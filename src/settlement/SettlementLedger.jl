# src/settlement/SettlementLedger.jl
#
# SEAM: per-actor settlement ledger — post-solve ACCOUNTING, not optimization.
#
# This file declares its own `export`s:
#   - `SettlementLedger` — the immutable ledger (transfer rows, per-actor balances, the
#     EXPLICIT named merchandising-surplus line, optional household refinement);
#   - `build_settlement_ledger` — double-entry construction from one solved run's own
#     published prices, net injections and utilities (the run-output adapters that feed
#     it live in run_inputs.jl);
#   - `ledger_residual` — the money-conservation residual (exactly 0.0 by construction).
#
# Consumes ONLY a solved run's own published prices (DADP rows — `extract_dlmp` on the
# centralized leg, `dadp`/`agr_prices` on the ADMM leg), per-actor net injections
# (`ctx.meta[:agg_net]` / `agr_dispatch`) and utilities — no re-solve, no new model.
# DISTINCT from the operational solves (models/welfare_solve.jl, admm/): this is
# post-solve money accounting — the per-actor refinement of `welfare_accounting`'s
# aggregate social = prosumer + DSO surplus split (thesis 3.46/3.47).
#
# GOLDEN POLICY: `src/pricing/` (`welfare_accounting` / `fit_baseline`) and `src/admm/`
# are consumed, NEVER modified — the whole settlement module is purely additive.
#
# MONETARY UNITS: everything here is in the framework's EXISTING welfare units — the
# SAME ¢$/kWh-consistent unit as the MEM price profile / λ₀ and the device utility
# coefficients (a second unit would scale a surplus by 10×/100×). No currency
# conversion is introduced anywhere in this module.

export SettlementLedger, build_settlement_ledger, ledger_residual

"""
    Actor

A settlement counterparty: `:wholesale` (the MEM/slack frontier), `:dso`,
`(:aggregator, bus)` for the bus-level aggregator, or `(:house, house_id)` for a
household refinement row. Internal — not exported; qualify as `TSODSO.Actor` if needed.
"""
const Actor = Union{Symbol, Tuple{Symbol, Int}}

"""
    Transfer

One double-entry ledger row `(; from, to, t, price, quantity, amount)` with the
invariant `amount == price * quantity`. Row reading: `from` DELIVERS the signed
`quantity` to `to` at the published `price` per unit, and `amount` is the signed
settlement — a positive `amount` means `to` pays `from`, a negative one means `from`
pays `to`. Every logical flow is recorded as TWO ADJACENT mirror rows (row 2 carries
the negated `quantity` and the exact negation of row 1's `amount`) so a sequential
fold over `amount` cancels each pair exactly in IEEE-754 arithmetic. Internal — not
exported; tests may qualify as `TSODSO.Transfer`.
"""
const Transfer = NamedTuple{
    (:from, :to, :t, :price, :quantity, :amount),
    Tuple{Actor, Actor, Int, Float64, Float64, Float64},
}

"""
    SettlementLedger

Immutable per-actor settlement ledger over ONE solved run (post-solve ACCOUNTING).
Fields:

  - `transfers` — every per-hour price-times-quantity settlement row, stored as
    adjacent payer/receiver mirror pairs (see the `Transfer` NamedTuple).
  - `balances` — per-actor SETTLEMENT balance: the actor's fold over the rows it
    participates in (`balances[row.from] += row.amount` per row, construction order).
    These are money-moved balances, NOT welfare: an actor's economic surplus is its own
    device utility (from the run) PLUS its settlement balance. Summing the Dict values
    reproduces [`ledger_residual`](@ref) up to Dict-iteration association; the EXACT
    identity is the transfer fold itself.
  - `merchandising_surplus` — EXPLICIT named line: the DSO's net revenue after
    per-actor settlements (nodal collections minus the wholesale payment), equal to
    `balances[:dso]` by construction and NEVER silently absorbed into another row. On a
    centralized run it reproduces `welfare_accounting(ctx).dso` within a measured,
    gate-then-golden pinned tolerance — the two are independently-associated summations
    of the same floats, so bitwise equality is NOT the contract (40-06 precedent).
  - `wholesale_payment` — `Σ_t λ₀[t]·p_import[t]`, folded sequentially with the SAME
    association as `welfare_accounting`'s `mem_cost`.
  - `households` — `nothing`, or a Vector of per-house NamedTuples
    `(; house_id, bus, aggregator, bill, surplus)` with `bill = Σ_t p·(-net_h)` and
    `surplus = U_h + Σ_t p·net_h`. Household rows REFINE aggregator rows; they are
    never the conservation source — reconciliation residuals are RECORDED, never
    thrown (the split is not the conservation source).
  - `reconciliation` — `nothing`, or a `Dict` mapping an aggregator bus to
    `(max_t abs(Σ_h net_h[t] − net_j[t]), abs(Σ_h U_h − U_j))` over its supplied
    households — recorded honesty about how well the split reproduces the aggregate,
    never a gate.
  - `metadata` — `(; T, source, buses)`: the horizon, the run-kind label
    (`:centralized` / `:admm` from the adapters; free-form otherwise) and the ascending
    aggregator buses.
"""
struct SettlementLedger
    transfers::Vector{Transfer}
    balances::Dict{Actor, Float64}
    merchandising_surplus::Float64
    wholesale_payment::Float64
    households::Union{Nothing, Vector{<:NamedTuple}}
    reconciliation::Union{Nothing, Dict{Int, Tuple{Float64, Float64}}}
    metadata::NamedTuple
