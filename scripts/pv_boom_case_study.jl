# scripts/pv_boom_case_study.jl
#
# PV-BOOM CASE STUDY — a narrative, showcase script sweeping PV penetration on the
# modified IEEE-13 feeder across BOTH layers of the framework:
#
#   Part A  — the operational layer: a PV-penetration sweep of `solve_welfare` +
#             `extract_dlmp`/`decompose_dlmp`, cross-checked against the declarative
#             `Scenario`/`run_scenario` entry point and against `solve_admm` (ADMM).
#   Part A2 — the documented SOCP/AC exactness boundary (EXACT-04), reproduced verbatim
#             on its certified 3-bus stress substrate — never re-derived/re-tuned.
#   Part B  — the planning layer: two IEEE-13-scale distributor specs (a low-PV
#             "baseline" at pv_mult=0.7 and a "boom" distributor reusing Part A's own
#             already-swept pv_mult=2.5 population — see Part B's own Deviation note for
#             why 0.0 cannot be used) play a Stackelberg-Nash investment game over a
#             shared transmission-reinforcement corridor (`run_nash!`), reporting the
#             converged investment response.
#
# PURE ORCHESTRATION (per this quick task's own scope note): every heavy call routes
# through the already-validated public API (`Scenario`/`run_scenario`, `solve_welfare`,
# `solve_admm`, `extract_dlmp`/`decompose_dlmp`, `ACPowerFlow`/`assert_ac_exact!`,
# `build_shared_transmission`/`run_nash!`). The ONLY new logic is: (1) the
# `pv_boom_population` PV-penetration wrapper — a thin re-parametrization of
# `TSODSO._default_house`, which ALREADY accepts `pv_scale` as a keyword,
# `build_population(:default, ...)` simply never varies it; (2) the local
# `pvboom_stress_feeder`/`pvboom_stress_house` reproduction of the certified EXACT-04
# fixture (test/fixtures_phase4.jl); (3) the `slice_aggregator` helper that carves a
# short sub-horizon out of an ALREADY-DRAWN Task-1 aggregator's own time series for the
# planning-layer game. No `src/` file is touched, no model/solver code is added here.
#
#   julia --project=. scripts/pv_boom_case_study.jl
#
using DrWatson
@quickactivate "TSODSO"

using TSODSO
using JuMP
using CSV, DataFrames
using Printf

# ── Constants ─────────────────────────────────────────────────────────────────────────
# PV_MULTS: 0.0 = pre-solar baseline, 1.0 = the existing documented :ieee13/:default
# calibration (TSODSO._IEEE13_PV_SCALE), 2.5 = the "boom" scenario this case study
# showcases. BASE_SEED anchors every sub-seeded draw (sub_seed) so the whole script is
# byte-reproducible end to end.
const PV_MULTS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
const BASE_SEED = 20260806
const T_FULL = 24

# ── Part A — the ONE new "glue" function this task adds ────────────────────────────────
#
# `pv_boom_population` mirrors `TSODSO.build_population`'s `:default` body EXACTLY (same
# `_load_buses`, same `_IEEE13_LOAD_SCALE`/`_IEEE123_LOAD_SCALE` etc., same battery
# sizing), except it scales the PV magnitude by `pv_mult` — a parametrization
# `TSODSO._default_house` already exposes as its own `pv_scale` keyword;
# `build_population` itself just never varies it. `pv_mult = 1.0` reproduces
# `build_population(:default, ...)` bit-for-bit (same seed ⇒ same per-bus profile
# draws), which is what lets Part A's own `Scenario`/`run_scenario` cross-check below
# hold to floating-point tolerance.
"""
    pv_boom_population(feeder, feeder_sym, profiles, seed, T, pv_mult) -> Vector{<:Aggregator}

One seeded residential `Aggregator` per real load bus of `feeder`, identical in every
respect to `TSODSO.build_population(:default, feeder, feeder_sym, profiles, seed)` except
the PV magnitude is `TSODSO._IEEE13_PV_SCALE (or _IEEE123_PV_SCALE) * pv_mult` instead of
the fixed default scale. `pv_mult = 1.0` is bit-identical to `:default`.
"""
function pv_boom_population(
    feeder,
    feeder_sym::Symbol,
    profiles,
    seed::Integer,
    T::Int,
    pv_mult::Real,
)
    buses = TSODSO._load_buses(feeder, feeder_sym)

    load_scale, pv_scale_base, dev_scale = if feeder_sym === :ieee123
        (TSODSO._IEEE123_LOAD_SCALE, TSODSO._IEEE123_PV_SCALE, TSODSO._IEEE123_DEV_SCALE)
    else
        (TSODSO._IEEE13_LOAD_SCALE, TSODSO._IEEE13_PV_SCALE, TSODSO._IEEE13_DEV_SCALE)
    end
    pv_scale = pv_scale_base * pv_mult

    return [
        TSODSO._default_house(
            bus,
            profiles,
            seed,
            T;
            φ = 0.90,
            load_scale = load_scale,
            pv_scale = pv_scale,
            dev_scale = dev_scale,
            batt_pmax = 0.5 * load_scale,
            batt_emax = 2.0 * load_scale,
            batt_soc0 = 1.0 * load_scale,
        ) for bus in buses
    ]
