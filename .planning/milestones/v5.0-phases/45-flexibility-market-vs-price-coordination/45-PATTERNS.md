# Phase 45: Flexibility Market vs Price Coordination - Pattern Map

**Mapped:** 2026-11-04
**Files analyzed:** 17 new or modified files (one of them is the CSV data artifact)
**Analogs found:** 17 / 17. Three sub-patterns have only a partial analog: the L1 tracking penalty, the PAV monotone repair and the congested-hour classifier (see "No Analog Found").

All line numbers are against HEAD `2e3f3b9`, with a clean tree.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/coordination/coordination.jl` (new) | model types (`AbstractCoordination`, `PriceBased`, `FlexMarket`, `_flex_row_name`) | config / validation | `src/actors/actor_objective.jl` (type hierarchy) + `src/actors/Portfolio.jl:15-31` (kwarg ctor) | exact |
| `src/coordination/flex_market.jl` (new): `FlexBidDevice` | device | build (`contribute!` → `(; vars, p_inject, utility)`) | `src/devices/Behavioural.jl` (`OptOut`/`Rebound`) + `src/devices/Interruptible.jl:157-171` | exact |
| `src/coordination/flex_market.jl`: fixed-net probe + delivery QP | service (aggregator QP) | request-response, build once and re-solve | `src/settlement/price_taker.jl:79-144` | exact (shape); the mutation loop is new |
| `src/coordination/flex_market.jl`: stage-2 clear + status mapping | service (DSO SOCP) | request-response | `src/settlement/comparison.jl:311-315` (DADP solve) + `:653-678` (fit try/catch → status) | exact |
| `src/coordination/flex_market.jl`: flex payment rows builder | utility | transform (solved quantities → ledger rows) | `src/settlement/run_inputs.jl:424-463` (`actor_wedge_rows`) | exact |
| `src/coordination/flex_market.jl`: congested hours | utility | transform | `src/pricing/dlmp.jl:319` (`decompose_dlmp`) consumed as-is | partial |
| `src/settlement/SettlementLedger.jl` (mod): `flex_payments` kwarg | model (ledger) | transform (double-entry) | the same file's own `actor_wedges` flow: `:207`, `:336-369`, `:426-442` | exact |
| `src/settlement/run_inputs.jl` (mod): forward `flex_payments` | adapter | passthrough | the same file, `:523-540` | exact |
| `src/settlement/comparison.jl` (mod): `flex_market`, `welfare_optimizer` | service (runner) | batch assembly | the same file: `fit_optimizer` if/else `:658-669`, the flat/tou leg `:553-650`, return `:767-772` | exact |
| `src/TSODSO.jl` (mod): includes | config | — | `src/TSODSO.jl:299-312` (settlement block) and `:142-145` (actors block) | exact |
| `docs/src/api.md` (mod): coordination Pages block | config (docs) | — | `docs/src/api.md:91-109` | exact |
| `test/test_flex_market_fence.jl` (new) | test (regression fence) | — | `test/test_actor_default_fence.jl` (whole file) + `test/test_settlement.jl:984-1089` | exact |
| `test/test_flex_market.jl` (new) | test (unit + integration, fast) | — | `test/test_actor_settlement.jl:19-188,298-324` + `test/test_settlement.jl:1091-1106` | exact |
| `test/test_flex_market_ieee.jl` (new, `:slow`) | test (slow integration) | — | `test/test_settlement.jl:1526-1584` + `test/test_ieee123_admm.jl:19-61` | exact |
| `test/test_exports.jl` (mod) + `test/expected_broken.txt` (mod) | test config | — | `test/test_exports.jl:4-45,75-184`; `test/expected_broken.txt:24` | exact |
| `scripts/tariff_comparison.jl` (mod): `--flex-market`, `--mode ieee123` | script (measurement) | file-I/O (CSV upsert) | the same file: `parse_args!` `:115-141`, `ground_main` `:407-458`, upsert `:206-220,345-370`; population from `scripts/actor_behaviour_sweep.jl:73-141` | exact |
| `scripts/README.md` (mod) + `docs/literate/flex_market.jl` (new) + `docs/make.jl` (mod) | docs | file-I/O (reads the committed CSV) | `docs/literate/settlement_equity.jl:125-204` (reads the same CSV) + `docs/literate/aggregator_actor.jl`; `docs/make.jl:38,110`; `scripts/README.md:52` | exact |

---

## Pattern Assignments

### `src/coordination/coordination.jl` (model types, config/validation)

**Analog:** `src/actors/actor_objective.jl` (the whole file is 107 lines: an abstract supertype, a default singleton and one validated concrete type, with the export at the bottom).

**Type hierarchy pattern** (`actor_objective.jl:21-53`):
```julia
"""
    AbstractActorObjective

Supertype of per-actor objectives (see [`WelfareObjective`](@ref), [`ProfitObjective`](@ref)).
"""
abstract type AbstractActorObjective end

"""
    WelfareObjective()

The default objective: ... exactly the pre-phase-44 behaviour. The default path is byte-identical.
"""
struct WelfareObjective <: AbstractActorObjective end

struct ProfitObjective{M <: Union{Real, AbstractVector{<:Real}}} <: AbstractActorObjective
    wedge::M
    function ProfitObjective(wedge::M) where {M <: Union{Real, AbstractVector{<:Real}}}
        all(isfinite, wedge) ||
            throw(ArgumentError("ProfitObjective: wedge must be finite, got $(wedge)"))
        return new{M}(wedge)
    end
end
```
Map it as follows:
- `AbstractCoordination` corresponds to `AbstractActorObjective`;
- `PriceBased` corresponds to `WelfareObjective`, a field-less singleton;
- `FlexMarket` corresponds to `ProfitObjective`, with the validation inside the inner constructor.

**Keyword-constructor pattern** (`src/actors/Portfolio.jl:19-30`). This is the shape for `FlexMarket(; baseline_tariff = :flat, payment_rule = :uniform, n_blocks = 4, baseline_inflation = 0.0)`:
```julia
    function Portfolio(
        sites::AbstractVector{<:Aggregator};
        objective::AbstractActorObjective = WelfareObjective(),
        name::Symbol = :portfolio,
    )
        isempty(sites) && throw(ArgumentError("Portfolio $(name): sites must be non-empty"))
        ...
        return new(Vector{Aggregator}(sites), objective, name)
    end
