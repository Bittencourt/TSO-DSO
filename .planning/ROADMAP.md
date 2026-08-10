# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- 🚧 **v3.0 Research Extension Rungs** — Phases 19–24 (in progress)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md), and
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md).

## Phases

- [x] **Phase 19: 4Q-BESS + Live Reactive Dual-Ascent** - A battery device gets genuine P/Q decision variables inside an apparent-power cone, and the v2.1 reactive-dual scaffolding is promoted to a live, converging μ-ascent step
- [x] **Phase 20: Overvoltage-Capable Relaxation** - Price the v2.1 EXACT-04 high-PV overvoltage regime via a restricted SOCP with its own AC-certified validity certificate, establishing the reusable restriction-certificate pattern
- [x] **Phase 21: MPC / Rolling-Horizon / Real-Time Pricing** - Closed-loop receding-horizon solves over stateful devices, publishing rolling DADPs as an RTP signal benchmarked against perfect foresight
- [x] **Phase 22: Stochastic PV/Demand Uncertainty** - Two-stage extensive-form welfare solve over seeded Markov scenarios, with per-scenario DADPs as the primary price output
- [ ] **Phase 23: Meshed Networks** - A parallel `MeshedFeeder` + non-radial SOCP formulation with its own angle-recoverability certificate, combined with Phase 19's live reactive price in one literate rung page
- [ ] **Phase 24: Discrete/Integer Investment Expansion** - Binary-expansion integer investment + Laporte–Louveaux integer cuts in the planning Benders master, with the PVAL-04 no-binaries guard consciously scoped

## Phase Details

### Phase 19: 4Q-BESS + Live Reactive Dual-Ascent

**Goal**: A researcher can model a battery with genuine four-quadrant (P,Q) capability and observe a
live-converging reactive nodal price out of ADMM — not just the one-shot certified dual v2.1 shipped —
without touching the byte-identical default (no-4Q-BESS, no-dual-ascent) path.
**Depends on**: Nothing (independent of every other v3.0 axis); sequenced first because it is the
lowest-risk, fastest-to-ship axis and establishes the "new device + widened Aggregator contract"
pattern the meshed phase (23) references, and because Phase 23's combined literate page needs this
device and dual-ascent step to already exist.
**Requirements**: MESH-04, MESH-05
**Success Criteria** (what must be TRUE):

  1. Researcher can instantiate a `FourQuadBESS` device exposing sign-free active and reactive
     decision variables inside an inverter apparent-power cone `p² + q² ≤ S²max`, flowing
     device → aggregator → the `:Rq` residual.

  2. The no-binaries complementarity property (`p_ch·p_dch = 0` at the optimum) is re-derived for the
     4Q case or replaced by a hard post-solve numeric check — never silently inherited from the
     active-only battery.

  3. Researcher can enable a live reactive μ-dual-ascent step (on `:balance_q`, using the
     `qag_dso`/`reactive_consensus` scaffolding) that converges inside `solve_admm` on a fixture with
     `FourQuadBESS` present, cross-validated against the centralized solve, under its own two-block
     convergence/stopping treatment (not the single-block Boyd rule as-is).

  4. With no `FourQuadBESS` device present and the dual-ascent step disabled, ADMM and centralized
     welfare results are byte-identical to pre-milestone behavior.
**Plans:** 8 plans (6 waves)

Plans:
**Wave 1**

