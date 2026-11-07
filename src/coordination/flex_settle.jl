# src/coordination/flex_settle.jl
#
# SEAM: the money of the flexibility market. The physics record of one clear (stage 1, bids,
# stage 2, delivery; flex_clear.jl) is computed ONCE and shared by the payment rules, so the
# dispatch, the welfare and the AC verdict cannot depend on how the money is split.
#
# THE SETTLEMENT IS THE SAME LEDGER AS THE TARIFF LEGS. One primitive `build_settlement_ledger`
# call per clear, with:
#   - households and aggregators paying the baseline tariff on ALL metered (delivered) energy,
#     the same uniform price matrix as the flat and TOU legs;
#   - the DSO paying λ₀ on the lossless delivered import, again as in the flat and TOU legs;
#   - the flexibility payments booked as `flex_payments` rows, each one mirror pair
#     `(:aggregator, bus) <-> :dso`, so the conservation residual stays exactly 0.0.
#
# TARIFF ON ACTIVATION. Flexibility payments are made on the activated deviation, on top of the
# tariff on metered energy, so an up-activated unit earns the tariff it no longer pays plus the
# clearing price. This is standard local-market practice: retail energy and the flexibility
# service are settled separately. `tariff_on_activation = Σ p_t·Δ_{j,t}` quantifies the overlap.
# It is money only and never changes the dispatch or the welfare.
#
# ACTIVATED, NOT DELIVERED, IS PAID. The rows carry the activated Δ (plus the β phantom). The
# delivery shortfall is reported by the physics record, and no non-delivery penalty is booked;
# `flex_payment_on_delivered` recomputes the uniform payment on the delivered deviation n − b as
# an informational number.
#
# BASELINE INFLATION β CHANGES PAYMENTS ONLY. It adds phantom up-payment rows in congested hours
# with up-activation, priced like the real rows. The rows are real ledger money (the
# overpayment is reported); the physics record is the truthful clear's.

"""
    _baseline_price(input::SettlementInput, fm::FlexMarket; bins = nothing) -> Vector{Float64}

The stage-1 baseline tariff of a flexibility-market clear, derived from the DADP run exactly as
the flat and TOU legs derive theirs: `flat_prices(input)` for `baseline_tariff = :flat` (`bins`
ignored), and `tou_prices(input; bins)` for `:tou`, with `bins = default_tou_bins(input.T)` when
`bins === nothing`. The default bins are resolved only on the TOU path, so a non-daily flat
clear never meets the 24-hour-only default. Internal (unexported).
"""
function _baseline_price(
    input::SettlementInput,
    fm::FlexMarket;
    bins::Union{Nothing, Vector{Vector{Int}}} = nothing,
)
    fm.baseline_tariff === :flat && return flat_prices(input)
    b = bins === nothing ? default_tou_bins(input.T) : bins
    return tou_prices(input; bins = b)
end

# One flexibility-payment row of the ledger's `flex_payments` flow.
const _FlexRow =
    NamedTuple{(:bus, :t, :price, :quantity), Tuple{Int, Int, Float64, Float64}}

# Internal: the price of the highest accepted up block of hour `t` (blocks are in
# non-decreasing price order); a block counts as accepted above the range floor, and if no
# block clears the floor the highest block with a non-zero quantity is used.
function _marginal_up_price(
    u::AbstractMatrix{Float64},
    up_m::AbstractMatrix{Float64},
    t::Int,
)
    k = findlast(>(FLEX_RANGE_FLOOR), view(u, t, :))
    k === nothing && (k = findlast(!=(0.0), view(u, t, :)))
    k === nothing && throw(
        ArgumentError("_marginal_up_price: hour $t has no accepted up block (internal)."),
    )
    return up_m[t, k]
end

