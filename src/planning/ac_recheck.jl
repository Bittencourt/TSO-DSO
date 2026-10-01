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
        -> (; ok::Bool, violations, p_import, raw_status)

The incumbent-only AC physics re-check (BILEV-04b infra half): build a FRESH
[`PlanningOracle`](@ref)-shaped model via
`build_planning_oracle(feeder, ACPowerFlow(; limits = false), aggregators; λ₀ = λ₀, T = T)`
(reuses the EXISTING generic builder — `ACPowerFlow` already routes through the SAME
`contribute!` dispatch, `problem_class(ACPowerFlow()) = NLP()`), pin
`set_parameter_value.(oracle_ac.z, z_incumbent)`, then call
`assert_solved!(oracle_ac.model; dual = false, allow_local = true)` DIRECTLY — NEVER
`solve_planning_oracle!`/`solve_with_retry!` (both reject Ipopt's `LOCALLY_SOLVED` by
default and have no `allow_local` passthrough, confirmed 30-RESEARCH.md).

On a THROWN `ErrorException` from `assert_solved!` (a genuine Ipopt non-convergence — a
tooling failure, not a physical violation), RE-THROWS with a clearer message naming
`z_incumbent` and the phase — this is still a genuine error (mirrors
`_mpc_truth_import_acpf`'s own convention for a convergence FAILURE).

On a converged solve, computes violations DIRECTLY from `oracle_ac.ctx.meta[:pf_vars]`
(`P`, `Q`, `l`, `v`) against the ORIGINAL `feeder`'s `smax`/`vmin`/`vmax` (the
`ACPowerFlow(; limits = false)` model itself has no `:smax`/voltage-bound constraint to
read a dual from), aggregated over EVERY branch/hour and bus/hour pair — mirroring
`_mpc_settlement_violations`'s own per-branch/per-bus check shape (`src/experiments/
mpc_loop.jl`), generalized from its single-hour (`T=1`) form to the full `T`-period
horizon. **NEVER throws on a genuine physical violation** (CONTEXT.md: "its violation
REPORTED on the result — never thrown, never silently passed") — only a non-convergent
Ipopt solve itself raises.

Returns `(; ok = true, violations, p_import = value(oracle_ac.p_import[1]), raw_status =
raw_status(oracle_ac.model))` where `violations` is a `NamedTuple`:
`(; n_thermal_violations::Int, max_overload_ratio::Float64, n_voltage_violations::Int,
min_voltage::Float64, max_voltage::Float64, voltage_violated::Bool)`. `max_overload_ratio`
is `0.0` and `min_voltage`/`max_voltage` are `Inf`/`-Inf` only when the feeder has zero
thermally-limited branches / zero non-root buses respectively (never happens on a
well-formed `Feeder`, but defensively mirrors `_mpc_settlement_violations`'s own
no-limited-branch convention).
"""
function ac_recheck_incumbent(
    feeder,
    aggregators::AbstractVector{<:Aggregator},
    λ₀,
    T::Int,
    z_incumbent::AbstractVector{<:Real},
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
            ratio > 1.0 && (n_thermal += 1)
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
            (vj < vb.vmin || vj > vb.vmax) && (n_voltage += 1)
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
    )

    return (;
        ok = true,
        violations,
        p_import = value(oracle_ac.p_import[1]),
        raw_status = raw_status(oracle_ac.model),
    )
end

export ac_recheck_incumbent
