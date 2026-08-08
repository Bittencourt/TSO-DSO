# src/powerflow/RestrictedBranchFlow.jl
#
# SEAM: Gan-Low OPF-m / OPF-ε restricted-feasible-set formulation (OVR-01).
# OWNER: plan 20-02.
#
# A genuine feasible-set RESTRICTION (never a relaxation tightening; D-01) implementing
# Gan, Li, Topcu & Low's (2015) "Modified OPF" construction (Theorem 2 / Section IV):
# impose the DIRECT constraint `v̂_GL(s) ≤ v̄` — the loss-free shadow voltage (Definition 3,
# eq. 18; the SAME quantity `recover_lossfree_shadow_voltage` computes as post-processing in
# `src/models/ac_oracle.jl`) must not exceed the existing physical upper bound. Since Lemma 1
# proves `v ≤ v̂_GL(s)` always, this new constraint is STRICTLY MORE RESTRICTIVE than the
# existing `v ≤ v̄` alone — so the modified problem ("OPF-m") is a genuine subset of the
# original OPF's feasible set, and Theorem 2 proves "SOCP-m is exact if C1 holds," with NO
# dependence on the optimal solution's own location (unlike the base Theorem 1, whose
# condition C2 fails exactly in the over-voltage regime EXACT-04 documents).
#
# ## Escalation history (Rule 4 / plan 20-02 checkpoint, resolved by roadmap-owner decision)
#
# The FIRST implementation of this file (commit 704f029) implemented only the SIMPLER
# special case OPF-ε (shrink `v`'s own upper bound by a single measured scalar `ε`,
# Section IV-D eq. surrounding (18)) — proven a SUBSET of OPF-m (`F_{OPF-ε} ⊆ F_{OPF-m}`,
# paper's Fig. 9), needing zero new constraints. Exhaustive empirical testing on the EXACT-04
# fixture (documented in `20-02-SUMMARY.md`) found this did NOT close the SOCP exactness gap
# at ANY feasible `ε` (residual stayed `≈1.6` even at the largest feasible `ε≈0.17`, versus
# the `<1e-5` gate; the problem goes `INFEASIBLE` above `ε≈0.18`). Root cause: EXACT-04's
# dominant residual is REVERSE-FLOW-driven (branch 2, negative `P`), not primarily a
# voltage-pinning-at-`v`'s-own-bound effect — the OPF-ε special case does not target this.
#
# The roadmap owner directed implementing the FULLER OPF-m mechanism directly (this file, as
# rewritten): the direct `v̂_GL(s) ≤ v̄` constraint, rather than the simpler bound-shrink. This
# is NOT a violation of D-03's "no auto-tuning/bisection loop" constraint — OPF-m has NO free
# parameter to search; it is a purely STRUCTURAL constraint derived from the existing decision
# variables. See `20-02-SUMMARY.md` for the full empirical record (including whether OPF-m
# itself succeeds or the plan honestly pivots to the D-09/D-10 AC-dual fallback).
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
# than duplicate), then ADDS the new `v̂_GL(s) ≤ v̄` constraint (OPF-m) and, OPTIONALLY (off by
# default; composes if a nonzero `ε` kwarg is supplied), shrinks `v`'s own upper bound
# (OPF-ε) as an EXTRA margin on top. Both are genuine feasible-set RESTRICTIONS — composing
# them only shrinks the feasible set further, never relaxes it.

using JuMP

# The Gan-Low "modification gap" ε (Definition 3, eq. 18), measured on the EXACT-04 fixture
# (test/test_restricted_branch_flow.jl, plan 20-01 Task 2): ε_measured = 0.005811069127373614
# pu²; 1.25× safety multiplier ⇒ ε = 0.007263836409217017 pu² (D-03/D-07 provenance — never
# re-derive without updating this comment). Retained as a NAMED, citable constant for
# researchers who want to COMPOSE the OPF-ε margin on top of OPF-m (see `RestrictedBranchFlow`
# docstring) — it is NOT the default any more (OPF-m needs no such margin; Theorem 2 holds
# unconditionally on C2 once the `v̂_GL(s) ≤ v̄` constraint is present).
const _EXACT04_MEASURED_ε = 0.005811069127373614 * 1.25

