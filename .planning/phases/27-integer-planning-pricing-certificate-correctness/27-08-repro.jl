# .planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl
#
# Direct-script reproduction (NOT TestItemRunner — see project memory
# gsd-plan-verify-testitemrunner-trap.md: TestItemRunner does not resolve under
# `julia --project=.`) of every run_mpc-dependent FIX-10 testitem body from
# test/test_mpc_loop.jl, PLUS a seed=5 AC-vs-SOCP cross-check.
#
# ESCALATED FINDING (see 27-08-SUMMARY.md "Findings" for the full record): the plan's own
# instruction was to revert ALL seed=5 substitutions (made by plans 27-03/27-07 to dodge the
# OLD SOCP truth-resolve's exactness knife-edge) to the DEFAULT seed=1, since the AC
# power-flow settlement has no SOCP relaxation to be inexact. MEASURED (direct execution):
# this holds for the happy-path fixture (mpc_forecast_error=0.0, unaffected either way), but
# the forced-PV-shortfall and mpc_step-stride fixtures' DEFAULT seed=1 now throws a GENUINE
# Ipopt LOCALLY_INFEASIBLE under the strict AC settlement — confirmed (by re-solving the
# identical fixed-injection AC model with the :smax/:smax_rev thermal-limit constraints
# REMOVED, which reaches LOCALLY_SOLVED cleanly) that the realized/clipped dispatch at that
# seed genuinely exceeds the head branch's smax=0.0686 rating at BOTH ends once served by the
# TRUE (unrelaxed) l·v=P²+Q² equality — NOT a numerics/warm-start artifact, NOT fixable
# without weakening the settlement's convergence bar (LOCKED policy). Per this plan's own
# parallel_execution instructions ("do not weaken the status check — report it as an
# ESCALATION"), this script does NOT force seed=1 on those two fixtures: it reproduces the
# genuine throw at seed=1 (documenting the finding) and separately reproduces each item's
# OWN intended behavior at the RETAINED seed=5 (which MEASURABLY clears the AC settlement's
# strict LOCALLY_SOLVED gate at every applied hour on both fixtures).
#
# Run: julia --project=. .planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl
# Exits nonzero on any test failure or uncaught exception.

using TSODSO
using Test

