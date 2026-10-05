# src/admm/admm_state.jl
#
# SEAM: AdmmState + reactive-mode singleton dispatch for the decomposed `solve_admm`
# Internal, unexported.
#
# FLOATING-POINT ORDER CONTRACT (binding; ADMM knife-edge canary iters = 56, welfare
# -4823.66604824162 must stay bit-identical): every statement here is MOVED from the former
# monolithic `solve_admm`, not rewritten. The ACTIVE accumulators keep the `for j in load_nodes,
# t in 1:T` order and are never fused; the reactive accumulators are independent variables and
# live in their own loop (bit-safe). Under OFF/CERTIFIED the former `+ 0.0` reactive terms are
# exact no-ops, so those hooks skip them; under LIVE the exact original expressions are kept.
# The reactive multiplier is named `μq`, NEVER bare `μ` (that is the adaptive-ρ band kwarg).

using JuMP

"""
Dispatch tag for the reactive-consensus mode (internal mirror of the public `ReactiveMode` enum).
"""
abstract type _ReactiveMode end
struct _ReactiveOff <: _ReactiveMode end
struct _ReactiveCertified <: _ReactiveMode end
struct _ReactiveLive <: _ReactiveMode end

"""
Map the public [`ReactiveMode`](@ref) enum to its singleton dispatch tag (total over the enum).
"""
function _react_mode(m::ReactiveMode.T)
    m == ReactiveMode.OFF && return _ReactiveOff()
    m == ReactiveMode.CERTIFIED && return _ReactiveCertified()
    m == ReactiveMode.LIVE && return _ReactiveLive()
    throw(ArgumentError("unknown ReactiveMode $m"))
end

"""
LIVE-only reactive dual-ascent state (mirrors the active `λ/a/c/pag_dso_prev` on the `qag` axis):
`μq` multiplier (warm-start 0), `d` reactive netflow target, `b` AGR's solved `qag_live`,
`qag_dso_prev` z-block snapshot, `ρ_qf` live reactive penalty, `ρ_q_frozen` latch.
"""
mutable struct _LiveState
    μq::Dict{Int, Vector{Float64}}
    d::Dict{Int, Vector{Float64}}
    b::Dict{Int, Vector{Float64}}
    qag_dso_prev::Dict{Int, Vector{Float64}}
    ρ_qf::Float64
    ρ_q_frozen::Bool
end

"""
    admm_supported(pf::AbstractPowerFlow) -> Bool

Trait: can `pf` drive the decentralized ADMM (`solve_admm`/`build_dso_opt`)? `true` for
[`ConvexBranchFlow`](@ref) (both variants), [`RestrictedBranchFlow`](@ref), [`MeshedFlow`](@ref)
and [`LinDistFlow`](@ref); `false` for everything else (`ACPowerFlow`, `DCPowerFlow`, ...).
DSO-OPT delegates network construction to the formulation's `contribute!`, so any formulation
whose `contribute!` yields the nodal-balance / `Rp,Rq` seam the ADMM coupling needs is supported.
Mirrored at the symbol level by `supports_pf(::ADMM, ...)`.
"""
admm_supported(::AbstractPowerFlow) = false
admm_supported(::Union{ConvexBranchFlow, RestrictedBranchFlow, MeshedFlow, LinDistFlow}) =
    true

"""
    _check_admm_pair!(fname::Symbol, feeder::AbstractFeeder, pf::AbstractPowerFlow)

Up-front validation of the (topology, formulation) pair: `pf` must be [`admm_supported`](@ref), and
a `MeshedFeeder` is valid ONLY with [`MeshedFlow`](@ref). Throws `ArgumentError` naming `fname`.
"""
function _check_admm_pair!(fname::Symbol, feeder::AbstractFeeder, pf::AbstractPowerFlow)
    admm_supported(pf) || throw(
        ArgumentError(
            "$fname: power flow $(typeof(pf)) is not ADMM-capable (supported: " *
            "ConvexBranchFlow, RestrictedBranchFlow, MeshedFlow, LinDistFlow)",
        ),
    )
    feeder isa MeshedFeeder &&
        !(pf isa MeshedFlow) &&
        throw(
            ArgumentError(
                "$fname is radial-only for $(typeof(pf)); got a MeshedFeeder - use pf = MeshedFlow() " *
                "for a meshed feeder",
            ),
        )
    return nothing
