# src/settlement/feasibility.jl
#
# SEAM: AC-physics feasibility STATUS for a fixed dispatch — a REPORT, never a
# gate (SETL-03). THIRD deliberate copy of the Phase-27 physics-only idiom:
#   1. `src/pricing/fit.jl` SITE-2 (`fit_baseline`'s FIT AC-PF settlement +
#      `_fit_ac_settlement_violations`, the per-hour diagnostics template), and
#   2. `src/experiments/mpc_loop.jl` `_mpc_truth_import_acpf` +
#      `_mpc_settlement_violations` (the single-hour production variant).
# Deliberately UN-SHARED from those copies (fit.jl:741-744 rationale: small,
# independently-readable functions beat one over-parametrized one) — this file
# owns ONLY the status struct and the general-T wrapper around the same pieces.
#
# HONESTY POLICY: statuses are MEASURED outcomes. Thermal/voltage violations are
# diagnosed from the solved physics (`ACPowerFlow(; limits = false)` — the model
# carries NO operating limits to violate), never thrown; a genuine Ipopt
# non-convergence is a recorded `:solve_failed` carrying the termination status.
# The ONLY throws from `ac_feasibility_status` are misuse `ArgumentError`s
# (shape/length/finiteness guards — a caller bug, not an operating outcome).
#
# WARM-START REMEDY (the Ipopt degenerate-zero-start start problem, ANALYTIC
# variant): Ipopt's default all-zero start sits at a DEGENERATE KKT point of the
# unrelaxed equality `l·v = P² + Q²` (the (P,Q)-gradient vanishes at P = Q = 0).
# The established remedy is a PHYSICALLY PLAUSIBLE warm start — `mpc_loop.jl`'s
# production truth settlement seeds from the calling window's own solved point
# (mpc_loop.jl:1515-1526: "a physically plausible warm start is the standard,
# already-established remedy"); `fit.jl`'s SITE-2 seeds from a ConvexBranchFlow
# solve. THIS wrapper has no prior solve to seed from, and the ConvexBranchFlow
# seed is NOT AVAILABLE here: its `v̂ ≥ v` exactness copy is a conservative
# RESTRICTION that excludes the true AC point of any REVERSE-FLOW fixed dispatch
# (the Phase-26 v4.0 finding, re-measured 2026-10-25: a fixed-injection seed on
# the benign export fixture terminates INFEASIBLE — with `P < 0` the AC point
# `v₂ = v̂₂ + (r²+x²)·l` sits ABOVE the copy while the cone forces `l > 0`, a
# contradiction; fit.jl's own header documents the same structural behavior as
# "genuinely, structurally inexact ... fixing every injection leaves the loss
# current l free"). So this file computes the ANALYTIC start instead:
# `_analytic_distflow_start!` hand-builds the lossless DistFlow point
# (downstream-accumulated flows, `v = 1 − 2(rP+xQ)` drops, `l = S²/v`) — the
# same physically plausible warm start, no solver needed, deterministic.
#
# SOLVER ABSTRACTION: `ACPowerFlow(; limits = false)` via
# `select_optimizer(problem_class(ACPowerFlow()))` — no concrete solver is named
# anywhere in this file (grep `Ipopt` == 0).
#
# GOLDEN POLICY: `src/pricing/`, `src/admm/`, `src/models/` are consumed, never
# modified — the third copy is additive, not a refactor of the originals.

export FeasibilityStatus, ac_feasibility_status

"""
    FeasibilityStatus

The SETL-03 contract: the AC-physics feasibility of one tariff's dispatch as a
REPORTED status — never thrown, never silently absorbed. Fields:

  - `status::Symbol` — `:feasible` (every hour clean), `:infeasible` (any thermal
    or voltage violation in any hour), or `:solve_failed` (the physics-only power
    flow did not converge — `message` carries the solver termination status);
  - `hours` — one diagnostics row per hour `(; t, n_thermal_violations, max_overload_ratio, n_voltage_violations, min_voltage, max_voltage, voltage_violated)`, the EXACT field set of `_fit_ac_settlement_violations`
    (empty when `status == :solve_failed` — no value is ever read off a
    non-converged model);
  - `n_thermal_violations::Int` — branch-hour overload count summed over hours;
  - `n_voltage_violations::Int` — bus-hour out-of-band count summed over hours;
  - `max_overload_ratio::Float64` — the worst branch apparent-power/rating ratio
    over all (branch, hour) pairs (0.0 when nothing counts);
  - `message::String` — the recorded refusal detail for `:solve_failed` (or a
    violation summary for `:infeasible`; `""` when feasible).
"""
struct FeasibilityStatus
    status::Symbol
    hours::Vector{<:NamedTuple}
    n_thermal_violations::Int
    n_voltage_violations::Int
    max_overload_ratio::Float64
    message::String

    function FeasibilityStatus(
        status::Symbol,
        hours::Vector{<:NamedTuple},
        n_thermal_violations::Int,
        n_voltage_violations::Int,
        max_overload_ratio::Float64,
        message::AbstractString,
    )
        status in (:feasible, :infeasible, :solve_failed) || throw(
            ArgumentError(
                "FeasibilityStatus: invalid status=$(repr(status)), expected " *
                ":feasible, :infeasible or :solve_failed",
            ),
        )
        return new(
            status,
            hours,
            n_thermal_violations,
            n_voltage_violations,
            max_overload_ratio,
            String(message),
        )
    end
