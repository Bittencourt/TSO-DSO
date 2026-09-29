---
phase: 27-integer-planning-pricing-certificate-correctness
reviewed: 2026-09-29T12:40:42Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - src/experiments/mpc_loop.jl
  - src/models/exactness.jl
  - src/models/welfare_solve.jl
  - src/planning/benders.jl
  - src/planning/subproblem.jl
  - src/planning/follower.jl
  - src/powerflow/ACPowerFlow.jl
  - src/powerflow/ConvexBranchFlow.jl
  - src/pricing/dlmp.jl
  - src/pricing/fit.jl
  - scripts/repro_stability_check.jl
  - test/test_planning_certification_integer.jl
  - test/test_exactness.jl
  - test/test_mpc_loop.jl
  - test/test_fit.jl
findings:
  critical: 2
  warning: 3
  info: 0
  total: 5
status: issues_found
---

# Phase 27: Code Review Report

**Reviewed:** 2026-09-29T12:40:42Z
**Depth:** standard
**Files Reviewed:** 15 (of 20 listed in `<required_reading>`; `docs/literate/pricing_dlmp.jl`,
`test/test_dlmp.jl`, `test/test_planning_oracle.jl`, `test/test_pricing_dlmp.jl`,
`test/test_pricing_fit.jl`, `test/test_stochastic_welfare.jl`, `test/test_thesis_repro.jl` were
not opened this pass — see Summary)

## Summary

Reviewed the Phase 27 diff against `6f9e24e` for the five FIX items: the T>1 Kelley
cutting-plane recourse (FIX-06), the hybrid SOCP exactness floor (FIX-08), the DLMP
`cone`/`drop` rename + deprecation shim (FIX-07), the FIT-baseline AC settlement + bounded
`ALMOST_OPTIMAL` fallback (FIX-09), and the MPC truth-settled AC physics-only settlement
(FIX-10).

`assert_socp_exact!`'s hybrid floor (FIX-08) is carefully derived, measured, and the
orientation-agnostic head-branch lookup is directly tested for both storage orientations —
this is solid work. The DLMP rename (FIX-07) is well-scoped with a working deprecation shim.

Two BLOCKER-level correctness defects were found, both in code paths the phase's own
documentation says are "CONFIRMED to occur" or are load-bearing for the phase's stated goal,
and both are **not exercised by any test in the suite** (confirmed by direct search):

1. `_corner_recourse_joint`'s (benders.jl, FIX-06) anti-stall bisection guard does not
   actually make progress when the bisection midpoint is *also* oracle-infeasible with no
   Farkas certificate — it deterministically re-proposes the identical futile trial every
   remaining iteration and burns the entire `iters` budget before raising a generic
   "exhausted iterations" error.
2. `run_mpc`'s (mpc_loop.jl, FIX-10) truth-settlement PV clip only clips the *charging* power
   `p_ch` to the device's true PV availability — it does **not** clip `pv_used` (the
   self-consumed/exported PV, which is what actually feeds `p_inject`/`realized_welfare`'s net
   injection). Under `fe.pv_factor > 1`, `realized_welfare` can be credited with PV energy
   that does not physically exist, which is exactly the class of bug FIX-10 was created to
   close.

Three WARNING-level items concern a type/shape-breaking change to `decompose_dlmp`'s return
value, an arbitrary head-branch choice on meshed feeders with multiple root-incident branches,
and the single-shot (non-iterative) nature of the T>1 stall bisection even on its "working"
branch.

Given the two BLOCKER findings and their bearing on this phase's own stated correctness goals
(T>1 recourse robustness, truth-settled realized welfare), status is `issues_found`.

## Critical Issues

### CR-01: `_corner_recourse_joint`'s double-infeasible stall guard makes no progress and wastes the entire iteration budget

**File:** `src/planning/benders.jl:386-409`

