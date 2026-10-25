# src/settlement/price_taker.jl
#
# SEAM: thin counterfactual dispatch at FIXED exogenous prices — the price-taker
# QP behind the `:flat`/`:tou` tariff legs (SETL-02).
#
# THE ONE DELIBERATE DIFFERENCE FROM THE ADMM MECHANISM (research-locked, Phase-41):
# this builder mirrors `build_agr_opt` (`src/admm/AgrOpt.jl:134-192`) and
# `_fit_opt_solve`'s self-contained solve shape (`src/pricing/fit.jl:155-245`)
# VERBATIM — `Model(select_optimizer(QP()))` → `ModelContext` → `contribute!`
# (devices contributed untouched) → `pag` coupling (thesis 3.22) → objective —
# EXCEPT the objective: `Max ctx.objective + Σ_t p[t]·pag[t]` carries NO
# `−(ρ/2)·Σ pag²` penalty. `build_agr_opt` builds that fixed quadratic
# (AgrOpt.jl:173) and `solve_agr!` installs the linear coefficient
# `−λ_j[t] − ρ·c_j[t]` mid-loop (AgrOpt.jl:308); at the production `ρ = 100` that
# penalty MATERIALLY DISTORTS a price-taker optimum (a price-taker has no
# consensus term to damp). Never reuse `solve_agr!` for a settlement leg; never
# add a ρ term here — the counterfactual-validity certificate in
# test_settlement.jl pins the unshaded rated-bounds dispatch.
#
# Prices are plain `Float64` vectors, NEVER JuMP `Parameter`s (AgrOpt.jl header
# convention: a Parameter×variable price term is an indefinite bilinear the convex
# conic backend rejects). Batteries are INCLUDED in the device set (A1 resolution):
# the rebound metric explicitly requires battery-driven shifts, so the full-asset
# counterfactual IS the deliverable — the asymmetry vs `fit_baseline`'s batteryless
# A4 is a documented comparison property, not a simplification.
#
# BATTERY CERTIFICATE (report semantics, Pitfall 1): `assert_battery_complementarity!`
# supports only `(:error, :warn)` (`src/models/welfare_solve.jl:358`); this file
# implements the research's `:report` semantics by calling it with
# `on_violation = :error` inside try/catch and recording the `CertificateError` on
# the result — `battery_certificate = :refused` + the message. A refusal is a
# MEASURED OUTCOME (Phase-40 refusal precedent), never a dropped dispatch, and τ is
# NEVER loosened: it stays at the ADMM-consolidation discipline `τ_batt = 1e-3`.
#
# SIGN CONVENTION (matches `agr_prices` and `welfare_accounting`'s transfer): `p`
# is the PUBLISHED price; a net exporter (`pag > 0`) EARNS `p·pag`, an importer
# PAYS. `utility` is the pure device-utility term (`value(ctx.objective)`,
# EXCLUDING the price revenue) — revenue settles as ledger transfers, matching
# `welfare_accounting`'s U semantics.
#
# GOLDEN POLICY: `src/admm/` and `src/models/` are consumed, never modified.

export price_taker_dispatch, price_taker_dispatches

