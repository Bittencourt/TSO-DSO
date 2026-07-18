---
phase: 01-plumbing-solver-abstraction
reviewed: 2026-07-18T00:00:00Z
depth: deep
files_reviewed: 12
files_reviewed_list:
  - src/TSODSO.jl
  - src/units/PerUnit.jl
  - src/data/Feeder.jl
  - src/data/topology.jl
  - src/solver/ProblemClass.jl
  - src/solver/factory.jl
  - src/core/ModelContext.jl
  - src/core/status.jl
  - src/powerflow/AbstractPowerFlow.jl
  - src/models/toy_dc.jl
  - ext/TSODSOGurobiExt.jl
  - ext/TSODSOMosekExt.jl
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-07-18
**Depth:** deep
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Phase 1 delivers a clean, well-documented walking-skeleton spine: per-unit base + magnitude
tripwires, an immutable validating `Feeder`, sparse-incidence radial validation, a
singleton-dispatch solver factory, a residual-registry `ModelContext`, a status choke point, the
abstract power-flow contract, two weakdep solver extensions, and an end-to-end toy DC solve. The
solver-abstraction convention (models never name a concrete solver) is respected — `toy_dc.jl` goes
through `select_optimizer(LP())` and only `factory.jl` + `ext/*` reference concrete solvers. The
extension wiring, `commercial_optimizer` fallback dispatch, and `MOI`-in-scope usage in `status.jl`
(`using JuMP` re-exports `MOI`) are all correct.

I ran the toy solve end-to-end to check the flagged dual concern: **objective = 2.0** and
**`dual(balance) = +1.0`**. The dual sign and extraction are correct — the price equals the marginal
import cost (positive, economically sensible), so there is **no dual-sign bug**. The BFS/edge-count
tree check is logically sound (connected ∧ `B == N-1` ⟺ tree; parallel-edge and self-loop cases are
caught via the disconnection branch, confirmed against the tests).

No correctness defect produces wrong output on a Phase-1 code path, so there are **no BLOCKERs**. The
findings below are genuine gaps in the validation completeness and test strength that are latent
silent-wrong hazards for Phase 2+ and should be closed while the seams are still small.

## Warnings

### WR-01: `assert_radial` never checks that `root` index matches the `is_root`-flagged bus

**File:** `src/data/topology.jl:32-84` (consumed by `src/data/Feeder.jl:62-71`)
**Issue:** The validator independently checks (a) `1 ≤ root ≤ N` and (b) exactly one bus has
`is_root == true`, but never checks that these agree. I constructed and confirmed a feeder that
passes validation with `feeder.root = 2` while the `is_root == true` bus is bus 1. The struct's
stated guarantee ("an invalid feeder can never exist", `Feeder.jl:6-9,50-51`) is therefore
overstated: the stored frontier index and the frontier flag can silently disagree. Phase 2+
substation/frontier logic that reads `feeder.root` in one place and scans `is_root` in another would
silently operate on two different buses — a classic silent-wrong hazard.
**Fix:** Add a consistency check inside `assert_radial` (or the constructor):
```julia
buses[root].is_root || throw(ArgumentError(
    "Feeder root index $root does not point to the is_root-flagged bus."))
```
Or derive `root` from the flag (`root = findfirst(b -> b.is_root, buses)`) and drop the redundant
argument entirely.

### WR-02: Magnitude invariant is enforced with `@assert`, which the Julia manual says may be elided

**File:** `src/units/PerUnit.jl:59-101`
**Issue:** `assert_magnitudes` / `assert_magnitudes_voltage` are described as the per-unit
"validation gate" run at construction (`Feeder.jl:69`), yet they enforce it with `@assert`. The
Julia docs explicitly warn that `@assert` "might be disabled at various optimization levels" and
"should only be used as a debugging tool," never as a validation gate that must always run. This is
also inconsistent with `topology.jl`, which correctly uses `throw(ArgumentError(...))` for its
invariant. If assertions are ever disabled in a build, the SI/pu-mixing tripwire silently vanishes,
letting plausible-wrong data through.
**Fix:** Convert the magnitude checks to explicit throws, mirroring `topology.jl`:
```julia
VOLTAGE_PU_MIN ≤ bus.vmin ≤ bus.vmax ≤ VOLTAGE_PU_MAX || throw(ArgumentError(
    "voltage bounds [$(bus.vmin), $(bus.vmax)] out of per-unit band ... at bus $(bus.id)"))
```

