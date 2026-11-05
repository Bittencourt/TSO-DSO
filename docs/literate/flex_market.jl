# # Flexibility market vs price coordination
#
# This page compares two ways a DSO can coordinate aggregators on the same feeder and the
# same population: price-based coordination through the dynamic distribution price (DADP), and
# a two-stage DSO flexibility market. The measurement is produced by
# `scripts/tariff_comparison.jl` and committed to `results/settlement_comparison/`:
#
# ```
# julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground --flex-market
# julia --project=. scripts/tariff_comparison.jl --mode ieee123 --flex-market
# julia --project=. scripts/tariff_comparison.jl --mode ieee123-default
# ```
#
# **This page solves nothing.** It reads the committed `tariff_comparison.csv` (and the per-hour
# `rebound_hourly.csv`) and recomputes every quoted number live from those rows, so no result
# below is typed by hand. The CSVs carry no run-date column; the provenance printed below is
# what every row stamps (Julia version, seed, horizon, thread counts), and the date of a
# measurement is the commit that recorded its rows.
#
# The library side is `src/coordination/` (the scheme types, bid generation, the stage-2 clear
# and the settlement) and the opt-in `flex_market` keyword of [`compare_tariffs`](@ref).

using TSODSO
using Printf

# The reader below is copied from the settlement page: it is quote-aware, because the recorded
# status messages contain commas and quotes, and an EMPTY cell (a deliberately missing value)
# parses to NaN, never silently to zero.

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
rebound_rows = read_settlement_csv(joinpath(RESULTS_DIR, "rebound_hourly.csv"))

# One summary row by (mode, tariff); `nothing` when the row is absent.
function find_row(mode, tariff)
    i = findfirst(r -> r["mode"] == mode && r["tariff"] == tariff, summary_rows)
    return i === nothing ? nothing : summary_rows[i]
end
isflex(r) = startswith(r["tariff"], "flex_")
const FLEX_MODES = ("ieee13-ground", "ieee123")

let modes = unique(r["mode"] for r in summary_rows)
    println(length(summary_rows), " committed summary rows over modes: ", join(modes, ", "))
    for mode in modes
        r = first(filter(x -> x["mode"] == mode, summary_rows))
        nflex = count(x -> x["mode"] == mode && isflex(x), summary_rows)
        @printf(
            "  %-16s seed %-9s T %-3s julia %-7s threads %s, BLAS %s; %d flexibility-market rows\n",
            mode,
            r["seed"],
            r["t_horizon"],
            r["julia_version"],
            r["threads"],
            r["blas_threads"],
            nflex
        )
    end
end

# ## 1. Two coordination schemes
#
# **Price-based (DADP).** One centralized social-welfare solve on the SOCP branch-flow model,
# certified by the exactness gate. Its nodal-balance duals are the distribution prices, and
# each aggregator responds to its own bus price. In the code this is `PriceBased()`.
#
# **Flexibility market.** `FlexMarket(; baseline_tariff, payment_rule, n_blocks,
# baseline_inflation)` runs two stages:
#
# 1. *Baseline.* Each aggregator dispatches as a price-taker against a revenue-neutral retail
#    tariff derived from the same DADP run: the flat tariff by default, TOU as an option. That
#    schedule is the baseline `b`.
# 2. *DSO redispatch.* On the same feeder, the same SOCP model and the same exactness gate, the
#    DSO buys activated up and down quantities from the aggregators' bids to minimise the cost
#    of accepted bids plus the wholesale import cost `λ₀ᵀ p_import`.
#
# The bids are divisible, piecewise-linear and **hour-separable**: `n_blocks` up and
# `n_blocks` down blocks per aggregator and hour (4 each by default). Each aggregator builds them
# by **probing its own model**: single-hour perturbation re-solves around the baseline, with
# the other hours held at baseline. The block price is the aggregator's own utility loss, so
# the bids are truthful by construction and the marginal cost is non-decreasing.
#
# Because a single-hour bid cannot carry intertemporal coupling (battery state of charge,
# deferrable energy), each aggregator then **re-solves to track its activated targets**
# `b + Δ`. The *delivered* dispatch is what gets settled, valued and AC-checked, and the
# delivery shortfall `|delivered − (b + Δ)|` is reported (section 8).
#
# **Reactive power in stage 2 is held at the inelastic draw `−Pdc·tanφ`.** The flex product is
# active power only, and the bid pseudo-device writes no reactive injection. Two reasons make
# this the right reading rather than a simplification of convenience: it is the same reactive
# model the AC feasibility check uses, so stage 2 and the AC verdict see the same `q`; and
# holding `q` at the full baseline value instead (which includes the flexible-load draw
# `p·tanφ` at the low flat price) makes the redispatch infeasible on these feeders. The
# documented difference from DADP is that the centralized DADP solve includes the flexible-load
# reactive draw and stage 2 does not. A population with a constant reactive injection
# (`FixedCapacitor`) is refused, because the pseudo-device cannot represent it.

