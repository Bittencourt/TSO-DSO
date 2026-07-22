# Feature Research

**Domain:** Research-grade power-system optimization framework (Julia/JuMP) for TSO–DSO transactive energy — convex branch-flow OPF + prosumer device models + ADMM dynamic distribution pricing (DADP/DLMP), extensible to a Stackelberg–Nash planning game.
**Researched:** 2026-07-18
**Confidence:** HIGH (theory grounded in `THEORY-thesis.md` / `THEORY-papers.md`; ecosystem grounded in PowerModels.jl / PowerModelsDistribution.jl / Sienna as reference frameworks)

> **Framing note.** "Users" here are the PhD researcher and collaborators. "Table stakes" means *what any credible research framework in this domain must have to produce trustworthy, reproducible, publishable results* — not consumer-app expectations. "Differentiators" are capabilities that set this framework apart from the general-purpose Julia power stack (PowerModels/PMD/Sienna) and directly serve the thesis's Core Value. "Anti-features" are things that are attractive but would dilute a research library.

---

## Feature Landscape

### Table Stakes (A research framework in this domain is incomplete without these)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| **Radial network data model** (buses/nodes, branches with r/x, parent→child topology, per-unit base) | Every distribution-OPF paper is stated in per-unit on a radial feeder; the branch-flow model *requires* a parent-child tree | MEDIUM | Foundation for everything. Store squared-voltage `v`, squared-current `l`, branch flows `P,Q`. Node 0 = MEM/TSO frontier. |
| **Per-unit handling + base-power/base-voltage bookkeeping** | Numbers in thesis are ¢$/kWh, MVA, kV; results must round-trip to physical units for validation | LOW | Silent unit bugs are the #1 source of "wrong DLMP" errors. Centralize conversion. |
| **Radial-topology validation** (connected tree, single root, no cycles) | SOCP-BFM exactness proof only holds on radial networks; a meshed input silently invalidates prices | LOW | Cheap guard, high payoff. Emit a clear error, not a wrong answer. Dependency for exactness validation. |
| **IEEE test-feeder fixtures (modified 13-node & 123-node)** | These are *the* reference cases in the thesis (Case A congestion, Case B voltage); reproducing them is the primary validation gate | MEDIUM | Ship as versioned fixtures with expected results (e.g. `v₉[16]=1.0493`, +25% welfare, 28 ADMM iters). Parsing raw IEEE/OpenDSS files is optional (see differentiators). |
| **Device/load parameter tables** (per-house device params, occupancy, PV, inelastic load profiles) | Optimization consumes these as parameters; must be inspectable and reproducible | LOW–MEDIUM | Tabular, seed-driven. Inelastic loads are *parameters*, not decisions (thesis 3.22). |
| **Prosumer device library**: thermostatic (3.2–3.3), programmable/deferrable (3.4–3.5), interruptible/elastic, PV+BESS (3.6–3.9) | These four device classes *are* the demand-side model of the thesis; the transactive scheme is meaningless without them | MEDIUM | Each device = variables + temporal-coupling constraints + a utility/cost term. BESS charge/discharge needs **no binaries** (App. C proof) — parametrize per 3.15–3.20. |
| **Quadratic concave utility / convex cost preference functions** (3.10–3.20) | The welfare objective and the price signal both derive from these; wrong curvature ⇒ non-convex or meaningless duals | LOW–MEDIUM | Coefficients `a,b` from `λ_max,λ_min,λ_med` (3.13–3.20). Must stay convex/concave so `GLB-CVX` stays convex. |
| **Aggregator aggregation** (3.21–3.23): device decisions → nodal net P/Q + summed utility | The optimization and ADMM operate at the *nodal aggregator* level, not per-house | MEDIUM | `p_ag>0` = net consumption. Reactive power via load power factor `φ`. One aggregator per load node. |
| **Convex branch-flow OPF (SOCP + LinDistFlow exactness)** (3.29–3.45) | The core network model. SOC relaxation of `l=(P²+Q²)/v` **plus** the LinDistFlow affine copy (3.43–3.45) that makes the relaxation exact | HIGH | The single most correctness-critical component. Without the exactness constraints the DADP prices are *meaningless* (thesis §2.4). |
| **Social-welfare maximization objective** `GLB-OPT`/`GLB-CVX` (3.38): Σ aggregator utility − λ₀ᵀp₀ | This is the operational problem; everything else feeds it | LOW (given the pieces) | Assembles device utilities + network model + wholesale cost. |
| **Centralized monolithic solve** | The clarity/ground-truth path; ADMM results are validated *against* it on small cases | MEDIUM | First solver target. Also the fastest route to a first correct result. |
| **Open-source solver integration behind an abstraction** (HiGHS LP/MILP, Ipopt NLP, Clarabel/SCS conic-SOCP; Gurobi optional fallback) | Reproducibility for reviewers requires no commercial license; JuMP makes swapping trivial | LOW–MEDIUM | Solver choice must be a config knob, never hard-wired. Conic solver is the load-bearing one. |
| **DADP/DLMP extraction** (dual of nodal active-power balance, 3.31) | The transactive tariff *is* this dual; extracting it correctly is the whole point | MEDIUM | From centralized: constraint dual. From ADMM: converged `λ_j[t]`. The two must agree — a key cross-check. |
| **Relaxation-exactness validation** (check `l_{i,j}·v_i ≈ P²+Q²` at optimum) | If the SOC relaxation is not tight, the solution is physically infeasible and prices are wrong | LOW | Automated post-solve assertion with tolerance. Gate every result on it. |
| **Energy-balance / feasibility residual checks** | Trust: confirm nodal P/Q balances close, voltage/thermal limits respected | LOW | Cheap sanity layer; catches modeling bugs early. |
| **Reproducible, seeded data generation** | "Trustworthy, reproducible results" is the stated Core Value; unseeded random demand ⇒ irreproducible papers | MEDIUM | Markov-chain demand/PV/occupancy synthesis (1-min → hourly aggregation). Seed + pinned `Manifest.toml`. |
| **Result storage / experiment output** (structured, inspectable) | Comparing DADP vs FIT, sweeps, welfare accounting all need persisted, diffable results | LOW–MEDIUM | Plain tabular/JSON/Arrow; no database. Keep results diff-friendly for regression. |
| **Per-model math documentation** (assumptions + equations alongside code) | Stated *hard requirement*; thesis traceability (equation numbers) is mandatory | MEDIUM | Docstrings + literate docs citing thesis eq. numbers. Not optional per PROJECT.md. |

