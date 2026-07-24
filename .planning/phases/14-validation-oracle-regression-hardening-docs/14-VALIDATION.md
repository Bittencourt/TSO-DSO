---
phase: 14
slug: validation-oracle-regression-hardening-docs
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-24
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems 1.0 / TestItemRunner 1.1 |
| **Config file** | `test/runtests.jl` (auto-discovers `@testitem`s) |
| **Quick run command** | `TestItemRunner.run_tests(["test/<changed-file>.jl"])` from a scratch dev-linked env (explicit paths — bare `@run_package_tests` picks up `.claude/worktrees/` copies) |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | quick ~1-3 min per file; full suite ~9 min |

---

## Sampling Rate

- **After every task commit:** Run the quick command on the touched test file(s)
- **After every plan wave:** Run the full suite command
- **Before `/gsd:verify-work`:** Full suite must be green (modulo the pre-attributed Aqua stale-deps failure from the user-local uncommitted Project.toml edit)
- **Max feedback latency:** ~600 seconds

---

## Per-Task Verification Map

*Filled by the planner — one row per task. Key automated anchors for this phase:*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 14-01-* | 01 | 1 | PVAL-02 | — | N/A | regression | `TestItemRunner.run_tests(["test/test_planning_goldens.jl"])` | ❌ W0 | ⬜ pending |
| 14-01-* | 01 | 1 | PVAL-04 | — | N/A | guard | `TestItemRunner.run_tests(["test/test_planning_no_binaries.jl"])` (or goldens file if co-located) | ❌ W0 | ⬜ pending |
| 14-02-* | 02 | 2 | PVAL-03 | — | N/A | docs build | `julia --project=docs docs/make.jl` exits 0 (checkdocs=:exports strict) | ✅ (build exists, currently RED) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers the harness (TestItemRunner + runtests.jl auto-discovery — new
test files are picked up with zero wiring). New test FILES are deliverables of this phase's
tasks, not pre-work:

- [ ] `test/test_planning_goldens.jl` — created by the PVAL-02 plan (goldens + gate)
- [ ] no-binaries guard testitem(s) — created by the PVAL-04 plan
- [ ] Docs build baseline is currently RED (`[:missing_docs]`, 33 orphaned planning docstrings) —
  the PVAL-03 plan must turn it green; treat `julia --project=docs docs/make.jl` as the
  red→green anchor for docs tasks.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rendered docs pages read correctly (prose quality, math rendering, PSR-number map accuracy) | PVAL-03 | Prose/LaTeX rendering quality is not machine-checkable beyond build success | Open `docs/build/index.html` after build; check the two planning rung pages render math and code output |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 600s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
