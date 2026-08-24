---
phase: 24
slug: discrete-integer-investment-expansion
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-23
approved: 2026-08-23
---

# Phase 24 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `24-RESEARCH.md`'s `## Validation Architecture` section and the final
> 24-01..24-06 PLAN.md files (populated during phase planning, per the plan-checker's
> Blocker 1 requirement that every phase in this milestone carries one).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` (stdlib) for per-task quick checks; TestItems 1.0.0 / TestItemRunner 1.1.5 (test-only, discovered via `test/runtests.jl`) for the real `@testitem` suite |
| **Config file** | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| **Quick run command** | A plain `julia --project=. -e '...'` script (Test-free, `@assert`-based) that inlines the fixture construction directly (self-contained copies of `Phase6Fixtures`/`ToyDeviceFixture`'s shape where the test-only `@testmodule`s are unreachable from a raw script) and asserts the same behavioral claim(s) as the corresponding `@testitem`(s). Per this repo's MANDATORY testing constraint: **never** `julia --project=test -e '...@run_package_tests...'`, and **never** TestItemRunner invoked under `--project=.` for a quick loop. One such command is embedded in each per-task `<verify><automated>` across 24-01..24-06's PLAN.md files. |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint, runs every `@testitem` including the new ones; ~23 min per MEMORY.md's documented baseline; run in background, only at the phase-closing gate — plan 24-06 Task 2 is the sole plan permitted to run it as an acceptance gate) |
| **Estimated runtime** | Quick command: <20s per task. Full suite: ~23 min (run once, only as the phase-closing gate in plan 24-06 Task 2 — not run per task or per wave). |

> **TRAP — do not invoke TestItemRunner directly in a `<verify>` block.** MEMORY.md documents
> `julia --project=test -e '...@run_package_tests...'` as a sibling-worktree contamination
> hazard (cwd-based root resolution picks up sibling worktrees). Every per-task `<verify>`
> command in this phase's PLAN.md files is either a direct `Test`-free `julia --project=. -e`
> script, or the full `Pkg.test()` entrypoint — never the raw TestItemRunner macro.

---

## Sampling Rate

- **After every task commit:** run that task's own plain-script quick command (<20s) — embedded
  verbatim in each PLAN.md task's `<verify><automated>` block
- **After every plan wave:** re-run each wave's task-level `<verify>` inline scripts (idempotent);
  defer full `@testitem` execution to the phase-closing gate
- **Before `/gsd:verify-work`:** full suite must be green -- `julia --project=. -e 'import Pkg; Pkg.test()'`
  (plan 24-06 Task 2 is the ONLY plan in this phase permitted to run it), `0` new failures beyond
  the project's pre-existing known-false Aqua/CairoMakie-drift pair, `passed` = pre-phase baseline
  (2358, per MEMORY.md) + this phase's tallied new-`@testitem` count
- **Max feedback latency:** 20 seconds for the per-task quick command; the full-suite gate is
  intentionally infrequent (once, at phase close) -- the SAME discipline Phases 20/21/22/23/25
  already established

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | INT-01 | T-24-01 | `select_optimizer(::MILP())` sets `mip_rel_gap=>0.0`; a standalone binary-knapsack MILP solves `OPTIMAL` to the exact known integer answer without stalling | unit | plain-script quick command (24-01-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `test/test_solver_factory_milp.jl` | ⬜ pending |
| 24-01-02 | 01 | 1 | INT-01 | T-24-01 / T-24-02 / T-24-03 | `BendersMasterInteger`/`build_master_integer` build a K=4 binary-expansion MILP master; zero-cut first solve is `OPTIMAL`; the all-ones corner reaches `y_max*(1-2^-K)` exactly (D-02); `L=α_op_lb+α_x_lb` is confirmed by sampling the real oracle/follower across `[0,y_max]` | unit/regression | plain-script quick command (24-01-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- new `src/planning/master_integer.jl`, `test/test_planning_master_integer.jl` | ⬜ pending |
| 24-02-01 | 02 | 2 | INT-01 | T-24-04 | `add_optimality_cut!`/`add_feasibility_cut!` fire against `BendersMasterInteger` with unchanged algebra; constraint count grows by exactly the number of cuts appended, variable count unchanged | unit/regression | plain-script quick command (24-02-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- extends `test/test_planning_master_integer.jl` | ⬜ pending |
| 24-02-02 | 02 | 2 | INT-04 | T-24-05 / T-24-06 | `build_master_integer` is registered + on an explicit `EXEMPT` list in the PVAL-04 guard; the exemption asserts binaries ARE present (never a blind skip); every other registry entry's no-binaries assertion is unchanged; the source-scan tripwire still holds | unit/regression | plain-script quick command (24-02-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- extends `test/test_planning_noninteger.jl` | ⬜ pending |
| 24-03-01 | 03 | 3 | INT-02 | T-24-07 / T-24-08 | The Laporte-Louveaux cut is tight at the incumbent `b^ν` and implied-elsewhere (never excludes) at all 15 other K=4 corners (exhaustive, not sampled); the no-good cut forbids exact re-visitation of a specific corner while leaving every other corner feasible | unit | plain-script quick command, exhaustive 16x16 corner sweep (24-03-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- extends `test/test_planning_master_integer.jl` | ⬜ pending |
| 24-03-02 | 03 | 3 | INT-02 | T-24-09 | `BendersTrace` gains an additive `nogood_count_trace` column; every pre-existing `push!` call site (which omits the new keyword) records `0` and is otherwise unaffected; `trace_summary` exposes `total_nogoods` | unit/regression | plain-script quick command (24-03-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- new `test/test_planning_trace.jl` (or extends an existing `BendersTrace` test file, per the plan's own "check first" instruction) | ⬜ pending |
| 24-04-01 | 04 | 4 | INT-02 | T-24-10 / T-24-11 / T-24-18 | `solve_stackelberg!` accepts `master`/`known_optimum` kwargs; default path byte-identical (`y≈0.7`, `UB≈-0.245` on the D-12 fixture); `converged_now` is a mutually EXCLUSIVE branch on `known_optimum`, proven by an adversarial unit case (gap<=tol true, known_optimum mismatched -> must NOT converge) -- the direct regression against plan-checker Blocker 2 | unit/regression | plain-script quick command (24-04-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `test/test_planning_benders_integer.jl` | ⬜ pending |
| 24-04-02 | 04 | 4 | INT-02 | T-24-12 | `apply_integer_cuts!` fires generically on the optimality branch for both master types; `nogood_count`/`converged_via` are present on every returned NamedTuple; the end-to-end integer smoke run completes without a `MethodError`/`UndefVarError` | integration | plain-script quick command (24-04-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- extends `test/test_planning_benders_integer.jl` | ⬜ pending |
| 24-05-01 | 05 | 5 | INT-03 | T-24-13 | `enumerate_lattice` computes the true K=4 lattice optimum via REAL `solve_follower!`/`solve_planning_oracle!` solves (never the archived closed form), using the IDENTICAL `y_inv(b)` formula `build_master_integer` uses | unit | plain-script quick command (24-05-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `test/test_planning_certification_integer.jl` | ⬜ pending |
| 24-05-02 | 05 | 5 | INT-02 / INT-03 | T-24-14 / T-24-15 / T-24-18 | Gate-then-golden: `solve_stackelberg!` on the D-12 fixture matches the enumerated optimum exactly (D-14); every fired LL cut is valid against the TRUE enumerated optimum (D-15 cert 1); the continuous PVAL-02 golden brackets the integer answer (D-15 cert 2); `nogood_count`/`converged_via` are present (D-16); the D-11 BilevelJuMP non-blocker is documented, not re-attempted; a DELIBERATELY WRONG `known_optimum` is REJECTED (raises, never falsely converges) -- the negative-control regression closing Blocker 2 on the certified path itself | integration/regression | full-suite `@testitem` (24-05-PLAN.md Task 2 `<verify>`, background) | n/a (extends the Wave-0 file from Task 1) | ⬜ pending |
| 24-06-01 | 06 | 6 | INT-04 | T-24-16 | `docs/literate/integer_investment.jl` exists, covers all nine required narrative sections, is live-executed with zero hardcoded literals, imports no test-only solver package | docs/lint | grep-based quick check (24-06-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `docs/literate/integer_investment.jl` | ⬜ pending |
| 24-06-02 | 06 | 6 | INT-04 | T-24-17 | `docs/make.jl` wires the new page into both the Literate loop and the `"Planning"` pages tree; full suite green: `0` new failures beyond the pre-existing known-false Aqua/CairoMakie-drift pair, `passed` = baseline + this phase's tallied new-`@testitem` count | full-suite | `julia --project=. -e 'import Pkg; Pkg.test()'` (24-06-PLAN.md Task 2 `<verify>`) | n/a (acceptance gate) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_solver_factory_milp.jl` -- new file, plan 24-01 Task 1 (INT-01, MILP exactness fix)
- [ ] `test/test_planning_master_integer.jl` -- new file, plan 24-01 Task 2 (INT-01, boundary
      guards / zero-cut solve / lattice reachability / L-validity), extended by plan 24-02 Task 1
      (cut reuse) and plan 24-03 Task 1 (exhaustive LL/no-good cut algebra)
