# scripts/demo_mpc_plots.jl
#
# Demo: the RECEDING-HORIZON CLOSED LOOP (MPC) — an example case + rich diagnostics.
#
# Phase 21's `run_mpc(s::Scenario)` re-solves a fixed-length window model (`MpcWindow`, built
# ONCE) every `mpc_step` hours, publishes only the first interval's DADP dual, propagates the
# measured battery/temperature state on the nominal plant, and benchmarks itself against a
# perfect-foresight day-ahead optimum over the SAME information set. This script runs ONE
# baseline example case end-to-end, then two single-knob sweeps (forecast-error magnitude and
# window length H), then a hand-driven pass that mirrors `run_mpc`'s loop VERBATIM (same
# parameter updates, same state propagation) while additionally RECORDING every resolve's full
# planned window — producing the classic receding-horizon "plan spaghetti" picture.
#
# Figures (PDF + PNG into results/demo_mpc_plots/):
#   1. mpc_price_diagnostics — published RTP vs day-ahead DADP, per-hour deviation,
#      step-to-step price jumps, cumulative deviation (the MpcTrace ledger, drawn hour by
#      hour), published-price markers colored by certificate provenance.
#   2. mpc_receding_plan    — INSIDE the loop: every resolve's planned 6-hour window (faded,
#      colored by resolve hour) vs the actually applied trajectory, for the published price,
#      battery SOC (with the hard terminal-SOC targets), indoor temperature (comfort band),
#      and the TSO↔DSO frontier exchange.
#   3. mpc_sweeps           — regret and price-consistency vs forecast-error magnitude and
#      vs window length H.
#   4. mpc_welfare_regret   — the information-set-fair welfare comparison and the published
#      vs day-ahead price-tracking scatter.
#
# Run:
#     julia --project=. scripts/demo_mpc_plots.jl

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO: propagate_soc, propagate_tin, draw_forecast_error, sub_seed  # unexported MPC seams
using CairoMakie
using Printf
using Statistics
using JuMP: value, dual, set_parameter_value, set_objective_coefficient

# -------------------------------------------------------------------------------------------
# Output directory + baseline example-case selectors.
# -------------------------------------------------------------------------------------------
const OUT = projectdir("results", "demo_mpc_plots")
mkpath(OUT)

