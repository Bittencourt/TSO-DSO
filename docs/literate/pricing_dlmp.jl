# # Rung 4 — DADP/DLMP Decomposition & Welfare Accounting
#
# This page is the EXP-03 literate proof for the pricing seam (PRICE-01/PRICE-02/
# PRICE-03): it executes the real [`extract_dlmp`](@ref), [`decompose_dlmp`](@ref), and
# [`welfare_accounting`](@ref) end-to-end during the Documenter build over a genuine
# solved [`ConvexBranchFlow`](@ref) point, so the numbers below cannot silently drift
# from the code (mirrors the `toy_dc.jl` reproducibility-proof pattern, threat T-01-09).
# Every component is reconstructed INDEPENDENTLY from a DISTINCT registered dual — never
# hand-rolled dual extraction — and both `decompose_dlmp` and `welfare_accounting` carry
# HARD internal assertions that throw on a dropped or mis-signed term (T-05-02/T-05-03),
# so reaching the displayed numbers below is itself part of the validation.
#
# ## The DADP — dual of the nodal active balance
#
# The day-ahead dynamic price (DADP), a.k.a. the DLMP, is the dual of the nodal
# ACTIVE-power balance constraint that `solve_welfare` closes at every bus and hour:
#
# ```math
# \lambda_j[t] \; = \; \text{dual}\big(\text{balance\_p}[j,t]\big) \qquad \text{(3.31)}
# ```
#
# Positive `λ_j[t]` is the marginal cost of consuming one more unit at bus `j`, hour `t`.
# [`extract_dlmp`](@ref) REFUSES to return a price (throws) if handed an `:l`-bearing
# SOCP `ctx` that lacks the PF-04 exactness certificate `ctx.meta[:socp_maxgap]` — a
# strict (inexact) SOC relaxation makes `l` a fictitious over-current and any recovered
# dual physically meaningless (threat T-05-01).
#
# ## The four-way decomposition
#
# Because the feeder is a radial TREE, every bus `j` has a unique path root→j, and the
# per-branch price increment along that path telescopes into four INDEPENDENTLY-sourced
# components that provably SUM back to the nodal price:
#
# ```math
# \lambda_j[t] \;=\; \underbrace{\lambda_0[t]}_{\text{energy}} \;+\;
# \underbrace{\sum_{b\in\text{path}} -\,\text{dual}(\text{cone}[b,t])[3]}_{\text{loss (3.39)}} \;+\;
# \underbrace{\sum_{b\in\text{path}} -\,\text{dual}(\text{smax}[b,t])[2]}_{\text{congestion (3.36)}} \;+\;
# \underbrace{\sum_{b\in\text{path}} -2\,r_b\big(\text{dual}(\text{vdrop}[b,t])+\text{dual}(\text{cpydrop}[b,t])\big)}_{\text{voltage (3.33/3.43)}}
# ```
#
# - **energy** — the root MEM price `dual(balance_p[root,t])`, the SAME at every node;
# - **loss** — the SOC/DistFlow marginal-loss term, sourced from the rotated
#   second-order-cone dual (eq. 3.39);
# - **congestion** — the thermal-limit dual (eq. 3.36), zero unless a branch's apparent
#   power actually binds its `smax`;
# - **voltage** — propagation of the voltage-drop bound pressure (eqs. 3.33/3.43), zero
#   when no voltage headroom is engaged.
#
# `decompose_dlmp` asserts `energy + loss + congestion + voltage ≈ dual(balance_p)` at
# every (bus, hour) — a HARD relative-tolerance gate, never a soft check.
#
# ## Welfare accounting — social = prosumer + DSO surplus
#
# The solved GLB-CVX social welfare (eq. 3.38) splits into a prosumer surplus and a DSO
# surplus that provably sum back to it (thesis eqs. 3.46-3.47):
#
# ```math
# \text{prosumer} = \sum_j U_{\text{ag}_j} + \sum_j\sum_t \lambda_j[t]\, p_{\text{ag}_j}[t]
# \qquad \text{(3.46)}
# ```
# ```math
# \text{dso} = -\sum_j\sum_t \lambda_j[t]\, p_{\text{ag}_j}[t] \; - \; \sum_t \lambda_0[t]\, p_\text{import}[t]
# \qquad \text{(3.47)}
# ```
#
# The `Σ_j λ_j·p_agⱼ` price-transfer CANCELS between the two settlements, so
# `social == prosumer + dso == objective_value(ctx.model)` is the correctness net —
# [`welfare_accounting`](@ref) throws if that identity is violated (threat T-05-03).

using TSODSO
using TSODSO: Bus, Branch, Feeder
using JuMP

# ## Building a small radial feeder with two aggregators
#
# A 3-bus radial feeder (root + two downstream load buses), each load bus holding one
# `PVBattery` aggregator — a minimal device mix kept small for a fast doc build.

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
branches = [Branch(1, 2, 0.01, 0.02, 10.0), Branch(2, 3, 0.01, 0.02, 10.0)]
feeder = Feeder(buses, branches, 1)

T = 3
batt2 = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))   # eqs 3.6-3.9
agg2 = Aggregator(2, 0.9, [batt2], fill(0.1, T))

batt3 = PVBattery(3, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.3, T))
agg3 = Aggregator(3, 0.9, [batt3], fill(0.2, T))

# ## Solving the GLB-CVX welfare (eq. 3.38) on the SOCP branch-flow formulation
#
# `allow_export = true` gives the frontier a free-sign net exchange — the SOC-exactness
# enabler (PF-04) that keeps the cone tight so the recovered duals are trustworthy.

λ₀ = fill(40.0, T)
ctx, objective, dadp = solve_welfare(
    feeder, ConvexBranchFlow(), [agg2, agg3]; T = T, λ₀ = λ₀, allow_export = true,
)

# ## Extracting the DADP and its four-way decomposition
#
# The full `(N_buses, T)` DADP matrix (eq. 3.31) — a genuine solved dual, not a
# placeholder:

dlmp = extract_dlmp(ctx)

# The four-way decomposition. `decompose_dlmp` internally asserts the four components
# sum back to `dlmp` at every (bus, hour) — reaching this line without a thrown error IS
# the validation that no term was dropped or mis-signed:

decomp = decompose_dlmp(ctx)
(energy = sum(decomp.energy), loss = sum(decomp.loss), congestion = sum(decomp.congestion), voltage = sum(decomp.voltage))

# ## Welfare accounting — the surplus split
#
# `welfare_accounting` internally asserts `social == prosumer + dso` (eqs. 3.46-3.47) —
# again, reaching the displayed NamedTuple below certifies that identity held:

acct = welfare_accounting(ctx; T = T, λ₀ = λ₀)
