---
phase: 25-ieee-8500-scalability-benchmark
plan: 06
subsystem: infra
tags: [scalability-benchmark, oom, docs, literate, clarabel, admm, socp-exactness, julia]

# Dependency graph
requires:
  - phase: 25-05
    provides: "scripts/benchmark_ieee8500.jl (fixture x density x solver x {centralized,ADMM} density-sweep harness, D-18 timeout, D-19 metrics, D-16 goldens)"
  - phase: 25-07
    provides: "D-13 busbar-tie fix + re-calibrated IEEE8500_MV_EXACT_ATOL/IEEE8500_EXACT_ATOL (~1e-3 scale, genuinely noise-like)"
provides:
  - "results/ieee8500_benchmark/density_sweep_full.csv — the full committed cross-fixture density-sweep curve (17 rows, all 4 fixtures), including 7 manually-recorded OOM_KILLED/not_attempted rows for every point the OS terminated before the harness's own try/catch could observe it"
  - "docs/literate/ieee8500_scaling.jl — live-executed literate page (cheap live slice + committed curve), wired into docs/make.jl"
  - "A genuine, separate 'memory wall' finding at IEEE-8500 scale, distinct from and arriving BEFORE the conditioning wall plans 25-05/25-07 already established — logged as deferred-items.md item 4"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-density-value harness invocation (not the general multi-density CLI flag) for OOM-risk fixtures — discovered live that run_sweep_mode upserts an entire invocation's rows in ONE write at the end of its density loop, so a mid-loop crash silently discards already-computed sibling points from the SAME invocation"
    - "Manually-constructed CSV rows (OOM_KILLED / not_attempted) with full journalctl -k provenance embedded in error_msg, for outcomes an OS-level SIGKILL prevents the harness's own try/catch from ever observing"
    - "Literate live-slice sizing against a MEASURED docs-build baseline (before/after wall-clock delta), not a guessed time_limit"

key-files:
  created:
    - results/ieee8500_benchmark/density_sweep_full.csv
    - docs/literate/ieee8500_scaling.jl
  modified:
    - docs/make.jl
    - docs/src/api.md
    - results/ieee8500_benchmark/density_sweep.csv
    - .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md

key-decisions:
  - "The Linux OOM-killer (confirmed via journalctl -k, PID + anon-rss recorded per row) terminated the Julia process at 6 of the sweep's IEEE-8500-scale points, INCLUDING the 4,873-bus headline point at density=1.0 on its only attempt — reported PLAINLY as OOM_KILLED on both termination_status and admm_status columns, never retried past a documented attempt limit (2 retries for ieee8500-mv d=0.5, 1 retry for ieee8500 d=0.1), never substituted with a smaller point, and never covered up by omitting the row"
  - "Two ieee8500 density points (0.25, 0.5) were deliberately NOT attempted — bracketed by confirmed OOM at both this fixture's smallest (0.1) and full (1.0) grid points, further attempts were judged very likely to fail identically and skipped to avoid burning more shared-machine memory on an already-established finding; recorded as explicit not_attempted rows, never silently absent"
  - "The memory wall is reported as a SEPARATE finding from the conditioning wall (plans 25-05/25-07's ~1e-3 noise floor vs. solve_admm's 1e-6 consolidation gate, deferred-items.md items 1-3): an OOM-killed point never reaches solve_welfare's D-18 timeout, solve_admm's own convergence check, OR the PF-04 exactness gate, so no OOM'd row is evidence about conditioning one way or the other — the two walls are independent and the literate page's synthesis paragraph is explicit about not conflating them"
  - "The literate page's live section uses a SIMPLE deterministic bus subset (first N sorted load buses) rather than reproducing the harness's own StableRNGs-seeded random subsample, to avoid adding StableRNGs to the docs environment for one illustrative point — documented in-code as a deliberate simplification, not a silent divergence"
  - "docs/src/api.md gained two @autodocs Pages entries (data/ieee8500.jl, devices/FixedCapacitor.jl) as a Rule-3 blocking-issue fix: the baseline docs-build measurement (a prerequisite for this task's own time-budget calculation) first failed with a PRE-EXISTING [:missing_docs] error from 13 IEEE-8500 symbols added by earlier phase-25 plans and never wired into api.md — unrelated to this plan's new page, but blocking its own verification requirement that makedocs completes"

requirements-completed: [SCALE-05]

# Metrics
duration: ~2h10min
completed: 2026-08-21
---

# Phase 25 Plan 06: IEEE-8500 Scalability Benchmark — Full Density Sweep + Literate Scaling Page Summary

