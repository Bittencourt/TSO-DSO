---
phase: 22-stochastic-pv-demand-uncertainty
plan: 02
subsystem: optimization
tags: [julia, jump, clarabel, socp, stochastic-programming, extensive-form]

# Dependency graph
requires:
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "Scenario.jl stoch_* fields + Phase22Fixtures (test/fixtures_phase22.jl,
      stoch_feeder/stoch_scenario_aggregators) from plan 22-01"
provides:
  - "build_stochastic_welfare(feeder, pf, scenario_aggs; probabilities, T, λ₀) — the
    S-scenario extensive-form welfare builder (STOCH-01/STOCH-02)"
  - "Per-scenario de-scaled DADP (dadp::Vector{Vector{Float64}}) with a derived
    probability-weighted expected_dadp summary — never a constraint-backed primitive"
  - "select_optimizer(::SOCP; attrs...) keyword-override method (src/solver/factory.jl) —
    byte-identical default when called with no kwargs"
affects: ["22-03", "22-04", "22-05"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "S independently-contribute!d, JuMP.unregister-decoupled scenario network blocks on
      one shared Model, each wrapped in its own fresh ModelContext"
    - "Nonanticipativity via explicit equality constraints across independently-built
      per-scenario device copies (never a literally-shared JuMP variable)"
    - "Per-scenario PF-04 exactness gate run in a plain loop, never aggregated"
    - "select_optimizer(::ProblemClass; attrs...) keyword-override pattern (mirrors the
      pre-existing NLP method) for a builder-specific convergence-precision default"

key-files:
  created: [src/models/stochastic_welfare.jl, test/test_stochastic_welfare.jl]
  modified: [src/TSODSO.jl, docs/src/api.md, src/solver/factory.jl]

key-decisions:
  - "build_stochastic_welfare's default optimizer requests tol_gap_abs/rel=5e-10 (not the
    SOCP() factory's base 1e-8) because a probability-weighted extensive-form objective
    genuinely weakens a low-probability scenario's own loss-cost gradient, which measurably
    (though non-structurally) tripped the PF-04 exactness gate on a near-lossless branch at
    the base tolerance; 5e-10 was chosen by sweeping both that fixture and a separate,
    more-lossy one — 1e-10 alone trips ALMOST_OPTIMAL on the lossier feeder, while
    [3e-10, 9e-10] converges OPTIMAL on both."
  - "Frontier import/export variables (p_import_s/q_import_s) are built AFTER each
    scenario's aggregators, exactly mirroring solve_welfare's own construction order —
    building them before the aggregators (as an early reading of the plan's own action
    text suggested) is mathematically equivalent but shifts Clarabel's internal
    variable-ordering enough to be worth avoiding for byte-for-byte D-08 reproduction."
  - "Task 2's D-06 test places both scenarios' aggregator at the SAME bus (not different
    buses as PLAN.md's own <verify> script literally does) — see Deviations."

patterns-established:
  - "select_optimizer(::ProblemClass; attrs...) keyword-override methods are the sanctioned
    way for a specific builder to request tighter/different solver convergence WITHOUT
    naming a concrete solver outside src/solver/factory.jl (INFRA-02 preserved)."

requirements-completed: [STOCH-01, STOCH-02]

# Metrics
duration: 53min
completed: 2026-08-10
---

# Phase 22 Plan 2: Stochastic extensive-form welfare builder Summary

**`build_stochastic_welfare` — S independently-built, `JuMP.unregister`-decoupled SOCP
scenario blocks on one shared `Model`, battery-tied nonanticipativity, per-scenario
de-scaled DADP with a derived expected-price summary, and a `select_optimizer(::SOCP;
attrs...)` convergence-precision fix for probability-weighted low-probability scenarios.**

## Performance

- **Duration:** 53 min
- **Started:** 2026-08-10T02:16:59Z
- **Completed:** 2026-08-10T03:10:03Z
- **Tasks:** 2/2 completed
- **Files modified:** 5 (4 modified, 2 created — `src/solver/factory.jl` was an
  out-of-declared-scope Rule 1 fix, see Deviations)

