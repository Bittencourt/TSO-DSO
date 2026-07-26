---
phase: 17-real-ieee123-impedances
plan: 04
subsystem: docs
tags: [documenter, literate, opendss, ieee123, fortescue]

# Dependency graph
requires:
  - phase: 17-02
    provides: "src/data/ieee123_impedances.jl (committed IEEE123_BRANCH_RX_OHMS const table) and ieee123_modified() real-data ingestion path"
provides:
  - "docs/literate/ieee123_impedances.jl: literate, executed Documenter page documenting the public OpenDSS source, the Fortescue-averaging reduction formula (worked linecode.1 example), the units-trap resolution, and the reduction caveats"
  - "docs/make.jl: the new page registered in both the Literate-render tuple and the pages= navigation (Models section)"
affects:
  - "Future phases touching ieee123.jl/ieee123_impedances.jl now have a citable, always-executed doc page instead of relying solely on RESEARCH.md"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Literate doc page ends with a live executed call to the real ingestion function (ieee123_modified()), never a re-implemented reduction — matches lindistflow.jl's existing convention"
    - "Radial-invariant check uses throw(ArgumentError(...)) per WR-02, never @assert, even in a doc page"

key-files:
  created:
    - docs/literate/ieee123_impedances.jl
  modified:
    - docs/make.jl

key-decisions:
  - "docs/src/api.md left UNCHANGED — confirmed IEEE123_BRANCH_RX_OHMS is not exported (grep of src/data/ieee123.jl's export statement shows only ieee123_modified, build_ieee123, ieee123_load_nodes, ieee123_relabel_map), avoiding the Phase-15 checkdocs=:exports trap of surfacing a non-exported symbol."
  - "Replaced the plan's literal Task 1 action text (@assert length(feeder.branches) == length(feeder.buses) - 1) with the throw(ArgumentError(...)) form per the in-flight correction and the project's WR-02 no-@assert convention, already used elsewhere in this codebase (PerUnit.jl's assert_magnitudes_voltage)."

requirements-completed: [IMPED-01, IMPED-02]

# Metrics
duration: ~3min (task work); background full-docs-build verification still running at summary time
completed: 2026-07-26
---

# Phase 17 Plan 04: IEEE-123 Real Impedances — Literate Documentation Summary

Added a literate, executed Documenter page (`docs/literate/ieee123_impedances.jl`) narrating the public OpenDSS data source, the Fortescue-averaging positive-sequence reduction formula worked through the pinned `linecode.1` example, the units-trap no-conversion resolution, and the reduction caveats (transposition, single/two-phase laterals, regulators/switches absorbed-not-modeled) — registered in `docs/make.jl`'s render loop and navigation, with `docs/src/api.md` correctly left untouched.

## Performance

