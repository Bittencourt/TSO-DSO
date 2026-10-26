# # Case A Welfare-Gain Magnitude — the honest, pre-registered measurement
#
# This page is the writeup of the Phase 42 Case A welfare-gain magnitude measurement:
# the DADP-vs-FIT welfare gain of the real 784-house Case A population, measured under a
# PRE-REGISTERED protocol (`42-CASE-A-PROTOCOL.md` in the phase's planning directory,
# committed BEFORE any Case A run executed) and reported AT WHATEVER MAGNITUDE IT
# MEASURED — the PROJECT.md v5.0 honesty policy. It is the evidence chain's last link:
#
#   - **REPRO-03** — the SIGN-SAFE welfare-gain definition, pre-registered and guarded;
#   - **REPRO-04** — the headline measurement at the frozen registered configuration:
#     five master seeds, the bounded AGR solver-precision ladder, the centralized
#     cross-check, and the four-leg settlement lenses;
#   - **REPRO-05** — the four-axis OFAT ablation (FIT parameters, price range,
#     population, device mix) and the written gap-attribution statement.
#
# **Page contract.** This page READS `results/thesis_case_a_magnitude/*.csv` exactly as
# committed by `scripts/case_a_magnitude.jl` and SOLVES NOTHING — its whole live slice is
# reading those CSVs and recomputing the derived figures from the rows (seconds; the docs
# build's 30-minute CI budget is safe). Every relative figure below is RECOMPUTED LIVE
# from the committed rows (the Phase-28 CR-01 discipline: no stale derived number can
# survive a data revision), every division is SIGN-SAFE (denominator `abs(W_FIT)`), and
# every magnitude number is printed through ONE qualifier helper (defined below).
#
# !!! note "The locked statements (protocol §1–§2, §9–§10)"
#     The registered relative gain is `Δ% = 100·(W_DADP − W_FIT)/|W_FIT|` — SIGN-SAFE.
#     The naive ratio `W_DADP/W_FIT` is NEVER reported anywhere in this project: welfare
#     is large and NEGATIVE at the 784-house population, so the ratio sign-inverts (a
#     positive-looking number for a welfare LOSS). The SOC-exactness gate, the battery
#     τ and ρ = `ADMM().ρ` were never loosened or re-tuned — refusals and infeasibilities
#     are recorded MEASURED outcomes, answered only by the pre-registered ladder and its
#     ONE sanctioned solver-tightened retry. "Gap not fully attributed" and "whatever the
#     magnitude" are acceptable, pre-registered endings: closing the gap to the thesis's
#     +25% was NEVER a success condition.
#
# ## The live slice — committed-CSV reads only (seconds)
#
# The reader is quote-aware (the recorded status messages legitimately contain commas and
# quotes; the settlement page ships the same minimal reader) and treats an EMPTY cell as
# a deliberately-missing certified value — parsed to NaN, never silently to zero. The
# package import below exists ONLY for `pkgdir(TSODSO)` (the repo-root anchor the other
# committed-CSV pages use); nothing is solved, fitted or plotted on this page.

using TSODSO
using Printf

function read_case_a_csv(path)
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

const RESULTS_DIR = joinpath(pkgdir(TSODSO), "results", "thesis_case_a_magnitude")
readcsv(name) = read_case_a_csv(joinpath(RESULTS_DIR, name))
num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
cell(s) = isempty(s) ? "-" : s

const MAG = readcsv("magnitude.csv")     # the 5-seed headline ledger (REPRO-04)
const XCHK = readcsv("crosscheck.csv")   # the centralized cross-check + price lens
const ABL = readcsv("ablation.csv")      # the four-axis OFAT ablation table (REPRO-05)
const LENS = readcsv("lens_summary.csv") # the four-leg settlement lenses
const PROXY = readcsv("proxy.csv")       # the proxy restatement fixtures (protocol §8)

# Fail the docs build loudly if the evidence chain is broken — a missing/empty CSV must
# never render as an empty page.
for (name, rows) in (
    ("magnitude.csv", MAG),
    ("crosscheck.csv", XCHK),
    ("ablation.csv", ABL),
    ("lens_summary.csv", LENS),
    ("proxy.csv", PROXY),
)
    isempty(rows) && error(
        "case_a_magnitude page: $name carries no rows — the committed evidence chain " *
        "is broken; re-run the measurement (scripts/case_a_magnitude.jl) and commit " *
        "the CSVs before rendering this page",
    )
