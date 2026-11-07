---
phase: quick-261107-qzn
plan: 01
status: complete
subsystem: docs
tags: [convex-branch-flow, exactness-copy, documentation]
requirements: [QUICK-261107-qzn]
key-files:
  modified:
    - src/powerflow/ConvexBranchFlow.jl
    - src/models/ac_oracle.jl
    - src/models/restriction_exactness.jl
    - test/test_convex_branch_flow.jl
    - test/test_ac_oracle.jl
    - docs/literate/convex_branch_flow.jl
    - docs/literate/ac_oracle.jl
    - docs/literate/restricted_branch_flow.jl
    - docs/src/index.md
    - docs/writeups/FRAMEWORK_GUIDE.html
    - scripts/pv_boom_case_study.jl
    - results/pv_boom/findings.txt
    - .planning/PROJECT.md
    - .planning/todos/completed/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md
completed: 2026-11-07
---

# Quick 261107-qzn: Re-document default ConvexBranchFlow exactness copy

The default copy (`v̂ ≤ vmax²`, eq. 3.45) is now described everywhere as a per-branch inner approximation (`v̂ − v = Σ_path |z|²l`), not Gan-Low OPF-m and not exact by theorem. No behaviour change.

## Commits

- fc1bcf1 docs: src, tests, literate pages
- 252db0b docs: index.md, FRAMEWORK_GUIDE, pv_boom narrative + findings.txt, PROJECT.md
- e1e9f37 style: formatter on scripts/pv_boom_case_study.jl
- e97dd06 docs: close the 2026-10-07 todo (moved to completed/ with resolution)

## Verification

- Targeted tests (ConvexBranchFlow, ac_oracle, restricted_branch_flow files via Pkg.test): 109 pass / 0 fail / 0 error (aggregate; Pkg.test prints one total). test/Project.toml and test/Manifest.toml restored.
- Code-only comparison (comments and docstrings stripped, whitespace-strict) is identical to HEAD for all 8 src/test/literate .jl files.
- check_planning_ids: "FAIL: 354 hit(s), 0 stale" (baseline unchanged).
- results/: only findings.txt changed (one paragraph, prose only; existing numbers unchanged, new text cites the 6.10e-6 / 3.63e-6 / +2.6e-9 tolerance figures from the debug session).
- scripts/pv_boom_case_study.jl parses; the script was not re-run.
- check_content_loss.py reports content change on the prose-edited files by design (it only passes for formatter-only changes); it was clean on the formatter-only style commit.

## Deviations

- The plan listed the "Overvoltage-Capable Relaxation" title in restricted_branch_flow.jl; it was a markdown header, so it was changed to "Restriction" (matches docs/make.jl and README, which already said Restriction). The FRAMEWORK_GUIDE reference to that title was updated too. docs/src/generated/ is untracked and untouched.
- Literate line numbers had drifted from the plan; sites were located by phrase.
- Formatter touched only scripts/pv_boom_case_study.jl code layout (separate style commit); the other .jl files needed no formatter changes.

## Out of scope / left unchanged

- Runtime strings: none in the listed src files needed changing. Not touched: src/models/exactness.jl (l.297 and l.435 still say the copy "drives the cone tight") and src/pricing/fit.jl l.514 (same phrasing); these were not in the plan's file list and are worth a follow-up.
- docs/literate/ac_oracle.jl and restricted_branch_flow.jl still contain older narrative on live-executed output ("loose-relaxation solution", "orders of magnitude above the benign feeder's"); only the framing sites in the plan were reworded.
- PROJECT.md l.64 and l.119 (historical target text / v2.1 finding) left as historical record.
- .planning/debug/lindistflow-vmax-reverse-flow.md was already modified before this task and is not part of these commits.
- Docs build not run (orchestrator).

## Known Stubs

None.

## Orchestrator follow-up (2026-11-07)

- **`exactness.jl`:** the leftover "drives the cone tight" docstring in `src/models/exactness.jl:297` is corrected (commit 880e34d). The two other hits, at `exactness.jl:435` and `fit.jl:514`, credit the loss-cost gradient, which is correct, so they were left alone.
- **First docs build failed:** `api.md` crossed Documenter's 1 MiB hard `size_threshold`, from 1023.56 KiB before this task.
- **Threshold raised:** to 1.5 MiB with a 1 MiB warning (commit in `docs/make.jl`), following the two earlier documented raises. Splitting `api.md` is now in the backlog todo.
- **Second docs build:** exit 0, with only the two known `@ref` warnings plus size warnings.
- **Debug session:** `lindistflow-vmax-reverse-flow` is resolved and moved to `.planning/debug/resolved/`.
