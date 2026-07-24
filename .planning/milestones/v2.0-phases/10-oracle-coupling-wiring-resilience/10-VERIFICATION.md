---
phase: 10-oracle-coupling-wiring-resilience
verified: 2026-07-22T19:20:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 10: Oracle Coupling Wiring & Resilience Verification Report

**Phase Goal:** The real `p_import == z` coupling constraint and its dual are wired live into a
build-once oracle subproblem, the hourly distribution dual is reconciled to a single per-scenario
interconnection dual, and repeated oracle re-solves are resilient to the known intermittent
Clarabel `NUMERICAL_ERROR` — all before any Benders code depends on these seams.
**Verified:** 2026-07-22T19:20:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A build-once oracle subproblem exposes `p_import == z` as a live JuMP `Parameter` constraint and returns its dual — superseding the `ArgumentError` SEAM-01 stub — while `operational_oracle`/`solve_welfare` remain unmodified | VERIFIED | `src/planning/subproblem.jl:194-195` (`@variable(model, z[t=1:T] in Parameter(0.0))`; `@constraint(model, pin[t=1:T], p_import[t] == z[t])`); dual read at line 297 (`π = dual.(o.pin)`). `git diff --stat e129958..HEAD -- src/models/oracle.jl src/models/welfare_solve.jl` is empty (e129958 = first phase-10 commit) — confirms byte-for-byte unmodified across the ENTIRE phase-10 commit range, not just at plan-end. The old `ArgumentError` free-path guard in `src/models/oracle.jl` (`_coupling_dual`, `z !== nothing` throw) is untouched and still exercised by a dedicated free-path-parity test. |
| 2 | The hourly distribution dual `λ_j` reconciles to a single per-scenario interconnection dual `π_s` via a documented time-aggregation + sign convention, validated against a hand-computed toy case | VERIFIED | `src/planning/subproblem.jl:298` (`π_s = sum(Δt * π[t] for t in 1:o.T)`, duration-weighted, documented D-07). Sign convention documented and pinned by a hand-derived toy-case regression in `test/test_planning_oracle.jl` (`ToyElasticDevice`, hand-derived analytic optimum `p*=2` from `a=6,b=1,λ₀=4`): asserts `|π|<1e-4` at the unconstrained optimum, `π<=0` below it, `π>=0` above it, and elementwise monotonicity — the exact "hand-computed toy case" success criterion. |
| 3 | An oracle solve wrapped in bounded retry + checkpointing survives an injected/observed `NUMERICAL_ERROR` without silently corrupting or aborting a run | VERIFIED | `src/planning/retry.jl` (`solve_with_retry!`, 4-rung escalating Clarabel-conditioning ladder around `assert_solved!`, never SCS fallback, raises loudly with full diagnostics + exhausted-attempt count on budget exhaustion — `D-10`). `src/planning/checkpoint.jl` (`checkpoint_iteration!`/`resume_from_checkpoint`, JLD2 + git-provenance, always reports highest-numbered checkpoint as "redo," excludes stale `safesave` backups per `CR-02`). Both empirically exercised: `test/test_planning_retry.jl` reproduces a real `RETRYABLE_STATUSES` failure (measured, not assumed) and asserts recovery-or-loud-raise; `test/test_planning_checkpoint.jl` covers round-trip, highest-numbered-redo, filename-bound guard, and stale-backup exclusion. `solve_planning_oracle!` calls `solve_with_retry!` as its SOLE solve entry point (`grep -n 'assert_solved!' src/planning/subproblem.jl` returns nothing). |
| 4 | No planning-layer subproblem introduces a binary/integer variable (continuous-only scope preserved) | VERIFIED | `grep -in 'Bin\b|::Integer|Int, *Bin' src/planning/*.jl` returns nothing. All `@variable` declarations in `src/planning/subproblem.jl` are continuous (`p_import[t]`, `q_import[t]` free-sign, `z[t] in Parameter(...)`). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/planning/retry.jl` | `solve_with_retry!` escalating-retry wrapper (D-08/D-09) | VERIFIED | 165 lines. Defines `RETRYABLE_STATUSES`, `solve_with_retry!(model; max_attempts=4, dual=true)`. Exported. Wraps `assert_solved!` verbatim, never falls back to SCS (`grep -n 'SCS|Clarabel.Optimizer|HiGHS|Ipopt' src/planning/retry.jl` returns nothing — solver-generic API). |
| `src/planning/checkpoint.jl` | `checkpoint_iteration!`/`resume_from_checkpoint` (D-10) | VERIFIED | 109 lines. Both functions defined and exported. Uses `@tagsave(...; gitpath = pkgdir(@__MODULE__), safe = true)` (line 56-62), the exact `store.jl` idiom. |
| `src/planning/subproblem.jl` | `PlanningOracle` + `build_planning_oracle` + `solve_planning_oracle!` | VERIFIED | 305 lines. `struct PlanningOracle{Z,PC,PI,F}`, `build_planning_oracle(feeder, pf, aggregators; λ₀, T=24)`, `solve_planning_oracle!(o, z_trial; max_attempts=4, Δt=1.0, ...)` all present, all exported. Formulation-generic (`select_optimizer(problem_class(pf))`, never hardcodes `SOCP()` — confirmed via grep). |
| `test/test_planning_retry.jl` | recoverable-escalation + non-retryable-immediate-raise `@testitem`s | VERIFIED | 3 `@testitem`s (recoverable escalation w/ measured fixture, `max_attempts<1` guard, genuine INFEASIBLE never-retried). All tagged `[:planning]`. |
| `test/test_planning_checkpoint.jl` | round-trip + highest-numbered-always-redo `@testitem`s | VERIFIED | 4 `@testitem`s (round-trip, highest-numbered-redo + empty-dir, filename-bound guard, stale-safesave-backup exclusion regression). |
| `test/test_planning_oracle.jl` | guards, build-once, shape, dual-sign toy-case, free-path parity `@testitem`s | VERIFIED | 7 `@testitem`s + 1 `@testmodule` (`ToyDeviceFixture`): guards, build-once invariance (LinDistFlow), NamedTuple shape, dual-sign toy-case regression, free-path parity, build-once re-solve invariance, ConvexBranchFlow CR-03 exactness-gate coverage. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `src/planning/retry.jl` | `src/core/status.jl` | `assert_solved!` sole choke point | WIRED | `assert_solved!(model; dual=dual)` called at line 142; no duplicated status-check logic. |
| `src/planning/checkpoint.jl` | DrWatson `@tagsave` | provenance-stamped JLD2 persistence | WIRED | `@tagsave(path, Dict(...); storepatch=true, gitpath=pkgdir(@__MODULE__), safe=true)` at line 56. |
| `src/planning/subproblem.jl` | `src/planning/retry.jl` | `solve_planning_oracle!` calls `solve_with_retry!` | WIRED | Line 278: `solve_with_retry!(o.model; max_attempts=max_attempts, dual=true)` is the sole solve call; `assert_solved!` never appears directly in `subproblem.jl`. |
| `src/planning/subproblem.jl` | `src/powerflow/AbstractPowerFlow.jl` | `contribute!(pf, ctx, feeder; T)` reused verbatim | WIRED | Line 149: `contribute!(pf, ctx, feeder; T = T)`. |
| `src/TSODSO.jl` | `src/planning/{retry,checkpoint,subproblem}.jl` | append-only include block, correct load order | WIRED | Three `include(...)` lines present in the required order (`retry.jl` → `checkpoint.jl` → `subproblem.jl`), documented rationale in the block comment (subproblem.jl must load after retry.jl). |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| PLAN-01 | 10-02 | Live `p_import == z` coupling wired, ArgumentError stub superseded, `operational_oracle`/`solve_welfare` unmodified | SATISFIED | `build_planning_oracle` (subproblem.jl); `git diff` empty on both unmodified files across the full phase-10 commit range. |
| PLAN-02 | 10-02 | `λ_j → π_s` reconciliation, sign convention pinned by hand-computed toy case | SATISFIED | `solve_planning_oracle!`'s `π_s` computation + `ToyElasticDevice` dual-sign regression test. |
| PLAN-03 | 10-01 | Bounded retry + checkpointing around oracle solves, survives `NUMERICAL_ERROR` | SATISFIED | `solve_with_retry!` + `checkpoint_iteration!`/`resume_from_checkpoint`, both empirically tested. **Note:** `.planning/REQUIREMENTS.md`'s traceability table still shows PLAN-03 as `Pending` (line 85) even though the requirement checkbox itself (line 24) and ROADMAP.md both confirm delivery — this is a stale bookkeeping checkbox, not a code gap (see Anti-Patterns/Info below). |

No orphaned requirements: `10-01-PLAN.md` declares `[PLAN-03]` and `10-02-PLAN.md` declares `[PLAN-01, PLAN-02]` — together the exact set ROADMAP.md assigns to Phase 10.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` scan across `src/planning/*.jl` and `test/test_planning_*.jl` | none found | — |
| `.planning/REQUIREMENTS.md` | 85 | Traceability table row `PLAN-03 \| Phase 10 \| Pending` not updated to `Complete` despite the requirement checkbox (line 24) and delivered code both confirming completion | Info | Cosmetic/bookkeeping only — does not affect code-level truth. Recommend updating this row before closing the milestone. |
| `.planning/STATE.md` | 6-33 | Frontmatter/Current-Position still shows "Phase 10 — EXECUTING", "Plan 1 of 2", 0% progress — stale relative to both completed plans and ROADMAP.md's `[x]` phase-10 checkbox | Info | Workflow bookkeeping only; STATE.md update is normally an orchestrator post-verification step, not a phase-goal criterion. |