end

println("="^96)
println("PV-BOOM CASE STUDY — Part A: PV-penetration operational sweep (IEEE-13, T=24)")
println("="^96)

# `λ₀` (the :mem MEM/wholesale price shape) does not depend on pv_mult (build_price's
# `:mem` selector ignores its `profiles` argument, per materialize.jl) — captured once,
# below, from the pv_mult=1.0 iteration for reuse in Part A's ADMM cross-check and
# Part B's planning-layer horizon slice.
sweep_rows = NamedTuple[]
ctx_by_mult = Dict{Float64, Any}()
aggs_by_mult = Dict{Float64, Any}()
feeder_by_mult = Dict{Float64, Any}()
λ0_full = nothing

for pv_mult in PV_MULTS
    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(BASE_SEED, :profiles), T = T_FULL)
    λ0 = build_price(:mem, T_FULL, profiles)
    aggs = pv_boom_population(
        feeder,
        :ieee13,
        profiles,
        sub_seed(BASE_SEED, :population),
        T_FULL,
        pv_mult,
    )
    global λ0_full
    λ0_full === nothing && (λ0_full = λ0)

    row = try
        ctx, welfare, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_FULL,
            λ₀ = λ0,
            allow_export = true,
        )
        dlmp = extract_dlmp(ctx)
        decomp = decompose_dlmp(ctx)
        ctx_by_mult[pv_mult] = ctx
        aggs_by_mult[pv_mult] = aggs
        feeder_by_mult[pv_mult] = feeder
        (;
            pv_mult,
            status = "ok",
            welfare,
            exact_maxgap = ctx.meta[:socp_maxgap],
            dlmp,
            decomp,
        )
    catch e
        (; pv_mult, status = "failed", reason = sprint(showerror, e))
    end
    push!(sweep_rows, row)
    @printf(
        "  pv_mult=%.2f -> %-6s%s\n",
        pv_mult,
        row.status,
        row.status == "ok" ? @sprintf(
            "  welfare=%.6f  exact_maxgap=%.3e",
            row.welfare,
            row.exact_maxgap,
        ) : "  (" * first(row.reason, 120) * ")"
    )
end
flush(stdout)

n_ok = count(r -> r.status == "ok", sweep_rows)
println("\n$(n_ok)/$(length(PV_MULTS)) pv_mult points solved successfully.")

# ── Part A, declarative leg — cross-check against Scenario/run_scenario ────────────────
#
# The sweep above CANNOT use `Scenario` directly: its schema (feeder/strategy/seed/T/
# population/price/allow_export/ADMM knobs, `src/experiments/Scenario.jl`) has no
# PV-penetration selector — `pv_boom_population` exists precisely because
# `materialize.jl`'s own `build_population` never varies `pv_scale`. But the pv_mult=1.0
# point IS exactly the `:default` population, so `Scenario`'s own declarative entry point
# is exercised here as an independent cross-check at that one point.
println("\n" * "-"^96)
println("Declarative leg: Scenario(...)/run_scenario cross-check @ pv_mult=1.0")
println("-"^96)

scenario_baseline = Scenario(
    name = "pv_boom_baseline",
    feeder = :ieee13,
    strategy = :centralized,
    seed = BASE_SEED,
    T = T_FULL,
)
scenario_result = run_scenario(scenario_baseline)

