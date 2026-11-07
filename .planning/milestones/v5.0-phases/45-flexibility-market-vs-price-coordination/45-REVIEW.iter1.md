---
phase: 45-flexibility-market-vs-price-coordination
reviewed: 2026-11-05T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - src/coordination/coordination.jl
  - src/coordination/flex_bids.jl
  - src/coordination/flex_clear.jl
  - src/coordination/flex_settle.jl
  - src/settlement/comparison.jl
  - src/settlement/run_inputs.jl
  - src/settlement/SettlementLedger.jl
  - src/TSODSO.jl
  - scripts/tariff_comparison.jl
  - docs/literate/flex_market.jl
  - docs/make.jl
  - docs/src/api.md
  - scripts/README.md
  - test/test_flex_market.jl
  - test/test_flex_market_fence.jl
  - test/test_flex_market_ieee.jl
  - test/test_flex_market_ieee123.jl
  - test/test_exports.jl
  - test/expected_broken.txt
findings:
  critical: 1
  warning: 6
  info: 8
  total: 15
status: issues_found
---

# Phase 45: Code Review Report

**Reviewed:** 2026-11-05
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

I reviewed the flexibility-market legs against the phase contract. The contract covers exact
ledger conservation, the dual sign, pay-as-bid quantities, β affecting money only, the
default-path fence, guards before any solve, statuses instead of throws, social welfare with
the like-for-like gap, non-vacuous tests, `@testitem` scoping, and measured tolerances. I did
not run Julia. Every finding below comes from reading the code and the committed CSVs.

**What holds:**

- **Conservation.** Flow (e) is an adjacent `(:aggregator, bus) <-> :dso` mirror pair.
  `ledger_residual == 0.0` therefore holds by induction, for both rules and for every β.
- **Sign conventions.** They agree everywhere. The aggregator earns `price·quantity`, up-flex
  is positive, and pay-as-bid down rows are `(g_k, −w_k)`.
- **Clearing price.** It is read through `settlement_input(ctx2)`, which is the same
  `extract_dlmp` convention as the DADP leg.
- **Pay-as-bid rows.** Their quantities sum to Δ by construction.
- **β.** It only appends phantom rows on a physics record shared through the
  `(baseline_tariff, n_blocks)` cache.
- **Default path.** `flex_market = nothing` returns before any flex code runs, and
  `flex_payments = nothing` adds no rows.
- **Committed CSVs.** They match the script's contract:
  - no duplicate upsert keys in any of the three tables;
  - the 34 `FLEX_EXTRA_COLUMNS` and `run_wall_s` are appended after the base columns;
  - β rows have identical physics columns.
- **Test scoping.** I found no soft-scope traps.

**What breaks:**

- **One BLOCKER.** Several inputs are refused only after every solve has run: a power-flow
  formulation other than ConvexBranchFlow, a non-positive λ₀, or a failure of the DLMP
  split's reconstruction check. These throw from `_congested_hours` after the DADP run, all
  four base legs, stage 1, bid probing and stage 2. That breaks both "guards fire before any
  solve" and "statuses are reported, never thrown". It also throws away the whole
  `compare_tariffs` result, base rows included.
- **Six warnings:**
  - one more late guard;
  - an untested pay-as-bid invariant;
  - an unjustified claim that the delivery penalty is exact;
  - stale rows in the script's upserts;
  - an IEEE-123 smoke test whose catch is too broad;
  - a diagnostic re-solve whose failure throws away a valid clear.

## Critical Issues

### CR-01: Formulation and λ₀ preconditions fire only after every solve, and the DLMP split's reconstruction check is never mapped to a status

**File:** `src/coordination/flex_clear.jl:353-358` and `:641`; `src/settlement/comparison.jl:363-419`; `src/coordination/flex_settle.jl:314-335`

**Issue:** `_congested_hours` runs only after stage 2 succeeds. It calls `decompose_dlmp(ctx2)`,
which can throw in three ways that are not solver outcomes:

1. **Wrong formulation.** `decompose_dlmp` throws `ArgumentError` when `ctx2` lacks the
   ConvexBranchFlow handles (`:cone`, `:vdrop`, `:cpydrop`, `:smax`; see `src/pricing/dlmp.jl:327-335`).
   `compare_tariffs` and `clear_flex_market` take any `pf::AbstractPowerFlow`, and
   `LinDistFlow`, `DCPowerFlow`, `RestrictedBranchFlow` and `ACPowerFlow` all exist. A flex
   call with any of them runs everything else first and then throws.
