---
phase: 46-ieee-8500-headline-measurement-go-no-go
reviewed: 2026-11-06T00:38:10Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - scripts/ieee8500_scenario_point.jl
  - test/test_ieee8500_scenario.jl
  - test/test_flex_population.jl
  - docs/literate/ieee8500_scaling.jl
  - scripts/README.md
  - results/ieee8500_benchmark/scenario_table.csv
findings:
  critical: 2
  warning: 9
  info: 8
  total: 19
status: issues_found
---

# Phase 46: Code Review Report

**Reviewed:** 2026-11-06T00:38:10Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Scope: `git diff 7f13ec4..HEAD`, limited to the eight files listed above. Known and out of scope: formatter drift in 22 unrelated files, and the 2 pre-existing script-API-lint findings in `scripts/profile_ieee8500_memory_attribution.jl`.

**What is sound.**
- **The `:default_10pct` selector.**
  - It reuses the `:default` branch, which is unchanged.
  - It uses the same `clamp(round(Int, 0.1*n), 1, n)` / `randperm(LehmerRNG(seed))` / sorted / keep-capacitors rule as `sample_density_buses` + `density_filtered_population`.
  - At a fixed seed and Julia version it is deterministic.
- **The `Scenario` widening.**
  - No field was added, so the default construction, `==`, `hash` and `savename` stay as they were.
  - All four new guards are in the inner constructor, so `with_strategy` and the keyword paths cannot bypass them.
- **The ADMM phase composition.** It matches `solve_admm` for `run(::ADMM)`:
  - same `ρ`/`ρ_q`, `ρ_min = 1e-2`, `ρ_max = 1e4`, `rtol_exact = 1e-4`, `atol_exact = nothing`;
  - the same `ConvergenceError` iteration count (`maxiter`);
  - the `CertificateError` iteration count is taken from `st.residuals.iters`, which is equivalent to the re-wrap.

**Two blockers.**
1. **False provenance.** The committed measured row and the docs record a heap-size hint of `8G`, but the run had none. Julia ignores `JULIA_HEAP_SIZE_HINT` and the wrapper never passes `--heap-size-hint`. I checked this on the same Julia 1.12.5 and confirmed it from the run's own `.time` command line.
2. **Lossy upsert key.** The key does not include the seed or the run label. A later `started` or `preflight_refused` row therefore silently replaces a completed measurement. This already happened twice during the phase.

**Warnings.**
- The CSV rewrite is not atomic.
- The NO-GO verdict uses `min` where it should use `max`, and the docs never assert the verdict against the recorded status.
- B2 depends on whichever host runs `--record-nogo`, and the docs back-derive its "host total" from B2 itself.
- Hard-coded counter-fact prose in the NO-GO note.
- Expected memory outcomes (`OutOfMemoryError`) leave a misleading `started` row.
- Status-row information is lost on non-certificate certify errors.
- The phase timings include JIT compilation but are not labelled as such.
- Every non-`ok` status branch is untested, and that includes the branch that produced the committed row.

## Critical Issues

### CR-01: Committed measured row and docs claim an 8G heap-size hint that was never applied

**File:** `scripts/ieee8500_scenario_point.jl:707` (also `:10`, `:105`; `scripts/README.md:34`; `docs/literate/ieee8500_scaling.jl:851`, `:925`, `:1028`; `results/ieee8500_benchmark/scenario_table.csv:3`)

**Issue:** `_provenance_fields` records `heap_size_hint = get(ENV, "JULIA_HEAP_SIZE_HINT", missing)`. Julia does not read that variable:
- `JULIA_HEAP_SIZE_HINT=1G julia -e 'print(Base.JLOptions().heap_size_hint)'` prints `0` on 1.12.5;
- `julia --heap-size-hint=1G ...` prints `1073741824`.

`scripts/run_ieee8500_point.sh` runs `julia --project=. "$SCRIPT" ...` without the flag. The run's evidence file `runs/p46-scn-ieee8500-d10-T10.time` confirms the command line had no `--heap-size-hint`.

The consequences:
- The committed measured row says `heap_size_hint = 8G`. That is false provenance.
- The docs divergence table (line 925) lists the heap hint as a difference between the harness path and the Scenario path. That difference does not exist.
- The run did not meet the CONTEXT hygiene requirement (`--heap-size-hint`).
- The README and docs reproduce commands keep giving the same no-op instruction.

