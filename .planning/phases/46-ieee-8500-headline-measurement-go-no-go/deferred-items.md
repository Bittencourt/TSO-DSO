# Deferred items (out of scope, discovered during execution)

## From 46-01 (2026-11-05)

1. **Repo-wide JuliaFormatter 2.10.2 drift (pre-existing).** `format210.jl src ext test docs`
   at 52ad22e rewrites 22 files this plan never touched (incl. `src/admm/*.jl`,
   `src/actors/*`, `src/devices/Behavioural.jl`, `src/pricing/fit.jl`, `src/settlement/equity.jl`,
   `src/core/errors.jl`, `docs/literate/aggregator_actor.jl`, `docs/literate/case_a_magnitude.jl`,
   several `test/test_actor_*.jl`, `test/test_behaviour.jl`, `test/test_electricvehicle.jl`,
   `test/test_case_a_magnitude.jl`, `test/test_population_case_a_scaling.jl`). Formatting
   `src/admm` would break the SC3 diff gate, so only the plan's own files were formatted. A
   dedicated style sweep (outside this phase's SC3 window) should clear it.
2. **`check_script_api.jl` pre-existing failure.** 2 findings in
   `scripts/profile_ieee8500_memory_attribution.jl:115,117` (bare `build_feeder`, `build_price`).
   The file was last changed in the earlier attribution work; nothing under `scripts/` or the
   export list changed in 46-01. Plan 46-02 adds a new script and could qualify these two names
   if it touches that file; otherwise a one-line fix later.

## From the code review (iterations 1 and 2, 2026-11-06)

3. **IEEE-8500 horizon floor only in the script (review iteration-1 IN-07, iteration-2 IN-06).**
   `Scenario(feeder = :ieee8500, T = 5)` constructs, and it fails only later, at
   materialization. The script's guard (`T_MIN_8500 = 9` in `scripts/ieee8500_scenario_point.jl`)
   blocks the case on the measured path. Moving the floor into the inner constructor of
   `src/experiments/Scenario.jl` changes library behaviour, so it was left for a library-level
   change with its own tests.
4. **Test items that include the script run `@quickactivate` (review iteration-1 IN-08,
   iteration-2 IN-06).** Every `include` of `scripts/ieee8500_scenario_point.jl` in
   `test/test_ieee8500_scenario.jl` runs `@quickactivate "TSODSO"`. Skipping it changes which
   `projectdir()` and package environment the included helpers see under `Pkg.test` (the default
   results directory, `git_head()`). The existing precedent (`test_case_a_magnitude.jl`) does the
   same. A fix would make the activation conditional on `PROGRAM_FILE` and route `projectdir()`
   through `pkgdir(TSODSO)`.