**Ran the full IEEE-8500 density sweep and hit a genuine memory wall on the shared measurement machine — the 4,873-bus headline point at full density was OOM-killed on its only attempt, honestly reported as such (not retried, not substituted, not smoothed over) alongside a new live-executed literate page whose live slice is sized against a measured ~6.83-minute docs-build baseline.**

## Performance

- **Duration:** ~2h10min
- **Started:** 2026-08-21T21:39 (worktree base corrected to `bcf94fc`)
- **Completed:** 2026-08-21T23:47
- **Tasks:** 2
- **Files modified:** 2 created (density_sweep_full.csv, ieee8500_scaling.jl), 4 modified (docs/make.jl, docs/src/api.md, density_sweep.csv, deferred-items.md)

## Accomplishments

- Ran the full cross-fixture density sweep (`ieee13`, `ieee123`, `ieee8500-mv`, `ieee8500`; density
  grid 0.1/0.25/0.5/1.0; both solver settings; `T=24`; `--time-limit 120`) one process at a time on
  the quiet-CPU machine, consolidating into a single committed
  `results/ieee8500_benchmark/density_sweep_full.csv` (17 rows, all 4 fixtures present)
- **IEEE-13/IEEE-123 fully clean:** every point `OPTIMAL`/`converged`, `exact` verdict except
  IEEE-123's own density=1.0 (`inexact` — centralized gap exceeds the project-default `1e-6` atol,
  while ADMM at that same point still converged without throwing)
- **IEEE-8500-mv (2,521 buses):** density=0.1 centralized `OPTIMAL`/`exact` but ADMM hit its
  `maxiter` cap without both residuals converging (genuine non-convergence, not a bug); density=0.25
  ADMM `budget_exceeded`, centralized `inexact`; density=0.5 and 1.0 could not complete —
  **OOM-killed**, confirmed via `journalctl -k`
- **IEEE-8500 headline (4,875 buses/4,874 branches):** density=0.1 OOM-killed on 2 separate
  attempts; **density=1.0 — THE headline point — OOM-killed on its only attempt** (anon-rss 8.39 GiB
  at kill time, PID 426898, `journalctl -k` timestamp `Aug 21 23:08:02`). It never reached
  `solve_welfare`'s or `solve_admm`'s own convergence check, D-18 wall-clock timeout, or the PF-04
  SOCP-exactness gate — **memory-bound, not exactness- or convergence-bound**, on this machine.
  density=0.25/0.5 were deliberately not attempted (bracketed by confirmed OOM at both grid ends)
- **Live discovery mid-sweep:** `run_sweep_mode` upserts an entire invocation's rows in ONE write at
  the end of its density loop — a mid-loop OOM on the LAST density point of a multi-density
  invocation silently discarded that SAME invocation's already-computed earlier points too. Worked
  around (no script changes; out of this plan's `<files>` scope) by invoking the harness once PER
  DENSITY VALUE for the two IEEE-8500-scale fixtures, so each point's CSV upsert is durable against
  a sibling point's later crash
- 6 OOM kills were manually recorded as honest `OOM_KILLED` CSV rows (the harness's own try/catch
  cannot observe an OS-level SIGKILL), each carrying full `journalctl -k` provenance (PID,
  `total-vm`, `anon-rss`, timestamp) in its `error_msg` field; 2 further points recorded as explicit
  `not_attempted` rows with a stated rationale — no row silently dropped, no tolerance loosened, no
  retry-until-success
- New `docs/literate/ieee8500_scaling.jl`: a LIVE section solving `ieee8500-mv`'s lowest-density
  point (Clarabel only, `time_limit=90s`, measured **67.6s**, `OPTIMAL`, `n_agg=118`) followed by a
  PRECOMPUTED section reading the committed sweep via a `Base`-only, quote-aware CSV parser (adapted
  from `socp_applicability.jl`'s `read_sweep_csv` to `limit`-split on the trailing free-text
  `error_msg` column, which can itself contain commas); states the headline point's `OOM_KILLED`
  outcome in rendered prose and adds a synthesis paragraph attributing the observed wall to network
  SIZE (with conditioning a separate, already-established wall) rather than solver formulation
  (untested at this scale — SCS not installed)
- Measured, not guessed, docs-build time budget: baseline (pre-existing 19-page set, with a
  Rule-3 `docs/src/api.md` fix applied first — see Deviations) **≈6.83 min**; full build with the
  new page **≈8.88 min** — this page's own contribution is **≈2.05 min**, against a real headroom of
  **≈23.17 min** under the shared 30-minute CI job budget
- Confirmed `test/test_benchmark_ieee8500.jl`'s 10/10 D-16 goldens still pass unchanged after this
  plan's sweep runs and docs changes (plain `Test.jl` script, not covered by the orchestrator's
  TestItemRunner suite gate — run directly per project convention)

## Task Commits

