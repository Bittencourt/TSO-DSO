# Phase 20: Overvoltage-Capable Relaxation - Pattern Map

**Mapped:** 2026-08-08
**Files analyzed:** 6 (5 new, 1 modified-in-place-only-if-needed)
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/powerflow/RestrictedBranchFlow.jl` (NEW) | model/formulation (`AbstractPowerFlow` subtype) | transform (JuMP model-build, delegates + one bound edit) | `src/powerflow/ACPowerFlow.jl` | exact (same seam: new formulation type, `contribute!`, `problem_class`, `export`) |
| `src/models/restriction_exactness.jl` (NEW, name at discretion e.g. `assert_restriction_exact!`) | certificate/validator | transform (post-solve, no solve) | `src/models/complementarity_4q.jl` (`assert_4q_complementarity!`) for throw/report + measured-tolerance docstring provenance; `src/models/ac_oracle.jl` (`assert_ac_exact!`) for the AC-cross-check comparison shape | exact (both are direct structural + provenance-style analogs; certificate is a hybrid of the two) |
| `src/models/ac_oracle.jl` (MODIFIED — add small `v̂_GL` post-processing helper, e.g. `recover_lossfree_shadow_voltage`) | utility (pure post-processing) | transform | same file's existing `recover_voltage_angles` | exact (peer function, same file, same "no new JuMP var, reads solved ctx" contract) |
| Nonconvex-AC-dual fallback (OVR-03/D-09/D-10) — lands as a function in `src/models/restriction_exactness.jl` or a new `src/models/ac_dual_fallback.jl` | service (dispatch orchestration) | request-response (calls `solve_welfare` a second time, tags result) | `src/models/welfare_solve.jl`'s `solve_welfare` dispatch seam + `test/test_ac_oracle.jl`'s 2-start Ipopt pattern | role-match (dispatch seam is exact; multi-start harness is the closest behavioral analog) |
| `test/test_restricted_branch_flow.jl` (NEW) | test | request-response / unit | `test/test_ac_oracle.jl` (EXACT-04 `@testitem`, `Phase4Fixtures` setup, 2-start guard) | exact |
| `docs/literate/restricted_branch_flow.jl` (NEW) | doc/literate rung page | transform (live-executed narrative) | `docs/literate/ac_oracle.jl` | exact |

## Pattern Assignments

### `src/powerflow/RestrictedBranchFlow.jl` (formulation, transform)

**Analog:** `src/powerflow/ACPowerFlow.jl` (the v2.1 "add a new `AbstractPowerFlow` subtype" precedent) and `src/powerflow/ConvexBranchFlow.jl` (the formulation being restricted/delegated to).

**Header/provenance-comment pattern** (`ACPowerFlow.jl` lines 1-35):
```julia
# src/powerflow/ACPowerFlow.jl
#
# SEAM: independent nonconvex AC-OPF branch-flow oracle (EXACT-01).
# OWNER: plan 15-01.
#
# A genuinely INDEPENDENT peer to `ConvexBranchFlow`: ...
# Dispatched through the EXISTING `solve_welfare` entrypoint with ZERO change to that file: ...
```
Follow this exact header shape for `RestrictedBranchFlow.jl`: state the SEAM id (e.g. `OVR-01`), the OWNER plan, and explicitly note "dispatched through the EXISTING `solve_welfare` entrypoint with ZERO change to that file."

**Struct + kwarg-constructor pattern** (mirrors `ConvexBranchFlow.jl` line 76 `struct ConvexBranchFlow <: AbstractPowerFlow end`, adapted for a field per D-03's kwarg):
```julia
struct RestrictedBranchFlow <: AbstractPowerFlow
    ε::Float64   # Gan–Low "modification gap" margin, V² units; measured default
end
RestrictedBranchFlow(; ε::Real = EXACT04_MEASURED_ε) = RestrictedBranchFlow(Float64(ε))
```

**Core delegation + bound-edit pattern** (RESEARCH.md's own worked example, itself built from `ConvexBranchFlow.jl` lines 116-145's variable/bound-setting loop):
```julia
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)   # delegate: identical SOCP+cone+exactness copy
    pv = ctx.meta[:pf_vars]
    for j in 1:length(feeder.buses), t in 1:T
        j == feeder.root && continue
        set_upper_bound(pv.v[j, t], feeder.buses[j].vmax^2 - pf.ε)   # Gan–Low OPF-ε
    end
    ctx.meta[:restriction_ε] = pf.ε        # D-08 provenance marker
    return ctx