**Fix:**
1. Record the hint the process actually has, not the environment variable:
   ```julia
   heap_size_hint = let h = Base.JLOptions().heap_size_hint
       h == 0 ? "none" : string(h ÷ 1024^2, "M")
   end,
   ```
2. Make the wrapper (or the documented launch) pass the hint for real, for example `julia --project=. ${JULIA_HEAP_SIZE_HINT:+--heap-size-hint=$JULIA_HEAP_SIZE_HINT} "$SCRIPT" ...`.
3. Correct the committed row's `heap_size_hint` to `none`, with a dated note.
4. In the docs, fix the line-925 table row (both paths ran without a hint) and the line-1028 / README commands.

### CR-02: The upsert key omits seed and run_label, so a later attempt silently replaces a completed measurement

**File:** `scripts/ieee8500_scenario_point.jl:301`, `:319`, `:724-732`, `:739-766`

**Issue:** `ROW_KEY = (:row_kind, :feeder, :population, :T, :strategy)`. The `key` NamedTuple built in `run_measured_point` also carries `seed` and `sub_seed_population`, but neither is part of the identity. So any re-launch of the same point removes the existing completed row (for example `refused_certificate` or `ok`), whatever its seed or label:
- the `preflight_refused` row at line 750 replaces it;
- the `started` row at line 755 replaces it before any work runs. If that relaunch is then OOM-killed, the only measurement on disk is gone.

A run with `--seed 2` also overwrites the seed-1 measurement. This is not hypothetical:
- In plan 02, a `preflight_refused` row replaced the `ok` smoke row.
- In plan 04, attempt 1's `preflight_refused` row was lost, so the docs had to reconstruct the footprint from attempt 2 only (46-05 deviation 2).

This is a data-loss path in a measurement script whose purpose is to preserve outcomes.

**Fix:** Key measured rows on the attempt identity, and never let a non-final row replace a final one:
```julia
const ROW_KEY = (:row_kind, :feeder, :population, :T, :strategy, :seed, :run_label)
# in upsert_rows!: refuse to replace a final row with a transient one
const TRANSIENT = ("started", "preflight_refused")
function _replace_ok(old, new)
    string(new.status) in TRANSIENT && !(string(old.status) in TRANSIENT) && return false
    return true
end
```
Alternatively, write the `started` and `preflight_refused` rows under a distinct `row_kind` (`attempt`), so that only final rows ever share the `measured` key. Add a test in which a `preflight_refused` upsert does not displace an existing `refused_certificate` row.

## Warnings

### WR-01: `upsert_rows!` rewrites the committed CSV in place (not atomic)

**File:** `scripts/ieee8500_scenario_point.jl:329-346` (write at `:344`)

**Issue:** `CSV.write(csv_path, df)` truncates the file and then streams the rows into it. The final upsert runs right after certify, which is when the process sits at its high-water mark and is most likely to receive earlyoom's SIGTERM. A kill or crash during the write leaves `scenario_table.csv` truncated or partial, and that loses the committed `recorded_no_go` row along with the new one. Two concurrent invocations would also lose each other's updates, because there is no lock.

**Fix:** Write to a temporary file in the same directory and rename it over the target:
```julia
tmp = csv_path * ".tmp." * string(getpid())
CSV.write(tmp, df)
mv(tmp, csv_path; force = true)   # atomic rename on the same filesystem
```

### WR-02: Expected memory outcomes and validation errors leave a `started` row that the docs read as "process died"

**File:** `scripts/ieee8500_scenario_point.jl:659-660`, `:755-776`; `docs/literate/ieee8500_scaling.jl:782-784`

**Issue:** Only a `TSODSOError` becomes a status. Anything else is rethrown after the `started` row has been written, and that row has already replaced any earlier completed row (see CR-02). This covers:
- Julia's `OutOfMemoryError`, which is a plausible outcome at 8500 scale and is exactly the kind of result this phase exists to record;
- an `ArgumentError` from `_check_admm_pair!` or from Population;
- a `SystemError` from reading `/proc`.

The table then holds `started`. `hm_status_sentence` turns that into "the process died before writing its final row; the wrapper row … is the measured outcome", but the wrapper row will show `rc 1, oom_source none`. The record is wrong either way: a Julia OOM is misfiled as a non-outcome, and a programming error looks like a kill.

