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
It is the first proof that every seam connects; richer per-model math documentation
arrives in Phase 9.
