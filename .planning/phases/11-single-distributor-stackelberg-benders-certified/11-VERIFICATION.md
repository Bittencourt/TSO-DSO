---
phase: 11-single-distributor-stackelberg-benders-certified
verified: 2026-07-22T23:37:41Z
status: passed
score: 5/5 roadmap success criteria verified (plus all plan-level must_haves)
overrides_applied: 0
deviations_assessed:
  - deviation: "11-01-PLAN.md's stated hand-enumerated optimum (y*=1.0, z*=1.0, cost=-0.2) had an arithmetic error; corrected analytically to y*=z*=0.7, cost=-0.245 (derivation documented in test/test_planning_benders.jl and test/test_planning_certification.jl headers); all downstream consumers (11-02, 11-03) updated consistently."
    assessment: "Satisfies intent. Re-derivation is independently verifiable (first-order condition on total(z)=0.5z^2-0.7z), consistently applied across all three plans, and empirically confirmed by three independent solve paths (Benders, StrongDualityMode, ProductMode) converging to the corrected value."
  - deviation: "Success criterion 4 names BigMMode as one of two certification reformulations. BigMMode+HiGHS cannot solve the resulting MIQP (measured: HiGHS prints 'Cannot solve MIQP problems with HiGHS', termination_status == MOI.OTHER_ERROR, at any Big-M bound — a categorical solver-capability gap, not a bound-tuning issue, since the Upper-level welfare term is genuinely quadratic and BigMMode's Fortuny-Amat reformulation introduces binary complementarity indicators). BilevelJuMP.ProductMode (already shipped in the same package, no new dependency) was substituted as the second, structurally-independent reformulation; BigMMode+HiGHS is retained as a permanently-asserted negative regression."
    assessment: "Satisfies intent. The literal criterion text names BigMMode, but its substantive purpose — two independent MPEC reformulations cross-checked against a hand enumeration to empirically resolve the sign/role convention — is met by StrongDualityMode + ProductMode, which are structurally independent (strong-duality equality vs. epsilon-relaxed bilinear-product complementarity) and both converge to the same certified answer. The BigMMode incapacity is not hidden — it is reproduced and asserted as a permanent documented negative regression, satisfying the spirit of 'not left as a code comment.' Independently reproduced during this verification (see Behavioral Spot-Checks)."
  - deviation: "Post-execution code review applied 7 fix commits (2ab7907..59c3cbc: CR-01 incumbent tracking, WR-01 through WR-05) plus a formatter pass; final review status clean."
    assessment: "Confirmed via git log. The current working tree reflects the post-fix state — the incumbent-tracking (CR-01), follower-feasibility-before-oracle ordering (WR-01), and finiteness guards (WR-03) are all present in the code read during this verification. No further action needed."
---

# Phase 11: Single-Distributor Stackelberg-Benders (Certified) Verification Report

**Phase Goal:** A single distributor's Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower) solves end-to-end via a hand-rolled Benders loop, with the
source-flagged leader/follower role assignment and coupling-dual sign convention resolved
empirically and certified by a tiny BilevelJuMP MPEC cross-check — not left as a code comment.