- [x] 19-01-PLAN.md — Wire seam stubs (FourQuadBESS.jl, complementarity_4q.jl, ReactiveMode.jl) into TSODSO.jl + capture pre-Phase-19 byte-identity baseline

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 19-02-PLAN.md — FourQuadBESS device: struct/constructors/guards, contribute! (SOC recursion + apparent-power cone + q_inject), complementarity re-derivation docstring
- [x] 19-03-PLAN.md — DsoOpt reactive_consensus promoted to 3-state (OFF/CERTIFIED/LIVE), LIVE unpins qag_dso with its own ρ_q penalty + set_rho_q!

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 19-04-PLAN.md — Aggregator.contribute! widened to roll up optional q_inject additively into :Rq, byte-identical when absent
- [x] 19-05-PLAN.md — assert_4q_complementarity! certificate (own measured tolerance, throw-by-default + report kwarg), disambiguated from assert_battery_complementarity!

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 19-06-PLAN.md — AgrOpt live qag_live coupling variable + ρ_q penalty, solve_agr! μ/d update + check_4q wiring

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 19-07-PLAN.md — solve_admm joint (λ,μ) stacked dual-ascent, μ/q_devices results surface, final-block certificate wiring

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 19-08-PLAN.md — Phase19Fixtures, measured cross-validation tolerances, liveness regression, IEEE-13 quarantined evidence, final byte-identity gate

### Phase 20: Overvoltage-Capable Relaxation

**Goal**: A researcher can price the high-PV overvoltage regime that v2.1's AC oracle proved the plain
SOCP relaxation cannot solve exactly (EXACT-04, the `Phase4Fixtures.high_pv_feeder()` stress
fixture at `pv_scale=1.2` — corrected here from the "IEEE-13" shorthand used elsewhere in this
project; it is a purpose-built 3-bus radial fixture, not the 13-bus IEEE test feeder), keeping the
"prices are duals of one convex problem" story intact via a feasible-set restriction rather than a
heuristic penalty.
**Depends on**: Nothing code-wise (independent of Phase 19); sequenced second because it produces a
reusable non-radial-adjacent "restriction + AC-certified validity certificate" pattern that Phase 23
(Meshed) reuses rather than re-deriving, and because Phase 21 (MPC)'s rolling windows can legitimately
drift into this same overvoltage regime — resolving it first gives the rolling-horizon loop a defined
fallback instead of an undefined catch-and-continue.
**Requirements**: OVR-01, OVR-02, OVR-03, OVR-04
**Success Criteria** (what must be TRUE):

  1. Researcher can solve the exact EXACT-04 stress fixture (the high-PV `Phase4Fixtures` fixture,
     `pv_scale=1.2`) via a restricted SOCP (Gan–Low-style feasible-set tightening, e.g.
     reverse-flow-aware `V²max` shrink) dispatched
     as a formulation/config variant through the existing `solve_welfare` path, at the operating point
     where the unrestricted relaxation was proven genuinely inexact.

  2. The restriction carries its own new validity certificate (peer to `assert_socp_exact!`/
     `assert_ac_exact!`, never a reused tolerance): the restricted solution is certified AC-feasible
     via the existing AC oracle, and the certificate reports the optimality loss vs. the unrestricted
     (inexact) SOCP bound.

  3. Researcher can read DADP prices in the previously-refused regime as genuine convex duals of the
     restricted problem, with a documented nonconvex-AC-dual fallback (Ipopt local duals, explicit
     local-optimum / not-market-clearing caveat, multi-start evidence) reported — never thrown — when
     even the restricted SOCP cannot certify.

  4. A live-executed literate rung page documents the restriction mechanism, its measured
     optimality-loss, and the fallback semantics beside the Gan & Low condition it implements.
**Plans:** 5 plans (5 waves)

Plans:
**Wave 1**

- [x] 20-01-PLAN.md — v ≥ v̂ sign-relationship spot-check + Gan-Low lossless-shadow-voltage helper + measured ε (Wave 1)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 20-02-PLAN.md — RestrictedBranchFlow formulation (Gan-Low OPF-ε) + default-path regression (Wave 2)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 20-03-PLAN.md — assert_restriction_exact! AC-feasibility + optimality-loss certificate (Wave 3)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 20-04-PLAN.md — ac_dual_fallback_price nonconvex-AC-dual fallback + multi-start evidence (Wave 4)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 20-05-PLAN.md — Literate rung page + full-suite acceptance (Wave 5)

### Phase 21: MPC / Rolling-Horizon / Real-Time Pricing

