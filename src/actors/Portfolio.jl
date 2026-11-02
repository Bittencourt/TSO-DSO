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

"""
    SlotTable

The consensus axis of the slot ADMM branch (Phase 44, ACTOR-03): one ADMM coupling pair per
SLOT keyed by (actor, bus) instead of one per load node. Fields: `ids` (ascending slot ids),
`bus` (slot -> feeder bus), `actor` (slot -> portfolio index), `site` (slot -> index into the
flat aggregator vector). Built by `build_slot_table`; internal (unexported).
"""
struct SlotTable
    ids::Vector{Int}
    bus::Dict{Int, Int}
    actor::Dict{Int, Int}
    site::Dict{Int, Int}
end

"""
    build_slot_table(site_buses, site_actor, N) -> SlotTable

Deterministic slot ids. Sites are visited in portfolio-then-positional order
(`sort(eachindex(site_buses); by = i -> (site_actor[i], i))`); the FIRST site at a bus gets slot
id = bus, the k-th further site at the same bus gets `N + k` (k counted over the whole table, in
visiting order). When every site sits on its own bus the ids are the buses ascending, i.e. the
legacy `load_nodes`. `ArgumentError` on mismatched lengths or a bus outside `1:N`.
"""
function build_slot_table(
    site_buses::AbstractVector{<:Integer},
    site_actor::AbstractVector{<:Integer},
    N::Integer,
)
    length(site_buses) == length(site_actor) || throw(
        ArgumentError(
            "build_slot_table: $(length(site_buses)) site buses vs $(length(site_actor)) site actors",
        ),
    )
    for (i, b) in enumerate(site_buses)
        1 <= b <= N ||
            throw(ArgumentError("build_slot_table: site $i bus=$b is outside feeder buses 1:$N"))
    end
    bus = Dict{Int, Int}()
    actor = Dict{Int, Int}()
    site = Dict{Int, Int}()
    taken = Set{Int}()
    extra = 0
    for i in sort(collect(eachindex(site_buses)); by = i -> (site_actor[i], i))
        b = Int(site_buses[i])
        id = if b in taken
            extra += 1
            Int(N) + extra
        else
            push!(taken, b)
            b
        end
        bus[id] = b
        actor[id] = Int(site_actor[i])
        site[id] = i
    end
    return SlotTable(sort!(collect(keys(bus))), bus, actor, site)
end

export Portfolio
