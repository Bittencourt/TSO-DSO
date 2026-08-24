---
phase: 21-mpc-rolling-horizon-real-time-pricing
verified: 2026-08-09T18:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 21: MPC / Rolling-Horizon / Real-Time Pricing Verification Report

**Phase Goal:** A researcher can run a closed-loop receding-horizon solve over the stateful
devices (battery SOC, thermostatic temperature), with rolling re-computed DADPs published as a
real-time price signal, and see the closed loop honestly benchmarked against the
perfect-foresight day-ahead optimum.

**Verified:** 2026-08-09
**Status:** passed
**Re-verification:** No — initial verification (checked against post-review-fix HEAD `4b9d713`,
not the pre-fix state; this supersedes any first-pass reading of the code before the 10 fix
commits `d3937f9..4b9d713`)

## Method

This verification does NOT trust `SUMMARY.md`/`21-REVIEW.md` claims at face value. Every claim
below was checked against the actual current source (`src/models/mpc_window.jl`,
`src/models/mpc_trace.jl`, `src/experiments/mpc_loop.jl`, `src/experiments/Scenario.jl`,
`docs/literate/mpc_rolling_horizon.jl`) and, where the claim was behavioral, re-derived
independently with standalone Julia scripts (never `TestItemRunner` under `--project=.`, per this
repo's own documented tooling trap) that reconstruct the test fixtures from scratch and drive the
real (not mocked) `TSODSO` code. All scripts ran successfully against the live package on the
current `main` checkout; none are committed (scratchpad only, per instructions).

Independent behavioral checks executed and their results:

1. Build-once invariant: built one `MpcWindow`, re-solved it 3× at heterogeneous
   soc0/Tin0/terminal-target/forecast-slice/λ₀ states — `objectid(o.model)` unchanged,
   `num_variables`/`num_constraints` unchanged. **PASS.**
2. `terminal_soc` toggle produces a structurally different model (99 vs 97 constraints on the
   fixture) and rejects `H=1` with the toggle on (`WR-03`). **PASS.**
3. `run_mpc` happy path on `Scenario(feeder=:ieee13, T=9, mpc_H=3)`: `steps == T-H+1 == 7`,
   trace populated, all finite, all `:certified_convex_dual`. **PASS.**
4. `WR-02` guard (`mpc_step == mpc_H` with stateful devices) and `WR-07` guard (`mpc_H > T`) both
   throw `ArgumentError` as documented. **PASS.**
5. `mpc_step` genuinely strides the resolve cadence (D-03): two runs at `mpc_step=1` vs `2` on the
   identical scenario produce the SAME published-step count but genuinely DIFFERENT
   `realized_welfare`/`dadp_trace` under nonzero forecast error. **PASS.**
6. **CR-01 regression, independently reproduced**: drove `TSODSO._mpc_certify_and_price` directly
   against the high-PV forced-inexact fixture (`pv_scale=3.0`, cone ratio ≈ 9157×) at `t=1` and
   `t=4` under a FLAT `λ₀` — the two escalation prices are DISTINCT
   (`[4.005, 4.010, 1.956]` vs `[1.901, 1.901, 1.878]`), confirming the escalation ladder now
   prices the CURRENT window, not the pre-fix "hours 1..H with construction-time ICs" bug.
   **PASS.**
7. **CR-02/WR-04 regression, independently reproduced**: injected throwing stand-ins
   (`_solve_welfare`/`_ac_dual_fallback_price`) into `_mpc_certify_and_price` — both tiers failing
   published `:cert_failed` with the fallback-price window slice and never propagated an
   exception; forcing only tier 2 to fail reached the genuine tier-3 `:local_ac_dual` pricer.
   **PASS.**
8. **MPC-02 dump/hoard A/B regression, independently reproduced** (not merely re-read): rebuilt
   `test_mpc_terminal.jl`'s exact fixture/price-spike/mini-loop from scratch and measured
   `dev_disabled = 9.328e-7`, `dev_enabled = 2.626e-11`, ratio `≈ 35,530×` — matching the
   documented measurement to 4 significant figures. This is the single most safety-critical
   honesty claim in the phase (the terminal condition genuinely prevents the artifact, it is not
   assumed), and it reproduces cleanly on a from-scratch rebuild of the fixture. **PASS.**
9. **Literate page (MPC-04), independently re-executed**: ran the exact `Scenario`/`run_mpc` call
   the literate page makes (`T=24, mpc_H=6, mpc_terminal_soc=true, mpc_forecast_error=0.08`) —
   `steps=19`, `regret=-0.032125...` (matches `21-06-SUMMARY.md`'s self-check `-0.03212514...` to
   solver-noise precision), `any_cert_failed=false`, all 19 steps `:certified_convex_dual` —
   confirming the page's numbers are genuinely live-computed, not stale/hardcoded, and that the
   CR-03 rewrite (regret flipped from a small positive bias to this small negative, honest value)
   is real in the current code, not just narrated. **PASS.**
10. `Scenario`'s `mpc_H`/`mpc_step`/`mpc_terminal_soc`/`mpc_forecast_error` fields confirmed
    additive-only: `grep mpc_ src/experiments/run.jl` returns zero matches — `run_scenario`'s
    `:centralized`/`:admm` dispatch genuinely never reads them (D-01/D-12). **PASS.**

## Goal Achievement

### Observable Truths (mapped 1:1 to ROADMAP.md Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|---|---|---|
| 1 | Deterministic receding-horizon closed-loop solve; window `[t,t+H]` initialized from measured device state via JuMP `Parameter` injection — built once, re-solved per step, never rebuilt. | VERIFIED | `build_mpc_window`/`solve_mpc_window!` (`src/models/mpc_window.jl:62-311`); independently reproduced build-once invariant (same `objectid`, unchanged var/constraint counts across 3 heterogeneous re-solves — check 1 above); `run_mpc`'s outer loop (`src/experiments/mpc_loop.jl:286-400`) calls `set_parameter_value`/`set_objective_coefficient` on the SAME `o` every resolve, never `build_mpc_window` again. |
| 2 | Hard terminal-SOC condition prevents end-of-horizon dump/hoard, with an A/B regression (artifact present when disabled, absent when enabled). | VERIFIED | `terminal_soc` toggle mechanism (`mpc_window.jl:226-269`, `WR-03` guard at `H=1`); A/B regression independently rebuilt from scratch and re-measured — `dev_disabled=9.33e-7` vs `dev_enabled=2.63e-11`, ratio ≈ 35,530× (check 8 above), matching `test_mpc_terminal.jl`'s documented measurement. |
| 3 | Rolling re-computed DADP published per step as RTP signal, with price-consistency metrics (step jumps, cumulative deviation vs day-ahead path) in a trace struct following the `AdmmResiduals`/`BendersTrace` convention. | VERIFIED | `MpcTrace` (`src/models/mpc_trace.jl`, mirrors `AdmmResiduals`'s fields/`record!`/fail-loud sequential-`k` guard verbatim); `max_jump`/`mean_jump`/`any_cert_failed` query predicates; independently confirmed `run_mpc` populates a `steps`-length trace with correct `jump`/`cum_deviation` bookkeeping (checks 3, 9 above) and that `any_cert_failed` is genuinely reachable (`:cert_failed`, check 7). |
| 4 | Closed-loop trajectory benchmarked against perfect-foresight day-ahead optimum under seeded synthetic forecast error, information-set-fair, in a live-executed literate rung page. | VERIFIED | `regret` computation (`mpc_loop.jl:415-425`) sources BOTH sides (utilities AND frontier `p_import`) from `ctx_da_cmp`, the Deferrable-excluded comparable day-ahead benchmark (CR-03 fix, independently confirmed present in current code — no longer reading `p_import` from the full-population `ctx_da`); `draw_forecast_error` (`mpc_window.jl:369-392`) is seeded, independent, regenerated per step; `docs/literate/mpc_rolling_horizon.jl` independently re-executed end-to-end (check 9), reproducing the documented `regret≈-0.0321` to solver-noise precision; wired into `docs/make.jl` (Literate source list + `"Models"` pages entry) and `docs/src/api.md` (`@autodocs Pages = ["models/mpc_trace.jl","models/mpc_window.jl","experiments/mpc_loop.jl"]`). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/models/mpc_window.jl` | `MpcWindow`, `build_mpc_window`, `solve_mpc_window!`, `propagate_soc`, `propagate_tin`, `draw_forecast_error` | VERIFIED | 394 lines; substantive, no stubs; all functions exercised behaviorally above. |
| `src/models/mpc_trace.jl` | `MpcTrace`, `record!`, `max_jump`, `mean_jump`, `any_cert_failed` | VERIFIED | 133 lines; mirrors `AdmmResiduals` convention; independently exercised. |
| `src/experiments/mpc_loop.jl` | `run_mpc`, `_mpc_certify_and_price`, `_mpc_assert_state_keying`, `_mpc_escalation_aggregators`, `_mpc_window_device`, `_mpc_device_hour_utility` | VERIFIED | 852 lines; every review-flagged Critical/Warning finding's fix (CR-01/02/03, WR-01..07) confirmed present in the current source text AND behaviorally reproduced where testable in a targeted script (CR-01, CR-02, WR-02, WR-03, WR-07). |
| `src/experiments/Scenario.jl` | additive `mpc_H`/`mpc_step`/`mpc_terminal_soc`/`mpc_forecast_error` `@kwdef` fields | VERIFIED | Confirmed additive-only (never read by `run_scenario`/`run.jl`'s `:centralized`/`:admm` dispatch — zero `grep` matches). |
| `docs/literate/mpc_rolling_horizon.jl` | live-executed Rung 8 page | VERIFIED | 187 lines; independently re-executed, numbers reproduce to solver-noise precision; wired into `docs/make.jl` and `docs/src/api.md`. |
| `test/fixtures_phase21.jl`, `test/test_mpc_window.jl`, `test/test_mpc_trace.jl`, `test/test_mpc_terminal.jl`, `test/test_mpc_loop.jl` | Phase-21 CI coverage | VERIFIED | Present, substantive (15 `@testitem`s across 4 files + 1 shared fixture module); logic independently reproduced outside `TestItemRunner` for the load-bearing items (build-once, terminal A/B, escalation ladder, happy path, stride). |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `run_mpc` | `build_mpc_window`/`solve_mpc_window!` | build-once, `set_parameter_value`/`set_objective_coefficient` per resolve | WIRED | Independently confirmed same model object across 3 heterogeneous re-solve cycles. |
| `run_mpc` | `MpcTrace.record!` | per applied hour, inside the `n_apply` loop | WIRED | `trace.steps == r.steps` confirmed on 3 independent scenario configurations. |
| `run_mpc` | Phase-20 certificate/fallback ladder (`RestrictedBranchFlow`, `assert_restriction_exact!`, `ac_dual_fallback_price`) | `_mpc_certify_and_price` | WIRED | Independently forced escalation on the high-PV fixture; all three tiers (`:certified_convex_dual_restricted`, `:local_ac_dual`, `:cert_failed`) individually and distinctly reachable. |
| `Scenario.mpc_*` fields | `run_mpc` | direct field reads, never through `run_scenario` | WIRED (and confirmed NOT cross-wired into `:centralized`/`:admm`) | `grep mpc_ src/experiments/run.jl` → 0 matches. |
| `regret` | `ctx_da_cmp` (Deferrable-excluded day-ahead benchmark) | both utility AND frontier `p_import` terms | WIRED | Source-read confirms both terms come from `ctx_da_cmp.meta[...]`, not the full-population `ctx_da` (CR-03 fix present). |
| `docs/literate/mpc_rolling_horizon.jl` | `docs/make.jl` / `docs/src/api.md` | Literate source list, `pages=` entry, `@autodocs Pages=[...]` | WIRED | Grep-confirmed in both files. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `run_mpc` return `trace` | `MpcTrace.dadp_trace`/`cert_status_trace` | `dual.(o.ctx.constraints[:balance_p][...])` (real Clarabel duals) or the certified fallback tiers | Yes — independently confirmed non-constant, non-empty, correctly-lengthed trace on 3 scenario configs | FLOWING |
| Literate page `r.regret`/`r.trace` | `run_mpc(s)` | genuine `solve_welfare`/window re-solves, not a static return | Yes — independently re-executed, reproduces documented values | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Build-once invariant | standalone script, `objectid`/`num_variables`/`num_constraints` before/after 3 re-solves | unchanged | PASS |
| `terminal_soc` structural difference | standalone script, `num_constraints` true vs false | 99 vs 97 | PASS |
| `WR-03` guard | standalone script, `build_mpc_window(...; H=1, terminal_soc=true)` | throws `ArgumentError` | PASS |
| `run_mpc` happy path | standalone script, `Scenario(T=9, mpc_H=3)` | `steps=7`, all finite, all certified | PASS |
| `WR-02` guard | standalone script, `mpc_step=mpc_H=3` with stateful devices | throws `ArgumentError` | PASS |
| `WR-07` guard | standalone script, `mpc_H=8 > T=5` | throws `ArgumentError` | PASS |
| `mpc_step` load-bearing (D-03) | standalone script, `mpc_step=1` vs `2` under forecast error | different `realized_welfare`/`dadp_trace`, same `steps` | PASS |
| CR-01 escalation prices the current window | standalone script, `_mpc_certify_and_price` at `t=1` vs `t=4` | distinct prices | PASS |
| CR-02/WR-04 never-throw ladder | standalone script, injected throwing tier stand-ins | `:cert_failed` published, no exception | PASS |
| MPC-02 dump/hoard A/B | standalone script, from-scratch fixture rebuild | ratio ≈ 35,530× | PASS |
| Literate page re-execution | standalone script, exact `Scenario`/`run_mpc` call | `regret≈-0.0321`, matches SUMMARY to solver-noise precision | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes declared for this phase; none found under `scripts/`.
Step 7c: SKIPPED (no probes declared or discovered).

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| MPC-01 | 21-01, 21-03, 21-04, 21-05 | Deterministic receding-horizon closed-loop, build-once/re-solve via `Parameter` injection | SATISFIED | Independently reproduced build-once invariant + `run_mpc` end-to-end. |
| MPC-02 | 21-03, 21-04 | Hard terminal-SOC condition, dump/hoard A/B regression | SATISFIED | Independently reproduced A/B regression (35,530× separation). |
| MPC-03 | 21-02, 21-05 | Rolling DADP as RTP signal, price-consistency metrics in `AdmmResiduals`/`BendersTrace`-style struct | SATISFIED | `MpcTrace` reviewed + exercised; `any_cert_failed`/`max_jump`/`mean_jump` confirmed non-vacuous. |
| MPC-04 | 21-05, 21-06 | Regret benchmark vs perfect-foresight day-ahead, seeded forecast error, info-set-fair, literate page | SATISFIED | CR-03 fix confirmed present in code; literate page independently re-executed. |

No orphaned requirements: `.planning/REQUIREMENTS.md`'s `### MPC` section lists exactly MPC-01..04,
all four claimed across the six plans' `requirements:` frontmatter, all four appear in at least
one plan's `must_haves.truths`.

`REQUIREMENTS.md`'s traceability table still shows `Phase 21 | Pending` for all four IDs and the
checklist items remain unchecked `[ ]` — this is EXPECTED at this point in the workflow (confirmed
by inspecting how Phase 20 closed: `git show 0967fbd` — the `[ ]→[x]`/`Pending→Complete` flip
happens in the orchestrator's own `docs(phase-N): complete phase execution` commit, which runs
AFTER verification passes, not before). Not a gap.

### Anti-Patterns Found

None blocking. No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK` markers in any Phase-21 file. Two occurrences
of the literal word "PLACEHOLDER" in `mpc_window.jl` (lines 116, 271) refer to the documented,
ALWAYS-overridden `0.0` objective coefficient on `p_import` at build time (the caller calls
`set_objective_coefficient` before every solve, confirmed live in check 1/3/9 above) — this is an
accurately-labeled, non-user-visible build-time default, not a stub or debt marker.

Five Info-level findings from `21-REVIEW.md` (IN-01..IN-05) remain open by design (explicitly out
of the `critical_warning` fix-pass scope): a docstring signature mismatch on an internal helper,
`mean_jump`'s documented dilution behavior, a non-concrete struct field type, a doc typo, and a
softened-but-not-fully-rewritten literate-page sentence. None of these affect goal achievement —
they are minor, non-blocking documentation/style nits on internal (unexported except `MpcTrace`
query functions) surfaces. Not gaps; noted for completeness only.

### Human Verification Required

None. Every must-have for this phase's four success criteria is either a deterministic numeric
result independently reproduced above, or a structural/wiring fact confirmed by direct source
inspection plus a standalone script. No visual, real-time, or external-service surface exists in
this phase's scope.

### Gaps Summary

No gaps. All three Critical and seven Warning findings from `21-REVIEW.md`'s standard-depth code
review (CR-01 escalation-ladder wrong-window bug, CR-02 non-genuine never-throw contract, CR-03
biased regret benchmark, WR-01..07) were independently confirmed FIXED in the current source
(HEAD `4b9d713`), not merely claimed fixed — six of the ten fixes were behaviorally re-derived
from scratch in standalone scripts against the live package (CR-01, CR-02/WR-04, WR-02, WR-03,
WR-07, and the MPC-02 terminal A/B regression), matching the documented measurements to
solver-noise precision. The remaining fixes (WR-01 documentation, WR-05 state-keying assertion,
WR-06 `allow_export` threading) were confirmed present by direct source read against the exact
review finding they address. The phase's own closing full-suite/docs-build claims (`2685 passed`
post-fix per commit `4b9d713`'s message, matching this verification's supplied clean-env
expectation) were not independently re-run in full (per the explicit instruction to avoid
re-running the full suite and rely on targeted checks), but every load-bearing behavioral claim
within that suite was independently spot-checked above.

---

_Verified: 2026-08-09_
_Verifier: Claude (gsd-verifier)_
