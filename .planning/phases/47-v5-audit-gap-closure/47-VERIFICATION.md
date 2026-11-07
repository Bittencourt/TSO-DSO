---
phase: 47-v5-audit-gap-closure
verified: 2026-11-07T04:39:22Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 47: v5.0 Audit Gap Closure Verification Report

**Phase Goal:** Every certificate on the price-taker and flex-market paths reports only checks that actually ran, and every combination the milestone did not wire is refused loudly instead of silently mis-handled.
**Verified:** 2026-11-07T04:39:22Z
**Status:** passed
**Re-verification:** No. This is the initial verification.

Method: the verifier read code and ran `git diff` against the pre-implementation commit `9e9b709` and against HEAD `33b69d9`. The verifier did not run Julia. The suite, review and gate results below come from the orchestrator's runs at HEAD `33b69d9`, and this report cites them without re-running them.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Battery-certificate selection on `price_taker_dispatch` and `clear_flex_market` uses the device-type trait. V2G EVs get the EV co-charge certificate as their own status, and a V2G fixture on each path, including a negative-price case, never reports a false `:ok`. | VERIFIED | Both shape predicates (`p_ch ∧ p_dch ∧ ¬q`) are gone. `price_taker_dispatch` and `_deliver` both call the shared `_storage_certificates` (`src/settlement/price_taker.jl:86-109`). That helper selects through `_stash_entry_has_kind(types, v, i, :battery, …)` and `(…, :ev, _ -> false) && haskey(v, :p_dch)`, which is the same selection `assert_ev_complementarity!` uses (`src/models/complementarity_ev.jl:114-115`). The EV check runs at `τ_ev = TAU_EV_ADMM`, and `_certificate_status` maps a `CertificateError` to `:refused`, an absent check to `:not_checked` and a clean pass to `:ok`, rethrowing any other error. `_dispatch_record` adds `ev_certificate`, `ev_message` and `n_ev_*` to `physics.baseline` and `physics.delivered` (`src/coordination/flex_clear.jl:513-530`), and `clear_flex_market` returns `physics = phys`. Tests on the price-taker path (`test/test_settlement.jl`): negative-price V2G gives EV `:refused` and battery `:not_checked`; V1G, compliant (`:ok`), EV-free, battery plus EV, and wrapped-EV routing are also covered. Tests on the flex path (`test/test_flex_market.jl`): the negative-price `clear_flex_market` gives `physics.baseline.ev_certificate == [:refused]` and `battery_certificate == [:not_checked]`, and a compliant clear checks the delivered record. |
| 2 | `compare_tariffs` and `clear_flex_market` refuse actor inputs with an `ArgumentError`. The scope decision is recorded in REQUIREMENTS.md, the audit and the docs limitations. | VERIFIED | Both functions take an untyped `actors = nothing` keyword, and their first guard throws an `ArgumentError` that names "a recorded scope decision (future work …)": `src/settlement/comparison.jl:375-383` and `src/coordination/flex_settle.jl:326-333`. Zero-solve tests cover a `Portfolio`/`ProfitObjective` value and a wrong-typed `:x` on both functions (`test/test_flex_market_fence.jl`, `test/test_flex_market.jl`), and an explicit `actors = nothing` equals the default. REQUIREMENTS.md has the SETL-F2 entry and notes on the SETL-07/08 rows; the audit has the "Gap closure (Phase 47)" B2 row; `docs/literate/flex_market.jl` limitations has "Actors are not settled here." |
| 3 | `compare_tariffs` refuses unsupported Phase-43 devices before any solve. Flex stage 2 refuses devices with a reactive decision the same way it refuses `FixedCapacitor`. Each guard is tested. | VERIFIED | **W2:** a per-aggregator check sits in the `compare_tariffs` boundary-guard block (`comparison.jl:401-419`), between the shared-bus check and any solve; no solve call comes before line 480. It reads the same device set (`_FitUnsupportedDevice`, `src/pricing/fit.jl:72-77`) that `_reject_unsupported_flex_devices` uses, and the error type is still `ArgumentError`. Since the WR-03 fix, the check uses its own message instead of calling `_reject_unsupported_flex_devices` literally, which is an equivalent the context allows. The fence tests EV, HeatPump, SmartInverterPV and PartialCompliance and asserts a counted-solve `n == 0`. **W3:** `_refuse_reactive_decision` uses `has_reactive_decision(d) && !is_flexible_load(d)` (`flex_clear.jl:178-192`) and is called right after `_refuse_fixed_capacitor` at `_stage2_aggregators`, `_flex_physics` and `compare_tariffs` (with `flex_market`). Tests: SmartInverterPV and FourQuadBESS in `test/test_flex_market.jl` (`_stage2_aggregators` and a zero-call clear), FourQuadBESS through `compare_tariffs`, and SmartInverterPV through `clear_flex_market` (zero solves, "own reactive decision") in the fence. A flexible-load population passes the guard (`_refuse_reactive_decision([agg9], "x") === nothing`). |
| 4 | Default paths, goldens and the knife-edge canary stay byte-identical; no tolerance, τ, ε or floor changes; committed result CSVs are unchanged. | VERIFIED | `git diff 9e9b709 -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` returns 0 bytes. `git diff --stat 9e9b709 -- results/` is empty. `test/test_admm_knifeedge_canary.jl` and `test/test_actor_default_fence.jl` have no diff. `test/test_flex_market_fence.jl` shows 85 lines added and 0 removed. The EV τ is the existing `TAU_EV_ADMM` reused by name, and `τ_batt` defaults are unchanged. Cited gate results: canary 56 iterations / −4823.66604824162, JET 20 baseline with 0 new, planning IDs 354 (≤355). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/settlement/price_taker.jl` | `_certificate_status`, `_storage_certificates`, EV fields on `price_taker_dispatch` | VERIFIED | Substantive; called from `price_taker_dispatch` and `_deliver` |
| `src/coordination/flex_clear.jl` | trait-routed `_deliver`, EV fields in `_dispatch_record`, `_refuse_reactive_decision` | VERIFIED | Wired into `_flex_physics` (baseline and delivered) and `_stage2_aggregators` |
| `src/coordination/flex_settle.jl` | `actors` guard on `clear_flex_market` | VERIFIED | First guard, before any solve |
| `src/settlement/comparison.jl` | `actors` guard, up-front device check, reactive-decision guard | VERIFIED | All in the boundary block |
| `src/pricing/fit.jl` | shared unsupported-device set | VERIFIED | `_FitUnsupportedDevice` and `_fit_unsupported_device_names` are used by both guards |
| `docs/literate/flex_market.jl` | stage-2 refusal sentence and limitations bullets | VERIFIED | Comment prose only (see the docs note below) |
| `.planning/REQUIREMENTS.md` | SETL-F2 and row notes | VERIFIED | |
| `.planning/v5.0-MILESTONE-AUDIT.md` | gap-closure section | VERIFIED | |
| `.planning/todos/pending/2026-11-06-v5-integration-check-backlog.md` | W1, W4-W9, `@ref` warnings, review info items | VERIFIED | Exists and lists W1, W4–W9, both `@ref` warnings and IN-01..IN-09 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `price_taker_dispatch` / `_deliver` | `assert_battery_complementarity!` / `assert_ev_complementarity!` | `_storage_certificates` → `_certificate_status` | WIRED |
| `_flex_physics` stage 1 | `price_taker_dispatches` → `_dispatch_record` → `physics.baseline` | direct call, `flex_clear.jl:707-713` | WIRED |
| `_flex_physics` delivery | `_deliver` → `_dispatch_record` → `physics.delivered` | `flex_clear.jl:796` | WIRED |
| `clear_flex_market` | `physics` field | `physics = phys` (`flex_settle.jl:363,385`) | WIRED |
| `compare_tariffs` boundary | `_fit_unsupported_device_names`, `_refuse_reactive_decision` | boundary-guard block | WIRED |

### Behavioral Spot-Checks

The verifier ran no spot-checks; the constraint was no Julia while another heavy run could overlap. This report cites the orchestrator's full-suite run at HEAD `33b69d9`: **37134 pass / 0 fail / 0 error / 7 broken (expected)**. That is 154 tests above the P46 baseline of 36980/0/0/7, and the suite ran detached and alone.

### Probe Execution

Not applicable: no probes are declared, and this is not a migration or tooling phase.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| DEV-07 | 47-01, 47-03 | SATISFIED | V2G EV certificate reported honestly on the price-taker and flex paths (truth 1) |
| SETL-07 | 47-01, 47-02, 47-03 | SATISFIED | Flex physics EV status, actors guard, stage-2 reactive refusal (truths 1–3) |
| SETL-08 | 47-02, 47-03 | SATISFIED | `compare_tariffs` actors guard and up-front device refusal (truths 2–3) |
| SETL-F2 | 47-03 (recorded) | RECORDED (future) | Entry under future requirements in REQUIREMENTS.md, and guarded |

No requirement is orphaned.

### Anti-Patterns Found

The verifier found no `TBD`, `FIXME`, `XXX`, `TODO`, `HACK` or `PLACEHOLDER` in any line Phase 47 added under `src/`, `test/` or `docs/`.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/v5.0-MILESTONE-AUDIT.md` | W2 row | Says `compare_tariffs` "calls `_reject_unsupported_flex_devices`"; since WR-03 it reads the shared set through `_fit_unsupported_device_names` with its own message | Info | Wording drift only; the behaviour matches |
| `src/pricing/fit.jl` | `_reject_unsupported_flex_devices` message | Still says "phase-43 / phase-44" (backlog IN-09) | Info | Pre-existing; already in the backlog |

