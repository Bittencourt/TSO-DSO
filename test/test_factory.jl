# Seam: solver/factory.jl + solver/ProblemClass.jl (INFRA-02). RED until plan 01-03.
@testitem "factory: select_optimizer(::ProblemClass) yields a working solver factory (INFRA-02)" begin
    using TSODSO, JuMP

    # ProblemClass singletons dispatch the factory; no model file names a solver.
    opt = TSODSO.select_optimizer(TSODSO.LP())
    model = Model(opt)
    @variable(model, x >= 0)
    @objective(model, Min, x)
    optimize!(model)
    @test is_solved_and_feasible(model)
end
