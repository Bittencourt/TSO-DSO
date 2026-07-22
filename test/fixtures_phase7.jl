# test/fixtures_phase7.jl
#
# Shared Phase-7 (ADMM convergence & scale) test fixture module (Wave 0). A TestItems
# `@testmodule` that the Phase-7 `@testitem`s consume via `setup=[Phase7Fixtures]`. It provides
# the IEEE-123 seeded aggregator population (one house per LOAD node), the pinned λ₀ profile,
# and the adaptive-ρ / per-unit-tolerance config constants (RESEARCH Patterns 3 & 4).
#
# CONTRACT (threat T-06-01 / T-07 defines-only): this module DEFINES functions and consts
# ONLY — it makes NO top-level call to any symbol filled by a LATER Phase-7 wave (in
# particular it NEVER calls `ieee123_modified()` at module-load time). The aggregator-population
# builder takes the `feeder` as an ARGUMENT, so nothing here evaluates a not-yet-defined symbol
# at load time; a partial-wave state cannot corrupt test discovery.
#
# REPRODUCIBILITY (threat T-06-06): every aggregator flows from a seeded `generate_profiles`
# (StableRNGs), so the 123-node population regenerates bit-for-bit (RESEARCH Security Domain).
#
# SELF-CONTAINED: the house builder is inlined here (mirroring the Phase4Fixtures
# `_house_aggregator` SHAPE) so the module has no cross-`@testmodule` load-time dependency, the
# same discipline `Phase6Fixtures` follows.

