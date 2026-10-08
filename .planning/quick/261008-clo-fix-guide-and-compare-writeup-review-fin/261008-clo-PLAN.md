---
quick_id: 261008-clo
type: quick
autonomous: true
scope: docs-only (no src/, no test/, no Julia runs)
---

# Quick 261008-clo: apply the review findings to the compare writeup and FRAMEWORK_GUIDE

Two review reports (compare writeup, framework guide) list stale numbers, wrong claims and
leftover planning IDs. Check every claim against the code or the stored results before editing.

## Task 1: docs/writeups/compare_default_stochastic.typ

- Apply findings 1, 2, 3, 4, 5, 7, 8, 9. Finding 6 uses the honest wording "verificado na versão
  anterior; a reexecução de outubro foi única" (no re-run).
- Check the numbers against `results/compare_default_stochastic/*.csv` and `scenario_fan.png`.
- Remove all planning IDs. Compile it with typst. Regenerate a tracked PDF only if one exists
  (there is none).
- Verify: grep `\b[A-Z]{1,6}-\d{2}\b` and `Fase \d+` find nothing; `check_planning_ids.py` passes.
- Commit: `docs(quick-261008-clo): ...`

## Task 2: docs/writeups/FRAMEWORK_GUIDE.html

- Edit with a scratchpad python script that does exact string replacements, each asserted to
  happen exactly once. Never touch the `data:` payloads.
- Apply findings 1–8, the stray-dot fix and the header date ("; revised 2026-10-08").
- Check each claim against src/ (dlmp.jl, ConvexBranchFlow.jl, MPC/Stochastic, results types).
- Verify: sha256 of every data: URI is the same before and after; html.parser raises no
  exceptions; every replacement count is 1; `check_planning_ids.py` passes.
- Commit: `docs(quick-261008-clo): ...`
