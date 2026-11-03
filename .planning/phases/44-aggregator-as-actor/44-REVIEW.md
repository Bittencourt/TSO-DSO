---
phase: 44-aggregator-as-actor
reviewed: 2026-11-02T00:00:00Z
depth: standard
iteration: 2
files_reviewed: 31
files_reviewed_list:
  - src/actors/Portfolio.jl
  - src/actors/actor_objective.jl
  - src/actors/efficiency.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/admm_phases.jl
  - src/admm/admm_state.jl
  - src/admm/solve_admm.jl
  - src/devices/Behavioural.jl
  - src/devices/CapabilityTraits.jl
  - src/experiments/materialize.jl
  - src/models/stochastic_welfare.jl
  - src/models/welfare_solve.jl
  - src/pricing/fit.jl
  - src/settlement/SettlementLedger.jl
  - src/settlement/run_inputs.jl
  - src/TSODSO.jl
  - scripts/actor_behaviour_sweep.jl
  - scripts/jet_baseline.txt
  - scripts/README.md
  - docs/literate/aggregator_actor.jl
  - docs/make.jl
  - results/actor_behaviour/actor_behaviour_sweep.csv
  - test/test_actor_default_fence.jl
  - test/test_actor_objective.jl
  - test/test_actor_portfolio.jl
  - test/test_actor_settlement.jl
  - test/test_actor_sweep.jl
  - test/test_behaviour.jl
  - test/test_exports.jl
  - test/expected_broken.txt
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: clean
---

# Phase 44: Code Review Report (Iteration 2)

**Reviewed:** 2026-11-02
**Depth:** standard
**Files Reviewed:** 31
**Status:** clean (no blockers, no warnings; 3 Info)

## Summary

I inspected each fix commit (32a6436, 6acba96, dd74dad, eb82e36, f7bada4, 7fc0cf8) by diff. WR-01 through WR-07 are resolved. I found no regressions. I did not run the test suite, as instructed. I checked these points.

- **Default-path byte-identity.** The only source edits are in `admm_phases.jl`, `solve_admm.jl` and `materialize.jl`.
  - WR-01 removes the `slot_tol` keyword and the only call site that passed it (`grep slot_tol` finds nothing left). The certificate is report-only and sits behind the `any(slot_bus[j] != j)` guard, so the default 1:1 path does not reach it.
  - WR-02 adds no key change for the first site at a bus. `_flex_mix` is variadic, and rank 0 takes the original 4-argument call. Every single-site-per-bus draw is therefore bit-identical.
  - No golden digest was touched.
- **WR-01.** The tolerance is now a named constant that is independent of `tol`. The docstring and the comment both say it compares against the primary slot's multiplier, not against `dual(balance_p)`. This is the docs-fix option from iteration 1. See IN-01 for the tolerance judgement.
- **WR-02.** The rank is the per-bus occurrence order, and the new testitem asserts that the first site is unchanged. It also asserts that the twin differs for at least one seed in 1:8. A different ordering of `aggregators` changes which twin gets rank > 0. That is acceptable because the order is deterministic input.
- **WR-03.** Digest gating and goldens are unchanged. The fence now also has a bitwise same-process comparison of default against all-welfare actor routing. The comparison uses fieldwise `==` for `AdmmResiduals`. See IN-02 for the limit of this check.
- **WR-04.** The README counts are now 20. The Group 4 comment names `has_4q_by_bus` and records the measurement method. No baseline entries were changed.
- **WR-05.** `COLS` and `ordered_columns` fix the column order. An unlisted column is an error, and an unused one is omitted. The committed CSV header follows `COLS` (`detail` is absent because no refusal row exists). `runtime_s` is documented as wall-clock in the script and on the page.
- **WR-06 and WR-07.**
  - The page now states the null result, the bitwise-repeat `xi = 0` rows, and the symmetric wedge with its negative actor profit.
  - It prints a live noise-floor line and a live m=1 to m=2 increment against the m=0 ADMM gap.
  - The "saturation" mechanism claim is removed.

## Info

### IN-01: Slot-lambda tolerance pinned at the 1e-12 numerical-zero floor, not 3x the measured 2.7e-15

**File:** `src/admm/admm_phases.jl:447-453`
**Issue:**
- The pin is about 370x the observed 2.7e-15 gap, not the 3x the measured-not-picked policy implies.
- I judge it acceptable, for three reasons.
  - It is not an arbitrary value: it is the repo's existing numerical-zero floor (`PortfolioFixtures.TOL_FLOOR`).
  - The measurement, the 3x value and the reason for choosing the floor are all written next to the constant.
  - The flag is report-only and never throws, so a looser floor cannot hide a failure.
- A literal 3x value of about 8e-15 would flip on other platforms or Julia versions, and nothing in the code would show why.
- The comment calls it "MEASURED, not picked", which slightly overstates it. The measurement informs the choice, but the constant is the floor.

**Fix:** Optionally reword the comment to "bounded by the measured 2.7e-15, pinned at the 1e-12 floor". Otherwise no change.

### IN-02: The new WR-03 fence compares two post-phase paths

**File:** `test/test_actor_default_fence.jl:162-194`
**Issue:**
- The version-independent assertions compare the default path with the all-welfare actor path. Both run through code changed in this phase.
- A regression in shared changed code, such as `solve_agr!` or the `DsoOpt` index selection, would move both sides equally and would not be caught.
- Only the 1.12.5 digest gate would catch it.
- This is a real limit but it is documented in the header. It strictly improves on iteration 1, and it is not a defect.

**Fix:** None required. Optionally capture per-version digests from the pre-phase commit if CI coverage of the headline guarantee is wanted.

### IN-03: Iteration-1 Info items carried forward, plus prose figures typed into the literate page

**File:** `.planning/phases/44-aggregator-as-actor/44-REVIEW.iter1.md` (IN-01 through IN-06); `docs/literate/aggregator_actor.jl` (Section 4 prose)
**Issue:**
- Iteration-1 IN-01 to IN-06 are unaddressed and remain valid Info items. They were out of fix scope.
  - Union-typed `linear_offset`.
  - Dead `actors` and `tol` parameters in the sweep script.
  - The `phi` vs `φ` comment in `Behavioural.jl`.
  - The spec deviation where `MethodError` stands in for the guard on MPC, stochastic and FIT entry points.
  - `_find_site` first-match on duplicate aggregator objects.
  - IN-04, the markup typo, was fixed incidentally in 7fc0cf8.
- New in iteration 2: the WR-06 prose hardcodes figures (3.4e-9, 7.9e-6, 8.9999) beside the live-computed lines.
  - They match the committed CSV today.
  - They would go stale if the sweep were re-run.

**Fix:** Address the iteration-1 items opportunistically. Optionally replace the typed prose figures with references to the printed live lines.

---

_Reviewed: 2026-11-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (iteration 2)_
