# src/experiments/Scenario.jl
#
# SEAM: Scenario — the immutable declarative scenario spec (EXP-01), restructured in Phase 32
# (ARCH-01/ARCH-02) around a primitive `pf::Symbol` power-flow selector and a
# `strategy::AbstractStrategy` field (strategies.jl) instead of one flat bag of strategy knobs.
#
# Every field except `strategy` is a PRIMITIVE selector (Symbol/Int/Float64/Bool/String), so the
# heavy objects (feeder, λ₀, aggregators, power-flow formulation) are materialized later,
# deterministically, by `src/experiments/materialize.jl` from these selectors + the master
# `seed`. `strategy` is a struct-valued field: DrWatson's `savename` silently DROPS it (it is
# outside `default_allowed`), so on-disk filename identity is restored by `scenario_filename`
# (store.jl), which flattens the strategy. Never use a bare `savename(s, ...)` as an on-disk
# identity key; every storage call site must also pass `digits = 10` and `safe = true`
# (CR-01: default `sigdigits = 3` float rounding can collapse sub-percent-different floats).
#
# Validation is a CONSTRUCTION invariant (mirrors `Thermostatic`/`PVBattery`/`Aggregator`):
# an explicit inner constructor `throw`s `ArgumentError` (never `@assert`, threat T-03-04
# convention), so a `Scenario` can never silently underdetermine a run (threat T-08-05).
# Strategy-knob validation lives in the strategy constructors (strategies.jl).

"""
Valid `feeder` selectors a `Scenario` may name (dispatch target: `build_feeder`, materialize.jl).
"""
const SCENARIO_VALID_FEEDERS = (:ieee13, :ieee123)

"""
Legacy `strategy` selector symbols accepted by the `Scenario` outer keyword constructor. Each
maps to a strategy struct (`:centralized` → `Centralized`, `:admm` → `ADMM`, `:mpc` → `MPC`,
`:stochastic` → `Stochastic`) via `_resolve_strategy`.
"""
const SCENARIO_VALID_STRATEGIES = (:centralized, :admm, :mpc, :stochastic)

"""
Valid `pf` (power-flow formulation) selectors a `Scenario` may name (dispatch target:
`build_powerflow`, materialize.jl). `MeshedFlow` and `DCPowerFlow` are intentionally NOT
selectable (Phase 32 CONTEXT).
"""
const SCENARIO_VALID_PFS = (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)

"""
Valid `price` selectors a `Scenario` may name (dispatch target: `build_price`, materialize.jl).
"""
const SCENARIO_VALID_PRICES = (:mem,)

"""
Valid `population` selectors a `Scenario` may name (dispatch target: `build_population`, materialize.jl).
"""
const SCENARIO_VALID_POPULATIONS = (:default,)

