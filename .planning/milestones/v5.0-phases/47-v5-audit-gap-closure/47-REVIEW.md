---
phase: 47-v5-audit-gap-closure
reviewed: 2026-11-07T02:53:15Z
depth: standard
iteration: 2
files_reviewed: 9
files_reviewed_list:
  - docs/literate/flex_market.jl
  - src/coordination/flex_clear.jl
  - src/coordination/flex_settle.jl
  - src/settlement/comparison.jl
  - src/settlement/price_taker.jl
  - src/pricing/fit.jl
  - test/test_flex_market.jl
  - test/test_flex_market_fence.jl
  - test/test_settlement.jl
findings:
  critical: 0
  warning: 0
  info: 9
  total: 9
status: issues_found
---

# Phase 47: Code Review Report (iteration 2)

**Reviewed:** 2026-11-07T02:53:15Z
**Depth:** standard (scope: `git diff 9e9b709..HEAD` on the nine files above; the fix commits are
e17250d, 554a1c3, 57f2e19 and dc21e9c)
**Files Reviewed:** 9
**Status:** issues_found (Info only)

## Narrative Findings (AI reviewer)

## Summary

All three iteration-1 Warnings are fixed correctly, and the fixes add no Critical or Warning issue.
Nine Info items remain:
- six carried from iteration 1, all still present in the tree;
- three new ones, all about wording or test strength.

**Checks run in this iteration (not taken from the fix report):**

- **Targeted fast tests.** `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl`
  gave 1564 pass, 0 fail, in 2m59.6s, on Julia 1.12.5.
  - The compliant clear logged `status = "ok"`.
  - `test/Project.toml` and `test/Manifest.toml` were restored afterwards, and the working tree is
    clean.
- **Formatter.** JuliaFormatter 2.10.2, the version CI pins, ran with the committed
  `.JuliaFormatter.toml` and `overwrite = false` on all nine files. Every file reports formatted, so
  the CI format check passes.

**WR-01 (fixed).** `test/test_flex_market.jl:1115` pins `res.status == "ok"`. The delivered
record's EV fields are now asserted unconditionally (`:1118-1119`).
- I checked that the pin does not indirectly pin the EV certificate value, which CONTEXT forbids:
  - In `_flex_physics` (`flex_clear.jl:700-800`), `status` comes only from solver outcomes:
    `_physics_error_status`, `rd.status` and `_congestion_status`.
  - Certificates are recorded inside `_certificate_status` and never change `status`.
  - So a `:refused` EV certificate still gives `"ok"`, and `ev_fields_ok` still accepts
    `(:ok, :refused)`. The pin is sound.

**WR-02 (fixed).**
- **The `compare_tariffs` case.** The comment at `test/test_flex_market_fence.jl:483-485` now
  states the real ordering. The asserts distinguish the two guards:
  - `r_sipv` must contain "fit leg" and must not contain "own reactive decision" (`:489-495`).
  - `e_4q` must contain "own reactive decision" (`:488`).
- **The phrases do not overlap.** The new W2 message says "whose reactive power its stage 2
  cannot represent", not "own reactive decision", so the negative assert is meaningful.
- **The new `clear_flex_market` case** (`:496-515`) reaches `_refuse_reactive_decision` for
  SmartInverterPV. Its `n == 0` check is weaker than its comment claims; see IN-08.
- **The duplicate case was dropped safely.** `cases[end - 2]` is still `lindistflow` and
  `cases[end - 1]` is still `zero_lambda0`.
- **The docstring** (`comparison.jl:349-354`) is now correct.

**WR-03 (fixed).** `compare_tariffs` builds its own message (`comparison.jl:404-419`). I checked
each of its claims against the code it names:

- **"every comparison runs it" (the fit leg): true.** Leg 4 (`comparison.jl:840-858`) is an
  unconditional `begin` block.
- **"clear_flex_market … refuses a SmartInverterPV": true.** `_refuse_reactive_decision`
  (`flex_clear.jl:177-192`) is reached from `_flex_physics:701`, before stage 1, and again from
  `_stage2_aggregators`. The predicate is `has_reactive_decision(d) && !is_flexible_load(d)`, and
  `has_reactive_decision(::SmartInverterPV) = true` (`SmartInverterPV.jl:89`).
- **"accepts electric vehicles, heat pumps and behaviour-wrapped devices": true at the guard
  level.**
  - No `clear_flex_market` or `_flex_physics` guard refuses these types.
  - `flex_bids.jl` has no device-type branch.
  - Wrappers forward `has_reactive_decision` (`CapabilityTraits.jl:44-46`), but
    `_beh_unwrappable` (`Behavioural.jl:39`) already refuses to wrap a SmartInverterPV,
    FourQuadBESS or FixedCapacitor. So no wrapped device trips the reactive guard.
  - EV clears are tested (`test_flex_market.jl:1052-1120`) and wrapper clears are tested
    (`:1665-1682`). HeatPump has no end-to-end clear test; see IN-07.