```
- **Validation (VALIDATION row 1):** `payment_rule ∈ (:uniform, :pay_as_bid)`, `baseline_tariff ∈ (:flat, :tou)`, `n_blocks >= 1`, and `isfinite(β) && β >= 0`. Each check throws its own `ArgumentError`; never use `@assert` (convention, `Interruptible.jl:64-67`).
- **Field types:** use concrete fields (`Symbol`, `Int`, `Float64`) to keep the JET ratchet flat.
- **`_flex_row_name(fm)`:** an internal, unexported pure function. It must be injective over `(payment_rule, baseline_tariff, n_blocks, β)` (Pitfall 9). The CSV upsert key is `(:mode, :tariff, :seed, :t_horizon)` at `scripts/tariff_comparison.jl:352`. Detect duplicates with `allunique(names)` before any solve, in the guard block of `compare_tariffs` (pattern at `comparison.jl:265-307`).
- **Export:** the line goes at the bottom of the file, as at `actor_objective.jl:106`. A name may be exported from exactly one file (`test/test_exports.jl:186-208`).

---

### `src/coordination/flex_market.jl`: `FlexBidDevice` (device, build)

**Analog:** `src/devices/Behavioural.jl`. It is the most recent wrapper device, and like the bid device it holds a precomputed baseline and returns affine `p_inject`.

**File header + struct pattern** (`Behavioural.jl:1-13,127-145`): a SEAM header explaining why the type exists, then a typed struct with Float64 fields and the validation in the inner constructor:
```julia
struct OptOut{D <: AbstractDevice} <: AbstractDevice
    b::Vector{Float64}
    Ub::Float64
    ...
    function OptOut(inner::D, b::AbstractVector{<:Real}, Ub::Real) where {D <: AbstractDevice}
        _beh_check_inner(inner, "OptOut")
        _beh_check_baseline(b, Ub, "OptOut")
        return new{D}(Float64[b...], Float64(Ub), ...)
    end
end
```
In the inner constructor, validate:
- `size(up_q) == size(up_m) == size(dn_q) == size(dn_g)`;
- `length(gross) == size(up_q, 1)`;
- every value finite, every `q >= 0`.

Copy the finite guard from `Behavioural.jl:65-69` (`_beh_check_baseline`) and the T guard from `:74-82` (`_beh_check_T`).

**`contribute!` pattern.** Anonymous variables, nothing written to residuals or the objective, and a NamedTuple return (`Behavioural.jl:198-221`):
```julia
function contribute!(d::OptOut, ctx::ModelContext; T::Int, kwargs...)
    _beh_check_T(d.b, T, "OptOut")
    p_inject = AffExpr[AffExpr(d.b[t]) for t in 1:T]
    utility = zero(QuadExpr) + d.Ub
    return (; vars = (;), p_inject, utility)
end

function contribute!(d::Rebound, ctx::ModelContext; T::Int, kwargs...)
    ...
    m = ctx.model
    u = @variable(m, [t = 1:T], lower_bound = 0.0)
```
Bounded anonymous variable form (`Interruptible.jl:160`):
```julia
    p = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)
```
- **Anonymous variables only.** Named containers collide when a second aggregator contributes to the same model; `Aggregator.jl:178-189` documents the `Pdc_param` collision.
- **No `q_inject` key.** `Aggregator.jl:203` checks it with `hasproperty`, so omitting it gives `:Rq = −Pdc·tanφ`. That is the locked reactive model (research Q1).
- **Traits:** keep the defaults (`AbstractDevice.jl:84,109,130-131`: `is_flexible_load = false`, `storage_kind = :none`) and add no overrides. Per `CapabilityTraits.jl:16-17`, new devices that do need an override put it in their own file.
- **Include order:** the device can be defined after `Aggregator.jl`. `Aggregator.contribute!` dispatches at runtime (`Aggregator.jl:198-199`: `for d in agg.devices; res = contribute!(d, ctx; T = T)`).

**Stage-2 aggregator construction** (`Aggregator.jl:105-113`, outer constructor):
```julia
function Aggregator(bus::Integer, φ::Real, devices::AbstractVector{<:AbstractDevice}, Pdc::AbstractVector{<:Real})
```
Build `stage2_aggs = [Aggregator(a.bus, a.φ, [FlexBidDevice(...)], a.Pdc) for a in aggs]` **in the same (ascending-bus) order as `aggs`**. `settlement_input(ctx)` throws on a non-ascending `ctx.meta[:agg_net]` (`run_inputs.jl:133-141`).

---

### `src/coordination/flex_market.jl`: fixed-net probe model and L1 delivery QP (aggregator QP, build once and re-solve)

**Analog:** `src/settlement/price_taker.jl:79-144`. Copy the build shape **without modifying the function**: it feeds the default flat and tou legs, and the research anti-patterns forbid touching it.

**Header discipline to copy** (`price_taker.jl:6-18`): no ρ term, never `solve_agr!`, and prices as plain `Float64`, never JuMP `Parameter`s.

**Guards** (`price_taker.jl:85-98`):
```julia
    length(price) == T || throw(
        ArgumentError("price_taker_dispatch: price has length $(length(price)), expected T=$T"),
    )
    for t in 1:T
        isfinite(price[t]) || throw(ArgumentError(...))
    end
```

**Core build** (`price_taker.jl:100-117`). This is the probe model's skeleton:
```julia
    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.T = T
    res = contribute!(agg, ctx; T = T)

    @variable(model, pag[1:T])
    @constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    register_constraint!(ctx, :price_taker_coupling, coupling)

    @objective(model, Max, ctx.objective + sum(price[t] * pag[t] for t in 1:T))

    assert_solved!(model; dual = false)

    net = Float64[value(pag[t]) for t in 1:T]
    utility = value(ctx.objective)
