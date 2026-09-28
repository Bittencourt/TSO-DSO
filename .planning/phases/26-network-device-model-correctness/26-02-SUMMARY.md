---
phase: 26-network-device-model-correctness
plan: 02
subsystem: power-flow-modeling
tags: [jump, clarabel, socp, branch-flow, exactness, gan-low, distflow]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness (plan 01, if sequenced before)
    provides: N/A — this plan has no depends_on; wave 1, standalone
provides:
  - "ConvexBranchFlow(; thesis_literal=false) — the corrected default exactness-copy sign (v̂ ≥ v, Gan-Low direction)"
  - "ConvexBranchFlow(; thesis_literal=true) — explicit opt-in reproducing the literal, defective thesis eq. 3.43 formula"
  - "Documented verdict on thesis eq. 3.43 vs. Gan-Low (2015) in docs/literate/convex_branch_flow.jl"
  - "test/test_exactness_verdict.jl — permanent FIX-01 3-bus AC-feasible/SOCP-feasible/thesis-literal-infeasible regression"
affects: [26-03, 26-04, 26-05, 26-06, 27-integer-planning-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Opt-in defective/literal formulation retained via a boolean struct field + outer kwarg constructor (thesis_literal), mirroring RestrictedBranchFlow's ε-field precedent"

key-files:
  created:
    - test/test_exactness_verdict.jl
  modified:
    - src/powerflow/ConvexBranchFlow.jl
    - src/powerflow/RestrictedBranchFlow.jl
    - docs/literate/convex_branch_flow.jl
    - test/test_restricted_branch_flow.jl
    - test/test_convex_branch_flow.jl

key-decisions:
  - "Implemented FIX-01/02 via RESEARCH Option A (local per-branch sign flip inside cpydrop), not Option B (RestrictedBranchFlow's tree-based v̂_GL) — proven sufficient by telescoping-sum algebra, preserves ConvexBranchFlow's graph-generic (MeshedFlow-compatible) design, and keeps the :cpydrop container shape byte-identical so downstream consumers (MeshedFlow, RestrictedBranchFlow, DsoOpt, stochastic_welfare, decompose_dlmp) structurally resolve unchanged"
  - "decompose_dlmp's dual(:cpydrop) coefficient re-derivation is explicitly OUT of this plan's scope — threat T-26-03 in this plan's own threat_model assigns that mitigation to Plan 26-06, sequenced after; this plan's only DLMP-relevant obligation (keeping the constraint container shape unchanged) is satisfied"

requirements-completed: [FIX-01, FIX-02]

# Metrics
duration: ~25min
completed: 2026-09-28
---

# Phase 26 Plan 02: ConvexBranchFlow Exactness-Copy Sign Fix (FIX-01/02) Summary

**Flipped `ConvexBranchFlow`'s default exactness-copy sign to the Gan-Low direction (v̂ ≥ v) via a local per-branch coefficient flip, retained the literal thesis formula as an explicit `thesis_literal=true` opt-in, and backed it with a documented verdict page plus a permanent 3-bus AC-feasible/SOCP-feasible/thesis-literal-infeasible regression.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-28T17:05:00Z (approx.)
- **Completed:** 2026-09-28T17:21:00Z
- **Tasks:** 3 completed
- **Files modified:** 5 modified, 1 created

## Accomplishments

- Resolved the FIX-01 verdict: the thesis's own text (page ~84) claims `v ≤ V²max` becomes
  redundant after imposing the exactness-copy bounds, citing Gan-Low (2015) — true only if
  `v̂ ≥ v`. The literal transcribed eq. 3.43 formula produces the opposite (`v̂ ≤ v`), proven
  by a telescoping-sum argument along the root→j path — a defect in the thesis's own
  algebra, not a code bug.
- `ConvexBranchFlow` now defaults (`thesis_literal=false`) to the corrected Gan-Low
  direction; the literal, defective formula remains available and clearly labelled as a
  restriction via `ConvexBranchFlow(; thesis_literal=true)`.
- Documented the full verdict, citation, and proof sketch in
  `docs/literate/convex_branch_flow.jl`'s new "Verdict" subsection.
- Added a permanent 3-bus regression (`test/test_exactness_verdict.jl`) proving the
  restriction finding empirically: an AC-feasible (Ipopt), heavy-load/low-voltage
  operating point remains feasible under the corrected default SOCP but goes INFEASIBLE
  under the literal thesis-transcribed variant.
  Fixture: `Bus(j, 0.90, 1.05, ...)` at every bus, `Branch(1,2,0.08,0.03,SMAX_NO_LIMIT)`,
  `Branch(2,3,0.08,0.03,SMAX_NO_LIMIT)`, a dummy `Deferrable(3,1,1,0.0,1.0,1.0)` plus
  `Aggregator(3, 0.999999, [dummy], [0.53])`; T=1, λ₀=[1.0]. Measured gap at bus 3 under
  the corrected default: `v̂ - v = 0.004999...` (≥ 0, confirming the Gan-Low direction).
- Flipped the pre-existing (now-superseded) golden in `test/test_restricted_branch_flow.jl`
  (the "RESEARCH Assumption A1" spot-check) to assert `v̂ ≥ v`, and updated its
  now-in-agreement-but-still-distinct comment against the tree-wide `v̂_GL(s)` measurement
  in the adjacent `@testitem`.
  Old golden: `mingap = minimum(v[j,t] - v̂[j,t]) ; @test mingap >= -1e-9` (asserted `v ≥ v̂`).
  New golden: `mingap = minimum(v̂[j,t] - v[j,t]) ; @test mingap >= -1e-9` (asserts `v̂ ≥ v`).
  Cause: FIX-01/02's corrected default cpydrop sign, verified end-to-end on the EXACT-04
  fixture (measured gap sign flipped from previously-negative to non-negative).
- Extended `test/test_convex_branch_flow.jl` with two new regressions: a direct `v̂ ≥ v`
  spot-check on the default formulation, and a load-bearing/redundant-bound demonstration
  (maximizing the branch current `l` shows `v̂` hits its own `V²max` bound strictly before
  `v` does — `v̂2=1.10250000...` vs `vmax²=1.1025` binding, while `v2=1.05035...` stays
  well clear of the same bound — confirming `v̂ ≤ V²max` is load-bearing and `v ≤ V²max` is
  redundant under the corrected direction, matching the corrected docstring claim).

## Task Commits

Each task was committed atomically:

1. **Task 1: Flip cpydrop to the Gan-Low direction by default; retain thesis-literal as an opt-in kwarg** - `f677965` (fix)
2. **Task 2: Document the FIX-01 verdict in the convex_branch_flow literate docs page** - `d520758` (docs)
3. **Task 3: FIX-01 3-bus regression, flip the RestrictedBranchFlow golden, extend the SOCP unit test** - `ab397d1` (test)

_Note: tasks 1 and 3 were marked `tdd="true"` in the plan, but the plan's own `<verify>` blocks are inline diagnostic scripts (not separately-committed failing-test artifacts) — see "TDD Gate Compliance" below._

## Files Created/Modified

- `src/powerflow/ConvexBranchFlow.jl` - `ConvexBranchFlow` struct gains a `thesis_literal::Bool` field + outer kwarg constructor; `contribute!` introduces `sign = pf.thesis_literal ? 1.0 : -1.0` inside the `cpydrop` constraint; module header, struct docstring, and `contribute!` docstring rewritten to document the FIX-01/02 verdict
- `src/powerflow/RestrictedBranchFlow.jl` - stale docstring/header prose rewritten (no longer claims the "opposite sign relationship" as `ConvexBranchFlow`'s current default); documents `v̂_GL(s)` as a separate, complementary, still-needed tree-wide restriction
- `docs/literate/convex_branch_flow.jl` - displayed cpydrop formula updated to the corrected default; new "Verdict: thesis eq. 3.43 vs. Gan-Low (2015)" subsection with the telescoping-sum proof and citation
- `test/test_exactness_verdict.jl` (new) - the FIX-01 3-bus AC-feasible/SOCP-feasible/thesis-literal-infeasible regression
- `test/test_restricted_branch_flow.jl` - flipped the line-20 golden's mingap direction and assertion comment; updated the ε-measurement item's now-stale "opposite sign" comment
- `test/test_convex_branch_flow.jl` - two new `@testitem`s: default `v̂ ≥ v` spot-check, and load-bearing/redundant-bound demonstration

## Decisions Made

- **RESEARCH Option A over Option B**: implemented the fix as a local per-branch sign flip
  inside the existing `cpydrop` constraint rather than reusing `RestrictedBranchFlow`'s
  tree-based `v̂_GL` machinery. Option A is proven sufficient (telescoping-sum algebra),
  keeps `ConvexBranchFlow` graph-generic (no tree-order dependency, preserving
  `MeshedFlow` compatibility), and keeps the `:cpydrop` constraint container's shape
  byte-identical so every downstream consumer continues to structurally resolve — per
  RESEARCH.md's explicit recommendation.
- **DLMP coefficient re-derivation deferred to Plan 26-06**: this plan's own
  `<threat_model>` (T-26-03) explicitly assigns the `decompose_dlmp` dual-coefficient
  re-derivation to Plan 26-06, sequenced after this plan. This plan's obligation was only
  to keep the `:cpydrop` container's registered shape unchanged (confirmed: only the
  numeric coefficient inside the constraint changed, not its name/indices).
- **Load-bearing/redundant-bound test design**: rather than a weak `<=` check, the new
  `test_convex_branch_flow.jl` regression maximizes the branch current `l` (which
  increases `v̂` twice as fast as `v` per unit `l`, since both start from the same root
  value) to force the solver to hit `v̂`'s own upper bound strictly before `v`'s — giving a
  genuine, non-trivial demonstration of the corrected direction's load-bearing/redundant
  asymmetry rather than an always-true inequality.

## Deviations from Plan

None - plan executed as written. The load-bearing sub-test design (maximizing `l` to force
a genuine binding demonstration) was Claude's discretion within Task 3's stated behavior
("v̂ ≤ V²max is the binding (load-bearing) bound when voltage headroom is engaged"), not a
deviation from the plan's specified acceptance criteria.

## TDD Gate Compliance

Tasks 1 and 3 carry `tdd="true"` in the plan frontmatter, but this plan's `type` is
`execute` (not `tdd`), and each task's `<verify>` block is an inline diagnostic Julia
script embedded in the plan itself — not a separately-committed failing-test artifact to
RED/GREEN against. Task 1's verify script was run and passed before commit (confirming the
sign-flip behavior numerically both directions); Task 3 is itself the test-authoring task
(a permanent regression for behavior Task 1 already implemented), so a strict
test-before-implementation RED gate does not apply to its own commit. No `test(...)` →
`feat(...)` gate pair was expected or produced; this reflects the plan's task sequencing
(implementation in Task 1, documentation in Task 2, permanent tests in Task 3), not a
process failure.

