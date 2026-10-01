# test/test_planning_ac_recheck.jl
#
# Seam: src/planning/ac_recheck.jl (BILEV-04b infra half, plan 30-01). Two @testitems:
# a comfortably-feasible pin (expect `ok=true`, zero violations) and a pin chosen to
# overload the head branch (expect `ok=false` with a POPULATED violation report — the AC
# physics may well SOLVE at a z the SOCP oracle found MOI.INFEASIBLE under its hard
# `:smax` constraint; CONTEXT.md's policy is "reported, never thrown", so this item
# asserts the solve succeeds and the violation is surfaced, never `@test_throws`).
# Phase 30 code review (CR-02): `ok` used to be hard-coded `true`, and the overload item
# below asserted `r.ok` right next to `n_thermal_violations > 0` — locking the bug in. `ok`
# now means "no limit violated beyond the per-instance measured tolerance".

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
    # WR-09: the full p_import trajectory (length T) and the AC welfare are returned.
    @test length(r.p_import) == T
    @test isapprox(r.p_import, z; atol = 1e-6)
    @test isfinite(r.ac_welfare)
    # CR-02: the violation tolerance is measured per instance from the AC solve's own
    # primal residual (measured ~2e-9 here, 2026-10-01), never a picked constant.
    @test 0 <= r.violations.ac_primal_violation < 1e-6
    @test r.violations.violation_tol == 10 * r.violations.ac_primal_violation

    # WR-09: a z_incumbent of the wrong length is rejected before any build.
    @test_throws ArgumentError TSODSO.ac_recheck_incumbent(feeder, [agg], λ₀, T, [0.02, 0.0])
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

    # CR-02: a physically violating incumbent must NOT report ok.
    @test !r.ok
    @test r.violations.n_thermal_violations > 0
    @test r.violations.max_overload_ratio > 1.0
    @test r.raw_status == "Solve_Succeeded"
end
