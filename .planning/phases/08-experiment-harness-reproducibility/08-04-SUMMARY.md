---
phase: 08-experiment-harness-reproducibility
plan: 04
subsystem: infra
tags: [drwatson, tagsave, jld2, dict_list, collect_results, csv, dataframes, provenance, reproducibility]

# Dependency graph
requires:
  - phase: 08-experiment-harness-reproducibility
    plan: 03
    provides: ScenarioResult + run_scenario strategy dispatch (:centralized/:admm), PATH-FREE
  - phase: 08-experiment-harness-reproducibility
    plan: 01
    provides: two-tier storage split (data/ gitignored, results/sweeps/ committed) + include-graph stubs
provides:
  - "run_and_store(s; dir=datadir(\"sims\")): @tagsave's a per-run JLD2 stamped with :gitcommit/:gitpatch/:script + :julia_version + :seed (INFRA-04 provenance)"
  - "run_sweep(params; dir): dict_list-expands scenario params into Scenarios and run_and_store's each"
  - "collate_summary(dir, csvpath): collect_results -> fixed-column, deterministically-sorted, :path-free CSV (keeps :gitcommit); two collations byte-identical"
  - "scripts/run_scenario.jl + scripts/sweep.jl: @quickactivate \"TSODSO\" runnable entry points"
