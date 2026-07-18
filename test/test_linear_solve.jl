# Seam: models/linear_solve.jl — the rung-1 centralized linear assembly (integration).
#
# The analytic first-price test: a 2-bus loss-less LinDistFlow fixture whose price has
# a closed form. The FOC of `max a·p − (b/2)p² − λ₀·p` is `a − b·p − λ₀ = 0`, so the
# served power is `p* = (a − λ₀)/b`; loss-less ⇒ the frontier import equals the load and
# the nodal-balance dual at the load bus (the DADP) equals the frontier price λ₀. Both
# expectations are DERIVED from the fixture coefficients in the test body (crit 3, WR-04),
# never a hard-coded magic number, and the dual sign is asserted positive (Pitfall 2).
@testitem "linear: 2-bus loss-less first price DADP=λ₀ and p*=(a−λ₀)/b (crit 3, price)" tags = [:linear] begin
    using TSODSO, JuMP

    # 2-bus radial loss-less fixture: node 1 = frontier/root (v fixed 1.0),
    # node 2 = elastic load, one small-impedance branch (within the pu tripwire band).
    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    # Utility coefficients + frontier price — the closed form below is DERIVED from these.
    a, b, λ0 = 4.0, 1.0, 2.0
    load = TSODSO.Interruptible(2, 0.0, 5.0, a, b)   # concave (b > 0), bus 2 = priced load

    ctx, obj, dadp =
        TSODSO.solve_linear(feeder, TSODSO.LinDistFlow(), [load]; T = 1, λ₀ = [λ0])

    # Closed form (NOT hard-coded): FOC a − b·p − λ₀ = 0 ⇒ p* = (a−λ₀)/b; loss-less ⇒ DADP = λ₀.
    expected_p = (a - λ0) / b        # = 2.0
    expected_dadp = λ0               # = 2.0

    @test is_solved_and_feasible(ctx.model; allow_local = false)   # OPTIMAL gate honored
    @test haskey(ctx.constraints, :balance_p)                      # active balance registered
    @test dadp[1] ≈ expected_dadp atol = 1e-6                      # DADP == λ₀ (first price)
    @test dadp[1] > 0                                              # positive = marginal cost sign

    # The served-power variable is stashed for inspection; its value is the closed form.
    p = ctx.meta[:device_vars][1]
    @test value(p[1]) ≈ expected_p atol = 1e-6                     # p* = (a−λ₀)/b
end

# Seam: models/linear_solve.jl — CR-01. A device whose `bus` exceeds the feeder is
# silently dropped from the nodal balance (its `−p` injection never gets pinned to zero),
# manufacturing welfare from power sourced nowhere. Assembly must reject it LOUDLY. This
# also re-confirms a fully valid solve still recovers welfare 2.0 / DADP 2.0.
@testitem "linear: out-of-range device bus throws; valid solve still gives welfare/DADP (CR-01)" tags = [:linear] begin
    using TSODSO, JuMP

    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    a, b, λ0 = 4.0, 1.0, 2.0
    good = TSODSO.Interruptible(2, 0.0, 5.0, a, b)     # bus 2 = valid priced load
    phantom = TSODSO.Interruptible(3, 0.0, 5.0, a, b)  # bus 3 does NOT exist (Np = 2)

    # A device at nonexistent bus 3 must throw at assembly time, not solve silently wrong.
    @test_throws ArgumentError TSODSO.solve_linear(
        feeder,
        TSODSO.LinDistFlow(),
        [good, phantom];
        T = 1,
        λ₀ = [λ0],
    )

    # A fully valid solve is unaffected: welfare = a·p − (b/2)p² − λ₀·p at p*=2 is 2.0.
    ctx, obj, dadp =
        TSODSO.solve_linear(feeder, TSODSO.LinDistFlow(), [good]; T = 1, λ₀ = [λ0])
    @test obj ≈ 2.0 atol = 1e-6                        # NOT the phantom-inflated 10.0
    @test dadp[1] ≈ 2.0 atol = 1e-6                    # DADP == λ₀
end

# Seam: models/linear_solve.jl — WR-01. An empty `devices` vector previously produced a
# bare `KeyError` on `ctx.meta[:objective]` (and a `BoundsError` on `devices[1]`). It must
# reject with a clear message instead.
@testitem "linear: empty devices vector throws a clear error (WR-01)" tags = [:linear] begin
    using TSODSO, JuMP

    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)

    @test_throws ArgumentError TSODSO.solve_linear(
        feeder,
        TSODSO.LinDistFlow(),
        TSODSO.Interruptible{Float64}[];
        T = 1,
        λ₀ = [2.0],
    )
end

# Seam: models/linear_solve.jl — WR-02. A λ₀ whose length disagrees with T must fail at
# the boundary with a clear message, not silently work only at T=1 (scalar) or BoundsError
# deep in objective assembly (short vector).
@testitem "linear: λ₀ length mismatch against T throws (WR-02)" tags = [:linear] begin
    using TSODSO, JuMP

    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]
    feeder = TSODSO.Feeder(buses, branches, 1)
    load = TSODSO.Interruptible(2, 0.0, 5.0, 4.0, 1.0)

    # T = 2 but a single-element λ₀: length mismatch must throw up front.
    @test_throws ArgumentError TSODSO.solve_linear(
        feeder,
        TSODSO.LinDistFlow(),
        [load];
        T = 2,
        λ₀ = [2.0],
    )
end
