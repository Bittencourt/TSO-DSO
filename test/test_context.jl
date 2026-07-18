# Seam: core/ModelContext.jl (PF-01 residual registry). RED until plan 01-03.
@testitem "context: ModelContext residual registry accumulates with no branching (PF-01)" begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)

    # Formulations ADD their contribution into the shared nodal-balance residual.
    TSODSO.add_to_residual!(ctx, :nodal_balance, p)
    TSODSO.add_to_residual!(ctx, :nodal_balance, -1.0 * p)
    @test haskey(ctx.residuals, :nodal_balance)

    # Constraint registry exposes handles for later dual() / DADP access.
    c = @constraint(model, p == 0)
    TSODSO.register_constraint!(ctx, :balance, c)
    @test ctx.constraints[:balance] === c
end
