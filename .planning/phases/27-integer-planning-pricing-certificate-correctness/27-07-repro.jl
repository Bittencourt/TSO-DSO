# .planning/phases/27-integer-planning-pricing-certificate-correctness/27-07-repro.jl
#
# Plan 27-07, Task 1/2: a PLAIN `julia --project=.` script (never TestItemRunner under
# --project=., per the project's own `gsd-plan-verify-testitemrunner-trap` memory) that
# reproduces the BODIES of all 5 wave-1 post-merge failing testitems:
#
#   1. test/test_mesh_angle_certificate.jl:97  (reversed-orientation head-branch lookup)
#   2. test/test_mpc_loop.jl:444               (mpc_step stride — truth-import degenerate cone)
#   3. test/test_planning_oracle.jl:269        (planning oracle precision floor)
#   4. test/test_stochastic_welfare.jl:254     (WR-10 anchor precision floor)
#   5. test/test_thesis_repro.jl:62            (IEEE-123 fit_baseline precision floor)
#
# Each @testmodule fixture body needed is INLINED below as a plain `module ... end` (per the
# `testitem-try-scoping-trap` / `gsd-plan-verify-testitemrunner-trap` project memories — a
# `try x = ... end` inside a TestItems-wrapped body does not reach the outer binding, and
# TestItemRunner itself does not resolve under --project=.). Exits nonzero (`exit(1)`) if any
# of the 5 reproductions still fails/errors.
#
# USAGE: julia --project=. .planning/phases/27-integer-planning-pricing-certificate-correctness/27-07-repro.jl

using TSODSO
using JuMP
using Test

# ─────────────────────────────────────────────────────────────────────────────────────────
# Inlined fixture modules (plain `module`, NOT `@testmodule` — this is a script, not a
# TestItemRunner discovery run).
# ─────────────────────────────────────────────────────────────────────────────────────────

module Phase23FixturesRepro
using TSODSO

const T_MESH = 1
const LAMBDA0_MESH = 4.0
const P2_LOAD = 0.30
const P3_LOAD = 0.05
const UNIFORM_RX = [(0.01, 0.02), (0.01, 0.02), (0.01, 0.02), (0.01, 0.02)]
const HETEROGENEOUS_RX = [(0.32, 0.08), (0.08, 0.48), (0.16, 0.16), (0.24, 0.12)]

function mesh_feeder(profile::Symbol)
    rx =
        profile == :uniform ? UNIFORM_RX :
        profile == :heterogeneous ? HETEROGENEOUS_RX :
        throw(ArgumentError("mesh_feeder profile must be :uniform or :heterogeneous"))
    buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.90, 1.10, false),
        TSODSO.Bus(3, 0.90, 1.10, false),
        TSODSO.Bus(4, 0.90, 1.10, false),
    ]
    branches = [
        TSODSO.Branch(1, 2, rx[1]..., TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(1, 3, rx[2]..., TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(2, 4, rx[3]..., TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(3, 4, rx[4]..., TSODSO.SMAX_NO_LIMIT),
    ]
    return TSODSO.MeshedFeeder(buses, branches, 1)
end

function mesh_aggregators()
    therm2 = TSODSO.Thermostatic(
        2, 0.0, 1.0, 20.0, 20.0, 20.0, P2_LOAD, P2_LOAD, 0.5, [20.0]; φ = 1.0,
    )
    therm3 = TSODSO.Thermostatic(
        3, 0.0, 1.0, 20.0, 20.0, 20.0, P3_LOAD, P3_LOAD, 0.5, [20.0]; φ = 1.0,
    )
    return [
        TSODSO.Aggregator(2, 0.95, [therm2], [0.0]),
        TSODSO.Aggregator(3, 0.95, [therm3], [0.0]),
    ]
end

mesh_lambda0() = [LAMBDA0_MESH]

end # module Phase23FixturesRepro

module Phase6FixturesRepro
using TSODSO

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_2BUS = 20260719
const LOAD_SCALE_2BUS = 0.02
const PV_SCALE_2BUS = 0.005
const LAMBDA0_2BUS = 4.0

function temperature_profile()
    return Float64[
        19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19,
    ]
end

two_bus_lambda0() = fill(LAMBDA0_2BUS, T)

function two_bus_feeder()
    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 1e-3, 1e-3, TSODSO.SMAX_NO_LIMIT)]
    return TSODSO.Feeder(buses, branches, 1)
end

function build_two_bus_aggregators(feeder; seed::Integer = SEED_2BUS)
    bus = 2
    prof = TSODSO.generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[PV_SCALE_2BUS * p for p in prof.pv]
    Pdc = Float64[LOAD_SCALE_2BUS * d for d in prof.demand]

    therm = TSODSO.Thermostatic(
        bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile(),
    )
    defer = TSODSO.Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = TSODSO.PVBattery(
        bus, 0.95, 1.0, 0.1, 0.0, 0.2, 0.1, BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return [TSODSO.Aggregator(bus, 0.90, [therm, defer, batt], Pdc)]
end

end # module Phase6FixturesRepro

module Phase22FixturesRepro
using TSODSO

const T = 6
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_STOCH = 20260809
const LOAD_SCALE_STOCH = 0.02
const PV_SCALE_STOCH = 0.01
const LAMBDA0_STOCH = 4.0

function temperature_profile(Tsteps::Int = T)
    full = Float64[
        19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19,
    ]
    return Float64[full[mod1(t, length(full))] for t in 1:Tsteps]
end

stoch_lambda0(Tsteps::Int = T) = fill(LAMBDA0_STOCH, Tsteps)

function stoch_feeder()
    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 1e-3, 1e-3, TSODSO.SMAX_NO_LIMIT)]
    return TSODSO.Feeder(buses, branches, 1)
