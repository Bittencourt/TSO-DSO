---
phase: 03-prosumer-device-library-social-welfare-solve
plan: 02
subsystem: data
tags: [markov, stablerngs, reproducibility, profiles, julia]

# Dependency graph
requires:
  - phase: 03-01
    provides: StableRNGs dependency + comment-only profiles.jl / RED test_profiles.jl stubs
provides:
  - Pure, JuMP-free markov_path first-order Markov walk (seeded, reproducible)
  - Seeded generate_profiles producing T=24 inelastic-demand + PV per-unit profiles
  - Row-stochastic / square / range guards throwing ArgumentError
affects: [03-05 welfare solve (consumes demand/PV parameters), aggregator roll-up]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Explicit AbstractRNG threaded through the generator (StableRNGs.LehmerRNG), never the global RNG"
    - "Hand-rolled inverse-CDF categorical draw (no Distributions.jl)"
    - "Loud ArgumentError guards on untrusted matrices/values (throw, never @assert)"

key-files:
  created: []
  modified:
    - src/data/profiles.jl
    - test/test_profiles.jl

key-decisions:
  - "Reached the AbstractRNG supertype via StableRNGs.Random.AbstractRNG rather than importing Random (Random is not a TSODSO dep and Project.toml is out of scope)"
  - "PV output = irradiance state x deterministic diurnal daylight envelope, guaranteeing non-negativity and ~0 nights"
  - "Seed a single LehmerRNG once and thread it through both chains so the whole NamedTuple is deterministic in seed"

patterns-established:
  - "Pattern: pure data-layer generators take an explicit rng argument; reproducibility is the caller's seed contract"
  - "Pattern: default transition matrices + value tables are overridable module consts, validated at call time"

requirements-completed: [DATA-04]

# Metrics
duration: ~20min
completed: 2026-07-18
---

# Phase 3 Plan 2: Seeded Markov Profile Generator Summary

**Pure, JuMP-free first-order Markov generator (`markov_path` + `generate_profiles`) producing bit-for-bit reproducible T=24 inelastic-demand and PV per-unit profiles, seeded via `StableRNGs.LehmerRNG` threaded as an explicit `AbstractRNG`.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-07-18
- **Tasks:** 2 (both TDD: RED → GREEN)
- **Files modified:** 2

## Accomplishments
- `markov_path(P, s0, steps, rng)` — a hand-rolled inverse-CDF categorical walk over a row-stochastic transition matrix (RESEARCH Pattern 4; thesis §2.8), consuming one `rand(rng)` per step, with square / row-stochastic / range guards that throw `ArgumentError` loudly (threat T-03-04).
- `generate_profiles(; seed, T=24)` — seeds a single `StableRNGs.LehmerRNG(seed)` once and threads it through two chains (demand + PV), mapping state paths through per-unit value tables; PV is scaled by a deterministic diurnal daylight envelope so it stays non-negative and ≈ 0 at night (threat T-03-05).
- Reproducibility contract enforced by tests: same seed → `==` vectors bit-for-bit (INFRA-04, threat T-03-03); distinct seeds diverge.
- The `profile` seam is green: 21/21 assertions across two `@testitem`s.

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1: markov_path (RED)** - `dfc682b` (test)
2. **Task 1: markov_path (GREEN)** - `088f195` (feat)
3. **Task 2: generate_profiles (RED)** - `3be67cc` (test)
4. **Task 2: generate_profiles (GREEN)** - `d2f38e5` (feat)

_No REFACTOR commits were needed; the GREEN implementations were already clean._

## Files Created/Modified
- `src/data/profiles.jl` - Filled the comment-only stub with `markov_path` and `generate_profiles` (both exported), default transition matrices/value tables, and the `_pv_diurnal_envelope` helper. Pure data layer — no JuMP / ModelContext / Feeder / Distributions.jl.
- `test/test_profiles.jl` - Extended the RED stub into two `profile` testitems: markov_path (shape, determinism, distinctness, guards) and generate_profiles (length, non-negativity, per-unit band, same-seed `==`, distinct-seed divergence).

## Decisions Made
- **AbstractRNG via `StableRNGs.Random`:** The plan action suggested `import Random`, but `Random` is not a direct dependency of `TSODSO` and `Project.toml` was explicitly out of this executor's scope. `StableRNGs` (a hard dep) re-exposes the stdlib abstract interface, so the signature annotates `rng::StableRNGs.Random.AbstractRNG` — generic over any RNG, with reproducibility guaranteed by the caller seeding a `LehmerRNG`. No namespace-polluting alias const was introduced.
- **PV diurnal envelope:** rather than model PV purely as a raw state value, states map to irradiance levels scaled by a half-sine daylight envelope over the horizon; this guarantees non-negativity and realistic ~0 night output while keeping the peak within the per-unit band (threat T-03-05).

## Deviations from Plan

None functionally — the plan was executed as written. The only adjustment was the `AbstractRNG` sourcing (`StableRNGs.Random.AbstractRNG` instead of `import Random`) to respect the Project.toml scope boundary; this is documented above under Decisions and preserves the interface contract (explicit `AbstractRNG` threaded through `markov_path`).

## Issues Encountered
- **Selective testitem run in a parallel worktree:** the plan's verify command (`@run_package_tests`) requires the test environment (TestItemRunner/StableRNGs), which is not the main project env. Resolved by building an isolated temporary env in scratchpad with `TSODSO` dev-linked to this worktree and stacking it onto `JULIA_LOAD_PATH`, then invoking `TestItemRunner.run_tests(<worktree>; filter=ti->occursin("profile", ti.name))`. This ran only the `profile` seam without touching tracked manifests or the parallel-wave RED stubs.

## Next Phase Readiness
- `generate_profiles` is ready to feed the GLB-CVX welfare solve (plan 03-05) and the aggregator roll-up as reproducible parameter inputs (Assumption A4).
- Note for the orchestrator: `profiles.jl` now genuinely `using`s and references `StableRNGs`, so the post-wave Aqua stale-deps cleanup (StableRNGs-ignore) can be removed for this file.

## Self-Check: PASSED

- Files verified present: `src/data/profiles.jl`, `test/test_profiles.jl`, `03-02-SUMMARY.md`.
- Commits verified in git history: `dfc682b`, `088f195`, `3be67cc`, `d2f38e5`.
- `markov_path` and `generate_profiles` both exported; `profile` seam green (21/21).

---
*Phase: 03-prosumer-device-library-social-welfare-solve*
*Completed: 2026-07-18*