# ## 2. First-welfare-theorem framing (read this before any number)
#
# With truthful, convex, divisible bids that equalled each aggregator's exact separable loss,
# the stage-2 optimality conditions would coincide with those of the centralized welfare solve:
# an accepted marginal block prices at the clearing price, and the network conditions are the
# same. The uniform clearing price would then equal the DADP price and the market welfare
# would equal the DADP welfare. This is the first-welfare-theorem (LP-duality) analogue of a
# competitive market.
#
# The bids used here are a finite set of blocks (bid discretisation) and are hour-separable
# approximations of a value function that is coupled across hours (hour separability). **The
# measured welfare gap is therefore the bid-discretisation plus hour-separability gap**, not a
# property of markets in general. It is printed below in the like-for-like (lossless)
# convention explained in section 3, absolute and relative to the DADP welfare on the same
# footing.

let
    for mode in FLEX_MODES
        for r in filter(x -> x["mode"] == mode && isflex(x), summary_rows)
            r["status"] == "ok" || continue
            num(r["baseline_inflation"]) == 0 || continue
            gap = num(r["welfare_gap_vs_dadp_lossless"])
            ref = num(r["welfare_dadp_lossless"])
            verdict =
                gap == 0 ? "NULL (exactly zero)" :
                (gap < 0 ? "flex below DADP" : "flex above DADP")
            @printf(
                "%-14s %-13s  welfare_gap_vs_dadp_lossless = %+.4f  (relative %+.3e)  -> %s\n",
                mode,
                r["tariff"],
                gap,
                gap / abs(ref),
                verdict
            )
        end
    end
end

# The uniform and pay-as-bid rows share one dispatch, so they print the same gap. The gap is
# not null on either feeder. It is small and negative on both, so the market comes close to
# DADP without reaching it, and it is larger, in absolute and in relative terms, on IEEE-123.
#
# The framing is cross-validated in `test/test_flex_market.jl`: the item "flex market: liveness
# against the centralized optimum (hour-separable)" clears an exactly hour-separable fixture
# for `n_blocks` in 1, 2, 4, 8 and 16 and checks that the centralized optimum bounds the
# market from above and that the gap shrinks strictly at every refinement. The item "flex
# market: clearing prices sit in a band around the DADP prices" checks the price side as a
# measured band, because a uniform clearing price over piecewise-linear bids is not the same
# object as a DLMP. On the IEEE feeders the largest such difference is the
# `price_gap_vs_dadp_max` column:

let
    for mode in FLEX_MODES
        r = find_row(mode, "flex_uniform")
        r === nothing && continue
        @printf(
            "%-14s max |π − λ_dadp| over activated bus-hours = %.4f\n",
            mode,
            num(r["price_gap_vs_dadp_max"])
        )
    end
end