end

function stoch_scenario_aggregators(feeder, seed::Integer; Tsteps::Int = T)
    bus = 2
    prof = TSODSO.generate_profiles(seed = seed + bus, T = Tsteps)
    Ppv = Float64[PV_SCALE_STOCH * p for p in prof.pv]
    Pdc = Float64[LOAD_SCALE_STOCH * d for d in prof.demand]

    therm = TSODSO.Thermostatic(
        bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile(Tsteps),
    )
    batt = TSODSO.PVBattery(
        bus, 0.95, 1.0, 0.1 * LOAD_SCALE_STOCH, 0.0, 0.4 * LOAD_SCALE_STOCH,
        0.2 * LOAD_SCALE_STOCH, BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return [TSODSO.Aggregator(bus, 0.90, [therm, batt], Pdc)]
end

end # module Phase22FixturesRepro

module Phase7FixturesRepro
using TSODSO

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
        19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19,
    ]
end

function ieee123_lambda0()
    return Float64[
        3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
        5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
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
    prof = TSODSO.generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]

    therm = TSODSO.Thermostatic(
        bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, temperature_profile(),
    )
    defer = TSODSO.Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = TSODSO.PVBattery(
        bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return TSODSO.Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function build_ieee123_aggregators(feeder; seed::Integer = SEED_IEEE123, load_buses = nothing)
    buses = load_buses === nothing ? TSODSO.ieee123_load_nodes() : load_buses
    return [
        _house_aggregator(
            feeder, bus;
            seed = seed, φ = 0.90,
            load_scale = LOAD_SCALE_IEEE123, pv_scale = PV_SCALE_IEEE123,
            dev_scale = DEV_SCALE_IEEE123,
            batt_pmax = 0.5 * LOAD_SCALE_IEEE123, batt_emax = 2.0 * LOAD_SCALE_IEEE123,
            batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
        ) for bus in buses
    ]
end

end # module Phase7FixturesRepro

# ─────────────────────────────────────────────────────────────────────────────────────────
# Runner: each reproduction wrapped in its own @testset + outer try/catch, so an exception
# OUTSIDE a @test (exactly the wave-1 failure mode: "Got exception outside of a @test") is
# caught here and reported, without aborting the remaining reproductions.
# ─────────────────────────────────────────────────────────────────────────────────────────

const RESULTS = Vector{Tuple{String, Bool}}()

function run_repro(body::Function, name::AbstractString)
    println("\n" * "=" ^ 80)
    println("REPRO: ", name)
    println("=" ^ 80)
    ok = try
        body()
        true
    catch e
        println("ERRORED: ", name)
        showerror(stdout, e, catch_backtrace())
        println()
        false
    end
    push!(RESULTS, (String(name), ok))
    println(ok ? "RESULT: PASS ($name)" : "RESULT: FAIL ($name)")
    return ok
end

# ── 1. test_mesh_angle_certificate.jl:97 — reversed-orientation head-branch lookup ────────
run_repro("test_mesh_angle_certificate.jl:97 reversed-orientation") do
    @testset "certify_angle_recoverable!: reversed-orientation re-encoding" begin
        function reversed_mesh_feeder(profile::Symbol)
            rx =
                profile == :uniform ? Phase23FixturesRepro.UNIFORM_RX :
                Phase23FixturesRepro.HETEROGENEOUS_RX
            buses = [
                TSODSO.Bus(1, 0.95, 1.05, true),
                TSODSO.Bus(2, 0.90, 1.10, false),
                TSODSO.Bus(3, 0.90, 1.10, false),
                TSODSO.Bus(4, 0.90, 1.10, false),
            ]
            branches = [
                TSODSO.Branch(2, 1, rx[1]..., TSODSO.SMAX_NO_LIMIT),
                TSODSO.Branch(3, 1, rx[2]..., TSODSO.SMAX_NO_LIMIT),
                TSODSO.Branch(4, 2, rx[3]..., TSODSO.SMAX_NO_LIMIT),
                TSODSO.Branch(4, 3, rx[4]..., TSODSO.SMAX_NO_LIMIT),
            ]
            return TSODSO.MeshedFeeder(buses, branches, 1)
        end

        λ₀ = Phase23FixturesRepro.mesh_lambda0()
        for profile in (:uniform, :heterogeneous)
            ctx_c, _, _ = solve_welfare(
                Phase23FixturesRepro.mesh_feeder(profile),
                MeshedFlow(),
                Phase23FixturesRepro.mesh_aggregators();
                T = Phase23FixturesRepro.T_MESH,
                λ₀ = λ₀,
            )
            r_c = certify_angle_recoverable!(ctx_c; report = true)
            ctx_r, _, _ = solve_welfare(
                reversed_mesh_feeder(profile),
                MeshedFlow(),
                Phase23FixturesRepro.mesh_aggregators();
                T = Phase23FixturesRepro.T_MESH,
                λ₀ = λ₀,
            )
            r_r = certify_angle_recoverable!(ctx_r; report = true)

            @test r_r.status == r_c.status
            @test r_r.recoverable == r_c.recoverable

            rtol_resid = profile == :uniform ? 0.01 : 0.05
            @test isapprox(r_r.worst_residual, r_c.worst_residual; rtol = rtol_resid)

            if r_c.recoverable
                @test maximum(abs, r_r.angles .- r_c.angles) < 1.0e-8
            end
        end

        rbuses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.80, 1.20, false)]
        rtherm = TSODSO.Thermostatic(2, 0.0, 1.0, 20.0, 20.0, 20.0, 0.30, 0.30, 0.5, [20.0])
        raggs = [TSODSO.Aggregator(2, 0.95, [rtherm], [0.0])]
        fwd = TSODSO.Feeder(rbuses, [TSODSO.Branch(1, 2, 0.32, 0.08, TSODSO.SMAX_NO_LIMIT)], 1)
        rev = TSODSO.Feeder(rbuses, [TSODSO.Branch(2, 1, 0.32, 0.08, TSODSO.SMAX_NO_LIMIT)], 1)
        ctx_f, _, _ = solve_welfare(fwd, ConvexBranchFlow(), raggs; T = 1, λ₀ = [4.0])
        ctx_v, _, _ = solve_welfare(rev, ConvexBranchFlow(), raggs; T = 1, λ₀ = [4.0])
        r_f = certify_angle_recoverable!(ctx_f; report = true)
        r_v = certify_angle_recoverable!(ctx_v; report = true)
        @test r_f.status == :angle_certified
        @test r_v.status == :angle_certified
        @test maximum(abs, r_v.angles .- r_f.angles) < 1.0e-8
    end
