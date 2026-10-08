# Phase 37 Timings (plan 04): instrumented full run, Julia 1.12.7

Source: one detached run, `TSODSO_TEST_VERBOSE=1 TSODSO_TEST_SET=all`, `julia +1.12 --project=. -t2 -e 'import Pkg; Pkg.test()'`, HEAD 781b543, clean tree, no other Julia process. Log: `.planning/tmp/36/p37-timing.log` (untracked scratch). Wall time 37m03s. Per-item times are the TestItemRunner summary "Time" column (2 worker processes, so file sums are item wall times, not a serial critical path).

## Outcome vs baseline

| | Pass | Error | Broken | Total |
|---|---:|---:|---:|---:|
| 1.12.5 baseline (pre-phase) | 32205 | 0 | 5 | |
| 1.12.7 observed (this run) | 32218 | 1 | 4 | 32223 |

Canary reached: `iters = 56`, `welfare = -4823.666048218671` (golden -4823.66604824162 agrees to about 5e-12 relative, inside the pinned tolerance; the canary item passed). Items selected: 510 in 98 files (506 per `--count-sets` in plan 02 plus the 4 items of `test/test_flake_retry.jl` from plan 03). The "guards" testset also ran and passed.

Deltas (Pass +13, Error +1, Broken -1):
- +16 passes: the 4 `test_flake_retry.jl` items (plan 03, 16 passes).
- +1 pass: the new `guards` testset (zero-selection and unexpected-Broken check, plan 02).
- -4 passes, +1 Error, -1 Broken: the `welfare surplus accounting: +25% FIT ratio golden + non-failing thesis cross-check` item (test/test_pricing_welfare.jl:301) now ERRORs on 1.12.7: `fit_baseline` returns ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT / ALMOST_SOLVED and `assert_solved!` (src/core/status.jl:55) throws `SolveFailedError` at test line 325 (called from src/pricing/fit.jl:515). The passes after that line, and the conditional Broken thesis cross-check, are never reached. (Pass delta is inferred from the arithmetic 32205+16+1-4 = 32218; the per-item pass count of the FIT item on 1.12.5 was not re-measured here.)
- No other failure or error. The only failing item is the known FIT item.

## Broken accounting

Broken items on 1.12.7 (observed): acceptance IEEE-13 congestion SC3 (thesis cross-check), ieee13 ground golden + thesis v9[16] cross-check, planning nash plot (skipped, no CairoMakie), diagnostics plot (skipped, no CairoMakie). On 1.12.5 the FIT item contributes the fifth.

```
BROKEN_1.12.5=5
BROKEN_1.12.7_RAW=4
BROKEN_1.12.7_EXPECTED_POSTGATE=5
```

EXPECTED_POSTGATE = RAW + 1: after the later gate the unreachable cross-check Broken is replaced by exactly one gated Broken for the solve failure. Plans 05, 12, 13 take their Broken numbers from these lines. Expected item counts: all = 510 selected items (506 + 4 flake_retry), 98 files in the summary.

## Rule for :slow

An item is `:slow` iff its file's total is >= 30 s AND the item's own time is >= 5 s, EXCEPT (a) any `:canary` item (test/test_admm_knifeedge_canary.jl, file total 24.6 s, stays fast and is below the file threshold anyway), (b) the Aqua item in test/test_toy_dc.jl (needs committed Project.toml; stays fast), (c) the compile-paying first item of a run, re-assessed against the 1.12.5 figures. For (c): the 1.12.5 baseline runs (p05, p05b) were non-verbose and have no per-item times, so no re-assessment is possible; no item was removed under (c). Per-item times include first-solve compile in each of the 2 workers (Pitfall 2), which can inflate whichever items happened to run first; all 35 selected items are far above 5 s except the smallest few (5.4 to 7.7 s), which are the ones that could be compile-biased.

Result: 35 items in 13 files, 1213.8 s of item time (see 37-slow-items.txt).

## Fast-set estimate

Total item time 2220 s (sum over 2 workers). Removing the 35 slow items (1213.8 s) leaves about 1006.6 s of item time, of which 582.2 s is the Aqua item. Wall time of a fast run is about half the item sum if the 2 workers balance, about 8.4 min, plus compile/load; this fits the roughly 12 min target.

