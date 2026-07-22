# Project Research Summary

**Project:** TSO–DSO Integration Optimization Framework (Julia)
**Domain:** Research-grade mathematical-optimization framework — convex branch-flow transactive-energy pricing (SOCP + ADMM), extensible to a Stackelberg–Nash TSO–DSO planning game (Benders + diagonalization)
**Researched:** 2026-07-18
**Confidence:** HIGH

## Executive Summary

Build a Julia/JuMP research bench that ports the *theory* of Palacios' thesis (not the MATLAB+CVX
code): a single-level, convex, social-welfare-maximizing operational model over a radial branch-flow
distribution network with utility-based prosumer devices, where the dynamic distribution price
(DADP/DLMP) emerges as the **dual of the nodal active-power balance**. The single most important
architectural insight — spanning all four research files — is that this nodal power-balance residual
`R_p[j,t]` (thesis 3.31) is the **universal seam**: it is the device↔network coupling constraint, the
constraint whose dual is the price, the ADMM consensus residual, and (aggregated to the feeder head)
the coupling flow `z` into the future planning game. Organize the entire codebase around that one
object and every swappable component (power-flow formulation, device model, solve strategy) meets
there and nowhere else. Centralized and ADMM solves therefore **share 100% of model-building code** —
they differ only in how the residual is closed (hard constraint vs proximal penalty + dual ascent) —
and the operational solve must be built **oracle-shaped** (accept a fixed/penalized import, return the
frontier coupling dual) from the correctness milestone onward, so the planning layer is additive, not
a rewrite.

The prescribed stack is JuMP for modeling (not Convex.jl — you need per-constraint dual access,
explicit control of the exactness constraints, and cheap re-solves via `Parameter`s), **Clarabel** as
the primary SOCP/QP conic solver (native quadratic objectives, high-accuracy duals — your prices *are*
duals), HiGHS for LP/MILP, Ipopt as an NLP/cross-check fallback, and a one-line `select_optimizer`
factory so no model ever names a solver (Gurobi/Mosek opt-in behind it only). ADMM and Benders are
**hand-rolled outer loops** over JuMP subproblems (the idiomatic and thesis-prescribed approach — no
decomposition mega-framework). Tooling: Documenter + Literate (rich per-model math docs are a hard
requirement), DrWatson (reproducibility backbone from day one), TestItems, Aqua/JET, CairoMakie.

The dominant risk is **silent wrongness** — this library produces plausible-but-wrong numbers rather
than crashes. Four cross-cutting invariants must be automated hard tests, not eyeball checks: (1) SOCP
**exactness** (`l·v ≈ P²+Q²` per branch), which breaks precisely in the high-DER/over-voltage regimes
the research targets and without which every price is meaningless; (2) **ADMM = centralized** welfare
and duals on every fixture small enough to solve monolithically; (3) DLMP components sum to the nodal
price with the correct sign; (4) `termination_status == OPTIMAL` gating with no hidden slacks. The v1
acceptance gate is reproducing the modified IEEE 13-node (congestion) and 123-node (voltage) feeders
with exact relaxation, recovered DADP, and ADMM matching the centralized optimum.

## Key Findings

### Recommended Stack

Model in JuMP throughout; solve the convex operational core with Clarabel (SOCP+QP, accurate duals),
route LP/MILP to HiGHS and any true NLP to Ipopt, all behind a single `select_optimizer(::ProblemClass)`
factory so the open-source-first + Gurobi-fallback constraint is structural. Build the branch-flow
model **from scratch** (PowerModelsDistribution as a data-parsing/cross-validation oracle only, not a
foundation — its generator-centric OPF model fights prosumer utilities, aggregators, and duals-as-prices).
Hand-roll ADMM and Benders. See STACK.md for versions and rationale.

**Core technologies:**
- **JuMP 1.30 + MOI**: algebraic modeling — per-constraint `dual()` (the DADP), native `Parameter`s for cheap re-solve, warm starts, solver-agnostic. The whole `ModelContext` wraps one JuMP `Model`.
- **Clarabel 0.11**: primary conic solver (SOCP `DSO-OPT`/`GLB-CVX`, QP `AGR-OPT`) — native quadratic objectives, high-accuracy primal+dual (essential: prices are duals). IPM accuracy >> first-order.
- **HiGHS 1.24**: LP/MILP — Benders masters, binary-expansion subproblems, DC/LinDistFlow toy rungs. (Cannot do SOCP — route cones away from it.)
- **Ipopt 1.15**: NLP fallback + convex cross-check; never the primary SOCP solver.
- **DrWatson, Documenter+Literate, TestItems, Aqua/JET, CairoMakie**: reproducibility, literate math docs (hard requirement), ladder-friendly testing, publication figures.

### Expected Features

