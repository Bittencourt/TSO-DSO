# Seam: powerflow/DCPowerFlow.jl + powerflow/LinDistFlow.jl (PF-02). Owned by plan 02-02.
#
# These @testitems exercise the two concrete `AbstractPowerFlow` formulations against a
# BARE `ModelContext` (no assembly, no device) — they assert only that each formulation
# writes the correct per-bus/time branch terms into the shared residual by DISPATCH:
#   - DCPowerFlow  → :Rp ONLY (active), no :Rq, no voltage.
#   - LinDistFlow  → :Rp + :Rq + squared-voltage variable + the loss-less 3.43 drop.
# The item names contain "powerflow" / "lindistflow" so the occursin filters match.

# --- Task 1: DCPowerFlow (active-only) ------------------------------------------------
@testitem "powerflow: DCPowerFlow contributes active-only :Rp per-bus residual by dispatch (PF-02)" tags =
    [:powerflow] begin
    using TSODSO, JuMP

    # 3-bus radial feeder: 1 (root) — 2 — 3.
    buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    branches =
        [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0), TSODSO.Branch(2, 3, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx = TSODSO.ModelContext(Model(TSODSO.select_optimizer(TSODSO.LP())))
    TSODSO.contribute!(TSODSO.DCPowerFlow(), ctx, feeder; T = 1)

    # Shape: :Rp is a (N buses × T) Matrix{AffExpr}; DC never allocates :Rq or voltage.
    @test ctx.residuals[:Rp] isa Matrix{AffExpr}
    @test size(ctx.residuals[:Rp]) == (3, 1)
    @test !haskey(ctx.residuals, :Rq)

    # Per-bus balance = inflow(br.to==j) − outflow(br.from==j), thesis 3.31 loss-less.
    P = ctx.model[:P]
    @test num_variables(ctx.model) == 2                      # one active flow per branch
    @test isequal_canonical(ctx.residuals[:Rp][1, 1], -P[1, 1])            # root: -outflow
    @test isequal_canonical(ctx.residuals[:Rp][2, 1], P[1, 1] - P[2, 1])   # mid: in − out
    @test isequal_canonical(ctx.residuals[:Rp][3, 1], 1.0 * P[2, 1])       # leaf: +inflow
end

@testitem "powerflow: DCPowerFlow indexes over the horizon T (per-bus, per-time) (PF-02)" tags =
    [:powerflow] begin
    using TSODSO, JuMP

    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx = TSODSO.ModelContext(Model(TSODSO.select_optimizer(TSODSO.LP())))
    TSODSO.contribute!(TSODSO.DCPowerFlow(), ctx, feeder; T = 3)

    @test size(ctx.residuals[:Rp]) == (2, 3)
    P = ctx.model[:P]
    @test isequal_canonical(ctx.residuals[:Rp][2, 3], 1.0 * P[1, 3])   # leaf inflow at t=3
end

# --- Task 2: LinDistFlow (loss-less branch flow + squared voltage) --------------------
@testitem "lindistflow: LinDistFlow contributes :Rp+:Rq, squared-voltage bounds, root fix, 3.43 drop (PF-02)" tags =
    [:lindistflow] begin
    using TSODSO, JuMP

    # 3-bus radial feeder: 1 (root) — 2 — 3.
    buses = [
        TSODSO.Bus(1, 0.90, 1.10, true),
        TSODSO.Bus(2, 0.92, 1.08, false),
        TSODSO.Bus(3, 0.93, 1.07, false),
    ]
    branches =
        [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0), TSODSO.Branch(2, 3, 0.03, 0.04, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx = TSODSO.ModelContext(Model(TSODSO.select_optimizer(TSODSO.LP())))
    TSODSO.contribute!(TSODSO.LinDistFlow(), ctx, feeder; T = 1)

    # Both active and reactive residuals are populated as (N × T) Matrix{AffExpr}.
    @test ctx.residuals[:Rp] isa Matrix{AffExpr}
    @test ctx.residuals[:Rq] isa Matrix{AffExpr}
    @test size(ctx.residuals[:Rp]) == (3, 1)
    @test size(ctx.residuals[:Rq]) == (3, 1)

    v = ctx.model[:v]
    P = ctx.model[:P]
    Q = ctx.model[:Q]

    # Root squared voltage fixed at 1.0 (= 1.0²); Pitfall 1: v is |V|².
    @test is_fixed(v[feeder.root, 1])
    @test fix_value(v[feeder.root, 1]) ≈ 1.0

    # Non-root squared voltage bounds are the SQUARE of the magnitude pu bounds (Pitfall 1).
    @test lower_bound(v[2, 1]) ≈ 0.92^2
    @test upper_bound(v[2, 1]) ≈ 1.08^2
    @test lower_bound(v[3, 1]) ≈ 0.93^2
    @test upper_bound(v[3, 1]) ≈ 1.07^2

    # Active balance inflow − outflow into :Rp (thesis 3.31), reactive into :Rq (3.32).
    @test isequal_canonical(ctx.residuals[:Rp][3, 1], 1.0 * P[2, 1])
    @test isequal_canonical(ctx.residuals[:Rq][2, 1], Q[1, 1] - Q[2, 1])

    # Loss-less voltage-drop constraint present, one per branch/time (thesis 3.43, l→0).
    @test haskey(object_dictionary(ctx.model), :vdrop)
    @test length(ctx.model[:vdrop]) == length(branches) * 1
end

@testitem "lindistflow: 2-bus loss-less identity p_import == p_load (PF-02)" tags =
    [:lindistflow] begin
    using TSODSO, JuMP

    # 2-bus radial: node 1 = frontier/root (v fixed 1.0), node 2 = load. LinDistFlow is
    # loss-less ⇒ pinning both residuals to 0 forces p_import == p_load (thesis 3.43, l→0).
    buses = [TSODSO.Bus(1, 0.90, 1.10, true), TSODSO.Bus(2, 0.90, 1.10, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx = TSODSO.ModelContext(Model(TSODSO.select_optimizer(TSODSO.LP())))
    TSODSO.contribute!(TSODSO.LinDistFlow(), ctx, feeder; T = 1)
    m = ctx.model

    # Frontier import at the root (+injection) and a fixed load at bus 2 (−injection).
    @variable(m, p_import >= 0)
    p_load = 2.0
    TSODSO.add_to_residual!(ctx, :Rp, 1, 1, p_import)
    TSODSO.add_to_residual!(ctx, :Rp, 2, 1, -p_load)

    # Close every present residual to zero (active + reactive) — no formulation branching.
    Np = length(feeder.buses)
    @constraint(m, [j = 1:Np], ctx.residuals[:Rp][j, 1] == 0)
    @constraint(m, [j = 1:Np], ctx.residuals[:Rq][j, 1] == 0)
    @objective(m, Min, p_import)

    optimize!(m)
    @test is_solved_and_feasible(m; allow_local = false)
    @test value(p_import) ≈ p_load atol = 1e-8   # loss-less identity
end
