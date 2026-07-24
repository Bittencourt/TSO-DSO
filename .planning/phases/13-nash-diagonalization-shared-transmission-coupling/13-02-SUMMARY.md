---
phase: 13-nash-diagonalization-shared-transmission-coupling
plan: 02
subsystem: planning
tags: [jump, highs, benders, nash-diagonalization, gauss-seidel, cairomakie, transmission-coupling]

# Dependency graph
requires:
  - phase: 13-01-shared-transmission-coupling
    provides: "SharedTransmission/DistributorView/solve_follower!(::DistributorView,...) build-once N-distributor shared corridor (src/planning/coupling.jl)"
  - phase: 11-transmission-follower-benders
    provides: "solve_stackelberg! single-distributor Stackelberg Benders loop (src/planning/benders.jl), extended here with an additive follower keyword"
provides:
  - "solve_stackelberg!'s additive, defaulted `follower` keyword — byte-identical for every Phase 11/12 call site, additionally accepts a DistributorView"
  - "NashTrace: two-level (sweep, distributor) convergence ledger mirroring BendersTrace's shape"
  - "run_nash!: the outer Gauss-Seidel diagonalization loop over N distributors' atomic solve_stackelberg! best-responses, with nested-tolerance guard and fail-loud max_sweeps exhaustion"
  - "plot_nash_convergence: core stub (src/diagnostics/plots.jl) + CairoMakie twin-axis extension method (ext/TSODSOMakieExt.jl)"
affects: [13-03-nash-probe]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Additive, defaulted keyword extension to an existing hardened function (follower = nothing) — mirrors the attempts_out::Union{Nothing,Ref{Int}} precedent for non-breaking Phase-to-Phase API growth"
    - "Outer loop as pure orchestration over an already-hardened inner loop (run_nash! builds NO JuMP model; solve_stackelberg! remains the sole Benders solver, called fresh per best-response)"
    - "Two-level convergence ledger: one row per (sweep, distributor) pair, embedding the inner loop's own summary fields, enabling a single ledger to drive a two-level (outer + inner) convergence plot"

key-files:
  created:
    - src/planning/nash.jl
    - test/test_planning_nash.jl
  modified:
    - src/planning/benders.jl
    - src/TSODSO.jl
    - src/diagnostics/plots.jl
    - ext/TSODSOMakieExt.jl

key-decisions:
  - "follower keyword mutual-exclusivity guard is a hard ArgumentError (not a silent last-one-wins rule) — Claude's Discretion per 13-CONTEXT.md, matching the codebase's existing fail-loud-over-implicit convention"
  - "NashTrace has NO sequential-k push! guard (unlike BendersTrace) since the outer sweep index k legitimately repeats across distributors within one sweep — the natural incrementing key is the row count itself"
  - "run_nash! performs a final optimize!(shared.model) immediately before returning on convergence, so the returned shared object is left in a genuinely solved state for any post-hoc value()/dual() queries a caller might make — not present in the plan's literal action text, added because write_back!'s own bound-pinning dirties the model's solved status (JuMP CachingOptimizer semantics)"

patterns-established:
  - "Two-level convergence ledger (NashTrace) mirroring BendersTrace's shape while documenting the divergences explicitly in the file header, per 13-PATTERNS.md's own convention"

requirements-completed: [NASH-02, NASH-03]

# Metrics
duration: 95min
completed: 2026-07-24
---

# Phase 13 Plan 02: Nash Diagonalization Loop Summary

**`run_nash!` outer Gauss-Seidel diagonalization loop over N distributors' atomic `solve_stackelberg!` best-responses against a shared transmission corridor, with a nested-tolerance guard, a two-level `NashTrace` convergence ledger, and a CairoMakie twin-axis convergence plot — proven convergent on a hand-checked, genuinely congested N=2 fixture (z=[0.6,0.6], x_inv=[0.3,0.3]).**

## Performance

- **Duration:** 95 min
- **Started:** 2026-07-23T21:30:30-03:00
- **Completed:** 2026-07-23T23:05:38-03:00
- **Tasks:** 3 completed
- **Files modified:** 6 (2 created, 4 modified)

