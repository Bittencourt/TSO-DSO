---
quick_id: 260822-hld
description: Phase-25 round 2 — thread the ADMM exactness override into the harness, make the noise-floor calibration point configurable, and re-measure the floor at the point it's applied to
date: 2026-08-22
mode: quick
---

# Quick Task 260822-hld: Thread ADMM exactness override + configurable calibration point

## Why

Round 1 (`260822-f0b`) built the `atol_exact`/`rtol_exact` override SEAM on `solve_admm`/
`solve_dso!` but nothing in the harness actually calls it — `run_admm_point` still calls
`solve_admm(...)` with no override, so the final consolidation gate still uses the project
default `atol=1e-6`. The orchestrator's diagnostic run of `--fixture ieee8500 --density 0.1
--t-horizon 10 --solver clarabel` proved this concretely:

    measured ADMM cone gap    = 1.3968e-4
    headline measured floor   = 4.9691e-3   (measured at density=0.05, T=24 — a DIFFERENT point)
    ratio @ atol=1e-6 (today) = 139.7  -> THROWS  (admm_status = ERROR:ErrorException)
    ratio @ atol=floor        = 0.0281 -> PASSES

That same diagnostic also refuted the orchestrator's earlier hypothesis that the sweep's
`ALMOST_OPTIMAL` centralized status was a tolerance-flag problem: `--clarabel-tol` (round 1) DID
apply the fixture-aware `1e-7` default, and it still came back `ALMOST_OPTIMAL`. The reason is
that `CALIBRATION_DENSITY = 0.05` and the calibration's `T = 24` (module-level) do NOT match the
sweep point actually being run (density=0.1, T=10 via `--t-horizon`) — the ladder's "1e-7 is
achievable" conclusion was measured on a different-density, different-horizon problem and does
not transfer. This task fixes the wiring gap (Task A), makes the calibration point configurable
so a floor can be measured at the point it will be applied to (Task B), then measures the real
floor at density=0.1/T=10 and re-runs the point (Task C) — WITHOUT attempting to fix the
`ALMOST_OPTIMAL` centralized status itself, which is a separate, genuine conditioning question
out of this task's scope.

## Context

- `scripts/benchmark_ieee8500.jl` — the harness; both `run_admm_point` (~L448) and the
  calibration mode (`CALIBRATION_DENSITY` ~L224, `run_calibration` ~L237, `run_calibrate_mode`
  ~L306) live here.
- `src/admm/solve_admm.jl` (`solve_admm`, ~L222; `atol_exact`/`rtol_exact` kwargs ~L239-240;
  threaded into the final consolidation `solve_dso!` call at ~L776-777) — the seam round 1 built.
- `src/admm/DsoOpt.jl` (`solve_dso!`, ~L432; `atol_exact`/`rtol_exact` kwargs ~L438-439; gate call
  ~L464) — the seam's actual gate.
- `EXACTNESS_ATOL::Dict{Symbol,Float64}` (~L111-116) — the SAME dict `run_centralized_point`'s
  `exact_verdict` classification already consults (`atol = EXACTNESS_ATOL[fixture_sym]`, ~L647).
  Task A reuses this dict; it does NOT introduce a new tolerance source.
- `results/ieee8500_benchmark/noise_floor_calibration.csv` — the committed ladder. Current
  `ieee8500` floor: `tol=1e-7 -> 0.0049691451` (density=0.05, T=24 provenance, undocumented in the
  CSV itself before this task).
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` items 2/3/4 — item 3 is
  what Task A closes (the wiring half; item 2, excluding near-zero branches from the gap scan,
  stays open and out of scope).
- `test/test_benchmark_ieee8500.jl` — plain `Test.jl` script (NOT a `@testitem`), invoked directly
  via `julia --project=. test/test_benchmark_ieee8500.jl` (~4 min); the regression gate for Tasks
  A and B. It rewrites `results/ieee8500_benchmark/density_sweep.csv` as a side effect
  (`--quick` upserts the `(ieee8500-mv, clarabel)` key only) — restore with `git checkout --` if
  only wall-clock columns moved.

## Tasks

### Task A — thread the exactness override from the harness into `solve_admm`

