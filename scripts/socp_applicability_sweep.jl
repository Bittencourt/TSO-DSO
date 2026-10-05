# scripts/socp_applicability_sweep.jl
#
# SOC-relaxation APPLICABILITY sweep — where is the SOC branch-flow relaxation exact?
#
# Re-runnable measurement script (mirrors scripts/repro_stability_check.jl's DrWatson scaffold:
# `projectdir` output, committed findings artifact, per-point try/catch, asserted-and-printed
# controls). Sweeps a (pv × load × vmax) grid on either substrate and classifies every point by the
# cone-gap residual that `src/models/exactness.jl` ALREADY computes — free off the SOCP solve, with
# NO AC/Ipopt oracle involved.
#
#   julia --project=. scripts/socp_applicability_sweep.jl            # both substrates
#   julia --project=. scripts/socp_applicability_sweep.jl highpv     # 3-bus stress fixture (~70 s)
#   julia --project=. scripts/socp_applicability_sweep.jl ieee123    # real impedances (~16 min)
#
# ── READ THIS BEFORE TRUSTING A VERDICT ──────────────────────────────────────────────────────
# The classifier bound is `atol + rtol·max(|l·v|, |P²+Q²|)` with atol = 1e-6. On a large feeder
# that atol sits AT Clarabel's achievable cone residual at the default `tol_gap = 1e-8`, so points
# flag "inexact" from solver noise rather than a relaxation gap. On IEEE-123 that is ~48% of points.
# A ratio near 1 is NOT evidence: structural inexactness on the 3-bus stress fixture produces
# ratios of 1e3-1e4. Discriminate with `--tol-ladder`: a structural property PERSISTS as tolerance
# tightens, numerical noise SHRINKS.
#
#   julia --project=. scripts/socp_applicability_sweep.jl ieee123 --tol-ladder
#
# Provenance of the committed CSVs in results/socp_applicability/ and the full findings: see
# docs/literate/socp_applicability.jl.

using DrWatson
@quickactivate "TSODSO"

using TSODSO
using TSODSO: SOCP, ieee123_load_nodes
using JuMP
using CSV, DataFrames
using Printf

const T = 24

# Both profiles are bit-for-bit identical to test/fixtures_ieee13.jl / fixtures_ieee123.jl.
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
const BATT_λ = (3.8, 6.2, 8.9)

const OUT = projectdir("results", "socp_applicability")
mkpath(OUT)

# ── The FREE detector, plus the free interpretive diagnostics ──────────────────────────────────
"""
    cone_stats(ctx, feeder; atol=1e-6, rtol=1e-4)

The same per-branch cone residual `|l·v − (P²+Q²)|` that `src/models/exactness.jl` computes, with
the scale-free combined bound, plus the binding-set / reverse-flow diagnostics that make a map
INTERPRETABLE (also free). `maxratio ≤ 1` is the exactness classification.
"""
function cone_stats(ctx, feeder; atol = 1e-6, rtol = 1e-4)
    pf = ctx.pf_vars
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

with_vmax(f, vmax) =
    Feeder([Bus(b.id, b.vmin, vmax, b.is_root) for b in f.buses], f.branches, f.root)

# ── Substrate A: the 3-bus high-PV stress fixture (test/fixtures_ieee13.jl:184) ────────────────
# Low-impedance r=x=0.05 branches + a tight band: back-feed swings voltage fast, so the
# overvoltage/reverse-flow mechanism that breaks SOC exactness can actually fire here.
highpv_feeder(; vmax = 1.05) = Feeder(
    [Bus(1, 0.95, vmax, true), Bus(2, 0.95, vmax, false), Bus(3, 0.95, vmax, false)],
    [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)],
    1,
)

function highpv_house(bus; pv_scale, load_scale)
    prof = generate_profiles(seed = 20260406 + bus, T = T)
    return Aggregator(
        bus,
        0.95,
        [
            Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, TEMP),
            Deferrable(bus, 8, 16, 1.0, 0.5, 0.5),
            PVBattery(
                bus,
                0.95,
                1.0,
                0.1,
                0.0,
                0.2,
                0.1,
                BATT_λ...,
                Float64[pv_scale * p for p in prof.pv],
            ),
        ],
        Float64[load_scale * d for d in prof.demand],
    )
end

# ── Substrate B: real IEEE-123 impedances, retuned population ─────────────────────────
const IEEE123_BASE = (load = 0.05, pv = 0.12, dev = 0.05 * (0.05 / 0.03), seed = 20260719)

