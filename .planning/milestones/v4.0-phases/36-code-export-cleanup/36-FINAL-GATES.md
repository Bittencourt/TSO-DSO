# Phase 36 Final Gates (plan 36-22)

Final code commit: 949b0c8. Docs build and full suite were both launched after it, sequentially.

## Gate log

| Gate | Command | Result |
|---|---|---|
| One-shot tooling scan | `unexport_migrate.py scan ... src ext test docs scripts` | `0 sites in 0 files`; tool and name list deleted |
| Planning-ID guard | `check_planning_ids.py` / `--selftest` | exit 0 (243 files, none) / exit 0 (14 pos, 9 neg, 6 fail-closed) |
| Formatter (CI scope `src ext test docs`) | `format210.jl` (JuliaFormatter 2.10.2) + `check_content_loss.py HEAD` | See formatter note below |
| Token grep | `grep -rnE "Phase[0-9]+Fixtures\|fixtures_phase[0-9]\|:phase[0-9]+\|FIX08" src ext test scripts docs/literate docs/make.jl docs/src .github` | empty (exit 1) |
| Golden literals | `ast_equiv.jl --literals 801fb0c` on canary, planning_goldens, thesis_repro | EQUAL x3 |
| Golden diff stat | `git diff --stat 801fb0c -- test \| grep -i golden` | only `test_planning_goldens.jl` (41 lines), literals EQUAL so comment/identifier edits only |
| Aqua | direct script | 8/8 pass (ambiguity, unbound, undefined exports, project/test project, stale deps, compat, piracy, persistent tasks) |
| Setup names | `check_setup_names.py` | 20 testmodules, 219 uses, 0 unresolved |
| Docs build | `suite_detached.sh p22docs julia --project=docs docs/make.jl` + `check_suite_log.py --mode docs` | `docs OK`, exit 0 |
| Docs cross-refs | grep of log | 4 unresolved `@ref` (plan 06 count: 6; the two `*_FIX08` refs are gone). Remaining: `FIT_SITE3_ALMOST_GAP_TOL`, `BendersMaster.lb_clamped`, `stall_z_atol`, `BendersMasterInteger.lb_clamped` in `docs/src/api.md` (non-fatal, internal names; `:cross_references` in `warnonly`). No heading-anchor warnings from plan 15 renames. |
| Full suite | `suite_detached.sh p22`, `check_suite_log.py p22 --same-pass-as p20` | `suite OK`: 32202 pass / 0 fail / 0 error / 5 broken (27m39s), identical to p20; canary `iters = 56`, `welfare = -4823.66604824162` in log |

### Formatter note
The formatter wanted to change two files. `test/test_exports.jl` is the intended edit of this plan (the 102-name list was inlined as a Symbol tuple because `unexported_names.txt` was deleted; the content-loss "+1608 chars" is that inlining, not loss). `test/test_benchmark_ieee8500.jl` (`"..."` docstring rewritten to a triple-quoted block, +4 chars) was reported as content change by `check_content_loss.py`, so it was reverted and left unformatted, as plans 17/20 did. The remaining tree is formatter-clean.

## ROADMAP success criteria

| # | Criterion | Evidence |
|---|---|---|
| 1 | Planning-identifier guard, CI step | `check_planning_ids.py` exit 0 + selftest 0; CI.yml format job runs it (plan 21); thesis-token checks recorded per plan summary |
| 2 | Enum-only `normalize_reactive_mode`, oracle MethodError | covered by the suite (32202 pass); breaking-changes docs section 7 |
| 3 | Exports snapshot, `ReactiveMode` module, `public` block, docstring, Aqua, docs | `test/test_exports.jl` inside the green suite; Aqua 8/8; docs build OK with `checkdocs = :exports` |
| 4 | Fixture/tag names | token grep empty; `check_setup_names.py` 0 unresolved |

Ledger reconciliation: every public-facing bullet of `36-BREAKING-LEDGER.md` (operational_oracle keywords, ReactiveMode, unexported names, DlmpDecomposition aliases, stored provenance) appears in `docs/src/status_policy.md` section 7. The internal `_coupling_dual(ctx, z)` signature change is intentionally not in user docs. The docs note does not point to the deleted name file.

No golden was re-pinned or touched numerically.

## Pass-count delta
Phase 35 close 32177; final 32202 = +25. All plan runs from p05 onward measured 32201 or 32202 (p20 and p22 identical), so the additions are the new assertions (exports snapshot, MethodError and ArgumentError checks); this plan changed no assertion count (the single inlined `isdefined` assertion replaces the file-reading one).
