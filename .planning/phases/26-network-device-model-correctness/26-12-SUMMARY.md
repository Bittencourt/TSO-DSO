---
phase: 26-network-device-model-correctness
plan: 12
subsystem: admm
tags: [julia, jump, admm, reactive-power, dso-opt, dual-ascent, pm-03]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "FIX-05 flexible-load reactive draw in the centralized Aggregator (plans 26-04/07), is_flexible_load trait"
provides:
  - "ADMM's DSO-OPT subproblem defaults its reactive_consensus mode to LIVE whenever any aggregator carries a FourQuadBESS or an is_flexible_load member, matching the centralized model's post-FIX-05 reactive draw by default"
  - "WR-04 fail-loud guard widened to catch flexible-load members, not just FourQuadBESS, on an explicit OFF/CERTIFIED override"
affects: [26-08-golden-audit, 26-13, 26-14, 26-15, 26-16, 26-17, 26-18, 26-19, 26-20]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared unexported helper (_any_flexible_reactive) placed beside build_dso_opt and consumed by both build_dso_opt's and solve_admm's own keyword defaults, since Julia evaluates keyword defaults left-to-right against earlier positional parameters"

key-files:
  created: []
  modified:
    - src/admm/DsoOpt.jl
    - src/admm/solve_admm.jl
    - .planning/phases/26-network-device-model-correctness/deferred-items.md

key-decisions:
  - "reactive_consensus's smart default is applied IDENTICALLY in both build_dso_opt and solve_admm (not just build_dso_opt), because solve_admm always normalizes its own default to an explicit mode before calling build_dso_opt, which would otherwise bypass build_dso_opt's own smart default entirely"
  - "The WR-04 guard's probe is widened from `dv isa FourQuadBESS` to `dv isa FourQuadBESS || is_flexible_load(dv)` in both files' shared code path, so an explicit override still fails loud against a flexible-load population"
  - "Test-file convergence-budget re-tuning for test_admm.jl:121 and test_acceptance.jl:82 record 1 is logged to deferred-items.md (D-26-02) rather than done here — Task 2 explicitly forbids editing either test file, and the root cause is a convergence-budget gap, not a source defect"

requirements-completed: [FIX-05]

# Metrics
duration: 55min
completed: 2026-09-29
---

# Phase 26 Plan 12: ADMM reactive_consensus smart default for flexible loads (PM-03) Summary

**`build_dso_opt`/`solve_admm` now default `reactive_consensus` to `LIVE` whenever any aggregator carries a `FourQuadBESS` or an `is_flexible_load` member (Thermostatic/Deferrable/Interruptible), so ADMM's DSO-OPT subproblem matches the centralized `Aggregator`'s post-FIX-05 reactive draw without the caller needing to pass `reactive_consensus = :live` by hand; the WR-04 fail-loud guard now also catches an explicit override against a flexible-load population.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-28T23:50:00Z (approx, worktree reset + context gathering)
- **Completed:** 2026-09-29T00:45:22Z
- **Tasks:** 2 completed
- **Files modified:** 3 (2 source, 1 deferred-items log)

## Accomplishments
- `_any_flexible_reactive(aggregators)` helper added (shared, unexported, `TSODSO` module scope) that returns `true` iff any aggregator carries a `FourQuadBESS` or an `is_flexible_load` member.
- `build_dso_opt`'s `reactive_consensus` kwarg default changed from literal `false` to `_any_flexible_reactive(aggregators) ? LIVE : false`.
- `solve_admm`'s OWN `reactive_consensus` kwarg default changed identically — required because `solve_admm` always normalizes its default to an explicit mode BEFORE calling `build_dso_opt`, so fixing `build_dso_opt` alone would never fire for `solve_admm` callers.
- WR-04 fail-loud guard's probe widened from `dv isa FourQuadBESS` to `dv isa FourQuadBESS || is_flexible_load(dv)` — an explicit `reactive_consensus = :off`/`:certified` override against a flexible-load population still throws `ArgumentError`.
- Verified (direct scripts, not `@testmodule`/TestItemRunner per project convention):
  - A flexible-load-free population (PVBattery-only aggregator) is COMPLETELY unaffected — `dso.qag === nothing` (OFF), byte-identical to before this plan.
  - A flexible-load population (Thermostatic+Deferrable+PVBattery) with NO explicit `reactive_consensus` resolves to `LIVE` (`dso.qag !== nothing`) in `build_dso_opt`, and `solve_admm`'s own default also engages `LIVE` (`res.mu_q` present, `status = :converged`).
  - An explicit `reactive_consensus = :off` override on the flexible-load population still throws the widened WR-04 `ArgumentError`.
