# # Rung 6 — Stackelberg-Benders (Planning)
#
# This page is the literate proof for the planning layer's single-distributor
# Stackelberg equilibrium: it executes the real
# [`solve_stackelberg!`](@ref) hand-rolled Benders loop end-to-end during the Documenter
# build, on a toy instance ECONOMICALLY EQUIVALENT to the one the permanent
# certification regression uses, so the numbers below are a genuinely solved answer —
# never a hardcoded literal copied from a goldens/test file (mirrors the `admm.jl`/
# `pricing_dlmp.jl` reproducibility-proof pattern).
#
# ## The PSR problem-number map — planning-layer symbols
#
# The bilevel game the leader/follower/master triple below solves, mapped to the PSR
# N1–N2 note's own problem numbers and this project's `src/planning/` code symbols:
#
#   - **Follower LP** `α(z)` (transmission-reinforcement investment, given a trial
#     coupling flow `z`) — [`build_follower`](@ref TSODSO.build_follower) constructs it ONCE;
#     [`solve_follower!`](@ref TSODSO.solve_follower!) re-solves it at each Benders trial.
#   - **Benders master** (the leader's epigraph relaxation over `y`, accumulating
#     optimality/feasibility cuts from both the follower and the operational oracle) —
#     [`build_master`](@ref TSODSO.build_master) constructs it ONCE; [`add_optimality_cut!`](@ref TSODSO.add_optimality_cut!)/
#     [`add_feasibility_cut!`](@ref TSODSO.add_feasibility_cut!) append cuts; [`solve_master!`](@ref TSODSO.solve_master!) re-solves it.
#   - **The outer Benders loop** tying the two together against the REUSED v1
#     operational welfare oracle — [`solve_stackelberg!`](@ref) (the entrypoint this
#     page calls live below).
#
# ## The coupling seam — z ↔ p_import/p_ag, λ_j ↔ π_s
#
# | Planning-layer symbol | Operational-layer symbol | Where it lives |
# |:-----------------------|:--------------------------|:----------------|
# | `z` (the Benders trial coupling flow) | `p_import` at the oracle's frontier / the aggregator's own net import `p_ag` | `PlanningOracle`'s `pin[t]: p_import[t] == z[t]` ([`build_planning_oracle`](@ref TSODSO.build_planning_oracle)); the follower's own `coupling[t]: x_op[t] == z[t]` ([`build_follower`](@ref TSODSO.build_follower)) |
# | `λ_j[t] ↔ π_s` (the coupling-constraint dual) | the DADP/DLMP the v1 operational layer already reports | the oracle's `pin` dual (`oracle_res.π`, the optimality-cut gradient) and the follower's own `coupling` dual (`follower_res.π_s`) |
#
# ## The empirical certification story (narrated, not re-executed)
#
# The leader/follower role assignment and the coupling-dual sign convention used by
# [`solve_stackelberg!`](@ref) are NOT assumed — they were independently CERTIFIED in
# `test/test_planning_certification.jl` (a permanent `[:planning]` regression, retained
# forever) against an INDEPENDENT `BilevelJuMP` MPEC reduction of the SAME toy instance
# reused (in economically-equivalent form) below. Two structurally-different
# reformulations — `BilevelJuMP.StrongDualityMode` (strong-duality equality) and
# `BilevelJuMP.ProductMode` (epsilon-relaxed bilinear-product complementarity) — agree
# with EACH OTHER and with a hand-worked enumeration (`y* = z* = 0.7`, total cost
# `-0.245`); a `BilevelJuMP.BigMMode` + HiGHS attempt is retained ONLY as a documented,
# asserted NEGATIVE regression (its Big-M reformulation combined with this instance's
# quadratic upper-level term produces a genuine MIQP that HiGHS categorically cannot
# solve, at ANY Big-M bound). `solve_stackelberg!` (the production Benders loop) agrees
# with BOTH successfully-solving reformulations and the hand enumeration — NO sign flip
# was ever required in `follower.jl`/`benders.jl`.
#
# This page deliberately does **NOT** re-execute that certification live: it imports
# only `TSODSO` (no `using BilevelJuMP`, `using HiGHS`, or `using Ipopt` anywhere in this
# file) so the published docs site never depends on a validation-oracle-only, test-only
# package — see `test/test_planning_certification.jl` for the full certification proof.

