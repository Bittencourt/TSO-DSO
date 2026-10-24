---
phase: 39-parallel-ready-admm-gating-measurements
reviewed: 2026-10-24T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - docs/literate/ieee8500_scaling.jl
  - scripts/profile_ieee8500_memory_attribution.jl
  - src/admm/admm_phases.jl
  - src/admm/admm_state.jl
  - src/admm/solve_admm.jl
  - src/experiments/store.jl
  - test/expected_broken.txt
  - test/test_admm_parallel.jl
  - test/test_experiments.jl
findings:
  critical: 0
  warning: 1
  info: 8
  total: 9
status: clean
---

# Phase 39: Code Review Report

**Reviewed:** 2026-10-24
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 39 delivers the opt-in threaded AGR executor (`parallel` kwarg threading through `solve_admm` → `_admm_iterate!` → `_admm_certify` → `_agr_solve_step!`), the task-safe solve/apply grain split in `admm_state.jl`, the PAR-05 additive per-aggregator result keys, the PAR-04 process thread-count provenance keys in `result_to_dict`, the SCALE-06 memory-attribution harness, and the thread-gated test file with its `expected_broken.txt` allowlist entries.

The core concurrency design holds up under adversarial tracing. The solve/apply grain split is genuinely clean: `_react_agr_solve_only` reads only per-`j` / loop-invariant state (`λ[j]`, `c[j]`, `μq[j]`, `d[j]`, `ρ_qf`) and mutates only its own AgrOpt JuMP model; every `st`/`ls` write (`st.a`, `st.util`, `ls.b`) stays in the serial join region, and the serial writes that tasks' reads depend on (dual step, ρ adaptation) all happen strictly after the join completes — no read/write overlap exists between task bodies and the serial region. The composed `_react_agr_solve!` preserves the original write order, so the serial default path is statement-for-statement identical (golden policy respected; canary untouched). The fetch-in-`load_nodes`-order join with `TaskFailedException` unwrap gives serial's first-throw attribution with the original exception object, and no `@sync`/`CompositeException` anywhere. The fail-loud 1-thread guard fires before any build. BLAS state is snapshotted before the loop and restored in a `finally` covering all exit paths. `expected_broken.txt` entries were verified against the runner's exact-key matching (`runner_support.jl` `record_key`/`read_expected_broken`) — item names, file basenames, and the literal skip-message `test` fields all match the test file verbatim. The profiler's reconciliation arithmetic, unit conversions (`Sys.maxrss()` is bytes on Linux; `/proc` KiB ÷ 2^20 → GiB), tolerance model (quadrature sum), and the docs page's quoted figures are internally consistent (checked: 0.408/1.724/1.370/0.318/−0.100 → Σ 3.720, residual 0.620, tol 0.237; T-scaling ratios 2.26/2.33; all KiB→GiB conversions). The profiler's `AdmmState`/`_admm_iterate!`/`_admm_certify`/`_agr_solve_step!` call shapes all match the current source signatures; the ledger-reset bookkeeping (`st.residuals.iters = 0`) is safe because `converged` uses `last(trace)`, and it is honestly documented as an iteration undercount.

One Warning (abandoned in-flight tasks on the first-failure join — resource leak on the opt-in error path, no result corruption) and eight Info items.

## Warnings

### WR-01: First-failure join abandons in-flight tasks — unawaited solver runs leak past the throw

