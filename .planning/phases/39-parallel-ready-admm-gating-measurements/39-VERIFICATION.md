---
phase: 39-parallel-ready-admm-gating-measurements
verified: 2026-10-24T11:10:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
gaps: []
human_verification:
  - test: "Reproduce the researcher opt-in on your machine: JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'"
    expected: "All items pass (executor measured 33/33 at -t 4 post-WR-01): bitwise serial-vs-threaded equality (both legs iters=56, welfare=-4823.66604824162), all three error-parity legs type+message identical, no TaskFailedException/CompositeException wrappers"
    why_human: "The two binding thread-gated items are allowlisted skips in the default 1-thread suite (expected_broken.txt), so the certified 32405-pass run never executes them; threaded determinism is host-dependent (BLAS backend, core count) real-time behavior that only the researcher's own machine can confirm for their environment"
  - test: "Decide whether/when to re-run the T=24 full attribution point on a host with ~12 GiB genuinely available (julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 24)"
    expected: "Loop-stage attribution at T=24 completes, or the Phase-35 standing figures (11.52 GiB peak / 10.17 GiB loop delta) remain the accepted T=24 record into the Phase-40 scaling report"
    why_human: "SCALE-06 is satisfied by the documented honest outcome (T=24 earlyoom kill recorded + build-only attribution; T=10 fully reconciled with 0.62 GiB residual); completing the T=24 loop stages is a resource/scheduling decision, not a code property"
---

# Phase 39: Parallel-Ready ADMM & Gating Measurements Verification Report

