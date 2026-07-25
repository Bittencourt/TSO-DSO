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

## Current Milestone: v2.1 Validation & Reproduction

**Goal:** Harden the framework's core correctness claims so every downstream extension — and the
thesis itself — rests on validated, citable ground. No new research axis; this milestone deepens
trust in what already exists.

**Target features:**
- **AC-exactness oracle** — wire Ipopt AC-OPF as an independent nonconvex oracle and certify the SOCP
  Convex Branch Flow solution matches true AC to tolerance on the radial fixtures (replacing the
  current toy-point + same-relaxation self-check).
- **Reactive-power consensus** — implement the μ dual-ascent placeholder (`AgrOpt.jl`) so DERs carry
  reactive power, restoring voltage/DLMP credibility and enabling a meaningful AC comparison.
- **Real IEEE-123 impedances** — replace the synthetic representative values in `ieee123.jl` using the
  public OpenDSS IEEE-123 dataset via PMD-parse + a documented positive-sequence reduction.
- **Directional thesis reproduction** — reproduce the *structure* of the thesis welfare result (gain
  sign and rough magnitude) with real, standard data, pinned as goldens; exact-figure reproduction is
  a stretch goal contingent on obtaining thesis Appendix E.

**Key context / decisions:** Discrete/integer investment, stochastic, MPC/rolling-horizon, and
meshed+4Q-BESS are deliberately deferred to later thrusts. Exact reproduction of the thesis
+$1,819/+25% headline is *not* a hard requirement — the source Appendix E lives behind an IP-blocked
CONICET repository, so v2.1 uses public IEEE-123 data + a documented reduction instead (see
`memory/ieee123-real-impedances-source.md`).

## Requirements

### Validated

- ✓ Convex operational model: branch-flow (DistFlow/SOCP) power flow with voltage & congestion limits,
      LinDistFlow exactness constraints, validated exact on radial test feeders — v1.0
- ✓ Prosumer device models (thermostatic, deferrable, interruptible, PV+battery — no binaries) with
      concave quadratic utility/cost — v1.0
- ✓ Aggregator aggregation of prosumer devices into nodal net power + utility — v1.0
- ✓ Social-welfare maximization (`GLB-CVX`): Σ aggregator utility − wholesale purchase — v1.0
- ✓ Two selectable solve strategies — centralized monolithic **and** ADMM (`AGR-OPT`/`DSO-OPT`, DADP as
      duals, convergence diagnostics), cross-validated on IEEE 13 + 123 — v1.0
- ✓ DADP/DLMP extraction + 4-way decomposition (energy/loss/congestion/voltage) — v1.0
- ✓ Scenario & network data layer + IEEE 13/123 radial fixtures — v1.0
- ✓ Abstraction ladder (toy DC → SOCP/multi-period/ADMM) with stable interfaces per rung — v1.0
- ✓ Open-source solver integration behind `select_optimizer` (HiGHS/Ipopt/Clarabel; Gurobi/Mosek fallback) — v1.0
- ✓ Rich per-model documentation (Documenter + Literate, math+assumptions+validation) + reproducible experiment scripts — v1.0
- ✓ Extension seams (SEAM-01) for stochastic / MPC-RTP / meshed+4Q-BESS / Stackelberg-Nash — delivered as inert stubs — v1.0
- ✓ Planning oracle coupling (`p_import == z` Parameter pin, per-scenario dual `π_s`) with
      retry/checkpoint resilience (PLAN-01..03) — v2.0
- ✓ Single-distributor Stackelberg-Benders, hand-rolled, certified against BilevelJuMP MPEC
      reductions (leader/follower role + dual sign empirically pinned) (PLAN-04..07, PVAL-01) — v2.0
- ✓ Nash via Gauss-Seidel diagonalization over a shared transmission corridor
      (`SharedTransmission`, `run_nash!`, nested tolerances, two-level `NashTrace`,
      multi-seed/multi-order `run_nash_probe` honesty gate) (NASH-01..04) — v2.0
