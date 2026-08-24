---
phase: 25-ieee-8500-scalability-benchmark
plan: 05
subsystem: infra
tags: [socp-exactness, calibration, benchmark-harness, clarabel, scs, admm, julia]

# Dependency graph
requires:
  - phase: 25-02
    provides: "solve_admm(...; time_limit_s=...) honest :budget_exceeded exit; alternative_optimizer(SCSChoice(), pc) opt-in SCS dispatch"
  - phase: 25-04
    provides: "build_feeder(:ieee8500)/(:ieee8500_mv); build_population(:default, ..., :ieee8500/:ieee8500_mv, ...) with real per-load-kW population + capacitor Aggregators"
provides:
  - "socp_relaxation_gap(ctx) — a non-throwing sibling of assert_socp_exact! for noise-floor calibration"
  - "scripts/benchmark_ieee8500.jl --calibrate-noise-floor: fresh, per-fixture SOCP-exactness noise-floor measurement (spike-002's tolerance-ladder method), never inherited from IEEE-13/123"
  - "scripts/benchmark_ieee8500.jl (default mode): fixture x density x solver x {centralized,ADMM} density-sweep harness with D-18 timeout, D-19 metrics, D-20/D-21 SCS comparison, --quick CI-affordable mode"
  - "test/test_benchmark_ieee8500.jl: D-16 deterministic goldens (model dims, termination status, ADMM iteration count) on the --quick point, wall-time-free"
affects: [25-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Calibration-only non-throwing sibling function pattern: socp_relaxation_gap duplicates assert_socp_exact!'s gap loop verbatim, no rtol/atol classification, byte-identical original left untouched"
    - "Per-rung try/catch inside a tolerance ladder (mirrors socp_applicability_sweep.jl's per-point try/catch) so an ALMOST_OPTIMAL rung is recorded as NaN and reported, never crashing the whole calibration run"
    - "Extracting the real MOI termination status from a caught assert_solved! error message via regex (`termination_status\\s*:\\s*(\\S+)`), since solve_welfare does not return its ctx on a throw"
    - "JuMP/MOI's own solve_time(model) used to split wall time into assembly vs solver time (D-19) without instrumenting src/models/welfare_solve.jl"
    - "--quick uses its own tighter time-limit AND horizon (T_horizon threaded as an explicit function parameter, not a module-level const) to fit a CI feedback-latency budget, independent of the general sweep's defaults"

key-files:
  created:
    - scripts/benchmark_ieee8500.jl
    - test/test_benchmark_ieee8500.jl
    - results/ieee8500_benchmark/noise_floor_calibration.csv
    - results/ieee8500_benchmark/density_sweep.csv
    - .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md
  modified:
    - src/models/exactness.jl

key-decisions:
  - "IEEE8500_MV_EXACT_ATOL=0.1796 / IEEE8500_EXACT_ATOL=0.5653 are measured, fixture-fresh, but LARGE — the calibration ladder does not converge to a small numerical noise floor on either IEEE-8500 fixture because the SAME real, vendored near-zero-impedance MV connector (HVMV_Sub_48332 -> _HVMV_Sub_LSB, r~3.2e-9 pu) dominates the cone-gap scan at every rung; this is a genuine structural finding (LinDistFlow's exactness gradient is absent on a near-zero-r branch), not a harness bug, root-caused via a real-entrypoint diagnostic rather than concluded from ratio magnitude alone"
  - "--quick uses a DEDICATED, tighter ADMM time_limit (5s, not the general 120s) and a DEDICATED shorter horizon (T_QUICK=10, not the general T=24) to keep the whole invocation's wall time under 120s (measured ~100-103s across 3 runs) — reducing time_limit alone could not work because both the centralized JuMP-assembly cost and solve_admm's build-once phase (before the wall-clock loop even starts) are dominated by NETWORK size at fixed T, not by the time_limit setting"
  - "T_QUICK=10, not smaller: _ieee8500_house's fixed Deferrable energy budget (E=1.0, Pmax=0.5) requires window_length=min(16,T)-min(8,T)+1 >= 2, i.e. T>=9 — discovered live when T_QUICK=4 threw an ArgumentError at population-construction time"
  - "The centralized point's exactness verdict uses socp_relaxation_gap's raw maxgap compared directly against the calibrated atol (no rtol/magnitude term) — a simpler, honest proxy for 'at/below this fixture's own noise floor', since the harness only has the raw gap, not assert_socp_exact!'s full ratio"
  - "IEEE-13/123 keep the project's existing assert_socp_exact! default atol=1e-6 in the harness's EXACTNESS_ATOL map (already validated by prior phases) — only the two NEW IEEE-8500 fixtures get a fresh Task-1 measurement, per the anti-certificate-laundering mandate"

patterns-established:
  - "Density-filtered population sampling: StableRNGs.Random.randperm on an explicit seeded RNG (never the global RNG), returned sorted ascending; capacitor Aggregators are ALWAYS kept regardless of density (grid infrastructure, not the fan-out axis under study)"

requirements-completed: [SCALE-04, SCALE-05]

# Metrics
duration: ~80min
completed: 2026-08-21
---

# Phase 25 Plan 05: IEEE-8500 Noise-Floor Calibration + Density-Sweep Benchmark Harness Summary

**A fresh per-fixture SOCP-exactness noise-floor measurement that surfaced a genuine structural finding (a real near-zero-impedance MV connector breaks the standard LinDistFlow exactness gradient at IEEE-8500 scale), plus a fixture x density x solver x {centralized,ADMM} benchmark harness whose `--quick` mode was re-tuned live to fit the 120s CI feedback-latency budget.**

## Performance

- **Duration:** ~80 min
- **Started:** 2026-08-21T09:03 (worktree base corrected to `439f9149...`)
- **Completed:** 2026-08-21T10:25
- **Tasks:** 3
- **Files modified:** 1 modified, 5 created (incl. 2 committed CSVs + 1 deferred-items log)

**Measurement provenance (per orchestrator instruction):** the FIRST calibration attempt on
`ieee8500-mv` was launched while the orchestrator's full-suite `Pkg.test()` was still running
concurrently (CPU-contended); that attempt used the PRE-FIX calibration code (crashed uncaught on
an `ALMOST_OPTIMAL` rung, produced no usable rows, and was NEVER committed). Every number that
IS committed — both `noise_floor_calibration.csv`'s measured gaps and `density_sweep.csv`'s rows,
including all 3 `--quick` timing runs and the `--time-limit 1` exercise — was measured AFTER the
orchestrator confirmed the machine was quiet (its full suite finished: 29,760 passed). The
`measured_gap` numbers are additionally CPU-independent by construction (pure numerical residuals,
not wall-clock quantities), so even the discarded contended attempt's partial output would not
have been suspect — it simply never produced a complete row.

## Accomplishments

- `socp_relaxation_gap(ctx)`: a new, non-throwing, calibration-only sibling of
  `assert_socp_exact!` — the existing gate's 78-107 lines are byte-identical before/after (verified
  by direct diff)
