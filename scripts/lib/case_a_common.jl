# scripts/lib/case_a_common.jl
#
# Shared Phase-42 "case-a-magnitude" helpers — a plain-Julia include-able lib (NO DrWatson,
# NO top-level TSODSO dependency): both the measurement runner (plans 42-03/42-04,
# `scripts/case_a_magnitude.jl`) and the structural test file (`test/test_case_a_magnitude.jl`)
# `include` this file directly.
#
# Honesty-policy framing: the functions here make Phase 42's pre-registration STRUCTURALLY
# enforceable rather than aspirational (42-CASE-A-PROTOCOL.md, committed BEFORE any Case A
# run). `assert_protocol_registered` is the fail-loud gate every Case A measurement main
# calls before building or solving anything: no protocol file, no run; an uncommitted
# protocol, no run. `welfare_gain` is the ONE registered gain definition — the SIGN-SAFE
# form `100·(W_DADP − W_FIT)/|W_FIT|` (protocol §1); the naive ratio `W_DADP/W_FIT` is
# banned (it sign-inverts on negative welfare — welfare is ≈ −3.78e5 at 784 houses) and NO
# ratio method exists here. `provenance_row`/`flatten_note` stamp every CSV row so each row
# is auditable to its measurement environment, and every row carries the `protocol_sha`
# returned by the guard so post-hoc protocol edits are visible in every artifact.
#
# 42-04 addition — the device-variant rebuild (protocol §7d): `case_a_houses_variant`,
# `assert_houses_map_aligned` and `case_a_variant_rollup` reference TSODSO ONLY through
# `TSODSO.X`-qualified names resolved at CALL time. The include stays TSODSO-free (the
# guard/gain test items never load TSODSO), while a CALL of the rebuild helpers requires
# `using TSODSO` first (the runner and the rebuild test items do exactly that). The rebuild
# law (42-RESEARCH Pitfall 5): houses are rebuilt from the SAME `_case_a_house` primitives
# the 784 builder uses, in `case_a_household_map` order; the builder's `pv_fraction` kwarg
# is accepted-for-symmetry only and is NEVER used; the variant map's PV attribution is
# recomputed from the ACTUAL device sets.

using LinearAlgebra: BLAS

# The CONTEXT-locked protocol path. The repo root is derived from @__DIR__ walking up two
# levels (this file lives in <root>/scripts/lib/) — NOT projectdir() — so the lib works
# identically from the test env and from the script env.
const PROTOCOL_PATH = joinpath(
    dirname(dirname(@__DIR__)),
    ".planning",
    "phases",
    "42-thesis-case-a-magnitude",
    "42-CASE-A-PROTOCOL.md",
)

"""
    welfare_gain(w_dadp::Real, w_fit::Real) -> NamedTuple

The REGISTERED Case A welfare-gain definition (42-CASE-A-PROTOCOL.md §1; the
`scripts/thesis_case123_repro.jl` sign-safe form): returns
`(Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))`.

The denominator is `abs(w_fit)` so the sign of `Δpct` always equals the sign of `ΔW` —
including when welfare is negative (it is, at the 784-house population: ≈ −3.78e5). The
naive ratio `w_dadp / w_fit` is NEVER computed or reported: on negative welfare it
SIGN-INVERTS (a DADP welfare loss reads as a gain > 1). Banned by the PROJECT.md Key
Decision and protocol §1.
"""
welfare_gain(w_dadp::Real, w_fit::Real) =
    (Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))

"""
    protocol_sha(path::AbstractString = PROTOCOL_PATH) -> String

The full 40-hex SHA of the latest commit touching `path`, via
`git -C <dir of path> log -1 --format=%H -- <path>`. Returns `""` when the file has no git
history (never committed, or the repo has no commits at all). Never throws on the
"no history" condition — an empty SHA is the honest answer, and
[`assert_protocol_registered`](@ref) is what turns it into a loud failure.
"""
function protocol_sha(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || return ""
    sha = try
        readchomp(`git -C $(dirname(path)) log -1 --format=%H -- $(path)`)
    catch
        return ""
    end
    # readchomp returns a SubString{String} (chomp keeps the parent buffer); the contract —
    # and every later CSV row's protocol_sha stamp — is a plain String.
    return String(sha)
end

"""
    assert_protocol_registered(path::AbstractString = PROTOCOL_PATH) -> String

The pre-registration gate (42-CASE-A-PROTOCOL.md; every Case A measurement main calls this
BEFORE building or solving anything). Errors — fail-loud, message names the
"PRE-REGISTRATION VIOLATION" — when the protocol file is missing, or when it exists but is
NOT committed (no git history ⇒ empty SHA: an uncommitted protocol is no pre-registration).
Returns the full 40-hex protocol SHA otherwise (later plans stamp it into every CSV row, so
any post-hoc protocol edit is visible in every artifact — the tampering mitigation
T-42-01-1/T-42-01-2).
"""
function assert_protocol_registered(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol file missing at " *
        "$path. Write and commit 42-CASE-A-PROTOCOL.md BEFORE any Case A run.",
    )
    sha = protocol_sha(path)
    isempty(sha) && error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol exists at $path but is " *
        "NOT committed (no git history). Commit it in its own commit before running.",
    )
    return sha
