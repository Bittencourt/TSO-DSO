# Seam: devices/Aggregator.jl (DEV-05). Aggregator roll-up, the network-facing writer.
#
# Plan 03-05 turns this green: the `Aggregator` rolls its member devices into ONE
# nodal net active injection, ONE nodal net reactive injection (from its power
# factor, thesis eq. 3.23), and ONE summed utility (eq. 3.21), and is the SOLE
# :Rp/:Rq writer at its bus — devices stay network-agnostic. The name contains
# "aggregator" so `occursin("aggregator", ti.name)` selects it.

@testitem "aggregator: roll-up type exists (DEV-05)" tags = [:aggregator] begin
    using TSODSO

    # The aggregator that sums devices into nodal net P/Q + utility (3.21-3.23).
    @test isdefined(TSODSO, :Aggregator)
end

@testitem "aggregator: sole :Rp/:Rq writer at its bus (DEV-05, eqs. 3.21-3.23)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    T = 6
    bus = 2
    φ = 0.9
    Pdc = fill(0.3, T)                      # inelastic-demand parameter profile (A4)
    Tout = fill(25.0, T)                    # ambient for the thermostatic recursion
    Ppv = fill(0.2, T)                      # PV availability for the battery

    # A flexible load (aggregatable, returns terms) + a PV+battery (aggregatable).
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)

    agg = Aggregator(bus, φ, [therm, batt], Pdc)
    @test agg isa TSODSO.AbstractDevice

    # Roll the devices up on a solver-free model (unit test never solves).
    ctx = ModelContext(Model())
    res = contribute!(agg, ctx; T = T)

    Rp = ctx.residuals[:Rp]
    Rq = ctx.residuals[:Rq]
    # The indexed residual grew EXACTLY to the aggregator's bus (nothing beyond it).
    @test size(Rp) == (bus, T)
    @test size(Rq) == (bus, T)

    # ONLY agg.bus carries content; every other bus row is identically zero (devices
    # wrote nothing themselves — the aggregator is the sole network-facing writer).
    for j in 1:bus, t in 1:T
        if j == bus
            @test !iszero(Rp[j, t])
            @test !iszero(Rq[j, t])
        else
            @test iszero(Rp[j, t])
            @test iszero(Rq[j, t])
        end
    end

    # Reactive is PURELY the inelastic-demand power-factor term (DERs active-only, A3):
    # q = −P_dc·tan(arccos φ). MPC-01 (D-08) widened Pdc into a genuine Parameter
    # (Pdc_param), so this is now an AffExpr TERM referencing Pdc_param[t] with
    # coefficient −tanφ (constant 0.0) rather than a bare numeric constant — the
    # byte-identical-default invariant is on the EVALUATED value (Parameter defaults to
    # the exact prior literal `Pdc[t]`), not on the raw `.constant`/`.terms` shape.
    tanφ = sqrt(1 - φ^2) / φ
    for t in 1:T
        @test isapprox(Rq[bus, t].constant, 0.0; atol = 1e-9)
        @test isapprox(get(Rq[bus, t].terms, res.Pdc_param[t], 0.0), -tanφ; atol = 1e-9)
        @test isapprox(parameter_value(res.Pdc_param[t]), Pdc[t]; atol = 1e-9)
    end

    # The summed device utility reached the QuadExpr welfare accumulator (3.21).
    @test ctx.objective isa QuadExpr
    @test res.utility isa QuadExpr

    # Device vars stashed for the post-solve battery-complementarity check, keyed by bus,
    # and the battery's charge/discharge variables are reachable.
    @test !isempty(ctx.agg_device_vars)
    @test any(v -> haskey(v, :p_ch) && haskey(v, :p_dch), ctx.agg_device_vars[bus])
end

@testitem "aggregator: reactive_factor helper single-sources tan(acos φ) (IN-01)" tags =
    [:aggregator] begin
    using TSODSO
    using TSODSO: reactive_factor

    # The single-sourced reactive-draw factor (IN-01) equals tan(arccos φ) = sqrt(1−φ²)/φ,
    # reused verbatim by the aggregator roll-up and both ADMM subproblems.
    @test isdefined(TSODSO, :reactive_factor)
    for φ in (0.85, 0.9, 0.95, 1.0)
        @test isapprox(reactive_factor(φ), tan(acos(φ)); atol = 1e-12)
        @test isapprox(reactive_factor(φ), sqrt(1 - φ^2) / φ; atol = 1e-12)
    end
    # Unity power factor draws zero reactive.
    @test reactive_factor(1.0) == 0.0
