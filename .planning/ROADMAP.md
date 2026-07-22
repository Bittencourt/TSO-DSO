# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- 📋 **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (planned)

Full phase details, decisions, and per-phase artifacts for v1.0 are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md).

## Phases

<details>
<summary>✅ v1.0 Operational Transactive-Energy Core (Phases 1–9) — SHIPPED 2026-07-20</summary>

- [x] Phase 1: Plumbing & Solver Abstraction (4/4 plans) — completed 2026-07-18
- [x] Phase 2: Linear Branch-Flow Residual Seam (4/4 plans) — completed 2026-07-18
- [x] Phase 3: Prosumer Device Library & Social-Welfare Solve (5/5 plans) — completed 2026-07-18
- [x] Phase 4: Convex Branch-Flow Correctness Milestone (6/6 plans) — completed 2026-07-19
- [x] Phase 5: Distribution Pricing — DADP & DLMP Decomposition (5/5 plans) — completed 2026-07-19
- [x] Phase 6: ADMM Decomposition Core (4/4 plans) — completed 2026-07-19
- [x] Phase 7: ADMM Convergence & Scale (6/6 plans) — completed 2026-07-19
- [x] Phase 8: Experiment Harness & Reproducibility (4/4 plans) — completed 2026-07-20
- [x] Phase 9: Documentation & Regression Acceptance Gate (5/5 plans) — completed 2026-07-20

Delivered: the full operational layer (rungs 0–5) — solver abstraction, residual-seam power-flow
(DC/LinDistFlow/SOCP Convex Branch Flow with validated exactness), prosumer device library +
GLB-CVX social welfare, DADP/DLMP dual-based pricing with 4-way decomposition, ADMM decomposition
validated against the centralized optimum (IEEE 13 + 123), a reproducible experiment harness, and
literate per-model docs + an end-to-end regression acceptance gate. 1946 tests pass.

</details>

### 📋 v2.0 Stackelberg-Nash TSO–DSO Planning Game (Planned)

**Milestone Goal:** Add the thesis's planning layer — a bilevel TSO–DSO investment equilibrium
where distributor-leaders choose flexibility investment / import profiles against a
transmission-reinforcement follower, reaching a Nash equilibrium across multiple distributors via
Gauss-Seidel diagonalization. Continuous investment variables only; hand-rolled Benders +
diagonalization; BilevelJuMP as a small-case validation oracle only (never the production solver).

- [x] **Phase 10: Oracle Coupling Wiring & Resilience** - Wire the real z-pin coupling constraint/dual, reconcile the dual convention, and make repeated oracle solves resilient before any Benders code depends on them (completed 2026-07-22)
- [ ] **Phase 11: Single-Distributor Stackelberg-Benders (Certified)** - A hand-rolled Benders loop solves a single distributor's leader/follower equilibrium end-to-end, with the leader/follower semantics resolved and certified by a tiny BilevelJuMP MPEC cross-check
- [ ] **Phase 12: Cut-Store & Benders Master Robustness Hardening** - Harden the Benders cut store, gap diagnostics, and retry/checkpoint mechanics at realistic iteration counts before nesting a second (Nash) outer loop
- [ ] **Phase 13: Nash Diagonalization & Shared-Transmission Coupling** - Multiple distributors reach a Gauss-Seidel Nash fixed point over a genuinely new shared transmission-reinforcement coupling model, with honest non-uniqueness reporting
- [ ] **Phase 14: Validation-Oracle Regression Hardening & Docs** - One-off validation runs become permanent pinned regressions; planning math is literate-documented; an automated guard enforces continuous-only scope

## Phase Details

### Phase 10: Oracle Coupling Wiring & Resilience

**Goal**: The real `p_import == z` coupling constraint and its dual are wired live into a build-once
oracle subproblem, the hourly distribution dual is reconciled to a single per-scenario
interconnection dual, and repeated oracle re-solves are resilient to the known intermittent
Clarabel `NUMERICAL_ERROR` — all before any Benders code depends on these seams.
**Depends on**: Phase 9 (v1.0 `operational_oracle` + SEAM-01 stubs)
**Requirements**: PLAN-01, PLAN-02, PLAN-03
**Success Criteria** (what must be TRUE):

  1. A build-once oracle subproblem exposes `p_import == z` as a live JuMP `Parameter` constraint
     and returns its dual — superseding the current `ArgumentError` SEAM-01 stub — while
     `operational_oracle`/`solve_welfare` remain unmodified.

  2. The hourly distribution dual `λ_j` reconciles to a single per-scenario interconnection dual
     `π_s` via a documented time-aggregation + sign convention, validated against a hand-computed
     toy case.

  3. An oracle solve wrapped in bounded retry + checkpointing survives an injected/observed
     `NUMERICAL_ERROR` without silently corrupting or aborting a run.

  4. No planning-layer subproblem introduces a binary/integer variable (continuous-only scope
     preserved from the first phase onward).
**Plans**: 2 plans

Plans:
**Wave 1**

