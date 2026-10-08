# src/experiments/run_stochastic.jl
#
# SEAM: stochastic extensive-form closed orchestrator.
#
# `run_stochastic(s::Scenario)` reads its knobs from `Scenario.strategy::Stochastic`
# and is also reachable via `TSODSO.run(::Stochastic, s)`. It:
#
#  1. materializes `st.S` in-sample scenario aggregator populations from a DISJOINT
#     `sub_seed` tag family (`:stoch_insample_profiles_k`/`:stoch_insample_population_k`);
#  2. solves the S-scenario extensive form via `build_stochastic_welfare`;
#  3. reads the SOLVED, shared first-stage battery schedule off scenario 1's own device vars
#     (every scenario's battery is nonanticipativity-tied to it, so scenario 1's copy IS the
#     shared schedule);
#  4. materializes `st.H_oos` held-out scenario aggregator populations from a SECOND,
#     DISJOINT `sub_seed` tag family (`:stoch_oos_profiles_h`/`:stoch_oos_population_h`);
#  5. builds the out-of-sample harness EXACTLY ONCE (`build_stochastic_oos_harness`)
#     against held-out scenario 1's aggregator list as the device STRUCTURE template,
#     pins the harness's battery controls to the in-sample optimum ONCE — before the
#     held-out loop (the build-once contract) — then re-slides every held-out scenario's
#     own PV/demand/ambient data and re-solves via `solve_stochastic_oos_step!` (which
#     certifies each held-out solve with the shared SOCP exactness gate); and
#  6. reports the realized-vs-in-sample welfare gap over the feasible AND exact held-out
#     draws (infeasible or inexact draws are skipped-and-reported, never averaged in).
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
    _stoch_solve_held_out!(h_oos::StochasticOosHarness, h_index::Integer)
        -> (welfare::Float64, infeasible::Bool, inexact::Bool)

Internal helper (unexported): re-solve the pinned harness for held-out scenario `h_index`,
converting the two documented held-out failure modes into an honest skip-and-report instead of
aborting the whole [`run_stochastic`](@ref) call:

  - a GENUINE primal infeasibility returns `(NaN, true, false)`;
  - an INEXACT held-out solve (the step's exactness gate refused it:
    `CertificateError` with `kind === :socp_exact`) returns
    `(objective, false, true)`. The objective is reported per draw but the caller
    EXCLUDES it from `realized_welfare`, because it is not certified.

A successful, certified solve returns `(objective, false, false)`. Each skip emits a `@warn`.

Why infeasibility is a REAL, expected failure mode here (the classic committed-first-stage
evaluation problem): the in-sample optimal `p_ch[t]` satisfies `p_ch[t] ≤ pv_used_s[t] ≤ Ppv_s[t]` for every IN-SAMPLE scenario, but a held-out draw whose PV at some hour falls
below every in-sample draw makes the pinned equality `p_ch[t] == pin` collide with that
scenario's own `p_ch[t] ≤ pv_used[t] ≤ Ppv_h[t]` — a genuine `PRIMAL_INFEASIBLE` that
[`solve_with_retry!`](@ref) correctly refuses to retry. Low-probability on the small-PV CI
fixtures, likely under scaled-up PV. Only the infeasibility statuses (`INFEASIBLE`,
`INFEASIBLE_OR_UNBOUNDED`, `LOCALLY_INFEASIBLE`) are converted.

Why inexactness is one too: on the pinned-dispatch held-out problem the interior-point solve
can leave cone residuals just above the gate's solver floor (measured on IEEE-13, T = 9: a
few held-out draws in ten, with violations of 2-4e-7 against τ_solver = 2e-7, not fixed by
tightening the solver tolerances). Aborting the run would discard the expensive in-sample
solve; averaging the draw in would publish an uncertified number.