saveboth(name, fig) =
    (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

# The baseline example case — the SAME fixture as the docs' Rung-8 literate page
# (docs/literate/mpc_rolling_horizon.jl, whose build verified all 19 resolves certify at the
# first tier on seed=1): full 24-hour day-ahead horizon on the IEEE-13 feeder with the
# default residential population, a 6-hour receding window re-solved hourly, D-06's hard
# terminal-SOC equality ON, and a genuinely nonzero ±8% seeded PV/demand forecast error.
const T = 24
const H = 6
const FE = 0.08

s_base = Scenario(;
    name = "mpc-demo-baseline",
    feeder = :ieee13,
    T = T,
    mpc_H = H,
    mpc_step = 1,                # re-solve every real hour (classic receding horizon)
    mpc_terminal_soc = true,
    mpc_forecast_error = FE,
)                               # seed defaults to 1 (deterministic, INFRA-04)

# Certificate-provenance → color (run_mpc's D-04 ladder statuses).
const CERT_COLORS = Dict(
    :certified_convex_dual => :crimson,
    :certified_convex_dual_restricted => :darkorange,
    :local_ac_dual => :mediumpurple,
    :cert_failed => :black,
)
const CERT_LABELS = Dict(
    :certified_convex_dual => "certified (convex dual)",
    :certified_convex_dual_restricted => "certified (restricted-tier rescue)",
    :local_ac_dual => "AC-dual fallback",
    :cert_failed => "certification FAILED (reference price)",
)

println("="^78)
println("MPC receding-horizon closed loop — example case & diagnostics")
println("  feeder = ieee13, T = $T h, window H = $H h, mpc_step = 1 h, forecast error = ±$(100FE)%")
println("="^78)

# ===========================================================================================
# 1. BASELINE EXAMPLE CASE — run_mpc end-to-end (the public API, verbatim).
# ===========================================================================================
println("\n[1/4] Baseline example case: run_mpc (2 day-ahead benchmarks + 19 window resolves)...")
r = run_mpc(s_base)

pub_hours = 1:r.steps                      # published hours are ALWAYS 1:T-H+1 (Pitfall 5)
statuses = unique(r.trace.cert_status_trace)
println("  steps published : $(r.steps)  (= T - H + 1)")
@printf("  day-ahead welfare (FULL population, 24 h) : %12.5f\n", r.day_ahead_welfare)
@printf("  realized welfare  (closed loop, %d h)      : %12.5f\n", r.steps, r.realized_welfare)
@printf("  regret (info-set-fair, same %d h horizon)  : %12.5f\n", r.steps, r.regret)
@printf("  price jumps  max = %8.4f   mean = %8.4f\n", max_jump(r.trace), mean_jump(r.trace))
@printf("  final cumulative |RTP - DA| deviation     : %12.5f\n", last(r.trace.cum_deviation_trace))
println("  certificate statuses: ",
    join(["$(count(==(st), r.trace.cert_status_trace))× $(CERT_LABELS[st])" for st in statuses], ", "))
any_cert_failed(r.trace) && println("  ⚠ at least one resolve exhausted the escalation ladder")

# ===========================================================================================
# 2. SINGLE-KNOB SWEEPS — forecast-error magnitude and window length H.
#    (Only the non-baseline levels are re-run; each level is a full run_mpc closed loop.)
# ===========================================================================================
println("\n[2/4] Sweeps: forecast-error magnitude and window length...")
const FE_LEVELS = [0.00, 0.04, 0.08, 0.12]   # 0.08 is the baseline (reused, not re-run)
const H_LEVELS = [3, 6, 9, 12]               # 6 is the baseline (reused, not re-run)

fe_records = [(; fe = FE, regret = r.regret, realized = r.realized_welfare,
    max_jump = max_jump(r.trace), mean_jump = mean_jump(r.trace),
    cumdev = last(r.trace.cum_deviation_trace), steps = r.steps)]
for fe in FE_LEVELS
    fe == FE && continue
    s = Scenario(; name = "mpc-demo-fe$(fe)", feeder = :ieee13, T = T, mpc_H = H,
        mpc_step = 1, mpc_terminal_soc = true, mpc_forecast_error = fe)
    rr = run_mpc(s)
    push!(fe_records, (; fe, regret = rr.regret, realized = rr.realized_welfare,
        max_jump = max_jump(rr.trace), mean_jump = mean_jump(rr.trace),
        cumdev = last(rr.trace.cum_deviation_trace), steps = rr.steps))
    @printf("  forecast error ±%.0f%%: regret = %10.5f   max_jump = %7.4f   mean_jump = %7.4f\n",
        100fe, rr.regret, max_jump(rr.trace), mean_jump(rr.trace))
end
sort!(fe_records; by = x -> x.fe)

h_records = [(; H = H, regret = r.regret, max_jump = max_jump(r.trace),
    mean_jump = mean_jump(r.trace), cumdev = last(r.trace.cum_deviation_trace), steps = r.steps)]
for h in H_LEVELS
    h == H && continue
    s = Scenario(; name = "mpc-demo-H$(h)", feeder = :ieee13, T = T, mpc_H = h,
        mpc_step = 1, mpc_terminal_soc = true, mpc_forecast_error = FE)
    rr = run_mpc(s)
    push!(h_records, (; H = h, regret = rr.regret, max_jump = max_jump(rr.trace),
        mean_jump = mean_jump(rr.trace), cumdev = last(rr.trace.cum_deviation_trace),
        steps = rr.steps))
    @printf("  window H = %2d h: published steps = %2d   regret = %10.5f   mean_jump = %7.4f\n",
        h, rr.steps, rr.regret, mean_jump(rr.trace))
end
sort!(h_records; by = x -> x.H)

# ===========================================================================================
# 3. INSIDE THE LOOP — hand-driven pass mirroring run_mpc's loop VERBATIM (same materialize
#    block, same per-resolve Parameter writes, same nominal-plant state propagation), extended
#    ONLY with recording of every resolve's full planned window and every applied hour. This
#    is what makes the "plan spaghetti" figure possible: run_mpc's public return records only
#    the PUBLISHED first interval per resolve, not the planned future.
#    (Mirrors src/experiments/mpc_loop.jl §1-§3 and test/test_mpc_terminal.jl's mini-loop.)
# ===========================================================================================
println("\n[3/4] Hand-driven recording pass (mirrors run_mpc's loop; records full planned windows)...")

fe_plans = NamedTuple[]      # one entry per resolve: the FULL planned window
fe_applied = NamedTuple[]    # one entry per applied (published) hour

let s = s_base
    # --- materialize, verbatim run_mpc §1 ----------------------------------------------------
    feeder = build_feeder(s.feeder)
    profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
    λ₀ = build_price(s.price, s.T, profiles)
    aggs = build_population(s.population, feeder, s.feeder, profiles, sub_seed(s.seed, :population))
    pf = ConvexBranchFlow()
    # Deferrable-excluded window population (run_mpc's own header deviation note: the window
    # model cannot host a Deferrable whose energy-budget window is baked against full T).
    mpc_aggs = [
        Aggregator(agg.bus, agg.φ, filter(d -> !(d isa Deferrable), agg.devices), agg.Pdc) for
        agg in aggs
    ]

    # --- comparable day-ahead benchmark (run_mpc §2b): terminal-SOC targets + overlay paths --
    ctx_cmp, _, _ = solve_welfare(feeder, pf, mpc_aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export)
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:s.T] for
        (bus, varlist) in ctx_cmp.meta[:agg_device_vars] for v in varlist if haskey(v, :soc)
    )
    # Day-ahead reference paths at the PUBLISHED bus (same dual convention as the window's
    # published price: dual of balance_p at the first aggregator's bus — welfare_solve.jl
    # returns exactly this for its own `dadp`).
    bus = mpc_aggs[1].bus
    da_price = Float64[dual.(ctx_cmp.constraints[:balance_p][bus, :])...]
    da_import = Float64[value.(ctx_cmp.meta[:p_import])...]
    da_soc = soc_da[bus]
    vl_da = ctx_cmp.meta[:agg_device_vars][bus]
    da_tin = Float64[value.(only(vv for vv in vl_da if haskey(vv, :Tin0)).Tin)...]

    # The recorded bus's own devices (structural fields for the propagation + panel bands).
    batt = only(d for d in mpc_aggs[1].devices if hasproperty(d, :soc0))
    therm = only(d for d in mpc_aggs[1].devices if hasproperty(d, :Tin0))

    # --- build the window ONCE (run_mpc §3) ---------------------------------------------------
    o = build_mpc_window(feeder, pf, mpc_aggs; H = s.mpc_H, terminal_soc = s.mpc_terminal_soc,
        allow_export = s.allow_export)

    # Measured state ledger, keyed (bus, kind) — initialized from each device's own t=1 IC.
    measured_state = Dict{Tuple{Int,Symbol},Float64}()
    for agg in mpc_aggs, d in agg.devices
        hasproperty(d, :soc0) && (measured_state[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (measured_state[(agg.bus, :Tin)] = Float64(d.Tin0))
    end

    # Recording handles at the published bus (the default population hosts exactly one
    # :soc-kind and one :Tin-kind device per bus — WR-05's asserted invariant).
    vl = o.ctx.meta[:agg_device_vars][bus]
    v_soc = only(vv for vv in vl if haskey(vv, :soc))
    v_tin = only(vv for vv in vl if haskey(vv, :Tin0))

    global fe_plans, fe_applied
    for t in 1:s.mpc_step:(s.T - s.mpc_H + 1)
        fe = draw_forecast_error(s.seed, t, s.mpc_forecast_error)

        # IC + terminal-target Parameters (verbatim run_mpc).
        for entry in o.ic_handles
            set_parameter_value(entry.ic_param, measured_state[(entry.bus, entry.kind)])
            if entry.terminal_param !== nothing
                set_parameter_value(entry.terminal_param, soc_da[entry.bus][min(t + s.mpc_H - 1, s.T)])
            end
        end
        # Per-step device forecast slices (verbatim run_mpc: PV/demand perturbed, ambient not).
        for agg in mpc_aggs
            varlist = o.ctx.meta[:agg_device_vars][agg.bus]
            for (d, v) in zip(agg.devices, varlist)
                if haskey(v, :Ppv_param)
                    set_parameter_value.(v.Ppv_param,
                        Float64[d.Ppv[t + τ - 1] * fe.pv_factor for τ in 1:s.mpc_H])
                end
                if haskey(v, :Tout_param)
                    set_parameter_value.(v.Tout_param,
                        Float64[d.Tout[t + τ - 1] for τ in 1:(s.mpc_H - 1)])
                end
            end
        end
        for handle in o.agg_pdc_handles
            agg = only(a for a in mpc_aggs if a.bus == handle.bus)
            set_parameter_value.(handle.Pdc_param,
                Float64[agg.Pdc[t + τ - 1] * fe.demand_factor for τ in 1:s.mpc_H])
        end
        # Slide λ₀ via set_objective_coefficient — NEVER a Parameter (Pitfall 2).
        for τ in 1:s.mpc_H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end

        solve_mpc_window!(o)

        # RECORD the full planned window (price = the same balance_p duals run_mpc publishes
        # at the first tier of its certificate ladder).
        plan = (;
            t = t,
            pv_factor = fe.pv_factor,
            demand_factor = fe.demand_factor,
            price_plan = Float64[dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])...],
            soc_plan = Float64[value.(v_soc.soc)...],
            tin_plan = Float64[value.(v_tin.Tin)...],
            import_plan = Float64[value.(o.p_import)...],
            terminal = soc_da[bus][min(t + s.mpc_H - 1, s.T)],
        )
        push!(fe_plans, plan)

        # APPLY the first interval and propagate the measured state (verbatim run_mpc).
        n_apply = min(s.mpc_step, s.mpc_H, (s.T - s.mpc_H + 1) - t + 1)
        for τ in 1:n_apply
            abs_hour = t + τ - 1
            for agg in mpc_aggs
                varlist = o.ctx.meta[:agg_device_vars][agg.bus]
                for d in agg.devices
                    if d isa PVBattery || d isa FourQuadBESS
                        v = only(vv for vv in varlist if haskey(vv, :soc0))
                        measured_state[(agg.bus, :soc)] = propagate_soc(
                            measured_state[(agg.bus, :soc)],
                            value(v.p_ch[τ]), value(v.p_dch[τ]), d.η, d.Δt)
                    elseif d isa Thermostatic
                        v = only(vv for vv in varlist if haskey(vv, :Tin0))
                        measured_state[(agg.bus, :Tin)] = propagate_tin(
                            measured_state[(agg.bus, :Tin)],
                            value(v.p[τ]), d.α, d.β, d.Tout[abs_hour])
                    end
                end
            end
            push!(fe_applied, (;
                t = abs_hour,
                price = plan.price_plan[τ],
                soc = measured_state[(bus, :soc)],
                tin = measured_state[(bus, :Tin)],
                p_import = plan.import_plan[τ],
            ))
        end
    end

    # Da→plots globals for the figure section (bus constants + day-ahead reference paths).
    global rec_bus = bus
    global rec_batt = batt
    global rec_therm = therm
    global rec_da_price = da_price
    global rec_da_import = da_import
    global rec_da_soc = da_soc
    global rec_da_tin = da_tin
