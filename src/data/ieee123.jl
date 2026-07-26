# src/data/ieee123.jl
#
# SEAM: modified IEEE 123-node feeder built-in fixture (DATA-03, scale target).
# OWNER: plan 07-01 wired this into the include graph; plan 07-02 FILLS it.
#
# NAMING (IN-02): "IEEE 123-node" is the HISTORICAL name of the source test feeder, NOT a
# guaranteed bus count — exactly as ieee13.jl warns for the 13-node case. The MODIFIED thesis
# Case B (App. E, p.170) relabels the non-contiguous IEEE terminals to the framework's contiguous
# `bus.id == 1-based position` convention and keeps only the RADIAL branch set (the 4 normally-open
# tie switches stay open), so `edges == N − 1`. Read "123-node" as the lineage of the fixture.
#
# ─────────────────────────────────────────────────────────────────────────────────────────────
# DATA PROVENANCE / TRANSCRIPTION NOTE (threat T-07-05, ACCEPTED in the plan):
#
#   * TOPOLOGY (which terminal feeds which) is transcribed from the canonical IEEE-123 node test
#     feeder — the same radial structure the thesis's modified Case B is built on: one substation
#     frontier (terminal 150) feeding long radial laterals through the closed switches/regulators
#     (150-149, 13-152, 18-135, 60-160, 97-197) with the four normally-open tie switches
#     (54-94, 151-300, 250-251, 450-451) OPEN so the graph is a clean tree (RESEARCH Pitfall 4,
#     Assumption A2). This structure is the load-bearing content the fixture must ship.
#
#   * PER-UNIT R/X MAGNITUDES are REAL (plan 17-02, IMPED-02), not the earlier representative
#     placeholder: non-switch branch impedances are now sourced from the public IEEE-123 OpenDSS
#     test-case data (positive-sequence Fortescue-reduced R1/X1 × segment length, in Ohms),
#     reduced by `scripts/reduce_ieee123_impedances.jl` into the generated, committed
#     `src/data/ieee123_impedances.jl` (see that file's own provenance header for source URL and
#     fetch date). The Ω→pu conversion happens ONCE at ingestion here, via `to_pu_impedance`
#     (`src/units/PerUnit.jl:53`) — never inside the reduction script. Switch/regulator segments
#     (`IEEE123_SWITCH_EDGES`) intentionally keep their existing near-ideal synthetic value
#     (RESEARCH Assumption A2), not a real one. Numerical fidelity beyond the magnitude tripwires
#     is still cross-validated at the centralized-SOCP level (T-07-05's load-bearing net).
# ─────────────────────────────────────────────────────────────────────────────────────────────
#
# The ~37 non-load junction (transit / zero-injection) buses this fixture exposes via
# `ieee123_load_nodes` are handled by the DSO-OPT transit-node relaxation (plan 07-03,
# RESEARCH Pitfall 5), NOT here — this file only ships the topology and the load/transit split.

using SparseArrays

include("ieee123_impedances.jl")

"""
    IEEE123_BASE

The single documented per-unit base for the modified IEEE-123 fixture (thesis Case B):
`S_base = 1 MVA`, `V_base = 4.16 kV`. A FEEDER-SCALE apparent-power base (the feeder's own
order of magnitude, not the 100 MVA transmission base) is chosen deliberately so the
distribution quantities (nodal injections, branch flows, the SOC cone `l·v ≈ P²+Q²`) land at
`O(0.1–1)` pu instead of `O(1e-3)` pu. At the transmission-scale 100 MVA base every 4.16 kV
distribution quantity is `~1e-3` pu, which sits at the numerical noise floor of BOTH the PF-04
exactness gate (its `atol = 1e-6` cone-slack floor becomes comparable to the cone itself) and
Clarabel's conditioning under the ADMM ρ-penalty — making convergence + exactness fragile at
scale (plan 07-05 finding). The feeder-scale base keeps the cone magnitude several orders above
the exactness floor (robustly exact) and the SOCP well-conditioned (ADMM converges in tens of
iterations). The head-branch apparent-power limit is the only SI quantity converted here (once,
at ingestion) through `to_pu_power`; the branch r/x are supplied already in per-unit
(representative — see the DATA PROVENANCE note above).
"""
const IEEE123_BASE = PerUnitBase(1.0, 4.16)

"""
Thesis terminal chosen as the MEM/substation frontier (root); RESEARCH Open-Q1: the no-parent node.
"""
const IEEE123_ROOT_TERMINAL = 150

