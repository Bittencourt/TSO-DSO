# test/fixtures_phase4.jl
#
# Shared Phase-4 test fixture module (Wave 1). A TestItems `@testmodule` that the
# Phase-4 `@testitem`s consume via `setup=[Phase4Fixtures]`. It provides the modified
# IEEE-13 aggregator builder, the digitized MEM price / exterior-temperature profiles,
# and the high-PV / over-voltage stress fixture that the PF-04 exactness gate targets.
#
# CONTRACT (threat T-04-08): this module DEFINES functions and consts ONLY — it makes NO
# top-level call to any symbol filled by a later Phase-4 wave (e.g. `ieee13_modified`,
# `ConvexBranchFlow`, `operational_oracle`). The feeder-consuming builders take a `feeder`
# argument, so nothing here evaluates a not-yet-defined symbol at module-load time; a
# partial-wave state therefore cannot corrupt test discovery.
#
# REPRODUCIBILITY (threat T-04-06): every profile / aggregator flows from a seeded
# `generate_profiles` (StableRNGs), so the high-PV stress fixture regenerates bit-for-bit.
#
# UNITS (RESEARCH Pitfall 3): the MEM price profile is kept in the SAME monetary unit as
# the device price coefficients (¢$/kWh-consistent, cf. the battery triple
# λ_max=8.9 / λ_med=6.2 / λ_min=3.8), so no objective term dwarfs another.
#
# The MEM price (Fig 4.5) and temperature (Fig 4.2) profiles are figure-bound in the
# thesis and only PLOTTED, so these are documented DIGITIZED approximations (RESEARCH
# Open Q1); the tight ground-truth golden is pinned later behind a human-verify checkpoint.

