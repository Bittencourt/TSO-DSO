# Milestones

## v2.1 Validation & Reproduction (Shipped: 2026-07-26)

**Phases completed:** 4 phases, 14 plans, 27 tasks

**Key accomplishments:**

- ACPowerFlow — a genuinely independent nonconvex AC-OPF peer (true equality l·v==P²+Q² via Ipopt) dispatched through the unchanged solve_welfare, plus recover_voltage_angles validated against a hand-derived 2-bus closed-form phasor
- assert_ac_exact! certifies the SOCP relaxation against the AC oracle per-hour on objective/voltage/branch-flow gaps using the scale-free atol+rtol·magnitude idiom, returning an inspectable Vector{NamedTuple} report and throwing ONLY on a structural T mismatch — never on a genuine numeric gap
- At pv_scale=1.2 the SOC relaxation goes GENUINELY INEXACT over the high-PV afternoon window (voltage pinned at V²max, reverse flow), surfaced by assert_ac_exact! as a positive 10-inexact-hour finding, guarded against a local-optimum artifact by a two-start Ipopt comparison, and documented in a live-executed literate rung page citing Farivar & Low (2013) / Gan et al. (2015)
- Re-confirmed the mu/mu/MU naming-collision grep-audit live against the current tree, pinned three distinct reactive-power identifiers (qag_dso / reactive / mu_q), and scaffolded a 3-item RED @testitem harness (test/test_admm_reactive.jl) pinning the REACT-01/02/03 contract for plans 16-02/16-03 to turn green.
- Promoted the ADMM `DSO-OPT`'s per-load-node reactive draw from a hand-summed `Float64` constant to a genuine, pinned JuMP coupling variable `qag_dso[j,t]`, gated behind a `reactive_consensus::Bool=false` kwarg (default preserves today's behavior byte-for-byte), and added the `assert_no_slack` certificate on `:balance_q` so its dual becomes trustworthy/publishable whenever the flag is on.
- Added `extract_reactive_dlmp` (mirroring `extract_dlmp`'s shape/PF-04 gate exactly) and a new `reactive` field on `decompose_dlmp`'s NamedTuple, reading the dual of the now-certified `:balance_q` (Plan 16-02) as a documented, citable 5th DLMP component that is never summed into the existing 4-term active-price total.
- Measured the Clarabel NUMERICAL_ERROR-class flake rate of `solve_admm` under `reactive_consensus ∈ {false, true}` on IEEE-13 (N=20: 55% false / 15% true) and IEEE-123 (N=20: 5% false / 5% true), and recorded the rho vs rho_q (Open Question 1) finding grounded in Plan 16-02's hard-equality-pinned `qag_dso` mechanism.
- Task 1 — Vendored upstream OpenDSS fixture files
- Does the IEEE-123 case remain voltage-binding once real impedances replace the synthetic uniform R=0.005/X=0.0025?
- Measured (not assumed) that the thesis-mirroring DSO-surplus sign flip holds at the exact Phase-17-retuned IEEE-123 population point but breaks down under any ±2-5% population-scale perturbation, because the SOCP-exactness gate itself throws near that boundary — an honest negative robustness result that Plan 18-02's golden band and Plan 18-03's assumptions page must both carry forward.
- Wrote and green-lit `test/test_thesis_repro.jl`'s primary IEEE-123 real-impedance `@testitem` (5 hard gates: SOCP exactness, DADP DSO-surplus > 0, FIT DSO-surplus < 0, prosumer surplus decrease, and the DSO-surplus magnitude pinned in [0.0, 5.58855710237937] sourced verbatim from Plan 18-01's committed findings) plus a secondary non-gated IEEE-13 qualitative cross-check — full suite gained exactly the 6 new test items with zero new failures.
- Promoted the phase's IEEE-123 real-impedance DADP-vs-FIT reproduction to a live-executed Documenter/Literate page (numbers cross-checked bit-for-bit against Plan 18-01's committed findings: DADP dso=+3.725705, FIT dso=-196.216447) and wrote a consolidated assumptions/reduction page that states plainly, without softening, that the thesis's +25% welfare-ratio magnitude does not transfer to real public data while the DSO-surplus sign flip does — completing ROADMAP Phase 18 success criteria 1-3.

