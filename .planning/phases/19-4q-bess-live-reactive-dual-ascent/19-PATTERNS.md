# Phase 19: 4Q-BESS + Live Reactive Dual-Ascent - Pattern Map

**Mapped:** 2026-08-07
**Files analyzed:** 9 (2 new, 7 modified) + 3 new test files
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/devices/FourQuadBESS.jl` (NEW) | device (aggregatable, variant 2) | CRUD (per-t decision vars + SOC recursion) | `src/devices/PVBattery.jl` | exact (same aggregatable-device contract, same SOC-split pattern, minus PV coupling) |
| `src/devices/Aggregator.jl` (MODIFIED) | device (aggregator, sole residual writer) | CRUD (roll-up/reduce) | itself (pre-phase version) | exact — additive-only diff on existing file |
| `src/devices/AbstractDevice.jl` (MODIFIED, docstring only) | interface/contract doc | n/a | itself | exact — doc-only diff |
| `src/models/exactness.jl`-peer certificate (new function, likely same file or a sibling) | model/certificate | batch/post-solve validation | `src/models/exactness.jl` (`assert_socp_exact!`) AND `src/models/welfare_solve.jl` (`assert_battery_complementarity!`) | exact (shape: throw-by-default, own WR-01 tolerance) |
| `src/admm/AgrOpt.jl` (MODIFIED) | service/subproblem builder (ADMM block 1, per-node QP→SOCP) | CRUD / build-once-resolve-many | itself (pre-phase version) | exact — additive dispatch on device presence |
| `src/admm/DsoOpt.jl` (MODIFIED) | service/subproblem builder (ADMM block 2, whole-network SOCP) | CRUD / build-once-resolve-many | itself (pre-phase version) — `reactive_consensus::Bool` → 3-state | exact — the file already has the exact seam (`:qag_pin`, `qag_dso`) this phase unpins |
| `src/admm/solve_admm.jl` (MODIFIED) | orchestrator (outer dual-ascent loop) | event-driven/iterative (fixed-point loop) | itself (pre-phase version) — active-block λ-ascent is the template for μ-ascent | exact — literally the same accumulator/record!/converged idiom, stacked |
| `src/admm/residuals.jl` (POSSIBLY MODIFIED) | model/ledger (pure data, no JuMP) | batch (accumulate-then-check) | itself (pre-phase version) — `record!`/`converged` overload pattern | exact — same multi-dispatch-overload-for-back-compat idiom already used for the Phase-6→7 transition |
| Results/μ,q surface (`src/pricing/dlmp.jl` peer or `solve_admm` return tuple) | pricing/results extraction | transform (post-solve read) | `src/pricing/dlmp.jl` (`extract_reactive_dlmp`) | exact — centralized-path analogue already exists; question is only wiring it to the ADMM-path `dso_ctx` |
| `test/test_fourquadbess.jl` (NEW) | test | unit | `test/test_pvbattery.jl` | exact |
| `test/fixtures_phase19.jl` (NEW, `@testmodule Phase19Fixtures`) | test fixture | data-only | `test/fixtures_phase3.jl` (`Phase3Fixtures`) | exact |
| `test/test_admm_reactive.jl` (EXTENDED, not new) | test | integration/regression | itself (pre-phase version) + `test/test_admm.jl`'s crossval items | exact |

## Pattern Assignments

### `src/devices/FourQuadBESS.jl` (device, CRUD)

**Analog:** `src/devices/PVBattery.jl` (full file read — 294 lines)

**File header / SEAM comment pattern** (lines 1-17 of `PVBattery.jl`):
```julia
# src/devices/PVBattery.jl
#
# SEAM: PV + battery (BESS) prosumer device (DEV-04).
# OWNER: plan 03-04.
#
# An `AbstractDevice` implementing a co-located PV generator and battery with
# continuous charge/discharge and SOC dynamics (thesis eqs. 3.6-3.9): ...
```
Copy this header shape for `FourQuadBESS.jl`: `SEAM:` line naming the device + requirement ID
(MESH-04), `OWNER:` line naming this phase's plan, then a prose paragraph citing the thesis eqs
reused (3.6 SOC recursion) and eqs NOT inherited (3.7/A6 PV-limited charge).

**Struct + strict-guard inner constructor pattern** (lines 87-157):
```julia
struct PVBattery{T <: Real} <: AbstractDevice
    bus::Int
    η::T
    Δt::T
    Pmax::T
    Emin::T
    Emax::T
    soc0::T
    λ_min::T
    λ_med::T
    λ_max::T
    Ppv::Vector{T}

    function PVBattery(bus::Int, η::T, Δt::T, Pmax::T, Emin::T, Emax::T, soc0::T,
                        λ_min::T, λ_med::T, λ_max::T, Ppv::Vector{T}) where {T <: Real}
        if !(λ_min < λ_med < λ_max)
            throw(ArgumentError("PVBattery requires STRICT λ_min < λ_med < λ_max ..."))
        end
        if Pmax <= zero(T)
            throw(ArgumentError("PVBattery power bound Pmax must be > 0 ..."))
        end
        if !(zero(T) < η <= one(T))
            throw(ArgumentError("PVBattery round-trip efficiency η must lie in (0, 1] ..."))
        end
        if !(Emin <= soc0 <= Emax)
            throw(ArgumentError("PVBattery initial SOC must satisfy Emin ≤ soc0 ≤ Emax ..."))
        end
        return new{T}(bus, η, Δt, Pmax, Emin, Emax, soc0, λ_min, λ_med, λ_max, Ppv)
    end