### WR-03: Documented `bus.id == 1-based position` convention is unenforced

**File:** `src/data/Feeder.jl:16,24-29`; `src/data/topology.jl:13-14,47-59`
**Issue:** All topology/incidence code indexes by *position* (`adj[br.from]`, `sparse(..., N, B)`)
and the whole framework assumes `bus.id` equals its 1-based position, but nothing verifies it. A
caller who builds `buses` whose `id` fields do not match their positions (e.g. mislabeled or
reordered) produces incidence/adjacency indexed inconsistently with `bus.id`, with no error — a
silent-wrong hazard the moment any later layer indexes by `id`.
**Fix:** Assert the convention at construction:
```julia
all(i -> buses[i].id == i, eachindex(buses)) || throw(ArgumentError(
    "Bus ids must equal their 1-based position in `buses`."))
```

### WR-04: Keystone integration test only checks `isfinite`, not the known optimum

**File:** `test/test_toy_dc.jl:2-17`
**Issue:** `solve_toy_dc` is the phase's end-to-end proof, yet the test asserts only
`isfinite(obj)` and `isfinite(λ)`. The problem has a known closed-form optimum (I verified
`obj == 2.0`, `p_load == p_import == 1.0`, `dual(balance) == 1.0`). As written, a regression in the
objective coefficients (`toy_dc.jl:57`), the balance-residual sign (`:53-54`), or the dual
extraction would still return finite numbers and the test would pass green — defeating the entire
purpose of a walking-skeleton keystone. This is a test-reliability defect, not a style nit.
**Fix:** Pin the numeric result:
```julia
@test obj ≈ 2.0 atol = 1e-8
@test λ   ≈ 1.0 atol = 1e-8
```

## Info

### IN-01: Sparse incidence `A` is computed then discarded by the constructor

**File:** `src/data/topology.jl:43-51,83`; `src/data/Feeder.jl:68`
**Issue:** `assert_radial` builds and returns the `N × B` sparse incidence matrix, and its docstring
says it is "returned for reuse by the model layer," but the `Feeder` inner constructor calls it only
for its side effects and throws `A` away. The `Feeder` struct stores no incidence, so any later layer
must recompute it. Either dead work now or a missed caching opportunity.
**Fix:** Store `A` on `Feeder` (add an `incidence` field populated in the constructor), or drop the
return value and the "returned for reuse" claim to avoid implying a contract that is not kept.

### IN-02: Out-of-range branch endpoints surface as a cryptic `sparse` error

**File:** `src/data/topology.jl:47-51`
**Issue:** A branch referencing a bus index outside `1:N` does throw `ArgumentError` (so the
exception-type contract holds), but the message comes from `SparseArrays.sparse` ("row index out of
range"), not a domain message — confusing next to the file's otherwise clear "Non-radial feeder"
errors.
**Fix:** Add an explicit endpoint-range check before building the incidence:
```julia
for (b, br) in enumerate(branches)
    (1 ≤ br.from ≤ N && 1 ≤ br.to ≤ N) || throw(ArgumentError(
        "Branch $b endpoints ($(br.from)->$(br.to)) out of range 1:$N."))
end
```

### IN-03: `add_to_residual!` hard-converts to `AffExpr`, silently constraining future contributions

**File:** `src/core/ModelContext.jl:66-70`
**Issue:** On first insert the accumulator is forced to `AffExpr` via `convert(AffExpr, expr)`. This
is correct for Phase 1, but a Phase-2+ formulation contributing a `QuadExpr` (e.g. an SOCP/quadratic
term) into the same residual would hit a `convert` error or a type promotion that is easy to miss.
Not a defect today; flag so the seam's element-type assumption is a conscious decision when concrete
formulations land.
**Fix:** No change required for Phase 1. When Phase 2 adds nonlinear contributions, revisit whether
the accumulator should be typed more permissively (e.g. `Any` with `add_to_expression!`).

---

_Reviewed: 2026-07-18_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