## Accomplishments
- `build_stochastic_welfare(feeder, pf, scenario_aggs; probabilities, T, λ₀)` implements
  the full S-scenario two-stage extensive form: `JuMP.unregister`-decoupled per-scenario
  `ConvexBranchFlow` blocks, explicit nonanticipativity equality constraints tying every
  battery-like device (`PVBattery`/`FourQuadBESS`) across scenarios, a per-scenario PF-04
  exactness gate that never aggregates, and de-scaled per-scenario DADP with a clearly
  DERIVED `expected_dadp` summary.
- Wired into `src/TSODSO.jl` (after `models/mpc_window.jl`) and `docs/src/api.md` (new
  "Stochastic PV/Demand Uncertainty" `@autodocs` section).
- Discovered and fixed a genuine numerical-sensitivity bug: a probability-weighted
  extensive form measurably weakens a low-probability scenario's own SOC-cone-tightening
  gradient, occasionally tripping the PF-04 gate on a near-lossless branch at the shared
  SOCP factory's base `tol_gap=1e-8`. Fixed via a new `select_optimizer(::SOCP; attrs...)`
  keyword-override method (mirrors the pre-existing `NLP` pattern) so this builder's
  default optimizer can request `tol_gap_abs/rel=5e-10` — verified to resolve the residual
  (5.6e-6 → 4.8e-8) without touching the exactness gate's own tolerance, and verified NOT
  to break convergence on a separate, more-lossy fixture (unlike a more aggressive `1e-10`,
  which trips `ALMOST_OPTIMAL` there).
- `test/test_stochastic_welfare.jl` covers D-04 (non-uniform probabilities genuinely change
  the objective), D-06 (PF-04 gate never aggregated — a scanned extreme scenario trips while
  the modest one stays exact), and the structural-congruence guard (a genuine bus mismatch
  throws `ArgumentError`).

## Task Commits

Each task was committed atomically:

1. **Task 1: build_stochastic_welfare — S-scenario extensive form + de-scaled DADP** -
   `7e4bd0f` (feat)
2. **Task 1 follow-up: tol_gap safety correction** - `b5b4169` (fix — see Deviations)
3. **Task 2: test_stochastic_welfare.jl D-04/D-06/structural-congruence coverage** -
   `5fe207f` (test)

**Plan metadata:** (pending — final metadata commit follows this SUMMARY)

## Files Created/Modified
- `src/models/stochastic_welfare.jl` - New `build_stochastic_welfare` extensive-form
  builder (S-scenario `ConvexBranchFlow` blocks, nonanticipativity ties, per-scenario PF-04
  gate, de-scaled DADP + derived expectation).
- `src/TSODSO.jl` - Wired `include("models/stochastic_welfare.jl")` after
  `models/mpc_window.jl`.
- `docs/src/api.md` - New "Stochastic PV/Demand Uncertainty" `@autodocs` section.
- `src/solver/factory.jl` - Added `select_optimizer(::SOCP; attrs...)` keyword-override
  method (byte-identical default when called with no kwargs) — out-of-declared-scope Rule 1
  fix, see Deviations.
- `test/test_stochastic_welfare.jl` - New `@testitem`s (D-04, D-06, structural congruence).

## Decisions Made
- `tol_gap_abs/rel = 5e-10` (not a more aggressive `1e-10`) for `build_stochastic_welfare`'s
  default optimizer — measured to converge `OPTIMAL` on both the near-lossless fixture that
  originally needed it AND a separate, more-lossy fixture that a tighter `1e-10` broke.
- Frontier import/export construction moved to AFTER the per-scenario aggregator loop
  (matching `solve_welfare`'s own order) rather than before it, for numerical-path fidelity
  to the S=1 degenerate-reduction anchor (D-08).
- Task 2's D-06 test item places both scenarios' single aggregator at the SAME bus (2)
  rather than different buses — see Deviations for the full rationale.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] tol_gap convergence-precision fix for probability-weighted low-probability scenarios**