Every OTHER error (any other solve failure, any other certificate kind, a programming error)
still rethrows LOUDLY, never a silent skip.
"""
function _stoch_solve_held_out!(h_oos::StochasticOosHarness, h_index::Integer)
    try
        solve_stochastic_oos_step!(h_oos)
        return _objective(h_oos.model), false, false
    catch e
        if e isa CertificateError && e.kind === :socp_exact
            ratio = get(h_oos.ctx.meta, :socp_maxratio, NaN)
            @warn "run_stochastic: held-out scenario $h_index: SOCP relaxation inexact " *
                  "(cone ratio $(_ratio_phrase(ratio))) — recorded with inexact_h = true " *
                  "and EXCLUDED " *
                  "from realized_welfare (skip-and-report, never silent)"
            return _objective(h_oos.model), false, true
        end
        e isa SolveFailedError || rethrow()
        ts = termination_status(h_oos.model)
        ts in (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE) ||
            rethrow()
        @warn "run_stochastic: held-out scenario $h_index is INFEASIBLE against the " *
              "committed first-stage schedule (its PV/demand draw cannot support the " *
              "pinned p_ch/p_dch at some hour) — recorded as welfare_h = NaN, " *
              "infeasible_h = true, and EXCLUDED from realized_welfare " *
              "(skip-and-report, never silent)" termination_status = ts
        return NaN, true, false
    end
end

"""
    run_stochastic(s::Scenario) -> NamedTuple

The result additionally carries a trailing `status` (`:solved`, `:oos_infeasible_skipped` or
`:oos_inexact_skipped`, see `STATUS_VOCABULARY.run_stochastic`).

Drive the FULL two-stage stochastic extensive-form + out-of-sample evaluation for `s`
materialize `st.S` in-sample scenario aggregator populations, solve the
extensive form via [`build_stochastic_welfare`](@ref), then drive
[`build_stochastic_oos_harness`](@ref)/[`solve_stochastic_oos_step!`](@ref) across
`st.H_oos` held-out scenarios — pinning the first-stage battery schedule to the
in-sample optimum ONCE (the build-once contract, never rebuilding across the held-out
loop) — and reporting the realized-vs-in-sample welfare gap.

# Guards

Unlike [`run_mpc`](@ref), which checks `MPC.H > T` against the scenario horizon, this function
needs NO cross-field guard: `Stochastic(S, probabilities, H_oos)` validates its own knobs at
construction, and `_check_probabilities` re-checks `probabilities` here in case the vector was
mutated after construction.

TWO documented runtime failure modes, both skipped-and-reported (a `@warn` per draw, never
allowed to abort the run and never silently absorbed; see [`_stoch_solve_held_out!`](@ref)):

  - a held-out draw can be genuinely INFEASIBLE against the committed first-stage schedule
    (the classic committed-first-stage evaluation problem): `welfare_h[h] = NaN`,
    `infeasible_h[h] = true`;
  - a held-out re-solve can be refused by the SOCP exactness gate (inexact relaxation):
    `welfare_h[h]` keeps the uncertified objective for reporting, `inexact_h[h] = true`.

Every OTHER failure still throws: any other solve failure, and the in-sample exactness refusal
(`CertificateError` from [`build_stochastic_welfare`](@ref)).

# Materialization (seed disjointness)

Both scenario families flow through [`sub_seed`](@ref)`(s.seed, tag)` with DISJOINT tag
prefixes — in-sample scenario `k` uses `Symbol(:stoch_insample_profiles_, k)` /
`Symbol(:stoch_insample_population_, k)`; held-out scenario `h` uses the disjoint
`Symbol(:stoch_oos_profiles_, h)` / `Symbol(:stoch_oos_population_, h)` — so no held-out
scenario ever replays an in-sample draw. `λ₀` is materialized ONCE, from in-sample
scenario 1's own profile draw, and reused verbatim for every in-sample and held-out scenario
(the `:mem` price shape is deterministic and profile-independent).

# Returns