row1 = sweep_rows[findfirst(r -> r.pv_mult == 1.0, sweep_rows)]
aggs1 = aggs_by_mult[1.0]
feeder1 = feeder_by_mult[1.0]
load_buses1 = sort([a.bus for a in aggs1])
direct_dadp1 = row1.dlmp[load_buses1, :]

welfare_match = isapprox(scenario_result.welfare, row1.welfare; rtol = 1e-8, atol = 1e-8)
dadp_match = isapprox(scenario_result.dadp, direct_dadp1; rtol = 1e-6, atol = 1e-8)
@printf(
    "  Scenario welfare=%.6f vs direct pv_mult=1.0 welfare=%.6f -> match=%s\n",
    scenario_result.welfare,
    row1.welfare,
    welfare_match
)
@printf(
    "  Scenario dadp vs direct pv_mult=1.0 dadp (load buses) -> match=%s (max|Δ|=%.3e)\n",
    dadp_match,
    maximum(abs.(scenario_result.dadp .- direct_dadp1))
)
welfare_match && dadp_match ||
    error(
        "pv_boom_case_study: the declarative Scenario/run_scenario leg does NOT " *
        "reproduce the direct pv_mult=1.0 sweep point to tolerance — the two code " *
        "paths have drifted apart (this must never happen: same seed, same T, same " *
        "population).",
    )

# ── Part A, ADMM cross-check @ pv_mult=1.0 ONLY ────────────────────────────────────────
#
# ρ=100.0 is the ONE point already documented/validated for the default :ieee13/:default
# calibration (Scenario.jl's own docstring) — the ADMM leg is deliberately run ONLY here,
# reusing the SAME feeder/aggs/λ₀ as the sweep point (never re-materialized).
println("\n" * "-"^96)
println("ADMM cross-check @ pv_mult=1.0 (ρ=100.0)")
println("-"^96)

admm_result = solve_admm(
    feeder1,
    ConvexBranchFlow(),
    aggs1;
    T = T_FULL,
    λ₀ = λ0_full,
    ρ = 100.0,
    allow_export = true,
)

welfare_gap_rel = abs(admm_result.welfare - row1.welfare) / abs(row1.welfare)
centralized_dadp_at_loads = row1.dlmp[load_buses1, :]
dadp_maxgap = maximum(abs.(admm_result.dadp .- centralized_dadp_at_loads))
@printf("  centralized welfare = %.6f\n", row1.welfare)
@printf("  ADMM welfare        = %.6f  (relative gap = %.3e)\n", admm_result.welfare, welfare_gap_rel)
@printf("  ADMM iters          = %d\n", admm_result.iters)
@printf("  max|DADP_admm - DADP_centralized| = %.3e\n", dadp_maxgap)

# ── Part A persistence: DrWatson raw data + diff-friendly CSV summary ──────────────────
mkpath(datadir("pv_boom"))
DrWatson.wsave(
    datadir("pv_boom", "results.jld2"),
    Dict{String, Any}(
        "pv_mults" => PV_MULTS,
        "sweep" => sweep_rows,
        "admm_crosscheck" => (;
            pv_mult = 1.0,
            welfare_centralized = row1.welfare,
            welfare_admm = admm_result.welfare,
            dadp_maxgap = dadp_maxgap,
            residuals = admm_result.residuals,
        ),
    ),
)
println("\nwrote ", datadir("pv_boom", "results.jld2"))

mkpath(projectdir("results", "pv_boom"))
baseline_idx = findfirst(r -> r.pv_mult == 0.0, sweep_rows)
baseline_welfare = sweep_rows[baseline_idx].status == "ok" ? sweep_rows[baseline_idx].welfare : NaN
summary_df = DataFrame(
    pv_mult = Float64[r.pv_mult for r in sweep_rows],
    status = String[r.status for r in sweep_rows],
    welfare = Float64[r.status == "ok" ? r.welfare : NaN for r in sweep_rows],
    exact_maxgap = Float64[r.status == "ok" ? r.exact_maxgap : NaN for r in sweep_rows],
    welfare_delta_vs_baseline = Float64[
        r.status == "ok" && isfinite(baseline_welfare) ? r.welfare - baseline_welfare : NaN for
        r in sweep_rows
    ],
)
CSV.write(projectdir("results", "pv_boom", "summary.csv"), summary_df)
println("wrote ", projectdir("results", "pv_boom", "summary.csv"))

