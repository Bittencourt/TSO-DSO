---
phase: 37-test-infrastructure-repo-hygiene
verified: 2026-10-07T00:00:00Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Push to GitHub and confirm Actions run: fast job (TSODSO_TEST_SET=fast reaches Pkg.test), jet job on 1.12.7, slow.yml on push/nightly/dispatch, docs deploy, 1.10/1.11/1.12 matrix"
    expected: "All jobs green"
    why_human: "GitHub-side execution cannot be verified locally (accepted/out-of-scope per phase context)"
---

# Phase 37 Verification

**Goal:** CI enforces static analysis and a fast/slow split, known flakes resolved honestly, scripts/manifests tidy.
**Status:** human_needed (all local truths verified; only GitHub-side execution remains)

## Observable truths

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|---|---|---|
| 1 | JET in CI, report mode, agreed baseline (HYG-04) | VERIFIED | `jet` job in CI.yml pinned to Julia 1.12.7 with `JULIA_LOAD_PATH`; `scripts/jet_check.jl` run here on 1.12.7: 12 current / 12 baseline / 0 NEW / 0 FIXED; `--selftest` OK. Baseline is 12 signatures after the review loop (plan 13 had 11). |
| 2 | `:slow` tag; fast job per push, slow in separate/nightly job (HYG-05) | VERIFIED | `--count-sets --strict`: all=511 fast=474 slow=37 files=98 canary=1 outside=0. CI.yml sets `TSODSO_TEST_SET: fast`; slow.yml runs on push to main, nightly cron and dispatch. Bogus `TSODSO_TEST_SET` errors ("invalid; allowed values: fast\|slow\|all"). Both YAMLs parse (CI: test/jet/format/docs; slow: test). |
| 3 | Flakes fixed or quarantined honestly (HYG-06) | VERIFIED (caveat) | 20x fresh-process measurement on 1.12.5 and 1.12.7 found no ieee13 NUMERICAL_ERROR and no stochastic-welfare flake, so nothing was quarantined; FlakeRetry helper is unit-tested and reserved. The one deterministic 1.12.7 failure (`fit_baseline` seed AC-PF ALMOST_OPTIMAL) is a gated `@test_broken` recorded in per-site `test/expected_broken.txt`; the runtests guard fails on any unlisted Broken/skipped record. Caveat: 0/20 gives a Wilson 95% upper bound of 16%, so a rarer flake is not excluded. |
| 4 | scripts index, archive, pv_boom merge, root Manifest, `.planning/tmp` (HYG-08) | VERIFIED | `scripts/README.md` index; `check_scripts_index.py` complete (37 files) and `--selftest` OK. `scripts/archive/` holds `pv_boom_report_v1.jl` and `reactive_flake_rate.jl`; `pv_boom_report.jl` includes shared `scripts/lib/pv_boom_common.jl`. No root `Manifest.toml`; `git ls-files .planning/tmp Manifest.toml` is empty; `/.planning/tmp/` is gitignored. |

## Regression gate (run here, sequential, clean env)

| Run | Pass | Fail | Err | Broken | check_suite_log | Notes |
|---|---:|---:|---:|---:|---|---|
| 1.12.5 (`julia +release`, `TSODSO_TEST_SET=all`) | 32224 | 0 | 0 | 5 | suite OK | canary `iters = 56`; soft-scope warnings 0 |
| 1.12.7 (`julia +1.12`) | 32219 | 0 | 0 | 5 | suite OK | canary `iters = 56`; soft-scope warnings 0 |

**Delta vs plan 13 (32223 / 32218): +1 on each.** The review loop added `@test isempty(dead)` to the `guards` testset in `test/runtests.jl` (IN-02: TSODSO_TEST_FILES matched-name check). The 1.12.5 to 1.12.7 difference stays 5 (the gated FIT item skips 5 passing assertions and replaces the conditional Broken with the gated one).

**Broken 5 explained:** `expected_broken.txt` is now per-site (kind, file, item, test) and lists 5 broken sites and 2 skipped sites (CairoMakie absent in the test env). Broken sites are 3 conditional thesis cross-checks (ieee13, acceptance, thesis_repro sign_flip), the pricing_welfare `gap < 0.1` conditional (fires on 1.12.5), and the pricing_welfare gated FIT `@test_broken` (fires on 1.12.7). Observed 5 on both patches, same count as plan 13, so the format change did not alter counts. The list is a multiset-coverage allowance, so unobserved entries are permitted.

## Other gates
- `check_planning_ids.py`: OK 250 files; `--selftest` OK (42 pos / 24 neg / 10 fail-closed).
- `check_script_api.jl` (1.12): OK 40 files; `--selftest` OK (55 cases).
- `check_scripts_index.py` + `--selftest`: OK.
- `run_tests_filtered.jl <root> --count-sets --strict` and `--selftest`: OK.
- Hygiene: clean `git status`; no tracked `.planning/tmp`; no root Manifest.

Note for operators: `jet_check.jl` and `run_tests_filtered.jl` need `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"` (as CI sets) and `run_tests_filtered.jl` takes the repo root as its first argument. Without them they error out. This is documented usage, not a defect.

## Anti-patterns
No blockers found. No unreferenced TBD/FIXME/XXX checked in the changed runner/test files for this verification beyond the passing planning-ID guard.

## Human verification (accepted, GitHub-side)
1. Env passthrough `TSODSO_TEST_SET` reaches `Pkg.test` in the fast job; `jet` job green on Actions; slow.yml nightly/dispatch/push; docs deploy; full 1.10/1.11/1.12 matrix.

## Accepted / out of scope
Seed-42 battery-complementarity todo; LinDistFlow-copy vmax bound research todo (2026-10-07); 1.12.7 `fit_baseline` ALMOST_OPTIMAL backlog; IEEE-8500 harness manual-only.

## Requirements
HYG-04, HYG-05, HYG-06, HYG-08: all SATISFIED locally (REQUIREMENTS.md marks them Complete). No orphaned Phase 37 requirements (HYG-07 belongs to Phase 36).

_Verifier: Claude (gsd-verifier)_
