# src/models/mesh_angle_certificate.jl
#
# SEAM: angle-recoverability a-posteriori certificate (MESH-03).
# OWNER: plan 23-03.
#
# A NEW sibling to models/ac_oracle.jl (NOT a modification of it — RESEARCH's own
# "Critical codebase finding": `recover_voltage_angles` is SILENTLY loop-blind, its
# `visited[j] && continue` BFS guard drops the exact branch that would close a cycle with
# no error). This file generalizes that BFS with EXPLICIT chord tracking plus a per-chord
# closure-residual check — the direct phasor-domain operationalization of Farivar-Low's
# angle-recovery condition ("the implied angle differences sum to zero mod 2π around each
# cycle," arXiv:1204.4865) — the ONLY mechanism that can distinguish a genuine AC operating
# point from a loop-inconsistent one on a meshed context, since both pass the EXISTING
# per-branch cone gate (`assert_socp_exact!`) identically (RESEARCH Pitfall 14, empirically
# reproduced on this fixture in plan 23-02).
#
# `certify_angle_recoverable!` is REPORT-BY-DEFAULT (`report::Bool = true`), a DELIBERATE,
# DOCUMENTED divergence from this codebase's certificate-family convention
# (`assert_socp_exact!`, `assert_ac_exact!`, `assert_restriction_exact!` all throw by
# default) — because "unrecoverable" is a first-class SCIENTIFIC FINDING here (D-05), not a
# defect to refuse by default the way a strict SOC cone is. An opt-in `report = false`
# strict/throw mode still exists for a caller that wants the family's usual hard gate.
#
using JuMP

