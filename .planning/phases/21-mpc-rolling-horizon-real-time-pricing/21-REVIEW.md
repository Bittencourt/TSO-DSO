---
phase: 21-mpc-rolling-horizon-real-time-pricing
reviewed: 2026-08-09T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - src/TSODSO.jl
  - src/devices/PVBattery.jl
  - src/devices/Thermostatic.jl
  - src/devices/FourQuadBESS.jl
  - src/devices/Aggregator.jl
  - src/models/mpc_trace.jl
  - src/models/mpc_window.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/Scenario.jl
  - test/fixtures_phase21.jl
  - test/test_mpc_trace.jl
  - test/test_mpc_window.jl
  - test/test_mpc_terminal.jl
  - test/test_mpc_loop.jl
  - docs/literate/mpc_rolling_horizon.jl
findings:
  critical: 3
  warning: 7
  info: 5
  total: 15
status: issues_found
---

# Phase 21: Code Review Report

**Reviewed:** 2026-08-09
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Reviewed the Phase-21 MPC / rolling-horizon implementation: the Parameter-widened devices
(`PVBattery`/`Thermostatic`/`FourQuadBESS`/`Aggregator`), the build-once `MpcWindow`, the
`MpcTrace` ledger, the `run_mpc` closed-loop orchestrator with Phase-20 certificate
escalation, the additive `Scenario` `mpc_*` fields, the Phase-21 test suite, and the
literate regret-benchmark page. Cross-file contracts (`solve_welfare`'s return/meta shape
and internal throwing gates, `assert_restriction_exact!`/`ac_dual_fallback_price`
signatures, `RestrictedBranchFlow`'s delegation to `ConvexBranchFlow`, the `:default`
population composition, `sub_seed`/`StableRNGs` availability) were verified against their
source files, not taken from comments.

**What holds up under scrutiny:** the build-once discipline is genuinely respected (the
window model is constructed once; all per-step mutation flows through anonymous `Parameter`
handles and `set_objective_coefficient`; the byte-identical-default invariant on every
widened Parameter checks out); the strided loop's `n_apply` formula provably covers
published hours `1..T−H+1` exactly once for any `mpc_step ≤ mpc_H`; the inline cone-residual
reimplementation in `_mpc_certify_and_price` matches `assert_socp_exact!`'s formula at its
identical defaults; nominal-plant `propagate_soc`/`propagate_tin` are consistent with the
in-model recursions; `MpcTrace` bookkeeping is correct and fail-loud.

**What does not:** the certificate-escalation branch re-solves the *wrong problem* (hours
`1..H` with construction-time initial conditions, under hour-`t` prices), the escalation
ladder has multiple reachable throwing calls despite the explicit "never throws" (D-04)
contract, and the regret metric's day-ahead frontier term violates the file's own
"identical device set" claim — three Critical findings, all in the phase's headline
correctness/honesty surface.

## Critical Issues

### CR-01: Escalation ladder solves the wrong window — hours 1..H with construction-time ICs under hour-t prices

**File:** `src/experiments/mpc_loop.jl:343-360`
**Issue:** On an inexact step at absolute hour `t`, `_mpc_certify_and_price` escalates via
fresh `solve_welfare(feeder, RestrictedBranchFlow(), mpc_aggs; T = o.H, λ₀ = λ₀_window, ...)`
and `solve_welfare(feeder, ACPowerFlow(), mpc_aggs; ...)`. These build brand-new models from
the ORIGINAL device structs, whose Parameters default to `d.Ppv[1:H]`, `d.Tout[1:H−1]`,
`agg.Pdc[1:H]`, `d.soc0`, `d.Tin0` — i.e. the day's **first H hours with the day's initial
state**, no measured SOC/Tin, no forecast perturbation. Only `λ₀` is correctly sliced to
`t:(t+H−1)`. The published escalation `price_vec` and the cert verdict therefore describe a
problem that mixes hour-1 physics with hour-`t` prices — wrong at every resolve except
`t = 1`, which is exactly (and only) where the forced-inexact test
(`test/test_mpc_loop.jl:82`, `t = 1`) drives it, so the suite cannot catch this.
**Fix:** After building each escalation context, re-target its Parameter handles to the
current window's state before reading duals — set `soc0`/`Tin0` to `measured_state`,
`Ppv_param`/`Tout_param`/`Pdc_param` to the same `t`-sliced (and forecast-perturbed, for
consistency with the failed window) profiles `run_mpc` fed the main window. The handles are
reachable via each context's `ctx.meta[:agg_device_vars]` and the aggregator `contribute!`
return; alternatively build a second build-once escalation window (RestrictedBranchFlow)
at construction time and slide it exactly like the main window. This requires threading
`measured_state`/`fe` (or the ready-made slices) into `_mpc_certify_and_price`.

