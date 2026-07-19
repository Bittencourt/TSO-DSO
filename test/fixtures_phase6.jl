# test/fixtures_phase6.jl
#
# Shared Phase-6 (ADMM) test fixture module (Wave 0). A TestItems `@testmodule` that the
# Phase-6 `@testitem`s consume via `setup=[Phase6Fixtures]`. It provides the NEW 2-bus
# dual-SIGN-anchor feeder + its seeded aggregator, plus the pinned starting penalty `RHO_2BUS`
# and the MEM price `λ₀`. The IEEE-13 ground case is NOT redefined here — the harness reuses
# `Phase4Fixtures.build_ieee13_ground_aggregators` + the exported `ieee13_modified()` feeder
# directly (Wave-0 requirement: "reuse Phase 4/5 fixtures").
#
# CONTRACT (threat T-06-01): this module DEFINES functions and consts ONLY — it makes NO
# top-level call to any symbol filled by a LATER Phase-6 wave (the AGR-OPT / DSO-OPT / loop
# seams). The feeder-consuming builder takes a `feeder` argument, so nothing here evaluates a
# not-yet-defined symbol at module-load time; a partial-wave state cannot corrupt discovery.
#
# REPRODUCIBILITY (threat T-06-06): the 2-bus aggregator flows from a seeded `generate_profiles`
# (StableRNGs), so it regenerates bit-for-bit (RESEARCH Security Domain).
#
# DUAL-SIGN ANCHOR (RESEARCH Pattern 2 / Pitfall 5): the 2-bus branch is NEAR-LOSSLESS
# (r,x ≈ 0) and UNCONGESTED (`SMAX_NO_LIMIT`), so at the interior optimum the load-bus DADP
# `λ_2 ≈ λ₀ > 0` — the analytically-known, strictly-POSITIVE price (marginal cost of
# consumption) against which the recovered ADMM `λ` sign is pinned (positive = consumption cost,
# matching `extract_dlmp`'s convention). Bus 2 is kept a NET CONSUMER (PV < load) so the sign
# is unambiguous.

@testmodule Phase6Fixtures begin
    using TSODSO

    # Day-ahead hourly horizon (thesis A1), matching Phase4Fixtures.T. Exported so items
    # reference `Phase6Fixtures.T`.
    const T = 24

    # Battery price triple (App. C parametrization) in ¢$/kWh — STRICT ordering
    # λ_min < λ_med < λ_max is the no-binary guarantee (CR-01), same values as Phase 4.
    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    # 2-bus fixture scaling + tuning constants (all pinned ⇒ reproducible).
    const SEED_2BUS = 20260719          # StableRNGs seed for the seeded profile draw
    const LOAD_SCALE_2BUS = 0.02        # small inelastic demand ⇒ feasible, interior, near-lossless
    const PV_SCALE_2BUS = 0.005         # PV < load ⇒ bus 2 stays a NET CONSUMER (positive DADP)
    const LAMBDA0_2BUS = 4.0            # flat MEM price λ₀ (¢$/kWh-consistent, positive, in-band)

    # Pinned starting penalty/dual-step ρ for the 2-bus (RESEARCH Pitfall 2: O(1)–O(10) at the
    # 100 MVA-base pu scale, NOT the thesis's 1000). The Wave-3 loop's `ρ` keyword defaults from
    # this; adaptive-ρ is Phase 7. Empirically retunable (06-VALIDATION Manual-Only).
    const RHO_2BUS = 5.0

    """
        temperature_profile() -> Vector{Float64}

    The 24-hour exterior-temperature profile (°C) feeding the thermostatic-load ambient `Tout`,
    a DIGITIZED approximation of thesis Fig 4.2 (same shape as Phase4Fixtures). Kept local so
    this module is self-contained (no cross-`@testmodule` load-time dependency).
    """
    function temperature_profile()
        return Float64[
            19, 18, 17, 16, 16, 17,   # 00–05 cooling to a dawn minimum
            19, 21, 23, 26, 28, 30,   # 06–11 morning warm-up
            31, 32, 32, 31, 29, 27,   # 12–17 afternoon peak → decline
            25, 23, 22, 21, 20, 19,   # 18–23 evening cool-down
        ]
    end

    """
        two_bus_lambda0() -> Vector{Float64}

    The flat 24-hour MEM / wholesale price `λ₀ = LAMBDA0_2BUS` (¢\$/kWh-consistent, strictly
    positive, well within `PerUnit.PRICE_MAX`). Flat by design: on the near-lossless uncongested
    2-bus the load-bus DADP must land at ≈ this constant, making it the analytic sign anchor.
    """
    two_bus_lambda0() = fill(LAMBDA0_2BUS, T)

    """
        two_bus_feeder() -> Feeder

    The minimal dual-SIGN-anchor feeder: root bus 1 (`is_root`, voltage fixed to 1.0 pu by the
    formulation) + one load bus 2, joined by a SINGLE NEAR-LOSSLESS branch 1→2 (r = x = 1e-3,
    so losses are negligible and `λ_2 ≈ λ₀`) carrying the `SMAX_NO_LIMIT` sentinel (uncongested,
    no thermal cone). Radial by construction; built INSIDE the function (never at module top
    level, threat T-06-01).
    """
    function two_bus_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier (v fixed at 1.0 by the model)
            Bus(2, 0.95, 1.05, false),   # the single load bus (the priced node)
        ]
        branches = [
            Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),   # near-lossless, uncongested (no power cone)
        ]
        return Feeder(buses, branches, 1)
    end

    """
        build_two_bus_aggregators(feeder; seed=SEED_2BUS) -> Vector{<:Aggregator}

    ONE small seeded aggregator at bus 2 of the [`two_bus_feeder`](@ref): a Thermostatic +
    Deferrable + PVBattery house (the Phase4Fixtures `_house_aggregator` SHAPE) fed by a seeded
    `generate_profiles` draw, scaled small (`LOAD_SCALE_2BUS` demand, `PV_SCALE_2BUS` PV, tiny
    battery) so the near-lossless 2-bus solve is FEASIBLE and INTERIOR (voltage un-binding) and
    bus 2 stays a NET CONSUMER (positive DADP). Seeded ⇒ reproducible (threat T-06-06); takes
    the feeder as an argument so the module never touches a later-wave ADMM symbol at load time.
    """
    function build_two_bus_aggregators(feeder; seed::Integer = SEED_2BUS)
        bus = 2
        prof = generate_profiles(seed = seed + bus, T = T)   # deterministic in `seed`
        Ppv = Float64[PV_SCALE_2BUS * p for p in prof.pv]
        Pdc = Float64[LOAD_SCALE_2BUS * d for d in prof.demand]

        therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile())
        defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
        batt = PVBattery(
            bus, 0.95, 1.0, 0.1, 0.0, 0.2, 0.1,
            BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
        )
        return [Aggregator(bus, 0.90, [therm, defer, batt], Pdc)]
    end

    export T, BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX,
        SEED_2BUS, LOAD_SCALE_2BUS, PV_SCALE_2BUS, LAMBDA0_2BUS, RHO_2BUS,
        temperature_profile, two_bus_lambda0, two_bus_feeder, build_two_bus_aggregators
end
