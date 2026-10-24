---
phase: 40-784-house-thesis-population
plan: 02
subsystem: measurement-harness
tags: [julia, admm, scaling-report, threads-sweep, population-ladder, csv-artifacts, honesty-policy]

# Dependency graph
requires:
  - phase: 40 plan 01 (:case_a_784 selector)
    provides: build_population(:case_a_784, ...) (10 bus-level roll-ups),
      _case_a_house/_case_a_house_counts/_case_a_house_seed helpers, SCENARIO_VALID_POPULATIONS
  - phase: 39 (threaded executor)
    provides: solve_admm(...; parallel = true) opt-in (fail-loud on 1 thread),
      time_limit_s honest :budget_exceeded path, iters/status in the return
provides:
  - "_case_a_rung_counts(full_counts, fraction) — nested-prefix rung helper with the
    documented ladder contract (no re-tuning per rung; 1.0 == full; ArgumentError on ≤ 0)"
  - "scripts/case_a_scaling.jl — ladder + threads-sweep measurement modes, DrWatson
    provenance, keyed CSV upsert, fail-loud arg validation, honest stall recording"
  - "scripts/run_case_a_scaling.sh — subprocess driver: one julia -t N process per leg,
    nonzero exits propagate, --ladder-only/--sweep-only"
  - "results/case_a_population/scaling_ladder.csv — 6 measured rungs (10→784 houses):
    iters 2,4,5,5,91,80; the 784-house point converges (80 iters) but the battery
    complementarity certificate refuses (recorded outcome)"
  - "results/case_a_population/threads_sweep.csv — measured -t 1/2/4 walls 593.4/478.8/
    410.8 s (speedup 1.24x / 1.44x), executor column stamped serial|parallel"
affects: [40-03 agreement measurement (battery-gate refusal at 784 is the escalation
  signal), 40-04 calibration docs, phase-41]

# Tech tracking
tech-stack:
  added: []   # zero new packages
  patterns:
    - "Subprocess-per-leg thread measurement: thread count is process-level, one
      julia -t N process per leg, nonzero exits propagate (no silent serial fallback)"
    - "Honest stall recording: ConvergenceError/CertificateError/SolveFailedError
      become CSV status rows (iters from the error, -1 sentinel), never dropped"
    - "Structural equality for the prefix tripwire: Aggregator/Device Vector fields
      are reference-compared under default =="
    - "Keyed CSV upsert (cols = :union) on the provenance identity — re-runs replace
      their own rows, never drop others"

key-files:
  created:
    - scripts/case_a_scaling.jl
    - scripts/run_case_a_scaling.sh
    - test/test_population_case_a_scaling.jl
    - results/case_a_population/scaling_ladder.csv
    - results/case_a_population/threads_sweep.csv
  modified:
    - src/experiments/materialize.jl
    - scripts/README.md

key-decisions:
  - "rho = ADMM().rho (100.0) passed explicitly at both solve_admm call sites — rho is a
    REQUIRED kwarg in the signature, so the executor's own default is sourced from the
    strategy struct and shared identically everywhere (the locked no-re-tuning config)"
  - "The 1.0-rung prefix tripwire asserts STRUCTURAL equality (field-wise devices +
    element-wise Pdc) against build_population(:case_a_784, ...) — default == is
    reference-true on Aggregator's Vector fields (40-01 documented semantics); tripwire
    proven live during the run"
  - "Micro-ladder smoke runs at T=10, not T=2 — the Deferrable guard makes this house
    shape unconstructable below T=9 (T_HORIZON_FLOOR=10 precedent)"
  - "Solver-outcome stalls (maxiter ConvergenceError, certificate refusals, solver
    failures) are RECORDED as status rows per the honesty policy; misuse errors
    (fail-loud parallel guard) still propagate"

patterns-established:
  - "Measured-artifact CSVs: provenance stamped per row (julia_version, threads,
    blas_threads, seed, t_horizon) + executor column (serial|parallel) matching the
    kwarg actually passed"
  - "BLAS.set_num_threads(1) pinned before every measurement solve for row-to-row
    comparability"

requirements-completed: [POP-05]

# Metrics
duration: 74min
completed: 2026-10-24
---

# Phase 40 Plan 2: Measured Scaling Report Summary

