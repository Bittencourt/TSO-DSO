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
  `reactive_consensus` flag (bit-for-bit identical default path), whose certified dual is a
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
s = Scenario(name = "demo", feeder = :ieee13, strategy = ADMM(ρ = 100.0),
             pf = :convex_branch_flow, seed = 1, T = 24)
res = TSODSO.run(s.strategy, s)   # → welfare, DADP prices, exactness gap, ADMM details
```

`TSODSO.run(strategy, scenario)` is the single entry point (`run_scenario(s)` is a wrapper).
Strategies: `Centralized()`, `ADMM(...)`, `MPC(...)`, `Stochastic(...)`. The power-flow
formulation is selected with `pf` (`:convex_branch_flow` default, `:restricted_branch_flow`
with `pf_ε`, `:lindistflow`, `:ac`; `pf_thesis_literal` for the default). `Centralized`
accepts all four; ADMM/MPC/Stochastic accept only the default convex formulation until the
ADMM generalisation phase. The legacy flat-kwarg form (`strategy = :admm, ρ = ...`) remains valid.

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
  `ArgumentError`s rather than warn; solver, certificate and non-convergence failures raise
  typed `SolveFailedError` / `CertificateError` / `ConvergenceError` (all `<: TSODSOError`),
  and handlers catch only those, so programming errors always propagate. One documented
  status-vs-throw policy covers every solve entry point (`docs/src/status_policy.md`).
  Retry ladders (`solve_with_retry!`) escalate solver conditioning explicitly and are
  instrumented, never silent.
- **Traceability**: every constraint maps to a numbered thesis/PSR equation, documented
  beside the code in literate pages.
- **Reproducibility**: declarative `Scenario`s, seeded data generation, DrWatson-stamped
  result storage (git commit + Manifest), per-minor pinned environments.

## Repository layout

```
src/
  core/         solver status gate, typed errors + status policy, typed ModelContext,
                residual registry, shared close_balance! helper
  solver/       ProblemClass-keyed optimizer factory (Clarabel/HiGHS/Ipopt; Gurobi/Mosek ext)
  units/        per-unit system
  data/         AbstractFeeder (radial Feeder / MeshedFeeder), IEEE 13/123/8500 fixtures,
                seeded profiles
  powerflow/    DC / LinDistFlow / SOCP convex branch-flow / restricted / meshed / AC
                residual seams (has_reactive, has_branch_current, admm_supported traits)
  devices/      convex prosumer device library
  models/       GLB-CVX social-welfare centralized solve
  pricing/      DADP/DLMP extraction, 4-way decomposition, welfare accounting
  admm/         AGR-OPT / DSO-OPT decomposition (build / iterate / ρ-adapt / certify phases),
                formulation-generic incl. meshed + live reactive pricing, adaptive ρ
  planning/     oracle, follower LP, Benders master + loop, SharedTransmission, Nash
  experiments/  declarative Scenario (pf selector + typed strategies) / TSODSO.run /
                sweeps / DrWatson storage
  diagnostics/  plotting stubs (CairoMakie via package extension)
