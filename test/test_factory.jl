# Seam: solver/factory.jl + solver/ProblemClass.jl.
@testitem "factory: select_optimizer(::ProblemClass) yields a working solver factory" begin
    using TSODSO, JuMP

    # ProblemClass singletons dispatch the factory; no model file names a solver.
    opt = TSODSO.select_optimizer(TSODSO.LP())
    model = Model(opt)
    @variable(model, x >= 0)
    @objective(model, Min, x)
    optimize!(model)
    @test is_solved_and_feasible(model)
end

# POP-04 additive attribute seam: `select_optimizer(::QP; attrs...)` layers caller
# attribute overrides on top of the base factory (mirroring the SOCP/NLP methods).
# No-kwarg must stay behaviorally the old one-liner (golden policy); attrs must reach
# the backend without breaking the factory.
@testitem "factory: select_optimizer(::QP) builds + solves a tiny QP, with and without attrs" begin
    using TSODSO, JuMP

    # Tiny convex QP (mirrors the LP item's model shape): min x² + x s.t. x >= 0.
    # (1) DEFAULT factory — the no-kwarg call is behaviorally the previous one-liner.
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    @variable(model, x >= 0)
    @objective(model, Min, x^2 + x)
    optimize!(model)
    @test is_solved_and_feasible(model)

    # (2) ATTRIBUTE OVERRIDES — layering Clarabel convergence tolerances must still
    # build and solve the same tiny QP (the behavioral proof that attrs reach the
    # backend; the values here are the test's own, not a src/ default).
    tight = TSODSO.select_optimizer(TSODSO.QP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
    model_t = Model(tight)
    @variable(model_t, x >= 0)
    @objective(model_t, Min, x^2 + x)
    optimize!(model_t)
    @test is_solved_and_feasible(model_t)
end
