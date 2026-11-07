---
phase: 44-aggregator-as-actor
plan: 07
subsystem: experiments
tags: [sweep, csv, literate-docs, jet-ratchet, requirements-closure]
requires: ["44-06"]
provides:
  - "scripts/actor_behaviour_sweep.jl and results/actor_behaviour/actor_behaviour_sweep.csv (22 rows, all ok)"
  - "docs/literate/aggregator_actor.jl registered in docs/make.jl; scripts/README.md row"
  - "test/test_actor_sweep.jl (slow): CSV schema + reference-point reproduction"
  - "JET ratchet green (20 current / 20 baseline); ACTOR-01..04 marked complete"
affects: []
tech-stack:
  added: []
  patterns: ["script -> committed CSV -> literate page that recomputes figures live", "refusals as verdict rows"]
key-files:
  created:
    - scripts/actor_behaviour_sweep.jl
    - results/actor_behaviour/actor_behaviour_sweep.csv
    - docs/literate/aggregator_actor.jl
    - test/test_actor_sweep.jl
  modified:
    - docs/make.jl
    - scripts/README.md
    - scripts/jet_baseline.txt
    - src/admm/DsoOpt.jl
    - .planning/REQUIREMENTS.md
key-decisions:
  - "Sweep grid sized after timing a warm IEEE-123 ADMM point (about 50-60 s, A5 now measured): IEEE-123 xi {1,.5,0} x opt_out {0,.3} x rebound {none, W4 r1} with 2 seeds on the opt-out draw (18 points) + IEEE-13 wedge m {0,.5,1,2}; total about 19 min."
  - "Behavioural dW is W_ref(unwrapped) - W_row and is reported with sign: a wrapped device has a blended utility, so the W_soc <= W_opt guarantee (and the impossible_dW flag) applies only to the wedge block."
  - "No IEEE-123 wedge rows: the wedge block runs on IEEE-13 (plan scope); IEEE-123 rows are on the welfare objective."
requirements-completed: [ACTOR-01, ACTOR-02, ACTOR-03, ACTOR-04]
duration: ~3h
completed: 2026-11-02
---

# Phase 44 Plan 07: Sweep artifact, literate page and phase gates Summary

Committed measurement of retail wedge and behavioural scenarios (IEEE-123 and IEEE-13), a literate page that recomputes every figure from the CSV, and the repo gates (exports, JET ratchet, scripts index, docs registration) closed with ACTOR-01..04 marked complete.

## Tasks

1. Sweep + CSV + slow tests (`a6b6f63`): public-API orchestration (no `compare_tariffs`), DrWatson-activated, upsert keyed (fixture, wedge, xi, opt_out, r, seed). Slow test items "actor sweep" check schema/verdicts/identity anchor and re-solve the IEEE-13 m = 0.5 point (113 tests pass, 2m48s).
2. Literate page, registration, index row (`145336c`): page states the first-welfare-theorem framing, "not a strategic aggregator", and that the baseline is not `fit_baseline`'s output; numbers are computed from the CSV. `check_scripts_index.py` passes.
3. Gates (`bb77ef5`): export set audited (matches `keep`, no change needed); JET ratchet made green; ACTOR-01..04 closed.

## Measured results (from the committed CSV; julia 1.12.5)

- IEEE-13 wedge (ADMM, centralized cross-check): m = 0 gives dW = 0 exactly (bitwise pass-through); m = 0.5, 1, 2 give dW = 2.03e-3, 2.74e-3, 2.75e-3 (relative 4.2e-7 to 5.7e-7), i.e. growth then saturation; centralized DADP gap 3.9e-3 to 4.2e-3 (same order as the 44-02 pinned band). No impossible_dW.
- IEEE-123 behaviour (18 points, all converged in 35 iterations at this fixture): welfare spread over the whole grid is 3.4e-9 relative, mean DADP moves by at most 7.9e-6. At this fixture's device scales the flexible devices barely respond to the price, so xi / opt-out / rebound effects are at solver-noise level; this is the measured outcome, not a tuning target. The six xi = 0 rows are bitwise identical, as they must be (they describe the same population).
- All 22 rows are `ok`; `ledger_residual == 0.0` on every row; no refused rows occurred (the refusal path is exercised by construction and documented, not by data).
- Runtime: about 19 min total (IEEE-123 points 45-63 s, IEEE-13 points 44-60 s).

## JET ratchet

The ratchet had not been run since Phases 39-41: it reported 8 NEW signatures on the pre-phase commit `1506ef5` itself (20 reports then, 20 now). Phase 44 had added 2 more (`getindex(::Nothing, ::Int64)` in `build_dso_opt`, from `site_slot` being `Union{Nothing,Dict}`); fixed by making `site_slot` a concrete (possibly empty) `Dict{Int,Int}` (default path unaffected). The 8 pre-existing reports are Nothing-guard / conditionally-defined-local false positives and were recorded in two justified groups (4, 5) in `scripts/jet_baseline.txt`; check now reports 20 current, 20 baseline, 0 NEW, 0 FIXED (Julia 1.12.7, the pinned patch).

## Verification

- Slow: `test_actor_sweep.jl` 113/113.
- Fast regression set (actor_objective, default_fence, portfolio, behaviour, actor_settlement, knifeedge_canary, admm, agr, dso, admm_reactive, welfare_solve, settlement, flex_population, exports): 1240/1240 pass. `git diff` on goldens, fence, `expected_broken.txt`: empty. `jet_check.jl --selftest` and the full check pass; `check_scripts_index.py` passes.

## Deviations from Plan

- **[Rule 3 - Blocking]** The JET ratchet was already red before the phase (8 pre-existing NEW reports). Recorded them with justification after proving they predate Phase 44 (JET on the pre-phase commit in a temporary worktree, since removed) and fixed the 2 that Phase 44 introduced.
- The IEEE-123 block uses the welfare objective (no wedge); the wedge block is IEEE-13 only, as the plan specified.
- The reproduction test re-solves the IEEE-13 point through `IEEE13Fixtures` instead of including the script (the script needs DrWatson, not guaranteed in the test environment); the parameters are identical.
- `test_exports.jl` needed no change (the exported set already matched `keep`).

## Known Stubs

None.

## Self-Check: PASSED

Files exist: scripts/actor_behaviour_sweep.jl, results/actor_behaviour/actor_behaviour_sweep.csv, docs/literate/aggregator_actor.jl, test/test_actor_sweep.jl. Commits `a6b6f63`, `145336c`, `bb77ef5` exist.
