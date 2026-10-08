---
phase: 26-network-device-model-correctness
plan: 07
subsystem: devices
tags: [jump, aggregator, flexible-load, reactive-power, thesis-eq-3.23, device-contract]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "is_flexible_load(::AbstractDevice) trait + Aggregator flexible-load tanφ roll-up (plan 26-04)"
provides:
  - "Interruptible converted from the self-injecting Variant-1 device contract to the aggregatable Variant-2 contract"
  - "is_flexible_load(::Interruptible) == true, matching Thermostatic/Deferrable"
  - "solve_linear's device roll-up loop generalized to write ANY Variant-2-contract device's residual/objective generically"
  - "AbstractDevice.jl's docstring: Variant-1 removed (zero live members)"
affects: ["26-08 (cross-phase golden re-derivation — full suite must be re-run to confirm no other regression)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Assembly-level (non-Aggregator) consumer of the Variant-2 contract: solve_linear now performs its own explicit residual/objective write loop, mirroring Aggregator's own roll-up shape, generalizing beyond Interruptible to any device with a .bus field"

key-files:
  created: []
  modified:
    - src/devices/Interruptible.jl
    - src/devices/AbstractDevice.jl
    - src/models/linear_solve.jl
    - test/test_device.jl
    - test/test_linear_solve.jl
    - test/test_aggregator.jl
    - src/devices/PVBattery.jl
    - docs/literate/convex_branch_flow.jl

key-decisions:
  - "New Interruptible :Rq==p*tanφ regression landed in test/test_aggregator.jl (not a new per-device file) per the plan's own action text (\"in test/test_aggregator.jl or a per-device file\"), mirroring plan 26-04's Thermostatic/Deferrable testitems exactly — a deviation from the plan frontmatter's files_modified list (which omitted test_aggregator.jl) but explicitly sanctioned by the plan's task action prose."
  - "test/test_conformance.jl needed NO logic change (confirmed by direct-script reproduction of its DC<->LinDistFlow crit-4 case) since it never indexes ctx.meta[:device_vars] — only test_linear_solve.jl's device_vars[1] -> device_vars[1].p needed the shape fix."

patterns-established:
  - "Rule-1 doc-staleness fix: any comment contrasting a device against \"the self-injecting Interruptible\" became factually wrong the moment Interruptible converted; searched and fixed both occurrences (PVBattery.jl docstring, docs/literate/convex_branch_flow.jl) rather than leaving stale prose."

requirements-completed: [FIX-05]

# Metrics
duration: 40min
completed: 2026-09-28
---

# Phase 26 Plan 07: Interruptible Variant-1 -> Variant-2 Conversion Summary

**`Interruptible` converts from the self-injecting (Variant-1) device contract to the aggregatable (Variant-2) contract used by `Thermostatic`/`Deferrable`, so it can draw power-factor reactive power through the same `Aggregator` roll-up (FIX-05), with `solve_linear.jl`'s device loop fixed in the same plan to perform the residual/objective write generically — byte-identical published prices/objectives on the existing closed-form fixture.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-28T17:20:00Z (approx, worktree branch reset to wave-1 base `3d808d4`)
- **Completed:** 2026-09-28T18:00:00Z (approx)
- **Tasks:** 3 completed (+ 1 in-scope Rule-1 doc-staleness fix)
- **Files modified:** 8 (3 source, 3 test, 1 device docstring, 1 literate docs page)

## Accomplishments

- `Interruptible.contribute!` now returns `(; vars = (; p), p_inject, utility)`, writing
  NOTHING to `ctx.residuals` and calling NO `add_to_objective!` — identical shape to
  `Deferrable`/`Thermostatic`.
- `is_flexible_load(::Interruptible) = true` added alongside the `Thermostatic`/
  `Deferrable` overrides from plan 26-04, so `Interruptible`'s own consumption now draws
  `q = p·tan(arccos φ)` into an `Aggregator`'s `:Rq` residual (thesis eq. 3.23, FIX-05)
  when wrapped in one.
- `AbstractDevice.jl`'s "TWO variants" docstring rewritten: the "Variant 1 —
  SELF-INJECTING device" section is REMOVED (Interruptible was its only member and
  now has zero live self-injecting devices in the codebase); a historical note explains
  the removal and points to this plan.
- `src/models/linear_solve.jl`'s device roll-up loop — the ONLY production call site
  that consumed a Variant-1 device directly — replaced the single-line
  `ctx.meta[:device_vars] = [contribute!(d, ctx; T=T) for d in devices]` with an explicit
  loop that writes each device's returned `p_inject` into `:Rp` and `utility` into
  `ctx.meta[:objective]`, mirroring `Aggregator.contribute!`'s own roll-up shape.
  Generalizes to ANY Variant-2-contract device with a `.bus` field, not just
  `Interruptible`. Verified byte-identical objective (`2.0`) and DADP (`2.0`) on the
  existing closed-form 2-bus fixture before/after the conversion.
