# src/settlement/comparison.jl
#
# SEAM: the tariff-comparison RUNNER — pure ASSEMBLY of the validated settlement layers
# (SettlementLedger + run adapters, tariff price construction, price-taker counterfactual,
# AC feasibility status, equity metrics + rebound) over ONE solved DADP run. This file
# introduces NO new formulation and NO new solve: every leg consumes an existing, tested
# seam. Direct solver calls (`solve_welfare` / `solve_admm` / `fit_baseline`) — NEVER the
# `run_scenario` seam (ScenarioResult normalizes away the ctx / additive keys the ledger
# needs; the experiments `run()` materialization sequence is the seed-discipline model,
# and the CALLER owns seeding — this file draws nothing random).
#
# Engines: `engine = :centralized` → `solve_welfare`; `engine = :admm` → `solve_admm`
# (the thesis-relevant published-price path — `dadp == λ`; the ADMM result's own
# `:converged` guard makes a non-converged / budget-exceeded stop fail LOUDLY here via
# `settlement_input`, never silently). Both legs solve with `allow_export = true` (priced
# export is the SOC-exactness enabler in the reverse-flow regime and the ground
# fixtures' calibration requirement).
#
# HONESTY POLICY: every leg is recorded as a row, never dropped. A solver-outcome failure
# of the `:fit` leg (`SolveFailedError` / `CertificateError` / `ConvergenceError`,
# including `fit_baseline`'s nested SITE-3 cross-check, or its `on_inexact = :report`
# NaN-certified early return) becomes an honest status row with the non-certified values
# `missing` — never a crash, never a re-tune. Misuse errors (shape/finiteness guards)
# propagate. The AC feasibility of every leg's dispatch is a RECORDED
# [`FeasibilityStatus`](@ref), never a gate.
#
# SETTLEMENT CONVENTIONS (documented, uniform across legs):
#   - `:dadp` settles the run's OWN numbers: bus nets/utilities from the packed
#     `SettlementInput`, the run's own solved `p_import` (losses included), and the
#     run's published price rows.
#   - `:flat` / `:tou` are revenue-neutral DERIVATIONS (`flat_prices` / `tou_prices`)
#     settled at the price-taker counterfactual dispatch. The device-level QP carries no
#     network losses, so the frontier exchange is the LOSSLESS balance
#     `p_import = −Σ_j net_j` — a documented convention (the DADP leg keeps the run's
#     own loss-inclusive import).
#   - `:fit` settles the FIT price triple from `fit_baseline`'s own `fit_flows` rows:
#     the bill is the GRID payment `Σ_t (λ_import·imp − λ_export·exp)`; the notional
#     `λ_self` self-consumption credit never crosses the meter (it is valued inside the
#     device utility). DSO collections = the same grid payments; wholesale = `λ₀` times
#     the aggregate import (lossless, as above); merchandising surplus = collections −
#     wholesale. With these definitions the fit leg's actor totals conserve EXACTLY.
#   - A1 ASYMMETRY (documented, never hidden): `:dadp`/`:flat`/`:tou` household equity
#     uses per-house price-taker dispatches (ALL devices, batteries included); the
#     `:fit` leg is BATTERYLESS by `fit_baseline`'s design (Assumption A4) and exposes
#     no per-aggregator device utility, so its equity reports at BUS granularity with
#     the surplus-side columns `missing` and no house-granularity breakout rows. The
#     `bills_granularity` column marks which reading every row carries. The fit leg is
#     NEVER back-filled with a different dispatch.
#   - `fairness_total` is the locked fairness condition carried through the runner: the
#     total settled at the leg's prices over the DADP run's OWN quantities. For
#     `:dadp` it is the leg's own settlement (same prices, same quantities); for
#     `:flat`/`:tou` it reproduces the DADP total identically (the 41-03 revenue-
#     neutrality algebra). `total_payments` is the leg's settlement at its OWN dispatch.
#   - Rebound: flat and tou aggregate net-load (grid consumption = −Σ net injection)
#     versus the DADP leg's (the baseline). The dadp row IS the baseline — its rebound
#     amount is exactly `0.0` and its ratio `NaN` by construction; the fit leg carries
#     `missing` (the plan pins rebound to the flat/tou vs dadp pair).
#
# FLEX-MARKET LEGS (opt-in, `flex_market` keyword; the default path never enters them):
#   - Each `FlexMarket` row settles the DELIVERED dispatch at its baseline tariff (the flat or
#     TOU derivation of the same DADP run) and books the flexibility payments on the
#     activated deviation as conserving ledger rows, so the row's actor totals come from one
#     ledger with residual exactly 0.0.
#   - The tariff is also paid on metered energy, so an up-activated unit earns the tariff it
#     no longer pays plus the clearing price; `tariff_on_activation` reports that overlap and
#     never changes the dispatch.
#   - `welfare` is the delivered dispatch's utilities minus λ₀ on the LOSSLESS import (the
#     flat/tou convention). The dadp row keeps its loss-inclusive import, so the two are not
#     like for like; `welfare_dadp_lossless` and `welfare_gap_vs_dadp_lossless` put the DADP
#     dispatch on the same lossless footing for the comparison.
#   - The redispatch holds each bus's reactive draw at the inelastic `−Pdc·tanφ` (the
#     flexibility product is active power only).
#   - A redispatch that fails is a status row (`infeasible_redispatch`, `inexact_redispatch`
#     or `error:<Type>`) with the same field set and the uncomputed values `missing`; it adds
#     no bill or rebound rows. Flex rows are appended after the four tariff rows through a
#     separate table and `vcat(...; cols = :union)`, so the base rows and columns are never
#     touched.
#
# GOLDEN POLICY: `fit_baseline` is consumed via its documented `optimizer` /
# `on_inexact` kwargs ONLY (the `fit_optimizer` passthrough is the documented tightening
# seam — Pitfall 2) — never modified. `src/pricing/`, `src/admm/`, `src/models/` are
# untouched. NO file IO anywhere in this file: the runner RETURNS DataFrames; the
# measurement script (`scripts/tariff_comparison.jl`) owns persistence.

export compare_tariffs

using DataFrames: DataFrame
using LinearAlgebra: BLAS

# Internal: NamedTuple rows → DataFrame with per-column type promotion (`Union{T,Missing}`
# wherever a missing appears). Small assembly helper for the runner's four returned
# tables; the row NamedTuples across legs share ONE field set per table (built by
# `_summary_row` / the bill and breakout row builders) and differ only in which fields
# are `missing`.
function _rows_to_dataframe(rows::Vector{<:NamedTuple})
    isempty(rows) && return DataFrame()
    ks = propertynames(first(rows))
    cols = AbstractVector[]
    for k in ks
        vals = Any[getproperty(r, k) for r in rows]
        types = unique(map(typeof, vals))
        if length(types) > 1
            T = reduce((a, b) -> promote_type(a, b), types)
            vals = convert(Vector{T}, vals)
        end
        push!(cols, vals)
    end
    return DataFrame(cols, collect(Symbol, ks))
