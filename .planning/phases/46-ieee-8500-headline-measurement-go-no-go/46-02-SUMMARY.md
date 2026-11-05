---
phase: 46-ieee-8500-headline-measurement-go-no-go
plan: 02
subsystem: experiments / measurement scripts
tags: [ieee8500, scenario, admm, measurement, memory, go-no-go, julia]

requires:
  - phase: 46-01
    provides: Scenario(feeder = :ieee8500 | :ieee8500_mv), population :default_10pct
provides:
  - scripts/ieee8500_scenario_point.jl (measured mode, --record-nogo, --help)
  - script-level API for the next plan's tests: SCENARIO_TABLE_COLUMNS, scenario_row, upsert_rows!, mem_available_kb, preflight_ok, proc_status_kb, kb_to_gib, parse_gap_ratio, derive_nogo_row, scenario_admm_phases, main
affects: [46-03 tests + README row + committed NO-GO row, 46-04 orchestrator launch, 46-05 docs section]

tech-stack:
  added: []
  patterns:
    - "Phase-composed solve_admm plumbing (materialize/build/iterate/certify) with separate @elapsed timings and no GC between phases"
    - "Expected solver outcomes are status rows; non-TSODSOError exceptions propagate"
    - "started row upserted before heavy work, replaced by the final row under the same key"

key-files:
  created:
    - scripts/ieee8500_scenario_point.jl
  modified: []

key-decisions:
  - "NO-GO row key: row_kind recorded_no_go, feeder ieee8500, population harness_density_0.1 (the record comes from the benchmark-harness path, not the :default_10pct selector), T 24, strategy ADMM"
  - "derive_nogo_row refuses (ArgumentError) to emit memory_infeasible if a measured peak does not exceed the threshold"
  - "materialize_s covers _materialize + build_powerflow + the admm pair guard + reactive-mode resolution; build_s is _admm_build only"
  - "Schema kept exactly as the interface list; raw Sys.maxrss kB and per-phase VmHWM go into the note (maxrss_gib is the only maxrss column)"
  - "ok rows carry gap_ratio = missing: the ADMM certify path does not store the hybrid ratio in ctx.meta"

requirements-completed: []

duration: ~25min
completed: 2026-11-05
---

# Phase 46 Plan 02: IEEE-8500 Scenario point script Summary

**`scripts/ieee8500_scenario_point.jl` runs one `Scenario` point through the ADMM phases (`_materialize`, `_admm_build`, `_admm_iterate!`, `_admm_certify`), timing each one separately. It has a MemAvailable pre-flight gate, writes keyed `started`/final status rows to `scenario_table.csv`, and has a `--record-nogo` mode that derives the T = 24 `memory_infeasible` row from the committed CSVs alone. On IEEE-13 the phase composition matches `run_scenario` exactly (`==`).**

## Performance

- **Duration:** ~25 min (plan start ~11:50Z, last task commit 12:12Z)
- **Tasks:** 3/3 (Task 3 is gates only; it made no commit)
- **Files:** 1 created (835 lines)

## Accomplishments

- **CLI:**
  - Flags: `--feeder`, `--T`, `--seed`, `--run-label`, `--time-limit`, `--min-mem-avail-gib`, `--results-dir` (or env `TSODSO_IEEE8500_RESULTS_DIR`), `--record-nogo`, `--help`.
  - Every flag is validated with an `ArgumentError` that names the flag, before any heavy work. `--T` must be at least 9 on the 8500 feeders. Run labels must match `[A-Za-z0-9._-]+`. Unknown arguments are rejected.
  - `parse_kv_flag`/`has_flag` are copied from the harness, so the script is standalone. It is include-safe through `abspath(PROGRAM_FILE) == @__FILE__`.