**Verified:** 2026-07-22T23:37:41Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A transmission-reinforcement follower LP `α(z)` returns the coupling dual `π_s` for feasible `z` and an infeasibility/Farkas certificate for infeasible `z`. | VERIFIED | `src/planning/follower.jl` `solve_follower!` (lines 164-217): feasible branch returns `(; feasible=true, cost, π_s=dual.(f.coupling))`; infeasible branch checks `dual_status == MOI.INFEASIBILITY_CERTIFICATE` and returns `(; feasible=false, v, u)`, enforcing `isfinite` on both. `test/test_planning_follower.jl`'s two Farkas regressions (`z=[-1.0]`, `z=[10.0]`) pass; ran independently this session (140/140 planning tests green, includes these). |
| 2 | The Benders master accumulates both optimality and feasibility cuts as persistent constraint rows (no per-iteration rebuild), with every cut-producing solve gated by the strict `assert_solved!(...; allow_almost=false)` check. | VERIFIED | `src/planning/master.jl` `add_optimality_cut!`/`add_feasibility_cut!` append `@constraint` rows to the existing `master.model` (never `Model(...)` again); `solve_master!` routes through `solve_with_retry!` (`src/planning/retry.jl:142`, `return assert_solved!(model; dual = dual)` — no `allow_almost` argument, defaults `false`). `test/test_planning_master.jl`'s cut-row-growth test asserts `num_variables` invariant / `num_constraints` +1 per cut across all 3 cut kinds — passes. |
| 3 | A single-distributor Stackelberg equilibrium converges end-to-end with a reported upper/lower-bound gap below a documented tolerance. | VERIFIED | `src/planning/benders.jl` `solve_stackelberg!` builds oracle/follower/master exactly once, loops `solve_master!`→`solve_planning_oracle!`/`solve_follower!`→cut→checkpoint→gap check, returns on `gap <= tol` (default `1e-6`) or raises loudly on exhaustion. `test/test_planning_benders.jl`'s convergence test passes: `result.gap <= 1e-6`, `result.y`/`result.z[1] ≈ 0.7` (re-derived analytic optimum). Independently re-run this session — green. |
| 4 | A tiny BilevelJuMP (`BigMMode`/`StrongDualityMode`) certification case, cross-checked against a hand-worked toy enumeration, empirically resolves the leader/follower role assignment and coupling-dual sign convention, encoded as a tested invariant. | VERIFIED (documented substitution) | `test/test_planning_certification.jl`: `StrongDualityMode`(Ipopt) + `ProductMode`(Ipopt, substituting for `BigMMode`+HiGHS's role — see deviation note) independently converge to `y*=z*=0.7`, `total=-0.245`, agree with each other (`rtol=1e-4`) and the hand enumeration (`atol=1e-3`); `BigMMode`+HiGHS is exercised and asserted to fail with `MOI.OTHER_ERROR` (permanent negative regression, reproduced this session). No sign flip was required in `follower.jl`/`benders.jl` — all paths agree. |
| 5 | The BilevelJuMP certification case is retained in the test suite as a permanent, fast regression (not a one-off validation run). | VERIFIED | `test/test_planning_certification.jl` contains 2 permanent `@testitem`s tagged `[:planning]`, part of the default `@run_package_tests` full-suite run (confirmed: appears in both the 140-item planning-tagged run and the 4043-item full-suite run executed this session). |

**Score:** 5/5 roadmap success criteria verified.

### Additional Plan-Level Must-Haves (from PLAN frontmatter, all folded into the truths above)

| Must-have | Status | Evidence |
|---|---|---|
| Master's first (zero-cut) solve returns `OPTIMAL`, never `DUAL_INFEASIBLE` | VERIFIED | `α_op_lb`/`α_x_lb` declared at `@variable` build time (`master.jl` lines 104-105); `test_planning_master.jl`'s epigraph-lower-bound regression passes |
| Feasibility cut never updates `UB` | VERIFIED | `benders.jl` lines 157-165: `continue` immediately after the feasibility-cut branch's `checkpoint_iteration!` call, before reaching the `UB = min(...)` line; `test_planning_benders.jl`'s feasibility-cut-branch test independently exercises this and passes |
| `checkpoint_iteration!` fires exactly once per iteration on both branches | VERIFIED | Both branches in `benders.jl`'s loop call `checkpoint_iteration!` exactly once; checkpoint-file-count regression (`length(checkpoint_files) == result.iters`) passes in both convergence tests |
| No planning-layer subproblem introduces a binary/integer variable | VERIFIED | `grep -in 'Bin\b\|::Integer' src/planning/{follower,master,benders}.jl` → no matches |
| `BilevelJuMP` is test-only, never imported by `src/` | VERIFIED | `grep -rn 'using BilevelJuMP\|import BilevelJuMP' src/` → no matches; `test/Project.toml` carries `BilevelJuMP = "= 0.6.3"` in `[compat]` |
| Every cut-producing solve routes through the correct gate (strict `assert_solved!` for oracle/master, direct un-retried read for the follower's infeasible branch) | VERIFIED | `grep -n 'solve_with_retry!' src/planning/follower.jl` → no match (confirmed); `grep -c 'solve_with_retry!(master.model' src/planning/master.jl` → 1 |

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/planning/follower.jl` | `FollowerLP`/`build_follower`/`solve_follower!`, genuine Farkas certificates | VERIFIED | 219 lines; exports all three; `INFEASIBILITY_CERTIFICATE` appears 7×; no `solve_with_retry!`; routes via `select_optimizer(LP())` |
| `src/planning/master.jl` | `BendersMaster`/`build_master`/`add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!` | VERIFIED | 270 lines; exports all five; persistent-row cut appends confirmed; epigraph lower bounds declared at build time |
| `src/planning/benders.jl` | `solve_stackelberg!` outer Benders loop | VERIFIED | 216 lines; builds subproblems exactly once outside the loop (confirmed by inspection: `build_planning_oracle`/`build_follower`/`build_master` all appear before the `for k in 1:max_iter` loop, none inside it); no `@variable`/`Model(` call in this file |
| `test/test_planning_follower.jl` | guards, build-once invariance, feasible/Farkas branches, dual-sign regression | VERIFIED | 155 lines, 6 `@testitem`s; all pass (part of the 140/140 planning run) |
| `test/test_planning_master.jl` | guards, epigraph regression, cut-row growth, cut-validity check | VERIFIED | 140 lines, 7 `@testitem`s; all pass |
| `test/test_planning_benders.jl` | end-to-end convergence, feasibility-cut branch, iteration-cap regression | VERIFIED | 175 lines, 3 `@testitem`s; all pass, including a feasibility-cut-branch test beyond the plan's literal minimum |
| `test/test_planning_certification.jl` | BigMMode/StrongDualityMode/ProductMode vs hand enumeration, Benders cross-check | VERIFIED | 227 lines, 2 `@testitem`s (20 assertions); all pass, including reproduction of the documented BigMMode MIQP-incapacity negative regression |
| `test/Project.toml` | `BilevelJuMP` in `[deps]` + `[compat]` pin | VERIFIED | `BilevelJuMP = "= 0.6.3"`, `HiGHS = "= 1.24.1"`, `Ipopt = "= 1.15.0"` — exact pins, not floating ranges |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `follower.jl` | MOI infeasibility-certificate machinery | `dual_status(model) == MOI.INFEASIBILITY_CERTIFICATE` | WIRED | Confirmed at `follower.jl:179`, never a hand-rolled heuristic |
| `follower.jl` | `src/solver/factory.jl` | `Model(select_optimizer(LP()))` | WIRED | `follower.jl:110` |
| `master.jl` | `src/planning/retry.jl` | `solve_with_retry!(master.model; ...)` | WIRED | `master.jl:261` |
| `master.jl` | `src/solver/factory.jl` | `Model(select_optimizer(LP()))` | WIRED | `master.jl:98` |
| `benders.jl` | `src/planning/subproblem.jl` | `solve_planning_oracle!(oracle, lb_res.z)` | WIRED | `benders.jl:168`, called once per feasible iteration, oracle built once at `benders.jl:131` |
| `benders.jl` | `src/planning/follower.jl` | `solve_follower!(follower, lb_res.z)` direct call | WIRED | `benders.jl:155`, never wrapped in `solve_with_retry!` (confirmed: `grep -c 'solve_with_retry!' src/planning/benders.jl` == 0) |
| `benders.jl` | `src/planning/master.jl` | `add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!` | WIRED | `benders.jl:144,158,172,174` |
| `benders.jl` | `src/planning/checkpoint.jl` | `checkpoint_iteration!` once per iteration | WIRED | `benders.jl:159,186`, both loop branches |
| `test_planning_certification.jl` | `BilevelJuMP.jl` | `BilevelModel(..., mode=BigMMode/StrongDualityMode/ProductMode)` | WIRED | Confirmed via independent re-run this session (Ipopt/HiGHS solve traces observed, including the "Cannot solve MIQP" HiGHS message) |
| `test_planning_certification.jl` | `src/planning/benders.jl` | `solve_stackelberg!` on the identical toy instance | WIRED | Cross-check assertions pass (`result.y`/`result.z[1]`/`result.UB` vs. both BilevelJuMP reformulations and the hand enumeration) |

### Behavioral Spot-Checks (actually executed this session, not trusted from SUMMARY.md)

| Behavior | Command | Result | Status |
|---|---|---|---|
| Planning-tagged test suite (140 items: follower + master + benders + certification, all Phase 11 work plus Phase 10's retry/checkpoint/subproblem items) | `julia --project=<merged env> -e 'using TestItemRunner; @run_package_tests filter=ti->(:planning in ti.tags)'` | `Package | 140 140 1m37.1s` | PASS |
| Certification-only subset (BigMMode/StrongDualityMode/ProductMode + Benders cross-check) re-run in isolation | `@run_package_tests filter=ti->occursin("certification", ti.name)` | `Package | 20 20 2m25.9s`; log shows `ERROR: Cannot solve MIQP problems with HiGHS` fired twice (once per BigMMode build in the test + the assertion), confirming the documented negative regression is genuinely reproduced, not merely claimed | PASS |
| Full project test suite (all phases, Phase 1-11) | `julia --project=<merged env> -e 'using TestItemRunner; @run_package_tests'` | `Package | 4039 pass, 4 broken, 4043 total, 7m53.1s`, 0 failures | PASS — the 4 broken items are pre-existing, explicitly annotated (`note = "gap is expected & documented (Open Q1: inputs figure-bound)"`), unrelated to Phase 11 |
| Debt-marker scan on all 7 Phase-11 files | `grep -n -E "TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER" -i <files>` | No matches in any file | PASS |
| No binary/integer variables in planning-layer subproblems | `grep -in 'Bin\b\|::Integer' src/planning/{follower,master,benders}.jl` | No matches | PASS |
| No `src/` import of BilevelJuMP | `grep -rn 'using BilevelJuMP\|import BilevelJuMP' src/` | No matches | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| PLAN-04 | 11-01 | Follower LP exposes coupling dual + Farkas certificate | SATISFIED | `follower.jl` + `test_planning_follower.jl`, all green |
| PLAN-05 | 11-01 | Benders master with persistent optimality/feasibility cuts, strict `assert_solved!` gate | SATISFIED | `master.jl` + `test_planning_master.jl`, all green |
| PLAN-06 | 11-02 | Single-distributor Stackelberg equilibrium end-to-end | SATISFIED | `benders.jl` + `test_planning_benders.jl`, all green |
| PLAN-07 | 11-03 | Leader/follower role + sign convention resolved empirically, tested invariant | SATISFIED | `test_planning_certification.jl`'s permanent Benders-vs-BilevelJuMP invariant, green |
| PVAL-01 | 11-03 | BilevelJuMP certification retained as permanent fast regression | SATISFIED | Same file, `[:planning]`-tagged, part of default full-suite run |

**Note (tracking-document staleness, not a code gap):** `.planning/REQUIREMENTS.md`'s checkbox list and traceability table still show `PLAN-04`/`PLAN-05` as `[ ]`/"Pending" (last touched by commit `30144c6`, before any of Phase 11's three plan-commits). `.planning/STATE.md` similarly still reads "Phase 11 execution started" / "Plan 1 of 3" / 0% progress. Both are stale bookkeeping artifacts — `.planning/ROADMAP.md` (the authoritative per-phase contract) correctly marks Phase 11 `[x]` complete, and the actual code/tests substantiate every requirement. Recommend a housekeeping pass to sync `REQUIREMENTS.md`/`STATE.md` before starting Phase 12, but this does not block Phase 11's goal achievement since it is a tracking-document lag, not a missing implementation.

### Anti-Patterns Found

None. Scanned all 7 phase-11 files (`src/planning/{follower,master,benders}.jl`, `test/test_planning_{follower,master,benders,certification}.jl`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`/`placeholder`/`coming soon`/`not yet implemented` — zero matches. No empty implementations (`return null`/`return {}`/`=> {}`), no hardcoded-empty stub patterns. All `@testitem`s exercise real solves against a real solver (HiGHS/Ipopt/Clarabel), not mocked.

### Human Verification Required

None. This phase delivers pure numerical/algorithmic library code (JuMP models, a Benders loop, a test-only MPEC certification) with no UI, no external service integration, and no user-facing flow — every success criterion is mechanically checkable via code inspection and test execution, which was done directly in this session (not merely trusted from SUMMARY.md).

### Gaps Summary

No gaps. All 5 ROADMAP success criteria are independently verified against the actual codebase (not SUMMARY.md claims): code was read directly, greps were run to confirm structural invariants (no rebuild, no retry-wrapper leakage, no binary variables, no BilevelJuMP scope creep), and the full test suite (4043 items) plus the planning-tagged subset (140 items) and the certification subset (20 items, including a live reproduction of the documented BigMMode/HiGHS MIQP incapacity) were all executed fresh in this verification session and passed with zero failures.

Two items are noted as non-blocking:
1. `.planning/REQUIREMENTS.md` and `.planning/STATE.md` tracking documents are stale relative to the actual (complete, verified) state of Phase 11 — a housekeeping gap, not a code gap.
2. Success criterion 4's literal `BigMMode` naming is satisfied via a documented, well-justified substitution (`ProductMode`) for BigMMode's role as the second independent reformulation, with `BigMMode`+HiGHS retained as a permanent negative regression rather than silently dropped — assessed as satisfying the criterion's substantive intent.

---

*Verified: 2026-07-22T23:37:41Z*
*Verifier: Claude (gsd-verifier)*
