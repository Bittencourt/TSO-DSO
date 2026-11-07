---
phase: 45-flexibility-market-vs-price-coordination
reviewed: 2026-11-05T05:22:50Z
depth: standard
iteration: 2
files_reviewed: 11
files_reviewed_list:
  - src/coordination/flex_bids.jl
  - src/coordination/flex_clear.jl
  - src/coordination/flex_settle.jl
  - src/coordination/coordination.jl
  - src/settlement/comparison.jl
  - scripts/tariff_comparison.jl
  - docs/literate/flex_market.jl
  - test/test_flex_market.jl
  - test/test_flex_market_ieee.jl
  - test/test_flex_market_ieee123.jl
  - test/test_flex_market_fence.jl
findings:
  critical: 0
  warning: 4
  info: 12
  total: 16
status: issues_found
---

# Phase 45: Code Review Report (iteration 2)

**Reviewed:** 2026-11-05T05:22:50Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This is a re-review of the fix commits `107c4a9..5266d96` (`git log c78d9b1..HEAD`), checked
against the iteration-1 findings CR-01, WR-01 to WR-06 and IN-04, followed by a standard pass
over the changed code. I did not run Julia. Everything below comes from reading the code, the
diffs and the committed CSVs. `flex_bids.jl` and `coordination.jl` did not change in this
range; I read them only to check their callers.

**The iteration-1 findings are resolved, and none of the fixes broke anything that was
working.** I found no new BLOCKER. Three of the four new warnings are about how robust the
new tests and guards are. The fourth is a hole that WR-04 left in the script's
`--record-timeout` path.

| Iter-1 ID | Verdict | Notes |
|---|---|---|
| CR-01 | Resolved | `_flex_physics` (`flex_clear.jl:646-666`) and the `compare_tariffs` flex block (`comparison.jl:414-435`) refuse the conditions below with `ArgumentError` before stage 1 and before the DADP run. `clear_flex_market` gets the same protection through `_flex_physics`: before it, only `_baseline_price` runs, and that is not a solve. A split reconstruction failure is now `"error:dlmp_split"` (`:709-717`). The fence tests pin 0 optimizer calls. The status mapping depends on the error message text, see WR-01. |
| WR-01 | Resolved | `clear_flex_market` uses `agg_buses == input.buses` (`flex_settle.jl:321`). `_flex_physics` and `compare_tariffs` check `issorted` before any solve. |
| WR-02 | Resolved | Each row is now compared as a tuple against the accepted block it books, so the weak price check is gone. The quantity and money invariants are asserted, but the money equality depends on summation order, see WR-03. |
| WR-03 | Resolved | The "exact penalty" guarantee has been removed from the `_deliver` and `_flex_physics` docstrings and from docs section 8. The new upper-bound claim is **true**, under qualifiers the text leaves out (IN-09). |
| WR-04 | Resolved, with a residual | `purge_rows` deletes only rows the run regenerated or deliberately replaced, on every path that can be invoked. The one way to record a killed `--flex-market` ieee13-ground run deletes base rows it never re-ran, see WR-04. |
| WR-05 | Resolved | The DADP solve runs on its own, and only a `SolveFailedError` or a `CertificateError` with kind `:socp_exact` counts as a refusal. `compare_tariffs` runs outside any `try`. The refused branch checks that `compare_tariffs` throws the same error type. |
| WR-06 | Resolved in code | `_shortfall_diagnostic` is separate from the primary delivery, and the clear stays `"ok"` with notes and a `missing` value. The new test forces the failure through solver numerics, see WR-02. |
| IN-04 | Resolved | `_refuse_fixed_capacitor(aggs, "compare_tariffs")` (`comparison.jl:435`). |

**The specific properties you asked about:**

- **Default path untouched when `flex_market = nothing`.** Confirmed. In `compare_tariffs`,
  every new line sits inside `if flex_markets !== nothing` (`comparison.jl:407-436`). The only
  other edit to that file is the docstring. The fence item still runs `LinDistFlow` without
  `flex_market` and gets the four legs (`test_flex_market_fence.jl:431-440`). The non-flex
  path still accepts a zero λ₀, but no test covers that case.
- **New guards fire before any solve.** Confirmed for `compare_tariffs` (before the DADP
  `solve_welfare`), `_flex_physics` (before `price_taker_dispatches`) and `clear_flex_market`
  (only `_baseline_price` runs first, which is a price computation).
  - The λ₀ > 0 guard also keeps the tracking weight positive. This prevents a late
    `ArgumentError` from `_deliver`'s `weight > 0` check.
  - The `MeshedFeeder` case is still refused early: `ConvexBranchFlow` rejects it when the
    DADP model is built.
