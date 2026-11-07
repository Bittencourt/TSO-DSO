---
phase: 47-v5-audit-gap-closure
plan: 02
subsystem: settlement
tags: [guards, actors, flex-market, tariff-comparison, reactive-power, honesty-policy, julia]

requires:
  - phase: 47-01
    provides: _storage_certificates, the EV certificate fields on _deliver and the flex physics record
  - phase: 45
    provides: clear_flex_market, compare_tariffs with flex_market, _refuse_fixed_capacitor
  - phase: 44
    provides: Portfolio / ProfitObjective actors, behavioural wrappers (apply_behaviour)
  - phase: 43
    provides: _reject_unsupported_flex_devices (fit.jl), has_reactive_decision / is_flexible_load traits
provides:
  - untyped `actors = nothing` keyword on compare_tariffs and clear_flex_market; any other value is an ArgumentError naming the scope decision, raised before any solve
  - compare_tariffs refuses EV / HeatPump / SmartInverterPV / behavioural-wrapper populations in its boundary guards (zero solves)
  - _refuse_reactive_decision (internal, src/coordination/flex_clear.jl), called after each _refuse_fixed_capacitor call (three sites)
  - clear_flex_market docstring records the undetected SettlementInput-from-actor-run limitation
affects: [47-03 closure docs (flex_market.jl limitations, REQUIREMENTS SETL-F2, backlog provenance flag)]

tech-stack:
  added: []
  patterns:
    - "Unsupported keyword values are refused by an untyped keyword plus an ArgumentError as the first statement, never by a MethodError"
    - "Stage-2 refusals are trait-based: has_reactive_decision(d) && !is_flexible_load(d)"

key-files:
  created: []
  modified:
    - src/settlement/comparison.jl
    - src/coordination/flex_settle.jl
    - src/coordination/flex_clear.jl
    - test/test_flex_market_fence.jl
    - test/test_flex_market.jl

key-decisions:
  - "Explicit untyped `actors = nothing` keyword with an ArgumentError, not the MethodError precedent: the success criterion requires an ArgumentError naming the scope decision, and an untyped keyword keeps a wrong-typed value (actors = :x) an ArgumentError too"
  - "SettlementInput-from-actor-run channel documented, not guarded: it cannot be told apart from a normal input without changing the pinned SettlementInput type"
  - "Behaviour wrappers are not an actor channel: a PartialCompliance population clears through clear_flex_market with status \"ok\" and ledger residual 0.0 (measured, primary pin held)"
  - "The W2 refusal reuses _reject_unsupported_flex_devices unchanged, with caller \"compare_tariffs (the fit leg runs fit_baseline / FIT-OPT)\"; the fit.jl call stays for direct fit_baseline callers"
  - "W3 predicate is has_reactive_decision(d) && !is_flexible_load(d), so it selects exactly SmartInverterPV and FourQuadBESS"

patterns-established:
  - "New stage-2 refusals are siblings of _refuse_fixed_capacitor, called right after it at every site"

requirements-completed: [SETL-07, SETL-08]

duration: 35min
completed: 2026-11-07
---

# Phase 47 Plan 02: Loud input guards for the flexibility market and tariff comparison Summary

**`compare_tariffs` and `clear_flex_market` now refuse actor inputs with an `ArgumentError` that names the recorded scope decision. `compare_tariffs` refuses devices the fit leg cannot model before the DADP solve, not after it. Flex stage 2 refuses `SmartInverterPV` and `FourQuadBESS` the same way it refuses `FixedCapacitor`. Every refusal has a test proving that no solve ran, and every guard is a no-op on supported inputs.**

## Performance

- **Duration:** about 35 min
- **Tasks:** 3 (2 fix commits, 1 style commit; Task 3 is gates only)
- **Files modified:** 5

## Accomplishments

- **B2 (guard part).** Both entry points take an untyped `actors = nothing` keyword. The first statement throws an `ArgumentError` for any other value: in `compare_tariffs` it is the first line of the boundary-guard block, and in `clear_flex_market` it comes before `input.T == T`. The message says that settling `Portfolio` / `ProfitObjective` actors is a recorded scope decision (future work). `actors = :x` is also an `ArgumentError`, not a `MethodError`.
- **B2 limitation documented.** A **Actors** paragraph sits next to **Reactive power** in the `clear_flex_market` docstring. It says that an `input` from an actor-objective run is not detected and that its wedges are not carried into the ledger.
- **W2.** `compare_tariffs` calls `_reject_unsupported_flex_devices` per aggregator right after the shared-bus check. EV, HeatPump, SmartInverterPV and wrapper populations used to be refused after one welfare solve; they are now refused with zero solves. The device set and error type are unchanged, and the `fit.jl` call is untouched.
- **W3.** `_refuse_reactive_decision` is the sibling of `_refuse_fixed_capacitor` and is called right after it in `_stage2_aggregators`, `_flex_physics` (so `clear_flex_market` is covered) and `compare_tariffs` with `flex_market`. The FixedCapacitor message is unchanged.
- **Docstrings.** The `compare_tariffs`, `clear_flex_market`, `_stage2_aggregators` and `_flex_physics` docstrings list the new refusals. The `flex_clear.jl` header comment names the two device types.

## Task Commits

1. **Task 1: actors scope guard and up-front unsupported-device refusal:** `16ba018` (fix)
2. **Task 2: reactive-decision refusal in flex stage 2:** `a4f6d37` (fix)
3. **Task 3: style pass, fences and gates:** `7262924` (style). The formatter only rewrapped long lines that this plan inserted in the two test files. The content-loss check reported OK.

TDD: each fix commit contains its tests. RED was run and observed before the implementation in both tasks (see below).

## RED Evidence

