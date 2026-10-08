---
phase: 35-ieee-8500-scale-after-refactor
reviewed: 2026-10-05T12:00:00Z
depth: standard
iteration: 2
files_reviewed: 12
files_reviewed_list:
  - docs/literate/ieee8500_scaling.jl
  - scripts/benchmark_ieee8500.jl
  - scripts/profile_ieee8500_memory.jl
  - scripts/run_ieee8500_point.sh
  - scripts/run_tests_filtered.jl
  - src/admm/DsoOpt.jl
  - src/admm/solve_admm.jl
  - src/core/errors.jl
  - src/models/exactness.jl
  - test/test_admm_exactness_default.jl
  - test/test_benchmark_ieee8500.jl
  - test/test_tsodso_errors.jl
findings:
  critical: 0
  warning: 5
  info: 5
  total: 10
status: issues_found
---

# Phase 35: Code Review Report (iteration 2)

**Reviewed:** 2026-10-05T12:00:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

This is a re-review of the Phase 35 diff (`03f8dbc..HEAD`), focused on the fix commits `aa897d1..ffe30ce`. I checked each fix against the iteration-1 report (`35-REVIEW.iter2.md`) and the fix report (`35-REVIEW-FIX.md`).

**Prior findings:**

| ID | Verdict | Notes |
|---|---|---|
| CR-01 | Resolved | The bypass diagnostic is gated on `admm_status == "converged"`. Other outcomes are recorded as `DIAGNOSTIC_BYPASS:<status>`. |
| WR-01 | Resolved | The docstrings are rewritten and no longer claim byte-identity. |
| WR-02 | Resolved, no regression | See verification below. |
| WR-03 | Resolved | Attribution is by pid. I checked on this host that the juliaup `julialauncher` `exec`s: `bash -c 'echo $$; exec julia ...'` reports the same pid, so `CHILD_PID` is julia's pid. The regex `(process \|pid[= ])PID([^0-9]\|$)` matches both the kernel format (`Killed process N`, `pid=N,`) and the earlyoom format (`sending SIGTERM to process N`). |
| WR-04 | Resolved | |
| WR-05 | Resolved | Same key as the `started` row. |
| WR-06 | Resolved | The tests now pin the default that reaches the gate, through `meta[:socp_atol_exact]` and the real `solve_dso!` final gate. Both helper ctxs flip their verdict between `nothing` and a flat `1e-6`. |
| WR-07 | Code fixed; data not fixed | The library and harness changes are correct. The committed data still has the problems below (WR-01 and WR-04 of this report). |
| WR-08 | Resolved | |

**WR-02 is arithmetic-identical to the old gate.** `_cone_row` has the same expressions in the same order:
- `lhs`, `rhs`, `gap`;
- `ref_b` with the same `SMAX_NO_LIMIT` branch;
- `atol_b = atol === nothing ? max(τ_solver, ε * ref_b) : atol`;
- `tol = atol_b + rtol * max(abs(lhs), abs(rhs))`;
- `gap / tol`.

The old code computed `maxratio = max(maxratio, gap / tol)` inline. Now `row.ratio` is the same `gap / tol` and is folded the same way. Julia does not reassociate floating point without `@fastmath`, so the verdict, `maxgap`, `maxratio` and the message are unchanged. NaN propagation through `max` is also unchanged. `_socp_head_branch` is the same `findfirst` predicate.

**WR-07 keeps existing constructors and messages unchanged.**
- `CertificateError(msg; kind)` still works, and the explicit outer method keeps `CertificateError(msg, kind)` working.
- `showerror` still prints only `e.msg`, so every existing message is byte-identical.
- The rethrow in `solve_admm` reuses `err.msg`/`err.kind` and fires only when `iterations === nothing`. Every in-tree constructor leaves it `nothing`, which I checked by grep.

