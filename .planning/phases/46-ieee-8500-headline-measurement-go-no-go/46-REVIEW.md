---
phase: 46-ieee-8500-headline-measurement-go-no-go
reviewed: 2026-11-06T12:30:09Z
iteration: 3
depth: standard
files_reviewed: 8
files_reviewed_list:
  - scripts/ieee8500_scenario_point.jl
  - scripts/run_ieee8500_point.sh
  - docs/literate/ieee8500_scaling.jl
  - .planning/research/STACK.md
  - test/test_ieee8500_scenario.jl
  - scripts/README.md
  - .gitignore
  - .planning/phases/46-ieee-8500-headline-measurement-go-no-go/deferred-items.md
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 46: Code Review Report (iteration 3)

**Reviewed:** 2026-11-06T12:30:09Z
**Iteration:** 3, the final allowed iteration. Iteration 2 is kept as `46-REVIEW.iter2.md` and iteration 1 as `46-REVIEW.iter1.md`.
**Depth:** standard, plus these cross-file checks:
- `src/admm/admm_phases.jl`: where `_admm_iterate!` advances `residuals.iters`, and how `record!` (`src/admm/residuals.jl`) counts;
- the evidence the docs cite from history (`git show f60857e:...`);
- the docs page executed end to end (`julia --project=docs docs/literate/ieee8500_scaling.jl`, exit 0).

**Files Reviewed:** 8
**Status:** issues_found

## Summary

**Scope.** `git diff f6e6afc..HEAD`: the iteration-2 fix commits `0bfbe83` .. `77f51e2`.

**Out of scope (known or deferred):**
- repo-wide JuliaFormatter drift;
- the 2 pre-existing script-API-lint findings in `profile_ieee8500_memory_attribution.jl`;
- `deferred-items.md` items 3 and 4 (iteration-1 IN-07 and IN-08).

**Result.** All five iteration-2 findings in scope (CR-01, WR-01 .. WR-04) and IN-01 .. IN-05 are resolved as specified. I found no critical regression. Two warnings remain:
- **WR-01.** The two label-reuse overrides are not ordered safely. `REPLACE_LABEL=1` destroys the `runs/` evidence of a row that the script then keeps.
- **WR-02.** The WR-04 out-of-memory row keeps partial timings only for the solve and certify phases. Build is the phase most likely to run out of memory, and it is still timed with `@elapsed`.

### Verification of the iteration-2 findings

| ID | Verdict | Basis |
|---|---|---|
| CR-01 docs vs re-run | **Resolved** | I ran the page. It prints `runs/...time command line: --heap-size-hint=8G`, attempts 1 to 3 with floors 7 / 5.5 / 6.5, "the measured row joins attempt 3", 77,496 kB (bare runtime startup) and about 8.07 GiB. The prose matches what is printed. I checked the cited history: `f60857e:.../p46-scn-ieee8500-d10-T10.time` has no `--heap-size-hint`. The `f60857e` measured row has 5 iterations, ratio 309.67 and in-script reading 6,455,204 kB. 7247 MiB × 1024 − 6,455,204 = 965,724 kB, as quoted. The STACK.md note is scoped and dated correctly. |
| WR-01 label reuse | **Resolved for the default path; residual risk WR-01 below** | The wrapper refuses a label when `runs/<label>.time` or `.free_before` exists, or when the label has a `point_resources.csv` row. It exits 2 before `free -m` or `/usr/bin/time` writes anything. `final_status_for_key` uses the same `_key` stringification as `upsert_rows!`, so an Int `T`/`seed` and the CSV-read values agree. A missing `run_label` reads as `"missing"` on both sides. The check runs before the pre-flight, so a refused key writes no `preflight_refused` row. |
| WR-02 docs crash on transient rows | **Resolved** | When `vmhwm_kb` is `NaN`, the page uses `empty(wrappers)`. When nothing joins, it prints the last wrapper row and returns, with no `@assert`. A real `memory_infeasible_inprocess` row (MaxRSS ≥ VmHWM) also renders. |
| WR-03 loop error discards solve time and iterations | **Resolved** | Reasoning below. |
| WR-04 OOM row cannot name the phase | **Resolved for solve and certify; partial for build (WR-02 below)** | Reasoning below. |
| IN-01 .. IN-05 | **Resolved** | `^[1-9][0-9]*[KMGTkmgt]$` rejects `8`, `50%`, `8.5G` and `0G` (tested). The `args` suffix is added only when a hint is set. The anchor budget check matches the attribution script's `budget_exceeded` status. `>=` is used in both the script and the docs, with a boundary test. The mid-stream write test confirms the temporary file exists and is then removed. `.gitignore` matches `.scenario_table.csv.tmp.<pid>` (`git check-ignore` confirms). `error:<Type>` is tested through `certify_fn`. |
| IN-06 | **Moved to `deferred-items.md`** | Items 3 and 4. Out of scope. |

