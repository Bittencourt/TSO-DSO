---
phase: 10-oracle-coupling-wiring-resilience
plan: 02
subsystem: infra
tags: [julia, jump, clarabel, parameter, dual, benders-seam]

# Dependency graph
requires:
  - phase: 10-oracle-coupling-wiring-resilience
    provides: "solve_with_retry! -- bounded, escalating Clarabel-conditioning retry wrapper around assert_solved! (plan 10-01, D-08/D-09)"
provides:
  - "PlanningOracle + build_planning_oracle -- build-once, formulation-generic welfare-shaped subproblem with a genuine JuMP Parameter z[t] and a named pin[t]: p_import[t] == z[t] constraint (D-01/D-11)"
  - "solve_planning_oracle! -- retry-wrapped re-solve returning (; cost, π, π_s, dadp, ctx); π is the length-T Benders-cut gradient (D-05), π_s its duration-weighted, reporting-only reconciliation (D-04/D-07)"
  - "raw-dual sign convention pinned by a hand-derived toy-case monotonicity invariant (D-06): π is monotonically non-decreasing in z, ~0 at the network's own unconstrained free-import optimum"
affects: [phase-11-benders-master-follower, phase-12-cut-store-master-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JuMP Parameter-typed coupling variable + named pin constraint: z[t] in Parameter(0.0), pin[t]: p_import[t] == z[t] -- re-solved via set_parameter_value.(o.z, z_trial) with zero rebuild, mirroring DsoOpt/AgrOpt's build-once idiom but for a single-variable pin rather than a whole-network coupling array"
    - "Formulation-generic subproblem factory: Model(select_optimizer(problem_class(pf))) -- mirrors solve_welfare's routing (never hardcodes SOCP(), unlike DsoOpt)"
    - "z_trial feasibility discipline: derive test z_trial from the network's own unconstrained free-import optimum (operational_oracle(...; z=nothing, allow_export=true)) rather than an arbitrary fixed vector, when the aggregator's device flexibility band is narrow"
    - "Toy-device regression pattern: a minimal DEV-05-conformant device with a separable, loose-bounded concave-quadratic utility isolates a clean (non-degenerate) dual-sign invariant, when the project's own richer fixture has active device bounds that make the redundant dual split ill-conditioned at the exact optimum"

key-files:
  created:
    - src/planning/subproblem.jl
  modified:
    - src/TSODSO.jl
    - test/test_planning_oracle.jl

key-decisions:
  - "z_trial must be derived from the network's own unconstrained free-import optimum (via the unmodified operational_oracle free path), not an arbitrary fixed vector, when testing against Phase6Fixtures's real 2-bus aggregator -- its inelastic demand + bounded device flexibility only tolerates a narrow feasible import band (z=0 is INFEASIBLE for this fixture, empirically verified)."
  - "The dual-sign toy-case regression (the load-bearing D-06 test) cannot cleanly hit |π|<1e-4 at zstar when built on Phase6Fixtures's real aggregator (Thermostatic/Deferrable/PVBattery): two structurally-redundant equality constraints touch p_import[t] (balance_p[root,t] and pin[t]), and their dual SPLIT is uniquely pinned only when every other coupled variable's own KKT stationarity is non-degenerate. Phase6Fixtures's comfort-band/battery-SOC bounds actively bind at the free-import optimum, giving |π| up to ~1.5 there instead of ~0. Built a minimal ToyElasticDevice (DEV-05-conformant, separable utility, loose bounds -- interior optimum at every hour, hand-derived p*=2) via a new ToyDeviceFixture @testmodule, reusing Phase6Fixtures's 2-bus feeder shape but not its aggregator -- exactly 10-RESEARCH.md Pitfall 1's own guidance (reuse the toy-case PATTERN, not the document's specific numeric toy, and not necessarily Phase6Fixtures's own aggregator)."
  - "src/TSODSO.jl wiring (the third planning/ include line) was moved to Task 1's GREEN commit rather than Task 2's, as the plan's action text specified -- without it, build_planning_oracle is unreachable via `using TSODSO` and Task 1's own acceptance criteria (automated test suite exits 0) cannot be satisfied. No functional difference in the final file; Task 2 needed no further TSODSO.jl change."

patterns-established:
  - "build_planning_oracle(feeder, pf, aggregators; λ₀, T=24) -> PlanningOracle: build-once, formulation-generic, free-sign frontier, mirrors solve_welfare's WR-03 reactive-capture ordering and DsoOpt's defensive residual-shape guard, without modifying either file"
  - "solve_planning_oracle!(o, z_trial; max_attempts=4, Δt=1.0) -> (; cost, π, π_s, dadp, ctx): solve_with_retry! is the SOLE solve entry point (never assert_solved! directly); π = dual.(o.pin); π_s = duration-weighted sum, reporting-only"

requirements-completed: [PLAN-01, PLAN-02]

# Metrics
duration: 71min
completed: 2026-07-22
---

# Phase 10 Plan 02: Oracle Coupling Wiring Summary

**A build-once `PlanningOracle` subproblem with a genuine JuMP `Parameter`-typed `z[t]` and a named `p_import[t] == z[t]` pin, re-solved via the plan-10-01 retry wrapper, returning the length-T Benders-cut gradient `π` and its duration-weighted `π_s` -- the raw-dual sign convention pinned by a hand-derived toy-case monotonicity invariant on a purpose-built smooth fixture (since the project's own richer 2-bus aggregator has active device bounds that make the redundant dual split ill-conditioned exactly at the unconstrained optimum).**

## Performance

- **Duration:** 71 min (13:44 -> 14:55 local, across 5 commits)
- **Started:** 2026-07-22T16:44:55Z (first commit)
- **Completed:** 2026-07-22T17:55:58Z (final commit)
- **Tasks:** 2 (both TDD: RED test commit + GREEN implementation commit each, plus one Rule-1 docs fixup commit)
- **Files modified:** 3 (1 created source file, 1 modified source file, 1 created/modified test file)

## Accomplishments

- `build_planning_oracle` turns the SEAM-01 `z`-pin `ArgumentError` stub into a live, build-once JuMP subproblem: a genuine `Parameter`-typed `z[t]` and a named `pin[t]: p_import[t] == z[t]` constraint, formulation-generic (routes via `select_optimizer(problem_class(pf))`, never hardcoding `SOCP()`), reusing `contribute!(pf, ctx, feeder)` / `contribute!(agg, ctx)` verbatim
- `solve_planning_oracle!` re-solves the built-once oracle via `solve_with_retry!` (plan 10-01, D-08) as the SOLE solve entry point, returning `(; cost, π, π_s, dadp, ctx)` -- `π` is the exact length-T Benders-cut gradient (D-05), `π_s` its duration-weighted, reporting-only reconciliation (D-04/D-07), never fed back into the optimization
- The raw-dual sign convention is pinned by a hand-derived toy-case regression (not assumed from a docstring formula): `π` is monotonically non-decreasing in `z`, ≈0 (max abs ~4e-10) at the network's own unconstrained free-import optimum -- discovered during implementation that this invariant does NOT hold cleanly on Phase6Fixtures's real aggregator (active device bounds create an ill-conditioned redundant-dual split there), so built a minimal, purpose-designed smooth toy device to isolate and verify the invariant cleanly
- `operational_oracle`/`solve_welfare` remain byte-for-byte unmodified (`git diff --stat` empty, verified at every commit) -- the entire seam lives in the new `src/planning/subproblem.jl` module
- Full v1.0+Phase-10 regression suite green throughout: 1978 passed / 2 documented-broken, zero Phase 1-9 regressions

## Task Commits

Each task followed the TDD RED -> GREEN cycle:

1. **Task 1: `PlanningOracle` + `build_planning_oracle`**
   - `a3b80d8` (test) -- RED: failing `@testitem`s for guard tests + build-once invariance
   - `d7ce70d` (feat) -- GREEN: `build_planning_oracle` implementation + `src/TSODSO.jl` wiring (moved here from Task 2's planned location, since Task 1's own tests require it reachable via `using TSODSO`)
2. **Task 2: `solve_planning_oracle!`**
   - `ac97b8f` (test) -- RED: failing `@testitem`s for NamedTuple shape, dual-sign regression, free-path parity, build-once re-solve
   - `2dd365c` (feat) -- GREEN: `solve_planning_oracle!` implementation, plus test-fixture adjustments (feasible `z_trial` derivation, new `ToyDeviceFixture` for the dual-sign regression) discovered necessary while turning RED tests green
   - `68dda6b` (docs) -- Rule-1 fixup: reworded doc comments to satisfy the literal `assert_solved!` grep acceptance gate (no behavior change)

**Plan metadata:** this commit (docs: complete plan) -- see final commit below.

## Files Created/Modified

- `src/planning/subproblem.jl` -- `PlanningOracle` struct, `build_planning_oracle`, `solve_planning_oracle!` (271 lines)
- `src/TSODSO.jl` -- appended `include("planning/subproblem.jl")` as the third `planning/` include line, after `retry.jl` and `checkpoint.jl`
- `test/test_planning_oracle.jl` -- 6 `@testitem`s (`[:planning]` tagged) + 1 `@testmodule` (`ToyDeviceFixture`): guards, build-once invariance (x2), NamedTuple shape, dual-sign toy-case regression, free-path parity

## Decisions Made

- **z_trial feasibility discipline:** Phase6Fixtures's real 2-bus aggregator (Thermostatic + Deferrable + PVBattery) has only a narrow feasible import band around its own unconstrained free-import optimum -- `z=0` and other arbitrary fixed vectors are INFEASIBLE for this fixture (empirically verified: `PRIMAL_INFEASIBLE` from Clarabel). Every test now derives its `z_trial` from `operational_oracle(...; z=nothing, allow_export=true)`'s own solved `p_import`, which is feasible by construction.
- **Toy-device regression for the dual-sign invariant:** the plan's Task 2(b) prescribes computing `zstar` via `operational_oracle` on Phase6Fixtures's real aggregator and asserting `|π| < 1e-4` there. Empirically, this does NOT hold on the real fixture -- `|π|` reaches ~1.5 at the exact `zstar`, and the dual is highly sensitive (swinging from ~-2.2 to ~+1.5 within a `1e-5` neighborhood of `zstar`). Root cause: `p_import[t]` is constrained by TWO structurally-redundant equalities (`balance_p[root,t]` and `pin[t]`), whose dual SPLIT is uniquely determined only when no OTHER coupled variable has an active bound; Phase6Fixtures's Thermostatic comfort-band and PVBattery SOC bounds actively bind at the free-import optimum, making the split ill-conditioned there. Per 10-RESEARCH.md Pitfall 1's own guidance ("reuse this toy-case PATTERN... NOT this document's specific numeric toy"), built a minimal `ToyElasticDevice` (DEV-05-conformant: `contribute!` returns `(; vars, p_inject, utility)`, separable utility `U(p) = a*p - (b/2)*p^2` mirroring `Interruptible`'s eq. 3.10 shape but aggregator-compatible) with deliberately loose bounds so its price-responsive optimum (`p* = 2`, hand-derived from `a=6, b=1, λ₀=4`) is strictly interior at every hour -- verified clean: `max|π| ~ 4e-10` at `zstar`, monotonic sign flip around it.
- **TSODSO.jl wiring moved to Task 1:** the plan assigns the `src/TSODSO.jl` include-line edit to Task 2's action text, but `build_planning_oracle` (Task 1) is unreachable via `using TSODSO` without it, and Task 1's own acceptance criteria require its automated test suite to exit 0. Wired at Task 1's GREEN commit instead; Task 2 needed no further edit to `TSODSO.jl`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task 2(b)'s prescribed dual-sign test fixture (Phase6Fixtures's real aggregator) does not satisfy its own `|π|<1e-4` assertion**
- **Found during:** Task 2, while turning the RED dual-sign regression test green
- **Issue:** The plan's literal action text prescribes `zstar` from `operational_oracle(Phase6Fixtures.two_bus_feeder(), LinDistFlow(), aggs; ...)` (the REAL 2-bus aggregator: Thermostatic + Deferrable + PVBattery) and asserts `all(abs.(res_star.π) .< 1e-4)`. Empirically this fails (`max|π| ~ 1.5`) because two structurally-redundant equality constraints (`balance_p[root,t]`, `pin[t]`) both touch `p_import[t]`; their dual split is only unique when no other coupled variable has an active bound, and Phase6Fixtures's Thermostatic comfort-band / PVBattery SOC bounds DO bind at the network's free-import optimum, making the split acutely ill-conditioned right at that point (dual swings by ~4 within a `1e-5` neighborhood of `zstar`).
- **Fix:** Built a minimal, DEV-05-conformant `ToyElasticDevice` (loose bounds, separable concave-quadratic utility, hand-derived interior optimum `p*=2`) in a new `ToyDeviceFixture` `@testmodule`, reusing Phase6Fixtures's 2-bus feeder shape (not its aggregator) for the dual-sign regression specifically. Also derived every OTHER test's `z_trial` from the network's own unconstrained free-import optimum rather than an arbitrary fixed vector, since `z=0`/`fill(-0.02,T)` are infeasible for the real aggregator.
- **Files modified:** `test/test_planning_oracle.jl`
- **Verification:** `max|π| ~ 4e-10` at `zstar` on the toy device (well within `1e-4`); monotonicity (`res_plus.π >= res_star.π >= res_minus.π`) holds; full suite green (1978 passed / 2 documented-broken).
- **Commit:** `2dd365c`

**2. [Rule 1 - Bug] Doc comments tripped the literal `assert_solved!` grep acceptance gate**
- **Found during:** Task 2, final acceptance-criteria verification pass
- **Issue:** The plan's acceptance criteria require `grep -n 'assert_solved!' src/planning/subproblem.jl` to return nothing (D-08: the retry wrapper is the sole solve entry point). Doc-comment prose explaining "never calls `assert_solved!` directly" mentioned the literal token, tripping the grep even though no actual call exists.
- **Fix:** Reworded the three comment lines to describe the same guarantee without the literal token.
- **Files modified:** `src/planning/subproblem.jl`
- **Verification:** `grep -n 'assert_solved!' src/planning/subproblem.jl` now returns nothing; full suite re-verified green.
- **Commit:** `68dda6b`

---

**Total deviations:** 2 auto-fixed (both Rule 1 -- bug: a test-fixture correctness gap and a literal-grep documentation wording gap)
**Impact on plan:** Both fixes preserve the plan's exact intent (D-06's monotonic sign-pin invariant; D-08's sole-entry-point guarantee) while making the delivered tests and docs actually correct/passing. No scope creep, no change to the public API (`PlanningOracle`, `build_planning_oracle`, `solve_planning_oracle!` match the plan's prescribed signatures exactly).

## Issues Encountered

- **The `TestItemRunner.runtests(filter=...)` command in the plan's literal `<automated>` verify blocks does not exist** (same pre-existing deviation pattern documented in every prior phase, most recently 10-01-SUMMARY.md) -- resolved by using scoped scratch-environment `julia` scripts for interactive debugging/verification during implementation, and the authoritative `julia --project=. -e 'import Pkg; Pkg.test()'` for every RED/GREEN gate and the final acceptance gate.
- **Investigating the dual-sign discrepancy required substantial debugging** (sweeping `z` around `zstar` in small increments, comparing `balance_p[root]` vs `pin` duals, verifying the redundant-constraint-degeneracy hypothesis) before concluding the correct fix was a purpose-built smooth toy device rather than a bug in `build_planning_oracle`/`solve_planning_oracle!` itself. The implementation was verified correct throughout (feasibility, cost matching, `p_import` matching `zstar` to `1e-11`) before the toy-device fix was applied.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- `build_planning_oracle`/`solve_planning_oracle!` are both independently proven (11 new passing `@testitem` assertions across 6 items) and exported from `TSODSO`, ready for Phase 11's Benders loop to consume `π` as the cut gradient.
- Full regression suite confirmed healthy: 1978 passed / 2 documented-broken (unchanged baseline plus this plan's 17 new assertions across Task 1+2) -- no Phase 1-9 source file was modified (`git diff --stat` on `src/models/oracle.jl`/`src/models/welfare_solve.jl` empty at every commit, D-03/D-11).
- Phase 11 should be aware of the redundant-dual-split finding (documented above) when certifying the raw-dual sign convention against a REAL Benders master problem: any coupled variable with an active bound (device comfort bands, SOC limits) near the trial point can make `dual(pin)` acutely sensitive to numerical precision. The length-T `π` (D-05, the exact cut gradient) is unaffected by this finding when `z_trial` sits away from such a boundary; Phase 11's own certification gate (PLAN-07, BilevelJuMP cross-validation) is the right place to further stress-test this on realistic feeder/aggregator combinations.
- No blockers for Phase 11.

## Self-Check: PASSED

- All created files verified present on disk: `src/planning/subproblem.jl`, `test/test_planning_oracle.jl`, this SUMMARY.md.
- All referenced commit hashes verified present in `git log`: `a3b80d8`, `d7ce70d`, `ac97b8f`, `2dd365c`, `68dda6b`.
