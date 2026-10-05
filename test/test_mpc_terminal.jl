# test/test_mpc_terminal.jl
#
# Seam: MPC-02 (D-06) — the hard terminal-SOC condition's dump/hoard-prevention regression,
# driven directly against plan 21-03's `build_mpc_window`/`solve_mpc_window!` primitives plus
# this plan's own `propagate_soc` (D-05), BEFORE the full `run_mpc` orchestrator (plan 21-05)
# exists. Every item name contains "mpc_terminal", tagged `[:mpc_terminal]`, `setup =
# [Phase21Fixtures]`.
#
# DEVIATION (documented in 21-04-SUMMARY.md, Rule 1): the plan's own action sketch reads
# `λ₀ = Phase21Fixtures.mpc_lambda0()` (a FLAT price). Measured empirically (a standalone probe
# script, not committed), a flat price on this fixture makes BOTH the disabled and enabled
# receding-horizon loops converge to the SAME PV-driven Emax-saturated endpoint (the free PV
# charging dominates and hits the hard `Emax` cap regardless of the terminal toggle), so
# `dev_disabled`/`dev_enabled` are both ~1e-9-1e-10 solver-noise-floor numbers with NO
# measurable separation — an ambiguous, non-demonstrative margin (T-21-11's own disposition:
# widen the fixture rather than weaken the assertion). Per the plan's explicit permission to
# "widen T/H's ratio or Phase21Fixtures's battery headroom" when ambiguous, the MINIMAL widening
# used here is a non-flat, mid-horizon price SPIKE (`λ₀ = [4,4,4,9,4,4,4,4]`, hour 4 of 8) built
# locally in this test file — `Phase21Fixtures.mpc_feeder`/`build_mpc_aggregators` (the feeder,
# aggregators, battery/thermostatic headroom, and PV/demand ground truth) are all used
# VERBATIM, unmodified. A price spike that falls INSIDE one interior window but OUTSIDE the
# window immediately preceding it is exactly the informational asymmetry the terminal condition
# exists to correct: the myopic (disabled) loop's window covering the spike hour has zero
# incentive to preserve a specific SOC beyond its own end, while the day-ahead optimum (full
# horizon visibility) commits to a SPECIFIC SOC trajectory through that hour that every window
# before/after it should track. Originally measured margin (pre-FIX-04):
# `dev_disabled ≈ 9.3e-7` vs `dev_enabled ≈ 2.6e-11`, a ratio of ~35,500×.
#
# RE-MEASURED (Phase 26 plan 26-11, post-FIX-04 soc[H+1]/soc_da[t+H] retarget): this file's
# own hand-rolled loop carried the SAME stale `soc_da_bus[min(t + H - 1, T)]` index the
# 26-POSTMERGE-TRIAGE.md cluster-C fix corrects — building `soc_da` over `1:(T + 1)` and
# indexing the terminal target at `soc_da_bus[t + H]` (matching `run_mpc`'s own retarget,
# `src/experiments/mpc_loop.jl`) restores a measurable, non-noise-floor margin:
# `dev_disabled ≈ 4.36e-7` vs `dev_enabled ≈ 8.98e-11` — a ratio of ~4,851× (re-run via
# `.planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl`; live
# numbers, not assumed from any prior measurement — SC-6, no silent re-pin). Still
# comfortably above the `dev_disabled > 1000 * dev_enabled` assertion below, and
# `dev_enabled` still sits at the same ~1e-10-1e-11 solver-precision floor.