end

# Internal: the per-leg equity metric column set on ONE value vector (`nothing` ⇒ the
# honestly-missing set, e.g. the fit leg's surplus side). Same documented conventions as
# the underlying metrics: gini over ALL values; theil/atkinson positive-support subset
# with the excluded count RETURNED; palma group-total ratio.
function _equity_columns(values::Union{Nothing, Vector{Float64}})
    if values === nothing
        return (
            gini = missing,
            theil = missing,
            theil_n_excluded = missing,
            atkinson = missing,
            atkinson_n_excluded = missing,
            palma = missing,
        )
    end
    t = theil(values)
    a = atkinson(values)
    return (
        gini = gini(values),
        theil = t.theil,
        theil_n_excluded = t.n_excluded,
        atkinson = a.atkinson,
        atkinson_n_excluded = a.n_excluded,
        palma = palma(values),
    )
end

# Internal: one summary row with the FULL column set (every leg emits the same field
# list; unavailable values are `missing` — a dropped COLUMN would be a dropped leg by
# another name).
function _summary_row(;
    tariff::String,
    engine::String,
    t_horizon::Int,
    status::String = "ok",
    notes::String = "",
    welfare = missing,
    total_payments = missing,
    fairness_total = missing,
    merchandising_surplus = missing,
    dso_total = missing,
    aggregators_total = missing,
    wholesale_total = missing,
    feasibility_status::String = "not_run",
    n_thermal_violations = missing,
    n_voltage_violations = missing,
    max_overload_ratio = missing,
    batt_ok::Int = 0,
    batt_refused::Int = 0,
    batt_not_checked::Int = 0,
    eq_bills = _equity_columns(nothing),
    eq_surplus = _equity_columns(nothing),
    rebound_amount = missing,
    rebound_ratio = missing,
    bills_granularity::String = "bus",
)
    return (
        tariff = tariff,
        engine = engine,
        status = status,
        notes = notes,
        welfare = welfare,
        total_payments = total_payments,
        fairness_total = fairness_total,
        merchandising_surplus = merchandising_surplus,
        dso_total = dso_total,
        aggregators_total = aggregators_total,
        wholesale_total = wholesale_total,
        feasibility_status = feasibility_status,
        n_thermal_violations = n_thermal_violations,
        n_voltage_violations = n_voltage_violations,
        max_overload_ratio = max_overload_ratio,
        batt_ok = batt_ok,
        batt_refused = batt_refused,
        batt_not_checked = batt_not_checked,
        gini_bills = eq_bills.gini,
        theil_bills = eq_bills.theil,
        theil_n_excluded_bills = eq_bills.theil_n_excluded,
        atkinson_bills = eq_bills.atkinson,
        atkinson_n_excluded_bills = eq_bills.atkinson_n_excluded,
        palma_bills = eq_bills.palma,
        gini_surplus = eq_surplus.gini,
        theil_surplus = eq_surplus.theil,
        theil_n_excluded_surplus = eq_surplus.theil_n_excluded,
        atkinson_surplus = eq_surplus.atkinson,
        atkinson_n_excluded_surplus = eq_surplus.atkinson_n_excluded,
        palma_surplus = eq_surplus.palma,
        rebound_amount = rebound_amount,
        rebound_ratio = rebound_ratio,
        bills_granularity = bills_granularity,
        julia_version = string(VERSION),
        threads = Threads.nthreads(),
        blas_threads = BLAS.get_num_threads(),
        t_horizon = t_horizon,
    )
end

# Internal: the `flex_market` keyword normalised to a `Vector{FlexMarket}` (`nothing` stays
# `nothing`, the default path). Every refusal is an `ArgumentError` raised before any solve.
function _flex_market_list(flex_market)
    flex_market === nothing && return nothing
    fms = if flex_market isa FlexMarket
        FlexMarket[flex_market]
    elseif flex_market isa AbstractVector
        for (k, x) in enumerate(flex_market)
            x isa FlexMarket || throw(
                ArgumentError(
                    "compare_tariffs: flex_market[$k] is a $(typeof(x)), not a FlexMarket.",
                ),
            )
        end
        FlexMarket[x for x in flex_market]
    else
        throw(
            ArgumentError(
                "compare_tariffs: flex_market must be nothing, a FlexMarket or a vector of " *
                "them; got a $(typeof(flex_market)).",
            ),
        )
    end
    isempty(fms) && throw(
        ArgumentError(
            "compare_tariffs: flex_market is an empty vector; pass nothing for the default " *
            "four-leg comparison.",
        ),
    )
    row_names = String[_flex_row_name(fm) for fm in fms]
    length(unique(row_names)) == length(row_names) || throw(
        ArgumentError(
            "compare_tariffs: flex_market has duplicate row names $(row_names); every " *
            "FlexMarket must differ in payment rule, baseline tariff, n_blocks or β.",
        ),
    )
    return fms
end

