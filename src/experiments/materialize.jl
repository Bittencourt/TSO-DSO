# src/experiments/materialize.jl
#
# SEAM: deterministic selector → object materialization.
#
# Deterministically reconstructs the heavy objects (feeder, λ₀, aggregators) from
# a `Scenario`'s primitive selectors + its master `seed`, reusing `ieee13_modified` /
# `ieee123_modified` / `generate_profiles` / `Aggregator` verbatim — this is orchestration,
# NO new model, NO solver named anywhere. `sub_seed` derives INDEPENDENT
# deterministic sub-streams from the master seed so `:profiles` and
# `:population` never accidentally couple or collide; every stochastic draw flows through a
# freshly-seeded `generate_profiles` call (itself backed by a `StableRNGs.LehmerRNG`), NEVER
# the global RNG / `Random.seed!`. Kept dependency-light (no DrWatson) so scenario materialization is testable
# without the storage layer.

"""
    sub_seed(master::Integer, tag::Symbol) -> Int

Derive an INDEPENDENT deterministic sub-seed from a `Scenario`'s master `seed` and a stream
tag (e.g. `:profiles`, `:population`). Two different tags on the SAME
master produce DIFFERENT sub-seeds (independent, non-colliding sub-streams); the SAME
`(master, tag)` pair always produces the SAME sub-seed (deterministic). Never
touches the global RNG: this is a pure `hash` derivation, not a draw.
"""
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))

"""
    build_feeder(sym::Symbol) -> Feeder{Float64}

Materialize the feeder named by `sym`: `:ieee13` → [`ieee13_modified`](@ref), `:ieee123` →
[`ieee123_modified`](@ref), `:ieee8500` → [`ieee8500_modified`](@ref) (headline
full MV+LV), `:ieee8500_mv` → [`ieee8500_mv_modified`](@ref) (MV-only control,
a SEPARATE builder, not an `mv_only=true` keyword argument). Throws `ArgumentError`
on any other selector (a `Scenario`'s own constructor already guards this, but `build_feeder` guards again as a seam that may be called directly).
"""
function build_feeder(sym::Symbol)
    if sym === :ieee13
        return ieee13_modified()
    elseif sym === :ieee123
        return ieee123_modified()
    elseif sym === :ieee8500
        return ieee8500_modified()
    elseif sym === :ieee8500_mv
        return ieee8500_mv_modified()
    else
        throw(
            ArgumentError(
                "build_feeder: unknown feeder selector $(repr(sym)); expected :ieee13, " *
                ":ieee123, :ieee8500, or :ieee8500_mv",
            ),
        )
    end
end

# --- :mem price shape ---
#
# The pinned 24-hour MEM / wholesale price `λ₀` (¢$/kWh-consistent) — the SAME digitized
# shape as `test/fixtures_ieee13.jl` `mem_price_profile()` / `test/fixtures_ieee123.jl`
# `ieee123_lambda0()` (overnight trough → morning ramp → evening peak). Duplicated here
# (rather than `using` the test fixture module) because `src/` must never depend on `test/`;
# this is the SOURCE OF TRUTH the fixtures were originally digitized from. Positive and well
# within `PerUnit.PRICE_MAX`.
const _MEM_PRICE_PROFILE_24H = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,   # 00–05 overnight trough
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,   # 06–11 morning ramp → midday shoulder
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,   # 12–17 afternoon rise → evening peak
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,   # 18–23 evening decline
]

"""
    build_price(sym::Symbol, T::Int, profiles) -> Vector{Float64}

Materialize a length-`T` price vector `λ₀` named by `sym`. `:mem` returns the pinned MEM
shape (`_MEM_PRICE_PROFILE_24H`), cyclically repeated/truncated to length `T` when `T ≠ 24`
(deterministic, no randomness). `profiles` is accepted for API symmetry with
[`build_population`](@ref) (a future price selector may derive `λ₀` from the profile draw)
but is unused by `:mem`. Throws `ArgumentError` on any other selector.
"""
function build_price(sym::Symbol, T::Int, profiles)
    if sym === :mem
        base = _MEM_PRICE_PROFILE_24H
        return Float64[base[mod1(t, length(base))] for t in 1:T]
    else
        throw(
            ArgumentError(
                "build_price: unknown price selector $(repr(sym)); expected :mem",
            ),
        )
    end
end

# --- :default population shape ---
#
# Reuses the fixtures_ieee13/7 `_house_aggregator` residential-magnitude SHAPE (Thermostatic +
# Deferrable + PVBattery, seeded per-bus `generate_profiles`) but is not itself allowed to
# `using` a test fixture module, so the construction is duplicated here as the canonical
# `src/`-side implementation. The two feeder-scale calibrations (ieee13 @ 100 MVA base /
# ieee123 @ 1 MVA base) need DIFFERENT residential magnitude scales to stay in a sane,
# congestion/voltage-relevant regime on their own per-unit base; `_default_house` is
# feeder-scale-agnostic and takes the scale triple as arguments.

const _DEFAULT_BATT_λ_MIN = 3.8
const _DEFAULT_BATT_λ_MED = 6.2
const _DEFAULT_BATT_λ_MAX = 8.9

# ieee13 (100 MVA base) residential scale — mirrors fixtures_ieee13 GROUND_LOAD_SCALE/GROUND_PV_SCALE.
const _IEEE13_LOAD_SCALE = 0.005
const _IEEE13_PV_SCALE = 0.03
const _IEEE13_DEV_SCALE = 1.0

# ieee123 (1 MVA feeder-scale base) residential scale — mirrors fixtures_ieee123
# LOAD_SCALE_IEEE123/PV_SCALE_IEEE123/DEV_SCALE_IEEE123.
const _IEEE123_LOAD_SCALE = 0.03
const _IEEE123_PV_SCALE = 0.06
const _IEEE123_DEV_SCALE = 0.05

# :case_a_784 population calibration — the thesis Case A size and its PV-ownership split.
# `_CASE_A_PV_FRACTION = 1.0` is the honest reading of the locked "keep the `:default`
# fractions" decision (`:default` is 100%-PV: every house carries a `PVBattery`); the
# fraction is a named constant so a later phase can lower it without redesign.
const _CASE_A_TOTAL_HOUSES = 784
const _CASE_A_PV_FRACTION = 1.0