end

# Battery complementarity policy under ADMM: SOCP-class formulations keep the fail-loud gate
# (default path bit-identical); non-SOCP ones warn (mirrors welfare_solve.jl).
_batt_on_violation(st) = problem_class(st.dso.ctx.pf) isa SOCP ? :error : :warn
# Same policy for the 4Q-BESS peer certificate: strict (throw) on SOCP, `report = true` (warn) otherwise.
_report_4q(st) = !(problem_class(st.dso.ctx.pf) isa SOCP)


"""
Mutable iterate state of one `solve_admm` run (per-load-node length-`T` profiles, NEVER a JuMP
Parameter). `react` is `nothing` under OFF/CERTIFIED (no reactive arrays allocated).
"""
mutable struct AdmmState
    dso::DsoOpt
    agr_by_bus::Dict{Int, AgrOpt}
    load_nodes::Vector{Int}
    T::Int
    residuals::AdmmResiduals
    λ::Dict{Int, Vector{Float64}}
    c::Dict{Int, Vector{Float64}}
    a::Dict{Int, Vector{Float64}}
    pag_dso_prev::Dict{Int, Vector{Float64}}
    util::Dict{Int, Float64}
    p_import::Vector{Float64}
    ρf::Float64
    ρ_frozen::Bool
    exact_maxgap::Any
    converged_flag::Bool
    budget_exceeded_flag::Bool
    t0_wall_ns::UInt64
    react::Union{Nothing, _LiveState}
end

# ---- hook: state allocation ---------------------------------------------------------------------
_react_state(::Union{_ReactiveOff, _ReactiveCertified}, load_nodes, T, ρ_q) = nothing

function _react_state(::_ReactiveLive, load_nodes, T, ρ_q)
    mk() = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    μq = mk()
    d = mk()
    b = mk()
    qag_dso_prev = mk()
    return _LiveState(μq, d, b, qag_dso_prev, Float64(ρ_q), false)
end

# ---- hook: AGR solve ----------------------------------------------------------------------------
# `final = false`: mid-loop (check_battery = false, strict = false). `final = true`: the converged
# consolidation re-solve (battery + 4Q certificates, interior-point-loosened literals).
function _react_agr_solve!(
    ::Union{_ReactiveOff, _ReactiveCertified},
    st::AdmmState,
    j::Int;
    final::Bool = false,
    has_4q::Bool = false,
)
    agr = st.agr_by_bus[j]
    r = if final
        solve_agr!(
            agr,
            st.λ[j],
            st.c[j],
            st.ρf;
            check_battery = true,
            battery_on_violation = _batt_on_violation(st),
            τ_batt = 1e-3,
            strict = false,
            check_4q = has_4q,
            report_4q = _report_4q(st),
            rtol_4q = 1e-3,
            atol_4q = 1e-7,
        )
    else
        solve_agr!(agr, st.λ[j], st.c[j], st.ρf; check_battery = false, strict = false)
    end
    st.a[j] = r.pag
    st.util[j] = r.utility
    return r
end

function _react_agr_solve!(
    ::_ReactiveLive,
    st::AdmmState,
    j::Int;
    final::Bool = false,
    has_4q::Bool = false,
)
    agr = st.agr_by_bus[j]
    ls = st.react
    r = if final
        solve_agr!(
            agr,
            st.λ[j],
            st.c[j],
            st.ρf;
            μ_j = ls.μq[j],
            d_j = ls.d[j],
            ρ_q = ls.ρ_qf,
            check_battery = true,
            battery_on_violation = _batt_on_violation(st),
            τ_batt = 1e-3,
            strict = false,
            check_4q = has_4q,
            report_4q = _report_4q(st),
            rtol_4q = 1e-3,
            atol_4q = 1e-7,
        )
    else
        solve_agr!(
            agr,
            st.λ[j],
            st.c[j],
            st.ρf;
            μ_j = ls.μq[j],
            d_j = ls.d[j],
            ρ_q = ls.ρ_qf,
            check_battery = false,
            strict = false,
        )
    end
    st.a[j] = r.pag
    st.util[j] = r.utility
    if !final
        ls.b[j] = value.(agr.qag_live)
    end
    return r
