# # Rung 10 — Meshed Networks + Live Reactive Price
#
# Every prior "Models" page in this manual — every rung from Rung 0's toy DC feeder through
# Rung 9's stochastic extensive form — solves a genuinely RADIAL feeder: `Feeder`/`assert_radial`
# admit only a tree (`nB == N-1`). This page fills Phase 23's meshed slot (SEAM-01) with a
# genuine LOOP topology, solved through the SAME `ConvexBranchFlow` constraint set (KCL,
# v-drop, rotated cone, exactness copy, apparent-power cone) via [`MeshedFlow`](@ref)'s pure
# delegation (D-03) — the formulation itself required zero new constraint-writing code. What
# genuinely IS new is validation: a meshed relaxation's SOCP is provably ALWAYS conic-feasible
# (Low, arXiv:1405.0814), so the existing per-branch cone gate (`assert_socp_exact!`) cannot,
# by itself, tell a genuine AC operating point apart from a loop-inconsistent one (RESEARCH
# Pitfall 14) — that is exactly the gap [`certify_angle_recoverable!`](@ref) (MESH-03) closes.
# Section 3 then combines this meshed loop with Phase 19's 4Q-BESS device to read a LIVE
# reactive price directly off the meshed network's own centralized `:balance_q` dual
# (MESH-06/D-04), then runs the decomposed meshed ADMM (`solve_admm(feeder, MeshedFlow(), aggs;
# reactive_consensus = ReactiveMode.LIVE, ...)`) next to it and cross-validates the two live — closing the
# v3.0 MESH-06 advisory.
#
# Every number shown below is RECOMPUTED live during this page's build, exactly like every
# prior rung page in this manual.

using TSODSO, JuMP

# ## Building the 4-bus diamond loop fixture (D-02/D-10)
#
# **Honest deviation, documented here rather than smoothed over:** this phase's OWN plan text
# originally called for a literal 3-bus triangle (branches `(1,2),(2,3),(3,1)`). Plan 23-02
# discovered — and empirically confirmed — that topology is mathematically INCOMPATIBLE with
# `MeshedFlow`'s mandated pure delegation to `ConvexBranchFlow.contribute!`: `ConvexBranchFlow`
# fixes both the true squared-voltage `v[root]` and its exactness-copy `v̂[root]` to the SAME
# value, and subtracting the `v`/`v̂` phasor-magnitude recursions around ANY closed cycle forces
# `Σ ε_b·(r_b²+x_b²)·l_b = 0`. On an ODD, consistently-oriented cycle (the literal triangle)
# every `ε_b = +1`, so — since every loss `l_b ≥ 0` — the identity forces `l_b = 0` on EVERY
# loop branch, which forces `P_b = Q_b = 0` too: the model can carry NO real power around such
# a cycle, and even an infinitesimal asymmetric load is `INFEASIBLE` (reproduced live just
# below). The committed fixture is instead a 4-bus **diamond** — root 1 branching to buses 2
# and 3, both merging at bus 4 — RESEARCH.md's own explicitly-suggested alternative topology.
# Its cycle (`1→2→4→3→1`) is EVEN-length with an even `ε` split (`+1,+1,-1,-1`), turning the
# forced identity into a genuine, non-degenerate BALANCE between the two parallel paths rather
# than a zero-forcing pin. `MeshedFlow.contribute!` itself needed zero changes — this is a
# fixture-topology choice, never a formulation change.

const T_MESH = 1
const LAMBDA0_MESH = [4.0]

## Asymmetric pinned loads (never the degenerate symmetric case, D-10) — chosen so the
## diamond's chord flow stays strictly nonzero, exactly `MeshFixtures`'s own committed
## values.
const P2_LOAD = 0.30
const P3_LOAD = 0.05

## Per-branch `(r, x)` literals, ordered `(1,2), (1,3), (2,4), (3,4)` — byte-identical to
## `test/fixtures_mesh.jl`'s committed `MeshFixtures` module (reconstructed inline here,
## never `include()`d, mirroring every prior rung page's own self-contained construction).
## `:uniform` — R/X ratio 0.5 on all four branches. `:heterogeneous` — ratios
## 4.0 / ~0.167 / 1.0 / 2.0 (RESEARCH.md's own spike ratios), at 8x their original spike
## MAGNITUDE — plan 23-03 measured that ratio spread ALONE does not separate the certificate's
## two branches on this diamond's parallel-two-path topology; impedance MAGNITUDE is the
## genuine, cone-exactness-preserving lever (see Section 2 below).
const UNIFORM_RX = [(0.01, 0.02), (0.01, 0.02), (0.01, 0.02), (0.01, 0.02)]
const HETEROGENEOUS_RX = [(0.32, 0.08), (0.08, 0.48), (0.16, 0.16), (0.24, 0.12)]

