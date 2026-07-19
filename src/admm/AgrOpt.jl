# src/admm/AgrOpt.jl
#
# SEAM: AGR-OPT — the per-node aggregator/device ADMM subproblem (ADMM-01).
# OWNER: plan 06-02 (Wave 2). Declares its own `export`s per the include-graph convention.
#
# Block 1 of the 2-block ADMM split (RESEARCH Pattern 1/4, thesis eq. 3.46): a thin
# per-aggregator QP that REUSES the existing device / `Aggregator.contribute!` builders
# VERBATIM — ADMM is orchestration, NOT a model re-implementation. Derived from the single
# augmented Lagrangian of the centralized GLB-CVX (fixing the network side `netflow_j = c_j`):
#
#       max_{device vars}  U_ag,j(devices)                            (thesis 3.21)
#                          − Σ_t λ_j[t]·pag_j[t]                      (linear price term)
#                          − (ρ/2) Σ_t ( c_j[t] + pag_j[t] )²        (quadratic ρ-penalty)
#         s.t.  pag_j[t] == Σ_d p_inject_d[t] − Pdc[t]               (coupling var, thesis 3.22)
#               qag_j[t]  =  −Pdc[t]·tan(arccos φ)                   (thesis 3.23, constant)
#               device constraints (thesis 3.2–3.9, via contribute!)
#
# BUILD-ONCE / RE-SOLVE (ADMM-03, RESEARCH Pattern 3): the model is built ONCE. The quadratic
# self-penalty coefficient (−ρ/2 on pag_j²) is FIXED; expanding −(ρ/2)(pag+c)² shows the only
# per-iteration change is the LINEAR coefficient on pag_j[t], which absorbs BOTH the price and
# the shifted penalty target: coeff = −λ_j[t] − ρ·c_j[t]. Each ADMM iteration mutates only that
# scalar via `set_objective_coefficient(model, pag_j[t], −λ_j[t] − ρ·c_j[t])` (one call per
# hour) — NO JuMP rebuild. λ_j is a plain `Float64`, NEVER a JuMP `Parameter` (a `λ·pag`
# Parameter×variable term is an indefinite bilinear that Clarabel rejects — RESEARCH Pitfall 1).
# Solver via `select_optimizer(QP())` (INFRA-02, never names a concrete solver); every solve is
# gated on `assert_solved!(...; dual=true)` (INFRA-03); the App. C battery-complementarity check
# (`assert_battery_complementarity!`) runs after each solve — the batteries live in AGR-OPT now.

using JuMP

"""
    AgrOpt

The per-node AGR-OPT ADMM subproblem (thesis eq. 3.46) — block 1 of the 2-block split. A
BUILD-ONCE JuMP QP wrapping one [`Aggregator`](@ref)'s device roll-up, re-solved each ADMM
iteration by a single `set_objective_coefficient` update on the coupling variable (ADMM-03).

# Fields
- `model::Model` — the JuMP QP (Clarabel via `select_optimizer(QP())`), built ONCE.
- `ctx::ModelContext` — the model context the aggregator/device `contribute!` wrote into; its
  `ctx.meta[:objective]` holds the aggregator utility `U_ag` (a `QuadExpr`) and
  `ctx.meta[:agg_device_vars]` the battery vars for the App. C complementarity check.
- `pag::Vector{VariableRef}` — the coupling variable `pag_j[t]` (net active injection), pinned
  to `Σ_d p_inject_d[t] − Pdc[t]` (thesis 3.22). Its linear objective coefficient is the
  per-iteration ADMM handle.
- `qag::Vector{Float64}` — the CONSTANT net reactive injection `−Pdc[t]·tan(arccos φ)` (thesis
  3.23; DERs are active-only, A3), exposed for the reactive dual (`μ`) update.
- `T::Int` — the day-ahead horizon.
- `bus::Int` — the aggregator's distribution bus.
- `ρ::Float64` — the ADMM penalty / dual-step weight fixed into the quadratic term at build.
"""
struct AgrOpt
    model::Model
    ctx::ModelContext
    pag::Vector{VariableRef}
    qag::Vector{Float64}
    T::Int
    bus::Int
    ρ::Float64
end