affects: [09-documentation-regression-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@tagsave gitpath pinned to pkgdir(@__MODULE__), never the projectdir() default — reliable under both a plain script run and Pkg.test()'s sandboxed temp environment"
    - "collect_results' black_list override must use String entries, not Symbol — collect_results reads on-disk JLD2 dict keys, which JLD2/FileIO always round-trips as String regardless of what was passed to @tagsave"
    - "DrWatson.collect_results is Requires-gated (fires only once DataFrames loads); reference it fully-qualified inside a function body, never via a restricted `using DrWatson: collect_results` at file-load time"

key-files:
  created:
    - scripts/run_scenario.jl
    - scripts/sweep.jl
  modified:
    - src/experiments/store.jl
    - src/experiments/sweep.jl
    - test/test_experiments.jl

key-decisions:
  - "[Rule 1 - Bug] wload on a .jld2 always returns String-keyed dicts (JLD2's generic FileIO save/load stores every key as a variable NAME, converting Symbol keys with a warning) — fixed the INFRA-04 provenance testitem's Symbol-keyed haskey assertions to String keys; the provenance intent (gitcommit/julia_version/seed survive the round-trip) is unchanged."
  - "[Rule 1 - Bug] collect_results' own default black_list already excludes :gitcommit (alongside :gitpatch/:script) and is Symbol-typed, but on-disk keys are String — passing black_list=[\"gitpatch\",\"script\"] (String) is what actually keeps :gitcommit in the collated DataFrame."
  - "[Rule 1 - Bug] Avoided a precompile-time race on DrWatson.collect_results (Requires-gated, not statically declared until DataFrames loads) by using a plain `import DrWatson` + fully-qualified DrWatson.collect_results(...) call at runtime inside collate_summary, instead of a restricted `using DrWatson: collect_results` at file scope."
  - "[Rule 1 - Bug] @tagsave's default gitpath=projectdir() resolves to Pkg.test()'s temporary sandbox directory (not a git repo), silently skipping the :gitcommit stamp under `Pkg.test()`. Pinned gitpath=pkgdir(@__MODULE__) in run_and_store so the stamp is reliable both in normal use and under Pkg.test()."

patterns-established:
  - "Storage/collation functions never rely on projectdir()/datadir() defaults for git-repo discovery inside @tagsave — pin gitpath explicitly to pkgdir(@__MODULE__)."

requirements-completed: [EXP-02, INFRA-04]

# Metrics
duration: ~40min
completed: 2026-07-20
---

# Phase 08, Plan 04: Storage + Sweep — @tagsave Provenance + Diff-Friendly CSV Summary

**`run_and_store` @tagsave's a gitignored per-run JLD2 stamped with git commit + Julia VERSION + seed; `run_sweep`/`collate_summary` turn a `dict_list` parameter sweep into a byte-stable, fixed-column, `:path`-free CSV — completing the Phase-8 experiment harness with two `@quickactivate` runnable scripts.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-07-20T00:46:59Z
- **Completed:** 2026-07-20T01:27:09Z
- **Tasks:** 2
- **Files modified/created:** 5 (`src/experiments/store.jl`, `src/experiments/sweep.jl`, `test/test_experiments.jl`, `scripts/run_scenario.jl`, `scripts/sweep.jl`)

## Accomplishments
- `result_to_dict(res::ScenarioResult)` (`src/experiments/store.jl`) builds the Symbol-keyed provenance dict (scalar result fields + scenario selectors + `dadp` + `:julia_version => string(VERSION)`); `run_and_store(s; dir=datadir("sims"))` runs the scenario and `@tagsave`s it to a per-run JLD2 named `savename(s,"jld2")`, gitignored, stamped with `:gitcommit`/`:gitpatch`/`:script` (INFRA-04).
- `run_sweep(params; dir)` (`src/experiments/sweep.jl`) expands a `dict_list` (Vector-valued keys sweep, scalars stay fixed) into `Scenario`s and `run_and_store`s each; `collate_summary(dir, csvpath)` reads `collect_results(dir)`, applies all three mandatory diff-friendly rules — fixed explicit column order, deterministic `sort!` by `[:feeder,:strategy,:seed]`, drop the machine-local `:path` column while keeping `:gitcommit` — and `CSV.write`s. Two collations of the same run directory are byte-identical.
- `scripts/run_scenario.jl` and `scripts/sweep.jl`: `@quickactivate "TSODSO"` runnable entry points for a single declarative run and a full parameter sweep + collation into `results/sweeps/`.
- Full `Pkg.test()` after both tasks: **1922 pass, 0 fail, 0 error, 2 broken** (pre-existing, unrelated `@test_broken` items). All Phase-8 target testitems green: "EXP-01 scenario centralized/admm/strategy guard", "EXP-02 sweep"/"EXP-02 sweep diff-friendly", "INFRA-04 same-seed repro"/"seed sensitivity"/"provenance tagsave".

## Task Commits

Each task was committed atomically:

1. **Task 1: run_and_store — @tagsave per-run JLD2 provenance stamp** — `d834ac3` (feat)
2. **Task 2: run_sweep + collate_summary + @quickactivate scripts** — `f9eeaf6` (feat)

## Files Created/Modified
- `src/experiments/store.jl` — filled the 08-01 stub: `result_to_dict` + `run_and_store` (`@tagsave`, `gitpath = pkgdir(@__MODULE__)`), exported.
- `src/experiments/sweep.jl` — filled the 08-01 stub: `run_sweep` + `collate_summary` (diff-friendly CSV via `collect_results`/`select`/`sort!`/`CSV.write`), exported.
- `test/test_experiments.jl` — fixed the "INFRA-04 provenance tagsave" testitem's key-type assertions (Symbol → String) to match verified `wload` round-trip behavior.
- `scripts/run_scenario.jl` (new) — `@quickactivate "TSODSO"` single declarative run + `run_and_store`.
- `scripts/sweep.jl` (new) — `@quickactivate "TSODSO"` full sweep + `collate_summary` into `results/sweeps/`.

## Decisions Made
- Kept `run_scenario` itself untouched and path-free; all persistence lives in `store.jl`/`sweep.jl` exactly as the plan's architecture dictates.
- `collate_summary`'s fixed column list excludes `:dadp` (the full node×T matrix) by design — the committed CSV is a SCALAR summary; the full array stays in the gitignored per-run JLD2.
- Chose `pkgdir(@__MODULE__)` over any hand-rolled git-root lookup for `@tagsave`'s `gitpath` — it is the one API that reliably resolves to the real package source directory regardless of whether the code is running from a plain `--project=.` invocation or Pkg's `Pkg.test()` sandbox.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `wload` always returns String-keyed dicts; the INFRA-04 provenance testitem asserted Symbol keys**
- **Found during:** Task 1 (running the plan's own `<verify>` command for `run_and_store`)
- **Issue:** DrWatson's `wload(f)` on a `.jld2` file delegates to `FileIO.load`, which for the JLD2 format always stores/loads dict keys as `String` variable names — verified live: a `Dict{Symbol,Any}` passed to `@tagsave` round-trips through `wload` as `Dict{String,Any}` (with a `@warn "you passed a key as a symbol..."` at save time). The pre-existing "INFRA-04 provenance tagsave" testitem asserted `haskey(dict, :gitcommit)` etc. (Symbol keys) against the `wload`'d result — an assertion that could never pass regardless of `store.jl`'s implementation, since `Dict{String,Any}` never `haskey`s a `Symbol`.
- **Fix:** Changed the testitem's assertions to String keys (`"gitcommit"`, `"julia_version"`, `"seed"`), documenting the root cause inline. The provenance intent (gitcommit + julia_version + seed survive the `@tagsave`/`wload` round-trip) is unchanged — only the key TYPE of the assertion was wrong.
- **Files modified:** `test/test_experiments.jl`
- **Verification:** `julia --project=. -e '...run_and_store...wload...haskey(dict,"gitcommit")...'` → `INFRA-04 provenance OK`.
- **Committed in:** `d834ac3` (Task 1 commit)

**2. [Rule 1 - Bug] `collect_results`' Symbol-typed `black_list` override silently ignored (on-disk keys are String)**
- **Found during:** Task 2 (building `collate_summary`)
- **Issue:** `collect_results`'s documented default `black_list = [:gitcommit, :gitpatch, :script]` would exclude `:gitcommit` from the collated DataFrame — the plan requires KEEPING `:gitcommit` (the provenance anchor). Attempting to override with `black_list=[:gitpatch, :script]` (Symbol) had NO effect — `collect_results`' internal `to_data_row` keys its `black_list` by the ACTUAL on-disk key type (`String`, same JLD2 round-trip cause as deviation #1), so a Symbol-typed override never matches and both `gitpatch`/`script` stayed in the frame.
- **Fix:** Passed `black_list=["gitpatch", "script"]` (String) — this both keeps `:gitcommit` (never excluded) and correctly drops `gitpatch`/`script` noise columns.
- **Files modified:** `src/experiments/sweep.jl`
- **Verification:** Manual REPL check confirmed `:gitcommit` present, `gitpatch`/`script` absent, in the collated DataFrame before writing `collate_summary`.
- **Committed in:** `f9eeaf6` (Task 2 commit)

**3. [Rule 1 - Bug] Precompile-time race on `DrWatson.collect_results` (Requires-gated symbol)**
- **Found during:** Task 2 (first `using TSODSO` after adding `sweep.jl`'s imports)
- **Issue:** `DrWatson.collect_results`/`collect_results!` are defined only once DrWatson's `Requires`-based `@require DataFrames = "..." begin include("result_collection.jl") end` block fires (DrWatson has not migrated this to native Julia package extensions). A restricted `using DrWatson: dict_list, collect_results, datadir` at file-load time raced that gate during `TSODSO`'s precompilation, producing a `WARNING: Imported binding DrWatson.collect_results was undeclared at import time` during `using TSODSO`.
- **Fix:** Dropped `collect_results` from the restricted import list; added a plain `import DrWatson` (binds the module name without racing any specific symbol) and call `DrWatson.collect_results(...)` fully-qualified INSIDE `collate_summary` — resolved at runtime, well after both `DrWatson` and `DataFrames` (a hard project dep) have loaded.
- **Files modified:** `src/experiments/sweep.jl`
- **Verification:** `using TSODSO` precompiles with zero warnings; `collate_summary` still functions correctly (verified via the plan's Task 2 `<verify>` command).
- **Committed in:** `f9eeaf6` (Task 2 commit)

**4. [Rule 1 - Bug] `@tagsave`'s default `gitpath=projectdir()` resolves to `Pkg.test()`'s sandbox, silently skipping the `:gitcommit` stamp**
- **Found during:** Task 2, running the full `Pkg.test()` suite after Task 1 (a manual REPL check of `run_and_store` had passed, masking this — `Pkg.test()` is the only path that exercises the real sandboxed environment)
- **Issue:** `@tagsave`'s `gitpath` keyword defaults to `DrWatson.projectdir()`, which resolves from the CURRENTLY ACTIVE project. Under `Pkg.test()`, Julia activates a temporary sandbox directory to run the test suite — that directory is NOT a git repository, so `gitdescribe` silently returned `nothing` and `tag!` never added `:gitcommit` at all (confirmed via the `@warn "The directory (...) is not a Git repository..."` DrWatson emits). The real "INFRA-04 provenance tagsave" testitem, run through `Pkg.test()`, failed: `haskey(dict, "gitcommit")` was `false`.
- **Fix:** Pinned `gitpath = pkgdir(@__MODULE__)` in `run_and_store`'s `@tagsave` call — `pkgdir(TSODSO)` always resolves to the actual on-disk package source directory (the real git checkout), regardless of which project is active or how the package was dev-installed/sandboxed.
- **Files modified:** `src/experiments/store.jl`
- **Verification:** Re-ran full `Pkg.test()`: 1921→1922 pass, the one real failure resolved; "INFRA-04 provenance tagsave" now green (6 pass, 1 broken pre-existing sub-assertion unaffected — actually 7/7 pass post-fix, see Validation).
- **Committed in:** `f9eeaf6` (Task 2 commit, alongside the sweep.jl changes since both were discovered/fixed together before the final full-suite confirmation run)

---

**Total deviations:** 4 auto-fixed (all Rule 1 - bugs, all rooted in DrWatson/JLD2's actual key-type and git-path-resolution behavior differing from the RESEARCH's illustrative code examples)
**Impact on plan:** All four fixes were necessary for the plan's own INFRA-04/EXP-02 acceptance criteria to actually hold under real `wload`/`collect_results`/`Pkg.test()` behavior — none change the architecture, storage location, or CSV schema the plan specifies. No scope creep.

## Issues Encountered
None beyond the four deviations documented above — all four were discovered via the plan's own `<verify>` commands and the real `Pkg.test()` run (not hypothetical), and are all narrowly scoped fixes to key-type/git-path handling.

## Validation
Full `Pkg.test()` after both tasks (and all four fixes): **1922 pass, 0 fail, 0 error, 2 broken** (5m33s). `test/test_experiments.jl`: 42 pass, 1 broken-count-adjacent... actually 43 total items pass/broken split as: "EXP-01 scenario centralized" 9/9, "EXP-01 scenario admm" 7/7, "EXP-01 scenario strategy guard" 5/5, "EXP-02 sweep" 3/3, "EXP-02 sweep diff-friendly" 4/4, "INFRA-04 same-seed repro" 5/5, "INFRA-04 seed sensitivity" 3/3, "INFRA-04 provenance tagsave" — all green after the gitpath fix. The 2 pre-existing `@test_broken` items (`test_pricing_welfare.jl`, `test_diagnostics_plot.jl`) are unrelated to this plan (documented in STATE.md as figure-bound/weakdep gaps from Phases 4/5/7).

- `data/` and `results/sweeps/` remain clean after the full test run (no stray artifacts; `.gitkeep` intact).
- `scripts/run_scenario.jl` and `scripts/sweep.jl` exist and `@quickactivate "TSODSO"`.
- Both plan `<verify>` commands pass as written (adjusted only for the JLD2-not-a-direct-dep verify-script detail — used `DrWatson.wload` instead of a bare `using JLD2`, since JLD2 is intentionally a transitive-only dependency per 08-01's design decision).

## Next Phase Readiness
- Phase 08 (experiment-harness-reproducibility) is now feature-complete: `Scenario` → `run_scenario` → `run_and_store`/`run_sweep`/`collate_summary`, with the full EXP-01/EXP-02/INFRA-04 requirement set green.
- Phase 09 (documentation-regression-acceptance-gate) can build Literate/Documenter experiment pages directly on top of `scripts/run_scenario.jl`/`scripts/sweep.jl` and the harness API; no known blockers.
- Advisory note carried into Phase 9: the `wload`/`collect_results` String-key behavior and the `@tagsave` `gitpath`/`Pkg.test()` sandbox interaction (this plan's deviations #1-4) are useful to know if Phase 9 experiment scripts touch provenance dicts directly.

---
*Phase: 08-experiment-harness-reproducibility*
*Completed: 2026-07-20*

## Self-Check: PASSED
- FOUND: src/experiments/store.jl
- FOUND: src/experiments/sweep.jl
- FOUND: scripts/run_scenario.jl
- FOUND: scripts/sweep.jl
- FOUND: test/test_experiments.jl
- FOUND commit: d834ac3
- FOUND commit: f9eeaf6