# ## 3. Welfare convention: lossless vs lossy
#
# Every welfare number is **social welfare recomputed from utilities**, never an objective
# value: device utilities minus the wholesale cost `λ₀ᵀ p_import`. The flexibility-market
# welfare is evaluated on the delivered dispatch with the **lossless** import `−Σ_j n_j[t]`,
# the same convention as the flat and TOU legs: the delivered dispatch comes from device-level
# re-solves that carry no network state. The DADP welfare uses its own **loss-inclusive** SOCP
# import.
#
# A naive comparison therefore credits the flexibility market with the DADP loss cost and can
# show "flex above DADP". The like-for-like column `welfare_gap_vs_dadp_lossless` re-evaluates
# the DADP dispatch on the lossless footing (`welfare_dadp_lossless`) before subtracting. Both
# gaps are printed below; the difference between them is the DADP loss cost.

let
    @printf(
        "%-14s %15s %15s %15s %12s %12s %12s\n",
        "mode",
        "flex welfare",
        "DADP welfare",
        "DADP lossless",
        "raw gap",
        "lossless gap",
        "loss cost"
    )
    for mode in FLEX_MODES
        f = find_row(mode, "flex_uniform")
        d = find_row(mode, "dadp")
        (f === nothing || d === nothing) && continue
        wf, wd, wl = num(f["welfare"]), num(d["welfare"]), num(f["welfare_dadp_lossless"])
        @printf(
            "%-14s %15.4f %15.4f %15.4f %+12.4f %+12.4f %12.4f\n",
            mode,
            wf,
            wd,
            wl,
            wf - wd,
            num(f["welfare_gap_vs_dadp_lossless"]),
            wl - wd
        )
    end
end

# The raw gap is positive on both feeders and the lossless gap is negative on both: the
# flexibility market does **not** beat DADP. The raw sign is an artefact of the convention.

# ## 4. Payment rules: the dispatch is identical, only money moves
#
# - **Uniform:** activated flexibility at a bus and hour is paid the clearing price, the dual of
#   the stage-2 nodal balance at that bus and hour.
# - **Pay-as-bid:** each activated block is paid its own bid price times its quantity.
#
# The physics is computed once per clear and shared by both rules, so welfare, the AC verdict
# and the delivered dispatch are equal; the rows differ in the ledger only. The DSO pays the
# flexibility payments to the aggregators as mirrored transfer pairs in the same settlement
# ledger as the tariff legs, so the ledger still sums to zero exactly.

let
    @printf(
        "%-14s %-9s %14s %14s %16s %12s\n",
        "mode",
        "rule",
        "aggregators",
        "DSO",
        "flex payments",
        "welfare"
    )
    for mode in FLEX_MODES
        for t in ("flex_uniform", "flex_pab")
            r = find_row(mode, t)
            r === nothing && continue
            @printf(
                "%-14s %-9s %14.4f %14.4f %16.4f %12.4f\n",
                mode,
                r["payment_rule"],
                num(r["aggregators_total"]),
                num(r["dso_total"]),
                num(r["flex_payments_total"]),
                num(r["welfare"])
            )
        end
        u, p = find_row(mode, "flex_uniform"), find_row(mode, "flex_pab")
        (u === nothing || p === nothing) && continue
        @printf(
            "%-14s pay-as-bid pays %.4f less in flexibility payments; welfare equal: %s\n",
            mode,
            num(u["flex_payments_total"]) - num(p["flex_payments_total"]),
            num(u["welfare"]) == num(p["welfare"])
        )
    end
end

# The ordering is the static one expected from truthful bids: a block is accepted only when it
# is in the money at the clearing price, so its own bid price never exceeds what the uniform
# rule would pay it, and pay-as-bid never pays more than uniform. With strategic bidders the
# comparison would change (bidders shade their bids up under pay-as-bid); that is out of scope
# here (section 12).

# ## 5. Tariff on activation
#
# The settlement charges the baseline tariff on **all metered (delivered) energy** and pays
# flexibility on the **activated deviation** Δ. An up-activated unit is therefore billed the
# tariff for the energy it consumes and paid the clearing price for having moved, so relative to
# a baseline-settled design it earns tariff + clearing price. This is standard local flexibility
# market practice: retail energy and the flexibility service are settled separately. The
# column `tariff_on_activation = Σ p_t·Δ_{j,t}` quantifies the overlap. It moves money only;
# dispatch and welfare are unaffected.