"""
    _flex_payment_rows(phys, fm::FlexMarket, agg_buses::AbstractVector{Int}) -> NamedTuple

The flexibility-payment rows of one clear, from its physics record `phys` (`status == "ok"`)
and the bus of each aggregator in physics order. Internal (unexported). Returns a NamedTuple
with the fields `rows`, `flex_payments_total`, `baseline_overpayment`, `tariff_on_activation`
and `flex_payment_on_delivered`. `rows` is a `Vector` of `(; bus, t, price, quantity)` rows
(`quantity > 0` is up-flex, more injection; the aggregator earns `price·quantity`):

  - `:uniform`: one row per aggregator and hour with `Δ ≠ 0`, `(bus, t, π_t, Δ_t)`, the
    stage-2 clearing price on the whole activated deviation;
  - `:pay_as_bid`: one row per accepted block (non-zero quantity), up blocks `(m_k, +u_k)` and
    down blocks `(g_k, −w_k)`, each at its own bid price. Rejected blocks come back from the
    interior-point solver at about `1e-9` of either sign; they are booked as they are, so the
    row quantities of each hour sum to its `Δ` and no threshold decides what was accepted.

With `β = fm.baseline_inflation > 0`, every congested hour with up-activation
(`Δ_t > FLEX_RANGE_FLOOR`) adds one phantom row of quantity `β·max(−b_t, 0)`: the consumption
baseline is reported inflated, so the up-activation looks larger than it was. A net exporter's
baseline is not inflated. The phantom is priced at `π_t` (uniform) or at the price of the
highest accepted up block (pay-as-bid). With `β == 0` no phantom row exists.

`flex_payments_total` sums `price·quantity` over the real rows, and `baseline_overpayment`
over the phantom rows. `tariff_on_activation = Σ_j Σ_t p_t·Δ_{j,t}` (with `p` the baseline
tariff) is the informational tariff overlap. `flex_payment_on_delivered = Σ π·(n − b)` over the
delivered deviation is reported for the uniform rule and is `missing` for pay-as-bid.
"""
function _flex_payment_rows(phys, fm::FlexMarket, agg_buses::AbstractVector{Int})
    phys.status == "ok" || throw(
        ArgumentError(
            "_flex_payment_rows: physics status is $(repr(phys.status)), not ok.",
        ),
    )
    length(agg_buses) == length(phys.Δ) || throw(
        ArgumentError(
            "_flex_payment_rows: $(length(agg_buses)) buses for $(length(phys.Δ)) aggregators.",
        ),
    )
    p = phys.price
    T = length(p)
    β = fm.baseline_inflation
    rows = _FlexRow[]
    for (k, bus) in enumerate(agg_buses)
        Δ = phys.Δ[k]
        if fm.payment_rule === :uniform
            for t in 1:T
                Δ[t] != 0 && push!(rows, _FlexRow((bus, t, phys.π[k][t], Δ[t])))
            end
        else
            fb = phys.bids[k]
            u = phys.u[k]
            w = phys.w[k]
            for t in 1:T
                for kk in axes(u, 2)
                    u[t, kk] != 0 &&
                        push!(rows, _FlexRow((bus, t, fb.up_m[t, kk], u[t, kk])))
                end
                for kk in axes(w, 2)
                    w[t, kk] != 0 &&
                        push!(rows, _FlexRow((bus, t, fb.dn_g[t, kk], -w[t, kk])))
                end
            end
        end
    end
    flex_payments_total = 0.0
    for r in rows
        flex_payments_total += r.price * r.quantity
    end

    baseline_overpayment = 0.0
    if β > 0
        for (k, bus) in enumerate(agg_buses), t in 1:T
            (phys.congested[t] && phys.Δ[k][t] > FLEX_RANGE_FLOOR) || continue
            q = β * max(-phys.baseline.net[k][t], 0.0)
            price =
                fm.payment_rule === :uniform ? phys.π[k][t] :
                _marginal_up_price(phys.u[k], phys.bids[k].up_m, t)
            push!(rows, _FlexRow((bus, t, price, q)))
            baseline_overpayment += price * q
        end
    end

    tariff_on_activation = 0.0
    for Δ in phys.Δ, t in 1:T
        tariff_on_activation += p[t] * Δ[t]
    end

    flex_payment_on_delivered = missing
    if fm.payment_rule === :uniform
        s = 0.0
        for k in eachindex(agg_buses), t in 1:T
            s += phys.π[k][t] * (phys.delivered.net[k][t] - phys.baseline.net[k][t])
        end
        flex_payment_on_delivered = s
    end

    return (;
        rows,
        flex_payments_total,
        baseline_overpayment,
        tariff_on_activation,
        flex_payment_on_delivered,
    )
end

