---
phase: 40-784-house-thesis-population
plan: 05
subsystem: solver-seam
tags: [julia, jump, clarabel, solver-precision-seam, qp-factory, admm, agr-opt, golden-policy, pop-04]

# Dependency graph
requires:
  - phase: 40 plan 02/03 (verification + agreement measurement)
    provides: the POP-04 gap definition — battery-complementarity certificate
      refuses the converged 784-house ADMM point on certificate noise (product
      0.04% over the ~1e-12 relative band), and the sanctioned answer class
      (tighten the SOLVER, never a gate)
  - phase: solver factory + admm core
    provides: select_optimizer(::ProblemClass) dispatch (SOCP/NLP attrs-seam
      precedents), build_agr_opt (build-once AGR QP), _admm_build, solve_admm
      (atol_exact/rtol_exact additive-kwarg discipline)
provides:
  - "select_optimizer(::QP; attrs...) — the additive attribute-override seam on
    the last factory method without one (no-kwarg call byte-identical)"
  - "build_agr_opt(optimizer=...) — injectable AGR model factory, default
    byte-identical, governing every re-solve of the build-once model"
  - "solve_admm(agr_optimizer=...) — end-to-end aggregator solver-precision seam
    (kwarg -> _admm_build -> build_agr_opt -> Clarabel factory), default nothing
    -> byte-identical; plan 40-06 can pass a measured tighter factory through it
    with zero further src/ change"
affects: [40-06 ladder measurement (POP-04 closure), phase verifier, phase-42
  DADP-vs-FIT planning]

# Tech tracking
tech-stack:
  added: []   # zero new packages (40-RESEARCH.md Package Legitimacy Audit)
  patterns:
    - "Additive-kwarg seam discipline: new kwargs resolve to the byte-identical
      default when omitted; golden (knife-edge canary) proves the default path
      numerically unchanged — never re-pinned"
    - "No tolerance literal in executable src lines: numeric ladder values live
      at call sites (caller-measured-floor discipline, mirrors atol_exact)"

key-files:
  created:
    - test/test_factory.jl (extended — new QP attrs testitem)
    - test/test_agr.jl (extended — new optimizer-kwarg testitem)
  modified:
    - src/solver/factory.jl
    - src/admm/AgrOpt.jl
    - src/admm/admm_phases.jl
    - src/admm/solve_admm.jl

key-decisions:
  - "QP attrs seam bakes in NO tolerance: only the SOCP method's pre-existing
    1e-8 defaults remain in factory.jl — the ladder values live in plan 40-06's
    measurement script, honoring the caller-measured-floor discipline"
  - "agr_optimizer is UNTYPED (mirrors reactive_consensus) and resolves ONCE in
    solve_admm before _admm_build; _admm_build carries its own
    select_optimizer(QP()) default so non-solve_admm callers are unaffected"
  - "POP-04 stays open for 40-06 to close: this plan only builds the seam
    (requirements-completed: [] by design — the band is pinned or the
    non-closure documented by 40-06, never by the seam plan)"

patterns-established:
  - "Golden-policy proof pattern: additive seam + knife-edge canary
    (iters=56 / welfare=-4823.66604824162, NOT re-pinned) + gate-surface
    git-diff-empty + full fast lane green before done"

requirements-completed: []   # POP-04 closes only via 40-06 (band pinned or non-closure documented)

# Metrics
duration: 31min
completed: 2026-10-24
---

# Phase 40 Plan 5: ADMM Solver-Precision Seam Summary

**Additive Clarabel precision seam for the ADMM aggregator solves — `select_optimizer(::QP; attrs...)` + `build_agr_opt(optimizer=...)` + `solve_admm(agr_optimizer=...)` threaded end-to-end, with the default path proven byte-identical (canary 56 / -4823.66604824162 untouched, fast lane 32165/0 fail) so plan 40-06 can drive its measured tolerance ladder through the seam with zero further src/ change.**

## Performance

- **Duration:** 31 min
- **Started:** 2026-10-24T19:05:51Z
- **Completed:** 2026-10-24T19:37:11Z
- **Tasks:** 2/2
- **Files modified:** 4 src + 2 test

## Accomplishments

