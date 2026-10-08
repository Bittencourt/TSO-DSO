---
phase: 29
slug: genuine-bilevel-tso-dso-variant
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-30
---

# Phase 29 — Validation Strategy

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems; BilevelJuMP/Ipopt in test/Project.toml |
| **Quick run** | direct `julia --project=.` scripts (never TestItemRunner under `--project=.`); BilevelJuMP oracle scripts need the test environment — see 29-RESEARCH.md for the working invocation |
| **Full suite** | `julia --project=. -e 'import Pkg; Pkg.test()'` detached, HEAD recorded, no `.claude/worktrees/agent-*` present |

| Requirement | Behavior | Verification | Status |
|-------------|----------|--------------|--------|
| BILEV-01 | solve_bilevel! solves the genuine bilevel (KKT+SOS1 MILP, HiGHS); unsupported inputs throw | direct script on 2-/3-bus fixture | ⬜ |
| BILEV-02 | fixture: bilevel optimum ≠ joint by measured margin; production == BilevelJuMP StrongDuality == brute-force grid | direct scripts + committed testitems | ⬜ |
| regression | solve_stackelberg! byte-identical (existing goldens untouched) | existing planning testitems via direct script | ⬜ |

**Approval:** pending