**Issue:** In the T>1 Kelley cutting-plane loop, when a trial `z_next` is oracle-infeasible
with no Farkas certificate (`r.feas_cut === nothing`, i.e. `solve_planning_oracle!` threw), the
code checks whether the SAME trial repeated from the previous iteration
(`last_skipped !== nothing && maximum(abs, z_next .- last_skipped) <= 1e-9`, line 392) and, if
so, evaluates one bisection midpoint `z_mid = (z_next .+ z_best) ./ 2` (line 393).

If that midpoint is *itself* oracle-infeasible with no certificate too (the `elseif
r_mid.feas_cut !== nothing` branch at line 401 does not match, and the `isfinite(r_mid.Qz)`
branch at line 395 does not match either), **nothing is added to `cuts` or `feas_cuts`** — no
new information reaches the small cutting-plane master LP. `last_skipped` is then set to
`copy(z_next)` (line 408) — the SAME value it already held. On the next outer iteration the
small master LP is rebuilt from an *unchanged* cut set, so it deterministically re-proposes the
identical `z_next` (HiGHS's simplex is deterministic on an unchanged LP with no warm start
carried over — the model is rebuilt fresh every iteration, line 356). This reproduces the exact
same "stall" condition, computes the exact same `z_mid` (since neither `z_next` nor `z_best`
changed), gets the exact same oracle-infeasible-no-certificate result, and repeats — for every
remaining iteration up to `iters` (default 100) — with `UB`/`LB` frozen at their prior values
(no new cuts touch the master, so `LB` cannot move either). The loop then falls through to the
generic `error("...exhausted $iters iteration(s)...")` at line 418, having made zero progress
after the stall was first detected.

The function's own docstring (lines 250-275) documents this scenario as "CONFIRMED to occur on
realistic non-separable battery fixtures whenever the follower-feasible box extends beyond what
the network can physically accept" — i.e. this is not a hypothetical edge case, it is a
documented production occurrence. No test in the suite exercises this path: grepping the test
suite for any exercise of `_corner_recourse_joint`'s stall/oracle-infeasible branches returns
nothing, and the one T>1 `@testitem`
(`test/test_planning_certification_integer.jl:596-649`) only samples `y_inv ∈ {0.5, 1.5}` on a
fixture whose follower deliverable capacity is `4.0` — comfortably above both tested `y_inv`
values, so the oracle-infeasible branch is never reached by that test at all. Likewise
`test_planning_benders_integer.jl` only exercises `T=1` end-to-end. The mechanism that this
docstring claims handles a "genuine, CONFIRMED" production stall is therefore both buggy and
completely untested.