2. **Non-positive λ₀.** `_congested_hours` itself throws `ArgumentError` when any `λ₀[t] <= 0`
   (lines 355-357). The front guards check only the length (`compare_tariffs`, line 363) and
   finiteness (`_flex_physics`, line 595). Zero or negative wholesale hours are a legitimate
   research input, for example PV-surplus days, and with `flex_market` they crash the
   comparison at the very end.
3. **Reconstruction failure.** The split's sum-to-price check uses `error(...)`
   (`dlmp.jl:412`), which raises an `ErrorException`. Nothing maps it, so a borderline stage-2
   solve that passed the exactness gate can still abort the run.

In `compare_tariffs` all three happen after the DADP run, the flat, TOU and FIT legs, stage 1
and bid probing. The flex phase took 126 s on IEEE-123, out of 215.6 s for the whole
comparison. `_flex_tables` runs inside the single `compare_tariffs` call, so the exception
discards the base rows as well. `scripts/tariff_comparison.jl:run_compare_outcome` then
rethrows it, so nothing is written. The `_flex_physics` docstring (lines 573-575) lists its
guards "before any solve" and omits both preconditions.

**Fix:** validate the preconditions up front, and turn the post-solve classifier into a status.

```julia
# in _flex_physics, with the other guards (and mirrored in compare_tariffs' flex block and
# clear_flex_market, before any solve):
pf isa ConvexBranchFlow || throw(ArgumentError(
    "_flex_physics: the flexibility market needs ConvexBranchFlow (the congested-hour " *
    "split reads its :cone/:vdrop/:cpydrop/:smax duals); got $(typeof(pf))."))
all(>(0), λ) || throw(ArgumentError(
    "_flex_physics: λ₀ must be positive in every hour (it normalises the congestion score)."))

# around the classifier, after stage 2:
ch = try
    _congested_hours(rd.ctx2::ModelContext, λ; T = T)
catch err
    err isa ErrorException || rethrow()
    return _physics_record(; status = "error:dlmp_split", notes = first(err.msg, 400), known...)
end
```

If non-positive λ₀ must be supported, normalise by `max(abs(λ₀[t]), eps)` instead of refusing.
Add a test that pins `@test_throws ArgumentError` for `LinDistFlow()` with a counting
optimizer that reports zero calls, the same pattern as
`test_flex_market_fence.jl:327-373`.

## Warnings

### WR-01: An aggregator vector that is complete but unsorted passes the `clear_flex_market` guard, then throws after stage 1 and bid probing

**File:** `src/coordination/flex_settle.jl:317-323`; `src/coordination/flex_clear.jl:193-198`

**Issue:** `clear_flex_market` checks `sort(agg_buses) == input.buses`, so the check accepts
any permutation. `_stage2_aggregators` then requires `issorted([a.bus for a in aggs])` and
throws `ArgumentError`. It only gets there after `price_taker_dispatches` and `flex_bids`
have run for every aggregator, which is about 241 QP solves per aggregator at T = 24, K = 4.
`compare_tariffs` has the same gap on any engine path whose settlement does not already
enforce ascending order. The docstring says the bus check happens "before any solve".

**Fix:** in `clear_flex_market`, and in the `compare_tariffs` flex block, use
`agg_buses == input.buses` with a message that names the ascending-order requirement. You
could also sort `aggs` by bus once at entry and carry the permutation.

### WR-02: The pay-as-bid quantity invariant is never tested, and the pay-as-bid price assertion is weak

**File:** `test/test_flex_market.jl:1160-1170`

**Issue:** The review contract asks that "the pay-as-bid payments add up to Δ". The
`_flex_payment_rows` docstring states it too: "the row quantities of each hour sum to its Δ".
No test asserts it. `grep quantity` over the flex tests finds only the uniform check
(`r.quantity == Δ[r.t]`, line 1159) and the β phantom.

The pay-as-bid price check is also weak:
`r.price in fb.up_m[r.t, :] || r.price in fb.dn_g[r.t, :]`.

- An up row priced at a down value would pass.
- So would a row priced at the wrong block index.
- So would a block whose price was stored as `0.0` for an absent block, since `0.0` is in
  `up_m` whenever any block is absent.

So the pay-as-bid money is not checked against `Σ_k m_k·u_k − Σ_k g_k·w_k`.

**Fix:** inside the existing `check`/loop:

```julia
for t in 1:M.T_INT
    q = sum(r.quantity for r in p.payment_rows if r.t == t; init = 0.0)
    @test abs(q - p.physics.Δ[1][t]) <= <measured 3x>   # or == if the measured max is 0.0
end
fb, u, w = p.physics.bids[1], p.physics.u[1], p.physics.w[1]
expect = sum(fb.up_m .* u) - sum(fb.dn_g .* w)
@test abs(p.flex_payments_total - expect) <= <measured 3x>
```

