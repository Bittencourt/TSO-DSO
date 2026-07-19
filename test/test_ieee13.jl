# Seam: data/ieee13.jl (DATA-03) — the modified IEEE 13-node built-in fixture.
#
# Fixture-level @testitems (driven GREEN by plan 04-03). They assert that
# `ieee13_modified()` constructs as a radial, magnitude-valid, per-unit `Feeder`
# and that its topology matches thesis Table 4.1 under the node `k` → struct
# index `k+1` shift. Item names contain "ieee13" so the `occursin(...)` filter
# selects them.
#
# The GLB-CVX SOCP solve on this feeder (OPT-02) and the thesis-number ground-truth
# regression (OPT-02/OPT-03) ARE exercised by the "ground" @testitems below (added by
# plan 04-06). Their names contain BOTH "ieee13" and "ground" so either `occursin`
# filter selects them; they consume the Phase4Fixtures ground-truth calibration and run
# the full centralized SOCP solve through `operational_oracle`.

@testitem "ieee13: ieee13_modified constructs radial — 11 buses, 10 branches, root at index 1 (DATA-03)" tags = [
    :ieee13,
] begin
    using TSODSO

    @test isdefined(TSODSO, :ieee13_modified)

    feeder = TSODSO.ieee13_modified()               # runs assert_radial + assert_magnitudes
    @test length(feeder.buses) == 11                 # thesis node 0 + nodes 1..10
    @test length(feeder.branches) == 10              # radial tree ⇒ buses − 1
    @test feeder.root == 1                            # index 1 = thesis MEM frontier (node 0)
    @test feeder.buses[1].is_root                     # root bus carries the is_root flag
    @test count(b -> b.is_root, feeder.buses) == 1    # exactly one frontier bus
    @test eltype(feeder.branches) == TSODSO.Branch{Float64}   # per-unit Float64 fixture
end

@testitem "ieee13: fixture magnitudes & topology match thesis Table 4.1 (DATA-03)" tags = [
    :ieee13,
] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()

    # Voltage band: every bus 0.95 / 1.05 pu (Table 4.1).
    @test all(b -> b.vmin == 0.95, feeder.buses)
    @test all(b -> b.vmax == 1.05, feeder.buses)

    # Head branch (thesis 0→1 ⇒ struct index 1→2) carries the single binding limit:
    # S_max = 6.86 MVA ⇒ 0.0686 pu on the 100 MVA base.
    head = feeder.branches[1]
    @test head.from == 1 && head.to == 2
    @test head.smax ≈ 0.0686

    # Interior branches are effectively unconstrained but STRICTLY inside the
    # 0 < smax < 100 magnitude band (99.0 sentinel, Open Q2 / Assumption A4).
    interior = feeder.branches[2:end]
    @test all(br -> br.smax == 99.0, interior)
    @test all(br -> 0 < br.smax < 100.0, feeder.branches)

    # IN-01: the interior sentinel is SINGLE-SOURCED. The fixture alias, the formulation's
    # internal constant, and the canonical `SMAX_NO_LIMIT` must all be the SAME value — this
    # is the equality that the two previously-duplicated `99.0` literals silently relied on.
    @test TSODSO.IEEE13_INTERIOR_SMAX === TSODSO.SMAX_NO_LIMIT
    @test TSODSO._SMAX_NO_LIMIT === TSODSO.SMAX_NO_LIMIT
    @test all(br -> br.smax == TSODSO.SMAX_NO_LIMIT, interior)

    # Topology spot-checks under the node k → struct index k+1 shift:
    #   branch 1: thesis (0,1) → index (1,2), r 0.310
    @test (feeder.branches[1].from, feeder.branches[1].to) == (1, 2)
    @test feeder.branches[1].r ≈ 0.310 && feeder.branches[1].x ≈ 0.155
    #   branch 9: thesis (3,9) → index (4,10), r 0.600 (the long lateral)
    @test (feeder.branches[9].from, feeder.branches[9].to) == (4, 10)
    @test feeder.branches[9].r ≈ 0.600 && feeder.branches[9].x ≈ 0.300
    #   branch 10: thesis (2,10) → index (3,11), r 0.300
    @test (feeder.branches[10].from, feeder.branches[10].to) == (3, 11)

    # Impedances stay well inside the per-unit sanity band (0 ≤ r,x < 5).
    @test all(br -> 0 ≤ br.r < 5.0 && 0 ≤ br.x < 5.0, feeder.branches)
end

