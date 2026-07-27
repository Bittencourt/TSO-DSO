# src/models/ac_oracle.jl
#
# SEAM: AC-exactness oracle post-processing (EXACT-01/02/03).
# OWNER: plan 15-01 (recover_voltage_angles); plan 15-02 (assert_ac_exact!, added to this
#        same file next).
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

export recover_voltage_angles, assert_ac_exact!