ext/            CairoMakie / Gurobi / Mosek package extensions
docs/           Documenter + Literate sources (the rung ladder) + Typst writeups
scripts/        authored analysis & reproduction scripts (offline, seeded); see scripts/README.md
test/           ~2,350 tests: unit, golden regressions, acceptance gates, guards
```

## Testing and checks

`Pkg.test()` runs the full gate: unit tests, **pinned computed goldens** (gate-then-golden:
validity gates asserted before pinned values), the BilevelJuMP certification case, the
IEEE-13/123 acceptance regressions, the no-binaries guard, Aqua + JET quality checks.
CI additionally builds the docs with `checkdocs = :exports` strict — an undocumented
exported symbol fails the build.

**Selecting a test set.** `TSODSO_TEST_SET` chooses which items run:

| Value | Runs |
|-------|------|
| unset or `all` | every item (what plain `Pkg.test()` does) |
| `fast` | items not tagged `:slow` (about 474 items, roughly 9 minutes locally) |
| `slow` | only the `:slow` items (37) |

Any other value is an error. CI on push and pull request runs `fast`; the `slow` workflow
runs everything on Julia 1.10 and 1.12 on every push to `main`, nightly, and on manual
dispatch.

The end-to-end correctness gates (the IEEE-13 and IEEE-123 SC3 acceptance items, the ADMM
cross-validation items and the planning certification items) are tagged `:slow`. Pull
requests therefore run only `fast`, and those gates first run when the change lands on
`main`, where every merge triggers the full suite.
`TSODSO_TEST_VERBOSE=1` prints per-item timing. `TSODSO_TEST_FILES=a.jl,b.jl` restricts a
run to those test files (entries are trimmed; a name that matches no test item fails the
run). Discovery is rooted at `test/` (`TestItemRunner.run_tests(test_dir)`), so files
outside it, such as agent worktrees under `.claude/worktrees/`, are never parsed. The IEEE-8500 harness test is manual only (about 15 minutes,
2.7 GB peak); see `scripts/README.md`.

**Filtered runs.** `scripts/run_tests_filtered.jl` runs by tag or file with the test
directory on the load path:

```
JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_admm.jl
```

**JET ratchet.** `scripts/jet_check.jl` compares static-inference reports with the committed
baseline `scripts/jet_baseline.txt` (12 signature lines). It is a ratchet over a multiset:
each baseline line allows one report, so a new report fails even when it normalizes to an
already-listed signature, and a fixed one must be removed from the baseline (`--update`
rewrites it). The check also fails while the baseline still has an UNJUSTIFIED block, and
`--update` exits 1 when it writes one. It runs on Julia 1.12 only; the CI job pins the patch
recorded in the baseline header (1.12.7), so bump both together.

**Flake harness.** `scripts/flake_rate.jl` repeats selected test items in fresh Julia
processes and records outcomes and solver status labels. The measured result was 20 of 20
clean runs on each of two Julia 1.12 patches (a Wilson 95% upper bound on the flake rate of
about 16%).

**Known broken items.** The suite records expected Broken and skipped results in
`test/expected_broken.txt`, one line per test site: `kind | item | test expression |
reason`. Each line allows one record with exactly that item and printed test expression, so
any unlisted record fails the run, including a new `@test_broken` inside an item that is
already listed. The `fit_baseline` item (`welfare surplus accounting: +25% FIT ratio golden
...`) is gated on one specific failure: a `SolveFailedError` with termination
`ALMOST_OPTIMAL` and primal `NEARLY_FEASIBLE_POINT`, raised by the seed AC power-flow solve
inside `fit_baseline`. It was observed on Julia 1.12.7, not on 1.12.5; other patches are
unmeasured. Any other status, or the same status from another solve, fails the item. Expected `Broken` totals for the full suite: 5 on
1.12.5 and 5 on 1.12.7 (with the gate); the fast set contributes 4.

## Environments and manifests

There is deliberately no root `Manifest.toml`. Resolved environments are committed per
Julia minor version: `Manifest-v1.10.toml`, `Manifest-v1.11.toml` and
`Manifest-v1.12.toml`, which Pkg selects automatically. They were verified on Julia
1.10.11, 1.11.9 and 1.12.x; the assumption is the minimum patch of each minor, and a newer
Julia minor resolves fresh from `Project.toml`.

## Status

| Milestone | Scope | Status |
|-----------|-------|--------|
| v1.0 Operational Transactive-Energy Core | rungs 0–5, DADP/DLMP, ADMM | ✅ shipped 2026-07-20 |
| v2.0 Stackelberg-Nash TSO–DSO Planning Game | rungs 6–7, Benders + Nash | ✅ shipped 2026-07-24 |
| v2.1 Validation & Reproduction | AC oracle, reactive DLMP, real IEEE-123 impedances, directional thesis reproduction | ✅ shipped 2026-07-26 |
| v3.0 Research Extension Rungs | overvoltage-capable relaxation, MPC/rolling-horizon/RTP, stochastic scenarios, meshed + 4Q-BESS, integer investment expansion | 📋 scoped 2026-07-26 |

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
