---
quick_id: 260822-oi7
description: Build a per-branch SOCP cone-residual diagnostic and use it to pin WHY the IEEE-8500 SOCP relaxation is inexact — structural (modeling convention), physical (reverse flow), or numerical (conditioning)
date: 2026-08-22
status: complete
commits:
  - feb9951 (Task 1 — additive socp_gap_report in src/models/exactness.jl)
  - 024c0c2 (Task 2 — --gap-report diagnostic mode on scripts/benchmark_ieee8500.jl, includes point (d) smoke-test row)
  - (this commit) (Task 3 — measure points (a)/(b)/(c), analysis, deferred-items.md Item 5, this SUMMARY)
---

# Quick Task 260822-oi7 — Summary

Built `socp_gap_report` (`src/models/exactness.jl`, additive, `assert_socp_exact!`/
`socp_relaxation_gap` byte-identical) — a per-branch/per-time SOC-cone-residual diagnostic — and a
new `--gap-report` mode on `scripts/benchmark_ieee8500.jl` that runs it centralized-only at any
(fixture, density, T, tol) point, joins bus names + D-13 near-ideal-edge membership for the
IEEE-8500 fixtures, and writes a point-keyed `results/ieee8500_benchmark/socp_gap_report.csv`.
Measured all 4 discriminating points named by the plan and applied the decision rubric.

**VERDICT: STRUCTURAL.** The inexactness is driven by a small set of genuinely near-zero-impedance
real LV branches — headlined by `"L2674047"->"M1142828"` (`r ≈ 4.8e-5 Ω`, `r_pu ≈ 1.5e-7`, an order
smaller than the D-13 near-ideal convention) — that starve the welfare objective's `r·l` loss-cost
gradient. This is the SAME mechanism as the already-fixed busbar-tie connector
(`deferred-items.md` Item 1), but a DIFFERENT, uncatalogued branch (not among the 43
`IEEE8500_REGULATOR_EDGES`). Reverse flow co-occurs at this branch but is a non-discriminating
correlate (uniformly ~90-100% present even on the fully-exact `ieee13` control and the exact
`ieee8500-mv` point), so PHYSICAL is not favored. NUMERICAL is not favored either — offenders are
tightly concentrated, not scattered, and the (b)-vs-(c) controlled comparison shows the SAME branch
simply worsening with density rather than a new offender set appearing. Full evidence and rubric
application: `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` Item 5.

## What changed

### Task 1 — `socp_gap_report` (`src/models/exactness.jl`)

Additive-only sibling of `assert_socp_exact!`/`socp_relaxation_gap`. Re-walks the identical
per-branch/per-time gap loop and returns the `topn` worst `(branch, time)` rows with `r_pu`, `x_pu`,
`l`, `v_from`, `P`, `Q`, `gap`, `ratio` (the same WR-01 combined bound), `reverse_flow` (`P<0`), and
`loading` (`missing` when `smax == SMAX_NO_LIMIT`). `git diff -U0` confirms exactly ONE removed
line (the old `export`), proving both existing functions' bodies are untouched. Inline regression
(bypassing the TestItemRunner trap) on `ieee13_modified()`, `T=24`: `socp_gap_report`'s top-1 `gap`
equals `socp_relaxation_gap`'s scalar exactly (`3.254808623185341e-8`).

### Task 2 — `--gap-report` mode (`scripts/benchmark_ieee8500.jl`)

New `run_gap_report_mode`, centralized-only (no ADMM), reusing `FIXTURE_MAP`,
`density_filtered_population`, `DEFAULT_CLARABEL_TOL_GAP`, `T_HORIZON_FLOOR`, `_SWEEP_SEED` so a
`--gap-report` point is directly comparable to the density-sweep mode's own measurement at the same
(fixture, density, T, tol). Joins bus names (`ieee8500_relabel_map`/`ieee8500_mv_relabel_map`) and
D-13 near-ideal-edge membership (`TSODSO.IEEE8500_REGULATOR_EDGES`) in the script layer only —
`exactness.jl` stays fixture-agnostic. Writes/upserts `results/ieee8500_benchmark/
socp_gap_report.csv`, keyed by a `point` column so re-runs overwrite (not duplicate). `main(args)`
gained a new `elseif has_flag(args, "--gap-report")` branch; existing `--calibrate-noise-floor` and
default sweep modes are provably unaffected — `julia --project=. test/test_benchmark_ieee8500.jl`:
10/10 D-16 goldens pass, model dims/termination/ADMM-iter counts byte-identical. Only the last
row's wall-clock columns moved in `density_sweep.csv`; restored via `git checkout --`. Smoke-tested
on `ieee13, density=1.0, T=24, tol=1e-8` (also serves as discriminating point (d)) — 20 rows, top-1
`gap=1.928035e-8` matches the existing `density_sweep.csv` `exact_maxgap` for `ieee13,1.0,both`.

### Task 3 — measure the 4-point discriminating set, analysis, verdict

Ran the remaining 3 points one at a time (`free -h` checked before each; never concurrent):