end

"""
    provenance_row(T_H::Int, seed::Int) -> NamedTuple

The provenance stamp merged into every measurement row (`scripts/tariff_comparison.jl`
verbatim shape): julia_version / threads / blas_threads / seed / t_horizon. Runners pin
`BLAS.set_num_threads(1)` at main start so the stamped value is row-to-row comparable.
"""
provenance_row(T_H::Int, seed::Int) = (
    julia_version = string(VERSION),
    threads = Threads.nthreads(),
    blas_threads = BLAS.get_num_threads(),
    seed = seed,
    t_horizon = T_H,
)

"""
    flatten_note(s) -> String

Committed-CSV note hygiene (`scripts/tariff_comparison.jl` verbatim): the status `notes`
carry solver messages that legitimately contain newlines, but the artifact CSVs are
LINE-ORIENTED by repo convention — embedded newlines are flattened to "; " and double
quotes to single; the message CONTENT is preserved verbatim otherwise.
"""
flatten_note(s) = replace(replace(String(s), '\n' => "; ", '\r' => ""), '"' => "'")

# ---- the device-variant rebuild (protocol §7d; TSODSO-qualified at CALL time) ------------------

# The protocol-pinned device-mix variant set (42-CASE-A-PROTOCOL.md §7d). Adding a variant
# is a protocol amendment + a script/test edit (the deliberate-act friction).
const CASE_A_DEVICE_VARIANTS = ("registered", "batteries_out", "pv_half")

# The device TYPE NAME of a rebuilt house's device — the lib stays TSODSO-free by comparing
# NAMES (`"PVBattery"`, `"Thermostatic"`, `"Deferrable"`), never `isa` tests on TSODSO types.
_device_name(d) = String(nameof(typeof(d)))

_has_pv_battery(devices) = any(_device_name(d) == "PVBattery" for d in devices)

"""
    assert_houses_map_aligned(houses, map_rows, context) -> nothing

The rebuild drift tripwire (the `tariff_comparison.jl:511-518` fail-loud shape): errors —
naming `context` and the drift — unless `houses` and `map_rows` agree 1:1 on length and bus
assignment, AND every map row's `pv_group` agrees with that house's ACTUAL device set. Every
rebuilt population must pass this before any roll-up or solve: a rebuild that drifted from
`case_a_household_map` aborts loudly, never solves.
"""
function assert_houses_map_aligned(houses, map_rows, context::AbstractString)
    length(houses) == length(map_rows) || error(
        "$context: $(length(houses)) rebuilt houses vs $(length(map_rows)) household-map " *
        "rows — the rebuild drifted from case_a_household_map (aborting loudly)",
    )
    for k in eachindex(houses)
        houses[k].bus == map_rows[k].bus || error(
            "$context: house $k bus $(houses[k].bus) vs map bus $(map_rows[k].bus) — the " *
            "rebuild drifted from case_a_household_map (aborting loudly)",
        )
        actual_pv = _has_pv_battery(houses[k].devices)
        map_rows[k].pv_group == (actual_pv ? :pv : :non_pv) || error(
            "$context: house $k map pv_group $(map_rows[k].pv_group) disagrees with its " *
            "actual device set — the variant map drifted from the rebuilt houses " *
            "(aborting loudly)",
        )
    end
    return nothing
end