"""
    Scenario

An immutable declarative experiment specification (EXP-01). Selectors are primitives; the
solve strategy is a strategy struct (see [`AbstractStrategy`](@ref)).

# Fields

  - `name::String` — human label (REQUIRED keyword).
  - `feeder::Symbol = :ieee13` — one of `$(SCENARIO_VALID_FEEDERS)` (dispatches `build_feeder`).
  - `seed::Int = 1` — master seed (sub-seeds derived via `sub_seed`).
  - `T::Int = 24` — day-ahead horizon length (hours).
  - `population::Symbol = :default` — one of `$(SCENARIO_VALID_POPULATIONS)`.
  - `price::Symbol = :mem` — one of `$(SCENARIO_VALID_PRICES)`.
  - `allow_export::Bool = true` — whether the frontier allows priced export.
  - `pf::Symbol = :convex_branch_flow` — power-flow formulation, one of `$(SCENARIO_VALID_PFS)`
    (dispatches `build_powerflow`).
  - `pf_thesis_literal::Bool = false` — option of `:convex_branch_flow` only.
  - `pf_ε::Float64 = 0.0` — option of `:restricted_branch_flow` only (finite, `≥ 0`).
  - `strategy::AbstractStrategy = Centralized()` — solve strategy.

# `pf` selector and strategy compatibility

| `pf`                      | option             | Centralized | ADMM / MPC / Stochastic |
|:--------------------------|:-------------------|:-----------:|:-----------------------:|
| `:convex_branch_flow`     | `pf_thesis_literal`| yes         | only with `pf_thesis_literal = false` |
| `:restricted_branch_flow` | `pf_ε`             | yes         | no                      |
| `:lindistflow`            | —                  | yes         | no                      |
| `:ac`                     | —                  | yes         | no                      |

# Legacy flat keyword mapping

The keyword constructor still accepts `strategy::Symbol` plus flat knobs and maps them to the
strategy struct:

| `strategy`    | accepted knobs                                                                  |
|:--------------|:--------------------------------------------------------------------------------|
| `:centralized`| none                                                                            |
| `:admm`       | `ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ`                                          |
| `:mpc`        | `mpc_H → H`, `mpc_step → step`, `mpc_terminal_soc → terminal_soc`, `mpc_forecast_error → forecast_error` |
| `:stochastic` | `stoch_S → S`, `stoch_probabilities → probabilities`, `stoch_H_oos → H_oos`     |

A knob foreign to the chosen strategy, an unknown keyword, or any knob combined with an
`AbstractStrategy` value throws `ArgumentError` (knobs are detected by the keys actually
supplied, never by comparing against defaults).

# Construction errors

`ArgumentError` on: unknown `feeder`/`price`/`population`/`pf`/strategy selector; `T < 1` or
`seed < 1`; `pf_ε` not finite and `≥ 0`; a `pf_*` option foreign to the chosen `pf`; a strategy x
`pf` combination rejected by `supports_pf`; any invalid strategy knob. The foreign-`pf_*` checks
are judged against the neutral defaults (`pf_ε != 0.0`, `pf_thesis_literal == true`) because the
inner constructor cannot see which keywords were supplied.

`savename` silently drops the struct-valued `strategy` field; the on-disk filename flattening of
`strategy` is `scenario_filename`'s job (store.jl).
"""
struct Scenario
    name::String
    feeder::Symbol
    seed::Int
    T::Int
    population::Symbol
    price::Symbol
    allow_export::Bool
    pf::Symbol
    pf_thesis_literal::Bool
    pf_ε::Float64
    strategy::AbstractStrategy

    function Scenario(
        name::String,
        feeder::Symbol,
        seed::Int,
        T::Int,
        population::Symbol,
        price::Symbol,
        allow_export::Bool,
        pf::Symbol,
        pf_thesis_literal::Bool,
        pf_ε::Float64,
        strategy::AbstractStrategy,
    )
        if feeder ∉ SCENARIO_VALID_FEEDERS
            throw(
                ArgumentError(
                    "Scenario: unknown feeder selector $(repr(feeder)); expected one of " *
                    "$(SCENARIO_VALID_FEEDERS)",
                ),
            )
        end
        if price ∉ SCENARIO_VALID_PRICES
            throw(
                ArgumentError(
                    "Scenario: unknown price selector $(repr(price)); expected one of " *
                    "$(SCENARIO_VALID_PRICES)",
                ),
            )
        end
        if population ∉ SCENARIO_VALID_POPULATIONS
            throw(
                ArgumentError(
                    "Scenario: unknown population selector $(repr(population)); expected one " *
                    "of $(SCENARIO_VALID_POPULATIONS)",
                ),
            )
        end
        if T < 1
            throw(ArgumentError("Scenario: T must be ≥ 1 (day-ahead horizon); got T=$T"))
        end
        if seed < 1
            throw(
                ArgumentError(
                    "Scenario: seed must be ≥ 1 (a sane master-seed range); got seed=$seed",
                ),
            )
        end
        if pf ∉ SCENARIO_VALID_PFS
            throw(
                ArgumentError(
                    "Scenario: unknown pf selector $(repr(pf)); expected one of " *
                    "$(SCENARIO_VALID_PFS)",
                ),
            )
        end
        if !(isfinite(pf_ε) && pf_ε >= 0)
            throw(ArgumentError("Scenario: pf_ε must be finite and ≥ 0; got pf_ε=$pf_ε"))
        end
        if pf_ε != 0.0 && pf !== :restricted_branch_flow
            throw(
                ArgumentError(
                    "Scenario: pf_ε is an option of pf = :restricted_branch_flow only; got " *
                    "pf=$(repr(pf)), pf_ε=$pf_ε",
                ),
            )
        end
        if pf_thesis_literal && pf !== :convex_branch_flow
            throw(
                ArgumentError(
                    "Scenario: pf_thesis_literal is an option of pf = :convex_branch_flow " *
                    "only; got pf=$(repr(pf))",
                ),
            )
        end
        if !supports_pf(strategy, pf, pf_thesis_literal)
            lit = pf_thesis_literal ? " (pf_thesis_literal = true)" : ""
            throw(
                ArgumentError(
                    "Scenario: strategy $(nameof(typeof(strategy))) does not support " *
                    "pf=$(repr(pf))$lit; supported pf selectors: $(supported_pfs(strategy))",
                ),
            )
        end
        pf_ε = pf_ε + 0.0   # normalize -0.0 -> +0.0 so `==` and `hash` agree
        return new(
            name,
            feeder,
            seed,
            T,
            population,
            price,
            allow_export,
            pf,
            pf_thesis_literal,
            pf_ε,
            strategy,
        )
    end
end

