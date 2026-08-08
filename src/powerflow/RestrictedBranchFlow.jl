# src/powerflow/RestrictedBranchFlow.jl
#
# SEAM: Gan-Low OPF-ε restricted-feasible-set formulation (OVR-01).
# OWNER: plan 20-02.
#
# A genuine feasible-set RESTRICTION (never a relaxation tightening; D-01) implementing
# Gan, Li, Topcu & Low's (2015) "OPF-ε" construction (Theorem 2 / Section IV-D, eq. 18):
# shrink `ConvexBranchFlow`'s own per-bus squared-voltage upper bound from `vmax²` to
# `vmax² − ε` for a single measured scalar `ε` (the network's "modification gap"). The paper
# proves (Theorem 2) this makes the SOC relaxation of the shrunk problem EXACT whenever the
# mild, a-priori-checkable condition C1 holds — resolving the genuine SOCP inexactness the
# v2.1 EXACT-04 finding documented in the high-PV / reverse-flow regime, without abandoning
# the "prices are duals of one convex problem" story (OVR-03).
#
# Dispatched through the EXISTING `solve_welfare` entrypoint with ZERO change to that file —
# the exact `ACPowerFlow` v2.1 precedent (D-02): the `SOCP()` problem-class trait defined
# below routes `solve_welfare`'s default `optimizer` kwarg to `select_optimizer(SOCP())`
# (the same tight-tolerance Clarabel factory `ConvexBranchFlow` already uses), and the rest
# of `solve_welfare` is formulation-agnostic. Selection is PURELY by Julia dispatch on the
# concrete type — no formulation-flag branching anywhere.
#
# `contribute!` DELEGATES to `contribute!(ConvexBranchFlow(), ctx, feeder; T)` first
# (identical SOC cone + exactness copy + apparent-power cone + balance accumulation —
# correctness-drift avoidance per RESEARCH.md's explicit recommendation to delegate rather
# than duplicate), then shrinks ONLY `v`'s own upper bound. This is provably a genuine
# RESTRICTION (Theorem 2 / OPF-ε, Section IV-D): the returned point is guaranteed
# AC-feasible whenever C1 holds (RESEARCH.md analytically argues C1 holds comfortably on
# this fixture's tiny impedances).

using JuMP

# The Gan-Low "modification gap" ε, measured on the EXACT-04 fixture
# (test/test_restricted_branch_flow.jl, plan 20-01 Task 2): ε_measured = 0.005811069127373614
# pu²; 1.25× safety multiplier ⇒ ε = 0.007263836409217017 pu² (D-03/D-07 provenance — never
# re-derive without updating this comment).
const _EXACT04_MEASURED_ε = 0.005811069127373614 * 1.25

"""
    RestrictedBranchFlow <: AbstractPowerFlow

`ConvexBranchFlow` plus one shrunk voltage upper bound — Gan, Li, Topcu & Low's (2015)
"OPF-ε" construction (Theorem 2 / Section IV-D, eq. 18). It is a peer
[`AbstractPowerFlow`](@ref) subtype, drop-in interchangeable with
[`ConvexBranchFlow`](@ref)/[`ACPowerFlow`](@ref) by dispatch alone (swapping it as the `pf`
argument to [`solve_welfare`](@ref) touches neither device nor assembly code — there is no
`if formulation ==` branching anywhere).

Purpose (OVR-01): resolve the genuine SOCP-relaxation inexactness the v2.1 EXACT-04 finding
documented in the high-PV / reverse-flow / over-voltage regime. The existing thesis
exactness copy (`v̂`, thesis 3.43/3.45, already in `ConvexBranchFlow`) is provably a
*lower*-bound shadow on the true voltage (`v ≥ v̂` everywhere, confirmed numerically by plan
20-01 Task 1) — the OPPOSITE sign relationship from Gan-Low's *upper*-bound shadow
(`v ≤ v̂_GL(s)`), so it is structurally incapable of helping the over-voltage case. This
formulation adds the genuinely new, complementary Gan-Low restriction instead.

Field `ε::Float64` is the modification gap (Gan-Low Definition 3, eq. 18): the worst-case
deviation `‖v̂_GL(s) − v(s)‖∞` between the loss-free shadow voltage and the true voltage,
over the unrestricted problem's AC-feasible set. The outer constructor's default is
`_EXACT04_MEASURED_ε` — measured on the EXACT-04 fixture (plan 20-01 Task 2) via
[`recover_lossfree_shadow_voltage`](@ref), times a documented `1.25×` safety multiplier
(D-03: measured, not searched; mirrors this project's `DSO_BAND_HI = 1.5×max|dso|`
precedent). Per Gan-Low Theorem 2 / eq. surrounding (18): shrinking `v`'s own upper bound
by `ε` guarantees membership in the (genuinely more restrictive) "OPF-m" feasible set,
giving the chain `F_{OPF-ε} ⊆ F_{OPF-m} ⊆ F_{OPF}` — so the SOC relaxation of the shrunk
problem is exact whenever C1 holds (checkable a priori, depends only on `(r,x,p̄,q̄,v̲)`, not
on the upper voltage bound at all).

Caveat (RESEARCH.md Assumptions Log A4): `_EXACT04_MEASURED_ε` is a *point estimate at one
fixture* (the EXACT-04 high-PV stress fixture), not a network-wide worst case. Running
`RestrictedBranchFlow` on a DIFFERENT fixture/scenario without re-measuring `ε` there may
not carry Theorem 2's exactness guarantee — this default is not a universal constant.
"""
struct RestrictedBranchFlow <: AbstractPowerFlow
    ε::Float64
