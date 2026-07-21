---
phase: 07-admm-convergence-scale
reviewed: 2026-07-19T00:00:00Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - src/admm/solve_admm.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/residuals.jl
  - src/data/ieee123.jl
  - ext/TSODSOMakieExt.jl
  - src/diagnostics/plots.jl
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-07-19
**Depth:** deep
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Phase 7 hardens the hand-rolled ADMM loop with a Boyd two-residual stop, ε-normalized
residual-balancing adaptive ρ, a transit-node relaxation for IEEE-123 scale, a feeder-scale
per-unit rescale, and a weakdep Makie plotting extension. I reviewed the algorithm
adversarially, tracing every sign and block that could silently corrupt the recovered price.

**The load-bearing correctness paths hold up.** I verified end-to-end:

- The **augmented-Lagrangian sign structure is internally consistent**: AGR quadratic coeff
  `−0.5ρ` (Max), DSO `+0.5ρ` (Min); linear coeffs `−λ−ρ·c` (AGR) and `−λ−ρ·a` (DSO); the
  netflow target `c = −pag_dso`; the primal residual `r = a − pag_dso`; and the dual ascent
  `λ += ρ·r`. Every sign follows from the single MAX augmented Lagrangian in the header, and
  `set_rho!` reproduces the build-time quadratic coefficient with the correct per-subproblem
  sign. **No repulsive-penalty sign error.**
- The **dual residual uses the right (z / consensus) block**: `s = ρ·‖Δ(pag_dso)‖₂`, the
  second-updated block, initialized against a zeros previous-iterate so iteration 1 cannot
  false-converge.
- The **two-residual stop is theoretically sound**: `r → 0` forces the dual step to zero
  (fixed point ⇒ KKT ⇒ global optimum for the convex problem), and stopping requires BOTH
  `‖r‖ ≤ ε_pri` and `‖s‖ ≤ ε_dual`. A small-ρ artificial-`s` false stop cannot occur because
  `r` (unscaled) must also be below tolerance.
- The **per-unit thresholds match Boyd eq. 3.12** exactly for `A=I, B=−I, c=0`
  (`ε_pri = √p·ε_abs + ε_rel·max(‖a‖,‖pag_dso‖)`, `ε_dual = √p·ε_abs + ε_rel·‖λ‖`).
- The **adaptive-ρ / dual-step ρ never diverge** within an iteration: the dual step uses the
  pre-adaptation `ρf`, and `set_rho!` + the next-iteration linear-coeff update both use the
  post-adaptation `ρf` in lockstep; ρ is clamped and freezes.
- The **transit-node closure is well-determined**: every bus is exactly one of {root, load,
  transit}; transit nodes get a zero injection closed by `balance_p`/`balance_q` at all N buses
  — a correct radial zero-injection node, not under/over-determined.
- The **base rescale is per-unit consistent**: `S_base = 1 MVA`, r/x supplied directly in pu
  (not derived through `Z_base`, so no `Z_base/S_base` inconsistency), and `3.8 MVA → 3.8 pu`
  via `to_pu_power`. The IEEE-123 cross-validation compares two solution methods on the *same*
  rescaled feeder against the trusted monolithic optimum, so the rescale cannot make the
  comparison "self-consistent-but-wrong."

Remaining findings are a documented contract violation on the final consolidation solve
(WARNING), a per-unit base docstring contradiction (WARNING), and minor dead/stale-field and
robustness items (INFO).

## Warnings

### WR-01: Final consolidation solves accept NEARLY_FEASIBLE, contradicting the INFRA-03 "final solve must be strict" contract

