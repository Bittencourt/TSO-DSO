# test/test_flex_population.jl
#
# Seam: src/experiments/materialize.jl — the `flex_devices` opt-in kwarg of `build_population`
# (Phase 43 plan 05, DEV-06) and its per-house seeded EV / HeatPump / SmartInverterPV helpers.
#
# Every item name contains "flex population" so a substring selector picks them up.
#
# Byte-identity fence: `flex_devices = nothing` (the default) must leave the `:default` and
# `:case_a_784` populations structurally unchanged and `SCENARIO_VALID_POPULATIONS` untouched
# (the Scenario schema is NOT widened: opt-in is a kwarg, never a new selector symbol).
#
# SOFT-SCOPE RULE: accumulators live inside functions / `let` blocks, never bare in a top-level
# `for` of a @testitem body.

@testitem "flex population: byte-identity fence (kwarg absent == flex_devices=nothing)" tags =
    [:population] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    @test TSODSO.SCENARIO_VALID_POPULATIONS == (:default, :case_a_784)

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    s_pop = sub_seed(42, :population)

    shape(aggs) = [(a.bus, a.φ, [typeof(d) for d in a.devices], a.Pdc) for a in aggs]

    for sym in (:default, :case_a_784)
        a = build_population(sym, feeder, :ieee13, profiles, s_pop)
        b = build_population(sym, feeder, :ieee13, profiles, s_pop; flex_devices = nothing)
        @test isequal(shape(a), shape(b))
        # the pre-change device set per aggregator is the fixed 3-device house (+ n houses)
        @test all(x -> !(TSODSO.ElectricVehicle in (typeof(d) for d in x.devices)), b)
    end
    # :default is exactly one 3-device aggregator per load bus
    d = build_population(:default, feeder, :ieee13, profiles, s_pop)
    @test all(a -> length(a.devices) == 3, d)
end

@testitem "flex population: opt-in attaches the right device types, unknown selector throws" tags =
    [:population] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    s_pop = sub_seed(42, :population)

    count_of(aggs, D) = [count(x -> x isa D, a.devices) for a in aggs]
    base = build_population(:default, feeder, :ieee13, profiles, s_pop)

    ev = build_population(:default, feeder, :ieee13, profiles, s_pop; flex_devices = :ev)
    @test count_of(ev, TSODSO.ElectricVehicle) == fill(1, length(ev))
    @test [length(a.devices) for a in ev] == [length(a.devices) + 1 for a in base]
    @test [a.bus for a in ev] == [a.bus for a in base]

    hp = build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        s_pop;
        flex_devices = :heatpump,
    )
    @test count_of(hp, TSODSO.HeatPump) == fill(1, length(hp))

    sp = build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        s_pop;
        flex_devices = :smartinverterpv,
    )
    @test count_of(sp, TSODSO.SmartInverterPV) == fill(1, length(sp))

    mix = build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        s_pop;
        flex_devices = [:ev, :heatpump, :smartinverterpv],
    )
    @test count_of(mix, TSODSO.ElectricVehicle) == fill(1, length(mix))
    @test count_of(mix, TSODSO.HeatPump) == fill(1, length(mix))
    @test count_of(mix, TSODSO.SmartInverterPV) == fill(1, length(mix))

    # case_a_784: one EV per HOUSE (rolled into the bus aggregator)
    ca = build_population(:case_a_784, feeder, :ieee13, profiles, s_pop; flex_devices = :ev)
    @test sum(count_of(ca, TSODSO.ElectricVehicle)) == 784

    @test_throws ArgumentError build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        s_pop;
        flex_devices = :nonsense,
    )
    @test_throws ArgumentError build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        s_pop;
        flex_devices = [:ev, :bogus],
    )
end

@testitem "flex population: _flex_mix is a portable integer mix (pinned values, WR-02)" tags =
    [:population] begin
    using TSODSO: _flex_mix
    # SplitMix64-fold values are pure UInt64 arithmetic: identical on every Julia version.
    # (Base.hash-derived seeds are NOT — hence these pins would catch a regression to hash.)
    @test _flex_mix(1_234_567_890, 1, 2, 3) == 2692509415
    @test _flex_mix(0) == 271713375
    @test _flex_mix(5, 11) == 472329139
    @test _flex_mix(1, 2) != _flex_mix(2, 1)
end