## Accomplishments
- `src/planning/benders.jl`: `solve_stackelberg!` gains an additive, defaulted `follower = nothing` keyword — byte-identical behavior for every Phase 11/12 call site; accepts a `DistributorView` (or any object with a `solve_follower!` method) in place of building a fresh `FollowerLP`; mutual exclusivity with a non-empty `follower_kwargs` enforced via `ArgumentError`
- `src/planning/nash.jl`: `NashTrace` (two-level convergence ledger, one row per `(sweep, distributor)` pair, mirroring `BendersTrace`'s shape while documenting three explicit structural divergences) and `run_nash!` (the outer Gauss-Seidel loop: boundary guards including the nested-tolerance guard, fresh `DistributorView` best-response per distributor per sweep, CR-01-parity re-solve, damped/undamped write-back, fail-loud `max_sweeps` exhaustion)
- `src/diagnostics/plots.jl` + `ext/TSODSOMakieExt.jl`: `plot_nash_convergence` core stub (plot-free, threat T-07-01 parity) + CairoMakie twin-axis extension method (outer per-sweep max residual on a log-scaled left axis, inner per-distributor Benders gap trajectory on a right axis)
- `test/test_planning_nash.jl`: 15 new `@testitem`s (34 assertions) — `NashTrace` round-trip/guards, `follower`-keyword additivity + mutual-exclusivity regressions, N=2 congested-equilibrium convergence, nested-tolerance guard, forward/reverse order agreement, a DIRECT intra-sweep write-back timing regression, fail-loud `max_sweeps` exhaustion, damping tolerance, and the `plot_nash_convergence` core-stays-plot-free + CairoMakie-loaded smoke test
- Full test suite (`Pkg.test()`-equivalent, all 2220 items across the whole package) green: 2217 passed, 3 broken (CairoMakie-weakdep-skipped, expected), 0 failed, 0 errored

## Task Commits

Each task was committed atomically:

1. **Task 1: solve_stackelberg!'s additive `follower` keyword + NashTrace ledger** - `189183e` (feat)
2. **Task 2: run_nash! — the outer Gauss-Seidel loop** - `b7cc165` (feat)
3. **Task 3: plot_nash_convergence (core stub + CairoMakie extension method)** - `b59fd52` (feat)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified
- `src/planning/nash.jl` - `NashTrace` (struct, empty constructor, `push!`/`is_converged`/`trace_summary`) + `run_nash!` (outer Gauss-Seidel loop, nested-tolerance guard, damping, fail-loud exhaustion, final re-solve before returning)
- `src/planning/benders.jl` - `solve_stackelberg!`'s new additive `follower = nothing` keyword + mutual-exclusivity guard + docstring update
- `src/TSODSO.jl` - one new `include("planning/nash.jl")` line, after `coupling.jl`, before `diagnostics/plots.jl`
- `src/diagnostics/plots.jl` - `plot_nash_convergence` method-less generic + export
- `ext/TSODSOMakieExt.jl` - `TSODSO.plot_nash_convergence(::NashTrace)` twin-axis CairoMakie method
- `test/test_planning_nash.jl` - 15 `[:planning]`-tagged testitems across all three tasks

## Decisions Made
- The `follower`/`follower_kwargs` mutual-exclusivity guard raises `ArgumentError` (hard fail) rather than a softer "last one wins" rule, per Claude's Discretion (13-CONTEXT.md) — matches this codebase's existing fail-loud convention (e.g., `benders.jl`'s own boundary guards).
- `NashTrace.push!` deliberately has NO sequential-`k` guard (unlike `BendersTrace`), since the outer sweep index legitimately repeats across distributors within one sweep — documented explicitly in the file header as one of three structural divergences from `BendersTrace`.
- `run_nash!` performs one final `optimize!(shared.model)` immediately before returning on convergence — an addition beyond the plan's literal action text, made because `write_back!`'s own bound-pinning (locked behavior from plan 13-01) dirties `shared.model`'s solved status under JuMP's `CachingOptimizer` semantics; without it, any caller querying `value()`/`dual()` on the returned `shared` object would hit a spurious `OptimizeNotCalled()`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Docstring interpolation crash from an unescaped `$` in `run_nash!`'s own docstring**
- **Found during:** Task 2, first test run (package failed to precompile)
- **Issue:** A markdown code span inside `run_nash!`'s docstring (`` `sweep_$k/distributor_$i` ``) triggered Julia's string-interpolation syntax at module-load time (docstrings are ordinary triple-quoted strings), raising `UndefVarError: k not defined in TSODSO` — the ENTIRE package failed to precompile.
- **Fix:** Removed the stray `$` from the docstring's prose (`sweep_k/distributor_i`, no interpolation).
- **Files modified:** `src/planning/nash.jl`
- **Verification:** Package precompiles; full `:planning`-tag suite green.
- **Committed in:** `b7cc165` (Task 2 commit)

**2. [Rule 1 - Bug] `dual()` on a Parameter requires a solved model; `write_back!`'s own bound-pin dirties it**
- **Found during:** Task 2 testitem 7b ("intra-sweep write-back timing")
- **Issue:** `value.(shared.model[:z][1,:])` (a native JuMP `Parameter`) raised `OptimizeNotCalled()` after `write_back!` — JuMP's `Parameter` accessor still routes through the solved-model `MOI.VariablePrimal` path even though a Parameter's own set value is solve-independent.
- **Fix:** Switched to `parameter_value.(...)`, the correct solve-independent accessor for a native JuMP `Parameter`'s own state.
- **Files modified:** `test/test_planning_nash.jl`
- **Verification:** Testitem 7b passes.
- **Committed in:** `b7cc165` (Task 2 commit)

**3. [Rule 1 - Bug] `run_nash!`'s returned `shared` model left in an unsolved state**
- **Found during:** Task 2 testitem 5 ("N=2 Gauss-Seidel converges...")
- **Issue:** `run_nash!` never re-solves `shared.model` after the last distributor's `write_back!` — any post-hoc `value()`/`dual()` query by a caller on the returned `shared` object raised `OptimizeNotCalled()`.
- **Fix:** Added a final `optimize!(shared.model)` immediately before the convergence `return`.
- **Files modified:** `src/planning/nash.jl`
- **Verification:** No more spurious exceptions; `value()` queries on the returned model succeed.
- **Committed in:** `b7cc165` (Task 2 commit)

**4. [Rule 1 - Bug] Plan's literal `dual(shared.model[:capacity][1]) != 0` assertion is mathematically unreliable on a fully-pinned model**
- **Found during:** Task 2 testitem 5, after fix #3 above
- **Issue:** Once `run_nash!` returns, `write_back!` has bound-pinned BOTH distributors' `x_inv[i]` to a single point (lb == ub) and both `z[i,:]` are pinned Parameters — `shared.model` has ZERO remaining degrees of freedom anywhere. HiGHS's presolve reduces this fully-determined LP to an empty problem ("Reduced to empty") and postsolve recovers a valid-but-arbitrary dual assignment among the (degenerate) many that satisfy complementary slackness; verified directly (standalone probe) that this consistently allocates ZERO dual mass to the `capacity` row, regardless of whether `x_inv` sits at its own ceiling or strictly below it, and regardless of HiGHS's presolve setting. This is an inherent LP-duality-degeneracy property of a fully-pinned model, not a defect in `run_nash!`'s logic or `write_back!`'s (already-locked, plan-13-01) design.
- **Fix:** Replaced the dual-based assertion in testitem 5 with a mathematically equivalent, numerically robust check: the pooled capacity constraint holds with EQUALITY (`total_flow ≈ corridor_cap * total_investment`, not slack) at the converged equilibrium — confirming genuine congestion without relying on a fragile degenerate-LP dual.
- **Files modified:** `test/test_planning_nash.jl`
- **Verification:** Testitem 5 passes; the equality check is immune to the degeneracy the literal dual assertion hits.
- **Committed in:** `b7cc165` (Task 2 commit)

**5. [Rule 1 - Bug] TestItemRunner top-level scoping: `local err`/`try-catch` across separate top-level forms**
- **Found during:** Task 2 testitem 8 ("max_sweeps exhaustion raises loudly")
- **Issue:** TestItemRunner re-includes each `@testitem`'s body as a SEQUENCE of independent top-level forms (not one compound expression); a bare top-level `local err = nothing` followed by a separate `try/catch` form and separate `@test` forms do NOT share scope, causing `UndefVarError: err not defined` on the `@test` lines (confirmed directly: `run_nash!` itself correctly raises `ErrorException` with the expected message when tested outside TestItemRunner).
- **Fix:** Wrapped the try/catch and assertions in a single `let err = nothing ... end` block (one compound top-level form), mirroring `test_planning_benders.jl`'s own `mktempdir() do dir ... end` closure idiom for the identical pattern.
- **Files modified:** `test/test_planning_nash.jl`
- **Verification:** Testitem 8 passes.
- **Committed in:** `b7cc165` (Task 2 commit)

**6. [Rule 1 - Bug] `plot_nash_convergence`'s legend-entry vector type inference**
- **Found during:** Task 3, manual CairoMakie-installed verification (not exercised by the headless suite, which correctly skips when the weakdep is absent)
- **Issue:** `plotted = [lresid]` type-inferred a `Vector{Lines}` from its first (`lines!`) element; a later `push!` of a `scatterlines!` plot object raised `MethodError` (mixed `Lines`/`ScatterLines` types cannot share a concretely-typed vector).
- **Fix:** Changed to `plotted = Any[lresid]`.
- **Files modified:** `ext/TSODSOMakieExt.jl`
- **Verification:** Directly verified in a scratch environment with CairoMakie installed: `TSODSO.plot_nash_convergence(trace)` returns a `CairoMakie.Makie.Figure`.
- **Committed in:** `b59fd52` (Task 3 commit)

---

**Total deviations:** 6 auto-fixed (all Rule 1 — bugs discovered during verification, each fixed inline and re-verified before continuing)
**Impact on plan:** All six fixes were necessary for correctness (either the code did not work as written, or a test assertion encoded a mathematically fragile expectation). No scope creep — the fixture's hand-derived target values (z=[0.6,0.6], x_inv=[0.3,0.3]) were verified correct and required NO re-tuning (the plan's own Revision-1 contingency was available but not needed).

## Issues Encountered
- **TestItemRunner cross-worktree test discovery:** running `julia -e '... @run_package_tests filter=...'` from inside this worktree's directory picked up test files from a SIBLING parallel-executor worktree too (`@run_package_tests`'s bare macro form resolves its scan path relative to `dirname(__source__.file)`, which for `-e` inline code resolves to `..` relative to the shell's cwd — i.e., the shared `.claude/worktrees/` parent directory containing every active worktree). Worked around by calling `TestItemRunner.run_tests(path; filter=...)` directly with an explicit, worktree-scoped absolute path instead of the bare `@run_package_tests` macro. Also confirmed (mirroring 13-01-SUMMARY.md's own note) that `--project=test` cannot resolve `TSODSO` directly (`test/Manifest.toml` has no dev-path entry for it); verification instead used a dedicated scratch environment (`Pkg.develop(path=pwd())` into a copy of `test/Project.toml`) to run tests without touching the repo's own `test/` environment files.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `run_nash!`/`NashTrace`/`plot_nash_convergence` are ready for plan 13-03's multi-seed/multi-order probe (`run_nash_probe`, NASH-04) to consume: `run_nash!`'s own boundary-guard/return-tuple contract and `NashTrace.order_trace` field already carry what a probe needs to slice per-run traces back out.
- The TestItemRunner cross-worktree scan-path issue noted above should be flagged to the orchestrator/next executor: any future parallel-executor verification run from inside a worktree must use `TestItemRunner.run_tests(<explicit path>; filter=...)`, never the bare `@run_package_tests` macro form, to avoid accidentally scanning sibling worktrees' test files.
- No blockers for plan 13-03.

---
*Phase: 13-nash-diagonalization-shared-transmission-coupling*
*Completed: 2026-07-24*

## Self-Check: PASSED

- FOUND: src/planning/nash.jl
- FOUND: test/test_planning_nash.jl
- FOUND: src/planning/benders.jl
- FOUND: src/TSODSO.jl
- FOUND: src/diagnostics/plots.jl
- FOUND: ext/TSODSOMakieExt.jl
- FOUND: commit 189183e (Task 1)
- FOUND: commit b7cc165 (Task 2)
- FOUND: commit b59fd52 (Task 3)
