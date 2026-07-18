# test/fixtures_phase3.jl
#
# Shared Phase-3 test fixture (Wave 0). A TestItems `@testmodule` provides a small
# valid radial feeder plus a deterministic T=24 multi-period parameter set that
# the Wave-2/3 device, aggregator, and welfare integration `@testitem`s consume
# via `setup=[Phase3Fixtures]`. It is intentionally solver-free and JuMP-free:
# pure data so it stays cheap and stable across the whole phase.
#
# The horizon T=24 (hourly, Δt=1h) matches the thesis day-ahead horizon (RESEARCH
# Assumption A1). Every parameter vector has length T so temporal-coupling device
# models can index t = 1:T directly.

@testmodule Phase3Fixtures begin
    using TSODSO: Bus, Branch, Feeder

    # Day-ahead hourly horizon (RESEARCH A1). Exported so items reference `Phase3Fixtures.T`.
    const T = 24

    """
        small_radial_feeder() -> Feeder

    A minimal 3-bus radial feeder in per-unit with a single root/MEM frontier bus
    (bus 1). Branches 1->2 and 2->3 give the tree the required `branches == buses-1`
    edge count; all voltages/impedances/limits sit inside the PerUnit sanity bands,
    so `Feeder` construction (radial + magnitude invariants) succeeds.
    """
    function small_radial_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier
            Bus(2, 0.95, 1.05, false),   # load bus
            Bus(3, 0.95, 1.05, false),   # load bus
        ]
        branches = [
            Branch(1, 2, 0.01, 0.02, 10.0),
            Branch(2, 3, 0.01, 0.02, 10.0),
        ]
        return Feeder(buses, branches, 1)
    end

    "Ambient-temperature profile (°C), length T — drives the thermostatic recursion (3.2)."
    const Tout = Float64[20 + 5 * sinpi((t - 1) / 12) for t in 1:T]

    "Inelastic (fixed) demand profile in per-unit power, length T — enters :Rp as a parameter."
    const Pdc = Float64[0.3 + 0.1 * cospi((t - 1) / 12) for t in 1:T]

    "PV availability profile in per-unit power, length T — daylight bump, zero at night."
    const Ppv = Float64[max(0.0, sinpi((t - 6) / 12)) * 0.4 for t in 1:T]

    "Hourly wholesale/MEM price λ₀ (\$/MWh-equivalent), length T — the priced frontier import."
    const λ₀ = Float64[40 + 15 * sinpi((t - 8) / 12) for t in 1:T]

    export small_radial_feeder, T, Tout, Pdc, Ppv, λ₀
end
