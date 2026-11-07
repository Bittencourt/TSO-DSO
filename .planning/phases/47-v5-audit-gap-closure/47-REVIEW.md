---
phase: 47-v5-audit-gap-closure
reviewed: 2026-11-06T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - docs/literate/flex_market.jl
  - src/coordination/flex_clear.jl
  - src/coordination/flex_settle.jl
  - src/settlement/comparison.jl
  - src/settlement/price_taker.jl
  - test/test_flex_market.jl
  - test/test_flex_market_fence.jl
  - test/test_settlement.jl
findings:
  critical: 0
  warning: 3
  info: 6
  total: 9
status: issues_found
---

# Phase 47: Code Review Report

**Reviewed:** 2026-11-06
**Depth:** standard (scope: `git diff 9e9b709..HEAD` on the eight files above)
**Files Reviewed:** 8
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

I traced each focus area through the code it calls: `_stash_entry_has_kind` and the
`storage_kind` overrides (`CapabilityTraits.jl`), both certificates (`welfare_solve.jl`,
`complementarity_ev.jl`), the behavioural wrappers' `contribute!` (`Behavioural.jl`), the
`Aggregator.contribute!` stash pairing, `_reject_unsupported_flex_devices` (`fit.jl`), and
every consumer of the price-taker, `_deliver` and `_dispatch_record` NamedTuples in `src/`,
`scripts/`, `docs/` and `test/`.

**What holds (verified, not assumed):**

- **No `:ok` without a check.** In `_storage_certificates` the presence predicates are the
  certificates' own selections, entry for entry:
  - battery: `_stash_entry_has_kind(..., :battery, legacy_shape)`;
  - EV: `_stash_entry_has_kind(..., :ev, _ -> false) && haskey(v, :p_dch)`.

  `_certificate_status` returns `:ok` only after `f()` returns. Whenever presence is true, the
  matching certificate loops over that same entry for `t in 1:T`, so `:ok` always means the
  check ran.
- **V1G and wrapped EVs.**
  - V1G vars have no `:p_dch`, so they are excluded by both the predicate and the
    certificate, and report `:not_checked`.
  - `PartialCompliance` returns `res.vars` and `Rebound` returns `merge(res.vars, (; rebound_u))`.
    Both keep `p_ch`/`p_dch`, and `storage_kind` forwards through the wrapper type, so a
    wrapped V2G EV is selected and certified.
  - `OptOut` is `:none` with `vars = (;)`, so `:not_checked` is correct.
- **Exceptions.** `_certificate_status` (`price_taker.jl:51-60`) catches only
  `CertificateError` and rethrows anything else.
- **Guard ordering.**
  - `actors` is the first statement in both `compare_tariffs` (`comparison.jl:371`) and
    `clear_flex_market` (`flex_settle.jl:326`).
  - The W2 loop (`comparison.jl:396-401`) runs before any solve.
  - `_refuse_reactive_decision` runs right after `_refuse_fixed_capacitor` at all three sites,
    each before its first solve: `flex_clear.jl:225` and `:700`, and `comparison.jl:464`.
  - `_baseline_price`, the only call before `_flex_physics` in `clear_flex_market`, does not
    solve.
  - No other caller of `_stage2_aggregators` or `_redispatch` exists.
- **Byte-identity.**
  - Every consumer reads these records by field name: `comparison.jl:644, 731, 740, 1144,
    1200, 1228, 1263-1265, 1309`, `flex_settle.jl:142, 160, 212-213, 378`, and
    `docs/literate/settlement_equity.jl:89`.
  - No script calls `price_taker_dispatch`, `_deliver` or `clear_flex_market`.
  - No fence digest folds a physics record or a price-taker result: the
    `ActorFenceDigest` / `df_digest` / `ledger_digest` inputs are DataFrames, ledgers and
    ADMM/welfare results.
  - The key-set pins at `test_flex_market.jl:1212/1296/1410` cover the top-level physics
    keys, which are unchanged.
  - The default path adds only a no-op `actors === nothing` check and guard loops that pass
    the default populations.
