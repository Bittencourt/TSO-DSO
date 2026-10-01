# test/test_planning_ac_recheck.jl
#
# Seam: src/planning/ac_recheck.jl (BILEV-04b infra half, plan 30-01). Two @testitems:
# a comfortably-feasible pin (expect `ok=true`, zero violations) and a pin chosen to
# overload the head branch (expect `ok=true` with a POPULATED violation report — the AC
# physics may well SOLVE at a z the SOCP oracle found MOI.INFEASIBLE under its hard
# `:smax` constraint; CONTEXT.md's policy is "reported, never thrown", so this item
# asserts the solve succeeds and the violation is surfaced, never `@test_throws`).

@testitem "planning ac_recheck: feasible pin reports ok with zero violations" tags =
    [:planning] begin
    using TSODSO

    T = 1
    feeder = TSODSO.ieee13_modified()
    agg = TSODSO.Aggregator(
        2,
        0.9,
        [TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))],
        [0.01],
    )
    λ₀ = [6.0]
    z = [0.02]   # comfortably inside the measured feasible-and-exact window

    r = TSODSO.ac_recheck_incumbent(feeder, [agg], λ₀, T, z)

    @test r.ok
    @test r.violations.n_thermal_violations == 0
    @test !r.violations.voltage_violated
    @test r.raw_status == "Solve_Succeeded"
end

@testitem "planning ac_recheck: a pin overloading the head branch reports (never throws) a populated violation" tags =
    [:planning] begin
    using TSODSO

    T = 1
    feeder = TSODSO.ieee13_modified()
    agg = TSODSO.Aggregator(
        2,
        0.9,
        [TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))],
        [0.01],
    )
    λ₀ = [6.0]
    # Reuses the THERMAL-infeasible-pin fixture shape from
    # test_planning_feasibility_oracle.jl (z well above the 0.0686 pu head-branch limit),
    # but ac_recheck_incumbent is called on a DIFFERENT, unconstrained-limits AC model —
    # the AC physics SOLVES even though the SOCP oracle finds this pin MOI.INFEASIBLE
    # under its hard :smax constraint. Assert the solve succeeds and the violation is
    # reported; do NOT assume a throw.
    z = [0.2]

    r = TSODSO.ac_recheck_incumbent(feeder, [agg], λ₀, T, z)

    @test r.ok
    @test r.violations.n_thermal_violations > 0
    @test r.violations.max_overload_ratio > 1.0
    @test r.raw_status == "Solve_Succeeded"
end