"""
    build_agr_opt(agg::Aggregator, T::Int; ρ::Real) -> AgrOpt

Build the AGR-OPT per-node subproblem for aggregator `agg` over horizon `T` (thesis eq. 3.46),
ONCE, following RESEARCH Pattern 4 (option a — reuse `Aggregator.contribute!` verbatim):

1. `model = Model(select_optimizer(QP()))`; `ctx = ModelContext(model)`; stash `T` (INFRA-02).
2. Reuse the aggregator roll-up: `res = contribute!(agg, ctx; T)` drives each device once and
   sums their `p_inject` / `utility` (thesis 3.21–3.22). It also writes `:Rp`/`:Rq` and stashes
   the battery vars — the stray residual writes are HARMLESS here (AGR-OPT never closes them),
   and the battery stash is exactly what the App. C check consumes post-solve.
3. Create the coupling variable `pag[t]` and pin it to the net active injection
   `pag[t] == res.p_inject[t] − agg.Pdc[t]` (thesis 3.22).
4. Expose the CONSTANT reactive injection `qag[t] = −Pdc[t]·tan(arccos φ)` (thesis 3.23) for the
   μ update — there is no reactive DER decision, so it is a fixed vector, not a variable.
5. Set `@objective(model, Max, U_ag − (ρ/2)·Σ_t pag[t]²)` — the FIXED quadratic ρ-penalty part,
   built ONCE. The linear price+penalty-shift coefficient on `pag[t]` starts at zero and is
   updated per iteration by [`solve_agr!`](@ref) via `set_objective_coefficient` (never a
   JuMP `Parameter` for the price — RESEARCH Pitfall 1).

Returns an [`AgrOpt`](@ref). No concrete solver is named (INFRA-02); the model is well-posed and
solves OPTIMAL at the default zero price.
"""
function build_agr_opt(agg::Aggregator, T::Int; ρ::Real)
    # (1) One QP model per node, chosen by problem class only (INFRA-02 — never names a solver).
    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.meta[:T] = T

    # (2) Reuse the aggregator/device builders VERBATIM (RESEARCH Pattern 4, option a). This
    # populates ctx.meta[:objective] (U_ag, a QuadExpr) and ctx.meta[:agg_device_vars] (the
    # battery vars for the App. C check). Its :Rp/:Rq writes are never closed here (harmless).
    res = contribute!(agg, ctx; T = T)

    # (3) Coupling variable pag_j[t] pinned to the net active injection (thesis 3.22).
    @variable(model, pag[1:T])
    @constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    register_constraint!(ctx, :agr_coupling, coupling)

    # (4) Constant net reactive injection (thesis 3.23; DERs active-only, A3) for the μ update.
    tanφ = sqrt(1 - agg.φ^2) / agg.φ
    qag = Float64[-agg.Pdc[t] * tanφ for t in 1:T]

    # (5) Objective: aggregator utility − FIXED (ρ/2)·Σ pag² penalty (built ONCE). The linear
    # price+penalty-shift coefficient on pag[t] is applied per iteration in solve_agr! via
    # set_objective_coefficient — so the quadratic term here is the only ρ-penalty built once.
    @objective(model, Max, ctx.meta[:objective] - 0.5 * ρ * sum(pag[t]^2 for t in 1:T))

    return AgrOpt(model, ctx, collect(pag), qag, T, agg.bus, Float64(ρ))
end

"""
    solve_agr!(agr::AgrOpt, λ_j::AbstractVector, c_j::AbstractVector, ρ::Real)
        -> (; pag::Vector{Float64}, utility::Float64)

Re-solve the AGR-OPT subproblem for one ADMM iteration (RESEARCH Pattern 3, thesis 3.46)
WITHOUT rebuilding the JuMP model (ADMM-03). For each hour `t` it updates ONLY the linear
objective coefficient of the coupling variable `pag_j[t]` to `−λ_j[t] − ρ·c_j[t]` — the price
plus the shifted-penalty term (expanding `−(ρ/2)(pag+c)²` leaves `−ρ·c` on the linear part; the
FIXED `−ρ/2` quadratic self-term built by [`build_agr_opt`](@ref) is untouched). `λ_j` is a
plain `Float64` vector, NEVER a JuMP `Parameter` (a `λ·pag` Parameter×variable term is an
indefinite bilinear Clarabel rejects — RESEARCH Pitfall 1).

After the coefficient update it:
- gates the solve on [`assert_solved!`](@ref)`(...; dual = true)` (INFRA-03) before reading any
  value; and
- runs the MANDATORY App. C battery-complementarity check
  [`assert_battery_complementarity!`](@ref)`(agr.ctx; τ = 1e-6, T = agr.T)` — the batteries live
  in AGR-OPT now, so a degenerate simultaneous charge/discharge is caught here (threat T-06-10).

Returns `(; pag = value.(agr.pag), utility = value(agr.ctx.meta[:objective]))`: the solved net
active injection over the horizon and the aggregator utility `U_ag` value (the un-penalized
welfare term the ADMM loop recombines for reporting). Throws `ArgumentError` on a `λ_j`/`c_j`
length mismatch — the boundary guard against a silently-wrong coefficient update.
"""
function solve_agr!(agr::AgrOpt, λ_j::AbstractVector, c_j::AbstractVector, ρ::Real)
    length(λ_j) == agr.T ||
        throw(ArgumentError("solve_agr!: λ_j has length $(length(λ_j)), expected T=$(agr.T)"))
    length(c_j) == agr.T ||
        throw(ArgumentError("solve_agr!: c_j has length $(length(c_j)), expected T=$(agr.T)"))

    # Build-once re-solve (ADMM-03): one scalar coefficient update per hour — no JuMP rebuild.
    for t in 1:agr.T
        set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
    end

    # INFRA-03 gate before any value()/dual() read.
    assert_solved!(agr.model; dual = true)

    # App. C battery complementarity (τ = 1e-6 on the tight QP path) — batteries live here now.
    assert_battery_complementarity!(agr.ctx; τ = 1e-6, T = agr.T)

    return (; pag = value.(agr.pag), utility = value(agr.ctx.meta[:objective]))
end

export AgrOpt, build_agr_opt, solve_agr!
