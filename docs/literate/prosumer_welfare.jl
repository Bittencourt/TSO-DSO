# # Rung 2a — Prosumer Devices, Aggregator Roll-Up & GLB-CVX Social Welfare
#
# This page is the EXP-03 literate proof for the device library: it executes the real
# [`solve_welfare`](@ref) end-to-end during the Documenter build over a full prosumer
# device mix — a [`Thermostatic`](@ref) A/C load, a [`Deferrable`](@ref) shiftable task,
# and a [`PVBattery`](@ref) — rolled into one [`Aggregator`](@ref) (thesis 3.21-3.23), so
# the numbers below cannot silently drift from the code (mirrors the `toy_dc.jl`
# reproducibility-proof pattern, threat T-01-09). The horizon is deliberately short
# (`T = 4`) for a fast, self-contained doc solve — this page is illustrative, not a
# regression (the calibrated ground-truth fixture lives in `test/fixtures_phase4.jl`).
#
# ## The device math
#
# ### Thermostatic (A/C) load — comfort band + RC/ETP recursion
#
# The indoor temperature `Tin[t]` evolves by a linear RC/ETP recursion in power drawn
# `p[t]`, kept inside a comfort band:
#
# ```math
# T_\text{in}[t+1] = T_\text{in}[t] + \alpha\,(T_\text{out}[t] - T_\text{in}[t]) - \beta\, p[t]
# \qquad \text{(3.2)}
# ```
# ```math
# T_\text{min} \le T_\text{in}[t] \le T_\text{max} \qquad \text{(3.3)}
# ```
#
# with a concave-quadratic comfort utility `U(T_\text{in}) = -(b/2)\sum_t (T_\text{in}[t]
# - T_\text{min})^2` (eq. 3.11), whose strictly-positive curvature `b > 0` keeps the
# assembled welfare a convex QP.
#
# ### Deferrable (shiftable) load — energy-window budget
#
# A task (washer, EV charge) draws an energy budget inside a contiguous window, zero
# outside it:
#
# ```math
# E_\text{min} \le \sum_{t \in [t_\text{start},t_\text{end}]} p[t] \le E ,
# \qquad 0 \le p[t] \le P_\text{max} \quad (t \text{ in window}) \qquad \text{(3.4-3.5)}
# ```
#
# with the concave-quadratic soft-target utility `U(p) = -(b/2)\,(\sum_{t\in
# \text{window}} p[t] - E)^2` (eq. 3.12) — a LIVE preference (WR-01: the upper budget is
# an inequality, not a hard equality) so the load reaches `E` when energy is cheap but
# backs off when the network price is high.
#
# ### PV + battery — SOC dynamics and the App. C no-binary parametrization
#
# The co-located PV generator and battery schedule continuous charge/discharge and
# state-of-charge subject to (thesis eqs. 3.6-3.9):
#
# ```math
# \text{soc}[t+1] = \text{soc}[t] + \left(\eta\, p_\text{ch}[t] - p_\text{dch}[t]/\eta\right)\Delta t
# \qquad \text{(3.6, SOC dynamics)}
# ```
# ```math
# 0 \le p_\text{ch}[t] \le \text{pv\_used}[t] \le P_\text{pv}[t] \qquad \text{(3.7, PV-limited charge)}
# ```
# ```math
# 0 \le p_\text{ch}[t],\, p_\text{dch}[t] \le P_\text{max} , \qquad
# E_\text{min} \le \text{soc}[t] \le E_\text{max} \qquad \text{(3.8-3.9)}
# ```
#
# with the App. C (pp. 166-168) concave charge utility minus convex discharge cost
# (eqs. 3.15-3.20). There is deliberately **no binary and no `p_ch·p_dch == 0`
# constraint** — the LOAD-BEARING invariant is the STRICT ordering
#
# ```math
# \lambda_\text{min} < \lambda_\text{med} < \lambda_\text{max}
# ```
#
# which alone makes simultaneous charge and discharge strictly dominated at the
# optimum (a non-strict ordering would flatten the dominance to a tie and admit
# SOC-draining co-optima), so `p_ch[t]·p_dch[t] = 0` is achieved WITHOUT any
# complementarity constraint — verified numerically post-solve by
# [`assert_battery_complementarity!`](@ref) (called internally by `solve_welfare`).
#
# ### Aggregator roll-up — the sole network-facing writer
#
# The `Aggregator` sums its member devices' active injections and utilities into the
# SINGLE nodal quantities the network sees (thesis eqs. 3.21-3.23):
#
# ```math
# U_\text{ag} = \sum_d U_d \qquad \text{(3.21, summed utility)}
# ```
# ```math
# p_\text{ag} = \sum_d p_{\text{inject},d} - P_\text{dc} \qquad \text{(3.22, net active injection)}
# ```
# ```math
# q_\text{ag} = -P_\text{dc}\cdot\tan(\arccos\varphi) \qquad \text{(3.23, power-factor reactive)}
# ```
#
# ### GLB-CVX centralized social welfare
#
# `solve_welfare` assembles every aggregator's utility against a priced frontier import
# and maximizes the centralized social welfare (thesis eq. 3.38):
#
# ```math
# \max \; \sum_j U_{\text{ag}_j} \; - \; \sum_t \lambda_0[t]\, p_\text{import}[t] \qquad \text{(3.38)}
# ```

