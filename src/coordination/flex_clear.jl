# src/coordination/flex_clear.jl
#
# SEAM: the physics of the flexibility market. Given the baseline schedules and the truthful
# bids, the DSO clears the bids on the SAME network model as price-based coordination, reads
# the clearing prices and the congested hours through the gated pricing APIs, and each
# aggregator then re-solves to follow its activated target.
#
# STAGE 2 IS THE EXISTING WELFARE SOLVE. Each real aggregator is replaced by a pseudo-aggregator
# at the same bus, with the same power factor and inelastic demand, holding ONE `FlexBidDevice`:
# its injection is the baseline gross injection plus the accepted up blocks minus the accepted
# down blocks, and its "utility" is minus the accepted bid cost. `solve_welfare` then maximises
# −(bid cost) − λ₀ᵀ p_import over the same feeder, the same power-flow formulation, the same
# `close_balance!` seam and the same SOCP exactness gate as the DADP run. There is no new
# network formulation, and the clearing price is the dual of the nodal active balance, read
# only after the gate through `settlement_input`.
#
# REACTIVE POWER IS HELD AT −Pdc·tanφ. The pseudo-device returns no `q_inject` and is not a
# flexible load, so the aggregator roll-up writes only the inelastic reactive draw −Pdc·tanφ at
# each bus. This is the reactive model of the AC feasibility check and the default reactive
# model of the DSO subproblem, so the stage-2 SOCP and the AC verdict see the same q. Holding
# the full baseline q instead, including the flexible-load draw p·tanφ, would make stage 2
# infeasible for reasons unrelated to the flex product (on IEEE-13 that draw is two orders of
# magnitude above the head-branch rating). The flex product is ACTIVE power only. A constant
# reactive injection (`FixedCapacitor`) is not represented by the pseudo-device, so populations
# that contain one are refused before any solve.
#
# DELIVERY. Bids are hour-separable, but the devices behind them are not (state of charge,
# deferrable energy, thermal state), so the activated targets b + Δ need not be jointly
# reachable. Each aggregator re-solves its own price-taker problem with an L1 exact-penalty
# tracking term; the delivered dispatch is what gets settled, and the per-hour shortfall
# |n − (b + Δ)| is reported, never hidden. The penalty is a modelling device, not money.
#
# HONESTY: every solver outcome is a status value (`ok`, `infeasible_redispatch`,
# `inexact_redispatch`, `error:<Type>`), never an exception; anything that is not a solver
# outcome (a malformed input, a broken invariant) still throws.

"""
    FLEX_CONGESTION_KAPPA

The congestion threshold of [`_congested_hours`](@ref), `1e-2`: an hour is congested when the
largest network component of the stage-2 clearing price (thermal congestion plus voltage drop)
exceeds this fraction of the wholesale price λ₀[t]. A definitional threshold, not a test
tolerance; the interval of thresholds that leave the classification unchanged is reported
alongside it.
"""
const FLEX_CONGESTION_KAPPA = 1e-2

