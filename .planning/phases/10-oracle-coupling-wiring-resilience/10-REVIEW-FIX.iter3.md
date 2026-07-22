---
phase: 10-oracle-coupling-wiring-resilience
fixed_at: 2026-07-22T20:55:00-03:00
review_path: .planning/phases/10-oracle-coupling-wiring-resilience/10-REVIEW.md
iteration: 2
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-07-22T20:55:00-03:00
**Source review:** .planning/phases/10-oracle-coupling-wiring-resilience/10-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 1 (1 Warning; fix_scope = critical_warning — the 6 Info findings
  IN-01..IN-06 were not in scope, and 4 of them are explicitly "no action now" carries)
- Fixed: 1
- Skipped: 0

**Verification:** the edited file parse-checked (`Meta.parseall`), the new testitem run
in isolation via TestItemRunner (10/10 assertions pass, confirming the SOCP gate branch
EXECUTES — `ctx.meta[:socp_maxgap]` absent before the solve, present and `< 1e-5`
after), and the full `:planning`-tagged suite re-run: **62/62 pass** (52 prior + 10 new),
exit 0. The touched file was verified already conformant to the CI-enforced
`.JuliaFormatter.toml` (JuliaFormatter v2 `format_file` reported no change).

## Fixed Issues (iteration 2)

### WR-01: The CR-03 SOCP exactness-gate wiring in `solve_planning_oracle!` has zero test coverage

**Files modified:** `test/test_planning_oracle.jl`
**Commit:** 4919817
**Applied fix:** Added the review's suggested `ConvexBranchFlow`-backed oracle testitem
("planning oracle: ConvexBranchFlow solve runs the PF-04 exactness gate and stashes
socp_maxgap (CR-03)", tags `[:planning]`, setup `[Phase6Fixtures]` — file conventions,
no direct solver imports per INFRA-02). It follows the file-header z_trial-feasibility
convention: the pin point is the network's OWN unconstrained free-import optimum derived
under the SAME formulation via the unmodified free path
(`operational_oracle(feeder, ConvexBranchFlow(), aggs; z = nothing, allow_export = true)`)
— the near-lossless 2-bus fixture whose free ConvexBranchFlow solve is already
certified exact by the ADMM cross-validation item, so pinning `z = z*` reproduces the
exact solution and the gate must PASS. The item proves the previously-dead branch end to
end: (1) pre-solve, the SOCP arm is ARMED — `haskey(o.ctx.meta, :pf_vars)` and
`haskey(o.ctx.meta[:pf_vars], :l)` (the exact haskey chain `solve_planning_oracle!`
branches on) and `!haskey(o.ctx.meta, :socp_maxgap)`; (2) post-solve, the gate RAN and
PASSED — `haskey(res.ctx.meta, :socp_maxgap)` (written nowhere else on the oracle path),
`isa Float64`, and `< 1e-5` (test_exactness.jl's exact-point bound); (3) `π`/`dadp` are
finite length-T, i.e. prices were returned rather than refused. Semantics verified by
the passing testitem executing the gate live, not just a syntax check.

The review's OPTIONAL pairing (a deliberately-inexact pinned fixture asserting
`@test_throws`) was considered and not added: constructing a z_trial that is
simultaneously FEASIBLE for the high-PV fixture's narrow import band AND provably
cone-slack is empirical/solver-sensitive, and a flaky refusal test would be worse than
none. The refusal direction of `assert_socp_exact!` itself is already covered directly
by two `@test_throws` items in `test/test_exactness.jl`; what WR-01 flagged as untested
— the oracle-path wiring (haskey chain, meta key, gate invocation) — is now exercised
live.

## Skipped Issues (iteration 2)

None — the single in-scope finding was fixed.

---

## Iteration 1 history (7 findings: 3 Critical + 4 Warning, all fixed)

Fixed at 2026-07-22T18:38:00-03:00 against the iteration-1 REVIEW.md (backed up at
`10-REVIEW.iter2.md`). Verification then: every fix parse-checked, `:planning` suite
48/48, full `Pkg.test()` 1994 pass / 2 pre-existing `@test_broken` / 0 failures.
Iteration 2's re-review verdict: "all 7 prior findings are soundly fixed."

- **CR-01** (`solve_with_retry!` silent `nothing` fall-through) — commit `4d59130`,
  `src/planning/retry.jl` + `test/test_planning_retry.jl`: `max_attempts >= 1`
  ArgumentError guard; ladder-aware `n_attempts = min(max_attempts, length(ladder))` so
  the final rung always returns or errors loudly; regression tests for the overshoot
  budget and the `<= 0` untouched-model path.
- **CR-02** (`resume_from_checkpoint` returned stale safesave backups) — commit
  `034d66f`, `src/planning/checkpoint.jl` + `test/test_planning_checkpoint.jl`: resume
  scan filtered to canonical `r"^iter_\d{5}\.jld2$"` names; double-/triple-save and
  foreign-file regression tests.
- **CR-03** (oracle returned duals without the PF-04 exactness gate or App. C battery
  check) — commit `75993e2`, `src/planning/subproblem.jl`: both trust gates mirrored
  from `solve_welfare` strictly between the retry-gated solve and any dual read;
  problem-class-aware `τ` default via the `:problem_class` build-time stash; `maxgap`
  stashed under `ctx.meta[:socp_maxgap]`. (Its SOCP branch's test coverage gap is what
  iteration 2's WR-01 closed, above.)
- **WR-01 iter-1** (sticky escalation attributes) — commit `529db8e`,
  `src/planning/retry.jl`: stickiness made an explicit documented contract; every rung
  >= 2 a complete attribute set (rung 4 restates `equilibrate_max_iter => 50`).
- **WR-02** (Clarabel raw attrs on a generic model) — commit `c99d399`,
  `src/planning/retry.jl`: attribute rejection converted into the loud D-10 four-line
  diagnostic naming backend, attribute, original error, and status quadruple.
- **WR-03** (unbounded checkpoint iteration numbers) — commit `b2f65ad`,
  `src/planning/checkpoint.jl` + `test/test_planning_checkpoint.jl`: `0 <= iter <=
  99999` ArgumentError guard with boundary-value tests.
- **WR-04** (solver-version-pinned retry fixture) — commit `0a587ff`,
  `test/test_planning_retry.jl`: precondition softened to `!= MOI.OPTIMAL`; escalation
  branch gated on `raw_ts in RETRYABLE_STATUSES`, degrading to an `@info` skip on
  solver drift.
- **Style** — commit `e8f9911`: JuliaFormatter v2 pass over the iteration-1 touched
  files; no semantic changes.

---

_Fixed: 2026-07-22T20:55:00-03:00_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
