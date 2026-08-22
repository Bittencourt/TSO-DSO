# Deferred Items — Phase 25 (IEEE-8500 Scalability Benchmark)

Discoveries made during plan execution that are out of the discovering plan's `<files>` scope,
logged here per the executor's SCOPE BOUNDARY rule rather than fixed inline.

## Plan 25-05: near-zero-impedance MV connector breaks the naive SOC-exactness noise-floor calibration

**Found during:** Task 1's real 5-rung noise-floor calibration deliverable (`--calibrate-noise-floor`)
on both IEEE-8500 fixtures.

**What was found:** On BOTH `ieee8500_mv_modified()` and `ieee8500_modified()`, the worst-offending
branch in the SOCP cone-residual scan is, at every tolerance rung, the SAME real vendored MV
segment `HVMV_Sub_48332 -> _HVMV_Sub_LSB` — `IEEE8500_MV_BRANCH_RX_OHMS[("HVMV_Sub_48332",
"_HVMV_Sub_LSB")] = (1e-6 Ω, 1e-5 Ω)`. At `S_base = 0.5 MVA`, `V = 12.47 kV` this converts to a
genuinely near-zero per-unit impedance (`r ≈ 3.2e-9 pu`, `x ≈ 3.2e-8 pu`) — roughly SIX orders of
magnitude smaller than the D-13 near-ideal regulator/switch convention already used elsewhere in
this same fixture (`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` = 3e-4/1.5e-4 pu).

**Why this matters:** the LinDistFlow SOC-exactness argument relies on a strictly-positive
loss-cost gradient (`r·l` in the objective) to drive the squared-current variable `l` to its tight
minimal value at the optimum. On a near-zero-`r` branch that gradient is essentially absent, so the
cone residual on THIS branch does not shrink as the solver's `tol_gap` tightens — it is a
STRUCTURAL/ill-conditioning property of the branch, not shrinking numerical noise. Confirmed via a
real-entrypoint diagnostic (not a ratio-only conclusion): the SAME branch tops the worst-gap list on
both fixtures, at every density/seed tried.

**Consequence for this plan (historical — SUPERSEDED by Item 1's 2026-08-21 resolution below):**
at the time plan 25-05 measured it, the calibrated `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL`
constants in `scripts/benchmark_ieee8500.jl` were measured HONESTLY (never inherited from
IEEE-13/123) but were consequently LARGE (0.1796 / 0.5653) — large enough that the harness's own
`exact_verdict` classification against them was a much weaker check than IEEE-13/123's `1e-6`-scale
gate. This was documented in-code and here, not silently absorbed. Item 1 below (RESOLVED) fixed
the root cause and both constants are now re-measured, ~150x smaller, and genuinely noise-like.

**Deferred (out of plan 25-05's `<files>` scope — only `src/models/exactness.jl`,
`scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl` are authorized):**

### Item 1 — RESOLVED 2026-08-21 (phase-25 gap-closure task, authorized directly by the user)

`scripts/reduce_ieee8500_impedances.jl`'s `reshape_near_zero_mv_edges!` now detects this ONE
degenerate MV segment (`("HVMV_Sub_48332", "_HVMV_Sub_LSB")`, the substation Low Side Bus busbar
tie) via an explicit, documented threshold (`r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM = 1e-5 Ω`, with
a loud assert-exactly-1 check so a future data refresh that changes this set fails fast) and
reassigns its `r_ohm`/`x_ohm` VALUES in place — same bus pair, same `IEEE8500_MV_BRANCH_RX_OHMS`
table, same connectivity — to the D-13 near-ideal Ω-equivalent of `IEEE123_SWITCH_R`/
`IEEE123_SWITCH_X` at this fixture's own MV per-unit base: `(r=0.09330 Ω, x=0.04665 Ω)` (was
`(1e-6 Ω, 1e-5 Ω)`). `IEEE8500_REGULATOR_EDGES` is untouched (still 43 entries); MV edge count
(2477), and both fixtures' bus/branch counts (4875/4874, 2521/2520) are unchanged. Full
data-shaping rationale in `25-DATA-PROVENANCE.md`'s new "Deviation from verbatim transcription"
section.

