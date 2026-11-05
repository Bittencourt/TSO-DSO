# src/coordination/flex_bids.jl
#
# SEAM: the aggregator's own value function. A flexibility bid is read off the aggregator's
# fixed-net value function
#
#     V(x) = max { U(devices) : pag[t] == x[t] for every hour t },
#
# the best device utility it can reach when its net injection `pag` is pinned to the schedule
# `x`. Truthful bidding means the cost of an up deviation of δ at hour h (more injection) is the
# utility loss V(b) − V(b + δ·e_h) around the baseline `b`, and the value of a down deviation is
# the gain V(b − δ·e_h) − V(b). The probes move ONE hour at a time with every other hour held
# at baseline (hour-separable bids), and the devices are free to re-arrange behind the meter.
#
# The model is the price-taker build shape (`Model(select_optimizer(QP()))` → `ModelContext` →
# `contribute!` → `pag` coupling) with NO price term and NO ρ term, never `solve_agr!`. It is
# built ONCE per aggregator and re-solved by `fix`/`unfix` and objective swaps; the price-taker
# seam itself is consumed, never modified.
#
# WHY SECANTS, NOT BREAKPOINT DUALS. The dual of `pag[h] == x_h` is the local slope V'(x_h): one
# number per point, exact only in the limit. A block of width δ needs the AVERAGE marginal cost
# over the block, and the secant (V_{k−1} − V_k)/δ is exactly that average, so the accepted cost
# of a whole block equals the true utility loss on it. V is concave (a concave maximisation with
# an affine right-hand side), so in exact arithmetic the secants are already monotone and the
# curve is convex.
#
# WHY A RANGE FLOOR. A secant divides a value difference by δ. Solver noise on V is of order
# 1e-8·|V|, so on a near-zero range (δ ≈ 1e-9 pu) the quotient is pure noise, large enough to
# make the curve non-convex and to put a down price above an up price (a wash trade the stage-2
# clear would accept for free). Below `FLEX_RANGE_FLOOR` no block is emitted in that direction;
# this is a modelling floor, measured, not a test tolerance.
#
# WHY ONE PAV PASS. The remaining secant noise above the floor is small but can still break
# monotonicity by a few 1e-5. A single weighted pool-adjacent-violators (isotonic) pass over the
# concatenated marginal curve [g_K .. g_1, m_1 .. m_K], weighted by block width, returns the
# closest non-decreasing curve in the weighted least-squares sense. That one pass makes the up
# prices non-decreasing, the down prices non-increasing and g_1 ≤ m_1 at once, and pooling
# preserves the total cost of the pooled blocks. The largest change is REPORTED (`repair_max`),
# never hidden.
#
# HONESTY: every solve is gated on `termination_status == OPTIMAL` and `primal_status ==
# FEASIBLE_POINT`. A failed probe drops its block and is counted in `n_failed`; bid generation
# never throws on a solver outcome. Certificates (battery complementarity) belong to the
# delivery solves, never to the probes.

"""
    FLEX_RANGE_FLOOR

The smallest single-hour flexibility range (in pu) for which a bid direction is offered,
`1e-6`. A direction whose range is below it emits no block: secant prices on a smaller range
are dominated by solver noise. A modelling floor, not a test tolerance.
"""
const FLEX_RANGE_FLOOR = 1e-6

