---
phase: 46-ieee-8500-headline-measurement-go-no-go
plan: 01
subsystem: experiments
tags: [scenario, population, ieee8500, selectors, guards, julia]

requires:
  - phase: 39
    provides: harness density rule (sample_density_buses + density_filtered_population) and the 122-model d = 0.1 point
provides:
  - Scenario(feeder = :ieee8500 | :ieee8500_mv) constructs (widened SCENARIO_VALID_FEEDERS)
  - population = :default_10pct (density 0.1 + 4 capacitor aggregators, 8500 feeders only)
  - four ArgumentError construction guards for never-measured 8500 combinations
  - test/test_ieee8500_scenario.jl (5 fast-lane items, no solve)
affects: [46-02 scenario point script, 46-03 docs/NO-GO record, any Scenario consumer]

tech-stack:
  added: []
  patterns:
    - "Density expressed as a population selector (build-full-then-filter), never a Scenario field"
    - "Never-measured selector combinations fail loudly at construction (ArgumentError, 'Scenario: ' prefix)"

key-files:
  created:
    - test/test_ieee8500_scenario.jl
  modified:
    - src/experiments/Scenario.jl
    - src/experiments/materialize.jl
    - test/test_flex_population.jl

key-decisions:
  - ":default_10pct reuses the unchanged :default 8500 builder and filters with the harness rule (LehmerRNG randperm, sorted, capacitors always kept); equal seed gives equal aggregators"
  - "Guards placed after the ADMM/allow_export guard; :default on 8500 stays allowed (density 1.0, documented as measured OOM)"
  - "Style pass limited to the plan's own files: repo-wide formatter drift in 22 untouched files (incl. src/admm) left alone to keep the SC3 gate empty"

patterns-established:
  - "Guard tests assert the specific guard message (needle + not 'unknown'), so they cannot pass vacuously on the generic selector error"

requirements-completed: [SCALE-08]

duration: 23min
completed: 2026-11-05
---

# Phase 46 Plan 01: Scenario widening to IEEE-8500 Summary

**`Scenario` now accepts `:ieee8500`/`:ieee8500_mv` and a `:default_10pct` population (122 / 118 aggregators) that reproduces the benchmark harness's density-0.1 sampling rule at an equal seed. Four `ArgumentError` guards cover the 8500 combinations that were never measured. No field, `==`, `hash` or default path changed.**

## Performance

- **Duration:** ~23 min
- **Started:** 2026-11-05T11:35:12Z
- **Completed:** 2026-11-05T11:58Z
- **Tasks:** 3/3
- **Files modified:** 4 source/test files (plus this summary and deferred-items.md)

## Accomplishments
- `SCENARIO_VALID_FEEDERS = (:ieee13, :ieee123, :ieee8500, :ieee8500_mv)`, plus a private `_SCENARIO_8500_FEEDERS` (not exported, so `test_exports.jl` is unchanged). `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784, :default_10pct)`.
- Guards (all `ArgumentError`, prefixed "Scenario: "):
  - `:default_10pct` on a feeder outside the 8500 family;
  - `:case_a_784` on an 8500 feeder;
  - `pf = :ac` on an 8500 feeder;
  - `MPC` or `Stochastic` on an 8500 feeder.
- Docstrings updated: both constants, a new "IEEE-8500 feeder family" section in `Scenario`, and a `:default_10pct` section in `build_population`. The `build_population` section documents the `sub_seed(s.seed, :population)` divergence from the harness literal.
- `_build_population_core` has a new `:default_10pct` branch. The unknown-selector message now names `:default`, `:default_10pct` and `:case_a_784`. The `:default` body was not edited.
- Measured in tests:
  - `:ieee8500`: 4866 buses, 4865 branches, 122 aggregators, 4 of them capacitors.
  - `:ieee8500_mv`: 2512 buses, 118 aggregators, 4 of them capacitors.
  - Materialization is deterministic and changes with the seed.
  - The selector's buses, `Pdc` and device counts equal the inline harness rule at seed 20260821.

## Task Commits

1. **Task 1 (RED): failing selector/guard tests:** `d56e1a8` (test)
2. **Task 1 (GREEN): widen Scenario + `:default_10pct` branch:** `9957d9e` (feat)
3. **Task 2: materialization, harness-equivalence, default-fence items:** `52ad22e` (test)
4. **Task 3: style pass:** `dfecc76` (style)

