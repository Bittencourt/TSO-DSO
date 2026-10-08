# .planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl
#
# Direct-script reproduction (NOT TestItemRunner — see project memory
# gsd-plan-verify-testitemrunner-trap.md: TestItemRunner does not resolve under
# `julia --project=.`) of plan 27-09's "physics only" gap closure (USER DECISION
# 2026-09-29). Grown incrementally, one task per commit:
#
#   Task 1: the MPC FIX-10 "physics only" settlement — the seed=1-restored happy-path,
#     forced-PV-shortfall, and mpc_step-stride items from test/test_mpc_loop.jl, confirming
#     NONE throws and the forced-PV-shortfall item's genuine head-branch overload (27-07/27-08's
#     own finding) is now REPORTED via `r.settlement_violations` instead of causing a thrown
#     `LOCALLY_INFEASIBLE`.
#   Task 2 (this commit): the FIT SITE-2 AC path (a forced non-convergence via the
#     `_site2_ac_optimizer` internal test seam, plus a normal control run) and REPRO-01
#     (`test/test_thesis_repro.jl`'s primary IEEE-123 DSO-surplus sign-flip item), confirming
#     it still passes once SITE 2 is a genuine AC power flow instead of the structurally-
#     inexact fixed-dispatch SOCP re-solve (measured gap≈211/ratio≈9993 on this SAME point,
#     `27-wave2-suite.log`, the reason plan 27-09 replaces it).
#
# Phase4Fixtures/Phase7Fixtures are `@testmodule`s (TestItems), not `include`-able directly
# under `--project=.` — the small subset of their fixture code Task 2 needs is INLINED below
# (byte-identical to the corresponding `test/fixtures_phase*.jl` functions at the time of this
# plan), keeping this script self-contained per the project's TestItemRunner-trap convention.
#
# Run: julia --project=. .planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl
# Exits nonzero on any test failure or uncaught exception (~3-6 min: REPRO-01's IEEE-123 solves
# dominate the runtime).

using TSODSO
using JuMP
using Test

# --- Inlined Phase4Fixtures subset (test/fixtures_phase4.jl), Task 2 -----------------------
module ReproPhase4
using TSODSO
using TSODSO: Bus, Branch, Feeder, Thermostatic, Deferrable, PVBattery, Aggregator

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

function mem_price_profile()
    return Float64[
        3.8, 3.7, 3.6, 3.6, 3.7, 4.0,
        4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
        5.6, 5.8, 6.0, 6.8, 8.2, 9.0,
        8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
    ]
end

function temperature_profile()
    return Float64[
        19, 18, 17, 16, 16, 17,
        19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27,
        25, 23, 22, 21, 20, 19,
    ]
end

function _house_aggregator(
    feeder,
    bus;
    seed::Integer,
    φ::Real,
    pv_scale::Real = 1.0,
    load_scale::Real = 1.0,
    batt_pmax::Real = 0.5,
    batt_emax::Real = 2.0,
    batt_soc0::Real = 1.0,
)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm =
        Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile())
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        batt_pmax,
        0.0,
        batt_emax,
        batt_soc0,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function high_pv_feeder()
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    branches = [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)]
    return Feeder(buses, branches, 1)
end

function build_high_pv_aggregators(feeder; seed::Integer = 20260406, pv_scale::Real = 0.5)
    N = length(feeder.buses)
    return [
        _house_aggregator(
            feeder,
            bus;
            seed = seed,
            φ = 0.95,
            pv_scale = pv_scale,
            load_scale = 0.2,
            batt_pmax = 0.1,
            batt_emax = 0.2,
            batt_soc0 = 0.1,
        ) for bus in 2:N
    ]
end
end # module ReproPhase4

# --- Inlined Phase7Fixtures subset (test/fixtures_phase7.jl), Task 2 -----------------------
module ReproPhase7
using TSODSO
using TSODSO: Thermostatic, Deferrable, PVBattery, Aggregator

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)

function temperature_profile()
    return Float64[
        19, 18, 17, 16, 16, 17,
        19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27,
        25, 23, 22, 21, 20, 19,
    ]
end

function ieee123_lambda0()
    return Float64[
        3.8, 3.7, 3.6, 3.6, 3.7, 4.0,
        4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
        5.6, 5.8, 6.0, 6.8, 8.2, 9.0,
        8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
    ]
end

