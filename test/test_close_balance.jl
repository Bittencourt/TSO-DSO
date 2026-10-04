# Seam: src/core/balance.jl (ARCH-04). Pre-migration constraint-order fingerprints (captured on
# the builders as they were BEFORE Plan 33-05 migrates them onto `close_balance!`) plus the
# helper-contract tests.
#
# NOTE: the stochastic extensive builder's balance constraints are currently UNNAMED and become
# `balance_p[j,t]`-named after Plan 33-05, so its fingerprint intentionally checks counts / types
# only, not names. Audit (grep `constraint_by_name` in src/ test/): no consumer looks balance
# constraints up by name on a stochastic model.

@testitem "close_balance: pre-migration fingerprint solve_welfare LinDistFlow + DC (ARCH-04)" tags =
    [:balance] setup = [Phase3Fixtures] begin
    using TSODSO
    using JuMP

    # (first/last name, first/last position, count) of each balance_* block within the full
    # constraint list. Order drift of any block changes the positions.
    function block_fp(model, prefix)
        cons = JuMP.all_constraints(model; include_variable_in_set_constraints = false)
        pos = [i for (i, c) in enumerate(cons) if startswith(JuMP.name(c), prefix)]
        isempty(pos) && return nothing
        return (
            JuMP.name(cons[first(pos)]),
            JuMP.name(cons[last(pos)]),
            first(pos),
            last(pos),
            length(pos),
            pos == collect(first(pos):last(pos)),
        )
    end

    function build(pf)
        feeder = Phase3Fixtures.small_radial_feeder()
        T = 3
        therm = Thermostatic(
            2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Phase3Fixtures.Tout[1:T],
        )
        agg = Aggregator(2, 0.9, [therm], Phase3Fixtures.Pdc[1:T])
        ctx, _, _ = solve_welfare(feeder, pf, [agg]; T = T, λ₀ = Phase3Fixtures.λ₀[1:T])
        return ctx.model
    end

    function run_all()
        return (
            lin = (block_fp(build(LinDistFlow()), "balance_p"), block_fp(build(LinDistFlow()), "balance_q")),
            dc = (block_fp(build(DCPowerFlow()), "balance_p"), block_fp(build(DCPowerFlow()), "balance_q")),
        )
    end
    fp = run_all()
    @test fp.lin[1] == ("balance_p[1,1]", "balance_p[3,3]", 10, 18, 9, true)
    @test fp.lin[2] == ("balance_q[1,1]", "balance_q[3,3]", 19, 27, 9, true)
    @test fp.dc[1] == ("balance_p[1,1]", "balance_p[3,3]", 4, 12, 9, true)
    @test fp.dc[2] === nothing      # DC leaves :Rq unclosed
end

@testitem "close_balance: pre-migration fingerprint solve_linear + mpc_window + stochastic + dso (ARCH-04)" tags =
    [:balance] setup = [Phase21Fixtures, Phase22Fixtures, Phase6Fixtures] begin
    using TSODSO
    using JuMP

    function block_fp(model, prefix)
        cons = JuMP.all_constraints(model; include_variable_in_set_constraints = false)
        pos = [i for (i, c) in enumerate(cons) if startswith(JuMP.name(c), prefix)]
        isempty(pos) && return nothing
        return (
            JuMP.name(cons[first(pos)]),
            JuMP.name(cons[last(pos)]),
            first(pos),
            last(pos),
            length(pos),
            pos == collect(first(pos):last(pos)),
        )
    end
    function type_fp(model)
        return (
            JuMP.num_constraints(model; count_variable_in_set_constraints = false),
            sort!([string(F, " in ", S) for (F, S) in JuMP.list_of_constraint_types(model) if !(F <: JuMP.VariableRef)]),
        )
    end

    function run_all()
        buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
        lf = TSODSO.Feeder(buses, [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)], 1)
        load = TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 1.0)
        ctxl, _, _ = solve_linear(lf, LinDistFlow(), [load]; T = 1, λ₀ = [2.0])
        linear = (block_fp(ctxl.model, "balance_p"), block_fp(ctxl.model, "balance_q"))

        mf = Phase21Fixtures.mpc_feeder()
        maggs = Phase21Fixtures.build_mpc_aggregators(mf)
        w = build_mpc_window(mf, ConvexBranchFlow(), maggs; H = Phase21Fixtures.H)
        mpc = (block_fp(w.model, "balance_p"), block_fp(w.model, "balance_q"))

        sf = Phase22Fixtures.stoch_feeder()
        saggs = [
            Phase22Fixtures.stoch_scenario_aggregators(
                sf, sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, k)),
            ) for k in 1:2
        ]
        r = build_stochastic_welfare(
            sf, ConvexBranchFlow(), saggs; T = Phase22Fixtures.T, λ₀ = Phase22Fixtures.stoch_lambda0(),
        )
        stoch = type_fp(r.model)

        df = Phase6Fixtures.two_bus_feeder()
        daggs = Phase6Fixtures.build_two_bus_aggregators(df)
        dso = build_dso_opt(df, daggs, Phase6Fixtures.T; ρ = Phase6Fixtures.RHO_2BUS, λ₀ = Phase6Fixtures.two_bus_lambda0())
        dsoc = (type_fp(dso.model), block_fp(dso.model, "balance_p"), block_fp(dso.model, "balance_q"))
        return (; linear, mpc, stoch, dsoc)
    end
    fp = run_all()
    @test fp.linear[1] == ("balance_p[1,1]", "balance_p[2,1]", 2, 3, 2, true)
    @test fp.linear[2] == ("balance_q[1,1]", "balance_q[2,1]", 4, 5, 2, true)
    @test fp.mpc[1] == ("balance_p[1,1]", "balance_p[2,3]", 14, 19, 6, true)
    @test fp.mpc[2] == ("balance_q[1,1]", "balance_q[2,3]", 20, 25, 6, true)
    # Stochastic extensive form: counts + type pairs only (balance constraints unnamed pre-33-05).
    @test fp.stoch[1] == 146
    @test fp.stoch[2] == [
        "JuMP.AffExpr in MathOptInterface.EqualTo{Float64}",
        "JuMP.AffExpr in MathOptInterface.LessThan{Float64}",
        "Vector{JuMP.AffExpr} in MathOptInterface.RotatedSecondOrderCone",
    ]
    @test fp.dsoc[1][1] == 168
    @test fp.dsoc[1][2] == [
        "JuMP.AffExpr in MathOptInterface.EqualTo{Float64}",
        "Vector{JuMP.AffExpr} in MathOptInterface.RotatedSecondOrderCone",
    ]
    @test fp.dsoc[2] == ("balance_p[1,1]", "balance_p[2,24]", 49, 96, 48, true)
    @test fp.dsoc[3] == ("balance_q[1,1]", "balance_q[2,24]", 97, 144, 48, true)
