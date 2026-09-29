# .planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl
#
# Direct-script reproduction (NOT TestItemRunner — see project memory
# gsd-plan-verify-testitemrunner-trap.md: TestItemRunner does not resolve under
# `julia --project=.`) of plan 27-09's "physics only" gap closure (USER DECISION
# 2026-09-29). Grown incrementally, one task per commit:
#
#   Task 1 (this commit): the MPC FIX-10 "physics only" settlement — the seed=1-restored
#     happy-path, forced-PV-shortfall, and mpc_step-stride items from test/test_mpc_loop.jl,
#     confirming NONE throws and the forced-PV-shortfall item's genuine head-branch overload
#     (27-07/27-08's own finding) is now REPORTED via `r.settlement_violations` instead of
#     causing a thrown `LOCALLY_INFEASIBLE`.
#   Task 2 (next commit): the FIT SITE-2 AC path + REPRO-01.
#
# Run: julia --project=. .planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl
# Exits nonzero on any test failure or uncaught exception.

using TSODSO
using Test

function main()
    @testset "27-09 Task 1: MPC happy-path (seed=1, unaffected, settlement_violations exposed)" begin
        s = Scenario(;
            name = "mpc_loop_happy",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.0,
        )
        r = run_mpc(s)
        @test r.trace.steps == r.steps
        @test r.steps == 9 - 3 + 1
        @test all(==(:certified_convex_dual), r.trace.cert_status_trace)
        @test all(isfinite, (r.day_ahead_welfare, r.realized_welfare, r.regret))
        @test isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-6)
        @test length(r.settlement_violations) == r.steps
    end

    @testset "27-09 Task 1: forced-PV-shortfall at RESTORED seed=1 — settles, REPORTS overload (never throws)" begin
        s = Scenario(;
            name = "mpc_loop_fix10_shortfall",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_step = 1,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.3,
            seed = 1,
        )
        r = run_mpc(s)   # must NOT throw under plan 27-09's physics-only settlement
        @test isfinite(r.realized_welfare)
        @test isfinite(r.forecast_settled_welfare)
        @test !isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-9)
        @test length(r.settlement_violations) == r.steps

        v5 = only(filter(v -> v.abs_hour == 5, r.settlement_violations))
        @info "27-09 forced-PV-shortfall seed=1 abs_hour=5 diagnostic" v5
        @test v5.n_thermal_violations >= 1
        @test v5.max_overload_ratio > 1.0   # the genuine head-branch overload, now REPORTED
    end

    @testset "27-09 Task 1: mpc_step stride at RESTORED seed=1 — settles at both strides" begin
        base = (;
            name = "mpc_loop_stride",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.05,
            seed = 1,
        )
        s_step1 = Scenario(; base..., mpc_step = 1)
        s_step2 = Scenario(; base..., mpc_step = 2)
        r_step1 = run_mpc(s_step1)   # must NOT throw
        r_step2 = run_mpc(s_step2)   # must NOT throw

        @test r_step1.steps == 9 - 3 + 1
        @test r_step2.steps == r_step1.steps
        @test r_step1.realized_welfare != r_step2.realized_welfare
        @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace

        s_bad = Scenario(; base..., mpc_H = 3, mpc_step = 5)
        @test_throws ArgumentError run_mpc(s_bad)
        s_free_lunch = Scenario(; base..., mpc_H = 3, mpc_step = 3)
        @test_throws ArgumentError run_mpc(s_free_lunch)
        s_long_window = Scenario(; base..., mpc_H = 12)
        @test_throws ArgumentError run_mpc(s_long_window)
    end
end

main()
