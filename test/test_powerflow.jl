# Seam: powerflow/DCPowerFlow.jl + powerflow/LinDistFlow.jl (PF-02). Owned by plan 02-02.
#
# These @testitems exercise the two concrete `AbstractPowerFlow` formulations against a
# BARE `ModelContext` (no assembly, no device) — they assert only that each formulation
# writes the correct per-bus/time branch terms into the shared residual by DISPATCH:
#   - DCPowerFlow  → :Rp ONLY (active), no :Rq, no voltage.
#   - LinDistFlow  → :Rp + :Rq + squared-voltage variable + the loss-less 3.43 drop.
# The item names contain "powerflow" / "lindistflow" so the occursin filters match.

# --- Task 1: DCPowerFlow (active-only) ------------------------------------------------
@testitem "powerflow: DCPowerFlow contributes active-only :Rp per-bus residual by dispatch (PF-02)" tags = [:powerflow] begin
    using TSODSO, JuMP

    # 3-bus radial feeder: 1 (root) — 2 — 3.
    buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0), TSODSO.Branch(2, 3, 0.01, 0.01, 10.0)]
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

@testitem "powerflow: DCPowerFlow indexes over the horizon T (per-bus, per-time) (PF-02)" tags = [:powerflow] begin
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
