---
phase: 45-flexibility-market-vs-price-coordination
fixed_at: 2026-11-05T05:15:03Z
review_path: .planning/phases/45-flexibility-market-vs-price-coordination/45-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 45: Code Review Fix Report

**Fixed at:** 2026-11-05T05:15:03Z
**Source review:** .planning/phases/45-flexibility-market-vs-price-coordination/45-REVIEW.md
**Iteration:** 1

**Summary:**

- Findings in scope: 7 (CR-01, WR-01 to WR-06)
- Fixed: 7
- Skipped: 0
- Also fixed: IN-04, a one-line Info fix in `src/settlement/comparison.jl`, which was already
  being edited. The other Info items are out of scope.

**Locked constraints, as verified:**

- **Default path.** Every new guard in `compare_tariffs` sits inside the
  `flex_markets !== nothing` block. The fence digests are unchanged:
  `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`.
- **Gates.** No gate was loosened and no golden was re-pinned.
- **Committed CSVs.** No committed CSV changed and no script mode was re-run.
- **Static checks.**
  - JET ratchet: 20 current, 20 baseline, 0 NEW, 0 FIXED.
  - Planning-ID guard: 355 hits, unchanged.
  - `check_content_loss.py HEAD` after the formatter pass: OK.

## Fixed Issues

### CR-01: Formulation and λ₀ preconditions fire only after every solve, and the DLMP split's reconstruction check is never mapped to a status

**Files modified:** `src/coordination/flex_clear.jl`, `src/coordination/flex_settle.jl`, `src/settlement/comparison.jl`, `test/test_flex_market.jl`, `test/test_flex_market_fence.jl`
**Commit:** 107c4a9

**Applied fix:**

- **Guards before any solve.** `_flex_physics` and the `compare_tariffs` flex block now throw
  `ArgumentError` for:
  - a `pf` that is not a `ConvexBranchFlow`;
  - a `λ₀` with a non-positive entry (`compare_tariffs` also refuses non-finite entries).

  `clear_flex_market` gets the `_flex_physics` guards, which still run before stage 1.
- **λ₀ policy.** Non-positive λ₀ is refused rather than normalised. The congestion score is
  defined as a fraction of λ₀, and an `eps` floor would be a picked constant.
- **Split failures become a status.** A reconstruction failure of the split after a gated
  stage 2 (an `ErrorException` starting with `"decompose_dlmp:"`) now maps, through the new
  `_congestion_status`, to the status `"error:dlmp_split"` with notes prefixed
  `"congestion: "`. Solver-outcome types map as before, and anything else rethrows.
- **Tests.**
  - The fence item has new LinDistFlow, zero-λ₀ and negative-λ₀ cases. Each throws
    `ArgumentError` with **0 optimizer calls**, so the DADP solve never ran.
  - A LinDistFlow call without `flex_market` still returns the four legs, so the guard is
    opt-in only.
  - The physics item has new guard checks and unit checks of `_congestion_status`.

### WR-01: An aggregator vector that is complete but unsorted passes the `clear_flex_market` guard, then throws after stage 1 and bid probing

**Files modified:** `src/coordination/flex_clear.jl`, `src/coordination/flex_settle.jl`, `src/settlement/comparison.jl`, `test/test_flex_market.jl`, `test/test_flex_market_fence.jl`
**Commit:** 8e84829

**Applied fix:**

- **`clear_flex_market`.** The bus check is now `agg_buses == input.buses`, and its message
  names the ascending-order requirement.
- **`_flex_physics`.** It checks `issorted` with its other entry guards.
- **`compare_tariffs`.** The flex block refuses a descending order before the DADP run.
- **Tests.**
  - The fence refuses descending order with 0 optimizer calls.
  - A descending `clear_flex_market` call raises the `clear_flex_market:` message (the old
    behaviour raised the `_stage2_aggregators:` message), and `_flex_physics` raises its own
    message.

### WR-02: The pay-as-bid quantity invariant is never tested, and the pay-as-bid price assertion is weak

**Files modified:** `test/test_flex_market.jl`
**Commit:** 85dd14a

**Applied fix:** the "payment rules differ only in money" item now asserts three things:

1. **Pairing.** Every pay-as-bid row equals, as a tuple, the accepted block it books:
   `(bus, t, m_k, +u_k)` or `(bus, t, g_k, −w_k)`. An up row priced at a down value, or at
   the wrong block, now fails.