### Differentiators (What sets this apart from the general Julia power stack)

| Feature | Value Proposition | Complexity | Notes / Dependencies |
|---------|-------------------|------------|----------------------|
| **ADMM decomposition that recovers prices as duals** (`AGR-OPT` per node + `DSO-OPT` per hour, 3.46–3.47) | This is the thesis's actual solver *and* the mechanism by which the transactive tariff emerges. PowerModels/PMD do **not** do this | HIGH | Native outer loop; dual update `λ←λ+ρR`. `ρ=1000`, `ε=5e-5`, ~28 iters. Requires: device library, network model, centralized solve (for validation). Optional PCPM variant (App. B). |
| **DLMP decomposition into economic components** (energy / loss / congestion / voltage) | Turns a price number into *insight* — the interpretive payload of the thesis (§4). Rare in general frameworks | MEDIUM–HIGH | Decompose `λ_j` via the branch-flow duals. Depends on exact relaxation + correct dual extraction. High research value. |
| **Swappable power-flow formulation behind one interface** (DC/linear → LinDistFlow → SOCP-BFM), the "abstraction ladder" | Directly mirrors PowerModels' proven central design principle; lets a researcher compare formulations on one problem spec | HIGH | The key architectural differentiator. Same problem/device/objective code runs against any formulation. Enables toy→full progression. |
| **Selectable solve strategy per experiment** (monolithic vs ADMM), same model | Centralized = clarity/ground truth; ADMM = scale + prices-as-duals + matches thesis. Being able to A/B them is a research asset | MEDIUM | Both consume the same assembled model. Cross-validation of the two is itself a headline result. |
| **Welfare accounting split** (social / DSO surplus / prosumer surplus) + **FIT baseline comparison** | The thesis's central quantitative claim (+25% welfare, DSO −$2829→+$439). Reproducing the *decomposition* is a differentiator | MEDIUM | FIT-OPT baseline (3.24–3.28) as an alternative objective. Depends on device library + solve. |
| **Declarative scenario / experiment definition + parameter sweeps** | "Express a scenario and a model variant declaratively" is the Core Value verbatim; enables the thesis's sensitivity studies (battery×1.5, PV×1.5, willingness×1.5) | MEDIUM | Scenario = network × devices × prices × formulation × strategy. Sweep = cartesian/seeded over params. |
| **Extension seams designed-in** (stochastic scenarios, rolling-horizon MPC/RTP, meshed+4Q BESS, Benders/diagonalization planning game) | The four declared PhD research axes; architecture that *precludes* them is a v1 failure even if v1 runs | MEDIUM (as seams) / HIGH (when realized) | Seams only in v1: multi-scenario objective hook, horizon parameter, formulation slot for meshed, coupling-flow interface `z ↔ p_ag`. Do not implement the extensions; do not preclude them. |
| **Convergence diagnostics for ADMM** (residual traces, iteration history, per-node/per-hour) | Debugging distributed solvers is hard; good diagnostics are what make ADMM usable in research | MEDIUM | Primal/dual residual logging, convergence plots data. Depends on ADMM. |
| **Literate experiment notebooks / scripts** (runnable, narrated, reproducing figures) | Reproducibility + thesis/paper figure generation from one source of truth | MEDIUM | Pluto/Literate.jl or plain scripts. Each reproduces a case study end-to-end. |
| **Regression fixtures pinned to reference results** | Guards correctness across refactors; reviewers/collaborators can trust the port matches the theory | MEDIUM | Snapshot IEEE 13/123 outputs (welfare, DLMP, iters, exactness). CI-gated. Depends on fixtures. |
| **Native OpenDSS / IEEE feeder importer** *(optional, lower priority)* | Would let researchers pull arbitrary feeders; PMD proves the value of an OpenDSS parser | HIGH | Deprioritize for v1 — hand-curated modified 13/123 fixtures suffice and are what the thesis uses. Add only if arbitrary-feeder studies become a need. |