```
- **Probe:** drop the price term (`@objective(model, Max, ctx.objective)`), then follow the sequence in RESEARCH "Code Examples / Fixed-net probe": `fix(pag[t], b[t]; force = true)` → `optimize!` → unfix/range LP → re-fix.
- **Probe gating:** do **not** use `assert_solved!` inside the probe loop, because it throws. Gate each probe on `termination_status(m) == MOI.OPTIMAL && primal_status(m) == MOI.FEASIBLE_POINT`, then count failures (`n_probe_failed`). Each aggregator's model is built once, outside the hour and block loops.
- **Delivery:** reuse the build above, plus anonymous `s = @variable(model, [t = 1:T], lower_bound = 0.0)`, `@constraint(model, [t=1:T], s[t] >= pag[t] - target[t])` and `>= target[t] - pag[t]` (the anonymous-constraint pattern at `Behavioural.jl:209-211`). Objective: `Max ctx.objective + Σ p·pag − w·Σ s`. A single solve, so `assert_solved!(model; dual = false)` is fine there.

**Battery-certificate report semantics** (`price_taker.jl:126-141`). Copy this verbatim for the **delivery** solves only (research table, "Run the EV/battery certificates on delivery solves only"):
```julia
    has_battery = any(
        haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q) for
        varlist in values(ctx.agg_device_vars) for v in varlist
    )
    battery_certificate = :not_checked
    battery_message = ""
    if has_battery
        battery_certificate = :ok
        try
            assert_battery_complementarity!(ctx; τ = τ_batt, T = T, on_violation = :error)
        catch err
            err isa CertificateError || rethrow()
            battery_certificate = :refused
            battery_message = err.msg
        end
    end
    return (; net, utility, battery_certificate, battery_message)
```
The delivery result must expose `net`, `utility` and `battery_certificate`, the same field names as `price_taker_dispatch`, so that the summary-row code from `comparison.jl:557-561,638-640` transfers unchanged.

---

### `src/coordination/flex_market.jl`: stage-2 clear and status mapping (DSO SOCP, request-response)

**Analog for the solve + price read** (`comparison.jl:311-315`):
```julia
    local input
    if engine === :centralized
        ctx, _obj, _dadp =
            solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
        input = settlement_input(ctx; T = T, λ₀ = λ₀)
```
For stage 2, call it with `stage2_aggs`. `in2.prices` is the gated clearing price π. **Never** use `in2.bus_utilities`: on this ctx it is −(bid cost) (research anti-pattern). `in2.bus_nets` gives the targets `b + Δ`.

**Optimizer passthrough analog** (`comparison.jl:658-669`). `solve_welfare`'s default is `optimizer = select_optimizer(problem_class(pf))` (`welfare_solve.jl:123`), so `nothing` cannot be forwarded as a value. Use the if/else shape:
```julia
            fit =
                fit_optimizer === nothing ?
                fit_baseline(feeder, pf, aggs; T = T, λ₀ = λ₀, on_inexact = :report) :
                fit_baseline(
                    feeder, pf, aggs;
                    T = T, λ₀ = λ₀, on_inexact = :report,
                    optimizer = fit_optimizer,
                )
```

**Error → status-row analog** (`comparison.jl:670-678`):
```julia
        catch err
            (
                err isa SolveFailedError ||
                err isa CertificateError ||
                err isa ConvergenceError
            ) || rethrow()
            fit_status = "error:" * string(nameof(typeof(err)))
            fit_notes = first(string(err.msg), 400)
        end
```
Refine this for stage 2 with the error fields at `src/core/errors.jl:33-39,71-75`:
- `err isa SolveFailedError && err.termination_status in (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED)` → `"infeasible_redispatch"`;
- `err isa CertificateError && err.kind === :socp_exact` → `"inexact_redispatch"`;
- any other solver-outcome error → `"error:<Type>"`;
- anything else → `rethrow()`.

`MOI` is `JuMP.MOI` (`errors.jl:11`).

**Gate order you get for free** (`welfare_solve.jl:193,222-228,246-254,267,270,284-289,304-306`):
1. `contribute!(pf)`;
2. the aggregator roll-up, stashed in `ctx.meta[:agg_net]`;
3. `p_import`, free-sign under `allow_export`;
4. `close_balance!`;
5. the objective;
6. `assert_solved!(dual = true)`;
7. `assert_socp_exact!`, with `ctx.meta[:socp_maxgap]` recorded.

Read `ctx2.meta[:socp_maxgap]` for the `redispatch_socp_maxgap` column.

---

### `src/coordination/flex_market.jl`: flex payment rows (utility, transform)

**Analog:** `src/settlement/run_inputs.jl:424-463` (`actor_wedge_rows`). This is the internal, unexported builder that produces the rows the ledger keyword consumes:
```julia
function actor_wedge_rows(ctx::ModelContext, portfolios, aggregators; T::Int)
    haskey(ctx.meta, :agg_net) || throw(
        ArgumentError("actor_wedge_rows: ctx.meta is missing :agg_net (not a solve_welfare ctx)."),
    )
    ...
    rows = NamedTuple[]
    for (a, p) in enumerate(portfolios)
        for s in p.sites
            ...
            push!(rows, (; actor = a, bus = entries[k].bus, m = _wedge_vec(p.objective, T),
                         net = Float64[value(entries[k].net[t]) for t in 1:T]))
```
- **Row shape:** `(; bus, t, price, quantity)` (RESEARCH Pattern 4). Use a concrete `Vector{NamedTuple{(:bus,:t,:price,:quantity),Tuple{Int,Int,Float64,Float64}}}` rather than `NamedTuple[]`, to keep JET quiet.
- **Docstring:** the analog's docstring at `run_inputs.jl:406-423` is the style for this builder's docstring, including the "Internal (unexported)" line.

---

### `src/coordination/flex_market.jl`: congested hours (utility, transform)

**Analog:** `decompose_dlmp` (`src/pricing/dlmp.jl:276-325`), consumed as-is. It returns a `DlmpDecomposition` (`:241-248`) with `(N_buses, T)` matrices `energy`, `cone`, `drop`, `congestion`, `reactive` and `total`. Call it on the **truthful** stage-2 `ctx2` only after `solve_welfare` returned, which means after the gate; `_assert_priceable` (`:326`) refuses anything else. The classifier is a pure function: `t` is congested iff `maximum(abs.(d.congestion[:, t]) .+ abs.(d.drop[:, t])) > κ * λ₀[t]`, with κ = 1e-2. That rule is the research Q8 recommendation; document it.

---

### `src/settlement/SettlementLedger.jl` (modified): `flex_payments` keyword

**Analog:** the same file's `actor_wedges` addition. This is a mirror copy, done three times:

1. **Signature** (`:197-208`): add `flex_payments = nothing` after `actor_wedges = nothing`. Extend the docstring bullet list at `:165-170` with one bullet in the same style. The docstring's flows list `(a)` to `(c)` at `:172-182` also gets an `(e)` entry. Note that flow (d) lives only in the bullet at `:165-170`, so keep both places consistent.
2. **V5 validation block**, copied from `:336-369`:
```julia
    if actor_wedges !== nothing
        for (k, w) in enumerate(actor_wedges)
            hasproperty(w, :actor) &&
            hasproperty(w, :bus) &&
            hasproperty(w, :m) &&
            hasproperty(w, :net) || throw(
                ArgumentError(
                    "build_settlement_ledger: actor_wedges[$k] must be a NamedTuple " *
                    "(; actor, bus, m, net).",
                ),
            )
            Int(w.bus) in buses || throw(ArgumentError(... "is not one of the aggregator buses $buses."))
            ...
            _finite_or_throw(w.m, "actor_wedges[$k].m")