@testmodule Phase4Fixtures begin
    using TSODSO

    # Day-ahead hourly horizon (thesis A1). Exported so items reference `Phase4Fixtures.T`.
    const T = 24

    # Battery price triple (App. C parametrization, thesis Table 4.x) in ¢$/kWh — STRICT
    # ordering λ_min < λ_med < λ_max is the load-bearing no-binary guarantee (CR-01).
    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    """
        mem_price_profile() -> Vector{Float64}

    The 24-hour MEM / wholesale price `λ₀` (¢\$/kWh-consistent), a DIGITIZED approximation
    of thesis Fig 4.5 (Open Q1): low overnight, a morning ramp, a moderate midday shoulder,
    and an evening peak. Positive and well within the `PerUnit.PRICE_MAX` sanity bound.
    """
    function mem_price_profile()
        return Float64[
            3.8,
            3.7,
            3.6,
            3.6,
            3.7,
            4.0,   # 00–05 overnight trough
            4.8,
            5.8,
            6.5,
            6.2,
            5.9,
            5.7,   # 06–11 morning ramp → midday shoulder
            5.6,
            5.8,
            6.0,
            6.8,
            8.2,
            9.0,   # 12–17 afternoon rise → evening peak
            8.6,
            7.4,
            6.2,
            5.2,
            4.4,
            4.0,   # 18–23 evening decline
        ]
    end

    """
        temperature_profile() -> Vector{Float64}

    The 24-hour exterior-temperature profile (°C), a DIGITIZED approximation of thesis
    Fig 4.2 (Open Q1): a dawn minimum and an afternoon peak. Feeds the thermostatic-load
    ambient `Tout`; it may exceed the comfort band (it is ambient, not the setpoint).
    """
    function temperature_profile()
        return Float64[
            19,
            18,
            17,
            16,
            16,
            17,   # 00–05 cooling to a dawn minimum
            19,
            21,
            23,
            26,
            28,
            30,   # 06–11 morning warm-up
            31,
            32,
            32,
            31,
            29,
            27,   # 12–17 afternoon peak → decline
            25,
            23,
            22,
            21,
            20,
            19,   # 18–23 evening cool-down
        ]
    end

    """
        _house_aggregator(feeder, bus; seed, φ, pv_scale=1.0, load_scale=1.0,
                          batt_pmax=0.5, batt_emax=2.0, batt_soc0=1.0) -> Aggregator

    Build one aggregator at `bus` holding a Thermostatic + Deferrable + PVBattery, fed by a
    seeded `generate_profiles` draw (reproducible). The battery uses the App. C price triple
    (strict `λ_min < λ_med < λ_max`). `pv_scale`/`load_scale` let a stress fixture amplify the
    PV back-feed or shrink the load without changing the seeded SHAPE.
    """
    function _house_aggregator(
        feeder,
        bus;
        seed::Integer,
        φ::Real,
        pv_scale::Real = 1.0,
        load_scale::Real = 1.0,
        batt_pmax::Real = 0.5,
        batt_emax::Real = 2.0,
        batt_soc0::Real = 1.0,
    )
        prof = generate_profiles(seed = seed + bus, T = T)   # per-bus, deterministic in `seed`
        Ppv = Float64[pv_scale * p for p in prof.pv]
        Pdc = Float64[load_scale * d for d in prof.demand]

        therm = Thermostatic(
            bus,
            0.2,
            0.05,
            15.0,
            30.0,
            22.0,
            0.0,
            1.0,
            0.5,
            temperature_profile(),
        )
        defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
        batt = PVBattery(
            bus,
            0.95,
            1.0,
            batt_pmax,
            0.0,
            batt_emax,
            batt_soc0,
            BATT_λ_MIN,
            BATT_λ_MED,
            BATT_λ_MAX,
            Ppv,
        )
        return Aggregator(bus, φ, [therm, defer, batt], Pdc)
    end

    """
        build_ieee13_aggregators(feeder; seed=20260718) -> Vector{<:Aggregator}

    One aggregator per NON-root bus (indices `2:length(feeder.buses)` — the 10 thesis load
    nodes 1..10) on the modified IEEE-13 feeder, each holding Thermostatic + Deferrable +
    PVBattery with the App. C price triple and a load power factor `φ = 0.90 ∈ [0.85, 0.95]`.
    Seeded and reproducible (threat T-04-06). Takes the feeder as an argument so this module
    never calls `ieee13_modified` at load time (threat T-04-08).
    """
    function build_ieee13_aggregators(feeder; seed::Integer = 20260718)
        N = length(feeder.buses)
        return [_house_aggregator(feeder, bus; seed = seed, φ = 0.90) for bus in 2:N]
    end

    """
        high_pv_feeder() -> Feeder

    A small 3-bus radial fixture (root + two downstream load buses) with low-impedance
    branches and tight voltage headroom — the substrate for the high-PV / over-voltage,
    reverse-power-flow regime that stresses SOC-relaxation exactness (RESEARCH Pitfall 1).
    Constructed inside the function (never at module top level).
    """
    function high_pv_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier (v fixed at 1.0)
            Bus(2, 0.95, 1.05, false),
            Bus(3, 0.95, 1.05, false),
        ]
        branches = [
            Branch(1, 2, 0.05, 0.05, 99.0),   # low-impedance ⇒ back-feed swings voltage fast
            Branch(2, 3, 0.05, 0.05, 99.0),   # 99.0 pu sentinel honours the strict smax band
        ]
        return Feeder(buses, branches, 1)
    end

    """
        build_high_pv_aggregators(feeder; seed=20260406) -> Vector{<:Aggregator}

    Aggregators for the [`high_pv_feeder`](@ref): a seeded PV back-feed that exceeds the small
    local load, so the surplus REVERSE-FLOWS toward the root and pushes the bus voltages ABOVE
    nominal (over-voltage). Calibrated to the EXACT over-voltage regime the PF-04 gate targets:
    with the priced frontier export (`solve_welfare(...; allow_export = true)`) the surplus is
    sold to the MEM rather than dissipated, so the SOC relaxation stays TIGHT — voltage climbs
    to ≈`1.04` pu (genuine over-voltage / reverse power flow) while remaining strictly BELOW the
    `1.05` cap, which is precisely the regime in which the LinDistFlow exactness copy keeps
    `l·v = P²+Q²` (thesis over-voltage result, e.g. `v ≈ 1.049` pu, is an EXACT SOCP outcome).

    Calibration note (why `pv_scale = 0.5`, not `≫ 1`): exactness of the DistFlow SOC
    relaxation holds under reverse flow so long as the UPPER voltage bound does not STRICTLY
    bind. An over-scaled back-feed pins voltage at `V²max` (the bound binds), which is the one
    regime where SOC exactness genuinely fails — the solver then dumps surplus into a fictitious
    loss current `l` (`l·v > P²+Q²`) and the PF-04 gate correctly REFUSES the resulting prices.
    `pv_scale = 0.5` (against the seeded PV shape, a small `load_scale = 0.2`, and a tiny
    battery) lands the peak at ≈`1.04` pu — clear over-voltage with headroom below the cap.
    Fixed default seed ⇒ reproducible (threat T-04-06).

    The `pv_scale` kwarg defaults to `0.5` (the documented ≈1.04 pu EXACT regime,
    `test_exactness.jl`'s own high-PV case); a caller-supplied `pv_scale ≫ 0.5` pins voltage at
    `V²max` — the one regime where SOC exactness genuinely fails (EXACT-04, plan 15-03).
    """
    function build_high_pv_aggregators(
        feeder;
        seed::Integer = 20260406,
        pv_scale::Real = 0.5,
    )
        N = length(feeder.buses)
        return [
            _house_aggregator(
                feeder,
                bus;
                seed = seed,
                φ = 0.95,
                pv_scale = pv_scale,  # caller-tunable; default 0.5 = the documented EXACT regime
                load_scale = 0.2,     # small load ⇒ the surplus must leave via the frontier
                batt_pmax = 0.1,
                batt_emax = 0.2,
                batt_soc0 = 0.1,   # tiny storage headroom
            ) for bus in 2:N
        ]
    end

    # --- Ground-truth calibration (OPT-02/OPT-03, RESEARCH Open Q1 / Assumptions A2–A3) ---
    #
    # The head-branch thermal limit S_max,(0,1) = 6.86 MVA ⇒ 0.0686 pu on the 100 MVA base,
    # while EVERY device / demand magnitude in this module is O(0.1..1) pu (a normalized
    # per-node SHAPE, not a residential magnitude). The full-magnitude `build_ieee13_aggregators`
    # therefore draws ≈6.3 pu at the peak hour — ~90× the head limit — so the congestion-
    # constrained GLB-CVX solve is INFEASIBLE. That is the figure-bound-input gap flagged in
    # RESEARCH Open Q1 (the thesis MEM/temperature profiles and per-house device
    # parametrization are only PLOTTED) and the house-count inconsistency A3 (784 houses /
    # 112-per-node ⇒ a residential feeder is a small fraction of the 100 MVA base).
    #
    # `GROUND_LOAD_SCALE` / `GROUND_PV_SCALE` rescale the seeded SHAPES to a physically
    # sensible residential magnitude so the feeder is (a) FEASIBLE under the 0.0686 pu head
    # limit and (b) CONGESTION-DRIVEN AT THE HEAD (the thesis regime): at the chosen scale the
    # head branch binds at its EXPORT limit (|P₀|≈0.067 < 0.0686 pu) at the afternoon PV peak,
    # driving a genuine over-voltage on the long node-9 lateral (thesis Fig 4.4, `v₉[16]`).
    # PV is scaled ABOVE load (`0.03` vs `0.005`) so the surplus reverse-flows to the frontier —
    # the exact over-voltage / reverse-power regime the LinDistFlow exactness copy targets, and
    # the reason the ground solve needs `allow_export = true` (priced export keeps the SOC cone
    # tight/exact; PF-04). These are a DOCUMENTED CALIBRATION, not the thesis inputs — the
    # ground-truth regression pins the resulting COMPUTED golden (a reproducibility anchor) and
    # cross-checks the thesis `v₉[16] ≈ 1.0493` as an APPROXIMATE magnitude, per Open Q1.
    const GROUND_LOAD_SCALE = 0.005
    const GROUND_PV_SCALE = 0.03

    """
        build_ieee13_ground_aggregators(feeder; seed=20260718) -> Vector{<:Aggregator}

    The modified IEEE-13 aggregators calibrated for the OPT-02/OPT-03 GROUND-TRUTH solve:
    one aggregator per non-root bus, identical SHAPE to [`build_ieee13_aggregators`](@ref) but
    rescaled to a residential magnitude (`GROUND_LOAD_SCALE` demand / battery, `GROUND_PV_SCALE`
    PV) so the head-branch-congested GLB-CVX solve is FEASIBLE and lands in the thesis
    congestion-driven over-voltage regime (`v₉[16]`, thesis Fig 4.4). Seeded and reproducible
    (threat T-04-06); takes the feeder as an argument (never calls `ieee13_modified` at load
    time, threat T-04-08). Requires `allow_export = true` at the solve (the PV surplus exports
    to the MEM; priced export is the SOC-exactness enabler, PF-04).
    """
    function build_ieee13_ground_aggregators(feeder; seed::Integer = 20260718)
        N = length(feeder.buses)
        return [
            _house_aggregator(
                feeder,
                bus;
                seed = seed,
                φ = 0.90,
                load_scale = GROUND_LOAD_SCALE,
                pv_scale = GROUND_PV_SCALE,
                batt_pmax = 0.5 * GROUND_LOAD_SCALE,   # battery scaled WITH the load magnitude
                batt_emax = 2.0 * GROUND_LOAD_SCALE,
                batt_soc0 = 1.0 * GROUND_LOAD_SCALE,
            ) for bus in 2:N
        ]
    end

    export T,
        mem_price_profile,
        temperature_profile,
        build_ieee13_aggregators,
        high_pv_feeder,
        build_high_pv_aggregators,
        build_ieee13_ground_aggregators,
        GROUND_LOAD_SCALE,
        GROUND_PV_SCALE
end
