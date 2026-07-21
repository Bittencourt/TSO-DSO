---
phase: 08-experiment-harness-reproducibility
plan: 02
subsystem: infra
tags: [scenario, drwatson, savename, reproducibility, stablerngs, materialize]

# Dependency graph
requires:
  - phase: 08-experiment-harness-reproducibility
    plan: 01
    provides: src/experiments/ include-graph stubs (Scenario.jl, materialize.jl empty seams) + RED @testitem harness
  - phase: 04-convex-branch-flow-correctness-milestone
    provides: ieee13_modified() feeder builder
  - phase: 07-admm-convergence-scale
    provides: ieee123_modified() / ieee123_load_nodes() feeder + load/transit split
  - phase: 03-prosumer-device-library-social-welfare-solve
    provides: generate_profiles, Thermostatic/Deferrable/PVBattery, Aggregator
provides:
  - "Immutable primitive-selector Scenario struct (name/feeder/strategy/seed/T/population/price/allow_export + ADMM knobs), validated at construction, savename-able with ZERO DrWatson.default_allowed overloading"
  - "sub_seed(master, tag) deterministic independent sub-stream derivation (RESEARCH Pitfall 5)"
  - "build_feeder/build_price/build_population deterministic materializers reconstructing Phase 1-7 objects (feeder, λ0, aggregator population) from selectors + seed, feeder-scale-aware residential magnitude scaling"