WARNING for the tagging plan: the Aqua item costs 582 s, of which Persistent tasks alone is 552.3 s (9m12s; Aqua precompiles the package in a fresh process). Aqua stays fast by rule (b), so it is about 58% of the fast item time and a single item in one worker; the fast wall time is therefore bounded below by roughly 10 min. Decide whether to keep it, or to run Aqua with `persistent_tasks=false` in the fast set and the full check in the slow set.

## Per-file table (seconds, sorted)

| file | seconds | items |
|---|---:|---:|
| test/test_toy_dc.jl | 582.4 | 2 |
| test/test_acceptance.jl | 237.3 | 2 |
| test/test_ieee123_admm.jl | 208.7 | 3 |
| test/test_experiments.jl | 177.8 | 17 |
| test/test_admm.jl | 143.2 | 5 |
| test/test_planning_certification_bilevel_interior.jl | 92.7 | 3 |
| test/test_strategies.jl | 84.6 | 26 |
| test/test_admm_adaptive.jl | 80.0 | 3 |
| test/test_planning_nash.jl | 79.8 | 21 |
| test/test_planning_certification_integer.jl | 48.4 | 4 |
| test/test_planning_master_integer.jl | 43.3 | 14 |
| test/test_thesis_repro.jl | 41.0 | 2 |
| test/test_planning_nash_integer.jl | 40.6 | 4 |
| test/test_admm_generic_pf.jl | 29.7 | 7 |
| test/test_admm_knifeedge_canary.jl | 24.6 | 1 |
| test/test_planning_alpha_bounds_stackelberg.jl | 23.4 | 4 |
| test/test_planning_inexact_policy.jl | 23.0 | 9 |
| test/test_welfare_solve.jl | 21.2 | 6 |
| test/test_mpc_loop.jl | 18.4 | 11 |
| test/test_planning_goldens.jl | 15.5 | 3 |
| test/test_run_stochastic.jl | 14.1 | 5 |
| test/test_exactness_verdict.jl | 11.5 | 1 |
| test/test_planning_benders_integer.jl | 10.5 | 4 |
| test/test_admm_dualresid.jl | 9.8 | 2 |
| test/test_status_policy.jl | 9.1 | 4 |
| test/test_scenario_pf.jl | 8.0 | 10 |
| test/test_planning_certification.jl | 7.7 | 2 |
| test/test_feeder.jl | 7.3 | 1 |
| test/test_pricing_dlmp.jl | 7.2 | 11 |
| test/test_pricing_welfare.jl | 6.6 | 8 |
| test/test_restricted_branch_flow.jl | 6.5 | 9 |
| test/test_planning_checkpoint.jl | 6.0 | 4 |
| test/test_ieee13.jl | 5.3 | 4 |
| test/test_close_balance.jl | 5.1 | 4 |
| test/test_admm_reactive.jl | 4.5 | 8 |
| test/test_dso.jl | 4.2 | 9 |
| test/test_admm_exactness_default.jl | 4.1 | 5 |
| test/test_planning_feasibility_oracle.jl | 4.0 | 4 |
| test/test_planning_hardening.jl | 3.9 | 4 |
| test/test_admm_meshed.jl | 3.7 | 3 |
| test/test_planning_oracle.jl | 3.6 | 6 |
| test/test_mpc_terminal.jl | 3.4 | 1 |
| test/test_tsodso_errors.jl | 3.3 | 7 |
| test/test_ac_oracle.jl | 3.2 | 5 |
| test/test_mesh_angle_certificate.jl | 2.9 | 2 |
| test/test_economic_direction.jl | 2.8 | 4 |
| test/test_model_context_traits.jl | 2.7 | 6 |
| test/test_stochastic_welfare.jl | 2.6 | 7 |
| test/test_planning_benders.jl | 2.5 | 4 |
| test/test_exactness.jl | 2.5 | 6 |
| test/test_planning_benders_ieee13.jl | 2.5 | 1 |
| test/test_pricing_fit.jl | 2.1 | 10 |
| test/test_planning_certification_bilevel.jl | 1.9 | 1 |
| test/test_fourquadbess.jl | 1.9 | 18 |
| test/test_ieee8500.jl | 1.9 | 10 |
| test/test_fit.jl | 1.8 | 3 |
| test/test_planning_retry.jl | 1.7 | 5 |
| test/test_planning_master.jl | 1.4 | 16 |
| test/test_admm_phases.jl | 1.4 | 6 |
| test/test_planning_bilevel.jl | 1.4 | 7 |
| test/test_stochastic_oos_harness.jl | 1.4 | 5 |
| test/test_thermostatic.jl | 1.2 | 6 |
| test/test_mpc_window.jl | 1.2 | 5 |
| test/test_abstract_feeder.jl | 1.2 | 4 |
| test/test_aggregator.jl | 1.1 | 9 |
| test/test_planning_ieee13_short_fixture.jl | 1.0 | 1 |
| test/test_exports.jl | 1.0 | 1 |
| test/test_flake_retry.jl | 0.9 | 4 |
| test/test_planning_noninteger.jl | 0.9 | 1 |
| test/test_conformance.jl | 0.8 | 2 |
| test/test_linear_solve.jl | 0.7 | 4 |
| test/test_deferrable.jl | 0.7 | 7 |
| test/test_pvbattery.jl | 0.6 | 5 |
| test/test_mpc_trace.jl | 0.5 | 3 |
| test/test_ieee123.jl | 0.5 | 5 |
| test/test_model_context_migration_gate.jl | 0.5 | 3 |
| test/test_planning_trace.jl | 0.4 | 4 |
| test/test_context.jl | 0.4 | 7 |
| test/test_solver_factory_milp.jl | 0.3 | 1 |
| test/test_profiles.jl | 0.3 | 2 |
| test/test_device.jl | 0.3 | 2 |
| test/test_mesh_flow.jl | 0.3 | 1 |
| test/test_planning_coupling.jl | 0.3 | 7 |
| test/test_convex_branch_flow.jl | 0.3 | 8 |
| test/test_agr.jl | 0.3 | 5 |
| test/test_reactive_mode.jl | 0.2 | 4 |
| test/test_ac_powerflow.jl | 0.2 | 4 |
| test/test_oracle.jl | 0.2 | 3 |
| test/test_planning_ac_recheck.jl | 0.2 | 3 |
| test/test_powerflow.jl | 0.2 | 4 |
| test/test_diagnostics_plot.jl | 0.2 | 3 |
| test/test_mesh_feeder.jl | 0.1 | 1 |
| test/test_planning_follower.jl | 0.1 | 6 |
| test/test_dlmp.jl | 0.1 | 2 |
| test/test_perunit.jl | 0.0 | 1 |
| test/test_factory.jl | 0.0 | 1 |
| test/test_topology.jl | 0.0 | 1 |
| test/test_status.jl | 0.0 | 1 |

