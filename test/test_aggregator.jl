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
    # q = −P_dc·tan(arccos φ), a pure constant (no DER reactive variables).
    tanφ = sqrt(1 - φ^2) / φ
    for t in 1:T
        @test isapprox(Rq[bus, t].constant, -Pdc[t] * tanφ; atol = 1e-9)
        @test isempty(Rq[bus, t].terms)     # no reactive variables — only the constant
    end

    # The summed device utility reached the QuadExpr welfare accumulator (3.21).
    @test ctx.meta[:objective] isa QuadExpr
    @test res.utility isa QuadExpr

    # Device vars stashed for the post-solve battery-complementarity check, keyed by bus,
    # and the battery's charge/discharge variables are reachable.
    @test haskey(ctx.meta, :agg_device_vars)
    @test any(v -> haskey(v, :p_ch) && haskey(v, :p_dch), ctx.meta[:agg_device_vars][bus])
end

@testitem "aggregator: reactive_factor helper single-sources tan(acos φ) (IN-01)" tags =
    [:aggregator] begin
    using TSODSO

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

    # (a) BYTE-IDENTITY: a FRESH Thermostatic + PVBattery aggregator (mirrors the
    # existing "sole :Rp/:Rq writer" fixture exactly) — no member device carries
    # q_inject, so :Rq must stay a pure constant AND res.q_inject must be zero per t.
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)

    agg_no4q = Aggregator(bus, φ, [therm, batt], Pdc)
    ctx_no4q = ModelContext(Model())
    res_no4q = contribute!(agg_no4q, ctx_no4q; T = T)
    Rq_no4q = ctx_no4q.residuals[:Rq]

    tanφ = sqrt(1 - φ^2) / φ
    for t in 1:T
        @test isapprox(Rq_no4q[bus, t].constant, -Pdc[t] * tanφ; atol = 1e-9)
        @test isempty(Rq_no4q[bus, t].terms)
        @test res_no4q.q_inject[t] == zero(AffExpr)
    end

    # (b) SUMMATION: a SECOND aggregator at the SAME bus with the SAME Thermostatic plus
    # a FourQuadBESS (valid asymmetric Pch_max/Pdch_max/Smax/η/λ triple) — proving the
    # roll-up genuinely wires the device's own q[t] variable into :Rq and into the
    # returned q_inject total (CR-01: tests passing != mechanism live).
    bess = FourQuadBESS(bus, 0.95, 1.0, 0.3, 0.3, 0.4, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0)

    agg_4q = Aggregator(bus, φ, [therm, bess], Pdc)
    ctx_4q = ModelContext(Model())
    res_4q = contribute!(agg_4q, ctx_4q; T = T)
    Rq_4q = ctx_4q.residuals[:Rq]

    q_var = res_4q.vars[2].q     # the FourQuadBESS's own q[t] VariableRef vector, per
                                  # contribute!'s (; vars = device_vars, ...) stash order
    for t in 1:T
        # Rq now carries a non-empty terms entry equal to the device's q[t] with
        # coefficient 1.0, ON TOP OF the same untouched -Pdc[t]*tanφ constant (D-10).
        @test isapprox(Rq_4q[bus, t].constant, -Pdc[t] * tanφ; atol = 1e-9)
        @test !isempty(Rq_4q[bus, t].terms)
        @test isapprox(get(Rq_4q[bus, t].terms, q_var[t], 0.0), 1.0; atol = 1e-9)

        # res.q_inject is an AffExpr REFERENCING that same q[t] variable, not a numeric
        # constant — the load-bearing "genuinely wired" assertion (T-19-09).
        @test res_4q.q_inject[t] isa AffExpr
        @test isapprox(get(res_4q.q_inject[t].terms, q_var[t], 0.0), 1.0; atol = 1e-9)
    end
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
