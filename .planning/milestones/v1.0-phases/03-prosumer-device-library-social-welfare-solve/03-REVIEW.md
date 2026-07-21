---
phase: 03-prosumer-device-library-social-welfare-solve
reviewed: 2026-07-18T21:35:17Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - src/data/profiles.jl
  - src/devices/Thermostatic.jl
  - src/devices/Deferrable.jl
  - src/devices/PVBattery.jl
  - src/devices/Aggregator.jl
  - src/models/welfare_solve.jl
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-07-18T21:35:17Z
**Depth:** deep (cross-file: welfare_solve → Aggregator → devices; residual/objective seam; power-flow contract)
**Files Reviewed:** 6 (scoped Phase-3 sources; supporting infra `ModelContext.jl`, `status.jl`, `LinDistFlow.jl`, `DCPowerFlow.jl`, `Feeder.jl`, `factory.jl`, `Interruptible.jl` read for context and NOT counted)
**Status:** issues_found

## Summary

Phase 3 adds three aggregatable devices (Thermostatic, Deferrable, PVBattery), the
Aggregator roll-up, the seeded Markov profile generator, and the GLB-CVX welfare solve.
The code is well-documented and the residual/objective seam is used correctly — device
utilities go to `add_to_objective!` as `QuadExpr` (curvature preserved), injections go to
the affine `:Rp`/`:Rq` residual, and the Aggregator is a clean sole-writer. Sign
conventions for active injection (load `-p`), reactive (`-Pdc·tanφ`), SOC recursion
(`+η·p_ch − p_dch/η`), and the DADP dual read mirror the accepted `linear_solve.jl`
baseline and are consistent.

The one material correctness defect is in `PVBattery`: the whole "no binary /
no complementarity constraint" design rests on **strict** price ordering, but the
constructor guard permits **equality**, so there is an input regime where the mandatory
post-solve `p_ch·p_dch < τ` check is unreliable — exactly the silent-wrong hazard this
bench must not ship. Four warnings cover a vacuous Deferrable utility, missing
Thermostatic parameter/IC guards, a mis-documented DC+aggregator combination, and the
absence of PV curtailment/export recourse.

## Critical Issues

### CR-01: PVBattery no-complementarity guarantee rests on STRICT price ordering, but the constructor allows equality

**File:** `src/devices/PVBattery.jl:110` (guard), `:246-249` (curvatures), `:44-53` (the claim); enforced by `src/models/welfare_solve.jl:143-156` (mandatory check)

**Issue:** The entire "NO binary, NO `p_ch·p_dch == 0`" correctness argument (docstring
lines 41-53) and the mandatory post-solve check in `solve_welfare`
(`value(p_ch[t])·value(p_dch[t]) < τ`) depend on **strict** dominance. The docstring even
states: *"the strict ordering makes them > 0 and the `p_ch·p_dch = 0` dominance strict."*
But the constructor guard is weak:

```julia
if !(λ_min <= λ_med <= λ_max)   # line 110 — allows λ_min == λ_med and/or λ_med == λ_max
```

When `λ_min == λ_med` then `b_ch = (λ_med − λ_min)/Pmax = 0` (line 247); when
`λ_med == λ_max` then `b_dch = 0` (line 249). In that regime the charge/discharge
objective loses strict curvature and the round-trip is only **weakly** dominated. Because
`η² < 1`, simultaneous same-`t` charge+discharge of equal magnitude `x` leaves the
injection `Ppv − p_ch + p_dch` unchanged but drains SOC by `x·(1/η − η)·Δt > 0` at zero
objective cost — so the QP admits alternative optima with `p_ch[t]·p_dch[t] > 0` and a
**different SOC trajectory** (which can bind `Emin` later and shift the balance duals /
DADP). Consequences at the welfare optimum:
- the mandatory check throws on a *validly constructed* battery (`λ_min == λ_med` is a
  legitimate degenerate parameterization the guard explicitly admits) — a spurious hard
  failure; or
- a solver returns the `p_ch·p_dch ≈ 0` vertex and the check passes while a SOC-draining
  co-optimum was equally optimal — the "correct price" is no longer unique/trustworthy.

Either way the load-bearing invariant the file names is not actually enforced by the guard
that is supposed to enforce it. For a bench whose value *is* trustworthy prices, this is a
silent-wrong hazard.

**Fix:** Enforce the strictness the design and the runtime check assume:

