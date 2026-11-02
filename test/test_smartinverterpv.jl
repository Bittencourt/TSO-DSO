# Seam: devices/SmartInverterPV.jl
#
# Phase 43 plan 04 (DEV-09, DEV-10b). SmartInverterPV is PV with a smart-inverter reactive
# capability, as a SEPARATE device (the FourQuadBESS precedent; PVBattery is NOT widened):
# curtailable `pv_used[t] <= Ppv[t]` plus a sign-free `q[t]`, tied by ONE ANONYMOUS per-t
# apparent-power cone `[S_inv, pv_used[t], q[t]] in SecondOrderCone()`. Neither pv_used nor q
# carries a device utility term: both are priced ONLY through the network balances.
#
# Every item name contains "smartinverterpv" so `occursin("smartinverterpv", ti.name)` selects it.
#
# Signature under test:  SmartInverterPV(bus, S_inv, Ppv)

@testitem "smartinverterpv: constructor guards reject degenerate cone / negative profile" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    @test TSODSO.SmartInverterPV(2, 1.0, [0.0, 0.5, 1.0]) isa TSODSO.AbstractDevice
    @test TSODSO.SmartInverterPV(2, 1.0, [0.0, 0.5, 1.0]) isa TSODSO.SmartInverterPV{Float64}
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, 0.0, [0.5])
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, -1.0, [0.5])
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, 1.0, [0.5, -0.1])

    # Mixed-type call (Int S_inv, Int profile) promotes to one common type.
    mixed = TSODSO.SmartInverterPV(2, 1, [0, 1])
    @test mixed isa TSODSO.SmartInverterPV{Float64} || mixed isa TSODSO.SmartInverterPV{Int}
    mixed2 = TSODSO.SmartInverterPV(2, 1, [0.0, 1.0])
    @test mixed2 isa TSODSO.SmartInverterPV{Float64}
    @test mixed2.S_inv === 1.0
end

@testitem "smartinverterpv: contribute! widened 4-tuple contract, zero utility, no residual writes" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 4
    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(d, ctx; T = T)

    @test propertynames(res) == (:vars, :p_inject, :q_inject, :utility)
    @test res.q_inject === res.vars.q
    @test res.q_inject isa Vector{VariableRef}
    @test length(res.vars.pv_used) == T && length(res.vars.q) == T
    @test res.p_inject isa Vector{AffExpr}
    for t in 1:T
        @test res.p_inject[t] == res.vars.pv_used[t]
    end
    # Active/reactive side writes NOTHING to residuals or the objective.
    @test isempty(ctx.residuals)
    @test isempty(ctx.objective.terms)

    # Zero-utility-on-q invariant: the utility is identically zero (no term mentions q or pv_used).
    @test res.utility isa QuadExpr
    @test isempty(res.utility.terms)
    @test isempty(res.utility.aff.terms)
    @test iszero(res.utility.aff.constant)
    # q is sign-free (no bounds), pv_used only lower-bounded at 0.
    for t in 1:T
        @test !has_lower_bound(res.vars.q[t]) && !has_upper_bound(res.vars.q[t])
        @test lower_bound(res.vars.pv_used[t]) == 0.0
    end
end

@testitem "smartinverterpv: anonymity -- no named JuMP objects, two instances on one model" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 3
    mk() = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(mk(), ctx; T = T)
    @test isempty(object_dictionary(model))
    # A second instance would throw on any named-container collision.
    TSODSO.contribute!(mk(), ctx; T = T)
    @test isempty(object_dictionary(model))
    @test length(all_variables(model)) == 2 * 2T
end

@testitem "smartinverterpv: apparent-power cone binds (tight S_inv forces q support and curtailment)" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 4
    Ppv = fill(1.0, T)
    function solve_sipv(S_inv; qprice)
        d = TSODSO.SmartInverterPV(2, S_inv, Ppv)
        model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
        ctx = TSODSO.ModelContext(model)
        res = TSODSO.contribute!(d, ctx; T = T)
        @objective(
            model,
            Max,
            sum(1.0 * res.p_inject[t] + qprice * res.q_inject[t] for t in 1:T)
        )
        TSODSO.assert_solved!(model; dual = false, allow_local = false)
        return res
    end

    # Tight cone with a reactive value: p and q share the S_inv budget (p = q = S/sqrt(2)).
    tight = solve_sipv(0.8; qprice = 1.0)
    for t in 1:T
        p = value(tight.vars.pv_used[t])
        q = value(tight.vars.q[t])
        @test abs(q) > 1e-3
        @test p < 1.0 - 1e-3                      # curtailed below availability
        @test p^2 + q^2 ≈ 0.8^2 atol = 1e-5       # cone binds
    end
    # No reactive value: q relaxes to the price-neutral optimum, full PV is used.
    neutral = solve_sipv(10.0; qprice = 0.0)
    for t in 1:T
        @test value(neutral.vars.pv_used[t]) ≈ 1.0 atol = 1e-6
    end
    # Sign-free: a negative reactive price drives q negative.
    neg = solve_sipv(0.8; qprice = -1.0)
    @test all(value(neg.vars.q[t]) < -1e-3 for t in 1:T)
end

@testitem "smartinverterpv: zero binary / zero integer variables, exact variable count" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 5
    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(d, ctx; T = T)
    vars = all_variables(model)
    @test length(vars) == 2T                   # pv_used (T) + q (T)
    @test count(is_binary, vars) == 0
    @test count(is_integer, vars) == 0
end

@testitem "smartinverterpv: profile shorter than horizon throws at contribute!" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 6
    ctx() = TSODSO.ModelContext(Model())
    @test_throws ArgumentError TSODSO.contribute!(
        TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T - 1)),
        ctx();
        T = T,
    )
    @test TSODSO.contribute!(
        TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T)),
        ctx();
        T = T,
    ) isa NamedTuple
end

@testitem "smartinverterpv: classification -- reactive decision yes, flexible load no" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, 3))
    @test TSODSO.has_reactive_decision(d) === true
    @test TSODSO.is_flexible_load(d) === false
    @test TSODSO.storage_kind(d) === :none

    # Aggregator roll-up: q_inject enters :Rq (+1 coefficient) via the existing hasproperty branch,
    # with NO power-factor term on the PV's own active injection (not a flexible load).
    T = 3
    agg = TSODSO.Aggregator(2, 0.9, [d], zeros(T))
    ctx = TSODSO.ModelContext(Model())
    TSODSO.contribute!(agg, ctx; T = T)
    Rq = ctx.residuals[:Rq]
    q = ctx.agg_device_vars[2][1].q
    p = ctx.agg_device_vars[2][1].pv_used
    for t in 1:T
        @test get(Rq[2, t].terms, q[t], 0.0) ≈ 1.0 atol = 1e-12
        @test get(Rq[2, t].terms, p[t], 0.0) == 0.0
    end
end