end

# The ONE qualifier convention this page introduces (the `scripts/thesis_case123_repro.jl`
# `REPRO_QUALIFIER`/`cite_repro` pattern): EVERY magnitude number printed below passes
# through this helper, which states what the number is — measured under the pre-registered
# protocol, reported at whatever magnitude it measured, never gated, never tuned toward a
# target.
const MAGNITUDE_QUALIFIER = "measured, pre-registered"
cite_magnitude(x) = "$x ($MAGNITUDE_QUALIFIER)"

# The page's own SIGN-SAFE recomputation (the registered definition, protocol §1): the
# denominator carries `abs`, so the sign of the result always equals the sign of
# `W_DADP − W_FIT` whatever the sign of the welfare level. `haspair` decides whether a
# row carries BOTH certified welfares (a certified pair) — an empty cell is NaN, so a
# refused leg is "no pair", never a zero.
delta_abs(w_dadp, w_fit) = w_dadp - w_fit
delta_pct_signsafe(w_dadp, w_fit) = 100 * (w_dadp - w_fit) / abs(w_fit)
haspair(r) = !isnan(num(r["welfare_dadp"])) && !isnan(num(r["welfare_fit"]))

# ## The pre-registered protocol — what was frozen, and when
#
# The protocol (`.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md`) was
# committed before any 784-house solve executed; every CSV row this page reads stamps a
# `protocol_sha` column (the 40-hex git SHA of the protocol's latest commit at measurement
# time), so every number below is auditable to the exact protocol version that produced it.
# The frozen pieces:
#
#   - **The gain definition** (REPRO-03): `ΔW = W_DADP − W_FIT`, `Δ% = 100·ΔW/|W_FIT|` —
#     the naive ratio banned (see the locked statements above).
#   - **The registered configuration** (REPRO-04): `:ieee13` feeder, `ConvexBranchFlow()`,
#     T = 24, λ₀ = `build_price(:mem)`, `allow_export = true`, the `:case_a_784` population
#     (784 houses → 10 bus-level aggregators), ρ = `ADMM().ρ` locked, provenance stamped
#     on every row (`julia_version`, `threads`, `blas_threads`, `seed`, `t_horizon`).
#   - **The seeds**: master seeds 42 (the registered continuity anchor) … 46 — each a full
#     honest re-draw via the POP-02 hash seeding.
#   - **The AGR solver-precision ladder**: `default → gap_1e-10 → gap_1e-12 →
#     gapfeas_1e-12`, stop-on-first-certified, hard stop after the last rung — the ONLY
#     answer to a refusal; no gate was ever loosened.
#   - **The four ablation axes** (REPRO-05): fit_params, price_range, population,
#     device_mix — axis names AND variant values committed pre-run; no free-form search.
#   - **The amendment policy**: the protocol file is append-only after the pre-run commit;
#     the ONE amendment (2026-10-26) repaired the `gapfeas_1e-12` rung's Clarabel
#     attribute spelling (`tol_feas`; the pre-registered `tol_feas_abs/rel` field names do
#     not exist in Clarabel 0.11.1) — name, ladder position and hard-stop unchanged; no
#     gate, no ρ, no battery τ touched. The `protocol_sha` trail printed below splits
#     visibly at that amendment.
#
# ## The headline — W_DADP certified 5/5 seeds; the FIT counterfactual refused on every one
#
# `magnitude.csv` stamps one row per ladder-rung attempt plus one terminal `gain` row per
# seed. The DADP leg CERTIFIED on all five seeds — the seed→rung attribution (which seed
# certified at which rung, at how many iterations, and the default-rung refusal the
# ladder answered) RECOMPUTES LIVE from the committed rows below; no seed→rung map or
# iteration count is hand-copied into this prose, so a re-measurement re-attributes
# visibly instead of silently disagreeing. The
# FIT leg — `fit_baseline` consumed unchanged, BATTERYLESS by thesis design (Assumption
# A4) — reports termination INFEASIBLE at the registered call AND at the ONE sanctioned
# solver-tightened retry on EVERY seed. **No certified pair exists at the registered
# 784-house mix: the headline DADP-vs-FIT Δ% is honestly UNDEFINED there.** That is a
# measured result of the honest-status discipline — not a failure of the measurement, and
# never a reason to loosen a gate or manufacture a value.

