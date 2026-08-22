# src/data/ieee8500.jl
#
# SEAM: IEEE-8500 scale-benchmark feeder fixtures (SCALE-01, SCALE-02). Two committed fixtures
# built from the generated `IEEE8500_*` tables (plan 25-01, src/data/ieee8500_impedances.jl):
# the full MV+LV headline fixture (`ieee8500_modified`) and the MV-only control (D-02,
# `ieee8500_mv_modified`).
#
# NAMING (IN-02): "IEEE 8500-node" is the HISTORICAL name of the source test feeder — it counts
# PER-PHASE nodes on an unbalanced model, NOT a bus count on this framework's balanced
# positive-sequence convention (the same caveat `ieee13.jl`/`ieee123.jl` already carry). The
# REAL, MEASURED bus count of the headline fixture after positive-sequence collapse and
# relabeling is 4,866 (stated here explicitly, never implied by the "8500-node" name); the
# MV-only control fixture measures 2,512 buses. (Both counts were 4,875/2,521 before quick task
# 260822-pxb, 2026-08-22, merged 3 degenerate MV bus pairs — 2 genuine 1-ft real-conductor
# bus-splits plus the substation busbar-tie connector — dropping to 4,872/2,518; then quick task
# 260822-rle, 2026-08-22, WIDENED the same length-class merge to a sub-metre bound, catching 6
# further real-conductor line-split segments and dropping the counts further to 4,866/2,512; see
# `src/data/ieee8500_impedances.jl`'s generated-file header and
# `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` for the full
# record.) Both counts include 2 small virtual buses (`HVMV_Sub_HSB`, `regxfmr_HVMV_Sub_LSB`)
# internal to the substation-transformer/regulator chain — see `IEEE8500_ROOT_BUS` below.
#
# S_base NON-COMPARABILITY (D-05 REVISED): this fixture is built at `S_base = 0.5 MVA` —
# NOT the 1 MVA base of the IEEE-13/123 fixtures. 0.5 MVA is the ONLY base that clears BOTH
# `IMPEDANCE_PU_MAX` and `SMAX_PU_MAX` under the CORRECTED 3-winding service-transformer
# reduction (the worst-case CT5 unit lands at r=3.00/x=2.72 pu, 60% of `IMPEDANCE_PU_MAX`; the
# head branch lands at 55.0 pu, under `SMAX_PU_MAX = 100`). Per-unit impedance/power NUMBERS
# from this fixture are therefore NOT directly comparable to the IEEE-13/123 fixtures' per-unit
# magnitudes — this benchmark phase compares TIMINGS, ITERATION COUNTS, and MODEL DIMENSIONS
# across fixtures, never raw impedance magnitudes. `src/units/PerUnit.jl`'s tripwire constants
# (`IMPEDANCE_PU_MAX`, `SMAX_PU_MAX`) are NEVER touched to accommodate this fixture — the
# tripwires are cleared honestly by the `S_base` choice alone.
#
# ─────────────────────────────────────────────────────────────────────────────────────────────
# TOPOLOGY PROVENANCE / RADIALITY NOTE (SCALE-02, T-25-07):
#
#   The generated `IEEE8500_REGULATOR_EDGES` table (plan 25-01) already carries ONLY the
#   ENABLED `switch=y` tie segments (38 of the source's 43): plan 25-01's original reduction
#   silently treated every `switch=y` record as closed, which (confirmed by direct computation
#   during this plan's construction) produces `edges - (buses - 1) == 5` — 5 independent cycles
#   — and `Feeder`'s `assert_radial` throws on a non-tree feeder. Cross-referencing the vendored
#   `Lines.dss` source text directly found the ground truth already recorded there: exactly 5 of
#   the 43 `switch=y` records carry an explicit `enabled=False` (genuine, authoritative
#   normally-open tie switches, e.g. `New Line.WD701_48332_sw ... switch=y ... enabled=False`).
#   `scripts/reduce_ieee8500_impedances.jl` was corrected (this plan, a Rule-1/Rule-3 deviation:
#   a data-parsing bug blocking `Feeder` construction) to capture `enabled=` and EXCLUDE the 5
#   disabled records from `IEEE8500_REGULATOR_EDGES` entirely — mirroring `ieee123.jl`'s own
#   treatment of its 4 normally-open tie switches (kept out of `IEEE123_EDGES` so the graph is a
#   clean tree). With the 5 disabled ties excluded, the full topology (MV lines + regulators +
#   38 enabled switches + service transformers + LV triplex) is verified (this plan) to be a
#   single connected tree over all buses: `edges == buses - 1` exactly, reachable from
#   `IEEE8500_ROOT_BUS` via BFS. No other edge is dropped (D-06: every real line/transformer
#   segment is kept).
# ─────────────────────────────────────────────────────────────────────────────────────────────