"""
    FlexBidDevice(gross, up_q, up_m, dn_q, dn_g)
    FlexBidDevice(gross, bids::FlexBids)

The stage-2 pseudo-device of one aggregator: its bids as a divisible device. Internal.

  - `gross[t]` — the baseline gross device injection `b[t] + Pdc[t]` (length `T`);
  - `up_q`, `up_m` — `T × K` up-block widths and prices;
  - `dn_q`, `dn_g` — `T × K` down-block widths and values.

`contribute!` adds one bounded variable `u[t,k] ∈ [0, up_q[t,k]]` per OFFERED up block and one
`w[t,k] ∈ [0, dn_q[t,k]]` per offered down block (width `0.0` ⇒ no variable, the entry is the
constant `0`), and returns `p_inject[t] = gross[t] + Σ_k u[t,k] − Σ_k w[t,k]` with
`utility = −Σ m·u + Σ g·w`, minus the accepted bid cost. It returns no `q_inject` and keeps
the default traits (not a flexible load, no storage), so the aggregator writes the inelastic
reactive draw only.

Throws `ArgumentError` when the four matrices differ in size, `length(gross)` is not their row
count, any entry is non-finite, or any width is negative.
"""
struct FlexBidDevice <: AbstractDevice
    gross::Vector{Float64}
    up_q::Matrix{Float64}
    up_m::Matrix{Float64}
    dn_q::Matrix{Float64}
    dn_g::Matrix{Float64}

    function FlexBidDevice(
        gross::AbstractVector{<:Real},
        up_q::AbstractMatrix{<:Real},
        up_m::AbstractMatrix{<:Real},
        dn_q::AbstractMatrix{<:Real},
        dn_g::AbstractMatrix{<:Real},
    )
        sz = size(up_q)
        (size(up_m) == sz && size(dn_q) == sz && size(dn_g) == sz) || throw(
            ArgumentError(
                "FlexBidDevice: bid matrices differ in size (up_q $(size(up_q)), up_m " *
                "$(size(up_m)), dn_q $(size(dn_q)), dn_g $(size(dn_g))).",
            ),
        )
        length(gross) == sz[1] || throw(
            ArgumentError(
                "FlexBidDevice: gross has length $(length(gross)), expected $(sz[1]) (the " *
                "number of bid rows, one per hour).",
            ),
        )
        all(isfinite, gross) ||
            throw(ArgumentError("FlexBidDevice: gross has a non-finite entry."))
        for (name, M) in (("up_q", up_q), ("up_m", up_m), ("dn_q", dn_q), ("dn_g", dn_g))
            all(isfinite, M) ||
                throw(ArgumentError("FlexBidDevice: $name has a non-finite entry."))
        end
        (all(>=(0), up_q) && all(>=(0), dn_q)) ||
            throw(ArgumentError("FlexBidDevice: block widths must be non-negative."))
        return new(
            Float64[gross...],
            Matrix{Float64}(up_q),
            Matrix{Float64}(up_m),
            Matrix{Float64}(dn_q),
            Matrix{Float64}(dn_g),
        )
    end
end

FlexBidDevice(gross::AbstractVector{<:Real}, bids::FlexBids) =
    FlexBidDevice(gross, bids.up_q, bids.up_m, bids.dn_q, bids.dn_g)

"""
    contribute!(d::FlexBidDevice, ctx::ModelContext; T, kwargs...) -> (; vars, p_inject, utility)

Add the accepted-block variables of the bid pseudo-device to `ctx.model` (anonymous, so any
number of pseudo-aggregators share one model) and return the affine injection and the
negative accepted bid cost. `vars = (; u, w)` holds `T × K` matrices of affine expressions:
a variable for each offered block, the constant `0` for each absent one. Performs no solve.
"""
function contribute!(d::FlexBidDevice, ctx::ModelContext; T::Int, kwargs...)
    length(d.gross) == T || throw(
        ArgumentError(
            "FlexBidDevice: gross has length $(length(d.gross)), expected the horizon T=$T.",
        ),
    )
    m = ctx.model
    K = size(d.up_q, 2)
    u = AffExpr[zero(AffExpr) for _ in 1:T, _ in 1:K]
    w = AffExpr[zero(AffExpr) for _ in 1:T, _ in 1:K]
    utility = zero(QuadExpr)
    for t in 1:T, k in 1:K
        if d.up_q[t, k] > 0
            x = @variable(m, lower_bound = 0.0, upper_bound = d.up_q[t, k])
            u[t, k] = AffExpr(0.0, x => 1.0)
            add_to_expression!(utility, -d.up_m[t, k], x)
        end
        if d.dn_q[t, k] > 0
            y = @variable(m, lower_bound = 0.0, upper_bound = d.dn_q[t, k])
            w[t, k] = AffExpr(0.0, y => 1.0)
            add_to_expression!(utility, d.dn_g[t, k], y)
        end
    end
    p_inject = AffExpr[
        d.gross[t] + sum(u[t, k] for k in 1:K) - sum(w[t, k] for k in 1:K) for t in 1:T
    ]
    return (; vars = (; u, w), p_inject, utility)
end

# Internal: refuse a population with a constant reactive injection the pseudo-device cannot
# carry. Runs before any solve.
function _refuse_fixed_capacitor(aggs, who::AbstractString)
    for (k, a) in enumerate(aggs)
        for d in a.devices
            d isa FixedCapacitor && throw(
                ArgumentError(
                    "$who: aggregator[$k] (bus $(a.bus)) holds a FixedCapacitor; its constant " *
                    "reactive injection is not represented by the stage-2 bid pseudo-device " *
                    "(the flex product is active power only).",
                ),
            )
        end
    end
    return nothing
end