**Fix:** In `run_measured_point`, wrap the phases so the outcome is written before the rethrow:
```julia
ph = try
    scenario_admm_phases(s; ...)
catch err
    st = err isa OutOfMemoryError ? "memory_infeasible_inprocess" : "crashed:" * string(nameof(typeof(err)))
    upsert_rows!(path, [scenario_row(; key..., prov..., status = st, mem_avail_before_kb = avail_kb,
                                     note = first(sprint(showerror, err), 400))])
    rethrow()
end
```
Add the new statuses to the docs status vocabulary.

### WR-03: The iteration count and certify timing are discarded when certify throws a non-certificate `TSODSOError`

**File:** `scripts/ieee8500_scenario_point.jl:616`, `:630-637`, `:659-673`

**Issue:** `iters` is set from `st.residuals.iters` at line 616. Then, if `_admm_certify` throws, for example a `SolveFailedError` from a certify AgrOpt re-solve:
- the inner `catch` rethrows it, because it is not a `CertificateError`;
- the `@elapsed` aborts, so `t[:certify]` and the `:certify` HWM sample are never recorded;
- the outer `catch` sets `iters = -1`, because `SolveFailedError` has no `iterations` and the `have_st && status == "refused_certificate"` branch does not apply.

The row then reports a `-1` sentinel and a missing certify time for a loop that converged in a known number of iterations.

**Fix:** Keep the iteration count once the loop has finished, and time certify with explicit `time_ns`:
```julia
iters = if hasproperty(err, :iterations) && err.iterations !== nothing
    Int(err.iterations)
elseif have_st && st.residuals.iters > 0
    Int(st.residuals.iters)
else
    -1
end
```
For the timing, wrap certify with `t0 = time_ns(); try … finally t[:certify] = (time_ns()-t0)/1e9 end`.

### WR-04: B2 depends on the host that runs `--record-nogo`, and the docs back-derive its "host total" from B2

**File:** `scripts/ieee8500_scenario_point.jl:427`; `docs/literate/ieee8500_scaling.jl:681-702`

**Issue:** `derive_nogo_row` defaults `host_total_kb` to the MemTotal of the machine running the derivation. B2 is meant to describe *this host's* earlyoom limit at the measured peak. Re-running `--record-nogo` on a CI runner or a larger workstation silently rewrites `b2_gib_estimate` (and `git_head` and `julia_version`), while the note still says "on this host". The test pins `host_total_kb` explicitly, but the CLI does not.

In the docs:
- B2 is read from the row and is never recomputed.
- The printed "host total" is `(B2 - B1) / 0.12`, which is circular.
- The `free -m` cross-check (`hm_free_total_mib`) is printed and not asserted.

**Fix:**
1. Take MemTotal from the measurement host's evidence: the `Mem:` total in `runs/<label>.free_before`, or a named constant citing it. Make the CLI pass it, and do not read `/proc/meminfo`.
2. In the docs, recompute B2 and assert it:
```julia
hm_b2_calc = hm_b1_gib + 0.12 * hm_free_total_mib / 1024
@assert isapprox(hm_b2_calc, hm_b2_gib; rtol = 1e-3)   # free -m truncates to MiB
```

### WR-05: The verdict compares the smaller peak with the threshold, and the docs never check the verdict against the recorded status

**File:** `scripts/ieee8500_scenario_point.jl:431`; `docs/literate/ieee8500_scaling.jl:643-644`, `:657`

**Issue:** GO requires the point's peak to stay below the threshold. B1 is defined as the larger observation. Both sites test `min(peaks) > threshold`, which gives the wrong answer when the two peaks fall on opposite sides of the threshold (say 9.9 and 11.5 GiB):
- the script throws and refuses to record a NO-GO that the data supports (max = 11.5 > 10);
- the docs print `verdict: GO` next to a row whose status is `memory_infeasible`.

Line 657 prints both values without an `@assert`, so the contradiction would render silently. Today's data has both peaks above 10 GiB, so the current output is correct by luck.

**Fix:** Use `max(...) > threshold_gib` for NO-GO in both places, which is consistent with B1. In the docs, add `@assert (hm_verdict == "NO-GO") == (hm_nogo["status"] == "memory_infeasible")`.

### WR-06: The NO-GO note hard-codes the "completed twice" counter-fact instead of deriving it

**File:** `scripts/ieee8500_scenario_point.jl:438-444`, `:465-468`

**Issue:** The note always states "this d = 0.1 T = 24 point completed on this host twice … by evicting page cache and using swap". It says so whatever `p35_rc` is and whatever the anchor row shows. If the head row had `rc != 0`, the note would interpolate `rc 143` into a sentence that says the point completed. The "evicting page cache and using swap" mechanism is asserted and not taken from any row. Separately, if the d = 0.25 row is missing or duplicated, `killed_txt` is silently dropped.

