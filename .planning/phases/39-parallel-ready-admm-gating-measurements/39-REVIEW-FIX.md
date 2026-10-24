---
phase: 39-parallel-ready-admm-gating-measurements
fixed_at: 2026-10-24T10:37:57Z
review_path: .planning/phases/39-parallel-ready-admm-gating-measurements/39-REVIEW.md
iteration: 1
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 39: Code Review Fix Report

**Fixed at:** 2026-10-24T10:37:57Z
**Source review:** .planning/phases/39-parallel-ready-admm-gating-measurements/39-REVIEW.md
**Iteration:** 1
**Scope:** Critical + Warning (Info findings IN-01..IN-08 out of scope this round)

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

## Fixed Issues

### WR-01: First-failure join abandons in-flight tasks — unawaited solver runs leak past the throw

**Files modified:** `src/admm/admm_phases.jl`
**Commit:** 3af9bec
**Status:** fixed: requires human verification (drain logic is simple and attribution parity is test-covered under `-t 4`, but no test directly asserts the reaping effect itself — that no solver work survives past the throw; the error-parity leg asserts exception type/message only)

**Applied fix:** Wait-drain on the error path only (the review's stated alternative, chosen over the `first_err` restructure to keep the threaded success path *statement*-identical and preserve `rethrow()` stack-trace semantics for non-`TaskFailedException` errors). Inside the existing join's `catch` block, before the PAR-03 unwrap/rethrow, the loop now `wait`s every remaining future `idx+1..length(futs)` (reap-and-discard with an explicitly commented empty `catch`, per the review's empty-catch-audit note), so no Clarabel solve keeps running after the throw — and after `solve_admm`'s `finally` restores BLAS threads. First-failure-in-`load_nodes`-order attribution is untouched: `throw(e.task.exception)` / `rethrow()` fire at the same site with the original exception object. The serial branch is byte-identical (untouched). Docstring point 3 updated to document the error-path reap.

**Verification (3 tiers):**
- Tier 1: re-read of modified sections — fix present, surrounding code intact, serial branch untouched.
- Tier 2: `Meta.parseall` on the file — parse OK (14 top-level exprs).
- Test evidence (Julia 1.x, worktree of `agents/session-2026-10-23` @ `d6e780c`):
  - `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` → **33/33 pass** (2m44s). Includes the bitwise serial-vs-threaded equality item (serial/threaded iters both 56, welfare both −4823.66604824162) and all three error-parity legs — leg 3 (`SolveFailedError` via task-body unwrap, poisoned aggregator j=3) **executes the new drain path directly** and passes with type + message parity, no wrapper types.
  - `TSODSO_TEST_FILES=test_admm_parallel.jl ...` (1 thread) → 4 pass, 2 broken = exactly the 2 `expected_broken.txt` allowlisted thread-gated skips.
  - `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl ...` → **5/5 pass** (1m52s); canary unchanged: `iters = 56`, `welfare = -4823.66604824162`, `escalations = 0`.

## Skipped Issues

None.

## REVIEW.md note

The review file has no per-finding status field convention (findings carry File/Issue/Fix only; frontmatter `status:` is the overall review status), so 39-REVIEW.md was left untouched per workflow instructions.

---

_Fixed: 2026-10-24T10:37:57Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