- ✓ Planning-layer permanent regressions: pinned computed goldens, no-binaries guard + tripwire,
      literate planning docs (Rung 6/7) (PVAL-02..04) — v2.0

### Active

**v2.1 Validation & Reproduction** (requirements defined in `.planning/REQUIREMENTS.md`):
- AC-exactness certification of the SOCP branch-flow model against an independent Ipopt AC-OPF oracle
- Reactive-power (μ) consensus in the ADMM operational layer
- Real IEEE-123 impedances from public OpenDSS data via positive-sequence reduction
- Directional reproduction of the thesis welfare result on real data (exact-figure = stretch)

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

## Current State

**Shipped v1.0 "Operational Transactive-Energy Core" (2026-07-20)** — 9 phases, 43 plans, 83 tasks.

The operational transactive-energy layer is complete and validated end-to-end:
- **Solver abstraction** (`select_optimizer(::ProblemClass)`; Clarabel/HiGHS/Ipopt default, Gurobi/Mosek weakdep-gated), `assert_solved!` fail-loud status gate, `ModelContext` residual registry.
- **Power flow** via one swappable residual seam: DC, LinDistFlow, and SOCP Convex Branch Flow with the LinDistFlow exactness copy — relaxation validated exact on radial fixtures.
- **Prosumer device library** (thermostatic, deferrable, interruptible, PV+battery — no binaries) + aggregator roll-up + `GLB-CVX` social-welfare centralized solve + `operational_oracle(z)→(cost,π)`.
- **Pricing**: DADP/DLMP as the dual of the nodal active-power balance, 4-way DLMP decomposition, welfare/surplus accounting + FIT baseline, economic-direction checks.
- **ADMM** decomposition (AGR-OPT / DSO-OPT, adaptive ρ, primal+dual residual stop, build-once/re-solve) validated against the centralized optimum on IEEE 13 (congestion) + 123 (voltage).
- **Reproducibility**: declarative `Scenario` + `run_scenario`/`run_sweep`, seeded/bit-for-bit, provenance-stamped storage (DrWatson).
- **Docs & gate**: literate per-model math pages (Documenter + Literate, `@example`-executed), an end-to-end regression acceptance gate, and pinned regression fixtures.

**Health:** 1946 tests pass / 0 fail / 2 documented-broken (thesis-figure cross-checks); docs build green.

**Known deferred tech debt** (accepted; see `milestones/v1.0-MILESTONE-AUDIT.md`): thesis welfare-headline
figure digitization (Phase 4/5), IEEE-123 exact App. E impedances (Phase 7), `sub_seed` cross-version
hash stability (Phase 8), and an intermittent version-independent Clarabel `NUMERICAL_ERROR` on the
IEEE-13 ADMM solve (post-v1, flagged in STATE.md). *Closed post-v1 (2026-07-20/22):* published docs site
(`DOCUMENTER_KEY` + Pages), docstring `@docs` manual wiring, JuliaFormatter-on-`docs/`, `deploydocs` slug.

## Shipped Milestone: v2.0 Stackelberg-Nash TSO–DSO Planning Game (2026-07-24)

**Shipped 2026-07-24** — 5 phases, 13 plans, 25 tasks, +24,760 LOC. Audit passed 15/15
requirements, 10/10 integration seams, 2276 tests pass (health baseline; the only failing check
on a dirty local checkout is the user-local CairoMakie Project.toml drift — see v2.0 audit).
Next milestone not yet scoped — run `/gsd:new-milestone`.

