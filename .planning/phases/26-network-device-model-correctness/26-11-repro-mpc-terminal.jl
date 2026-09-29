# 26-11-repro-mpc-terminal.jl
#
# Direct-script reproduction of test/test_mpc_terminal.jl's
# "mpc_terminal: hard terminal-SOC condition prevents end-of-horizon dump/hoard, present when
# disabled (MPC-02)" @testitem, per this project's own executor discipline (memory
# gsd-plan-verify-testitemrunner-trap: TestItemRunner/@testmodule do not resolve under
# `julia --project=.`) — the Phase21Fixtures fixture pieces this testitem needs
# (T/H/mpc_feeder/build_mpc_aggregators/temperature_profile) are inlined verbatim below
# rather than loaded via `@testmodule`.
#
# Run: julia --project=. .planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl

using TSODSO, Test
using JuMP: value, set_parameter_value, set_objective_coefficient

# --- Phase21Fixtures pieces, inlined verbatim from test/fixtures_phase21.jl -----------------
const T = 8
const H = 3
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_MPC = 20260809
const LOAD_SCALE_MPC = 0.02
const PV_SCALE_MPC = 0.01

function temperature_profile(Tsteps::Int = T)
    full = Float64[
        19, 18, 17, 16, 16, 17,
        19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27,
        25, 23, 22, 21, 20, 19,
    ]
    return Float64[full[mod1(t, length(full))] for t in 1:Tsteps]
end

function mpc_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),
        Bus(2, 0.95, 1.05, false),
    ]
    branches = [
        Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),
    ]
    return Feeder(buses, branches, 1)
end

function _mpc_house_aggregator(
    feeder,
    bus;
    seed::Integer,
    φ::Real,
    pv_scale::Real,
    load_scale::Real,
    batt_pmax::Real,
    batt_emax::Real,
    batt_soc0::Real,
    Tsteps::Int,
)
    prof = generate_profiles(seed = seed + bus, T = Tsteps)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]

    therm = Thermostatic(
        bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile(Tsteps),
    )
    batt = PVBattery(
        bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return Aggregator(bus, φ, [therm, batt], Pdc)
end

function build_mpc_aggregators(feeder; seed::Integer = SEED_MPC, Tsteps::Int = T)
    bus = 2
    return [
        _mpc_house_aggregator(
            feeder, bus;
            seed = seed, φ = 0.90, pv_scale = PV_SCALE_MPC, load_scale = LOAD_SCALE_MPC,
            batt_pmax = 0.1 * LOAD_SCALE_MPC, batt_emax = 0.4 * LOAD_SCALE_MPC,
            batt_soc0 = 0.2 * LOAD_SCALE_MPC, Tsteps = Tsteps,
        ),
    ]
end

# --- test_mpc_terminal.jl's own testitem body, reproduced verbatim (post-fix) --------------

feeder = mpc_feeder()
aggs = build_mpc_aggregators(feeder)

λ₀ = Float64[4.0, 4.0, 4.0, 9.0, 4.0, 4.0, 4.0, 4.0]
@assert length(λ₀) == T

ctx_da, welfare_da, _ =
    solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)
soc_da = Dict(
    bus => [value(v.soc[t]) for t in 1:(T + 1)] for
    (bus, varlist) in ctx_da.meta[:agg_device_vars] for
    v in varlist if haskey(v, :soc)
)

batt = only(d for d in aggs[1].devices if hasproperty(d, :soc0))
therm = only(d for d in aggs[1].devices if hasproperty(d, :Tin0))
bus = batt.bus
soc_da_bus = soc_da[bus]

function run_mini_loop(; terminal_soc::Bool)
    o = build_mpc_window(
        feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = terminal_soc,
    )

    soc_measured = batt.soc0
    η = batt.η
    Δt = batt.Δt

    soc_handle = only(h for h in o.ic_handles if h.kind == :soc)
    device_vars = [v for (b, varlist) in o.ctx.meta[:agg_device_vars] for v in varlist]
    batt_vars = only(v for v in device_vars if haskey(v, :soc))
    therm_vars = only(v for v in device_vars if haskey(v, :Tin0))

    for t in 1:(T - H + 1)
        set_parameter_value(soc_handle.ic_param, soc_measured)
        if terminal_soc
            set_parameter_value(
                soc_handle.terminal_param,
                soc_da_bus[t + H],
            )
        end
        set_parameter_value.(batt_vars.Ppv_param, batt.Ppv[t:(t + H - 1)])
        if H > 1
            set_parameter_value.(therm_vars.Tout_param, therm.Tout[t:(t + H - 2)])
        end
        for handle in o.agg_pdc_handles
            set_parameter_value.(handle.Pdc_param, aggs[1].Pdc[t:(t + H - 1)])
        end
        for τ in 1:H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end

        solve_mpc_window!(o)

        p_ch1 = value(batt_vars.p_ch[1])
        p_dch1 = value(batt_vars.p_dch[1])
        soc_measured = TSODSO.propagate_soc(soc_measured, p_ch1, p_dch1, η, Δt)
    end

    return soc_measured
end

soc_final_disabled = run_mini_loop(; terminal_soc = false)
soc_final_enabled = run_mini_loop(; terminal_soc = true)

soc_da_final = soc_da_bus[(T - H + 1) + H]

dev_disabled = abs(soc_final_disabled - soc_da_final)
dev_enabled = abs(soc_final_enabled - soc_da_final)

@info "mpc_terminal MPC-02 measured deviations" dev_disabled dev_enabled soc_da_final soc_final_disabled soc_final_enabled

@test dev_enabled < dev_disabled
@test dev_disabled > 1000 * dev_enabled

println("test_mpc_terminal.jl:33 REPRO: PASSED (dev_disabled=$dev_disabled, dev_enabled=$dev_enabled, ratio=$(dev_disabled / dev_enabled))")
