---
phase: 46-ieee-8500-headline-measurement-go-no-go
plan: 03
subsystem: experiments / measurement scripts / tests
tags: [ieee8500, scenario, go-no-go, tests, scripts-index, julia]

requires:
  - phase: 46-01
    provides: Scenario(feeder = :ieee8500 | :ieee8500_mv), population :default_10pct, test/test_ieee8500_scenario.jl items 1-5
  - phase: 46-02
    provides: scripts/ieee8500_scenario_point.jl (helpers, scenario_admm_phases, --record-nogo)
provides:
  - four new fast-lane test items (9 in the file) that pin the script helpers and the IEEE-13 phase-composition parity with run_scenario
  - scripts/README.md index row for ieee8500_scenario_point.jl (the scripts-index check now passes)
  - results/ieee8500_benchmark/scenario_table.csv with the single committed recorded_no_go row (T = 24, memory_infeasible)
affects: [46-04 orchestrator T = 10 launch (upserts into the same CSV), 46-05 docs section reading scenario_table.csv]

tech-stack:
  added: []
  patterns:
    - "Script helpers pinned by including the script inside each @testitem body (include-safe main guard)"
    - "B2 pinned against an explicit host_total_kb so the test does not depend on the machine's MemTotal"

key-files:
  created:
    - results/ieee8500_benchmark/scenario_table.csv
  modified:
    - test/test_ieee8500_scenario.jl
    - scripts/README.md

key-decisions:
  - "Parity is compared with == (observed differences exactly 0), so no measured tolerance was needed"
  - "The parity item passes time_limit_s = nothing, so the script runs without a wall-clock cap just as the library path does (solve_admm defaults to nothing)"
  - "The README row is placed alphabetically (after flake_rate.jl, before jet_baseline.txt). That is inside the span the plan named: after benders_toy.jl and before the profile_* rows"

requirements-completed: [SCALE-07]

duration: ~15min
completed: 2026-11-05
---

# Phase 46 Plan 03: Script tests, README index and committed NO-GO record Summary

**Four new test items now pin the scenario point script:**
- the NO-GO derivation, by raw kB and binary GiB;
- the MemAvailable pre-flight;
- the keyed upsert and the gap-ratio parse;
- an IEEE-13 phase-composition parity check against `run_scenario`, compared with `==`.

**The script is indexed in `scripts/README.md`. The T = 24 `recorded_no_go` row was produced by `--record-nogo` and committed as `results/ieee8500_benchmark/scenario_table.csv`.**

## Performance

- **Duration:** about 15 min (09:15 to 09:30 -03)
- **Tasks:** 3/3
- **Files:** 1 created, 2 modified

## Accomplishments

- **Test items** (all names contain "ieee8500 scenario"; none solves an IEEE-8500 point):
  - **NO-GO record derived from the committed CSVs.** These values are pinned:
    - `vmhwm_kb == 11_753_716` (11.209 GiB)
    - `p35_maxrss_kb == 12_079_316` (11.520 GiB = B1)
    - `b2_gib_estimate == b1 + 0.12 * 15_765_568 / 1024^2`, which is greater than B1
    - `anchor_iters == 7`, anchor delta 9.2955 GiB, gap ratio 223.68, status `memory_infeasible`
    - `kb_to_gib(1_048_576) == 1.0`
    - the note says "is an estimate, not a bound" and carries the counter-fact
    - a threshold of 12 GiB is refused with an `ArgumentError`
  - **Memory pre-flight.** A synthetic meminfo gives 4324172. `preflight_ok` is false at 8 GiB, true at 0, and correct at the exact 8 GiB boundary. A missing MemAvailable gives -1.
  - **Keyed upsert and gap-ratio parse:**
    - The row schema is checked, with `note` last. An unknown column is refused, and newlines are stripped from the note.
    - In `mktempdir`, a `started` row is replaced by its final row, a different key survives, and an added column is tolerated with `note` still last.
    - `parse_gap_ratio` reads the production phrase (568.9541645248668) and returns `NaN` when the phrase is absent or the message is empty.
  - **IEEE-13 phase-composition parity.** `Scenario(feeder = :ieee13, strategy = ADMM(), T = 10, seed = 3)` is run through `scenario_admm_phases` and through `TSODSO.run_scenario`. They agree on `iters`, `welfare`, `exact_maxgap` and `dadp` with `==`, and the types are Float64 and Matrix{Float64}.
- **Observed parity differences:** exactly 0.0 for iters, welfare, exact_maxgap and dadp. Plan 02 measured this, and the `==` assertions passing here confirm it. `==` is kept, so no tolerance was introduced.
- **README row:** `ieee8500_scenario_point.jl`, covering the measured wrapper line and `--record-nogo`, the outputs, and the status "Maintained; long-running (measured run needs >= 8 GiB MemAvailable)". It contains no planning IDs.
- **Committed NO-GO row** (`--record-nogo`, which reads only the committed CSVs):