**New problems are in the evidence chain, not the library:**
- The docs' Phase-35 comparison table cites numbers ("8 ADMM iterations", "about 5.9 GB", "151/441 MB") without naming the row or fixture they come from. Some come from a different fixture, and the units are mixed.
- The committed `density_sweep.csv` had its `admm_iters` column permanently coerced to Float by the NaN rows.
- `hybrid_diagnostic.csv` and `memory_profile.csv` use upsert keys that can mix runs or fixtures.

## Warnings

### WR-01: Docs table's "ADMM iterations 8" (and other v3.0/Phase-35 cells) are not traceable to the cited rows

**File:** `docs/literate/ieee8500_scaling.jl:213-241` (table at 236-241, source list at 216-217)
**Issue:** Section 3's Phase-35 column describes the `p35-head-d0.1-T10` run (`ERROR:CertificateError`, 287 s, 6.21 GB) and gives "ADMM iterations | 8". That run's committed `density_sweep.csv` row has `admm_iters = NaN` (written before WR-07). The only harness-measured 8 for Phase 35 is the separate `p35-diag-d0.1-T10` `DIAGNOSTIC_BYPASS` run (solver `admm_bypass`, `atol_exact = Inf`). Two other problems compound this:
- The page names its sources as `{hybrid_diagnostic,point_resources,memory_wall_recharacterization}.csv`. None of those contains a harness-recorded iteration count. The only one is a hand-typed free-text cell in `memory_wall_recharacterization.csv` ("converged 8 iters"), and it is attached to the *head* row, so it attributes the bypass run's count to the refused run. Plan 35-03 explicitly required stating that the iteration count is sourced from the diag row. The page does not.
- The v3.0 column is also ambiguous. The same page loads `density_sweep_full.csv` and prints the v3.0 IEEE-8500 d=0.1 T=10 point as `budget_exceeded`, 6 iterations, 153 s. The table's "8 / 227 s" comes from a *different* v3.0 row in `density_sweep.csv` (`converged`, 8.0, 227.4 s). That row was certified under a flat `admm_atol_used = 0.00497`, about 5000x looser than `1e-6`. The table shows only its centralized status, so a reader cannot tell that the v3.0 vs Phase-35 status change is partly a gate-tolerance change.
- Other figures also come from files the source list omits: "287 s" and "delta 4.67 GB" come from `density_sweep.csv`; `4.4e-9` comes from `density_sweep.csv:diag_loss_impact_max`, since the 20 rows in `hybrid_diagnostic.csv` max out at `2.9e-10`; "about 5.9 GB" for v3.0 appears in no committed CSV.

**Fix:** Name the source row for each cell, for example: "ADMM iterations: 8 (from `density_sweep.csv` row `run_label = p35-diag-d0.1-T10`, the gate-bypassed re-run of the same point; the refused head row predates WR-07 and records NaN)". Do the same for the v3.0 column (`density_sweep.csv` 25-08 row, flat `atol_exact = 4.97e-3`) and say why it differs from the `density_sweep_full.csv` row printed above. Add `density_sweep.csv` and `memory_profile.csv` to the source list and give a source for "about 5.9 GB" or drop it. Better still, re-run `p35-head-d0.1-T10` with the WR-07 code so the head row carries its own count.

### WR-02: The memory-profile figures come from the MV fixture but are compared against full IEEE-8500 loop deltas

**File:** `docs/literate/ieee8500_scaling.jl:255-257`; `scripts/profile_ieee8500_memory.jl:45, 85`
**Issue:** `profile_ieee8500_memory.jl` defaults `--fixture` to `ieee8500-mv` (2,521 buses). The committed profile runs passed no `--fixture`: `point_resources.csv` records the args for `p35-prof-s2`/`p35-prof-s3` as `--density 0.1 --t-horizon 10 --stage N`. So the "+151 MB build / +441 MB first optimize" figures are for the MV fixture. The docs place them beside "the whole T = 10 loop adds 4.67 GB", which is measured on the 4,875-bus `ieee8500` fixture, and use the comparison to name "the dominant consumer" and to justify "No `src/` memory mitigation was adopted". The fixture is not stated anywhere, and `memory_profile.csv` has no `fixture` column. Its upsert key `(density, T, stage, name)` (line 85) also lets a later `--fixture ieee8500` profile silently overwrite the MV rows, or the reverse.
**Fix:** Add `fixture = fixture_str` to each `ROWS` entry and to the upsert key. Then either re-profile with `--fixture ieee8500` or state in the docs that the 151/441 MB figures are for `ieee8500-mv`. The conclusion probably still holds, because even doubled per-build figures are far below 4.67 GB, but it has to be stated on matched fixtures.