function main()
    @testset "27-08 happy-path CI fixture (FIX-10, seed=1, unaffected)" begin
        # test_mpc_loop.jl:15-50 — UNCHANGED, seed already 1.
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
        @test isfinite(r.forecast_settled_welfare)
        @test all(isfinite, r.day_ahead_dadp)
        @test length(r.trace.dadp_trace) == r.steps

        # Zero-forecast-error byte-identity invariant (permanent regression, now AC-settled):
        # no clip engages, and the AC truth re-solve reproduces the window's own solved
        # dispatch to solver precision, since the fixed injections match what the window
        # itself balanced.
        @test isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-6)
    end

    @testset "27-08 ESCALATED FINDING: forced-PV-shortfall's default seed=1 genuinely throws under strict AC settlement" begin
        # test_mpc_loop.jl:52-.. fixture parameters, at the DEFAULT seed=1 the plan's own
        # must_haves text asked to revert to. MEASURED: this throws a genuine Ipopt
        # LOCALLY_INFEASIBLE at abs_hour=5 (see file header). Documented here as a
        # regression, not silently avoided.
        s1 = Scenario(;
            name = "mpc_loop_fix10_shortfall",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_step = 1,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.3,
            seed = 1,
        )
        err = try
            run_mpc(s1)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        msg = sprint(showerror, err)
        @test occursin("AC power-flow truth settlement", msg)
        @test occursin("abs_hour=5", msg)
        @test occursin("LOCALLY_INFEASIBLE", msg)
    end

    @testset "27-08 forced-PV-shortfall's OWN intent, exercised at the RETAINED seed=5 (FIX-10)" begin
        # test_mpc_loop.jl:52-83 body, at the RETAINED seed=5 (see file header escalation).
        s2 = Scenario(;
            name = "mpc_loop_fix10_shortfall",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_step = 1,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.3,
            seed = 5,
        )
        r2 = run_mpc(s2)

        @test isfinite(r2.realized_welfare) && isfinite(r2.forecast_settled_welfare)
        @test isfinite(r2.regret)
        # The clip + AC-settled import genuinely changed the settlement — NOT a coincidental
        # floating-point tie.
        @test !isapprox(r2.realized_welfare, r2.forecast_settled_welfare; atol = 1e-9)
    end

    @testset "27-08 true-state propagation THROWS (unaffected by the settlement-formulation change, FIX-10)" begin
        # test_mpc_loop.jl:85-135 — exercises _mpc_assert_true_state_inband directly, no
        # run_mpc / seed involved. Included here for completeness of FIX-10 coverage.
        @test isdefined(TSODSO, :_mpc_assert_true_state_inband)
        @test TSODSO._mpc_assert_true_state_inband(0.0, 0.01, 0.01, "SOC", 2, 5) === nothing
        @test TSODSO._mpc_assert_true_state_inband(0.0, 0.01 + 5e-7, 0.01, "SOC", 2, 5) ===
              nothing
        @test TSODSO._mpc_assert_true_state_inband(15.0, 22.0, 30.0, "temperature", 3, 7) ===
              nothing
        err = try
            TSODSO._mpc_assert_true_state_inband(0.0, 0.05, 0.01, "SOC", 2, 5)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        msg = sprint(showerror, err)
        @test occursin("TRUE-plant", msg)
        @test occursin("SOC", msg)
        @test occursin("bus=2", msg)
        @test occursin("abs_hour=5", msg)
        @test_throws ErrorException TSODSO._mpc_assert_true_state_inband(
            15.0,
            50.0,
            30.0,
            "temperature",
            3,
            7,
        )
    end

    @testset "27-08 ESCALATED FINDING: mpc_step-stride's default seed=1 (mpc_step=2) genuinely throws under strict AC settlement" begin
        base1 = (;
            name = "mpc_loop_stride",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.05,
            seed = 1,
        )
        # mpc_step=1 at seed=1 is fine (MEASURED); mpc_step=2 at seed=1 throws (MEASURED).
        r_step1_seed1 = run_mpc(Scenario(; base1..., mpc_step = 1))
        @test isfinite(r_step1_seed1.realized_welfare)

        err = try
            run_mpc(Scenario(; base1..., mpc_step = 2))
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        msg = sprint(showerror, err)
        @test occursin("AC power-flow truth settlement", msg)
        @test occursin("LOCALLY_INFEASIBLE", msg)
    end

    @testset "27-08 mpc_step-stride's OWN intent, exercised at the RETAINED seed=5 (D-03, checker revision 1)" begin
        # test_mpc_loop.jl:460-.. body, at the RETAINED seed=5 (see file header escalation).
        base = (;
            name = "mpc_loop_stride",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.05,
            seed = 5,
        )
        s_step1 = Scenario(; base..., mpc_step = 1)
        s_step2 = Scenario(; base..., mpc_step = 2)

        r_step1 = run_mpc(s_step1)
        r_step2 = run_mpc(s_step2)

        @test r_step1.steps == 9 - 3 + 1
        @test r_step2.steps == r_step1.steps
        @test r_step1.trace.steps == r_step1.steps
        @test r_step2.trace.steps == r_step1.steps

        s_bad = Scenario(; base..., mpc_H = 3, mpc_step = 5)
        @test_throws ArgumentError run_mpc(s_bad)

        s_free_lunch = Scenario(; base..., mpc_H = 3, mpc_step = 3)
        @test_throws ArgumentError run_mpc(s_free_lunch)

        s_long_window = Scenario(; base..., mpc_H = 12)   # T = 9 < mpc_H = 12
        @test_throws ArgumentError run_mpc(s_long_window)

        @info "mpc_loop mpc_step stride measured difference (seed=5, plan 27-08)" r_step1.realized_welfare r_step2.realized_welfare r_step1.regret r_step2.regret

        # LOAD-BEARING (D-03, checker revision 1): mpc_step must produce a genuinely different
        # closed-loop trajectory, not merely a different `steps` bookkeeping value.
        @test r_step1.realized_welfare != r_step2.realized_welfare
        @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace
    end

    @testset "27-08 seed=5 AC-vs-SOCP cross-check (SOCP re-solve independently known exact here)" begin
        # Re-uses the forced-PV-shortfall fixture at seed=5 (27-03-SUMMARY.md/27-07-SUMMARY.md:
        # MEASURED to clear the SOCP truth-resolve's assert_socp_exact! gate cleanly at
        # mpc_forecast_error=0.3). `_truth_settlement` is run_mpc's own internal test seam
        # (plan 27-08) — `:socp` reaches the SUPERSEDED reference function, `:ac` (default)
        # the production AC settlement — both over the IDENTICAL realized/clipped trajectory
        # (same seed, same forecast-error draws), so any difference is attributable ONLY to
        # the settlement formulation, not to a different random draw.
        s5 = Scenario(;
            name = "mpc_loop_fix10_shortfall",
            feeder = :ieee13,
            T = 9,
            mpc_H = 3,
            mpc_step = 1,
            mpc_terminal_soc = true,
            mpc_forecast_error = 0.3,
            seed = 5,
        )
        r5_ac = run_mpc(s5)
        r5_socp = run_mpc(s5; _truth_settlement = :socp)

        @test isfinite(r5_ac.realized_welfare)
        @test isfinite(r5_socp.realized_welfare)

        abs_diff = abs(r5_ac.realized_welfare - r5_socp.realized_welfare)
        rel_diff = abs_diff / max(abs(r5_socp.realized_welfare), 1e-12)
        @info "27-08 AC-vs-SOCP cross-check (seed=5, mpc_forecast_error=0.3)" r5_ac.realized_welfare r5_socp.realized_welfare abs_diff rel_diff

        # MEASURED tolerance (recorded in 27-08-SUMMARY.md): on this fixture, at a seed where
        # the SOCP re-solve is independently known exact, the two settlements agree to within
        # solver precision (both formulations solve for the SAME unique physical operating
        # point at the SAME fixed injections whenever the SOCP relaxation happens to bind
        # tight). rtol=1e-4 is this project's own standing assert_socp_exact! default
        # (src/models/exactness.jl) reused here as the agreement bound — not a new,
        # ad-hoc tolerance.
        @test isapprox(r5_ac.realized_welfare, r5_socp.realized_welfare; rtol = 1e-4)
    end
end

main()
