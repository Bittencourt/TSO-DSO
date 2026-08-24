---
phase: 25-ieee-8500-scalability-benchmark
plan: 03
subsystem: data
tags: [feeder, per-unit, radial-topology, ieee8500, julia]

# Dependency graph
requires:
  - phase: 25-01
    provides: "Generated src/data/ieee8500_impedances.jl (MV/LV branch Ohms, xfmr edges,
      capacitor kvar, load kW, regulator/switch edge set)"
provides:
  - "ieee8500_modified() — headline full MV+LV Feeder (4,875 buses) at S_base=0.5 MVA"
  - "ieee8500_mv_modified() — MV-only control Feeder (2,521 buses, D-02)"
  - "ieee8500_relabel_map / ieee8500_mv_relabel_map — deterministic bus_name -> 1..N maps"
  - "ieee8500_load_nodes / ieee8500_mv_load_buses / ieee8500_capacitor_buses — bus-role helpers
    for plan 25-04's population/device layer"
  - "Corrected IEEE8500_REGULATOR_EDGES (48 -> 43): 5 genuine, source-confirmed normally-open
    switch=y ties excluded, resolving the raw-data non-radiality plan 25-01 flagged as unverified"
affects: [25-04, 25-05, 25-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Root = the substation transformer's own HV-side bus name (found via a New Transformer.*
      buses=(...) statement), so the substation transformer itself becomes the fixture's
      near-ideal head branch — carries the head-only thermal limit, never modeled as a separate
      unconstrained branch"
    - "Per-voltage-level bus classification via a verified 100%-reliable string-prefix rule
      (startswith X/SX) rather than a topology walk, once directly confirmed against the full
      bus-name population"
    - "Hybrid @testitem/plain-Test.jl file: a no-op @testitem stub (defined only if undefined)
      lets the SAME file run green both under TestItemRunner and via a direct
      `julia --project=. test/test_X.jl` quick command"

key-files:
  created:
    - src/data/ieee8500.jl
    - test/test_ieee8500.jl
  modified:
    - src/TSODSO.jl
    - scripts/reduce_ieee8500_impedances.jl
    - src/data/ieee8500_impedances.jl

key-decisions:
  - "Root bus = \"HVMV_Sub_HSB\" (the HVMV_Sub substation transformer's own High-Side Bus,
    Transformers.dss), not an arbitrary MV bus — makes the substation transformer itself the
    modeled head branch, carrying the 27.5 MVA D-08 thermal limit, exactly mirroring ieee123.jl's
    treatment of its own substation frontier"
  - "Fixed a plan-25-01 data-parsing gap (Rule 1/3 deviation): the reduction script silently
    treated all 43 Lines.dss switch=y records as closed, producing 5 independent cycles
    (edges - (buses-1) == 5) that made assert_radial throw at construction time. Traced to the
    ground truth already present in the source data: exactly 5 of the 43 records carry an
    explicit enabled=False (genuine normally-open ties). Fixed scripts/reduce_ieee8500_impedances.jl
    to capture enabled= and exclude those 5, regenerating IEEE8500_REGULATOR_EDGES (48 -> 43).
    No heuristic spanning-tree guess was used — the ground truth was in the vendored .dss text."
  - "ieee8500_mv_load_buses()'s measured count is 1138 (not 1177) — 1,138 distinct MV buses host
    the 1,177 service transformers post phase-suffix collapse, confirming the plan's own
    'multiple transformers CAN share one MV bus' expectation empirically."
  - "Headline bus count is 4,875 (not the ~4,873 estimate) — 2 extra virtual buses
    (HVMV_Sub_HSB, regxfmr_HVMV_Sub_LSB) from the substation-transformer/regulator chain are
    included as real graph nodes since root=HVMV_Sub_HSB requires them; MV-only count is 2,521
    for the same reason."

patterns-established:
  - "Hybrid @testitem + standalone Test.jl file pattern (no-op @testitem stub defined only if
    undefined) — reusable for any future fixture test file that needs both TestItemRunner
    discovery and a direct quick-command run"

requirements-completed: [SCALE-01, SCALE-02]

# Metrics
duration: 40min
completed: 2026-08-21
---

# Phase 25 Plan 03: IEEE-8500 Fixture Construction (MV+LV headline + MV-only control) Summary

**Two committed IEEE-8500 `Feeder`s (4,875-bus headline MV+LV, 2,521-bus MV-only control) at `S_base=0.5 MVA`, built by fixing a plan-25-01 data gap that silently made the raw topology non-radial — the source `.dss` text's own `enabled=False` field on 5 of 43 switch records was the ground truth needed to resolve it.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-08-21 (worktree base corrected to `eebed57`)
- **Completed:** 2026-08-21T11:32:20Z
- **Tasks:** 3
- **Files modified:** 2 created, 3 modified

