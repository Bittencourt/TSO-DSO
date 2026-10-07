# Phase 37 Final Gates (plan 37-13)

Code state: both full runs and the docs build were launched sequentially (never concurrent, `pgrep julia` empty, no agent worktrees, clean tree) at HEAD 949c810. The formatter then reformatted 4 test runner files (AST-equivalent, `check_content_loss.py HEAD` OK), committed as 6dabf6e; `--count-sets --strict` was re-run after it (unchanged: all=511 fast=474 slow=37 files=98). The suites ran on the pre-format text of those 4 files; whitespace/comma-only, so behaviour is identical.

## Full runs

| Run | Command | Pass | Fail | Error | Broken | Total | check_suite_log |
|---|---|---:|---:|---:|---:|---:|---|
| p37-full125 | `TSODSO_TEST_SET=all`, `julia +release` (1.12.5) | 32223 | 0 | 0 | 5 | 32228 | `suite OK` |
| p37-full127 | same, `julia +1.12` (1.12.7), `--broken 5` | 32218 | 0 | 0 | 5 | 32223 | `suite OK` |

Canary in both logs: `iters = 56`, `welfare = -4823.66604824162` (1.12.7 canary log line also iters = 56). `soft scope is ambiguous` count 0 in both.

### Pass arithmetic, 1.12.5

32205 (baseline) + 16 (4 `test_flake_retry.jl` items) + 1 (`guards` testset) + 1 (new `:slow` item "Aqua persistent tasks": 1 pass; the fast Aqua item with `persistent_tasks=false` keeps the other Aqua passes) = **32223**. Observed 32223, delta 0. Broken 5 = baseline (includes the FIT item's conditional thesis cross-check, which fires on 1.12.5).

### 1.12.7 delta

`BROKEN_1.12.7_EXPECTED_POSTGATE=5` (37-TIMINGS.md: raw 4 + 1 gated). Observed 5. Pass 32218 = 32223 - 5: the gated FIT item (`fit_baseline` ends ALMOST_SOLVED, `assert_solved!` throws SolveFailedError) now records one `@test_broken false` and skips the 5 passing assertions of the else branch (haskey, ratio vs obj, ratio vs base.ratio, golden, band) plus the conditional thesis-cross-check Broken, which is replaced by the gated Broken (Broken stays 5). No other difference between the two runs. The `RETRY SUMMARY ... five x5` line in the 1.12.5 log comes from the `test_flake_retry.jl` fixture (deliberate), not from a real guarded solve.

## Static and hygiene gates

| Gate | Command | Result |
|---|---|---|
| Planning-ID guard | `check_planning_ids.py` / `--selftest` | OK 250 files / selftest OK (42 pos, 24 neg, 10 fail-closed) |
| Script API | `check_script_api.jl` / `--selftest` (1.12.5) | OK 40 files / selftest OK (55 cases) |
| Scripts index | `check_scripts_index.py` / `--selftest` | complete (37 tracked) / OK |
| count-sets | `run_tests_filtered.jl --count-sets --strict`, `--selftest` | all=511 fast=474 slow=37 files=98 canary=1 outside=0 / selftest OK |
| JET 1.12.5 | `scripts/jet_check.jl` | 11 current, 11 baseline, 0 NEW, 0 FIXED (version-mismatch WARNING only, baseline recorded on 1.12.7) |
| JET 1.12.7 | `scripts/jet_check.jl`, `--selftest` | 11/11, 0 NEW, 0 FIXED / selftest OK |
| Formatter | `format210.jl src ext test docs` (2.10.2) + `check_content_loss.py HEAD` | OK, no content change; 4 test files reformatted, committed 6dabf6e; `git status` clean |
| Docs | `suite_detached.sh p37-docs-final julia --project=docs docs/make.jl`, `--mode docs` | `docs OK`, exit 0, 0 `Cannot resolve @ref` |
| Aqua | direct `Aqua.test_all(TSODSO)` | all testsets pass (ambiguity, unbound, exports, project/test project, stale deps, compat 4, piracy, persistent tasks) |
| tmp / Manifest | `git ls-files .planning/tmp Manifest.toml` | empty; no root Manifest.toml (only Manifest-v1.10/1.11/1.12.toml and bench/docs/test) |
| Workflows | yaml parse CI.yml, slow.yml | both parse |
| src diff | `git diff 57558d3 --stat -- src` | 19 files, 38+/31-: JET cleanups, docstring edits, factory addition; canary/golden values untouched (canary iters 56 and welfare reproduced) |

## Success-criterion mapping

- HYG-04 (JET in CI, baseline): jet_check 0 new on 1.12.5 and 1.12.7, baseline 11 signatures; CI job file parses. Actions execution is MANUAL.
- HYG-05 (`:slow` tag, fast job): 37 slow / 474 fast items, canary and Aqua stay fast; both CI workflows parse. Actions execution is MANUAL.
- HYG-06 (flakes): FlakeRetry helper (16 passes), harness `scripts/flake_rate.jl`, gated 1.12.7 FIT item, full runs on both patches reproduce with 0 Fail/Error.
- HYG-08 (scripts index, hygiene): index + drift guard, script-API check, tmp/Manifest hygiene all green.

## MANUAL (needs GitHub)

- Env passthrough (`TSODSO_TEST_SET`) reaches `Pkg.test` in the fast job.
- The `jet` job passes on Actions.
- Nightly cron / `workflow_dispatch` on `slow.yml` runs the slow set.
- Docs deploy and the full CI matrix (Julia 1.10/1.11/1.12) on a pushed branch.
- PV-boom re-tune physically sensible: approved at the checkpoint (reference, plan 37-08).

Pending, out of scope: seed-42 battery-complementarity investigation (`.planning/todos/pending/2026-10-06-investigate-demo-seed-42-battery-complementarity.md`); the 1.12.7 `fit_baseline` ALMOST_SOLVED backlog todo.

## Verdict

All local gates green. HYG-04/05/06/08 marked complete locally; the MANUAL items above are the remaining GitHub-side confirmation.