end

# ---- hook: DSO objective-coefficient prepare (LIVE drives dso.qag; `b`, never `d`) --------------
_react_dso_prepare!(::Union{_ReactiveOff, _ReactiveCertified}, st::AdmmState) = nothing

function _react_dso_prepare!(::_ReactiveLive, st::AdmmState)
    ls = st.react
    for j in st.load_nodes, t in 1:(st.T)
        set_objective_coefficient(
            st.dso.model,
            st.dso.qag[j, t],
            -ls.μq[j][t] - ls.ρ_qf * ls.b[j][t],
        )
    end
    return nothing
end

# ---- hook: read the DSO reactive coupling iterate -----------------------------------------------
_react_dso_read(::Union{_ReactiveOff, _ReactiveCertified}, st::AdmmState) = nothing
_react_dso_read(::_ReactiveLive, st::AdmmState) = value.(st.dso.qag)

# ---- hook: reactive accumulators (Σ over j,t in the same order as the active ones) ---------------
_react_accumulate!(::Union{_ReactiveOff, _ReactiveCertified}, st::AdmmState, qag_dso) =
    nothing

function _react_accumulate!(::_ReactiveLive, st::AdmmState, qag_dso)
    ls = st.react
    sq_r_q = 0.0      # Σ (b − qag_dso)²   → ‖r_q‖₂
    sq_ds_q = 0.0     # Σ (Δ qag_dso)²     → ‖s_q‖₂ / ρ_q
    sq_b = 0.0        # Σ b²               → ‖b‖₂
    sq_qd = 0.0       # Σ qag_dso²         → ‖qag_dso‖₂
    sq_μq = 0.0       # Σ μq²              → ‖μq‖₂
    for j in st.load_nodes, t in 1:(st.T)
        rq = ls.b[j][t] - qag_dso[j, t]
        dzq = qag_dso[j, t] - ls.qag_dso_prev[j][t]
        sq_r_q += rq^2
        sq_ds_q += dzq^2
        sq_b += ls.b[j][t]^2
        sq_qd += qag_dso[j, t]^2
        sq_μq += ls.μq[j][t]^2
    end
    return (; sq_r_q, sq_ds_q, sq_b, sq_qd, sq_μq)
end

# ---- hook: JOINT stacked stopping-rule quantities (r_norm, s_norm, ε_pri, ε_dual) ---------------
function _react_stack(
    ::Union{_ReactiveOff, _ReactiveCertified},
    st::AdmmState,
    acc,
    sq_r,
    sq_ds,
    sq_a,
    sq_pd,
    sq_λ,
    p_p,
    ε_abs,
    ε_rel,
)
    r_norm = sqrt(sq_r)
    s_norm = st.ρf * sqrt(sq_ds)
    ε_pri = sqrt(p_p) * ε_abs + ε_rel * max(sqrt(sq_a), sqrt(sq_pd))
    ε_dual = sqrt(p_p) * ε_abs + ε_rel * sqrt(sq_λ)
    return r_norm, s_norm, ε_pri, ε_dual
end

function _react_stack(
    ::_ReactiveLive,
    st::AdmmState,
    acc,
    sq_r,
    sq_ds,
    sq_a,
    sq_pd,
    sq_λ,
    p_p,
    ε_abs,
    ε_rel,
)
    ρ_qf = st.react.ρ_qf
    r_norm = sqrt(sq_r + acc.sq_r_q)
    s_norm = st.ρf * sqrt(sq_ds) + ρ_qf * sqrt(acc.sq_ds_q)
    p_total = p_p * 2
    ε_pri =
        sqrt(p_total) * ε_abs + ε_rel * max(sqrt(sq_a + acc.sq_b), sqrt(sq_pd + acc.sq_qd))
    ε_dual = sqrt(p_total) * ε_abs + ε_rel * sqrt(sq_λ + acc.sq_μq)
    return r_norm, s_norm, ε_pri, ε_dual
end

# ---- hook: reactive dual-ascent step (μq += ρ_q (b − qag_dso); d = −qag_dso; snapshot) ----------
_react_dual_step!(::Union{_ReactiveOff, _ReactiveCertified}, st::AdmmState, qag_dso) =
    nothing

