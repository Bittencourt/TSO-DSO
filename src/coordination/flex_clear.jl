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
# reachable. Each aggregator re-solves its own price-taker problem with an L1 penalty
# tracking term (exact only when its weight exceeds the tracking multiplier, which the weight
# rule does not guarantee; see `_flex_physics`); the delivered dispatch is what gets settled,
# and the per-hour shortfall |n − (b + Δ)| is reported, never hidden. The penalty is a
# modelling device, not money.
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
`settlement_input` requires). Pseudo-aggregator `k` keeps the bus, `φ` and `Pdc` of
`aggs[k]` and holds the single device `FlexBidDevice(b[k] + Pdc, bids[k])`, so its net
injection is `b[k] + Δ`. Throws `ArgumentError` on length mismatches, a non-ascending
bus order, or a `FixedCapacitor` in the population.
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
    status = "ok"
    notes = ""
    # The solve is the value of the try expression (`nothing` on a mapped solver outcome),
    # so `ctx2` is always bound.
    ctx2 = try
        if optimizer === nothing
            solve_welfare(feeder, pf, stage2_aggs; T = T, λ₀ = λ₀, allow_export = true)[1]
        else
            solve_welfare(
                feeder,
                pf,
                stage2_aggs;
                T = T,
                λ₀ = λ₀,
                allow_export = true,
                optimizer = optimizer,
            )[1]
        end
    catch err
        mapped = _redispatch_status(err)
        mapped === nothing && rethrow()
        status, notes = mapped
        nothing
    end
    if ctx2 === nothing
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
        maximum(
            abs(d.congestion[j, t]) + abs(d.drop[j, t]) for j in axes(d.congestion, 1)
        ) / λ₀[t] for t in 1:T
    ]
    congested = Bool[s > κ for s in scores]
    kappa_lo = maximum((scores[t] for t in 1:T if !congested[t]); init = 0.0)
    kappa_hi = minimum((scores[t] for t in 1:T if congested[t]); init = Inf)
    return (; congested, scores, kappa_lo, kappa_hi)
end

