---
phase: 03-prosumer-device-library-social-welfare-solve
plan: 01
subsystem: infra
tags: [julia, jump, stablerngs, testitems, manifest, reproducibility, seam-stubs]

# Dependency graph
requires:
  - phase: 02-power-flow-device-contract
    provides: "AbstractDevice/Interruptible contract, ModelContext residual seam, LinDistFlow, TestItemRunner harness, versioned Manifests"
provides:
  - "StableRNGs 1.0.4 pinned in BOTH the main project and the test environment (reproducible seeded RNG for DATA-04)"
  - "All version-specific manifests (Manifest-v1.10/1.11/1.12 + plain Manifest) re-resolved on their channels; test/Manifest regenerated (was stale)"
  - "Include graph wired for all 6 Phase-3 seam files (comment-only stubs) in dependency order; package precompiles"
  - "RED @testitem harness for profiles/thermostatic/deferrable/battery/aggregator/welfare + shared T=24 @testmodule Phase3Fixtures"
affects: [03-02-profiles, 03-03-devices, 03-04-pvbattery, 03-05-aggregator-welfare]

# Tech tracking
tech-stack:
  added: [StableRNGs 1.0.4]
  patterns:
    - "Shared-file edits (Project.toml, Manifests, TSODSO include graph) isolated to a single serialized Wave-1 plan"
    - "Comment-only SEAM/OWNER stubs wired into the include graph ahead of implementation; each fills its own exports later"
    - "@testmodule fixture (Phase3Fixtures) consumed by integration @testitems via setup=[...]"

key-files:
  created:
    - src/data/profiles.jl
    - src/devices/Thermostatic.jl
    - src/devices/Deferrable.jl
    - src/devices/PVBattery.jl
    - src/devices/Aggregator.jl
    - src/models/welfare_solve.jl
    - test/fixtures_phase3.jl
    - test/test_profiles.jl
    - test/test_thermostatic.jl
    - test/test_deferrable.jl
    - test/test_pvbattery.jl
    - test/test_aggregator.jl
    - test/test_welfare_solve.jl
  modified:
    - Project.toml
    - test/Project.toml
    - Manifest.toml
    - Manifest-v1.10.toml
    - Manifest-v1.11.toml
    - Manifest-v1.12.toml
    - test/Manifest.toml
    - src/TSODSO.jl
    - test/test_toy_dc.jl

key-decisions:
  - "Regenerated the stale test/Manifest.toml from scratch (it was missing JuMP/MOI and pinned an incompatible OrderedCollections 2.0.1) rather than preserving it"
  - "Added StableRNGs to test/Project.toml as well as the main project, since profile @testitems construct LehmerRNG directly and Pkg.test() activates the test env"
  - "Configured Aqua stale-deps to ignore StableRNGs until plan 03-02 loads it in profiles.jl, keeping the Phase-2 baseline fully green"

patterns-established:
  - "Serialized shared-foundation wave owns all shared-file edits so later waves touch only disjoint new files"
  - "RED seam @testitems assert isdefined(TSODSO, :Symbol) so they fail (not error) until their owning wave turns them green"

requirements-completed: [DATA-04]

# Metrics
duration: ~35min
completed: 2026-07-18
---

# Phase 3 Plan 01: Shared Foundation Summary

**StableRNGs 1.0.4 pinned in both main and test envs with all five manifests re-resolved on Julia 1.10/1.11/1.12, six Phase-3 seam stubs wired into the include graph, and a RED @testitem harness + T=24 Phase3Fixtures standing up over a still-green 138-test Phase-2 baseline.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-18T20:32:15Z
- **Tasks:** 3
- **Files modified:** 22 (9 modified, 13 created)

## Accomplishments
- Added `StableRNGs = "860ef19b-..."` v1.0.4 to the main `Project.toml` `[deps]`+`[compat]` and to `test/Project.toml` `[deps]`; re-resolved `Manifest-v1.10/1.11/1.12.toml`, the plain `Manifest.toml`, and `test/Manifest.toml`. `using StableRNGs; LehmerRNG(1)` resolves on all three channels and in the test env.
- Created six comment-only SEAM/OWNER stubs (profiles, Thermostatic, Deferrable, PVBattery, Aggregator, welfare_solve) and wired them into `src/TSODSO.jl` in dependency order without disturbing existing include lines; `using TSODSO` precompiles.
- Stood up `@testmodule Phase3Fixtures` (3-bus radial feeder + T=24 deterministic Tout/Pdc/Ppv/λ₀) and six RED seam `@testitem`s whose names carry the runner filter substrings. Full suite: **142 passed, 6 failed, 0 errored** — 138 Phase-2 tests green, 6 new seam items RED, runner healthy.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add StableRNGs (main + test) and re-resolve manifests** - `ee1cd5e` (chore)
2. **Task 2: Create Phase-3 stubs and wire the include graph** - `c363816` (feat)
3. **Task 3: RED @testitem harness + T=24 fixture** - `31f08ad` (test)

## Files Created/Modified
- `Project.toml` / `test/Project.toml` - StableRNGs added to deps (+ main compat floor "1.0.4")
- `Manifest.toml`, `Manifest-v1.10/1.11/1.12.toml`, `test/Manifest.toml` - re-resolved; all list StableRNGs 1.0.4
- `src/data/profiles.jl`, `src/devices/{Thermostatic,Deferrable,PVBattery,Aggregator}.jl`, `src/models/welfare_solve.jl` - comment-only SEAM/OWNER stubs
- `src/TSODSO.jl` - six new includes in dependency order
- `test/fixtures_phase3.jl` - `@testmodule Phase3Fixtures` (feeder + T=24 params)
- `test/test_{profiles,thermostatic,deferrable,pvbattery,aggregator,welfare_solve}.jl` - RED seam @testitems
- `test/test_toy_dc.jl` - Aqua stale-deps ignore for StableRNGs (regression fix)