- `scripts/benchmark_ieee8500.jl --calibrate-noise-floor`: spike-002's tolerance-ladder method,
  robustified (Rule 1, discovered live) to survive a per-rung `ALMOST_OPTIMAL` failure without
  crashing the whole ladder — every rung, including failed ones, is written to the committed CSV
- **Genuine finding, not a bug:** the calibration ladder on BOTH `ieee8500-mv` and `ieee8500`
  plateaus at a LARGE residual (0.1796 / 0.5653, not a small "noise" number) because the same real
  vendored near-zero-impedance MV connector (`HVMV_Sub_48332 -> _HVMV_Sub_LSB`, `r≈3.2e-9 pu`)
  structurally breaks the LinDistFlow exactness gradient — confirmed by a real-entrypoint
  per-branch diagnostic on both fixtures, never concluded from the ratio's magnitude alone
  (see Deviations and `deferred-items.md`)
- The density-sweep harness (`scripts/benchmark_ieee8500.jl`, default mode): fixture x density x
  solver x {centralized, ADMM}, every point reported honestly (including `budget_exceeded` and
  caught-error rows — never silently dropped), D-19 assembly-vs-solve timing split via JuMP's own
  `solve_time(model)`, D-20/D-21 SCS crossover (gracefully degrades to `"scs_unavailable"` — SCS is
  confirmed NOT installed in this environment, a genuine weakdep-absent path, not a stub)