- **files:** `scripts/benchmark_ieee8500.jl`
- **action:**
  1. Add an `atol_exact::Real` parameter to `run_admm_point`'s signature (after `T_horizon::Int`),
     and pass `atol_exact = atol_exact, rtol_exact = DEFAULT_RTOL` (the harness's existing
     project-default rtol constant, ~L119) into the `solve_admm(...)` call inside it. Update the
     docstring to state: the value passed MUST be the caller's `EXACTNESS_ATOL[fixture_sym]` (a
     MEASURED noise floor), never a literal — this is legitimate ONLY because that dict entry is a
     genuine measurement, and a point whose gap EXCEEDS its fixture's measured floor must still
     throw (T-25-12, certificate-laundering bar — mirrors the exact language already attached to
     `solve_admm`'s own `atol_exact` kwarg in `src/admm/solve_admm.jl`).
  2. In the function's final `merge(...)` call (the one currently producing
     `(; admm_time_s = total_s, admm_peak_rss_delta_mb = peak_delta_mb)`), add
     `admm_atol_used = atol_exact` to the merged NamedTuple — computed unconditionally from the
     caller's argument (not from inside the try/catch), so the column is populated whether the
     solve throws or succeeds.
  3. In `run_sweep_mode`, update the call site (~L668,
     `apoint = run_admm_point(feeder, aggs, λ0, 100.0, time_limit, T_horizon)`) to
     `apoint = run_admm_point(feeder, aggs, λ0, 100.0, time_limit, T_horizon, atol)` — reusing the
     `atol = EXACTNESS_ATOL[fixture_sym]` binding already computed a few lines above for
     `run_centralized_point`'s own `exact_atol_used` column. Do not introduce a second lookup.
  4. Add `admm_atol_used = apoint.admm_atol_used,` to the `row` NamedTuple construction (next to
     the existing `exact_atol_used = atol,` field). Decision (document in-code as a comment above
     the new field): a NEW column, not a reuse of `exact_atol_used`, even though both currently
     read from the same `EXACTNESS_ATOL[fixture_sym]` value — `exact_atol_used` is consulted by a
     pure post-hoc Julia-side classification (`exact_verdict`), while `admm_atol_used` is the value
     that actually controlled whether `solve_admm` threw inside the subprocess. Reusing one column
     for both would silently imply they can never diverge; a future change to either consumer
     could desync them without the CSV ever showing it — this is the same class of silent-lie bug
     round 1's `clarabel_tol_gap` fix closed.
  5. Update the module header comment (CLI usage block, ~L20-35) to mention that ADMM's final
     consolidation gate now uses `EXACTNESS_ATOL[fixture_sym]` (the same value the centralized
     verdict uses), recorded in the new `admm_atol_used` CSV column.