end
```
Mirror `ConvexBranchFlow.jl`'s bound-setting loop shape (lines 138-145) EXACTLY for the shrink loop (same `j == feeder.root && continue` guard, same `feeder.buses[j].vmax^2` access), but call `set_upper_bound` again (JuMP allows re-tightening an already-bounded variable) rather than duplicating variable creation.

**Dispatch/trait registration pattern** (`ConvexBranchFlow.jl` lines 236-243, `ACPowerFlow.jl` lines 213-221):
```julia
problem_class(::RestrictedBranchFlow) = SOCP()   # same Clarabel tight-tolerance factory
export RestrictedBranchFlow
```

**Module registration:** add `include("powerflow/RestrictedBranchFlow.jl")` to `src/TSODSO.jl` immediately after `include("powerflow/ACPowerFlow.jl")` (line 52) — mirrors how `ACPowerFlow.jl` (line 52) was added right after `ConvexBranchFlow.jl` (line 47) with the comment "Included immediately after ConvexBranchFlow.jl (it references the `_SMAX_NO...` sentinel)"; `RestrictedBranchFlow` similarly depends on `ConvexBranchFlow` (delegation call) so must be included after it.

**Anti-pattern warning (from RESEARCH.md, load-bearing):** do NOT touch `v̂`'s own bound (the existing thesis exactness copy, `ConvexBranchFlow.jl` lines 143-144) — only shrink `v`'s bound (line 142's `set_upper_bound(v[j,t], vb.vmax^2)` counterpart). `v̂` is a *different*, lower-bound shadow; shrinking it is either a no-op or a silent double-restriction.

---

### `src/models/restriction_exactness.jl` (certificate, transform)

**Analog 1 (throw/report + provenance-table docstring style):** `src/models/complementarity_4q.jl` (`assert_4q_complementarity!`).

**Header/provenance pattern** (lines 1-19):
```julia
# src/models/complementarity_4q.jl
#
# SEAM: 4Q-BESS post-solve complementarity certificate (MESH-04 clause 2).
# OWNER: plan 19-05.
#
# Defines `assert_4q_complementarity!(ctx; rtol, atol, report)`: a NEW, named certificate,
# a peer of `assert_socp_exact!` (`exactness.jl`) and `assert_battery_complementarity!`
# (`welfare_solve.jl`), that numerically checks ... Its `rtol`/`atol` defaults are MEASURED
# against this device's own Clarabel-solved noise floor at the COMMITTED production
# fixtures' per-unit scales (D-07) — never copied from another certificate's tuned
# constant (certificate-laundering guard).
```
Reuse this exact framing for the new file's header: name the SEAM (`OVR-02`), name the peer certificates (`assert_socp_exact!`, `assert_ac_exact!`), and state the measured-not-copied tolerance discipline up front.

**Throw-by-default / `report` kwarg neutralization pattern** (lines 120-161, the mechanism D-06 requires):
```julia
function assert_4q_complementarity!(
    ctx::ModelContext;
    rtol::Real = 1e-4,
    atol::Real = 1e-8,
    T::Int = ctx.meta[:T],
    report::Bool = false,
)
    ...
    for t in 1:T
        ...
        prod <= tol && continue
        msg = "... violated at ... — see ... docstring"
        if report
            @warn msg
        else
            error(msg)
        end
    end
    return maxratio
end
export assert_4q_complementarity!
```
Copy this `if report ... @warn ... else ... error(...) end` shape verbatim for the new certificate's AC-feasibility gate (D-06/D-09).

**Measured-tolerance docstring provenance pattern** (lines 63-107 — the exact style D-07 mandates): a `# Tolerance provenance (D-07 ...)` subsection with a literal measured-noise-floor table (scale → observed gap → chosen default → margin multiplier), explicitly contrasting against the OTHER certificate's tolerance to show it was NOT copied:
```
Re-measured noise floors (...):
    scale = 0.1    pu  max p_ch·p_dch ≈ 4.2e-8 .. 6.3e-8   (rel to scale²: 4.2e-6 .. 6.3e-6)
    ...
The chosen defaults size EACH term ~an order above its OWN measured floor ...
  - `rtol = 1e-4` — ≈16× above the measured relative floor ...
  - `atol = 1e-8` — ≈16× above the measured absolute floor ...
```
The new certificate MUST include an equivalent table measured on the actual EXACT-04 (`Phase4Fixtures.high_pv_feeder()` at `pv_scale=1.2`) restricted-vs-AC residual — per RESEARCH.md's explicit instruction, expect the residual to collapse from `≈10.4` to `~1e-6`–`~1e-7`; derive `rtol`/`atol` from THAT measurement, never from `assert_ac_exact!`'s `1e-4`/`1e-6` or `assert_socp_exact!`'s numbers.