# ════════════════════════════════════════════════════════════════════════════════════
# Part A2 — the known SOCP/AC exactness boundary (EXACT-04), REPRODUCED, never re-derived
# ════════════════════════════════════════════════════════════════════════════════════
println("\n" * "="^96)
println("PV-BOOM CASE STUDY — Part A2: the documented EXACT-04 finding, reproduced")
println("="^96)

# Verbatim reproduction of the certified 3-bus stress substrate (test/fixtures_phase4.jl
# `high_pv_feeder`/`build_high_pv_aggregators`/`_house_aggregator`, also cross-referenced
# by test/test_ac_oracle.jl:180-260 and scripts/socp_applicability_sweep.jl:130-165).
# Reproduced LOCALLY (this file, per this quick task's own scope note) rather than
# `using` the test fixture module (src/ and scripts/ must never depend on test/).
function pvboom_stress_feeder(; vmax::Real = 1.05)
    return Feeder(
        [Bus(1, 0.95, vmax, true), Bus(2, 0.95, vmax, false), Bus(3, 0.95, vmax, false)],
        [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)],
        1,
    )
end

function pvboom_stress_house(
    bus::Int;
    pv_scale::Real,
    load_scale::Real,
    seed::Integer = 20260406,
    T::Int = 24,
)
    prof = generate_profiles(; seed = seed + bus, T = T)
    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0,
        0.5,
        TSODSO._temperature_profile(T),
    )
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        0.1,
        0.0,
        0.2,
        0.1,
        3.8,
        6.2,
        8.9,
        Float64[pv_scale * p for p in prof.pv],
    )
    Pdc = Float64[load_scale * d for d in prof.demand]
    return Aggregator(bus, 0.95, [therm, defer, batt], Pdc)
end

stress_feeder = pvboom_stress_feeder(; vmax = 1.05)
stress_aggs = [
    pvboom_stress_house(bus; pv_scale = 1.2, load_scale = 0.2) for
    bus in 2:length(stress_feeder.buses)
]
λ0_stress = build_price(:mem, T_FULL, nothing)   # :mem ignores `profiles`

# SOCP solve with `rtol_exact=1.0`: the ONE documented diagnostic override this plan
# authorizes (see this file's own module-level constraint list) — it changes ZERO code
# in `solve_welfare`/`welfare_solve.jl`. The ACTUAL exactness verdict below comes from
# `assert_ac_exact!`'s own standard `rtol=1e-4`, never from this loosened internal gate.
ctx_socp, cost_socp, _ = solve_welfare(
    stress_feeder,
    ConvexBranchFlow(),
    stress_aggs;
    T = T_FULL,
    λ₀ = λ0_stress,
    allow_export = true,
    rtol_exact = 1.0,
)
ctx_ac, cost_ac, _ = solve_welfare(
    stress_feeder,
    ACPowerFlow(),
    stress_aggs;
    T = T_FULL,
    λ₀ = λ0_stress,
    allow_local = true,
    allow_export = true,
)

ac_report = TSODSO.assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)
inexact_hours = [row.t for row in ac_report.hours if !row.exact]

@printf("  obj_gap (SOCP - AC)     = %.6e\n", ac_report.obj_gap)
@printf("  socp_maxgap (PF-04)     = %.6e\n", ctx_socp.meta[:socp_maxgap])
@printf("  inexact hours           = %d / %d  %s\n", length(inexact_hours), T_FULL, inexact_hours)

isempty(inexact_hours) && error(
    "pv_boom_case_study: the EXACT-04 reproduction came back ALL-EXACT — this is a " *
    "signal something has drifted from the certified test/fixtures_phase4.jl " *
    "high_pv_feeder/build_high_pv_aggregators substrate (pv_scale=1.2, load_scale=0.2, " *
    "vmax=1.05). Per this task's own contract: stop and report the discrepancy rather " *
    "than silently accepting a different-looking result.",
)
println("  -> the documented EXACT-04 finding, reproduced: the SOCP relaxation is " *
        "genuinely INEXACT at $(length(inexact_hours)) hour(s) on the certified stress fixture.")

# ════════════════════════════════════════════════════════════════════════════════════
# Part B — feeding the boom into the planning layer (NASH-01/02)
# ════════════════════════════════════════════════════════════════════════════════════
println("\n" * "="^96)
println("PV-BOOM CASE STUDY — Part B: planning-layer Stackelberg-Nash investment response")
println("="^96)