- **WR-04 cannot delete base rows that were not re-run on any path that can be invoked:**
  - `ground_flex_main` purges only `flex_` rows, and only after `assert_dadp_reproduces`
    passes.
  - `ground_main` deletes the flex rows only when the provenance check fails or the run is
    refused.
  - The IEEE-123 modes, `case-a-784` and `--record-timeout` own all rows of the mode.
  - Combining timeout with flex on ieee13-ground is refused.

  The gap is the workaround that refusal leaves the operator: see WR-04.
- **The WR-03 "upper bound" claim.** This is true for the **total** L1 shortfall, at exact
  optima.
  - **Why it holds.** At exact optima, the two delivery problems at `w` and at `w' > w` have
    the same feasible set. Adding their two optimality inequalities gives
    `(w' − w)(S(w) − S(w')) ≥ 0`, so the shortfall never increases as the weight grows.
    Separately, any feasible dispatch's shortfall upper-bounds the minimum reachable
    shortfall.
  - **Where it does not hold.** It does not apply to `delivery_shortfall_max` or to the
    per-hour rebound shortfall. It is relative to the relaxed battery model, so it only
    describes physics when the delivered battery certificates are `:ok`. They are `:ok` on
    every committed flex row: IEEE-13 `batt_ok = 10`, IEEE-123 `batt_ok = 85`. See IN-09.
- **The WR-06 test (w = 1e300).** This is not robust. It depends on what Clarabel happens to
  do with a cost of 1e300: today it returns `NUMERICAL_ERROR`. See WR-02.

## Warnings

### WR-01: The `"error:dlmp_split"` mapping depends on the error message prefix, and the test pins a made-up message, so changing the wording in `dlmp.jl` would silently undo CR-01

**File:** `src/coordination/flex_clear.jl:511-516`; `src/pricing/dlmp.jl:204, 412`; `test/test_flex_market.jl:1108-1119`

**Issue:** `_congestion_status` decides between "status" and "rethrow" with
`err isa ErrorException && startswith(err.msg, "decompose_dlmp:")`. That has two problems.

1. **Fragile coupling.** The decision depends on the prose of an `error(...)` call in another
   file. If someone rewords the message at `dlmp.jl:412`, or the repo's own content passes
   switch it to a typed error, the reconstruction failure stops matching. It is then
   rethrown after the DADP run, all base legs, stage 1, the probes and stage 2. That is
   exactly the CR-01 failure. The unit test builds its own
   `ErrorException("decompose_dlmp: four-way split ...")` (`test_flex_market.jl:1110`), so
   it stays green after such a change. No test checks that the real `decompose_dlmp` failure
   produces a message the mapper accepts.
2. **It matches more than intended.** The same prefix is on the radial-topology error at
   `dlmp.jl:204` ("bus $cur has no parent branch"), which is a malformed input, not a solver
   outcome. Today that error cannot be reached, because `ConvexBranchFlow` refuses a
   `MeshedFeeder` when the model is built. If it ever is reached, it would be recorded as a
   reconstruction failure, which goes against the file's HONESTY rule that a malformed input
   still throws.

**Fix:** share one constant between the thrower and the mapper, and match on it exactly. A
typed error is better still.

```julia
# src/pricing/dlmp.jl
const _DLMP_RECON_FAIL = "decompose_dlmp: four-way split does NOT reconstruct the nodal DADP"
worst_res <= tol || error(_DLMP_RECON_FAIL * " — worst residual ...")

# src/coordination/flex_clear.jl
if err isa ErrorException && startswith(err.msg, _DLMP_RECON_FAIL)
```

In the test, build the message from `TSODSO._DLMP_RECON_FAIL` rather than a literal. Also
assert that the radial-topology message is **not** mapped.

### WR-02: The WR-06 test forces the diagnostic to fail through Clarabel's numerics at w = 1e300, and the integration path is never exercised

**File:** `test/test_flex_market.jl:1037-1054`; `src/coordination/flex_clear.jl:475-489, 753-768`

**Issue:** `bad = redeliver(1e300, ph1.targets)` expects `(missing, note)`. That only holds
if Clarabel, given an objective coefficient of 1e300, ends in a status that
`assert_solved!` rejects. The fix report measured `NUMERICAL_ERROR` on the current version.
The test asserts nothing about what `_shortfall_diagnostic` does; it asserts how the solver
behaves on data it cannot represent. There are two ways it can break.

- **Clarabel throws.** A version that validates its data, or a factorization path that
  raises a Julia exception (`DomainError`, `PosDefException`), would make
  `_shortfall_diagnostic` rethrow. The test would then *error*.