**File:** `src/admm/admm_phases.jl:230-241`
**Issue:** When the fetch-in-order join hits the first failed task, `throw(e.task.exception)` exits the loop while tasks `idx+1..length(load_nodes)` are still running (or queued). They are never cancelled, fetched, or waited: up to `n_aggregators − 1` Clarabel solves keep executing after `solve_admm` has already thrown — and after the `finally` has restored `BLAS.set_num_threads(blas0)`. Their results are silently discarded. There is no correctness impact (task bodies touch only their own models, so no race with the caller's recovery), but on the opt-in path every error exit leaks a phantom iteration's worth of solver work: CPU contention with whatever the caller does next (catch-and-retry, a subsequent scenario run), invisible to any caller-facing signal. At IEEE-8500 scale (122 aggregators, minutes per AGR solve) this is minutes of wasted multithreaded compute per failure; it also makes latency after a caught `SolveFailedError`/`CertificateError` nondeterministic. This is a resource/state-management gap, not a parity violation — attribution is still serial-correct.
**Fix:** Drain the remaining futures before propagating, preserving the first failure in `load_nodes` order:

```julia
local first_err = nothing
for (idx, j) in enumerate(load_nodes)
    if first_err === nothing
        r = try
            fetch(futs[idx])
        catch e
            first_err = e isa TaskFailedException ? e.task.exception : e
            nothing
        end
        first_err === nothing && _react_agr_apply!(rmode, st, j, r; final = final)
    else
        try
            fetch(futs[idx])   # drain: reap in-flight work, discard results/errors
        catch
        end
    end
end
first_err === nothing || throw(first_err)
```

(Alternatively `wait`-drain on the error path only, to keep the happy path byte-identical.) Note the empty `catch` here is a deliberate reap-and-discard and deserves a comment saying so, to avoid tripping the project's empty-catch audit.

## Info

### IN-01: Executor-entry pinning repeats on every call, comment says "ONCE per call"

**File:** `src/admm/admm_phases.jl:209-213`
**Issue:** `BLAS.set_num_threads(1)` plus the `MOI.NumberOfThreads() = 1` loop over all AGR models run on every `_agr_solve_step!` invocation — i.e., once per ADMM iteration plus the certify re-solve — while the comment reads "Executor entry, ONCE per call". Idempotent and cheap relative to solve cost, but it is O(n_aggs) redundant MOI writes per iteration (≈7k for the 122-aggregator/56-iterate canary-scale run) and the comment's "per call" is easy to misread as "per `solve_admm`".
**Fix:** Either hoist both pins to a once-per-`solve_admm` seam (e.g., a flag in `AdmmState` or executor setup right after `_admm_build`), or reword the comment to "ONCE per `_agr_solve_step!` call (i.e., per iteration; idempotent)".

### IN-02: `blas0` conditionally assigned (soft local) couples two `if parallel` sites

**File:** `src/admm/solve_admm.jl:357-359` and `443-446`
**Issue:** `blas0` is assigned only under `if parallel` and read only under `if parallel` in the `finally`. Correct at runtime, but the correctness depends on two distant conditionals staying in sync; a future edit that reads `blas0` unconditionally in the `finally` would throw `UndefVarError` on the serial path.
**Fix:** `blas0 = parallel ? BLAS.get_num_threads() : nothing` (or take the snapshot unconditionally — one cheap call) so the restore site can be unconditional too.

### IN-03: Docstring signature sketch shows a stale `reactive_consensus` default

**File:** `src/admm/solve_admm.jl:60` (vs. `:305`)
**Issue:** The docstring's signature sketch still shows `reactive_consensus = ReactiveMode.OFF`, but the actual keyword default is the smart default `_default_reactive_consensus(aggregators)` (and the prose at lines 104-110 documents the smart default correctly). Pre-existing staleness inside a docstring this phase edited heavily; a reader skimming only the sketch gets the wrong default.
**Fix:** Update the sketch line to `reactive_consensus = _default_reactive_consensus(aggregators)`.

### IN-04: Equality testitem never asserts convergence before the bitwise comparisons

**File:** `test/test_admm_parallel.jl:115-126`
**Issue:** The bitwise-equality item compares `iters`/traces/welfare/dadp without first asserting `r1.status == :converged && r2.status == :converged`. Today this cannot spuriously pass (no `time_limit_s` is passed, so the `:budget_exceeded` path cannot fire, and non-convergence throws) — but the guarantee is incidental to the fixture list, not enforced by the test. A one-line status assertion makes the equality bar self-validating if kwargs ever change.
**Fix:** Add `@test r1.status == :converged` and `@test r2.status == :converged` before the field comparisons.

### IN-05: `--stage` gating: stage 2 always runs; no lower-bound validation

**File:** `scripts/profile_ieee8500_memory_attribution.jl:98, 135, 148-185`
**Issue:** Only the anchor and the stages 3-5 block are gated on `max_stage >= 3`; the stage-2 builds run unconditionally. So `--stage 1` (or `--stage 0`) still executes the full DSO + AgrOpt builds, and `--stage` accepts any integer without a `>= 1` check. The committed T = 24 evidence was correctly produced with `--stage 2`, but the flag's semantics ("builds always run") are undocumented and surprising.
**Fix:** Gate the stage-2 block on `max_stage >= 2` (or document that stage 2 is unconditional) and validate `max_stage >= 1` at parse time alongside the `--max-bounded-iters` guard.

### IN-06: Reconciliation console table prints `+` before negative components

**File:** `scripts/profile_ieee8500_memory_attribution.jl:578-589`
**Issue:** The per-component console lines hardcode a leading `"+"`, so a negative component (e.g., `comp_certify = −0.100` at T = 10) renders as `"+-0.1"`. Cosmetic only — the CSV rows carry the raw signed value — but it is exactly the kind of output pasted into evidence notes.
**Fix:** Use a signed format, e.g. `Printf.@printf("  %-26s %8.3f ± %.3f GiB   %s\n", nm, c, comp_tol(c), note)`.

### IN-07: Header overstates cap-sensitivity of `iter_*` row names

**File:** `scripts/profile_ieee8500_memory_attribution.jl:17-18`
**Issue:** The header says rows from a run with a different `--max-bounded-iters` "leave differently-named `iter_*` rows behind", but only `iter_$(n_bounded)` is cap-named; `iter_before_gc`, `after_first_optimize_gc`, and `iter_after_gc` are fixed-name and get upsert-replaced. A cap-mismatched re-run therefore leaves one stale cap-named row beside the new run's fixed-name rows — a mixed-provenance evidence file. Reconciliation stays correct (`rss_gib_of` reads only the current run's `ROWS`), and the header does say "re-run with the same cap to replace them", but the mechanism description is imprecise.
**Fix:** Reword to "leaves the cap-named `iter_N` row of the old cap behind; fixed-name stage-3/4 rows are replaced", or fold the cap into all `iter_*` row names.

