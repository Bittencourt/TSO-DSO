---
phase: 26-network-device-model-correctness
reviewed: 2026-09-29T02:44:07Z
depth: standard
files_reviewed: 41
files_reviewed_list:
  - src/admm/DsoOpt.jl
  - src/admm/solve_admm.jl
  - src/devices/AbstractDevice.jl
  - src/devices/Aggregator.jl
  - src/devices/Deferrable.jl
  - src/devices/FourQuadBESS.jl
  - src/devices/Interruptible.jl
  - src/devices/PVBattery.jl
  - src/devices/Thermostatic.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run.jl
  - src/models/linear_solve.jl
  - src/models/mpc_window.jl
  - src/models/stochastic_welfare.jl
  - src/models/welfare_solve.jl
  - src/powerflow/ACPowerFlow.jl
  - src/powerflow/ConvexBranchFlow.jl
  - src/powerflow/RestrictedBranchFlow.jl
  - src/pricing/dlmp.jl
  - docs/literate/convex_branch_flow.jl
  - test/fixtures_phase23.jl
  - test/fixtures_phase6.jl
  - test/test_ac_powerflow.jl
  - test/test_admm_knifeedge_canary.jl
  - test/test_admm_reactive.jl
  - test/test_aggregator.jl
  - test/test_convex_branch_flow.jl
  - test/test_device.jl
  - test/test_exactness_verdict.jl
  - test/test_fourquadbess.jl
  - test/test_mpc_terminal.jl
  - test/test_pricing_dlmp.jl
  - test/test_pvbattery.jl
  - test/test_restricted_branch_flow.jl
  - test/test_thesis_repro.jl
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 26: Code Review Report

**Reviewed:** 2026-09-29T02:44:07Z
**Depth:** standard
**Files Reviewed:** 41 (all files in `<required_reading>`; `docs/literate/meshed_reactive_price.jl`,
`docs/literate/prosumer_welfare.jl`, and the remaining `test_*.jl` files listed in
`<required_reading>` were skimmed but not individually cited below)
**Status:** issues_found (no BLOCKER-level defects found; several WARNING/INFO findings)

## Summary

This review traced the mathematically load-bearing changes of phase 26 by hand:

- The `cpydrop`/`Prev`/`Qrev` sign flip in `ConvexBranchFlow.jl` (FIX-01/02): re-derived the
  telescoping-sum argument independently for both the default (`a = −1`) and
  `thesis_literal = true` (`a = +1`) branches. Both reproduce the file's own documented
  `(1 + 2a)·Σ(r²+x²)l` formula exactly, confirming `v̂ ≥ v` under the default and `v̂ ≤ v` under
  the literal opt-in. No sign or coefficient error found.
- The receiving-end cone (thesis 3.37) in both `ConvexBranchFlow.jl` and `ACPowerFlow.jl`:
  confirmed `Prev`/`Qrev` (`P − r·l`, `Q − x·l`) are shared between `cpydrop`'s default branch
  and the new `:smax_rev` cone, gated by the identical `B[b].smax < _SMAX_NO_LIMIT` filter as
  `:smax`, and independently exercised by a dedicated PV-back-feed regression in
  `test_convex_branch_flow.jl` (`mag_rev > 100·mag_fwd`) and mirrored in `test_ac_powerflow.jl`.
  Correct.
- `soc[1:T+1]` recursion + terminal handling in `PVBattery`/`FourQuadBESS`: the whole-horizon
  recursion, the `soc_terminal` keyword's three branches, and `mpc_window.jl`'s retargeted
  `soc[H+1]`/`soc_da[t+H]` indexing were all cross-checked against `run_mpc`/`test_mpc_terminal.jl`
  and are internally consistent (including the removal of the old `H == 1` guard, which is now
  structurally unnecessary rather than silently dropped).