**Measured POP-05 scaling artifacts for the 784-house Case A population: ADMM iterations
vs rung (2,4,5,5,91,80 over 10→784 houses — the iteration blow-up lands between 390 and
584 houses) and a subprocess-driven threads sweep (593.4 s serial / 478.8 s at -t 2 /
410.8 s at -t 4 = 1.44x), with the full-population point's battery-complementarity
certificate refusal recorded as data in all three sweep legs.**

## Performance

- **Duration:** 74 min
- **Started:** 2026-10-24T12:49:48Z
- **Completed:** 2026-10-24T14:04:15Z
- **Tasks:** 2/2 (+1 instrument-fix commit)
- **Files modified:** 3 new scripts/tests + 1 src helper + 2 measured CSVs + README index

## Measured Results (the deliverable)

Population ladder (serial `-t 1`, T=24, seed 42, ρ=100 executor default, no per-rung
tuning; rungs are nested prefixes of the same seeded population):

| rung | fraction | houses | iters | status | wall_s |
|------|----------|--------|-------|--------|--------|
| 1 | 1/78 | 10 | 2 | converged | 27.7 (JIT-inclusive first solve) |
| 2 | 0.125 | 90 | 4 | converged | 4.6 |
| 3 | 0.25 | 190 | 5 | converged | 14.1 |
| 4 | 0.5 | 390 | 5 | converged | 28.8 |
| 5 | 0.75 | 584 | 91 | converged | 419.8 |
| 6 | 1.0 | 784 | 80 | **error:CertificateError** | 508.4 |

The iterations-vs-rungs curve is FLAT (2→5) through 390 houses then JUMPS (91 at 584,
80 at 784) — the heterogeneous-scale iteration blow-up (research Pitfall 5 / C6) is
real and now measured. The 1.0-fraction rung matched `build_population(:case_a_784, ...)`
(structural tripwire) live during the run.

Threads sweep (full 784 houses, one `julia -t N` subprocess per leg, BLAS=1 pinned):

| threads | executor | wall_s | speedup | status |
|---------|----------|--------|---------|--------|
| 1 | serial | 593.4 | 1.00x | error:CertificateError (iters=80) |
| 2 | parallel | 478.8 | 1.24x | error:CertificateError (iters=80) |
| 4 | parallel | 410.8 | **1.44x** | error:CertificateError (iters=80) |

The measured speedup is POSITIVE but modest (1.44x at -t 4, not the negative outcome the
plan flagged as possible) — consistent with the overhead-bound regime (parallelism spans
only 10 bus subproblems; Clarabel's QDLDL backend is single-threaded). All three legs hit
the SAME recorded refusal deterministically (80 iterations each).

**Certificate refusal (diagnosed, recorded, NOT retried or tuned away):**
`CertificateError kind=:battery` at the final consolidation —
"Battery complementarity violated at bus 5, t=16: p_ch·p_dch = 1.0019e-12 ≥
τ·Pmax² = 1.0014e-12 (relative τ=0.001, Pmax≈3.16e-5 pu; App. C)" — the ADMM loop
CONVERGED (80 iters); the certificate band is razor-thin because the per-house-divided
battery scale squares into a ~1e-12 band and the converged point's product sits 0.04%
over it. This matches the repo's standing note ("run_scenario fails at seed 42 — battery
complementarity gate — under investigation"). It is a recorded outcome here and the
escalation signal for 40-03's gate-then-golden agreement work (fix path per repo policy:
solver-precision/certificate-noise investigation, never loosening the gate).

## Accomplishments

- **POP-05 delivered, measured not assumed:** committed provenance-stamped CSVs under
  `results/case_a_population/` (wall time vs threads; iterations vs population size),
  with a negative/null result explicitly recorded as valid if measured (the measured
  result turned out to be a modest positive speedup).
- `_case_a_rung_counts` helper in `src/experiments/materialize.jl` with the documented
  ladder contract (nested prefixes of the SAME seeded population, no per-rung re-tuning,
  1.0 == full, `ArgumentError` on fraction ≤ 0).
- `scripts/case_a_scaling.jl`: ladder + threads-sweep modes; kwarg-only direct
  `solve_admm` calls (NO Scenario seam); keyed CSV upsert (`cols = :union`); fail-loud
  arg validation incl. a `--threads N` vs `Threads.nthreads()` process-level cross-check;
  `BLAS.set_num_threads(1)` pinned; default `--time-limit-s 1800` honest budget path;
  honest stall recording (`error:ConvergenceError` / `error:CertificateError` /
  `error:SolveFailedError` status rows).
