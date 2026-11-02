# # SOCP exactness in the high-PV regime, with and without optimal Q
#
# Phase 43 (DEV-09) re-measures the SOC branch-flow exactness on the certified 3-bus high-PV
# stress substrate (`high_pv_feeder`, copied verbatim, never re-tuned) now that a PV inverter
# can dispatch reactive power. The measurement is produced by
# `scripts/socp_highpv_remeasure.jl` and committed to `results/socp_highpv/highpv_exactness.csv`;
# this page reads that committed artifact and recomputes every derived figure live, so no
# number below is typed by hand.
#
# ## What is measured
#
# - Seeds `20260719..20260723`, PV scales `0.5` (the documented exact regime) and `1.2` (the
#   stress regime).
# - Variants: `active_only` (the certified population), `with_optimal_q` (plus one
#   [`SmartInverterPV`](@ref) per house, with its own panel; this also adds active PV, so it is
#   not a pure-Q ablation) and `q_only_capability` (a zero-panel inverter: pure reactive support).
# - **Verdicts come only from the standard gate**: `solve_welfare` runs `assert_socp_exact!` at
#   `rtol_exact = 1e-4` with the hybrid floor. A refusal is a recorded outcome, never a failure:
#   `refused_socp_exact` is the cone certificate refusing; any other `refused_<kind>` (here
#   `refused_battery`) is a LATER certificate (battery complementarity) refusing a point whose
#   cone gate had already passed (`socp_gate_passed = true`, because the cone gate runs first).
#   No tolerance or tau was raised to obtain any outcome.
#
# ## The Volt-VAR comparator (post hoc, never a constraint)
#
# On the FIXED active dispatch of each solved point, `ac_feasibility_status`
# (`ACPowerFlow(; limits = false)` physics) yields the per-hour maximum bus voltage. The
# IEEE 1547-2018 Category-B Volt-VAR curve (`(0.92,+0.44) (0.98,0) (1.02,0) (1.08,-0.44)` of
# nameplate) is evaluated point-wise at that voltage, summed over the inverters, and compared
# with the `q` the convex optimum dispatched. The physics model excludes the inverter `q`, so
# the voltage is what a droop would SEE, not a closed-loop equilibrium. The curve never enters a
# convex model.

using TSODSO
using Printf

function read_csv(path)
    lines = readlines(path)
    header = String.(split(first(lines), ','))
    idx = Dict(h => i for (i, h) in enumerate(header))
    return [
        (f = split(ln, ','); Dict(h => String(strip(f[idx[h]])) for h in header)) for
        ln in lines[2:end]
    ]
end
num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)

rows = read_csv(joinpath(pkgdir(TSODSO), "results", "socp_highpv", "highpv_exactness.csv"))
println(length(rows), " committed measurement rows")

# ## Verdicts and cone-residual ratios
#
# `max_ratio` is the worst `gap / (atol_b + rtol*|cone|)` over branches and hours (`<= 1` is the
# gate's acceptance). A refused solve returns no context, so for the `refused_*` rows the cone
# gap is HARVESTED by a diagnostic re-solve (`gap_source = diag_resolve_after_refused_*`): for a
# `refused_battery` row only the battery tau is relaxed and the cone gate stays at `1e-4`; for a
# `refused_socp_exact` row the cone tolerance is relaxed. The re-solve never decides the verdict.
# The `refused` column below is the refused fraction (refused/n) and `harvested` counts the rows
# whose ratio comes from such a re-solve, so the maximum is NOT censored to the surviving rows.

@printf(
    "%-20s %-18s %5s %7s %9s %10s %12s\n",
    "fixture",
    "variant",
    "n",
    "exact",
    "refused",
    "harvested",
    "max ratio"
)
for fx in sort(unique(r["fixture"] for r in rows)),
    v in ("active_only", "with_optimal_q", "q_only_capability")

    s = filter(r -> r["fixture"] == fx && r["variant"] == v, rows)
    isempty(s) && continue
    nex = count(r -> r["verdict"] == "exact", s)
    rat = [num(r["max_ratio"]) for r in s if isfinite(num(r["max_ratio"]))]
    nharv = count(r -> startswith(get(r, "gap_source", ""), "diag_resolve"), s)
    @printf(
        "%-20s %-18s %5d %7d %9s %10d %12s\n",
        fx,
        v,
        length(s),
        nex,
        @sprintf("%d/%d", length(s) - nex, length(s)),
        nharv,
        isempty(rat) ? "NA" : @sprintf("%.3g", maximum(rat))
    )
end

# The refusals (if any), with the certificate that issued them:

for r in filter(r -> r["verdict"] != "exact", rows)
    println(
        r["fixture"],
        " ",
        r["variant"],
        " ",
        r["seed"],
        " -> ",
        r["verdict"],
        " (cone gate passed: ",
        r["socp_gate_passed"],
        ")",
    )
end

# ## Physics voltage and the droop comparator

@printf(
    "%-20s %-18s %9s %8s %10s %12s\n",
    "fixture",
    "variant",
    "max Vphys",
    "hrs>1.02",
    "droop~opt",
    "rms dq (pu)"
)
for fx in sort(unique(r["fixture"] for r in rows)),
    v in ("active_only", "with_optimal_q", "q_only_capability")

    s = filter(
        r ->
            r["fixture"] == fx && r["variant"] == v && isfinite(num(r["physics_vmax"])),
        rows,
    )
    isempty(s) && continue
    vmax = maximum(num(r["physics_vmax"]) for r in s)
    hrs = sum(num(r["physics_hours_above_1p02"]) for r in s)
    agree = sum(filter(isfinite, [num(r["q_sign_agree_hours"]) for r in s]); init = 0.0)
    active = sum(filter(isfinite, [num(r["q_active_hours"]) for r in s]); init = 0.0)
    rms = filter(isfinite, [num(r["q_droop_vs_opt_rms"]) for r in s])
    @printf(
        "%-20s %-18s %9.4f %8d %10s %12s\n",
        fx,
        v,
        vmax,
        hrs,
        active > 0 ? @sprintf("%d/%d", agree, active) : "n/a",
        isempty(rms) ? "n/a" : @sprintf("%.3g", sum(rms) / length(rms))
    )
end

# `droop~opt` counts the hours (summed over seeds) in which the optimal-q dispatch is active and
# the droop request has the same sign. Read it as measured: where the count is far below the
# number of active hours, the droop curve (fed the active-only physics voltage) and the convex
# optimum request different reactive trajectories. The optimal-q dispatch is the benchmark; the
# droop is reported as a comparator only, and `rms dq` is the per-point mean of the hourly RMS gap
# (pu). No claim is made beyond these measured columns.
#
# Honesty notes: the `refused_battery` rows are battery-complementarity refusals, not SOCP
# inexactness; the cone gate had already passed at them. Their cone residual is taken from a
# diagnostic re-solve (battery tau relaxed, cone gate kept at `1e-4`), so the stress-regime
# `max ratio` covers every seed, refused or not. Any row where that re-solve itself failed
# would show up in the `harvested` column as missing and in its `detail` field; the `refused`
# column is the explicit refused fraction of each cell. The harvested value is a diagnostic of
# the relaxed-tau point, which can differ slightly from the (non-existent) certified point.
