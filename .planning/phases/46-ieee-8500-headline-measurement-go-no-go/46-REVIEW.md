---
phase: 46-ieee-8500-headline-measurement-go-no-go
reviewed: 2026-11-06T11:45:24Z
iteration: 2
depth: standard
files_reviewed: 11
files_reviewed_list:
  - scripts/ieee8500_scenario_point.jl
  - scripts/run_ieee8500_point.sh
  - scripts/README.md
  - test/test_ieee8500_scenario.jl
  - docs/literate/ieee8500_scaling.jl
  - src/experiments/materialize.jl
  - .planning/research/STACK.md
  - results/ieee8500_benchmark/scenario_table.csv
  - results/ieee8500_benchmark/point_resources.csv
  - results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time
  - results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.free_before
findings:
  critical: 1
  warning: 4
  info: 6
  total: 11
status: issues_found
---

# Phase 46: Code Review Report (iteration 2)

**Reviewed:** 2026-11-06T11:45:24Z
**Iteration:** 2 (iteration 1 is kept as `46-REVIEW.iter1.md`)
**Depth:** standard, plus cross-file checks:
- `src/core/errors.jl` and `src/admm/` catch sites;
- `scripts/profile_ieee8500_memory_attribution.jl` anchor logic;
- the docs section `## Headline measurement and go/no-go` executed standalone against the committed CSVs.

**Files Reviewed:** 11
**Status:** issues_found

## Summary

Scope: `git diff f60857e..HEAD`, which covers the iteration-1 fix commits plus the orchestrator's 2026-11-06 re-run of the T = 10 point (commit `02d8857`). Known and out of scope: repo-wide formatter drift, and the 2 pre-existing script-API-lint findings in `scripts/profile_ieee8500_memory_attribution.jl`.

### Verification of the iteration-1 findings

| ID | Verdict | Basis |
|---|---|---|
| CR-01 heap hint | **Resolved in code and data; the docs regressed (see CR-01 below)** | The row records `Int(Base.JLOptions().heap_size_hint)` = 8589934592. The new `.time` command line shows `julia --heap-size-hint=8G`. On Julia 1.12.5 I checked that `--heap-size-hint=8GB/8.5G/50%` parse as expected. |
| CR-02 key/attempt | **Resolved as specified; residual risk WR-01** | Traced the `upsert_rows!` rules. A transient row replaces only older transient rows. A final row replaces every row of its key. Old-schema tables key on `"missing"` consistently. The `_key` stringification agrees between Int and CSV-read values. |
| WR-01 atomic write | **Resolved** | Same-directory temp file, then `Base.Filesystem.rename`, which exists on 1.10, 1.11 and 1.12. The test does not exercise the cleanup path (IN-04). |
| WR-02 in-process failures | **Resolved; residual WR-04** | `OutOfMemoryError` is final. `crashed:*` is transient. No TSODSO catch site wraps an OOM into a `TSODSOError`: `admm_phases.jl:306` rethrows the original, and `solve_admm.jl:549` re-wraps only `CertificateError`. |
| WR-03 certify iters/timing | **Resolved for certify; the same defect remains in the solve phase (WR-03)** | Reasoning below. |
| WR-04 B2 host total | **Resolved** | B2 is recomputed from `runs/p39-attr-d0.1-T24.free_before` (15396 MiB) and asserted at rtol 1e-9. The page prints 13.324 GiB. |
| WR-05 verdict uses max | **Resolved; a boundary nit remains (IN-03)** | Reasoning below. |
| WR-06 counter-fact | **Resolved; predicate nit (IN-02)** | Head run: `rc == 0`. Anchor: `iters > 0`. A missing killed row throws. |
| WR-07 compile time | **Resolved** | `cumulative_compile_timing` is a re-entrant counter (enable increments, disable decrements), so the on/off pair is safe under nested `@time`. The page prints a 15.3 % compile share. |
| WR-08 status branches | **Resolved except `error:<Type>` (IN-05)** | `refused_certificate` is pinned to `solve_admm`'s own `CertificateError.iterations` and ratio. `convergence_error` is pinned to `run_scenario`. `budget_exceeded` is covered. |
| WR-09 pre-flight before load | **Resolved in code; the docs prose regressed (CR-01)** | `MEMAVAIL_AT_START_KB` is read with Base only, before `using DrWatson`. There is no `~/.julia/config/startup.jl` on the host, so the claim "before any package load" holds. |

#### WR-03: certify iterations and timing

