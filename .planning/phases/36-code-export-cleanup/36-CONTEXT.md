# Phase 36: Code & Export Cleanup - Context

**Gathered:** 2026-10-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Close HYG-01, HYG-02, HYG-03, HYG-07: source comments/docstrings carry no planning IDs (CI grep guard
enforces it; thesis-equation and literature references stay); the inert SEAM-01 stubs and the
reactive-mode Bool/Symbol shim are removed; the export list is trimmed with generic names namespaced
or unexported and an accurate top-module docstring; test fixtures and tags are named after content.

Pure cleanup: NO behaviour change. Every golden and the knife-edge canary (iters = 56,
welfare = -4823.66604824162) bit-identical; NO golden re-pinned. Out of scope: `.planning/` artifacts,
JET/CI fast-slow split/flakes/scripts index (Phase 37).

</domain>

<decisions>
## Implementation Decisions

### Planning-ID scrub (HYG-01)
- Scope: `src/`, `ext/`, `test/`, `scripts/`, `docs/literate/` (~5,300 matching lines; src 80/80 files,
  test 108/110). The CI guard covers the same scope.
- Rewrite, don't just delete: each comment keeps its rationale in plain prose with the ID removed;
  delete only when the ID was the whole content. Thesis-equation refs (e.g. "(3.31)", "eq. 3.4x") and
  literature refs are never touched; the ~19 lines mixing a thesis ref with a planning ID are
  hand-edited.
- Rename internal constants `MEASURED_ε_FIX08` → `MEASURED_REL_TOL_EXACT` and `TAU_SOLVER_FIX08` →
  `TAU_SOLVER_EXACT` (non-exported; ~19 uses in src/test/scripts). Values unchanged.
- Guard: `.github/scripts/check_planning_ids.py` (alongside `check_content_loss.py`) invoked in the CI
  format job; regex over ID patterns (Phase N, NN-NN plan refs, D-NN, FIX/ARCH/CR/WR/IN/PM-NN,
  BILEV/MESH/SCALE/SEAM/DATA/INFRA/PF/HYG-, Wave N, Task N, T-NN-NN, 260xxx-yyy quick IDs, `_FIXNN`)
  plus the words "byte-identical" and "Pitfall N"; small allowlist file for unavoidable cases; runnable
  locally. Excludes `.planning/`.

### Stub & shim removal (HYG-02)
- Remove `operational_oracle`'s `objective_hook`, `horizon_state` and `z` kwargs entirely (unknown-kwarg
  MethodError thereafter); remove `_coupling_dual`'s `z` throw path; delete the stub-kwarg tests and the
  two `z` `@test_throws` in `test/test_oracle.jl`; clean the referencing comments
  (`stochastic_welfare.jl`, `PVBattery.jl`).
- Remove the Bool and Symbol methods of `normalize_reactive_mode`; only the `ReactiveMode` enum is
  accepted; anything else → `ArgumentError` naming the valid values. Migrate the ~35 test/fixture/script
  call sites to the enum form.
- Pure removal: all goldens + canary unchanged, full suite green.
- Record breaking removals in a "Breaking changes" note in the docs (status/API page) and the SUMMARY.

### Export trim (HYG-03)
- `LP/QP/SOCP/NLP/MILP` problem-class singletons: unexported, names kept (`TSODSO.SOCP()`), declared
  public via `Compat.@compat public` (works on the 1.10 compat floor); migrate ~120 test/docs/script
  uses (qualified or explicit `using TSODSO: SOCP` in test setup).
- `ReactiveMode` enum: scoped in a module → `ReactiveMode.OFF/CERTIFIED/LIVE`; export `ReactiveMode`
  only; bare `OFF`/`LIVE`/`CERTIFIED` no longer in the namespace.
- `record!`/`converged`: unexported (internal ADMM/MPC trace helpers). Full audit of the 199 exported
  names: keep researcher-facing API (entry points, feeders/data, device & model types, results/error
  types, solver factory, power-flow selectors); make internals non-exported (mark useful advanced ones
  `public`); fix the 4 names exported from multiple files (`record!`, `set_rho!`, `set_rho_q!`,
  `solve_follower!`).
- Rewrite the stale `src/TSODSO.jl` top-module docstring to describe the module as it is now.
- Gates: Aqua `test_all` (undefined exports) green; docs build with `checkdocs = :exports` green.

### Fixture/tag renames & sequencing (HYG-07)
- Fixture files/modules renamed after content (planner produces a mapping table from each file's
  actual contents, e.g. `fixtures_phase6.jl`/`Phase6Fixtures` → content name); `git mv` to keep history;
  update all ~46 `setup=[...]` users and docs prose references; regenerate affected docs pages.
- Tags `:phase7` / `:phase25` → content tags (`:ieee123` / `:ieee8500` / `:admm` as fits); confirm no CI
  filter depends on the old tags (`scripts/run_tests_filtered.jl tag:` users updated).
- Order: (1) stub/shim removal → (2) export trim → (3) fixture/tag renames → (4) ID scrub last, across
  every touched file → (5) CI guard, fail-closed. Full suite after each wave, sequential on main tree;
  canary checked each time.
- `.planning/` out of scope; guard excludes it.

### Claude's Discretion
- Exact content names for fixtures/modules; exact keep/unexport classification of the 199 exports
  (documented in the plan); guard regex details and allowlist entries; wording of rewritten comments.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/scripts/check_content_loss.py` (existing CI script pattern); `.github/workflows/CI.yml`
  (tests, format-check, docs jobs).
- `scripts/run_tests_filtered.jl` (`tag:<sym>` / `file:<basename>` runner).

### Established Patterns
- Exports are spread over 82 `export` statements in 76 files (199 unique names); `src/TSODSO.jl`
  itself exports nothing.
- `@enum ReactiveMode` at `src/admm/ReactiveMode.jl:45` (export :89); `normalize_reactive_mode`
  methods Bool :60, ReactiveMode :64, Symbol :68, fallback :80; callers `AgrOpt.jl:129`,
  `DsoOpt.jl:285`, `solve_admm.jl:311`.
- Problem classes: singletons `<: ProblemClass` in `src/solver/ProblemClass.jl:21-46` (export :81).
- `operational_oracle` kwargs at `src/models/oracle.jl:96-99`, docs :72-79, debug :112-120;
  `_coupling_dual` z-throw :162-177.
- Fixtures: `test/fixtures_phase{3,4,6,7,8,19,21,22,23}.jl` as `@testmodule PhaseNFixtures`, used via
  `setup=[...]` in 46 files. Tags `:phase7` (16), `:phase25` (10) in 8 files.
- Docs: `docs/src/api.md` `@docs TSODSO` + ~14 `@autodocs` (Pages=-selected, include non-exported);
  `docs/make.jl` `checkdocs = :exports`, missing_docs fatal.
- Aqua `test_all(TSODSO)` in `test/test_toy_dc.jl:30-35`.

### Integration Points
- Thesis refs ~257 lines in src (keep). JuliaFormatter docstring data-loss hazard (STATE.md) — run
  `check_content_loss.py` after comment rewrites.

</code_context>

<specifics>
## Specific Ideas

- Memory notes: `background-suite-orphan-race` (sequential suites, no worktree contamination),
  `gsd-plan-verify-testitemrunner-trap`, `testitem-try-scoping-trap`, `local-project-toml-drift`.

</specifics>

<deferred>
## Deferred Ideas

- JET in CI, `:slow` split, flakes, scripts index, root Manifest — Phase 37.

</deferred>