```
   For flex rows, check `:bus/:t/:price/:quantity` presence, `Int(f.bus) in buses`, `1 <= f.t <= T`, and `isfinite(f.price) && isfinite(f.quantity)`. Do this BEFORE `transfers = Transfer[]` (`:373`).
3. **Flow (e)**, placed after flow (d) at `:426-442` and BEFORE the fold at `:444`:
```julia
    if actor_wedges !== nothing
        for w in actor_wedges
            for t in 1:T
                _push_transfer_pair!(
                    transfers,
                    (:actor, Int(w.actor)),
                    (:aggregator, Int(w.bus)),
                    t,
                    Float64(w.m[t]),
                    -Float64(w.net[t]),
                )
```
   For flex rows: `_push_transfer_pair!(transfers, (:aggregator, Int(f.bus)), :dso, Int(f.t), Float64(f.price), Float64(f.quantity))`. **Direction check:** `balances[tr.from] += amount` (`:449`). So with `from = (:aggregator, bus)` and `amount = price·quantity > 0` for up-flex, the aggregator's balance rises, meaning it earns. That matches flow (a)'s exporter-earns convention at `:380-393`. Conservation is exact through `_push_transfer_pair!` (`:101-130`). Do not touch the `sizehint!` at `:374-377`: it is a hint only, and changing it would alter the default path's code.

`merchandising_surplus = balances[:dso]` (`:463`) then automatically becomes the DSO's net after flex payments. That is the research Q5 mapping.

---

### `src/settlement/run_inputs.jl` (modified): forward `flex_payments`

**Analog:** the same overload, `:523-540`. Add one kwarg and one forwarded line:
```julia
function build_settlement_ledger(
    input::SettlementInput;
    households = nothing,
    actor_wedges = nothing,
)
    return build_settlement_ledger(
        input.prices, input.bus_nets, input.bus_utilities, input.p_import, input.λ₀, input.buses;
        T = input.T, source = input.source,
        households = households,
        actor_wedges = actor_wedges,
    )
end
```
Also update its docstring at `:513-522`. That docstring does not even mention `actor_wedges` today; mention both.

---

### `src/settlement/comparison.jl` (modified): `flex_market` and `welfare_optimizer`

**Signature:** add the keywords after `agr_optimizer = nothing` at `:263`, and document them in the docstring after the `agr_optimizer` paragraph at `:243-247`.

**Guards:** add them inside the guard block at `:265-307`, BEFORE `λ₀vec` at `:308`:
- normalise `flex_market` to a `Vector{FlexMarket}`;
- check `allunique(_flex_row_name.(fms))`;
- throw on `houses !== nothing && flex_market !== nothing` (research Q5, "Houses");
- decide and document what `welfare_optimizer` does with `engine = :admm`. The DADP solve under `:admm` is `solve_admm`, which takes no `optimizer` kwarg, so either throw on that combination or restrict the keyword to the centralized DADP and stage 2.

**DADP passthrough** (`:312-315`). Use the `fit_optimizer` if/else shape (`:658-669`, quoted above) so that `nothing` produces the identical call:
```julia
        ctx, _obj, _dadp =
            solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
```

**Flex rows.** The per-leg body to mirror is the flat/tou leg at `:553-650`:
- price matrix: `uniform_matrix(price_vec)` (`:450-456`), where the price vector comes from `flat_prices(input)` or `tou_prices(input; bins = bins)` (`:555`);
- lossless import: `p_imp = Float64[-sum(nets[i][t] for i in 1:nb) for t in 1:T]` (`:563`);
- ledger: `build_settlement_ledger(P, bus_nets, bus_utils, p_imp, λ₀vec, input.buses; T, source = input.source, ...)` (`:581-591`), plus `flex_payments = rows`;
- bills and surplus at bus granularity: `:597-600`;
- AC check: `ac_feasibility_status(feeder, aggs, [by_bus[a.bus].net for a in aggs]; T = T)` (`:603`). Pass the **original** `aggs`, not `stage2_aggs`, because the reactive draw is read off `agg.Pdc`/`agg.φ` (`feasibility.jl:246-248`);
- rebound against `dadp_nets`, plus per-hour rebound rows: `:604-620`;
- `_summary_row(...)` call: `:621-647`. Set `fairness_total = missing`, as the fit leg does at `:732`;
- welfare: `sum(utils) - sum(λ₀vec[t] * p_imp[t] for t in 1:T)` (`:627`). Here `utils` must be the **delivery** utilities (research Q6).

**Status-only rows** (`infeasible_redispatch`, `inexact_redispatch`, `error:<Type>`) follow the fit error row at `:679-691`:
```julia
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
```
Push this one into the **flex** row vector, not into `summary_rows`, and merge in the additive columns with `missing`.

**Additive columns and the return.** `_rows_to_dataframe` keys its schema on the FIRST row (`:75-89`, specifically `:77`, `ks = propertynames(first(rows))`):
- Build flex rows as `merge(_summary_row(...), (; coordination = ..., baseline_tariff = ..., ...))` in a separate `flex_summary_rows` vector.
- Every flex row, status-only rows included, must carry the identical field set, because `_rows_to_dataframe` uses the first row's keys for all rows.
- The return at `:767-772` becomes the following; leave it unchanged when `flex_market === nothing`:
```julia
    return (
        summary = _rows_to_dataframe(summary_rows),
        household_bills = _rows_to_dataframe(bill_rows),
        equity_breakouts = _rows_to_dataframe(breakout_rows),
        rebound = _rows_to_dataframe(rebound_rows),
    )
