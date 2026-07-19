# src/powerflow/ConvexBranchFlow.jl
#
# SEAM: SOCP Convex Branch Flow (DistFlow SOC relaxation) power-flow formulation (PF-03).
# OWNER: plan 04-02.
#
# The project's correctness keystone. A THIRD `AbstractPowerFlow` subtype implementing
# the Baran–Wu / DistFlow branch-flow model relaxed to a Second-Order Cone Program,
# together with the LinDistFlow "exactness copy" (auxiliary squared-voltage `v̂` + affine
# voltage bounds, thesis eqs. 3.40–3.45) that makes the SOC relaxation EXACT on radial
# feeders. Mirrors `LinDistFlow.jl` structurally; the only additions are the squared
# current `l[b,t] ≥ 0`, the copy `v̂[j,t]`, the loss terms `−r·l` / `−x·l` in the affine
# `:Rp`/`:Rq` balances (3.31/3.32), the true voltage drop with `+(r²+x²)·l` (3.33), the
# copy drop (3.43), the rotated SOC cone `[0.5·l, v_i, P, Q] ∈ RotatedSecondOrderCone()`
# (3.39), and the apparent-power limits (3.36). Stashes
# `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)` for the PF-04 exactness checker.
#
# This file also adds `problem_class(::ConvexBranchFlow) = SOCP()` so the cone routes to
# the tight-gap Clarabel factory (the generic `problem_class(::AbstractPowerFlow) = QP()`
# lives in solver/problem_class_trait.jl, owned by plan 04-01). Selection is PURELY by
# Julia dispatch on the singleton type — no formulation-flag branching anywhere.

using JuMP

# No-limit sentinel for the apparent-power constraint (RESEARCH Open Q2, Assumption A7):
# non-head branches carry no binding thermal limit in the thesis. The IEEE-13 fixture
# (plan 04-03) encodes "no real limit" as this sentinel (just under the strict
# `0 < smax < 100` `assert_magnitudes` band). Branches at/above this sentinel get NO
# apparent-power cone (only branches with a genuine limit — e.g. the head branch
# `S_max,(0,1) = 0.0686` pu — are constrained), so the case stays congestion-driven at the
# head rather than over-constrained by fictitious interior limits.
#
# IN-01: sourced from the single canonical `SMAX_NO_LIMIT` in units/PerUnit.jl (the fixture
# references the SAME constant), so the "interior-unconstrained" sentinel has one source of
# truth instead of a bare `99.0` literal duplicated across modules.
const _SMAX_NO_LIMIT = SMAX_NO_LIMIT

