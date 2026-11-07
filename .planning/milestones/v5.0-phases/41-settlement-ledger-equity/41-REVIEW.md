---
phase: 41-settlement-ledger-equity
reviewed: 2026-10-26T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - CLAUDE.md
  - src/TSODSO.jl
  - src/settlement/SettlementLedger.jl
  - src/settlement/run_inputs.jl
  - src/settlement/tariffs.jl
  - src/settlement/price_taker.jl
  - src/settlement/feasibility.jl
  - src/settlement/equity.jl
  - src/settlement/comparison.jl
  - scripts/tariff_comparison.jl
  - docs/literate/settlement_equity.jl
  - docs/make.jl
  - test/test_settlement.jl
  - test/test_equity.jl
  - test/test_exports.jl
findings:
  critical: 1
  warning: 5
  info: 6
  total: 12
status: clean
fix:
  applied_at: 2026-10-26T08:46:25Z
  fix_report: 41-REVIEW-FIX.md
  in_scope: 6
  fixed: 6
  fixed_ids: [BL-01, WR-01, WR-02, WR-03, WR-04, WR-05]
  skipped: 0
  info_out_of_scope: 6
re_review:
  verified_at: 2026-10-26T09:07:12Z
  commits: [b99a5b7, cf56e2e, 8768865, ae7deab, 7ab2455, 0e6c7ca]
  result: clean
  tests: 560 passed / 0 failed (test_settlement, test_equity, test_exports, test_tsodso_errors, test_status_policy)
---

# Phase 41: Code Review Report

**Reviewed:** 2026-10-26
**Depth:** standard
**Files Reviewed:** 14
**Status:** clean — re-verified 2026-10-26 (see Re-Review below). Original review found
1 critical + 5 warnings + 6 info; all 6 in-scope findings fixed and VERIFIED
(`41-REVIEW-FIX.md`); the 6 INFO items remain open, out of fix scope.

## Summary

The settlement layer is numerically sound at its core. Verified clean under direct trace:
(1) the double-entry ledger is conservation-exact by the adjacent mirror-pair construction —
each logical flow stores `a = fl(price·qty)` then its exact negation, so the sequential fold
cancels bitwise, the constructor guards `residual == 0.0`, and `merchandising_surplus ==
balances[:dso]` with the correct nodal-collections-minus-wholesale semantics (re-derived
independently); (2) the pinned TOU bins (`1:6`, `7:16 ∪ 23:24`, `17:22`) are an exact
partition of `1:24` — no off-by-one — and both `revenue_neutral_flat`/`revenue_neutral_tou`
are algebraically revenue-neutral with a ≈1.0 no-op rescale guard; (3) `ac_feasibility_status`
honors the report-never-throw contract (only misuse `ArgumentError`s escape; `:solve_failed`
carries the termination status and reads no values off a non-converged model); (4) the
negative-value conventions for Theil/Atkinson/Palma are implemented exactly as documented
(positive-support exclusion with returned counts; NaN terminals; group-total Palma with the
`-3.0` sign caveat); (5) test certificates are genuinely non-vacuous (hand-computed
`gini([-2,1,3,6]) == 0.8125`, `palma == -3.0`, exact `-80.0` ledger sign anchor, measured
gate-then-golden rtol pins, honest `missing`/NaN assertions).

One CRITICAL: the `:fit` leg's `wholesale_total` column is sign-flipped relative to the
ledger convention used by the other three legs, contradicting the module's own header
spec — cross-tariff wholesale comparisons in the committed artifact are inverted. Five
warnings follow (a Gini negative-mean spec gap, a dead λ₀ guard that leaks a raw
BoundsError, a battery-certificate status mislabel, a missing `ensure_schema` on the
script's failure path, and message-sniffing control flow). Six info items.

Note for downstream: `is_solved_and_feasible` (feasibility.jl:374 and 17 other call sites)
was checked for a missing definition — it is JuMP's own API (JuMP ≥1.15, `allow_local`/
`dual`/`allow_almost` kwargs), not a repo function; not a defect. Several read artifacts
displayed character-mangled text; every suspicious line was re-verified against raw file
bytes before being judged.

## Re-Review (iteration 2, 2026-10-26)

All six fix commits verified — each fix is genuine, correctly coupled, and regression-free.

