---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 04
subsystem: pricing
tags: [dlmp, jump, deprecation, testitems, clarabel]

# Dependency graph
requires:
  - phase: 27-02
    provides: "prior wave-1 pricing/exactness fixes this plan builds on (26-10 :smax_rev congestion term, cone/drop derivation already correct in dlmp.jl's header)"
provides:
  - "DlmpDecomposition{A} struct (energy/cone/drop/congestion/reactive/total) as decompose_dlmp's return type, replacing the ad-hoc NamedTuple"
  - "cone/drop field names matching what the components mathematically ARE (rotated-SOC cone-slot multiplier, thesis 3.39; voltage-drop/copy-drop multiplier, thesis 3.33/3.43)"
  - "Base.getproperty deprecation shim: .loss/.voltage still work (one-time Base.depwarn each), aliasing .cone/.drop"
  - "Corrected zero-iff-multiplier-zero test property on the IEEE-13 ground fixture, replacing the factually-incorrect 'voltage component ≈ 0 when unbinding' claim"
affects: [pricing, dlmp, phase-36-code-export-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deprecation via Base.getproperty override + Base.depwarn, not @deprecate (needed because the deprecated names are struct FIELDS, not functions)"
    - "Zero-iff-multiplier-zero property testing on a realistic-impedance (non-toy) fixture, verified in both directions (a trivially-zero root-bus case plus the genuinely-nonzero non-root case) rather than a magnitude-threshold heuristic"

key-files:
  created: []
  modified:
    - src/pricing/dlmp.jl
    - src/powerflow/ConvexBranchFlow.jl
    - test/test_pricing_dlmp.jl
    - test/test_dlmp.jl
    - docs/literate/pricing_dlmp.jl

key-decisions:
  - "Renamed the pre-existing local variable `cone` (holding ctx.constraints[:cone], the JuMP constraint container) to `cone_constr` inside decompose_dlmp's body to avoid a naming collision with the new `cone` COMPONENT accumulator matrix -- the plan's literal 'rename loss/voltage to cone/drop' instruction would otherwise have silently shadowed the constraint container mid-function (Rule 1 auto-fix, caught before it could corrupt the loop reading dual(cone[b,t])[3])."
  - "The new zero-iff-multiplier-zero test includes the root bus (empty root-path, vacuously-zero component) alongside all non-root buses/hours on the IEEE-13 ground fixture -- empirically, EVERY non-root (bus,hour) pair on this fixture has BOTH the cone and drop multipliers genuinely nonzero (measured directly: 0/264 zero pairs), so root's trivial zero case is what makes the IFF property non-vacuous in both directions."
  - "Removed (not renamed) the old '.voltage ≈ 0 when in-bound' assertion from the 2-bus 'uncongested/in-bound' test item rather than keeping a diluted version of it -- it conflated the drop EQUALITY-constraint dual (always structurally present) with the voltage INEQUALITY bound multiplier, a distinction that only became load-bearing after Phase 26's Gan-Low relabeling (PM-01)."
  - "Updated dlmp.jl's file-header derivation comment (not just decompose_dlmp's own docstring) to use cone/drop labels for consistency, since the plan's own objective statement flags the header's PRE-EXISTING loss/volt labels as the source of the naming mismatch."

patterns-established:
  - "Struct-with-getproperty-shim as the deprecation vehicle for renamed struct fields (vs. @deprecate for renamed functions)."

requirements-completed: [FIX-07]

# Metrics
duration: 45min
completed: 2026-09-29
---

# Phase 27 Plan 04: DLMP Component Naming (FIX-07) Summary

**Renamed `decompose_dlmp`'s `loss`/`voltage` fields to `cone`/`drop` (their true multiplier identity) via a new `DlmpDecomposition` struct with a `Base.getproperty` deprecation shim, and replaced the factually-incorrect "voltage ≈ 0 when unbinding" test with a correct zero-iff-multiplier-zero property verified on the IEEE-13 ground fixture.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-29T09:12:00Z (approx, first file read)
- **Completed:** 2026-09-29T09:57:10Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- `decompose_dlmp` now returns a `DlmpDecomposition{A}` struct (`energy, cone, drop, congestion, reactive, total`) instead of an ad-hoc `NamedTuple`, with `A` generic over the full-matrix (`Matrix{Float64}`) and `bus`-sliced (`Vector{Float64}`) return shapes.
- `.loss`/`.voltage` field access still works via a `Base.getproperty` override, each firing exactly one `Base.depwarn` and returning the identical value `.cone`/`.drop` would — verified on both return shapes, with zero numeric change (empirically confirmed the sum-to-price identity and byte-identical aliasing).
- Replaced the old, now-provably-incorrect "voltage component ≈ 0 when [the voltage bound is] unbinding" test assertion with a mathematically correct property: a component is zero IFF every underlying multiplier on the node's root path is zero — verified on the IEEE-13 ground fixture (realistic branch impedances), not the toy near-lossless 2-bus.
- All real consumers (tests, literate doc) migrated to the new `.cone`/`.drop` names; all other identified consumers (`scripts/*.jl`) confirmed to keep working unchanged via the deprecation alias (no edits needed, none in this plan's file scope).

## Task Commits

Each task was committed atomically:

1. **Task 1: DlmpDecomposition struct + cone/drop rename + Base.depwarn alias** - `3a98581` (feat)
2. **Task 2: Field-rename edits in tests + corrected zero-iff-multiplier property + literate doc update** - `978aebb` (test)

_Note: no separate TDD RED/GREEN split was applicable here — this plan is a rename/refactor of already-correct math (zero numeric change), not new behavior, so each task's own verify script served as the correctness gate before commit._

## Files Created/Modified

- `src/pricing/dlmp.jl` - Added `DlmpDecomposition{A}` struct + `Base.getproperty` deprecation shim; renamed `decompose_dlmp`'s internal `loss`/`voltage` locals to `cone`/`drop` (renamed the pre-existing constraint-container local `cone` to `cone_constr` to avoid a shadowing collision); updated docstring and file-header derivation comment; exported `DlmpDecomposition`.
- `src/powerflow/ConvexBranchFlow.jl` - Updated 2 prose comments referencing "loss/voltage DLMP component" to "cone/drop DLMP component (Phase 27 rename)".
- `test/test_pricing_dlmp.jl` - Mechanically renamed 8 `.loss`/`.voltage` sites to `.cone`/`.drop`; removed the incorrect "voltage ≈ 0 when in-bound" assertion; added a new zero-iff-multiplier-zero `@testitem` on the IEEE-13 ground fixture; added a new suite-level `@testitem` regression for the deprecated-alias shim (both full-matrix and `bus`-sliced shapes).
- `test/test_dlmp.jl` - Renamed the 1 `.loss`/`.voltage` site to `.cone`/`.drop`.
- `docs/literate/pricing_dlmp.jl` - Renamed every `.loss`/`.voltage` reference (prose, math, code, figure legend) to `.cone`/`.drop`; added a deprecation note.

## Decisions Made

- **`cone` naming collision fix (Rule 1):** the function already had a local `cone = ctx.constraints[:cone]` (the JuMP constraint container) before this plan touched it. The plan's literal instruction to rename the `loss`/`loss_b` accumulator to `cone`/`cone_b` would have silently reassigned/shadowed that pre-existing `cone` variable partway through the function, breaking the `dual(cone[b,t])[3]` read inside the per-branch loop (which runs BEFORE the reassignment textually, so Julia would actually have errored with a `UndefVarError`/`MethodError` on `getindex` at the WRONG point, or silently used the wrong value depending on statement order — either way, a genuine bug). Fixed by renaming the constraint-container local to `cone_constr`, keeping the two concepts (the JuMP constraint container vs. the accumulated DLMP component matrix) textually distinct. Caught and fixed during Task 1, before the verify script ran.
- **Root-bus inclusion in the zero-iff test:** measured directly (via a throwaway script) that on the IEEE-13 ground fixture, `d.cone`/`d.drop` are NEVER zero at any non-root bus/hour (0 of 264 sampled pairs), so a property test restricted to non-root buses would only exercise the "nonzero" direction of the IFF, never the "zero" direction. Including the root bus (whose root-to-root path is empty, so both the component and the multiplier-conjunction are vacuously/structurally zero) makes the test genuinely bidirectional without needing to hunt for a degenerate non-root zero case.
- **Deletion, not dilution, of the old "voltage ≈ 0 when in-bound" claim:** rather than keep a weakened version of the old assertion, it was removed outright from the 2-bus item and its role handed entirely to the new IEEE-13 zero-iff property test, per the plan's `must_haves.truths` requirement that the replacement property be "correct," not merely "less wrong."

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed a would-be variable-shadowing bug from the literal loss→cone rename**
- **Found during:** Task 1 (DlmpDecomposition struct + cone/drop rename)
- **Issue:** `decompose_dlmp` already had a local `cone = ctx.constraints[:cone]` (constraint container) before this plan's edits. Renaming the accumulator matrix `loss` → `cone` per the plan's literal instruction, without also renaming the pre-existing `cone` constraint-container local, would shadow it and corrupt the per-branch dual read `dual(cone[b,t])[3]`.
- **Fix:** Renamed the constraint-container local to `cone_constr`; the accumulator matrix is now the only thing named `cone`.
- **Files modified:** `src/pricing/dlmp.jl`
- **Verification:** Task 1's verify script (sum-to-price identity + `.loss`/`.voltage` alias check) passed; Task 2's direct-script re-run of the pre-existing IEEE-13/high-PV/2-bus test items (277+4+18+3 assertions) all passed with zero numeric change.
- **Committed in:** `3a98581` (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for correctness — without this fix the rename would have introduced a genuine bug in the per-branch cone-dual read. No scope creep; fixed within the same file/function the plan already scoped for editing.

## Issues Encountered

None beyond the deviation above. The `docs/literate/pricing_dlmp.jl` script initially appeared to hang under a 120s foreground timeout; re-run in the background confirmed it was CairoMakie precompilation/build time (exit code 0, no errors) — not a regression from this plan's changes.

## Cross-plan observations (not fixed, out of this plan's file scope)

- `scripts/pv_boom_report.jl`, `scripts/pv_boom_report_v2.jl`, `scripts/demo_flexibility_plots.jl`, `scripts/pv_boom_case_study.jl`, `scripts/thesis_caseA.jl`, `scripts/thesis_case123_repro.jl` all access `decompose_dlmp(...)`'s result via `.loss`/`.voltage` (plain field access only — no `pairs()`/`keys()`/NamedTuple-specific destructuring found, no `tagsave`/`JLD2`/`BSON` serialization of the `decompose_dlmp` return value found). These are NOT in this plan's `files_modified` scope (research's blast-radius grep only flagged tests + the literate doc + `ConvexBranchFlow.jl` comments as this plan's consumers) and continue to work unchanged via the `Base.getproperty` deprecation shim — confirmed by the SAME mechanism Task 1's verify script and Task 2's suite-level regression test directly exercise (both the full-matrix and `bus`-sliced shapes). Two of these scripts (`demo_flexibility_plots.jl:214`, `thesis_caseA.jl:84`) have a stale inline comment `# (; energy, loss, congestion, voltage, total)` describing the OLD NamedTuple shape — cosmetic only, left as-is (out of file scope); worth a one-line comment fix whenever those scripts are next touched, or in Phase 36 alongside the alias removal.
- No golden/serialized-result files were found to pin `decompose_dlmp`'s return type/shape directly (no `tagsave`/`JLD2`/`BSON` usage touching `decomp` in the grepped scripts), so switching the return type from `NamedTuple` to `DlmpDecomposition{A}` carries no discovered serialization-compatibility risk for this repo's current scripts.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-07 is complete: `decompose_dlmp` returns `cone`/`drop`-named components matching their true multiplier identity; `.loss`/`.voltage` remain as working, warning deprecated aliases (removal scheduled Phase 36); the sum-to-price identity is unchanged (zero numeric drift, verified via direct scripts reproducing every pre-existing `@testitem` in `test_pricing_dlmp.jl`/`test_dlmp.jl`); the replaced test property is mathematically correct and verified on a realistic-impedance fixture.
- No blockers for downstream plans in this phase. Phase 36 (Code & Export Cleanup) should remove the `.loss`/`.voltage` `Base.getproperty` branches and migrate the cosmetic stale-comment sites noted above.

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-04-SUMMARY.md`
- FOUND: commit `3a98581` (Task 1)
- FOUND: commit `978aebb` (Task 2)
