---
phase: 02-linear-branch-flow-residual-seam
plan: 03
subsystem: devices
tags: [jump, device-contract, interruptible-load, quadexpr, residual-seam, concavity]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "ModelContext + contribute! generic (AbstractPowerFlow) + solver factory (select_optimizer/QP)"
  - phase: 02-01
    provides: "indexed add_to_residual!(ctx,name,i,t,expr) (Matrix{AffExpr}) + add_to_objective!(ctx,expr) (QuadExpr)"
provides:
  - "AbstractDevice supertype sharing the framework contribute! generic (device contract)"
  - "Interruptible{T} elastic load: bounded power var, signed -p :Rp injection, concave a*p-(b/2)p^2 QuadExpr utility"
  - "Concavity guard (b>0) and bounds guard (Pmax>=Pmin) enforced at construction via ArgumentError"
affects: [phase-02-04-integration, phase-03-device-library, admm-operational-layer]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Device-as-type contract: concrete devices add METHODS to the shared contribute! generic (mirrors AbstractPowerFlow)"
    - "Affine-residual / quadratic-objective split: signed injection -> :Rp (AffExpr), concave utility -> ctx.meta[:objective] (QuadExpr, curvature retained)"
    - "Network-agnostic device: holds only bus id + horizon T; grep-gate forbids topology references in src/devices/"
    - "Correctness guards use throw(ArgumentError), never @assert (project convention)"

key-files:
  created: []
  modified:
    - src/devices/AbstractDevice.jl
    - src/devices/Interruptible.jl
    - test/test_device.jl

key-decisions:
  - "contribute! generic reused from AbstractPowerFlow (not redeclared) so devices and power-flow share one dispatch surface"
  - "Utility routed through add_to_objective! (QuadExpr) to preserve -(b/2)p^2 curvature; :Rp stays strictly affine"
  - "Consumed load contributes NEGATIVE injection (-p) into :Rp, matching toy_dc sign convention (a load reduces net injection)"
  - "b<=0 and Pmax<Pmin rejected in the inner constructor with ArgumentError (throw, not @assert)"

patterns-established:
  - "Device contract: contribute!(dev, ctx; T) creates own vars+bounds, adds signed :Rp injection, accumulates concave QuadExpr utility"
  - "Docstrings avoid literal topology tokens so the network-agnosticism grep-gate over src/devices/ stays mechanically clean"

requirements-completed: [DEV-03]

# Metrics
duration: 5min
completed: 2026-07-18
---

# Phase 2 Plan 03: Device Contract + Interruptible Load Summary

**AbstractDevice contract plus a network-agnostic Interruptible/elastic load that injects a signed `-p` into the affine `:Rp` residual and accumulates a concave `a·p − (b/2)p²` utility into the QuadExpr welfare objective, with a `b>0` concavity guard.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-07-18T18:43:00Z
- **Completed:** 2026-07-18T18:48:11Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `AbstractDevice` supertype documents and establishes the device contract, reusing (not redeclaring) the shared `contribute!` generic from `AbstractPowerFlow`.
- `Interruptible{T}` device: bounded per-time power variable `Pmin ≤ p[t] ≤ Pmax`, a signed **negative** injection `−p[t]` into `ctx.residuals[:Rp]`, and a concave utility `Σ_t(a·p[t] − (b/2)p[t]²)` (thesis eq. 3.10) accumulated into `ctx.meta[:objective]` as a `QuadExpr` (curvature retained).
- Concavity guard: `b ≤ 0` throws `ArgumentError` (thesis eq. 3.14); inconsistent bounds `Pmax < Pmin` also throw.
- Device is fully network-agnostic — built with only a bus id and horizon `T`, no topology reference (grep gate over `src/devices/` is clean).
- Device `@testitem`s GREEN; full suite `Pkg.test()` = 91/91, no regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define the AbstractDevice contract** — `f97fa0c` (feat)
2. **Task 2: Implement the Interruptible/elastic load (DEV-03)** — TDD:
   - RED test: `cd99701` (test)
   - GREEN impl: `0a19f5b` (feat)

_Note: TDD task has test → feat commits (no refactor needed)._

