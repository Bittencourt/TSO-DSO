---
phase: 44-aggregator-as-actor
plan: 05
subsystem: admm
tags: [slot-table, shared-bus, portfolio, lambda-certificate, admm]
requires: ["44-03"]
provides:
  - "Several actors/sites at one bus under ADMM: automatic routing to the slot branch when actors is given and a bus carries >1 site"
  - "Per-bus dadp/mu_q (primary slot row), per-slot lambda_slots, reported slot_lambda_gap/slot_lambda_agree, slot_bus/slot_actor result keys (shared-bus runs only)"
  - "Slot-keyed has_4q_by_bus, _react_outputs inner key, actor report built from slot dispatch"
affects: [44-06, 44-07]
tech-stack:
  added: []
  patterns: ["slot code only on slot branch (meta[:slot_site] discriminator); legacy statements unchanged", "additive keys only when a bus actually has several slots, so forced 1:1 slot runs keep the legacy key set bitwise"]
key-files:
  created: []
  modified:
    - src/admm/admm_phases.jl
    - src/admm/admm_state.jl
    - src/admm/solve_admm.jl
    - test/test_actor_portfolio.jl
key-decisions:
  - "Published per-bus DADP/mu_q row = the PRIMARY slot (slot id == bus), so shape is (n_load_nodes, T) and rows are identical to legacy when 1:1"
  - "Slot additive keys appear only when some bus has more than one slot (keeps 44-03 forced-slot key-set equality)"
  - "q_devices and agr_* are keyed by slot id (== bus for the primary slot); _react_outputs indexes the AGR stash with slot_bus[j]"
  - "slot_lambda_agree compares the gap with solve_admm's tol; reported, never thrown"
  - "p_p stays length(load_nodes)*T, i.e. counts slots (legacy value when 1:1); no code change"
requirements-completed: []
duration: ~2h
completed: 2026-11-02
---

# Phase 44 Plan 05: Several actors per bus under ADMM Summary

Extra slots at a shared bus now iterate, publish per-bus DADP and report a slot-lambda agreement certificate; split-bus matches the merged aggregator within measured bands on both the centralized and ADMM paths.

## Tasks

1. RED tests (`d6fcc5c`): PortfolioFixtures testmodule (2-bus and 4-bus feeders, split/merged twins, measured-band constants) and eight items covering split-bus centralized, split-bus ADMM, certificate/keys, portfolios spanning buses, OFF/CERTIFIED, LIVE + FourQuadBESS second site, p_p, threaded, routing.
2. Implementation (`8c6b299`, docs `4d7f7c9`): auto-routing in `solve_admm`; `has_4q_by_bus` by slot id; `_react_outputs` inner key via `slot_bus`; `_primary_slots` for per-bus rows; `lambda_slots`/`slot_lambda_gap`/`slot_lambda_agree`/`slot_bus`/`slot_actor`; `_actor_report` from slot-keyed dispatch.

## Measured bands (julia 1.12.5, 3 seeds, ADMM eps_abs 1e-7 / eps_rel 1e-8, rho 5; pinned at 3x observed max; table in the test header)

| Quantity | Observed max | Pinned |
|---|---|---|
| centralized split vs merged dW / dlambda | 9.8e-15 / 3.5e-11 | 1e-12 floor / 1.04e-10 |
| ADMM split vs merged dW / dlambda (4-bus) | 7.72e-6 / 2.70e-6 | 2.3e-5 / 8.1e-6 |
| ADMM split vs centralized dW / dlambda | 5.22e-6 / 2.63e-6 | 1.6e-5 / 7.9e-6 |
| 2-bus OFF/CERT/LIVE/4Q dW / dlambda / dmu_q | 1.03e-5 / 2.2e-7 / 5.1e-7 | 3.1e-5 / 6.6e-7 / 1.53e-6 |
| slot-lambda gap | 2.7e-15 | 1e-12 floor |

The gap is structurally ~0: after the first dual step every slot at a bus holds the DSO's nodal balance dual.

## Iteration counts (merged / split, no parity claimed)

4-bus 17/15, 17/14, 13/15; 2-bus OFF 3/4, 3/3, 3/4; LIVE 3/4; 4Q second site 4/189, 4/185, 4/171 (a FourQuadBESS as its own slot converges far slower than inside one aggregator).

## Verification (julia 1.12.5, fast set, foreground)

- `test_actor_portfolio, test_actor_objective, test_actor_default_fence, test_admm_knifeedge_canary, test_admm, test_dso, test_admm_reactive, test_admm_phases, test_admm_exactness_default, test_exports`: pass.
- `JULIA_NUM_THREADS=4` with `test_admm_parallel.jl` + `test_actor_portfolio.jl`: pass (threaded == serial on shared-bus case).
- Fence, canary, 44-03 forced-slot bitwise tests unchanged. No golden, tolerance or `expected_broken.txt` change.

## Deviations from Plan

- **[Process]** RED was not re-run on a clean tree: the test commit precedes the src commit, but src edits were already in the working tree (the shared-bus-with-actors path previously hit the legacy guard ArgumentError). A mid-task accidental working-tree revert (`git checkout -- .`, which discarded uncommitted edits) forced re-applying all edits; nothing committed was affected.
- **[Rule 1]** The first GREEN run exposed a test bug (re-generated site objects broke portfolio identity); fixed by reusing `r.p`.
- Tests 4/5/9 use the 2-bus and a purpose-built 4-bus feeder instead of IEEE-13, to keep runtimes in seconds.
- Additive slot keys are emitted only on shared-bus runs (not on every slot run) to keep the 44-03 bitwise key-set test valid.

## Known Stubs

None.

## Self-Check: PASSED

Commits `d6fcc5c`, `8c6b299`, `4d7f7c9` exist; `src/admm/admm_phases.jl` contains `lambda_slots`; REQUIREMENTS.md not touched.