- `--quick` re-tuned live (Rule 1) with its OWN tighter ADMM cap (5s) and horizon (`T_QUICK=10`)
  after the FIRST verify attempt measured ~163-193s total wall time, well over
  `25-VALIDATION.md`'s 120s ceiling — re-verified 3 times after the fix, landing at ~100-103s each
  time, with IDENTICAL `model_vars`/`model_cons`/`termination_status`/`admm_status`/`admm_iters`
  across all 3 runs
- `test/test_benchmark_ieee8500.jl`: D-16's deterministic goldens (model dims, termination status,
  ADMM iteration count), pinned after the stability check above; 10/10 assertions pass; wall time
  never asserted
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`: the near-zero-impedance
  connector finding and its downstream consequence for `solve_admm`'s hardcoded final-consolidation
  exactness gate, logged for a future plan (out of this plan's `<files>` scope to fix)

## Task Commits

Each task was committed atomically (with one additional Rule-1 fix commit per task after live
discoveries during verification — see Deviations):

1. **Task 1: socp_relaxation_gap sibling + noise-floor calibration mode** — `90977f4` (feat)
   — `1061a59` (fix: per-rung robustness + the real measured floors, discovered running the
   actual full 5-rung deliverable)
2. **Task 2: density-sweep harness** — code landed inside `90977f4` (see granularity note below)
   — `9df35db` (fix: `--quick`'s time budget re-tuned to fit the 120s ceiling, discovered running
   the actual `<verify>` command)
3. **Task 3: D-16 deterministic goldens** — `5b5bdd6` (test)

**Note on task/commit granularity** (mirrors plan 25-03's own precedent): Task 1 and Task 2's
initial code were authored into `scripts/benchmark_ieee8500.jl` in a single `Write` (the
calibration mode and the density-sweep mode share the same CLI dispatcher, the same
`density_filtered_population` helper, and the same CSV-upsert convention — drafting them as one
cohesive file was the natural authoring unit), so both tasks' FIRST-DRAFT code landed in commit
`90977f4` rather than two separate commits. Each task's OWN `<verify>`/acceptance criteria were
independently re-run and confirmed passing (Task 1's ieee13 smoke verify, then separately Task 2's
`--quick` verify) before proceeding, and each task's LIVE-DISCOVERED bug fix landed in its own
distinct, clearly-scoped follow-up commit.

**Plan metadata:** this SUMMARY.md commit (below) — STATE.md/ROADMAP.md owned by the orchestrator
post-merge (worktree mode).

## Files Created/Modified

- `src/models/exactness.jl` — added `socp_relaxation_gap(ctx)`, exported alongside the existing
  `assert_socp_exact!` (byte-identical, unchanged)
- `scripts/benchmark_ieee8500.jl` — new harness, both modes (`--calibrate-noise-floor` and the
  default density sweep with `--quick`)
- `test/test_benchmark_ieee8500.jl` — new plain `Test.jl` script, D-16 goldens
- `results/ieee8500_benchmark/noise_floor_calibration.csv` — committed 12-row trace (ieee13 smoke
  rows + the full 5-rung ladder for `ieee8500-mv`/`ieee8500`, including the `NaN` failed rungs)
- `results/ieee8500_benchmark/density_sweep.csv` — committed `--quick` point row
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — new, the near-zero-
  impedance connector finding

## Decisions Made

- **Fresh, honest calibration over a convenient one:** rather than forcing a small `atol` to keep
  the exactness gate "meaningful," the measured floors are reported as-is (0.1796 / 0.5653), with
  the root cause documented in-code and in `deferred-items.md` — matching this project's standing
  "honest-finding-as-deliverable" convention (mirrors the v2.1 SOCP-inexactness finding).
- **`--quick`'s horizon/time-limit are DEDICATED constants** (`T_QUICK`, `_QUICK_TIME_LIMIT_S`),
  not derived by scaling the general defaults, because the dominant costs (JuMP assembly,
  `solve_admm`'s build-once phase) are NETWORK-size-dominated at fixed `T`, not time-limit-
  dominated — tuning `--time-limit` alone could not have closed the latency gap.
  `run_centralized_point`/`run_admm_point`/`run_scs_comparison` now take `T_horizon` as an
  explicit parameter instead of reading a module-level `const T` closure.
- **Executed the plan's own `<verify>` commands with `--project=.` added**, since the plan's
  literal text (`julia scripts/benchmark_ieee8500.jl ...`, no `--project=.`) fails immediately
  with `ArgumentError: Package DrWatson not found` when Julia's LOAD_PATH defaults to the global
  environment — `--project=.` is required for `@quickactivate "TSODSO"` to resolve, and every
  OTHER verify command in this same plan (Task 1, Task 3) already includes it explicitly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Calibration ladder crashed uncaught on an `ALMOST_OPTIMAL` rung**
- **Found during:** Task 1, running the real 5-rung calibration deliverable on `ieee8500-mv`
- **Issue:** `solve_welfare`'s internal `assert_solved!` has no `allow_almost` pass-through, so a
  ladder rung that legitimately lands `ALMOST_OPTIMAL` (a real numerical-conditioning limit at this
  scale, not a bug) threw uncaught and killed the entire calibration run before later rungs could
  even attempt to solve.
- **Fix:** wrapped each rung's solve in try/catch (mirrors `socp_applicability_sweep.jl`'s own
  per-point try/catch convention); a failed rung is recorded as `measured_gap = NaN` in the CSV
  (never silently dropped) and the floor-selection logic picks the floor from the last
  SUCCESSFUL, still-improving rung.
- **Files modified:** `scripts/benchmark_ieee8500.jl`
- **Verification:** re-ran the full 5-rung ladder for both `ieee8500-mv` (3 successful + 2 `NaN`
  rungs) and `ieee8500` (1 successful + 4 `NaN` rungs); both wrote complete, honest 5-row traces.
- **Committed in:** `1061a59`

**2. [Rule 1 - Bug, genuine finding] The calibration ladder does not converge to a small noise
floor — root-caused to a real near-zero-impedance branch**
- **Found during:** Task 1, investigating why the ladder's residuals (0.496 -> 0.380 -> 0.180)
  were orders of magnitude larger than IEEE-13's (~2.6e-9)
- **Issue:** per the prior-wave-context mandate to "never conclude from a ratio's magnitude alone
  — discriminate with a real entrypoint AND a tolerance ladder," a per-branch diagnostic was run
  against the actual solved model on both fixtures. The SAME real vendored MV segment
  (`HVMV_Sub_48332 -> _HVMV_Sub_LSB`, `r≈3.2e-9 pu`, six orders of magnitude below the project's
  own near-ideal-branch convention) tops the worst-gap list at every ladder rung and on both
  fixtures — a genuine structural property of the real data, not a calibration bug.
- **Fix:** NOT fixed in `src/` (out of this plan's `<files>` scope — `scripts/
  reduce_ieee8500_impedances.jl`/`src/data/ieee8500.jl` are not authorized for this plan). The
  measured, honest floors were committed as-is; the finding and its downstream consequence for
  `solve_admm`'s own hardcoded exactness gate are logged in
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` for a future plan.
- **Files modified:** `scripts/benchmark_ieee8500.jl` (constants + comments only);
  `deferred-items.md` (new)