include("ieee8500_impedances.jl")

"""
    IEEE8500_MV_BASE

The documented per-unit base for the IEEE-8500 fixture's MV (primary, 12.47 kV) network:
`S_base = 0.5 MVA`, `V_base = 12.47 kV` (D-05 REVISED — see the file-header non-comparability
note above; this is deliberately NOT the 1 MVA base the IEEE-13/123 fixtures use).
"""
const IEEE8500_MV_BASE = PerUnitBase(0.5, 12.47)

"""
    IEEE8500_LV_BASE

The documented per-unit base for the IEEE-8500 fixture's LV (secondary, 208 V) network:
`S_base = 0.5 MVA` (the SAME `S_base` as `IEEE8500_MV_BASE` — a single system-wide MVA base is
required for per-unit power to be additive across voltage levels), `V_base = 0.208 kV`. Matches
the real ~59.95:1 (`12.47/0.208`) MV/LV transformer turns ratio (RESEARCH Architecture Pattern
2) — NEVER pair `12.47` with `0.12` (a different, unrelated LV standard not used by this
feeder's `LoadXfmrCodes.dss`).
"""
const IEEE8500_LV_BASE = PerUnitBase(0.5, 0.208)

"""
    IEEE8500_ROOT_BUS

The single frontier (root) bus name: `"HVMV_Sub_HSB"`, the substation transformer's own
High-Side Bus. Found in `scripts/data/ieee8500/Transformers.dss`:

    New Transformer.HVMV_Sub  phases=3  windings=2  buses=(HVMV_Sub_HSB, regxfmr_HVMV_Sub_LSB...)
    ~ conns=(delta wye)  kvs=(115, 12.47)  kvas=(27500, 27500)  xhl=15.51  sub=y

`HVMV_Sub_HSB` (bus1, 115 kV) is the transformer's own HV-side terminal — literally the
"substation HV-side ... bus" this fixture's root must be. Choosing it as root means the
substation transformer ITSELF becomes the modeled head branch (near-ideal treatment via
`IEEE8500_REGULATOR_EDGES` membership, D-13), carrying the `IEEE8500_HEAD_SMAX_MVA` rating
(D-08) — exactly mirroring `ieee123.jl`'s pattern (the substation transformer is never modeled
as a separate unconstrained branch; its own edge carries the thermal limit). Verified (this
plan) by direct BFS: `IEEE8500_ROOT_BUS` has degree 1 (its sole edge goes to
`"regxfmr_HVMV_Sub_LSB"`, the transformer's MV-side terminal before the FEEDER_REG regulator
bank) and reaches all buses in the headline and MV-only fixtures.
"""
const IEEE8500_ROOT_BUS = "HVMV_Sub_HSB"

"""
    IEEE8500_HEAD_SMAX_MVA

Head-branch (substation transformer) apparent-power limit, `27.5 MVA` — the substation's own
nameplate rating from `Transformers.dss` (`kvas=(27500, 27500)` on the `HVMV_Sub` transformer).
D-08: the ONLY branch carrying a real thermal limit; every interior branch uses the
`SMAX_NO_LIMIT` sentinel (no per-segment ampacity modeling in this benchmark phase).
"""
const IEEE8500_HEAD_SMAX_MVA = 27.5