- `scripts/run_case_a_scaling.sh`: subprocess driver — ladder leg at `-t 1`, sweep legs
  at `-t 1 2 4`, nonzero exits propagate, `--ladder-only`/`--sweep-only` flags.
- `scripts/README.md`: both new scripts indexed (CI guard green) plus the missing
  Phase-39 attribution-script row (guard was already red at HEAD).
- `test/test_population_case_a_scaling.jl`: 27 assertions green (3m25s) — rung
  derivation (deterministic, nested, bounded, 1.0 == full, ≤ 0 throws) + T=10
  micro-ladder through the script's own construction path (2 rungs solved serially).

## Task Commits

Each task was committed atomically:

1. **Task 1: ladder rung helper, measurement script, subprocess driver, README rows,
   smoke test** - `a004b8a` (feat) + `f7711a0` (fix: honest stall recording, pre-flight
   for the long run)
2. **Task 2: run the harness — commit measured scaling CSVs** - `ba9e2f2` (feat)

## Files Created/Modified

- `src/experiments/materialize.jl` — `_case_a_rung_counts` (additive)
- `scripts/case_a_scaling.jl` — ladder + threads-sweep measurement harness
- `scripts/run_case_a_scaling.sh` — subprocess driver (one `julia -t N` per leg)
- `scripts/README.md` — 3 index rows added (2 new scripts + missing 39-05 attribution row)
- `test/test_population_case_a_scaling.jl` — rung-derivation + T=10 micro-ladder smoke
- `results/case_a_population/scaling_ladder.csv` — 6 measured rungs (committed artifact)
- `results/case_a_population/threads_sweep.csv` — 3 measured legs (committed artifact)

## Decisions Made

- ρ sourced from `ADMM().ρ` (required kwarg; executor default shared at every call site)
- Structural (not reference) equality for the 1.0-rung tripwire — stronger than `==`
- T=10 (not T=2) for the micro-ladder — Deferrable guard floor
- Stalls recorded as status rows (honesty policy); misuse errors propagate fail-loud

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's literal `==` assert on the 1.0 rung cannot hold (reference
semantics)**
- **Found during:** Task 1 (script authoring)
- **Issue:** `Aggregator`/device structs are immutable with Vector fields, so default
  `==` compares those fields by REFERENCE — the script's independently built 1.0 rung and
  `build_population`'s output are `==`-false even when bit-identical (documented in
  40-01's summary and test_population_case_a.jl's header).
- **Fix:** structural field-wise equality (`aggregators_structurally_equal`: bus/φ/Pdc
  element-wise + per-device field-wise) — the honest reading of the prefix-drift
  tripwire; proven live during the Task-2 run.