#### WR-03: reasoning through the error path

1. **Where the counter advances.** `_admm_iterate!` calls `record!` (`res.iters += 1`) only after both the AgrOpt solves and the DSO solve of iteration k.
   - A `SolveFailedError` raised by either solve in iteration k leaves `residuals.iters == k-1`. That is exactly the number of completed iterations, so `iters_partial: ... after $(iters) completed iterations` is accurate.
2. **What `finally` records.** The solve `finally` at `:858-862` records `t[:solve]`, `tc[:solve]` and the `:solve` sample before the outer `catch` runs.
3. **Counting order in the catch.** `own_iters` comes first, so an error that carries its own `iterations` keeps it.
   - The `iters_partial` marker is gated on `have_st && !loop_done && !own_iters`. A certify-time error has `loop_done == true`, so it gets the converged count with no marker. The IN-05 test pins this.
4. **The default path is unchanged.** `iterate_fn`/`certify_fn` default to the real functions with the same positional arguments, and `run_measured_point` never passes them.

#### WR-04: reasoning through the error path

1. **Solve and certify.** An `OutOfMemoryError` raised there passes through the inner `finally` (certify's inner `catch` rethrows it). The outer `catch` then returns `memory_infeasible_inprocess` with the phase name, the phases sampled and `st.residuals.iters`.
2. **After the phases return.** The `st` locals become unreachable, so the CSV rewrite in `run_measured_point` does not run under the peak footprint.
3. **The row is final.** `memory_infeasible_inprocess` is not in `TRANSIENT_STATUSES`.
4. **The exit stays nonzero.** It is still raised after the upsert (`:1181`). The wrapper then sees rc 1, so `oom_source` correctly stays `none` (not 137/143).
5. **If the handler itself runs out of memory.** An OOM raised inside the catch while building strings would propagate. `run_measured_point`'s outer catch still records the status (best effort), so no outcome is lost.
6. **The gap** is that materialize and build are still timed with `@elapsed` (see WR-02).

### Wrapper backward compatibility

With `HEAP_SIZE_HINT` unset, the julia command line and the `args` column are byte-identical to before for `benchmark_ieee8500.jl`, `profile_ieee8500_memory.jl` and `profile_ieee8500_memory_attribution.jl`. The extra `${ARGS_STR% }` strip is idempotent.

The only behaviour change is the intended one: reusing a label now exits 2.
- **Callers.** No script, test, CI file or docs page calls the wrapper with a committed label. The README, the script headers and the docs all use `<label>` or a fresh dated `$LABEL`.
- **Older plans.** `.planning/milestones/v4.0-phases/35-*` contains historic commands with committed labels. Re-running one of them now needs a new label or `REPLACE_LABEL=1`, which is acceptable for planning history.

## Warnings

### WR-01: `REPLACE_LABEL=1` overwrites the `runs/` evidence before the script decides whether to keep the old row, so the committed row can end up beside another launch's evidence

**File:** `scripts/run_ieee8500_point.sh:67-80`, `:83`, `:92-93`; `scripts/ieee8500_scenario_point.jl:1051-1063`; `docs/literate/ieee8500_scaling.jl:969-984`, `:1228-1230`

**Issue:** There are two independent overrides. The destructive one acts first.
- **The wrapper acts first.** With `REPLACE_LABEL=1` it writes over:
  - `runs/$LABEL.free_before` (`:83`);
  - `runs/$LABEL.pid` (`:92`);
  - `runs/$LABEL.time` (`:93`, `/usr/bin/time -o` truncates at launch);
  - later, `.oom_kernel` and `.oom_earlyoom`.

  All of this happens before julia starts.
- **The script decides only afterwards.** It decides after package load whether the old row survives, and in several outcomes it keeps the old final row:
  - **No `--replace`:** `final_status_for_key` refuses with an `ArgumentError` (exit 1). The docs list the two overrides as independent bullets (`:1228-1230`) and never say they must be paired, so this is the natural mistake.
  - **`--replace`, but the launch ends transient:** this covers `preflight_refused` on a busy host, a SIGKILL from earlyoom that leaves `started`, and a `crashed:*` outcome. `upsert_rows!` keeps the old final row by design.

In each case, `scenario_table.csv` still holds the committed `refused_certificate` row for `p46-scn-ieee8500-d10-T10`, but its `runs/` files now describe the failed launch. That is the same row-versus-evidence mismatch that caused iteration-2 CR-01.

The docs page would not catch it:
- `hm_time_heap_flag` (`:976-984`) only **prints** the current `.time` flag. The prose at `:971-972` says it "is checked below", but nothing asserts it against the row's `heap_size_hint`.
- A no-hint replacement would print `no --heap-size-hint flag` under a paragraph that says the run used `--heap-size-hint=8G`, and the page would still build.

**Fix:**
1. **Make the override non-destructive.** Archive the existing evidence instead of overwriting it:
   ```bash
   if [ "${REPLACE_LABEL:-0}" = 1 ]; then
     STAMP="$(date +%Y%m%d-%H%M%S)"
     for ext in free_before time pid oom_kernel oom_earlyoom; do
       [ -e "$RUNS/$LABEL.$ext" ] && mv "$RUNS/$LABEL.$ext" "$RUNS/$LABEL.$ext.replaced-$STAMP"
     done
   fi
   ```
   Alternatively, for `SCRIPT=*ieee8500_scenario_point.jl`, refuse `REPLACE_LABEL=1` unless `--replace` is among `"$@"`. That at least removes the unpaired case.
2. **Make the docs check real.** Assert that the `.time` flag agrees with the row's effective hint:
   ```julia
   hm_flag = hm_time_heap_flag(hm_label)
   hm_hint = tryparse(Int, only(hm_meas)["heap_size_hint"])
   @assert (hm_hint !== nothing && hm_hint > 0) == startswith(hm_flag, "--heap-size-hint=")
   ```
3. **Document the pairing.** At `:1228-1230`, say that replacing a Scenario row needs both `REPLACE_LABEL=1` and `--replace`, and that a transient outcome keeps the old row.

### WR-02: An out-of-memory error during build, the phase with the largest measured memory component, still loses the build time and its VmHWM sample

**File:** `scripts/ieee8500_scenario_point.jl:787-799` (materialize), `:808-822` (build), `:62-64` (header claim), `:754-756` (docstring claim); `test/test_ieee8500_scenario.jl:925-940`

**Issue:** The WR-04 fix advertises "every partial field (phase times, sizes, VmHWM samples, completed iterations) is kept". The header says "the row keeps the phase under way and the partial timings". In code, only solve and certify moved to `time_ns` + `finally`. Materialize and build are still `t[...] = @elapsed begin ... end` followed by `tc[...]` and `push!(hwm_by_phase, ...)`. An `OutOfMemoryError` inside `_admm_build` therefore aborts the `@elapsed`, and the row then has:
- `build_s` and `build_compile_s` missing;
- no `:build` sample, so the message reads `VmHWM sampled after: materialize`;
- every size field from `n_agr_models` onward missing.

That is the most plausible in-process OOM site for this study. The committed T = 24 attribution puts 4.569 GiB in the 122 AgrOpt builds plus 0.851 GiB in the DSO build. That is more than the first retained iterate (about 2.9 GiB). The test covers only an OOM in the solve phase (`one_then_oom`), so this gap has no regression guard. The row still names `phase build`, which was the core ask of iteration-2 WR-04, so this is a robustness gap and not a loss of the verdict.

**Fix:** Time materialize and build with the same pattern as solve and certify:
```julia
phase = :build
t0 = time_ns(); c0 = cns()
try
    st = TSODSO._admm_build(feeder, pf, aggs, s.T, λ₀, ρf, ρf, mode, rmode;
                            agr_optimizer = TSODSO.select_optimizer(TSODSO.QP()))
finally
    t[:build] = (time_ns() - t0) / 1e9
    tc[:build] = (cns() - c0) / 1e9
    push!(hwm_by_phase, :build => hwm())
end
have_st = true
```
Apply the same pattern to materialize. Add a stub test: wrap `TSODSO._admm_build` behind a `build_fn` seam that throws `OutOfMemoryError()`. Assert `!ismissing(ph.build_s)`, `phase_names(ph) == [:materialize, :build]` and `occursin("during phase build", ph.message)`. If the extra seam is not wanted, narrow the header and docstring wording to "solve and certify timings".

## Info

### IN-01: Header and docstring text predate the iteration-2 changes

**File:** `scripts/ieee8500_scenario_point.jl:39-40`, `:47-50`, `:726`, `:645`

**Issue:** The text no longer matches the code in four places:
- **`:39-40` and `:726`** say each phase gets "its own `@elapsed`". Solve and certify are now timed with `time_ns`.
- **The sequence at `:47-50`** omits the reused-key check, which now runs before the pre-flight. It also still says the final row replaces "any earlier final row of the same seed and label". Without `--replace`, such a run is now refused before anything is written.
- **The NO-GO note at `:645`** says the larger peak "exceeds" the threshold. Since IN-03, a peak equal to the threshold is also a NO-GO.

**Fix:** Reword these four places:
- `:39-40` and `:726`: "timed separately (`@elapsed`, or `time_ns` + `finally` for solve and certify)";
- `:47-50`: insert "-> reused-key check (refused unless `--replace`)" into the sequence;
- `:645`: "reaches or exceeds".

### IN-02: The wrapper test inherits `REPLACE_LABEL` and `HEAP_SIZE_HINT` from the test process environment

**File:** `test/test_ieee8500_scenario.jl:769-777`

**Issue:** `addenv` merges into the inherited environment. If a developer runs the suite with `REPLACE_LABEL=1` exported, the `used` and `rowonly` cases skip the guard. The wrapper then runs `free`, `/usr/bin/time` and julia on the nonexistent script, exits 0 and writes `runs/` files. The test fails, or on a host without `/usr/bin/time` it behaves unpredictably. An exported invalid `HEAP_SIZE_HINT` makes the label cases exit 2 for the wrong reason.

**Fix:** Pin both variables in `wrapper_rc` before the caller's overrides: `"REPLACE_LABEL" => "0", "HEAP_SIZE_HINT" => ""`.

### IN-03: The wrapper's label uniqueness does not carry over to the Scenario row key, because the script's `--run-label` is typed separately

**File:** `scripts/run_ieee8500_point.sh:44-47`; `docs/literate/ieee8500_scaling.jl:1232-1236`; `scripts/README.md:34`

**Issue:** The wrapper injects `--run-label "$LABEL"` only for `benchmark_ieee8500.jl`. For `ieee8500_scenario_point.jl`, the user must pass `--run-label "$LABEL"` by hand.
- **A forgotten label.** If it is left out, the row is keyed with `run_label = missing`. It no longer joins the wrapper row, which the docs select by `run_label`.
- **A mismatched label.** If the two labels differ, the fresh-label guarantee that WR-01 relies on does not hold for the row.

**Fix:** Extend the basename check to `ieee8500_scenario_point.jl`, after checking that `parse_options` rejects a duplicated `--run-label` or takes the first one. Drop the manual flag from the documented commands. Alternatively, have the script refuse when `--run-label` is absent in measured mode.

---

_Reviewed: 2026-11-06T12:30:09Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 3_