"""
    _ieee8500_is_lv_bus(name) -> Bool

D-07's per-voltage-level band classifier: `true` for any bus reachable only through a service
transformer (secondary LV network), `false` for MV buses. On this fixture's real bus-name
population this is EXACTLY the string-prefix rule `startswith(name, "X") || startswith(name,
"SX")` — verified (this plan) by direct enumeration: no MV-level bus name (from
`IEEE8500_MV_BRANCH_RX_OHMS` or `IEEE8500_REGULATOR_EDGES`) starts with `"X"` or `"SX"`, and
every LV-only bus name (from `IEEE8500_XFMR_EDGES`/`IEEE8500_LV_BRANCH_RX_OHMS`, excluding the
MV-side transformer endpoint) does.
"""
_ieee8500_is_lv_bus(name::AbstractString) = startswith(name, "SX") || startswith(name, "X")

"""
    ieee8500_relabel_map() -> Dict{String,Int}

The documented `bus_name -> 1..N` relabeling for the HEADLINE (full MV+LV) fixture, over the
union of every bus name in `IEEE8500_MV_BRANCH_RX_OHMS`, `IEEE8500_REGULATOR_EDGES`,
`IEEE8500_XFMR_EDGES` (both endpoints), and `IEEE8500_LV_BRANCH_RX_OHMS`. Deterministic rule:

  - `IEEE8500_ROOT_BUS` maps to struct index `1`;
  - every OTHER bus name maps to `1 + its rank` in ASCENDING LEXICOGRAPHIC order.

Analogous to `ieee123_relabel_map`'s numeric-ascending rule, adapted to `String` bus names
(RESEARCH Architecture Patterns §2).
"""
function ieee8500_relabel_map()
    names = Set{String}()
    for (a, b) in keys(IEEE8500_MV_BRANCH_RX_OHMS)
        push!(names, a)
        push!(names, b)
    end
    for (a, b) in IEEE8500_REGULATOR_EDGES
        push!(names, a)
        push!(names, b)
    end
    for (a, b) in keys(IEEE8500_XFMR_EDGES)
        push!(names, a)
        push!(names, b)
    end
    for (a, b) in keys(IEEE8500_LV_BRANCH_RX_OHMS)
        push!(names, a)
        push!(names, b)
    end
    sorted = sort!(collect(names))
    non_root = filter(!=(IEEE8500_ROOT_BUS), sorted)
    remap = Dict{String, Int}(IEEE8500_ROOT_BUS => 1)
    for (rank, name) in enumerate(non_root)
        remap[name] = rank + 1
    end
    return remap
end

# Sparse node-branch incidence self-check (CLAUDE.md perf: SparseArrays for the topology),
# mirroring `_ieee123_assert_incidence`: every branch column must hold exactly one +1 (from) and
# one -1 (to), so all column sums are 0 and `nnz == 2*B`. Integer-indexed, applied AFTER
# relabeling — needs no string-keyed variant.
function _ieee8500_assert_incidence(branches, N)
    B = length(branches)
    Irow = Int[]
    Jcol = Int[]
    Vval = Int[]
    for (b, br) in enumerate(branches)
        push!(Irow, br.from)
        push!(Jcol, b)
        push!(Vval, +1)
        push!(Irow, br.to)
        push!(Jcol, b)
        push!(Vval, -1)
    end
    A = sparse(Irow, Jcol, Vval, N, B)
    (nnz(A) == 2B && all(iszero, sum(A; dims = 1))) || throw(
        ArgumentError(
            "IEEE-8500 incidence malformed: a branch has a self-loop or a duplicated endpoint.",
        ),
    )
    return A
end