- **Pre-flight gate:** reads MemAvailable from `/proc/meminfo` right after validation and before `Scenario` materialization. A refusal writes one `preflight_refused` row and exits 0.
- **Keyed upsert** on `(row_kind, feeder, population, T, strategy)`, with `cols = :union`. Columns are written in `SCENARIO_TABLE_COLUMNS` order, any extra columns next, and `note` last. Newlines are stripped from `note`. CSV.jl handles quoting.
- **`--record-nogo`:** reproduces the committed values from the CSVs:
  - `vmhwm_kb` 11,753,716 = 11.209 GiB;
  - `p35_maxrss_kb` 12,079,316 = 11.520 GiB;
  - B1 = 11.520 GiB (measured bound);
  - B2 = 13.324 GiB, labelled an estimate (B1 + 12 % of MemTotal 15,765,568 kB);
  - anchor delta 9.2955 GiB, 7 iterations, gap ratio 223.68;
  - the earlyoom-killed d = 0.25 row (12,636,180 kB = 12.051 GiB, rc 143).
  
  The note also states the counter-fact (the point completed twice on this host, using cache eviction and swap) and that no lever is claimed. Re-running replaces the row in place (still 1 row).
- **`scenario_admm_phases(s; time_limit_s, sample_mem)`:**
  - Phase order and arguments follow `run(::ADMM)` plus `solve_admm`. There is no `GC.gc()` between phases, and VmHWM is read after each phase.
  - Sizes are read from the models the run already holds.
  - Status mapping:
    - converged and certified → `ok`;
    - `CertificateError` → `refused_certificate`, with `st.residuals.iters` and the ratio parsed before the message is truncated to 400 characters;
    - not converged → `convergence_error`;
    - budget flag → `budget_exceeded`, with certify skipped;
    - any other `TSODSOError` → `error:<Type>`, with a -1 iteration sentinel;
    - anything else is rethrown.
  - `result` is the certified NamedTuple, with `welfare`/`dadp`/`exact_maxgap`/`iters` converted the same way `run(::ADMM)` converts them.

## Task Commits

1. **Task 1: CLI, pre-flight, row schema, keyed upsert, --record-nogo:** `05b303d` (feat)
2. **Task 2: phase-timed Scenario run with status rows and sizes:** `fcd364a` (feat)
3. **Task 3: gates:** no commit (verification only). No style commit: `scripts/` is outside the formatter scope, and the formatter pass on `src ext test docs` changed only files this plan did not touch (see Deviations).

## Verification

- **Task 1 verify:** passed end to end against a scratch results dir (`p46_r1`). Steps:
  - `--help` prints the usage;
  - `--record-nogo` writes a 1-row table, and the CSV assertions on `vmhwm_kb`, `p35_maxrss_kb`, `anchor_iters` and `vmhwm_gib` pass;
  - a second `--record-nogo` still leaves 1 row;
  - `--T 3 --feeder ieee8500` exits nonzero before any work.
- **Task 2 verify:** passed against a scratch results dir (`p46_r2`):
  - **IEEE-13 smoke run** (`--feeder ieee13 --T 10 --seed 3 --min-mem-avail-gib 0 --run-label smoke`) produced status `ok`, 43 iterations, 11 buses, 10 aggregators, DSO 740 variables / 1060 constraints, AgrOpt 1220 / 2250. Timings: materialize 0.16 s, build 14.2 s, solve 18.6 s, certify 1.8 s (cold process, so compilation is included). VmHWM was 1,377,692 kB.
  - **Impossible pre-flight** (`--min-mem-avail-gib 1000000`) wrote `preflight_refused` and exited 0. It replaced the `ok` row because the key is the same.
  - **GC grep:** no `GC.gc` on code lines.
- **Scratch behaviour check** (`red_behaviour.jl` in the scratchpad, not committed): 26/26 pass. It covers:
  - the NO-GO values;
  - `keys(row) == SCENARIO_TABLE_COLUMNS`;
  - `kb_to_gib(1_048_576) == 1.0`;
  - `preflight_ok(4324172, 8) == false`, `(4324172, 0)` and `(9_000_000, 8)` true;
  - `mem_available_kb` on a synthetic meminfo file;
  - `parse_gap_ratio(...568.9541645248668...)` exact, and `NaN` when the ratio is absent;
  - `upsert_rows!` replacing a `started` row, keeping other keys, tolerating a new column and keeping `note` last.