**Phase Goal:** A researcher can opt in to solving aggregator subproblems concurrently with results identical to serial, and the gating facts for later phases (Clarabel concurrency, 8500 memory attribution) are measured.
**Verified:** 2026-10-24T11:10:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP SC contract) | Status | Evidence |
|---|---|---|---|
| 1 | Documented Clarabel concurrency/determinism spike exists (incl. `direct_model` question), states bitwise-equality verdict under `-t 4`; threaded execution enabled only if it passes | ✓ VERIFIED | `.planning/spikes/005-clarabel-concurrency/README.md` line 6 `verdict: PASS`; direct_model settled as `AddVariableNotAllowed` at first `@variable` (README lines 92-102); `sweep.csv` 167 measured rows incl. `verdict,ALL,threaded_vs_serial,BITWISE-EQUAL` (line 163, "under julia -t 4, BLAS=1, MOI.NumberOfThreads()=1, Clarabel 0.11.1"); controls live-proofed (positive/cross-state PASS, negative FAILED-AS-DESIGNED via 2-ulp escalation); MANIFEST row 005 registered; gate honored — executor landed in wave 2 (depends_on 39-01) and the equality test cites the gate artifact (`test_admm_parallel.jl` line 111) |
| 2 | Researcher selects threaded opt-in; multi-aggregator fixture threaded == serial on iterations, residual traces, welfare, prices; default serial path hits canary (iters=56, welfare=-4823.66604824162) unchanged | ✓ VERIFIED | `src/admm/solve_admm.jl`: `parallel::Bool = false` trailing kwarg (line 310), fail-loud `ArgumentError` at `nthreads()==1` (lines 318-321), BLAS snapshot + `finally` restore on every exit path (lines 358/445). `src/admm/admm_phases.jl` `_agr_solve_step!` (line 188): serial branch = exact pre-existing loop; threaded branch pins BLAS=1 + MOI=1 (211-214), one `Threads.@spawn` per aggregator (222), fetch in load_nodes order, `TaskFailedException` unwrap (253). `test/test_admm_parallel.jl` Item B asserts bitwise `==` on iters/primal/dual/rho traces, welfare, dadp, `isequal` on NaN-bearing exact_maxgap, all four additive keys, price↔dadp consistency, BLAS restore. Canary pins intact: `test_admm_knifeedge_canary.jl` line 71 `@test r.iters == 56`, line 81 welfare `-4823.66604824162`; certified unchanged post-fix (5/5) |
| 3 | Solver/certificate error inside a parallel task surfaces with same error type and node attribution as serial | ✓ VERIFIED | Source: `throw(e.task.exception)` at the fetch site (admm_phases.jl line 253) — original exception object, never wrapper types; WR-01 reap-and-drain of in-flight tasks on join failure present in the `catch` (commit `3af9bec`, review addendum verdict "fix region verifies clean", frontmatter `status: clean`). Tests: Item C three legs — CertificateError (atol_exact=1e-30: type/msg/kind/iterations equal), ConvergenceError (messages embed residual traces), poisoned-AgrOpt task-body `SolveFailedError` under both executors with exact message parity and explicit `@test !(e3p isa TaskFailedException)`; leg 3 executes the new drain path directly (33/33 at -t 4 measured post-fix) |
| 4 | Run provenance records thread + BLAS-thread counts; executor choice leaves scenario `==`, `hash`, filename unchanged | ✓ VERIFIED | `src/experiments/store.jl` `result_to_dict`: `d[:julia_threads] = Threads.nthreads()` and `d[:blas_threads] = BLAS.get_num_threads()` (lines 207-208), placed immediately after `d[:julia_version]` (206) and AFTER the `_scenario_identity` call (196); grep confirms zero `parallel`/thread keys inside `_scenario_identity`/`_strategy_knobs` — identity is executor-blind. `test/test_experiments.jl` lines 324-326 assert key presence + live values on the wload'd dict, plus two Scenarios `==`, hash-equal and filename-identical |
| 5 | ADMM results expose per-aggregator dispatch, utilities, import profile, per-slot prices as additive keys; ~3.4 GiB unattributed IEEE-8500 memory profiled and attributed in a documented result | ✓ VERIFIED | `src/admm/admm_state.jl` `_agr_result_keys` (lines 460-473): agr_dispatch/agr_utility/agr_import/agr_prices as per-bus Dicts over ascending load_nodes; attached as TRAILING additive keys on `_admm_certify`'s return (admm_phases.jl lines 481-484), sign/layout conventions documented (agr_prices[j] == dadp bus-j row), price-consistency pinned by test. SCALE-06: `scripts/profile_ieee8500_memory_attribution.jl` (proc_status_kb line 70, staged GC/malloc_trim design, keyed CSV upsert, include-safe gate) + committed `results/ieee8500_benchmark/memory_attribution.csv` — T=10 fully reconciled (DSO build +0.408±0.05, 122 AgrOpt builds +1.724±0.172, first-iterate retained +1.370±0.137, iterates-2..8 retained +0.318±0.05, certify −0.100; total 3.720±0.237; **residual 0.620±0.237 GiB documented, not forced to a mechanism**), T=24 honest earlyoom-kill evidence row + build-only stage-2 rows (+0.922 DSO / +4.024 AgrOpt, ~2.3× T=10 for 2.4× T). `docs/literate/ieee8500_scaling.jl` dated Appended section (lines ~440-533) cites the CSV rows, states units (binary GiB), refutes the per-hour DSO hypothesis as dominant (~0.045 GiB/iter), and states what is NOT established (T=24 loop stages) |

**Score:** 5/5 truths verified