@testitem "flex population: EV session seeding is deterministic, per-house distinct and valid" tags =
    [:population] begin
    using TSODSO
    using TSODSO: _flex_devices_for_house, sub_seed

    T = 24
    s_pop = 1_234_567_890   # literal: independent of Base.hash (WR-02)
    mk(bus, h; sp = s_pop) =
        only(_flex_devices_for_house(sp, bus, h, [:ev], T; scale = 0.005, ppv = nothing))
    sess(e) = (e.t_arr, e.t_dep, e.E_target, e.soc0)

    # determinism: same seed -> identical sessions
    @test all(h -> sess(mk(2, h)) == sess(mk(2, h)), 1:20)
    # per-house distinctness on the SAME bus (the per-house hash lesson)
    s = Set(sess(mk(2, h)) for h in 1:40)
    @test length(s) > 30
    # per-bus distinctness too
    @test length(Set(sess(mk(b, 1)) for b in 2:11)) > 7
    # different population seed -> different sessions
    @test any(h -> sess(mk(2, h)) != sess(mk(2, h; sp = 987_654_321)), 1:10)

    # validity for the constructor / contribute! guards; overnight wrap sessions occur
    evs = [mk(3, h) for h in 1:200]
    @test all(e -> 1 <= e.t_arr <= T && 1 <= e.t_dep <= T && e.t_arr != e.t_dep, evs)
    @test all(e -> e.Emin <= e.soc0 <= e.Emax && e.Emin <= e.E_target <= e.Emax, evs)
    @test any(e -> e.t_dep < e.t_arr, evs)
    @test all(e -> e.E_target >= e.soc0, evs)
    # arrival evening-centered, departure morning-centered (documented calibration)
    @test 16 <= sum(e.t_arr for e in evs) / length(evs) <= 21
    @test 5 <= sum(e.t_dep for e in evs) / length(evs) <= 10
end

@testitem "flex population: flex EV population solves through solve_welfare and solve_admm" setup =
    [TwoBusFixtures] tags = [:population, :admm] begin
    using TSODSO, JuMP, LinearAlgebra

    T = TwoBusFixtures.T
    λswing = [(t in 5:8) ? 12.0 : ((t >= 18 || t <= 4) ? 1.0 : 4.0) for t in 1:T]

    function flex_aggs(seed)
        prof = generate_profiles(seed = seed + 2, T = T)
        Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
        devs = TSODSO._flex_devices_for_house(
            seed,
            2,
            1,
            [:ev],
            T;
            scale = TwoBusFixtures.LOAD_SCALE_2BUS,
            ppv = nothing,
        )
        return [TSODSO.Aggregator(2, 0.90, devs, Pdc)]
    end

    seed = TwoBusFixtures.SEED_2BUS
    feeder = TwoBusFixtures.two_bus_feeder()
    ctx, obj, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        flex_aggs(seed);
        T = T,
        λ₀ = λswing,
        allow_export = true,
    )
    @test isfinite(obj)
    res = solve_admm(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        flex_aggs(seed);
        T = T,
        λ₀ = λswing,
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
    )
    @test res.iters >= 1
    @test isfinite(res.welfare)
    @test abs(res.welfare - obj) <= 1e-3 * max(1.0, abs(obj))
end

@testitem "flex population: FIT and MPC paths reject the phase-43 devices explicitly (WR-05)" tags =
    [:population] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder, _flex_devices_for_house, _reject_unsupported_flex_devices

    T = 3
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    # each new device type, alone, must be rejected with a message naming it
    function rejects(which, name)
        devs = _flex_devices_for_house(
            1_234_567_890,
            2,
            1,
            which,
            T;
            scale = 0.1,
            ppv = fill(0.05, T),
        )
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, AbstractDevice[batt; devs], fill(0.1, T))
        err_fit = try
            fit_baseline(feeder, ConvexBranchFlow(), [agg]; λ_fit = 40.0, T = T)
            nothing
        catch e
            e
        end
        err_mpc = try
            _reject_unsupported_flex_devices(agg.devices, "run_mpc")
            nothing
        catch e
            e
        end
        return err_fit isa ArgumentError &&
               occursin(name, err_fit.msg) &&
               err_mpc isa ArgumentError &&
               occursin(name, err_mpc.msg) &&
               occursin("run_mpc", err_mpc.msg)
    end
    @test rejects(:ev, "ElectricVehicle")
    @test rejects(:heatpump, "HeatPump")
    @test rejects(:smartinverterpv, "SmartInverterPV")
    # the legacy device set is NOT rejected
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    @test _reject_unsupported_flex_devices([batt], "run_mpc") === nothing
end
