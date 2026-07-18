# Theory Extraction — Journal + PSR Papers

> Sources:
> 1. `docs/references/IET Generation Trans Dist - 2019 - Palacios - Dynamic transactive energy scheme...pdf` (10 pp.)
> 2. `docs/references/Expansão-N1-N2-EquilibriosStackelberg-Nash-v2 (1).pdf` (9 pp., PSR internal note, Portuguese)
> Extracted by research agent.

## Paper 1 — IET 2019 (operational layer, published)

Same model as the thesis (see `THEORY-thesis.md`) — day-ahead 24h social-welfare maximization,
BFM/DistFlow SOCP, quadratic prosumer utilities, ADMM decomposition producing DADP/DLMP as duals.

Additional detail vs thesis digest:
- Test system stated as **modified IEEE 13-node feeder**, 13.2 kV, aggregate PV=12 MWp, load=8.45 MW,
  784 prosumers, 112/node. Voltage `0.95²≤v≤1.05²`, `S_max,1=6.86 MVA`. Converges in 28 iterations,
  tol `ε=5×10⁻⁵`.
- Explicit SOCP relaxation `l_{i,j} ≥ (P²+Q²)/v_i` (eq. 36) + Gan–Low exactness affine constraints
  (37–40, 42).
- DSO welfare settlement eq. (46). KKT proof (App.) that PV-battery subproblem needs no binaries.
- **Not itself a Stackelberg/bilevel game** — supplies the operational lower level + DLMP concept.

## Paper 2 — PSR note: "Reforços interconexões N1-N2 via Stackelberg + Nash" (planning layer)

**This is the explicit Stackelberg-Nash game.** Modeling/methodology note (no numerical case).
References: Zou–Ahmed–Sun 2019 (SDDiP); Bansal–Küçükyavuz 2025 (Integer L-shaped/Lagrangian cuts).

### N1 / N2 and the core trade-off

- **N1 = distribution side (distributor); N2 = transmission side.** The subject is reinforcement of
  the **N1↔N2 interconnections** through which the distributor imports energy.
- A distributor serves (consumption − internal production). It can either **import directly**
  (volatile import profile) or **invest in flexibility** (batteries, flexibility aggregators,
  metering/control/comms) to import the **same total energy less volatilely**. Less volatile import
  ⇒ less interconnection reinforcement needed. So **flexibility investment (N1) reduces transmission
  reinforcement cost (N2)** — the value-of-flexibility lever, quantified operationally by Paper 1.

### Game structure