- **BL-01** (`b99a5b7`): the fit leg now computes `wholesale_total = sum(λ₀vec[t]*imp_total[t])`
  (comparison.jl:711) and `merchandising_surplus = dso_total - wholesale_total` (:725) — the
  coupled flip, changed together. The surplus VALUE is invariant under the flip (pre-fix
  `dso + (-w)` ≡ post-fix `dso - w`), and all four legs now agree: dadp (:526) and flat/tou
  (shared builder at :625) read `led.balances[:wholesale]` — the positive import receipt —
  with `merchandising_surplus = led.merchandising_surplus` (≡ `balances[:dso]` = collections
  minus wholesale), exactly the convention the fit leg now implements. The pin test uses a
  pure-consumer fixture (imp = fixed load > 0 strictly) so `wholesale_total > 0` FAILS on
  pre-fix code (which reported -12), plus a `≈ 12.0 rtol=1e-6` magnitude band and bitwise
  same-float identity pins. The committed CSV needed no regeneration (its fit row is an
  error-status row with empty values — no inverted numbers were ever shipped).
- **WR-01** (`cf56e2e`): documentation-convention fix per the finding's own option 2 — the
  docstring and module header now state the sign follows μ, reported as computed, never
  clipped, matching the docs page; pinned by the hand-computed mirror
  `gini([-3.0, -1.0]) == -0.25 == -gini([1.0, 3.0])` (exact dyadic arithmetic). By design
  this test also passes on pre-fix code (the formula never changed) — it pins the
  documented convention; it is not a regression tripwire.
- **WR-02** (`8768865`): the `length(λ₀) >= T` guard now precedes the comprehension
  (run_inputs.jl:121-122); the dead post-build check is removed; truncation semantics
  preserved (`λ0 = λ0[1:T]`). Pins: a short λ₀ raises the documented `ArgumentError`
  naming "λ₀ has length 2 < T=3" (pre-fix: raw BoundsError — fails on pre-fix code), and
  an over-length λ₀ is still accepted and truncated to T.
- **WR-03** (`ae7deab`): `has_battery` keys on the check's OWN predicate
  (`p_ch` ∧ `p_dch` ∧ ¬`q` — identical to welfare_solve.jl:366), not on `agg_device_vars`
  emptiness; a thermostatic-only aggregator now reports `:not_checked` (pre-fix: `:ok` —
  fails on pre-fix code). An empty `agg_device_vars` still yields `:not_checked`
  (`any` over an empty collection), and a mixed population with at least one battery still
  runs the check (`:ok`/`:error` unchanged).
- **WR-04** (`7ab2455`): `ensure_all_schemas()` runs immediately BEFORE the `!outcome.ok`
  early return in BOTH mains (script lines 436 and 540); the old trailing calls are gone
  (grep: `ensure_schema` now appears only at its definition and inside the helper). Every
  exit path leaves all three CSVs; no other early return sits between the run and the
  hoist, and misuse errors still propagate (crash exit — no CSV promised).
  `ensure_schema` is create-if-missing, so the success path is behavior-identical.
- **WR-05** (`0e6c7ca`): `UnconvergedAdmmError <: TSODSOError` (exported from
  src/core/errors.jl:109-144) is thrown by `settlement_input(r::NamedTuple)`
  (run_inputs.jl:209); the script catches BY TYPE (tariff_comparison.jl:176);
  `is_unconverged_guard` is gone repo-wide (grep-verified, zero hits). Regression sweep:
  `compare_tariffs`'s ADMM path (comparison.jl:324) has no intervening catch; the fit-leg
  catch (SolveFailedError/CertificateError/ConvergenceError only, :662) is untouched; no
  other call site matched `ArgumentError` against this refusal. `showerror` prints
  `e.msg` via the shared TSODSOError method (message unchanged); exports, tests
  (test_tsodso_errors, test_exports, test_settlement), and docs/src/status_policy.md all
  updated for the new type.

**Test evidence:** the five affected test files (test_settlement.jl, test_equity.jl,
test_exports.jl, test_tsodso_errors.jl, test_status_policy.jl) via
`TSODSO_TEST_SET=all TSODSO_TEST_FILES=... julia --project=. -e 'import Pkg; Pkg.test()'`
→ **560 passed / 0 failed** (4m51s). The measurement script was additionally load-verified
under the package env (`include("scripts/tariff_comparison.jl")`; it is
`PROGRAM_FILE`-guarded): the export wiring resolves, `ensure_all_schemas` is defined, and
the old sniffer is undefined.

**New findings:** none. No regression found in any fixed hunk.

## Critical Issues

### BL-01: `:fit` leg reports `wholesale_total` with the opposite sign of every other leg

**File:** `src/settlement/comparison.jl:711` (interaction with `:725`; conventions at `:526`, `:625`)