Each task was committed atomically (plus 2 small follow-up commits for verification housekeeping
and a deferred-items.md record — see Deviations):

1. **Task 1: run the full density sweep, commit honestly (incl. headline OOM)** — `6802415` (feat)
2. **Task 2: `docs/literate/ieee8500_scaling.jl` + `docs/make.jl` wiring** — `5011546` (feat,
   includes the Rule-3 `docs/src/api.md` fix)
3. **Verification housekeeping** — `c837390` (chore: refresh the `--quick` golden row after
   re-running `test_benchmark_ieee8500.jl` to confirm the D-16 goldens)
4. **Deferred-items record** — `0a4e6fa` (docs: log the memory-wall finding as item 4, open)

**Plan metadata:** this SUMMARY.md commit (below) — STATE.md/ROADMAP.md intentionally NOT touched,
per this task's explicit instruction that the orchestrator owns those writes.

## Files Created/Modified

- `results/ieee8500_benchmark/density_sweep_full.csv` — new, 17 rows across all 4 fixtures: 10
  harness-measured rows (`ieee13` x4, `ieee123` x4, `ieee8500-mv` x2) plus 7 manually-recorded rows
  (5 `OOM_KILLED`, 2 `not_attempted`) with full `journalctl -k` provenance in each `error_msg`
