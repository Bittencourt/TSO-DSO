# scripts/socp_highpv_remeasure.jl
#
# DEV-09 -- SOCP exactness RE-MEASUREMENT in the high-PV regime, with and without optimal Q
# (SmartInverterPV), plus a POST-HOC Volt-VAR droop comparator.
#
#   julia --project=. scripts/socp_highpv_remeasure.jl
#
# PURE ORCHESTRATION through the public API. The certified 3-bus high-PV stress substrate
# (test/fixtures_ieee13.jl `high_pv_feeder` / `build_high_pv_aggregators`, as already reproduced
# in scripts/pv_boom_case_study.jl) is COPIED VERBATIM, never re-tuned. Seeds 20260719..20260723,
# PV scales {0.5 (the documented exact regime), 1.2 (the stress regime)}.
#
# Variants (all on the SAME fixture; only the added device differs):
#   "active_only"        -- the certified population (Thermostatic + Deferrable + PVBattery).
#   "with_optimal_q"     -- plus one SmartInverterPV per house: its own panel (0.5 x the house PV
#                           availability) with a free-sign q inside the apparent-power cone.
#                           NOTE: this also adds active PV, so it is not a pure-Q ablation.
#   "q_only_capability"  -- plus one SmartInverterPV with ZERO panel (Ppv = 0): the cone leaves a
#                           pure reactive-support capability, isolating the effect of optimal Q.
#
# VERDICTS come ONLY from the standard gate: `solve_welfare` runs `assert_socp_exact!` at its
# default rtol_exact = 1e-4 with the hybrid floor. A `CertificateError` is recorded as a
# first-class verdict "refused_<kind>" (honesty policy: a refusal is a valid measurement):
# "refused_socp_exact" = the SOCP cone certificate itself refused (inexact relaxation);
# any other kind (e.g. battery complementarity) refused a LATER certificate, i.e. the cone gate
# had already passed (`socp_gate_passed = true`). Only AFTER a refused_socp_exact is the point
# re-solved with rtol_exact = 1e12 -- purely to harvest the maxgap / hybrid_ratios diagnostics;
# that re-solve never decides the verdict and no tolerance or tau is ever raised.
#
# DROOP COMPARATOR (POST HOC ONLY -- never a convex constraint): on the FIXED active dispatch of
# the solved point, `ac_feasibility_status` (ACPowerFlow(; limits = false) physics) gives the
# per-hour maximum bus voltage; the IEEE 1547-2018 Category-B Volt-VAR curve (points
# (0.92, +0.44) (0.98, 0) (1.02, 0) (1.08, -0.44) of the nameplate, positive = injection)
# is evaluated point-wise at that voltage, summed over the SmartInverterPV devices, and compared
# with the q the convex optimum actually dispatched. The physics model does not include the
# SmartInverterPV q (it is the dispatch-fixed, load-reactive-only physics), so the voltage fed to
# the curve is the voltage the droop would SEE, not a closed-loop equilibrium.
#
# Rows are upserted keyed (fixture, variant, seed) into results/socp_highpv/highpv_exactness.csv
# (String keys only; `cols = :union`). One process at a time.

using DrWatson
@quickactivate "TSODSO"

using TSODSO
using TSODSO:
    CertificateError,
    Feeder,
    Bus,
    Branch,
    SmartInverterPV,
    PVBattery,
    build_price,
    hybrid_ratios
using TSODSO: Thermostatic, Deferrable, Aggregator
using TSODSO.JuMP
using CSV, DataFrames
using Printf

const T = 24
const SEEDS = 20260719:20260723
const PV_SCALES = (0.5, 1.2)
const VARIANTS = ("active_only", "with_optimal_q", "q_only_capability")
const OUT = projectdir("results", "socp_highpv", "highpv_exactness.csv")

# ---- certified high-PV stress substrate (copied verbatim, never re-tuned) -------------------
function highpv_feeder()
    return Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)],
        [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)],
        1,
    )