end
@assert length(fe_plans) == r.steps
@assert length(fe_applied) == r.steps
# The recording pass must reproduce run_mpc's published prices (identical seeded draws +
# identical parameter writes → identical deterministic solves). max |Δ| is a mirroring check.
mirror_gap = maximum(abs.(getfield.(fe_applied, :price) .- r.trace.dadp_trace))
@printf("  recording pass vs run_mpc published-price max |Δ| = %.3e (mirror check)\n", mirror_gap)

# ===========================================================================================
# 4. FIGURES.
# ===========================================================================================
println("\n[4/4] Figures...")

# === (4a) Price diagnostics — the MpcTrace ledger, hour by hour ============================
let
    fig = Figure(; size = (920, 1080))
    fig[0, 1] = Label(fig,
        "MPC example case (IEEE-13, T=$T h, H=$H h, ±$(100FE)% forecast error) — published real-time price vs day-ahead reference";
        fontsize = 15, font = :bold)

    dev = r.trace.dadp_trace .- r.trace.dadp_da_trace

    # (a) the two price paths; published markers colored by certificate provenance.
    ax1 = Axis(fig[1, 1]; xlabel = "hour t", ylabel = "price (¢\$/kWh-consistent)",
        title = "(a) Published RTP vs day-ahead DADP (published bus $rec_bus)", titlealign = :left,
        xticks = 2:2:T)
    vspan!(ax1, r.steps + 0.5, T + 0.5; color = (:gray, 0.12))
    text!(ax1, (r.steps + T) / 2 + 1, maximum(r.day_ahead_dadp);
        text = "never published\n(fixed-window tail)", align = (:center, :top),
        fontsize = 9, color = :dimgrey)
    lines!(ax1, 1:T, r.day_ahead_dadp; color = :dodgerblue, linestyle = :dash, linewidth = 1.8,
        label = "day-ahead DADP (perfect foresight, 24 h)")
    lines!(ax1, pub_hours, r.trace.dadp_trace; color = :grey30, linewidth = 1.0)
    for st in statuses
        idx = findall(==(st), r.trace.cert_status_trace)
        scatter!(ax1, pub_hours[idx], r.trace.dadp_trace[idx];
            color = CERT_COLORS[st], markersize = 8,
            label = "$(length(idx))× $(CERT_LABELS[st])")
    end
    axislegend(ax1; position = :lt, labelsize = 10, framevisible = false)

    # (b) per-hour signed deviation published − day-ahead.
    ax2 = Axis(fig[2, 1]; xlabel = "published hour t", ylabel = "price deviation",
        title = "(b) Signed deviation  λ_RTP − λ_DA  per published hour", titlealign = :left,
        xticks = 2:2:r.steps)
    hlines!(ax2, 0.0; color = :black, linewidth = 0.8)
    pos = findall(>=(0), dev)
    neg = findall(<(0), dev)
    barplot!(ax2, pub_hours[pos], dev[pos]; color = (:teal, 0.75))
    barplot!(ax2, pub_hours[neg], dev[neg]; color = (:indianred, 0.75))

    # (c) step-to-step price jumps with max/mean norms.
    ax3 = Axis(fig[3, 1]; xlabel = "published hour t", ylabel = "price jump |λ_t − λ_{t−1}|",
        title = "(c) Step-to-step price jumps, with max/mean norms (D-10)", titlealign = :left,
        xticks = 2:2:r.steps)
    barplot!(ax3, pub_hours, r.trace.jump_trace; color = (:purple, 0.55))
    hlines!(ax3, max_jump(r.trace); color = :black, linestyle = :dash, linewidth = 1.4,
        label = "max jump = $(round(max_jump(r.trace); digits = 3))")
    hlines!(ax3, mean_jump(r.trace); color = :dimgrey, linestyle = :dot, linewidth = 1.4,
        label = "mean jump = $(round(mean_jump(r.trace); digits = 3))")
    axislegend(ax3; position = :rt, labelsize = 10, framevisible = false)

    # (d) running cumulative deviation from the day-ahead path.
    ax4 = Axis(fig[4, 1]; xlabel = "published hour t", ylabel = "cumulative Σ|λ_RTP − λ_DA|",
        title = "(d) Running cumulative deviation from the day-ahead path", titlealign = :left,
        xticks = 2:2:r.steps)
    band!(ax4, pub_hours, zeros(r.steps), r.trace.cum_deviation_trace; color = (:purple, 0.15))
    lines!(ax4, pub_hours, r.trace.cum_deviation_trace; color = :purple, linewidth = 2.2)
    scatter!(ax4, pub_hours, r.trace.cum_deviation_trace; color = :purple, markersize = 5)
    text!(ax4, pub_hours[end], r.trace.cum_deviation_trace[end];
        text = "  final = $(round(last(r.trace.cum_deviation_trace); digits = 3))",
        align = (:right, :bottom), fontsize = 10, color = :dimgrey)

    saveboth("mpc_price_diagnostics", fig)
    println("  ✓ mpc_price_diagnostics.{pdf,png}")
