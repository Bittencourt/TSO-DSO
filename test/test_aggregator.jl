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

@testitem "aggregator: sole :Rp/:Rq writer at its bus (DEV-05, eqs. 3.21-3.23)" tags = [:aggregator] begin
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
