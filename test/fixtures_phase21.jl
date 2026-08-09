# test/fixtures_phase21.jl
#
# Shared Phase-21 (MPC / rolling-horizon) test fixture module (Wave 2). A TestItems
# `@testmodule` that the Phase-21 `@testitem`s consume via `setup=[Phase21Fixtures]`. It
# provides the phase's SHORT-`T` CI substrate (`mpc_feeder`/`build_mpc_aggregators`) and the
# short-horizon high-PV forced-inexact fixture (`mpc_high_pv_feeder`/
# `build_mpc_high_pv_aggregators`) a later wave's certificate-escalation test drives.
#
# SEAM: Phase-21 CI fixture (MPC-01..04).
#
# CONTRACT (mirrors fixtures_phase6.jl's discipline, not fixtures_phase19.jl's cross-reference
# — Phase 21 needs no Phase-6-specific reuse): this module is SELF-CONTAINED, i.e. it makes NO
# top-level call to any symbol filled by a later Phase-21 wave. Every feeder-consuming builder
# takes a `feeder` argument, so nothing here evaluates a not-yet-defined symbol at module-load
# time; a partial-wave state cannot corrupt discovery.
#
# DELIBERATE EXCLUSION (RESEARCH Pitfall 8): this module never includes the project's
# scheduled-energy-budget flexible-load device (the third member of the Thermostatic/
# PV-battery/scheduled-load trio used elsewhere in the test suite). That device's
# within-window energy budget resets every window under a rolling horizon, which is
# honest-but-confusing for a minimal CI fixture whose whole point is closed-loop state
# CONTINUITY (soc0/Tin0 carried step-to-step) — including it would silently reset that
# budget on every re-window and muddy what the fixture is meant to demonstrate.
#
# REPRODUCIBILITY: every aggregator flows from a seeded `generate_profiles` (StableRNGs), so
# both fixtures regenerate bit-for-bit.