### CR-02: The "never throws mid-loop" (D-04) escalation ladder has multiple reachable throwing calls

**File:** `src/experiments/mpc_loop.jl:344-375` (with `src/models/welfare_solve.jl:241-264`)
**Issue:** The docstring and D-04 claim "this function itself NEVER throws," but only the
inline cone check is non-throwing. Inside the escalation branch, `solve_welfare` runs three
throwing gates:
1. `assert_socp_exact!` runs on the `RestrictedBranchFlow` solve — `RestrictedBranchFlow.contribute!`
   delegates to `ConvexBranchFlow.contribute!` (`RestrictedBranchFlow.jl:175`), which stashes
   `pf_vars[:l]`, so `welfare_solve.jl:257` fires the gate at `rtol = 1e-4`. That is
   **stricter** than `assert_restriction_exact!`'s own `cone_rtol = 5e-4`: any window where
   the OPF-m restriction fails to restore cone tightness — precisely the case the
   `ac_dual_fallback_price` tier exists for — throws out of `solve_welfare` before the
   fallback tier is ever reachable.
2. `assert_battery_complementarity!` (`welfare_solve.jl:264`) runs on both escalation solves
   and is documented (FourQuadBESS.jl:79-85) to *legitimately* throw in the
   negative-effective-price / high-PV regime — the very regime that trips the inline cone
   check and triggers escalation.
3. `assert_solved!` retry exhaustion inside either escalation solve.
Any of these kills `run_mpc` mid-loop, losing the trace accumulated so far.
**Fix:** Route each ladder tier's documented failure modes into the ledger instead of
propagating: catch the specific gate errors (or call non-asserting builders) and record
`cert_status = :cert_failed` with a fallback price policy (e.g. hold the previous published
price or the day-ahead reference), so the `:cert_failed` tier that `MpcTrace` and
`any_cert_failed` advertise is actually producible (see WR-04).

### CR-03: Regret's day-ahead frontier term includes Deferrable's import cost while excluding its utility — biased headline metric

**File:** `src/experiments/mpc_loop.jl:274-284`
**Issue:** The comment claims "both sides are evaluated ... over the SAME `mpc_aggs` device
set." The utility side honors that, but the frontier term
`day_ahead_comparable_welfare -= λ₀[τ] * value(ctx_da.meta[:p_import][τ])` reads `p_import`
from `ctx_da`, which was solved with the **full** population *including* `Deferrable`
(line 132-139). The day-ahead comparison is thus charged the frontier cost of serving
Deferrable's consumption while being denied Deferrable's utility, and its entire dispatch
(hence `p_import` and every device trajectory) reflects a different population than the
closed loop's. Net effect: `day_ahead_comparable_welfare` is systematically understated, so
`regret = realized − day_ahead_comparable` is inflated in the MPC's favor. The literate
page's observation that realized welfare "slightly exceeds" the perfect-foresight benchmark
(`docs/literate/mpc_rolling_horizon.jl:163-165`) is consistent with this bias.
**Fix:** Solve a second day-ahead benchmark over `mpc_aggs` (Deferrable-excluded) and take
both the comparison utilities and `p_import` from that context — one extra one-time solve,
outside the loop. Keep the full-population `day_ahead_welfare` as the separately-reported
number it already is.

## Warnings

### WR-01: Realized welfare is settled against the forecast, not the realized truth

**File:** `src/experiments/mpc_loop.jl:257` (and 187-205)
**Issue:** `realized_welfare -= λ₀[abs_hour] * value(o.p_import[τ_apply])` charges the
window's *forecast-consistent* frontier import. Under nonzero `mpc_forecast_error` the true
plant's import must absorb the demand error (`Pdc_true − Pdc_forecast·factor`) and the PV
error, so the "realized frontier cost/revenue" the docstring promises is fictional.
Relatedly, when `pv_factor > 1` the applied `p_ch` can exceed the TRUE PV availability
(`d.Ppv[abs_hour]`), violating Assumption A6 physically — the "realized" trajectory is not
realizable on the ground truth.
**Fix:** Re-settle the realized frontier per applied hour from truth: realized import =
`value(p_import[τ]) + Σ_agg (Pdc_true − Pdc_forecast)[abs_hour] − Σ (pv_used_true − pv_used_forecast)`,
and clip applied `p_ch` at `d.Ppv[abs_hour]` (documenting the clip) before `propagate_soc`.
At minimum, document that realized settlement is forecast-consistent by construction.

