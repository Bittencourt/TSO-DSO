# test/test_mpc_window.jl
#
# Seam: src/models/mpc_window.jl (MPC-01/MPC-02). `MpcWindow` + `build_mpc_window` (Task 1)
# generalize `PlanningOracle`'s build-once/`Parameter`-re-solve shape from a single `z`-pin to
# the full set of per-step device Parameters (soc0/Tin0/Ppv_param/Tout_param/Pdc_param) plan
# 21-01 widened, plus a build-time `terminal_soc` toggle (MPC-02). `solve_mpc_window!` is a
# one-line delegation to `solve_with_retry!`. Items tagged `[:mpc_window]`, every name contains
# "mpc_window" (occursin filter convention, mirrors test_planning_oracle.jl / test_mpc_trace.jl),
# `setup = [Phase21Fixtures]`.

@testitem "mpc_window: build_mpc_window guards (empty aggregators, H<1, bus range)" tags =
    [:mpc_window] setup = [Phase21Fixtures] begin
    using TSODSO

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    H = Phase21Fixtures.H

    # Empty aggregators: no priced load / no objective.
    @test_throws ArgumentError build_mpc_window(
        feeder,
        ConvexBranchFlow(),
        typeof(aggs)();
        H = H,
    )

    # H < 1.
    @test_throws ArgumentError build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = 0)

    # WR-03: terminal_soc = true at H = 1 double-pins soc[1] (IC + terminal equality on the
    # SAME variable) — rejected loudly at build time, not a cryptic mid-loop infeasibility.
    @test_throws ArgumentError build_mpc_window(
        feeder,
        ConvexBranchFlow(),
        aggs;
        H = 1,
        terminal_soc = true,
    )
    # ... while H = 1 WITHOUT the terminal toggle stays buildable (a degenerate but legal
    # single-hour window).
    o1 = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = 1, terminal_soc = false)
    @test o1 isa TSODSO.MpcWindow

    # Aggregator bus outside 1:length(feeder.buses) (feeder has 2 buses; 99 is out of range).
    out_of_range = [TSODSO.Aggregator(99, 0.9, aggs[1].devices, aggs[1].Pdc)]
    @test_throws ArgumentError build_mpc_window(
        feeder,
        ConvexBranchFlow(),
        out_of_range;
        H = H,
    )
end

@testitem "mpc_window: allow_export threads to the frontier — import-only lower bound when false, free-sign when true (WR-06)" tags =
    [:mpc_window] setup = [Phase21Fixtures] begin
    using TSODSO
    using JuMP: has_lower_bound, lower_bound

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    H = Phase21Fixtures.H

    # Default (and explicit true): FREE-SIGN frontier — no lower bound on any p_import[τ].
    o_free = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H)
    @test all(!has_lower_bound(o_free.p_import[τ]) for τ in 1:H)

    # allow_export = false: IMPORT-ONLY — p_import[τ] ≥ 0, mirroring solve_welfare's own
    # kwarg exactly, so a Scenario(allow_export = false) run never benchmarks a no-export
    # day-ahead optimum against an export-allowed closed loop.
    o_imp = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, allow_export = false)
    @test all(has_lower_bound(o_imp.p_import[τ]) for τ in 1:H)
    @test all(lower_bound(o_imp.p_import[τ]) == 0.0 for τ in 1:H)
end

