# # Settlement, Tariffs & Equity — the per-actor ledger and its comparison
#
# This page documents the settlement layer (`src/settlement/`): how any solved run is
# settled into a per-actor money ledger that sums to zero with an EXPLICIT merchandising-
# surplus line (SETL-01); how flat and TOU tariffs are DERIVED revenue-neutrally from one
# DADP run and compared against FIT and nodal-DADP on the SAME network and population,
# with per-tariff counterfactual dispatch, AC-physics feasibility statuses, equity metrics
# and rebound (SETL-02, SETL-03, SETL-06); and how equity is broken out by PV ownership,
# electrical location and load level (SETL-05) — with the no-income-data statement below.
#
# The computational pieces each carry their own test certificate (`test/test_settlement.jl`,
# `test/test_equity.jl`); this page executes a tiny live slice so the rendered numbers
# cannot drift from the real `src/` code, and reads the committed measurement CSVs in
# `results/settlement_comparison/` for the heavy 784-house results (the precomputed-
# results precedent of the Case-A population and IEEE-8500 scaling pages).
#
# !!! note "No income data — the locked statement"
#     **Every equity number in this framework operates on per-household BILLS and SURPLUS
#     only. NO income data exists in this framework and none is used anywhere.** The proxy
#     groupings (PV owner vs non-owner, electrical location, load-level terciles of
#     baseline consumption) come from the `case_a_household_map` row shape — house, bus,
#     aggregator, device set, PV group, house index — no new data, and never an income
#     variable. This is the phase's locked deliverable (SETL-05), stated at module level in
#     `src/settlement/equity.jl` and repeated here because it qualifies every chart the
#     equity metrics will ever produce.
#
# ## The live slice — one DADP run settled end-to-end (seconds)
#
# The block below solves the 2-bus welfare fixture, packs it into a
# [`SettlementInput`](@ref), settles the double-entry ledger, derives the revenue-neutral
# flat and TOU prices, re-dispatches a price-taker at the run's own prices, checks the AC
# physics of that dispatch, and computes the four equity metrics on the ledger's household
# rows. Total runtime: a few seconds (T = 3, two buses, two houses).

using TSODSO
using TSODSO: Bus, Branch, Feeder
using Printf

feeder = Feeder(
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
    [Branch(1, 2, 0.01, 0.02, 10.0)],
    1,
)
T = 3
batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
λ₀ = fill(40.0, T)

# One DADP run (the social-welfare optimum; its duals ARE the nodal prices):
ctx, obj, _dadp =
    solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = λ₀, allow_export = true)
input = settlement_input(ctx; T = T, λ₀ = λ₀)
led = build_settlement_ledger(input)

# SETL-01: money conservation is EXACT by construction (double-entry mirror pairs).
@printf("ledger residual (must be 0.0)   : %.1f\n", ledger_residual(led))
@printf("merchandising surplus (DSO line): %.6f\n", led.merchandising_surplus)
@printf("wholesale payment               : %.6f\n", led.wholesale_payment)

# SETL-02: flat and TOU DERIVED from the same run, revenue-neutrally — the derived
# tariffs settle the SAME total at the run's own quantities (the fairness condition):
flat = flat_prices(input)
tou = tou_prices(input; bins = [[1, 2], [3]])
dadp_total = sum(input.prices[1, t] * input.bus_nets[2][t] for t in 1:T)
flat_total = sum(flat[t] * input.bus_nets[2][t] for t in 1:T)
tou_total = sum(tou[t] * input.bus_nets[2][t] for t in 1:T)
for t in 1:T
    @printf(
        "  t=%d  dadp %7.3f   flat %7.3f   tou %7.3f\n",
        t,
        input.prices[1, t],
        flat[t],
        tou[t]
    )
end
@printf(
    "totals  — dadp %.9f  flat %.9f  tou %.9f (all equal)\n",
    dadp_total,
    flat_total,
    tou_total
)

