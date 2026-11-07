---
phase: 47-v5-audit-gap-closure
plan: 01
subsystem: settlement
tags: [certificates, ev, v2g, price-taker, flex-market, honesty-policy, julia]

requires:
  - phase: 43
    provides: assert_ev_complementarity!, TAU_EV_ADMM, the storage_kind trait and the type-paired stash (_stash_entry_has_kind)
  - phase: 45
    provides: price_taker_dispatch report semantics, _deliver, _dispatch_record, clear_flex_market physics record
provides:
  - _certificate_status and _storage_certificates (internal, src/settlement/price_taker.jl), the one shared trait-routed certificate report
  - price_taker_dispatch returns ev_certificate / ev_message (additive; keyword τ_ev = TAU_EV_ADMM)
  - _deliver returns ev_certificate / ev_message before shortfall (keyword τ_ev = TAU_EV_ADMM)
  - physics.baseline and physics.delivered carry ev_certificate, ev_message, n_ev_ok, n_ev_refused, n_ev_not_checked
affects: [47-02 guards, 47-03 closure docs, compare_tariffs (reads battery_certificate only, unchanged), any reader of the flex physics record]

tech-stack:
  added: []
  patterns:
    - "Certificate presence decided by the storage_kind trait over the type-paired stash, never by variable shape"
    - "A certificate that did not run is :not_checked; one shared helper feeds every price-taker-shaped solve"

key-files:
  created: []
  modified:
    - src/settlement/price_taker.jl
    - src/coordination/flex_clear.jl
    - test/test_settlement.jl
    - test/test_flex_market.jl

key-decisions:
  - "The EV certificate on price-taker and stage-2 delivery solves runs at TAU_EV_ADMM, referenced by name: these paths take τ_batt = 1e-3 from the ADMM final consolidation, which pairs it with TAU_EV_ADMM"
  - "τ_ev is a keyword on price_taker_dispatch and _deliver only; it is not threaded through clear_flex_market, compare_tariffs or _flex_physics (the default applies on those paths)"
  - "The _deliver key-set pin was extended additively (a schema check, not a golden re-pin); the two-line statement is the only existing test line removed"
  - "Delivery at a negative price with a zero target is :ok, not :refused (measured ratio 4.2e-15); the plan fallback asserts in (:ok, :refused) there and τ is unchanged"

patterns-established:
  - "Storage certificate reports go through _storage_certificates; new device classes add a presence predicate and a _certificate_status call there"

requirements-completed: [DEV-07, SETL-07]

duration: 50min
completed: 2026-11-06
---

# Phase 47 Plan 01: Honest storage certificates on price-taker and flex paths Summary

**Battery and V2G-EV certificates on `price_taker_dispatch` and the flex delivery now run through one trait-routed helper. The EV co-charge certificate runs at `TAU_EV_ADMM` and is recorded as its own `ev_certificate` status in the flex physics records. A V2G EV no longer yields a false battery `:ok`.**

## Performance

- **Duration:** about 50 min
- **Tasks:** 3 (2 fix commits, 1 style commit; Task 3 is gates only)
- **Files modified:** 4

## Accomplishments

- **Audit item B1 closed.** Battery presence is now decided by `_stash_entry_has_kind(..., :battery, legacy_shape)`, the same selection `assert_battery_complementarity!` uses. So an EV-only population reports battery `:not_checked`, not `:ok`.
- **V2G EVs get the EV co-charge certificate.** `assert_ev_complementarity!` runs at `TAU_EV_ADMM` and is recorded as `ev_certificate` / `ev_message` (`:not_checked | :ok | :refused`). V1G-only and EV-free populations report `:not_checked`.
- **One shared helper.** `_storage_certificates` is called from both `price_taker_dispatch` and `_deliver`, so the two report sites cannot diverge. No shape predicate is left in `flex_clear.jl`.
- **Flex physics records.** `_dispatch_record` appends `ev_certificate`, `ev_message`, `n_ev_ok`, `n_ev_refused` and `n_ev_not_checked`, so they appear in `physics.baseline` and `physics.delivered`. The top-level `physics` keys are unchanged.
- **No output changes.** No CSV column, digest, golden, tolerance or committed results file changed.

## Task Commits

1. **Task 1: shared trait-routed certificate helper and the price-taker EV status:** `2d757ed` (fix)
2. **Task 2: delivery and flex-market physics records carry the EV status:** `e934b11` (fix)
3. **Task 3: style pass, fences and gates:** `4e0497d` (style). The formatter rewrapped only long test lines in the two test files; the content-loss check reported OK.

TDD: each fix commit contains its tests. RED was observed before implementation in both tasks:
- Task 1: Test A saw battery `:ok` and no `ev_*` fields.
- Task 2: Tests H and I saw no `ev_*` fields, and delivery reported battery `:ok`.

## Measured Outcomes