| column | value |
|---|---|
| row_kind / feeder / population / T / strategy | recorded_no_go / ieee8500 / harness_density_0.1 / 24 / ADMM |
| status | memory_infeasible |
| vmhwm_kb / vmhwm_gib | 11753716 / 11.209217071533203 |
| p35_maxrss_kb / p35_maxrss_gib | 12079316 / 11.519733428955078 |
| b1_gib (measured) | 11.519733428955078 |
| b2_gib_estimate | 13.323959503173828 (B1 + 12 % of MemTotal 15765568 kB) |
| anchor_delta_gib / anchor_iters / iters | 9.29550552368164 / 7 / 7 |
| gap_ratio | 223.680501440749 |
| threshold_gib | 10.0 |
| julia_version / git_head | 1.12.5 / dc8d859 (HEAD when the row was derived) |

The note:
- labels B2 "an estimate, not a bound";
- cites the earlyoom-killed d = 0.25 row (12636180 kB = 12.051 GiB, rc 143);
- states the counter-fact (the point completed twice on this host by evicting page cache and using swap);
- says that no memory lever is claimed.

## Task Commits

1. **Task 1: script helper and parity test items:** `dc8d859` (test)
2. **Task 2: README row and committed NO-GO record:** `7a847fa` (docs)
3. **Task 3: style pass and gates:** `fcf5570` (style: formatting of `test/test_ieee8500_scenario.jl` only)

## Verification

- **Task 1:** `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl` passed 173/173 (2m07s).
- **Task 2:**
  - `check_scripts_index.py` reports "scripts index complete (48 tracked files checked)".
  - The table has exactly 1 data row, and the CSV `@assert` (row_kind, status, T, vmhwm_kb, p35_maxrss_kb, B2 > B1 > 11.5, "estimate" in the note) passed.
- **Task 3 gates:**
  - **Formatter:** the second pass on the touched file changed nothing.
  - **Content loss:** `check_content_loss.py HEAD` was OK before the style commit and OK again afterwards against `HEAD~1`.
  - **Planning-ID:** 355 hits, the same as the 355 baseline.
  - **Scripts index:** passes.
  - **Script-API lint:** the tree-wide run reports 2 findings, both pre-existing at `scripts/profile_ieee8500_memory_attribution.jl:115,117` (deferred item 2). There are no new findings.
  - **JET** (`JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`, `-t2`): 20 current, 20 baseline, 0 NEW, 0 FIXED, on 1.12.5.
  - **SC3 diff gate:** `git diff 7f13ec4..HEAD --stat -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` is empty.
  - **Regression set:** the fast run of `test_ieee8500_scenario.jl`, `test_strategies.jl`, `test_experiments.jl`, `test_flex_population.jl`, `test_admm_knifeedge_canary.jl` and `test_exports.jl` passed 753/753 (3m57s), with the canary unchanged.
- **Threat T-46-03-04 grep:** the 8500-solve grep over code lines of the test file is empty.
- **Not run:** no IEEE-8500 solve, no measured mode, no full suite.

## Deviations from Plan

1. **[Process: FMT rule] The style pass reverted 22 unrelated files.** `format210.jl src ext test docs` again rewrote the 22 untouched files from deferred item 1, `src/admm/*` among them. I reverted each one individually with `git checkout -- <file>`. Only `test/test_ieee8500_scenario.jl` was formatted and committed. Because of that, the plan's literal Task 3 verify, `format210 ... && git diff --quiet -- src ext test docs`, cannot pass on this tree. I ran the second-pass no-op check on the touched file instead.
2. **[Process: Script-API lint] The literal verify step was not satisfied.** The plan's Task 3 chain requires `check_script_api.jl` to succeed. The tree-wide lint exits 1 with `FAIL: 2 finding(s)`, both pre-existing and deferred, so the literal chain stops at that step. I ran the remaining gates individually, and all of them passed. No new finding was added.
3. **[Rule 2: determinism] B2 is pinned against an explicit MemTotal.** The NO-GO test item passes `host_total_kb = 15_765_568` (this host's MemTotal), so the pinned B2 value does not depend on the machine running the test. The committed CSV row used `/proc/meminfo` on this host, which has the same value.
4. **[Plan detail] The README row is placed alphabetically.** It sits after `flake_rate.jl` and before `jet_baseline.txt`, which is within the span the plan named ("after benders_toy.jl, before the profile_* rows"). It is not directly after `benders_toy.jl`, because that would break the alphabetical order.

## TDD Gate Compliance

- **RED:** the items pin behaviour that already exists, since the script was committed by plan 02. They therefore passed on their first run, so there is no failing RED stage. This is expected for a pinning plan: the "feature" was implemented and checked in scratch by plan 02, where the RED stage happened.
- **Commits:** `test(46-03)` dc8d859 is the test commit. No `feat` commit was needed, because no implementation changed.

## Known Stubs

None. In the NO-GO row the per-run columns (sizes, timings, seed) are `missing` by design. That row is a record of earlier runs, not a run of its own (see the plan 02 summary).

## Self-Check: PASSED

- FOUND: test/test_ieee8500_scenario.jl, scripts/README.md, results/ieee8500_benchmark/scenario_table.csv
- FOUND: dc8d859, 7a847fa, fcf5570
- No file deletions in b7688e1..HEAD
