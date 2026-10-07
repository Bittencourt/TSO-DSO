# scripts/ index

Authored analysis, reproduction and tooling scripts. Every tracked file under `scripts/`
(including `lib/`, `archive/` and `data/`) is listed here; a CI guard
(`.github/scripts/check_scripts_index.py`) fails when a file is missing from this index or
when the index names a file that does not exist.

Paths are relative to the repository root. "Test env" means the test directory on the load
path: `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. ...`.

## Scripts

| Script | Purpose | How to run | Outputs | Status |
|--------|---------|------------|---------|--------|
| `benchmark_ieee8500.jl` | IEEE-8500-scale benchmark harness: noise-floor calibration and density sweep | `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500-mv` (see header for the sweep mode) | CSVs under `results/ieee8500_benchmark/` | Maintained; long-running |
| `benders_toy.jl` | Visual step-by-step toy of Benders decomposition (one scalar decision) | `julia --project=. scripts/benders_toy.jl` | Figures (CairoMakie) | Kept; referenced by the documentation |
| `compare_default_stochastic.jl` | Default (deterministic) vs two-stage stochastic solve on the same IEEE-13 network and seed | `julia --project=. scripts/compare_default_stochastic.jl` | Console comparison | Kept; referenced by the documentation |
| `demo_flexibility_plots.jl` | Day-ahead scenario with parametrized flexibility: DADP, 4-way DLMP decomposition, welfare split | `julia --project=. scripts/demo_flexibility_plots.jl` | Figures | Maintained demo |
| `demo_mpc_plots.jl` | Receding-horizon (MPC) closed-loop example with diagnostics and sweeps | `julia --project=. scripts/demo_mpc_plots.jl` | Figures | Maintained demo |
| `flake_rate.jl` | Fresh-process flake-rate harness: runs selected test items N times, each in a new Julia process, recording outcome, solver status labels and Julia version | Test env, `julia --project=. -t2 scripts/flake_rate.jl [--repeats N] [--jobs J] [--targets a,b] [--inprocess N] [--outdir DIR] [--force]`; `--selftest` for the logic test | `results/flake_rate/`; outcome `no_items` (exit 1) when a target selects no test item | Maintained; Julia 1.10+ |
| `jet_baseline.txt` | Committed baseline of normalized JET report signatures (12 entries, a multiset: one line per allowed report) | Data file read and rewritten by `jet_check.jl` | n/a | Maintained; recorded on Julia 1.12.7, the patch the CI JET job pins |
| `jet_check.jl` | JET ratchet: current static-inference reports must equal the baseline as a multiset; UNJUSTIFIED entries fail | Test env, `julia +1.12 --project=. -t2 scripts/jet_check.jl`; `--update` rewrites the baseline (exit 1 if it wrote UNJUSTIFIED entries); `--baseline PATH`; `--selftest` (no JET, any Julia) | Exit code, NEW/FIXED signature list | Maintained; the real check is Julia 1.12 only |
| `profile_ieee8500_memory.jl` | Staged peak-memory profile of one IEEE-8500 point | `SCRIPT=scripts/profile_ieee8500_memory.jl scripts/run_ieee8500_point.sh <label> -- --density 0.1 --t-horizon 10 --stage 2` | `results/ieee8500_benchmark/memory_profile.csv` | Maintained |
| `pv_boom_case_study.jl` | PV-boom narrative case study: PV-penetration sweep (operational layer), SOCP-vs-AC comparison on a high-PV stress fixture (with a diagnostic of why they disagree), and a two-distributor Stackelberg-Nash game (planning layer) | `julia --project=. scripts/pv_boom_case_study.jl` | `data/pv_boom/results.jld2` (gitignored) | Maintained. The planning sub-horizon was re-tuned to hours 11:16 so the planning part passes the exactness gate; see the CALIBRATION note in the file header |
| `pv_boom_report.jl` | Single review-hardened HTML report for the PV-boom case study | `julia --project=. scripts/pv_boom_report.jl [results.jld2 [outdir]]` (run the case study first) | `results/pv_boom/report.html` | Maintained; replaces the earlier two-script layout |
| `lib/pv_boom_common.jl` | Shared helpers for the report (results loading, figures, base64 embedding, HTML fragments) | Not run directly; `include`d by `pv_boom_report.jl` | n/a | Maintained shared code |
| `reduce_ieee123_impedances.jl` | Dependency-free Fortescue reduction of the vendored OpenDSS IEEE-123 data to positive-sequence R1/X1 | `julia scripts/reduce_ieee123_impedances.jl` | `src/data/ieee123_impedances.jl` | Maintained |
| `reduce_ieee8500_impedances.jl` | Same reduction for the 10 vendored IEEE-8500 files, including service transformers | `julia scripts/reduce_ieee8500_impedances.jl` | `src/data/ieee8500_impedances.jl` | Maintained |
| `repro_stability_check.jl` | Directional thesis reproduction stability/sensitivity measurement (Clarabel flake rate at the retuned IEEE-123 point) | `julia --project=. scripts/repro_stability_check.jl` | Committed findings and CSV | Maintained |
| `run_ieee8500_point.sh` | Per-process wrapper for one IEEE-8500 point: records peak RSS, free memory and OOM evidence | `scripts/run_ieee8500_point.sh <label> -- <benchmark args...>` | One row in `results/ieee8500_benchmark/point_resources.csv` | Maintained |
| `run_scenario.jl` | Runnable entry point: edit the `Scenario(...)` call and run it with provenance-stamped storage | `julia --project=. scripts/run_scenario.jl` | `data/sims/` (gitignored) | fails at seed 42 (battery complementarity gate) - under investigation |
| `run_tests_filtered.jl` | Test runner with tag and file filters (avoids the `julia -e` trap) | Test env, `julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> tag:<sym> file:<basename>[,...]`; `--count-sets [--strict]` prints fast/slow/all counts; `--selftest` | Test results / counts | Maintained; fails closed on a spec that selects nothing |
| `socp_applicability_sweep.jl` | Sweep of the (PV x load x Vmax) grid classifying where the SOC relaxation is exact | `julia --project=. scripts/socp_applicability_sweep.jl [highpv]` | Committed findings artifact | Maintained |
| `sweep.jl` | Runnable entry point for a parameter sweep with collated CSV summary | `julia --project=. scripts/sweep.jl` | `results/sweeps/` | Maintained |
| `thesis_case123_repro.jl` | Directional thesis reproduction on real IEEE-123 impedances (DADP vs FIT) | `julia --project=. scripts/thesis_case123_repro.jl` | Figures and findings | Maintained; the +25% magnitude does not reproduce |
| `thesis_caseA.jl` | Thesis Case A reproduction on the modified IEEE-13 feeder | `julia --project=. scripts/thesis_caseA.jl` | Figures and findings | Maintained |

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