end

"""
    _settlement_feasibility_violations(feeder, pf_vars::NamedTuple, T::Int) -> Vector{<:NamedTuple}

Internal helper (unexported): the THIRD copy of the per-hour thermal/voltage
diagnostics template (`_fit_ac_settlement_violations`, `src/pricing/fit.jl:746`;
single-hour precedent `_mpc_settlement_violations`, `src/experiments/mpc_loop.jl`)
— computed from a SOLVED [`ACPowerFlow`](@ref)`(; limits = false)` context's own
`P`/`Q`/`l`/`v`, never a constraint dual (there is none to read when
`limits = false`). For every branch with a real thermal rating
(`smax < SMAX_NO_LIMIT`) and every hour: forward apparent power `|S_fwd| = sqrt(P²+Q²)`, receiving-end `|S_rev| = sqrt((P−r·l)²+(Q−x·l)²)`, OVERLOADED
whenever `max(|S_fwd|, |S_rev|)/smax > 1`. For every non-root bus: `|V_j| = sqrt(v_j)`, OUT-OF-BAND whenever outside `[vmin, vmax]`. Same field names as the
template. Deliberately NOT shared code with the two originals (fit.jl:741-744).
"""
function _settlement_feasibility_violations(feeder, pf_vars::NamedTuple, T::Int)
    B = feeder.branches
    Np = length(feeder.buses)
    out = Vector{NamedTuple}(undef, T)
    for t in 1:T
        n_thermal = 0
        max_ratio = 0.0
        for (b, br) in enumerate(B)
            br.smax < SMAX_NO_LIMIT || continue          # skip-listed sentinel branch
            Pb = value(pf_vars.P[b, t])
            Qb = value(pf_vars.Q[b, t])
            lb = value(pf_vars.l[b, t])
            s_fwd = sqrt(Pb^2 + Qb^2)
            s_rev = sqrt((Pb - br.r * lb)^2 + (Qb - br.x * lb)^2)
            ratio = max(s_fwd, s_rev) / br.smax
            ratio > 1.0 && (n_thermal += 1)
            max_ratio = max(max_ratio, ratio)
        end

        n_voltage = 0
        min_v = Inf
        max_v = -Inf
        for j in 1:Np
            j == feeder.root && continue
            vb = feeder.buses[j]
            vj = sqrt(max(value(pf_vars.v[j, t]), 0.0))
            (vj < vb.vmin || vj > vb.vmax) && (n_voltage += 1)
            min_v = min(min_v, vj)
            max_v = max(max_v, vj)
        end

        out[t] = (;
            t,
            n_thermal_violations = n_thermal,
            max_overload_ratio = max_ratio,
            n_voltage_violations = n_voltage,
            min_voltage = min_v,
            max_voltage = max_v,
            voltage_violated = n_voltage > 0,
        )
    end
    return out
end

