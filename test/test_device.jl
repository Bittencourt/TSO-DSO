# Seam: devices/Interruptible.jl (DEV-03). Device contract + first concrete device.
#
# These items prove the device↔network decoupling (success criterion 2): the device is
# constructed and contributes with NO `Feeder` ever built. The name contains "device"
# so the `occursin("device", ti.name)` runner filter selects them.

@testitem "device: Interruptible rejects a non-concave utility (b <= 0) at construction (DEV-03)" tags = [:device] begin
    using TSODSO

    # b > 0 keeps the utility a·p − (b/2)p² concave (thesis 3.14) → convex QP welfare.
    @test TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 1.0) isa TSODSO.AbstractDevice

    # b ≤ 0 flips curvature (maximization unbounded/non-convex) → must be rejected loudly.
    @test_throws ArgumentError TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 0.0)
    @test_throws ArgumentError TSODSO.Interruptible(2, 0.0, 5.0, 4.0, -1.0)

    # Inconsistent bounds are also rejected.
    @test_throws ArgumentError TSODSO.Interruptible(2, 5.0, 0.0, 4.0, 1.0)
end

@testitem "device: Interruptible contributes a bounded var, a signed :Rp injection, and a concave QuadExpr utility — with NO feeder (DEV-03)" tags = [:device] begin
    using TSODSO, JuMP

    # A bare context: QP model, NO feeder anywhere. The device is network-agnostic.
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    @test !haskey(ctx.meta, :feeder)

    bus, Pmin, Pmax, a, b = 2, 0.0, 5.0, 4.0, 1.0
    load = TSODSO.Interruptible(bus, Pmin, Pmax, a, b)
    T = 3
    TSODSO.contribute!(load, ctx; T = T)

    # (1) A bounded served-power variable per time step: Pmin ≤ p[t] ≤ Pmax.
    vars = all_variables(model)
    @test length(vars) == T
    for v in vars
        @test has_lower_bound(v) && lower_bound(v) == Pmin
        @test has_upper_bound(v) && upper_bound(v) == Pmax
    end

    # (2) The residual grew a cell at (bus, t) and the injection is NEGATIVE (−p) —
    #     a consumed load reduces net injection (Pitfall 2, toy_dc sign convention).
    @test ctx.residuals[:Rp] isa Matrix{AffExpr}
    @test size(ctx.residuals[:Rp], 1) >= bus
    for t in 1:T
        cell = ctx.residuals[:Rp][bus, t]
        @test length(cell.terms) == 1                    # exactly one variable p[t]
        @test all(c -> c < 0, values(cell.terms))        # negative injection (−p[t])
    end

    # A no-load bus row stays zero — the device only touched its own bus.
    @test isequal_canonical(ctx.residuals[:Rp][1, 1], zero(AffExpr))

    # (3) The utility went to the WELFARE objective as a QuadExpr with curvature intact
    #     (NOT routed through the affine residual, which would drop the quadratic term).
    @test haskey(ctx.meta, :objective)
    @test ctx.meta[:objective] isa QuadExpr
    @test !isempty(ctx.meta[:objective].terms)           # quadratic term retained

    # The quadratic coefficient is −(b/2) on each p[t]^2 (concave), the linear is +a.
    obj = ctx.meta[:objective]
    @test length(obj.terms) == T                         # one p[t]^2 term per step
    @test all(c -> c == -(b / 2), values(obj.terms))     # concave: negative curvature
    @test length(obj.aff.terms) == T
    @test all(c -> c == a, values(obj.aff.terms))        # linear utility slope +a

    # The residual is strictly affine — no quadratic leaked into the price seam.
    @test all(cell -> cell isa AffExpr, ctx.residuals[:Rp])
end
