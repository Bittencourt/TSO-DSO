# Phase 8: Experiment Harness & Reproducibility - Context

**Gathered:** 2026-07-19
**Status:** Ready for planning
**Mode:** Auto-generated (tooling/infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Make experiments **first-class**: a researcher declares a scenario **declaratively** (feeder + devices
+ price profile + config), runs it **end-to-end with EITHER the centralized (Phase-4 SOCP) or the ADMM
(Phase-6/7) solve strategy**, sweeps parameters over scenarios storing results in a **flat, versioned,
diff-friendly format**, and every run **records its inputs/config/environment (seed logged) so results
regenerate bit-for-bit** on the open-source (Clarabel/HiGHS/Ipopt) solver path.

In scope: EXP-01 (declarative scenario → end-to-end run with a swappable solve strategy), EXP-02
(parameter sweeps + flat/versioned/diff-friendly results storage), INFRA-04 (per-run provenance:
inputs, config, environment, seed → bit-for-bit reproducibility). Out of scope: the documentation gate
+ literate experiment pages (Phase 9 — this phase builds the harness those pages USE), the planning
layer (later milestone).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to CLAUDE.md tooling + Phases 1–7 seams)
No user-preference grey areas — the harness follows CLAUDE.md's explicit tooling choices. Anchor to:

- **DrWatson.jl (CLAUDE.md — the reproducibility backbone):** `@produce_or_load`, `savename`,
  `tagsave` (stamps git commit + Manifest into results), `collect_results` for sweep aggregation.
  Adopt as the experiment/scenario manager. A `Scenario` struct (feeder + devices/aggregators +
  price profile + config incl. seed + solve-strategy selector) that DrWatson can `savename`/hash.
- **Declarative scenario + swappable strategy (EXP-01):** a `Scenario` is a plain declarative
  spec; `run_scenario(scenario)` dispatches to the centralized `solve_welfare`/`operational_oracle`
  OR the ADMM `solve_admm` via a strategy selector (e.g. `strategy = :centralized | :admm`), reusing
  the validated builders — the harness is orchestration, no new models. Returns a result record
  (welfare, DADP, iters/residuals for ADMM, exactness certificate, timings).
- **Parameter sweeps + flat storage (EXP-02):** `dict_list`-style sweep over scenario parameters;
  results stored in a **flat, versioned, diff-friendly format** — CSV + DataFrames for the tabular
  sweep collation (CLAUDE.md CSV.jl/DataFrames.jl), DrWatson `savename`/`tagsave` for per-run
  artifacts. Diff-friendly = deterministic key ordering, text/CSV not opaque binary for the summary
  tables.
- **Reproducibility / provenance (INFRA-04):** every run records inputs + config + environment +
  SEED (the StableRNGs seed threaded through profile generation) via DrWatson `tagsave` (git commit +
  Manifest stamp) so a run regenerates **bit-for-bit** on the open-source solver path. A test asserts
  same-seed → identical result (reusing the DATA-04 reproducibility guarantee end-to-end through the
  solve).
- **Solver/status discipline (CLAUDE.md):** open-source path (Clarabel/HiGHS/Ipopt) via
  `select_optimizer`; `assert_solved!` + PF-04 exactness on the SOCP path; no model names a solver.
- **DrWatson project layout:** adopt DrWatson's `@quickactivate`/project structure conventions where
  they fit a package (keep the harness inside `src/experiments/` and put runnable scenarios/sweeps in
  a `scripts/` or `experiments/` dir DrWatson manages) — research to confirm the package-vs-project fit.

### New dependencies
This phase adds **DrWatson.jl**, **CSV.jl**, **DataFrames.jl** (all in the CLAUDE.md recommended stack,
pinnable). Flag them; re-resolve the version-specific manifests (main + test) on 1.10/1.11/1.12.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–7)
- `src/models/welfare_solve.jl` + `src/models/oracle.jl` (centralized strategy), `src/admm/solve_admm.jl`
  (ADMM strategy) — the two solve strategies the harness dispatches over.
- `src/data/{ieee13,ieee123}.jl` + `Feeder.jl` (feeders), `src/devices/*` + `Aggregator.jl`,
  `src/data/profiles.jl` (seeded price/demand/PV — the seed the harness logs), `src/pricing/*`
  (DADP/decomposition/welfare the harness reports), `src/models/exactness.jl` (PF-04 certificate).
- `src/solver/factory.jl` (open-source `select_optimizer`), the committed version-specific manifests
  (the reproducibility environment DrWatson `tagsave` stamps).

### Established Patterns
- Immutable declarative structs; seeded StableRNGs reproducibility; committed manifests; TestItems
  `@testitem` (name contains filter substring); throw-based validation; weakdep extensions for heavy
  optional deps (the CairoMakie pattern — consider whether DrWatson/CSV/DataFrames are hard deps or
  test/experiment-only; DrWatson is the harness core so likely a hard dep, CSV/DataFrames too).

### Integration Points
- New `src/experiments/` (Scenario struct, run_scenario strategy dispatch, sweep + collation, DrWatson
  provenance/tagsave wrappers); a `scripts/`/`experiments/` dir for runnable scenario/sweep entry
  points; the new [deps] (DrWatson/CSV/DataFrames) + manifest re-resolution.

</code_context>

<specifics>
## Specific Ideas

Pull the DrWatson.jl idioms (`@produce_or_load`, `savename`, `tagsave` with git+Manifest stamping,
`dict_list` for sweeps, `collect_results`) and the recommended package-vs-project structure from the
DrWatson docs during research (re-verify the current API surface via Context7/docs). Design the
`Scenario` schema so it fully determines a run (feeder + devices + price profile + seed + strategy +
config) and DrWatson can `savename`/hash it. The bit-for-bit reproducibility test (same seed →
identical result through the full solve) is the load-bearing INFRA-04 gate. Confirm DrWatson/CSV/
DataFrames pins and re-resolve manifests on 1.10/1.11/1.12. Keep the results format flat + diff-friendly
(CSV summary tables; deterministic ordering).

</specifics>

<deferred>
## Deferred Ideas

- Literate/Documenter experiment pages that USE the harness → Phase 9.
- Publication figures beyond the Phase-7 ADMM diagnostics (CairoMakie) → Phase 9.
- Stochastic / rolling-horizon scenario families → later milestone.

</deferred>
