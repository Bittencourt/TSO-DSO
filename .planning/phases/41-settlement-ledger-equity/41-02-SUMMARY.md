---
phase: 41-settlement-ledger-equity
plan: 02
subsystem: settlement
tags: [equity, gini, theil, atkinson, palma, rebound, inequality-metrics, negative-values, known-value-tests, julia]

# Dependency graph
requires:
  - phase: 41-settlement-ledger-equity (plan 01)
    provides: the src/settlement/ module skeleton + TSODSO.jl settlement include block (equity.jl appended as its last line)
  - phase: 40-784-house-thesis-population
    provides: case_a_household_map row shape (house/bus/aggregator/device_set/pv_group/house_index) — the ONLY grouping source for the SETL-05 breakouts
  - phase: 41 RESEARCH Pattern 5
    provides: the normative per-metric negative-value conventions table (literature-cited) that the docstrings carry verbatim-per-metric
provides:
  - src/settlement/equity.jl — gini/theil/atkinson/palma with documented negative-value conventions, load_terciles, equity_breakdown (7-field per-group metric set), rebound (single number + per-hour detail), all pure-math zero-solver
  - test/test_equity.jl — 14 @testitems: uniform exact anchor (0,0,0,0.25), hand-computed negative Gini 0.8125, exclusion reporting, Palma -3.0/1.0 anchors, tercile count pins, breakdown equivalence, rebound exact certificates, guard non-vacuity
  - 7 new exports on the TSODSO public surface (export-guard keep set updated to 17 items in the settlement block)
affects: [tariff comparison (41-03), comparison CSV + literate writeup (41-04 — the no-income-data statement is restated there), equity_breakouts.csv artifact]

# Tech tracking
tech-stack:
  added: [] # zero new packages (RESEARCH Package Legitimacy Audit: empty by construction)
  patterns:
    - "Known-value certificates per new mathematical regime (v3.0 standing bar): hand-computed exact anchors incl. a negative-bearing Gini (0.8125 = 52/(2·4²·2)) pinned as ==, never recomputed via the implementation's own formula path"
    - "One negative-value convention PER METRIC, carried verbatim in its docstring: Gini over ALL values (may exceed 1; never zeroed/dropped), Theil/Atkinson positive-support subset with n_excluded RETURNED, Palma group-total ratio over the sorted full vector"
    - "Honesty policy in the metric layer: exclusions/undefined ratios are returned values (n_excluded fields, NaN ratios compared via isnan) — never silent drops, fake zeros, or throws"
    - "Exactness short-circuit where IEEE round-trips would break a pinned anchor: atkinson uniform => 0.0 exactly (raw formula leaves ~1 ulp)"
    - "Non-build_ names for all pure-metric functions (gini/theil/...), keeping the test_planning_noninteger operational-builders tripwire inapplicable"

key-files:
  created:
    - src/settlement/equity.jl
    - test/test_equity.jl
  modified:
    - src/TSODSO.jl
    - test/test_exports.jl

key-decisions:
  - "Atkinson returns uniform vectors as EXACTLY 0.0 via a documented all-equal short-circuit — the raw power-mean formula leaves a ~1-ulp IEEE artifact (measured 2.2220446049250313e-16 at mu=7, n=10) that would break the pinned (0,0,0,0.25) exact anchor; Theil needs no such case (log(1)=0.0 exact), Gini/Palma exact by construction"
  - "Exclusion counts are returned NamedTuple fields (n_excluded) asserted in tests; all-excluded => NaN never a throw or fake 0; rebound: NaN ratio on no-reduction input but DEFINED 0.0 when reductions exist without later increases"
  - "epsilon = 1 (the log Atkinson form) rejected with an explicit unimplemented ArgumentError; valid epsilons in (0,1) ∪ (1,∞); _ATKINSON_EPSILON = 0.5 module constant (A6) and the used value travels in the result"
  - "Rebound increase-hours count only strictly AFTER the first reduction hour; NET-LOAD input definition documented (grid consumption = negated net injection) so battery- and deferrable-driven shifts share one definition"

patterns-established:
  - "Equity metric seam: pure functions in src/settlement/equity.jl, each docstring carrying its negative-value convention + the module-level no-income-data stance (SETL-05 statement lives in code AND in the 41-04 writeup)"
  - "Known-value test style for the metric layer: pinned == anchors with hand-arithmetic comments, inline independent recomputations at rtol 1e-12, isnan for undefined quantities"