### WR-02: `mpc_step == mpc_H` applies the dynamics-uncovered H-th control — can drive measured state out of bounds and crash the next resolve

**File:** `src/experiments/mpc_loop.jl:102-107, 229-254` (with `src/models/mpc_window.jl`)
**Issue:** The guard permits `mpc_step == mpc_H`, making `n_apply = H` on full resolves. But
the window's `soc`/`Tin` states have length `H` and the recursions cover `τ ≤ H−1`, so the
controls at `τ = H` (`p_ch[H]`, `p_dch[H]`, `p[H]`) carry **no** SOC/temperature consequence
inside the model — the optimizer can discharge/consume freely at `τ = H` (e.g. `p_dch[H]`
limited only by `Pmax`, not by stored energy). Applying that interval via
`propagate_soc`/`propagate_tin` can push the measured state below `Emin` / outside
`[Tmin, Tmax]`; the next window then pins `soc[1] == soc0` (or `Tin[1] == Tin0`) outside the
variable bounds → infeasible → `solve_with_retry!` throws mid-loop. The stride test only
exercises `mpc_step = 2 < H = 3`, so this is untested.
**Fix:** Tighten the guard to `mpc_step ≤ mpc_H − 1` when any stateful device is present
(or extend the window's state vectors to `H+1` so every control has a modeled state
consequence).

### WR-03: `mpc_H = 1` with `terminal_soc = true` double-pins `soc[1]` — infeasible whenever measured state ≠ terminal target

**File:** `src/models/mpc_window.jl:207-217` (with `src/experiments/mpc_loop.jl:169-178`)
**Issue:** With `H = 1`, `build_mpc_window` adds both `soc[1] == soc0` (IC Parameter) and
`soc[H] == term` (terminal Parameter) on the same variable. `Scenario` accepts `mpc_H = 1`
and `run_mpc` sets the two Parameters to the measured state and the day-ahead target
respectively — infeasible at the first hour where they differ.
**Fix:** Throw in `build_mpc_window` when `terminal_soc && H == 1` (or require `H ≥ 2` for
the terminal toggle), with an explanatory message.

### WR-04: `:cert_failed` is unreachable, so `any_cert_failed` is structurally vacuous; tier-2 rescue is indistinguishable from tier-1 certification

**File:** `src/experiments/mpc_loop.jl:333-377` (with `src/models/mpc_trace.jl:119-127`)
**Issue:** `_mpc_certify_and_price` only ever emits `:certified_convex_dual` or
`:local_ac_dual`; the `:cert_failed` symbol that `MpcTrace`'s docs, `any_cert_failed`, and
D-04's ladder advertise cannot occur — genuine failures surface as exceptions instead
(CR-02). Additionally, the restricted-tier rescue (`report.ac_feasible == true`) reuses the
literal `:certified_convex_dual`, so the trace cannot distinguish a first-tier certification
from a restricted-solve rescue — a real diagnostic loss for a price-provenance ledger.
**Fix:** Emit a distinct symbol for the restricted tier (e.g. `:certified_restricted`) and
wire the ladder's terminal failure mode to `:cert_failed` (see CR-02 fix).

### WR-05: Bus-keyed single-stateful-device assumption is undocumented and partially silent

**File:** `src/experiments/mpc_loop.jl:140-143, 157-161, 239, 250` (with `src/devices/Aggregator.jl:220-221`)
**Issue:** `measured_state` is keyed `(bus, kind)`, `soc_da` is a Dict comprehension keyed by
bus (silently overwriting when a bus hosts two SOC devices), and
`only(vv for vv in varlist if haskey(vv, :soc0))` throws for a bus hosting both a
`PVBattery` and a `FourQuadBESS` (both carry `:soc0`). Two aggregators sharing a bus
mispair `zip(agg.devices, varlist)` because `Aggregator.contribute!` APPENDS varlists into
one per-bus vector. All of this holds today only because the `:default` population places
one Thermostatic + one PVBattery per distinct bus — an invariant nothing asserts.
**Fix:** Key state by device identity (e.g. `(bus, device_index)` captured while walking
`ic_handles`), or throw a clear `ArgumentError` in `run_mpc` when a bus hosts more than one
device of the same state kind / when aggregator buses are not unique.

