# src/settlement/run_inputs.jl
#
# SEAM: settlement run-input adapters — solved-run output → SettlementInput.
#
# ADAPTERS ONLY: price/dispatch EXTRACTION stays owned by the solved paths — the
# centralized leg reads through `extract_dlmp` (which carries the SOCP-exactness gate,
# never bypassed here) and the `ctx.meta[:agg_net]`/`:p_import` stashes; the ADMM leg
# reads the `dadp` matrix and the PAR-05 additive keys (`agr_dispatch`/`agr_utility`/
# `agr_prices`), which exist ONLY on the `:converged` path. This file packs those
# published outputs into a `SettlementInput` for `build_settlement_ledger`.
# `src/pricing/` and `src/admm/` are GOLDEN — consumed, never modified.
#
# SIGN/LAYOUT conventions preserved (admm_state.jl `_agr_result_keys`): `agr_prices[j]`
# and the `dadp` rows are the PUBLISHED per-slot prices (the internal ADMM `st.λ` is
# NEGATED — never settle from it); `net` quantities are net INJECTIONS (`net > 0` ⇒
# export), so an exporter EARNS `price·net` and an importer PAYS.

export SettlementInput, settlement_input

"""
    SettlementInput

Typed NamedTuple packing ONE solved run's published settlement numbers for
[`build_settlement_ledger`](@ref): `(; prices, bus_nets, bus_utilities, p_import, λ₀, buses, T, source)` where

  - `prices` — `(length(buses) × T)` PUBLISHED prices, ascending-bus rows;
  - `bus_nets` — `Dict{Int,Vector{Float64}}` per-aggregator net INJECTION per hour
    (`net > 0` ⇒ export);
  - `bus_utilities` — `Dict{Int,Float64}` per-aggregator device utility;
  - `p_import` — length-`T` frontier import at the root (free-sign with export);
  - `λ₀` — length-`T` wholesale/MEM price profile;
  - `buses` — ascending, unique aggregator buses;
  - `source` — `:centralized` (a solved `solve_welfare` `ModelContext`) or `:admm`
    (a converged `solve_admm` result NamedTuple).
"""
const SettlementInput = NamedTuple{
    (:prices, :bus_nets, :bus_utilities, :p_import, :λ₀, :buses, :T, :source),
    Tuple{
        Matrix{Float64},
        Dict{Int, Vector{Float64}},
        Dict{Int, Float64},
        Vector{Float64},
        Vector{Float64},
        Vector{Int},
        Int,
        Symbol,
    },
}

# Internal: fail-loud finite guard on EXTRACTED numbers (V5 input validation) — a solver
# NaN/Inf must throw at the adapter boundary instead of silently poisoning every
# downstream settlement/equity artifact.
function _finite_or_throw_adapt(xs, who::AbstractString, name::AbstractString)
    for (k, x) in pairs(xs)
        isfinite(x) || throw(
            ArgumentError(
                "settlement_input: extracted $name ($who) contains a non-finite value " *
                "at [$k] ($x) — refusing to settle on solver NaN/Inf output.",
            ),
        )
    end
    return nothing
end