### Documented Deviation (accepted)

At the negative price, `_deliver` measured EV `:ok` with a ratio of about 4.2e-15: the tracking penalty pins the net injection at zero and prices co-charge out, so that `:ok` is true, not false. The plan's fallback was used: the test asserts `in (:ok, :refused)`, and the negative-price `:refused` on the flex path is shown through `physics.baseline`. τ was not touched.

### Docs Build

A docs rebuild has **not** run since Phase 47. The last docs build was the milestone-audit build before Phase 47, and it exited 0. The Phase 47 docs edit is comment prose in an existing Literate page (`docs/literate/flex_market.jl`) and adds no `@ref` or code. This report does not claim a passing post-Phase-47 docs build.

### Code Review

Iteration 1 found 3 warnings (WR-01..03), fixed in `e17250d`, `554a1c3` and `57f2e19`. Iteration 2 was clean: 0 critical, 0 warning, 9 info. The info items are backlogged in `.planning/todos/pending/2026-11-06-v5-integration-check-backlog.md`. The verifier confirmed that all cited commits exist.

### Human Verification Required

None.

### Gaps Summary

No gaps. B1, B2, W2 and W3 are closed in code, with tests on every path, and the SC3 golden pin holds byte for byte. W1 and W4–W9 are deliberately out of scope and are tracked in the backlog todo.

---

_Verified: 2026-11-07T04:39:22Z_
_Verifier: Claude (gsd-verifier)_
