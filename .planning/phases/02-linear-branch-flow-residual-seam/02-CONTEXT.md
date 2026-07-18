# Phase 2: Linear Branch-Flow Residual Seam - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Auto-generated (modeling phase — decisions determined by source theory + Phase 1 seam; discuss skipped)

<domain>
## Phase Boundary

Establish the residual-seam contract that everything downstream reuses: a **swappable linear
power-flow formulation** (DC and LinDistFlow) and **one flexible device** (interruptible/elastic
load) that meet ONLY at the shared nodal residual (`Rp`/`Rq`), and the **first nodal-balance dual**
(the first price signal) emerging from a centralized linear solve.

In scope: PF-02 (linear power-flow formulations conforming to `AbstractPowerFlow`), DEV-03 (one
flexible device conforming to a device contract). Both plug into the Phase-1 `ModelContext` residual
registry with NO `if formulation ==` / `if device ==` branching. Out of scope: SOCP/convex branch
flow (Phase 4), full device library (Phase 3), ADMM/decomposition (Phase 6+), pricing decomposition
beyond exposing the raw nodal-balance dual (Phase 5).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to source theory + Phase 1)
All modeling choices follow the source thesis/papers and the Phase 1 seam — there are no
user-preference grey areas here; correctness follows the theory. Anchor to:

- **`AbstractPowerFlow` contract (Phase 1):** DC and LinDistFlow are concrete subtypes; each
  `contribute!`s branch/voltage terms into `ctx.residuals[:nodal_balance]` (and reactive residual
  for LinDistFlow). Dispatch on the formulation type — never `if formulation ==` branching.
- **LinDistFlow:** the linearized branch-flow (DistFlow without the loss/quadratic term) with
  voltage-magnitude-squared variables, per the thesis. DC is the pure active-power linearization.
  Both must be interchangeable behind the same residual interface (success criterion 4).
- **Flexible device (DEV-03):** an interruptible/elastic load contributing decision variables, a
  **concave quadratic utility** term to the objective, and a **signed injection** into the residual —
  and it must NOT reference the network/topology (device↔network decoupling is the whole point).
- **Centralized solve:** assemble device + power-flow contributions into one convex model, solve via
  the Phase-1 `select_optimizer` factory (LP for DC-only; QP once the concave-quadratic utility is
  present → Clarabel or HiGHS as the factory decides), gate on `OPTIMAL` via `assert_solved!`, and
  expose `dual(nodal_balance)` as the first price signal.
- **Solver discipline (CLAUDE.md):** no model file names a concrete solver; use `select_optimizer`.

### Interface-conformance testing
A conformance test must prove DC↔LinDistFlow swap requires zero change to device or assembly code,
and that the device contributes without touching the network.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 1)
- `src/core/ModelContext.jl` — residual registry (`register_constraint!`, `add_to_residual!`,
  `ctx.residuals[:nodal_balance]`). The seam this phase builds on.
- `src/powerflow/AbstractPowerFlow.jl` — the contract (with the `contribute!` stub) to make concrete.
- `src/solver/factory.jl` + `ProblemClass.jl` — `select_optimizer(::ProblemClass)`; add a QP class if
  not already present for the concave-quadratic utility.
- `src/core/status.jl` — `assert_solved!` (and `assert_no_slack`, still to be wired where meaningful).
- `src/data/Feeder.jl`, `src/units/PerUnit.jl` — feeder structs + per-unit for the linear model.
- `src/models/toy_dc.jl` — the rung-0 pattern to generalize into a real feeder-based linear solve.

### Established Patterns
- Immutable, concretely-typed structs; SparseArrays incidence; residual accumulation via the context;
  TestItems `@testitem` per seam; throw-based validation (not `@assert`).

### Integration Points
- New: `src/powerflow/` concrete formulations (DC, LinDistFlow); `src/devices/` (or similar) for the
  flexible device + device contract; a `src/models/` linear assembly generalizing toy_dc.

</code_context>

<specifics>
## Specific Ideas

Pull the exact LinDistFlow / device-utility equations from the thesis reference PDFs in
`docs/references/` (Palacios thesis + the IET transactive-energy paper) during research so every
constraint traces to a numbered thesis equation (a hard project requirement).

</specifics>

<deferred>
## Deferred Ideas

- SOCP / exact convex branch flow → Phase 4.
- Full prosumer device library + aggregator roll-up → Phase 3.
- DADP/DLMP price decomposition (beyond raw nodal-balance dual) → Phase 5.
- ADMM decomposition → Phase 6.

</deferred>