# The 24-hour exterior-temperature profile (°C) feeding the thermostatic ambient `Tout`, the
# SAME digitized shape as the earlier fixtures (thesis Fig 4.2). Cyclically repeated to any
# horizon `T` (see `_temperature_profile`), matching the `_MEM_PRICE_PROFILE_24H` convention.
const _TEMPERATURE_PROFILE_24H = Float64[
    19,
    18,
    17,
    16,
    16,
    17,   # 00–05 cooling to a dawn minimum
    19,
    21,
    23,
    26,
    28,
    30,   # 06–11 morning warm-up
    31,
    32,
    32,
    31,
    29,
    27,   # 12–17 afternoon peak → decline
    25,
    23,
    22,
    21,
    20,
    19,   # 18–23 evening cool-down
]

"""
`_temperature_profile(T) -> Vector{Float64}` — the pinned ambient shape, cycled to length `T`.
"""
_temperature_profile(T::Int) = Float64[_TEMPERATURE_PROFILE_24H[mod1(t, 24)] for t in 1:T]

"""
    _load_buses(feeder, feeder_sym::Symbol) -> Vector{Int}

The (struct-index) load buses of `feeder` (topology-only): the modified IEEE-123 fixture has a
documented load/transit split (`ieee123_load_nodes`, 85 spot-load buses vs. ~37 zero-injection
transit junctions handled by the DSO-OPT relaxation), so that split is used when
`feeder_sym === :ieee123`; otherwise (`:ieee13` and any other radial fixture) every non-root
bus is a load bus, mirroring `fixtures_ieee13.build_ieee13_aggregators`.

Dispatches on the ALREADY-KNOWN, already-validated `Scenario.feeder::Symbol`
selector rather than re-deriving "is this ieee123" from `length(feeder.buses)` — the previous
bus-count heuristic would silently mis-scale for any future feeder fixture that happens to
share IEEE-123's bus count (no `ArgumentError`, no warning, just a quietly wrong load/transit
split).
"""
function _load_buses(feeder, feeder_sym::Symbol)
    if feeder_sym === :ieee123
        return ieee123_load_nodes()
    elseif feeder_sym === :ieee8500
        return ieee8500_load_nodes()
    elseif feeder_sym === :ieee8500_mv
        return ieee8500_mv_load_buses()
    end
    return [b.id for b in feeder.buses if !b.is_root]
end

"""
    _default_house(bus, profiles, seed, T; φ, load_scale, pv_scale, dev_scale,
                   batt_pmax, batt_emax, batt_soc0) -> Aggregator

Build one seeded residential `Aggregator` at `bus` (Thermostatic + Deferrable + PVBattery),
mirroring the `fixtures_ieee13`/`fixtures_ieee123` `_house_aggregator` construction SHAPE.
`profiles` is accepted for signature symmetry with [`build_population`](@ref) but each house
draws its OWN per-bus profile via `generate_profiles(seed = seed + bus, T)` — the SAME
per-bus-seeded idiom the fixtures use — so no two houses share a profile draw and the whole
population is deterministic in `seed` (a global-RNG leak would break this;
`generate_profiles` itself threads a fresh `StableRNGs.LehmerRNG`, never `Random.seed!`).
"""
function _default_house(
    bus::Int,
    profiles,
    seed::Integer,
    T::Int;
    φ::Real,
    load_scale::Real,
    pv_scale::Real,
    dev_scale::Real,
    batt_pmax::Real,
    batt_emax::Real,
    batt_soc0::Real,
)
    prof = generate_profiles(; seed = seed + bus, T = T)   # per-bus, deterministic in `seed`
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]

    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0 * dev_scale,
        0.5,
        _temperature_profile(T),
    )
    defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        batt_pmax,
        0.0,
        batt_emax,
        batt_soc0,
        _DEFAULT_BATT_λ_MIN,
        _DEFAULT_BATT_λ_MED,
        _DEFAULT_BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

"""
    _ieee8500_house(bus, kw_pu, profiles, seed, T) -> Aggregator

A per-bus-REAL-MAGNITUDE sibling of [`_default_house`](@ref) for the IEEE-8500 fixtures,
a genuinely NEW code path, NOT a parameterized modification of `_default_house`.
`kw_pu::Float64` is the bus's OWN real per-load kW, ALREADY converted
to per-unit power (`to_pu_power`) by the caller — it takes the place of
`_default_house`'s tuned `load_scale * d` scalar multiply: `Pdc = kw_pu * d` for each
seeded demand-profile sample `d` (the seeded profile SHAPE still modulates the fixed real
magnitude; only the magnitude source differs from `_default_house`).

The device-construction body below is copied VERBATIM from `_default_house` (same
`Thermostatic`/`Deferrable`/`PVBattery` calls, same `_DEFAULT_BATT_λ_*` constants:
the 3-device house stays fixed, no device-count axis is introduced alongside the density
sweep), with `dev_scale = 1.0` FIXED inline (no tuned
`_IEEE8500_DEV_SCALE`-style constant for this fixture, unlike the `_IEEE13_*`/`_IEEE123_*`
scale triples `_default_house` takes as arguments).
"""
function _ieee8500_house(bus::Int, kw_pu::Float64, profiles, seed::Integer, T::Int)
    prof = generate_profiles(; seed = seed + bus, T = T)   # per-bus, deterministic in `seed`
    dev_scale = 1.0   # no tuned _IEEE8500_DEV_SCALE constant for this fixture
    Ppv = Float64[kw_pu * p for p in prof.pv]
    Pdc = Float64[kw_pu * d for d in prof.demand]

    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0 * dev_scale,
        0.5,
        _temperature_profile(T),
    )
    defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        0.5 * kw_pu,
        0.0,
        2.0 * kw_pu,
        1.0 * kw_pu,
        _DEFAULT_BATT_λ_MIN,
        _DEFAULT_BATT_λ_MED,
        _DEFAULT_BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, 0.90, [therm, defer, batt], Pdc)