requirements-completed: [SETL-04, SETL-05, SETL-06]

# Metrics
duration: 27min
completed: 2026-10-25
---

# Phase 41 Plan 02: Equity & Rebound Layer Summary

**Gini/Theil/Atkinson/Palma over negative-bearing bill/surplus vectors with per-metric documented conventions, PV/bus/load-tercile breakouts from household-map rows, and a snapback rebound metric — all certified by hand-computed known-value anchors incl. the exact negative-value Gini 0.8125 and uniform (0, 0, 0, 0.25).**

## Performance

- **Duration:** 27 min
- **Started:** 2026-10-25T17:46:19Z
- **Completed:** 2026-10-25T18:13:30Z
- **Tasks:** 3 (each TDD: failing-test commit → implementation commit)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- SETL-04: the four inequality metrics with literature-grounded negative-value conventions living in OUR docstrings (Gini over ALL values — never zeroed/dropped per the Raffinetti/De Battisti bias finding; Theil/Atkinson positive-support subset with the excluded count a RETURNED value; Palma group-total ratio, most negative-robust)
- SETL-05 (computational): `load_terciles` (floor/floor/remainder-to-middle, stable ascending sortperm) + `equity_breakdown` over any household-shaped group vector (pv_group, bus, tercile) returning all seven fields per group; no-income-data stance at module level and in both docstrings
- SETL-06 (computational): `rebound` returning the single number plus full per-hour detail (delta vector + reduction/increase hour classifications); increases count only after the first reduction hour; NaN ratio convention on no-reduction input
- Full TDD gate compliance: three RED commits (failing tests first, verified failing) each followed by a GREEN implementation commit

## Task Commits

Each task was committed atomically (TDD: test commit → feat commit):

1. **Task 1: four metrics with documented negative-value conventions** — `6121e7c` (test, RED) → `9e8ff49` (feat, GREEN)
2. **Task 2: breakouts + load terciles** — `f5b36a7` (test, RED) → `b5d4208` (feat, GREEN)
3. **Task 3: rebound metric** — `f05c76a` (test, RED) → `37b0e6e` (feat, GREEN)

**Plan metadata:** (this commit) (docs: complete plan)

_Note: TDD plans carry paired test/feat commits; no REFACTOR commits were needed (formatter idempotent, no cleanup beyond the initial write)._

## Files Created/Modified

- `src/settlement/equity.jl` (created, 353 lines) — SEAM header, module-level no-income-data stance, `_ATKINSON_EPSILON = 0.5` (A6), shared fail-loud input guard, gini/theil/atkinson/palma/load_terciles/equity_breakdown/rebound with convention docstrings
- `test/test_equity.jl` (created, 333 lines) — 14 `@testitem`s tagged `[:equity]`: the Task-1 known-value certificates (uniform anchor, hand-computed negative Gini, exclusion reporting, Palma -3.0 sign caveat + n=10 1.0 anchor, all-non-positive NaN, guards), Task-2 tercile/breakdown certificates, Task-3 rebound certificates
- `src/TSODSO.jl` (modified) — `include("settlement/equity.jl")` appended as the LAST line of the settlement block (dependency order types → adapters → equity)
- `test/test_exports.jl` (modified) — keep set extended with the 7 new exports

## Decisions Made

