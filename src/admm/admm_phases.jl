# src/admm/admm_phases.jl
#
# SEAM: the named internal phases of `solve_admm` (Phase 34, ARCH-05): `_admm_build`,
# `_admm_iterate!`, `_adapt_rho!` (certification `_admm_certify` follows in a later plan).
# Code is MOVED from the former monolithic loop; see admm_state.jl for the floating-point order
# contract (statement order per iteration: AGR -> LIVE dso.qag coefficients -> solve_dso! ->
# accumulate -> record! -> converged? -> budget? -> dual step -> ρ adapt -> ρ_q adapt;
# `set_rho!` order: dso first, then each AGR in `load_nodes` order).

using JuMP

"""
BUILD ONCE (ADMM-03): one AGR-OPT per aggregator and the whole-network DSO-OPT, the 1:1
node<->aggregator guards, the residual ledger and the initial [`AdmmState`](@ref). No JuMP model is
constructed after this returns.
"""
function _admm_build(
    feeder,
    pf,
    aggregators,
    T::Int,
    λ₀,
    ρf::Float64,
    ρ_qf::Float64,
    mode::ReactiveMode,
    rmode::_ReactiveMode,
)
    dso = build_dso_opt(
        feeder,
        aggregators,
        T;
        ρ = ρf,
        λ₀ = λ₀,
        reactive_consensus = mode,
        ρ_q = ρ_qf,
    )
    load_nodes = dso.load_nodes                       # ascending non-root aggregator buses

    # 1:1 node<->aggregator coupling (multi-aggregator-per-bus is a Phase-7 generalization).
    length(aggregators) == length(load_nodes) || throw(
        ArgumentError(
            "solve_admm assumes one aggregator per load node (got $(length(aggregators)) " *
            "aggregators for $(length(load_nodes)) load nodes); multi-aggregator-per-bus " *
            "coupling is a Phase-7 extension",
        ),
    )
    agr_by_bus = Dict{Int, AgrOpt}()
    for agg in aggregators
        haskey(agr_by_bus, agg.bus) && throw(
            ArgumentError("two aggregators share bus $(agg.bus); solve_admm assumes 1:1"),
        )
        agr_by_bus[agg.bus] =
            build_agr_opt(agg, T; ρ = ρf, reactive_mode = mode, ρ_q = ρ_qf)
    end

    N = length(feeder.buses)
    residuals = AdmmResiduals(N, T)

    # Warm-start the INTERNAL multiplier at −λ₀ (it converges to −DADP; see solve_admm).
    λ = Dict{Int, Vector{Float64}}(j => Float64[-λ₀[t] for t in 1:T] for j in load_nodes)
    c = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # netflow target for AGR
    a = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # pag target for DSO
    # z-block snapshot, zeros so iteration 1's s is large (no 1-iteration false convergence).
    pag_dso_prev = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    util = Dict{Int, Float64}(j => 0.0 for j in load_nodes)
    p_import = zeros(Float64, T)

    react = _react_state(rmode, load_nodes, T, ρ_qf)

    return AdmmState(
        dso,
        agr_by_bus,
        load_nodes,
        T,
        residuals,
        λ,
        c,
        a,
        pag_dso_prev,
        util,
        p_import,
        ρf,
        false,                 # ρ_frozen
        nothing,               # exact_maxgap
        false,                 # converged_flag
        false,                 # budget_exceeded_flag
        time_ns(),             # t0_wall_ns: loop-entry timestamp (wall-clock budget)
        react,
    )
end

"""
Residual-balancing adaptive ρ (Boyd §3.4.1; RESEARCH Pattern 4) on the ACTIVE-block-only
normalized residuals, then the independent reactive ρ_q hook. `set_rho!` on the DSO first, then
each AGR in `load_nodes` order, only on an actual change. λ is never rescaled.
"""
function _adapt_rho!(
    st::AdmmState,
    rmode::_ReactiveMode,
    r_norm_p,
    s_norm_p,
    ε_pri_p,
    ε_dual_p,
    acc,
    p_p,
    ε_abs,
    ε_rel,
    μ,
    τ,
    ρ_min,
    ρ_max,
)
    if !st.ρ_frozen
        r̂ = r_norm_p / ε_pri_p
        ŝ = s_norm_p / ε_dual_p
        if r̂ <= 10 && ŝ <= 10
            st.ρ_frozen = true
        else
            ρ_new = if r̂ > μ * ŝ
                τ * st.ρf
            elseif ŝ > μ * r̂
                st.ρf / τ
            else
                st.ρf
            end
            ρ_new = clamp(ρ_new, ρ_min, ρ_max)
            if ρ_new != st.ρf
                st.ρf = ρ_new
                set_rho!(st.dso, st.ρf)
                for j in st.load_nodes
                    set_rho!(st.agr_by_bus[j], st.ρf)
                end
            end
        end
    end
    _react_adapt_rho!(rmode, st, acc, p_p, ε_abs, ε_rel, μ, τ, ρ_min, ρ_max)
    return nothing
