# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)

Full phase details, decisions, and per-phase artifacts are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) and
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md).

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

<details>
<summary>✅ v2.0 Stackelberg-Nash TSO–DSO Planning Game (Phases 10–14) — SHIPPED 2026-07-24</summary>

- [x] Phase 10: Oracle Coupling Wiring & Resilience (2/2 plans) — completed 2026-07-22
- [x] Phase 11: Single-Distributor Stackelberg-Benders (Certified) (3/3 plans) — completed 2026-07-22
- [x] Phase 12: Cut-Store & Benders Master Robustness Hardening (2/2 plans) — completed 2026-07-23
- [x] Phase 13: Nash Diagonalization & Shared-Transmission Coupling (3/3 plans) — completed 2026-07-24
- [x] Phase 14: Validation-Oracle Regression Hardening & Docs (3/3 plans) — completed 2026-07-24

Delivered: the thesis's planning layer (rungs 6–7) — build-once Parameter-pinned planning oracle
with retry/checkpoint resilience, hand-rolled single-distributor Stackelberg-Benders certified
against BilevelJuMP MPEC reductions (leader/follower role + dual sign empirically pinned),
hardened cut store + BendersTrace ledger, SharedTransmission N-distributor corridor coupling,
run_nash! Gauss-Seidel diagonalization with nested tolerances + NashTrace two-level diagnostics,
run_nash_probe multi-seed/multi-order honesty gate ("a converged equilibrium", never "the"),
pinned computed goldens, a registry+tripwire no-binaries guard, and two live-executed literate
planning docs pages. Audit: 15/15 requirements, 10/10 integration seams. 2276 tests pass.

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–9 (archived) | v1.0 | 43/43 | Complete | 2026-07-20 |
| 10. Oracle Coupling Wiring & Resilience | v2.0 | 2/2 | Complete | 2026-07-22 |
| 11. Single-Distributor Stackelberg-Benders (Certified) | v2.0 | 3/3 | Complete | 2026-07-22 |
| 12. Cut-Store & Benders Master Robustness Hardening | v2.0 | 2/2 | Complete | 2026-07-23 |
| 13. Nash Diagonalization & Shared-Transmission Coupling | v2.0 | 3/3 | Complete | 2026-07-24 |
| 14. Validation-Oracle Regression Hardening & Docs | v2.0 | 3/3 | Complete | 2026-07-24 |

## Deferred / Future-Milestone Notes

- **Meshed + 4Q-BESS** (deferred in v1.0 and again in v2.0): breaks the radial exactness proof —
  needs its own relaxation/exactness treatment.
- **Discrete/integer investment expansion** (binary-expansion + integer/Lagrangian cuts): explicitly
  out of v2.0 continuous-only scope; the PVAL-04 no-binaries guard must be consciously lifted when
  this milestone opens.
- **Deferred tech debt**: see `milestones/v1.0-MILESTONE-AUDIT.md` and
  `milestones/v2.0-MILESTONE-AUDIT.md` (Info-severity review findings, user-local
  Project.toml/Manifest CairoMakie drift, Clarabel NUMERICAL_ERROR root cause).
