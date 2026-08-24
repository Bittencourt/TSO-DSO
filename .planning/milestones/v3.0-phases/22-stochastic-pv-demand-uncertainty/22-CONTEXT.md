# Phase 22: Stochastic PV/Demand Uncertainty - Context

**Gathered:** 2026-08-09
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all three grey-area tables accepted as recommended

<domain>
## Phase Boundary

A researcher can solve a two-stage extensive-form welfare problem over a small seeded scenario set
(3–5 seeded Markov scenarios, explicit probabilities), with per-scenario DADPs as the primary,
honestly-documented price output — the probability-weighted expectation only a derived summary.
Includes an out-of-sample validation harness (held-out scenarios, realized-vs-in-sample welfare
gap, measurement-before-golden) and a live-executed literate rung page. Requirements:
STOCH-01..04. Depends on Phase 21 (reuses the coordinated `Scenario.jl` schema extension and the
`Parameter`-pinned convention).

</domain>

<decisions>
## Implementation Decisions

### Extensive-Form Architecture
- **D-01:** **One monolithic scenario-indexed JuMP model** solved by Clarabel (CLAUDE.md's
  "extensive form first" prescription; criterion 1's "within measured capacity"). Lagrangian/PH
  decomposition explicitly deferred.
- **D-02:** The builder lives in a **new sibling module** (e.g. `src/models/stochastic_welfare.jl`,
  name at Claude's discretion). The SEAM-01 `objective_hook` stub cannot express per-scenario
  duplication of network + devices (it only transforms the objective) — document this honestly as
  the SEAM-01 resolution note. REQUIREMENTS explicitly allows the sibling-orchestrator route.
- **D-03:** First-stage vs recourse split: **battery schedule (and deferrable commitments) are
  first-stage (shared across scenarios); network flows, imports, and thermostatic response are
  per-scenario recourse.** Research may refine the exact split within this framing (battery
  first-stage and network recourse are fixed).
- **D-04:** **Explicit probabilities kwarg, default uniform**; the CI fixture must use non-uniform
  probabilities to prove the weighting plumbing.

### Price Semantics & Gating (STOCH-02)
- **D-05:** Per-scenario DADP = the dual of scenario s's own nodal balance, **de-scaled by its
  probability p_s** (in a probability-weighted objective the raw dual is p_s-scaled), restoring
  the standard price interpretation per scenario. Derivation documented in the docstring.
- **D-06:** **PF-04 exactness gate per scenario block** — each scenario's cone checked separately
  (assert_socp_exact!-family), never aggregated.
- **D-07:** The probability-weighted expected price is a **derived summary field with an
  unmistakable name and docstring caveat** — never presented as a constraint-backed price
  primitive.
- **D-08:** **Degenerate reduction regression:** a 1-scenario extensive form must reproduce the
  deterministic `solve_welfare` result (welfare + DADPs within solver tolerance). CI-gated.

### Out-of-Sample Harness & Evidence (STOCH-03/04)
- **D-09:** Held-out evaluation **Parameter-pins the first-stage decisions** (Phase-21 build-once
  convention) and solves recourse-only per held-out scenario; reports realized-vs-in-sample
  welfare gap.
- **D-10:** Held-out scenario budget at Claude's discretion within a small seeded budget
  (e.g. 5–10, seeds disjoint from in-sample); CI keeps a cheap subset, fuller sweep quarantined.
- **D-11:** **Measurement-before-golden** (v2.1 pattern, locked): repeated-run stability check
  before pinning any golden.
- **D-12:** **Small radial CI fixture** (Phase-19/20/21 precedent); the 3–5-scenario IEEE-13
  demonstration lives in the literate page / quarantined evidence, not CI.

### Claude's Discretion
- Module/struct/function/kwarg names (builder, result struct, probability kwarg, harness entry).
- Exact scenario counts within the locked bands (3–5 in-sample, 5–10 held-out).
- Whether deferrable commitments join the battery in first-stage (D-03 allows refinement).
- Result-struct shape, provided per-scenario DADPs are primary and the expectation clearly derived.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- SEAM-01 `objective_hook` stub — src/models/oracle.jl:27,98,112 (inert; D-02 documents why a
  sibling builder supersedes it).
- Seeded Markov profile generator — src/data/profiles.jl (DATA-04 seam; generates the scenarios).
- `Scenario` schema with Phase-21's mpc_* additive-field precedent — src/experiments/Scenario.jl
  (add stoch_* fields the same additive @kwdef way; savename string change accepted per Phase-21
  research resolution; numeric reproducibility is the bar).
- Phase-21 Parameter conventions: device Parameter handles (anonymized containers — see
  21-01/21-05 summaries), build-once re-solve, num_variables/num_constraints invariance idiom.
- solve_welfare (src/models/welfare_solve.jl) — the deterministic core each scenario block
  replicates; the degenerate reduction test anchors against it.
- Certificate family + per-scenario gating patterns (src/models/exactness.jl).
- Literate page pattern: docs/literate/mpc_rolling_horizon.jl (Rung 8) is the freshest example.

### Established Patterns
- Additive @kwdef Scenario fields with defaults; never new run_scenario strategy dispatch without
  need — Phase 21 gave run_mpc its own entry point; mirror with e.g. run_stochastic.
- Quarantined expensive evidence vs CI-gated cheap evidence.
- Docs: every new exported symbol wired into docs/src/api.md (checkdocs=:exports blocking).

### Integration Points
- New builder consumes feeder + aggregators + scenario profile sets; produces scenario-indexed
  model + result struct with per-scenario DADPs.
- Out-of-sample harness reuses the builder with first-stage Parameters pinned.
- docs/make.jl literate list + api.md.

### Testing constraints (Phases 19-21 lessons — MANDATORY for plans)
- Plans' <verify> blocks: direct Julia/Test.jl scripts under `--project=.` ONLY. NEVER
  TestItemRunner under --project=. ; never bare include() of @testitem files.
- Full suite: `julia --project=. -e 'import Pkg; Pkg.test()'` (~12-20 min, background), reserved
  for the final acceptance plan. Green reference after Phase 21 fixes: 2685 passed / 0 real
  failures / 3 pre-existing broken (+2 known-false Aqua drift failures on the drifted main
  checkout; +3 intermittent pre-existing Clarabel NUMERICAL_ERROR errors in test_experiments.jl).
- Extensive forms multiply model size by scenario count — keep the CI fixture SMALL and measure
  Clarabel capacity before committing fixture sizes (criterion 1's "measured capacity").

</code_context>

<specifics>
## Specific Ideas

- The 1-scenario degenerate reduction (D-08) is the anchor: any scenario-index plumbing bug shows
  up as a mismatch against the already-validated deterministic solve.
- Per-scenario price de-scaling (D-05) must be cross-checked on the degenerate case: with p=1 the
  de-scaled dual equals the deterministic DADP exactly.
- The literate page should show the per-scenario DADP spread visually alongside the expectation
  summary, making "prices are per-scenario duals" concrete.

</specifics>

<deferred>
## Deferred Ideas

- Lagrangian/progressive-hedging scenario decomposition (DualDecomposition.jl evaluation) — later
  milestone per CLAUDE.md.
- Multi-stage (>2) scenario trees and horizon-decaying forecast composition with Phase 21 — later.
- Risk measures (CVaR etc.) on the objective — out of this rung.
- InfiniteOpt.jl continuous random-domain formulation — evaluation deferred per CLAUDE.md.

</deferred>