using TSODSO
using TSODSO: Bus, Branch, Feeder

# ## Building a toy instance economically equivalent to the certified fixture
#
# `test/test_planning_certification.jl`'s own toy fixture uses a test-only
# `ToyElasticDevice` (utility `U(p) = a·p − (b/2)·p²`, `a=6.0`, `b=1.0`, `Pmax=10.0`) at
# bus 2 of a near-lossless 2-bus feeder — a test-only struct not reachable from `docs/`
# without adding a new dependency. The PUBLIC `Deferrable` device's own utility (thesis
# eq. 3.12) is `U(p) = −(b/2)·(p − E)²`, which expands to `b·E·p − (b/2)·p² − (b/2)·E²` —
# the elastic device's `a·p − (b/2)·p²` shape whenever `a = b·E`, PLUS the constant
# `−(b/2)·E²`. `Deferrable`'s IMPLEMENTED utility KEEPS that constant — it is inherent in
# the squared form (`Deferrable.jl` builds `-(b/2)*(Σp − E)^2` verbatim; only
# dropping eq. 3.12's separate additive constant `c`, NOT this expansion term).
# Setting `E = 6.0`, `b = 1.0` (so `a = b·E = 6.0`, matching the certified fixture's own
# `a`) with a single-hour window `[1,1]` (`T = 1`) therefore reproduces the certified
# fixture's economics UP TO AN ADDITIVE CONSTANT `(b/2)·E² = 18` on the leader's total
# cost: the equilibrium point (`y*`, `z*`) and every price/dual are IDENTICAL (an additive
# constant never moves an argmax), but every OBJECTIVE-LEVEL quantity on this page is
# shifted by `+18` relative to the certified fixture — expect `UB ≈ −0.245 + 18 = 17.755`
# below, NOT the certified fixture's own `−0.245`. (The offset also inflates `|UB|` inside
# `solve_stackelberg!`'s relative-gap normalizer `max(1, |UB|)`, so the SAME `tol = 1e-6`
# stops this instance a few 1e-3 short of the certified `z* = 0.7` — see the `z` note
# below.) All of this uses ONLY public `TSODSO` API.

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
branches = [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)]
feeder = Feeder(buses, branches, 1)

T = 1
dev = Deferrable(2, 1, 1, 6.0, 10.0, 1.0)
agg = Aggregator(2, 0.9, [dev], fill(0.0, T))

λ₀ = [4.0]
follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

# ## Solving the Stackelberg equilibrium live
#
# `checkpoint_dir` must be writable — `mktempdir()` gives every doc build a fresh,
# disposable checkpoint directory. `solve_stackelberg!` builds the oracle/follower/master
# ONCE, then iterates the Benders loop to the documented relative UB/LB gap tolerance.

checkpoint_dir = mktempdir()
result = solve_stackelberg!(
    feeder,
    LinDistFlow(),
    [agg];
    λ₀ = λ₀,
    T = T,
    follower_kwargs = follower_kwargs,
    master_kwargs = master_kwargs,
    tol = 1e-6,
    max_iter = 100,
    checkpoint_dir = checkpoint_dir,
)

# ## Validation — a genuinely converged Benders gap
#
# The converged relative UB/LB gap (never a hardcoded tolerance echo — the loop's own
# termination criterion):

result.gap

# The leader's converged flexibility investment `y`:

result.y

# The converged coupling flow `z` — economically, this instance reproduces the SAME
# ballpark as the certified fixture's own hand-enumerated `z* = 0.7` (see the
# certification narrative above): the underlying economics are identical by construction
# UP TO the `+18` additive constant discussed above, and that constant's inflation of
# `|UB|` in the relative-gap normalizer `max(1, |UB|)` is exactly why the converged `z`
# here sits a few 1e-3 from `0.7` rather than matching it to solver precision (the same
# `tol = 1e-6` is effectively ~17.8× looser on this instance's gap). The exact digits
# below come from THIS live solve, not copied from `test_planning_certification.jl`:

result.z

# The converged upper bound — the leader's total cost at the incumbent FOR THIS
# instance's `Deferrable` utility, i.e. the certified fixture's hand-enumerated `−0.245`
# SHIFTED by the kept constant `(b/2)·E² = 18` (expect `≈ 17.755`, NOT `−0.245`):

result.UB

# The offset-corrected leader cost — subtracting the `(b/2)·E²` constant makes it
# directly comparable to the certified fixture's own hand-enumerated total cost `−0.245`:

result.UB - 0.5 * 1.0 * 6.0^2

# ## Benders convergence figure (CairoMakie)
#
# The canonical Benders picture, drawn from `result.trace` — the per-iteration
# [`BendersTrace`](@ref) ledger `solve_stackelberg!` recorded WHILE it ran
# (`src/planning/trace.jl`) — so no additional solve happens here; both panels read only
# the already-recorded, JuMP-free ledger. Left: the incumbent upper bound `UB` and the
# relaxed master's lower bound `LB` close on each other as cuts accumulate. Right: the
# relative gap `(UB − LB)/max(1, |UB|)` — the loop's OWN stopping quantity, never a
# re-derived one — decays below the `tol = 1e-6` passed to `solve_stackelberg!` above,
# on a log axis. `UB = Inf` (before the first optimality iteration) and `gap = NaN`
# (every feasibility-branch row) are legitimate trace sentinels, NOT defects (see
# `BendersTrace`'s docstring) — they are masked out of the plotted series here, never
# guarded away in the ledger itself. The `max.(·, eps())` floor mirrors the package's
# own `TSODSOMakieExt` log-axis guard: a gap that converges to exactly `0.0` maps to
# `log10(0) = -Inf`, which Makie rejects — clamping degrades it gracefully to the axis
# floor instead of crashing the docs build.

using CairoMakie

trace = result.trace
ks = trace.iter_trace
ub_mask = isfinite.(trace.UB_trace)
gap_mask = .!isnan.(trace.gap_trace)

fig = Figure(size = (900, 380))
ax_bounds = Axis(
    fig[1, 1];
    xlabel = "Benders iteration k",
    ylabel = "leader objective bound",
    title = "Benders bounds: incumbent UB & master LB",
)
scatterlines!(
    ax_bounds,
    ks[ub_mask],
    trace.UB_trace[ub_mask];
    label = "UB (incumbent)",
    color = :crimson,
)
scatterlines!(ax_bounds, ks, trace.LB_trace; label = "LB (master)", color = :dodgerblue)
axislegend(ax_bounds; position = :rb)

ax_gap = Axis(
    fig[1, 2];
    xlabel = "Benders iteration k",
    ylabel = "relative gap (UB − LB) / max(1, |UB|)",
    yscale = log10,
    title = "Relative gap vs stopping tolerance",
)
scatterlines!(
    ax_gap,
    ks[gap_mask],
    max.(trace.gap_trace[gap_mask], eps());
    label = "relative gap",
    color = :purple,
)
hlines!(
    ax_gap,
    [1e-6];
    label = "tol (solve_stackelberg!)",
    color = :black,
    linestyle = :dash,
)
axislegend(ax_gap; position = :rt)
fig

