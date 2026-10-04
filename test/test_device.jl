# Seam: devices/Interruptible.jl (DEV-03). Device contract + first concrete device.
#
# These items prove the device↔network decoupling (success criterion 2): the device is
# constructed and contributes with NO `Feeder` ever built. The name contains "device"
# so the `occursin("device", ti.name)` runner filter selects them.

@testitem "device: Interruptible rejects a non-concave utility (b <= 0) at construction (DEV-03)" tags =
    [:device] begin
    using TSODSO

    # b > 0 keeps the utility a·p − (b/2)p² concave (thesis 3.14) → convex QP welfare.
    @test TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 1.0) isa TSODSO.AbstractDevice

    # b ≤ 0 flips curvature (maximization unbounded/non-convex) → must be rejected loudly.
    @test_throws ArgumentError TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 0.0)
    @test_throws ArgumentError TSODSO.Interruptible(2, 0.0, 5.0, 4.0, -1.0)

    # Inconsistent bounds are also rejected.
    @test_throws ArgumentError TSODSO.Interruptible(2, 5.0, 0.0, 4.0, 1.0)

    # IN-01: a mixed-type call (integer 0 among Float64s) promotes rather than MethodError.
    mixed = TSODSO.Interruptible(2, 0, 5.0, 4.0, 1.0)
    @test mixed isa TSODSO.Interruptible{Float64}
    @test mixed.Pmin === 0.0
end

@testitem "device: Interruptible contributes a bounded var, returns the aggregatable (; vars, p_inject, utility) contract, and writes NOTHING itself — with NO feeder (DEV-03, FIX-05)" tags =
    [:device] begin
    using TSODSO, JuMP

    # A bare context: QP model, NO feeder anywhere. The device is network-agnostic.
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    @test ctx.feeder === nothing

    bus, Pmin, Pmax, a, b = 2, 0.0, 5.0, 4.0, 1.0
    load = TSODSO.Interruptible(bus, Pmin, Pmax, a, b)
    T = 3
    res = TSODSO.contribute!(load, ctx; T = T)

    # (0) Aggregatable (Variant-2) contract: the NamedTuple shape, mirroring the
    # Deferrable/Thermostatic pattern (26-07, FIX-05) — Interruptible writes NOTHING
    # itself; the Aggregator is the sole :Rp/:Rq writer.
    @test propertynames(res) == (:vars, :p_inject, :utility)
    @test isempty(ctx.residuals)
    @test isempty(ctx.objective.terms) && iszero(ctx.objective.aff)
    @test TSODSO.is_flexible_load(load) == true

    # (1) A bounded served-power variable per time step: Pmin ≤ p[t] ≤ Pmax.
    vars = all_variables(model)
    @test length(vars) == T
    for v in vars
        @test has_lower_bound(v) && lower_bound(v) == Pmin
        @test has_upper_bound(v) && upper_bound(v) == Pmax
    end

    # (2) The returned p_inject is NEGATIVE (−p) — a consumed load reduces net
    #     injection (Pitfall 2, toy_dc sign convention).
    p = res.vars.p
    @test length(res.p_inject) == T
    for t in 1:T
        cell = res.p_inject[t]
        @test cell isa AffExpr
        @test length(cell.terms) == 1                    # exactly one variable p[t]
        @test all(c -> c < 0, values(cell.terms))        # negative injection (−p[t])
    end

    # (3) The returned utility is a QuadExpr with curvature intact (NOT an affine
    #     expression, which would drop the quadratic term).
    @test res.utility isa QuadExpr
    @test !isempty(res.utility.terms)                    # quadratic term retained

    # The quadratic coefficient is −(b/2) on each p[t]^2 (concave), the linear is +a.
    @test length(res.utility.terms) == T                 # one p[t]^2 term per step
    @test all(c -> c == -(b / 2), values(res.utility.terms))  # concave: negative curvature
    @test length(res.utility.aff.terms) == T
    @test all(c -> c == a, values(res.utility.aff.terms))     # linear utility slope +a
end
