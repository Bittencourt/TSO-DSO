---
phase: 38-close-v4-0-audit-gaps
plan: 02
subsystem: mpc-certificate
tags: [socp-exactness, mpc, hybrid-floor, gap-closure, regression-test]
requires:
  - "38-01: _socp_cone_check kernel in src/models/exactness.jl"
provides:
  - "MPC first-tier certificate = _socp_cone_check(o.ctx).maxratio (hybrid floor, library defaults, non-throwing)"
  - "Regression @testitem: flat-1e-6 accepts / hybrid refuses / escalates, plus parity with hybrid_ratios"
  - "38-MEASUREMENTS.md sections: MPC first-tier ratios, MPC explained moves, Cross-version (1.10 / 1.11) MPC checks"
affects: [38-03, 38-10]
tech-stack:
  added: []
  patterns: ["consumer calls shared non-throwing kernel; escalation ladder unchanged"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-02-SUMMARY.md
  modified:
    - src/experiments/mpc_loop.jl
    - test/test_mpc_loop.jl
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
decisions:
  - "Added the optional feeder-identity guard (o.ctx.feeder === feeder, ArgumentError otherwise); every caller (run_mpc and all tests) passes the window's own feeder"
  - "Shortfall fixture t=4 on 1.12.7 escalation accepted as a measured, explained move (no test asserts it); happy-path 0.938 margin kept, tau not raised"
metrics:
  duration: ~45min
  completed: 2026-10-07
  tasks: 3
  files: 3
requirements: [FIX-08, FIX-10]
---

# Phase 38 Plan 02: MPC first-tier certificate through the shared hybrid-floor kernel Summary

MPC's per-resolve first-tier certificate now calls `_socp_cone_check(o.ctx).maxratio`, the same
`_cone_row` arithmetic and defaults as `assert_socp_exact!` (rtol 1e-4, per-branch hybrid floor),
evaluated without throwing. The inline `1e-6 + 1e-4` loop is gone. The escalation ladder is
unchanged. A new regression item shows a light-branch slack that the old flat floor accepted now
escalates.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | BEFORE-change old-vs-hybrid ratios on 1.12.5 and 1.12.7 | 134c096 | 38-MEASUREMENTS.md |
| 2 (RED) | Failing hybrid-floor regression item | da1ec0a | test/test_mpc_loop.jl |
| 2 (GREEN) | First tier through `_socp_cone_check`, docstrings, feeder guard | 17a9cf9 | src/experiments/mpc_loop.jl, 38-MEASUREMENTS.md |
| 3 | Explained move, 1.10/1.11 cross-check, consumers, format | ea9a2f5 | 38-MEASUREMENTS.md (formatter: no changes) |

## Verification

- Task 1: all research numbers reproduced to rounding on both patches. The only flip is shortfall t=4 on 1.12.7. Regression point at δ=5e-7: old 0.4993/0.4992, new 2.4571/2.4566, and the current code returned `:certified_convex_dual`.
- RED: the new item had 3 failures (parity `0.4993 == 2.4571`, `> 1`, status) and 4 passes against the old inline loop.
- GREEN: `file:test_mpc_loop.jl` went from 11 items / 369 Pass to 12 items / 376 Pass. `1e-6 + 1e-4` count is 0, the `cone_maxratio = _socp_cone_check(o.ctx).maxratio` line is present, and `check_planning_ids.py` is OK.
- Consumers: `test_status_policy, test_mpc_terminal, test_mpc_window` gave 10 items / 45 Pass. `test_strategies.jl` (all 26 items, including the `:slow` one, run via `suite_detached.sh`) gave 415 Pass.
- `format210.jl` made no changes. `check_content_loss.py HEAD` is OK. No scratch `.jl` in the repo.
- Cross-version, using the committed code on Julia 1.10.11 and 1.11.9: the unperturbed point is certified (0.0114). The slack point gives old 0.4993 / new 2.4571, exact parity, `:certified_convex_dual_restricted` and 3 finite prices. Scenario A stays `:certified` with worst ratio 0.9383. Every new assertion holds; no manual CI risk.

## Explained move (1.12.7 only; shortfall fixture `T=9, MPC(H=3, step=1, terminal_soc=true, forecast_error=0.3)`, seed 1)

| quantity | before | after |
|----------|--------|-------|
| first-tier ratio t=4 | 0.233 (flat floor) | 1.165 (hybrid; b=6, τ=3, gap 2.333e-7) |
| `cert_status_trace[4]` | `:certified_convex_dual` | `:certified_convex_dual_restricted` |
| `status` | `:certified` | `:degraded` |
| `dadp_trace[4]` | 0.008895250684296654 | 0.008894113604359186 |
| other dadp entries, `regret` (-0.0469747761931103), `realized_welfare` (-468.9958511666502), `forecast_settled_welfare` (-468.8911819809952) | — | bit-identical |

The "before" column was re-measured in this plan by re-instating the pre-change function from 134c096. On 1.12.5 nothing moves (t=4 goes from 0.157 to 0.771). No test asserts B's status, cert trace or dadp: the scenario name appears only in three test_mpc_loop items, and none of them reads those fields. The knife-edge canary is not MPC and was not touched.

**Margin note:** the happy-path fixture's worst hybrid ratio is **0.938** on 1.12.5, 1.10.11 and 1.11.9 (t=4, b=9, gap 1.879e-7). That is a 6.6 % margin under its "never escalates" assertion. On 1.12.7 it is 0.323. τ is not raised.

## Deviations from Plan

- **[Rule 2 - guard]** Added the optional `o.ctx.feeder === feeder || throw(ArgumentError(...))` guard. The plan allowed it only if every caller passes the same object. `run_mpc` builds the window from `feeder`, and every test passes the same fixture feeder. The docstring mentions the guard.
- The docstring line about the escalation tier's throw ("trips the inline cone check") and the in-body comment at the ladder were reworded to "first-tier cone check", as the plan's grep-for-"inline" instruction asked.
- Stale "inline check" prose in `test/test_mpc_loop.jl` (header line 7 and the comments at ~359/363/486) was left as is: plan 03 owns test, fixture and literate prose.
- For the post-fix scenario-A ratios on 1.10/1.11, I used a logging-only scratch hook on the fixed function (a `push!` after the shipped `_socp_cone_check` line; decision logic verbatim), because `MpcTrace` does not store ratios. The regression-point numbers come straight from the unpatched call return.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: src/experiments/mpc_loop.jl (`cone_maxratio = _socp_cone_check(o.ctx).maxratio`), test/test_mpc_loop.jl ("hybrid exactness floor"), 38-MEASUREMENTS.md (3 new sections)
- FOUND commits: 134c096, da1ec0a, 17a9cf9, ea9a2f5
