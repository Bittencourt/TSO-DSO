# scripts/actor_behaviour_sweep.jl
#
# Phase 44 (ACTOR-01..04) -- effect of an actor objective (retail wedge) and of exogenous
# behavioural scenarios (partial compliance xi, opt-out, rebound r) on social welfare, DADP prices
# and the settlement ledger.
#
#   julia --project=. scripts/actor_behaviour_sweep.jl
#
# PURE ORCHESTRATION through the public API (`solve_admm`, `solve_welfare`, `apply_behaviour`,
# `settlement_input`, `build_settlement_ledger(...; actor_wedges)`, `rebound`, `actor_efficiency`).
# NOT `compare_tariffs`. No tolerance or tau is ever loosened to obtain a verdict.
#
# Two blocks, one CSV (results/actor_behaviour/actor_behaviour_sweep.csv):
#
#   (A) "ieee123_behaviour" -- the modified IEEE-123 feeder (85 load nodes, one seeded
#       Thermostatic + Deferrable + PVBattery house per node; the test fixture
#       test/fixtures_ieee123.jl population COPIED VERBATIM) solved by ADMM with the SAME
#       per-unit adaptive-rho configuration as test/test_ieee123_admm.jl. Grid over
#       compliance xi, opt-out share, rebound r (W = 4 hours) and the seed of the opt-out draw.
#       The anchor row (xi = 1, opt_out = 0, no rebound) is the unwrapped population and defines
#       W_ref; dW on a behavioural row is W_ref - W_row. Because a wrapped device carries a
#       BLENDED utility, a behavioural dW is NOT bounded by the first welfare theorem and is
#       reported with its sign (never flagged).
#   (B) "ieee13_wedge" -- the IEEE-13 ground fixture (10 houses), two portfolios of 5 houses; the
#       first earns the retail wedge m (ProfitObjective(m)), the second stays on welfare. W_opt
#       is the unwrapped, welfare-objective ADMM solve; dW = W_opt - W_soc must be >= 0 up to the
#       measured ADMM slack (1.24e-7 relative, test_actor_objective.jl); a materially negative
#       value is recorded as verdict "refused:impossible_dW" (a bug flag, never hidden).
#       A centralized `solve_welfare` cross-check column is recorded for every wedge.
#
# FRAMING: a wedge is a weighted objective inside ONE price-taking equilibrium (first welfare
# theorem), NOT a strategic aggregator. The behavioural baseline is the FIT flat price applied
# per device, not `fit_baseline`'s output.
#
# VERDICTS: "ok" | "refused:<kind>" (CertificateError.kind, or the exception type name for any
# other failure) | "refused:impossible_dW". Refusals are first-class rows with the measured
# diagnostics available (status column), never dropped.
#
# CSV KEY: (fixture, wedge, xi, opt_out, r, seed), String keys, `cols = :union`, upsert; columns in
# the fixed order `COLS` (runtime_s, the last one, is non-reproducible wall-clock).
# RUNTIME BUDGET: see RUNTIME note below (target < ~45 min total); `:case_a_784` is NOT used.
# One process at a time.

using DrWatson
@quickactivate "TSODSO"

using TSODSO
using TSODSO:
    CertificateError,
    Thermostatic,
    Deferrable,
    PVBattery,
    Aggregator,
    generate_profiles,
    ieee123_load_nodes,
    ieee123_modified,
    ieee13_modified
using TSODSO.JuMP
using CSV, DataFrames
using Printf

const T = 24
const OUT = projectdir("results", "actor_behaviour", "actor_behaviour_sweep.csv")

# ---- grids (sized after timing one warm IEEE-123 ADMM point, see RUNTIME) -------------------
const XIS = (1.0, 0.5, 0.0)
const OPT_OUTS = (0.0, 0.3)
const REBOUNDS = (nothing, (W = 4, r = 1.0))
const OPTOUT_SEEDS = (1, 2)                       # seeds of the opt-out draw
const WEDGES = (0.0, 0.5, 1.0, 2.0)               # IEEE-13 retail wedge m (same units as lambda)
const IMPOSSIBLE_REL = 1.24e-7                    # measured ADMM slack (test_actor_objective.jl)