function diamond_feeder(profile::Symbol)
    rx = profile == :uniform ? UNIFORM_RX : HETEROGENEOUS_RX
    buses = [
        Bus(1, 0.95, 1.05, true),   # root — fixed at 1.0 by ConvexBranchFlow.contribute! regardless
        Bus(2, 0.90, 1.10, false),
        Bus(3, 0.90, 1.10, false),
        Bus(4, 0.90, 1.10, false),  # the merge bus that closes the loop
    ]
    branches = [
        Branch(1, 2, rx[1]..., SMAX_NO_LIMIT),
        Branch(1, 3, rx[2]..., SMAX_NO_LIMIT),
        Branch(2, 4, rx[3]..., SMAX_NO_LIMIT),
        Branch(3, 4, rx[4]..., SMAX_NO_LIMIT),
    ]
    return MeshedFeeder(buses, branches, 1)
end

## Plan 26-13 pin (PM-04, `26-POSTMERGE-TRIAGE.md` cluster G): both loads pin their OWN power
## factor to phi=1.0 (unity, zero reactive draw), overriding the aggregators' own phi=0.95,
## restoring this fixture's original MESH-02/03 zero-reactive-draw intent -- see
## `test/fixtures_mesh.jl`'s `mesh_aggregators()` docstring (Plan 26-13) for the identical
## pin and the discovered finding it documents: at phi=0.95, the `:uniform` profile's SOC
## relaxation becomes genuinely inexact on this diamond (cone ratio ~2711, gap ~0.0147).
therm2 = Thermostatic(2, 0.0, 1.0, 20.0, 20.0, 20.0, P2_LOAD, P2_LOAD, 0.5, [20.0]; φ = 1.0)
therm3 = Thermostatic(3, 0.0, 1.0, 20.0, 20.0, 20.0, P3_LOAD, P3_LOAD, 0.5, [20.0]; φ = 1.0)

# The odd, consistently-oriented triangle really is infeasible on this delegation path — shown
# live, once, so this claim is never a hand-typed assertion:

triangle_buses =
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.90, 1.10, false), Bus(3, 0.90, 1.10, false)]
triangle_branches = [
    Branch(1, 2, 0.01, 0.02, SMAX_NO_LIMIT),
    Branch(2, 3, 0.01, 0.02, SMAX_NO_LIMIT),
    Branch(3, 1, 0.01, 0.02, SMAX_NO_LIMIT),
]
triangle_feeder = MeshedFeeder(triangle_buses, triangle_branches, 1)
triangle_infeasible = try
    solve_welfare(
        triangle_feeder,
        MeshedFlow(),
        [Aggregator(2, 0.95, [therm2], [0.0]), Aggregator(3, 0.95, [therm3], [0.0])];
        T = T_MESH,
        λ₀ = LAMBDA0_MESH,
    )
    false   # the reached-on-regression path: a solved triangle means the derivation above no longer holds
catch e
    e isa SolveFailedError && occursin("INFEASIBLE", sprint(showerror, e))
end

triangle_infeasible

#-

## Self-checking page (review WR-02): the prose below states this value as fact, so the
## docs build must FAIL, loudly, if the live claim ever regresses (a solvable triangle, a
## changed failure message, or a non-ErrorException all land on `false` above).
triangle_infeasible || error(
    "Rung 10 doc regression: the odd triangle solved -- the degeneracy derivation no longer holds",
);

# `triangle_infeasible === true` above confirms, live, that the literal odd-triangle topology
# genuinely fails to solve (`PRIMAL_INFEASIBLE`) on this delegation path, exactly as derived
# above — and the guard just executed turns any future regression of that claim into a
# docs-build failure. The committed diamond fixture below has no such degeneracy.

# ## 1. Solving via MeshedFlow (MESH-02)
#
# Both impedance profiles solve `OPTIMAL` on the diamond. Both ALSO pass the EXISTING
# per-branch cone gate (`assert_socp_exact!`, stashed at `ctx.meta[:socp_maxgap]`) — Pitfall
# 14's point made concrete: this gate alone cannot distinguish the two profiles, since it is
# tight for both alike.

aggregators_plain =
    [Aggregator(2, 0.95, [therm2], [0.0]), Aggregator(3, 0.95, [therm3], [0.0])]

ctx_u, obj_u, dadp_u = solve_welfare(
    diamond_feeder(:uniform),
    MeshedFlow(),
    aggregators_plain;
    T = T_MESH,
    λ₀ = LAMBDA0_MESH,
)

(termination_status(ctx_u.model), obj_u, ctx_u.meta[:socp_maxgap])

#-

ctx_h, obj_h, dadp_h = solve_welfare(
    diamond_feeder(:heterogeneous),
    MeshedFlow(),
    aggregators_plain;
    T = T_MESH,
    λ₀ = LAMBDA0_MESH,
)

