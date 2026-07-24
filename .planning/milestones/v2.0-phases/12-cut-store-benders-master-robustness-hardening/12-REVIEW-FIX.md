---
phase: 12-cut-store-benders-master-robustness-hardening
fixed_at: 2026-07-23T03:16:33Z
review_path: .planning/phases/12-cut-store-benders-master-robustness-hardening/12-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 12: Code Review Fix Report

**Fixed at:** 2026-07-23T03:16:33Z
**Source review:** .planning/phases/12-cut-store-benders-master-robustness-hardening/12-REVIEW.md
**Iteration:** 1

**Summary:**

- Findings in scope: 3 (fix_scope = critical_warning: CR-01, WR-01, WR-02)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-01: `master_status_trace` always records `:OPTIMIZE_NOT_CALLED` — status queried after cut appends dirty the master model

**Files modified:** `src/planning/benders.jl`, `test/test_planning_benders.jl`
**Commit:** 0cfa619
**Applied fix:** Captured `master_status_k = Symbol(termination_status(master.model))`
immediately after `solve_master!` returns — before `solve_follower!` and before any
`add_feasibility_cut!`/`add_optimality_cut!` call sets `is_model_dirty` on the
CACHING-mode master model — and used the captured symbol at both trace-push sites
(feasibility and optimality branches). `oracle_status` is still queried directly at the
push site, per the review's own analysis that `oracle.model` is never dirtied between
its solve and the query (only `master.model` receives cuts).

**RED/GREEN verification:** the WR-02 regression test was added FIRST and run against
the pre-fix code — it failed exactly as predicted
(`all(==(:OPTIMAL), result.trace.master_status_trace)` red; the oracle assertion green,
confirming only the master column was affected). After the fix, the testitem passed
17/17.

### WR-02: No test asserts the contents of `master_status_trace`

**Files modified:** `test/test_planning_benders.jl` (same commit as CR-01)
**Commit:** 0cfa619
**Applied fix:** Added to the end-to-end converging testitem:

```julia
@test all(==(:OPTIMAL), result.trace.master_status_trace)
@test result.trace.oracle_status_trace[end] == :OPTIMAL
```

Verified to fail against the pre-fix CR-01 behavior (see above), so the
always-`:OPTIMIZE_NOT_CALLED` defect can no longer ship green.

### WR-01: `solve_time_trace` measures checkpoint I/O and git provenance stamping, not subproblem solve time

**Files modified:** `src/planning/benders.jl`, `src/planning/trace.jl`
**Commit:** e992d70
**Applied fix:** Option (a) from the review — the docstring-matching fix. Each
iteration now accumulates `t_solve` by bracketing ONLY the three solve calls
(`solve_master!`, `solve_follower!`, and `solve_planning_oracle!` on the optimality
branch) and pushes `solve_time = t_solve`. `checkpoint_iteration!`'s JLD2 write + git
provenance shell-outs, cut appends, and trace bookkeeping are excluded from the
measurement. Per the fixer instructions, IN-04 was folded in since the same lines were
rewritten: the brackets use the monotonic clock (`time_ns()`, converted via `/ 1.0e9`)
instead of the NTP-adjustable `time()`, so a backward clock step can no longer produce
a negative `solve_time` that trips `push!`'s `solve_time >= 0` guard mid-run.
`trace.jl`'s `solve_time_trace` field doc was tightened to state the solve-calls-only,
monotonic-clock contract explicitly.

## Skipped Issues

None — all in-scope findings were fixed.

Out-of-scope Info findings NOT addressed (fix_scope = critical_warning): IN-01
(`Ref(0)` sentinel), IN-02 (`n_cuts_trace` +2/+1 doc), IN-03 (inert feasibility cuts in
the LB-monotonicity episode), IN-05 (solver-version-pinned iteration band). IN-04 was
addressed as part of WR-01 (explicitly authorized as trivially co-located).

## Deviations

### Pre-existing test-environment defect unblocked (extra commit af9c60b)

The mandated final full-suite gate (`julia --project=. -e 'using Pkg; Pkg.test()'`)
failed on FIRST run with an error **unrelated to any fix in this session**:
`test/test_planning_hardening.jl:211`'s `using Logging: Warn` (introduced pre-review in
commit 2b5a594, plan 12-02's load test) raised
`ArgumentError: Package Logging not found in current path` inside the Pkg.test sandbox,
because the `Logging` stdlib was never declared in `test/Project.toml`. Verified
pre-existing: none of this session's changes touch that file or any package
environment, and the fast `:planning` filter (which excludes the `:slow` load test)
passed 184/184 both before and after the review fixes. Fixed minimally by declaring
`Logging` in `test/Project.toml` `[deps]` (stdlib — no compat pin) and re-resolving
`test/Manifest.toml` (project-hash-only change; Logging was already a transitive
manifest entry). Committed separately as `fix(12): declare Logging stdlib in test env
(unblocks full-suite gate under Pkg.test)` (af9c60b) so it is trivially revertable and
auditable apart from the review-finding fixes.

### Worktree isolation skipped

Per the orchestrator's explicit fix note ("Work on the main working tree"), all edits
and commits were made directly on `main` in the main working tree; no isolated
reviewfix worktree/branch/sentinel was created.

## Verification

- **RED/GREEN on CR-01/WR-02:** regression test added first, confirmed red pre-fix,
  green post-fix (17/17 in the end-to-end testitem).
- **Fast filter after fixes:** `:planning` (excluding `:slow`) — 184/184 pass.
- **Formatting:** JuliaFormatter 2.10.1 (project `.JuliaFormatter.toml`) run on every
  touched `.jl` file before its commit; reflows folded into the fix commits.
- **Full-suite gate:** `Pkg.test()` — **4097 passed / 0 failed / 0 errored / 4
  documented-broken**, `Testing TSODSO tests passed`, exit 0 (after the af9c60b
  test-env fix; the identical suite errored on the pre-existing Logging defect before
  it).

## Commits

| Commit  | Finding(s)    | Files |
|---------|---------------|-------|
| 0cfa619 | CR-01 + WR-02 | `src/planning/benders.jl`, `test/test_planning_benders.jl` |
| e992d70 | WR-01 (+IN-04 co-located) | `src/planning/benders.jl`, `src/planning/trace.jl` |
| af9c60b | (deviation: pre-existing test-env defect) | `test/Project.toml`, `test/Manifest.toml` |

---

_Fixed: 2026-07-23T03:16:33Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
