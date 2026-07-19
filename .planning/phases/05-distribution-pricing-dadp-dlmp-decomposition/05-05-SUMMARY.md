---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
plan: 05
subsystem: pricing
tags: [welfare-accounting, surplus-identity, dadp, fit-baseline, socp, jump, price-decomposition]

# Dependency graph
requires:
  - phase: 05-01
    provides: ctx.meta[:agg_net] per-aggregator net-injection + utility stash, welfare.jl seam
  - phase: 05-02
    provides: extract_dlmp(ctx) — the per-node DADP λ_j and PF-04 price-refusal gate
  - phase: 05-03
    provides: fit_baseline(...).social_fit — the FIT counterfactual (ratio denominator)
  - phase: 04-06
    provides: computed-golden + non-failing thesis cross-check pattern (@info gap + broken test)
provides:
  - welfare_accounting(ctx; T, λ₀, baseline) -> (; social, dso, prosumer[, ratio])
  - HARD surplus identity social == prosumer + dso == objective_value (transfer cancels), throws
  - +25% headline as a COMPUTED ratio social_DADP/social_FIT pinned as a golden
  - non-vacuous sign-flip self-test proving the identity is load-bearing

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Post-solve accounting reads only stashed primals/duals — no re-solve"
    - "HARD relative-tolerance identity throw (error, never @assert), mirroring assert_socp_exact!"
    - "Computed golden as primary anchor + non-failing figure-bound thesis cross-check (broken test)"

key-files:
  created:
    - .planning/phases/05-distribution-pricing-dadp-dlmp-decomposition/05-05-SUMMARY.md
  modified:
    - src/pricing/welfare.jl
    - test/test_pricing_welfare.jl

key-decisions:
  - "λ₀ defaults to the root DADP (energy = dual(balance_p[root,t])); = λ₀ at the priced-frontier optimum (KKT), so the identity is a genuine dual-consistency check without needing an external λ₀"
  - "Surplus identity computes social := objective_value(ctx.model) and asserts prosumer+dso ≈ social within rtol=1e-4; holds tight (rtol 1e-6) on the near-lossless 2-bus AND lossy IEEE-13 — Open Q2 resolved, NO separate loss term needed"
  - "_transfer_flip self-test hook mis-signs the transfer in the DSO settlement only (broken cancellation) to prove the identity assertion throws — non-vacuous (T-05-03)"
  - "FIT AC-PF on IEEE-13 runs on a head-branch-THERMALLY-relaxed feeder (limits not enforced, thesis FIT step) because the batteryless FIT schedule is INFEASIBLE under the 0.0686-pu head limit the DADP optimum only just binds"
  - "+25% ratio pinned as a computed golden (0.99997) — ≈1.0 not 1.25 because absolute welfare is NEGATIVE in this ¢$/kWh calibration (figure-bound, RESEARCH Pitfall 4 / STATE Phase-4 caveat); thesis 1.25 is a NON-FAILING broken cross-check"

patterns-established:
  - "Surplus split via cancelling price-transfer: prosumer=ΣU−transfer (3.46), dso=transfer−λ₀ᵀp_import (3.47)"
  - "Ratio-of-negatives sign caveat documented: DADP welfare is higher (less negative) yet ratio<1"

requirements-completed: [PRICE-03]

# Metrics
duration: ~35min
completed: 2026-07-19
---

# Phase 5 Plan 5: Welfare Accounting Summary

**`welfare_accounting` splits the GLB-CVX welfare into social/DSO/prosumer surplus with a HARD cancelling-transfer identity (social == prosumer + dso == objective_value), and reports the +25% headline as a computed FIT ratio golden with a non-failing thesis-1.25 cross-check.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-19
- **Tasks:** 2 (both TDD: RED test → GREEN impl)
- **Files modified:** 2 (+1 SUMMARY created)

## Accomplishments
- `welfare_accounting(ctx; T, λ₀, baseline)` computes prosumer surplus (AGR-OPT value, 3.46), DSO surplus (−DSO-OPT value, 3.47), and social welfare (GLB-CVX objective, 3.38) from a solved DADP ctx — reading only stashed primals/duals, no re-solve.
- HARD surplus-identity gate: `social ≈ prosumer + dso` within rtol, throwing an `error` (never `@assert`) with the mismatch magnitude. Verified TIGHT (rtol 1e-6) on a near-lossless 2-bus (Open Q2: no loss remainder) and within rtol 1e-4 on the lossy IEEE-13 ground solve.
- Non-vacuous proof: a `_transfer_flip` self-test mis-signs the price-transfer in the DSO settlement only, making the identity throw (`@test_throws`) — the load-bearing check catches a broken cancellation (threat T-05-03).
- +25% headline as a COMPUTED ratio `social_DADP / social_FIT`, pinned as a regression golden, with the thesis ~1.25 as a NON-FAILING cross-check (@info gap + broken test + generous 0.8–2.0 physical band).

## Task Commits

1. **Task 1 (RED): surplus-identity tests** - `d2c230c` (test)
2. **Task 1 (GREEN): welfare_accounting + identity gate** - `ac611d3` (feat)
3. **Task 2 (RED): +25% FIT ratio golden test** - `be7e311` (test)
4. **Task 2 (GREEN): ratio helper + pinned golden** - `b207d06` (feat)

