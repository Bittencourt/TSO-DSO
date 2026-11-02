---
phase: 44-aggregator-as-actor
plan: 03
subsystem: admm
tags: [slot-table, consensus-axis, admm, dso-opt, byte-identity]
requires: ["44-02"]
provides:
  - "SlotTable + build_slot_table (internal): slot id = bus for the first site at a bus, N + k for the k-th extra"
  - "build_dso_opt(...; slots): pag_dso/qag_dso indexed by slot, injected at bus(s); slot_bus in dso.ctx.meta[:slot_bus]"
  - "AdmmState trailing slot_bus field + 18-arg outer constructor (identity default)"
  - "_admm_build slot branch (slots/site_objectives kwargs) and solve_admm test seam _force_slot_path"
affects: [44-05, 44-07]
tech-stack:
  added: []
  patterns: ["new branch only; legacy code path literally unchanged", "state allocation factored into _admm_state_init shared by both branches"]
key-files:
  created:
    - test/test_actor_portfolio.jl
  modified:
    - src/actors/Portfolio.jl
    - src/admm/DsoOpt.jl
    - src/admm/admm_state.jl
    - src/admm/admm_phases.jl
    - src/admm/solve_admm.jl
key-decisions:
  - "DsoOpt gets NO new field (10-field positional layout kept); slot_bus lives in ctx.meta[:slot_bus]"
  - "AdmmState.slot_bus is trailing; the 18-arg positional constructor (profile_ieee8500 script) defaults it to identity over load_nodes"
  - "_force_slot_path with actors=nothing treats each site as its own actor; a bus with several sites still reaches the legacy guard (44-05 adds automatic slot routing)"
requirements-completed: []
duration: ~2h (mostly test wall-clock)
completed: 2026-11-02
---

# Phase 44 Plan 03: Slot-indexed ADMM coupling axis Summary

The ADMM coupling axis can now be keyed by (actor, bus) slots on a new branch; forced onto the 10-aggregator IEEE-13 population it reproduces legacy BITWISE (welfare, dadp, iters, every residual trace, every agr_* key, key set).

## Tasks

1. RED tests (`60a8da1`): slot-table id rule and determinism, forced-slot bitwise vs legacy, distinct-bus portfolio == legacy, legacy guard message intact, AdmmState 18-arg and `meta[:slot_bus]`.
2. Implementation (`fa75dcd`): `SlotTable`/`build_slot_table`; `build_dso_opt(...; slots)` (load_nodes := slot ids, per-slot q_draw, injection at `slot_bus[s]`); `AdmmState.slot_bus` + 18-arg constructor; `_admm_build` slot branch with the legacy guards and messages untouched on the legacy branch; `_force_slot_path` seam on `solve_admm`.
3. Threads and LIVE reactive (`9ae52f3`): forced slot serial == parallel (runs only when `Threads.nthreads() > 1`, deliberately no `@test_skip`, so no new expected_broken record); forced slot LIVE reactive with a FourQuadBESS site == legacy LIVE (covers `has_4q_by_bus`, `_react_outputs`).

## Verification (julia 1.12.5)

- `test_actor_portfolio.jl` alone: 39 pass.
- Regression (fence, canary 56 iters / -4823.66604824162, test_admm, test_dso, test_admm_phases, test_admm_exactness_default, test_exports): 186 pass.
- `test_actor_portfolio.jl` + `test_admm_reactive.jl`: 76 pass.
- `JULIA_NUM_THREADS=4` with `test_admm_parallel.jl` + `test_actor_portfolio.jl`: 83 pass (threaded slot path == serial).
- No golden, tolerance or `expected_broken.txt` change. No tolerance is used anywhere in the new file (all `==`).

## Deviations from Plan

- The src implementation was written before the RED test run was re-done after fixing fixture problems (first RED run showed the new-symbol errors; the IEEE-13 items also failed because my initial hand-picked ADMM parameters did not converge; switched to the canary scenario recipe). The test commit precedes the src commit.
- The IEEE-13 slot items run in the fast set (about 1-2 min each), not tagged slow, since the plan's verify uses the fast set.

## Known Stubs

None. Extra slots at a shared bus (iteration-time keys, DADP publication, certificate) are intentionally left to 44-05.

## Self-Check: PASSED

Files and commits `60a8da1`, `fa75dcd`, `9ae52f3` exist.