let
    for mode in FLEX_MODES
        r = find_row(mode, "flex_uniform")
        r === nothing && continue
        @printf(
            "%-14s tariff_on_activation = %.4f  (against flex payments %.4f)\n",
            mode,
            num(r["tariff_on_activation"]),
            num(r["flex_payments_total"])
        )
    end
end

# ## 6. Why the market activates: congestion vs energy mispricing
#
# A flat-baseline market activates for two reasons that must not be confused:
#
# - **Congestion relief:** the baseline overloads a branch or a voltage limit, and stage 2 buys
#   the deviation that removes it.
# - **Energy mispricing:** the flat tariff is far from the wholesale price `λ₀`, so the baseline
#   misallocates energy across hours, and stage 2 (which minimises cost at `λ₀`) buys back the
#   energy value even in hours without any binding network limit.
#
# An hour counts as **congested** when the congestion and voltage-drop components of the
# stage-2 price decomposition exceed `κ·λ₀[t]` at some bus, with `κ = 1e-2`. The reported
# interval `[κ_lo, κ_hi)` is the measured range of thresholds that give exactly the same set of
# hours, so the count is robust to the choice of `κ` across that whole interval.
#
# The flat level is recovered from the CSV: under a flat baseline `p_t` is one constant, so
# `p = tariff_on_activation / (flex_up_total − flex_down_total)`. The mean of `λ₀` is computed
# from **the same price generator the script uses**: `build_price(:mem, 24, nothing)` for
# IEEE-13 (the script's `ground_setup`), and the script's own `ieee123_lambda0()` profile for
# IEEE-123, parsed from `scripts/tariff_comparison.jl` (not retyped here).

function script_ieee123_lambda0()
    path = joinpath(pkgdir(TSODSO), "scripts", "tariff_comparison.jl")
    ex = Meta.parseall(read(path, String))
    for a in ex.args
        if a isa Expr && a.head === :(=) && a.args[1] == :(ieee123_lambda0())
            return Core.eval(Module(), a.args[2])::Vector{Float64}
        end
    end
    return error("ieee123_lambda0() not found in $path")
end

λ0_by_mode = Dict(
    "ieee13-ground" => TSODSO.build_price(:mem, 24, nothing),
    "ieee123" => script_ieee123_lambda0(),
)

let
    for mode in FLEX_MODES
        r = find_row(mode, "flex_uniform")
        r === nothing && continue
        up, dn = num(r["flex_up_total"]), num(r["flex_down_total"])
        p_flat = num(r["tariff_on_activation"]) / (up - dn)
        λm = sum(λ0_by_mode[mode]) / length(λ0_by_mode[mode])
        @printf("%s:\n", mode)
        @printf(
            "  congested hours %d of %s at κ = %s; same hours for κ in [%.3e, %.4f)\n",
            Int(num(r["n_congested_hours"])),
            r["t_horizon"],
            r["congestion_kappa"],
            num(r["congestion_kappa_lo"]),
            num(r["congestion_kappa_hi"])
        )
        @printf("  activated up %.4f, down %.4f (Σ over aggregators and hours)\n", up, dn)
        @printf(
            "  flat level %.4f vs mean λ₀ %.4f (flat / mean = %.3f)\n",
            p_flat,
            λm,
            p_flat / λm
        )
        @printf(
            "  uniform payment per activated unit %.4f\n",
            num(r["flex_payments_total"]) / (up + dn)
        )
    end
end

# On both feeders the flat level sits far below the mean wholesale price, while the uniform
# payment per activated unit is of the order of the wholesale price. **A large part of what the
# market buys is energy-value correction of a mispriced baseline, not congestion relief**, and
# this is why the flexibility payments are large against the DADP merchandising surplus: under
# DADP each aggregator already faces the right energy price, so there is nothing to buy back.
# The congested-hour count separates the two: only those hours carry a network price
# component above the threshold.

# ## 7. Baseline gaming via β
#
# A flexibility market settles against a baseline the seller reports. The opt-in
# `baseline_inflation = β` models the classic manipulation: the *reported* baseline is the true
# baseline times `(1 + β)` on the up direction in congested hours (only positive consumption
# baselines are inflated). β changes **payments only, never physics**: the dispatch, the
# welfare and the AC verdict are those of the truthful clear, and each row reports the
# overpayment against the true baseline.