```julia
if !(λ_min < λ_med < λ_max)
    throw(ArgumentError(
        "PVBattery requires STRICT λ_min < λ_med < λ_max: the App. C no-binary " *
        "argument and the post-solve p_ch·p_dch < τ check both rely on strict " *
        "dominance (b_ch, b_dch > 0). Equality admits SOC-draining co-optima. " *
        "got λ_min=$λ_min, λ_med=$λ_med, λ_max=$λ_max"))
end
```

If a degenerate (equal-λ) battery must be supported, then the complementarity property is
no longer guaranteed and an explicit tie-break (e.g. a tiny discharge-of-charged-energy
penalty, or a real complementarity/SOS1 constraint on that device) is required — the
current weak guard + strict claim cannot both stand.

## Warnings

### WR-01: Deferrable soft utility is identically zero on the feasible set (redundant with the hard budget equality)

**File:** `src/devices/Deferrable.jl:158` (hard equality) and `:162` (soft penalty)

**Issue:** `contribute!` adds BOTH a hard budget equality
`sum(p[t] for t in t_start:t_end) == E` (line 158) AND a soft quadratic penalty
`utility = -(b/2)·(sum(p) − E)^2` (line 162) on the *same* quantity. On every feasible
point `sum(p) == E`, so `utility ≡ 0`. The device therefore contributes exactly nothing to
the welfare objective, and its `b > 0` concavity guard (lines 70-77) protects a term that
can never be nonzero. This is not the accepted "no-linear-term" note — it is a structural
redundancy: the thesis 3.12 quadratic is meant as a *soft* target, but pairing it with the
hard equality neutralizes it. The scheduling within the window is then driven purely by
network price, with no device preference signal at all (which may be intended, but the
utility term is dead weight and misleadingly implies a preference).

**Fix:** Choose one representation. Either drop the hard equality and let 3.12 act as the
genuine soft budget target (`sum(p)` free, penalized toward `E`), or keep the hard equality
and drop the vacuous `utility`/`b` machinery. Document which semantics the thesis intends.

### WR-02: Thermostatic missing physical-parameter and initial-condition guards

**File:** `src/devices/Thermostatic.jl:66-106` (constructor), `:197-198` (recursion)

**Issue:** The constructor guards `b > 0`, `Tmax ≥ Tmin`, and `Pmax ≥ Pmin`, but omits
guards that the sibling devices enforce:
- No sign/range guard on `α` or `β`. A negative `β` silently flips the physics
  (`− β·p` becomes heating instead of cooling) — a silently-wrong model, not a crash.
  An `α ∉ (0,1)` breaks the RC/ETP interpretation (anti-diffusion / overshoot).
- **No `Tmin ≤ Tin0 ≤ Tmax` initial-condition guard.** Line 197 fixes `Tin[1] == d.Tin0`
  while line 194 bounds `Tmin ≤ Tin[1] ≤ Tmax`. If `Tin0` is outside the band the model is
  infeasible, surfacing as a cryptic `INFEASIBLE` solver status rather than a clear
  construction error. `PVBattery` guards the analogous `Emin ≤ soc0 ≤ Emax` (PVBattery.jl:133);
  `Thermostatic` should mirror it.

**Fix:** Add to the inner constructor:

```julia
if !(zero(T) < α < one(T))   # RC/ETP diffusion coefficient
    throw(ArgumentError("Thermostatic α must lie in (0,1) for a stable RC recursion; got α=$α"))
end
if β <= zero(T)              # power must cool (−β·p), not heat
    throw(ArgumentError("Thermostatic β must be > 0 (eq. 3.2 cooling gain); got β=$β"))
end
if !(Tmin <= Tin0 <= Tmax)   # IC must lie in the comfort band (mirrors soc0 guard)
    throw(ArgumentError("Thermostatic Tin0 must satisfy Tmin ≤ Tin0 ≤ Tmax; got Tmin=$Tmin, Tin0=$Tin0, Tmax=$Tmax"))
end
```

### WR-03: DC + Aggregator reactive balance is infeasible; docstring overstates DC↔LinDistFlow interchangeability

**File:** `src/devices/Aggregator.jl:153-156`, `src/models/welfare_solve.jl:44-49,118-131`