headline_rows = filter(r -> r["mode"] == "headline", MAG)
seeds = sort(unique(parse(Int, r["seed"]) for r in headline_rows))
w_certified = Float64[]
for s in seeds
    seed_rungs = filter(r -> r["kind"] == "rung" && r["seed"] == string(s), headline_rows)
    certified = filter(r -> r["status"] == "converged", seed_rungs)
    isempty(certified) && error(
        "case_a_magnitude page: headline seed $s has no certified rung row — the " *
        "committed ledger's DADP leg certified on every seed; investigate the CSV " *
        "before rendering this page",
    )
    c = certified[end]
    gain = filter(r -> r["kind"] == "gain" && r["seed"] == string(s), headline_rows)[end]
    @printf(
        "seed %d: W_DADP %s at rung '%s' (iters %s); FIT leg: %s\n",
        s,
        cite_magnitude(num(c["welfare_dadp"])),
        cell(gain["rung"]),
        cell(c["iters"]),
        cell(gain["status"]),
    )
    push!(w_certified, num(c["welfare_dadp"]))
end

# The seed→rung attribution, RECOMPUTED LIVE from the committed rows (the prose
# deliberately names no seed→rung map — this print IS the attribution, and a
# re-measurement restates it):
attribution = Dict{String,Vector{String}}()   # certified rung → seeds
default_refusal_iters = String[]              # default-rung refusal iterations, seed order
for s in seeds
    seed_rungs = filter(r -> r["kind"] == "rung" && r["seed"] == string(s), headline_rows)
    c = filter(r -> r["status"] == "converged", seed_rungs)[end]
    push!(get!(attribution, cell(c["rung"]), String[]), string(s))
    for r in seed_rungs
        if cell(r["rung"]) == "default" && startswith(cell(r["status"]), "error:")
            push!(default_refusal_iters, cell(r["iters"]))
        end
    end
end
for rung in sort!(collect(keys(attribution)))
    @printf(
        "DADP certified at rung '%s': seeds %s\n",
        rung,
        join(sort(attribution[rung]), ", "),
    )
end
isempty(default_refusal_iters) || @printf(
    "default-rung refusal (the battery-complementarity precedent) recorded at iters %s before certification\n",
    join(default_refusal_iters, ", "),
)

w_mean = sum(w_certified) / length(w_certified)
w_spread = maximum(w_certified) - minimum(w_certified)
@printf(
    "mean W_DADP %s; min–max spread %s (relative %.3e of |mean|)\n",
    cite_magnitude(w_mean),
    cite_magnitude(w_spread),
    w_spread / abs(w_mean),
)

head_gains = filter(r -> r["kind"] == "gain", headline_rows)
npairs = count(haspair, head_gains)
@printf(
    "certified DADP-vs-FIT pairs at the registered mix: %d of %d seeds → headline Δ%%: %s\n",
    npairs,
    length(head_gains),
    npairs == 0 ? "UNDEFINED (no W_FIT exists to divide by — the honest terminal rows)" :
    "defined",
)

# The seed-42 continuity anchor holds: the certified value printed above reproduces the
# committed Phase-40 `results/case_a_population/agreement.csv` welfare (−378163.5654, the
# same code path, seed and gap_1e-10 rung) to ALL printed digits — cited to that
# committed artifact, not re-read here.
# ## The centralized cross-check and the price-signal lens
#
# `crosscheck.csv` records the centralized `solve_welfare` bound at the registered seed —
# via the ONE sanctioned `tol_gap_1e-10` SOCP tightening, the same path the Phase-40
# agreement measurement used — and the DADP-vs-λ₀ price lens at the certified rung's
# conditioning. Both figures re-derive below from the row's own values.