- **Clarabel succeeds.** A version that rescales the cost differently could converge, so
  `bad[1]` would be a number and the test would *fail*.

In both cases the code under test is unchanged.

The path that matters in production is also never tested: `_flex_physics` returning
`status == "ok"` with a non-empty `notes` and `shortfall_10w_total === missing`, and that row
reaching `_flex_tables` with `delivery_shortfall_total_10w = missing`.

**Fix:** inject the failure deterministically. Add a test-only device to the fixture module
and drive it through both the diagnostic and `_flex_physics`:

```julia
struct FailingDev <: TSODSO.AbstractDevice end
TSODSO.contribute!(::FailingDev, ctx::TSODSO.ModelContext; T::Int, kwargs...) =
    throw(TSODSO.SolveFailedError("injected diagnostic failure"))
# or, if you want a real solver outcome: add `x >= 1` and `x <= 0`, which is INFEASIBLE on
# any solver
```

Then assert `(missing, note)` from `_shortfall_diagnostic([agg_with_failing_dev], ...)`.
Keep the 1e300 case, if at all, as an `@info` probe rather than an assertion.

### WR-03: The pay-as-bid money check uses exact equality across two different summation orders, and the quantity tolerance is an absolute value below one ulp

**File:** `test/test_flex_market.jl:1258`, `:333`, `:1256`; `src/coordination/flex_settle.jl:117-136`

**Issue:**

- **Money.** Production sums `price·quantity` row by row in hour-major order, alternating
  each hour's up blocks with its down blocks (`flex_settle.jl:133-136`). The test computes
  `sum(fb.up_m .* pu) - sum(fb.dn_g .* pw)`: a column-major sum of all up products, a
  separate sum of all down products, then a subtraction. Floating-point addition is not
  associative, so `==` holds on the three measured seeds by coincidence, not because of the
  invariant. A change in fixture data, or solver noise in the rejected blocks (about 1e-9,
  booked as-is), can produce a one-ulp difference and fail a correct implementation.
- **Quantities.** The same applies to `TOL_PAB_Q = 8.33e-17`. That is 3 × 2.78e-17, which is
  one ulp at |Δ| ≈ 0.2. One ulp at |Δ| ≈ 1 is 2.2e-16, so a fixture with a larger activation
  fails the check without any bug.

**Fix:**

- Compute the expected money in production order, so `==` is justified:

  ```julia
  expect = 0.0
  for t in axes(pu, 1)
      for k in axes(pu, 2); pu[t, k] != 0 && (expect += fb.up_m[t, k] * pu[t, k]); end
      for k in axes(pw, 2); pw[t, k] != 0 && (expect += fb.dn_g[t, k] * -pw[t, k]); end
  end
  @test p.flex_payments_total == expect
  ```

- Scale the quantity check by magnitude, for example
  `gap <= 4 * eps() * max(1.0, maximum(abs, Δ))`, and record the measured ratio in the
  tolerance table.

### WR-04: A killed `ieee13-ground --flex-market` run can only be recorded by deleting the certified base rows it never re-ran

**File:** `scripts/tariff_comparison.jl:1069-1078`, `:1198-1208`, header `:22-27`

**Issue:** `--record-timeout` together with `--flex-market` is refused on ieee13-ground. The
refusal message says that is because "a timeout row would purge the base rows it never
re-ran". But the operator whose flex run was stopped has only one other option:
`--mode ieee13-ground --record-timeout S` without the flag. `record_timeout_main` then runs
`purge_rows("ieee13-ground", seed, T_H)` with the default all-rows predicate (`:1072`).

- **Data deleted.** That removes the certified dadp, flat, TOU and FIT rows, their bill and
  breakout rows, and every flex row. None of these were touched by the killed run, which
  writes only flex rows (`ground_flex_main`).
- **False record.** It then writes a `(run)` timeout row that claims the **base** run timed
  out.

So the guard blocks one invocation, and the only alternative the script offers produces the
data loss the guard was meant to prevent, plus a misattributed timeout. The header (`:22-27`)
does not say how to record a flex-only timeout.

**Fix:** give the ieee13-ground flex path a scoped timeout record instead of refusing it:

```julia
if parsed.record_timeout !== nothing && parsed.mode == "ieee13-ground" && parsed.flex_market
    purge_rows("ieee13-ground", seed, T_H; tariff = isflex_tariff)  # base rows untouched
    write_run_status_row(outcome, "ieee13-ground", "centralized", T_H, seed;
                         run_wall_s = S, tariff = "flex_(run)")   # flex-scoped status row
```

Teach `no_stale_rows` (`test_flex_market_ieee.jl:115-129`) that `flex_(run)` excludes
`flex_` leg rows only.

