# src/planning/ac_recheck.jl
#
# SEAM: incumbent-only AC physics re-check (BILEV-04b infra half, plan 30-01).
# OWNER: plan 30-01.
#
# CONTEXT.md's SOCP-inexactness policy (BILEV-04b): when the Benders loop's incumbent
# turns out SOCP-inexact, a physical AC re-check via `ACPowerFlow(; limits = false)` is run
# ONCE (never per-iteration — measured ~15s/solve vs ~30ms for the SOCP, 30-RESEARCH.md
# Pattern 2) and its violation is REPORTED on the result — never thrown, never silently
# passed. This file provides that re-check, mirroring `src/experiments/mpc_loop.jl`'s
# `_mpc_truth_import_acpf` (lines 1557+), the ONLY path confirmed this session (30-RESEARCH.md)
# to accept Ipopt's genuine `LOCALLY_SOLVED` success: `solve_planning_oracle!`/
# `solve_with_retry!` both reject `LOCALLY_SOLVED` unconditionally (no `allow_local`
# passthrough), so this function bypasses BOTH entirely, calling
# `assert_solved!(...; dual = false, allow_local = true)` DIRECTLY.
#
# Unlike `_mpc_truth_import_acpf` (a bespoke, single-hour, T=1 free-variable build),
# `ac_recheck_incumbent` reuses the EXISTING generic `build_planning_oracle` builder
# directly — it already builds the full pinned model for ANY `AbstractPowerFlow`, including
# `ACPowerFlow`, since `problem_class(ACPowerFlow()) = NLP()` routes it to Ipopt via the
# SAME `select_optimizer(problem_class(pf))` factory. So this file's job is thin: build
# once at the incumbent, bypass the convex-core solve gate, and report violations computed
# DIRECTLY from the solved `P`/`Q`/`l`/`v` against the ORIGINAL feeder's `smax`/`vmin`/`vmax`
# — mirroring `_mpc_settlement_violations`'s own diagnostic-only, non-gating design, but
# aggregated across the FULL T-period horizon (not a single hour).

using JuMP