"""
    compare_tariffs(feeder::AbstractFeeder, pf::AbstractPowerFlow,
                    aggs::AbstractVector{<:Aggregator};
                    T::Int, λ₀, engine::Symbol = :centralized, ρ::Real = ADMM().ρ,
                    τ_batt::Real = 1e-3, bins::Vector{Vector{Int}} = default_tou_bins(T),
                    houses = nothing, map_rows = nothing, fit_optimizer = nothing,
                    time_limit_s::Union{Nothing, Real} = nothing, agr_optimizer = nothing,
                    flex_market = nothing, welfare_optimizer = nothing) ->
        (; summary, household_bills, equity_breakouts, rebound)

The SETL-02/05 comparison runner: settle ONE solved DADP run into a per-actor ledger and
rebuild dispatch per tariff (`:dadp` / `:flat` / `:tou` / `:fit`) on the SAME feeder and
population, returning four DataFrames — the Phase-35/39/40 measurement-artifact shape
(the script `scripts/tariff_comparison.jl` persists them; this function does NO file IO).

  - `summary` — one row per tariff, in the fixed leg order `["dadp", "flat", "tou", "fit"]`, never dropped: welfare, `total_payments` (the leg's own settlement),
    `fairness_total` (the same total at the DADP quantities — the locked
    revenue-neutrality echo), merchandising surplus and per-actor totals, AC
    `feasibility_status` + violation counts + worst overload ratio, battery-certificate
    counts (:ok/:refused/:not_checked — covering the price-taker dispatches at the row's
    `bills_granularity`: the per-house re-solves when houses are attributed, the
    aggregator-level dispatches otherwise; the `:dadp` bus-level dispatch is the run
    itself, so its bus-granularity counts are all :not_checked; the fit leg is
    batteryless A4, always :not_checked), gini/theil/atkinson/palma on bills and on
    surplus (with theil/atkinson exclusion counts), `rebound_amount`/`rebound_ratio`
    (flat/tou vs the dadp baseline), `bills_granularity` (`"house"`/`"bus"` — the A1
    asymmetry marker), `status`/`notes` (honest outcomes) and provenance
    (`julia_version`, `threads`, `blas_threads`, `t_horizon`).
  - `household_bills` — per-house rows for `:dadp`/`:flat`/`:tou` when `houses` is
    supplied (granularity `"house"`, with `pv_group`/`load_tercile` from `map_rows`),
    otherwise per-bus rows; the `:fit` leg is always bus-granularity with `surplus`
    missing (A1).
  - `equity_breakouts` — per-group metric rows (`grouping ∈ {"pv_group", "bus", "load_tercile"}`, `metric_kind ∈ {"bills", "surplus"}`) for the three
    house-granularity legs when `houses` + `map_rows` are supplied; the batteryless fit
    leg emits none (A1).
  - `rebound` — per-hour detail rows for the flat/tou legs: baseline/counterfactual net
    load, delta, and the reduction/increase classification.

Engines: `:centralized` runs `solve_welfare`; `:admm` runs `solve_admm` (`ρ` REQUIRED
kwarg sourced from `ADMM().ρ` — the locked no-re-tuning default) and INHERITS the loud
non-`:converged` refusal of `settlement_input` (a budget stop carries no certified
price). `time_limit_s` forwards to `solve_admm` when `engine = :admm`.

`houses` are single-house `Aggregator`s rebuilt from the population's own construction
primitives; `map_rows` are the matching `case_a_household_map`-shaped rows (1:1 with
`houses` — the guard is loud). Passing either without the other, a length mismatch, a
missing `:pv_group` field, a house bus outside the aggregator buses, more than one
aggregator per bus, an unknown engine, or a `λ₀` length ≠ `T` throws `ArgumentError`
BEFORE any solving (T-41-19).

`fit_optimizer` is the documented `fit_baseline` tightening seam (Pitfall 2): a
differently-CONDITIONED optimizer factory — never a gate change; `fit_baseline` runs
with `on_inexact = :report`, so a non-certified SITE-2 AC outcome is an honest
`fit_inexact` status row, and a `SolveFailedError`/`CertificateError`/`ConvergenceError`
from any fit-internal solve becomes a recorded `error:<Type>` row.

`agr_optimizer` is the documented `solve_admm` AGR precision seam (the pre-registered
ladder's mechanism): a caller-supplied AGR-OPT optimizer factory forwarded verbatim to
the `engine = :admm` solve. The default `nothing` resolves to the plain
`select_optimizer(QP())` factory, byte-identical. The exactness gate, battery τ, and ρ
are not exposed here and remain untouched.

`welfare_optimizer` is a conditioning seam for the centralized SOCP solves: a
caller-supplied optimizer factory forwarded to the DADP solve under
`engine = :centralized` and to every flexibility-market redispatch. The default `nothing`
makes exactly the default calls. With `engine = :admm` a non-`nothing` `welfare_optimizer`
throws `ArgumentError` before any solve, because `solve_admm` takes no optimizer (use
`agr_optimizer` for ADMM conditioning). A flexibility market is still allowed under
`:admm`; its redispatch then runs at the default SOCP optimizer. To condition that solve
after an ADMM run, call [`clear_flex_market`](@ref) directly with its `optimizer`.

`flex_market` (default `nothing`, the four-leg table above) takes one
[`FlexMarket`](@ref) or a vector of them. Each one appends a row named by its payment
rule and options (`flex_uniform`, `flex_pab`, `flex_uniform_beta0.05`, ...) after the
`fit` row, with the 37 base columns plus the additive flexibility columns of
`FLEX_EXTRA_COLUMNS`. The physics of a clear (baseline, bids, redispatch, delivery and the
AC check) runs once per pair of baseline tariff and block count, and the payment rule and β
change money only. `household_bills` gains bus-granularity rows per flex row and
`rebound` gains per-hour rows, both with an additive `delivery_shortfall` column (summed
over hours per bus, and over buses per hour); the column is `missing` on the base rows.
`equity_breakouts` is unchanged. A redispatch that fails becomes a status row
(`infeasible_redispatch`, `inexact_redispatch` or `error:<Type>`) with no bill or rebound
rows; so does a failure of the congested-hour price split after the redispatch
(`error:dlmp_split`). With `flex_market`, these throw `ArgumentError` before any solve:
`houses` (household attribution of flexibility payments is not modelled), an empty vector,
an entry that is not a `FlexMarket`, two entries with the same row name, a power-flow
formulation other than `ConvexBranchFlow` (the congested-hour split reads its constraint
duals), a `λ₀` with a non-finite or non-positive entry (it normalises the congestion
score), and any aggregator holding a `FixedCapacitor` (its constant reactive injection has
no stage-2 representation).
"""
function compare_tariffs(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggs::AbstractVector{<:Aggregator};
    T::Int,
    λ₀,
    engine::Symbol = :centralized,
    ρ::Real = ADMM().ρ,
    τ_batt::Real = 1e-3,
    bins::Vector{Vector{Int}} = default_tou_bins(T),
    houses = nothing,
    map_rows = nothing,
    fit_optimizer = nothing,
    time_limit_s::Union{Nothing, Real} = nothing,
    agr_optimizer = nothing,
    flex_market = nothing,
    welfare_optimizer = nothing,
)
    # ---- boundary guards (T-41-19) — BEFORE any solving ---------------------------------
    engine in (:centralized, :admm) || throw(
        ArgumentError(
            "compare_tariffs: unknown engine $(repr(engine)) — expected :centralized or :admm.",
        ),
    )
    isempty(aggs) && throw(
        ArgumentError(
            "compare_tariffs: empty aggregator vector — a comparison needs at least one aggregator.",
        ),
    )
    length(λ₀) == T ||
        throw(ArgumentError("compare_tariffs: λ₀ has length $(length(λ₀)), expected T=$T."))
    length(unique(a.bus for a in aggs)) == length(aggs) || throw(
        ArgumentError(
            "compare_tariffs: aggregators share buses — the ledger requires exactly one aggregator per bus.",
        ),
    )
    if houses === nothing
        map_rows === nothing || throw(
            ArgumentError(
                "compare_tariffs: map_rows supplied without houses — the map refines nothing; pass houses too (or neither).",
            ),
        )
    else
        map_rows === nothing && throw(
            ArgumentError(
                "compare_tariffs: houses supplied without map_rows — household attribution needs the matching map (T-41-19).",
            ),
        )
        length(map_rows) == length(houses) || throw(
            ArgumentError(
                "compare_tariffs: $(length(houses)) houses but $(length(map_rows)) map rows — they must align 1:1.",
            ),
        )
        for (k, r) in enumerate(map_rows)
            hasproperty(r, :pv_group) || throw(
                ArgumentError(
                    "compare_tariffs: map_rows[$k] has no :pv_group field — the breakouts group by it.",
                ),
            )
        end
    end
    (engine === :admm && welfare_optimizer !== nothing) && throw(
        ArgumentError(
            "compare_tariffs: welfare_optimizer conditions the centralized SOCP solves (the " *
            "DADP solve under engine = :centralized and each flexibility-market redispatch); " *
            "solve_admm takes no optimizer (use agr_optimizer for ADMM conditioning).",
        ),
    )
    flex_markets = _flex_market_list(flex_market)
    if flex_markets !== nothing
        houses === nothing || throw(
            ArgumentError(
                "compare_tariffs: houses cannot be combined with flex_market — household " *
                "attribution of flexibility payments is not modelled; pass one or the other.",
            ),
        )
        pf isa ConvexBranchFlow || throw(
            ArgumentError(
                "compare_tariffs: flex_market needs ConvexBranchFlow (the congested-hour " *
                "split of the redispatch prices reads its cone, voltage-drop, exactness-copy " *
                "and thermal-limit duals); got $(typeof(pf)).",
            ),
        )
        all(t -> isfinite(λ₀[t]) && λ₀[t] > 0, 1:T) || throw(
            ArgumentError(
                "compare_tariffs: with flex_market, λ₀ must be finite and positive in every " *
                "hour (it normalises the congestion score of the clearing prices); got " *
                "$(collect(λ₀)).",
            ),
        )
        for (k, a) in enumerate(aggs)
            any(d -> d isa FixedCapacitor, a.devices) && throw(
                ArgumentError(
                    "compare_tariffs: aggs[$k] (bus $(a.bus)) holds a FixedCapacitor; with " *
                    "flex_market its constant reactive injection has no stage-2 representation " *
                    "(the flexibility product is active power only).",
                ),
            )
        end
    end
    λ₀vec = Float64[float(λ₀[t]) for t in 1:T]

    # ---- the ONE DADP run ----------------------------------------------------------------
    local input
    if engine === :centralized
        if welfare_optimizer === nothing
            ctx, _obj, _dadp =
                solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
        else
            ctx, _obj, _dadp = solve_welfare(
                feeder,
                pf,
                aggs;
                T = T,
                λ₀ = λ₀,
                allow_export = true,
                optimizer = welfare_optimizer,
            )
        end
        input = settlement_input(ctx; T = T, λ₀ = λ₀)
    else
        # Both conditioning kwargs forward UNCONDITIONALLY: each defaults to `nothing` and
        # `solve_admm` treats `nothing` for each as its own default, so this single call is
        # byte-identical to the pre-seam if/else shapes (golden policy; the knife-edge
        # canary is never re-pinned).
        admm = solve_admm(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            ρ = ρ,
            allow_export = true,
            agr_optimizer = agr_optimizer,
            time_limit_s = time_limit_s,
        )
        input = settlement_input(admm; λ₀ = λ₀)
    end

    nb = length(input.buses)
    row_of = Dict(b => i for (i, b) in enumerate(input.buses))
    dadp_nets = [input.bus_nets[b] for b in input.buses]
    dadp_utils = [input.bus_utilities[b] for b in input.buses]
    engine_str = string(engine)

    if houses !== nothing
        for (k, h) in enumerate(houses)
            Int(h.bus) in input.buses || throw(
                ArgumentError(
                    "compare_tariffs: houses[$k].bus = $(h.bus) is not one of the aggregator buses $(input.buses).",
                ),
            )
        end
    end

    # Breakout groupings (built once): PV ownership and bus straight from the map rows;
    # load terciles from the per-house BASELINE consumption total (Σ Pdc over the horizon).
    tercile_labels = nothing
    groupings = nothing
    if houses !== nothing
        tercile_labels =
            load_terciles(Float64[sum(houses[k].Pdc[1:T]) for k in eachindex(houses)])
        groupings = [
            ("pv_group", Symbol[r.pv_group for r in map_rows]),
            ("bus", Int[Int(houses[k].bus) for k in eachindex(houses)]),
            ("load_tercile", tercile_labels),
        ]
    end
    summary_rows = Vector{NamedTuple}()
    bill_rows = Vector{NamedTuple}()
    breakout_rows = Vector{NamedTuple}()
    rebound_rows = Vector{NamedTuple}()

    # Shared per-house re-solve at a leg's price matrix (the house at bus b sees the bus
    # row): per-household attribution for EVERY house-granularity leg, certificates included.
    house_solve = function (P)
        return [
            price_taker_dispatch(
                houses[k],
                P[row_of[Int(houses[k].bus)], :];
                T = T,
                τ_batt = τ_batt,
            ) for k in eachindex(houses)
        ]
    end

    # Shared bill/breakout row push for a ledger leg.
    push_bill_rows! = function (name::String, bills, surplus, granularity, house_rows)
        if granularity == "house"
            for (k, hrow) in enumerate(house_rows)
                push!(
                    bill_rows,
                    (
                        tariff = name,
                        unit_id = Int(hrow.house_id),
                        bus = Int(hrow.bus),
                        granularity = "house",
                        bill = hrow.bill,
                        surplus = hrow.surplus,
                        pv_group = string(map_rows[k].pv_group),
                        load_tercile = string(tercile_labels[k]),
                    ),
                )
            end
        else
            for (i, b) in enumerate(input.buses)
                push!(
                    bill_rows,
                    (
                        tariff = name,
                        unit_id = b,
                        bus = b,
                        granularity = "bus",
                        bill = bills[i],
                        surplus = surplus[i],
                        pv_group = missing,
                        load_tercile = missing,
                    ),
                )
            end
        end
        return nothing
    end

    push_breakouts! = function (name::String, bills, surplus)
        (groupings === nothing) && return nothing
        for (gname, group_keys) in groupings
            for (kind, values) in (("bills", bills), ("surplus", surplus))
                bd = equity_breakdown(values, group_keys)
                for g in sort!(collect(keys(bd)); by = string)
                    m = bd[g]
                    push!(
                        breakout_rows,
                        (
                            tariff = name,
                            grouping = gname,
                            group = string(g),
                            metric_kind = kind,
                            n = m.n,
                            gini = m.gini,
                            theil = m.theil,
                            theil_n_excluded = m.theil_n_excluded,
                            atkinson = m.atkinson,
                            atkinson_n_excluded = m.atkinson_n_excluded,
                            palma = m.palma,
                        ),
                    )
                end
            end
        end
        return nothing
    end

    # Uniform price matrix for the flat/tou legs: the same published vector on every bus row.
    uniform_matrix = function (p::Vector{Float64})
        P = Matrix{Float64}(undef, nb, T)
        for i in 1:nb, t in 1:T
            P[i, t] = p[t]
        end
        return P
    end

    # The fairness fold: the leg's prices over the DADP run's OWN quantities (negated ⇒
    # a payment total, directly comparable with `total_payments`).
    fairness_total = function (P)
        f = 0.0
        for t in 1:T, i in 1:nb
            f -= P[i, t] * dadp_nets[i][t]
        end
        return f
    end

    # ---- leg 1: :dadp — the run itself ---------------------------------------------------
    begin
        house_rows = nothing
        certs = Symbol[:not_checked for _ in 1:nb]   # the run IS the bus-level dispatch
        if houses !== nothing
            house_dispatch = house_solve(input.prices)
            certs = Symbol[d.battery_certificate for d in house_dispatch]
            house_rows = [
                (
                    house_id = k,
                    bus = Int(houses[k].bus),
                    net = house_dispatch[k].net,
                    utility = house_dispatch[k].utility,
                ) for k in eachindex(houses)
            ]
        end
        led = build_settlement_ledger(
            input.prices,
            Dict{Int, Vector{Float64}}(input.buses[i] => dadp_nets[i] for i in 1:nb),
            Dict{Int, Float64}(input.buses[i] => dadp_utils[i] for i in 1:nb),
            input.p_import,
            λ₀vec,
            input.buses;
            T = T,
            source = input.source,
            households = house_rows,
        )
        granularity = houses === nothing ? "bus" : "house"
        if granularity == "house"
            bills = Float64[h.bill for h in led.households]
            surplus = Float64[h.surplus for h in led.households]
        else
            bills = Float64[-led.balances[(:aggregator, b)] for b in input.buses]
            surplus = Float64[
                dadp_utils[i] + led.balances[(:aggregator, input.buses[i])] for i in 1:nb
            ]
        end
        aggregators_total = sum(led.balances[(:aggregator, b)] for b in input.buses)
        # Social welfare on the run's own numbers: aggregators' economic surplus
        # (device utility + settlement balance) plus the merchandising surplus — the
        # ledger's social identity, valid for BOTH engines (on :admm it is the
        # primal-welfare echo of r.welfare).
        social_welfare =
            sum(dadp_utils[i] + led.balances[(:aggregator, input.buses[i])] for i in 1:nb) +
            led.merchandising_surplus
        st = ac_feasibility_status(
            feeder,
            aggs,
            [input.bus_nets[a.bus] for a in aggs];
            T = T,
        )
        baseline_netload = Float64[-sum(dadp_nets[i][t] for i in 1:nb) for t in 1:T]
        rb = rebound(baseline_netload, baseline_netload)
        push!(
            summary_rows,
            _summary_row(
                tariff = "dadp",
                engine = engine_str,
                t_horizon = T,
                status = "ok",
                welfare = social_welfare,
                total_payments = -aggregators_total,
                fairness_total = fairness_total(input.prices),
                merchandising_surplus = led.merchandising_surplus,
                dso_total = led.balances[:dso],
                aggregators_total = aggregators_total,
                wholesale_total = led.balances[:wholesale],
                feasibility_status = string(st.status),
                n_thermal_violations = st.n_thermal_violations,
                n_voltage_violations = st.n_voltage_violations,
                max_overload_ratio = st.max_overload_ratio,
                batt_ok = count(==(:ok), certs),
                batt_refused = count(==(:refused), certs),
                batt_not_checked = count(==(:not_checked), certs),
                eq_bills = _equity_columns(bills),
                eq_surplus = _equity_columns(surplus),
                rebound_amount = rb.rebound_amount,
                rebound_ratio = rb.rebound_ratio,
                bills_granularity = granularity,
            ),
        )
        push_bill_rows!("dadp", bills, surplus, granularity, led.households)
        push_breakouts!("dadp", bills, surplus)
    end

    # ---- legs 2-3: :flat and :tou — revenue-neutral derivations at price-taker dispatches
    for (name, price_vec) in
        (("flat", flat_prices(input)), ("tou", tou_prices(input; bins = bins)))
        P = uniform_matrix(price_vec)
        res = price_taker_dispatches(aggs, price_vec; T = T, τ_batt = τ_batt)
        by_bus = Dict(a.bus => res[k] for (k, a) in enumerate(aggs))
        nets = [by_bus[b].net for b in input.buses]
        utils = [by_bus[b].utility for b in input.buses]
        certs = [r.battery_certificate for r in res]
        # Lossless frontier exchange (device-level QP carries no network losses).
        p_imp = Float64[-sum(nets[i][t] for i in 1:nb) for t in 1:T]
        bus_nets = Dict{Int, Vector{Float64}}(input.buses[i] => nets[i] for i in 1:nb)
        bus_utils = Dict{Int, Float64}(input.buses[i] => utils[i] for i in 1:nb)
        house_rows = nothing
        house_certs = nothing
        if houses !== nothing
            house_dispatch = house_solve(P)
            house_certs = Symbol[d.battery_certificate for d in house_dispatch]
            house_rows = [
                (
                    house_id = k,
                    bus = Int(houses[k].bus),
                    net = house_dispatch[k].net,
                    utility = house_dispatch[k].utility,
                ) for k in eachindex(houses)
            ]
        end
        cert_vec = houses === nothing ? certs : house_certs
        led = build_settlement_ledger(
            P,
            bus_nets,
            bus_utils,
            p_imp,
            λ₀vec,
            input.buses;
            T = T,
            source = input.source,
            households = house_rows,
        )
        granularity = houses === nothing ? "bus" : "house"
        if granularity == "house"
            bills = Float64[h.bill for h in led.households]
            surplus = Float64[h.surplus for h in led.households]
        else
            bills = Float64[-led.balances[(:aggregator, b)] for b in input.buses]
            surplus = Float64[
                utils[i] + led.balances[(:aggregator, input.buses[i])] for i in 1:nb
            ]
        end
        aggregators_total = sum(led.balances[(:aggregator, b)] for b in input.buses)
        st = ac_feasibility_status(feeder, aggs, [by_bus[a.bus].net for a in aggs]; T = T)
        leg_netload = Float64[-sum(nets[i][t] for i in 1:nb) for t in 1:T]
        baseline_netload = Float64[-sum(dadp_nets[i][t] for i in 1:nb) for t in 1:T]
        rb = rebound(baseline_netload, leg_netload)
        for t in 1:T
            push!(
                rebound_rows,
                (
                    tariff = name,
                    t = t,
                    baseline_net_load = baseline_netload[t],
                    counterfactual_net_load = leg_netload[t],
                    delta = rb.delta[t],
                    classification = t in rb.reduction_hours ? "reduction" :
                                     t in rb.increase_hours ? "increase" : "",
                ),
            )
        end
        push!(
            summary_rows,
            _summary_row(
                tariff = name,
                engine = engine_str,
                t_horizon = T,
                welfare = sum(utils) - sum(λ₀vec[t] * p_imp[t] for t in 1:T),
                total_payments = -aggregators_total,
                fairness_total = fairness_total(P),
                merchandising_surplus = led.merchandising_surplus,
                dso_total = led.balances[:dso],
                aggregators_total = aggregators_total,
                wholesale_total = led.balances[:wholesale],
                feasibility_status = string(st.status),
                n_thermal_violations = st.n_thermal_violations,
                n_voltage_violations = st.n_voltage_violations,
                max_overload_ratio = st.max_overload_ratio,
                batt_ok = count(==(:ok), cert_vec),
                batt_refused = count(==(:refused), cert_vec),
                batt_not_checked = count(==(:not_checked), cert_vec),
                eq_bills = _equity_columns(bills),
                eq_surplus = _equity_columns(surplus),
                rebound_amount = rb.rebound_amount,
                rebound_ratio = rb.rebound_ratio,
                bills_granularity = granularity,
            ),
        )
        push_bill_rows!(name, bills, surplus, granularity, led.households)
        push_breakouts!(name, bills, surplus)
    end

    # ---- leg 4: :fit — fit_baseline consumed as-is (golden), A1 asymmetry ----------------
    begin
        fit = nothing
        fit_status = "ok"
        fit_notes = ""
        try
            fit =
                fit_optimizer === nothing ?
                fit_baseline(feeder, pf, aggs; T = T, λ₀ = λ₀, on_inexact = :report) :
                fit_baseline(
                    feeder,
                    pf,
                    aggs;
                    T = T,
                    λ₀ = λ₀,
                    on_inexact = :report,
                    optimizer = fit_optimizer,
                )
        catch err
            (
                err isa SolveFailedError ||
                err isa CertificateError ||
                err isa ConvergenceError
            ) || rethrow()
            fit_status = "error:" * string(nameof(typeof(err)))
            fit_notes = first(string(err.msg), 400)
        end
        if fit === nothing
            # Honest error row — the leg is RECORDED, never dropped; no certified value exists.
            push!(
                summary_rows,
                _summary_row(
                    tariff = "fit",
                    engine = engine_str,
                    t_horizon = T,
                    status = fit_status,
                    notes = fit_notes,
                    batt_not_checked = nb,
                ),
            )
        else
            flows = fit.fit_flows
            (
                length(flows) == length(aggs) &&
                all(flows[k].bus == aggs[k].bus for k in eachindex(aggs))
            ) || throw(
                ArgumentError(
                    "compare_tariffs: fit_baseline flows misaligned with the aggregator order.",
                ),
            )
            nets = [Float64.(f.net) for f in flows]
            imps = [Float64.(f.imp) for f in flows]
            exps = [Float64.(f.exp) for f in flows]
            welfare_ok = isfinite(fit.welfare)
            if !welfare_ok && fit_status == "ok"
                fit_status = "fit_inexact"
                fit_notes =
                    "fit_baseline returned non-certified welfare (on_inexact=:report; " *
                    "SITE-2 AC non-convergence, ac_status=$(fit.ac_status)) — bills below are " *
                    "the FIT-OPT dispatch's own, the welfare line is honestly missing."
            end
            bills = Float64[
                sum(FIT_λ_IMPORT * imps[j][t] - FIT_λ_EXPORT * exps[j][t] for t in 1:T)
                for j in 1:nb
            ]
            total_payments = sum(bills)
            imp_total = Float64[sum(imps[j][t] for j in 1:nb) for t in 1:T]
            wholesale_total = sum(λ₀vec[t] * imp_total[t] for t in 1:T)
            dso_total = total_payments   # the DSO's collections == the prosumers' grid payments
            st = ac_feasibility_status(feeder, aggs, nets; T = T)
            push!(
                summary_rows,
                _summary_row(
                    tariff = "fit",
                    engine = engine_str,
                    t_horizon = T,
                    status = fit_status,
                    notes = fit_notes,
                    welfare = welfare_ok ? Float64(fit.welfare) : missing,
                    total_payments = total_payments,
                    fairness_total = missing,  # the FIT triple is not one price vector
                    merchandising_surplus = dso_total - wholesale_total,
                    dso_total = dso_total,
                    aggregators_total = -total_payments,
                    wholesale_total = wholesale_total,
                    feasibility_status = string(st.status),
                    n_thermal_violations = st.n_thermal_violations,
                    n_voltage_violations = st.n_voltage_violations,
                    max_overload_ratio = st.max_overload_ratio,
                    batt_not_checked = nb,   # batteryless A4: the battery never enters the FIT-OPT
                    eq_bills = _equity_columns(bills),
                    eq_surplus = _equity_columns(nothing),  # no per-agg FIT device utility exists
                    rebound_amount = missing,
                    rebound_ratio = missing,
                    bills_granularity = "bus",
                ),
            )
            for (j, b) in enumerate(input.buses)
                push!(
                    bill_rows,
                    (
                        tariff = "fit",
                        unit_id = b,
                        bus = b,
                        granularity = "bus",
                        bill = bills[j],
                        surplus = missing,
                        pv_group = missing,
                        load_tercile = missing,
                    ),
                )
            end
        end
    end

    # ---- flexibility-market legs (opt-in): appended through their own tables ------------
    if flex_markets !== nothing
        flex = _flex_tables(
            feeder,
            pf,
            aggs,
            input,
            flex_markets;
            T = T,
            λ₀vec = λ₀vec,
            bins = bins,
            engine_str = engine_str,
            τ_batt = τ_batt,
            optimizer = welfare_optimizer,
        )
        return (
            summary = vcat(_rows_to_dataframe(summary_rows), flex.summary; cols = :union),
            household_bills = vcat(
                _rows_to_dataframe(bill_rows),
                flex.household_bills;
                cols = :union,
            ),
            equity_breakouts = _rows_to_dataframe(breakout_rows),
            rebound = vcat(_rows_to_dataframe(rebound_rows), flex.rebound; cols = :union),
        )
    end

    return (
        summary = _rows_to_dataframe(summary_rows),
        household_bills = _rows_to_dataframe(bill_rows),
        equity_breakouts = _rows_to_dataframe(breakout_rows),
        rebound = _rows_to_dataframe(rebound_rows),
    )