**Analog 2 (the AC-cross-check comparison shape + named-tuple, never-bare-Bool return):** `src/models/ac_oracle.jl` (`assert_ac_exact!`, lines 112-186).

```julia
function assert_ac_exact!(ctx_socp::ModelContext, ctx_ac::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
    T = ctx_socp.meta[:T]
    T == ctx_ac.meta[:T] || error("assert_ac_exact!: T mismatch (...) — the two solves are not the same operating point")
    ...
    rows = NamedTuple[]
    for t in 1:T
        vgap = maximum(abs(value(pv_s.v[j, t]) - value(pv_a.v[j, t])) for j in 1:N)
        ...
        exact = vgap <= atol + rtol * vmag && pgap <= atol + rtol * pmag
        push!(rows, (; t, vgap, pgap, qgap, exact))
    end
    obj_gap = objective_value(ctx_socp.model) - objective_value(ctx_ac.model)
    return (; obj_gap, hours = rows)
end
```
The new certificate should structurally borrow this per-hour comparison loop (restricted-ctx vs AC-ctx, `atol + rtol*magnitude` combined bound) for its AC-feasibility half, but change the CONTRACT: `assert_ac_exact!` never throws on disagreement (a gap is a finding); the new certificate MUST throw by default (D-06, matching `assert_4q_complementarity!`'s contract, not `assert_ac_exact!`'s). Also add the D-05 optimality-loss report as a second named field (e.g. `optimality_loss = objective_value(ctx_restricted.model) - unrestricted_cost`), returned in the SAME namedtuple, never silently folded into `obj_gap`.

