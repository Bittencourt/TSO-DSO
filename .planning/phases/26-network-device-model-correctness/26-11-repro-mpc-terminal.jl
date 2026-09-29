# .planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl
#
# Direct-script reproduction of test/test_mpc_terminal.jl's ":33" testitem body under Plan
# 26-11 Task 2's CORRECTED indexing (soc_da built over 1:(T+1), terminal target
# soc_da_bus[t+H] with NO min(...,T) clamp, soc_da_final = soc_da_bus[T+1]) — TestItemRunner
# traps under --project=. (see the gsd-plan-verify-testitemrunner-trap memory), so this script
# reconstructs the FIXED hand-rolled loop directly and asserts the SAME margin conditions the
# committed testitem checks, exiting nonzero (via `error`) if either fails. This is a REAL
# check, not a placeholder: if Task 2's edit to test/test_mpc_terminal.jl does not land the
# corrected indexing, this script's own re-implementation of that indexing still exercises the
# fixed src/models/mpc_window.jl behavior directly, so a genuine regression in the underlying
# fix (not just the test file) is caught here too.

using TSODSO
using JuMP: value, set_parameter_value, set_objective_coefficient

include("test/fixtures_phase21.jl")
using .Phase21Fixtures

feeder = Phase21Fixtures.mpc_feeder()
aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
T = Phase21Fixtures.T
H = Phase21Fixtures.H

# Non-flat, mid-horizon price spike (hour 4 of 8) — see test_mpc_terminal.jl's own file-header
# DEVIATION note for why the flat mpc_lambda0() is not used here.
λ₀ = Float64[4.0, 4.0, 4.0, 9.0, 4.0, 4.0, 4.0, 4.0]
@assert length(λ₀) == T

ctx_da, welfare_da, _ =
    solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)

# CORRECTED (Plan 26-11 Task 2): soc_da built over 1:(T+1), not 1:T (Plan 26-03's soc[T+1]).
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
    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = terminal_soc)

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
            # CORRECTED (Plan 26-11 Task 2): index t+H directly, no min(..., T) clamp — every
            # visited t satisfies t+H <= T+1 by construction of the outer loop's own bound.
            set_parameter_value(soc_handle.terminal_param, soc_da_bus[t + H])
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

# CORRECTED (Plan 26-11 Task 2): the last window's own terminal target is soc_da_bus[T+1].
soc_da_final = soc_da_bus[T + 1]

dev_disabled = abs(soc_final_disabled - soc_da_final)
dev_enabled = abs(soc_final_enabled - soc_da_final)

println(
    "MEASURED dev_disabled=", dev_disabled,
    " dev_enabled=", dev_enabled,
    " soc_da_final=", soc_da_final,
)

dev_enabled < dev_disabled ||
    error("FAIL: dev_enabled ($dev_enabled) is not < dev_disabled ($dev_disabled)")
dev_disabled > 1000 * dev_enabled ||
    error("FAIL: dev_disabled ($dev_disabled) is not > 1000x dev_enabled ($dev_enabled)")

println("OK: corrected soc_da[t+H] indexing restores the dump/hoard-prevention margin")
