# scripts/ index

Authored analysis, reproduction and tooling scripts. Every tracked file under `scripts/`
(including `lib/`, `archive/` and `data/`) is listed here; a CI guard
(`.github/scripts/check_scripts_index.py`) fails when a file is missing from this index or
when the index names a file that does not exist.

Paths are relative to the repository root. "Test env" means the test directory on the load
path: `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. ...`. "Figure env" means the
docs environment stacked in front of the package, because CairoMakie is only a weak dependency
of the package (the root project lists it under `[weakdeps]` only) and `docs/Project.toml` is the
committed environment that carries it: instantiate it once with
`julia --project=docs -e 'using Pkg; Pkg.instantiate()'`, then run
`JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/<script>.jl` from the repository
root. Plain `julia --project=. ...` fails for these scripts with `Package CairoMakie not
found in current path` unless CairoMakie happens to be in your global `@v1.x` environment;
the explicit load path leaves that environment out, so the command does not depend on it.
`docs/Manifest.toml` is resolved with Julia 1.12.5 (the patch the CI docs job pins).

## Scripts

| Script | Purpose | How to run | Outputs | Status |
|--------|---------|------------|---------|--------|
| `actor_behaviour_sweep.jl` | Phase 44 (ACTOR-04) sweep: IEEE-123 behaviour grid (compliance xi, opt-out share, rebound r, seeds of the opt-out draw; per-device FIT flat-price baseline) plus an IEEE-13 retail-wedge block with efficiency loss dW, centralized cross-check, per-actor settlement ledger totals and the rebound metric; refusals and an impossible dW are verdict rows, no tolerance is loosened | `julia --project=. scripts/actor_behaviour_sweep.jl` (about 20 min) | `results/actor_behaviour/actor_behaviour_sweep.csv` | Maintained; long-running |
| `benchmark_ieee8500.jl` | IEEE-8500-scale benchmark harness: noise-floor calibration and density sweep | `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500-mv` (see header for the sweep mode) | CSVs under `results/ieee8500_benchmark/` | Maintained; long-running |
| `benders_toy.jl` | Visual step-by-step toy of Benders decomposition (one scalar decision) | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/benders_toy.jl` | Figures (CairoMakie) | Kept; referenced by the documentation |
| `case_a_agreement.jl` | POP-04 Case-A centralized-vs-ADMM agreement measurement on the full 784-house `:case_a_784` population: both engines on the SAME 10-aggregator roll-up at the thesis point (T=24, seed 42); observed welfare/price deltas + recommended band constants recorded gate-then-golden (10× the observed delta, floored at solver noise — never pre-loosened); certificate refusals/stalls recorded honestly as status rows (the exactness gate is never touched — a refusal is answered by tightening the SOLVER's `tol_gap`, test_admm.jl:42-50 precedent) | `julia --project=. scripts/case_a_agreement.jl` | `results/case_a_population/agreement.csv` | Maintained; long-running |
| `case_a_magnitude.jl` | REPRO-03/04/05 Phase-42 pre-registered welfare-gain MAGNITUDE measurement: protocol-gated runner (`assert_protocol_registered` refuses to run unless `42-CASE-A-PROTOCOL.md` exists AND is committed; the SHA stamps every row). `--mode headline` runs the pre-registered AGR solver-precision ladder (`AGR_TOL_RUNGS`, stop-on-first-certified, hard stop after the last rung) over `solve_admm` at the frozen registered configuration (`:case_a_784` over `:ieee13`, T=24, λ₀=`:mem`, ρ=`ADMM().ρ` locked) plus the unchanged `fit_baseline` FIT leg (ONE pinned `tol_gap 1e-10` SOLVER retry), then the SIGN-SAFE registered gain (the naive W_DADP/W_FIT ratio is banned — it sign-inverts on negative welfare). `--mode proxy` re-runs the SAME code path on the protocol-pinned fixtures: IEEE-123 `:default` seed 20260719 (the ≈+0.263% restatement point) and IEEE-13 `:default` seed 20260718 (the known FIT INFEASIBLE is an expected honest row). The four `--mode ablation-*` modes are the REPRO-05 OFAT axes (protocol §7, pre-pinned `ABLATION_AXES` Dicts, seed 42 only): `ablation-fit` re-solves ONLY fit_baseline per variant (the seed's certified W_DADP is reused from magnitude.csv — loud error if missing); `ablation-price` re-runs the full ladder per λ₀ scaling; `ablation-population` walks the nested-prefix rungs fresh (no per-rung re-tuning) and reuses the proxy.csv fixture rows and the magnitude.csv headline row (`full_784`/`rung_1.0`) with `status="reused"` provenance-transparent rows; `ablation-devices` re-runs the full ladder per device-mix variant on the script-side rebuild from the SAME `_case_a_house` primitives (map-consistency tripwire + 1:1 bus roll-up guard). `--mode crosscheck` records the centralized `solve_welfare` cross-check bound at the certified seed-42 point (on a `CertificateError`: the ONE sanctioned `tol_gap 1e-10` SOCP tightening — `centralized_optimizer` names the path; the certified W_DADP is reused from magnitude.csv and the certified rung's published prices are re-fetched for the DADP-vs-λ₀ price lens). `--mode lenses` runs the four-leg `compare_tariffs` settlement at the certified point (engine=:admm at the certified rung's `agr_optimizer`, per-house rebuild + map rows) into `lens_summary.csv` — dadp/flat/tou/fit rows, honest per-leg statuses (the FIT refusal is a recorded outcome), the DSO-surplus sign-flip lens at full scale. Honest status rows (`error:<Type>`, `:budget_exceeded`, `fit_inexact`, `error:ladder_exhausted`, `reused`), per-row `protocol_sha` + provenance, kill-anytime upsert CSVs; one measurement process at a time | `julia --project=. scripts/case_a_magnitude.jl --mode proxy` (minutes-scale; or `--mode headline --seed 42` — long-running; ablations: `--mode ablation-population --variant 1/78` for the smallest rung, `--variant all` = the full axis; cross-check `--mode crosscheck --seed 42` and lenses `--mode lenses --seed 42` — both long-running) | `results/thesis_case_a_magnitude/magnitude.csv`, `results/thesis_case_a_magnitude/proxy.csv`, `results/thesis_case_a_magnitude/ablation.csv`, `results/thesis_case_a_magnitude/crosscheck.csv`, `results/thesis_case_a_magnitude/lens_summary.csv` | Maintained; long-running |
| `case_a_scaling.jl` | POP-05 Case-A scaling measurement on the 784-house `:case_a_784` population: nested-prefix population ladder (ADMM iterations + wall time per rung, no per-rung re-tuning) and full-population threads sweep of the ADMM solve (kwarg-only `parallel = Threads.nthreads() > 1`, fail-loud on 1 thread; honesty policy: a `:budget_exceeded`/killed leg is a recorded row) | `julia --project=. -t 4 scripts/case_a_scaling.jl --mode threads-sweep` (or `--mode ladder` at `-t 1`; driven per-leg by `scripts/run_case_a_scaling.sh`) | `results/case_a_population/scaling_ladder.csv`, `results/case_a_population/threads_sweep.csv` | Maintained; long-running |
| `compare_default_stochastic.jl` | Default (deterministic) vs two-stage stochastic solve on the same IEEE-13 network and seed | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/compare_default_stochastic.jl` | Console comparison | Kept; referenced by the documentation |
| `demo_flexibility_plots.jl` | Day-ahead scenario with parametrized flexibility: DADP, 4-way DLMP decomposition, welfare split | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/demo_flexibility_plots.jl` | Figures | Maintained demo |
| `demo_mpc_plots.jl` | Receding-horizon (MPC) closed-loop example with diagnostics and sweeps | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/demo_mpc_plots.jl` | Figures | Maintained demo |
| `flake_rate.jl` | Fresh-process flake-rate harness: runs selected test items N times, each in a new Julia process, recording outcome, solver status labels and Julia version | Test env, `julia --project=. -t2 scripts/flake_rate.jl [--repeats N] [--jobs J] [--targets a,b] [--inprocess N] [--outdir DIR] [--force]`; `--selftest` for the logic test | `results/flake_rate/`; outcome `no_items` (exit 1) when a target selects no test item | Maintained; Julia 1.10+ |
| `ieee8500_scenario_point.jl` | One IEEE-8500 point run through `Scenario` with separately timed build, iterate and certify phases, a memory pre-flight and status rows; `--record-nogo` derives the go/no-go record from the committed CSVs | `HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>` (`HEAP_SIZE_HINT` makes the wrapper pass julia's `--heap-size-hint=`; julia ignores `JULIA_HEAP_SIZE_HINT`, and the row records the effective hint); `julia --project=. scripts/ieee8500_scenario_point.jl --record-nogo` | `results/ieee8500_benchmark/scenario_table.csv` (and the wrapper's `point_resources.csv` row) | Maintained; long-running (measured run needs >= 8 GiB MemAvailable, read at script start before any package load; `--min-mem-avail-gib`) |
| `jet_baseline.txt` | Committed baseline of normalized JET report signatures (20 entries, a multiset: one line per allowed report) | Data file read and rewritten by `jet_check.jl` | n/a | Maintained; recorded on Julia 1.12.7, the patch the CI JET job pins |
| `jet_check.jl` | JET ratchet: current static-inference reports must equal the baseline as a multiset; UNJUSTIFIED entries fail | Test env, `julia +1.12 --project=. -t2 scripts/jet_check.jl`; `--update` rewrites the baseline (exit 1 if it wrote UNJUSTIFIED entries); `--baseline PATH`; `--selftest` (no JET, any Julia) | Exit code, NEW/FIXED signature list | Maintained; the real check is Julia 1.12 only |
| `profile_ieee8500_memory.jl` | Staged peak-memory profile of one IEEE-8500 point | `SCRIPT=scripts/profile_ieee8500_memory.jl scripts/run_ieee8500_point.sh <label> -- --density 0.1 --t-horizon 10 --stage 2` | `results/ieee8500_benchmark/memory_profile.csv` | Maintained |
| `profile_ieee8500_memory_attribution.jl` | SCALE-06 staged RSS memory ATTRIBUTION of one IEEE-8500 point: splits `solve_admm` memory growth into named components (data/population, DSO build, AgrOpt builds, per-iteration retained, per-hour solver state, certify) reconciled against a full production-path anchor | `julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 10` (see header for the stage map; wrapper: `SCRIPT=scripts/profile_ieee8500_memory_attribution.jl scripts/run_ieee8500_point.sh <label> -- ...`) | `results/ieee8500_benchmark/memory_attribution.csv` | Maintained; long-running |
| `pv_boom_case_study.jl` | PV-boom narrative case study: PV-penetration sweep (operational layer), SOCP-vs-AC comparison on a high-PV stress fixture (with a diagnostic of why they disagree), and a two-distributor Stackelberg-Nash game (planning layer) | `julia --project=. scripts/pv_boom_case_study.jl` | `data/pv_boom/results.jld2` (gitignored) | Maintained. The planning sub-horizon was re-tuned to hours 11:16 so the planning part passes the exactness gate; see the CALIBRATION note in the file header |
| `pv_boom_report.jl` | Single review-hardened HTML report for the PV-boom case study | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/pv_boom_report.jl [results.jld2 [outdir]]` (run the case study first) | `results/pv_boom/report.html` | Maintained; replaces the earlier two-script layout |
| `lib/case_a_common.jl` | Shared Phase-42 case-a-magnitude helpers: the pre-registration protocol guard (`PROTOCOL_PATH`/`protocol_sha`/`assert_protocol_registered` — fail-loud unless `42-CASE-A-PROTOCOL.md` exists AND is committed; the SHA stamps every CSV row), the SIGN-SAFE welfare gain `welfare_gain` (`100·(W_DADP−W_FIT)/\|W_FIT\|` — the naive ratio is banned, it sign-inverts on negative welfare), and the provenance/note stamps (`provenance_row`, `flatten_note`) | Not run directly; `include("scripts/lib/case_a_common.jl")` (shared lib, no standalone entry point) | n/a | Maintained; shared lib (case-a-magnitude runner + structural tests) |
| `lib/pv_boom_common.jl` | Shared helpers for the report (results loading, figures, base64 embedding, HTML fragments) | Not run directly; `include`d by `pv_boom_report.jl` | n/a | Maintained shared code |
| `reduce_ieee123_impedances.jl` | Dependency-free Fortescue reduction of the vendored OpenDSS IEEE-123 data to positive-sequence R1/X1 | `julia scripts/reduce_ieee123_impedances.jl` | `src/data/ieee123_impedances.jl` | Maintained |
| `reduce_ieee8500_impedances.jl` | Same reduction for the 10 vendored IEEE-8500 files, including service transformers | `julia scripts/reduce_ieee8500_impedances.jl` | `src/data/ieee8500_impedances.jl` | Maintained |
| `repro_stability_check.jl` | Directional thesis reproduction stability/sensitivity measurement (Clarabel flake rate at the retuned IEEE-123 point) | `julia --project=. scripts/repro_stability_check.jl` | Committed findings and CSV | Maintained |
| `run_case_a_scaling.sh` | Subprocess driver for the POP-05 Case-A scaling measurement: one `julia -t N` process per leg (serial ladder leg, then threads-sweep legs at -t 1/2/4); nonzero exits propagate — no silent serial fallback; a killed leg is a recorded outcome (persisted CSV rows) | `scripts/run_case_a_scaling.sh [--ladder-only|--sweep-only]` | Rows in `results/case_a_population/scaling_ladder.csv` and `results/case_a_population/threads_sweep.csv` | Maintained; long-running |
| `run_ieee8500_point.sh` | Per-process wrapper for one IEEE-8500 point: records peak RSS, free memory and OOM evidence | `scripts/run_ieee8500_point.sh <label> -- <benchmark args...>`; optional `HEAP_SIZE_HINT=8G` passes julia's `--heap-size-hint=8G` (julia reads no environment variable for the hint) | One row in `results/ieee8500_benchmark/point_resources.csv` | Maintained |
| `run_scenario.jl` | Runnable entry point: edit the `Scenario(...)` call and run it with provenance-stamped storage | `julia --project=. scripts/run_scenario.jl` | `data/sims/` (gitignored) | fails at seed 42 (battery complementarity gate) - under investigation |
| `run_tests_filtered.jl` | Test runner with tag and file filters (avoids the `julia -e` trap) | Test env, `julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> tag:<sym> file:<basename>[,...]`; `--count-sets [--strict]` prints fast/slow/all counts; `--selftest` | Test results / counts | Maintained; fails closed on a spec that selects nothing |
| `socp_highpv_remeasure.jl` | DEV-09 SOCP exactness RE-MEASUREMENT on the certified 3-bus high-PV stress substrate (copied verbatim) with and without optimal-Q `SmartInverterPV` (seeds 20260719-23, pv 0.5 and 1.2); verdicts only via the standard gate (a refusal is a recorded outcome); post-hoc Volt-VAR droop comparator on the fixed dispatch (`ACPowerFlow(; limits = false)` physics), never a convex constraint | `julia --project=. scripts/socp_highpv_remeasure.jl` (about 1 min) | `results/socp_highpv/highpv_exactness.csv` | Maintained |
| `socp_applicability_sweep.jl` | Sweep of the (PV x load x Vmax) grid classifying where the SOC relaxation is exact | `julia --project=. scripts/socp_applicability_sweep.jl [highpv]` | Committed findings artifact | Maintained |
| `sweep.jl` | Runnable entry point for a parameter sweep with collated CSV summary | `julia --project=. scripts/sweep.jl` | `results/sweeps/` | Maintained |
| `tariff_comparison.jl` | SETL-02/05 tariff-comparison measurement: one DADP run per mode settled and re-dispatched per tariff (dadp/flat/tou/fit) on the SAME feeder + population via `compare_tariffs` — welfare, ledger totals, AC feasibility statuses, equity on bills/surplus with pv/bus/tercile breakouts, and rebound; `--mode ieee13-ground` is the fast smoke leg, `--mode case-a-784` the thesis-scale deliverable (thesis constants T=24/seed 42, engine :admm at ρ = ADMM().ρ — no re-tuning; per-house attribution rebuilt from the exact `_case_a_house` primitives in `case_a_household_map` order). Opt-in flexibility-market legs (`--flex-market`): a flat or TOU baseline plus a DSO redispatch on the same feeder, uniform and pay-as-bid payment rules, baseline-inflation β rows, delivery shortfall and AC verdicts, appended to the same table; `--mode ieee123` is the certified IEEE-123 fixture population (welfare solves at tol_gap 3e-9), `--mode ieee123-default` records the default population's DADP exactness refusal, `--record-timeout S` writes a timeout status row without solving (with `--flex-market` on ieee13-ground, a `flex_(run)` row that replaces only the flex rows and keeps the committed base rows). Documented on the docs page "Flexibility Market vs Price Coordination" (`docs/literate/flex_market.jl`) | `julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground` (or `--mode case-a-784`), `... --mode ieee13-ground --flex-market` (about 1.5 min), `... --mode ieee123 --flex-market` (about 5 min; the comparison call measured 215.6 s, of which 126.1 s is the flex clear), `... --mode ieee123-default` (about 1.5 min) | `results/settlement_comparison/tariff_comparison.csv`, `results/settlement_comparison/household_bills.csv`, `results/settlement_comparison/equity_breakouts.csv`, `results/settlement_comparison/rebound_hourly.csv` (flex and IEEE-123 paths) | Maintained; long-running for --mode case-a-784 |
| `td_hybrid_6node_case_study.jl` | 6-node hybrid SDP-SOCP T&D case study backing the convexification paper: baseline self-check against the paper (fails loudly), Ipopt AC-OPF global-optimality check, TSO-DSO ADMM with rho/eps sweeps, congestion and inexact-regime (PV back-feed, exactness copy) experiments | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/td_hybrid_6node_case_study.jl` | `results/td_hybrid_6node/` (CSV/TXT committed, figures gitignored) | Maintained |
| `thesis_case123_repro.jl` | Directional thesis reproduction on real IEEE-123 impedances (DADP vs FIT) | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/thesis_case123_repro.jl` | Figures and findings | Maintained; the +25% magnitude does not reproduce |
| `thesis_caseA.jl` | Thesis Case A reproduction on the modified IEEE-13 feeder | Figure env, `JULIA_LOAD_PATH="docs:.:@stdlib" julia --project=. scripts/thesis_caseA.jl` | Figures and findings | Maintained |

## Archive

Kept for history only; not maintained and skipped by the script API check.

| Script | Reason archived |
|--------|-----------------|
| `archive/reactive_flake_rate.jl` | Uses the pre-ReactiveMode Bool API; superseded by `flake_rate.jl` |
| `archive/pv_boom_report_v1.jl` | Superseded by the merged `pv_boom_report.jl` plus `lib/pv_boom_common.jl` |

## Vendored data

Offline OpenDSS inputs read by the reduction scripts.

| File | Purpose |
|------|---------|
| `data/IEEE123Master.dss`, `data/IEEELineCodes.DSS` | IEEE-123 feeder and line codes |
| `data/ieee8500/Master.dss` | IEEE-8500 master file |
| `data/ieee8500/Lines.dss`, `data/ieee8500/LineCodes2.DSS` | MV/LV lines and line codes |
| `data/ieee8500/Triplex_Lines.DSS`, `data/ieee8500/Triplex_Linecodes.dss` | Secondary triplex lines and codes |
| `data/ieee8500/Transformers.dss`, `data/ieee8500/LoadXfmrCodes.dss` | Service transformers and their codes |
| `data/ieee8500/Loads.dss`, `data/ieee8500/Capacitors.dss`, `data/ieee8500/Regulators.dss` | Loads, capacitors, regulators |

## Manual test: IEEE-8500 harness

`test/test_benchmark_ieee8500.jl` is NOT part of the automated suite: measured wall time is
14m49s with a 2.74 GB peak RSS, over the 10-minute bound for a suite item. Run it by hand:

```
julia --project=. test/test_benchmark_ieee8500.jl
```

Expected pins: `model_vars = 137258`, `model_cons = 274570`, `admm_iters = 1`; the run ends
with "ALL TESTS PASSED".

## Conventions

- `archive/` is skipped by the script API check and is not maintained.
- `lib/` holds shared code that is `include`d by scripts; it is not run directly.
- `data/` holds vendored inputs; reduction scripts are the only readers.
- Any new file under `scripts/` must be added to this index (the CI guard enforces it).

## Running tests selectively

```
# counts of fast / slow / all items
julia -t2 scripts/run_tests_filtered.jl "$PWD" --count-sets

# one test file, with the test directory on the load path
JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_admm.jl

# by tag
JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" tag:slow
```

Whole-suite selection uses `TSODSO_TEST_SET=fast|slow|all` with `Pkg.test()`; see the root
README.