end

function highpv_house(bus::Int; pv_scale::Real, seed::Integer, load_scale::Real = 0.2)
    prof = TSODSO.generate_profiles(; seed = seed + bus, T = T)
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

function sipv_for(a::Aggregator, variant::String)
    pv = first(d.Ppv for d in a.devices if d isa PVBattery)
    if variant == "with_optimal_q"
        Ppv = 0.5 .* pv
        return SmartInverterPV(a.bus, 1.1 * maximum(Ppv), Ppv)
    else # q_only_capability: zero panel, same nameplate as the with_optimal_q inverter
        return SmartInverterPV(a.bus, 1.1 * 0.5 * maximum(pv), zeros(T))
    end
end

function build_aggs(pv_scale::Real, seed::Integer, variant::String)
    base = [highpv_house(b; pv_scale = pv_scale, seed = seed) for b in 2:3]
    variant == "active_only" && return base
    return [
        Aggregator(
            a.bus,
            a.φ,
            TSODSO.AbstractDevice[a.devices...; sipv_for(a, variant)],
            a.Pdc,
        ) for a in base
    ]
end

# ---- Volt-VAR droop (IEEE 1547-2018 Category B), POST HOC ONLY -------------------------------
const DROOP_V = (0.92, 0.98, 1.02, 1.08)
const DROOP_QFRAC = 0.44
function droop_qfrac(V::Real)
    V <= DROOP_V[1] && return DROOP_QFRAC
    V < DROOP_V[2] && return DROOP_QFRAC * (DROOP_V[2] - V) / (DROOP_V[2] - DROOP_V[1])
    V <= DROOP_V[3] && return 0.0
    V < DROOP_V[4] && return -DROOP_QFRAC * (V - DROOP_V[3]) / (DROOP_V[4] - DROOP_V[3])
    return -DROOP_QFRAC
end

# ---- one measurement point -------------------------------------------------------------------
sanitize(s) = replace(first(string(s), 120), ',' => ';', '\n' => ' ', '"' => '\'')

function solve_point(feeder, aggs, λ0; rtol_exact)
    return solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ0,
        allow_export = true,
        rtol_exact = rtol_exact,
    )
end

