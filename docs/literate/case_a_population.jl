# # The Case A population — 784 houses over the IEEE-13 feeder
#
# Every other page of this manual populates its feeder with one residential
# `Aggregator` per load bus. The thesis's Case A study instead works at a true
# **784-house** population scale — and this page documents, for a reader who
# never opens the source: how that population is constructed, how it is
# calibrated, what it actually contains (measured live at docs-build time),
# what the centralized and decomposed solve engines agree on (measured, and
# honestly qualified), how solve cost scales with population size and with
# thread count (measured), and which thesis parameters were NOT available when
# the population was built — with the exact rule that replaced each one.
#
# One structural fact shapes the whole design: the decomposed (ADMM) solver
# requires EXACTLY one aggregator per load node — it throws on any other count —
# and the centralized price extraction needs one unique bus row per load node.
# The 784 houses are therefore rolled up, at construction time, into exactly
# **10 bus-level `Aggregator`s** (the houses' device lists concatenated, their
# inelastic demands summed). The house-level granularity is not lost: it lives
# in the construction itself (every house draws its own seeded profile and its
# own device parameters), in the pure `TSODSO.case_a_household_map` accessor,
# and in the composition statistics below.

using TSODSO
using TSODSO:
    _CASE_A_PV_FRACTION,
    _CASE_A_TOTAL_HOUSES,
    _IEEE13_DEV_SCALE,
    _IEEE13_LOAD_SCALE,
    _IEEE13_PV_SCALE,
    build_feeder,
    build_population,
    case_a_household_map,
    sub_seed
using Printf

# ## Construction rule
#
# `TSODSO.build_population(:case_a_784, ...)` over the modified IEEE-13 feeder
# builds the population. Three rules fully determine it; each one is
# test-enforced in `test/test_population_case_a.jl`.
#
# **Per-bus house counts.** The houses are distributed over the 10 load buses
# proportionally to the default population's per-bus counts — which on this
# feeder is exactly ONE house per bus (a uniform signal, so "proportional"
# degenerates to equal shares). Every bus receives the base share
# `total ÷ length(buses)`; the residue `total % length(buses)` is handed out
# +1 per bus to the FIRST buses in ascending bus-id order. That tiebreak is a
# documented specialization: the rule's original "largest buses first" language
# carries no size signal on a uniform base, so it resolves to bus id. The live
# tally below prints the resulting table.
#
# **Per-house seeding.** Every house's profile draw is seeded by
# `Int(hash((s_pop, :house, bus, house_index)) % typemax(UInt32))` with
# `s_pop = sub_seed(master_seed, :population)` — the materializer's standard
# hash idiom extended with a richer tuple. The derivation is deliberately
# per-HOUSE: the older `seed + bus` idiom gives every house on a bus the
# IDENTICAL draw, which would silently collapse this population to ten distinct
# houses repeated over and over. The tests assert that all 784 seeds are
# distinct, that rebuilding reproduces the population exactly, and that all
# 784 full profile draws are distinct.
#
# **The PV-ownership group.** Every household-map row carries a `pv_group`
# field from a generic rule (`:pv` when
# `house_index ≤ ceil(pv_fraction × houses_on_bus)`, else `:non_pv`). At the
# named constant `_CASE_A_PV_FRACTION = 1.0` every house is `:pv` — which is
# the honest reading of the locked calibration decision below, because the
# default population is all-PV (every house carries a `PVBattery`). The field
# is deliberately generic: a later phase can lower the constant without
# redesigning anything.
#
# The live slice below builds the population and tallies the household map. It
# is build-only work — seeded random draws and struct construction:
#
# !!! note "Sized against a measured docs-build baseline, not guessed"
#     `julia --project=docs docs/make.jl` on the pre-existing (19-page) doc set was
#     MEASURED at **≈6.8 minutes** wall time against this job's shared
#     `timeout-minutes: 30` CI budget (the Scaling to IEEE-8500 page recorded that
#     measurement). This page performs **no optimization of any kind** — no model is
#     built, no solver is invoked — and its live slice (784 seeded profile draws plus
#     struct construction) costs seconds. Every solver-derived number on this page is
#     instead READ from the committed CSVs in `results/case_a_population/`.

