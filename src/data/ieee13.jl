# src/data/ieee13.jl
#
# SEAM: modified IEEE 13-node feeder built-in fixture (DATA-03).
# OWNER: plan 04-03.
#
# Ships the modified IEEE 13-node distribution feeder from the thesis (Table 4.1 +
# Figure 4.1, base 100 MVA / 13.2 kV) as an immutable, JuMP-free `Feeder`: 11 buses
# (index 1 = thesis node 0 = MEM frontier / root, indices 2..11 = the 10 aggregator
# load nodes) and 10 radial branches with their per-unit r/x and the head-branch
# apparent-power limit `S_max,(0,1) = 6.86 MVA ⇒ 0.0686 pu`. Interior branches carry no
# binding thermal limit in the thesis (congestion-driven at the head), so they use a
# 99.0 pu sentinel that honours the STRICT `0 < smax < 100` magnitude band in
# units/PerUnit.jl (RESEARCH Open Q2). Construction runs `assert_radial` +
# `assert_magnitudes`, so an invalid feeder can never be returned (DATA-03).
#
# COMMENT-ONLY STUB — no code, no exports. Filled by plan 04-03 (DATA-03).