# Internal: the ANALYTIC warm start — the lossless DistFlow point of the fixed
# dispatch, hand-built with no solver (see the SEAM header for why this replaces
# fit.jl's ConvexBranchFlow seed). Per branch (parent→child flow convention):
# `P`/`Q` = the child subtree's accumulated injection, `v` = the parent's `v`
# less the lossless drop `2(rP+xQ)` (floored at a small positive value — `v` is
# a squared magnitude and must start strictly inside its `v ≥ 0` bound), and
# `l = (P²+Q²)/v_parent`. The root's frontier import start is the accumulated
# subtree exchange. Deterministic; sets every P/Q/l/v (+ frontier) start value.
function _analytic_distflow_start!(
    pv::NamedTuple,
    feeder::AbstractFeeder,
    aggs,
    nets,
    T::Int,
    p_import,
    q_import,
    reactive::Bool,
)
    Np = length(feeder.buses)
    inj_p = zeros(Np, T)
    inj_q = zeros(Np, T)
    for (agg, net) in zip(aggs, nets)
        tanφ = reactive_factor(agg.φ)                  # tan(arccos φ) (thesis 3.23)
        for t in 1:T
            inj_p[agg.bus, t] += net[t]
            inj_q[agg.bus, t] -= agg.Pdc[t] * tanφ
        end
    end

    kids = [Tuple{Int, Int}[] for _ in 1:Np]           # bus => (branch_idx, child_bus)
    for (b, br) in enumerate(feeder.branches)
        push!(kids[br.from], (b, br.to))
    end
    order = Int[feeder.root]                           # BFS: parents before children
    parent_branch = fill(0, Np)
    i = 1
    while i <= length(order)
        j = order[i]
        i += 1
        for (b, c) in kids[j]
            parent_branch[c] = b
            push!(order, c)
        end
    end

    sub_p = copy(inj_p)                                # reverse-BFS subtree accumulation
    sub_q = copy(inj_q)
    for j in reverse(order)
        for (_, c) in kids[j], t in 1:T
            sub_p[j, t] += sub_p[c, t]
            sub_q[j, t] += sub_q[c, t]
        end
    end

    B = feeder.branches
    v_start = ones(Np, T)                              # squared-voltage start; root = 1.0
    for j in order
        j == feeder.root && continue
        b = parent_branch[j]
        br = B[b]
        p = br.from
        for t in 1:T
            Pb = sub_p[j, t]                           # flow parent→child = subtree demand
            Qb = sub_q[j, t]
            vj = max(v_start[p, t] - 2 * (br.r * Pb + br.x * Qb), 0.05)
            v_start[j, t] = vj
            set_start_value(pv.P[b, t], Pb)
            set_start_value(pv.Q[b, t], Qb)
            set_start_value(pv.l[b, t], (Pb^2 + Qb^2) / max(v_start[p, t], 0.1))
            set_start_value(pv.v[j, t], vj)
        end
    end
    for t in 1:T
        # Root KCL: p_import + agg_inj[root] = Σ flows out of the root, and
        # Σ child-subtree sums = sub_p[root] − agg_inj[root] ⇒ the lossless start.
        set_start_value(p_import[t], sub_p[feeder.root, t] - inj_p[feeder.root, t])
        reactive &&
            set_start_value(q_import[t], sub_q[feeder.root, t] - inj_q[feeder.root, t])
    end
    return nothing
end

