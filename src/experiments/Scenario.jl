# src/experiments/Scenario.jl
#
# SEAM: Scenario — the immutable, primitive-selector declarative scenario spec (EXP-01).
# OWNER: plan 08-01 (this plan) wires this STUB into the include graph; plan 08-02 FILLS it.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 2. Plan 08-02 fills:
#
#     Base.@kwdef struct Scenario
#         name::String
#         feeder::Symbol      = :ieee13      # :ieee13 | :ieee123
#         strategy::Symbol    = :centralized # :centralized | :admm
#         seed::Int           = 1
#         T::Int              = 24
#         population::Symbol  = :default
#         price::Symbol       = :mem
#         allow_export::Bool  = true
#         ρ::Float64          = 1.0          # ADMM-only knobs, kept in the one flat schema
#         ε_abs::Float64      = 1e-4
#         ε_rel::Float64      = 1e-3
#         maxiter::Int        = 200
#         τ_ratio::Float64    = 2.0
#         μ::Float64          = 10.0
#     end
#
# EVERY field a primitive selector (Symbol/Int/Float64/Bool/String) — never a built Feeder /
# Vector{Aggregator} / λ₀::Vector — so `savename(s)` works with ZERO DrWatson.default_allowed
# overloading (RESEARCH Pitfall 1). An inner validation throws ArgumentError on any unknown
# feeder/strategy/price/population selector or out-of-range T/seed/maxiter, so a Scenario
# never silently underdetermines a run.
#
# Filled by plan 08-02 (EXP-01 / INFRA-04 — RESEARCH §Pattern 1: Declarative selectors →
# deterministic materialization).
