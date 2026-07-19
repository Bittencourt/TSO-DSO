# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Overview

This milestone builds the **operational transactive-energy layer** by climbing the abstraction ladder
(rungs 0-5 from `research/ARCHITECTURE.md`): each phase delivers a *runnable, validated end-to-end
solve* at increasing fidelity, and every interface is locked against real math before it is
generalized. We start with plumbing and a toy DC solve (rung 0), establish the residual-seam contract
with a linear branch flow (rung 1), grow the full prosumer device library and social-welfare objective
(rung 2a), then reach the **correctness milestone** — SOCP Convex Branch Flow with the LinDistFlow
exactness copy, validated exact on IEEE 13-node, with the `operational_oracle(z)→(cost,π)` seam in
place (rung 2b). Pricing (DADP/DLMP decomposition, rung 3) sits deliberately between the correctness
milestone and ADMM to de-risk duals early. ADMM decomposition (rung 4) is pure orchestration over the
already-validated builders and must be validated against the centralized ground truth. A cross-cutting
experiment/reproducibility layer and a documentation + regression acceptance gate close the milestone.
The v1 acceptance gate: reproduce IEEE 13-node (congestion) + 123-node (voltage) with **exact
relaxation, recovered DADP, and ADMM matching centralized**. The v2 extension axes
(stochastic / MPC-RTP / meshed+4Q-BESS / Stackelberg-Nash planning) are out of scope here — v1 only
leaves correct seams for them (SEAM-01).

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Plumbing & Solver Abstraction** - Data model, `ModelContext`, `select_optimizer`, toy DC single-node solve (rung 0) (completed 2026-07-18)
- [x] **Phase 2: Linear Branch-Flow Residual Seam** - LinDistFlow + one flexible load, centralized; nodal-balance dual appears (rung 1) (completed 2026-07-18)
- [x] **Phase 3: Prosumer Device Library & Social-Welfare Solve** - All devices + aggregator + `GLB-CVX` on linear flow, centralized (rung 2a) (completed 2026-07-18)
- [x] **Phase 4: Convex Branch-Flow Correctness Milestone** - SOCP + LinDistFlow exactness + IEEE 13 + `operational_oracle` seam (rung 2b) (completed 2026-07-19)
- [x] **Phase 5: Distribution Pricing — DADP & DLMP Decomposition** - Nodal-balance dual prices, four-way decomposition, welfare accounting (rung 3) (completed 2026-07-19)
- [x] **Phase 6: ADMM Decomposition Core** - `AGR-OPT`/`DSO-OPT` + dual ascent, build-once, cross-validated vs centralized (rung 4a) (completed 2026-07-19)
- [x] **Phase 7: ADMM Convergence & Scale** - Primal+dual stopping, adaptive ρ, diagnostics, IEEE 123-node voltage case (rung 4b) (completed 2026-07-19)
- [ ] **Phase 8: Experiment Harness & Reproducibility** - Declarative scenarios, sweeps, bit-for-bit reproducible runs
- [ ] **Phase 9: Documentation & Regression Acceptance Gate** - Literate per-model math docs, pinned regression fixtures, v1 acceptance gate

## Phase Details

### Phase 1: Plumbing & Solver Abstraction
**Goal**: Lock the architectural keystone — pure data model, `ModelContext` + residual registry, solver
abstraction, and the status/per-unit discipline — against real-but-trivial math (a toy DC single-node,
single-period centralized solve) before any complexity is added.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-05, DATA-01, DATA-02, PF-01
**Success Criteria** (what must be TRUE):
  1. The package resolves cleanly from a clean checkout (`Project.toml` + committed `Manifest.toml`, `[compat]` floors) on Julia 1.10 LTS and 1.11.
  2. A toy single-node, single-period DC model builds, solves via `select_optimizer(::ProblemClass)`, and returns an objective — with no model file naming a concrete solver (HiGHS/Clarabel/Ipopt default; Gurobi/Mosek opt-in behind the factory).
  3. Every solve path asserts `termination_status == OPTIMAL` and fails loudly on non-optimal status or hidden constraint slack.
  4. A feeder defined as immutable JuMP-free structs is validated radial (N nodes → N−1 branches, connected, one root); a non-tree feeder raises a clear error.
  5. All electrical and monetary quantities pass magnitude-sanity assertions under one documented per-unit system, converted once at ingestion.