# ---- IEEE-123 substrate (copied verbatim from test/fixtures_ieee123.jl) ---------------------
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)
const EPS_ABS = 1e-5
const EPS_REL = 1e-4
const TAU = 2.0
const MU = 10.0
const RHO_MIN = 1e-2
const RHO_MAX = 1e4
const RHO0 = 5.0

temperature_profile() = Float64[
    19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
    31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19,
]

ieee123_lambda0() = Float64[
    3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
]

# IEEE-13 price profile (test/fixtures_ieee13.jl `mem_price_profile`) = the same digitized shape.
ieee13_lambda0() = ieee123_lambda0()

function house(
    bus;
    seed,
    φ,
    pv_scale = 1.0,
    load_scale = 1.0,
    dev_scale = 1.0,
    batt_pmax = 0.5,
    batt_emax = 2.0,
    batt_soc0 = 1.0,
)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(
        bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, temperature_profile(),
    )
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(
        bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function ieee123_population()
    return [
        house(
            bus;
            seed = SEED_IEEE123,
            φ = 0.90,
            load_scale = LOAD_SCALE_IEEE123,
            pv_scale = PV_SCALE_IEEE123,
            dev_scale = DEV_SCALE_IEEE123,
            batt_pmax = 0.5 * LOAD_SCALE_IEEE123,
            batt_emax = 2.0 * LOAD_SCALE_IEEE123,
            batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
        ) for bus in ieee123_load_nodes()
    ]
end

# ---- IEEE-13 ground substrate (test/fixtures_ieee13.jl `build_ieee13_ground_aggregators`) ----
const GROUND_LOAD_SCALE = 0.005
const GROUND_PV_SCALE = 0.03
function ieee13_population(feeder; seed = 20260718)
    return [
        house(
            bus;
            seed = seed,
            φ = 0.90,
            load_scale = GROUND_LOAD_SCALE,
            pv_scale = GROUND_PV_SCALE,
            batt_pmax = 0.5 * GROUND_LOAD_SCALE,
            batt_emax = 2.0 * GROUND_LOAD_SCALE,
            batt_soc0 = 1.0 * GROUND_LOAD_SCALE,
        ) for bus in 2:length(feeder.buses)
    ]
end

# ---- row helpers -----------------------------------------------------------------------------
sanitize(s) = replace(first(string(s), 160), ',' => ';', '\n' => ' ', '"' => '\'')
rlabel(r) = r === nothing ? "none" : "W$(r.W)_r$(r.r)"

function new_row(fixture, wedge, xi, opt_out, r, seed)
    return Dict{Symbol, Any}(
        :fixture => fixture,
        :wedge => Float64(wedge),
        :xi => Float64(xi),
        :opt_out => Float64(opt_out),
        :r => rlabel(r),
        :seed => Int(seed),
        :verdict => "ok",
    )
end

function refuse!(row, e)
    if e isa CertificateError
        row[:verdict] = "refused:" * String(e.kind)
        row[:detail] = sanitize(e.msg)
    else
        row[:verdict] = "refused:" * String(nameof(typeof(e)))
        row[:detail] = sanitize(sprint(showerror, e))
    end
    return row
end

# Fill the shared measurement columns of a converged ADMM result.
function fill_admm!(row, res, aggs, λ₀, rows_wedge)
    row[:status] = String(res.status)
    row[:iters] = Int(res.iters)
    row[:welfare] = Float64(res.welfare)
    dadp = res.dadp
    row[:dadp_mean] = sum(dadp) / length(dadp)
    row[:dadp_max] = maximum(dadp)
    input = settlement_input(res; λ₀ = λ₀)
    led = build_settlement_ledger(input; actor_wedges = rows_wedge)
    row[:ledger_residual] = ledger_residual(led)
    row[:ledger_merchandising] = led.merchandising_surplus
    row[:ledger_wholesale] = led.wholesale_payment
    row[:ledger_total_aggregators] =
        sum(led.balances[(:aggregator, j)] for j in input.buses)
    return led
end

function rebound_columns!(row, aggs, res)
    base = sum(TSODSO.baseline_net_load(aggs, T))
    real = Float64[-sum(res.agr_dispatch[b][t] for b in keys(res.agr_dispatch)) for t in 1:T]
    rb = rebound(base, real)
    row[:rebound_amount] = rb.rebound_amount
    row[:rebound_ratio] = rb.rebound_ratio            # NaN kept when no reduction occurs
    row[:n_reduction_hours] = length(rb.reduction_hours)
    row[:n_increase_hours] = length(rb.increase_hours)
    return row
end

# ---- block A: IEEE-123 behaviour -------------------------------------------------------------
function admm123(feeder, aggs; actors = nothing)
    return solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = ieee123_lambda0(),
        ρ = RHO0,
        ε_abs = EPS_ABS,
        ε_rel = EPS_REL,
        τ = TAU,
        μ = MU,
        ρ_min = RHO_MIN,
        ρ_max = RHO_MAX,
        maxiter = 300,
        allow_export = true,
    )