---

## v2.0 Stackelberg-Nash TSO-DSO Planning Game (Shipped: 2026-07-24)

**Phases completed:** 5 phases, 13 plans, 25 tasks

**Key accomplishments:**

- `solve_with_retry!` (4-rung escalating Clarabel-conditioning ladder around `assert_solved!`) and `checkpoint_iteration!`/`resume_from_checkpoint` (JLD2 per-iteration checkpoint, always redoing the highest-numbered iteration) — both proven independently before Phase 11's Benders loop consumes them.
- A build-once `PlanningOracle` subproblem with a genuine JuMP `Parameter`-typed `z[t]` and a named `p_import[t] == z[t]` pin, re-solved via the plan-10-01 retry wrapper, returning the length-T Benders-cut gradient `π` and its duration-weighted `π_s` -- the raw-dual sign convention pinned by a hand-derived toy-case monotonicity invariant on a purpose-built smooth fixture (since the project's own richer 2-bus aggregator has active device bounds that make the redundant dual split ill-conditioned exactly at the unconstrained optimum).
- Genuinely new transmission-reinforcement follower LP returning real HiGHS Farkas/dual-ray certificates on infeasibility, plus a build-once multi-cut Benders master with a documented finite epigraph lower bound — both independently unit-tested ahead of plan 11-02's outer loop.
- `solve_stackelberg!` — a build-once hand-rolled Benders loop wiring the Phase-10 `PlanningOracle`, plan 11-01's `FollowerLP`, and `BendersMaster` into an end-to-end single-distributor Stackelberg equilibrium, converging to a documented UB/LB relative-gap tolerance (1e-6) on the Phase-11 toy fixture, matching a re-derived (corrected) analytic optimum.
- Independent BilevelJuMP MPEC certification (StrongDualityMode + ProductMode, cross-checked against a hand-worked enumeration) empirically CONFIRMS the leader/follower role assignment and coupling-dual sign convention chosen in plans 11-01/11-02 — no code changes required — while documenting, as a permanent regression, that BigMMode+HiGHS cannot solve this instance (a genuine MIQP solver-capability gap, not a bound-tuning issue).
- BendersTrace convergence ledger with a genuine per-iteration retry count (via a new `solve_with_retry!` `attempts_out` keyword) and both retry-gated subproblems' statuses, wired into `solve_stackelberg!`; closes IN-01/IN-02/IN-03/IN-06 from Phase 11's review; three degenerate feasibility-cut edge cases proven not to corrupt the persistent cut store.
- Load-test `@testitem` forcing a genuinely-converging 66-iteration Benders run (T=8 toy fixture) with retry/checkpoint machinery fully active; empirical `solve_with_retry!` escalation rate (0% on this fixture) measured from `BendersTrace.retry_count_trace` and cross-checked against captured `@warn` logs, closing the STATE.md "measure, don't assume" blocker.
- `SharedTransmission` — a build-once N-distributor JuMP model with per-distributor investment ownership and one pooled, genuinely-binding transmission capacity row, validated in isolation via an asymmetric N=2 fixture that discriminates a broken bound-pin.
- `run_nash!` outer Gauss-Seidel diagonalization loop over N distributors' atomic `solve_stackelberg!` best-responses against a shared transmission corridor, with a nested-tolerance guard, a two-level `NashTrace` convergence ledger, and a CairoMakie twin-axis convergence plot — proven convergent on a hand-checked, genuinely congested N=2 fixture (z=[0.6,0.6], x_inv=[0.3,0.3]).
- `run_nash_probe` — the phase's own honesty gate: repeats `run_nash!` across a >=3-seed x >=2-order matrix (>=6 independent runs, each against a fresh `SharedTransmission`), asserts EVERY run converges (a phase-gating regression, never a soft warning), and reports the observed max-pairwise-distance spread via a structurally "a converged equilibrium (never "the equilibrium")" summary string.
- Extracted the N=1 BilevelJuMP-certified Stackelberg equilibrium and N=2 hand-checked Nash equilibrium into a dedicated `PlanningFixtures` goldens module and a gate-then-golden regression file, plus a newly-bounded (not just non-negative) N=2 probe spread check.
- Registry-based `@testitem` builds all four planning-layer subproblem models (oracle, follower, master, shared-transmission) and asserts zero binary/integer variables, backed by a source-scan tripwire so a future new builder can't silently skip the check.
- Task 1 — `docs/src/api.md` Planning Layer section.

---

## v1.0 Operational Transactive-Energy Core (Shipped: 2026-07-20)

**Phases completed:** 9 phases, 43 plans, 83 tasks

**Key accomplishments:**

- TSODSO walking-skeleton package scaffolded with a committed, [compat]-floored (Julia 1.10) Manifest pinned to CLAUDE.md versions, a 9-seam single-ownership include graph of compiling stubs, weakdep-gated Gurobi/Mosek extensions, a 1.10/1.11/1.12 CI matrix, and a healthy red Wave 0 TestItems harness (10 pass / 1 fail / 7 error, as intended).
- Immutable, JuMP-free radial feeder structs whose construction enforces both a tree-topology invariant (sparse incidence + BFS, no Graphs.jl) and per-unit magnitude tripwires, plus a convert-once-at-ingestion per-unit system — driving the perunit/feeder/topology Wave 0 @testitems green (24/24).
- Filled the compute keystone: `select_optimizer(::ProblemClass)` singleton-dispatch factory with Gurobi/Mosek weakdep extensions, the `assert_solved!` fail-loud status choke point, and the `ModelContext` residual registry + `AbstractPowerFlow` contract — driving the factory, status, and context Wave 0 @testitems GREEN.
- solve_toy_dc closes the walking skeleton — a single-node DC solve built via select_optimizer(LP()), routed through the ctx.residuals[:nodal_balance] seam, gated by assert_solved!, returning objective + nodal-balance dual; plus an executable Literate/Documenter reproducibility page.
- Extended Phase-1's `ModelContext` with an indexed per-(bus,t) `Matrix{AffExpr}` residual accumulator and a separate `QuadExpr` welfare accumulator (`add_to_objective!` under `ctx.meta[:objective]`), keeping the affine price-bearing residual strictly separate from the quadratic utility — and wired the full Phase-2 include graph via five comment-only stubs so wave-2/3 plans fill disjoint files without ever re-touching `src/TSODSO.jl`; all 62 tests green with the rung-0 toy_dc regression and Aqua preserved.
- DCPowerFlow (active-only :Rp) and LinDistFlow (loss-less branch flow with squared-voltage v, the thesis-3.43 voltage drop, and :Rp+:Rq balances) as dispatch-selected AbstractPowerFlow subtypes writing only into the shared residual seam.
- AbstractDevice contract plus a network-agnostic Interruptible/elastic load that injects a signed `-p` into the affine `:Rp` residual and accumulates a concave `a·p − (b/2)p²` utility into the QuadExpr welfare objective, with a `b>0` concavity guard.
- StableRNGs 1.0.4 pinned in both main and test envs with all five manifests re-resolved on Julia 1.10/1.11/1.12, six Phase-3 seam stubs wired into the include graph, and a RED @testitem harness + T=24 Phase3Fixtures standing up over a still-green 138-test Phase-2 baseline.
- Pure, JuMP-free first-order Markov generator (`markov_path` + `generate_profiles`) producing bit-for-bit reproducible T=24 inelastic-demand and PV per-unit profiles, seeded via `StableRNGs.LehmerRNG` threaded as an explicit `AbstractRNG`.
- PVBattery (DEV-04): a co-located PV+battery aggregatable device with SOC dynamics, PV-limited charge, and an App. C concave-charge/convex-discharge parametrization that keeps p_ch·p_dch=0 at the optimum with NO binaries — verified numerically on a standalone Clarabel QP solve.
- Closed the phase's vertical slice: an Aggregator rolls thermostatic/deferrable/PV-battery devices into one nodal net P/Q injection + summed utility as the sole residual writer, and solve_welfare assembles the multi-aggregator GLB-CVX welfare over LinDistFlow at T=24 — global-optimum QP, emergent nodal dual, WR-03 reactive-root fix, and a physically-valid (p_ch·p_dch<τ) battery schedule.
- Wired the five Phase-4 source stubs + the `problem_class`→QP() trait into the include graph, confirmed `SOCP()` already routes to Clarabel, and stood up a RED `@testitem` harness (14 clean missing-symbol failures) plus the shared `Phase4Fixtures` module — Phase-3's 470 tests stay green.
- ConvexBranchFlow — the DistFlow SOC relaxation (rotated cone `l·v ≥ P²+Q²`) with the LinDistFlow exactness copy (aux `v̂` + affine V² bounds, thesis 3.43/3.45) — as a drop-in third AbstractPowerFlow subtype interchangeable with DC/LinDistFlow by dispatch alone.
- `ieee13_modified()` ships the modified IEEE 13-node feeder from thesis Table 4.1 as an immutable, radial-validated, per-unit `Feeder` — 11 buses / 10 branches, head branch at 0.0686 pu, interior branches at a 99.0 pu sentinel, node k -> struct index k+1.
- `operational_oracle` exposes the centralized GLB-CVX solve as `(cost, π, dadp, ctx)` — returning the frontier coupling dual `π` (root nodal-balance dual) as a thin, additive wrapper over `solve_welfare` — with the four SEAM-01 planning interfaces (coupling flow `z↔p_ag` + explicit leader/follower role, multi-scenario objective hook, rolling-horizon state, meshed-formulation slot) landed as inert, typed, documented stubs.
- The project's headline correctness gate: `assert_socp_exact!` certifies `max|l·v−(P²+Q²)| < τ` per branch after every SOCP solve and REFUSES prices on failure — and the fix that makes a genuine over-voltage/reverse-flow case exact is a priced frontier export sink, not a formulation change.
- Centralized ConvexBranchFlow SOCP solve on the modified IEEE-13 feeder proven OPTIMAL, PF-04-exact (maxgap 3.25e-8), and Clarabel-vs-Ipopt-consistent (rtol 5.5e-9), with a pinned computed golden (|V9[16]|=1.0436, welfare -4823.16) and a non-failing thesis v9[16]≈1.0493 cross-check (gap 0.0057).
- 1. [Rule 3 - Blocking] SparseAxisArray key access in the `:smax` @testitem
- Trustworthy per-node/hour distribution prices: the DADP read as the dual of the nodal active balance (PF-04-gated, sign-pinned) plus a KKT-derived energy/loss/congestion/voltage split that provably sums to the nodal price to machine precision on IEEE-13 and high-PV.
- `fit_baseline` — the thesis-faithful FIT-OPT (3.24-3.28, no battery, German-FIT prices) aggregated onto a plain voltage-unenforced AC power flow, returning the reproducible FIT social welfare that anchors the +25% headline ratio.
- `welfare_accounting` splits the GLB-CVX welfare into social/DSO/prosumer surplus with a HARD cancelling-transfer identity (social == prosumer + dso == objective_value), and reports the +25% headline as a computed FIT ratio golden with a non-failing thesis-1.25 cross-check.
- Wired the src/admm/ module into the TSODSO include graph, filled the JuMP-free AdmmResiduals ledger, and stood up the 2-bus dual-sign-anchor fixture plus the RED cross-validation/build-once @testitem harness that pins the solve_admm correctness contract — all without regressing the 1065-test Phase-5 baseline.
- Whole-network DSO-OPT SOCP (thesis eq. 3.47) built ONCE by reusing ConvexBranchFlow.contribute! verbatim, with a free-sign priced p_import/q_import frontier, a per-load-node ACTIVE coupling variable pag_dso, the centralized REACTIVE closure (constant draw + balance_q at all buses), and a coefficient-only re-solve (set_objective_coefficient) gated by the PF-04 exactness certificate on convergence.
- 1. [Rule 3 - Blocking] `-λ₀` multiplier warm start (the real slow-convergence bug)
- CairoMakie weakdep + TSODSOMakieExt scaffold, a JuMP-free AdmmResiduals ledger extended with ρ/ε/price traces (plus a retained Phase-6 record! overload that NaN-pads them), and a RED @testitem harness — the single-owner shared-surface foundation that lets Phase-7 Waves 2–4 run file-disjoint.
- Radial, per-unit, JuMP-free `ieee123_modified()` Feeder (123 buses / 122 branches, root at frontier terminal 150) with a deterministic non-contiguous-label relabel map, an 85-load / 37-transit split, and SparseArrays incidence — validated by construction and driving all four IEEE-123 fixture-construction @testitems GREEN.
- Adaptive ρ now mutates the ADMM subproblem penalty geometry in place via the verified 4-arg `set_objective_coefficient` (±0.5ρ, no rebuild), and DSO-OPT admits zero-injection transit buses — the two seams the 07-04 adaptive loop and the 07-05 IEEE-123 scale case require.
- solve_admm now stops on the Boyd z-block dual residual s = ρ·‖Δ(pag_dso)‖₂ with per-unit two-residual tolerances and drives a residual-balancing adaptive ρ (via set_rho!) that converges the 2-bus AND IEEE-13 with one scale-invariant config — the Phase-6 centralized cross-validation stays exact.
- Adaptive-ρ ADMM converges on the voltage-constrained IEEE-123 feeder in ~17 iterations with λ_j → DADP cross-validated against the centralized SOCP (max gap ~0.003 pu), PF-04 exact at the converged point (exact_maxgap ~1e-9), and the ~37 transit buses handled — full suite 0 fail / 0 error.
- DrWatson/CSV/DataFrames hard deps + re-resolved 1.10/1.11/1.12 manifests, two-tier data/results storage, the src/experiments/ include-graph scaffold, and a RED @testitem harness (Phase8Fixtures) that pins the full EXP-01/EXP-02/INFRA-04 contract.
- Immutable primitive-selector `Scenario` (savename-able with zero DrWatson overloading, throws on unknown feeder/strategy/price/population) plus `sub_seed`/`build_feeder`/`build_price`/`build_population` deterministically reconstructing the Phase 1-7 feeder/λ₀/aggregator-population from selectors + seed.
- `run_scenario(s::Scenario) -> ScenarioResult` dispatching :centralized (solve_welfare+extract_dlmp) and :admm (solve_admm) into one normalized node×T result, with the INFRA-04 same-seed bit-for-bit reproducibility gate green.
- `run_and_store` @tagsave's a gitignored per-run JLD2 stamped with git commit + Julia VERSION + seed; `run_sweep`/`collate_summary` turn a `dict_list` parameter sweep into a byte-stable, fixed-column, `:path`-free CSV — completing the Phase-8 experiment harness with two `@quickactivate` runnable scripts.
- Two new Documenter/Literate pages (Rung 1-2 LinDistFlow, Rung 3 SOCP + exactness copy) that call the real `solve_linear`/`solve_welfare` entrypoints and render genuine solved numbers — including the PF-04 `socp_maxgap` exactness certificate — beside the thesis equations they implement (3.31-3.33, 3.39, 3.43, 3.45).
- Two new EXP-03 literate documentation pages (`docs/literate/prosumer_welfare.jl`, `docs/literate/pricing_dlmp.jl`) executing the real device library, GLB-CVX solve, DLMP decomposition, and welfare-accounting entrypoints end-to-end during the Documenter build.
- Consolidated `test/test_acceptance.jl` proving IEEE-13 congestion + IEEE-123 voltage exact-relaxation/DADP/ADMM≈centralized end-to-end, plus a new FIT-vs-DADP regression golden in `test_pricing_fit.jl`.
- Rung-5 ADMM literate page cross-validating `solve_admm` against `solve_welfare` on a real 3-bus scenario, plus `docs/make.jl` fully extended to build all six abstraction-ladder pages with `checkdocs=:exports`, CI-gated `deploydocs`, and a re-resolved `docs/Manifest.toml` that actually renders CairoMakie convergence figures.
- Added a dedicated `docs` GitHub Actions job (single pinned Julia version, explicit docs-env instantiate via julia-buildpkg@v1) that builds the full Documenter+Literate site with CairoMakie figures on every push/PR, and resolved the deploydocs repo-slug checkpoint by keeping the placeholder per researcher decision.

---

## v3.0 Research Extension Rungs — shipped 2026-08-24

**Phases 19–25** (7 phases, 43 plans executed against 41 planned + 2 unplanned gap-closure waves).
Git range `v2.1.1..v3.0`: 453 commits, 291 files, +84,308 / -504. Audit: `gaps_accepted`.
Known deferred items at close: 3 genuinely open (see STATE.md Deferred Items) — SCALE-STRETCH,
Phase-18 `fit_baseline` convergence, and the MESH-06 composition advisory. The 16 quick tasks and
1 verification gap that `audit-open` flagged are documented there as a frontmatter-convention
artifact and an accepted gap respectively, not open work.

Seven research-extension axes, each shipping as a documented rung with **its own** certificate (the
milestone's standing bar was that no new mathematical regime may reuse another's tolerance — verified
clean at audit: `assert_socp_exact!` 1e-4/1e-6, `assert_4q_complementarity!` 1e-4/1e-8,
`assert_restriction_exact!` 5e-4, `certify_angle_recoverable!` 0.01, plus Phase 25's freshly measured
per-fixture noise floors).

- **4Q-BESS + live reactive dual-ascent** (MESH-04/05) — genuine P/Q variables in an apparent-power
  cone; the v2.1 reactive-dual scaffolding promoted to a live converging μ-ascent, gated by a measured
  cross-validation and a liveness regression that proves the mechanism reacts to its input.
- **Overvoltage-capable restricted relaxation** (OVR-01..04) — prices the v2.1 EXACT-04 high-PV
  regime with an AC-certified validity certificate, and ships an honest negative result (OPF-ε)
  beside the OPF-m success. Established the restriction-certificate pattern Phase 23 reuses.
- **MPC / rolling-horizon RTP** (MPC-01..04) — closed-loop receding-horizon solves over stateful
  devices publishing rolling DADPs, benchmarked against perfect foresight. Genuinely reuses Phase
  20's escalation ladder — the milestone's standout real cross-phase wire.
- **Stochastic PV/demand** (STOCH-01..04) — two-stage extensive form over seeded Markov scenarios,
  per-scenario DADPs as the primary price output, never-aggregated per-scenario exactness gate.
- **Meshed networks** (MESH-01/02/03/06) — non-radial SOCP whose angle-recoverability certificate
  exercises BOTH verdicts on one committed 4-bus diamond fixture.
- **Discrete/integer investment** (INT-01..04) — binary-expansion investment with genuine
  Laporte–Louveaux cuts, certified against exhaustive lattice enumeration, PVAL-04 guard scoped
  rather than deleted via a self-verifying per-builder exemption.
- **IEEE-8500 scale benchmark** (SCALE-01..05) — the public balanced load case (full MV + LV, ~4.9k
  buses after positive-sequence collapse) as a committed fixture, and a density sweep that reported
  a memory wall honestly rather than passing the MV-only control fixture's numbers off as the
  headline result.

**Accepted gap:** SCALE-05 — the ~40x headline fixture was OOM-killed at every density; headline-scale
solve time / ADMM iterations / exactness were never measured. Accepted as an honest non-measurement.
The true memory requirement is lower-bounded only (kills at 6.8–9.75 GiB on a shared 15 GiB machine
under ~9 GiB of unrelated swap pressure).

**Methodological finding worth reusing:** Phase 24's per-cut-validity certificate — a *mechanism*
test, not an *outcome* test — caught an invalid Laporte–Louveaux cut that an exhaustive 256-pair
algebra proof had passed cleanly, because that proof validated the formula against a fixed input and
so could not see a defect in what supplied it. Three stacked defects sat underneath; code review
found two more. Separately: an outer criterion claiming *exactness* silently inherits inner solver
slack unless `mip_rel_gap` and `mip_feasibility_tolerance` are both set explicitly.

---