x = XCHK[end]
w_cen = num(x["welfare_centralized"])
w_dadp42 = num(x["welfare_dadp"])
xabs = abs(w_cen - w_dadp42)
xrel = xabs / abs(w_dadp42)
@printf(
    "centralized bound (optimizer path '%s'): W_CEN %s\n",
    cell(x["centralized_optimizer"]),
    cite_magnitude(w_cen),
)
@printf(
    "|W_CEN − W_DADP| = %s (relative %.3e) — decomposed/centralized agreement to solver precision\n",
    cite_magnitude(xabs),
    xrel,
)
@printf(
    "price lens: max|λ_DADP − λ₀| = %s (relative %.3f on the max(|λ₀|, 1) denominator) — the DADP prices MOVE off the flat signal where the network asks them to\n",
    cite_magnitude(num(x["price_max_abs_delta"])),
    num(x["price_max_rel_delta"]),
)

# ## The ablation — where the gain IS measurable, and what it is
#
# `ablation.csv` is the complete four-axis OFAT table. Its certified DADP-vs-FIT pairs
# (both legs certified — the ONLY rows where Δ% exists under the registered definition)
# recompute below, live and sign-safe. The registered mix itself contributes NO pair (the
# FIT refusal above), so the per-axis effect versus the registered variant —
# `Δ%_variant − Δ%_registered` — is honestly UNDEFINED on every axis; the code computes
# it where both sides exist and says so where they do not.

gain_rows = filter(r -> r["kind"] == "gain", ABL)
pairs = filter(haspair, gain_rows)
println("certified DADP-vs-FIT pairs (ΔW and Δ% recomputed live, sign-safe):")
for r in pairs
    wd = num(r["welfare_dadp"])
    wf = num(r["welfare_fit"])
    @printf(
        "  axis %-12s variant %-14s ΔW %s  Δ%% %s\n",
        cell(r["axis"]),
        cell(r["variant"]),
        cite_magnitude(delta_abs(wd, wf)),
        cite_magnitude(delta_pct_signsafe(wd, wf)),
    )
end

println("per-axis effect on Δ% (variant Δ% − registered Δ%), recomputed live:")
for ax in unique(r["axis"] for r in ABL)
    reg = filter(
        r -> r["axis"] == ax && r["variant"] == "registered" && r["kind"] == "gain",
        ABL,
    )
    reg_dp =
        !isempty(reg) && haspair(reg[end]) ?
        delta_pct_signsafe(num(reg[end]["welfare_dadp"]), num(reg[end]["welfare_fit"])) :
        NaN
    for v in unique(r["variant"] for r in filter(r -> r["axis"] == ax, pairs))
        r = filter(r -> r["axis"] == ax && r["variant"] == v, pairs)[end]
        v_dp = delta_pct_signsafe(num(r["welfare_dadp"]), num(r["welfare_fit"]))
        effect = v_dp - reg_dp
        @printf(
            "  axis %-12s variant %-14s Δ%% %s  effect vs registered: %s\n",
            ax,
            v,
            cite_magnitude(v_dp),
            isnan(effect) ?
            "UNDEFINED — the registered mix has no measurable FIT gain (FIT refused; see the headline)" :
            cite_magnitude(effect),
        )
    end
end

# **The price-range axis cut hard both ways**: one variant runs the ladder to real
# EXHAUSTION (the honest terminal state is the documented non-closure,
# `error:ladder_exhausted`) while the other certifies — both verdicts, with their rungs
# and iterations, RECOMPUTE LIVE below (no rung count, iteration count or certifying
# rung is hand-copied into this prose). The verdict lines, then the per-rung ledger:

scale_rungs = filter(r -> r["axis"] == "price_range" && r["kind"] == "rung", ABL)
for v in ("scale_0.5", "scale_2.0")
    vr = filter(r -> r["variant"] == v, scale_rungs)
    cert = filter(r -> cell(r["status"]) == "converged", vr)
    if isempty(cert)
        @printf(
            "  price_range/%-10s NOT CERTIFIED — terminal state %s over %d rung rows (iters %s)\n",
            v,
            isempty(vr) ? "no rows" : cell(vr[end]["status"]),
            length(vr),
            join((cell(r["iters"]) for r in vr), ", "),
        )
    else
        @printf(
            "  price_range/%-10s CERTIFIED at rung '%s' (iters %s)\n",
            v,
            cell(cert[end]["rung"]),
            cell(cert[end]["iters"]),
        )
    end