- **Verification:** diagnostic re-run on both `ieee8500_mv_modified()` and `ieee8500_modified()`
  independently confirms the identical offending branch tops the gap list on both.
- **Committed in:** `1061a59`

**3. [Rule 1 - Bug] `--quick` exceeded the 120s feedback-latency budget**
- **Found during:** Task 2, running the plan's own literal `<verify>` command for the first time
- **Issue:** first measured wall time was ~163-193s (centralized ~76s + `solve_admm`'s build-once
  phase + iterations ~42-117s + Julia import overhead), well over `25-VALIDATION.md`'s 120s
  ceiling. Reducing `--time-limit` alone could not close the gap because `solve_admm`'s build-once
  phase runs BEFORE the wall-clock loop even starts checking the budget, and JuMP model assembly
  is dominated by fixed NETWORK size at `T=24`, not by the time-limit setting.
- **Fix:** added a dedicated `--quick`-only ADMM cap (`_QUICK_TIME_LIMIT_S = 5`) and a dedicated
  `--quick`-only horizon (`T_QUICK = 10`, threaded as an explicit `T_horizon` parameter through
  `run_centralized_point`/`run_admm_point`/`run_scs_comparison`, replacing their prior read of a
  module-level `const T`). `T_QUICK = 10` (not smaller) was itself required by a second live
  discovery: `_ieee8500_house`'s fixed `Deferrable` energy budget needs
  `window_length = min(16,T) - min(8,T) + 1 >= 2`, i.e. `T >= 9` — `T_QUICK = 4` threw an
  `ArgumentError` at population-construction time.
