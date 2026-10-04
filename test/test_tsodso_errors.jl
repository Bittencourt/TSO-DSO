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