end
```
For `FourQuadBESS`, copy this exact shape but: (a) add `Pch_max::T`/`Pdch_max::T` (asymmetric
caps, D-02) instead of one `Pmax`, guarding `Pch_max > 0 && Pdch_max > 0` (loud `ArgumentError`,
never `@assert` — throw-never-@assert is a house convention, see `CLAUDE.md`/RTK context and
every guard above); (b) add `Smax::T` for the apparent-power cone (D-04), guarded `Smax > 0`;
(c) drop `Ppv`, `λ_min/λ_med/λ_max`'s STRICT-ordering guard is Claude's Discretion whether kept —
if the utility retains the App. C shape, keep an analogous (possibly non-strict, since D-05 finds
the strict-ordering premise does not by itself suffice once grid-charging is enabled — see the
certificate note below) guard, documented as to WHY it differs from `PVBattery`'s.

**Outer promoting constructor** (lines 159-208) — copy verbatim shape (IN-01 promotion pattern):
```julia
function PVBattery(bus::Integer, η::Real, ..., Ppv::AbstractVector{<:Real})
    T = promote_type(typeof(η), ..., eltype(Ppv))
    return PVBattery(Int(bus), T(η), ..., Vector{T}(Ppv))
end
```

**`contribute!` — aggregatable-device contract** (lines 210-291):
```julia
function contribute!(d::PVBattery, ctx::ModelContext; T::Int)
    m = ctx.model
    p_ch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)   # (3.8)
    p_dch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)  # (3.8)
    soc = @variable(m, [t = 1:T], lower_bound = d.Emin, upper_bound = d.Emax) # (3.9)
    @constraint(m, soc[1] == d.soc0)
    if T > 1
        @constraint(m, [t = 1:(T - 1)],
            soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt)
    end
    # ... utility, p_inject ...
    return (; vars = (; p_ch, p_dch, soc, pv_used), p_inject, utility)
end
```
`FourQuadBESS.contribute!` follows this exactly for the SOC recursion (D-04's `p_ch`/`p_dch`
split), but: drops the `p_ch[t] <= pv_used[t]` PV-limited-charge constraint (D-02: grid charging
permitted, so `p_ch` is bounded only by `Pch_max`, `p_dch` by `Pdch_max` — asymmetric, unlike
`PVBattery`'s single `Pmax`); adds the free reactive variable `q[t]` (D-03, no bound, no
objective term) and the apparent-power cone (see Pattern below, from `ConvexBranchFlow.jl`);
returns `(; vars = (; p_ch, p_dch, soc, q), p_inject, q_inject = q, utility)` — the NEW
`q_inject` field per D-09 (see Aggregator pattern below). `utility` must NOT contain any `q[t]`
term (D-03).

**Apparent-power SOC cone idiom** — copy from `src/powerflow/ConvexBranchFlow.jl:201-206`
(branch-level analog) and `src/pricing/dlmp.jl:182` (dual-slot convention):
```julia
# src/powerflow/ConvexBranchFlow.jl:201-206 — the EXISTING idiom to mirror at device scope
@constraint(
    m,
    smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
    [B[b].smax, P[b, t], Q[b, t]] in SecondOrderCone()
)
register_constraint!(ctx, :smax, smax)   # dual ν = congestion DLMP component (3.36)
```
```julia
# src/pricing/dlmp.jl:182 — SecondOrderCone dual slot convention (if the device cone's dual
# is ever read; D-03 says the deliverable compares welfare/price not q, so likely NOT needed)
dual(smax[b, t])[2]      # SecondOrderCone dual [smax, P, Q]; slot 2 = P
```
Device-scoped analog (net `p` as an `@expression`, not a raw variable, since it is
`p_dch - p_ch`):
```julia
p = @expression(m, [t = 1:T], p_dch[t] - p_ch[t])
q = @variable(m, [t = 1:T])   # sign-free, D-03: no bound, no cost term
@constraint(m, cone[t = 1:T], [d.Smax, p[t], q[t]] in SecondOrderCone())
```
Do NOT `register_constraint!` this cone into `ctx.constraints` unless a later task needs its
dual — `PVBattery`'s device-level constraints (SOC recursion, PV-limit) are likewise never
registered; only NETWORK-level constraints (`ConvexBranchFlow`'s `:smax`/`:cone`) are registered
because their duals feed `decompose_dlmp`.

**Export line** (line 293): `export PVBattery` → `export FourQuadBESS`.

---

### `src/devices/Aggregator.jl` (MODIFIED — widen roll-up, D-09/D-10)

**Analog:** itself, pre-phase version (full file read, 181 lines) — this is an ADDITIVE diff, not
a rewrite; every excerpt below is the EXACT code the new lines are inserted beside.

**Roll-up accumulator loop to widen** (lines 149-160):
```julia
p_inject = AffExpr[zero(AffExpr) for _ in 1:T]
utility = zero(QuadExpr)
device_vars = Any[]
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
    end
    utility += res.utility
    push!(device_vars, res.vars)
