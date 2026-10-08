---
phase: 26-network-device-model-correctness
verified: 2026-09-29T00:00:00Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
---

# Phase 26: Network & Device Model Correctness Verification Report

**Phase Goal:** Researcher can trust that the default SOCP branch-flow formulation and the SOC
device models (`PVBattery`, `FourQuadBESS`) reflect the thesis physics, not a silently-introduced
restriction or free hour-T energy.
**Verified:** 2026-09-29
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Documented verdict on thesis eq. 3.43 (relaxation vs. restriction) exists, checked against thesis PDF + Gan-Low 2015, backed by a passing regression on an AC-feasible (Ipopt), heavy-load/low-voltage 3-bus feeder that is also feasible under the default SOCP | ✓ VERIFIED | `docs/literate/convex_branch_flow.jl` "PM-01" verdict subsection cites thesis PDF + Gan-Low(2015), states default is a RESTRICTION (not relaxation). `test/test_exactness_verdict.jl`'s 3-way regression re-run live by this verifier (independent script, not TestItemRunner): AC-feasible=true, default-SOCP feasible with `v̂-v gap = +0.005 ≥ -1e-9`, `thesis_literal=true` variant throws (infeasible). All three legs PASS. |
| 2 | Default `ConvexBranchFlow` exactness copy satisfies v̂ ≥ v (Gan-Low direction) or is clearly relabelled as a restriction; a test checks the docstring's claimed load-bearing bound against the actual constraint | ✓ VERIFIED | `src/powerflow/ConvexBranchFlow.jl` default (`thesis_literal=false`) implements `v̂_j = v̂_i - 2{r(P-rl)+x(Q-xl)}` (Gan-Low direction); module/struct/constructor docstrings explicitly state "restriction... NEVER a genuine relaxation" (PM-01 relabel). `test/test_convex_branch_flow.jl`'s "load-bearing/redundant bound" testitem asserts `v̂ ≤ V²max` binds and `v ≤ V²max` is slack — directly tests the docstring's claim. Live gap re-measurement above (+0.005) confirms v̂ ≥ v empirically. |
| 3 | A PV back-feed fixture shows the reverse (receiving-end) apparent-power limit (thesis 3.37) binding on a limited branch | ✓ VERIFIED | `src/powerflow/ConvexBranchFlow.jl` registers `:smax_rev` (gated by the same `_SMAX_NO_LIMIT` filter as `:smax`); `ACPowerFlow.jl` mirrors it (PM-07). `test/test_convex_branch_flow.jl`'s PV back-feed testitem re-run live by this verifier: `mag_rev=1.38` (binds), `mag_fwd=2.4e-7` (slack), `mag_rev > 100*mag_fwd`. PASS. |
| 4 | `PVBattery`/`FourQuadBESS` link SOC across the whole horizon; "soc0=Emin, discharge at hour T" regression is infeasible or forces zero discharge | ✓ VERIFIED | Both devices' `soc` vectors are `1:(T+1)` long with the recursion closing over `t=1:T` (verified by direct grep + docstring). `mpc_window.jl` retargets the terminal constraint to `soc[H+1]`, removing the old `H==1` double-pin guard. `test/test_pvbattery.jl`'s FIX-04 regression re-run live by this verifier: `p_dch[T] = 1.4e-13` (numerically zero). PASS. |
| 5 | A per-device test shows interruptible/thermostatic/deferrable loads drawing reactive power q = p·tanφ (thesis 3.23) into `:Rq` | ✓ VERIFIED | `src/devices/Aggregator.jl` sums `is_flexible_load` members' `p_inject[t]*tanφ_used` into `:Rq`; `AbstractDevice.jl` defaults `is_flexible_load = false`; `Thermostatic`/`Deferrable`/`Interruptible` override to `true` and each supports an optional per-device φ (falls back to aggregator's φ). Per-device tests exist in `test/test_aggregator.jl` for all three device types (FIX-05 titled testitems), including the Interruptible override/guard case added in review-fix WR-03. |
| 6 | Every golden this phase's fixes move is re-derived in-phase with a stated explanation (test comment + phase SUMMARY), and the full suite is green at phase close — no golden left red, none silently re-pinned | ✓ VERIFIED | `26-GOLDEN-AUDIT.md` documents every moved golden (both original wave 26-02..07 and gap-closure wave 26-09..20) with old→new+cause, cross-referenced against actual test files. Full-suite log `26-postfix-suite.log` (HEAD `9d00b82`, after code-review fix iterations 1-2): **30213 pass / 0 fail / 0 error / 5 broken / 30218 total**, exit 0 — all 5 Broken items named/attributed (2 CairoMakie weakdep skips, 1 pre-existing v2.1 welfare-ratio figure-bound cross-check, 2 honest thesis v₉[16] cross-checks whose growing gap is the FIX-04-driven physics move, predicted and documented). Two subsequent commits: `c7aa143` (test-only, +2 assertions — re-verified live by this verifier, both pass against current HEAD) and `d26b2d1` (docs-only: review-fix report + suite log commit). No code changed after the postfix-suite run. |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/powerflow/ConvexBranchFlow.jl` | `thesis_literal` kwarg, corrected default cpydrop sign, `:smax_rev` cone | ✓ VERIFIED | Confirmed by direct read + live re-run of both FIX-01 and FIX-03 regressions |
| `src/powerflow/ACPowerFlow.jl` | `:smax_rev` receiving-end limit (PM-07) | ✓ VERIFIED | `register_constraint!(ctx, :smax_rev, smax_rev)` present, same filter as `:smax` |
| `src/powerflow/RestrictedBranchFlow.jl` | Inherits `:smax_rev` via delegation, docstring no longer claims opposite-sign default | ✓ VERIFIED | 26-02-SUMMARY confirms header rewrite; delegation model confirmed structurally (MeshedFlow/RestrictedBranchFlow delegate to ConvexBranchFlow.contribute!) |
| `docs/literate/convex_branch_flow.jl` | FIX-01 verdict narrative citing thesis PDF + Gan-Low 2015, PM-01 honest relabel | ✓ VERIFIED | "PM-01" subsection present with EXACT-04 measured numbers (-921.754 default vs -921.277 true AC), explicit "NOT a genuine relaxation" language |
| `src/devices/PVBattery.jl` | `soc[1:(T+1)]`, optional `soc_terminal` kwarg | ✓ VERIFIED | Live-run regression confirms zero hour-T discharge |
| `src/devices/FourQuadBESS.jl` | `soc[1:(T+1)]`, optional `soc_terminal` kwarg | ✓ VERIFIED | Confirmed by direct grep of recursion + bounds |
| `src/models/mpc_window.jl` | Terminal target `soc[H+1]`, `H==1` guard removed | ✓ VERIFIED | Confirmed by direct read |
| `src/devices/Aggregator.jl` | `is_flexible_load` trait dispatch summing flexible-load reactive draw into `:Rq` | ✓ VERIFIED | Confirmed by direct read |
| `src/devices/Thermostatic.jl`, `Deferrable.jl`, `Interruptible.jl` | `is_flexible_load = true`, optional φ override, Variant-2 aggregatable contract (Interruptible) | ✓ VERIFIED | Confirmed by direct read; Interruptible writes nothing to `ctx.residuals`, calls no `add_to_objective!` |
| `src/admm/DsoOpt.jl` | Live reactive-consensus default whenever a flexible-load member or FourQuadBESS is present (PM-03) | ✓ VERIFIED | `_any_flexible_reactive` helper confirmed; WR-04 guard covers both device classes |
| `.planning/phases/26-.../26-GOLDEN-AUDIT.md` | Table of every golden moved, old→new+cause | ✓ VERIFIED | Complete, cross-references both waves, verified against actual test files by the audit's own methodology and spot-checked here |
| `.planning/phases/26-.../26-BASELINE.md` | Pre-fix HEAD-attributed suite counts | ✓ VERIFIED | HEAD `5939799`, 30154 pass/0 fail/0 error/3 broken/30157 total, isolation certified |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `RestrictedBranchFlow.jl`/`MeshedFlow.jl` | `ConvexBranchFlow.contribute!` | delegation | WIRED | `:smax_rev` inherited automatically per plan 26-05's design; no separate code needed |
| `src/pricing/dlmp.jl` (`decompose_dlmp`) | `ConvexBranchFlow.jl` (`:cpydrop`, `:smax_rev` duals) | `dual(...)` reads | WIRED | Plan 26-06 empirically re-certified `volt_b` unchanged; Plan 26-10 added `:smax_rev` dual read for congestion component (residual 6.23 → 3.55e-15) |
| `src/models/mpc_window.jl` | device `soc[H+1]` | terminal constraint | WIRED | Confirmed by direct read |
| `src/admm/DsoOpt.jl` | `src/devices/AbstractDevice.jl` (`is_flexible_load`) | flexible-load probe | WIRED | Confirmed: `any(dv -> dv isa FourQuadBESS || is_flexible_load(dv), agg.devices)` |
| `test/test_experiments.jl` (WR-05 assertions) | `src/experiments/run.jl`/`solve_admm` (`reactive_consensus_mode`) | provenance field | WIRED | Live re-run by this verifier: centralized → `missing`, admm → `LIVE::ReactiveMode` |

