---
phase: 45-flexibility-market-vs-price-coordination
reviewed: 2026-11-05T06:05:53Z
depth: standard
iteration: 3
files_reviewed: 8
files_reviewed_list:
  - src/pricing/dlmp.jl
  - src/coordination/flex_clear.jl
  - src/coordination/flex_settle.jl
  - src/settlement/comparison.jl
  - scripts/tariff_comparison.jl
  - docs/literate/flex_market.jl
  - test/test_flex_market.jl
  - test/test_flex_market_ieee.jl
findings:
  critical: 0
  warning: 1
  info: 13
  total: 14
status: issues_found
---

# Phase 45: Code Review Report (iteration 3, final)

**Reviewed:** 2026-11-05T06:05:53Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

This re-review covers the fix commits `3fa053e..3e96fd4` (`git log 5258235..HEAD`). I checked
each one against the iteration-2 findings WR-01 to WR-04, IN-09 and IN-10, then did a standard
pass over the changed lines only. I did not run Julia. Everything below comes from reading the
diffs, the current files and the committed CSVs.

- `flex_settle.jl`, `comparison.jl`, `test_flex_market_fence.jl` and `results/` did not change
  in this range (`git diff --stat 5258235..HEAD` is empty for them). I read `flex_settle.jl`
  only to check the order in which the payment rows are booked.

**All six iteration-2 findings are resolved, and I found no new BLOCKER.** I found one new
warning: `src/pricing/dlmp.jl` changes the exception type of an exported function, which goes
against the constraint you set for that file.

| Iter-2 ID | Verdict | Notes |
|---|---|---|
| WR-01 | Resolved, with one new warning | `_congestion_status` now matches `startswith(err.msg, _DLMP_RECON_FAIL)` (`flex_clear.jl:514`). The test gets the failure from the real `decompose_dlmp` on a real gated stage-2 context (`test_flex_market.jl:1194-1200`), so rewording the message now fails a test. The tree error is no longer mapped. As a side effect, the tree error's type changed, see WR-01 below. |
| WR-02 | Resolved | The 1e300 assertion is gone. `FailAtCall` injects a `SolveFailedError` deterministically, on a chosen `contribute!` call. It covers three levels: the diagnostic unit, `_flex_physics` (the diagnostic fails and the status stays `ok`; the primary delivery fails and gives `delivery:`), and `_flex_tables` (the table row). The seam is robust, see below. |
| WR-03 | Resolved | `tuple_money(expect_rows)` sums in the same order as `_flex_payment_rows` (`flex_settle.jl:111-136`): by bus, then hour, then up blocks, then down blocks. The rows are asserted tuple-equal to `expect_rows` first, so `==` holds by construction. The quantity check is now scaled by `Σ|q|` of the hour (`pab_quantity_relgap`). A gap with no rows correctly gives `Inf`. |
| WR-04 | Resolved | `--record-timeout S --flex-market` on ieee13-ground goes to `record_flex_timeout_main` (`tariff_comparison.jl:1111-1145`). It refuses before any write when there is no committed dadp row, deletes only the rows matching `isflex_tariff`, and writes a single `flex_(run)` row. The base rows cannot be deleted on this path, see below. |
| IN-09 | Resolved | All three qualifiers are now in the docstring (`flex_clear.jl:608-611`), in docs section 8 (`flex_market.jl:462-469`) and in the limitations bullet (`:648-650`). I checked the CSV claim: every `ok` flex row has `batt_refused = 0` (IEEE-13 `batt_ok = 10`, IEEE-123 `batt_ok = 85`). |
| IN-10 | Resolved | The script header now states the ieee123 recording rule (`:73-76`). `ground_main` prints `chk.reason` (`:676-682`). Moving the advice into its own field keeps the thrown text the same: before, the advice was part of `reason`; now `reason * advice` gives the same string. Docs section 13 lists all four ownership rules (`flex_market.jl:665-675`). |

**The checks you asked for:**

- **`src/pricing/dlmp.jl`, default behaviour and messages.**
  - **The reconstruction-failure message is byte-identical.** The old literal
    `"decompose_dlmp: four-way split does NOT reconstruct the nodal DADP — worst residual "`
    is now `_DLMP_RECON_FAIL * " — worst residual "`. The rest of the message is unchanged,
    the thrown type is still `ErrorException`, and the default `rtol = 1e-5, atol = 1e-7` and
    the control flow are untouched.
  - **No existing test matches either message.** Outside `test_flex_market.jl`, I searched
    `test/`, `docs/`, `scripts/` and `src/` for "does NOT reconstruct", "four-way split ...
    nodal", "no parent branch" and "radial tree". The only other hit is an unrelated comment
    in `test_ieee13.jl:22`.
  - **No `@test_throws` targets `decompose_dlmp`.** The only `@test_throws` in the DLMP tests
    is `ArgumentError extract_dlmp(ctx)` (`test_pricing_dlmp.jl:91`).
  - **The error types are not all unchanged.** `_path_branches` now throws `ArgumentError`
    where it used to throw `ErrorException`. `decompose_dlmp` is exported, so this is a change
    to its exception contract, and it goes against the stated constraint. See WR-01.
