---
phase: 23-meshed-networks
plan: 01
subsystem: data
tags: [julia, jump, sparsearrays, graph-topology, feeder-data-model]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "Feeder{T}/Bus{T}/Branch{T} (data/Feeder.jl) and assert_radial (data/topology.jl) -- the radial data model this plan generalizes alongside"
provides:
  - "MeshedFeeder{T} -- a separate, immutable feeder struct admitting a genuinely cyclic topology (nB > N-1)"
  - "assert_connected(buses, branches, root) -> SparseMatrixCSC -- assert_radial's checks 2-6 minus the tree-count theorem"
  - "Wired includes in TSODSO.jl + docs/src/api.md Network Data Model @autodocs block"
affects: [23-02-meshed-flow, 23-03-angle-recoverability-certificate, 23-04-literate-page-and-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Validator-minus-one-check generalization: assert_connected is assert_radial with exactly the tree-specific edge-count theorem dropped, every other check (root range, positional convention, endpoint range, BFS connectivity, single-root, root/is_root agreement) kept verbatim"
    - "Separate-struct-same-shape: MeshedFeeder duck-types identically to Feeder (buses/branches/root) by reusing Bus/Branch as-is, never subtyping or wrapping Feeder"

key-files:
  created:
    - src/data/mesh_topology.jl
    - src/data/MeshedFeeder.jl
    - test/test_mesh_feeder.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md

key-decisions:
  - "assert_connected returns the same N x B sparse incidence matrix assert_radial does, for interface parity, even though MeshedFeeder's constructor discards it (validation-only use, matching Feeder's own convention)"
  - "Error messages reworded from assert_radial's 'Non-radial feeder: ...' to mesh-appropriate phrasing ('Disconnected mesh feeder: ...' / 'Malformed mesh feeder: ...') since the failure being described is no longer 'not a tree'"

patterns-established:
  - "D-01/D-09 lock discipline: a new topology regime (mesh) gets its own validator + struct rather than modifying or subclassing the existing radial one; a same-input regression test (Feeder throws / MeshedFeeder succeeds) proves the original gate was never weakened"

requirements-completed: [MESH-01]

# Metrics
duration: ~20min
completed: 2026-08-10
---

# Phase 23 Plan 1: MeshedFeeder Data-Layer Foundation Summary

**`MeshedFeeder{T}` -- a Feeder-shaped struct gated by a new `assert_connected` validator that accepts genuinely cyclic topologies (`nB > N-1`) while `Feeder`/`assert_radial` stay byte-unchanged.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3 completed
- **Files modified:** 5 (3 created, 2 modified)

## Accomplishments
- `assert_connected(buses, branches, root) -> SparseMatrixCSC` in `src/data/mesh_topology.jl`: `assert_radial`'s checks 2-6 kept verbatim, check 1 (the `B == N-1` edge-count theorem) dropped, so a 3-bus triangle (`nB=3 > N-1=2`) is accepted.
- `MeshedFeeder{T}` in `src/data/MeshedFeeder.jl`: mirrors `Feeder`'s exact field shape (`buses`, `branches`, `root`), reuses `Bus`/`Branch` verbatim, gated by `assert_connected` + `assert_magnitudes` instead of `assert_radial` + `assert_magnitudes`. A wholly separate struct -- never a subtype or field of `Feeder`.
- D-09 regression proven directly: the identical 3-branch triangle edge list makes `Feeder(...)` throw `ArgumentError` while `MeshedFeeder(...)` succeeds -- the radial gate was never weakened to admit meshes.
- Wired `src/TSODSO.jl` (new includes immediately after `data/topology.jl`) and `docs/src/api.md` (`MeshedFeeder.jl`/`mesh_topology.jl` appended to the Network Data Model `@autodocs` `Pages` list).
- `test/test_mesh_feeder.jl`: one `@testitem` covering the shared structural cases (root range, positional convention, endpoint range, disconnected graph, zero/two roots, root/is_root mismatch), the new cyclic-accept case, the D-09 regression, and a duck-typing check.

## Task Commits

Each task was committed atomically:

1. **Task 1: assert_connected -- the mesh-topology validator** - `f775fd5` (feat)
2. **Task 2: MeshedFeeder + wiring** - `9cff3ca` (feat)
3. **Task 3: test/test_mesh_feeder.jl** - `b84b924` (test)

_Base commit: `dd96dfe8776623ad218c3d54d4bdefddbc487b94` (phase-23 plan creation)._

## Files Created/Modified
- `src/data/mesh_topology.jl` - `assert_connected` mesh-topology validator (new)
- `src/data/MeshedFeeder.jl` - `MeshedFeeder{T}` struct + outer constructor (new)
- `src/TSODSO.jl` - wired `include("data/mesh_topology.jl")` / `include("data/MeshedFeeder.jl")` after `data/topology.jl`
- `docs/src/api.md` - appended `data/MeshedFeeder.jl`/`data/mesh_topology.jl` to the Network Data Model `@autodocs` block
- `test/test_mesh_feeder.jl` - one `@testitem` (MESH-01/D-09 regression), new

## Decisions Made
- Kept `assert_connected`'s return contract (`SparseMatrixCSC`) identical to `assert_radial`'s for interface parity, even though `MeshedFeeder`'s constructor only uses it for validation (discards the returned matrix), matching `Feeder`'s own convention.
- Reworded error messages from "Non-radial feeder: ..." to "Disconnected mesh feeder: ..." / "Malformed mesh feeder: ..." since a mesh's failure mode is no longer "not a tree."

## Deviations from Plan

None - plan executed exactly as written. All three tasks' files, structs, and wiring match the plan's `must_haves` and `<action>` specifications verbatim.

## Issues Encountered

- **Worktree base-drift caught and corrected before any task commit was finalized on the wrong base.** The initial `<worktree_branch_check>` setup command (a multi-line compound script) was rejected by the sandbox as "too complex to verify," and I incorrectly proceeded without re-running the simpler equivalent checks. This left the worktree HEAD on a stale ancestor commit (`baaa94f`, pre-Phase-19) instead of the mandated `dd96dfe8776623ad218c3d54d4bdefddbc487b94` (which includes Phases 19-22 + Phase 23 planning docs). I built and committed all 3 tasks once on the wrong base, discovered the drift via a `git diff --stat` sanity check against the mandated base commit (it showed spurious deletions of Phase-19/20/21/22 source files that should never have been touched by this plan), verified HEAD was still on the correct per-agent branch (`worktree-agent-a8e4761697360e42b`, not a protected ref), then ran `git reset --hard dd96dfe8776623ad218c3d54d4bdefddbc487b94` (sanctioned recovery per the `<worktree_branch_check>` step, since HEAD was never on a protected branch) and re-executed all 3 tasks from scratch against the correct base. Final `git diff --stat` against `dd96dfe8...` now shows exactly the plan's 5 `files_modified` paths and nothing else. No project code was lost (the stale-base commits only ever existed on this same per-agent branch, which was reset before any push).

## Next Phase Readiness
- `MeshedFeeder`/`assert_connected` are ready for plan 23-02 (`MeshedFlow`, the SOCP formulation over a `MeshedFeeder`) and plan 23-03 (angle-recoverability certificate) to consume directly -- `solve_welfare`'s duck-typed feeder access works unmodified since `MeshedFeeder` exposes the identical `buses`/`branches`/`root` shape.
- No blockers. `Feeder`/`assert_radial`/`data/topology.jl` remain byte-unchanged (verified via `diff` against the base commit before any edits), so no existing radial-fixture code path is at risk.
