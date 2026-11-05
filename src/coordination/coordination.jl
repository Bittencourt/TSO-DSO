# src/coordination/coordination.jl
#
# SEAM: the coordination-scheme hierarchy. A coordination scheme decides HOW the DSO steers
# aggregator dispatch on a shared feeder. Price-based coordination (the dynamic distribution
# price, DADP) is the existing scheme: prices emerge as the duals of the nodal balance and every
# aggregator responds as a price taker. A flexibility market is the alternative: aggregators
# first schedule against a retail tariff, then the DSO buys up and down deviations from them
# through explicit bids to relieve the network.
#
# WHY THIS FILE EXISTS: the flexibility market is a coordination alternative, not a settlement
# variant, so its configuration lives in its own small type hierarchy rather than as extra
# keywords on the tariff legs. These types are pure configuration (validated on construction);
# they carry no solver state and never touch the default comparison path, which is unchanged
# unless a `FlexMarket` is passed explicitly (opt-in).

"""
    AbstractCoordination

Supertype of DSO coordination schemes (see [`PriceBased`](@ref), [`FlexMarket`](@ref)).
"""
abstract type AbstractCoordination end

"""
    PriceBased()

The existing price-based coordination: the day-ahead dynamic distribution price (DADP), read as
the dual of the nodal active-power balance of the convex welfare problem, with every aggregator
responding as a price taker. A marker type; the default comparison legs use it implicitly.
"""
struct PriceBased <: AbstractCoordination end

const _FLEX_BASELINE_TARIFFS = (:flat, :tou)
const _FLEX_PAYMENT_RULES = (:uniform, :pay_as_bid)

"""
    FlexMarket(; baseline_tariff = :flat, payment_rule = :uniform, n_blocks = 4,
                 baseline_inflation = 0.0)

A two-stage DSO flexibility market, the alternative to [`PriceBased`](@ref) coordination.
Keywords (each invalid value throws `ArgumentError`):

  - `baseline_tariff`: `:flat` or `:tou`, the revenue-neutral retail tariff of stage 1.
  - `payment_rule`: `:uniform` or `:pay_as_bid`.
  - `n_blocks`: number of up blocks and of down blocks per aggregator per hour (an integer, at
    least 1).
  - `baseline_inflation`: β, a finite non-negative real stored as `Float64` (0 is truthful).

**Stage 1, baseline.** Each aggregator solves a price-taker dispatch (the
[`price_taker_dispatch`](@ref) seam) against the revenue-neutral flat or TOU tariff, derived
exactly as for the existing flat and TOU legs. That schedule is the baseline `b`.

**Stage 2, DSO redispatch.** The DSO clears the activated up and down quantities per aggregator,
hour and block on the same feeder, with the same power-flow model (the SOCP branch flow) and the
same exactness gate as the DADP run. It minimises the cost of the accepted bids plus the
wholesale import cost `λ₀ᵀ p_import`. The network constraints are the existing power-flow
contribution and balance seam; there is no new network formulation. If the offered flexibility
cannot restore feasibility, the leg is reported as a status row, never a crash.

**Bids.** Bids are divisible, piecewise-linear and hour-separable: `n_blocks` up and `n_blocks`
down blocks per aggregator per hour, each a quantity and a price with a non-decreasing marginal
cost. Each aggregator generates them by probing its own model (single-hour perturbation
re-solves around the baseline, other hours held at the baseline). Bids are truthful: the price
is the aggregator's own utility loss.

**Delivery.** Hour-separable bids drop intertemporal coupling (storage state of charge,
deferrable energy), so each aggregator re-solves on its own devices to track its activated
target. The delivered dispatch is what is settled, welfare-evaluated and AC-checked, and the
shortfall between delivered and target is reported, never hidden.

**Payment rule.** Under `:uniform`, activated flexibility at a bus and hour is paid the
stage-2 clearing price, the dual of the stage-2 nodal balance in the existing `dual(balance)`
sign convention. Under `:pay_as_bid`, each activated block is paid its own bid price times its
quantity. The dispatch is the same under both rules; only the money differs.

**Baseline inflation.** β inflates the reported consumption baseline in congested hours, as a
baseline-gaming sensitivity. It changes money only: the dispatch, the welfare and the AC
feasibility are those of the truthful clear, and the resulting overpayment is reported.
"""
struct FlexMarket <: AbstractCoordination
    baseline_tariff::Symbol
    payment_rule::Symbol
    n_blocks::Int
    baseline_inflation::Float64
    function FlexMarket(
        baseline_tariff::Symbol,
        payment_rule::Symbol,
        n_blocks::Integer,
        baseline_inflation::Real,
    )
        baseline_tariff in _FLEX_BASELINE_TARIFFS || throw(
            ArgumentError(
                "FlexMarket: baseline_tariff must be :flat or :tou, got $(repr(baseline_tariff))",
            ),
        )
        payment_rule in _FLEX_PAYMENT_RULES || throw(
            ArgumentError(
                "FlexMarket: payment_rule must be :uniform or :pay_as_bid, got $(repr(payment_rule))",
            ),
        )
        n_blocks >= 1 ||
            throw(ArgumentError("FlexMarket: n_blocks must be at least 1, got $(n_blocks)"))
        isfinite(baseline_inflation) || throw(
            ArgumentError(
                "FlexMarket: baseline_inflation must be finite, got $(baseline_inflation)",
            ),
        )
        baseline_inflation >= 0 || throw(
            ArgumentError(
                "FlexMarket: baseline_inflation must be non-negative, got $(baseline_inflation)",
            ),
        )
        # `-0.0` is stored as `0.0` so that equal β values give equal row names.
        β = Float64(baseline_inflation) + 0.0
        return new(baseline_tariff, payment_rule, Int(n_blocks), β)
    end