end

function behaviour_point(feeder, pop, xi, opt_out, r, seed, W_ref)
    row = new_row("ieee123_behaviour", 0.0, xi, opt_out, r, seed)
    t0 = time()
    try
        spec = BehaviourSpec(compliance = xi, opt_out = opt_out, rebound = r, seed = seed)
        aggs = apply_behaviour(pop, spec; T = T)
        res = admm123(feeder, aggs)
        fill_admm!(row, res, aggs, ieee123_lambda0(), nothing)
        rebound_columns!(row, aggs, res)
        row[:actor_objective] = row[:welfare]          # welfare objective: actor objective = social
        if W_ref !== nothing
            e = actor_efficiency(W_ref, row[:welfare])
            row[:dW_abs] = e.delta_abs
            row[:dW_rel] = e.delta_rel
        end
    catch e
        refuse!(row, e)
    end
    row[:runtime_s] = time() - t0
    return row
end

# ---- block B: IEEE-13 wedge ------------------------------------------------------------------
function wedge_point(feeder, aggs, m, W_opt)
    row = new_row("ieee13_wedge", m, 1.0, 0.0, nothing, 20260718)
    t0 = time()
    λ₀ = ieee13_lambda0()
    kw = (
        T = T, λ₀ = λ₀, ρ = 100.0, tol = 1e-6, maxiter = 700,
        ε_abs = 1e-6, ε_rel = 1e-7, allow_export = true,
    )
    try
        h = length(aggs) ÷ 2
        ports = [
            Portfolio(aggs[1:h]; objective = ProfitObjective(m), name = :a),
            Portfolio(aggs[(h + 1):end]; name = :b),
        ]
        res = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., actors = ports)
        wrows = TSODSO.actor_wedge_rows(res, ports; T = T)
        led = fill_admm!(row, res, aggs, λ₀, wrows)
        row[:actor_objective] =
            haskey(res, :actor) ? Float64(res.actor.actor_objective_value) : row[:welfare]
        row[:ledger_total_actor_1] = get(led.balances, (:actor, 1), NaN)
        row[:ledger_total_actor_2] = get(led.balances, (:actor, 2), NaN)
        rebound_columns!(row, aggs, res)
        e = actor_efficiency(W_opt, row[:welfare])
        row[:dW_abs] = e.delta_abs
        row[:dW_rel] = e.delta_rel
        if e.delta_abs < -IMPOSSIBLE_REL * abs(W_opt)
            row[:verdict] = "refused:impossible_dW"
            row[:detail] = "W_soc exceeds W_opt beyond the measured ADMM slack"
        end
        # centralized cross-check under the same wedge (never decides the verdict)
        try
            cm = solve_welfare(
                feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true,
                actors = ports,
            )
            row[:cent_welfare] = Float64(cm[2])
            row[:cent_dadp_gap] = maximum(abs.(res.dadp[1, :] .- cm[3]))
        catch e2
            row[:detail] = get(row, :detail, "") * " | cent_crosscheck_failed:" *
                           sanitize(typeof(e2))
        end
    catch e
        refuse!(row, e)
    end
    row[:runtime_s] = time() - t0
    return row
end

