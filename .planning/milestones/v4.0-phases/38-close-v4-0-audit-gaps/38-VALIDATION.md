---
phase: 38
slug: close-v4-0-audit-gaps
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-10-07
---

# Phase 38 — Validation Strategy

> Source: 38-RESEARCH.md "Validation Architecture" (authoritative detail there).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test (stdlib) + TestItemRunner 1.1.5 (`@testitem`, `@testmodule` setups) |
| Config file | `test/runtests.jl` (discovery rooted at `test/`), `test/runner_support.jl`, `test/expected_broken.txt` |
| Quick run command | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<basename.jl>` |
| Discovery/count check | `... scripts/run_tests_filtered.jl "$PWD" --count-sets --strict` (baseline all=511 fast=474 slow=37 files=98; final all=517 fast=480 slow=37 files=99) |
| Full suite command | `.github/scripts/suite_detached.sh p38_1125` (default `julia --project=. -e 'import Pkg; Pkg.test()'`; for 1.12.7 pass `julia +1.12 --project=. -e 'import Pkg; Pkg.test()'`) then `python3 .github/scripts/check_suite_log.py p38_1125 --broken 5` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-08 / FIX-10 | MPC tier uses the hybrid floor; old-accepts/new-refuses point escalates; `cone_maxratio` equals `hybrid_ratios` max | unit/integration | `... run_tests_filtered.jl "$PWD" file:test_mpc_loop.jl` | test file ✅, new item ❌ |
| FIX-08 | `assert_socp_exact!` verdicts unchanged after the kernel refactor | unit | `... file:test_exactness.jl,test_admm_exactness_default.jl` | ✅ |
| ARCH-08 / HYG-05 | `solve_admm(...; time_limit_s=1e-9).status == :budget_exceeded`, no price fields; maxiter cap throws `ConvergenceError` | integration | `... file:test_admm_timeout.jl` | file ✅ (plain script → convert) |
| HYG-05 | count-sets consistent, timeout items discovered | infra | `... --count-sets --strict` | ✅ |
| ARCH-02 | `Scenario(strategy=ADMM(), allow_export=false)` → `ArgumentError`; legacy `:admm`; `TSODSO.run(ADMM(), s_noexport)` | unit (no solve) | `... file:test_strategies.jl` | ❌ new assertions |
| ARCH-08 | OOS inexact draw → skip-and-report flag + status; golden stays `:solved`; vocabulary pin updated | unit + integration | `... file:test_run_stochastic.jl,test_stochastic_oos_harness.jl,test_status_policy.jl` | ✅ (edits) |
| W4 (store) | `result_to_dict` stores `:LIVE` Symbol; wload gives a Symbol | unit (no solve) | `... file:test_experiments.jl` (or test_strategies.jl) | ❌ new item |
| W1/W2 prose | docs build green; literate pages execute | docs | `julia --project=docs docs/make.jl` (via suite_detached.sh `--mode docs`) | ✅ |
| W2 guide | 0 static findings | static (scratch) | `julia +release --project=. --startup-file=no .github/scripts/check_script_api.jl $SCRATCH/guide_blocks` + scratch scan | n/a (scratch) |
| W7 | setup names resolve; selftest | static | `python3 .github/scripts/check_setup_names.py --selftest && python3 .github/scripts/check_setup_names.py` | ✅ |
| Gates | planning IDs, scripts index, script API, content loss, JET | static | `python3 .github/scripts/check_planning_ids.py`; `python3 .github/scripts/check_scripts_index.py`; `julia --project=. .github/scripts/check_script_api.jl`; `python3 .github/scripts/check_content_loss.py HEAD`; `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl` | ✅ |

### Sampling Rate
- **Per task commit:** the filtered-runner command for the touched test file(s), plus `check_planning_ids.py` and `format210.jl` on touched files.
- **Per wave merge:** `--count-sets --strict`; filtered runs of every file touched in the wave.
- **Phase gate:** full suite on 1.12.5 then 1.12.7 (sequential, never concurrent), docs build, JET on 1.12.7, all guards. Canary log lines must show iters = 56 and welfare = -4823.66604824162.

### Wave 0 Gaps
- [x] New `@testitem` for the MPC regression point and parity (test_mpc_loop.jl).
- [x] test_admm_timeout.jl converted into `@testitem`(s).
- [x] W5 assertions (test_strategies.jl or test_scenario_pf.jl).
- [x] W6 tests: harness-level inexact flag (pin-binding fixture at default tolerance gives a robust ratio of about 51), `_stochastic_status` pure-helper cases, updated vocabulary pin.
- [x] W4 no-solve round-trip item.
No framework install needed.

## Manual-Only Verifications

| Behavior | Why Manual | Instructions |
|----------|------------|--------------|
| FRAMEWORK_GUIDE model-text corrections are accurate | prose judgement | spot-check each corrected passage against src/ and status_policy.md |
| compare_default_stochastic writeup moves (if any) | research judgement | numbers documented in SUMMARY |

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-10-07 (plan 38-10 phase gate: every row green; evidence in 38-FINAL-GATES.md — 1.12.5 Pass 32304 and 1.12.7 Pass 32299, both 0/0/Broken 5, canary iters 56, count-sets all=517 fast=480 slow=37 files=99, JET 0 NEW / 0 FIXED, docs OK)