- **The POP-04 "seam currently absent" missing-item is closed:** `solve_admm` can now
  receive a measured tighter Clarabel factory for its aggregator solves through ONE
  additive kwarg, without any further src/ change (40-06's precondition).
- `select_optimizer(::QP; attrs...)` — the QP factory (the ONE class method without an
  attribute-override seam) now mirrors the SOCP/NLP methods: base `"verbose" => false`
  kept first, splatted caller attrs last (caller keys win). No-kwarg call is behaviorally
  the previous one-liner (pure additive seam, golden policy).
- `build_agr_opt(optimizer = select_optimizer(QP()))` — the factory is injectable at
  BUILD time; AGR models are build-once/re-solve, so the injected factory governs EVERY
  solve (mid-loop coefficient updates AND the certify re-solves — exactly where the
  battery-complementarity certificate fires).
- `solve_admm(agr_optimizer = nothing)` — untyped additive kwarg (mirrors
  `reactive_consensus`), resolved once to the plain QP factory when omitted, threaded
  through `_admm_build` into every `build_agr_opt`. Docstring section names POP-04, the
  measured refusal (product 0.04% over the ~1e-12 relative band at the per-house-divided
  battery scale), and the NEVER-touch-a-gate discipline.
- **Golden policy proven, not assumed:** knife-edge canary reproduces its PINNED
  iters=56 / welfare=-4823.66604824162 (never re-pinned); `git diff` over the gate
  surfaces (`admm_state.jl` τ_batt=1e-3 literals, `welfare_solve.jl`,
  `exactness.jl`) is EMPTY; no tolerance literal in any executable src line (only the
  SOCP method's pre-existing 1e-8 defaults); fast lane 32165 pass / 6 broken (5 known +
  the tracked POP-04 skip) / 0 fail.

## Task Commits

Each task was committed atomically:

1. **Task 1: QP factory attrs seam + build_agr_opt optimizer kwarg** - `2283c3a` (feat)
2. **Task 2: Thread agr_optimizer through solve_admm → _admm_build; byte-identical default proof** - `87f1ad2` (feat)

## Files Created/Modified

- `src/solver/factory.jl` — `select_optimizer(::QP; attrs...)` additive attribute seam
  (motivation + no-tolerance-in-factory discipline documented in the comment block)
- `src/admm/AgrOpt.jl` — `build_agr_opt` trailing `optimizer` kwarg; `Model(optimizer)`;
  docstring paragraph (build-time injection covers all re-solves)
- `src/admm/admm_phases.jl` — `_admm_build` trailing kwarg `agr_optimizer =
  select_optimizer(QP())` passed into every `build_agr_opt`; no other line changed
- `src/admm/solve_admm.jl` — untyped `agr_optimizer = nothing` kwarg (after `rtol_exact`,
  before `parallel`), one-line resolution, pass-through; docstring signature + new
  "Aggregator solver-precision seam" section
- `test/test_factory.jl` — fast testitem: tiny convex QP builds + solves under the
  default QP factory AND under `tol_gap_abs/rel = 1e-10` overrides (attrs reach the
  backend)
- `test/test_agr.jl` — fast testitem: `build_agr_opt(...; optimizer =
  select_optimizer(TSODSO.QP(); tol_gap_abs/rel = 1e-12))` solves OPTIMAL at zero price
  and `solve_agr!` re-solves finite (kwarg reaches the model)

## Decisions Made

- **No tolerance default in the seam** (binding constraint honored): the factory bakes in
  nothing; 40-06's ladder values stay in the measurement script — grep-verified that the
  only numeric literals in the src/ diff sit in comments.
- **Untyped kwarg + one-time resolution**: mirrors the signature's own
  `reactive_consensus` precedent; `agr_optimizer === nothing ? select_optimizer(QP()) :
  agr_optimizer` keeps the default path a literal call to the same factory expression as
  before.
- **`_admm_build` carries its own default**: non-`solve_admm` callers (none today, but
  any future internal caller) get the unchanged plain-QP behavior.
- **92-col pinned formatter reflows**: the `_admm_build` call became multi-line per the
  pinned JuliaFormatter config (the same reflow precedent recorded in the 39-series);
  no docstring content loss (STATE.md hazard checked by diff).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Both test gates passed on the first run (Task 1: 37/37 in 1m02s; Task 2: 93/93 in
8m28s with the pinned canary; fast lane 32165 pass / 0 fail in 15m28s).

## User Setup Required

None - no external service configuration required.

## Threat Surface Scan

No new surface beyond the plan's `<threat_model>`: the seam's mitigation set is
implemented as planned — gate-surface diff empty (T-40-05-01), byte-identical defaults
proven by the canary + fast lane (T-40-05-02), a looser factory cannot weaken a verdict
that runs downstream of the solves (T-40-05-03, accepted), POP-04 + measured refusal
named in docstrings and commit messages (T-40-05-04), zero tolerance literals in
executable lines (T-40-05-05), zero new packages (T-40-05-SC).

## Next Phase Readiness

- **Ready for 40-06 (wave 2):** the ladder script can pass
  `agr_optimizer = select_optimizer(QP(); <rung attrs...>)` exactly as pre-planned —
  no further src/ change needed (the plan's success criterion).
- Gate surfaces, goldens, and the A5 consensus config are all byte-identical; the only
  behavior change on the repo is the new optional kwargs.

---
*Phase: 40-784-house-thesis-population*
*Completed: 2026-10-24*