```
  For the flex case, add `vcat(base, _rows_to_dataframe(flex_rows); cols = :union)` per table. `DataFrame` is already imported (`:67`); `vcat` with `cols` is a DataFrames method, so no new import is needed. Keep `equity_breakouts` unchanged, since `houses` combined with `flex_market` throws.
- **Do not edit `_summary_row` (`:121-186`) or `_equity_columns` (`:95-116`).**

**Header comment** (`:1-63`): add a "FLEX-MARKET LEGS (opt-in)" paragraph in the style of the SETTLEMENT CONVENTIONS bullets at `:27-57`. It covers delivered energy at the baseline tariff, flex on activated Δ, the lossless welfare convention and the tariff-on-activation overlap.

---

### `src/TSODSO.jl` (modified): include order

**Analog:** the settlement block at `:299-312`, which has a dependency-order comment and one trailing comment per include:
```julia
include("settlement/SettlementLedger.jl")
include("settlement/run_inputs.jl")     # run-output → SettlementInput adapters
include("settlement/tariffs.jl")        # revenue-neutral flat/TOU price construction (pure)
include("settlement/price_taker.jl")    # thin penalty-free counterfactual dispatch QP
include("settlement/feasibility.jl")    # AC-physics feasibility status (report, never throw)
include("settlement/equity.jl")         # Gini/Theil/Atkinson/Palma + breakouts + rebound
include("settlement/comparison.jl")     # compare_tariffs — the SETL-02/05 comparison runner
```
Insert `include("coordination/coordination.jl")` and `include("coordination/flex_market.jl")` between `equity.jl` (`:311`) and `comparison.jl` (`:312`), and extend the block comment at `:299-305` with the reason: `flex_market` uses price_taker, feasibility and `decompose_dlmp`, and `comparison` uses `flex_market`. `dlmp.jl` is included at `:203` and `welfare_solve.jl` at `:152`, both earlier. For a section heading, mirror `:142` (`# --- Actor objectives + portfolios (phase 44) ---`), but read the planning-ID guard note below first. Exports go in the coordination files themselves, not in `TSODSO.jl`. The `@compat public` list at `:314-418` is only for documented-but-unexported names, so add to it only if `FlexBidDevice` or the probe helpers are meant to be public-but-unexported.

---

### `docs/src/api.md` (modified): surface the new docstrings

**Analog:** `docs/src/api.md:91-109` (the Settlement, Tariffs & Equity `@autodocs` block):
````
```@autodocs
Modules = [TSODSO]
Pages = [
    "settlement/SettlementLedger.jl",
    ...
    "settlement/equity.jl",
]
Order = [:type, :constant, :function]
```
````
`docs/make.jl:142` sets `checkdocs = :exports`, so a documented exported symbol that is not surfaced FAILS the docs build (`docs/make.jl:130-141`). Add a "Coordination" section with `Pages = ["coordination/coordination.jl", "coordination/flex_market.jl"]` and keep `:constant` in `Order`. **Caution for the planner:** `actors/*.jl` and `devices/Behavioural.jl` (Phase 44) do not appear in any api.md `Pages` list (`grep -n "actors/\|Behavioural" docs/src/api.md` → no hits). That gap may already break `checkdocs`, and it is not this phase's job to fix; just do not copy it.

---

### `test/test_flex_market_fence.jl` (new): default-path fence, captured BEFORE any `src/` edit

**Analog:** `test/test_actor_default_fence.jl` (whole file, 208 lines).

**Header pattern** (`:1-21`): capture date, Julia version, git HEAD, "`git diff -- src` empty at capture", the 1.12.5-only rationale, the list of version-independent assertions, and the soft-scope rule.