end

# Internal: push the two ADJACENT mirror rows for one logical flow. `amount` is computed
# ONCE from the single `price * quantity` product and row 2 carries its exact negation,
# so the adjacent `(+a, -a)` pair cancels BITWISE in the sequential conservation fold
# (`x + (-x) == 0.0` exactly in IEEE-754 for any finite `x`).
function _push_transfer_pair!(
    transfers::Vector{Transfer},
    from::Actor,
    to::Actor,
    t::Int,
    price::Float64,
    quantity::Float64,
)
    amount = price * quantity
    push!(
        transfers,
        (from = from, to = to, t = t, price = price, quantity = quantity, amount = amount),
    )
    push!(
        transfers,
        (
            from = to,
            to = from,
            t = t,
            price = price,
            quantity = -quantity,
            amount = -amount,
        ),
    )
    return nothing
end

# Internal: fail-loud finite guard (V5 input validation) — a solver NaN/Inf reaching the
# accounting layer would silently poison every downstream settlement/equity artifact.
function _finite_or_throw(xs, name::AbstractString)
    for (k, x) in pairs(xs)
        isfinite(x) || throw(
            ArgumentError(
                "build_settlement_ledger: $name contains a non-finite value at [$k] ($x) — " *
                "a solver NaN would silently poison every downstream settlement artifact.",
            ),
        )
    end
    return nothing
end

