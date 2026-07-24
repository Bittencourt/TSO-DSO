---
phase: 10-oracle-coupling-wiring-resilience
plan: 01
subsystem: infra
tags: [julia, jump, clarabel, drwatson, jld2, resilience, retry, checkpoint]

# Dependency graph
requires:
  - phase: 09-documentation-regression-acceptance-gate
    provides: "assert_solved! (INFRA-03 choke point), select_optimizer (INFRA-02 factory), run_and_store's @tagsave/DrWatson provenance idiom"
provides:
  - "solve_with_retry! -- bounded, escalating Clarabel-conditioning retry wrapper around assert_solved! (D-08/D-09)"
  - "checkpoint_iteration!/resume_from_checkpoint -- per-iteration JLD2 checkpoint save/resume with git-commit provenance (D-10)"
affects: [10-02, phase-11-benders-master-follower, phase-12-cut-store-master-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Retry-ladder middleware: catch assert_solved!'s plain ErrorException, re-query termination_status(model)/raw_status(model) inside the catch block (still valid post-throw), branch retry vs re-raise on RETRYABLE_STATUSES"
    - "Checkpoint-file naming: zero-padded iter_NNNNN.jld2 so lexicographic sort == numeric sort, enabling resume_from_checkpoint to trust readdir+sort for 'highest-numbered'"

key-files:
  created:
    - src/planning/retry.jl
    - src/planning/checkpoint.jl
    - test/test_planning_retry.jl
    - test/test_planning_checkpoint.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "Ill-conditioned SOCP retry-test fixture combines a >=1e6 coefficient-magnitude spread (project's documented per-unit-base cone-slack sensitivity) with a deliberately tight max_iter attribute -- pure coefficient scaling alone did not reproduce a retryable Clarabel status (Clarabel's automatic equilibration proved robust up to 1e16 spread in isolation); solve_with_retry!'s ladder never touches max_iter, so the fixture reliably reproduces a RETRYABLE_STATUSES failure on every attempt, empirically verified before either RED or GREEN commit (10-RESEARCH.md Pitfall 4)."
  - "Test fixtures build models via TSODSO.select_optimizer(TSODSO.SOCP()) (the project's own factory), never `using Clarabel` directly in a test file -- matches every other test file in the suite (INFRA-02) and is required for the fixture to resolve under Pkg.test()'s sandboxed test environment, which does not expose main-project deps as directly `using`-able unless also listed in test/Project.toml."

patterns-established:
  - "solve_with_retry!(model; max_attempts=4, dual=true): 4-rung escalating Clarabel conditioning ladder, wraps assert_solved! verbatim, never rebuilds, never falls back to SCS, raises assert_solved!'s exact diagnostic format plus exhausted-attempt-count on budget exhaustion or non-retryable status"
  - "checkpoint_iteration!/resume_from_checkpoint: reuses store.jl's @tagsave idiom verbatim (gitpath = pkgdir(@__MODULE__), safe = true); resume always treats the highest-numbered checkpoint file as 'redo, never trust-complete'"

requirements-completed: [PLAN-03]

# Metrics
duration: 77min
completed: 2026-07-22
---

# Phase 10 Plan 01: Oracle Resilience Primitives Summary

**`solve_with_retry!` (4-rung escalating Clarabel-conditioning ladder around `assert_solved!`) and `checkpoint_iteration!`/`resume_from_checkpoint` (JLD2 per-iteration checkpoint, always redoing the highest-numbered iteration) — both proven independently before Phase 11's Benders loop consumes them.**

## Performance

- **Duration:** 77 min (12:53 -> 14:10 local, commits span ~7 min; remainder is research/empirical fixture verification + two full-suite regression runs)
- **Started:** 2026-07-22T15:53:24Z (first commit)
- **Completed:** 2026-07-22T17:10:00Z (approx, final full-suite verification)
- **Tasks:** 2 (both TDD: RED test commit + GREEN implementation commit each, plus one Rule-1 fix commit)
- **Files modified:** 5 (2 created source files, 2 created test files, 1 modified — `src/TSODSO.jl`)

## Accomplishments

- `solve_with_retry!` wraps the project's sole INFRA-03 choke point (`assert_solved!`) with a bounded, 4-rung escalating Clarabel-conditioning ladder — recoverable `NUMERICAL_ERROR`/`SLOW_PROGRESS`/`ALMOST_OPTIMAL` statuses escalate through post-build `set_optimizer_attribute` calls (no rebuild, no SCS fallback); genuinely non-retryable statuses (e.g. `INFEASIBLE`) raise immediately, never wasting the retry budget
- `checkpoint_iteration!`/`resume_from_checkpoint` round-trip Benders-iteration state through JLD2, reusing `src/experiments/store.jl`'s `@tagsave` provenance idiom verbatim; `resume_from_checkpoint` always reports the highest-numbered checkpoint as "redo," never "trust-complete"
- Empirically verified (not guessed) an ill-conditioned SOCP fixture that reliably reproduces a `RETRYABLE_STATUSES` failure, after discovering that Clarabel's automatic equilibration is robust to pure coefficient-magnitude scaling alone up to 1e16 spread

## Task Commits

Each task followed the TDD RED -> GREEN cycle:

1. **Task 1: `solve_with_retry!`**
   - `e129958` (test) — RED: failing `@testitem`s for recoverable-escalation and non-retryable-immediate-raise
   - `ecee1d1` (feat) — GREEN: `solve_with_retry!` implementation + `src/TSODSO.jl` wiring
   - `35fd483` (fix) — Rule 1 auto-fix: removed a direct `using Clarabel` from the test fixture (INFRA-02 violation that also broke under `Pkg.test()`'s sandboxed env), found during full-suite regression verification
2. **Task 2: `checkpoint_iteration!`/`resume_from_checkpoint`**
   - `b18c314` (test) — RED: failing `@testitem`s for round-trip and highest-numbered-always-redo
   - `d372aae` (feat) — GREEN: `checkpoint_iteration!`/`resume_from_checkpoint` implementation + `src/TSODSO.jl` wiring

**Plan metadata:** this commit (docs: complete plan) — see final commit below.

## Files Created/Modified

- `src/planning/retry.jl` — `RETRYABLE_STATUSES`, `solve_with_retry!` (102 lines)
- `src/planning/checkpoint.jl` — `checkpoint_iteration!`, `resume_from_checkpoint` (76 lines)
- `test/test_planning_retry.jl` — 2 `@testitem`s, `[:planning]` tagged (65 lines)
- `test/test_planning_checkpoint.jl` — 2 `@testitem`s, `setup = [Phase8Fixtures]`, `[:planning]` tagged (42 lines)
- `src/TSODSO.jl` — appended a new `planning/` include block (2 lines + 7-line header comment) after `admm/solve_admm.jl` / `models/oracle.jl`, before `diagnostics/plots.jl`

## Decisions Made

- **Ill-conditioned SOCP fixture design:** the plan asked for a fixture reproducing a retryable Clarabel failure via coefficient-magnitude spread alone (>= 1e6). Empirically, Clarabel's `equilibrate_max_iter` auto-scaling absorbed spreads up to 1e16 without failing (tested across several structurally different SOCP shapes: single-cone alternating scale, multi-cone, badly-scaled equality constraints, disabled equilibration, near-zero regularization). The fixture that reliably reproduces a `RETRYABLE_STATUSES` result combines the required >= 1e6 coefficient spread with a tightened `max_iter` set at model-build time (outside `solve_with_retry!`'s own ladder, which never touches `max_iter`) — this is an honest, reproducible way to exercise the retry path without guessing, and both possible test outcomes (recovers to `OPTIMAL` or exhausts with `"exhausted"` in the message) were left as valid per the plan's own acceptance criteria.
- **No direct `using Clarabel`/`HiGHS`/`Ipopt` in any test file:** confirmed this is a project-wide convention (grep across `test/*.jl` before writing the fixture) and is required for `Pkg.test()`'s sandboxed test environment to resolve at all.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test fixture named a solver directly, breaking under `Pkg.test()`'s sandbox**
- **Found during:** Task 1, discovered during the full-suite `Pkg.test()` regression verification (not caught by the scoped filtered test run, which used a scratch environment with `Clarabel` explicitly `Pkg.add`ed)
- **Issue:** `test/test_planning_retry.jl`'s ill-conditioned-SOCP fixture did `using TSODSO, JuMP, Clarabel` and built the model via `optimizer_with_attributes(Clarabel.Optimizer, ...)`. This is the only test file in the entire suite that names a solver package directly (verified by grep) — it violates INFRA-02 ("no solver named outside the factory") and fails outright under `Pkg.test()`'s sandboxed test environment (`ArgumentError: Package Clarabel not found in current path`), because `Pkg.test()` only merges `test/Project.toml`'s explicit deps into the sandbox, not the main package's own `[deps]`.
- **Fix:** Rebuilt the fixture via `TSODSO.select_optimizer(TSODSO.SOCP())` (the project's own factory, already sets `verbose=false`/`tol_gap_abs=1e-8`/`tol_gap_rel=1e-8`) and applied the tightened `max_iter` post-build via `set_optimizer_attribute` — the identical idiom `solve_with_retry!` itself uses.
- **Files modified:** `test/test_planning_retry.jl`
- **Verification:** Re-ran the scoped filtered test (5/5 pass) and the full `julia --project=. -e 'import Pkg; Pkg.test()'` suite (1957 passed, 0 failed, 2 documented-broken, matching the pre-existing v1.0 baseline of 1946 + 11 new assertions from this plan).
- **Commit:** `35fd483`

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug)
**Impact on plan:** Necessary correctness fix surfaced only by running the authoritative full-suite gate; no scope creep, no change to the delivered primitives' behavior or public API.

## Issues Encountered

- **`TestItemRunner.runtests(...)` (the plan's literal `<automated>` verify command) does not exist** in the pinned `TestItemRunner` 1.1.5 API — only `TestItemRunner.run_tests(path; filter, verbose)` and the `@run_package_tests` macro exist, and `TestItemRunner` is a test-only dependency not resolvable from the main project environment. This mirrors a documented deviation pattern from every prior v1.0 phase (e.g. `01-01-SUMMARY.md`, `02-02-SUMMARY.md`): resolved by building a throwaway scratch environment (`Pkg.develop` the worktree + `Pkg.add TestItemRunner`/`JuMP`/`Clarabel`/`DrWatson`/`StableRNGs`) for scoped filtered runs during RED/GREEN verification, and using the authoritative `julia --project=. -e 'import Pkg; Pkg.test()'` for the final full-suite regression gate. Not a code issue in this plan's deliverables.
- **Clarabel's automatic equilibration proved far more robust than expected** to pure coefficient-magnitude scaling (tested up to 1e16 spread across several SOCP shapes without triggering any `RETRYABLE_STATUSES` result) — required combining the required coefficient spread with a tightened `max_iter` to reliably reproduce a retryable failure. Documented as a Key Decision above; the resulting fixture still satisfies every plan acceptance criterion (>= 1e6 spread, raw-optimize! confirmation before wrapping, either-outcome assertion).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `solve_with_retry!` and `checkpoint_iteration!`/`resume_from_checkpoint` are both independently proven (11 new passing assertions) and exported from `TSODSO`, ready for plan 10-02 to wire into `solve_planning_oracle!`.
- Full regression suite confirmed healthy: 1957 passed / 0 failed / 2 documented-broken (unchanged from the v1.0 baseline plus this plan's 11 new assertions) — no Phase 1-9 source file was modified, per D-03/D-11.
- No blockers for plan 10-02.

## Self-Check: PASSED

- All created files verified present on disk: `src/planning/retry.jl`, `src/planning/checkpoint.jl`, `test/test_planning_retry.jl`, `test/test_planning_checkpoint.jl`, this SUMMARY.md.
- All referenced commit hashes verified present in `git log`: `e129958`, `ecee1d1`, `b18c314`, `d372aae`, `35fd483`.