# Short contiguous afternoon PV-peak sub-horizon (materialize.jl's own documented
# afternoon-peak window), sliced from Task-1-methodology populations — NO new profile
# draw (generate_profiles is a Markov transition, not re-sliceable by re-calling it at a
# smaller T; slicing the ALREADY-materialized arrays is the only way to reuse the exact
# same drawn realization).
#
# Deviation (Rule 1, discovered during execution — a genuine STRUCTURAL finding, not a
# tuning knob): the plan's own suggested "baseline" distributor is pv_mult=0.0 (ZERO PV).
# `solve_stackelberg!`'s Benders master ALWAYS proposes z=0 as its very FIRST trial (no
# cuts yet ⇒ the epigraph variables sit at their free lower bounds ⇒ z is forced to its
# own box lower bound, 0) — and ONLY the follower's shell transmission-corridor LP gates
# feasibility before that trial reaches the oracle (benders.jl's own documented ordering);
# the oracle itself has NO feasibility-cut recovery path. With pv_mult=0.0 the local
# network has LITERALLY ZERO generation anywhere, so z=0 (no frontier import at all) is
# PHYSICALLY infeasible — not a tunable margin issue — and `solve_planning_oracle!` raises
# a hard `INFEASIBLE` `ErrorException` on the unconditional first trial, before any
# Benders cut can even be attempted. Verified directly: `pv_mult ∈ {0.0, 0.3, 0.5}` all
# raise INFEASIBLE at z=0 on this sliced sub-horizon; `pv_mult >= 0.7` is feasible (enough
# curtailable local PV to net exactly to the zero-import trial via the continuous
# `0 <= pv_used <= Ppv` freedom). The "baseline" distributor below is therefore
# `pv_mult = 0.7` (materialized via the SAME `pv_boom_population` + `BASE_SEED`
# methodology as the Part-A sweep, just not one of the 6 headline `PV_MULTS` sweep
# points) rather than the plan's suggested `0.0` — preserving the intended "low PV vs PV
# boom" contrast against `pv_mult = 2.5` while keeping the game playable under
# `solve_stackelberg!`'s existing (unmodified, per this task's own `src/`-untouched
# scope) Benders design. This is reported here, in `findings.txt`, and in the SUMMARY —
# never silently substituted.
const BASELINE_PV_MULT = 0.7
const BOOM_PV_MULT = 2.5
const PLANNING_HOURS = 13:18
const T_PLANNING = length(PLANNING_HOURS)

"""
    slice_aggregator(agg, hrs, T_planning) -> Aggregator

Build a NEW `Aggregator` (Thermostatic + Deferrable + PVBattery) whose time-series fields
(`Tout`, `Ppv`, `Pdc`) are sliced to `hrs` from `agg`'s OWN already-drawn arrays — no new
`generate_profiles` call — keeping every scalar device parameter identical.

Deviation (Rule 1, discovered during execution): the Deferrable's `t_start`/`t_end`
window (`8:16` in the full T=24 horizon, per `_default_house`) is itself a set of
absolute hour INDICES, so it cannot be copied verbatim into a T_planning=6 sub-horizon
(`Deferrable`'s own `contribute!` guard throws when `t_end > T`). It is re-expressed in
the sub-horizon's own local indexing (`t - (first(hrs)-1)`, clamped to `1:T_planning`),
which for `hrs = 13:18` keeps the genuine overlap of the original 8:16 window with the
13:16 sub-range (local hours 1:4) — i.e. this is a coordinate change, not a parameter
retune: the deferrable task is still elastic across the SAME physical hours the original
window covered, restricted to the shorter horizon this game is played over.
"""
function slice_aggregator(agg, hrs::AbstractRange, T_planning::Int)
    therm0, defer0, batt0 = agg.devices[1], agg.devices[2], agg.devices[3]
    offset = first(hrs) - 1

    therm = Thermostatic(
        agg.bus,
        therm0.α,
        therm0.β,
        therm0.Tmin,
        therm0.Tmax,
        therm0.Tin0,
        therm0.Pmin,
        therm0.Pmax,
        therm0.b,
        Float64.(therm0.Tout[hrs]),
    )

    t_start_local = clamp(defer0.t_start - offset, 1, T_planning)
    t_end_local = clamp(defer0.t_end - offset, 1, T_planning)
    t_end_local < t_start_local && (t_start_local = t_end_local)
    defer = Deferrable(
        agg.bus,
        t_start_local,
        t_end_local,
        defer0.E,
        defer0.Pmax,
        defer0.b;
        E_min = defer0.E_min,
    )

    batt = PVBattery(
        agg.bus,
        batt0.η,
        batt0.Δt,
        batt0.Pmax,
        batt0.Emin,
        batt0.Emax,
        batt0.soc0,
        batt0.λ_min,
        batt0.λ_med,
        batt0.λ_max,
        Float64.(batt0.Ppv[hrs]),
    )

    return Aggregator(agg.bus, agg.φ, [therm, defer, batt], Float64.(agg.Pdc[hrs]))
