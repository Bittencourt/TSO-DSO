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