**File:** `src/admm/solve_admm.jl:355-362`
**Issue:** After convergence the final AGR and DSO re-solves both pass `strict = false`
(`solve_agr!(...; strict = false)` and `solve_dso!(...; check_exact = true, strict = false)`),
which routes to `assert_solved!(...; allow_almost = true)`. The reported **welfare**
(`Σ value(U_ag) − Σ λ₀·value(p_import)`, line 367) and the **PF-04 exactness certificate**
(`assert_socp_exact!` on the DSO primal) are therefore computed from a primal the solver may
have labeled `ALMOST_OPTIMAL` / `NEARLY_FEASIBLE_POINT`. This directly contradicts the
INFRA-03 contract stated in `src/core/status.jl:35-36`: *"The FINAL/converged solve must still
use the STRICT gate (`allow_almost=false`) so no near-feasible price is ever published."* The
in-file justification (the published DADP is the outer multiplier `λ`, not a subproblem dual)
is valid for the *price*, but welfare and the exactness gap are published outputs derived from
the near-feasible primal, and the comment itself concedes Clarabel "intermittently stops at
ALMOST_OPTIMAL / NEARLY_FEASIBLE" under the ρ-penalty — so this path is exercised, not
hypothetical. At runtime there is no loud signal that a returned welfare is off by the solver
gap; only the test-time cross-validation (rtol 1e-4) catches it.
**Fix:** Make the final DSO solve strict (`strict = true`) so the published welfare/exactness
certificate come from a fully OPTIMAL primal; if Clarabel genuinely cannot hit the
centralized-grade gap under the converged ρ, do one strict re-solve at a relaxed penalty (or
tighten the solver's `tol_gap_*`) rather than publishing a near-feasible primal. At minimum,
add `assert_no_slack` on `:balance_p`/`:balance_q` at the converged point so a near-feasible
final primal is caught loudly instead of flowing silently into `welfare`.

### WR-02: IEEE-123 constructor docstring states "100 MVA" base, contradicting `IEEE123_BASE = 1 MVA`

**File:** `src/data/ieee123.jl:213`
**Issue:** `ieee123_modified`'s docstring says it builds a Feeder *"on the `IEEE123_BASE`
(100 MVA / 4.16 kV)"*, but `IEEE123_BASE = PerUnitBase(1.0, 4.16)` (line 57) is a **1 MVA**
feeder-scale base — the entire point of the Phase-7 rescale, correctly documented everywhere
else in the same file (header lines 45-47, the `IEEE123_BASE` docstring, and line 234's
"1 MVA feeder-scale base"). A per-unit base annotation that is off by 100× is precisely the
silent-scaling hazard this project's per-unit tripwires exist to prevent: a collaborator
scaling aggregator load/PV data to "match the feeder base" off this docstring would inject a
100× per-unit inconsistency that the magnitude tripwires would not necessarily catch (injections
are not magnitude-checked at construction). In a project where documentation fidelity of every
modeling decision is a hard requirement, this is a real defect, not a typo to wave through.
**Fix:** Change line 213 to read `(1 MVA / 4.16 kV)` to match `IEEE123_BASE` and the rest of the
file.

## Info

### IN-01: Stale, never-read `ρ` fields on `DsoOpt` and `AgrOpt`

**File:** `src/admm/DsoOpt.jl:73`, `src/admm/AgrOpt.jl:59`
**Issue:** Both structs store `ρ::Float64` at build time, but `set_rho!` mutates only the JuMP
model's quadratic coefficient — the struct field is immutable and is never updated, so after the
first adaptive-ρ change `dso.ρ` / `agr.ρ` hold the *initial* ρ, not the live penalty. Grep
confirms neither field is read anywhere in `src/` or `test/`, so this is latent, not active, but
a future reader treating `dso.ρ` as "the current penalty" would silently get a stale value.
**Fix:** Either drop the field (it is unused) or add a doc note that it is the *initial* ρ₀ and
the live penalty lives only in the model coefficients; do not read it as the current ρ.

### IN-02: `AgrOpt.qag` computed for a "μ update" that does not exist

**File:** `src/admm/AgrOpt.jl:103,110`
**Issue:** `qag = [−Pdc·tanφ]` is computed and stored "exposed for the reactive dual (`μ`)
update," but no reactive dual-ascent is implemented anywhere — the DSO closes reactive with a
constant draw and a free `q_import`, and `solve_admm` never touches `agr.qag`. Dead field.
**Fix:** Remove `qag` (and its computation) until a μ dual-ascent is actually implemented, or
note explicitly that it is a placeholder for a future reactive-consensus extension.

### IN-03: No `T ≥ 1` guard — `T = 0` yields a degenerate trivial "convergence"

**File:** `src/admm/solve_admm.jl:252-263`
**Issue:** With `T = 0` (and a length-0 `λ₀`, which passes the `length(λ₀) == T` guard), the
coupling-entry count `p = length(load_nodes)*T == 0`, so `ε_pri = ε_dual = 0` and all residual
sums are 0. `converged(residuals, 0, 0)` is then `true` on iteration 1 (`0 ≤ 0`), and the loop
returns a degenerate "converged" result rather than rejecting a nonsensical horizon. The other
boundary guards (empty aggregators, `maxiter ≥ 1`, `allow_export`) are thorough; this is the one
gap.
**Fix:** Add `T ≥ 1 || throw(ArgumentError("solve_admm needs T ≥ 1 (got T=$T)"))` alongside the
existing boundary guards.

### IN-04: Makie convergence plot uses `yscale = log10` on traces that can be zero

**File:** `ext/TSODSOMakieExt.jl:44,72`
**Issue:** `plot_convergence` and `plot_price_convergence` put `primal_trace`, `dual_trace`, and
`price_gap_trace` on a `log10` axis. These are stored `abs(...)` / `ρ·r_norm`, so a value of
exactly `0.0` (e.g. `price_gap = ρ·r_norm` when `r_norm` hits 0, or a residual that is exactly
zero) yields `log10(0) = -Inf`, which Makie rejects/drops. Unlikely with floating-point
residuals but not impossible, and it would break the thesis-grade figure with no graceful
fallback. (Not a correctness issue for the solve itself.)
**Fix:** Clamp the plotted series to a small positive floor (e.g. `max.(trace, eps())`) before
the log axis, or filter non-positive points, so a zero residual degrades gracefully.

---

_Reviewed: 2026-07-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
