# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)

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

## Progress

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

## Research Flags (carried to v2)

- **Stackelberg-Nash planning** (v2 milestone): MEDIUM-confidence source, author-flagged leader/follower
  inconsistency, integer-cut correctness — needs dedicated research. v1 delivered only the SEAM-01 stubs.
- **Meshed + 4Q-BESS** (v2 milestone): breaks the radial exactness proof — needs its own relaxation/exactness treatment.
- **Deferred tech debt** (see `milestones/v1.0-MILESTONE-AUDIT.md`): thesis welfare-headline figure
  digitization (Phase 4/5), IEEE-123 exact App. E impedances (Phase 7), sub_seed cross-version hash
  stability (Phase 8, WR-02), docstring `@docs` manual wiring + JuliaFormatter-on-docs (Phase 9).
