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

# Positional arguments (kept as a standalone label so it survives auto-formatting):
#   bus, η, Δt, Pmax, Emin, Emax, soc0,   then   λ_min < λ_med < λ_max (STRICT, App. C),   then   pv
# The three λ values must be strictly increasing (App. C guarantees no simultaneous
# charge/discharge without binaries); `profiles.pv` supplies the eqs 3.6-3.9 PV cap.
batt = PVBattery(2, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, profiles.pv)

agg = Aggregator(2, 0.9, [therm, defer, batt], profiles.demand)   # eqs 3.21-3.23

# ## Solving the GLB-CVX centralized welfare (eq. 3.38)
#
# `ConvexBranchFlow()` routes to the SOCP backend; `allow_export = true` gives the
# frontier a free-sign net exchange (the SOC-exactness enabler, PF-04) so a PV-heavy
# hour can sell surplus to the MEM rather than dissipating it.

λ₀ = fill(6.0, T)
ctx, objective, dadp =
    solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = λ₀, allow_export = true)

# The optimal social welfare (summed device utility minus the priced frontier import):

objective

# The day-ahead dynamic price (DADP) — the dual of the nodal active balance at the
# aggregator's bus, over the horizon:

dadp

# And the PRICE-03 surplus stash — the per-aggregator net injection recorded during the
# solve, one entry per aggregator (here: 1), each carrying a length-`T` net vector that
# the next page's welfare accounting consumes:

length(ctx.meta[:agg_net])

# ## Figure — the scheduled flexibility, device by device
#
# Everything below is read off the ALREADY-SOLVED `ctx` — `value.()` on the per-device
# variable stash `ctx.meta[:agg_device_vars]` (the same seam `assert_battery_complementarity!`
# and the stochastic/MPC orchestrators consume) — no re-solve. Devices are identified by
# their STRUCTURAL variable signature (`:Tin` ⇒ thermostatic, `:soc` ⇒ battery, the
# remainder ⇒ deferrable), never by container order. Three stacked panels, one physical
# unit each (power / temperature / energy — never a twin axis):
#
# 1. **Net active injections (eq. 3.22's summands)** — each device's signed contribution to
#    `p_ag[t]` (negative = consuming): the thermostatic draw `−p`, the deferrable draw `−p`,
#    the PV+battery injection `pv_used − p_ch + p_dch`, the FIXED baseline demand `−Pdc`,
#    and their sum, the aggregator net `p_ag` the network actually sees. On THIS fixture
#    both flexible LOADS sit flat at zero (the two lines overlap on the axis): the
#    deferrable's energy budget is a LIVE preference with `E_min = 0` (WR-01), and at
#    `λ₀ = 6` backing off entirely beats paying for the soft target — the flexibility
#    story here is carried by the battery discharging against the priced frontier.
# 2. **Thermostatic state (eqs. 3.2-3.3)** — the indoor temperature `Tin[t]` riding the
#    ambient `Tout[t]` inside the shaded comfort band `[Tmin, Tmax]`; the comfort utility
#    (3.11) pulls `Tin` toward `Tmin` exactly as hard as the price lets it.
# 3. **Battery state of charge (eqs. 3.6/3.9)** — the SOC trajectory between its dashed
#    `Emin`/`Emax` bounds, the intertemporal storage state coupling the hours.
#
# Same guarded-CairoMakie idiom as `admm.jl`/`socp_applicability.jl`; the block's final
# expression is the `Figure` Documenter renders inline.

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie
    using TSODSO.JuMP: value

    varlist = ctx.meta[:agg_device_vars][agg.bus]
    tvars = only(v for v in varlist if haskey(v, :Tin))
    bvars = only(v for v in varlist if haskey(v, :soc))
    dvars = only(v for v in varlist if !haskey(v, :Tin) && !haskey(v, :soc))

    hours = 1:T
    therm_inj = -value.(tvars.p)                                       # A/C draw (3.2)
    defer_inj = -value.(dvars.p)                                       # shiftable draw (3.4)
    batt_inj = value.(bvars.pv_used) .- value.(bvars.p_ch) .+ value.(bvars.p_dch)  # (3.6-3.9)
    net_inj = value.(ctx.meta[:agg_net][1].net)                        # p_ag (3.22)

    fig = Figure(size = (860, 900))
    ax1 = Axis(
        fig[1, 1];
        xlabel = "hour t",
        ylabel = "net active injection (p.u.)",
        xticks = hours,
        title = "Device schedules at bus $(agg.bus) — signed contributions to p_ag (3.22)",
    )
    hlines!(ax1, [0.0]; color = (:black, 0.3), linewidth = 1)
    scatterlines!(ax1, hours, therm_inj; color = :crimson, label = "thermostatic −p")
    scatterlines!(ax1, hours, defer_inj; color = :orange, label = "deferrable −p")
    scatterlines!(ax1, hours, batt_inj; color = :seagreen, label = "PV+battery injection")
    scatterlines!(
        ax1,
        hours,
        -profiles.demand;
        color = :gray,
        linestyle = :dash,
        label = "baseline −Pdc",
    )
    scatterlines!(
        ax1,
        hours,
        net_inj;
        color = :black,
        linewidth = 3,
        label = "aggregator net p_ag",
    )
    axislegend(ax1; position = :rb, labelsize = 11)

    ax2 = Axis(
        fig[2, 1];
        xlabel = "hour t",
        ylabel = "temperature (°C)",
        xticks = hours,
        title = "Thermostatic state — Tin inside the comfort band (3.2-3.3)",
    )
    hspan!(ax2, therm.Tmin, therm.Tmax; color = (:crimson, 0.08))
    hlines!(
        ax2,
        [therm.Tmin, therm.Tmax];
        color = :crimson,
        linestyle = :dash,
        linewidth = 1,
    )
    scatterlines!(ax2, hours, therm.Tout; color = :gray, linestyle = :dot, label = "Tout")
    scatterlines!(ax2, hours, value.(tvars.Tin); color = :crimson, label = "Tin")
    axislegend(ax2; position = :rb, labelsize = 11)

    ax3 = Axis(
        fig[3, 1];
        xlabel = "hour t",
        ylabel = "stored energy (p.u.·h)",
        xticks = hours,
        title = "Battery state of charge (3.6) between its bounds (3.9)",
    )
    hlines!(
        ax3,
        [batt.Emin, batt.Emax];
        color = :seagreen,
        linestyle = :dash,
        linewidth = 1,
    )
    scatterlines!(ax3, hours, value.(bvars.soc); color = :seagreen, label = "soc")
    axislegend(ax3; position = :rb, labelsize = 11)
    fig
end