**How the certify path behaves now.** Take a non-certificate `TSODSOError` raised inside `_admm_certify`:
1. The inner `catch` rethrows it.
2. Before the rethrow reaches the outer `catch`, the inner `finally` (`:829-833`) records `t[:certify]`, `tc[:certify]` and the `:certify` VmHWM sample.
3. `loop_done` was set at `:805`, only after `_admm_iterate!` returned. So the outer `catch` (`:864-870`) takes `st.residuals.iters`, which is the converged count, not -1.
4. `hasproperty(err, :iterations)` comes first. A `CertificateError` or `ConvergenceError` that carries its own count therefore keeps it.

**Correct for certify.** The same reasoning shows the fix was not applied to the solve phase (WR-03 below).

#### WR-05: the verdict uses the larger peak

- **Script.** `b1 = kb_to_gib(max(vmhwm_kb, p35_kb))`, then `b1 > threshold_gib || throw` (`:554-570`).
- **Docs.** The docs use the same `max` (`:647-648`) and `@assert (verdict == "NO-GO") == (status == "memory_infeasible")` (`:649`).
- **Split peaks.** If the two peaks straddle the threshold, both sides now say NO-GO. The 11.3 GiB test pins this.
- **Consistency.** The verdict uses the same quantity as B1.
- **Correct.** The only gap left is the equality boundary (IN-03).

### Wrapper backward compatibility

With `HEAP_SIZE_HINT` unset, `HEAP_ARGS=()`. The expansion `"${HEAP_ARGS[@]}"` is safe under `set -u` on bash 5.3, which the host runs; bash ≥ 4.4 is required for that, and `LABEL_ARGS` already relied on it.

The julia command line for `benchmark_ieee8500.jl`, `profile_ieee8500_memory.jl` and `profile_ieee8500_memory_attribution.jl` is therefore byte-identical to before. No other script, doc or CI file sets or reads `JULIA_HEAP_SIZE_HINT`.

### Re-run data

- **Row consistency.** The regenerated measured row is internally consistent:
  - VmHWM 6,016,952 kB equals the wrapper's MaxRSS;
  - the ratio 309.6735071222779 and 5 iterations are byte-identical to the 2026-11-05 run (deterministic);
  - the sub-seed is unchanged.
- **Docs run.** The docs section runs to completion against the committed CSVs.
- **The problem.** Some of its prose no longer describes what it prints (CR-01).

## Critical Issues

### CR-01: After the re-run, the committed docs page contradicts its own cited evidence and its printed numbers, and it omits the 2026-11-06 gate override

**File:** `docs/literate/ieee8500_scaling.jl:953-959`, `:961-977`, `:1139-1141`, `:1041`; `.planning/research/STACK.md:63-69`; root cause in `results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time:1`

**Issue:** The fixes were written before the re-run. Commit `02d8857` then replaced the measured row and overwrote the label's `runs/` evidence files. The page is the committed go/no-go decision record, and it now makes four claims that the committed tree contradicts.

1. **The heap-hint correction note cites evidence that now shows the opposite (`:953-957`).**
   - The note says the 2026-11-05 run had no hint, because "the run's `runs/p46-scn-ieee8500-d10-T10.time` command line has no such flag".
   - The committed file now reads `... julia --heap-size-hint=8G --project=. scripts/ieee8500_scenario_point.jl ... --min-mem-avail-gib 6.5`.
   - The evidence the note relies on exists only in history (`git show f60857e:results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time`, which shows no flag).
   - A reader who checks the cited file will conclude that the correction itself is false. That is the same false-provenance class as iteration-1 CR-01.
   - `STACK.md:66-67` ("No IEEE-8500 run ... up to and including the Phase-46 T = 10 point had a heap-size hint") is now wrong for the T = 10 point that is committed, which did have one.
   - The divergence-table row at `:1041` says "(none on the 2026-11-05 row, see the correction note)". That row is no longer in the CSV.
2. **The prose and the printed footprint disagree (`:972-976`, `:1139-1141`).**
   - The prose says the startup footprint "is computed below from that attempt's two readings", meaning attempt 2, which was read after package load.
   - The Reproducing section says that on 2026-11-05 "the default floor needed about one more GiB at launch (printed above)".
   - The page actually prints the following (I executed the section): `in-script MemAvailable (measured row, read before package load) 7482696 kB = 7.136 GiB; startup footprint 77496 kB = 0.074 GiB` and `the default 8 GiB in-script gate therefore implies about 8.07 GiB`.
   - The ~0.92 GiB package-load footprint, which justified the 2026-11-05 floor override, can no longer be derived from committed rows: attempt 2's final row was replaced.
