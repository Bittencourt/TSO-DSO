---
phase: 06-admm-decomposition-core
reviewed: 2026-07-19T06:22:42Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - src/admm/residuals.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/solve_admm.jl
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-07-19T06:22:42Z
**Depth:** deep (cross-file: traced ADMM ↔ `Aggregator.contribute!`, `ConvexBranchFlow`, `ModelContext`, `welfare_solve`/`extract_dlmp` oracle, `assert_socp_exact!`, `assert_battery_complementarity!`, `assert_solved!`, and the `test_admm.jl` cross-validation harness)
**Files Reviewed:** 4
**Status:** issues_found (no BLOCKER; 1 WARNING, 3 INFO)

## Summary

I reviewed the ADMM core adversarially, starting from the hypothesis that the dual-sign
convention, the coefficient-update formula, or the two-block penalty targets contained a
compensating error that happens to pass on the symmetric 2-bus fixture. **None of the
load-bearing algorithmic/economic concerns survived scrutiny — they are correct.** The one
finding worth fixing is a robustness gap in the fail-loud path; the rest is quality/INFO.

**Load-bearing concerns I actively tried to break, and why each holds:**

1. **Coefficient formula `−λ−ρ·c` (AGR) / `−λ−ρ·a` (DSO)** — *correct.* I re-derived both from
   the single MAX augmented Lagrangian `L_ρ = ΣU_ag − λ₀ᵀp_import − Σλ_jᵀR_{p,j} − (ρ/2)Σ‖R‖²`,
   `R_{p,j}=netflow_j+pag_j`. AGR fixes `netflow_j=c_j`: expanding `−(ρ/2)(c_j+pag_j)²` leaves
   linear coeff `−λ_j−ρ·c_j` on `pag_j` (AgrOpt.jl:165). DSO renames `pag_dso:=−netflow_j` so
   `R=a_j−pag_dso_j`; the MIN block `+(ρ/2)(pag_dso−a_j)²−λ_j·pag_dso` gives linear coeff
   `−λ_j−ρ·a_j` (DsoOpt.jl:282). Both match the code exactly, and the fixed `±(ρ/2)pag²`
   quadratic self-term is built once and never touched (`set_objective_coefficient` mutates only
   the affine part — idiomatic for a `QuadExpr` objective).

2. **Dual sign `DADP = −λ_internal`** — *correct, and validated on an ASYMMETRIC case.* The
   reviewer's specific worry ("works on the symmetric 2-bus but breaks asymmetric") is refuted by
   `test_admm.jl:103`, which compares `res.λ` to `extract_dlmp(centralized)` **element-wise on
   every IEEE-13 load node** (`atol=1e-2, rtol=1e-3`) on a congestion+voltage-driven fixture where
   `DADP ≠ λ₀`. The centralized reference (`solve_welfare`) is an *independently built monolith*,
   not derived from ADMM — a genuine oracle, not a self-consistent-but-wrong mirror. A global sign
   error would flip `res.λ` to the negative of `dlmp_c` (≈ 2×price off) and fail `isapprox`
   catastrophically, not marginally. Because both validated fixtures carry uniformly-positive
   prices and the alignment is a single global negation (`λ_mat = reduce(vcat, permutedims(-λ[j]))`,
   solve_admm.jl:260), a hypothetical negative-DADP node would be handled by the same negation —
   there is no per-node sign branch that could diverge. Sound.

3. **Primal residual `R = a_j − pag_dso_j`** — *correct AGR-vs-DSO mismatch.* `a_j = value(pag_j)`
   is the aggregator net injection (`Σp_inject − Pdc`, AgrOpt.jl:98) and `pag_dso_j` is the
   network's injection variable pinned by `:Rp[j]+pag_dso==0` (DsoOpt.jl:203,217). Both denote the
   same physical nodal injection; consensus ⇒ equal. The netflow target `c_j = −pag_dso_j` and the
   AGR target `a_j = pag_j` carry the correct opposite signs (solve_admm.jl:201, header lines
   18–29), and the Gauss-Seidel ordering (AGR→DSO within an iteration, DSO feeds `a` fresh, `c`
   refreshed at iteration end) is standard.

4. **Reactive closure matches centralized exactly.** DSO injects each load node's constant
   `−Pdc·tan(acos φ)` into `:Rq[j]` (DsoOpt.jl:167,209) — bit-identical to `Aggregator.contribute!`
   (Aggregator.jl:155) — plus a free-sign, unpriced `q_import` at root and `:Rq==0` pinned at all
   buses (mirrors `welfare_solve`). No μ dual-ascent (reactive is not a consensus quantity),
   consistent with the fixed `qag` vectors.