"""
    ConvexBranchFlow <: AbstractPowerFlow

SOCP Convex Branch Flow: the Baran–Wu / DistFlow branch-flow model relaxed to a
Second-Order Cone Program (thesis eqs. 3.31–3.39) **with** the LinDistFlow exactness copy
(auxiliary squared-voltage `v̂` + affine voltage bounds, thesis eqs. 3.43/3.45) that makes
the relaxation EXACT on radial feeders. It is the third concrete [`AbstractPowerFlow`](@ref)
subtype and is drop-in interchangeable with [`DCPowerFlow`](@ref) and [`LinDistFlow`](@ref)
by dispatch alone — swapping it as the `pf` argument touches neither device nor assembly
code (there is no `if formulation ==` branching anywhere).

Thesis equations implemented (all traced in [`contribute!`](@ref)):

  * 3.31 — per-bus active balance, now WITH the `−r·l` loss term (affine in `l`);
  * 3.32 — per-bus reactive balance, now WITH the `−x·l` loss term (affine in `l`);
  * 3.33 — TRUE voltage drop `v_j = v_i − 2(rP+xQ) + (r²+x²)·l` (the loss-current term
    `+(r²+x²)·l` that `LinDistFlow` drops);
  * 3.36 — forward apparent-power limit `P² + Q² ≤ S²max` (only where a real limit exists,
    see `_SMAX_NO_LIMIT`);
  * 3.39 — the SOC relaxation `l_ij·v_i ≥ P² + Q²`, written as a rotated second-order cone
    `[0.5·l, v_i, P, Q] ∈ RotatedSecondOrderCone()` (‖x‖² ≤ 2·t·u ⇒ P²+Q² ≤ 2·(0.5l)·v = l·v);
  * 3.43 — the exactness-copy voltage drop `v̂_j = v̂_i − 2{r(P+rl) + x(Q+xl)}`, written
    purely in the ORIGINAL `P, Q, l` plus the single new copy `v̂` (no separate `P̂/Q̂`);
  * 3.45 — squared-magnitude voltage bounds `V²min ≤ v, v̂ ≤ V²max` on BOTH `v` and `v̂`.

Differences from [`LinDistFlow`](@ref) (which is this model with `l → 0`): adds the squared
current `l[b,t] ≥ 0` and the exactness copy `v̂[j,t]`; the rotated SOC cone (3.39); the loss
terms `−r·l`/`−x·l` in the balances; the `+(r²+x²)·l` term in the true drop; the copy drop
(3.43); and the forward apparent-power limit (3.36).

Why the exactness copy is not decorative (RESEARCH Pitfall 1 / Pattern 2): the true drop
3.33 carries `+(r²+x²)·l` while the copy drop 3.43 carries `−2(r²+x²)·l`; upper-bounding
`v̂ ≤ V²max` (3.45) drives the loss current `l` down until the cone 3.39 holds with equality
(exact) at the optimum. Omit it and the recovered DADP prices are physically meaningless in
exactly the high-PV / over-voltage regimes the research targets.

Pitfall 1 (off-by-square voltage): `v`/`v̂` are the SQUARE of the magnitude, so bounds are
`vmin²`/`vmax²` and the root is fixed at `1.0` (= 1.0²).
"""
struct ConvexBranchFlow <: AbstractPowerFlow end

