---
phase: 04-convex-branch-flow-correctness-milestone
verified: 2026-07-19T01:05:51Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
requirements_satisfied:
  - PF-03
  - PF-04
  - OPT-02
  - OPT-03
  - DATA-03
  - SEAM-01
notes:
  - "Independent full test run: 563 Pass / 0 Fail / 0 Error (1m46.6s) — matches expected 563."
  - "Computed golden (v9[16]=1.0436, welfare=-4823.16) pinned as primary regression anchor; thesis v9[16]=1.0493 cross-check is non-failing (broken-test + @info gap). Welfare gap to thesis $1819 documented as figure-bound inputs and accepted by the researcher — NOT a gap."
  - "No concrete solver named in models/powerflow; TestItemRunner absent from main Project.toml (Aqua stale-dep clean)."
---

# Phase 4: Convex Branch-Flow Correctness Milestone — Verification Report

**Phase Goal:** SOCP Convex Branch Flow + LinDistFlow exactness copy, all devices + social welfare, proven EXACT on the modified IEEE-13 feeder as centralized ground truth, with `operational_oracle(z)→(cost,π)` + SEAM-01 extension stubs.
**Verified:** 2026-07-19T01:05:51Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SOCP branch flow + LinDistFlow exactness copy (aux v̂ + affine bounds) solves full GLB-CVX on modified IEEE-13 via Clarabel | ✓ VERIFIED | `ConvexBranchFlow.jl`: rotated cone with the mandatory 0.5 factor (L147 `[0.5*l, v[from], P, Q] in RotatedSecondOrderCone()`); v̂ copy variable (L119), root-fix of both v and v̂ at 1.0² (L126–127), 3.45 squared bounds on both v and v̂ (L135–138), 3.43 copy-drop written in P,Q,l (L164–173), true drop with `+(r²+x²)·l` (L152–158). `problem_class(::ConvexBranchFlow)=SOCP()` (L217) routes to Clarabel via factory. Ground-truth `@testitem` solves the full 24h GLB-CVX on `ieee13_modified()` and PASSES. |
| 2 | Automated invariant asserts exactness (max\|l·v−(P²+Q²)\|<τ per branch); prices REFUSED (throw) if it fails; high-PV over-voltage fixture solves & stays exact | ✓ VERIFIED | `exactness.jl` `assert_socp_exact!` computes per-branch gap and `error(...)`s on `maxgap ≥ τ` (L64). Hooked in `welfare_solve.jl` AFTER `assert_solved!` (L222) and BEFORE the `dual()` read (L260), guarded on `:l` presence (L236). `test_exactness.jl` L40 `@test_throws Exception` proves refusal on a grossly inexact point. High-PV item (L77–127) SOLVES with `allow_export=true`, asserts genuine over-voltage (`v>1.0`) AND reverse flow (`P<0`) — not a weakened/trivial case — and that prices are not refused (`maxgap<1e-5`). |
| 3 | Centralized solve reproduces thesis voltage ground truth; computed golden pinned as primary anchor; thesis cross-check non-failing; nodal DADP available | ✓ VERIFIED | `test_ieee13.jl` pins `GOLDEN_V9_16=1.0436080536` (=√v[10,16]), `GOLDEN_WELFARE=-4823.16`, `GOLDEN_DADP16`, `GOLDEN_SUM_DADP` as HARD ~1e-4 regression anchors (L195–198). Thesis `v₉[16]=1.0493` is a NON-FAILING `broken`-test + `@info` gap emit (L204–211). Welfare gap to thesis $1819 documented as figure-bound (A2/A3) and accepted — not asserted. DADP + frontier π returned and finite (L133–138). |
| 4 | `operational_oracle(z)→(cost,π)` returns frontier coupling dual + SEAM-01 stubs exist | ✓ VERIFIED | `oracle.jl` `operational_oracle(...) -> (; cost, π, dadp, ctx)`; `π=_coupling_dual(ctx,z)` = dual of root `:balance_p` (L173). SEAM-01 stubs all present & inert: `z↔p_ag` coupling flow + documented pin extension point (L157–174), `role::Symbol` leader/follower validated (L101), `objective_hook` multi-scenario hook (L112), `horizon_state` rolling-horizon param (L115), meshed slot = the `pf::AbstractPowerFlow` argument (docstring L77–80). `test_oracle.jl` exercises every stub kwarg and rejects an unknown role via `@test_throws ArgumentError`. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/powerflow/ConvexBranchFlow.jl` | SOCP formulation + exactness copy + SOCP() trait | ✓ VERIFIED | 219 lines; rotated cone (0.5), v̂ copy, root-fix, 3.43/3.45, loss terms, `problem_class=SOCP()`; wired in `TSODSO.jl` L43. |
| `src/models/exactness.jl` | `assert_socp_exact!` price-refusal gate | ✓ VERIFIED | Computes gap, throws on inexact; wired in `TSODSO.jl` L70 and called by `welfare_solve.jl` L237. |
| `src/models/oracle.jl` | `operational_oracle` + SEAM-01 stubs | ✓ VERIFIED | Returns (cost,π,dadp,ctx); all 4 stub families present; wired `TSODSO.jl` L73. |
| `src/models/welfare_solve.jl` | GLB-CVX solve with exactness hook + allow_export | ✓ VERIFIED | Gate placed after `assert_solved!`, before dual read; `allow_export` free-sign frontier is the documented SOC-exactness enabler. |
| `src/data/ieee13.jl` | Modified IEEE-13 built-in fixture (Table 4.1) | ✓ VERIFIED | 11 buses / 10 branches, head-limit 0.0686 pu, 99.0 interior sentinel; `assert_radial`+`assert_magnitudes` at construction. |
| `src/solver/ProblemClass.jl` + `problem_class_trait.jl` | Problem-class taxonomy + QP generic trait | ✓ VERIFIED | SOCP singleton exists; generic `problem_class(::AbstractPowerFlow)=QP()`; ConvexBranchFlow overrides to SOCP() by dispatch (no `if formulation ==`). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `welfare_solve` | `assert_socp_exact!` | `if haskey(pf_vars,:l)` after `assert_solved!`, before `dual()` | ✓ WIRED | L236–238; DC/LinDistFlow (no `:l`) skip untouched. |
| `operational_oracle` | `solve_welfare` | single solve, reuses `:balance_p` dual | ✓ WIRED | L122–132; π from registered root balance constraint. |
| `ConvexBranchFlow` | Clarabel factory | `problem_class(pf)=SOCP()` → `select_optimizer(SOCP())` | ✓ WIRED | No model names a solver; only `factory.jl` maps SOCP→Clarabel with 1e-8 gap. |
| SOCP formulation | three-way conformance | same `solve_welfare` call, only `pf` differs | ✓ WIRED | `test_conformance.jl` L50–90 loops DC/LinDistFlow/SOCP, all finite. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | 563 Pass / 0 Fail / 0 Error (1m46.6s) | ✓ PASS |
| No solver named in models | `grep -E "(Clarabel\|HiGHS\|Ipopt)\.(Optimizer\|MOI)" src/models src/powerflow` | NONE (only in `factory.jl`) | ✓ PASS |
| Aqua stale-dep (TestItemRunner) | `grep -c TestItemRunner Project.toml` | 0 (only in `test/Project.toml`) | ✓ PASS |
| Exactness gate refuses inexact | `@test_throws` in `test_exactness.jl` (in suite) | passes | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PF-03 | 04-02 | SOCP Convex Branch Flow + LinDistFlow exactness copy | ✓ SATISFIED | `ConvexBranchFlow.jl` + socp/conformance testitems |
| PF-04 | 04-05 | Post-solve exactness invariant, prices refused on failure | ✓ SATISFIED | `exactness.jl` + gate in `welfare_solve` + exact testitems (throw + high-PV) |
| OPT-02 | 04-06 | Centralized monolithic global optimum, nodal-balance dual available | ✓ SATISFIED | ground GLB-CVX SOCP solve OPTIMAL+exact; DADP/π returned |
| OPT-03 | 04-04/04-06 | `operational_oracle(z)→(cost,π)` frontier coupling dual | ✓ SATISFIED | `oracle.jl` + oracle/ground testitems |
| DATA-03 | 04-03 | Modified IEEE-13 built-in fixture | ✓ SATISFIED | `ieee13.jl` + ieee13 testitems (topology/magnitudes vs Table 4.1) |
| SEAM-01 | 04-04 | Extension stubs (multi-scenario, rolling-horizon, meshed, z↔p_ag/λ_j↔π_s, leader/follower) | ✓ SATISFIED | `oracle.jl` typed inert stubs + role guard + oracle testitems |

No orphaned requirements: every ID REQUIREMENTS.md maps to Phase 4 is claimed by a plan and verified.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | No TBD/FIXME/XXX/HACK/PLACEHOLDER/return-null stubs in any Phase-4 source | ℹ️ Info | Clean. SEAM-01 `@debug`-flagged inert stubs are intentional, documented, and tested — not code smells. |

### Human Verification Required

None. The one manual-only item flagged in `04-VALIDATION.md` (exact thesis-number match `v₉[16]≈1.0493` / welfare `≈$1819`) has already been resolved: it is automated as a NON-FAILING cross-check, and the researcher has accepted the pinned computed golden as the primary anchor with the welfare gap documented as figure-bound inputs. No open decision remains.

### Gaps Summary

No gaps. All four ROADMAP success criteria are observably true in the code and exercised by the passing 563-test suite. The SOCP formulation carries the mandatory 0.5 rotated-cone factor and the full exactness copy (v̂ root-fix + 3.45 bounds + 3.43 copy-drop). The PF-04 gate is correctly sequenced (after `assert_solved!`, before `dual()`) and provably refuses prices on an inexact point while the genuine high-PV over-voltage/reverse-flow fixture solves and stays exact — with `allow_export=true` as a real, documented, physically-motivated SOC-exactness enabler (not a weakened test). Ground truth is anchored on a pinned computed golden with a non-failing thesis cross-check; the welfare gap is an accepted, documented deviation, not a failure. `operational_oracle` returns the frontier coupling dual and all SEAM-01 extension interfaces exist as typed, inert, tested stubs. No concrete solver is named in any model, ConvexBranchFlow is a pure-dispatch drop-in across the three-way DC/LinDistFlow/SOCP conformance, and TestItemRunner is absent from the main `Project.toml`.

---

_Verified: 2026-07-19T01:05:51Z_
_Verifier: Claude (gsd-verifier)_