- **Found during:** Task 1's own `<verify>` script — the S=2, non-uniform-probability
  (`p₁=0.35, p₂=0.65`) case deterministically tripped the PF-04 exactness gate on the
  fixture's near-lossless branch (5.6e-6 residual, ratio 5.6 over threshold), even though
  the underlying primal solution (welfare, DADP) matched `solve_welfare`'s own baseline
  within far tighter tolerances than required.
- **Root cause (verified, not assumed):** a probability-weighted objective
  `Σ_s p_s·(...)` scales scenario s's own loss-cost gradient by `p_s`; the lower-probability
  scenario (`p₁=0.35`) has a genuinely weaker gradient driving its SOC cone tight than a
  standalone (`p=1.0`) solve, which the SOCP factory's base `tol_gap=1e-8` occasionally
  couldn't fully resolve on a near-lossless branch. Confirmed by re-solving with a much
  tighter `tol_gap=1e-12`, which reduced the residual to ~5.7e-10 (welfare/DADP/all other
  branch-flow variables were BYTE-IDENTICAL to `solve_welfare`'s own solve whenever the gate
  passed, ruling out a construction-order or structural bug).
- **Fix:** added `select_optimizer(::SOCP; attrs...)` in `src/solver/factory.jl` (mirrors
  the pre-existing `select_optimizer(::NLP; attrs...)` pattern; `select_optimizer(SOCP())`
  with no kwargs stays byte-identical) and set `build_stochastic_welfare`'s default
  `optimizer` kwarg to request `tol_gap_abs/rel=5e-10` when `problem_class(pf) isa SOCP`.
  `5e-10` (not the first-tried `1e-10`) was chosen after discovering `1e-10` alone trips
  `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` on a SEPARATE, more-lossy (`r=x=0.05`) fixture
  (Task 2's own D-06 test) — swept `[3e-10, 9e-10]` and confirmed every value in that window
  converges `OPTIMAL` on BOTH fixtures.
- **Files modified:** `src/solver/factory.jl` (out of the plan's declared `files_modified`
  scope — necessary to fix a genuine blocking bug without weakening the PF-04 exactness
  gate's own tolerance), `src/models/stochastic_welfare.jl`.
- **Verification:** Task 1's full `<verify>` script re-run 3× across fresh Julia processes,
  all passing; `solve_welfare` (an existing, unmodified caller of `select_optimizer(SOCP())`
  with no kwargs) re-verified byte-identical after the factory change.
- **Committed in:** `7e4bd0f` (initial fix, `1e-10`), `b5b4169` (correction to `5e-10`
  after discovering the lossy-fixture regression).

**2. [Rule 1 - Bug] PLAN.md's own Task 2 `<verify>` script conflicts with Task 1's structural-congruence guard**
- **Found during:** Task 2, writing `test/test_stochastic_welfare.jl` from PLAN.md's D-06
  `<verify>` script.
- **Issue:** PLAN.md's Task 2 `<verify>` script places scenario 1's aggregator at bus 2 and
  scenario 2's at bus 3 (a single aggregator each, at DIFFERENT buses), then expects the
  pair to build and solve cleanly, tripping only `assert_socp_exact!`'s `ErrorException` at
  an extreme `pv_scale`. This directly collides with Task 1's OWN action-text-specified
  structural-congruence guard (`build_stochastic_welfare` throws `ArgumentError` when
  `scenario_aggs[s][k].bus != scenario_aggs[1][k].bus`) — a guard that is itself
  load-bearing: without it, the nonanticipativity walk would hit an unhandled `KeyError` on
  a genuinely-absent bus key, a WORSE failure mode than a clean `ArgumentError`. Verified:
  running PLAN.md's literal Task 2 script throws `ArgumentError` (not `ErrorException`) on
  the very first scanned `pv_scale`, and — because the script's own `catch` block does
  `e isa ErrorException || rethrow()` — that `ArgumentError` propagates uncaught, failing
  the whole script.
- **Fix:** Item 2 of `test/test_stochastic_welfare.jl` places BOTH scenarios' single
  aggregator at the SAME bus (2) instead of different buses. This satisfies the
  structural-congruence guard while preserving the test's actual intent (D-06: the PF-04
  gate certifies a per-scenario NETWORK copy — `l`/`v`/`P`/`Q` are never tied across
  scenarios, only the battery schedule is — so scenario 2's own network can still be driven
  independently inexact by an extreme `pv_scale` regardless of the shared bus). Verified:
  scanning `pv_scale ∈ {1.0, 2.0, 4.0, 8.0, 16.0, 32.0}` on the same-bus construction finds a
  genuine STRUCTURAL inexactness at `pv_scale=2.0` (maxratio ≈ 9688, ~9700× over the
  ratio>1 threshold — not a knife-edge residual), while scenario 1 alone (at its own
  `pv_scale=0.5`) stays `OPTIMAL` and exact throughout. Item 3 (the structural-congruence
  guard test itself) is UNAFFECTED and still uses two genuinely different buses, exactly as
  PLAN.md specifies.
- **Files modified:** `test/test_stochastic_welfare.jl` (this file was authored fresh in
  this task; the "fix" is a deviation from PLAN.md's literal `<verify>` script text, not a
  change to already-committed code).
- **Verification:** the D-06 fixture's actual scan (matching the test item's logic) run
  standalone, confirmed a clean `pv_scale=2.0` trip with `ErrorException`, scenario 1's
  own gap (2.5e-8) unaffected by scenario 2's inexactness (0.327 residual) in the SAME
  2-scenario solve — the exact "never aggregated" property D-06 requires.