A `NamedTuple` `(; in_sample, oos)`:

  - `in_sample::NamedTuple` — `(; welfare, dadp, expected_dadp, probabilities, socp_maxgap)`,
    read verbatim off [`build_stochastic_welfare`](@ref)'s own return value: `welfare` is the
    probability-weighted in-sample expected-welfare objective; `dadp`/`expected_dadp` are the
    per-scenario de-scaled DADP and its probability-weighted expectation.
  - `oos::NamedTuple` — `(; welfare_h, infeasible_h, inexact_h, socp_maxratio_h, realized_welfare, welfare_gap)`:
    `welfare_h[h]` is the held-out scenario `h`'s realized objective value (the fixed
    first-stage schedule re-scored against that scenario's own exogenous draw), or `NaN`
    when that draw is genuinely INFEASIBLE against the committed schedule (the
    committed-first-stage evaluation problem: a held-out PV draw
    below every in-sample draw at some hour collides with the pinned `p_ch`; see
    [`_stoch_solve_held_out!`](@ref)); `infeasible_h::Vector{Bool}` marks exactly those
    skipped-and-reported scenarios; `inexact_h::Vector{Bool}` marks the draws whose
    re-solve the SOCP exactness gate refused (their `welfare_h` entry is kept, uncertified,
    for reporting); `socp_maxratio_h::Vector{Float64}` is each draw's worst cone ratio
    (gap/(atol_b + rtol·|cone|), > 1 means refused; `NaN` for an infeasible draw or a
    formulation without branch current). A `@warn` is emitted per skip — never silent.
    `realized_welfare` is the uniform-weight average over the held-out draws that are
    FEASIBLE AND EXACT only (`NaN` if there are none — an honestly unusable evaluation,
    never a fabricated number); `welfare_gap = realized_welfare - in_sample.welfare` is
    the realized-vs-in-sample gap (also `NaN` in that case). When no held-out draw is
    skipped, `realized_welfare` and `welfare_gap` are unchanged from the plain average over
    all draws.

# Solver precision of the held-out re-solves