- **Files modified:** `scripts/benchmark_ieee8500.jl`
- **Verification:** 3 repeated `--quick` runs measured ~100-103s wall time each (comfortably under
  120s), with byte-identical `model_vars`/`model_cons`/`termination_status`/`admm_status`/
  `admm_iters` across all 3.
- **Committed in:** `9df35db`

**4. [Rule 1 - Bug, wording only] Two comments literally contained grep-forbidden substrings**
- **Found during:** Task 1 and Task 2's own acceptance-criteria grep checks
- **Issue:** a comment explaining the anti-certificate-laundering property literally contained
  "reused from IEEE-13/123" (in a NEGATING sentence), and a comment explaining the peak-memory
  method literally contained "BenchmarkTools" (explaining why NO such dependency was added) — both
  tripped their respective strict, literal, comment/code-blind grep acceptance checks (mirrors
  plan 25-04's own `_IEEE8500_LOAD_SCALE` wording-only precedent).
- **Fix:** reworded both comments to convey the same intent without the literal forbidden
  substring.
- **Files modified:** `scripts/benchmark_ieee8500.jl`
- **Verification:** `grep -n "reused from IEEE-13\|reused from IEEE-123"` and
  `grep -ic "BenchmarkTools" scripts/benchmark_ieee8500.jl Project.toml` both return no
  matches/`0`.
- **Committed in:** `1061a59` / `9df35db`

---

**Total deviations:** 4 auto-fixed (2 bugs in this plan's own new script, 1 genuine data/structural
finding correctly root-caused and deferred rather than silently patched, 1 wording-only grep-check
fix). **Impact on plan:** all four were required for the plan's own stated acceptance criteria
(a robust calibration ladder; a `--quick` command that actually fits the documented latency
budget; literal grep checks). No `src/` scope creep beyond the additive `socp_relaxation_gap`
Task 1 explicitly authorized.

## Issues Encountered

- **The plan's own `<verify>` command text for Task 2 omits `--project=.`** (`julia
  scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick`), which fails immediately against
  Julia's global environment (`DrWatson` not found there). Every verification run in this plan
  used `--project=.` explicitly — consistent with Task 1's and Task 3's own `<verify>` text, both
  of which already include it.
- **SCS is confirmed NOT installed** in this worktree's environment (`Base.find_package("SCS")`
  returns `nothing`) — the D-20/D-21 SCS-comparison code path (`run_scs_comparison`) is
  structurally correct by inspection and degrades gracefully to `"scs_unavailable"`, but could not
  be empirically exercised end-to-end with a real SCS solve in this session (consistent with plan
  25-02's own SUMMARY, which also could not exercise a live SCS solve for the same reason).

## User Setup Required

None — no external service configuration required. A researcher who wants to exercise the D-20/
D-21 SCS comparison path need only `import Pkg; Pkg.add("SCS")` in their own environment first;
nothing in this plan's verification requires it.

## Next Phase Readiness

- Plan 25-06 (headline results) can consume `scripts/benchmark_ieee8500.jl`'s general (non-quick)
  sweep mode directly — the harness, its CSV schema, and both calibrated `atol` constants are
  complete and committed.
- **Flagged for 25-06's attention** (see `deferred-items.md`): a genuinely CONVERGED, fully
  consolidated ADMM point on EITHER IEEE-8500 fixture will hit `solve_admm`'s own hardcoded
  final-consolidation `assert_socp_exact!` gate (project-default `atol=1e-6`, no override seam)
  and throw, because of the SAME near-zero-impedance connector this plan's calibration surfaced.
  25-06's density sweep should expect (and honestly report, per D-18/T-25-11) `ERROR:*` or
  `budget_exceeded` ADMM rows on these fixtures rather than a clean `:converged` status, unless a
  follow-up data-shaping or gate-override fix lands first.
- No blockers for plan 25-06 to START — the harness itself is complete, tested, and honest about
  every point it attempts.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*