"""
    ac_recheck_incumbent(feeder, aggregators::AbstractVector{<:Aggregator}, λ₀, T::Int,
                         z_incumbent::AbstractVector{<:Real})
        -> (; ok::Bool, violations, p_import::Vector{Float64}, ac_welfare::Float64,
              raw_status)

The incumbent-only AC physics re-check (BILEV-04b infra half).

**What this checks (Phase 30 code review, WR-09).** It does NOT replay the SOCP
incumbent's own dispatch or prices. It builds a FRESH
[`PlanningOracle`](@ref)-shaped model via
`build_planning_oracle(feeder, ACPowerFlow(; limits = false), aggregators; λ₀ = λ₀, T = T)`
(the generic builder; `problem_class(ACPowerFlow()) = NLP()` routes it to Ipopt), pins
the SAME coupling flow `set_parameter_value.(oracle_ac.z, z_incumbent)`, and RE-OPTIMIZES
the welfare dispatch under exact AC physics with the feeder's thermal/voltage limits
DROPPED. The question it answers is: "at the incumbent's coupling flow `z`, does the
AC-optimal dispatch respect the ORIGINAL feeder's `smax`/`vmin`/`vmax`?" A violation
means the SOCP relaxation's answer at `z` is not physically realizable as-is; a clean
report is evidence (not proof) that it is.

The solve calls `assert_solved!(oracle_ac.model; dual = false, allow_local = true)`
DIRECTLY — NEVER `solve_planning_oracle!`/`solve_with_retry!` (both reject Ipopt's
`LOCALLY_SOLVED` and have no `allow_local` passthrough, confirmed 30-RESEARCH.md). A
THROWN `ErrorException` from it (Ipopt non-convergence — a tooling failure, not a
physical violation) is re-thrown with a clearer message naming `z_incumbent`.

Violations are computed DIRECTLY from `oracle_ac.ctx.meta[:pf_vars]` (`P`, `Q`, `l`, `v`)
against the ORIGINAL `feeder`, over EVERY branch/hour and bus/hour pair, BEYOND a
per-instance MEASURED tolerance (Phase 30 code review, CR-02): `δ` is the maximum primal
constraint violation of the solved AC model itself (`primal_feasibility_report`, read at
runtime — measured 2.0e-9 to 9.9e-9 on `ieee13_modified()` T=1/T=4 pins, 2026-10-01), and
a branch counts as overloaded iff `max(s_fwd, s_rev) > smax + 10δ`, a bus as out of band iff
`√v < vmin − 10δ` or `√v > vmax + 10δ` (a constraint residual `δ` moves `√(P²+Q²)` by at most
`√2·δ` and `√v` by at most `δ` for `v ≥ 0.25`; the factor 10 is headroom over that).
**NEVER throws on a genuine physical violation** — it is REPORTED.

Returns `(; ok, violations, p_import, ac_welfare, raw_status)`:

  - `ok = n_thermal_violations == 0 && n_voltage_violations == 0` — `true` ONLY when no
    limit is violated beyond the measured tolerance (it is never hard-coded);
  - `violations::NamedTuple` — `(; n_thermal_violations::Int, max_overload_ratio::Float64,
    n_voltage_violations::Int, min_voltage::Float64, max_voltage::Float64,
    voltage_violated::Bool, ac_primal_violation::Float64, violation_tol::Float64)`.
    `max_overload_ratio` is `0.0` and `min_voltage`/`max_voltage` are `Inf`/`-Inf` only
    when the feeder has zero thermally-limited branches / zero non-root buses;
  - `p_import` — the AC model's frontier import for EVERY hour `1:T` (WR-09; equal to
    `z_incumbent` up to the pin's own residual);
  - `ac_welfare` — the AC model's optimal welfare `objective_value(oracle_ac.model)`, so a
    caller can compare it with the SOCP welfare at the same `z` (limits are dropped here,
    so this is a diagnostic, not a bound);
  - `raw_status` — Ipopt's own status string.

Throws `ArgumentError` when `length(z_incumbent) != T` (WR-09), before any build.
"""
function ac_recheck_incumbent(
    feeder,
    aggregators::AbstractVector{<:Aggregator},
    λ₀,
    T::Int,
    z_incumbent::AbstractVector{<:Real},
)
    length(z_incumbent) == T || throw(
        ArgumentError(
            "ac_recheck_incumbent: z_incumbent has length $(length(z_incumbent)), " *
            "expected T=$T",
        ),
    )
    oracle_ac = build_planning_oracle(
        feeder,
        ACPowerFlow(; limits = false),
        aggregators;
        λ₀ = λ₀,
        T = T,
    )
    set_parameter_value.(oracle_ac.z, z_incumbent)

    try
        assert_solved!(oracle_ac.model; dual = false, allow_local = true)
    catch e
        e isa ErrorException || rethrow()
        throw(
            ErrorException(
                "ac_recheck_incumbent: AC power-flow re-check FAILED to reach " *
                "LOCALLY_SOLVED at the incumbent z=$(z_incumbent) — a genuine Ipopt " *
                "non-convergence (tooling failure), never a reported physical violation " *
                "(BILEV-04b). Original error: $(sprint(showerror, e))",
            ),
        )
    end

    # CR-02: the per-instance measured noise floor — the solved AC model's own maximum
    # primal constraint violation (an empty report means every constraint holds exactly).
    feas_report = primal_feasibility_report(oracle_ac.model)
    δ = isempty(feas_report) ? 0.0 : Float64(maximum(values(feas_report)))
    viol_tol = 10 * δ

    pv = oracle_ac.ctx.meta[:pf_vars]
    B = feeder.branches
    Np = length(feeder.buses)

    n_thermal = 0
    max_ratio = 0.0
    for (b, br) in enumerate(B)
        br.smax < SMAX_NO_LIMIT || continue
        for t in 1:T
            Pb = value(pv.P[b, t])
            Qb = value(pv.Q[b, t])
            lb = value(pv.l[b, t])
            s_fwd = sqrt(Pb^2 + Qb^2)
            s_rev = sqrt((Pb - br.r * lb)^2 + (Qb - br.x * lb)^2)
            ratio = max(s_fwd, s_rev) / br.smax
            max(s_fwd, s_rev) > br.smax + viol_tol && (n_thermal += 1)
            max_ratio = max(max_ratio, ratio)
        end
    end

    n_voltage = 0
    min_v = Inf
    max_v = -Inf
    for j in 1:Np
        j == feeder.root && continue
        vb = feeder.buses[j]
        for t in 1:T
            vj = sqrt(max(value(pv.v[j, t]), 0.0))
            (vj < vb.vmin - viol_tol || vj > vb.vmax + viol_tol) && (n_voltage += 1)
            min_v = min(min_v, vj)
            max_v = max(max_v, vj)
        end
    end

    violations = (;
        n_thermal_violations = n_thermal,
        max_overload_ratio = max_ratio,
        n_voltage_violations = n_voltage,
        min_voltage = min_v,
        max_voltage = max_v,
        voltage_violated = n_voltage > 0,
        ac_primal_violation = δ,
        violation_tol = viol_tol,
    )

    return (;
        ok = n_thermal == 0 && n_voltage == 0,
        violations,
        p_import = [value(oracle_ac.p_import[t]) for t in 1:T],
        ac_welfare = objective_value(oracle_ac.model),
        raw_status = raw_status(oracle_ac.model),
    )
end

export ac_recheck_incumbent