**Fix:** Either (a) make the bisection genuinely iterative — keep halving between the
last-known-feasible anchor and the stalled trial until a new cut (of either kind) is produced
or a small max-depth is exhausted, updating `z_next`/`last_skipped` to the new midpoint each
sub-iteration so the loop doesn't reconverge on the identical point; or (b) on a
double-infeasible midpoint, force a *feasibility*-only sub-bisection that only ever moves toward
the guaranteed-feasible anchor `z_best` by a shrinking fraction (never landing back on
`z_next`'s own value on the next outer pass) and record enough state so a diagnostic
`error(...)` clearly distinguishes "stalled, no progress possible" from "gap not yet met". Add a
`@testitem` that drives `_corner_recourse_joint` on a fixture measured to hit this exact branch
(e.g. a `y_inv` large enough that the oracle genuinely goes infeasible partway across the
hypercube on the T=2 PVBattery fixture already in
`test/test_planning_certification_integer.jl`) so the fix is regression-locked.

### CR-02: MPC truth settlement clips PV charging but not PV self-consumption/export, understating the correction FIX-10 exists to make

**File:** `src/experiments/mpc_loop.jl:539-564`

**Issue:** FIX-10's stated purpose (see the `realized_welfare` docstring, lines 116-124, and
27-CONTEXT.md's "realized PV clips charging" decision) is to settle realized welfare against
the TRUE, unperturbed plant rather than the forecast-perturbed one the window optimized under.
The window's own `pv_used[t]` variable is bounded by `Ppv_param[t]`
(`src/devices/PVBattery.jl:307-308`), which `run_mpc` sets to the *forecast-perturbed* PV
(`d.Ppv[t+τ-1] * fe.pv_factor`, `mpc_loop.jl:438`). When `fe.pv_factor > 1` (the window believes
MORE PV is available than truly is), the window is free to push `pv_used` up to that inflated
bound — and since PVBattery's own `p_inject = pv_used - p_ch + p_dch`
(`src/devices/PVBattery.jl:349`) feeds directly into net grid injection, an inflated `pv_used`
directly inflates the reported net injection.

The truth-settlement code:

```julia
p_ch_true = min(value(v.p_ch[τ_apply]), d.Ppv[abs_hour])   # line 544 — clipped to TRUE PV
p_dch1 = value(v.p_dch[τ_apply])
pv_used1 = value(v.pv_used[τ_apply])                        # line 546 — NOT clipped
realized_welfare += _mpc_pvbattery_utility(d, p_ch_true, p_dch1)
...
net_p += pv_used1 - p_ch_true + p_dch1                      # line 564
```

only clips `p_ch` (the charging power) to the device's TRUE `d.Ppv[abs_hour]`. It leaves
`pv_used1` — the window-solved, potentially forecast-inflated self-consumption/export amount —
completely unclipped, and feeds it straight into `realized_net_p[agg.bus]`
(line 625: `realized_net_p[agg.bus] = net_p - agg.Pdc[abs_hour]`), which is then FIXED as the
injection for the AC truth power-flow settlement (`_mpc_truth_import_acpf`, lines 653-660). The
AC truth solve treats this as a hard numeric input — it has no way to know `pv_used1` exceeds
the true available PV, and the resulting `p_import_true` (and hence `realized_welfare`, line
674) is credited with energy that the true plant cannot physically supply.

Confirmed against `test/test_mpc_loop.jl:52-93` ("forced-PV-shortfall ... FIX-10"): this is the
one test that exercises `fe.pv_factor != 1`, and its only assertion is
`!isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-9)` — a weak "something
changed" check that passes identically whether the clip is fully correct or only half-applied as
here. There is no assertion anywhere that bounds `realized_welfare`/`p_import_true` against the
TRUE PV availability.

**Fix:** Clip `pv_used` to the true PV availability the same way `p_ch` is clipped, e.g.
`pv_used_true = min(pv_used1, d.Ppv[abs_hour])`, and use `pv_used_true` (not `pv_used1`) in the
`net_p` accumulation on line 564. Note `p_ch_true <= pv_used_true` must still hold (the PVBattery
model's own `p_ch <= pv_used` invariant) — since `p_ch_true = min(p_ch, TruePV)` and
`pv_used_true = min(pv_used, TruePV)` and the window already enforces `p_ch <= pv_used`, this
holds automatically. Add an assertion or test that drives `fe.pv_factor > 1` and directly checks
that the truth-settled net PV contribution never exceeds `d.Ppv[abs_hour]`.

## Warnings

### WR-01: `decompose_dlmp`'s return type changed from `NamedTuple` to a custom struct with a different field order

**File:** `src/pricing/dlmp.jl:250-277` (vs. pre-Phase-27 `NamedTuple(energy, loss, congestion,
voltage, reactive, total)`)

**Issue:** Before this phase, `decompose_dlmp` returned a plain `NamedTuple` with field order
`(energy, loss, congestion, voltage, reactive, total)`. FIX-07 replaces this with a new
`DlmpDecomposition` struct whose field order is `(energy, cone, drop, congestion, reactive,
total)` — note that position 3 was `congestion` and is now `drop`, and position 4 was `voltage`
and is now `congestion`: the congestion/voltage(drop) pair is **transposed**, not just renamed,
relative to the old positional order. Any consumer that destructured the old NamedTuple
positionally, or called `Tuple(nt)`/`values(nt)`/`collect(nt)` on it (all valid, idiomatic
operations on a `NamedTuple` that are NOT valid — they simply error — on a plain `struct`) would
silently receive `congestion` where it expected `voltage`/`drop` or vice versa if such a call
site existed and were adapted mechanically (e.g. `values(x)` still works after generically
swapping `NamedTuple(...)` for `DlmpDecomposition(...)` only if field-name access is used
throughout). A grep of the tree found no current positional/NamedTuple-semantics consumer (all
found call sites use named field access, `.loss`/`.voltage`/`.cone`/`.drop`/`.congestion`), so
no *currently shipped* breakage was found, but this is a type AND positional-order breaking
change for any external/future consumer that treated the return value as an ordinary
`NamedTuple` (a reasonable thing to have done, since it always was one before this phase) rather
than through named-field access only.

**Fix:** Document this as a breaking change in the phase's release notes / CHANGELOG (not found
in the reviewed files), and/or add a `Base.propertynames`/`NamedTuple(::DlmpDecomposition)`
conversion method so existing "duck-typed as a NamedTuple" call sites keep working. At minimum,
grep any downstream repo/notebook that may consume `decompose_dlmp` positionally before this
ships.

### WR-02: `assert_socp_exact!`'s interior-branch reference scale is an arbitrary choice on a meshed feeder with multiple root-incident branches

**File:** `src/models/exactness.jl:181-211`

**Issue:** For an interior/unlimited branch, `ref_b` falls back to
`value(pv.P[head_b,t])^2 + value(pv.Q[head_b,t])^2` where `head_b` is the FIRST branch found
(by array index) satisfying `br.from == feeder.root || br.to == feeder.root` (line 204,
`findfirst`). The docstring explicitly acknowledges a meshed feeder's root can "legitimately fan
out to more than one branch" (line 198-203) and documents that the code deliberately does not
require uniqueness, taking the first match. However, if two root-incident branches carry very
different flow magnitudes (a plausible meshed-feeder scenario — e.g. an unevenly split load),
the arbitrary "first" branch's own `P²+Q²` may significantly under- or over-state the network's
actual flow scale for OTHER interior branches referencing it, making the exactness floor's
protective strength depend on the feeder's branch STORAGE ORDER rather than on physics. The
existing test coverage for the orientation-agnostic lookup
(`test/test_exactness.jl:184-260`) uses a linear 3-bus chain with only ONE root-incident branch
per orientation — it certifies orientation-invariance, not multi-root-branch scale-choice
robustness. `test_mesh_angle_certificate.jl`'s 4-bus diamond (cited in the docstring as the
"currently-passing" precedent for tolerating multiple root branches) is not exercised against
`assert_socp_exact!`'s hybrid floor at all — it is used for a different (angle) certificate.

