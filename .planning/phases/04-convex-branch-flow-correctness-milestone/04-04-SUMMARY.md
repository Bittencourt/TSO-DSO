---
phase: 04-convex-branch-flow-correctness-milestone
plan: 04
subsystem: optimization
tags: [oracle, coupling-dual, seam-01, stackelberg, planning-seam, jump, solve_welfare]

# Dependency graph
requires:
  - phase: 03-* (OPT-01)
    provides: solve_welfare — the centralized GLB-CVX social-welfare solve the oracle wraps
  - phase: 04-01 (INFRA-02 / PF-03)
    provides: problem_class(pf) trait — routes the wrapped solve to the right solver factory
provides:
  - operational_oracle(feeder, pf, aggregators; λ₀, T, z, role, objective_hook, horizon_state) -> (; cost, π, dadp, ctx)
  - π = frontier coupling dual (dual of :balance_p at feeder.root), distinct from the first-aggregator DADP
  - SEAM-01 INERT extension stubs — coupling flow z↔p_ag + explicit :leader/:follower role, multi-scenario objective_hook, rolling-horizon horizon_state, meshed AbstractPowerFlow slot
affects: [planning-layer, stackelberg-nash, benders, diagonalization, stochastic, mpc, meshed-flow, phase-8, phase-9]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Oracle-as-thin-wrapper: expose the operational solve as (cost, π) for a deferred outer layer without a rewrite"
    - "Frontier coupling dual = dual of the root nodal-balance constraint (λ_j ↔ π_s bridge)"
    - "INERT typed seams: accept+validate+document extension kwargs with zero current behavior (no silent partial implementation)"

key-files:
  created: []
  modified:
    - src/models/oracle.jl
    - test/test_oracle.jl

key-decisions:
  - "π is the ROOT/frontier balance dual, deliberately distinct from solve_welfare's first-aggregator DADP (which is passed through as `dadp`) — the frontier price is what the planning game equates across the TSO↔DSO boundary"
  - "z-pin (frontier import == z) is NOT wired into solve_welfare in Phase 4; a non-nothing z returns the frontier DADP as a documented proxy and flags the pin as the PLAN-01/02 extension — no silent partial pinning (threat T-04-13)"
  - "objective_hook and horizon_state are accepted, typed and documented but carry no Phase-4 behavior; role is validated (:leader|:follower) and rejects anything else loudly"
  - "solve_welfare is wrapped, never modified; the oracle adds no new solve path and reuses the dual solve_welfare already gates behind assert_solved!(dual=true) (threat T-04-12)"

patterns-established:
  - "Additive planning seam: the operational core is queryable as an oracle so the Stackelberg-Nash layer is purely additive later"
  - "Solver-agnostic routing via select_optimizer(problem_class(pf)) inside the wrapper — the oracle names no concrete solver"

requirements-completed: [OPT-03, SEAM-01]

# Metrics
duration: ~20min
completed: 2026-07-18
---

# Phase 4 Plan 04: operational_oracle + SEAM-01 Extension Stubs Summary

**`operational_oracle` exposes the centralized GLB-CVX solve as `(cost, π, dadp, ctx)` — returning the frontier coupling dual `π` (root nodal-balance dual) as a thin, additive wrapper over `solve_welfare` — with the four SEAM-01 planning interfaces (coupling flow `z↔p_ag` + explicit leader/follower role, multi-scenario objective hook, rolling-horizon state, meshed-formulation slot) landed as inert, typed, documented stubs.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 2 completed
- **Files modified:** 2 (`src/models/oracle.jl`, `test/test_oracle.jl`)

## Accomplishments
- `operational_oracle(feeder, pf, aggregators; λ₀, T=24, z=nothing, role=:follower, objective_hook=identity, horizon_state=nothing) -> (; cost, π, dadp, ctx)` wrapping `solve_welfare`, routing via `select_optimizer(problem_class(pf))` (SOCP for ConvexBranchFlow, QP for LinDistFlow/DC) — names no concrete solver.
- `_coupling_dual(ctx, z)` returns the frontier coupling dual: the dual of the registered `:balance_p` at `feeder.root` over the horizon — the `λ_j ↔ π_s` bridge the deferred planning layer consumes, distinct from the first-aggregator DADP.
- SEAM-01 extension interfaces landed as INERT stubs with each v2 requirement named: coupling flow `z` + explicit Stackelberg `role`, multi-scenario `objective_hook`, rolling-horizon `horizon_state`, and the meshed `AbstractPowerFlow` slot (with the documented `assert_radial` bypass for a future `MeshedFlow`).
- oracle @testitems GREEN (18 assertions across 2 items): finite `cost`, finite length-`T` `π`, length-`T` `dadp`; `:leader` role returns the identical shape; an unknown role raises `ArgumentError`.

## Task Commits

Each task was committed atomically:

1. **Task 1: operational_oracle wrapper + _coupling_dual + SEAM-01 stubs** — `a23353a` (feat)
2. **Task 2: turn the oracle + SEAM-01 @testitems green** — `fb5eda0` (test)

_Note: Task 1 was TDD — its RED harness pre-existed as the Wave-1 `test_oracle.jl` stub; this plan added the GREEN implementation (feat) and then broadened the test (test)._

## Files Created/Modified
- `src/models/oracle.jl` — `operational_oracle` wrapper + `_coupling_dual` helper + SEAM-01 stub documentation; `export operational_oracle`. Wraps `solve_welfare` (unmodified), reads the `:balance_p` root dual, routes through `problem_class`/`select_optimizer`.
- `test/test_oracle.jl` — two "oracle" @testitems: finite `(cost, π, dadp)` + `ctx` shape on a LinDistFlow feeder, and the `:leader`-role inert-stub shape check plus the unknown-role `ArgumentError` guard. Inline 2-bus feeder + single-aggregator (no Phase4 fixture / SOCP dependency).

## Interfaces for Downstream

`operational_oracle` is the seam the deferred Stackelberg-Nash planning layer (Phase 8/9) queries:
- **Coupling flow / role** (PLAN-01/02): `z` (`z↔p_ag` frontier import setpoint) + returned `π` (`λ_j↔π_s`) + `role::Symbol` (`:leader`|`:follower`; PSR: distributor = leader). z-pinning is the documented extension point (add `p_import == z` and return its dual).
- **Multi-scenario objective hook** (STOCH-01/02): `objective_hook::Function` to compose per-scenario welfare.
- **Rolling-horizon parameter** (MPC-01/02): `horizon_state` → a JuMP `Parameter` (`@variable(m, s0 in Parameter(v))`) re-settable without a rebuild.
- **Meshed-formulation slot** (MESH-01): the `pf::AbstractPowerFlow` argument itself; a future `MeshedFlow` plugs in and bypasses `assert_radial`.

## Deviations from Plan

None — plan executed exactly as written. `operational_oracle` and `_coupling_dual` match the RESEARCH Pattern 6 signature; SEAM-01 stubs are inert and typed per the stub inventory; `solve_welfare` untouched.

## Threat Model Compliance
- **T-04-12 (π provenance):** π is derived solely from the registered `:balance_p` dual that `solve_welfare` already gates behind `assert_solved!(...; dual = true)`. The oracle adds no new solve path.
- **T-04-13 (stubs pretending to be implemented):** all four SEAM-01 interfaces are documented INERT with their concrete v2 requirement; the z-pin explicitly returns the frontier DADP proxy (no silent partial pinning), and an unknown role fails loudly.

## Verification
- Filtered oracle run: `TestItemRunner.run_tests(pkg; filter=ti->occursin("oracle", ti.name))` → **18/18 pass**.
- Full suite (precompiled scratch env): **491 passed, 13 failed**. All 13 failures are pre-existing Wave-1 RED items in parallel-owned suites (`test_convex_branch_flow`, `test_exactness`, `test_ieee13`, `test_conformance` SOCP arm) that fail on `isdefined(TSODSO, :ConvexBranchFlow)` / `assert_socp_exact!` / `ieee13_modified` — empty stubs in this worktree owned by 04-02/04-03/04-05, untouched by this plan. No regression attributable to this plan; every previously-green suite (welfare 120, aggregator 48, linear_solve 10, context 22, powerflow 25, devices, profiles, …) remains green.
- Only `src/models/oracle.jl` and `test/test_oracle.jl` changed vs. base `27aa079`; `solve_welfare` unmodified.

## Known Stubs

The SEAM-01 extension interfaces are INTENTIONAL, documented stubs (not accidental placeholders) — the plan's whole purpose. They are inert in Phase 4 and made concrete in later milestones:

| Stub | File | Made concrete in |
|------|------|------------------|
| Coupling flow `z` + `role` (returned `π`) | `src/models/oracle.jl` | PLAN-01/02 (Phase 8/9) |
| `objective_hook` (multi-scenario) | `src/models/oracle.jl` | STOCH-01/02 (v2) |
| `horizon_state` (rolling-horizon) | `src/models/oracle.jl` | MPC-01/02 (v2) |
| meshed `AbstractPowerFlow` slot | `src/models/oracle.jl` | MESH-01 (v2) |

These do not block the Phase-4 goal (OPT-03: expose `operational_oracle(z) → (cost, π)` returning the frontier coupling dual) — that behavior is fully implemented and tested.

## Self-Check: PASSED
- `src/models/oracle.jl` — FOUND
- `test/test_oracle.jl` — FOUND
- `.planning/phases/04-convex-branch-flow-correctness-milestone/04-04-SUMMARY.md` — FOUND
- Commit `a23353a` (Task 1) — FOUND
- Commit `fb5eda0` (Task 2) — FOUND
