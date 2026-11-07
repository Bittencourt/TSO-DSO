---
phase: 47-v5-audit-gap-closure
fixed_at: 2026-11-06T00:00:00Z
review_path: .planning/phases/47-v5-audit-gap-closure/47-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 47: Code Review Fix Report

**Fixed at:** 2026-11-06
**Source review:** .planning/phases/47-v5-audit-gap-closure/47-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (WR-01, WR-02, WR-03; there were no Critical findings)
- Fixed: 3
- Skipped: 0
- Out of scope: IN-01 to IN-06 (Info), not attempted

Work ran on the main tree, with no worktree or branch, as the user asked.

## Fixed Issues

### WR-01: The compliant-clear test accepts every status, so the `physics.delivered` EV record can go untested without a failure

**Files modified:** `test/test_flex_market.jl`
**Commit:** e17250d
**Applied fix:**
- The status disjunction is replaced by `@test res.status == "ok"`, which is the measured value from 47-01 Test K and was measured again in this run.
- `@test res.physics.delivered !== nothing` and `ev_fields_ok(res.physics.delivered)` now run unconditionally. The second is guarded only against a `nothing` record, so a missing record fails the first assert instead of erroring.
- The EV certificate value stays in `(:ok, :refused)`, as decided in CONTEXT.
- These lines were added in this phase. The file's removed-line count against `9e9b709` stays at 2.

### WR-02: The SmartInverterPV + `flex_market` fence case is credited to the reactive-decision guard, but the fit-leg guard refuses it

**Files modified:** `test/test_flex_market_fence.jl`, `src/settlement/comparison.jl`
**Commit:** 554a1c3
**Applied fix:**
- **Fence, `compare_tariffs` case.** The comment now says what happens: in `compare_tariffs`, only `FourQuadBESS` reaches the stage-2 reactive-decision guard, and `SmartInverterPV` is refused first by the fit-leg device guard.
  - `r_sipv` asserts `"fit leg"` is in the message and `"own reactive decision"` is not.
  - The `FourQuadBESS` assert is tightened from `"reactive"` to `"own reactive decision"`.
- **Fence, new `clear_flex_market` case.** It calls `clear_flex_market` directly, which has no fit leg, with the SmartInverterPV population and the counting optimizer factory. It asserts zero solves, the device name, and `"own reactive decision"`. This is the case that actually reaches the stage-2 guard for SmartInverterPV.
- **Duplicate case dropped.** The `"smartinverterpv_flex"` entry in `cases` duplicated `"smartinverterpv"`. It was added in this phase, so the fence file still only gains lines relative to `9e9b709`. The end-relative indices `cases[end - 2]` and `cases[end - 1]` are unaffected.
- **`compare_tariffs` docstring.** It now lists only `FourQuadBESS` under the `flex_market` reactive-decision refusal. It also says that `SmartInverterPV` is refused up front by the device check, whether or not `flex_market` is set.

### WR-03: The new up-front W2 refusal surfaces a message whose remedy is wrong for `compare_tariffs`

**Files modified:** `src/settlement/comparison.jl`, `src/pricing/fit.jl`, `test/test_flex_market_fence.jl`
**Commit:** 57f2e19, plus the formatter-only commit dc21e9c (`style(47)`)
**Applied fix:**
- **New message.** `compare_tariffs` now throws its own `ArgumentError`. The message:
  - names the aggregator index, its bus and the device types;
  - says the tariff comparison does not support them, because every comparison runs the fit leg (`fit_baseline` / FIT-OPT), which has no model for these devices;
  - points to the route that works: `solve_welfare` or `solve_admm`, then `price_taker_dispatch` or `clear_flex_market` directly;
  - says `clear_flex_market` accepts EVs, heat pumps and behaviour-wrapped devices but refuses `SmartInverterPV`.

  The message has no planning IDs. It deliberately avoids the phrase "own reactive decision", so the WR-02 negative assert still tells the two guards apart.
- **Shared device set.** The set lives in one internal constant in `src/pricing/fit.jl`, `_FitUnsupportedDevice`, read through `_fit_unsupported_device_names`. `_reject_unsupported_flex_devices` and `compare_tariffs` both use it, so the two cannot drift apart. The error type is still `ArgumentError`, and the device set is unchanged.
- **`fit_baseline` message unchanged.** No test pins its "phase-43 / phase-44" text: `test_behaviour.jl` and `test_flex_population.jl` pin only the caller and the type names. The message was still left as it was, to keep the change narrow.
- **Docstring.** The `compare_tariffs` paragraph on the device check now describes the new message and the working route. It no longer says "the same `ArgumentError` as `fit_baseline`".
- **Fence asserts.** The per-device loop, added in this phase, now pins the new message. It checks for "tariff comparison does not support", "solve_welfare or solve_admm", `clear_flex_market` and `price_taker_dispatch`, and checks that the message has no `phase-<n>` text.

## Notes

- **Pre-existing wording.** The shared `_reject_unsupported_flex_devices` message in `src/pricing/fit.jl` still says "phase-43 flexible devices / phase-44 behavioural wrappers" and "drop `flex_devices`". `compare_tariffs` users no longer see it. `fit_baseline`, `run_mpc` and the stochastic-welfare callers still do. Removing those planning IDs from the shared message is left as a follow-up, as the review suggested.
- **Wording deviation.** The guidance suggested the phrase "five-scheme comparison". The code calls the base rows "the four tariff rows" (dadp, flat, tou, fit), and the flex rows are optional. To avoid stating a scheme count that is wrong in one of the two cases, the message says "the tariff comparison".
- **Formatter side effect.** JuliaFormatter 2.10.2 reflowed the existing `_reject_unsupported_flex_devices` docstring in `fit.jl`: it joined a backtick span that was split across two lines, and the joined line is long. `check_content_loss.py` reports a whitespace-only change. The reflow is in the `style(47)` commit dc21e9c.

## Verification

- **Targeted tests.** `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl`: 1564 pass, 0 fail, 0 error, in 2m58s. The compliant clear logged `status = "ok"` and baseline EV `:ok`. `test/Project.toml` and `test/Manifest.toml` were restored afterwards.
- **Golden-pin gates against `9e9b709`:**
  - the fence file has no removed lines;
  - `test_admm_knifeedge_canary.jl` and `test_actor_default_fence.jl` have no diff;
  - `test_flex_market.jl` has 2 removed lines, within the bound of 2;
  - `src/admm`, `src/models/exactness.jl`, `src/solver/factory.jl` and `test/expected_broken.txt` have no diff;
  - `results/` is unchanged;
  - no τ, tolerance or floor was changed.
- **`check_planning_ids.py`:** 354, unchanged and within the bound of 355.
- **JET:** 20 current, 20 baseline, 0 new.

---

_Fixed: 2026-11-06_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
