---
phase: 04-convex-branch-flow-correctness-milestone
plan: 02
subsystem: powerflow
tags: [jump, socp, clarabel, distflow, rotated-second-order-cone, branch-flow, exactness-copy, lindistflow]

# Dependency graph
requires:
  - phase: 04-01
    provides: problem_class(::AbstractPowerFlow)=QP() generic trait + SOCP() problem class + RED socp/conformance @testitems
  - phase: 02-02
    provides: LinDistFlow.jl contribute! pattern (variable creation, root fix, squared bounds, vdrop, :Rp/:Rq inflow/outflow loop, pf_vars stash)
  - phase: 03-05
    provides: solve_welfare (GLB-CVX) accepting any AbstractPowerFlow as pf, closing :Rq only when the formulation provides it
provides:
  - "ConvexBranchFlow <: AbstractPowerFlow: SOCP DistFlow relaxation + LinDistFlow exactness copy (thesis eqs 3.31-3.45)"
  - "Rotated SOC cone [0.5*l, v_from, P, Q] in RotatedSecondOrderCone() => l*v >= P^2+Q^2 (3.39)"
  - "Exactness copy: aux v̂ per bus + affine V^2 bounds on both v and v̂ (3.45) + copy drop (3.43)"
  - "Affine loss terms -r*l/-x*l charged at the child node in :Rp/:Rq (3.31/3.32)"
  - "problem_class(::ConvexBranchFlow)=SOCP() routing (tight-gap Clarabel factory)"
  - "pf_vars=(;v,v̂,P,Q,l) stash exposing :l for the PF-04 exactness gate (04-05)"
  - "Three-way DC/LinDistFlow/SOCP zero-edit interchange conformance"
affects: [04-05 exactness gate (reads pf_vars.l), 04-03 ieee13 fixture (feeds ConvexBranchFlow), 04-06 ground truth, Phase 5 prices, Phase 6 ADMM]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Drop-in AbstractPowerFlow subtype by dispatch only (no if formulation ==)"
    - "SOC relaxation via JuMP RotatedSecondOrderCone with mandatory 0.5*l factor"
    - "Single-aux-v̂ LinDistFlow exactness copy (P̂/Q̂ expanded inline, no extra flow vars)"
    - "Affine loss terms flow through the existing add_to_residual! seam unchanged"

key-files:
  created: []
  modified:
    - src/powerflow/ConvexBranchFlow.jl
    - test/test_conformance.jl

key-decisions:
  - "Apparent-power limit (3.36) skipped at/above the 99.0 pu no-limit sentinel; applied only where a real limit exists (RESEARCH Open Q2 / Assumption A7)"
  - "problem_class(::ConvexBranchFlow)=SOCP() placed in ConvexBranchFlow.jl (per plan), sharing the trait function with the 04-01 generic by name across the module"
  - "Conformance SOCP arm strengthened to a full three-way (DC/LinDistFlow/SOCP) zero-edit swap rather than a single SOCP solve"

patterns-established:
  - "Pattern: SOC cone = [0.5*l, v_from, P, Q] in RotatedSecondOrderCone() (0.5 factor mandatory)"
  - "Pattern: exactness copy = one v̂ per bus + bounds on both v and v̂; upper-bounding v̂ drives the cone tight"
  - "Pattern: losses (-r*l/-x*l) charged at the child node of the incoming branch"

requirements-completed: [PF-03]

# Metrics
duration: ~20min
completed: 2026-07-18
---

# Phase 4 Plan 02: SOCP Convex Branch Flow Summary

**ConvexBranchFlow — the DistFlow SOC relaxation (rotated cone `l·v ≥ P²+Q²`) with the LinDistFlow exactness copy (aux `v̂` + affine V² bounds, thesis 3.43/3.45) — as a drop-in third AbstractPowerFlow subtype interchangeable with DC/LinDistFlow by dispatch alone.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-18
- **Completed:** 2026-07-18
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `ConvexBranchFlow <: AbstractPowerFlow` implementing thesis eqs 3.31–3.45: rotated SOC cone (3.39), true voltage drop with `+(r²+x²)·l` (3.33), copy drop (3.43), V² bounds on both `v` and `v̂` (3.45), forward apparent-power limit (3.36), and affine loss terms `−r·l`/`−x·l` in the `:Rp`/`:Rq` balances (3.31/3.32).
- The exactness copy (`v̂` + 3.45 bounds + 3.43 copy-drop) is built as part of the formulation — the half that drives the cone tight (exact) at the optimum, not decoration.
- `problem_class(::ConvexBranchFlow) = SOCP()` routes the cone to the tight-gap Clarabel factory; the model names no concrete solver.
- `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)` stashed — exposes `:l` for the Phase-4 exactness gate (04-05).
- Conformance strengthened to a genuine three-way DC↔LinDistFlow↔SOCP zero-edit swap (build feeder+aggregator once, call `solve_welfare` three times differing only in `pf`); all three solve with a finite objective and finite length-T DADP.
- `socp` @testitems 16/16 green; `conformance` @testitems 16/16 green; no formulation branching anywhere; no regression to any previously-passing test.

## Task Commits

Each task was committed atomically:

1. **Task 1: ConvexBranchFlow struct + contribute! (SOC cone + exactness copy, eqs 3.31–3.45)** - `d521028` (feat) — TDD GREEN against the RED socp @testitems authored in 04-01
2. **Task 2: DC↔LinDistFlow↔SOCP interchange conformance (crit 4, SOCP arm)** - `665c5cc` (test)

**Plan metadata:** committed separately with this SUMMARY.

_Note: the RED test commits (`test(...)`) for the socp/conformance items were authored in plan 04-01 (Wave 1); this plan supplied the GREEN implementation._

## Files Created/Modified
- `src/powerflow/ConvexBranchFlow.jl` - The SOCP DistFlow formulation + LinDistFlow exactness copy; `contribute!` dispatch; `problem_class(::ConvexBranchFlow)=SOCP()`; `export ConvexBranchFlow`.
- `test/test_conformance.jl` - SOCP-arm item extended to the full three-way DC/LinDistFlow/SOCP interchange; the original DC↔LinDistFlow closed-form item left unchanged.

## Decisions Made
- **Apparent-power limit gating:** applied `P²+Q² ≤ S²max` (3.36) only where `smax < 99.0` (the IEEE-13 fixture's no-limit sentinel), leaving interior branches unconstrained per RESEARCH Open Q2 / Assumption A7 (congestion is head-driven). Encoded as a file-local `_SMAX_NO_LIMIT = 99.0` constant with a traceable comment.
- **Trait method placement:** `problem_class(::ConvexBranchFlow)=SOCP()` lives in `ConvexBranchFlow.jl` (as the plan directs) even though the generic `(::AbstractPowerFlow)=QP()` lives in `solver/problem_class_trait.jl` (04-01); both add methods to the same `problem_class` function by name within `module TSODSO`, so dispatch resolves correctly regardless of include order.
- **Conformance breadth:** implemented the SOCP arm as a three-way loop (DC/LinDistFlow/SOCP) to fully satisfy Task 2's acceptance criterion, rather than the single SOCP call the RED stub contained.

## Deviations from Plan

None - plan executed exactly as written. (No Rule 1–4 deviations; no bugs, missing functionality, blocking issues, or architectural changes were encountered.)

## Issues Encountered
- **Test harness discovery / environment:** `julia --project=test -e '@run_package_tests …'` cannot resolve the `TSODSO` package (test/Project.toml does not dev the package) and, when invoked from the shared `.claude/worktrees/` tree, discovers sibling worktrees' test copies. Resolved by (a) verifying formulation behavior directly under `--project=.` and (b) running the authoritative `julia --project=. -e 'import Pkg; Pkg.test()'`, which sets up the package on the path and, being rooted at this worktree, discovers only this worktree's tests.

## Cross-Plan Test Status (NOT deviations, NOT regressions)
The authoritative full suite reports **499 passed, 7 failed, 0 errored**. All 7 failures are cross-plan integration tests that were RED before this plan (blocked on `isdefined(ConvexBranchFlow)`) and remain RED now because they depend on sibling Wave-2 plans still in progress — none are in this plan's files, and `git diff` confirms I touched only `ConvexBranchFlow.jl` and `test_conformance.jl`:
- `test_exactness.jl` (3) — blocked on `assert_socp_exact!` (`src/models/exactness.jl`, a comment-only stub owned by plan 04-05).
- `test_ieee13.jl` (3) — blocked on `ieee13_modified()` (`src/data/ieee13.jl`, a comment-only stub owned by plan 04-03).
- `test_oracle.jl` (1) — blocked on `operational_oracle` (`src/models/oracle.jl`, a comment-only stub owned by plan 04-04).

Implementing `ConvexBranchFlow` correctly advanced these items past their `isdefined` guard; they now block on the NEXT missing symbol from another plan. Expected parallel-execution state. Per the SCOPE BOUNDARY these are out of scope and were deliberately not touched (the orchestrator also forbade editing those files).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `pf_vars.l` is exposed, so the PF-04 exactness gate (04-05) can read `l·v` vs `P²+Q²`.
- The SOCP formulation is ready to be fed the IEEE-13 fixture (04-03) and cross-checked/ground-truthed (04-06).
- The three-way interchange contract confirms DC/LinDistFlow/SOCP are dispatch-interchangeable in `solve_welfare`.
- Blocker for the phase gate: sibling plans 04-03/04-04/04-05 must land before `test_ieee13.jl`/`test_oracle.jl`/`test_exactness.jl` go green (expected; not owned here).

## Self-Check: PASSED

- Files verified present: `src/powerflow/ConvexBranchFlow.jl`, `test/test_conformance.jl`, `.planning/phases/04-convex-branch-flow-correctness-milestone/04-02-SUMMARY.md`.
- Commits verified in git log: `d521028` (Task 1, feat), `665c5cc` (Task 2, test).
- Content markers verified in `ConvexBranchFlow.jl`: `RotatedSecondOrderCone`, the `0.5 * l` cone factor, and `problem_class(::ConvexBranchFlow) = SOCP()`.
- `socp` and `conformance` @testitems: 16/16 + 16/16 green via `Pkg.test()`; no regression to previously-passing tests.

---
*Phase: 04-convex-branch-flow-correctness-milestone*
*Completed: 2026-07-18*