"""
    ieee8500_modified() -> Feeder{Float64}

Build the headline full MV+LV IEEE-8500 feeder (D-02) as an immutable, radial-validated,
per-unit `Feeder`, ingesting THREE Ω/percent-based edge classes and converting to per-unit
ONCE here (D-09, never inside the reduction script):

  - MV lines (`IEEE8500_MV_BRANCH_RX_OHMS`) via `to_pu_impedance` on `IEEE8500_MV_BASE`;
  - Regulators + the substation transformer + the 38 enabled switch ties
    (`IEEE8500_REGULATOR_EDGES`) — near-ideal treatment reusing `IEEE123_SWITCH_R`/
    `IEEE123_SWITCH_X` verbatim (D-13, Assumption A2 analog; no Ω value to convert);
  - Service transformers (`IEEE8500_XFMR_EDGES`) via the confirmed 3-winding-reduction percent
    formula `r_pu = (r_pct/100)*(S_base_kVA/kva)`, `x_pu = (x_pct/100)*(S_base_kVA/kva)` (D-05
    REVISED) — on the transformer's OWN kVA base, not `to_pu_impedance` (that helper is for
    Ω-based impedances only);
  - LV triplex lines (`IEEE8500_LV_BRANCH_RX_OHMS`) via `to_pu_impedance` on `IEEE8500_LV_BASE`.

# Voltage bands (D-07, per-voltage-level)

MV buses get `(0.9, 1.1)` (the IEEE-123 convention); LV buses (`_ieee8500_is_lv_bus`) get
`(0.88, 1.1)` — the `Loads.dss`-declared `Vminpu=.88` floor.

# Thermal limit (D-08, head-only)

The head branch (either endpoint equal to `IEEE8500_ROOT_BUS` — the substation transformer
edge) carries `to_pu_power(IEEE8500_HEAD_SMAX_MVA, IEEE8500_MV_BASE)` (≈55.0 pu at `S_base =
0.5 MVA`); every other branch uses the `SMAX_NO_LIMIT` sentinel.

`Feeder(buses, branches, root)` runs `assert_radial` (DATA-02) and `assert_magnitudes`
(INFRA-05) before returning, so an invalid feeder can never exist (DATA-03) — see the file
header's TOPOLOGY PROVENANCE note for how this plan resolved the raw source data's cycle
structure into a clean tree.
"""
function ieee8500_modified()
    remap = ieee8500_relabel_map()
    N = length(remap)

    buses = Vector{Bus{Float64}}(undef, N)
    for (name, id) in remap
        vmin, vmax = _ieee8500_is_lv_bus(name) ? (0.88, 1.1) : (0.9, 1.1)
        buses[id] = Bus(id, vmin, vmax, id == 1)
    end

    s_head = to_pu_power(IEEE8500_HEAD_SMAX_MVA, IEEE8500_MV_BASE)   # ≈55.0 pu
    s_int = SMAX_NO_LIMIT
    is_head(a, b) = a == IEEE8500_ROOT_BUS || b == IEEE8500_ROOT_BUS

    branches = Branch{Float64}[]

    for ((a, b), (r_Ω, x_Ω)) in IEEE8500_MV_BRANCH_RX_OHMS
        r, x = to_pu_impedance(r_Ω, IEEE8500_MV_BASE), to_pu_impedance(x_Ω, IEEE8500_MV_BASE)
        smax = is_head(a, b) ? s_head : s_int
        push!(branches, Branch(remap[a], remap[b], r, x, smax))
    end

    for (a, b) in IEEE8500_REGULATOR_EDGES
        r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X   # near-ideal (D-13), no real Ω here
        smax = is_head(a, b) ? s_head : s_int
        push!(branches, Branch(remap[a], remap[b], r, x, smax))
    end

    s_base_kva = IEEE8500_MV_BASE.S_base * 1000.0
    for ((a, b), nt) in IEEE8500_XFMR_EDGES
        r = (nt.r_pct / 100.0) * (s_base_kva / nt.kva)
        x = (nt.x_pct / 100.0) * (s_base_kva / nt.kva)
        push!(branches, Branch(remap[a], remap[b], r, x, s_int))   # never touches root
    end

    for ((a, b), (r_Ω, x_Ω)) in IEEE8500_LV_BRANCH_RX_OHMS
        r, x = to_pu_impedance(r_Ω, IEEE8500_LV_BASE), to_pu_impedance(x_Ω, IEEE8500_LV_BASE)
        push!(branches, Branch(remap[a], remap[b], r, x, s_int))   # never touches root
    end

    _ieee8500_assert_incidence(branches, N)
    return Feeder(buses, branches, 1)   # assert_radial + assert_magnitudes run here
