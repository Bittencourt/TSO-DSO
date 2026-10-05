# test/test_mpc_terminal.jl
#
# Seam: the hard terminal-SOC condition's dump/hoard-prevention regression,
# driven directly against the `build_mpc_window`/`solve_mpc_window!` primitives plus
# `propagate_soc`, BEFORE the full `run_mpc` orchestrator.
# Every item name contains "mpc_terminal", tagged `[:mpc_terminal]`, `setup =
# [MPCFixtures]`.
#
# Price choice: a FLAT price `λ₀ = MPCFixtures.mpc_lambda0()` was measured empirically
# (a standalone probe script, not committed) to make BOTH the disabled and enabled
# receding-horizon loops converge to the SAME PV-driven Emax-saturated endpoint (the free PV
# charging dominates and hits the hard `Emax` cap regardless of the terminal toggle), so
# `dev_disabled`/`dev_enabled` are both ~1e-9-1e-10 solver-noise-floor numbers with NO
# measurable separation — an ambiguous, non-demonstrative margin (widen the fixture rather
# than weaken the assertion). The MINIMAL widening
# used here is a non-flat, mid-horizon price SPIKE (`λ₀ = [4,4,4,9,4,4,4,4]`, hour 4 of 8) built
# locally in this test file — `MPCFixtures.mpc_feeder`/`build_mpc_aggregators` (the feeder,
# aggregators, battery/thermostatic headroom, and PV/demand ground truth) are all used
# VERBATIM, unmodified. A price spike that falls INSIDE one interior window but OUTSIDE the
# window immediately preceding it is exactly the informational asymmetry the terminal condition
# exists to correct: the myopic (disabled) loop's window covering the spike hour has zero
# incentive to preserve a specific SOC beyond its own end, while the day-ahead optimum (full
# horizon visibility) commits to a SPECIFIC SOC trajectory through that hour that every window
# before/after it should track.
#
# Measured margin: this file's hand-rolled loop builds `soc_da` over `1:(T + 1)` and indexes
# the terminal target at `soc_da_bus[t + H]` (matching `run_mpc`'s own terminal target in
# `src/experiments/mpc_loop.jl`; the earlier `soc_da_bus[min(t + H - 1, T)]` index is one hour
# too early). With that index: `dev_disabled ≈ 4.36e-7` vs `dev_enabled ≈ 8.98e-11` — a
# ratio of ~4,851× (live numbers, not assumed from any prior measurement). Still
# comfortably above the `dev_disabled > 1000 * dev_enabled` assertion below, and
# `dev_enabled` still sits at the same ~1e-10-1e-11 solver-precision floor.

@testitem "mpc_terminal: hard terminal-SOC condition prevents end-of-horizon dump/hoard, present when disabled" tags =
    [:mpc_terminal] setup = [MPCFixtures] begin
    using TSODSO
    using TSODSO: build_mpc_window, solve_mpc_window!
    using JuMP: value, set_parameter_value, set_objective_coefficient

    feeder = MPCFixtures.mpc_feeder()
    aggs = MPCFixtures.build_mpc_aggregators(feeder)
    T = MPCFixtures.T
    H = MPCFixtures.H

    # Non-flat, mid-horizon price spike (hour 4 of 8) — see the file-header price-choice note: the
    # fixture's own flat `mpc_lambda0()` produces an ambiguous, noise-floor-only margin on this
    # feeder/aggregator pair; this is the minimal widening that makes the artifact measurable
    # without touching MPCFixtures' feeder/aggregator/battery-headroom shapes at all.
    λ₀ = Float64[4.0, 4.0, 4.0, 9.0, 4.0, 4.0, 4.0, 4.0]
    @assert length(λ₀) == T

    # Day-ahead perfect-foresight benchmark, solved ONCE (the standard extraction idiom).
    ctx_da, welfare_da, _ =
        solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)
    # build_mpc_window's terminal-condition constraint targets
    # `soc[H + 1]` (the day-ahead state AFTER the window), since the battery `soc` vector is
    # now `1:(T + 1)` long. `soc_da` must therefore be built over the SAME `1:(T + 1)` range
    # so the terminal target below can be indexed at `soc_da_bus[t + H]` — never the stale
    # `soc_da_bus[min(t + H - 1, T)]` (one hour BEFORE the window's actual end), which
    # silently drives this mini-loop INFEASIBLE.
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:(T + 1)] for
        (bus, varlist) in ctx_da.agg_device_vars for v in varlist if haskey(v, :soc)
    )

    # The fixture's single aggregator's battery device — its own `soc0`/`η`/`Δt` literals are
    # the SAME values the day-ahead solve started/propagated from.
    batt = only(d for d in aggs[1].devices if hasproperty(d, :soc0))
    therm = only(d for d in aggs[1].devices if hasproperty(d, :Tin0))
    bus = batt.bus
    soc_da_bus = soc_da[bus]

    # `run_mini_loop`: a manual receding-horizon loop driving `build_mpc_window`/
    # `solve_mpc_window!` DIRECTLY (no orchestrator exists yet) — builds the window ONCE
    # (build-once), re-solves it T-H+1 times via `set_parameter_value`/
    # `set_objective_coefficient`, and propagates the MEASURED SOC via `TSODSO.propagate_soc`
    # on each step's REALIZED first-interval controls. Returns the final measured SOC.
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
                # The window's own terminal target is soc[H + 1] (the state AFTER
                # the window); its day-ahead counterpart is soc_da_bus[t + H].
                # No min(..., T) clamp — the outer loop's own header bound (t in
                # 1:(T - H + 1)) guarantees t + H <= T + 1 at every visited t, and
                # soc_da_bus is now built over 1:(T + 1), so every index here is in-bounds
                # by construction.
                set_parameter_value(soc_handle.terminal_param, soc_da_bus[t + H])
            end
            # TRUE ground-truth slices (no forecast error — isolate the terminal-condition
            # effect alone).
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
    # enabled case is pinned toward (algebraically soc_da_bus[T + 1], written
    # this way to name what it MEANS: the last published window's own terminal target,
    # `t + H` at the last resolve `t = T - H + 1`).
    soc_da_final = soc_da_bus[(T - H + 1) + H]

    dev_disabled = abs(soc_final_disabled - soc_da_final)
    dev_enabled = abs(soc_final_enabled - soc_da_final)

    @info "mpc_terminal measured deviations" dev_disabled dev_enabled soc_da_final soc_final_disabled soc_final_enabled

    # MEASURED margin (not assumed): dev_enabled sits at the solver-precision floor (~1e-10-
    # 1e-11); dev_disabled is 3-4 orders of magnitude above it. A 1000x margin is comfortably
    # inside the measured (see file
    # header) ~4,851x ratio while leaving generous headroom against solver-run noise.
    @test dev_enabled < dev_disabled
    @test dev_disabled > 1000 * dev_enabled
end
