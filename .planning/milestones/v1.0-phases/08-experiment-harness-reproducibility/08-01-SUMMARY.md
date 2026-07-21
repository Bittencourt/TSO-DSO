---
phase: 08-experiment-harness-reproducibility
plan: 01
subsystem: infra
tags: [drwatson, csv, dataframes, testitems, testitemrunner, reproducibility, include-graph, jld2]

# Dependency graph
requires:
  - phase: 07-admm-convergence-scale
    provides: solve_admm (ConvexBranchFlow ADMM) + residual traces the harness will run
  - phase: 05-distribution-pricing-dadp-dlmp-decomposition
    provides: extract_dlmp / DADP extraction the harness surfaces per scenario
  - phase: 04-convex-branch-flow-correctness-milestone
    provides: solve_welfare (centralized SOCP ground truth) the harness dispatches to
provides:
  - "Hard [deps] DrWatson 2.19.1 / CSV 0.10.16 / DataFrames 1.8.2 (root + test env) with re-resolved committed manifests on Julia 1.10/1.11/1.12"
  - "Two-tier storage split: data/ (gitignored, binary JLD2 per-run artifacts) vs results/ (committed, diff-friendly CSV)"
  - "src/experiments/ include-graph: five comment-only stubs (Scenario -> materialize -> run -> store -> sweep) wired into TSODSO.jl after admm/ + diagnostics/"
  - "Complete RED @testitem harness (test/test_experiments.jl) + @testmodule Phase8Fixtures asserting the final EXP-01/EXP-02/INFRA-04 contract"
affects: [08-02, 08-03, 08-04, 09-documentation-regression-acceptance-gate]

# Tech tracking
tech-stack:
  added: [DrWatson, CSV, DataFrames]
  patterns:
    - "RED-then-green testitem harness with isdefined() guards (Phase-6 test_admm.jl precedent)"
    - "Wave-0 single-owner of shared files so downstream waves stay file-disjoint / parallel-safe"
    - "Two-tier storage: data/ gitignored (binary), results/ committed (diffable)"

key-files:
  created:
    - src/experiments/Scenario.jl
    - src/experiments/materialize.jl
    - src/experiments/run.jl
    - src/experiments/store.jl
    - src/experiments/sweep.jl
    - test/fixtures_phase8.jl
    - test/test_experiments.jl
    - results/sweeps/.gitkeep
  modified:
    - Project.toml
    - test/Project.toml
    - Manifest.toml
    - Manifest-v1.10.toml
    - Manifest-v1.11.toml
    - Manifest-v1.12.toml
    - test/Manifest.toml
    - .gitignore
    - src/TSODSO.jl

key-decisions:
  - "DrWatson/CSV/DataFrames added as hard [deps], not weakdeps — the harness (provenance + repro) needs them unconditionally; JLD2/FileIO arrive transitively via DrWatson (not added explicitly)."
  - "Stubs are comment-only and wired in dependency order after admm/ + diagnostics/ so run_scenario orchestrates already-validated Phase 1-7 builders; no earlier source file is modified."
  - "Test harness asserts the FINAL intended API and is guarded by isdefined() — later waves go green by landing source, never by editing test_experiments.jl."

patterns-established:
  - "Wave-0 foundation owner: exactly one plan touches shared files (Project.toml, manifests, TSODSO.jl, test harness), isolating parallel waves."
  - "RED @testitem harness with isdefined() guards: missing symbol => clean fail, runner stays stable."
  - "Two-tier storage: data/ gitignored binary, results/ committed diffable."

requirements-completed: [EXP-01, EXP-02, INFRA-04]

# Metrics
duration: ~20min
completed: 2026-07-19
---

# Phase 08, Plan 01: Experiment-Harness Foundation Summary

**DrWatson/CSV/DataFrames hard deps + re-resolved 1.10/1.11/1.12 manifests, two-tier data/results storage, the src/experiments/ include-graph scaffold, and a RED @testitem harness (Phase8Fixtures) that pins the full EXP-01/EXP-02/INFRA-04 contract.**

## Performance

- **Duration:** ~20 min (across two atomic commits)
- **Completed:** 2026-07-19
- **Tasks:** 2
- **Files modified/created:** 17

