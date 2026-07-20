# # Rung 1-2 — LinDistFlow (Linear Branch Flow)
#
# This page is the reproducibility proof that the residual-seam contract (PF-01/PF-02)
# generalizes from Rung 0's toy single-node balance to a REAL, multi-bus radial
# branch-flow network with a flexible device. It calls the real
# [`solve_linear`](@ref) end-to-end — never a re-implemented `@constraint`/`@objective`
# — so every number below cannot silently drift from the code.
#
# ## The LinDistFlow math
#
# [`LinDistFlow`](@ref) is the loss-less DistFlow model: per-bus active and reactive
# nodal balances (thesis eqs. 3.31/3.32) over the branch flows `P[b,t]`/`Q[b,t]`, plus
# a squared-voltage variable `v[j,t] = |V_j|²` (thesis eq. 3.33) related along each
# branch by the loss-less voltage-drop relation
#
# ```math
# p_{j} - p_{j}^{\text{out}} = 0 \qquad \text{(3.31, active nodal balance)}
# ```
# ```math
# q_{j} - q_{j}^{\text{out}} = 0 \qquad \text{(3.32, reactive nodal balance)}
# ```
# ```math
# v_{\text{to}} = v_{\text{from}} - 2\,(r\,P + x\,Q) \qquad \text{(3.43, loss-less voltage drop)}
# ```
#
# Eq. 3.43 is the `l \to 0` specialization of the eventual SOCP exactness copy that the
# next page (Rung 3 — [`ConvexBranchFlow`](@ref)) builds on: dropping the squared
# branch current `l` from the true DistFlow voltage-drop relation collapses it to this
# linear form. Contrast with `toy_dc.jl`'s DC-only, single-node balance: LinDistFlow
# generalizes to a real radial network AND adds a reactive channel — the `:Rq` residual
# below did not exist on Rung 0.

using TSODSO

# ## Building a small radial feeder with one flexible device
#
# A minimal 2-bus radial feeder (mirroring the shape used across the test suite's
# `FitFixtures.feeder()`): a root/frontier bus and one downstream bus joined by a
# single branch with modest impedance and a slack thermal limit.

buses = [
    Bus(1, 0.95, 1.05, true),      # root / MEM frontier
    Bus(2, 0.95, 1.05, false),
]
branches = [Branch(1, 2, 0.02, 0.03, 10.0)]   # r, x, smax (pu) — slack limit
feeder = Feeder(buses, branches, 1)            # validated on construction

# One interruptible (curtailable) load at bus 2 — a concave-quadratic-utility flexible
# device (thesis eqs. 3.10, 3.13-3.14), the assumption being `b > 0` so the welfare
# maximization stays a convex QP.

device = Interruptible(2, 0.0, 1.0, 3.0, 1.0)   # bus, Pmin, Pmax, a, b (b > 0)

# ## Solving through the real rung-1 assembly
#
# [`solve_linear`](@ref) is the rung-1 centralized assembly: it lets `LinDistFlow`
# `contribute!` its branch/voltage terms into the shared residuals, lets the device
# `contribute!` its signed injection and utility, closes every residual PRESENT
# (`:Rp` always, `:Rq` because `LinDistFlow` allocates it), and solves through the
# `assert_solved!` status choke point before any dual is trusted.

ctx, objective, dadp = solve_linear(feeder, LinDistFlow(), [device]; T = 1, λ₀ = [1.0])

# ## Validation
#
# The optimal welfare of serving the flexible load net of the priced frontier import:

objective

# The recovered distribution price (DADP) — the dual of the active nodal balance at
# the device's bus, over the horizon:

dadp

# And the reactive channel really was exercised: `LinDistFlow` (unlike the DC-only
# Rung 0 formulation) allocates a `:Rq` residual, closed alongside `:Rp` by the same
# data-driven assembly loop with no formulation-flag branching.

haskey(ctx.residuals, :Rq)