end

# ── 2. test_mpc_loop.jl:444 — mpc_step stride (truth-import degenerate cone) ──────────────
run_repro("test_mpc_loop.jl:444 mpc_step stride") do
    @testset "mpc_loop: mpc_step genuinely strides the resolve cadence" begin
        # MEASURED seed=5 substitute (see test/test_mpc_loop.jl's own comment): the DEFAULT
        # seed=1 genuinely trips a non-tolerance-fixable, non-objective-fixable SOCP-exactness
        # knife-edge unrelated to this item's own D-03 intent.
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

        s_long_window = Scenario(; base..., mpc_H = 12)
        @test_throws ArgumentError run_mpc(s_long_window)

        @info "mpc_loop mpc_step stride measured difference" r_step1.realized_welfare r_step2.realized_welfare r_step1.regret r_step2.regret

        @test r_step1.realized_welfare != r_step2.realized_welfare
        @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace
    end
end

# ── 3. test_planning_oracle.jl:269 — precision floor ──────────────────────────────────────
run_repro("test_planning_oracle.jl:269 planning oracle precision floor") do
    @testset "planning oracle: ConvexBranchFlow solve runs the PF-04 exactness gate" begin
        feeder = Phase6FixturesRepro.two_bus_feeder()
        aggs = Phase6FixturesRepro.build_two_bus_aggregators(feeder)
        T = Phase6FixturesRepro.T
        λ₀ = Phase6FixturesRepro.two_bus_lambda0()

        ctx_free, _, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
        )
        zstar = value.(ctx_free.meta[:p_import])

        o = build_planning_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = T)

        @test haskey(o.ctx.meta, :pf_vars)
        @test haskey(o.ctx.meta[:pf_vars], :l)
        @test !haskey(o.ctx.meta, :socp_maxgap)

        res = solve_planning_oracle!(o, zstar)

        @test haskey(res.ctx.meta, :socp_maxgap)
        @test res.ctx.meta[:socp_maxgap] isa Float64
        @test res.ctx.meta[:socp_maxgap] < 1e-5
        @test length(res.π) == T
        @test all(isfinite, res.π)
        @test length(res.dadp) == T
        @test all(isfinite, res.dadp)
    end
