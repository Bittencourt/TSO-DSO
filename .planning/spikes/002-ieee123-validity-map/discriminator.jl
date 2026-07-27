# Spike 002 — numerical-vs-structural discriminator.
#
# The sweep flagged 23/48 IEEE-123 points as "inexact", but with ratios in [1.1, 4.8] — three
# orders of magnitude below the 3-bus fixture's structural gaps (1e3..1e4), scattered
# non-monotonically across the grid, and with the voltage upper bound NEVER active anywhere.
#
# Competing hypotheses:
#   STRUCTURAL — a genuine relaxation gap, small because the driving mechanism is weak here
#   NUMERICAL  — Clarabel's interior point not converging the cone to within rtol=1e-4 on a
#                122-branch problem, i.e. no relaxation gap at all
#
# Discriminator: re-solve flagged points with progressively TIGHTER solver tolerances. A
# structural gap is a property of the optimum and must PERSIST as tolerance tightens. A numerical
# residual must SHRINK.
#
# Default SOCP tolerances are tol_gap_abs = tol_gap_rel = 1e-8 (src/solver/factory.jl:59-64).
#
# Run:  julia --project=. .planning/spikes/002-ieee123-validity-map/discriminator.jl

using TSODSO
using JuMP
using Clarabel

const T = 24
const TEMP = Float64[
    19,
    18,
    17,
    16,
    16,
    17,
    19,
    21,
    23,
    26,
    28,
    30,
    31,
    32,
    32,
    31,
    29,
    27,
    25,
    23,
    22,
    21,
    20,
    19,
]
const PRICE = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,
]
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
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        0.5 * load_scale,
        0.0,
        2.0 * load_scale,
        1.0 * load_scale,
        BATT_λ...,
        Ppv,
    )
    return Aggregator(bus, 0.90, [therm, defer, batt], Pdc)
end

with_vmax(f, vmax) =
    Feeder([Bus(b.id, b.vmin, vmax, b.is_root) for b in f.buses], f.branches, f.root)

function cone_stats(ctx, feeder; atol = 1e-6, rtol = 1e-4)
    pf = ctx.meta[:pf_vars]
    maxgap = 0.0
    maxratio = 0.0
    vpeak = 0.0
    for t in 1:T
        for (b, br) in enumerate(feeder.branches)
            lhs = value(pf.l[b, t]) * value(pf.v[br.from, t])
            rhs = value(pf.P[b, t])^2 + value(pf.Q[b, t])^2
            g = abs(lhs - rhs)
            maxgap = max(maxgap, g)
            maxratio = max(maxratio, g / (atol + rtol * max(abs(lhs), abs(rhs))))
        end
        for bus in feeder.buses
            bus.is_root && continue
            vpeak = max(vpeak, sqrt(max(value(pf.v[bus.id, t]), 0.0)))
        end
    end
    return (; maxgap, maxratio, vpeak)
end

# Tolerance ladder. Rung 1 == the project default.
const LADDER = [
    ("default  1e-8 ", 1e-8, nothing),
    ("tight    1e-10", 1e-10, 1e-10),
    ("tighter  1e-12", 1e-12, 1e-12),
]

# The three most interesting flagged points.
const POINTS = [
    (label = "worst ratio in sweep", vmax = 1.05, lm = 1.05, pm = 0.7, was = 4.76),
    (label = "LOWEST pv, yet flagged", vmax = 1.10, lm = 0.95, pm = 0.4, was = 4.093),
    (label = "the gate-tripping point", vmax = 1.05, lm = 1.00, pm = 1.0, was = 1.727),
]

base = ieee123_modified()
nodes = ieee123_load_nodes()

println("="^94)
println("NUMERICAL vs STRUCTURAL — does the cone gap persist as solver tolerance tightens?")
println("  structural gap  ⇒ ratio PERSISTS (property of the optimum)")
println("  numerical noise ⇒ ratio SHRINKS  (artifact of convergence)")
println("="^94)

for p in POINTS
    println(
        "\n",
        p.label,
        "  —  vmax=",
        p.vmax,
        " load×",
        p.lm,
        " pv×",
        p.pm,
        "   (sweep reported ratio = ",
        p.was,
        ")",
    )
    feeder = with_vmax(base, p.vmax)
    aggs = [
        house(
            bus;
            pv_scale = BASE_PV * p.pm,
            load_scale = BASE_LOAD * p.lm,
            dev_scale = BASE_DEV,
        ) for bus in nodes
    ]
    for (name, tol, feas) in LADDER
        attrs = Any["verbose" => false, "tol_gap_abs" => tol, "tol_gap_rel" => tol]
        feas === nothing || push!(attrs, "tol_feas" => feas)
        opt = optimizer_with_attributes(Clarabel.Optimizer, attrs...)
        try
            ctx, obj, _ = solve_welfare(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = T,
                λ₀ = PRICE,
                optimizer = opt,
                allow_export = true,
                rtol_exact = 1e6,
            )
            s = cone_stats(ctx, feeder)
            println(
                "    ",
                name,
                " → ratio=",
                rpad(round(s.maxratio; sigdigits = 5), 12),
                " maxgap=",
                rpad(round(s.maxgap; sigdigits = 4), 12),
                " vpeak=",
                rpad(round(s.vpeak; sigdigits = 6), 10),
                " obj=",
                round(obj; digits = 5),
                "   ",
                s.maxratio <= 1.0 ? "EXACT" : "inexact",
            )
        catch err
            println("    ", name, " → FAILED: ", first(sprint(showerror, err), 90))
        end
        flush(stdout)
    end
end
println("\n", "="^94)
