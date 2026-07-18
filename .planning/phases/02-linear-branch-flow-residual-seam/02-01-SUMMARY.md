---
phase: 02-linear-branch-flow-residual-seam
plan: 01
subsystem: core
tags: [julia, jump, modelcontext, residual-seam, quadexpr, include-graph, tdd, phase-2-foundation]

# Dependency graph
requires:
  - "Phase-1 ModelContext scalar residual seam + register_constraint! (plan 01-03)"
  - "Phase-1 solver factory select_optimizer(LP()/QP()) + assert_solved! choke point"
  - "Phase-1 single-ownership include graph in src/TSODSO.jl"
provides:
  - "Indexed add_to_residual!(ctx,name,i,t,expr): per-(bus,t) Matrix{AffExpr} accumulator with index-only lazy growth (no feeder handle needed) — the shared price-bearing residual seam for Phases 2-7 (PF-02)"
  - "add_to_objective!(ctx,expr): QuadExpr welfare accumulator under ctx.meta[:objective], separate from the affine residual so concave-quadratic curvature survives (eq 3.38 shape)"
  - "Scalar add_to_residual! preserved — rung-0 toy_dc regression untouched"
  - "Five comment-only Phase-2 source stubs wired into src/TSODSO.jl (DCPowerFlow, LinDistFlow, AbstractDevice, Interruptible, linear_solve) so wave-2/3 plans fill disjoint files without editing TSODSO.jl"
  - "contribute! contract docstring generalized to (pf,ctx,feeder;T) writing :Rp/:Rq via indexed add_to_residual!"
