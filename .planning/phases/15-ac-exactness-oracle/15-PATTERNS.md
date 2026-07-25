# Phase 15: AC-Exactness Oracle - Pattern Map

**Mapped:** 2026-07-25
**Files analyzed:** 9 (create/modify)
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `src/powerflow/ACPowerFlow.jl` (CREATE) | model/formulation (JuMP `contribute!`) | request-response (build-once, solve-once) | `src/powerflow/ConvexBranchFlow.jl` | exact (peer `AbstractPowerFlow` subtype, same variable names, same residual seam) |
| `src/TSODSO.jl` (MODIFY — one `include` line) | config/module-wiring | batch (load-order include graph) | existing `include("powerflow/ConvexBranchFlow.jl")` line (`src/TSODSO.jl:47`) | exact |
| `src/powerflow/AbstractPowerFlow.jl` (MODIFY — docstring only, optional) | interface/contract | request-response | itself (already generic; likely zero-diff) | exact — no new dispatch needed, `ACPowerFlow <: AbstractPowerFlow` needs no change to this file's code, only possibly a doc mention |
| `problem_class(::ACPowerFlow) = NLP()` (goes INSIDE `ACPowerFlow.jl`, NOT `problem_class_trait.jl`) | trait/routing | request-response | `problem_class(::ConvexBranchFlow) = SOCP()` at `src/powerflow/ConvexBranchFlow.jl:241` | exact — same file-locality convention |
| `src/models/ac_oracle.jl` (CREATE) — `assert_ac_exact!` | model/validator (report, not gate) | transform (comparison → report table) | `src/models/exactness.jl` (`assert_socp_exact!`) — but diverges on throw-vs-report | role-match, deliberate behavioral divergence |
| `src/models/ac_oracle.jl` (same file) — `recover_voltage_angles` | utility (post-processing, pure Julia) | transform (BFS over solved primal) | `src/data/topology.jl` (`assert_radial`'s BFS) | role-match (BFS-shape reused; new complex-arithmetic recursion is genuinely new) |
| `test/test_ac_powerflow.jl` (CREATE) | test (unit, `@testitem`) | request-response | `test/test_convex_branch_flow.jl` | exact |
| `test/test_ac_oracle.jl` (CREATE) | test (unit+integration, `@testitem`) | request-response | `test/test_exactness.jl` — but must NOT copy its `@test_throws`-on-inexact-fixture pattern | role-match, deliberate divergence |
| Stress fixture call site (in test files, no new fixture file) | test fixture/data | batch | `test/fixtures_phase4.jl` (`Phase4Fixtures.build_high_pv_aggregators`'s existing `pv_scale` kwarg) | exact — reuse, do not duplicate |
| `docs/literate/ac_oracle.jl` (CREATE) + `docs/make.jl` (MODIFY) | docs/literate rung page | request-response (executed live by Documenter) | `docs/literate/convex_branch_flow.jl` + `docs/make.jl`'s literate tuple/pages list | exact |

## Pattern Assignments

### `src/powerflow/ACPowerFlow.jl` (CREATE)

**Analog:** `src/powerflow/ConvexBranchFlow.jl` (243 lines, read in full)

**Module header / no-solver-naming convention** (`ConvexBranchFlow.jl:1-35`):
```julia
# src/powerflow/ConvexBranchFlow.jl
#
# SEAM: SOCP Convex Branch Flow (DistFlow SOC relaxation) power-flow formulation (PF-03).
# ...
using JuMP

const _SMAX_NO_LIMIT = SMAX_NO_LIMIT   # sourced from units/PerUnit.jl — reuse the SAME const,
                                        # do not duplicate a bare literal
```
`ACPowerFlow.jl` should open the same way (`using JuMP`; reuse `_SMAX_NO_LIMIT` — either import
it or reference `TSODSO._SMAX_NO_LIMIT`/re-`const` from the same `SMAX_NO_LIMIT` source, planner's
call, but do not duplicate the literal).

**Struct + docstring convention** (`ConvexBranchFlow.jl:37,76`):
```julia
struct ConvexBranchFlow <: AbstractPowerFlow end
```
Mirror exactly: `struct ACPowerFlow <: AbstractPowerFlow end` — a zero-field singleton, dispatched
on type alone (INFRA-02: no formulation-flag branching).

**Core `contribute!` pattern — variable declaration + bounds** (`ConvexBranchFlow.jl:116-145`):
```julia
function contribute!(::ConvexBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)
    nB = length(B)

    @variable(m, v[j = 1:N, t = 1:T])
    @variable(m, v̂[j = 1:N, t = 1:T])
    @variable(m, P[b = 1:nB, t = 1:T])
    @variable(m, Q[b = 1:nB, t = 1:T])
    @variable(m, l[b = 1:nB, t = 1:T] >= 0)

    fix.(v[feeder.root, :], 1.0; force = true)
    fix.(v̂[feeder.root, :], 1.0; force = true)

    for j in 1:N, t in 1:T
        j == feeder.root && continue
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)
        set_upper_bound(v[j, t], vb.vmax^2)
        set_lower_bound(v̂[j, t], vb.vmin^2)
        set_upper_bound(v̂[j, t], vb.vmax^2)
    end
```
`ACPowerFlow.contribute!` mirrors this **verbatim except**: drop every `v̂` line (no exactness
copy variable, no `v̂` bounds, no `fix.(v̂[...])`) — nothing to force tight when the cone is
already an equality. Keep `v`, `P`, `Q`, `l` identical (same names, same bounds, same root-fix
convention, same `Pitfall 1` off-by-square-voltage discipline: `v`/`vmin^2`/`vmax^2`).

**Cone → nonconvex equality (the ONE substantive replacement)** (`ConvexBranchFlow.jl:147-158`):
```julia
    @constraint(
        m,
        cone[b = 1:nB, t = 1:T],
        [0.5 * l[b, t], v[B[b].from, t], P[b, t], Q[b, t]] in RotatedSecondOrderCone()
    )
    register_constraint!(ctx, :cone, cone)
```
Replace with a plain scalar quadratic **equality** (no cone macro — Ipopt's MOI wrapper takes a
`ScalarQuadraticFunction`-in-`EqualTo` natively, per RESEARCH Assumption A2 — verify empirically
in the first implementation plan):
```julia
    @constraint(
        m, cone[b = 1:nB, t = 1:T],
        l[b, t] * v[B[b].from, t] == P[b, t]^2 + Q[b, t]^2,
    )
    register_constraint!(ctx, :cone, cone)
```
Keep the SAME container name `:cone` and the SAME `register_constraint!` call so any downstream
code indexing `ctx.constraints[:cone]` (e.g. a future DLMP-style dual read) works unchanged
across both formulations.

**True voltage drop — IDENTICAL, copy verbatim** (`ConvexBranchFlow.jl:160-171`):
```julia
    @constraint(
        m,
        vdrop[b = 1:nB, t = 1:T],
        v[B[b].to, t] ==
        v[B[b].from, t] - 2 * (B[b].r * P[b, t] + B[b].x * Q[b, t]) +
        (B[b].r^2 + B[b].x^2) * l[b, t]
    )
    register_constraint!(ctx, :vdrop, vdrop)
```
This equation (thesis 3.33) is unaffected by the relaxation choice — copy unchanged, same
name `:vdrop`. **Drop entirely**: the `cpydrop`/`v̂` block (`ConvexBranchFlow.jl:173-187`) — no
exactness copy in `ACPowerFlow`.

**Apparent-power limit — IDENTICAL structure, convert cone to scalar quadratic**
(`ConvexBranchFlow.jl:189-206`):
```julia
    @constraint(
        m,
        smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
        [B[b].smax, P[b, t], Q[b, t]] in SecondOrderCone()
    )
    register_constraint!(ctx, :smax, smax)
```
`ACPowerFlow` writes the same convex quadratic **inequality** directly (still valid without a
cone macro under Ipopt):
```julia
    @constraint(
        m, smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
        P[b, t]^2 + Q[b, t]^2 <= B[b].smax^2,
    )
    register_constraint!(ctx, :smax, smax)
```
Same sparse, branch-indexed, `_SMAX_NO_LIMIT`-filtered container shape — byte-identical feasible
set to `ConvexBranchFlow`'s cone form.

**Residual accumulation — IDENTICAL, copy verbatim** (`ConvexBranchFlow.jl:208-227`):
```julia
    for j in 1:N, t in 1:T
        pin = sum(
            P[b, t] - br.r * l[b, t] for (b, br) in enumerate(B) if br.to == j;
            init = 0.0,
        )
        pout = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, pin - pout)

        qin = sum(
            Q[b, t] - br.x * l[b, t] for (b, br) in enumerate(B) if br.to == j;
            init = 0.0,
        )
        qout = sum(Q[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rq, j, t, qin - qout)
    end
```
Same loss-at-child convention (Pitfall 6 in the analog's own comments) — copy unchanged.

**Stash + trait registration** (`ConvexBranchFlow.jl:229-241`):
```julia
    ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)
    return ctx
end

problem_class(::ConvexBranchFlow) = SOCP()

export ConvexBranchFlow
```
`ACPowerFlow` stashes `ctx.meta[:pf_vars] = (; v, P, Q, l)` — **no `v̂`** — so `assert_ac_exact!`
can index both solved contexts by the SAME field names (`v`, `P`, `Q`, `l`) present in both.
Note (call out in the new file's docstring, per RESEARCH Pattern 1): because `:l` IS present,
`solve_welfare`'s own `haskey(ctx.meta[:pf_vars], :l)` gate (`welfare_solve.jl:256`) will ALSO
fire `assert_socp_exact!` on an `ACPowerFlow`-built `ctx` — harmlessly, since the cone is already
an equality by construction so the reported residual is ~0. Document this, do not "fix" it.
End with:
```julia
problem_class(::ACPowerFlow) = NLP()

export ACPowerFlow
```
`NLP` is imported for free — it's exported from `src/solver/ProblemClass.jl:68` (already a
project-wide export via `TSODSO`), so no new `using`/`import` is needed beyond what
`ConvexBranchFlow.jl` already has (`using JuMP`).

---

### `src/TSODSO.jl` (MODIFY)

**Analog / exact insertion point** (`src/TSODSO.jl:46-52`):
```julia
# --- SOCP Convex Branch Flow formulation (owned by plan 04-02, PF-03) ---
include("powerflow/ConvexBranchFlow.jl")

# --- Power-flow → problem-class routing trait (owned by plan 04-01, INFRA-02 / PF-03) ---
# Included AFTER the powerflow formulations (needs `AbstractPowerFlow`) and after
# solver/ProblemClass.jl (needs `QP`): it maps a formulation to its solver problem class.
include("solver/problem_class_trait.jl")
```
Add one line immediately after `include("powerflow/ConvexBranchFlow.jl")` (before the
`problem_class_trait.jl` include, matching the phase's own recommended structure):
```julia
include("powerflow/ACPowerFlow.jl")
```
No other line in `TSODSO.jl` changes. Also add the two `models/` includes for the new oracle
file, mirroring the existing `models/exactness.jl` include (`src/TSODSO.jl:73-74`):
```julia
# --- SOCP relaxation exactness gate (owned by plan 04-05, PF-04) ---
include("models/exactness.jl")
```
Insert a peer include (planner's exact placement discretion, but AFTER `welfare_solve.jl` and
`exactness.jl` since `ac_oracle.jl` reads `ModelContext.meta[:pf_vars]` populated by both SOCP
and AC solves and conceptually sits beside `exactness.jl`):
```julia
include("models/ac_oracle.jl")
```

---

### `src/models/ac_oracle.jl` (CREATE) — `assert_ac_exact!`

**Analog:** `src/models/exactness.jl` (109 lines, read in full) — **same tolerance idiom,
opposite failure-mode contract.**

**Header/ownership comment convention** (`exactness.jl:1-19`) — mirror the seam-comment style
(SEAM/OWNER lines, prose describing the invariant and threat IDs) but write a NEW description
emphasizing report-not-refuse:
```julia
# src/models/exactness.jl
#
# SEAM: SOCP relaxation exactness invariant — the price-refusal gate (PF-04).
# OWNER: plan 04-05.
# ...
# On FAILURE it THROWS, refusing to return any price...
```

**`atol + rtol·magnitude` scale-free idiom to reuse verbatim** (`exactness.jl:78-99`):
```julia
function assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    maxgap = 0.0
    maxratio = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
        gap = abs(lhs - rhs)
        tol = atol + rtol * max(abs(lhs), abs(rhs))
        maxgap = max(maxgap, gap)
        maxratio = max(maxratio, gap / tol)
    end

    maxratio <= 1 || error(
        "SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=$maxratio > 1 " *
        "(rtol=$rtol, atol=$atol; max abs |l·v−(P²+Q²)|=$maxgap) — " *
        "prices REFUSED (thesis 3.43-3.45; PF-04)",
    )
    return maxgap
end
```
**Critical divergence (Pitfall 1 in RESEARCH — do not copy the `error(...)` line):**
`assert_ac_exact!` reuses the SAME `atol + rtol * max(|lhs|,|rhs|)` per-quantity idiom, but
computes it PER-HOUR across `v`/`P`/`Q` gaps between two solved contexts and returns a full
report — it must NEVER `error(...)` on a numerical disagreement. Reserve `error(...)` only for
structural mismatches (differing `T`, missing `pf_vars` keys), exactly as `welfare_solve.jl`'s
own boundary guards do (`throw(ArgumentError(...))` pattern, `welfare_solve.jl:113-115`):
```julia
T == ctx_ac.meta[:T] || error("assert_ac_exact!: T mismatch ($T vs $(ctx_ac.meta[:T])) — " *
    "the two solves are not the same operating point")   # structural mismatch: OK to throw
```
See RESEARCH Pattern 3 (lines 294-333 of `15-RESEARCH.md`) for the full illustrative
`assert_ac_exact!` body — treat it as the recommended skeleton (`(; obj_gap, hours)` return,
`rows = NamedTuple[...]` per-hour, `exact = vgap <= atol+rtol*vmag && pgap <= atol+rtol*pmag`).

**`fail loudly, never @assert` convention** (`src/core/status.jl:1-13`, `56-64`):
```julia
if !ok
    error("""
          Solve failed — refusing to trust results:
            termination_status : $(termination_status(model))
          ...
          """)
end
```
Use `error(...)` (never `@assert`) for the structural-mismatch branch of `assert_ac_exact!`,
matching this project-wide convention.

---

### `src/models/ac_oracle.jl` (same file) — `recover_voltage_angles`

**Analog:** `src/data/topology.jl`'s `assert_radial` BFS (lines 81-107, read in full):
```julia
adj = [Int[] for _ in 1:N]
for br in branches
    push!(adj[br.from], br.to)
    push!(adj[br.to], br.from)
end
seen = falses(N)
seen[root] = true
reached = 1
queue = [root]
while !isempty(queue)
    u = pop!(queue)
    for v in adj[u]
        if !seen[v]
            seen[v] = true
            reached += 1
            push!(queue, v)
        end
    end
end
```
`recover_voltage_angles` reuses this exact BFS-over-hand-built-adjacency-list shape (`Don't Hand-
Roll`: no `Graphs.jl` dependency, consistent with this project's own existing precedent) but
walks `feeder.branches` in BOTH directions (signed branch index, per RESEARCH Pattern 4) and
accumulates a `ComplexF64` phasor at each visited bus instead of just a `seen`/`reached` count.
See RESEARCH Pattern 4 (`15-RESEARCH.md:335-393`) for the full illustrative body (children
adjacency keyed by signed branch index, `Vphasor[feeder.root,t] = sqrt(value(pv.v[...]))` seed,
BFS assigning `Vphasor[j,t] = Vphasor[i,t] - z*conj(S)/conj(Vphasor[i,t])`).

**Validation-first requirement (STATE.md flag, do not skip):** before trusting this on IEEE-13,
hand-validate on the SAME 2-bus fixture used throughout `test_convex_branch_flow.jl`/
`test_exactness.jl` (`Bus(1,0.95,1.05,true), Bus(2,0.95,1.05,false)`,
`Branch(1,2,0.01,0.02,10.0)` — see exact literal at `test_convex_branch_flow.jl:43-47` and
`test_exactness.jl:21-25`) at a fixed, hand-computable `(P,Q)`, confirming `|Vphasor[2,t]|² ≈
v[2,t]`.

---

### `test/test_ac_powerflow.jl` (CREATE)

**Analog:** `test/test_convex_branch_flow.jl` (129 lines, read in full).

**RED-guard `isdefined` pattern to mirror exactly** (`test_convex_branch_flow.jl:10-20`):
```julia
@testitem "socp: ConvexBranchFlow is a defined AbstractPowerFlow subtype (PF-03)" tags =
    [:socp] begin
    using TSODSO

    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.ConvexBranchFlow() isa TSODSO.AbstractPowerFlow
    end
end
```
Mirror with `:ACPowerFlow` / tag `[:ac_powerflow]` (use a filter-safe tag/name substring per
RESEARCH's own test-command note — `"ac_powerflow"`, not bare `"ac"`).

**`problem_class` routing test to mirror** (`test_convex_branch_flow.jl:22-34`):
```julia
@testitem "socp: ConvexBranchFlow routes to the SOCP problem class (PF-03 / INFRA-02)" tags =
    [:socp] begin
    using TSODSO
    @test isdefined(TSODSO, :ConvexBranchFlow)
    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.problem_class(TSODSO.ConvexBranchFlow()) isa TSODSO.SOCP
    end
end
```
Mirror as `@test TSODSO.problem_class(TSODSO.ACPowerFlow()) isa TSODSO.NLP`.

**`contribute!` stash test to mirror** (`test_convex_branch_flow.jl:36-68`) — SAME 2-bus fixture
literal, SAME `ModelContext(model)` + `TSODSO.contribute!(pf, ctx, feeder; T=1)` call shape,
but assert `keys(pv) == (:v, :P, :Q, :l)` (no `:v̂`) and still both `:Rp`/`:Rq` populated
(`ACPowerFlow` is reactive-capable, same as `ConvexBranchFlow`):
```julia
feeder = Feeder(
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
    [Branch(1, 2, 0.01, 0.02, 10.0)],
    1,
)
...
model = Model()
ctx = TSODSO.ModelContext(model)
TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 1)
@test haskey(ctx.meta, :pf_vars)
pv = ctx.meta[:pf_vars]
for k in (:v, :v̂, :P, :Q, :l)
    @test k in keys(pv)
end
@test haskey(ctx.residuals, :Rp)
@test haskey(ctx.residuals, :Rq)
```
For `ACPowerFlow`, drop `:v̂` from the loop and use `Model()` (no optimizer needed — same
convention: `contribute!` unit tests build against a bare, unattached `Model()`).

**End-to-end solve-through-`solve_welfare` test to mirror** (project convention, per
`test_ieee13.jl:155-170` / `test_welfare_solve.jl:71-83` — see Shared Patterns below).

---

### `test/test_ac_oracle.jl` (CREATE)

**Analog:** `test/test_exactness.jl` (190 lines, read in full) — **reuse the fixed-value-model
unit-test SHAPE, but NOT the throw-on-inexact-fixture assertion.**

**Fixed-value model construction pattern to mirror (structure only)**
(`test_exactness.jl:11-49`):
```julia
@testitem "exact: assert_socp_exact! throws on an inexact relaxation, refusing prices (PF-04)" tags =
    [:exact] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    @test isdefined(TSODSO, :assert_socp_exact!)

    if isdefined(TSODSO, :assert_socp_exact!)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:N, 1:T]); @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T]); @variable(model, Q[1:B, 1:T]); @variable(model, l[1:B, 1:T])
        fix.(v, 1.0; force = true); fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true); fix.(Q, 0.0; force = true); fix.(l, 1.0; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)

        @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    end
end
```
`assert_ac_exact!` tests need TWO solved `ModelContext`s (one per formulation) — do NOT build
a single fixed-value ctx and call `assert_ac_exact!` on it alone; instead build (or reuse) a
solved `ctx_socp` (via `solve_welfare(..., ConvexBranchFlow(), ...)`) and `ctx_ac` (via
`solve_welfare(..., ACPowerFlow(), ...)`) on the SAME feeder/aggregators/λ₀/T/allow_export, per
RESEARCH Pattern 2.

**High-PV stress-fixture test to mirror STRUCTURE from, but INVERT the assertion polarity**
(`test_exactness.jl:138-190`):
```julia
@testitem "exact: high-PV / over-voltage SOCP solve stays exact, prices NOT refused (PF-04)" tags =
    [:exact] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
    ...
    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()

    pf = TSODSO.ConvexBranchFlow()
    ctx, obj, dadp = solve_welfare(
        feeder, pf, aggs;
        T = Phase4Fixtures.T, λ₀ = λ₀,
        optimizer = select_optimizer(problem_class(pf)),
        allow_export = true,
    )
    @test haskey(ctx.meta, :socp_maxgap)
    maxgap = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    @test maxgap < 1e-5
    ...
end
```
For `test_ac_oracle.jl`'s STRESS test, use `setup = [Phase4Fixtures]` identically, but call
`Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = <tuned higher value, e.g. 1.0-2.0>)`
(the `pv_scale` kwarg ALREADY EXISTS — `fixtures_phase4.jl:218-233` — no new fixture code
needed) to pin `v[j,t]` at `vmax²`, then run BOTH solves and `assert_ac_exact!`, asserting the
report shows `exact = false` for at least one hour — **this is a POSITIVE (expected-gap) test,
NOT an `@test_throws`.** See RESEARCH's own explicit warning (Pitfall 1, "Warning signs: Any
test asserting `@test_throws Exception assert_ac_exact!(...)` on a HIGH-PV/inexact fixture...is
a signal the design has drifted toward the wrong shape").

**Pitfall-3 guard (`allow_export` must match across both calls)** — per
`fixtures_phase4.jl:204-216`'s own calibration comment and `test_exactness.jl:159-167`'s usage:
the high-PV fixture is INFEASIBLE at `allow_export=false`; both `solve_welfare` calls
(SOCP and AC) in the same test item MUST pass `allow_export = true` identically.

---

### Stress fixture (extend existing `Phase4Fixtures`, no new file)

**Analog / exact call site to reuse** (`test/fixtures_phase4.jl:218-233`):
```julia
function build_high_pv_aggregators(feeder; seed::Integer = 20260406)
    N = length(feeder.buses)
    return [
        _house_aggregator(
            feeder, bus;
            seed = seed, φ = 0.95,
            pv_scale = 0.5,       # PV > load ⇒ reverse flow / over-voltage (≈1.04 pu), EXACT
            load_scale = 0.2,
            batt_pmax = 0.1, batt_emax = 0.2, batt_soc0 = 0.1,
        ) for bus in 2:N
    ]
end
```
The `pv_scale` kwarg is ALREADY threaded through `_house_aggregator` (`fixtures_phase4.jl:118-
128`) and `build_high_pv_aggregators` (`fixtures_phase4.jl:218`, default `0.5`). The stress test
calls `Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = <tuned>)` directly — **no
new fixture function, no new file.** The existing docstring's own "Calibration note"
(`fixtures_phase4.jl:209-216`) explicitly documents that `pv_scale ≫ 0.5` pins voltage at
`V²max`, the exact regime EXACT-04 targets. Tune the exact scale value empirically during
implementation (RESEARCH Open Question 1 recommends starting around `1.0-2.0`).

---

### `docs/literate/ac_oracle.jl` (CREATE) + `docs/make.jl` (MODIFY)

**Analog:** `docs/literate/convex_branch_flow.jl` (91 lines, read in full).

**Literate page structure to mirror** (`convex_branch_flow.jl:1-42`):
```julia
# # Rung 3 — SOCP Convex Branch-Flow & the LinDistFlow Exactness Copy
#
# This page proves the SOCP branch-flow relaxation ([`ConvexBranchFlow`](@ref)) — the
# project's correctness keystone — is EXACT on a real radial feeder, by calling the
# real [`solve_welfare`](@ref) end-to-end and displaying the exactness certificate
# `solve_welfare` computed internally. Never a re-implemented cone or voltage-drop
# constraint.
#
# ## The SOCP + exactness-copy math
# ...
using TSODSO

buses = [
    Bus(1, 0.95, 1.05, true),
    Bus(2, 0.95, 1.05, false),
]
branches = [Branch(1, 2, 0.01, 0.02, 10.0)]
feeder = Feeder(buses, branches, 1)

device = Deferrable(2, 1, 1, 0.5, 1.0, 1.0)
agg = Aggregator(2, 0.95, [device], [0.2])

ctx, objective, dadp =
    solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = 1, λ₀ = [1.0], allow_export = true)

objective
dadp
ctx.meta[:socp_maxgap]
```
`ac_oracle.jl` mirrors this shape: build the SAME (or the Phase4Fixtures high-PV) feeder/agg,
run BOTH `solve_welfare(..., ConvexBranchFlow(), ...)` and `solve_welfare(..., ACPowerFlow(),
...)`, call `assert_ac_exact!(ctx_socp, ctx_ac; ...)`, and display the returned report — a real,
solved comparison, never a hardcoded placeholder (same "the rendered numbers cannot drift from
the real `src/` code" discipline stated in `docs/make.jl`'s own header comment). Per RESEARCH
Open Question 3, include a one-paragraph citation of Farivar & Low 2013 / Gan, Li, Topcu & Low
2015 near the math section, mirroring `convex_branch_flow.jl`'s own inline `math` blocks
(`convex_branch_flow.jl:9-38`).

**`docs/make.jl` registration — exact two edits needed** (`docs/make.jl:19-27`, `56-62`):
```julia
for src in (
    "toy_dc.jl",
    "lindistflow.jl",
    "convex_branch_flow.jl",
    "prosumer_welfare.jl",
    "pricing_dlmp.jl",
    "admm.jl",
    "stackelberg_benders.jl",
    "nash_diagonalization.jl",
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src),
        GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end
...
pages = [
    "Home" => "index.md",
    "Models" => [
        "Rung 0: Toy DC" => "generated/toy_dc.md",
        "Rung 1-2: LinDistFlow" => "generated/lindistflow.md",
        "Rung 3: SOCP + Exactness" => "generated/convex_branch_flow.md",
        "Rung 3: Devices + GLB-CVX" => "generated/prosumer_welfare.md",
        "Rung 4: DADP/DLMP Pricing" => "generated/pricing_dlmp.md",
        "Rung 5: ADMM Decomposition" => "generated/admm.md",
    ],
    ...
```
Add `"ac_oracle.jl"` to the literate source tuple (any position — alphabetical/thematic
placement near `"convex_branch_flow.jl"` is most readable) AND add a matching
`"Rung 3: AC-Exactness Oracle" => "generated/ac_oracle.md"` entry under `"Models"` in `pages`.
Both edits are required — `checkdocs = :exports` (`docs/make.jl:75`) will fail the build if a
new exported symbol's docstring isn't surfaced anywhere in the manual, and the literate tuple
must include the source or `generated/ac_oracle.md` never gets created.

## Shared Patterns

### No-solver-naming / problem-class trait (INFRA-02)
**Source:** `src/solver/factory.jl:32-66`, `src/solver/ProblemClass.jl:1-68`,
`src/solver/problem_class_trait.jl:20-38`
**Apply to:** `ACPowerFlow.jl` (defines `problem_class(::ACPowerFlow) = NLP()` INSIDE the
formulation file, exactly where `ConvexBranchFlow.jl:241` does for `SOCP()` — never inside
`problem_class_trait.jl`, which holds only the GENERIC `QP()` fallback).
```julia
# src/solver/factory.jl:66
select_optimizer(::NLP) = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
```
No change needed to this file — `NLP()` is already wired.

### Cross-solver re-solve call shape (dispatch through `solve_welfare` unchanged)
**Source:** `test/test_ieee13.jl:155-170`, `test/test_welfare_solve.jl:71-83`
**Apply to:** any file that builds `ctx_ac` (the new `ACPowerFlow` peer) alongside an existing
`ctx_socp` — `test_ac_oracle.jl`, `docs/literate/ac_oracle.jl`.
```julia
_ctx2, obj2, _dadp2 = solve_welfare(
    feeder, ConvexBranchFlow(), aggs;
    T = 24, λ₀ = λ₀,
    optimizer = select_optimizer(NLP()),
    allow_local = true,
    allow_export = true,
)
@test isapprox(res.cost, obj2; rtol = 1e-3, atol = 1e-3)
```
Phase 15's own call is structurally IDENTICAL except `pf = ACPowerFlow()` is a genuinely
different formulation (not a bridge-based re-solve of the SAME cone) — same kwargs
(`optimizer = select_optimizer(NLP())`, `allow_local = true`, matching `allow_export`).

### `error(...)`, never `@assert` (project-wide convention)
**Source:** `src/core/status.jl:1-13,56-64`, `src/models/exactness.jl:101-105`,
`src/models/welfare_solve.jl:113-115,223-225,229-231`
**Apply to:** `assert_ac_exact!`'s structural-mismatch branch ONLY (never its numerical-gap
branch — see the dedicated divergence note above).
```julia
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
```

### `register_constraint!` / `add_to_residual!` seam (PF-01/PRICE-02)
**Source:** `src/core/ModelContext.jl:67-101`, used throughout `ConvexBranchFlow.jl:158,171,187,206,219,226`
**Apply to:** every named constraint in `ACPowerFlow.contribute!` (`:cone`, `:vdrop`, `:smax`)
and every residual write (`:Rp`, `:Rq`) — same call shape, same container names as
`ConvexBranchFlow`, so any tooling that indexes `ctx.constraints[:vdrop]` etc. works across
both formulations without branching.

## No Analog Found

None — every file in this phase has a direct or role-matched analog already read in full this
session. The one genuinely NEW piece of math (the Baran-Wu phasor recursion in
`recover_voltage_angles`) has no *implementation* analog in this codebase (flagged by the
project's own `.planning/STATE.md`), but its *algorithmic shape* (BFS over a hand-built
adjacency list) is directly modeled on `src/data/topology.jl`'s `assert_radial`, so it is
classified as role-matched, not analog-free.

## Metadata

**Analog search scope:** `src/powerflow/`, `src/models/`, `src/solver/`, `src/data/`,
`src/core/`, `test/`, `docs/literate/`, `docs/make.jl` — all read directly this session (no
`Glob`/`Grep` scan needed beyond directory listing; RESEARCH.md had already named every analog
correctly and this pass verified each against live code with zero drift).
**Files scanned:** `src/powerflow/AbstractPowerFlow.jl`, `src/powerflow/ConvexBranchFlow.jl`,
`src/models/exactness.jl`, `src/models/welfare_solve.jl`, `src/solver/ProblemClass.jl`,
`src/solver/problem_class_trait.jl`, `src/solver/factory.jl`, `src/TSODSO.jl`,
`src/data/topology.jl`, `src/data/Feeder.jl`, `src/core/ModelContext.jl`, `src/core/status.jl`,
`test/test_convex_branch_flow.jl`, `test/test_exactness.jl`, `test/fixtures_phase4.jl`,
`test/test_ieee13.jl` (lines 140-180), `test/test_welfare_solve.jl` (lines 55-95),
`test/runtests.jl`, `docs/literate/convex_branch_flow.jl`, `docs/make.jl`.
**Pattern extraction date:** 2026-07-25