end
for v in ("scale_0.5", "scale_2.0")
    vr = filter(r -> r["variant"] == v, scale_rungs)
    for r in vr
        @printf(
            "  price_range/%-10s rung %-13s status %-22s iters %s\n",
            v,
            cell(r["rung"]),
            cell(r["status"]),
            cell(r["iters"]),
        )
    end
end

# The population axis carries the gain-vs-population-size curve (the Phase-40
# nested-prefix rungs, no per-rung re-tuning) plus the headline row itself (`full_784`,
# reused provenance-transparently, never re-run). FIT certifies only at the small rungs —
# and every certified gain there sits ORDERS OF MAGNITUDE below the thesis's +25% (the
# exact factors print below, recomputed live):

pop_order = (
    "rung_1/78",
    "rung_0.125",
    "rung_0.25",
    "rung_0.5",
    "rung_0.75",
    "rung_1.0",
    "full_784",
)
println("population curve (seed 42; W_DADP from the committed rung/reuse rows):")
for v in pop_order
    rows = filter(r -> r["axis"] == "population" && r["variant"] == v, ABL)
    isempty(rows) && error(
        "case_a_magnitude page: population axis is missing variant '$v' — the " *
        "committed ablation table is incomplete; investigate before rendering",
    )
    gain = filter(r -> r["kind"] == "gain", rows)[end]
    wd = num(gain["welfare_dadp"])
    dp = haspair(gain) ? delta_pct_signsafe(wd, num(gain["welfare_fit"])) : NaN
    @printf(
        "  %-10s W_DADP %s  status %-20s Δ%% %s\n",
        v,
        cite_magnitude(wd),
        cell(gain["status"]),
        isnan(dp) ? "undefined (no certified pair)" : cite_magnitude(dp),
    )
end
for v in ("rung_0.25", "rung_0.5")
    r = filter(r -> r["axis"] == "population" && r["variant"] == v && haspair(r), ABL)
    isempty(r) && continue
    dp = delta_pct_signsafe(num(r[end]["welfare_dadp"]), num(r[end]["welfare_fit"]))
    @printf(
        "  distance below the thesis +25%%: Δ%% %s → a factor of %.3e below (measured point, never gated)\n",
        cite_magnitude(dp),
        25.0 / dp,
    )
end

# ## The proxy restatement — ≈+0.263% under the registered definition
#
# The SAME protocol re-run on the IEEE-123 `:default` proxy (one house per load bus,
# fixture seed 20260719 — the provenance fixture of `scripts/thesis_case123_repro.jl`)
# restates the published ≈+0.263% figure under the pre-registered definition. Proximity is
# REPORTED — the underlying seeding differs from the script's ad-hoc per-bus construction,
# so exact equality is neither expected nor required (protocol §8) — never gated and never
# tuned toward. The same-feeder IEEE-13 `:default` proxy keeps its honest statuses.

p = filter(r -> r["fixture"] == "ieee123-default" && r["kind"] == "gain", PROXY)[end]
dp_proxy = delta_pct_signsafe(num(p["welfare_dadp"]), num(p["welfare_fit"]))
# The CITED EXTERNAL provenance figure (scripts/thesis_case123_repro.jl's restatement) —
# a literature value for proximity reporting, NOT a magnitude golden and NOT a gate.
const PROVENANCE_PROXY_PCT = 0.263
@printf(
    "measured proxy Δ%% %s vs the cited ≈+%.3f%% provenance figure → the measured figure sits a factor %.1f BELOW the provenance restatement (reported proximity; protocol §8: exact equality neither expected nor required — never gated)\n",
    cite_magnitude(dp_proxy),
    PROVENANCE_PROXY_PCT,
    PROVENANCE_PROXY_PCT / dp_proxy,
)
for r in filter(r -> r["fixture"] == "ieee13-default" && r["kind"] == "gain", PROXY)
    @printf(
        "ieee13-default proxy: status %s (the committed FIT-INFEASIBLE precedent at the ground fixture — an honest recorded outcome)\n",
        cell(r["status"]),
    )
end