"""
    RestrictedBranchFlow <: AbstractPowerFlow

`ConvexBranchFlow` plus Gan, Li, Topcu & Low's (2015) "OPF-m" restriction (Theorem 2 /
Section IV): the DIRECT constraint `v̂_GL(s) ≤ v̄` on the loss-free shadow voltage, forcing
condition C2 to hold by construction regardless of where the optimal solution lands. It is a
peer [`AbstractPowerFlow`](@ref) subtype, drop-in interchangeable with
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

**Mechanism (OPF-m, the PRIMARY restriction, always active):** for every non-root bus `i`
and time `t`, `contribute!` builds `v̂_GL(s)[i,t]` — Gan-Low's loss-free ("every branch's `ℓ`
set to 0") shadow voltage, Definition 3/eq. 18 — as a plain AFFINE JuMP expression in the
ALREADY-EXISTING `P`, `Q`, `l` decision variables (the SAME closed-subtree-loss recursion
[`recover_lossfree_shadow_voltage`](@ref) uses as POST-processing over a solved point; here
it is built at MODEL-BUILD time, before any solve, as a live expression — no new decision
variable is introduced). It then adds `@constraint(model, v̂_GL(s)[i,t] <= v̄_i)`. Since Lemma
1 (Gan-Low 2015) proves `v ≤ v̂_GL(s)` unconditionally for ANY point satisfying the true
branch-flow equations with `ℓ ≥ 0`, this new constraint is STRICTLY MORE RESTRICTIVE than
the existing `v ≤ v̄` alone (it is redundant only if `v̂_GL(s)` happens to already sit at or
below `v̄` — exactly the over-voltage regime where it does NOT, and where it does its work).
Theorem 2 (verbatim, RESEARCH.md): *"SOCP-m is exact if C1 holds"* — unconditionally on C2,
because this constraint forces C2 to hold by construction.

**Optional composable margin (`ε` field, OFF by default):** `RestrictedBranchFlow(; ε=...)`
also accepts the SIMPLER, LESS POWERFUL OPF-ε special case (Section IV-D, eq. surrounding
(18)) — an ADDITIONAL shrink of `v`'s own upper bound by a scalar `ε`, proven a SUBSET of
OPF-m (`F_{OPF-ε} ⊆ F_{OPF-m}`, paper's Fig. 9) and thus safe to compose (it only shrinks the
feasible set further). Defaults to `0.0` (no shrink; OPF-m alone is Theorem-2-sufficient
given C1). `_EXACT04_MEASURED_ε` remains available as a citable, measured value for a
researcher who wants extra margin on top of OPF-m — pass
`RestrictedBranchFlow(; ε = TSODSO._EXACT04_MEASURED_ε)` explicitly.

Caveat (RESEARCH.md Assumptions Log; escalation history above): even OPF-m's exactness
guarantee is CONDITIONAL on C1 holding for the fixture at hand — C1 is checkable a priori
(depends only on `(r,x,p̄,q̄,v̲)`) but was NOT re-verified analytically for the EXACT-04
fixture's specific reverse-flow-heavy regime in this plan; see `20-02-SUMMARY.md` for the
empirical verdict on this exact fixture.
"""
struct RestrictedBranchFlow <: AbstractPowerFlow
    ε::Float64
end
RestrictedBranchFlow(; ε::Real = 0.0) = RestrictedBranchFlow(Float64(ε))

