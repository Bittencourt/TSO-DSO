# src/experiments/materialize.jl
#
# SEAM: deterministic selector → object materialization (EXP-01 / INFRA-04).
# OWNER: plan 08-02 (this plan).
#
# Deterministically reconstructs the heavy Phase 1–7 objects (feeder, λ₀, aggregators) from
# a `Scenario`'s primitive selectors + its master `seed`, reusing `ieee13_modified` /
# `ieee123_modified` / `generate_profiles` / `Aggregator` verbatim — this is orchestration,
# NO new model, NO solver named anywhere (INFRA-02). `sub_seed` derives INDEPENDENT
# deterministic sub-streams from the master seed (RESEARCH Pitfall 5) so `:profiles` and
# `:population` never accidentally couple or collide; every stochastic draw flows through a
# freshly-seeded `generate_profiles` call (itself backed by a `StableRNGs.LehmerRNG`), NEVER
# the global RNG / `Random.seed!`. Kept dependency-light (no DrWatson) so EXP-01 is testable
# without the storage layer (plan 08-04).

"""
    sub_seed(master::Integer, tag::Symbol) -> Int

Derive an INDEPENDENT deterministic sub-seed from a `Scenario`'s master `seed` and a stream
tag (e.g. `:profiles`, `:population`), per RESEARCH Pitfall 5. Two different tags on the SAME
master produce DIFFERENT sub-seeds (independent, non-colliding sub-streams); the SAME
`(master, tag)` pair always produces the SAME sub-seed (deterministic — INFRA-04). Never
touches the global RNG: this is a pure `hash` derivation, not a draw.
"""
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))

"""
    build_feeder(sym::Symbol) -> Feeder{Float64}

Materialize the feeder named by `sym`: `:ieee13` → [`ieee13_modified`](@ref), `:ieee123` →
[`ieee123_modified`](@ref), `:ieee8500` → [`ieee8500_modified`](@ref) (SCALE-01 headline
full MV+LV), `:ieee8500_mv` → [`ieee8500_mv_modified`](@ref) (SCALE-02 MV-only control,
D-02 — a SEPARATE builder, not an `mv_only=true` keyword argument). Throws `ArgumentError`
on any other selector (a `Scenario`'s own constructor already guards this — RESEARCH
§Pattern 1 — but `build_feeder` guards again as a seam that may be called directly).
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

# --- :mem price shape (EXP-01 §Pattern 1) ---
#
# The pinned 24-hour MEM / wholesale price `λ₀` (¢$/kWh-consistent) — the SAME digitized
# shape as `test/fixtures_phase4.jl` `mem_price_profile()` / `test/fixtures_phase7.jl`
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

# --- :default population shape (EXP-01 §Pattern 1 / RESEARCH read_first fixture SHAPEs) ---
#
# Reuses the fixtures_phase4/7 `_house_aggregator` residential-magnitude SHAPE (Thermostatic +
# Deferrable + PVBattery, seeded per-bus `generate_profiles`) but is not itself allowed to
# `using` a test fixture module, so the construction is duplicated here as the canonical
# `src/`-side implementation. The two feeder-scale calibrations (ieee13 @ 100 MVA base /
# ieee123 @ 1 MVA base) need DIFFERENT residential magnitude scales to stay in a sane,
# congestion/voltage-relevant regime on their own per-unit base; `_default_house` is
# feeder-scale-agnostic and takes the scale triple as arguments.

const _DEFAULT_BATT_λ_MIN = 3.8
const _DEFAULT_BATT_λ_MED = 6.2
const _DEFAULT_BATT_λ_MAX = 8.9

# ieee13 (100 MVA base) residential scale — mirrors fixtures_phase4 GROUND_LOAD_SCALE/GROUND_PV_SCALE.
const _IEEE13_LOAD_SCALE = 0.005
const _IEEE13_PV_SCALE = 0.03
const _IEEE13_DEV_SCALE = 1.0

# ieee123 (1 MVA feeder-scale base) residential scale — mirrors fixtures_phase7
# LOAD_SCALE_IEEE123/PV_SCALE_IEEE123/DEV_SCALE_IEEE123.
const _IEEE123_LOAD_SCALE = 0.03
const _IEEE123_PV_SCALE = 0.06
const _IEEE123_DEV_SCALE = 0.05

# The 24-hour exterior-temperature profile (°C) feeding the thermostatic ambient `Tout`, the
# SAME digitized shape as the Phase4/7 fixtures (thesis Fig 4.2). Cyclically repeated to any
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
bus is a load bus, mirroring `fixtures_phase4.build_ieee13_aggregators`.

WR-03 fix: dispatches on the ALREADY-KNOWN, already-validated `Scenario.feeder::Symbol`
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
mirroring the `fixtures_phase4`/`fixtures_phase7` `_house_aggregator` construction SHAPE.
`profiles` is accepted for signature symmetry with [`build_population`](@ref) but each house
draws its OWN per-bus profile via `generate_profiles(seed = seed + bus, T)` — the SAME
per-bus-seeded idiom the fixtures use — so no two houses share a profile draw and the whole
population is deterministic in `seed` (a global-RNG leak would break this, RESEARCH Pitfall 5;
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

A per-bus-REAL-MAGNITUDE sibling of [`_default_house`](@ref) for the IEEE-8500 fixtures
(D-03) — a genuinely NEW code path, NOT a parameterized modification of `_default_house`
(RESEARCH Pitfall 4). `kw_pu::Float64` is the bus's OWN real per-load kW, ALREADY converted
to per-unit power (`to_pu_power`, D-03/D-05) by the caller — it takes the place of
`_default_house`'s tuned `load_scale * d` scalar multiply: `Pdc = kw_pu * d` for each
seeded demand-profile sample `d` (the seeded profile SHAPE still modulates the fixed real
magnitude; only the magnitude source differs from `_default_house`).

The device-construction body below is copied VERBATIM from `_default_house` (same
`Thermostatic`/`Deferrable`/`PVBattery` calls, same `_DEFAULT_BATT_λ_*` constants — D-04:
the 3-device house stays fixed, no device-count axis is introduced alongside the density
sweep), with `dev_scale = 1.0` FIXED inline — D-03 explicitly rejects a tuned
`_IEEE8500_DEV_SCALE`-style constant for this fixture, unlike the `_IEEE13_*`/`_IEEE123_*`
scale triples `_default_house` takes as arguments.
"""
function _ieee8500_house(bus::Int, kw_pu::Float64, profiles, seed::Integer, T::Int)
    prof = generate_profiles(; seed = seed + bus, T = T)   # per-bus, deterministic in `seed`
    dev_scale = 1.0   # D-03: no tuned _IEEE8500_DEV_SCALE constant for this fixture
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
    build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer) -> Vector{<:Aggregator}