See FEATURES.md. "Users" = the PhD researcher and collaborators; "table stakes" = what a credible,
reproducible research framework in this domain must have.

**Must have (table stakes):**
- Radial network data model + per-unit + radial-topology validation (SOCP exactness only holds on radial trees).
- Prosumer device library (thermostatic, deferrable, interruptible, PV+BESS) with quadratic concave utilities — BESS needs **no binaries** (App. C proof); adding one breaks convexity and ADMM pricing.
- Aggregator aggregation → nodal P/Q + utility; social-welfare objective `GLB-CVX`.
- Convex BFM: SOC relaxation **plus the LinDistFlow exactness copy** (the single most correctness-critical component).
- Centralized monolithic solve (ground truth) **and** ADMM decomposition (thesis solver + price mechanism), selectable, cross-validating each other.
- DADP/DLMP extraction (dual of nodal balance); exactness + energy-balance validation gates.
- IEEE 13/123 fixtures + seeded Markov data generation; per-model math docs + literate reproduction scripts.

**Should have (differentiators vs the general Julia power stack):**
- DLMP economic decomposition (energy/loss/congestion/voltage) — the interpretive payload; the headline research output.
- Swappable power-flow formulation behind one interface (DC → LinDistFlow → SOCP-BFM) — the abstraction ladder.
- Welfare accounting split (social/DSO/prosumer) + FIT baseline (reproduces the +25% headline).
- ADMM convergence diagnostics; declarative scenarios + sweeps; regression fixtures pinned to reference results.
- **Extension seams designed in** (multi-scenario objective hook, horizon parameter, meshed formulation slot, coupling-flow interface `z↔p_ag`, `λ_j↔π_s`) — interfaces only in v1.

**Anti-features (deliberately excluded):** GUI/dashboard, real-time/HIL, unbalanced 3-phase in v1,
MPEC/KKT tooling for the *operational* layer (it is single-level convex — a category error), full
planning implementation in v1, line-for-line MATLAB port, BESS charge/discharge binaries, premature
performance optimization.

### Architecture Approach

See ARCHITECTURE.md. A single package, layered strictly acyclically around the residual registry.
`data/` is pure structs (no JuMP). `powerflow/` and `devices/` are **sibling leaves that never import
each other** — they only touch `ModelContext`; coupling happens one layer up in `aggregate.jl` +
`model/build.jl`. This is the linchpin of independent swappability (a hard requirement). The
PowerModels idiom — formulation-as-type + multiple-dispatch builders — gives zero `if formulation ==`
branching. `solve/` sits above assembly and consumes builder *functions*, so centralized and ADMM
cannot drift apart. `planning/` ships as interfaces + stubs now (the `operational_oracle(z)→(cost,π)`
signature especially).

**Major components:**
1. **Data model** — immutable feeder/device/market structs + fixtures + seeded profile generation (Markov, data-gen only).
2. **Power-flow formulations** (`AbstractPowerFlow`: DC / LinDistFlow / SOCBranchFlow / meshed-stub) — contribute branch terms into `Rp/Rq`.
3. **Device models** (`AbstractDevice`: thermo/deferrable/interruptible/PV-battery) — add injections + utility; never reference the network.
4. **Model assembly (`ModelContext{F}`)** — the shared JuMP model + `Rp[j,t]`/`Rq[j,t]`/`utility` registries + `balance_con`; the only knower of both sides.
5. **Solve strategy** (`Centralized`, `ADMM`) — differ only in how the residual is closed.
6. **Pricing/results, solver abstraction, experiment layer, and the future planning oracle.**

### Critical Pitfalls

See PITFALLS.md. All are silent-correctness bugs; catch each with an automated invariant.

1. **SOCP relaxation inexact and unchecked** — without the LinDistFlow exactness copy the duals are physically meaningless, and exactness breaks exactly under high-DER/reverse-flow/over-voltage (the research target). *Avoid:* implement the exactness constraints as part of the model definition; assert `max|l·v − (P²+Q²)| < τ` after every solve on both an easy and a high-PV fixture.
2. **ADMM converges to the wrong thing** — stopping on the primal residual alone (as the thesis states) gives false convergence; hard-coded `ρ=1000` is scale-tuned to the paper. *Avoid:* stop on **both** primal and dual residuals, adaptive `ρ` on per-unit-normalized data, and make "ADMM welfare/duals = centralized" an automated test.
3. **Unit / per-unit scaling errors** — mixing ¢/kWh vs $/MWh, kW vs MW, or `v=V²` vs `V` silently dwarfs objective terms. *Avoid:* one per-unit system, convert once at ingestion, magnitude-sanity assertions.
4. **Wrong-sign / misidentified DADP** — max-objective dual signs, or reading the reactive/copy constraint. *Avoid:* hand-solved 2-bus sign test; ADMM dual = centralized dual; DLMP components must sum to the nodal price; economic-direction assertions (price < wholesale at PV glut, > at congestion).
5. **Build-once-resolve-many violated + solver mismatch** — rebuilding JuMP models each ADMM/Benders iteration blows up at 150k+ vars; Ipopt-on-SOCP or trusting `ALMOST_OPTIMAL` conic points corrupts duals. *Avoid:* persist models, update coefficients/`Parameter`s, warm-start; route SOCP→Clarabel; gate on `OPTIMAL` + tight duality gap.
6. **(Planning, deferred) LP duals from MIP subproblems + leader/follower ambiguity** — classical Benders cuts are invalid when the reinforcement subproblem is integer (need Lagrangian/integer L-shaped cuts); the PSR note mislabels leader/follower once (distributor = leader — confirm with author); binary-expansion granularity `Δ` silently biases the equilibrium; Gauss–Seidel diagonalization may not converge / equilibria non-unique. *Avoid now:* keep the operational subproblem oracle-swappable and the leader/follower role an explicit parameter.