2. **Quantities.** The per-hour row quantities sum to Δ within `TOL_PAB_Q = 8.33e-17`.
   - Measured on Julia 1.12.5 over seeds 20260719 to 20260721: 6.6e-24, 1.0e-25 and
     2.78e-17.
   - The pin is 3 times the maximum.
3. **Money.** `flex_payments_total == Σ m·u − Σ g·w` exactly. The observed difference was 0.0
   on all three seeds.

Both measured values are recorded in the file's tolerance table.

### WR-03: The claim that the delivery penalty is exact is not justified, so the shortfall may be partly a penalty artefact

**Files modified:** `src/coordination/flex_clear.jl`, `docs/literate/flex_market.jl`
**Commit:** 03c229a

**Applied fix:** the second option was chosen: keep the 10× weight and correct the claims. No
measured number changes.

- **Docstrings.** The `_deliver` and `_flex_physics` docstrings and the file header now say
  that the weight is a documented heuristic, not a proof that the penalty is exact. The reason
  given is that the tracking multiplier is a device marginal utility, bounded by the slope of
  the value function and not by any price.
- **What they state is guaranteed.** The shortfall does not increase as the weight grows, so
  the value at w is an **upper bound** on the hour-separability loss.
- **Docs page, section 8.** It no longer concludes "structural hour-separability loss". It
  presents the w vs 10w sensitivity as the evidence, and says this does not rule out a
  multiplier above 10w.
- **Printed output.** The section now prints the relative change as well. The committed
  values give:

  | Mode | Shortfall at w | Shortfall at 10w | Relative change |
  |---|---|---|---|
  | IEEE-13 | 0.296140167664805 | 0.2961401530535588 | −4.93e-8 (change −1.46e-8) |
  | IEEE-123 | 0.70933441617307 | 0.7093341786155828 | −3.35e-7 (change −2.38e-7) |

- **Limitations.** A new bullet, "Heuristic tracking weight", was added.

### WR-04: Script upserts leave stale `(run)` and flex rows next to fresh rows, and the CSV test accepts the mix

**Files modified:** `scripts/tariff_comparison.jl`, `test/test_flex_market_ieee.jl`, `docs/literate/flex_market.jl`
**Commit:** 45aa785

**Applied fix:** a new `purge_rows(mode, seed, T_H; tariff)` deletes the rows a run owns from
all four tables before the run writes. Ownership is as follows:

| Run | Rows it owns |
|---|---|
| IEEE-123 modes (`write_mode_outcome`), any outcome | every row of the mode |
| `case-a-784` | every row of the mode |
| `--record-timeout` | every row of the mode |
| Default `ieee13-ground`, success | the non-flex rows; also the flex rows when the new dadp row does not reproduce the committed one (`dadp_provenance`) |
| Default `ieee13-ground`, refusal | every row of the mode |
| `ieee13-ground --flex-market` | only the flex rows, purged after the unchanged stop-on-mismatch `assert_dadp_reproduces` |

- **Provenance check.** `dadp_provenance` is the non-throwing core of
  `assert_dadp_reproduces`, and the error messages are unchanged.
- **New refusal.** `--record-timeout` combined with `--flex-market` on `ieee13-ground` is
  refused, because that path has no run-level row.
- **Test.** The committed-CSV test is now exclusive: the IEEE-123 rows must be either the full
  leg set or only `(run)`. It also asserts that no `(run)` row sits beside leg, bill, breakout
  or rebound rows; 2 `(run)` groups are checked.
- **Scratch check.** The scratch check ran on copies, and the files were restored
  byte-identical. It found:
  - a no-op purge rewrites nothing;
  - purging keeps every other line byte-identical and in order;
  - the flex-only purge leaves the base rows intact;
  - the timeout+flex refusal writes nothing.

### WR-05: The IEEE-123 smoke test treats any `SolveFailedError` or `CertificateError` as a DADP refusal and passes with zero flex assertions

**Files modified:** `test/test_flex_market_ieee123.jl`
**Commit:** f53031b

**Applied fix:**

- **DADP solve first.** The DADP `solve_welfare` runs first and alone, with the comparison's
  optimizer. Only it may refuse, with `SolveFailedError` or a `CertificateError` of kind
  `:socp_exact`.
- **Certified DADP.** `compare_tariffs` runs outside any `try`. The item asserts the leg order,
  the dadp status, the flex row's status sets and its wall time. On an ok flex row it also
  asserts the probe count, the welfare and the shortfall.