"""
    _stage2_aggregators(aggs, b, bids; T) -> Vector{Aggregator}

One pseudo-aggregator per real aggregator, in the SAME order (ascending buses, as
`settlement_input` requires): `Aggregator(a.bus, a.φ, [FlexBidDevice(b[k] + Pdc, bids[k])],
a.Pdc)`. Its net injection is therefore `b[k] + Δ`. Throws `ArgumentError` on length
mismatches, a non-ascending bus order, or a `FixedCapacitor` in the population.
"""
function _stage2_aggregators(
    aggs::AbstractVector{<:Aggregator},
    b::AbstractVector{<:AbstractVector{<:Real}},
    bids::AbstractVector{FlexBids};
    T::Int,
)
    n = length(aggs)
    n >= 1 || throw(ArgumentError("_stage2_aggregators: empty aggregator vector."))
    (length(b) == n && length(bids) == n) || throw(
        ArgumentError(
            "_stage2_aggregators: $n aggregators but $(length(b)) baselines and " *
            "$(length(bids)) bids.",
        ),
    )
    issorted([a.bus for a in aggs]) || throw(
        ArgumentError(
            "_stage2_aggregators: aggregator buses are not ascending; settlement_input " *
            "folds in bus order.",
        ),
    )
    _refuse_fixed_capacitor(aggs, "_stage2_aggregators")
    out = Vector{Aggregator}(undef, n)
    for (k, a) in enumerate(aggs)
        length(b[k]) == T || throw(
            ArgumentError(
                "_stage2_aggregators: baseline $k has length $(length(b[k])), expected T=$T.",
            ),
        )
        length(a.Pdc) >= T || throw(
            ArgumentError(
                "_stage2_aggregators: aggregator $k has Pdc length $(length(a.Pdc)) < T=$T.",
            ),
        )
        gross = Float64[b[k][t] + a.Pdc[t] for t in 1:T]
        dev = FlexBidDevice(gross, bids[k])
        out[k] = Aggregator(a.bus, a.φ, AbstractDevice[dev], a.Pdc)
    end
    return out
end

# Internal: the stage-2 solver-outcome → status mapping. Returns `(status, notes)` for a
# solver outcome and `nothing` for anything else (the caller rethrows).
function _redispatch_status(err)
    if err isa SolveFailedError &&
       err.termination_status in (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED)
        return "infeasible_redispatch", first(string(err.msg), 400)
    elseif err isa CertificateError && err.kind === :socp_exact
        return "inexact_redispatch", first(string(err.msg), 400)
    elseif err isa SolveFailedError || err isa CertificateError || err isa ConvergenceError
        return "error:" * string(nameof(typeof(err))), first(string(err.msg), 400)
    end
    return nothing
end

