# test/test_device_traits.jl
#
# Seam: devices/AbstractDevice.jl capability traits (`has_reactive_decision`,
# `storage_kind`) + the type-paired device stash (`ModelContext.agg_device_types`).
#
# The DEV-10 correctness gate for Phase 43: the hard-coded device-classification
# probes — `dv isa FourQuadBESS || is_flexible_load(dv)` (DsoOpt.jl's
# `_any_flexible_reactive` + its inline guard copy, and `admm_state.jl`'s
# `_default_reactive_consensus` which delegates to it) and the var-shape battery
# sniff `haskey(v,:p_ch) && haskey(v,:p_dch) && !haskey(v,:q)`
# (welfare_solve.jl's battery certificate; the 4Q twin in admm_state.jl's
# `_react_outputs`) — are replaced by capability traits, BEHAVIOR-IDENTICALLY.
#
# EQUIVALENCE CONTRACT (the load-bearing assertion of this file): on today's
# device set (Thermostatic, Deferrable, Interruptible, PVBattery, FourQuadBESS,
# FixedCapacitor) every classification resolves EXACTLY as the old probes did,
# and every existing fixture population keeps its resolved reactive mode
# (LIVE/OFF). The ONE deliberate asymmetry is reproduced by construction (A8):
# `FixedCapacitor` carries `q_inject` but `has_reactive_decision === false` —
# its reactive is part of the constant `-Pdc·tanφ` draw, not a decision; flipping
# it would flip every `:ieee8500*` reactive default.
#
# The certificates' certificate-side selection (battery/4Q over
# `ctx.agg_device_vars`) is routed by the PAIRED device type
# (`ctx.agg_device_types`, appended in lockstep by `Aggregator.contribute!`);
# entries WITHOUT type provenance (hand-built test contexts) fall back to the
# legacy shape predicate, so the existing hand-built certificate fixtures stay
# green. Proven here by test, not by comment.
#
# Every item name contains "device traits" so `occursin("device traits", ti.name)`
# selects it; the file is also selected directly via
# `TSODSO_TEST_FILES=test_device_traits.jl`.

@testitem "device traits: truth table over every existing device type" tags =
    [:device, :traits] begin
    using TSODSO

    # Explicit per-type assertions — NOT a loop over an untyped list — so a NEW
    # device type can never silently skip this table (a new device must extend it
    # explicitly, mirroring the old probes' extension discipline).
    #
    # Minimal valid parameterizations follow each device's own test file's
    # `good()` factory idiom (`contribute!` is never called here, so profile
    # lengths only need to satisfy the CONSTRUCTORS).

    therm = TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(20.0, 24))
    defer = TSODSO.Deferrable(2, 8, 16, 1.0, 0.5, 0.5)
    inter = TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 1.0)
    pvbatt =
        TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, fill(5.0, 4))
    bess = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    fc = TSODSO.FixedCapacitor(2, 0.1)

    # --- has_reactive_decision ≡ the old probe `d isa FourQuadBESS || is_flexible_load(d)` ---
    @test TSODSO.has_reactive_decision(therm) ==
          (therm isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(therm))
    @test TSODSO.has_reactive_decision(therm) === true # flexible load ⇒ probe-true today
    @test TSODSO.has_reactive_decision(defer) ==
          (defer isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(defer))
    @test TSODSO.has_reactive_decision(defer) === true
    @test TSODSO.has_reactive_decision(inter) ==
          (inter isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(inter))
    @test TSODSO.has_reactive_decision(inter) === true
    @test TSODSO.has_reactive_decision(pvbatt) ==
          (pvbatt isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(pvbatt))
    @test TSODSO.has_reactive_decision(pvbatt) === false # active-only DER (A3): probe-false today
    @test TSODSO.has_reactive_decision(bess) ==
          (bess isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(bess))
    @test TSODSO.has_reactive_decision(bess) === true # the isa half of the old probe

    # A8 asymmetry, reproduced BY CONSTRUCTION and asserted NAMED: FixedCapacitor
    # carries `q_inject` (a constant nameplate injection) but the old probe never
    # matched it — its reactive belongs to the constant `-Pdc·tanφ` draw, not a
    # decision. The trait MUST stay `false` or every `:ieee8500*` reactive
    # consensus default flips.
    @test TSODSO.has_reactive_decision(fc) === false
    @test TSODSO.has_reactive_decision(fc) ==
          (fc isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(fc))

    # --- storage_kind: :battery (PVBattery) / :four_quadrant (FourQuadBESS) / :none ---
    @test TSODSO.storage_kind(therm) === :none
    @test TSODSO.storage_kind(defer) === :none
    @test TSODSO.storage_kind(inter) === :none
    @test TSODSO.storage_kind(pvbatt) === :battery
    @test TSODSO.storage_kind(bess) === :four_quadrant
    @test TSODSO.storage_kind(fc) === :none

    # The trait is also readable off the TYPE (what the type-paired stash
    # `agg_device_types` stores): instance reads forward to the type-level
    # method, so there is exactly ONE override point per device class.
    @test TSODSO.storage_kind(typeof(pvbatt)) === :battery
    @test TSODSO.storage_kind(typeof(bess)) === :four_quadrant
    @test TSODSO.storage_kind(typeof(therm)) === :none
