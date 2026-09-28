---
phase: 26-network-device-model-correctness
plan: 04
subsystem: devices
tags: [jump, aggregator, flexible-load, reactive-power, thesis-eq-3.23]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "Aggregator sole :Rp/:Rq writer contract, reactive_factor helper (pre-existing)"
provides:
  - "is_flexible_load(::AbstractDevice) trait (default false; true for Thermostatic/Deferrable)"
  - "Optional per-device φ power-factor override on Thermostatic and Deferrable"
  - "Aggregator roll-up draws q = p_inject*tan(arccos φ_used) into q_inject for flexible-load members"
  - "Per-device :Rq == p*tanφ regression tests (including the φ-override precedence case)"
affects: ["26-07 (Interruptible Variant-1->Variant-2 conversion, same is_flexible_load trait)", "26-08 (cross-phase golden re-derivation)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AbstractDevice trait function (is_flexible_load) dispatched per concrete device type, defaulting false on the abstract supertype"
    - "Optional Union{Nothing,T} device field threaded through inner constructor (positional/required) + outer constructor (keyword, default nothing), converted separately from the promote_type/promote calls since nothing cannot be promoted"

key-files:
  created: []
  modified:
    - src/devices/AbstractDevice.jl
    - src/devices/Aggregator.jl
    - src/devices/Thermostatic.jl
    - src/devices/Deferrable.jl
    - test/test_aggregator.jl

key-decisions:
  - "Interruptible's Variant-1->Variant-2 conversion (same is_flexible_load trait target) is explicitly out of scope for this plan — larger, non-Aggregator-file blast radius, handled by Plan 26-07 which depends on this plan."
  - "Fixed the pre-existing q_inject byte-identity testitem's case (a) in test_aggregator.jl (Thermostatic+PVBattery -> PVBattery+PVBattery) since FIX-05 correctly invalidated its old zero-q_inject assertion for a Thermostatic member; broader blast radius across other fixtures deferred to Plan 26-08's cross-phase golden audit."

patterns-established:
  - "Flexible-load reactive draw: is_flexible_load(d) trait check inside the Aggregator's per-device roll-up loop, additive alongside the existing hasproperty(:q_inject) accumulation — a device may in principle carry both, though none currently does."

requirements-completed: [FIX-05]

# Metrics
duration: 35min
completed: 2026-09-28
---

# Phase 26 Plan 04: Flexible-Load Power-Factor Reactive Draw Summary

**Thermostatic and Deferrable loads now draw q = p·tan(arccos φ) into the Aggregator's `:Rq` residual via a new `is_flexible_load` trait, closing the FIX-05 defect where only the inelastic demand term ever drew reactive power.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-28T16:44:00Z (approx, worktree branch reset)
- **Completed:** 2026-09-28T17:19:20Z
- **Tasks:** 3 completed (+ 1 in-scope test repair)
- **Files modified:** 4 (3 source, 1 test)

## Accomplishments

- Added `is_flexible_load(::AbstractDevice)` trait to `AbstractDevice.jl`, defaulting `false`, exported alongside `AbstractDevice`.
- `Thermostatic` and `Deferrable` both override the trait to `true` and gain an optional `φ::Union{Nothing,T}` field (default `nothing`, keyword-settable, validated to `(0,1]` when supplied) that overrides the aggregator's own power factor for that device's own reactive draw.
- `Aggregator.contribute!`'s roll-up loop now sums `res.p_inject[t] * reactive_factor(φ_used)` into `q_inject` for every flexible-load member, where `φ_used` is the device's own `φ` when set, else `agg.φ` — additive alongside the pre-existing `q_inject`-field accumulation (MESH-04), so a mixed flexible-load + `FourQuadBESS` aggregator sums both terms.
- Added a new `@testitem` in `test/test_aggregator.jl` proving `:Rq`'s device-reactive coefficient equals `-reactive_factor(φ)` for a Thermostatic-only aggregator, a Deferrable-only aggregator, and a φ-override case (device `φ=0.75` inside an `agg.φ=0.9` aggregator uses `0.75`).
- Repaired a pre-existing `test_aggregator.jl` testitem whose "byte-identity" sub-case was invalidated by this very fix (see Deviations).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the is_flexible_load trait and the optional phi override field to Thermostatic and Deferrable** - `7d501d3` (feat)
2. **Task 2: Wire the Aggregator roll-up to draw power-factor reactive power from flexible-load members** - `b1f5826` (feat)
3. **Task 3: Add per-device :Rq == p*tanφ tests for Thermostatic and Deferrable** - `27933ee` (test)
4. **Rule-1 auto-fix: repair the pre-existing q_inject byte-identity testitem** - `d3dd947` (fix)

**Plan metadata:** this SUMMARY's own commit (docs: complete plan)

_Note: no TDD RED/GREEN/REFACTOR gate sequence was used — the plan's tasks were `tdd="true"` but the project's TestItemRunner does not resolve under `--project=.` (known trap, see `gsd-plan-verify-testitemrunner-trap` memory), so each task's `<verify>` script substituted a direct Julia script reproduction of the intended behavior, run to green before committing, per the established project convention for this repo._

## Files Created/Modified

- `src/devices/AbstractDevice.jl` - new `is_flexible_load(::AbstractDevice) = false` trait, exported
- `src/devices/Thermostatic.jl` - new `φ::Union{Nothing,T}` field (inner ctor positional/required, outer ctor keyword default `nothing`), `is_flexible_load(::Thermostatic) = true`, docstring updates
- `src/devices/Deferrable.jl` - new `φ::Union{Nothing,T}` field (inner + outer ctor keyword, mirroring the existing `E_min` pattern), `is_flexible_load(::Deferrable) = true`, docstring updates
- `src/devices/Aggregator.jl` - roll-up loop extension summing the flexible-load reactive term into `q_inject`; module header comment + `contribute!` docstring updated
- `test/test_aggregator.jl` - new FIX-05 `@testitem` (3 cases); repaired the pre-existing q_inject byte-identity testitem's case (a)

## Decisions Made

- Followed the plan's exact interface guidance: `φ` is a REQUIRED positional argument in `Thermostatic`'s inner constructor (mirroring its existing all-positional-fields convention) but an OPTIONAL KEYWORD (default `nothing`) in the outer convenience constructor; `Deferrable`'s inner constructor keeps `φ` as a keyword (mirroring its existing `E_min` keyword-threading pattern exactly, since `Deferrable`'s inner constructor already uses keywords).
- `φ` is deliberately excluded from both devices' `promote_type`/`promote` calls (it may be `nothing`, which cannot be promoted with `Real`s) — a supplied `Real` override is separately `convert`ed into the common promoted type, while `nothing` passes through unchanged.
- Left `Interruptible`'s Variant-1→Variant-2 conversion untouched, per the plan's explicit scope boundary (larger blast radius, owned by Plan 26-07).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Repaired the pre-existing q_inject byte-identity testitem invalidated by Task 2's own fix**
- **Found during:** Task 3 (writing/verifying the new FIX-05 regression alongside the existing suite)
- **Issue:** The pre-existing `"aggregator: q_inject byte-identity (no 4Q) + FourQuadBESS summation (MESH-04, D-09/D-10)"` testitem's case (a) built a `Thermostatic` + `PVBattery` aggregator and asserted `q_inject[t] == zero(AffExpr)`. Task 2's fix correctly makes `is_flexible_load(::Thermostatic) == true`, so that aggregator's `q_inject` is now genuinely nonzero (the Thermostatic's own `p*tanφ` term) — the old assertion encoded the pre-fix bug, not a byte-identity invariant.
- **Fix:** Swapped case (a)'s device pair from `[Thermostatic, PVBattery]` to `[PVBattery, PVBattery]` — both active-only devices carrying neither a genuine `q_inject` field nor `is_flexible_load == true` — preserving the sub-case's actual intent (testing the `hasproperty(:q_inject)` accumulator stays byte-identical to zero when no member carries the field), independent of FIX-05's new behavior. Case (b) (Thermostatic + FourQuadBESS summation) needed only its own `therm` definition restored (previously shared from case (a)); its assertions target only the `FourQuadBESS`'s `q_var[t]` coefficient, a distinct `AffExpr` term unaffected by the Thermostatic's additive contribution, and were re-verified unchanged.
- **Files modified:** `test/test_aggregator.jl`
- **Verification:** Reproduced both testitem cases standalone via direct Julia scripts (`julia --project=.`); both pass. Full assertion set unchanged in case (b).
- **Committed in:** `d3dd947`