# ----------------------------------------------------------------------------------------
# GROUND-TRUTH SOLVE + REGRESSION (OPT-02 / OPT-03) — plan 04-06.
#
# The centralized GLB-CVX social-welfare solve every later rung (pricing, ADMM) is
# validated against. The full ConvexBranchFlow SOCP is solved on the modified IEEE-13
# feeder through `operational_oracle`, proven OPTIMAL + EXACT (PF-04 gate) +
# cross-solver-consistent (Clarabel-SOCP vs Ipopt-NLP), and a COMPUTED golden is pinned as
# the primary reproducibility anchor. The thesis figure `v₉[16] ≈ 1.0493` is a documented
# APPROXIMATE cross-check (RESEARCH Open Q1 / Assumption A1), NOT a hard exact-match gate.
#
# ── The ground-truth CALIBRATION (RESEARCH Open Q1 / A2–A3) ────────────────────────────
# The thesis MEM price profile (Fig 4.5), exterior temperature (Fig 4.2), and per-house
# device parametrization are only PLOTTED, and the 784-house / 112-per-node count is
# internally inconsistent (A3), so the thesis inputs cannot be bit-reproduced. The shared
# Phase4Fixtures magnitudes are normalized SHAPES (O(0.1..1) pu) that, at full scale, draw
# ~90× the 0.0686 pu head limit ⇒ the congestion-constrained solve is INFEASIBLE. The
# `build_ieee13_ground_aggregators` builder rescales those shapes to a residential
# magnitude (GROUND_LOAD_SCALE / GROUND_PV_SCALE) so the solve is FEASIBLE and lands in the
# thesis CONGESTION-DRIVEN OVER-VOLTAGE regime: the head branch binds at its export limit at
# the afternoon PV peak, driving a genuine over-voltage on the long node-9 lateral. This is
# a DOCUMENTED calibration, not the thesis inputs — hence a pinned COMPUTED golden.
#
# ── Assumption A1 (|V| = √v) ──────────────────────────────────────────────────────────
# `ctx.meta[:pf_vars].v` is the SQUARED voltage v = |V|², so the voltage MAGNITUDE is
# `|V| = sqrt(value(v[bus, t]))`. The thesis y-axis (Fig 4.4, "Tensión [p.u.]") plots the
# MAGNITUDE, so `v₉[16] ≈ 1.0493` is compared against `sqrt(v)`, NOT the squared variable.
#
# ── Node → struct-index mapping ────────────────────────────────────────────────────────
# `ieee13_modified()` puts thesis node k at struct index k+1 (root = thesis node 0 = index
# 1). So thesis NODE 9 is struct INDEX 10, and hour 16 is time index t = 16.
#
# ── Why `allow_export = true` ─────────────────────────────────────────────────────────
# The PV surplus reverse-flows to the frontier; priced export is the SOC-exactness enabler
# (PF-04) that keeps the cone `l·v = P²+Q²` tight in the over-voltage regime. Import-only
# leaves losses-vs-curtailment welfare-equivalent (cone can go slack / inexact) and here is
# INFEASIBLE (the root cannot absorb the reverse flow).

@testitem "ieee13 ground: GLB-CVX SOCP solve is OPTIMAL, exact, cross-solver-consistent (OPT-02/OPT-03)" tags = [
    :ieee13,
    :ground,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = TSODSO.ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    λ₀ = Phase4Fixtures.mem_price_profile()
    @test length(λ₀) == 24

    # Full centralized GLB-CVX SOCP solve through the oracle (SOCP routing by the
    # problem_class trait ⇒ Clarabel; allow_export lets the PV surplus reach the MEM so the
    # cone stays exact — see header). The oracle RETURNED, so `solve_welfare` passed
    # `assert_solved!` (OPTIMAL) AND the PF-04 exactness gate (else it would have thrown).
    res = operational_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true)
    ctx = res.ctx

    # Welfare is finite and within a magnitude sanity bound (catches a unit/scale blowup).
    @test isfinite(res.cost)
    @test abs(res.cost) < 1e6

    # The exactness gate RAN and PASSED: max|l·v − (P²+Q²)| well under τ = 1e-5 (PF-04).
    @test haskey(ctx.meta, :socp_maxgap)
    @test ctx.meta[:socp_maxgap] < 1e-5

    # The distribution price (DADP) at the first aggregator's bus is length-24 and finite.
    @test length(res.dadp) == 24
    @test all(isfinite, res.dadp)

    # The frontier coupling dual π (root DADP over the horizon) is finite and length-24.
    @test length(res.π) == 24
    @test all(isfinite, res.π)

    # A1 sanity: `v` is the SQUARED voltage, so |V₉[16]| = sqrt(v[10, 16]) (node 9 → index
    # 10). The over-voltage regime puts it above 1.0 but strictly below the 1.05 pu cap.
    v9_16 = sqrt(value(ctx.meta[:pf_vars].v[10, 16]))
    @test 1.0 < v9_16 < 1.05

    # Cross-solver sanity (RESEARCH Pitfall 4): re-solve the SAME assembly through the NLP
    # factory (Ipopt) with `allow_local = true` (Ipopt reports LOCALLY_SOLVED on this convex
    # problem) and `allow_export = true`. The RSOC→nonconvex-quadratic bridge (registered in
    # solve_welfare) lets Ipopt take the cone. A doubled current from a bad cone scaling would
    # surface as an objective DISAGREEMENT here.
    _ctx2, obj2, _dadp2 = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = 24, λ₀ = λ₀,
        optimizer = select_optimizer(NLP()),
        allow_local = true,
        allow_export = true,
    )
    @test isapprox(res.cost, obj2; rtol = 1e-3, atol = 1e-3)