function ieee123_house(bus; pv_scale, load_scale, dev_scale)
    prof = generate_profiles(seed = IEEE123_BASE.seed + bus, T = T)
    return Aggregator(
        bus,
        0.90,
        [
            Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, TEMP),
            Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5),
            PVBattery(
                bus,
                0.95,
                1.0,
                0.5 * load_scale,
                0.0,
                2.0 * load_scale,
                1.0 * load_scale,
                BATT_λ...,
                Float64[pv_scale * p for p in prof.pv],
            ),
        ],
        Float64[load_scale * d for d in prof.demand],
    )
end

# ── The sweep ─────────────────────────────────────────────────────────────────────────────────
"""
    sweep(substrate; optimizer=nothing) -> DataFrame

Classify every grid point UNDER BOTH `ConvexBranchFlow()` (the corrected Gan-Low default,
`thesis_literal=false`) AND `ConvexBranchFlow(; thesis_literal=true)` (the OLD literal copy) — a
`formulation` column (`:default`/`:thesis_literal`) records which. Restated after the model corrections:
since the DEFAULT was flipped to the Gan-Low direction (`v̂ ≥ v`), the DEFAULT's own
exactness boundary shrinks dramatically on this grid (MEASURED highpv substrate: 98/150 exact vs
`thesis_literal=true`'s 104/150 — comparable order of magnitude), but it does **not vanish**:
MEASURED 3/150 default points are genuinely cone-INEXACT (ratio 8196–9746, e.g.
`vmax=1.05, load=0.1, pv=1.2`) — Gan-Low's construction is DESIGNED to force cone-tightness, but
this sweep finds it is not an unconditional guarantee at every operating point. The default's
inexact points are far RARER and sit at different (grid-specific) combinations than
`thesis_literal=true`'s (5/150, ratio 9727–9872) — see
`docs/literate/socp_applicability.jl`'s own "Restated in v4.0" section for the full gate-qualified
derivation. Reporting BOTH side by side is strictly more informative than either alone, since it
shows exactly how the fix changed the applicability map's shape — narrowing the exactness-failure
region, not eliminating it.

A non-solved point is NEVER dropped and never merged into one bucket: `infeasible` (the feeder
cannot serve it inside the voltage band — legitimate white space) and `guard` (a model guard
tripped — genuinely UNMEASURED) are physically different outcomes.
"""
function sweep(substrate::Symbol; optimizer = nothing)
    if substrate === :highpv
        pvs, lds, vms = [0.3, 0.5, 0.7, 0.9, 1.0, 1.1, 1.2, 1.4, 1.6, 2.0],
        [0.10, 0.15, 0.20, 0.30, 0.40],
        [1.05, 1.075, 1.10]
        base = nothing
        mk =
            (vmax, ps, ls) -> (
                highpv_feeder(; vmax),
                [highpv_house(b; pv_scale = ps, load_scale = ls) for b in 2:3],
            )
    else
        pvs, lds, vms =
            [0.4, 0.7, 1.0, 1.3, 1.7, 2.2], [0.95, 1.00, 1.05], [1.05, 1.075, 1.10]
        base = ieee123_modified()
        nodes = ieee123_load_nodes()
        mk =
            (vmax, pm, lm) -> (
                with_vmax(base, vmax),
                [
                    ieee123_house(
                        b;
                        pv_scale = IEEE123_BASE.pv * pm,
                        load_scale = IEEE123_BASE.load * lm,
                        dev_scale = IEEE123_BASE.dev,
                    ) for b in nodes
                ],
            )
    end

    rows = NamedTuple[]
    total = 2 * length(vms) * length(lds) * length(pvs)
    i = 0
    for thesis_literal in (false, true)
        # DUAL-MODE: the two bare-`ConvexBranchFlow()` call sites
        # are HERE and in `tol_ladder` below. `rtol_exact` neutralized so an inexact solve is
        # RETURNED for classification instead of refused (the diagnostic override pattern of
        # test/test_ac_oracle.jl:181-187). This changes no src/ code and does not weaken the
        # shipped exactness gate for any other caller.
        socp_formulation =
            thesis_literal ? ConvexBranchFlow(; thesis_literal = true) : ConvexBranchFlow()
        formulation_label = thesis_literal ? :thesis_literal : :default
        for vmax in vms, ls in lds, ps in pvs
            i += 1
            feeder, aggs = mk(vmax, ps, ls)
            opt = optimizer === nothing ? select_optimizer(SOCP()) : optimizer
            row = try
                ctx, obj, _ = solve_welfare(
                    feeder,
                    socp_formulation,
                    aggs;
                    T = T,
                    λ₀ = PRICE,
                    optimizer = opt,
                    allow_export = true,
                    rtol_exact = 1e6,
                )
                s = cone_stats(ctx, feeder)
                (;
                    substrate,
                    formulation = formulation_label,
                    vmax,
                    load = ls,
                    pv = ps,
                    status = "SOLVED",
                    objective = obj,
                    maxgap = s.maxgap,
                    maxratio = s.maxratio,
                    n_at_vmax = s.n_at_vmax,
                    min_branch_P = s.min_P,
                    vpeak = s.vpeak,
                    class = s.maxratio <= 1.0 ? "exact" : "inexact",
                    fail_reason = "",
                )
            catch err
                msg = sprint(showerror, err)
                (;
                    substrate,
                    formulation = formulation_label,
                    vmax,
                    load = ls,
                    pv = ps,
                    status = "FAILED:" * string(nameof(typeof(err))),
                    objective = NaN,
                    maxgap = NaN,
                    maxratio = NaN,
                    n_at_vmax = -1,
                    min_branch_P = NaN,
                    vpeak = NaN,
                    class = occursin("INFEASIBLE", msg) ? "infeasible" :
                            occursin("complementarity", msg) ? "guard" : "solver",
                    fail_reason = replace(first(msg, 200), '\n' => " | "),
                )
            end
            push!(rows, row)
            @printf(
                "[%3d/%3d] %-8s %-14s vmax=%-6s load=%-5s pv=%-4s -> %-11s ratio=%-11s atVmax=%-4s vpeak=%s\n",
                i,
                total,
                substrate,
                formulation_label,
                vmax,
                ls,
                ps,
                row.class,
                isfinite(row.maxratio) ? string(round(row.maxratio; sigdigits = 4)) : "—",
                row.n_at_vmax,
                isfinite(row.vpeak) ? string(round(row.vpeak; sigdigits = 5)) : "—"
            )
            flush(stdout)
        end
    end
    return DataFrame(rows)
