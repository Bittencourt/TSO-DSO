# Phase 40 — Deferred / Out-of-Scope Discoveries

## 1. CI planning-identifier guard fails repo-wide at HEAD (pre-existing, NOT this plan's files)

**Found during:** 40-04 Task 2 (CI-guard sweep).

**Observation:** `python3 .github/scripts/check_planning_ids.py` exits 1 at HEAD with
**63 hits** across 20+ tracked files (`src/admm/admm_phases.jl`,
`src/experiments/materialize.jl`, `scripts/case_a_scaling.jl`,
`scripts/case_a_agreement.jl`, `scripts/run_case_a_scaling.sh`, several test files,
`docs/literate/ieee8500_scaling.jl`, `scripts/README.md`, …). The hits are overwhelmingly
the `phase` rule (`(?i)\bphases?[\s-]?\d+`) — prose like "Phase 39" / "Phase-40" in
comments — plus `reqid`/`pitfall`/`artifact` matches in a few files.

**Why it is out of scope here:** every hit predates 40-04 (mostly introduced by the
Phase-39/40 measurement work and earlier phases; the branch has not been pushed since
2026-10-10, so CI has not seen it yet). The plan's verify gate for this surface is
`check_scripts_index.py` (exit 0 — green). Fixing 63 hits across 20+ files owned by five
different phases is a repo-wide rewording effort, not a 40-04 task (scope boundary:
pre-existing failures in unrelated files are logged, not fixed).

**This plan's contribution:** ZERO new hits — the new page
(`docs/literate/case_a_population.jl`) and `docs/make.jl` were written guard-clean and
verified: `check_planning_ids.py docs/literate/case_a_population.jl docs/make.jl` exits 0
("2 files scanned, no planning identifiers").

**Suggested resolution path (for a future hygiene task):** either reword the hits or
extend the allowlist with per-file reasons; note the guard's own allowlist comment says
"every hit is fixed by rewording, not exempted", so rewording is the intended path.
Note the local branch (`agents/session-2026-10-23`) is ~16 days ahead of `origin/main`;
the format job (which runs this guard) will go red on the next push unless this is
resolved first.

**Date:** 2026-10-24
