---
phase: 08-experiment-harness-reproducibility
plan: 03
subsystem: infra
tags: [scenario, run-scenario, solve-welfare, solve-admm, extract-dlmp, reproducibility, admm]

# Dependency graph
requires:
  - phase: 08-experiment-harness-reproducibility
    plan: 02
    provides: Scenario (primitive selectors) + materialize.jl (sub_seed/build_feeder/build_price/build_population)
  - phase: 04-convex-branch-flow-correctness-milestone
    provides: solve_welfare (centralized SOCP ground truth)
  - phase: 05-distribution-pricing-dadp-dlmp-decomposition
    provides: extract_dlmp (DADP extraction)
  - phase: 06-admm-decomposition-core
    provides: solve_admm base contract (welfare, dadp, iters, residuals, exact_maxgap)
  - phase: 07-admm-convergence-scale
    provides: solve_admm adaptive-ρ loop
provides:
  - "ScenarioResult record: welfare/dadp(node×T)/exact_maxgap/iters/final_r/final_s/elapsed, one comparable schema for both solve strategies"
  - "run_scenario(s::Scenario) -> ScenarioResult: materializes feeder/profiles/price/population then dispatches :centralized -> solve_welfare+extract_dlmp or :admm -> solve_admm, throwing ArgumentError on any other strategy"
  - "INFRA-04 same-seed reproducibility gate GREEN: same Scenario+seed -> == identical welfare/dadp/exact_maxgap in-process; different seed -> different dadp"
