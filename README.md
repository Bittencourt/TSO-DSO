# TSODSO.jl — TSO–DSO Integration Optimization Framework

[![CI](https://github.com/Bittencourt/TSO-DSO/actions/workflows/CI.yml/badge.svg)](https://github.com/Bittencourt/TSO-DSO/actions/workflows/CI.yml)
[![Docs: stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://bittencourt.github.io/TSO-DSO/stable/)
[![Docs: dev](https://img.shields.io/badge/docs-dev-lightblue.svg)](https://bittencourt.github.io/TSO-DSO/dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A **Julia + JuMP research framework** for experimenting with a TSO–DSO integration
optimization theory built on transactive energy, dynamic distribution pricing, and
Stackelberg–Nash investment equilibria.

It implements the two-layer framework from J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022)
and the associated PSR N1–N2 expansion note, and serves as the computational bench for an
ongoing PhD: reproducible experiments from simple to complex scenarios, with clean seams
for model adaptations and novel research extensions.

> **Core value:** a researcher can express a scenario and a model variant declaratively,
> run it end-to-end with open-source solvers, and get trustworthy, reproducible results
> and prices — with every model assumption documented and every layer swappable.

## The layers

### ⚡ Operational layer (v1.0) — day-ahead dynamic distribution pricing

A single-level **convex social-welfare maximization** over a 24h horizon on a convex
branch-flow (DistFlow/SOCP) distribution network, solved centrally **and** distributedly
by hand-rolled ADMM. The day-ahead dynamic price (DADP/DLMP) emerges as the **dual of the
nodal active-power balance** — prices are never postulated, always recovered from duals.

- Branch-flow power flow behind one swappable residual seam: DC, LinDistFlow, and SOCP
  Convex Branch Flow with the LinDistFlow exactness copy — the SOC relaxation is
  **validated exact** on radial fixtures (IEEE 13 & 123).
- Prosumer device library (thermostatic, deferrable, interruptible, PV+battery — all
  convex, no binaries) rolled up by aggregators into nodal net power + utility.
- Two selectable solve strategies — centralized monolithic and ADMM (`AGR-OPT`/`DSO-OPT`)
  — cross-validated against each other on IEEE 13 (congestion) and IEEE 123 (voltage).
- DADP/DLMP extraction with a 4-way decomposition (energy / loss / congestion / voltage),
  welfare and surplus accounting, feed-in-tariff baseline comparison.

### 🏗 Planning layer (v2.0) — Stackelberg–Nash TSO–DSO investment game

The thesis's bilevel planning game: **distributor-leaders** choose flexibility investment
and import profiles against a **transmission-reinforcement follower**, solved by
hand-rolled **Benders decomposition**; multiple distributors reach a **Nash equilibrium
via Gauss-Seidel diagonalization** over a shared transmission corridor.

- Build-once planning oracle with a JuMP-`Parameter`-pinned `p_import == z` coupling
  constraint; the Benders cut gradient is the coupling dual `π_s` (linking price ≈ DLMP).
- The interpretive **leader/follower role and coupling-dual sign convention are
  empirically certified** against BilevelJuMP MPEC reductions (StrongDualityMode,
  ProductMode, hand enumeration, and the production loop agree 4-ways) — retained as a
  permanent regression.
- `SharedTransmission`: N-distributor coupling with per-distributor investment ownership
  over one pooled corridor capacity row; each Benders solve is an atomic best-response.
- `run_nash!`: Gauss-Seidel diagonalization with inner Benders tolerances asserted
  strictly tighter than the outer Nash tolerance, a two-level convergence ledger
  (`NashTrace`), and CairoMakie convergence plots.
- **Honest non-uniqueness reporting**: `run_nash_probe` re-solves across ≥3 seeds × 2
  sweep orders and reports "**a** converged equilibrium (spread: …)" — never "the"
  equilibrium. The never-"the" rule is encoded in code, not prose.
- Continuous-only scope is **enforced by an automated no-binaries guard** over every
  planning-layer subproblem builder (registry + tripwire, negative-tested).

### 🔬 Validation & reproduction (v2.1) — hardening both layers

Every downstream extension rests on validated, citable ground:

- **AC-exactness oracle**: an independent nonconvex AC-OPF peer (`ACPowerFlow`, Ipopt,
  true equality `l·v = P² + Q²`) certifies the SOCP relaxation per-hour
  (`assert_ac_exact!`, report-don't-throw). It surfaced a **genuine high-PV/reverse-flow
  inexactness** of the SOC relaxation as a first-class, citable finding.
- **Certified reactive DLMP**: a genuine per-node reactive balance behind a
  `reactive_consensus` flag (byte-identical default path), whose certified dual is a
  documented 5th DLMP component — never summed into the active-price total.
- **Real IEEE-123 impedances**: positive-sequence R₁/X₁ reduced from the public OpenDSS
  case via a dependency-free Fortescue parser (no PMD runtime dependency).
- **Directional thesis reproduction**: the thesis's DSO-surplus **sign flip reproduces**
  on real public data; the +25% welfare-ratio magnitude does **not** — stated plainly,
  always with the "directional, public-data" qualifier, pinned only on sign-safe
  quantities.

## Quickstart

Requires Julia ≥ 1.10 (CI runs 1.10 / 1.11 / 1.12).

```julia
using Pkg
Pkg.activate(".")          # from a clone of this repository
Pkg.instantiate()
using TSODSO
```

**Run a declarative operational scenario** (seeded, bit-for-bit reproducible):

```julia
s = Scenario(name = "demo", feeder = :ieee13, strategy = :admm, seed = 1, T = 24)
res = run_scenario(s)      # → welfare, DADP prices, exactness gap, ADMM residuals
```

**Solve a small Stackelberg–Nash planning game** (N=2 distributors, shared corridor):

```julia
shared = build_shared_transmission(;
    N = 2, T = 1, corridor_cap = 2.0,
    x_inv_max = [0.3, 0.5], c_inv = [1.0, 3.0],
    c_op = [[0.1], [0.1]],
)
# specs = one per-distributor Benders/oracle spec each (see the Rung 7 docs page
# for the complete runnable fixture)
result = run_nash!(specs, shared; z0 = zeros(2, 1), tol_outer = 1e-4)
result.converged, result.z, result.x_inv   # Gauss-Seidel Nash fixed point
```

See the [documentation](https://bittencourt.github.io/TSO-DSO/stable/) for complete,
executable examples — every model page runs its real solver entrypoint during the docs
build, so every rendered number is a genuine solve.

## Documentation

The [docs site](https://bittencourt.github.io/TSO-DSO/stable/) is organized as an
**abstraction ladder** — each rung a runnable, literate page tracing the implementation
to the thesis/PSR equations it encodes:

| Rung | Page | Theory |
|------|------|--------|
| 0 | Toy DC | architectural spine, solver factory, duals |
| 1–2 | LinDistFlow | thesis 3.31–3.33, 3.43 |
| 3 | SOCP + Exactness | thesis 3.39, 3.43–3.45 |
| 3 | AC-Exactness Oracle | Farivar & Low (2013), Gan et al. (2015); nonconvex AC peer |
| 3 | Devices + GLB-CVX | thesis 3.2–3.23, 3.38 |
| 4 | DADP/DLMP Pricing | thesis 3.31, 3.46–3.47 |
| 5 | ADMM Decomposition | thesis 3.46–3.47 |
| — | IEEE-123 Real Impedances | public OpenDSS case, Fortescue reduction |
| — | Thesis Reproduction — IEEE-123 | thesis Case B, directional/public-data |
| — | Thesis Reproduction — Assumptions | full assumption/reduction chain |
| — | SOC Relaxation Applicability | measured exactness-boundary maps |
| 6 | Stackelberg–Benders (planning) | PSR N1–N2 note; BilevelJuMP certification |
| 7 | Nash Diagonalization & Shared Corridor | PSR N1–N2 note, multi-distributor |

Plus a full API reference for the ~130-symbol public surface.

## Design principles

- **Open-source solvers first**, behind a factory: Clarabel (SOCP/QP — accurate duals for
  price recovery), HiGHS (LP/MILP), Ipopt (NLP). Gurobi/Mosek only as weakdep-gated
  fallbacks; **no model ever names a concrete solver**.
- **Build once, re-solve many**: ADMM/Benders/Nash outer loops mutate JuMP `Parameter`s
  and RHS — models are never rebuilt inside a loop.
- **Fail loud**: every solve passes an `assert_solved!` status gate; guards raise
  `ArgumentError`s rather than warn; retry ladders (`solve_with_retry!`) escalate solver
  conditioning explicitly and are instrumented, never silent.
- **Traceability**: every constraint maps to a numbered thesis/PSR equation, documented
  beside the code in literate pages.
- **Reproducibility**: declarative `Scenario`s, seeded data generation, DrWatson-stamped
  result storage (git commit + Manifest), pinned environments.

## Repository layout

```
src/
  core/         solver status gate, model context, residual registry
  solver/       ProblemClass-keyed optimizer factory (Clarabel/HiGHS/Ipopt; Gurobi/Mosek ext)
  units/        per-unit system
  data/         feeder data model, IEEE 13/123 fixtures, seeded profiles
  powerflow/    DC / LinDistFlow / SOCP convex branch-flow residual seams
  devices/      convex prosumer device library
  models/       GLB-CVX social-welfare centralized solve
  pricing/      DADP/DLMP extraction, 4-way decomposition, welfare accounting
  admm/         AGR-OPT / DSO-OPT decomposition, adaptive ρ, convergence diagnostics
  planning/     oracle, follower LP, Benders master + loop, SharedTransmission, Nash
  experiments/  declarative Scenario / run_scenario / sweeps / DrWatson storage
  diagnostics/  plotting stubs (CairoMakie via package extension)
ext/            CairoMakie / Gurobi / Mosek package extensions
docs/           Documenter + Literate sources (the rung ladder) + Typst writeups
scripts/        authored analysis & reproduction scripts (offline, seeded)
test/           ~2,350 tests: unit, golden regressions, acceptance gates, guards
```

## Testing & regression posture

`Pkg.test()` runs the full gate: unit tests, **pinned computed goldens** (gate-then-golden:
validity gates asserted before pinned values), the BilevelJuMP certification case, the
IEEE-13/123 acceptance regressions, the no-binaries guard, Aqua + JET quality checks.
CI additionally builds the docs with `checkdocs = :exports` strict — an undocumented
exported symbol fails the build.

## Status

| Milestone | Scope | Status |
|-----------|-------|--------|
| v1.0 Operational Transactive-Energy Core | rungs 0–5, DADP/DLMP, ADMM | ✅ shipped 2026-07-20 |
| v2.0 Stackelberg-Nash TSO–DSO Planning Game | rungs 6–7, Benders + Nash | ✅ shipped 2026-07-24 |
| v2.1 Validation & Reproduction | AC oracle, reactive DLMP, real IEEE-123 impedances, directional thesis reproduction | ✅ shipped 2026-07-26 |
| v3.0 Research Extension Rungs | overvoltage-capable relaxation, MPC/rolling-horizon/RTP, stochastic scenarios, meshed + 4Q-BESS, integer investment expansion | 📋 scoped 2026-07-26 (Phases 19–24) |

## Theory sources

- J.P. Palacios, *PhD thesis*, UNSJ/CONICET, 2022 — operational layer (single-level convex
  social-welfare maximization; DADP as nodal-balance dual; IET GTD 2019 companion paper).
- PSR N1–N2 expansion note — planning layer (Stackelberg–Nash investment game, Benders
  decomposition, Gauss-Seidel diagonalization; coupling variable = N1↔N2 interconnection
  flow, linking price = interconnection dual ≈ DLMP).

This repository ports the *theory*, not the original MATLAB+CVX code, and documents every
departure (e.g., per-distributor investment ownership over the pooled corridor) where the
sources leave choices open.

## License

[MIT](LICENSE)
