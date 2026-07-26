# src/powerflow/ACPowerFlow.jl
#
# SEAM: independent nonconvex AC-OPF branch-flow oracle (EXACT-01).
# OWNER: plan 15-01.
#
# A genuinely INDEPENDENT peer to `ConvexBranchFlow`: the SAME Baran–Wu / DistFlow
# branch-flow physics (thesis eqs. 3.31–3.36) but UNRELAXED. Where `ConvexBranchFlow`
# writes the rotated second-order cone `l·v ≥ P²+Q²` (thesis 3.39) plus the LinDistFlow
# exactness copy (`v̂`, thesis 3.43/3.45) that forces the relaxation tight, this
# formulation writes the TRUE nonconvex scalar-quadratic EQUALITY `l·v = P²+Q²` directly
# and carries NO exactness copy at all (there is no relaxation to make exact). It is the
# AC-exactness ORACLE against which the SOCP relaxation is certified: an equality-constrained
# nonconvex AC-OPF solved with Ipopt, NOT a re-solve of the same relaxed cone through a
# different solver (the RSOCtoNonConvexQuadBridge cross-check in welfare_solve.jl already
# does that, and is insufficient as a certification per the exactness literature).
#
# "Same operating point" contract (RESEARCH Assumption A3, LOCKED as the OPTIMALITY-CHECK
# interpretation): the AC oracle consumes the IDENTICAL feeder / aggregators / λ₀ / T /
# allow_export inputs the SOCP call used and each solve INDEPENDENTLY re-optimizes device
# dispatch — never a fixed-injection feasibility check. The per-hour SOCP-vs-AC comparison
# (assert_ac_exact!, plan 15-02) is trustworthy precisely because both are genuine optima on
# the same data.
#
# Dispatched through the EXISTING `solve_welfare` entrypoint with ZERO change to that file:
# the `NLP()` problem-class trait defined below routes `solve_welfare`'s default `optimizer`
# kwarg to `select_optimizer(NLP())` (Ipopt), and the rest of `solve_welfare` is
# formulation-agnostic. Selection is PURELY by Julia dispatch on the singleton type — no
# formulation-flag branching anywhere.
#
# Harmless :l-keyed double-fire (documented, NOT a defect to "fix"): because this formulation
# ALSO stashes `:l` in `ctx.meta[:pf_vars]`, the `:l`-gated `assert_socp_exact!` call inside
# `solve_welfare` (welfare_solve.jl:256-258) fires on an ACPowerFlow-built ctx too. It is
# harmless: the "cone" is an EQUALITY by construction, so the residual `l·v − (P²+Q²)` is ~0
# and the gate passes trivially, stashing a near-zero `ctx.meta[:socp_maxgap]`. This is
# intentional — leave it.

using JuMP

"""
    ACPowerFlow <: AbstractPowerFlow

Independent nonconvex AC-OPF branch-flow oracle: the Baran–Wu / DistFlow branch-flow model
(thesis eqs. 3.31–3.36) written UNRELAXED — the true scalar-quadratic EQUALITY
`l_ij·v_i = P_ij² + Q_ij²` (thesis 3.39 as an equality, not the rotated-SOC inequality) — and
carrying NO LinDistFlow exactness copy. It is a peer [`AbstractPowerFlow`](@ref) subtype,
drop-in interchangeable with [`ConvexBranchFlow`](@ref) by dispatch alone (swapping it as the
`pf` argument to [`solve_welfare`](@ref) touches neither device nor assembly code — there is no
`if formulation ==` branching anywhere).

Purpose (EXACT-01): this is the AC-exactness ORACLE. [`assert_ac_exact!`](@ref) (plan 15-02)
compares a solved [`ConvexBranchFlow`](@ref) `ModelContext` against a solved `ACPowerFlow`
`ModelContext` — both from the IDENTICAL problem data, each independently re-optimized — to
certify the SOC relaxation exact (or surface a genuine relaxation gap) per-hour. It is a
GENUINELY INDEPENDENT nonconvex formulation, not a re-solve of the same relaxed cone through a
different solver.

Thesis equations implemented (all traced in [`contribute!`](@ref)):

  - 3.31 — per-bus active balance, WITH the `−r·l` loss term (affine in `l`);
  - 3.32 — per-bus reactive balance, WITH the `−x·l` loss term (affine in `l`);
  - 3.33 — TRUE voltage drop `v_j = v_i − 2(rP+xQ) + (r²+x²)·l`;
  - 3.34 — the squared branch current `l[b,t] ≥ 0`;
  - 3.36 — forward apparent-power limit `P² + Q² ≤ S²max` (only where a real limit exists,
    see `_SMAX_NO_LIMIT`), written as the plain scalar quadratic inequality;
  - 3.39 (UNRELAXED) — the branch-flow relation `l_ij·v_i = P_ij² + Q_ij²` as a genuine
    nonconvex EQUALITY, replacing the rotated-SOC inequality of [`ConvexBranchFlow`](@ref).

Differences from [`ConvexBranchFlow`](@ref): drops the exactness copy `v̂` entirely (no `v̂`
variable, no `v̂` bounds, no copy voltage drop 3.43) — there is no relaxation to force tight;
replaces the rotated SOC cone (3.39) with the nonconvex scalar-quadratic equality; replaces the
apparent-power SOC (3.36) with the equivalent scalar-quadratic inequality. Everything else — the
true voltage drop (3.33), the loss-at-child `:Rp`/`:Rq` accumulation (3.31/3.32) — is
byte-identical to [`ConvexBranchFlow`](@ref).

Squared-voltage convention (matches [`ConvexBranchFlow`](@ref) verbatim, threat T-15-01): `v`
is the SQUARE of the magnitude `|V|²`, so bounds are `vmin²`/`vmax²` and the root is fixed at
`1.0` (= 1.0²) — reintroducing a magnitude-vs-square mismatch here would look like a relaxation
gap but be a units bug.

The `NLP()` problem-class routing (defined below) sends the nonconvex equality to the Ipopt
factory via `solve_welfare`'s default `optimizer` kwarg — unchanged dispatch. The `:l`-keyed
`assert_socp_exact!` double-fire in `welfare_solve.jl:256-258` is harmless (the cone is an
equality by construction, residual ~0) and intentional — see this file's header.
"""
struct ACPowerFlow <: AbstractPowerFlow end