end

# === (4b) The receding-horizon plan picture — planned windows vs applied trajectory ==========
let
    nres = length(fe_plans)
    cmap = cgrad(:viridis)
    pcol(i) = cmap[(i - 1) / (nres - 1)]   # i = resolve number (1..nres); step=1 ⇒ i == start hour
    applied_t = getfield.(fe_applied, :t)
    applied_price = getfield.(fe_applied, :price)
    applied_soc = getfield.(fe_applied, :soc)
    applied_tin = getfield.(fe_applied, :tin)
    applied_import = getfield.(fe_applied, :p_import)

    fig = Figure(; size = (1180, 860))
    fig[0, 1:2] = Label(fig,
        "Inside the receding horizon — every resolve's planned H=$H h window (faded) vs the applied trajectory (bus $rec_bus)";
        fontsize = 15, font = :bold)

    # (a) planned vs published PRICE ------------------------------------------------------------
    axa = Axis(fig[1, 1]; xlabel = "hour t", ylabel = "price (¢\$/kWh-consistent)",
        title = "(a) Planned price windows vs published RTP", titlealign = :left, xticks = 2:2:T)
    for (i, p) in enumerate(fe_plans)
        lines!(axa, p.t:(p.t + H - 1), p.price_plan; color = (pcol(i), 0.30), linewidth = 1.2)
    end
    lines!(axa, 1:T, rec_da_price; color = :dodgerblue, linestyle = :dash, linewidth = 1.8,
        label = "day-ahead DADP (perfect foresight)")
    lines!(axa, applied_t, applied_price; color = :crimson, linewidth = 2.8,
        label = "published RTP (hour 1 of each plan)")
    scatter!(axa, applied_t, applied_price; color = :crimson, markersize = 7)
    axislegend(axa; position = :lt, labelsize = 10, framevisible = false)

    # (b) planned vs realized battery SOC + terminal targets ------------------------------------
    axb = Axis(fig[1, 2]; xlabel = "hour t", ylabel = "battery SOC (per-unit)",
        title = "(b) Planned SOC windows, realized SOC, hard terminal targets", titlealign = :left,
        xticks = 2:2:T)
    hspan!(axb, rec_batt.Emin, rec_batt.Emax; color = (:gray, 0.15), label = "structural band [Emin, Emax]")
    for (i, p) in enumerate(fe_plans)
        lines!(axb, p.t:(p.t + H - 1), p.soc_plan; color = (pcol(i), 0.30), linewidth = 1.2)
    end
    lines!(axb, 1:T, rec_da_soc; color = :dodgerblue, linestyle = :dash, linewidth = 1.8,
        label = "day-ahead optimal SOC")
    lines!(axb, applied_t, applied_soc; color = :crimson, linewidth = 2.8,
        label = "realized SOC (propagated on applied controls)")
    scatter!(axb, applied_t, applied_soc; color = :crimson, markersize = 6)
    scatter!(axb, [p.t + H - 1 for p in fe_plans], [p.terminal for p in fe_plans];
        color = :black, marker = :diamond, markersize = 9, label = "terminal-SOC target (D-06 pin)")
    axislegend(axb; position = :rt, labelsize = 9, framevisible = false)

    # (c) planned vs realized indoor temperature ------------------------------------------------
    axc = Axis(fig[2, 1]; xlabel = "hour t", ylabel = "indoor temperature (°C)",
        title = "(c) Planned Tin windows vs realized Tin (comfort band)", titlealign = :left,
        xticks = 2:2:T)
    hspan!(axc, rec_therm.Tmin, rec_therm.Tmax; color = (:gray, 0.15), label = "comfort band [Tmin, Tmax]")
    for (i, p) in enumerate(fe_plans)
        lines!(axc, p.t:(p.t + H - 1), p.tin_plan; color = (pcol(i), 0.30), linewidth = 1.2)
    end
    lines!(axc, 1:T, rec_da_tin; color = :dodgerblue, linestyle = :dash, linewidth = 1.8,
        label = "day-ahead optimal Tin")
    lines!(axc, applied_t, applied_tin; color = :crimson, linewidth = 2.8,
        label = "realized Tin (ground-truth ambient)")
    scatter!(axc, applied_t, applied_tin; color = :crimson, markersize = 6)
    axislegend(axc; position = :rb, labelsize = 9, framevisible = false)

    # (d) planned vs realized TSO↔DSO frontier exchange -----------------------------------------
    axd = Axis(fig[2, 2]; xlabel = "hour t", ylabel = "frontier exchange p_import (per-unit)",
        title = "(d) Planned frontier exchange vs applied", titlealign = :left, xticks = 2:2:T)
    hlines!(axd, 0.0; color = :black, linewidth = 0.8)
    for (i, p) in enumerate(fe_plans)
        lines!(axd, p.t:(p.t + H - 1), p.import_plan; color = (pcol(i), 0.30), linewidth = 1.2)
    end
    lines!(axd, 1:T, rec_da_import; color = :dodgerblue, linestyle = :dash, linewidth = 1.8,
        label = "day-ahead optimal exchange")
    lines!(axd, applied_t, applied_import; color = :crimson, linewidth = 2.8,
        label = "applied exchange (hour 1 of each plan)")
    scatter!(axd, applied_t, applied_import; color = :crimson, markersize = 6)
    axislegend(axd; position = :rt, labelsize = 10, framevisible = false)

    Colorbar(fig[1:2, 3]; limits = (1, nres), colormap = :viridis,
        label = "resolve start hour t (one faded line per resolve)")

    saveboth("mpc_receding_plan", fig)
    println("  ✓ mpc_receding_plan.{pdf,png}")
