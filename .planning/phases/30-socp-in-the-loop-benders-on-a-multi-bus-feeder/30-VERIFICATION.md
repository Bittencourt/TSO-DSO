---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
verified: 2026-10-01T15:56:32Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder Verification Report

**Phase Goal:** Researcher can run Stackelberg-Benders with the real branch-flow SOCP on a
realistic multi-bus, multi-period feeder, with feasibility cuts and automatically derived
bounds.
**Verified:** 2026-10-01T15:56:32Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `solve_stackelberg!` runs with `ConvexBranchFlow` on IEEE-13 and T>1 inside the Benders loop, converging with a closed LB/UB gap | VERIFIED | `test/test_planning_benders_ieee13.jl` (`IEEE13ShortHorizonFixtures`, T=4, real `ieee13_modified()`), runs `solve_stackelberg!` with `ConvexBranchFlow()`, asserts `result.gap <= 1e-6`, and cross-checks the Benders bracket `LB-ε <= J* <= UB+ε` against an **independently-built** monolithic joint SOCP (`IEEE13ShortHorizonFixtures.solve_joint_reference`, which itself certifies its own cone exactness). Independently re-executed this session via `EMU_FILTER` against the real `TSODSO` package (not trusting the SUMMARY): **13/13 pass**, 56.7s. The `docs/literate/stackelberg_benders.jl` rung further extends to T=24, a full day-ahead horizon, converging in 15 iterations, gap≈3.09e-7, with the battery-complementarity caveat openly documented (see below). |
| 2 | The planning oracle produces a feasibility cut when a pinned z is voltage- or thermally infeasible | VERIFIED | `src/planning/feasibility_oracle.jl` (`build_feasibility_oracle`/`solve_feasibility_oracle!`, slack-min oracle, `z` as a `Parameter`) wired into `src/planning/benders.jl`'s `solve_stackelberg!` oracle-catch branch (routes only genuine `MOI.INFEASIBLE`-class statuses, rethrows everything else unchanged). `test/test_planning_feasibility_oracle.jl` uses a rigorous relax-one-constraint-at-a-time ablation to *confirm* (not assume) thermal vs. voltage causation on the real `ieee13_modified()` feeder, asserts a nonzero-cost cut with the correct sign/separation property (`cut(u,z_k)>0`, `cut(u,z_feas)<=0`), and drives two full `solve_stackelberg!` end-to-end runs that hit a genuine infeasibility naturally and still converge, with the feasibility-cut row never updating UB (`gap=NaN` on that row). Independently re-executed: **35/35 pass**, 59.4s. |
| 3 | SOCP inexactness at a pinned z is handled by a documented policy instead of crashing the loop | VERIFIED | `inexact_policy` keyword (`:strict`/`:reject`/`:certify_incumbent`, default `:certify_incumbent`) in `src/planning/benders.jl`: `:strict` reproduces the pre-existing throw byte-for-byte; `:reject` appends the (valid, under-estimating) relaxation cut but bars the trial from UB/incumbent, with a named stall diagnosis; `:certify_incumbent` accepts the cut, logs the measured cone gap (`BendersTrace.socp_maxgap_trace`/`policy_action_trace`), and if the *final incumbent* itself is inexact, runs `ACPowerFlow(limits=false)` (`src/planning/ac_recheck.jl`) and returns a populated `ac_report` with an explicitly-derived `ok` field and a non-`nothing` `error` field on AC-recheck failure — never silently passed. `test/test_planning_inexact_policy.jl` drives a MEASURED, naturally-occurring inexact fixture (not synthetic) through all three policies, including a dedicated item that forces the incumbent itself inexact and inspects the populated `ac_report` end-to-end. Independently re-executed: **91/91 pass**, 1m18.6s (includes `test_planning_ac_recheck.jl`'s own **22/22**, also re-run independently). |
| 4 | The master's α lower bounds (`α_op_lb`, `α_x_lb`) are derived automatically; a user-supplied bound above the true minimum is detected and rejected | VERIFIED | `:auto` (new default) resolves both bounds via a genuine one-time relaxed solve (`derive_alpha_op_lb`/`derive_alpha_x_lb` in `src/planning/master.jl`), requiring `bounds_ctx`. An explicit bound supplied alongside `bounds_ctx` is validated against the derived minimum plus a measured, scale-aware slack and raises `ArgumentError` naming the offending value when it exceeds it — demonstrated by `test_planning_master.jl` (`α_op_lb=1e9`/`α_x_lb=1e9` rejected; a bound exactly at the derived optimum ± slack accepted/rejected correctly) and independently by `test_planning_alpha_bounds_stackelberg.jl` through `solve_stackelberg!`'s own unconditional `bounds_ctx` wiring. A universal *runtime* floor guard (`_assert_epigraph_floor`) is defense-in-depth regardless of how the bound was derived. `30-ALPHA-AUDIT.md`'s repo-wide T>1 census independently confirms the one pre-existing T>1 literal (`test_planning_hardening.jl`, T=8) is `-50.0` (valid) today, and that the formerly-documented `-5.0` literal *would* be rejected by the new gate — this is explicitly reconciled in `30-FINDINGS.md` as "RESEARCH.md was stale about what's in the repo, not wrong about the math," not a live discrepancy. Independently re-executed: planning-master BILEV-05 items **54/54 pass** (29.1s, with `Phase6Fixtures`/`ToyDeviceFixture` included), alpha-bounds-stackelberg **16/16 pass** (1m00.1s). |

**Score:** 4/4 truths verified

### Scope note: `DistributorView` α_x_lb build-time skip (not a gap)

`build_master`'s `α_x_lb=:auto`/explicit-bound validation requires a sound per-object
relaxed-minimum derivation from `bounds_ctx.follower_kwargs`. For `src/planning/coupling.jl`'s
`DistributorView` (the `run_nash!` per-distributor pooled-capacity follower), no such sound
derivation exists, so the build-time check is explicitly, documentedly **skipped** (never
silently "passed" as valid) — `α_op_lb` on the same call remains fully validated regardless, and
the universal runtime floor guard still applies as defense-in-depth. This is a stated, narrow
scope limit (consistent with CONTEXT.md's "two layers" design, where the runtime layer is the
backstop for exactly this case), not a failure of SC-4, whose own wording ("the master's α lower
bounds... derived automatically... a user-supplied bound above the true minimum is detected and
rejected") is fully demonstrated on the general (non-pooled) follower path used by
`solve_stackelberg!` itself and by `build_master`'s own direct callers.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/planning/feasibility_oracle.jl` | Slack-min feasibility oracle (BILEV-04a) | VERIFIED | 249 lines, `build_feasibility_oracle`/`solve_feasibility_oracle!`, registered in PVAL-04's builder registry (`test/test_planning_noninteger.jl:55-56`) |
| `src/planning/ac_recheck.jl` | AC physics re-check for inexact incumbents (BILEV-04b) | VERIFIED | 193 lines, wired into `solve_stackelberg!`'s policy dispatch, returns a populated/empty `ac_report` with explicit `ok`/`error` fields |
| `src/planning/master.jl` (`derive_alpha_op_lb`/`derive_alpha_x_lb`, `:auto`) | Automatic α bound derivation (BILEV-05) | VERIFIED | Build-time rejection with named `ArgumentError`, byte-identical path preserved when `bounds_ctx === nothing` |
| `src/planning/benders.jl` (`inexact_policy`, oracle-feasibility-cut branch) | 3-way inexactness policy + feasibility-cut integration | VERIFIED | 1714 lines; feasibility-cut branch resolved before policy dispatch; `BendersTrace` carries `socp_maxgap_trace`/`policy_action_trace`/`feas_cut_v_trace` |
| `test/test_planning_benders_ieee13.jl` | BILEV-03 headline IEEE-13 T=4 convergence + monolithic cross-check | VERIFIED, WIRED, independently re-run (13/13 pass) |
| `test/test_planning_feasibility_oracle.jl` | BILEV-04a thermal/voltage feasibility-cut fixtures | VERIFIED, WIRED, independently re-run (35/35 pass) |
| `test/test_planning_inexact_policy.jl` + `test/test_planning_ac_recheck.jl` | BILEV-04b 3-way policy matrix + AC re-check | VERIFIED, WIRED, independently re-run (91/91 + 22/22 pass) |
| `test/test_planning_master.jl` + `test/test_planning_alpha_bounds_stackelberg.jl` | BILEV-05 build-time rejection + `:auto` wiring | VERIFIED, WIRED, independently re-run (54/54 + 16/16 pass) |
| `docs/literate/stackelberg_benders.jl` | T=24 Literate extension (CONTEXT.md requirement: larger-T run outside the suite) | VERIFIED (code present, measured numbers recorded; see T=24 note below) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `solve_stackelberg!` oracle-catch | `feasibility_oracle.jl` | genuine `MOI.INFEASIBLE`-class status routes to `solve_feasibility_oracle!`, everything else rethrown | WIRED | Confirmed by both static read and independent test re-run |
| `solve_stackelberg!` inexact dispatch | `ac_recheck.jl` | `oracle_res.exactness === :inexact` + final-incumbent check → `ACPowerFlow(limits=false)` | WIRED | `ac_report` populated end-to-end in a dedicated test, `nothing` on exact-incumbent runs (both legitimate per BILEV-04b) |
| `solve_stackelberg!`/`build_master` | `derive_alpha_op_lb`/`derive_alpha_x_lb` | `bounds_ctx` constructed unconditionally in `solve_stackelberg!`, forwarded through `run_nash!` | WIRED | `master.jl:565-629`; zero regression on ~90 pre-existing explicit-bound call sites (`bounds_ctx===nothing` branch untouched) |
| `run_nash!` | `solve_stackelberg!` | `inexact_policy` forwarded to every best response, default `:strict` | WIRED | `src/planning/nash.jl:391-399` |

### Probe / Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| BILEV-03 headline IEEE-13 T=4 convergence | `EMU_FILTER="converges on a realistic multi-bus" julia emu.jl fixtures_planning_ieee13_short.jl test_planning_benders_ieee13.jl` | 13/13 pass, 56.7s | PASS |
| BILEV-04a feasibility-cut fixtures | `julia emu.jl test_planning_feasibility_oracle.jl` | 35/35 pass, 59.4s | PASS |
| BILEV-04b inexact-policy matrix + AC report | `julia emu.jl fixtures_planning_ieee13_short.jl test_planning_inexact_policy.jl` | 91/91 pass, 1m18.6s | PASS |
| BILEV-04b AC-recheck module | `julia emu.jl test_planning_ac_recheck.jl` | 22/22 pass, 29.7s | PASS |
| BILEV-05 build-time rejection (`build_master`) | `julia emu.jl fixtures_phase6.jl test_planning_oracle.jl test_planning_master.jl` | 54/54 pass, 29.1s | PASS |
| BILEV-05 `solve_stackelberg!` `:auto` wiring | `julia emu.jl fixtures_phase6.jl test_planning_oracle.jl fixtures_planning_ieee13_short.jl test_planning_alpha_bounds_stackelberg.jl` | 16/16 pass, 1m00.1s | PASS |
| Golden-move audit, base = true Phase-29 close commit `e5dc782` | `python3 .planning/phases/28-.../scripts/audit_goldens.py --base e5dc782 --head HEAD` | exit 0, 0 flagged moves | PASS |
| Certified full suite (orchestrator-established evidence, cross-checked against the scratchpad's own retained log) | `Pkg.test()` at HEAD `22b7eb5` | 31091 pass / 0 fail / 0 error / 5 broken, 23m56.7s | PASS |

All spot-checks were executed independently in this verification session against the real
`TSODSO` package source (not copy-pasted from any SUMMARY), using the project's documented
`JULIA_LOAD_PATH="test:.:@stdlib"` + direct-script idiom (TestItemRunner does not resolve under
`--project=.` on this repo).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BILEV-03 | 30-03, 30-05 | `solve_stackelberg!` + `ConvexBranchFlow` + IEEE-13 + T>1, closed LB/UB gap | SATISFIED | Truth #1 above |
| BILEV-04 | 30-01, 30-04 | Feasibility cuts on infeasible pinned z + documented non-crashing inexactness policy | SATISFIED | Truths #2, #3 above |
| BILEV-05 | 30-02, 30-04 | Automatic α lower bounds + rejection of over-high user bounds | SATISFIED | Truth #4 above |

REQUIREMENTS.md cross-reference: BILEV-03/04/05 all marked `Complete | Phase 30`; no orphaned
Phase-30 requirement IDs found (BILEV-06/07/08 correctly map to Phase 31, matching ROADMAP.md).

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX` debt markers found in the phase's modified files. No stub
(`return null`/`return []`/empty-handler) patterns found in `feasibility_oracle.jl`,
`ac_recheck.jl`, or the `inexact_policy`/`:auto`-bound code paths — every branch either performs
a real solve/derivation or raises a named, diagnostic error.

**Carried-forward, non-blocking findings** (from the orchestrator's 3-iteration code review,
`30-REVIEW.md`, final: 0 critical / 3 warning / 3 info, converged from an initial 3
critical/10 warning/7 info):

1. **WR-01** — the integer corner search (`_oracle_or_infeasible`, Laporte-Louveaux path) maps
   `ALMOST_INFEASIBLE` to `+Inf` without the outer loop's own confirmation step, which can
   over-estimate the per-corner recourse `Q_nu`.
2. **WR-02** — the LL cut's validity argument requires an unenforced `Q_nu >= L` precondition;
   `L` (`α_op_lb + α_x_lb` for `BendersMasterInteger`) is never validated.
3. **WR-03** — an accepted build-time bound within the WR-05 acceptance slack can inflate `LB` by
   up to `S + gap` with no widening of the convergence certificate (measured ≈2.5e-8 relative on
   IEEE-13 T=4 — harmless on this instance, not a general guarantee).

**Judgment:** all three warnings live exclusively in `BendersMasterInteger`/`add_ll_cut!`/
`ll_cut_recourse` — the **integer** investment recourse path, confirmed by static grep
(`_oracle_or_infeasible`/`add_ll_cut!` call sites are all `BendersMasterInteger`-only). Phase
30's own scope and every one of its own tests exercise the **continuous** `BendersMaster` on
LinDistFlow/`ConvexBranchFlow` — none of the three warnings are reachable from Phase 30's own
success criteria or its own test suite. They are correctly classified as Phase 31 (BILEV-07,
integer N>1) input, consistent with the ROADMAP's own phase boundary, and are explicitly recorded
(not silenced) in `30-FINDINGS.md` and this phase's SUMMARY. **Not treated as a Phase 30 gap.**

**T=24 Literate battery-complementarity limitation:** `docs/literate/stackelberg_benders.jl`'s
T=24 rung documents (not hides) that the T=4 headline's own kwargs throw a genuine
`assert_battery_complementarity!` violation at `t=7` once the full 24-hour price swing is in
play, and that the T=24 run therefore uses a tighter investment ceiling to stay inside the
complementarity-safe region. This is an honestly-reported scope boundary of a Literate
*demonstration* script (explicitly out of the in-suite test budget per CONTEXT.md), not a defect
in the production `solve_stackelberg!`/`ConvexBranchFlow` path, which has its own unconditional
complementarity gate that always fires loudly rather than silently accepting a violating solve.

### Human Verification Required

None. Every observable truth for this phase is a solver/code-level behavior (convergence
certificates, cut validity, exactness-policy dispatch, bound rejection) that was verified by
static code reading plus independent, non-SUMMARY-trusting test re-execution against the real
package. No UI, visual, or subjective-judgment artifact is in scope for this phase.

### Gaps Summary

No gaps. All four ROADMAP success criteria are independently verified against the actual
codebase (not SUMMARY claims): the headline IEEE-13 T=4 `ConvexBranchFlow` Benders convergence
re-runs clean with an independent monolithic cross-check; both thermal and voltage feasibility
cuts are demonstrated via causation-confirming ablation fixtures with pinned sign/validity
checks; the 3-way `inexact_policy` is demonstrated end-to-end including a populated `ac_report`
on a genuinely-inexact incumbent; and automatic α-bound derivation with build-time rejection of
over-high user bounds is demonstrated both directly and through `solve_stackelberg!`'s own
wiring. The RESEARCH.md/ALPHA-AUDIT.md "discrepancy" flagged for this review is resolved and
correctly attributed in `30-FINDINGS.md` (a stale repo-state reading, not a math error) and
independently confirmed here via test re-execution. The three open code-review warnings and the
T=24 complementarity note are real, honestly documented limitations, but they sit outside Phase
30's own continuous-Benders/IEEE-13 scope and are correctly carried forward to Phase 31.

---
*Verified: 2026-10-01T15:56:32Z*
*Verifier: Claude (gsd-verifier)*