## Issues Encountered

None. All three tasks' verification scripts passed on the first attempt.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `ConvexBranchFlow`'s corrected default is ready for Plan 26-05 (which per the plan's
  `<objective>` note extracts a shared `Prev`/`Qrev` expression pair once its `:smax_rev`
  cone lands, since that receiving-end power expression is algebraically identical to this
  plan's corrected `cpydrop` substitution).
- Plan 26-06 (or whichever plan handles DLMP correctness) must re-derive
  `decompose_dlmp`'s `dual(:cpydrop)` coefficient in `volt_b` — the sign of this dual
  changed with the corrected cpydrop coefficient, and `decompose_dlmp`'s hard
  sum-to-price assertion has NOT yet been re-verified against the corrected default in
  this plan (explicitly out of scope per this plan's own threat_model).
- The full test suite (`Pkg.test()`) has NOT been run in this plan (per-task direct-script
  verification was used instead, matching the project's TestItemRunner-trap memory); the
  orchestrator/wave-merge step should run the full suite to catch any downstream
  ADMM/DLMP/stochastic-welfare regressions this sign change may surface, per RESEARCH.md's
  explicit blast-radius warning (34 files touch `ConvexBranchFlow`, 11 touch DLMP).
- No blockers for proceeding to the next plan in this wave.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `test/test_exactness_verdict.jl`
- FOUND: `docs/literate/convex_branch_flow.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-02-SUMMARY.md`
- FOUND commit: `f677965` (Task 1)
- FOUND commit: `d520758` (Task 2)
- FOUND commit: `ab397d1` (Task 3)
