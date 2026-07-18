# Seam: core/status.jl (INFRA-03). RED until plan 01-03 fills the stub.
@testitem "status: assert_solved! passes optimal, fails loudly on non-optimal (INFRA-03)" begin
    using TSODSO, JuMP

    # An OPTIMAL solve passes the choke-point wrapper.
    ok = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(ok, x >= 0)
    @objective(ok, Min, x)
    TSODSO.assert_solved!(ok; dual = true, allow_local = false)
    @test is_solved_and_feasible(ok)

    # An infeasible model must make assert_solved! throw (refuse to trust results).
    bad = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(bad, y >= 0)
    @constraint(bad, y <= -1)   # infeasible against y >= 0
    @objective(bad, Min, y)
    @test_throws Exception TSODSO.assert_solved!(bad)
end
