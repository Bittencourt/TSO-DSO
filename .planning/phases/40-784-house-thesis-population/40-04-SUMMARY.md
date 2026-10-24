---
phase: 40-784-house-thesis-population
plan: 04
subsystem: docs
tags: [julia, literate, documenter, population-composition, calibration-provenance, committed-csv-pattern, agreement, scaling-report, appendix-e]

# Dependency graph
requires:
  - phase: 40 plan 01 (:case_a_784 selector)
    provides: build_population(:case_a_784, ...) (10 bus-level roll-ups, 784 houses),
      case_a_household_map, _CASE_A_TOTAL_HOUSES/_CASE_A_PV_FRACTION, the _IEEE13_*
      scale constants, per-house hash seeding
  - phase: 40 plan 02 (scaling report)
    provides: results/case_a_population/scaling_ladder.csv + threads_sweep.csv (committed
      measured CSVs the page reads), scripts/run_case_a_scaling.sh + case_a_scaling.jl
      (reproduction commands)
  - phase: 40 plan 03 (agreement measurement)
    provides: results/case_a_population/agreement.csv (the honest POP-04 record the page
      cites: certified centralized leg, refused decomposed leg, no pinnable band),
      scripts/case_a_agreement.jl + the :slow test file (reproduction commands)
  - phase: 35/39 measurement pages
    provides: the ieee8500_scaling.jl page conventions (budget note, Base-only CSV
      reader, dated attributed Appended section, docs-env import style)
provides:
  - "docs/literate/case_a_population.md — the auditable POP-06 record: composition
    measured live at build time, calibration provenance, Appendix-E unavailability
    table with each replacement rule, agreement + scaling sections read from the
    committed CSVs, reproduction commands"
  - "docs/make.jl — page registered at BOTH sites (Literate tuple + Experiments
    pages tree)"
  - "docs/Manifest.toml — TSODSO deps list updated with LinearAlgebra (the docs env
    precompile was broken at HEAD by the phase-39 stdlib-dep addition)"
affects: [phase verifier (POP-06 routing), phase-41 (pv_group seam documentation),
  thesis readers]

# Tech tracking
tech-stack:
  added: []   # zero new packages
  patterns:
    - "Committed-CSV doc page: agreement/scaling numbers READ at build time via a
      Base-only parser (zero literal numerals for measured quantities in the source);
      composition numbers COMPUTED live from the deterministic build"
    - "Guard-clean doc authoring: new files verified to add zero planning-identifier
      hits (scoped guard scan) against the repo-wide guard"

key-files:
  created:
    - docs/literate/case_a_population.jl
    - .planning/phases/40-784-house-thesis-population/deferred-items.md
  modified:
    - docs/make.jl
    - docs/Manifest.toml

key-decisions:
  - "Composition measured LIVE at docs-build time (784 seeded profile draws + struct
    construction, seconds); every solver-derived number READ from the committed CSVs —
    the page performs no optimization of any kind (solve_welfare|solve_admm grep
    returns nothing in the page source)"
  - "Agreement section states exactly what is and is NOT established: the POP-04
    agreement band is NOT pinned — the centralized leg certifies only at the recorded
    tol_gap_1e-10 solver path, the decomposed leg converges (iters from the CSV) and
    is refused by the battery-complementarity certificate; deltas/band cells print as
    '-' from the CSV's empty cells, never invented"
  - "The page is written planning-identifier-clean (no 'Phase N', no plan refs, no
    planning-file citations): the repo-wide CI guard already fails at HEAD with 63
    pre-existing hits (logged to deferred-items.md); this plan's files add zero"
  - "Thesis reference totals (PV = 5 MWp, elastic = 6.5 MW, inelastic = 1.5 MW) stated
    as provenance CONTEXT, explicitly not targeted — thesis-MW matching deferred to a
    later ablation phase"

patterns-established:
  - "Docs-page budget note cites the measured ~6.8-min baseline and states the page's
    own live-cost class (build-only, no solves) — third page to carry the note"
  - "Scoped planning-ID guard scan as a per-plan hygiene check for new tracked files"