- **Atkinson exact-zero short-circuit:** measured before implementing — the raw power-mean formula on a uniform vector returns 2.2220446049250313e-16 (~1 ulp), so the pinned EXACT uniform anchor is unachievable without a documented all-equal convention (mirrors gini's). Implemented, docstring-carried, and the measurement is recorded here as provenance.
- **epsilon = 1 rejection:** the log form of Atkinson is a different formula — rejected with an explicit "unimplemented" ArgumentError rather than silently switching formulas.
- **Rebound ratio semantics:** no-reduction input ⇒ NaN (undefined, isnan-compared); reductions-without-later-increases ⇒ defined 0.0 — kept distinct and pinned by separate tests.
- **Small-n count conventions** (Palma `max(1, floor(0.1n))/max(1, floor(0.4n))`, tercile remainder-to-middle) implemented exactly as plan-pinned; consequences at n = 1 (Palma top/bottom overlap) accepted as documented convention, not special-cased.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Atkinson uniform-exactness short-circuit**
- **Found during:** Task 1 (pre-implementation measurement)
- **Issue:** the plan's pinned uniform anchor demands `atkinson == 0.0` EXACTLY, but the raw formula's IEEE round-trip through the power mean leaves ~1 ulp (measured 2.2220446049250313e-16)
- **Fix:** documented all-equal-subset short-circuit returning exactly 0.0 (the uniform distribution has zero inequality by definition), mirroring gini's all-equal convention
- **Files modified:** src/settlement/equity.jl
- **Verification:** uniform-anchor testitem asserts `atkinson(u) == 0.0` at n = 10 — green
- **Committed in:** 9e8ff49 (Task 1 GREEN)

**2. [Rule 1 - Bug] Test-side `values` shadowing in the household-map item**
- **Found during:** Task 2 (GREEN run)
- **Issue:** the test's local `values` vector shadowed `Base.values(::Dict)`, so `values(by_pv)` raised MethodError (Vector not callable) — the RED-phase test draft was defective, not the implementation
- **Fix:** non-emptiness assertions rewritten key-wise (`all(g -> by_pv[g].n >= 1, keys(by_pv))`)
- **Files modified:** test/test_equity.jl
- **Verification:** item green; full test_equity 90/90 at the time, 114/114 after Task 3
- **Committed in:** b5d4208 (Task 2 GREEN)

---

**Total deviations:** 2 auto-fixed (1 missing-critical, 1 test-side bug)
**Impact on plan:** both fixes were necessary to meet the pinned exact anchors and gate discipline; no scope creep — all four `files_modified` match the plan frontmatter.

## Issues Encountered

None beyond the two deviations above. The `gsd-sdk roadmap.update-plan-progress 41 41-02 complete` handler reported but did not write ROADMAP.md — updated manually (plan checkbox + progress row 2/4), matching the 41-01 convention.

## Verification (plan-level, all run)

- `TSODSO_TEST_FILES=test_equity.jl julia --project=. -e 'import Pkg; Pkg.test()'` — **114/114 pass**
- `TSODSO_TEST_FILES=test_exports.jl ...` — **17/17 pass** (keep set includes all 7 new exports)
- `git diff --exit-code src/pricing/ src/admm/ src/settlement/SettlementLedger.jl src/settlement/run_inputs.jl` — **clean** (golden + adjacent settlement files untouched)
- `grep -c "Clarabel\|Ipopt\|HiGHS" src/settlement/equity.jl` — **0** (zero solver references)
- JuliaFormatter run on both files, second pass idempotent; docstring content intact (7 convention-statement markers)
- Structural threat mitigations: `filter(>(0), x)` present only inside theil/atkinson (the documented convention) — never feeding gini (T-41-06); exclusions returned+asserted (T-41-07); ArgumentError guards everywhere (T-41-08); NaN-not-throw on undefined ratios (T-41-09); zero new packages (T-41-SC)

## Threat Surface Scan

No new surface beyond the plan's threat model: pure in-process functions on caller-supplied numeric vectors — no network endpoints, no file access, no auth paths, no schema changes.

## Known Stubs

None — every exported function is fully implemented and certified.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 41-03 (tariff construction & counterfactuals): the equity seam is additive and self-contained; 41-03 touches tariffs.jl/price_taker.jl/feasibility.jl in the same settlement block
- 41-04 will consume `equity_breakdown`/`load_terciles` for the equity_breakouts.csv artifact and restate the no-income-data statement in the literate page
- Note for 41-04: `rebound` expects NET-LOAD profiles (grid consumption = negated net injection) — the comparison harness must convert from `agr_dispatch` before calling

## Self-Check: PASSED

- `[ -f src/settlement/equity.jl ]` — FOUND (353 lines ≥ min 150)
- `[ -f test/test_equity.jl ]` — FOUND (333 lines ≥ min 120)
- `git log` contains all six task commits: `6121e7c`, `9e8ff49`, `f5b36a7`, `b5d4208`, `f05c76a`, `37b0e6e` — FOUND
- test_equity 114/114, test_exports 17/17, scope diff clean, solver-name grep 0 — re-verified post-Task-3
- TDD gate compliance: `test(41-02)` commit precedes each `feat(41-02)` commit in git history — VERIFIED

---
*Phase: 41-settlement-ledger-equity*
*Completed: 2026-10-25*