## Files Created/Modified
- `src/devices/AbstractDevice.jl` — `abstract type AbstractDevice`; documents the device contract (own vars + signed `:Rp` injection + concave QuadExpr utility) and network decoupling; exports `AbstractDevice`. Does NOT redeclare the `contribute!` generic.
- `src/devices/Interruptible.jl` — `struct Interruptible{T<:Real} <: AbstractDevice` with `bus, Pmin, Pmax, a, b`; inner constructor guards (`b>0`, `Pmax≥Pmin`); `contribute!(d, ctx; T=1)` creates bounded `p[t]`, adds `−p[t]` to `:Rp`, adds concave utility to the objective; exports `Interruptible`.
- `test/test_device.jl` — two `:device` `@testitem`s: (1) `b≤0`/`Pmax<Pmin` throw; (2) `contribute!` against a bare `ModelContext` (NO feeder) yields a bounded var, a `:Rp` cell with a negative coefficient at the bus, and a `QuadExpr` objective whose quadratic coefficient is `−(b/2)` and linear is `+a`.

## Decisions Made
- Reused the existing `contribute!` generic (declared for `AbstractPowerFlow`) rather than declaring a second one — devices and formulations share one dispatch surface. The AbstractDevice source deliberately avoids the literal string `function contribute! end` so the plan's `grep -c` gate returns 0.
- Utility flows through `add_to_objective!` (QuadExpr), never `add_to_residual!`, so the `−(b/2)p²` curvature is not silently linearized away (threat T-02-02, Pitfall 3).
- Load injection sign is negative (`−p`), matching the toy_dc nodal-balance convention (threat T-02-01, Pitfall 2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test runner invocation adjusted for TSODSO availability**
- **Found during:** Task 2 (device @testitem verification)
- **Issue:** The plan's verify command `julia --project=. -e 'using TestItemRunner; ...'` fails two ways: `TestItemRunner` is not a dependency of the main project (it lives in `test/Project.toml`), and running under `--project=test` leaves `TSODSO` off the load path.
- **Fix:** Used `julia --project=. -e 'using Pkg; Pkg.test()'` — the authoritative runner per the environment notes — which activates the combined test env, puts `TSODSO` on the path, and runs every `@testitem` (including the two `:device` items).
- **Files modified:** none (invocation only)
- **Verification:** Full suite 91/91 pass, including both device items; RED confirmed the items errored before implementation.
- **Committed in:** n/a (no source change)

**2. [Rule 1 - Bug] Reworded device docstrings to satisfy the network-agnosticism grep gate**
- **Found during:** Task 2 (grep gate check)
- **Issue:** Initial docstrings in `AbstractDevice.jl`/`Interruptible.jl` contained the literal tokens `Feeder`, `Branch`, `feeder`, `:Rq`, which the mechanical grep gate (`grep -nE 'Feeder|Branch|feeder|\.r\b|\.x\b|:Rq' src/devices/`) flags even though they were only prose describing the decoupling.
- **Fix:** Reworded prose to "network object / network topology / line parameters / reactive residual" so the gate over `src/devices/` returns nothing while the docstrings still explain decoupling.
- **Files modified:** src/devices/AbstractDevice.jl, src/devices/Interruptible.jl
- **Verification:** `grep -rnE 'Feeder|Branch|feeder|\br\b|\bx\b|\.r\b|\.x\b|:Rq' src/devices/` → CLEAN.
- **Committed in:** `0a19f5b` (GREEN task commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both necessary to satisfy the plan's own acceptance gates (test execution + grep gate). No scope creep; contract and behavior are exactly as specified.

## Issues Encountered
None beyond the two auto-fixed items above. The "Infeasible" messages in the `Pkg.test()` output are a pre-existing status test intentionally solving an infeasible model — not a regression.

## Known Stubs
None — both device files are fully implemented; no placeholder/empty-data patterns.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- The device seam is ready for plan 02-04 (rung-1 integration): a power-flow formulation + the Interruptible load meet only at `:Rp`, and assembly can `@objective(m, Max, ctx.meta[:objective] − …)`.
- The contract generalizes to the Phase 3 device library (generators, storage, prosumers) — each adds a `contribute!` method and, if reactive, writes the reactive residual.

## Self-Check: PASSED
- Files: `src/devices/AbstractDevice.jl`, `src/devices/Interruptible.jl`, `test/test_device.jl`, `02-03-SUMMARY.md` all present.
- Commits: `f97fa0c` (T1), `cd99701` (RED), `0a19f5b` (GREEN) all in git log.

---
*Phase: 02-linear-branch-flow-residual-seam*
*Completed: 2026-07-18*