- **@testitem scoping.** No `try x = ...` at item top level. No loop reassigns an outer
  variable: every loop-assigned name (`ra`, `e6`, `r7`, `agg9`, `ru`) is local to its loop
  body. Results are captured with `Ref` (`out[]`) or `M.caught`.

**What does not hold:** three Warnings, all in tests or user-facing text, and six Info items.
No Critical issues.

## Warnings

### WR-01: The compliant-clear test accepts every status, so the `physics.delivered` EV record can go untested without a failure

**File:** `test/test_flex_market.jl:1109-1119`
**Issue:**
- Line 1112 asserts `res.status in ("ok", "infeasible_redispatch", "inexact_redispatch") || startswith(res.status, "error:")`.
  That holds for every status `_physics_record` can emit except a thrown exception, so it is
  close to vacuous.
- The only check that `_dispatch_record` carries the EV fields into `physics.delivered` is
  conditional: line 1116 (`res.status == "ok" && @test ...`) and the `if` block below it.
- If a regression moves this fixture to `"inexact_redispatch"`, the test still passes, but it
  then asserts nothing about the delivered record. It is the only test of
  `physics.delivered.ev_*`, since the `_deliver` test checks the raw `_deliver` tuple, not
  `_dispatch_record`.
- 47-01-SUMMARY (Test K) records the measured status as `"ok"`, so a firm pin is available.
  The "do not pin `:ok`" correction in CONTEXT is about the EV certificate value on a
  flat-baseline clear, not about the clear status.

**Fix:** Pin the measured status and assert the delivered record unconditionally. Keep the EV
value in `(:ok, :refused)` as decided.
```julia
res = compliant_clear()
@test res.status == "ok"                      # measured (47-01 Test K)
@test res.physics.baseline !== nothing
@test ev_fields_ok(res.physics.baseline)
@test res.physics.delivered !== nothing
res.physics.delivered === nothing || @test ev_fields_ok(res.physics.delivered)
```

### WR-02: The SmartInverterPV + `flex_market` fence case is credited to the reactive-decision guard, but the fit-leg guard refuses it

**File:** `test/test_flex_market_fence.jl:394-397, 484-492`; `src/settlement/comparison.jl:345-349`
**Issue:**
- The W2 loop (`comparison.jl:396-401`) runs before the `flex_markets !== nothing` block
  (`:445-465`), and `_reject_unsupported_flex_devices` refuses `SmartInverterPV`. So in
  `compare_tariffs`, a `SmartInverterPV` never reaches `_refuse_reactive_decision`. That
  branch is unreachable for SIPV, and only `FourQuadBESS` exercises it.
- The test comment at `:484` says "with flex_market, a device with its own reactive decision
  is refused like the capacitor". But `r_sipv` (`:488-492`) asserts only
  `occursin("SmartInverterPV", msg)`, which the W2 message also satisfies. The test would pass
  unchanged if `_refuse_reactive_decision` were removed from `compare_tariffs`, so as a test of
  W3 it proves nothing.
  - 47-02-SUMMARY confirms this: "The SmartInverterPV case with `flex_market` already passed,
    because the Task 1 device guard refuses it".
- The `"smartinverterpv_flex"` entry in `cases` (`:394`) duplicates `"smartinverterpv"`
  (`:402`): both hit the same guard.
- The `compare_tariffs` docstring (`:345-349`) lists `SmartInverterPV` among the
  `flex_market`-only refusals, with the reason "stage 2 holds reactive power at the inelastic
  draw". A caller never sees that message for SIPV; they get the fit-leg message whether or
  not `flex_market` is set.