Materialize the aggregator population named by `sym`. `:default` returns one seeded
residential `Aggregator` per real load bus of `feeder` ([`_load_buses`](@ref)), rescaled to
the feeder's own per-unit base (`_IEEE13_*`/`_IEEE123_*` residential scales, selected by
`feeder_sym`). `T` is read from `length(profiles.demand)` (the caller's own
`generate_profiles(; T = s.T)` draw), so this stays consistent with the Scenario's horizon
without taking `T` as a separate argument. Deterministic in `seed`: two calls with the SAME
`seed` return structurally identical aggregators (same per-bus profile draws); a DIFFERENT seed
changes every house. Throws `ArgumentError` on any other selector.

WR-03 fix: `feeder_sym` (the caller's already-validated `Scenario.feeder` selector) now
disambiguates the IEEE-13 vs IEEE-123 residential scale directly, instead of re-deriving it
from `length(feeder.buses) == length(ieee123_relabel_map())` — a structural coincidence that a
future feeder fixture sharing IEEE-123's bus count would silently, wrongly match.

# IEEE-8500 real-per-load-kW path (D-03, plan 25-04)

For `feeder_sym in (:ieee8500, :ieee8500_mv)`, the `:ieee13`/`:ieee123` tuned-scalar path
above is BYPASSED entirely (this branch never runs for those two selectors — the
`:ieee13`/`:ieee123` branch is left completely untouched, must-not-break): each house uses
its OWN real per-load kW from `Loads.dss` (`IEEE8500_LOAD_KW`, already `to_pu_power`-
converted) via [`_ieee8500_house`](@ref), never a tuned scalar-multiplier module-level
constant (D-03). `:ieee8500` looks up `IEEE8500_LOAD_KW` directly by the bus's own SX name (the
table is keyed EXCLUSIVELY by SX/LV load-bus names); `:ieee8500_mv` has NO direct SX->MV
table, so it walks SX -> X (triplex) -> MV (service transformer) explicitly, summing every
service transformer's real kW onto its host MV bus (D-02's "each load aggregated onto its
MV node" — the aggregation multiple transformers hanging off one MV bus require). Both
paths additionally APPEND 4 `Aggregator`s (one per `ieee8500_capacitor_buses()` entry, D-12)
wrapping a single `FixedCapacitor` each at zero inelastic demand (`Pdc = zeros(T)`),
preserving DEV-05 (`Aggregator` stays the SOLE `:Rp`/`:Rq` writer — `FixedCapacitor` itself
never touches `ctx.residuals`).
"""
function build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer)
    if sym !== :default
        throw(
            ArgumentError(
                "build_population: unknown population selector $(repr(sym)); expected :default",
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
                bus => to_pu_power(IEEE8500_LOAD_KW[inv_remap[bus]] / 1000.0, IEEE8500_MV_BASE)
                for bus in buses
            )
        else
            # No direct SX->MV table exists: walk SX -> X (triplex) -> MV (service
            # transformer) explicitly (D-02's cross-transformer summation).
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

        cap_relabel = feeder_sym === :ieee8500 ? ieee8500_relabel_map() : ieee8500_mv_relabel_map()
        cap_houses = [
            # D-12: Pdc=0 (zero inelastic demand), so φ's exact value is a formal
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

export sub_seed, build_feeder, build_price, build_population
