# test/test_flake_retry.jl
#
# Unit tests for the FlakeRetry helper (test/fixtures_retry.jl) using deterministic fake
# solves. The helper is not applied to any production item here.

@testitem "flake retry: two retryable failures then success returns the value" tags = [:flake] setup =
    [FlakeRetry] begin
    using TSODSO
    using JuMP: MOI
    FlakeRetry.reset_retry_records!()
    n = Ref(0)
    f = function ()
        n[] += 1
        n[] < 3 && throw(
            TSODSO.SolveFailedError("x", MOI.NUMERICAL_ERROR, MOI.NO_SOLUTION, MOI.NO_SOLUTION, ""),
        )
        return 42.0
    end
    v = FlakeRetry.with_solve_retry(f; label = "t1")
    @test v == 42.0
    @test FlakeRetry.retry_records() == [("t1", 3)]
end

@testitem "flake retry: three failures rethrow the last error" tags = [:flake] setup = [FlakeRetry] begin
    using TSODSO
    FlakeRetry.reset_retry_records!()
    n = Ref(0)
    f = function ()
        n[] += 1
        throw(TSODSO.ConvergenceError("fail $(n[])"))
    end
    err = try
        FlakeRetry.with_solve_retry(f; label = "t2")
        nothing
    catch e
        e
    end
    @test err isa TSODSO.ConvergenceError
    @test err.msg == "fail 3"
    @test FlakeRetry.retry_records() == [("t2", 3)]
    @test_throws TSODSO.ConvergenceError FlakeRetry.with_solve_retry(f)
end

@testitem "flake retry: non-retryable errors are rethrown immediately" tags = [:flake] setup = [FlakeRetry] begin
    using TSODSO
    using JuMP: MOI
    FlakeRetry.reset_retry_records!()
    n = Ref(0)
    infeas = function ()
        n[] += 1
        throw(
            TSODSO.SolveFailedError("x", MOI.INFEASIBLE, MOI.NO_SOLUTION, MOI.NO_SOLUTION, ""),
        )
    end
    @test_throws TSODSO.SolveFailedError FlakeRetry.with_solve_retry(infeas; label = "inf")
    @test n[] == 1
    m = Ref(0)
    other = function ()
        m[] += 1
        error("boom")
    end
    @test_throws ErrorException FlakeRetry.with_solve_retry(other; label = "other")
    @test m[] == 1
    @test FlakeRetry.retry_records() == [("inf", 1), ("other", 1)]
end

@testitem "flake retry: tries and retry_on keywords are honoured" tags = [:flake] setup = [FlakeRetry] begin
    using TSODSO
    FlakeRetry.reset_retry_records!()
    n = Ref(0)
    f = function ()
        n[] += 1
        throw(TSODSO.ConvergenceError("c"))
    end
    @test_throws TSODSO.ConvergenceError FlakeRetry.with_solve_retry(f; tries = 5, label = "five")
    @test n[] == 5
    k = Ref(0)
    g = function ()
        k[] += 1
        throw(TSODSO.ConvergenceError("c"))
    end
    @test_throws TSODSO.ConvergenceError FlakeRetry.with_solve_retry(
        g;
        retry_on = (TSODSO.SolveFailedError,),
        label = "narrow",
    )
    @test k[] == 1
    @test FlakeRetry.retry_records() == [("five", 5), ("narrow", 1)]
end