### WR-06: Window (and escalation) frontier ignores `s.allow_export` while the day-ahead benchmark honors it

**File:** `src/models/mpc_window.jl:151-156`; `src/experiments/mpc_loop.jl:132-139, 344-372`
**Issue:** `build_mpc_window` always builds a free-sign `p_import` (export allowed), and the
escalation solves hardcode `allow_export = true`, but the day-ahead benchmark passes
`allow_export = s.allow_export`. A `Scenario(allow_export = false)` run benchmarks a
no-export day-ahead optimum against an export-allowed closed loop — an information-set
asymmetry beyond the intended forecast-error mismatch, corrupting regret for that
configuration.
**Fix:** Thread `allow_export` into `build_mpc_window` (add a `p_import` lower bound of 0
when false, mirroring `solve_welfare`) and into both escalation `solve_welfare` calls, or
throw on `run_mpc` with `allow_export = false` until supported.

### WR-07: No `mpc_H ≤ T` guard — cryptic device-level failure (or silent zero-step run)

**File:** `src/experiments/mpc_loop.jl:98-107`; `src/experiments/Scenario.jl:219-235`
**Issue:** `run_mpc` guards `mpc_step > mpc_H` only. With `mpc_H > s.T`, `build_mpc_window`
fails deep inside device `contribute!` with "Tout has length ... < horizon T=..." — a
misleading message for a Scenario-level misconfiguration. If any future population carried
profiles longer than `s.T`, the build would succeed and the loop range
`1:(s.T − s.mpc_H + 1)` would be empty — zero resolves, `steps = 0`, `regret = 0.0`
returned silently, contradicting the docstring's "steps is ALWAYS `s.T − s.mpc_H + 1`."
**Fix:** `s.mpc_H <= s.T || throw(ArgumentError(...))` at the top of `run_mpc` (Scenario's
constructor already sees both fields and could also enforce it).

## Info

### IN-01: `_mpc_device_hour_utility` docstring advertises an `AbstractDevice` signature that has no method

**File:** `src/experiments/mpc_loop.jl:382-397`
**Issue:** The docstring's signature line reads `d::AbstractDevice`, but only
`PVBattery`/`FourQuadBESS`/`Thermostatic` methods exist — any future aggregatable device in
a population reaching `run_mpc` hits a mid-loop `MethodError`.
**Fix:** Correct the docstring, and consider an explicit fallback method that throws an
`ArgumentError` naming the unsupported device type.

### IN-02: `mean_jump` divides by `steps` although only `steps − 1` real jumps exist

**File:** `src/models/mpc_trace.jl:117`
**Issue:** The forced `0.0` first jump is included in the mean's numerator and denominator,
diluting the metric (e.g. one 1.0 jump over 2 steps reports 0.5). Documented behavior, but
a reader of "mean step-to-step jump" will assume `Σ jump / (steps − 1)`.
**Fix:** Either divide by `max(steps − 1, 1)` or state the dilution explicitly in the
docstring.

### IN-03: `MpcWindow` fields `Vector{<:NamedTuple}` are non-concrete

**File:** `src/models/mpc_window.jl:66-67`
**Issue:** `ic_handles::Vector{<:NamedTuple}`/`agg_pdc_handles::Vector{<:NamedTuple}` are
UnionAll field types, against the project's own "concrete, parametrized fields" convention
(CLAUDE.md). Correctness is unaffected; access from the hot loop is field-lookup dynamic.
**Fix:** Parametrize the struct on the handle vector types, or store
`Vector{NamedTuple}` concretely and document.

### IN-04: Doc typo — `set_parameter_value!` (nonexistent bang form)

**File:** `src/models/mpc_window.jl:18`
**Issue:** The header comment says callers re-solve "via `set_parameter_value!`/
`set_parameter_value.`" — JuMP's function is `set_parameter_value` (no `!`).
**Fix:** Drop the bang.

### IN-05: Literate "Finding" section asserts qualitative claims the page never checks

**File:** `docs/literate/mpc_rolling_horizon.jl:160-165`
**Issue:** The prose asserts `max_jump`/`mean_jump` are "non-trivial, non-flat" and frames
positive regret as the loop "slightly exceed[ing]" the perfect-foresight optimum. The first
is an unchecked claim over live-recomputed numbers (a rebuild could produce a flat trace and
the prose would be wrong); the second is presented as a benign outcome when it is more
plausibly the CR-03 bias artifact.
**Fix:** Rephrase to describe rather than assert, and revisit after CR-03 lands.

---

_Reviewed: 2026-08-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
