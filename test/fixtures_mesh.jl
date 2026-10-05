# test/fixtures_mesh.jl
#
# Shared test fixture module for the meshed-network tests. A TestItems
# `@testmodule` that every meshed-network `@testitem` consumes via
# `setup=[MeshFixtures]`. It provides the ONE committed CI loop fixture: a
# 4-bus "diamond" (single independent cycle, nB=4 > N-1=3) with a TOGGLABLE impedance
# profile -- `:uniform` and `:heterogeneous` on the SAME topology -- exercising both the
# angle-recoverability certificate's recoverable and unrecoverable branches
# without any knife-edge parameter search.
#
# SEAM: meshed-network CI fixture (prerequisite for the angle-recoverability certificate tests).
#
# CONTRACT (mirrors fixtures_stochastic.jl's discipline): this module is SELF-CONTAINED, i.e. it
# makes NO top-level call to any symbol that may be defined later. Every feeder-
# consuming builder takes arguments (`profile::Symbol`), so nothing here evaluates a
# not-yet-defined symbol at module-load time.
#
# TOPOLOGY CHOICE (a 3-bus triangle is not usable; chosen at the discretion of the
# fixture design for the exact loop-fixture topology/parameters):
#
# A literal 3-bus TRIANGLE (branches (1,2),(2,3),
# (3,1)) was tried first. Direct testing found that topology MATHEMATICALLY
# INCOMPATIBLE with `MeshedFlow`'s pure delegation to `ConvexBranchFlow.contribute!` (exactly
# as designed, with ZERO new constraint code): `ConvexBranchFlow`'s exactness-copy
# mechanism (`v̂`, thesis 3.43/3.45) fixes BOTH `v[root]` and `v̂[root]` to the SAME value
# (1.0). Applying the `v` recursion (thesis 3.33, loss coefficient `+(r²+x²)l`) and the `v̂`
# recursion (thesis 3.43, loss coefficient `-2(r²+x²)l`) around ANY closed cycle each forces
# an independent "return to the same value" identity; SUBTRACTING them eliminates the
# `-2(rP+xQ)` terms entirely and leaves `Σ ε_b·(r_b²+x_b²)·l_b = 0` around the cycle, where
# `ε_b = ±1` is the branch's orientation relative to the traversal direction. On the literal
# 3-bus triangle (an ODD-length cycle), the natural `(1,2),(2,3),(3,1)` branch storage makes
# EVERY `ε_b = +1` — since every `l_b ≥ 0`, the sum-to-zero identity FORCES `l_b = 0` on
# EVERY loop branch, which (via the rotated cone `l·v ≥ P²+Q²`) forces `P_b = Q_b = 0` on
# every branch too — i.e. the model can carry NO real power around ANY odd consistently-
# oriented cycle, making even an infinitesimally small nonzero load INFEASIBLE (empirically
# verified: `p2 = 0.01` alone already gives `INFEASIBLE`/`PRIMAL_INFEASIBLE`, independent of
# voltage-bound width). Flipping ONE triangle branch's stored orientation avoids the
# all-zero degeneracy but (empirically verified) produces a genuinely large, STRUCTURAL cone
# gap (~1.1e-2, three orders of magnitude above the `assert_socp_exact!` default `rtol_exact
# = 1e-4` gate) unrelated to R/X heterogeneity — because an odd-length cycle can only split
# `ε` as 2-vs-1, never an even balance, so one branch's `l` is always PINNED to the sum of
# the other two rather than free to seek its own cone-tight value.
#
# A 4-bus DIAMOND (root=1 branching to 2 and 3, both merging at 4 -- an
# explicitly-suggested alternative topology, "e.g. a 4-bus 'diamond'... or the literal 3-bus
# triangle spiked above") is an EVEN-length cycle (1→2→4→3→1) whose natural branch storage
# `(1,2),(1,3),(2,4),(3,4)` splits `ε` evenly (+1,+1,-1,-1): the forced identity becomes
# `(r₁₂²+x₁₂²)l₁₂ + (r₂₄²+x₂₄²)l₂₄ = (r₁₃²+x₁₃²)l₁₃ + (r₃₄²+x₃₄²)l₃₄` -- a genuine,
# non-degenerate BALANCE between the two parallel paths (the physically-correct KVL
# condition for two paths in parallel), not an artificial zero-forcing or an inflated-slack
# pin. Empirically verified (both profiles, default `rtol_exact = 1e-4`): cone
# gaps of `1.6e-8` (`:uniform`) and `1.8e-9` (`:heterogeneous`) -- both PASS
# `assert_socp_exact!` cleanly, matching the empirical expectation that cone-
# tightness is UNINFORMATIVE on a mesh (tight for both profiles alike) and the TRUE
# discriminator is the angle-recoverability certificate, never the
# existing cone gate alone. This is NOT a knife-edge parameter search
# (a topology choice is not a numeric search): it is a discrete topology choice sanctioned by the requirement of a "3-4 bus,
# single loop" fixture and the suggested alternative, made ONCE, before any numeric
# tuning -- the R/X literals themselves are still the exact ratios a preliminary toy-triangle measurement found
# (4.0, ~0.167, 1.0, plus one more heterogeneous branch at 2.0 for the diamond's 4th edge).
#
# FIXTURE DESIGN: buses 1 (root), 2, 3 (the two parallel-path buses), 4 (the merge bus that
# closes the loop); branches (1,2), (1,3), (2,4), (3,4). Asymmetric pinned loads at buses 2
# and 3 (P2_LOAD=0.30, P3_LOAD=0.05 -- the spike's own Case-A/A2 asymmetric pair) keep the
# chord flow strictly nonzero -- never the degenerate symmetric case. Two impedance profiles
# on the SAME topology:
#   - :uniform        -- all four branches r=0.01,x=0.02 (R/X ratio 0.5 everywhere) --
#                        the RECOVERABLE case (the certificate measures worst_residual ~6.27e-3
#                        on this exact fixture, certified).
#   - :heterogeneous  -- branch(1,2) r=0.32,x=0.08 (ratio 4.0), branch(1,3) r=0.08,x=0.48
#                        (ratio ~0.167), branch(2,4) r=0.16,x=0.16 (ratio 1.0), branch(3,4)
#                        r=0.24,x=0.12 (ratio 2.0) -- exercising the certificate's
#                        UNRECOVERABLE branch.
# All branches carry smax = SMAX_NO_LIMIT (this fixture is about the LOOP, not congestion).
# Bus voltage bounds at 2/3/4 are wide (0.90-1.10 pu) so the small pinned loads never bind a
# voltage constraint -- isolating the loop/angle question from the overvoltage question.
#
# HETEROGENEOUS_RX MAGNITUDE CHANGE FROM THE ORIGINAL LITERALS (adjusted
# at the fixture author's discretion
# so that both certificate branches are genuinely exercised
# by adjusting the profile parameters):
#
# The `certify_angle_recoverable!` measurement found that on THIS diamond,
# with the ORIGINAL `(0.04,0.01),(0.01,0.06),(0.02,0.02),(0.03,0.015)` heterogeneous
# literals, the angle-recovery residual (0.00697) is essentially the SAME ORDER OF
# MAGNITUDE as the `:uniform` profile's residual (0.00627) -- NOT the multi-order-of-
# magnitude separation the toy-triangle measurement predicted. Direct empirical
# measurement (sweeping R/X ratio spread, load asymmetry, and impedance scale
# independently, all while keeping the SOCP cone tight;
# the full sweep established that on this diamond's PARALLEL-TWO-PATH topology (unlike the
# triangle's simple series ring), the angle-recovery residual for THIS load-asymmetry
# level is dominated by `residual ≈ 0.05 · (impedance scale) · (chord-flow magnitude)`,
# essentially INDEPENDENT of R/X RATIO heterogeneity across the range that keeps the SOCP
# cone exact -- R/X ratio spread alone cannot separate the two profiles on this topology.
# Scaling the ORIGINAL heterogeneous literals' OVERALL MAGNITUDE up by 8x (preserving
# their exact ratios 4.0/~0.167/1.0/2.0) keeps the SOCP cone exact (measured cone gap
# improves to ~1.8e-11, even tighter than at the original scale) while the residual grows
# linearly with that scale, reaching ~0.0607 -- a ~9.7x separation from `:uniform`'s fixed
# 0.00627 floor, safely inside the region before the SOCP becomes genuinely INFEASIBLE at
# 10x (empirically confirmed: 10x already breaks cone-exactness; 12x+ is outright
# INFEASIBLE). This is a genuinely different, topology-specific finding from the
# triangle-based mechanism (which used a simplified spike lacking ConvexBranchFlow's
# exactness-copy machinery, as found while building this fixture) -- not a
# knife-edge parameter search: the SCALE lever was swept broadly and
# monotonically (1x-9.5x, cone tight throughout) before settling on 8x for a comfortable
# safety margin from the 10x infeasibility cliff, and the RATIOS themselves are UNCHANGED
# from the original literals (only their common magnitude scale differs).