"""
    contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int=1)

Write the SOCP DistFlow branch/voltage terms — identical to
[`contribute!(::ConvexBranchFlow, …)`](@ref), via direct delegation — then add Gan-Low's
OPF-m shadow-voltage restriction `v̂_GL(s) ≤ v̄` (Theorem 2, Section IV) and, OPTIONALLY (only
if `pf.ε > 0`), compose the simpler OPF-ε bound-shrink on top (Section IV-D).

Delegates `contribute!(ConvexBranchFlow(), ctx, feeder; T = T)` FIRST (correctness-drift
avoidance per RESEARCH.md's explicit recommendation to delegate rather than duplicate the
SOC cone / exactness copy / apparent-power cone / balance accumulation). Reads
`ctx.meta[:pf_vars]` (the `(; v, v̂, P, Q, l)` stash `ConvexBranchFlow.contribute!` just
populated).

**OPF-m (primary mechanism, always applied):** builds the SAME rooted parent/child BFS tree
[`recover_lossfree_shadow_voltage`](@ref) uses, then for each time `t` computes, as AFFINE
JuMP expressions (no new variable):

  - `LossInclR[i]`/`LossInclX[i]` — the closed-subtree `r·ℓ`/`x·ℓ` accumulation (reverse-BFS,
    INCLUSIVE of the branch feeding `i`), IDENTICAL formula to the post-processing helper;
  - `v̂_GL[i] = v̂_GL[parent] − 2·(r·P̌ + x·Q̌)`, `P̌ = P[b] − LossInclR[i]`,
    `Q̌ = Q[b] − LossInclX[i]`, `v̂_GL[root] = v[root]`.

Then adds `@constraint(ctx.model, v̂_GL[i,t] <= feeder.buses[i].vmax^2)` for every non-root
`i,t`, registered under `:opfm_shadow_voltage` (dual available for future diagnostics, though
this plan's certificate does not require it).

**OPF-ε (optional, composes on top, OFF by default):** if `pf.ε > 0`, ALSO shrinks `v`'s own
upper bound to `vmax² − pf.ε`, mirroring the escalation history's original mechanism — this
is a strictly-more-restrictive addition (safe to compose per `F_{OPF-ε} ⊆ F_{OPF-m}`), never
applied to `v̂`'s bound (`ConvexBranchFlow`'s `cpydrop` copy, thesis 3.43): `v̂` is a
DIFFERENT, LOWER-bound shadow (plan 20-01 Task 1 confirmed `v ≥ v̂` numerically) — shrinking
it would be a no-op at best, a silent double-restriction at worst.

After both mechanisms are wired, stashes `ctx.meta[:restriction_ε] = pf.ε` and
`ctx.meta[:formulation] = :RestrictedBranchFlow` (D-08 provenance, consumed by plan 20-03's
certificate). Returns `ctx`.
"""
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)

    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    # Optional OPF-ε companion margin (Section IV-D) — OFF by default (pf.ε == 0.0). Shrinks
    # ONLY v's own bound. Do NOT touch v̂'s bound (ConvexBranchFlow's cpydrop copy, thesis
    # 3.43): v̂ is a DIFFERENT, LOWER-bound shadow (plan 20-01 Task 1 confirmed v ≥ v̂
    # numerically) — shrinking it would be a no-op at best, a silent double-restriction at
    # worst.
    if pf.ε > 0.0
        for j in 1:N, t in 1:T
            j == feeder.root && continue
            set_upper_bound(pv.v[j, t], feeder.buses[j].vmax^2 - pf.ε)
        end
    end

    # --- OPF-m (Theorem 2, Section IV): v̂_GL(s) ≤ v̄, the PRIMARY restriction ---
    # Rooted parent/child tree via one BFS traversal from feeder.root — IDENTICAL structure
    # to recover_lossfree_shadow_voltage (src/models/ac_oracle.jl), but here the "loss-free
    # shadow voltage" is built as a live AFFINE JuMP expression over the model's own P/Q/l
    # variables (model-build time), not evaluated numerically over an already-solved point
    # (post-processing time). Same math, different phase of use.
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

    opfm_constraints = Any[]
    for t in 1:T
        # (1) Reverse-BFS closed-subtree loss accumulation, AFFINE in l — byte-identical
        # formula to recover_lossfree_shadow_voltage's LossInclR/LossInclX.
        LossInclR = Dict{Int, AffExpr}()
        LossInclX = Dict{Int, AffExpr}()
        for i in reverse(order)
            accR = zero(AffExpr)
            accX = zero(AffExpr)
            if i != feeder.root
                b_own = branch_of_child[i]
                br_own = feeder.branches[b_own]
                accR += br_own.r * pv.l[b_own, t]
                accX += br_own.x * pv.l[b_own, t]
            end
            for c in children_of[i]
                accR += LossInclR[c]
                accX += LossInclX[c]
            end
            LossInclR[i] = accR
            LossInclX[i] = accX
        end

        # (2) Forward recursion from the root, AFFINE in P, Q, l — byte-identical formula to
        # recover_lossfree_shadow_voltage's v̂_GL recursion.
        v̂_GL = Dict{Int, AffExpr}()
        v̂_GL[feeder.root] = 1.0 * pv.v[feeder.root, t]
        for i in order
            i == feeder.root && continue
            b = branch_of_child[i]
            br = feeder.branches[b]
            P̌ = pv.P[b, t] - LossInclR[i]
            Q̌ = pv.Q[b, t] - LossInclX[i]
            v̂_GL[i] = v̂_GL[br.from] - 2 * (br.r * P̌ + br.x * Q̌)

            # OPF-m (eq. 11/12): the loss-free shadow must not exceed the EXISTING physical
            # upper bound — forces C2 to hold by construction (Theorem 2).
            push!(
                opfm_constraints,
                @constraint(ctx.model, v̂_GL[i] <= feeder.buses[i].vmax^2)
            )
        end
    end
    register_constraint!(ctx, :opfm_shadow_voltage, opfm_constraints)

    ctx.meta[:restriction_ε] = pf.ε             # D-08 provenance
    ctx.meta[:formulation] = :RestrictedBranchFlow   # D-08 provenance
    return ctx
end

# Route the restricted formulation to the SAME tight-gap Clarabel factory ConvexBranchFlow
# uses (a MORE-SPECIFIC method on the `problem_class` trait; multiple dispatch, no solver
# change, no `if formulation ==` branching, no model names a concrete solver — INFRA-02).
problem_class(::RestrictedBranchFlow) = SOCP()

export RestrictedBranchFlow
