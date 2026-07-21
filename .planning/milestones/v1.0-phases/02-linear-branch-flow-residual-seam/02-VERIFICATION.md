---
phase: 02-linear-branch-flow-residual-seam
verified: 2026-07-18T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
---

# Phase 2: Linear Branch-Flow Residual Seam Verification Report

**Phase Goal:** Establish the residual-seam contract everything reuses — a swappable linear power-flow (DC / LinDistFlow) and one flexible device (interruptible/elastic load) meet ONLY at the shared nodal residual Rp/Rq, and the first nodal-balance dual appears from a centralized linear solve.
**Verified:** 2026-07-18
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (Success Criterion) | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | LinDistFlow AND DC contribute branch/voltage terms into shared nodal residual with NO `if formulation ==` branching | ✓ VERIFIED | Both `contribute!` methods write via `add_to_residual!(ctx, :Rp, j, t, ...)` (DCPowerFlow.jl:58; LinDistFlow.jl:89/93). Selection is pure Julia dispatch on singleton types `DCPowerFlow`/`LinDistFlow`. grep found `if formulation ==` ONLY in comments; grep for `isa/==/typeof` type-branching returned NONE. Conformance testitem (test_conformance.jl) and powerflow testitems pass. |
| 2 | Interruptible/elastic load contributes vars + concave quadratic utility (via `add_to_objective!`, curvature retained) + signed injection into residual WITHOUT referencing network | ✓ VERIFIED | Interruptible.jl:93 creates bounded `p[t]`; line 99 injects `-p[t]` into `:Rp`; line 105 routes `Σ(a·p − (b/2)·p²)` through `add_to_objective!` (QuadExpr, curvature kept). grep of src/devices for Feeder/Branch/topology/feeder/.buses returned only docstrings + the `bus::Int` id — no network object. test_device asserts quadratic coeff `-(b/2)`, linear `+a`, negative `:Rp` injection, with NO feeder built. |
| 3 | Centralized solve closes nodal balance and exposes `dual(nodal_balance)` (first price), gated on OPTIMAL via `assert_solved!` | ✓ VERIFIED | linear_solve.jl:81 pins `balance_p == 0` and registers it (line 82); line 94 calls `assert_solved!(model; dual=true, allow_local=false)` (INFRA-03 choke point delegating to `is_solved_and_feasible`); dual read ONLY after the gate (line 98). test_linear_solve asserts `dadp ≈ λ₀`, `dadp > 0`, and OPTIMAL gate honored. |
| 4 | Swapping DC↔LinDistFlow requires NO change to device or assembly code | ✓ VERIFIED | linear_solve.jl closes `:Rq` only via `haskey(ctx.residuals, :Rq)` (line 83) — data-driven on registry CONTENTS, not a formulation flag. Conformance testitem constructs ONE `Interruptible`, calls `solve_linear` twice changing ONLY the `pf` argument (test_conformance.jl:23-26), asserts identical objective + identical DADP, both matching the derived closed form. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/core/ModelContext.jl` | Indexed `add_to_residual!(ctx,name,i,t,expr)` (AffExpr matrix) + `add_to_objective!` (QuadExpr) | ✓ VERIFIED | Indexed AffExpr matrix accumulator (lines 107-121, pinned via `convert(AffExpr,·)` so quadratics fail loudly); QuadExpr objective accumulator (lines 136-139). Wired by both pf and device code. |
| `src/powerflow/AbstractPowerFlow.jl` | Abstract type + `contribute!` generic | ✓ VERIFIED | Type + generic declared; reused (not redeclared) by devices. |
| `src/powerflow/DCPowerFlow.jl` | Active-only `:Rp` via dispatch | ✓ VERIFIED | Writes `:Rp` only, allocates no `:Rq`/voltage. Wired into solve_linear + conformance/powerflow tests. |
| `src/powerflow/LinDistFlow.jl` | `:Rp`+`:Rq`+squared-voltage var + 3.43 vdrop | ✓ VERIFIED | Creates `v`,`P`,`Q`, root fix, squared bounds, `vdrop` constraint (3.43), accumulates `:Rp`/`:Rq`. |
| `src/devices/AbstractDevice.jl` | Network-agnostic device contract | ✓ VERIFIED | Contract documents bus-id-only, `:Rp` seam, `add_to_objective!`. |
| `src/devices/Interruptible.jl` | Vars + concave-quad utility + signed injection, concavity guard | ✓ VERIFIED | `b<=0` and `Pmax<Pmin` throw ArgumentError; contribute! wires all three seam channels. |
| `src/models/linear_solve.jl` | Centralized QP solve, closes balances, returns DADP | ✓ VERIFIED | QP factory → Clarabel (accurate duals); closes every present residual; OPTIMAL gate; returns `(ctx, obj, dadp)`. |
| `test/test_conformance.jl` etc. | Conformance + analytic price + device tests | ✓ VERIFIED | All testitems present and passing. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| DCPowerFlow / LinDistFlow | ModelContext `:Rp`/`:Rq` | `add_to_residual!` indexed | ✓ WIRED | Both formulations accumulate; no overwrite, no branching. |
| Interruptible | ModelContext `:Rp` + `:objective` | `add_to_residual!` / `add_to_objective!` | ✓ WIRED | Signed `-p` injection + QuadExpr utility. |
| solve_linear | `dual(balance_p)` | `assert_solved!` → `dual.(...)` | ✓ WIRED | Dual read only post-OPTIMAL gate. |
| solve_linear | QP solver | `select_optimizer(QP())` → Clarabel | ✓ WIRED | Accurate-dual conic backend; no hard-coded solver. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | `Pass 127 / Total 127`, 0 fail, 0 error, 1m12s | ✓ PASS |
| No formulation-type branching | grep `if formulation`, `isa/==/typeof PowerFlow` in src/ | only comments; no code branch | ✓ PASS |
| Device network-agnostic | grep Feeder/Branch/topology/feeder in src/devices | only docstrings + `bus::Int` | ✓ PASS |
| Analytic price derived (not magic number) | read test_linear_solve.jl / test_conformance.jl | `expected_p=(a-λ0)/b`, `expected_dadp=λ0` derived from fixture coeffs; `dadp>0` asserted | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PF-02 | 02-01/02/04 | DC / LinDistFlow linear formulations | ✓ SATISFIED | Both formulations implemented via dispatched `contribute!`, tested (powerflow/lindistflow/conformance testitems). |
| DEV-03 | 02-01/03/04 | Interruptible/elastic-load with concave quadratic utility | ✓ SATISFIED | Interruptible with `U=Σ(a·p−(b/2)p²)`, concavity guard, network-agnostic; tested (device testitems). |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None | — | No TODO/FIXME/XXX/TBD/HACK/PLACEHOLDER in any phase-modified file. `if formulation ==` occurrences are documentation only. |

### Human Verification Required

None for the phase goal — all four success criteria are programmatically verifiable and are covered by passing tests executed independently by the verifier.

Informational (out of Phase-2 scope): VALIDATION.md carries a manual-only note "Cross-version resolve (1.10 LTS)" inherited from INFRA-01 (Phase 1). This is a CI-matrix concern (only Julia 1.11 available locally), not a Phase-2 deliverable and not part of any Phase-2 success criterion. It does not gate this phase.

### Gaps Summary

No gaps. The residual-seam contract is fully realized: DC and LinDistFlow both contribute into a shared per-(bus,t) affine `:Rp`/`:Rq` residual purely by Julia dispatch (no formulation branching, confirmed by grep and the conformance test); the Interruptible device meets the network only at `:Rp` and routes its concave-quadratic utility through the separate QuadExpr objective accumulator with curvature retained and no network reference; the centralized `solve_linear` closes every present residual, gates on OPTIMAL through `assert_solved!`, and exposes the nodal-balance dual as the first DADP; and the DC↔LinDistFlow swap changes only the `pf` argument while yielding an identical objective and DADP matching the analytically derived closed form (`DADP=λ₀`, `p*=(a−λ₀)/b`, positive price sign). Full suite: 127/127 pass.

---

_Verified: 2026-07-18_
_Verifier: Claude (gsd-verifier)_
