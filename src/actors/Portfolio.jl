# src/actors/Portfolio.jl
#
# SEAM: grouping of single-bus site `Aggregator`s into an actor (Phase 44, ACTOR-01).
# A `Portfolio` carries ONE objective for all its sites (no per-site override). It is named
# `Portfolio`, not `Actor`, because `const Actor` already exists in
# src/settlement/SettlementLedger.jl.

"""
    Portfolio(sites::Vector{Aggregator}; objective = WelfareObjective(), name = :portfolio)
    Portfolio(sites...; objective, name)

A group of site aggregators sharing one [`AbstractActorObjective`](@ref). Throws `ArgumentError`
on an empty portfolio or a site listed twice (identity, `===`).
"""
struct Portfolio
    sites::Vector{Aggregator}
    objective::AbstractActorObjective
    name::Symbol
    function Portfolio(
        sites::AbstractVector{<:Aggregator};
        objective::AbstractActorObjective = WelfareObjective(),
        name::Symbol = :portfolio,
    )
        isempty(sites) && throw(ArgumentError("Portfolio $(name): sites must be non-empty"))
        for i in eachindex(sites), j in (i + 1):lastindex(sites)
            sites[i] === sites[j] &&
                throw(ArgumentError("Portfolio $(name): the same site appears twice"))
        end
        return new(Vector{Aggregator}(sites), objective, name)
    end
end
Portfolio(sites::Aggregator...; kw...) = Portfolio(collect(Aggregator, sites); kw...)

_find_site(aggregators, s) = findfirst(a -> a === s, aggregators)

"""
    _expand_actors(portfolios, aggregators) -> (; site_actor, site_objective)

Validate exact one-to-one membership (by `===`) between `portfolios` and `aggregators` and
return, aligned with the POSITIONAL order of `aggregators`, the portfolio index and objective of
each site.
"""
function _expand_actors(
    portfolios::AbstractVector{Portfolio},
    aggregators::AbstractVector{<:Aggregator},
)
    n = length(aggregators)
    site_actor = zeros(Int, n)
    site_objective = Vector{AbstractActorObjective}(undef, n)
    for (k, p) in enumerate(portfolios), s in p.sites
        i = _find_site(aggregators, s)
        i === nothing && throw(
            ArgumentError("Portfolio $(p.name): a site is not among the given aggregators"),
        )
        site_actor[i] == 0 || throw(
            ArgumentError("Portfolio $(p.name): a site already belongs to another portfolio"),
        )
        site_actor[i] = k
        site_objective[i] = p.objective
    end
    all(!iszero, site_actor) ||
        throw(ArgumentError("_expand_actors: an aggregator belongs to no Portfolio"))
    return (; site_actor, site_objective)
end

export Portfolio