end

# ── 4. test_stochastic_welfare.jl:254 — WR-10 anchor precision floor ──────────────────────
run_repro("test_stochastic_welfare.jl:254 WR-10 anchor") do
    @testset "stochastic_welfare: WR-10 anchor" begin
        feeder = Phase22FixturesRepro.stoch_feeder()
        T = Phase22FixturesRepro.T
        λ0 = Phase22FixturesRepro.stoch_lambda0()
        aggs = Phase22FixturesRepro.stoch_scenario_aggregators(
            feeder,
            sub_seed(Phase22FixturesRepro.SEED_STOCH, :wr10_anchor),
        )

        ctx_det, welfare_det, dadp_det =
            solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)
        r1 = build_stochastic_welfare(
            feeder, ConvexBranchFlow(), [aggs]; probabilities = [1.0], T = T, λ₀ = λ0,
        )
        @test isapprox(r1.welfare, welfare_det; rtol = 1e-6)
        @test all(isapprox.(r1.dadp[1], dadp_det; rtol = 1e-5, atol = 1e-8))
        @test r1.dadp[1] == r1.expected_dadp

        r2 = build_stochastic_welfare(
            feeder, ConvexBranchFlow(), [aggs, aggs]; probabilities = [0.3, 0.7], T = T, λ₀ = λ0,
        )
        @test all(isapprox.(r2.dadp[1], r2.dadp[2]; rtol = 1e-5, atol = 1e-8))
        @test all(isapprox.(r2.dadp[1], dadp_det; rtol = 1e-4, atol = 1e-7))
        @test all(isapprox.(r2.expected_dadp, r2.dadp[1]; rtol = 1e-5, atol = 1e-8))
    end
end

# ── 5. test_thesis_repro.jl:62 — IEEE-123 fit_baseline precision floor ────────────────────
run_repro("test_thesis_repro.jl:62 IEEE-123 fit_baseline") do
    @testset "thesis_repro: IEEE-123 real-impedance DADP-vs-FIT" begin
        DSO_BAND_LO = 0.0
        DSO_BAND_HI = 7.211125525764296

        feeder = ieee123_modified()
        aggs = Phase7FixturesRepro.build_ieee123_aggregators(feeder)
        Th = Phase7FixturesRepro.T
        λ₀ = Phase7FixturesRepro.ieee123_lambda0()

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

        fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀)
        fit_dso = fb.social_fit - fb.prosumer_surplus

        @test ctx.meta[:socp_maxgap] < 1e-5
        @test acct.dso > 0.0
        @test fit_dso < 0.0
        @test acct.prosumer < fb.prosumer_surplus
        @test DSO_BAND_LO < acct.dso < DSO_BAND_HI
    end
end

# ─────────────────────────────────────────────────────────────────────────────────────────
println("\n" * "=" ^ 80)
println("SUMMARY")
println("=" ^ 80)
nfail = 0
for (name, ok) in RESULTS
    println(ok ? "PASS  " : "FAIL  ", name)
    ok || (global nfail += 1)
end
println("\n$(length(RESULTS) - nfail)/$(length(RESULTS)) reproductions passed.")
exit(nfail == 0 ? 0 : 1)