using TSODSO
using TSODSO: Bus, Branch, Feeder

# ## Building a small radial feeder and one seeded profile draw
#
# A 2-bus radial feeder (root + one load bus) — the same minimal-radial shape used by
# every earlier rung. `generate_profiles` (DATA-04) is a seeded, reproducible Markov-walk
# profile generator (thesis §2.8): the SAME `seed` always regenerates bit-for-bit
# identical `demand`/`pv` vectors.

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
branches = [Branch(1, 2, 0.01, 0.02, 10.0)]
feeder = Feeder(buses, branches, 1)

T = 4
profiles = generate_profiles(seed = 20260720, T = T)
(demand = profiles.demand, pv = profiles.pv)

# ## Constructing the prosumer devices and rolling them into one aggregator
#
# Illustrative (not calibrated-fixture) parameters, mirroring the SHAPE of
# `test/fixtures_phase4.jl`'s `_house_aggregator` — one of each device type at bus 2.

Tout = [20.0, 24.0, 27.0, 23.0]                    # ambient temperature profile (°C), length T
therm = Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)   # eqs 3.2-3.3

defer = Deferrable(2, 1, 4, 0.5, 0.3, 0.5)          # eqs 3.4-3.5, energy window over the full horizon

batt = PVBattery(
    2, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5,               # bus, η, Δt, Pmax, Emin, Emax, soc0
    1.0, 2.0, 3.0,                                   # STRICT λ_min < λ_med < λ_max (App. C)
    profiles.pv,                                     # eqs 3.6-3.9
)

agg = Aggregator(2, 0.9, [therm, defer, batt], profiles.demand)   # eqs 3.21-3.23

# ## Solving the GLB-CVX centralized welfare (eq. 3.38)
#
# `ConvexBranchFlow()` routes to the SOCP backend; `allow_export = true` gives the
# frontier a free-sign net exchange (the SOC-exactness enabler, PF-04) so a PV-heavy
# hour can sell surplus to the MEM rather than dissipating it.

λ₀ = fill(6.0, T)
ctx, objective, dadp = solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = λ₀, allow_export = true)

# The optimal social welfare (summed device utility minus the priced frontier import):

objective

# The day-ahead dynamic price (DADP) — the dual of the nodal active balance at the
# aggregator's bus, over the horizon:

dadp

# And the PRICE-03 surplus stash — the per-aggregator net injection recorded during the
# solve, one entry per aggregator (here: 1), each carrying a length-`T` net vector that
# the next page's welfare accounting consumes:

length(ctx.meta[:agg_net])