- **The `price_taker_dispatch` route: sound.** `select_optimizer(QP())` is Clarabel
  (`factory.jl:42`), which accepts the SmartInverterPV `SecondOrderCone`, and the function adds no
  device refusal of its own.
- **No planning IDs.** The fence asserts `!occursin(r"phase-?\d", msg)` (`:481`).
- **The new name `_fit_unsupported_device_names` exists only in `fit.jl` and `comparison.jl`.**
  No other test or doc pins the replaced caller string `"compare_tariffs (the fit leg runs …)"`.

**The shared device-list constant in `fit.jl`:**
- **Behaviour is unchanged.**
  - `_FitUnsupportedDevice` is the same six-type `Union`.
  - `_fit_unsupported_device_names` is the same `unique(nameof(typeof(d)) for d in devices if …)`
    generator, moved verbatim.
  - The three other callers keep their caller strings and their message:
    - `fit_baseline` via `_fit_pv_and_flex` (`fit.jl:124`);
    - `run_mpc` (`mpc_loop.jl:292`);
    - `build_stochastic_welfare` (`stochastic_welfare.jl:200`), which pre-filters to the wrapper
      subset and so is unaffected.
- **Load order is safe.** The `Union` moved from a function body to a top-level `const`, so its
  types must exist when `fit.jl` is included. They do: `FourQuadBESS.jl`, `ElectricVehicle.jl`,
  `HeatPump.jl`, `SmartInverterPV.jl` and `Behavioural.jl` are included at `TSODSO.jl:125-130`,
  before `pricing/fit.jl` at `:204`.

**The formatter rewrap of the `_reject_unsupported_flex_devices` docstring: harmless.**
- Line `fit.jl:83` now holds the whole code span `` `build_population(...; flex_devices = ...)` ``
  on one line of about 160 characters.
- Markdown turns a line break inside a code span into a space, so the rendered text is unchanged,
  and joining the span is if anything safer.
- The function is internal and is not in any `@docs` block.
- `format_docstrings = true` produces this output, and the file is idempotent under 2.10.2, so CI
  will not fight it.

## Info

### IN-01 (carried): FourQuadBESS populations get no co-charge certificate on the price-taker paths

**File:** `src/settlement/price_taker.jl:86-107` (docstring `:131-148`)
**Issue:**
- `_storage_certificates` routes only `:battery` and `:ev`. A `FourQuadBESS` (`:four_quadrant`)
  therefore reports `:not_checked` for both statuses.
- That is honest, but the flat and TOU legs and direct `price_taker_dispatch` calls dispatch 4Q
  uncertified. The `price_taker_dispatch` docstring does not say so.
- Unchanged since iteration 1.

**Fix:** Add "four-quadrant storage has no certificate on this path" to the docstring, or file a
backlog item for a `fourq_certificate` routed to `complementarity_4q.jl`.

### IN-02 (carried): The rethrow branch of `_certificate_status` is untested

**File:** `src/settlement/price_taker.jl:51-60`
**Issue:**
- No test calls `_certificate_status` directly; `grep` finds no hit under `test/`.
- So nothing pins two parts of its contract:
  - only `CertificateError` is caught;
  - `present == false` means `f` is never called.
- A widened `catch` would turn real failures into `:refused` and still pass every test.

**Fix:**
```julia
@test TSODSO._certificate_status(() -> error("boom"), false) == (:not_checked, "")
@test_throws ErrorException TSODSO._certificate_status(() -> error("boom"), true)
@test TSODSO._certificate_status(() -> throw(CertificateError("x"; kind = :ev)), true) == (:refused, "x")
@test TSODSO._certificate_status(() -> 1.0, true) == (:ok, "")
```

### IN-03 (carried): The W3 predicate depends on an unpinned invariant

**File:** `src/coordination/flex_clear.jl:181`
**Issue:**
- `has_reactive_decision(d) && !is_flexible_load(d)` passes every flexible load.
- That is correct only while no flexible load returns its own `q_inject`, and that invariant is
  stated only in a comment (`src/devices/Aggregator.jl:212-213`).

**Fix:** Add a test that every concrete `AbstractDevice` with `is_flexible_load == true` returns no
`:q_inject` from `contribute!`. Alternatively, refuse on a dedicated `has_own_q_decision` trait.

### IN-04 (carried): `τ_ev` is not threaded alongside `τ_batt`

**File:** `src/coordination/flex_clear.jl:494-498, 707, 771`; `src/coordination/flex_settle.jl:323`; `src/settlement/comparison.jl:364`
**Issue:**
- A caller `τ_batt` reaches the battery certificate on stage 1, the delivery and the 10w
  diagnostic.