"""
    _flex_settle(phys, fm::FlexMarket, agg_buses::AbstractVector{Int}, input::SettlementInput;
                 T::Int, λ₀) -> NamedTuple

The settlement record of one clear (`phys.status == "ok"`). Internal (unexported). Builds the
uniform baseline-tariff matrix (every row the baseline price, over `input.buses`), the
delivered nets and utilities per bus, and the lossless delivered import
`p_import_lossless[t] = −Σ_j n_j[t]`, then calls the primitive `build_settlement_ledger` with
`source = :flex_market` and the rows of [`_flex_payment_rows`](@ref) as `flex_payments`.

Returns a NamedTuple with the fields `ledger`, `payment_rows`, the four money numbers of
[`_flex_payment_rows`](@ref), `p_import_lossless`, `bills`, `surplus`, `welfare_lossless` and
`welfare_socp_import`, where

  - `bills[b] = −balances[(:aggregator, b)]`;
  - `surplus[b] = U_b(n_b) + balances[(:aggregator, b)]`;
  - `welfare_lossless = Σ_j U_j(n_j) − Σ_t λ₀[t]·p_import_lossless[t]`, the flat and TOU legs'
    convention;
  - `welfare_socp_import = Σ_j U_j(n_j) − Σ_t λ₀[t]·p_import_stage2[t]`, with the stage-2 SOCP
    import (losses included), exact for the delivered dispatch only when the shortfall is 0.
"""
function _flex_settle(
    phys,
    fm::FlexMarket,
    agg_buses::AbstractVector{Int},
    input::SettlementInput;
    T::Int,
    λ₀,
)
    pay = _flex_payment_rows(phys, fm, agg_buses)
    buses = input.buses
    nb = length(buses)
    p = phys.price
    P = Matrix{Float64}(undef, nb, T)
    for i in 1:nb, t in 1:T
        P[i, t] = p[t]
    end
    slot = Dict(b => k for (k, b) in enumerate(agg_buses))
    nets = phys.delivered.net
    utils = phys.delivered.utility
    bus_nets = Dict{Int, Vector{Float64}}(b => nets[slot[b]] for b in buses)
    bus_utils = Dict{Int, Float64}(b => utils[slot[b]] for b in buses)
    p_import_lossless = Float64[-sum(nets[slot[b]][t] for b in buses) for t in 1:T]
    λ = Float64[λ₀[t] for t in 1:T]
    led = build_settlement_ledger(
        P,
        bus_nets,
        bus_utils,
        p_import_lossless,
        λ,
        buses;
        T = T,
        source = :flex_market,
        flex_payments = pay.rows,
    )
    bills = Dict{Int, Float64}(b => -led.balances[(:aggregator, b)] for b in buses)
    surplus = Dict{Int, Float64}(
        b => bus_utils[b] + led.balances[(:aggregator, b)] for b in buses
    )
    U = sum(bus_utils[b] for b in buses)
    welfare_lossless = U - sum(λ[t] * p_import_lossless[t] for t in 1:T)
    welfare_socp_import = U - sum(λ[t] * phys.p_import_stage2[t] for t in 1:T)
    return (;
        ledger = led,
        payment_rows = pay.rows,
        pay.flex_payments_total,
        pay.baseline_overpayment,
        pay.tariff_on_activation,
        pay.flex_payment_on_delivered,
        p_import_lossless,
        bills,
        surplus,
        welfare_lossless,
        welfare_socp_import,
    )
end