**Honest-outcome ruling (per verification brief):** SCALE-06's T=24 partial attribution and the T=10 `CertificateError` anchor refusal are VALID documented outcomes — the success criterion is "profiled and attributed in a documented result," which the committed CSV + doc note satisfy including honest residuals and an honestly recorded earlyoom kill. Not counted as gaps.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `.planning/spikes/005-clarabel-concurrency/sweep.jl` | Re-runnable spike: serial/threaded/direct_model legs + controls | ✓ VERIFIED | 18.8 KB; contains `Threads.@spawn` (line 223), production substrate `TSODSO._admm_build` (line 106), BLAS/MOI pinning, control ladder |
| `.planning/spikes/005-clarabel-concurrency/README.md` | Verdict + evidence per spike conventions | ✓ VERIFIED | `verdict: PASS` frontmatter; direct_model answer; controls; cites sweep.csv |
| `.planning/spikes/005-clarabel-concurrency/sweep.csv` | Recorded leg results | ✓ VERIFIED | 167 rows, real per-aggregator digests/metrics, verdict row |
| `.planning/spikes/MANIFEST.md` | Spike 005 registered | ✓ VERIFIED | Row 005 with ✓ PASS outcome (line 49) |
| `src/admm/solve_admm.jl` | `parallel::Bool` kwarg, 1-thread guard, BLAS save/restore, docstrings | ✓ VERIFIED | All present; guard message carries the restart instruction; Returns/Throws documented |
| `src/admm/admm_phases.jl` | Split AGR execute step + threaded join + additive certify keys | ✓ VERIFIED | `_agr_solve_step!` serves mid-loop AND certify re-solves; reap-drain (WR-01) present; agr_* keys trailing (481-484) |
| `src/admm/admm_state.jl` | Solve/apply split + `_agr_result_keys` | ✓ VERIFIED | `_react_agr_solve_only` (141/170) + `_react_agr_apply!` (214/226), composed by `_react_agr_solve!` (238-246) |
| `src/experiments/store.jl` | Additive provenance keys | ✓ VERIFIED | Lines 207-208, positioned after identity call |
| `test/test_admm_parallel.jl` | Guard / bitwise-equality / error-parity items | ✓ VERIFIED | 3 testitems; 2 thread-gated with loud `@test_skip` carrying the exact -t 4 invocation |
| `test/test_experiments.jl` | Provenance + executor-blind identity assertions | ✓ VERIFIED | Lines 324-326 + identity assertions |
| `test/expected_broken.txt` | Allowlisted thread-gated skips | ✓ VERIFIED | Exactly the 2 new `skipped` entries for test_admm_parallel.jl — matches the certified "7 broken = 5 pre-existing + 2 new" count |
| `test/test_admm_knifeedge_canary.jl` | Canary pins never re-pinned | ✓ VERIFIED | `iters == 56`, welfare `-4823.66604824162` with change-history comments |
| `scripts/profile_ieee8500_memory_attribution.jl` | Re-runnable staged attribution harness | ✓ VERIFIED | proc_status_kb / parse_kv_flag / staged design / keyed upsert / include-safe gate |
| `results/ieee8500_benchmark/memory_attribution.csv` | Committed attribution rows | ✓ VERIFIED | T=10 reconciliation (components + residual + tolerances), T=24 kill evidence + build-only rows; run-evidence files under runs/ |
| `docs/literate/ieee8500_scaling.jl` | Dated Appended doc note | ✓ VERIFIED | Cites `memory_attribution.csv` row keys, binary GiB units, per-hour-hypothesis refutation, not-established statements |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| spike README | sweep.csv | verdict cites recorded legs | ✓ WIRED | README lines 50/62/82/97/121 cite sweep.csv; verdict row present in CSV |
| sweep.jl | `src/admm/admm_state.jl _admm_build` | production fixture substrate | ✓ WIRED | `TSODSO._admm_build(...)` at line 106; observe-only (no src/ mutation) |
| test_admm_parallel.jl | src/admm/solve_admm.jl | direct solve_admm calls differing only in `parallel` | ✓ WIRED | Lines 103-104 (equality), 205/215, 237/247, 291 (parity legs); identical solve_kw derivation |
| admm_phases.jl threaded join | src/core/errors.jl TSODSOError types | `throw(e.task.exception)` unwrap | ✓ WIRED | Line 253; reap-drain precedes it in the catch |
| admm_phases.jl threaded entry | LinearAlgebra.BLAS + MOI.NumberOfThreads | BLAS=1 + per-model MOI=1, threaded only | ✓ WIRED | Lines 211-214; orchestrator-side finally restore in solve_admm.jl (445) |
| admm_phases.jl agr_prices | `_admm_certify` dadp key | agr_prices[j] == dadp bus-j row | ✓ WIRED | λ_mat assembly (467) + documented convention (453-456, 479-480) + test assertion |
| store.jl result_to_dict | `_scenario_identity` | keys added after identity call, never inside | ✓ WIRED | Identity at 196; keys at 207-208; identity functions grep-clean of executor keys |
| test_admm_parallel.jl | spike 005 README | PASS-gate provenance | ✓ WIRED | Line 111 `gate_artifact = ".planning/spikes/005-clarabel-concurrency/README.md"` |
| attribution script | profile_ieee8500_memory.jl idioms | proc_status_kb / staging / upsert | ✓ WIRED | proc_status_kb (70, 411, 453), parse_kv_flag, malloc_trim staging |
| attribution script + doc note | memory_attribution.csv / point_resources.csv | reconciliation targets | ✓ WIRED | CSV upsert path in script; doc note cites CSV rows and Phase-35 point_resources baselines |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| result_to_dict provenance | `d[:julia_threads]`/`d[:blas_threads]` | Live `Threads.nthreads()` / `BLAS.get_num_threads()` at save time | Yes (measured live; test asserts equality with live process values) | ✓ FLOWING |
| `_agr_result_keys` | st.a / st.util / st.p_import / λ_mat | Real AdmmState populated by the production solve path | Yes (populated by `_admm_iterate!`/`_admm_certify`; equality test reads them from real solves) | ✓ FLOWING |
| memory_attribution.csv | VmRSS/VmHWM staging | `/proc/self/status` + Sys.maxrss during real 8500 runs | Yes (T=10 anchor 4.339 GiB measured; T=24 MaxRSS 7.46 GiB kill evidence) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full suite green at HEAD | (withheld — orchestrator instruction: suite certified post-wave-4) | 32405 pass / 0 fail / 0 error / 7 broken (5 pre-existing + 2 allowlisted thread-gated skips), TEST_EXIT=0 | ✓ PASS (certified, not re-run) |
| Thread-gated equality + error parity at -t 4 | `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` | 33/33 pass, both legs iters=56 / welfare=-4823.66604824162 (REVIEW-FIX tier 3 + orchestrator re-certification post-WR-01) | ✓ PASS (certified, not re-run) |
| Canary after parallel items (dangerous ordering) | scratch same-process driver (parallel items first, canary after) | 32/32, BLAS restored, canary iters=56 / welfare=-4823.66604824162 | ✓ PASS (measured evidence in 39-04-SUMMARY) |
| Step 7b independent execution | — | Skipped: re-running the suite was explicitly prohibited by the verification brief; certification is at HEAD including the WR-01 fix | ? SKIP |