- [x] 10-01-PLAN.md — resilience primitives: solve_with_retry! (escalating Clarabel-conditioning retry around assert_solved!) + checkpoint_iteration!/resume_from_checkpoint (DrWatson @tagsave round-trip), wave 1

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 10-02-PLAN.md — PlanningOracle: build_planning_oracle (build-once, Parameter-pinned p_import==z coupling) + solve_planning_oracle! (retry-wrapped re-solve, pi/pi_s reconciliation, dual-sign toy-case regression), wave 2, depends on 10-01

### Phase 11: Single-Distributor Stackelberg-Benders (Certified)

**Goal**: A single distributor's Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower) solves end-to-end via a hand-rolled Benders loop, with the
source-flagged leader/follower role assignment and coupling-dual sign convention resolved
empirically and certified by a tiny BilevelJuMP MPEC cross-check — not left as a code comment.
**Depends on**: Phase 10
**Requirements**: PLAN-04, PLAN-05, PLAN-06, PLAN-07, PVAL-01
**Success Criteria** (what must be TRUE):

  1. A transmission-reinforcement follower LP `α(z)` returns the coupling dual `π_s` for feasible
     `z` and an infeasibility/Farkas certificate for infeasible `z`.

  2. The Benders master accumulates both optimality and feasibility cuts as persistent constraint
     rows (no per-iteration rebuild), with every cut-producing solve gated by the strict
     `assert_solved!(...; allow_almost=false)` check.

  3. A single-distributor Stackelberg equilibrium converges end-to-end with a reported
     upper/lower-bound gap below a documented tolerance.

  4. A tiny BilevelJuMP (`BigMMode`/`StrongDualityMode`) certification case, cross-checked against
     a hand-worked toy enumeration, empirically resolves the leader/follower role assignment and
     coupling-dual sign convention, encoded as a tested invariant.

  5. The BilevelJuMP certification case is retained in the test suite as a permanent, fast
     regression (not a one-off validation run).
**Plans**: 3 plans
**Research note**: HIGH — SUMMARY.md flags this phase for a focused research pass on BilevelJuMP's
exact mode API surface (`BigMMode`/`StrongDualityMode` construction, Fortuny-Amat bound
requirements) and the empirical leader/follower semantic resolution before coding the
certification case. Consider `/gsd:plan-phase 11 --research-phase`.

Plans:
**Wave 1**

- [x] 11-01-PLAN.md — FollowerLP (build_follower/solve_follower!, genuine HiGHS Farkas certificates) + BendersMaster (build_master, add_optimality_cut!/add_feasibility_cut!/solve_master!, bounded epigraphs, persistent cut rows), wave 1

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 11-02-PLAN.md — solve_stackelberg!: build-once Benders orchestration over PlanningOracle/FollowerLP/BendersMaster, UB/LB gap convergence, per-iteration checkpointing, fail-loud maxiter, wave 2, depends on 11-01

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 11-03-PLAN.md — BilevelJuMP certification: BigMMode + StrongDualityMode vs. hand enumeration vs. the production Benders answer, permanent [:planning] regression (PLAN-07/PVAL-01), wave 3, depends on 11-02

### Phase 12: Cut-Store & Benders Master Robustness Hardening

**Goal**: The Benders mechanics that the Nash diagonalization loop (Phase 13) will call repeatedly
and at higher volume — feasibility-cut edge cases, cut-store growth, retry-budget tuning,
convergence-gap instrumentation — are proven solid at single-distributor scale before a second
outer loop is nested on top.
**Depends on**: Phase 11
**Requirements**: Hardening pass — deepens PLAN-05 (persistent cut accumulation) and PLAN-06
(UB/LB gap convergence detection) delivered in Phase 11; no new requirement IDs are owned by this
phase (100% coverage of the 15 v2.0 requirements is preserved via the Traceability table).
**Success Criteria** (what must be TRUE):

  1. Feasibility-cut edge cases (degenerate/near-infeasible candidate `z`) are exercised by
     dedicated tests and handled without corrupting the persistent cut store.

  2. Benders UB/LB gap convergence diagnostics are finalized as their own purpose-built struct —
     explicitly NOT a copy of ADMM's dual-ascent residual-based stopping criterion.

  3. The bounded retry/checkpoint mechanism from Phase 10 is load-tested at realistic Benders
     iteration counts without exhausting its retry budget or losing a checkpoint.

  4. No planning-layer subproblem introduces a binary/integer variable.

**Plans**: TBD

### Phase 13: Nash Diagonalization & Shared-Transmission Coupling