end

# The additive summary columns of a flexibility-market row, in order, appended after the 37
# base columns of `_summary_row` (internal; `_flex_extras` builds them in this order).
const FLEX_EXTRA_COLUMNS = (
    :coordination,
    :baseline_tariff,
    :payment_rule,
    :n_blocks,
    :baseline_inflation,
    :flex_payments_total,
    :energy_merchandising_surplus,
    :tariff_on_activation,
    :flex_payment_on_delivered,
    :flex_up_total,
    :flex_down_total,
    :delivery_shortfall_total,
    :delivery_shortfall_max,
    :delivery_shortfall_ratio,
    :delivery_shortfall_total_10w,
    :tracking_weight,
    :baseline_overpayment,
    :n_congested_hours,
    :congestion_kappa,
    :congestion_kappa_lo,
    :congestion_kappa_hi,
    :redispatch_socp_maxgap,
    :redispatch_p_import_total,
    :welfare_socp_import,
    :welfare_dadp_lossless,
    :welfare_gap_vs_dadp_lossless,
    :price_gap_vs_dadp_max,
    :bid_repair_max,
    :min_bid_ask_gap,
    :max_wash,
    :n_probe_solves,
    :n_probe_failed,
    :baseline_batt_refused,
    :flex_wall_s,
)

