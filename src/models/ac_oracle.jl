# src/models/ac_oracle.jl
#
# SEAM: AC-exactness oracle post-processing (EXACT-01/02/03); OVR-01/OVR-03 modification-gap
# measurement (plan 20-01).
# OWNER: plan 15-01 (recover_voltage_angles); plan 15-02 (assert_ac_exact!, added to this
#        same file next); plan 20-01 (recover_lossfree_shadow_voltage, OVR-01/OVR-03
#        modification-gap measurement).
#
# A NEW sibling to models/exactness.jl (NOT a modification of it). This file holds the pure
# post-processing over an already-solved branch-flow point — no new JuMP variable, no solver
# involvement:
#
#   - `recover_voltage_angles(ctx)` — a BFS Baran–Wu complex-phasor recursion that recovers the
#     TRUE voltage phasors (magnitude AND angle) from the magnitude-only squared-voltage state
#     `v = |V|²` a solved SOCP/AC branch-flow model carries. This is the ONE genuinely-new piece
#     of math this phase adds (STATE.md flag), so it is validated NUMERICALLY against a
#     hand-derived closed-form phasor on the trivial 2-bus fixture (test/test_ac_oracle.jl) —
#     a BLOCKING analytic gate — BEFORE any later plan trusts it on a larger feeder.
#
#   - `assert_ac_exact!(ctx_socp, ctx_ac)` (plan 15-02) — the per-hour SOCP-vs-AC certification.
#     It is the peer to `assert_socp_exact!` (models/exactness.jl) with the SAME
#     `atol + rtol·magnitude` scale-free tolerance philosophy (WR-01) but the OPPOSITE
#     failure-mode contract: it compares TWO independently-trusted solved contexts and NEVER
#     raises on a numerical disagreement (EXACT-03) — a genuine per-hour gap is this milestone's
#     most valuable finding, not a defect to refuse. It raises ONLY on a STRUCTURAL mismatch
#     (differing horizon `T`, missing `pf_vars` keys).
#
# Convention: uses explicit `error` calls, never `@assert` (elided under -O), per
# src/core/status.jl.

using JuMP

"""
    recover_voltage_angles(ctx::ModelContext) -> Matrix{ComplexF64}

Recover the TRUE voltage phasors `V_j[t]` (magnitude AND angle) from a solved branch-flow
`ModelContext`, whose native voltage state is the magnitude-only squared voltage
`v = |V|²`. Returns an `(N, T)` `Matrix{ComplexF64}` (`N = length(ctx.meta[:feeder].buses)`,
`T = ctx.meta[:T]`).

This is pure POST-PROCESSING over an already-solved `(v, P, Q, l)` point — it creates no JuMP
variable and invokes no solver. It reads `ctx.meta[:feeder]`, `ctx.meta[:T]`, and
`ctx.meta[:pf_vars]` (the `(; v, P, Q, l)` stash) only, and writes nothing back to `ctx`.

Method (Baran–Wu complex-phasor recursion, thesis-adjacent to the 3.33 voltage-drop
derivation). Anchor the root phasor at angle zero, `V_root[t] = √(v_root[t]) + 0im` (a
per-unit magnitude with no upstream drop), then walk the radial tree OUTWARD by BFS. For a
tree edge `i → j` carrying branch `b` with impedance `z = r + jx` and complex power
`S = P_b + jQ_b` FLOWING toward the child, the downstream phasor is

    V_j = V_i − z · conj(S) / conj(V_i)

(the branch current is `I = conj(S)/conj(V_i)` from `S = V_i·conj(I)`, and `V_j = V_i − z·I`).
Because a stored `Branch(from, to, …)` need not point parent→child in the BFS tree order that
`assert_radial` guarantees only a TREE, never a topological branch sort — the adjacency keeps
a SIGNED branch index (positive = the branch's own `(from,to)` direction, negative = its
reverse) and flips the sign of `S` when traversing the branch backwards, so `S` is always the
power flowing toward the child `j`.

Validation (STATE.md blocking flag / threat T-15-05): a sign or conjugate error would silently
produce a wrong angle with no solver error to warn you, so this recursion is certified against a
hand-derived closed-form 2-bus phasor (`V₂ = 0.998 − 0.0015im` at the fixture point) by
`test/test_ac_oracle.jl` BEFORE any later plan (or later milestone phase) trusts it on
IEEE-13/123.
"""
function recover_voltage_angles(ctx::ModelContext)
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    # Signed-branch adjacency: bus -> list of (neighbor_bus, signed_branch_index). Mirrors
    # assert_radial's adjacency-build loop (data/topology.jl) but KEEPS the branch index, signed
    # by traversal direction, so the phasor recursion knows which way the branch's own (P,Q)
    # point. +b = the branch's own (from -> to) direction, -b = the reverse.
    children = [Tuple{Int, Int}[] for _ in 1:N]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b))
        push!(children[br.to], (br.from, -b))
    end

    Vphasor = Matrix{ComplexF64}(undef, N, T)
    for t in 1:T
        # Root reference: angle 0, magnitude √(v_root) (no upstream drop at the frontier).
        Vphasor[feeder.root, t] = sqrt(value(pv.v[feeder.root, t])) + 0.0im

        # BFS outward from the root (mirror assert_radial's seen/queue shape).
        visited = falses(N)
        visited[feeder.root] = true
        queue = [feeder.root]
        while !isempty(queue)
            i = pop!(queue)
            for (j, bsigned) in children[i]
                visited[j] && continue
                b = abs(bsigned)
                br = feeder.branches[b]
                z = Complex(br.r, br.x)
                # S = power flowing toward the child j. The branch stores (P,Q) in its own
                # (from -> to) direction; flip the sign when traversing it backwards so S always
                # points i -> j.
                S =
                    bsigned > 0 ? Complex(value(pv.P[b, t]), value(pv.Q[b, t])) :
                    -Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
                # Baran–Wu downstream phasor: V_j = V_i − z · conj(S)/conj(V_i).
                Vphasor[j, t] = Vphasor[i, t] - z * conj(S) / conj(Vphasor[i, t])
                visited[j] = true
                push!(queue, j)
            end
        end
    end
    return Vphasor
