---
phase: 25-ieee-8500-scalability-benchmark
plan: 02

subsystem: infra
tags: [jump, clarabel, scs, admm, solver-factory, wall-clock-budget]

# Dependency graph
requires: []
provides:
  - "SCS reachable via TSODSO.alternative_optimizer(TSODSO.SCSChoice(), pc) when SCS is loaded (opt-in weakdep, never a hard dependency)"
  - "solve_admm(...; time_limit_s=<seconds>) — an honest wall-clock exit for the whole consensus loop, returning status = :budget_exceeded instead of hanging"
  - "solve_admm's return NamedTuple now always carries a status key (:converged or :budget_exceeded)"
affects: [25-05-benchmark-harness]

# Tech tracking
tech-stack:
  added: ["SCS.jl 2.6.4 (weakdep only, never [deps])"]
  patterns:
    - "New alternative_optimizer(choice, pc) dispatch point, parallel to commercial_optimizer, for open-source-but-opt-in solvers (avoids the semantic mismatch of routing SCS through a 'commercial' function)"
    - "Wall-clock loop exit checked once per iteration, immediately after the convergence check and before the dual-ascent update, with its own honest early-return branch that skips the certified-consolidation pass"

key-files:
  created:
    - ext/TSODSOSCSExt.jl
    - test/test_admm_timeout.jl
  modified:
    - Project.toml
    - src/solver/ProblemClass.jl
    - src/solver/factory.jl
    - src/admm/solve_admm.jl

key-decisions:
  - "Task 1's blocking human-verify checkpoint was resolved by the orchestrator before this worktree agent ran: the plan's stated SCS UUID (c946c3f1-2d62-5474-9fac-a2c854d76d31) was WRONG against the live Julia General registry; the registry-actual UUID c946c3f1-0d1f-5ce8-9dea-7daa1f7e2d13 (v2.6.4, jump-dev/SCS.jl) was written instead"
  - "SCS is dispatched via a NEW alternative_optimizer function, never commercial_optimizer — SCS is open-source, so reusing the 'commercial' name would be a semantic mismatch (D-20)"
  - "time_limit_s's wall-clock check is placed AFTER the convergence check and BEFORE the dual-ascent update, so it never preempts a genuine consensus reached on the same iteration"
  - "A :budget_exceeded return skips the final consolidation pass entirely (battery/4Q/SOC-exactness certificates) and sets welfare/dadp/λ/exact_maxgap/mu_q to nothing by design — never a plausible-but-uncertified mid-loop price"

patterns-established:
  - "Alternative (open-source, opt-in) solver dispatch: alternative_optimizer(choice, pc), sibling to commercial_optimizer(choice, pc), for weakdeps that are opt-in but not commercial/licensed"

requirements-completed: [SCALE-04]

duration: 65min
completed: 2026-08-21
---

# Phase 25 Plan 02: SCS Weakdep Extension + ADMM Wall-Clock Budget Summary

**Added an `alternative_optimizer`/`SCSChoice` dispatch wiring SCS.jl as an opt-in weakdep solver, and a `time_limit_s` wall-clock exit on `solve_admm` that returns an honest `:budget_exceeded` status instead of hanging — both prerequisites for the IEEE-8500 benchmark harness (plan 25-05).**

## Performance

- **Duration:** ~65 min (dominated by a full-suite `Pkg.test()` run under heavy shared-machine memory/swap pressure, superseded per orchestrator instruction by the wave-level post-merge test gate)
- **Completed:** 2026-08-21
- **Tasks:** 3 (1 checkpoint, pre-resolved by the orchestrator; 2 auto)
- **Files modified:** 4 modified, 2 created

## Accomplishments

