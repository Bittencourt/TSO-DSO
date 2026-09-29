# Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement - Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

FIX-11: cross-phase audit that every golden moved in Phases 26–27 was re-derived with an explanation;
re-run the v2.1 thesis reproduction (DSO-surplus sign flip, welfare-magnitude gap) and the v2.1/v3.0
SOCP-inexactness findings (EXACT-04 etc.) against the corrected models; restate changed results in
PROJECT.md and the literate docs. No new modelling features.

</domain>

<decisions>
## Implementation Decisions

### Cross-phase golden audit (SC-1)
- A committed audit script parses `git diff 5939799..HEAD -- test/` (5939799 = pre-Phase-26 base) for
  every changed numeric literal and flags any lacking an adjacent old→new + cause comment; its output
  plus the 26-/27-GOLDEN-AUDIT tables are merged into one `28-CROSS-PHASE-AUDIT.md`.
- Also audit pinned numbers cited in `docs/literate/*.jl` prose and `.planning/PROJECT.md` key
  findings that reference now-moved values.
- Any unexplained move is explained in-phase (comment + audit row) — never silently accepted.

### Thesis reproduction re-run (SC-2)
- Re-run the FULL REPRO-01 pipeline (`docs/literate/thesis_reproduction_ieee123.jl`, `scripts/`
  repro/stability tooling): sign flip + welfare-magnitude gap, the 5-point stability sweep, and
  regenerate `results/thesis_caseA` figures + `docs/writeups` artifacts that depend on it.
- The repro-point SOCP-exactness drift found in 27-05: MEASURE first — precision artifact → measured
  tol_gap; genuinely inexact → restate as uncertified at that point. Never hide.
- Restatement framing: old vs new side by side with the named cause of each change (FIX-0x / PM-0x /
  27 execution amendments); a changed result is reported as a finding, not a regression.

### SOCP-inexactness + deferred restatements (SC-3)
- Re-verify EXACT-04 (and the v2.1/v3.0 inexactness findings) under BOTH the default Gan–Low copy
  (expected exact) and `ConvexBranchFlow(; thesis_literal=true)` (expected inexact); restate as a
  property of the thesis-literal copy. Update `socp_applicability.jl`, `restricted_branch_flow.jl`,
  `ac_oracle.jl` literate pages and PROJECT.md.
- Also restate the Phase-27 deferrals: MPC truth-settled realized_welfare/regret semantics
  (`docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl`) and DLMP `cone`/`drop`
  naming across docs.
- Format: edit pages in place with a "Restated in v4.0 (Phase 28)" callout + one summary page listing
  old→new for every headline finding (and link it from PROJECT.md).
- Run the Documenter/Literate docs build so every edited literate page actually executes.

### Process (carried from 26/27)
- Full suite after each wave with NO agent worktrees under `.claude/worktrees/` present during the
  run; ≤3 concurrent Julia executors; executors never edit STATE/ROADMAP; findings → 28-FINDINGS.md.
- Real executable `julia --project=.` verify scripts only.

### Claude's Discretion
- Audit-script implementation language/approach; summary page name/location; figure regeneration
  tooling.

</decisions>

<code_context>
## Existing Code Insights

- `docs/literate/thesis_reproduction_ieee123.jl`, `thesis_reproduction_assumptions.jl`,
  `socp_applicability.jl`, `restricted_branch_flow.jl`, `ac_oracle.jl`, `mpc_rolling_horizon.jl`,
  `pricing_dlmp.jl`; `scripts/repro_stability_check.jl`, `scripts/demo_mpc_plots.jl`;
  `results/thesis_caseA/*.pdf`; `docs/writeups/`.
- Audit sources: `.planning/phases/26-*/26-GOLDEN-AUDIT.md`, `.planning/phases/27-*/27-GOLDEN-AUDIT.md`,
  26-/27-FINDINGS.md.
- Memory: v2.1 thesis repro = sign flip yes, +25% magnitude no; knife-edge now thesis_literal-only.

</code_context>

<specifics>
## Specific Ideas

- Headline numbers known to have moved: IEEE-13 h16 DADP 1.402→0.394, |V₉[16]| 1.0436→1.0360, FIT
  ratio 0.643→0.772, exporter surplus 65.6→47.4, EXACT-04 SOCP −921.754 (default) vs AC −921.277.

</specifics>

<deferred>
## Deferred Ideas

- Removal of deprecated DLMP aliases — Phase 36.
- App. C η<1 complementarity treatment — unscheduled backlog.

</deferred>