end

λ0_planning = Float64.(λ0_full[PLANNING_HOURS])

# BASELINE_PV_MULT (0.7) is not one of Part A's 6 headline PV_MULTS sweep points, so it is
# materialized here via the IDENTICAL pv_boom_population + BASE_SEED methodology (see the
# Deviation note above `slice_aggregator` for why 0.0 cannot be used). BOOM_PV_MULT (2.5)
# IS one of Part A's own already-swept points, reused directly with no re-materialization.
feeder_for_baseline_pop = build_feeder(:ieee13)
profiles_for_baseline_pop =
    generate_profiles(; seed = sub_seed(BASE_SEED, :profiles), T = T_FULL)
aggs_baseline_full = pv_boom_population(
    feeder_for_baseline_pop,
    :ieee13,
    profiles_for_baseline_pop,
    sub_seed(BASE_SEED, :population),
    T_FULL,
    BASELINE_PV_MULT,
)
aggs_baseline_sliced =
    [slice_aggregator(a, PLANNING_HOURS, T_PLANNING) for a in aggs_baseline_full]
aggs_boom_sliced =
    [slice_aggregator(a, PLANNING_HOURS, T_PLANNING) for a in aggs_by_mult[BOOM_PV_MULT]]

# Anchor the shared-model calibration to already-known quantities (master.jl's own
# Pitfall M1 contract: an aggressively low α_op_lb/α_x_lb is always SAFE, only slower to
# tighten): read each distributor's own sliced-horizon welfare + peak frontier-import
# magnitude via a quick `solve_welfare` call, mirroring how Part A itself solves.
function distributor_calibration(aggs, λ0)
    feeder = build_feeder(:ieee13)
    ctx, welfare, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = length(λ0),
        λ₀ = λ0,
        allow_export = true,
    )
    peak_import = maximum(abs.(value.(ctx.meta[:p_import])))
    local_price = sum(extract_dlmp(ctx)) / length(extract_dlmp(ctx))
    return (; welfare, peak_import, local_price)
end

calib_base = distributor_calibration(aggs_baseline_sliced, λ0_planning)
calib_boom = distributor_calibration(aggs_boom_sliced, λ0_planning)
@printf(
    "  baseline (pv_mult=%.1f): welfare=%.4f  peak|p_import|=%.4f  local_price=%.4f\n",
    BASELINE_PV_MULT,
    calib_base.welfare,
    calib_base.peak_import,
    calib_base.local_price
)
@printf(
    "  boom     (pv_mult=%.1f): welfare=%.4f  peak|p_import|=%.4f  local_price=%.4f\n",
    BOOM_PV_MULT,
    calib_boom.welfare,
    calib_boom.peak_import,
    calib_boom.local_price
)