Alternatively, keep the refusal but make plain `--record-timeout` on ieee13-ground
non-destructive when a reproducing dadp row is committed: refuse, and name the two choices.

## Info

### IN-09: The WR-03 upper-bound wording needs its qualifiers

**File:** `docs/literate/flex_market.jl:461-463`, `:641-644`; `src/coordination/flex_clear.jl:599-606`

The claim that "the value at `w` is an upper bound on the hour-separability loss" is correct
for the **total** L1 shortfall, and for each aggregator's total, at exact optima of the
modelled delivery QP. Three qualifiers are missing.

- **Totals only.** The bound does not hold for `delivery_shortfall_max` (printed in the same
  line, `:483`) or for the per-hour `rebound_hourly.delivery_shortfall`. One hour's shortfall
  can rise while the total falls.
- **Relaxed batteries.** The bound is relative to the relaxed battery model. With a
  `:refused` delivered certificate, the physical loss can exceed the reported shortfall. All
  committed delivered certificates are `:ok`, so the committed numbers stand.
- **Solver tolerance.** "Does not increase" holds only up to solver tolerance. The committed
  10w changes (−1.46e-8 and −2.38e-7) are at that noise level.

State these qualifiers in one clause.

### IN-10: The ownership rules are partly undocumented, and a documented invocation now breaks the CSV test

**File:** `scripts/tariff_comparison.jl:12`, `:656-661`; `docs/literate/flex_market.jl:658-661`; `test/test_flex_market_ieee.jl:94-108`

- **Base-only IEEE-123 runs.** The header documents `--mode ieee123 [--flex-market]`. A
  base-only `ieee123` run now purges the flex rows (by design), which leaves
  `t123 == {dadp, flat, tou, fit}`. The fast CSV item rejects that table. Say in the header
  that the committed `ieee123` artifact must be recorded with `--flex-market`.
- **Misleading message.** On the first run of a seed, or after a recorded refusal,
  `ground_main` prints "the in-run dadp row does not reproduce the committed one". The actual
  reason is "no committed dadp row", which `chk.reason` holds and the script drops. Print
  `chk.reason`.
- **Incomplete docs summary.** The docs page (`:659-660`) lists the ownership rules for the
  IEEE-123 modes and the ieee13-ground flex path only. The default ieee13-ground rule is
  missing.

### IN-11: Purging before writing is not atomic

**File:** `scripts/tariff_comparison.jl:963`, `:1162`, `:661`

`purge_rows` rewrites each table before `write_compare_results` upserts the new rows one at
a time, each upsert being a full CSV read and write. A kill in that window leaves the mode
with rows deleted and only some rewritten, and with no `(run)` row. The script header calls a
kill a "measured outcome". The data can be recovered from git, but you could instead build
the purged and new tables in memory and write each file once.

### IN-12: Small quality items in the fix diffs

- **Overlong docstring line.** `src/coordination/flex_clear.jl:606` is 117 characters
  against `margin = 92`. The formatter does not reflow prose.
- **Positional case lookup.** `test/test_flex_market_fence.jl:427, 429` look up cases with
  `cases[end - 2]` and `cases[end - 1]`. Appending a case shifts these lookups. The message
  checks would then fail loudly rather than silently, but looking the case up by its label is
  clearer.

### IN-13: A `"error:dlmp_split"` record discards stage-2 results that were already computed

**File:** `src/coordination/flex_clear.jl:709-717`

On a split failure the record is built from `known...` only. `u`, `w`, `Δ`, `π`, `maxgap`
and `max_wash` have been computed but are returned as `nothing`, while the docstring says
"the fields that were not computed are `nothing`". Pass `stage2`-style fields, without the
congestion fields, so the failing clear can be diagnosed.

### Carried forward from iteration 1 (still open, unchanged in this range)

- **IN-01:** near-infeasible termination codes are not mapped to `infeasible_redispatch`
  (`flex_clear.jl:219-229`).
- **IN-02:** `FLEX_RANGE_FLOOR` is reused for three different thresholds.
- **IN-03:** a failed baseline `V0` solve offers zero flexibility without changing the status
  (`flex_bids.jl`).
- **IN-05:** tautological assertions in `test/test_flex_market.jl`.
- **IN-06:** the literate page `Core.eval`s the script's text layout.
- **IN-07:** the `π` local and record field shadow `Base.π`.
- **IN-08:** the refused IEEE-13 stage-1 battery certificates are not stated in the docs.

The full text of each is in `45-REVIEW.iter1.md`. IN-04 is resolved.

---

_Reviewed: 2026-11-05T05:22:50Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_
