---
phase: 35-ieee-8500-scale-after-refactor
reviewed: 2026-10-05T13:00:00Z
depth: standard
iteration: 3
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
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 35: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-05T13:00:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

This is a re-review of the Phase 35 diff (`03f8dbc..HEAD`), focused on the iteration-2 fix commits `aa6277e`, `85d2fe9`, `037b0b1`, `8d2c395` and `c5b5468`. None of these commits touches `src/`, so the library verdicts from iteration 2 still hold: the gate is arithmetic-identical, `CertificateError` is backward-compatible, and the WR-06 tests pin the default. This pass checked the harness and profiler code changes, the new test (h), and every figure that the rewritten docs section quotes from the committed `results/ieee8500_benchmark/` files.

**Prior findings (iteration 2):**

| ID | Verdict | Evidence |
|---|---|---|
| WR-01 | Resolved | Every number in docs sections 2–4 matches its named row; see the spot-check list below. The v3.0 row is byte-identical to its state at `262c983`. That commit's message confirms the gap of 1.3968e-4 under the flat gate, the 8 iterations and `admm_atol_used = 0.0049691`. The 1200 s budget comes from `748fc50`. |
| WR-02 | Resolved, with one new attribution problem (WR-01 below) | `memory_profile.csv` now has a `fixture` column. The MV rows are backfilled correctly (`p35-prof-s{2,3}` passed no `--fixture`, and the profiler default was already `ieee8500-mv`). The `ieee8500` rows match `runs/p35-prof-ieee8500-s3.time` (stage-3 VmHWM 2,515,692 = `Maximum resident set size`). |
| WR-03 | Resolved, with one carried-over error (WR-02 below) | All converted values check out: 6205808/2^20 = 5.92, 12079316/2^20 = 11.52, 12636180/2^20 = 12.05, 4672.77/1024 = 4.56, 10409.89/1024 = 10.17, 5154.18/1024 = 5.03, 3200.44/1024 = 3.13, 10641/1024 = 10.4, 15908/1024 = 15.5, 6699480/2^20 = 6.39, 5.9e9/2^30 = 5.49, +0.3%/+8%. |
| WR-04 | Resolved | Diffing `density_sweep.csv` between `ffe30ce` and `HEAD` cell by cell shows only `admm_iters` cells changing: 14 `X.0 → X` and 2 `NaN → -1` (the two pre-WR-07 head rows). No other cell changed and the row count is the same (17). `normalize_admm_iters!` runs on every write, and the docs parser `iters_cell` accepts `8`, `8.0`, `NaN` and `""`. |
| WR-05 | Resolved | `replace_diagnostic_rows` replaces rows per `(fixture, density, T_horizon)`, including on non-converged re-runs. Test (h) covers the converged branch and the `--topn` shrink. Test (f) still passes (no file is created when there is nothing to write). |

**Spot-checked docs figures, all correct against the named source:**
- **Hybrid diagnostic rows:** 568.95, b = 1325, t = 3, `r_pu` 2.40e-6, gap 1.21e-4, `atol_b` 2e-7, minimum ratio 289.06, maximum `loss_impact` 2.9e-10.
- **Sweep diagnostic columns:** `diag_loss_impact_max` 4.4e-9.
- **Process wall times** (`runs/*.time`): 335 s (5:35.13), 728 s (12:07.62), 213 s (3:33.02).
- **`admm_time_s`:** 287 / 678 / 227 s.
- **Profile deltas:** stage 1→2 = 238,072 KiB (0.23 GiB); stage 2→3 = 929,700 KiB (0.89 GiB); MV 0.14 / 0.42 GiB.
- **Gate ratios:** 4.97e-3 / 1e-6 ≈ 4,969, quoted as "about 5,000x".
- **v3.0 `density_sweep_full.csv` row:** `budget_exceeded`, 6 iterations, 153.3 s, `tol_gap` 1e-8, "~5.9GB".

Two problems remain in the memory-wall evidence chain. Both are attributions that the data do not support, not arithmetic errors.

## Warnings

### WR-01: "The rest is state kept across iterations" is not supported by the profile, because AgrOpt construction is part of the loop delta but was never measured

**File:** `docs/literate/ieee8500_scaling.jl:297-305`; `results/ieee8500_benchmark/memory_wall_recharacterization.csv:7-8` (`dominant_consumer` column)
**Issue:** The `037b0b1`/`85d2fe9` rewrite adds a quantitative conclusion: "One build plus one solve therefore accounts for about a quarter of the T = 10 loop's growth; the rest is state kept across iterations". It keeps the earlier claim that "the dominant consumer is the per-hour DSO solver state retained across the ADMM loop". The comparison does not isolate that.
- **The loop delta covers more than the DSO.** `admm_peak_rss_delta_mb` is `Sys.maxrss()` after `solve_admm` minus `Sys.maxrss()` before it (`scripts/benchmark_ieee8500.jl:580, 619-621`). So the delta includes everything `solve_admm` allocates, not only DSO iterations:
  - building **one AgrOpt per aggregator** (`n_agg = 122` at this point; `src/admm/solve_admm.jl` docstring, "one `build_agr_opt` per aggregator");
  - their first solves;
  - the final `check_exact = true` consolidation.