"""
    contribute!(::ConvexBranchFlow, ctx::ModelContext, feeder; T::Int=1)

Write the SOCP DistFlow branch/voltage terms — plus the LinDistFlow exactness copy — into
the shared residuals, mirroring [`contribute!(::LinDistFlow, …)`](@ref) with the additions
listed on [`ConvexBranchFlow`](@ref).

Creates, on `ctx.model`:
- `v[j,t]`  — squared voltage magnitude `|V_j|²` (thesis 3.33 variable);
- `v̂[j,t]`  — the exactness-copy squared voltage (thesis 3.43/3.45), one per bus per time
  (NOT a separate flow network — only `v̂`, per RESEARCH Pattern 2);
- `P[b,t]`, `Q[b,t]` — branch active/reactive flows (parent→child), `t = 1:T`;
- `l[b,t] ≥ 0` — squared branch current (thesis 3.34 variable), lower-bounded at 0 so the
  rotated cone's `t,u ≥ 0` requirement holds.

The root squared voltage AND its copy are fixed at the reference `1.0` (= 1.0²); every
non-root bus bounds BOTH `v` and `v̂` by `vmin²`/`vmax²` (thesis 3.45 — the bounds that
force exactness; Pitfall 1: SQUARE the pu magnitude bounds).

Per branch/time it adds:
- the rotated SOC cone `[0.5·l, v[from], P, Q] ∈ RotatedSecondOrderCone()` ⇒
  `l·v ≥ P²+Q²` (thesis 3.39; the `0.5` factor is MANDATORY — dropping it silently doubles
  the allowed current, RESEARCH Anti-Pattern);
- the true voltage drop `v[to] == v[from] − 2(rP+xQ) + (r²+x²)·l` (thesis 3.33);
- the copy drop `v̂[to] == v̂[from] − 2{r(P+rl) + x(Q+xl)}` (thesis 3.43, `P̂/Q̂` expanded);
- where a real limit exists (`smax < _SMAX_NO_LIMIT`), the forward apparent-power cone
  `‖(P,Q)‖₂ ≤ smax` ⇒ `P²+Q² ≤ S²max` (thesis 3.36).

Then accumulates the per-bus active balance into `ctx.residuals[:Rp]` (thesis 3.31) and the
reactive balance into `:Rq` (thesis 3.32) via the INDEXED `add_to_residual!`. The incoming
branch `(i,j)` contributes `+P − r·l` (`:Rp`) / `+Q − x·l` (`:Rq`) at the CHILD node `j`
(RESEARCH Pitfall 6 — losses are charged at the child); outgoing branches `(j,m)` contribute
`−P` / `−Q`. The loss terms are LINEAR in `l`, so they flow through the affine
`add_to_residual!` seam unchanged. Stashes `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)` for the
PF-04 exactness checker. Returns `ctx`.
"""
function contribute!(::ConvexBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)
    nB = length(B)

    # Squared voltage v = |V|² (thesis 3.33 var), its exactness copy v̂ (3.43/3.45), branch
    # active/reactive flows P/Q, and the squared branch current l ≥ 0 (3.34 var).
    @variable(m, v[j = 1:N, t = 1:T])
    @variable(m, v̂[j = 1:N, t = 1:T])
    @variable(m, P[b = 1:nB, t = 1:T])
    @variable(m, Q[b = 1:nB, t = 1:T])
    @variable(m, l[b = 1:nB, t = 1:T] >= 0)

    # Root (frontier) squared voltage AND its copy fixed to the reference 1.0² (thesis: v_0
    # fixed; the copy root is fixed too, RESEARCH Pattern 2).
    fix.(v[feeder.root, :], 1.0; force = true)
    fix.(v̂[feeder.root, :], 1.0; force = true)

    # Squared voltage bounds on BOTH v and v̂ at every non-root bus (thesis 3.45; Pitfall 1:
    # SQUARE the pu magnitude bounds). Bounding v̂ ≤ V²max is what drives the cone tight
    # (exact) — this is the load-bearing half of the exactness copy, not decoration.
    for j in 1:N, t in 1:T
        j == feeder.root && continue
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)    # V²_min
        set_upper_bound(v[j, t], vb.vmax^2)    # V²_max
        set_lower_bound(v̂[j, t], vb.vmin^2)
        set_upper_bound(v̂[j, t], vb.vmax^2)
    end

    # Rotated SOC relaxation (thesis 3.39): l·v ≥ P²+Q². JuMP's RotatedSecondOrderCone
    # enforces ‖x‖² ≤ 2·t·u, so with t = 0.5·l, u = v[from], x = (P,Q) we get
    # P²+Q² ≤ 2·(0.5l)·v = l·v. The 0.5 factor is MANDATORY (RESEARCH Anti-Pattern).
    @constraint(
        m,
        cone[b = 1:nB, t = 1:T],
        [0.5 * l[b, t], v[B[b].from, t], P[b, t], Q[b, t]] in RotatedSecondOrderCone()
    )
    # PRICE-02 (05-01): register the rotated cone (3.39) so its dual is recoverable for the
    # DLMP loss/voltage split (decompose_dlmp, plan 05-02). PURELY ADDITIVE — the handle is
    # the SAME container already built above; nothing about the feasible set changes.
    register_constraint!(ctx, :cone, cone)   # dual feeds the loss/voltage DLMP component (3.39)

    # TRUE voltage drop (thesis 3.33): v_j = v_i − 2(rP + xQ) + (r²+x²)·l. Unlike
    # LinDistFlow (l→0), the loss-current term (r²+x²)·l is retained.
    @constraint(
        m,
        vdrop[b = 1:nB, t = 1:T],
        v[B[b].to, t] ==
        v[B[b].from, t] - 2 * (B[b].r * P[b, t] + B[b].x * Q[b, t]) +
        (B[b].r^2 + B[b].x^2) * l[b, t]
    )
    # PRICE-02 (05-01): register the true voltage drop (3.33) — its dual β feeds the
    # loss+voltage DLMP component. PURELY ADDITIVE (same container, unchanged math).
    register_constraint!(ctx, :vdrop, vdrop)   # dual β feeds loss+voltage DLMP component (3.33)

    # Exactness-copy voltage drop (thesis 3.43): substitute P̂ = P + r·l, Q̂ = Q + x·l into
    # the copy recursion ⇒ v̂_j = v̂_i − 2{ r(P + r·l) + x(Q + x·l) }. Written purely in the
    # ORIGINAL P, Q, l plus the single copy v̂ (no separate P̂/Q̂ variables — RESEARCH
    # Pattern 2).
    @constraint(
        m,
        cpydrop[b = 1:nB, t = 1:T],
        v̂[B[b].to, t] ==
        v̂[B[b].from, t] -
        2 * (
            B[b].r * (P[b, t] + B[b].r * l[b, t]) +
            B[b].x * (Q[b, t] + B[b].x * l[b, t])
        )
    )
    # PRICE-02 (05-01): register the exactness-copy drop (3.43) — its dual feeds the
    # exactness-copy contribution to the DLMP split. Pitfall 2: omitting this registration
    # leaves a residual in the four-way sum-to-nodal-price identity. PURELY ADDITIVE.
    register_constraint!(ctx, :cpydrop, cpydrop)   # dual feeds the exactness-copy DLMP term (3.43)

    # Forward apparent-power limit (thesis 3.36): P²+Q² ≤ S²max ⟺ ‖(P,Q)‖₂ ≤ smax, added
    # ONLY where a genuine limit exists (RESEARCH Open Q2 / Assumption A7). Branches with the
    # `_SMAX_NO_LIMIT` sentinel (interior, unconstrained) get NO cone — the case is
    # congestion-driven at the head branch alone.
    #
    # PRICE-02 (05-01): built as a NAMED, BRANCH-INDEXED sparse container (keyed by branch
    # index b and time t) via the SAME `B[b].smax < _SMAX_NO_LIMIT` filter predicate the prior
    # anonymous loop used — so the feasible set is BYTE-IDENTICAL (only genuinely-limited
    # branches, i.e. the head branch, get a cone). The container is keyed by BRANCH INDEX b
    # (WARNING-2, plan 05-01) — NOT an (b,br) tuple — so `decompose_dlmp` (plan 05-02) can index
    # the congestion dual ν by branch on the root→j tree path. Its dual is the congestion
    # component of the DLMP.
    @constraint(
        m,
        smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
        [B[b].smax, P[b, t], Q[b, t]] in SecondOrderCone()
    )
    register_constraint!(ctx, :smax, smax)   # dual ν = congestion DLMP component (3.36)

    # Per-bus active (3.31) and reactive (3.32) balances: inflow − outflow, accumulated into
    # the shared :Rp / :Rq via the indexed seam. The incoming branch (i,j) contributes
    # +P − r·l / +Q − x·l at the CHILD node j (loss charged at the child — Pitfall 6);
    # outgoing branches (j,m) contribute −P / −Q. The −r·l / −x·l loss terms are LINEAR in l,
    # so they pass through the affine add_to_residual! unchanged.
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

    # Stash the SOC/exactness variables for the PF-04 exactness checker (plan 04-05), which
    # keys off the presence of :l to run `max|l·v − (P²+Q²)| < τ` and refuse prices on
    # inexactness. DC/LinDistFlow stash no :l, so that gate leaves them untouched.
    ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)
    return ctx
end

# Route the SOCP formulation to the tight-gap Clarabel factory (RESEARCH Pattern 5). This is
# a MORE-SPECIFIC method on the `problem_class` trait whose generic `(::AbstractPowerFlow) =
# QP()` lives in solver/problem_class_trait.jl (plan 04-01); both share one function by
# name within module TSODSO, so multiple dispatch picks SOCP() here and QP() for DC/LDF —
# no `if formulation ==` branching, and no model names a concrete solver (INFRA-02).
problem_class(::ConvexBranchFlow) = SOCP()

export ConvexBranchFlow