"""
    settlement_input(ctx::ModelContext; T = _require_T(ctx), λ₀ = nothing) -> SettlementInput

Centralized adapter: read a solved `solve_welfare` [`ModelContext`](@ref) into a
[`SettlementInput`](@ref), mirroring `welfare_accounting`'s extraction sequence exactly
(welfare.jl:99-152) so the ledger's merchandising surplus can be cross-checked against
`welfare_accounting(ctx).dso`:

  - guards: `ctx.meta` must carry `:agg_net` AND `:p_import` (a loud `ArgumentError`
    naming the missing key otherwise — this is not a solved welfare ctx), `:agg_net`
    must be non-empty, and `T` must not exceed the solved horizon;
  - prices: `extract_dlmp(ctx)` — INHERITS the exactness gate (an ungated SOCP ctx is
    refused here exactly as `welfare_accounting` refuses it); rows taken at the
    aggregator buses, `λ₀` defaulting to the root row `[λ[root, t] for t in 1:T]` (the
    thesis energy-component convention);
  - quantities: per-entry `value(entry.net[t])` / `value(entry.utility)` reads IN
    `ctx.meta[:agg_net]` ENTRY ORDER — the order-preservation is load-bearing for the
    merchandising-surplus cross-check's summation association (the stash is ascending in
    practice; a non-ascending stash throws so the association argument stays honest);
  - `p_import = value.(ctx.meta[:p_import])` (free-sign priced frontier).

All extracted numbers are finite-guarded at this boundary. Pass `λ₀` explicitly to
settle at the wholesale profile the run was solved with (same convention as
`welfare_accounting`).
"""
function settlement_input(ctx::ModelContext; T::Int = _require_T(ctx), λ₀ = nothing)
    for key in (:agg_net, :p_import)
        haskey(ctx.meta, key) || throw(
            ArgumentError(
                "settlement_input: ctx.meta is missing :$key — this is not a solved " *
                "solve_welfare ModelContext carrying the surplus stash " *
                "(thesis 3.38/3.46/3.47).",
            ),
        )
    end
    isempty(ctx.meta[:agg_net]) && throw(
        ArgumentError(
            "settlement_input: ctx.meta[:agg_net] is empty — a settlement needs at least " *
            "one aggregator; this is not a solved solve_welfare ModelContext.",
        ),
    )

    feeder = _require_feeder(ctx)
    root = feeder.root

    # Per-node DADP prices (runs the exactness gate; refuses an ungated SOCP ctx).
    λ = extract_dlmp(ctx)                              # (N, Tfull) matrix
    Tfull = size(λ, 2)
    T <= Tfull || throw(
        ArgumentError("settlement_input: T=$T exceeds the solved horizon Tfull=$Tfull"),
    )

    # MEM/wholesale price λ₀: the passed profile, else the root DADP row (thesis energy
    # component = dual(balance_p[root, t]); = λ₀ at the priced-frontier optimum).
    # GUARD BEFORE INDEX: a too-short passed λ₀ must raise the documented loud
    # ArgumentError, never a raw BoundsError from the comprehension below (the old
    # post-build length check was DEAD CODE — λ0 is built with exactly T elements
    # whenever the indexing succeeded; the ADMM adapter below already had this order).
    λ₀ === nothing || length(λ₀) >= T ||
        throw(ArgumentError("settlement_input: λ₀ has length $(length(λ₀)) < T=$T"))
    λ0 =
        λ₀ === nothing ? Float64[λ[root, t] for t in 1:T] :
        Float64[float(λ₀[t]) for t in 1:T]
    λ0 = λ0[1:T]

    # Per-entry reads IN ctx.meta[:agg_net] ENTRY ORDER (== ascending-bus order in
    # practice; asserted so the ledger's bus-order fold matches welfare_accounting's
    # entry-order fold — the MS cross-check's association argument stays honest).
    entries = ctx.meta[:agg_net]
    buses = Int[entry.bus for entry in entries]
    issorted(buses) || throw(
        ArgumentError(
            "settlement_input: ctx.meta[:agg_net] entry buses are not ascending " *
            "($buses) — the ledger folds in bus order, so a non-ascending stash would " *
            "break the welfare_accounting cross-check's summation association.",
        ),
    )
    bus_nets = Dict{Int, Vector{Float64}}()
    bus_utilities = Dict{Int, Float64}()
    for entry in entries
        b = entry.bus
        (1 <= b <= size(λ, 1)) || throw(
            ArgumentError("settlement_input: aggregator bus=$b outside 1:$(size(λ, 1))"),
        )
        bus_nets[b] = Float64[value(entry.net[t]) for t in 1:T]
        bus_utilities[b] = Float64(value(entry.utility))
    end

    # Priced-frontier import p_import[t] (free-sign with allow_export).
    p_imp = Float64.(value.(ctx.meta[:p_import]))
    length(p_imp) >= T || throw(
        ArgumentError(
            "settlement_input: p_import has length $(length(p_imp)), expected at least T=$T.",
        ),
    )
    p_imp = p_imp[1:T]

    prices = λ[buses, 1:T]
    _finite_or_throw_adapt(prices, "centralized", "prices")
    for j in buses
        _finite_or_throw_adapt(bus_nets[j], "centralized", "bus_nets[$j]")
    end
    for (j, u) in bus_utilities
        isfinite(u) || throw(
            ArgumentError(
                "settlement_input: extracted utility (centralized, bus $j) is non-finite ($u).",
            ),
        )
    end
    _finite_or_throw_adapt(p_imp, "centralized", "p_import")
    _finite_or_throw_adapt(λ0, "centralized", "λ₀")

    return SettlementInput((
        prices = prices,
        bus_nets = bus_nets,
        bus_utilities = bus_utilities,
        p_import = p_imp,
        λ₀ = λ0,
        buses = buses,
        T = T,
        source = :centralized,
    ))
