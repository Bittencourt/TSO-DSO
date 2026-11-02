# src/actors/actor_objective.jl
#
# SEAM: the per-actor objective hierarchy (Phase 44, ACTOR-01). An aggregator "actor" is NOT a
# new kind of solver: it is a *weighted objective inside the same price-taking equilibrium*.
# The objective type decides (a) how the AGR-OPT objective is assembled (`agr_objective`),
# (b) what per-iteration linear term must ride along the ADMM price update (`agr_linear_offset`)
# and (c) what term enters the centralized welfare objective (`wedge_term`).
#
# SIGN CONVENTION. `pag` is the aggregator's net INJECTION (load negative). The AGR-OPT linear
# coefficient on `pag[t]` is `-λ_int[t] - ρ·c[t]` (λ_int = -DADP). A retail margin `m_t` adds
# `+m_t` to that coefficient, i.e. the aggregator's profit is `-Σ_t m_t·pag_t = Σ_t m_t·load_t`
# (positive on net load). The same `m_t` also applies to net EXPORT (a symmetric additive
# tariff offset, assumption A6); it is not a strategic aggregator (no market power, no
# Stackelberg game).
#
# WHY A SEPARATE `linear_offset` (RESEARCH Pitfall 1): `solve_agr!` rewrites the `pag`
# coefficient with `set_objective_coefficient` every ADMM iteration, which would silently
# overwrite any margin baked into the objective expression. The margin is therefore stored on
# `AgrOpt.linear_offset` and re-added inside that update.

"""
    AbstractActorObjective

Supertype of per-actor objectives (see [`WelfareObjective`](@ref), [`ProfitObjective`](@ref)).
"""
abstract type AbstractActorObjective end

"""
    WelfareObjective()

The default objective: the aggregator maximizes its own utility net of the price terms (thesis
3.46), exactly the pre-phase-44 behaviour. The default path is byte-identical.
"""
struct WelfareObjective <: AbstractActorObjective end

"""
    ProfitObjective(wedge)

Retail-margin objective. `wedge` is a finite scalar or a per-hour vector `m_t` (price units of
`λ₀`), added to the AGR-OPT linear coefficient on `pag[t]` (`-λ - ρc + m_t`). This is a weighted
objective inside the same price-taking equilibrium, with a symmetric additive tariff offset also
applied to exports (assumption A6); it is NOT a strategic aggregator. `ProfitObjective(0)` is
NOT the default objective (`is_default_objective` is `false`); a zero wedge is never
short-circuited. Non-finite wedge values throw `ArgumentError`.
"""
struct ProfitObjective{M <: Union{Real, AbstractVector{<:Real}}} <: AbstractActorObjective
    wedge::M
    function ProfitObjective(wedge::M) where {M <: Union{Real, AbstractVector{<:Real}}}
        all(isfinite, wedge) ||
            throw(ArgumentError("ProfitObjective: wedge must be finite, got $(wedge)"))
        return new{M}(wedge)
    end
end

# Expand a wedge to a Float64 vector of length T (scalar -> fill; vector length must equal T).
function _wedge_vec(obj::ProfitObjective, T::Integer)
    w = obj.wedge
    if w isa Real
        return fill(Float64(w), T)
    end
    length(w) == T || throw(
        ArgumentError("ProfitObjective: wedge has length $(length(w)), expected T=$T"),
    )
    return Float64.(collect(w))
end

"""
    agr_objective(obj, U, pag, T)

The utility part of the AGR-OPT objective. For both shipped objectives this is `U` itself
(`===`): the margin never enters the built expression (it rides `agr_linear_offset`).
"""
agr_objective(::AbstractActorObjective, U, pag, T) = U

"""
    agr_linear_offset(obj, T) -> Union{Nothing, Vector{Float64}}

Per-hour linear term added to the `pag` coefficient at every `solve_agr!`. `nothing` for
[`WelfareObjective`](@ref) (no extra float operation on the default path).
"""
agr_linear_offset(::WelfareObjective, T) = nothing
agr_linear_offset(obj::ProfitObjective, T) = _wedge_vec(obj, T)

"""
    wedge_term(obj, net, T)

Centralized-objective hook: `nothing` for welfare; `Σ_t m_t·net[t]` for a profit objective, where
`net` is the aggregator's net injection (so profit enters as `-wedge_term` on load).
"""
wedge_term(::WelfareObjective, net, T) = nothing
function wedge_term(obj::ProfitObjective, net, T)
    length(net) == T ||
        throw(ArgumentError("wedge_term: net has length $(length(net)), expected T=$T"))
    m = _wedge_vec(obj, T)
    return sum(m[t] * net[t] for t in 1:T)
end

"""
    is_default_objective(obj) -> Bool

`true` only for [`WelfareObjective`](@ref). `ProfitObjective(0)` is deliberately NOT default.
"""
is_default_objective(::AbstractActorObjective) = false
is_default_objective(::WelfareObjective) = true

export AbstractActorObjective, WelfareObjective, ProfitObjective
