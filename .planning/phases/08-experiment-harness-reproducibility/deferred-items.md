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

## WR-02 — sub_seed cross-version hash stability (code-review deferral, needs researcher)

- **Source:** 08-REVIEW.md finding WR-02 (Warning), raised during Phase-8 code review.
- **Issue:** `sub_seed` in `src/experiments/materialize.jl` derives per-component seeds via
  `Base.hash`, whose docstring explicitly disclaims cross-process/cross-Julia-version stability.
  Empirically stable TODAY across Julia 1.10/1.11/1.12, but not a guaranteed contract — a
  long-term risk for the INFRA-04 bit-for-bit reproducibility requirement.
- **Why deferred:** the mechanical fix (SplitMix64/FNV-1a stable hash) was attempted and rolled
  back — it changed derived sub-seeds enough to trip a hard battery-complementarity numerical
  assertion (`τ·Pmax²`) on the pinned fixture (seed=7, T=24, IEEE-13, ADMM ρ=100.0) in BOTH the
  `:centralized` and `:admm` paths. A safe fix requires re-validating/re-tuning the ρ/τ numerical
  defaults against the new seed derivation — a research decision, not a mechanical code-review fix.
- **Action (later, researcher):** choose a stable seed-derivation scheme, then re-tune/re-pin the
  ADMM ρ and battery τ defaults and the golden fixtures against it. Until then the current
  `Base.hash` derivation stands (documented, empirically reproducible on supported Julia versions).
