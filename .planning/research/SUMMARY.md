# Project Research Summary

**Project:** TSO-DSO Integration Optimization Framework — Milestone v3.0 "Research Extension Rungs"
**Domain:** Brownfield extension of a validated Julia/JuMP power-systems optimization research bench (convex branch-flow OPF + transactive pricing + Stackelberg-Nash planning) with five new research axes
**Researched:** 2026-07-26
**Confidence:** HIGH (architecture, pitfalls — grounded directly in this repo's code) / MEDIUM-HIGH (stack — live registry + GitHub verification, but architectural "no new package" calls reasoned by analogy) / MEDIUM-HIGH (features — canonical literature verified, some single-source)

## Executive Summary

v3.0 is not a new product but five independent "research extension rungs" bolted onto an already-shipped, validated operational (ADMM/SOCP) and planning (Benders/Nash) core. The unifying finding across all four research files is that **this milestone is almost entirely new code on the existing solver factory and orchestration idioms, not a new stack or a new architecture**. Four of five axes (overvoltage relaxation, MPC/rolling-horizon, stochastic scenarios, 4Q-BESS) need zero new Julia packages — Clarabel already exposes the PSD cone for any SDP-tightening need, and the project's own build-once/`Parameter`-re-solve idiom (proven in ADMM and Benders) is the correct chassis for MPC windows and stochastic subproblems alike. InfiniteOpt.jl, StochasticPrograms.jl, Juniper/Pavito, and BranchFlowModel.jl were all evaluated and explicitly rejected — mostly for the same "hides the per-constraint dual" reason that ruled out Convex.jl in the original stack decision, since DADPs-as-duals is the project's core deliverable. Only axis 5 (integer investment expansion) is structurally heavy: it introduces a genuinely new master-problem class (MILP) and a weaker cut theory (Laporte-Louveaux integer L-shaped), the highest-complexity and highest-risk piece of the milestone.

The recommended approach, synthesized from the architecture and feature research, is additive orchestration: every axis should ship as a new sibling module/type/builder that calls the existing, byte-for-byte-unmodified `contribute!`/`solve_welfare`/`solve_admm`/Benders machinery, exactly the precedent set by every prior milestone (ADMM Phase 6, planning Phase 10-14). The two axes that touch shared, schema-fragile machinery — Scenario.jl (axes 2 & 3) and the SOCP exactness/relaxation gate (axes 1 & 4) — should be sequenced deliberately so the first mover establishes a reusable pattern (a non-radial exactness certificate; a `Scenario` schema convention) that the second reuses rather than re-derives independently.

The dominant risk across all five axes, repeated with textbook regularity in the pitfalls research, is **certificate/gate laundering**: reusing an existing tuned tolerance, guard, or convergence check for a genuinely different mathematical regime instead of deriving a new one — this is called out explicitly for the overvoltage relaxation (Pitfall 1), the meshed angle-consistency gap (Pitfall 14), the 4Q-BESS complementarity proof (Pitfall 16), the two-block ADMM stopping rule (Pitfall 17), and the PVAL-04 no-binaries guard scoping (Pitfall 22). Mitigation is consistent everywhere: every new capability needs its own, independently-derived and independently-named certificate/gate, cross-validated against the existing AC-OPF oracle or brute-force enumeration, never against a loosened copy of an existing gate. Axis 5 additionally needs a small-instance validation oracle check (BilevelJuMP's KKT modes may not extend to integer variables — a fallback to brute-force enumeration is the documented Plan B).

## Key Findings

### Recommended Stack

No `Project.toml` changes are recommended for v3.0 — this is a pure additive-code milestone on the existing three-solver factory (Clarabel/HiGHS/Ipopt, Gurobi/Mosek behind weakdeps). The single most load-bearing new fact this research pass surfaced is that **Clarabel already natively supports the PSD cone** (`PSDTriangleConeT` with chordal decomposition), which forecloses any need for a dedicated SDP solver even if overvoltage-tightening or meshed-network work eventually wants an SDP-style relaxation.

**Core technologies (all unchanged, confirmed still-current 2026-07-26):**
- **Clarabel 0.11.1** — conic backend for overvoltage-tightened SOCP, meshed bus-injection SOCP, 4Q-BESS's reactive capability cone, and any future PSD-tightened relaxation — no new solver package needed for any of these.
- **HiGHS 1.24.1** — Benders master with binary-expansion integer investment variables (axis 5); already a full LP/MILP solver, so no MINLP solver (Juniper/Pavito) is needed since Benders keeps integers confined to the master.
- **Ipopt 1.15.0** — unchanged nonconvex AC-OPF oracle, reused as the correctness backstop for overvoltage-tightened relaxations (not itself the pricing formulation — local KKT duals are not certified global prices).
- **JuMP 1.30.1** — `Parameter`s for rolling-horizon state and scenario-indexed variables; the same idiom that already powers ADMM and Benders re-solves.

**Evaluated and explicitly rejected (not maintenance failures, mostly architectural):** InfiniteOpt.jl (dual-access indirection through its transcription layer — same reason Convex.jl was rejected originally), StochasticPrograms.jl (dead upstream since 2022), Juniper.jl/Pavito.jl (solve monolithic MINLP; Benders avoids ever forming one), BranchFlowModel.jl and PowerModels.jl as runtime/test deps (niche or "more overriding than building," same argument that rejected PowerModelsDistribution.jl originally — read as literature reference only).

### Expected Features

Each axis's "feature" is a research capability (a formulation + a validation certificate), not a UI feature. The literature converges on a clear, right-sized "minimal validated rung" per axis, distinct from deeper differentiators that should be explicitly deferred.

**Must have (table stakes) per axis:**
- **Axis 1 (overvoltage):** restriction/feasible-set-shrink (Gan-Low style) as the primary mechanism, certified against the existing AC-oracle (`assert_ac_exact!`) on the known EXACT-04 high-PV scenario.
- **Axis 2 (MPC):** deterministic receding-horizon re-solve loop, hard terminal-SOC constraint, closed-loop-vs-open-loop (perfect-foresight) benchmark.
- **Axis 3 (stochastic):** small fixed seeded scenario set (3-5) via the existing Markov generator, extensive-form solve, per-scenario DADP as primary output with probability-weighted expectation as a derived summary, one out-of-sample check.
- **Axis 4 (meshed + 4Q-BESS):** plain SOCP meshed relaxation + Gan/Low angle-recoverability a-posteriori check as the validity gate; 4Q-BESS apparent-power cone with `q_bess` wired into the existing v2.1 reactive-dual path.
- **Axis 5 (integer investment):** binary-expansion investment (per the PSR note) + Laporte-Louveaux integer optimality cuts on the existing `BendersMaster`; PVAL-04 guard narrowed (not deleted).

**Should have (differentiators, natural v3.1+ follow-ons):** QC/convex-hull/SDP tightening for meshed exactness; phase-shifter meshed convexification; formal scenario-reduction algorithms (fast-forward/k-means); economic-MPC terminal value functions.

**Defer/anti-features:** full economic-MPC terminal value function or robust/tube-MPC (overkill for a minimal rung); distributionally-robust/chance-constrained stochastic reformulations; a literal IEEE 1547 Volt-VAR droop-curve controller (wrong framing for an optimization-first project — the optimal `q_bess(v)` relationship already subsumes it); full branch-and-Benders-cut/lazy-constraint MILP integration (explicitly declined project-wide per CLAUDE.md's anti-mega-framework stance).

### Architecture Approach

The existing codebase is a single-ownership include graph (`experiments` → `admm`/`planning` → `models` → `pricing`/`devices`/`powerflow` → `core`/`data`) with one dominant, already-proven convention: **additive orchestration over unmodified builders**. Every prior layered feature (ADMM, planning) was built as a new sibling module reusing `contribute!`/`solve_welfare` verbatim rather than editing the validated builder it reuses, and "build-once + `Parameter`-pin + re-solve" is already the house style for every outer loop (`AgrOpt`/`DsoOpt`, `PlanningOracle`, `FollowerLP`, `SharedTransmission`). New axes should default to the same pattern; unfilled extension points must fail loudly (`ArgumentError`), never silently no-op.

**Major components/integration points per axis:**
1. **Axis 1** — a new `AbstractPowerFlow` sibling (e.g. `OvervoltageBranchFlow`) plus a companion, separately-derived exactness certificate beside (not inside) `models/exactness.jl`; `ConvexBranchFlow.jl` stays untouched as the baseline.
2. **Axis 2** — a new `src/mpc/` `RollingWindowOracle` (mirrors `PlanningOracle`'s shape) plus a targeted, minimal, byte-identical-default `Parameter`-ization of `PVBattery.jl`/`Thermostatic.jl`'s initial-condition constraint — the SEAM-01 `horizon_state` stub is expected to stay inert, matching the precedent that the `z`-stub was never filled either.
3. **Axis 3** — a new `src/stochastic/extensive_form.jl` builder calling `contribute!` once per scenario into one shared `ModelContext` — the `objective_hook` stub is architecturally insufficient for a genuine extensive form (needs shared first-stage variables, not post-hoc composition), so expect a new sibling builder here too.
4. **Axis 4** — split into two independent sub-problems: (a) meshed topology needs a new parallel `MeshedFeeder` struct (Feeder's inner constructor cannot be relaxed) plus a genuinely new non-radial branch-flow formulation; (b) 4Q-BESS is a smaller, independent lift — a new `AbstractDevice` + an additive `q_inject` accumulator in `Aggregator.contribute!` + promoting the existing one-shot `qag_dso` dual to a live μ-ascent step in `solve_admm.jl`.
5. **Axis 5** — extends `planning/master.jl`'s `BendersMaster` with binary/integer variables and a new `add_integer_cut!` sibling function; the PVAL-04 no-binaries test registry must be split (a new, separate positive-check entry for the lifted builder), never loosened globally.

**Shared cross-cutting risk:** `experiments/Scenario.jl` is a schema-fragile, all-fields-positional struct whose `savename`/provenance dict changes shape whenever a field is added — axes 2 and 3 both need new fields and should be done together, in one reviewed diff, to halve the review surface on this file.

### Critical Pitfalls

1. **Certificate/gate laundering (Pitfalls 1, 14, 16, 17, 22)** — reusing an existing tuned tolerance, guard, or convergence check for a genuinely new regime (overvoltage relaxation, meshed angle-consistency, 4Q-BESS complementarity, two-block ADMM stopping, PVAL-04 scoping) instead of deriving a new one. Avoid by requiring a new, separately-named, independently-derived certificate/gate for every new formulation, cross-validated against the AC-OPF oracle or brute-force enumeration — never against a loosened copy of an existing gate.
2. **Rebuild-in-loop anti-pattern (Pitfall 8, and the shared Performance Traps table)** — wiring `horizon_state`/stochastic subproblems by rebuilding the JuMP model each iteration instead of `Parameter`-threading. Avoid by extending the existing build-once/`Parameter` idiom (already proven for ADMM/Benders) rather than calling `solve_welfare` fresh inside a per-window/per-scenario loop.
3. **Structural gap mistaken for a tunable knife-edge (Pitfall 15)** — treating the meshed SOC-relaxation gap like the v2.1 EXACT-04 knife-edge (sweep and fix) when meshed non-exactness has no equivalent proof and may be genuinely structural. Avoid by checking the literature first; the honest deliverable may be a reported structural gap with a validity boundary, not a fixed/exact relaxation.
4. **Silent partial wiring of shared seams (Pitfall 13, 18)** — filling a stub (`objective_hook`, `assert_radial`, `reactive_consensus`) in only one of its consumers, or loosening a shared invariant globally instead of adding a new, parallel, scoped path. Avoid by enumerating every consumer explicitly and failing loudly on any left unwired; add new types/kwargs rather than mutating shared invariants.
5. **Weaker convergence theory understated (Pitfalls 19, 20, 23)** — integer L-shaped cuts are structurally weaker than continuous Benders cuts and standard optimality-cut construction can be invalid once the recourse response to `z` is discontinuous; BilevelJuMP's KKT validation oracle may not extend to integer variables. Avoid by re-measuring iteration counts before inheriting `max_iter=100`, and falling back to brute-force enumeration for small-instance validation if BilevelJuMP's modes don't apply.

## Implications for Roadmap

Based on combined research (architecture's dependency-driven build order + pitfalls' sequencing flags + features' MVP scoping), the suggested phase structure follows the architecture research's explicit build-order recommendation, which resolves risk-sharing between axis 1/4a and schema-sharing between axis 2/3:

### Phase 1: 4Q-BESS + Live Reactive Dual-Ascent (Axis 4b)
**Rationale:** No dependency on anything else in the milestone; reuses the v2.1 `reactive_consensus`/`qag_dso` scaffolding almost as-is (promote one-shot to live ascent) plus one new additive device file. Lowest risk, fastest to ship, and establishes the "new device + widened Aggregator contract" pattern that axis 2's device work can reference.
**Delivers:** `FourQuadBESS` device with apparent-power cone; live μ-dual-ascent in `solve_admm.jl`; re-derived/reinstated complementarity check for the P-Q coupled feasible region.
**Addresses:** Axis 4's 4Q-BESS table stakes from FEATURES.md.
**Avoids:** Pitfall 16 (P-Q complementarity gap) and Pitfall 17 (joint two-block stopping rule) — both require re-derivation, not inheritance.

### Phase 2: Overvoltage-Capable Relaxation (Axis 1)
**Rationale:** Independent of the Scenario-schema work; produces a reusable "non-radial exactness certificate" pattern that axis 4a (meshed) should reuse rather than re-derive — sequence before axis 4a for that reason.
**Delivers:** New `AbstractPowerFlow` sibling with restriction/feasible-set-shrink tightening; new, separately-derived exactness certificate; documented throw-vs-report gate-polarity decision.
**Uses:** Clarabel (existing), `ACPowerFlow`/`assert_ac_exact!` as the certifying peer (existing).
**Implements:** New formulation file beside `ConvexBranchFlow.jl`/`models/exactness.jl`, both left untouched.
**Avoids:** Pitfall 1 (tolerance laundering), Pitfall 2 (single-local-solution AC pricing), Pitfall 3 (penalty contaminating the DADP dual), Pitfall 4 (default-path regression / gate-polarity).

### Phase 3: MPC/Rolling-Horizon + Stochastic Uncertainty (Axes 2 + 3, combined)
**Rationale:** Both axes require the identical three-touch-point `Scenario.jl` schema extension (fields + positional constructor + validation) — doing them together means one reviewed diff to the schema-fragile file instead of two, and lets axis 3 reuse axis 2's `Parameter`-pinned window-oracle convention directly if the extensive form is decomposed.
**Delivers:** `PVBattery`/`Thermostatic` `Parameter`-ized initial conditions; `RollingWindowOracle` + rolling-horizon outer loop with terminal-SOC constraint and closed-loop-vs-day-ahead benchmark; extensive-form stochastic builder with per-scenario DADP semantics and out-of-sample validation; new `Scenario` fields for both axes added together.
**Addresses:** Axis 2 and Axis 3 table stakes from FEATURES.md.
**Avoids:** Pitfall 5 (terminal-SOC myopia and the T-window-scoped no-binaries re-check), Pitfall 6/7 (unfair MPC-vs-day-ahead benchmark framing, price-discontinuity misattribution), Pitfall 8/9 (rebuild-in-loop, overvoltage-interaction with no defined fallback — sequence axis 1 before this phase for that reason too), Pitfall 10 (per-scenario dual scaling), Pitfall 11 (Clarabel/SCS scenario-count ceiling), Pitfall 12 (fragile single-seed golden), Pitfall 13 (Scenario/savename collision, objective_hook partial wiring).

### Phase 4: Meshed Networks (Axis 4a)
**Rationale:** Sequenced after axis 1 (reuses its relaxation-certificate pattern) and after axis 4b ships (so the 4Q-BESS device already exists for a meshed+4Q-BESS combined validation rung). Highest architecture-plus-math risk in the milestone — schedule so its research/validation overrun does not block the other axes.
**Delivers:** New parallel `MeshedFeeder` struct (with `assert_connected`, not `assert_radial`); new non-radial branch-flow SOCP formulation with an explicit angle-consistency/loop check as the validity gate.
**Implements:** `data/MeshedFeeder.jl`, a new `MeshedFlow <: AbstractPowerFlow` (the SEAM-01-anticipated model-layer swap), leaving `Feeder.jl`/`topology.jl`/`ConvexBranchFlow.jl` untouched.
**Avoids:** Pitfall 14 (missing loop/angle constraint — the most dangerous silent failure mode in the milestone, since the existing per-branch gate would not catch it), Pitfall 15 (structural gap mistaken for tunable knife-edge).

### Phase 5: Discrete/Integer Investment Expansion (Axis 5)
**Rationale:** Fully independent of axes 1-4 (touches only `planning/`) — can in principle be parallelized against any of them from a code-conflict standpoint, but is ordered last because it is flagged as the single highest algorithmic-risk item in the milestone (integer-cut correctness), giving the most time to resolve cut-correctness concerns and keeping the earlier, lower-risk axes' validated rungs unblocked.
**Delivers:** Binary-expansion investment variables in `BendersMaster`; Laporte-Louveaux integer optimality cuts (`add_integer_cut!`); scoped, non-global PVAL-04 guard lift (new registry entry, shared mechanism untouched); small-instance validation against brute-force enumeration (BilevelJuMP mode-compatibility checked first, not assumed).
**Avoids:** Pitfall 19 (invalid standard cuts if the subproblem becomes discontinuous in `z`), Pitfall 20 (inherited `max_iter`/checkpoint cadence understating real cost), Pitfall 21 (HiGHS lazy-constraint/callback mixing with the external-loop design — explicitly deferred), Pitfall 22 (PVAL-04 guard loosened globally instead of scoped), Pitfall 23 (BilevelJuMP validation assumed to extend to integers without checking).

### Phase Ordering Rationale

- **Axis 4b before axis 1/4a:** lowest risk, ships fastest, and establishes the device-extension pattern the rest of the milestone can reference — a low-risk warm-up that de-risks nothing structurally but builds team/pattern confidence.
- **Axis 1 before axis 4a:** both touch the SOCP relaxation/exactness-certification machinery (flagged as an explicit interdependency in PROJECT.md); axis 1 produces a reusable non-radial certificate pattern axis 4a should reuse rather than re-derive independently — avoids inventing two divergent certification strategies.
- **Axes 2 and 3 together:** both require the identical `Scenario.jl` three-touch-point schema extension; combining halves the review surface on the single most schema-fragile file in the codebase.
- **Axis 1 before axis 2/3 (not just before axis 4a):** MPC rolling windows can legitimately drift into the same high-PV overvoltage regime axis 1 addresses, and PROJECT.md's interdependency note doesn't currently extend to MPC — resolving axis 1 first means the rolling-horizon loop has a defined fallback when a window hits the exactness gate mid-simulation, rather than an undefined catch-and-continue.
- **Axis 5 last:** structurally independent of axes 1-4 (touches only the planning layer), but carries the highest algorithmic risk (integer-cut correctness, weaker convergence theory) — ordering it last means the other four validated rungs are not blocked waiting on the riskiest piece.

### Research Flags

Needs deeper research during planning (`--research-phase`):
- **Phase 2 (Overvoltage relaxation):** the actual convexification mechanism (tightened SOC vs. McCormick valid inequalities vs. PSD-style tightening) is unresolved model-math, not an architecture question — flagged explicitly in ARCHITECTURE.md as needing its own theory research pass before a plan is written.
- **Phase 4 (Meshed networks):** the non-radial branch-flow formulation (signed incidence over a cycle basis, or bus-injection/line-flow with loop constraints) is new model-math with the same "needs its own research pass" flag; also carries literature-check risk on whether meshed SOC relaxations are expected to be structurally inexact (Pitfall 15).
- **Phase 5 (Integer investment):** integer L-shaped cut derivation and BilevelJuMP mode-compatibility for integer variables are both open, project-flagged algorithmic-correctness concerns (CLAUDE.md itself names "integer-cut correctness" as an open concern) — the highest-complexity axis in the milestone.

Phases with standard, well-documented patterns (can skip a dedicated research-phase):
- **Phase 1 (4Q-BESS):** apparent-power capability cone and reactive dual-ascent are both direct, well-precedented extensions of existing machinery (the SOC idiom already used for branch limits; the existing λ-ascent pattern) — the only genuinely new derivation needed is the P-Q complementarity re-proof, which is a focused, scoped task, not open-ended research.
- **Phase 3 (MPC/stochastic):** the re-solve mechanism (`Parameter` + `set_parameter_value`) is already verified and documented in-repo ("RESEARCH Pattern 6, verified"); the extensive-form scenario pattern is a textbook two-stage stochastic program with no open model-math questions — the work here is orchestration and schema plumbing, not novel formulation research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH on versions/maintenance activity (live registry + GitHub API verification, 2026-07-26); MEDIUM-HIGH on "no new package" architectural calls (reasoned by re-applying documented precedents, not independently re-litigated per axis) |
| Features | MEDIUM-HIGH (canonical papers — Farivar & Low, Gan/Li/Topcu/Low, Laporte & Louveaux — verified and cross-checked across multiple sources; some axis-specific claims, e.g. convex-hull relaxation and BESS capability-curve sources, rest on a single source) |
| Architecture | HIGH (every claim grounded in direct code reads with file:line citations; forward-looking model-math choices for axes 1/4/5 explicitly flagged as needing a dedicated research pass, not claimed as settled) |
| Pitfalls | MEDIUM-HIGH (codebase-specific integration pitfalls are HIGH confidence, read directly from code and the project's own retrospective; general decomposition/optimization theory pitfalls — integer L-shaped weakness, meshed non-exactness, two-block ADMM — are MEDIUM, standard literature results not independently re-verified against a specific paper this session) |

**Overall confidence:** HIGH on architecture/integration mechanics and stack decisions; MEDIUM-HIGH on domain feature/pitfall theory. The milestone's biggest genuine unknowns are model-math, not tooling or architecture — this is explicitly and consistently flagged across all four research files for axes 1, 4a, and 5.

### Gaps to Address

- **Axis 1's exact convexification mechanism** (restriction vs. valid inequalities vs. PSD tightening) is not chosen — flag Phase 2 for a dedicated model-math research pass before planning constraints.
- **Axis 4a's non-radial formulation** (cycle-basis signed incidence vs. bus-injection/line-flow with loop constraints) is not chosen — flag Phase 4 for the same reason; also unresolved whether the meshed test fixture will show a structural gap requiring an "honest gap" deliverable instead of an exact relaxation.
- **Axis 5's cut theory** — whether standard Benders optimality cuts remain valid at the chosen binary-expansion granularity, and whether BilevelJuMP's KKT/SOS1/Fortuny-Amat modes support any mixed-integer follower at all — are both open questions the research explicitly could not resolve without implementation-time verification (check HiGHS/BilevelJuMP docs directly at Phase 5 start).
- **Scenario-count ceiling for Clarabel on the stochastic extensive form (Axis 3)** — no empirical measurement exists yet; must be established on IEEE-13/123 fixtures before scaling scenario count, per Pitfall 11.
- **PROJECT.md's overvoltage/meshed interdependency note does not yet mention MPC** — Pitfall 9 flags that a rolling-horizon window can also drift into the same exactness-gate territory; the roadmap should extend the documented interdependency to include Phase 3 (MPC) alongside Phase 2/4.

## Sources

### Primary (HIGH confidence)
- Direct code reads across the repository (file:line citations in ARCHITECTURE.md and PITFALLS.md): `src/models/oracle.jl`, `src/models/exactness.jl`, `src/models/welfare_solve.jl`, `src/admm/solve_admm.jl`, `src/admm/DsoOpt.jl`, `src/devices/PVBattery.jl`, `src/devices/Aggregator.jl`, `src/devices/AbstractDevice.jl`, `src/planning/benders.jl`, `src/planning/master.jl`, `src/planning/subproblem.jl`, `src/planning/follower.jl`, `src/planning/coupling.jl`, `src/data/Feeder.jl`, `src/data/topology.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/powerflow/ACPowerFlow.jl`, `src/experiments/Scenario.jl`, `src/experiments/store.jl`, `test/test_planning_noninteger.jl`, `test/test_experiments.jl`.
- Julia General registry `Versions.toml` + GitHub API commit/release timestamps + package `Project.toml` `[compat]` sections, all fetched 2026-07-26 — verified all package version and maintenance-activity claims.
- Clarabel.jl official docs/README (clarabel.org, github.com/oxfordcontrol/Clarabel.jl) — native PSD-cone support, the load-bearing stack finding.
- `.planning/PROJECT.md`, `.planning/RETROSPECTIVE.md`, `CLAUDE.md` — v3.0 scope, prior Key Decisions, cross-milestone lessons (gate-then-golden ordering, "tests passing ≠ mechanism live," measurement-before-golden).

### Secondary (MEDIUM-HIGH confidence)
- Farivar & Low, *"Branch Flow Model: Relaxations and Convexification"* (2013, arXiv:1204.4865); Gan, Li, Topcu & Low, *"Exact Convex Relaxation of Optimal Power Flow in Radial Networks"* (arXiv:1311.7170); Gan & Low, *"Exact Convex Relaxation of OPF in Tree Networks"* (arXiv:1208.4076) — canonical, cross-verified radial/meshed exactness theory.
- Laporte & Louveaux, *"The integer L-shaped method for stochastic integer programs with complete recourse"* (Operations Research Letters, 1993) — canonical integer Benders citation.
- InfiniteOpt.jl official docs (`guide/result.md`, `guide/transcribe.md`) + GitHub discussion #338 — dual-access indirection and warm-start-immaturity findings driving the InfiniteOpt rejection.

### Tertiary (LOW-MEDIUM confidence, single source or not independently re-verified)
- "Convex Hull of the Quadratic Branch AC Power Flow Equations..." (arXiv:1701.07146) — single source.
- Angulo, Ahmed & Dey (2016) integer L-shaped enhancement — cited by name only via secondary sources, not directly fetched.
- General decomposition/optimization theory claims (integer L-shaped weakness, meshed non-exactness structure, two-block ADMM joint stopping criteria) flagged in PITFALLS.md as standard results not independently re-verified against a specific paper this session — recommend a targeted literature check at Phase 4/5 start if HIGH confidence is wanted before implementation.

---
*Research completed: 2026-07-26*
*Ready for roadmap: yes*