end

"""
    _case_a_house_counts(buses::Vector{Int}, total::Int) -> Dict{Int,Int}

Distribute `total` houses over `buses` per the locked Phase-40 rule: every bus gets the base
share `total ÷ length(buses)`, and the residue `total % length(buses)` is assigned +1 per bus
to the first `r` buses in ascending bus-id order. The locked decision's "largest buses first"
language specializes to ascending bus id here because the `:default` population has exactly
one house per bus (uniform per-bus counts carry no size signal) — this is the A4 tiebreak
definition. For the IEEE-13 load buses `[2..11]` and `total = 784`: buses 2, 3, 4, 5 get 79
houses and buses 6-11 get 78.

Throws `ArgumentError` when `buses` is empty or `total < length(buses)` (a bus with zero
houses would build an empty, `Aggregator`-illegal roll-up).
"""
function _case_a_house_counts(buses::Vector{Int}, total::Int)
    isempty(buses) &&
        throw(ArgumentError("_case_a_house_counts: buses must be non-empty; got none"))
    total < length(buses) && throw(
        ArgumentError(
            "_case_a_house_counts: total ($total) must be >= length(buses) " *
            "($(length(buses))); every bus needs at least one house",
        ),
    )
    ordered = sort(buses)   # residue rule: ascending bus-id order, independent of input order
    base = total ÷ length(ordered)
    r = total % length(ordered)
    counts = Dict{Int, Int}(bus => base for bus in ordered)
    for bus in ordered[1:r]
        counts[bus] += 1
    end
    return counts
end

"""
    _case_a_rung_counts(full_counts::Dict{Int,Int}, fraction::Real) -> Dict{Int,Int}

The per-bus house counts of one nested-prefix population-ladder rung: for every bus `b`,
the rung keeps the prefix length `m_b = fraction >= 1 ? full_counts[b] : max(1, floor(Int, fraction * full_counts[b]))` — the first `m_b` houses of that bus, in the
same house-index order the builder uses.

# Ladder contract (locked Phase-40 decision)

Ladder rungs are NESTED PREFIXES of the SAME seeded population: a rung's houses are a
subset (by house index) of every larger rung's, drawn from the identical per-house seeds —
NO re-tuning per rung (the same solver configuration runs at every rung, so the ladder
measures the iteration/wall-time behavior of ONE configuration as the population grows).
`fraction = 1.0` is EXACTLY the full population (the prefix is the whole per-bus house
list, and the roll-up must match `build_population(:case_a_784, ...)` — callers assert
that consistency). The `max(1, ...)` floor keeps every bus populated at every fraction
(an empty bus would build an empty, `Aggregator`-illegal roll-up).

Throws `ArgumentError` when `fraction <= 0` or `full_counts` is empty.
"""
function _case_a_rung_counts(full_counts::Dict{Int, Int}, fraction::Real)
    isempty(full_counts) &&
        throw(ArgumentError("_case_a_rung_counts: full_counts must be non-empty; got none"))
    fraction > 0 || throw(
        ArgumentError(
            "_case_a_rung_counts: fraction must be > 0 (got $(repr(fraction))); " *
            "rungs are nested prefixes, so a non-positive fraction selects nothing",
        ),
    )
    return Dict{Int, Int}(
        bus => (fraction >= 1 ? n : max(1, floor(Int, fraction * n))) for
        (bus, n) in full_counts
    )
end

"""
    _case_a_house_seed(s_pop::Integer, bus::Int, house_index::Int) -> Int

The per-house profile seed of the `:case_a_784` population: exactly
`Int(hash((s_pop, :house, bus, house_index)) % typemax(UInt32))` — the [`sub_seed`](@ref)
hash idiom extended with a richer tuple (locked Phase-40 decision). `s_pop` is
`build_population`'s `seed` argument, already the population sub-seed (call sites pass
`sub_seed(scenario_seed, :population)`); the per-house tuple takes it directly, mirroring how
`:default` derives its per-bus draws from the same sub-seed.

Per-HOUSE, never per-bus: the `seed + bus` idiom `_default_house` uses would give every house
on a bus the SAME profile draw, silently collapsing the population to 10 distinct houses.
Collision-freeness across the 784 `(bus, house_index)` pairs is an EMPIRICAL property (hash
independence of distinct tuples), enforced by test (`test_population_case_a.jl` asserts a
784-element seed set).
"""
_case_a_house_seed(s_pop::Integer, bus::Int, house_index::Int) =
    Int(hash((s_pop, :house, bus, house_index)) % typemax(UInt32))

"""
    _case_a_pv_group(house_index::Int, n_bus::Int, pv_fraction::Real) -> Symbol

The house's PV-ownership group within its bus: `:pv` when
`house_index <= ceil(pv_fraction * n_bus)`, else `:non_pv`. A GENERIC field (A2 resolution):
at the named constant `_CASE_A_PV_FRACTION = 1.0` every house is `:pv` — the honest reading
of the locked "keep the `:default` fractions" decision, since `:default` is 100%-PV (every
house carries a `PVBattery`). Lowering the constant later (Phase-41 settlement groups) needs
no redesign: the field is generic and the fixed 3-device house construction is unchanged.
"""
function _case_a_pv_group(house_index::Int, n_bus::Int, pv_fraction::Real)
    return house_index <= ceil(pv_fraction * n_bus) ? :pv : :non_pv
end