end

"""
    recover_lossfree_shadow_voltage(ctx::ModelContext) -> Matrix{Float64}

Compute Gan, Li, Topcu & Low's (2015) loss-free "shadow" squared voltage `v̂_GL(s)`
(Definition 3 / eq. (18) of *"Exact Convex Relaxation of Optimal Power Flow in Radial
Networks,"* IEEE TAC 60(1):72–87) from an already-solved branch-flow `ModelContext`, and this
project's `.planning/phases/20-overvoltage-capable-relaxation/20-RESEARCH.md` "Measuring ε"
section.

Pure POST-PROCESSING over an already-solved `(v, P, Q, l)` point — it creates no JuMP
variable and invokes no solver, and writes nothing back to `ctx`. It reads
`ctx.meta[:feeder]`, `ctx.meta[:T]`, and `ctx.meta[:pf_vars]` only. Returns an `(N, T)`
`Matrix{Float64}` (`N = length(ctx.meta[:feeder].buses)`, `T = ctx.meta[:T]`).

`v̂_GL(s)` is the squared voltage that WOULD result from the same power injections `s` if
every branch's loss current `ℓ ≡ 0` (i.e. the lossless LinDistFlow voltage for the SAME
dispatch). Lemma 1 (Gan-Low 2015) proves `v ≤ v̂_GL(s)` always — the loss-free shadow is
always an UPPER bound on the true voltage — the OPPOSITE sign relationship from this
project's EXISTING thesis exactness copy `v̂` (thesis 3.43/3.45), which is a LOWER-bound
shadow (`v ≥ v̂`, spot-checked in `test/test_restricted_branch_flow.jl`'s first `@testitem`).
These are two genuinely DISTINCT mechanisms; do not conflate them.

Method (unrolling the branch-flow recursion against THIS project's actual `:Rp`/`:Rq`
balance convention — loss charged at the child, `pin[j] − pout[j] = −inj[j]` — rather than
RESEARCH.md's "Measuring ε" pseudo-code literally, which stated the accumulated-loss sign
backwards relative to that convention; corrected here and re-derived from the balance
equations directly, then validated by the Lemma-1 sanity check below): build a ROOTED
parent/child tree via one BFS traversal from `feeder.root`. For each time `t`: (1) a
REVERSE-BFS loss accumulation — for bus `i`, `LossIncl[i] :=` the branch entering `i`'s own
`r·ℓ` PLUS the total `r·ℓ` accumulated over `i`'s entire downstream subtree (i.e. the closed
subtree rooted at `i`, INCLUSIVE of the branch feeding it) — and the `x`-analog; (2) a forward
recursion from the root — `v̂_GL[root] = v[root]`, and for each non-root bus `i` fed by its
tree parent via branch `b` (impedance `r,x`), the loss-free flow equals the actual flow MINUS
that closed-subtree loss: `P̌ = P[b] − LossInclR[i]`, `Q̌ = Q[b] − LossInclX[i]`, and
`v̂_GL[i] = v̂_GL[parent] − 2·(r·P̌ + x·Q̌)` (the lossless LinDistFlow drop, thesis-adjacent to
3.33 with the `+(r²+x²)·ℓ` term removed by construction). Unrolling the balance recursion
`P[b*] = Σ_{m∈children(j)} P[m] + r_{b*}·ℓ_{b*} − inj[j]` (this project's convention, byte-
identical for the lossless model with the SAME injections `inj[j]`) confirms `P[b*] − P̌[b*]`
telescopes to exactly the total loss in the CLOSED subtree rooted at `j` (the branch entering
`j` plus everything strictly below it) — hence the minus sign and the inclusive accumulation.

Validation (threat T-20-02): a sign or accumulation bug here would silently produce a wrong
`ε`. `test/test_restricted_branch_flow.jl`'s second `@testitem` sanity-checks Lemma 1
(`v̂_GL ≥ v` everywhere) numerically on a solved `ACPowerFlow` context BEFORE trusting the
measured `ε` for anything downstream.
"""
function recover_lossfree_shadow_voltage(ctx::ModelContext)
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    # Rooted parent/child tree via one BFS traversal from feeder.root. Unlike
    # recover_voltage_angles's signed BIDIRECTIONAL adjacency (immediate neighbors only), this
    # function needs to walk each bus's SUBTREE, so it keeps an explicit ROOTED tree: BFS visit
    # `order` (root first), `children_of[i]` (tree children of bus i), and `branch_of_child[c]`
    # (the branch connecting child c to its tree parent).
    children = [Tuple{Int, Int}[] for _ in 1:N]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b))
        push!(children[br.to], (br.from, -b))
    end

    order = Int[feeder.root]
    children_of = [Int[] for _ in 1:N]
    branch_of_child = Dict{Int, Int}()
    visited = falses(N)
    visited[feeder.root] = true
    queue = [feeder.root]
    while !isempty(queue)
        i = popfirst!(queue)
        for (j, bsigned) in children[i]
            visited[j] && continue
            visited[j] = true
            push!(children_of[i], j)
            branch_of_child[j] = abs(bsigned)
            push!(order, j)
            push!(queue, j)
        end
    end

    v̂_GL = Matrix{Float64}(undef, N, T)
    for t in 1:T
        # (1) Reverse-BFS loss accumulation: LossInclR[i]/LossInclX[i] := total r·ℓ / x·ℓ over
        # the CLOSED subtree rooted at i — the branch feeding i from its parent (own_r/own_x
        # below) PLUS everything strictly downstream (the recursive sum over children_of[i]).
        # The root has no feeding branch, so LossInclR/X[root] stays 0.
        LossInclR = zeros(N)
        LossInclX = zeros(N)
        for i in reverse(order)
            if i != feeder.root
                b_own = branch_of_child[i]
                br_own = feeder.branches[b_own]
                LossInclR[i] += br_own.r * value(pv.l[b_own, t])
                LossInclX[i] += br_own.x * value(pv.l[b_own, t])
            end
            for c in children_of[i]
                LossInclR[i] += LossInclR[c]
                LossInclX[i] += LossInclX[c]
            end
        end

        # (2) Forward recursion from the root: the loss-free flow on the branch feeding bus i
        # equals the actual flow MINUS the total loss in i's own closed subtree (see docstring
        # derivation).
        v̂_GL[feeder.root, t] = value(pv.v[feeder.root, t])
        for i in order
            i == feeder.root && continue
            b = branch_of_child[i]
            br = feeder.branches[b]
            P̌ = value(pv.P[b, t]) - LossInclR[i]
            Q̌ = value(pv.Q[b, t]) - LossInclX[i]
            v̂_GL[i, t] = v̂_GL[br.from, t] - 2 * (br.r * P̌ + br.x * Q̌)
        end
    end
    return v̂_GL
