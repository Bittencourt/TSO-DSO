---
phase: 45-flexibility-market-vs-price-coordination
plan: 01
subsystem: settlement / coordination
tags: [julia, testitems, fnv-digest-fence, coordination-types, flex-market]

requires:
  - phase: 41-settlement
    provides: compare_tariffs, SettlementLedger, build_settlement_ledger, settlement_input
  - phase: 44-aggregator-as-actor
    provides: ActorFenceDigest testmodule (FNV-1a fold), default-path fence pattern
provides:
  - default-path fence over compare_tariffs (4 tables) and the default ledger, captured with src unchanged
  - FlexFenceFixtures testmodule (2-bus T=3 fixture, SUMMARY_COLUMNS, df_digest, ledger_digest) for later fence items
  - AbstractCoordination, PriceBased, FlexMarket (validated keywords), coordination_label, _flex_row_name
  - Coordination @autodocs block in docs/src/api.md (Pages list for later coordination files)
affects: [45-02, 45-03, 45-04, 45-05, 45-06, 45-07]

tech-stack:
  added: []
  patterns:
    - "Typed inner constructor validates every FlexMarket field; outer keyword constructor type-checks so bad kwarg types are ArgumentError, not MethodError"
    - "Column-wise DataFrame FNV digest that excludes the threads/blas_threads provenance columns"

key-files:
  created:
    - test/test_flex_market_fence.jl
    - test/test_flex_market.jl
    - src/coordination/coordination.jl
  modified:
    - test/expected_broken.txt
    - src/TSODSO.jl
    - test/test_exports.jl
    - docs/src/api.md

key-decisions:
  - "Fence fixtures live in a new @testmodule FlexFenceFixtures (in the fence file) so later plans can add fence items without duplicating the fixture; the fold is reused from ActorFenceDigest"
  - "FlexMarket stores beta = -0.0 as 0.0 so equal beta values give equal row names (keeps _flex_row_name injective)"
  - "Bool is rejected for n_blocks and baseline_inflation; non-Symbol tariff/rule values raise ArgumentError"

patterns-established:
  - "Fence goldens obtained by running the item once with placeholder zeros and reading the Evaluated tuple from the failure output"

requirements-completed: []  # SETL-07/08 span plans 01-07; marked complete by the final plan (Phase 44 convention)

duration: 18min
completed: 2026-11-04
---

# Phase 45 Plan 01: Default-path fence and coordination types Summary

**A 1.12.5-gated FNV-1a digest fence over the four default `compare_tariffs` tables and the default ledger, captured on an untouched src tree, plus the validated `AbstractCoordination` / `PriceBased` / `FlexMarket` hierarchy with an injective `_flex_row_name`, exported and documented.**

## Performance

- **Duration:** about 18 min
- **Started:** 2026-11-05T01:04:00Z (2026-11-04 22:04 -0300)
- **Completed:** 2026-11-05T01:21:00Z (2026-11-04 22:21 -0300)
- **Tasks:** 2/2 (plus the RED gate commit and the formatter style commit)
- **Files modified:** 7

## Accomplishments

- Captured the fence with `git diff --quiet -- src` passing, at HEAD `ea30313`, on Julia 1.12.5. `git diff --stat -- src | wc -l` returned 0 at capture.
- The fence holds 2 items: a version-independent schema and determinism item (13 assertions) and a 1.12.5-gated digest item (1 assertion). It ran green both before and after the first src edit, and its goldens have not changed since the capture commit.
- Added the coordination types with an `ArgumentError` for each invalid value. The row naming is injective over the 2 x 2 x 3 x 3 = 36-element keyword grid.
- The three exports are in the include chain (after `settlement/equity.jl`, before `settlement/comparison.jl`), in the `test_exports.jl` keep list, and in a `## Coordination` @autodocs block with `Order = [:type, :constant, :function]`.

## Fence record

- **HEAD at capture:** `ea30313` (src tree clean)
- **Julia:** 1.12.5
- **Golden digests** `(d_summary, d_bills, d_breakouts, d_rebound, d_ledger)`:
  `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`
- **Skip record added to test/expected_broken.txt (exact line):**