- The EV certificate always runs at `TAU_EV_ADMM`, and no docstring says so.
- Not threading `τ_ev` is a recorded decision, and the `TAU_EV_ADMM` reuse itself is not flagged.

**Fix:** Add one sentence to the `clear_flex_market` and `compare_tariffs` docstrings: "the EV
co-charge certificate always runs at `TAU_EV_ADMM`; `τ_batt` does not change it".

### IN-05 (carried): The docs page does not say that `compare_tariffs` refuses EV, HeatPump, SmartInverterPV and wrapper populations

**File:** `docs/literate/flex_market.jl:690-693`
**Issue:**
- The section-12 EV bullet implies that EV rows can come from `compare_tariffs(...; flex_market)`.
- After W2 they cannot: the EV certificate is reachable only through `clear_flex_market` called
  directly.
- The file is unchanged by the fix commits.

**Fix:** Append to the EV bullet: "`compare_tariffs` refuses EV, HeatPump, SmartInverterPV and
behaviour-wrapped populations before any solve (its fit leg cannot model them); call
`clear_flex_market` directly for them."

### IN-06 (carried): Redundant status disjunction in the wrapper-clear test

**File:** `test/test_flex_market.jl:1679-1681`
**Issue:** The disjunction at `:1679-1680` is subsumed by `@test res.status == "ok"` at `:1681`.
This is the same pattern WR-01 removed at `:1112`.

**Fix:** Drop the disjunction at `:1679-1680`.

### IN-07 (new): The new `compare_tariffs` message names only SmartInverterPV among `clear_flex_market`'s refusals

**File:** `src/settlement/comparison.jl:404-419`
**Issue:**
- The message says "For this population, … call price_taker_dispatch … or clear_flex_market …
  directly", then lists SmartInverterPV as the one device `clear_flex_market` refuses.
- The message is built from the fit-unsupported devices only. `clear_flex_market` also refuses
  `FourQuadBESS` and `FixedCapacitor` (`flex_clear.jl:159-192`).
  - So a hand-built population holding an EV next to a FourQuadBESS is sent to
    `clear_flex_market`, which then refuses it.
  - The second refusal is loud and comes before any solve, so no result is wrong; the user only
    finds the refusals one at a time.
  - Default populations are not affected: `FixedCapacitor` appears only in the IEEE-8500 branch of
    `build_population` (`materialize.jl:1219`).
- Separately, "accepts … heat pumps" holds at the guard level, but no test runs a
  `clear_flex_market` with a HeatPump end to end. EVs and wrappers both have tests.

**Fix:** Make the last sentence read "…but refuses a SmartInverterPV or FourQuadBESS (whose
reactive power its stage 2 cannot represent) and a FixedCapacitor". Optionally, add a small
HeatPump clear to `test_flex_market.jl` that asserts no `ArgumentError`, the status reached and
`ledger_residual == 0.0`.

### IN-08 (new): The new fence case's `n == 0` does not show "before any solve"

**File:** `test/test_flex_market_fence.jl:496-511`
**Issue:**
- The comment says SmartInverterPV reaches the stage-2 guard "before any solve", and the proof
  offered is `r_sipv_clear.n == 0`.
- The counting factory is passed as `optimizer`, which only the stage-2 redispatch uses. Stage 1
  (`price_taker_dispatches`) and the delivery build `Model(select_optimizer(QP()))` themselves.
- So if the `_flex_physics` guard were removed, stage 1 would solve and `_stage2_aggregators`
  would still refuse before the redispatch. `n` would stay 0 and the test would still pass.
- The early-site ordering is pinned elsewhere, by the counting-device test at
  `test_flex_market.jl:1722-1764` (`calls == 0`). So this is redundant, not a coverage hole.

**Fix:** Pin the site in the message instead of relying on `n`:
```julia
@test r_sipv_clear.e isa ArgumentError && startswith(r_sipv_clear.e.msg, "_flex_physics:")
```
Or reword the comment to "refused by the stage-2 reactive-decision guard".

### IN-09 (new, backlog): The shared `fit_baseline` / `run_mpc` / stochastic message still carries planning IDs and a remedy that is wrong for wrappers

**File:** `src/pricing/fit.jl:93-96` (and the docstring at `:82-83`)
**Issue:**
- `compare_tariffs` no longer surfaces this message. `fit_baseline`, `run_mpc` and
  `build_stochastic_welfare` still do, unchanged in this phase.
- The message says "phase-43 flexible devices / phase-44 behavioural wrappers".
- Its "drop `flex_devices`" remedy is wrong for wrappers, which come from `apply_behaviour`.
- This is pre-existing and was deliberately left out of this phase.

**Fix:** Track it in the backlog todo. When it is done, drop the planning IDs and name
`apply_behaviour` as the source of the wrappers.

---

_Reviewed: 2026-11-07T02:53:15Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_
