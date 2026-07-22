# src/data/ieee13.jl
#
# SEAM: modified IEEE 13-node feeder built-in fixture (DATA-03).
# OWNER: plan 04-03.
#
# NAMING (IN-02): "IEEE 13-node" is the HISTORICAL name of the source test feeder, NOT a bus
# count. The MODIFIED thesis case collapses it to 11 buses (root MEM node 0 + 10 load nodes)
# and 10 radial branches — see the node→index table below. Read "13-node" as the lineage of
# the fixture, not its size.
#
# Ships the modified IEEE 13-node distribution feeder from the thesis (Table 4.1 +
# Figure 4.1, base 100 MVA / 13.2 kV) as an immutable, JuMP-free `Feeder`: 11 buses
# (index 1 = thesis node 0 = MEM frontier / root, indices 2..11 = the 10 aggregator
# load nodes) and 10 radial branches with their per-unit r/x and the head-branch
# apparent-power limit `S_max,(0,1) = 6.86 MVA ⇒ 0.0686 pu`. Interior branches carry no
# binding thermal limit in the thesis (congestion-driven at the head), so they use the
# canonical `SMAX_NO_LIMIT` pu sentinel that honours the STRICT `0 < smax < 100` magnitude
# band in units/PerUnit.jl (RESEARCH Open Q2). Construction runs `assert_radial` +
# `assert_magnitudes`, so an invalid feeder can never be returned (DATA-03).

"""
    IEEE13_BASE

The single documented per-unit base for the modified IEEE-13 fixture:
`S_base = 100 MVA`, `V_base = 13.2 kV` (thesis Table 4.1 / Figure 4.1, pp. 89-90).
All SI→pu conversion for this fixture happens ONCE, here at ingestion, through
`to_pu_*` on this base — never inside a model builder (see units/PerUnit.jl).
"""
const IEEE13_BASE = PerUnitBase(100.0, 13.2)

"""
    IEEE13_INTERIOR_SMAX

Per-unit apparent-power sentinel for the non-head (interior) branches. The thesis
gives no explicit thermal limit on interior branches — the modified IEEE-13 case is
congestion-driven at the head branch only (Assumption A4 / Open Q2). We therefore
mark interior branches as effectively unconstrained with a large sentinel that is
STRICTLY below the `SMAX_PU_MAX = 100.0` magnitude tripwire in units/PerUnit.jl.

IN-01: this is an ALIAS of the canonical `SMAX_NO_LIMIT` (units/PerUnit.jl) — the SAME
constant the `ConvexBranchFlow` formulation checks against when deciding to drop a branch's
power cone. Sourcing both from one definition removes the fragile "two independent `99.0`
literals must stay equal" coupling (a test asserts the alias holds).

NOTE: the RESEARCH code sketch used `100.0`, which FAILS the strict `0 < smax < 100`
band at `Feeder` construction. `SMAX_NO_LIMIT = 99.0` is the largest round value that both
passes the tripwire and stays far above any physical interior flow, so only the head branch
binds.
"""
const IEEE13_INTERIOR_SMAX = SMAX_NO_LIMIT

"""
    ieee13_modified() -> Feeder{Float64}

Build the modified IEEE 13-node test feeder from thesis Table 4.1 / Figure 4.1 as an
immutable, radial-validated, per-unit `Feeder` on the `IEEE13_BASE` (100 MVA / 13.2 kV).

# Topology (11 buses, 10 radial branches)

Bus `id` equals its 1-based position, so **thesis node `k` maps to struct index `k+1`**
(the root MEM frontier, thesis node 0, is struct index 1). The full node→index map — a
reference for the ground-truth regression (plan 04-06), e.g. thesis node 9 = struct
index 10:

| thesis node  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9  | 10 |
|:------------ |:- |:- |:- |:- |:- |:- |:- |:- |:- |:-- |:-- |
| struct index | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |

Branches (thesis `from,to` — `r[pu]`, `x[pu]`), shifted `k → k+1` on construction:

    (0,1) 0.310 0.155   (1,6) 0.300 0.150
    (1,2) 0.310 0.155   (2,7) 0.300 0.150
    (2,3) 0.310 0.155   (3,8) 0.300 0.150
    (1,4) 0.150 0.075   (3,9) 0.600 0.300
    (4,5) 0.150 0.075   (2,10)0.300 0.150

# Magnitudes

  - Every bus has voltage bounds `vmin = 0.95`, `vmax = 1.05` pu.
  - The **head branch** (thesis `0→1`, struct index `1→2`) carries the single binding
    thermal limit `S_max = 6.86 MVA ⇒ 0.0686 pu` (converted once via `to_pu_power`).
  - Interior branches use the `IEEE13_INTERIOR_SMAX = 99.0` pu sentinel — effectively
    unconstrained, and strictly inside the magnitude band (Assumption A4 / Open Q2).

`Feeder(buses, branches, 1)` runs `assert_radial` (DATA-02) and `assert_magnitudes`
(INFRA-05) before returning, so the fixture is validated by construction (DATA-03).
"""
function ieee13_modified()
    vmin, vmax = 0.95, 1.05
    buses = [Bus(i, vmin, vmax, i == 1) for i in 1:11]     # index 1 = thesis node 0 (root)

    # SI→pu ONCE at ingestion: head-branch limit 6.86 MVA on the 100 MVA base ⇒ 0.0686 pu.
    s_head = to_pu_power(6.86, IEEE13_BASE)                 # == 0.0686 pu
    s_int = IEEE13_INTERIOR_SMAX                            # 99.0 pu sentinel (Open Q2)

    # (thesis_from, thesis_to, r_pu, x_pu, smax_pu) — node k shifts to struct index k+1.
    raw = [
        (0, 1, 0.310, 0.155, s_head),   # head branch — the single binding thermal limit
        (1, 2, 0.310, 0.155, s_int),
        (2, 3, 0.310, 0.155, s_int),
        (1, 4, 0.150, 0.075, s_int),
        (4, 5, 0.150, 0.075, s_int),
        (1, 6, 0.300, 0.150, s_int),
        (2, 7, 0.300, 0.150, s_int),
        (3, 8, 0.300, 0.150, s_int),
        (3, 9, 0.600, 0.300, s_int),
        (2, 10, 0.300, 0.150, s_int),
    ]
    branches = [Branch(f + 1, t + 1, r, x, s) for (f, t, r, x, s) in raw]

    return Feeder(buses, branches, 1)     # assert_radial + assert_magnitudes run here
end

export ieee13_modified