"""
    clear_flex_market(feeder, pf, aggs, input::SettlementInput, fm::FlexMarket; T, λ₀,
                      bins = nothing, optimizer = nothing, τ_batt = 1e-3,
                      actors = nothing) -> NamedTuple

Clear one DSO flexibility market ([`FlexMarket`](@ref)) after a DADP run and settle it on the
same [`SettlementLedger`](@ref) as the tariff legs. For example, after
`ctx, _, _ = solve_welfare(feeder, pf, aggs; T, λ₀, allow_export = true)`, the call
`clear_flex_market(feeder, pf, aggs, settlement_input(ctx; T, λ₀), FlexMarket(); T, λ₀)`
returns the flexibility market's settlement record.

The baseline tariff is derived from `input` like the flat and TOU legs (`flat_prices`, or
`tou_prices` with `bins`; the default TOU bins are resolved only when
`fm.baseline_tariff == :tou`, before any solve). The physics of the clear (stage-1 baseline,
truthful bids, stage-2 redispatch on `feeder` with `pf` and the SOCP exactness gate, delivery
re-solves) is computed once, so bid generation runs once per clear and the payment rule and β
change money only. `optimizer` reaches the stage-2 welfare solve (`nothing` is its default).

**Settlement.** Households and aggregators pay the baseline tariff on all metered (delivered)
energy, the DSO pays λ₀ on the lossless delivered import, and the DSO pays the aggregators the
flexibility payments as conserving mirror pairs, so `ledger_residual(ledger) == 0.0`. The
payment is on the activated deviation: `:uniform` pays `π_{j,t}·Δ_{j,t}` at the stage-2
clearing price, `:pay_as_bid` pays each accepted block at its own bid price. Because the
tariff is also paid on metered energy, an up-activated unit earns tariff plus clearing price
(retail energy and the flexibility service are settled separately). The informational
`tariff_on_activation`, equal to `Σ p_t·Δ_{j,t}`, reports that overlap, money only. β adds
phantom up-payments in congested hours (`baseline_overpayment`).

**Welfare.** `welfare_lossless = Σ_j U_j(n_j) − λ₀ᵀ(−Σ_j n_j)` is social welfare of the
delivered dispatch with the lossless import, the convention of the flat and TOU legs (device
utilities, never an objective value). `welfare_socp_import` uses the stage-2 SOCP import
instead (losses included) and is exact only when the delivery shortfall is 0.

**Reactive power.** Stage 2 holds each bus's reactive draw at the inelastic `−Pdc·tanφ`; the
flexibility product is active power only. The AC check runs on the delivered nets with the
original aggregators (`ac_feasibility_status`) and reports, never gates.

**Actors.** Settling profit-seeking aggregator actors (`Portfolio` / `ProfitObjective`) here
is a recorded scope decision (future work), so `actors` must be `nothing`. An `input` built
from an actor-objective run (`solve_welfare` or `solve_admm` with `actors`) is not detected:
it settles like any other input, and its wedges are not carried into this ledger.

**Returns** a NamedTuple with the fields, in order, `status`, `notes`, `market`,
`baseline_price`, `physics`, `ledger`, `feasibility`, `payment_rows`, `flex_payments_total`,
`baseline_overpayment`, `tariff_on_activation`, `flex_payment_on_delivered`,
`p_import_lossless`, `bills`, `surplus`, `welfare_lossless` and `welfare_socp_import`.
`physics` is the full physics record; `bills` and `surplus` are per-bus `Dict`s.
`status` is `"ok"`, `"infeasible_redispatch"` (the offered flexibility
cannot restore network feasibility), `"inexact_redispatch"` (the stage-2 SOCP is not exact) or
`"error:<Type>"` (another solver outcome, with `notes`). A status other than `"ok"` never
throws: `ledger`, `feasibility`, `payment_rows`, `p_import_lossless`, `bills` and `surplus` are
`nothing`, and the money and welfare numbers are `missing`.

Throws `ArgumentError` before any solve when `actors` is not `nothing`, when `input.T != T`,
when the aggregator buses are not exactly `input.buses` (one aggregator per bus, in ascending
bus order), or when the default TOU bins do not exist for `T`; the physics guards of the clear apply too, also before any
solve (among them, `pf` must be a `ConvexBranchFlow` and every `λ₀[t]` must be positive). A
failure of the congested-hour price split after the redispatch is the status
`"error:dlmp_split"`.
"""
function clear_flex_market(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggs::AbstractVector{<:Aggregator},
    input::SettlementInput,
    fm::FlexMarket;
    T::Int,
    λ₀,
    bins::Union{Nothing, Vector{Vector{Int}}} = nothing,
    optimizer = nothing,
    τ_batt::Real = 1e-3,
    actors = nothing,
)
    actors === nothing || throw(
        ArgumentError(
            "clear_flex_market: actors are not supported. Settling profit-seeking aggregator " *
            "actors (Portfolio / ProfitObjective) through the flexibility market or the " *
            "tariff comparison is a recorded scope decision (future work: wedge lines and " *
            "flexibility payments in one ledger); pass actors = nothing.",
        ),
    )
    input.T == T || throw(
        ArgumentError("clear_flex_market: input.T = $(input.T) does not match T = $T."),
    )
    agg_buses = Int[a.bus for a in aggs]
    agg_buses == input.buses || throw(
        ArgumentError(
            "clear_flex_market: the aggregator buses $(agg_buses) must be exactly the DADP " *
            "input buses $(input.buses): one aggregator per bus, in ascending bus order " *
            "(the stage-2 settlement folds in bus order).",
        ),
    )
    baseline_price = _baseline_price(input, fm; bins = bins)
    phys = _flex_physics(
        feeder,
        pf,
        aggs,
        baseline_price;
        T = T,
        λ₀ = λ₀,
        n_blocks = fm.n_blocks,
        optimizer = optimizer,
        τ_batt = τ_batt,
    )
    if phys.status != "ok"
        return (;
            status = phys.status,
            notes = phys.notes,
            market = fm,
            baseline_price,
            physics = phys,
            ledger = nothing,
            feasibility = nothing,
            payment_rows = nothing,
            flex_payments_total = missing,
            baseline_overpayment = missing,
            tariff_on_activation = missing,
            flex_payment_on_delivered = missing,
            p_import_lossless = nothing,
            bills = nothing,
            surplus = nothing,
            welfare_lossless = missing,
            welfare_socp_import = missing,
        )
    end
    feasibility = ac_feasibility_status(feeder, aggs, phys.delivered.net; T = T)
    s = _flex_settle(phys, fm, agg_buses, input; T = T, λ₀ = λ₀)
    return (;
        status = phys.status,
        notes = phys.notes,
        market = fm,
        baseline_price,
        physics = phys,
        s.ledger,
        feasibility,
        s.payment_rows,
        s.flex_payments_total,
        s.baseline_overpayment,
        s.tariff_on_activation,
        s.flex_payment_on_delivered,
        s.p_import_lossless,
        s.bills,
        s.surplus,
        s.welfare_lossless,
        s.welfare_socp_import,
    )
end

export clear_flex_market