- **verify:**
  <automated>
  Write a throwaway verification script to the scratchpad (NOT committed) that proves the wiring
  end-to-end without paying IEEE-8500 cost: copy `scripts/benchmark_ieee8500.jl`'s source with its
  trailing `main(ARGS)` line stripped, `include_string(Main, ...)` it, then call the harness's own
  `build_feeder`, `generate_profiles`, `density_filtered_population`, `build_price` helpers to
  build the CHEAP `:ieee13` fixture at density=1.0/T=10 (the existing committed CSV shows this
  point ADMM-converges in the low tens of iterations, ~seconds of wall time) and:
    - call `run_admm_point(feeder, aggs, λ0, 100.0, 30.0, 10, 1.0e-30)` (deliberately tiny
      `atol_exact`) and assert `startswith(result.admm_status, "ERROR:")` — the gate must still
      throw under an absurdly tight override, proving Task A did not weaken anything.
    - call `run_admm_point(feeder, aggs, λ0, 100.0, 30.0, 10, EXACTNESS_ATOL[:ieee13])`
      (`EXACTNESS_ATOL[:ieee13] == 1e-6`, byte-identical to `solve_admm`'s own project default)
      and assert `result.admm_status == "converged"` and `result.admm_atol_used == 1.0e-6` —
      proving the plumbing carries the REAL value through in the normal case too, not just in the
      throw case.
  </automated>
  Also run the regression gate: `julia --project=. test/test_benchmark_ieee8500.jl` (10/10 D-16
  goldens must still pass — `--quick` resolves `:ieee8500_mv`, whose `EXACTNESS_ATOL` entry is
  unchanged by this task, so `admm_status` stays `"budget_exceeded"` exactly as before; restore
  `density_sweep.csv` via `git checkout --` if only wall-clock columns moved).
- **done:** `run_admm_point` accepts and forwards `atol_exact`; `run_sweep_mode` passes
  `EXACTNESS_ATOL[fixture_sym]` (never a literal); the CSV gains `admm_atol_used`; the tiny-atol
  throw-check and the real-atol converge-check both pass on the cheap `ieee13` fixture; D-16
  goldens are unaffected.

### Task B — make the calibration point configurable (density + horizon)

- **files:** `scripts/benchmark_ieee8500.jl`
- **action:**
  1. Factor `run_sweep_mode`'s existing `--t-horizon` parse-and-validate block (absent → default,
     present → `parse(Int, ...)` validated against `T_HORIZON_FLOOR`, throwing — never
     clamping — below it) into a shared helper `parse_t_horizon_flag(args, default::Int)::Int`.
     Replace `run_sweep_mode`'s inline block with a call to this helper
     (`T_horizon = parse_t_horizon_flag(args, quick ? T_QUICK : T)`), byte-identical behavior
     (same error message, same floor).
  2. Add `--calibration-density <float>` to calibrate mode: in `run_calibrate_mode`, parse
     `density_str = parse_kv_flag(args, "--calibration-density", nothing)`, then
     `density = density_str === nothing ? CALIBRATION_DENSITY : parse(Float64, density_str)`.
     Default (`CALIBRATION_DENSITY = 0.05`) is unchanged, so today's committed ladder rows for
     `ieee13`/`ieee8500-mv` (not re-measured by this task) remain exactly reproducible.
  3. Make calibrate mode honor `--t-horizon` via the SAME shared helper from step 1:
     `T_horizon = parse_t_horizon_flag(args, T)` (default `T = 24`, module constant — unchanged
     default).
  4. Change `run_calibration`'s signature to
     `run_calibration(fixture_sym, fixture_label, tolerances, density::Real, T_horizon::Int)`,
     replacing its internal `CALIBRATION_DENSITY` and module-level `T` references with the new
     `density`/`T_horizon` parameters (`generate_profiles(; seed = CALIBRATION_SEED, T =
     T_horizon)`, `density_filtered_population(..., density, rng)`). Add `density` and `t_horizon`
     fields to each pushed row: `push!(rows, (; fixture = fixture_label, tol = tol, measured_gap =
     gap, density = density, t_horizon = T_horizon))`. Update `run_calibrate_mode`'s call site to
     pass the two new arguments through.
  5. Handle the CSV backfill for legacy rows (documented in-code, above the merge logic in
     `run_calibrate_mode`): the file currently committed has NO `density`/`t_horizon` columns.
     Every row in it WAS genuinely measured at the calibration mode's then-hardcoded defaults
     (`CALIBRATION_DENSITY = 0.05`, module `T = 24`) — this is documented provenance, not a guess
     (contrast with "mark unknown", which would be dishonest here since the provenance IS known).
     Before the `vcat`, if `!hasproperty(df_old, :density)`, backfill
     `df_old.density = fill(CALIBRATION_DENSITY, nrow(df_old))` and
     `df_old.t_horizon = fill(T, nrow(df_old))` using the CONSTANTS (not the current run's
     `density`/`T_horizon` arguments — those describe only the run in progress). Use
     `vcat(...; cols = :union)` for the merge to tolerate any residual column-set mismatch
     defensively.
  6. Update the module header's calibrate-mode documentation block (~L14-19) to mention
     `--calibration-density` and `--t-horizon`, and their unchanged defaults.