---

**Total deviations:** 1 auto-fixed (1 bug fix, Rule 1)
**Impact on plan:** Necessary consequence of the FIX-05 correctness fix itself — no scope creep; fix stayed within this plan's own designated test file (`test/test_aggregator.jl`).

## Known Stubs

None.

## Threat Flags

None — this plan edits internal device/aggregator code and tests only (per the plan's own threat model; T-26-06/T-26-07 both `accept`, no package installs, no secrets).

## Issues Encountered

- **Broader golden/fixture blast radius (not fixed here, flagged for 26-08):** Any full-model solve that places a `Thermostatic` or `Deferrable` device inside an `Aggregator` will now correctly draw additional reactive power into `:Rq` — this is a genuine, intended behavior change (the whole point of FIX-05), but it means numeric goldens in OTHER test files/fixtures (e.g. `test/fixtures_phase*.jl`, `test/test_mpc_*.jl`, `test/test_run_stochastic.jl`, `test/test_stochastic_welfare.jl`, `test/test_ieee8500.jl`, `test/test_planning_oracle.jl`, and various `scripts/*.jl` demos) that solve a full welfare/ADMM/planning model with a Thermostatic or Deferrable member may now produce different reactive-power, DLMP, or welfare figures than previously pinned. This plan's own scope (per its `files_modified` and acceptance criteria) is limited to `src/devices/{AbstractDevice,Aggregator,Thermostatic,Deferrable}.jl` and `test/test_aggregator.jl`; the phase's own Plan 26-08 (wave 3, depends on this plan plus 26-01/02/03/05/06/07) is explicitly chartered to run the full suite after ALL Phase 26 fixes land, re-derive every moved golden with an old→new+cause record, and write the cross-phase `26-GOLDEN-AUDIT.md` table — this is where the remaining blast radius from FIX-05 should be resolved, not silently re-pinned.
- The `--project=.` TestItemRunner trap (per project memory `gsd-plan-verify-testitemrunner-trap`) means none of this plan's new/repaired `@testitem`s were run under the actual TestItemRunner harness in this worktree — each was instead reproduced and verified as a standalone Julia script under `--project=.`. This is the established, documented convention for this repo's executors and not itself a new risk, but the full suite (`Pkg.test()`) has not been run in this worktree and is expected to run as part of Plan 26-08's cross-phase verification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `is_flexible_load` trait is now available for Plan 26-07 to apply to `Interruptible` when it converts from Variant-1 (self-injecting) to Variant-2 (aggregatable) — no rework needed on this plan's files for that conversion to proceed.
- The Aggregator roll-up mechanism (additive `is_flexible_load` accumulation) is proven correct on single-device, φ-override, and mixed flexible-load+FourQuadBESS cases; ready for Plan 26-08 to sweep for downstream golden shifts across the rest of the suite.
- **Blocker/concern carried forward:** Plan 26-08 must account for FIX-05's reactive-power blast radius across every fixture/script that builds a Thermostatic- or Deferrable-bearing Aggregator inside a full solve — see Issues Encountered above.

## Self-Check: PASSED

All 6 modified/created files found on disk (`src/devices/AbstractDevice.jl`,
`src/devices/Aggregator.jl`, `src/devices/Thermostatic.jl`, `src/devices/Deferrable.jl`,
`test/test_aggregator.jl`, this SUMMARY.md). All 4 task commit hashes (`7d501d3`,
`b1f5826`, `27933ee`, `d3dd947`) found in `git log --oneline --all`.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*
