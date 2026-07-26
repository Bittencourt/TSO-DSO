# Spike 001 — relaxation validity map: the sweep.
#
# For each point of a (pv_scale × load_scale × vmax) grid, computes the SOC cone relaxation gap
# that src/models/exactness.jl:8 already measures — FREE off the SOCP solve. No AC/Ipopt oracle.
#
# SUBSTRATE: Phase4Fixtures.high_pv_feeder() — a purpose-built 3-bus fixture with low-impedance
# (r=x=0.05) branches and a tight 0.95/1.05 band, replicated here because the original lives in
# a TestItems @testmodule. This is the substrate on which EXACT-04 was found; sweeping
# ieee13_modified() instead was tried first and is INERT (see README § Investigation Trail).
#
# POSITIVE/NEGATIVE CONTROLS (non-negotiable): the grid contains the two known EXACT-04 points —
#   (pv=0.5, load=0.2, vmax=1.05) must classify EXACT
#   (pv=1.2, load=0.2, vmax=1.05) must classify INEXACT
# A map that cannot reproduce both is not trustworthy, regardless of how good it looks.
#
# The internal PF-04 gate (assert_socp_exact!) is neutralized via `rtol_exact` so an inexact
# solve is RETURNED for classification instead of refused — mirroring the existing diagnostic
# override at test/test_ac_oracle.jl:181-187. Changes ZERO src/ code.
#
# Run:  julia --project=. .planning/spikes/001-relaxation-validity-map/sweep.jl

using TSODSO
using JuMP
using CSV, DataFrames

const T = 24

# Both profiles verified identical to Phase4Fixtures.temperature_profile() / mem_price_profile().
const TEMP = Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
    31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
const PRICE = Float64[3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0]

const SEED = 20260406            # Phase4Fixtures default — reproducible (threat T-04-06)
const BATT_λ = (3.8, 6.2, 8.9)

# ── Fixture (replicated from test/fixtures_phase4.jl:118 and :184) ────────────────────────
function high_pv_feeder(; vmax = 1.05)
    buses = [Bus(1, 0.95, vmax, true), Bus(2, 0.95, vmax, false), Bus(3, 0.95, vmax, false)]
    branches = [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)]
    return Feeder(buses, branches, 1)
end

function house(bus; pv_scale, load_scale, batt_pmax = 0.1, batt_emax = 0.2, batt_soc0 = 0.1)
    prof = generate_profiles(seed = SEED + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, TEMP)
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0, BATT_λ..., Ppv)
    return Aggregator(bus, 0.95, [therm, defer, batt], Pdc)   # φ = 0.95, per build_high_pv_aggregators
end

# ── The FREE detector + free interpretive diagnostics ─────────────────────────────────────
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
            # SCALE-FREE bound — the house WR-01 idiom, never a bare absolute threshold.
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

# ── Grid — spans BOTH EXACT-04 control points ─────────────────────────────────────────────
const PV_SCALES = [0.3, 0.5, 0.7, 0.9, 1.0, 1.1, 1.2, 1.4, 1.6, 2.0]
const LOAD_SCALES = [0.10, 0.15, 0.20, 0.30, 0.40]
const VMAXES = [1.05, 1.075, 1.10]

function main()
    rows = NamedTuple[]
    total = length(VMAXES) * length(LOAD_SCALES) * length(PV_SCALES)
    i = 0
    for vmax in VMAXES, ls in LOAD_SCALES, ps in PV_SCALES
        i += 1
        feeder = high_pv_feeder(; vmax = vmax)
        aggs = [house(bus; pv_scale = ps, load_scale = ls) for bus in 2:length(feeder.buses)]
        row = try
            ctx, obj, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs;
                T = T, λ₀ = PRICE, allow_export = true, rtol_exact = 1e6)
            s = cone_stats(ctx, feeder)
            (; vmax, load_scale = ls, pv_scale = ps, status = "SOLVED", objective = obj,
                maxgap = s.maxgap, maxratio = s.maxratio, n_at_vmax = s.n_at_vmax,
                min_branch_P = s.min_P, vpeak = s.vpeak, exact = s.maxratio <= 1.0,
                class = s.maxratio <= 1.0 ? "exact" : "inexact", fail_reason = "")
        catch err
            # Non-solved points are NEVER silently dropped or merged into one colour. They split
            # into physically distinct classes: INFEASIBLE is legitimate white space (the feeder
            # cannot serve this operating point inside the voltage band); a guard trip is a
            # genuinely UNMEASURED point and must read as such on the map.
            msg = sprint(showerror, err)
            cls = occursin("INFEASIBLE", msg) ? "infeasible" :
                  occursin("complementarity", msg) ? "guard" : "solver"
            (; vmax, load_scale = ls, pv_scale = ps,
                status = "FAILED:" * string(nameof(typeof(err))), objective = NaN,
                maxgap = NaN, maxratio = NaN, n_at_vmax = -1, min_branch_P = NaN,
                vpeak = NaN, exact = missing, class = cls,
                fail_reason = replace(first(msg, 160), '\n' => " | "))
        end
        push!(rows, row)
        fmt(x) = x isa Float64 && isfinite(x) ? string(round(x; sigdigits = 4)) : "—"
        println(rpad("[$i/$total]", 10), " vmax=", rpad(vmax, 6), " load=", rpad(ls, 5),
            " pv=", rpad(ps, 4), " → ", rpad(row.status, 22),
            " ratio=", rpad(fmt(row.maxratio), 11), " atVmax=", rpad(row.n_at_vmax, 4),
            " vpeak=", rpad(fmt(row.vpeak), 7), " minP=", fmt(row.min_branch_P))
    end

    df = DataFrame(rows)
    out = joinpath(@__DIR__, "sweep.csv")
    CSV.write(out, df)

    # ── Controls ─────────────────────────────────────────────────────────────────────────
    ctl(ps, ls, vm) = only(filter(r -> r.pv_scale == ps && r.load_scale == ls && r.vmax == vm,
        eachrow(df)))
    c_exact = ctl(0.5, 0.20, 1.05)
    c_inexact = ctl(1.2, 0.20, 1.05)

    nsolved = count(==("SOLVED"), df.status)
    nexact = count(x -> x === true, df.exact)
    ninexact = count(x -> x === false, df.exact)

    println("\n", "="^78)
    println("solved:   $nsolved / $total     exact: $nexact   inexact: $ninexact   failed: $(total - nsolved)")
    println("-"^78)
    println("CONTROLS (must reproduce EXACT-04 or the map is void):")
    println("  pv=0.5 load=0.2 vmax=1.05  expect EXACT    got ",
        c_exact.exact === true ? "EXACT ✓" : "$(c_exact.exact) ✗   [$(c_exact.status)]",
        "   ratio=", round(c_exact.maxratio; sigdigits = 4), " vpeak=",
        round(c_exact.vpeak; sigdigits = 5))
    println("  pv=1.2 load=0.2 vmax=1.05  expect INEXACT  got ",
        c_inexact.exact === false ? "INEXACT ✓" : "$(c_inexact.exact) ✗   [$(c_inexact.status)]",
        " ratio=", round(c_inexact.maxratio; sigdigits = 4), " vpeak=",
        round(c_inexact.vpeak; sigdigits = 5))
    println("-"^78)
    println("csv:      $out")
    println("="^78)
    return df
end

main()
