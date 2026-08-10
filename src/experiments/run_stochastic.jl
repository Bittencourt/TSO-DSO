# src/experiments/run_stochastic.jl
#
# SEAM: stochastic extensive-form closed orchestrator (STOCH-01..03).
# OWNER: plan 22-04.
#
# `run_stochastic(s::Scenario)` is an INDEPENDENT entry point — it is NOT wired through
# `run_scenario`/`run.jl`'s `:centralized`/`:admm` `strategy` dispatch (D-01/D-02; mirrors
# `run_mpc`'s own positioning note verbatim, `src/experiments/mpc_loop.jl`). It:
#
#  1. materializes `s.stoch_S` in-sample scenario aggregator populations from a DISJOINT
#     `sub_seed` tag family (`:stoch_insample_profiles_k`/`:stoch_insample_population_k`);
#  2. solves the S-scenario extensive form via `build_stochastic_welfare` (plan 22-02);
#  3. reads the SOLVED, shared first-stage battery schedule off scenario 1's own device vars
#     (every scenario's battery is nonanticipativity-tied to it, so scenario 1's copy IS the
#     shared schedule);
#  4. materializes `s.stoch_H_oos` held-out scenario aggregator populations from a SECOND,
#     DISJOINT `sub_seed` tag family (`:stoch_oos_profiles_h`/`:stoch_oos_population_h`);
#  5. builds the out-of-sample harness EXACTLY ONCE (`build_stochastic_oos_harness`, plan
#     22-03) against held-out scenario 1's aggregator list as the device STRUCTURE template,
#     pins the harness's battery controls to the in-sample optimum ONCE — before the
#     held-out loop (D-09's build-once contract) — then re-slides every held-out scenario's
#     own PV/demand/ambient data and re-solves via `solve_stochastic_oos_step!`; and
#  6. reports the realized-vs-in-sample welfare gap (STOCH-03).
#
# `λ₀` is computed ONCE, from in-sample scenario 1's own profile draw, and reused for every
# in-sample AND held-out scenario: `:mem`'s shape is deterministic and profile-independent
# per its own docstring (`src/experiments/materialize.jl`), so this is not a hidden
# per-scenario price divergence.

using JuMP

"""
    _stoch_device_with_field(aggs, bus::Int, field::Symbol) -> AbstractDevice

Internal helper (unexported): the single member device of the aggregator at `bus` (within
`aggs`) carrying `field` as one of its own struct fields — e.g. `field = :Ppv` finds the
`PVBattery` member, `field = :Tout` finds the `Thermostatic` member. Used to slide a
held-out scenario's own device data onto a [`StochasticOosHarness`](@ref)'s
`ppv_handles`/`tout_handles` (which are keyed only by `bus`, not by a device index within
that bus's aggregator).
"""
function _stoch_device_with_field(aggs, bus::Int, field::Symbol)
    agg = only(a for a in aggs if a.bus == bus)
    return only(d for d in agg.devices if hasproperty(d, field))
end