"""
    _case_a_house(bus::Int, house_index::Int, n_bus::Int, s_pop::Integer, T::Int;
                  load_scale, pv_scale, dev_scale, pv_fraction) -> Aggregator

One per-house-seeded residential `Aggregator` of the `:case_a_784` population — a genuinely
NEW code path (the [`_ieee8500_house`](@ref) precedent), NOT a parameterized modification of
[`_default_house`](@ref). The device-construction body is copied VERBATIM from
`_default_house` (same `Thermostatic`/`Deferrable`/`PVBattery` calls, same
`_DEFAULT_BATT_λ_*` constants, φ = 0.90) with exactly two changes:

 1. The profile draw is PER-HOUSE: its seed is `_case_a_house_seed(s_pop, bus, house_index)`
    fed to `generate_profiles` — never the `seed + bus` per-bus idiom, under which every house
    on a bus would receive an IDENTICAL draw.
 2. The per-house magnitude scales are DIVIDED by the bus's house count: `hs = load_scale / n_bus`, `ps = pv_scale / n_bus`, `ds = dev_scale / n_bus`, used everywhere the `:default`
    path uses the raw scales. RATIONALE (calibration provenance): dividing by houses-per-bus
    preserves each bus's aggregate load/PV at the validated `:default` level, keeping both
    solve engines in the known-good congestion/voltage regime; raw per-house scales would put
    roughly 78x the calibrated load through the 6.86 MVA head branch and be near-certainly
    infeasible.

`pv_fraction` is accepted for symmetry with `case_a_household_map` and is NOT used by this
construction: every house carries the fixed 3-device set (the PV group lives in
`_case_a_pv_group` / the household map, per the A2 generic-field resolution).
"""
function _case_a_house(
    bus::Int,
    house_index::Int,
    n_bus::Int,
    s_pop::Integer,
    T::Int;
    load_scale::Real,
    pv_scale::Real,
    dev_scale::Real,
    pv_fraction::Real,
)
    hs = load_scale / n_bus
    ps = pv_scale / n_bus
    ds = dev_scale / n_bus
    prof = generate_profiles(; seed = _case_a_house_seed(s_pop, bus, house_index), T = T)
    Ppv = Float64[ps * p for p in prof.pv]
    Pdc = Float64[hs * d for d in prof.demand]

    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0 * ds,
        0.5,
        _temperature_profile(T),
    )
    defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * ds, 0.5 * ds, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        0.5 * hs,
        0.0,
        2.0 * hs,
        1.0 * hs,
        _DEFAULT_BATT_λ_MIN,
        _DEFAULT_BATT_λ_MED,
        _DEFAULT_BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, 0.90, [therm, defer, batt], Pdc)
end

# ---------------------------------------------------------------------------------------------
# `flex_devices` opt-in (Phase 43 plan 05, DEV-06): seeded EV / HeatPump / SmartInverterPV
# attached per house. A KWARG of `build_population` (default `nothing` = no-op), never a new
# `Scenario` population selector, so `SCENARIO_VALID_POPULATIONS`, `:default` and `:case_a_784`
# stay byte-identical.
#
# CALIBRATION CAVEAT — LOW CONFIDENCE (research assumption A6). The EV session distribution
# below is a plausible, documented stand-in, NOT an empirical fit. Shape is informed by public
# residential-charging studies: ACN-Data (Lee, Li & Low, "ACN-Data: Analysis and Applications of
# an Open EV Charging Dataset", ACM e-Energy 2019) and the US National Household Travel Survey
# 2017 (NHTS; FHWA) home-arrival / trip-energy statistics. Recalibration against those datasets
# is explicitly DEFERRED by locked decision; do not cite these constants as measured.
# HeatPump 2R2C constants are literature-plausible illustrative values (Kircher / Bacher-Madsen
# RC lineage, MEDIUM bibliographic confidence), also not a calibration.
# ---------------------------------------------------------------------------------------------
const _FLEX_VALID = (:ev, :heatpump, :smartinverterpv)

# EV session: arrival hour ~ truncated Normal(18.5, 2.0) on [15, 22]; departure hour
# ~ truncated Normal(7.5, 1.5) on [5, 10] (morning, so evening sessions WRAP the horizon edge;
# NOTE the EV model's wrap semantics: only hours 1..t_dep count toward the departure target and
# `soc0` is the SOC at hour 1 — see the ElectricVehicle.jl header, review WR-01);
# energy need fraction of the pack ~ LogNormal(log(0.30), 0.40) capped at 0.60; arrival SOC
# fraction ~ Uniform(0.15, 0.40). Hours are on a 24 h clock, mapped onto `1:T`.
const _EV_ARR_MU, _EV_ARR_SD, _EV_ARR_LO, _EV_ARR_HI = 18.5, 2.0, 15.0, 22.0
const _EV_DEP_MU, _EV_DEP_SD, _EV_DEP_LO, _EV_DEP_HI = 7.5, 1.5, 5.0, 10.0
const _EV_ENERGY_MEDIAN, _EV_ENERGY_SIGMA, _EV_ENERGY_CAP = 0.30, 0.40, 0.60
const _EV_SOC0_LO, _EV_SOC0_HI = 0.15, 0.40
# Pack / charger sizing as multiples of the house load scale `scale` (same convention as the
# `PVBattery` sizing `0.5·hs` / `2·hs`): Pmax = 1·scale, Emax = 8·scale.
const _EV_PMAX_FACTOR, _EV_EMAX_FACTOR = 1.0, 8.0
const _EV_η, _EV_κ = 0.95, 10.0

# HeatPump 2R2C (heating season): coupling fractions, comfort band 19-23 degC, envelope band
# 5-35 degC, Tin0 ~ 21 + Uniform(-1, 1), ambient 5 + 4 sin(2π(t-9)/24) degC, COP
# = clamp(3 + 0.05(Tout-5), 2, 4.5), gain β = 1/scale (degC per pu-hour of heat), Pmax = 0.8·scale.
const _HP_COEF = (aie = 0.10, aia = 0.05, ame = 0.05, ama = 0.02)
const _HP_BAND = (Tmin = 19.0, Tmax = 23.0, Tem_min = 5.0, Tem_max = 35.0)
const _HP_PMAX_FACTOR, _HP_B_FACTOR = 0.8, 10.0

# SmartInverterPV: own panel = 0.5 × the house PV availability; S_inv = 1.1 × its peak.
const _SIPV_PV_SHARE, _SIPV_OVERSIZE = 0.5, 1.1

