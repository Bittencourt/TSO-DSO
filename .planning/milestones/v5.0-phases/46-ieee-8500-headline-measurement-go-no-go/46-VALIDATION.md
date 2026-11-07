---
phase: 46
slug: ieee-8500-headline-measurement-go-no-go
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-11-05
---

# Phase 46 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: the
> "Validation Architecture" section of `46-RESEARCH.md`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems `@testitem` via `Pkg.test()`; TestItemRunner configured by `test/runtests.jl` with tags `:fast`/`:slow` |
| **Config file** | `test/runtests.jl`, `test/expected_broken.txt` |
| **Quick run command** | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (orchestrator only, detached, ~105 min) |
| **Estimated runtime** | ~60–240 s per targeted fast file, including load and precompile |

After any run that mutated them, restore with `git checkout -- test/Project.toml test/Manifest.toml`.
Never run TestItemRunner via `julia -e` or `--project=test`. Agents do not run the full suite and
do not run any IEEE-8500 solve.

---

## Sampling Rate

- **After every task commit:** run the touched test file (fast set).
- **After every plan wave:** run `test_ieee8500_scenario.jl, test_strategies.jl, test_experiments.jl, test_flex_population.jl, test_admm_knifeedge_canary.jl, test_exports.jl`, then the planning-ID, scripts-index and API-lint checkers.
- **Before verification:** the full suite must be green against the baseline of 36668 pass / 0 fail / 0 error / 7 allowlisted broken, plus the new items. The orchestrator's detached T = 10 run must have recorded its row.
- **Max feedback latency:** ~300 s for a targeted file.

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| SCALE-08 | The widened feeder tuple constructs `:ieee8500`/`:ieee8500_mv`. The default and `:bogus` behave as before. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-08 | The new `ArgumentError` guards fire: `:default_10pct` off-8500, `:case_a_784` on 8500, `:ac` on 8500, MPC/Stochastic on 8500. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-08 | `:default_10pct` materializes deterministically with the expected aggregator and bus counts, and equals the harness filtered population at an equal seed. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-08 | The script's phase composition equals `run_scenario` on IEEE-13. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-08 | Row building, the status vocabulary, keyed upsert, ratio parse and pre-flight parse work. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-07 | The NO-GO derivation from the committed CSVs gives 11,753,716 kB = 11.209 GiB (binary), B1 = 11.520 GiB and status `memory_infeasible`. | unit | quick run | ❌ W0 | ⬜ pending |
| SCALE-08 | The measured T = 10 row exists with an allowed status, joined to its wrapper resource row. | data check (post-run) | CSV assertion after the orchestrator run | ❌ W0 | ⬜ pending |
| SC3 | No tolerance, τ, ε or hybrid floor changed. | diff gate | `git diff` over `src/admm`, `src/models/exactness.jl` and the solver factory is empty; the canary is unchanged | ✅ | ⬜ pending |
| All | Default-path regression. | regression | `TSODSO_TEST_FILES=test_strategies.jl,test_experiments.jl,test_flex_population.jl,test_admm_knifeedge_canary.jl,test_exports.jl` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_ieee8500_scenario.jl`, created by the plans that own it.
- [ ] The one-line tuple edit in `test/test_flex_population.jl:20`, made in the same change as the selector.
- [ ] Framework install: none.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The measured T = 10 run on the real host | SCALE-08 | It needs about 6 GiB and must run detached and alone, behind the MemAvailable ≥ 8 GiB pre-flight | The orchestrator launches `scripts/run_ieee8500_point.sh` with the scenario script. If the pre-flight refuses or earlyoom kills the run, the outcome is recorded as a row. |
| The docs section reads honestly (NO-GO stated as a threshold verdict; B1 bound vs B2 estimate; path-divergence label) | SCALE-07/08 | Prose fidelity | Review the appended dated section of `docs/literate/ieee8500_scaling.jl`. |

---

## Validation Sign-Off

- [x] Every task has an `<automated>` verify or a Wave 0 dependency
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers every MISSING reference
- [x] No watch-mode flags
- [x] Feedback latency < 300 s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-11-05