"""
    price_taker_dispatch(agg::Aggregator, price::AbstractVector{<:Real};
                         T = length(price), τ_batt = 1e-3) ->
        (; net::Vector{Float64}, utility::Float64,
           battery_certificate::Symbol, battery_message::String)

Thin penalty-free counterfactual dispatch of ONE aggregator at the FIXED exogenous
price vector `price` (length `T`): `Max U_ag(devices) + Σ_t price[t]·pag[t]` s.t.
`pag[t] == Σ_d p_inject_d[t] − Pdc[t]` (thesis 3.22), devices contributed verbatim
via `contribute!`. Solves through `Model(select_optimizer(QP()))` (never a named
solver) and gates on `assert_solved!(model; dual = false)` before any value is
read (no dual is consumed here).

Returns:

  - `net` — the solved net active injection `pag` per hour (net INJECTION: an
    exporter earns `price·net`, an importer pays);
  - `utility` — the pure device-utility term `value(ctx.objective)`, EXCLUDING the
    price revenue (revenue settles as ledger transfers, matching
    `welfare_accounting`'s U semantics);
  - `battery_certificate` — `:ok` when the App. C battery-complementarity check
    passed, `:refused` when it threw `CertificateError` (recorded on the result
    together with `battery_message`; a MEASURED OUTCOME, never rethrown, never
    tuned away — under a constant `:flat` price the arbitrage problem is degenerate
    and interior-point solvers can co-activate charge/discharge), or `:not_checked`
    when the aggregator carries no battery vars (the check is a no-op then);
  - `battery_message` — the refusal message (`""` otherwise).

`τ_batt = 1e-3` is the ADMM-consolidation discipline — NEVER loosen it to make a
leg pass (the honesty policy; Phase-40 refusal precedent).

Guards: `length(price) == T`, all prices finite, and the aggregator's `Pdc` length
(`contribute!`'s own guard) — each a loud `ArgumentError`.
"""
function price_taker_dispatch(
    agg::Aggregator,
    price::AbstractVector{<:Real};
    T::Int = length(price),
    τ_batt::Real = 1e-3,
)
    length(price) == T || throw(
        ArgumentError(
            "price_taker_dispatch: price has length $(length(price)), expected T=$T",
        ),
    )
    for t in 1:T
        isfinite(price[t]) || throw(
            ArgumentError(
                "price_taker_dispatch: price[$t] is non-finite ($(price[t])) — " *
                "refusing to build a counterfactual on a non-finite price.",
            ),
        )
    end
    T >= 1 || throw(ArgumentError("price_taker_dispatch: T=$T must be at least 1"))

    # Same build shape as build_agr_opt (AgrOpt.jl:148-162) — minus the ρ penalty.
    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.T = T
    res = contribute!(agg, ctx; T = T)

    @variable(model, pag[1:T])
    @constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    register_constraint!(ctx, :price_taker_coupling, coupling)

    # THE deliberate difference (research-locked): the price term enters the
    # objective and NO −(ρ/2)·Σ pag² self-penalty exists here.
    @objective(model, Max, ctx.objective + sum(price[t] * pag[t] for t in 1:T))

    assert_solved!(model; dual = false)

    net = Float64[value(pag[t]) for t in 1:T]
    utility = value(ctx.objective)

    # Battery complementarity as a RECORDED status (report semantics over the
    # existing (:error, :warn) API — try/catch the :error branch; never rethrow,
    # never loosen τ). :not_checked when the aggregator registered no battery vars
    # (the check's own documented no-op case).
    battery_certificate = :ok
    battery_message = ""
    if isempty(ctx.agg_device_vars)
        battery_certificate = :not_checked
    else
        try
            assert_battery_complementarity!(ctx; τ = τ_batt, T = T, on_violation = :error)
        catch err
            err isa CertificateError || rethrow()
            battery_certificate = :refused
            battery_message = err.msg
        end
    end

    return (; net, utility, battery_certificate, battery_message)
end

"""
    price_taker_dispatches(aggs::AbstractVector{<:Aggregator}, price::AbstractVector{<:Real};
                           kwargs...) -> Vector{<:NamedTuple}

[`price_taker_dispatch`](@ref) mapped over `aggs` at the SAME fixed price vector —
the per-aggregator counterfactual rows the tariff-comparison harness assembles.
`kwargs` forward (`T`, `τ_batt`). An empty vector throws an `ArgumentError` (a
comparison with no aggregators is a caller bug, not an empty result).
"""
function price_taker_dispatches(
    aggs::AbstractVector{<:Aggregator},
    price::AbstractVector{<:Real};
    kwargs...,
)
    isempty(aggs) && throw(
        ArgumentError(
            "price_taker_dispatches: empty aggregator vector — a counterfactual " *
            "needs at least one aggregator.",
        ),
    )
    return map(agg -> price_taker_dispatch(agg, price; kwargs...), aggs)
end

"""
    household_dispatches(houses::AbstractVector{<:Aggregator}, price::AbstractVector{<:Real};
                         kwargs...) -> Vector{<:NamedTuple}

Readability alias for [`price_taker_dispatches`](@ref) at the HOUSEHOLD level
(SETL-01's per-household attribution): at a fixed price the aggregator problem
separates across member houses, so each house re-solves its own tiny QP at the
same price and the sums reconcile to the aggregator's dispatch/utility within a
measured tolerance (Pitfall 5 — never claimed bitwise). Houses ARE single-house
`Aggregator`s per the Phase-40 construction (`_case_a_house`).
"""
function household_dispatches(
    houses::AbstractVector{<:Aggregator},
    price::AbstractVector{<:Real};
    kwargs...,
)
    return price_taker_dispatches(houses, price; kwargs...)
end