| Point | termination_status | top-1 `gap` | matches `density_sweep.csv`? | verdict vs fixture atol |
|---|---|---|---|---|
| (a) `ieee8500`, density=0.1, T=10, tol=1e-6 | OPTIMAL | 0.0325015512 | yes (3.250155e-2) | INEXACT |
| (b) `ieee8500-mv`, density=0.1, T=24, tol=1e-8 | OPTIMAL | 0.0005781162 | yes (5.781162e-4) | EXACT |
| (c) `ieee8500-mv`, density=0.25, T=24, tol=1e-8 | OPTIMAL | 0.0037728310 | yes (3.772831e-3) | INEXACT |
| (d) `ieee13`, density=1.0, T=24, tol=1e-8 (control) | OPTIMAL | 1.928035e-8 | yes (1.928035e-8) | EXACT |

All 4 top-1 gaps reproduce the already-committed `density_sweep.csv` `exact_maxgap` values to full
precision — confirms `socp_gap_report` computes the identical quantity `assert_socp_exact!` does.

**Structural signal:** (a)/(b)/(c) — 100% of top-20 offenders sit at `r_pu ~ 1e-7` pu (smaller than
the D-13 convention's `3e-4` pu), none flagged `is_near_ideal` (not among the 43 catalogued D-13
edges). (b) and (c): all 20/20 rows are the literal SAME branch (`"L2674047"->"M1142828"`, `r_pu`
bit-identical). (a): that same branch accounts for 10/20 rows; the rest split across two other
near-zero-`r` branches. (d) control: 0% near-ideal-scale, ordinary `r_pu ∈ [0.15, 0.3]` pu.

**Physical signal (non-discriminating):** `reverse_flow` fraction is 100%/100%/100%/90% across
(a)/(b)/(c)/(d) — uniformly high everywhere, including the fully-exact control and the exact `(b)`
point, so it fails the rubric's "markedly higher on inexact points" test.

**Cross-point fingerprint:** the SAME branch (`"L2674047"->"M1142828"`) dominates or co-dominates
all THREE IEEE-8500-family points regardless of density/horizon/tolerance — identical fingerprint
pattern to the already-resolved busbar-tie connector (Item 1), a different branch.

**(b)-vs-(c) controlled comparison:** same fixture/T/tol, only density changed. Offender identity,
`r_pu`, `reverse_flow` all IDENTICAL between (b) and (c); the gap simply grew ~6.5x with density —
the SAME branch worsening, not a new offender set appearing.

Appended "Item 5" to `deferred-items.md` (items 1-4 untouched) with the full evidence table, rubric
application, and the explicit VERDICT sentence; cross-referenced still-open Item 2.

## Verification

| Check | Result |
|---|---|
| `git diff -U0 src/models/exactness.jl \| grep -E '^-[^-]'` | exactly one line (old `export`) |
| Inline regression: `socp_gap_report` top-1 == `socp_relaxation_gap` on `ieee13_modified()` | `3.254808623185341e-8`, exact match |
| `julia --project=. test/test_benchmark_ieee8500.jl` | 10/10 D-16 goldens pass |
| `density_sweep.csv` drift after goldens run | only wall-clock columns on the unrelated `ieee8500-mv,0.1,clarabel` row; restored via `git checkout --` |
| Smoke test `--gap-report --fixture ieee13 --density 1.0 --t-horizon 24 --clarabel-tol 1e-8` | 20 rows, top-1 gap 1.928e-8 matches `density_sweep.csv` |
| `wc -l results/ieee8500_benchmark/socp_gap_report.csv` | 81 (4×20 + header) |
| `grep -c "^### Item 5" deferred-items.md` | 1 |
| `grep VERDICT deferred-items.md` | present, "STRUCTURAL" |
| All 4 points' one-process-at-a-time memory discipline | `free -h` checked before every invocation; no OOM |

## Deviations from Plan

None — plan executed exactly as written. `assert_socp_exact!`/`socp_relaxation_gap` remain
byte-identical; no tolerance or gate default changed anywhere in this task.

## Issues Encountered

None. All 4 points solved `OPTIMAL` on the first attempt; no `ALMOST_OPTIMAL`/timeout/OOM.

## Next Phase Readiness

- `socp_gap_report` and `--gap-report` are now reusable diagnostic tools for any future
  near-zero-impedance root-cause investigation on any fixture.
- Item 2 (whether `exactness.jl` should special-case near-zero-impedance branches) remains OPEN —
  this task's finding sharpens its scope: the offending class is broader than the 43 catalogued
  D-13 edges and may include other uncatalogued near-zero-real-impedance LV service-drop segments
  in the vendored IEEE-8500 data. A future plan could grep
  `IEEE8500_MV_BRANCH_RX_OHMS`/the LV impedance tables for other `r < 1e-4 Ω`-scale entries to
  scope the full extent of this class before deciding whether/how `exactness.jl` should special-case
  it.
- No gate, tolerance, or production behavior changed by this task — it is purely diagnostic.

## Known Stubs

None — no UI/data-rendering stubs; this is a measurement/diagnostic quick task.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface introduced. `--gap-report`
is a read-only, centralized-only diagnostic CLI mode on an existing offline benchmark script.

## Self-Check: PASSED

- FOUND: commit `feb9951`
- FOUND: commit `024c0c2`
- FOUND: `src/models/exactness.jl` (`socp_gap_report` present)
- FOUND: `scripts/benchmark_ieee8500.jl` (`run_gap_report_mode`, `--gap-report` dispatch)
- FOUND: `results/ieee8500_benchmark/socp_gap_report.csv` (81 lines)
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` (Item 5 appended)
- FOUND: `.planning/quick/260822-oi7-pin-ieee-8500-socp-inexactness-mechanism/260822-oi7-SUMMARY.md`
