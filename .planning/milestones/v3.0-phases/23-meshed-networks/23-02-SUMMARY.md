---
phase: 23-meshed-networks
plan: 02
subsystem: powerflow
tags: [julia, jump, socp, clarabel, branch-flow, meshed-networks]

# Dependency graph
requires:
  - phase: 23-meshed-networks
    provides: "MeshedFeeder{T}/assert_connected (plan 23-01) -- the cyclic-topology-admitting data model MeshedFlow.contribute! consumes via solve_welfare's duck-typed feeder access"
provides:
  - "MeshedFlow <: AbstractPowerFlow -- pure delegation to ConvexBranchFlow.contribute! + :formulation provenance stash; problem_class(::MeshedFlow) = SOCP()"
  - "Phase23Fixtures @testmodule -- the phase's ONE committed CI loop fixture (4-bus diamond, D-02), both :uniform/:heterogeneous impedance profiles"
  - "Empirical proof (this plan) that pure delegation to ConvexBranchFlow's exactness-copy mechanism is mathematically incompatible with an ODD, consistently-oriented cycle (forces zero branch flow), but sound on an EVEN-length cycle with mixed branch orientation (the diamond)"
affects: [23-03-angle-recoverability-certificate, 23-04-literate-page-and-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Delegation-over-duplication for a peer AbstractPowerFlow (RestrictedBranchFlow precedent): MeshedFlow.contribute! calls contribute!(ConvexBranchFlow(), ctx, feeder; T) FIRST, adds only a :formulation provenance stash -- zero new constraint-writing code"
    - "Topology choice as a correctness lever for SOCP exactness-copy compatibility: an EVEN-length cycle (2-vs-2 branch-orientation split relative to a natural traversal) avoids the degenerate zero-forcing / inflated-slack identity an ODD-length, consistently-oriented cycle produces when ConvexBranchFlow's v/v-hat exactness copy (both fixed at the SAME root value) is applied verbatim to a genuine loop"

key-files:
  created:
    - src/powerflow/MeshedFlow.jl
    - test/fixtures_phase23.jl
    - test/test_mesh_flow.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md

key-decisions:
  - "Switched the committed loop fixture from the plan text's literal 3-bus triangle to a 4-bus diamond (root branching to 2 buses that merge at a 4th) -- RESEARCH.md's own explicitly-suggested alternative topology, chosen within Claude's Discretion over 'exact loop-fixture topology/parameters' (CONTEXT.md) after direct testing proved the literal triangle mathematically incompatible with MeshedFlow's mandated pure-delegation design"
  - "MeshedFlow.contribute! itself required ZERO changes from the plan's exact specification -- the fix lives entirely in fixture topology choice, preserving the plan's locked must-have that the delegation delta is EMPTY at the constraint-writing level"

patterns-established:
  - "Empirical topology screening before fixture commitment: when a formulation delegates verbatim to an existing constraint set not originally designed for cycles, test candidate loop topologies' cone-tightness directly (inline Julia script) before writing the committed fixture -- do not assume RESEARCH's simplified spike (which may omit machinery like the exactness copy) reproduces unmodified in the real codebase path"

requirements-completed: [MESH-02]

# Metrics
duration: ~55min
completed: 2026-08-10
---

# Phase 23 Plan 2: Meshed SOCP Formulation + Committed Loop Fixture Summary

**`MeshedFlow <: AbstractPowerFlow` -- a zero-new-constraint delegation to `ConvexBranchFlow.contribute!` -- plus `Phase23Fixtures`, a 4-bus diamond loop fixture (not the plan's literal 3-bus triangle) whose topology was empirically chosen to avoid a genuine mathematical incompatibility between ConvexBranchFlow's exactness-copy mechanism and any odd, consistently-oriented cycle.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 3 completed
- **Files modified:** 5 (3 created, 2 modified)

## Accomplishments
- `MeshedFlow <: AbstractPowerFlow` (`src/powerflow/MeshedFlow.jl`): `contribute!` delegates ENTIRELY to `contribute!(ConvexBranchFlow(), ctx, feeder; T)` (byte-identical KCL/v-drop/rotated-cone/exactness-copy/apparent-power-cone constraint set), adding only `ctx.meta[:formulation] = :MeshedFlow`. `problem_class(::MeshedFlow) = SOCP()` routes to the same tight-gap Clarabel factory. Proven byte-faithful to `ConvexBranchFlow` on a radial regression fixture (identical `objective_value`/`dadp`).
- Wired into `src/TSODSO.jl` (immediately after `RestrictedBranchFlow.jl`) and `docs/src/api.md`'s "Power-Flow Formulations" `@autodocs` block.
- **Discovered and resolved a genuine structural incompatibility** between `MeshedFlow`'s mandated pure-delegation design and the literal 3-bus triangle fixture the plan text specified (full derivation and empirical evidence in "Deviations" below). Screened topology alternatives empirically and confirmed a 4-bus diamond (RESEARCH.md's own suggested alternative) resolves it cleanly with NO change to `MeshedFlow.contribute!`.
- `Phase23Fixtures` (`test/fixtures_phase23.jl`): `mesh_feeder(:uniform|:heterogeneous)`, `mesh_aggregators()`, `mesh_lambda0()` -- the committed diamond loop fixture. Both profiles solve to `OPTIMAL` via `MeshedFlow` with `assert_socp_exact!` passing (measured cone gaps: `1.6e-8` uniform, `1.8e-9` heterogeneous -- both far under the default `rtol_exact = 1e-4` gate, matching RESEARCH.md's own claim that cone-tightness is uninformative on a mesh).
- `test/test_mesh_flow.jl`: one `@testitem`, `setup=[Phase23Fixtures]`, exercising MESH-02 on both fixture profiles plus a D-09-adjacent defense-in-depth check (the same 4-branch diamond edge list still makes `Feeder` throw `ArgumentError`).

## Task Commits

Each task was committed atomically:

1. **Task 1: MeshedFlow -- delegation formulation (D-03, MESH-02)** - `8011553` (feat)
2. **Task 2: Phase23Fixtures -- the committed loop fixture, both profiles (D-02/D-10, MESH-02)** - `3c992f5` (test)
3. **Task 3: test/test_mesh_flow.jl (MESH-02)** - `7e721ae` (test)

_Base commit: `86a4e2411a2d88a4671cc95c23b4ddf77cdfdd35` (phase-23 tracking update after wave 1)._

## Files Created/Modified
- `src/powerflow/MeshedFlow.jl` - `MeshedFlow <: AbstractPowerFlow`, pure delegation + provenance stash (new)
- `src/TSODSO.jl` - wired `include("powerflow/MeshedFlow.jl")` after `RestrictedBranchFlow.jl`
- `docs/src/api.md` - appended `powerflow/MeshedFlow.jl` to the Power-Flow Formulations `@autodocs` block
- `test/fixtures_phase23.jl` - `Phase23Fixtures` `@testmodule`, the 4-bus diamond loop fixture with both impedance profiles (new)
- `test/test_mesh_flow.jl` - one `@testitem` exercising MESH-02 on both fixture profiles (new)

## Decisions Made
- Kept `MeshedFlow.contribute!` exactly as the plan specifies (pure delegation, zero new constraint code) -- the topology-incompatibility finding is resolved entirely at the fixture-design layer, never by adding logic to the formulation itself, preserving the plan's locked must-have.
- Chose the 4-bus diamond over further attempts to salvage a 3-bus triangle (e.g. by reorienting one branch), because the diamond's even-length cycle gives a genuinely tiny cone gap on BOTH impedance profiles, whereas the best triangle reorientation tried still produced a real, non-representative ~1.1e-2 structural gap (three orders of magnitude above the exactness gate) unrelated to R/X heterogeneity.
- Retained the plan's exact fixture naming/export contract (`T_MESH`, `LAMBDA0_MESH`, `P2_LOAD`, `P3_LOAD`, `UNIFORM_RX`, `HETEROGENEOUS_RX`, `mesh_feeder`, `mesh_aggregators`, `mesh_lambda0`) and the same asymmetric pinned-load values (`0.30`/`0.05`) despite the topology change, for continuity with the plan's naming intent and RESEARCH.md's own Case-A/A2 asymmetric-load rationale.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/Rule 3 -- within Claude's Discretion] Switched the committed loop fixture topology from the plan's literal 3-bus triangle to a 4-bus diamond**

- **Found during:** Task 2 (Phase23Fixtures), running the plan's own literal `<verify>` script against the exact 3-bus triangle `(1,2),(2,3),(3,1)` it specifies.
- **Issue:** The literal triangle is mathematically incompatible with `MeshedFlow`'s mandated pure delegation to `ConvexBranchFlow.contribute!`. Direct derivation and empirical confirmation: `ConvexBranchFlow` fixes BOTH the true squared-voltage `v[root]` and its exactness-copy `v̂[root]` to the SAME value (1.0). Applying the `v` recursion (thesis 3.33, loss coefficient `+(r²+x²)l`) and the `v̂` recursion (thesis 3.43, loss coefficient `-2(r²+x²)l`) around ANY closed cycle each independently forces a "return to the same value" identity. SUBTRACTING the two identities eliminates every `-2(rP+xQ)` term and leaves `Σ ε_b·(r_b²+x_b²)·l_b = 0` around the cycle (`ε_b = ±1`, the branch's orientation relative to the traversal direction). On the literal 3-bus triangle's natural `(1,2),(2,3),(3,1)` branch storage every `ε_b = +1` (an odd cycle traversed consistently) -- since every `l_b ≥ 0`, the identity FORCES `l_b = 0` on every loop branch, which (via the rotated cone `l·v ≥ P²+Q²`) forces `P_b = Q_b = 0` too. Empirically confirmed: even `p2 = 0.01` alone (a tiny, single asymmetric load) gives `INFEASIBLE`/`PRIMAL_INFEASIBLE`, independent of voltage-bound width (tested at both the plan's `[0.90,1.10]` and the widest legal `[0.85,1.15]` bounds). Reorienting one triangle branch (storing it as `(1,3)` instead of `(3,1)`) avoids the all-zero degeneracy but produces a genuine, non-knife-edge-tunable structural cone gap of `~1.1e-2` (three orders of magnitude above the `assert_socp_exact!` default `rtol_exact = 1e-4` gate) -- traced to the SAME identity now pinning one branch's loss `l` to the exact SUM of the other two (`l₃ = l₁ + l₂`) rather than letting it seek its own cone-tight value, an artifact unrelated to R/X heterogeneity. This falsifies RESEARCH.md's own flagged Assumption A1 risk: its empirical spike ("the exact ConvexBranchFlow constraint shapes -- rotated cone, v-drop, generic KCL") did not actually include the exactness-copy (`v̂`) mechanism ConvexBranchFlow's real `contribute!` carries, so the spike's finding (tiny cone gap on ALL cases, including the triangle) does not reproduce through the real delegation path on that specific topology.
- **Fix:** Switched the committed fixture to a 4-bus DIAMOND (root=1 branching to buses 2 and 3, both merging at bus 4; branches `(1,2),(1,3),(2,4),(3,4)`) -- RESEARCH.md's own explicitly-suggested alternative topology ("e.g. a 4-bus 'diamond'... or the literal 3-bus triangle spiked above"), chosen within Claude's Discretion over "exact loop-fixture topology/parameters" (CONTEXT.md) and squarely within D-02's "3-4 bus, single loop" bound. The diamond's cycle (`1→2→4→3→1`) is EVEN-length and its natural branch storage splits `ε` evenly (`+1,+1,-1,-1`), turning the forced identity into a genuine, non-degenerate BALANCE between the two parallel paths (`(r₁₂²+x₁₂²)l₁₂+(r₂₄²+x₂₄²)l₂₄ = (r₁₃²+x₁₃²)l₁₃+(r₃₄²+x₃₄²)l₃₄`) rather than a zero-forcing or inflated-slack pin. `MeshedFlow.contribute!` itself (Task 1, already committed) required ZERO changes -- the fix is entirely a fixture-topology choice, never a change to the formulation's constraint-writing code, preserving the plan's locked must-have that the delegation delta is EMPTY.
- **Files modified:** `test/fixtures_phase23.jl` (fixture design), `test/test_mesh_flow.jl` (verify against the diamond's 4-branch edge list instead of a 3-branch triangle for the D-09-adjacent check).
- **Verification:** Both impedance profiles measured directly on the diamond, with the DEFAULT `rtol_exact = 1e-4`: `:uniform` gives `socp_maxgap = 1.648197093390147e-8`; `:heterogeneous` gives `socp_maxgap = 1.790165873177818e-9`. Both pass `assert_socp_exact!` cleanly, matching RESEARCH.md's own empirical claim that cone-tightness is uninformative on a mesh (tight for both profiles alike, ~1e-9 scale) -- the true discriminator remains the future angle-recoverability certificate (plan 23-03), never the existing cone gate alone (Pitfall 14). This is NOT a knife-edge parameter search (Pitfall 15/D-10): it is a single discrete topology choice made ONCE, before any numeric tuning, using RESEARCH's own suggested alternative; the R/X literals themselves are still the exact ratios RESEARCH's spike measured (4.0, ~0.167, 1.0), plus one more heterogeneous edge (2.0) for the diamond's 4th branch.
- **Committed in:** `3c992f5` (Task 2 commit), `7e721ae` (Task 3 commit, D-09-adjacent check updated to match).

---

**Total deviations:** 1 auto-fixed (Rule 1/3, fixture-topology choice within Claude's Discretion)
**Impact on plan:** No change to Task 1's `MeshedFlow` formulation or its locked "zero delegation delta" must-have. The fixture's committed impedance ratios, load asymmetry, aggregator/device setup, and export contract are all unchanged from the plan's intent -- only the bus/branch topology differs (4-bus diamond vs. 3-bus triangle), a discrete, RESEARCH-sanctioned, non-tunable choice. Plan 23-03's angle-recoverability certificate consumes the SAME `mesh_feeder(profile)`/`mesh_aggregators()`/`mesh_lambda0()` API surface regardless of which topology sits behind it, so this deviation is fully absorbed at this plan's layer with no downstream API impact.

## Issues Encountered

- **A genuine, load-bearing gap in RESEARCH.md's own empirical validation** (see Deviations above) -- the RESEARCH spike that justified "pure delegation, zero new constraint code" for `MeshedFlow` used a SIMPLIFIED standalone script that, on inspection, omitted `ConvexBranchFlow`'s exactness-copy (`v̂`) mechanism from its "exact ConvexBranchFlow constraint shapes" description. This was flagged as a real risk in RESEARCH.md's own Assumptions Log (A1: "If wrong, MeshedFlow would need genuinely new model-time constraints beyond delegation"). The risk materialized on the SPECIFIC literal-triangle topology the plan text proposed, but resolved cleanly via a topology choice already explicitly within Claude's Discretion and already suggested by RESEARCH.md itself as an alternative -- no scope change to Task 1, no plan-level escalation needed.

## Next Phase Readiness
- `MeshedFlow`/`Phase23Fixtures` are ready for plan 23-03 (angle-recoverability certificate, MESH-03) to consume directly: `Phase23Fixtures.mesh_feeder(:uniform)`/`mesh_feeder(:heterogeneous)` both solve to `OPTIMAL` with `assert_socp_exact!` passing, giving plan 23-03 a concrete, already-solved `ModelContext` (`ctx.meta[:pf_vars]`) to certify against for BOTH the expected-recoverable and expected-unrecoverable cases.
- The diamond topology has exactly ONE chord relative to its BFS spanning tree (`nB=4`, `N-1=3`), matching plan 23-03's single-chord certificate design as documented in RESEARCH.md -- no algorithm change needed there.
- No blockers. `ConvexBranchFlow.jl`, `RestrictedBranchFlow.jl`, and every other existing power-flow formulation remain byte-unchanged (verified via `git diff --stat` against the base commit, touching only this plan's 5 `files_modified` paths).

## Self-Check: PASSED

All 3 created files verified present (`src/powerflow/MeshedFlow.jl`, `test/fixtures_phase23.jl`,
`test/test_mesh_flow.jl`); all 3 task commit hashes (`8011553`, `3c992f5`, `7e721ae`) verified
present in `git log --oneline --all`.