**Progress:** All phases 10–14 complete (2026-07-24).
- Phase 14 — Validation-Oracle Regression Hardening & Docs: planning goldens pinned
  (`test/fixtures_planning.jl` + gate-then-golden `test_planning_goldens.jl` — N=1 certified
  equilibrium and N=2 Nash equilibrium, probe spread bounded), consolidated 4-builder
  no-binaries guard + source/export tripwire (`test_planning_noninteger.jl`, negative-tested),
  and the Documenter build fixed red→green with a Planning Layer @autodocs section plus two
  live-executed literate rung pages (Rung 6 Stackelberg–Benders narrating the BilevelJuMP
  certification; Rung 7 Nash diagonalization, "a converged equilibrium" language).
  Verification 4/4; review clean after 4 fixes (incl. Deferrable +18 objective-offset
  reconciliation in docs).
- Phase 13 — Nash Diagonalization & Shared-Transmission Coupling: `SharedTransmission` pooled
  N2-corridor coupling model (`coupling.jl`, per-distributor `x_inv[i]` ownership over one shared
  capacity row, build-once/`Parameter`-pinned, `DistributorView` atomic best-response),
  `run_nash!` outer Gauss-Seidel loop with nested-tolerance guard + damping + `NashTrace`
  two-level ledger, `plot_nash_convergence` (CairoMakie ext), and `run_nash_probe` — the NASH-04
  honesty gate: ≥3 seeds × 2 sweep orders, max-pairwise-distance spread, structural
  "**a** converged equilibrium" reporting. Verification 5/5; code review clean after a 3-iteration
  fix loop (6 fixes, incl. CR-01 seed-liveness making the multi-seed dimension genuinely live,
  proven by a distinct-equilibria regression: cold `[0.6,0.6]` vs hot-seed `[0.7,0.0]`).
- Phase 12 — Cut-Store & Benders Master Robustness Hardening: purpose-built `BendersTrace`
  per-iteration convergence ledger (retry counts, master/oracle statuses, solve-only timing),
  degenerate feasibility-cut edge cases proven safe, 66-iteration load test with retry +
  checkpoint active (measured 0 Clarabel escalations on planning fixtures), cut-store growth
  instrumented (unbounded accumulation retained). 4097 tests pass / 0 fail; review clean.
- Phase 10 — Oracle Coupling Wiring & Resilience: `build_planning_oracle`/`solve_planning_oracle!`
  (build-once, `Parameter`-pinned `p_import == z` coupling, per-scenario dual `π_s`),
  `solve_with_retry!` (bounded Clarabel-conditioning ladder), `checkpoint_iteration!`/resume.
- Phase 11 — Single-Distributor Stackelberg-Benders (Certified): `FollowerLP` (genuine HiGHS
  Farkas certificates), `BendersMaster` (build-once, persistent optimality + feasibility cut
  rows, incumbent-tracked UB), `solve_stackelberg!` (end-to-end convergence, rel-gap 1e-6,
  per-iteration checkpointing). **Leader/follower role + coupling-dual sign convention
  empirically certified**: StrongDualityMode, ProductMode, hand enumeration, and the production
  Benders loop independently agree (y*=z*=0.7, cost −0.245) — permanent `[:planning]` regression;
  BigMMode+HiGHS MIQP incapacity pinned as an asserted negative regression. 4039 tests pass /
  0 fail; phase code review clean after 6 fixes.

**Goal:** Add the thesis's planning layer — a bilevel TSO–DSO investment equilibrium where
distributor-leaders choose flexibility investment / import profiles against a transmission-reinforcement
follower, reaching a Nash equilibrium across multiple distributors via Gauss-Seidel diagonalization.

**Target scope:**
- **Multiple distributors → Nash** (Gauss-Seidel diagonalization; each solves its own bilevel vs shared transmission)
- **Continuous investment variables first** — convex Benders master (LP/QP); discrete/integer expansion (binary-expansion + integer/Lagrangian cuts) deferred to a later milestone
- **Hand-rolled Benders + diagonalization** (per CLAUDE.md); **BilevelJuMP as a small-case validation oracle only**, never the production solver
- **Reuses v1's `operational_oracle(z)→(cost,π)`** as the lower level — the coupling seam (`z↔p_ag`, `λ_j↔π_s`, leader/follower role) shipped as SEAM-01 stubs in v1