"""
Head-branch (substation/frontier) apparent-power limit, thesis Case B `S_max,01 = 3.8 MVA`.
"""
const IEEE123_HEAD_SMAX_MVA = 3.8

# Switch/regulator segments keep their near-ideal (tiny, strictly-positive pu) synthetic value
# (RESEARCH Assumption A2) — real data is not used here since these are near-ideal by design, not
# ordinary line segments. Non-switch branch impedances now come from `IEEE123_BRANCH_RX_OHMS`
# (`ieee123_impedances.jl`, included above), converted Ω→pu at ingestion in `ieee123_modified()`
# (plan 17-02, IMPED-02). CALIBRATION (plan 07-05): the feeder-scale 1 MVA base keeps the solved
# voltages inside the Case-B band `V∈[0.9,1.1]` while still binding it (under-voltage on the long
# load laterals, over-voltage under midday PV reverse flow) — a genuinely voltage-constrained
# scale case, not a slack one.
const IEEE123_SWITCH_R = 0.0003
const IEEE123_SWITCH_X = 0.00015

# Radial branch set in ORIGINAL IEEE-123 terminal labels: (parent_terminal, child_terminal). Each
# non-root terminal appears EXACTLY ONCE as a child, so this is a spanning tree rooted at 150 by
# construction (the four normally-open tie switches are omitted → `edges == N − 1`). The closed
# switch/regulator segments are listed in `IEEE123_SWITCH_EDGES` and get the near-ideal impedance.
const IEEE123_EDGES = [
    (150, 149),
    (149, 1),
    (1, 2),
    (1, 3),
    (1, 7),
    (3, 4),
    (3, 5),
    (5, 6),
    (7, 8),
    (8, 12),
    (8, 9),
    (8, 13),
    (9, 14),
    (14, 10),
    (14, 11),
    (13, 34),
    (13, 18),
    (13, 152),
    (152, 52),
    (34, 15),
    (15, 16),
    (15, 17),
    (18, 19),
    (18, 21),
    (18, 135),
    (135, 35),
    (19, 20),
    (21, 22),
    (21, 23),
    (23, 24),
    (23, 25),
    (25, 26),
    (25, 28),
    (26, 27),
    (26, 31),
    (27, 33),
    (28, 29),
    (29, 30),
    (31, 32),
    (35, 36),
    (35, 40),
    (36, 37),
    (36, 38),
    (38, 39),
    (40, 41),
    (40, 42),
    (42, 43),
    (42, 44),
    (44, 45),
    (44, 47),
    (45, 46),
    (47, 48),
    (47, 49),
    (49, 50),
    (50, 51),
    (51, 151),
    (52, 53),
    (53, 54),
    (54, 55),
    (54, 57),
    (55, 56),
    (57, 58),
    (57, 60),
    (58, 59),
    (60, 61),
    (60, 62),
    (60, 160),
    (160, 67),
    (62, 63),
    (63, 64),
    (64, 65),
    (65, 66),
    (67, 68),
    (67, 72),
    (67, 97),
    (68, 69),
    (69, 70),
    (70, 71),
    (72, 73),
    (72, 76),
    (73, 74),
    (74, 75),
    (76, 77),
    (76, 86),
    (77, 78),
    (78, 79),
    (78, 80),
    (80, 81),
    (81, 82),
    (81, 84),
    (82, 83),
    (84, 85),
    (86, 87),
    (87, 88),
    (87, 89),
    (89, 90),
    (89, 91),
    (91, 92),
    (91, 93),
    (93, 94),
    (93, 95),
    (95, 96),
    (97, 98),
    (97, 197),
    (197, 101),
    (98, 99),
    (99, 100),
    (100, 450),
    (101, 102),
    (101, 105),
    (102, 103),
    (103, 104),
    (105, 106),
    (105, 108),
    (106, 107),
    (108, 109),
    (108, 300),
    (109, 110),
    (110, 111),
    (110, 112),
    (112, 113),
    (113, 114),
]

"""
Closed switch/regulator segments (near-ideal impedance); the tie switches are excluded entirely.
"""
const IEEE123_SWITCH_EDGES = Set([(150, 149), (13, 152), (18, 135), (60, 160), (97, 197)])