| Check | Measured |
|---|---|
| Test A: price-taker, V2G EV at price −50 | battery `:not_checked`, EV `:refused` (message contains "EV complementarity") |
| Test C: price-taker, compliant V2G at swing | EV `:ok` (pinned; no fallback needed) |
| Test F: wrapped V2G (`PartialCompliance`) at −50 | routed to the EV certificate (`in (:ok, :refused)` holds), battery `:not_checked` |
| Test I: `_deliver` V2G at −50, target zeros(24), weight 500 | EV **`:ok`**; raw ratio **4.23e-15** (max abs(pag) 2.2e-14). See the deviation below. |
| Test J: negative-price clear, status | `"inexact_redispatch"` (not pinned); `physics.baseline.ev_certificate == [:refused]`, battery `[:not_checked]` |
| Test K: compliant clear (Interruptible + V2G test EV, swing) | status **`"ok"`**; baseline EV `[:ok]`; `physics.delivered` present and its EV fields are consistent |

## Test Counts (fast set, targeted)

| Batch | Files | Result |
|---|---|---|
| Task 1 GREEN | test_settlement.jl | 326/326 pass |
| Task 2 GREEN | test_flex_market.jl | 1362/1362 pass |
| Fence batch 1 | test_settlement.jl, test_electricvehicle.jl, test_admm_knifeedge_canary.jl | 593/593 pass; canary at 56 iterations / −4823.66604824162 |
| Fence batch 2 | test_flex_market.jl, test_flex_market_fence.jl | 1445/1445 pass; fence digests equal their pins |

The plan noted 86/86 for the fence file at baseline. This batch adds 83 tests on top of the 1362 flex-market tests. Every digest assertion passed; the count was not reconciled further.

## Gates

| Gate | Result |
|---|---|
| Planning IDs | 354 hits, 0 stale; at most 355 allowed. One hit fewer: the "review WR-03" comment was removed. |
| Scripts index | complete (48 files) |
| JET | 20 current, 20 baseline, 0 new, 0 fixed |
| SC3 (`git diff 9e9b709` over src/admm, exactness.jl, factory.jl, expected_broken.txt) | empty |
| `git diff 9e9b709 -- src/admm src/models` | empty |
| τ gate (`τ_batt::Real = 1e-3` counts per file vs 9e9b709) | unchanged |
| `price_taker.jl` | no `TAU_EV` bare name, no `3.6e-3`, no `2e-7` |
| Golden pins | fence file only gained lines; canary and actor-fence files unchanged; 2 removed lines in test_flex_market.jl (the pin statement) |
| results/ | untouched |
| Formatter | no-op after the style commit |
| Content-loss check | OK |
| Exports | `src/TSODSO.jl` and `test/test_exports.jl` untouched |

## Deliberate Schema Change (not a golden re-pin)

The `_deliver` key-set assertion in `test/test_flex_market.jl` was extended additively. The two-line `@test keys(c.d1) == (...)` became `(:net, :utility, :battery_certificate, :battery_message, :ev_certificate, :ev_message, :shortfall)`. The `@test c.d1.ev_certificate === :not_checked` line was added beside it. These two lines are the only existing lines removed from the file (gate bound 2).

## Deviations from Plan

### Measured outcome differed (plan fallback applied)

**1. Test I: delivery of the negative-price V2G EV reports `:ok`, not `:refused`**
- **Found during:** Task 2 (GREEN run)
- **Measured:** The scratch measurement recipe used the `_deliver` body with weight 500.0 and target zeros(24). It gave `assert_ev_complementarity!(...; τ = TAU_EV_ADMM, report = true)` = **4.23e-15**, with max abs(pag) = 2.2e-14 and max p_ch·p_dch = 3.8e-16.
- **Why:** The L1 tracking penalty holds the net injection at the zero target. With η < 1, an SOC-neutral round trip needs a net import of (1 − η²)·p_ch, which the weight-500 penalty prices out. So co-charge is no longer optimal and `:ok` is the honest result.
- **Fix:** Following the plan fallback, the test asserts `d.ev_certificate in (:ok, :refused)`, with the message consistent with the status. The status is logged with `@info`, and a comment in the test gives the measured ratio.
  - τ was not changed.
  - The flex path still pins `:refused` non-vacuously: Test J asserts `physics.baseline.ev_certificate == [:refused]` on the negative-price clear.
- **Files modified:** test/test_flex_market.jl
- **Commit:** `e934b11`

### Other adjustments

- **Comment wording in `price_taker.jl`.** The plan asked the reuse comment to name the centralized `TAU_EV`. But the Task 1 verify grep forbids `TAU_EV` followed by a non-identifier character. The comment therefore says "the centralized EV default tolerance (the certificate's own keyword default)", which means the same thing.
- **Commit structure.** Each task's tests were committed with its implementation in the single `fix(47)` commit the plan names, not as a separate `test(...)` commit. RED was still run and observed first in both tasks.

## Known Stubs

None.

## Threat Flags

None. No new endpoints, file access or trust-boundary surface. The new fields are additive and do not reach any CSV writer.

## Self-Check: PASSED

- FOUND: src/settlement/price_taker.jl (`_storage_certificates`, `_certificate_status`)
- FOUND: src/coordination/flex_clear.jl (`_storage_certificates(ctx`, `n_ev_not_checked`)
- FOUND: test/test_settlement.jl (`ev_certificate`)
- FOUND: test/test_flex_market.jl (`:ev_certificate`)
- FOUND: commits 2d757ed, e934b11, 4e0497d