end

"""
    ieee8500_mv_relabel_map() -> Dict{String,Int}

The MV-only control fixture's (D-02) OWN, SEPARATE `bus_name -> 1..M` relabeling — NOT a subset
of `ieee8500_relabel_map()`'s ids, since `Feeder` requires contiguous `1:M` and the MV-only
fixture has fewer buses than the headline. The MV-only bus name set is the union of every
`IEEE8500_MV_BRANCH_RX_OHMS` endpoint, every `IEEE8500_REGULATOR_EDGES` endpoint, and every
`mv_bus_base` (first element) of an `IEEE8500_XFMR_EDGES` key (in practice already covered by
the first two sets on this fixture, included for completeness per the plan's definite
contract). Sorted lexicographically for a deterministic id assignment; `IEEE8500_ROOT_BUS` is
forced to id `1`.
"""
function ieee8500_mv_relabel_map()
    names = Set{String}()
    for (a, b) in keys(IEEE8500_MV_BRANCH_RX_OHMS)
        push!(names, a)
        push!(names, b)
    end
    for (a, b) in IEEE8500_REGULATOR_EDGES
        push!(names, a)
        push!(names, b)
    end
    for (mv_bus_base, _) in keys(IEEE8500_XFMR_EDGES)
        push!(names, mv_bus_base)
    end
    sorted = sort!(collect(names))
    non_root = filter(!=(IEEE8500_ROOT_BUS), sorted)
    remap = Dict{String, Int}(IEEE8500_ROOT_BUS => 1)
    for (rank, name) in enumerate(non_root)
        remap[name] = rank + 1
    end
    return remap
end

"""
    ieee8500_mv_modified() -> Feeder{Float64}

Build the MV-only control fixture (D-02): ~2,518 MV buses (measured, post quick task
260822-pxb's 3-pair bus-merge, 2026-08-22 — was 2,521 before; see
`ieee8500_mv_relabel_map`), keeping every MV line + regulator/switch edge and EXCLUDING every
LV (`X*`/`SX*`) bus and every service-transformer edge entirely. `Feeder` itself holds no load
data, so per-MV-bus load aggregation (D-02's "each load aggregated onto its MV node") is a
POPULATION-LAYER concern (`ieee8500_mv_load_buses`, plan 25-04), not this topology builder's —
symmetric with how `ieee123_load_nodes` externalizes the load/transit split.
"""
function ieee8500_mv_modified()
    remap = ieee8500_mv_relabel_map()
    N = length(remap)

    buses = Vector{Bus{Float64}}(undef, N)
    for (name, id) in remap
        # Every bus in the MV-only fixture is, by construction, an MV bus (D-07 MV band);
        # `_ieee8500_is_lv_bus` would always be false here but is intentionally not called —
        # the MV-only builder never touches an X*/SX* name at all.
        buses[id] = Bus(id, 0.9, 1.1, id == 1)
    end

    s_head = to_pu_power(IEEE8500_HEAD_SMAX_MVA, IEEE8500_MV_BASE)
    s_int = SMAX_NO_LIMIT
    is_head(a, b) = a == IEEE8500_ROOT_BUS || b == IEEE8500_ROOT_BUS

    branches = Branch{Float64}[]
    for ((a, b), (r_Ω, x_Ω)) in IEEE8500_MV_BRANCH_RX_OHMS
        r, x = to_pu_impedance(r_Ω, IEEE8500_MV_BASE), to_pu_impedance(x_Ω, IEEE8500_MV_BASE)
        smax = is_head(a, b) ? s_head : s_int
        push!(branches, Branch(remap[a], remap[b], r, x, smax))
    end
    for (a, b) in IEEE8500_REGULATOR_EDGES
        r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X
        smax = is_head(a, b) ? s_head : s_int
        push!(branches, Branch(remap[a], remap[b], r, x, smax))
    end

    _ieee8500_assert_incidence(branches, N)
    return Feeder(buses, branches, 1)