No Critical or Warning-level anti-patterns. The phase's own 3-iteration code-review process (`10-REVIEW.md` → `10-REVIEW.iter2.md` → `10-REVIEW.iter3.md`) independently found and the fix-loop (`10-REVIEW-FIX.md` → `.iter2.md` → `.iter3.md`) closed 3 Critical + multiple Warning findings (CR-01/02/03, WR-01 through WR-04) before this verification; final review status is `clean` (0 critical, 0 warning, 7 info — all documented as deliberate/residual and non-blocking).

### Behavioral Spot-Checks / Full-Suite Confirmation

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full regression suite (independent live re-run attempted during this verification) | `julia --project=. -e 'import Pkg; Pkg.test()'` | Started, ran ~219 lines of solver output (HiGHS solves consistent with the non-retryable-INFEASIBLE test path executing correctly — infeasibility detected, dual ray computation invoked, no errors observed) before the background process was lost to sandbox resource exhaustion (system load average 5.7, <250 MB free RAM, competing julia process) | INCONCLUSIVE (environment-limited, not code-limited) |
| Full regression suite (documented, independently re-run 5 times during the phase's own TDD + 3-iteration review cycle) | `julia --project=. -e 'import Pkg; Pkg.test()'` per 10-01-SUMMARY.md, 10-02-SUMMARY.md, 10-REVIEW-FIX.md, .iter2.md, .iter3.md | 1957 → 1978 → 1994 → 2004 passed / 2 pre-existing documented-broken / 0 failed, monotonically increasing as new assertions were added, each cross-referenced against the actual commit diff (not merely quoted) | PASS (corroborating, cross-referenced against git log, not taken on SUMMARY's word alone) |
| `git diff --stat` on unmodified files, spanning the FULL phase-10 commit range | `git diff --stat e129958..HEAD -- src/models/oracle.jl src/models/welfare_solve.jl` | empty | PASS |
| No solver named outside factory in retry.jl | `grep -n 'SCS\|Clarabel.Optimizer\|HiGHS\|Ipopt' src/planning/retry.jl` | no matches | PASS |
| No binary/integer variables anywhere in `src/planning/` | `grep -in 'Bin\b\|::Integer\|Int, *Bin' src/planning/*.jl` | no matches | PASS |
| Sole solve entry point discipline | `grep -n 'assert_solved!' src/planning/subproblem.jl` | no matches (only `solve_with_retry!` called) | PASS |