**Fix:** Either measure and document that the chosen head branch's flow magnitude is always
representative on the project's actual meshed fixtures (i.e. establish this is a non-issue in
practice), or make `ref_b` for an interior branch use e.g. `sum`/`max` of every root-incident
branch's own `P²+Q²` so the floor is not order-dependent. Add a regression test on a meshed
feeder where the two root branches carry deliberately disparate flow magnitudes to pin the
intended behavior.

### WR-03: T>1 stall bisection is single-shot even on its "working" branch

**File:** `src/planning/benders.jl:392-407`

**Issue:** Independent of CR-01's double-infeasible failure mode, even when the FIRST bisection
attempt succeeds (finite `Qz` or a feasibility certificate at `z_mid`), the mechanism only ever
performs exactly ONE bisection step per detected stall — it is not a genuine iterative bisection
search that narrows toward a feasible boundary over several halvings. This is a much weaker
recovery than the docstring's framing ("bisect toward the guaranteed-feasible incumbent")
suggests, and it means a fixture whose true feasible/infeasible boundary requires more than one
halving to resolve will still eventually hit CR-01's failure mode after the single successful
bisection is exhausted (the next stall detected against the new `z_next` has no further
halving to fall back on beyond another single `(z_next + z_best)/2`, which is fine only if that
one step is enough).

**Fix:** Consider folding this into CR-01's fix (a genuinely iterative bisection loop bounded by
a small max-depth) rather than treating "one bisection, then rely on the outer loop's `iters` to
paper over the rest" as sufficient.

---

_Reviewed: 2026-09-29T12:40:42Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
