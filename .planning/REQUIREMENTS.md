# Requirements: TSO-DSO Integration Optimization Framework (Julia)

**Defined:** 2026-07-18
**Core Value:** A researcher can express a scenario and model variant declaratively, run it end-to-end
with an open-source solver, and get trustworthy, reproducible results and prices — every assumption
documented, every layer swappable.

> "User" = the PhD researcher and collaborators. Requirements are theory-derived (see
> `.planning/research/`), organized along the abstraction ladder (rungs 0–5).

## v1 Requirements

Requirements for the operational transactive-energy layer + its extension seams. Each maps to a phase.

### Infrastructure & Reproducibility

- [x] **INFRA-01**: Researcher can instantiate the Julia package with a pinned environment
      (`Project.toml` + committed `Manifest.toml`, `[compat]` floors) that resolves cleanly on Julia 1.10 LTS + 1.11.
- [x] **INFRA-02**: Any model requests its solver via a single `select_optimizer(::ProblemClass)`
      factory; no model file names a concrete solver (HiGHS/Clarabel/Ipopt default; Gurobi/Mosek opt-in behind it).
- [x] **INFRA-03**: Every solve asserts `termination_status == OPTIMAL` (with tight duality gap for conic)
      and fails loudly on non-optimal status or hidden constraint slack.
- [x] **INFRA-04**: Experiments are reproducible — random data generation is seeded and logged; a run
      records its inputs, config, and environment so results regenerate bit-for-bit.
- [x] **INFRA-05**: One consistent per-unit system; all external data is converted once at ingestion,
      with magnitude-sanity assertions guarding unit/scale mistakes.

### Network Data Model

- [x] **DATA-01**: Researcher can define a radial distribution feeder (buses, branches with r/x, limits,
      MEM frontier node) as immutable data structs independent of JuMP.
- [x] **DATA-02**: The framework validates that a feeder is radial (tree) and reports a clear error
      otherwise (SOC exactness holds only on radial trees).
- [x] **DATA-03**: Modified IEEE 13-node and 123-node test feeders ship as built-in fixtures with the
      thesis parameters (voltage limits, head-branch capacity, price profiles).
- [x] **DATA-04**: Researcher can generate seeded inelastic-demand and PV profiles via first-order
      Markov-chain synthesis (data generation only, outside the optimization).

### Prosumer Device Library

- [x] **DEV-01**: Thermostatic-load model (temperature linear in power, comfort bounds) contributing
      variables, constraints, and a quadratic utility term to a model.
- [x] **DEV-02**: Programmable/deferrable-load model (energy-within-window) with quadratic utility.
- [x] **DEV-03**: Interruptible/elastic-load model (power bounds) with concave quadratic utility.
- [x] **DEV-04**: PV + battery (BESS) model with SOC dynamics, PV-limited charge, and charge-utility /
      discharge-cost preferences — **without binary variables** (App. C parametrization guarantees no simultaneous charge/discharge).
- [x] **DEV-05**: Aggregator aggregates its prosumers' devices into nodal net active/reactive power and
      total utility; device modules never reference the network directly.

### Power-Flow Formulations

- [x] **PF-01**: A swappable power-flow interface (`AbstractPowerFlow`) lets a formulation contribute
      branch/voltage terms into the shared nodal-balance residual with no `if formulation ==` branching.
- [x] **PF-02**: DC / LinDistFlow linear formulations for the lower rungs of the abstraction ladder.
- [x] **PF-03**: SOCP Convex Branch Flow formulation (DistFlow SOC relaxation) with the LinDistFlow
      exactness copy (aux `v̂` + affine voltage bounds) as part of the model definition.
- [x] **PF-04**: After any SOCP solve, an automated invariant asserts relaxation exactness
      (`max|l·v − (P²+Q²)| < τ` per branch) on both an easy and a high-PV/over-voltage fixture.

### Objective & Centralized Solve

- [x] **OPT-01**: Social-welfare objective `GLB-CVX` = Σ aggregator utility − wholesale (MEM) purchase
      cost, assembled from device utility terms + the power-flow model.
- [x] **OPT-02**: A centralized monolithic solve produces the global optimum as ground truth, with the
      nodal-balance dual available.
- [x] **OPT-03**: The centralized solve is exposed as an `operational_oracle(z) → (cost, π)` returning
      the frontier coupling dual, so the future planning game wraps it without a rewrite.

### Pricing & Welfare Accounting

- [x] **PRICE-01**: Extract the day-ahead dynamic price (DADP/DLMP) as the dual of the nodal
      active-power balance, per node per hour.
- [x] **PRICE-02**: Decompose the DLMP into energy / loss / congestion / voltage components that sum to
      the nodal price with correct sign (validated by assertion).
- [x] **PRICE-03**: Welfare accounting split into social / DSO / prosumer surplus, plus a FIT baseline
      for comparison (reproduces the +25%-social-welfare headline).
- [x] **PRICE-04**: Economic-direction sanity checks (price below wholesale at PV glut, above at congestion).

### ADMM Decomposition

- [x] **ADMM-01**: ADMM decomposition solves the operational problem via per-node aggregator subproblems
      (`AGR-OPT`) + per-hour network subproblem (`DSO-OPT`) with dual ascent, reusing the same builders as centralized.
- [x] **ADMM-02**: ADMM stops on **both** primal and dual residuals with per-unit-normalized adaptive `ρ`
      (no hard-coded scale-specific penalty).
- [x] **ADMM-03**: An automated cross-validation test asserts ADMM welfare and duals match the
      centralized optimum on every fixture small enough to solve monolithically.
