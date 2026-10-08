---
phase: 37
slug: test-infrastructure-repo-hygiene
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-06
---

# Phase 37 — Validation Strategy

> Source: 37-RESEARCH.md "Validation Architecture" (authoritative detail there).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | TestItemRunner 1.1.5 / TestItems 1.0.0 (+ plain Test); JET 0.11.6 static check (Julia 1.12 only) |
| **Config file** | `test/runtests.jl`, `test/Project.toml` |
| **Quick run command** | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<x>.jl` |
| **Full suite command** | `.github/scripts/suite_detached.sh LABEL` + `check_suite_log.py` (~28 min; never concurrent) |
| **Fast set** | `TSODSO_TEST_SET=fast julia --project=. -e 'import Pkg; Pkg.test()'` (~8–10 min, detached) |
| **Estimated runtime** | quick ≤ 60 s; JET ~61 s warm; fast ~10 min; full ~28 min; flake harness 25–48 min (manual) |

---

## Sampling Rate

- **After every task commit:** relevant filtered run/script (≤ 60 s) + `check_planning_ids.py` + `check_script_api.jl`
- **After every plan wave:** fast set, JET check, docs build when docs touched
- **Before `/gsd:verify-work`:** detached full run (`all`) reproduces 32205/0/0/5 or documents each delta (known: 1.12.7 FIT item); canary iters = 56, welfare = -4823.66604824162; any src/ edit bit-identical on goldens
- **Max feedback latency:** 60 s (quick)

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| HYG-04 | only baselined JET signatures | static | `scripts/jet_check.jl` | ❌ W0 | ⬜ pending |
| HYG-04 | normalize/diff logic | unit | `scripts/jet_check.jl --selftest` | ❌ W0 | ⬜ pending |
| HYG-05 | fast ∪ slow = all (605), no empty set, bad env errors, canary fast | discovery-only | discovery-count check | ❌ W0 | ⬜ pending |
| HYG-05 | fast set within CI budget | integration | `TSODSO_TEST_SET=fast` Pkg.test | ❌ W0 | ⬜ pending |
| HYG-06 | retry helper semantics | unit | `file:test_flake_retry.jl` | ❌ W0 | ⬜ pending |
| HYG-06 | observed Broken ⊆ allowed list | suite-level | runtests outer testset | ❌ W0 | ⬜ pending |
| HYG-06 | flake rates recorded (both 1.12 patches) | measurement | `scripts/flake_rate.jl --repeats 20` | ❌ W0 | ⬜ pending |
| HYG-08 | README covers scripts; archive skipped by API check | script | `check_script_api.jl --selftest` + scan | ✅ extend | ⬜ pending |
| HYG-08 | `.planning/tmp/` untracked + ignored | shell | `git ls-files .planning/tmp` empty; `git check-ignore` | — | ⬜ pending |
| HYG-08 | no root Manifest; 1.10/1.11/1.12 resolve | CI/local | manifest_file per `julia +1.x` | — | ⬜ pending |
| HYG-08 | pv_boom case study passes gate after re-tune; merged report regenerated | measurement | `scripts/pv_boom_case_study.jl` then `scripts/pv_boom_report.jl` | ✅ edit | ⬜ pending |
| HYG-08 | docs build: no unresolved @ref | build | docs build | ✅ | ⬜ pending |
| HYG-08 | ieee8500 test formatter/content-loss clean | static | `check_content_loss.py HEAD` | ✅ | ⬜ pending |
| All | planning-ID guard clean | static | `check_planning_ids.py` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/jet_check.jl` + baseline + `--selftest`
- [ ] `test/runtests.jl` rewrite (env selection, test-dir restriction, outer testset + allowed-Broken list)
- [ ] retry `@testmodule` + `test/test_flake_retry.jl`
- [ ] discovery-count check + canary-stays-fast assertion
- [ ] `scripts/flake_rate.jl`
- [ ] `.github/workflows/slow.yml`; `jet` job + `TSODSO_TEST_SET` in `CI.yml`
- [ ] `check_script_api.jl` archive skip + selftest case

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CI workflows behave on GitHub (env passthrough, cron) | HYG-04/05 | needs GitHub Actions | push branch / workflow_dispatch; inspect with `gh run view` |
| PV-boom re-tune is physically sensible | HYG-08 | research judgement | calibration rationale documented in SUMMARY + scripts README |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
