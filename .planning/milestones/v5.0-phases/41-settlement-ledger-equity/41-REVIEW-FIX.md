---
phase: 41-settlement-ledger-equity
fixed_at: 2026-10-26T08:46:25Z
review_path: .planning/phases/41-settlement-ledger-equity/41-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 41: Code Review Fix Report

**Fixed at:** 2026-10-26T08:46:25Z
**Source review:** `.planning/phases/41-settlement-ledger-equity/41-REVIEW.md`
**Iteration:** 1
**Fix scope:** critical + warning (the 6 INFO findings are out of scope and remain open)

**Summary:**
- Findings in scope: 6 (1 critical, 5 warnings)
- Fixed: 6
- Skipped: 0

**Test results:** the fast suite over the affected files — `test/test_settlement.jl`,
`test/test_equity.jl`, `test/test_exports.jl`, `test/test_tsodso_errors.jl` — passes
**492 / 492** (`TSODSO_TEST_SET=fast`, Julia 1.12.5, `julia --project=test` with the
repo root stacked on `JULIA_LOAD_PATH`, per CI's filtered-run recipe). Every fix was
also parse-checked (`Meta.parseall`) and byte-verified before its atomic commit.

## Fixed Issues

### BL-01: `:fit` leg reports `wholesale_total` with the opposite sign of every other leg

**Files modified:** `src/settlement/comparison.jl`, `test/test_settlement.jl`
**Commit:** `b99a5b7`
**Status:** fixed: requires human verification (sign-convention flip — numerically
pinned by tests, but the semantic choice deserves an eyeball)
**Applied fix:** `wholesale_total = sum(λ₀vec[t] * imp_total[t] for t in 1:T)` (was
`-sum(...)`) and the coupled `merchandising_surplus = dso_total - wholesale_total` (was
`+`), matching the ledger convention (`led.balances[:wholesale]` = `+Σ_t λ₀·p_import`)
used by the dadp/flat/tou legs and the module header spec. Pins added: a dedicated
pure-consumer test (`PVBattery` with `Ppv ≡ 0` ⇒ FIT `imp = Pdc > 0`) asserting
`fitr.wholesale_total > 0` and `≈ 12.0` (measured band), plus bitwise identity pins
(`merchandising_surplus == dso_total - wholesale_total`, `dso_total == total_payments`,
`aggregators_total == -total_payments`) on the hermetic four-leg fixture — whose FIT
prosumer is self-sufficient (`Ppv == p_h` ⇒ `imp ≈ 0`), which is why the sign lives in
its own fixture.
**Artifact check:** the committed `results/settlement_comparison/tariff_comparison.csv`
fit row is an honest `error:SolveFailedError` status row with EMPTY values, and the
case-a-784 row is the `(run)` refusal — **no inverted wholesale numbers were ever
committed, so no CSV regeneration was needed** (the long-running 784-house run was not
re-attempted, per instructions).

### WR-01: `gini` silent sign-flip on negative-mean vectors; docstring omits μ < 0

**Files modified:** `src/settlement/equity.jl`, `test/test_equity.jl`
**Commit:** `cf56e2e`
**Applied fix:** adopted the convention the docs page already asserts
(`docs/literate/settlement_equity.jl` metric table: Gini "may be negative on
net-earning populations") — the `gini` docstring (and the module-header normative
convention line) now document that on `mu < 0` the sign of `G` follows μ and is
reported as computed, never clipped. Code unchanged (it already returns the signed
value). Pinned by a hand-computed known-value test: `gini([-3.0, -1.0]) == -0.25` with
the mirror `gini([1.0, 3.0]) == 0.25` (dyadic-exact arithmetic).

### WR-02: λ₀ indexed before its own length guard — raw BoundsError, dead validation

**Files modified:** `src/settlement/run_inputs.jl`, `test/test_settlement.jl`
**Commit:** `8768865`
**Applied fix:** the `length(λ₀) >= T` guard now runs BEFORE the comprehension, so a
too-short λ₀ raises the documented `ArgumentError` naming `λ₀ has length N < T` instead
of a raw `BoundsError`; the dead post-build check was removed (it could never fire) and
over-length λ₀ still truncates to `T`. Tests pin both the short-refusal (on a real
solved `solve_welfare` fixture) and the truncation path.

### WR-03: price-taker battery certificate mislabels "devices but no battery" as `:ok`

**Files modified:** `src/settlement/price_taker.jl`, `test/test_settlement.jl`
**Commit:** `ae7deab`
**Applied fix:** `:not_checked` detection now keys on the check's OWN battery predicate
(`haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q)` — mirroring
`assert_battery_complementarity!` in `welfare_solve.jl`) instead of
`isempty(ctx.agg_device_vars)` emptiness; the complementarity check runs only when a
battery var is present. The docstring already promised "no battery vars" semantics, so
code and docstring now agree. New test pins a Thermostatic-only aggregator (which does
populate `agg_device_vars`, so the pin is non-vacuous): `battery_certificate ==
:not_checked`. All-battery tests are unaffected (they take the same `:ok`/`:refused`
path as before).

### WR-04: run-failure path never calls `ensure_schema` — promised header-only artifacts missing

**Files modified:** `scripts/tariff_comparison.jl`
**Commit:** `7ab2455`
**Applied fix:** new `ensure_all_schemas()` helper (the three `ensure_schema` calls)
runs immediately after `run_compare_outcome` and BEFORE the `if !outcome.ok` branch in
BOTH `ground_main` and `caseA_main`; the trailing calls were removed. Every exit path —
including a run-level failure writing the `"(run)"` status row — now leaves all three
CSVs present (header-only when nothing was certified). Verified by loading the script
(main-guard prevents auto-run) and executing the helper against the existing artifacts.

### WR-05: ADMM budget-stop detection sniffs the error message for `":converged"`

**Files modified:** `src/core/errors.jl`, `src/settlement/run_inputs.jl`,
`scripts/tariff_comparison.jl`, `test/test_settlement.jl`, `test/test_tsodso_errors.jl`,
`test/test_exports.jl`, `docs/src/status_policy.md`
**Commit:** `0e6c7ca`
**Applied fix:** the review's "better" option — new exported
`UnconvergedAdmmError <: TSODSOError` (message unchanged, so `showerror` output is
bit-identical) thrown by `settlement_input(r::NamedTuple)`'s non-`:converged` refusal;
the script catches BY TYPE (the `error:unconverged_admm` status row is unchanged) and
the `is_unconverged_guard` message-sniffing helper is deleted. Functionally verified:
an unrelated `ArgumentError` that merely mentions `:converged` now PROPAGATES (exit
nonzero) while a genuine `UnconvergedAdmmError` is recorded. Tests updated: adapter
refusal asserts the new type (and that it is NOT an `ArgumentError`), the errors
hierarchy/`_is_solver_failure` loops include it, the curated exports list gained it,
and `docs/src/status_policy.md` documents the type.

## Skipped Issues

None — all 6 in-scope findings were fixed.

**Note (out of scope):** the 6 INFO findings (NF-01…NF-06) were not touched, per fix
scope.

---

_Fixed: 2026-10-26T08:46:25Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