3. **The 2026-11-06 launch override is not recorded.**
   - CONTEXT requires a pre-flight of at least 8 GiB.
   - Attempt 3 ran with `--min-mem-avail-gib 6.5` on a pre-load reading of 7.136 GiB. The default gate would have refused that reading.
   - The commit message says the floor was user-approved on 2026-11-06. The page says only that attempts 1 and 2 were "launched with the user's explicit approval at about 7.1 GiB". The approval behind the row it actually reports is not stated.
   - Plan 05 set the precedent that the docs state the override.
4. **The section narrative (`:961-977`) still describes attempt 2 as the run that "ran to completion" and joins the measured row.** The printed join is attempt 3. A reader cannot tell from the prose which launch produced the six numbers, or that it ran with an 8 GiB heap hint, unlike every harness comparator.

**Fix:** Add a dated paragraph and adjust the existing prose. The page should compute numbers and must not quote them:
```julia
# **Re-run (2026-11-06).** The measured row above is attempt 3: launched with
# `HEAP_SIZE_HINT=8G` (an applied `--heap-size-hint=8G`, visible in the run's `.time`
# command line) and `--min-mem-avail-gib 6.5` on the pre-load reading, a floor below the
# 8 GiB gate that the user approved on 2026-11-06. It replaced the 2026-11-05 final row
# (attempt 2) under the same key. The runs/ evidence files now belong to attempt 3; the
# 2026-11-05 evidence is at commit f60857e (`git show f60857e:results/ieee8500_benchmark/runs/
# p46-scn-ieee8500-d10-T10.time`).
```
- Change the correction note at `:956` to cite `f60857e:` and not the working-tree file.
- Make the footprint sentence conditional on `when`. For example, print "package-load footprint (2026-11-05, attempt 2): not derivable from committed rows; 965,724 kB recorded at commit f60857e". Alternatively, drop the "about one more GiB (printed above)" clause.
- Change `:1041` to say "8 GiB on the current row; none on the replaced 2026-11-05 row".
- Add a dated line to `STACK.md` saying that the 2026-11-06 re-run did apply the hint.

## Warnings

### WR-01: Reusing a run label, as the documented reproduce command does, overwrites the `runs/` evidence and lets any final outcome replace the committed measurement

**File:** `scripts/run_ieee8500_point.sh:57`, `:65-67` (evidence paths keyed only by `$LABEL`); `docs/literate/ieee8500_scaling.jl:1148-1150`; `scripts/README.md:34`; `scripts/ieee8500_scenario_point.jl:348`

**Issue:** CR-02 made `run_label` part of the attempt identity, so a "re-run of the same attempt identity replaces its own row". Three facts work against that:
- **Nothing makes labels unique per launch.**
- **The reproduce command reuses the committed label.** Both the docs and the README hard-code `p46-scn-ieee8500-d10-T10`.
- **The wrapper overwrites the evidence of every earlier launch of a label.** It writes `free -m > runs/$LABEL.free_before`, `rm -f runs/$LABEL.pid`, and `time -o runs/$LABEL.time`.

The consequences:
- **This already happened.** After `02d8857`, `point_resources.csv` holds three rows for the label (attempts 1-3), but the `runs/` files describe only attempt 3. Attempt 2's row (MaxRSS 6,059,204 kB, floor 5.5) has no evidence in the tree, and that is how CR-01 item 1 arose.
- **A failed reproduction can replace the committed measurement.** Suppose a later reproduction with this label ends in a final but different outcome: `memory_infeasible_inprocess` on a busier host, `budget_exceeded` on a slower one, or `error:SolveFailedError`. That outcome silently replaces the committed `refused_certificate` row, which is the scenario CR-02 was raised to prevent.
- **The transient-row protection does not help here.** It covers only `started`, `preflight_refused` and `crashed:*`.

**Fix:**
1. **Wrapper.** Refuse to reuse a label whose evidence already exists, unless `FORCE_RELABEL=1` is set:
   ```bash
   if [ -e "$RUNS/$LABEL.time" ] && [ "${FORCE_RELABEL:-0}" != 1 ]; then
     echo "label $LABEL already has evidence in $RUNS; use a new label (e.g. ${LABEL}-r2)" >&2
     exit 2
   fi
   ```
2. **Commands.** Change the docs and README reproduce commands to use a fresh label, for example `<label>-$(date +%Y%m%d)`, and say so.
3. **Optional.** Record the wrapper's `started_at`, or the child pid, in the scenario row. The docs could then join on it instead of on the MaxRSS == VmHWM coincidence (see WR-02).

### WR-02: The docs page crashes on exactly the outcomes its status prose promises to describe (`started`, `preflight_refused`)

**File:** `docs/literate/ieee8500_scaling.jl:1001-1003` (and `:839-842`, `:830-832`)

**Issue:** `hm_print_wrappers` filters the wrapper rows on `hm_num(w["peak_rss_kb"]) == hm_num(r["vmhwm_kb"])` and then runs `@assert !isempty(joined)`.
- A `started` row (process killed by a signal) has an empty `vmhwm_kb`, and so does a `preflight_refused` row. `hm_num("")` is `NaN`, and `NaN == x` is never true, so the assert fires and the docs build fails.
- `hm_status_sentence("started")` says "the wrapper row below (rc, oom_source) is the measured outcome". That branch can never render, and neither can the pre-flight one. The 46-05 summary's claim that "a refusal, a kill or a not-launched run each read plainly" is therefore false for two of the three cases.
- Before the fix, the last-wrapper assert had the same flaw. The CR-02 fix rewrote this join and kept the hard assert.
- The join on MaxRSS == VmHWM is also a numeric coincidence, not a key. `/usr/bin/time` MaxRSS can exceed the VmHWM read before the final upsert and exit, and then the assert also fails for a final row.

**Fix:** Join only when the row carries a peak, and print instead of asserting:
```julia
joined = isnan(hm_num(r["vmhwm_kb"])) ? typeof(wrappers)() :
         filter(w -> hm_num(w["peak_rss_kb"]) == hm_num(r["vmhwm_kb"]), wrappers)