## Accomplishments
- Added DrWatson 2.19.1 / CSV 0.10.16 / DataFrames 1.8.2 as hard `[deps]` (+ `[compat]` pins) to root and test environments; re-resolved and committed all five manifests (Manifest.toml + Manifest-v1.10/1.11/1.12.toml + test/Manifest.toml).
- Established the two-tier storage split: `/data/` gitignored (binary JLD2 per-run artifacts), `results/sweeps/` committed with `.gitkeep` (diff-friendly CSV) — set up before any artifact is written.
- Wired five comment-only `src/experiments/` stubs into `TSODSO.jl`'s include graph in dependency order (Scenario → materialize → run → store → sweep), after `admm/` and `diagnostics/`. `using TSODSO` loads clean.
- Stood up the complete RED `@testitem` harness plus `@testmodule Phase8Fixtures` — 8 testitems covering EXP-01 (centralized/admm/strategy-guard), EXP-02 (sweep/diff-friendly), INFRA-04 (same-seed repro/seed-sensitivity/provenance-tagsave), each behind an `isdefined()` guard.

## Task Commits

1. **Task 1: hard deps + re-resolved manifests + two-tier storage dirs** — `639baa2` (feat)
2. **Task 2: wire experiments/ include-graph stubs + RED @testitem harness** — `b23c2d9` (feat)

## Files Created/Modified
- `Project.toml` / `test/Project.toml` — DrWatson/CSV/DataFrames `[deps]` + `[compat]` pins
- `Manifest.toml`, `Manifest-v1.10/1.11/1.12.toml`, `test/Manifest.toml` — re-resolved, committed (INFRA-01 reproducibility)
- `.gitignore` — `/data/` ignored (binary JLD2 artifacts); manifests intentionally NOT ignored
- `results/sweeps/.gitkeep` — committed diffable-results dir
- `src/TSODSO.jl` — five `include("experiments/*.jl")` after admm/ + diagnostics/
- `src/experiments/{Scenario,materialize,run,store,sweep}.jl` — comment-only stubs (filled by 08-02/03/04)
- `test/test_experiments.jl` — RED @testitem suite (final-API assertions, isdefined-guarded)
- `test/fixtures_phase8.jl` — `@testmodule Phase8Fixtures` (minimal Scenario spec + mktempdir helper)

## Decisions Made
- **Hard deps, not weakdeps** — the harness needs DrWatson/CSV/DataFrames unconditionally; JLD2/FileIO come in transitively via DrWatson (not added explicitly).
- **Stubs orchestrate, never re-implement** — includes go after admm/ + diagnostics/ so `run_scenario` calls the validated Phase 1-7 builders; no earlier source file touched, keeping Waves 2-4 file-disjoint.
- **Harness asserts final API + guarded** — `isdefined(TSODSO, :symbol)` guards mean a missing symbol is a clean test failure, not a runner crash; later waves go green by landing source, never by editing the harness.

## Deviations from Plan
None - plan executed as written. Two-task structure preserved; each task committed atomically per the plan's wave design.

## Issues Encountered
A stale git worktree (`.claude/worktrees/agent-ac2dd9858a99eaab7`) left by a prior parallel agent held an *earlier, less-complete draft* of this same 08-01 work. Because `@run_package_tests` walks the package root recursively, it was double-discovering `test_experiments.jl` from that copy. Confirmed the worktree's commit + files were strictly superseded by the main tree (older mtimes, smaller stubs), then removed the worktree and deleted its branch. Test discovery is now single-source; no unique work lost.

## Validation
- `using TSODSO` loads clean with all five stub includes present.
- Phase-8 harness runs to completion: **15 clean `@test` failures, 0 errors, 0 passes** — every failure is the intended `isdefined()` guard (`:Scenario` / `:run_scenario` / `:run_and_store`). Runner stays stable (RED-by-design).
- `grep -c 'include("experiments/' src/TSODSO.jl` == 5; `/data/` gitignored; `results/sweeps/.gitkeep` tracked; both storage dirs exist.

## Next Phase Readiness
- **08-02** (Scenario + materialize): implement `Scenario` struct (primitive selectors, construction-time strategy/feeder/price/population guards) and `materialize` (selectors + seed → feeder/λ₀/aggregators) → turns EXP-01 scenario-construction + INFRA-04 seed testitems green.
- **08-03** (run): implement `ScenarioResult` + `run_scenario` strategy dispatch → EXP-01 centralized/admm green.
- **08-04** (store + sweep): implement `run_and_store` (@tagsave provenance) + `run_sweep`/`collate_summary` (dict_list → diff-friendly CSV) → EXP-02 + INFRA-04 provenance green.
- All three are file-disjoint from this wave and from each other by construction; the harness is the target contract and must NOT be edited to go green.

---
*Phase: 08-experiment-harness-reproducibility*
*Completed: 2026-07-19*
