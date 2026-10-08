---
phase: 36-code-export-cleanup
verified: 2026-10-05T23:45:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 36: Code & Export Cleanup Verification Report

**Phase Goal:** Source comments, dead seams, and exports read cleanly and honestly reflect the refactored codebase.
**Status:** passed (re-run at HEAD 6deb8f4, after the 3-iteration review/fix loop)

## Observable Truths

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|---|---|---|
| 1 | No plan/wave/task/decision/review IDs in comments/docstrings; CI grep guard enforces; thesis/literature refs remain (HYG-01) | VERIFIED | `check_planning_ids.py` OK (243 files, none); `--selftest` OK (42 pos / 24 neg / 10 fail-closed); independent grep of `src ext` for Phase/Wave/CR-/WR-/D-NN/SEAM-/HYG-/Pnn finds nothing; guard is wired into CI.yml format job (plan 21) |
| 2 | Inert SEAM-01 stubs and Bool/Symbol shim removed (HYG-02) | VERIFIED | `operational_oracle` signature (src/models/oracle.jl:62) has no `objective_hook`/`horizon_state`/`z`; test_oracle.jl asserts MethodError for all three; `normalize_reactive_mode` (src/admm/ReactiveMode.jl) accepts only `ReactiveMode.T`, everything else throws ArgumentError; breaking-changes documented in docs/src/status_policy.md |
| 3 | Export list trimmed; generic names namespaced/unexported; module docstring current (HYG-03) | VERIFIED | grep: none of OFF/LIVE/CERTIFIED/LP/QP/SOCP/NLP/MILP/record!/converged appear in any `export` line (61 export lines remain); OFF/CERTIFIED/LIVE live in the exported `ReactiveMode` module; advanced names are `@compat public`; top docstring has an "API policy" section matching this; Aqua 8/8 pass; test_exports.jl in green suite |
| 4 | Fixtures/tags named by content (HYG-07) | VERIFIED | test/ files are `fixtures_ieee13`, `fixtures_mpc`, etc.; grep for `fixtures_phase`/`PhaseNFixtures`/`:phaseN`/`FIX08` across src ext test scripts docs finds nothing (only the guard's own regex in `.github/scripts/planning_id_rules.py`, which is intentional); `test_admm_phases.jl` refers to ADMM solve phases, not planning phases |

## Regression Gate (this verification)

| Check | Result |
|---|---|
| Preconditions | no julia processes, no .claude/worktrees |
| Full suite (`suite_detached.sh v36suite`) | exit 0, 32205 pass / 0 fail / 0 error / 5 broken (27m51s); canary `iters = 56`, `welfare = -4823.66604824162` present |
| Pass delta vs p22 (32202) | +3, itemized: +2 `@test all(...)` in test/test_exports.jl (PerUnitBase/Z_base/I_base/to_pu_* and MpcWindow/admm_supported are public, not exported), +1 `!haskey(nt, :loss/:voltage)` in test/test_pricing_dlmp.jl; no other test assertions changed. `--same-pass-as p22` therefore reports the expected mismatch, fully explained |
| Docs build (`--mode docs`) | docs OK, exit 0; 4 non-fatal unresolved `@ref` (same as plan 22: `FIT_SITE3_ALMOST_GAP_TOL`, `BendersMaster(Integer).lb_clamped`, `stall_z_atol`) |
| `check_script_api.jl` / `--selftest` | OK (39 files) / OK (55 cases) |
| Aqua direct script | 8/8 pass |
| Token grep | clean |

## Requirements Coverage

HYG-01, HYG-02, HYG-03, HYG-07 are all marked Complete in REQUIREMENTS.md and satisfied above. No orphaned Phase 36 requirements.

## Anti-Patterns

None blocking. No TBD/FIXME/XXX introduced in checked src.

## Known out-of-scope items (accepted, not failing the phase)

- scripts/reactive_flake_rate.jl experiment design vs the reactive default, and its ConvergenceError handling
- scripts/run_scenario.jl battery-complementarity failure (pre-existing at 438e162^)
- stale results/pv_boom/*.html
- committed .planning/**/*.jl repro scripts containing `@testitem` discovered by Pkg.test (Phase 37 HYG-06/HYG-08)
- Residual: test/test_benchmark_ieee8500.jl left unformatted (formatter change flagged by content-loss check); 4 unresolved docs `@ref` to internal names (non-fatal)

## Human Verification

None required.

_Verifier: Claude (gsd-verifier)_