```
skipped | test_flex_market_fence.jl | flex market: default fence (digests) | (d_summary, d_bills, d_breakouts, d_rebound, d_ledger) == (0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8) | digest goldens valid only on Julia 1.12.5; version-gated
```

The formatter wrapped the gated tuple across several lines. A scratch parse of the wrapped `@test_skip` confirmed that `string(expr)` still matches the record's 4th field character for character.

## Measured tolerances

This plan has no tolerance-based comparison. Every assertion is exact: `==`, `isequal`, `===`, `ledger_residual == 0.0`, or digest equality. So the 3x-observed-max rule did not apply, and the tolerance table in the `test/test_flex_market.jl` header is empty, ready for later plans.

## Task Commits

1. **Task 1: Capture the default-path fence before any src edit:** `295b928` (test). src was unchanged at capture.
2. **Task 2 RED: failing tests for the coordination types and row naming:** `7676452` (test). It failed with `UndefVarError: FlexMarket`.
3. **Task 2 GREEN: types, row naming, include, exports, api.md block:** `31da05d` (feat)
4. **FMT style pass:** `0713ab3` (style). Whitespace and wrapping only; `check_content_loss.py HEAD` reported OK.

## Test results

- Fence only, src clean, pinned goldens: 17/17 pass (14 in the file + 3 runner guards), 0 fail, 0 error.
- `test_flex_market.jl`, `test_flex_market_fence.jl` and `test_exports.jl`: 55/55 pass, 0 fail, 0 error, both after GREEN and again after the formatter. 0 soft-scope warnings.
- Planning-ID guard: 355 (not above 355). `check_setup_names.py`: 27 testmodules, 0 unresolved.
- JuliaFormatter 2.10.2: the second `format` pass returned true, so the files are stable.

## Files Created/Modified

- `test/test_flex_market_fence.jl`: the `FlexFenceFixtures` testmodule and the two fence items
- `test/expected_broken.txt`: one version-gated skip record
- `src/coordination/coordination.jl`: `AbstractCoordination`, `PriceBased`, `FlexMarket`, `coordination_label`, `_flex_row_name`
- `src/TSODSO.jl`: the coordination include and the extended dependency comment
- `test/test_flex_market.jl`: the unit tests for the types and row naming, and the header for the tolerance table
- `test/test_exports.jl`: `AbstractCoordination PriceBased FlexMarket` added to the keep list
- `docs/src/api.md`: the `## Coordination` @autodocs section

## Decisions Made

- I defined the fixture in a new `@testmodule FlexFenceFixtures` inside the fence file instead of a local function in each item. Both fence items share it, and the later ledger fence item can reuse it. The digest fold is the existing `ActorFenceDigest.fold`, reused rather than copied.
- β is stored with `-0.0` normalised to `0.0`, which keeps the stored value and the row name consistent.
- SETL-07 and SETL-08 are not marked complete in REQUIREMENTS.md. This plan only lays the foundation for them; following the Phase 44 convention, the final plan of the phase marks them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Input validation] Type-checked keyword constructor**
- **Found during:** Task 2
- **Issue:** A typed keyword signature raises `MethodError` rather than `ArgumentError` for values such as `baseline_tariff = "flat"` or `n_blocks = 4.0`. `Bool` would also pass silently as an `Integer` or a `Real`.
- **Fix:** The keyword constructor checks the types and throws `ArgumentError`. The typed inner constructor checks the value ranges, so the positional path is guarded too. `-0.0` is normalised to `0.0`.
- **Files modified:** src/coordination/coordination.jl
- **Commit:** 31da05d

**2. Fixture placement:** the plan said to build the fixture "inside a local function". I placed that function in the shared `FlexFenceFixtures` testmodule instead. The behaviour is the same and there is no duplication.

Otherwise the plan executed as written.

## Issues Encountered

None.

## Known Stubs

None. The empty tolerance table in the `test/test_flex_market.jl` header is intentional; later plans fill it in.

## Next Phase Readiness

- The fence is the default-path contract for every later plan. Its goldens are never re-pinned.
- Later coordination source files append to the api.md `Pages = ["coordination/coordination.jl"]` list.

## Self-Check: PASSED

- FOUND: test/test_flex_market_fence.jl, test/test_flex_market.jl, src/coordination/coordination.jl
- FOUND commits: 295b928, 7676452, 31da05d, 0713ab3
