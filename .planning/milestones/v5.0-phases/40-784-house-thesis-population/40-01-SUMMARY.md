---
phase: 40-784-house-thesis-population
plan: 01
subsystem: experiments
tags: [julia, population-construction, ieee13, deterministic-seeding, hash, aggregator-rollup]

# Dependency graph
requires:
  - phase: 39 (executor + scale work)
    provides: build_population selector dispatch, sub_seed hash idiom, generate_profiles
      (StableRNG, bit-reproducible), _load_buses, ADMM one-aggregator-per-load-node guard
provides:
  - ":case_a_784 population selector — 784 per-house-seeded houses rolled into exactly 10
    bus-level Aggregators over the IEEE-13 load buses (solve_admm 1:1-guard compatible)"
  - "_case_a_house_seed — per-house hash((S_pop, :house, bus, house_index)) % typemax(UInt32)
    seed derivation (extends the sub_seed idiom)"
  - "case_a_household_map — pure deterministic house → (bus, aggregator, device_set, pv_group)
    accessor, unexported, derived from the same helpers as the builder"
  - "SCENARIO_VALID_POPULATIONS widened to (:default, :case_a_784)"
  - "test/test_population_case_a.jl — 6 fast @testitems (51 assertions) covering
    POP-01/POP-02/POP-03"
affects: [40-02 scaling ladder, 40-03 agreement measurement, 40-04 calibration docs, phase-41
  settlement groups (pv_group field)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (research Package Legitimacy Audit)
  patterns:
    - "Additive selector branch with bus-level roll-up: per-house devices concatenated,
      Pdc summed, one Aggregator per load bus"
    - "Per-house seeding via a richer hash tuple — never the seed+bus per-bus idiom"
    - "Map/builder single-source-of-truth: the accessor reuses the builder's own helpers"
tech-stack-note: "JuliaFormatter format_docstrings re-flow verified content-safe on new docstrings"

key-files:
  created:
    - test/test_population_case_a.jl
  modified:
    - src/experiments/materialize.jl
    - src/experiments/Scenario.jl

key-decisions:
  - "Per-house magnitude calibration: _case_a_house divides the :default scale triple by
    houses-per-bus (A1) — bus aggregates stay at the validated :default solve regime;
    raw per-house scales would put ~78x the calibrated load through the 6.86 MVA head"
  - "pv_group is a generic field at _CASE_A_PV_FRACTION = 1.0 (A2) — all-PV is the honest
    reading of 'keep :default fractions'; Phase 41 lowers the constant without redesign"
  - "Residue tiebreak (A4): +1 to the first r buses in ascending bus-id order (buses 2-5
    carry 79 houses, buses 6-11 carry 78)"
  - "build_population dispatch restructured with an early-return :case_a_784 branch so the
    :default body stays byte-identical (git-diff criterion) — the plan's wrap-in-if shape
    would have re-indented the golden-bearing body"
  - "Rebuild-reproducibility asserted STRUCTURALLY (device structs carry Vector fields, so
    default == is reference-true); same-bus heterogeneity asserted with a measured entropy
    threshold after pinning showed pv paths (12 daylight hours, 3-state alphabet) collide
    with small probability while all 784 full (pv, demand) draws stay distinct"

patterns-established:
  - "Per-house hash seeding: Int(hash((S_pop, :house, bus, house_index)) % typemax(UInt32))"
  - "Bus-level roll-up shape: Aggregator(bus, 0.90, reduce(vcat, devices), reduce(+, Pdcs))"
  - "Pure accessor pattern: case_a_household_map rebuilds population metadata from the same
    helpers with no Aggregator construction and no profile draws"

requirements-completed: [POP-01, POP-02, POP-03]

# Metrics
duration: 29min
completed: 2026-10-24
---

# Phase 40 Plan 1: `:case_a_784` Thesis Population Selector Summary

**784 per-house hash-seeded houses rolled into 10 bus-level Aggregators behind a new
`:case_a_784` selector — the `:default` path byte-identical (knife-edge canary green:
iters=56, welfare=-4823.66604824162) — plus the pure `case_a_household_map` accessor and a
6-item fast test file (51 assertions).**

## Performance

- **Duration:** 29 min
- **Started:** 2026-10-24T11:47:31Z
- **Completed:** 2026-10-24T12:16:00Z
- **Tasks:** 3/3 (+1 formatter style commit)
- **Files modified:** 2 src + 1 new test file

## Accomplishments

- **POP-01:** `build_population(:case_a_784, feeder, :ieee13, profiles, seed)` builds 784
  houses (3 devices each, 2352 total) distributed over buses 2-11 (79 on buses 2-5, 78 on
  buses 6-11 per `_case_a_house_counts`), rolled up into exactly 10 bus-level
  `Aggregator`s (ascending bus order) — the shape `solve_admm`'s one-aggregator-per-load-node
  guard (admm_phases.jl:67-74) and the centralized price extraction require. Unknown
  selectors and non-`:ieee13` feeders throw `ArgumentError`.