**Goal**: Multiple distributors reach a Gauss-Seidel Nash fixed point over a genuinely new shared
transmission-reinforcement coupling model (`src/planning/coupling.jl`), each distributor's Benders
solve treated as an atomic best-response, with honest multi-seed/multi-order non-uniqueness
reporting.
**Depends on**: Phase 12
**Requirements**: NASH-01, NASH-02, NASH-03, NASH-04
**Success Criteria** (what must be TRUE):

  1. `src/planning/coupling.jl` models the shared N2/transmission-reinforcement signal that every
     distributor's Benders best-response reads and updates — without it, "Nash" has nothing shared
     to iterate on.

  2. Gauss-Seidel diagonalization across N≥2 distributors converges to a fixed point, with each
     distributor's Benders solve treated as an atomic best-response and inner tolerances strictly
     nested tighter than the outer Nash tolerance.

  3. Two-level convergence diagnostics — inner Benders UB/LB gap and outer Nash residual — are
     computed together and are plottable across the diagonalization sweep.

  4. Nash convergence is probed across multiple seeds and multiple sweep orders as a gating
     acceptance criterion, and results are reported as "a converged equilibrium" with the observed
     spread — never "the" equilibrium.

  5. No planning-layer subproblem introduces a binary/integer variable.

**Plans**: TBD
**Research note**: MEDIUM — SUMMARY.md flags this phase for Gauss-Seidel/diagonalization
convergence theory for multi-leader-multi-follower games (general literature, no project-specific
numerical case exists) and treats the `coupling.jl` model design itself as a genuine research
decision, not a lookup. Consider `/gsd:plan-phase 13 --research-phase`.

### Phase 14: Validation-Oracle Regression Hardening & Docs

**Goal**: One-off validation runs (BilevelJuMP certification, diagonalization convergence) become
permanent regression infrastructure, the planning math is literate-documented and traced to code,
and continuous-only scope is enforced automatically rather than by convention.
**Depends on**: Phase 13
**Requirements**: PVAL-02, PVAL-03, PVAL-04 (PVAL-01 is delivered and retained as a permanent
regression starting in Phase 11)
**Success Criteria** (what must be TRUE):

  1. Canonical single-distributor (N=1) and multi-distributor (N=2) fixtures are pinned as
     computed goldens, gated by BilevelJuMP agreement (N=1) and diagonalization convergence (N=2)
     — there is no external numerical reference case for the planning layer.

  2. Literate Documenter pages map the PSR planning-layer problem numbers, the coupling seam
     (`z↔p_ag`, `λ_j↔π_s`), and the interpretive leader/follower choice to the actual code,
     `@example`-executed.

  3. An automated no-binaries guard fails CI/tests if any planning-layer subproblem builder
     introduces a binary/integer variable, enforcing the milestone's continuous-only scope
     end-to-end (not just by convention).

  4. The BilevelJuMP certification case (PVAL-01) remains green in the permanent regression suite,
     wired into the same CI gate as the new goldens.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 10 → 11 → 12 → 13 → 14

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Plumbing & Solver Abstraction | v1.0 | 4/4 | Complete | 2026-07-18 |
| 2. Linear Branch-Flow Residual Seam | v1.0 | 4/4 | Complete | 2026-07-18 |
| 3. Prosumer Device Library & Social-Welfare Solve | v1.0 | 5/5 | Complete | 2026-07-18 |
| 4. Convex Branch-Flow Correctness Milestone | v1.0 | 6/6 | Complete | 2026-07-19 |
| 5. Distribution Pricing — DADP & DLMP Decomposition | v1.0 | 5/5 | Complete | 2026-07-19 |
| 6. ADMM Decomposition Core | v1.0 | 4/4 | Complete | 2026-07-19 |
| 7. ADMM Convergence & Scale | v1.0 | 6/6 | Complete | 2026-07-19 |
| 8. Experiment Harness & Reproducibility | v1.0 | 4/4 | Complete | 2026-07-20 |
| 9. Documentation & Regression Acceptance Gate | v1.0 | 5/5 | Complete | 2026-07-20 |
| 10. Oracle Coupling Wiring & Resilience | v2.0 | 2/2 | Complete    | 2026-07-22 |
| 11. Single-Distributor Stackelberg-Benders (Certified) | v2.0 | 2/3 | In Progress|  |
| 12. Cut-Store & Benders Master Robustness Hardening | v2.0 | 0/TBD | Not started | - |
| 13. Nash Diagonalization & Shared-Transmission Coupling | v2.0 | 0/TBD | Not started | - |
| 14. Validation-Oracle Regression Hardening & Docs | v2.0 | 0/TBD | Not started | - |

## Research Flags

- **Phase 11** (HIGH): leader/follower semantic resolution + coupling-dual sign/scale
  reconciliation are empirical, not literature-answerable — expect a focused research pass on
  BilevelJuMP's exact mode API surface before coding the certification case.

- **Phase 13** (MEDIUM): Gauss-Seidel/diagonalization convergence theory for multi-leader-
  multi-follower games is general literature (no project-specific numerical case exists); the
  `coupling.jl` model design is a genuinely new research decision, not a lookup.

- **Meshed + 4Q-BESS** (future milestone, deferred again in v2.0): breaks the radial exactness
  proof — needs its own relaxation/exactness treatment.

- **Deferred tech debt** (see `milestones/v1.0-MILESTONE-AUDIT.md`): thesis welfare-headline figure
  digitization (Phase 4/5), IEEE-123 exact App. E impedances (Phase 7), sub_seed cross-version hash
  stability (Phase 8, WR-02), docstring `@docs` manual wiring + JuliaFormatter-on-docs (Phase 9).