**Issue:** The Aggregator *unconditionally* writes reactive `−Pdc·tanφ` into `:Rq`
(Aggregator.jl:155) for every aggregator, regardless of the power-flow formulation. With
`DCPowerFlow` there are no reactive branch flows and `welfare_solve` injects `q_import`
**only at `feeder.root`** (welfare_solve.jl:113). So `balance_q` at any non-root aggregator
bus becomes `−Pdc[j]·tanφ == 0`, infeasible for `Pdc[j] > 0` (or, if the aggregator/root do
not reach bus `Np`, the `size(ctx.residuals[:Rq]) == (Np,T)` guard at welfare_solve.jl:126
trips first with the misleading "index escaped the feeder" message). This contradicts the
docstring claim (welfare_solve.jl:48-49) that swapping DC↔LinDistFlow "changes only which
residuals exist" — `:Rq` now always exists because the aggregator creates it. The failure
is loud (not silent), but the combination is effectively unsupported and mis-documented.

**Fix:** Either (a) document that aggregator-based welfare requires a reactive-capable
formulation (LinDistFlow) and reject `DCPowerFlow + Aggregator` with a clear guard, or
(b) make the reactive channel conditional so DC genuinely yields no `:Rq`. Update the
docstring to stop claiming free DC↔LinDistFlow interchange once aggregators are present.

### WR-04: No PV curtailment and no export recourse can make the welfare solve infeasible

**File:** `src/devices/PVBattery.jl:263`, `src/models/welfare_solve.jl:109`

**Issue:** PV enters as a fixed *must-take* injection: `p_inject[t] = Ppv[t] − p_ch + p_dch`
(PVBattery.jl:263), where `Ppv` is a parameter, not a decision variable — there is no
curtailment slack. The frontier import `p_import[t] ≥ 0` (welfare_solve.jl:109) has no
export counterpart. Consequently a high-PV scenario that pushes squared voltage above
`vmax²` (LinDistFlow bounds), or a net-surplus bus that would need to export through the
root, has no recourse and the problem becomes `INFEASIBLE`. This fails loudly via
`assert_solved!`, but PV curtailment / a frontier export sink are standard modeling needs;
their absence will surface as puzzling infeasibilities on realistic profiles.

**Fix:** Add an optional PV-curtailment variable `0 ≤ p_curt[t] ≤ Ppv[t]` (inject
`Ppv[t] − p_curt[t] − p_ch + p_dch`) and/or a free-sign / non-negative frontier export at
the root, gated behind the model configuration. At minimum, document the must-take / no-export
assumption so an infeasible solve is diagnosable.

## Info

### IN-01: Thermostatic Tout length guard is off-by-one conservative

**File:** `src/devices/Thermostatic.jl:182`

**Issue:** The recursion reads `d.Tout[t]` only for `t = 1:T-1` (line 198), so length
`T-1` suffices, but the guard requires `length(d.Tout) < T` → needs `≥ T`. Harmless
(over-strict by one; the docstring at line 180 even notes the `1:T-1` read), but a caller
supplying exactly `T-1` ambient samples is rejected unnecessarily.

**Fix:** Either relax the guard to `length(d.Tout) < T - 1` or keep it and note the extra
sample is intentionally required for forward compatibility.

### IN-02: markov_path inverse-CDF fall-through silently repeats the current state at the row-sum boundary

**File:** `src/data/profiles.jl:80-89`

**Issue:** `nxt` is initialized to the current state `s`; if `u` exceeds the accumulated
row mass `c` (possible only when the row sum is below `u`, i.e. within the `1e-8` tolerance
slack), the loop falls through and the chain silently self-loops. Probability is ~`1e-8`
given the row-stochastic guard, so immaterial, but strictly it biases the last mass bin.

**Fix:** After the loop, either assert `u <= c` or renormalize the row once at entry so the
final bin absorbs the residual mass exactly.

### IN-03: Device-variant contract (self-injecting vs aggregatable) is unenforced by the type system

**File:** `src/devices/Aggregator.jl:141-147`, `src/devices/AbstractDevice.jl:24-66`

**Issue:** `Aggregator.devices::AbstractVector{<:AbstractDevice}` accepts *any*
`AbstractDevice`, including a self-injecting `Interruptible` (whose `contribute!` returns a
bare variable array and writes directly to `:Rp`/objective). Passing one into an aggregator
would throw at `res.p_inject` (line 144) with a cryptic "type has no field p_inject" — and
would also double-write to `:Rp`. The failure is loud, but the two contract variants are
distinguished only by convention/docstring, not by types.

**Fix:** Introduce a marker (e.g. `AbstractAggregatableDevice <: AbstractDevice`) and type
the aggregator's member vector against it, so misuse is a compile-time `MethodError` with a
clear signature rather than a runtime field error.

---

_Reviewed: 2026-07-18T21:35:17Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