if isempty(joined)
    println("no wrapper row joins this row by peak; the last wrapper row (rc ",
            last(wrappers)["rc"], ", oom_source ", last(wrappers)["oom_source"],
            ") is the launch outcome")
    return nothing
end
```
Better still, use an explicit join key (WR-01, fix 3).

### WR-03: A solver-layer error inside the ADMM loop still discards the solve time and the iterations already run

**File:** `scripts/ieee8500_scenario_point.jl:787-806`, `:864-870`

**Issue:** The WR-03 fix moved certify to `time_ns` + `finally`. The solve phase still uses `t[:solve] = @elapsed begin _admm_iterate!(...) end`. If `_admm_iterate!` raises a `TSODSOError` mid-loop, for example a `SolveFailedError` from a Clarabel subproblem at 8500 scale:
- `@elapsed` aborts, so `t[:solve]`, `tc[:solve]` and the `:solve` VmHWM sample are never recorded;
- `loop_done` stays `false`, so the outer catch writes `iters = -1`, although `st.residuals.iters` holds the number of completed iterations (`have_st` is true).

The resulting `error:SolveFailedError` row has `solve_s` missing and `-1` iterations. For a plausible large-scale failure, that is the same information loss iteration-1 WR-03 described.

**Fix:** Use the same pattern as certify:
```julia
t0 = time_ns(); c0 = cns()
try
    TSODSO._admm_iterate!(st, rmode, A.maxiter, A.ε_abs, A.ε_rel, A.τ_ratio, A.μ,
                          1e-2, 1e4, time_limit_s, false)
finally
    t[:solve] = (time_ns() - t0) / 1e9
    tc[:solve] = (cns() - c0) / 1e9
    push!(hwm_by_phase, :solve => hwm())
end
```
In the outer catch, use `have_st ? Int(st.residuals.iters) : -1` after the `err.iterations` check. Note in the row that this is a partial count when `!loop_done`, for example as `iters_partial` in the message.

### WR-04: A `memory_infeasible_inprocess` row cannot say which phase ran out of memory

**File:** `scripts/ieee8500_scenario_point.jl:855-856`, `:1005-1035`

**Issue:** An `OutOfMemoryError` is not a `TSODSOError`, so `scenario_admm_phases` rethrows it (`:856`). Every partial result lives in that function's locals: `t`, `tc`, `sizes`, `hwm_by_phase`, `iters` and `loop_done`. All of it is discarded.

The row written by `run_measured_point` holds only:
- the VmHWM at catch time;
- `sprint(showerror, err)`, which for an OOM is the uninformative `OutOfMemoryError()`.

This status is the one WR-02 introduced as "a measured outcome" of the memory study. The row cannot say whether the failure came during the AgrOpt builds, the DSO build or iterate k, or what sizes were reached. That decomposition is exactly what the T = 24 attribution needed.

**Fix:** Catch `OutOfMemoryError` inside `scenario_admm_phases` and return a status, as is done for `TSODSOError`. Keep every partial field:
```julia
catch err
    if err isa OutOfMemoryError
        status = "memory_infeasible_inprocess"
        message = "OutOfMemoryError after phases " * join(first.(hwm_by_phase), ",")
        iters = have_st ? Int(st.residuals.iters) : -1
    else
        err isa TSODSOError || rethrow()
        ...
    end