### WR-03: Mixed and mislabelled memory units in the published memory-wall evidence

**File:** `docs/literate/ieee8500_scaling.jl:240, 245-252`
**Issue:**
- "6.21 GB", "12.08 GB" and "12.64 GB" are `/usr/bin/time` `peak_rss_kb` values, which are KiB, divided by 10^6. That is neither GB nor GiB: 6205808 KiB is 6.35 GB or 5.92 GiB.
- "delta 4.67 GB" is 4672.8 MiB divided by 1000.
- "earlyoom SIGTERM at 10.6 GiB anon RSS" does not match the committed evidence. `runs/p35-head-d0.25-T24.oom_earlyoom` says `VmRSS 10641 MiB`, which is 10.39 GiB of VmRSS, not anon RSS.
- The v3.0 "about 5.9 GB" has no stated unit source. If it is GiB, the "+5%" growth reported in 35-03-SUMMARY and implied by the table is a units artifact (5.92 GiB vs 5.9).

The memory wall ("between density 0.1 and 0.25 at T = 24 on a 15.9 GB host") is a quantitative thesis claim, so each value must use a consistent unit.
**Fix:** Convert every figure from its raw unit (KiB → GiB `/2^20`, MiB → GiB `/2^10`) and label it GiB. Quote the earlyoom value as `VmRSS 10641 MiB (10.4 GiB)`. Restate the v3.0 peak with its source and unit, or drop the comparison.

### WR-04: The committed `density_sweep.csv` `admm_iters` column is now Float for every row, and the WR-07 fix cannot repair it

**File:** `scripts/benchmark_ieee8500.jl:604-606, 734-746`; `results/ieee8500_benchmark/density_sweep.csv`; `docs/literate/ieee8500_scaling.jl:152`
**Issue:** At `03f8dbc`, `admm_iters` held Int text (`4`, `8`, `-1`). The two Phase-35 NaN rows made `CSV.read` infer Float64, and `upsert_sweep_rows` rewrote the whole file. Every historical row now reads `4.0`, `8.0`, `-1.0`.
- WR-07 makes the harness emit Int `-1`/`r.iters`, but `upsert_sweep_rows` still does `vcat(old Float64 column, new Int column)`. That promotes to Float64, so all future rows are written as `8.0` too.
- The fix report's claim that "the column is no longer an Int/NaN mix" is therefore false for the committed artifact.
- The docs parser `something(tryparse(Int, ...), -1)` turns `"8.0"` into `-1`. It reads `density_sweep_full.csv` today, but that file is the documented regeneration target (docs line 116), so pointing the parser at a refreshed CSV would silently print -1 for every iteration count.

**Fix:** In `upsert_sweep_rows`, normalize before writing:
```julia
if hasproperty(df_final, :admm_iters)
    df_final.admm_iters = [ismissing(x) ? missing :
        (x isa AbstractFloat && !isfinite(x)) ? -1 : Int(x) for x in df_final.admm_iters]
end
```
Then re-run the upsert once to repair the committed file, mapping NaN to -1. Alternatively, make the docs parser accept `tryparse(Float64, ...)` and convert.

### WR-05: `hybrid_diagnostic.csv` upsert mixes runs, and the converged-bypass path is untested