## The standard Case A seed — the same value every measurement script below
## records in its CSV provenance columns — and the thesis day length.
const CASE_A_SEED = 42
const T_HORIZON = 24

feeder = build_feeder(:ieee13)
profiles = generate_profiles(; seed = sub_seed(CASE_A_SEED, :profiles), T = T_HORIZON)
s_pop = sub_seed(CASE_A_SEED, :population)
aggs = build_population(:case_a_784, feeder, :ieee13, profiles, s_pop)
households = case_a_household_map(feeder, :ieee13, s_pop)

buses = sort(unique(r.bus for r in households))
per_bus = [(bus = b, houses = count(r -> r.bus == b, households)) for b in buses]

@printf("households (map rows)       : %d\n", length(households))
@printf("named total constant        : %d\n", _CASE_A_TOTAL_HOUSES)
@printf("bus-level aggregators built : %d\n", length(aggs))
@printf(
    "devices per house           : %d\n",
    length(reduce(vcat, (a.devices for a in aggs))) ÷ length(households),
)
println("bus   houses")
for row in per_bus
    @printf("%3d   %5d\n", row.bus, row.houses)
end

# ## Calibration provenance
#
# **Per-house magnitude scale.** Each house's device magnitudes use the IEEE-13
# residential scales DIVIDED by its bus's house count. The rationale is
# load-bearing: dividing by houses-per-bus preserves each bus's aggregate load
# and PV at the validated default level, keeping both solve engines in the
# known-good congestion/voltage regime that the one-house-per-bus proxy was
# calibrated in. Raw per-house scales would instead put roughly 78× the
# calibrated load through the 6.86 MVA head branch — near-certainly infeasible,
# which would render every agreement and scaling measurement meaningless. The
# printout below shows the constants doing the dividing.
#
# **Fractions kept from the default population.** The PV/non-PV split and the
# elastic/inelastic proportions are the default population's OWN — continuity
# with the validated rescaled proxy is the whole calibration principle, and
# nothing about this population is re-tuned.
#
# **Thesis reference totals, stated as context only.** The thesis's Case A
# specification targets PV = 5 MWp, elastic = 6.5 MW and inelastic = 1.5 MW.
# Those totals are recorded here as PROVENANCE CONTEXT, not as a target: this
# construction deliberately does NOT chase absolute thesis megawatts. What it
# preserves is the validated per-bus solve regime at the true house count.
# Matching the thesis magnitudes is an ablation-study concern for a later
# phase, and would be a measured, documented change of its own.

@printf(
    "IEEE-13 residential scales : load %.3g pu, pv %.3g pu, dev %.3g pu\n",
    _IEEE13_LOAD_SCALE,
    _IEEE13_PV_SCALE,
    _IEEE13_DEV_SCALE,
)
@printf("PV-fraction constant       : %.1f (all-PV; generic field, see above)\n",
    _CASE_A_PV_FRACTION,
)

# ## Composition — measured live from the built population
#
# Everything in the printout below is COMPUTED at build time from the
# deterministic construction; rebuilding the population reproduces every figure
# exactly. Units: the IEEE-13 fixture runs on a 100 MVA base, so a per-unit
# power `p` corresponds to `100·p` MW — both are shown. The inelastic figure
# sums each bus's Pdc PEAK (its own peak hour), not the all-bus simultaneous
# peak.

