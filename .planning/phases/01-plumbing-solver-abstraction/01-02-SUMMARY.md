---
phase: 01-plumbing-solver-abstraction
plan: 02
subsystem: data
tags: [julia, per-unit, feeder, topology, sparsearrays, radial-validation, immutable-structs, tdd]

# Dependency graph
requires:
  - phase: 01-plumbing-solver-abstraction (plan 01-01)
    provides: "TSODSO package scaffold, include-graph seam stubs, red Wave 0 @testitem harness"
provides:
  - "PerUnitBase{T} + convert-once-at-ingestion helpers (to_pu_power, to_pu_impedance, Z_base, I_base)"
  - "assert_magnitudes(feeder) + assert_magnitudes_voltage(v) magnitude tripwires (INFRA-05)"
  - "Immutable JuMP-free Bus{T}/Branch{T}/Feeder{T} structs (DATA-01)"
  - "assert_radial: edge-count + sparse incidence + BFS connectivity + single-root tree check (DATA-02)"
  - "Feeder(...) construction gate that runs BOTH assert_radial and assert_magnitudes on the live path"
affects: [powerflow, models, operational-layer, planning-layer, data-fixtures]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Convert SI→pu ONCE at ingestion; magnitude @assert tripwires guard SI/pu mixing (RESEARCH Pattern 5, Pitfall 5)"
    - "Validation as a construction invariant inside the INNER constructor (suppresses Julia's auto-generated non-validating constructor; no bypass, no precompile method-overwriting)"
    - "Tree check via edges==nodes-1 ∧ BFS-connected ∧ one root — no cycle detection, no Graphs.jl (RESEARCH Pattern 4)"
    - "Duck-typed cross-seam helper (assert_magnitudes(feeder)) resolved at call time to respect include order"

key-files:
  created:
    - .planning/phases/01-plumbing-solver-abstraction/01-02-SUMMARY.md
  modified:
    - src/units/PerUnit.jl
    - src/data/Feeder.jl
    - src/data/topology.jl
    - test/test_perunit.jl
    - test/test_feeder.jl
    - test/test_topology.jl

key-decisions:
  - "Put Feeder validation in the INNER constructor (not an outer method): Julia 1.12 forbids overwriting the auto-generated outer constructor at precompile, and an inner constructor cleanly suppresses auto-generation so validation cannot be bypassed"
  - "Kept the scalar assert_magnitudes_voltage(v) helper referenced by the pre-existing red test AND added the feeder-level assert_magnitudes(feeder) required by the plan interface"
  - "Bus id == 1-based position convention (Phase 1); assert_radial guards root ∈ 1:N with a clear ArgumentError"

patterns-established:
  - "Construction-invariant data model: an invalid (non-tree or out-of-band) feeder can never exist"
  - "Sparse node-branch incidence returned by assert_radial for reuse by the model layer"

requirements-completed: [DATA-01, DATA-02, INFRA-05]

# Metrics
duration: 22min
completed: 2026-07-18
---

# Phase 1 Plan 02: Feeder Data Model & Per-Unit System Summary

**Immutable, JuMP-free radial feeder structs whose construction enforces both a tree-topology invariant (sparse incidence + BFS, no Graphs.jl) and per-unit magnitude tripwires, plus a convert-once-at-ingestion per-unit system — driving the perunit/feeder/topology Wave 0 @testitems green (24/24).**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-07-18
- **Completed:** 2026-07-18
- **Tasks:** 2 (both TDD: RED → GREEN)
- **Files modified:** 6 (3 source, 3 test)

## Accomplishments
- `PerUnitBase{T}` with `Z_base`/`I_base` derived bases and `to_pu_power`/`to_pu_impedance` convert-once helpers, documented placeholder base `S_base=1.0 MVA`, `V_base=4.16 kV` (INFRA-05).
- `assert_magnitudes(feeder)` + `assert_magnitudes_voltage(v)` loud `AssertionError` tripwires (voltage ∈ [0.8,1.2], `0 ≤ r,x < 5`, `0 < smax < 100`) naming the offending bus/branch.
- Immutable, concretely-typed `Bus{T}`/`Branch{T}`/`Feeder{T}` structs holding per-unit numbers only (DATA-01).
- `assert_radial` tree check: edge-count theorem → sparse `N×B` incidence (`SparseArrays.sparse`) → ~15-line BFS connectivity → single-root, each failure a clear `ArgumentError`; returns the incidence for the model layer (DATA-02).
- `Feeder(...)` construction runs BOTH `assert_radial` AND `assert_magnitudes` on the live path, so downstream consumers inherit validated data for free.

## Task Commits

Each task was committed atomically (TDD: test → feat):

1. **Task 1: Per-unit system + magnitude tripwires** — `a858573` (test), `f155d2a` (feat)
2. **Task 2: Immutable feeder structs + radial validation** — `6b1316a` (test), `dc9fce8` (feat)

**Plan metadata:** (this SUMMARY, committed separately)

## Files Created/Modified
- `src/units/PerUnit.jl` — `PerUnitBase{T}`, derived bases, convert-once helpers, magnitude assertions + exports.
- `src/data/Feeder.jl` — immutable `Bus{T}`/`Branch{T}`/`Feeder{T}`; inner constructor enforces both invariants; outer constructor infers `T`.
- `src/data/topology.jl` — `assert_radial` (sparse incidence + BFS), returns incidence; exports.
- `test/test_perunit.jl` — derived-base, convert-once, and in-band/out-of-band (low+high) AssertionError coverage.
- `test/test_feeder.jl` — valid construction, immutability (`ismutabletype` + `setfield!` throws), wrong-branch-count rejection, and live-path out-of-band magnitude rejection.
- `test/test_topology.jl` — valid tree + incidence shape; wrong branch count, disconnected, zero-root, two-root ArgumentError cases.