"""
    FlexBids

The divisible, hour-separable bid curve of one aggregator, as produced by [`flex_bids`](@ref).
Internal; every matrix is `T × K` (hours × blocks).

  - `up_q`, `up_m` — up-block widths (pu of extra injection) and prices; `up_m` is
    non-decreasing in the block index.
  - `dn_q`, `dn_g` — down-block widths (pu of reduced injection) and values; `dn_g` is
    non-increasing in the block index.
  - `V0` — the fixed-net value V(b) at the baseline (`NaN` only when that solve failed, in
    which case no block is offered).
  - `repair_max` — the largest absolute change the monotone repair made to any price.
  - `min_bid_ask_gap` — the minimum over hours with both directions of `m₁ − g₁` (first
    offered up price minus first offered down value); `+Inf` when no hour has both.
  - `n_solves`, `n_failed` — the number of solves run and the number that failed the status
    gate.

A width of `0.0` means the block is not offered; its price is stored as `0.0` and never used.
"""
struct FlexBids
    up_q::Matrix{Float64}
    up_m::Matrix{Float64}
    dn_q::Matrix{Float64}
    dn_g::Matrix{Float64}
    V0::Float64
    repair_max::Float64
    min_bid_ask_gap::Float64
    n_solves::Int
    n_failed::Int
end