# ## Rung 6 at scale — a full day-ahead horizon on IEEE-13 (T=24)
#
# Everything above is a T=1 toy instance, chosen to stay directly comparable to the
# `test/test_planning_certification.jl` certification narrative. The headline
# result (`test/test_planning_benders_ieee13.jl`) demonstrates
# `solve_stackelberg!` with the REAL `ConvexBranchFlow()` SOCP branch-flow formulation on
# a realistic multi-bus, multi-period feeder (`ieee13_modified()`) at `T=4`; this section
# extends that same demonstration to a full day-ahead horizon, `T=24`, confirming the
# Benders loop scales cleanly beyond the suite's own `≤2min` budget (this section is
# OUTSIDE the test suite — it runs once, live, as part of this documentation build).
#
# `test/fixtures_planning_ieee13_short.jl`'s own `IEEE13ShortHorizonFixtures.house_agg`
# hard-codes `T = 4` as a MODULE CONSTANT referenced inside its own body (feeding
# `generate_profiles`/`Thermostatic`/`PVBattery`), so it does not generalize to an
# arbitrary `T` by simply passing a larger value — a small, `T=24`-specific variant,
# `house_agg_t24`, is defined inline below instead, reusing the SAME tuned magnitudes
# (`load_scale=0.01`, `pv_scale=0.03`, `batt_pmax=0.02`, `batt_emax=0.1`,
# `batt_soc0=0.05`, the STRICT battery price triple `λ_min=3.8 < λ_med=6.2 < λ_max=8.9`)
# as `IEEE13ShortHorizonFixtures`'s own T=4 recipe, parametrized by `T` this time. This
# page imports `using TSODSO` ONLY (no test-only fixture module), so the day-ahead price
# profile below is also redefined inline — the SAME digitized morning-ramp/evening-peak
# shape `test/fixtures_ieee13.jl`'s own `IEEE13Fixtures.mem_price_profile()` uses (low
# overnight, moderate midday shoulder, evening peak), not imported from that test-only
# module.

function house_agg_t24(
    bus;
    seed::Integer,
    φ::Real = 0.90,
    load_scale::Real = 0.01,
    pv_scale::Real = 0.03,
    batt_pmax::Real = 0.02,
    batt_emax::Real = 0.1,
    batt_soc0::Real = 0.05,
)
    prof = generate_profiles(seed = seed + bus, T = 24)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, 24))
    batt =
        PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0, 3.8, 6.2, 8.9, Ppv)
    return Aggregator(bus, φ, [therm, batt], Pdc)
end

feeder24 = TSODSO.ieee13_modified()
N24 = length(feeder24.buses)
aggs24 = [house_agg_t24(bus; seed = 20260718) for bus in 2:N24]

λ0_24 = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,   # 00–05 overnight trough
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,   # 06–11 morning ramp -> midday shoulder
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,   # 12–17 afternoon rise -> evening peak
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,   # 18–23 evening decline
]

# `follower_kwargs24`/`master_kwargs24` are DELIBERATELY smaller than the T=4 headline
# test's own kwargs (`y_max=0.05, corridor_cap=1.0`): a live probe found
# that configuration throws a genuine `assert_battery_complementarity!` violation at
# `t=7` once the full 24-hour price swing is in play (OUT OF SCOPE for `inexact_policy`
# — a complementarity violation, not an exactness-class throw, per `solve_stackelberg!`'s
# own documented disambiguation). Tightening the leader's investment ceiling
# (`y_max=0.03`, `corridor_cap=0.5`, `x_inv_max=0.03`) keeps every Benders trial inside a
# region where the battery's own complementarity gate holds throughout — confirmed
# below by a full, live, error-free run. `master_kwargs24` again OMITS `α_op_lb`/
# `α_x_lb` entirely (the `:auto` default, same as the T=4 headline test).

follower_kwargs24 =
    (; corridor_cap = 0.5, x_inv_max = 0.03, c_inv = 0.01, c_op = fill(0.01, 24))
master_kwargs24 = (; c_y = 0.01, y_max = 0.03)

checkpoint_dir24 = mktempdir()
result24 = solve_stackelberg!(
    feeder24,
    ConvexBranchFlow(),
    aggs24;
    λ₀ = λ0_24,
    T = 24,
    follower_kwargs = follower_kwargs24,
    master_kwargs = master_kwargs24,
    tol = 1e-6,
    max_iter = 100,
    checkpoint_dir = checkpoint_dir24,
)

# ## T=24 validation — real, observed numbers
#
# The converged relative UB/LB gap (measured on THIS run: `iters=15`,
# `gap≈3.09e-7`, well inside `tol=1e-6`):

result24.gap

# The leader's converged flexibility investment `y` (measured on this run: `0.015`,
# half of `y_max=0.03` — the master's own box did not bind at the optimum):