end

# === (4c) Sweeps — regret & price consistency vs forecast error and window length ============
let
    fig = Figure(; size = (1080, 760))
    fig[0, 1:2] = Label(fig,
        "Single-knob sweeps — how forecast error and window length shape the closed loop";
        fontsize = 15, font = :bold)

    fe_x = [x.fe for x in fe_records]
    h_x = [x.H for x in h_records]

    axa = Axis(fig[1, 1]; xlabel = "forecast-error magnitude (± fraction)",
        ylabel = "regret (welfare units)",
        title = "(a) Regret vs forecast error (H = $H h)", titlealign = :left)
    hlines!(axa, 0.0; color = :black, linewidth = 0.8)
    lines!(axa, fe_x, [x.regret for x in fe_records]; color = :dodgerblue, linewidth = 2)
    scatter!(axa, fe_x, [x.regret for x in fe_records]; color = :dodgerblue, markersize = 9)
    scatter!(axa, [FE], [r.regret]; color = :crimson, marker = :star5, markersize = 18,
        label = "baseline example case")
    axislegend(axa; position = :rt, labelsize = 10, framevisible = false)
    axa.xticks = (FE_LEVELS, ["±$(round(Int, 100x))%" for x in FE_LEVELS])

    axb = Axis(fig[1, 2]; xlabel = "window length H (hours)", ylabel = "regret (welfare units)",
        title = "(b) Regret vs window length — each H over its OWN published horizon (steps annotated)",
        titlealign = :left)
    hlines!(axb, 0.0; color = :black, linewidth = 0.8)
    lines!(axb, h_x, [x.regret for x in h_records]; color = :seagreen, linewidth = 2)
    scatter!(axb, h_x, [x.regret for x in h_records]; color = :seagreen, markersize = 9)
    scatter!(axb, [H], [r.regret]; color = :crimson, marker = :star5, markersize = 18)
    for x in h_records
        text!(axb, x.H, x.regret; text = "  steps=$(x.steps)", fontsize = 9, color = :dimgrey,
            align = (:left, :bottom))
    end
    axb.xticks = H_LEVELS

    axc = Axis(fig[2, 1]; xlabel = "forecast-error magnitude (± fraction)",
        ylabel = "price jump (price units)",
        title = "(c) Price consistency vs forecast error", titlealign = :left)
    lines!(axc, fe_x, [x.max_jump for x in fe_records]; color = :purple, linewidth = 2,
        label = "max jump")
    scatter!(axc, fe_x, [x.max_jump for x in fe_records]; color = :purple, markersize = 8)
    lines!(axc, fe_x, [x.mean_jump for x in fe_records]; color = :teal, linewidth = 2,
        label = "mean jump")
    scatter!(axc, fe_x, [x.mean_jump for x in fe_records]; color = :teal, markersize = 8)
    axislegend(axc; position = :lt, labelsize = 10, framevisible = false)
    axc.xticks = (FE_LEVELS, ["±$(round(Int, 100x))%" for x in FE_LEVELS])

    axd = Axis(fig[2, 2]; xlabel = "window length H (hours)", ylabel = "price jump (price units)",
        title = "(d) Price consistency vs window length", titlealign = :left)
    lines!(axd, h_x, [x.max_jump for x in h_records]; color = :purple, linewidth = 2,
        label = "max jump")
    scatter!(axd, h_x, [x.max_jump for x in h_records]; color = :purple, markersize = 8)
    lines!(axd, h_x, [x.mean_jump for x in h_records]; color = :teal, linewidth = 2,
        label = "mean jump")
    scatter!(axd, h_x, [x.mean_jump for x in h_records]; color = :teal, markersize = 8)
    axislegend(axd; position = :lt, labelsize = 10, framevisible = false)
    axd.xticks = H_LEVELS

    saveboth("mpc_sweeps", fig)
    println("  ✓ mpc_sweeps.{pdf,png}")