end
```
D-09's widened contract inserts a `hasproperty` guard inside the SAME loop, additively:
```julia
q_inject = AffExpr[zero(AffExpr) for _ in 1:T]   # NEW accumulator, mirrors p_inject exactly
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
        if hasproperty(res, :q_inject)     # NEW: absent ⇒ contributes zero (D-09)
            q_inject[t] += res.q_inject[t]
        end
    end
    utility += res.utility
    push!(device_vars, res.vars)
end
```

**Residual-write site to widen additively** (lines 162-168):
```julia
for t in 1:T
    add_to_residual!(ctx, :Rp, agg.bus, t, p_inject[t] - agg.Pdc[t])   # (3.22)
    add_to_residual!(ctx, :Rq, agg.bus, t, -agg.Pdc[t] * tanφ)         # (3.23)
end
```
D-10's purely-additive composition (`:Rq = −Pdc·tanφ + Σ device q_inject`) changes ONLY the
`:Rq` line, additively:
```julia
for t in 1:T
    add_to_residual!(ctx, :Rp, agg.bus, t, p_inject[t] - agg.Pdc[t])   # (3.22), unchanged
    add_to_residual!(ctx, :Rq, agg.bus, t, -agg.Pdc[t] * tanφ + q_inject[t])   # (3.23) + D-10 NEW term
