---
phase: 39-parallel-ready-admm-gating-measurements
plan: 04
subsystem: admm
tags: [threads, parallelism, admm, bitwise-equality, error-parity, par-02, par-03, par-05, expected-broken]

# Dependency graph
requires:
  - phase: 39-01 (Clarabel concurrency spike)
    provides: spike 005 PASS verdict — the documented gate the equality items echo as provenance
  - phase: 39-02 (threaded executor)
    provides: the opt-in `parallel` executor, fail-loud guard, TaskFailedException-unwrap join this plan proves behaviorally
provides:
  - "PAR-02 behavioral proof: threaded == serial BITWISE (iters, primal/dual/rho traces, welfare, dadp, all four additive keys) on the 10-aggregator IEEE-13 minimal scenario at JULIA_NUM_THREADS=4 — measured 56 / -4823.66604824162 on BOTH legs"
  - "PAR-03 behavioral proof: CertificateError, ConvergenceError and task-body (poisoned-AgrOpt) errors surface with the SAME type and EXACT same message under both executors; threaded error is never TaskFailedException/CompositeException"
  - "PAR-05: per-aggregator additive keys agr_dispatch/agr_utility/agr_import/agr_prices on the certified result (trailing; pre-existing keys untouched), with the price-consistency property agr_prices[j] == dadp row of j pinned by test"
  - "test/test_admm_parallel.jl: 1-thread-safe guard item + two thread-gated items with loud @test_skip and exact-key expected_broken.txt allowlist entries (1-thread suite green: 4 pass / 2 allowlisted skips)"
  - "BLAS-leak protection evidence: canary holds its pins (56 / -4823.66604824162) in the same process AFTER the parallel items under the dangerous ordering (measured via a scratch same-process driver, 32/32)"
affects: [phase 40 POP-05 scaling report (consumes the additive keys + the equality proof), SCALE-06 memory attribution, any threaded solve_admm caller]

# Tech tracking
tech-stack:
  added: []
  patterns: ["thread-gated test items: loud @test_skip carrying the exact JULIA_NUM_THREADS=4 invocation + exact-key expected_broken.txt allowlist (an unlisted skip fails the run)", "bitwise field-wise equality on the certified result: literal == on Float64 traces/welfare/prices, isequal only for the NaN-bearing exact_maxgap, never the whole mutable NamedTuple", "same-process dangerous-order verification: scratch TestItemRunner driver running parallel items first, canary after (the committed combined command's walk order puts the canary first — measured fact)"]

key-files:
  created:
    - test/test_admm_parallel.jl
  modified:
    - src/admm/admm_state.jl
    - src/admm/admm_phases.jl
    - src/admm/solve_admm.jl
    - test/expected_broken.txt

key-decisions:
  - "agr_import keyed to the SHARED root frontier profile: st.p_import is the single network-level exchange at feeder.root (there is no per-bus import decomposition in AdmmState) — every aggregator maps to that per-slot profile, documented at _agr_result_keys"
  - "Leg-3 poison = contradictory constraint pair on ONE aggregator's pag (deterministic INFEASIBLE → SolveFailedError under both executors); the bus-naming battery/4Q certificate poisons were probed and are UNREACHABLE — the PV-limited charge bound (thesis 3.7/A6) makes forced co-charge INFEASIBLE at the solve gate before any certificate fires, so attribution parity is proven by exact message equality instead"
  - "Equality-item comments phrased to keep the anti-pattern grep literal: zero isapprox tokens in test_admm_parallel.jl (39-02 precedent)"
  - "Skip records allowlisted by exact key with the expression as a single-line string literal, so stringified orig_expr is stable and grep-friendly"

requirements-completed: [PAR-02, PAR-03, PAR-05]

# Metrics
duration: 40min
completed: 2026-10-24
---

# Phase 39 Plan 04: Parallel-Ready ADMM Equality, Error Parity & Additive Keys Summary

**Bitwise serial-vs-threaded equality proven on the 10-aggregator IEEE-13 fixture at -t 4 (both legs 56 / -4823.66604824162), error parity proven for CertificateError/ConvergenceError/poisoned-task errors with no wrapper types, and per-aggregator additive result keys (agr_dispatch/agr_utility/agr_import/agr_prices) exposed on the certified result — the default serial path and the knife-edge canary untouched (canary green in the same process AFTER the parallel items).**

## Performance

