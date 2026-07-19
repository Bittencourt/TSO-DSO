# src/experiments/materialize.jl
#
# SEAM: deterministic selector → object materialization (EXP-01 / INFRA-04).
# OWNER: plan 08-01 (this plan) wires this STUB into the include graph; plan 08-02 FILLS it.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 2. Plan 08-02 fills:
#
#     sub_seed(master::Integer, tag::Symbol) -> Int
#     build_feeder(sym::Symbol) -> Feeder{Float64}
#     build_price(sym::Symbol, T::Int, profiles) -> Vector{Float64}
#     build_population(sym::Symbol, feeder, profiles, seed::Integer) -> Vector{<:Aggregator}
#
# `sub_seed` derives INDEPENDENT deterministic sub-streams from the Scenario's master seed
# (`hash((master, tag)) % typemax(UInt32) |> Int`, RESEARCH Pitfall 5) so `:profiles` and
# `:population` never accidentally couple or collide. The three `build_*` functions
# deterministically reconstruct the heavy Phase 1–7 objects (feeder, λ₀, aggregators) from
# Scenario selectors + a seed, reusing `ieee13_modified`/`ieee123_modified`/`generate_profiles`/
# `Aggregator` verbatim and threading a `StableRNGs.LehmerRNG` into any stochastic construction
# — NEVER the global RNG. Each throws `ArgumentError` on an unknown selector.
#
# Filled by plan 08-02 (EXP-01 / INFRA-04 — RESEARCH §Pitfall 5 / §Pattern 1 materialize block).