# The counterfactual dispatch at the run's own prices is the price-taker QP
# (no ADMM ρ-penalty); its AC physics is a RECORDED status, never a throw:
pt = price_taker_dispatch(agg, collect(input.prices[1, :]))
st = ac_feasibility_status(feeder, [agg], [pt.net]; T = T)
@printf(
    "price-taker at DADP prices — battery certificate: %s, AC status: %s\n",
    pt.battery_certificate,
    st.status
)

# SETL-04/05: the four equity metrics on the ledger's household rows. Two houses
# split the aggregator exactly in half (the synthetic split of test_settlement.jl);
# the metrics operate on BILLS only — no income data exists to use.
households = [
    (
        house_id = 1,
        bus = 2,
        net = input.bus_nets[2] ./ 2,
        utility = input.bus_utilities[2] / 2,
    ),
    (
        house_id = 2,
        bus = 2,
        net = input.bus_nets[2] ./ 2,
        utility = input.bus_utilities[2] / 2,
    ),
]
led_h = build_settlement_ledger(input; households = households)
bills = [h.bill for h in led_h.households]
surplus = [h.surplus for h in led_h.households]
th = theil(bills)
at = atkinson(bills)
@printf("household bills: %s\n", bills)
@printf(
    "gini %.6f  theil %.6f (n_excluded %d)  atkinson %.6f  palma %.6f\n",
    gini(bills),
    th.theil,
    th.n_excluded,
    at.atkinson,
    palma(bills)
)

# ## The 784-house comparison — read from the committed CSVs
#
# !!! note "This section reads committed data; nothing heavy is solved at build time"
#     The full comparison runs per mode through the measurement script. Regenerate with:
#     ```
#     julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground
#     julia --project=. scripts/tariff_comparison.jl --mode case-a-784   # long-running
#     ```
#     The script UPSERTS its rows into `results/settlement_comparison/*.csv` keyed on
#     provenance (mode, tariff, seed, t_horizon) — re-runs replace their own rows and
#     never drop others'. A killed run leaves the rows already captured — a kill is a
#     MEASURED OUTCOME (honesty policy), and so is every per-leg status row: a leg whose
#     certified values are missing is RECORDED, never dropped.
#
# The minimal reader below is quote-aware (the recorded status messages legitimately
# contain commas and quotes); an EMPTY cell is a deliberately-missing certified value
# and parses to NaN — never silently to zero.

function read_settlement_csv(path)
    function split_line(line)
        cells = String[]
        cur = Char[]
        inq = false
        i = firstindex(line)
        while i <= ncodeunits(line)
            c = line[i]
            if inq
                if c == '"'
                    if nextind(line, i) <= ncodeunits(line) && line[nextind(line, i)] == '"'
                        push!(cur, '"')
                        i = nextind(line, i)
                    else
                        inq = false
                    end
                else
                    push!(cur, c)
                end
            elseif c == '"'
                inq = true
            elseif c == ','
                push!(cells, String(cur))
                empty!(cur)
            else
                push!(cur, c)
            end
            i = nextind(line, i)
        end
        push!(cells, String(cur))
        return cells
    end
    lines = readlines(path)
    header = split_line(first(lines))
    return map(lines[2:end]) do ln
        cells = split_line(ln)
        Dict(header[j] => strip(cells[j]) for j in 1:min(length(header), length(cells)))
    end
end

num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
cell(s) = isempty(s) ? "-" : s

const RESULTS_DIR = joinpath(pkgdir(TSODSO), "results", "settlement_comparison")

summary_rows = read_settlement_csv(joinpath(RESULTS_DIR, "tariff_comparison.csv"))

# ### The measurement rows
#
# Each row is one tariff leg of one mode (or a "(run)" row: the DADP run itself refused
# or stalled — its own honest record, certified values missing). `status` carries the
# leg's honesty state (`ok`, `fit_inexact`, or `error:<Type>`), and `feasibility_status`
# the AC physics verdict of that leg's dispatch (`feasible`, `infeasible`,
# `solve_failed`, or `not_run` when no dispatch exists).