- [ ] `test/test_planning_trace.jl` -- new file (or extends an existing `BendersTrace` test file
      if one is found -- plan 24-03 Task 2 requires checking first), plan 24-03 Task 2 (INT-02,
      additive `nogood_count_trace` column)
- [ ] `test/test_planning_benders_integer.jl` -- new file, plan 24-04 Task 1 (INT-02, injection
      seam + mutual-exclusivity regression), extended by plan 24-04 Task 2 (end-to-end smoke)
- [ ] `test/test_planning_certification_integer.jl` -- new file, plan 24-05 Task 1 (INT-03,
      enumeration harness), extended by plan 24-05 Task 2 (INT-02/INT-03 certification + D-15
      certificates + negative-control regression)

*Existing infrastructure (`test/runtests.jl`'s `TestItemRunner.@run_package_tests`) covers
discovery for every new item; no changes to `test/runtests.jl` are required. `test/test_planning_noninteger.jl`
is EXTENDED (not newly created) by plan 24-02 Task 2 -- it already exists and is discovered.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.* The literate page (plan 24-06) is built and
checked automatically via `julia --project=docs docs/make.jl` when the docs environment is
available; if it is not runnable in a given execution session, plan 24-06 Task 2 requires that
gap to be stated explicitly rather than silently skipped. There is no behavior in this phase
that requires a human-only manual check (no UI, no external service, no visual review) -- the
integer master's lattice, the LL/no-good cuts, the enumeration certificate, and the no-good
attribution are all LIVE-COMPUTED, automatically-asserted quantities.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (5 new test files, enumerated above)
- [x] No watch-mode flags
- [x] Feedback latency < 20s (per-task quick commands; the full-suite gate is an intentional,
      documented exception run exactly once, at phase close, matching Phases 20/21/22/23/25's
      own established baseline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-23 -- populated from `24-RESEARCH.md`'s "Validation Architecture"
section and the final 24-01..24-06 PLAN.md files during phase planning (revision pass addressing
plan-checker Blocker 1).