- **Files modified:** scripts/case_a_scaling.jl
- **Verification:** tripwire passed during the real ladder run ("✓ 1.0-fraction rung
  matches the build_population roll-up")
- **Committed in:** a004b8a

**2. [Rule 3 - Blocking] `solve_admm`'s `ρ` is a REQUIRED kwarg (plan's literal call
would MethodError)**
- **Found during:** Task 1 (signature re-read: `ρ::Real` has no default despite the
  plan's `interfaces` block showing `ρ = default`)
- **Fix:** pass `ρ = ADMM().ρ` (100.0, strategies.jl executor default) at both call
  sites, shared identically — the locked no-re-tuning configuration, not a per-rung
  override. Acceptance criterion read as "no per-rung VARIATION of ρ/maxiter/tol".
- **Files modified:** scripts/case_a_scaling.jl
- **Verification:** greps show both call sites pass only T, λ₀, ρ (shared),
  time_limit_s, parallel; tests green
- **Committed in:** a004b8a

**3. [Rule 3 - Blocking] T=2 micro-ladder is unconstructable (Deferrable guard)**
- **Found during:** Task 1 (first targeted test run: ArgumentError from the Deferrable
  constructor — `E ≤ Pmax·window_length` infeasible below T=9)
- **Fix:** T=10, the repo's measured minimum feasible horizon for this exact house shape
  (`T_HORIZON_FLOOR = T_QUICK = 10`, documented in benchmark_ieee8500.jl)
- **Files modified:** test/test_population_case_a_scaling.jl
- **Verification:** targeted file run green (27 pass / 0 fail / 0 error)
- **Committed in:** a004b8a

**4. [Rule 3 - Blocking] CI scripts-index guard already red at HEAD**
- **Found during:** Task 1 (verify block: `check_scripts_index.py` failed on
  `scripts/profile_ieee8500_memory_attribution.jl`, committed in 39-05 without its
  README index row — pre-existing, unrelated to this plan's files but blocking the
  task's verify gate)
- **Fix:** added the missing README index row for the attribution script
- **Files modified:** scripts/README.md
- **Verification:** guard exits 0 ("scripts index complete (41 tracked files checked)")
- **Committed in:** a004b8a

**5. [Rule 2 - Missing Critical] Maxiter/certificate stalls would kill the leg and DROP
the measured outcome**
- **Found during:** Task 2 preparation (solve_admm THROWS ConvergenceError on a maxiter
  stall when the wall-clock budget hasn't elapsed first; CertificateError/SolveFailedError
  likewise at/inside the consolidation) — contradicting the plan's must-have truth "a
  budget-exceeded or maxiter stall is a recorded outcome, never dropped"
- **Fix:** `run_solve_outcome` catches the three solver-outcome exception types and
  records them as status rows (iters from the error's own field, -1 sentinel when
  absent; welfare/exact_maxgap missing); misuse errors still propagate. This record path
  is exactly what captured the real battery-certificate refusal in all four full-scale
  legs.
- **Files modified:** scripts/case_a_scaling.jl
- **Verification:** pre-flight asserts the recording path and the rethrow path; the
  Task-2 run exercised it live (4 recorded `error:CertificateError` rows)
- **Committed in:** f7711a0

---

**Total deviations:** 5 auto-fixed (1 bug, 3 blocking, 1 missing-critical)
**Impact on plan:** all fixes were prerequisites for a correct/honest harness; no scope
creep; the measured deliverables are unaffected in shape (columns, keys, provenance all
per plan).

## Issues Encountered

- The full 784-house ADMM point converges (80 iterations) but the battery
  complementarity certificate refuses at the final consolidation (diagnosed above; 0.04%
  over a ~1e-12 band). Recorded in the committed CSVs per the honesty policy; handed to
  40-03 as the escalation signal. NOT fixed here (solver/certificate investigation is
  out of this plan's scope and the honesty policy forbids tuning until it fits).
- Ladder wall times include first-solve JIT in rung 1 (27.7 s vs 4.6 s for the larger
  rung 2) — noted so the curve is read correctly; sweep legs are JIT-fair (each ran in a
  fresh process).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 40-03 (centralized-vs-ADMM agreement at full scale): the population builds,
  solves, and its behavior at 784 houses is now measured. 40-03 must plan around the
  recorded battery-complementarity refusal (band ~1e-12 at the per-house-divided battery
  scale) — gate-then-golden with the honest-recording pattern this plan established.
- The threads-sweep instrumentation (executor column, BLAS pinning, subprocess legs) is
  reusable for any future executor benchmarking.
- Open: nothing blocking; the certificate investigation may need the Pitfall-4-style
  escalation (tighten solver precision / study the certificate noise floor) in a later
  plan.

## Self-Check: PASSED

- FOUND: scripts/case_a_scaling.jl, scripts/run_case_a_scaling.sh,
  test/test_population_case_a_scaling.jl, results/case_a_population/scaling_ladder.csv,
  results/case_a_population/threads_sweep.csv (all on disk)
- FOUND: commits a004b8a (Task 1), f7711a0 (instrument fix), ba9e2f2 (Task 2 CSVs)
- FOUND: `_case_a_rung_counts` in src/experiments/materialize.jl:349
- Re-verified post-run: targeted test file 27 pass / 0 fail / 0 error;
  `check_scripts_index.py` exit 0; Task-2 CSV verify command passed ("CSVs OK: ladder
  rungs = 6, max iters = 91, -t4 wall = 410.831851456s"); `bash -n` clean; no
  `Scenario(` in the script; solve_admm call sites kwarg-only.

---
*Phase: 40-784-house-thesis-population*
*Completed: 2026-10-24*