- **Duration:** ~3 min task work (2 commits, 43s apart)
- **Tasks:** 2 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Created `docs/literate/ieee123_impedances.jl` (121 lines): documents the exact fetch URLs + date (`2026-07-25`), the case-sensitivity trap (`IEEELineCodes.DSS` vs `.dss`), the Fortescue `R1 = mean(diag) - mean(offdiag)` formula worked through the live `linecode.1` numeric trace (`R1 ≈ 0.057967`, `X1 ≈ 0.118756`), the units-trap resolution (no length-unit conversion, citing `opendss.epri.com/LineCode1.html`), and the reduction caveats (transposition assumption, `n=1` single-phase-lateral short-circuit, regulators/caps/switches absorbed into the existing near-ideal switch impedance). Ends with a live `ieee123_modified()` call and an explicit `throw(ArgumentError(...))` radial-invariant check.
- Verified the page renders cleanly: `julia --project=docs -e 'using Literate; Literate.markdown(...)'` exits 0, writes `docs/src/generated/ieee123_impedances.md` (gitignored, regenerated at `makedocs` time — not committed).
- Registered the page in `docs/make.jl`: added `"ieee123_impedances.jl"` to the `for src in (...)` Literate tuple and `"IEEE-123 Real Impedances" => "generated/ieee123_impedances.md"` under the `"Models"` pages= section. `grep -o 'ieee123_impedances' docs/make.jl | wc -l` == 2, as required.
- Confirmed `IEEE123_BRANCH_RX_OHMS` is NOT exported (`src/data/ieee123.jl`'s single `export` line lists only `ieee123_modified, build_ieee123, ieee123_load_nodes, ieee123_relabel_map`) — left `docs/src/api.md` unchanged (`git diff docs/src/api.md` is empty), avoiding the Phase-15 `checkdocs=:exports` trap.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write the literate reduction doc page** - `1dbbba0` (docs)
2. **Task 2: Register the page in the Documenter build** - `9f7f3eb` (docs)

## Files Created/Modified

- `docs/literate/ieee123_impedances.jl` - New literate page: public-source citation, Fortescue-reduction worked example, units-trap resolution, reduction caveats, live executed `ieee123_modified()` call with radial-invariant check
- `docs/make.jl` - Added `"ieee123_impedances.jl"` to the Literate-render tuple and `"IEEE-123 Real Impedances" => "generated/ieee123_impedances.md"` to the `pages=` `"Models"` section (2 additions, 1 file)

## Decisions Made

- **In-flight correction applied**: replaced the plan's literal `@assert length(feeder.branches) == length(feeder.buses) - 1` action text with `length(feeder.branches) == length(feeder.buses) - 1 || throw(ArgumentError("radial invariant violated: |branches| must equal |buses|-1"))`, per the mandatory correction (WR-02 forbids `@assert`) and consistent with the project's existing tripwire convention (`PerUnit.jl`'s `assert_magnitudes_voltage`).
- **`docs/src/api.md` left unchanged**, confirmed by directly grepping `src/data/ieee123.jl`'s `export` statement rather than assuming — `IEEE123_BRANCH_RX_OHMS` is a plain internal `const`, invisible to `checkdocs=:exports`, so no `@autodocs` entry was added (adding one for a non-exported symbol would have broken the build, per the Phase-15 precedent this plan's threat model explicitly flags).

## Deviations from Plan

None beyond the explicitly mandated in-flight correction (Task 1's `@assert` → `throw(ArgumentError(...))` swap, documented above and already anticipated by the plan's own critical-constraints override). No other deviations — both tasks executed exactly as scoped.

## Issues Encountered

None. Both Literate-render verification commands (`docs/literate/ieee123_impedances.jl` alone, and the task-2 loop form) exited 0 on the first attempt. A full `julia --project=docs docs/make.jl` build was also kicked off as an extra belt-and-suspenders check beyond the plan's declared verification; it was still running in the background at summary-write time (Documenter builds against ~2276+ tests' worth of docstrings and executes 10 literate pages, so a full run legitimately takes several minutes) — the plan's own required verification commands (both already green) are the authoritative acceptance gate per the plan's `<verification>` section, not this supplementary full-build check.

## Next Phase Readiness

- The IEEE-123 real-impedance reduction is now fully documented end-to-end: RESEARCH.md (research trace) → `src/data/ieee123_impedances.jl` (committed data, Plan 17-02) → `docs/literate/ieee123_impedances.jl` (this plan, citable rendered doc page). No further phase-17 doc debt remains for IMPED-01/IMPED-02.
- Phase 17's next plan (if any) can build on this page's convention for any additional real-data documentation needs.

## Self-Check: PASSED

- FOUND: docs/literate/ieee123_impedances.jl
- FOUND: docs/make.jl (modified, grep count == 2)
- FOUND commit: 1dbbba0 (docs(17-04): add IEEE-123 real-impedance literate reduction page)
- FOUND commit: 9f7f3eb (docs(17-04): register IEEE-123 impedances page in Documenter build)

---
*Phase: 17-real-ieee123-impedances*
*Completed: 2026-07-26*