| Task | Observed before implementation |
|---|---|
| 1 | `actors` cases gave a `MethodError`; each of EV, HeatPump, SmartInverterPV and PartialCompliance gave `n == 1` (refused by `fit_baseline (FIT-OPT)` after the DADP solve); the new clear item errored on `actors = nothing` (MethodError) |
| 2 | `_stage2_aggregators` accepted both devices (`nothing isa ArgumentError`); `_flex_physics` / `clear_flex_market` ran with `dev.calls[] == 4`; `_refuse_reactive_decision` was undefined; the FourQuadBESS `compare_tariffs` case did not refuse. 22 failures and 6 errors in total. The SmartInverterPV case with `flex_market` already passed, because the Task 1 device guard refuses it. |

## Measured Outcomes

| Check | Measured |
|---|---|
| Test 5: `apply_behaviour([f.agg], BehaviourSpec(compliance = 0.5); T = 3)` on the market fixture (seed 20260719), DADP on the wrapped population, then `clear_flex_market` | wrapped device is a `PartialCompliance`; no exception; **status `"ok"`**, `ledger_residual == 0.0`. Primary pin held, no fallback. |
| Test 2a: `compare(; actors = nothing)` | all four frames `isequal` to the default; summary column names unchanged |
| Test 2b: `clear_flex_market(...; actors = nothing)` | status, baseline_price, payment_rows, flex_payments_total, welfare_lossless and ledger transfers `isequal` to the default |
| Zero-solve proofs | counting `welfare_optimizer` n == 0 on every new `compare_tariffs` case; `FailAtCall` `dev.calls[] == 0` on every refused clear and physics call |

## Test Counts (fast set, targeted)

| Batch | Files | Result |
|---|---|---|
| Task 1 RED | test_flex_market_fence.jl, test_flex_market.jl | failed as expected (21 fail + 1 error in the fence file, 1 error in the new clear item) |
| Task 1 GREEN | test_flex_market_fence.jl, test_flex_market.jl | 1504/1504 pass |
| Task 2 RED | test_flex_market.jl, test_flex_market_fence.jl | failed as expected (flex_market 22 fail + 6 error, fence 4 fail) |
| Task 2 GREEN | test_flex_market.jl, test_flex_market_fence.jl | 1542/1542 pass |
| Fence batch 1 | test_flex_market_fence.jl, test_admm_knifeedge_canary.jl | 136/136 pass; canary 56 iterations / −4823.66604824162, 0 escalations; fence digests equal their pins |
| Fence batch 2 | test_behaviour.jl, test_flex_population.jl, test_settlement.jl, test_device_traits.jl | 616/616 pass |
| Fence batch 3 | test_flex_market.jl | 1411/1411 pass |

Every run stayed under 3.5 minutes. `test/Project.toml` and `test/Manifest.toml` were restored after each run.

## Gates

| Gate | Result |
|---|---|
| Planning IDs | 354 hits, 0 stale (at most 355); unchanged by this plan |
| Scripts index | complete (48 files) |
| JET | 20 current, 20 baseline, 0 new, 0 fixed |
| SC3 (`git diff 9e9b709` over src/admm, exactness.jl, factory.jl, expected_broken.txt) | empty |
| τ gate (`τ_batt::Real = 1e-3` counts per file vs 9e9b709) | unchanged |
| Golden pins | fence file only gained lines vs 9e9b709; canary and actor-fence files unchanged; 2 removed lines in test_flex_market.jl (the earlier `_deliver` pin statement; this plan removed none) |
| results/ | untouched |
| Formatter | no-op after the style commit |
| Content-loss check | OK |
| Exports | `src/TSODSO.jl` and `test/test_exports.jl` untouched; no new export |

## Deviations from Plan

None in behaviour. Test 5 measured `"ok"` with residual 0.0, so the primary pin is used and the fallback was not needed. Smaller adjustments:

- **W2 call shape.** The caller string is bound to a local `fit_caller`, so that `_reject_unsupported_flex_devices(a.devices, fit_caller)` stays on one line through the formatter. The verify grep `_reject_unsupported_flex_devices(a.devices` needs that.
- **Actors limitation placement.** The sentence is its own short **Actors.** paragraph directly after **Reactive power.**, not a sentence inside it. It covers both the refusal and the undetected `SettlementInput` channel.
- **Test placement.** Tests 1, 4 and 8 are new `cases` entries inserted after `"capacitor"` (before `"lindistflow"`), plus new reason-specific asserts after the existing ones. Test 2a was inserted after the existing default loop. No existing fence line was edited. Tests 2b, 3 and 5 form one new item; Tests 6, 7 and 9 form another.
- **Commit structure.** Each task's tests were committed with its implementation in the single `fix(47)` commit the plan names, as in plan 01. RED was still run and observed first.
- A temporary `@info` of the measured Test 5 status was removed before the Task 1 commit, once the primary pin held.

## Known Stubs

None.

## Threat Flags

None. The plan adds only refusals and no new endpoints, file access or trust-boundary surface. T-47-02-01, -03, -04 and -05 are mitigated and tested. T-47-02-02 is accepted and documented in the docstring; the docs page and backlog line follow in the closure plan.

## Self-Check: PASSED

- FOUND: src/coordination/flex_clear.jl (`function _refuse_reactive_decision(aggs`, two call sites)
- FOUND: src/settlement/comparison.jl (`actors === nothing ||`, `_reject_unsupported_flex_devices(a.devices`, `_refuse_reactive_decision(aggs, "compare_tariffs")`)
- FOUND: src/coordination/flex_settle.jl (`actors === nothing ||`)
- FOUND: test/test_flex_market.jl (`_refuse_reactive_decision`), test/test_flex_market_fence.jl (`actors`)
- FOUND: commits 16ba018, a4f6d37, 7262924