"""
    _fixed_net_model(agg::Aggregator; T::Int) -> (; model, ctx, pag)

Build, without solving, the aggregator's fixed-net value-function model: the price-taker
build shape (`Model(select_optimizer(QP()))`, `ModelContext`, `contribute!(agg, ctx; T)`)
with anonymous `pag[t] == p_inject[t] − Pdc[t]` and the objective `Max ctx.objective` (pure
device utility, no price term, no ρ term). Built once per aggregator and re-solved by
`fix`/`unfix` of `pag`.
"""
function _fixed_net_model(agg::Aggregator; T::Int)
    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.T = T
    res = contribute!(agg, ctx; T = T)
    pag = @variable(model, [1:T])
    @constraint(model, [t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    @objective(model, Max, ctx.objective)
    return (; model, ctx, pag)
end

# Internal: the status gate for every bid solve (never throws).
function _bid_solve_ok(model::Model)
    return termination_status(model) == MOI.OPTIMAL &&
           primal_status(model) == MOI.FEASIBLE_POINT
end

"""
    _pav_nondecreasing(values::Vector{Float64}, weights::Vector{Float64}) -> Vector{Float64}

Weighted pool-adjacent-violators: the non-decreasing sequence closest to `values` in the
`weights`-weighted least-squares sense. Adjacent violators are pooled to their weighted mean,
so an already non-decreasing input is returned unchanged (`==`). Weights must be positive and
finite; throws `ArgumentError` otherwise or on a length mismatch.
"""
function _pav_nondecreasing(values::Vector{Float64}, weights::Vector{Float64})
    n = length(values)
    length(weights) == n || throw(
        ArgumentError(
            "_pav_nondecreasing: $(length(weights)) weights for $n values (lengths must match).",
        ),
    )
    for i in 1:n
        isfinite(values[i]) || throw(
            ArgumentError("_pav_nondecreasing: values[$i] is non-finite ($(values[i]))."),
        )
        isfinite(weights[i]) && weights[i] > 0 || throw(
            ArgumentError(
                "_pav_nondecreasing: weights[$i] = $(weights[i]) must be positive and finite.",
            ),
        )
    end
    level = Float64[]
    weight = Float64[]
    count = Int[]
    for i in 1:n
        push!(level, values[i])
        push!(weight, weights[i])
        push!(count, 1)
        while length(level) >= 2 && level[end - 1] > level[end]
            w = weight[end - 1] + weight[end]
            l = (weight[end - 1] * level[end - 1] + weight[end] * level[end]) / w
            c = count[end - 1] + count[end]
            pop!(level)
            pop!(weight)
            pop!(count)
            level[end] = l
            weight[end] = w
            count[end] = c
        end
    end
    out = Vector{Float64}(undef, n)
    i = 1
    for (l, c) in zip(level, count)
        for j in i:(i + c - 1)
            out[j] = l
        end
        i += c
    end
    return out
end

# Internal: probe one direction (`s = +1` up, `s = -1` down) of hour `h` over `K` equal steps
# of the range `R`, writing block widths and raw secant prices into row `h` of `q` and `price`.
# A failed probe drops its block; the next successful probe's secant then spans from the last
# successful point (its width covers the dropped step). Returns `(n_solves, n_failed)`.
function _probe_direction!(
    q::Matrix{Float64},
    price::Matrix{Float64},
    fm,
    b::Vector{Float64},
    h::Int,
    s::Int,
    R::Float64,
    K::Int,
    V0::Float64,
)
    model = fm.model
    δ = R / K
    v_prev = V0
    last = 0
    n_solves = 0
    n_failed = 0
    for k in 1:K
        fix(fm.pag[h], b[h] + s * k * δ; force = true)
        optimize!(model)
        n_solves += 1
        if !_bid_solve_ok(model)
            n_failed += 1
            continue
        end
        v_k = value(fm.ctx.objective)
        width = (k - last) * δ
        # up: the utility lost per unit of extra injection; down: the utility gained per unit
        # of reduced injection.
        price[h, k] = s > 0 ? (v_prev - v_k) / width : (v_k - v_prev) / width
        q[h, k] = width
        v_prev = v_k
        last = k
    end
    return n_solves, n_failed
end

# Internal: the monotone repair of hour `h`. Concatenate the offered blocks in order of
# increasing injection, [g_K .. g_1, m_1 .. m_K], pool with weighted PAV, write the repaired
# prices back and return the largest absolute change (0.0 with no offered block).
function _repair_hour!(
    up_m::Matrix{Float64},
    dn_g::Matrix{Float64},
    up_q::Matrix{Float64},
    dn_q::Matrix{Float64},
    h::Int,
    K::Int,
)
    vals = Float64[]
    wts = Float64[]
    for k in K:-1:1
        if dn_q[h, k] > 0
            push!(vals, dn_g[h, k])
            push!(wts, dn_q[h, k])
        end
    end
    for k in 1:K
        if up_q[h, k] > 0
            push!(vals, up_m[h, k])
            push!(wts, up_q[h, k])
        end
    end
    isempty(vals) && return 0.0
    rep = _pav_nondecreasing(vals, wts)
    worst = 0.0
    i = 1
    for k in K:-1:1
        if dn_q[h, k] > 0
            worst = max(worst, abs(rep[i] - vals[i]))
            dn_g[h, k] = rep[i]
            i += 1
        end
    end
    for k in 1:K
        if up_q[h, k] > 0
            worst = max(worst, abs(rep[i] - vals[i]))
            up_m[h, k] = rep[i]
            i += 1
        end
    end
    return worst
end

# Internal: the first offered block of row `h` (smallest block index with a positive width),
# or 0 when the direction offers nothing.
function _first_block(q::Matrix{Float64}, h::Int)
    for k in axes(q, 2)
        q[h, k] > 0 && return k
    end
    return 0
end

"""
    flex_bids(agg::Aggregator, b::AbstractVector{<:Real}; T::Int, n_blocks::Int,
              range_floor = FLEX_RANGE_FLOOR) -> FlexBids

Generate the truthful, divisible, hour-separable bid curve of `agg` around its baseline net
injection `b` (length `T`) by probing its own fixed-net value function (see
[`_fixed_net_model`](@ref)), built once and re-solved:

 1. fix every hour at `b` and solve, giving `V0 = V(b)`;
 2. for each hour `h`, release `pag[h]` and solve the two range problems `max pag[h]` and
    `min pag[h]` (other hours still fixed), giving `R↑ = sup − b_h` and `R↓ = b_h − inf`;
 3. for each direction whose range is at least `range_floor`, fix `pag[h]` at
    `b_h ± k·R/K` for `k = 1..K` (`K = n_blocks`) and record V; then re-fix `pag[h] = b_h`;
 4. secant prices over equal widths `δ = R/K`: up `m_k = (V_{k−1} − V_k)/δ` and down
    `g_k = (V_k − V_{k−1})/δ`, with `V_0 = V0` on both sides;
 5. one weighted PAV repair per hour over `[g_K .. g_1, m_1 .. m_K]` (weights = widths).

The solve count is `1 + 2T + K·(number of offered hour-directions)` when nothing fails. Every
solve is status-gated; a failed probe drops its block and counts in `n_failed`, a failed range
problem offers nothing in that direction, and a failed baseline solve returns an empty bid with
`V0 = NaN`. None of these throws.

Throws `ArgumentError` when `T < 1`, `length(b) != T`, any `b[t]` is non-finite,
`n_blocks < 1`, or `range_floor` is negative or non-finite.
"""
function flex_bids(
    agg::Aggregator,
    b::AbstractVector{<:Real};
    T::Int,
    n_blocks::Int,
    range_floor::Real = FLEX_RANGE_FLOOR,
)
    T >= 1 || throw(ArgumentError("flex_bids: T=$T must be at least 1."))
    length(b) == T || throw(
        ArgumentError("flex_bids: baseline b has length $(length(b)), expected T=$T."),
    )
    for t in 1:T
        isfinite(b[t]) ||
            throw(ArgumentError("flex_bids: baseline b[$t] is non-finite ($(b[t]))."))
    end
    n_blocks >= 1 ||
        throw(ArgumentError("flex_bids: n_blocks=$n_blocks must be at least 1."))
    isfinite(range_floor) && range_floor >= 0 || throw(
        ArgumentError(
            "flex_bids: range_floor=$range_floor must be finite and non-negative.",
        ),
    )
    K = n_blocks
    floor_ = Float64(range_floor)
    bb = Float64[b[t] for t in 1:T]

    up_q = zeros(T, K)
    up_m = zeros(T, K)
    dn_q = zeros(T, K)
    dn_g = zeros(T, K)

    fm = _fixed_net_model(agg; T = T)
    model = fm.model
    for t in 1:T
        fix(fm.pag[t], bb[t]; force = true)
    end
    optimize!(model)
    n_solves = 1
    n_failed = 0
    if !_bid_solve_ok(model)
        return FlexBids(up_q, up_m, dn_q, dn_g, NaN, 0.0, Inf, n_solves, n_failed + 1)
    end
    V0 = value(fm.ctx.objective)

    for h in 1:T
        unfix(fm.pag[h])

        @objective(model, Max, fm.pag[h])
        optimize!(model)
        n_solves += 1
        R_up = 0.0
        if _bid_solve_ok(model)
            R_up = max(0.0, value(fm.pag[h]) - bb[h])
        else
            n_failed += 1
        end

        @objective(model, Min, fm.pag[h])
        optimize!(model)
        n_solves += 1
        R_dn = 0.0
        if _bid_solve_ok(model)
            R_dn = max(0.0, bb[h] - value(fm.pag[h]))
        else
            n_failed += 1
        end

        @objective(model, Max, fm.ctx.objective)
        if R_up >= floor_ && R_up > 0
            ns, nf = _probe_direction!(up_q, up_m, fm, bb, h, 1, R_up, K, V0)
            n_solves += ns
            n_failed += nf
        end
        if R_dn >= floor_ && R_dn > 0
            ns, nf = _probe_direction!(dn_q, dn_g, fm, bb, h, -1, R_dn, K, V0)
            n_solves += ns
            n_failed += nf
        end
        fix(fm.pag[h], bb[h]; force = true)
    end

    repair_max = 0.0
    min_gap = Inf
    for h in 1:T
        repair_max = max(repair_max, _repair_hour!(up_m, dn_g, up_q, dn_q, h, K))
        ku = _first_block(up_q, h)
        kd = _first_block(dn_q, h)
        if ku > 0 && kd > 0
            min_gap = min(min_gap, up_m[h, ku] - dn_g[h, kd])
        end
    end

    return FlexBids(up_q, up_m, dn_q, dn_g, V0, repair_max, min_gap, n_solves, n_failed)
end