### Anti-Features (Attractive but wrong for this research library)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **GUI / interactive dashboard** | "Visualize the network and prices" feels helpful | Enormous maintenance surface, zero research value, distracts from correctness; not what a thesis is graded on | Plotting *scripts* (Makie/Plots) that emit publication figures from stored results |
| **Real-time / hardware-in-the-loop / live market integration** | "Deploy the transactive scheme for real" | Out of scope by charter; introduces I/O, latency, safety concerns orthogonal to the theory | Keep it offline/day-ahead. RTP is a *future MPC extension*, still simulated. |
| **Unbalanced three-phase / multi-conductor modeling in v1** | PowerModelsDistribution does it; "more realistic" | Thesis uses **balanced positive-sequence**; 3-phase multiplies model size and derails the exactness proof and every fixture. Wrong tree to climb first | Balanced single-phase-equivalent BFM in v1. If ever needed, it's a formulation-slot extension — not v1. |
| **MPEC / bilevel / KKT tooling for the operational layer** | The narrative *sounds* leader-follower (DSO sets price, prosumers respond) | The operational model is a **single-level convex program**; reaching for MPEC is a category error that produces a harder, non-convex, wrong model | Convex SOCP + ADMM; prices emerge as duals. Reserve MPEC/Benders strictly for the **planning** layer. |
| **Full Stackelberg–Nash planning implementation in v1** | It's the exciting end-state; "just build it all" | Deferred by charter; depends on a validated operational engine as its subproblem. Building it first = building on sand | v1 ships operational layer + *interfaces* (coupling flow `z`, DLMP↔`π_s` link) that the planning game will plug into. |
| **Line-for-line port of the MATLAB+CVX codebase** | "It already works, just translate it" | Ports the *bugs and idioms*, not the *theory*; forecloses the clean abstraction ladder that is the whole point | Port the **theory** (equation-numbered), idiomatic Julia, validated against the *results* not the code. |
| **Generic multi-energy / gas / heat / transmission-AC coverage** | "Make it a general platform" | Scope explosion; PowerModels/InfrastructureModels already occupy that niche; dilutes thesis focus | Stay a focused transactive-distribution + TSO-DSO-coupling framework. Depth over breadth. |
| **Premature performance optimization** (custom sparse linear algebra, GPU, hand-tuned ADMM in v1) | "Research code should be fast" | Charter says favor clarity/correctness/traceability over premature perf; obscures the math | Lean on JuMP + mature solvers. Optimize only a measured bottleneck, later. |
| **Binary/complementarity modeling of BESS charge-vs-discharge** | "A battery can't charge and discharge at once — add a binary" | App. C *proves* the parametrization prevents simultaneous charge/discharge; a binary needlessly turns a convex QP into a MIP and breaks ADMM's dual pricing | Trust the 3.15–3.20 parametrization; keep it continuous/convex. |
| **Heavyweight results database / experiment-tracking server** | "Track all my runs like MLflow" | Operational overhead, another service to maintain, poor fit for a solo/small-team thesis | Flat, versioned, diff-friendly result files under the repo; seeded reproducibility. |