end

"""
    tol_ladder(substrate, points) -> nothing

NUMERICAL-vs-STRUCTURAL discriminator. Re-solves the given `(vmax, load, pv, thesis_literal)`
points at progressively tighter solver tolerances, under whichever formulation each point
specifies (dual-mode — the SECOND bare-`ConvexBranchFlow()` call site,
mirroring `sweep`'s formulation selection). A structural relaxation gap is a property of
the OPTIMUM and must PERSIST; a convergence residual SHRINKS. Print the objective alongside to
confirm the optimum did not move.
"""
function tol_ladder(substrate::Symbol, points)
    println("\n", "="^96)
    println("TOLERANCE LADDER — structural gap PERSISTS, numerical noise SHRINKS")
    println("="^96)
    base = select_optimizer(SOCP())
    for (vmax, ls, ps, thesis_literal) in points
        formulation_label = thesis_literal ? :thesis_literal : :default
        socp_formulation =
            thesis_literal ? ConvexBranchFlow(; thesis_literal = true) : ConvexBranchFlow()
        @printf(
            "\n%s  %s  vmax=%s load=%s pv=%s\n",
            substrate,
            formulation_label,
            vmax,
            ls,
            ps
        )
        for tol in (nothing, 1e-10)
            opt =
                tol === nothing ? base :
                optimizer_with_attributes(
                    base.optimizer_constructor,
                    base.params...,
                    "tol_gap_abs" => tol,
                    "tol_gap_rel" => tol,
                )
            df = try
                feeder, aggs =
                    substrate === :highpv ?
                    (
                        highpv_feeder(; vmax),
                        [highpv_house(b; pv_scale = ps, load_scale = ls) for b in 2:3],
                    ) :
                    (
                        with_vmax(ieee123_modified(), vmax),
                        [
                            ieee123_house(
                                b;
                                pv_scale = IEEE123_BASE.pv * ps,
                                load_scale = IEEE123_BASE.load * ls,
                                dev_scale = IEEE123_BASE.dev,
                            ) for b in ieee123_load_nodes()
                        ],
                    )
                ctx, obj, _ = solve_welfare(
                    feeder,
                    socp_formulation,
                    aggs;
                    T = T,
                    λ₀ = PRICE,
                    optimizer = opt,
                    allow_export = true,
                    rtol_exact = 1e6,
                )
                s = cone_stats(ctx, feeder)
                @printf(
                    "  tol_gap=%-7s ratio=%-12s maxgap=%-11s obj=%.6f  %s\n",
                    tol === nothing ? "1e-8*" : string(tol),
                    round(s.maxratio; sigdigits = 5),
                    round(s.maxgap; sigdigits = 4),
                    obj,
                    s.maxratio <= 1 ? "EXACT" : "inexact"
                )
            catch e
                @printf(
                    "  tol_gap=%-7s FAILED: %s\n",
                    tol === nothing ? "1e-8*" : string(tol),
                    first(sprint(showerror, e), 80)
                )
            end
        end
    end
    println("\n(* 1e-8 is the project default from src/solver/factory.jl)")
    return nothing