function _react_dual_step!(::_ReactiveLive, st::AdmmState, qag_dso)
    ls = st.react
    for j in st.load_nodes
        for t in 1:(st.T)
            ls.qag_dso_prev[j][t] = qag_dso[j, t]
            ls.μq[j][t] += ls.ρ_qf * (ls.b[j][t] - qag_dso[j, t])
            ls.d[j][t] = -qag_dso[j, t]
        end
    end
    return nothing
end

# ---- hook: independent ρ_q adaptation (reactive block's OWN r̂_q/ŝ_q) ---------------------------
_react_adapt_rho!(
    ::Union{_ReactiveOff, _ReactiveCertified},
    st::AdmmState,
    acc,
    p_p,
    ε_abs,
    ε_rel,
    μ,
    τ,
    ρ_min,
    ρ_max,
) = nothing

function _react_adapt_rho!(
    ::_ReactiveLive,
    st::AdmmState,
    acc,
    p_p,
    ε_abs,
    ε_rel,
    μ,
    τ,
    ρ_min,
    ρ_max,
)
    ls = st.react
    if !ls.ρ_q_frozen
        r_norm_q = sqrt(acc.sq_r_q)
        s_norm_q = ls.ρ_qf * sqrt(acc.sq_ds_q)
        ε_pri_q = sqrt(p_p) * ε_abs + ε_rel * max(sqrt(acc.sq_b), sqrt(acc.sq_qd))
        ε_dual_q = sqrt(p_p) * ε_abs + ε_rel * sqrt(acc.sq_μq)
        r̂_q = r_norm_q / ε_pri_q
        ŝ_q = s_norm_q / ε_dual_q
        if r̂_q <= 10 && ŝ_q <= 10
            ls.ρ_q_frozen = true
        else
            ρ_q_new = if r̂_q > μ * ŝ_q
                τ * ls.ρ_qf
            elseif ŝ_q > μ * r̂_q
                ls.ρ_qf / τ
            else
                ls.ρ_qf
            end
            ρ_q_new = clamp(ρ_q_new, ρ_min, ρ_max)
            if ρ_q_new != ls.ρ_qf
                ls.ρ_qf = ρ_q_new
                set_rho_q!(st.dso, ls.ρ_qf)
                for j in st.load_nodes
                    set_rho_q!(st.agr_by_bus[j], ls.ρ_qf)
                end
            end
        end
    end
    return nothing
end

# ---- hook: reactive default (smart default, moved out of the solve_admm signature) --------
_default_reactive_consensus(aggregators) =
    _any_flexible_reactive(aggregators) ? ReactiveMode.LIVE : ReactiveMode.OFF

# ---- hook: `:balance_q` no-slack certificate -----------------------------------------
# OFF: `:balance_q` is the inelastic constant closure, intentionally NOT gated.
_react_certify_q!(::_ReactiveOff, dso) = nothing

function _react_certify_q!(::Union{_ReactiveCertified, _ReactiveLive}, dso)
    let balance_q = dso.ctx.constraints[:balance_q]
        for j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
            assert_no_slack(dso.model, balance_q[j, t]; atol = 1e-6)
        end
    end
    return nothing
end

# ---- hook: published reactive outputs `(mu_q, q_devices)` ---------------------------------------
_react_outputs(::Union{_ReactiveOff, _ReactiveCertified}, st, agr_by_bus) =
    (nothing, nothing)

function _react_outputs(::_ReactiveLive, st::AdmmState, agr_by_bus)
    load_nodes = st.load_nodes
    T = st.T
    # SIGN CONVENTION: internal `μq[j]` converges to the NEGATED `dual(:balance_q[j])` (same
    # relationship as `λ` to `dual(:balance_p)`); reported `mu_q` is the negation, in the same
    # ascending-bus order as `λ_mat`. Never compare an individual FourQuadBESS `q` trajectory.
    mu_q_mat = reduce(vcat, (permutedims(-st.react.μq[j]) for j in load_nodes))
    q_devices = Dict{Int, Vector{Float64}}()
    for j in load_nodes
        for v in agr_by_bus[j].ctx.agg_device_vars[j]
            if haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)
                q_devices[j] = Float64[value(v.q[t]) for t in 1:T]
            end
        end
    end
    return (mu_q_mat, q_devices)
end