"""
    _flex_selectors(x) -> Vector{Symbol}

Normalize and validate a `flex_devices` selector (`nothing`, a Symbol, or a collection of
Symbols among `(:ev, :heatpump, :smartinverterpv)`). Throws `ArgumentError` on anything else
(never silently shrinks the population).
"""
function _flex_selectors(x)
    x === nothing && return Symbol[]
    xs = x isa Symbol ? Symbol[x] : collect(x)
    for s in xs
        if !(s isa Symbol && s in _FLEX_VALID)
            throw(
                ArgumentError(
                    "build_population: unknown flex_devices selector $(repr(s)); " *
                    "expected one of $(_FLEX_VALID) (or a collection of them)",
                ),
            )
        end
    end
    return unique(xs)
end

# Portable seed mix for the phase-43 `_flex_*` helpers (WR-02). `Base.hash` makes no
# cross-Julia-version guarantee (its algorithm changed in 1.12), so the new flex draws never
# touch it: fold integer-coded tags through the SplitMix64 finalizer (fixed constants, pure
# UInt64 arithmetic => identical on every Julia version / platform). `_case_a_house_seed` and
# `sub_seed` are golden-pinned and deliberately still hash-based (known follow-up).
function _flex_mix(vals::Integer...)
    h = 0x9e3779b97f4a7c15 % UInt64
    for v in vals
        z = (h + (v % UInt64) + 0x9e3779b97f4a7c15) % UInt64
        z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
        z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
        h = z ⊻ (z >> 31)
    end
    return Int(h % UInt64(typemax(UInt32)))
end
# Integer tag codes (never hash a Symbol).
const _FLEX_TAG_EV = 1
const _FLEX_TAG_HP = 2
const _FLEX_SUB_ARR = 11
const _FLEX_SUB_DEP = 12
const _FLEX_SUB_ENERGY = 13
const _FLEX_SUB_SOC0 = 14
const _FLEX_SUB_TIN0 = 15

# Truncated normal by rejection (own tagged StableRNG stream; never the global RNG).
function _flex_trunc_normal(seed::Integer, μ::Real, sd::Real, lo::Real, hi::Real)
    rng = StableRNGs.LehmerRNG(seed)
    for _ in 1:1000
        x = μ + sd * randn(rng)
        lo <= x <= hi && return x
    end
    return clamp(μ, lo, hi)
end

_flex_uniform(seed::Integer, lo::Real, hi::Real) =
    lo + (hi - lo) * rand(StableRNGs.LehmerRNG(seed))

"""
    _flex_ev(s_pop, bus, house_index, T; scale) -> ElectricVehicle

One seeded EV session. Seed `_flex_mix(s_pop, _FLEX_TAG_EV, bus, house_index)` (per-HOUSE,
never per-bus; a portable SplitMix64 mix, not `Base.hash`), then tag-split sub-seeds
`_flex_mix(ev_seed, _FLEX_SUB_ARR|DEP|ENERGY|SOC0)` so the four draws are independent.
"""
function _flex_ev(s_pop::Integer, bus::Int, house_index::Int, T::Int; scale::Real)
    T >= 2 || throw(ArgumentError("flex EV: horizon T must be >= 2; got T=$T"))
    ev_seed = _flex_mix(s_pop, _FLEX_TAG_EV, bus, house_index)
    sub(tag) = _flex_mix(ev_seed, tag)
    hour_to_t(h) = clamp(round(Int, h * T / 24), 1, T)

    t_arr = hour_to_t(
        _flex_trunc_normal(sub(_FLEX_SUB_ARR), _EV_ARR_MU, _EV_ARR_SD, _EV_ARR_LO, _EV_ARR_HI),
    )
    t_dep = hour_to_t(
        _flex_trunc_normal(sub(_FLEX_SUB_DEP), _EV_DEP_MU, _EV_DEP_SD, _EV_DEP_LO, _EV_DEP_HI),
    )
    if t_dep == t_arr   # degenerate (tiny T): shift departure by one slot
        t_dep = mod1(t_arr + 1, T)
    end
    frac = min(
        _EV_ENERGY_CAP,
        _EV_ENERGY_MEDIAN *
        exp(_EV_ENERGY_SIGMA * randn(StableRNGs.LehmerRNG(sub(_FLEX_SUB_ENERGY)))),
    )
    Emax = _EV_EMAX_FACTOR * scale
    soc0 = _flex_uniform(sub(_FLEX_SUB_SOC0), _EV_SOC0_LO, _EV_SOC0_HI) * Emax
    E_target = min(Emax, soc0 + frac * Emax)
    return ElectricVehicle(
        bus,
        _EV_η,
        1.0,
        _EV_PMAX_FACTOR * scale,
        0.0,
        Emax,
        soc0,
        E_target,
        _EV_κ,
        _DEFAULT_BATT_λ_MIN,
        _DEFAULT_BATT_λ_MED,
        _DEFAULT_BATT_λ_MAX,
        t_arr,
        t_dep,
    )
end

function _flex_heatpump(s_pop::Integer, bus::Int, house_index::Int, T::Int; scale::Real)
    hp_seed = _flex_mix(s_pop, _FLEX_TAG_HP, bus, house_index)
    Tin0 = 21.0 + _flex_uniform(_flex_mix(hp_seed, _FLEX_SUB_TIN0), -1.0, 1.0)
    Tout = Float64[5.0 + 4.0 * sin(2π * (t - 9) / 24) for t in 1:T]
    COP = Float64[clamp(3.0 + 0.05 * (x - 5.0), 2.0, 4.5) for x in Tout]
    return HeatPump(
        bus,
        _HP_COEF.aie,
        _HP_COEF.aia,
        _HP_COEF.ame,
        _HP_COEF.ama,
        1.0 / scale,
        _HP_BAND.Tmin,
        _HP_BAND.Tmax,
        _HP_BAND.Tem_min,
        _HP_BAND.Tem_max,
        Tin0,
        20.0,
        _HP_PMAX_FACTOR * scale,
        _HP_B_FACTOR * scale,
        Tout,
        COP,
    )
end

function _flex_smartinverterpv(bus::Int, T::Int, scale::Real, ppv)
    Ppv = ppv === nothing ? zeros(T) : Float64[_SIPV_PV_SHARE * p for p in ppv]
    peak = maximum(Ppv)
    S_inv = peak > 0 ? _SIPV_OVERSIZE * peak : 0.1 * scale
    return SmartInverterPV(bus, S_inv, Ppv)