affects: [08-03, 08-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Base.@kwdef struct with an explicit validating inner constructor (defaults sugar + throw-based V5 guards in one struct, no separate validate! step)"
    - "Primitive-selector Scenario (never a built Feeder/Vector{Aggregator}/λ0 field) so savename/hash/diff fall out for free"
    - "sub_seed(master, tag) = hash((master,tag)) % typemax(UInt32) — independent deterministic sub-streams, never the global RNG"
    - "Feeder-scale-aware residential population scaling (ieee13 @ 100 MVA vs ieee123 @ 1 MVA constants), dispatched by bus count"

key-files:
  created: []
  modified:
    - src/experiments/Scenario.jl
    - src/experiments/materialize.jl

key-decisions:
  - "Base.@kwdef + a hand-written inner constructor (accepting all fields positionally) combine cleanly: @kwdef supplies the keyword-with-defaults outer constructor and forwards to the user's positional inner constructor, so validation lives in exactly one place (verified directly in a REPL before committing to the pattern)."
  - "price/population valid selector sets are ({:mem},) / ({:default},) only — matching the sole build_price/build_population branches materialize.jl implements; any other symbol throws ArgumentError immediately at Scenario construction (fail fast, before run_scenario)."
  - "build_population dispatches residential-magnitude scale constants by feeder bus count (123 -> ieee123 residential scale, else -> ieee13 residential scale) since :default is feeder-agnostic in its symbol but the two shipped feeders need different per-unit-base-appropriate scaling to stay physically sane."
  - "_load_buses uses ieee123_load_nodes() (85 spot-load buses, excluding ~37 transit junctions) when the feeder has 123 buses, else every non-root bus (ieee13's convention) -- so :default population never puts a house on a zero-injection transit node."
  - "_MEM_PRICE_PROFILE_24H / _TEMPERATURE_PROFILE_24H are duplicated from test/fixtures_phase4.jl into src/experiments/materialize.jl (never `using` a test fixture from src/); both cycle via mod1 to support T != 24."

patterns-established:
  - "Validating Base.@kwdef struct: write the struct fields with @kwdef defaults, then an explicit inner constructor with the exact positional signature that throws ArgumentError on invalid selectors/ranges before calling new(...)."

requirements-completed: [EXP-01, INFRA-04]

# Metrics
duration: ~35min
completed: 2026-07-19
---

# Phase 08, Plan 02: Scenario + Deterministic Materialization Summary

**Immutable primitive-selector `Scenario` (savename-able with zero DrWatson overloading, throws on unknown feeder/strategy/price/population) plus `sub_seed`/`build_feeder`/`build_price`/`build_population` deterministically reconstructing the Phase 1-7 feeder/λ₀/aggregator-population from selectors + seed.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-19
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `Scenario` (`src/experiments/Scenario.jl`): a `Base.@kwdef` struct whose 14 fields are ALL primitives (`String`/`Symbol`/`Int`/`Float64`/`Bool`), so `savename(s)` works out of the box — verified two Scenarios differing only in `feeder` produce different `savename` strings (no collision, RESEARCH Pitfall 1). A hand-written inner constructor validates `feeder ∈ {:ieee13,:ieee123}`, `strategy ∈ {:centralized,:admm}`, `price ∈ {:mem}`, `population ∈ {:default}`, and `T/seed/maxiter ≥ 1`, throwing `ArgumentError` on any violation — a Scenario can never silently underdetermine a run (threat T-08-05).
- `sub_seed`/`build_feeder`/`build_price`/`build_population` (`src/experiments/materialize.jl`): `sub_seed(master, tag)` derives independent deterministic sub-streams (RESEARCH Pitfall 5 formula); `build_feeder` dispatches to the validated `ieee13_modified`/`ieee123_modified`; `build_price(:mem, T, profiles)` returns the pinned MEM λ₀ shape cycled to length `T`; `build_population(:default, feeder, profiles, seed)` builds one seeded residential `Aggregator` (Thermostatic + Deferrable + PVBattery) per real load bus — using `ieee123_load_nodes()` to skip the ~37 transit junctions on the 123-bus feeder, and every non-root bus on ieee13 — with feeder-scale-appropriate residential magnitude constants (0.005/0.03 load/PV scale on the 100 MVA ieee13 base; 0.03/0.06/0.05 load/PV/dev scale on the 1 MVA ieee123 base). Each house draws its own `generate_profiles(seed = seed + bus, T)`, so the whole population is deterministic in `seed` with no global-RNG touch (grep-verified clean).

## Task Commits

Each task was committed atomically:

1. **Task 1: Immutable Scenario struct of primitive selectors + validation + savename-ability** - `12fc47e` (feat)
2. **Task 2: Deterministic materialization — sub_seed + build_feeder/build_price/build_population** - `ddd1f25` (feat)

## Files Created/Modified
- `src/experiments/Scenario.jl` — filled the 08-01 comment-only stub: `Scenario` struct + validating constructor + export.
- `src/experiments/materialize.jl` — filled the 08-01 comment-only stub: `sub_seed`, `build_feeder`, `build_price`, `build_population` + private helpers (`_load_buses`, `_default_house`, `_temperature_profile`) + exports.

## Decisions Made
- `Base.@kwdef struct Scenario` with a hand-written inner constructor (all 14 fields positionally) combines the keyword-defaults sugar with construction-time validation in one struct — confirmed this composition works as intended (the `@kwdef`-generated keyword outer constructor forwards to the user's positional inner constructor) with a standalone REPL check before committing to the pattern project-wide.
- `price`/`population` valid-selector sets are deliberately narrow (`{:mem}` / `{:default}` only) — they name exactly the branches `build_price`/`build_population` implement; extending either set is a one-line addition alongside the corresponding new `build_*` branch, never a silent gap.
- `build_population`'s residential-magnitude scale constants are feeder-scale-aware (dispatched by bus count: 123 → ieee123 constants, else → ieee13 constants) rather than one universal constant, because the two shipped feeders sit on drastically different per-unit bases (100 MVA vs 1 MVA) — a single scale would be nonsensical on one of the two.
- The pinned MEM price and temperature-profile arrays are duplicated (not `using`-imported) from the `test/fixtures_phase4.jl`/`fixtures_phase7.jl` test modules into `materialize.jl`, since `src/` must never depend on `test/`; both are documented as the canonical source these fixtures were originally digitized from.

## Deviations from Plan
None - plan executed exactly as written. Both tasks' `<verify><automated>` commands from the PLAN.md pass unmodified.

## Issues Encountered
A full `Pkg.test()` run (extra confidence check beyond the plan's own per-task verify commands)
completed: **1889 pass, 9 fail, 2 broken, 1900 total** (~4m39s). Of the 9 fails, 8 are the expected
RED `test/test_experiments.jl` items for `run_scenario`/`run_sweep`/`run_and_store` (not yet
implemented — correctly still RED, owned by plans 08-03/08-04) and the "EXP-01 scenario strategy
guard" testitem this plan targets PASSES (5/5). The 9th fail is an Aqua "stale dependencies"
check (`CSV`/`DrWatson`/`DataFrames` unused until 08-04's `store.jl`/`sweep.jl` land) — pre-existing
from plan 08-01's dependency addition, not caused by this plan's changes (which touch only
`Scenario.jl`/`materialize.jl`, neither of which imports those packages). Logged (not fixed, per
the executor scope-boundary rule) in
[deferred-items.md](./deferred-items.md). The 2 "broken" items are pre-existing `@test_broken`
markers in Phase 5/7 test files, unrelated to Phase 8.

## Next Phase Readiness
- **08-03** (run): can now implement `ScenarioResult` + `run_scenario(s::Scenario)` strategy dispatch, consuming `build_feeder`/`build_price`/`build_population`/`sub_seed` from this plan and `solve_welfare`/`solve_admm`/`extract_dlmp` from Phases 3-6 — turning the "EXP-01 scenario centralized/admm" RED testitems green.
- **08-04** (store + sweep): unaffected by this plan's scope (file-disjoint); will consume `Scenario`'s `savename`-ability directly for `@tagsave` provenance and `dict_list` sweep expansion.
- No blockers. `Scenario`/`materialize.jl` are dependency-light (no DrWatson import), confirming EXP-01 is testable independent of the storage layer as designed.

---
*Phase: 08-experiment-harness-reproducibility*
*Completed: 2026-07-19*

## Self-Check: PASSED
- FOUND: src/experiments/Scenario.jl
- FOUND: src/experiments/materialize.jl
- FOUND: .planning/phases/08-experiment-harness-reproducibility/08-02-SUMMARY.md
- FOUND commit: 12fc47e
- FOUND commit: ddd1f25