(termination_status(ctx_h.model), obj_h, ctx_h.meta[:socp_maxgap])

# Both `socp_maxgap`s above are comfortably under `assert_socp_exact!`'s default
# `rtol_exact = 1e-4` gate — tight for BOTH profiles alike, matching RESEARCH.md's own claim
# that cone-tightness is uninformative on a mesh. Something else is needed to tell them apart.

# ## 2. The angle-recoverability certificate (MESH-03, D-05/D-06/D-07)
#
# [`certify_angle_recoverable!`](@ref) is that "something else": a chord-aware, a-posteriori
# check of Farivar-Low's angle-recovery condition, operationalized directly on the diamond's
# ONE chord. Report-by-default (`report = true`, the DELIBERATE family divergence, D-05) — an
# unrecoverable verdict is a scientific finding here, never a defect to abort a run over.

r_u = certify_angle_recoverable!(ctx_u; report = true)

(r_u.status, r_u.recoverable, r_u.worst_residual)

#-

r_h = certify_angle_recoverable!(ctx_h; report = true)

(r_h.status, r_h.recoverable, r_h.worst_residual)

#-

## Self-checking page (review WR-02): the "Stated plainly" paragraph and the Finding section
## below state both verdicts as fact -- enforce them, never merely display them.
r_u.status == :angle_certified || error(
    "Rung 10 doc regression: the :uniform profile no longer certifies (status = $(r_u.status))",
)
r_h.status == :angle_unrecoverable || error(
    "Rung 10 doc regression: the :heterogeneous profile is no longer unrecoverable (status = $(r_h.status))",
);

# Stated plainly (D-10): `:uniform` is a genuine AC-RECOVERABLE operating point — its full
# voltage-phasor field (`r_u.angles`) is returned and certified consistent with the diamond's
# one chord. `:heterogeneous` is NOT — `r_h.angles === nothing`, and `objective_value(ctx_h.model)`
# (`obj_h` above) remains a valid UPPER BOUND on the true AC welfare optimum only, never a
# certified AC point: `solve_welfare` MAXIMIZES welfare, and the relaxation's feasible set
# contains every genuine AC operating point, so its maximum can only be ≥ the true AC maximum
# (`W_SOCP ≥ W_AC` — the welfare-maximization mirror of Low's minimization statement,
# arXiv:1405.0814, where a relaxation's optimum lower-bounds the true minimum cost). The
# `@warn` printed above (not an `error`) is exactly this report-don't-throw contract in
# action.

# ## 3. Live reactive price on the meshed loop (MESH-06/D-04)
#
# Rebuild the bus-2 aggregator with a [`FourQuadBESS`](@ref) ADDED alongside its existing
# `Thermostatic` (the project's standard battery price triple, byte-identical to
# `test/fixtures_four_quad_bess.jl`'s own committed values), then re-solve the `:uniform` profile via
# `MeshedFlow`:

bess = FourQuadBESS(2, 0.95, 1.0, 0.05, 0.05, 0.08, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9)
agg2_with_bess = Aggregator(2, 0.95, [therm2, bess], [0.0])
aggregators_bess = [agg2_with_bess, Aggregator(3, 0.95, [therm3], [0.0])]

ctx_bess, obj_bess, dadp_bess = solve_welfare(
    diamond_feeder(:uniform),
    MeshedFlow(),
    aggregators_bess;
    T = T_MESH,
    λ₀ = LAMBDA0_MESH,
)

(termination_status(ctx_bess.model), dadp_bess)

# The angle-recoverability certificate still certifies with the 4Q-BESS present (its presence
# only adds device-level variables/constraints, never network-level ones — D-03/D-04):

bess_status = certify_angle_recoverable!(ctx_bess; report = true).status

#-

## Self-checking page (review WR-02): enforced, not just displayed.
bess_status == :angle_certified || error(
    "Rung 10 doc regression: the :uniform + 4Q-BESS solve no longer certifies (status = $bess_status)",
);

# The reactive DADP at bus 2 is read directly off the meshed network's own `:balance_q`
# constraint dual — the genuine convex dual of the SOLVED meshed SOCP:

q_dadp_bus2 = dual.(ctx_bess.constraints[:balance_q][2, :])

# This is the CENTRALIZED reference for Phase 19's LIVE radial μ-ascent. The decomposed
# counterpart now exists on the mesh too: `solve_admm(feeder, MeshedFlow(), aggs;
# reactive_consensus = ReactiveMode.LIVE, ...)` iterates the reactive dual `μ_j[t]` to consensus, and it is
# cross-validated against the centralized `dual.(ctx_bess.constraints[:balance_q][2, :])` just
# computed (Phase 34, ARCH-06), closing the v3.0 MESH-06 advisory:

r_admm = solve_admm(
    diamond_feeder(:uniform),
    MeshedFlow(),
    aggregators_bess;
    T = T_MESH,
    λ₀ = LAMBDA0_MESH,
    ρ = 10.0,
    ε_abs = 1e-6,
    ε_rel = 1e-5,
    reactive_consensus = ReactiveMode.LIVE,
    maxiter = 500,
)

p_central = [dual(ctx_bess.constraints[:balance_p][j, 1]) for j in (2, 3)]
q_central = [dual(ctx_bess.constraints[:balance_q][j, 1]) for j in (2, 3)]
gap_p = maximum(abs.(vec(r_admm.λ) .- p_central))
gap_q = maximum(abs.(vec(r_admm.mu_q) .- q_central))
gap_w = abs(r_admm.welfare - obj_bess) / max(abs(obj_bess), 1.0)

(status = r_admm.status, iters = r_admm.iters, gap_p = gap_p, gap_q = gap_q, rel_gap_welfare = gap_w)

#-

## Self-checking page: the claim "meshed live ADMM reproduces the centralized duals and
## welfare" is enforced with the Plan 34-10 tolerances (5e-4 price, rtol 1e-4 welfare).
(r_admm.status == :converged && gap_p < 5e-4 && gap_q < 5e-4 && gap_w < 1e-4) || error(
    "Rung 10 doc regression: meshed live ADMM no longer matches the centralized solve " *
    "(status = $(r_admm.status), gap_p = $gap_p, gap_q = $gap_q, rel gap_w = $gap_w)",
);

# **Honest caveat.** On THIS page's diamond (uniform impedance, unity-power-factor loads) the
# centralized reactive price is near-degenerate (about `5e-10` / `2e-3`), so the agreement
# printed above certifies the quantities shown, not a well-conditioned reactive price. The
# non-degenerate check (heterogeneous profile, `φ = 0.95`, centralized reactive prices
# `≈0.25 / 0.14`) lives in `test/test_admm_meshed.jl` and agrees to `≈6e-5` for
# `ρ₀ ∈ {1, 10, 100}`. See the [status & exception policy](@ref status-policy) for the
# status vocabulary of `solve_admm`.

# ## Finding
#
# **The structural gap is real and topology-specific, not a tuned knife-edge (D-10):** on this
# diamond's parallel-two-path topology, R/X RATIO heterogeneity alone does NOT separate the
# certificate's two branches (a genuinely different, topology-specific finding from
# RESEARCH.md's own triangle-based hypothesis) — Section 2's measured residuals above
# (`r_u.worst_residual ≈ 0.0063` recoverable vs `r_h.worst_residual ≈ 0.0607` unrecoverable, a
# `≈9.7x` separation, matching plan 23-03's own measurement exactly) come from scaling
# `HETEROGENEOUS_RX`'s impedance MAGNITUDE 8x while holding its R/X RATIOS fixed — impedance
# MAGNITUDE, not ratio spread, is the genuine lever (`test/fixtures_mesh.jl`'s own header
# comment documents the full sweep). With the 4Q-BESS additionally present (Section 3), the
# `:uniform` residual shifts slightly (to `≈0.0072`, the device's own reactive dispatch
# perturbs the solved flows a little) but the certificate still certifies comfortably — the
# gap is a genuine property of the network's impedance structure, not an artifact of one
# specific device configuration. The `worst_residual`s above are measured FRESH on this page's
# own live solve, never copied from a prior plan's SUMMARY.
#
# **The anti-feature is honored (D-11):** no IEEE-1547 Volt-VAR droop controller is built
# anywhere on this page, or anywhere in this codebase. The reactive dispatch the SOCP itself
# chose (`bess`'s `q[t]`, buried inside `ctx_bess`) is read and reported here POST-HOC only —
# never a control law imposed on the network. The reactive DADP measured above
# (`q_dadp_bus2`) is genuinely small relative to the active DADP (`dadp_bess`, close to
# `LAMBDA0_MESH`) — an honest finding, reported plainly rather than dressed up: on this small,
# lightly-loaded, primarily-resistive fixture, reactive power carries very little marginal
# value at the SOCP optimum, and the centralized `:balance_q` dual reflects that directly,
# right down to the solver's own numerical floor.
#
# **Scope note:** the MESH-06 advisory (no meshed ADMM) is closed above. A meshed-IEEE-13-with-tie-switch quarantined variant (D-02/D-12,
# MESH-STRETCH) was NOT built this phase — it remains deferred. The single small diamond
# fixture with its two impedance profiles, demonstrated live on this page, is the phase's SOLE
# committed evidence, sufficient for the ROADMAP Phase 23 success criterion "at least one
# committed meshed fixture."
