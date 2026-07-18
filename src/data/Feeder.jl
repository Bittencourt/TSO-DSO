# src/data/Feeder.jl
#
# SEAM: immutable, JuMP-free feeder data model (DATA-01).
# OWNER: plan 01-02.
#
# When filled, this file will provide the concretely-typed parametrized structs
# `Bus{T}`, `Branch{T}`, and `Feeder{T}` (per-unit numbers only), with the outer
# `Feeder(...)` constructor running radial validation (see data/topology.jl) as a
# construction invariant. It declares its own exports when implemented.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
