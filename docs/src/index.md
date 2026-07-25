# TSODSO

The **TSO–DSO Integration Optimization Framework** — a Julia + JuMP research bench for
transactive-energy / dynamic distribution pricing and Stackelberg–Nash TSO–DSO investment
equilibria.

Two shipped layers:

- **v1.0 — Operational layer** (rungs 0–5): convex branch-flow social-welfare maximization
  over a 24h horizon, with the day-ahead dynamic price (DADP/DLMP) emerging as the dual of
  the nodal active-power balance, solved centrally and by hand-rolled ADMM.
- **v2.0 — Planning layer** (rungs 6–7): the bilevel TSO–DSO investment game — distributor
  leaders choosing flexibility investment / import profiles against a transmission-reinforcement
  follower, solved by hand-rolled Benders decomposition, extended to a multi-distributor Nash
  equilibrium via Gauss-Seidel diagonalization over a shared transmission corridor.

## Reproducibility pipeline

Every model page below executes its real `src/` entrypoint during the documentation build, so
every rendered number, price, and equilibrium is a genuine solve — never a placeholder — and the
documented results cannot drift from the code.

## Model Documentation

**Operational layer (v1.0):**

- [Rung 0: Toy DC](generated/toy_dc.md) — the architectural spine proven end-to-end on a
  toy single-node DC solve.
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

**Planning layer (v2.0):**

- [Rung 6: Stackelberg–Benders (planning)](generated/stackelberg_benders.md) — the
  single-distributor leader/follower investment equilibrium: build-once planning oracle with the
  `p_import == z` coupling pin and its dual `π_s`, the transmission-reinforcement follower LP with
  genuine Farkas certificates, and the hand-rolled Benders loop — with the interpretive
  leader/follower choice and coupling-dual sign convention certified 4-ways against BilevelJuMP
  MPEC reductions.
- [Rung 7: Nash Diagonalization & Shared Corridor](generated/nash_diagonalization.md) — the
  multi-distributor game: per-distributor investment ownership over one pooled corridor capacity,
  `run_nash!` Gauss-Seidel diagonalization with strictly nested inner/outer tolerances, two-level
  convergence diagnostics, and the multi-seed / multi-order probe that reports "**a** converged
  equilibrium (spread: …)" — never "the" equilibrium.

## Validation & regression posture

The planning layer ships with permanent regression infrastructure: the BilevelJuMP certification
case, pinned computed goldens for the canonical N=1 and N=2 fixtures (gated by certification
agreement and diagonalization convergence respectively), and an automated no-binaries guard that
fails the test suite if any planning-layer subproblem builder introduces a binary/integer
variable — enforcing the milestone's continuous-only scope structurally, not by convention.