end

"""
    ieee8500_load_nodes() -> Vector{Int}

The (relabeled via `ieee8500_relabel_map`, sorted) struct indices of the 1,177 `SX*` LV load
buses of the HEADLINE fixture — mirrors `ieee123_load_nodes`'s load/transit-split role. Every
OTHER non-root headline bus (MV transit junctions + `X*` service-transformer LV terminals) is a
TRANSIT (zero-injection) bus.
"""
function ieee8500_load_nodes()
    remap = ieee8500_relabel_map()
    sx_names = Set{String}()
    for (a, b) in keys(IEEE8500_LV_BRANCH_RX_OHMS)
        startswith(a, "SX") && push!(sx_names, a)
        startswith(b, "SX") && push!(sx_names, b)
    end
    return sort!([remap[name] for name in sx_names])
end

"""
    ieee8500_mv_load_buses() -> Vector{Int}

D-02's DEFINITE, single contract: the `unique`-deduplicated, ASCENDING-sorted set of
`ieee8500_mv_relabel_map()` ids for every MV bus that is the `mv_bus_base` (first element) of AT
LEAST ONE `IEEE8500_XFMR_EDGES` entry. `unique` IS applied — multiple service transformers CAN
(and DO: measured 1,138 distinct MV buses host the 1,177 transformers) hang off the same MV bus
after phase-suffix collapse, so `length(ieee8500_mv_load_buses()) ≤ 1177`, MEASURED not
hardcoded. This function answers "which MV buses need a load," NOT "how much load" — plan
25-04's population builder does the SX -> X -> MV real-kW summation onto these exact bus ids
directly from `IEEE8500_XFMR_EDGES` + `IEEE8500_LV_BRANCH_RX_OHMS` + `IEEE8500_LOAD_KW`.
"""
function ieee8500_mv_load_buses()
    remap = ieee8500_mv_relabel_map()
    mv_bases = unique(mv_bus_base for (mv_bus_base, _) in keys(IEEE8500_XFMR_EDGES))
    return sort!(unique([remap[b] for b in mv_bases]))
end

"""
    ieee8500_capacitor_buses() -> Vector{Int}

The 4 relabeled ids of `R20185`, `R42247`, `R42246`, `R18242` (D-12's promoted, zero-inelastic-
demand cap buses) — valid for BOTH fixtures via each fixture's OWN relabel map, since these are
MV terminals present in both (`IEEE8500_CAPACITOR_KVAR`'s keys). Accepts which relabel map to
use, defaulting to the headline fixture's.
"""
function ieee8500_capacitor_buses(relabel_map::Dict{String, Int} = ieee8500_relabel_map())
    return sort!([relabel_map[name] for name in keys(IEEE8500_CAPACITOR_KVAR)])
end

export ieee8500_modified,
    ieee8500_mv_modified,
    ieee8500_relabel_map,
    ieee8500_mv_relabel_map,
    ieee8500_load_nodes,
    ieee8500_mv_load_buses,
    ieee8500_capacitor_buses,
    IEEE8500_MV_BASE,
    IEEE8500_LV_BASE,
    IEEE8500_ROOT_BUS,
    IEEE8500_HEAD_SMAX_MVA