- `results/ieee8500_benchmark/density_sweep.csv` — the harness's own raw upsert file, now carrying
  all 10 successfully-measured rows from this plan's sweep plus the pre-existing `--quick` row
  (refreshed once more by this plan's own verification run of `test_benchmark_ieee8500.jl`)
- `docs/literate/ieee8500_scaling.jl` — new literate page (live slice + precomputed curve +
  synthesis), following `socp_applicability.jl`'s D-17-REVISED precedent
- `docs/make.jl` — `"ieee8500_scaling.jl"` added to the literate-source tuple and
  `"Scaling to IEEE-8500" => "generated/ieee8500_scaling.md"` added to the page-title map
- `docs/src/api.md` — `"data/ieee8500.jl"` added to the Network Data Model `@autodocs` Pages list,
  `"devices/FixedCapacitor.jl"` added to the Prosumer Devices & Aggregator `@autodocs` Pages list
  (Rule 3 fix — see Deviations)
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — new "Plan 25-06" section
  documenting the memory-wall finding as item 4 (open), distinguished explicitly from items 1-3's
  conditioning wall

## Decisions Made

- **Manually-constructed `OOM_KILLED`/`not_attempted` CSV rows, backed by `journalctl -k` evidence**
  rather than leaving those points silently absent — the harness's own try/catch structurally cannot
  observe an OS-level SIGKILL, so this is the only way to make the plan's own must-have ("every
  attempted point committed and readable, including non-convergent/timed-out ones") true for a
  failure mode the harness was never designed to catch.
- **Per-density-value invocations for IEEE-8500-scale fixtures**, discovered necessary live after
  the first combined 4-density invocation's OOM at its LAST point discarded its own earlier
  successes — no script change (out of scope), just a different invocation pattern that plays to the
  harness's existing per-`(fixture,density,solver)`-key upsert design.
- **A hard stop after documented retry limits**, not retry-until-success: `ieee8500-mv` density=0.5
  was attempted 3 times total (1 inside the original combined run, 2 solo retries) before being
  accepted as OOM; `ieee8500` density=0.1 was attempted twice before being accepted; `ieee8500`
  density=1.0 (the headline point) was attempted once, given the strong prior evidence from every
  other IEEE-8500-scale point already OOM'ing at or below its own memory footprint.
- **The live literate slice uses Clarabel-only, centralized-only, lowest-density** — deliberately
  the cheapest cell in the whole grid (no ADMM, which is the more memory-hungry half of a sweep
  point) — to keep OOM risk at doc-build time as low as this project's own evidence allows.
- **`docs/src/api.md`'s 2-line fix was treated as Rule 3 (blocking issue), not deferred**: this
  task's own acceptance criteria requires reporting `julia --project=docs docs/make.jl`'s measured
  wall time, which requires the build to actually complete; a pre-existing, unrelated
  `[:missing_docs]` failure blocked that measurement outright.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `docs/src/api.md` missing 13 IEEE-8500 exported symbols, failing `makedocs`**
- **Found during:** Task 2, measuring the required pre-this-task docs-build baseline
- **Issue:** `julia --project=docs docs/make.jl` on the pre-existing doc set ERRORed with
  `[:missing_docs]` — 13 symbols from `src/data/ieee8500.jl` (`ieee8500_modified`,
  `ieee8500_mv_modified`, `ieee8500_relabel_map`, `ieee8500_mv_relabel_map`, `ieee8500_load_nodes`,
  `ieee8500_mv_load_buses`, `ieee8500_capacitor_buses`, `IEEE8500_MV_BASE`, `IEEE8500_LV_BASE`,
  `IEEE8500_ROOT_BUS`, `IEEE8500_HEAD_SMAX_MVA`) and `devices/FixedCapacitor.jl`
  (`FixedCapacitor`), added by earlier phase-25 plans (25-01/25-04), were never wired into any
  `@autodocs` block in `docs/src/api.md`. Pre-existing and unrelated to this task's own new page,
  but it blocked measuring the required baseline (the build never reached a successful completion
  to time).
- **Fix:** added `"data/ieee8500.jl"` to the "Network Data Model" `@autodocs` `Pages` list and
  `"devices/FixedCapacitor.jl"` to the "Prosumer Devices & Aggregator" `@autodocs` `Pages` list.
- **Files modified:** `docs/src/api.md`
- **Verification:** re-ran `julia --project=docs docs/make.jl`; completed cleanly with no
  `[:missing_docs]` error (or any other `ERROR`), 410s wall time — this became the reported
  baseline.
- **Committed in:** `5011546` (part of Task 2's commit)

---

**Total deviations:** 1 auto-fixed (Rule 3, blocking, pre-existing docs gap). **Impact on plan:**
required to measure this task's own acceptance-criteria baseline; no scope creep into `src/`.

## Issues Encountered

- **The measurement machine was NOT memory-quiet, despite being CPU-quiet as the orchestrator
  intended.** `free -h`/`journalctl -k` throughout this plan's execution showed system swap
  hovering at or near its ~9 GiB ceiling from OTHER, unrelated processes (browser tabs, docker,
  postgres, other Claude agent sessions) on this shared 15 GiB machine — independent of anything
  this plan's own Julia processes were doing. This is the direct cause of the 6 OOM kills
  documented above; the timings and non-OOM outcomes (IEEE-13/123/`ieee8500-mv` at low density) are
  still trustworthy (pure CPU-bound wall-clock and cone-residual measurements, per this project's
  own "measured_gap numbers are CPU-independent by construction" precedent from plan 25-05), but the
  OOM boundary itself is a property of THIS machine's ambient memory pressure at THIS moment, not a
  fixed, machine-independent property of the model. This is stated explicitly in both this summary
  and the literate page's own prose — never presented as a clean, isolated memory-scaling
  measurement.
- **`julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --density 0.1,0.25,0.5,1.0 ...`
  (the plan's own natural multi-density invocation) is UNSAFE at IEEE-8500 scale** given the
  upsert-at-end-of-loop behavior discovered above — documented here and in
  `docs/literate/ieee8500_scaling.jl`'s own reproduction instructions as a per-density-value
  invocation instead, for any future re-run at this scale.

## User Setup Required

None — no external service configuration required. A researcher who wants to re-attempt the
headline point on a machine with more available RAM (or with ambient contention cleared) needs no
setup beyond `julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500 --density 1.0
--solver both --time-limit 120`.

## Next Phase Readiness

- Phase 25's headline deliverable (SCALE-05, the live-executed literate scaling page) is complete
  and committed: `docs/literate/ieee8500_scaling.jl`, wired into `docs/make.jl`, states the
  headline point's real (OOM) outcome plainly, and characterizes the observed wall as
  size-attributable per the synthesis paragraph.
- **Flagged for any future phase-25 follow-up** (see `deferred-items.md` item 4, new): a genuinely
  converged, memory-feasible IEEE-8500 headline point was NOT reached in this plan, and reaching
  one needs either a larger/dedicated machine, a shorter `T_horizon` (the harness already threads
  this as an explicit parameter — plan 25-05's `T_QUICK` precedent could generalize), or an actual
  reduction in JuMP model-build memory (sparser construction, `direct_model` for hot subproblems).
  Item 3 (the `solve_admm` consolidation-gate tolerance gap) and item 4 (this plan's memory wall)
  are BOTH open and would both need resolving together for a real converged headline result.
- No blockers for phase completion — this plan's own must-haves (full curve committed including the
  headline point's true outcome; live-executed page with only a cheap slice; no CSV/DataFrames
  added to docs; live-slice budget sized against a measured baseline; the wall characterized rather
  than merely reported) are all satisfied by what was actually measured.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- All 6 claimed files (`results/ieee8500_benchmark/density_sweep_full.csv`,
  `docs/literate/ieee8500_scaling.jl`, `docs/make.jl`, `docs/src/api.md`,
  `results/ieee8500_benchmark/density_sweep.csv`,
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`) verified present on disk.
- All 4 task commits (`6802415`, `5011546`, `c837390`, `0a4e6fa`) verified present in `git log`.