---

## Feature Dependencies

```
[Radial network data model + per-unit]
    └──enables──> [Radial-topology validation]
    └──enables──> [Convex BFM (SOCP + LinDistFlow exactness)]
                       └──requires──> [Relaxation-exactness validation]
                       └──enables──> [DADP/DLMP extraction]
                                          └──enables──> [DLMP economic decomposition]

[Prosumer device library] ──feeds──> [Aggregator aggregation]
                                          └──feeds──> [Social-welfare objective GLB-OPT/CVX]
[Quadratic utility/cost functions] ──feeds──> [Prosumer device library]
                                          └──must-preserve──> [convexity of GLB-CVX]

[Social-welfare objective] + [Convex BFM] + [Solver abstraction]
    └──solved by──> [Centralized monolithic solve]  (ground truth)
    └──solved by──> [ADMM decomposition]  ──produces──> [DADP as duals]
                          └──requires──> [Convergence diagnostics]
    [Centralized] <──cross-validates──> [ADMM]

[Seeded data generation (Markov)] ──produces──> [Device/load parameter tables]

[IEEE 13/123 fixtures] + [Regression fixtures] ──validate──> [everything]
[FIT baseline] ──benchmarks──> [Welfare accounting split]

[Formulation abstraction (DC→LinDistFlow→SOCP)]
    └──is-the-slot-for──> [meshed-network extension]
[Multi-scenario objective hook] ──is-the-slot-for──> [stochastic extension]
[Horizon parameter] ──is-the-slot-for──> [MPC / rolling-horizon / RTP extension]
[Coupling-flow interface z ↔ p_ag, DLMP ↔ π_s]
    └──is-the-slot-for──> [Stackelberg–Nash planning game (Benders + diagonalization)]
```

### Dependency Notes

- **DLMP extraction requires exact relaxation:** duals are only meaningful when the SOC relaxation is tight; hence exactness validation is upstream of any pricing claim.
- **ADMM requires the centralized solve first (practically):** you validate the distributed prices against the monolithic optimum on small cases before trusting them at scale.
- **Convexity is a cross-cutting invariant:** every utility/cost term and every formulation must keep `GLB-CVX` convex, or ADMM's dual-as-price interpretation collapses. This is why the BESS-binary anti-feature matters.
- **Extension seams are interface commitments, not implementations:** the coupling-flow interface (`p_ag ≈ z_{y,s}`, `λ_j ≈ π_s`) is the single most important seam — it is where the operational engine becomes the planning game's subproblem.
- **Fixtures gate the whole project:** reproducing IEEE 13 (congestion) and 123 (voltage) is both a table-stakes validation and the acceptance test for the operational milestone.

---

## MVP Definition

### Launch With (v1 — the operational transactive layer)