requirements-completed: [POP-06]

# Metrics
duration: 52min
completed: 2026-10-24
docs_build_wall_times: "9m45s / 14m12s / 10m41s (three full builds; >= 15 min headroom
  vs the 30-min docs CI budget; page's own slice is build-only seconds)"
---

# Phase 40 Plan 4: Case-A Population Composition & Calibration Docs Summary

**The 784-house population is now auditable from the docs alone: a new literate page
measures the composition live at build time (784 houses, 3×784 devices, 26.6 MWp PV,
3.2 MW inelastic, 1000 + 500 MW elastic bounds), states the full calibration provenance
and the Appendix-E replacements, and reads the agreement/scaling numbers from the
committed CSVs — with the POP-04 band honestly reported as NOT pinned.**

## Performance

- **Duration:** 52 min
- **Started:** 2026-10-24T16:02:36Z
- **Completed:** 2026-10-24T16:55:35Z
- **Tasks:** 2/2
- **Files modified:** 1 new page + 2 docs configs + 1 planning note

## Docs Build Wall Time (the budget-honesty convention)

Three full `julia --project=docs docs/make.jl` runs measured this plan: **9m45s**,
**14m12s**, **10m41s** (exit 0 each; host-load dependent — the first included the
one-time docs-env TSODSO precompile after the manifest fix). Against the shared
`timeout-minutes: 30` docs CI job that leaves **≥ 15 minutes of real headroom**. The
page's OWN live slice is build-only — 784 seeded profile draws plus struct
construction and three CSV reads, seconds total (verified by a standalone run of the
identical code before the first build); the page contains no solve calls
(`grep -E "solve_welfare|solve_admm" docs/literate/case_a_population.jl` returns
nothing).

## Accomplishments

- **POP-06 delivered:** `docs/literate/case_a_population.jl` — reachable in the docs
  navigation under "Experiments" → "Case A Population (784 houses)". Sections:
  1. *Overview* — 784 houses over the 10 IEEE-13 load buses rolled into 10 bus-level
     aggregators, the one-aggregator-per-load-node constraint that forces the roll-up,
     and where house granularity lives (construction, household map, composition).
  2. *Construction rule* — per-bus house counts table tallied LIVE from
     `TSODSO.case_a_household_map` at the standard seeds; the base-share + residue
     rule with its ascending-bus-id tiebreak; the per-house hash-seed derivation in
     prose (`hash((s_pop, :house, bus, house_index)) % typemax(UInt32)`, per-house
     never `seed + bus`, collision-freeness test-enforced); the `pv_group` field with
     `_CASE_A_PV_FRACTION = 1.0` stated honestly (all-PV is the locked default-fraction
     reading; the field is generic so a later phase can lower the constant).
  3. *Calibration provenance* — per-house scale = IEEE-13 residential scale ÷
     houses-per-bus with the load-bearing rationale (bus aggregates preserved at the
     validated regime; raw scales ≈ 78× the calibrated head loading, near-certainly
     infeasible); fractions kept from `:default`; thesis totals as context only.
  4. *Composition (live)* — houses 784; device mix 784 Thermostatic + 784 Deferrable +
     784 PVBattery (3/house, 2352 total); total PV nameplate 26.6162 MWp; inelastic
     3.19722 MW (Σ per-bus Pdc peaks); elastic bounds 1000 MW thermostatic + 500 MW
     deferrable; battery fleet 2.5 MW / 10 MWh; per-bus table (buses 2–11 at 79/78
     houses) — all computed in-page, matching the test-enforced construction facts.
  5. *Agreement* — reads `agreement.csv` via the Base-only parser; reports the
     certified centralized welfare (-378163.58894571784 at the `tol_gap_1e-10`
     recorded path), the decomposed leg's 80 iterations + `error:CertificateError`,
     and prints the deltas/band cells as "-" exactly because they are empty in the
     CSV — the page states the POP-04 band is NOT pinned and why; gate-then-golden
     ordering + the `:slow` test file cited by name.
  6. *Scaling* — reads `scaling_ladder.csv` + `threads_sweep.csv`; renders the
     iters-vs-rungs and wall-vs-threads tables with the speedup column COMPUTED from
     the measured walls; states measured-not-assumed and that the recorded modest
     positive speedup (1.44× at 4 threads) is simply what the CSVs show.
  7. *Appendix E* — the three unavailable thesis parameters (per-house appliance
     ownership, per-house PV sizing, per-node house counts) each paired with its
     replacement rule.
  8. *Reproduction* — the driver + per-leg commands + agreement script + slow-lane
     test invocation, and a dated "Appended" section naming every source CSV and row
     key.