"""
    run_stochastic(s::Scenario) -> NamedTuple

Drive the FULL two-stage stochastic extensive-form + out-of-sample evaluation for `s`
(STOCH-01..03): materialize `s.stoch_S` in-sample scenario aggregator populations, solve the
extensive form via [`build_stochastic_welfare`](@ref), then drive
[`build_stochastic_oos_harness`](@ref)/[`solve_stochastic_oos_step!`](@ref) across
`s.stoch_H_oos` held-out scenarios — pinning the first-stage battery schedule to the
in-sample optimum ONCE (D-09's build-once contract, never rebuilding across the held-out
loop) — and reporting the realized-vs-in-sample welfare gap (D-09/D-10).

# Guards

Unlike [`run_mpc`](@ref)'s cross-field `mpc_H > T` check, this function needs NO additional
guard beyond what [`Scenario`](@ref)'s own constructor already enforces:
`stoch_S`/`stoch_H_oos`/`stoch_probabilities` are independently bounded at construction
(D-01/D-04/D-10), with no cross-field interaction to re-check here.

# Materialization (seed disjointness, D-01/D-02)

Both scenario families flow through [`sub_seed`](@ref)`(s.seed, tag)` with DISJOINT tag
prefixes — in-sample scenario `k` uses `Symbol(:stoch_insample_profiles_, k)` /
`Symbol(:stoch_insample_population_, k)`; held-out scenario `h` uses the disjoint
`Symbol(:stoch_oos_profiles_, h)` / `Symbol(:stoch_oos_population_, h)` — so no held-out
scenario ever replays an in-sample draw (T-22-06). `λ₀` is materialized ONCE, from in-sample
scenario 1's own profile draw, and reused verbatim for every in-sample and held-out scenario
(the `:mem` price shape is deterministic and profile-independent).

# Returns

A `NamedTuple` `(; in_sample, oos)`:

  - `in_sample::NamedTuple` — `(; welfare, dadp, expected_dadp, probabilities, socp_maxgap)`,
    read verbatim off [`build_stochastic_welfare`](@ref)'s own return value: `welfare` is the
    probability-weighted in-sample expected-welfare objective; `dadp`/`expected_dadp` are the
    per-scenario de-scaled DADP and its probability-weighted expectation (D-05/D-07).
  - `oos::NamedTuple` — `(; welfare_h, realized_welfare, welfare_gap)`: `welfare_h[h]` is the
    held-out scenario `h`'s realized objective value (the fixed first-stage schedule
    re-scored against that scenario's own exogenous draw); `realized_welfare` is the
    uniform-weight average `sum(welfare_h) / s.stoch_H_oos` (Claude's-discretion default);
    `welfare_gap = realized_welfare - in_sample.welfare` is the D-09 realized-vs-in-sample
    gap.

Reproducible: two calls with the SAME `Scenario` (same `seed`) return `==`-identical
`in_sample.welfare`/`oos.welfare_gap` (INFRA-04, mirrors [`run_mpc`](@ref)'s own same-seed
guarantee) — every stochastic draw flows through a seeded, independent `sub_seed` sub-stream,
never the global RNG.
"""
function run_stochastic(s::Scenario)
    # --- 1. MATERIALIZE, verbatim per run_mpc's/run_scenario's own materialization block
    # (mirrors `src/experiments/mpc_loop.jl`): feeder/pf built ONCE, reused for every
    # scenario below (never rebuilt inside the per-scenario loops). ------------------------
    feeder = build_feeder(s.feeder)
    pf = ConvexBranchFlow()

    # --- 2. In-sample scenario populations, one per k in 1:s.stoch_S, from a DISJOINT
    # `sub_seed` tag family (T-22-06). λ₀ is computed ONCE, from scenario 1's own profile
    # draw, and reused verbatim for every scenario (see file header). ----------------------
    scenario_aggs = Vector{Vector{Aggregator}}(undef, s.stoch_S)
    λ₀ = Float64[]
    for k in 1:s.stoch_S
        profiles_k = generate_profiles(;
            seed = sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)),
            T = s.T,
        )
        if k == 1
            λ₀ = build_price(s.price, s.T, profiles_k)
        end
        scenario_aggs[k] = build_population(
            s.population,
            feeder,
            s.feeder,
            profiles_k,
            sub_seed(s.seed, Symbol(:stoch_insample_population_, k)),
        )
    end

    # --- 3. Solve the S-scenario extensive form (STOCH-01/STOCH-02, plan 22-02). -----------
    r = build_stochastic_welfare(
        feeder,
        pf,
        scenario_aggs;
        probabilities = s.stoch_probabilities,
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )

    # --- 4. Read the SOLVED, shared first-stage battery schedule off scenario 1's own
    # device vars (every scenario's battery is nonanticipativity-tied to it, so scenario 1's
    # copy IS the shared schedule). --------------------------------------------------------
    in_sample_battery = NamedTuple[]
    for (bus, varlist) in r.ctxs[1].meta[:agg_device_vars]
        for v in varlist
            if haskey(v, :soc0)
                push!(
                    in_sample_battery,
                    (; bus, p_ch = value.(v.p_ch), p_dch = value.(v.p_dch)),
                )
            end
        end
    end

    # --- 5. MATERIALIZE the held-out scenario populations, one per h in 1:s.stoch_H_oos,
    # from a SECOND, DISJOINT `sub_seed` tag family (T-22-06). ------------------------------
    held_out_aggs = Vector{Vector{Aggregator}}(undef, s.stoch_H_oos)
    for h in 1:s.stoch_H_oos
        profiles_h = generate_profiles(;
            seed = sub_seed(s.seed, Symbol(:stoch_oos_profiles_, h)),
            T = s.T,
        )
        held_out_aggs[h] = build_population(
            s.population,
            feeder,
            s.feeder,
            profiles_h,
            sub_seed(s.seed, Symbol(:stoch_oos_population_, h)),
        )
    end

    # --- 6. Build the out-of-sample harness EXACTLY ONCE (D-09), against held-out scenario
    # 1's aggregator LIST as the device STRUCTURE template — every held-out population
    # shares the SAME bus/device composition (structural congruence, `build_population`'s
    # own convention: device count/bus order depend only on `feeder`/`population`, never on
    # the seed). Pin the harness's battery controls to the in-sample optimum ONCE, before
    # the held-out loop (D-09's build-once contract). --------------------------------------
    h_oos = build_stochastic_oos_harness(
        feeder,
        pf,
        held_out_aggs[1];
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )

    for pin in h_oos.battery_pins
        batt = only(b for b in in_sample_battery if b.bus == pin.bus)
        set_parameter_value.(pin.pin_p_ch, batt.p_ch)
        set_parameter_value.(pin.pin_p_dch, batt.p_dch)
    end

    # --- 7. Held-out loop: re-slide every held-out scenario's own PV/demand/ambient data
    # onto the (never-rebuilt) harness and re-solve. ----------------------------------------
    welfare_h = Vector{Float64}(undef, s.stoch_H_oos)
    for h in 1:s.stoch_H_oos
        aggs_h = held_out_aggs[h]

        for ppv in h_oos.ppv_handles
            d = _stoch_device_with_field(aggs_h, ppv.bus, :Ppv)
            set_parameter_value.(ppv.Ppv_param, d.Ppv[1:s.T])
        end
        for tout in h_oos.tout_handles
            d = _stoch_device_with_field(aggs_h, tout.bus, :Tout)
            set_parameter_value.(tout.Tout_param, d.Tout[1:(s.T - 1)])
        end
        for pdc in h_oos.agg_pdc_handles
            agg = only(a for a in aggs_h if a.bus == pdc.bus)
            set_parameter_value.(pdc.Pdc_param, agg.Pdc[1:s.T])
        end

        solve_stochastic_oos_step!(h_oos)
        welfare_h[h] = objective_value(h_oos.model)
    end

    # --- 8. D-09's realized-vs-in-sample welfare gap: uniform-weight average across the
    # held-out budget (Claude's-discretion default, documented above) minus the in-sample
    # extensive form's own expected-welfare objective value. --------------------------------
    realized_welfare = sum(welfare_h) / s.stoch_H_oos
    welfare_gap = realized_welfare - r.welfare

    return (;
        in_sample = (;
            welfare = r.welfare,
            dadp = r.dadp,
            expected_dadp = r.expected_dadp,
            probabilities = r.probabilities,
            socp_maxgap = r.socp_maxgap,
        ),
        oos = (; welfare_h, realized_welfare, welfare_gap),
    )
end

export run_stochastic
