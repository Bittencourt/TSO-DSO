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
status: findings
---

# Phase 41: Code Review Report

**Reviewed:** 2026-10-26
**Depth:** standard
**Files Reviewed:** 14
**Status:** findings

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