- [ ] **Radial network data model + per-unit + topology validation** — foundation; wrong here ⇒ everything wrong.
- [ ] **Prosumer device library** (thermostatic, programmable, interruptible, PV+BESS) with **quadratic utility/cost** — the demand side of the theory.
- [ ] **Aggregator aggregation** to nodal P/Q + utility — the level the optimization runs at.
- [ ] **Convex BFM: SOCP + LinDistFlow exactness** — the correctness-critical network core.
- [ ] **Social-welfare objective `GLB-CVX`** — the operational problem.
- [ ] **Centralized monolithic solve** via solver abstraction (Clarabel/SCS + Ipopt + HiGHS) — ground-truth path.
- [ ] **ADMM decomposition** with convergence diagnostics — the thesis solver + price mechanism.
- [ ] **DADP/DLMP extraction** (both centralized dual and ADMM), agreeing with each other.
- [ ] **Relaxation-exactness + energy-balance validation** — trust gates.
- [ ] **IEEE 13 & 123 fixtures + seeded Markov data generation** — reproducing the two reference cases *is* the v1 acceptance test.
- [ ] **Per-model math docs + one literate reproduction script per case** — the hard documentation requirement.

### Add After Validation (v1.x)

- [ ] **DLMP economic decomposition** (energy/loss/congestion/voltage) — trigger: once base DLMP validated exact. High interpretive value; natural first "research" output.
- [ ] **FIT baseline + full welfare split** (social/DSO/prosumer) — trigger: reproducing the +25% headline number.
- [ ] **Declarative scenario layer + parameter sweeps** — trigger: when running the thesis sensitivity cases (896 houses, ×1.5 variants) by hand becomes tedious.
- [ ] **Regression-fixture CI** — trigger: first refactor that risks silently changing results.
- [ ] **PCPM ADMM variant** (App. B) — trigger: if base ADMM convergence is finicky.

### Future Consideration (v2+ — the four declared research axes)

- [ ] **Stochastic PV/demand scenarios** — defer: needs a validated deterministic core first; enters via the multi-scenario objective hook.
- [ ] **MPC / rolling-horizon / real-time pricing** — defer: reuses the horizon parameter + repeated solves; only meaningful after day-ahead is solid.
- [ ] **Meshed networks + four-quadrant BESS** — defer: needs a non-radial formulation (BIM/SDP or meshed BFM) in the formulation slot; breaks the radial exactness proof, so it is a genuinely new model.
- [ ] **TSO–DSO Stackelberg–Nash planning game** (Benders + Gauss–Seidel diagonalization, binary-expansion + Lagrangian cuts) — defer: the operational engine is its subproblem; enters via the coupling-flow interface. This is the thesis end-state, deliberately post-v1.

---

## Feature Prioritization Matrix

| Feature | Research Value | Implementation Cost | Priority |
|---------|----------------|---------------------|----------|
| Radial data model + per-unit + topology validation | HIGH | LOW–MEDIUM | P1 |
| Prosumer device library + quadratic utilities | HIGH | MEDIUM | P1 |
| Aggregator aggregation | HIGH | MEDIUM | P1 |
| Convex BFM (SOCP + LinDistFlow exactness) | HIGH | HIGH | P1 |
| Social-welfare objective (GLB-CVX) | HIGH | LOW | P1 |
| Centralized solve + solver abstraction | HIGH | MEDIUM | P1 |
| ADMM decomposition + diagnostics | HIGH | HIGH | P1 |
| DADP/DLMP extraction | HIGH | MEDIUM | P1 |
| Exactness + balance validation | HIGH | LOW | P1 |
| IEEE 13/123 fixtures + seeded data gen | HIGH | MEDIUM | P1 |
| Per-model math docs + literate scripts | HIGH | MEDIUM | P1 |
| Formulation abstraction ladder (DC→LinDistFlow→SOCP) | HIGH | HIGH | P1 (architectural) |
| Extension seams (interfaces only) | HIGH | LOW–MEDIUM | P1 (design), P3 (realize) |
| DLMP economic decomposition | HIGH | MEDIUM–HIGH | P2 |
| FIT baseline + welfare split | HIGH | MEDIUM | P2 |
| Declarative scenarios + sweeps | MEDIUM | MEDIUM | P2 |
| Regression-fixture CI | MEDIUM | MEDIUM | P2 |
| OpenDSS/IEEE feeder importer | MEDIUM | HIGH | P3 |
| Stochastic / MPC / meshed+4Q / planning game | HIGH (later) | HIGH | P3 |