- **Refused DADP.** The item asserts that `compare_tariffs` refuses with the same error type.
- **Measured run** (`TSODSO_TEST_SET=all`): 11/11 pass in 7m31s. It took the ok path:
  `flex_uniform` was ok and feasible.

### WR-06: A failed diagnostic 10w delivery throws away a successful clear

**Files modified:** `src/coordination/flex_clear.jl`, `test/test_flex_market.jl`
**Commit:** 6524228

**Applied fix:**

- **Separate diagnostic.** The 10w pass is now `_shortfall_diagnostic`, run after the primary
  delivery's own `try`. On a solver outcome it returns
  `(missing, "delivery at 10w (sensitivity diagnostic only; ...")`. The clear stays `"ok"`,
  with the note in `notes` and `delivery_shortfall_total_10w = missing`.
- **Values unchanged.** The summation order is the same as before, so the recorded values are
  bit-identical.
- **Tests.**
  - The diagnostic reproduces the record's `shortfall_10w_total` exactly.
  - At an absurd weight of 1e300, the solver returns NUMERICAL_ERROR and the diagnostic
    returns `(missing, note)` instead of throwing.
  - A malformed target still throws `ArgumentError`.

### IN-04 (Info, trivial, in a file already edited): The FixedCapacitor guard is duplicated

**Files modified:** `src/settlement/comparison.jl`
**Commit:** 8060e2a

**Applied fix:** the duplicated guard was replaced by
`_refuse_fixed_capacitor(aggs, "compare_tariffs")`. The fence capacitor case still passes.

## Style

**Commit:** 5266d96. A JuliaFormatter 2.10.2 pass on the touched files changed layout only:
`check_content_loss.py HEAD` reports whitespace and commas only.

## Verification

All counts below come from runs on Julia 1.12.5.

- **Fast run, final.** `test_flex_market.jl`, `test_flex_market_fence.jl` and
  `test_flex_market_ieee.jl`, run after the formatter pass: 1421/1421 pass, 0 fail, 0 error.
  The fence digests are unchanged.
- **Slow run.** `test_flex_market_ieee123.jl`: 11/11 pass.
- **Per-fix runs.**

  | Fix | Pass |
  |---|---|
  | CR-01 | 1379 |
  | WR-01 | 1387 |
  | WR-02 | 1313 |
  | WR-06 | 1400 |
  | WR-04 | 24 |
  | IN-04 | 86 |

