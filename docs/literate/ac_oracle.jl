# # Rung 3 — AC-Exactness Oracle: Certifying the SOCP Relaxation Against a True Nonconvex AC-OPF
#
# The previous page proved [`ConvexBranchFlow`](@ref)'s SOC branch-flow relaxation EXACT on a
# benign radial feeder via its internal exactness certificate. This page goes one step further:
# it certifies the relaxation against a GENUINELY INDEPENDENT nonconvex formulation
# ([`ACPowerFlow`](@ref), which enforces the branch-flow relation `l·v = P²+Q²` as a true
# EQUALITY solved with Ipopt) rather than re-solving the same relaxed cone through a different
# solver — and it does so in the one regime the relaxation is documented to fail.
#
# ## Why an independent oracle
#
# The exactness of the DistFlow SOC relaxation on radial networks is a theorem with KNOWN
# boundaries. Farivar & Low, *"Branch Flow Model: Relaxations and Convexification"* (IEEE Trans.
# Power Systems, 2013), and Gan, Li, Topcu & Low, *"Exact Convex Relaxation of Optimal Power Flow
# in Radial Networks"* (IEEE Trans. Automatic Control, 2015), establish that the relaxation is
# exact provided the upper voltage bound does not strictly bind — and characterize the
# over-voltage / reverse-power-flow regime (a high-PV feeder exporting surplus) as precisely where
# it can go INEXACT: the solver then dumps surplus into a fictitious squared branch current
# `l` so that `l·v > P²+Q²` strictly, and the recovered DADP prices become physically
# meaningless. An INDEPENDENT nonconvex AC-OPF is the oracle that detects this — a bridge-based
# re-solve of the SAME cone cannot, since it optimizes the same relaxed feasible set.
#
# [`assert_ac_exact!`](@ref) compares a solved [`ConvexBranchFlow`](@ref) context against a solved
# [`ACPowerFlow`](@ref) context — both built from the IDENTICAL problem data and each
# independently re-optimized — and reports the per-hour gap. It NEVER throws on a genuine
# numerical disagreement: a relaxation gap is a finding to investigate, not a defect to refuse.

using TSODSO

# ## Building the high-PV stress fixture
#
# A small 3-bus radial feeder with low-impedance branches and tight voltage headroom, plus
# aggregators whose PV back-feed is scaled into the over-voltage regime (`pv_scale = 1.2`, the
# value the test suite settled on empirically). This is the SAME construction logic as the test
# suite's `Phase4Fixtures` high-PV fixture, inlined here because literate pages do not load
# test-only modules.

const T = 24

mem_price = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,
]
temperature = Float64[
    19,
    18,
    17,
    16,
    16,
    17,
    19,
    21,
    23,
    26,
    28,
    30,
    31,
    32,
    32,
    31,
    29,
    27,
    25,
    23,
    22,
    21,
    20,
    19,
]

buses = [
    Bus(1, 0.95, 1.05, true),      # root / MEM frontier
    Bus(2, 0.95, 1.05, false),
    Bus(3, 0.95, 1.05, false),
]
branches = [
    Branch(1, 2, 0.05, 0.05, 99.0),   # low-impedance ⇒ back-feed swings voltage fast
    Branch(2, 3, 0.05, 0.05, 99.0),
]
feeder = Feeder(buses, branches, 1)

# One aggregator per non-root bus, each a Thermostatic + Deferrable + PVBattery, with the PV
# profile scaled by `pv_scale = 1.2` into the over-voltage / reverse-flow regime.

pv_scale = 1.2
aggs = map(2:length(feeder.buses)) do bus
    prof = generate_profiles(seed = 20260406 + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[0.2 * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature)
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, 0.1, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9, Ppv)
    Aggregator(bus, 0.95, [therm, defer, batt], Pdc)
end;

# ## Solving both formulations on the same data
#
# The SOCP solve passes `rtol_exact = 1.0` — a DELIBERATE, documented diagnostic override of
# `solve_welfare`'s own internal PF-04 exactness gate, so the loose-relaxation solution is
# RETURNED for comparison instead of refused. It changes no code in `solve_welfare`. The AC solve
# uses the default Ipopt backend (`allow_local = true` for the nonconvex local-optimum gate). Both
# share the IDENTICAL `feeder` / `aggs` / `λ₀` / `T` / `allow_export`.

ctx_socp, cost_socp, _ = solve_welfare(
    feeder,
    ConvexBranchFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_export = true,
    rtol_exact = 1.0,
)

ctx_ac, cost_ac, _ = solve_welfare(
    feeder,
    ACPowerFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_local = true,
    allow_export = true,
)

# ## The exactness report
#
# [`assert_ac_exact!`](@ref) returns the welfare gap plus a per-hour table `(; t, vgap, pgap,
# qgap, exact)`. These are REAL, solved numbers — recomputed every time this page builds, so they
# can never drift from the `src/` code.

report = assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)

# The welfare gap between the relaxed (SOCP) and the true nonconvex (AC) optimum:

report.obj_gap

# The hours where the SOC relaxation genuinely disagrees with the true AC-OPF:

inexact_hours = [row.t for row in report.hours if !row.exact]

# The full per-hour report:

report.hours

# The SOC relaxation gap `solve_welfare` measured internally (`max |l·v − (P²+Q²)|`). Under the
# default `rtol_exact` this value would have caused `solve_welfare` to REFUSE the SOCP prices; we
# passed `rtol_exact = 1.0` only to expose the loose solution for this comparison. A LARGE value
# here (orders of magnitude above the benign feeder's `~1e-8`) is the direct numerical signature
# of the relaxation going strict:

ctx_socp.meta[:socp_maxgap]

# ## Finding
#
# At `pv_scale = 1.2` the SOC relaxation is GENUINELY INEXACT across the high-PV afternoon window:
# `assert_ac_exact!` flags a run of inexact hours (`inexact_hours` above), and the internal
# relaxation gap (`ctx_socp.meta[:socp_maxgap]`) is orders of magnitude larger than the benign
# feeder's. At those hours the SOCP solution pins a bus voltage at the squared upper bound
# `V²max = 1.05² = 1.1025` and carries reverse (PV back-feed) branch flow — exactly the
# over-voltage / reverse-flow regime Farivar & Low (2013) and Gan, Li, Topcu & Low (2015) identify
# as the SOC relaxation's exactness boundary. There the relaxation inflates the fictitious squared
# current `l` (`l·v > P²+Q²`), so its recovered prices are not physically meaningful — which is why
# `solve_welfare` REFUSES them under its default `rtol_exact`.
#
# This is a DOCUMENTED milestone finding, not a defect to fix: the SOC relaxation is exact on the
# benign feeders of the previous page and genuinely inexact here, and the independent nonconvex AC
# oracle — validated hour-by-hour against a two-start Ipopt comparison in the test suite (ruling
# out a local-optimum artifact) and against a closed-form 2-bus phasor for its angle recovery — is
# what certifies which regime is which. The voltage-binding / reverse-flow diagnostic itself is
# asserted live in `test/test_ac_oracle.jl` (EXACT-04).