```
After that, `run_measured_point` writes the full row and can still rethrow, or exit nonzero, if a nonzero exit code is wanted.

## Info

### IN-01: `HEAP_SIZE_HINT` validation accepts values that silently mean bytes

**File:** `scripts/run_ieee8500_point.sh:46-50`

**Issue:** The regex `^[0-9]+([.][0-9]+)?[KMGTkmgt%]?$` accepts a bare number: `HEAP_SIZE_HINT=8` gives an 8-byte hint, which I verified (`JLOptions().heap_size_hint == 8`). It also accepts `%`, which the error message advertises (`50%`). On Julia 1.10.11, the project's compat floor, `--heap-size-hint=50%` silently yields **50 bytes**. The `point_resources.csv` `args` column does not record the hint either; only the `.time` file does.

**Fix:** Require a unit, and reject `%` unless `julia --version` is at least 1.11. Alternatively, accept only `[0-9]+[MG]`. Append `heap=$HEAP_SIZE_HINT` to `ARGS_STR`.

### IN-02: The counter-fact's "ran its production solve to the end" accepts a budget-exceeded anchor

**File:** `scripts/ieee8500_scenario_point.jl:580`, `:594-596`; `docs/literate/ieee8500_scaling.jl:735`

**Issue:** `anchor_done = anchor_iters > 0`. The attribution script (`profile_ieee8500_memory_attribution.jl:372`) writes `iters = r.iters` for any returned result, including `status = "budget_exceeded"`. Such an anchor would be reported as having run "to the end". The current data (`ERROR:CertificateError`, 7 iterations) is correct.

**Fix:** `anchor_done = anchor_iters > 0 && !occursin("budget", lowercase(anchor_status))`. Mirror the check in the docs assert.

### IN-03: The verdict at exactly the threshold is undefined

**File:** `scripts/ieee8500_scenario_point.jl:565`; `docs/literate/ieee8500_scaling.jl:648`

**Issue:** GO needs the peak *below* the threshold, so NO-GO is `peak >= threshold`. With `>`, a peak equal to the threshold makes the script throw ("no measured peak exceeds"), while the docs print `GO`.

**Fix:** Use `>=` in both places, and reword the throw message to "no measured peak reaches".

### IN-04: The atomic-write test does not exercise the cleanup path, and a SIGKILL leaves an unignored temp file

**File:** `test/test_ieee8500_scenario.jl:596-600`; `scripts/ieee8500_scenario_point.jl:440-446`

**Issue:** `CSV.write(tmp, :not_a_table)` throws `ArgumentError` *before* it creates the file (verified: `isfile` is false afterwards). So "no temporary file behind" holds vacuously, and the `finally rm` is never tested. Separately, a SIGKILL during the write, such as earlyoom's escalation, leaves `.scenario_table.csv.tmp.<pid>` in `results/ieee8500_benchmark/`. That file is not covered by `.gitignore` and could be committed with the directory.

**Fix:** Test with a table whose write fails mid-stream, for example a column whose `string` method throws. Add `/results/**/.*.tmp.*` to `.gitignore`.

### IN-05: The `error:<Type>` branch is still untested

**File:** `scripts/ieee8500_scenario_point.jl:855-871`

**Issue:** The branch has no test (the fixer acknowledged this), so the WR-03 iteration logic for a non-certificate error has no regression guard.

**Fix:** Inject the failure. For example, give `scenario_admm_phases` an internal `certify = TSODSO._admm_certify` keyword, used only by tests, and pass a stub that throws `SolveFailedError(...)`. Then assert `status == "error:SolveFailedError"`, `iters == <converged count>` and `!ismissing(certify_s)`.

### IN-06: Iteration-1 IN-07 and IN-08 are still open (the fixer deferred them)

**File:** `src/experiments/Scenario.jl:181` (no IEEE-8500 T < 9 guard); `scripts/ieee8500_scenario_point.jl:92-93` (`@quickactivate` runs inside test items)

**Issue:** The fixer's reasons were recorded and are reasonable. The findings still stand.

**Fix:** As in iteration 1, or move them to the deferred-items list explicitly.

---

_Reviewed: 2026-11-06T11:45:24Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_