end

"""
    settlement_input(r::NamedTuple; λ₀ = nothing) -> SettlementInput

ADMM adapter: read a CONVERGED `solve_admm` result NamedTuple into a
[`SettlementInput`](@ref). Loud `ArgumentError` (never a silent divide) unless
`get(r, :status, :missing) == :converged` — the per-aggregator additive keys
(`agr_dispatch`/`agr_utility`/`agr_prices`) exist ONLY on the `:converged` path and a
`:budget_exceeded` stop carries NO certified price (Pitfall 4: settling an
unconverged iterate as if real is repudiation of the honesty policy).

`λ₀` is REQUIRED here (the result NamedTuple does not carry it): pass the SAME
wholesale profile given to `solve_admm`. Prices are the PUBLISHED `dadp` rows in
ascending load-bus order, cross-checked against `agr_prices[j]` (the pinned
`agr_prices[j] == dadp[row_of_j, :]` layout invariant — a mismatch refuses loudly);
quantities are `agr_dispatch[j]` net injections; `p_import` reads the DSO-OPT stash
`r.dso_ctx.meta[:p_import]`. All extracted numbers are finite-guarded.
"""
function settlement_input(r::NamedTuple; λ₀ = nothing)
    status = get(r, :status, :missing)
    status == :converged || throw(
        ArgumentError(
            "settlement_input: ADMM result status is $(repr(status)) — the per-aggregator " *
            "additive keys (agr_dispatch/agr_utility/agr_prices) exist ONLY on the " *
            ":converged path; settle a converged run (a :budget_exceeded stop carries NO " *
            "certified price).",
        ),
    )
    for key in (:dadp, :agr_dispatch, :agr_utility, :agr_prices, :dso_ctx)
        haskey(r, key) || throw(
            ArgumentError(
                "settlement_input: result is missing :$key — not a solve_admm result " *
                "NamedTuple (the converged path always carries it).",
            ),
        )
    end
    r.dadp === nothing && throw(
        ArgumentError(
            "settlement_input: result carries dadp = nothing — malformed result (the " *
            ":converged path always publishes the DADP price matrix).",
        ),
    )
    λ₀ === nothing && throw(
        ArgumentError(
            "settlement_input: ADMM results do not carry λ₀ — pass the SAME wholesale " *
            "price profile given to solve_admm: settlement_input(r; λ₀ = ...).",
        ),
    )

    isempty(r.agr_dispatch) && throw(
        ArgumentError(
            "settlement_input: r.agr_dispatch is empty — a settlement needs at least " *
            "one aggregator.",
        ),
    )
    buses = sort!(collect(keys(r.agr_dispatch)))
    T = length(r.agr_dispatch[buses[1]])
    T >= 1 || throw(ArgumentError("settlement_input: T=$T must be at least 1."))
    length(λ₀) >= T ||
        throw(ArgumentError("settlement_input: λ₀ has length $(length(λ₀)) < T=$T"))
    λ0 = Float64[float(λ₀[t]) for t in 1:T]

    size(r.dadp, 1) >= length(buses) || throw(
        ArgumentError(
            "settlement_input: dadp has $(size(r.dadp, 1)) rows but the result carries " *
            "$(length(buses)) aggregator buses.",
        ),
    )
    size(r.dadp, 2) >= T || throw(
        ArgumentError(
            "settlement_input: dadp has $(size(r.dadp, 2)) columns, expected at least T=$T.",
        ),
    )

    prices = Matrix{Float64}(undef, length(buses), T)
    bus_nets = Dict{Int, Vector{Float64}}()
    bus_utilities = Dict{Int, Float64}()
    for (i, j) in enumerate(buses)
        for key in (:agr_dispatch, :agr_utility, :agr_prices)
            haskey(getproperty(r, key), j) || throw(
                ArgumentError(
                    "settlement_input: $key is missing bus $j — the per-aggregator keys " *
                    "are keyed over the ascending load_nodes.",
                ),
            )
        end
        length(r.agr_dispatch[j]) == T || throw(
            ArgumentError(
                "settlement_input: agr_dispatch[$j] has length " *
                "$(length(r.agr_dispatch[j])), expected T=$T.",
            ),
        )
        row = Float64.(r.dadp[i, 1:T])
        published = Float64.(r.agr_prices[j])
        # Pinned layout invariant (admm_state.jl _agr_result_keys): the published price
        # row for bus j IS the bus-j row of dadp. A mismatch is a loud refusal, never a
        # silent pick of one of the two.
        published == row || throw(
            ArgumentError(
                "settlement_input: agr_prices[$j] != dadp[$i, 1:T] — the pinned layout " *
                "invariant (agr_prices[j] == dadp[row_of_j, :], _agr_result_keys) is " *
                "VIOLATED; refusing to settle on inconsistent published prices.",
            ),
        )
        prices[i, :] .= row
        bus_nets[j] = Float64.(r.agr_dispatch[j])
        bus_utilities[j] = Float64(r.agr_utility[j])
    end

    haskey(r.dso_ctx.meta, :p_import) || throw(
        ArgumentError(
            "settlement_input: r.dso_ctx.meta is missing :p_import — this is not a " *
            "converged solve_admm dso_ctx (build_dso_opt stashes the frontier exchange).",
        ),
    )
    p_imp = Float64.(value.(r.dso_ctx.meta[:p_import]))
    length(p_imp) >= T || throw(
        ArgumentError(
            "settlement_input: p_import has length $(length(p_imp)), expected at least T=$T.",
        ),
    )
    p_imp = p_imp[1:T]

    _finite_or_throw_adapt(prices, "admm", "prices")
    for j in buses
        _finite_or_throw_adapt(bus_nets[j], "admm", "agr_dispatch[$j]")
    end
    for (j, u) in bus_utilities
        isfinite(u) || throw(
            ArgumentError(
                "settlement_input: extracted agr_utility (admm, bus $j) is non-finite ($u).",
            ),
        )
    end
    _finite_or_throw_adapt(p_imp, "admm", "p_import")
    _finite_or_throw_adapt(λ0, "admm", "λ₀")

    return SettlementInput((
        prices = prices,
        bus_nets = bus_nets,
        bus_utilities = bus_utilities,
        p_import = p_imp,
        λ₀ = λ0,
        buses = buses,
        T = T,
        source = :admm,
    ))
end

"""
    settlement_input(input::SettlementInput) -> SettlementInput

Identity method: a [`SettlementInput`](@ref) is already a settlement input (lets
callers pipe either a solved run or a packed input through the same seam).
"""
settlement_input(input::SettlementInput) = input

"""
    build_settlement_ledger(input::SettlementInput; households = nothing) -> SettlementLedger

Adapter overload: settle a packed [`SettlementInput`](@ref) via the primitive
[`build_settlement_ledger`](@ref) constructor, preserving `input`'s bus order (the
centralized adapter has already asserted the `ctx.meta[:agg_net]` stash is ascending,
so entry order == bus order and the `welfare_accounting` cross-check's summation
association is preserved). `households` is forwarded unchanged — a Vector of
`(; house_id, bus, net, utility)` NamedTuples, or `nothing`.
"""
function build_settlement_ledger(input::SettlementInput; households = nothing)
    return build_settlement_ledger(
        input.prices,
        input.bus_nets,
        input.bus_utilities,
        input.p_import,
        input.λ₀,
        input.buses;
        T = input.T,
        source = input.source,
        households = households,
    )
end