- SCS.jl wired as a genuinely opt-in, never-hard-dependency alternative conic solver, reachable only via `TSODSO.alternative_optimizer(TSODSO.SCSChoice(), pc)` when the user has `import SCS`'d it
- `solve_admm` now accepts an optional wall-clock budget (`time_limit_s`) for the whole consensus loop, with a byte-identical default (`nothing`) path and an honest `:budget_exceeded` early return that never fabricates a mid-loop price
- New regression test (`test/test_admm_timeout.jl`, a plain `Test.jl` script per this project's TestItemRunner-under-`--project=.` sibling-worktree trap) proving all three required behaviors: unaffected default fail-loud throw, honest budget-exceeded exit, and the additive `:converged` status on normal convergence — 17/17 assertions pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify SCS.jl package legitimacy before adding the weakdep** — no commit (human-verify checkpoint; the orchestrator ran this against the live Julia General registry before this worktree agent started and supplied the verified UUID/version as input — see Deviations below)
2. **Task 2: SCS weakdep extension via a new alternative_optimizer/SCSChoice dispatch (D-20)** — `305a57a` (feat)
3. **Task 3: solve_admm time_limit_s wall-clock exit (D-18)** — `47c683f` (feat)

_No plan-metadata commit yet — STATE.md/ROADMAP.md updates are owned by the orchestrator post-merge (worktree mode)._

## Files Created/Modified

- `Project.toml` — SCS added under `[weakdeps]` (UUID `c946c3f1-0d1f-5ce8-9dea-7daa1f7e2d13`), `[extensions]` (`TSODSOSCSExt = "SCS"`), `[compat]` (`SCS = "2.6.4"`) — confirmed absent from `[deps]`
- `src/solver/ProblemClass.jl` — added `struct SCSChoice end` marker + export
- `src/solver/factory.jl` — added `alternative_optimizer(choice, pc::ProblemClass)` fallback (error message never says "commercial") + export
- `ext/TSODSOSCSExt.jl` — new package extension, `TSODSO.alternative_optimizer(::SCSChoice, pc) = optimizer_with_attributes(SCS.Optimizer, "verbose" => 0)`
- `src/admm/solve_admm.jl` — added `time_limit_s` kwarg, wall-clock check inside the loop, the `budget_exceeded_flag` early-return branch, and the additive `status` field on both return paths; docstring updated (Returns/Throws/new "Wall-clock budget" section)
- `test/test_admm_timeout.jl` — new plain-script regression test (not `@testitem`)

## Decisions Made

- **UUID correction (Task 1 checkpoint resolution):** the plan's stated SCS UUID `c946c3f1-2d62-5474-9fac-a2c854d76d31` does not match the live Julia General registry. The orchestrator fetched `https://raw.githubusercontent.com/JuliaRegistries/General/master/S/SCS/Package.toml` and `Versions.toml` directly and confirmed the registry-actual UUID is `c946c3f1-0d1f-5ce8-9dea-7daa1f7e2d13`, repo `jump-dev/SCS.jl`, current version `2.6.4` (newest registered). This is the UUID written to `Project.toml`. Consistent with `25-RESEARCH.md`'s Package Legitimacy Audit tagging SCS `[ASSUMED]` (no ecosystem support in `slopcheck` to verify it automatically) — this checkpoint was the intended mitigation, and it caught a real discrepancy.
- **`alternative_optimizer` as a new, separate dispatch (not `commercial_optimizer`):** SCS is open-source; reusing the "commercial" name/wording for it would be a semantic mismatch even though both are opt-in weakdep extensions (D-20).
- **Wall-clock check ordering:** placed immediately after the convergence check and before the dual-ascent update, so a genuine consensus reached on the same iteration the budget would also expire is never preempted by the budget check.
- **Test fixture seed for `test_admm_timeout.jl`:** uses `ieee13_modified()` + `build_population(:default, feeder, :ieee13, profiles, seed)` + `ConvexBranchFlow()` + `build_price(:mem, T, nothing)` exactly as the plan specifies, but with `seed = 20260718` (matching `test/fixtures_phase4.jl`'s `build_ieee13_ground_aggregators` default seed) rather than an arbitrary seed — see Deviations below for why.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — required correction, pre-authorized by the orchestrator] SCS UUID in the plan was wrong**
- **Found during:** Task 1 (checkpoint resolution, performed by the orchestrator before this agent started)
- **Issue:** `25-02-PLAN.md` stated the SCS UUID as `c946c3f1-2d62-5474-9fac-a2c854d76d31`. The live Julia General registry's `Package.toml` for SCS gives `c946c3f1-0d1f-5ce8-9dea-7daa1f7e2d13` — they share only the `c946c3f1` prefix.
- **Fix:** Wrote the registry-actual UUID everywhere SCS's UUID appears (`Project.toml`'s `[weakdeps]`). Recorded version `2.6.4` in `[compat]` (confirmed newest registered).
- **Files modified:** `Project.toml`
- **Verification:** `grep -n "c946c3f1-0d1f-5ce8-9dea-7daa1f7e2d13" Project.toml` matches; `grep -n "c946c3f1-2d62-5474-9fac-a2c854d76d31" Project.toml` does not match; `grep -i scs` against the `[deps]` block is empty.
- **Committed in:** `305a57a` (Task 2 commit)

**2. [Rule 1 — test fixture bug, own new test file] `test_admm_timeout.jl`'s first fixture attempt converged trivially on iteration 1**
- **Found during:** Task 3 verification
- **Issue:** The first draft used `build_population(:default, feeder, :ieee13, profiles, seed)` with `seed = 42` and a flat constant `λ₀ = fill(1.0, T)`. That population/price combination has essentially no congestion, so `solve_admm` converged on the VERY FIRST iteration — before the new wall-clock check ever got a chance to fire — and the run proceeded into the final consolidation pass, which then hit an UNRELATED, PRE-EXISTING battery-complementarity certificate (`assert_battery_complementarity!`) exactly at its numerical knife-edge (`p_ch·p_dch` landing within ~1e-9 of the `τ·Pmax²` threshold). This is a property of that particular off-nominal price/population/certificate-tolerance combination, not of the `time_limit_s` feature under test, and not something this plan's `<files>` scope authorizes touching.
- **Fix:** Switched the test fixture to the realistic digitized MEM price (`build_price(:mem, T, nothing)`, same as `scripts/thesis_caseA.jl`) and to `seed = 20260718` — the SAME default seed `test/fixtures_phase4.jl`'s `build_ieee13_ground_aggregators` uses for its congestion-driven "ground" fixture (the one `test/test_admm.jl`'s own ieee13 crossval test already exercises safely, needing ~dozens of iterations to converge at ρ=100). This reproduces that known-good, congestion-driven population via the plan-specified `build_population(:default, ...)` call (no source changes), giving both the fail-loud (`maxiter=1`) and wall-clock (`time_limit_s=1e-9`) tests something genuine to interrupt before any convergence or consolidation-pass certificate runs.
- **Files modified:** `test/test_admm_timeout.jl` (test-only; no `src/` changes)
- **Verification:** `julia --project=. test/test_admm_timeout.jl` — Test Summary: 17 Pass, 0 Fail, 0 Error, 0 Broken.
- **Committed in:** `47c683f` (Task 3 commit)