"""
    certify_angle_recoverable!(ctx::ModelContext; atol::Real = 0.02, rtol::Real = 0.02,
                                report::Bool = true)
        -> (; recoverable::Bool, worst_residual::Float64, status::Symbol,
             angles::Union{Matrix{ComplexF64},Nothing})

Certify that a solved meshed branch-flow `ModelContext`'s implied voltage-ANGLE field is
RECOVERABLE — i.e. that the magnitude-only `(v,P,Q,l)` SOCP solution corresponds to a
genuine, angle-consistent AC operating point (Farivar-Low's angle-recovery condition,
Gan-Low's operationalization), not merely a per-branch-cone-tight but globally
loop-inconsistent point (RESEARCH Pitfall 14). This is the ONLY certificate in this
codebase that checks LOOP consistency — `assert_socp_exact!` (models/exactness.jl) is
necessary but NOT sufficient on a mesh: both a genuine AC point and a loop-inconsistent one
pass its per-branch cone gate identically (empirically confirmed on
`Phase23Fixtures.mesh_feeder`: cone gaps `~1.6e-8` (`:uniform`) and `~1.8e-11`
(`:heterogeneous`, this plan's D-08 magnitude-scaled literals — see "Tolerance provenance"
below) — BOTH comfortably tight, yet only `:uniform` is angle-recoverable).

# Report-by-default (D-05 — the deliberate family divergence)

Every OTHER certificate in this codebase (`assert_socp_exact!`, `assert_ac_exact!`,
`assert_restriction_exact!`) THROWS by default: a strict SOC cone, an AC-vs-SOCP mismatch
handled elsewhere, or a physically-infeasible restricted point are treated as DEFECTS to
refuse. Here, "unrecoverable" is not a defect — the SOCP relaxation is provably ALWAYS
conic-feasible on a mesh (Low, arXiv:1405.0814: "for mesh networks, the conic relaxation is
always exact but the angle relaxation may not be exact") and an unrecoverable verdict is
itself the MESH-03 finding: the solved objective remains a valid LOWER BOUND on the true AC
optimum (D-07), worth reporting, not an error worth aborting a run over. `report::Bool =
true` therefore `@warn`s (never throws) on an unrecoverable verdict by default; passing
`report = false` restores the family's usual throw-by-default contract for a caller that
wants a hard gate.

# Algorithm (D-06 — genuine cycle-consistency, never the per-branch cone alone)

Generalizes [`recover_voltage_angles`](@ref)'s traversal (`src/models/ac_oracle.jl:66-112`
— a DFS, despite that file's "BFS" label: `pop!` on a `Vector` is LIFO; any spanning tree
suffices, review IN-01) with EXPLICIT chord tracking, mirroring its signed bidirectional
adjacency (`children[i]` = list of `(neighbor, ±branch_index)`) and its phasor recursion
for a tree edge `i → j` carrying branch `b` (impedance `z = r+jx`, complex power `S`
flowing toward `j`): `V_j = V_i − z·conj(S)/conj(V_i)`. A branch traversed WITH its stored
orientation contributes its own sending-end flow, `S = S_b = P_b + jQ_b` (measured at
`br.from`). A branch traversed AGAINST its stored orientation (`bsigned < 0`) contributes
the negated RECEIVING-end flow `S = −(S_b − z·ℓ_b)` — the flow toward the child, measured
at the parent, which here is the branch's own `to` end where this project charges the loss
(`ConvexBranchFlow`'s KCL convention). A bare sign flip `−S_b` alone would be off by the
branch's own `|z|²·ℓ_b/|V|` per backward edge — the Phase-20 CR-01 bug class (see
[`recover_lossfree_shadow_voltage`](@ref)'s "Branch orientation" note), material on this
fixture's `:heterogeneous` impedances (`~0.002–0.015`, the same order as the certified
residuals; review 23 CR-01). NOTE: `recover_voltage_angles` itself still carries the bare
flip (byte-locked this phase, D-09 — negligible on its lightly-impedanced radial fixtures,
`~1e-5`; flagged for a follow-up plan rather than silently diverging from its "verbatim"
claim). The chord-tracking addition: the instant a branch `b` is used to reach an unvisited
bus, `tree_edges[b]` is marked `true`. Any branch never so marked is a **chord** — for the
committed `Phase23Fixtures.mesh_feeder` diamond (`nB=4`, `N-1=3`) there is exactly one.

For every chord `b` (endpoints `(from, to)`, impedance `z_b`) and every hour `t`: using the
chord's OWN solved `(P_b, Q_b)` (never traversal-sign-flipped — this evaluates the branch's
OWN defining equation, not a tree traversal), predict `V_to,predicted = V_from,tree −
z_b·conj(S_b)/conj(V_from,tree)` where `V_from,tree` is the phasor the traversal already
assigned to the chord's `from` bus, and compare to `V_to,tree` (the traversal-assigned
phasor at the chord's `to` bus — both chord endpoints are on the tree, since the whole graph is
connected). `residual = |V_to,predicted − V_to,tree|`. This operationalizes Farivar-Low's
"the implied angle differences sum to zero mod 2π around each cycle" DIRECTLY in the phasor
domain: a zero residual means the accumulated rotation walking the loop via the tree path
vs. via the chord is exactly the identity.

`worst_residual = maximum(residual over every chord, every t)` (`0.0` if the context is
radial and has no chords at all — a degenerate but well-defined certification: a radial
context handed to this function trivially certifies, since there is nothing to check).
`scale = maximum(abs, Vphasor)` (a magnitude reference over ALL bus phasors, all `t`).
`recoverable = worst_residual <= atol + rtol*scale` — the SAME scale-free `atol +
rtol·magnitude` combined-bound SHAPE every certificate in this codebase uses (WR-01),
copied for STYLE consistency only; the VALUES below are measured fresh on
`Phase23Fixtures`, never reused from a sibling certificate (D-08).

# Output contract (D-07)

- **Recoverable** (`status = :angle_certified`): `angles` is the full `(N,T)`
  `Matrix{ComplexF64}` of traversal-recovered voltage phasors, certified consistent with every
  chord. The solved objective is a genuine AC-operating-point value.
- **Unrecoverable** (`status = :angle_unrecoverable`): `angles === nothing` (this
  certificate's job is ONLY to correctly LABEL the verdict via `status`; it never
  duplicates the objective — a caller reads `objective_value(ctx.model)` itself, which
  remains a valid LOWER BOUND on the true AC optimum, per Low arXiv:1405.0814).

`ctx.meta[:price_provenance]` is stashed UNCONDITIONALLY (both paths), scrubbing any stale
marker FIRST (mirrors `restriction_exactness.jl`'s T-20-08 discipline — before anything
that can throw):

    ctx.meta[:price_provenance] = (; formulation = get(ctx.meta, :formulation, :unknown),
        certificate = :certify_angle_recoverable!, status)

`formulation` is READ from `ctx.meta[:formulation]` (never hardcoded, T-23-06) — the marker
`MeshedFlow.contribute!` stashed for exactly this purpose; a context whose formulation
never stashed the marker (e.g. a plain `ConvexBranchFlow` context) honestly reports
`formulation = :unknown`, never a fabricated `:MeshedFlow`.

# Tolerance provenance (D-08 — measured fresh, never copied from a sibling certificate)

Measured on `Phase23Fixtures.mesh_feeder` (`test/fixtures_phase23.jl`, the committed 4-bus
diamond), both impedance profiles, solved via `MeshedFlow()` + `solve_welfare`
(2026-08-10): the `:uniform` profile's raw `worst_residual` is `≈6.27e-3`; the
`:heterogeneous` profile's raw `worst_residual` is `≈6.07e-2` — a genuine, measured
**≈9.7×** separation, NOT the multi-order-of-magnitude gap RESEARCH.md's unrelated
standalone toy-triangle spike observed (`1e-5`/`5.8e-3`, a DIFFERENT topology, DIFFERENT
per-unit values, and — per plan 23-02's own finding — a simplified spike that omitted
`ConvexBranchFlow`'s exactness-copy machinery; never reused here per D-08).

**A genuine, topology-specific finding (documented in full in `test/fixtures_phase23.jl`'s
header comment and this plan's SUMMARY):** on THIS diamond's two-parallel-2-hop-path
topology (as opposed to the triangle's simple series ring), direct empirical measurement
(sweeping R/X ratio spread, load asymmetry, and impedance scale independently, all while
keeping `assert_socp_exact!`'s cone tight) found the angle-recovery residual is dominated
by `residual ≈ 0.05 · (impedance scale) · |chord-flow|`, essentially **independent of R/X
RATIO heterogeneity** across the range that keeps the SOCP cone exact — ratio spread alone
does not separate the two profiles on this topology. The committed `:heterogeneous`
profile instead scales the ORIGINAL R/X-ratio literals' overall MAGNITUDE up 8× (preserving
their exact ratios 4.0/~0.167/1.0/2.0) — the SOCP cone stays exact (even tighter,
`~1.8e-11`) throughout that range, up to a genuine INFEASIBILITY cliff at 10×, giving the
measured `≈9.7×` residual separation with a comfortable safety margin from that cliff.

Defaults are centered roughly at the GEOMETRIC MEAN of the two measured floors (a
DELIBERATE departure from `assert_4q_complementarity!`'s "~10× the recoverable floor"
sizing discipline, which here would collide with the `:heterogeneous` floor since the
measured separation is under 2 orders of magnitude — see above): `atol = 0.02` and
`rtol = 0.02` (the fixture's phasor `scale ≈ 1.0` per-unit, so the combined bound
`atol + rtol·scale ≈ 0.04` sits almost exactly between the two measured floors). At these
defaults the `:uniform` profile certifies with a `≈6.4×` margin (`0.00627 ≪ 0.04`) and the
`:heterogeneous` profile's `worst_residual` (`≈0.0607`) sits a clean `≈1.5×` ABOVE the
bound — `recoverable = false`, the honest structural gap (D-10) ships as the deliverable,
never chased away by further parameter tuning.

Reads `ctx.meta[:feeder]`, `ctx.meta[:T]`, `ctx.meta[:pf_vars]` (the `(; v, v̂, P, Q, l)`
stash `ConvexBranchFlow.contribute!` populates — `MeshedFlow` delegates to it verbatim,
plan 23-02) — identical inputs to [`recover_voltage_angles`](@ref). Uses an explicit
`error(...)`/`@warn(...)` (never `@assert`, elided under `-O`), per project convention
(`src/core/status.jl`).
"""
function certify_angle_recoverable!(
    ctx::ModelContext;
    atol::Real = 0.02,
    rtol::Real = 0.02,
    report::Bool = true,
)
    # T-20-08-style discipline (review WR-02): scrub any stale provenance marker FIRST,
    # before anything that can throw.
    delete!(ctx.meta, :price_provenance)

    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)
    nB = length(feeder.branches)

    # Signed bidirectional adjacency -- mirrors ac_oracle.jl's recover_voltage_angles
    # verbatim (children[i] = list of (neighbor_bus, signed_branch_index)).
    children = [Tuple{Int, Int}[] for _ in 1:N]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b))
        push!(children[br.to], (br.from, -b))
    end

    # Recover phasors along a DFS spanning tree (pop! on a Vector is LIFO -- a depth-first
    # walk, review IN-01; any spanning tree suffices) using recover_voltage_angles's
    # recursion with TWO deliberate changes relative to ac_oracle.jl:
    #  (1) chord tracking (RESEARCH's algorithm spec): tree_edges[b] = true is marked the
    #      instant branch b is used to reach an unvisited bus. tree_edges is purely
    #      topological (independent of t, since the traversal order never depends on the
    #      solved values), so re-marking it identically on every t is harmless.
    #  (2) backward-edge flow correction (review 23 CR-01): a branch traversed AGAINST its
    #      stored orientation uses the negated RECEIVING-end flow -(S_b - z*l_b), never the
    #      bare flip -S_b that recover_voltage_angles still carries (byte-locked this
    #      phase, D-09; flagged for follow-up) -- see the docstring's Algorithm section.
    tree_edges = falses(nB)
    Vphasor = Matrix{ComplexF64}(undef, N, T)
    for t in 1:T
        Vphasor[feeder.root, t] = sqrt(value(pv.v[feeder.root, t])) + 0.0im

        visited = falses(N)
        visited[feeder.root] = true
        queue = [feeder.root]
        while !isempty(queue)
            i = pop!(queue)
            for (j, bsigned) in children[i]
                visited[j] && continue
                b = abs(bsigned)
                tree_edges[b] = true   # chord tracking: the ONE addition vs. ac_oracle.jl
                br = feeder.branches[b]
                z = Complex(br.r, br.x)
                S = if bsigned > 0
                    Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
                else
                    # Receiving-end flow at the parent (the loss z·l is charged at the
                    # branch's own `to` end), negated toward the child: −(S_b − z·l_b).
                    # A bare sign flip −S_b alone would be off by the branch's own
                    # |z|²·l_b/|V| — the Phase-20 CR-01 lesson
                    # (recover_lossfree_shadow_voltage's "Branch orientation" note), here
                    # in the phasor domain (review 23 CR-01).
                    -(Complex(value(pv.P[b, t]), value(pv.Q[b, t])) - z * value(pv.l[b, t]))
                end
                Vphasor[j, t] = Vphasor[i, t] - z * conj(S) / conj(Vphasor[i, t])
                visited[j] = true
                push!(queue, j)
            end
        end
    end

    # Chords: every branch never used as a tree edge. For the committed diamond (nB=4,
    # N-1=3) there is exactly one; the algorithm generalizes to nB-(N-1) chords for a
    # future multi-loop fixture (MESH-STRETCH).
    chords = findall(!, tree_edges)

    # Per-chord closure residual (D-06's genuine cycle-consistency check): evaluate the
    # chord's OWN defining branch-flow equation using its OWN solved (P,Q) -- never
    # traversal-sign-flipped, this is the branch's own (from -> to) direction by
    # construction -- from the tree-recovered phasor at its `from` endpoint, and compare to
    # the tree-recovered phasor already assigned to its `to` endpoint.
    worst = 0.0
    worst_chord = 0
    worst_t = 0
    for b in chords, t in 1:T
        br = feeder.branches[b]
        z = Complex(br.r, br.x)
        S_b = Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
        V_from = Vphasor[br.from, t]
        V_to_predicted = V_from - z * conj(S_b) / conj(V_from)
        residual = abs(V_to_predicted - Vphasor[br.to, t])
        if residual > worst
            worst = residual
            worst_chord = b
            worst_t = t
        end
    end

    # Magnitude reference over ALL bus phasors, all t (WR-01's scale-free philosophy).
    scale = maximum(abs, Vphasor)
    recoverable = worst <= atol + rtol * scale
    status = recoverable ? :angle_certified : :angle_unrecoverable
    angles = recoverable ? Vphasor : nothing

    # D-08-style provenance, stashed UNCONDITIONALLY (both the pass and fail path), keyed
    # on the recoverability verdict. formulation is READ, never hardcoded (T-23-06).
    ctx.meta[:price_provenance] = (;
        formulation = get(ctx.meta, :formulation, :unknown),
        certificate = :certify_angle_recoverable!,
        status,
    )

    if !recoverable
        chord_br = feeder.branches[worst_chord]
        msg =
            "Meshed SOCP angle-recovery FAILED (worst_residual=$worst at chord branch " *
            "b=$worst_chord, bus $(chord_br.from)->$(chord_br.to), hour t=$worst_t; " *
            "atol=$atol, rtol=$rtol, scale=$scale): the SOCP objective is a valid LOWER " *
            "BOUND only, NOT a certified AC operating point (Gan-Low angle-recovery " *
            "condition; MESH-03)."
        report ? (@warn msg) : error(msg)
    end

    return (; recoverable, worst_residual = worst, status, angles)
end

export certify_angle_recoverable!