- **POP-02:** every house's profile draw is seeded by
  `_case_a_house_seed(S_pop, bus, house_index) = Int(hash((S_pop, :house, bus, house_index))
  % typemax(UInt32))`; all 784 seeds distinct (Set-size assertion), rebuild reproduces the
  population structurally `==`, and all 784 full `(pv, demand)` draws are distinct.
- **POP-03:** `case_a_household_map(feeder, :ieee13, seed; pv_fraction)` returns 784
  `@NamedTuple` rows (house, bus, aggregator, device_set, pv_group, house_index) in
  bus-major order — pure hash arithmetic, no `Aggregator` construction, no profile draws,
  `==`-deterministic across calls, unexported.
- `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)`; Scenario constructs with the new
  selector and still rejects unknowns (guard message auto-lists the tuple).
- `:default` golden policy protected: git diff across the whole plan removes only the two
  old dispatch-guard lines; knife-edge canary (iters=56, welfare=-4823.66604824162) and
  ieee8500 goldens pass unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rebuild-equality test: default `==` is reference-true on device Vectors**
- **Found during:** Task 3 (first targeted run: 2 failed, 1 errored)
- **Issue:** the plan's "assert `==`" on two independently built populations cannot hold —
  `Thermostatic`/`PVBattery`/`Aggregator` are immutable structs with `Vector` fields
  (`Tout`/`Ppv`/`Pdc`/`devices`), so default `==`/`===` compares those by reference.
- **Fix:** structural field-wise comparison (`isequal` per property at device level;
  element-wise device comparison at aggregator level) — the honest reading of the locked
  "rebuilding reproduces the population exactly" criterion.
- **Files modified:** test/test_population_case_a.jl
- **Commit:** 913b25a

**2. [Rule 1 - Bug] Pairwise-distinct pv assertion tripped by generator entropy, not a bug**
- **Found during:** Task 3 (same run). Diagnosis: bus-2 houses 8 and 13 have DISTINCT seeds
  and DISTINCT demand draws but coincidentally identical pv vectors — the pv vector encodes
  only the 12 daylight hours of a 3-state Markov path (diurnal envelope zeroes the rest), so
  rare same-path collisions are inherent to the generator (measured: 780 distinct pv of 784
  houses; 784/784 distinct full draws; 79/79 distinct seeds on bus 2).
- **Fix:** anti-Pitfall-2 assertion changed to (a) bus-2 PVBattery pv distinct-count ≥ 70 of
  79 (collapses to 1 under the `seed + bus` idiom — the bug signature the item exists to
  catch) plus (b) 784 distinct full `(pv, demand)` draws re-derived from the per-house seeds
  (would be 10 under `seed + bus`). Threshold rationale documented in the test.
- **Files modified:** test/test_population_case_a.jl
- **Commit:** 913b25a

**3. [Rule 3 - Blocking] Scenario keyword constructor: `name` is a REQUIRED keyword**
- **Found during:** Task 3 (`MethodError: TSODSO.Scenario(::String; population)`)
- **Fix:** `Scenario(; name = ..., population = :case_a_784)`.
- **Files modified:** test/test_population_case_a.jl
- **Commit:** 913b25a

### Implementation-Choice Notes (no user decision required)

- **Dispatch shape:** the plan asked for the `build_feeder`-style wrap-in-`if` restructure
  while ALSO requiring the `:default` body textually unchanged (git-diff criterion). The two
  conflict under re-indentation, so the branch is an early-return positive branch
  (`if sym === :case_a_784 ... return` → `elseif sym !== :default throw` → untouched
  `:default` fall-through): positive-branch dispatch and both-selectors error message as
  specified, zero diff inside the golden-bearing body.

## Auth Gates

None.

## Known Stubs

None. Every new symbol is fully wired: `_case_a_house` draws real profiles, the map
derives from the same helpers, and `_CASE_A_PV_FRACTION = 1.0` is the documented locked
decision (not a placeholder — Phase 41 lowers the constant per design).

## Threat Surface Scan

No new surface beyond the plan's `<threat_model>`: no new endpoints, auth paths, file
access, or schema changes; T-40-01 mitigated (`:default` body byte-identical, canary +
goldens re-run green); T-40-02 mitigated (map and builder share `_load_buses`/
`_case_a_house_counts`/`_case_a_house_seed`/`_case_a_pv_group`; consistency asserted).

## Self-Check: PASSED

- FOUND: src/experiments/materialize.jl (`:case_a_784` branch + 4 helpers +
  `case_a_household_map`)
- FOUND: src/experiments/Scenario.jl line 48 `(:default, :case_a_784)`
- FOUND: test/test_population_case_a.jl (315 lines ≥ min_lines 100, 6 items)
- FOUND: commits 403d8bf, f46af22, 913b25a, fb0359a (git log)
- FOUND: canary iters=56, welfare=-4823.66604824162 (test log, post-change)
- FOUND: targeted test file 51/51 pass; zero "soft scope is ambiguous" warnings
