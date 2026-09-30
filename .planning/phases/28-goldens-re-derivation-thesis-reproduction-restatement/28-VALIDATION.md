---
phase: 28
slug: goldens-re-derivation-thesis-reproduction-restatement
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-29
---

# Phase 28 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner; Documenter + Literate docs build |
| **Quick run command** | direct `julia --project=. <script>.jl` (never TestItemRunner under `--project=.`) |
| **Docs build** | per 28-RESEARCH.md (docs/make.jl) — must execute every edited literate page |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` DETACHED, HEAD recorded, NO `.claude/worktrees/agent-*` present |
| **Estimated runtime** | quick ~1–3 min; repro pipeline per research; full suite ~21–36 min |

## Per-Requirement Verification Map

(Full table in `28-RESEARCH.md` → Validation Architecture.)

| Criterion | Behavior | Verification | Status |
|-----------|----------|--------------|--------|
| SC-1 | every moved golden 5939799..HEAD has old→new + cause; 28-CROSS-PHASE-AUDIT.md | committed audit script exits 0 (nonzero on any unexplained literal) | ⬜ |
| SC-2 | REPRO-01 re-run (sign flip, magnitude gap, 5-pt sweep, figures) restated old vs new | repro script outputs recorded + literate page executes in docs build | ⬜ |
| SC-3 | EXACT-04 & v2.1/v3.0 inexactness re-verified under default + thesis_literal; restated | direct script asserting both verdicts + docs build | ⬜ |
| Deferred | MPC truth-settlement semantics + DLMP naming restated in docs | grep assertions + docs build | ⬜ |

## Validation Sign-Off

- [ ] All tasks have real `<automated>` verify
- [ ] Docs build executes all edited pages
- [ ] Full suite green (Phase 27 close: 30703/0/0/5 at 40ccff2)
- [ ] `nyquist_compliant: true` set at phase close

**Approval:** pending
