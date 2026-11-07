---
phase: 47-v5-audit-gap-closure
plan: 03
subsystem: settlement
tags: [docs, scope-decision, requirements, audit, backlog, phase-gate]

requires:
  - phase: 47-01
    provides: trait-routed battery certificate and the V2G EV certificate on the price-taker and flex paths (2d757ed, e934b11, 4e0497d)
  - phase: 47-02
    provides: actors ArgumentError guard, up-front unsupported-device refusal in compare_tariffs, _refuse_reactive_decision (16ba018, a4f6d37, 7262924)
provides:
  - flex_market docs section 1 records the reactive-decision refusal; section 12 has the actors, reactive-decision and EV-certificate limitation bullets
  - SETL-F2 future requirement; gap-closure notes on the DEV-07, SETL-07 and SETL-08 traceability rows
  - milestone audit gap-closure section for B1, B2, W2 and W3 (frontmatter status left for the re-audit)
  - backlog todo .planning/todos/pending/2026-11-06-v5-integration-check-backlog.md
affects: [v5.0 re-audit, SETL-F2 future milestone]

tech-stack:
  added: []
  patterns:
    - "A scope decision is recorded in three places: a future requirement, the audit, and the docs limitations"

key-files:
  created:
    - .planning/todos/pending/2026-11-06-v5-integration-check-backlog.md
  modified:
    - docs/literate/flex_market.jl
    - .planning/REQUIREMENTS.md
    - .planning/v5.0-MILESTONE-AUDIT.md

key-decisions:
  - "Actors in the flexibility market and tariff comparison are future work (SETL-F2); SETL-07/08 ledger actors are the DSO, the aggregators and the wholesale side"
  - "The audit records the B1 outcome as measured: price-taker and clear_flex_market baseline report :refused at the negative price; _deliver measured :ok because tracking pins the net injection at zero"
  - "Audit frontmatter status and scores are left untouched for the re-audit"

requirements-completed: [DEV-07, SETL-07, SETL-08]

duration: 25min
completed: 2026-11-07
---

# Phase 47 Plan 03: Scope decision, refusal docs, backlog and phase gate Summary

**The scope decision that actors are not settled through the flexibility market or the tariff comparison is now recorded in three places: SETL-F2 in REQUIREMENTS.md, the audit's gap-closure section and the flex-market docs limitations. The stage-2 reactive-decision refusal is documented. The leftover integration-check items are filed as one backlog todo. The phase gate is green and nothing golden moved.**

## Accomplishments

- **Docs (`docs/literate/flex_market.jl`), prose only.**
  - Section 1: the refusal sentence now also covers `SmartInverterPV` and `FourQuadBESS`. It explains that flexible loads are not refused, because stage 2 drops their power-factor draw on purpose.
  - Section 12 gets three new bullets:
    - devices with their own reactive decision are refused;
    - the V2G EV certificate is reported separately, counted, never repaired, and checked at the ADMM final-consolidation tolerance;
    - actors are not settled here: an `ArgumentError` for any `actors` value other than `nothing`, before any solve, and an undetected `SettlementInput` from an actor run.
  - No planning IDs were added: the count stays at 354.
- **REQUIREMENTS.md.**
  - SETL-F2 was added after SETL-F1.
  - The SETL-07 and SETL-08 rows carry scope notes (`see SETL-F2`) and their specific refusals.
  - The DEV-07 row notes the EV-certificate gap closure.
  - All checkboxes were already `[x]` and are unchanged.
- **Audit.** A new section, "Gap closure (Phase 47, 2026-11-06)", has a table of item, resolution and commits for B1, B2, W2 and W3. The B1 row states the measured outcomes:
  - `price_taker_dispatch` reports `:refused` at the negative price, and so does the `clear_flex_market` baseline.
  - The `_deliver` test measured `:ok` (ratio 4.2e-15), because the tracking penalty pins the net injection at zero.
  - The flex-path `:refused` is therefore shown through the negative-price `clear_flex_market` baseline.

  The W2 row lists EV, HeatPump, SmartInverterPV and behaviour-wrapper populations as refused before any solve. The B2 row points to the separate **Actors.** docstring paragraph. The frontmatter is untouched.
- **Backlog todo.** It covers:
  - W1 and W4–W9;
  - the two `@ref` warnings (`_analytic_distflow_start!`, `_any_flexible_reactive`);
  - the `SettlementInput` provenance flag (cross-referenced to SETL-F2);
  - the `TAU_EV_ADMM` docstring update (docstring only, value unchanged).

  Each item has a suggested fix.

## Task Commits

1. **Task 1: record the scope decision, document the refusals, file the backlog:** `2e4583c` (docs)
2. **Task 2: phase gate:** the formatter was a no-op on both passes, so there is no `style(47)` commit. The gates only ran checks. The audit B2 row's commit cell was then updated with `2e4583c` in the final docs commit.

## Test Counts (fast set, targeted)

| Batch | Files | Result |
|---|---|---|
| A | test_admm_knifeedge_canary.jl, test_actor_default_fence.jl | 17/17 pass (2m36s); canary 56 iterations / −4823.66604824162, 0 escalations; actor digests equal their pins |
| B | test_flex_market_ieee.jl, test_exports.jl, test_electricvehicle.jl | 308/308 pass (1m24s); includes the fast `committed comparison CSV rows` item |

`test/Project.toml` and `test/Manifest.toml` were restored after each run.

## Gates

| Gate | Result |
|---|---|
| Formatter (flex_market.jl only, twice) | no change |
| Content-loss check | OK |
| Planning IDs | 354 hits, 0 stale (at most 355) |
| Scripts index | complete (48 files) |
| JET | 20 current, 20 baseline, 0 new, 0 fixed |
| SC3 (`git diff 9e9b709` over src/admm, exactness.jl, factory.jl, expected_broken.txt) | empty |
| τ gate | counts equal |
| Golden pins | fence file only gained lines; canary and actor-fence files unchanged; 2 removed lines in test_flex_market.jl |
| `git diff 9e9b709 --stat -- results src/models src/admm`, `git status -- results` | empty |
| Literate parse (no `:error` / `:incomplete` node) | ok |
| DEV-07 / SETL-07 / SETL-08 checkboxes | still `[x]` |

## Deviations from Plan

None in substance.
- **Audit B1 wording.** The plan's step 3 summary said that the negative-price fixtures report `:refused` on both paths. The audit instead records what was measured: `:refused` on the price-taker and on the `clear_flex_market` baseline, and `:ok` on the `_deliver` test, with the reason (see 47-01 SUMMARY).
- **Formatter.** It was a no-op, so no `style(47)` commit exists. The verify form handles that case (`ref=HEAD`).

## Known Stubs

None.

## Threat Flags

None. The changes are documentation and planning records only.

## Self-Check: PASSED

- FOUND: docs/literate/flex_market.jl ("own reactive decision", "Actors are not settled here")
- FOUND: .planning/REQUIREMENTS.md (SETL-F2, 2× "see SETL-F2")
- FOUND: .planning/v5.0-MILESTONE-AUDIT.md ("Gap closure")
- FOUND: .planning/todos/pending/2026-11-06-v5-integration-check-backlog.md
- FOUND: commit 2e4583c
