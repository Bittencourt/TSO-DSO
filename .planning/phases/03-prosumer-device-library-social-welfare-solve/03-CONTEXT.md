# Phase 3: Prosumer Device Library & Social-Welfare Solve - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Auto-generated (modeling phase — decisions determined by source thesis theory; discuss skipped)

<domain>
## Phase Boundary

Deliver the full prosumer **device library** (thermostatic, deferrable, PV+battery), an **aggregator
roll-up**, and the **`GLB-CVX` social-welfare** objective, solved centrally on the Phase-2 linear
branch-flow formulation with **seeded reproducible profiles** — a complete multi-device welfare solve
at linear fidelity, before SOCP complexity (Phase 4).

In scope: DEV-01, DEV-02, DEV-04, DEV-05 (device models + aggregator), OPT-01 (GLB-CVX social-welfare
objective), DATA-04 (seeded Markov-chain demand/PV profiles). Out of scope: SOCP/exact convex branch
flow (Phase 4), DADP/DLMP price decomposition (Phase 5), ADMM (Phase 6+).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to source theory + Phase 1–2 seams)
No user-preference grey areas — every model follows the source thesis (device models, App. C battery
parametrization, GLB-CVX). Anchor to:

- **Device contract (Phase 2):** every device is an `AbstractDevice` whose `contribute!` adds decision
  variables, temporal-coupling constraints, a concave quadratic utility (via `add_to_objective!`), and
  a signed injection into `ctx.residuals` — and NEVER references the network/topology.
- **Thermostatic load:** temperature state dynamics (RC/ETP-style recursion) + comfort-band utility.
- **Deferrable load:** energy-budget / time-window coupling with a concave utility.
- **PV + battery (BESS):** SOC dynamics, PV-limited charge, charge-utility/discharge-cost preferences —
  **NO binary variables**; rely on the App. C parametrization so `p_ch·p_dch ≈ 0` holds at the optimum
  (never simultaneous charge/discharge). This is a hard correctness requirement — verify complementarity
  numerically at the solution.
- **Aggregator (DEV-05):** rolls its member devices into nodal net active/reactive power and total
  utility; the aggregator (not the device) is what the network sees. Device modules stay
  network-agnostic (enforced by grep + design).
- **GLB-CVX (OPT-01):** social-welfare objective = Σ aggregator utility − wholesale/MEM purchase cost,
  assembled from device utility terms + the linear power-flow model, solved centrally to a **global**
  optimum via `select_optimizer(QP())` (convex QP — Clarabel for accurate duals), gated on OPTIMAL.
- **Seeded profiles (DATA-04):** first-order Markov-chain demand and PV profile generation that is
  **reproducible** (same seed → identical profiles). Use a seeded RNG passed explicitly; no global RNG
  state. Feeds the solve.
- **Solver/status discipline (CLAUDE.md):** no model names a concrete solver; `assert_solved!` gates.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–2)
- `src/devices/AbstractDevice.jl` + `Interruptible.jl` — device contract + the first concrete device to
  pattern the new ones after.
- `src/core/ModelContext.jl` — indexed `add_to_residual!(ctx,name,i,t,expr)` + `add_to_objective!`
  (QuadExpr) accumulators; residual-kind mismatch now errors loudly.
- `src/models/linear_solve.jl` — centralized assembly + balance closure + `dual(nodal_balance)`;
  generalize toward the GLB-CVX social-welfare solve (device bus-range validation already added).
- `src/powerflow/{DCPowerFlow,LinDistFlow}.jl` — the linear formulations the welfare solve runs on.
- `src/solver/factory.jl` (`select_optimizer(QP())`), `src/core/status.jl` (`assert_solved!`),
  `src/data/Feeder.jl`, `src/units/PerUnit.jl`.

### Established Patterns
- Immutable concretely-typed structs; concave-utility→`add_to_objective!`; network-agnostic devices;
  throw-based validation; TestItems `@testitem` per seam (name contains the filter substring);
  reproducibility via committed manifests + seeded RNG.

### Integration Points
- New `src/devices/` modules (thermostatic, deferrable, PV+battery) + an aggregator type; a profile
  generator module (seeded Markov chains); the GLB-CVX social-welfare assembly generalizing
  `linear_solve.jl`.

</code_context>

<specifics>
## Specific Ideas

Pull device dynamics (thermostatic RC, deferrable energy budget, App. C battery no-binary
parametrization), the GLB-CVX objective form, and the Markov-chain profile method from the thesis
reference material in `.planning/research/THEORY-thesis.md` / `docs/references/` during research so
every constraint traces to a numbered source equation (hard project requirement). Verify the battery
complementarity `p_ch·p_dch ≈ 0` numerically at the optimum.

</specifics>

<deferred>
## Deferred Ideas

- SOCP / exact convex branch flow → Phase 4.
- DADP/DLMP price decomposition → Phase 5.
- ADMM decomposition of the welfare solve → Phase 6.

</deferred>