end

"""
    assert_ac_exact!(ctx_socp::ModelContext, ctx_ac::ModelContext;
                     rtol::Real = 1e-4, atol::Real = 1e-6) -> (; obj_gap, hours)

Certify the SOC branch-flow relaxation EXACT by comparing a solved [`ConvexBranchFlow`](@ref)
`ModelContext` (`ctx_socp`) against a solved [`ACPowerFlow`](@ref) `ModelContext` (`ctx_ac`) —
both built from the IDENTICAL problem data and each independently re-optimized (the LOCKED
"same operating point" contract) — on per-hour objective, voltage, and branch-flow gaps.

This is a NEW sibling to [`assert_socp_exact!`](@ref) (models/exactness.jl): it reuses the SAME
scale-free `atol + rtol·magnitude` tolerance philosophy (WR-01), but has the OPPOSITE
failure-mode contract. `assert_socp_exact!` THROWS to refuse physically-meaningless prices from
a single strict cone; `assert_ac_exact!` compares TWO independently-trusted solves and MUST
NEVER raise on a genuine numerical disagreement (EXACT-03) — a relaxation gap is the milestone's
most valuable possible finding, to be INVESTIGATED (reverse-flow / voltage-binding state), not
suppressed. The ONLY exception path here is a STRUCTURAL mismatch (differing horizon `T`) — a
signal the two contexts are not the same operating point, which makes any "gap" uninformative.

Returns `(; obj_gap, hours)`, NEVER a bare `Bool`:

  - `obj_gap = objective_value(ctx_socp.model) − objective_value(ctx_ac.model)` — the welfare gap
    between the relaxed and the true nonconvex optimum;
  - `hours::Vector{NamedTuple}` — one row `(; t, vgap, pgap, qgap, exact)` per hour, where
    `vgap`/`pgap`/`qgap` are the max-over-buses/branches absolute SOCP−AC gaps in squared
    voltage / active / reactive branch flow, and `exact = vgap ≤ atol + rtol·vmag && pgap ≤ atol + rtol·pmag` uses the SAME combined scale-free bound `assert_socp_exact!` uses (applied
    per-hour across the two contexts instead of per-branch within one), NEVER a purely absolute
    threshold. Inspect `hours` to locate and diagnose a genuine per-hour gap; it never collapses
    to a single pass/fail boolean.

Reads `ctx_socp.meta[:pf_vars]`/`[:feeder]`/`[:T]` and `ctx_ac.meta[:pf_vars]`/`[:T]` — the
`(; v, P, Q, l)` (AC) and `(; v, v̂, P, Q, l)` (SOCP) stashes share the `v`/`P`/`Q` field names
this indexes. Uses an explicit `error` call (never `@assert`) for the `T`-mismatch guard, per
`src/core/status.jl`.
"""
function assert_ac_exact!(
    ctx_socp::ModelContext,
    ctx_ac::ModelContext;
    rtol::Real = 1e-4,
    atol::Real = 1e-6,
)
    # The ONLY exception path: a STRUCTURAL mismatch. A differing horizon T means the two solves
    # are not the same operating point, so any per-hour "gap" would be meaningless — refuse that
    # (EXACT-03: a NUMERIC disagreement, by contrast, is reported, never raised).
    T = ctx_socp.meta[:T]
    T == ctx_ac.meta[:T] || error(
        "assert_ac_exact!: T mismatch ($T vs $(ctx_ac.meta[:T])) — " *
        "the two solves are not the same operating point",
    )

    feeder = ctx_socp.meta[:feeder]
    pv_s = ctx_socp.meta[:pf_vars]
    pv_a = ctx_ac.meta[:pf_vars]
    N = length(feeder.buses)
    nB = length(feeder.branches)

    rows = NamedTuple[]
    for t in 1:T
        # Max-over-buses/branches absolute SOCP−AC gaps.
        vgap = maximum(abs(value(pv_s.v[j, t]) - value(pv_a.v[j, t])) for j in 1:N)
        pgap = maximum(abs(value(pv_s.P[b, t]) - value(pv_a.P[b, t])) for b in 1:nB)
        qgap = maximum(abs(value(pv_s.Q[b, t]) - value(pv_a.Q[b, t])) for b in 1:nB)
        # SCALE-FREE reference magnitudes (WR-01), taken from the SOCP side.
        vmag = maximum(abs(value(pv_s.v[j, t])) for j in 1:N)
        pmag = maximum(abs(value(pv_s.P[b, t])) for b in 1:nB)
        # The SAME combined bound assert_socp_exact! uses — atol floor + rtol·magnitude — applied
        # per-hour across the two contexts. NEVER a purely absolute threshold.
        exact = vgap <= atol + rtol * vmag && pgap <= atol + rtol * pmag
        push!(rows, (; t, vgap, pgap, qgap, exact))
    end

    # Welfare gap between the relaxed (SOCP) and the true nonconvex (AC) optimum. NO error/throw
    # anywhere below the T-mismatch guard — a per-hour gap surfaces in `rows`, never as a raise.
    obj_gap = objective_value(ctx_socp.model) - objective_value(ctx_ac.model)
    return (; obj_gap, hours = rows)
end

export recover_lossfree_shadow_voltage, recover_voltage_angles, assert_ac_exact!