**Digest module:** reuse it rather than copying it. `ActorFenceDigest` is a `@testmodule` (`:23-92`), and testmodules are global to the run, so `setup = [ActorFenceDigest]` works from another file. The fold handles `missing`, strings, arrays and NamedTuples:
```julia
    function fold(h::UInt64, x)::UInt64
        if x isa AbstractFloat
            return (h ⊻ reinterpret(UInt64, Float64(x))) * 0x100000001b3
        ...
        elseif x === nothing || x === missing
            return h * 0x100000001b3
    ...
    digest(x) = fold(0xcbf29ce484222325, x)
```
**DataFrame digest (new helper, defined in the test item):** fold `names(df)` and then each column, for example `foldl((h, c) -> ActorFenceDigest.fold(ActorFenceDigest.fold(h, c), df[!, c]), names(df); init = 0xcbf29ce484222325)`. Do not rely on the struct fallback (`:70-75`) for a `DataFrame`, because it folds internal fields. **Exclude the environment-dependent provenance columns `threads` and `blas_threads`** (`comparison.jl:182-183` stamp `Threads.nthreads()` and `BLAS.get_num_threads()`; the runner's thread count is not pinned). `julia_version` is already covered by the version gate.

**Fixture:** the hermetic 2-bus T = 3 fixture, `test/test_settlement.jl:998-1006`:
```julia
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)
```
Call it with `engine = :centralized, bins = [[1, 2], [3]]`, as at `:1135-1142`. `default_tou_bins` is 24-hour-only (`:991-992`).

**Version-gated single digest assertion** (`test_actor_default_fence.jl:202-207`):
```julia
    if VERSION == ActorFenceDigest.GOLDEN_VERSION
        @test (da2, dw2, da, dw) == (0xc1791cfe86ef6538, ...)
    else
        @test_skip (da2, dw2, da, dw) == (0xc1791cfe86ef6538, ...)
    end
```
Use one tuple of the four DataFrame digests plus the ledger digest, so that a single skip record covers it.

**Version-independent checks** (`:160-193` style: same-process `==`):
- `names(res.summary)` equals the pinned 37-column list. The list is the `_summary_row` field order at `comparison.jl:147-185`, which is also `SUMMARY_COLS` minus `:mode`/`:seed` at `scripts/tariff_comparison.jl:250-290`;
- `res.summary.tariff == ["dadp", "flat", "tou", "fit"]` (`test_settlement.jl:1547`);
- `isequal(default, compare_tariffs(...; flex_market = nothing))` for all four tables. Use `isequal`, not `==`, because of `missing` and `NaN` cells (the dadp row's `rebound_ratio` is NaN by construction, `comparison.jl:54-57`).

**Ledger `nothing ⇒ ==` check:** copy `test/test_actor_settlement.jl:122-137`:
```julia
    l0 = build_settlement_ledger(input)
    l1 = build_settlement_ledger(input; actor_wedges = nothing)
    @test l0.transfers == l1.transfers
    @test l0.balances == l1.balances
    @test l0.merchandising_surplus == l1.merchandising_surplus
    @test l0.wholesale_payment == l1.wholesale_payment
    @test length(l1.transfers) == 2 * (length(input.buses) * F.T + F.T)
```

**`welfare_optimizer` signature-contract items:** copy `test/test_settlement.jl:984-1041` (an explicit factory gives bitwise-equal rows) and `:1043-1089` (explicit `nothing` gives bitwise-equal rows). Switch to `engine = :centralized`. The explicit factory is `select_optimizer(TSODSO.SOCP())`, which is the `solve_welfare` default for `ConvexBranchFlow` (`welfare_solve.jl:123`). The core assertion:
```julia
    row_k = only(filter(r -> r.tariff == "dadp", eachrow(kwargless.summary)))
    row_n = only(filter(r -> r.tariff == "dadp", eachrow(explicit_nothing.summary)))
    @test row_k.status == "ok"
    @test row_n.welfare == row_k.welfare
```

**Item header shape** (`test_actor_default_fence.jl:94-96`):
```julia
@testitem "actor objective: default fence (admm + welfare + canary, byte-identity)" setup =
    [ActorFenceDigest, TwoBusFixtures, IEEE13Fixtures, ExperimentHarnessFixtures] tags =
    [:actors, :fence] begin
```

---

### `test/test_flex_market.jl` (new, fast)

**Analog for the fixture module + measured-tolerance header:** `test/test_actor_settlement.jl:1-110`. The header table at `:10-16` records "observed max / pinned" per quantity, which is the place for the measured tolerances (3× the observed max over 3 seeds):
```julia
# Tolerances (julia 1.12.5, seeds 20260719..21, centralized SOCP at tol 1e-10 ...;
# pinned at 3x the observed max or a numerical-zero floor):
#
#   quantity                                              observed max   pinned
#   balances[(:actor,k)] vs independent sum m*load        0.0            1e-12 (numerical-zero floor)
```
and the `@testmodule` with `const SEEDS`, a `feeder2()` builder and a `cent_opt()` factory (`:19-58`):
```julia
@testmodule ActorSettlementFixtures begin
    using TSODSO
    using TSODSO: SOCP, select_optimizer, SMAX_NO_LIMIT
    const T = 24
    const SEEDS = (20260719, 20260720, 20260721)
    function feeder2()
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)],
            1,
        )
    end
    cent_opt() = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
```
- **Liveness fixture (RESEARCH Pattern 6):** set a finite, tight `smax` on `Branch(1, 2, r, x, smax)` and use `Aggregator(2, 1.0, [Interruptible(2, Pmin, Pmax, a, b)], Pdc)`. The constructor is `Interruptible.jl:116-128`; with φ = 1.0, tanφ = 0.
- **Conservation tests:** copy `test_actor_settlement.jl:154-177`:
```julia
    for seed in F.SEEDS
        r = check(seed)
        @test ledger_residual(r.led) == 0.0
        ...
        nb = length(r.base.transfers)
        @test r.led.transfers[1:nb] == r.base.transfers
        @test r.led.merchandising_surplus == r.base.merchandising_surplus
```
  Wrap the loop body in a function, as `check(seed)` does here; this is the TestItem soft-scope trap. Note that `merchandising_surplus` differs once flex rows exist, so assert `balances[:dso]` against the base minus the flex total instead.
- **V5 guard tests:** copy `test_actor_settlement.jl:298-324`. That item builds rows with the `(; r1..., field = bad)` splat and asserts `@test_throws ArgumentError build([...])` for non-finite values, an unknown bus, a malformed row and an out-of-range `t`.
- **compare_tariffs flex integration** on the hermetic 2-bus: the `test_settlement.jl:1091-1106` fixture plus the `:1546-1548` row-order checks; then assert that rows 1-4 `isequal` the default call.

---

### `test/test_flex_market_ieee.jl` (new, `:slow`)

**IEEE-13 analog:** `test/test_settlement.jl:1526-1584`:
```julia
@testitem "compare-tariffs: IEEE-13 ground four-leg run (centralized, T=24) — statuses populated, no throw" tags =
    [:settlement, :slow] setup = [IEEE13Fixtures] begin
    feeder = ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
    T = IEEE13Fixtures.T
    λ₀ = IEEE13Fixtures.mem_price_profile()
    res = compare_tariffs(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, engine = :centralized)
    ...
        @test r.feasibility_status in ("feasible", "infeasible", "solve_failed")
```
The set-membership assertion on `feasibility_status` is exactly the RESEARCH Pitfall 5 prescription: never assert `feasible`. The FIT row's status set at `:1573-1578` is the precedent for an allowed status set on flex rows (`ok`, `infeasible_redispatch`, `inexact_redispatch`, `error:*`).

**IEEE-123 analog:** `test/test_ieee123_admm.jl:19-61`. Use `setup = [IEEE123Fixtures]`, `tags = [..., :ieee123, :slow]`, `IEEE123Fixtures.build_ieee123_aggregators(feeder)`, `IEEE123Fixtures.ieee123_lambda0()`, and pass the conditioning factory:
```julia
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9),
```
That becomes `welfare_optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)`. The comment at `:48-52` is the documented conditioning rationale to cite. Assert only "a row exists and its status is in the set" (research IEEE-123 (e)).

---

### `test/test_exports.jl` + `test/expected_broken.txt` (modified)

**Exports** (`test/test_exports.jl:4-45`): append the new exported names to the `keep` heredoc on a new line near `:35` (`compare_tariffs`), for example `AbstractCoordination PriceBased FlexMarket`. Add internal names you want asserted reachable (`FlexBidDevice`, `_flex_row_name`) to the `unexported` tuple at `:75-183`, keeping alphabetical order. The `@test exported == keep` at `:49` is exact set equality, so a forgotten name fails both ways.

**Skip record** (`test/expected_broken.txt:24`, format at `:2-14`):
```
skipped | test_actor_default_fence.jl | actor objective: default fence (admm + welfare + canary, byte-identity) | (da2, dw2, da, dw) == (0xc1791cfe86ef6538, 0xd3ba3a3fbb317158, 0x27a82704e86fbdd9, 0x3b8e36e55565b99c) | digest goldens valid only on Julia 1.12.5 (0.x drift on 1.12.7); version-gated, Phase 44 plan 01
```
Add one line: `skipped | test_flex_market_fence.jl | <exact item name> | <exact printed expr> | <reason>`. The 4th field must be `string(orig_expr)` of the `@test_skip` expression, character for character, hex literals included, so write it after the digests are captured.

---

### `scripts/tariff_comparison.jl` (modified): `--flex-market` and `--mode ieee123`

**Analog:** the same file.

- **Header usage/modes block** (`:8-30`): add the `ieee123` mode paragraph and the `--flex-market` flag line, in the style of the `ieee13-ground` and `case-a-784` paragraphs at `:14-29`.
- **Mode parsing** (`:115-123`): extend the allowed tuple and the error message:
```julia
    mode = let m = parse_kv_flag(args, "--mode", "ieee13-ground")
        (m in ("ieee13-ground", "case-a-784")) || throw(
            ArgumentError("--mode must be \"ieee13-ground\" or \"case-a-784\" (got $(repr(m)))"),
        )
        m
    end,
```
  `parse_kv_flag` (`:108-113`) requires a value. A boolean `--flex-market` must be parsed as `("--flex-market" in args)`, or given a value form such as `--flex-market on`.
- **Seed default** (`:146-147`) is a two-way ternary. Extend it with `"ieee123" => 20260719` (`SEED_IEEE123`, `actor_behaviour_sweep.jl:77`).
- **Run + honest outcome** (`ground_main`, `:407-458`). This is the template for `ieee123_main`:
```julia
    wall_s = @elapsed outcome = run_compare_outcome() do
        compare_tariffs(feeder, ConvexBranchFlow(), aggs; T = T_H, λ₀ = λ₀, engine = :centralized)
    end
    ensure_all_schemas()
    if !outcome.ok
        write_run_status_row(outcome, "ieee13-ground", "centralized", T_H, seed)
        ...
        return nothing
    end
    write_compare_results(outcome.res, "ieee13-ground", T_H, seed)
```
  Pass `flex_market = [FlexMarket(...), ...]` only when the flag is set. That keeps the default `ieee13-ground` run identical. Record `flex_wall_s` from `@elapsed` as the research column (or rely on the runner's own column).
- **Upsert:** reuse `write_compare_results` (`:345-370`) and `upsert_row` (`:206-220`, `vcat(keep, new; cols = :union)`) unchanged. New flex columns append after the existing trailing `mode,seed,iters` columns of the committed CSV, whose current header ends `...,t_horizon,mode,seed,iters`. Optionally add the new columns to `SUMMARY_COLS` (`:250-290`). It is only used for header-only creation (`:244-247`).
- **`(run)` refusal row** (`write_run_status_row`, `:379-403`): a `build_population(:default, :ieee123)` DADP refusal under an optional `ieee123-default` mode is recorded by exactly this path. `run_compare_outcome` (`:163-195`) already maps `CertificateError` to `error:CertificateError`.
- **IEEE-123 population:** copy it verbatim from `scripts/actor_behaviour_sweep.jl:73-141`. That copy is itself verbatim from `test/fixtures_ieee123.jl`:
```julia
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)
...
function house(bus; seed, φ, pv_scale = 1.0, load_scale = 1.0, dev_scale = 1.0,
               batt_pmax = 0.5, batt_emax = 2.0, batt_soc0 = 1.0)
    prof = generate_profiles(seed = seed + bus, T = T)
    ...
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end
function ieee123_population()
    return [house(bus; seed = SEED_IEEE123, φ = 0.90, load_scale = LOAD_SCALE_IEEE123, ...) for bus in ieee123_load_nodes()]
end
```
  Add `ieee123_lambda0()` (`:94-97`) and `temperature_profile()` (`:89-92`). **You cannot `include("test/fixtures_ieee123.jl")` from a script:** `@testmodule` expands to a no-op outside TestItemRunner (`scripts/repro_stability_check.jl:19-26`). Cite that note in the copied block's comment. Imports come from `actor_behaviour_sweep.jl:47-57` (`ieee123_load_nodes`, `ieee123_modified`, device types). The feeder is `ieee123_modified()`, and the conditioning is `welfare_optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)` (import `SOCP` and `select_optimizer` from `TSODSO`).

### `scripts/README.md` (modified)

**Analog:** the existing `tariff_comparison.jl` row at `scripts/README.md:52` (a single table row). Extend its Purpose cell (flex-market legs, `--mode ieee123`, `--flex-market`) and its "How to run" cell. No new script file is added, so no new row is needed. `.github/scripts/check_scripts_index.py` only checks that every tracked `scripts/` file is indexed.

### `docs/literate/flex_market.jl` (new) + `docs/make.jl` (modified)

**Primary analog:** `docs/literate/settlement_equity.jl:125-204`. It reads the **same** `results/settlement_comparison/tariff_comparison.csv` with a quote-aware reader. Copy the reader verbatim: the committed `notes` cells contain commas and quotes (see the `fit` row), so the naive `split(ln, ',')` reader of `aggregator_actor.jl:42-50` would misparse it.
```julia
function read_settlement_csv(path)
    function split_line(line)
        cells = String[]
        cur = Char[]
        inq = false
        ...
    end
    lines = readlines(path)
    header = split_line(first(lines))
    return map(lines[2:end]) do ln
        cells = split_line(ln)
        Dict(header[j] => strip(cells[j]) for j in 1:min(length(header), length(cells)))
    end
end
num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
const RESULTS_DIR = joinpath(pkgdir(TSODSO), "results", "settlement_comparison")
summary_rows = read_settlement_csv(joinpath(RESULTS_DIR, "tariff_comparison.csv"))
```
**Narrative analog:** `docs/literate/aggregator_actor.jl`.
- `:1-7`: the page states its source script and that every derived number is recomputed live from the CSV.
- `:30-37`: the "First-welfare-theorem framing (read this before interpreting any number)" paragraph. Mirror it for the uniform = DLMP framing.
- `:84-89` and `:184-197`: `let` blocks that compute and `@printf` derived figures from the rows, never typed by hand. Use this for the welfare gap, PAB vs uniform money and the β overpayment.
- `:217-227`: the refusals section, which lists the non-ok rows.
- `:229-235`: the "Reproduce" section.

**Registration** (`docs/make.jl:19-68`, list; `:94-129`, pages):
- Add `"flex_market.jl",` with a trailing comment next to `"settlement_equity.jl",` (`:59`) or after `"aggregator_actor.jl",` (`:38`).
- Add a nav entry under `"Experiments"` (`:116-121`) next to `"Settlement, Tariffs & Equity" => "generated/settlement_equity.md"`, for example `"Flexibility Market vs Price Coordination" => "generated/flex_market.md"`.

---

## Shared Patterns

### Opt-in keyword with a `nothing` default, never touching the default path
**Sources:** `comparison.jl:261-263,317-331` (the `fit_optimizer`, `agr_optimizer` and `time_limit_s` passthroughs); `SettlementLedger.jl:207,337,429` (`actor_wedges`); `welfare_solve.jl:137-139` (`actors`).
**Apply to:** `flex_market`, `welfare_optimizer` and `flex_payments`. Every new branch is guarded `if x !== nothing`. When the callee has a non-`nothing` default, use the if/else call shape (`comparison.jl:658-669`), never `optimizer = x`.

### Honesty policy: errors become status rows
**Sources:** `comparison.jl:657-691` (in-runner), `scripts/tariff_comparison.jl:163-195` (script-level `(run)` row), `price_taker.jl:132-141` (certificate becomes a recorded symbol).
**Apply to:** stage 2, probes, delivery, and the ieee123 mode. Catch by TYPE and `rethrow()` everything else. Truncate notes with `first(string(err.msg), 400)`, and flatten them in the script with `flatten_note` (`tariff_comparison.jl:234`).

### Fail-loud input validation (V5)
**Sources:** `SettlementLedger.jl:132-144` (`_finite_or_throw`), `:336-369`; `Behavioural.jl:65-82`; `Interruptible.jl:68-94`.
**Apply to:** `FlexMarket` kwargs, the `FlexBidDevice` constructor, `flex_payments` rows, and `compare_tariffs` guards. Always `throw(ArgumentError("<fn>: <what> ..."))` with the function name as the prefix; never `@assert`.

### Solver factory only
**Sources:** `price_taker.jl:101` (`Model(select_optimizer(QP()))`), `welfare_solve.jl:123,161`.
**Apply to:** probe, delivery and stage 2. No model names Clarabel.

### TestItem hygiene
**Sources:** `test_actor_default_fence.jl:21` ("accumulators live inside functions"); `test_actor_settlement.jl:145-156` (`check(seed)` function, then a loop over the results); memory notes `testitem-try-scoping-trap` and `gsd-plan-verify-testitemrunner-trap`.
**Apply to:** all three new test files. Use `x = try ... catch; nothing end`, never `try x = ...`. Tag IEEE items `:slow`. Verify with `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'`, then `git checkout -- test/Project.toml test/Manifest.toml`.

### Planning-ID guard (copy comments with care)
**Source:** `.github/scripts/check_planning_ids.py` (it already fails on main with 355 hits; Phase 45 must not add more).
**Apply to:** every new or edited line in `src/`, `test/`, `scripts/` and `docs/literate/`. **The analogs above are full of tokens that must NOT be copied into new lines:** `Phase 44`, `ACTOR-02`, `SETL-02/05`, `phase 44`, `T-41-19`, `byte-identical`, `bit-identical`, `44-06`, `41-03`. Use neutral wording such as "the default path is unchanged", "opt-in", or "flexibility-market legs". Item names and the `expected_broken.txt` reason field fall under the same rule: the existing record at `expected_broken.txt:24` says "Phase 44 plan 01", so do not copy that phrasing.

## No Analog Found

| File / sub-pattern | Role | Data Flow | Reason → use RESEARCH.md |
|---|---|---|---|
| `flex_market.jl`: probe mutation loop (`fix`/`unfix`, range LPs, secant prices) | service | build once, re-solve | No existing code mutates a price-taker model with `fix`. Use RESEARCH "Code Examples / Fixed-net probe" (`:565-580`) on top of the `price_taker.jl:100-108` build. |
| `flex_market.jl`: PAV monotone repair + range floor 1e-6 | utility | transform | No isotonic-regression helper in `src/`. Pure arithmetic per RESEARCH Pattern 1 (`:309`); report `bid_repair_max`. |
| `flex_market.jl`: L1 exact-penalty tracking | service | request-response | Closest is the `Rebound` auxiliary-variable constraint at `Behavioural.jl:209-211`; the weight rule comes from RESEARCH Pattern 3 (`:369-374`). |
| `flex_market.jl`: congested-hour classifier + β phantom rows | utility | transform | `decompose_dlmp` supplies the inputs; the threshold rule is RESEARCH Q8 (`:472-478`). |

## Metadata

**Analog search scope:** `src/devices/`, `src/actors/`, `src/settlement/`, `src/models/welfare_solve.jl`, `src/pricing/dlmp.jl`, `src/core/errors.jl`, `src/TSODSO.jl`, `test/` (fence, settlement, actor settlement, ieee123 admm, exports, expected_broken), `scripts/` (`tariff_comparison`, `actor_behaviour_sweep`, `repro_stability_check`, README), `docs/` (`make.jl`, `src/api.md`, `literate/aggregator_actor.jl`, `literate/settlement_equity.jl`), and the committed `results/settlement_comparison/tariff_comparison.csv` header.
**Files scanned:** 30
**Pattern extraction date:** 2026-11-04
