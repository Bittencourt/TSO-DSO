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

# --- Seeded profile generator (owned by plan 03-02, DATA-04) ---
include("data/profiles.jl")

# --- Modified IEEE 13-node feeder fixture (owned by plan 04-03, DATA-03) ---
include("data/ieee13.jl")

# --- Solver abstraction (owned by plan 01-03, INFRA-02) ---
include("solver/ProblemClass.jl")
include("solver/factory.jl")

# --- Core (owned by plan 01-03, PF-01 residual seam / INFRA-03 status) ---
include("core/ModelContext.jl")
include("core/status.jl")

# --- Power-flow interface (owned by plan 01-03, PF-01) ---
include("powerflow/AbstractPowerFlow.jl")

# --- Power-flow formulations (owned by plan 02-02, PF-02) ---
include("powerflow/DCPowerFlow.jl")
include("powerflow/LinDistFlow.jl")

# --- SOCP Convex Branch Flow formulation (owned by plan 04-02, PF-03) ---
include("powerflow/ConvexBranchFlow.jl")

# --- Power-flow → problem-class routing trait (owned by plan 04-01, INFRA-02 / PF-03) ---
# Included AFTER the powerflow formulations (needs `AbstractPowerFlow`) and after
# solver/ProblemClass.jl (needs `QP`): it maps a formulation to its solver problem class.
include("solver/problem_class_trait.jl")

# --- Devices (owned by plan 02-03, DEV-03) ---
include("devices/AbstractDevice.jl")
include("devices/Interruptible.jl")

# --- Concrete prosumer devices (owned by plans 03-03 / 03-04) ---
include("devices/Thermostatic.jl")   # DEV-01
include("devices/Deferrable.jl")     # DEV-02
include("devices/PVBattery.jl")      # DEV-04

# --- Aggregator roll-up: the network-facing residual writer (plan 03-05, DEV-05) ---
include("devices/Aggregator.jl")

# --- Models (owned by plan 01-04 rung 0 / plan 02-04 rung 1 integration) ---
include("models/toy_dc.jl")
include("models/linear_solve.jl")

# --- GLB-CVX centralized social-welfare solve (owned by plan 03-05, OPT-01) ---
include("models/welfare_solve.jl")

# --- SOCP relaxation exactness gate (owned by plan 04-05, PF-04) ---
include("models/exactness.jl")

# --- operational_oracle + SEAM-01 extension stubs (owned by plan 04-04, OPT-03 / SEAM-01) ---
include("models/oracle.jl")

# --- Distribution pricing: DLMP decomposition, FIT baseline, checks, welfare accounting ---
# Wired empty (comment-only) in plan 05-01, AFTER models/oracle.jl (each consumes a solved
# ctx / the operational oracle). Dependency order: dlmp → fit → checks → welfare. Each seam
# is filled by exactly one Wave-2 plan, which declares its own exports.
include("pricing/dlmp.jl")      # DLMP extraction + four-way decomposition (plan 05-02, PRICE-02)
include("pricing/fit.jl")       # flat feed-in-tariff baseline (plan 05-03, PRICE-04)
include("pricing/checks.jl")    # economic-direction price checks (plan 05-04, PRICE-05)
include("pricing/welfare.jl")   # social = prosumer + DSO surplus split (plan 05-05, PRICE-03)

end # module TSODSO