---

**Total deviations:** 2 (1 pre-authorized checkpoint correction, 1 test-fixture self-fix). **Impact on plan:** No scope creep — the UUID correction is exactly what the Task 1 checkpoint exists to catch, and the fixture fix stayed entirely inside the new test file with zero `src/` changes beyond what the plan specified.

## Issues Encountered

- **Full-suite `Pkg.test()` was run once, took ~40 minutes under heavy shared-machine memory/swap pressure** (this worktree shares the host with sibling wave-1 worktree agents), and finished with **2801 pass / 1 fail / 3 error / 3 broken** (of 2808 total). The failures/errors were: `test_pricing_welfare.jl` (1 error), `test_planning_nash.jl` (1 error), `test_diagnostics_plot.jl` (1 error), `test_stochastic_welfare.jl` (1 fail, in the "D-06 PF-04 gate runs per scenario" testset), and `test_experiments.jl` (3 errors: "EXP-01 scenario admm", "INFRA-04 same-seed repro admm", "INFRA-04 seed sensitivity admm" — all `NUMERICAL_ERROR` from Clarabel on an IEEE-13 ADMM re-solve). These match this project's own recorded, pre-existing, unfixed flakiness note (`MEMORY.md`: "CI-flaky, version-independent, intermittent Clarabel `NUMERICAL_ERROR` on the IEEE-13 ADMM solve ... never fixed in v1.0 ... expected to be AMPLIFIED once new outer loops re-solve it repeatedly") — none of these failing files are in this plan's `<files>` scope, and `test/test_admm.jl` itself (the file most directly adjacent to `src/admm/solve_admm.jl`) passed all 34 of its own items in that same run, evidence this plan's changes did not regress the existing ADMM suite. Per the orchestrator's explicit instruction, full-suite verification is delegated to the wave-level post-merge test gate rather than re-run here; this plan's own primary verification gate (`julia --project=. test/test_admm_timeout.jl`) passed cleanly (17/17) as the targeted evidence for Tasks 2/3.
- A second, concurrent `Pkg.test()`-adjacent process (the standalone `test_admm_timeout.jl` run, launched while the full suite was still going) was killed under the same memory pressure; it was not a duplicate of the full-suite run and no orphaned process remained by the time work resumed (`pgrep -af "Pkg.test|runtests.jl"` returned empty before committing).

## User Setup Required

None — SCS is a pure Julia weakdep with no external service/credential configuration. A researcher who wants to actually exercise `alternative_optimizer(SCSChoice(), pc)` need only `import SCS` in their own environment; nothing in this plan requires that for the plan's own verification to pass.

## Next Phase Readiness

- Plan 25-05 (benchmark harness) can now call `solve_admm(...; time_limit_s = <budget>)` for an honest, non-hanging IEEE-8500-scale run, and can select SCS via `alternative_optimizer(SCSChoice(), pc)` for the Clarabel-vs-SCS crossover measurement (SCALE-04) — both seams exist independently of the 8500 fixture itself, confirming this plan's wave-1 (dependency-free) placement was correct.
- No blockers for downstream plans. The full-suite pre-existing flakiness (documented above) is a known, standing project concern, not a new blocker introduced here.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- FOUND: ext/TSODSOSCSExt.jl
- FOUND: test/test_admm_timeout.jl
- FOUND: .planning/phases/25-ieee-8500-scalability-benchmark/25-02-SUMMARY.md
- FOUND commit: 305a57a (Task 2)
- FOUND commit: 47c683f (Task 3)