## Accomplishments

- Built `ieee8500_modified()` (headline, 4,875 buses / 4,874 branches) and `ieee8500_mv_modified()`
  (MV-only control, D-02, 2,521 buses / 2,520 branches), both passing `Feeder`'s own construction
  invariants (`assert_radial`, `assert_magnitudes`) for real at IEEE-8500 scale
- Root = `"HVMV_Sub_HSB"`, the substation transformer's own HV-side bus (found directly in
  `Transformers.dss`), confirmed by BFS to have degree 1 and reach every bus in both fixtures
- Resolved the non-radiality plan 25-01 flagged as an open, unverified concern: the raw combined
  topology (all 43 `switch=y` records treated as closed) has exactly 5 independent cycles; the
  vendored source text itself already records which 5 are genuinely normally-open
  (`enabled=False`) — fixed the upstream reduction script rather than guessing a spanning tree
- Applied the confirmed 3-winding transformer per-unit formula at ingestion
  (`r_pu=(r_pct/100)*(S_base_kVA/kva)`), pinned exactly at CT5 (r=3.00/x=2.72 pu)
- Exposed the five bus-role helper functions (`ieee8500_load_nodes`, `ieee8500_mv_load_buses`,
  `ieee8500_capacitor_buses`, plus both relabel maps) plan 25-04's population layer needs
- 6 `@testitem` blocks + a standalone hybrid quick-command block in `test/test_ieee8500.jl`
  (22,195 assertions, exit 0), including the pinned CT5 regression trap and the D-06 measured
  ~9-order impedance-spread report

## Task Commits

Each task was committed atomically:

1. **Task 1: PerUnitBase + relabel + branch/bus construction for ieee8500_modified()** - `83dd3a3` (feat)
2. **Task 2: MV-only control fixture (D-02) + bus-role helper exports** - included in `83dd3a3` (see Deviations — combined with Task 1's commit)
3. **Task 3: test/test_ieee8500.jl construction/invariant tests + pinned transformer regression trap** - `9cdc3ba` (test)

**Plan metadata:** commit pending (this SUMMARY.md, per worktree-mode convention — STATE.md/ROADMAP.md owned by the orchestrator)

## Files Created/Modified

- `src/data/ieee8500.jl` - Both fixture builders, both relabel maps, five bus-role helpers, `IEEE8500_MV_BASE`/`IEEE8500_LV_BASE`/`IEEE8500_ROOT_BUS`/`IEEE8500_HEAD_SMAX_MVA` constants
- `src/TSODSO.jl` - One new include line (`data/ieee8500.jl`, after `data/ieee123.jl`)
- `scripts/reduce_ieee8500_impedances.jl` - Captures `enabled=` on `switch=y` records; splits `switch_pairs` (38 enabled) from `disabled_switch_pairs` (5 normally-open); only enabled pairs reach `IEEE8500_REGULATOR_EDGES`
- `src/data/ieee8500_impedances.jl` - Regenerated (`REG: 48 -> 43`); `IEEE8500_REGULATOR_EDGES` no longer contains the 5 `enabled=False` ties
- `test/test_ieee8500.jl` - Construction/invariant tests, hybrid `@testitem`/standalone pattern

## Decisions Made

- **Root bus = `"HVMV_Sub_HSB"`** (substation transformer's HV-side bus). Confirmed by direct BFS: reaches all buses in both fixtures with degree 1, and the substation transformer's own edge (near-ideal, via `IEEE8500_REGULATOR_EDGES` membership) naturally becomes the head branch carrying the D-08 27.5 MVA rating — no separate substation-transformer branch needed, mirroring `ieee123.jl` exactly.
- **Per-voltage-level classification via string prefix** (`startswith(name, "X") || startswith(name, "SX")`) — verified by exhaustive enumeration against the real bus-name population (no MV bus starts with X/SX; every LV-only bus does) before committing to this simpler-than-a-topology-walk rule.
- **`ieee8500_capacitor_buses()` uses the headline relabel map by default**, with an optional `relabel_map` argument. Verified computationally that the resulting ids happen to be identical across both fixtures' relabel maps for these specific 4 capacitor buses (their `"R#####"` names sort before all `X*`/`SX*`/`regxfmr_*` names, so their relative rank is unaffected by whether LV names are present) — satisfying the plan's "valid index into BOTH fixtures" acceptance criterion without any special-casing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/Rule 3 - Bug / Blocking] `IEEE8500_REGULATOR_EDGES` silently included 5 genuinely normally-open switch ties, making the raw topology non-radial**
- **Found during:** Task 1 (constructing `ieee8500_modified()` and running `assert_radial` for the first time at full scale)
- **Issue:** Plan 25-01's reduction script parsed every `switch=y` `Lines.dss` record as closed and merged all 43 into `IEEE8500_REGULATOR_EDGES` alongside the 4 regulator-bank/substation edges (48 total). Direct computation confirmed this produces `edges - (buses - 1) == 5` — 5 independent cycles — which makes `Feeder`'s `assert_radial` throw `ArgumentError` unconditionally; `ieee8500_modified()` could not construct at all. This exact risk was flagged (unresolved) in 25-01's own SUMMARY.md: "whether `ieee8500_modified()`'s full topology... resolves to exactly `buses-1`... or surfaces a genuine non-radiality finding requiring a documented decision, is unverified by this plan and is plan 25-03's construction-time concern."
- **Investigation:** A heuristic Kruskal/union-find spanning-tree construction correctly found the CORRECT COUNT (5 redundant edges) but NOT a unique, order-independent SET of which 5 to drop (multiple valid spanning trees exist over the same 39→1 component-merge). Cross-referencing the actual vendored `Lines.dss` source text directly found the real, authoritative answer already present in the data: exactly 5 of the 43 `switch=y` records carry an explicit `enabled=False` field (e.g. `New Line.WD701_48332_sw ... switch=y ... enabled=False`) — genuine normally-open tie switches, not an inferred choice.
- **Fix:** `parse_mv_lines` in `scripts/reduce_ieee8500_impedances.jl` now captures `enabled=` on `switch=y` records, splitting them into `switch_pairs` (38 enabled) and `disabled_switch_pairs` (5 disabled); `main()` asserts both counts explicitly (38/5) and only the enabled 38 reach `build_regulator_edges`/`IEEE8500_REGULATOR_EDGES`. Mirrors `ieee123.jl`'s own treatment of its 4 normally-open tie switches (excluded from `IEEE123_EDGES` entirely). Regenerated `src/data/ieee8500_impedances.jl` (`REG: 48 -> 43`).
- **Files modified:** `scripts/reduce_ieee8500_impedances.jl`, `src/data/ieee8500_impedances.jl`
- **Verification:** Post-fix, direct computation confirms the full topology (MV lines + regulators + 38 enabled switches + service transformers + LV triplex) is a single connected tree over all 4,875 buses: `edges == 4,874 == buses - 1` exactly, BFS-reachable from `IEEE8500_ROOT_BUS`. `ieee8500_modified()` and `ieee8500_mv_modified()` both construct successfully (`assert_radial` + `assert_magnitudes` pass).
- **Committed in:** `83dd3a3` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug/blocking, resolved via source-data ground truth rather than heuristic inference).
**Impact on plan:** Necessary for Task 1's own stated done-criterion ("`ieee8500_modified()` constructs a valid, radial... `Feeder`"). No scope creep — the fix stayed inside plan 25-01's own reduction-script file, correcting a data-completeness bug that blocked this plan's construction, and is fully consistent with D-06 ("every real line/transformer segment is kept" — the 5 excluded records are not real physical connections in the modeled network, they are documented-open ties).