## Decisions Made
- **Regenerated `test/Manifest.toml` from scratch.** The committed one was stale (no JuMP/MOI, incompatible OrderedCollections 2.0.1); `resolve`/`add --preserve` both failed against it. A clean resolve picked OrderedCollections 1.8.2 and produced a complete, consistent manifest — strictly better than the prior state.
- **StableRNGs in the test env too.** The Wave-2 profile @testitems construct `StableRNGs.LehmerRNG(seed)` directly, and `Pkg.test()` activates `test/Project.toml`; without it the full-suite gate would error on load (the plan-checker blocker this plan fixes). Mirrors the existing JuMP-in-test precedent.
- **`release` channel == Julia 1.12.5.** The `1.12` juliaup channel is not installed, but `release` is 1.12.5 and matches the v1.12 manifest header, so it was used for the 1.12 leg.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Regenerated stale test/Manifest.toml instead of resolving it**
- **Found during:** Task 1
- **Issue:** The committed `test/Manifest.toml` had no JuMP/MOI and pinned OrderedCollections 2.0.1; both `Pkg.resolve()` and `Pkg.add(...; preserve=PRESERVE_ALL)` failed with an unsatisfiable MOI/OrderedCollections conflict, blocking the required "test env resolves StableRNGs".
- **Fix:** Deleted the stale `test/Manifest.toml` and did a clean resolve/instantiate on the release channel, producing a complete manifest (OrderedCollections 1.8.2, JuMP 1.30, MOI 1.51, StableRNGs 1.0.4, plus the test-only deps).
- **Files modified:** test/Manifest.toml
- **Verification:** `julia --project=test -e 'import Pkg; Pkg.instantiate(); using StableRNGs'` → "test-env OK".
- **Committed in:** ee1cd5e (Task 1 commit)

**2. [Rule 1 - Bug] Escaped `$` in a fixture docstring (ParseError)**
- **Found during:** Task 3 (first full-suite run)
- **Issue:** The `λ₀` docstring `"...($/MWh-equivalent)..."` was parsed as Julia string interpolation → `ParseError` at fixture include time, which aborted the entire `@run_package_tests` (only 20 assertions ran, package testing errored).
- **Fix:** Escaped the dollar sign (`\$/MWh-equivalent`).
- **Files modified:** test/fixtures_phase3.jl
- **Verification:** Re-ran full suite — no ParseError; all files discovered.
- **Committed in:** 31f08ad (Task 3 commit)

**3. [Rule 1 - Regression] Aqua stale-deps flagged the newly-added StableRNGs**
- **Found during:** Task 3 (full-suite run after fixture fix)
- **Issue:** Adding StableRNGs to the main `Project.toml [deps]` (Task 1) while no `src/` code loads it yet made Aqua's stale-dependency check fail — a previously-green Phase-2 test (`quality: Aqua package checks`) went RED, breaking the 138-test baseline.
- **Fix:** `Aqua.test_all(TSODSO; stale_deps=(ignore=[:StableRNGs],))` with a comment noting plan 03-02 removes the ignore once `profiles.jl` `using`s StableRNGs.
- **Files modified:** test/test_toy_dc.jl
- **Verification:** Full suite → 142 passed / 6 failed; the only 6 fails are the intended RED seam items; Aqua green.
- **Committed in:** 31f08ad (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 bug/regression)
**Impact on plan:** All three were necessary to satisfy the plan's own acceptance criteria (test-env resolves StableRNGs; runner healthy; Phase-2 baseline green). No scope creep — the manifest regeneration and Aqua ignore are directly caused by adding the StableRNGs foundation dependency.

## Issues Encountered
- The plan's Task-3 verify command (`julia --project=. -e 'using TestItemRunner; @run_package_tests ...'`) cannot run as written: `TestItemRunner` is a test-only dependency, not present in the main project env. Used the authoritative full-suite gate `julia --project=. -e 'import Pkg; Pkg.test()'` instead, which sets up the sandbox with both TSODSO and the test deps and runs the runner. Exit code 1 is the intended RED-harness state (6 failing seam items), not a crash.

## Known Stubs
The six new `src/` files are intentional comment-only stubs (no functional code, no exports) — this is the plan's explicit design (shared-foundation wave wires the include graph; Waves 2-3 fill the stubs). Each is owned by a named downstream plan:
- `src/data/profiles.jl` → 03-02 (DATA-04)
- `src/devices/Thermostatic.jl`, `Deferrable.jl` → 03-03 (DEV-01/DEV-02)
- `src/devices/PVBattery.jl` → 03-04 (DEV-04)
- `src/devices/Aggregator.jl` → 03-05 (DEV-05)
- `src/models/welfare_solve.jl` → 03-05 (OPT-01)

Correspondingly, the six seam `@testitem`s are RED by design until their owning wave lands.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Wave 2 (03-02/03/04) and Wave 3 (03-05) can fill their stubs without touching any shared file (Project.toml, Manifests, or `src/TSODSO.jl`).
- StableRNGs is available in both envs; `Phase3Fixtures` is ready for downstream integration tests.
- Reminder for plan 03-02: once `profiles.jl` `using`s StableRNGs, remove the `stale_deps` ignore in `test/test_toy_dc.jl`.

---
*Phase: 03-prosumer-device-library-social-welfare-solve*
*Completed: 2026-07-18*

## Self-Check: PASSED
- All 13 created files present on disk.
- All 3 task commits (ee1cd5e, c363816, 31f08ad) present in git history.