- **Scratch status paths and parity check** (`phase_paths.jl` in the scratchpad, IEEE-13 only):
  - **Parity:** `scenario_admm_phases` vs `TSODSO.run_scenario` on `Scenario(feeder = :ieee13, strategy = ADMM(), T = 10, seed = 3)` gives `iters`, `welfare`, `exact_maxgap` and `dadp` all `==`, with observed differences of exactly 0.0. The next plan can keep `==`.
  - **Wall-clock cap:** `time_limit_s = 1e-6` gives `budget_exceeded`.
  - **Low `maxiter`:** `ADMM(; maxiter = 3)` gives `convergence_error` with iters 3.
- **Gates:**
  - Planning-ID: 355, baseline 355 (the new file was `git add`-ed first).
  - Script-API lint on the new file alone: `OK: 1 files checked`. The tree-wide lint still exits 1, but only on the two findings already logged at `scripts/profile_ieee8500_memory_attribution.jl:115,117`; there are no new findings.
  - JET ratchet (`JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`): 20 current / 20 baseline, 0 NEW, 0 FIXED, on 1.12.5.
  - SC3 diff gate `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt`: empty.
  - `check_content_loss.py HEAD`: OK.
  - `check_scripts_index.py`: fails with "NOT INDEXED: scripts/ieee8500_scenario_point.jl". This is expected; the README row is added by the next plan.
- **Not run:** no IEEE-8500 solve, no full suite, no `Pkg.test()`. No `src/` or `test/` file changed, and the script's test items belong to the next plan.

## Deviations from Plan

### Auto-fixed / added

1. **[Rule 2 - Validation] Unknown arguments are rejected.** A misspelled flag such as `--time-limt` would otherwise fall back silently to the default cap (threat T-46-02-04).
2. **[Rule 2 - Honesty guard] `derive_nogo_row` throws instead of recording.** If either measured peak does not exceed `threshold_gib`, it throws, so the row can never state `memory_infeasible` against the data.
3. **[Mirror of solve_admm] `TSODSO._check_admm_pair!(:solve_admm, feeder, pf)` is called** in the materialize phase, as `solve_admm` does before building. It is cheap and keeps the composition faithful.
4. **[Rule 3 - Verify gate] Docstring reworded.** The `scenario_admm_phases` docstring said "No `GC.gc()` runs", which tripped the verify grep (docstring lines do not start with `#`). It now says "No explicit garbage-collection call runs between phases".
5. **Schema kept exact, extras in the note.** Raw `Sys.maxrss` kB and the per-phase VmHWM values are written into `note`, because the fixed column list has only `maxrss_gib`. The measured-row note also records the wall-clock cap and the certificate message.

### Process

- **TDD:** the RED step was a scratch test in the session scratchpad. It failed because the script did not exist, then went green. It was not committed, because the repo test items for this script are owned by the next plan. So there is no `test(46-02)` commit (see TDD Gate Compliance).
- **FMT rule:** `format210.jl src ext test docs` rewrote the same 22 untouched files already logged as deferred item 1, `src/admm/*` among them. I reverted each one individually with `git checkout -- <file>` to keep the SC3 gate empty. No file this plan touched is in formatter scope, so there was no style commit.

## TDD Gate Compliance

- **RED:** a scratch-only behaviour test, failing at `include` of the missing script; not committed.
- **GREEN:** `feat(46-02)` 05b303d, with 26/26 scratch checks passing.
- **Missing:** a repo `test(...)` RED commit. The plan routes the committed tests (items 6a-c and 7) to the next plan.

## Known Stubs

None. Two points for the next plans:
- `gap_ratio` is `missing` on `ok` rows, because the ADMM certify path does not expose the hybrid ratio.
- The NO-GO row's per-run columns (sizes, timings, `seed`) are `missing` by design: that row is a record built from earlier runs, not a run.

## Notes for the next plans / orchestrator

- **MemAvailable is low right now:** 1.76-2.79 GiB during this plan's runs. The 8 GiB pre-flight would refuse a launch now, so the orchestrator should free the host before plan 04's launch.
- **Smoke timings include compilation.** The 8500 numbers will come from a single cold process too.

## Self-Check: PASSED

- FOUND: scripts/ieee8500_scenario_point.jl
- FOUND: 05b303d, fcd364a
- No file deletions in 0562c54..HEAD