end

"""
The consensus loop (thesis 3.46/3.47 dual ascent) on an [`AdmmState`](@ref). Returns when
`converged_flag` (joint stacked Boyd two-residual stop) or `budget_exceeded_flag` is latched, or
`maxiter` is exhausted (the caller throws the fail-loud `ConvergenceError`).
"""
function _admm_iterate!(
    st::AdmmState,
    rmode::_ReactiveMode,
    maxiter::Int,
    ε_abs,
    ε_rel,
    τ,
    μ,
    ρ_min,
    ρ_max,
    time_limit_s,
)
    load_nodes = st.load_nodes
    T = st.T
    dso = st.dso
    λ, c, a = st.λ, st.c, st.a
    pag_dso_prev = st.pag_dso_prev
    residuals = st.residuals
    for k in 1:maxiter
        # (1) AGR-OPT[j] ∀j: coeff −λ_j − ρ·c_j (thesis 3.46). Mid-loop: no battery/4Q certificate.
        for j in load_nodes
            _react_agr_solve!(rmode, st, j)
        end

        # (2) DSO-OPT: coeff −λ_j − ρ·a_j (thesis 3.47); LIVE first sets dso.qag coefficients.
        _react_dso_prepare!(rmode, st)
        dres = solve_dso!(dso, λ, a, st.ρf; check_exact = false, strict = false)
        pag_dso = dres.pag_dso
        st.p_import = dres.p_import
        qag_dso = _react_dso_read(rmode, st)

        # (3) BOYD two-residual diagnostics. ACTIVE accumulators keep the original order.
        sq_r = 0.0        # Σ (a − pag_dso)²        → ‖r_p‖₂
        sq_ds = 0.0       # Σ (Δ pag_dso)²          → ‖s_p‖₂ / ρ
        sq_a = 0.0        # Σ a²                    → ‖a‖₂
        sq_pd = 0.0       # Σ pag_dso²              → ‖pag_dso‖₂
        sq_λ = 0.0        # Σ λ²                    → ‖λ‖₂
        for j in load_nodes, t in 1:T
            rp = a[j][t] - pag_dso[j, t]
            dz = pag_dso[j, t] - pag_dso_prev[j][t]
            sq_r += rp^2
            sq_ds += dz^2
            sq_a += a[j][t]^2
            sq_pd += pag_dso[j, t]^2
            sq_λ += λ[j][t]^2
        end
        acc = _react_accumulate!(rmode, st, qag_dso)

        # ACTIVE-ONLY quantities (independent active-ρ decision; LIVE can never contaminate it).
        r_norm_p = sqrt(sq_r)
        s_norm_p = st.ρf * sqrt(sq_ds)
        p_p = length(load_nodes) * T
        ε_pri_p = sqrt(p_p) * ε_abs + ε_rel * max(sqrt(sq_a), sqrt(sq_pd))
        ε_dual_p = sqrt(p_p) * ε_abs + ε_rel * sqrt(sq_λ)

        # (4) JOINT stacked stopping quantities (one record!/converged call; never per-block).
        r_norm, s_norm, ε_pri, ε_dual =
            _react_stack(rmode, st, acc, sq_r, sq_ds, sq_a, sq_pd, sq_λ, p_p, ε_abs, ε_rel)
        price_gap = st.ρf * r_norm_p   # ACTIVE-only move even under LIVE

        record!(residuals, k, r_norm, s_norm, st.ρf, ε_pri, ε_dual, price_gap)

        if converged(residuals, ε_pri, ε_dual)
            st.converged_flag = true
            break
        end

        # Wall-clock budget (Phase 25, D-18): after the convergence check, before the dual step.
        if time_limit_s !== nothing && (time_ns() - st.t0_wall_ns) / 1.0e9 > time_limit_s
            st.budget_exceeded_flag = true
            break
        end

        # Dual ascent λ ← λ + ρ·R (UNSCALED), netflow target c = −pag_dso, z-block snapshot.
        for j in load_nodes
            for t in 1:T
                pag_dso_prev[j][t] = pag_dso[j, t]
                λ[j][t] += st.ρf * (a[j][t] - pag_dso[j, t])
                c[j][t] = -pag_dso[j, t]
            end
        end
        _react_dual_step!(rmode, st, qag_dso)

        # (5) adaptive ρ (active) then independent ρ_q (reactive hook).
        _adapt_rho!(
            st,
            rmode,
            r_norm_p,
            s_norm_p,
            ε_pri_p,
            ε_dual_p,
            acc,
            p_p,
            ε_abs,
            ε_rel,
            μ,
            τ,
            ρ_min,
            ρ_max,
        )
    end
    return nothing
end