### IN-08: Staged iteration 1 runs without the wall-clock budget check

**File:** `scripts/profile_ieee8500_memory_attribution.jl:233-245` (vs. `:262-275`)
**Issue:** The isolated iterate-1 `_admm_iterate!` call passes `time_limit_s = nothing`; only the continuation passes the budget. Production `solve_admm` applies the budget from iteration 1 (`t0` is set in `_admm_build`), so a staged iterate-1 that alone exceeds the budget would not latch `budget_exceeded_flag` where the anchor would. The solve statements are identical (as the header claims), but the budget-check semantics of the split block differ subtly from the production sequence. Measurement-only divergence; worth a header sentence, not a correctness fix.
**Fix:** Pass `time_limit` to the iterate-1 call as well (the state's `t0_wall_ns` is already set at construction, so the elapsed accounting stays correct), or note the divergence in the file header next to the ledger-reset paragraph.

---

**Verification notes (no findings):** the serial default path is statement-identical (composed `_react_agr_solve!` preserves the original solve-then-write order; all Phase-39 additions to `solve_admm` are flag-gated no-ops when `parallel = false`); the canary file and tolerances are untouched by this diff; `expected_broken.txt` entries match the runner's exact `(kind, file, item, test)` key semantics including the em-dash-containing skip messages; `has_4q_by_bus` gating on `final` is race-free (Dict built before spawn, read-only in tasks); `agg_prices[j] == dadp[row_of_j, :]` holds exactly (both are `−λ[j]`); the budget-exit NamedTuple correctly omits the PAR-05 keys as documented; `run(::ADMM, s)` reads named fields, so the trailing result keys break no consumer; `store.jl` thread keys are measured live, executor-blind, and excluded from scenario identity as tested.

_Reviewed: 2026-10-24_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_

---

## Addendum: Fix Verification — WR-01 (fix loop 1/3)

**Fix commit:** `3af9bec` ("fix(39): reap-and-drain in-flight AGR tasks on join failure (WR-01)")
**Verified against:** parent `d6e780c`; working tree clean at HEAD `d556a27`
**Verdict:** **fix region verifies clean** — frontmatter `status` set to `clean`. WR-01 resolved; no new findings. Info items IN-01..IN-08 remain outstanding (info tier, non-blocking). Original counts above are the historical record of the first-pass review (0 critical / 1 warning / 8 info); post-fix outstanding: 0 critical / 0 warning / 8 info.

### 1. Drain loop cannot throw or shift attribution vs serial — CONFIRMED

`src/admm/admm_phases.jl:241-248`. The drain range `(idx + 1):length(futs)` is pure arithmetic (cannot throw) and always in-bounds: `idx ≤ length(futs)` since `length(futs) == length(load_nodes)`, and the range is empty when the last task failed. `futs[k]` indexing and `wait` sit inside the `try`; the bare `catch` discards everything, so the drain loop is throw-proof and control always reaches the PAR-03 unwrap/rethrow with `e` intact. Attribution parity holds: in serial, tasks after the first failing `j` never execute, so their (possibly different) failures are unobservable — discarding drained results/errors reproduces serial's first-throw semantics exactly, and the surfaced exception is still the original object (`e.task.exception`). The inner bare catch does not disturb the outer `rethrow()` target (the inner handler is popped when its try/catch completes normally) and does not rebind `e`. Only nuance: an `InterruptException` landing inside the bounded drain window is discarded per the documented reap-and-discard semantics; the original error still surfaces — accepted, not a defect.

### 2. Success path untouched — CONFIRMED

`git diff -U0 d6e780c..HEAD -- src/admm/admm_phases.jl` contains exactly two hunks: `@@ -184 +184,3 @@` (docstring prose only, no code) and `@@ -233,0 +236,13 @@` (pure addition inside `catch e`, before the existing PAR-03 line). The serial branch, executor entry (`BLAS.set_num_threads` / MOI pinning), spawn block, `fetch(futs[idx])`, and `_react_agr_apply!` call are byte-identical to the pre-fix state.

### 3. No new concurrency hazard — CONFIRMED

No double-wait: Julia `Task`s are re-awaitable, and each future is observed at most once here — success path uses only `fetch`; error path `wait`s `idx+1..n` exactly once. No deadlock: the task at `idx` has already completed (that is why `fetch` threw), tasks `1..idx−1` completed via earlier fetches, and an already-failed future makes `wait` throw immediately rather than block. The joiner holds no lock the task bodies need (bodies are self-contained solves on their own AgrOpt models per the grain-split contract), so all in-flight tasks make progress and the drain terminates. Drain-before-rethrow leaves no unobserved task behind.

**Out-of-scope observation (pre-existing, unchanged by `3af9bec`, not re-classified):** if `_react_agr_apply!` itself throws after a successful fetch, tasks `idx+1..n` are still abandoned — that throw exits outside the fetch's catch. This predates the fix (commit `1af3dda`), is unchanged by it, and belongs to the apply/write error class rather than the WR-01 join-drain scope.

_Verified: 2026-10-24 (fix loop 1/3, region-only re-review of `src/admm/admm_phases.jl` @ `3af9bec`)_