let
    for mode in FLEX_MODES
        for rule in ("uniform", "pab")
            rs = [find_row(mode, "flex_$rule$sfx") for sfx in ("", "_beta0.05", "_beta0.1")]
            any(isnothing, rs) && continue
            same_physics =
                all(r -> r["welfare"] == rs[1]["welfare"], rs) &&
                all(r -> r["max_overload_ratio"] == rs[1]["max_overload_ratio"], rs)
            @printf(
                "%-14s %-8s β = %s: overpayment %s; physics identical across β: %s\n",
                mode,
                rule,
                join((r["baseline_inflation"] for r in rs), " / "),
                join((@sprintf("%.4f", num(r["baseline_overpayment"])) for r in rs), " / "),
                same_physics
            )
            o05, o10 =
                num(rs[2]["baseline_overpayment"]), num(rs[3]["baseline_overpayment"])
            o05 > 0 && @printf(
                "%-14s %-8s overpayment(β = 0.10) / overpayment(β = 0.05) = %.6f\n",
                mode,
                rule,
                o10 / o05
            )
        end
    end
end

# On IEEE-13 the overpayment is linear in β: a seller who inflates its baseline by 10 % is paid
# for flexibility it never provided, at no physical cost. On IEEE-123 the overpayment is zero
# at every β, for a structural reason rather than robustness (section 10): the only congested
# hour is a reverse-flow export hour, where the baselines are negative and nothing is inflated.
#
# Baselines are a known weak point of local flexibility markets. The EcoGrid 2.0 field trial
# (Heinrich, Ziras, Syrri and Bindner, *Applied Energy* 261, 2020) reports real-life baseline
# problems for DSO services, and Ziras, Heinrich and Bindner, "Why baselines are not suited for
# local flexibility markets" (*Renewable and Sustainable Energy Reviews* 135, 2021), propose
# capacity-limitation services instead. The β rows quantify that exposure on this model; they
# are an exogenous sensitivity, not a model of strategic behaviour.

# ## 8. Hour-separability shortfall
#
# The bids are hour-separable, but the devices are not: a battery that discharges more in one
# hour has less energy for the next. The delivery re-solve tracks the targets `b + Δ` with a
# fixed, documented L1 penalty weight `w`, and whatever it does not reach is the **delivery
# shortfall**. It is reported, never hidden: total, worst single bus-hour, and ratio to
# `Σ|Δ|`.
#
# The weight rule, ten times the largest price in play, is a heuristic and **not a proof that
# the penalty is exact**. The penalty is exact only when `w` exceeds the multiplier of the
# tracking constraint, and that multiplier is a device's marginal utility at its target minus
# the tariff, bounded by the slope of the device's value function there rather than by any
# price. A steep utility, or a coupled device near the edge of its reachable set, can push it
# above `w`. What is guaranteed is weaker: the shortfall does not increase with the weight, so
# the value at `w` is an **upper bound** on the loss that hour separability alone causes.
#
# The `_10w` column measures how much the weight matters: it re-solves the delivery at ten
# times the weight. The change and the relative change are printed below; when the relative
# change is small, the shortfall is insensitive to the weight over a tenfold range.
# That is consistent with a structural hour-separability loss, but it does not rule out a
# tracking multiplier above `10w` (a near-vertical marginal-utility curve also gives an almost
# unchanged shortfall). The numbers are therefore the shortfall at `w`, with the `10w`
# sensitivity as the evidence for how far the weight can be trusted.

let
    for mode in FLEX_MODES
        r = find_row(mode, "flex_uniform")
        r === nothing && continue
        tot, tot10 =
            num(r["delivery_shortfall_total"]), num(r["delivery_shortfall_total_10w"])
        @printf(
            "%-14s w = %s: shortfall total %.4f, max %.3e, ratio %.3e; at 10w total %.4f (change %.2e, relative %.2e)\n",
            mode,
            r["tracking_weight"],
            tot,
            num(r["delivery_shortfall_max"]),
            num(r["delivery_shortfall_ratio"]),
            tot10,
            tot10 - tot,
            (tot10 - tot) / tot
        )
    end