function _house_aggregator(
    feeder,
    bus;
    seed::Integer,
    φ::Real,
    pv_scale::Real = 1.0,
    load_scale::Real = 1.0,
    dev_scale::Real = 1.0,
    batt_pmax::Real = 0.5,
    batt_emax::Real = 2.0,
    batt_soc0::Real = 1.0,
)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0 * dev_scale,
        0.5,
        temperature_profile(),
    )
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        batt_pmax,
        0.0,
        batt_emax,
        batt_soc0,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function build_ieee123_aggregators(feeder; seed::Integer = SEED_IEEE123, load_buses = nothing)
    buses = load_buses === nothing ? ieee123_load_nodes() : load_buses
    return [
        _house_aggregator(
            feeder,
            bus;
            seed = seed,
            φ = 0.90,
            load_scale = LOAD_SCALE_IEEE123,
            pv_scale = PV_SCALE_IEEE123,
            dev_scale = DEV_SCALE_IEEE123,
            batt_pmax = 0.5 * LOAD_SCALE_IEEE123,
            batt_emax = 2.0 * LOAD_SCALE_IEEE123,
            batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
        ) for bus in buses
    ]
end
end # module ReproPhase7

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

    @testset "27-09 Task 2: FIT SITE-2 AC path — forced non-convergence via _site2_ac_optimizer" begin
        feeder = ReproPhase4.high_pv_feeder()
        aggs = ReproPhase4.build_high_pv_aggregators(feeder; pv_scale = 2.0)
        λ₀ = ReproPhase4.mem_price_profile()
        crippled = select_optimizer(NLP(); max_iter = 1)

        err = try
            fit_baseline(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = ReproPhase4.T,
                λ₀ = λ₀,
                on_inexact = :error,
                _site2_ac_optimizer = crippled,
            )
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("FIT AC-PF (SITE 2)", sprint(showerror, err))
        @test_throws ErrorException fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = ReproPhase4.T,
            λ₀ = λ₀,
            on_inexact = :error,
            _site2_ac_optimizer = crippled,
        )

        res = fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = ReproPhase4.T,
            λ₀ = λ₀,
            on_inexact = :report,
            _site2_ac_optimizer = crippled,
        )
        @test res.ac_status !== nothing
        @test res.ac_status != MOI.LOCALLY_SOLVED
        @test isnan(res.social_fit)
        @test isnan(res.ratio)

        @test_throws ArgumentError fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = ReproPhase4.T,
            λ₀ = λ₀,
            on_inexact = :bogus,
        )
    end

    @testset "27-09 Task 2: FIT SITE-2 AC path — normal control run converges, reports violations" begin
        feeder = ReproPhase4.high_pv_feeder()
        aggs = ReproPhase4.build_high_pv_aggregators(feeder; pv_scale = 2.0)
        λ₀ = ReproPhase4.mem_price_profile()

        ok = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = ReproPhase4.T, λ₀ = λ₀)
        @test isfinite(ok.social_fit)
        @test ok.ac_status == MOI.LOCALLY_SOLVED
        @test length(ok.ac_violations) == ReproPhase4.T
        @test ok.socp_maxgap === nothing   # ALWAYS nothing as of plan 27-09
    end

    @testset "27-09 Task 2: REPRO-01 (test_thesis_repro.jl primary item) still passes" begin
        # Golden band copied VERBATIM from test/test_thesis_repro.jl (SC-6: not re-derived
        # here — Phase 28 owns any restatement of the underlying numbers).
        DSO_BAND_LO = 0.0
        DSO_BAND_HI = 7.211125525764296

        feeder = ieee123_modified()
        aggs = ReproPhase7.build_ieee123_aggregators(feeder)
        Th = ReproPhase7.T
        λ₀ = ReproPhase7.ieee123_lambda0()

        ctx, welfare_dadp, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9),
        )
        acct = welfare_accounting(ctx; T = Th)

        fb = fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-9, tol_gap_rel = 1e-9),
        )
        fit_dso = fb.social_fit - fb.prosumer_surplus

        @info "27-09 REPRO-01 measured values" ctx.meta[:socp_maxgap] acct.dso fit_dso acct.prosumer fb.prosumer_surplus fb.ac_status

        @test ctx.meta[:socp_maxgap] < 1e-5
        @test acct.dso > 0.0
        @test fit_dso < 0.0
        @test acct.prosumer < fb.prosumer_surplus
        @test DSO_BAND_LO < acct.dso < DSO_BAND_HI
        @test fb.ac_status == MOI.LOCALLY_SOLVED
    end
end

main()
