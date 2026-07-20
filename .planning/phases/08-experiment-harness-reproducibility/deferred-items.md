# Deferred Items — Phase 08 (experiment-harness-reproducibility)

Items discovered during plan execution that are OUT OF SCOPE for the current plan (pre-existing,
not caused by the current task's changes) per the executor's scope-boundary rule. Logged, not
fixed.

## From 08-02 execution (full `Pkg.test()` run, 2026-07-19)

**Aqua "Stale dependencies" test failure** (`test/test_toy_dc.jl` — "quality: Aqua package checks").

- **What:** `Aqua.test_all(TSODSO)`'s `stale_deps` check flags `CSV`, `DrWatson`, `DataFrames` as
  stale (declared in `Project.toml [deps]` but not `using`/`import`ed anywhere reachable from
  `src/TSODSO.jl`'s module body).
- **Why it exists:** these three were added as hard `[deps]` in plan 08-01 (foundation wave) in
  anticipation of the provenance/storage layer (`src/experiments/store.jl` — `@tagsave`,
  `savename`/`datadir` — and `src/experiments/sweep.jl` — `dict_list`/`collect_results`/`CSV.write`/
  `DataFrames`), which are still comment-only stubs. `savename(::Scenario)` (this plan, 08-02) works
  via multiple dispatch on DrWatson's *generic* `savename` function — calling it does NOT require
  `TSODSO` itself to `using DrWatson`, so `Scenario.jl`/`materialize.jl` staying dependency-light
  (per this plan's own acceptance criteria) does not resolve the staleness.
- **Not caused by this plan:** 08-02 touched only `src/experiments/Scenario.jl` and
  `src/experiments/materialize.jl`; neither imports (nor should import) DrWatson/CSV/DataFrames.
  The staleness is intrinsic to 08-01's dependency addition and will resolve naturally once 08-04
  lands `store.jl`/`sweep.jl` with their `using DrWatson`/`using CSV, DataFrames` lines.
- **Expected resolution:** plan 08-04 (store + sweep). No action needed from 08-02 or 08-03.
- **Verification that it's pre-existing, not introduced by 08-02:** `git diff` for this plan's two
  commits (`12fc47e`, `ddd1f25`) touches only `src/experiments/{Scenario,materialize}.jl`; the
  `Project.toml`/`Manifest.toml` dependency additions are unchanged (last touched in 08-01's
  `639baa2`).

## Not a deferred item (confirmed pre-existing, unrelated to Phase 8)

- `test/test_pricing_welfare.jl` (1 `@test_broken`, Phase 5) and `test/test_diagnostics_plot.jl`
  (1 `@test_broken`, Phase 7) — both surfaced in the same full-suite run as pre-existing, already
  `@test_broken`-marked items (not new failures; the full-suite summary reports them under
  "Broken", not "Fail"). Untouched by this plan; no action needed.
