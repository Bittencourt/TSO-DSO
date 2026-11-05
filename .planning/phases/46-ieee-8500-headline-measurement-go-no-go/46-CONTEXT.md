# Phase 46: IEEE-8500 Headline Measurement (go/no-go) - Context

**Gathered:** 2026-11-05
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase records the **go/no-go decision** for the IEEE-8500 headline run (SCALE-07) and
delivers a **measured IEEE-8500 table run through `Scenario`** (SCALE-08). "Memory-infeasible on
this host" and "refused with certificate" are both accepted measured outcomes. No tolerance, τ,
ε or hybrid floor is changed to obtain any outcome (SC3).

Out of scope:
- memory re-engineering of the ADMM path, such as `HourSplitDsoOpt`, a solver-state pool,
  dropping names, or a GC/allocator rework;
- runs on a bigger machine;
- convergence or exactness fixes at 8500 scale;
- new densities or horizons beyond the points named below.

The phase is additive. Every default path, golden and the knife-edge canary (56 iterations /
−4823.66604824162) stay byte-identical.

</domain>

<decisions>
## Implementation Decisions (user-approved 2026-11-05)

### Go/no-go (SCALE-07): NO-GO from data
- The **headline point** is the one the milestone research named: `:ieee8500` (4,875 buses, full
  MV+LV), ADMM-only, density 0.1, T = 24.
- The decision is made **from the committed Phase-39 attribution**
  (`results/ieee8500_benchmark/memory_attribution.csv`, `point_resources.csv`). It is not re-run
  and not re-engineered:
  - T = 24 peak HWM was 11.75 GiB, above the ~10 GiB GO threshold on the 15 GB host.
  - Anchor delta was 9.296 GiB at 7 iterations, ending in `CertificateError`, SOCP gap ratio 223.7.
  - The components: 122 AgrOpt builds ≈ 4.0 GiB, DSO build ≈ 0.9 GiB, first iterate retained
    ≈ 2.9 GiB, iterates 2..N ≈ 0.65 GiB.
  - Phase 35 measured an earlier peak of 11.52 GiB, and d = 0.25 T = 24 was earlyoom-killed.
- Record **"memory-infeasible on this host"** with a **lower-bounded requirement**, derived only
  from measured numbers: peak ≥ the measured HWM, plus the stated headroom the host needs for
  the OS and baseline load. The derivation is shown, and every number cites its CSV row. No
  lever is claimed to exist.
- The decision record is a committed, dated artifact: a CSV row and/or a markdown/literate
  section next to the existing `docs/literate/ieee8500_scaling.jl`. It states the threshold, the
  measured value, the verdict and the lower bound.

### Measured run (SCALE-08): widen `Scenario` and run the feasible point
- **Widen `SCENARIO_VALID_FEEDERS`** additively from `(:ieee13, :ieee123)` to include `:ieee8500`
  and `:ieee8500_mv` (`src/experiments/Scenario.jl:24`). `build_feeder` in `materialize.jl`
  already dispatches both.
  - The default `Scenario` and every existing selector behave identically.
  - Check the population, price and pf selector compatibility for 8500, including how
    `materialize` builds the 8500 population and density. Any combination 8500 cannot support
    gets an `ArgumentError` guard, not silent behaviour.
- **Run the largest memory-feasible point through `Scenario`/`run_scenario`**: `:ieee8500`,
  ADMM-only, d = 0.1, T = 10 (Phase 39 measured ~5.7–6.2 GiB peak). Commit the six-number table:
  size (buses, branches, houses or aggregators, variables/constraints if cheap), build time,
  solve time, iterations, peak memory (VmHWM/MaxRSS), and the exactness verdict.
  - "Refused with certificate" is the expected and accepted verdict. Phase 35/39 saw a
    `CertificateError` at T = 10, ratio ~569.
- The table also carries the **T = 24 NO-GO row**: status `memory_infeasible`, citing the
  measured peak, with no new run.
- If the `Scenario` path materially differs from the benchmark-harness path, the table states
  it, for example in population construction or default knobs. Any number that is compared with
  the Phase-35/39 harness numbers is labelled as coming from the different path.

### Host-memory hygiene for the run
- The run is **detached and alone**, launched by the orchestrator, never by an executor. It
  uses the existing per-point wrapper pattern (`scripts/run_ieee8500_point.sh`) or an
  equivalent: `--heap-size-hint`, earlyoom awareness, and MaxRSS/oom_source/mem_avail_before
  recording, following the `point_resources.csv` conventions.
- A **pre-flight gate** requires at least 8 GiB of `MemAvailable` before launch. If it fails, or
  earlyoom kills the run, the outcome is recorded as a measured row (MaxRSS, oom_source, mem
  available before). Nothing is ever retuned to make it fit.
- Tests are tiny. The `Scenario` widening is tested on construction/validation and, if
  feasible, on a small 8500-family slice. **No test runs the full 8500 point.** The full suite
  must stay at about its current wall time.

### Claude's Discretion
- Script layout: extend `scripts/benchmark_ieee8500.jl` with a scenario mode, or add a small
  dedicated script. The CSV name and columns follow the established
  `results/ieee8500_benchmark/` conventions. The docs placement is an additive, dated section in
  `docs/literate/ieee8500_scaling.jl` or a new registered page.

</decisions>

<code_context>
## Existing Code Insights

- `src/experiments/Scenario.jl`: `SCENARIO_VALID_FEEDERS` (line 24) and the inner-constructor
  `ArgumentError` validation (around line 134).
- `src/experiments/materialize.jl`: `build_feeder` already handles `:ieee8500` and
  `:ieee8500_mv` (lines 35–52). `_ieee8500_house` builds one house per SX load (around line 273).
- `scripts/benchmark_ieee8500.jl`: density sweep, noise-floor calibration, `--admm-only`, the
  T-horizon floor.
- `scripts/profile_ieee8500_memory_attribution.jl`: `proc_status_kb`, staged GC, keyed CSV upsert.
- `scripts/run_ieee8500_point.sh`: the per-point wrapper (MaxRSS, oom_source and
  mem_avail_before columns → `point_resources.csv`).
- `results/ieee8500_benchmark/`: `point_resources.csv`, `memory_attribution.csv`,
  `density_sweep*.csv`, `socp_gap_report.csv`, `noise_floor_calibration.csv`.
- `docs/literate/ieee8500_scaling.jl`: the existing scaling page, with dated appended sections
  and the headline-point statement around line 181.

## Established Patterns
- Measurement artifacts are committed CSVs plus dated literate docs sections. All numbers are
  computed from the CSV, and pages are registered in `docs/make.jl` and `scripts/README.md`.
- Honesty policy: refusals are status rows, certificates report and never throw in the harness,
  null and infeasible results are stated plainly, and tolerances are never loosened.
- Exports and selectors go through curated lists (`src/TSODSO.jl`, `test/test_exports.jl`).
  The `Scenario` selector tuples are documented constants.

</code_context>

<specifics>
## Specific Ideas
- Phase 40 recorded the memory wall at the 784-house case_a scale. The 8500 NO-GO lower bound
  should be phrased as a requirement on available RAM, not on total RAM.
- Keep the T = 10 run's provenance: git HEAD, Julia version, threads, and the heap-size-hint.

</specifics>

<deferred>
## Deferred Ideas
- Memory levers for a future T = 24 GO: `HourSplitDsoOpt`, a per-hour solver-state pool,
  names off, an AgrOpt pool.
- A bigger-RAM host run of the d = 0.1 T = 24 headline.
- An SCS/first-order diagnostic at the headline point (still untested there).

</deferred>