## Per-item table (files with total >= 30 s)

| file | item | seconds | slow |
|---|---|---:|:-:|
| test/test_toy_dc.jl | quality: Aqua package checks (no stale deps / ambiguities / export issues) | 582.2 |  |
| test/test_toy_dc.jl | toy: rung0 DC single-node solves OPTIMAL and returns objective + dual | 0.2 |  |
| test/test_acceptance.jl | acceptance: IEEE-123 voltage — exact relaxation + DADP + ADMM≈centralized (SC3) | 136.6 | yes |
| test/test_acceptance.jl | acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized (SC3) | 100.6 | yes |
| test/test_ieee123_admm.jl | ieee123 admm: end-to-end converge + DADP cross-validation (ieee123, crossval) | 139.7 | yes |
| test/test_ieee123_admm.jl | ieee13 admm 4q-bess: live reactive dual-ascent supporting evidence, NOT CI-gating (ieee13, 4q) | 50.4 | yes |
| test/test_ieee123_admm.jl | ieee123 admm: voltage-binding margin (ieee123, crossval) | 18.6 | yes |
| test/test_experiments.jl | experiments: seed sensitivity admm | 35.1 | yes |
| test/test_experiments.jl | experiments: mixed-strategy sweep collate | 33.2 | yes |
| test/test_experiments.jl | experiments: same-seed repro admm | 29.8 | yes |
| test/test_experiments.jl | experiments: scenario admm | 17.1 | yes |
| test/test_experiments.jl | experiments: sweep diff-friendly | 16.5 | yes |
| test/test_experiments.jl | experiments: result_to_dict flat primitives | 16.0 | yes |
| test/test_experiments.jl | experiments: run_and_store round-trip | 15.6 | yes |
| test/test_experiments.jl | experiments: sweep | 6.8 | yes |
| test/test_experiments.jl | experiments: scenario centralized | 1.8 |  |
| test/test_experiments.jl | experiments: same-seed repro | 1.7 |  |
| test/test_experiments.jl | experiments: seed sensitivity | 1.5 |  |
| test/test_experiments.jl | experiments: filename identity | 1.3 |  |
| test/test_experiments.jl | experiments: provenance tagsave | 1.0 |  |
| test/test_experiments.jl | experiments: scenario strategy guard | 0.1 |  |
| test/test_experiments.jl | experiments: Scenario copies stoch_probabilities — caller mutation cannot bypass validation | 0.1 |  |
| test/test_experiments.jl | experiments: scenario_filename identifies the probability vector | 0.1 |  |
| test/test_experiments.jl | experiments: over-length filename fallback uses the stable FNV digest | 0.0 |  |
| test/test_admm.jl | admm: cross-validation ieee13 welfare + DADP (crossval, ieee13) | 141.9 | yes |
| test/test_admm.jl | admm: cross-validation 2-bus welfare + DADP sign (crossval) | 0.7 |  |
| test/test_admm.jl | admm: dual-ascent loop converges + fails loud on the cap (loop) | 0.3 |  |
| test/test_admm.jl | admm: build-once subproblems, no per-iteration rebuild (resolve) | 0.2 |  |
| test/test_admm.jl | admm: final published primal certified — active-balance no hidden slack (crossval) | 0.2 |  |
| test/test_planning_certification_bilevel_interior.jl | bilevel certification (interior fixture): production == BilevelJuMP StrongDualityMode == brute-force grid; production != joint; production != z≡0 stub | 63.4 | yes |
| test/test_planning_certification_bilevel_interior.jl | bilevel certification (T=2 interior fixture): shared-x_inv stationarity sum over t; production == BilevelJuMP == brute-force | 15.6 | yes |
| test/test_planning_certification_bilevel_interior.jl | bilevel certification (interior fixture, d_max binds): the embedded network coupling restricts the leader | 13.2 | yes |
| test/test_strategies.jl | strategies: run(st, s) explicit strategy wins | 28.4 | yes |
| test/test_strategies.jl | strategies: ScenarioResult shape ADMM | 27.6 | yes |
| test/test_strategies.jl | strategies: run(Stochastic) common shape | 10.9 | yes |
| test/test_strategies.jl | strategies: run_mpc/run_stochastic fallback to defaults | 5.8 | yes |
| test/test_strategies.jl | strategies: run_and_store round-trip for MPC and Stochastic | 3.9 |  |
| test/test_strategies.jl | strategies: run(st, s) dispatch uniformity | 3.1 |  |
| test/test_strategies.jl | strategies: run(MPC) common shape | 1.8 |  |
| test/test_strategies.jl | strategies: legacy kwargs map identically | 0.8 |  |
| test/test_strategies.jl | strategies: ScenarioResult shape Centralized | 0.7 |  |
| test/test_strategies.jl | strategies: strategy value equality | 0.2 |  |
| test/test_strategies.jl | strategies: foreign and contradictory knobs throw ArgumentError | 0.2 |  |
| test/test_strategies.jl | strategies: Scenario value equality | 0.2 |  |
| test/test_strategies.jl | strategies: MPC/Stochastic reject non-convex pf at construction | 0.2 |  |
| test/test_strategies.jl | strategies: four strategies four filenames | 0.2 |  |
| test/test_strategies.jl | strategies: supports_pf matrix | 0.1 |  |
| test/test_strategies.jl | strategies: unknown strategy symbol, kwarg and feeder throw ArgumentError | 0.1 |  |
| test/test_strategies.jl | strategies: ADMM rejects non-finite knobs | 0.1 |  |
| test/test_strategies.jl | strategies: negative zero is normalized (== implies same hash) | 0.1 |  |
| test/test_strategies.jl | strategies: strategy defaults | 0.0 |  |
| test/test_strategies.jl | strategies: strategy validation | 0.0 |  |
| test/test_strategies.jl | strategies: stochastic probabilities copy | 0.0 |  |
| test/test_strategies.jl | strategies: run is package-owned | 0.0 |  |
| test/test_strategies.jl | strategies: Scenario has no flat strategy fields | 0.0 |  |
| test/test_strategies.jl | strategies: with_strategy re-validates | 0.0 |  |
| test/test_strategies.jl | strategies: run_mpc/run_stochastic re-validate strategy x pf | 0.0 |  |
| test/test_strategies.jl | strategies: post-construction probability mutation is caught at run time | 0.0 |  |
| test/test_admm_adaptive.jl | admm adaptive rho: scale-invariant convergence 2-bus AND ieee13 (adaptive, rho) | 79.9 | yes |
| test/test_admm_adaptive.jl | admm adaptive rho: set_rho! in-place quad-coeff, build-once invariant (adaptive, rho) | 0.0 |  |
| test/test_admm_adaptive.jl | admm transit dso: zero-injection non-load bus accepted (transit, dso) | 0.0 |  |
| test/test_planning_nash.jl | planning nash: interior-cap fixture (x_inv_max=[1.0,1.0]) exposes a genuine GNE continuum — x_inv_spread exceeds a measured floor, z_spread stays near-zero | 21.3 | yes |
| test/test_planning_nash.jl | planning nash: N=3 probe converges (no closed-form hand-check required, N=2 is hand-checkable and N=3 is probe-only) | 11.1 | yes |
| test/test_planning_nash.jl | planning nash: damping ω=0.5 still converges (no cycling on this monotone fixture) | 10.2 | yes |
| test/test_planning_nash.jl | planning nash: N=2 gating probe — 3 seeds x 2 orders all converge, structural 'a converged equilibrium' language | 7.7 | yes |
| test/test_planning_nash.jl | planning nash: z0/x_inv0 seeds genuinely enter the shared game state — distinct seeds produce distinct sweep-1 trajectories and can reach distinct equilibria | 6.0 | yes |
| test/test_planning_nash.jl | planning nash: inexact_policy defaults to :strict and certificates surface relaxation-only best responses | 4.9 |  |
| test/test_planning_nash.jl | planning nash: solve_variational_equilibrium selects the UNIQUE VE on an asymmetric-c_inv fixture — hand-derived split, equal per-player shared multipliers, distinct from the diagonalization's GNE | 4.3 |  |
| test/test_planning_nash.jl | planning nash: solve_variational_equilibrium on the symmetric interior-cap fixture returns A point of the non-unique VE face (a strict subset of the GNE set) — joint solve, shared multiplier 0.5, no-profitable-deviation | 3.7 |  |
| test/test_planning_nash.jl | planning nash: forward and reverse sweep orders agree on the symmetric N=2 fixture (Gauss-Seidel-vs-Jacobi timing regression) | 3.1 |  |
| test/test_planning_nash.jl | planning nash: N=2 Gauss-Seidel converges to the hand-checked congested equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3], capacity binding, continuous-only companion check) | 1.7 |  |
| test/test_planning_nash.jl | planning nash: nested-tolerance guard rejects inner tol >= outer tol | 1.5 |  |
| test/test_planning_nash.jl | planning nash: max_sweeps exhaustion raises loudly, never a silent non-converged return | 0.9 |  |
| test/test_planning_nash.jl | planning nash: solve_stackelberg! follower keyword is additive — existing call sites unchanged | 0.8 |  |
| test/test_planning_nash.jl | planning nash: solve_stackelberg! rejects follower + non-empty follower_kwargs together | 0.8 |  |
| test/test_planning_nash.jl | planning nash: run_nash_probe propagates a non-converging probe run, never swallows it | 0.8 |  |
| test/test_planning_nash.jl | planning nash: intra-sweep write-back timing — distributor 2 reads distributor 1's JUST-updated z_1 within the same sweep, not the previous sweep's value (DIRECT regression) | 0.5 |  |
| test/test_planning_nash.jl | planning nash: plot_nash_convergence core stays plot-free, ext returns a Makie Figure when CairoMakie is loaded (plot, makie, nash) | 0.4 |  |
| test/test_planning_nash.jl | planning nash: NashTrace push!/is_converged/trace_summary round-trip | 0.2 |  |
| test/test_planning_nash.jl | planning nash: run_nash_probe guards reject fewer than 3 seeds or fewer than 2 orders | 0.1 |  |
| test/test_planning_nash.jl | planning nash: NashTrace push! guards reject bad order/negative counts | 0.0 |  |
| test/test_planning_nash.jl | planning nash: solve_variational_equilibrium agrees with the corner-cap control's pinned unique equilibrium — VE and GNE coincide when the equilibrium IS unique | 0.0 |  |
| test/test_planning_certification_integer.jl | planning certification integer: negative-control regression -- a deliberately WRONG known_optimum is rejected, never falsely converges via a stray gap<=tol match | 23.7 | yes |
| test/test_planning_certification_integer.jl | planning certification integer: exhaustive-enumeration certification of the canonical tiny instance (certificates 1+2, no-good visibility, secondary-certificate non-blocker documented) -- FIXED (Q_nu recourse, stall/no-good over-eagerness, MILP feasibility tolerance), see file header | 18.1 | yes |
| test/test_planning_certification_integer.jl | planning certification integer: T>1 joint corner_recourse matches T=2 dense-grid enumeration on a genuinely non-separable PVBattery fixture | 5.4 | yes |
| test/test_planning_certification_integer.jl | planning certification integer: T>1 joint corner_recourse survives the oracle-infeasible double-stall | 1.1 |  |
| test/test_planning_master_integer.jl | planning master_integer: L-validity — L=α_op_lb+α_x_lb bounds the REAL oracle/follower across [0,y_max] | 28.2 | yes |
| test/test_planning_master_integer.jl | planning master_integer: zero-cut first solve is OPTIMAL (MILP analog of the continuous zero-cut solve) | 4.4 |  |
| test/test_planning_master_integer.jl | planning master_integer: add_ll_cut! exhaustive K=4 16x16-corner tightness/slackness | 1.8 |  |
| test/test_planning_master_integer.jl | planning master_integer: _accepted_lb_slack is always 0.0 — an accepted in-slack bound is CLAMPED to the certified minimum, never installed verbatim | 1.7 |  |
| test/test_planning_master_integer.jl | planning master_integer: lattice reachability — all-ones corner reaches y_max*(1-2^-K), never y_max | 1.2 |  |
| test/test_planning_master_integer.jl | planning master_integer: add_ll_cut! enforces its own Q_nu >= L precondition | 1.2 |  |
| test/test_planning_master_integer.jl | planning master_integer: build_master_integer guards (T, K, y_max, c_y) | 1.0 |  |
| test/test_planning_master_integer.jl | planning master_integer: :auto resolves both epigraph bounds via a genuine relaxed solve, matching derive_alpha_op_lb/derive_alpha_x_lb directly | 1.0 |  |
| test/test_planning_master_integer.jl | planning master_integer: build-time rejection of an over-high explicit α_op_lb when bounds_ctx is supplied | 0.8 |  |
| test/test_planning_master_integer.jl | planning master_integer: persistent cut-row growth — reused continuous cuts append rows, never columns | 0.7 |  |
| test/test_planning_master_integer.jl | planning master_integer: add_nogood_cut! forbids exact re-visitation, leaves other corners feasible | 0.3 |  |
| test/test_planning_master_integer.jl | planning master_integer: honest skip for DistributorView-shaped followers (bounds_ctx.follower_kwargs = nothing) | 0.2 |  |
| test/test_planning_master_integer.jl | planning master_integer: :auto requires bounds_ctx | 0.0 |  |
| test/test_planning_master_integer.jl | planning master_integer: an unknown Symbol bound is an ArgumentError, not a MethodError | 0.0 |  |
| test/test_thesis_repro.jl | thesis_repro: IEEE-123 real-impedance DADP-vs-FIT — DSO-surplus sign flip | 39.0 | yes |
| test/test_thesis_repro.jl | thesis_repro: IEEE-13 congestion — DSO-surplus sign-flip qualitative cross-check (secondary, non-gated) | 2.0 |  |
| test/test_planning_nash_integer.jl | planning nash integer: N=2 run_nash! with integer=(;K=4) converges + per-player brute-force certification (no profitable unilateral deviation) | 18.0 | yes |
| test/test_planning_nash_integer.jl | planning nash integer: damped ω=0.5 integer run converges — no false CYCLED error while b is stable and z/x_inv still move (live) | 15.0 | yes |
| test/test_planning_nash_integer.jl | planning nash integer: integer kwarg boundary guards (K must be a positive Integer; α_op_lb :auto or finite, α_x_lb finite; no silently ignored master_kwargs/integer keys, derived α_x_lb) — before any solve call | 7.4 | yes |
| test/test_planning_nash_integer.jl | planning nash integer: cycle predicate keys on the full committed state — fires on genuine recurrences, never on a converging damped history | 0.3 |  |