# Internal: the additive flex columns of one row, every key always present (`missing` when not
# computed), so ok rows and status rows share one field set and `_rows_to_dataframe`, which keys
# its schema on the first row, can never drop a column. Column meanings:
#   - coordination / baseline_tariff / payment_rule / n_blocks / baseline_inflation: the market;
#   - flex_payments_total: Σ price·quantity over the real payment rows (β phantom excluded);
#     baseline_overpayment: the β phantom rows' total;
#   - energy_merchandising_surplus: tariff collections − wholesale, i.e. the DSO line before
#     any flexibility payment (dso_total + flex_payments_total + baseline_overpayment);
#   - tariff_on_activation = Σ p_t·Δ (money overlap, informational); flex_payment_on_delivered:
#     the uniform payment on the delivered deviation (missing for pay-as-bid);
#   - flex_up_total / flex_down_total: Σ max(Δ, 0) and Σ max(−Δ, 0) over aggregators and hours;
#   - delivery_shortfall_total / _max: Σ and max of |n − (b + Δ)|; _ratio: the total over
#     Σ|Δ| (NaN with no activation); _total_10w: the total at ten times the tracking weight;
#   - tracking_weight: the delivery penalty weight w;
#   - n_congested_hours with congestion_kappa (the threshold) and the measured interval
#     [congestion_kappa_lo, congestion_kappa_hi) of thresholds that give the same hours;
#   - redispatch_socp_maxgap / redispatch_p_import_total: the stage-2 exactness gap and Σ import;
#   - welfare_socp_import: utilities minus λ₀ on the stage-2 SOCP import (exact when the
#     shortfall is 0); welfare_dadp_lossless: the DADP dispatch on the lossless footing, and
#     welfare_gap_vs_dadp_lossless = welfare − welfare_dadp_lossless (like for like);
#   - price_gap_vs_dadp_max: max |π − λ_dadp| over activated (|Δ| above the range floor)
#     bus-hours (NaN with no activation);
#   - bid_repair_max, min_bid_ask_gap, max_wash, n_probe_solves, n_probe_failed: bid and
#     clearing diagnostics; baseline_batt_refused: refused stage-1 battery certificates;
#   - flex_wall_s: wall time of the shared physics of the clear.
function _flex_extras(;
    coordination = missing,
    baseline_tariff = missing,
    payment_rule = missing,
    n_blocks = missing,
    baseline_inflation = missing,
    flex_payments_total = missing,
    energy_merchandising_surplus = missing,
    tariff_on_activation = missing,
    flex_payment_on_delivered = missing,
    flex_up_total = missing,
    flex_down_total = missing,
    delivery_shortfall_total = missing,
    delivery_shortfall_max = missing,
    delivery_shortfall_ratio = missing,
    delivery_shortfall_total_10w = missing,
    tracking_weight = missing,
    baseline_overpayment = missing,
    n_congested_hours = missing,
    congestion_kappa = missing,
    congestion_kappa_lo = missing,
    congestion_kappa_hi = missing,
    redispatch_socp_maxgap = missing,
    redispatch_p_import_total = missing,
    welfare_socp_import = missing,
    welfare_dadp_lossless = missing,
    welfare_gap_vs_dadp_lossless = missing,
    price_gap_vs_dadp_max = missing,
    bid_repair_max = missing,
    min_bid_ask_gap = missing,
    max_wash = missing,
    n_probe_solves = missing,
    n_probe_failed = missing,
    baseline_batt_refused = missing,
    flex_wall_s = missing,
)
    return (;
        coordination,
        baseline_tariff,
        payment_rule,
        n_blocks,
        baseline_inflation,
        flex_payments_total,
        energy_merchandising_surplus,
        tariff_on_activation,
        flex_payment_on_delivered,
        flex_up_total,
        flex_down_total,
        delivery_shortfall_total,
        delivery_shortfall_max,
        delivery_shortfall_ratio,
        delivery_shortfall_total_10w,
        tracking_weight,
        baseline_overpayment,
        n_congested_hours,
        congestion_kappa,
        congestion_kappa_lo,
        congestion_kappa_hi,
        redispatch_socp_maxgap,
        redispatch_p_import_total,
        welfare_socp_import,
        welfare_dadp_lossless,
        welfare_gap_vs_dadp_lossless,
        price_gap_vs_dadp_max,
        bid_repair_max,
        min_bid_ask_gap,
        max_wash,
        n_probe_solves,
        n_probe_failed,
        baseline_batt_refused,
        flex_wall_s,
    )