affects: [02-02, 02-03, 02-04, phase-03, phase-04, phase-06, phase-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-flavor accumulator: affine price-bearing residual (Matrix{AffExpr}) vs quadratic welfare objective (QuadExpr) — never mix (RESEARCH Pattern 4)"
    - "Index-only lazy matrix growth (network-agnostic device seam accumulates before feeder attached)"
    - "Value-type pinning as a loud-failure guard: quadratic term routed to residual errors via convert(AffExpr,·) (T-02-07)"
    - "Single-ownership include graph extended for a whole phase in one foundation plan (wave-2/3 never re-touch TSODSO.jl)"

key-files:
  created:
    - src/powerflow/DCPowerFlow.jl
    - src/powerflow/LinDistFlow.jl
    - src/devices/AbstractDevice.jl
    - src/devices/Interruptible.jl
    - src/models/linear_solve.jl
  modified:
    - src/core/ModelContext.jl
    - src/powerflow/AbstractPowerFlow.jl
    - src/TSODSO.jl
    - test/test_context.jl

key-decisions:
  - "Objective stored under ctx.meta[:objective] (not a new struct field, not a :objective residual key) — RESEARCH Open-Question Q1 resolved: no struct-field churn, residuals stay strictly affine/physical."
  - "Indexed residual sized from indices alone (max(nr,i) x max(nc,t)) — never reads ctx.meta[:feeder] — so the network-agnostic device seam can accumulate before any feeder is attached."
  - "Matrix growth via comprehension producing fresh zero(AffExpr) per new cell (no shared mutable-zero aliasing); previously-touched cells copied by reference and preserved."
  - "Stubs written comment-only (no struct/function tokens) mirroring the Phase-1 seam pattern; grep -L 'struct\\|^function' lists all five."

requirements-completed: [PF-02, DEV-03]

# Metrics
duration: ~20min
completed: 2026-07-18
---

# Phase 2 Plan 01: Linear Branch-Flow Residual Seam Foundation Summary

**Extended Phase-1's `ModelContext` with an indexed per-(bus,t) `Matrix{AffExpr}` residual accumulator and a separate `QuadExpr` welfare accumulator (`add_to_objective!` under `ctx.meta[:objective]`), keeping the affine price-bearing residual strictly separate from the quadratic utility — and wired the full Phase-2 include graph via five comment-only stubs so wave-2/3 plans fill disjoint files without ever re-touching `src/TSODSO.jl`; all 62 tests green with the rung-0 toy_dc regression and Aqua preserved.**

## What Was Built

### Task 1 — ModelContext accumulators (TDD: RED `6c05a1b` → GREEN `c70ad85`)
- New method `add_to_residual!(ctx, name::Symbol, i::Int, t::Int, expr)`: lazily allocates and grows a `Matrix{AffExpr}` under `ctx.residuals[name]`, sizing purely from the `(i,t)` indices. New cells initialize to `zero(AffExpr)`; the cell is updated with `M[i,t] += convert(AffExpr, expr)`. The `convert(AffExpr,·)` pins the value type — a quadratic term routed into the price-bearing residual fails loudly (T-02-07).
- New `add_to_objective!(ctx, expr)`: accumulates a `QuadExpr` under `ctx.meta[:objective]` (`get(...,zero(QuadExpr)) + expr`), bypassing the AffExpr conversion so the concave-quadratic utility's curvature is retained (T-02-02).
- The scalar Phase-1 `add_to_residual!(ctx, name, expr)` is untouched — toy_dc's `:nodal_balance` call site keeps working.
- Exported `add_to_objective!`; updated the module + struct docstrings to document the affine-residual / quadratic-welfare separation and cite thesis eq 3.38.
- Added four `@testitem`s (tag `:context`) covering: indexed accumulation + `Matrix{AffExpr}` type, no-feeder dynamic growth with zero-fill of untouched cells, QuadExpr accumulation retaining curvature, and scalar backward-compat.

### Task 2 — Phase-2 scaffolding + include wiring (`41d0a52`)
- Five comment-only stub files, each naming its SEAM, OWNER plan, and thesis equations: `DCPowerFlow.jl` / `LinDistFlow.jl` (owner 02-02, eqs 3.31–3.33/3.43/3.45), `AbstractDevice.jl` / `Interruptible.jl` (owner 02-03, DEV-03, eqs 3.10/3.13–3.14), `linear_solve.jl` (owner 02-04, rung-1 assembly).
- `src/TSODSO.jl` include graph extended in dependency order: powerflow formulations after `AbstractPowerFlow.jl`; a new Devices section (`AbstractDevice` before `Interruptible`) before `models/`; `models/linear_solve.jl` after `models/toy_dc.jl`.
- `contribute!` contract docstring in `AbstractPowerFlow.jl` generalized to `(pf, ctx, feeder; T::Int=1)` writing `:Rp` (and `:Rq` for reactive-capable formulations) via the indexed `add_to_residual!`, with the `haskey(ctx.residuals, :Rq)` registry-driven (not flag-driven) note for the DC↔LinDistFlow swap.

## Verification

- `julia --project=. -e 'using TSODSO'` precompiles clean (`✓ TSODSO`).
- `julia --project=. -e 'using Pkg; Pkg.test()'` → **62 pass / 62 total, exit 0**, including the `:rung0` toy_dc regression and the Aqua package-quality item (new `add_to_objective!` export introduced no ambiguities/stale-dep warnings).
- Comment-only guard: `grep -L 'struct\|^function'` lists all five stubs.
- TDD gate compliance: `test(...)` RED commit (`6c05a1b`) precedes the `feat(...)` GREEN commit (`c70ad85`); RED run confirmed 3 new context testitems errored on the missing methods before implementation.

## Deviations from Plan

None — plan executed exactly as written. No architectural changes, no auth gates, no auto-fixes required.

## Threat Mitigations Applied

- **T-02-02** (false result via silent linearization): `add_to_objective!` keeps a `QuadExpr`; test asserts `!isempty(ctx.meta[:objective].terms)` so curvature cannot be dropped.
- **T-02-07** (non-affine term tampering the price-bearing residual): indexed residual value type pinned to `Matrix{AffExpr}`; test asserts `isa Matrix{AffExpr}`; `convert(AffExpr,·)` fails loud on a quadratic input.
- **T-02-08** (broken include graph): `using TSODSO` precompile check green; single-owner wiring prevents wave-2/3 collisions.
- **T-02-SC** (supply chain): no `Pkg.add` in this plan; dependency set unchanged.

## Notes for Downstream Plans

- Wave-2/3 plans (02-02, 02-03, 02-04) fill the five stubs and MUST NOT edit `src/TSODSO.jl` — the include graph is already complete.
- Reactive channel `:Rq` is allocated on-demand by the indexed accumulator; DC formulations write `:Rp` only, and assembly should branch on `haskey(ctx.residuals, :Rq)` (registry contents), never on a formulation flag.
- Objective access for assembly (02-04): `ctx.meta[:objective]` (a `QuadExpr`), used as `@objective(m, Max, ctx.meta[:objective] - Σ_t λ₀[t]*p_import[t])`.

## Self-Check: PASSED

All created/modified files present on disk; all three per-task commits (`6c05a1b`, `c70ad85`, `41d0a52`) exist in git history.