## Implications for Roadmap

The abstraction ladder (ARCHITECTURE.md rungs 0–5) *is* the phase structure. Each rung is independently
runnable and validated before the next; later rungs add components without editing earlier ones.

### Phase 1 (Rung 0–1): Plumbing + first residual seam
**Rationale:** Lock the architectural keystone (data model, `ModelContext`, residual registry, solver
factory) against real-but-trivial math before generalizing. Low research risk.
**Delivers:** pure `data/` layer + fixtures scaffold, `select_optimizer`, DC/LinDistFlow toy on a single
node with one flexible load, centralized; nodal-balance dual appears and the interface shape is confirmed.
**Addresses:** radial data model + per-unit + topology validation; solver abstraction.
**Avoids:** Pitfall 3 (per-unit convention set here, once), Pitfall 8 (status-check + no-hidden-slack discipline as a coding standard from the first model), Pitfall 4 (routing/status discipline).

### Phase 2 (Rung 2): SOCP + all devices + exactness — the correctness milestone
**Rationale:** This is the "if all else fails, this must work" core; validation-heavy. Build the full
`GLB-CVX` and prove it exact on the reference feeders.
**Delivers:** `SOCBranchFlow` with the LinDistFlow exactness copy, all four device classes + aggregator,
social-welfare objective, IEEE 13-node reproduction, centralized DADP matching thesis numbers.
**Uses:** JuMP + Clarabel; from-scratch BFM.
**Implements:** power-flow + device + aggregator + objective components.
**Avoids:** Pitfall 1 (exactness invariant is the *gating acceptance criterion*), Pitfall 8.
**Critical:** define and stub the `operational_oracle(z)→(cost,π)` signature here so planning is additive later.

### Phase 3 (Rung 3): Pricing — DADP extraction + DLMP decomposition
**Rationale:** Small, cheap phase; depends only on rung-2 duals; de-risks the pricing story.
**Delivers:** DADP extraction, DLMP decomposition (energy/loss/congestion/voltage) matching Case A/B.
**Avoids:** Pitfall 7 (sign, component-sum, economic-direction assertions).

### Phase 4 (Rung 4): ADMM decomposition
**Rationale:** Pure orchestration over already-validated rung-2 builders; the scale/decomposition and
native-price-recovery phase. Requires the centralized solve to exist first as ground truth.
**Delivers:** `AGR-OPT`/node + `DSO-OPT`/hour + dual-ascent loop + diagnostics; IEEE 123-node voltage case;
ADMM optimum ≈ centralized; `λ_j → DADP` in ~28 iters.
**Uses:** hand-rolled loop over persisted JuMP `Parameter` subproblems; Clarabel.
**Avoids:** Pitfall 2 (primal+dual stopping, adaptive `ρ`), Pitfall 5 (build-once, warm-start).

### Phase 5 (Rung 5): Extensions — independent, research-priority-scheduled
**Rationale:** Each is additive thanks to the seams; mutually independent. Deferred by charter.
**Delivers (any of):** stochastic scenarios (`Scenario` axis + scenario-decomp strategy) · MPC/RTP
(rolling `Horizon` + re-solve) · meshed + 4Q-BESS (new formulation, breaks radial exactness proof) ·
**Stackelberg–Nash planning game** (Benders + Gauss–Seidel diagonalization, binary-expansion + Lagrangian
cuts) via `operational_oracle`.
**Avoids:** Pitfalls 6, 9, 10 (planning cut validity, granularity, diagonalization convergence, roles).