@testitem "mpc_window: build-once — num_variables/num_constraints invariant across re-solves at DIFFERENT soc0/Tin0/terminal-target/forecast-slice states (MPC-01)" tags =
    [:mpc_window] setup = [Phase21Fixtures] begin
    using TSODSO
    using JuMP:
        num_variables, num_constraints, set_parameter_value, set_objective_coefficient

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    H = Phase21Fixtures.H

    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = true)
    @test o isa TSODSO.MpcWindow

    nv0 = num_variables(o.model)
    nc0 = num_constraints(o.model; count_variable_in_set_constraints = true)

    device_vars = [v for (bus, varlist) in o.ctx.meta[:agg_device_vars] for v in varlist]

    # THREE heterogeneous re-solve cycles: every ic_handles entry's ic_param/terminal_param,
    # every device's Ppv_param/Tout_param, every aggregator's Pdc_param, AND every p_import[τ]
    # objective coefficient (λ₀) change EACH cycle — all values kept within each device's own
    # structural bounds (PVBattery Emin=0.0/Emax=0.008 pu, Thermostatic Tmin=15.0/Tmax=30.0)
    # so every re-solve stays feasible.
    # soc0/term pairs stay within the battery's per-window reachability envelope
    # (2 steps × Pmax=0.002/η=0.95 ⇒ max Δsoc ≈ ±0.004) so every cycle is genuinely feasible.
    cycles = [
        (
            soc0 = 0.003,
            term = 0.002,
            Tin0 = 20.0,
            Ppv = 0.008,
            Tout = 18.0,
            Pdc = 0.015,
            λ0 = 3.0,
        ),
        (
            soc0 = 0.002,
            term = 0.005,
            Tin0 = 25.0,
            Ppv = 0.012,
            Tout = 24.0,
            Pdc = 0.020,
            λ0 = 5.0,
        ),
        (
            soc0 = 0.006,
            term = 0.004,
            Tin0 = 17.0,
            Ppv = 0.005,
            Tout = 20.0,
            Pdc = 0.010,
            λ0 = 6.5,
        ),
    ]

    for c in cycles
        for h in o.ic_handles
            if h.kind == :soc
                set_parameter_value(h.ic_param, c.soc0)
                h.terminal_param === nothing ||
                    set_parameter_value(h.terminal_param, c.term)
            else # :Tin
                set_parameter_value(h.ic_param, c.Tin0)
            end
        end
        for v in device_vars
            haskey(v, :Ppv_param) && set_parameter_value.(v.Ppv_param, fill(c.Ppv, H))
            haskey(v, :Tout_param) &&
                set_parameter_value.(v.Tout_param, fill(c.Tout, length(v.Tout_param)))
        end
        for handle in o.agg_pdc_handles
            set_parameter_value.(handle.Pdc_param, fill(c.Pdc, H))
        end
        for τ in 1:H
            set_objective_coefficient(o.model, o.p_import[τ], -c.λ0)
        end
        solve_mpc_window!(o)
    end

    @test num_variables(o.model) == nv0
    @test num_constraints(o.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "mpc_window: set_parameter_value on soc0 is NOT a no-op — the solved soc[1] trajectory genuinely moves (MPC-01)" tags =
    [:mpc_window] setup = [Phase21Fixtures] begin
    using TSODSO
    using JuMP: value, set_parameter_value, set_objective_coefficient

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    H = Phase21Fixtures.H

    # terminal_soc = false here isolates the IC-parameter effect from the terminal-target
    # constraint (the FINAL test item below covers the toggle's structural effect separately).
    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = false)

    soc_handle = only(h for h in o.ic_handles if h.kind == :soc)
    device_vars = [v for (bus, varlist) in o.ctx.meta[:agg_device_vars] for v in varlist]
    batt_vars = only(v for v in device_vars if haskey(v, :soc))

    for τ in 1:H
        set_objective_coefficient(o.model, o.p_import[τ], -4.0)
    end

    valA = 0.002
    set_parameter_value(soc_handle.ic_param, valA)
    solve_mpc_window!(o)
    socA = value(batt_vars.soc[1])
    @test socA ≈ valA

    valB = 0.006
    set_parameter_value(soc_handle.ic_param, valB)
    solve_mpc_window!(o)
    socB = value(batt_vars.soc[1])
    @test socB ≈ valB
    @test !(socB ≈ socA)
end

@testitem "mpc_window: terminal_soc toggle produces a STRUCTURALLY different model (MPC-02 mechanism)" tags =
    [:mpc_window] setup = [Phase21Fixtures] begin
    using TSODSO
    using JuMP: num_constraints

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)
    H = Phase21Fixtures.H

    o_true = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = true)
    o_false =
        build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = false)

    nct = num_constraints(o_true.model; count_variable_in_set_constraints = true)
    ncf = num_constraints(o_false.model; count_variable_in_set_constraints = true)
    @test nct > ncf

    ht = only(h for h in o_true.ic_handles if h.kind == :soc)
    hf = only(h for h in o_false.ic_handles if h.kind == :soc)
    @test ht.terminal_param !== nothing
    @test hf.terminal_param === nothing
end