devices = reduce(vcat, (a.devices for a in aggs))
n_therm = count(d -> d isa Thermostatic, devices)
n_defer = count(d -> d isa Deferrable, devices)
n_batt = count(d -> d isa PVBattery, devices)
pv_nameplate_pu = sum(maximum(d.Ppv) for d in devices if d isa PVBattery)
therm_pmax_pu = sum(d.Pmax for d in devices if d isa Thermostatic)
defer_pmax_pu = sum(d.Pmax for d in devices if d isa Deferrable)
batt_pmax_pu = sum(d.Pmax for d in devices if d isa PVBattery)
batt_emax_pu = sum(d.Emax for d in devices if d isa PVBattery)
pdc_peak_pu = sum(maximum(a.Pdc) for a in aggs)

@printf("houses                  : %d\n", length(households))
@printf(
    "device mix              : %d Thermostatic, %d Deferrable, %d PVBattery\n",
    n_therm,
    n_defer,
    n_batt,
)
@printf(
    "total PV nameplate      : %.6g pu = %.6g MW  (Σ per-house peak of Ppv)\n",
    pv_nameplate_pu,
    100 * pv_nameplate_pu,
)
@printf(
    "inelastic load          : %.6g pu = %.6g MW  (Σ over buses of each bus's Pdc peak)\n",
    pdc_peak_pu,
    100 * pdc_peak_pu,
)
@printf(
    "elastic power bounds    : %.6g MW thermostatic + %.6g MW deferrable  (Σ Pmax)\n",
    100 * therm_pmax_pu,
    100 * defer_pmax_pu,
)
@printf(
    "battery fleet (storage) : %.6g MW power, %.6g MWh energy  (Σ Pmax, Σ Emax)\n",
    100 * batt_pmax_pu,
    100 * batt_emax_pu,
)

println("bus  houses  Pdc_peak_pu  Pdc_peak_MW")
for row in per_bus
    a = only(filter(x -> x.bus == row.bus, aggs))
    @printf(
        "%3d  %6d  %11.6g  %11.6g\n",
        row.bus,
        row.houses,
        maximum(a.Pdc),
        100 * maximum(a.Pdc),
    )
end

# ## Agreement — what is and is NOT established at the full population
#
# The protocol is gate-then-golden: run BOTH solve engines on the SAME built
# population FIRST, record the observed welfare and price deltas, and only then
# pin any test band derived from that measurement — never pre-loosened, never
# hand-picked. The band's home is the `:slow`-tagged test item in
# `test/test_population_case_a_agreement.jl`, deliberately excluded from the
# default CI lane so the fast suite stays fast.
#
# !!! note "This section reads committed data; nothing is solved at build time"
#     Regenerate the measurement row with:
#     ```
#     julia --project=. scripts/case_a_agreement.jl
#     ```
#     The script upserts its row — keyed on Julia version, seed and horizon — into
#     `results/case_a_population/agreement.csv`; re-runs replace their own row and
#     never drop others.
#
# The measured row, read here at build time:

## Read a committed measurement CSV with `Base` only — the docs environment pins a
## deliberately minimal dependency set (no CSV/DataFrames; the same convention as
## the Scaling to IEEE-8500 page's reader). These CSVs contain no quoted commas, so
## a plain per-line split is exact. An EMPTY cell is a deliberately-missing
## measured value and parses to NaN — never silently to zero.
function read_case_a_csv(path)
    lines = readlines(path)
    header = strip.(split(first(lines), ','))
    ncols = length(header)
    return map(lines[2:end]) do ln
        cells = split(ln, ','; limit = ncols)
        Dict(header[i] => strip(c) for (i, c) in enumerate(cells))
    end
end
num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
cell(s) = isempty(s) ? "-" : s

agreement = only(read_case_a_csv(
    joinpath(pkgdir(TSODSO), "results", "case_a_population", "agreement.csv"),
))