end
```
With NO `FourQuadBESS` present, `q_inject[t]` is `zero(AffExpr)` for every `t` (never touched by
the `hasproperty` branch), so `:Rq`'s expression is `-agg.Pdc[t]*tanφ + 0` — algebraically but
NOT necessarily byte-identically the same `AffExpr` as today (JuMP `AffExpr + zero(AffExpr)` may
or may not literally be `===`-identical; verify with the existing `test_aggregator.jl` regression
item below rather than assuming). The `reactive_factor`/`tanφ` line (line 147) and everything else
in the function is untouched.

**Regression test analog to extend** (`test/test_aggregator.jl:16-73`, full item read) — the
existing item already asserts `Rq[bus,t].constant == -Pdc[t]*tanφ` and `isempty(Rq[bus,t].terms)`
for a non-4Q aggregator; per the Phase Requirements table this exact assertion becomes the
byte-identical-:Rq regression guard (extend this file, do not create a new one).

---

### 4Q complementarity certificate (NEW, D-05/D-06/D-07/D-08)

**Analog 1 — the throw-by-default certificate shape:** `src/models/exactness.jl`
(`assert_socp_exact!`, full file read, 110 lines):
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
export assert_socp_exact!
```
This is the WR-01 scale-free `atol + rtol·magnitude` idiom D-07 mandates: `error(...)` (never
`@assert`), a returned `maxgap`/diagnostic value on success, kwargs `rtol`/`atol` (this IS the
"kwarg to report" neutralization D-06 references — a caller can pass a deliberately loose
`rtol`/`atol` to observe rather than throw, exactly like `test_ac_oracle.jl:198-210`'s documented
`rtol_exact = 1.0` diagnostic override of `solve_welfare`'s pass-through kwarg).

**Analog 2 — device-vars-stash duck-typed iteration + its OWN separate tolerance:**
`src/models/welfare_solve.jl:273-321` (`assert_battery_complementarity!`, full excerpt read):
```julia
function assert_battery_complementarity!(ctx::ModelContext; τ::Real, T::Int = ctx.meta[:T])
    haskey(ctx.meta, :agg_device_vars) || return nothing
    for (bus, varlist) in ctx.meta[:agg_device_vars]
        for v in varlist
            (haskey(v, :p_ch) && haskey(v, :p_dch)) || continue   # a battery
            pmax = has_upper_bound(v.p_ch[1]) ? upper_bound(v.p_ch[1]) : 1.0
            scale² = max(abs(pmax), 1e-8)^2
            for t in 1:T
                prod = value(v.p_ch[t]) * value(v.p_dch[t])
                prod < τ * scale² || error(
                    "Battery complementarity violated at bus $bus, t=$t: " *
                    "p_ch·p_dch = $prod ≥ τ·Pmax² = $(τ * scale²) " *
                    "(relative τ=$τ, Pmax≈$pmax; App. C, threat T-03-13)",
                )
            end
        end
    end
    return nothing
end
```
**CRITICAL per PITFALLS.md Pitfall 2 / this phase's D-07:** this OLD check duck-types on
`haskey(v, :p_ch) && haskey(v, :p_dch)` — if `FourQuadBESS.vars` reuses those exact field names,
this OLD check will ALSO silently match a 4Q device and apply the WRONG (`Pmax²`, one-dimensional
strict-ordering-derived) tolerance to it. The new certificate function (name is Claude's
Discretion, e.g. `assert_4q_complementarity!`) must either (a) give `FourQuadBESS.vars` a
distinguishing field (e.g. `haskey(v, :q)` alongside `p_ch`/`p_dch` — since `q` only exists on
the 4Q device — and have the OLD check's loop condition tightened to `haskey(v,:p_ch) &&
haskey(v,:p_dch) && !haskey(v,:q)`, OR dispatch by an explicit type tag) so the two checks are
mutually exclusive over the SAME `ctx.meta[:agg_device_vars]` stash, each iterated the SAME way
but calling a DIFFERENT named function with a DIFFERENT, independently-derived tolerance (D-07 —
"never a reused tolerance"). Wire the new certificate explicitly at BOTH the AGR-OPT-final-solve
call site in `solve_admm.jl` (mirrors `check_battery=true` in `solve_agr!`'s final call, see the
`solve_admm.jl` excerpt below) and `welfare_solve.jl`'s `solve_welfare` if 4Q devices are ever
solved centrally.

**Analog 3 — the "compare, never throw on a genuine numeric disagreement" alternate shape** (for
reference only, likely NOT the shape needed here since D-06 explicitly wants throw-by-default):
`src/models/ac_oracle.jl:146-186` (`assert_ac_exact!`) returns a per-hour `NamedTuple` report and
NEVER throws on a numeric gap — contrast with `assert_socp_exact!`'s throw-by-default. D-06 is
explicit that the NEW certificate follows Analog 1's throw-by-default shape, with the
"observe without a src/ edit" affordance coming from a tolerance kwarg (as in Analog 1), NOT from
switching to Analog 3's always-report shape.

---

### `src/admm/AgrOpt.jl` (MODIFIED — conic dispatch when 4Q present)

**Analog:** itself, pre-phase version (full file read, 238 lines). `build_agr_opt` already calls
`Model(select_optimizer(QP()))` (line 94) and reuses `contribute!(agg, ctx; T=T)` verbatim (line
101) — when `agg.devices` contains a `FourQuadBESS`, `contribute!` (via the widened Aggregator)
will itself add a `SecondOrderCone()` constraint to `ctx.model`, so `AgrOpt`'s model literally
BECOMES an SOCP without `build_agr_opt` writing any new JuMP code — only the optimizer FACTORY
call may need `select_optimizer(SOCP())` instead of `QP()` (Claude's Discretion per CONTEXT.md;
research Assumption A4 flags this as a tuning question, not an architecture one). If a
per-aggregator problem-class decision is needed, mirror the EXISTING `problem_class`
trait-dispatch idiom already used elsewhere in the codebase (`src/solver/ProblemClass.jl`,
`src/solver/problem_class_trait.jl`) rather than a fresh `if`-branch.

**Coefficient-update solve loop to extend for the μ-price term** (`solve_agr!`, lines 166-204):
```julia
function solve_agr!(agr::AgrOpt, λ_j::AbstractVector, c_j::AbstractVector, ρ::Real;
                     check_battery::Bool = true, τ_batt::Real = 1e-6, strict::Bool = true)
    length(λ_j) == agr.T || throw(ArgumentError(...))
    length(c_j) == agr.T || throw(ArgumentError(...))
    for t in 1:agr.T
        set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
    end
    if strict
        assert_solved!(agr.model; dual = true)
    else
        assert_solved!(agr.model; dual = false, allow_almost = true)
    end
    if check_battery
        assert_battery_complementarity!(agr.ctx; τ = τ_batt, T = agr.T)
    end
    return (; pag = value.(agr.pag), utility = value(agr.ctx.meta[:objective]))
end
```
The live μ-ascent extension (option 1 in RESEARCH.md, a genuine second ADMM block) adds a
`qag`/coupling-variable analog to `pag` PLUS a mirrored `set_objective_coefficient` call for the
μ price + ρ_q-penalty-shift term, taking new `μ_j::AbstractVector`/`d_j::AbstractVector`
(reactive analogs of `λ_j`/`c_j`) parameters — same length-guard pattern, same
`set_objective_coefficient` idiom, added to the SAME per-`t` loop (do not add a second loop).
`agr.qag` (currently a `Vector{Float64}` CONSTANT placeholder, `AgrOpt.jl:47-51` docstring) is the
documented seam this phase promotes to a genuine coupling variable when `q_inject` is non-zero
(i.e. a 4Q device is present) — see the field docstring's explicit "PLACEHOLDER for a FUTURE
reactive-consensus (μ dual-ascent) extension" note, which is THIS phase.

**`build_agr_opt`'s coupling-variable + objective-assembly pattern to mirror for `qag`**
(lines 92-118): the exact same three-step shape (`@variable` → `@constraint(... == ...)` pinning
→ `@objective` with a `-0.5*ρ*sum(pag[t]^2 ...)` fixed quadratic penalty) is the template for a
new `qag[t]` coupling variable pinned to `res.q_inject[t]` (NOT `-Pdc[t]*tanφ` — that constant
term stays inelastic-only per D-10; only the device `q_inject` component is the live-consensus
target) with its OWN `-0.5*ρ_q*sum(qag[t]^2 ...)` penalty term, added to the objective only under
`:live` mode (byte-identical objective otherwise).

---

### `src/admm/DsoOpt.jl` (MODIFIED — 3-state mode, unpin under `:live`)

**Analog:** itself, pre-phase version (full file read, 413 lines) — this file ALREADY contains the
exact `reactive_consensus::Bool` branch this phase promotes to 3-state.

**The exact branch to promote** (`build_dso_opt`, lines 244-256):
```julia
if reactive_consensus
    @variable(model, qag_dso[j = load_nodes, t = 1:T])
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
    end
    @constraint(model, qag_pin[j = load_nodes, t = 1:T], qag_dso[j, t] == q_draw[j][t])
    register_constraint!(ctx, :qag_pin, qag_pin)
    ctx.meta[:qag_dso] = qag_dso
else
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])
    end
