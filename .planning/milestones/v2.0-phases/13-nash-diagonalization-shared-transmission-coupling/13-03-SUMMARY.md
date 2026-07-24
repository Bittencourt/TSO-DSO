---
phase: 13-nash-diagonalization-shared-transmission-coupling
plan: 03
subsystem: planning
tags: [jump, highs, nash-diagonalization, gauss-seidel, multi-seed-probe, honesty-gate]

# Dependency graph
requires:
  - phase: 13-02-nash-diagonalization-loop
    provides: "run_nash!/NashTrace outer Gauss-Seidel diagonalization loop (src/planning/nash.jl), plot_nash_convergence"
  - phase: 13-01-shared-transmission-coupling
    provides: "SharedTransmission/build_shared_transmission build-once N-distributor shared corridor (src/planning/coupling.jl)"
provides:
  - "run_nash_probe: the multi-seed/multi-order honesty gate (NASH-04) — repeats run_nash! across a hand-picked >=3-seed x >=2-order matrix, each against a FRESH SharedTransmission, asserts every combination converges, and reports max-pairwise-distance spread"
  - "Structural 'a converged equilibrium' (never 'the equilibrium') summary-string contract, enforced by construction and regressed directly"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Zero-argument factory closure (build_shared) for fresh mutable-state construction per probe run — the same 'never reuse a destructively-mutated handle' discipline as run_nash!'s own SharedTransmission contract, one level up"
    - "No try/catch around a fail-loud inner call, by design — the gating contract requires propagation, not summarization, of a single non-converging run"

key-files:
  created: []
  modified:
    - src/planning/nash.jl
    - test/test_planning_nash.jl

key-decisions:
  - "Fixed a shape bug in the plan's own literal skewed seed matrix ([0.5;;0.1], which Julia parses as a 1x2 row matrix via the ;; hcat-along-dim-2 syntax) to [0.5; 0.1;;] (a genuine 2x1 column matrix) — required to satisfy run_nash!'s own size(z0) == (shared.N, shared.T) boundary guard for the N=2 fixture (and its N=3 analog)."
  - "Spread and convergence guards enforced entirely inside run_nash_probe (no separate validation layer) — mirrors this file's own run_nash!/NashTrace discipline of fail-loud ArgumentError/ErrorException over soft warnings."

patterns-established: []

requirements-completed: [NASH-04]

# Metrics
duration: 25min
completed: 2026-07-24
---

# Phase 13 Plan 03: Nash Multi-Seed/Multi-Order Probe Summary

**`run_nash_probe` — the phase's own honesty gate: repeats `run_nash!` across a >=3-seed x >=2-order matrix (>=6 independent runs, each against a fresh `SharedTransmission`), asserts EVERY run converges (a phase-gating regression, never a soft warning), and reports the observed max-pairwise-distance spread via a structurally "a converged equilibrium (never "the equilibrium")" summary string.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-23T23:54:42-03:00
- **Completed:** 2026-07-24T00:14:24-03:00
- **Tasks:** 2 completed
- **Files modified:** 2