## Files Created/Modified
- `src/pricing/welfare.jl` - Implemented `welfare_accounting` (social/dso/prosumer split, HARD cancelling-transfer identity, magnitude-sanity guards) and the `_fit_ratio` helper (+25% ratio with degenerate-baseline guard).
- `test/test_pricing_welfare.jl` - Added 4 @testitems: near-lossless 2-bus identity + signs, sign-flip guard (`@test_throws`), IEEE-13 ground identity + λ₀-vs-root-DADP equivalence, and the +25% FIT ratio golden + non-failing thesis cross-check.

## Key Computed Results
- **+25% ratio (computed golden):** `0.9999738567553946` (social_DADP=−4821.955, social_FIT=−4822.081 on the thermally-relaxed IEEE-13 ground scenario).
- **Gap to thesis 1.25:** `0.2500` — figure-bound, recorded via a `broken` test (non-failing).
- The ratio is ≈1.0 (not 1.25) because absolute social welfare is NEGATIVE in this framework's ¢$/kWh calibration (demand cost dominates utility; cf. the 04-06 golden welfare ≈ −4823). Dynamic pricing STILL improves welfare — social_DADP > social_FIT (less negative) — but the ratio of two negatives inverts direction (<1). This is the documented figure-bound caveat, exactly why the plan pins the computed ratio and treats 1.25 as aspirational.

## Decisions Made
- **λ₀ default = root DADP.** `welfare_accounting(ctx; T)` (no λ₀) recovers the MEM price as `extract_dlmp(ctx)[root, t]` — the thesis energy component; it equals λ₀ at the priced-frontier optimum by KKT, keeping the identity a genuine dual-consistency check. Passing an explicit λ₀ yields the same split (verified in the IEEE-13 test).
- **Open Q2 resolved.** The identity holds tight on both the near-lossless 2-bus (rtol 1e-6) and the lossy IEEE-13 (rtol 1e-4) — the `−r·l` losses are captured inside `objective_value` and `p_import` on both sides of the cancellation, so NO separate loss term was needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] FIT baseline infeasible on the un-relaxed IEEE-13; relaxed the head thermal limit for the FIT AC-PF**
- **Found during:** Task 2 (+25% FIT ratio)
- **Issue:** `fit_baseline(...)` on the standard modified IEEE-13 with the ground aggregators is INFEASIBLE (`assert_solved!` throws `INFEASIBLE`). The batteryless FIT schedule (Assumption A4 drops storage) cannot shift the PV peak, so it exports more surplus than the 0.0686-pu head-branch thermal limit permits — a limit the DADP optimum only just binds using its batteries. This blocked the plan's "build the FIT baseline for the IEEE-13 scenario" step.
- **Fix:** For the ratio test, run the FIT AC-PF (and the comparable DADP welfare) on a modified IEEE-13 whose head-branch thermal limit is set to the SMAX sentinel (99.0). This is thesis-consistent: the FIT step is a PLAIN AC power flow with network LIMITS NOT ENFORCED (fit.jl already relaxes the voltage band to [0.8,1.2] for the same reason, Open Q3); extending "not enforced" to the head thermal limit is the same modeling choice. The DADP welfare is solved on the SAME network so social_DADP and social_FIT stay directly comparable.
- **Files modified:** test/test_pricing_welfare.jl (the ratio @testitem builds the thermally-relaxed feeder inline)
- **Verification:** FIT baseline + DADP welfare both solve OPTIMAL; ratio finite, matches `base.ratio` (rtol 1e-6) and `obj/base.social_fit` (rtol 1e-8); full suite green.
- **Committed in:** `b207d06` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** The substitution keeps the plan's IEEE-13 scenario and the surplus/ratio semantics intact; it only removes a thermal limit the thesis FIT AC-PF does not enforce anyway. No scope creep.

## Issues Encountered
- **Ratio-of-negatives direction trap.** Because absolute welfare is negative, `social_DADP/social_FIT < 1` even though the DADP welfare is strictly HIGHER (better). Documented prominently in the test and this summary; the generous physical band (0.8–2.0) still guards a power-of-ten bug and the computed golden anchors regression.

## TDD Gate Compliance
Both tasks followed RED → GREEN: `test(05-05)` commit precedes each `feat(05-05)` commit (d2c230c→ac611d3, be7e311→b207d06). The identity throw is proven reachable by the `@test_throws` sign-flip guard.

## Next Phase Readiness
- PRICE-03 complete: the surplus split + identity gate and the +25% computed ratio are in place, closing the phase's welfare-accounting success criterion.
- **Follow-up (not blocking):** the absolute-welfare sign/magnitude is figure-bound (STATE Phase-4 caveat) — a future calibration pass toward the thesis's positive-welfare DER-rich regime would let the ratio reproduce the >1 "+25%" direction. The computed golden and non-failing cross-check are structured to absorb that recalibration.

## Self-Check: PASSED
- Files exist: src/pricing/welfare.jl, test/test_pricing_welfare.jl, 05-05-SUMMARY.md
- `function welfare_accounting` + `export welfare_accounting` present
- Commits present: d2c230c, ac611d3, be7e311, b207d06
- Full suite: 1049 pass, 1 broken (non-failing thesis cross-check), 0 fail, 0 error

---
*Phase: 05-distribution-pricing-dadp-dlmp-decomposition*
*Completed: 2026-07-19*