- Updated the 2 live call sites that indexed `ctx.meta[:device_vars]` directly
  (`test/test_linear_solve.jl`) or asserted on `contribute!`'s pre-conversion return
  shape (`test/test_device.jl`); confirmed `test/test_conformance.jl` and
  `docs/literate/lindistflow.jl` need NO change (neither indexes `device_vars`, and
  both were re-run/reproduced to confirm byte-identical behavior).
- Added a new `@testitem` in `test/test_aggregator.jl` proving the converted
  `Interruptible`, wrapped in a minimal `Aggregator`, draws `:Rq` coefficient
  `-reactive_factor(φ)` on its own `p[t]` — mirroring plan 26-04's Thermostatic/
  Deferrable regression exactly.
- Rule-1 fix: two stale doc comments (`PVBattery.jl`'s docstring, `docs/literate/
  convex_branch_flow.jl`) that contrasted their own contract against "the self-injecting
  `Interruptible`" were updated to reflect the conversion; both literate docs scripts
  (`lindistflow.jl`, `convex_branch_flow.jl`) were re-run end-to-end to confirm they
  still execute cleanly.

## Task Commits

Each task was committed atomically:

1. **Task 1: Convert Interruptible to the Variant-2 aggregatable contract** - `8354cd9` (feat)
2. **Task 2: Fix solve_linear's device loop to write the residual/objective generically** - `a24555b` (fix)
3. **Task 3: Update the 3 live call-site tests and add the Interruptible :Rq regression** - `b72f442` (test)
4. **Rule-1 auto-fix: repair stale self-injecting-Interruptible doc references** - `182b627` (docs)

**Plan metadata:** this SUMMARY's own commit (docs: complete plan)

_Note: no TDD RED/GREEN/REFACTOR gate sequence was used — the plan's Tasks 1/2 were
`tdd="true"` but the project's TestItemRunner does not resolve under `--project=.`
(known trap, see `gsd-plan-verify-testitemrunner-trap` memory), so each task's
`<verify>` script substituted a direct Julia script reproduction of the intended
behavior, run to green before committing, per the established project convention for
this repo's executors (confirmed by plan 26-04's own prior SUMMARY)._

## Files Created/Modified

- `src/devices/Interruptible.jl` - `contribute!` converted to the Variant-2 shape;
  module header, struct docstring, and `contribute!` docstring rewritten from
  Variant-1 to Variant-2 prose; new `is_flexible_load(::Interruptible) = true`
- `src/devices/AbstractDevice.jl` - "TWO variants" docstring collapsed to the single
  aggregatable-device contract; Variant-1 section removed with a historical note;
  `is_flexible_load`'s own docstring updated to list `Interruptible`
- `src/models/linear_solve.jl` - device roll-up loop rewritten to write `:Rp`/
  objective explicitly and generically for the Variant-2 contract; docstring updated
- `test/test_device.jl` - second `@testitem` rewritten to inspect the returned
  NamedTuple instead of `ctx.residuals`/`ctx.meta[:objective]` mutation
- `test/test_linear_solve.jl` - `ctx.meta[:device_vars][1]` -> `[1].p`
- `test/test_aggregator.jl` - new `@testitem`: converted Interruptible through an
  Aggregator draws `:Rq == p*tanφ`
- `src/devices/PVBattery.jl` - Rule-1 fix: stale "self-injecting Interruptible"
  contrast in the docstring updated
- `docs/literate/convex_branch_flow.jl` - Rule-1 fix: same stale contrast in the
  literate docs prose updated

## Decisions Made

- Followed the plan's exact target shape: `Deferrable.jl`'s `contribute!` was used as
  the literal template for `Interruptible.jl`'s converted `contribute!` (closest
  structural sibling — bounds-only device, no temporal coupling beyond simple bounds).
- The new FIX-05 regression test landed in `test/test_aggregator.jl` (not a new
  per-device file), per the plan's own action text explicitly naming that file as an
  acceptable location and to mirror plan 26-04's existing Thermostatic/Deferrable
  testitems in the same file for discoverability.
- `test/test_conformance.jl` was left UNMODIFIED after confirming (via a direct-script
  reproduction of its exact DC<->LinDistFlow crit-4 assertions) that it needs no
  change — it never indexes `ctx.meta[:device_vars]`, only `obj`/`dadp`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale "self-injecting Interruptible" doc references made incorrect by this plan's own conversion**
- **Found during:** post-Task-3 sweep (`grep -rln "Variant 1\|Variant-1\|self-injecting"` across `src/`, `test/`, `docs/`)
- **Issue:** `src/devices/PVBattery.jl`'s docstring ("Unlike the self-injecting
  `Interruptible`, this device is...") and `docs/literate/convex_branch_flow.jl`'s
  prose ("...rather than the self-injecting `Interruptible` used on the previous
  page...") both contrasted their own aggregatable contract against Interruptible's
  PRE-conversion behavior — a comparison this plan's own Task 1 made factually wrong.
- **Fix:** Updated both to describe `Interruptible` as conforming to the SAME
  aggregatable contract (with a note that it was converted from an earlier
  self-injecting contract in this plan), rather than removing the comparison outright.
- **Files modified:** `src/devices/PVBattery.jl`, `docs/literate/convex_branch_flow.jl`
- **Verification:** Re-ran both `docs/literate/lindistflow.jl` and
  `docs/literate/convex_branch_flow.jl` end-to-end via `julia --project=.` — both
  execute cleanly with no errors.
- **Committed in:** `182b627`

---

**Total deviations:** 1 auto-fixed (1 doc-staleness fix, Rule 1)
**Impact on plan:** Necessary consequence of Task 1's own contract conversion — no
scope creep beyond fixing comments this plan's own change made incorrect; both edited
files stayed within the phase's device/docs surface, no behavior changed.

## Known Stubs

None.

## Threat Flags

None — this plan converts one device's internal contract and its production consumer
plus test/docs updates only (per the plan's own threat model; T-26-10/T-26-11 both
`accept`, no package installs, no new external surface).

## Issues Encountered

- **`src/pricing/fit.jl:80`'s comment ("A flexible load (Deferrable / Thermostatic /
  Interruptible): reuse its aggregatable builder")** already anticipated
  `Interruptible` being aggregatable BEFORE this plan converted it — confirming the
  codebase's `fit.jl` roll-up (`contribute!(d, ctx; T)` on a generic flexible-load `d`)
  was already written assuming the Variant-2 shape. No live call site in the current
  suite actually passes an `Interruptible` through that path (verified: no
  `test_pricing_fit.jl` fixture uses `Interruptible`), so this was latent, not an
  active bug this plan needed to fix — but it corroborates that the conversion is the
  correct direction and unblocks that path for any future caller.
- Per plan 26-04's own "Next Phase Readiness" note, this plan's own regression
  (`test/test_aggregator.jl`'s new Interruptible `:Rq` testitem) is additive on top of
  plan 26-04's `is_flexible_load` roll-up mechanism — no rework was needed on
  `Aggregator.jl`/`AbstractDevice.jl`'s trait-dispatch machinery for this conversion to
  land.
- **Full suite not run in this worktree** (per the project's `background-suite-orphan-race`
  memory and this plan's own execution-context notes, full-suite verification is
  deferred to Plan 26-08's cross-phase audit, which runs AFTER all Phase 26 plans land).
  Only the plan's own `<verify>` scripts (all 3 tasks) plus targeted direct-script
  reproductions of `test_conformance.jl`'s crit-4 case and CR-01/WR-01 edge cases were
  run in this worktree, all green.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `Interruptible` is now a fully aggregatable (Variant-2) device — any future
  `Aggregator` population may include it alongside `Thermostatic`/`Deferrable`/
  `PVBattery` with no special-casing.
- `AbstractDevice.jl`'s contract surface is now single-variant (Variant-2 only) —
  Plan 26-08's cross-phase audit should confirm no other file's docs/comments still
  reference the removed Variant-1 section (a targeted grep for "Variant 1" /
  "self-injecting" was run and both remaining live hits were fixed in this plan; a
  fresh grep at 26-08 time is still advisable in case other plans in the same wave
  touched adjacent files).
- **Blocker/concern carried forward to 26-08:** this plan's own `<verify>` scripts and
  targeted direct-script reproductions all pass, but the FULL suite
  (`julia --project=. -e 'import Pkg; Pkg.test()'`) has not been run against this
  worktree's combined wave-2 changes — Plan 26-08 is explicitly chartered to do so
  after all Phase 26 plans land.

## Self-Check: PASSED

All 8 modified files found on disk (`src/devices/Interruptible.jl`,
`src/devices/AbstractDevice.jl`, `src/models/linear_solve.jl`, `test/test_device.jl`,
`test/test_linear_solve.jl`, `test/test_aggregator.jl`, `src/devices/PVBattery.jl`,
`docs/literate/convex_branch_flow.jl`, this SUMMARY.md). All 4 task commit hashes
(`8354cd9`, `a24555b`, `b72f442`, `182b627`) found in `git log --oneline --all`.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*
