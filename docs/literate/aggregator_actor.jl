# # The aggregator as an actor: retail wedge and behavioural scenarios
#
# Phase 44 (ACTOR-01..04) lets a group of site aggregators carry its own objective, lets several
# actors sit at one bus, and lets a population respond only partially (or not at all) to the
# price signal. The measurement is produced by `scripts/actor_behaviour_sweep.jl` and committed
# to `results/actor_behaviour/actor_behaviour_sweep.csv`. This page reads that committed artifact
# and recomputes every derived figure live, so no result number below is typed by hand.
#
# ## 1. The actor objective and the wedge
#
# A `Portfolio` groups single-bus site aggregators under one objective. With
# `WelfareObjective` a site maximises its utility minus its payment at the distribution
# price (the default, bit-identical to the pre-phase code). With `ProfitObjective``(m)`
# the actor adds a retail margin `m[t]` per unit of net consumption: the customers of the
# portfolio face `DADP + m` and the actor books
#
# ```math
# \text{profit}_k = \sum_{t} m_t \,\ell_{k,t}, \qquad \ell_{k,t} = \text{net load of the portfolio's sites}.
# ```
#
# **First-welfare-theorem framing (read this before interpreting any number).** The wedge is a
# weighted objective inside the SAME price-taking equilibrium: the actor takes the DSO price as
# given, has no market power and does not play a Stackelberg game against the DSO price. It is
# **not a strategic aggregator** (that is deferred as ACTOR-F1). Consequently a zero wedge is a null
# result by design (the identity row below), and a nonzero wedge can only lower social welfare:
# `W_soc <= W_opt`, so the efficiency loss `dW = W_opt - W_soc` is non-negative up to the measured
# ADMM slack. A materially negative value would be a bug and is recorded as the verdict
# `refused:impossible_dW`, never hidden.

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

rows = read_csv(joinpath(pkgdir(TSODSO), "results", "actor_behaviour", "actor_behaviour_sweep.csv"))
wedge = filter(r -> r["fixture"] == "ieee13_wedge", rows)
behav = filter(r -> r["fixture"] == "ieee123_behaviour", rows)
println(length(rows), " committed measurement rows (", length(wedge), " wedge, ", length(behav), " behaviour)")
total_s = sum(num(r["runtime_s"]) for r in rows)
@printf("total sweep runtime recorded in the CSV: %.1f min\n", total_s / 60)

# ## 2. Efficiency loss of the wedge (IEEE-13 ground fixture)
#
# Two portfolios of half the houses each: the first earns the wedge `m`, the second stays on
# welfare. `W_opt` is the welfare-objective solve on the same fixture and seed (the `m = 0` row is
# the identity anchor: `ProfitObjective(0)` passes through bitwise, so `dW` is exactly zero). The
# `cent_*` columns are a centralized `solve_welfare` cross-check under the same wedge; the DADP gap
# column is its maximum absolute difference to the ADMM prices.

@printf(
    "%-6s %-10s %14s %12s %12s %12s %10s\n",
    "m", "verdict", "social W", "dW abs", "dW rel", "actor profit", "cent gap"
)
for r in sort(wedge; by = r -> num(r["wedge"]))
    @printf(
        "%-6s %-10s %14.4f %12.3e %12.3e %12.4f %10.2e\n",
        r["wedge"], r["verdict"], num(r["welfare"]), num(r["dW_abs"]), num(r["dW_rel"]),
        num(r["ledger_total_actor_1"]), num(r["cent_dadp_gap"])
    )
end

# The loss grows with `m` and then saturates: the response of the flexible devices is piecewise
# linear in the retail price, so beyond the last kink a larger margin changes nothing. The ratio
# below is computed from the table above, not typed.

let ws = sort(wedge; by = r -> num(r["wedge"]))
    ok = filter(r -> r["verdict"] == "ok" && num(r["wedge"]) > 0, ws)
    if length(ok) >= 2
        @printf(
            "dW(largest m) / dW(smallest positive m) = %.3f\n",
            num(ok[end]["dW_abs"]) / num(ok[1]["dW_abs"])
        )
    end
end

# ## 3. Portfolios and slots (several actors at one bus)
#
# Under ADMM the consensus variable is keyed by `(actor, bus)`, a *slot*, not by the bus alone.
# Several sites at one bus therefore iterate separately, the published DADP is per bus, and every
# slot at a bus must carry the same nodal price. That agreement is reported as the
# slot-lambda certificate (`slot_lambda_gap` = max over slots of the distance to the *primary*
# slot's multiplier at the same bus, `slot_lambda_agree` = gap within the measured 1e-12 floor;
# observed gap 2.7e-15), never thrown. Portfolios are
# a **grouping only**: a portfolio spanning several buses has no shared-resource coupling between
# its sites (a joint capacity limit across buses is deferred as ACTOR-F2). The settlement adapters
# sum nets and utilities per bus on shared buses, and the actor profit is a separate, exactly
# conserving mirror pair `(:actor, id)` / `(:aggregator, bus)` in the Phase-41 ledger, so
# `ledger_residual == 0.0` holds on every row of the artifact (checked live below).

let ok = filter(r -> r["verdict"] == "ok", rows)
    @printf("ledger_residual == 0.0 on %d of %d ok rows\n", count(r -> num(r["ledger_residual"]) == 0.0, ok), length(ok))
end