### Behavioral Spot-Checks (run directly by this verifier, not TestItemRunner)

| Behavior | Command | Result | Status |
|---|---|---|---|
| FIX-01 3-way regression (AC-feasible / default-SOCP-feasible / thesis-literal-infeasible) | Direct `julia --project=.` script reproducing `test_exactness_verdict.jl` | AC feasible=true; gap=+0.005≥-1e-9; literal throws | ✓ PASS |
| FIX-02 v̂≥v Gan-Low direction | Same script | gap=+0.005 | ✓ PASS |
| FIX-03 PV back-feed receiving-end cone binds | Direct script reproducing `test_convex_branch_flow.jl`'s back-feed testitem | mag_rev=1.38, mag_fwd=2.4e-7 | ✓ PASS |
| FIX-04 zero hour-T discharge | Direct script reproducing `test_pvbattery.jl`'s FIX-04 testitem | p_dch[T]=1.4e-13 | ✓ PASS |
| WR-05 `reactive_consensus_mode` provenance (post-postfix-suite commit) | Direct script reproducing both `test_experiments.jl` testitem bodies | centralized→missing, admm→LIVE | ✓ PASS |

### Probe Execution

Not applicable — this phase has no `scripts/*/tests/probe-*.sh` convention; verification used direct `julia --project=.` scripts per project memory (`gsd-plan-verify-testitemrunner-trap`), not TestItemRunner under `--project=.`.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| FIX-01 | 26-02, 26-06, 26-08, 26-18, 26-19 | Documented verdict on thesis eq. 3.43, regression on AC-feasible/default-SOCP-feasible/thesis-literal-infeasible feeder | ✓ SATISFIED | Live-verified regression + docs page |
| FIX-02 | 26-02, 26-06, 26-08, 26-18 | Default satisfies v̂≥v or is relabelled; docstring/constraint consistency test | ✓ SATISFIED | Live-verified gap + load-bearing-bound test |
| FIX-03 | 26-05, 26-09, 26-10, 26-15, 26-16, 26-17, 26-19 | Receiving-end apparent-power limit on every limited branch; PV back-feed fixture | ✓ SATISFIED | Live-verified cone duals; ACPowerFlow mirrors it |
| FIX-04 | 26-03, 26-08 (partial), 26-09 (indirectly), 26-10, 26-11, 26-14, 26-16, 26-17 | SOC linked across whole horizon; zero/infeasible hour-T discharge regression | ✓ SATISFIED | Live-verified zero discharge; mpc_window/mpc_loop retargeted |
| FIX-05 | 26-04, 26-07, 26-12, 26-13, 26-17, 26-19, 26-20 | Flexible loads draw q=p·tanφ into `:Rq`; ADMM DsoOpt matches centralized default | ✓ SATISFIED | Per-device tests present; ADMM live-default confirmed; WR-05 provenance regression live-verified |