end

# === (4d) Welfare comparison + price tracking ==================================================
let
    fig = Figure(; size = (1080, 460))
    fig[0, 1:2] = Label(fig,
        "Welfare benchmark (information-set-fair) and published-vs-day-ahead price tracking";
        fontsize = 15, font = :bold)

    # The comparable day-ahead side is derived EXACTLY from run_mpc's returned pair:
    # regret = realized − day-ahead-comparable  ⇒  day-ahead-comparable = realized − regret.
    da_cmp = r.realized_welfare - r.regret

    axa = Axis(fig[1, 1];
        xlabel = "", ylabel = "welfare (per-unit)",
        title = "(a) Closed loop vs perfect foresight, SAME device set & horizon ($(r.steps) h)",
        titlealign = :left)
    barplot!(axa, [1, 2], [da_cmp, r.realized_welfare];
        color = [:dodgerblue, :crimson], width = 0.5)
    axa.xticks = (1:2, ["day-ahead optimum\n(perfect foresight)", "MPC closed loop\n(realized)"])
    text!(axa, 2, r.realized_welfare;
        text = "regret = $(round(r.regret; digits = 5))\n(= realized − day-ahead)",
        align = (:left, :top), fontsize = 10, color = :dimgrey)
    xlims!(axa, 0.5, 3.1)
    axa.xticklabelrotation = π / 8

    axb = Axis(fig[1, 2]; xlabel = "day-ahead DADP λ_DA", ylabel = "published RTP λ_RTP",
        title = "(b) Hour-by-hour price tracking (y = x = perfect tracking)", titlealign = :left)
    lo = minimum(vcat(r.trace.dadp_da_trace, r.trace.dadp_trace))
    hi = maximum(vcat(r.trace.dadp_da_trace, r.trace.dadp_trace))
    pad = 0.05 * (hi - lo)
    ablines!(axb, 0.0, 1.0; color = (:black, 0.6), linestyle = :dash, linewidth = 1.2)
    scatter!(axb, r.trace.dadp_da_trace, r.trace.dadp_trace; color = (:teal, 0.85), markersize = 10)
    xlims!(axb, lo - pad, hi + pad)
    ylims!(axb, lo - pad, hi + pad)
    ρ_corr = cor(r.trace.dadp_da_trace, r.trace.dadp_trace)
    rmse = sqrt(mean((r.trace.dadp_trace .- r.trace.dadp_da_trace) .^ 2))
    text!(axb, lo + pad, hi;
        text = "corr = $(round(ρ_corr; digits = 4))\nRMSE = $(round(rmse; digits = 4))",
        align = (:left, :top), fontsize = 10, color = :dimgrey)

    saveboth("mpc_welfare_regret", fig)
    println("  ✓ mpc_welfare_regret.{pdf,png}")
end

# -------------------------------------------------------------------------------------------
# Summary.
# -------------------------------------------------------------------------------------------
println("\n" ^ 2)
println("="^78)
println("Done. Baseline example case summary")
@printf("  published steps            : %d (always T − H + 1, independent of mpc_step)\n", r.steps)
@printf("  regret (info-set-fair)     : %.5f\n", r.regret)
@printf("  max / mean price jump      : %.4f / %.4f\n", max_jump(r.trace), mean_jump(r.trace))
@printf("  final cumulative deviation : %.5f\n", last(r.trace.cum_deviation_trace))
println("  certificate ladder         : all resolves at tier 1" *
    (length(statuses) == 1 && statuses[1] == :certified_convex_dual ? "" : " (escalations occurred — see trace)"))
println("  figures                    : $OUT")
println("="^78)