end

@testitem "aggregator: q_inject byte-identity (no 4Q) + FourQuadBESS summation (MESH-04, D-09/D-10)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    T = 6
    bus = 2
    φ = 0.9
    Pdc = fill(0.3, T)
    Tout = fill(25.0, T)
    Ppv = fill(0.2, T)

    # (a) BYTE-IDENTITY: a FRESH PVBattery-only aggregator — a member with NEITHER a
    # genuine `q_inject` field NOR `is_flexible_load(d) == true` (PVBattery is
    # active-only per Assumption A3), so :Rq's device-reactive contribution must be
    # zero per t. MPC-01 (D-08) widened Pdc into a genuine Parameter (Pdc_param), so the
    # inelastic-demand term is now an AffExpr TERM referencing Pdc_param[t] (coefficient
    # −tanφ, constant 0.0) rather than a bare numeric constant — the byte-identical-
    # default invariant is on the EVALUATED value (Pdc_param defaults to the exact prior
    # literal Pdc[t]), not on the raw `.constant`/`.terms` shape.
    #
    # DEVIATION (FIX-05, plan 26-04): this sub-case previously used a Thermostatic +
    # PVBattery pair (mirroring the "sole :Rp/:Rq writer" fixture). Since FIX-05 makes
    # `is_flexible_load(::Thermostatic) == true`, a Thermostatic member NOW correctly
    # draws q = p*tanφ into q_inject (thesis eq. 3.23) — so `q_inject[t] == zero(AffExpr)`
    # is no longer the right assertion for a Thermostatic-bearing aggregator. Swapped to
    # a SECOND `PVBattery` (both active-only, neither carries `q_inject` nor is a
    # flexible load) to keep testing the ORIGINAL "no q_inject field present" byte-
    # identity property this sub-case is actually about, independent of FIX-05's new
    # flexible-load reactive draw (covered separately by the new FIX-05 @testitem below).
    batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)
    batt2 = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)

    agg_no4q = Aggregator(bus, φ, [batt, batt2], Pdc)
    ctx_no4q = ModelContext(Model())
    res_no4q = contribute!(agg_no4q, ctx_no4q; T = T)
    Rq_no4q = ctx_no4q.residuals[:Rq]

    tanφ = sqrt(1 - φ^2) / φ
    for t in 1:T
        @test isapprox(Rq_no4q[bus, t].constant, 0.0; atol = 1e-9)
        @test isapprox(
            get(Rq_no4q[bus, t].terms, res_no4q.Pdc_param[t], 0.0),
            -tanφ;
            atol = 1e-9,
        )
        @test isapprox(parameter_value(res_no4q.Pdc_param[t]), Pdc[t]; atol = 1e-9)
        @test res_no4q.q_inject[t] == zero(AffExpr)
    end

    # (b) SUMMATION: an aggregator with a Thermostatic plus a FourQuadBESS (valid
    # asymmetric Pch_max/Pdch_max/Smax/η/λ triple) — proving the roll-up genuinely wires
    # the device's own q[t] variable into :Rq and into the returned q_inject total
    # (CR-01: tests passing != mechanism live), ADDITIVELY alongside the Thermostatic's
    # own FIX-05 power-factor reactive draw (a DIFFERENT AffExpr term, on p_therm[t] —
    # the assertions below target ONLY the q_var[t] coefficient, so they hold whether or
    # not the Thermostatic term is also present).
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    bess = FourQuadBESS(bus, 0.95, 1.0, 0.3, 0.3, 0.4, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0)

    agg_4q = Aggregator(bus, φ, [therm, bess], Pdc)
    ctx_4q = ModelContext(Model())
    res_4q = contribute!(agg_4q, ctx_4q; T = T)
    Rq_4q = ctx_4q.residuals[:Rq]

    q_var = res_4q.vars[2].q     # the FourQuadBESS's own q[t] VariableRef vector, per
    # contribute!'s (; vars = device_vars, ...) stash order
    for t in 1:T
        # Rq now carries a non-empty terms entry equal to the device's q[t] with
        # coefficient 1.0, ON TOP OF the same untouched Pdc_param[t]*(−tanφ) term (D-10).
        @test isapprox(Rq_4q[bus, t].constant, 0.0; atol = 1e-9)
        @test isapprox(
            get(Rq_4q[bus, t].terms, res_4q.Pdc_param[t], 0.0),
            -tanφ;
            atol = 1e-9,
        )
        @test !isempty(Rq_4q[bus, t].terms)
        @test isapprox(get(Rq_4q[bus, t].terms, q_var[t], 0.0), 1.0; atol = 1e-9)

        # res.q_inject is an AffExpr REFERENCING that same q[t] variable, not a numeric
        # constant — the load-bearing "genuinely wired" assertion (T-19-09).
        @test res_4q.q_inject[t] isa AffExpr
        @test isapprox(get(res_4q.q_inject[t].terms, q_var[t], 0.0), 1.0; atol = 1e-9)
    end
