# Spike 002 — the same validity sweep, on REAL IEEE-123 impedances.
#
# Identical method to spike 001 (free cone-gap detector off the SOCP solve, no AC oracle), on a
# completely different substrate: `ieee123_modified()`, whose non-switch branch impedances are
# sourced from the public IEEE-123 OpenDSS test case, positive-sequence Fortescue-reduced
# (src/data/ieee123.jl:23-24). 123 buses / 122 branches / 85 load nodes.
#
# AXES ARE MULTIPLIERS on the Phase-17-RETUNED population point — load 0.05 / pv 0.12 /
# dev 0.05*(0.05/0.03), seed 20260719 — i.e. the exact point the thesis-reproduction literate page
# and Phase 18-01 use. NOT the older 0.03/0.06 constants in src/experiments/materialize.jl.
#
# POSITIVE CONTROL (per .planning/spikes/CONVENTIONS.md): (pv×1.0, load×1.0, vmax=1.10) is the
# thesis-reproduction point, where the PF-04 gate is known to PASS. It must classify EXACT. Spike
# 001 iteration 1 showed an all-exact sweep is indistinguishable from an inert fixture without a
# control, so this is checked and printed on every run.
#
# COST: ~68 s per solve on this feeder (vs <1 s on the 3-bus fixture), so the grid is 54 points
# rather than 150. Grid resolution was traded down deliberately; the reduction is stated in the
# README rather than hidden.
#
# Run:  julia --project=. .planning/spikes/002-ieee123-validity-map/sweep.jl

using TSODSO
using JuMP
using CSV, DataFrames

const T = 24

const TEMP = Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
    31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
const PRICE = Float64[3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0]

# Phase-17-retuned baseline — docs/literate/thesis_reproduction_ieee123.jl:49-52.
const SEED = 20260719
const BASE_LOAD = 0.05
const BASE_PV = 0.12
const BASE_DEV = 0.05 * (0.05 / 0.03)
const BATT_λ = (3.8, 6.2, 8.9)

function house(bus; pv_scale, load_scale, dev_scale)
    prof = generate_profiles(seed = SEED + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, TEMP)
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    # Battery sized off load_scale, as the literate page does.
    batt = PVBattery(bus, 0.95, 1.0, 0.5 * load_scale, 0.0, 2.0 * load_scale,
        1.0 * load_scale, BATT_λ..., Ppv)
    return Aggregator(bus, 0.90, [therm, defer, batt], Pdc)   # φ = 0.90 on IEEE-123
end

function with_vmax(f, vmax)
    return Feeder([Bus(b.id, b.vmin, vmax, b.is_root) for b in f.buses], f.branches, f.root)
end

# Identical detector to spike 001 — the cone residual src/models/exactness.jl:8 computes, free.
function cone_stats(ctx, feeder; atol = 1e-6, rtol = 1e-4)
    pf = ctx.meta[:pf_vars]
    maxgap = 0.0
    maxratio = 0.0
    n_at_vmax = 0
    min_P = Inf
    vpeak = 0.0
    for t in 1:T
        for (b, br) in enumerate(feeder.branches)
            lhs = value(pf.l[b, t]) * value(pf.v[br.from, t])
            rhs = value(pf.P[b, t])^2 + value(pf.Q[b, t])^2
            g = abs(lhs - rhs)
            maxgap = max(maxgap, g)
            maxratio = max(maxratio, g / (atol + rtol * max(abs(lhs), abs(rhs))))
            min_P = min(min_P, value(pf.P[b, t]))
        end
        for bus in feeder.buses
            bus.is_root && continue
            v = value(pf.v[bus.id, t])
            vpeak = max(vpeak, sqrt(max(v, 0.0)))
            v >= bus.vmax^2 - 1e-7 && (n_at_vmax += 1)
        end
    end
    return (; maxgap, maxratio, n_at_vmax, min_P, vpeak)
end

const PV_MULTS = [0.4, 0.7, 1.0, 1.3, 1.7, 2.2]
const LOAD_MULTS = [0.95, 1.00, 1.05]
const VMAXES = [1.05, 1.075, 1.10]