## Files Created/Modified
- `src/experiments/Scenario.jl`: widened tuples, private 8500-family constant, four guards, docstrings
- `src/experiments/materialize.jl`: `:default_10pct` branch, unknown-selector message, `build_population` docstring
- `test/test_flex_population.jl`: line 20 tuple assertion follows the widened population tuple
- `test/test_ieee8500_scenario.jl`: 5 untagged `@testitem`s (construction, guards, materialization, harness equivalence, default fence)

## Verification

- Task 1 verify (`test_ieee8500_scenario, test_flex_population, test_strategies`): **577/577 pass**.
- New file alone: 109/109 pass (23.8 s including load).
- Task 2 verify (`test_ieee8500_scenario, test_flex_population, test_strategies, test_experiments, test_exports, test_admm_knifeedge_canary`): **689/689 pass**. Canary welfare is -4823.66604824162, unchanged.
- `grep -nE "solve_admm|run_scenario|_admm_" test/test_ieee8500_scenario.jl`: empty. No IEEE-8500 solve ran anywhere.
- Gates:
  - Planning-ID: 355 (baseline 355).
  - `check_setup_names`: OK (0 unresolved).
  - `check_scripts_index`: OK.
  - `check_content_loss HEAD`: OK, whitespace and commas only.
  - JET ratchet: 20 current / 20 baseline, 0 NEW, 0 FIXED. The run was on 1.12.5; the baseline header records 1.12.7, which only triggers a warning.
  - SC3 diff gate `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt`: empty.
- No `@test_broken` was added. `test/Project.toml` and `test/Manifest.toml` were restored after every `Pkg.test()`.

## Deviations from Plan

### Process deviations

**1. [Rule 3 - Blocking] Style pass scoped to the plan's files, not all of `src ext test docs`**
- **Found during:** Task 3
- **Issue:** `format210.jl src ext test docs` rewrote 25 files. 22 of them are pre-existing drift in files this plan never touched, including `src/admm/*.jl`. Committing those would break the SC3 diff gate, so the plan's `git diff --quiet -- src ext test docs` verify cannot pass on this tree.
- **Fix:** I reverted the formatter output file by file for the untouched files. I kept the formatting of `materialize.jl` and the two test files; `Scenario.jl` was already clean. This follows the earlier "phase-touched files" style-commit precedent. The second pass on those four files is a no-op. Some of the formatted hunks in `materialize.jl` and `test_flex_population.jl` are pre-existing wrapping drift in lines this plan did not otherwise change. They are whitespace-only, as confirmed by `check_content_loss`.
- **Logged:** `deferred-items.md` item 1.

**2. [Rule 3 - Blocking] JET invocation needs the test load path**
- `julia --project=. -t2 scripts/jet_check.jl`, as written in the plan, fails with "Package JET not found". The script's own documented usage, `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" ...`, ran clean.

**3. Test strengthening (not a scope change)**
- Before the guards existed, the guard assertions passed vacuously because the generic "unknown feeder" error fired first. Each guard check now asserts a guard-specific needle and the absence of "unknown". This was done before the RED commit.

**4. TDD note**
- Task 2's items 3-5 pin behaviour that Task 1 had already implemented, so they passed immediately rather than going through a separate RED step. They are characterization and equivalence tests. The RED gate for the plan is `d56e1a8`, which failed with 2 failures and 2 errors before `9957d9e`.

### Pre-existing gate failure (out of scope)
- `check_script_api.jl` exits 1 with 2 findings in `scripts/profile_ieee8500_memory_attribution.jl:115,117` (bare `build_feeder` and `build_price`). Nothing under `scripts/` changed in this plan. Logged in `deferred-items.md` item 2.

## TDD Gate Compliance
- RED `test(46-01)` d56e1a8, then GREEN `feat(46-01)` 9957d9e: present and in order.

## Known Stubs
None.

## Next Phase Readiness
- `Scenario(name=..., feeder=:ieee8500, population=:default_10pct, strategy=ADMM(), T=10)` materializes through `TSODSO._materialize` in about 3 s, which is ready for the measurement script.
- The `Scenario`-path population seed is `sub_seed(s.seed, :population)`, not the harness's 20260821. The T = 10 row must be labelled "same size and structure, different draws".

## Self-Check: PASSED

All 3 key files present; commits d56e1a8, 9957d9e, 52ad22e, dfecc76 exist; no file deletions in 7170b52..HEAD.