end
```
Per PITFALLS.md Pitfall 4 (re-verified in RESEARCH.md), the 3-state promotion (D-12) MUST turn
this into THREE genuinely separate branches — `OFF` (== today's `else`, byte-identical),
`CERTIFIED` (== today's `if reactive_consensus`/`true` branch, `:qag_pin` STILL registered,
UNCONDITIONALLY, byte-identical), `LIVE` (a NEW third branch: declares `qag_dso` the SAME way,
injects it into `:Rq` the SAME way, but registers NO `:qag_pin` equality — instead the coupling
is left open for `solve_admm`'s μ-ascent to drive via `set_objective_coefficient` on a new
`0.5*ρ_q*qag_dso[j,t]^2` penalty term this file's `@objective` (lines 287-292) must ALSO gain,
mirroring `pag_dso`'s existing `0.5*ρ*pag_dso[j,t]^2` term exactly):
```julia
# EXISTING objective (lines 287-292) — the template for the NEW ρ_q term under :live
@objective(
    model,
    Min,
    sum(λ₀[t] * p_import[t] for t in 1:T) +
    0.5 * ρ * sum(pag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    # NEW under :live: + 0.5 * ρ_q * sum(qag_dso[j, t]^2 for j in load_nodes, t in 1:T)
)
```

**`set_rho!` batch-mutation idiom to mirror for `ρ_q`** (lines 402-410):
```julia
function set_rho!(dso::DsoOpt, ρ::Real)
    v = VariableRef[dso.pag[j, t] for j in dso.load_nodes for t in 1:dso.T]
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ, length(v)))
    return dso
end
```
A `set_rho_q!` (or a `set_rho!` overload keyed by block) follows this EXACT batch-flatten-then-
one-call shape for `qag_dso` under `:live`.

**3-state normalization function (NEW, no direct analog — RESEARCH.md's own proposed code, not
yet in the codebase)** — copy verbatim from RESEARCH.md's Code Examples section (this IS the
recommended shape, following the file's existing fail-loud `ArgumentError` convention at
`DsoOpt.jl:154-173`'s boundary-guard style):
```julia
@enum ReactiveMode OFF CERTIFIED LIVE
function normalize_reactive_mode(m)::ReactiveMode
    m isa Bool && return m ? CERTIFIED : OFF
    m isa ReactiveMode && return m
    if m isa Symbol
        m === :off && return OFF
        m === :certified && return CERTIFIED
        m === :live && return LIVE
    end
    throw(ArgumentError(
        "reactive_consensus must be a Bool, :off, :certified, or :live; got $m",
    ))
end
```

**Boundary-guard style to mirror for the new mode validation** (lines 154-173, existing):
```julia
for (k, agg) in enumerate(aggregators)
    1 <= agg.bus <= N || throw(
        ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
    )
    agg.bus == root && throw(
        ArgumentError(
            "aggregator[$k] sits on the root bus $root; the frontier root carries " *
            "no aggregator in DSO-OPT (thesis 3.47)",
        ),
    )
end
```

---

### `src/admm/solve_admm.jl` (MODIFIED — μ-ascent + joint stopping)

**Analog:** itself, pre-phase version (full file read, 482 lines) — the active-block λ-ascent IS
the template; RESEARCH.md's Code Examples section already works out the exact stacked-accumulator
extension. Both excerpted together here.

**The EXACT accumulator/threshold/record!/converged block to extend** (lines 260-303, the primal
λ block):
```julia
sq_r = 0.0
sq_ds = 0.0
sq_a = 0.0
sq_pd = 0.0
sq_λ = 0.0
for j in load_nodes, t in 1:T
    rp = a[j][t] - pag_dso[j, t]
    dz = pag_dso[j, t] - pag_dso_prev[j][t]
    sq_r += rp^2
    sq_ds += dz^2
    sq_a += a[j][t]^2
    sq_pd += pag_dso[j, t]^2
    sq_λ += λ[j][t]^2