end

function FlexMarket(;
    baseline_tariff = :flat,
    payment_rule = :uniform,
    n_blocks = 4,
    baseline_inflation = 0.0,
)
    baseline_tariff isa Symbol || throw(
        ArgumentError(
            "FlexMarket: baseline_tariff must be a Symbol (:flat or :tou), got $(repr(baseline_tariff))",
        ),
    )
    payment_rule isa Symbol || throw(
        ArgumentError(
            "FlexMarket: payment_rule must be a Symbol (:uniform or :pay_as_bid), got $(repr(payment_rule))",
        ),
    )
    (n_blocks isa Integer && !(n_blocks isa Bool)) || throw(
        ArgumentError("FlexMarket: n_blocks must be an integer, got $(repr(n_blocks))"),
    )
    (baseline_inflation isa Real && !(baseline_inflation isa Bool)) || throw(
        ArgumentError(
            "FlexMarket: baseline_inflation must be a real number, got $(repr(baseline_inflation))",
        ),
    )
    return FlexMarket(baseline_tariff, payment_rule, n_blocks, baseline_inflation)
end

"""
    coordination_label(c::AbstractCoordination) -> String

Short label of a coordination scheme: `"price_based"` for [`PriceBased`](@ref), `"flex_market"`
for [`FlexMarket`](@ref). Internal; qualify as `TSODSO.coordination_label`.
"""
coordination_label(::PriceBased) = "price_based"
coordination_label(::FlexMarket) = "flex_market"

"""
    _flex_row_name(fm::FlexMarket) -> String

The comparison-table row name (the `tariff` column) of a flexibility-market leg. It is
`"flex_uniform"` or `"flex_pab"` by payment rule, then `"_tou"` when the baseline tariff is TOU,
`"_k<n>"` when `n_blocks` differs from the default 4, and `"_beta<β>"` (shortest round-trip
`string` of the Float64) when β is non-zero. For example `flex_uniform`, `flex_pab`,
`flex_uniform_tou`, `flex_uniform_k8`, `flex_uniform_beta0.05`. Every suffix is either present
or absent at a fixed position and the Float64 string is round-trip exact, so the name is
injective over the four fields (it is a CSV upsert key, where a collision would silently
overwrite a row). Internal.
"""
function _flex_row_name(fm::FlexMarket)
    name = "flex_" * (fm.payment_rule === :uniform ? "uniform" : "pab")
    fm.baseline_tariff === :tou && (name *= "_tou")
    fm.n_blocks != 4 && (name *= "_k$(fm.n_blocks)")
    fm.baseline_inflation != 0 && (name *= "_beta$(string(fm.baseline_inflation))")
    return name
end

export AbstractCoordination, PriceBased, FlexMarket