# Spot-load terminals of the modified IEEE-123 (thesis Case B: "85 load nodes"). Every OTHER
# non-root terminal is a TRANSIT (zero-injection) junction bus — the path plan 07-03's DSO-OPT
# relaxation must handle (RESEARCH Pitfall 5). This is the topological load/transit split, NOT
# the aggregator population (that stays in the test/population layer, RESEARCH Open-Q2).
const IEEE123_LOAD_TERMINALS = [
    1,
    2,
    4,
    5,
    6,
    7,
    9,
    10,
    11,
    12,
    16,
    17,
    19,
    20,
    22,
    24,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    37,
    38,
    39,
    41,
    42,
    43,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    55,
    56,
    58,
    59,
    60,
    62,
    63,
    64,
    65,
    66,
    68,
    69,
    70,
    71,
    73,
    74,
    75,
    76,
    77,
    79,
    80,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    90,
    92,
    94,
    95,
    96,
    98,
    99,
    100,
    102,
    103,
    104,
    106,
    107,
    109,
    111,
    112,
    113,
    114,
]

"""
    ieee123_relabel_map() -> Dict{Int,Int}

The documented `thesis_terminal → 1..N` relabeling that makes `bus.id == 1-based position`
(the framework indexing convention; RESEARCH Pitfall 4). The rule is deterministic:

  - the root frontier terminal (`IEEE123_ROOT_TERMINAL == 150`) maps to struct index `1`;
  - every OTHER terminal maps to `1 + its rank` in ASCENDING numeric order.

So with the present terminal set (`1..114` plus the switch/regulator terminals
`135, 149, 151, 152, 160, 197, 300, 450`), the map is, e.g.:

| thesis terminal | 150 | 1 | 2 | … | 114 | 135 | 149 | 151 | 152 | 160 | 197 | 300 | 450 |
|:--------------- |:--- |:- |:- |:- |:--- |:--- |:--- |:--- |:--- |:--- |:--- |:--- |:--- |
| struct index    | 1   | 2 | 3 | … | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 |

(analogous to ieee13.jl's `k → k+1` shift, but a full dictionary for the non-contiguous labels).
"""
function ieee123_relabel_map()
    terminals = sort!(unique!(reduce(vcat, [[p, c] for (p, c) in IEEE123_EDGES])))
    non_root = filter(!=(IEEE123_ROOT_TERMINAL), terminals)
    remap = Dict{Int, Int}(IEEE123_ROOT_TERMINAL => 1)
    for (rank, term) in enumerate(non_root)
        remap[term] = rank + 1
    end
    return remap
end

"""
    ieee123_load_nodes() -> Vector{Int}

The (relabeled, sorted) struct indices of the 85 spot-load buses of the modified IEEE-123
(thesis Case B). Their complement among the non-root buses is the set of TRANSIT
(zero-injection) junction buses — so the transit count is
`length(buses) − 1 − length(ieee123_load_nodes())` (≈ 37). Exposed here so the population layer
(`build_ieee123_aggregators`) and the DSO-OPT transit relaxation (plan 07-03) can split the
aggregator-coupling axis from the balance-closure axis without re-deriving the topology.
"""
function ieee123_load_nodes()
    remap = ieee123_relabel_map()
    return sort!([remap[t] for t in IEEE123_LOAD_TERMINALS])
end

# Sparse node-branch incidence self-check (CLAUDE.md perf: SparseArrays for the topology). A
# genuine transcription tripwire on the error-prone hand-built branch list (threat T-07-05):
# every branch column must hold exactly one +1 (from) and one −1 (to), so all column sums are 0
# and `nnz == 2·B`. `assert_radial` re-derives its own incidence for the tree checks; this one
# guards the RELABEL step before the data reaches the constructor.
function _ieee123_assert_incidence(branches, N)
    B = length(branches)
    Irow = Int[];
    Jcol = Int[];
    Vval = Int[]
    for (b, br) in enumerate(branches)
        push!(Irow, br.from);
        push!(Jcol, b);
        push!(Vval, +1)
        push!(Irow, br.to);
        push!(Jcol, b);
        push!(Vval, -1)
    end
    A = sparse(Irow, Jcol, Vval, N, B)
    (nnz(A) == 2B && all(iszero, sum(A; dims = 1))) || throw(
        ArgumentError(
            "IEEE-123 incidence malformed: a branch has a self-loop or a duplicated endpoint.",
        ),
    )
    return A
end