@testitem "mpc_terminal: hard terminal-SOC condition prevents end-of-horizon dump/hoard, present when disabled (MPC-02)" tags =
    [:mpc_terminal] setup = [Phase21Fixtures] begin
    using TSODSO
    using TSODSO: build_mpc_window, solve_mpc_window!
    using JuMP: value, set_parameter_value, set_objective_coefficient

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    T = Phase21Fixtures.T
    H = Phase21Fixtures.H

    # Non-flat, mid-horizon price spike (hour 4 of 8) — see file-header DEVIATION note: the
    # fixture's own flat `mpc_lambda0()` produces an ambiguous, noise-floor-only margin on this
    # feeder/aggregator pair; this is the minimal widening that makes the artifact measurable
    # without touching Phase21Fixtures' feeder/aggregator/battery-headroom shapes at all.
    λ₀ = Float64[4.0, 4.0, 4.0, 9.0, 4.0, 4.0, 4.0, 4.0]
    @assert length(λ₀) == T

    # Day-ahead perfect-foresight benchmark, solved ONCE (the RESEARCH-verified extraction idiom).
    ctx_da, welfare_da, _ =
        solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)
    # FIX-04 (Plan 26-03) retargeted build_mpc_window's terminal-condition constraint to
    # `soc[H + 1]` (the day-ahead state AFTER the window), since the battery `soc` vector is
    # now `1:(T + 1)` long. `soc_da` must therefore be built over the SAME `1:(T + 1)` range
    # so the terminal target below can be indexed at `soc_da_bus[t + H]` — never the stale
    # `soc_da_bus[min(t + H - 1, T)]` (one hour BEFORE the window's actual end), which
    # silently drives this mini-loop INFEASIBLE (26-POSTMERGE-TRIAGE.md cluster C).
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:(T + 1)] for
        (bus, varlist) in ctx_da.agg_device_vars for
        v in varlist if haskey(v, :soc)
    )

    # The fixture's single aggregator's battery device — its own `soc0`/`η`/`Δt` literals are
    # the SAME values the day-ahead solve started/propagated from.
    batt = only(d for d in aggs[1].devices if hasproperty(d, :soc0))
    therm = only(d for d in aggs[1].devices if hasproperty(d, :Tin0))
    bus = batt.bus
    soc_da_bus = soc_da[bus]

    # `run_mini_loop`: a manual receding-horizon loop driving `build_mpc_window`/
    # `solve_mpc_window!` DIRECTLY (no orchestrator exists yet) — builds the window ONCE
    # (build-once, MPC-01), re-solves it T-H+1 times via `set_parameter_value`/
    # `set_objective_coefficient`, and propagates the MEASURED SOC via `TSODSO.propagate_soc`
    # (D-05) on each step's REALIZED first-interval controls. Returns the final measured SOC.
    function run_mini_loop(; terminal_soc::Bool)
        o = build_mpc_window(
            feeder,
            ConvexBranchFlow(),
            aggs;
            H = H,
            terminal_soc = terminal_soc,
        )

        soc_measured = batt.soc0
        η = batt.η
        Δt = batt.Δt

        soc_handle = only(h for h in o.ic_handles if h.kind == :soc)
        device_vars = [v for (b, varlist) in o.ctx.agg_device_vars for v in varlist]
        batt_vars = only(v for v in device_vars if haskey(v, :soc))
        therm_vars = only(v for v in device_vars if haskey(v, :Tin0))

        for t in 1:(T - H + 1)
            set_parameter_value(soc_handle.ic_param, soc_measured)
            if terminal_soc
                # FIX-04: the window's own terminal target is soc[H + 1] (the state AFTER
                # the window, Plan 26-03); its day-ahead counterpart is soc_da_bus[t + H].
                # No min(..., T) clamp — the outer loop's own header bound (t in
                # 1:(T - H + 1)) guarantees t + H <= T + 1 at every visited t, and
                # soc_da_bus is now built over 1:(T + 1), so every index here is in-bounds
                # by construction.
                set_parameter_value(
                    soc_handle.terminal_param,
                    soc_da_bus[t + H],
                )
            end
            # TRUE ground-truth slices (no forecast error — isolate the terminal-condition
            # effect alone, per the plan's own instruction).
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

    # The day-ahead trajectory's value at the LAST window's terminal hour — the reference the
    # enabled case is pinned toward (algebraically soc_da_bus[T + 1] post-FIX-04, written
    # this way to name what it MEANS: the last published window's own terminal target,
    # `t + H` at the last resolve `t = T - H + 1`).
    soc_da_final = soc_da_bus[(T - H + 1) + H]

    dev_disabled = abs(soc_final_disabled - soc_da_final)
    dev_enabled = abs(soc_final_enabled - soc_da_final)

    @info "mpc_terminal MPC-02 measured deviations" dev_disabled dev_enabled soc_da_final soc_final_disabled soc_final_enabled

    # MEASURED margin (not assumed): dev_enabled sits at the solver-precision floor (~1e-10-
    # 1e-11); dev_disabled is 3-4 orders of magnitude above it. A 1000x margin is comfortably
    # inside the RE-MEASURED (Phase 26 plan 26-11, post-FIX-04 soc[H+1] retarget — see file
    # header) ~4,851x ratio while leaving generous headroom against solver-run noise.
    @test dev_enabled < dev_disabled
    @test dev_disabled > 1000 * dev_enabled
end