end

function report(df::DataFrame, label::AbstractString, path::AbstractString)
    open(path, "w") do io
        println(io, "SOC-relaxation applicability sweep — ", label)
        println(
            io,
            "Detector: cone residual |l·v − (P²+Q²)| vs atol=1e-6 + rtol=1e-4·magnitude",
        )
        println(
            io,
            "NO AC/Ipopt oracle involved (this is a gate-1/cone-residual map only — see",
        )
        println(
            io,
            "docs/literate/ac_oracle.jl for the SEPARATE gate-2/AC-dispatch comparison).",
        )
        println(
            io,
            "rtol_exact neutralized so inexact solves are returned for classification",
        )
        println(io, "rather than refused by the exactness gate.\n")
        println(io, "DUAL-MODE: every grid point solved under BOTH")
        println(io, "ConvexBranchFlow() (default, Gan-Low direction) AND")
        println(io, "ConvexBranchFlow(; thesis_literal=true) (OLD literal copy) — see the")
        println(io, "`formulation` column and the per-formulation breakdown below.\n")
        for g in groupby(df, [:formulation, :class])
            @printf(io, "  %-16s %-12s %d\n", g.formulation[1], g.class[1], nrow(g))
        end
        for (formulation_label, s_all) in (
            ("default", filter(r -> r.formulation == :default, df)),
            ("thesis_literal", filter(r -> r.formulation == :thesis_literal, df)),
        )
            s = filter(r -> r.status == "SOLVED", s_all)
            isempty(s) && continue
            @printf(io, "\n--- formulation = %s ---\n", formulation_label)
            @printf(
                io,
                "ratio range (solved): %.4g .. %.4g\n",
                minimum(s.maxratio),
                maximum(s.maxratio)
            )
            @printf(
                io,
                "vpeak range:          %.5f .. %.5f\n",
                minimum(s.vpeak),
                maximum(s.vpeak)
            )
            println(io, "voltage upper bound EVER active: ", any(s.n_at_vmax .>= 1))
            println(io, "reverse flow at every solved point: ", all(s.min_branch_P .< 0))
            ex = filter(r -> r.class == "exact", s)
            inx = filter(r -> r.class == "inexact", s)
            if !isempty(ex) && !isempty(inx)
                @printf(
                    io,
                    "max ratio among EXACT:   %.4g\nmin ratio among INEXACT: %.4g\n",
                    maximum(ex.maxratio),
                    minimum(inx.maxratio)
                )
                println(io, "(a wide empty band between these two means the boundary is")
                println(
                    io,
                    " insensitive to where the threshold is placed; a narrow one means",
                )
                println(
                    io,
                    " the classification is threshold-dependent — see the tolerance ladder)",
                )
            end
        end
        println(
            io,
            "\nCAVEAT: atol=1e-6 sits at Clarabel's achievable cone residual on a large",
        )
        println(
            io,
            "feeder at the default tol_gap=1e-8. A ratio near 1 is NOT evidence — verify",
        )
        println(io, "with --tol-ladder before reporting any point as genuinely inexact.")
    end
    println("\nwrote ", path)
    return nothing
end

