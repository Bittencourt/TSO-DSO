# TSO-DSO Integration Optimization Framework (Julia)

## What This Is

A Julia research framework for **experimenting with a TSO–DSO integration optimization theory**
built on transactive energy / dynamic distribution pricing and Stackelberg–Nash equilibria. It
implements the two-layer framework from J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022) and the
associated PSR N1–N2 expansion note: an **operational layer** (day-ahead dynamic pricing over a
convex branch-flow distribution network, solved as convex social-welfare maximization decomposed by
ADMM, with prices emerging as duals) and a **planning layer** (Stackelberg–Nash TSO–DSO investment
equilibria solved by Benders + diagonalization). It is the computational bench for Pedro's PhD:
reproducible experiments from simple to complex scenarios, with clean seams for model adaptations
and novel research extensions. Audience: the PhD researcher and collaborators (thesis, papers).

## Core Value

**A researcher can express a scenario and a model variant declaratively, run it end-to-end with an
open-source solver, and get trustworthy, reproducible results and prices — with every model
assumption documented and every layer swappable.** If everything else fails, this must work:
correct, validated optimization models that are easy to extend for research.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Convex operational model: branch-flow (DistFlow/SOCP) distribution power flow with voltage &
      congestion limits, LinDistFlow exactness constraints, validated exact on radial test feeders.
- [ ] Prosumer device models: thermostatic, programmable/deferrable, interruptible flexible loads,
      and PV+battery (BESS), with quadratic concave utility / cost preference functions.
- [ ] Aggregator aggregation of prosumer devices into nodal net power + utility.
- [ ] Social-welfare maximization (`GLB-OPT`/`GLB-CVX`): Σ aggregator utility − wholesale purchase.
- [ ] Two selectable solve strategies for the operational problem: (a) monolithic centralized solve;
      (b) ADMM decomposition (`AGR-OPT` per node + `DSO-OPT` per hour) recovering nodal prices (DADP)
      as duals, with convergence diagnostics.
- [ ] Distribution nodal price (DADP/DLMP) extraction and decomposition (energy/loss/congestion/volt).
- [ ] Scenario & network data layer: define feeders, devices, price profiles; ship IEEE-style radial
      test feeders as fixtures for validation.
- [ ] Abstraction ladder: minimal toy models (small bus count, single period, DC/linear) up to full
      AC-SOCP / multi-period / ADMM — same interfaces at each rung.
- [ ] Open-source solver integration first: HiGHS (LP/MILP), Ipopt (NLP), a conic/SOCP solver
      (Clarabel/SCS); Gurobi only as a commercial fallback behind a common interface.
- [ ] Rich per-step documentation: every model's math, assumptions, and validation documented
      alongside the code; reproducible experiment scripts.
- [ ] Extension seams designed in from the start for: stochastic uncertainty (PV/demand), MPC /
      rolling-horizon / real-time pricing, meshed networks + four-quadrant BESS, and TSO–DSO
      Stackelberg–Nash planning coupling (Benders / diagonalization) with real-data flex valuation.

### Out of Scope

- Full planning-layer (N1–N2 Stackelberg–Nash expansion) *implementation* in v1 — architecture and
  interfaces must accommodate it, but the operational layer ships first. *(Deferred, not excluded.)*
- Real-time hardware / market integration, GUI/dashboards — this is a research/experiment library.
- Reproducing the original MATLAB+CVX codebase line-for-line — we port the *theory*, not the code.
- Unbalanced three-phase / phase-detailed modeling in v1 (thesis uses balanced positive-sequence).
- Stochastic/robust solving as a v1 deliverable — it is a designed-for extension, not initial scope.

## Context

- **Origin theory** (see `.planning/research/THEORY-thesis.md` and `THEORY-papers.md` for the full
  extraction with equation numbers):
  - Operational layer (Palacios thesis / IET GTD 2019): a **single-level convex social-welfare
    maximization** over a 24h horizon on a **Convex Branch Flow Model** (Baran–Wu DistFlow with SOC
    relaxation + LinDistFlow exactness), with quadratic prosumer utilities, solved **distributedly by
    ADMM**; the day-ahead dynamic price (DADP/DLMP) is the **dual of the nodal active-power balance**.
    *It is not itself an MPEC* — the leader/follower story is conceptual; the machinery is convex
    dual decomposition. Reference cases: modified IEEE 13-node (congestion) and 123-node (voltage)
    feeders. Original implementation: MATLAB + CVX.
  - Planning layer (PSR N1–N2 note): the **explicit Stackelberg–Nash game** — distributor = leader
    choosing flexibility investment + import profile, transmission reinforcement = follower; solved
    by **Benders decomposition**; multiple distributors → **Nash via Gauss–Seidel diagonalization**;
    integer investments → **binary-expansion + Lagrangian/integer-L-shaped cuts**. Coupling variable
    = N1↔N2 interconnection flow; linking price = interconnection dual ≈ DLMP.
- **Named research extension axes** (all four flagged as targets): stochastic PV/demand uncertainty;
  MPC / rolling-horizon / real-time pricing; meshed networks + four-quadrant BESS (Q-V, ancillary
  services); TSO–DSO planning coupling + real-data flexibility-aggregator valuation (Octopus/PSR
  collaboration angle noted in meeting notes).
- **Motivation** (from thesis intro): rising DER/PV penetration in Latin America, flat tariffs that
  don't reflect real costs, prosumer proliferation causing congestion & voltage issues, need for
  dynamic tariff signals coordinating many devices without compromising network security.

## Constraints

- **Tech stack**: Julia + JuMP for optimization modeling — the natural ecosystem for research-grade
  math programming with swappable solvers and good performance.
- **Solvers**: Favor open source — HiGHS (LP/MILP), Ipopt (NLP), Clarabel/SCS (conic/SOCP). Gurobi
  permitted only as a commercial fallback, behind a solver-abstraction so no model hard-depends on it.
- **Correctness**: SOCP relaxation must be validated **exact** on radial fixtures (LinDistFlow trick);
  results must be reproducible (seeded data generation, pinned environment via `Project.toml`/`Manifest.toml`).
- **Extensibility**: architecture must let a researcher swap the power-flow model, device models,
  objective, and solve strategy independently — model adaptations are a first-class use case.
- **Documentation**: rich, step-by-step docs of every modeling decision and its math are a hard
  requirement, not optional. Clean, idiomatic, well-organized Julia code.
- **Audience/purpose**: PhD thesis research — favor clarity, correctness, and traceability to the
  source theory over premature performance optimization.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v1 targets the **operational layer** first (transactive pricing / dynamic pricing) | It is the validated core of the framework and the foundation the planning layer sits on | — Pending |
| **Abstraction ladder** (toy → full AC/ADMM) rather than replicate-then-extend | Prioritizes clean, extensible architecture; validation grows with complexity | — Pending |
| Support **both** centralized (monolithic) **and** ADMM decomposition, selectable per experiment | Centralized = clarity/small cases; ADMM = scale + matches thesis & yields prices as duals | — Pending |
| Julia + **JuMP** with a **solver-abstraction** layer | Research-grade modeling, swappable open-source solvers, Gurobi only as fallback | — Pending |
| Operational layer built as **convex SOCP + ADMM**, *not* MPEC | Matches the actual thesis math; MPEC/bilevel tooling is reserved for the planning layer | — Pending |
| Design **extension seams** for stochastic / MPC-RTP / meshed+4Q-BESS / TSO-DSO Stackelberg-Nash | All four are declared PhD research directions; scaffolding must not preclude them | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-18 after initialization*
