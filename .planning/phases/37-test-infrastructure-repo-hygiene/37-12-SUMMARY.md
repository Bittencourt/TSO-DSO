---
phase: 37-test-infrastructure-repo-hygiene
plan: 12
subsystem: docs-ci
tags: [scripts-index, drift-guard, readme, hygiene]
requires: [37-11]
provides:
  - "scripts/README.md indexing every tracked file under scripts/ with purpose, run command, outputs, status"
  - ".github/scripts/check_scripts_index.py drift guard (selftest + real run) wired into the CI format job"
  - "README testing/tooling/manifest documentation"
affects: [37-13]
key-files:
  created:
    - scripts/README.md
    - .github/scripts/check_scripts_index.py
  modified:
    - .github/workflows/CI.yml
    - README.md
requirements-completed: [HYG-08]
completed: 2026-10-06
---

# Phase 37 Plan 12: scripts index, drift guard, README Summary

Every tracked file under scripts/ (including lib/, archive/, data/, the .sh wrapper and jet_baseline.txt; 36 files) is indexed with honest statuses, a CI-wired guard fails on missing or stale entries, and the root README documents the new test and tooling surface.

## Commits
- d37e840: scripts/README.md index.
- b5777fd: check_scripts_index.py and CI wiring (selftest step then real step, both `if: ${{ !cancelled() }}`, in the format job).
- d1f0430: README "Testing and checks" and "Environments and manifests" sections.

## Task notes
- Index statuses: `run_scenario.jl` listed unchanged as "fails at seed 42 (battery complementarity gate) - under investigation"; archive entries (reactive_flake_rate.jl, pv_boom_report_v1.jl) carry reasons; pv_boom_case_study.jl points at its CALIBRATION header (window 11:16); pv_boom_report.jl plus lib/pv_boom_common.jl replace the v1 pair; benders_toy.jl and compare_default_stochastic.jl marked kept/documentation-referenced. IEEE-8500 harness test documented as manual: 14m49s wall, 2.74 GB peak, pins model_vars=137258, model_cons=274570, admm_iters=1.
- Guard: besides missing files it also flags stale backticked file names in the index (extra entries). Selftest covers missing, extra and complete cases. Drift demonstration: staging a dummy `scripts/zz_dummy.jl` made the real run exit 1 ("NOT INDEXED"); the dummy was removed afterwards, tree restored.
- README facts: TSODSO_TEST_SET fast/slow/all (474 fast / 37 slow; fast about 9 min locally; slow workflow nightly + dispatch on 1.10/1.12), TSODSO_TEST_VERBOSE, filtered runner, JET ratchet (11 baselined signatures, Julia 1.12 only), flake harness (20/20 clean on both patches; Wilson 95% upper bound about 16%), FIT item gate (observed on 1.12.7; not on 1.12.5; other patches unmeasured), Broken counts 5 on 1.12.5, 5 post-gate on 1.12.7, fast set 4 (from the BROKEN_* lines in 37-TIMINGS.md and the plan inputs), per-minor manifests with no root Manifest.toml (1.10.11 / 1.11.9 / 1.12.x verified).

## Verification
- check_scripts_index.py --selftest and real run: exit 0. check_planning_ids.py: OK (250 files). check_script_api.jl: OK (40 files). CI.yml parses (yaml.safe_load).

## HYG-08
All criteria are now met: scripts index (this plan), superseded scripts archived (earlier plans), pv_boom_report merge (plan 11), root Manifest dropped in favour of per-minor manifests (earlier plan), `.planning/tmp/` untracked (gitignored, no tracked files). Marked complete.

## Deviations from Plan
None. Extra: the guard also detects stale index entries (stricter than specified).

## Self-Check: PASSED
Commits d37e840, b5777fd, d1f0430 exist; scripts/README.md and check_scripts_index.py present.