@testmodule Phase7Fixtures begin
    using TSODSO

    # Day-ahead hourly horizon (thesis A1), matching Phase4/6Fixtures.T.
    const T = 24

    # Battery price triple (App. C parametrization) in ¢$/kWh — STRICT ordering
    # λ_min < λ_med < λ_max is the no-binary guarantee (CR-01), same values as Phase 4/6.
    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    # --- Adaptive-ρ / per-unit-tolerance config (RESEARCH Patterns 3 & 4, Boyd §3.3–3.4) ---
    # PER-UNIT NORMALIZED, so the SAME constants transfer unchanged across 2-bus / IEEE-13 /
    # IEEE-123 (the "no hard-coded scale-specific penalty" requirement, ADMM-02). These pin the
    # target config that plan 07-04's `solve_admm` consumes; they are Boyd-textbook values.
    # ε_abs/ε_rel are the SHARED (scale-invariant) per-unit stopping tolerances — the SAME values
    # are used on the 2-bus, IEEE-13 AND IEEE-123 (no per-fixture tuning; ADMM-02). They are one
    # decade tighter than Boyd's nominal (1e-4 / 1e-3): on the IEEE-123 voltage case the primal
    # residual collapses in a handful of iterations, so at 1e-4/1e-3 the two-residual stop fires
    # while the DADP tail is still ~0.02 pu from the centralized dual (just over the cross-val
    # atol). Tightening UNIFORMLY to 1e-5/1e-4 settles the price tail (λ→DADP within ~0.003 pu) at
    # the cost of a few extra iterations, still well within the tens-of-iters target, and remains a
    # STRICTLY stronger (never weaker) stop on every fixture — 2-bus/IEEE-13 still converge (plan
    # 07-05; the scale-invariance regression in test_admm_adaptive re-confirms both).
    const EPS_ABS = 1e-5        # absolute feasibility floor (√p·ε_abs term)
    const EPS_REL = 1e-4        # relative feasibility term (ε_rel·‖·‖)
    const TAU = 2.0             # residual-balancing ρ multiplier/divisor (τ_incr = τ_decr)
    const MU = 10.0             # residual-balancing imbalance band (‖r‖ vs μ·‖s‖)
    const RHO_MIN = 1e-2        # ρ clamp floor (keeps the proximal term meaningful)
    const RHO_MAX = 1e4         # ρ clamp ceiling (stops the penalty Hessian ill-conditioning)
    const RHO0 = 5.0            # starting penalty (O(1)–O(10) at the 100 MVA-base pu scale)

    # IEEE-123 population scaling (StableRNGs seed + magnitude scales). Sized (plan 07-05) on the
    # FEEDER-SCALE 1 MVA base (src/data/ieee123.jl) to keep the VOLTAGE-CONSTRAINED (V∈[0.9,1.1])
    # case FEASIBLE and genuinely VOLTAGE-BINDING (RESEARCH Open Q2): PV above load so the midday
    # surplus reverse-flows and the long laterals approach the upper voltage band (`≈1.04`), while
    # the evening load pulls the far ends down toward the lower band (`≈0.92`) — the regime the
    # LinDistFlow exactness copy targets. At these O(1e-2) pu house scales the solved cone
    # magnitude sits several orders above the PF-04 `atol` floor, so exactness is ROBUST at scale
    # (converged `exact_maxgap ~ 1e-9`), unlike the numerically-fragile 100 MVA-base sizing.
    # `DEV_SCALE_IEEE123` shrinks the (otherwise O(1) pu) flexible thermostatic/deferrable ratings
    # to the same residential order as the inelastic load, so no single house dominates the feeder.
    const SEED_IEEE123 = 20260719
    const LOAD_SCALE_IEEE123 = 0.03
    const PV_SCALE_IEEE123 = 0.06
    const DEV_SCALE_IEEE123 = 0.05

    """
        temperature_profile() -> Vector{Float64}

    The 24-hour exterior-temperature profile (°C) feeding the thermostatic-load ambient `Tout`,
    a DIGITIZED approximation of thesis Fig 4.2 (same shape as Phase4/6Fixtures). Inlined so this
    module is self-contained (no cross-`@testmodule` load-time dependency).
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
        ieee123_lambda0() -> Vector{Float64}

    The pinned 24-hour MEM / wholesale price `λ₀` (¢\$/kWh-consistent), a DIGITIZED shape
    (overnight trough → morning ramp → evening peak) reused for the IEEE-123 ADMM run. Positive
    and well within `PerUnit.PRICE_MAX`. Pinned ⇒ reproducible; the ADMM DADP `λ_j → −λ₀`-anchored
    price is cross-validated against `extract_dlmp` on the centralized SOCP (07-05).
    """
    function ieee123_lambda0()
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
        _house_aggregator(feeder, bus; seed, φ, pv_scale=1.0, load_scale=1.0,
                          batt_pmax=0.5, batt_emax=2.0, batt_soc0=1.0) -> Aggregator

    Build one aggregator at `bus` holding a Thermostatic + Deferrable + PVBattery, fed by a
    seeded `generate_profiles` draw (reproducible), mirroring the Phase4Fixtures SHAPE. The
    battery uses the App. C price triple (strict `λ_min < λ_med < λ_max`).
    """
    function _house_aggregator(
        feeder,
        bus;
        seed::Integer,
        φ::Real,
        pv_scale::Real = 1.0,
        load_scale::Real = 1.0,
        dev_scale::Real = 1.0,
        batt_pmax::Real = 0.5,
        batt_emax::Real = 2.0,
        batt_soc0::Real = 1.0,
    )
        prof = generate_profiles(seed = seed + bus, T = T)   # per-bus, deterministic in `seed`
        Ppv = Float64[pv_scale * p for p in prof.pv]
        Pdc = Float64[load_scale * d for d in prof.demand]

        # `dev_scale` rescales the FLEXIBLE device ratings (thermostatic max power, deferrable
        # energy/power) to a residential magnitude commensurate with the inelastic load — without
        # it the O(1) pu default ratings would let a single house's flexible demand dominate the
        # whole feeder at the feeder-scale base. Battery ratings scale with `load_scale` (below).
        therm = Thermostatic(
            bus,
            0.2,
            0.05,
            15.0,
            30.0,
            22.0,
            0.0,
            1.0 * dev_scale,
            0.5,
            temperature_profile(),
        )
        defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
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
        build_ieee123_aggregators(feeder; seed=SEED_IEEE123, load_buses=nothing)
            -> Vector{<:Aggregator}

    One seeded aggregator per LOAD node of the modified IEEE-123 `feeder` (RESEARCH Open Q2:
    seeded per-node houses, NOT full thesis device detail). `load_buses` selects the aggregator
    (coupling) axis — the subset of non-root buses that carry load; the remaining non-root buses
    are TRANSIT (zero-injection) nodes handled by the DSO-OPT relaxation (plan 07-03), NOT
    populated here. Defaults to the fixture's 85 spot-load buses (`ieee123_load_nodes()`, plan
    07-02), so the ~37 junction buses are genuinely exercised as transit nodes (the whole point of
    the 07-03 relaxation) rather than every non-root bus carrying a house. Rescaled to a
    residential magnitude (`LOAD_SCALE_IEEE123` / `PV_SCALE_IEEE123` / `DEV_SCALE_IEEE123`) on the
    feeder-scale base so the voltage-constrained solve is feasible AND voltage-binding (plan
    07-05). Seeded ⇒ reproducible (threat T-06-06); takes the feeder as an argument so this module
    never calls `ieee123_modified` at load time (threat T-06-01). Requires `allow_export = true` at
    the solve (priced export keeps the SOC relaxation exact, PF-04).
    """
    function build_ieee123_aggregators(
        feeder;
        seed::Integer = SEED_IEEE123,
        load_buses = nothing,
    )
        buses = load_buses === nothing ? ieee123_load_nodes() : load_buses
        return [
            _house_aggregator(
                feeder,
                bus;
                seed = seed,
                φ = 0.90,
                load_scale = LOAD_SCALE_IEEE123,
                pv_scale = PV_SCALE_IEEE123,
                dev_scale = DEV_SCALE_IEEE123,
                batt_pmax = 0.5 * LOAD_SCALE_IEEE123,
                batt_emax = 2.0 * LOAD_SCALE_IEEE123,
                batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
            ) for bus in buses
        ]
    end

    export T,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        EPS_ABS,
        EPS_REL,
        TAU,
        MU,
        RHO_MIN,
        RHO_MAX,
        RHO0,
        SEED_IEEE123,
        LOAD_SCALE_IEEE123,
        PV_SCALE_IEEE123,
        DEV_SCALE_IEEE123,
        temperature_profile,
        ieee123_lambda0,
        _house_aggregator,
        build_ieee123_aggregators
end