"""
    _redispatch(feeder, pf, stage2_aggs; T, λ₀, optimizer = nothing)
        -> (; status, notes, ctx2, input2, u, w, Δ, maxgap, max_wash)

The DSO redispatch: `solve_welfare(feeder, pf, stage2_aggs; T, λ₀, allow_export = true)`
over the bid pseudo-aggregators (see [`_stage2_aggregators`](@ref)), with the optimizer
forwarded only when one is given (`nothing` makes exactly the default call).

On success `status == "ok"` and:

  - `ctx2` is the solved, gated context and `input2 = settlement_input(ctx2; T, λ₀)`; its
    `prices` are the clearing prices π and its `bus_nets` the targets `b + Δ`. Its
    `bus_utilities` are −(bid cost), NOT device utility, and must never be read as such;
  - `u[k]`, `w[k]` are the accepted `T × K` up and down quantities of aggregator `k`, and
    `Δ[k][t] = Σ_k u − Σ_k w` its activated deviation;
  - `maxgap` is the SOCP cone gap recorded by the exactness gate (`NaN` on a cone-free
    formulation);
  - `max_wash` is the largest simultaneous up and down acceptance `min(Σu, Σw)` over
    aggregators and hours (zero up to solver noise when every bid–ask gap is positive).

Solver outcomes are statuses, never exceptions: an infeasible or infeasible-or-unbounded
solve is `"infeasible_redispatch"`, a refused SOCP exactness certificate is
`"inexact_redispatch"`, and any other `SolveFailedError`, `CertificateError` or
`ConvergenceError` is `"error:<Type>"`. Then `notes` holds the first 400 characters of the
message and every other field is `nothing`. Any other exception is rethrown.
"""
function _redispatch(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    stage2_aggs::AbstractVector{<:Aggregator};
    T::Int,
    λ₀,
    optimizer = nothing,
)
    local ctx2
    status = "ok"
    notes = ""
    try
        if optimizer === nothing
            ctx2, _, _ =
                solve_welfare(feeder, pf, stage2_aggs; T = T, λ₀ = λ₀, allow_export = true)
        else
            ctx2, _, _ = solve_welfare(
                feeder,
                pf,
                stage2_aggs;
                T = T,
                λ₀ = λ₀,
                allow_export = true,
                optimizer = optimizer,
            )
        end
    catch err
        mapped = _redispatch_status(err)
        mapped === nothing && rethrow()
        status, notes = mapped
    end
    if status != "ok"
        return (;
            status,
            notes,
            ctx2 = nothing,
            input2 = nothing,
            u = nothing,
            w = nothing,
            Δ = nothing,
            maxgap = nothing,
            max_wash = nothing,
        )
    end

    input2 = settlement_input(ctx2; T = T, λ₀ = λ₀)

    n = length(stage2_aggs)
    u = Vector{Matrix{Float64}}(undef, n)
    w = Vector{Matrix{Float64}}(undef, n)
    Δ = Vector{Vector{Float64}}(undef, n)
    seen = Dict{Int, Int}()
    max_wash = 0.0
    for (k, a) in enumerate(stage2_aggs)
        # each pseudo-aggregator holds exactly one device, so the i-th aggregator at a bus
        # owns the i-th entry of that bus's device-variable stash
        i = get(seen, a.bus, 0) + 1
        seen[a.bus] = i
        v = ctx2.agg_device_vars[a.bus][i]
        u[k] = Float64[value(x) for x in v.u]
        w[k] = Float64[value(x) for x in v.w]
        Δ[k] = Float64[sum(u[k][t, :]) - sum(w[k][t, :]) for t in 1:T]
        for t in 1:T
            max_wash = max(max_wash, min(sum(u[k][t, :]), sum(w[k][t, :])))
        end
    end
    maxgap = Float64(get(ctx2.meta, :socp_maxgap, NaN))
    return (; status, notes, ctx2, input2, u, w, Δ, maxgap, max_wash)
end

"""
    _congested_hours(ctx2, λ₀; T, κ = FLEX_CONGESTION_KAPPA)
        -> (; congested::Vector{Bool}, scores, kappa_lo, kappa_hi)

Classify the hours of a solved, gated stage-2 context as congested. With the four-way split
`d = decompose_dlmp(ctx2)`, the network score of hour `t` is

    s_t = max_j (|d.congestion[j, t]| + |d.drop[j, t]|) / λ₀[t],

the largest thermal-congestion plus voltage-drop component of any nodal clearing price, as a
fraction of the wholesale price; the energy and cone (loss) components are excluded. Hour `t`
is congested iff `s_t > κ`. `kappa_lo` is the largest score among uncongested hours (`0.0`
when there is none) and `kappa_hi` the smallest score among congested hours (`+Inf` when there
is none): every threshold in `[kappa_lo, kappa_hi)` gives the same classification, so the
interval measures how robust the definition is on this clear. Requires a `ConvexBranchFlow`
context (the split needs its constraint handles) and a positive `λ₀[t]`.
"""
function _congested_hours(
    ctx2::ModelContext,
    λ₀::AbstractVector{<:Real};
    T::Int,
    κ::Real = FLEX_CONGESTION_KAPPA,
)
    length(λ₀) >= T ||
        throw(ArgumentError("_congested_hours: λ₀ has length $(length(λ₀)) < T=$T."))
    all(t -> isfinite(λ₀[t]) && λ₀[t] > 0, 1:T) || throw(
        ArgumentError("_congested_hours: λ₀ must be finite and positive (it normalises)."),
    )
    d = decompose_dlmp(ctx2)
    scores = Float64[
        maximum(abs(d.congestion[j, t]) + abs(d.drop[j, t]) for j in axes(d.congestion, 1)) / λ₀[t] for t in 1:T
    ]
    congested = Bool[s > κ for s in scores]
    kappa_lo = maximum((scores[t] for t in 1:T if !congested[t]); init = 0.0)
    kappa_hi = minimum((scores[t] for t in 1:T if congested[t]); init = Inf)
    return (; congested, scores, kappa_lo, kappa_hi)
end