mode_rows = Dict{String, Vector{Dict{String, String}}}()
for r in summary_rows
    push!(get!(mode_rows, r["mode"], Dict{String, String}[]), r)
end

for mode in sort!(collect(keys(mode_rows)))
    rows = mode_rows[mode]
    println(
        "mode: $mode  (seed $(rows[1]["seed"]), T $(rows[1]["t_horizon"]), julia $(rows[1]["julia_version"]))",
    )
    println(
        "  tariff    status              feasibility   welfare          payments        MS",
    )
    for r in rows
        @printf(
            "  %-8s  %-18s  %-12s  %-15s  %-14s  %s\n",
            cell(r["tariff"]),
            cell(r["status"]),
            cell(r["feasibility_status"]),
            cell(r["welfare"]),
            cell(r["total_payments"]),
            cell(r["merchandising_surplus"])
        )
    end
end

# How to read the table, leg by leg:
#
#   - **dadp** — the run itself: the welfare-optimal dispatch settled at its own nodal
#     prices. Its `fairness_total` column (not printed above) IS its settlement: the
#     revenue-neutrality baseline every derived tariff must reproduce.
#   - **flat / tou** — revenue-neutral DERIVATIONS (41-03's tested constructors, same
#     input) re-dispatched through the penalty-free price-taker QP (all devices,
#     batteries included). Their `fairness_total` equals the dadp settlement within
#     measured rounding dust (pinned `rtol 2.8658034134118547e-15` / `1e-15` in
#     `test/test_settlement.jl`), so the comparison isolates DISPATCH behavior, not
#     tariff revenue. A `solve_failed` feasibility verdict means the counterfactual
#     dispatch has NO AC operating point on this feeder (beyond loadability) — a
#     recorded diagnostic, never a dropped leg.
#   - **fit** — `fit_baseline` consumed as-is (golden). On the congestion-calibrated
#     IEEE-13 fixtures the batteryless (A4) FIT dispatch is genuinely INFEASIBLE
#     against the head-branch thermal rating (attributed by probe: lifting only the
#     head `smax` makes `fit_baseline` converge) — recorded as an honest error row
#     with the non-certified values missing.
#
# ### Equity breakouts and household bills
#
# The per-group rows (PV ownership / electrical location / load tercile) and the
# per-household bill/surplus rows live in the sibling CSVs. They exist for modes run
# WITH household attribution (the `:case_a_784` mode rebuilds all 784 houses from the
# exact `_case_a_house` primitives); the smoke mode settles at bus granularity and
# legitimately writes no group rows.

bills_rows = read_settlement_csv(joinpath(RESULTS_DIR, "household_bills.csv"))
breakout_rows = read_settlement_csv(joinpath(RESULTS_DIR, "equity_breakouts.csv"))

house_modes = sort!(unique(r["mode"] for r in bills_rows if r["granularity"] == "house"))
for mode in house_modes
    rows = filter(r -> r["mode"] == mode && r["granularity"] == "house", bills_rows)
    m = filter(r -> r["mode"] == mode && r["tariff"] == "dadp", breakout_rows)
    println("mode: $mode — household-granularity bills")
    for tariff in sort!(unique(r["tariff"] for r in rows))
        tr = filter(r -> r["tariff"] == tariff, rows)
        vals = num.(r["bill"] for r in tr)
        @printf(
            "  %-5s  n=%3d  mean bill %9.4f  min %9.4f  max %9.4f\n",
            tariff,
            length(vals),
            sum(vals) / length(vals),
            minimum(vals),
            maximum(vals)
        )
    end
    for grouping in ("pv_group", "bus", "load_tercile")
        gr = filter(r -> r["grouping"] == grouping && r["metric_kind"] == "bills", m)
        isempty(gr) && continue
        println("  breakout by $grouping (bills):")
        for r in gr
            @printf(
                "    %-10s n=%3d  gini %8.5f  theil %8.5f (excl %s)  palma %8.5f\n",
                r["group"],
                round(Int, num(r["n"])),
                num(r["gini"]),
                num(r["theil"]),
                cell(r["theil_n_excluded"]),
                num(r["palma"])
            )
        end
    end
