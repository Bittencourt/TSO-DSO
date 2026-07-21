---
phase: 04-convex-branch-flow-correctness-milestone
plan: 03
subsystem: data
tags: [ieee13, feeder, per-unit, fixture, radial, socp, julia]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "Bus/Branch/Feeder immutable structs + assert_radial (DATA-02) + assert_magnitudes (INFRA-05) + PerUnitBase/to_pu_power"
provides:
  - "ieee13_modified() built-in fixture: radial-validated per-unit Feeder (11 buses / 10 branches) from thesis Table 4.1"
  - "IEEE13_BASE (100 MVA / 13.2 kV) and IEEE13_INTERIOR_SMAX (99.0 pu sentinel) constants"
  - "Documented thesis-node -> struct-index (k -> k+1) map for the 04-06 ground-truth regression"
affects: [04-04-oracle, 04-05-exactness, 04-06-ground-truth-regression]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SI->pu conversion done ONCE at ingestion via to_pu_power on a single documented base"
    - "Effectively-unconstrained branches use a sentinel strictly inside the magnitude tripwire band (99.0 < SMAX_PU_MAX=100.0)"

key-files:
  created: []
  modified:
    - src/data/ieee13.jl
    - test/test_ieee13.jl

key-decisions:
  - "Interior branches use 99.0 pu (not the RESEARCH sketch's 100.0) to pass the STRICT 0<smax<100 band"
  - "Head-branch S_max computed via to_pu_power(6.86, IEEE13_BASE) = 0.0686 pu, not a hardcoded literal"
  - "test_ieee13.jl kept solve-free; the SOCP solve/ground-truth items are deferred to plan 04-06"

patterns-established:
  - "Built-in feeder fixtures live in src/data/ and construct through the validating Feeder(...) gate"

requirements-completed: [DATA-03]

# Metrics
duration: ~12min
completed: 2026-07-18
---

# Phase 04 Plan 03: Modified IEEE-13 Feeder Fixture Summary

**`ieee13_modified()` ships the modified IEEE 13-node feeder from thesis Table 4.1 as an immutable, radial-validated, per-unit `Feeder` — 11 buses / 10 branches, head branch at 0.0686 pu, interior branches at a 99.0 pu sentinel, node k -> struct index k+1.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-18
- **Completed:** 2026-07-18
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `ieee13_modified()` builds the 11-bus/10-branch modified IEEE-13 feeder from thesis Table 4.1 (base 100 MVA / 13.2 kV), validated at construction by `assert_radial` + `assert_magnitudes`.
- Head branch (thesis 0->1, struct index 1->2) carries the single binding thermal limit `S_max = 6.86 MVA => 0.0686 pu`, converted once via `to_pu_power`.
- Interior branches use the `IEEE13_INTERIOR_SMAX = 99.0` pu sentinel — effectively unconstrained yet strictly inside the `0 < smax < 100` magnitude band (the RESEARCH sketch's `100.0` would have thrown).
- The thesis-node -> struct-index map (`k -> k+1`, so thesis node 9 = struct index 10) is documented in the docstring for the 04-06 ground-truth regression.
- The `ieee13` fixture @testitems are GREEN (19/19): construction, counts, root, head-branch limit, interior sentinel, voltage bounds, and Table 4.1 topology spot-checks.

## Task Commits

Each task was committed atomically:

1. **Task 1: ieee13_modified() built-in feeder from Table 4.1** - `20ec2e4` (feat)
2. **Task 2: Turn the ieee13 fixture @testitems green** - `e788024` (test)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified
- `src/data/ieee13.jl` - Fills the DATA-03 seam stub with `ieee13_modified()`, `IEEE13_BASE`, and `IEEE13_INTERIOR_SMAX`; exports `ieee13_modified`. Docstring documents the base, the node->index shift, the sole binding head branch, and the 99.0 sentinel rationale.
- `test/test_ieee13.jl` - Two fixture-level @testitems (construction/counts/root; magnitudes + Table 4.1 topology spot-checks). Solve/ground-truth items deferred to 04-06; file is solve-free.

## Decisions Made
- **99.0 interior sentinel over the RESEARCH sketch's 100.0.** `assert_magnitudes` enforces a STRICT `0 < smax < 100`; `100.0` fails at construction. 99.0 is the largest round value that passes while remaining far above any physical interior flow, so only the head branch binds (Assumption A4 / Open Q2). This is exactly the T-04-11 mitigation in the plan's threat register.
- **Head `smax` via `to_pu_power(6.86, IEEE13_BASE)` rather than a hardcoded 0.0686.** Keeps the single SI->pu conversion explicit and traceable at ingestion (T-04-04 mitigation), and asserts the resulting 0.0686 pu in the test.
- **`test_ieee13.jl` kept solve-free.** The SOCP GLB-CVX solve (OPT-02) and thesis-number ground-truth regression (OPT-02/OPT-03) depend on `ConvexBranchFlow` (plan 04-02, parallel this wave) and the pinned golden (plan 04-06). Per Task 2's explicit acceptance criteria ("No solve is attempted in this file (that is deferred to 04-06's 'ground' items)"), the two solve/ground @testitems from the 04-01 RED harness were removed from this file; plan 04-06 owns re-adding them.