**Priority key:** P1 = required for the v1 operational milestone · P2 = add once core validated · P3 = future research axes / optional.

---

## Competitor Feature Analysis

Reference frameworks in the Julia power ecosystem (not competitors so much as the surrounding stack this project is deliberately *not* duplicating):

| Feature | PowerModels.jl / PowerModelsDistribution.jl (LANL-ANSI) | Sienna (PowerSystems.jl / PowerSimulations.jl, NREL) | Our Approach |
|---------|--------------------------------------------------------|------------------------------------------------------|--------------|
| Formulation abstraction (swap AC/DC/SOC/linear) | **Yes** — this is PMD's central design principle; validates our ladder | Partial (device/formulation templates) | Adopt the same decoupling; scope to DC→LinDistFlow→SOCP-BFM on **radial** networks |
| Branch-flow SOCP + LinDistFlow | **Yes** (SOC-BFM, linear approximations) | Limited distribution focus | Yes, **plus the exactness copy (3.43–3.45)** which general frameworks don't emphasize |
| Unbalanced 3-phase multi-conductor | **Yes** (PMD's whole point) | Transmission-focused | **Deliberately not** — balanced positive-sequence v1 (anti-feature) |
| OpenDSS / IEEE feeder parsing | **Yes** (built-in OpenDSS parser, validated vs OpenDSS) | Various importers | Curated 13/123 fixtures in v1; importer is P3 |
| Prosumer device models (thermostatic/deferrable/BESS) with **utility functions** | No (network-side; loads are parameters) | Device models exist, not transactive-utility framed | **Yes — core differentiator**; utility-based demand response is the thesis's substance |
| Transactive DLMP as ADMM dual + economic decomposition | No | No | **Yes — the headline differentiator** |
| ADMM / distributed pricing loop | No (centralized solves) | No | **Yes** (native outer loop, prices-as-duals) |
| Welfare/surplus accounting + FIT benchmark | No | Production-cost / market simulation (different framing) | **Yes** (social/DSO/prosumer split vs FIT) |
| Stackelberg–Nash planning coupling | No | No | **Designed-for** (interfaces in v1, implementation v2+) |
| GUI / dashboard | No (library) | No (library) | No (anti-feature) — same stance |

**Takeaway:** the general Julia stack already nails *network-formulation abstraction and unbalanced power flow* — so this project should **borrow that architectural pattern** (formulation decoupling) but **not compete on breadth**. Its defensible research value is the combination the others lack: **utility-based prosumer devices + convex radial BFM + ADMM transactive DLMP with economic decomposition + a designed-in path to the TSO–DSO planning game.**

---

## Sources

- Theory (primary, HIGH): `.planning/research/THEORY-thesis.md`, `.planning/research/THEORY-papers.md` (Palacios PhD thesis UNSJ 2022; IET GTD 2019; PSR N1–N2 note) — equation numbers cited inline.
- Project charter: `.planning/PROJECT.md`.
- Ecosystem grounding (HIGH — official/peer-reviewed):
  - [PowerModelsDistribution.jl: An Open-Source Framework for Exploring Distribution Power Flow Formulations (arXiv 2004.10081)](https://arxiv.org/abs/2004.10081) — confirms SOC-BFM/BIM, linear approximations, OpenDSS parser, IEEE 13/34/123 validation, and the "not intended to replicate OpenDSS" scoping stance.
  - [PowerModels.jl: An Open-Source Framework for Exploring Power Flow Formulations (arXiv 1711.01728)](https://arxiv.org/pdf/1711.01728v2) — the formulation/problem-spec decoupling design principle behind the abstraction ladder.
  - [PowerModelsDistribution.jl GitHub (LANL-ANSI)](https://github.com/lanl-ansi/PowerModelsDistribution.jl)
  - [PowerModels.jl GitHub (LANL-ANSI)](https://github.com/lanl-ansi/PowerModels.jl)
  - [IEEE PES Distribution Test Feeders](https://cmte.ieee.org/pes-testfeeders/resources/) — 13/123-node reference feeders.

---
*Feature research for: research-grade TSO–DSO transactive-energy optimization framework (Julia/JuMP)*
*Researched: 2026-07-18*