**Goal**: A researcher can run a closed-loop receding-horizon solve over the stateful devices (battery
SOC, thermostatic temperature), with rolling re-computed DADPs published as a real-time price signal,
and see the closed loop honestly benchmarked against the perfect-foresight day-ahead optimum.
**Depends on**: Phase 20 (a rolling window can traverse the overvoltage-exactness boundary mid-simulation
and needs Phase 20's certified restriction/fallback rather than an undefined behavior); shares an
identical `Scenario.jl` schema-extension blast radius with Phase 22 — both axes' field additions should
land as one coordinated, tightly-reviewed pair of diffs to halve the review surface on that
schema-fragile, golden-hash-bearing file.
**Requirements**: MPC-01, MPC-02, MPC-03, MPC-04
**Success Criteria** (what must be TRUE):

  1. Researcher can run a deterministic receding-horizon closed-loop solve where, at each step, a
     window `[t, t+H]` problem is initialized from the measured device state (battery SOC,
     thermostatic temperature) via JuMP `Parameter` injection — built once and re-solved per step,
     never rebuilt.

  2. A hard terminal-SOC condition prevents end-of-horizon myopic battery dump/hoarding, demonstrated
     by a regression showing the artifact present when the condition is disabled and absent when it
     is enabled.

  3. The rolling re-computed DADP is published per step as an RTP signal, with price-consistency
     metrics (step-to-step price jumps, cumulative deviation from the day-ahead DADP path) recorded
     in a new trace struct following the `AdmmResiduals`/`BendersTrace` convention.

  4. The closed-loop trajectory is benchmarked against the perfect-foresight day-ahead optimum under
     seeded synthetic forecast error (bounded perturbation of the known ground truth), on an
     information-set-fair comparison, in a live-executed literate rung page.
**Plans:** 6 plans (5 waves)

Plans:
**Wave 1**

- [x] 21-01-PLAN.md — Parameter-widen PVBattery/Thermostatic/FourQuadBESS/Aggregator (soc0/Tin0/Ppv/Tout/Pdc), the SEAM-01 build-once mechanism's prerequisite
- [x] 21-02-PLAN.md — MpcTrace ledger (AdmmResiduals/BendersTrace convention) for per-step DADP/jump/cumulative-deviation/certificate-status

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 21-03-PLAN.md — build_mpc_window/solve_mpc_window! build-once window model + terminal-SOC toggle + Phase21Fixtures CI substrate

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 21-04-PLAN.md — Scenario.jl D-12 additive fields + nominal-plant state propagation/seeded forecast-error draw + MPC-02 dump/hoard regression

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 21-05-PLAN.md — run_mpc closed-loop orchestrator + Phase-20 certificate/fallback escalation ladder + regret benchmark

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 21-06-PLAN.md — Literate rung page (mpc_rolling_horizon.jl) + full-suite acceptance

### Phase 22: Stochastic PV/Demand Uncertainty

**Goal**: A researcher can solve a two-stage extensive-form welfare problem over a small seeded
scenario set, with per-scenario DADPs as the primary, honestly-documented price output rather than an
unconstrained "expected price."
**Depends on**: Phase 21 (reuses the coordinated `Scenario.jl` schema extension landed there, and can
reuse Phase 21's `Parameter`-pinned window-oracle convention directly if the extensive form is
decomposed); both phases' schema diffs to `experiments/Scenario.jl` are reviewed as one coordinated pair.
**Requirements**: STOCH-01, STOCH-02, STOCH-03, STOCH-04
**Success Criteria** (what must be TRUE):

  1. Researcher can solve a two-stage extensive-form welfare problem over a small fixed set of seeded
     Markov scenarios (3–5, explicit probabilities, generated by the existing seeded Markov data
     layer) with shared first-stage decisions and per-scenario recourse, solved by Clarabel within
     measured capacity.

  2. Per-scenario DADPs (the dual of each scenario's own nodal balance, PF-04-gated per scenario) are
     the primary price output; the probability-weighted expectation is reported only as a derived
     summary statistic — documented as such, never presented as an unconstrained "expected price"
     primitive.

  3. An out-of-sample validation harness evaluates the extensive-form first-stage decisions against
     held-out scenarios not used in the optimization, reporting the realized-vs-in-sample welfare
     gap, with goldens pinned only after repeated-run stability is checked (v2.1
     measurement-before-golden pattern).

  4. A live-executed literate rung page documents the extensive form, the per-scenario price
     semantics decision, and the out-of-sample result.
**Plans:** 5 plans (5 waves)

Plans:
**Wave 1**

- [x] 22-01-PLAN.md — Scenario.jl stoch_* additive fields (stoch_S/stoch_probabilities/stoch_H_oos) + Phase22Fixtures small Deferrable-free CI fixture

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 22-02-PLAN.md — build_stochastic_welfare: S-scenario extensive form (JuMP.unregister decoupling, nonanticipativity ties, per-scenario PF-04 gate, de-scaled DADP)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 22-03-PLAN.md — StochasticOosHarness: Parameter-pinned single-scenario build-once out-of-sample model

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 22-04-PLAN.md — run_stochastic(s::Scenario) orchestrator + realized-vs-in-sample welfare gap + measurement-before-golden

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 22-05-PLAN.md — Literate rung page (stochastic_pv_demand.jl) + full-suite acceptance

### Phase 23: Meshed Networks

**Goal**: The SEAM-01 meshed-formulation slot gets its own non-radial branch-flow formulation and its
own validity treatment (angle-recoverability, not the radial per-branch gate), combined with Phase 19's
live reactive price into one literate rung page.
**Depends on**: Phase 19 (the 4Q-BESS device + live reactive dual-ascent must already exist for the
combined meshed+4Q-BESS validation and for this phase's literate page to document the live reactive
price alongside the meshed formulation) and Phase 20 (reuses the restriction/AC-certified validity
certificate pattern established there rather than inventing a second, divergent certification
strategy) — the flagged PROJECT.md interdependency between overvoltage-capable relaxation and
meshed+4Q-BESS. Highest architecture-plus-math risk in the milestone; scheduled so its
research/validation overrun does not block the other axes.
**Requirements**: MESH-01, MESH-02, MESH-03, MESH-06
**Success Criteria** (what must be TRUE):

  1. A `MeshedFeeder` data type (loop-carrying topology, at least one committed meshed fixture) exists
     alongside the radial `Feeder`, with the radial constructor invariant (`assert_radial`) left
     completely untouched.

  2. Researcher can solve the meshed SOCP branch-flow problem via a `MeshedFlow <: AbstractPowerFlow`
     (or equivalent) through the SEAM-01 `pf` dispatch seam, with cycle/loop consistency handled
     explicitly — never the radial Baran–Wu variables alone.

  3. The meshed rung's own new angle-recoverability a-posteriori certificate (Gan–Low condition) is
     the validity gate: recoverable cases are certified with recovered angles; unrecoverable cases
     report the SOCP value as a valid lower bound with the inexactness stated as a first-class
     finding (report-don't-throw) — never the per-branch `assert_socp_exact!` alone, which is
     structurally blind to loop inconsistency.

  4. A live-executed literate rung page documents the meshed formulation, the angle-recoverability
     certificate, and the live reactive price from Phase 19 together (no literal IEEE-1547 Volt-VAR
     droop controller — optimal `q(v)` behavior characterized post-hoc if wanted).
**Plans:** 4 plans (4 waves)

Plans:
**Wave 1**

- [x] 23-01-PLAN.md — MeshedFeeder + assert_connected data-layer foundation, assert_radial/Feeder byte-unchanged (D-01/D-09)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 23-02-PLAN.md — MeshedFlow delegation formulation + Phase23Fixtures committed loop fixture (uniform/heterogeneous R/X profiles, D-02/D-03/D-10)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 23-03-PLAN.md — certify_angle_recoverable! chord-aware angle-recoverability certificate, tolerances measured fresh on the committed fixture (D-05/D-06/D-07/D-08)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 23-04-PLAN.md — Literate rung page (meshed_reactive_price.jl) combining the certificate with Phase 19's live reactive price + full-suite acceptance

### Phase 24: Discrete/Integer Investment Expansion

**Goal**: The single-distributor planning Benders loop supports genuine binary-expansion integer
investment, converging on real Laporte–Louveaux integer optimality cuts, with the PVAL-04 no-binaries
guard consciously scoped rather than deleted.
**Depends on**: The v2.0 continuous Benders baseline (`PVAL-02..04` goldens) staying stable to diff
against — structurally independent of Phases 19–23 (touches only `src/planning/`) and could in
principle be parallelized against any of them from a code-conflict standpoint, but sequenced last
because it is the single highest algorithmic-risk item in the milestone (integer-cut correctness,
weaker convergence theory), giving the most time to resolve cut-correctness concerns and keeping the
earlier, lower-risk axes' validated rungs unblocked.
**Requirements**: INT-01, INT-02, INT-03, INT-04
**Success Criteria** (what must be TRUE):

  1. Researcher can configure the planning master with binary-expansion integer investment (bounded
     integer levels as binary blocks), solved as a HiGHS MILP behind the existing `select_optimizer`
     factory (new/extended `ProblemClass` as needed), single-distributor Stackelberg scope.

  2. Convergence is driven by genuine Laporte–Louveaux integer optimality cuts (LP Benders cuts
     retained where valid; plain no-good cuts only as a documented anti-stall fallback, never the
     convergence argument), with iteration behavior re-measured on this problem class — not inherited
     from the continuous Benders defaults.

  3. The integer loop is certified on a tiny instance against an independent oracle (exhaustive
     enumeration of the discrete investment lattice, and/or a BilevelJuMP reduction where
     mode-compatible — checked, not assumed), following the v2.0 certify-before-build precedent.

  4. The PVAL-04 no-binaries guard is scoped, not deleted: a registry exemption for the lifted
     builder(s) only, with the full unmodified guard test still green for every non-lifted builder
     (operational layer stays binary-free), and a live-executed literate page documents the guard
     lift and cut mechanism.
**Plans**: TBD

<details>
<summary>✅ v1.0 Operational Transactive-Energy Core (Phases 1–9) — SHIPPED 2026-07-20</summary>

- [x] Phase 1: Plumbing & Solver Abstraction (4/4 plans) — completed 2026-07-18
- [x] Phase 2: Linear Branch-Flow Residual Seam (4/4 plans) — completed 2026-07-18
- [x] Phase 3: Prosumer Device Library & Social-Welfare Solve (5/5 plans) — completed 2026-07-18
- [x] Phase 4: Convex Branch-Flow Correctness Milestone (6/6 plans) — completed 2026-07-19
- [x] Phase 5: Distribution Pricing — DADP & DLMP Decomposition (5/5 plans) — completed 2026-07-19
- [x] Phase 6: ADMM Decomposition Core (4/4 plans) — completed 2026-07-19
- [x] Phase 7: ADMM Convergence & Scale (6/6 plans) — completed 2026-07-19
- [x] Phase 8: Experiment Harness & Reproducibility (4/4 plans) — completed 2026-07-20
- [x] Phase 9: Documentation & Regression Acceptance Gate (5/5 plans) — completed 2026-07-20

Delivered: the full operational layer (rungs 0–5) — solver abstraction, residual-seam power-flow
(DC/LinDistFlow/SOCP Convex Branch Flow with validated exactness), prosumer device library +
GLB-CVX social welfare, DADP/DLMP dual-based pricing with 4-way decomposition, ADMM decomposition
validated against the centralized optimum (IEEE 13 + 123), a reproducible experiment harness, and
literate per-model docs + an end-to-end regression acceptance gate. 1946 tests pass.

</details>

<details>
<summary>✅ v2.0 Stackelberg-Nash TSO–DSO Planning Game (Phases 10–14) — SHIPPED 2026-07-24</summary>

- [x] Phase 10: Oracle Coupling Wiring & Resilience (2/2 plans) — completed 2026-07-22
- [x] Phase 11: Single-Distributor Stackelberg-Benders (Certified) (3/3 plans) — completed 2026-07-22
- [x] Phase 12: Cut-Store & Benders Master Robustness Hardening (2/2 plans) — completed 2026-07-23
- [x] Phase 13: Nash Diagonalization & Shared-Transmission Coupling (3/3 plans) — completed 2026-07-24
- [x] Phase 14: Validation-Oracle Regression Hardening & Docs (3/3 plans) — completed 2026-07-24

Delivered: the thesis's planning layer (rungs 6–7) — build-once Parameter-pinned planning oracle
with retry/checkpoint resilience, hand-rolled single-distributor Stackelberg-Benders certified
against BilevelJuMP MPEC reductions (leader/follower role + dual sign empirically pinned),
hardened cut store + BendersTrace ledger, SharedTransmission N-distributor corridor coupling,
run_nash! Gauss-Seidel diagonalization with nested tolerances + NashTrace two-level diagnostics,
run_nash_probe multi-seed/multi-order honesty gate ("a converged equilibrium", never "the"),
pinned computed goldens, a registry+tripwire no-binaries guard, and two live-executed literate
planning docs pages. Audit: 15/15 requirements, 10/10 integration seams. 2276 tests pass.

</details>

<details>
<summary>✅ v2.1 Validation & Reproduction (Phases 15–18) — SHIPPED 2026-07-26</summary>

- [x] Phase 15: AC-Exactness Oracle (3/3 plans) — completed 2026-07-26
- [x] Phase 16: Reactive-Power (μ) Consensus (4/4 plans) — completed 2026-07-26
- [x] Phase 17: Real IEEE-123 Impedances (4/4 plans) — completed 2026-07-26
- [x] Phase 18: Directional Thesis Reproduction (3/3 plans) — completed 2026-07-26

Delivered: the framework's validation & reproduction layer — an independent nonconvex AC-OPF oracle
(`ACPowerFlow` + `assert_ac_exact!`, Ipopt, true equality `l·v==P²+Q²`) that certifies the SOCP
relaxation per-hour and surfaces a **genuine high-PV/reverse-flow inexactness as a first-class citable
finding** (`pv_scale=1.2`, gap≈10.4) rather than tuning it away; a genuine reactive-power balance with a
**certified, citable reactive DLMP component** (`reactive_consensus` flag + `qag_dso` pinned coupling +
`assert_no_slack` on `:balance_q`, byte-identical default path); **real positive-sequence IEEE-123
impedances** reduced from public OpenDSS data via a dependency-free Fortescue parser (PMD kept out of
runtime `[deps]`), with an honest **asymmetric voltage-binding** finding (lower band transfers, upper
overvoltage band sits on the SOCP-inexactness knife-edge); and a defensible **directional, public-data**
thesis reproduction — the **DSO-surplus sign flip reproduces** (FIT −196.22 → DADP +3.73, prosumer
decreases) while the **+25% welfare magnitude does NOT** (~+0.045%), stated plainly, with a
measurement-before-golden stability harness. Audit: 12/12 requirements, 6/6 integration seams. 2348
tests pass (the only 2 failures are pre-existing Aqua/CairoMakie `Project.toml` drift, not regressions).

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–9 (archived) | v1.0 | 43/43 | Complete | 2026-07-20 |
| 10–14 (archived) | v2.0 | 13/13 | Complete | 2026-07-24 |
| 15–18 (archived) | v2.1 | 14/14 | Complete | 2026-07-26 |
| 19. 4Q-BESS + Live Reactive Dual-Ascent | v3.0 | 8/8 | Complete    | 2026-08-08 |
| 20. Overvoltage-Capable Relaxation | v3.0 | 5/5 | Complete    | 2026-08-09 |
| 21. MPC / Rolling-Horizon / Real-Time Pricing | v3.0 | 6/6 | Complete    | 2026-08-09 |
| 22. Stochastic PV/Demand Uncertainty | v3.0 | 5/5 | Complete    | 2026-08-10 |
| 23. Meshed Networks | v3.0 | 4/4 | Complete   | 2026-08-10 |
| 24. Discrete/Integer Investment Expansion | v3.0 | 0/TBD | Not started | - |

## Deferred / Future-Milestone Notes

- **Meshed + 4Q-BESS**: NO LONGER deferred — active this milestone as Phases 19 (4Q-BESS + live
  reactive dual-ascent) and 23 (meshed formulation + angle-recoverability certificate).

- **Discrete/integer investment expansion**: NO LONGER deferred — active this milestone as Phase 24;
  the PVAL-04 no-binaries guard is consciously scoped (not deleted) there.

- **A live cross-subproblem reactive dual-ascent loop** (4Q-BESS/volt-var): NO LONGER deferred —
  active this milestone as Phase 19's μ-ascent step, replacing v2.1 Phase 16's one-shot certified dual.

- **MPC/rolling-horizon RTP** and **stochastic PV/demand uncertainty**: NO LONGER deferred — active
  this milestone as Phases 21 and 22, sequenced together for their shared `Scenario.jl` schema blast
  radius.

- **OVR-STRETCH** (convex-hull relaxation / QC valid-inequality tightening as an alternative to
  restriction, arXiv:1701.07146): still deferred past this milestone's Phase 20 — restriction is the
  chosen v3.0 mechanism; convex-hull/QC tightening is a natural v3.1+ differentiator, not a table-stakes
  requirement.

- **MPC-STRETCH** (economic-MPC terminal value function, robust/tube MPC): still deferred past Phase
  21 — the hard terminal-SOC condition is the minimal-rung mechanism; economic-MPC terminal cost
  functions and robustness are explicitly out of scope for this milestone's rung.

- **STOCH-STRETCH** (formal scenario reduction — fast-forward/k-means, SAA convergence studies,
  distributionally-robust/chance-constrained variants, `DualDecomposition.jl` if scenario counts
  outgrow the extensive form): still deferred past Phase 22 — 3–5 fixed seeded scenarios are the
  minimal-rung scope.

- **MESH-STRETCH** (QC/SDP tightening via Clarabel's native PSD cone, phase-shifter convexification
  per Farivar–Low): still deferred past Phase 23 — contingent on whether the angle-recoverability
  check fails structurally on the committed meshed fixture; only pursued if that gap proves genuine
  and un-avoidable, per the Pitfall-15 "structural gap vs. tunable knife-edge" distinction.

- **INT-STRETCH** (integer **Nash** diagonalization — MILP best-responses across N distributors;
  Angulo et al. 2016 alternating-cut refinements): still deferred past Phase 24 — single-distributor
  integer-cut correctness must be proven first; equilibrium-existence theory is judged too weak to
  stack on unproven cut machinery yet.

- **Exact-figure thesis reproduction** (`REPRO-STRETCH-01`, the +$1,819/+25% headline): still deferred,
  contingent on obtaining thesis Appendix E (currently behind an IP-blocked CONICET repository).
  Unrelated to any v3.0 axis; v2.1's Phase 18 delivered only a directional (sign + band) reproduction.

- **v2.1 overvoltage / SOCP-exactness knife-edge**: the specific finding motivating Phase 20 — on real
  IEEE-123 impedances the upper voltage band (PV overvoltage) cannot be pushed toward ~1.05 while the
  plain SOCP relaxation stays exact. Phase 20 addresses this for IEEE-13's EXACT-04 fixture; whether
  the restriction mechanism also resolves the IEEE-123 real-impedance case is an open question for
  Phase 20 to answer, not assumed.

- **Deferred tech debt**: see `milestones/v1.0-MILESTONE-AUDIT.md`, `milestones/v2.0-MILESTONE-AUDIT.md`,
  and `milestones/v2.1-MILESTONE-AUDIT.md` (unflipped Nyquist flags, ROADMAP "reactive pricing"
  wording, the `julia -e '@run_package_tests'` sibling-worktree gotcha, user-local Project.toml/Manifest
  CairoMakie drift, Clarabel NUMERICAL_ERROR root cause).