- **One distributor → Stackelberg equilibrium.** Distributor = **leader** (first level, problem 4):
  chooses flexibility investment + import levels `{z_{y,s}}` anticipating the transmission system's
  (follower's) reinforcement-cost response `α({z_{y,s}})` (second level, problem 2).
  *(Note: the note labels leader/follower inconsistently once; the consistent reading is
  distributor = leader. Confirm with author before hard-coding.)*
- **Multiple distributors → Nash equilibrium** among distributors, each interacting with the
  transmission system via its own Stackelberg equilibrium, taking others' decisions as given.

### Integrated formulation (problem 1, single distributor)

Variables: `x_inv,x_op,s` (N1 transmission reinforcement invest/op), `y_inv,y_op,s` (N2 distributor
invest/op), `y_inv,flex` (flexibility investment), `z_flex,s` (flexibility operation), `z_{x,s},z_{y,s}`
(export/import interconnection flows, scenario s). `(1/S)Σ_s` = scenario expectation.
```
Min c_x,inv·x_inv + c_y,inv·y_inv + c_y,inv,flex·y_inv,flex + (1/S)Σ_s(c_x,op·x_op,s + c_y,op·y_op,s)
s.t.  A·x_inv ≤ b                         (1a)  N1 invest
      x_op,s ≤ M_x·x_inv                  (1b)  N1 invest↔op
      F_x·x_op,s = d_x,s                   (1c)  N1 demand balance
      B·y_inv ≤ h                         (1d)  N2 invest
      y_op,s ≤ M_y·y_inv                   (1e)  N2 invest↔op
      F_y·y_op,s = d_y,s                   (1f)  N2 demand balance
      z_{x,s} − H_x·x_op,s = 0            (1g)  frontier balance N1
      z_{y,s} − H_y·y_op,s − H_{y,flex}·z_flex,s = 0   (1h)  frontier balance N2 + flexibility
      z_flex,s ≤ H_{y,invflex}·y_inv,flex (1i)  flexibility op ≤ flexibility invest
      z_{x,s} − z_{y,s} = 0               (1j)  N1↔N2 COUPLING (export = import)
```

### Solution — Stackelberg via Benders

**Follower (second level, transmission reinforcement) `α({z_{y,s}})`** parameterized by imports:
```
α = Min c_x,inv·x_inv + (1/S)Σ_s c_x,op·x_op,s
    s.t. (2a) A·x_inv≤b ; (2b) x_op,s≤M_x·x_inv ; (2c) F_x·x_op,s=d_x,s ;
         (2d) z_{x,s}−H_x·x_op,s=0 ; (2e) (1/S)z_{x,s}=(1/S)z_{y,s}   [dual π_s]
```
`π_s` = dual of coupling (2e) = **marginal cost of a unit increment of interconnection flow**
(= additional TUST / transmission-use tariff for reinforcement).

**Leader (first level, distributor) with Benders cuts:**
```
Min c_y,inv·y_inv + c_y,inv,flex·y_inv,flex + (1/S)Σ_s c_y,op·y_op,s + α
s.t. (4a)–(4e) [distributor invest/op/coupling/flex] ;
     α ≥ w^k + (1/S)Σ_s π_s^k·(z_{y,s} − z_{y,s}^k),  k=1..K      (4f)  BENDERS CUTS
```
`w^k=α({z_{y,s}^k})`, `π_s^k` = dual at trial imports. Distributor chooses flexibility investment +
import level anticipating transmission reinforcement cost.

### Multiple distributors — Nash via diagonalization

Distributor i's cost depends on its own decisions + others' import levels `{z_{j,y,s}, j≠i}` (which
set shared reinforcement levels). Cut coefficients `w_i^k, π_{i,s}^k` depend on others' reinforcements.
**Nash equilibrium** = each i optimizes taking others' equilibrium flows as fixed (problem 7).
**Solved by Gauss–Seidel diagonalization** — optimize each distributor in turn, fixing others' flows,
iterate to convergence.

### Integer case (MIP) — binary expansion + Lagrangian cuts

Cut representation exact only for binary/continuous LP subproblems. Continuous flow `z_{y,s}` is
**binary-expanded**: `z_{y,s}=z⁺−z⁻`, `z⁺=Δ·Σ_ĵ n⁺_ĵ·2^ĵ`, `n∈{0,1}`, `Δ=z̄/(2^{J+1}−1)`.
Second-level becomes a **MIP** (problem 8); valid cuts generated via the **Lagrangian of the copy
constraints** (problem 9), multipliers from **maximizing the Lagrangian** (Lagrangian / integer
L-shaped cuts, per SDDiP references).

## How the two layers compose (the integrated framework)

The two papers are the **two levels of one TSO–DSO bilevel program**:

- **Paper 1 = operational / market lower level.** Models inside-the-distribution-network operation
  (flexible loads, PV-batteries, aggregators, SOCP AC-OPF) → DLMPs. Quantifies the **value of
  flexibility** and how a distributor reshapes its net import profile. Paper 1's net nodal profile
  `p_{ag_j}[t]` ≈ Paper 2's interconnection flow `z_{y,s}`.
- **Paper 2 = investment / equilibrium upper level.** Embeds distributor operation in an expansion
  game: distributor (leader) trades flexibility investment (N1) vs transmission reinforcement (N2,
  follower); Benders/Stackelberg; Nash (diagonalization) for many distributors; MILP (binary
  expansion + Lagrangian cuts) for discrete investment.
- **Natural architecture:** an operational SOCP/ADMM engine (Paper 1) plays the role of Paper 2's
  second-level subproblem; wrapped in a Benders / diagonalization outer loop (Paper 2) for
  Stackelberg-Nash investment equilibria. Coupling variable = interconnection flow `z`; linking
  price = DLMP (`λ_j[t]`) ↔ interconnection dual (`π_s`).

## Solver mapping (Julia)

- Operational layer: SOCP/QP → Clarabel / SCS / ECOS / Ipopt (Mosek if licensed).
- Planning masters / MILP: **HiGHS** (open source) or Gurobi (commercial fallback).
- Bilevel: Benders (custom) + diagonalization (custom); optionally BilevelJuMP.jl for compact
  MPEC/KKT single-level reductions on small cases.

## Cautionary flags

- Paper 2 leader/follower labeling stated inconsistently once — confirm distributor = leader.
- Paper 2 cut representation exact only for binary/continuous LP subproblems; integer needs the
  binary-expansion + Lagrangian machinery (approximate in flow granularity `Δ`).
- Paper 1 SOCP exactness relies on the LinDistFlow affine voltage constraints — keep them.
