---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 07
subsystem: experiments
tags: [phase-gate, certification, full-suite, docs]
requires: [32-06]
provides: [phase-32-certification]
key-files:
  created: [.planning/phases/32-declarative-power-flow-strategy-dispatch/32-07-SUMMARY.md]
  modified:
    - .planning/phases/32-declarative-power-flow-strategy-dispatch/32-VALIDATION.md
    - test/test_planning_noninteger.jl
    - docs/src/api.md
requirements-completed: [ARCH-01, ARCH-02]
duration: ~75min
completed: 2026-10-03
---

# Phase 32 Plan 07: Phase Gate Summary

**Phase 32 certified: the full suite is 31762 passed / 0 failed / 0 errored / 5 broken at 03b91a5, every numeric golden is unchanged, and the docs build exits 0.**

Executed inline by the orchestrator. The memory note `background-suite-orphan-race` says the detached full-suite run should be owned by the orchestrator.

## Source gates
- (a) `ConvexBranchFlow()` has zero hits in `src/experiments/run.jl`, `mpc_loop.jl` and `run_stochastic.jl`. The executable code no longer hard-codes it anywhere.
- (b) The anchored grep `\bs\.(ρ|maxiter|ε_abs|ε_rel|τ_ratio|μ|mpc_|stoch_)` finds 2 hits, both in comments: `test/test_admm_reactive.jl:39` and `test/test_mpc_loop.jl:8`.
- (c) `fieldnames(Scenario)` is `(:name, :feeder, :seed, :T, :population, :price, :allow_export, :pf, :pf_thesis_literal, :pf_ε, :strategy)`, which is 11 fields with no flat strategy knobs.
- (d) The tree is clean. No phase-32 commit touched `Project.toml` or `Manifest-v1.12.toml`, and `git worktree list` shows no `.claude/worktrees/agent-*`.

## Certification runs
- **Run 1 (b3c88e6, start 15:23:41):** 31761 passed, 1 failed, 0 errored, 5 broken.
  - The failure was PVAL-04 (`test_planning_noninteger.jl:241`). The plan 32-02 export of `build_powerflow` tripped the guard that checks every exported `build_*` symbol, which is what the guard is designed to do.
  - The docs build failed `checkdocs = :exports` on 4 docstrings from `planning/feasibility_oracle.jl` and `planning/ac_recheck.jl`. That gap dates from Phase 30; neither file was listed in `api.md`.
- **Fixes:**
  - 7913eb3 adds `build_powerflow` to the PVAL-04 operational-builder allowlist, with a written reason.
  - 03b91a5 adds the two planning files to the Planning Layer Pages in `docs/src/api.md`.
  - `test_planning_noninteger.jl` alone then passed 10 of 10.
- **Run 2 (03b91a5, log start 16:01:42, after commit 16:01:02):**
  - The full suite gave **31762 Pass / 0 Fail / 0 Error / 5 Broken** of 31767 total, in 29m26s. The count parser printed COUNTS OK.
  - The docs build (`julia --project=docs docs/make.jl`) exited 0.

## Goldens (bit-identical)
- **ADMM knife-edge canary:** `iters = 56`, `welfare = -4823.66604824162`. It passed unchanged.
- **Unchanged assertions:** the stochastic golden, the 356 MPC-loop assertions, and the centralized/ADMM same-seed repro all passed without changes. Only filename strings changed, which was documented and accepted.

## Deviations
- **[Rule 1 - Bug]** Plan 32-02 left `build_powerflow` off the PVAL-04 allowlist. Fixed in 7913eb3.
- **[Rule 3 - Blocking, pre-existing]** The docs `checkdocs` failure came from Phase 30, not this phase. It was fixed in 03b91a5 because it blocked this plan's docs gate.

## Self-Check: PASSED
