# Phase 6: ADMM Decomposition Core - Context

**Gathered:** 2026-07-19
**Status:** Ready for planning
**Mode:** Auto-generated (decomposition-algorithm phase — decisions determined by source thesis; discuss skipped)

<domain>
## Phase Boundary

Add the **ADMM solve strategy** as **pure orchestration over the already-validated rung-2 builders** —
per-node `AGR-OPT` (aggregator/device subproblem) + per-hour `DSO-OPT` (network subproblem) with
**dual ascent** — built ONCE and re-solved via parameter/coefficient updates + warm starts (NO
per-iteration JuMP model rebuild) — and prove it recovers the centralized (Phase-4 SOCP) optimum and
duals on every fixture small enough to solve monolithically.

In scope: ADMM-01 (the ADMM AGR-OPT/DSO-OPT split + dual ascent, reusing the exact device/power-flow
builders), ADMM-03 (build-once/re-solve via JuMP Parameters + warm starts — the performance
discipline), ADMM-04 (automated cross-validation: ADMM welfare AND duals match the centralized
optimum within tolerance). Out of scope: convergence hardening / adaptive-ρ / IEEE-123 scale
(Phase 7), the experiment harness (Phase 8), the planning layer (later milestone).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to source thesis + Phases 1–5 seams)
No user-preference grey areas — the ADMM split, the dual-ascent update, and the parameter re-solve
pattern all come from the thesis + CLAUDE.md's explicit ADMM guidance. Anchor to:

- **ADMM split (ADMM-01):** decompose the centralized GLB-CVX into `AGR-OPT` (per-node aggregator/
  device subproblem — house-separable QP) and `DSO-OPT` (per-hour network subproblem — the SOCP
  branch flow), coupled at the aggregator net injection `p_ag` / the nodal price `λ_j`. Dual ascent:
  `λ_j ← λ_j + ρ·R_{p,j}` on the coupling residual. REUSE the exact same device (`contribute!`) and
  power-flow (`ConvexBranchFlow.contribute!`) builders as the centralized `solve_welfare` — ADMM is
  orchestration, not a re-implementation of the models.
- **Build-once / re-solve (ADMM-03, the perf discipline — CLAUDE.md):** construct the `AGR-OPT` and
  `DSO-OPT` JuMP models ONCE, then in the ADMM loop update the price/penalty terms via JuMP
  `Parameter`s (`@variable(m, p in Parameter(v))` + `set_parameter_value`) / `set_normalized_rhs` /
  `set_objective_coefficient`, and WARM-START from the previous iterate. NEVER rebuild a JuMP model
  inside the loop (the dominant avoidable perf sink). Track residuals in a small struct.
- **Cross-validation (ADMM-04):** an automated test asserting ADMM welfare AND duals (DADPs) match the
  centralized monolithic optimum within tolerance on every small fixture (2-bus, IEEE-13). This is
  the correctness gate — ADMM must recover the ground truth from Phase 4.
- **Solver/status discipline (CLAUDE.md):** subproblems solved via `select_optimizer` (AGR-OPT QP →
  Clarabel/HiGHS; DSO-OPT SOCP → Clarabel), gated on `assert_solved!`; the SOCP exactness gate (PF-04)
  applies to the DSO-OPT subproblem so ADMM prices are only trusted when exact.
- **Hand-rolled loop (CLAUDE.md):** no decomposition mega-framework (Coluna/StructJuMP) — a
  hand-rolled dual-ascent loop with full control of the updates, as the thesis and CLAUDE.md prescribe.

### Convergence scope
This phase proves ADMM RECOVERS the centralized optimum on small fixtures. Robust convergence tuning,
adaptive-ρ, dual-residual stopping, and IEEE-123 scale are Phase 7 (a separate STATE concern).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–5)
- `src/models/welfare_solve.jl` — the centralized GLB-CVX assembly ADMM decomposes; the ground truth
  to cross-validate against; the device + power-flow builder call sites to REUSE.
- `src/devices/*` (`contribute!` returning `(;vars,p_inject,utility)`), `src/devices/Aggregator.jl`
  (the per-node aggregation → AGR-OPT), `src/powerflow/ConvexBranchFlow.jl` (the SOCP → DSO-OPT).
- `src/core/ModelContext.jl` (residual registry + `add_to_objective!`; JuMP model access for
  Parameters/warm starts), `src/core/status.jl` (`assert_solved!`), `src/models/exactness.jl`
  (PF-04 gate on the DSO-OPT SOCP), `src/pricing/dlmp.jl` (`extract_dlmp` — the duals to match).
- `src/solver/factory.jl` + `ProblemClass.jl` (`select_optimizer` for QP/SOCP subproblems),
  `src/data/ieee13.jl`, `src/data/profiles.jl`, `src/models/oracle.jl`.

### Established Patterns
- Build-once/re-solve via JuMP `Parameter`s + warm starts (CLAUDE.md perf pattern — verified surface
  in Phase-1 research); dispatch-not-branching; `assert_solved!` gating; computed-golden +
  cross-validation-against-centralized; TestItems `@testitem` (name contains filter substring);
  throw-based validation; every step cites a thesis equation.

### Integration Points
- New `src/admm/` (or `src/decomposition/`) module: the AGR-OPT + DSO-OPT subproblem builders (thin
  wrappers reusing the device/PF `contribute!`), the dual-ascent loop, a residual-tracking struct, and
  the cross-validation harness against `solve_welfare`.

</code_context>

<specifics>
## Specific Ideas

Pull the exact ADMM AGR-OPT / DSO-OPT decomposition, the coupling variable (`p_ag`/`λ_j`), the dual-
ascent update (`λ_j ← λ_j + ρ·R_{p,j}`), the ρ choice for this rung, and the residual definitions from
the thesis reference material in `.planning/research/THEORY-thesis.md` / `docs/references/` during
research so every step traces to a numbered source equation. Confirm the JuMP `Parameter` /
`set_normalized_rhs` / warm-start API surface for the build-once re-solve (CLAUDE.md flagged it for a
doc re-check; Phase-1 research already verified `Parameter` — reconfirm the re-solve mutators). The
cross-validation (ADMM ≈ centralized welfare + duals) is the load-bearing correctness gate.

</specifics>

<deferred>
## Deferred Ideas

- Convergence hardening / adaptive-ρ / dual-residual stopping / IEEE-123 scale → Phase 7.
- Experiment harness / scenario sweeps using ADMM → Phase 8.
- Stochastic / rolling-horizon ADMM variants → later milestone.

</deferred>