**Note on task/commit granularity:** Tasks 1 and 2 were both authored into `src/data/ieee8500.jl` in a single `Write` (the two fixture builders and their shared relabel-map/bus-role-helper code are tightly coupled and were drafted as one cohesive file), so both tasks' code landed in a single commit (`83dd3a3`) rather than two separate commits. Both tasks' verify commands and acceptance criteria were independently re-run and confirmed passing before proceeding to Task 3.

## Issues Encountered

None beyond the deviation documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `src/data/ieee8500.jl` exports both fixture builders and all five bus-role helpers plan 25-04
  (capacitor device + real-kW population) needs: `ieee8500_load_nodes`, `ieee8500_mv_load_buses`,
  `ieee8500_capacitor_buses`, plus both relabel maps.
- `ieee8500_mv_load_buses()`'s measured count (1,138, not 1,177) is the number plan 25-04's
  population builder should iterate over when aggregating real per-load kW onto MV buses.
- Full-suite regression (`julia --project=. -e 'import Pkg; Pkg.test()'`) was NOT run in this
  worktree per the orchestrator's explicit instruction (previous plan 25-02 lost significant time
  to a redundant per-worktree full-suite run) — delegated to the orchestrator's wave-level
  post-merge gate. This plan's own targeted verification
  (`julia --project=. test/test_ieee8500.jl`, 22,195/22,195 pass) and `ieee123`/reduction-script
  spot-checks (unaffected, confirmed above) are the evidence for this plan's own correctness.
- No blockers for plan 25-04.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- FOUND: src/data/ieee8500.jl
- FOUND: test/test_ieee8500.jl
- FOUND: .planning/phases/25-ieee-8500-scalability-benchmark/25-03-SUMMARY.md
- FOUND commit: 83dd3a3 (Task 1+2)
- FOUND commit: 9cdc3ba (Task 3)
- FOUND commit: 86a8e86 (SUMMARY.md)