end
r_norm = sqrt(sq_r)
s_norm = ρf * sqrt(sq_ds)

p = length(load_nodes) * T
ε_pri = sqrt(p) * ε_abs + ε_rel * max(sqrt(sq_a), sqrt(sq_pd))
ε_dual = sqrt(p) * ε_abs + ε_rel * sqrt(sq_λ)
price_gap = ρf * r_norm

record!(residuals, k, r_norm, s_norm, ρf, ε_pri, ε_dual, price_gap)

if converged(residuals, ε_pri, ε_dual)
    converged_flag = true
    break
end

for j in load_nodes
    for t in 1:T
        pag_dso_prev[j][t] = pag_dso[j, t]
        λ[j][t] += ρf * (a[j][t] - pag_dso[j, t])
        c[j][t] = -pag_dso[j, t]
    end
end
```
**RESEARCH.md's worked-out stacked extension (Code Examples section, verbatim — use this as the
implementation template, NOT two independent `converged` calls per Pitfall 3/Anti-Pattern #1):**
```julia
sq_r, sq_ds, sq_a, sq_pd, sq_λ = 0.0, 0.0, 0.0, 0.0, 0.0
sq_r_q, sq_ds_q, sq_b, sq_qd, sq_μ = 0.0, 0.0, 0.0, 0.0, 0.0   # NEW reactive accumulators
for j in load_nodes, t in 1:T
    rp = a[j][t] - pag_dso[j, t]
    dz = pag_dso[j, t] - pag_dso_prev[j][t]
    sq_r += rp^2; sq_ds += dz^2; sq_a += a[j][t]^2; sq_pd += pag_dso[j, t]^2; sq_λ += λ[j][t]^2
    if reactive_mode == LIVE
        rq = b[j][t] - qag_dso[j, t]                       # reactive consensus violation
        dzq = qag_dso[j, t] - qag_dso_prev[j][t]
        sq_r_q += rq^2; sq_ds_q += dzq^2; sq_b += b[j][t]^2
        sq_qd += qag_dso[j, t]^2; sq_μ += μ[j][t]^2
    end
end
r_norm = sqrt(sq_r + sq_r_q)              # JOINT primal norm (both blocks stacked)
s_norm = ρf * sqrt(sq_ds) + ρ_qf * sqrt(sq_ds_q)   # JOINT dual norm (each block's own ρ)
p_total = length(load_nodes) * T * (reactive_mode == LIVE ? 2 : 1)
ε_pri = sqrt(p_total) * ε_abs + ε_rel * max(sqrt(sq_a + sq_b), sqrt(sq_pd + sq_qd))
ε_dual = sqrt(p_total) * ε_abs + ε_rel * sqrt(sq_λ + sq_μ)
```
NB: `converged(residuals, ε_pri, ε_dual)` (`src/admm/residuals.jl:177-180`) is called EXACTLY
ONCE on this joint `(r_norm, s_norm, ε_pri, ε_dual)` — never once per block (Pitfall 3 /
Anti-Pattern #1). The one existing `record!`/`converged` call site (line 296/300) is where the
joint values are plugged in; do not add a second call anywhere.

**Adaptive-ρ residual-balancing block to potentially mirror for `ρ_q`** (lines 337-359) — if
Claude's Discretion lands on an INDEPENDENT `ρ_q` (RESEARCH.md's recommendation, since the
reactive channel's magnitude typically differs sharply from active), this exact
`r̂=r_norm/ε_pri; ŝ=s_norm/ε_dual; if r̂<=10 && ŝ<=10 ... else ρ_new = r̂>μ*ŝ ? τ*ρf : ŝ>μ*r̂ ?
ρf/τ : ρf ...` shape is duplicated for the reactive block's own `r̂_q`/`ŝ_q`/`ρ_qf`, each calling
`set_rho!`/`set_rho_q!` on BOTH `AgrOpt` and `DsoOpt` in lockstep (mirrors the existing
"in lockstep" contract documented in both files' `set_rho!` docstrings).

**Final-consolidation certificate block to extend** (lines 399-451) — the `:balance_q` no-slack
certification is ALREADY conditional on `reactive_consensus` (now: `mode != OFF`); the NEW 4Q
complementarity certificate call (see certificate section above) is added to the SAME final block,
alongside the EXISTING `check_battery = true` call on `solve_agr!` (lines 399-411) — do not create
a separate final pass, extend the existing one.

**Docstring convention to mirror** — the file's ~130-line header comment block (lines 1-51) and
the function's own extensive `"""..."""` docstring (lines 54-127) covering Algorithm, Adaptive ρ,
Reactive consensus, Returns, Throws sections: `FourQuadBESS`/`solve_admm`'s updated docstring
should gain an analogous "Live reactive dual-ascent (Phase 19, MESH-05)" subsection replacing/
extending the current "Reactive consensus (Phase 16, REACT-01/02)" subsection (lines 99-109),
keeping the EXISTING subsection's prose for `:off`/`:certified` verbatim (byte-identical
documentation of unchanged behavior) and adding new prose only for `:live`.

---

### `src/admm/residuals.jl` (POSSIBLY MODIFIED — stacked-block ledger)

**Analog:** itself, pre-phase version (full file read, 195 lines) — this file ALREADY solved the
EXACT problem this phase faces (extending a residual ledger without breaking old callers) once
before, for the Phase-6→Phase-7 transition. Copy that idiom, don't invent a new one.

**The multi-dispatch-overload-for-back-compat pattern** (lines 109-192):
```julia
# EXTENDED (8-arg) form — the CURRENT call site uses this
function record!(res::AdmmResiduals, k::Integer, primal::Real, dual::Real, ρ::Real,
                  ε_pri::Real, ε_dual::Real, price_gap::Real)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal)))
    ...
    res.iters += 1
    return res
