---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 02
subsystem: pricing-certificate
tags: [socp, exactness-gate, jump, clarabel, pf-04, fix-08]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: per-fixture Clarabel tol_gap calibrations (cluster-E fixtures) that interact
      with the new per-branch exactness floor
provides:
  - assert_socp_exact! HYBRID per-branch exactness floor (atol_b = max(τ_solver, ε*ref_b)),
    replacing the flat atol=1e-6 default
  - MEASURED_ε_FIX08 = 1e-9 and TAU_SOLVER_FIX08 = 2e-7, two measured (not guessed) named
    constants
  - A synthetic regression proving a slack cone on a small-smax branch is now caught
  - A resolved ε conflict between the new floor and a pre-existing WR-01 regression test in
    test_exactness.jl (initially escalated, then resolved with a hybrid absolute+relative
    floor per user decision)
affects: [28-thesis-reproduction-restatement, any future FIX-08 follow-up if a fixture with a
  genuinely-exact excess above ~1.5e-7 or a tighter synthetic regression is added]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Backward-compatible kwarg override: atol::Union{Nothing,Real}=nothing bypasses a new
      default computation entirely when the caller passes an explicit value, preserving
      byte-identical behavior at 2 existing call sites"
    - "Measured-constant discipline: MEASURED_ε_FIX08/TAU_SOLVER_FIX08 mirror
      KNOWN_OPTIMUM_ATOL's cite-the-raw-sweep-numbers comment convention rather than a
      hand-picked value"
    - "Hybrid absolute+relative floor: atol_b = max(τ_solver, ε*ref_b) — an absolute
      solver-noise floor for lightly-loaded/interior branches, a relative per-branch floor
      for larger-scale branches, chosen when a PURE relative floor proved irreconcilable
      with two conflicting fixture requirements"

key-files:
  created:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md
  modified:
    - src/models/exactness.jl
    - test/test_exactness.jl

key-decisions:
  - "Initial approach (a PURE relative floor, MEASURED_ε_FIX08=1e-4) was escalated as
    irreconcilable: no single ε kept both the required canonical/cluster-E fixture set
    passing AND test_exactness.jl's pre-existing WR-01 regression item throwing (thresholds
    ~5e-5 vs <5e-8, three orders of magnitude apart)."
  - "User-directed resolution: HYBRID floor atol_b = max(τ_solver, ε*ref_b). τ_solver=2e-7
    (measured: ~2.53x the worst genuinely-exact 'excess' residual, 7.90e-8 on IEEE-123, found
    by isolating gap - rtol_term at each branch/hour — the part an absolute floor alone must
    cover). ε reset to 1e-9 (<5e-8, keeps the relative term meaningful for large-smax
    branches). All three required outcomes (WR-01 throws, synthetic regression throws,
    every canonical/cluster-E fixture passes >=2x) hold simultaneously — hybrid is feasible,
    the ε=1e-4-plus-rescope fallback was not needed."
  - "Chose a documented ~2.5x margin for τ_solver rather than KNOWN_OPTIMUM_ATOL's own 10x
    convention: 10x (7.9e-7) would itself exceed the Task-2 synthetic regression's injected
    gap (5e-7) and break the 'must still throw' requirement. The feasible window was
    [1.635e-7, 2.5e-7]; 2e-7 sits centered in it."

patterns-established:
  - "Per-branch exactness floor: ref_b = br.smax^2 for thermally-limited branches, else the
    head branch's own flow magnitude squared, for any future exactness-adjacent certificate
    that needs a scale-aware floor"
  - "Excess decomposition for absolute-floor measurement: excess[b,t] = gap[b,t] -
    rtol*max(|lhs|,|rhs|) isolates exactly what an absolute floor must cover, independent of
    any relative/ref_b term — negative excess means rtol alone already covers that point"

requirements-completed: [FIX-08]

# Metrics
duration: ~140min
completed: 2026-09-29
---

# Phase 27 Plan 02: Per-Branch Exactness Floor Summary