- Registered at BOTH `docs/make.jl` sites (`grep -c case_a_population docs/make.jl`
  = 3 ≥ 2).
- **Blocking fix carried:** `docs/Manifest.toml`'s TSODSO deps list lacked
  `LinearAlgebra` (added to the root project in Phase 39, after the docs manifest was
  last resolved) — the docs env could not precompile TSODSO at all. `Pkg.resolve()`
  produced exactly a one-line manifest change; `julia_version = "1.12.5"` lockstep
  preserved. Without this fix the docs CI job is red regardless of this plan.
- CI-guard sweep green: `check_scripts_index.py` exit 0; pinned-JuliaFormatter pass
  over the touched files is content-loss-clean (repo guard: "no content change,
  whitespace/commas only", 224 files) and idempotent (second pass returns true).

## Task Commits

Each task was committed atomically:

1. **Task 1: literate page + both make.jl registrations** - `d775a92` (feat; includes
   the docs-manifest blocking fix)
2. **Task 2: docs-build verification + CI-guard sweep** - `90aa998` (style: formatter
   reflow + deferred-items note)

## Files Created/Modified

- `docs/literate/case_a_population.jl` — the POP-06 page (new)
- `docs/make.jl` — registration at both sites (Literate tuple + Experiments tree)
- `docs/Manifest.toml` — one line: LinearAlgebra added to the TSODSO deps list
- `.planning/phases/40-784-house-thesis-population/deferred-items.md` — the logged
  pre-existing planning-ID guard failure (out-of-scope discovery)

## Decisions Made

- **Live composition, CSV measurement:** composition numbers are computed from the
  deterministic build in-page; agreement/scaling numbers are parsed from the committed
  CSVs — the source contains zero literal numerals for measured quantities (the plan's
  anti-drift acceptance criterion, verified by the CSV-read code paths and the
  printed-output spot checks in the built HTML).
- **Honest non-agreement:** the page reports the POP-04 state exactly as recorded —
  centralized certified at the tightened-solver path, decomposed refused at the battery
  certificate, no measurable deltas, no pinnable band — never smoothing the refusal
  into a pass.
- **Guard-clean authoring:** the page cites artifacts by repo path and avoids planning
  identifiers entirely, so it adds zero hits to the already-failing repo-wide guard
  (scoped scan of the two touched files: clean).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Docs env could not precompile TSODSO (stale manifest)**
- **Found during:** Task 1 (first docs build: `ArgumentError: Package TSODSO does not
  have LinearAlgebra in its dependencies`)
- **Issue:** the root project gained a LinearAlgebra dependency in Phase 39
  (threaded-executor work), but `docs/Manifest.toml`'s TSODSO entry predates it — the
  docs env failed to load the package at all, independent of the new page.
- **Fix:** `julia --project=docs -e 'using Pkg; Pkg.resolve()'` — exactly one line
  changed (LinearAlgebra added to the TSODSO deps array); julia_version lockstep
  (1.12.5) preserved, matching the CI docs job's pin.
- **Files modified:** docs/Manifest.toml
- **Verification:** subsequent builds exit 0
- **Committed in:** d775a92

### Verify-command adaptations (no code impact)

- The plan's Task-2 verify greps `docs/build/generated/*.md`, but the actual build
  layout emits Literate markdown at `docs/src/generated/case_a_population.md` and
  Documenter HTML at `docs/build/generated/case_a_population.html` (the `.md` glob
  matches nothing in `docs/build/`). Verified against BOTH real paths: the markdown
  carries the static content markers; the HTML carries the rendered live outputs
  (composition table, agreement row, ladder + sweep tables, computed speedups).
- Task-2's timing step was executed as three full builds (9m45s / 14m12s / 10m41s) to
  give the SUMMARY an honest host-load range rather than a single sample.

---

**Total deviations:** 1 auto-fixed (blocking) + 2 verify-command adaptations
**Impact on plan:** the manifest fix was a precondition for ANY docs build; the verify
adaptations follow the build system's real file layout. No scope creep; no src/ changes
(the code is frozen by 40-01..03 and stays frozen — `git diff` over src/ remains empty
for this plan).

## Issues Encountered

- **Pre-existing, out of scope (logged to deferred-items.md):** the CI
  planning-identifier guard (`check_planning_ids.py`) fails repo-wide at HEAD with 63
  hits across 20+ files (mostly "Phase N" prose from the unpushed Phase-39/40 work;
  the branch is ~16 days ahead of origin/main). Not caused by this plan; this plan's
  files were written guard-clean and verified to add ZERO hits (scoped scan exit 0).
  Resolution is a repo-wide rewording effort for a future hygiene task.
- First docs build after the manifest fix included a one-time docs-env TSODSO
  precompilation (~3 min of the 9m45s); later builds are representative.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. Every figure on the page is wired: composition numbers come from the live
deterministic build; agreement/scaling numbers come from the committed CSVs; the
missing agreement-band cells print as "-" because the CSV's cells ARE empty (the
measured state), with the prose explaining exactly why.