end

# Internal: the summary row of a flexibility-market leg whose clear did not reach `ok`. The
# market identity, the DADP lossless welfare and whatever bid diagnostics exist are filled;
# every other value is `missing`, with the same field set as an ok row.
function _flex_status_row(
    fm::FlexMarket,
    phys;
    engine_str::String,
    T::Int,
    nb::Int,
    welfare_dadp_lossless::Float64,
)
    known(x) = x === nothing ? missing : x
    return merge(
        _summary_row(
            tariff = _flex_row_name(fm),
            engine = engine_str,
            t_horizon = T,
            status = phys.status,
            notes = first(string(phys.notes), 400),
            batt_not_checked = nb,
        ),
        _flex_extras(;
            coordination = coordination_label(fm),
            baseline_tariff = string(fm.baseline_tariff),
            payment_rule = string(fm.payment_rule),
            n_blocks = fm.n_blocks,
            baseline_inflation = fm.baseline_inflation,
            congestion_kappa = FLEX_CONGESTION_KAPPA,
            welfare_dadp_lossless = welfare_dadp_lossless,
            bid_repair_max = known(phys.bid_repair_max),
            min_bid_ask_gap = known(phys.min_bid_ask_gap),
            n_probe_solves = phys.n_probe_solves,
            n_probe_failed = phys.n_probe_failed,
            baseline_batt_refused = phys.baseline === nothing ? missing :
                                    phys.baseline.n_battery_refused,
            flex_wall_s = phys.wall_s,
        ),
    )