- **Duration:** 40 min
- **Started:** 2026-10-24T07:16:51Z
- **Completed:** 2026-10-24T07:57Z
- **Tasks:** 3
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **PAR-05 (Task 1):** `_agr_result_keys(st)` in `admm_state.jl` — per-bus `Dict`s keyed over ascending `load_nodes`, modeled on the `_react_outputs` precedent, ALWAYS populated at certify time (every reactive mode); attached as TRAILING additive entries on `_admm_certify`'s return NamedTuple. Documented sign/layout conventions: `agr_prices[j]` equals the bus-j `dadp` row (`λ_mat = −λ`); `agr_import` keys to the shared root frontier profile (`st.p_import` is network-level, not per-bus). solve_admm's Returns docstring + `_admm_certify` docstring updated (no docstring content-loss hazards). Serial regression: test_admm_phases.jl + test_admm.jl 83/83 green without edits.
- **PAR-02 + guard (Task 2):** `test/test_admm_parallel.jl` Item A (1-thread-safe, always runs): `parallel = true` at 1 thread throws ArgumentError; multi-threaded the guard is silent and the solve converges. Item B (thread-gated, loud `@test_skip` with the exact 4-thread invocation): two IDENTICAL `solve_admm` calls differing only in `parallel`, asserted field-wise BITWISE (`iters`, `primal_trace`, `dual_trace`, `rho_trace`, `welfare`, `dadp`, `isequal` on the NaN-bearing `exact_maxgap`, all four additive keys) plus `agr_prices[j] == dadp[i, :]` and a BLAS thread-count restore assertion inside save/finally-restore hygiene. **Measured at JULIA_NUM_THREADS=4: 17/17 pass; both legs bitwise-equal at the canary values (iters 56, welfare -4823.66604824162); pre-assertion @info echoes the spike-005 PASS verdict + artifact path.** 1-thread run green: 4 pass / 1 allowlisted skip.
- **PAR-03 (Task 3):** Item C (thread-gated): three legs comparing serial vs threaded errors — CertificateError leg (`atol_exact = 1e-30`: type, msg, kind, iterations all equal), ConvergenceError leg (`maxiter = 1`, tight ε: equal types + equal messages, and the messages embed the residual traces), and the task-body unwrap leg (fresh `_admm_build` poisoned on bus 3's `pag`; `SolveFailedError` under BOTH executors with exact message parity; explicitly NOT TaskFailedException/CompositeException). **Measured at -t 4: all three legs type-parity.** expected_broken.txt carries both exact-key skipped lines; 1-thread run green (4 pass / 2 allowlisted skips).
- **Canary protection (T-39-04-02):** the committed combined command (`JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl,test_admm_knifeedge_canary.jl`) is green 35/35 with the canary pins unchanged — but MEASURED FACT: TestItemRunner's walk order runs the canary file FIRST there, so a scratch same-process driver (parallel items first, canary after — the dangerous ordering) was run additionally: **32/32, BLAS restored to its pre-run value (2), canary AFTER the parallel items still hits iters = 56, welfare = -4823.66604824162.**

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-aggregator additive result keys (agr_dispatch / agr_utility / agr_import / agr_prices)** - `4d6755f` (feat)
2. **Task 2: test_admm_parallel.jl — guard item + bitwise equality item with BLAS hygiene** - `e3517fd` (test)
3. **Task 3: Error-parity item + expected_broken entries + canary-after-parallel check** - `4e6d65b` (test)

## Files Created/Modified

- `src/admm/admm_state.jl` — `_agr_result_keys(st)`: the four per-bus snapshot Dicts + sign/layout convention comments
- `src/admm/admm_phases.jl` — the four TRAILING keys on `_admm_certify`'s return + docstring note
- `src/admm/solve_admm.jl` — Returns docstring gains the additive keys (converged path only)
- `test/test_admm_parallel.jl` — NEW: guard item, bitwise equality item, error-parity item (tags `[:admm, :parallel]`, `setup = [ExperimentHarnessFixtures]`, explicit `using TSODSO`)
- `test/expected_broken.txt` — two exact-key `skipped` lines (Items B and C), one per thread-gated item

## Decisions Made

- `agr_import` semantics: the plan said "read the actual layout of `st.p_import` … do not guess the orientation" — the actual layout is a flat length-T vector (the DSO's single free-sign frontier exchange at `feeder.root`), so every aggregator is keyed to that shared per-slot profile; the honest reading is documented at the helper and in this summary rather than fabricating a per-bus decomposition.
- Leg-3 poison selection: measured probes showed the bus-naming battery-certificate poison (force `p_ch`/`p_dch` co-charge) is unreachable — three variants (pmax/pmax, pmax/1e-5, net-neutral η_c·pmax) all die INFEASIBLE at the solve gate because charging is PV-limited (`p_ch[t] ≤ pv_used[t]`, thesis 3.7/A6). Used the plan's own fallback ("pick the poison that throws in serial too"): contradictory constraints on `pag[1]` → deterministic `SolveFailedError`; attribution parity proven by EXACT message equality (the multi-line solver-status block).
- Equality-item comments reworded so the file contains ZERO `isapprox` tokens (the anti-pattern grep stays literal; 39-02 precedent).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The committed canary-after-parallel command cannot exercise the dangerous order**
- **Found during:** Task 3 verification
- **Issue:** TestItemRunner's `run_tests` walks `test/` in directory order, which (measured) places `test_admm_knifeedge_canary.jl` BEFORE `test_admm_parallel.jl` — the combined command is green but the canary runs first, so the "canary after parallel items in the same process" acceptance was not actually exercised by it. (Noted en passant: the runner `cd`s into each item's directory while evaluating it, which is exactly why a LOAD_PATH-stacked scratch driver must use `@` not `.` for the active project — the documented cwd hazard.)
- **Fix:** additional same-process scratch driver (in /tmp/opencode, deliberately uncommitted): `TestItemRunner.run_tests` twice in one process — parallel items first, canary second — under `JULIA_NUM_THREADS=4` with the repo's Phase-29 stacked-LOAD_PATH idiom (`JULIA_LOAD_PATH="test:@:@stdlib"`, no Pkg mutation; env verified clean afterwards). Result: 32/32 pass, BLAS restored (2), canary pins unchanged (56 / -4823.66604824162) AFTER the parallel items. The committed verify command remains as planned and is green; the ordering caveat is recorded here as a measured environment fact.
- **Files modified:** none in the repo (verification-only evidence)
- **Verification:** scratch driver output 32/32; `git status` clean on test/Manifest.toml and test/Project.toml after the run

---

**Total deviations:** 1 auto-fixed (verification-order blocker; no src/test scope change)
**Impact on plan:** the acceptance's INTENT (same-process canary-after-parallel BLAS-leak protection) is proven; no scope creep.

## Issues Encountered

- The plan's leg-3 sketch "(bus j named in the message)" is not reachable with any deterministic poison found (see Decisions Made); the shipped leg proves the binding PAR-03 claims (same type, exact same message, no wrapper types) via the `SolveFailedError` poison. Documented in the test file's poison note for future readers.
- `Pkg.test()` runs each selection in a subprocess, so "same process" ordering verification required the LOAD_PATH-stacked scratch driver instead of two `Pkg.test` calls.

## Known Stubs

None — no placeholder/stub patterns in the created/modified files; all four additive keys are fully wired and populated at certify time, and all test items are live (skips are thread-gating, not stubs).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 40's POP-05 scaling report can consume the additive keys (`agr_dispatch`/`agr_utility`/`agr_import`/`agr_prices`) and cite this plan's equality proof as the executor-trust gate; Scenario-level `parallel` wiring remains Phase 40's deliberate concern (kwarg-only here, executor-blind identity intact).
- SCALE-06 memory attribution can reuse the executor + keys as planned (sequencing per CONTEXT.md).
- The 1-thread default suite and CI stay on the serial path: the two thread-gated items skip loudly with exact-key allowlisted records; the 4-thread leg is invoked via the documented targeted command.

## Self-Check: PASSED

- All 5 files exist on disk (4 modified + test/test_admm_parallel.jl created)
- SUMMARY.md exists in the phase directory
- All 3 task commits found in git log: 4d6755f, e3517fd, 4e6d65b
- Verification evidence: 1-thread targeted run 4 pass / 2 allowlisted skips (green); -t 4 combined run 35/35 (bitwise equality, all three error-parity legs type-parity, canary pins unchanged); serial regression 83/83 after the additive keys; same-process dangerous-order driver 32/32 with canary pins unchanged after the parallel items; zero isapprox tokens in test_admm_parallel.jl