affects: [08-04, 09-documentation-regression-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "run_scenario is PATH-FREE: returns a ScenarioResult, never writes to disk (persistence is 08-04's run_and_store)"
    - "Timings captured via @elapsed and stored on the result but EXCLUDED from every reproducibility/equality comparison"
    - "Strategy dispatch normalizes both branches to a common node×T dadp shape (sorted-load-bus rows) so centralized and ADMM results are directly comparable"

key-files:
  created: []
  modified:
    - src/experiments/run.jl
    - src/experiments/Scenario.jl

key-decisions:
  - "Two atomic task commits mirroring the plan's own two-task structure: Task 1 landed ScenarioResult + the :centralized branch (with a temporary throw for any other strategy, not faked); Task 2 added the :admm branch + the terminal ArgumentError guard."
  - "[Rule 1 - Bug] Scenario's default ADMM ρ (1.0, inherited from 08-02/RESEARCH Pattern 1) numerically errors (Clarabel NUMERICAL_ERROR) when run_scenario(:admm) is exercised end-to-end for the first time on the default :ieee13 feeder + :default population -- the Phase-7 adaptive-ρ loop cannot climb from ρ₀=1.0 to a well-conditioned value before Clarabel fails. Bumped Scenario's default ρ to 100.0, matching test_admm.jl's own empirically-validated ρ_ieee13 for the same feeder scale; confirmed run_scenario(:admm) then converges cleanly in 58 iterations with exact_maxgap ~1e-9. Adaptive ρ still self-tunes per scenario from this starting point; per-scenario ρ override remains available."

patterns-established: []

requirements-completed: [EXP-01, INFRA-04]

# Metrics
duration: ~35min
completed: 2026-07-19
---

# Phase 08, Plan 03: run_scenario Strategy Dispatch + Reproducibility Gate Summary

**`run_scenario(s::Scenario) -> ScenarioResult` dispatching :centralized (solve_welfare+extract_dlmp) and :admm (solve_admm) into one normalized node×T result, with the INFRA-04 same-seed bit-for-bit reproducibility gate green.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-19
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `ScenarioResult` (`src/experiments/run.jl`): an immutable record — `scenario`, `welfare::Float64`, `dadp::Matrix{Float64}` (node×T, sorted-load-bus rows), `exact_maxgap::Float64`, `iters`/`final_r`/`final_s::Union{Missing,...}` (populated only for `:admm`), and `elapsed::Float64` (wall-clock, explicitly non-reproducible) — the SAME schema for both strategies so centralized and ADMM outputs are directly comparable (EXP-01).
- `run_scenario(s::Scenario)`: materializes `feeder`/`profiles`/`λ₀`/`aggs`/`pf` from `s`'s selectors + seed (08-02's `build_feeder`/`build_price`/`build_population`/`sub_seed`), then dispatches `s.strategy`: `:centralized` calls `solve_welfare` + `extract_dlmp(ctx)[sorted_load_buses, :]`, reading `ctx.meta[:socp_maxgap]`; `:admm` calls `solve_admm` (whose `dadp` is already node×T, per solve_admm's own docstring) and populates `iters`/`final_r`/`final_s` from the converged residual trace; any other strategy throws `ArgumentError` naming the two valid selectors (defensive-in-depth — `Scenario` itself already guards this at construction, 08-02). `run_scenario` is PATH-FREE — never writes a file.
- Verified the INFRA-04 load-bearing gate directly: two same-`Scenario` same-seed centralized runs in one process give `==`-identical `welfare`/`dadp`/`exact_maxgap`; a different seed (`seed=8` vs `seed=7`) changes `dadp`. Both the plan's own `<verify>` commands and the pre-existing `test/test_experiments.jl` "EXP-01 scenario centralized"/"EXP-01 scenario admm"/"EXP-01 scenario strategy guard"/"INFRA-04 same-seed repro"/"INFRA-04 seed sensitivity" testitems pass green (24 individual `@test` assertions across the five items).

## Task Commits

Each task was committed atomically:

1. **Task 1: ScenarioResult record + run_scenario :centralized branch (end-to-end slice + repro gate)** — `a5c7a9b` (feat)
2. **Task 2: run_scenario :admm branch + strategy dispatch guard** — `d1ef249` (feat, includes the Scenario.jl ρ-default deviation)

## Files Created/Modified
- `src/experiments/run.jl` — filled the 08-01 comment-only stub: `ScenarioResult` struct + `run_scenario` strategy dispatch (`:centralized`/`:admm`/terminal guard) + export.
- `src/experiments/Scenario.jl` — one-line default change (`ρ::Float64 = 1.0` → `100.0`) + docstring note explaining the deviation.

## Decisions Made
- Preserved the plan's own two-task/two-commit structure exactly: Task 1's `run_scenario` temporarily threw a plain `ErrorException` (not `ArgumentError`, and explicitly commented as temporary) for any non-`:centralized` strategy, so the terminal `ArgumentError` guard added in Task 2 is a genuinely new commit, not pre-faked.
- `ScenarioResult`'s `dadp` is normalized via `sort!([a.bus for a in aggs])` on the `:centralized` branch (matching `extract_dlmp(ctx)[load_buses, :]`'s expected row order) so it lines up exactly with `solve_admm`'s already-node×T `dadp` (ascending load-node bus order) — no separate reconciliation step needed.
- Timings (`elapsed`, via `@elapsed` wrapping the full materialize+solve body) are captured on `ScenarioResult` for reporting but never appear in any equality/reproducibility assertion (RESEARCH Anti-Pattern; threat T-08-07).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Scenario's default ADMM ρ too small for the default :ieee13 population, causing a Clarabel NUMERICAL_ERROR**
- **Found during:** Task 2 (running the plan's own admm verify command against the `test_experiments.jl` "EXP-01 scenario admm" testitem, which uses `Phase8Fixtures.minimal_scenario_kwargs()` with NO `ρ` override — i.e. `Scenario`'s default `ρ = 1.0`)
- **Issue:** `run_scenario(Scenario(feeder=:ieee13, strategy=:admm, seed=7, T=24))` (all defaults) threw `Solve failed — refusing to trust results: termination_status: NUMERICAL_ERROR` deep inside `solve_admm`'s DSO-OPT re-solve. The Phase-7 adaptive-ρ loop, starting at `ρ₀ = 1.0`, could not climb to a well-conditioned penalty before Clarabel's SOCP numerically failed on the congestion-heavy default `:default` residential population (12 houses on ieee13's 100 MVA base).
- **Fix:** Changed `Scenario`'s default `ρ::Float64` from `1.0` to `100.0` — the SAME empirically-validated initial penalty `test_admm.jl` already pins for this exact feeder scale (`ρ_ieee13 = 100.0`, documented there as "ρ is fixture-empirical"). Updated the struct docstring to explain the rationale and that adaptive ρ still self-tunes per scenario from this new starting point.
- **Files modified:** `src/experiments/Scenario.jl`
- **Verification:** `run_scenario(Scenario(feeder=:ieee13, strategy=:admm, seed=7, T=24))` (now all-default) converges in 58 iterations, `exact_maxgap ≈ 1.28e-9`. Full `Pkg.test()` re-run after the fix: "EXP-01 scenario admm" went from 2 pass/1 error to 7 pass/0 fail/0 error; no other testitem regressed (package-wide: 1909 pass / 5 fail / 2 broken, matching the pre-existing 08-02 baseline plus the still-RED 08-04-owned items).
- **Committed in:** `d1ef249` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Necessary for `run_scenario(:admm)` to actually work end-to-end on the SHIPPED default scenario (the plan's own success criterion) — not a plan-scope change, no new model/solver logic touched. No scope creep.

## Issues Encountered
None beyond the deviation documented above.

## Validation
Full `Pkg.test()` after both tasks: **1909 pass, 5 fail, 0 error, 2 broken** (1916 total, ~4m32s).
- `test_experiments.jl`: 31 pass, 4 fail — every fail is in an item explicitly owned by 08-04 ("EXP-02 sweep" 1 fail, "EXP-02 sweep diff-friendly" 2 fails, "INFRA-04 provenance tagsave" 1 fail — `run_sweep`/`collate_summary`/`run_and_store` are still comment-only stubs). This plan's five target items ("EXP-01 scenario centralized", "EXP-01 scenario admm", "EXP-01 scenario strategy guard", "INFRA-04 same-seed repro", "INFRA-04 seed sensitivity") are ALL green.
- The remaining 1 fail (Aqua stale-deps, nested under `test_toy_dc.jl`) and 2 broken (pre-existing `@test_broken` in Phase 5/7 files) are the SAME pre-existing gaps logged in 08-02's `deferred-items.md`, unrelated to this plan's changes (resolves in 08-04 once `store.jl`/`sweep.jl` land and use CSV/DrWatson/DataFrames).
- No regressions in `test_admm.jl` (34 pass), `test_welfare_solve.jl` (137 pass), `test_pricing_dlmp.jl` (337 pass), or any other pre-existing suite.

## Next Phase Readiness
- **08-04** (store + sweep): can now implement `run_and_store` (`@tagsave` provenance) and `run_sweep`/`collate_summary` (`dict_list` → diff-friendly CSV), consuming this plan's `ScenarioResult`/`run_scenario` directly — turning the remaining "EXP-02 sweep"/"EXP-02 sweep diff-friendly"/"INFRA-04 provenance tagsave" RED testitems green.
- No blockers. `run_scenario` is fully path-free and dependency-light (no DrWatson/CSV import), confirming EXP-01 + the INFRA-04 same-seed gate are independently testable ahead of the storage layer, as designed.

---
*Phase: 08-experiment-harness-reproducibility*
*Completed: 2026-07-19*

## Self-Check: PASSED
- FOUND: src/experiments/run.jl
- FOUND: src/experiments/Scenario.jl
- FOUND: .planning/phases/08-experiment-harness-reproducibility/08-03-SUMMARY.md
- FOUND commit: a5c7a9b
- FOUND commit: d1ef249