# Knob name (legacy flat kwarg) -> strategy-constructor kwarg, per strategy symbol.
const _LEGACY_KNOBS = Dict{Symbol,Dict{Symbol,Symbol}}(
    :centralized => Dict{Symbol,Symbol}(),
    :admm => Dict{Symbol,Symbol}(
        :ρ => :ρ,
        :ε_abs => :ε_abs,
        :ε_rel => :ε_rel,
        :maxiter => :maxiter,
        :τ_ratio => :τ_ratio,
        :μ => :μ,
    ),
    :mpc => Dict{Symbol,Symbol}(
        :mpc_H => :H,
        :mpc_step => :step,
        :mpc_terminal_soc => :terminal_soc,
        :mpc_forecast_error => :forecast_error,
    ),
    :stochastic => Dict{Symbol,Symbol}(
        :stoch_S => :S,
        :stoch_probabilities => :probabilities,
        :stoch_H_oos => :H_oos,
    ),
)

"""
    _resolve_strategy(strategy, knobs) -> AbstractStrategy

Map the `strategy` keyword (a legacy `Symbol` or an `AbstractStrategy` value) plus the flat
legacy `knobs` (a `Base.Pairs` of the supplied extra keywords) to a strategy struct. Knobs are
detected from the supplied keys only. Throws `ArgumentError` for contradictory, foreign or
unknown knobs and for an unknown strategy symbol.
"""
function _resolve_strategy(strategy::AbstractStrategy, knobs)
    if !isempty(knobs)
        throw(
            ArgumentError(
                "Scenario: strategy knobs $(collect(keys(knobs))) were passed together with " *
                "an explicit strategy value $(nameof(typeof(strategy)))(...); set the knobs " *
                "on the strategy struct instead",
            ),
        )
    end
    return strategy
end

function _resolve_strategy(strategy::Symbol, knobs)
    if strategy ∉ SCENARIO_VALID_STRATEGIES
        throw(
            ArgumentError(
                "Scenario: unknown strategy selector $(repr(strategy)); expected one of " *
                "$(SCENARIO_VALID_STRATEGIES)",
            ),
        )
    end
    allowed = _LEGACY_KNOBS[strategy]
    mapped = Dict{Symbol,Any}()
    for (k, v) in pairs(knobs)
        if haskey(allowed, k)
            mapped[allowed[k]] = v
        else
            owner = nothing
            for (st, tbl) in _LEGACY_KNOBS
                haskey(tbl, k) && (owner = st)
            end
            if owner === nothing
                throw(ArgumentError("Scenario: unknown keyword argument $(repr(k))"))
            else
                throw(
                    ArgumentError(
                        "Scenario: keyword $(repr(k)) belongs to strategy " *
                        "$(repr(owner)) and is foreign to strategy=$(repr(strategy))",
                    ),
                )
            end
        end
    end
    kw = (; mapped...)
    if strategy === :centralized
        return Centralized()
    elseif strategy === :admm
        return ADMM(; kw...)
    elseif strategy === :mpc
        return MPC(; kw...)
    else
        return Stochastic(; kw...)
    end
end

function Scenario(;
    name::String,
    feeder::Symbol = :ieee13,
    strategy::Union{Symbol,AbstractStrategy} = Centralized(),
    seed::Integer = 1,
    T::Integer = 24,
    population::Symbol = :default,
    price::Symbol = :mem,
    allow_export::Bool = true,
    pf::Symbol = :convex_branch_flow,
    pf_thesis_literal::Bool = false,
    pf_ε::Real = 0.0,
    knobs...,
)
    st = _resolve_strategy(strategy, knobs)
    return Scenario(
        name,
        feeder,
        Int(seed),
        Int(T),
        population,
        price,
        allow_export,
        pf,
        pf_thesis_literal,
        Float64(pf_ε),
        st,
    )
end

"""
    with_strategy(s::Scenario, st::AbstractStrategy) -> Scenario

Rebuild `s` with strategy `st` through the inner constructor, so the strategy x `pf`
compatibility is re-validated. Used by `TSODSO.run(st, s)` when `st` differs from `s.strategy`,
so `result.scenario` is accurate.
"""
function with_strategy(s::Scenario, st::AbstractStrategy)
    return Scenario(
        s.name,
        s.feeder,
        s.seed,
        s.T,
        s.population,
        s.price,
        s.allow_export,
        s.pf,
        s.pf_thesis_literal,
        s.pf_ε,
        st,
    )
end

# Value semantics over every field (incl. the strategy).
function Base.:(==)(a::Scenario, b::Scenario)
    return a.name == b.name && a.feeder == b.feeder && a.seed == b.seed && a.T == b.T &&
           a.population == b.population && a.price == b.price &&
           a.allow_export == b.allow_export && a.pf == b.pf &&
           a.pf_thesis_literal == b.pf_thesis_literal && a.pf_ε == b.pf_ε &&
           a.strategy == b.strategy
end

function Base.hash(s::Scenario, h::UInt)
    return hash(
        (
            s.name, s.feeder, s.seed, s.T, s.population, s.price, s.allow_export, s.pf,
            s.pf_thesis_literal, s.pf_ε, s.strategy,
        ),
        hash(:Scenario, h),
    )
end

export Scenario