"""
    _deliver(agg, price, target; T, weight, τ_batt = 1e-3)
        -> (; net, utility, battery_certificate, battery_message, shortfall)

The delivery re-solve of one aggregator: its own price-taker problem at the baseline tariff
`price`, plus an L1 exact-penalty term that pulls its net injection toward the activated
target `target = b + Δ`:

    max  U(devices) + Σ_t price[t]·pag[t] − weight·Σ_t s[t]
    s.t. s[t] ≥ pag[t] − target[t],  s[t] ≥ target[t] − pag[t],  s[t] ≥ 0.

A fresh model per call, one solve, gated by `assert_solved!(model; dual = false)`. When
`weight` exceeds the largest multiplier of `pag[t] == target[t]`, the penalty is exact: the
target is met whenever the devices can jointly reach it. That multiplier is the device's
marginal utility at the target minus the tariff, bounded by the slope of the device value
function there and not by any price, so no price-based weight is guaranteed to exceed it.
`shortfall[t] = |net[t] − target[t]|` is the part of the activation that was not delivered,
either because the devices cannot reach the target (the bids were hour-separable, the
devices are not) or because `weight` is below the multiplier; it is returned, never hidden.

The penalty is a MODELLING DEVICE, not money: it is never booked in a settlement ledger, and
`utility` is the device utility of the delivered dispatch alone. `net`, `utility`,
`battery_certificate` and `battery_message` have the meaning and names of
[`price_taker_dispatch`](@ref); the battery complementarity certificate is reported
(`:ok`, `:refused` or `:not_checked`), never thrown.

Throws `ArgumentError` on a `price` or `target` of the wrong length or with a non-finite
entry, or a `weight` that is not positive and finite.
"""
function _deliver(
    agg::Aggregator,
    price::AbstractVector{<:Real},
    target::AbstractVector{<:Real};
    T::Int,
    weight::Real,
    τ_batt::Real = 1e-3,
)
    T >= 1 || throw(ArgumentError("_deliver: T=$T must be at least 1."))
    (length(price) == T && length(target) == T) || throw(
        ArgumentError(
            "_deliver: price has length $(length(price)) and target $(length(target)), " *
            "expected T=$T.",
        ),
    )
    (all(isfinite, price) && all(isfinite, target)) ||
        throw(ArgumentError("_deliver: price and target must be finite."))
    (isfinite(weight) && weight > 0) ||
        throw(ArgumentError("_deliver: weight=$weight must be positive and finite."))

    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.T = T
    res = contribute!(agg, ctx; T = T)
    pag = @variable(model, [1:T])
    @constraint(model, [t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    s = @variable(model, [1:T], lower_bound = 0.0)
    @constraint(model, [t = 1:T], s[t] >= pag[t] - target[t])
    @constraint(model, [t = 1:T], s[t] >= target[t] - pag[t])
    @objective(
        model,
        Max,
        ctx.objective + sum(price[t] * pag[t] for t in 1:T) - weight * sum(s)
    )

    assert_solved!(model; dual = false)

    net = Float64[value(pag[t]) for t in 1:T]
    utility = value(ctx.objective)
    shortfall = Float64[abs(net[t] - target[t]) for t in 1:T]

    # Battery complementarity as a recorded status (the price-taker report semantics).
    has_battery = any(
        haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q) for
        varlist in values(ctx.agg_device_vars) for v in varlist
    )
    battery_certificate = :not_checked
    battery_message = ""
    if has_battery
        battery_certificate = :ok
        try
            assert_battery_complementarity!(ctx; τ = τ_batt, T = T, on_violation = :error)
        catch err
            err isa CertificateError || rethrow()
            battery_certificate = :refused
            battery_message = err.msg
        end
    end

    return (; net, utility, battery_certificate, battery_message, shortfall)
end

# Internal: a stage-1 or delivery solver outcome → `(status, notes)` with the stage prefix;
# `nothing` for anything that is not a solver outcome (the caller rethrows).
function _physics_error_status(err, prefix::AbstractString)
    (err isa SolveFailedError || err isa CertificateError || err isa ConvergenceError) ||
        return nothing
    return "error:" * string(nameof(typeof(err))), first(prefix * string(err.msg), 400)
end

# Internal: the total delivery shortfall of every aggregator re-delivered at `weight`, the
# sensitivity diagnostic of the tracking weight. Returns `(total, "")`, or `(missing, notes)`
# on a solver outcome (a `SolveFailedError`, `CertificateError` or `ConvergenceError`), so a
# failed diagnostic never fails the leg. Anything else rethrows.
function _shortfall_diagnostic(aggs, p, targets; T::Int, weight::Real, τ_batt::Real)
    try
        total = 0.0
        for (k, a) in enumerate(aggs)
            total += sum(_deliver(a, p, targets[k]; T, weight, τ_batt).shortfall)
        end
        return total, ""
    catch err
        mapped = _physics_error_status(
            err,
            "delivery at 10w (sensitivity diagnostic only; the primary delivery is kept): ",
        )
        mapped === nothing && rethrow()
        return missing, mapped[2]
    end
end

# Internal: per-aggregator dispatch results folded into one record with certificate counts.
function _dispatch_record(ds)
    certs = Symbol[d.battery_certificate for d in ds]
    return (;
        net = Vector{Float64}[d.net for d in ds],
        utility = Float64[d.utility for d in ds],
        battery_certificate = certs,
        battery_message = String[d.battery_message for d in ds],
        n_battery_ok = count(==(:ok), certs),
        n_battery_refused = count(==(:refused), certs),
        n_battery_not_checked = count(==(:not_checked), certs),
    )
end

# Internal: a failure of the congested-hour classifier on a solved, gated stage 2 →
# `(status, notes)` with the `"congestion: "` prefix. The DLMP split's sum-to-price check
# raises an `ErrorException` whose message starts with `_DLMP_RECON_FAIL`, the prefix that
# `decompose_dlmp` itself uses; it becomes `"error:dlmp_split"`. Other `decompose_dlmp`
# errors (a malformed tree or a missing handle, both `ArgumentError`) are not matched. A
# solver-outcome type maps as in `_physics_error_status`. `nothing` for anything else (the
# caller rethrows).
function _congestion_status(err)
    if err isa ErrorException && startswith(err.msg, _DLMP_RECON_FAIL)
        return "error:dlmp_split", first("congestion: " * err.msg, 400)
    end
    return _physics_error_status(err, "congestion: ")
end

# Internal: the physics record, every field present; unknown fields are `nothing`.
function _physics_record(;
    status,
    notes = "",
    price,
    baseline = nothing,
    bids = nothing,
    u = nothing,
    w = nothing,
    Δ = nothing,
    π = nothing,
    congested = nothing,
    congestion_scores = nothing,
    kappa_lo = nothing,
    kappa_hi = nothing,
    targets = nothing,
    delivered = nothing,
    shortfall = nothing,
    shortfall_total = nothing,
    shortfall_10w_total = nothing,
    weight = nothing,
    maxgap = nothing,
    p_import_stage2 = nothing,
    max_wash = nothing,
    n_probe_solves = 0,
    n_probe_failed = 0,
    bid_repair_max = nothing,
    min_bid_ask_gap = nothing,
    t_start,
)
    wall_s = (time_ns() - t_start) / 1e9
    return (;
        status,
        notes,
        price,
        baseline,
        bids,
        u,
        w,
        Δ,
        π,
        congested,
        congestion_scores,
        kappa_lo,
        kappa_hi,
        targets,
        delivered,
        shortfall,
        shortfall_total,
        shortfall_10w_total,
        weight,
        maxgap,
        p_import_stage2,
        max_wash,
        n_probe_solves,
        n_probe_failed,
        bid_repair_max,
        min_bid_ask_gap,
        wall_s,
    )
end

"""
    _flex_physics(feeder, pf, aggs, price; T, λ₀, n_blocks, optimizer = nothing,
                  τ_batt = 1e-3) -> NamedTuple

The physics of one flexibility-market clear, for one (baseline price, `n_blocks`) pair. The
payment rules consume this record and never re-solve, so the dispatch is identical between
them by construction.

 1. **Stage 1.** `price_taker_dispatches(aggs, price; T, τ_batt)` gives each aggregator's
    baseline `b`, its utility and its battery certificate (`baseline`).
 2. **Bids.** [`flex_bids`](@ref) around each baseline (`bids`; the probe counts, the largest
    monotone repair and the smallest bid–ask gap are summed or reduced over aggregators).
 3. **Stage 2.** [`_redispatch`](@ref) over [`_stage2_aggregators`](@ref): the accepted
    blocks `u`, `w`, the deviations `Δ`, the clearing prices `π` (one length-`T` vector per
    aggregator, read through `settlement_input`), the SOCP `maxgap`, `max_wash` and the
    stage-2 import `p_import_stage2`; then [`_congested_hours`](@ref) (`congested`,
    `congestion_scores`, `kappa_lo`, `kappa_hi`).
 4. **Delivery.** `targets = b + Δ`, and [`_deliver`](@ref) per aggregator at the baseline
    tariff with `weight = 10·max(max|π|, maximum(λ₀), max|price|)`: ten times the largest
    price in play. This is a documented heuristic, fixed and not tuned, and NOT a proof that
    the penalty is exact: the tracking multiplier is a device marginal utility, which a steep
    utility or a coupled device near the edge of its reachable set can push above any price
    (see [`_deliver`](@ref)). Its adequacy is measured instead, by a second delivery at
    `10·weight` whose only output is `shortfall_10w_total`. A shortfall that is unchanged
    between `weight` and `10·weight` is insensitive to the weight over that tenfold range;
    it is not thereby proven to be the infinite-weight value, so it is reported as an upper
    bound on the hour-separability loss, with the sensitivity beside it. That second delivery is a diagnostic: if one
    of its solves ends in a solver outcome, `shortfall_10w_total` is `missing`, the reason
    goes to `notes`, and the clear stays `"ok"` with the primary delivery. `delivered` holds
    the nets, utilities and battery certificates (with counts), `shortfall` the
    per-(aggregator, hour) shortfall and `shortfall_total` its sum.

`wall_s` is the wall time of the whole clear. Every solver outcome is a status: a stage-2
outcome as in [`_redispatch`](@ref), and a stage-1 or delivery `SolveFailedError`,
`CertificateError` or `ConvergenceError` as `"error:<Type>"` with `notes` prefixed
`"baseline: "` or `"delivery: "`. A failure of the congested-hour split after a successful
stage 2 (its sum-to-price reconstruction check) is `"error:dlmp_split"` with `notes` prefixed
`"congestion: "`. On any status other than `"ok"` the fields that were not computed are
`nothing` (the probe counts stay those already known). Anything else throws.

Throws `ArgumentError` before any solve on an empty population, a `price` or `λ₀` of the
wrong length or with a non-finite entry, a `λ₀` with a non-positive entry (it normalises the
congestion score), `n_blocks < 1`, a power-flow formulation other than `ConvexBranchFlow`
(the congested-hour split reads its constraint duals), aggregator buses that are not
ascending, or a `FixedCapacitor` in the population.
"""
function _flex_physics(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggs::AbstractVector{<:Aggregator},
    price::AbstractVector{<:Real};
    T::Int,
    λ₀,
    n_blocks::Int,
    optimizer = nothing,
    τ_batt::Real = 1e-3,
)
    t_start = time_ns()
    isempty(aggs) && throw(ArgumentError("_flex_physics: empty aggregator vector."))
    length(price) == T || throw(
        ArgumentError("_flex_physics: price has length $(length(price)), expected T=$T."),
    )
    all(isfinite, price) ||
        throw(ArgumentError("_flex_physics: price has a non-finite entry."))
    (length(λ₀) == T && all(isfinite, λ₀)) ||
        throw(ArgumentError("_flex_physics: λ₀ must have length T=$T with finite entries."))
    all(>(0), λ₀) || throw(
        ArgumentError(
            "_flex_physics: λ₀ must be positive in every hour (it normalises the " *
            "congestion score of the clearing prices); got $(collect(λ₀)).",
        ),
    )
    n_blocks >= 1 ||
        throw(ArgumentError("_flex_physics: n_blocks=$n_blocks must be at least 1."))
    pf isa ConvexBranchFlow || throw(
        ArgumentError(
            "_flex_physics: the flexibility market needs ConvexBranchFlow (the congested-" *
            "hour split reads its cone, voltage-drop, exactness-copy and thermal-limit " *
            "duals); got $(typeof(pf)).",
        ),
    )
    issorted([a.bus for a in aggs]) || throw(
        ArgumentError(
            "_flex_physics: aggregator buses $([a.bus for a in aggs]) are not ascending; " *
            "the stage-2 settlement folds in bus order.",
        ),
    )
    _refuse_fixed_capacitor(aggs, "_flex_physics")
    p = Float64[price[t] for t in 1:T]
    λ = Float64[λ₀[t] for t in 1:T]

    # 1. stage 1: the baseline at the given tariff
    local stage1
    try
        stage1 = price_taker_dispatches(aggs, p; T = T, τ_batt = τ_batt)
    catch err
        mapped = _physics_error_status(err, "baseline: ")
        mapped === nothing && rethrow()
        return _physics_record(; status = mapped[1], notes = mapped[2], price = p, t_start)
    end
    baseline = _dispatch_record(stage1)
    b = baseline.net

    # 2. truthful bids around each baseline (status-gated inside; never throws on a solve)
    bids = FlexBids[
        flex_bids(a, b[k]; T = T, n_blocks = n_blocks) for (k, a) in enumerate(aggs)
    ]
    n_probe_solves = sum(fb.n_solves for fb in bids)
    n_probe_failed = sum(fb.n_failed for fb in bids)
    bid_repair_max = maximum(fb.repair_max for fb in bids)
    min_bid_ask_gap = minimum(fb.min_bid_ask_gap for fb in bids)
    known = (;
        price = p,
        baseline,
        bids,
        n_probe_solves,
        n_probe_failed,
        bid_repair_max,
        min_bid_ask_gap,
        t_start,
    )

    # 3. stage 2: the DSO redispatch over the bid pseudo-devices
    s2 = _stage2_aggregators(aggs, b, bids; T = T)
    rd = _redispatch(feeder, pf, s2; T = T, λ₀ = λ, optimizer = optimizer)
    rd.status == "ok" ||
        return _physics_record(; status = rd.status, notes = rd.notes, known...)
    row = Dict(j => i for (i, j) in enumerate(rd.input2.buses))
    π = Vector{Float64}[Float64[rd.input2.prices[row[a.bus], t] for t in 1:T] for a in aggs]
    # ok status: the solve exists. The split is read after the gate, so a failure of its
    # reconstruction check is a recorded status, never an exception.
    ch = try
        _congested_hours(rd.ctx2::ModelContext, λ; T = T)
    catch err
        mapped = _congestion_status(err)
        mapped === nothing && rethrow()
        return _physics_record(; status = mapped[1], notes = mapped[2], known...)
    end
    stage2 = (;
        u = rd.u,
        w = rd.w,
        Δ = rd.Δ,
        π,
        congested = ch.congested,
        congestion_scores = ch.scores,
        kappa_lo = ch.kappa_lo,
        kappa_hi = ch.kappa_hi,
        maxgap = rd.maxgap,
        p_import_stage2 = copy(rd.input2.p_import),
        max_wash = rd.max_wash,
    )

    # 4. delivery: each aggregator follows its activated target
    targets = Vector{Float64}[b[k] .+ rd.Δ[k] for k in eachindex(aggs)]
    weight = 10 * max(maximum(x -> maximum(abs, x), π), maximum(λ), maximum(abs, p))
    local delivered_raw
    try
        delivered_raw = [
            _deliver(a, p, targets[k]; T = T, weight = weight, τ_batt = τ_batt) for
            (k, a) in enumerate(aggs)
        ]
    catch err
        mapped = _physics_error_status(err, "delivery: ")
        mapped === nothing && rethrow()
        return _physics_record(;
            status = mapped[1],
            notes = mapped[2],
            known...,
            stage2...,
            targets,
            weight,
        )
    end
    # the 10w re-delivery is a sensitivity diagnostic only: its own solver outcome never
    # discards the valid primary delivery
    shortfall_10w_total, notes_10w = _shortfall_diagnostic(
        aggs,
        p,
        targets;
        T = T,
        weight = 10 * weight,
        τ_batt = τ_batt,
    )
    delivered = _dispatch_record(delivered_raw)
    shortfall = Vector{Float64}[d.shortfall for d in delivered_raw]
    return _physics_record(;
        status = "ok",
        notes = notes_10w,
        known...,
        stage2...,
        targets,
        delivered,
        shortfall,
        shortfall_total = sum(sum, shortfall),
        shortfall_10w_total,
        weight,
    )
end
