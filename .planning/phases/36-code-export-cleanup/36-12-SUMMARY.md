---
phase: 36-code-export-cleanup
plan: 12
subsystem: hygiene
tags: [planning-id-scrub, experiments, core, solver, units, diagnostics, ext]
requires: ["36-11"]
provides:
  - src/experiments, src/core, src/solver, src/units, src/diagnostics and ext/ free of planning identifiers (classifier TOTAL 0 over the 21-file set)
affects: [36-13]
key-files:
  modified:
    - src/experiments/materialize.jl
    - src/experiments/mpc_loop.jl
    - src/experiments/run.jl
    - src/experiments/run_stochastic.jl
    - src/experiments/Scenario.jl
    - src/experiments/store.jl
    - src/experiments/strategies.jl
    - src/experiments/sweep.jl
    - src/core/ModelContext.jl
    - src/core/balance.jl
    - src/core/errors.jl
    - src/core/status.jl
    - src/solver/ProblemClass.jl
    - src/solver/factory.jl
    - src/solver/problem_class_trait.jl
    - src/units/PerUnit.jl
    - src/diagnostics/plots.jl
    - ext/TSODSOGurobiExt.jl
    - ext/TSODSOMakieExt.jl
    - ext/TSODSOMosekExt.jl
    - ext/TSODSOSCSExt.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 12: Scrub of src/experiments, core, solver, units, diagnostics, ext Summary

About 371 classifier hits (273 in src/experiments, 98 in the other 13 files) were rewritten so each rationale survives as plain prose with no phase, plan, requirement, decision, threat, pitfall or research-artifact identifiers. The classifier reports TOTAL 0 over the plan's 21 files; `mpc_loop.jl` alone carried 161 hits, mostly long amendment-history paragraphs, which were condensed into provenance prose. HYG-01 stays pending (later scrub plans and the CI guard remain).

## Commits
- 42e0233: scrub src/experiments
- 4c8ae6a: pre-align docstring tables and one list marker for the formatter (see Deviations)
- 29ddf40: JuliaFormatter 2.10.2 pass on src/experiments (check_content_loss OK)
- 14374ff: scrub core, solver, units, diagnostics, ext
- c8a5ec9: JuliaFormatter 2.10.2 pass on core, solver, units, diagnostics, ext (check_content_loss OK)

## Verification
- Classifier: TOTAL 0 on the plan file set.
- ast_equiv.jl against the plan-start commit: EQUAL for all 21 files (the formatter commits were also checked EQUAL against the scrub commits). thesis_tokens.py: OK.
- check_content_loss.py HEAD prints OK before each formatter commit.
- Targeted tests: experiments, strategies, run_stochastic, mpc_loop, migration gate: 923 pass. errors, factory, status, context, perunit, diagnostics_plot, migration gate: 153 pass, 1 pre-existing broken. After formatting: migration gate, factory, mpc_loop re-run, 385 pass. Canary/goldens untouched. CairoMakie is not installed in this environment, so the Makie extension was verified by AST equality only.

## Message changes
Runtime strings changed (grep of `test/` found no assertion on any of them; `ast_equiv.jl --strings` output reviewed and every entry is listed). No `@testitem` names changed.

mpc_loop.jl
- `_truth_settlement` ArgumentError: `(internal test seam, plan 27-08 — production callers never set this)` became `(internal test seam — production callers never set this)`.
- Thermostatic step-size ArgumentError: `(unchanged by Plan 26-03/FIX-04)` became `(unchanged for the thermostatic recursion)`, and `their soc[1:(H+1)] recursion (FIX-04) covers` became `their soc[1:(H+1)] recursion covers`.
- `@warn` on terminal failure: `(D-04: never throws mid-loop)` became `(never throws mid-loop)`.
- `@warn` on cone-check failure: `escalating via Phase-20's certificate/fallback ladder` became `escalating via the certificate/fallback ladder`.
- SolveFailedError in `_mpc_truth_import_acpf`: `never silently accepted (USER DECISION 2026-09-29, plans 27-08/27-09) — this is a genuine Ipopt non-convergence` became `never silently accepted, never relaxed — this is a genuine Ipopt non-convergence`; `(... OMITTED from this physics-only model, plan 27-09)` became `(... OMITTED from this physics-only model)`. The `FAILED to reach LOCALLY_SOLVED` fragment is unchanged.

run_stochastic.jl
- `@warn` for an infeasible held-out draw: `EXCLUDED from realized_welfare (WR-05 skip-and-report, never silent)` became `EXCLUDED from realized_welfare (skip-and-report, never silent)`.

## ID-like identifiers found (for the guard plan)
None in these files. The scan for identifiers containing planning tokens (`_EXACT04_...`, `_FIXnn`, `PhaseNFixtures`) over the 21 files found no code identifier. File paths cited in prose that exist (for example `test/test_solver_factory_milp.jl`) were left.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded in the same files: `byte-identical`/`BYTE-IDENTICAL` (became `bit-for-bit identical`), `pre-phase`, `post-merge triage` paths, `*-SUMMARY.md`, `*-REVIEW.md`, `*-PLAN.md`, `.planning/...` paths, `USER DECISION`, `DEVIATION (Rule N ...)` headings (the two header notes in mpc_loop.jl became "DESIGN NOTE" and "FIX NOTE"), `checker-flagged`, "gap-closure wave", bare `26-15:` and "Wave-2 plans".
- A semi-automatic first pass (scratch script outside the repo) removed ID-only parentheticals and a join pass fixed continuation lines left starting with punctuation; every hunk was then reviewed. The AST check caught one real mistake: collapsing a split string concatenation in a SolveFailedError message removed one `*` operand, so the split was restored. It also caught an over-wide range edit that had deleted `using JuMP` from the mpc_loop.jl header; restored before commit.
- The formatter pass changes padded markdown-table separator dashes in `Scenario.jl` and `materialize.jl` docstrings (dashes count as content in check_content_loss) and rewrote a docstring line starting with `+` as a `-` list marker in `mpc_loop.jl`. To keep the content-loss check at OK, the tables were pre-aligned to the formatter's output and the `+` line was joined to the previous line in a separate commit (4c8ae6a) before the formatter run.
- Some comment lines are now long (joined where a removed parenthetical had left an orphaned sentence start); the formatter does not wrap comments.

## Known Stubs
None.

## Self-Check: PASSED