end
isempty(house_modes) &&
    println("no household-granularity rows recorded yet (bus-granularity modes only)")

# ## Metric conventions — the negative-value treatment, restated
#
# Each metric's full convention lives in its docstring (`src/settlement/equity.jl`) and
# is certified by hand-computed known-value tests (`test/test_equity.jl`, including the
# exact negative-bearing Gini `0.8125` and the uniform anchor `(0, 0, 0, 0.25)`). The
# short forms, which every table above inherits:
#
# | Metric | Convention | Negative-value behaviour |
# |---|---|---|
# | Gini | population mean-absolute-difference form over ALL values | a relative mean-difference measure, NOT a concentration index — may exceed 1 and may be negative on net-earning populations; values are NEVER zeroed or dropped (the documented bias finding) |
# | Theil | `(1/n) Σ (x/μ) ln(x/μ)` on the positive-support subset | non-computable for x ≤ 0 — the excluded count is a RETURNED value (`theil_n_excluded` columns), all-excluded ⇒ NaN, never a fake zero |
# | Atkinson | `1 − (Σ x^(1−ε)/n)^(1/(1−ε)) / μ` on the positive-support subset, ε = 0.5 | same positive-support restriction with the excluded count returned; ε = 1 (the log form) is deliberately unimplemented |
# | Palma | Σ(top 10 %)/Σ(bottom 40 %) over the sorted FULL vector | group totals cancel, so it is the most negative-robust; a negative bottom-40 sum yields a negative ratio reported as computed; an exactly-zero bottom sum ⇒ NaN |
# | rebound | load shifted into later hours after price-driven reductions, on NET-LOAD profiles (grid consumption = −net injection) | battery- and deferrable-driven shifts share one definition; no-reduction input ⇒ ratio NaN (reported), reductions without later increases ⇒ ratio exactly 0.0 |
#
# ## The A1 asymmetry — the FIT leg is batteryless, and it shows
#
# The `:dadp`/`:flat`/`:tou` legs settle household equity from per-house price-taker
# dispatches with ALL devices (batteries included — the rebound metric explicitly
# requires battery-driven shifts). The `:fit` leg is `fit_baseline` consumed as-is, and
# `fit_baseline` is BATTERYLESS by design (thesis Assumption A4): it also exposes no
# per-aggregator device utility. The comparison therefore reports the fit leg's equity
# at BUS granularity (`bills_granularity = bus`), with the surplus-side equity columns
# missing — marked, never hidden, and never back-filled with a different dispatch. On
# the congestion-calibrated IEEE-13 fixtures the asymmetry is physical: without
# batteries the FIT schedule's PV export cannot clear the head-branch thermal rating,
# and the leg is recorded as a genuine infeasibility.
#
# ## Reproducing every number on this page
#
# ```
# # the comparison measurement — fast smoke leg, then the thesis-scale leg (long-running)
# julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground
# julia --project=. scripts/tariff_comparison.jl --mode case-a-784
# # the settlement/equity test certificates (fast items + the :slow real-run identity)
# TSODSO_TEST_FILES=test_settlement.jl julia --project=. -e 'import Pkg; Pkg.test()'
# TSODSO_TEST_FILES=test_equity.jl julia --project=. -e 'import Pkg; Pkg.test()'
# ```
#
# *(Appended 2026-10-26. The live slice executes at docs-build time against the real
# `src/settlement/` code — T = 3, two buses, two houses, a few seconds. The 784-house
# sections read `results/settlement_comparison/*.csv` exactly as committed by
# `scripts/tariff_comparison.jl`: one row per tariff per mode with provenance
# (`julia_version`, `threads`, `blas_threads`, `seed`, `t_horizon`), per-leg status
# rows for every honest outcome, and equity breakouts by PV ownership, electrical
# location and load tercile for the household-attributed modes. No income data exists
# in this framework and none is used anywhere.)*