end

"""
    _flex_devices_for_house(s_pop, bus, house_index, which, T; scale, ppv = nothing)
        -> Vector{AbstractDevice}

The extra flexible devices of one house for the selectors in `which` (see
[`_flex_selectors`](@ref)). `scale` is the house load scale (peak inelastic demand, per-unit);
`ppv` the house PV availability vector (used by `:smartinverterpv`). Per-house seeded.
"""
function _flex_devices_for_house(
    s_pop::Integer,
    bus::Int,
    house_index::Int,
    which,
    T::Int;
    scale::Real,
    ppv = nothing,
)
    sel = _flex_selectors(which)
    out = AbstractDevice[]
    :ev in sel && push!(out, _flex_ev(s_pop, bus, house_index, T; scale = scale))
    :heatpump in sel &&
        push!(out, _flex_heatpump(s_pop, bus, house_index, T; scale = scale))
    :smartinverterpv in sel && push!(out, _flex_smartinverterpv(bus, T, scale, ppv))
    return out
end

# Append the flex devices of one house to an Aggregator's own device list (Pdc untouched).
function _with_flex(a::Aggregator, s_pop::Integer, house_index::Int, sel, T::Int)
    pv = nothing
    for d in a.devices
        if d isa PVBattery
            pv = d.Ppv
            break
        end
    end
    scale = maximum(a.Pdc)
    scale > 0 || return a
    extra =
        _flex_devices_for_house(s_pop, a.bus, house_index, sel, T; scale = scale, ppv = pv)
    return Aggregator(a.bus, a.φ, AbstractDevice[a.devices...; extra...], a.Pdc)
end

"""
    build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer;
                     flex_devices = nothing) -> Vector{<:Aggregator}

Materialize the aggregator population named by `sym`. `:default` returns one seeded
residential `Aggregator` per real load bus of `feeder` ([`_load_buses`](@ref)), rescaled to
the feeder's own per-unit base (`_IEEE13_*`/`_IEEE123_*` residential scales, selected by
`feeder_sym`). `T` is read from `length(profiles.demand)` (the caller's own
`generate_profiles(; T = s.T)` draw), so this stays consistent with the Scenario's horizon
without taking `T` as a separate argument. Deterministic in `seed`: two calls with the SAME
`seed` return structurally identical aggregators (same per-bus profile draws); a DIFFERENT seed
changes every house. Throws `ArgumentError` on any other selector.

`feeder_sym` (the caller's already-validated `Scenario.feeder` selector) now
disambiguates the IEEE-13 vs IEEE-123 residential scale directly, instead of re-deriving it
from `length(feeder.buses) == length(ieee123_relabel_map())` — a structural coincidence that a
future feeder fixture sharing IEEE-123's bus count would silently, wrongly match.

# `flex_devices` opt-in (Phase 43)

`flex_devices = nothing` (default) is a strict no-op: every existing call site and the
`:default` / `:case_a_784` populations are byte-identical (the `Scenario` schema is untouched —
opt-in is a kwarg, not a population selector). Otherwise a Symbol or collection among
`(:ev, :heatpump, :smartinverterpv)` appends per-HOUSE seeded flexible devices (one per
`:case_a_784` house, one per `:default` bus aggregator); unknown selectors throw `ArgumentError`.
EV session distributions are documented LOW-CONFIDENCE calibration (see the constants block
above `_flex_selectors`). LIMITATION: flex populations are supported by the day-ahead
centralized / ADMM paths only. `fit_baseline` / `compare_tariffs` and `run_mpc` have no
model for `ElectricVehicle` / `HeatPump` / `SmartInverterPV` and throw an explicit
`ArgumentError` naming them (the `Scenario` schema cannot carry `flex_devices` anyway).

# IEEE-8500 real-per-load-kW path

For `feeder_sym in (:ieee8500, :ieee8500_mv)`, the `:ieee13`/`:ieee123` tuned-scalar path
above is BYPASSED entirely (this branch never runs for those two selectors — the
`:ieee13`/`:ieee123` branch is left completely untouched, must-not-break): each house uses
its OWN real per-load kW from `Loads.dss` (`IEEE8500_LOAD_KW`, already `to_pu_power`-
converted) via [`_ieee8500_house`](@ref), never a tuned scalar-multiplier module-level
constant. `:ieee8500` looks up `IEEE8500_LOAD_KW` directly by the bus's own SX name (the
table is keyed EXCLUSIVELY by SX/LV load-bus names); `:ieee8500_mv` has NO direct SX->MV
table, so it walks SX -> X (triplex) -> MV (service transformer) explicitly, summing every
service transformer's real kW onto its host MV bus (each load aggregated onto its
MV node — the aggregation multiple transformers hanging off one MV bus require). Both
paths additionally APPEND 4 `Aggregator`s (one per `ieee8500_capacitor_buses()` entry)
wrapping a single `FixedCapacitor` each at zero inelastic demand (`Pdc = zeros(T)`),
so `Aggregator` stays the SOLE `:Rp`/`:Rq` writer (`FixedCapacitor` itself
never touches `ctx.residuals`).

# `:case_a_784` population

`sym = :case_a_784` materializes the thesis Case A population: `_CASE_A_TOTAL_HOUSES = 784`
per-house-seeded residential houses distributed over the 10 IEEE-13 load buses
(`_case_a_house_counts`: base share `784 ÷ 10` per bus, residue +1 to the first 4 buses in
ascending bus-id order — buses 2-5 carry 79 houses, buses 6-11 carry 78), rolled up into
EXACTLY 10 bus-level `Aggregator`s (devices concatenated, `Pdc` summed, ascending bus
order). The roll-up is load-bearing: `solve_admm` hard-enforces one aggregator per load
node, and `run(::Centralized, s)`'s `sort!([a.bus for a in aggs])` price extraction needs
unique bus rows — 784 per-house aggregators would throw on both counts. The 784-house
granularity lives in the construction: each house draws its profile via
`generate_profiles` seeded by `_case_a_house_seed(seed, bus, house_index)` — a per-house
`hash((seed, :house, bus, house_index)) % typemax(UInt32)` derivation, NEVER the per-bus
`seed + bus` idiom — and its device magnitudes use the `_IEEE13_*` scales DIVIDED by the
bus's house count, preserving each bus's aggregate load/PV at the validated `:default`
level (calibration provenance; raw per-house scales would put roughly 78x the calibrated
load through the 6.86 MVA head branch). The selector is defined over `:ieee13` only; any
other `feeder_sym` throws `ArgumentError`. `case_a_household_map` rebuilds the
house → (bus, aggregator, device set, PV group) map from the same helpers without
constructing `Aggregator`s or drawing profiles.
"""
function build_population(
    sym::Symbol,
    feeder,
    feeder_sym::Symbol,
    profiles,
    seed::Integer;
    flex_devices = nothing,
)
    sel = _flex_selectors(flex_devices)   # validate first: unknown selector fails loud
    if isempty(sel)
        return _build_population_core(sym, feeder, feeder_sym, profiles, seed, sel)
    end
    aggs = _build_population_core(sym, feeder, feeder_sym, profiles, seed, sel)
    sym === :case_a_784 && return aggs   # per-house attachment done inside the core
    T = length(profiles.demand)
    # :default — one house per aggregator (house_index = 1); pure-capacitor aggregators skipped.
    return [
        all(d -> d isa FixedCapacitor, a.devices) ? a : _with_flex(a, seed, 1, sel, T) for
        a in aggs
    ]
