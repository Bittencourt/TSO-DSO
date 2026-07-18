# src/data/profiles.jl
#
# SEAM: seeded first-order Markov profile generator (DATA-04).
# OWNER: plan 03-02.
#
# Data-layer ONLY — pure, JuMP-free reproducible profile synthesis. Given a
# row-stochastic transition matrix, an initial state, a state->value map, a
# horizon, and an EXPLICIT `AbstractRNG` (a `StableRNGs.LehmerRNG` seeded once by
# the caller — never the global RNG), produces inelastic-demand and PV profiles
# that regenerate bit-for-bit across Julia 1.10/1.11/1.12 (INFRA-04). Same seed ->
# identical profiles. These profiles enter the welfare solve as PARAMETERS, not
# decisions (RESEARCH Pattern 4; thesis §2.8). This file declares its own
# `export`s when plan 03-02 fills it; it is a comment-only stub until then.