function measure(pv_scale::Real, seed::Integer, variant::String)
    feeder = highpv_feeder()
    aggs = build_aggs(pv_scale, seed, variant)
    λ0 = build_price(:mem, T, nothing)
    row = Dict{Symbol, Any}(
        :fixture => "highpv_3bus_pv$(pv_scale)",
        :variant => variant,
        :seed => Int(seed),
        :pv_scale => Float64(pv_scale),
    )
    ctx = nothing
    obj = missing
    try
        ctx, obj, _ = solve_point(feeder, aggs, λ0; rtol_exact = 1e-4)
        row[:verdict] = "exact"
        row[:socp_gate_passed] = true
    catch e
        if e isa CertificateError
            # Which certificate refused? `solve_welfare` runs the SOCP exactness gate FIRST and
            # the battery / EV complementarity certificates after it, so any non-:socp_exact
            # refusal means the cone gate had already PASSED at this point (cone maxgap is then
            # unavailable: no ctx is returned from a refused solve).
            row[:verdict] = "refused_" * String(e.kind)
            row[:socp_gate_passed] = e.kind !== :socp_exact
            row[:detail] = sanitize(e.msg)
            if e.kind === :socp_exact
                try   # diagnostics of the refused point ONLY; never decides the verdict
                    ctx, obj, _ = solve_point(
                        feeder,
                        build_aggs(pv_scale, seed, variant),
                        λ0;
                        rtol_exact = 1e12,
                    )
                catch e2
                    row[:detail] =
                        row[:detail] * " | diag_resolve_failed:" * sanitize(typeof(e2))
                end
            end
        else
            row[:verdict] = "solve_failed"
            row[:detail] = sanitize(sprint(showerror, e))
        end
    end
    ctx === nothing && return row
    row[:welfare] = Float64(obj)
    rows = hybrid_ratios(ctx)
    row[:maxgap] = maximum(r.gap for r in rows)
    row[:max_ratio] = maximum(r.ratio for r in rows)
    row[:n_ratio_gt1] = count(r -> r.ratio > 1, rows)
    row[:worst_branch] = rows[1].b
    row[:worst_hour] = rows[1].t

    # q the convex optimum dispatched (summed over SmartInverterPV devices) + their nameplates
    sip = [d for a in aggs for d in a.devices if d isa SmartInverterPV]
    q_opt = zeros(T)
    for a in aggs, (i, v) in enumerate(ctx.agg_device_vars[a.bus])
        if haskey(v, :q) && haskey(v, :pv_used)
            q_opt .+= Float64[value(v.q[t]) for t in 1:T]
        end
    end
    # fixed-dispatch physics (limits = false)
    nets = [Float64[value(x) for x in n.net] for n in ctx.meta[:agg_net]]
    st = ac_feasibility_status(feeder, aggs, nets; T = T)
    row[:physics_status] = String(st.status)
    if !isempty(st.hours)
        vmax_h = [h.max_voltage for h in st.hours]
        row[:physics_vmax] = maximum(vmax_h)
        row[:physics_hours_above_1p02] = count(>(1.02), vmax_h)
        row[:physics_n_voltage_violations] = st.n_voltage_violations
        if !isempty(sip)
            q_droop = [sum(droop_qfrac(V) * d.S_inv for d in sip) for V in vmax_h]
            row[:q_opt_absmax] = maximum(abs, q_opt)
            row[:q_droop_absmax] = maximum(abs, q_droop)
            row[:q_droop_vs_opt_rms] = sqrt(sum(abs2, q_droop .- q_opt) / T)
            row[:q_sign_agree_hours] = count(
                t ->
                    abs(q_opt[t]) > 1e-6 &&
                    abs(q_droop[t]) > 1e-6 &&
                    sign(q_opt[t]) == sign(q_droop[t]),
                1:T,
            )
            row[:q_active_hours] = count(t -> abs(q_opt[t]) > 1e-6, 1:T)
        end
    end
    return row
end

function main()
    rows = Dict{Symbol, Any}[]
    for pv in PV_SCALES, variant in VARIANTS, seed in SEEDS
        r = measure(pv, seed, variant)
        @printf(
            "%-18s %-18s %d  %-26s maxgap=%s ratio=%s\n",
            r[:fixture],
            variant,
            seed,
            r[:verdict],
            get(r, :maxgap, "NA"),
            get(r, :max_ratio, "NA")
        )
        push!(rows, r)
    end
    cols = [
        :fixture,
        :variant,
        :seed,
        :pv_scale,
        :verdict,
        :welfare,
        :maxgap,
        :max_ratio,
        :socp_gate_passed,
        :n_ratio_gt1,
        :worst_branch,
        :worst_hour,
        :physics_status,
        :physics_vmax,
        :physics_hours_above_1p02,
        :physics_n_voltage_violations,
        :q_opt_absmax,
        :q_droop_absmax,
        :q_droop_vs_opt_rms,
        :q_sign_agree_hours,
        :q_active_hours,
        :detail,
    ]
    df_new = DataFrame([c => Any[get(r, c, missing) for r in rows] for c in cols])
    mkpath(dirname(OUT))
    keyfn(r) = (r.fixture, r.variant, r.seed)
    df_final = if isfile(OUT)
        old = CSV.read(OUT, DataFrame)
        nk = Set(keyfn(r) for r in eachrow(df_new))
        vcat(filter(r -> !(keyfn(r) in nk), old), df_new; cols = :union)
    else
        df_new
    end
    CSV.write(OUT, df_final)
    println("wrote ", OUT, " (", nrow(df_final), " rows)")
end

main()