end

@testitem "device traits: reactive-default resolution unchanged on existing fixture populations" tags =
    [:device, :traits] setup = [TwoBusFixtures] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    Th = TwoBusFixtures.T

    # Fixture-level trait equivalence FIRST: every member of both existing
    # fixture populations classifies exactly as the old probe did.
    aggs_live = TwoBusFixtures.build_two_bus_aggregators(feeder) # Thermostatic+Deferrable: probe-true
    aggs_off = TwoBusFixtures.build_two_bus_aggregators_no_flex(feeder) # PVBattery-only: probe-false
    for agg in (aggs_live..., aggs_off...)
        for dv in agg.devices
            @test TSODSO.has_reactive_decision(dv) ==
                  (dv isa TSODSO.FourQuadBESS || TSODSO.is_flexible_load(dv))
        end
    end

    # The ADMM smart default routes through the shared probe (`_default_reactive_consensus`
    # delegates to `_any_flexible_reactive`): LIVE iff any member is probe-true.
    @test TSODSO._default_reactive_consensus(aggs_live) === ReactiveMode.LIVE
    @test TSODSO._default_reactive_consensus(aggs_off) === ReactiveMode.OFF

    # Behavioral proof on the EXPORTED surface — solve WITHOUT an explicit
    # `reactive_consensus` kwarg and observe the RESOLVED mode plus the published
    # reactive outputs (`mu_q` is `nothing` unless LIVE ran its dual ascent).
    res_live = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs_live;
        T = Th,
        λ₀ = λ₀,
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
    )
    @test res_live.status == :converged
    @test res_live.reactive_consensus_mode === ReactiveMode.LIVE
    @test res_live.mu_q !== nothing

    res_off = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs_off;
        T = Th,
        λ₀ = λ₀,
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
    )
    @test res_off.status == :converged
    @test res_off.reactive_consensus_mode === ReactiveMode.OFF
    @test res_off.mu_q === nothing
end

@testitem "device traits: stash pairing — agg_device_types lockstep with agg_device_vars" tags =
    [:device, :traits] setup = [TwoBusFixtures, FourQuadBESSFixtures] begin
    using TSODSO, JuMP
    using TSODSO: SOCP

    # The companion stash exists on ModelContext (typed field, empty by default).
    @test :agg_device_types in fieldnames(TSODSO.ModelContext)
    @test isempty(TSODSO.ModelContext(Model()).agg_device_types)

    feeder = TwoBusFixtures.two_bus_feeder()
    Th = TwoBusFixtures.T
    solver = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)

    # (a) One real two-bus `solve_welfare` run: Thermostatic + Deferrable + PVBattery at bus 2.
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    ctx, _obj, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = TwoBusFixtures.two_bus_lambda0(),
        allow_export = true,
        optimizer = solver,
    )

    # Lockstep invariant per bus: one paired type per stashed vars entry.
    @test Set(keys(ctx.agg_device_types)) == Set(keys(ctx.agg_device_vars))
    for (bus, varlist) in ctx.agg_device_vars
        @test length(ctx.agg_device_types[bus]) == length(varlist)
    end

    # Positional pairing: device_vars[i]'s OWNER is agg_device_types[bus][i]
    # (both appended by the same per-device loop iteration).
    types2 = ctx.agg_device_types[2]
    @test length(types2) == length(ctx.agg_device_vars[2]) == 3
    @test types2[1] isa TSODSO.Thermostatic
    @test types2[2] isa TSODSO.Deferrable
    @test types2[3] isa TSODSO.PVBattery
    # Every PVBattery-derived entry pairs with storage_kind === :battery.
    for t in types2
        if t isa TSODSO.PVBattery
            @test TSODSO.storage_kind(t) === :battery
        end
    end

    # (b) The 4Q fixture: the FourQuadBESS entry pairs with :four_quadrant (the
    # `_react_outputs` publish selection), the PVBattery entry still with :battery.
    aggs4q = FourQuadBESSFixtures.build_two_bus_aggregators_4q(feeder)
    ctx4q, _obj4q, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs4q;
        T = Th,
        λ₀ = TwoBusFixtures.two_bus_lambda0(),
        allow_export = true,
        optimizer = solver,
    )
    types4q = ctx4q.agg_device_types[2]
    @test length(types4q) == length(ctx4q.agg_device_vars[2]) == 4
    @test types4q[3] isa TSODSO.PVBattery
    @test TSODSO.storage_kind(types4q[3]) === :battery
    @test types4q[4] isa TSODSO.FourQuadBESS
    @test TSODSO.storage_kind(types4q[4]) === :four_quadrant