- [x] **ADMM-04**: ADMM subproblems are built once and re-solved via parameter/coefficient updates +
      warm starts (no per-iteration model rebuild).
- [x] **ADMM-05**: Convergence diagnostics (residual traces, iteration count, price convergence) are
      reported and plottable.

### Experiments, Docs & Extension Seams

- [x] **EXP-01**: Researcher can define a scenario declaratively (feeder + devices + price profile +
      config) and run it end-to-end with either solve strategy.
- [x] **EXP-02**: Parameter sweeps over scenarios run and store results in a flat, versioned,
      diff-friendly format.
- [x] **EXP-03**: Every model has literate, reproducible documentation stating its math (equation
      references), assumptions, and validation, built via Documenter + Literate.
- [x] **EXP-04**: Regression fixtures pin reference results (IEEE 13/123, FIT comparison) so numerical drift is caught.
- [x] **SEAM-01**: Extension interfaces exist as stubs/hooks in v1 — multi-scenario objective hook,
      rolling-horizon parameter, meshed-formulation slot, and the coupling-flow interface (`z ↔ p_ag`,
      `λ_j ↔ π_s`) with an explicit leader/follower role parameter — without implementing the extensions.

## v2 Requirements

Deferred research-extension axes (designed-for, not built in v1). Each becomes its own milestone/phase.

### Stochastic Optimization

- **STOCH-01**: Scenario-based stochastic day-ahead dispatch under PV/demand uncertainty.
- **STOCH-02**: Scenario decomposition strategy plugged into the existing objective hook.

### MPC / Real-Time Pricing

- **MPC-01**: Rolling-horizon (1–3h) re-solve loop for real-time pricing.
- **MPC-02**: Model-predictive-control experiment harness over the rolling horizon.

### Meshed Networks & Four-Quadrant BESS

- **MESH-01**: Power-flow formulation for meshed (non-radial) networks (with its own relaxation/exactness treatment).
- **MESH-02**: Four-quadrant BESS inverter model (Q-V control) + ancillary-service remuneration.

### Stackelberg-Nash Planning Game (N1–N2 Expansion)

- **PLAN-01**: Bilevel Stackelberg expansion — distributor (leader) flexibility investment vs
      transmission reinforcement (follower) via Benders decomposition over the `operational_oracle`.
- **PLAN-02**: Multiple-distributor Nash equilibrium via Gauss–Seidel diagonalization.
- **PLAN-03**: Integer-investment case via binary-expansion of coupling flow + Lagrangian / integer-L-shaped cuts.
- **PLAN-04**: Real-data flexibility-aggregator valuation (Octopus/PSR collaboration angle).

## Out of Scope

| Feature | Reason |
|---------|--------|
| GUI / dashboard | Research library, not an application — results consumed via scripts/notebooks |
| Real-time / hardware-in-the-loop integration | Out of research scope; day-ahead + rolling-horizon simulation only |
| Unbalanced three-phase modeling (v1) | Thesis uses balanced positive-sequence; adds large complexity for no v1 research value |
| MPEC/KKT tooling for the *operational* layer | It is a single-level convex program — reaching for MPEC is a category error |
| Line-for-line MATLAB+CVX port | We port the *theory*, not the original code |
| BESS charge/discharge binaries | App. C proof makes them unnecessary; adding them breaks convexity + ADMM pricing |
| Premature performance optimization | Correctness and clarity first; optimize only where scaling demands |

## Traceability

Populated during roadmap creation. All v1 requirements map to exactly one phase (see `.planning/ROADMAP.md`).

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-05 | Phase 1 | Complete |
| DATA-01 | Phase 1 | Complete |
| DATA-02 | Phase 1 | Complete |
| PF-01 | Phase 1 | Complete |
| PF-02 | Phase 2 | Complete |
| DEV-03 | Phase 2 | Complete |
| DEV-01 | Phase 3 | Complete |
| DEV-02 | Phase 3 | Complete |
| DEV-04 | Phase 3 | Complete |
| DEV-05 | Phase 3 | Complete |
| OPT-01 | Phase 3 | Complete |
| DATA-04 | Phase 3 | Complete |
| PF-03 | Phase 4 | Complete |
| PF-04 | Phase 4 | Complete |
| OPT-02 | Phase 4 | Complete |
| OPT-03 | Phase 4 | Complete |
| DATA-03 | Phase 4 | Complete |
| SEAM-01 | Phase 4 | Complete |
| PRICE-01 | Phase 5 | Complete |
| PRICE-02 | Phase 5 | Complete |
| PRICE-03 | Phase 5 | Complete |
| PRICE-04 | Phase 5 | Complete |
| ADMM-01 | Phase 6 | Complete |
| ADMM-03 | Phase 6 | Complete |
| ADMM-04 | Phase 6 | Complete |
| ADMM-02 | Phase 7 | Complete |
| ADMM-05 | Phase 7 | Complete |
| EXP-01 | Phase 8 | Complete |
| EXP-02 | Phase 8 | Complete |
| INFRA-04 | Phase 8 | Complete |
| EXP-03 | Phase 9 | Complete |
| EXP-04 | Phase 9 | Complete |

**Coverage:**
- v1 requirements: 35 total (35 distinct IDs across INFRA/DATA/DEV/PF/OPT/PRICE/ADMM/EXP/SEAM)
- Mapped to phases: 35/35 — every v1 requirement maps to exactly one phase ✓
- Unmapped: 0
- v2 requirements (STOCH/MPC/MESH/PLAN): out of this milestone's scope — not mapped (future milestones)

---
*Requirements defined: 2026-07-18*
*Last updated: 2026-07-18 after roadmap creation (traceability populated)*