# ## 4. Behavioural scenarios (IEEE-123)
#
# Behaviour is exogenous and seeded, built by `apply_behaviour(aggs, BehaviourSpec(...); T)`:
#
# - **Partial compliance `xi`.** A wrapped device dispatches `p' = b + xi (p - b)` with the blended
#   utility `(1 - xi) Ub + xi U(p)`. This is the exact *expectation* over a population in which a
#   share `xi` responds and the rest keeps its baseline; it is not a single household's behaviour.
#   `xi = 0` is the pure opt-out.
# - **Opt-out.** A seeded per-device draw (the granularity is the device, not the house) removes a
#   share of devices from the response entirely. The opt-out is exogenous; endogenous opt-out is
#   deferred as ACTOR-F3.
# - **Rebound `r`.** A device that curtailed must recover at least `r` times the curtailed energy
#   within a window `W` of hours.
#
# **Baseline, stated honestly.** The no-response baseline `b` is the FIT flat price applied per
# device by a single-device solve. It is **not** `fit_baseline`'s output (that function returns
# per-aggregator flows, drops batteries, rejects EV/HeatPump/SmartInverterPV and runs a nested
# power flow). The rebound metric below compares the sum of these baselines against the realised
# net load.
#
# The anchor row (`xi = 1`, `opt_out = 0`, no rebound) is the unwrapped population and defines
# `W_ref`. A behavioural `dW` is `W_ref - W_row`; because a wrapped device has a blended utility the
# first-welfare-theorem sign guarantee does NOT apply, and the sign is reported as measured.

@printf(
    "%-5s %-8s %-9s %-4s %-8s %14s %12s %10s %10s %9s\n",
    "xi", "opt_out", "r", "seed", "verdict", "social W", "dW abs", "DADP mean", "DADP max", "rebound"
)
for r in sort(behav; by = r -> (-num(r["xi"]), num(r["opt_out"]), r["r"], num(r["seed"])))
    @printf(
        "%-5s %-8s %-9s %-4s %-8s %14.4f %12.3e %10.4f %10.4f %9.4f\n",
        r["xi"], r["opt_out"], r["r"], r["seed"], r["verdict"], num(r["welfare"]),
        num(r["dW_abs"]), num(r["dadp_mean"]), num(r["dadp_max"]), num(r["rebound_ratio"])
    )
end

# The next figures are derived from the table. `spread` is the largest welfare change relative to
# the anchor, expressed against `|W_ref|`; whether it is distinguishable from solver noise is the
# reader's call, and the repeated `xi = 0` rows give the cleanest noise reference: they describe
# the same population (everything opted out), so their welfare must coincide.

let ok = filter(r -> r["verdict"] == "ok", behav)
    ref = only(filter(r -> num(r["xi"]) == 1 && num(r["opt_out"]) == 0 && r["r"] == "none", ok))
    Wref = num(ref["welfare"])
    spread = maximum(abs(num(r["welfare"]) - Wref) for r in ok) / abs(Wref)
    @printf("largest |W - W_ref| / |W_ref| over the grid: %.3e\n", spread)
    xi0 = [num(r["welfare"]) for r in ok if num(r["xi"]) == 0]
    @printf("xi = 0 rows: %d, max pairwise welfare difference %.3e\n", length(xi0), maximum(xi0) - minimum(xi0))
    dm = maximum(abs(num(r["dadp_mean"]) - num(ref["dadp_mean"])) for r in ok)
    @printf("largest change of the mean DADP versus the anchor: %.3e\n", dm)
end

# ## 5. Settlement and the rebound metric
#
# Ledger totals per actor come from `build_settlement_ledger(...; actor_wedges)`. On the wedge block
# the actor profit is the `ledger_total_actor_*` column; the portfolio left on welfare has no
# wedge row (recorded `NaN`). The rebound metric (`rebound_amount`, `rebound_ratio`) is computed from
# the summed per-device baseline against the realised net load; the ratio is `NaN` exactly when
# there is no reduction hour.

@printf("%-14s %-6s %14s %14s %14s\n", "fixture", "m/xi", "aggregators", "merch. surplus", "rebound ratio")
for r in rows
    r["verdict"] == "ok" || continue
    @printf(
        "%-14s %-6s %14.4f %14.4f %14.4f\n",
        r["fixture"], r["fixture"] == "ieee13_wedge" ? r["wedge"] : r["xi"],
        num(r["ledger_total_aggregators"]), num(r["ledger_merchandising"]), num(r["rebound_ratio"])
    )
end

# ## 6. Refusals
#
# Certificate refusals, solve failures and an impossible `dW` are rows with
# `verdict = refused:<reason>`, never dropped and never repaired by loosening a tolerance.

let bad = filter(r -> r["verdict"] != "ok", rows)
    println(isempty(bad) ? "no refused points in this artifact" : "refused points:")
    for r in bad
        println("  ", r["fixture"], " wedge=", r["wedge"], " xi=", r["xi"], " -> ", r["verdict"])
    end
end

# ## Reproduce
#
# `julia --project=. scripts/actor_behaviour_sweep.jl` regenerates the CSV (the total runtime is
# printed at the top of this page, recomputed from the artifact). The columns are written in a
# fixed order; every column except `runtime_s` is deterministic, while `runtime_s` is a wall-clock
# measurement and differs on every run and machine. The slow test
# `test/test_actor_sweep.jl` checks the schema and re-solves one reference wedge point.