**Recommended combined signature** (per RESEARCH.md's own sketch, consistent with both analogs):
```julia
function assert_restriction_exact!(
    ctx_restricted::ModelContext, ctx_ac::ModelContext;
    rtol::Real = <own EXACT-04-derived value>,
    atol::Real = <own EXACT-04-derived value>,
    unrestricted_cost::Union{Real,Nothing} = nothing,
    report::Bool = false,
) -> (; ac_feasible::Bool, optimality_loss, hours, ...)
```

**Error-message style convention (project-wide, verify in `src/core/status.jl`):** always `error(...)`, never `@assert` (elided under `-O`) — confirmed at the top of `exactness.jl`, `ac_oracle.jl`, and `complementarity_4q.jl` alike.

---

### `src/models/ac_oracle.jl` — new `v̂_GL` post-processing helper (utility, transform)

**Analog:** the SAME file's existing `recover_voltage_angles` (lines 31-110) — the precedent for "a pure post-processing function, no new JuMP variable, reads an already-solved context only" landing in this exact file.

**Pattern to mirror** (docstring shape, lines 31-63, and the BFS/adjacency-build style, lines 64-109):
```julia
"""
    recover_voltage_angles(ctx::ModelContext) -> Matrix{ComplexF64}

Recover the TRUE voltage phasors ... from a solved branch-flow `ModelContext` ...
This is pure POST-PROCESSING over an already-solved (v, P, Q, l) point — it creates no JuMP
variable and invokes no solver. It reads `ctx.meta[:feeder]`, `ctx.meta[:T]`, and
`ctx.meta[:pf_vars]` ... only, and writes nothing back to `ctx`.
"""
function recover_voltage_angles(ctx::ModelContext)
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)
    children = [Tuple{Int, Int}[] for _ in 1:N]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b))
        push!(children[br.to], (br.from, -b))
    end
    ...
end
```
The new `v̂_GL` helper (RESEARCH.md calls it e.g. `recover_lossfree_shadow_voltage`) should reuse this SAME signed-branch adjacency build (a bottom-up post-order accumulation of `r*l`/`x*l` losses, then a top-down `v̂_GL[to] = v̂_GL[from] - 2*(r*P̌ + x*Q̌)` recursion) — same "reads `ctx.meta[:pf_vars]`/`[:feeder]`/`[:T]`, writes nothing back" contract, same explicit `error(...)` convention if any structural guard is needed. Add it as a new function in this same file (not a new file) — `ac_oracle.jl`'s own header already anticipates growth ("A NEW sibling to models/exactness.jl ... holds the pure post-processing over an already-solved branch-flow point").

---

### Nonconvex-AC-dual fallback (OVR-03/D-09/D-10)

**Analog 1 (the dispatch seam — zero new solve machinery needed):** `src/models/welfare_solve.jl`'s `solve_welfare` entrypoint, already routes `ACPowerFlow()` through `NLP()` → Ipopt (confirmed: `ACPowerFlow.jl` line 219 `problem_class(::ACPowerFlow) = NLP()`) and already reads `dual()` unconditionally for every formulation.

**Analog 2 (multi-start / local-optimum-guard pattern):** `test/test_ac_oracle.jl` lines 213-243 (the EXACT-04 test's existing 2-start comparison):
```julia
ctx_ac, cost_ac, _ = solve_welfare(feeder, ACPowerFlow(), aggs; T = ..., λ₀ = λ₀, allow_local = true, allow_export = true)
ctx_ac2, cost_ac2, _ = solve_welfare(
    feeder, ACPowerFlow(), aggs; T = ..., λ₀ = λ₀, allow_local = true, allow_export = true,
    optimizer = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0, "mu_strategy" => "adaptive"),
)
@test isapprox(cost_ac, cost_ac2; rtol = 1e-3, atol = 1e-3)
```
Extend this EXACT pattern from 2 seeds to 3-5 (D-11): loop over `StableRNG`-seeded Ipopt attribute variants (e.g. varying `mu_strategy`/a seeded starting point), collect `(cost, dadp)` per start, and report BOTH the cost agreement (`isapprox(...; rtol=1e-3)`, matching the existing guard's own tolerance) AND the `dadp` vector spread — never publish a single-start price. The 2-start subset is the CI-gated version; 3-5 goes in the quarantined script (see below).

**Structural status-field pattern (D-10):** no direct existing analog for a `price_status` field; follow the "named field on the result, never a bare value" discipline used throughout this project's certificates (`(; obj_gap, hours)` in `assert_ac_exact!`; `(; ac_feasible, optimality_loss, ...)` in the new certificate above) — e.g. return `(; dadp, price_status = :local_ac_dual, agreement_report)`.

---

### `test/test_restricted_branch_flow.jl` (test)

**Analog:** `test/test_ac_oracle.jl`, specifically the EXACT-04 `@testitem` (lines 180-277).

**Setup/fixture pattern:**
```julia
@testitem "..." tags = [:ac_oracle] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
    import Ipopt
    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()
    ...
end
```
Reuse `Phase4Fixtures` (`test/fixtures_phase4.jl`) verbatim (`high_pv_feeder`, `build_high_pv_aggregators(feeder; pv_scale=1.2)`, `mem_price_profile()`, `T`) — this IS the EXACT-04 fixture (correcting the "IEEE-13" mislabel per RESEARCH.md Open Question 1: it is a 3-bus purpose-built fixture, not a real 13-node network).

**Regression-guard pattern (byte-identical default path, an Anti-Pattern in RESEARCH.md):** add a new `@testitem` asserting `ConvexBranchFlow` alone (no `RestrictedBranchFlow` involved) is unchanged before/after — mirrors the project's general "new formulation, zero existing-caller drift" discipline already implicit in how `ACPowerFlow.jl` and `ConvexBranchFlow.jl` coexist without cross-contamination.

**Quarantine convention for the fuller multi-start evidence (D-11, D-13-Phase-19-precedent):** a script under `.planning/spikes/` (see `.planning/spikes/CONVENTIONS.md`, `.planning/spikes/003-phase18-fragility-tolerance/` as the most recent precedent directory) — CI gates only the cheap 2-start version inside `test_restricted_branch_flow.jl`; the 3-5-seed sweep lands as a quarantined spike script, numbered as the next spike directory (currently `001`-`003` exist; use `004-...`).

---

### `docs/literate/restricted_branch_flow.jl` (literate doc page, OVR-04)

**Analog:** `docs/literate/ac_oracle.jl` (the most structurally similar existing rung page — "prove a formulation, then certify it against an independent oracle, then narrate a documented finding").

**Section-shape pattern to mirror** (verified from the file, lines 1-192):
1. `# # Rung N — <Title>` header + 1-2 paragraph motivation citing the literature (Farivar & Low 2013; Gan, Li, Topcu & Low 2015) — same citation style as lines 13-16.
2. `# ## Building the high-PV stress fixture` — inline-rebuild the SAME `Phase4Fixtures`-equivalent fixture (literate pages cannot load test-only modules, lines 30-116 build it inline from raw `Bus`/`Branch`/`Aggregator` constructors).
3. `# ## Solving both formulations on the same data` — the `solve_welfare(...)` calls, one per formulation compared (here: `ConvexBranchFlow` diagnostic-loosened, `RestrictedBranchFlow`, and `ACPowerFlow`), using the exact kwarg style at lines 126-144.
4. `# ## The exactness report` — call the new certificate, print its returned namedtuple fields as live, re-executed numbers (never hard-coded), lines 146-172.
5. `# ## Finding` — a closing prose section stating the documented, re-derived result (here: EXACT-04 is now priceable; the measured optimality loss; when the fallback semantics apply), lines 174-192.

**New requirement beyond the `ac_oracle.jl` template (D-12):** must ALSO show the Gan & Low condition itself (`C1`, the modification-gap `ε` measurement) beside the code that implements it — this is new narrative content not present in `ac_oracle.jl`, to be added as its own `# ## The Gan–Low condition` subsection citing Theorem 1/2 and eq. (18) directly (per RESEARCH.md's Architecture Patterns section, which already has the exact theorem text and equation numbers ready to quote).

**Module registration:** add the new file's entry to `docs/make.jl`'s Literate page list (mirror however `ac_oracle.jl` is currently registered there — read `docs/make.jl` before writing to confirm the exact list syntax/ordering).

## Shared Patterns

### Certificate family (throw-by-default + `report` kwarg + measured-tolerance docstring provenance)
**Source:** `src/models/exactness.jl` (`assert_socp_exact!`), `src/models/complementarity_4q.jl` (`assert_4q_complementarity!`)
**Apply to:** `src/models/restriction_exactness.jl` (the new OVR-02 certificate)
```julia
maxratio <= 1 || error(
    "SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=$maxratio > 1 " *
    "(rtol=$rtol, atol=$atol; max abs |l·v−(P²+Q²)|=$maxgap) — " *
    "prices REFUSED (thesis 3.43-3.45; PF-04)",
)
```
and the `report::Bool = false` → `@warn` vs `error(...)` branch shown in `complementarity_4q.jl` lines 152-156. Every new mathematical regime gets its OWN measured tolerance — never copy another certificate's `rtol`/`atol` (binding project convention, confirmed across `exactness.jl`, `ac_oracle.jl`, and `complementarity_4q.jl`'s explicit anti-laundering commentary).

### Formulation-per-type dispatch (never formulation-by-kwarg)
**Source:** `src/powerflow/AbstractPowerFlow.jl` (the `contribute!` contract) + `src/powerflow/ConvexBranchFlow.jl`/`ACPowerFlow.jl` (`problem_class` trait methods)
**Apply to:** `src/powerflow/RestrictedBranchFlow.jl`
```julia
abstract type AbstractPowerFlow end
function contribute! end
# concrete: struct RestrictedBranchFlow <: AbstractPowerFlow ... end
#           contribute!(pf::RestrictedBranchFlow, ctx, feeder; T=1) = ...
#           problem_class(::RestrictedBranchFlow) = SOCP()
```
Swapping the formulation is PURE Julia multiple dispatch on the singleton/parametrized type passed to `solve_welfare` — no `if formulation == ...` branch anywhere in `welfare_solve.jl` or device code.

### `ctx.meta` provenance stashing (D-08)
**Source:** `src/powerflow/ConvexBranchFlow.jl` line 232 (`ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)`) and `src/models/welfare_solve.jl` line 257 (`ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact)`)
**Apply to:** `RestrictedBranchFlow.contribute!` (stash `ctx.meta[:restriction_ε] = pf.ε`) and the result surface returned to callers (stash/attach a formulation + certificate-status provenance field per D-08, following the SAME "stash on `ctx.meta`, read by a downstream consumer keyed off `haskey`" idiom `welfare_solve.jl` already uses for the `:l`-gated `assert_socp_exact!` dispatch, lines 254-258).

### Explicit `error(...)`, never `@assert`
**Source:** stated explicitly in the header comments of `exactness.jl`, `ac_oracle.jl`, and `complementarity_4q.jl` alike (referencing `src/core/status.jl`'s convention — elided under `-O`)
**Apply to:** all new certificate/guard code in this phase.

## No Analog Found

None — every file this phase needs has a strong, structurally close analog already in the codebase (Phase 15/19 precedent). No file requires falling back to RESEARCH.md's abstract Code Examples alone.

## Metadata

**Analog search scope:** `src/powerflow/`, `src/models/`, `test/`, `docs/literate/`, `src/TSODSO.jl` (module include list), `.planning/spikes/` (quarantine convention).
**Files read in full or targeted:** `src/powerflow/AbstractPowerFlow.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/powerflow/ACPowerFlow.jl`, `src/models/exactness.jl`, `src/models/complementarity_4q.jl`, `src/models/ac_oracle.jl`, `docs/literate/ac_oracle.jl`, `test/test_ac_oracle.jl` (lines 160-277), `test/fixtures_phase4.jl` (lines 170-300), `test/fixtures_phase19.jl` (lines 1-80), `src/TSODSO.jl` (include list grep).
**Pattern extraction date:** 2026-08-08