function main(args)
    which = isempty(args) || startswith(first(args), "--") ? "both" : first(args)
    ladder = "--tol-ladder" in args

    if which in ("both", "highpv")
        println("\n", "="^96, "\nSubstrate A — 3-bus high-PV stress fixture\n", "="^96)
        df = sweep(:highpv)
        CSV.write(joinpath(OUT, "highpv_3bus_sweep.csv"), df)
        report(
            df,
            "3-bus high-PV stress fixture (r=x=0.05, vmin=0.95)",
            joinpath(OUT, "highpv_3bus_findings.txt"),
        )
        # Controls, RESTATED after the model corrections (dual-mode, gate-1/cone-residual only):
        # previously this block asserted pv=1.2 -> "expect inexact" under the (then bare-default)
        # ConvexBranchFlow(). Since the default was flipped to the Gan-Low direction, THIS
        # SPECIFIC point (pv=1.2, load=0.20, vmax=1.05 — the high-PV exactness fixture's own calibration) is now
        # measured EXACT under BOTH formulations (`test_restricted_branch_flow.jl:
        # 314-320` — cited not re-derived; confirmed by this sweep itself below). This does NOT mean
        # the default is unconditionally cone-exact everywhere on the broader grid below — MEASURED
        # here: 3/150 default points ARE genuinely cone-inexact (ratio 8196–9746, at DIFFERENT,
        # lower-load combinations than this control point), so the default has its own (far rarer)
        # exactness boundary, not a blanket theoretical guarantee. The genuine negative control used
        # here (a KNOWN, still-reproducing cone-inexact point at THIS control's own load/vmax) is a
        # property of `thesis_literal=true` specifically, at a HIGHER pv_scale — measured
        # at pv=1.4 (ratio in the thousands; the default hits an unrelated App. C
        # battery-complementarity guard at this same pv_scale/load/vmax, so it is not a comparable
        # point for the default AT THIS load level). A sweep that cannot reproduce a KNOWN-inexact
        # point cannot be trusted when it reports "all exact" — that outcome is indistinguishable
        # from a fixture in which the mechanism cannot fire.
        ctl(ps, ls, vm, formulation_sym) = only(
            filter(
                r ->
                    r.pv == ps &&
                    r.load == ls &&
                    r.vmax == vm &&
                    r.formulation == formulation_sym,
                eachrow(df),
            ),
        )
        e_default = ctl(0.5, 0.20, 1.05, :default)
        e_thesis = ctl(0.5, 0.20, 1.05, :thesis_literal)
        x04_default = ctl(1.2, 0.20, 1.05, :default)
        x04_thesis = ctl(1.2, 0.20, 1.05, :thesis_literal)
        x_thesis = ctl(1.4, 0.20, 1.05, :thesis_literal)
        @printf(
            "\nCONTROLS  pv=0.5 default -> %s (expect exact)   pv=0.5 thesis_literal -> %s (expect exact)\n",
            e_default.class,
            e_thesis.class
        )
        @printf(
            "          pv=1.2 default -> %s (expect exact)   pv=1.2 thesis_literal -> %s (expect exact)\n",
            x04_default.class,
            x04_thesis.class
        )
        @printf(
            "          pv=1.4 thesis_literal -> %s (expect inexact — the genuine, still-reproducing negative control)\n",
            x_thesis.class
        )
        e_default.class == "exact" ||
            @warn "positive control (default) drifted" e_default.class e_default.maxratio
        e_thesis.class == "exact" ||
            @warn "positive control (thesis_literal) drifted" e_thesis.class e_thesis.maxratio
        x04_default.class == "exact" ||
            @warn "high-PV default control drifted from its measured exact verdict" x04_default.class x04_default.maxratio
        x04_thesis.class == "exact" ||
            @warn "high-PV thesis_literal control drifted from its measured exact verdict" x04_thesis.class x04_thesis.maxratio
        x_thesis.class == "inexact" ||
            @warn "negative control (thesis_literal, pv=1.4) drifted" x_thesis.class x_thesis.maxratio
        # Dual-mode ladder points: pv=1.2 under the DEFAULT — gate 1 EXACT,
        # ratio should PERSIST tiny as tol tightens. pv=1.4 under thesis_literal=true
        # — the genuinely cone-inexact point THIS sweep measures (ratio in the thousands; the
        # default hits an unrelated App. C battery-complementarity guard at this pv_scale on this
        # exact load/vmax combination, so it is not a comparable ladder point here).
        ladder && tol_ladder(:highpv, [(1.05, 0.20, 1.2, false), (1.05, 0.20, 1.4, true)])
    end

    if which in ("both", "ieee123")
        println(
            "\n",
            "="^96,
            "\nSubstrate B — REAL IEEE-123 impedances (~16 min)\n",
            "="^96,
        )
        df = sweep(:ieee123)
        CSV.write(joinpath(OUT, "ieee123_sweep.csv"), df)
        report(
            df,
            "real IEEE-123 OpenDSS positive-sequence impedances, retuned population",
            joinpath(OUT, "ieee123_findings.txt"),
        )
        # Dual-mode ladder points: both kept on the DEFAULT (unchanged from
        # the earlier behavior) — no thesis_literal=true genuinely-inexact IEEE-123 point has
        # been independently measured; the sweep's own dual-mode grid above (both
        # formulations, every grid point) is the authoritative IEEE-123 map either way.
        ladder && tol_ladder(:ieee123, [(1.05, 1.05, 0.7, false), (1.10, 0.95, 0.4, false)])
    end
    return nothing
end

main(ARGS)