@printf("centralized leg  optimizer path : %s\n",
    cell(agreement["centralized_optimizer"]),
)
@printf("centralized leg  welfare        : %s (certified)\n",
    cell(agreement["welfare_centralized"]),
)
@printf("decomposed leg   iterations     : %d\n",
    round(Int, num(agreement["admm_iters"])),
)
@printf("decomposed leg   status         : %s\n", cell(agreement["admm_status"]))
@printf(
    "welfare deltas   abs / rel      : %s / %s\n",
    cell(agreement["welfare_abs_delta"]),
    cell(agreement["welfare_rel_delta"]),
)
@printf(
    "price deltas     abs / rel      : %s / %s\n",
    cell(agreement["price_max_abs_delta"]),
    cell(agreement["price_max_rel_delta"]),
)
@printf("recommended test band           : %s\n",
    cell(agreement["recommended_rtol_welfare"]),
)

# The honest reading of that row: the centralized leg certifies only under the
# tightened solver-precision path the row itself names (`centralized_optimizer`)
# — the model's exactness gates are untouched; the SOLVER's own convergence
# precision is what was tightened, the established response to a gate refusal.
# The decomposed leg CONVERGES at the recorded iteration count but is then
# REFUSED by the battery-complementarity certificate at the final consolidation
# (`admm_status`). A refused leg yields no certified welfare and no certified
# prices — so at this configuration NO agreement delta is measurable and NO
# band constant can honestly be pinned. The test file above carries that
# missing pin as a loud, tracked skip citing this CSV and the regeneration
# command, so it cannot silently rot. The refusal itself is a recorded measured
# outcome — the same deterministic refusal the scaling section shows — and it
# is escalated for investigation, never tuned away.
#
# ## Scaling — measured, not assumed
#
# !!! note "These curves are precomputed, and deliberately so"
#     Every leg below costs hundreds of seconds of solve wall time per process — far
#     past any docs-build slice budget, and orders past the seconds this page's
#     build-only slice spends. The legs are therefore LOADED from committed data, not
#     solved on this page. Regenerate them with:
#     ```
#     scripts/run_case_a_scaling.sh                  # every leg (tens of minutes total)
#     scripts/run_case_a_scaling.sh --ladder-only    # the population ladder leg only
#     scripts/run_case_a_scaling.sh --sweep-only     # the threads-sweep legs only
#     ```
#
# **Population ladder.** Deterministic NESTED PREFIXES of the same seeded
# population: every rung's houses are a subset (by house index) of every larger
# rung's, drawn from the identical per-house seeds, solved with the identical
# solver configuration — no per-rung re-tuning, so the ladder measures ONE
# configuration's behavior as the population grows.

ladder = read_case_a_csv(
    joinpath(pkgdir(TSODSO), "results", "case_a_population", "scaling_ladder.csv"),
)

println("rung   fraction  houses  iters  status                  wall_s")
for r in ladder
    @printf(
        "%-6s %8.4g  %6d  %5d  %-22s %7.1f\n",
        r["rung_label"],
        num(r["fraction"]),
        round(Int, num(r["houses_actual"])),
        round(Int, num(r["iters"])),
        r["status"],
        num(r["wall_s"]),
    )
end

# The recorded shape: the iteration count is flat through the half-population
# rung and rises sharply at the three-quarter and full rungs — the
# heterogeneous-scale iteration growth this population was built to probe is
# real, and it lands between the last two rungs. The full-population rung
# CONVERGES at its recorded iteration count and is then refused by the same
# battery-complementarity certificate the agreement section reports — a
# recorded outcome, kept exactly as measured (the wall time is the solve's own).
#
# **Threads sweep.** One full-population solve per OS process: thread count is
# fixed at process start, so the sweep drives ONE `julia -t N` process per leg
# through the shell driver above, with the linear-algebra backend pinned to a
# single thread in every leg for row-to-row comparability and the executor
# actually used recorded per row.

sweep = read_case_a_csv(
    joinpath(pkgdir(TSODSO), "results", "case_a_population", "threads_sweep.csv"),
)
serial_wall = num(only(filter(r -> r["executor"] == "serial", sweep))["wall_s"])