end

@testitem "aggregator: flexible-load members (Thermostatic/Deferrable) draw q = p*tanφ into :Rq (FIX-05)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    T = 6
    bus = 2
    φ_agg = 0.9
    φ_override = 0.75
    Tout = fill(25.0, T)
    tanφ_agg = TSODSO.reactive_factor(φ_agg)
    tanφ_override = TSODSO.reactive_factor(φ_override)

    # (1) A Thermostatic ALONE in a minimal aggregator uses the AGGREGATOR's φ (no
    # per-device override set). Its own p[t] draws q = p*tanφ into :Rq (thesis eq. 3.23,
    # FIX-05) — inspect the AffExpr terms map exactly like the q_inject byte-identity
    # item above.
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    agg_therm = Aggregator(bus, φ_agg, [therm], fill(0.0, T))
    ctx_therm = ModelContext(Model())
    res_therm = contribute!(agg_therm, ctx_therm; T = T)
    p_therm = res_therm.vars[1].p
    for t in 1:T
        @test isapprox(
            get(res_therm.q_inject[t].terms, p_therm[t], 0.0),
            -tanφ_agg;
            atol = 1e-9,
        )
    end

    # (2) A Deferrable ALONE in a minimal aggregator, same story.
    defer = Deferrable(bus, 1, T, 1.0, 1.0, 1.0)
    agg_defer = Aggregator(bus, φ_agg, [defer], fill(0.0, T))
    ctx_defer = ModelContext(Model())
    res_defer = contribute!(agg_defer, ctx_defer; T = T)
    p_defer = res_defer.vars[1].p
    for t in 1:T
        @test isapprox(
            get(res_defer.q_inject[t].terms, p_defer[t], 0.0),
            -tanφ_agg;
            atol = 1e-9,
        )
    end

    # (3) φ-OVERRIDE case: a Thermostatic with its OWN φ override inside an aggregator
    # with a DIFFERENT φ uses the device's override, not the aggregator's φ.
    therm_ov = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0,
        0.5,
        Tout;
        φ = φ_override,
    )
    agg_ov = Aggregator(bus, φ_agg, [therm_ov], fill(0.0, T))
    ctx_ov = ModelContext(Model())
    res_ov = contribute!(agg_ov, ctx_ov; T = T)
    p_therm_ov = res_ov.vars[1].p
    for t in 1:T
        @test isapprox(
            get(res_ov.q_inject[t].terms, p_therm_ov[t], 0.0),
            -tanφ_override;
            atol = 1e-9,
        )
    end
end

@testitem "aggregator: Interruptible (converted Variant-2, 26-07) draws q = p*tanφ into :Rq (FIX-05)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    T = 3
    bus = 2
    φ = 0.9
    tanφ = TSODSO.reactive_factor(φ)

    # Interruptible converted from self-injecting (Variant-1) to the aggregatable
    # Variant-2 contract in plan 26-07 — it can now sit under an Aggregator exactly like
    # Thermostatic/Deferrable, and its own consumption draws power-factor reactive power
    # (thesis eq. 3.23, FIX-05).
    load = TSODSO.Interruptible(bus, 0.0, 5.0, 4.0, 1.0)
    agg = TSODSO.Aggregator(bus, φ, [load], fill(0.0, T))
    ctx = TSODSO.ModelContext(Model())
    res = TSODSO.contribute!(agg, ctx; T = T)
    p = res.vars[1].p
    for t in 1:T
        @test isapprox(get(res.q_inject[t].terms, p[t], 0.0), -tanφ; atol = 1e-9)
    end
    @test TSODSO.is_flexible_load(load) == true
end