The held-out harness is built with the factory default optimizer (Clarabel
`tol_gap_abs = tol_gap_rel = 1e-8`), while the in-sample extensive form is solved at `5e-10`.
The number of draws the exactness gate refuses is therefore solver- and version-dependent
(the refused residuals sit just above the gate's solver floor), and so are `realized_welfare`
and `welfare_gap` whenever a draw is excluded. Compare against the mean over all feasible
draws (`welfare_h[.!infeasible_h]`) to see the effect of an exclusion. See the
[status & exception policy](@ref status-policy).

Reproducible: two calls with the SAME `Scenario` (same `seed`) return `==`-identical
`in_sample.welfare`/`oos.welfare_gap` (mirrors [`run_mpc`](@ref)'s own same-seed
guarantee) — every stochastic draw flows through a seeded, independent `sub_seed` sub-stream,
never the global RNG.
"""
function _run_stochastic(
    s::Scenario,
    st::Stochastic;
    # Internal test seam: the per-draw held-out solve. Production always uses
    # `_stoch_solve_held_out!`; a test may wrap it (same signature and return contract) to
    # force a deterministic refusal on chosen draws and check the aggregation below.
    solve_held_out! = _stoch_solve_held_out!,
)
    _check_probabilities(st.S, st.probabilities)   # `probabilities` is mutable post-construction
    # --- 1. MATERIALIZE, verbatim per run_mpc's/run_scenario's own materialization block
    # (mirrors `src/experiments/mpc_loop.jl`): feeder/pf built ONCE, reused for every
    # scenario below (never rebuilt inside the per-scenario loops). ------------------------
    feeder = build_feeder(s.feeder)
    pf = build_powerflow(s)

    # --- 2. In-sample scenario populations, one per k in 1:st.S, from a DISJOINT
    # `sub_seed` tag family. λ₀ is computed ONCE, from scenario 1's own profile
    # draw, and reused verbatim for every scenario (see file header). ----------------------
    scenario_aggs = Vector{Vector{Aggregator}}(undef, st.S)
    λ₀ = Float64[]
    for k in 1:st.S
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

    # --- 3. Solve the S-scenario extensive form. -----------
    r = build_stochastic_welfare(
        feeder,
        pf,
        scenario_aggs;
        probabilities = st.probabilities,
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )

    # --- 4. Read the SOLVED, shared first-stage battery schedule off scenario 1's own
    # device vars (every scenario's battery is nonanticipativity-tied to it, so scenario 1's
    # copy IS the shared schedule). --------------------------------------------------------
    in_sample_battery = NamedTuple[]
    for (bus, varlist) in r.ctxs[1].agg_device_vars
        for v in varlist
            if haskey(v, :soc0)
                # A FourQuadBESS's reactive dispatch q is
                # first-stage too (tied across scenarios by build_stochastic_welfare),
                # so the committed schedule read here carries it for pinning below.
                if haskey(v, :q)
                    push!(
                        in_sample_battery,
                        (;
                            bus,
                            p_ch = value.(v.p_ch),
                            p_dch = value.(v.p_dch),
                            q = value.(v.q),
                        ),
                    )
                else
                    push!(
                        in_sample_battery,
                        (; bus, p_ch = value.(v.p_ch), p_dch = value.(v.p_dch)),
                    )
                end
            end
        end
    end

    # --- 5. MATERIALIZE the held-out scenario populations, one per h in 1:st.H_oos,
    # from a SECOND, DISJOINT `sub_seed` tag family. ------------------------------
    held_out_aggs = Vector{Vector{Aggregator}}(undef, st.H_oos)
    for h in 1:st.H_oos
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

    # --- 6. Build the out-of-sample harness EXACTLY ONCE, against held-out scenario
    # 1's aggregator LIST as the device STRUCTURE template — every held-out population
    # shares the SAME bus/device composition (structural congruence, `build_population`'s
    # own convention: device count/bus order depend only on `feeder`/`population`, never on
    # the seed). Pin the harness's battery controls to the in-sample optimum ONCE, before
    # the held-out loop (the build-once contract). --------------------------------------
    h_oos = build_stochastic_oos_harness(
        feeder,
        pf,
        held_out_aggs[1];
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )

    # Snapshot the harness's as-built solver conditioning BEFORE any solve. A retry
    # escalation inside `solve_with_retry!` is sticky on the model; restoring this baseline
    # before every held-out re-solve (below) keeps each draw's exactness verdict independent
    # of whether an EARLIER draw escalated, so the held-out evaluation does not depend on draw
    # order.
    ladder_baseline = _snapshot_ladder_attrs(h_oos.model)

    for pin in h_oos.battery_pins
        batt = only(b for b in in_sample_battery if b.bus == pin.bus)
        # The committed values are raw value.() reads, so
        # interior-point noise can return p_ch = -1e-12 — pinning that against the
        # device's own p_ch ≥ 0 bound is a needless infeasibility risk. Free insurance:
        # clamp the (mathematically nonnegative) active pins at 0. q stays unclamped
        # (free-sign by construction).
        set_parameter_value.(pin.pin_p_ch, clamp.(batt.p_ch, 0.0, Inf))
        set_parameter_value.(pin.pin_p_dch, clamp.(batt.p_dch, 0.0, Inf))
        # Pin the committed reactive dispatch too when the
        # device carries one (FourQuadBESS) — q is first-stage, and the
        # in-sample entry above is guaranteed to carry :q whenever the harness pin does
        # (both walks key off the same device vars shape).
        haskey(pin, :pin_q) && set_parameter_value.(pin.pin_q, batt.q)
    end

    # --- 7. Held-out loop: re-slide every held-out scenario's own PV/demand/ambient data
    # onto the (never-rebuilt) harness and re-solve. A held-out draw that is genuinely
    # INFEASIBLE against the committed first-stage schedule (welfare_h = NaN +
    # infeasible_h mask + @warn) or whose re-solve the exactness gate refuses (inexact_h
    # mask + @warn) is skipped-and-reported, never allowed to abort the whole run after the
    # expensive extensive-form solve, and never silent. ------------------------------------
    welfare_h = Vector{Float64}(undef, st.H_oos)
    infeasible_h = fill(false, st.H_oos)
    inexact_h = fill(false, st.H_oos)
    socp_maxratio_h = fill(NaN, st.H_oos)
    for h in 1:st.H_oos
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

        _restore_ladder_attrs!(h_oos.model, ladder_baseline)   # draw-order independence
        welfare_h[h], infeasible_h[h], inexact_h[h] = solve_held_out!(h_oos, h)
        if !infeasible_h[h]
            socp_maxratio_h[h] = get(h_oos.ctx.meta, :socp_maxratio, NaN)
        end
    end

    # --- 8. the realized-vs-in-sample welfare gap: uniform-weight average across the
    # FEASIBLE AND EXACT held-out scenarios (an infeasible or inexact draw is reported via
    # its mask, never averaged in and never fabricated) minus the in-sample extensive
    # form's own expected-welfare objective value. When nothing is skipped this is the same
    # expression as sum(welfare_h)/H. -------------------------------------------------------
    usable = .!(infeasible_h .| inexact_h)
    n_usable = count(usable)
    realized_welfare = n_usable == 0 ? NaN : sum(welfare_h[usable]) / n_usable
    welfare_gap = realized_welfare - r.welfare

    return (;
        in_sample = (;
            welfare = r.welfare,
            dadp = r.dadp,
            expected_dadp = r.expected_dadp,
            probabilities = r.probabilities,
            socp_maxgap = r.socp_maxgap,
        ),
        oos = (;
            welfare_h,
            infeasible_h,
            inexact_h,
            socp_maxratio_h,
            realized_welfare,
            welfare_gap,
        ),
        # Documented status vocabulary (STATUS_VOCABULARY.run_stochastic).
        status = _stochastic_status(infeasible_h, inexact_h),
    )
end

"""
    _stochastic_status(infeasible_h[, inexact_h]) -> Symbol

`:oos_inexact_skipped` iff any held-out re-solve was refused by the exactness gate, else
`:oos_infeasible_skipped` iff any held-out draw was infeasible, else `:solved`. The status
names the more serious skip; the masks carry the full per-draw detail. The one-argument form
assumes no inexact draw.
"""
_stochastic_status(infeasible_h) =
    _stochastic_status(infeasible_h, falses(length(infeasible_h)))
function _stochastic_status(infeasible_h, inexact_h)
    any(inexact_h) && return :oos_inexact_skipped
    any(infeasible_h) && return :oos_infeasible_skipped
    return :solved
end

"""
    run_stochastic(s::Scenario) -> NamedTuple

Thin wrapper; knobs live on `Scenario.strategy::Stochastic` (`Stochastic()` defaults apply
for a non-Stochastic strategy). NamedTuple contract unchanged.

# Status and exceptions

The returned `status` is `:solved`, `:oos_infeasible_skipped` (a held-out draw was infeasible
and was skipped and reported) or `:oos_inexact_skipped` (a held-out re-solve was refused by the
SOCP exactness gate and was skipped and reported; takes precedence when both occur). Only a
`SolveFailedError` on an INFEASIBLE status and a held-out `CertificateError` of kind
`:socp_exact` are skipped; every other failure throws, including the in-sample exactness
refusal. See the [status & exception policy](@ref status-policy).
"""
function run_stochastic(s::Scenario)
    st = s.strategy isa Stochastic ? s.strategy : Stochastic()
    s_eff = st == s.strategy ? s : with_strategy(s, st)   # re-runs the strategy x pf check
    return _run_stochastic(s_eff, st)
end

"""
    run(st::Stochastic, s::Scenario) -> ScenarioResult

`welfare = in_sample.welfare`; `dadp = expected_dadp` as a `1 x T` row (first aggregator's
priced bus); `exact_maxgap = maximum(in_sample.socp_maxgap)` (NaN if empty);
`details::StochasticDetails`, carrying the run's own `status`.
"""
function run(st::Stochastic, s::Scenario)
    s_eff = st == s.strategy ? s : with_strategy(s, st)
    t0 = time_ns()
    r = _run_stochastic(s_eff, st)
    elapsed = (time_ns() - t0) / 1.0e9
    gap = isempty(r.in_sample.socp_maxgap) ? NaN : Float64(maximum(r.in_sample.socp_maxgap))
    return ScenarioResult(
        s_eff,
        Float64(r.in_sample.welfare),
        Matrix{Float64}(reshape(Vector{Float64}(r.in_sample.expected_dadp), 1, :)),
        gap,
        elapsed,
        StochasticDetails(r.in_sample, r.oos, r.status),
    )
end

export run_stochastic