end

function _build_population_core(
    sym::Symbol,
    feeder,
    feeder_sym::Symbol,
    profiles,
    seed::Integer,
    sel::Vector{Symbol},
)
    if sym === :case_a_784
        if feeder_sym !== :ieee13
            throw(
                ArgumentError(
                    "build_population(:case_a_784): the selector is defined over the 10 " *
                    "IEEE-13 load buses only; got feeder selector $(repr(feeder_sym))",
                ),
            )
        end
        buses = _load_buses(feeder, feeder_sym)
        counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)
        T = length(profiles.demand)
        load_scale, pv_scale, dev_scale =
            (_IEEE13_LOAD_SCALE, _IEEE13_PV_SCALE, _IEEE13_DEV_SCALE)
        aggs = Aggregator[]
        for bus in buses
            houses = [
                _case_a_house(
                    bus,
                    h,
                    counts[bus],
                    seed,
                    T;
                    load_scale = load_scale,
                    pv_scale = pv_scale,
                    dev_scale = dev_scale,
                    pv_fraction = _CASE_A_PV_FRACTION,
                ) for h in 1:counts[bus]
            ]
            isempty(sel) ||
                (houses = [_with_flex(h, seed, i, sel, T) for (i, h) in enumerate(houses)])
            # Bus-level roll-up (load-bearing shape): one Aggregator per load bus with the
            # houses' devices concatenated and their Pdc summed — solve_admm throws on any
            # other aggregator count (one-aggregator-per-load-node guard) and the
            # centralized price extraction needs unique bus rows.
            push!(
                aggs,
                Aggregator(
                    bus,
                    0.90,
                    reduce(vcat, [h.devices for h in houses]),
                    reduce(+, [h.Pdc for h in houses]),
                ),
            )
        end
        return aggs
    elseif sym !== :default
        throw(
            ArgumentError(
                "build_population: unknown population selector $(repr(sym)); " *
                "expected :default or :case_a_784",
            ),
        )
    end

    buses = _load_buses(feeder, feeder_sym)
    T = length(profiles.demand)

    if feeder_sym in (:ieee8500, :ieee8500_mv)
        kw_pu_dict = if feeder_sym === :ieee8500
            # Direct per-SX-bus lookup, exactly as `IEEE8500_LOAD_KW` is keyed.
            remap = ieee8500_relabel_map()
            inv_remap = Dict(id => name for (name, id) in remap)
            Dict{Int, Float64}(
                bus => to_pu_power(
                    IEEE8500_LOAD_KW[inv_remap[bus]] / 1000.0,
                    IEEE8500_MV_BASE,
                ) for bus in buses
            )
        else
            # No direct SX->MV table exists: walk SX -> X (triplex) -> MV (service
            # transformer) explicitly (cross-transformer summation).
            x_to_sx_name = Dict{String, String}()
            for (a, b) in keys(IEEE8500_LV_BRANCH_RX_OHMS)
                sx_name, x_name = startswith(a, "SX") ? (a, b) : (b, a)
                x_to_sx_name[x_name] = sx_name
            end
            mv_kw_by_name = Dict{String, Float64}()
            for ((mv_bus_base, x_bus_base), _) in IEEE8500_XFMR_EDGES
                sx_name = x_to_sx_name[x_bus_base]
                mv_kw_by_name[mv_bus_base] =
                    get(mv_kw_by_name, mv_bus_base, 0.0) + IEEE8500_LOAD_KW[sx_name]
            end
            mv_remap = ieee8500_mv_relabel_map()
            dict = Dict{Int, Float64}(
                mv_remap[mv_name] => to_pu_power(kw / 1000.0, IEEE8500_MV_BASE) for
                (mv_name, kw) in mv_kw_by_name
            )
            expected = Set(ieee8500_mv_load_buses())
            got = Set(keys(dict))
            if got != expected
                throw(
                    ArgumentError(
                        "build_population(:ieee8500_mv): SX->X->MV aggregation bus-id " *
                        "mismatch against ieee8500_mv_load_buses(): missing " *
                        "$(setdiff(expected, got)), unexpected $(setdiff(got, expected))",
                    ),
                )
            end
            dict
        end

        houses = [_ieee8500_house(bus, kw_pu_dict[bus], profiles, seed, T) for bus in buses]

        cap_relabel =
            feeder_sym === :ieee8500 ? ieee8500_relabel_map() : ieee8500_mv_relabel_map()
        cap_houses = [
            # Pdc=0 (zero inelastic demand), so φ's exact value is a formal
            # placeholder — the load-power-factor reactive term (-Pdc*tanφ) vanishes
            # identically since Pdc is the zero vector; φ=0.90 is chosen only to satisfy
            # Aggregator's (0,1] constructor guard.
            Aggregator(
                cap_relabel[cap_bus_name],
                0.90,
                [
                    FixedCapacitor(
                        cap_relabel[cap_bus_name],
                        to_pu_power(kvar / 1000.0, IEEE8500_MV_BASE),
                    ),
                ],
                zeros(T),
            ) for (cap_bus_name, kvar) in IEEE8500_CAPACITOR_KVAR
        ]

        return vcat(houses, cap_houses)
    end

    load_scale, pv_scale, dev_scale = if feeder_sym === :ieee123
        (_IEEE123_LOAD_SCALE, _IEEE123_PV_SCALE, _IEEE123_DEV_SCALE)
    else
        (_IEEE13_LOAD_SCALE, _IEEE13_PV_SCALE, _IEEE13_DEV_SCALE)
    end

    return [
        _default_house(
            bus,
            profiles,
            seed,
            T;
            φ = 0.90,
            load_scale = load_scale,
            pv_scale = pv_scale,
            dev_scale = dev_scale,
            batt_pmax = 0.5 * load_scale,
            batt_emax = 2.0 * load_scale,
            batt_soc0 = 1.0 * load_scale,
        ) for bus in buses
    ]
