---
phase: 06-admm-decomposition-core
plan: 01
subsystem: infra
tags: [admm, jump, socp, dual-decomposition, residuals, testitems, fixtures, cross-validation]

# Dependency graph
requires:
  - phase: 05-distribution-pricing
    provides: "extract_dlmp (DADP ground-truth duals), pricing/welfare.jl include anchor"
  - phase: 04-socp-branch-flow
    provides: "solve_welfare centralized SOCP, ConvexBranchFlow, assert_socp_exact!, IEEE-13 ground fixture"
  - phase: 03-devices
    provides: "Aggregator.contribute! + device contribute! builders (reused by AGR-OPT), generate_profiles"
  - phase: 01-foundation
    provides: "Feeder/Bus/Branch, ModelContext, select_optimizer, SMAX_NO_LIMIT, TSODSO include graph"
provides:
  - "src/admm/ module wired into the TSODSO include graph (residuals -> AgrOpt -> DsoOpt -> solve_admm)"
  - "AdmmResiduals: a JuMP-free primal/dual residual ledger (record!/converged) reused unchanged by Phase 7"
  - "Comment-only AGR-OPT / DSO-OPT / solve_admm seam stubs awaiting Waves 2-3"
  - "Phase6Fixtures @testmodule: two_bus_feeder dual-sign anchor + build_two_bus_aggregators + RHO_2BUS + λ₀"
  - "RED @testitem cross-validation/build-once harness pinning the solve_admm contract (ADMM-04 false-convergence net)"