### Probe Execution

No conventional `scripts/*/tests/probe-*.sh` probes exist for this phase, and no PLAN declares one. The phase's runnable checks are the test suite and the measurement harness — covered under Behavioral Spot-Checks and the SCALE-06 CSV evidence. No MISSING_PROBE findings.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| PAR-01 | 39-02 | Opt-in concurrent aggregator subproblems; serial default byte-identical to v4.0 | ✓ SATISFIED | `parallel::Bool = false` kwarg + fail-loud guard (solve_admm.jl 310, 318-321); canary pins unchanged; serial branch = exact pre-existing loop |
| PAR-02 | 39-01, 39-04 | Threaded == serial (`==` iterations/residuals/welfare/prices) on multi-aggregator fixture; gated on documented spike | ✓ SATISFIED | Spike 005 PASS verdict + committed sweep.csv; Item B bitwise assertions; gate artifact cited in test |
| PAR-03 | 39-02, 39-04 | Parallel-task errors surface with serial's type and node attribution | ✓ SATISFIED | `throw(e.task.exception)` unwrap + reap-drain (WR-01 fixed, review clean); Item C three type/message-parity legs |
| PAR-04 | 39-03 | Provenance records thread + BLAS-thread counts; identity executor-blind | ✓ SATISFIED | store.jl 207-208 additive keys; identity/`==`/`hash`/filename untouched (grep-clean); pinned by test |
| PAR-05 | 39-04 | Per-aggregator dispatch, utilities, import profile, per-slot prices as additive keys | ✓ SATISFIED | `_agr_result_keys` + trailing certify keys + price↔dadp consistency test; pre-existing keys untouched (83/83 serial regression green) |
| SCALE-06 | 39-05 | ~3.4 GiB unattributed IEEE-8500 memory profiled and attributed, result documented | ✓ SATISFIED (honest outcome) | memory_attribution.csv: T=10 components + 0.620±0.237 GiB documented residual; T=24 honest earlyoom kill + build-only attribution; dated doc note |