- **verify:**
  - `grep -n "function parse_t_horizon_flag" scripts/benchmark_ieee8500.jl` shows the new shared
    helper exists exactly once.
  - `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee13
    --tolerances 1e-6,1e-8` (cheap, ~1s/rung per the committed CSV) with NO `--calibration-density`/
    `--t-horizon` flags, then `git diff results/ieee8500_benchmark/noise_floor_calibration.csv` —
    confirm the `ieee13` rows' `measured_gap` values are unchanged from the committed CSV
    (`2.579145160095453e-9` at both tolerances) and that `density`/`t_horizon` columns now read
    `0.05`/`24` for those rows (proving the default-path is byte-identical). Confirm the OTHER
    fixtures' rows (`ieee8500-mv`, `ieee8500`) also now carry backfilled `density=0.05`,
    `t_horizon=24` (not blank/NaN) — proving the backfill ran, not just the new-run rows.
  - Restore the CSV afterward via `git checkout --
    results/ieee8500_benchmark/noise_floor_calibration.csv` ONLY once the diff above is confirmed
    to be exactly "new density/t_horizon columns added, ieee13 rows re-measured identically" —
    Task C's run below is the one that should leave the CSV with real new content.
  - `julia --project=. test/test_benchmark_ieee8500.jl` — 10/10 D-16 goldens still pass (this
    task's changes are calibrate-mode-only; `--quick` never invokes `run_calibrate_mode`).
- **done:** `--calibration-density` and `--t-horizon` both work in calibrate mode with unchanged
  defaults; `run_calibration` records `density`/`t_horizon` per row; legacy rows are backfilled
  with their known true provenance (`0.05`/`24`), never silently left implying the new default.

### Task C — measure the floor at the target point, then re-run the ADMM point

- **files:** `results/ieee8500_benchmark/noise_floor_calibration.csv`,
  `results/ieee8500_benchmark/density_sweep.csv`, `scripts/benchmark_ieee8500.jl` (only if the
  measured floor differs materially from the committed one — see step 2 below)
- **action:**
  1. Run the full 5-rung ladder at the ACTUAL target point:
     `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500
     --calibration-density 0.1 --t-horizon 10`. Machine is shared/memory-tight (15 GiB, as little
     as 5 GiB free, ONE compute process at a time) — this exact density/horizon combination was
     already confirmed safe for a SINGLE solve (~5.9 GB peak, no OOM, per deferred-items.md item
     4's T=10 remedy). If observed RSS climbs materially past that during the 5-rung ladder,
     interrupt and re-run with a shorter `--tolerances 1e-6,1e-7,1e-8` instead of the full 5-rung
     default — record whichever ladder actually completed.
  2. Compare the new `ieee8500` floor (density=0.1, T=10) against the committed
     `IEEE8500_EXACT_ATOL = 0.004969145122458496` (density=0.05, T=24 provenance). Decision rule
     (apply exactly, do not improvise a different one):
       - If the new floor is within the same order of magnitude (ratio < ~3x either direction),
         leave `IEEE8500_EXACT_ATOL`/`EXACTNESS_ATOL[:ieee8500]` UNCHANGED; add an in-code comment
         recording the new confirming measurement (value, density=0.1, T=10) alongside the
         existing constant's comment.
       - If the new floor is LARGER by more than ~3x, update `IEEE8500_EXACT_ATOL` to the new
         (larger) measured value, following the file's existing convention exactly (see the
         D-13-fix comment block ~L78-107 for the expected level of detail): document BOTH
         measurements and their (density, T) provenance, and state explicitly that the larger
         value is used so the gate stays conservative for both regimes — never a value picked to
         make one specific point pass (T-25-12).
       - If the new floor is SMALLER by more than ~3x, do NOT tighten `IEEE8500_EXACT_ATOL` (that
         would risk making a genuinely inexact point at the ORIGINAL density=0.05/T=24 calibration
         point pass); instead record both measurements in-code and flag in the SUMMARY that the
         two regimes now have meaningfully different noise floors — this is itself a finding to
         report honestly, not something to paper over by picking whichever number is more
         convenient.
     In EVERY case, state the actual measured number and the decision taken in the SUMMARY —
     never claim "no change needed" without showing the comparison.
  3. Re-run the single target point:
     `julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500 --density 0.1
     --t-horizon 10 --solver clarabel` (single point, `solver=clarabel` skips the unrelated SCS
     comparison; do NOT run the full density grid or `--solver both`). No existing
     `(ieee8500, 0.1, clarabel)` row exists in the committed `density_sweep.csv` (confirmed by
     inspection), so this adds a new row rather than overwriting one — commit the resulting row
     (this is now a genuinely, honestly gated measurement, not a throwaway diagnostic like round
     1's).
  4. Report plainly in the SUMMARY, without hedging:
     - The new floor's exact numeric value and whether/how `IEEE8500_EXACT_ATOL` changed.
     - The resulting row's `termination_status` (expected: still `ALMOST_OPTIMAL` — Task A/B do
       NOT address the centralized conditioning question; explicitly state that no attempt was
       made to fix it).
     - The resulting row's `admm_status` and `admm_atol_used` — state plainly whether the ADMM
       consolidation gate is now PASSED (i.e. `admm_status` is a real status like `"converged"` or
       an honest non-throw outcome, not `"ERROR:ErrorException"`).
- **verify:**
  - `cat results/ieee8500_benchmark/noise_floor_calibration.csv` — new `ieee8500` rows show
    `density=0.1`, `t_horizon=10`, and 5 (or fewer, per step 1's memory-safety fallback)
    `measured_gap` values; other fixtures' rows still show their pre-existing values plus the
    backfilled `density=0.05,t_horizon=24` from Task B.
  - `cat results/ieee8500_benchmark/density_sweep.csv | grep '^ieee8500,0.1,clarabel'` — the new
    row exists with the horizon/solver/density from step 3, and `admm_atol_used` equals whatever
    `EXACTNESS_ATOL[:ieee8500]` resolved to after step 2's decision.
  - `julia --project=. test/test_benchmark_ieee8500.jl` — final combined regression after all
    three tasks land: 10/10 D-16 goldens still pass (the `--quick` path never touches `:ieee8500`
    or calibrate mode).
- **done:** the `ieee8500` noise floor is measured at its own density=0.1/T=10 point (not
  borrowed from the density=0.05/T=24 calibration), `EXACTNESS_ATOL[:ieee8500]` is defensible
  (updated or explicitly justified as unchanged) per the decision rule, the target point is
  re-run and committed, and the SUMMARY states plainly whether the ADMM gate now passes and
  confirms the centralized `ALMOST_OPTIMAL` status was left untouched.

## Constraints

- Do NOT run the full density sweep. Only the single `ieee8500` density-0.1/T=10 point (Task C
  step 3) plus the one calibration ladder Task C names (step 1).
- Do NOT use `allow_almost = true` on any solve whose duals are read — `src/core/status.jl`'s
  final-solve strictness is untouched by this task.
- Do NOT attempt to "fix" the centralized `ALMOST_OPTIMAL` status. It is a separate, genuine
  conditioning question, explicitly out of scope (Task C step 4 must say so plainly).
- Do NOT re-run the true `T=24` headline point (memory wall, separate open item).
- `test/test_benchmark_ieee8500.jl` is a plain `Test.jl` script, NOT a `@testitem` — invoke
  directly (`julia --project=. test/test_benchmark_ieee8500.jl`, ~4 min), never via
  `Pkg.test()`/`@run_package_tests`. It rewrites `density_sweep.csv` as a side effect; if only
  wall-clock columns move, restore with `git checkout --`. This is the regression gate for Tasks A
  and B; Task C's own new row must survive after that gate runs (re-check the row still exists
  post-gate, since `--quick`'s upsert only touches the `(ieee8500-mv, clarabel)` key and must not
  disturb the `(ieee8500, 0.1, clarabel)` row Task C added).
- Machine is shared, 15 GiB total, memory fluctuates (as little as 5 GiB free observed). ONE
  compute process at a time. The density-0.1/T=10 point measured ~3.3-5.9 GB and did not OOM in
  prior runs; watch for anomalies during Task C's ladder specifically (5 sequential solves, not
  just one).
