---
phase: 15-ac-exactness-oracle
plan: 01
subsystem: optimization
tags: [julia, jump, ipopt, ac-opf, branch-flow, socp-exactness, phasor-recovery]

requires:
  - phase: 04-socp-exactness
    provides: ConvexBranchFlow SOCP formulation, assert_socp_exact! gate, solve_welfare entrypoint, pf_vars stash convention
provides:
  - ACPowerFlow <: AbstractPowerFlow — independent nonconvex AC-OPF peer (true equality l·v==P²+Q², no exactness copy), dispatched through unchanged solve_welfare to Ipopt
  - recover_voltage_angles(ctx) — pure BFS Baran-Wu complex-phasor recursion recovering true voltage phasors from magnitude-only v=|V|²
  - BLOCKING 2-bus analytic validation gate for the new angle-recovery math (GREEN)
affects: [15-02, 15-03]

tech-stack:
  added: []
  patterns:
    - "Peer AbstractPowerFlow subtype via multiple dispatch — new formulation costs one file + zero changes to solve/exactness machinery"
    - "problem_class(::ACPowerFlow)=NLP() routes to Ipopt through solve_welfare's default optimizer kwarg — no hard-coded solver"
    - "Signed-branch-index BFS adjacency for direction-aware phasor propagation over an unsorted radial tree"

key-files:
  created:
    - src/powerflow/ACPowerFlow.jl
    - src/models/ac_oracle.jl
    - test/test_ac_powerflow.jl
    - test/test_ac_oracle.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "l·v==P²+Q² written as a scalar-quadratic EqualTo constraint — Ipopt's MOI wrapper takes it natively (RESEARCH Assumption A2 resolved empirically: LOCALLY_SOLVED)"
  - "'Same operating point' locked as the optimality-check interpretation: SOCP and AC consume identical inputs and each independently re-optimizes"
  - "The :l-keyed assert_socp_exact! double-fire inside solve_welfare is harmless (equality => residual ~1e-11) and left intentionally, documented in the module header"
  - "Baran-Wu recursion V_j = V_i - z·conj(S)/conj(V_i) validated against hand-derived closed-form V₂ = 0.998 - 0.0015im"

patterns-established:
  - "AC oracle as a genuinely independent nonconvex formulation, never a re-solve of the same relaxed cone"

requirements-completed: [EXACT-01]

duration: 18min
completed: 2026-07-26
---

# Phase 15 Plan 01: AC-OPF Peer Formulation + Angle Recovery Summary

**ACPowerFlow — a genuinely independent nonconvex AC-OPF peer (true equality l·v==P²+Q² via Ipopt) dispatched through the unchanged solve_welfare, plus recover_voltage_angles validated against a hand-derived 2-bus closed-form phasor**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-26T00:11:20Z
- **Completed:** 2026-07-26T00:29:14Z
- **Tasks:** 3
- **Files modified:** 5 (4 created, 1 modified)

## Accomplishments
- `ACPowerFlow <: AbstractPowerFlow` enforces the UNRELAXED branch-flow physics — the true nonconvex scalar-quadratic EQUALITY `l·v == P²+Q²` (thesis 3.39 unrelaxed) with no LinDistFlow exactness copy — and dispatches through the EXISTING `solve_welfare` entrypoint with zero change to that file (`problem_class(::ACPowerFlow)=NLP()` routes to Ipopt). Confirmed end-to-end: `solve_welfare(..., ACPowerFlow(), ...)` reaches `LOCALLY_SOLVED`.
- `recover_voltage_angles(ctx)`: a pure BFS Baran-Wu complex-phasor recursion recovering true voltage phasors from the magnitude-only `v=|V|²` state; signed-branch adjacency handles unsorted branch order.
- The BLOCKING 2-bus analytic validation gate is GREEN — the new angle-recovery math matches the hand-derived closed-form phasor `V₂ = 0.998 - 0.0015im` (and `abs2 ≡ v[2,1]=0.99600625`, small-angle identity `θ₂≈-0.0015`) before any later plan trusts it on IEEE-13/123.

## Task Commits

1. **Task 1: RED scaffold (ACPowerFlow contract + 2-bus angle gate)** - `48c8fe6` (test)
2. **Task 2: ACPowerFlow peer formulation + TSODSO.jl wiring** - `431b032` (feat)
3. **Task 3: recover_voltage_angles + BLOCKING 2-bus gate** - `dccb736` (feat)

## Files Created/Modified
- `src/powerflow/ACPowerFlow.jl` - Nonconvex AC-OPF peer formulation (equality cone, scalar-quadratic smax, no v̂)
- `src/models/ac_oracle.jl` - recover_voltage_angles BFS complex-phasor recursion (assert_ac_exact! added in 15-02)
- `src/TSODSO.jl` - Two include lines (ACPowerFlow.jl after ConvexBranchFlow.jl; ac_oracle.jl after models/oracle.jl)
- `test/test_ac_powerflow.jl` - 3 @testitems (subtype contract, NLP routing, pf_vars stash without v̂) — GREEN
- `test/test_ac_oracle.jl` - 2 @testitems (BLOCKING 2-bus angle gate GREEN; assert_ac_exact! RED-guard intentionally RED for 15-02)

## Decisions Made
- Referenced the existing module-level `_SMAX_NO_LIMIT` const directly (ACPowerFlow.jl is included after ConvexBranchFlow.jl) rather than duplicating the `99.0` literal.
- Used a plain LP solve of the all-fixed model in the angle-recovery test so `value()` resolves (no cone involved in that fixture).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Angle-recovery test's fixed-value model needed an attached optimizer**
- **Found during:** Task 3 (2-bus analytic gate)
- **Issue:** Task 1's scaffold built a bare `Model()` and called `optimize!` → `JuMP.NoOptimizer()`; `value()` on the fixed variables requires a solved model.
- **Fix:** Switched to `Model(select_optimizer(LP()))` (trivial fixed-value LP), mirroring `test_exactness.jl`'s fixed-value construction pattern.
- **Files modified:** test/test_ac_oracle.jl
- **Verification:** 2-bus angle-recovery gate GREEN (7 asserts pass).
- **Committed in:** dccb736 (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 bug).
**Impact on plan:** Necessary correctness fix to the test harness; no scope change.

## Issues Encountered
- The plan's acceptance-criterion grep `l\[b, t\] \* v\[B\[b\].from, t\] == P\[b, t\]^2 + Q\[b, t\]^2` has an unescaped `^` that GNU grep treats as a line anchor, so it returns 0 against the verbatim code line. The code text matches the intent exactly and matches the pattern when the caret is escaped (`\^`). No code change warranted — the constraint is written as specified.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ACPowerFlow + recover_voltage_angles ready. Both SOCP-built and AC-built contexts stash `pf_vars` with the same field names, so `assert_ac_exact!` (plan 15-02) can index them uniformly.
- No new package added (`Project.toml`/`Manifest` untouched by these commits; the pre-existing CairoMakie drift is user-local, unrelated).

---
*Phase: 15-ac-exactness-oracle*
*Completed: 2026-07-26*