**Measured before/after** (both measured via `scripts/benchmark_ieee8500.jl
--calibrate-noise-floor`, machine confirmed quiet both times — the AFTER column is this
gap-closure task's own fresh Task 3 measurement, not inherited from any prior estimate):

| Fixture | Rung | Before (measured_gap) | After (measured_gap) |
|---|---|---|---|
| `ieee8500-mv` | tol=1e-6 | 0.4960365893 | 0.0312771897 |
| `ieee8500-mv` | tol=1e-7 | 0.3802856023 | 0.0059259602 |
| `ieee8500-mv` | tol=1e-8 (FLOOR) | 0.1795915651 (plateaued; tol=1e-9/1e-10 failed `ALMOST_OPTIMAL`) | 0.0011460286 (shrinking 27x tighter than tol=1e-6 — genuine noise-like behavior; tol=1e-9/1e-10 still fail `ALMOST_OPTIMAL`) |
| `ieee8500` | tol=1e-6 | 0.5653322911 (FLOOR before — every tighter rung failed) | 0.0273083027 |
| `ieee8500` | tol=1e-7 (FLOOR after) | NaN (`ALMOST_OPTIMAL`) | 0.0049691451 |

`ieee8500-mv`'s floor improved 157x at tol=1e-8 (`0.1796 -> 0.001146`). `ieee8500`'s floor
improved from a tol=1e-6 plateau (`0.5653`) to a genuinely tighter tol=1e-7 floor (`0.004969`),
a 114x improvement, AND (unlike before) it now successfully reaches a SECOND ladder rung at all.
More important than either raw ratio: BOTH fixtures' residuals now SHRINK as tolerance tightens
rung-over-rung instead of plateauing/immediately failing — they now behave like real numerical
noise rather than a structural relaxation floor. `test/test_benchmark_ieee8500.jl`'s D-16 goldens
(model dimensions, termination status, ADMM iteration count) were re-run and ALL 10/10 still
pass unchanged — only the (never-golden) wall-time and exactness-gap columns moved. See this
gap-closure task's `25-07-SUMMARY.md` for the full 5-rung ladder and the re-calibrated
`IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` constants.

**IMPORTANT HONEST CAVEAT — this fix does NOT make a converged ADMM consolidation work.** Even
after this fix the floor is still `~1e-3` scale, which STILL exceeds `solve_admm`'s hardcoded
final-consolidation `assert_socp_exact!` default of `atol=1e-6` (no override parameter exists —
see Item 3 below, which remains OPEN). A genuinely CONVERGED, CONSOLIDATED ADMM point on either
IEEE-8500 fixture can still throw at that gate. This fix closes the STRUCTURAL relaxation failure
(the residual now behaves like noise and shrinks with tolerance) but does NOT close the numerical
gap between that noise floor and the project's existing `1e-6` default gate — that gap is Item 3's
concern, still open.

### Item 2 — still OPEN (NOT in scope for this gap-closure task)

**Item 2 (open):** Whether `assert_socp_exact!`/`socp_relaxation_gap` should special-case or
exclude near-zero-impedance branches from the max-gap scan, so a single degenerate connector
cannot dominate (and effectively disable) the exactness gate for an otherwise well-conditioned
network — `src/models/exactness.jl` is NOT in this gap-closure task's authorized file list.

### Item 3 — RESOLVED 2026-08-22 (quick tasks 260822-f0b + 260822-hld)

**Item 3 (historical, at the time this plan measured it):** `solve_admm`'s own hardcoded final-
  consolidation `assert_socp_exact!` call (`src/admm/solve_admm.jl`, `check_exact = true`) used
  the PROJECT DEFAULT `atol = 1e-6`/`rtol = 1e-4` with no override parameter — meaning ADMM on
  either IEEE-8500 fixture would hit this SAME near-zero-impedance branch's residual and throw at
  the final consolidation gate REGARDLESS of density, population, or convergence quality. This was
  a real, reproducible finding (confirmed live during Task 2's `--quick` and `--time-limit 1`
  exercises: the ADMM point on `ieee8500-mv` never reached a clean converged consolidation — it
  was intentionally exercised under a SHORT wall-clock budget in this plan specifically so
  `solve_admm`'s D-18 early exit (`:budget_exceeded`) fired before the final consolidation gate
  was ever reached). Item 1's data-shaping fix (resolved 2026-08-21) closed the STRUCTURAL failure
  but did NOT close the remaining numerical gap between the re-measured `~1e-3` noise floor and
  this `1e-6` default.

**How it was resolved:** quick task 260822-f0b (2026-08-22) first added the additive
  `atol_exact`/`rtol_exact` override seam onto `solve_admm`'s final consolidation `solve_dso!`
  call (mid-loop `check_exact = false` untouched). Quick task 260822-hld (same day, round 2) then
  actually THREADED the seam: `scripts/benchmark_ieee8500.jl`'s `run_admm_point` now passes the
  SAME per-fixture `EXACTNESS_ATOL[fixture_sym]` already used for the centralized point's own
  `exact_verdict` into `solve_admm`'s `atol_exact` — never a literal chosen to pass a specific
  point (T-25-12 anti-certificate-laundering: a point whose cone gap genuinely exceeds its
  fixture's own measured floor still throws).

**Measured evidence (260822-hld):** re-ran `fixture=ieee8500, density=0.1, T_horizon=10,
  solver=clarabel` (the SAME point orchestrator diagnostics had measured throwing under the OLD
  unthreaded `atol=1e-6` default, cone gap `1.3968e-4`). With the floor threaded
  (`admm_atol_used=0.0049691451`, the density-0.05/T=24-measured `IEEE8500_EXACT_ATOL`), ADMM now
  reaches `admm_status = converged` (8 iterations) instead of throwing — see
  `results/ieee8500_benchmark/density_sweep.csv`'s `ieee8500,0.1,clarabel` row and
  `260822-hld-SUMMARY.md` for the full trace, including a freshly-measured, POINT-APPROPRIATE
  calibration ladder at this exact (density, T_horizon) that found an even LARGER floor
  (`0.0325016`, ~6.5x the reused density-0.05/T=24 value) — the converged point passes under
  either floor by more than 28x margin. The centralized solve's own `ALMOST_OPTIMAL` status is
  UNCHANGED and NOT claimed as fixed — that is a separate, still-open conditioning question (see
  Item 4's own conditioning-wall discussion below).

**Not a plan-25-05 blocker (historical note):** Task 1/2/3's own acceptance criteria never
required a converged ADMM consolidation — they required an honestly-reported point (including
`budget_exceeded`), which this plan delivered even before Item 3's resolution above.

## Plan 25-06: the memory wall arrives BEFORE the conditioning wall at IEEE-8500 scale

**Found during:** Task 1's full cross-fixture density sweep (`scripts/benchmark_ieee8500.jl`,
no `--quick`, full `T=24`, `--time-limit 120`, both solvers).

**What was found:** on the shared 15 GiB machine this sweep was measured on, the Linux OOM-killer
(confirmed via `journalctl -k`, PID + `anon-rss` recorded in each affected row's `error_msg` in
`results/ieee8500_benchmark/density_sweep_full.csv`) terminated the Julia process outright at 6
separate points: `ieee8500-mv` density=0.5 and 1.0, and `ieee8500` (headline) density=0.1 (×2
attempts) and density=1.0. Every kill happened with `anon-rss` between ~7 GiB and ~9.75 GiB, WHILE
system swap was independently at or near its ~9 GiB ceiling from OTHER, unrelated processes
(browser tabs, docker, other agent sessions) running concurrently on the same shared machine — so
these numbers are a measured LOWER BOUND on the point's true memory need, not a clean, isolated
peak-memory measurement.

**Why this matters:** this wall arrives strictly BEFORE either of `solve_welfare`'s own D-18
wall-clock timeout or `solve_admm`'s hardcoded final-consolidation `assert_socp_exact!` gate
(deferred-items.md item 3, above) can ever fire — an OOM-killed point never reaches either
mechanism. It is a genuinely SEPARATE, size-driven wall from the conditioning wall items 1-3
document, and — on this measurement machine — arrives FIRST, meaning the conditioning wall's
practical consequences for ADMM consolidation could not even be re-confirmed at IEEE-8500 scale
during this plan's own sweep (they were already established independently by plans 25-05/25-07's
calibration ladder, which uses a much smaller, low-density benign point that does NOT OOM).

**Deferred (out of plan 25-06's `<files>` scope — this plan's authorized files are
`results/ieee8500_benchmark/density_sweep_full.csv`, `docs/literate/ieee8500_scaling.jl`,
`docs/make.jl`; reducing the harness's or `solve_welfare`/`solve_admm`'s own memory footprint is
architectural, out of scope, and machine-dependent to boot):**

**Item 4 (open):** whether a genuinely converged, memory-feasible IEEE-8500 headline point is
reachable at all without either (a) a larger/dedicated machine, (b) a shorter `T_horizon` (this
plan's harness already threads `T_horizon` as an explicit parameter — plan 25-05's `T_QUICK`
precedent could be generalized beyond `--quick`), or (c) a genuine reduction in JuMP model-build
memory (e.g. sparser variable/constraint construction, `direct_model` for the hot subproblems —
already a project-wide recommendation in `CLAUDE.md`'s Numerical/Performance guidance, never
applied at this scale). A future plan wanting a real converged, consolidated IEEE-8500 point needs
to resolve items 3 AND 4 together — item 3's tolerance gap is moot if item 4's memory wall means
the point never reaches consolidation in the first place.

### Item 4 — PARTIALLY RESOLVED 2026-08-22 (phase-25 gap-closure task 25-08, remedy (b) applied)

The user authorized remedy (b) directly: a new `--t-horizon <int>` CLI flag was added to
`scripts/benchmark_ieee8500.jl` (generalizing plan 25-05's `T_QUICK` precedent beyond `--quick`,
exactly as this item anticipated), with a validated floor of 10 (rejects lower, never silently
clamps — `T_HORIZON_FLOOR = T_QUICK`). The headline `ieee8500_modified()` fixture (4,875 buses /
4,874 branches) was then re-attempted at `--t-horizon 10` (vs the general sweep's `T=24`),
density=0.1 (the cheapest grid point), run completely alone on the measurement machine per the
project's memory-discipline protocol.

**Did the headline fixture fit in memory at a shorter horizon? YES — the memory wall IS closed at
T=10.** The process completed normally: no SIGKILL, no `journalctl -k` OOM evidence, peak observed
anon-rss during live monitoring ≈5.9 GB, comfortably below the T=24 OOM range (6.8–9.75 GB)
documented above. This directly answers remedy (b)'s premise: a shorter horizon DOES let this
network fit in memory on this machine, at least at the cheapest density.

**But this does NOT mean a real, converged, T=24-equivalent headline result now exists — GAP B is
only PARTIALLY closed.** At T=10 the centralized (Clarabel) solve reached status `ALMOST_OPTIMAL`
(`primal_status`/`dual_status` both `NEARLY_FEASIBLE_POINT`), not `OPTIMAL`, and was REFUSED by
`assert_solved!`'s strict trust policy (no `allow_almost` pass-through exists — the SAME structural
limitation plan 25-05's calibration ladder hit on `ALMOST_OPTIMAL` rungs, now appearing at real
headline network scale for the first time; every PRIOR headline attempt was OOM-killed before ever
reaching a numerical status at all). Because the centralized solve never returned a `ctx`,
`model_vars`/`model_cons`/`exact_maxgap`/`exact_verdict` could not be populated and
`IEEE8500_EXACT_ATOL` could not be evaluated — not even a failing verdict. ADMM ran independently
(its own build succeeded, no OOM) for 6 iterations before hitting the harness's own 120s D-18
wall-clock budget (`budget_exceeded`) without both residuals converging — it never reached
`solve_admm`'s hardcoded final-consolidation gate (item 3, still open) because it never got that
far. Per this task's own instruction, 0.1 did not "succeed comfortably," so no higher density was
attempted, and no tolerance was widened or retried to manufacture a passing verdict (T-25-12).

**Net effect on this item:** the MEMORY component of item 4 is resolved (a shorter horizon is a
genuine, sufficient fix for the OOM wall, at least at density=0.1 on this machine) — but a NEW,
separate CONDITIONING wall (Clarabel not reaching full `OPTIMAL` on this specific network/horizon
combination) now blocks exactness certification at headline scale, structurally similar to but
distinct from item 3's `solve_admm` consolidation-gate gap. **A future plan wanting the full T=24
headline result, or even a T=10 result with a certified exactness verdict, still needs to resolve
this new conditioning gap** (e.g. an `allow_almost`-style relaxation on the calibration/measurement
path specifically — never on the production exactness gate — or root-causing which branch(es)
drive `ALMOST_OPTIMAL` at this scale, mirroring plan 25-07's near-zero-impedance root-cause
methodology) in addition to items 2 and 3, both still open and untouched by this task.

Full measured evidence and the honestly-labeled `T_HORIZON=10` CSV row (explicitly marked
non-comparable to every other T=24 row in the same table) are in
`results/ieee8500_benchmark/density_sweep_full.csv` and this gap-closure task's own
`25-08-SUMMARY.md`.