**Plans**: 4 plans
- [x] 01-01-PLAN.md — Package scaffold + committed Manifest/[compat] + Wave 0 failing TestItems harness (INFRA-01)
- [x] 01-02-PLAN.md — Immutable per-unit feeder data model + radial validation + magnitude tripwires (DATA-01, DATA-02, INFRA-05)
- [x] 01-03-PLAN.md — Solver factory (select_optimizer) + weakdep exts + status discipline + ModelContext residual seam (INFRA-02, INFRA-03, PF-01)
- [x] 01-04-PLAN.md — End-to-end toy DC single-node solve through all seams + Literate reproducibility page (INFRA-02, INFRA-03, PF-01)

### Phase 2: Linear Branch-Flow Residual Seam
**Goal**: Establish the residual-seam contract everything else reuses — a swappable linear power-flow
formulation (DC / LinDistFlow) and one flexible device meet only at `Rp/Rq`, and the first
nodal-balance dual appears from a centralized linear solve.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: PF-02, DEV-03
**Success Criteria** (what must be TRUE):
  1. A LinDistFlow (and DC) linear formulation contributes branch/voltage terms into the shared nodal residual with no `if formulation ==` branching (interface-conformance test passes).
  2. An interruptible/elastic load contributes variables, a concave quadratic utility term, and a signed injection into the residual without ever referencing the network.
  3. A centralized solve of the linear model closes the nodal balance and exposes the nodal-balance dual — the first price signal — gated on `OPTIMAL` status.
  4. Swapping DC↔LinDistFlow requires no change to device or assembly code.
**Plans**: 4 plans
- [x] 02-01-PLAN.md — Residual-seam foundation: indexed :Rp/:Rq + add_to_objective! QuadExpr accumulator, Phase-2 include scaffolding (PF-02, DEV-03)
- [x] 02-02-PLAN.md — DC + LinDistFlow linear formulations via dispatched contribute! (PF-02)
- [x] 02-03-PLAN.md — AbstractDevice contract + Interruptible/elastic load, network-agnostic (DEV-03)
- [x] 02-04-PLAN.md — Centralized solve_linear: first nodal-balance dual + DC↔LinDistFlow conformance + analytic 2-bus price (PF-02, DEV-03)

### Phase 3: Prosumer Device Library & Social-Welfare Solve
**Goal**: Deliver the full prosumer device library, aggregator roll-up, and the `GLB-CVX` social-welfare
objective, solved centrally on the linear branch-flow formulation with seeded profiles — a complete
multi-device welfare solve at linear fidelity, before SOCP complexity.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: DEV-01, DEV-02, DEV-04, DEV-05, OPT-01, DATA-04
**Success Criteria** (what must be TRUE):
  1. Thermostatic, deferrable, and PV+battery device models each add correct temporal-coupling constraints and a concave quadratic utility; PV+battery uses **no binaries** and `p_ch·p_dch ≈ 0` holds at the optimum (App. C).
  2. An aggregator rolls its devices into nodal net active/reactive power and total utility; device modules never reference the network directly.
  3. The social-welfare objective (Σ aggregator utility − wholesale/MEM purchase) assembles from device utility terms + the linear power-flow model and solves centrally to a global optimum.
  4. Seeded first-order Markov-chain demand and PV profiles generate reproducibly (same seed → identical profiles) and feed the solve.
**Plans**: 5 plans
- [x] 03-01-PLAN.md — StableRNGs dep + re-resolved manifests (1.10/1.11/1.12) + include-graph stubs + RED @testitem harness + T=24 fixture (DATA-04)
- [x] 03-02-PLAN.md — Seeded first-order Markov profile generator (markov_path + generate_profiles, reproducible) (DATA-04)
- [x] 03-03-PLAN.md — Thermostatic + Deferrable devices (temporal coupling + concave utility, aggregatable-device contract) (DEV-01, DEV-02)
- [x] 03-04-PLAN.md — PV+battery device: SOC/PV-limit, no binaries, numeric p_ch·p_dch<τ (App. C) (DEV-04)
- [x] 03-05-PLAN.md — Aggregator roll-up + GLB-CVX solve_welfare + q_import reactive-root fix + battery complementarity (DEV-05, OPT-01, DEV-04)

