---
phase: 36-code-export-cleanup
plan: 15
subsystem: hygiene
tags: [planning-id-scrub, docs, literate]
requires: ["36-14"]
provides:
  - the 20 docs/literate pages free of planning identifiers (classifier TOTAL 0 over docs/literate)
affects: [36-16]
key-files:
  modified:
    - docs/literate/*.jl (all 20 pages)
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 15: Scrub of docs/literate pages Summary

All 370 hit lines in the 20 literate pages were rewritten as reader-facing prose. Rationale, numbers, file and `run_label` citations (including those in `ieee8500_scaling.jl`) and thesis-equation references are kept. Process-specific headings such as "Restated in v4.0 (Phase 28)" became descriptive ones ("Restated: gate 1 versus gate 2", "Restated after the model corrections", "Dual-mode summary", "Post-refactor measured results"). Planning-artifact citations (`.planning/...`, `*-FINDINGS.md`, spike directories, project-memory slugs) were replaced by the fact itself or a pointer to another docs page. HYG-01 stays pending.

## Commits
- b9cf994: scrub pages a through m
- cc9475f: formatter pass (experiments, integer_investment, meshed_reactive_price)
- bd03061: scrub pages n through z
- 99446d3: formatter pass (socp_applicability, stackelberg_benders, stochastic_pv_demand)

Formatter passes: JuliaFormatter 2.10.2 only changed whitespace; `check_content_loss.py HEAD` printed OK before each formatter commit and the final whole-set pass was a no-op.

## Verification
- Classifier: `TOTAL 0` over `docs/literate`.
- `ast_equiv.jl` against the pre-plan commit (2f93aba): EQUAL for all 20 files.
- `thesis_tokens.py`: three DIFF reports in `ac_oracle.jl`, `convex_branch_flow.jl`, `restricted_branch_flow.jl`. All are one-word false positives: the removed token was the word "thesis" inside the project-memory slug `v2.1-socp-inexactness-and-thesis-repro` (a planning artifact), replaced by "the earlier SOCP-inexactness study". Every thesis equation/table/page reference is verbatim.
- All files parse (`Meta.parseall`).
- No docs build and no test run (the plan has none; code AST-equal, only comments and the string literals listed below changed). Last full suite remains p13 = 32202/0/0/5.

## Message changes
No `src/` runtime messages or `@testitem` names changed. String literals inside literate scripts that render in output (figure titles/labels, one error message in docs code):

- `integer_investment.jl`: `"... (WR-01 regression, Phase 24 code review)."` to `"... (regression: both trial points outside the deliverable capacity)."` (ErrorException text inside the page's own `enumerate_lattice` helper)
- `mpc_rolling_horizon.jl`: figure titles lost `(MPC-03)` and `(D-10)`
- `socp_applicability.jl`: `"EXACT-04 control"` to `"high-PV control"`; `"default (pv=1.2, EXACT-04)"` to `"default (pv=1.2, high-PV control)"`; printf label `"pv=1.2 (EXACT-04) default"` to `"pv=1.2 (high-PV control) default"`
- `stackelberg_benders.jl`: figure title lost `(BILEV-04b)`
- `stochastic_pv_demand.jl`: three figure titles lost `(PRIMARY, D-05)` to `(PRIMARY)`, `(D-07)`, `(STOCH-03/D-09)`
- `convex_branch_flow.jl`: figure title `"... vs PF-04 refusal threshold"` to `"... vs exactness refusal threshold"`

## Hand-edited MIXED lines
- `prosumer_welfare.jl` eq. 3.12 line: `(WR-01: the upper budget...)` to `(the upper budget...)`, eq. 3.12 reference verbatim.
- `convex_branch_flow.jl` eq. 3.43 display line: `corrected default — FIX-01/02, see Verdict below` to `corrected default — see Verdict below`.
- `meshed_reactive_price.jl` and `ieee123_impedances.jl`: arXiv:1405.0814 and Appendix E references untouched.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded: `byte-identical` to `bit-for-bit identical` (experiments, meshed, socp_applicability), `byte-comparable`, "this session", "this sweep", "spikes" to "probes", "quick task", "removal/phase" phrases, "REQUIREMENTS Out-of-Scope" in two pages.
- In-page anchors: the "Restated in v4.0 (Phase 28)" headings were renamed; the only in-page cross-reference (`restricted_branch_flow.jl` pointing at `ac_oracle.jl`'s section) was updated to match. No other source refers to them (stale generated markdown under `docs/src/generated/` is rebuilt by the docs build).
- Plan step 3 asks for the pre-plan hash in `.planning/tmp/36/`; recorded as `p15_start.txt`.

## Known Stubs
None.

## Self-Check: PASSED
