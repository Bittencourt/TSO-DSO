# TSODSO

Walking-skeleton chassis for the **TSO–DSO Integration Optimization Framework** — a
Julia + JuMP research bench for transactive-energy / dynamic distribution pricing and
Stackelberg–Nash TSO–DSO investment equilibria.

Phase 1 stands up the architectural spine: a JuMP-free immutable feeder data model, a
solver factory keyed on a `ProblemClass` type (no model ever names a concrete solver),
a solve-status discipline choke point, a per-unit system, and a shared nodal-balance
residual registry — all proven end-to-end on a toy single-node DC solve.

## Reproducibility pipeline

The [Rung 0: Toy DC](generated/toy_dc.md) page executes the real `solve_toy_dc`
during the documentation build, so the documented results cannot drift from the code.
It is the first proof that every seam connects.

## Model Documentation

Phase 9 (EXP-03) extends the reproducibility pipeline to every rung of the
abstraction ladder — each page below executes its real `src/` entrypoint during
the Documenter build, so every rendered number and price is a genuine solve, never
a placeholder:

- [Rung 1-2: LinDistFlow](generated/lindistflow.md) — the linear branch-flow
  assembly and the residual-seam contract (thesis 3.31-3.33, 3.43).
- [Rung 3: SOCP + Exactness](generated/convex_branch_flow.md) — the convex
  branch-flow relaxation and the LinDistFlow exactness copy (thesis 3.39, 3.43-3.45).
- [Rung 3: Devices + GLB-CVX](generated/prosumer_welfare.md) — the prosumer
  device library rolled into the aggregator social-welfare solve (thesis 3.2-3.23, 3.38).
- [Rung 4: DADP/DLMP Pricing](generated/pricing_dlmp.md) — the day-ahead dynamic
  price and its four-way decomposition, plus welfare accounting (thesis 3.31, 3.46-3.47).
- [Rung 5: ADMM Decomposition](generated/admm.md) — the hand-rolled 2-block
  dual-ascent decomposition, cross-validated against the centralized solve
  (thesis 3.46-3.47).