## Threat Surface Scan

No new surface beyond the plan's `<threat_model>`: T-40-12 (information integrity) —
mitigated as planned (CSV-read measured quantities, dated Appended attribution naming
source file + row key); T-40-13 (docs CI DoS) — mitigated (no solve calls in the page,
grep-verified; three measured whole-build wall times recorded with ≥ 15 min headroom);
T-40-14 (repudiation) — mitigated (every calibration rule, residue tiebreak, seeding
idiom and Appendix-E replacement stated in-page). No new endpoints, auth paths, file
access patterns or schema changes.

## Next Phase Readiness

- **POP-06 complete** — the population is auditable by a researcher who never reads the
  source. Combined with 40-01..03: POP-01/02/03/05/06 done; POP-04 remains routed to
  the phase verifier (agreement band blocked by the measured battery-certificate
  refusal — candidate resolutions listed in 40-03's summary).
- The page's Appended section names every CSV + row key, so a future re-measurement
  (e.g. after the certificate investigation lifts the refusal) updates the page by
  re-running the scripts and rebuilding docs — no page edits needed.
- The stale-docs-manifest failure mode is worth remembering: any future root
  Project.toml dependency change requires a docs-env `Pkg.resolve()` or the docs job
  fails to precompile.

## Self-Check: PASSED

- FOUND: docs/literate/case_a_population.jl (on disk, ~380 lines ≥ min 120)
- FOUND: docs/make.jl registrations (grep count 3 ≥ 2; both sites)
- FOUND: docs/src/generated/case_a_population.md (19.7 KB) with all content markers
  (Appendix E ×2, calibration provenance, ascending bus-id rule, all three CSV paths,
  slow test file); docs/build/generated/case_a_population.html with rendered outputs
  (784/10-aggregator/3-devices-per-house facts, 784 Thermostatic, 1.44x speedup,
  error:CertificateError ×5, welfare -378163.58894571784, tol_gap_1e-10)
- FOUND: docs/Manifest.toml one-line fix in commit d775a92
- FOUND: commits d775a92 (Task 1) and 90aa998 (Task 2) in git log
- `grep -E "solve_welfare|solve_admm" docs/literate/case_a_population.jl` → no matches
- Docs build exit 0 (three runs measured); check_scripts_index.py exit 0
- Scoped planning-ID guard on the plan's files: exit 0 (zero new hits)
- Formatter content-loss guard over the whole tracked tree: clean; second format pass
  idempotent (true)

---
*Phase: 40-784-house-thesis-population*
*Completed: 2026-10-24*