affects: [06-02-agr-opt, 06-03-dso-opt, 06-04-solve-admm-loop, 07-convergence-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-owner include-graph edit: this plan is the sole editor of src/TSODSO.jl for Phase 6, keeping Waves 2-3 file-disjoint"
    - "RED @testitem via isdefined(TSODSO, :symbol) guard: fails loud, never crashes discovery, auto-activates the guarded behavioral body when the code lands"
    - "JuMP-free residual ledger shared across phases (Phase-6 primal-only stop / Phase-7 dual+adaptive-ρ on the same traces)"

key-files:
  created:
    - "src/admm/residuals.jl (AdmmResiduals struct + record!/converged, filled)"
    - "src/admm/AgrOpt.jl (comment-only stub, owner 06-02)"
    - "src/admm/DsoOpt.jl (comment-only stub, owner 06-03)"
    - "src/admm/solve_admm.jl (comment-only stub, owner 06-04)"
    - "test/fixtures_phase6.jl (@testmodule Phase6Fixtures)"
    - "test/test_admm.jl (RED cross-validation/build-once harness)"
  modified:
    - "src/TSODSO.jl (four ADMM includes inserted after pricing/welfare.jl)"

key-decisions:
  - "AdmmResiduals stores per-iteration worst |R_p| / |ρ·Δ| MAGNITUDES with a sequential-k fail-loud guard; converged() is primal-only (Phase-6 scope), leaving the dual-residual stop to Phase 7"
  - "RED items reference solve_admm/AgrOpt/DsoOpt via isdefined guards (test_dlmp.jl precedent) so discovery stays healthy (0 errored) while the items fail loud"
  - "2-bus anchor uses r=x=1e-3 (near-lossless, in the 0<=r,x<5 band) + SMAX_NO_LIMIT + PV<load so the load-bus DADP ≈ λ₀ > 0 pins the price sign"
  - "The full house (therm+defer+batt) shape is reused for the 2-bus aggregator, scaled small (load 0.02 / PV 0.005) for feasibility and net-consumer sign"

patterns-established:
  - "Pattern 1: ADMM seam stubs are comment-only (zero code lines) until their owning wave fills them and declares exports"
  - "Pattern 2: the solve_admm return-tuple contract (welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap) is pinned by the RED tests before implementation"

requirements-completed: [ADMM-01]

# Metrics
duration: 14min
completed: 2026-07-19
---

# Phase 6 Plan 01: ADMM Decomposition Core Foundation Summary

**Wired the src/admm/ module into the TSODSO include graph, filled the JuMP-free AdmmResiduals ledger, and stood up the 2-bus dual-sign-anchor fixture plus the RED cross-validation/build-once @testitem harness that pins the solve_admm correctness contract — all without regressing the 1065-test Phase-5 baseline.**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-07-19T01:34:04Z (base commit)
- **Completed:** 2026-07-19T01:47:45Z
- **Tasks:** 3
- **Files modified:** 7 (6 created, 1 modified)

## Accomplishments
- ADMM module is on the include graph: four includes (residuals -> AgrOpt -> DsoOpt -> solve_admm) inserted additively after pricing/welfare.jl; package precompiles clean; no Phase-5 source file touched.
- `AdmmResiduals` is a reusable, JuMP-free residual ledger with `record!` (sequential-k guard, magnitude storage) and a primal-only `converged` predicate — the shape Phase 7 reuses for dual-residual + adaptive-ρ.
- `Phase6Fixtures` provides the new 2-bus dual-sign anchor (`two_bus_feeder`, `build_two_bus_aggregators`, `two_bus_lambda0`, `RHO_2BUS`), obeying the defines-only CONTRACT (no ADMM symbol evaluated at load time) and reusing the seeded `generate_profiles` draw.
- Three RED `@testitem`s (crossval 2-bus, crossval IEEE-13, build-once resolve) pin the ADMM-04 cross-validation contract; the full suite reports **1065 passed, 3 failed (admm RED), 1 broken (pre-existing), 0 errored** — the false-convergence net is armed and the runner is healthy.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire src/admm include graph + subproblem/loop stubs** - `5a6214d` (feat)
2. **Task 2: Fill AdmmResiduals tracking struct** - `1aef3b1` (feat) — TDD: RED confirmed (UndefVarError) then GREEN
3. **Task 3: Phase6Fixtures + RED cross-validation/build-once harness** - `855a6b6` (test)

**Plan metadata:** this SUMMARY commit (docs)

## Files Created/Modified
- `src/TSODSO.jl` - Inserted the four ADMM includes after pricing/welfare.jl, in dependency order, with a header comment documenting single-owner + orchestration-not-reimplementation.
- `src/admm/residuals.jl` - `mutable struct AdmmResiduals` (N, T, primal_trace, dual_trace, iters) + `record!`/`converged`; pure data, no JuMP/solver.
- `src/admm/AgrOpt.jl` - Comment-only stub for the per-node aggregator QP (thesis 3.46, owner 06-02).
- `src/admm/DsoOpt.jl` - Comment-only stub for the whole-network SOCP subproblem (thesis 3.47, owner 06-03).
- `src/admm/solve_admm.jl` - Comment-only stub for the hand-rolled dual-ascent loop (thesis 3.31 dual, owner 06-04).
- `test/fixtures_phase6.jl` - `@testmodule Phase6Fixtures`: 2-bus dual-sign anchor + seeded aggregator + RHO_2BUS + flat λ₀.
- `test/test_admm.jl` - Three RED `@testitem`s pinning the solve_admm welfare/DADP cross-validation and the build-once/no-rebuild invariant.

## Decisions Made
- **Residual magnitudes + sequential-k guard:** `record!` stores `abs(...)` (matching the `|R_p|`/`|ρ·Δ|` worst-case definitions) and throws if `k != iters+1`, following the project's fail-loud convention. `converged` is deliberately primal-only for Phase-6 scope (RESEARCH Pattern 2 / Pitfall 2); the dual-residual stop is Phase 7.
- **RED via isdefined guards:** mirrors the proven `test_dlmp.jl` precedent so the items fail loud on the missing `solve_admm` symbol while the behavioral asserts sit behind the guard and go live automatically when Wave 3 lands (0 errored confirms discovery health).
- **2-bus calibration:** near-lossless `r=x=1e-3` + `SMAX_NO_LIMIT` + PV(0.005) < load(0.02) keeps bus 2 an interior net consumer so the analytic DADP ≈ λ₀ > 0 anchors the price sign.
- **residuals.jl created in Task 1 as a stub, filled in Task 2:** the include for `residuals.jl` is added in Task 1 (all four includes land together), so the file must exist for `using TSODSO` to load; Task 2 fills it in place (no additional TSODSO.jl edit).

## Deviations from Plan

None - plan executed exactly as written. (residuals.jl was created as a comment-only stub during Task 1 so the Task-1 include graph loads, then filled during Task 2 as specified — this is the plan's intended sequencing, not a deviation.)

## Issues Encountered
- During Task-3 verification a `cd` into the shared main checkout (instead of the worktree) caused a stray grep miss and a TestItemRunner-not-found error; re-run inside the worktree with the correct paths. No code impact — all commits are on the worktree agent branch.
- The fixtures comment initially contained the literal token `solve_admm` (in prose), tripping the "no ADMM-symbol reference in fixtures" acceptance grep; reworded to "the Wave-3 loop's ρ keyword" before committing Task 3.

## User Setup Required
None - no external service configuration required. No package installs (Manifest.toml unchanged).

## Next Phase Readiness
- **Wave 2 (06-02 AGR-OPT, 06-03 DSO-OPT):** the seam stubs, the AdmmResiduals ledger, and the RED build-once/crossval gates are in place; those plans fill AgrOpt.jl/DsoOpt.jl and declare their exports without touching TSODSO.jl.
- **Wave 3 (06-04 solve_admm):** the RED cross-validation contract (welfare ≈ centralized objective, λ ≈ extract_dlmp, PF-04 exactness) is pinned on the 2-bus + IEEE-13 fixtures for the loop to drive green.
- **No STATE.md / ROADMAP.md edits** were made (parallel-execution constraint); the orchestrator owns those updates.

## Self-Check: PASSED

- All 6 created files present + `src/TSODSO.jl` modified (4 admm includes).
- All 3 task commits found in git history (`5a6214d`, `1aef3b1`, `855a6b6`).
- Full suite: 1065 passed, 3 failed (admm RED), 1 broken (pre-existing), 0 errored.

---
*Phase: 06-admm-decomposition-core*
*Completed: 2026-07-19*