"""
    build_settlement_ledger(prices, bus_nets, bus_utilities, p_import, λ₀, buses;
                            T, source, households = nothing) -> SettlementLedger

Primitive double-entry constructor: settle ONE solved run into a per-actor
[`SettlementLedger`](@ref). Arguments (all from the run's own published numbers — see
`settlement_input` in run_inputs.jl for the two run-kind adapters):

  - `prices` — `(length(buses) × ≥T)` matrix of PUBLISHED per-bus prices, ascending-bus
    rows (DADP rows; NEVER the negated internal ADMM multipliers);
  - `bus_nets` — `Dict{Int,Vector{Float64}}` of per-aggregator NET INJECTION
    `net = p_inject − Pdc` per hour (`net > 0` ⇒ export);
  - `bus_utilities` — `Dict{Int,Float64}` of per-aggregator device utility `U_j`;
  - `p_import` — length-`T` frontier import at the root (free-sign with export);
  - `λ₀` — length-`T` wholesale/MEM price profile;
  - `buses` — ascending, unique aggregator bus list;
  - `households` — `nothing`, or a Vector of NamedTuples
    `(; house_id, bus, net, utility)` refining each bus-level aggregator into
    households (per-house bills/surplus + recorded reconciliation residuals).

Flows, in construction order (each stored as an adjacent payer/receiver mirror pair so
the conservation fold is EXACT):

(a) aggregator `j` delivers its net injection to the DSO, per `(j, t)`:
`amount = prices[row_of_j, t] * net_j[t]` — an exporter (`net > 0`) EARNS
(the DSO pays), an importer PAYS;
(b) wholesale delivers the frontier import to the DSO, per `t`:
`amount = λ₀[t] * p_import[t]`;
(c) with households: the aggregator delivers house `h`'s net demand
(`quantity = -net_h[t]`, the bill contribution — positive when the house
imports) to the house, per `(h, t)`.

Named lines: `wholesale_payment = Σ_t λ₀[t]·p_import[t]` (same sequential association
as `welfare_accounting`'s `mem_cost`); `merchandising_surplus = balances[:dso]` — the
DSO's nodal collections minus the wholesale payment, an EXPLICIT named field.

Conservation is exact BY CONSTRUCTION and additionally GUARDED: the sequential fold
over all transfer amounts must be exactly `0.0`, else an `ErrorException` carrying the
residual magnitude is thrown (self-test guard, `welfare_accounting`'s
identity-assertion style).

Throws (never `@assert`): `ArgumentError` on any shape/length/uniqueness/finiteness
violation (`T >= 1`, ascending unique `buses`, one `prices` row per bus, every net
vector length `T`, `length(p_import) == length(λ₀) == T`, all values finite).
"""
function build_settlement_ledger(
    prices::AbstractMatrix{<:Real},
    bus_nets::AbstractDict{Int, <:Vector{<:Real}},
    bus_utilities::AbstractDict{Int, <:Real},
    p_import::AbstractVector{<:Real},
    λ₀::AbstractVector{<:Real},
    buses::AbstractVector{Int};
    T::Int,
    source::Symbol,
    households = nothing,
)
    # ---- boundary guards (fail-loud ArgumentError, welfare.jl:80-98 style) -----------
    T >= 1 || throw(
        ArgumentError(
            "build_settlement_ledger: T=$T must be at least 1 (a settlement needs at " *
            "least one hour).",
        ),
    )
    isempty(buses) && throw(
        ArgumentError(
            "build_settlement_ledger: buses is empty — a settlement needs at least one " *
            "aggregator bus.",
        ),
    )
    allunique(buses) || throw(
        ArgumentError(
            "build_settlement_ledger: buses contains duplicates ($buses) — one " *
            "aggregator per bus.",
        ),
    )
    issorted(buses) || throw(
        ArgumentError(
            "build_settlement_ledger: buses must be ASCENDING (got $buses) — the ledger " *
            "folds transfer rows in bus order.",
        ),
    )
    size(prices, 1) == length(buses) || throw(
        ArgumentError(
            "build_settlement_ledger: prices has $(size(prices, 1)) rows, expected one " *
            "row per bus (length(buses) = $(length(buses))).",
        ),
    )
    size(prices, 2) >= T || throw(
        ArgumentError(
            "build_settlement_ledger: prices has $(size(prices, 2)) columns, expected " *
            "at least T=$T.",
        ),
    )
    length(p_import) == T || throw(
        ArgumentError(
            "build_settlement_ledger: p_import has length $(length(p_import)), expected " *
            "T=$T.",
        ),
    )
    length(λ₀) == T || throw(
        ArgumentError(
            "build_settlement_ledger: λ₀ has length $(length(λ₀)), expected T=$T.",
        ),
    )
    for j in buses
        haskey(bus_nets, j) || throw(
            ArgumentError(
                "build_settlement_ledger: bus_nets is missing bus $j (keys: " *
                "$(sort!(collect(keys(bus_nets))))).",
            ),
        )
        length(bus_nets[j]) == T || throw(
            ArgumentError(
                "build_settlement_ledger: bus_nets[$j] has length " *
                "$(length(bus_nets[j])), expected T=$T.",
            ),
        )
        haskey(bus_utilities, j) || throw(
            ArgumentError(
                "build_settlement_ledger: bus_utilities is missing bus $j — one utility " *
                "per aggregator bus.",
            ),
        )
    end
    _finite_or_throw(prices, "prices")
    _finite_or_throw(λ₀, "λ₀")
    _finite_or_throw(p_import, "p_import")
    for j in buses
        _finite_or_throw(bus_nets[j], "bus_nets[$j]")
        isfinite(bus_utilities[j]) || throw(
            ArgumentError(
                "build_settlement_ledger: bus_utilities[$j] is non-finite " *
                "($(bus_utilities[j])).",
            ),
        )
    end

    houses = households
    if houses !== nothing
        isempty(houses) && throw(
            ArgumentError(
                "build_settlement_ledger: households was supplied but is empty — pass " *
                "`nothing` instead (an empty refinement is never meaningful).",
            ),
        )
        for (k, h) in enumerate(houses)
            hasproperty(h, :house_id) &&
            hasproperty(h, :bus) &&
            hasproperty(h, :net) &&
            hasproperty(h, :utility) || throw(
                ArgumentError(
                    "build_settlement_ledger: households[$k] must be a NamedTuple " *
                    "(; house_id, bus, net, utility).",
                ),
            )
            length(h.net) == T || throw(
                ArgumentError(
                    "build_settlement_ledger: households[$k].net has length " *
                    "$(length(h.net)), expected T=$T.",
                ),
            )
            Int(h.bus) in buses || throw(
                ArgumentError(
                    "build_settlement_ledger: households[$k].bus = $(h.bus) is not one " *
                    "of the aggregator buses $buses.",
                ),
            )
            _finite_or_throw(h.net, "households[$k].net")
            isfinite(h.utility) || throw(
                ArgumentError(
                    "build_settlement_ledger: households[$k].utility is non-finite " *
                    "($(h.utility)).",
                ),
            )
        end
        ids = [Int(h.house_id) for h in houses]
        allunique(ids) || throw(
            ArgumentError(
                "build_settlement_ledger: duplicate house_id among households ($ids).",
            ),
        )
    end

    # ---- flows, in construction order: (a) aggregator→DSO, (b) wholesale→DSO, -------
    # ---- (c) aggregator→house (each an adjacent mirror pair) ------------------------
    transfers = Transfer[]
    sizehint!(
        transfers,
        2 * (length(buses) * T + T + (houses === nothing ? 0 : length(houses) * T)),
    )
    row_of = Dict{Int, Int}(b => i for (i, b) in enumerate(buses))

    # (a) aggregator j delivers its net injection to the DSO, per (j, t): an exporter
    # (net > 0) EARNS price·net (the DSO pays), an importer PAYS.
    for (i, j) in enumerate(buses)
        for t in 1:T
            _push_transfer_pair!(
                transfers,
                (:aggregator, j),
                :dso,
                t,
                Float64(prices[i, t]),
                Float64(bus_nets[j][t]),
            )
        end
    end

    # (b) wholesale delivers the frontier import to the DSO, per t.
    for t in 1:T
        _push_transfer_pair!(
            transfers,
            :wholesale,
            :dso,
            t,
            Float64(λ₀[t]),
            Float64(p_import[t]),
        )
    end

    # (c) household refinement: the aggregator delivers the house's net demand
    # (quantity = -net_h, the bill contribution — positive when the house imports).
    if houses !== nothing
        for h in houses
            j = Int(h.bus)
            i = row_of[j]
            for t in 1:T
                _push_transfer_pair!(
                    transfers,
                    (:aggregator, j),
                    (:house, Int(h.house_id)),
                    t,
                    Float64(prices[i, t]),
                    -Float64(h.net[t]),
                )
            end
        end
    end

    # ---- fold: per-actor balances + the EXACT conservation guard ---------------------
    balances = Dict{Actor, Float64}()
    residual = 0.0
    for tr in transfers
        amount = tr.amount
        balances[tr.from] = get(balances, tr.from, 0.0) + amount
        residual += amount
    end
    residual == 0.0 || throw(
        ErrorException(
            "build_settlement_ledger: conservation VIOLATED — the sequential fold over " *
            "transfer amounts is $(residual), not exactly 0.0. Double-entry is exact by " *
            "construction (each logical flow is an adjacent (+a, -a) mirror pair), so a " *
            "non-zero residual means a transfer row was dropped, duplicated or mutated.",
        ),
    )

    # ---- named lines -----------------------------------------------------------------
    wholesale_payment = sum(Float64(λ₀[t]) * Float64(p_import[t]) for t in 1:T)
    merchandising_surplus = balances[:dso]

    # ---- household refinement rows + RECORDED (never thrown) reconciliation ----------
    household_rows = nothing
    reconciliation = nothing
    if houses !== nothing
        household_rows = [
            begin
                i = row_of[Int(h.bus)]
                bill = 0.0
                surplus = Float64(h.utility)
                for t in 1:T
                    p = Float64(prices[i, t])
                    bill += p * (-Float64(h.net[t]))
                    surplus += p * Float64(h.net[t])
                end
                (
                    house_id = Int(h.house_id),
                    bus = Int(h.bus),
                    aggregator = Int(h.bus),
                    bill = bill,
                    surplus = surplus,
                )
            end for h in houses
        ]
        reconciliation = Dict{Int, Tuple{Float64, Float64}}()
        for j in buses
            members = filter(h -> Int(h.bus) == j, houses)
            isempty(members) && continue
            net_gap = 0.0
            for t in 1:T
                s = 0.0
                for h in members
                    s += Float64(h.net[t])
                end
                net_gap = max(net_gap, abs(s - Float64(bus_nets[j][t])))
            end
            u_sum = 0.0
            for h in members
                u_sum += Float64(h.utility)
            end
            reconciliation[j] = (net_gap, abs(u_sum - Float64(bus_utilities[j])))
        end
    end

    return SettlementLedger(
        transfers,
        balances,
        merchandising_surplus,
        wholesale_payment,
        household_rows,
        reconciliation,
        (; T = T, source = source, buses = collect(buses)),
    )
end

"""
    ledger_residual(ledger) -> Float64

Money-conservation residual: the sequential (left) fold of every transfer row's
`amount`, in stored construction order. EXACTLY `0.0` for any [`SettlementLedger`](@ref)
built by [`build_settlement_ledger`](@ref) — the IEEE adjacent-pair argument: each
logical flow is stored as two ADJACENT mirror rows carrying `+a` then `-a` where
`a = fl(price·quantity)` is the single rounded product both rows share, and
`x + (-x)` cancels exactly in IEEE-754 arithmetic for any finite `x`, so each pair
leaves the running partial sum bit-for-bit unchanged. The constructor additionally
GUARDS this identity (an `ErrorException` fires on any non-zero residual), so a dropped,
duplicated or mutated transfer row can never pass silently.
"""
function ledger_residual(ledger::SettlementLedger)
    residual = 0.0
    for tr in ledger.transfers
        residual += tr.amount
    end
    return residual
end
