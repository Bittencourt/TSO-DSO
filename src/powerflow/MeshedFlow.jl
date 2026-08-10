# src/powerflow/MeshedFlow.jl
#
# SEAM: meshed SOCP branch-flow formulation (MESH-02).
# OWNER: plan 23-02.
#
# `MeshedFlow <: AbstractPowerFlow` -- a thin DELEGATION to `ConvexBranchFlow.contribute!`
# (the `RestrictedBranchFlow` precedent, src/powerflow/RestrictedBranchFlow.jl:174-175),
# with NO new model-time constraint. RESEARCH.md's "Critical codebase finding": the
# `ConvexBranchFlow.contribute!` KCL/v-drop/rotated-cone/exactness-copy/apparent-power-cone
# constraint set is ALREADY graph-generic -- every loop iterates `1:nB` and accumulates via
# `br.to == j` / `br.from == j` predicates, with zero tree-order or parent/child assumption
# anywhere (see ConvexBranchFlow.jl:213-227 for the KCL accumulation this delegates to).
# Handed a `MeshedFeeder` (nB > N-1), it builds a mathematically well-posed SOCP relaxation
# without any code change -- the ONLY thing that previously stood in the way was
# `Feeder`'s own `assert_radial` gate (MESH-01, plan 23-01, resolved by `MeshedFeeder` +
# `assert_connected`).
#
# WHY there is no new model-time constraint here (D-03's resolution): a genuine loop-closure
# condition ("the implied voltage-angle differences sum to zero mod 2π around every
# independent cycle" -- Farivar-Low's angle recovery condition, arXiv:1204.4865) is a
# NONCONVEX trigonometric identity in angles this branch-flow model has ALREADY eliminated
# (the "angle relaxation" step, thesis eq. 3.33's `v = |V|²` magnitude-only variable set).
# Writing it as a JuMP constraint would require reintroducing angle variables and a
# nonconvex sine/cosine relation, defeating the entire point of the branch-flow relaxation.
# The literature's own mechanism (and this phase's own MESH-03) defers loop-consistency to a
# POST-SOLVE a-posteriori angle-recoverability certificate (plan 23-03's
# `certify_angle_recoverable!`) -- never a hard convex constraint at model-build time.
# `ConvexBranchFlow.contribute!`'s existing per-branch cone-tightness gate
# (`assert_socp_exact!`) is necessary but NOT sufficient on a mesh (RESEARCH's Pitfall 14):
# it cannot distinguish a genuine AC operating point from a loop-inconsistent one, both of
# which can pass the per-branch cone identically. MESH-03's certificate is the ONLY thing
# that catches this -- it is a SEPARATE, later deliverable, not something `MeshedFlow`
# itself must build.

using JuMP

"""
    MeshedFlow <: AbstractPowerFlow

The meshed SOCP branch-flow formulation (MESH-02): a peer [`AbstractPowerFlow`](@ref)
subtype, drop-in interchangeable with [`ConvexBranchFlow`](@ref)/[`RestrictedBranchFlow`](@ref)
by dispatch alone (swapping it as the `pf` argument to [`solve_welfare`](@ref) touches
neither device nor assembly code -- there is no `if formulation ==` branching anywhere).

**Mechanism:** [`contribute!`](@ref) delegates ENTIRELY to
`contribute!(ConvexBranchFlow(), ctx, feeder; T)` -- the exact same rotated-cone (3.39),
true voltage-drop (3.33), exactness-copy drop (3.43), apparent-power cone (3.36), and
per-bus KCL accumulation (3.31/3.32) that formulation already builds. Zero new
constraint-writing code exists here: direct code reading of `ConvexBranchFlow.contribute!`
(src/powerflow/ConvexBranchFlow.jl:213-227) confirms its KCL loop is a full signed-incidence
Kirchhoff sum over EVERY branch, correct for any graph (tree or not) -- no BFS, no
parent/child recursion, no tree-order assumption anywhere in that file.

**Why "explicit cycle/loop consistency" (the ROADMAP's hard constraint, D-03) is NOT a
constraint added here:** a genuine loop-closure condition is a nonconvex trigonometric
identity in voltage ANGLES -- and this branch-flow model has already eliminated angles as
decision variables (the angle-relaxation step every Baran-Wu/DistFlow SOCP formulation
performs, magnitude-only `v = |V|²`). There is no way to write that identity as a JuMP
constraint on this model's own variables without reintroducing angles and a nonconvex
sine/cosine relation. Loop-consistency is instead realized as the NEW a-posteriori
angle-recoverability certificate (MESH-03, plan 23-03) -- a genuinely separate, post-solve
deliverable this formulation's `contribute!` never needs to build.

Stashes `ctx.meta[:formulation] = :MeshedFlow` (D-08-style provenance the next plan's
certificate reads) and routes to `problem_class(::MeshedFlow) = SOCP()` -- the SAME
tight-gap Clarabel factory `ConvexBranchFlow`/`RestrictedBranchFlow` already use.
"""
struct MeshedFlow <: AbstractPowerFlow end

"""
    contribute!(pf::MeshedFlow, ctx::ModelContext, feeder; T::Int=1)

Write the SOCP DistFlow branch/voltage terms by pure delegation to
[`contribute!(::ConvexBranchFlow, …)`](@ref) -- byte-identical KCL/v-drop/rotated-cone/
exactness-copy/apparent-power-cone constraint set, since that constraint set is ALREADY
graph-generic (see [`MeshedFlow`](@ref)'s docstring). Adds NOTHING beyond a provenance
stash: `ctx.meta[:formulation] = :MeshedFlow`. Returns `ctx`.
"""
function contribute!(pf::MeshedFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)
    ctx.meta[:formulation] = :MeshedFlow   # D-08-style provenance for plan 23-03's certificate
    return ctx
end

# Route the meshed formulation to the SAME tight-gap Clarabel factory ConvexBranchFlow/
# RestrictedBranchFlow already use (a MORE-SPECIFIC method on the `problem_class` trait;
# multiple dispatch, no solver change, no `if formulation ==` branching -- INFRA-02).
problem_class(::MeshedFlow) = SOCP()

export MeshedFlow