**Fix:** Make the test say what it exercises, and correct the docstring.
```julia
# SmartInverterPV is refused by the fit-leg device guard first (it runs before the
# flex_market block); only FourQuadBESS reaches the stage-2 reactive-decision guard here.
r_sipv = refused(g -> tight([unsupported[3][2]]; flex_market = FlexMarket(), welfare_optimizer = g))
@test r_sipv.n == 0
@test r_sipv.e isa ArgumentError && occursin("fit leg", r_sipv.e.msg)
@test r_sipv.e isa ArgumentError && !occursin("own reactive decision", r_sipv.e.msg)
```
- Drop the duplicate `"smartinverterpv_flex"` case, or keep it under the comment above.
- In the docstring, list only `FourQuadBESS` under the `flex_market` reactive refusal and note
  that `SmartInverterPV` is already refused by the fit-leg guard.

### WR-03: The new up-front W2 refusal surfaces a message whose remedy is wrong for `compare_tariffs`

**File:** `src/settlement/comparison.jl:396-401` (message text at `src/pricing/fit.jl:88-94`)
**Issue:**
- `compare_tariffs` now reaches `_reject_unsupported_flex_devices` directly. The caller is
  `"compare_tariffs (the fit leg runs fit_baseline / FIT-OPT)"`, so the user sees:

  > compare_tariffs (the fit leg runs fit_baseline / FIT-OPT) does not support the phase-43
  > flexible devices / phase-44 behavioural wrappers ... (build_population `flex_devices`
  > opt-in): they have no FIT-OPT / MPC model here. Use the day-ahead centralized/ADMM
  > strategies, or drop `flex_devices`.

- That message is inaccurate here in three ways:
  1. **The remedy.** "Use the day-ahead centralized/ADMM strategies" is no remedy: a
     `compare_tariffs` caller is already running `engine = :centralized` or `:admm`, and the
     fit leg is not optional. The working path for these populations is `solve_welfare` /
     `solve_admm` followed by `clear_flex_market`, which accepts EVs, HeatPumps and wrappers.
     The message never names it.
  2. **The source.** "drop `flex_devices`" is wrong for the wrappers, which come from
     `apply_behaviour`, not `build_population(...; flex_devices)`.
  3. **Planning IDs.** The message carries "phase-43" / "phase-44" into user-facing output.
     The line is not new, but this phase made it the first error `compare_tariffs` users see
     for these populations.

  The phase's own guard convention (CONTEXT, Established Patterns) requires a message that
  names the unsupported combination and why. This one names the combination but gives the
  wrong fix.

**Fix:** Keep the device set and the error type, as the decision requires, and make the
`compare_tariffs` message actionable. Either give `_reject_unsupported_flex_devices` an
optional `remedy` argument, or fold the remedy into the caller string.
```julia
fit_caller = "compare_tariffs (its fit leg runs fit_baseline / FIT-OPT, which has no model for these devices; " *
             "for them run solve_welfare / solve_admm and clear_flex_market directly)"
```
Remove "phase-43/phase-44" from the shared message in a follow-up, which is outside this
phase's file scope. Add it to the backlog todo if it is not done now.

## Info

### IN-01: FourQuadBESS populations get no co-charge certificate on the price-taker paths

**File:** `src/settlement/price_taker.jl:86-107`
**Issue:**
- `_storage_certificates` routes `:battery` and `:ev` only. A `FourQuadBESS` (`:four_quadrant`)
  reports `battery_certificate = :not_checked` and `ev_certificate = :not_checked`. That is
  honest, but no status records 4Q co-charge at all.
- W3 now keeps 4Q out of the flex paths, but the flat and TOU legs of `compare_tariffs`
  (`comparison.jl:727`) and direct `price_taker_dispatch` calls still dispatch 4Q populations
  uncertified, at any price, including negative ones.
- The behaviour predates this phase. This phase still wrote the docstring that defines
  `:not_checked` (`:132-137`), and that docstring does not say 4Q is never certified.