end

# Internal: the flexibility-market rows of `compare_tariffs` (summary, household_bills and
# rebound tables), from the DADP run's settlement `input`. The markets are grouped by their
# clear key (baseline tariff, n_blocks) in first-appearance order: the physics of a clear and
# its AC check run once per key, and each `FlexMarket` then settles its own money on the
# shared physics, so the payment rule and β cannot move a physics column. Rows follow the
# input order of `fms`.
function _flex_tables(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggs::AbstractVector{<:Aggregator},
    input::SettlementInput,
    fms::Vector{FlexMarket};
    T::Int,
    λ₀vec::Vector{Float64},
    bins::Vector{Vector{Int}},
    engine_str::String,
    τ_batt::Real,
    optimizer = nothing,
)
    buses = input.buses
    nb = length(buses)
    agg_buses = Int[a.bus for a in aggs]
    slot = Dict(b => k for (k, b) in enumerate(agg_buses))
    row_of = Dict(b => i for (i, b) in enumerate(buses))
    dadp_netload = Float64[-sum(input.bus_nets[b][t] for b in buses) for t in 1:T]
    welfare_dadp_lossless =
        sum(input.bus_utilities[b] for b in buses) -
        sum(λ₀vec[t] * (-sum(input.bus_nets[b][t] for b in buses)) for t in 1:T)

    clears = Dict{Tuple{Symbol, Int}, Any}()
    summary_rows = Vector{NamedTuple}()
    bill_rows = Vector{NamedTuple}()
    rebound_rows = Vector{NamedTuple}()
    for fm in fms
        key = (fm.baseline_tariff, fm.n_blocks)
        if !haskey(clears, key)
            price = _baseline_price(input, fm; bins = bins)
            phys = _flex_physics(
                feeder,
                pf,
                aggs,
                price;
                T = T,
                λ₀ = λ₀vec,
                n_blocks = fm.n_blocks,
                optimizer = optimizer,
                τ_batt = τ_batt,
            )
            feas =
                phys.status == "ok" ?
                ac_feasibility_status(feeder, aggs, phys.delivered.net; T = T) : nothing
            clears[key] = (; phys, feas)
        end
        c = clears[key]
        phys = c.phys
        name = _flex_row_name(fm)
        if phys.status != "ok"
            push!(
                summary_rows,
                _flex_status_row(
                    fm,
                    phys;
                    engine_str = engine_str,
                    T = T,
                    nb = nb,
                    welfare_dadp_lossless = welfare_dadp_lossless,
                ),
            )
            continue
        end
        st = c.feas
        s = _flex_settle(phys, fm, agg_buses, input; T = T, λ₀ = λ₀vec)
        led = s.ledger
        bills = Float64[s.bills[b] for b in buses]
        surplus = Float64[s.surplus[b] for b in buses]
        aggregators_total = sum(led.balances[(:aggregator, b)] for b in buses)
        dso = led.balances[:dso]
        flex_netload =
            Float64[-sum(phys.delivered.net[slot[b]][t] for b in buses) for t in 1:T]
        rb = rebound(dadp_netload, flex_netload)
        up = 0.0
        down = 0.0
        for Δ in phys.Δ, t in 1:T
            up += max(Δ[t], 0.0)
            down += max(-Δ[t], 0.0)
        end
        activated = up + down
        price_gap = NaN
        for (k, b) in enumerate(agg_buses), t in 1:T
            abs(phys.Δ[k][t]) > FLEX_RANGE_FLOOR || continue
            g = abs(phys.π[k][t] - input.prices[row_of[b], t])
            price_gap = isnan(price_gap) ? g : max(price_gap, g)
        end
        push!(
            summary_rows,
            merge(
                _summary_row(
                    tariff = name,
                    engine = engine_str,
                    t_horizon = T,
                    status = "ok",
                    notes = string(phys.notes),
                    welfare = s.welfare_lossless,
                    total_payments = -aggregators_total,
                    fairness_total = missing,  # flexibility payments are not one price vector
                    merchandising_surplus = dso,
                    dso_total = dso,
                    aggregators_total = aggregators_total,
                    wholesale_total = led.balances[:wholesale],
                    feasibility_status = string(st.status),
                    n_thermal_violations = st.n_thermal_violations,
                    n_voltage_violations = st.n_voltage_violations,
                    max_overload_ratio = st.max_overload_ratio,
                    batt_ok = phys.delivered.n_battery_ok,
                    batt_refused = phys.delivered.n_battery_refused,
                    batt_not_checked = phys.delivered.n_battery_not_checked,
                    eq_bills = _equity_columns(bills),
                    eq_surplus = _equity_columns(surplus),
                    rebound_amount = rb.rebound_amount,
                    rebound_ratio = rb.rebound_ratio,
                    bills_granularity = "bus",
                ),
                _flex_extras(;
                    coordination = coordination_label(fm),
                    baseline_tariff = string(fm.baseline_tariff),
                    payment_rule = string(fm.payment_rule),
                    n_blocks = fm.n_blocks,
                    baseline_inflation = fm.baseline_inflation,
                    flex_payments_total = s.flex_payments_total,
                    energy_merchandising_surplus = dso +
                                                   s.flex_payments_total +
                                                   s.baseline_overpayment,
                    tariff_on_activation = s.tariff_on_activation,
                    flex_payment_on_delivered = s.flex_payment_on_delivered,
                    flex_up_total = up,
                    flex_down_total = down,
                    delivery_shortfall_total = phys.shortfall_total,
                    delivery_shortfall_max = maximum(maximum, phys.shortfall),
                    delivery_shortfall_ratio = activated > 0 ?
                                               phys.shortfall_total / activated : NaN,
                    delivery_shortfall_total_10w = phys.shortfall_10w_total,
                    tracking_weight = phys.weight,
                    baseline_overpayment = s.baseline_overpayment,
                    n_congested_hours = count(phys.congested),
                    congestion_kappa = FLEX_CONGESTION_KAPPA,
                    congestion_kappa_lo = phys.kappa_lo,
                    congestion_kappa_hi = phys.kappa_hi,
                    redispatch_socp_maxgap = phys.maxgap,
                    redispatch_p_import_total = sum(phys.p_import_stage2),
                    welfare_socp_import = s.welfare_socp_import,
                    welfare_dadp_lossless = welfare_dadp_lossless,
                    welfare_gap_vs_dadp_lossless = s.welfare_lossless -
                                                   welfare_dadp_lossless,
                    price_gap_vs_dadp_max = price_gap,
                    bid_repair_max = phys.bid_repair_max,
                    min_bid_ask_gap = phys.min_bid_ask_gap,
                    max_wash = phys.max_wash,
                    n_probe_solves = phys.n_probe_solves,
                    n_probe_failed = phys.n_probe_failed,
                    baseline_batt_refused = phys.baseline.n_battery_refused,
                    flex_wall_s = phys.wall_s,
                ),
            ),
        )
        for (i, b) in enumerate(buses)
            push!(
                bill_rows,
                (
                    tariff = name,
                    unit_id = b,
                    bus = b,
                    granularity = "bus",
                    bill = bills[i],
                    surplus = surplus[i],
                    pv_group = missing,
                    load_tercile = missing,
                    delivery_shortfall = sum(phys.shortfall[slot[b]]),
                ),
            )
        end
        for t in 1:T
            push!(
                rebound_rows,
                (
                    tariff = name,
                    t = t,
                    baseline_net_load = dadp_netload[t],
                    counterfactual_net_load = flex_netload[t],
                    delta = rb.delta[t],
                    classification = t in rb.reduction_hours ? "reduction" :
                                     t in rb.increase_hours ? "increase" : "",
                    delivery_shortfall = sum(phys.shortfall[slot[b]][t] for b in buses),
                ),
            )
        end
    end
    return (
        summary = _rows_to_dataframe(summary_rows),
        household_bills = _with_shortfall_column(_rows_to_dataframe(bill_rows)),
        rebound = _with_shortfall_column(_rows_to_dataframe(rebound_rows)),
    )
end

# Internal: a flex bill or rebound table always carries the `delivery_shortfall` column, even
# when every clear was a status row (no rows), so the appended column set does not depend on
# the solver outcome.
function _with_shortfall_column(df::DataFrame)
    hasproperty(df, :delivery_shortfall) || (
        df[!, :delivery_shortfall] =
            Union{Missing, Float64}[missing for _ in 1:size(df, 1)]
    )
    return df
end