# Deviation (Rule 1, discovered during execution): this IEEE-13-scale planning game has
# never been exercised at this scale before (every prior `test_planning_nash.jl` fixture
# is a hand-derived toy 2-bus feeder). The FIRST calibration attempt below
# (corridor_cap=1.0, x_inv_max[i]=3×peak_import[i], y_max[i]=3×peak_import[i],
# α_op_lb[i]=-2×|welfare_i|, α_x_lb=0.0, c_y=0.3, c_inv=[1.0,1.0], c_op[i]=10% of each
# distributor's own local energy price) either converges directly or raises inside
# `run_nash!`/`solve_stackelberg!` naming the exhausted bound — the retry loop below
# widens the bounds geometrically (never re-tuning the physical data) until it converges,
# recording exactly which attempt succeeded.
function build_specs(margin::Real, α_margin::Real, c_op_frac::Real)
    peak_b, peak_m = calib_base.peak_import, calib_boom.peak_import
    corridor_cap = 1.0
    x_inv_max = [margin * max(peak_b, 1e-6), margin * max(peak_m, 1e-6)]
    y_max = copy(x_inv_max)
    α_op_lb = [-α_margin * abs(calib_base.welfare), -α_margin * abs(calib_boom.welfare)]
    c_y = 0.3
    c_inv = [1.0, 1.0]
    c_op = [
        fill(c_op_frac * calib_base.local_price, T_PLANNING),
        fill(c_op_frac * calib_boom.local_price, T_PLANNING),
    ]

    specs = [
        (;
            feeder = build_feeder(:ieee13),
            pf = ConvexBranchFlow(),
            aggregators = aggs_baseline_sliced,
            λ₀ = λ0_planning,
            master_kwargs = (;
                c_y = c_y,
                y_max = y_max[1],
                α_op_lb = α_op_lb[1],
                α_x_lb = 0.0,
            ),
        ),
        (;
            feeder = build_feeder(:ieee13),
            pf = ConvexBranchFlow(),
            aggregators = aggs_boom_sliced,
            λ₀ = λ0_planning,
            master_kwargs = (;
                c_y = c_y,
                y_max = y_max[2],
                α_op_lb = α_op_lb[2],
                α_x_lb = 0.0,
            ),
        ),
    ]
    shared = build_shared_transmission(;
        N = 2,
        T = T_PLANNING,
        corridor_cap = corridor_cap,
        x_inv_max = x_inv_max,
        c_inv = c_inv,
        c_op = c_op,
    )
    return specs, shared
end

nash_result = nothing
attempts = [(3.0, 2.0, 0.10), (6.0, 4.0, 0.05), (12.0, 8.0, 0.02)]
last_err = nothing
for (attempt_idx, (margin, α_margin, c_op_frac)) in enumerate(attempts)
    specs, shared = build_specs(margin, α_margin, c_op_frac)
    z0 = zeros(2, T_PLANNING)
    global nash_result
    try
        nash_result = run_nash!(
            specs,
            shared;
            z0 = z0,
            tol_outer = 1e-4,
            max_sweeps = 100,
            checkpoint_dir = mktempdir(),
        )
        println(
            "  attempt $attempt_idx (margin=$margin, α_margin=$α_margin, " *
            "c_op_frac=$c_op_frac) -> CONVERGED",
        )
        break
    catch e
        global last_err = e
        println(
            "  attempt $attempt_idx (margin=$margin, α_margin=$α_margin, " *
            "c_op_frac=$c_op_frac) -> FAILED: " * first(sprint(showerror, e), 200),
        )
    end
end
nash_result === nothing && error(
    "pv_boom_case_study: run_nash! failed to converge across every calibration " *
    "attempt tried — last error: " * sprint(showerror, last_err),
)

@printf("\n  converged             = %s\n", nash_result.converged)
@printf("  sweeps                = %d\n", nash_result.sweeps)
println("  x_inv (baseline, boom) = ", nash_result.x_inv)
println("  z[1,:] (baseline)      = ", nash_result.z[1, :])
println("  z[2,:] (boom)          = ", nash_result.z[2, :])
nash_summary = TSODSO.trace_summary(nash_result.trace)
println("  trace summary          = ", nash_summary)

# ── Persist Task 2's additions into the SAME results.jld2 (never overwrite Task 1) ────
existing = DrWatson.wload(datadir("pv_boom", "results.jld2"))
existing["nash_result"] = (;
    z = nash_result.z,
    x_inv = nash_result.x_inv,
    converged = nash_result.converged,
    sweeps = nash_result.sweeps,
)
existing["ac_stress"] = (;
    obj_gap = ac_report.obj_gap,
    n_inexact_hours = length(inexact_hours),
    socp_maxgap = ctx_socp.meta[:socp_maxgap],
)
DrWatson.wsave(datadir("pv_boom", "results.jld2"), existing)
println("\nupdated ", datadir("pv_boom", "results.jld2"), " with nash_result/ac_stress")