## Deviations from Plan

**1. [Rule 3 - Blocking] Removed solve/ground @testitems that reference undelivered seams**
- **Found during:** Task 2 (turn ieee13 fixture items green)
- **Issue:** The 04-01 RED harness placed two additional @testitems in `test/test_ieee13.jl` (GLB-CVX SOCP solve; thesis-number ground regression) whose bodies hard-assert `isdefined(TSODSO, :ConvexBranchFlow)` and call `solve_welfare`. `ConvexBranchFlow` is owned by plan 04-02 (running in parallel this wave, not present in this worktree's base), so those items are RED and would keep the `occursin("ieee13")` verification filter failing.
- **Fix:** Restructured `test/test_ieee13.jl` to contain only fixture-level items, matching Task 2's explicit action ("Do NOT add the SOCP solve here — that is 04-06") and acceptance criterion ("No solve is attempted in this file"). Deferral to plan 04-06 is documented in the file header.
- **Files modified:** test/test_ieee13.jl
- **Verification:** `Pkg.test()` reports `test/test_ieee13.jl | 19 pass / 0 fail`; the 9 remaining suite failures are all in other seams (test_oracle, test_convex_branch_flow, test_exactness, test_conformance) owned by parallel/later plans — none in the data/feeder/perunit/topology domain.
- **Committed in:** `e788024` (Task 2 commit)

---

**Total deviations:** 1 (1 blocking — scope-aligned file restructure per Task 2 acceptance criteria)
**Impact on plan:** No scope creep. The change is exactly what Task 2's acceptance criteria mandate; solve/ground coverage is explicitly the responsibility of plan 04-06.

## Issues Encountered
- Running the filtered `@run_package_tests` under `--project=test` mis-resolved the `TSODSO` package path (pulling test files from sibling worktrees). Resolved by using the authoritative `julia --project=. -e 'import Pkg; Pkg.test()'`, which sandboxes and dev-links `TSODSO` to this worktree correctly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `ieee13_modified()` is the centralized ground-truth network for the correctness milestone; plans 04-04 (oracle), 04-05 (exactness), and 04-06 (ground-truth regression) can consume it directly.
- The node->index map (thesis node 9 = struct index 10) is documented for the 04-06 voltage/DADP regression (`|V9|[16]`).
- Plan 04-06 must re-add the SOCP solve and thesis-number ground @testitems to `test/test_ieee13.jl` (deferred here per acceptance criteria) once `ConvexBranchFlow` (04-02) and the pinned golden land.

## Self-Check: PASSED

- src/data/ieee13.jl — FOUND (contains `ieee13_modified`)
- test/test_ieee13.jl — FOUND
- 04-03-SUMMARY.md — FOUND
- Commit 20ec2e4 (Task 1) — FOUND
- Commit e788024 (Task 2) — FOUND

---
*Phase: 04-convex-branch-flow-correctness-milestone*
*Completed: 2026-07-18*