### Phase 4: Convex Branch-Flow Correctness Milestone
**Goal**: The "if all else fails, this must work" core — the SOCP Convex Branch Flow formulation *with
the LinDistFlow exactness copy*, all devices, and social welfare, proven **exact** on the modified IEEE
13-node feeder as centralized ground truth, with the `operational_oracle(z)→(cost,π)` seam and
extension stubs in place so the planning layer is additive later.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: PF-03, PF-04, OPT-02, OPT-03, DATA-03, SEAM-01
**Success Criteria** (what must be TRUE):
  1. The SOCP Convex Branch Flow formulation with the LinDistFlow exactness copy (aux `v̂` + affine voltage bounds) solves the full `GLB-CVX` on the modified IEEE 13-node feeder via Clarabel.
  2. An automated invariant asserts relaxation exactness — `max|l·v − (P²+Q²)| < τ` per branch — on both an easy fixture and a high-PV / over-voltage fixture; prices are refused if it fails.
  3. The centralized monolithic solve reproduces the thesis DADP/voltage numbers (e.g. `v₉[16] ≈ 1.0493`) as ground truth, with the nodal active-balance dual available.
  4. `operational_oracle(z) → (cost, π)` returns the frontier coupling dual, and the SEAM-01 extension interfaces exist as stubs: multi-scenario objective hook, rolling-horizon parameter, meshed-formulation slot, and the coupling-flow interface (`z↔p_ag`, `λ_j↔π_s`) with an explicit leader/follower role parameter.
**Plans**: 6 plans
- [x] 04-01-PLAN.md — Foundation: include-graph wiring + problem_class(QP) trait + SOCP→Clarabel confirm + RED @testitem harness + Phase4Fixtures (PF-03, PF-04, OPT-02, OPT-03, DATA-03, SEAM-01)
- [x] 04-02-PLAN.md — ConvexBranchFlow SOCP formulation + LinDistFlow exactness copy (v̂, rotated cone, eqs 3.31-3.45); DC↔LinDistFlow↔SOCP interchange (PF-03)
- [x] 04-03-PLAN.md — Modified IEEE-13 feeder built-in fixture from thesis Table 4.1 (DATA-03)
- [x] 04-04-PLAN.md — operational_oracle(z)→(cost,π) + SEAM-01 extension stubs (OPT-03, SEAM-01)
- [x] 04-05-PLAN.md — PF-04 exactness invariant assert_socp_exact! (price-refusal gate) hooked into welfare_solve + SOCP trait routing + high-PV fixture (PF-04)
- [x] 04-06-PLAN.md — Full GLB-CVX SOCP solve on IEEE-13 + pinned-golden regression + thesis v₉[16] cross-check + cross-solver check (OPT-02, OPT-03)

### Phase 5: Distribution Pricing — DADP & DLMP Decomposition
**Goal**: Extract and validate the day-ahead dynamic price as the dual of the nodal active-power balance,
decompose it into interpretable components, and produce the welfare accounting that reproduces the
headline research result — a small, cheap phase depending only on rung-2 duals.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: PRICE-01, PRICE-02, PRICE-03, PRICE-04
**Success Criteria** (what must be TRUE):
  1. The DADP/DLMP is extracted as the dual of the nodal active-power balance, per node per hour, with the sign verified against a hand-solved 2-bus example.
  2. The DLMP decomposes into energy / loss / congestion / voltage components that sum to the nodal price with correct sign (validated by assertion).
  3. Welfare accounting splits into social / DSO / prosumer surplus with a FIT baseline, reproducing the +25%-social-welfare headline.
  4. Economic-direction checks pass: the price falls below wholesale at PV glut and rises above it at congestion.
**Plans**: 5 plans
- [x] 05-01-PLAN.md — Foundation: register ConvexBranchFlow branch-flow duals (:vdrop/:cpydrop/:cone/:smax) + per-aggregator :agg_net stash + src/pricing include graph + RED harness (PRICE-02, PRICE-03)
- [x] 05-02-PLAN.md — extract_dlmp (per-node/hour DADP, 2-bus sign) + decompose_dlmp (energy/loss/congestion/voltage, sum-to-price assertion) (PRICE-01, PRICE-02)
- [x] 05-03-PLAN.md — fit_baseline: FIT-OPT (3.24-3.28, no battery) + AC-PF counterfactual, the one genuine new solve (PRICE-03)
- [x] 05-04-PLAN.md — economic_direction_checks: DADP < λ₀ at PV glut, > λ₀ at congestion (PRICE-04)
- [x] 05-05-PLAN.md — welfare_accounting: social/DSO/prosumer surplus identity + computed FIT +25% ratio with non-failing thesis cross-check (PRICE-03)