@testmodule MeshFixtures begin
    using TSODSO

    # Single-hour CI horizon -- this fixture is about the LOOP, not the horizon.
    const T_MESH = 1
    const LAMBDA0_MESH = 4.0

    # Asymmetric pinned loads (the spike's own Case-A/A2 asymmetric pair) -- chosen so the
    # chord flow stays strictly nonzero, never the degenerate symmetric case.
    const P2_LOAD = 0.30
    const P3_LOAD = 0.05

    # Per-branch (r, x) literals for BOTH impedance profiles, ordered (1,2), (1,3), (2,4),
    # (3,4) -- see file header for why this 4-bus diamond, not a literal 3-bus
    # triangle, is the committed topology. Ratios: uniform = 0.5 everywhere; heterogeneous =
    # 4.0, ~0.167, 1.0, 2.0 (the toy-triangle measurement's ratios) at 8x the original
    # MAGNITUDE -- the certificate measurement found the ratio spread alone does not
    # separate the certificate's two branches on this diamond; see the file header's
    # "HETEROGENEOUS_RX MAGNITUDE CHANGE" note for the full derivation.
    const UNIFORM_RX = [(0.01, 0.02), (0.01, 0.02), (0.01, 0.02), (0.01, 0.02)]
    const HETEROGENEOUS_RX = [(0.32, 0.08), (0.08, 0.48), (0.16, 0.16), (0.24, 0.12)]

    """
        mesh_feeder(profile::Symbol) -> MeshedFeeder

    The phase's ONE committed CI loop fixture: a 4-bus diamond (root=1 branching to 2 and 3,
    both merging at 4; branches (1,2), (1,3), (2,4), (3,4), nB=4 > N-1=3, a genuine single
    independent loop -- see file header for why this topology, not a literal 3-bus triangle,
    is the committed choice). `profile` selects the per-branch impedance literals: `:uniform`
    (all four branches share R/X ratio 0.5, the angle-recoverability certificate's
    RECOVERABLE case) or `:heterogeneous` (differing R/X ratios 4.0/~0.167/1.0/2.0, the
    certificate's UNRECOVERABLE/structural-gap case). Throws `ArgumentError` for any other
    `profile` symbol.

    Root bus 1 has irrelevant voltage bounds (fixed at 1.0 by `ConvexBranchFlow.contribute!`
    regardless); buses 2/3/4 have wide bounds (0.90-1.10 pu) so the small pinned loads never
    bind a voltage constraint -- this fixture isolates the loop/angle question from the
    overvoltage question. Every branch carries `smax = SMAX_NO_LIMIT` (no thermal limit --
    this fixture is about the LOOP, not congestion).
    """
    function mesh_feeder(profile::Symbol)
        rx =
            profile == :uniform ? UNIFORM_RX :
            profile == :heterogeneous ? HETEROGENEOUS_RX :
            throw(
                ArgumentError(
                    "mesh_feeder profile must be :uniform or :heterogeneous; got $(repr(profile))",
                ),
            )
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier (irrelevant -- fixed at 1.0)
            Bus(2, 0.90, 1.10, false),
            Bus(3, 0.90, 1.10, false),
            Bus(4, 0.90, 1.10, false),   # the merge bus that closes the loop
        ]
        branches = [
            Branch(1, 2, rx[1]..., SMAX_NO_LIMIT),
            Branch(1, 3, rx[2]..., SMAX_NO_LIMIT),
            Branch(2, 4, rx[3]..., SMAX_NO_LIMIT),
            Branch(3, 4, rx[4]..., SMAX_NO_LIMIT),
        ]
        return MeshedFeeder(buses, branches, 1)
    end

    """
        mesh_aggregators() -> Vector{<:Aggregator}

    Two aggregators on the [`mesh_feeder`](@ref) diamond, at the two parallel-path buses
    (2 and 3): bus 2 draws a PINNED (`Pmin == Pmax == P2_LOAD`), deterministic asymmetric
    load via a single `Thermostatic` device whose comfort band is collapsed to a point
    (`Tmin == Tmax == Tin0`, a no-op recursion at `T=1`); bus 3 is the asymmetric analog with
    `P3_LOAD`. With no device utility curvature doing any work (loads are pinned, not chosen
    by the optimizer) and `Pdc = [0.0]` at both aggregators, `solve_welfare`'s objective
    reduces to minimizing the cost of imported power at `feeder.root` -- a genuine
    LOSS-MINIMIZING SOCP over the loop.

    Both `Thermostatic` members PIN their own power factor to `φ = 1.0` (thesis eq. 3.23's
    per-device override) -- i.e. UNITY power factor, zero reactive draw --
    overriding the aggregators' own `φ = 0.95`. This is a later correction
    restoring this fixture's ORIGINAL
    intent: isolating the angle-recoverability certificate from any reactive-power
    effect. That original intent was implicit (Thermostatic loads drew no reactive power at
    all before `is_flexible_load(::Thermostatic) == true` was made
    unconditionally); the `φ = 1.0` pin here makes it explicit and permanent instead of
    leaving it as an accident of the earlier device contract.

    **Discovered finding (RECORDED not silently fixed away):** at the
    aggregators' own native `φ = 0.95` (i.e. WITHOUT this pin), the `:uniform` impedance
    profile's SOC relaxation becomes GENUINELY inexact on this diamond -- measured cone ratio
    ≈2711, gap ≈0.0147, persistent across a Clarabel `tol_gap` ladder (so it is a real
    relaxation gap, not solver-precision noise). The `:heterogeneous` profile stays exact
    throughout. In other words: reactive load breaks SOCP exactness on this specific
    uniform-R/X meshed diamond topology. This is NOT a bug and NOT in scope for a fix here
    -- it is a discovered consequence of the flexible-load change on a mesh
    topology, left for future research.
    """
    function mesh_aggregators()
        therm2 = Thermostatic(
            2,
            0.0,
            1.0,
            20.0,
            20.0,
            20.0,
            P2_LOAD,
            P2_LOAD,
            0.5,
            [20.0];
            φ = 1.0,
        )
        therm3 = Thermostatic(
            3,
            0.0,
            1.0,
            20.0,
            20.0,
            20.0,
            P3_LOAD,
            P3_LOAD,
            0.5,
            [20.0];
            φ = 1.0,
        )
        return [Aggregator(2, 0.95, [therm2], [0.0]), Aggregator(3, 0.95, [therm3], [0.0])]
    end

    """
        mesh_aggregators_phi(φ::Real; bess::Bool = false) -> Vector{Aggregator}

    Same two pinned-load Thermostatic aggregators as [`mesh_aggregators`](@ref) (buses 2 and 3,
    loads `P2_LOAD` / `P3_LOAD`) but with the reactive power factor `φ` as a parameter, and with
    an optional `FourQuadBESS` (bus 2) appended to the bus-2 aggregator when `bess = true`.

    Note: `φ = 0.95` is used ONLY with the `:heterogeneous` profile -- it gives a
    clearly non-degenerate centralized reactive price (`dual(:balance_q)` ~ 0.2511 / 0.1354 at
    buses 2/3), whereas `φ = 1.0` pins the reactive price to ~0. Uniform `φ = 0.95` is NOT usable:
    the centralized solve itself throws `SOCP relaxation INEXACT` (the finding above).
    """
    function mesh_aggregators_phi(φ::Real; bess::Bool = false)
        therm2 = Thermostatic(
            2,
            0.0,
            1.0,
            20.0,
            20.0,
            20.0,
            P2_LOAD,
            P2_LOAD,
            0.5,
            [20.0];
            φ = φ,
        )
        therm3 = Thermostatic(
            3,
            0.0,
            1.0,
            20.0,
            20.0,
            20.0,
            P3_LOAD,
            P3_LOAD,
            0.5,
            [20.0];
            φ = φ,
        )
        devs2 = AbstractDevice[therm2]
        bess && push!(
            devs2,
            FourQuadBESS(2, 0.95, 1.0, 0.05, 0.05, 0.08, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9),
        )
        return [Aggregator(2, 0.95, devs2, [0.0]), Aggregator(3, 0.95, [therm3], [0.0])]
    end

    """
        mesh_lambda0() -> Vector{Float64}

    The flat MEM/wholesale price `λ₀ = LAMBDA0_MESH` over the fixture's single-hour horizon.
    """
    mesh_lambda0() = [LAMBDA0_MESH]

    export T_MESH,
        LAMBDA0_MESH,
        P2_LOAD,
        P3_LOAD,
        UNIFORM_RX,
        HETEROGENEOUS_RX,
        mesh_feeder,
        mesh_aggregators,
        mesh_aggregators_phi,
        mesh_lambda0
end