No orphaned requirements: all six IDs mapped to Phase 39 in REQUIREMENTS.md are claimed by exactly one plan each; no plan claims IDs outside this phase.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (all 8 phase files scanned) | — | Debt markers TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER | — | None found |
| (src/admm/*, src/experiments/store.jl) | — | Stub returns / not-implemented markers | — | None found |
| `@test_skip` × 2 (test_admm_parallel.jl) | 77, 167 | Thread-gated skips in the default 1-thread suite | ℹ️ Info | Intentional, allowlisted in expected_broken.txt with exact keys and the exact -t 4 invocation in the skip message; surfaced as human-verification item 1 |
| admm_phases.jl catch | ~245 | Commented deliberate empty catch (reap-and-discard of drained-task failures) | ℹ️ Info | Reviewed and accepted in the WR-01 fix loop; failures are superseded by the first error, nothing swallowed on the happy path |

Code review status: **clean** (39-REVIEW.md frontmatter, post-addendum; WR-01 resolved at `3af9bec`; 0 critical / 0 warning / 8 info outstanding, info tier non-blocking). One recorded out-of-scope observation (apply-side throw after a successful fetch can still abandon tasks idx+1..n) predates this phase's fix and is correctly documented as pre-existing. Git tree clean at HEAD `eebbc03`; all phase commits present.

### Human Verification Required

### 1. Researcher opt-in reproduction at -t 4 (UAT of the phase's core user story)

**Test:** `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'`
**Expected:** All items pass — bitwise serial-vs-threaded equality (both legs iters=56, welfare=-4823.66604824162), all three error-parity legs identical type+message, no wrapper exception types.
**Why human:** The two binding thread-gated items are allowlisted skips in the certified default 1-thread suite, so the 32405-pass certification never executed them; threaded determinism is host-dependent (BLAS backend, core count) and the phase goal's subject — "a researcher can opt in" — is exactly this command on the researcher's own machine. Executor and fix-loop measured 33/33 at -t 4, so this is confirmation, not discovery.

### 2. T=24 full attribution point — complete or accept the honest record (optional, resource decision)

**Test:** On a host with ~12 GiB genuinely available at launch: `julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 24`
**Expected:** T=24 loop-stage attribution rows land in memory_attribution.csv; or the Phase-35 standing figures (11.52 GiB peak / 10.17 GiB loop delta) are accepted as the T=24 record into the Phase-40 scaling report.
**Why human:** SCALE-06 is satisfied by the documented honest outcome; whether to spend host resources completing T=24 loop stages now (the 15.5 GiB host was too busy at launch, earlyoom killed at 7.46 GiB MaxRSS) is a scheduling decision, not a code property.

### Gaps Summary

No gaps. All 5 roadmap success criteria verified against the codebase at all levels: artifacts exist, are substantive (no stubs, no debt markers), are wired (every key link traced in source), and real measured data flows through them (committed spike.csv with 167 measured rows; committed memory_attribution.csv with measured RSS staging; live-measured provenance keys). The default serial path's byte-identity is guarded by the unchanged canary pins (`iters == 56`, `welfare = -4823.66604824162`), and the threaded executor is correctly gated behind spike 005's documented PASS.

Status is `human_needed` solely because the phase's core behavioral proof (threaded equality/error-parity) lives in two thread-gated test items that the certified default suite skips by design — the researcher should run the one-line -t 4 reproduction on their own machine (item 1), and may take or defer the optional T=24 completion decision (item 2). The full suite was certified green at HEAD including the WR-01 fix (33/33 parallel items at -t 4, canary 5/5 unchanged); nothing here contradicts that certification.

---

_Verified: 2026-10-24T11:10:00Z_
_Verifier: the agent (gsd-verifier)_