### Phase Ordering Rationale
- **Dependencies flow strictly upward** the abstraction ladder; interfaces are locked against real math before generalizing (avoids the over-engineering anti-pattern).
- **Centralized must precede ADMM** so the monolithic solve is the ground truth ADMM is validated against (Pitfalls 2, 7).
- **Pricing (rung 3) is deliberately small** and sits between the correctness milestone and ADMM to de-risk duals early.
- **The oracle shape must exist by rung 2**, so the largest future phase (planning) is additive, not a refactor — the single most important forward-looking dependency.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 5 – Planning (Stackelberg–Nash):** MEDIUM-confidence source (single PSR note with a flagged leader/follower inconsistency); integer-subproblem cut correctness (Lagrangian/integer L-shaped), binary-expansion granularity, and diagonalization convergence all need dedicated research + author confirmation. Flag `--research-phase`.
- **Phase 5 – Meshed + 4Q-BESS:** genuinely new formulation that breaks the radial exactness proof — needs its own exactness/relaxation research.
- **Phase 4 – ADMM (partial):** adaptive-`ρ` / dual-residual tuning on the SOCP subproblem is finickier than the QP-only ADMM literature; worth a focused look, though the pattern is well understood.

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 1 – Plumbing:** established JuMP/DrWatson/package-scaffold patterns.
- **Phase 2 – SOCP core** and **Phase 3 – Pricing:** fully specified by the thesis with equation numbers; the work is careful implementation + validation, not discovery.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions verified against the live Julia General registry (2026-07-18); ecosystem-fit judgments MEDIUM-HIGH. |
| Features | HIGH | Grounded in equation-level theory extraction + PowerModels/PMD/Sienna as reference frameworks. |
| Architecture | HIGH (op) / MEDIUM (planning) | Julia/JuMP/PowerModels idioms verified; planning-layer coupling MEDIUM (author-flagged inconsistencies). |
| Pitfalls | HIGH (op) / MEDIUM (planning) | Optimization math + solver behavior verified vs source + docs; planning cut-correctness rests on a single primary source + standard L-shaped literature. |

**Overall confidence:** HIGH for the v1 operational layer (the roadmap's actual scope); MEDIUM for the
deferred planning layer (which v1 only needs to leave a correct seam for).

### Gaps to Address
- **Leader/follower direction in the planning game** — PSR note inconsistent once; distributor = leader is the consistent reading. *Handle:* encode role as an explicit parameter now; confirm with author before Phase 5.
- **Clarabel API specifics** (quadratic-objective attribute names, `Parameter` surface, `direct_model` support) — not re-verified live this session. *Handle:* quick doc re-check at the start of Phase 2.
- **ADMM `ρ` tuning for the SOCP subproblem** — thesis `ρ=1000` is scale-specific. *Handle:* implement per-unit normalization + adaptive `ρ` in Phase 4; do not hard-code.
- **Binary-expansion granularity `Δ`** — silent equilibrium bias. *Handle:* treat as a convergence parameter with a sensitivity sweep in Phase 5.

## Sources

### Primary (HIGH confidence)
- `.planning/research/THEORY-thesis.md` — operational formulation (eq. 3.2–3.47), ADMM split, DADP-as-dual, LinDistFlow exactness, no-binaries battery proof, IEEE 13/123 validation numbers.
- `.planning/research/THEORY-papers.md` — IET GTD 2019 (operational, published); PSR N1–N2 note (planning: Benders eq. 2/4, diagonalization, binary expansion + Lagrangian cuts); two-layer composition.
- `.planning/research/STACK.md` — Julia General registry versions (2026-07-18); JuMP-vs-Convex, Clarabel-as-default, from-scratch-vs-PMD, hand-rolled decomposition.
- `.planning/research/ARCHITECTURE.md` — residual-seam design; PowerModels formulation-as-type idiom; rung 0–5 build order.
- `.planning/research/FEATURES.md` — table stakes / differentiators / anti-features; MVP + prioritization.
- `.planning/research/PITFALLS.md` — 10 silent-correctness pitfalls; pitfall-to-phase mapping; "looks done but isn't" checklist.
- `.planning/PROJECT.md` — charter, constraints, key decisions, extension axes.

### Secondary (MEDIUM confidence)
- PowerModels.jl / PowerModelsDistribution.jl docs + papers (arXiv 1711.01728, 2004.10081) — formulation-abstraction idiom, SOC-BFM reference, OpenDSS parser.
- Farivar–Low (2013), Gan–Li–Topcu–Low — SOCP branch-flow exactness conditions (fail under reverse flow / binding upper voltage).
- Boyd et al. (2011) ADMM §3.3–3.4 — primal+dual residual stopping, adaptive `ρ`.

### Tertiary (LOW confidence)
- Zou–Ahmed–Sun (SDDiP 2019), Bansal–Küçükyavuz (2025) — integer L-shaped / Lagrangian cuts for MIP Benders subproblems (planning layer, single project source + standard literature).

---
*Research completed: 2026-07-18*
*Ready for roadmap: yes*