No orphaned requirements: FIX-01..05 are exactly the set REQUIREMENTS.md assigns to Phase 26, and all five appear across the 20 plans' frontmatter `requirements:` fields.

### Anti-Patterns Found

None found. Scanned every file listed in the 20 plans' `files_modified` frontmatter for `TBD`/`FIXME`/`XXX` debt markers — zero matches. No stub patterns (`return null`, empty handlers, hardcoded `[]`/`{}` flowing to output) found in the FIX-01..05 core files inspected (`ConvexBranchFlow.jl`, `ACPowerFlow.jl`, `PVBattery.jl`, `FourQuadBESS.jl`, `mpc_window.jl`, `Aggregator.jl`, `Thermostatic.jl`, `Deferrable.jl`, `Interruptible.jl`, `DsoOpt.jl`).

### PM-01..08 Post-Merge Decision Compliance

| Decision | Status | Evidence |
|---|---|---|
| PM-01 (honest restriction relabel, no "genuine relaxation" claims) | ✓ HONORED | `grep -rn "genuine relaxation"` across `src/`, `docs/`, `test/` returns only negated occurrences ("NOT/NEVER a genuine relaxation"); `26-02-SUMMARY.md` itself carries a correction addendum rather than leaving the original inaccurate claim unaddressed |
| PM-02 (AC oracle reports η<1 battery complementarity as diagnostic, not throw) | ✓ HONORED | `assert_battery_complementarity!` `on_violation` kwarg; `26-FINDINGS.md` documents the finding + backlog item |
| PM-03 (ADMM DSO-OPT live reactive coupling whenever flexible loads present) | ✓ HONORED | `_any_flexible_reactive` in `DsoOpt.jl`; WR-04 guard widened to cover both FourQuadBESS and is_flexible_load |
| PM-04 (mesh diamond φ=1.0 pin + finding) | ✓ HONORED | `test/fixtures_phase23.jl` pins φ=1.0 on both Thermostatic members; docstring documents the exactness-loss finding |
| PM-05 (tighten Clarabel tol_gap per-fixture, gate atol unchanged) | ✓ HONORED | Multiple per-fixture `tol_gap_abs`/`tol_gap_rel` calibrations in test files (26-10, 26-16, 26-17, 26-19), PF-04 gate itself untouched |
| PM-06 (re-pin legitimately moved goldens with old→new+cause) | ✓ HONORED | `26-GOLDEN-AUDIT.md` table §1 covers all named PM-06 goldens (IEEE-13 h16 DADP, `|V9[16]|`, FIT ratio, exporter surplus, canary) |
| PM-07 (ACPowerFlow gets thesis 3.37 too) | ✓ HONORED | `:smax_rev` registered in `ACPowerFlow.jl` |
| PM-08 (call-site fixes: unregister Prev/Qrev/smax_rev, decompose_dlmp accounts for :smax_rev, mpc_loop/test_mpc_terminal target soc_da[t+H]) | ✓ HONORED | Confirmed in `stochastic_welfare.jl` (26-09), `dlmp.jl` (26-10), `mpc_loop.jl`/`test_mpc_terminal.jl` (26-11) per GOLDEN-AUDIT and direct grep |

### Human Verification Required

None. All success criteria are mechanically/numerically checkable and were independently re-run by this verifier via direct Julia scripts against the live codebase (not merely re-reading SUMMARY.md prose or trusting the plans' own reported numbers).

### Gaps Summary

No gaps. All 6 ROADMAP success criteria are independently verified against the actual codebase:
five via live re-execution of the exact regression fixtures the plans describe (producing numeric
evidence, not just reading test source), and the sixth (golden-audit / suite-green claim) via
direct inspection of `26-postfix-suite.log`'s tail (30213 pass / 0 fail / 0 error / 5 broken, exit
0) plus independent verification that the two commits landing after that log (`c7aa143` test-only,
`d26b2d1` docs-only) do not change production code — confirmed by `git show --stat` on both and a
live re-run of the two new assertions `c7aa143` added (both pass). The code-review process
(`26-REVIEW.md` iteration 2: 0 critical, 0 warning, status clean) closed out cleanly after two fix
iterations. No debt markers, no orphaned requirements, no stale "genuine relaxation" language.

---

_Verified: 2026-09-29_
_Verifier: Claude (gsd-verifier)_