# ## The honesty section — asymmetries stated, refusals counted, nothing tuned
#
# ### The A1/A4 asymmetry — the FIT leg is batteryless, and it shows (it IS the finding)
#
# The DADP leg carries batteries (the registered 3-device set: Thermostatic + Deferrable +
# PVBattery). The FIT counterfactual is `fit_baseline` consumed as-is — BATTERYLESS by
# thesis design (Assumption A4). At the registered 784-house mix this asymmetry blocks
# the measurement through TWO battery-linked mechanisms: the DADP battery-complementarity
# certificate refuses the default rung (answered by the pre-registered ladder, never by a
# gate change), and the batteryless FIT dispatch is genuinely INFEASIBLE. The device-mix
# ablation MEASURES the asymmetry instead of back-filling it: with batteries dropped from
# EVERY house, BOTH mechanisms vanish — the ladder certifies at the `default` rung in 5
# iterations (the complementarity refusal is gone) and the FIT leg certifies — producing
# the only full certified pair at the 784-house scale. No battery was added to the FIT
# leg; no correction term was invented.
#
# ### The DSO-surplus sign-flip lens — confirmed at full scale
#
# The v2.1/v4.0 headline the thesis itself frames — the DSO's settlement surplus flipping
# sign between the flat/TOU counterfactuals and DADP — re-derives from
# `lens_summary.csv` (the four-leg settlement at the certified 784-house point):

for r in LENS
    dso = num(r["dso_total"])
    @printf(
        "  tariff %-5s status %-22s dso_total %s\n",
        cell(r["tariff"]),
        cell(r["status"]),
        isnan(dso) ? "-" : cite_magnitude(dso),
    )
end
dso_dadp = num(filter(r -> r["tariff"] == "dadp", LENS)[end]["dso_total"])
dso_flat = num(filter(r -> r["tariff"] == "flat", LENS)[end]["dso_total"])
@printf(
    "the sign flip: DADP %s vs flat %s — POSITIVE under DADP, negative under the derived tariffs, at the full 784-house scale\n",
    cite_magnitude(dso_dadp),
    cite_magnitude(dso_flat),
)

# ### The refusal ledger — every error row, with its iterations
#
# The no-cherry-picking contract: every refusal, infeasibility and exhaustion is a
# committed row. The complete `error:` ledger of the headline and ablation artifacts:

n_err = let count = 0
    for r in MAG
        startswith(r["status"], "error:") || continue
        count += 1
        @printf(
            "  magnitude.csv   seed %-3s kind %-5s rung %-13s %-24s iters %s\n",
            cell(r["seed"]),
            cell(r["kind"]),
            cell(r["rung"]),
            cell(r["status"]),
            cell(r["iters"]),
        )
    end
    for r in ABL
        startswith(r["status"], "error:") || continue
        count += 1
        @printf(
            "  ablation.csv    axis %-11s variant %-16s kind %-5s %-24s iters %s\n",
            cell(r["axis"]),
            cell(r["variant"]),
            cell(r["kind"]),
            cell(r["status"]),
            cell(r["iters"]),
        )
    end
    count
end
@printf("total honest error rows in the two ledgers: %d\n", n_err)

# ### The no-tuning statement — the structural guard, with its sha trail
#
# The ablation axes AND their values were committed before any run (protocol §7); every
# intermediate row is committed — refusals included (the ledger above); the ONE constant
# introduced after intermediate results were visible went through the protocol's own
# amendment procedure (the 2026-10-26 `gapfeas_1e-12` Clarabel attribute spelling repair,
# an append-only dated amendment committed with the runner edit in the same deliberate
# act). No constant anywhere in this phase was fit to the +25% target. The `protocol_sha`
# values actually present in the committed rows — printed live — are:

for sha in unique(r["protocol_sha"] for r in vcat(MAG, ABL, XCHK, LENS, PROXY))
    println("  ", sha)
end
distinct_shas = unique(r["protocol_sha"] for r in vcat(MAG, ABL, XCHK, LENS, PROXY))
println(
    "  ($(length(distinct_shas)) distinct protocol_sha values across the committed " *
    "rows — the append-only 2026-10-26 amendment splits the trail visibly, per the " *
    "amendment policy; which prefix is the pre-run protocol vs the amendment resolves " *
    "from the protocol file's git history, never from a hand-copied annotation)",
)

