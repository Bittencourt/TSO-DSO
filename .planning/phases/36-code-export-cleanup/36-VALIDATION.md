---
phase: 36
slug: code-export-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-05
---

# Phase 36 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: 36-RESEARCH.md
> "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner; Python static checkers |
| **Config file** | `test/Project.toml`, `test/runtests.jl` |
| **Quick run command** | `JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<test_x.jl>` (or `tag:<sym>`) |
| **Aqua gate** | direct script: `JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -e 'using TSODSO, Aqua, Test; Aqua.test_all(TSODSO)'` |
| **Static gates** | `check_planning_ids.py`, AST-equivalence checker, thesis-token checker, `check_content_loss.py HEAD` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (detached, sequential, ~27 min; baseline 32177/0/0/5) |
| **Docs gate** | `julia --project=docs docs/make.jl` |
| **Estimated runtime** | static seconds; targeted 1–3 min; full ~27 min |

---

## Sampling Rate

- **After every task commit:** static checks for touched files + targeted `file:` set
- **After every plan wave:** full suite detached (no concurrent julia, no agent worktrees), canary log line
  `welfare = -4823.66604824162` + iters 56, Aqua script; docs build after export and rename waves
- **Before `/gsd:verify-work`:** full suite green, guard exit 0, docs build green, goldens diff empty
- **Max feedback latency:** 180 s (targeted)

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| HYG-01 | zero planning IDs in scope | static | `python3 .github/scripts/check_planning_ids.py` | ❌ W0/W5 | ⬜ pending |
| HYG-01 | guard regex self-test | unit | `check_planning_ids.py --selftest` | ❌ W5 | ⬜ pending |
| HYG-01 | comment-only edits (no code change) | static | AST-equivalence checker vs HEAD | ❌ W0 | ⬜ pending |
| HYG-01 | thesis refs preserved | static | thesis-token multiset checker | ❌ W0 | ⬜ pending |
| HYG-01 | formatter lost no text | static | `check_content_loss.py HEAD` | ✅ | ⬜ pending |
| HYG-02 | removed kwargs rejected; enum-only reactive mode | unit | `file:test_oracle.jl`, `file:test_reactive_mode.jl` | ✅ edit | ⬜ pending |
| HYG-02 | no behaviour change | integration | canary file + full suite | ✅ | ⬜ pending |
| HYG-03 | export keep-set exact; generic names unexported | unit | `tag:exports` (`test/test_exports.jl`) | ❌ W2 | ⬜ pending |
| HYG-03 | no undefined exports | quality | Aqua direct script | ✅ | ⬜ pending |
| HYG-03 | docs build (checkdocs = :exports, nested module) | docs | docs make | ✅ | ⬜ pending |
| HYG-07 | no phase-named fixtures/tags | static | grep `Phase[0-9]+Fixtures|fixtures_phase[0-9]|:phase[0-9]+` = 0 | ❌ W3 | ⬜ pending |
| HYG-07 | every `setup=[X]` resolves | static | name-resolution script | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] AST-equivalence checker (Julia)
- [ ] Thesis-token multiset checker (Python)
- [ ] ID classifier (Python) with MIXED flagging
- [ ] Unexport-usage scanner / `using TSODSO:` inserter
- [ ] `setup=[...]` name-resolution script
- [ ] Multi-spec extension of `scripts/run_tests_filtered.jl`
- [ ] Baseline capture (full-suite counts + canary log line)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rewritten comments keep their rationale | HYG-01 | prose quality | spot-check a sample per directory in review |
| Top-module docstring describes current module | HYG-03 | prose accuracy | read `src/TSODSO.jl` docstring vs layer list |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
