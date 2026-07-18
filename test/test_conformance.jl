# Seam: interface-conformance — the DC↔LinDistFlow swap contract (PF-02, criterion 4).
#
# This is success criterion 4 made into an automated test: the SAME device vector and the
# SAME `solve_linear` call, invoked once with `DCPowerFlow()` and once with `LinDistFlow()`
# on the SHARED 2-bus loss-less fixture, must yield equal objective and equal DADP. The
# ONLY textual difference between the two solve calls is the `pf` argument — the
# `Interruptible` is constructed ONCE and passed to both solves, and `solve_linear` is not
# edited between them. This proves the device is unaware of which formulation is active and
# that the assembly's `haskey(ctx.residuals, :Rq)` is a data-driven test of registry
# CONTENTS (LinDistFlow populates :Rq, DC does not), NOT branching on the formulation type.
@testitem "conformance: DC↔LinDistFlow swap yields identical price/objective, zero edit (crit 4)" tags = [:conformance] begin
    using TSODSO, JuMP

    # Shared 2-bus loss-less fixture and a SINGLE device — constructed once, reused for both.
    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    a, b, λ0 = 4.0, 1.0, 2.0
    load = TSODSO.Interruptible(2, 0.0, 5.0, a, b)   # ONE device, unaware of the formulation

    # Identical calls — ONLY the `pf` argument differs (no edit to `load` or `solve_linear`).
    ctx_dc, obj_dc, dadp_dc =
        TSODSO.solve_linear(feeder, TSODSO.DCPowerFlow(), [load]; T = 1, λ₀ = [λ0])
    ctx_ldf, obj_ldf, dadp_ldf =
        TSODSO.solve_linear(feeder, TSODSO.LinDistFlow(), [load]; T = 1, λ₀ = [λ0])

    # The swap must leave the price and objective invariant (loss-less ⇒ same closed form).
    @test obj_dc ≈ obj_ldf atol = 1e-6
    @test dadp_dc[1] ≈ dadp_ldf[1] atol = 1e-6

    # ... and both must match the derived closed form (DADP = λ₀, p* = (a−λ₀)/b ⇒ obj too).
    expected_dadp = λ0
    expected_p = (a - λ0) / b
    expected_obj = (a * expected_p - (b / 2) * expected_p^2) - λ0 * expected_p
    @test dadp_dc[1] ≈ expected_dadp atol = 1e-6
    @test dadp_ldf[1] ≈ expected_dadp atol = 1e-6
    @test obj_dc ≈ expected_obj atol = 1e-6
    @test obj_ldf ≈ expected_obj atol = 1e-6
end
