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
# (plan 15-02 adds `assert_ac_exact!` — the per-hour SOCP-vs-AC certification — to this file.)
#
# Convention: uses `error(...)`, never `@assert` (elided under -O), per src/core/status.jl.

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
                    bsigned > 0 ?
                    Complex(value(pv.P[b, t]), value(pv.Q[b, t])) :
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

export recover_voltage_angles