println("threads  executor  iters  status                  wall_s    speedup")
for r in sweep
    w = num(r["wall_s"])
    @printf(
        "%7d  %-8s  %5d  %-22s %7.1f  %.2fx\n",
        round(Int, num(r["threads"])),
        r["executor"],
        round(Int, num(r["iters"])),
        r["status"],
        w,
        serial_wall / w,
    )
end

# The speedup column is COMPUTED from the measured walls against the serial
# leg — never assumed. The recorded outcome is a modest positive speedup,
# consistent with parallelism spanning only the ten bus subproblems while the
# solver's own linear-algebra backend stays single-threaded. A negative or null
# result would have been an equally valid, equally recorded outcome (the
# project's honesty policy pre-authorizes it); what is reported is what was
# measured. Every leg's status column shows the SAME deterministic certificate
# refusal at the full population — the recorded state, not a smoothed one.
#
# ## Thesis parameters that are NOT available — and the rule that replaced each
#
# The thesis specifies its Case A population's fine structure in an appendix
# (its Appendix E) that is not public. Building a population at this size
# without it required an explicit, deterministic replacement for each
# unavailable parameter — each stated here, so the construction reads as
# calibration provenance rather than hidden re-tuning:
#
# | Unavailable thesis parameter (Appendix E) | Rule that replaces it here |
# |---|---|
# | Per-house appliance ownership | The device set is FIXED for every house: one Thermostatic, one Deferrable, one PVBattery — the default population's three-device house shape. No ownership heterogeneity is claimed. |
# | Per-house PV sizing | The PV/non-PV split keeps the default population's fraction, which is all-PV: every house carries a PV-battery at the divided-by-house-count scale (the `_CASE_A_PV_FRACTION = 1.0` triviality, stated honestly above). |
# | Per-node house counts | Counts are proportional to the default population's per-bus counts (uniform on this feeder, hence equal shares), with the residue assigned +1 per bus to the first buses in ascending bus-id order — the documented tiebreak. |
#
# Each replacement is deterministic, test-enforced, and exposed row by row
# through `TSODSO.case_a_household_map`, so any reader can audit the resulting
# assignment without constructing anything.
#
# ## Reproducing every number on this page
#
# ```
# # the scaling measurements — ladder + threads sweep (tens of minutes total)
# scripts/run_case_a_scaling.sh
# # ... or leg by leg, one julia process per thread count:
# julia --project=. -t 1 scripts/case_a_scaling.jl --mode ladder
# julia --project=. -t 4 scripts/case_a_scaling.jl --mode threads-sweep --threads 4
# # the agreement measurement — both engines at the full population
# julia --project=. scripts/case_a_agreement.jl
# # the agreement test — slow lane only; the default CI lane stays fast
# TSODSO_TEST_SET=slow julia --project=. -e 'import Pkg; Pkg.test()'
# ```
#
# Each script upserts its own rows into `results/case_a_population/*.csv`,
# keyed on provenance (Julia version, seed, horizon, thread count, rung) —
# re-runs replace their own rows and never drop others.
#
# *(Appended 2026-10-24. Every figure on this page names its source. The
# composition figures are computed live at docs-build time from the
# deterministic construction — seed 42, horizon 24 — and are therefore exact.
# The agreement figures are read from `results/case_a_population/agreement.csv`,
# the single row keyed `julia_version=1.12.5, seed=42, t_horizon=24`. The
# ladder figures come from `results/case_a_population/scaling_ladder.csv`, rows
# `rung1` through `rung6`. The threads figures come from
# `results/case_a_population/threads_sweep.csv`, one row each at 1, 2 and 4
# threads. The population itself is `TSODSO.build_population(:case_a_784, ...)`;
# the household-level assignment is `TSODSO.case_a_household_map`. This page
# delivers the phase requirement POP-06: composition with calibration
# provenance and the Appendix-E unavailability list.)*