### Phase 6: ADMM Decomposition Core
**Goal**: Add the ADMM solve strategy as pure orchestration over the already-validated rung-2 builders —
per-node `AGR-OPT` + per-hour `DSO-OPT` with dual ascent, built once and re-solved — and prove it
recovers the centralized optimum and duals on every fixture small enough to solve monolithically.
**Mode:** mvp
**Depends on**: Phase 5
**Requirements**: ADMM-01, ADMM-03, ADMM-04
**Success Criteria** (what must be TRUE):
  1. ADMM solves the operational problem via per-node `AGR-OPT` + per-hour `DSO-OPT` subproblems with dual ascent, reusing the exact same device/power-flow builders as the centralized solve.
  2. Subproblems are built once and re-solved via parameter/coefficient updates + warm starts — no per-iteration JuMP model rebuild.
  3. An automated cross-validation test asserts ADMM welfare and duals match the centralized optimum within tolerance on every fixture small enough to solve monolithically.
**Plans**: 4 plans
- [x] 06-01-PLAN.md — Foundation: src/admm include-graph wiring + AdmmResiduals struct + 2-bus dual-sign fixture + RED cross-validation/build-once harness (ADMM-01)
- [x] 06-02-PLAN.md — AGR-OPT per-node QP built once, reusing Aggregator.contribute!; set_objective_coefficient re-solve + App. C battery gate (ADMM-01, ADMM-03)
- [x] 06-03-PLAN.md — DSO-OPT whole-network SOCP built once, reusing ConvexBranchFlow.contribute!; coefficient re-solve + PF-04 exactness on convergence (ADMM-01, ADMM-03)
- [x] 06-04-PLAN.md — solve_admm dual-ascent loop (build-once, fail-loud cap) + cross-validation vs centralized welfare+DADP on 2-bus and IEEE-13 (ADMM-01, ADMM-03, ADMM-04)

### Phase 7: ADMM Convergence & Scale
**Goal**: Harden ADMM convergence and scale it to the IEEE 123-node voltage case — correct primal+dual
stopping, per-unit-normalized adaptive ρ (no hard-coded penalty), and first-class convergence
diagnostics — so the decomposition is trustworthy on the research-target regimes.
**Mode:** mvp
**Depends on**: Phase 6
**Requirements**: ADMM-02, ADMM-05
**Success Criteria** (what must be TRUE):
  1. ADMM stops on **both** primal and dual residuals with per-unit-normalized adaptive ρ (no hard-coded scale-specific penalty); hitting the iteration cap fails loudly rather than returning the last iterate.
  2. Convergence diagnostics (residual traces, iteration count, price convergence) are reported and plottable.
  3. The IEEE 123-node voltage-constrained case converges in ~tens of iterations with `λ_j → DADP` and the exactness invariant holding at the converged point.
**Plans**: 6 plans
- [x] 07-01-PLAN.md — Foundation: CairoMakie weakdep + re-resolved manifests + diagnostics/plot + ieee123 seams wired into TSODSO.jl + extended AdmmResiduals ledger + RED @testitem harness (ADMM-02, ADMM-05)
- [x] 07-02-PLAN.md — IEEE-123 radial per-unit fixture from thesis App. E (relabel + radialize + SparseArrays), validated by construction (ADMM-02)
- [x] 07-03-PLAN.md — Subproblem set_rho! quadratic-coefficient updaters (build-once preserved) + DSO-OPT transit-node relaxation (ADMM-02)
- [x] 07-04-PLAN.md — solve_admm: correct Boyd z-block dual residual + per-unit two-residual stopping + residual-balancing adaptive ρ (clamp/freeze), Phase-6 crossval regression intact (ADMM-02)
- [x] 07-05-PLAN.md — IEEE-123 ADMM convergence run (~tens iters, λ→DADP, PF-04 exact at convergence) + Phase-6 regression + full-suite gate (ADMM-02)
- [x] 07-06-PLAN.md — CairoMakie plotting extension (TSODSOMakieExt, return a Figure) + weakdep isolation test (core solve stays plot-free) (ADMM-05)
**Research flag** (RESOLVED at planning): adaptive-ρ on the SOCP subproblem is handled by the VERIFIED in-place quadratic-coefficient update `set_objective_coefficient(m,x,x,ρ)` (no rebuild) — see 07-RESEARCH.md Pattern 1; no `--research-phase` needed.

