# # Rung 3 — SOCP Convex Branch-Flow & the LinDistFlow Exactness Copy
#
# This page proves the SOCP branch-flow relaxation ([`ConvexBranchFlow`](@ref)) — the
# project's correctness keystone — is EXACT on a real radial feeder, by calling the
# real [`solve_welfare`](@ref) end-to-end and displaying the exactness certificate
# `solve_welfare` computed internally. Never a re-implemented cone or voltage-drop
# constraint.
#
# ## The SOCP + exactness-copy math
#
# `ConvexBranchFlow` relaxes the Baran-Wu / DistFlow branch-flow equations to a
# rotated second-order cone:
#
# ```math
# l_{ij}\, v_i \;\ge\; P_{ij}^2 + Q_{ij}^2 \qquad \text{(3.39, rotated SOC cone)}
# ```
#
# written in JuMP as `[0.5\,l,\, v_i,\, P,\, Q] \in \mathrm{RotatedSecondOrderCone()}`.
# The relaxation alone is not exact in general — it can go STRICT (the squared branch
# current `l` becomes a fictitious over-current) precisely in the over-voltage /
# reverse-flow regime a high-PV feeder produces. The LinDistFlow "exactness copy" fixes
# this: an auxiliary squared voltage `v̂` follows its own voltage-drop recursion
#
# ```math
# \hat v_j = \hat v_i - 2\bigl\{ r(P + rl) + x(Q + xl) \bigr\} \qquad \text{(3.43, exactness-copy voltage drop)}
# ```
#
# and BOTH `v` and `v̂` are bounded by the same squared-magnitude limits
#
# ```math
# V_{\min}^2 \le v,\, \hat v \le V_{\max}^2 \qquad \text{(3.45, voltage bounds on v AND v̂)}
# ```
#
# The copy is not decorative: upper-bounding `v̂ ≤ V²max` drives the loss current `l`
# down until the cone (3.39) holds with equality at the optimum — this is exactly the
# `l → 0` limit that collapses to the previous page's [`LinDistFlow`](@ref) linear
# voltage drop. Whether the cone actually closed tight is a numerical question, not an
# assumption; that is what the validation step below certifies.

using TSODSO

# ## Building a small radial feeder with one aggregator
#
# The same minimal 2-bus radial shape used by the test suite's exactness fixtures,
# with one aggregator (a single-device aggregator is valid — devices need only be
# non-empty). The aggregator (thesis eqs. 3.21-3.23) is the SOLE `:Rp`/`:Rq` network
# writer; its member device must therefore conform to the AGGREGATABLE-device contract
# (returns `(; vars, p_inject, utility)`, writes nothing itself) rather than the
# self-injecting `Interruptible` used on the previous page — here a `Deferrable`
# flexible load (thesis eqs. 3.4-3.5, 3.12).

buses = [
    Bus(1, 0.95, 1.05, true),      # root / MEM frontier
    Bus(2, 0.95, 1.05, false),
]
branches = [Branch(1, 2, 0.01, 0.02, 10.0)]   # r, x, smax (pu)
feeder = Feeder(buses, branches, 1)            # validated on construction

device = Deferrable(2, 1, 1, 0.5, 1.0, 1.0)      # bus, t_start, t_end, E, Pmax, b (b > 0)
agg = Aggregator(2, 0.95, [device], [0.2])       # bus, φ, devices, Pdc

# ## Solving through the real GLB-CVX welfare assembly
#
# [`solve_welfare`](@ref) lets `ConvexBranchFlow` `contribute!` the cone, both voltage
# drops (true + copy), and the loss terms into the shared residuals, then — strictly
# AFTER `assert_solved!` and BEFORE any dual is read — runs the PF-04 exactness gate
# [`assert_socp_exact!`](@ref) INSIDE the solve itself. That gate THROWS (refusing
# prices) on an inexact relaxation, so reaching this line at all is already the passing
# certificate. `allow_export = true` gives the feeder a priced export sink for
# reverse-flow surplus — the exactness enabler for the over-voltage regime.

ctx, objective, dadp =
    solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = 1, λ₀ = [1.0], allow_export = true)

# ## Validation
#
# The optimal social welfare:

objective

# The recovered distribution price (DADP) at the aggregator's bus:

dadp

# The PF-04 exactness certificate: `solve_welfare` already ran `assert_socp_exact!`
# internally and stashed its result. A well-under-tolerance `socp_maxgap` here is a
# REAL, solved number — not a hardcoded placeholder — confirming the cone `l·v ≥ P²+Q²`
# closed with equality at the optimum, so the DADP above is trustworthy.

ctx.meta[:socp_maxgap]