# ── Findings write-up (committed, diff-friendly) ───────────────────────────────────────
findings_path = projectdir("results", "pv_boom", "findings.txt")
open(findings_path, "w") do io
    println(io, "PV-BOOM CASE STUDY — findings")
    println(io, "="^80)
    println(io)
    println(io, "Part A — PV-penetration operational sweep (IEEE-13, T=24)")
    println(io, "-"^80)
    for r in sweep_rows
        if r.status == "ok"
            @printf(io, "  pv_mult=%.2f  welfare=%.6f  exact_maxgap=%.3e\n", r.pv_mult, r.welfare, r.exact_maxgap)
        else
            @printf(io, "  pv_mult=%.2f  FAILED: %s\n", r.pv_mult, first(r.reason, 200))
        end
    end
    println(io)
    println(io, "Declarative Scenario/run_scenario cross-check @ pv_mult=1.0: welfare_match=$welfare_match, dadp_match=$dadp_match")
    println(io)
    @printf(
        io,
        "ADMM cross-check @ pv_mult=1.0 (ρ=100.0): welfare_centralized=%.6f welfare_admm=%.6f relative_gap=%.3e dadp_maxgap=%.3e iters=%d\n",
        row1.welfare,
        admm_result.welfare,
        welfare_gap_rel,
        dadp_maxgap,
        admm_result.iters
    )
    println(io)
    println(io, "Part A2 — the documented EXACT-04 finding, reproduced")
    println(io, "-"^80)
    println(
        io,
        "On the certified 3-bus high-PV stress fixture (pv_scale=1.2, load_scale=0.2, " *
        "vmax=1.05, r=x=0.05 branches — test/fixtures_phase4.jl high_pv_feeder / " *
        "build_high_pv_aggregators), the SOC branch-flow relaxation is genuinely " *
        "INEXACT (EXACT-04) at $(length(inexact_hours))/$T_FULL hours: $inexact_hours.",
    )
    @printf(io, "obj_gap (SOCP welfare - AC welfare) = %.6e\n", ac_report.obj_gap)
    @printf(io, "socp_maxgap (PF-04, loosened rtol_exact=1.0 diagnostic)   = %.6e\n", ctx_socp.meta[:socp_maxgap])
    println(
        io,
        "This is the ONE documented diagnostic-override reproduction this case study " *
        "showcases (EXACT-04) — never re-derived or re-tuned from the certified fixture.",
    )
    println(io)
    println(io, "Part B — planning-layer Stackelberg-Nash investment response")
    println(io, "-"^80)
    println(
        io,
        "Two IEEE-13-scale distributors — 'baseline' (pv_mult=$(BASELINE_PV_MULT)) and " *
        "'boom' (pv_mult=$(BOOM_PV_MULT)) — built via the SAME pv_boom_population/" *
        "BASE_SEED methodology as Part A, sliced to the afternoon PV-peak sub-horizon " *
        "hours $(first(PLANNING_HOURS)):$(last(PLANNING_HOURS)) — play a Gauss-Seidel " *
        "Stackelberg-Nash investment game over a shared transmission-reinforcement " *
        "corridor (run_nash!).",
    )
    println(
        io,
        "DEVIATION (structural, not a tuning knob): the plan's own suggested baseline " *
        "pv_mult=0.0 is UNCONDITIONALLY infeasible under solve_stackelberg!'s Benders " *
        "design — its very first trial is always z=0 (no cuts yet), and a zero-PV " *
        "network has no way to self-balance with zero frontier import; this raises a " *
        "hard INFEASIBLE error before any feasibility cut can even be attempted (only " *
        "the follower's shell corridor LP gates feasibility pre-oracle, never the " *
        "oracle itself). Verified pv_mult ∈ {0.0, 0.3, 0.5} all fail this way; " *
        "pv_mult >= 0.7 is feasible. baseline=0.7 was substituted to keep the 'low PV " *
        "vs PV boom' contrast playable without touching src/.",
    )
    @printf(io, "Converged: %s  (sweeps=%d)\n", nash_result.converged, nash_result.sweeps)
    println(io, "Converged investment x_inv (baseline, boom) = ", nash_result.x_inv)
    if isapprox(nash_result.x_inv[1], nash_result.x_inv[2]; rtol = 1e-3)
        println(
            io,
            "HONEST FINDING: the two distributors' converged investments did NOT " *
            "differentiate at this calibration — reported as-is, not forced apart.",
        )
    else
        println(
            io,
            "The boom distributor's converged investment differs from the baseline's " *
            "(a genuine, distributor-differentiated investment response to the higher " *
            "PV-penetration afternoon flow).",
        )
    end
end
println("wrote ", findings_path)

println("\n" * "="^96)
println("PV-BOOM CASE STUDY complete.")
println("="^96)