end

# RETAINED (4-arg) form — kept so an UNMODIFIED older caller still compiles/runs
function record!(res::AdmmResiduals, k::Integer, primal_maxabs::Real, dual_maxabs::Real)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal_maxabs)))
    push!(res.dual_trace, abs(float(dual_maxabs)))
    push!(res.rho_trace, NaN)          # NaN-pad the traces the shorter-arity caller has no data for
    push!(res.eps_pri_trace, NaN)
    push!(res.eps_dual_trace, NaN)
    push!(res.price_gap_trace, NaN)
    res.iters += 1
    return res
end

converged(res::AdmmResiduals, ε_pri::Real, ε_dual::Real) = ...   # two-residual (current) form
converged(res::AdmmResiduals, tol::Real) = ...                    # RETAINED single-tol form
```
RESEARCH.md's recommendation is that the JOINT stacking happens BEFORE calling `record!`/
`converged` (i.e. the caller in `solve_admm.jl` pre-sums `sq_r_p + sq_r_q` etc. into ONE
`r_norm`/`s_norm`/`ε_pri`/`ε_dual` quadruple), so `residuals.jl` itself may need ZERO changes — the
EXISTING 8-arg `record!` and 2-arg `converged` already accept a single joint scalar pair. Only add
a new `record!`/`converged` overload here if the plan decides to store BOTH blocks' traces
SEPARATELY for diagnostic plotting (e.g. a `sq_r_q`/`price_gap_q` trace peer) — in which case copy
the SAME "new N-arg method, old M-arg method retained, NaN-pad the gap" idiom shown above verbatim,
never mutate the existing struct fields' semantics in place.

**Struct-field-and-constructor doc pattern** (lines 32-99) — if new fields ARE added (e.g. a
`price_gap_q_trace`), mirror the exact "Fields: ... All N traces kept EQUAL LENGTH" docstring
convention and the `AdmmResiduals(N,T)`/`AdmmResiduals()` two-constructor pattern (empty-vector
init + a convenience zero-shape constructor).

---

### μ / q results surface (D-11)

**Analog:** `src/pricing/dlmp.jl:138-152` (`extract_reactive_dlmp`, already reads verbatim above)
— the centralized-path function that ALREADY does exactly what D-11 wants, just not yet proven to
apply unchanged to the ADMM path's `dso_ctx`.
```julia
function extract_reactive_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    haskey(ctx.constraints, :balance_q) || throw(ArgumentError(
        "extract_reactive_dlmp: ctx has no :balance_q -- this formulation has no " *
        "reactive channel (e.g. DCPowerFlow); no reactive price exists to extract",
    ))
    bq = ctx.constraints[:balance_q]
    N, Tfull = size(bq)
    M = Float64[dual(bq[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end
```
Per RESEARCH.md Open Question 3, the FIRST task here is empirical, not code-writing: verify
whether `extract_reactive_dlmp(admm_result.dso_ctx)` under `:live` mode ALREADY equals the
outer-loop `μ` (up to the SAME sign convention `solve_admm.jl`'s header comment pins for `λ`; see
`solve_admm.jl:459-468`'s `λ_mat = reduce(vcat, (permutedims(-λ[j]) for j in load_nodes))` sign-
negation block — the exact empirical-sign-pinning precedent to replicate for μ). If they agree,
D-11 needs ONLY a `μ`/`dadp_q` field added to `solve_admm`'s return `NamedTuple` (mirroring the
EXISTING `dadp`/`λ` peer fields at lines 470-478) — NOT a new extraction function. If they
disagree, write a new ADMM-side extraction analogous to `extract_reactive_dlmp` but reading the
outer-loop `μ` dict directly (mirrors how `λ_mat` is built from the internal `λ` dict, not from
`dual(dso_ctx.constraints[:balance_p])`).

**`solve_admm`'s return-tuple assembly to mirror** (lines 470-478):
```julia
return (;
    welfare = welfare,
    dadp = λ_mat,
    λ = λ_mat,
    iters = residuals.iters,
    residuals = residuals,
    dso_ctx = dso.ctx,
    exact_maxgap = exact_maxgap,
)
```
D-11's μ/q peers are added here as NEW named fields (e.g. `μ = μ_mat`, `dadp_q = μ_mat`,
`q_devices = ...`), following the SAME `(n_load_nodes, T)` matrix shape and ascending-bus-order
convention `λ_mat`/`dadp` use — never a different shape for the reactive peer.

---

## Shared Patterns

### Throw-never-@assert, loud ArgumentError construction guards
**Source:** `src/devices/PVBattery.jl:122-154`, `src/devices/Aggregator.jl:72-89`,
`src/admm/DsoOpt.jl:154-173`
**Apply to:** `FourQuadBESS`'s inner constructor (Pch_max/Pdch_max/Smax/η guards), the 3-state
`normalize_reactive_mode` validator, and the new certificate's violation `error(...)` call.
```julia
if !(some_invariant)
    throw(ArgumentError("Descriptive message citing the thesis eq / requirement ID; got ..."))
end
```

### WR-01 scale-free `atol + rtol·magnitude` certificate tolerance
**Source:** `src/models/exactness.jl:78-107` (`assert_socp_exact!`)
**Apply to:** the new 4Q complementarity certificate (D-07 — own tolerance, never reused).
```julia
tol = atol + rtol * max(abs(lhs), abs(rhs))
maxratio = max(maxratio, gap / tol)
maxratio <= 1 || error("... prices REFUSED ...")
```

### Build-once / re-solve via `set_objective_coefficient`, never rebuild
**Source:** `src/admm/AgrOpt.jl:166-204` (`solve_agr!`), `src/admm/DsoOpt.jl:336-375` (`solve_dso!`)
**Apply to:** every per-iteration μ-ascent coefficient update — one scalar
`set_objective_coefficient` call per `(j,t)`, no `Model(...)`/`@constraint` call inside the loop.

### Batch quadratic-coefficient mutation for adaptive-ρ
**Source:** `src/admm/AgrOpt.jl:230-235`, `src/admm/DsoOpt.jl:402-410` (`set_rho!`)
**Apply to:** a parallel `set_rho_q!` (or overload) for the reactive block's own ρ_q, called in
lockstep with the active-block `set_rho!` per both files' existing docstring CONTRACT note.

### Aggregatable-device return contract, optional field, absent = zero
**Source:** `src/devices/AbstractDevice.jl:50-65` (Variant 2 doc), `src/devices/PVBattery.jl:290`
**Apply to:** `FourQuadBESS.contribute!`'s return NamedTuple gaining `q_inject`, and
`Aggregator.contribute!`'s `hasproperty(res, :q_inject)` guard.

### Fail-loud maxiter cap / never return a non-consensus iterate
**Source:** `src/admm/solve_admm.jl:362-372`
**Apply to:** the joint (λ,μ) stopping loop — the SAME `ErrorException`-on-cap contract applies
unchanged; only the message should name BOTH blocks' residual/threshold values once stacked.

### Bounded-retry quarantine for flaky IEEE-13 ADMM solves
**Source:** `test/fixtures_retry.jl` (`AdmmRetryFixtures.retry_flaky_admm_solve`)
**Apply to:** any new IEEE-13 supporting-evidence test item added for MESH-05 (D-13 — NOT the
CI-gating small-radial-fixture items, which run un-retried).

## No Analog Found

None. Every file in scope has a strong, directly-read analog in the current tree; the phase is
explicitly scoped (both CONTEXT.md and RESEARCH.md) as additive extension of existing,
well-precedented machinery rather than new architecture.

## Metadata

**Analog search scope:** `src/devices/`, `src/admm/`, `src/models/`, `src/pricing/`,
`src/powerflow/ConvexBranchFlow.jl`, `src/solver/`, `test/` (fixtures + `test_pvbattery.jl`,
`test_aggregator.jl`, `test_admm_reactive.jl`, `fixtures_retry.jl`, `fixtures_phase3.jl`).
**Files scanned (full or targeted read):** `src/devices/PVBattery.jl` (full, 294 lines),
`src/devices/Aggregator.jl` (full, 181 lines), `src/devices/AbstractDevice.jl` (full, 78 lines),
`src/admm/solve_admm.jl` (full, 482 lines), `src/admm/DsoOpt.jl` (full, 413 lines),
`src/admm/AgrOpt.jl` (full, 238 lines), `src/admm/residuals.jl` (full, 195 lines),
`src/models/exactness.jl` (full, 110 lines), `src/models/welfare_solve.jl` (targeted, lines
230-323), `src/pricing/dlmp.jl` (targeted, lines 1-190), `src/models/ac_oracle.jl` (targeted,
lines 100-189), `src/powerflow/ConvexBranchFlow.jl` (targeted, lines 185-210),
`test/test_pvbattery.jl` (full, 246 lines), `test/test_aggregator.jl` (full, 109 lines),
`test/test_admm_reactive.jl` (full, 187 lines), `test/fixtures_phase3.jl` (full, 58 lines),
`test/fixtures_retry.jl` (full, 69 lines).
**Pattern extraction date:** 2026-08-07