# ---- upsert ----------------------------------------------------------------------------------
const KEYCOLS = (:fixture, :wedge, :xi, :opt_out, :r, :seed)
# FIXED, deterministic output column order (WR-05): the rows are `Dict`s whose iteration order is
# hash-dependent, so the CSV columns are always re-selected in this order. A column that no row
# carries is omitted (e.g. `detail` appears only once a refusal is recorded); a column not listed
# here is an error rather than a silently scrambled position.
# `runtime_s` is a WALL-CLOCK measurement: it is informational only and is NOT reproducible
# across runs/machines. Every other column is deterministic (seeded, single process).
const COLS = (
    :fixture, :wedge, :xi, :opt_out, :r, :seed, :verdict, :status, :detail, :iters,
    :welfare, :cent_welfare, :cent_dadp_gap, :dW_abs, :dW_rel, :actor_objective,
    :dadp_mean, :dadp_max, :n_increase_hours, :n_reduction_hours,
    :rebound_amount, :rebound_ratio,
    :ledger_wholesale, :ledger_merchandising, :ledger_total_aggregators,
    :ledger_total_actor_1, :ledger_total_actor_2, :ledger_residual,
    :runtime_s,
)

function ordered_columns(df)
    names_ = Symbol.(names(df))
    unknown = setdiff(names_, collect(COLS))
    isempty(unknown) || error("actor_behaviour_sweep: columns missing from COLS: $unknown")
    return select(df, [c for c in COLS if c in names_])
end
rowkey(r) = join((string(r[k]) for k in KEYCOLS), "|")

function upsert!(rows)
    mkpath(dirname(OUT))
    old = isfile(OUT) ? CSV.read(OUT, DataFrame) : DataFrame()
    allrows = Dict{String, Dict{Symbol, Any}}()
    order = String[]
    for r in eachrow(old)
        d = Dict{Symbol, Any}(Symbol(k) => (ismissing(v) ? missing : v) for (k, v) in pairs(r))
        k = join((string(d[c]) for c in KEYCOLS), "|")
        haskey(allrows, k) || push!(order, k)
        allrows[k] = d
    end
    for r in rows
        k = rowkey(r)
        haskey(allrows, k) || push!(order, k)
        allrows[k] = r
    end
    df = vcat(
        (DataFrame([k => [v] for (k, v) in allrows[o]]) for o in order)...;
        cols = :union,
    )
    df = ordered_columns(df)
    CSV.write(OUT, df)
    return df
end

function show_row(r)
    @printf(
        "%-18s m=%-4s xi=%-4s oo=%-4s r=%-10s s=%d  %-24s W=%s dW=%s t=%.0fs\n",
        r[:fixture], r[:wedge], r[:xi], r[:opt_out], r[:r], r[:seed], r[:verdict],
        get(r, :welfare, "NA"), get(r, :dW_abs, "NA"), r[:runtime_s],
    )
end

function main()
    rows = Dict{Symbol, Any}[]
    # --- block B first (cheap): IEEE-13 wedge
    f13 = ieee13_modified()
    a13 = ieee13_population(f13)
    W_opt13 = solve_admm(
        f13, ConvexBranchFlow(), a13;
        T = T, λ₀ = ieee13_lambda0(), ρ = 100.0, tol = 1e-6, maxiter = 700,
        ε_abs = 1e-6, ε_rel = 1e-7, allow_export = true,
    ).welfare
    for m in WEDGES
        r = wedge_point(f13, a13, m, W_opt13)
        show_row(r)
        push!(rows, r)
        upsert!(rows)
    end
    # --- block A: IEEE-123 behaviour
    f123 = ieee123_modified()
    pop = ieee123_population()
    anchor = behaviour_point(f123, pop, 1.0, 0.0, nothing, OPTOUT_SEEDS[1], nothing)
    show_row(anchor)
    W_ref = get(anchor, :welfare, nothing)
    if W_ref !== nothing
        anchor[:dW_abs] = 0.0
        anchor[:dW_rel] = 0.0
    end
    push!(rows, anchor)
    upsert!(rows)
    for xi in XIS, oo in OPT_OUTS, r in REBOUNDS
        (xi == 1.0 && oo == 0.0 && r === nothing) && continue      # the anchor
        # xi = 0 with an opt-out share is the same population as xi = 0 alone; still measured
        seeds = oo == 0.0 ? OPTOUT_SEEDS[1:1] : OPTOUT_SEEDS
        for seed in seeds
            row = behaviour_point(f123, pop, xi, oo, r, seed, W_ref)
            show_row(row)
            push!(rows, row)
            upsert!(rows)
        end
    end
    df = upsert!(rows)
    println("wrote ", nrow(df), " rows to ", OUT)
    return df
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