- **Committed in:** `5fe207f` (Task 2 commit).

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bug fixes; one touched a file outside
the plan's declared scope, one adapted a test fixture that conflicted with the plan's own
guard specification).
**Impact on plan:** Both fixes were necessary to make the plan's own correctness
requirements (PF-04 gate integrity, structural-congruence guard) and its two tasks'
`<verify>`/`<done>` criteria mutually satisfiable. No scope creep beyond what each task
demanded; the `select_optimizer(::SOCP; attrs...)` addition is a minimal, backward-compatible,
precedented extension of an existing pattern in the same file.

## Issues Encountered

The initial diagnosis of the Task 1 exactness failure was non-trivial: welfare/DADP/DADP
and even the underlying `v`/`v̂`/`P`/`Q`/`l` values were BYTE-IDENTICAL between
`solve_welfare` and the S=1 `build_stochastic_welfare` call whenever both succeeded, which
initially looked like solver run-to-run nondeterminism. Isolating each call individually
(rather than as part of the full multi-call verify script) revealed the actual trigger was
the S=2 (`r2`) construction, not S=1 — the earlier apparent "flakiness across separate
processes" was an artifact of misattributing which line in a longer script had thrown.
Once isolated, the root cause (probability-scaled gradient weakness) was straightforward to
confirm and fix.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `build_stochastic_welfare` is a stable, exported, documented contract ready for plan
  22-03 (out-of-sample harness) and 22-04 (orchestrator/`run_stochastic`).
- `select_optimizer(::SOCP; attrs...)`'s keyword-override pattern is now available for any
  future builder that needs a tighter/different Clarabel convergence tolerance without
  naming a concrete solver — a reusable seam beyond this phase.
- No blockers carried forward specific to this plan. The pre-existing v3.0 Phase-22 flag
  ("no empirical measurement yet of Clarabel's scenario-count ceiling") is PARTIALLY
  addressed: Task 1's own `<verify>` script measured `num_variables`/warm-solve timing for
  S=1,3,5 on the small CI fixture (109/327/545 variables, all sub-0.1s warm) — comfortably
  within capacity at this fixture scale; a fuller sweep on a larger population remains for
  a later plan if needed.

---
*Phase: 22-stochastic-pv-demand-uncertainty*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: src/models/stochastic_welfare.jl
- FOUND: test/test_stochastic_welfare.jl
- FOUND: src/solver/factory.jl
- FOUND: src/TSODSO.jl
- FOUND: docs/src/api.md
- FOUND commit: 7e4bd0f (Task 1)
- FOUND commit: b5b4169 (Task 1 follow-up fix)
- FOUND commit: 5fe207f (Task 2)
