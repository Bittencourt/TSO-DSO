# Phase 11: Single-Distributor Stackelberg-Benders (Certified) - Context

**Gathered:** 2026-07-22
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — proposals accepted per area by user

<domain>
## Phase Boundary

A single distributor's Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower) solves end-to-end via a hand-rolled Benders loop, with the
source-flagged leader/follower role assignment and coupling-dual sign convention resolved
empirically and certified by a tiny BilevelJuMP MPEC cross-check — encoded as a tested invariant,
not left as a code comment. Covers PLAN-04 (follower LP `α(z)` with duals + Farkas certificates),
PLAN-05 (build-once Benders master with persistent optimality + feasibility cuts), PLAN-06
(end-to-end single-distributor convergence with documented gap tolerance), PLAN-07 + PVAL-01
(BilevelJuMP certification gate retained as permanent fast regression).

Out of scope: multiple distributors / Nash diagonalization (Phase 13), cut-store scale hardening
(Phase 12), integer/discrete investment (deferred milestone, PVAL-04 enforces continuous-only),
stochastic scenarios (v2.x).

</domain>

<decisions>
## Implementation Decisions

### Follower LP `α(z)` design (PLAN-04)
- Follower model is a **minimal PSR-note-faithful LP**: linear transmission-reinforcement
  capacity cost + operation subject to delivering the import profile `z[t]`, over a small
  declarative, seeded transmission-corridor fixture (project conventions). No multi-node DC
  transmission network in this phase.
- Infeasibility certificates are **genuine Farkas/dual rays from HiGHS**
  (`dual_status == INFEASIBILITY_CERTIFICATE`; disable presolve if needed to obtain rays) →
  feasibility cuts. No penalized-slack "always feasible" shortcut — success criterion 1 demands
  a real certificate.
- **Single deterministic scenario** in Phase 11, but the API is **scenario-indexed** (`α(z; s)`
  shape) so Phases 12/13 scale without signature breaks. Stochastic solving itself stays
  deferred (v2.x).
- Solver wiring goes through the existing **`select_optimizer(::ProblemClass)`** abstraction
  (HiGHS for follower LP and master). No solver named inside model code.

### Benders master & loop mechanics (PLAN-05/06)
- **Build-once JuMP master** (continuous investment variables + `z[t]` + epigraph `α`);
  optimality and feasibility cuts appended as **persistent constraint rows** — never rebuilt.
  Optimality cuts use the full length-`T` dual vector per Phase 10 D-05:
  `α ≥ cost^k + Σ_t π[t]·(z[t] − z^k[t])`.
- Convergence: **relative gap `(UB−LB)/max(1,|UB|) ≤ tol` (default 1e-6)**, documented formula,
  plus an iteration cap that **raises loudly** on exhaustion (never silent — Phase 10 D-10).
- **Every cut-producing solve** (oracle, follower, master) goes through `solve_with_retry!` and
  the strict `assert_solved!(...; allow_almost=false)` gate; `checkpoint_iteration!` fires per
  Benders iteration exactly as designed in Phase 10 D-10.
- Code organization: new files **`src/planning/follower.jl`, `src/planning/master.jl`,
  `src/planning/benders.jl`**, mirroring the established `build_*` / `solve_*!` build-once
  naming used by `subproblem.jl` and the ADMM modules.

### BilevelJuMP certification gate (PLAN-07, PVAL-01)
- Certification uses **both `BigMMode` and `StrongDualityMode`** on a tiny leader/follower
  instance, cross-checked against a **hand-worked enumeration** of the same toy case — three
  independent answers must agree (success criterion 4).
- BilevelJuMP is a **test-only dependency** (`test/Project.toml`) — production code never
  depends on MPEC machinery, honoring CLAUDE.md's "validation oracle only" rule.
- The invariant is a **permanent fast `@testitem`** (tagged `[:planning]`) asserting the Benders
  equilibrium matches the BilevelJuMP optimum within tolerance AND asserting the certified
  dual-sign/role convention. Retained forever per success criterion 5 — not a one-off script.
- If certification contradicts the assumed leader/follower reading: **the empirical result is
  authoritative** — flip the convention in code + docs and record the resolution in
  STATE/PROJECT decisions. Phase 10 D-06 deliberately left the sign uncommitted for exactly
  this outcome. Do NOT re-resolve by re-reading THEORY-papers.md (STATE.md blocker).

### Claude's Discretion
- Exact toy-instance data for the certification case (must admit hand enumeration).
- Big-M bound derivation for `BigMMode` (research pass covers Fortuny-Amat bound requirements).
- Follower fixture parameterization (corridor capacity, reinforcement cost coefficients).
- Master warm-start strategy across Benders iterations.
- Whether `benders.jl` exposes a single `solve_stackelberg!` entry point or a small loop API.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/subproblem.jl` — `PlanningOracle`, `build_planning_oracle`,
  `solve_planning_oracle!` returning `(; cost, π, π_s, dadp, ctx)`; the Benders subproblem for
  the distributor's operational cost at pinned `z`.
- `src/planning/retry.jl` — `solve_with_retry!` (bounded 4-rung Clarabel-conditioning ladder,
  sticky-escalation contract documented, foreign-backend diagnostic).
- `src/planning/checkpoint.jl` — `checkpoint_iteration!` / `resume_from_checkpoint` (JLD2 +
  git provenance, `iter_%05d` filename contract, 0:99999 bound).
- `src/solver/` — `select_optimizer(::ProblemClass)`, `assert_solved!` (INFRA-03 choke point).
- `src/core/` — `ModelContext` residual registry; `contribute!` seams.

### Established Patterns
- Build-once/re-solve with JuMP `Parameter`s + `set_parameter_value` (ADMM `build_dso_opt`,
  `build_planning_oracle`).
- Fail-loud status gating: no solve result is trusted without `assert_solved!`.
- TestItems suite, `[:planning]` tag, `Phase6Fixtures`/`ToyElasticDevice` fixture modules,
  INFRA-02: no direct solver imports in test files.
- JuliaFormatter v2 CI-enforced; every constraint traceable to a numbered thesis/PSR equation
  in docs.

### Integration Points
- `src/TSODSO.jl` — `planning/` include block (three includes; new files append there).
- `test/` — one test file per planning module (`test_planning_*.jl`).
- Docs: literate per-model math pages expected for the Benders master/follower math
  (hard project requirement; Phase 14 hardens docs, but math documentation lands with code).

</code_context>

<specifics>
## Specific Ideas

- Roadmap research note (HIGH): focused research pass required before coding — BilevelJuMP's
  exact mode API surface (`BigMMode`/`StrongDualityMode` construction, Fortuny-Amat bound
  requirements) and the empirical leader/follower semantic resolution. Plan-phase should run
  with a research pass.
- Phase 10 D-05 fixed the optimality-cut form; Phase 11 wires it for real.
- STATE.md blocker discipline: PSR N1-N2 note is MEDIUM-confidence and internally inconsistent
  on leader/follower labeling — resolve empirically via the certification gate only.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Standing deferrals: integer investment,
stochastic scenarios, MCP/VI recast — tracked in STATE.md Deferred Items.)

</deferred>
