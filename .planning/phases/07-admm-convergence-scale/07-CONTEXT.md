# Phase 7: ADMM Convergence & Scale - Context

**Gathered:** 2026-07-19
**Status:** Ready for planning
**Mode:** Auto-generated (algorithm-hardening phase — decisions determined by ADMM theory + thesis; discuss skipped)

<domain>
## Phase Boundary

**Harden ADMM convergence and scale it to the IEEE 123-node voltage case** — correct **primal+dual**
residual stopping, **per-unit-normalized adaptive ρ** (NO hard-coded scale-specific penalty), and
**first-class convergence diagnostics** (residual traces, iteration count, price convergence —
plottable) — so the Phase-6 decomposition is trustworthy on the research-target regimes.

In scope: ADMM-02 (primal+dual stopping + per-unit-normalized adaptive ρ + fail-loud iteration cap),
ADMM-05 (convergence diagnostics, reported + plottable), and the IEEE 123-node voltage-constrained
scale case (converges in ~tens of iterations, `λ_j → DADP`, exactness invariant holding at
convergence). Out of scope: the experiment harness (Phase 8), documentation gate (Phase 9), the
planning layer (later milestone).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to ADMM theory + Phases 4–6 seams)
No user-preference grey areas — the adaptive-ρ scheme, the dual residual, and the stopping criteria
come from standard ADMM theory (Boyd et al.) + the thesis. Anchor to:

- **Primal + dual stopping (ADMM-02):** stop on BOTH the primal residual (block mismatch) AND the dual
  residual (change in the consensus variable between iterations, scaled by ρ) falling below
  per-unit-normalized tolerances (`ε_abs + ε_rel·norm`), per Boyd §3.3. Hitting the iteration cap
  FAILS LOUDLY (throws) — never returns the last iterate silently (Phase-6 already fail-loud; keep it).
- **Per-unit-normalized adaptive ρ (ADMM-02):** residual-balancing adaptive ρ (Boyd §3.4.1): `ρ ← τ·ρ`
  when the primal residual >> dual residual, `ρ ← ρ/τ` when dual >> primal, within a band; NO
  hard-coded scale-specific penalty (the Phase-6 fixed ρ=5/100 must become adaptive). Because prices
  ARE duals and the subproblems are per-unit, normalize the residuals so ρ is scale-invariant across
  2-bus / IEEE-13 / IEEE-123. **RESEARCH FLAG (ROADMAP): adaptive-ρ on the SOCP DSO-OPT subproblem is
  finickier than QP-only ADMM** — the ρ-penalty coefficient update must stay consistent with the
  build-once `set_objective_coefficient` discipline (changing ρ changes the quadratic penalty weight,
  not just the linear term — handle the penalty-weight update without rebuilding, or document the
  minimal re-setup). Research must resolve this concretely.
- **Convergence diagnostics (ADMM-05):** report residual traces (primal + dual per iteration),
  iteration count, and price convergence (`λ_j` trajectory → DADP); make them PLOTTABLE. This likely
  introduces **CairoMakie** (the CLAUDE.md publication-figure choice) as a dependency — a diagnostics/
  plotting seam that produces vector figures (residual-vs-iteration, price convergence). Flag the dep;
  keep plotting OPTIONAL (a package extension or a thin seam) so the core solve doesn't hard-depend on
  a heavy plotting stack, and so headless CI stays fast.
- **IEEE-123 scale case:** build the IEEE 123-node voltage-constrained feeder fixture (immutable
  JuMP-free `Feeder`, radial-validated, per-unit), run ADMM on it, and assert it converges in ~tens of
  iterations with `λ_j → DADP` (cross-validated against the centralized SOCP where still solvable
  monolithically) and the PF-04 exactness invariant holding at the converged point. SparseArrays for
  the larger topology (CLAUDE.md perf).
- **Solver/status discipline (CLAUDE.md):** subproblems via `select_optimizer`; `assert_solved!`;
  PF-04 exactness on the converged DSO-OPT; no model names a solver; build-once/re-solve preserved.

### Reuse
Hardens the Phase-6 `solve_admm` loop + AGR-OPT/DSO-OPT builders — adaptive-ρ + dual-residual +
diagnostics are additions to the existing loop, plus the IEEE-123 fixture. The Phase-6 cross-validation
(ADMM ≈ centralized) must still pass on 2-bus/IEEE-13.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–6)
- `src/admm/solve_admm.jl` (the dual-ascent loop to harden — add dual residual + adaptive ρ),
  `src/admm/residuals.jl` (AdmmResiduals ledger — extend with the dual residual + traces),
  `src/admm/{AgrOpt,DsoOpt}.jl` (the subproblems whose ρ-penalty coefficient must update adaptively).
- `src/models/welfare_solve.jl` + `src/pricing/dlmp.jl` (centralized cross-validation on 2-bus/IEEE-13),
  `src/models/exactness.jl` (PF-04 at convergence), `src/data/ieee13.jl` (the fixture pattern to
  replicate for IEEE-123), `src/data/Feeder.jl` + `src/units/PerUnit.jl` (immutable feeder + per-unit),
  `src/solver/factory.jl`, SparseArrays.

### Established Patterns
- Build-once/re-solve via set_objective_coefficient (ρ-penalty-weight update is the new wrinkle);
  fail-loud maxiter; cross-validation against centralized; TestItems `@testitem` (name contains filter
  substring); committed version-specific manifests; every step cites a thesis/Boyd reference.

### Integration Points
- Extend `src/admm/` (adaptive-ρ + dual residual + stopping); a new `src/diagnostics/` (or an ext) for
  the plottable convergence figures (CairoMakie); a new IEEE-123 fixture in `src/data/`.

</code_context>

<specifics>
## Specific Ideas

Pull the adaptive-ρ residual-balancing scheme (Boyd et al. §3.4.1) + the primal/dual residual
definitions + stopping tolerances (§3.3), and the IEEE-123 feeder parameters, from Boyd's ADMM
monograph + the thesis reference material during research. RESOLVE the SOCP-subproblem adaptive-ρ
finickiness (ROADMAP research flag): how to update the quadratic ρ-penalty weight in AGR-OPT/DSO-OPT
each iteration WITHOUT a full rebuild (or the minimal accepted re-setup), keeping build-once. Confirm
whether CairoMakie (+ Makie) should be a hard dep, a test/docs-only dep, or a package extension —
prefer keeping the core solve plot-free and headless-CI-fast. Cross-validate IEEE-123 ADMM against the
centralized SOCP where monolithically solvable.

</specifics>

<deferred>
## Deferred Ideas

- Experiment harness / scenario sweeps → Phase 8.
- Documentation / literate convergence-study pages → Phase 9 (this phase produces the plottable
  diagnostics; the literate write-up is Phase 9).
- Stochastic / rolling-horizon ADMM → later milestone.

</deferred>