**Fix:** Before emitting the sentence, check `p35_rc == 0` and that the anchor row exists. Otherwise throw, or emit a different sentence. Require `nrow(killed) == 1`, because a silent omission changes the record. Attribute the mechanism to a cited source: the `free_before` swap and cache columns, or the Phase-39 docs section.

### WR-07: Phase timings include JIT compilation, and the docs present them as the measured build and solve times

**File:** `scripts/ieee8500_scenario_point.jl:556`, `:573`, `:600`, `:630`; `docs/literate/ieee8500_scaling.jl:756-764`, `:824-825`

**Issue:** The point runs in one cold process with no warm-up. `materialize_s`, `build_s` (27.48 s), `solve_s` (151.99 s) and `certify_s` therefore each include first-call compilation of JuMP/MOI/Clarabel and the TSODSO kernels. The IEEE-13 smoke run shows the scale: 14.2 s of "build" for a 740-variable DSO model. The docs print these as the "six numbers" with no compile caveat. The divergence table does not mention compilation either, although the harness numbers it is set beside have their own compile profile.

**Fix:** Record `Base.cumulative_compile_time_ns()` before and after each phase, either by enabling `Base.cumulative_compile_timing(true)` or with `@timed`'s `compile_time`. Store `*_compile_s` columns (or put them in the note). In the docs, add one line stating that the times include compilation, with the measured compile share.

### WR-08: Only the `ok` path of the phase composition is tested; the branch that produced the committed row is not

**File:** `test/test_ieee8500_scenario.jl:376-404`

**Issue:** The parity item checks `status == "ok"` on IEEE-13 and nothing else. No committed test exercises:
- `refused_certificate`, the actual production outcome, including the iteration count and the gap-ratio parse from a real `CertificateError`;
- `convergence_error`, where iters should be `maxiter`;
- `budget_exceeded`;
- `error:<Type>`.

The plan-02 scratch checks for `time_limit_s = 1e-6` and `maxiter = 3` were never committed. A regression in the status mapping or in the iteration logic would ship unnoticed. The `solve_admm` re-wrap equivalence for `CertificateError` iterations is also unpinned.

**Fix:** Add cheap IEEE-13 items. Each should also compare against `run_scenario`'s thrown error, for example via `@test_throws ConvergenceError run_scenario(...)` and its `.iterations`:
```julia
ph = scenario_admm_phases(Scenario(; name="x", strategy=ADMM(; maxiter=3), T=10, seed=3);
                          time_limit_s=nothing, sample_mem=false)
@test ph.status == "convergence_error" && ph.iters == 3 && ph.result === nothing
ph = scenario_admm_phases(s; time_limit_s=1e-6, sample_mem=false)
@test ph.status == "budget_exceeded" && ismissing(ph.certify_s)
```

### WR-09: The pre-flight measures MemAvailable after package load, so the documented 8 GiB gate is about 8.9 GiB in practice

**File:** `scripts/ieee8500_scenario_point.jl:57-59`, `:737-739`; `scripts/README.md:34`

**Issue:** The comment says the gate runs "first thing … before any materialization". It actually runs after `using DrWatson`, `@quickactivate`, `using TSODSO, JuMP, CSV, DataFrames, StableRNGs` and argument parsing, so it measures the process's own startup footprint (about 0.92 GiB). That footprint is why attempt 1 was refused, and why the floor was hand-lowered to 5.5 for attempt 2. The README still says the run "needs >= 8 GiB MemAvailable".

**Fix:** Read `/proc/meminfo` with Base only, at the top of the script before any `using`, and keep the value:
```julia
const _MEMAVAIL_AT_START_KB = let v = -1
    isfile("/proc/meminfo") && for l in eachline("/proc/meminfo")
        startswith(l, "MemAvailable:") && (v = parse(Int, split(l)[2]); break)
    end
    v
end
```
Use it in `run_measured_point`. Alternatively, keep the current gate and change the README and `--help` text to say "post-load MemAvailable".

## Info

### IN-01: Stale docstring for the column order

**File:** `scripts/ieee8500_scenario_point.jl:253-256`

**Issue:** The docstring says the docs page "splits each line with `limit = ncols`, so only the last field may contain commas". The docs reader is quote-aware (46-05 deviation 3).

**Fix:** Reword it: "`note` is last by convention; the docs reader is quote-aware."

### IN-02: Dead code in the certify branch

