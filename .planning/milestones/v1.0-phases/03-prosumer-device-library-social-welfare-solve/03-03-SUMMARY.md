---
phase: 03-prosumer-device-library-social-welfare-solve
plan: 03
subsystem: devices
tags: [devices, thermostatic, deferrable, temporal-coupling, aggregatable-device, convex-qp]
requires:
  - "src/devices/AbstractDevice.jl (AbstractDevice supertype + shared contribute! generic)"
  - "src/devices/Interruptible.jl (concrete-device pattern: guards, promotion, sign convention)"
  - "src/core/ModelContext.jl (ctx.model access)"
provides:
  - "Thermostatic{T} <: AbstractDevice + contribute! (DEV-01): temp recursion 3.2, comfort band 3.3, concave utility 3.11"
  - "Deferrable{T} <: AbstractDevice + contribute! (DEV-02): energy-within-window budget 3.4-3.5, concave utility 3.12"
  - "Aggregatable-device return contract: contribute! -> (; vars, p_inject, utility)"
affects:
  - "src/devices/Aggregator.jl (plan 03-05 consumes the (; vars, p_inject, utility) tuple as sole residual writer)"
  - "src/models/welfare_solve.jl (plan 03-05 rolls device utility into GLB-CVX)"
tech-stack:
  added: []
  patterns:
    - "Aggregatable device (aggregator-as-writer, DEV-05): device builds vars/constraints on ctx.model, RETURNS terms, writes nothing to residual/objective"
    - "Immutable concretely-typed struct + throw-based inner-constructor guards + promotion outer constructor"
    - "Concave-quadratic utility as a QuadExpr (curvature retained, never routed through the affine residual)"
key-files:
  created: []
  modified:
    - "src/devices/Thermostatic.jl"
    - "src/devices/Deferrable.jl"
    - "test/test_thermostatic.jl"
    - "test/test_deferrable.jl"
decisions:
  - "Deferrable energy budget uses an EQUALITY (Σ p == E) per plan, with utility 3.12 targeting E (thesis E_max role); on the feasible set the utility is a soft target, matching a deferrable load's indifference to timing"
  - "Deferrable omits the plan's parenthetical linear coeff `a` (thesis 3.12 is a pure quadratic penalty with only curvature b) — faithful to the source equation"
  - "State IC (Tin[1]==Tin0) and window-fit / ambient-length validation are enforced; JuMP classifies the single-variable IC as an affine EqualTo (test counts both EqualTo classes to stay robust)"
metrics:
  duration: ~35m
  completed: 2026-07-18
  tasks: 2
  files: 4
---

# Phase 3 Plan 03: Thermostatic & Deferrable Aggregatable Devices Summary

Two temporally-coupled prosumer loads — Thermostatic (DEV-01, RC/ETP temperature recursion + comfort band + concave comfort utility) and Deferrable (DEV-02, energy-within-window budget + concave utility) — implemented as **aggregatable** `AbstractDevice`s that build their variables and temporal-coupling constraints on `ctx.model` and RETURN `(; vars, p_inject, utility)` while writing nothing to the residual or objective (aggregator-as-writer, DEV-05).

## What Was Built

### Task 1 — Thermostatic (DEV-01)
- `struct Thermostatic{T<:Real} <: AbstractDevice` with fields `(bus, α, β, Tmin, Tmax, Tin0, Pmin, Pmax, b, Tout)`.
- Inner-constructor throw-guards: `b ≤ 0` (concavity, thesis 3.11/3.14), `Tmax < Tmin` (band), `Pmax < Pmin` (power bounds). Promotion outer constructor for mixed-type calls (including `Tout` element promotion).
- `contribute!(d, ctx; T)`: bounded power `p[t] ∈ [Pmin,Pmax]` and temperature `Tin[t] ∈ [Tmin,Tmax]` (3.3); state IC `Tin[1] == Tin0`; RC/ETP recursion `Tin[t+1] == Tin[t] + α(Tout[t]−Tin[t]) − β·p[t]` for `t=1:T-1` (3.2); concave comfort utility `−(b/2)·Σ(Tin[t]−Tmin)²` (3.11) as a QuadExpr. Returns `(; vars=(; p, Tin), p_inject=[-p[t]], utility)`. Validates `length(Tout) ≥ T` at contribute time.

### Task 2 — Deferrable (DEV-02)
- `struct Deferrable{T<:Real} <: AbstractDevice` with fields `(bus, t_start, t_end, E, Pmax, b)`.
- Inner-constructor throw-guards: `b ≤ 0` (concavity 3.12), inconsistent window (`t_start < 1` or `t_end < t_start`), infeasible/negative budget (`E < 0` or `E > Pmax·window_length`). Promotion outer constructor.
- `contribute!(d, ctx; T)`: per-hour power `p[t] ∈ [0,Pmax]` inside the window, pinned to `0` outside (3.5); energy-window budget `Σ_{t∈[t_start,t_end]} p[t] == E` (3.4); concave utility `−(b/2)·(Σp − E)²` (3.12) as a QuadExpr. Returns `(; vars=(; p), p_inject=[-p[t]], utility)`. Validates `t_end ≤ T`.

Both devices are network-agnostic (hold only a bus id + parameters, never a `Feeder`) and call neither `add_to_residual!` nor `add_to_objective!` — verified by grep.

## Verification

- `test/test_thermostatic.jl`: 43 checks green (guards, promotion, aggregatable return contract, no-residual/objective writes, recursion 3.2 + IC verified at the solved QP optimum, ambient-profile length guard).
- `test/test_deferrable.jl`: 47 checks green (guards, promotion, return contract, no writes, energy-budget 3.4 binds at the solved optimum, window-fit guard).
- Full `Pkg.test()`: all previously-green suites remain green (device 31, context 22, conformance 6, powerflow 25, linear_solve 10, toy_dc 15, feeder 9, perunit 9, topology 8, status 2, factory 1). The only remaining failures are the Wave-0 RED stubs owned by other plans (profiles 03-02, pvbattery 03-04, aggregator/welfare 03-05) — no regression.
- Grep confirms neither device file invokes `add_to_residual!`/`add_to_objective!` nor references `Feeder`/`Branch` in code (only in docstrings stating they are NOT used).

## Deviations from Plan

None affecting behavior. Two clarifications recorded as decisions (see frontmatter): the Deferrable utility follows thesis 3.12 exactly (pure quadratic penalty, curvature `b` only) rather than adding the plan's parenthetical linear coeff `a`; and the equality energy budget makes the 3.12 utility a soft target that is exactly met on the feasible set, which is the correct economic behavior for a pure deferrable (timing-indifferent) load.

## Self-Check: PASSED
- `src/devices/Thermostatic.jl` — FOUND
- `src/devices/Deferrable.jl` — FOUND
- `test/test_thermostatic.jl` — FOUND
- `test/test_deferrable.jl` — FOUND
- Commits: cdc4f5d (test), 7dcc1d8 (feat thermostatic), 2d39779 (test), 81c631d (feat deferrable) — all present in git log.