**`assert_socp_exact!` now gates on a HYBRID floor `atol_b = max(τ_solver, ε·ref_b)` (τ_solver=2e-7, ε=1e-9, both measured) instead of a flat `atol=1e-6` — closing the scale-blind gap on lightly-loaded branches while keeping a pre-existing WR-01 regression test throwing, after an initial pure-relative-floor approach was found irreconcilable and escalated, then resolved per user decision.**

## Performance

- **Duration:** ~140 min (includes the initial pure-relative-floor implementation, escalation,
  and the subsequent hybrid-floor measurement/implementation directed by the coordinator)
- **Started:** 2026-09-29T06:55:00Z (approx, worktree setup)
- **Completed:** 2026-09-29T09:15:00Z (approx)
- **Tasks:** 2 plan tasks completed, plus 1 coordinator-directed follow-up (hybrid floor)
- **Files modified:** 2 (`src/models/exactness.jl`, `test/test_exactness.jl`), 1 created (`27-FINDINGS.md`)

## Accomplishments

- `assert_socp_exact!` computes a per-branch, per-hour reference scale `ref_b` (the branch's
  own `smax^2` if thermally limited, else the head branch's own flow magnitude squared) and
  gates on the HYBRID floor `atol_b = max(τ_solver, ε * ref_b)` by default, replacing the flat
  `atol = 1e-6` that was calibrated only against head-branch-scale fixtures.
- An explicit `atol` kwarg still bypasses the hybrid computation entirely — verified
  byte-identical (same `maxgap`, no throw) on the existing exact-point fixture under both the
  new default path and the explicit-override path, and confirmed the 2 real call sites
  (`src/admm/DsoOpt.jl:671`, `test/fixtures_phase19.jl:359`) already pass an explicit `atol`
  and so take the unchanged bypass path.
- A new `@testitem` in `test/test_exactness.jl` demonstrates the regression this plan closes:
  a `smax=0.01` branch with an injected `l=5e-7` gap — below the OLD flat `atol=1e-6` (would
  have silently passed) — now correctly thrown by the hybrid default (2.5x margin).
- **First attempt (pure relative floor, `MEASURED_ε_FIX08=1e-4`) was measured, found to create
  an irreconcilable 3-order-of-magnitude conflict with a pre-existing WR-01 regression test,
  and ESCALATED** rather than silently resolved either direction (see "History" below).
- **Second attempt (HYBRID floor, coordinator-directed) was measured and found FEASIBLE**:
  `TAU_SOLVER_FIX08 = 2.0e-7` (an absolute Clarabel-noise-floor term, ~2.53x the worst measured
  genuinely-exact residual) combined with `MEASURED_ε_FIX08 = 1.0e-9` (a small relative term)
  satisfies all three required outcomes simultaneously with >=2.4x margin. The escalation in
  `27-FINDINGS.md` was updated from ESCALATED to RESOLVED with the full measured numbers.

## Task Commits

Each task/step was committed atomically:

1. **Task 1: Per-branch relative exactness floor in assert_socp_exact!** - `9374e5c` (feat)
2. **Task 2: Measure ε, add synthetic regression, re-verify cluster-E fixtures** - `9876322` (test)
3. **Plan metadata (initial escalation)** - `f7d334c` (docs)
4. **Coordinator-directed hybrid floor** - `5b72c74` (fix)
5. **Plan metadata (resolution)** - this commit (docs)

## Files Created/Modified

- `src/models/exactness.jl` - `assert_socp_exact!` HYBRID per-branch floor
  (`atol_b = max(τ_solver, ε*ref_b)`), `MEASURED_ε_FIX08` (1e-9) and `TAU_SOLVER_FIX08`
  (2e-7) constants with full measured-sweep comments (including the superseded pure-relative
  attempt's history), backward-compatible `atol` override, head-branch lookup with a loud
  `ArgumentError` on a malformed feeder.
- `test/test_exactness.jl` - new `@testitem` "per-branch floor flags a slack cone on a
  small-smax branch the old flat atol missed (FIX-08)". The 3 pre-existing items are
  byte-identical (untouched).
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md` -
  NEW file (didn't exist before this plan); documents the initial escalation (preserved for
  the record) and its RESOLUTION via the hybrid floor, with the full measured sweep.

## History: pure relative floor -> escalation -> hybrid resolution

**Attempt 1 (pure relative floor `atol_b = ε*ref_b`):** swept `ε` against the Task-2
synthetic regression and the plan's explicitly-named required fixture set (cluster-E +
IEEE-13/IEEE-123 canonical). Found `ε = 1e-4` satisfies all of those, but ALSO found that
`test/test_exactness.jl`'s PRE-EXISTING WR-01 item (a `smax=10` branch, injected `l=5e-6`
gap) needs `ε < 5e-8` to keep throwing — 3 orders of magnitude below the `ε ≳ 5e-5` the
IEEE-13 ground fixture needs to keep passing. **No single ε satisfies both.** Per the
locked "never raise/lower ε to hide a flip" policy, this was recorded as an ESCALATION in
`27-FINDINGS.md` rather than resolved silently in either direction, and surfaced prominently
in this plan's first completion report.

**Coordinator decision:** implement a HYBRID floor, `atol_b = max(τ_solver, ε·ref_b)`, with
`τ_solver` a separately-measured absolute Clarabel-noise floor and `ε` kept `< 5e-8`.

**Attempt 2 (hybrid, this plan's final state):** see "τ_solver / ε Measurement" below — found
FEASIBLE, implemented, verified.

## τ_solver / ε Measurement (hybrid, final)

**Stage 1 — measure `τ_solver`.** For every REQUIRED canonical/cluster-E fixture, computed
`excess[b,t] = gap[b,t] - rtol*max(|lhs|,|rhs|)` (the residual an absolute floor alone must
cover; negative excess means `rtol` alone already covers that point regardless of any
absolute floor):

| Fixture | Worst excess |
|---|---|
| IEEE-13 ground (branch 5→6, t=16) | ≈3.08e-8 |
| **IEEE-123 (branch 48→49, t=9)** | **≈7.90e-8 (worst REQUIRED excess, binding)** |
| two_bus_feeder | < 0 (every b,t — fully covered by `rtol`) |
| near-lossless smax=10 pair (dlmp/welfare) | < 0 (every b,t — real, non-trivial flow; `rtol_term≈1.76e-5 ≫ gap≈6.3e-6`) |

A strict 10x margin (matching `KNOWN_OPTIMUM_ATOL`'s own convention) would give
`τ_solver = 7.9e-7`, which is ITSELF larger than the Task-2 synthetic regression's injected
gap (`5e-7`) and would break the "must still throw" requirement — so a smaller, explicitly
documented margin was used: `τ_solver = 2.0e-7` (~2.53x the worst measured excess), the
largest value inside the numerically-narrow feasible window `[1.635e-7, 2.5e-7]` (lower bound
from a 2x pass-margin on IEEE-123; upper bound from a 2x throw-margin on the Task-2
synthetic regression).

**Stage 2 — verify all three required outcomes** at `τ_solver = 2.0e-7`, `ε = 1.0e-9`:

| Requirement | Result | Margin |
|---|---|---|
| (1) WR-01 pre-existing item (smax=10, l=5e-6) must THROW | **THROWS** | ≈24.9x |
| (2) Task-2 synthetic (smax=0.01, l=5e-7) must THROW | **THROWS** | ≈2.5x |
| (3) IEEE-13 ground must PASS ≥2x | **PASSES** | ≈6.47x |
| (3) IEEE-123 must PASS ≥2x | **PASSES** | ≈2.43x (tightest) |
| (3) two_bus_feeder must PASS ≥2x | **PASSES** | ≈145.8x |
| (3) near-lossless smax=10 pair (dlmp/welfare) must PASS ≥2x | **PASSES** | ≈2.81x |

All verified by DIRECT EXECUTION of `assert_socp_exact!` against each fixture's actual
reproduced solve (not just the arithmetic) — including running the literal `test_exactness.jl`
fixture bodies for both the WR-01 item and the new synthetic item.

## Decisions Made

- **Hybrid over a pure relative floor**, per the coordinator's explicit directive after
  reviewing the escalation, because a pure relative floor is architecturally unable to
  distinguish "this branch is small so its floor should be small" from "this branch's
  residual sits at the solver's own noise floor regardless of scale" — the absolute term
  `τ_solver` exists precisely for the latter.
- **~2.5x margin instead of a textbook 10x margin for `τ_solver`**: measured window
  `[1.635e-7, 2.5e-7]` is narrow; a 10x margin (`7.9e-7`) would have made the hybrid
  INFEASIBLE (it would itself exceed the Task-2 synthetic regression's gap). Chose `2e-7`,
  centered in the feasible window, and documented WHY 10x doesn't fit here (unlike
  `KNOWN_OPTIMUM_ATOL`'s own context, where 10x was feasible).
- Left `test/test_exactness.jl`'s 3 pre-existing `@testitem`s completely untouched throughout
  both attempts (only a NEW item was added) — never modified an existing item's fixture to
  "work around" a conflict.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed a `julia -e` top-level soft-scope bug in the plan's own Task 2 `<verify>` script**
- **Found during:** Task 2 verification
- **Issue:** The plan's literal verify script uses `threw = false; try ... catch e; threw = true; end`. Under `julia -e` (non-interactive top-level), Julia's soft-scope rule treats the `catch`-block assignment as a NEW local that dies with the block — the outer `threw` never updates, silently vacating the assertion (same failure class documented in this repo's `test/runtests.jl` header and the `testitem-try-scoping-trap` project memory, but here reproduced under plain `julia -e`, not TestItemRunner).
- **Fix:** Added `global threw = ...` in ad hoc verify scripts when running interactively via `-e` (not needed in the actual `test/test_exactness.jl` `@testitem`, which uses `@test_throws Exception` directly instead of a try/catch accumulator, avoiding the trap entirely).
- **Files modified:** none (only affected ad hoc verify invocations, not committed code).
- **Verification:** Re-ran with the `global` keyword; scripts now correctly report the exception was caught.
- **Committed in:** N/A (verify-script-only fix, not part of any commit).

---

**Total deviations:** 1 auto-fixed (1 blocking, verify-script-only, no source change)
**Impact on plan:** No impact on shipped code; the actual regression tests in
`test/test_exactness.jl` use `@test_throws Exception` directly and never hit this trap.

## Issues Encountered

An initial pure-relative-floor implementation was measured and found to create an
irreconcilable conflict (see "History" above) — escalated, then resolved via a coordinator-
directed hybrid floor. Fully resolved; no open issues remain from this plan's scope.

## Escalation — RESOLVED

The escalation raised mid-plan (a pure relative floor could not satisfy both the required
fixture set and a pre-existing WR-01 regression test) was reviewed by the user, who directed
the hybrid floor implemented in this plan's final state. Full detail, including the original
escalation text preserved verbatim, is in
`.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`
("Plan 27-02 — FIX-08 per-branch exactness floor: irreconcilable ε conflict (RESOLVED — hybrid floor)").
No open escalation remains for this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-08's hybrid per-branch floor is implemented, measured, verified against all three
  required outcomes, and the 2 backward-compat call sites are confirmed unaffected.
- `test/test_exactness.jl`'s pre-existing WR-01 item is confirmed throwing again
  (byte-identical fixture, re-verified by direct execution) — no suite-green blocker remains
  from this plan.
- **Caveat carried forward:** the tightest margins in this set (IEEE-123 pass-side ≈2.43x,
  Task-2 synthetic throw-side ≈2.5x) leave less headroom than a textbook 10x margin. IEEE-8500
  was NOT swept (not explicitly named in the plan's required fixture list; a much larger
  fixture). If a future plan touches IEEE-8500's exactness gating, or adds a tighter synthetic
  regression, re-measure `τ_solver`/`ε` rather than assuming this pair generalizes
  indefinitely.

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `src/models/exactness.jl`
- FOUND: `test/test_exactness.jl`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-02-SUMMARY.md`
- FOUND commit: `9374e5c`
- FOUND commit: `9876322`
- FOUND commit: `f7d334c`
- FOUND commit: `5b72c74`
