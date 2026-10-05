# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)
- 🚧 **v4.0 Correctness & Depth** — Phases 26–37 (in progress)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md),
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md), and
[`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md).

## v4.0 Correctness & Depth

**Milestone Goal:** Fix the modeling defects confirmed by the 2026-09-28 full-project quality
audit, deepen the planning layer into a genuine bilevel TSO–DSO game on a real network, then
restructure the orchestration layer and clean the codebase — correctness first, depth second,
structure third, hygiene last.

**Golden policy:** the v1–v3 "byte-identical default path" rule is consciously relaxed for the
correctness track. Any pinned golden that moves is re-derived, and the change is explained in the
test comment and the phase SUMMARY. Nothing is silently re-pinned.

## Phases

- [x] **Phase 26: Network & Device Model Correctness** - Fix the reversed exactness copy, add the (completed 2026-09-29)
  reverse thermal limit, link battery SOC across the horizon, and give flexible loads their
  reactive draw.

- [x] **Phase 27: Integer Planning & Pricing Certificate Correctness** - Fix `corner_recourse` for (completed 2026-09-29)
  T>1, relabel DLMP components honestly, tighten the exactness-gate floor, certify the FIT
  baseline, and settle MPC realized welfare against the true plant.

- [x] **Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement** - Re-derive every (completed 2026-09-30)
  golden touched by the correctness fixes and re-run/restate the thesis reproduction and
  SOCP-inexactness findings.

- [x] **Phase 29: Genuine Bilevel TSO-DSO Variant** - Solve a true bilevel game (TSO minimizes its (completed 2026-10-01)
  own cost against a DSO tariff) that the BilevelJuMP oracle can tell apart from joint
  optimization.

- [x] **Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder** - Run Stackelberg-Benders with (completed 2026-10-01)
  `ConvexBranchFlow` on a real multi-bus, multi-period feeder, with oracle feasibility cuts and
  derived master bounds.

- [x] **Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh** - Expose GNE multiplicity (completed 2026-10-02; NOT verified — 2 open critical findings, see Phase 31 detail below)
  with a variational-equilibrium selection, run integer investment across N>1 distributors, and
  refresh the planning-variant documentation.

- [x] **Phase 32: Declarative Power-Flow & Strategy Dispatch** - Select power-flow formulation and (completed 2026-10-03)
  solve strategy declaratively through `Scenario`, dispatched via one `run` entry point.

- [x] **Phase 33: Shared Abstractions — Feeder, Balance, Model Context** - Unify `Feeder`/ (completed 2026-10-04)
  `MeshedFeeder` under `AbstractFeeder`, deduplicate balance-closing code, and type `ModelContext`.

- [x] **Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy** - Split (completed 2026-10-04)
  `solve_admm` into named phases generic over any power flow, compose meshed + live reactive
  pricing, and apply one status/exception policy everywhere.

- [x] **Phase 35: IEEE-8500 Scale After Refactor** - Re-measure (or re-characterize) the IEEE-8500 (completed 2026-10-05)
  performance/memory headline point after the architecture changes.

- [ ] **Phase 36: Code & Export Cleanup** - Strip process IDs from comments, delete inert stubs and
  back-compat shims, trim exports, and rename fixtures after their content.

- [ ] **Phase 37: Test Infrastructure & Repo Hygiene** - Add a JET CI check, split fast/slow tests,
  fix or quarantine known flakes, and tidy scripts/manifests.

## Phase Details

### Phase 26: Network & Device Model Correctness

**Goal**: Researcher can trust that the default SOCP branch-flow formulation and the SOC device
models (`PVBattery`, `FourQuadBESS`) reflect the thesis physics, not a silently-introduced
restriction or free hour-T energy.
**Depends on**: Nothing (first phase of v4.0)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04, FIX-05
**Success Criteria** (what must be TRUE):

  1. A documented verdict on thesis eq. 3.43 exists (relaxation vs. restriction, checked against
     the thesis PDF and Gan–Low 2015), backed by a passing regression on a heavy-load, low-voltage
     3-bus feeder that is AC-feasible (Ipopt) and also feasible under the default SOCP formulation.

  2. The default `ConvexBranchFlow` exactness copy satisfies v̂ ≥ v (Gan–Low direction) or is
     clearly relabelled as a restriction; a test checks the docstring's claimed load-bearing bound
     against the actual constraint.

  3. A PV back-feed fixture shows the reverse (receiving-end) apparent-power limit (thesis 3.37)
     binding on a limited branch.

  4. `PVBattery` and `FourQuadBESS` link state of charge across the whole horizon; the "soc0=Emin,
     discharge at hour T" regression is infeasible or forces zero discharge.

  5. A per-device test shows interruptible/thermostatic/deferrable loads drawing reactive power
     `q = p·tanφ` (thesis 3.23) into `:Rq`.

  6. Every golden this phase's fixes move is re-derived in-phase with a stated explanation (test
     comment + phase SUMMARY), and the full suite is green at phase close — no golden is left red
     for a later phase and none is silently re-pinned.
**Plans:** 20/20 plans complete

Plans:
**Wave 1**

- [x] 26-01-PLAN.md — Baseline full-suite measurement before any fix lands
- [x] 26-02-PLAN.md — FIX-01/02: cpydrop sign flip to the Gan-Low direction, thesis-literal opt-in, verdict docs, 3-bus regression
- [x] 26-03-PLAN.md — FIX-04: battery SOC horizon linking (PVBattery, FourQuadBESS, mpc_window terminal wiring)
- [x] 26-04-PLAN.md — FIX-05: Aggregator flexible-load reactive draw (Thermostatic, Deferrable) + is_flexible_load trait

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 26-05-PLAN.md — FIX-03: receiving-end apparent-power limit (:smax_rev) + PV back-feed fixture
- [x] 26-06-PLAN.md — DLMP voltage-component coefficient re-derivation after the cpydrop sign flip
- [x] 26-07-PLAN.md — FIX-05: Interruptible Variant-1→2 conversion + solve_linear.jl fix

**Gap-closure wave 1** *(post-merge remediation, per 26-POSTMERGE-TRIAGE.md — parallel, disjoint files)*

- [x] 26-09-PLAN.md — Cluster A: stochastic_welfare.jl Prev/Qrev/smax_rev unregister fix + run_stochastic:104 golden repin
- [x] 26-10-PLAN.md — Cluster B: decompose_dlmp :smax_rev congestion dual + near-lossless DLMP tol_gap (D-26-01)
- [x] 26-11-PLAN.md — Cluster C: mpc_loop.jl/test_mpc_terminal.jl soc[H+1] reindex + mpc_step guard re-scope
- [x] 26-12-PLAN.md — PM-03: ADMM DsoOpt live-reactive default whenever flexible loads are present
- [x] 26-13-PLAN.md — PM-04: mesh diamond fixture φ=1.0 pin + reactive-load-breaks-exactness finding
- [x] 26-14-PLAN.md — PM-02: AC oracle battery-complementarity throw-to-diagnostic + App. C eta<1 finding
- [x] 26-15-PLAN.md — PM-07: ACPowerFlow receiving-end apparent-power limit (:smax_rev)
- [x] 26-16-PLAN.md — Cluster E: admm/planning_oracle/admm_reactive near-lossless SOCP tolerance calibration
- [x] 26-17-PLAN.md — PM-06: ieee13/pricing_fit/pricing_welfare golden repins + pricing_welfare tol_gap

**Gap-closure wave 2** *(blocked on wave-1 gap-closure completion)*

- [x] 26-18-PLAN.md — PM-01: Gan-Low relabeling (restriction, not relaxation) + escalation-ladder re-force
- [x] 26-19-PLAN.md — test_acceptance.jl golden repin (cross-ref 26-17) + IEEE-123 tol_gap calibration
- [x] 26-20-PLAN.md — ADMM knife-edge canary re-pin (post PM-03)

**Wave 3** *(blocked on ALL of the above)*

- [x] 26-08-PLAN.md — SC-6 golden-move audit (both waves) + final full-suite green

### Phase 27: Integer Planning & Pricing Certificate Correctness

**Goal**: Researcher can trust the integer Benders recourse for T>1, the DLMP component names, the
exactness gate, the FIT-baseline counterfactual, and MPC's realized-welfare accounting.
**Depends on**: Phase 26
**Requirements**: FIX-06, FIX-07, FIX-08, FIX-09, FIX-10
**Success Criteria** (what must be TRUE):

  1. `corner_recourse` returns the true per-hour `Q(bᵛ)` for T>1 (matching exhaustive enumeration
     on a T>1 test) or rejects T>1 with a clear error, instead of a flat `fill(z, T)` profile.

  2. DLMP components are named/documented after what they mathematically are (cone-slot and
     drop-constraint multipliers); the "voltage component ≈ 0 when unbinding" test uses realistic
     impedances and passes, or is replaced by a correct property.

  3. The SOCP exactness gate uses a per-branch relative floor; a test shows a slack cone on a
     lightly loaded branch is flagged.

  4. The FIT-baseline counterfactual asserts or reports exactness (never skips it); the
     `tol_gap=1e-10` `ALMOST_OPTIMAL` flake is root-caused and fixed or explicitly bounded.

  5. MPC realized welfare/regret settle against the true plant (PV clipping, true-state feasibility,
     true import); the forecast-settled number survives only as a separately labelled diagnostic.

  6. Every golden this phase's fixes move is re-derived in-phase with a stated explanation (test
     comment + phase SUMMARY), and the full suite is green at phase close.

**Plans:** 9/9 plans complete

Plans:
**Wave 1**

- [x] 27-01-PLAN.md — FIX-06: corner_recourse joint T>1 recourse + T=2 grid-enumeration certification
- [x] 27-02-PLAN.md — FIX-08: per-branch exactness floor in assert_socp_exact!
- [x] 27-03-PLAN.md — FIX-10: MPC truth-plant settlement (clip, throw, loss-exact import)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 27-04-PLAN.md — FIX-07: DLMP cone/drop rename with deprecated .loss/.voltage alias
- [x] 27-05-PLAN.md — FIX-09: fit_baseline exactness certificate + ALMOST_OPTIMAL root-cause

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 27-06-PLAN.md — SC-6 golden-move audit + final full-suite certification

### Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement

**Goal**: The project's headline findings (thesis reproduction, SOCP-inexactness) are re-run
against the corrected models and restated, and a cross-phase audit confirms every golden moved in
Phases 26–27 was re-derived with an explanation (goldens themselves are re-derived in-phase).
**Depends on**: Phase 26, Phase 27
**Requirements**: FIX-11
**Success Criteria** (what must be TRUE):

  1. A cross-phase golden audit lists every golden moved in Phases 26–27 with its old value, new
     value, and explanation (test comment + SUMMARY), and confirms none was silently re-pinned.

  2. The v2.1 thesis reproduction (DSO-surplus sign flip, welfare-magnitude gap) is re-run against
     the corrected model and PROJECT.md/the literate docs restate whichever result changed.

  3. The v2.1/v3.0 SOCP-inexactness findings (e.g. EXACT-04) are re-verified against the corrected
     exactness copy and restated if the verdict changed.
**Plans:** 6/5 plans complete

Plans:
**Wave 1**

- [x] 28-01-PLAN.md — SC-1: cross-phase golden-move audit script + 28-CROSS-PHASE-AUDIT.md
- [x] 28-02-PLAN.md — SC-2: REPRO-01 thesis-reproduction re-run + restatement + figure regen
- [x] 28-03-PLAN.md — SC-3: EXACT-04 dual-mode (cone vs AC-optimality) re-verification + restatement

**Wave 2** *(concurrency-cap only — no data dependency on Wave 1)*

- [x] 28-04-PLAN.md — SC-3: MPC truth-settlement + DLMP naming restatement

**Wave 3** *(phase-closing gate, blocked on ALL of the above)*

- [x] 28-05-PLAN.md — Full-suite + docs-build certification, consolidated findings + PROJECT.md restatement

### Phase 29: Genuine Bilevel TSO-DSO Variant

**Goal**: Researcher can express and solve a genuinely bilevel TSO–DSO game — not the integrated
problem decomposed by Benders — certified as distinct from the joint optimum.
**Depends on**: Phase 28
**Requirements**: BILEV-01, BILEV-02
**Success Criteria** (what must be TRUE):

  1. Researcher can solve a variant where the TSO follower minimizes its own cost, the DSO leader
     pays a tariff π·z, and the follower's objective genuinely differs from the leader's view of it,
     via the hand-rolled loop or a documented appropriate reformulation.

  2. A BilevelJuMP-certified fixture exists on which the bilevel optimum provably differs from the
     joint single-level optimum.

  3. The production method's answer matches the bilevel optimum on that fixture, not the joint one.

**Plans:** 4/4 plans complete

Plans:
**Wave 1**

- [x] 29-01-PLAN.md — BILEV-01: build_bilevel_kkt/solve_bilevel! embedded-LinDistFlow KKT-MILP + benders.jl docstring relabel (+ q_op curvature keyword, BLOCKER-1 revision)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 29-02-PLAN.md — BILEV-02: BilevelJuMP StrongDualityMode + brute-force certification vs. joint optimum (corner fixture)
- [x] 29-04-PLAN.md — BILEV-02 BLOCKER-1 remediation: non-degenerate (interior-response) certification fixture, SOS1 branch-switch assertion, z≡0 mutation guard

**Wave 3** *(phase-closing gate, blocked on Wave 1-2 completion)*

- [x] 29-03-PLAN.md — Golden-move audit, consolidated findings, full-suite certification

### Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder

**Goal**: Researcher can run Stackelberg-Benders with the real branch-flow SOCP on a realistic
multi-bus, multi-period feeder, with feasibility cuts and automatically derived bounds.
**Depends on**: Phase 29
**Requirements**: BILEV-03, BILEV-04, BILEV-05
**Success Criteria** (what must be TRUE):

  1. `solve_stackelberg!` runs with `ConvexBranchFlow` on IEEE-13 (or larger) and T>1 inside the
     Benders loop, converging with a closed LB/UB gap.

  2. The planning oracle produces a feasibility cut when a pinned z is voltage- or thermally
     infeasible.

  3. SOCP inexactness at a pinned z is handled by a documented policy (restricted formulation, AC
     fallback, or reported cut rejection) instead of crashing the loop.

  4. The master's α lower bounds (`α_op_lb`, `α_x_lb`) are derived automatically (e.g. from the
     relaxed oracle/follower optimum); a user-supplied bound above the true minimum is detected and
     rejected.
**Plans:** 6/6 plans complete

Plans:
**Wave 1**

- [x] 30-01-PLAN.md — BILEV-04a/04b infra: feasibility oracle (slack-min) + incumbent-only AC physics re-check
- [x] 30-02-PLAN.md — BILEV-05: :auto epigraph-bound derivation in build_master + repo-wide T>1 alpha-bound audit
- [x] 30-03-PLAN.md — BILEV-03 fixture: tuned T in [3,6] IEEE-13 population (z=0 feasible) + independent monolithic joint reference

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 30-04-PLAN.md — BILEV-04/05 integration: inexact_policy dispatch, oracle-feasibility-cut branch, :auto bounds wiring, AC-recheck-at-convergence hook

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 30-05-PLAN.md — BILEV-03: convergence + monolithic cross-check test, T=24 Literate experiment extension

**Wave 4** *(phase-closing gate, blocked on ALL of the above)*

- [x] 30-06-PLAN.md — Golden-move audit, consolidated findings, full-suite certification

### Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh

**Goal**: Researcher can see and select among multiple Nash equilibria under interior caps, run
integer investment across N>1 distributors, and read docs that accurately state each planning
variant's game-theoretic nature.
**Depends on**: Phase 30, Phase 27
**Requirements**: BILEV-06, BILEV-07, BILEV-08
**Success Criteria** (what must be TRUE):

  1. A Nash fixture with interior investment caps exposes a continuum of generalized Nash
     equilibria — the probe reports a nonzero spread.

  2. A variational-equilibrium (common shared multiplier) selection is available and documented.
  3. Integer investment runs in the N>1 Nash diagonalization path, with each best response using
     the integer master.

  4. `docs/writeups/stackelberg_vs_psr_n1n2.typ` and related docs state the game-theoretic nature
     of each planning variant (integrated-decomposed-by-Benders, genuine bilevel, shared-constraint
     GNE), refreshed to current code including the integer master.
**Plans:** 7/7 plans complete

**VERIFIED 2026-10-03:** a post-certification code review found 2 critical findings (CR-01 false
integer-cycle detection on converging runs; CR-02 VE selection vacuous on the symmetric
interior-cap fixture); both were fixed in a 3-iteration review/fix cycle (cap reached: 0 critical,
0 warning, 2 info open). Full suite re-certified 31260/0/0/5; UAT 5/5 (`31-UAT.md`). See
`31-FINDINGS.md` "Post-review fix cycle" and `31-REVIEW.md`.

Plans:
**Wave 1**

- [x] 31-01-PLAN.md — WR-01: feas_oracle-confirmed ALMOST_INFEASIBLE in the integer corner search (WR-03 found BLOCKED here, Option B breaks goldens — closed instead by 31-07's Option A)
- [x] 31-02-PLAN.md — WR-02 root fix: integer master bounds_ctx/lb_slack + Laporte-Louveaux cut-validity guard
- [x] 31-03-PLAN.md — BILEV-06a/06b: interior-cap GNE fixture + run_nash_probe seed extension + solve_variational_equilibrium

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 31-04-PLAN.md — BILEV-07: run_nash! integer kwarg + cycle detection + N=2 integer Nash brute-force certification
- [x] 31-07-PLAN.md — WR-03 gap closure: Option A build-time clamp (accepted-but-slack explicit epigraph bound) in build_master/build_master_integer

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 31-05-PLAN.md — BILEV-08: planning-variant taxonomy + docs refresh (stackelberg_vs_psr_n1n2.typ, modelo_stackelberg_dso_unico.typ, 3 docstrings)

**Wave 4** *(phase-closing gate, blocked on ALL of the above)*

- [x] 31-06-PLAN.md — Golden-move audit, consolidated findings, full-suite certification

### Phase 32: Declarative Power-Flow & Strategy Dispatch

**Goal**: Researcher can select the power-flow formulation and the solve strategy declaratively
through `Scenario`, dispatched via one common entry point.
**Depends on**: Phase 31
**Requirements**: ARCH-01, ARCH-02
**Success Criteria** (what must be TRUE):

  1. Researcher can select the power-flow formulation via `Scenario` and `run_scenario` honours it;
     nothing is hard-coded to `ConvexBranchFlow()`.

  2. Solve strategies are types (`Centralized`, `ADMM`, `MPC`, `Stochastic`) dispatched through one
     `run(strategy, scenario)` entry point that returns results with a common shape.

  3. `Scenario` no longer carries strategy-specific fields in one flat bag.

**Plans**: 7 plans

Plans:
**Wave 1**

- [x] 32-01-PLAN.md — strategy types (`Centralized`/`ADMM`/`MPC`/`Stochastic`), `TSODSO.run`, `supports_pf`, details structs

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 32-02-PLAN.md — restructured `Scenario` (pf selector + strategy field + legacy kwarg ctor), `build_powerflow`

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 32-03-PLAN.md — `ScenarioResult` reshape, `run(::Centralized/ADMM)` with pf wiring and guards

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 32-04-PLAN.md — store/sweep identity flattening (`scenario_filename`, `result_to_dict`, `collate_summary`)
- [x] 32-05-PLAN.md — `run(::MPC)`/`run(::Stochastic)` wrappers, pf de-hardcoding, test migration

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 32-06-PLAN.md — migrate literate docs, scripts, README; `run_and_store` for all strategies

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 32-07-PLAN.md — full-suite certification (31260/0/0/5), docs build, VALIDATION sign-off

**UI hint**: no

### Phase 33: Shared Abstractions — Feeder, Balance, Model Context

**Goal**: Feeder types, balance-closing logic, and `ModelContext` metadata are unified and typed
instead of duplicated five times or carried in an untyped `Dict`.
**Depends on**: Phase 32
**Requirements**: ARCH-03, ARCH-04, ARCH-07
**Success Criteria** (what must be TRUE):

  1. `Feeder` and `MeshedFeeder` share an `AbstractFeeder` supertype, and consumers dispatch on it.
  2. One `close_balance!` helper replaces the five copied balance-closing blocks in
     `welfare_solve`, `mpc_window`, `stochastic_welfare`, `DsoOpt`, and `linear_solve`.

  3. `ModelContext` carries typed fields for its fixed metadata (power-flow variables, objective,
     feeder, device variables); downstream code dispatches on the formulation type instead of
     `haskey(pf_vars, :l)`.
**Plans:** 11/11 plans complete

Plans:
**Wave 1**

- [x] 33-01-PLAN.md — AbstractFeeder supertype, has_reactive/has_branch_current traits, internal shared SOCP body, invalid-pair ArgumentError methods

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 33-02-PLAN.md — Type shared entry points AbstractFeeder, radial-only ADMM ::Feeder with meshed rejection
- [x] 33-03-PLAN.md — close_balance! helper plus pre-migration constraint-order fingerprints
- [x] 33-04-PLAN.md — Typed ModelContext fields, checked accessors, core writers with transient mirror

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 33-05-PLAN.md — Migrate the five balance-closing sites to close_balance!

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 33-06-PLAN.md — Dual-write typed feeder/T at all builders and hand-built test contexts

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 33-07-PLAN.md — Migrate models/admm/devices readers and haskey(:l) gates to typed fields and traits
- [x] 33-08-PLAN.md — Migrate pricing/planning/experiments readers and gates

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 33-09-PLAN.md — Migrate tests, docs/literate, scripts to typed fields

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 33-10-PLAN.md — Remove the transient mirror, add the source-scan grep gate

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 33-11-PLAN.md — Phase gate: detached full suite, docs build, VALIDATION sign-off

**Cross-cutting constraints:**

- Goldens bit-identical

### Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy

**Goal**: `solve_admm` is decomposed and formulation-generic, meshed topology + live reactive
pricing compose end-to-end, and every solve entry point follows one consistent status/exception
policy.
**Depends on**: Phase 33
**Requirements**: ARCH-05, ARCH-06, ARCH-08, ARCH-09
**Success Criteria** (what must be TRUE):

  1. `solve_admm` is split into named phases (build, iterate, ρ adaptation, certification),
     dispatches reactive-mode behaviour instead of repeated `mode == …` branches, and accepts any
     valid `AbstractPowerFlow`.

  2. Meshed topology plus live ADMM reactive pricing runs end-to-end, cross-validated against the
     centralized meshed `:balance_q` dual.

  3. `solve_admm`, `solve_stackelberg!`, `run_nash!`, `run_mpc`, and `run_stochastic` follow one
     documented, consistent status-vs-throw policy.

  4. `mpc_loop`'s exception handlers catch only solver-status and certificate exceptions;
     `MethodError`/`BoundsError` propagate uncaught.
**Plans**: 12 plans

Plans:
**Wave 1**

- [x] 34-01-PLAN.md — typed exception types + `_is_solver_failure`; widen all legacy ErrorException catch sites

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 34-02-PLAN.md — convert SolveFailedError/no-slack throw sites + migrate tests (retry ladder proven)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 34-03-PLAN.md — convert certificate refusals to CertificateError + migrate tests

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 34-04-PLAN.md — convert non-convergence throws to ConvergenceError + migrate tests

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 34-05-PLAN.md — additive `status` vocabulary on the five entry points + DC/reactive pin

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 34-06-PLAN.md — narrow mpc_loop / run_stochastic handlers (ARCH-09) + seam tests

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 34-07-PLAN.md — AdmmState, reactive singleton hooks, `_admm_build`/`_admm_iterate!`/`_adapt_rho!`

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 34-08-PLAN.md — `_admm_certify`, certify hooks, thin orchestrator, grep audit

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 34-09-PLAN.md — `admm_supported`, generic DsoOpt/solve_admm, pair check, LinDist warn-gate, widened supports_pf

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 34-10-PLAN.md — meshed live-reactive ADMM vs centralized cross-validation (measured tolerances)

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 34-11-PLAN.md — Status & exception policy docs, docstring links, meshed literate page (MESH-06 closed)

**Wave 12** *(blocked on Wave 11 completion)*

- [x] 34-12-PLAN.md — phase gate: source gates, detached full suite, docs build, VALIDATION sign-off

**Cross-cutting constraints:**

- Canary unchanged; never re-pinned

### Phase 35: IEEE-8500 Scale After Refactor

**Goal**: Researcher can trust the IEEE-8500 performance/memory characterization now that the
orchestration layer has been refactored.
**Depends on**: Phase 34
**Requirements**: ARCH-10
**Success Criteria** (what must be TRUE):

  1. The final consolidation's `assert_socp_exact!` behaves correctly at IEEE-8500 scale (no
     spurious throw on a converged point).

  2. At least one converged, memory-feasible headline point is measured, or the memory wall is
     re-characterized honestly after the architecture changes.
**Plans**: 5 plans

Plans:
**Wave 1**

- [x] 35-01-PLAN.md — ADMM atol_exact default -> nothing (hybrid floor), tests A/B/negative, hybrid_ratios diagnostic, goldens/canary bit-identical

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 35-02-PLAN.md — harness: --admm-only, --admm-atol, --admm-diagnostic-bypass, per-point wrapper (peak RSS + earlyoom capture), memory profiler

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 35-03-PLAN.md — measurements: memory profile, SC1 bypass diagnostic, headline density 0.1 T=10 post-refactor

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 35-04-PLAN.md — conditional bit-identical memory win, T=24/density 0.25 ladder, memory-wall re-characterization table

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 35-05-PLAN.md — docs section + regenerated page, append-only SCALE-05 status notes, full-suite phase gate

### Phase 36: Code & Export Cleanup

**Goal**: Source comments, dead seams, and exports read cleanly and honestly reflect the
refactored codebase.
**Depends on**: Phase 35 (runs after the refactors so cleanup isn't redone)
**Requirements**: HYG-01, HYG-02, HYG-03, HYG-07
**Success Criteria** (what must be TRUE):

  1. Source comments/docstrings contain no plan/wave/task/decision/review-finding IDs; a CI grep
     guard enforces this; thesis-equation and literature references remain.

  2. The inert SEAM-01 stubs (`operational_oracle`'s ignored `objective_hook`/`horizon_state`, the
     superseded `z` path) and the reactive-mode Bool/Symbol back-compat shim are removed.

  3. The export list is trimmed; generic names (`OFF`, `LIVE`, `CERTIFIED`, `LP`, `QP`, `SOCP`,
     `NLP`, `MILP`, `record!`, `converged`) are namespaced or unexported; the top-module docstring
     describes the module as it now is.

  4. Test fixture files and tags are named after their content, not the planning phase (no
     `fixtures_phaseN`, `:phaseN`).
**Plans**: 22 plans (sequential, one per wave)

Plans:
**Wave 1**

- [x] 36-01-PLAN.md — Verification tooling (AST/thesis/ID classifiers, migrator, multi-spec runner, detached-suite recipe) and baseline

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 36-02-PLAN.md — Remove operational_oracle stub kwargs/z path and DlmpDecomposition aliases

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 36-03-PLAN.md — Remove reactive Bool/Symbol shim; scope ReactiveMode in a module; full suite

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 36-04-PLAN.md — Compat dep, export trim, public block, module docstring, export snapshot test

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 36-05-PLAN.md — Migrate tests to the trimmed exports; full suite

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 36-06-PLAN.md — Migrate scripts/docs, ReactiveMode docs, Breaking changes note, docs build

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 36-07-PLAN.md — Rename fixtures and tags after content; full suite

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 36-08-PLAN.md — FIX08 constant rename; scrub planning/benders.jl and nash.jl

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 36-09-PLAN.md — Scrub remaining src/planning

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 36-10-PLAN.md — Scrub src/models and src/pricing

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 36-11-PLAN.md — Scrub src/admm and src/powerflow

**Wave 12** *(blocked on Wave 11 completion)*

- [x] 36-12-PLAN.md — Scrub src/experiments, core, solver, units, diagnostics, ext

**Wave 13** *(blocked on Wave 12 completion)*

- [x] 36-13-PLAN.md — Scrub src/devices and src/data (incl. ieee8500_impedances.jl); full-suite checkpoint for the src scrub stage

**Wave 14** *(blocked on Wave 13 completion)*

- [x] 36-14-PLAN.md — Scrub src/TSODSO.jl, docs/make.jl, docs/src, README, CI comments

**Wave 15** *(blocked on Wave 14 completion)*

- [ ] 36-15-PLAN.md — Scrub docs/literate

**Wave 16** *(blocked on Wave 15 completion)*

- [ ] 36-16-PLAN.md — Scrub scripts/

**Wave 17** *(blocked on Wave 16 completion)*

- [ ] 36-17-PLAN.md — Scrub tests part 1 (fixtures, runtests, test_a-d)

**Wave 18** *(blocked on Wave 17 completion)*

- [ ] 36-18-PLAN.md — Scrub tests part 2 (test_e-m)

**Wave 19** *(blocked on Wave 18 completion)*

- [ ] 36-19-PLAN.md — Scrub tests part 3 (test_planning_*)

**Wave 20** *(blocked on Wave 19 completion)*

- [ ] 36-20-PLAN.md — Scrub tests part 4 (rest), whole-test verification and full-suite checkpoint

**Wave 21** *(blocked on Wave 20 completion)*

- [ ] 36-21-PLAN.md — CI planning-ID guard (fail-closed) and workflow wiring

**Wave 22** *(blocked on Wave 21 completion)*

- [ ] 36-22-PLAN.md — Final gates: formatter, guard, docs build, full suite, evidence

### Phase 37: Test Infrastructure & Repo Hygiene

**Goal**: CI enforces static analysis and a fast/slow test split, known flakes are resolved
honestly, and the repo's scripts/manifests are tidy.
**Depends on**: Phase 36
**Requirements**: HYG-04, HYG-05, HYG-06, HYG-08
**Success Criteria** (what must be TRUE):

  1. A JET check runs in CI over the package, in report mode, against an agreed baseline.
  2. Tests carry a `:slow` tag; CI runs a fast job on every push and the slow suite in a separate
     or nightly job.

  3. Known flakes (Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM, the stochastic-welfare flake) are
     fixed or quarantined with `@test_broken`/retry-and-report, so a green suite means green.

  4. `scripts/` has an index; one-off and superseded scripts are archived; `pv_boom_report*`
     duplication is merged into shared code; the redundant root `Manifest.toml` is dropped or its
     purpose documented; `.planning/tmp/` is untracked.
**Plans**: TBD

## Progress

**Execution Order:** Phases execute in numeric order within v4.0: 26 → 27 → 28 → 29 → 30 → 31 →
32 → 33 → 34 → 35 → 36 → 37.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|-----------------|--------|-----------|
| 1–9 | v1.0 | 43/43 | Complete | 2026-07-20 |
| 10–14 | v2.0 | 13/13 | Complete | 2026-07-24 |
| 15–18 | v2.1 | 14/14 | Complete | 2026-07-26 |
| 19–25 | v3.0 | 43/40 | Complete (1 gap accepted) | 2026-08-24 |
| 26. Network & Device Model Correctness | v4.0 | 20/20 | Complete    | 2026-09-29 |
| 27. Integer Planning & Pricing Certificate Correctness | v4.0 | 9/9 | Complete    | 2026-09-29 |
| 28. Goldens Re-Derivation & Thesis Reproduction Restatement | v4.0 | 6/5 | Complete    | 2026-09-30 |
| 29. Genuine Bilevel TSO-DSO Variant | v4.0 | 4/4 | Complete    | 2026-10-01 |
| 30. SOCP-in-the-Loop Benders on a Multi-Bus Feeder | v4.0 | 6/6 | Complete    | 2026-10-01 |
| 31. GNE Nash Fixture, Integer N>1 & Planning Docs Refresh | v4.0 | 7/7 | Complete (NOT verified — 2 open critical findings) | 2026-10-02 |
| 32. Declarative Power-Flow & Strategy Dispatch | v4.0 | 7/7 | Complete    | 2026-10-03 |
| 33. Shared Abstractions — Feeder, Balance, Model Context | v4.0 | 11/11 | Complete    | 2026-10-04 |
| 34. ADMM Decomposition, Meshed Reactive & Status/Exception Policy | v4.0 | 12/12 | Complete    | 2026-10-04 |
| 35. IEEE-8500 Scale After Refactor | v4.0 | 5/5 | Complete    | 2026-10-05 |
| 36. Code & Export Cleanup | v4.0 | 14/22 | In Progress|  |
| 37. Test Infrastructure & Repo Hygiene | v4.0 | 0/TBD | Not started | - |

## Deferred / Future-Milestone Notes

- **Large-lattice integer termination criterion** — a rigorous `δ_min` is not derivable (`Q`'s
  local slope is a continuous SOCP dual price with no established Lipschitz bound), so the
  enumeration-backed criterion (Phase 24, v3.0) is tractable only where enumeration is. BILEV-07
  (Phase 31, v4.0) extends integer investment to N>1 Nash but does not resolve this; still open
  past v4.0.

Items formerly listed here — **SCALE-STRETCH**, the Phase-18 `fit_baseline` convergence flake,
the MESH-06 composition advisory, and integer investment beyond single-distributor Stackelberg —
are now in scope for v4.0 as ARCH-10 (Phase 35), FIX-09 (Phase 27), ARCH-06 (Phase 34), and
BILEV-07 (Phase 31) respectively, and are no longer deferred.
