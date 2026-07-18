"""
    TSODSO

Walking-skeleton chassis for the TSO–DSO Integration Optimization Framework.

This top module ONLY wires the include graph of the architectural seams, in
dependency order. Each seam file is created empty (comment-only) in plan 01-01
and filled by exactly one later plan, which declares that seam's own `export`s.
`TSODSO.jl` itself exports nothing — it is the assembly point, never a shared
edit surface, so Waves 2–3 fill stubs without ever touching this file.
"""
module TSODSO

# --- Units (owned by plan 01-02, INFRA-05) ---
include("units/PerUnit.jl")

# --- Data model (owned by plan 01-02, DATA-01 / DATA-02) ---
include("data/Feeder.jl")
include("data/topology.jl")

# --- Solver abstraction (owned by plan 01-03, INFRA-02) ---
include("solver/ProblemClass.jl")
include("solver/factory.jl")

# --- Core (owned by plan 01-03, PF-01 residual seam / INFRA-03 status) ---
include("core/ModelContext.jl")
include("core/status.jl")

# --- Power-flow interface (owned by plan 01-03, PF-01) ---
include("powerflow/AbstractPowerFlow.jl")

# --- Models (owned by plan 01-04, rung 0 integration) ---
include("models/toy_dc.jl")

end # module TSODSO
