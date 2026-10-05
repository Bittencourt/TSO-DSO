# test/fixtures_phase22.jl
#
# Shared Phase-22 (stochastic PV/demand uncertainty) test fixture module (Wave 1). A
# TestItems `@testmodule` that every downstream Phase-22 `@testitem` consumes via
# `setup=[Phase22Fixtures]`. It provides a small, Deferrable-free, radial CI fixture that
# produces S disjoint-seeded scenario aggregator populations for a battery+thermostatic
# house (D-12).
#
# SEAM: Phase-22 CI fixture (STOCH-01).
#
# CONTRACT (mirrors fixtures_phase21.jl's discipline): this module is SELF-CONTAINED, i.e. it
# makes NO top-level call to any symbol filled by a later Phase-22 wave. Every feeder-consuming
# builder takes `feeder`/`seed` as an argument, so nothing here evaluates a not-yet-defined
# symbol at module-load time; a partial-wave state cannot corrupt discovery.
#
# DELIBERATE EXCLUSION OF DEFERRABLE (D-12/RESEARCH Pitfall 3): this module never includes the
# project's scheduled-energy-budget flexible-load device. For THIS phase the reasoning is
# different from Phase 21's rolling-horizon-reset confusion: the extensive-form builder (plan
# 22-02) duplicates each aggregator ONCE PER IN-SAMPLE SCENARIO under nonanticipativity ties
# across independently-built battery copies, so an S-way duplication of a Deferrable's
# within-window energy budget would multiply an already-nontrivial modeling cost across every
# scenario for no fixture-scale benefit. Unlike Phase 21, this fixture carries NO small-T
# Deferrable constraint at all, since Deferrable is excluded entirely — `T = 6` is safe purely
# as a small day-ahead horizon, not because of any device-specific minimum-T requirement
# (RESEARCH Pitfall 3 flags that `:default` population needs T>=9 on `:ieee13`; this
# hand-built, Deferrable-free 2-bus fixture avoids that constraint by construction).
#
# REPRODUCIBILITY: every aggregator flows from a seeded `generate_profiles` (StableRNGs), so
# the fixture regenerates bit-for-bit. Calling convention for downstream plans (documented,
# never invoked here): in-sample scenarios use `sub_seed(SEED_STOCH, Symbol(:insample_, k))`
# for `k in 1:S`; held-out scenarios use a DISJOINT family
# `sub_seed(SEED_STOCH, Symbol(:oos_, h))` for `h in 1:H` — this module itself never calls
# `sub_seed`, it only documents the convention every downstream plan must follow.

@testmodule Phase22Fixtures begin
    using TSODSO

    # Small day-ahead CI horizon — safe at any T since Deferrable is absent from this fixture.
    const T = 6
    # Locked D-01/D-10 bands this fixture's constants mirror (not enforced here; Scenario.jl
    # itself is the enforcement point — plan 22-01 Task 1).
    const S_INSAMPLE = 3
    const H_OOS = 5

    # Battery price triple (App. C parametrization), the project's standard triple.
    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    # Fixture scaling + tuning constants (all pinned ⇒ reproducible). A fresh literal, distinct
    # from Phase21Fixtures.SEED_MPC.
    const SEED_STOCH = 20260809
    const LOAD_SCALE_STOCH = 0.02
    const PV_SCALE_STOCH = 0.01
    const LAMBDA0_STOCH = 4.0

    """
        temperature_profile(Tsteps::Int = T) -> Vector{Float64}

    The first `Tsteps` entries of the project's standard 24-hour ambient-temperature shape
    (the exact digitized literal `fixtures_phase21.jl`'s own `temperature_profile()` uses),
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
        stoch_lambda0(Tsteps::Int = T) -> Vector{Float64}

    The flat MEM / wholesale price `λ₀ = LAMBDA0_STOCH` over `Tsteps` hours (mirrors
    `Phase21Fixtures.mpc_lambda0`'s flat-price anchor convention).
    """
    stoch_lambda0(Tsteps::Int = T) = fill(LAMBDA0_STOCH, Tsteps)

    """
        stoch_feeder() -> Feeder

    The phase's small Deferrable-free CI substrate: a 2-bus radial fixture — root bus 1 (MEM
    frontier) + load bus 2, joined by ONE near-lossless, uncongested branch (mirrors
    `Phase21Fixtures.mpc_feeder` exactly). Built INSIDE the function (never at module top
    level).
    """
    function stoch_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier
            Bus(2, 0.95, 1.05, false),   # the single load bus (the priced node)
        ]
        branches = [
            Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),   # near-lossless, uncongested
        ]
        return Feeder(buses, branches, 1)
    end

    """
        stoch_scenario_aggregators(feeder, seed::Integer; Tsteps::Int = T) -> Vector{<:Aggregator}

    ONE small seeded aggregator at bus 2 of the [`stoch_feeder`](@ref): a Thermostatic +
    PVBattery house (no Deferrable device — see file header), fed by a seeded
    `generate_profiles` draw offset by the target bus (`seed = seed + 2`, mirrors
    `Phase21Fixtures._mpc_house_aggregator`'s per-bus-offset seeding convention), scaled small
    so the near-lossless short-`T` solve is FEASIBLE and INTERIOR.

    This function is called ONCE PER SCENARIO by every downstream plan with a DISJOINT `seed`
    per scenario: in-sample scenarios pass `sub_seed(SEED_STOCH, Symbol(:insample_, k))` for
    `k in 1:S`; held-out scenarios pass a DISJOINT family
    `sub_seed(SEED_STOCH, Symbol(:oos_, h))` for `h in 1:H`. This module itself never calls
    `sub_seed` — only documents the convention.
    """
    function stoch_scenario_aggregators(feeder, seed::Integer; Tsteps::Int = T)
        bus = 2
        prof = generate_profiles(seed = seed + bus, T = Tsteps)
        Ppv = Float64[PV_SCALE_STOCH * p for p in prof.pv]
        Pdc = Float64[LOAD_SCALE_STOCH * d for d in prof.demand]

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
            0.1 * LOAD_SCALE_STOCH,
            0.0,
            0.4 * LOAD_SCALE_STOCH,
            0.2 * LOAD_SCALE_STOCH,
            BATT_λ_MIN,
            BATT_λ_MED,
            BATT_λ_MAX,
            Ppv,
        )
        return [Aggregator(bus, 0.90, [therm, batt], Pdc)]
    end

    export T,
        S_INSAMPLE,
        H_OOS,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        SEED_STOCH,
        LOAD_SCALE_STOCH,
        PV_SCALE_STOCH,
        LAMBDA0_STOCH,
        temperature_profile,
        stoch_lambda0,
        stoch_feeder,
        stoch_scenario_aggregators
end