- T-25-12 (certificate-laundering) applies throughout: `EXACTNESS_ATOL` entries and `admm_atol_used`
  must always trace to a genuine measurement at the density/horizon they classify. Never adjust a
  tolerance to make a specific point pass without a fresh measurement backing it.

## must_haves

- **truths:**
  - The ADMM final-consolidation gate on `ieee8500`/`ieee8500-mv` now uses each fixture's own
    measured `EXACTNESS_ATOL` entry, not the project's generic `1e-6` default — provably still a
    real gate (a deliberately tiny override still throws).
  - The CSV honestly distinguishes which atol classified the centralized verdict
    (`exact_atol_used`) from which atol actually gated the ADMM consolidation
    (`admm_atol_used`) — no reader can be misled into thinking one implies the other stayed fixed.
  - A noise floor can be measured at ANY (density, T_horizon) combination, not only the
    hardcoded 0.05/T=24 calibration default — and the committed CSV records which combination
    produced which floor, including honest backfill for pre-existing rows.
  - The `ieee8500` density=0.1/T=10 point has been re-measured with a floor genuinely measured at
    that point (not borrowed from a different density/horizon), and the resulting ADMM/centralized
    statuses are reported honestly, including the still-open `ALMOST_OPTIMAL` conditioning gap.
- **artifacts:**
  - `scripts/benchmark_ieee8500.jl` (`run_admm_point`'s `atol_exact` parameter,
    `admm_atol_used` CSV column, `parse_t_horizon_flag` helper, `--calibration-density` flag,
    `run_calibration`'s `density`/`t_horizon` parameters and CSV columns, legacy-row backfill)
  - `results/ieee8500_benchmark/noise_floor_calibration.csv` (new `density`/`t_horizon` columns,
    backfilled legacy rows, new `ieee8500`/0.1/10 rows)
  - `results/ieee8500_benchmark/density_sweep.csv` (new `admm_atol_used` column, new
    `(ieee8500, 0.1, clarabel)` row)
- **key_links:**
  - `run_sweep_mode` → `run_admm_point(...; atol_exact = EXACTNESS_ATOL[fixture_sym])` →
    `solve_admm(...; atol_exact, rtol_exact = DEFAULT_RTOL)` → `solve_dso!(...; atol_exact,
    rtol_exact)` → `assert_socp_exact!(dso.ctx; atol = atol_exact, rtol = rtol_exact)`
  - `run_calibrate_mode` → `run_calibration(fixture_sym, fixture_label, tolerances, density,
    T_horizon)` → `generate_profiles(; T = T_horizon)` / `density_filtered_population(...,
    density, rng)`