"""
    ac_feasibility_status(feeder::AbstractFeeder, aggs::AbstractVector{<:Aggregator},
                          nets::AbstractVector{<:Vector{<:Real}}; T::Int) -> FeasibilityStatus

AC-physics feasibility of a FIXED dispatch, reported as a [`FeasibilityStatus`](@ref)
— REPORT, NEVER THROW (SETL-03; the third application of the Phase-27 physics-only
idiom). `nets[k]` is the per-hour net active injection aligned with `aggs[k]`
(mirrors `_fit_opt_solve`'s per-agg rows); each aggregator's reactive draw is the
SITE-2 constant `−Pdc[t]·tan(arccos φ)` at `agg.bus`.

Build (mirrors `_mpc_truth_import_acpf`'s production structure, general-T):

 1. `ACPowerFlow(; limits = false)` on the real feeder — fixed injections via
    `add_to_residual!` per aggregator bus, free-sign frontier import at the
    root, balance constraints registered, total-loss objective (with every
    injection fixed the objective only resolves residual numerical freedom —
    mpc_loop.jl's documented rationale).
 2. WARM START from the analytic DistFlow point
    ([`_analytic_distflow_start!`](@ref) — the degenerate-zero-start remedy;
    see the SEAM header for the measured reason the ConvexBranchFlow seed
    variant is unavailable for fixed reverse-flow dispatch).
 3. Gate: `is_solved_and_feasible(model; dual = false, allow_local = true, allow_almost = false)`. Non-convergence ⇒ recorded `:solve_failed` carrying
    `termination_status` — never a throw, and no value is ever read off a
    non-converged model.
 4. DIAGNOSTICS — per-hour thermal/voltage rows from the solved physics
    ([`_settlement_feasibility_violations`](@ref)); all hours clean ⇒
    `:feasible`, any violation ⇒ `:infeasible` with counts and the worst
    overload ratio.

Misuse guards (loud `ArgumentError` — a caller bug, not an operating outcome):
empty `aggs`, `length(aggs) == length(nets)`, every `net` of length `T`, finite
net values, aggregator buses inside the feeder, `Pdc` long enough, `T ≥ 1`.
"""
function ac_feasibility_status(
    feeder::AbstractFeeder,
    aggs::AbstractVector{<:Aggregator},
    nets::AbstractVector{<:Vector{<:Real}};
    T::Int,
)
    isempty(aggs) && throw(
        ArgumentError(
            "ac_feasibility_status: empty aggregator vector — a dispatch needs at " *
            "least one aggregator to locate its injections.",
        ),
    )
    length(aggs) == length(nets) || throw(
        ArgumentError(
            "ac_feasibility_status: $(length(aggs)) aggregators but " *
            "$(length(nets)) net-injection vectors — they must align 1:1.",
        ),
    )
    T >= 1 || throw(ArgumentError("ac_feasibility_status: T=$T must be at least 1"))
    Np = length(feeder.buses)
    for (k, net) in enumerate(nets)
        length(net) == T || throw(
            ArgumentError(
                "ac_feasibility_status: nets[$k] has length $(length(net)), " *
                "expected T=$T",
            ),
        )
        for t in 1:T
            isfinite(net[t]) || throw(
                ArgumentError(
                    "ac_feasibility_status: nets[$k][$t] is non-finite " *
                    "($(net[t])) — refusing to build a power flow on a non-finite " *
                    "injection.",
                ),
            )
        end
    end
    for agg in aggs
        1 <= agg.bus <= Np || throw(
            ArgumentError(
                "ac_feasibility_status: aggregator bus=$(agg.bus) outside the " *
                "feeder buses 1:$Np",
            ),
        )
        length(agg.Pdc) >= T || throw(
            ArgumentError(
                "ac_feasibility_status: aggregator Pdc length $(length(agg.Pdc)) < " *
                "T=$T (the reactive draw needs Pdc[t] for t = 1:T)",
            ),
        )
    end

    # --- Physics-only AC power flow on the fixed dispatch ------------------------------
    ac = ACPowerFlow(; limits = false)
    model = Model(select_optimizer(problem_class(ac)))
    ctx = ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T

    contribute!(ac, ctx, feeder; T = T)
    reactive = has_reactive(ac)

    for (agg, net) in zip(aggs, nets)
        tanφ = reactive_factor(agg.φ)
        for t in 1:T
            add_to_residual!(ctx, :Rp, agg.bus, t, net[t])                  # net active (3.22)
            reactive && add_to_residual!(ctx, :Rq, agg.bus, t, -agg.Pdc[t] * tanφ)
        end
    end

    @variable(model, p_import[t = 1:T])              # free-sign frontier exchange
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    q_import = nothing
    if reactive
        q_import = @variable(model, [t = 1:T])
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
    end

    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)
    if reactive
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # Warm start P/Q/l/v (+ frontier) from the analytic DistFlow point — Ipopt's
    # default all-zero start is a degenerate KKT point of l·v = P²+Q² (the mpc_loop
    # physically-plausible-start remedy, analytic variant; see the SEAM header).
    pv = _require_pf_vars(ctx)
    _analytic_distflow_start!(pv, feeder, aggs, nets, T, p_import, q_import, reactive)

    # Total-loss objective (with every injection fixed this only resolves residual
    # numerical freedom — mpc_loop.jl's documented rationale).
    B = feeder.branches
    @objective(model, Min, sum(B[b].r * pv.l[b, t] for b in eachindex(B), t in 1:T))

    optimize!(model)
    ok = is_solved_and_feasible(
        model;
        dual = false,
        allow_local = true,
        allow_almost = false,
    )
    ok || return FeasibilityStatus(
        :solve_failed,
        Vector{NamedTuple}(),
        0,
        0,
        0.0,
        "ac_feasibility_status: the physics-only AC power flow FAILED to reach " *
        "LOCALLY_SOLVED — termination_status=$(termination_status(model)), " *
        "primal_status=$(primal_status(model)), raw_status=\"$(raw_status(model))\". " *
        "ALMOST_LOCALLY_SOLVED is treated as a failure, never silently accepted. " *
        "This is a genuine Ipopt non-convergence at the fixed dispatch (for " *
        "injections beyond the feeder's AC loadability there IS no operating " *
        "point), never a thermal/voltage limit — those are OMITTED from this " *
        "physics-only model and reported as :infeasible diagnostics instead.",
    )

    # --- Diagnostics: per-hour rows from the solved physics ----------------------------
    hours = _settlement_feasibility_violations(feeder, pv, T)
    n_thermal = sum(h.n_thermal_violations for h in hours)
    n_voltage = sum(h.n_voltage_violations for h in hours)
    max_ratio = maximum(h.max_overload_ratio for h in hours)
    if n_thermal == 0 && n_voltage == 0
        return FeasibilityStatus(:feasible, hours, 0, 0, max_ratio, "")
    end
    return FeasibilityStatus(
        :infeasible,
        hours,
        n_thermal,
        n_voltage,
        max_ratio,
        "ac_feasibility_status: the dispatch violates operating limits — " *
        "$n_thermal branch-hour thermal overload(s), $n_voltage bus-hour voltage " *
        "band violation(s), worst branch ratio $max_ratio (diagnostics per hour in " *
        "the `hours` rows; measured outcomes, never a gate).",
    )
end
