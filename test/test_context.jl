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

# Seam: core/ModelContext.jl indexed residual accumulator (PF-02). Owned by plan 02-01.
@testitem "context: indexed add_to_residual! accumulates per (bus,t) as AffExpr (PF-02)" tags = [:context] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)

    # Two contributions into the same (bus=2, t=1) cell ADD (never overwrite).
    TSODSO.add_to_residual!(ctx, :Rp, 2, 1, 2.0 * p)
    TSODSO.add_to_residual!(ctx, :Rp, 2, 1, 3.0 * p)
    @test isequal_canonical(ctx.residuals[:Rp][2, 1], 5.0 * p)

    # The price-bearing residual is pinned to Matrix{AffExpr} — a non-affine term
    # entering here must fail loudly (T-02-07), so the value type is invariant.
    @test ctx.residuals[:Rp] isa Matrix{AffExpr}
end

@testitem "context: indexed add_to_residual! grows the matrix with no feeder present (PF-02)" tags = [:context] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)

    # Fresh ctx: NO ctx.meta[:feeder]. Sizing must come from the indices alone
    # (the device seam is network-agnostic).
    @test !haskey(ctx.meta, :feeder)

    TSODSO.add_to_residual!(ctx, :Rp, 2, 1, 1.0 * p)
    @test size(ctx.residuals[:Rp]) == (2, 1)

    # A later, larger index grows the matrix; previously-untouched cells are zero(AffExpr).
    TSODSO.add_to_residual!(ctx, :Rp, 3, 1, 1.0 * p)
    @test size(ctx.residuals[:Rp]) == (3, 1)
    @test isequal_canonical(ctx.residuals[:Rp][1, 1], zero(AffExpr))
    @test isequal_canonical(ctx.residuals[:Rp][2, 1], 1.0 * p)  # preserved across growth
    @test ctx.residuals[:Rp] isa Matrix{AffExpr}
end

@testitem "context: add_to_objective! accumulates a QuadExpr and retains curvature (PF-02)" tags = [:context] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)

    a, b = 3.0, 2.0
    # Concave-quadratic utility must NOT flow through add_to_residual! (which drops
    # curvature via convert(AffExpr, ·)). It goes to the WELFARE accumulator (T-02-02).
    TSODSO.add_to_objective!(ctx, a * p - (b / 2) * p^2)
    @test haskey(ctx.meta, :objective)
    @test ctx.meta[:objective] isa QuadExpr
    # Curvature survives: the quadratic term is present (not silently linearized).
    @test !isempty(ctx.meta[:objective].terms)

    # A second call ACCUMULATES (adds) into the objective.
    TSODSO.add_to_objective!(ctx, a * p - (b / 2) * p^2)
    @test ctx.meta[:objective] isa QuadExpr
    @test isequal_canonical(ctx.meta[:objective], 2 * (a * p - (b / 2) * p^2))
end

@testitem "context: scalar add_to_residual! backward-compat preserved (PF-01)" tags = [:context] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)

    # The Phase-1 scalar seam (used by toy_dc) is unchanged: name → AffExpr accumulator.
    TSODSO.add_to_residual!(ctx, :nodal_balance, p)
    TSODSO.add_to_residual!(ctx, :nodal_balance, -1.0 * p)
    @test haskey(ctx.residuals, :nodal_balance)
    @test ctx.residuals[:nodal_balance] isa AffExpr
    @test isequal_canonical(ctx.residuals[:nodal_balance], zero(AffExpr))
end

# Seam: core/ModelContext.jl — WR-04. Mixing a SCALAR and an INDEXED accumulator on the
# same residual name must fail loudly (either direction), never silently overwrite/lose a
# contribution. Distinct names for the two kinds keep working.
@testitem "context: scalar/indexed accumulator-kind collision throws both ways (WR-04)" tags = [:context] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)

    # Indexed-then-scalar on the same name: the scalar add must refuse (not corrupt).
    ctx1 = TSODSO.ModelContext(model)
    TSODSO.add_to_residual!(ctx1, :R, 1, 1, 1.0 * p)
    @test_throws ErrorException TSODSO.add_to_residual!(ctx1, :R, 1.0 * p)

    # Scalar-then-indexed on the same name: the indexed add must refuse (not discard).
    ctx2 = TSODSO.ModelContext(model)
    TSODSO.add_to_residual!(ctx2, :R, 1.0 * p)
    @test_throws ErrorException TSODSO.add_to_residual!(ctx2, :R, 1, 1, 1.0 * p)

    # Distinct names for the two kinds still coexist cleanly.
    ctx3 = TSODSO.ModelContext(model)
    TSODSO.add_to_residual!(ctx3, :scalar_name, 1.0 * p)
    TSODSO.add_to_residual!(ctx3, :indexed_name, 1, 1, 2.0 * p)
    @test ctx3.residuals[:scalar_name] isa AffExpr
    @test ctx3.residuals[:indexed_name] isa Matrix{AffExpr}
end