# ## The attribution statement — what the +25% question measurably resolves to
#
# The thesis frames the Case A outcome as a ≈+25% welfare gain (the FIT-ratio framing of
# its Appendix E digitization). Under the pre-registered SIGN-SAFE definition, the
# measurement resolves that question as follows:
#
#   1. **At the registered 784-house mix the DADP-vs-FIT gap is UNDEFINED** — the FIT
#      counterfactual refuses (INFEASIBLE at attempt AND the one sanctioned retry) on
#      every seed. There is NO measurable FIT gain at the registered mix for a gap to
#      +25% to be computed against. The measured DADP-vs-FIT gap therefore CANNOT be
#      attributed to the thesis +25% at the registered mix.
#   2. **Every point where the gain IS measurable sits orders of magnitude below +25%** —
#      every certified pair the committed ledgers carry (the ablation variants and the
#      proxy), its sign-safe Δ% and its distance below +25% (the 25.0/Δ% factor)
#      RECOMPUTE LIVE in the table printed right below this list — no Δ% or factor is
#      hand-copied into the prose. The thesis +25% number is NOT reproduced at any
#      measured point.
#   3. **What explains the direction and the size of the measured state**: the A1/A4
#      battery asymmetry (the FIT counterfactual is batteryless by design — it blocks the
#      registered mix outright and dominates the measurable comparison), the repo's
#      congestion-calibrated IEEE-13 fixture with its SOC-exactness and battery-
#      complementarity certification gates (stricter physics than the thesis framing),
#      and the sign-safe definition itself (the banned ratio framing cannot be used to
#      restate a +25%-shaped number here).
#   4. **The gap is NOT FULLY ATTRIBUTED** — explicitly an acceptable, recorded outcome
#      (protocol §9). Closing the gap to +25% was never a success condition: the phase
#      succeeds on the honesty of the measurement — reported at whatever magnitude it
#      measured — not on the size of the gain.
#
# Item 2's magnitudes, RECOMPUTED LIVE (the same sign-safe recomputation the population
# and proxy sections print inline, now over EVERY certified pair — newest committed row
# per axis/variant, plus the proxy):

last_pair = Dict{String,Dict{String,String}}()
for r in pairs
    last_pair[cell(r["axis"]) * "/" * cell(r["variant"])] = r
end
last_pair["proxy/ieee123-default"] = p
println("every measurable point vs the thesis +25% (recomputed live, sign-safe):")
for k in sort!(collect(keys(last_pair)))
    r = last_pair[k]
    wd = num(r["welfare_dadp"])
    wf = num(r["welfare_fit"])
    dp = delta_pct_signsafe(wd, wf)
    @printf(
        "  %-28s Δ%% %s → a factor of %.3e below +25%% (measured point, never gated)\n",
        k,
        cite_magnitude(dp),
        25.0 / dp,
    )
end
#
# ## Reproducing every number on this page
#
# ```
# # the measurement modes that wrote the committed CSVs this page reads (long-running)
# julia --project=. scripts/case_a_magnitude.jl --mode headline
# julia --project=. scripts/case_a_magnitude.jl --mode crosscheck
# julia --project=. scripts/case_a_magnitude.jl --mode lenses
# julia --project=. scripts/case_a_magnitude.jl --mode proxy
# julia --project=. scripts/case_a_magnitude.jl --mode ablation-fit
# julia --project=. scripts/case_a_magnitude.jl --mode ablation-price
# julia --project=. scripts/case_a_magnitude.jl --mode ablation-population
# julia --project=. scripts/case_a_magnitude.jl --mode ablation-devices
# # the structural certificates (fast) + the seed-42 reproducibility band (:slow)
# TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'
# TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'
# ```
#
# *(Appended 2026-10-26. The page executes ONLY committed-CSV reads — no solve call
# exists on it; every derived percentage recomputes live from
# `results/thesis_case_a_magnitude/*.csv` as committed by `scripts/case_a_magnitude.jl`
# under the pre-registered protocol. Headline outcome, honestly: W_DADP certified on all
# five seeds; the FIT counterfactual INFEASIBLE everywhere at attempt and retry; the
# registered-mix Δ% undefined; the measurable gains three-to-seven orders below the
# thesis +25%; gap not fully attributed — recorded.)*
