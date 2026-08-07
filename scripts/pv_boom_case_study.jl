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