@testmodule Phase21Fixtures begin
    using TSODSO

    # Short day-ahead CI horizon (Pitfall 5: T - H + 1 = 6 published receding-horizon steps).
    const T = 8
    # Fixed window length — build-once, never rebuilt across the published steps.
    const H = 3

    # Battery price triple (App. C parametrization), the project's standard triple.
    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    # Fixture scaling + tuning constants (all pinned ⇒ reproducible).
    const SEED_MPC = 20260809
    const LOAD_SCALE_MPC = 0.02
    const PV_SCALE_MPC = 0.01
    const LAMBDA0_MPC = 4.0

    """
        temperature_profile(Tsteps::Int = T) -> Vector{Float64}

    The first `Tsteps` entries of the project's standard 24-hour ambient-temperature shape
    (the exact digitized literal `fixtures_phase6.jl`'s own `temperature_profile()` uses),
    sliced/cycled to `Tsteps` via `mod1` (a `Tsteps > 24` request wraps rather than erroring).
    """
    function temperature_profile(Tsteps::Int = T)
        full = Float64[
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
        return Float64[full[mod1(t, length(full))] for t in 1:Tsteps]
    end

    """
        mpc_lambda0(Tsteps::Int = T) -> Vector{Float64}

    The flat MEM / wholesale price `λ₀ = LAMBDA0_MPC` over `Tsteps` hours (mirrors
    `Phase6Fixtures.two_bus_lambda0`'s flat-price anchor convention).
    """
    mpc_lambda0(Tsteps::Int = T) = fill(LAMBDA0_MPC, Tsteps)

    """
        mpc_feeder() -> Feeder

    The phase's short-`T` CI substrate: a 2-bus radial fixture — root bus 1 (MEM frontier) +
    load bus 2, joined by ONE near-lossless, uncongested branch (mirrors
    `Phase6Fixtures.two_bus_feeder` exactly, so `ConvexBranchFlow` stays comfortably exact on
    the happy-path fixture). Built INSIDE the function (never at module top level).
    """
    function mpc_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier
            Bus(2, 0.95, 1.05, false),   # the single load bus (the priced node)
        ]
        branches = [
            Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),   # near-lossless, uncongested
        ]
        return Feeder(buses, branches, 1)
    end

    # Shared private house-aggregator builder (mirrors `Phase4Fixtures._house_aggregator`'s
    # shape): a Thermostatic + PVBattery house fed by a seeded `generate_profiles` draw,
    # deliberately excluding the scheduled-load device (Pitfall 8, see file header). Not
    # exported — an internal helper both public builders below share.
    function _mpc_house_aggregator(
        feeder,
        bus;
        seed::Integer,
        φ::Real,
        pv_scale::Real,
        load_scale::Real,
        batt_pmax::Real,
        batt_emax::Real,
        batt_soc0::Real,
        Tsteps::Int,
    )
        prof = generate_profiles(seed = seed + bus, T = Tsteps)   # per-bus, deterministic in seed
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
            temperature_profile(Tsteps),
        )
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
        return Aggregator(bus, φ, [therm, batt], Pdc)
    end

    """
        build_mpc_aggregators(feeder; seed::Integer = SEED_MPC, Tsteps::Int = T) -> Vector{<:Aggregator}

    ONE small seeded aggregator at bus 2 of the [`mpc_feeder`](@ref): a Thermostatic +
    PVBattery house (no scheduled-load device — Pitfall 8, see file header) fed by a seeded
    `generate_profiles` draw, scaled small (`LOAD_SCALE_MPC` demand, `PV_SCALE_MPC` PV, tiny
    battery) so the near-lossless short-`T` solve is FEASIBLE and INTERIOR — mirrors
    `Phase6Fixtures.build_two_bus_aggregators`'s exact construction shape minus that third
    device. Seeded ⇒ reproducible; takes `feeder` as an argument so this module never touches
    a later-wave symbol at load time.
    """
    function build_mpc_aggregators(feeder; seed::Integer = SEED_MPC, Tsteps::Int = T)
        bus = 2
        return [
            _mpc_house_aggregator(
                feeder,
                bus;
                seed = seed,
                φ = 0.90,
                pv_scale = PV_SCALE_MPC,
                load_scale = LOAD_SCALE_MPC,
                batt_pmax = 0.1 * LOAD_SCALE_MPC,
                batt_emax = 0.4 * LOAD_SCALE_MPC,
                batt_soc0 = 0.2 * LOAD_SCALE_MPC,
                Tsteps = Tsteps,
            ),
        ]
    end

    """
        mpc_high_pv_feeder() -> Feeder

    A 3-bus radial fixture (root + two downstream buses), mirroring
    `Phase4Fixtures.high_pv_feeder()` EXACTLY (branches `r=x=0.05`, `SMAX_NO_LIMIT`) — the
    substrate a later wave's forced-inexact certificate-escalation test drives. Built INSIDE
    the function (never at module top level).
    """
    function mpc_high_pv_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier
            Bus(2, 0.95, 1.05, false),
            Bus(3, 0.95, 1.05, false),
        ]
        branches = [
            Branch(1, 2, 0.05, 0.05, SMAX_NO_LIMIT),   # low-impedance ⇒ back-feed swings voltage fast
            Branch(2, 3, 0.05, 0.05, SMAX_NO_LIMIT),
        ]
        return Feeder(buses, branches, 1)
    end

    """
        build_mpc_high_pv_aggregators(feeder; seed::Integer = SEED_MPC, pv_scale::Real,
                                      Tsteps::Int = T) -> Vector{<:Aggregator}

    Aggregators for the [`mpc_high_pv_feeder`](@ref): mirrors
    `Phase4Fixtures.build_high_pv_aggregators`'s shape (Thermostatic + PVBattery only, small
    `load_scale`, tiny battery headroom) at this fixture's SHORT `Tsteps`/`H`. `pv_scale` has
    NO default — a later wave's task must MEASURE the `pv_scale` that genuinely trips the
    inline cone-residual check at this fixture's short horizon, per this project's "measured,
    not guessed" discipline; that measurement is documented in that wave's own plan/summary,
    not here.
    """
    function build_mpc_high_pv_aggregators(
        feeder;
        seed::Integer = SEED_MPC,
        pv_scale::Real,
        Tsteps::Int = T,
    )
        N = length(feeder.buses)
        load_scale = 0.02
        return [
            _mpc_house_aggregator(
                feeder,
                bus;
                seed = seed,
                φ = 0.95,
                pv_scale = pv_scale,
                load_scale = load_scale,
                batt_pmax = 0.1 * load_scale,
                batt_emax = 0.4 * load_scale,
                batt_soc0 = 0.2 * load_scale,
                Tsteps = Tsteps,
            ) for bus in 2:N
        ]
    end

    # MEASURED (plan 21-05, Task 2 — "measured, not guessed" discipline): the pv_scale that
    # reliably trips the inline cone-residual check (rtol=1e-4, atol=1e-6, run_mpc's own
    # per-resolve formula) on THIS fixture's short H=3 window, sliced from a Tsteps=T=8 PV
    # draw (`build_mpc_high_pv_aggregators(mpc_high_pv_feeder(); pv_scale, Tsteps = T)`, then
    # `d.Ppv[1:H]`/`d.Pdc[1:H]` slid into `build_mpc_window(...; H = H)` — the EXACT shape
    # run_mpc's own window construction uses, NOT a bare `Tsteps = H` draw, which measures a
    # DIFFERENT problem). Scanned pv_scale ∈ {1.0, 2.0, 2.5, 3.0, 4.0, ..., 1024.0} at a flat
    # λ₀ = LAMBDA0_MPC, terminal_soc = false: a sharp knife-edge transition (consistent with
    # this project's own documented SOCP-exactness knife-edge under high-PV reverse flow)
    # between pv_scale=2.0 (maxratio ≈ 0.0036, comfortably certified) and pv_scale=2.5
    # (maxratio ≈ 8510, ~8500× over the ratio>1 threshold). `Phase4Fixtures.high_pv_feeder`'s
    # own reference point (`pv_scale=1.2`) does NOT transfer unchanged to this fixture's
    # shorter horizon/smaller feeder (measured: pv_scale=1.2 stays comfortably exact here,
    # maxratio ≈ 0.006 on this fixture) — RE-MEASURED, per this project's own discipline.
    # pv_scale=3.0 (maxratio ≈ 9157, comfortably past the knife-edge with ample margin) is the
    # value exported here.
    const MPC_HIGH_PV_SCALE_MEASURED = 3.0

    export T,
        H,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        SEED_MPC,
        LOAD_SCALE_MPC,
        PV_SCALE_MPC,
        LAMBDA0_MPC,
        MPC_HIGH_PV_SCALE_MEASURED,
        temperature_profile,
        mpc_lambda0,
        mpc_feeder,
        build_mpc_aggregators,
        mpc_high_pv_feeder,
        build_mpc_high_pv_aggregators
end
