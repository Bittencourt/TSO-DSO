# # Rung 5 — ADMM Decomposition & Convergence
#
# This page is the EXP-03 literate proof for the operational decomposition seam
# (ADMM-01/ADMM-03/ADMM-04): it executes the real [`solve_admm`](@ref) hand-rolled
# dual-ascent loop end-to-end during the Documenter build, on the SAME scenario also
# solved centrally by [`solve_welfare`](@ref), so the ADMM-vs-centralized cross-
# validation displayed below is a genuinely solved comparison — never a hardcoded
# number (mirrors the `toy_dc.jl` reproducibility-proof pattern, threat T-01-09).
#
# ## The 2-block ADMM split (thesis 3.46/3.47)
#
# `solve_admm` decomposes the monolithic GLB-CVX social-welfare problem
# (`solve_welfare`) into a per-node **AGR-OPT** block and a whole-network **DSO-OPT**
# block, coupled through a shared price:
#
# ```math
# \text{AGR-OPT}_j:\quad \max_{p_{\text{ag}_j}}\; U_{\text{ag}_j}\bigl(p_{\text{ag}_j}\bigr)
# \;-\;\lambda_j^\top p_{\text{ag}_j} \;-\; \tfrac{\rho}{2}\bigl\lVert p_{\text{ag}_j} - c_j\bigr\rVert_2^2
# \qquad \text{(3.46)}
# ```
# ```math
# \text{DSO-OPT}:\quad \max_{p_{\text{dso}}}\; -\lambda_0^\top p_{\text{import}}
# \;+\;\sum_j\Bigl(\lambda_j^\top p_{\text{dso},j} \;-\; \tfrac{\rho}{2}\bigl\lVert p_{\text{dso},j} - a_j\bigr\rVert_2^2\Bigr)
# \qquad \text{(3.47)}
# ```
#
# The two blocks are reconciled by a dual-ascent update on the shared coupling price
# at every iteration `k`:
#
# ```math
# \lambda_j[t] \;\leftarrow\; \lambda_j[t] \;+\; \rho\, R_{p,j}[t], \qquad
# R_{p,j} = p_{\text{ag}_j} - p_{\text{dso},j} \qquad \text{(primal residual)}
# ```
#
# so `λ_j` converges to the SAME nodal price [`extract_dlmp`](@ref) reports from the
# centralized solve — the load-bearing ADMM-04 cross-validation this page performs.
#
# ## Build once, re-solve many (ADMM-03/ADMM-04)
#
# The practical payoff of this split is NOT solving a smaller problem — it is that
# both the AGR-OPT and DSO-OPT JuMP models are constructed **once**, outside the
# iteration loop, and every subsequent iteration only mutates their linear objective
# coefficients (`−λ_j − ρ·c_j`, `−λ_j − ρ·a_j`) and re-solves. No `Model(...)` call
# ever appears inside `solve_admm`'s loop body, so `num_variables`/`num_constraints`
# on each subproblem are iteration-count-independent — the idiomatic "build once,
# re-solve many" discipline CLAUDE.md requires for any ADMM/Benders outer loop.

using TSODSO
using TSODSO: Bus, Branch, Feeder

# ## Building a small radial feeder with two aggregators
#
# The SAME 3-bus radial shape used on the pricing page (root + two downstream load
# buses, one `PVBattery` aggregator per load bus) — `solve_admm` assumes a 1:1
# node↔aggregator coupling (the Phase-6 scope), which this feeder already satisfies.
# `T = 4` keeps the doc build fast while still exercising a real multi-iteration
# dual-ascent trajectory.

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
branches = [Branch(1, 2, 0.01, 0.02, 10.0), Branch(2, 3, 0.01, 0.02, 10.0)]
feeder = Feeder(buses, branches, 1)

T = 4
batt2 = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
agg2 = Aggregator(2, 0.9, [batt2], fill(0.1, T))
batt3 = PVBattery(3, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.3, T))
agg3 = Aggregator(3, 0.9, [batt3], fill(0.2, T))

λ₀ = fill(40.0, T)

# ## Solving the SAME scenario twice — centralized ground truth, then decomposed
#
# `solve_welfare` on the monolithic `ConvexBranchFlow` SOCP is the centralized
# ground truth. `solve_admm` decomposes the IDENTICAL feeder/aggregators/`λ₀` via
# the hand-rolled 2-block dual-ascent loop above; `allow_export = true` on both
# keeps the SOC relaxation exact (PF-04), the enabler for trustworthy recovered
# duals in either solve path.

ctx_c, obj_c, dadp_c = solve_welfare(
    feeder, ConvexBranchFlow(), [agg2, agg3]; T = T, λ₀ = λ₀, allow_export = true,
)

admm = solve_admm(
    feeder, ConvexBranchFlow(), [agg2, agg3]; T = T, λ₀ = λ₀, ρ = 5.0, allow_export = true,
)

# ## Validation — ADMM ≈ centralized (ADMM-04)
#
# The number of dual-ascent iterations to convergence (both the Boyd primal AND
# dual residuals below their per-unit thresholds — a primal-only stop is refused,
# see `solve_admm`'s docstring):

admm.iters

# The welfare gap between the decomposed and centralized solves — a genuinely
# computed number, not an asserted tolerance (the page displays it; `test/`
# `@testitem`s carry the hard `isapprox` regression gate):

abs(admm.welfare - obj_c)

# The PF-04 SOC-exactness certificate from `solve_admm`'s FINAL converged DSO-OPT
# re-solve — confirming the recovered ADMM DADP is trustworthy, exactly as on the
# Rung-3 page:

admm.exact_maxgap

# ## Convergence figure (CairoMakie, guarded)
#
# `plot_convergence` renders the primal/dual residual trace on a log axis against
# the per-unit stopping thresholds (ADMM-05). The SAME source degrades gracefully
# (no error, just skips the figure) when CairoMakie is absent from the active
# environment — but `docs/Project.toml` now hard-depends on it (docs-only
# environments may; the root package's weakdep discipline is untouched), so the
# docs build itself always has it available once `docs/Manifest.toml` is
# re-resolved.

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie
    plot_convergence(admm.residuals)
end
