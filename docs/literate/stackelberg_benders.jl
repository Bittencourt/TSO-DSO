# # Rung 6 — Stackelberg-Benders (Planning)
#
# This page is the PVAL-03 literate proof for the planning layer's single-distributor
# Stackelberg equilibrium (PLAN-04/PLAN-05/PLAN-06/PLAN-07/PVAL-01): it executes the real
# [`solve_stackelberg!`](@ref) hand-rolled Benders loop end-to-end during the Documenter
# build, on a toy instance ECONOMICALLY EQUIVALENT to the one Phase 11's permanent
# certification regression uses, so the numbers below are a genuinely solved answer —
# never a hardcoded literal copied from a goldens/test file (mirrors the `admm.jl`/
# `pricing_dlmp.jl` reproducibility-proof pattern, threat T-14-05).
#
# ## The PSR problem-number map — planning-layer symbols
#
# The bilevel game the leader/follower/master triple below solves, mapped to the PSR
# N1–N2 note's own problem numbers and this project's `src/planning/` code symbols:
#
#   - **Follower LP** `α(z)` (transmission-reinforcement investment, given a trial
#     coupling flow `z`) — [`build_follower`](@ref) constructs it ONCE;
#     [`solve_follower!`](@ref) re-solves it at each Benders trial.
#   - **Benders master** (the leader's epigraph relaxation over `y`, accumulating
#     optimality/feasibility cuts from both the follower and the operational oracle) —
#     [`build_master`](@ref) constructs it ONCE; [`add_optimality_cut!`](@ref)/
#     [`add_feasibility_cut!`](@ref) append cuts; [`solve_master!`](@ref) re-solves it.
#   - **The outer Benders loop** tying the two together against the REUSED v1
#     operational welfare oracle — [`solve_stackelberg!`](@ref) (the entrypoint this
#     page calls live below).
#
# ## The coupling seam — z ↔ p_import/p_ag, λ_j ↔ π_s
#
# | Planning-layer symbol | Operational-layer symbol | Where it lives |
# |:-----------------------|:--------------------------|:----------------|
# | `z` (the Benders trial coupling flow) | `p_import` at the oracle's frontier / the aggregator's own net import `p_ag` | `PlanningOracle`'s `pin[t]: p_import[t] == z[t]` ([`build_planning_oracle`](@ref)); the follower's own `coupling[t]: x_op[t] == z[t]` ([`build_follower`](@ref)) |
# | `λ_j[t] ↔ π_s` (the coupling-constraint dual) | the DADP/DLMP the v1 operational layer already reports | the oracle's `pin` dual (`oracle_res.π`, the optimality-cut gradient) and the follower's own `coupling` dual (`follower_res.π_s`) |
#
# ## The Phase 11 empirical certification story (narrated, not re-executed)
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
# the squared form (`Deferrable.jl` builds `-(b/2)*(Σp − E)^2` verbatim; RESEARCH A5 only
# sanctions dropping eq. 3.12's separate additive constant `c`, NOT this expansion term).
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
# [`BendersTrace`](@ref) ledger `solve_stackelberg!` recorded WHILE it ran (plan 12-01,
# `src/planning/trace.jl`) — so no additional solve happens here; both panels read only
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
