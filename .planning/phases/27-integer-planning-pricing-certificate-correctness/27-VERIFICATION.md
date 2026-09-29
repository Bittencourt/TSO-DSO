---
phase: 27-integer-planning-pricing-certificate-correctness
verified: 2026-09-29T14:05:00Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
---

# Phase 27: Integer Planning & Pricing Certificate Correctness Verification Report

**Phase Goal:** Researcher can trust the integer Benders recourse for T>1, the DLMP component
names, the exactness gate, the FIT-baseline counterfactual, and MPC's realized-welfare
accounting.

**Verified:** 2026-09-29T14:05:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `corner_recourse` returns the true per-hour `Q(bᵛ)` for T>1, matching exhaustive enumeration on a T>1 test, instead of `fill(z,T)` | ✓ VERIFIED | `src/planning/benders.jl:158-164` dispatches `T==1 → _corner_recourse_ternary` (verbatim pre-Phase-27 body) / `T>1 → _corner_recourse_joint` (genuine Kelley's-method joint T-dimensional minimization, `benders.jl:306-…`, reading `fr.π_s .+ orr.π` as an exact gradient). No `fill(z,T)` surrogate remains (grepped: absent). `test/test_planning_certification_integer.jl` adds `enumerate_lattice_2d` (dense-grid T=2 oracle) and certifies `corner_recourse(T=2)` against it within a measured Lipschitz-derived tolerance on a non-separable `PVBattery` fixture. Code review (27-REVIEW.md CR-01) independently reproduced the converged value against the dense-grid bound outside the test suite and confirmed the iterative stall-guard bisection terminates correctly. |
| 2 | DLMP components named/documented as cone-slot and drop-constraint multipliers; the "voltage ≈ 0 when unbinding" test uses realistic impedances and passes, or is replaced by a correct property | ✓ VERIFIED | `src/pricing/dlmp.jl:250` defines `struct DlmpDecomposition{A}` with `energy, cone, drop, congestion, reactive, total` fields; `.loss`/`.voltage` survive only as one-time `Base.depwarn`-deprecated `Base.getproperty` aliases (`dlmp.jl:259-268`). `test/test_pricing_dlmp.jl:277-` removes the old, factually-incorrect "voltage≈0 when unbinding" assertion and replaces it with a zero-iff-every-root-path-multiplier-zero property verified on the IEEE-13 **ground** fixture (realistic non-toy impedances, `build_ieee13_ground_aggregators`), checked bidirectionally (root bus vacuously zero; all 264 sampled non-root (bus,hour) pairs genuinely nonzero). WR-01 code-review finding (NamedTuple-shape backward compatibility) fixed and confirmed (`Base.NamedTuple(::DlmpDecomposition)`, `dlmp.jl:279-311`). |
| 3 | SOCP exactness gate uses a per-branch relative floor; a test shows a slack cone on a lightly loaded branch is flagged | ✓ VERIFIED | `src/models/exactness.jl:75,85` define measured constants `MEASURED_ε_FIX08=1.0e-9`, `TAU_SOLVER_FIX08=2.0e-7`; `assert_socp_exact!` (`exactness.jl:170`) computes a HYBRID per-branch floor `atol_b = max(τ_solver, ε·ref_b)` replacing the flat `atol=1e-6`, with `ref_b` the branch's own `smax²` (thermal-limited) or the head-branch flow magnitude² (interior). `test/test_exactness.jl` ("per-branch floor flags a slack cone on a small-smax branch the old flat atol missed (FIX-08)") demonstrates a `smax=0.01` branch with an injected `l=5e-7` gap — below the OLD flat atol, now correctly thrown. A second regression item confirms the head-branch lookup is orientation-agnostic (forward vs. reversed `br.from`/`br.to`). An initial pure-relative-floor approach was found irreconcilable with a pre-existing WR-01 regression and was explicitly escalated in `27-FINDINGS.md` before the user-directed hybrid resolution — not silently patched. |
| 4 | FIT-baseline counterfactual asserts or reports exactness (never skips it); the `tol_gap=1e-10` `ALMOST_OPTIMAL` flake is root-caused and fixed or explicitly bounded | ✓ VERIFIED (with a judged, user-authorized reinterpretation — see note below) | `fit_baseline`'s SITE 2 is now a genuine AC power flow (`ACPowerFlow(; limits=false)`, Ipopt, `src/pricing/fit.jl:539-`) gated on `on_inexact::Symbol` (`:error` default throws on non-`LOCALLY_SOLVED`/`OPTIMAL`, `:report` returns `ac_status`+`ac_violations`, never a silent skip). The SITE-3 nested `solve_welfare` cross-check's `ALMOST_OPTIMAL` flake at `tol_gap=1e-10` was root-caused (Plan 27-05: `max_iter∈{200,400,2000}` produces BYTE-IDENTICAL Clarabel iteration traces terminating at iteration 24 — conclusively a genuine conditioning wall, not slow convergence) and bounded behind a measured, named `FIT_SITE3_ALMOST_GAP_TOL=7.749e-5` (10x the measured achieved gap), gated by a new `solve_welfare(...; allow_almost=false)` kwarg defaulting `false` everywhere else. Both mechanisms remain intact and unrelaxed after Plan 27-09's SITE-2 reformulation (confirmed by direct grep: `FIT_SITE3_ALMOST_GAP_TOL` and the SITE-3 retry-and-verify wrapper are untouched). |
| 5 | MPC realized welfare/regret settle against the true plant (PV clipping, true-state feasibility, true import); forecast-settled number survives only as a labelled diagnostic | ✓ VERIFIED | `run_mpc` (`src/experiments/mpc_loop.jl`) clips realized PVBattery charge/export to true `Ppv` (A6, both `p_ch` AND `pv_used` after the CR-02 code-review fix), throws (never clamps) on a genuine SOC/temperature out-of-band via `_mpc_assert_true_state_inband` (lines 594/639/661), and settles the frontier import via `_mpc_truth_import_acpf` — a genuine AC power flow at the fixed realized dispatch (`ACPowerFlow(; limits=false)`, warm-started from the window's own SOCP point). `forecast_settled_welfare` is the renamed, byte-unchanged pre-phase quantity; the zero-forecast-error byte-identity invariant (`realized_welfare == forecast_settled_welfare` at `atol=1e-6`) is a permanent regression. `regret` is re-derived against the truth-settled value. |
| 6 | Every golden this phase's fixes move is re-derived in-phase with a stated explanation; full suite green at phase close | ✓ VERIFIED (suite-green confirmed at HEAD-1; final close-out run in flight — see caveat) | `27-GOLDEN-AUDIT.md` documents every golden move (3 tol_gap precision-floor pins, the hybrid-floor constants, the head-branch orientation fix, the 3-stage truth-settlement reformulation SOCP→limited-AC→physics-only-AC, the seed `1→5→1` round-trip with zero net golden left non-default, the DLMP rename, and the FIT SITE-2 SOCP→AC reformulation) each with an old→new value/cause/plan attribution. `27-postfix-suite.log` (HEAD `d8f3d02`, i.e. all 9 plans + code-review iteration-1 fixes) is GREEN: `30422 pass / 0 fail / 0 error / 5 broken`, exit 0 — the same 5 named Broken items as the Phase 26 baseline, no new failures. |

**Score:** 6/6 truths verified

### FIT-baseline exactness reinterpretation — explicit judgment call

The CONTEXT's "Execution amendment" (2026-09-29, user decisions during execution) directs
that FIX-09/FIX-10's truth/counterfactual settlement move to AC-physics-only with violation
reporting. This changes what "asserts or reports exactness" means for FIT SITE 2: there is no
longer an SOC relaxation cone to certify exact (SITE 2 is a genuine AC power flow, not a
relaxation), so `on_inexact` now gates AC **convergence** (`LOCALLY_SOLVED`/`OPTIMAL` required,
`ALMOST_LOCALLY_SOLVED` treated as failure) rather than cone-exactness, and `socp_maxgap` is
always `nothing` (kept only for source compatibility). Read literally against the pre-amendment
ROADMAP wording ("asserts or reports exactness"), this could look like scope drift; read against
the CONTEXT's own explicit, dated user amendment — which is the authoritative, later-in-time
instruction — this is exactly what was ordered, and it is arguably a *stronger* guarantee than
cone-exactness (a converged AC power flow has no relaxation gap by construction; the
previously-used SOCP fixed-dispatch re-solve was shown to be **structurally** inexact — gap≈211,
ratio≈9993 on the IEEE-123 REPRO-01 population point — precisely because fixing every device
injection leaves the loss current unpinned, per Finding 1 in `27-09-SUMMARY.md`). Judgment:
**intent is met.** The AC-convergence certification is a legitimate, arguably superior,
realization of "certified, never silently skipped" for a settlement re-solve of this specific
structural class, explicitly authorized by the user amendment in `27-CONTEXT.md`. This is
recorded here rather than silently accepted so a future reader can independently agree or
disagree with the reinterpretation.

### No silent seed/tolerance masking found

Reviewed every seed and tolerance change across all 9 plans for the CONTEXT's "never raise
τ_solver/ε/rtol to hide it" policy:
- FIX-08's hybrid floor (`τ_solver=2e-7`, `ε=1e-9`): measured in two stages, with an initial
  pure-relative-floor approach explicitly ESCALATED (not silently resolved) when found
  irreconcilable with a pre-existing regression test — user-directed hybrid resolution recorded
  in `27-FINDINGS.md` with the full sweep.
- Three fixtures (`test_planning_oracle.jl`, `test_stochastic_welfare.jl`, `test_thesis_repro.jl`)
  received a **tighter** `tol_gap=1e-9` (Clarabel convergence precision, not the exactness gate
  itself) via a measured ladder (1e-8→1e-11) — this is a solver-precision tightening, not a
  relaxation, and does not touch `τ_solver`/`ε`.
- The MPC `seed=1→5→1` round-trip (27-03→27-07/27-08→27-09) is fully documented in
  `27-GOLDEN-AUDIT.md` §1 "Seed history note": each intermediate substitution is tied to a
  specific, measured, named root cause (SOCP knife-edge, then a genuine thermal overload under
  the limited AC settlement), and `seed=1` is restored once the physics-only decision removed
  the reason for the substitution — confirmed by direct grep, no non-default seed remains at
  phase close.
- No fixture's tolerance was loosened to make a failing test pass; every documented deviation is
  either a measured, justified constant, a genuine escalation with a recorded resolution, or a
  restored default. No masking found.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/planning/benders.jl` | T==1/T>1 dispatch, `_corner_recourse_joint` | ✓ VERIFIED | Read directly; dispatch, cutting-plane loop, Farkas-cut and stall-guard bisection all present and wired |
| `src/models/exactness.jl` | Hybrid per-branch floor | ✓ VERIFIED | `MEASURED_ε_FIX08`/`TAU_SOLVER_FIX08` constants + `assert_socp_exact!` computation confirmed |
| `src/pricing/dlmp.jl` | `DlmpDecomposition` struct, cone/drop naming | ✓ VERIFIED | Struct + deprecation shim confirmed |
| `src/experiments/mpc_loop.jl` | Truth-settled `run_mpc`, `_mpc_truth_import_acpf`, `settlement_violations` | ✓ VERIFIED | All present, wired into `run_mpc`'s returned `NamedTuple` |
| `src/pricing/fit.jl` | `on_inexact`, AC SITE-2 settlement, `ac_status`/`ac_violations` | ✓ VERIFIED | Present and wired |
| `src/powerflow/ACPowerFlow.jl` | `limits::Bool` kwarg | ✓ VERIFIED | Field + keyword constructor confirmed, default `true` (byte-identical for pre-27-09 call sites) |
| `test/test_planning_certification_integer.jl` | T=2 enumeration oracle | ✓ VERIFIED | `enumerate_lattice_2d` present |
| `test/test_exactness.jl` | Slack-cone regression + orientation regression | ✓ VERIFIED | Both `@testitem`s present |
| `test/test_pricing_dlmp.jl` | zero-iff property, alias regression | ✓ VERIFIED | Present |
| `test/test_mpc_loop.jl` | `seed=1` restored, WR-04 `pvbattery_truth_trace` test | ✓ VERIFIED | `seed = 1` at lines 84/285/645/712; WR-04 testitem present |
| `test/test_fit.jl`, `test/test_pricing_fit.jl` | AC-convergence-forced test, source tripwire | ✓ VERIFIED | Present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `corner_recourse` (T>1) | `solve_follower!`/`solve_planning_oracle!` | direct calls inside `evaluate()` | WIRED | Confirmed by reading `_corner_recourse_joint`'s body |
| `assert_socp_exact!` | every `ConvexBranchFlow`-formulated `ctx` | `haskey(ctx.meta[:pf_vars], :l)`-gated call sites (`solve_welfare`, `fit_baseline` seed solve, MPC seed solve) | WIRED | Confirmed via grep of call sites; 2 pre-existing explicit-`atol` call sites bypass unaffected |
| `decompose_dlmp` | DLMP consumers (tests, literate doc) | `.cone`/`.drop` field access | WIRED | Migrated call sites confirmed; unmigrated script consumers (`scripts/*.jl`) continue working via the deprecation alias (documented, not a defect) |
| `run_mpc` | `_mpc_truth_import_acpf` | per-applied-hour call inside the accumulation loop | WIRED | Confirmed at `mpc_loop.jl:711-719`; `pvbattery_truth_trace` diagnostic wraps the real accumulation line (WR-04 fix), demonstrated sensitive to a revert by direct script |
| `fit_baseline` SITE 2 | `ACPowerFlow(; limits=false)` | conditional AC upgrade gated on `has_cone` | WIRED | Confirmed at `fit.jl:539-`; REPRO-01 measured to pass under the new settlement |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `corner_recourse` T=2 dispatch exists and no `fill(z,T)` surrogate remains | `grep -n "fill(z, T)\|fill(z,T)" src/planning/benders.jl` | no match outside `_corner_recourse_ternary`'s intentional T==1-only body | ✓ PASS |
| No debt markers in phase-touched source files | `grep -nE "TBD|FIXME|XXX"` across all 8 phase-touched `src/*.jl` files | 0 matches | ✓ PASS |
| `ACPowerFlow(; limits=true)` byte-identical default | direct read of `contribute!`'s `pf.limits` gating | confirmed additive-only field | ✓ PASS |

### Probe Execution

Not applicable — this is a Julia/JuMP research framework phase, not a migration/tooling phase with declared probe scripts. No `scripts/*/tests/probe-*.sh` convention exists in this repository.

### Full-Suite Evidence

| Run | HEAD | Result | Note |
|-----|------|--------|------|
| `27-postfix-suite.log` | `d8f3d02` (all 9 plans + code-review iteration-1 fixes: CR-01, CR-02, WR-01, WR-02) | **GREEN** — 30422 pass / 0 fail / 0 error / 5 broken, exit 0 | Independently confirmed by reading the log's final `Test Summary` line and its "tests passed" trailer |
| `7c3e401` (WR-04 fix, iteration 2) | — | Not covered by a full-suite run; verified by direct hand demonstration (REVIEW-FIX.md iteration 2: reverted the fixed accumulation line, re-ran the committed test body standalone, confirmed FAIL; restored, confirmed PASS; also smoke-tested the zero-forecast-error happy-path invariant unaffected) | Purely additive diff (+110/-0 across 2 files — confirmed via `git show --stat`); code review iteration 3 (27-REVIEW.md) independently confirmed the fix and found 0 critical/0 warning remaining |
| `40ccff2` (current HEAD) | — | Docs-only commit (`27-REVIEW-FIX.md`, `27-REVIEW.md`, `27-postfix-suite.{log,done}` — confirmed via `git show --stat`, no `src/`/`test/` files touched) | No behavior change possible |
| `27-close-suite.log` | `40ccff2` (current HEAD) | **IN PROGRESS at verification time** (Julia PID 301562 confirmed alive via `pgrep`; log still growing, no `.done` marker yet) | See caveat below — not run by this verifier per explicit instruction |

**Caveat (informational, not a gap):** the phase's own closing full-suite certification run
(`27-close-suite.log`) had not finished at the time of this verification (confirmed still
running via `pgrep -fa julia`, log growing between checks, no `27-close-suite.done` file yet).
Per this verification task's explicit instruction, the full suite was not run or waited on by
this verifier. The evidence available — a GREEN full suite one commit prior
(`d8f3d02`), a purely additive +110/-0 diff since then that was independently
hand-verified fail-before/pass-after on its own regression, and a docs-only commit after that
— gives high confidence the close-out run will also be GREEN. This is not treated as a
BLOCKER or WARNING because no failing or uncertain evidence exists; it is a pending
confirmation of an already strongly-corroborated fact. **Recommend the orchestrator/human
confirm `27-close-suite.done` reads `0` before considering the phase's SC-6 gate formally
closed.**

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|----------------|--------------|--------|----------|
| FIX-06 | 27-01 | `corner_recourse` T>1 joint recourse, T=1 byte-identical | ✓ SATISFIED | See Truth #1 |
| FIX-07 | 27-04 | DLMP component naming (cone/drop), corrected test property | ✓ SATISFIED | See Truth #2 |
| FIX-08 | 27-02, 27-07 | Per-branch exactness floor, slack-cone regression | ✓ SATISFIED | See Truth #3 |
| FIX-09 | 27-05, 27-09 | FIT-baseline certification, `ALMOST_OPTIMAL` root cause | ✓ SATISFIED (with the AC-convergence reinterpretation noted above) | See Truth #4 |
| FIX-10 | 27-03, 27-07, 27-08, 27-09 | MPC truth-settled realized welfare/regret | ✓ SATISFIED | See Truth #5 |

No orphaned requirements found: `.planning/REQUIREMENTS.md`'s FIX-06 through FIX-10 entries all
map to a plan in this phase's directory; FIX-11 (golden re-derivation) is a cross-phase
requirement satisfied in-phase by Plan 27-06's `27-GOLDEN-AUDIT.md` (Truth #6) but is not itself
in this phase's declared requirement-ID list.

### Anti-Patterns Found

None. No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers in any of the 8 phase-touched
`src/*.jl` files. No stub return patterns (`return null`/`return {}`/empty handlers) — this is a
Julia numerical codebase, not a UI, and every new code path (cutting-plane loop, hybrid floor,
DLMP struct, AC settlement, violation diagnostics) is exercised by a committed `@testitem`
and/or a repro script, confirmed by direct reading.

Code review (`27-REVIEW.md`, 2 iterations) found 2 CRITICAL + 3 WARNING issues in iteration 1
(all fixed, commits `ba01c6e`/`9ad07dd`/`570089d`/`2a3670b`) and 1 further WARNING in iteration 2
(WR-04, a test-adequacy gap — fixed, commit `7c3e401`). Iteration 3 (orchestrator re-review)
confirmed WR-04 resolved with 0 critical/0 warning remaining. `27-REVIEW.md`'s final status:
clean.

### Human Verification Required

None. This phase's work is internal numerical-correctness/certificate logic (SOCP exactness
gates, MPC/FIT settlement re-solves, DLMP naming, integer recourse) verified through direct code
reading, existing/new automated tests, and code review — no UI, visual, or subjective-judgment
surface requiring human testing.

### Gaps Summary

No gaps found. All 5 requirement IDs (FIX-06 through FIX-10) are implemented, wired, and tested;
every escalation raised during execution (the FIX-08 pure-relative-floor conflict, the FIX-10
MPC seed knife-edge, the FIX-08/FIX-10 AC-settlement genuine thermal-limit finding) was
explicitly surfaced and resolved per the CONTEXT's "never silently hide it" policy, not papered
over; the cross-phase golden audit accounts for every numeric/behavioral change with a stated
cause; code review is clean after 2 fix iterations; the full suite was GREEN one commit prior to
HEAD with only a purely-additive, independently hand-verified diff since. The sole open item is
the still-in-flight final closing suite run, which is an informational caveat, not a blocker.

---

_Verified: 2026-09-29T14:05:00Z_
_Verifier: Claude (gsd-verifier)_

## Close-out suite

`27-close-suite.log` at HEAD `40ccff2`: 30703 pass / 0 fail / 0 error / 5 broken, exit 0 (+281 vs d8f3d02 = the WR-04 per-trace-entry assertions) — SC-6 formally closed.
