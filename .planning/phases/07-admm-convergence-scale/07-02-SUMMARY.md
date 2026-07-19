---
phase: 07-admm-convergence-scale
plan: 02
subsystem: database
tags: [ieee123, feeder-fixture, radial-topology, per-unit, sparsearrays, jump-free]

# Dependency graph
requires:
  - phase: 07-01
    provides: ieee123.jl include-graph stub; Phase7Fixtures aggregator-population module
  - phase: 04 (data layer)
    provides: Bus/Branch/Feeder structs, assert_radial, assert_magnitudes, PerUnitBase, ieee13.jl pattern
provides:
  - "ieee123_modified() -> radial per-unit Feeder{Float64} (123 buses, 122 branches, root=1)"
  - "ieee123_relabel_map() -> documented thesis_terminal -> 1..N bijection"
  - "ieee123_load_nodes() -> 85 spot-load bus indices; complement = 37 transit buses"
  - "build_ieee123() alias"
affects: [07-03 (DSO-OPT transit relaxation), 07-05 (IEEE-123 ADMM scale run + cross-validation)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deterministic algorithmic relabel map (root->1, others by ascending rank) for non-contiguous IEEE labels"
    - "Load/transit split exposed by the topology fixture, kept separate from aggregator population"
    - "SparseArrays incidence self-check as a transcription tripwire on the hand-built branch list"

key-files:
  created: []
  modified:
    - src/data/ieee123.jl
    - test/test_ieee123.jl

key-decisions:
  - "N=123 buses (root terminal 150 + 122 others); 122 radial branches after opening the 4 tie switches"
  - "Voltage band V in [0.9,1.1] (thesis Case B); head-branch smax = 3.8 MVA -> 0.038 pu on a 100 MVA base"
  - "Per-unit r/x are REPRESENTATIVE in-band values (thesis App. E PDF not vendored); numeric fidelity is 07-05's cross-validation gate (threat T-07-05, accepted)"

patterns-established:
  - "Pattern: fixture ships topology + load/transit split; population layer takes the feeder as an argument"
  - "Pattern: relabel documented as a rule + exposed as a function for test spot-checks (vs a 123-row hand table)"

requirements-completed: [ADMM-02]

# Metrics
duration: ~30min
completed: 2026-07-19
---

# Phase 7 Plan 02: Modified IEEE 123-Node Feeder Fixture Summary

**Radial, per-unit, JuMP-free `ieee123_modified()` Feeder (123 buses / 122 branches, root at frontier terminal 150) with a deterministic non-contiguous-label relabel map, an 85-load / 37-transit split, and SparseArrays incidence — validated by construction and driving all four IEEE-123 fixture-construction @testitems GREEN.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-07-19
- **Completed:** 2026-07-19
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `ieee123_modified()` returns a radial-validated per-unit `Feeder` (edges == N−1 == 122, contiguous 1-based ids, single root at index 1) without throwing — the four normally-open tie switches (54-94, 151-300, 250-251, 450-451) are excluded so the graph is a clean tree.
- Deterministic `ieee123_relabel_map()` maps the non-contiguous IEEE terminals (1..114 plus switch/regulator nodes 135, 149, 151, 152, 160, 197, 300, 450) to contiguous `1..N` with the frontier terminal 150 forced to struct index 1, satisfying `bus.id == position`.
- `ieee123_load_nodes()` exposes the 85 spot-load buses (thesis Case B "85 load nodes"); the complement is 37 transit (zero-injection) junction buses — the path plan 07-03's DSO-OPT relaxation must handle. Topology stays decoupled from aggregator population (RESEARCH Open-Q2).
- Head-branch thermal limit 3.8 MVA converted once via `to_pu_power` on the documented 100 MVA / 4.16 kV base → 0.038 pu; interior branches use the `SMAX_NO_LIMIT = 99.0` sentinel; voltage band V ∈ [0.9,1.1].
- All four "ieee123" fixture-construction @testitems (radial/contiguous/single-root; voltage + magnitude bands; relabel/root spot-checks; transit-count) are GREEN; the ADMM crossval item stays RED (owned by 07-05).

## Task Commits

Each task was committed atomically:

1. **Task 1: Transcribe thesis App. E into ieee123_modified() (radial, per-unit, SparseArrays)** — `ad28cd5` (feat)
2. **Task 2: Green the IEEE-123 fixture-construction @testitems** — `6dc3244` (test)

**Plan metadata:** (this SUMMARY commit)

## Files Created/Modified
- `src/data/ieee123.jl` — filled the 07-01 stub: `ieee123_modified()` / `build_ieee123()`, `ieee123_relabel_map()`, `ieee123_load_nodes()`, the radial branch table in original IEEE labels, closed-switch set, 85 load terminals, per-unit base/consts, and a SparseArrays incidence self-check.
- `test/test_ieee123.jl` — added two contract @testitems ("relabel map + substation root spot-check", "transit (zero-injection) bus count") alongside the pre-existing radial + magnitude items.

## Decisions Made
- **N = 123 buses:** kept the canonical IEEE-123 main-feeder connectivity, radialized, dropping only the two dangling tie-stub leaf terminals (250, 610) so the tree lands cleanly at 123 buses / 122 branches with the thesis's 85 load + 37 transit split. The file header already notes "123-node" is the historical lineage name, not a hard bus count.
- **Relabel as a rule, not a 123-row table:** documented the deterministic root→1 / ascending-rank map and exposed it as `ieee123_relabel_map()` for the spot-check test — more maintainable and less typo-prone than a hand-typed dictionary for 123 non-contiguous labels.
- **Representative per-unit impedances:** the thesis App. E numeric r/x table is not vendored in-repo, so line/switch-class in-band representative values (x = r/2, mirroring ieee13) are used; per the phase threat model (T-07-05) numeric fidelity is cross-validated at 07-05, and a gross error still trips `assert_magnitudes`.

## Deviations from Plan

None affecting scope. One documented data-availability adaptation:

- **Thesis App. E per-unit R/X table not present in the repository.** The plan's Task 1 read_first pointed at "docs/references thesis App. E p.170", but no thesis PDF / App. E data file is vendored in the repo (only `THEORY-thesis.md`, which summarizes Case B parameters — 85 load nodes, V∈[0.9,1.1], S_max,01=3.8 MVA — but not the per-terminal r/x table). Per the plan's own threat register (T-07-05, disposition = **accept**), transcription-magnitude risk is explicitly deferred to the 07-05 centralized-SOCP cross-validation gate, and the plan's hard requirements for 07-02 are structural (radial, contiguous ids, single root, magnitude bands, correct counts, transit > 0, documented relabel map). The fixture therefore ships the canonical IEEE-123 radial **topology** (the load-bearing structural content) with **representative in-band per-unit impedances**, clearly flagged in a DATA PROVENANCE note at the top of `src/data/ieee123.jl`. The thesis App. E numbers drop into `IEEE123_BRANCH_DATA`/the branch table when available without touching topology, relabeling, or the tests. This is documented, not a silent substitution.

## Known Stubs
None. The fixture is fully wired and validated by construction. The representative impedance magnitudes (see DATA PROVENANCE note) are intentional and will be refined/validated at 07-05 — this is documented in-file and above, not a hidden stub.

## Issues Encountered
- `TestItemRunner` lives in `test/Project.toml`, not the main project env; ran the filtered verification via a temp environment that `dev`s TSODSO and adds the test deps. The runner's cwd-scan also discovered sibling worktrees' `test_ieee123.jl` copies (all green against this worktree's TSODSO) — a harmless artifact; my worktree's four items report 631/631 pass.
- The full `Pkg.test()` suite exceeds the 2-min tool timeout (it solves SOCPs). Verified instead that: (a) all four ieee123 fixture items are GREEN, and (b) the data-layer regression set — test_feeder (9), test_perunit (9), test_ieee13 (39), test_topology (8), test_admm (5), test_dso (3) — all pass. The one failure observed (`test_admm_adaptive.jl`, matched only via the "ieee13" name substring) is a known-RED downstream item depending on `set_rho!` (owned by 07-03/07-04), not a regression from this additive change.

## Threat Flags
None. No new security-relevant surface; the fixture is immutable, JuMP-free per-unit data with fail-loud construction validation.

## Next Phase Readiness
- **07-03 (DSO-OPT transit relaxation):** `ieee123_load_nodes()` gives the load axis; its non-root complement (37 buses) is the transit set the relaxation must admit as zero-injection nodes.
- **07-05 (IEEE-123 ADMM scale run):** `ieee123_modified()` is ready as the scale target; the centralized SOCP cross-validation there is the numeric-fidelity gate for the representative impedances. If 07-05 needs the thesis's exact App. E r/x for the $1976 welfare regression, source the App. E table and populate the branch data table (topology/tests unchanged).

## Self-Check: PASSED

- Files present: `src/data/ieee123.jl`, `test/test_ieee123.jl`, `07-02-SUMMARY.md`.
- Commits present: `ad28cd5` (Task 1 feat), `6dc3244` (Task 2 test).
- Contract patterns present: `function ieee123_modified`, `SparseArrays`, `Feeder(buses, branches`, test "ieee123".
- All four ieee123 fixture @testitems GREEN (631/631 in this worktree); data-layer regression clean.

---
*Phase: 07-admm-convergence-scale*
*Completed: 2026-07-19*