"""
    case_a_houses_variant(feeder, feeder_sym, T, seed; variant, fraction = 1.0)
        -> (houses, map_rows)

The device-variant rebuild of the `:case_a_784` population (protocol §7d) at a nested-prefix
`fraction`: rebuilds the per-house `Aggregator`s from the SAME `_case_a_house` primitives the
builder uses (`_load_buses` / `_case_a_house_counts` / `_case_a_rung_counts` /
`sub_seed(seed, :population)`) in `case_a_household_map` order. The builder's `pv_fraction`
kwarg is accepted-for-symmetry only and is NEVER used (every house is built with the fixed
3-device set; the variant transform happens AFTER construction). Variants:

  - `registered`    — the fixed 3-device set (Thermostatic + Deferrable + PVBattery), PV 100%
  - `batteries_out` — `PVBattery` dropped from EVERY house before roll-up
  - `pv_half`       — the FIRST HALF of the prefix (in household-map order) keeps the
    3-device set; the rest is Thermostatic + Deferrable only (at the full
    784 houses this is the protocol's first-392/last-392 split)

Returns `(houses, map_rows)`: the per-house `Aggregator`s and the VARIANT map rows (same
shape as `case_a_household_map`'s) with `device_set`/`pv_group` recomputed from the ACTUAL
device sets — never the constant-1.0 assumption. At `fraction >= 1` the rebuild must carry
exactly `_CASE_A_TOTAL_HOUSES` houses. The alignment tripwire runs before the return.
Roll up bus-level with `case_a_variant_rollup`.
"""
function case_a_houses_variant(
    feeder,
    feeder_sym::Symbol,
    T::Int,
    seed::Integer;
    variant::AbstractString,
    fraction::Real = 1.0,
)
    variant in CASE_A_DEVICE_VARIANTS || throw(
        ArgumentError(
            "case_a_houses_variant: unknown device-mix variant $(repr(variant)); the " *
            "protocol-pinned set (42-CASE-A-PROTOCOL.md §7d) is: " *
            "$(join(CASE_A_DEVICE_VARIANTS, ", "))",
        ),
    )
    buses = TSODSO._load_buses(feeder, feeder_sym)
    counts = TSODSO._case_a_house_counts(buses, TSODSO._CASE_A_TOTAL_HOUSES)
    rung_counts = TSODSO._case_a_rung_counts(counts, fraction)
    n_prefix = sum(values(rung_counts))
    pv_split = div(n_prefix, 2)   # houses at 0-based index < pv_split keep the PV device
    s_pop = TSODSO.sub_seed(seed, :population)
    rebuilt = Any[]
    for bus in buses, h in 1:rung_counts[bus]
        house = TSODSO._case_a_house(
            bus,
            h,
            counts[bus],
            s_pop,
            T;
            load_scale = TSODSO._IEEE13_LOAD_SCALE,
            pv_scale = TSODSO._IEEE13_PV_SCALE,
            dev_scale = TSODSO._IEEE13_DEV_SCALE,
            pv_fraction = TSODSO._CASE_A_PV_FRACTION,
        )
        drop_pv =
            variant == "batteries_out" ||
            (variant == "pv_half" && length(rebuilt) >= pv_split)
        devices =
            drop_pv ? filter(d -> _device_name(d) != "PVBattery", house.devices) :
            house.devices
        push!(rebuilt, TSODSO.Aggregator(house.bus, house.φ, devices, house.Pdc))
    end
    houses = convert(Vector{typeof(rebuilt[1])}, rebuilt)
    # The variant map: the pure household map FILTERED to the prefix, then device_set /
    # pv_group recomputed from the ACTUAL device sets (never the constant-1.0 assumption).
    prefix_map = filter(
        r -> r.house_index <= rung_counts[r.bus],
        TSODSO.case_a_household_map(feeder, feeder_sym, seed),
    )
    map_rows = collect(
        map(
            (h, r) -> (
                house = r.house,
                bus = r.bus,
                aggregator = r.aggregator,
                device_set = Symbol(join(lowercase.(_device_name.(h.devices)), "_")),
                pv_group = _has_pv_battery(h.devices) ? :pv : :non_pv,
                house_index = r.house_index,
            ),
            houses,
            prefix_map,
        ),
    )
    context = "case_a_houses_variant(variant=$(repr(variant)), fraction=$(Float64(fraction)))"
    if fraction >= 1
        length(houses) == TSODSO._CASE_A_TOTAL_HOUSES || error(
            "$context: the full fraction rebuilt $(length(houses)) houses but the " *
            "selector's total is $(TSODSO._CASE_A_TOTAL_HOUSES) — the rebuild drifted " *
            "from the :case_a_784 construction (aborting loudly)",
        )
    end
    assert_houses_map_aligned(houses, map_rows, context)
    return (houses = houses, map_rows = map_rows)
end

"""
    case_a_variant_rollup(houses, map_rows; context = "case_a_variant_rollup")
        -> Vector of bus-level Aggregators

The bus-level roll-up of a rebuilt per-house population, EXACTLY the `build_population`
`:case_a_784` shape: one `Aggregator` per map bus with the houses' devices concatenated and
their `Pdc` summed, buses in map (ascending) order. The alignment tripwire runs first, and
the result carries EXACTLY one aggregator per distinct map bus — the 1:1 bus roll-up guard
(10 for `:ieee13` at every fraction; the `max(1, ...)` rung floor keeps every bus populated).
"""
function case_a_variant_rollup(
    houses,
    map_rows;
    context::AbstractString = "case_a_variant_rollup",
)
    assert_houses_map_aligned(houses, map_rows, context)
    aggs = typeof(houses[1])[]
    for bus in unique(r.bus for r in map_rows)
        hs = houses[findall(r -> r.bus == bus, map_rows)]
        push!(
            aggs,
            TSODSO.Aggregator(
                bus,
                0.90,
                reduce(vcat, [h.devices for h in hs]),
                reduce(+, [h.Pdc for h in hs]),
            ),
        )
    end
    return aggs
end