end

@testitem "close_balance!: contract (reactive/DC, registration, anonymous, shapes) (ARCH-04)" tags =
    [:balance] begin
    using TSODSO
    using JuMP
    const MOI = JuMP.MOI

    function mkctx(model, N, T; Rq = true)
        ctx = ModelContext(model)
        @variable(model, x[1:N, 1:T])
        ctx.residuals[:Rp] = AffExpr[1.0 * x[j, t] for j in 1:N, t in 1:T]
        Rq && (ctx.residuals[:Rq] = AffExpr[2.0 * x[j, t] for j in 1:N, t in 1:T])
        return ctx
    end

    function t1()
        m = Model()
        ctx = mkctx(m, 2, 1)
        bp, bq = close_balance!(ctx, 2, 1; reactive = true)
        @test bp isa Matrix && bq isa Matrix
        @test size(bp) == (2, 1) && size(bq) == (2, 1)
        @test ctx.constraints[:balance_p] === bp
        @test ctx.constraints[:balance_q] === bq
        @test JuMP.name(bp[2, 1]) == "balance_p[2,1]"
        @test JuMP.name(bq[2, 1]) == "balance_q[2,1]"
        co = JuMP.constraint_object(bp[1, 1])
        @test co.set isa MOI.EqualTo
        @test MOI.constant(co.set) == 0
    end
    t1()

    function t2()
        m = Model()
        ctx = mkctx(m, 2, 1)
        bp, bq = close_balance!(ctx, 2, 1; reactive = false)
        @test bq === nothing
        @test !haskey(ctx.constraints, :balance_q)
        @test haskey(ctx.constraints, :balance_p)
    end
    t2()

    function t3()
        m = Model()
        c1 = mkctx(m, 2, 1)
        c2 = ModelContext(m)
        c2.residuals[:Rp] = AffExpr[AffExpr(0.0) for j in 1:2, t in 1:1]
        close_balance!(c1, 2, 1; reactive = true)
        close_balance!(c2, 2, 1; reactive = false)
        @test !haskey(JuMP.object_dictionary(m), :balance_p)
        @test !haskey(JuMP.object_dictionary(m), :balance_q)
    end
    t3()

    function t4()
        m = Model()
        ctx = mkctx(m, 1, 1)
        e = try
            close_balance!(ctx, 2, 1; reactive = false)
            nothing
        catch err
            err
        end
        @test e isa ErrorException
        @test e.msg == "residual :Rp is (1, 1), expected (2, 1) — an index escaped the feeder"
        e = try
            close_balance!(ctx, 2, 1; reactive = false, label = "scenario 3 ")
            nothing
        catch err
            err
        end
        @test e.msg ==
              "scenario 3 residual :Rp is (1, 1), expected (2, 1) — an index escaped the feeder"
        # :Rq wrong-sized (Rp right-sized)
        ctx2 = mkctx(Model(), 2, 1)
        ctx2.residuals[:Rq] = ctx2.residuals[:Rq][1:1, :]
        e = try
            close_balance!(ctx2, 2, 1; reactive = true, label = "scenario 3 ")
            nothing
        catch err
            err
        end
        @test e.msg ==
              "scenario 3 residual :Rq is (1, 1), expected (2, 1) — an index escaped the feeder"
    end
    t4()
end