end

"""
    case_a_household_map(feeder, feeder_sym::Symbol, seed_unused::Integer;
                         pv_fraction::Real = _CASE_A_PV_FRACTION) -> Vector{<:NamedTuple}

The pure, deterministic household map of the `:case_a_784` population: one row per house, in
bus-major then house-index order (house 1 = bus 2 house 1, ...), with EXACTLY the fields
`house` (global 1..784 index), `bus`, `aggregator` (the house's bus id — the 10 aggregators
are keyed by bus), `device_set` (`:thermostatic_deferrable_pvbattery`, the fixed 3-device
house), `pv_group` (`_case_a_pv_group` at `pv_fraction`), and `house_index` (1-based within
its bus).

`seed_unused` is accepted positionally for call-site symmetry with
[`build_population`](@ref) and is NOT used: the map encodes only assignment structure
(`bus` / `house_index` / `pv_group`), never profile draws, so it is identical for every
seed. Per-house seeding lives exclusively in [`build_population`](@ref)'s profile draws
via `_case_a_house_seed`.

It derives everything from the SAME assignment primitives the `:case_a_784` branch of
[`build_population`](@ref) uses — `_load_buses`, `_case_a_house_counts`, `_case_a_pv_group`
— so the map and the built population's assignment cannot drift apart (single source of
truth). It performs NO `Aggregator` construction and NO profile draw: pure arithmetic,
cheap to call. No mutation, no global state, no randomness: two calls with equal arguments
return `==` vectors — and so do two calls differing only in `seed_unused`.

Throws `ArgumentError` unless `feeder_sym === :ieee13` (the same restriction as the
`:case_a_784` branch). UNEXPORTED by design (the materializer group stays out of the
namespace): callers qualify `TSODSO.case_a_household_map`.
"""
function case_a_household_map(
    feeder,
    feeder_sym::Symbol,
    seed_unused::Integer;
    pv_fraction::Real = _CASE_A_PV_FRACTION,
)
    if feeder_sym !== :ieee13
        throw(
            ArgumentError(
                "case_a_household_map: the map is defined over the 10 IEEE-13 load buses " *
                "only; got feeder selector $(repr(feeder_sym))",
            ),
        )
    end
    buses = _load_buses(feeder, feeder_sym)
    counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)
    row_t = @NamedTuple{
        house::Int,
        bus::Int,
        aggregator::Int,
        device_set::Symbol,
        pv_group::Symbol,
        house_index::Int,
    }
    rows = Vector{row_t}()
    house = 0
    for bus in buses
        for h in 1:counts[bus]
            house += 1
            push!(
                rows,
                (
                    house = house,
                    bus = bus,
                    aggregator = bus,
                    device_set = :thermostatic_deferrable_pvbattery,
                    pv_group = _case_a_pv_group(h, counts[bus], pv_fraction),
                    house_index = h,
                ),
            )
        end
    end
    return rows
end

"""
    _powerflow_from_selector(pf::Symbol, thesis_literal::Bool, ε::Float64)

Internal dispatch behind [`build_powerflow`](@ref); the terminal branch throws `ArgumentError`
for an unknown selector.
"""
function _powerflow_from_selector(pf::Symbol, thesis_literal::Bool, ε::Float64)
    if pf === :convex_branch_flow
        return ConvexBranchFlow(; thesis_literal = thesis_literal)
    elseif pf === :restricted_branch_flow
        return RestrictedBranchFlow(; ε = ε)
    elseif pf === :lindistflow
        return LinDistFlow()
    elseif pf === :ac
        # Default `limits = true`: this path solves the full welfare problem.
        return ACPowerFlow()
    else
        throw(
            ArgumentError(
                "build_powerflow: unknown pf selector $(repr(pf)); expected one of " *
                "$(SCENARIO_VALID_PFS)",
            ),
        )
    end
end

"""
    build_powerflow(s::Scenario) -> AbstractPowerFlow

Materialize the power-flow formulation named by `s.pf`:

| `s.pf`                    | result                                                     |
|:------------------------- |:---------------------------------------------------------- |
| `:convex_branch_flow`     | `ConvexBranchFlow(; thesis_literal = s.pf_thesis_literal)` |
| `:restricted_branch_flow` | `RestrictedBranchFlow(; ε = s.pf_ε)`                       |
| `:lindistflow`            | `LinDistFlow()`                                            |
| `:ac`                     | `ACPowerFlow()` (default `limits = true`)                  |

The default scenario yields an object `===` the earlier hard-coded `ConvexBranchFlow()`, so
numeric goldens stay bit-identical. `:ac` is the researcher's responsibility on large feeders
(only `:ieee13` has been measured).
"""
build_powerflow(s::Scenario) = _powerflow_from_selector(s.pf, s.pf_thesis_literal, s.pf_ε)