### Phase 8: Experiment Harness & Reproducibility
**Goal**: Make experiments first-class — a researcher declares a scenario, runs it end-to-end with either
solve strategy, sweeps parameters, and every run records its inputs/config/environment so results
regenerate bit-for-bit on the open-source solver path.
**Mode:** mvp
**Depends on**: Phase 7
**Requirements**: EXP-01, EXP-02, INFRA-04
**Success Criteria** (what must be TRUE):
  1. A researcher defines a scenario declaratively (feeder + devices + price profile + config) and runs it end-to-end with either the centralized or ADMM solve strategy.
  2. Parameter sweeps over scenarios run and store results in a flat, versioned, diff-friendly format.
  3. Every run records its inputs, config, and environment (seed logged) so results regenerate bit-for-bit on the open-source (Clarabel/HiGHS/Ipopt) solver path.
**Plans**: 4 plans
- [ ] 08-01-PLAN.md — Foundation: DrWatson/CSV/DataFrames hard [deps] + re-resolved manifests (1.10/1.11/1.12) + src/experiments/ include-graph stubs + two-tier storage dirs + RED @testitem harness (EXP-01, EXP-02, INFRA-04)
- [ ] 08-02-PLAN.md — Immutable primitive-selector Scenario (savename-able, validated) + deterministic materialize (sub_seed/build_feeder/build_price/build_population, StableRNGs sub-seeds) (EXP-01, INFRA-04)
- [ ] 08-03-PLAN.md — run_scenario strategy dispatch (:centralized/:admm) + node×T ScenarioResult + the INFRA-04 same-seed bit-for-bit reproducibility gate (EXP-01, INFRA-04)
- [ ] 08-04-PLAN.md — run_sweep (dict_list) + two-tier storage (gitignored JLD2 + diff-friendly sorted CSV) + @tagsave provenance (git commit + VERSION + seed) + @quickactivate scripts (EXP-02, INFRA-04)

### Phase 9: Documentation & Regression Acceptance Gate
**Goal**: Close the milestone with the hard documentation requirement and the v1 acceptance gate — literate
per-model math docs, pinned regression fixtures catching numerical drift, and an end-to-end
reproduction of the IEEE 13 + 123 reference cases with exact relaxation, recovered DADP, and ADMM
matching centralized.
**Mode:** mvp
**Depends on**: Phase 8
**Requirements**: EXP-03, EXP-04
**Success Criteria** (what must be TRUE):
  1. Every model has literate, reproducible documentation stating its math (equation references), assumptions, and validation, built via Documenter + Literate.
  2. Regression fixtures pin reference results (IEEE 13/123, FIT comparison) so numerical drift is caught automatically.
  3. The v1 acceptance gate passes end-to-end: IEEE 13-node congestion + IEEE 123-node voltage reproduced with exact relaxation, recovered DADP, and ADMM matching the centralized optimum.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plumbing & Solver Abstraction | 4/4 | Complete   | 2026-07-18 |
| 2. Linear Branch-Flow Residual Seam | 4/4 | Complete   | 2026-07-18 |
| 3. Prosumer Device Library & Social-Welfare Solve | 5/5 | Complete   | 2026-07-18 |
| 4. Convex Branch-Flow Correctness Milestone | 6/6 | Complete   | 2026-07-19 |
| 5. Distribution Pricing — DADP & DLMP Decomposition | 5/5 | Complete   | 2026-07-19 |
| 6. ADMM Decomposition Core | 4/4 | Complete   | 2026-07-19 |
| 7. ADMM Convergence & Scale | 6/6 | Complete   | 2026-07-19 |
| 8. Experiment Harness & Reproducibility | 0/4 | Not started | - |
| 9. Documentation & Regression Acceptance Gate | 0/TBD | Not started | - |

## Research Flags

Per `research/SUMMARY.md`:
- **Phase 7 (ADMM convergence):** adaptive-ρ / dual-residual tuning on the SOCP subproblem — partial research; flag `--research-phase` at planning.
- **v2 (out of scope this milestone):** Stackelberg-Nash planning (MEDIUM-confidence source, author-flagged leader/follower inconsistency, integer-cut correctness) and meshed + 4Q-BESS (breaks the radial exactness proof) will each need dedicated research when they become milestones. v1 only leaves the SEAM-01 stubs (delivered in Phase 4).
- **Phase 4 note:** quick Clarabel API doc re-check (quadratic-objective attribute names, `Parameter` surface) at phase start — flagged as a gap in SUMMARY.md.
