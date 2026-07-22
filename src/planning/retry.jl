# src/planning/retry.jl
#
# SEAM: escalating-retry wrapper around `assert_solved!` (D-08/D-09).
# OWNER: plan 10-01.
#
# `solve_with_retry!` wraps the project's SOLE INFRA-03 choke point (`assert_solved!`,
# src/core/status.jl, UNMODIFIED here) with a bounded, escalating Clarabel-conditioning
# ladder. It exists because the oracle this phase builds (plan 10-02) re-solves the same
# model many times inside a future Benders loop, amplifying the documented intermittent
# Clarabel `NUMERICAL_ERROR` (STATE.md carried blocker). Per D-09/CLAUDE.md, it NEVER falls
# back to SCS — only Clarabel's own post-build conditioning attributes are escalated via
# `set_optimizer_attribute` (no `@variable`/`@constraint`, no rebuild). Per D-10, on budget
# exhaustion OR a genuinely non-retryable status it raises LOUDLY, reusing `assert_solved!`'s
# exact 4-line diagnostic format plus the exhausted attempt count — never a silent fallback.
#
# `termination_status(model)`/`raw_status(model)` remain queryable inside a `catch` block
# AFTER `assert_solved!` throws its plain `ErrorException` (verified, 10-RESEARCH.md
# Pitfall 3) — this wrapper re-queries them, it does not receive a typed exception.

using JuMP

"""
    RETRYABLE_STATUSES

Termination statuses that indicate a numerical-conditioning artifact (not a genuine
modeling failure) and are therefore eligible for the escalating retry ladder in
[`solve_with_retry!`](@ref): `MOI.NUMERICAL_ERROR`, `MOI.SLOW_PROGRESS`,
`MOI.ALMOST_OPTIMAL`. Anything else — in particular `MOI.INFEASIBLE`,
`MOI.INFEASIBLE_OR_UNBOUNDED`, `MOI.DUAL_INFEASIBLE` — is NEVER retried (10-RESEARCH.md
Anti-Pattern: retrying a genuine infeasibility wastes the attempt budget and can mask a
real modeling/master-side bug).
"""
const RETRYABLE_STATUSES = (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS, MOI.ALMOST_OPTIMAL)

"""
    solve_with_retry!(model::Model; max_attempts::Int = 4, dual::Bool = true) -> Model

Solve `model` via [`assert_solved!`](@ref) (STRICT gate — never `allow_almost = true`,
per D-06/CLAUDE.md "duals only from a STRICT solve"), retrying with progressively
escalated Clarabel conditioning settings if the FIRST (or any subsequent) attempt reports
a status in [`RETRYABLE_STATUSES`](@ref). Never rebuilds the model (`num_variables`/
`num_constraints` are unchanged — only `set_optimizer_attribute` calls are issued) and
never falls back to a different solver (D-09).

The escalation ladder has 4 rungs (`max_attempts` caps how many are actually tried):

1. as-built (no attribute changes)
2. `static_regularization_constant => 1e-6`
3. adds `iterative_refinement_max_iter => 100, equilibrate_max_iter => 50`
4. `static_regularization_constant => 1e-5, dynamic_regularization_eps => 1e-11,
   iterative_refinement_max_iter => 200` (last resort)

If a retryable status is hit and attempts remain, `@warn`s with the attempt number and
`raw_status(model)`, then escalates to the next rung. If the status is NOT in
`RETRYABLE_STATUSES` (e.g. genuine `MOI.INFEASIBLE`) it raises immediately on attempt 1 —
no escalation is ever applied to a real modeling failure. If the budget is exhausted, it
raises a final loud `error(...)` reusing `assert_solved!`'s exact diagnostic format
(`termination_status`, `primal_status`, `dual_status`, `raw_status`) plus the exhausted
attempt count (D-10: raise loudly, never silent-corrupt, never silent-skip).
"""
function solve_with_retry!(model::Model; max_attempts::Int = 4, dual::Bool = true)
    ladder = [
        Dict(),                                                     # attempt 1: as-built
        Dict("static_regularization_constant" => 1e-6),             # attempt 2: relax static reg
        Dict(
            "static_regularization_constant" => 1e-6,
            "iterative_refinement_max_iter" => 100,
            "equilibrate_max_iter" => 50,
        ),                                                           # attempt 3: + refine/equilibrate
        Dict(
            "static_regularization_constant" => 1e-5,
            "dynamic_regularization_eps" => 1e-11,
            "iterative_refinement_max_iter" => 200,
        ),                                                           # attempt 4: last resort
    ]
    for (attempt, settings) in enumerate(ladder[1:min(max_attempts, length(ladder))])
        for (k, v) in settings
            set_optimizer_attribute(model, k, v)      # post-build attribute change; no rebuild
        end
        try
            return assert_solved!(model; dual = dual)
        catch e
            e isa ErrorException || rethrow()
            ts = termination_status(model)
            if ts in RETRYABLE_STATUSES && attempt < max_attempts
                @warn "solve_with_retry!: attempt $attempt failed ($ts); escalating conditioning" raw =
                    raw_status(model)
                continue
            end
            # non-retryable status, OR budget exhausted: RAISE LOUDLY with full diagnostics (D-10)
            error("""
                  solve_with_retry!: exhausted $attempt attempt(s) — refusing to trust results:
                    termination_status : $(ts)
                    primal_status      : $(primal_status(model))
                    dual_status        : $(dual_status(model))
                    raw_status         : $(raw_status(model))
                  """)
        end
    end
end

export solve_with_retry!, RETRYABLE_STATUSES