## Accomplishments
- `src/planning/nash.jl`: `run_nash_probe(specs, build_shared; seeds, orders, tol_outer, max_sweeps, checkpoint_dir)` — boundary guards (`length(seeds) >= 3`, `length(orders) >= 2`, valid order symbols) fire before any solve; enumerates every `(seed, order)` combination against a FRESH `SharedTransmission` built via a zero-argument factory closure (never a reused mutable instance); contains NO `try`/`catch` around the underlying `run_nash!` call so a single non-converging combination's `ErrorException` propagates uncaught; computes `spread = (; z_spread, x_inv_spread, cost_spread)` as the MAXIMUM pairwise distance across all `C(n_runs, 2)` combinations (never a mean/variance); returns `(; runs, spread, summary, n_runs)` where `summary` is structurally guaranteed to contain `"a converged equilibrium"` and never `"the equilibrium"`.
- `test/test_planning_nash.jl`: 4 new `@testitem`s (testitems 10-13) — the N=2 gating probe (3 seeds x 2 orders = 6 runs, all converge, structural language, finite non-negative spread), an N=3 probe (no closed-form hand-check required per CONTEXT.md's own scope split), a deliberately-too-tight `max_sweeps=1` propagation regression, and the `<3 seeds`/`<2 orders` guard regression.
- Full test suite (`Pkg.test()`-equivalent, TestItemRunner) run TWICE independently, both green: 2231 passed, 3 broken (CairoMakie-weakdep-skipped, expected), 0 failed, 0 errored.
- All 4 phase requirement IDs (NASH-01/02/03/04) are now covered across the three plans of Phase 13.

## Task Commits

Each task was committed atomically:

1. **Task 1: run_nash_probe — multi-seed/multi-order gate + spread reporting** - `132f94f` (feat)
2. **Task 2: gating tests — N=2 probe (>=6 runs), N=3 probe, structural-language regression** - `b6f01e6` (test)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified
- `src/planning/nash.jl` - `run_nash_probe`: boundary guards, fresh-`SharedTransmission`-per-run factory discipline, uncaught-propagation contract, max-pairwise-distance spread computation, structural summary-string construction
- `test/test_planning_nash.jl` - 4 new `[:planning]`-tagged testitems (10-13) covering the N=2 gating probe, N=3 probe, non-convergence propagation, and guard enforcement

## Decisions Made
- Fixed a shape bug in the plan's own literal `skewed` seed matrix: the plan's action text specifies `skewed = [0.5;;0.1]`, which Julia's `;;` syntax parses as horizontal concatenation (a 1x2 row matrix), not the `(shared.N, shared.T) = (2, 1)` column shape `run_nash!`'s own boundary guard requires. Corrected to `[0.5; 0.1;;]` (a genuine 2x1 column matrix) in both the N=2 test fixture and its N=3 analog (`[0.5; 0.1; 0.3;;]`).
- No new architectural decisions — this plan is pure orchestration over the already-hardened `run_nash!`/`SharedTransmission` layers from plans 13-01/13-02, exactly as CONTEXT.md scoped it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's literal `skewed` seed-matrix syntax produces the wrong matrix shape**
- **Found during:** Task 2, writing the N=2 gating-probe testitem
- **Issue:** The plan's action text literally specifies `skewed = [0.5;;0.1]` for the N=2 fixture. Julia's `[a;;b]` syntax is explicit horizontal concatenation (`hcat`), producing a `1x2` matrix (`[0.5 0.1]`) — not the `(shared.N, shared.T) = (2, 1)` column shape `run_nash!`'s own `size(z0) == (shared.N, shared.T)` boundary guard requires (verified directly: `size([0.5;;0.1]) == (1, 2)`).
- **Fix:** Changed to `[0.5; 0.1;;]` (semicolon vcat, with a trailing `;;` to force a genuine `Matrix` rather than a `Vector`), which correctly produces `(2, 1)`. Applied the equivalent fix to the N=3 fixture's own skewed seed (`[0.5; 0.1; 0.3;;]`, shape `(3, 1)`).
- **Files modified:** `test/test_planning_nash.jl`
- **Verification:** `julia -e 'println(size([0.5; 0.1;;]))'` → `(2, 1)`; both the N=2 gating-probe and N=3 probe testitems pass with this corrected literal.
- **Committed in:** `b6f01e6` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — a matrix-shape bug in the plan's own literal test fixture text, discovered and fixed before it could produce a spurious `ArgumentError` from `run_nash!`'s own boundary guard)
**Impact on plan:** The fix was necessary for correctness (the literal as written would not satisfy `run_nash!`'s own `size(z0)` guard). No scope creep — the seed VALUES themselves (0.5 favoring distributor 1, 0.1 favoring distributor 2) are unchanged from the plan's intent; only the Julia array-literal syntax used to express the correct shape was corrected.

## Issues Encountered
None beyond the deviation documented above. The `TestItemRunner` cross-worktree scan-path issue flagged by 13-02's own executor was avoided throughout this plan by using `TestItemRunner.run_tests(<explicit absolute test directory path>; filter=...)` from a dedicated scratch environment (mirroring 13-02's own established workaround), never the bare `@run_package_tests` macro form.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 13 (nash-diagonalization-shared-transmission-coupling) is now complete: `coupling.jl` (NASH-01, plan 13-01), `run_nash!`/`NashTrace`/`plot_nash_convergence` (NASH-02/03, plan 13-02), and `run_nash_probe` (NASH-04, this plan) together discharge all four phase requirement IDs.
- STATE.md's own carried blocker ("Gauss-Seidel Nash diagonalization has no general uniqueness/convergence guarantee — every reported equilibrium must carry a multi-seed/multi-order probe; never present one run as 'the' equilibrium") is now discharged in code, not merely documentation: `run_nash_probe`'s gating contract and structural summary-string language enforce this directly, regressed by testitems 10-13.
- No blockers for the next phase (Phase 14, per ROADMAP.md).

---
*Phase: 13-nash-diagonalization-shared-transmission-coupling*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: src/planning/nash.jl
- FOUND: test/test_planning_nash.jl
- FOUND: run_nash_probe defined in src/planning/nash.jl
- FOUND: commit 132f94f (Task 1)
- FOUND: commit b6f01e6 (Task 2)