"""
    ieee123_modified() -> Feeder{Float64}

Build the modified IEEE 123-node voltage-constrained test feeder (thesis Case B, App. E) as an
immutable, radial-validated, per-unit `Feeder` on the `IEEE123_BASE` (1 MVA / 4.16 kV — the
Phase-7 feeder-scale base chosen for SOC cone-slack robustness, matching `IEEE123_BASE` and the
file header; NOT a 100 MVA transmission base).

# Topology (123 buses, 122 radial branches)

The non-contiguous IEEE terminals are relabeled to contiguous `1..N` by `ieee123_relabel_map`
(root frontier terminal 150 → struct index 1; every other terminal → `1 + rank` in ascending
order), so `bus.id` equals its 1-based position. Only the RADIAL branch set is kept — the four
normally-open tie switches (`54-94, 151-300, 250-251, 450-451`) stay open — giving a clean tree
with `edges == N − 1` (RESEARCH Pitfall 4). The frontier terminal 150 (the node with no parent)
is the single root (RESEARCH Open-Q1).

# Load / transit split

`ieee123_load_nodes()` gives the 85 spot-load buses (thesis "85 load nodes"); the remaining ~37
non-root buses are TRANSIT (zero-injection) junctions handled by plan 07-03's DSO-OPT relaxation.

# Magnitudes

  - Every bus has the thesis Case-B voltage band `vmin = 0.9`, `vmax = 1.1` pu (looser than the
    congestion-driven ieee13 case).
  - The **head branch** (frontier terminal `150 → 149`) carries the thermal limit
    `S_max = 3.8 MVA ⇒ 3.8 pu` on the 1 MVA feeder-scale base, converted once via `to_pu_power`
    on `IEEE123_BASE`. At the plan-07-05 population the ACTIVE binding constraint is the voltage
    band (the long laterals hit `≈0.92` under load and `≈1.04` under PV reverse flow) rather than
    this head limit, so the case exercises the branch-flow / voltage physics, not just a scalar cap.
  - All interior branches use the `SMAX_NO_LIMIT = 99.0` pu sentinel (effectively unconstrained,
    strictly inside the `0 < smax < 100` band).
  - Non-switch branch r/x are REAL per-segment impedances (plan 17-02, IMPED-02), sourced from
    the public IEEE-123 OpenDSS test-case data and converted Ω→pu via `to_pu_impedance` (see
    `IEEE123_BRANCH_RX_OHMS` / the DATA PROVENANCE note at the top of this file). Switch/regulator
    segments keep their near-ideal synthetic value (`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X`).

`Feeder(buses, branches, root)` runs `assert_radial` (DATA-02) and `assert_magnitudes` (INFRA-05)
before returning, so an invalid feeder can never exist (DATA-03).
"""
function ieee123_modified()
    vmin, vmax = 0.9, 1.1                      # thesis Case B band (RESEARCH fixture skeleton)
    remap = ieee123_relabel_map()
    N = length(remap)

    buses = [Bus(i, vmin, vmax, i == 1) for i in 1:N]   # index 1 = terminal 150 (frontier/root)

    # SI→pu ONCE at ingestion: head-branch limit 3.8 MVA on the 1 MVA feeder-scale base ⇒ 3.8 pu.
    s_head = to_pu_power(IEEE123_HEAD_SMAX_MVA, IEEE123_BASE)   # == 3.8 pu
    s_int = SMAX_NO_LIMIT                                       # 99.0 pu sentinel (interior)

    branches = Branch{Float64}[]
    for (p, c) in IEEE123_EDGES
        is_switch = (p, c) in IEEE123_SWITCH_EDGES
        if is_switch
            r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X   # near-ideal regulator/switch segments unchanged
        else
            r_Ω, x_Ω = IEEE123_BRANCH_RX_OHMS[(p, c)]
            r, x = to_pu_impedance(r_Ω, IEEE123_BASE), to_pu_impedance(x_Ω, IEEE123_BASE)
        end
        smax = p == IEEE123_ROOT_TERMINAL ? s_head : s_int   # only the frontier branch binds
        push!(branches, Branch(remap[p], remap[c], r, x, smax))
    end

    _ieee123_assert_incidence(branches, N)     # transcription tripwire on the relabel step
    return Feeder(buses, branches, 1)          # assert_radial + assert_magnitudes run here
end

"""
Alias for `ieee123_modified` (RESEARCH fixture skeleton naming).
"""
build_ieee123() = ieee123_modified()

export ieee123_modified, build_ieee123, ieee123_load_nodes, ieee123_relabel_map