"""
    contribute!(::ACPowerFlow, ctx::ModelContext, feeder; T::Int=1)

Write the UNRELAXED nonconvex AC branch/voltage terms into the shared residuals, mirroring
[`contribute!(::ConvexBranchFlow, …)`](@ref) variable-for-variable EXCEPT the three
differences listed on [`ACPowerFlow`](@ref) (equality cone, scalar-quadratic apparent-power
limit, no exactness copy).

Creates, on `ctx.model`:

  - `v[j,t]`  — squared voltage magnitude `|V_j|²` (thesis 3.33 variable);
  - `P[b,t]`, `Q[b,t]` — branch active/reactive flows (parent→child), `t = 1:T`;
  - `l[b,t] ≥ 0` — squared branch current (thesis 3.34 variable).

There is NO exactness-copy `v̂` — this is not a relaxation. The root squared voltage is fixed
at the reference `1.0` (= 1.0²); every non-root bus bounds `v` by `vmin²`/`vmax²`.

Per branch/time it adds:

  - the TRUE nonconvex branch-flow relation `l[b,t]·v[from,t] == P[b,t]² + Q[b,t]²` (thesis
    3.39 UNRELAXED, a scalar-quadratic EQUALITY — Ipopt's MOI wrapper takes a
    `ScalarQuadraticFunction`-in-`EqualTo` natively, empirically confirmed by the
    LOCALLY_SOLVED/OPTIMAL termination the `solve_welfare` dispatch reaches);
  - the true voltage drop `v[to] == v[from] − 2(rP+xQ) + (r²+x²)·l` (thesis 3.33);
  - where a real limit exists (`smax < _SMAX_NO_LIMIT`), the forward apparent-power limit
    `P² + Q² ≤ S²max` (thesis 3.36) as a plain scalar-quadratic inequality.

Then accumulates the per-bus active balance into `ctx.residuals[:Rp]` (thesis 3.31) and the
reactive balance into `:Rq` (thesis 3.32) via the INDEXED `add_to_residual!`, loss-charged at
the CHILD node — byte-identical to [`contribute!(::ConvexBranchFlow, …)`](@ref). Stashes
`ctx.meta[:pf_vars] = (; v, P, Q, l)` (NO `v̂`) so [`assert_ac_exact!`](@ref) can index both the
SOCP-built and AC-built contexts by the same field names. Returns `ctx`.
"""
function contribute!(::ACPowerFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)
    nB = length(B)

    # Squared voltage v = |V|² (thesis 3.33 var), branch active/reactive flows P/Q, and the
    # squared branch current l ≥ 0 (3.34 var). NO exactness copy v̂ — this is the unrelaxed
    # nonconvex model, not a relaxation to be forced tight.
    @variable(m, v[j = 1:N, t = 1:T])
    @variable(m, P[b = 1:nB, t = 1:T])
    @variable(m, Q[b = 1:nB, t = 1:T])
    @variable(m, l[b = 1:nB, t = 1:T] >= 0)

    # Root (frontier) squared voltage fixed to the reference 1.0² (thesis: v_0 fixed).
    fix.(v[feeder.root, :], 1.0; force = true)

    # Squared voltage bounds at every non-root bus (Pitfall 1: SQUARE the pu magnitude bounds).
    # Only v — there is no v̂ copy in this formulation.
    for j in 1:N, t in 1:T
        j == feeder.root && continue
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)    # V²_min
        set_upper_bound(v[j, t], vb.vmax^2)    # V²_max
    end

    # TRUE nonconvex branch-flow relation (thesis 3.39 UNRELAXED): l·v_from = P²+Q², written as
    # a plain scalar-quadratic EQUALITY — NOT the rotated-SOC inequality ConvexBranchFlow uses.
    # This is the whole point of the oracle: the physics enforced exactly, not relaxed. Ipopt's
    # MOI wrapper accepts a ScalarQuadraticFunction-in-EqualTo natively (confirmed empirically by
    # the LOCALLY_SOLVED/OPTIMAL termination reached through solve_welfare's NLP dispatch —
    # resolving RESEARCH Assumption A2).
    @constraint(
        m,
        cone[b = 1:nB, t = 1:T],
        l[b, t] * v[B[b].from, t] == P[b, t]^2 + Q[b, t]^2
    )
    # Registered under the SAME :cone name ConvexBranchFlow uses, so a downstream consumer that
    # recovers this handle by name sees a peer container (here an equality, there a cone).
    register_constraint!(ctx, :cone, cone)

    # TRUE voltage drop (thesis 3.33): v_j = v_i − 2(rP + xQ) + (r²+x²)·l. Byte-identical to
    # ConvexBranchFlow (the loss-current term (r²+x²)·l is retained).
    @constraint(
        m,
        vdrop[b = 1:nB, t = 1:T],
        v[B[b].to, t] ==
        v[B[b].from, t] - 2 * (B[b].r * P[b, t] + B[b].x * Q[b, t]) +
        (B[b].r^2 + B[b].x^2) * l[b, t]
    )
    register_constraint!(ctx, :vdrop, vdrop)

    # NO exactness-copy voltage drop (thesis 3.43) — ConvexBranchFlow's :cpydrop block is
    # dropped entirely. There is no copy to drop: the model is already unrelaxed.

    # Forward apparent-power limit (thesis 3.36): P²+Q² ≤ S²max, added ONLY where a genuine
    # limit exists (RESEARCH Open Q2 / Assumption A7). Written as the plain scalar-quadratic
    # inequality (Ipopt takes it natively) — the equivalent of ConvexBranchFlow's SOC form,
    # under the SAME `B[b].smax < _SMAX_NO_LIMIT` filter so the feasible set matches.
    @constraint(
        m,
        smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
        P[b, t]^2 + Q[b, t]^2 <= B[b].smax^2
    )
    register_constraint!(ctx, :smax, smax)

    # Per-bus active (3.31) and reactive (3.32) balances: inflow − outflow, accumulated into
    # the shared :Rp / :Rq via the indexed seam. The incoming branch (i,j) contributes
    # +P − r·l / +Q − x·l at the CHILD node j (loss charged at the child — Pitfall 6);
    # outgoing branches (j,m) contribute −P / −Q. Byte-identical to ConvexBranchFlow.
    for j in 1:N, t in 1:T
        pin = sum(
            P[b, t] - br.r * l[b, t] for (b, br) in enumerate(B) if br.to == j;
            init = 0.0,
        )
        pout = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, pin - pout)

        qin = sum(
            Q[b, t] - br.x * l[b, t] for (b, br) in enumerate(B) if br.to == j;
            init = 0.0,
        )
        qout = sum(Q[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rq, j, t, qin - qout)
    end

    # Stash the AC variables for assert_ac_exact! (plan 15-02) and the harmless :l-keyed
    # assert_socp_exact! double-fire inside solve_welfare (residual ~0 since the cone is an
    # equality). No :v̂ — the field set is the ConvexBranchFlow stash MINUS the copy.
    ctx.meta[:pf_vars] = (; v, P, Q, l)
    return ctx
end

# Route the nonconvex equality formulation to the Ipopt factory (a MORE-SPECIFIC method on the
# `problem_class` trait whose generic `(::AbstractPowerFlow) = QP()` lives in
# solver/problem_class_trait.jl, and whose `(::ConvexBranchFlow) = SOCP()` lives in
# ConvexBranchFlow.jl). Multiple dispatch picks NLP() here — so `solve_welfare`'s default
# `optimizer = select_optimizer(problem_class(pf))` resolves to Ipopt with ZERO change to
# welfare_solve.jl, and no model names a concrete solver (INFRA-02).
problem_class(::ACPowerFlow) = NLP()

export ACPowerFlow