- **The profile cannot split that remainder.** The profiler has a stage 5 (`after_agr_opts`, `scripts/profile_ieee8500_memory.jl:79-82`), but no committed run reached it. The `ieee8500` rows stop at stage 3. The remaining ~3.4 GiB therefore cannot be assigned to "state kept across iterations" rather than to 122 AgrOpt models and solver workspaces.
- **The profile data cut against the "dominant" claim.** One DSO build plus solve is ~25% of the delta. Nothing measured shows the DSO is the dominant consumer.
- **The metrics differ.** The profile figures are VmRSS deltas between stages. The loop delta is a peak (HWM) delta. Measured as VmHWM from stage 1 to stage 3, the profile gives 1,261,504 KiB (1.20 GiB), not 1.12 GiB.
- **"Linear in nodes" is unmeasured.** `memory_wall_recharacterization.csv` repeats "ADMM-loop retained per-hour DSO solver state (linear in T and in nodes)". The "in nodes" part was never measured; only one density completed at T = 24.

This feeds the decision "No `src/` memory mitigation was adopted" and the ARCH-10 memory-wall narrative, so the attribution needs to be accurate.
**Fix:** Either measure the remainder: run `scripts/run_ieee8500_point.sh p35-prof-ieee8500-s5 -- --fixture ieee8500 --density 0.1 --t-horizon 10 --stage 5` and state the stage 3→5 AgrOpt contribution. Or weaken the text to what is measured:
```
# One DSO build plus its first solve accounts for about a quarter of the T = 10 loop's peak growth
# (VmRSS 1.12 GiB; VmHWM 1.20 GiB). The remainder (AgrOpt construction for the 122 aggregators,
# their solves, per-iteration state, and the final consolidation) was not decomposed; no single
# dominant consumer is established by this profile.
```
Make the same change to the `dominant_consumer` cells of the head rows, and drop "and in nodes".

### WR-02: The Phase-25 headline anon-rss range includes an `ieee8500-mv` kill

**File:** `results/ieee8500_benchmark/memory_wall_recharacterization.csv:2` (row `phase25-head-d0.1-a`, `notes` column)
**Issue:** The `8d2c395` unit fix rewrote this cell as "kernel anon-rss 6991636-9753068 KiB (6.67-9.30 GiB) across the density_sweep_full.csv OOM rows". The row describes the 4,875-bus `ieee8500` headline fixture, but 9,753,068 KiB is the anon-rss of the **`ieee8500-mv` density 1.0** OOM row in `density_sweep_full.csv`. The three `ieee8500` OOM rows record 6,991,636, 8,548,328 and 8,393,224 KiB, which is 6.67–8.15 GiB. The pre-fix text "6.8-9.75" had the same cross-fixture mix; the fix converted its units but kept the wrong upper bound. This is the same class of defect as iteration-2 WR-02: a figure from one fixture attributed to the other.
**Fix:**
```
kernel anon-rss 6991636-8548328 KiB (6.67-8.15 GiB) across the three ieee8500 OOM rows of density_sweep_full.csv
```
If the 15.5 GiB host context needs the all-fixture maximum (9.30 GiB, `ieee8500-mv` d = 1.0), quote it separately with its fixture named.

## Info

### IN-06: `memory_wall_recharacterization.csv` still calls `admm_time_s` "wall"

**File:** `results/ieee8500_benchmark/memory_wall_recharacterization.csv:7` (row `p35-head-d0.1-T24`, `notes` column: "677 s wall")
**Issue:** The WR-01 fix split process wall time (728 s, `runs/p35-head-d0.1-T24.time`) from `admm_time_s` (677.5 s, which the docs round to 678 s). This CSV cell still labels the `admm_time_s` value as "wall" and truncates it to 677, so the committed evidence contradicts the docs table at `docs/literate/ieee8500_scaling.jl:292`.
**Fix:** Write `admm_time_s 678 s; process wall 728 s`.

### IN-07: The docs say the head row "records" -1, but that value came from the repair, not the harness

**File:** `docs/literate/ieee8500_scaling.jl:259`
**Issue:** "the head row was written before WR-07 and records the unknown sentinel `-1`". The harness wrote `NaN`. The `-1` comes from the one-off `normalize_admm_iters!` repair in `aa6277e`. This is minor, but this section is explicitly about provenance.
**Fix:** "...was written before WR-07 with `NaN`, normalized to the unknown sentinel `-1` by the WR-04 repair (`aa6277e`)".

### IN-08: Stale-row removal on a non-converged re-run is untested, and the committed diagnostic file predates its schema

**File:** `scripts/benchmark_ieee8500.jl:990-996`; `test/test_benchmark_ieee8500.jl:184-208`; `results/ieee8500_benchmark/hybrid_diagnostic.csv`
**Issue:** Test (h) covers the converged replace path. The other half of the WR-05 fix is not exercised: a non-converged bypass of a point that already has rows must delete them (`replace_diagnostic_rows(..., nothing)`). Test (f) runs in a fresh directory, so it only covers the case where no file exists. Separately, the committed `hybrid_diagnostic.csv` still has no `admm_status` column, as the fix report acknowledges. Its 20 rows come from the converged `p35-diag-d0.1-T10` run, but the file does not say so.
**Fix:** In (f), seed `dir_f/hybrid_diagnostic.csv` with one row for the `--quick` point plus one row for another point. Assert that after the run only the other point's row remains. Optionally add an `admm_status = converged` column to the committed file.

## Carried over (not re-raised)

Iteration-2 IN-01 through IN-05 are still open and unchanged; no fix commit touched them, and none is worse. One addition to IN-01: `docs/literate/ieee8500_scaling.jl:234` ("stricter ... except on branches with `smax` of 32-99 pu") also leaves out the looser case on unlimited branches whose head flow is above ≈ 31.6 pu. `src/admm/solve_admm.jl:191-196` and `src/admm/DsoOpt.jl:541-545` both state that case correctly.

---

_Reviewed: 2026-10-05T13:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
