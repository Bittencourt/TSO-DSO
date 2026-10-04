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

@testitem "planning ac_recheck: a failed AC re-check is reported on ac_report, never thrown past a converged result (WR-03 iter 2)" tags =
    [:planning] begin
    using TSODSO

    # Phase 30 code review iteration 2 (WR-03). `solve_stackelberg!` builds its
    # `ac_report` through `_incumbent_ac_report`, which must turn an Ipopt
    # non-convergence (a tooling failure of the diagnostic) into a REPORTED failure.
    # MEASURED 2026-10-01 (scratchpad fix2/probe_wr03.jl): on the single-Thermostatic
    # T=1 population (fixed 0.01 load at bus 2), the pin z = [0.0] cannot serve the load,
    # and Ipopt does not reach LOCALLY_SOLVED (ac_recheck_incumbent throws its named
    # "FAILED to reach LOCALLY_SOLVED" SolveFailedError).
    T = 1
    feeder = TSODSO.ieee13_modified()
    therm = TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    agg = TSODSO.Aggregator(2, 0.9, [therm], fill(0.01, T))

    @test_throws TSODSO.SolveFailedError TSODSO.ac_recheck_incumbent(feeder, [agg], [-1.0], T, [0.0])
    r = TSODSO._incumbent_ac_report(feeder, [agg], [-1.0], T, [0.0], 12.0)
    @test !r.ok
    @test r.raw_status == "AC_RECHECK_FAILED"
    @test r.violations === nothing && r.p_import === nothing
    @test isnan(r.ac_welfare) && isnan(r.welfare_gap)
    @test r.socp_welfare == 12.0
    @test occursin("FAILED to reach LOCALLY_SOLVED", r.error)
    # A malformed call is NOT a tooling failure: it still propagates.
    @test_throws ArgumentError TSODSO._incumbent_ac_report(feeder, [agg], [-1.0], T, [0.0, 0.0], 12.0)
end