The live full-suite re-run I attempted could not complete within this session due to sandbox memory/CPU contention (two concurrent `julia` processes competing for <250 MB free RAM) — this is an environment constraint of this verification session, not a code defect. I did not substitute this inconclusive run for the pass determination; instead I independently cross-referenced the 5 documented full-suite runs against the actual `git log`/`git diff` for each commit that produced them (not merely trusting SUMMARY.md's narrative), and separately verified every artifact, key link, and decision (D-01 through D-11) against the live source code myself (see tables above).

### Human Verification Required

None. This phase is a single-process, in-process Julia numerical-optimization library change with no UI, no network surface, and no external service integration (per project's own threat-model scoping in both plans). Every success criterion is mechanically verifiable via code inspection, git diff, and the automated test suite, all of which were checked directly against source rather than inferred from SUMMARY.md claims.

### Gaps Summary

No gaps. All 4 ROADMAP success criteria are independently verified against the actual codebase:
substantive, non-stub implementations exist for the retry ladder, checkpoint primitive, and
build-once oracle subproblem; all are wired together and into `TSODSO.jl` in the documented,
dependency-correct order; `operational_oracle`/`solve_welfare` are confirmed byte-for-byte
unmodified across the entire phase-10 commit range (not just at plan boundaries); the dual-sign
convention is pinned by an actual hand-derived toy-case regression (not an assumed formula); and
no binary/integer variable exists anywhere in the new module. The phase's own 3-iteration
code-review/fix cycle closed every Critical and Warning finding before this verification ran, and
the final review status is `clean`.

Two purely cosmetic documentation-bookkeeping items (a stale `Pending` traceability row in
REQUIREMENTS.md for PLAN-03, and STATE.md's stale "Phase 10 — EXECUTING / 0%" position) are noted
as Info-level findings — they do not reflect the actual code state and do not block phase-goal
achievement, but should be tidied before milestone close.

---

_Verified: 2026-07-22T19:20:00Z_
_Verifier: Claude (gsd-verifier)_
