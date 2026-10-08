---
phase: 29-genuine-bilevel-tso-dso-variant
plan: 01
subsystem: planning
tags: [jump, highs, milp, sos1, bilevel, kkt, lindistflow]

# Dependency graph
requires:
  - phase: 11 (v2.0)
    provides: "FollowerLP/BendersMaster/solve_stackelberg! structural idioms (boundary-guard-before-assembly, Model(select_optimizer(...)) factory seam) mirrored (not reused) here"
  - phase: 02 (v1.0)
    provides: "LinDistFlow contribute!(pf, ctx, feeder; T) embedded verbatim as the leader's own network welfare (CONTEXT.md Option B)"
provides:
  - "build_bilevel_kkt / solve_bilevel! / BilevelKKT — the production, one-shot single-level KKT-MILP solver for the genuinely bilevel TSO-DSO variant (BILEV-01)"
  - "bilevel_toy_fixture() in test/fixtures_planning.jl — the shared 2-bus/T=1 fixture plan 29-02's BILEV-02 certification will also consume"
  - "Honest docstring/header relabelling of solve_stackelberg! as 'the integrated problem, Benders-decomposed', distinct from the new genuinely bilevel entry point"
affects: [29-02, 29-03, 29-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-level KKT-MILP construction: follower stationarity as linear equalities + SOS1 complementarity pairs via the automatic MOI SOS1ToMILPBridge, no outer loop"
    - "Measured (never guessed) SOS1 big-M bounds via a throwaway two-probe LP/QP pre-pass, now including BOTH named-constraint duals AND variable-bound reduced costs"

key-files:
  created:
    - src/planning/bilevel_kkt.jl
    - test/test_planning_bilevel.jl
  modified:
    - src/TSODSO.jl
    - src/planning/benders.jl
    - test/fixtures_planning.jl

key-decisions:
  - "Measured SOS1 bounds must include BOTH named-constraint duals (mu_cap, rho_y) AND variable-bound reduced costs (rho_lo, mu_lo) -- the research's illustrative probe (named-constraint duals only) silently fails on any fixture whose follower optimum is a degenerate corner at both probe extremes."
  - "q_op defaults to zeros(T) (BLOCKER-1 revision, byte-compatible with the plain-LP corner fixture); nonzero q_op deferred to plan 29-04's non-degenerate fixture."

requirements-completed: [BILEV-01]

# Metrics
duration: ~25min
completed: 2026-09-30
---

# Phase 29 Plan 01: Genuine Bilevel KKT-MILP Solver Summary

**`build_bilevel_kkt`/`solve_bilevel!` — a one-shot single-level KKT-MILP (SOS1 complementarity via the automatic MOI/HiGHS bridge) solving the genuinely bilevel DSO-leader/TSO-follower game, distinct from the existing Benders-decomposed `solve_stackelberg!`**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-30T20:10:00-03:00 (approx.)
- **Completed:** 2026-09-30T20:28:24-03:00
- **Tasks:** 2 completed
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments
- New `src/planning/bilevel_kkt.jl`: `BilevelKKT` struct + `build_bilevel_kkt` (embedded-LinDistFlow-network single-level KKT-MILP builder, with boundary guards, a measured SOS1 big-M pre-pass, and a strictly-affine leader objective) + `solve_bilevel!` (solves via `assert_solved!(...; dual=false)` and runs the Pitfall-3 post-solve validity check that a complementarity variable never sits at its derived bound).
- `solve_stackelberg!` (src/planning/benders.jl) honestly relabelled — docstring and module header now state it solves "the integrated problem, Benders-decomposed", pointing to `solve_bilevel!` for the genuinely bilevel variant — verified via `git diff` to be a comment/docstring-only change (no executable line touched).
- `test/fixtures_planning.jl` extended with `bilevel_toy_fixture()` — the shared locked 2-bus/T=1 fixture (`pi_tariff` dominance, follower under-supplies to `z*=0` regardless of `y_inv`) that this plan and plan 29-02 both consume.
- `test/test_planning_bilevel.jl` (new): 3 `@testitem`s — hand-derived corner reproduction (`y=x_inv=z=total_cost=0.0`), 7 boundary-guard `ArgumentError` cases, and a deliberate too-tight-`safety` stress test of the validity check — all verified passing via a direct Julia/Test.jl script under `--project=.`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write build_bilevel_kkt — embedded-network single-level KKT-MILP** - `c3972dd` (feat)
2. **Task 2: solve_bilevel! behavioral verification + unit/boundary-guard tests** - `1b7782c` (test, includes the Rule-1 auto-fix below)

## Files Created/Modified
- `src/planning/bilevel_kkt.jl` - `BilevelKKT`/`build_bilevel_kkt`/`solve_bilevel!`/`_measure_follower_kkt_bounds`
- `src/TSODSO.jl` - one new `include("planning/bilevel_kkt.jl")` line after `benders.jl`
- `src/planning/benders.jl` - docstring/module-header-only relabelling of `solve_stackelberg!`
- `test/fixtures_planning.jl` - `bilevel_toy_fixture()` added to `PlanningFixtures`
- `test/test_planning_bilevel.jl` - 3 `@testitem`s (BILEV-01 unit/boundary-guard coverage)

## Decisions Made
- Kept `select_optimizer(::MILP)`'s shared default tolerances untouched — the fixture's tiny MILP (2 SOS1 pairs after bridging, T=1) solved cleanly to `MOI.OPTIMAL` under the default; no keyword-passthrough seam was added to `src/solver/factory.jl` (Pitfall 4's "measure first, don't touch speculatively" instruction honored).
- `bilevel_toy_fixture()`'s numbers are exactly the plan's locked spec (`pi_tariff=[0.2]` vs `c_op=[0.5]`, `v_d=[3.0]`) — the hand-derived bilevel corner (`y*=0, z*=0, total*=0.0`) was verified to match the production solve exactly (no atol slack needed; HiGHS reached the exact corner to double precision).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_measure_follower_kkt_bounds` measured a too-tight (degenerately zero) SOS1 bound on this fixture's own corner, making the production MILP genuinely `MOI.INFEASIBLE`**
- **Found during:** Task 2 (running the direct-script verification of item 1, the hand-derived corner reproduction)
- **Issue:** The plan's Task 1 action (and 29-RESEARCH.md's own illustrative code example) specifies collecting ONLY the named-constraint duals `dual(inv_bound)`/`dual(cap[t])` at the two probe extremes. On `bilevel_toy_fixture()` the follower's true optimum is `x_inv=z=0` at BOTH `y_probe=0.0` and `y_probe=y_max` (the deliberate `pi_tariff` dominance the fixture is designed around) — at this degenerate corner both named-constraint duals measure exactly `0.0` (verified empirically: relaxing either bound further genuinely does not change the follower's objective), giving `m_ub = safety*max(1e-6, 0) = 1e-5`. But the production MILP's own `statio_x`/`statio_z` equalities still require a NONZERO `rho_lo`/`mu_lo[1]` (the follower's variable-bound duals on `x_inv>=0`/`z[1]>=0`) to balance at that same corner — the minimal feasible assignment needs `max(mu_cap, mu_lo, rho_lo) ≈ 0.534`, comfortably outside `[0, 1e-5]`. `optimize!` correctly reported `MOI.INFEASIBLE` (not a silently-wrong answer) — no complementarity assignment fits inside the too-tight box.
- **Fix:** Extended `_measure_follower_kkt_bounds` to ALSO collect `abs(reduced_cost(x_inv))` and `abs(reduced_cost(z[t]))` for every `t` at each probe — the follower's own VARIABLE-BOUND duals, which correspond exactly to `rho_lo`/`mu_lo[t]` in the production KKT block via the same `statio_x`/`statio_z` stationarity identity. Verified directly (`julia --project=. -e '...'`, see session transcript): at this fixture's degenerate corner, `reduced_cost(x_inv)=1.0` and `reduced_cost(z[1])=0.3` are exactly the nonzero KKT multipliers the production MILP needs, precisely where the named-constraint duals are degenerately zero. With this fix, `m_ub = 10.0`, comfortably above the ~0.534 minimum, and the MILP solves to `MOI.OPTIMAL` reproducing the hand-derived corner exactly.
- **Files modified:** `src/planning/bilevel_kkt.jl` (`_measure_follower_kkt_bounds` docstring + body)
- **Verification:** `julia --project=. /tmp/verify_29_01_bilevel.jl` — all 3 `@testitem` reproductions pass (12 assertions total, 0 failures); `using TSODSO` still loads cleanly.
- **Committed in:** `1b7782c` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for correctness — without the fix, `solve_bilevel!` on the plan's OWN locked fixture would throw `MOI.INFEASIBLE` instead of reproducing the hand-derived bilevel corner. No scope creep: the fix only widens the set of duals probed inside the existing measurement helper; the single-level MILP's own variables, constraints, and objective are unchanged.

## Issues Encountered
None beyond the deviation documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `build_bilevel_kkt`/`solve_bilevel!` and `bilevel_toy_fixture()` are ready for plan 29-02's BILEV-02 certification (BilevelJuMP `StrongDualityMode` + brute-force grid enumeration + a genuine bilevel-vs-joint gap assertion on this same fixture).
- No blockers. The measured-bound fix (this plan's one deviation) generalizes: any future fixture whose follower optimum is a degenerate corner at both probe extremes is now covered by the same widened probe.

---
*Phase: 29-genuine-bilevel-tso-dso-variant*
*Completed: 2026-09-30*

## Self-Check: PASSED

All claimed files found on disk (`src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`,
`src/TSODSO.jl`, `src/planning/benders.jl`, `test/fixtures_planning.jl`); both task commit hashes
(`c3972dd`, `1b7782c`) found in `git log --oneline --all`.