- The `q = p·tanφ` roll-up (FIX-05) in `Aggregator.jl`: verified the sign (`res.p_inject[t]` is
  already negative for a consuming device, so `q_inject[t] += res.p_inject[t]*tanφ_d` yields a
  negative/withdrawing reactive contribution, matching the existing `−Pdc·tanφ` convention) and
  that `FourQuadBESS`'s `q_inject` and the flexible-load `tanφ` term are mutually exclusive
  (`is_flexible_load(::FourQuadBESS)` is not overridden, so it stays `false`).
- DLMP sign conventions in `dlmp.jl`: `extract_dlmp`/`decompose_dlmp`'s PF-04 refusal gate, the
  `:smax_rev` congestion term added in plan 26-10, and the hard sum-to-nodal-price assertion were
  traced through; the assertion is a genuine correctness net (a mis-signed or dropped component
  produces an `O(price)` residual, not a silent pass).
- Name-collision / multi-instance registration: confirmed `stochastic_welfare.jl`'s
  `JuMP.unregister` list includes all twelve names `ConvexBranchFlow.contribute!` now registers
  (`:Prev`/`:Qrev`/`:smax_rev` added), matching PM-08.
- The ADMM `reactive_consensus` smart default (PM-03): traced `_any_flexible_reactive` and its
  two call sites (`build_dso_opt`, `solve_admm`) and confirmed the single-source-of-truth
  threading (`solve_admm` normalizes once and always passes an explicit `mode` into
  `build_dso_opt`, so the latter's own default expression never independently re-fires). This is
  a legitimate, well-tested fix, but it is also a substantial *silent* behavior/performance change
  for any existing caller that does not pass `reactive_consensus` explicitly — see WR-01 below.

No BLOCKER-level correctness or security defect was found in the reviewed files. The findings
below are WARNING/INFO items: a reproducibility-metadata gap, a test-coverage gap on one new
code path, and two documentation/contract-consistency nits.

## Warnings

### WR-01: PM-03's smart `reactive_consensus` default is invisible to experiment reproducibility metadata

**File:** `src/admm/DsoOpt.jl:155-174,270-278`, `src/admm/solve_admm.jl:249,277-298`,
`src/experiments/run.jl:128-142`

**Issue:** `build_dso_opt`/`solve_admm` now resolve `reactive_consensus` to `LIVE` whenever
*any* aggregator carries a `FourQuadBESS` or a flexible-load device
(`_any_flexible_reactive`), unless the caller passes it explicitly. `run_scenario`'s `:admm`
branch (`src/experiments/run.jl:129-142`) never passes `reactive_consensus`, so it always
receives this code-version-dependent default. `Scenario` (not modified by this phase) has no
`reactive_consensus` field, so the resolved mode is not part of the scenario's own
serializable parameters — it cannot be recovered from a saved `Scenario`/`savename` alone, only
from the stamped git commit (`DrWatson.tagsave`), which a downstream analysis script is not
guaranteed to check. The knife-edge canary (`test_admm_knifeedge_canary.jl`) documents a
material change from this default flip alone (iteration count 58→56, welfare
`-4822.90…`→`-4823.67…`, a ~0.016% absolute welfare shift with no `Scenario` field changed) —
i.e. re-running the *identical* `Scenario` object against two different commits of this
package now silently produces different, non-reproducible numbers whose cause is not
discoverable from the scenario's own recorded parameters.

This is a legitimate and well-tested correctness fix (ADMM previously silently diverged from
the centralized model's reactive draw whenever flexible loads were present), so it is not a
BLOCKER, but the project's own stated hard requirement is "reproducible results ... every
model assumption documented" — a silent, un-recorded default flip cuts against that.

**Fix:** Thread the *resolved* `mode` back out into `solve_admm`'s return tuple (it is already
computed once, `src/admm/solve_admm.jl:284`) so callers/experiment logs can record which
reactive-consensus mode actually ran, e.g.:

```julia
return (;
    welfare, dadp, λ = λ_mat, iters = residuals.iters, residuals,
    dso_ctx = dso.ctx, exact_maxgap, mu_q = mu_q_mat, q_devices,
    reactive_consensus_mode = mode,   # NEW: makes the resolved default recoverable
    status = :converged,
)
```
and have `run_scenario` record it into its own result `NamedTuple`.

### WR-02: `decompose_dlmp`'s new `:smax_rev` congestion term has no dedicated regression exercising the receiving-end-binding regime

**File:** `src/pricing/dlmp.jl:289-319`

**Issue:** The FIX-03 receiving-end cone (`:smax_rev`) is exercised directly at the
`ConvexBranchFlow`/`ACPowerFlow` level (`test_convex_branch_flow.jl`'s and
`test_ac_powerflow.jl`'s PV-back-feed items assert `mag_rev > 100·mag_fwd`), but
`test_pricing_dlmp.jl`'s "congestion binds" item uses the IEEE-13 *ground* population, which
the file's own header states is congestion-driven at the *sending* end. The dlmp.jl file
header itself documents that the `:smax_rev`-dominated congestion regime (IEEE-13 PV back-feed,
`t=9-16`, residual `3.55e-15`) was only verified via a one-off, non-committed measurement
(`26-10-SUMMARY.md`), not a repeatable `@testitem`. A future edit to the `cong_b[b,t]` sign for
the `smax_rev` term (dlmp.jl:315-317) could silently invert or drop that contribution without
any currently-committed test detecting it in the specific regime it was designed for — the hard
sum-to-price assertion would only catch it on a *fixture that actually exercises the
receiving-end bind*, which the current DLMP test suite does not include.

**Fix:** Add a `@testitem` combining the existing PV-back-feed fixture
(`test_convex_branch_flow.jl`'s 2-bus back-feed feeder) with `decompose_dlmp`, asserting both
the hard sum-to-price identity and that `d.congestion` is materially driven by the
`:smax_rev` dual (not just nonzero) in that regime — mirroring the existing
`ConvexBranchFlow`-level assertion `mag_rev > 100 * mag_fwd`.

### WR-03: `Interruptible` was converted to the flexible-load contract but does not get the same per-device `φ` override field as `Thermostatic`/`Deferrable`

**File:** `src/devices/Interruptible.jl:42-91` vs `src/devices/Thermostatic.jl:53-61,74`,
`src/devices/Deferrable.jl:58-60,76`

**Issue:** FIX-05 gave `Thermostatic` and `Deferrable` an optional `φ::Union{Nothing,T}` field
(with constructor validation) so a flexible load's reactive draw can override the aggregator's
own power factor. `Interruptible` was converted to the same `is_flexible_load(...) == true`
contract in the same plan (26-07) but received no such field — `Aggregator.contribute!`'s
`hasproperty(d, :φ) && d.φ !== nothing` check silently falls back to `agg.φ` for every
`Interruptible`, which is *consistent* (no crash, no wrong sign), but leaves the three
documented "flexible load" device types with an inconsistent public contract: two of three
support a per-device power-factor override, one does not, with no comment anywhere in
`Interruptible.jl` explaining the omission is deliberate (as opposed to simply not-yet-done).

**Fix:** Either add the same `φ::Union{Nothing,T}` field to `Interruptible` for contract
parity, or add a one-line comment in `Interruptible.jl` (mirroring the "Claude's Discretion"
notes elsewhere in this phase) stating the omission is intentional and why.

### WR-04: `_any_flexible_reactive`/`build_dso_opt`'s widened reactive-decision guard message references a raw symbol `:live` that does not match the actual runtime check

**File:** `src/admm/DsoOpt.jl:231-239,319-340`

**Issue:** The docstring (line ~232, ~319-338) and the thrown `ArgumentError` message
(`"...reactive_consensus normalizes to $(mode), not LIVE... Pass reactive_consensus = :live"`)
both use the raw keyword-argument spelling `:live`, while the actual guard condition compares
the *normalized* enum value `mode != LIVE` (line 319), not the raw `reactive_consensus`
argument. This is not a functional bug (the guard is correct), but the docstring text at
line 231 ("combined with `reactive_consensus != :live`") reads as if the comparison happens
against the caller's raw argument, which would be wrong if `reactive_consensus` were passed as
`true`/`ReactiveMode` rather than the symbol `:live` — a maintainer skimming only the docstring
could introduce a real bug (e.g. `if reactive_consensus != :live`) while "fixing" something
here.

**Fix:** Reword the docstring/error message to consistently reference the *normalized* `mode`
(e.g. "combined with a normalized `mode != LIVE`"), not the raw keyword spelling, to avoid
future confusion between the two.

## Info

### IN-01: `RestrictedBranchFlow.jl`'s `_EXACT04_MEASURED_ε` carries three superseded numeric values in one comment block

**File:** `src/powerflow/RestrictedBranchFlow.jl:61-89`

**Issue:** The comment above `_EXACT04_MEASURED_ε` accumulates the full re-measurement history
across three phases (`0.005811069127373614`, then `0.010189528427785532`, then the final
`0.010189528427785532 * 1.25 = 0.012736910534731915`), each introduced by a different plan.
The live value (line 89) is correct and I confirmed the arithmetic
(`0.010189528427785532 * 1.25 == 0.012736910534731915`), but a future reader must parse ~30
lines of historical narrative to identify which of the three numbers is currently load-bearing.

**Fix:** Move the historical re-measurement narrative to the SUMMARY docs it already
references (`20-02-SUMMARY.md`, `26-08-repro-restricted-and-canary.jl`) and leave only the
current provenance (date, fixture, measured value, 1.25× multiplier) inline.

### IN-02: `decompose_dlmp` assumes but never asserts that `:smax` and `:smax_rev` share identical (branch, time) key sets

**File:** `src/pricing/dlmp.jl:288-295,315-317`

**Issue:** `smaxkeys` is built once from `:smax`'s own `eachindex` (line 288) and then reused
unchanged for the soft-guarded `:smax_rev` lookup (line 295, 316-317) on the stated assumption
that both containers were registered under the identical filter predicate in
`ConvexBranchFlow.contribute!`. This is true today (both are gated by the same
`B[b].smax < _SMAX_NO_LIMIT` filter), but there is no runtime check that a hand-built or future
alternate `ModelContext` (e.g. a test fixture, or `MeshedFlow`'s delegation) actually preserves
this invariant — a `:smax_rev` container with a *different* key set would silently read `0.0`
for any `(b,t)` present in `:smax_rev` but absent from `smaxkeys`, rather than throwing. In
practice this would very likely still be caught by the hard sum-to-price assertion further down
the same function (a dropped/mis-keyed congestion contribution produces an `O(price)`
residual), so this is defence-in-depth rather than an exploitable defect.

**Fix:** Consider building `smaxkeys` from `union(eachindex(smax), eachindex(smax_rev))` (or
asserting the two key sets are equal when `smax_rev !== nothing`) so a future divergence fails
at the point of the actual bug rather than relying entirely on the downstream reconstruction
check.

### IN-03: `test_thesis_repro.jl`'s IEEE-123 golden band was not re-derived after phase 26's physics fixes

**File:** `test/test_thesis_repro.jl:19-22,64-68`

**Issue:** `DSO_BAND_HI = 7.211125525764296` predates phase 26 (derived at quick task
`260823-gea`, before FIX-01 through FIX-05). Phase 26's own CONTEXT.md explicitly defers
"Thesis reproduction restatement (sign flip / magnitude)" to Phase 28, and the git history shows
a full-suite-green certification at HEAD, so this file evidently still passes — the band is
wide enough (`0 < acct.dso < 7.21`) to absorb the physics changes without re-derivation. This is
not a functional defect, but it is worth flagging explicitly: the golden band's *provenance
comment* (lines 19-22, 45-58) still reads as if `7.211125525764296` reflects the current model
physics, when it in fact predates the cpydrop sign flip, the receiving-end limit, the SOC
horizon fix, and the flexible-load reactive draw — a reader could reasonably (and incorrectly)
assume this number was re-validated against the current model.

**Fix:** Add a one-line note at the top of the item cross-referencing this as an open item for
Phase 28's restatement, so a reader doesn't need to reconstruct that from the CONTEXT.md
deferred-ideas list.

---

_Reviewed: 2026-09-29T02:44:07Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