**File:** `scripts/benchmark_ieee8500.jl:913-944`; `test/test_benchmark_ieee8500.jl:166-174`
**Issue:** The diagnostic upsert key is per row: `(fixture, density, T_horizon, b, t)` (lines 935-937). Rows of an earlier run of the same point whose `(b,t)` is not in the new run's top-N survive. A second run with a different worst set, or a smaller `--topn`, therefore leaves a file mixing two runs' rows for one point, distinguishable only by `run_label`. Since CR-01, a later non-converged bypass of the same point writes no diagnostic rows and also leaves the earlier converged run's rows in place. `density_sweep.csv` then says `DIAGNOSTIC_BYPASS:budget_exceeded` with `diag_max_ratio = NaN`, while `hybrid_diagnostic.csv` still holds ratios for that point. The committed file also predates the new `admm_status` column, so old rows get `missing` there. Test (f) covers only the non-converged branch: no test runs the converged branch, which carries the new `admm_status` column, the `hr[1]` worst-row choice and the CSV upsert.
**Fix:** Key the replacement by point. Drop every old row with the same `(fixture, density, T_horizon)` before appending, and do this even when the new run is not converged, so stale ratios cannot outlive a re-run. Add a harness test of the converged bypass branch, for example on `ieee13 --admm-only --admm-diagnostic-bypass` (which converges quickly). It should assert the `admm_status` column and that a second run with a smaller `--topn` leaves exactly `topn` rows for the point.

## Info

### IN-01: The "(2e-7, 1e-6] now raises" phrasing overstates the stricter region

**File:** `src/admm/DsoOpt.jl:543`; `src/admm/solve_admm.jl:191-193`; `docs/literate/ieee8500_scaling.jl:223` (iteration-1 IN-01, unchanged)
**Issue:** A gap in (2e-7, 1e-6] raises only when it exceeds `max(2e-7, 1e-9·ref_b) + rtol·|cone|`. For `200 < ref_b < 1000` the floor already sits between 2e-7 and 1e-6, and the `rtol` term is ignored in the statement.
**Fix:** Say "a gap above `atol_b + rtol·|cone|` (as low as 2e-7) now raises".

### IN-02: Stale "byte-identical / duplicates the gap loop" comments after the `_cone_row` refactor

**File:** `src/models/exactness.jl:302-303, 345`
**Issue:** The `socp_relaxation_gap`/`socp_gap_report` comments still say `assert_socp_exact!` is "left BYTE-IDENTICAL" and that they duplicate "the gap loop". The loop body now lives in `_cone_row`. Both functions still carry their own third and fourth copies of the `lhs`/`rhs`/`gap` arithmetic (lines 335-336), which is the same drift hazard WR-02 removed for `hybrid_ratios`.
**Fix:** Update the comments, and optionally reuse `_cone_row(...).gap`.

### IN-03: Harness test (f) depends on `--quick` always ending `budget_exceeded`

**File:** `test/test_benchmark_ieee8500.jl:166-174`
**Issue:** The `budget_exceeded` outcome is driven by a wall-clock limit. On a faster host the point could converge, and then (f) fails and writes `hybrid_diagnostic.csv`. The existing golden `admm_iters == 1` shares this assumption.
**Fix:** Force the outcome with `--time-limit` set very small for (f).

### IN-04: The committed `point_resources.csv` `oom_source` values predate the WR-03 attribution rule

**File:** `results/ieee8500_benchmark/point_resources.csv` (row `p35-head-d0.25-T24`)
**Issue:** That row's `earlyoom` value came from the old `RC == 143` heuristic, and no `.pid` file exists to back it. The earlyoom line names pid 2048487 `"julia"`, which is plausible but unverified.
**Fix:** Note in the docs or CSV that pre-WR-03 rows were attributed heuristically.

### IN-05: The test helper builds the internal `DsoOpt` positionally

**File:** `test/test_admm_exactness_default.jl:44`
**Issue:** `TSODSO.DsoOpt(model, ctx, pag, pag, p_import, Int[], 1, ctx.feeder, 1.0, [0.0])` depends on the field order of a 10-field internal struct. A field addition or reorder breaks the WR-06 regression test with a confusing `MethodError`.
**Fix:** Add a small internal test constructor, or a keyword-based helper, next to `DsoOpt`.

---

_Reviewed: 2026-10-05T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