end

@testitem "ieee13 ground: pinned computed golden regression + thesis v₉[16] cross-check (OPT-02/OPT-03)" tags = [
    :ieee13,
    :ground,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    # ── PINNED COMPUTED GOLDEN (primary reproducibility anchor) ─────────────────────────
    # These constants were captured from the FIRST trusted solve (OPTIMAL + exact +
    # Clarabel≈Ipopt) on the documented ground-truth calibration. They are the ground truth
    # every later rung is validated against; a live solve must reproduce them to ~1e-4, which
    # catches numerical drift (a solver bump, a formulation regression, a fixture change).
    # They are COMPUTED values, NOT the thesis figures — the thesis inputs are figure-bound
    # (Open Q1); the thesis `v₉[16] ≈ 1.0493` is a separate APPROXIMATE cross-check below.
    #
    # `v` is the SQUARED voltage ⇒ |V₉[16]| = sqrt(v[10, 16]); node 9 → struct index 10; the
    # welfare has a documented (large) gap to the thesis social-welfare $1819 because the
    # MEM/temperature profiles and house counts are figure-bound (A2/A3).
    const GOLDEN_V9_16 = 1.0436080536       # |V₉[16]| = sqrt(v[10,16]); v[10,16]² ≈ 1.0891178
    const GOLDEN_WELFARE = -4823.1598620624 # GLB-CVX welfare optimum (computed; ≠ thesis $1819)
    const GOLDEN_DADP16 = 1.4024313925      # first-aggregator DADP at hour 16
    const GOLDEN_SUM_DADP = 96.7166853441   # Σ_t DADP — a horizon-wide summary of the price vector
    const THESIS_V9_16 = 1.0493             # thesis Fig 4.4 magnitude (Open Q1 / A1) — cross-check only

    feeder = TSODSO.ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    λ₀ = Phase4Fixtures.mem_price_profile()

    res = operational_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true)
    ctx = res.ctx

    # |V₉[16]| — sqrt because `v` is |V|² (A1); struct index 10 = thesis node 9, t = 16.
    v9_16 = sqrt(value(ctx.meta[:pf_vars].v[10, 16]))

    # ── HARD regression assertions on the COMPUTED golden (~1e-4 anchor) ────────────────
    @test isapprox(v9_16, GOLDEN_V9_16; atol = 1e-4)
    @test isapprox(res.cost, GOLDEN_WELFARE; rtol = 1e-4)
    @test isapprox(res.dadp[16], GOLDEN_DADP16; atol = 1e-3)
    @test isapprox(sum(res.dadp), GOLDEN_SUM_DADP; rtol = 1e-4)

    # ── APPROXIMATE thesis cross-check — NON-FAILING (plan-checker W#2) ──────────────────
    # Emit the exact gap to the thesis magnitude ALWAYS (visible in the test log), so a
    # figure-bound profile difference is observable without ever reddening the suite.
    gap = abs(v9_16 - THESIS_V9_16)
    @info "ieee13 ground: thesis v₉[16] cross-check (Assumption A1)" v9_16 = v9_16 thesis =
        THESIS_V9_16 gap = gap note = "gap is expected & documented (Open Q1: inputs figure-bound)"

    # A `broken` @test NEVER fails the suite: it reports Broken when the tight tolerance is
    # unmet and Pass when it is met (here gap ≈ 0.0057 < 1e-2, so it passes). This gives a
    # suite-visible marker of the approximate match WITHOUT a spurious red from a figure-bound
    # input difference. Only the COMPUTED golden above uses tight HARD assertions.
    @test gap < 1e-2 broken = (gap >= 1e-2)

    # Generous PHYSICAL-BAND sanity ceiling that cannot spuriously fail: voltage is capped at
    # vmax = 1.05 pu and the thesis over-voltage magnitude is ≈ 1.05, so a correct |V₉[16]|
    # sits within a small band of 1.0493. 0.06 is deliberately loose (it would tolerate a
    # figure-bound profile difference) — the tight MAGNITUDE reading is pinned by the HARD
    # golden assertion above (`v9_16 ≈ GOLDEN_V9_16`, atol 1e-4); this line only guards
    # against a gross regression (a mis-scaled price or an out-of-band voltage).
    @test gap < 0.06
end