- Reproduced `test/test_admm.jl:121` and `test/test_acceptance.jl:82` record 1 as direct scripts (Task 2): both now correctly engage `LIVE` reactive coupling and converge to the PHYSICALLY CORRECT DADP (elementwise `4.2e-4` at a widened convergence budget), but both items' PRE-PM-03-tuned convergence budget (`ρ = 100`, `maxiter = 200`, default/pinned tolerances) is now too tight for the norm-based `isapprox(atol=1e-2, rtol=1e-3)` DADP-match assertion — logged as `D-26-02` in `deferred-items.md` per the plan's own instruction (no test file edited).

## Task Commits

Each task was committed atomically:

1. **Task 1: Make reactive_consensus default to LIVE when any aggregator carries a flexible-load or FourQuadBESS member, in both build_dso_opt and solve_admm** - `2860453` (fix)
2. **Task 2: Verify the ADMM/centralized cross-validation and IEEE-13 acceptance items now agree, with no test file edit** - `b6280ed` (docs — deferred-items log; no source change, per Task 2's own no-test-edit / no-scope-expansion instruction)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified
- `src/admm/DsoOpt.jl` - Added `_any_flexible_reactive` helper; `build_dso_opt`'s `reactive_consensus` default now context-sensitive; WR-04 guard probe widened to `is_flexible_load`; docstrings updated.
- `src/admm/solve_admm.jl` - `solve_admm`'s own `reactive_consensus` default now identical to `build_dso_opt`'s; docstrings (Reactive consensus section, Throws section) updated to describe PM-03.
- `.planning/phases/26-network-device-model-correctness/deferred-items.md` - Added `D-26-02`: convergence-budget gap for `test_admm.jl:121`/`test_acceptance.jl:82` record 1, root-caused and out-of-scope for this plan.

## Decisions Made
- Applied the smart default to BOTH `build_dso_opt` and `solve_admm` (not just `build_dso_opt` as a literal reading of the plan's `<files_modified>` list might suggest in isolation) — this was explicitly called out in the plan's `<interfaces>` section as required, since `solve_admm` always passes an already-normalized `mode` to `build_dso_opt`.
- Did not attempt to fix the D-26-02 convergence-budget gap by tuning internal ADMM hyperparameters (e.g. a different default `ρ_q` split) inside `src/admm/`, since that would be a behavioral/performance change affecting every `LIVE`-mode caller with unclear blast radius, and the actual fix the plan anticipated is a test-file numeric re-tune — explicitly out of scope for Task 2 ("no test file edit... permitted in this task").

## Deviations from Plan

### Auto-fixed Issues

None — Task 1 was implemented exactly as specified in `<action>`/`<interfaces>`.

### Verify-script substitutions (not deviations from source, but from the plan's literal `<verify>` text)

**1. `@testmodule`/TestItemRunner fixtures don't load under `--project=.`**
- **Found during:** Task 1 and Task 2 verification
- **Issue:** `test/fixtures_phase6.jl` and `test/fixtures_phase4.jl` are TestItems `@testmodule`s; `@testmodule` is not defined under `--project=.` (TestItems is a test-only dependency, confirmed per the project's `gsd-plan-verify-testitemrunner-trap` memory).
- **Fix:** Reproduced each fixture module as a plain `module ... end` in a scratch copy (`sed` substitution of the `@testmodule Foo begin` header line only — no change to the actual test files), then `include`d that plain-module copy to exercise the identical fixture-building code. No test file in the repository was modified for this.
- **Verification:** Confirmed the transformed module builds identical `Feeder`/`Aggregator` objects (same construction code, unmodified).

**2. Plan's exact Task 1 `<verify>` comment ("flexible-load-free 2-bus, expect OFF byte-identical") does not match the actual `Phase6Fixtures.build_two_bus_aggregators` fixture**
- **Found during:** Task 1 verification
- **Issue:** Running the plan's literal `<verify>` command against `Phase6Fixtures.build_two_bus_aggregators` resolves to `LIVE` (`dso.qag !== nothing`), not `OFF` — because that specific 2-bus fixture actually contains a `Thermostatic` + `Deferrable` device pair (both flexible-load), contrary to the plan's inline comment describing it as flexible-load-free.
- **Fix:** No source change needed — this is the CORRECT new behavior (this population genuinely has flexible loads, so `LIVE` is the right resolution). Additionally constructed a genuinely flexible-load-free population (PVBattery-only aggregator on the same feeder) to directly verify the "unaffected, still OFF" half of Task 1's acceptance criteria, which the plan's literal fixture could not demonstrate.
- **Files modified:** none (verification-only).
- **Verification:** See "Accomplishments" above — all three acceptance-criteria cases (flexible-load-free unaffected, flexible-load default→LIVE, explicit-override still throws) directly confirmed.

**3. Plan's exact Task 2 `<verify>` command references nonexistent fixture function names**
- **Found during:** Task 2 verification
- **Issue:** The plan's `<verify>` block calls `Phase4Fixtures.ieee13_ground_feeder()` and `Phase4Fixtures.ieee13_ground_aggregators(feeder)`, but the actual exported fixture API (matching `test/test_admm.jl:121`'s own testitem body) is `TSODSO.ieee13_modified()` (a top-level feeder builder, not part of `Phase4Fixtures`) and `Phase4Fixtures.build_ieee13_ground_aggregators(feeder)`.
- **Fix:** Used the correct function names, matching the actual `test_admm.jl:121` and `test_acceptance.jl:82` testitem bodies verbatim (read directly from the test files rather than trusting the plan's guessed names).
- **Files modified:** none (verification-only).
- **Verification:** Successfully reproduced both testitems' logic; see Task 2 findings and `D-26-02`.

---

**Total deviations:** 0 auto-fixed source changes; 1 deferred item logged (`D-26-02`, a test-parameter re-tune correctly out of this plan's scope per its own instructions); 3 verify-script corrections (fixture-loading mechanism, an incorrect plan comment about fixture composition, and incorrect fixture function names in the plan's literal `<verify>` text) — none affected the source fix itself.
**Impact on plan:** Task 1's fix is complete and independently verified against all three of its own acceptance criteria using corrected fixture calls. Task 2 fully reproduced both target testitems and correctly diagnosed a genuine but out-of-scope convergence-budget gap, which is logged rather than silently worked around.

## Issues Encountered
- A `try`/`catch` block at Julia top-level (`julia -e` script, not inside a `@testitem`) hit the documented soft-scope reassignment trap (`testitem-try-scoping-trap` memory) — a bare `catch e; threw = ...; end` created a new local that never reached the outer `threw` variable, printing a false negative. Fixed in the verification script by declaring `global threw` inside both the `try` and `catch` blocks; this was a verification-script-only issue, not a source or test-file bug.
- `test/test_admm.jl:121` and `test/test_acceptance.jl:82` record 1: see `D-26-02` in "Deviations" above — root-caused as a convergence-budget gap, not a code defect, and logged to `deferred-items.md` per the plan's explicit instruction rather than silently fixed by editing an out-of-scope test file.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Task 1's source fix (`_any_flexible_reactive`, smart `reactive_consensus` default, widened WR-04 guard) is complete, independently verified, and committed — ready for the phase's wave-merge and full-suite validation.
- `D-26-02` (convergence-budget re-tune for `test_admm.jl:121`/`test_acceptance.jl:82` record 1) needs to be picked up by whichever plan/step re-tunes test-file numeric constants before Phase 26's SC-6 "full suite green at close" gate — it will surface as a failing/erroring `@testitem` in the phase's full `Pkg.test()` run.
- `test_acceptance.jl:82` record 2 (the `v9_16`/DADP16 golden re-pin) remains a SEPARATE, already-tracked concern per PM-06/26-08 — this plan did not touch it and confirms record 1 is independently diagnosable from record 2.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `src/admm/DsoOpt.jl`
- FOUND: `src/admm/solve_admm.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-12-SUMMARY.md`
- FOUND: commit `2860453` (Task 1)
- FOUND: commit `b6280ed` (Task 2)