- **WR-04: the `flex_(run)` timeout path never deletes base rows.** Confirmed.
  - **What it deletes.** The only delete is `purge_rows(...; tariff = isflex_tariff)`, i.e.
    rows whose tariff starts with `"flex_"`. No base tariff (`dadp`, `flat`, `tou`, `fit`,
    `(run)`) matches that prefix, in any of the four tables.
  - **The refusal writes nothing.** The `ArgumentError` for a missing dadp row fires before
    `ensure_all_schemas` and before the purge.
  - **Later runs.** The `flex_(run)` row behaves like any other flex row:
    - a default ieee13-ground run that reproduces the committed dadp row keeps it;
    - a stale or refused base run deletes it;
    - a later `--flex-market` run deletes it.

    A `flex_(run)` row can never be left without the dadp row it was recorded against.
  - **The plain `--record-timeout`** still owns every row of the mode. That matches the
    header, the README and docs section 13.
  - **The committed-CSV test.** It accepts either the 8 legs or only `flex_(run)`, never a
    mix. The four synthetic checks exercise both the accept case and the reject cases.
  - **The docs page** reads flex rows through `find_row(mode, "flex_uniform")`, which returns
    `nothing` when the row is absent. A table holding only `flex_(run)` therefore does not
    break the page.
- **The `FailAtCall` test seam is robust.** The things that make it so:
  - **Calls are counted in a fresh counter.** `failing_agg` creates a new `Ref(0)` on every
    call, so no state leaks between tests.
  - **`fail_at = 0` can never fire,** because the counter is incremented before it is
    compared.
  - **The clear is single-threaded.** No `Threads`, `@spawn` or `pmap` appears in
    `src/coordination/`, so the call order is deterministic.
  - **The injected failure is caught where a real one would be.** The throw happens at model
    build time, inside the same `try` blocks that catch a real `assert_solved!` failure.
  - **The wrapper is transparent.** The dry run reproduces the plain clear exactly: `net`,
    `shortfall_total` and `shortfall_10w_total` are compared with `==`.
  - **A wrong position fails loudly.** The two positions are "last call = the diagnostic" and
    "the call before it = the primary delivery". If either were wrong, the `notes` prefix
    assertions would fail; they would not silently pass.
  - **Why the positions are right.** `_flex_physics` makes no device call after
    `_shortfall_diagnostic` (`flex_clear.jl:758-767`). With one aggregator holding one device,
    the primary delivery and the diagnostic are exactly one `contribute!` call each.
  - **No ambiguity or piracy risk.** No other trait dispatches on the concrete device type in
    the flex path: the only `isa` check in `src/coordination/` is the FixedCapacitor guard,
    and `storage_kind` falls back to `:none`, which is correct for Interruptible.

  The remaining fragilities are minor and listed as IN-15.

## Warnings

### WR-01: `dlmp.jl` changes the exception type of the exported `decompose_dlmp` on the tree-walk path, against the "error types unchanged" constraint, and the change was not needed for the fix

**File:** `src/pricing/dlmp.jl:204-209`

**Issue:** Commit `3fa053e` changed `_path_branches` from `error("decompose_dlmp: bus $cur has
no parent branch …")` (an `ErrorException`) to `throw(ArgumentError(...))`. `_path_branches`
is called from `decompose_dlmp` (`dlmp.jl:390`), which is exported. So any caller of
`decompose_dlmp` that hits this path now gets a different exception type.

- **Why it matters.** Code that classifies with `_is_solver_failure(e) = e isa ErrorException
  || e isa TSODSOError` (`src/core/errors.jl:121`) treated the old error as a solver failure.
  It now rethrows the new one.
- **Why there is no runtime regression today.** `ConvexBranchFlow` refuses a `MeshedFeeder`
  when it builds the model (`ConvexBranchFlow.jl:214-217`), so this path cannot be reached
  through the public API. No current caller wraps `decompose_dlmp` in such a `try`: the
  planning code that uses `_is_solver_failure` never calls it. No test pins the old type.
- **Why this is still a finding.** You stated that this file's error types for other callers
  must be unchanged. The fix report describes the change as only "The radial-tree misuse is
  now a thrown `ArgumentError`", and the `decompose_dlmp` docstring (`:316-319`) does not
  mention it.
- **The change was not needed.** The new mapper matches the exact
  `_DLMP_RECON_FAIL` prefix, `"decompose_dlmp: four-way split does NOT reconstruct …"`. The
  tree message `"decompose_dlmp: bus … has no parent branch"` would not match that prefix
  whatever its type, and the test's tree-error assertion would still pass on an
  `ErrorException`.

**Fix:** pick one of these.