end

# Bids that keep the intertemporal coupling (aggregate-flexibility polytopes) would remove this
# loss; they are future work.

# ## 9. AC feasibility per leg
#
# Every leg's dispatch is checked against the AC power flow and the verdict is **recorded, not
# gated**: `feasible`, `infeasible` (with the worst overload ratio), `solve_failed` (no AC
# operating point exists for that dispatch) or `not_run` (no dispatch, for example a refused
# leg). The stage-2 targets sit on the head-branch limit by construction (the redispatch buys
# exactly enough to make the binding branch tight), so a ratio a hair under or over 1 is a
# measured outcome, not a bug.

let
    for mode in FLEX_MODES
        println("mode: $mode")
        @printf(
            "  %-22s %-24s %-13s %8s %14s\n",
            "leg",
            "status",
            "feasibility",
            "thermal",
            "max overload"
        )
        for r in filter(x -> x["mode"] == mode, summary_rows)
            @printf(
                "  %-22s %-24s %-13s %8s %14s\n",
                r["tariff"],
                r["status"],
                r["feasibility_status"],
                cell(r["n_thermal_violations"]),
                isempty(r["max_overload_ratio"]) ? "-" :
                @sprintf("%.10f", num(r["max_overload_ratio"]))
            )
        end
    end
end

# On IEEE-13 the flat and TOU legs have no AC operating point at all (`solve_failed`), and
# the flexibility market restores a feasible dispatch from the same flat baseline. The
# TOU-baseline flexibility legs did not clear: the stage-2 redispatch solve ended
# `ALMOST_OPTIMAL` at the default optimizer and is recorded as an `error:SolveFailedError`
# status row (section 11), never re-tuned. FIT's committed error row is unchanged.

# ## 10. IEEE-123
#
# Two configurations were measured on the modified IEEE-123 feeder.
#
# **Certified configuration (`--mode ieee123`).** The certified test-fixture population (85 load
# nodes, one seeded thermostatic, deferrable and PV-battery house per node), the fixture's price
# profile and, for every welfare solve (DADP and the redispatch), the documented solver
# conditioning `select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)`. The
# exactness gate, `τ`, `ε` and the hybrid floor are untouched; the conditioning only asks the
# interior-point solver for a tighter stop. Wall times below are read from the CSV's
# `run_wall_s` (the whole comparison call) and `flex_wall_s` (the shared physics of one clear:
# probing, stage 2 and delivery) columns.

let
    d = find_row("ieee123", "dadp")
    f = find_row("ieee123", "flex_uniform")
    if d !== nothing && f !== nothing
        @printf("comparison call wall time %.1f s\n", num(d["run_wall_s"]))
        @printf(
            "flex clear: %d probe solves (%d failed), clear physics %.1f s\n",
            Int(num(f["n_probe_solves"])),
            Int(num(f["n_probe_failed"])),
            num(f["flex_wall_s"])
        )
        @printf(
            "baseline battery certificates refused at the flat price: %d\n",
            Int(num(f["baseline_batt_refused"]))
        )
    end
end

# Flat and TOU are AC-infeasible here (section 9), while every flexibility-market row is
# feasible. The single congested hour is a **reverse-flow PV export hour**: the flat baseline
# exports through the head branch at the PV peak. The flat leg's per-hour net load (from
# `rebound_hourly.csv`) shows it, together with the delivered flexibility-market net load in
# the same hour:

let
    flat = filter(r -> r["mode"] == "ieee123" && r["tariff"] == "flat", rebound_rows)
    flex =
        filter(r -> r["mode"] == "ieee123" && r["tariff"] == "flex_uniform", rebound_rows)
    if !isempty(flat) && !isempty(flex)
        k = argmin([num(r["counterfactual_net_load"]) for r in flat])
        t = flat[k]["t"]
        fx = only(filter(r -> r["t"] == t, flex))
        @printf(
            "hour %s: flat-baseline net load %.4f (export), flexibility-market net load %.4f\n",
            t,
            num(flat[k]["counterfactual_net_load"]),
            num(fx["counterfactual_net_load"])
        )
    end
