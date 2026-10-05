---
phase: 36-code-export-cleanup
plan: 11
subsystem: hygiene
tags: [planning-id-scrub, admm, powerflow]
requires: ["36-10"]
provides:
  - src/admm/*.jl and src/powerflow/*.jl free of planning identifiers (classifier TOTAL 0 over the 14-file set)
affects: [36-12]
key-files:
  modified:
    - src/admm/AgrOpt.jl
    - src/admm/DsoOpt.jl
    - src/admm/admm_phases.jl
    - src/admm/admm_state.jl
    - src/admm/residuals.jl
    - src/admm/solve_admm.jl
    - src/powerflow/ACPowerFlow.jl
    - src/powerflow/ConvexBranchFlow.jl
    - src/powerflow/DCPowerFlow.jl
    - src/powerflow/LinDistFlow.jl
    - src/powerflow/MeshedFlow.jl
    - src/powerflow/RestrictedBranchFlow.jl
    - src/powerflow/AbstractPowerFlow.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 11: Scrub of src/admm and src/powerflow Summary

About 466 classifier hits across 13 files (ReactiveMode.jl had none) were rewritten so each rationale survives as plain prose without phase, plan, requirement, decision, threat, pitfall or research-artifact identifiers. The classifier reports TOTAL 0 over the plan's 14 files. HYG-01 stays pending (later scrub plans and the CI guard remain).

## Commits
- 4911de8: scrub src/admm
- b806bbf: JuliaFormatter 2.10.2 pass on src/admm (check_content_loss OK)
- b3c8612: scrub src/powerflow
- 80f9d3d: JuliaFormatter 2.10.2 pass on src/powerflow (check_content_loss OK)

## Verification
- Classifier: TOTAL 0 on the plan file set.
- ast_equiv.jl against the plan-start commit (afbbe96): EQUAL for all 14 files. thesis_tokens.py: OK.
- format210.jl re-run over the whole set is a no-op; check_content_loss.py HEAD prints OK.
- Targeted tests (admm_phases, reactive_mode, dso, agr, admm_dualresid, migration gate, powerflow, convex_branch_flow, restricted_branch_flow, ac_powerflow, admm, admm_generic_pf, knifeedge canary, admm_reactive): 395 pass, 0 failed, 0 errored. After the formatter passes, admm_phases + migration gate + canary re-run: 63 pass. Canary unchanged (welfare = -4823.66604824162); goldens untouched.

## Message changes
Runtime strings changed (grep of `test/` found no assertion on any of them; `ast_equiv.jl --strings` output reviewed and every entry is listed):

DsoOpt.jl (ArgumentError from `build_dso_opt`)
- `(q_inject, D-09, or the FIX-05 p_inject·tanφ flexible-load draw)` became `(q_inject, or the p_inject·tanφ flexible-load draw)`.
- `(WR-04, phase-19 review; widened PM-03, post-merge triage).` became `(or omit it to use the context-sensitive default).`

admm_phases.jl (ArgumentError)
- `coupling is a Phase-7 extension` became `coupling is not supported`.

solve_admm.jl
- ArgumentError: `(... SOC-exactness enabler, PF-04; import-only is out of Phase-6 scope)` became `(... SOC-exactness enabler; import-only is not supported)`.
- Non-convergence error: `refused (thesis §2.6; RESEARCH Pitfall 2).` became `refused (thesis §2.6).`

LinDistFlow.jl, ConvexBranchFlow.jl, RestrictedBranchFlow.jl (ArgumentError for meshed feeder)
- `invalid formulation x feeder pair per ARCH-03` became `invalid formulation x feeder pair (a radial formulation needs a radial feeder)`.

RestrictedBranchFlow.jl (negative-ε ArgumentError)
- `violating D-01's genuine-restriction contract` became `violating the genuine-restriction contract`.

No `@testitem` names changed.

## Hand-edited MIXED lines
Thesis references (eq. 3.46, 3.47, 3.31, 3.21-3.22, 3.23, 3.33, 3.36, 3.37, 3.39, 3.43, 3.45) on the mixed lines in AgrOpt, DsoOpt, solve_admm, ACPowerFlow, ConvexBranchFlow, LinDistFlow and RestrictedBranchFlow were kept verbatim, confirmed by thesis_tokens.py. Literature references (Gan-Low Theorem 2 / Lemma 1 / Definition 3, Farivar-Low, Boyd §3.3-3.4.1, App. C) were left verbatim.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded in the same files: `byte-identical` (became `bit-for-bit identical`), `pre-Phase-19`, `this plan`, `post-merge triage`, `.planning/debug/...` and `*-SUMMARY.md` paths (replaced by the fact or a test-file pointer), `quick task`, `USER DECISION`, `Escalation history (Rule 4 / ... checkpoint)`. The code identifier `_EXACT04_MEASURED_ε` was kept (renaming it would change code); only prose around it changed. References to the `EXACT-04` finding became "the high-PV reference fixture".
- A semi-automatic first pass (scratch script outside the repo) removed ID-only parentheticals; every hunk was then reviewed and dangling fragments (orphaned punctuation, joined sentences) fixed by hand. In DsoOpt.jl one accidentally deleted docstring line was restored before the commit.
- The plan-start hash was recorded as afbbe96 in `.planning/tmp/36/p11_start`. The rtk hook rewrites `git diff --name-only`, so checks used an explicit file list.

## Known Stubs
None.

## Self-Check: PASSED
