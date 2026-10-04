---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 01
subsystem: powerflow / data
tags: [AbstractFeeder, traits, formulation-validity, ARCH-03, ARCH-07]
requires: []
provides:
  - AbstractFeeder{T} supertype for Feeder and MeshedFeeder
  - has_reactive / has_branch_current formulation traits
  - internal _contribute_convex! shared SOCP body
  - ArgumentError on invalid formulation x MeshedFeeder pairs
affects: [33-02, 33-04]
key-files:
  created: [test/test_abstract_feeder.jl]
  modified:
    - src/data/Feeder.jl
    - src/data/MeshedFeeder.jl
    - src/TSODSO.jl
    - src/powerflow/AbstractPowerFlow.jl
    - src/powerflow/DCPowerFlow.jl
    - src/powerflow/LinDistFlow.jl
    - src/powerflow/ConvexBranchFlow.jl
    - src/powerflow/RestrictedBranchFlow.jl
    - src/powerflow/MeshedFlow.jl
    - src/powerflow/ACPowerFlow.jl
decisions:
  - ConvexBranchFlow, RestrictedBranchFlow and LinDistFlow throw ArgumentError on MeshedFeeder; DC, AC and MeshedFlow remain valid on both feeder types
  - Exactly one branch-current trait (no separate SOCP-exactness trait)
metrics:
  tasks: 3
  files: 11
completed: 2026-10-03
---

# Phase 33 Plan 01: AbstractFeeder, traits, invalid-pair errors Summary

`AbstractFeeder{T}` now supertypes `Feeder` and `MeshedFeeder`. The `has_reactive` and `has_branch_current` traits exist. `RestrictedBranchFlow`, `ConvexBranchFlow` and `LinDistFlow` now throw a named `ArgumentError` on a `MeshedFeeder`.

## Tasks

1. `d5460c0` - `AbstractFeeder` supertype, the two traits, and `AbstractPowerFlow.jl` included before `core/ModelContext.jl`.
2. `b065b3d` - the internal `_contribute_convex!` body, with the three invalid-pair throwing methods. `MeshedFlow` and `RestrictedBranchFlow` now call `_contribute_convex!` instead of the public `contribute!(ConvexBranchFlow(), ...)`.
3. `e4cc8df` - `test/test_abstract_feeder.jl` with 3 testitems: subtype and constructor gates, invalid and valid pairs, trait truth tables including agreement with `haskey(ctx.residuals, :Rq)`.

## Verification

Nine TestItemRunner files ran with 201 passes and 0 failures. They were `test_abstract_feeder`, `test_feeder`, `test_mesh_feeder`, `test_convex_branch_flow`, `test_mesh_flow`, `test_restricted_branch_flow`, `test_powerflow`, `test_ac_powerflow` and `test_mesh_angle_certificate`. I did not run the full suite. The `contribute!` bodies moved unchanged, so the goldens are untouched.

## Deviations from Plan

**1. [Rule 1 - Bug] `_contribute_convex!` takes `pf` as its first argument.**
- **Found during:** Task 2.
- **Issue:** The plan gave the signature `_contribute_convex!(ctx, feeder; T)`. The body reads `pf.thesis_literal`, so keeping the body byte-for-byte unchanged requires `pf`.
- **Fix:** The signature is `_contribute_convex!(pf::ConvexBranchFlow, ctx, feeder; T)`. `MeshedFlow` and `RestrictedBranchFlow` pass `ConvexBranchFlow()`, which matches the previous delegation behaviour.
- **Commit:** `b065b3d`

## Known Stubs

None.

## Self-Check: PASSED