- **Not run.** The full suite was not run (the orchestrator's job).

---

_Fixed: 2026-11-05T05:15:03Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

# Iteration 2

**Fixed at:** 2026-11-05T05:59:27Z
**Source review:** .planning/phases/45-flexibility-market-vs-price-coordination/45-REVIEW.md
(iteration 2)
**Iteration:** 2

**Summary:**

- Findings in scope: 6 (WR-01 to WR-04, plus the Info items IN-09 and IN-10)
- Fixed: 6
- Skipped: 0
- Out of scope, still open: IN-11, IN-12, IN-13 and the carried-forward IN-01, IN-02, IN-03,
  IN-05, IN-06, IN-07 and IN-08.

**Locked constraints, as verified:**

- **Default path.** `test/test_flex_market_fence.jl` is unchanged and passes, so its digests
  are unchanged: `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4,
  0x5515555ce78f74e5, 0xe386f1abc04d04c8)`.
- **Gates and goldens.** No gate was loosened and no golden was re-pinned. The one new
  tolerance (WR-03) was measured.
- **Statuses and guards.** Solver outcomes are still reported as statuses. The radial-tree
  misuse is now a thrown `ArgumentError` (WR-01), and the new flex timeout refusal (WR-04)
  fires before any write.
- **Committed CSVs.** None changed and no mode was re-run. The WR-04 scratch check ran on the
  committed files and restored them from a scratchpad copy. All four sha256 sums matched the
  originals afterwards, and `git diff 5258235 -- results/` is empty.
- **Static checks.**
  - JET ratchet (Julia 1.12.7, run alone): 20 current, 20 baseline, 0 NEW, 0 FIXED.
  - Planning-ID guard: 355 hits, unchanged.
  - `check_content_loss.py HEAD` after the formatter pass: OK.
  - `check_script_api.jl` on the script and the docs page: OK.
  - `check_scripts_index.py`: OK.

## Fixed Issues (iteration 2)

### WR-01: The `"error:dlmp_split"` mapping depends on the error message prefix, and the test pins a made-up message

**Files modified:** `src/pricing/dlmp.jl`, `src/coordination/flex_clear.jl`, `test/test_flex_market.jl`
**Commit:** 3fa053e

**Applied fix:** I chose a shared constant over a typed error. A shared constant keeps
`decompose_dlmp`'s public thrown type (`ErrorException`) unchanged for its other callers.

- **Shared prefix.** `const _DLMP_RECON_FAIL` in `dlmp.jl` is the prefix of the
  sum-to-price failure message, and `decompose_dlmp` builds the message from it.
  `_congestion_status` matches `startswith(err.msg, _DLMP_RECON_FAIL)` instead of
  `"decompose_dlmp:"`.
- **Tree misuse.** The radial-tree walk (`_path_branches`) now throws `ArgumentError`, so a
  malformed tree is a thrown misuse error and is never mapped to a status.
- **Tests on the real path.**
  - The test builds a real gated stage-2 context and calls the real `decompose_dlmp` with
    `atol = -1.0, rtol = 0.0`, a forcing seam that makes the check fail. It asserts that the
    error carries the constant's prefix and maps to `"error:dlmp_split"`.
  - It also asserts that four errors are not mapped: the real tree error, a generic
    `"decompose_dlmp: other"` `ErrorException`, an `ArgumentError` carrying the prefix, and
    an unrelated `ErrorException`.

### WR-02: The WR-06 test forces the diagnostic to fail through Clarabel's numerics at w = 1e300

**Files modified:** `test/test_flex_market.jl`
**Commit:** d1faee8

**Applied fix:** the 1e300 case is gone. A test-only device `FailAtCall` in
`FlexMarketFixtures` wraps the fixture's Interruptible and counts its `contribute!` calls. On
the chosen call it throws the `SolveFailedError` that `assert_solved!` throws. Every other
call contributes the inner device unchanged, and `is_flexible_load` is forwarded. The test
covers three levels:

- **Unit.** `_shortfall_diagnostic` with the failing device returns `(missing, note)`, and the
  note names the injected failure.
- **`_flex_physics`.**
  - A counting dry run reproduces the plain clear exactly: the delivered nets, the shortfall
    and the 10w total all match.
  - Failing the last device solve (the 10w diagnostic) keeps the status `"ok"`. The note goes
    to `notes`, `shortfall_10w_total === missing`, and the primary delivery, Δ and weight
    equal the dry run's.
  - Failing the solve before it (the primary delivery) gives `"error:SolveFailedError"` with
    a `"delivery: "` note and no delivery.
- **`_flex_tables`.** The failed diagnostic reaches the summary as an `ok` row: the note is
  set, `delivery_shortfall_total_10w` is missing, and the shortfall, welfare and AC verdict
  equal the dry run's.

### WR-03: The pay-as-bid money check uses exact equality across two different summation orders, and the quantity tolerance is an absolute value below one ulp

**Files modified:** `test/test_flex_market.jl`
**Commit:** 295afb0

**Applied fix:**

- **Money.** The expected value is now `tuple_money(expect_rows)`, which sums row by row in
  booking order (hour by hour, up blocks then down blocks). That is the order
  `_flex_payment_rows` accumulates, so `==` holds by construction.
- **Quantities.** The per-hour gap is now scaled by `Σ |row quantity|` of the hour
  (`pab_quantity_relgap`), so the bound no longer depends on the size of the activation.
  - Measured on Julia 1.12.5, seeds 20260719 to 20260721, with a scratch copy of the fixture:
    the maximum relative gaps were 9.44e-17, 1.35e-16 and 2.11e-16. The absolute maximum is
    still 2.78e-17.
  - `TOL_PAB_QREL = 6.33e-16` is three times the maximum. The tolerance table records it.
  - In the same measurement, the money difference was 0.0 on every seed, in both the
    production order and the old split order.

### WR-04: A killed `ieee13-ground --flex-market` run can only be recorded by deleting the certified base rows it never re-ran

**Files modified:** `scripts/tariff_comparison.jl`, `scripts/README.md`, `test/test_flex_market_ieee.jl`
**Commit:** c404b37

**Applied fix:** `--record-timeout S --flex-market` on ieee13-ground is now a flex-scoped
record instead of a refusal.

- **What the new path does.** `record_flex_timeout_main` runs these steps in order:
  1. It refuses with `ArgumentError`, before any write, when there is no committed dadp row
     to clear against.
  2. It purges only the mode's flex rows from all four tables. An earlier flex status row is
     purged too.
  3. It writes one `flex_(run)` status row with status `timeout` and `run_wall_s = S`.

  The base rows and their bill and breakout rows are never touched. `write_run_status_row`
  takes the tariff as a keyword.
- **Plain timeout.** A plain `--record-timeout S` still records a stopped base run and owns
  every row of the mode.
- **Docs.** The header, the CSV-contract paragraph and `scripts/README.md` describe both
  records.
- **CSV test.**
  - ieee13-ground must hold either the 8 flex legs or only `flex_(run)`.
  - `no_stale_rows` lets `flex_(run)` exclude the flex rows only: no flex leg row and no flex
    bill, breakout or rebound row may sit beside it, and the base rows stay. Four
    synthetic-table checks exercise the rule.
  - The flex-leg checks skip the status row, which must have status `timeout`.
- **Scratch check on the real files.** I backed up the CSVs and ran the script through a
  driver in the scratchpad.
  - The seed-1 refusal changed no file (sha256 unchanged).
  - The real record purged 8 summary, 60 bill and 144 rebound flex rows. Every other line
    stayed byte-identical and in order, and one `flex_(run)` timeout row was written.
  - The CSV test passed (29/29) on that state, and then on the restored committed state.

### IN-09: The WR-03 upper-bound wording needs its qualifiers

**Files modified:** `docs/literate/flex_market.jl`, `src/coordination/flex_clear.jl`
**Commit:** 8e044f4

**Applied fix:** docs section 8, the limitations bullet and the `_flex_physics` docstring now
state the three limits:

- the bound holds for totals only (overall or per aggregator), not for the worst bus-hour or
  the per-hour shortfall;
- it is relative to the relaxed battery model, so it bounds the physical loss only where the
  delivered certificates are `:ok`. They are `:ok` on every committed `ok` flex row, which I
  checked in the CSV: `batt_refused = 0`, `batt_ok = 10` on IEEE-13 and 85 on IEEE-123;
- it holds only up to solver tolerance, the size of the committed 10w changes.

No number changed.

### IN-10: The ownership rules are partly undocumented, and a documented invocation now breaks the CSV test

**Files modified:** `scripts/tariff_comparison.jl`, `docs/literate/flex_market.jl`
**Commit:** a2aee82

**Applied fix:**

- **Header.** The script header says the committed `ieee123` artifact is recorded with
  `--flex-market`, because a base-only run deletes the flex rows and the CSV test rejects
  the result.
- **Message.** `ground_main` now prints the real `dadp_provenance` reason, for example
  "Expected exactly 1 committed dadp row, found 0." on the first run of a seed.
  - The flex path's "Stop and investigate" text moved to a separate `advice` field, which only
    `assert_dadp_reproduces` appends.
  - Its thrown messages are byte-identical. I checked this against the previous script,
    loaded side by side, on a value mismatch, a missing committed row and a refused run.
- **Docs.** Section 13 now lists every ownership rule, including the default ieee13-ground
  rule that was missing, the flex timeout record and the plain `--record-timeout`.

## Style (iteration 2)

**Commit:** 3e96fd4. A JuliaFormatter 2.10.2 pass over the six touched `.jl` files made two
line wraps in `scripts/tariff_comparison.jl`; the other five files were already formatted.
`check_content_loss.py HEAD` reports whitespace and commas only.

## Verification (iteration 2)

All runs are on Julia 1.12.5 unless noted.

- **Final fast run.** `test_flex_market.jl`, `test_flex_market_fence.jl` and
  `test_flex_market_ieee.jl`, after the formatter pass: 1454/1454 pass, 0 fail, 0 error.
  Iteration 1 had 1421.
- **Per-fix runs.**

  | Fix | Files | Pass |
  |---|---|---|
  | WR-01 | `test_flex_market.jl` | 1322 |
  | WR-02 | `test_flex_market.jl` | 1345 |
  | WR-03 | `test_flex_market.jl` | 1345 |
  | WR-04, flex-timeout state | `test_flex_market_ieee.jl` | 29 |
  | WR-04, committed state | `test_flex_market_ieee.jl` | 29 |

- **IN-09 and IN-10.** These changed prose and the script only. Both files parse, and
  `check_script_api.jl` passes.
- **Not run.** The slow IEEE-123 item and the full suite (the orchestrator's job).

---

_Fixed: 2026-11-05T05:59:27Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