5. **Build-once, no state leakage.** No `Model(`/`build_*` call appears inside the loop; only
   scalar `set_objective_coefficient` updates. `test_admm.jl:198-200` asserts the converged DSO
   model has identical `num_variables`/`num_constraints` to a fresh build (SOC cones counted). The
   AGR `:Rp/:Rq` "stray" writes are genuinely dead (coupling uses the returned `res.p_inject`, not
   the residual). λ/c/a are plain `Float64` dicts, never JuMP `Parameter`s (Pitfall 1 respected).

6. **Convergence-vs-mid-loop gates placed correctly.** `assert_socp_exact!` (rtol default `1e-4`,
   matching `solve_welfare`, exactness.jl:78) and the App. C battery check run ONLY on the final
   converged pass; mid-loop uses `strict=false`/`check_*=false`. The exactness gate runs strictly
   after `assert_solved!` and refuses prices on a strict cone — the physical false-convergence net.

**Residual bookkeeping (residuals.jl):** the sequential-`k` guard, `abs`-storing, and empty-ledger
`converged ⇒ false` are all correct.

## Warnings

### WR-01: `maxiter ≤ 0` breaks the fail-loud error path itself (masked BoundsError)

**File:** `src/admm/solve_admm.jl:157, 207-214`
**Issue:** `maxiter` is never validated. With `maxiter = 0` (or negative), `for k in 1:maxiter` is
an empty range, `converged_flag` stays `false`, and control reaches the fail-loud `throw`. But the
error message interpolates `$(last(residuals.primal_trace))` (line 210) on a `primal_trace` that is
still empty (no iteration recorded), so `last([])` raises a `BoundsError` **before** the intended
`ErrorException` is constructed. The user gets an opaque `BoundsError` from deep in string
interpolation instead of the clear "FAILED to converge / retune ρ or raise maxiter" message the
Pitfall-2 contract promises. This is a self-inflicted failure of the very fail-loud guard that is
supposed to be the safety net.
**Fix:** Guard `maxiter` at the boundary alongside the other argument checks (solve_admm.jl:102-110):
```julia
maxiter >= 1 ||
    throw(ArgumentError("solve_admm needs maxiter ≥ 1 (got $maxiter)"))
```
(Alternatively, guard the throw message with `isempty(residuals.primal_trace) ? "n/a" : last(...)`,
but rejecting `maxiter ≤ 0` up front is the cleaner fix and matches the project's fail-loud-early
convention.)

## Info

### IN-01: `tan(arccos φ)` reactive factor duplicated across three modules

**File:** `src/admm/AgrOpt.jl:102`, `src/admm/DsoOpt.jl:167`, `src/devices/Aggregator.jl:135`
**Issue:** `tanφ = sqrt(1 - agg.φ^2) / agg.φ` (thesis 3.23) is hand-inlined in three places. If the
reactive model is ever changed (e.g. a different power-factor convention, or clamping near φ→0),
three sites must move in lockstep or the AGR/DSO/centralized reactive draws silently diverge — the
exact class of split-brain the DSO reactive-closure comment warns about.
**Fix:** Extract a single helper (e.g. `reactive_factor(φ) = sqrt(1 - φ^2) / φ`) next to
`Aggregator` and call it from all three sites, so the thesis-3.23 definition lives once.

### IN-02: `solve_agr!` `strict` kwarg is undocumented in its docstring

**File:** `src/admm/AgrOpt.jl:113-148, 156`
**Issue:** The signature grew a `strict::Bool = true` keyword (line 156) that materially changes the
solve gate (`assert_solved!(dual=true)` vs `allow_almost=true`), but the docstring only documents
`check_battery`/`τ_batt`. A caller reading the docstring cannot discover the mid-loop mode.
`solve_dso!` documents its `strict` flag; this one should match.
**Fix:** Add a `strict` line to the `solve_agr!` docstring mirroring the `solve_dso!` treatment
(strict = fully-OPTIMAL/dual-feasible; `strict=false` = mid-loop near-feasible primal, duals unread).

### IN-03: `AgrOpt.qag` field is computed and stored but never consumed in Phase 6

**File:** `src/admm/AgrOpt.jl:57, 102-103, 110`
**Issue:** `qag` (the constant reactive injection) is built and carried on every `AgrOpt`, but
`solve_admm` never reads `agr.qag` — the reactive μ dual-ascent it is "exposed for" is deferred.
It is harmless and documented as future API surface, but it is currently dead state (and duplicates
the DSO-side `q_draw` computation, see IN-01).
**Fix:** Acceptable to keep as a documented Phase-7 seam; if you prefer a lean struct, drop the
field until the μ update lands and reconstruct it from `agg.Pdc`/`agg.φ` at that time. No action
required for Phase 6 correctness.

---

_Reviewed: 2026-07-19T06:22:42Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