**File:** `scripts/ieee8500_scenario_point.jl:629`, `:646-647`

**Issue:**
- `certified = false` is never read.
- `get(st.dso.ctx.meta, :socp_maxratio, missing)` is always `missing`, because the ADMM certify path never sets that key (46-02 summary).
- The `ratio === nothing` test then checks for a value that cannot occur.

**Fix:** Remove the variable. Either set `gap_ratio = missing` with a comment, or expose the ratio from `_admm_certify`.

### IN-03: The meaning of `n_load_buses` is inconsistent

**File:** `scripts/ieee8500_scenario_point.jl:566-567`

**Issue:** `n_load_buses` is the total number of load buses on the feeder (1,177), not the 118 sampled houses. It is `missing` on non-8500 feeders, even though `_load_buses` works for every feeder.

**Fix:** Compute it for every feeder. Either add `n_sampled_houses = n_aggregators - n_cap_aggregators`, or say in the docs that it is the pre-sampling count.

### IN-04: CSV round-trip re-infers the provenance column types

**File:** `scripts/ieee8500_scenario_point.jl:333`

**Issue:** `CSV.read(csv_path, DataFrame)` infers column types on every upsert. If every `git_head` value happened to look numeric (for example `0123456` or `1234e56`), the column would be parsed as `Int` or `Float64` and rewritten without its leading zeros, or in exponent form.

**Fix:** Use `CSV.read(csv_path, DataFrame; types = Dict(:git_head => String, :run_label => String, :heap_size_hint => String))`.

### IN-05: The harness-equivalence test reuses the implementation's bus list, and the docstring overstates equivalence

**File:** `test/test_ieee8500_scenario.jl:189`; `src/experiments/materialize.jl:1046`

**Issue:** The inline "harness" copy calls `TSODSO._load_buses`, which is the same function the selector uses. The harness's own `_harness_load_buses` mirror is therefore not pinned. Also, the harness shares one `LehmerRNG(_SWEEP_SEED)` across all densities in a sweep (`benchmark_ieee8500.jl:977`). The two rules agree only for the first density drawn in a process, but the docstring says "at an equal `seed` the two give the same aggregators" without that qualifier.

**Fix:** Copy the harness's explicit per-feeder bus lists into the test. Qualify the docstring: "equal to a single-density harness invocation at an equal seed".

### IN-06: The docs ratio regex diverges from the script's parser

**File:** `docs/literate/ieee8500_scaling.jl:598-599`

**Issue:** `hm_ratio` uses `r"=([0-9.]+) > 1"`, which returns `NaN` for exponent-formatted ratios such as `=1.2e3 > 1`. The script uses the anchored `GAP_RATIO_RX`, which accepts `eE+-`.

**Fix:** Use the same pattern: `r"worst gap/\(atol_b\+rtol·\|cone\|\)=([0-9.eE+-]+)"`.

### IN-07: The IEEE-8500 horizon floor lives only in the script

**File:** `scripts/ieee8500_scenario_point.jl:108-110`; `src/experiments/Scenario.jl:181`, `:236-267`

**Issue:** `Scenario(feeder = :ieee8500, T = 5)` constructs fine. It then fails at materialization with the Deferrable energy-budget `ArgumentError`: the window collapses below T = 9, as `benchmark_ieee8500.jl:752-760` explains. The phase's policy is that "combinations 8500 cannot support get an ArgumentError guard", but here the knowledge is duplicated as `T_MIN_8500` in the script.

**Fix:** Add a construction guard `feeder ∈ _SCENARIO_8500_FEEDERS && T < 9`, with a message citing the Deferrable window. Drop the script constant, or derive it from the guard.

### IN-08: Test items that include the script run `@quickactivate` inside the test process

**File:** `test/test_ieee8500_scenario.jl:246`, `:301`, `:327`, `:378` (script `:57-58`)

**Issue:** Each `include` runs `using DrWatson; @quickactivate "TSODSO"`. That can switch the active project away from the `Pkg.test` sandbox in the middle of the run. `test_case_a_magnitude.jl` already does the same, so this follows precedent. It is still a latent cause of order-dependent `using` failures in later test items, for packages that are only test dependencies.

**Fix:** Guard the activation in the script, for example `isinteractive() || abspath(PROGRAM_FILE) == @__FILE__ ? @quickactivate("TSODSO") : nothing`. Alternatively, move the helpers into a small module file that both the script and the tests include.

---

_Reviewed: 2026-11-06T00:38:10Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
