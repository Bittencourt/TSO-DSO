---
phase: 03-prosumer-device-library-social-welfare-solve
plan: 04
subsystem: devices
tags: [julia, jump, clarabel, bess, battery, socp, qp, convex-optimization, no-binary]

# Dependency graph
requires:
  - phase: 03-01
    provides: PVBattery.jl comment-only seam stub + TSODSO.jl include wiring + battery RED testitem
  - phase: 02-03
    provides: AbstractDevice supertype + contribute! generic + Interruptible reference pattern
  - phase: 01-03
    provides: ModelContext, select_optimizer(QP()) factory, assert_solved! status gate
provides:
  - "PVBattery{T} <: AbstractDevice (DEV-04): guarded no-binary PV+battery device"
  - "SOC dynamics (3.6) + PV-limited charge (3.7) + SOC band/IC (3.9) constraints"
  - "App. C concave charge-utility / convex discharge-cost parametrization (3.15-3.20)"
  - "Aggregatable contract: contribute! returns (; vars, p_inject, utility), writes nothing to residual/objective"
  - "Numeric App. C verification: standalone-solve p_ch·p_dch < τ + zero-binary invariant"
affects: [03-05, phase-04, phase-05, phase-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Aggregatable-device variant: device builds vars+constraints on ctx.model but RETURNS (; vars, p_inject, utility) instead of self-injecting (aggregator-as-writer, DEV-05)"
    - "No-binary complementarity: cost-structure parametrization (App. C) + mandatory post-solve numeric assertion, no binary/complementarity constraint"

key-files:
  created: []
  modified:
    - src/devices/PVBattery.jl
    - test/test_pvbattery.jl

key-decisions:
  - "No-binary battery: relied entirely on App. C λ_min ≤ λ_med ≤ λ_max parametrization; verified p_ch·p_dch<τ numerically on a standalone QP solve rather than adding any complementarity/binary constraint (preserves QP convexity + Phase-5 duals)"
  - "Constructor guards λ ordering, η∈(0,1], Pmax>0, Emin≤soc0≤Emax as throw-based inner-constructor invariants (the λ-ordering guard is the load-bearing App. C sufficient condition)"
  - "Aggregatable return contract (; vars, p_inject, utility) with p_inject = Ppv − p_ch + p_dch; device holds no feeder and calls no add_to_residual!/add_to_objective!"

patterns-established:
  - "Aggregatable device: temporal-coupling constraints on ctx.model, preferences returned as a QuadExpr utility for the Aggregator to roll up (not self-injected)"
  - "Numeric-invariant testing: solve a bounded standalone QP with a tension-creating price signal, then assert the physics invariant (p_ch·p_dch<τ) + structural invariant (zero binaries) at the optimum"

requirements-completed: [DEV-04]

# Metrics
duration: ~25min
completed: 2026-07-18
---

# Phase 3 Plan 04: PV+Battery (BESS) No-Binary Device Summary

**PVBattery (DEV-04): a co-located PV+battery aggregatable device with SOC dynamics, PV-limited charge, and an App. C concave-charge/convex-discharge parametrization that keeps p_ch·p_dch=0 at the optimum with NO binaries — verified numerically on a standalone Clarabel QP solve.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Implemented `PVBattery{T} <: AbstractDevice` with a throw-based guarded inner constructor (App. C `λ_min ≤ λ_med ≤ λ_max`, `Pmax > 0`, `η ∈ (0,1]`, `Emin ≤ soc0 ≤ Emax`) and a promotion outer constructor.
- `contribute!` builds continuous `p_ch, p_dch ∈ [0,Pmax]` and `soc ∈ [Emin,Emax]` (NO binary/integer), adds SOC dynamics (3.6), PV-limited charge (3.7), SOC band + IC (3.9), and the App. C utility (3.15-3.20) — and returns the aggregatable `(; vars, p_inject, utility)` triple, writing nothing to the residual/objective.
- Battery `@testitem`s green (30/30 in `test/test_pvbattery.jl`): constructor guards, and a standalone convex-QP solve asserting `value(p_ch[t])·value(p_dch[t]) < 1e-6` for every hour (App. C numeric verification) with a genuine charge-early/discharge-late tension, plus the zero-binary/zero-integer invariant.

## Task Commits

Each task was committed atomically:

1. **Task 1: PVBattery device (DEV-04)** - `5f44e52` (feat)
2. **Task 2: Battery guards + standalone p_ch·p_dch<τ zero-binary solve tests** - `08f0b79` (test)

_TDD note: the RED battery testitem (`isdefined(TSODSO, :PVBattery)`) pre-existed from plan 03-01; Task 1 turned it green, Task 2 added the behavioral/numeric coverage._

## Files Created/Modified
- `src/devices/PVBattery.jl` - Filled the DEV-04 seam: `PVBattery{T}` struct + guarded constructors + `contribute!` (SOC 3.6, PV-limit 3.7, band 3.9, App. C utility 3.15-3.20, no binaries; aggregatable return). Docstring cites eqs. 3.6-3.9, 3.15-3.20, App. C pp. 166-168, Assumption A6.
- `test/test_pvbattery.jl` - Constructor-guard `@test_throws` cases + standalone Clarabel QP solve with the mandatory `p_ch·p_dch < τ` complementarity assertion and zero-binary invariant.

## Decisions Made
- **No-binary battery via App. C only:** did not add any binary or `p_ch·p_dch==0` complementarity constraint (RESEARCH §Anti-Patterns). Correctness rests on the `λ_min ≤ λ_med ≤ λ_max` cost structure (charge marginal ≤ λ_med ≤ discharge marginal) plus `η²<1` waste; verified numerically. This preserves QP convexity and the accurate duals Phase-5 pricing needs.
- **Aggregatable-device contract (aggregator-as-writer):** unlike the self-injecting `Interruptible`, this device returns `(; vars, p_inject, utility)` and touches neither `ctx.residuals` nor `add_to_objective!`; the Aggregator (DEV-05, plan 03-05) is the sole residual/utility writer.
- **Test scenario design:** used a time-varying export price (`[2,2,20,20]`) over `T=4` with `Ppv=[5,5,0,0]` to create real charge/discharge tension across hours, so the `p_ch·p_dch<τ` assertion is non-trivial (both charging and discharging are active, just never in the same hour).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- **Mixed-type promotion test initially failed:** the promotion assertion originally passed all-integer arguments, so `PVBattery` promoted to `{Int64}` (η=1 is a valid integer efficiency) and `mixed.Pmax === 5.0` failed against the `Int` `5`. Fixed by passing a `Float64` η (`0.95`) among the integer args so `promote_type` yields `Float64` — the intended mixed-promotion path. (Test-only fix, part of the Task 2 commit; not a device deviation.)
- **Local test-runner scoping:** `@run_package_tests` from `julia -e` expands to `run_tests("..")`, which scans sibling agent worktrees under `.claude/worktrees/`. Worked around by calling `TestItderRunner.run_tests(<worktree-root>; filter=...)` directly to scope to this worktree. `test/test_welfare_solve.jl` (plan 03-05's seam, `solve_welfare` not implemented here) stays RED and matched the "battery" filter only because its name contains "battery complementarity" — not a regression and not this plan's deliverable.

## Next Phase Readiness
- `PVBattery` is ready for the Aggregator (DEV-05) roll-up and `solve_welfare` (OPT-01) in plan 03-05, which will re-verify `p_ch·p_dch<τ` at the full welfare optimum.
- The device is network-agnostic (no feeder, no residual/objective writes), so the DC/LinDistFlow/SOCP power-flow swap (Phase 4) leaves it untouched.

## Self-Check: PASSED

- `src/devices/PVBattery.jl` — FOUND
- `test/test_pvbattery.jl` — FOUND
- `.planning/phases/03-prosumer-device-library-social-welfare-solve/03-04-SUMMARY.md` — FOUND
- Commit `5f44e52` (feat: PVBattery device) — FOUND
- Commit `08f0b79` (test: battery guards + solve) — FOUND
- Battery testitems (`test/test_pvbattery.jl`): 30/30 PASS incl. p_ch·p_dch<τ and zero-binary asserts

---
*Phase: 03-prosumer-device-library-social-welfare-solve*
*Completed: 2026-07-18*