### WR-03: The claim that the delivery penalty is exact is not justified, so the shortfall may be partly a penalty artefact

**File:** `src/coordination/flex_clear.jl:381-385`, `:559-563` and `:658`

**Issue:** The weight is `10·max(max|π|, max λ₀, max|p|)`, and the docstring says this makes
"the L1 penalty [exceed] every tracking multiplier". The multiplier of
`pag[t] == target[t]` is the device's marginal utility at the target minus the tariff. That is
bounded by the slope of the value function at the target, not by any price in play.

- **Steep utilities.** At a target near the edge of the jointly reachable set, the slope can
  be far above 10× the largest price: a steep quadratic `Interruptible` near `Pmin`, or a
  thermostatic comfort band.
- **Coupled devices.** Hour-separable bids put targets exactly where coupled devices are
  stiffest, so the multiplier can be large there.

When the weight falls below the multiplier, the delivered dispatch moves away from a target
the devices could reach, and the shortfall is attributed to hour separability. The 10w column
can detect this but cannot rule it out. Section 8 of `docs/literate/flex_market.jl` turns the
stable 10w value into the conclusion "structural hour-separability loss", which rests on this
claim.

**Fix:**

- Either drop the guarantee from the docstrings and state the weight as a documented heuristic
  whose adequacy the 10w column measures;
- or compute a sufficient weight per aggregator: for example
  `10·max(maximum(up_m), maximum(dn_g), max|π|, max|p|)` from the bids, plus a bound on the
  device marginal utility. Alternatively, raise the weight until
  `shortfall(w) == shortfall(10w)` within a measured tolerance and report the weight used.

### WR-04: Script upserts leave stale `(run)` and flex rows next to fresh rows, and the CSV test accepts the mix

**File:** `scripts/tariff_comparison.jl:535-561`, `:878-918`, `:930-1000`; `test/test_flex_market_ieee.jl:93-108`

**Issue:** The upsert key is `(mode, tariff, seed, t_horizon)`, so a row is only replaced by a
row with the same tariff. Three cases leave contradictory artifacts:

1. **A `(run)` row survives a later success.** A `--record-timeout` or refusal row for
   `ieee123` or `ieee123-default` stays after a later successful run, because no
   `"(run)"`-keyed row replaces it.
2. **Ok rows survive a later refusal.** A later refusal adds a `(run)` row beside the previous
   ok rows.
3. **Flex rows from an older run survive a base-only run.** `--mode ieee123` without
   `--flex-market` overwrites the base rows but leaves the flex rows of an earlier run. Those
   rows may come from different code or a different solver.

The ieee13-ground flex path guards against mixing provenance with `assert_dadp_reproduces`.
The IEEE-123 paths have no such guard.

The fast CSV test asserts `(t123 == Set([...])) || ("(run)" in t123)`. Any table that contains
a `(run)` row passes, whatever else it holds.

**Fix:** in `write_mode_outcome` and `record_timeout_main`, delete every existing row of the
same `(mode, seed, t_horizon)` from all four tables before upserting, since a run of an
IEEE-123 mode owns all of its rows. Alternatively, on an ok outcome delete that mode's `(run)`
row, and on a refusal delete its leg rows. In the test, make the two cases exclusive:
`t123 == Set([...]) || t123 == Set(["(run)"])`.

### WR-05: The IEEE-123 smoke test treats any `SolveFailedError` or `CertificateError` as a DADP refusal and passes with zero flex assertions

**File:** `test/test_flex_market_ieee123.jl:20-42`, `:55-58`

**Issue:** The `try` wraps the whole `compare_tariffs` call. Other legs can raise these error
types too:

- the flat and TOU legs, through `price_taker_dispatches` and `assert_solved!`, which throws
  `SolveFailedError`;
- any future regression that lets a flex-leg solver error escape.

Each of these gets recorded as "DADP refused (a recorded outcome)". The `else` branch then
re-asserts the type it just caught, which is a tautology. The test passes with no flex
coverage at all. The header says "A DADP refusal is accepted only as one of the two
documented refusal classes", but the test does not tell a DADP refusal apart from any other.

**Fix:** run the DADP solve first, separately, with the same optimizer. Catch only around that
solve, then call `compare_tariffs` outside any `try`. Or check that the caught error's message
or kind identifies the DADP exactness gate (`err isa CertificateError && err.kind === :socp_exact`).

### WR-06: A failed diagnostic 10w delivery throws away a successful clear

**File:** `src/coordination/flex_clear.jl:659-681`