end

# Because the congested-hour baseline is a net export, the β phantom has nothing to inflate,
# which is why the IEEE-123 overpayment is zero at every β (section 7).
#
# **Default population (`--mode ieee123-default`).** The default generated population
# (`build_population(:default, ..., :ieee123, ...)`), the `:mem` prices and the default
# optimizer. Its DADP solve is **refused at the SOCP exactness certificate**, so no leg exists;
# the refusal is recorded as its own status row and never re-tuned. Quoted from the row:

let
    r = find_row("ieee123-default", "(run)")
    if r !== nothing
        println("status: ", r["status"], "  (wall time ", r["run_wall_s"], " s)")
        println("notes : ", r["notes"])
    end
end

# The worst gap ratio sits just above 1, in the band between the solver's own precision and
# the gate. Loosening the gate to pass it would undercut every exactness claim of the
# framework; the certified configuration above is the honest IEEE-123 measurement.

# ## 11. Refusals and status rows
#
# Every row whose status is not `ok`, in every mode of the committed CSV. A refused or failed
# leg is a row, never dropped and never repaired by loosening a tolerance.

let
    bad = filter(r -> r["status"] != "ok", summary_rows)
    println(length(bad), " non-ok rows:")
    for r in bad
        note = replace(r["notes"], r"\s+" => " ")
        note = length(note) > 140 ? first(note, 140) * " …" : note
        @printf("  %-16s %-18s %-24s %s\n", r["mode"], r["tariff"], r["status"], note)
    end
end

# The list includes the IEEE-13 FIT row (the batteryless FIT dispatch is infeasible against
# the head-branch rating; recorded before the flexibility market existed and unchanged), the
# two TOU-baseline flexibility legs, the IEEE-123 FIT row, the IEEE-123 default-population
# refusal, and the run-level row of the 784-house mode (no flexibility leg runs there: a
# house-attributed run cannot carry flex legs, and that mode's DADP run is itself refused).

# ## 12. Assumptions and limitations
#
# - **Truthful bidding.** Every block is priced at the aggregator's own utility loss. No bid
#   shading or markup is modelled, so the pay-as-bid result is the truthful-bidder lower bound
#   on payments, not a prediction under strategic bidding.
# - **Exogenous β only.** Baseline inflation is a fixed sensitivity parameter, not a strategic
#   choice.
# - **No market power.** Aggregators are price-takers in both stages.
# - **Hour-separable, divisible bids.** No indivisible or binary blocks, and no intertemporal
#   coupling inside a bid; the delivery shortfall (section 8) measures the cost.
# - **Heuristic tracking weight.** The delivery penalty weight is ten times the largest price
#   in play, not a proven bound on the tracking multiplier, so the reported shortfall is an
#   upper bound on the hour-separability loss; the `10w` column measures its sensitivity
#   (section 8).
# - **Inelastic reactive power in stage 2** (section 1).
# - **Lossless flex welfare** against loss-inclusive DADP welfare; use the like-for-like column
#   (section 3).

# ## 13. Reproduce
#
# ```
# julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground --flex-market
# julia --project=. scripts/tariff_comparison.jl --mode ieee123 --flex-market   # several minutes
# julia --project=. scripts/tariff_comparison.jl --mode ieee123-default
# ```
#
# The ieee13-ground flex path first checks that the in-run DADP row reproduces the committed one
# bit for bit and writes nothing otherwise. Rows are upserted by provenance, and a run first
# deletes the rows of its own mode that it owns (every row of an IEEE-123 mode; the flex rows of
# the ieee13-ground flex path), so a re-run replaces its own rows, leaves no stale ones beside
# them, and keeps the others. The fast item "flex market: committed comparison CSV rows" in
# `test/test_flex_market_ieee.jl` checks the committed rows' invariants (statuses, no run-level
# row beside leg rows, β changes money only, the shortfall sums).
