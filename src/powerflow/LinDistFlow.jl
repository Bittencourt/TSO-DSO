# src/powerflow/LinDistFlow.jl
#
# SEAM: LinDistFlow (linear branch-flow) power-flow formulation (PF-02).
# OWNER: plan 02-02.
#
# An `AbstractPowerFlow` subtype implementing the dispatched `contribute!` contract:
# it writes the loss-less linear branch-flow terms — active AND reactive nodal
# balance plus the linear voltage-drop relation — into `ctx.residuals[:Rp]` and
# `ctx.residuals[:Rq]` via the indexed `add_to_residual!` seam (PF-02). Traces thesis
# eqs. 3.31–3.33 (nodal balances / branch flows) and the exactness copy 3.43 / 3.45
# (the LinDistFlow relaxation that later becomes the SOCP cone in Phase 4).
#
# Selection is PURELY by Julia dispatch on the singleton type `LinDistFlow` — no
# formulation-flag branching anywhere.

using JuMP

"""
    LinDistFlow <: AbstractPowerFlow

Loss-less linear branch-flow (LinDistFlow) formulation with squared-voltage-magnitude
variables. It is the DistFlow model (thesis eqs. 3.31–3.33) with the current/loss terms
(`r·ℓ`, `x·ℓ`, `(r²+x²)·ℓ`) dropped — the l→0 specialization that yields the linear
voltage drop 3.43 (and, in Phase 4, becomes the SOCP cone 3.39/3.45). It creates branch
active/reactive flows `P[b,t]`/`Q[b,t]` and a squared-voltage variable `v[j,t] = |V_j|²`,
contributes the per-bus active balance into `ctx.residuals[:Rp]` (3.31) and the reactive
balance into `ctx.residuals[:Rq]` (3.32), and adds the loss-less voltage-drop constraint
`vdrop` (3.43). Contrast with [`DCPowerFlow`](@ref), which is active-only (no `:Rq`,
no voltage). Swapping between the two touches neither device nor assembly code.

Pitfall 1 (off-by-square voltage): `v` is the SQUARE of the magnitude, so the bounds
are `vmin²`/`vmax²` and the root is fixed at `1.0` (= 1.0²).
"""
struct LinDistFlow <: AbstractPowerFlow end

"""
    contribute!(::LinDistFlow, ctx::ModelContext, feeder; T::Int=1)

Write the loss-less LinDistFlow branch/voltage terms into the shared residuals.

Creates, on `ctx.model`:

  - `v[j,t]` — squared voltage magnitude `|V_j|²` (thesis 3.33 variable), with the root
    fixed at `1.0` and every other bus bounded by the SQUARED magnitude limits
    `vmin²`/`vmax²` (thesis 3.45; Pitfall 1 — square the magnitude bounds);
  - `P[b,t]`, `Q[b,t]` — branch active/reactive flows (parent→child), `t = 1:T`;
  - `vdrop[b,t]` — the loss-less voltage-drop constraint
    `v[br.to,t] == v[br.from,t] − 2·(r·P[b,t] + x·Q[b,t])` (thesis 3.43, l→0).

Then accumulates the per-bus active balance (inflow − outflow of `P`) into
`ctx.residuals[:Rp]` (thesis 3.31, loss-less) and the reactive balance (inflow −
outflow of `Q`) into `ctx.residuals[:Rq]` (thesis 3.32), both via the INDEXED
`add_to_residual!`. Stashes `ctx.meta[:pf_vars] = (; v, P, Q)` for post-solve
inspection / the Phase-4 exactness check. Returns `ctx`.
"""
function contribute!(::LinDistFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)

    # Squared voltage v = |V|² (thesis 3.33 variable), branch active/reactive flows.
    @variable(m, v[j = 1:N, t = 1:T])
    @variable(m, P[b = 1:length(B), t = 1:T])
    @variable(m, Q[b = 1:length(B), t = 1:T])

    # Root (frontier) squared voltage fixed to the reference 1.0² (thesis: v_0 fixed).
    fix.(v[feeder.root, :], 1.0; force = true)

    # Squared voltage bounds for the non-root buses (thesis 3.45; Pitfall 1: SQUARE the
    # magnitude pu bounds — vmin²/vmax²). The root is fixed above, so it takes no bounds.
    for j in 1:N, t in 1:T
        j == feeder.root && continue
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)   # V²_min
        set_upper_bound(v[j, t], vb.vmax^2)   # V²_max
    end

    # Loss-less voltage drop (thesis 3.33 with l→0 ⇒ 3.43): v_to = v_from − 2(rP + xQ).
    @constraint(
        m,
        vdrop[b = 1:length(B), t = 1:T],
        v[B[b].to, t] == v[B[b].from, t] - 2 * (B[b].r * P[b, t] + B[b].x * Q[b, t])
    )

    # Per-bus active (3.31) and reactive (3.32) balances: inflow − outflow, accumulated
    # into the shared :Rp / :Rq via the indexed seam (loss-less: current terms dropped).
    for j in 1:N, t in 1:T
        pin = sum(P[b, t] for (b, br) in enumerate(B) if br.to == j; init = 0.0)
        pout = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, pin - pout)

        qin = sum(Q[b, t] for (b, br) in enumerate(B) if br.to == j; init = 0.0)
        qout = sum(Q[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rq, j, t, qin - qout)
    end

    ctx.meta[:pf_vars] = (; v, P, Q)   # stash for post-solve inspection / Phase-4 exactness
    return ctx
end

export LinDistFlow