result24.y

# The converged coupling flow `z` across all 24 hours (measured on this run: `0.015`
# pu during the overnight/morning/evening hours where importing is economic, `0.0`
# during the midday hours where it is not):

result24.z

# The converged upper bound (total leader cost at the incumbent):

result24.UB

# The incumbent's exactness certificate: the
# verdict of the very oracle solve that produced `UB`, its measured cone residual, and
# whether `UB`/`gap` certify only the SOC relaxation. Measured 2026-10-01: `:exact`,
# `incumbent_socp_maxgap ≈ 3.03e-9`, `ub_relaxation_only = false` — so `UB` is a genuine
# upper bound here, and no AC physics re-check was triggered (`ac_report === nothing`):

(result24.incumbent_exactness, result24.incumbent_socp_maxgap, result24.ub_relaxation_only)

#-

result24.ac_report

# ## T=24 Benders convergence figure, with a cone-gap panel (CairoMakie)
#
# The SAME canonical Benders bounds/gap panels as the T=1 figure above, PLUS a THIRD
# panel plotting `result24.trace.socp_maxgap_trace` — the per-iteration MEASURED SOCP
# cone residual `max |l·v − (P²+Q²)|` (`src/planning/trace.jl`), recorded on
# every row whose oracle solve ran the exactness gate (it used
# to be a `NaN` placeholder on every exact row, which left this panel empty by
# construction). `NaN` remains only on rows with no trusted oracle solve — here the
# follower-feasibility-cut rows, iterations 2–13 — and is masked with the SAME
# `isfinite.(...)` + `max.(..., eps())` log-axis-floor idiom the other two panels use.
# Measured 2026-10-01: the three oracle-solving rows (k = 1, 14, 15) record 3.02e-9,
# 3.03e-9 and 4.09e-9 — every one far inside the exactness gate's tolerance, i.e. this
# configuration is SOCP-exact at every iteration that reached the oracle. Contrast
# `test/test_planning_inexact_policy.jl`, whose fixture records inexact rows at
# 1.7e-3–2.4e-3.

trace24 = result24.trace
ks24 = trace24.iter_trace
ub_mask24 = isfinite.(trace24.UB_trace)
gap_mask24 = .!isnan.(trace24.gap_trace)
sg_mask24 = isfinite.(trace24.socp_maxgap_trace)

fig24 = Figure(size = (1300, 380))
ax_bounds24 = Axis(
    fig24[1, 1];
    xlabel = "Benders iteration k",
    ylabel = "leader objective bound",
    title = "T=24: Benders bounds (UB & LB)",
)
scatterlines!(
    ax_bounds24,
    ks24[ub_mask24],
    trace24.UB_trace[ub_mask24];
    label = "UB (incumbent)",
    color = :crimson,
)
scatterlines!(
    ax_bounds24,
    ks24,
    trace24.LB_trace;
    label = "LB (master)",
    color = :dodgerblue,
)
axislegend(ax_bounds24; position = :rb)

ax_gap24 = Axis(
    fig24[1, 2];
    xlabel = "Benders iteration k",
    ylabel = "relative gap (UB − LB) / max(1, |UB|)",
    yscale = log10,
    title = "T=24: relative gap vs tol",
)
scatterlines!(
    ax_gap24,
    ks24[gap_mask24],
    max.(trace24.gap_trace[gap_mask24], eps());
    label = "relative gap",
    color = :purple,
)
hlines!(ax_gap24, [1e-6]; label = "tol", color = :black, linestyle = :dash)
axislegend(ax_gap24; position = :rt)

ax_cone24 = Axis(
    fig24[1, 3];
    xlabel = "Benders iteration k",
    ylabel = "SOCP cone gap (socp_maxgap)",
    yscale = log10,
    title = "T=24: incumbent cone-gap",
)
scatterlines!(
    ax_cone24,
    ks24[sg_mask24],
    max.(trace24.socp_maxgap_trace[sg_mask24], eps());
    label = "socp_maxgap",
    color = :darkgreen,
)
axislegend(ax_cone24; position = :rt)
fig24