1. **Revert the type change.** This keeps the contract and loses nothing for WR-01:

   ```julia
   haskey(child_branch, cur) || error(
       "decompose_dlmp: bus $cur has no parent branch — feeder is not the expected " *
       "radial tree",
   )
   ```

   In `test_flex_market.jl:1205`, assert `e_tree isa ErrorException` and keep
   `_congestion_status(e_tree) === nothing`. That still shows the mapper rejects every
   `"decompose_dlmp:"` message other than the reconstruction failure. Also change the
   `flex_clear.jl:509-511` comment from "both `ArgumentError`" to "a malformed tree
   (`ErrorException`) or a missing handle (`ArgumentError`)".

2. **Keep `ArgumentError` as a deliberate contract change.** Approve it explicitly. Then add a
   sentence to the `decompose_dlmp` docstring ("throws `ArgumentError` on a feeder that is not
   a radial tree rooted at `feeder.root`"), and list it in the fix report as a change outside
   the phase's own files.

## Info

### IN-14: The WR-01 forcing seam assumes `decompose_dlmp` never validates its tolerances

**File:** `test/test_flex_market.jl:1194-1195`; `src/pricing/dlmp.jl:327-333`

`decompose_dlmp(ctx2; atol = -1.0, rtol = 0.0)` makes the check fail only because nothing
checks `atol >= 0`. Adding that check would be a reasonable hardening. If someone adds it, this
item fails with an `ArgumentError` that has nothing to do with the WR-01 mapping it protects.
Add a comment at the `atol::Real` keyword in `dlmp.jl` saying that a negative `atol` is a
documented test seam. Alternatively, keep the seam valid under such a check: use
`rtol = 0.0, atol = 0.0`, then perturb one dual-free input instead. The comment is the cheaper
option.

### IN-15: `failing_agg` rebuilds the aggregator from fixture fields instead of wrapping `f.agg`

**File:** `test/test_flex_market.jl:262-265`, `:1755-1786`

- **Copied parameters.** `failing_agg` builds `Aggregator(2, 1.0, [FailAtCall(Interruptible(2,
  0.0, 2.0, f.a, f.bc), …)], f.Pdc)`. That repeats the bus, φ, Pmin and Pmax of `tight_agg` and
  `market_agg` instead of wrapping the fixture's own device. The tight path catches drift: its
  dry run is compared with `==` against `ph1`. The `_flex_tables` path (`diag_tables`) only
  compares the wrapped run against another wrapped run.
- **Only one trait is forwarded.** The wrapper forwards `is_flexible_load` only, so
  `storage_kind` and `has_reactive_decision` would be wrong for any inner device other than an
  Interruptible.

Build the wrapper from the fixture's aggregator:
`Aggregator(f.agg.bus, f.agg.φ, AbstractDevice[FailAtCall(only(f.agg.devices), fail_at, Ref(0))], f.agg.Pdc)`.
Also add `storage_kind(::Type{<:FailAtCall{D}}) where {D} = storage_kind(D)` (the
`PartialCompliance` idiom, `CapabilityTraits.jl:47`).

### IN-16: The `_flex_physics` → `"error:dlmp_split"` wiring has no end-to-end test

**File:** `src/coordination/flex_clear.jl:715-722`; `test/test_flex_market.jl:1189-1200`

The mapper is now tested on the real throw, but nothing drives a whole clear to a
`"error:dlmp_split"` record. The `try` around `_congested_hours` and the `known...` record
(see IN-13) are only covered by reading the code. A five-line wiring with no regression
behind it is acceptable at this stage. If `_congested_hours` ever gains split keywords,
pass a negative `atol` through `_flex_physics` and assert the status, the notes prefix and
the record fields.

### Carried forward (still open, unchanged in this range)

- **IN-01:** near-infeasible termination codes are not mapped to `infeasible_redispatch`
  (`flex_clear.jl:223-233`).
- **IN-02:** `FLEX_RANGE_FLOOR` is reused for three different thresholds.
- **IN-03:** a failed baseline `V0` solve offers zero flexibility without changing the status
  (`flex_bids.jl`).
- **IN-05:** tautological assertions in `test/test_flex_market.jl`.
- **IN-06:** the literate page `Core.eval`s the script's text layout.
- **IN-07:** the `π` local and record field shadow `Base.π`.
- **IN-08:** the refused stage-1 battery certificates are not stated in the docs for IEEE-13.
  The committed CSV shows `baseline_batt_refused = 29` on IEEE-123 too, and the docs page
  prints it in section 10 only.
- **IN-11:** purging before writing is not atomic (`tariff_comparison.jl`). This now also
  applies to `record_flex_timeout_main`, which purges, then upserts.
- **IN-12:** partly resolved. The 117-character docstring line went away when IN-09
  rewrote it. The positional `cases[end - 2]` and `cases[end - 1]` lookups in
  `test_flex_market_fence.jl:427, 429` remain.
- **IN-13:** a `"error:dlmp_split"` record discards stage-2 results that were already
  computed (`flex_clear.jl:715-722`).

The full text of IN-01 to IN-08 is in `45-REVIEW.iter1.md`; IN-11 to IN-13 are in
`45-REVIEW.iter2.md`.

---

_Reviewed: 2026-11-05T06:05:53Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 3_
