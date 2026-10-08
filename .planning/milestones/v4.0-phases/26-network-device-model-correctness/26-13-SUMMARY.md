---
phase: 26-network-device-model-correctness
plan: 13
subsystem: testing
tags: [julia, jump, socp, thermostatic, mesh-flow, fixtures, literate-docs]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "FIX-05 (Plan 26-04) — Aggregator applies tanφ to flexible-load p_inject into :Rq, with an optional per-device φ override on Thermostatic/Deferrable/Interruptible"
provides:
  - "Phase23Fixtures.mesh_aggregators() pins φ=1.0 on both Thermostatic members, restoring the MESH-02/03 angle-recoverability fixture's original zero-reactive-draw intent"
  - "docs/literate/meshed_reactive_price.jl's self-contained inline fixture reconstruction kept consistent with the same φ=1.0 pin"
  - "Documented finding: reactive load (φ=0.95) breaks SOCP exactness on the uniform-R/X mesh diamond (cone ratio ~2711, gap ~0.0147) — a genuine research consequence of FIX-05 on a mesh topology, not a bug"
affects: [phase-27, phase-28]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-device φ override (Thermostatic outer-constructor keyword, Plan 26-04) used to pin a fixture's power factor independent of its owning Aggregator's own φ"

key-files:
  created: []
  modified:
    - test/fixtures_phase23.jl
    - docs/literate/meshed_reactive_price.jl

key-decisions:
  - "Pin φ=1.0 in mesh_aggregators() (PM-04 locked decision) rather than adopting the newly-inexact behavior as the fixture's default, since the fixture's purpose is isolating angle recoverability from reactive-power effects"
  - "Record the exactness-loss finding as fact in the fixture's own docstring (not merely implied by the code diff), per threat T-26-22's mitigation requirement"

requirements-completed: [FIX-05]

# Metrics
duration: ~20min
completed: 2026-09-29
---

# Phase 26 Plan 13: Mesh diamond PM-04 gap-closure Summary

**Pinned `Phase23Fixtures.mesh_aggregators()`'s two Thermostatic loads to φ=1.0, restoring the MESH-02/03 angle-recoverability fixture's zero-reactive-draw intent, and documented as fact the genuine finding that reactive load (φ=0.95) breaks SOCP exactness on the uniform-R/X mesh diamond.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 2/2 completed
- **Files modified:** 2

## Accomplishments
- `mesh_aggregators()`'s two `Thermostatic` constructions now pass `φ = 1.0` explicitly, overriding the owning `Aggregator`'s own `φ = 0.95` (thesis eq. 3.23 per-device override, Plan 26-04's outer-constructor keyword).
- The fixture's docstring now states, as fact: (a) the pin's purpose (restoring the MESH-02/03 zero-reactive-draw intent broken implicitly by FIX-05), and (b) the discovered finding that at the aggregators' native φ=0.95 the `:uniform` diamond's SOC relaxation becomes genuinely inexact (measured cone ratio ~2711, gap ~0.0147, persistent across a Clarabel `tol_gap` ladder) while `:heterogeneous` stays exact — explicitly marked NOT a bug and out of scope for this phase.
- `docs/literate/meshed_reactive_price.jl`'s self-contained inline `therm2`/`therm3` reconstruction (this file never `include()`s the test fixture) received the identical `φ=1.0` pin plus a one-line cross-reference comment to `test/fixtures_phase23.jl`'s pin and finding.
- Re-ran the literate script end-to-end; it exits cleanly (no thrown error), and its live-measured `worst_residual` values (uniform ≈0.0063, heterogeneous ≈0.0607) match the docs page's own pre-existing prose exactly — confirming this fix did not perturb the doc's other claims.

## Task Commits

1. **Task 1: Pin φ=1.0 on both mesh_aggregators() Thermostatic members and document the finding** - `f04ca73` (fix)
2. **Task 2: Apply the identical φ=1.0 pin to meshed_reactive_price.jl's self-contained fixture reconstruction** - `cdd43bf` (docs)

**Plan metadata:** (this SUMMARY commit, to follow)

## Files Created/Modified
- `test/fixtures_phase23.jl` - `mesh_aggregators()` now passes `φ = 1.0` to both `Thermostatic(...)` calls; docstring rewritten to state the pin's purpose and the discovered exactness-loss finding as fact.
- `docs/literate/meshed_reactive_price.jl` - inline `therm2`/`therm3` construction (lines ~78-84) receives the identical `φ = 1.0` pin plus a cross-reference comment to the test fixture.

## Decisions Made
- Followed the plan's locked PM-04 decision exactly: pin φ=1.0 (not adopt the newly-inexact behavior), and record the finding rather than silently absorb it.
- No architectural changes were needed; Plan 26-04's existing per-device `φ` override field was sufficient.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' verify blocks (adapted per the project's own `gsd-plan-verify-testitemrunner-trap` memory — TestItemRunner does not resolve under `--project=.`, so verification used direct Julia scripts reproducing the `@testitem` bodies inline, rather than `include("test/fixtures_phase23.jl")` which requires the test-only `TestItems` package) passed on both impedance profiles.

## Verification Detail

Since `test/fixtures_phase23.jl` is a `@testmodule` (TestItems macro, test-only dependency not resolvable under `--project=.` per the project's `gsd-plan-verify-testitemrunner-trap` memory), Task 1's plan-supplied `<verify>` command (which does `include("test/fixtures_phase23.jl")`) was adapted: a scratch script inlining `mesh_aggregators()`/`mesh_feeder()`/`mesh_lambda0()`'s exact post-fix logic (identical to the committed file) was run instead, reproducing:
- `test_mesh_flow.jl:4` — `solve_welfare` on both profiles returns without throwing, `ctx.meta[:formulation] == :MeshedFlow`, `isfinite(w)`. PASSED.
- `test_mesh_angle_certificate.jl:4` — `:uniform` certifies (`angle_certified`, `recoverable=true`, `worst_residual=0.006273`), `:heterogeneous` reports `angle_unrecoverable` under `report=true` and throws `ErrorException` under `report=false`, residual ordering `r_h > 5*r_u` holds (ratio ~9.68x), price provenance correctly names `:MeshedFlow`. PASSED.
- `test_mesh_angle_certificate.jl:97` — reversed-orientation re-encoding: verdicts/recoverability match between forward and reversed storage on both profiles, residuals agree within the test's documented tolerances, recovered phasor fields agree to <1e-8 on the certified (`:uniform`) case. PASSED.

Task 2's verify command ran as specified in the plan (`julia --project=. docs/literate/meshed_reactive_price.jl`): exit code 0, only the expected `@warn` (not an error) for the heterogeneous unrecoverable case; no `error(...)` calls triggered.

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes were introduced; this plan only edits a test fixture and a literate docs page, per the plan's own threat model.

## Cross-plan observations

None encountered outside this plan's two files during execution.

## Issues Encountered

None.

## Next Phase Readiness

- Cluster G (PM-04) of `26-POSTMERGE-TRIAGE.md` is closed: `test_mesh_flow.jl:4` and both `test_mesh_angle_certificate.jl` items (`:4`, `:97`) now pass, and the genuine exactness-loss finding at φ=0.95 is documented in both the test fixture's docstring and the literate docs page (rather than silently fixed away).
- No golden values were moved by this plan (the pin restores pre-FIX-05 numeric behavior exactly — `worst_residual` values are unchanged from before FIX-05, matching the docs page's pre-existing prose).

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: test/fixtures_phase23.jl
- FOUND: docs/literate/meshed_reactive_price.jl
- FOUND commit: f04ca73
- FOUND commit: cdd43bf
