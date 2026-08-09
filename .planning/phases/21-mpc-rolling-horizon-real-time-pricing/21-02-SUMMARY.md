---
phase: 21-mpc-rolling-horizon-real-time-pricing
plan: 02
subsystem: models
tags: [mpc, rolling-horizon, dadp, diagnostics, testitem]

# Dependency graph
requires:
  - phase: 21-mpc-rolling-horizon-real-time-pricing (Wave 0/1, plan 21-01 pattern map)
    provides: the AdmmResiduals trace-struct convention (D-09) this plan mirrors verbatim
provides:
  - "MpcTrace: an exported, JuMP-free mutable ledger recording per rolling-horizon-step
    published DADP, day-ahead reference DADP, step-to-step price jump, cumulative deviation
    from the day-ahead DADP path, and certificate/fallback status"
  - "record!(trace, k, dadp, dadp_da, cert_status) -> MpcTrace with the same sequential-k
    fail-loud ArgumentError guard as AdmmResiduals's record!"
  - "max_jump/mean_jump/any_cert_failed query predicates, each with a safe 0.0/false default
    on an empty ledger"
  - "a new docs/src/api.md '## MPC / Rolling-Horizon' @autodocs section"
affects: [21-mpc-rolling-horizon-real-time-pricing Wave 2/3/4 (mpc_window.jl, mpc_loop.jl)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Trace-struct convention (AdmmResiduals/BendersTrace/MpcTrace): mutable struct + empty
      constructor + local, file-disjoint _assert_sequential guard + record! + safe-default
      query predicates on an empty ledger."

key-files:
  created:
    - src/models/mpc_trace.jl
    - test/test_mpc_trace.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md

key-decisions:
  - "MpcTrace's record! signature is record!(trace::MpcTrace, k::Integer, dadp::Real, dadp_da::Real, cert_status::Symbol) -> MpcTrace — Wave 3/4's mpc_loop.jl must call it with exactly this argument order and types."
  - "Only the literal :cert_failed Symbol counts as a failure in any_cert_failed; :local_ac_dual is a successful fallback escalation (D-04's ladder) and is NOT flagged."
  - "Kept the plan's own <verify> inline scripts' floating-point-fragile == assertions (e.g. jump_trace == [0.0, 0.3]) as isapprox (≈) equivalents when actually running them, and wrote the permanent test/test_mpc_trace.jl with ≈ for all derived-float-vector assertions — see Deviations below."

requirements-completed: [MPC-03]

# Metrics
duration: 6min
completed: 2026-08-09
---

# Phase 21 Plan 02: MpcTrace Price-Consistency Ledger Summary

**New exported `MpcTrace` JuMP-free ledger (mirrors `AdmmResiduals` verbatim) recording per-step published DADP, step-to-step price jump, cumulative day-ahead deviation, and certificate/fallback status, with three permanent `@testitem`s pinning `record!`'s exact signature for Wave 3/4's `mpc_loop.jl`.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-08-09T09:31:06-03:00 (base commit)
- **Completed:** 2026-08-09T09:37:06-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments
- `MpcTrace` struct + `record!` + `max_jump`/`mean_jump`/`any_cert_failed`, exported and wired into `TSODSO.jl` and `docs/src/api.md`.
- The `_assert_sequential` fail-loud guard reimplemented locally (file-disjoint from `admm/residuals.jl`, per the project's established seam convention), matching `AdmmResiduals`'s contract exactly (double-record or skipped-step both throw `ArgumentError`).
- Three permanent `@testitem`s (empty-ledger defaults, sequential-k guard, hand-verified derived metrics across 4 steps) covering the T-21-04/T-21-05 threat-register mitigations.

## Task Commits

Each task was committed atomically:

1. **Task 1: MpcTrace struct + record! + query predicates** - `38a6792` (feat)
2. **Task 2: Permanent @testitem coverage for MpcTrace** - `84eef0a` (test)

_Note: no TDD red/green split — plan marked `tdd="true"` on Task 1 but this is a from-scratch
new-file seam with no pre-existing behavior to red/green against; the task's `<verify>` inline
script served the same role as a RED gate (it failed before the file existed) and the single
`feat` commit lands the passing implementation directly, matching the established `AdmmResiduals`
precedent (`06-01`) which also has no separate red/green commit split._

## Files Created/Modified
- `src/models/mpc_trace.jl` - `MpcTrace` mutable struct (`dadp_trace`, `dadp_da_trace`, `jump_trace`, `cum_deviation_trace`, `cert_status_trace`, `steps`), `MpcTrace()`, local `_assert_sequential`, `record!(trace, k, dadp, dadp_da, cert_status)`, `max_jump`, `mean_jump`, `any_cert_failed`; exports all five public names.
- `test/test_mpc_trace.jl` - 3 `@testitem`s: empty-ledger predicates, sequential-k fail-loud guard, and N-step derived-metric correctness (distinguishing `:cert_failed` from `:local_ac_dual`).
- `src/TSODSO.jl` - one new `include("models/mpc_trace.jl")` line after `models/ac_dual_fallback.jl`, before the `pricing/` block.
- `docs/src/api.md` - new `## MPC / Rolling-Horizon` `@autodocs` section (`Pages = ["models/mpc_trace.jl"]`) inserted after `## ADMM Decomposition`, before `## Diagnostics`.

## Decisions Made
- `record!`'s exact signature is `record!(trace::MpcTrace, k::Integer, dadp::Real, dadp_da::Real, cert_status::Symbol) -> MpcTrace` — pinned verbatim for Wave 3/4's `mpc_loop.jl` call sites.
- `MpcTrace`'s final field list (in struct-definition order): `dadp_trace::Vector{Float64}`, `dadp_da_trace::Vector{Float64}`, `jump_trace::Vector{Float64}`, `cum_deviation_trace::Vector{Float64}`, `cert_status_trace::Vector{Symbol}`, `steps::Int`.
- `any_cert_failed` treats ONLY the literal `:cert_failed` symbol as a failure; any other symbol (e.g. `:certified_convex_dual`, `:local_ac_dual`) is not a failure, per D-04's fallback-ladder semantics — pinned by a dedicated `@testitem` assertion (T-21-05 mitigation).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's own inline `<verify>` scripts used floating-point-fragile `==` where `≈` (isapprox) is required**
- **Found during:** Task 1's `<verify>` inline script (`t.jump_trace == [0.0, 0.3]`)
- **Issue:** The plan's task-level `<verify>` and `<behavior>` blocks specify exact `==` equality between computed `Float64` values (e.g. `abs(5.3 - 5.0)`) and float literals (e.g. `0.3`). In standard IEEE 754 double-precision arithmetic, `abs(5.3 - 5.0) == 0.2999999999999998 ≠ 0.3` — the exact-equality assertion is a floating-point representation bug baked into the verify script itself, not a defect in the implementation (the implementation follows the plan's stated arithmetic formula for `jump`/`cum` exactly, verbatim). The same issue reproduces for every derived-float assertion in Task 2's inline script (`0.4` vs `0.40000000000000036`, `0.3` vs `0.2999999999999998`).
- **Fix:** Confirmed correctness of the implementation by re-running both inline `<verify>` scripts with `≈` (isapprox) in place of `==` for all derived-`Float64`-vector/scalar comparisons — both print `OK`. Wrote the PERMANENT `test/test_mpc_trace.jl` using `≈` for every derived-float assertion (never `==` on a computed `Float64`), so the checked-in test suite does not carry the same latent flakiness forward. Exact `==` is retained only for genuinely exact values (`Int` fields, `Symbol` vectors, unmodified input literals like `t.dadp_trace == [5.0]` in the guard test, which are stored verbatim with no arithmetic applied).
- **Files modified:** `test/test_mpc_trace.jl` (written with `≈`, no plan file touched)
- **Verification:** Both corrected inline scripts print `OK`; `test/test_mpc_trace.jl`'s 3 `@testitem`s are internally consistent with `≈`-based assertions (permanent-test execution itself deferred to Wave 2/phase-closing 21-06 per this plan's own `<verification>` note — TestItemRunner is not run under `--project=.` in this plan per the orchestrator's tooling note).
- **Committed in:** `84eef0a` (Task 2's commit; the implementation itself, `38a6792`, required no code change — only the verify invocation used `≈`)

---

**Total deviations:** 1 auto-fixed (Rule 1 — verification-script floating-point bug, not an implementation bug).
**Impact on plan:** No scope creep. `src/models/mpc_trace.jl`'s arithmetic is implemented exactly as the plan's `<action>` specifies; only the equality operator used when *checking* the float results (in the inline verify invocation and in the permanent test file) was corrected from `==` to `≈`.

## TDD Gate Compliance

Task 1 was frontmatter-marked `tdd="true"`, but its `<action>` block specifies a single
from-scratch file build (struct + `record!` + query predicates) with an inline `<verify>`
script rather than a separate persistent RED test file — there is no `test(21-02): ...` commit
preceding `38a6792`'s `feat(21-02): ...`. This mirrors the established project precedent for
this exact trace-struct convention: `AdmmResiduals` itself (plan `06-01`) has no separate
RED/GREEN commit split either. The inline `<verify>` script served the RED-gate role (it would
fail against a nonexistent file) and Task 2 (not `tdd`-flagged) supplies the permanent,
checked-in `@testitem` coverage in its own commit (`84eef0a`). No plan or requirements gap
results — flagging here per the executor's gate-sequence validation protocol.

## Issues Encountered
None beyond the floating-point verify-script deviation documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
`MpcTrace` is exported, documented, and permanently tested — ready for Wave 2's window builder
(`mpc_window.jl`) and Wave 3/4's orchestrator (`mpc_loop.jl`) to call `record!` directly with the
signature pinned above. No blockers.

---
*Phase: 21-mpc-rolling-horizon-real-time-pricing*
*Plan: 02*
*Completed: 2026-08-09*