function main()
    base = ieee123_modified()
    nodes = ieee123_load_nodes()
    @info "IEEE-123 (real OpenDSS positive-sequence impedances)" nbus = length(base.buses) nbranch =
        length(base.branches) nload = length(nodes) r_range = extrema(b.r for b in base.branches)

    rows = NamedTuple[]
    total = length(VMAXES) * length(LOAD_MULTS) * length(PV_MULTS)
    i = 0
    t_start = time()
    for vmax in VMAXES, lm in LOAD_MULTS, pm in PV_MULTS
        i += 1
        feeder = with_vmax(base, vmax)
        ls = BASE_LOAD * lm
        aggs = [house(bus; pv_scale = BASE_PV * pm, load_scale = ls, dev_scale = BASE_DEV)
                for bus in nodes]
        t0 = time()
        row = try
            ctx, obj, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs;
                T = T, λ₀ = PRICE, allow_export = true, rtol_exact = 1e6)
            s = cone_stats(ctx, feeder)
            (; vmax, load_mult = lm, pv_mult = pm, status = "SOLVED", objective = obj,
                maxgap = s.maxgap, maxratio = s.maxratio, n_at_vmax = s.n_at_vmax,
                min_branch_P = s.min_P, vpeak = s.vpeak, exact = s.maxratio <= 1.0,
                class = s.maxratio <= 1.0 ? "exact" : "inexact", secs = time() - t0,
                fail_reason = "")
        catch err
            msg = sprint(showerror, err)
            cls = occursin("INFEASIBLE", msg) ? "infeasible" :
                  occursin("complementarity", msg) ? "guard" : "solver"
            (; vmax, load_mult = lm, pv_mult = pm,
                status = "FAILED:" * string(nameof(typeof(err))), objective = NaN,
                maxgap = NaN, maxratio = NaN, n_at_vmax = -1, min_branch_P = NaN,
                vpeak = NaN, exact = missing, class = cls, secs = time() - t0,
                fail_reason = replace(first(msg, 200), '\n' => " | "))
        end
        push!(rows, row)
        fmt(x) = x isa Float64 && isfinite(x) ? string(round(x; sigdigits = 4)) : "—"
        println(rpad("[$i/$total]", 9), " vmax=", rpad(vmax, 6), " load×", rpad(lm, 5),
            " pv×", rpad(pm, 4), " → ", rpad(row.class, 11),
            " ratio=", rpad(fmt(row.maxratio), 11), " atVmax=", rpad(row.n_at_vmax, 5),
            " vpeak=", rpad(fmt(row.vpeak), 7), " minP=", rpad(fmt(row.min_branch_P), 10),
            " (", round(row.secs; digits = 1), "s)")
        flush(stdout)
        # Checkpoint after every point — a 1-hour sweep must not lose everything to one crash.
        CSV.write(joinpath(@__DIR__, "sweep.csv"), DataFrame(rows))
    end

    df = DataFrame(rows)
    CSV.write(joinpath(@__DIR__, "sweep.csv"), df)

    anchor = only(filter(r -> r.pv_mult == 1.0 && r.load_mult == 1.0 && r.vmax == 1.10,
        eachrow(df)))
    println("\n", "="^88)
    for g in groupby(df, :class)
        println(rpad(g.class[1], 12), nrow(g))
    end
    println("-"^88)
    println("POSITIVE CONTROL — thesis-reproduction point (pv×1.0, load×1.0, vmax=1.10):")
    println("  expect EXACT   got ", anchor.exact === true ? "EXACT ✓" :
                                     "$(anchor.exact) ✗  [$(anchor.status)]",
        "   ratio=", anchor.maxratio isa Float64 && isfinite(anchor.maxratio) ?
                     round(anchor.maxratio; sigdigits = 4) : "—",
        "  vpeak=", anchor.vpeak isa Float64 && isfinite(anchor.vpeak) ?
                    round(anchor.vpeak; sigdigits = 5) : "—")
    println("-"^88)
    println("total wall time: ", round((time() - t_start) / 60; digits = 1), " min")
    println("="^88)
    return df
end

main()