@testitem "aggregator: Interruptible's own φ override takes precedence over agg.φ (WR-03, phase-26 review)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    T = 3
    bus = 2
    φ_agg = 0.9
    φ_override = 0.75
    tanφ_override = TSODSO.reactive_factor(φ_override)

    # Contract parity with Thermostatic/Deferrable (test_aggregator.jl's "flexible-load
    # members ... draw q = p*tanφ" item, case 3): an Interruptible with its OWN φ override
    # inside an aggregator with a DIFFERENT φ uses the device's override, not agg.φ.
    load_ov = TSODSO.Interruptible(bus, 0.0, 5.0, 4.0, 1.0; φ = φ_override)
    @test load_ov.φ == φ_override
    agg_ov = TSODSO.Aggregator(bus, φ_agg, [load_ov], fill(0.0, T))
    ctx_ov = TSODSO.ModelContext(Model())
    res_ov = TSODSO.contribute!(agg_ov, ctx_ov; T = T)
    p_ov = res_ov.vars[1].p
    for t in 1:T
        @test isapprox(get(res_ov.q_inject[t].terms, p_ov[t], 0.0), -tanφ_override; atol = 1e-9)
    end

    # Construction-time guard parity: a supplied φ override outside (0,1] is rejected LOUDLY,
    # exactly like Thermostatic/Deferrable's own φ guard.
    @test_throws ArgumentError TSODSO.Interruptible(bus, 0.0, 5.0, 4.0, 1.0; φ = 0.0)
    @test_throws ArgumentError TSODSO.Interruptible(bus, 0.0, 5.0, 4.0, 1.0; φ = 1.5)
end

@testitem "aggregator: constructor + horizon guards (DEV-05)" tags = [:aggregator] begin
    using TSODSO
    using JuMP

    T = 6
    Tout = fill(25.0, T)
    therm = Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    Pdc = fill(0.3, T)

    # φ must lie in (0, 1] (thesis eq. 3.23 power factor).
    @test_throws ArgumentError Aggregator(2, 1.2, [therm], Pdc)
    @test_throws ArgumentError Aggregator(2, 0.0, [therm], Pdc)
    # At least one member device (eqs. 3.21-3.22).
    @test_throws ArgumentError Aggregator(2, 0.9, TSODSO.AbstractDevice[], Pdc)

    # A Pdc shorter than the requested horizon fails LOUDLY at contribute! time.
    short = Aggregator(2, 0.9, [therm], fill(0.3, T - 1))
    @test_throws ArgumentError contribute!(short, ModelContext(Model()); T = T)
end

@testitem "aggregator: contribute! widens Pdc to a genuine Parameter, byte-identical default (MPC-01 seam)" tags =
    [:aggregator] begin
    using TSODSO
    using JuMP

    # Reuse the SAME literal parameters as the "sole :Rp/:Rq writer" item's fixture.
    T = 6
    bus = 2
    φ = 0.9
    Pdc = fill(0.3, T)
    Tout = fill(25.0, T)
    Ppv = fill(0.2, T)
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)
    agg = Aggregator(bus, φ, [therm, batt], Pdc)

    model = Model()
    ctx = ModelContext(model)
    res = contribute!(agg, ctx; T = T)

    # (a) Byte-identical default: every Pdc_param entry equals the ORIGINAL literal Pdc[t].
    @test all(parameter_value.(res.Pdc_param) .== Pdc)

    # (b) set_parameter_value changes the value with NO new variable/constraint added
    # (count_variable_in_set_constraints = true — test_planning_oracle.jl's idiom).
    nv0 = num_variables(model)
    nc0 = num_constraints(model; count_variable_in_set_constraints = true)
    set_parameter_value.(res.Pdc_param, fill(0.6, T))
    @test all(parameter_value.(res.Pdc_param) .== 0.6)
    @test num_variables(model) == nv0
    @test num_constraints(model; count_variable_in_set_constraints = true) == nc0

    # (c) The old literal-constant residual write is genuinely gone: :Rq's inelastic-demand
    # contribution is now an AffExpr TERM on Pdc_param[t] (constant 0.0), not a bare
    # numeric constant — the residual write mechanism is genuinely wired to the Parameter.
    tanφ = sqrt(1 - φ^2) / φ
    Rq = ctx.residuals[:Rq]
    for t in 1:T
        @test isapprox(Rq[bus, t].constant, 0.0; atol = 1e-9)
        @test isapprox(get(Rq[bus, t].terms, res.Pdc_param[t], 0.0), -tanφ; atol = 1e-9)
    end
end