end
RestrictedBranchFlow(; ε::Real = _EXACT04_MEASURED_ε) = RestrictedBranchFlow(Float64(ε))

"""
    contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int=1)

Write the SOCP DistFlow branch/voltage terms — identical to
[`contribute!(::ConvexBranchFlow, …)`](@ref), via direct delegation — then shrink ONLY `v`'s
own per-bus squared-voltage upper bound by `pf.ε` (Gan-Low OPF-ε, Theorem 2 / Section IV-D,
eq. 18).

Delegates `contribute!(ConvexBranchFlow(), ctx, feeder; T = T)` FIRST (correctness-drift
avoidance per RESEARCH.md's explicit recommendation to delegate rather than duplicate the
SOC cone / exactness copy / apparent-power cone / balance accumulation). Reads
`ctx.meta[:pf_vars]` (the `(; v, v̂, P, Q, l)` stash `ConvexBranchFlow.contribute!` just
populated), then, for every non-root bus/time, calls a SECOND `set_upper_bound` on the SAME
`v[j,t]` (JuMP allows re-tightening an already-bounded variable) to shrink it from `vmax²`
to `vmax² − pf.ε`.

Gan-Low OPF-ε (Theorem 2/Section IV-D, eq. 18) — shrink ONLY `v`'s own bound. Do NOT touch
`v̂`'s bound (`ConvexBranchFlow`'s `cpydrop` copy, thesis 3.43): `v̂` is a DIFFERENT,
LOWER-bound shadow (plan 20-01 Task 1 confirmed `v ≥ v̂` numerically) — shrinking it would be
a no-op at best, a silent double-restriction at worst.

After the shrink loop, stashes `ctx.meta[:restriction_ε] = pf.ε` and
`ctx.meta[:formulation] = :RestrictedBranchFlow` (D-08 provenance, consumed by plan 20-03's
certificate). Returns `ctx`.
"""
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)

    pv = ctx.meta[:pf_vars]

    # Gan-Low OPF-ε (Theorem 2/Section IV-D, eq. 18) — shrink ONLY v's own bound. Do NOT
    # touch v̂'s bound (ConvexBranchFlow's cpydrop copy, thesis 3.43): v̂ is a DIFFERENT,
    # LOWER-bound shadow (plan 20-01 Task 1 confirmed v ≥ v̂ numerically) — shrinking it would
    # be a no-op at best, a silent double-restriction at worst.
    for j in 1:length(feeder.buses), t in 1:T
        j == feeder.root && continue
        set_upper_bound(pv.v[j, t], feeder.buses[j].vmax^2 - pf.ε)
    end

    ctx.meta[:restriction_ε] = pf.ε             # D-08 provenance
    ctx.meta[:formulation] = :RestrictedBranchFlow   # D-08 provenance
    return ctx
end

# Route the restricted formulation to the SAME tight-gap Clarabel factory ConvexBranchFlow
# uses (a MORE-SPECIFIC method on the `problem_class` trait; multiple dispatch, no solver
# change, no `if formulation ==` branching, no model names a concrete solver — INFRA-02).
problem_class(::RestrictedBranchFlow) = SOCP()

export RestrictedBranchFlow
