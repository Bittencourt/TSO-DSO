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