end

@testitem "device traits: legacy shape fallback for hand-built stash contexts" tags =
    [:device, :traits] begin
    using TSODSO, JuMP

    # Hand-built test contexts (test_welfare_solve.jl / test_fourquadbess.jl
    # idioms) populate `ctx.agg_device_vars` WITHOUT any type provenance. The
    # certificates must FALL BACK to the legacy shape predicate for such entries
    # — the pre-refactor selection semantics — while production paths (which
    # always pair, see the stash-pairing item) are trait-routed.

    # Battery-shaped vars pinned at a deliberately co-activating pair of legs
    # (the test_fourquadbess.jl `pinned_ctx` idiom: EQUALITY constraints, never
    # `fix(...; force = true)`, so the certificate can still recover `upper_bound`).
    function pinned_battery_ctx()
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        T = 2
        ctx.T = T
        p_ch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = 2.0)
        p_dch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = 2.0)
        @constraint(model, [t = 1:T], p_ch[t] == 1.0)
        @constraint(model, [t = 1:T], p_dch[t] == 1.0)
        @objective(model, Max, 0.0)
        TSODSO.assert_solved!(model; dual = false, allow_local = false)
        return ctx, (; p_ch, p_dch)
    end

    # (a) NO type pairing present → the legacy shape predicate still SELECTS the
    # entry, and the battery certificate refuses the deliberate co-activation.
    ctx_a, vars_a = pinned_battery_ctx()
    append!(get!(ctx_a.agg_device_vars, 2, Vector{Any}()), [vars_a])
    @test_throws TSODSO.CertificateError TSODSO.assert_battery_complementarity!(
        ctx_a;
        τ = 1e-9,
    )

    # (b) Pairing present and the paired type's storage_kind ≠ :battery → the
    # battery certificate must SKIP the shape-matching entry (pairing overrides
    # shape — this is what will keep EV vars out of the battery certificate in 43-02).
    ctx_b, vars_b = pinned_battery_ctx()
    append!(get!(ctx_b.agg_device_vars, 2, Vector{Any}()), [vars_b])
    append!(get!(ctx_b.agg_device_types, 2, Vector{DataType}()), [TSODSO.FourQuadBESS])
    @test TSODSO.assert_battery_complementarity!(ctx_b; τ = 1e-9) === nothing
end

@testitem "device traits: OFF/CERTIFIED guard intact on the flexible-load fixture" tags =
    [:device, :traits] setup = [TwoBusFixtures] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder) # Thermostatic members are probe-true
    kw = (ρ = TwoBusFixtures.RHO_2BUS, λ₀ = TwoBusFixtures.two_bus_lambda0())

    # The smart default resolves LIVE on this population — building WITHOUT an
    # explicit `reactive_consensus` must NOT throw.
    @test TSODSO.build_dso_opt(feeder, aggs, TwoBusFixtures.T; kw...) isa DsoOpt

    # An EXPLICIT OFF override must still throw ArgumentError — the guard compares
    # the NORMALIZED mode (never the raw kwarg spelling; `normalize_reactive_mode`
    # stays in the guard path untouched).
    err = try
        TSODSO.build_dso_opt(
            feeder,
            aggs,
            TwoBusFixtures.T;
            kw...,
            reactive_consensus = ReactiveMode.OFF,
        )
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    # The guard's message names the TRAIT (the probe it replaced), not the isa-test.
    @test err isa ArgumentError && occursin("has_reactive_decision", err.msg)

    # A non-normalized `:live` Symbol spelling still throws (mode normalization discipline).
    @test_throws ArgumentError TSODSO.build_dso_opt(
        feeder,
        aggs,
        TwoBusFixtures.T;
        kw...,
        reactive_consensus = :live,
    )
end