**Issue:** The dadp/flat/tou legs report `wholesale_total = led.balances[:wholesale]`
(lines 526, 625), which by the ledger's flow (b) equals `+Σ_t λ₀[t]·p_import[t]` — positive
when the DSO imports (the wholesale actor's receipt). The fit leg instead computes
`wholesale_total = -sum(λ₀vec[t] * imp_total[t] for t in 1:T)` (line 711) — negative for
imports. `imp[t] ≥ 0` by construction (`src/pricing/fit.jl:187`), so for economically
identical runs the fit row's column is the negation of the other legs'. The module's own
header (comparison.jl:39-41) specifies "wholesale = `λ₀` times the aggregate import", i.e.
the positive magnitude — the code contradicts both the header and the ledger convention.
The merchandising-surplus line (`dso_total + wholesale_total`, line 725) is internally
consistent with the *flipped* sign, so `merchandising_surplus` is correct — but the
`wholesale_total` column of the committed `tariff_comparison.csv` inverts any cross-tariff
wholesale comparison (the artifact's stated purpose).

**Fix:**
```julia
# comparison.jl, fit leg — report the wholesale payment with the ledger's sign:
wholesale_total = sum(λ₀vec[t] * imp_total[t] for t in 1:T)   # was: -sum(...)
...
merchandising_surplus = dso_total - wholesale_total,          # was: dso_total + wholesale_total
```
Then pin the sign in `test/test_settlement.jl` (e.g. assert `fitr.wholesale_total > 0` on an
importing dispatch and `fitr.merchandising_surplus == fitr.dso_total - fitr.wholesale_total`).

> **Fixed** (2026-10-26, commit `b99a5b7`): fit leg now reports `wholesale_total =
> sum(λ₀[t]·imp_total[t])` with `merchandising_surplus = dso_total - wholesale_total` —
> the ledger/header convention, matching the other three legs. Pinned by a dedicated
> pure-consumer test (receipt ≈ 12.0 at λ₀ = 40, the hermetic fixture's FIT prosumer is
> self-sufficient so imp ≈ 0 there) plus bitwise identity pins. The committed CSV needed
> NO regeneration: its fit row is an honest `error:SolveFailedError` status row with
> empty values, so no inverted wholesale numbers were ever committed.

## Warnings

### WR-01: `gini` is silent and sign-flipped on negative-mean vectors; the normative docstring omits the μ < 0 case

**File:** `src/settlement/equity.jl:83-97` (guard at `:88`)

**Issue:** The relative mean-difference form `G = S / (2n²μ)` flips sign when `μ < 0`: e.g.
`gini([-3.0, -1.0]) == -0.25`. The docstring — declared by the module header as the locked
normative spec — documents only "MAY EXCEED 1" and guards exactly `μ == 0`; the μ < 0 case
neither throws nor is documented. Meanwhile the docs page
(`docs/literate/settlement_equity.jl:300`) states the metric "may be negative on
net-earning populations" — so the two artifacts assert different conventions, and no test
pins either. A negative Gini returned silently (an "inequality" that grows more negative
with inequality) is exactly the class of silently-plausible number this module's own
honesty policy forbids elsewhere.

**Fix:** Pick one convention and make code/docstring/tests agree. Recommended: throw
`ArgumentError` on `mu < 0` (mirroring the `mu == 0` degeneracy guard), or document the
negative-output convention in the docstring and add a pinned negative-mean test.

> **Fixed** (2026-10-26, commit `cf56e2e`): adopted the docs-page convention (a throw
> would have contradicted `settlement_equity.jl`'s "may be negative on net-earning
> populations"): the `gini` docstring and the module header now document that the sign
> follows μ, reported as computed, never clipped; pinned by the hand-computed
> `gini([-3.0, -1.0]) == -0.25 == -gini([1.0, 3.0])` mirror test.

### WR-02: `λ₀` is indexed before its own length guard — raw `BoundsError`, dead validation

**File:** `src/settlement/run_inputs.jl:119-124`

**Issue:** The centralized adapter builds `λ0 = Float64[float(λ₀[t]) for t in 1:T]` *before*
checking `length(λ0) >= T`. A caller passing a too-short `λ₀` gets a raw `BoundsError`
instead of the documented loud `ArgumentError`, and the guard at lines 122-123 is dead code
(it can never fire — `λ0` is built with exactly `T` elements if indexing succeeded). This
contradicts the adapter's fail-loud `ArgumentError` contract used everywhere else. (The
ADMM adapter at lines 242-244 and `compare_tariffs` at lines 269-270 get this order right.)

**Fix:**
```julia
λ₀ === nothing || length(λ₀) >= T ||
    throw(ArgumentError("settlement_input: λ₀ has length $(length(λ₀)) < T=$T"))
λ0 = λ₀ === nothing ? Float64[λ[root, t] for t in 1:T] : Float64[float(λ₀[t]) for t in 1:T]
```

> **Fixed** (2026-10-26, commit `8768865`): the length guard now runs BEFORE the
> comprehension — a short λ₀ raises the documented `ArgumentError` naming
> `λ₀ has length N < T` (never a raw `BoundsError`); the dead post-build check is gone
> and an over-length λ₀ still truncates to T. Tests pin both the short-refusal and the
> truncation paths.

### WR-03: Price-taker battery certificate mislabels "devices but no battery" as `:ok`

**File:** `src/settlement/price_taker.jl:123-135` (condition at `:125`)

**Issue:** `:not_checked` is chosen when `isempty(ctx.agg_device_vars)` — but
`agg_device_vars` holds *all* device variables (`src/core/ModelContext.jl:53`), not battery
variables. The docstring promises "`:not_checked` when the aggregator carries no battery
vars". An aggregator with only non-battery devices (e.g. thermostatic/deferrable-only
houses in a mixed population) takes the `else` branch, `assert_battery_complementarity!`
vacuously passes over zero battery vars (`src/models/welfare_solve.jl:363-366`), and the
result reports `battery_certificate = :ok` — read downstream as "complementarity checked
and passed". In `compare_tariffs` this inflates `batt_ok` and deflates `batt_not_checked`
for mixed device sets; the tests only pin all-battery houses
(`test/test_settlement.jl:990-992`), so the mismatched case is uncertified.

**Fix:** Detect battery vars specifically, mirroring the check's own predicate:
```julia
has_battery = any(any(haskey(v, :p_ch) && haskey(v, :p_dch) for v in varlist)
                  for varlist in values(ctx.agg_device_vars))
battery_certificate = has_battery ? :ok : :not_checked   # then run the check only if has_battery
```
or correct the docstring to "no device vars" and accept the vacuous-`:ok` semantics.

> **Fixed** (2026-10-26, commit `ae7deab`): `:not_checked` now keys on the check's own
> battery predicate (`p_ch ∧ p_dch ∧ ¬q`) instead of `agg_device_vars` emptiness; a
> thermostatic-only aggregator test pins the previously mislabeled case (`:ok` →
> `:not_checked`; the docstring already promised this semantics, now the code agrees).

### WR-04: Measurement script's run-failure path never calls `ensure_schema` — promised header-only artifacts are missing exactly when specified

**File:** `scripts/tariff_comparison.jl:426-434` and `:533-543` (contract at `:238-249`)

**Issue:** On a run-level failure (`!outcome.ok`) both modes write the `"(run)"` status row
and `return nothing` — before the `ensure_schema` calls at lines 447-449 / 556-558. So
`household_bills.csv` and `equity_breakouts.csv` are never created, directly violating
`ensure_schema`'s own docstring: "an empty table is the HONEST content of a mode whose
run-level failure left zero certified rows (a missing FILE would read as 'the measurement
never ran')". Downstream, the docs page reads both CSVs unconditionally
(`docs/literate/settlement_equity.jl:251-252`), so a committed run-failure artifact set
breaks the docs build with an IOError.

**Fix:** Hoist the three `ensure_schema(...)` calls (or an `ensure_all()` helper) above the
`if !outcome.ok` branches so every exit path leaves all three files present.

> **Fixed** (2026-10-26, commit `7ab2455`): an `ensure_all_schemas()` helper now runs
> BEFORE the `!outcome.ok` branch in BOTH modes, so every exit path leaves all three
> CSVs present (header-only when nothing was certified). Script load and helper
> execution verified against the existing artifacts.

### WR-05: ADMM budget-stop detection sniffs the error message for `":converged"`

**File:** `scripts/tariff_comparison.jl:196` (used at `:174-179`)

**Issue:** `is_unconverged_guard(err) = err isa ArgumentError && occursin(":converged",
err.msg)` converts any `ArgumentError` whose message merely mentions `":converged"` into a
recorded `error:unconverged_admm` status row instead of propagating. The intended source is
`settlement_input`'s non-`:converged` refusal (run_inputs.jl:204-211), but nothing scopes
the match to that message — today or after any future message edit. A genuinely fatal
misuse `ArgumentError` that happens to reference `:converged` would be silently absorbed
into an honest-looking CSV row, defeating the script's own "misuse errors propagate and
exit nonzero" policy (header line 47).

**Fix:** Match the specific signature, e.g.
`occursin("ADMM result status is", err.msg) && occursin(":converged", err.msg)`, or better,
introduce a dedicated `UnconvergedAdmmError <: TSODSOError` in `settlement_input` and catch
it by type.

> **Fixed** (2026-10-26, commit `0e6c7ca`): the better option — a new exported
> `UnconvergedAdmmError <: TSODSOError` is thrown by `settlement_input`'s
> non-`:converged` refusal; the script catches BY TYPE (the `error:unconverged_admm`
> status row is unchanged) and the message-sniffing helper is gone. Functionally
> verified: an unrelated `ArgumentError` that merely mentions `:converged` now
> propagates and exits nonzero. Tests (`test_tsodso_errors`, `test_settlement`), the
> curated exports list, and `docs/src/status_policy.md` were updated for the new type.

## Info

### NF-01: Feasibility voltage diagnostics record `±Inf` when every non-root bus is skipped

**File:** `src/settlement/feasibility.jl:134-142, 150-151`

**Issue:** `min_v`/`max_v` start at `Inf`/`-Inf` and are only updated for non-root buses; on
a degenerate single-bus feeder the hour rows carry `min_voltage = Inf`, `max_voltage = -Inf`.
Harmless for every real fixture (the tests only assert finiteness on multi-bus feeders) but
an unhandled edge in an otherwise carefully guarded file.
**Fix:** Fall back to the root's voltage (or `NaN` with a note) when no bus is inspected.

### NF-02: Duplicate-bus aggregator stash passes the adapter's `issorted` check

**File:** `src/settlement/run_inputs.jl:130-137`

**Issue:** `issorted(buses)` accepts non-strictly-ascending stashes (e.g. `[5, 5, 9]`); the
failure then surfaces later in `build_settlement_ledger`'s `allunique` guard
(SettlementLedger.jl:215-220) with a ledger-context message instead of the adapter's
stash-specific one — a misattributed diagnostic on an otherwise loud path.
**Fix:** Add `allunique(buses) || throw(ArgumentError(...))` beside the `issorted` check.

### NF-03: `palma` at n = 1 places the same element in both groups

**File:** `src/settlement/equity.jl:204-211`

**Issue:** `n_top = n_bottom = max(1, ...)` overlap only at n = 1, where top-sum ==
bottom-sum and the ratio is exactly `1.0` regardless of the value — a benign but
undocumented small-n pin (the docstring pins n = 4 and n = 10 only).
**Fix:** Document the n = 1 → `1.0` convention (or return `NaN` for `n == 1`).

### NF-04: `revenue_neutral_flat` docstring says "one scalar level per hour"

**File:** `src/settlement/tariffs.jl:171`

**Issue:** The construction is one scalar level *overall* (identical for every hour and bus
— as the parenthetical and the return `Float64[s * p̂ for _ in 1:T]` confirm); "per hour"
contradicts the rest of the sentence and could mislead a reader comparing against the TOU
per-bin levels.
**Fix:** Reword to "one scalar level (the same flat price for every hour and bus)".

### NF-05: Case-A reconstruction tripwire checks only length and bus alignment

**File:** `scripts/tariff_comparison.jl:503-511`

**Issue:** The "cannot drift" claim is enforced by `length(houses) == length(map_rows)` and
per-index `.bus` equality only; a drift in device scales/seeded parameters would reproduce
the same bus assignment and pass silently. Cheap to strengthen.
**Fix:** Also assert `houses[k].Pdc == <map-derived expectation>` for a spot-check index, or
compare `sum(h.Pdc)` totals against `build_population`'s aggregator aggregates.

### NF-06: Docs CSV reader crashes on short rows instead of the documented NaN treatment

**File:** `docs/literate/settlement_equity.jl:177-180`

**Issue:** `Dict(header[j] => strip(cells[j]) for j in 1:min(length(header), length(cells)))`
drops keys for truncated rows; the later `r["mode"]` lookups then throw `KeyError`, although
the page promises empty/missing certified values "parse to NaN — never silently to zero".
**Fix:** Default missing cells to `""`: `get!(Dict(...))`-style merge over `header` with
`j <= length(cells) ? strip(cells[j]) : ""`.

---

_Positive verification notes (not findings):_ ledger conservation re-derived exact
(adjacent `(+a, -a)` mirror pairs, single rounded product, constructor guard); TOU bin
partition of `1:24` exact; `wholesale_payment` sequential-fold association matches the
docstring claim; `ac_feasibility_status` throw-surface is misuse-`ArgumentError`-only;
`SettlementInput` adapters guard the pinned `agr_prices[j] == dadp[row_of_j, :]` invariant
loudly; exports test covers the full settlement surface (test_exports.jl:26-32);
`is_solved_and_feasible` confirmed as JuMP API.

_Reviewed: 2026-10-26_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