**Key context / risks:** Source (PSR N1–N2 note) is MEDIUM-confidence; the author flagged
**leader/follower-role inconsistency** and **integer-cut correctness** as open concerns. Mitigation:
research-first, continuous-before-integer, single-bilevel-before-Nash sequencing, and BilevelJuMP
KKT/SOS1/Fortuny-Amat cross-validation on tiny instances. Coupling variable = N1↔N2 interconnection
flow; linking price = interconnection dual ≈ DLMP.

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
| v1 targets the **operational layer** first (transactive pricing / dynamic pricing) | It is the validated core of the framework and the foundation the planning layer sits on | ✓ Good — v1.0 delivered the full operational layer, all 35 requirements verified |
| **Abstraction ladder** (toy → full AC/ADMM) rather than replicate-then-extend | Prioritizes clean, extensible architecture; validation grows with complexity | ✓ Good — rungs 0–5 each shipped a runnable, validated end-to-end solve |
| Support **both** centralized (monolithic) **and** ADMM decomposition, selectable per experiment | Centralized = clarity/small cases; ADMM = scale + matches thesis & yields prices as duals | ✓ Good — ADMM cross-validated against centralized on IEEE 13 + 123 (welfare rtol 1e-4) |
| Julia + **JuMP** with a **solver-abstraction** layer | Research-grade modeling, swappable open-source solvers, Gurobi only as fallback | ✓ Good — `select_optimizer(::ProblemClass)` factory; no model names a solver; Gurobi/Mosek weakdep-gated |
| Operational layer built as **convex SOCP + ADMM**, *not* MPEC | Matches the actual thesis math; MPEC/bilevel tooling is reserved for the planning layer | ✓ Good — SOCP Convex Branch Flow with validated exactness; DADP = dual of nodal balance |
| Design **extension seams** for stochastic / MPC-RTP / meshed+4Q-BESS / TSO-DSO Stackelberg-Nash | All four are declared PhD research directions; scaffolding must not preclude them | ✓ Good — SEAM-01 stubs (multi-scenario hook, rolling-horizon param, meshed slot, coupling-flow z↔p_ag/λ_j↔π_s + leader/follower role) delivered inert in Phase 4; the Stackelberg-Nash seam was consumed live in v2.0 with zero seam rework |
| **Hand-rolled Benders + Gauss-Seidel diagonalization**, BilevelJuMP as validation oracle only | Matches thesis method; MPEC single-level blowup scales poorly and diverges from decomposition intent | ✓ Good — v2.0 production loop is hand-rolled; BilevelJuMP certified the tiny case (4-way agreement) and stays a `[:planning]` regression |
| **Per-distributor investment ownership** over one pooled corridor capacity row (vs equal-split joint investment) | Resolves the N-distributor cost-allocation ambiguity the PSR source leaves open; game-theoretically cleaner best-response pricing | ✓ Good — v2.0 `SharedTransmission`; departure from equal-split documented in coupling.jl for thesis traceability |
| **Continuous-only planning scope**, enforced by an automated no-binaries guard | Convex Benders masters first; integer expansion deferred until Lagrangian/integer-L-shaped cuts milestone | ✓ Good — PVAL-04 guard + tripwire negative-tested; lift consciously when the integer milestone opens |
| **Fresh cut store per Nash best-response** (no cut reuse across sweeps) | Cuts computed at old z_{-i} are generally invalid once neighbors move; correctness-first | ✓ Good — rebuild cost instrumented in trace; cut-reuse deferred until a validity argument exists |
| **"A converged equilibrium" reporting language** (never "the equilibrium"), encoded in code | Diagonalization has no uniqueness guarantee; honesty gate is structural, not prose convention | ✓ Good — run_nash_probe multi-seed/multi-order spread reporting; carried into Rung 7 docs |

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
*Last updated: 2026-07-25 — v2.1 Validation & Reproduction milestone started*
