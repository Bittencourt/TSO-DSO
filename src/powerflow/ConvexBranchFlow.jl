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
#
# COMMENT-ONLY STUB — no code, no exports. Filled by plan 04-02 (PF-03).