**Fix:** Add one sentence to the `price_taker_dispatch` docstring ("four-quadrant storage has
no certificate on this path"), or file a backlog item for a `fourq_certificate` that routes
to `complementarity_4q.jl`.

### IN-02: The rethrow branch of `_certificate_status` is untested

**File:** `src/settlement/price_taker.jl:51-60`
**Issue:**
- The "only `CertificateError` is caught" contract is correct in code. No test pins it, and
  no test pins `present == false ⇒ f never called` either.
- A future edit that widens the catch, for example to `err isa Exception`, would turn a
  genuine failure into `:refused` and pass every current test.

**Fix:** Add a tiny unit item.
```julia
@test TSODSO._certificate_status(() -> error("boom"), false) == (:not_checked, "")
@test_throws ErrorException TSODSO._certificate_status(() -> error("boom"), true)
@test TSODSO._certificate_status(() -> throw(CertificateError("x"; kind = :ev)), true) == (:refused, "x")
@test TSODSO._certificate_status(() -> 1.0, true) == (:ok, "")
```

### IN-03: The W3 predicate depends on an unpinned invariant

**File:** `src/coordination/flex_clear.jl:181`
**Issue:**
- `has_reactive_decision(d) && !is_flexible_load(d)` lets every flexible load through.
- That is correct only while no flexible load also returns its own `q_inject`. The only place
  this invariant is stated is a comment (`src/devices/Aggregator.jl:212-213`, "though no
  current device does").
- A future flexible load with a genuine reactive decision would be accepted silently in stage
  2, which drops its q. That is the exact failure W3 exists to prevent.

**Fix:** Add a test that, for each concrete `AbstractDevice` subtype with
`is_flexible_load == true`, `contribute!` on a scratch context returns no `:q_inject`.
Alternatively, introduce a dedicated `has_own_q_decision` trait (true for `SmartInverterPV`
and `FourQuadBESS`) and refuse on that.

### IN-04: `τ_ev` is not threaded alongside `τ_batt`, so the pairing rule silently breaks for a custom `τ_batt`

**File:** `src/coordination/flex_clear.jl:707, 771`; `src/coordination/flex_settle.jl:323`; `src/settlement/comparison.jl:359`
**Issue:**
- The stated rule (`price_taker.jl:76-80`) is that `TAU_EV_ADMM` applies because these paths
  take `τ_batt = 1e-3` from the ADMM consolidation.
- `clear_flex_market`, `_flex_physics`, `_shortfall_diagnostic` and `compare_tariffs` all
  accept and forward a caller `τ_batt`, but not `τ_ev`. A caller who tightens `τ_batt` gets
  a tighter battery certificate and an unchanged EV certificate, with no indication.
- Not threading `τ_ev` is a recorded decision (47-01 key-decisions), so this is Info only.
  The `TAU_EV_ADMM` reuse itself is not flagged.

**Fix:** Add one sentence to the `clear_flex_market` docstring: "the EV co-charge certificate
always runs at `TAU_EV_ADMM`; `τ_batt` does not change it". Or thread `τ_ev` the same way
`τ_batt` is threaded.

### IN-05: The docs page does not say that `compare_tariffs` refuses EV, HeatPump, SmartInverterPV and wrapper populations

**File:** `docs/literate/flex_market.jl:688-693`
**Issue:**
- The new section-12 bullets say the V2G EV certificate is reported separately on the
  baseline and the delivery.
- The page documents both `clear_flex_market` and `compare_tariffs(...; flex_market)`.
  After W2, `compare_tariffs` refuses any population with an EV, HeatPump, SmartInverterPV or
  behavioural wrapper before any solve. So the EV certificate is reachable only through
  `clear_flex_market` called directly.
- A reader of this page would expect EV flex rows from `compare_tariffs`.

**Fix:** Add to the EV bullet: "`compare_tariffs` refuses EV, HeatPump, SmartInverterPV and
behaviour-wrapped populations before any solve (its fit leg cannot model them); call
`clear_flex_market` directly for them."

### IN-06: Redundant test assertions

**File:** `test/test_flex_market.jl:1679-1681`
**Issue:** The status disjunction at `:1679` is subsumed by the pin `@test res.status == "ok"`
at `:1681` two lines later. The duplicated SIPV fence case is covered under WR-02.

**Fix:** Drop the disjunction at `:1679`.

---

_Reviewed: 2026-11-06_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