**Issue:** The second delivery, at ten times the weight, exists only to produce
`shortfall_10w_total`, a sensitivity number. It sits in the same `try` as the primary
delivery. If any one of those `2·n` extra re-solves throws `SolveFailedError`, the whole leg
becomes `error:SolveFailedError` with "delivery: ". The valid primary delivery is then
discarded: no ledger, no welfare, no AC verdict. A higher weight makes the QP worse
conditioned, so this failure is more likely than a failure of the primary delivery.

**Fix:** compute the primary delivery in its own `try`. Run the 10w pass separately, and on a
solver outcome record `shortfall_10w_total = missing` plus a note, not a failed leg.

## Info

### IN-01: Infeasibility mapping misses near-infeasible termination codes

**File:** `src/coordination/flex_clear.jl:221-231`

Only `INFEASIBLE` and `INFEASIBLE_OR_UNBOUNDED` map to `infeasible_redispatch`.
`ALMOST_INFEASIBLE` and `LOCALLY_INFEASIBLE`, both of which an interior-point method can
return when the offered flexibility is insufficient, become a generic `error:SolveFailedError`.
Map them too, or record the termination status in `notes`; currently it is there only through
the message text. (The committed IEEE-13 TOU legs ended `ALMOST_OPTIMAL`, which is correctly
not infeasibility, so they need no change.)

### IN-02: `FLEX_RANGE_FLOOR` is used for three different thresholds

**File:** `src/coordination/flex_settle.jl:61`, `:141`; `src/settlement/comparison.jl:1193`

`FLEX_RANGE_FLOOR` is documented as the smallest offered bid range, set by noise in the probe
secants. It is reused as the accepted-block threshold in `_marginal_up_price`, as the
up-activation threshold for the β phantom, and as the activation filter of
`price_gap_vs_dadp_max`. Those quantities have their own noise level: rejected blocks come
back at about 1e-9. Give them a separately named and measured constant, or document the reuse.

### IN-03: A failed baseline value solve offers zero flexibility without changing the status

**File:** `src/coordination/flex_bids.jl:327-329`

When `V0` fails, `flex_bids` returns all-zero widths. Stage 2 then runs with that aggregator
offering nothing. The leg can come out `ok`, or `infeasible_redispatch` ("the offered
flexibility cannot restore feasibility"), while the real cause is a bid-generation failure,
visible only in `n_probe_failed`. Consider a distinct status, or a note, when any aggregator's
`V0` is `NaN`.

### IN-04: The FixedCapacitor guard is duplicated

**File:** `src/settlement/comparison.jl:410-418`

It re-implements `_refuse_fixed_capacitor` (`flex_clear.jl:155-168`) with a different message.
Call the helper with `"compare_tariffs"` as the `who` argument. The capacitor test only needs
the `"compare_tariffs"` prefix in the message.

### IN-05: Some assertions are tautological

**File:** `test/test_flex_market.jl:934-938`, `:1120`

`battery_certificate[1] in (:ok, :refused, :not_checked)`, the three counts summing to 1, and
`feasibility.status in (:feasible, :infeasible, :solve_failed)` cannot fail for any value the
code can return. They are harmless, but they inflate the assertion count. Replace them with
real expectations where one exists. For example, the coupled fixture's measured delivered
certificate.

### IN-06: The literate page depends on the script's text layout

**File:** `docs/literate/flex_market.jl:346-355`

`script_ieee123_lambda0` parses `scripts/tariff_comparison.jl` and `Core.eval`s the
right-hand side of a one-line `ieee123_lambda0() = ...` definition. Reformatting it as a
`function` block breaks the docs build. Move the profile into a small shared data file, or a
`TSODSO` internal, that both the script and the page read.

### IN-07: The `π` local shadows `Base.π`

**File:** `src/coordination/flex_clear.jl:490`, `:640`; `src/coordination/flex_settle.jl`

Using `π` as the clearing-price local, and as a record field, shadows the constant. It is
legal, but it invites a silent bug the first time someone writes `2π` in these files. Use
`clearing` or `πc`.

### IN-08: IEEE-13 bids are probed around a baseline whose battery certificates were all refused

**File:** `results/settlement_comparison/tariff_comparison.csv` (ieee13-ground flex rows, `baseline_batt_refused = 10`)

Every IEEE-13 stage-1 baseline refused battery complementarity, meaning simultaneous charge
and discharge. Bids are therefore secants of a value function evaluated around a non-physical
battery schedule, while the leg status is `ok`. This is reported and follows policy. The
literate page, however, quotes `baseline_batt_refused` only for IEEE-123 (section 10). State
it for IEEE-13 as well, since it qualifies every IEEE-13 bid price.

---

_Reviewed: 2026-11-05_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
