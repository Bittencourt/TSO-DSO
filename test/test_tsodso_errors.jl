@testitem "errors: hierarchy and showerror" begin
    using TSODSO, JuMP, Test
    const MOI = JuMP.MOI

    @test isconcretetype(ErrorException)
    for T in (SolveFailedError, CertificateError, ConvergenceError)
        @test T <: TSODSOError
        @test T <: Exception
        @test !(T <: ErrorException)
    end
    for e in (SolveFailedError("boom a"), CertificateError("boom b"), ConvergenceError("boom c"))
        @test e.msg isa String
        @test sprint(showerror, e) == e.msg
    end

    s = SolveFailedError("m", Model())
    @test s.termination_status == MOI.OPTIMIZE_NOT_CALLED
    d = SolveFailedError("m")
    @test d.primal_status == MOI.NO_SOLUTION
    @test d.dual_status == MOI.NO_SOLUTION
    @test d.raw_status == ""

    @test CertificateError("x").kind === :unspecified
    @test CertificateError("x"; kind = :slack).kind === :slack
    @test CertificateError("x").iterations === nothing
    @test CertificateError("x"; kind = :socp_exact, iterations = 8).iterations == 8
    @test CertificateError("x", :slack).iterations === nothing
    @test ConvergenceError("x").iterations === nothing
    @test ConvergenceError("x"; iterations = 7).iterations == 7
end

@testitem "errors: _is_solver_failure predicate" begin
    using TSODSO, Test
    p = TSODSO._is_solver_failure
    @test p(ErrorException("x"))
    @test p(SolveFailedError("x"))
    @test p(CertificateError("x"))
    @test p(ConvergenceError("x"))
    @test !p(MethodError(sin, ()))
    @test !p(BoundsError([1], 2))
    @test !p(ArgumentError("x"))
    @test !p(KeyError(:k))
    @test !p(InterruptException())
end

@testitem "errors: assert_solved! / assert_no_slack typed throws, byte-identical text" begin
    using TSODSO, JuMP, HiGHS, Test
    const MOI = JuMP.MOI

    function _catch(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    m = Model(HiGHS.Optimizer)
    set_silent(m)
    @variable(m, x >= 0)
    @constraint(m, x <= -1)
    e = _catch(() -> assert_solved!(m))
    @test e isa SolveFailedError
    @test e.termination_status == termination_status(m)
    @test sprint(showerror, e) == e.msg
    expected =
        "Solve failed — refusing to trust results:\n" *
        "  termination_status : $(termination_status(m))\n" *
        "  primal_status      : $(primal_status(m))\n" *
        "  dual_status        : $(dual_status(m))\n" *
        "  raw_status         : $(raw_status(m))\n"
    @test e.msg == expected

    m2 = Model(HiGHS.Optimizer)
    set_silent(m2)
    @variable(m2, y >= 0)
    c = @constraint(m2, y == 1)
    @objective(m2, Min, y)
    optimize!(m2)
    # A negative atol forces the guard to trip on the (exactly satisfied) constraint.
    e2 = _catch(() -> assert_no_slack(m2, c; atol = -1.0))
    @test e2 isa CertificateError
    @test e2.kind === :no_slack
    @test startswith(e2.msg, "Hidden constraint slack detected — refusing to trust results:\n")
    @test endswith(e2.msg, "(atol = -1.0)\n")
    @test sprint(showerror, e2) == e2.msg
end

@testitem "errors: assert_socp_exact! throws CertificateError(kind = :socp_exact)" begin
    using TSODSO: SOCP
    using TSODSO, JuMP, Test

    function _catch(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T, N, B = 1, 2, 1
    model = Model(select_optimizer(SOCP()))
    @variable(model, v[1:N, 1:T])
    @variable(model, v̂[1:N, 1:T])
    @variable(model, P[1:B, 1:T])
    @variable(model, Q[1:B, 1:T])
    @variable(model, l[1:B, 1:T])
    fix.(v, 1.0; force = true)
    fix.(v̂, 1.0; force = true)
    fix.(P, 0.0; force = true)
    fix.(Q, 0.0; force = true)
    fix.(l, 1.0; force = true)
    @objective(model, Max, 0)
    optimize!(model)
    ctx = TSODSO.ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T
    ctx.pf_vars = (; v, v̂, P, Q, l)
    e = _catch(() -> TSODSO.assert_socp_exact!(ctx; rtol = 1e-4))
    @test e isa CertificateError
    @test e.kind === :socp_exact
    @test occursin("SOCP relaxation INEXACT", e.msg)
end

@testitem "errors: assert_battery_complementarity! throws CertificateError(kind = :battery); :warn does not" begin
    using TSODSO: SOCP
    using TSODSO, JuMP, Test

    function _catch(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    model = Model(select_optimizer(SOCP()))
    ctx = TSODSO.ModelContext(model)
    ctx.T = 1
    @variable(model, 0 <= p_ch[1:1] <= 1.0)
    @variable(model, 0 <= p_dch[1:1] <= 1.0)
    fix.(p_ch, 0.5; force = true)
    fix.(p_dch, 0.5; force = true)
    @objective(model, Max, 0.0)
    optimize!(model)
    append!(get!(ctx.agg_device_vars, 2, Vector{Any}()), [(; p_ch, p_dch)])
    e = _catch(() -> TSODSO.assert_battery_complementarity!(ctx; τ = 1e-6, on_violation = :error))
    @test e isa CertificateError
    @test e.kind === :battery
    @test occursin("Battery complementarity violated", e.msg)
    @test _catch(() -> TSODSO.assert_battery_complementarity!(ctx; τ = 1e-6, on_violation = :warn)) ===
          nothing
end

@testitem "errors: certify_angle_recoverable! report=true does not throw; report=false throws CertificateError(kind = :angle)" setup =
    [MeshFixtures] begin
    using TSODSO, Test

    function _catch(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    aggs = MeshFixtures.mesh_aggregators()
    λ₀ = MeshFixtures.mesh_lambda0()
    ctx, _, _ = solve_welfare(
        MeshFixtures.mesh_feeder(:heterogeneous),
        MeshedFlow(),
        aggs;
        T = MeshFixtures.T_MESH,
        λ₀ = λ₀,
    )
    @test _catch(() -> certify_angle_recoverable!(ctx; report = true)) === nothing
    e = _catch(() -> certify_angle_recoverable!(ctx; report = false))
    @test e isa CertificateError
    @test e.kind === :angle
end

@testitem "errors: solve_admm maxiter=1 throws ConvergenceError(iterations = 1)" setup =
    [TwoBusFixtures] tags = [:admm] begin
    using TSODSO, Test

    function _catch(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    e = _catch(
        () -> solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = TwoBusFixtures.T,
            λ₀ = TwoBusFixtures.two_bus_lambda0(),
            ρ = TwoBusFixtures.RHO_2BUS,
            maxiter = 1,
            tol = 1e-12,
        ),
    )
    @test e isa ConvergenceError
    @test e.iterations == 1
    @test startswith(e.msg, "solve_admm FAILED to converge")
end