## Decisions Made
- **Inner-constructor validation.** Placing `assert_radial`/`assert_magnitudes` in `Feeder{T}`'s inner constructor suppresses Julia's auto-generated non-validating constructor and avoids the Julia-1.12 "method overwriting not permitted during precompilation" error that an outer-constructor override triggers. This also makes the validation impossible to bypass.
- **Both scalar and feeder-level magnitude asserts.** The pre-existing red `test_perunit` item (authored in plan 01-01) references `assert_magnitudes_voltage(0.1)`; I implemented that scalar helper AND the `assert_magnitudes(feeder)` required by the plan `<interfaces>`, with the latter reusing the same band constants.
- **No Graphs.jl.** Connectivity is a hand-rolled BFS per RESEARCH "Don't Hand-Roll" guidance; `Project.toml` gains no dependency. `SparseArrays` (already a dep) is now genuinely used, retiring the Aqua stale-dependency flag noted by plan 01-01.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Auto-generated constructor silently bypassed validation**
- **Found during:** Task 2 (feeder construction)
- **Issue:** The first implementation defined a validating OUTER `Feeder(...)` with `root::Integer`. Julia auto-generates an outer constructor with `root::Int` (from the field type), which is more specific and won dispatch for the `Int` argument in the tests — so `Feeder(buses, branches, 1)` skipped validation ("No exception thrown").
- **Fix:** Moved validation into the INNER constructor `Feeder{T}(...)`, which suppresses all auto-generated constructors; added a thin outer constructor to infer `T`.
- **Files modified:** src/data/Feeder.jl
- **Verification:** `feeder` and `topology` @testitems now green including wrong-branch-count and out-of-band-magnitude rejections on the live `Feeder(...)` path.
- **Committed in:** `dc9fce8` (Task 2 feat commit)

**2. [Rule 3 - Blocking] Julia 1.12 method-overwriting precompile error**
- **Found during:** Task 2 (first fix attempt for deviation #1)
- **Issue:** Redefining the auto-generated outer constructor with an identical `root::Int` signature triggered "Method overwriting is not permitted during Module precompilation" on Julia 1.12.5 — a hard error, not a warning.
- **Fix:** Same inner-constructor restructuring as #1 (defining an inner constructor prevents the auto-generation entirely, so nothing is overwritten).
- **Files modified:** src/data/Feeder.jl
- **Verification:** Clean precompile (no method-overwriting warning) and 24/24 @testitems green.
- **Committed in:** `dc9fce8` (Task 2 feat commit)

**3. [Rule 3 - Blocking] Test runner for a test-only dependency**
- **Found during:** Task 1 (RED/GREEN verification)
- **Issue:** The plan's literal verify command `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=...'` cannot load `TestItemRunner` (correctly a test-only dep). Additionally, `Pkg.test()` runs the FULL suite, which includes the parallel agent's seams (factory/status/toy_dc) that remain red stubs in this isolated worktree.
- **Fix:** Built a scratch environment (`Pkg.develop(path=worktree)` + `TestItemRunner`) and invoked the public `TestItemRunner.run_tests(worktree; filter=...)` to run exactly the perunit/feeder/topology items. Mirrors the 01-01 deviation rationale.
- **Files modified:** none (tooling only; scratch env outside the repo)
- **Verification:** Filtered runs show 24 pass / 0 fail / 0 error for my three seams.
- **Committed in:** n/a (no repo change)

---

**Total deviations:** 3 (2 blocking + 1 bug), all resolved
**Impact on plan:** All fixes were necessary for correctness (validation must actually run) and to compile on the installed Julia 1.12. No scope creep — no files outside `units/` + `data/` + their tests were touched, and no dependency was added.

## Issues Encountered
- None beyond the deviations above. The other Wave-2 agent's seams (solver/core/powerflow) remain red stubs in this isolated worktree, as expected; only the three seams owned by this plan were driven green.

## Known Stubs
None. All three seams (`PerUnit.jl`, `Feeder.jl`, `topology.jl`) are fully implemented; no placeholder values or unwired data paths remain.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The JuMP-free data keystone is complete: downstream layers (the plan 01-04 toy solve, and every later power-flow phase) can consume validated, immutable `Feeder{T}` structs and the returned sparse incidence.
- `assert_magnitudes(feeder)` firing on the live `Feeder(...)` path means the walking-skeleton solve inherits magnitude sanity without extra wiring.
- No blockers. Per-unit base values remain documented placeholders to be superseded by real IEEE fixtures in Phase 4 (DATA-03), as planned.

## Self-Check: PASSED
- All source files exist: `src/units/PerUnit.jl`, `src/data/Feeder.jl`, `src/data/topology.jl`.
- All task commits exist: `a858573` (test), `f155d2a` (feat), `6b1316a` (test), `dc9fce8` (feat).
- No modifications to `STATE.md`/`ROADMAP.md`; no edits outside `units/` + `data/` + their test files.

---
*Phase: 01-plumbing-solver-abstraction*
*Completed: 2026-07-18*
