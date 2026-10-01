# src/planning/bilevel_kkt.jl
#
# SEAM: build_bilevel_kkt / solve_bilevel! — the GENUINELY bilevel TSO-DSO planning
# variant (BILEV-01, Phase 29 plan 29-01).
# OWNER: plan 29-01.
#
# (a) THIS IS A GENUINELY BILEVEL GAME. The DSO LEADER chooses investment `y_inv` and
# embeds its OWN LinDistFlow network valuation of the follower's delivered quantity
# `z` (thesis-faithful welfare over the leader's own served elastic demand `d`, priced
# at `v_d`). The TSO FOLLOWER minimizes its OWN cost
# `c_inv*x_inv + sum((c_op[t]-pi_tariff[t])*z[t] + 0.5*q_op[t]*z[t]^2 for t)`, which
# genuinely DIFFERS from the leader's valuation of the same `z` whenever `pi_tariff`
# differs from the leader's marginal value `v_d` — this wedge is exactly what makes
# the game genuinely bilevel, not the integrated/Benders-decomposed problem
# `solve_stackelberg!` (src/planning/benders.jl) already solves.
#
# (b) WHY PLAIN BENDERS (`solve_stackelberg!`) IS INVALID HERE: feeding the
# follower's own reported cost/dual into a leader epigraph (exactly what
# `add_optimality_cut!` does in benders.jl) assumes the follower's value function IS
# the leader's cost-to-go. That assumption holds only when the follower and leader
# share the SAME objective in `z` (the integrated-problem case) — it is FALSE
# whenever `pi_tariff` differs from the leader's own marginal valuation, which is
# exactly this phase's whole point. Never reuse `add_optimality_cut!`/`BendersMaster`
# for this variant "for consistency" — the two problems have genuinely different
# mathematical structure (29-RESEARCH.md Pitfall 1).
#
# (c) THE PRODUCTION METHOD IS A ONE-SHOT SINGLE-LEVEL KKT/MPCC MILP — no outer loop,
# no re-solve, unlike every other file in `planning/`. Built via
# `Model(select_optimizer(MILP()))`.
#
# (d) The follower's complementarity conditions are reformulated via `MOI.SOS1` pairs,
# relying on JuMP/MOI's automatic `SOS1ToMILPBridge` (MOI 1.51.2, verified against the
# pinned HiGHS 1.24.1 in 29-RESEARCH.md). Every paired variable/expression needs a
# FINITE bound, derived in closed form (`_follower_kkt_dual_bound`), never guessed
# (29-RESEARCH.md Pattern 2, Pitfall 3).
#
# (e) THE DSO'S OWN LEADER WELFARE IS AN EMBEDDED LinDistFlow NETWORK (CONTEXT.md's
# post-research amendment, Option B — NOT a fixed linear coefficient), reusing
# `contribute!(pf, ctx, feeder; T)` verbatim, plus a directly-written linear
# elastic-demand variable `d` (NOT the full Aggregator/AbstractDevice roll-up — that
# machinery always produces a QuadExpr utility via `add_to_objective!`, and ANY
# quadratic term anywhere in this MILP's objective/constraints makes it an unsolvable
# MIQP for HiGHS, 29-RESEARCH.md Pitfall 5).
#
# (f) THE COUPLING DIRECTION IS INVERTED versus the existing `FollowerLP`
# (29-RESEARCH.md Pattern 3) — the leader bounds the follower's investment
# (`x_inv <= y_inv`) and the follower freely CHOOSES its own `z`, the opposite of
# `FollowerLP`'s `x_op[t] == z[t]` equality-pin. This is a deliberately NEW
# struct/file, never a parametrized reuse of `FollowerLP`.
#
# (g) BLOCKER-1 REVISION (checker feedback on the initial plan): the follower ALSO
# optionally carries a convex QUADRATIC curvature term in its own per-unit operating
# cost (`0.5*q_op[t]*z[t]^2`, `q_op[t] >= 0`, per CONTEXT.md's locked "Follower convex
# LP/QP" decision). This term NEVER appears verbatim anywhere in this single-level
# MILP (only its LINEAR gradient does, inside `statio_z`, per Pitfall 5's "strictly
# affine" rule) but it is what makes a genuinely NON-DEGENERATE certification fixture
# possible (plan 29-04): with `q_op[t] = 0` (the default, `zeros(T)`), the follower's
# response to the leader's `y_inv` is bang-bang (the original corner fixture, plan
# 29-02); with `q_op[t] > 0`, the follower's response is a continuous, piecewise
# function of `y_inv` that reaches a genuine INTERIOR optimum once `y_inv` is relaxed
# enough — the leader-coupling SOS1 pair `[slack_y, rho_y]` is observed ACTIVE for
# small `y_inv` and INACTIVE once the follower's own unconstrained optimum is reached,
# exercising genuine complementarity switching instead of a single always-zero corner.

using JuMP

"""
    BilevelKKT{Z,MC,D,ML}

The built-ONCE single-level KKT-MILP for the genuinely bilevel TSO-DSO game
(BILEV-01): the DSO LEADER's investment `y_inv` + embedded LinDistFlow network
welfare, folded together with the TSO FOLLOWER's own KKT conditions (stationarity +
SOS1 complementarity) into ONE JuMP `Model`, solved by a SINGLE `optimize!` call — no
outer loop, unlike every other `planning/` file.

# Fields

  - `model::Model` — the single-level KKT-MILP, built ONCE via
    `Model(select_optimizer(MILP()))` (INFRA-02).
  - `y_inv::VariableRef` — the leader's investment decision.
  - `x_inv::VariableRef` — the follower's own investment decision (bounded above by
    `y_inv` via the `slack_y >= 0` / SOS1 complementarity pair, NOT an equality pin).
  - `z::Z` (`Vector{VariableRef}`, length `T`) — the follower's freely-chosen
    delivered quantity.
  - `d::D` (`Vector{VariableRef}`, length `T`) — the DSO's own served elastic demand
    (a plain bounded continuous variable, never an Aggregator/AbstractDevice).
  - `mu_cap::MC` (`Vector{VariableRef}`, length `T`) — the follower's own dual on its
    `z[t] <= corridor_cap*x_inv` capacity constraint.
  - `rho_y::VariableRef` — the follower's own dual on `x_inv <= y_inv`.
  - `rho_lo::VariableRef` — the follower's own dual on `x_inv >= 0`.
  - `rho_max::VariableRef` — the follower's own dual on `x_inv <= x_inv_max`
    (29-REVIEW.md WR-01: `x_inv_max` is a bound in the FOLLOWER's own problem, so it
    needs its own multiplier and SOS1 pair, not just a variable bound).
  - `mu_lo::ML` (`Vector{VariableRef}`, length `T`) — the follower's own dual on
    `z[t] >= 0`.
  - `m_ub::Float64` — the single closed-form (never guessed, never solver-measured)
    upper bound shared by every complementarity dual in the KKT block (see
    [`_follower_kkt_dual_bound`](@ref)).
  - `T::Int` — the horizon.
"""
struct BilevelKKT{Z, MC, D, ML}
    model::Model
    y_inv::VariableRef
    x_inv::VariableRef
    z::Z
    d::D
    mu_cap::MC
    rho_y::VariableRef
    rho_lo::VariableRef
    rho_max::VariableRef
    mu_lo::ML
    m_ub::Float64
    T::Int
end

"""
    _follower_kkt_dual_bound(; corridor_cap, c_inv, c_op, pi_tariff, T, safety) -> Float64

Derive, IN CLOSED FORM, the single shared upper bound `m_ub` for every complementarity
dual in the KKT block (29-REVIEW.md CR-01/WR-03 fix). The bound is valid for EVERY
leader decision `y_inv in [0, y_max]`, and it does not depend on any solver's choice of
dual point.

# Why closed form, not a solver probe

The original implementation (`_measure_follower_kkt_bounds`) solved the follower's
own LP/QP at `y_probe in (0, y_max)` and read the duals. That approach had two defects:

  - At `y_probe = 0` the follower's feasible set collapses to `0 <= x_inv <= 0`, so
    Slater's condition fails and the dual optimal face is UNBOUNDED (`rho_y`/`rho_lo`
    and `mu_cap[t]`/`mu_lo[t]` can both move along a ray). The IPM (Clarabel) returns
    an arbitrary point of that face. On the interior fixture it gave `m_ub = 9544.4`
    where the tight value is `14.8`, so the result depended on the solver and its
    version.
  - A failed probe was skipped silently. If only the `y = 0` probe failed, `m_ub` came
    from the `y_max` probe alone. That under-measured bound cut off every leader
    decision whose `rho_y` exceeded it, and the post-solve at-bound check cannot detect
    a cut-off optimum.

# Derivation

Write `a[t] = pi_tariff[t] - c_op[t]` (the follower's per-unit margin) and
`a⁺ = max(a, 0)`, `a⁻ = max(-a, 0)`. The follower's KKT system is

    statio_x:     c_inv - corridor_cap*Σ_t mu_cap[t] + rho_y + rho_max - rho_lo = 0
    statio_z[t]:  -a[t] + q_op[t]*z[t] + mu_cap[t] - mu_lo[t] = 0

with `q_op[t] >= 0`, `z[t] >= 0` and all multipliers `>= 0`. The single-level MILP
is equivalent to the bilevel problem as long as, for every `y_inv` and every
follower-optimal `(x_inv, z)`, AT LEAST ONE KKT multiplier vector fits inside the box
`[0, m_ub]`. (The follower is convex with affine constraints, so KKT is necessary and
sufficient.) Such a vector always exists:

  - `mu_cap[t] <= a⁺[t]`. If `z[t] > 0`, then `mu_lo[t] = 0` and
    `mu_cap[t] = a[t] - q_op[t]*z[t] <= a[t]`. If `z[t] = 0` and `x_inv > 0`, the cap
    slack is `corridor_cap*x_inv > 0`, so `mu_cap[t] = 0`. If `x_inv = 0`, choose the
    smallest admissible value, `mu_cap[t] = a⁺[t]`.
  - `mu_lo[t] <= a⁻[t]`. It is nonzero only when `z[t] = 0`. Then
    `mu_lo[t] = mu_cap[t] - a[t]`, which is `a⁻[t]` under the choice above (or with
    `mu_cap[t] = 0`).
  - `rho_y, rho_max <= max(corridor_cap*Σ_t a⁺[t] - c_inv, 0)`. If `x_inv > 0`, then
    `rho_lo = 0` and `rho_y + rho_max = corridor_cap*Σ mu_cap - c_inv`. If
    `x_inv = 0`, then `rho_max = 0` (its slack is `x_inv_max > 0`) and `rho_y` takes
    the positive part of the same quantity.
  - `rho_lo <= c_inv`. It is nonzero only when `x_inv = 0`, where
    `rho_lo = c_inv - corridor_cap*Σ a⁺ + rho_y <= c_inv`, using the
    `rho_y = (corridor_cap*Σ a⁺ - c_inv)⁺` choice above.

Returns `safety * max(1e-6, maximum(a⁺), maximum(a⁻), corridor_cap*Σ a⁺ - c_inv, c_inv)`.
The bound does not depend on `q_op`, `x_inv_max` or `y_max`. A nonzero `q_op` only
LOWERS `mu_cap` below `a⁺`, and the box bound must hold for all `y_inv`.

Worked values: corner fixture (`a = [-0.3]`, `c_inv = 1`, `corridor_cap = 2`)
gives `max(0, 0.3, 0, 1) = 1`, so `m_ub = 10`. Interior fixture (`a = [1.5]`,
`c_inv = 0.2`, `corridor_cap = 10`) gives `max(1.5, 0, 14.8, 0.2) = 14.8`, so
`m_ub = 148`. That `14.8` is exactly the tight `rho_y(y=0)`.
"""
function _follower_kkt_dual_bound(;
    corridor_cap::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
    pi_tariff::AbstractVector{<:Real},
    T::Int,
    safety::Real,
)
    margin = Float64[pi_tariff[t] - c_op[t] for t in 1:T]
    a_plus = max.(margin, 0.0)
    a_minus = max.(-margin, 0.0)

    mu_cap_max = maximum(a_plus)
    mu_lo_max = maximum(a_minus)
    rho_y_max = max(corridor_cap * sum(a_plus) - c_inv, 0.0)   # also bounds rho_max
    rho_lo_max = Float64(c_inv)

    bound = max(1e-6, mu_cap_max, mu_lo_max, rho_y_max, rho_lo_max)
    isfinite(bound) || error(
        "_follower_kkt_dual_bound: derived a non-finite complementarity bound " *
        "(mu_cap_max=$mu_cap_max, mu_lo_max=$mu_lo_max, rho_y_max=$rho_y_max, " *
        "rho_lo_max=$rho_lo_max) — refusing to build the single-level MILP",
    )
    return safety * bound
end

"""
    build_bilevel_kkt(feeder, pf::AbstractPowerFlow = LinDistFlow(); T::Int,
                      agg_bus::Int, corridor_cap::Real, x_inv_max::Real, c_inv::Real,
                      c_op::AbstractVector{<:Real}, pi_tariff::AbstractVector{<:Real},
                      q_op::AbstractVector{<:Real} = zeros(T), c_y::Real,
                      y_max::Real, v_d::AbstractVector{<:Real}, d_max::Real,
                      follower_integer::Bool = false, safety::Real = 10.0)
        -> BilevelKKT

Build the genuinely bilevel single-level KKT-MILP EXACTLY ONCE (BILEV-01). See this
file's module header for the full "why single-level KKT, why not Benders" rationale.

**Bilevel semantics (29-REVIEW.md WR-07).** The reformulation is the OPTIMISTIC
bilevel problem. The single MILP minimizes over the leader decision AND the
follower's KKT points jointly, so when the follower has several optimal responses the
leader effectively picks the one it prefers. Leader-level constraints on follower
variables are COUPLING constraints: the network balance (`d = z` on a lossless
feeder), `d <= d_max` and the LinDistFlow voltage bounds. A leader decision whose
follower response violates them is infeasible, not feasible-but-curtailed.

`q_op` (BLOCKER-1 revision) is a NEW keyword defaulting to `zeros(T)`, so every
EXISTING call site (the plan 29-02 corner fixture) is byte-for-bit unaffected; only
plan 29-04's non-degenerate fixture passes a nonzero `q_op`.

# Boundary guards (each throws `ArgumentError` naming the offending value, BEFORE any
`@variable`/`@objective` assembly, mirroring `follower.jl`/`master.jl`):

  - `T >= 1`
  - `pf isa LinDistFlow` — an allowlist: only the strictly affine LinDistFlow network
    is supported (CONTEXT.md locked decision: DSO network LinDistFlow (LP) only). Any
    SOCP, NLP (`ACPowerFlow`) or other formulation is rejected up front, since a
    nonlinear term would make this an MIQP/MINLP that HiGHS cannot solve.
  - `follower_integer` — an integer follower is not supported in this phase
    (continuous-only investment, 29-RESEARCH.md Open Question 3).
  - `corridor_cap > 0`, `x_inv_max > 0`, `c_inv >= 0`, `c_y >= 0`, `y_max > 0`,
    `d_max > 0`, `safety > 0`.
  - `length(c_op) == T`, `length(pi_tariff) == T`, `length(q_op) == T`,
    `length(v_d) == T`.
  - `all(q_op .>= 0)` — `q_op` is the follower's own per-unit QUADRATIC curvature
    coefficient and must stay convex; a negative entry would make the follower's own
    KKT stationarity describe a maximum, not a minimum, silently corrupting the
    single-level reformulation.
  - `1 <= agg_bus <= length(feeder.buses)` and `agg_bus != feeder.root` — the
    elastic-demand bus must be a real, non-root bus so the network genuinely carries
    flow from the root to it (mirrors `solve_welfare`'s own "aggregator bus outside
    feeder buses" guard).

Then derives the shared SOS1 complementarity bound in closed form via
[`_follower_kkt_dual_bound`](@ref), builds `Model(select_optimizer(MILP()))`,
embeds the LinDistFlow network (`contribute!(pf, ctx, feeder; T=T)`, CONTEXT.md
Option B), declares the leader/follower KKT variables, the follower's KKT
stationarity (linear equalities), the complementarity slacks + SOS1 pairs, the
network coupling (the follower's delivered `z` enters at `feeder.root`, the leader's
own served demand `d` draws at `agg_bus`), and the leader's STRICTLY AFFINE objective
`c_y*y_inv + sum(pi_tariff[t]*z[t] - v_d[t]*d[t] for t in 1:T)`.

MEASURES, does not assume, whether the shared `select_optimizer(::MILP)` tolerances
solve this new MILP cleanly to `MOI.OPTIMAL` (29-RESEARCH.md Pitfall 4) — the shared
default is used as-is here; `select_optimizer(::MILP)` is extended with a
keyword-passthrough seam ONLY if measurement (Task 2's fixture) shows it is
insufficient.

Returns a [`BilevelKKT`](@ref).
"""
function build_bilevel_kkt(
    feeder,
    pf::AbstractPowerFlow = LinDistFlow();
    T::Int,
    agg_bus::Int,
    corridor_cap::Real,
    x_inv_max::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
    pi_tariff::AbstractVector{<:Real},
    q_op::AbstractVector{<:Real} = zeros(T),
    c_y::Real,
    y_max::Real,
    v_d::AbstractVector{<:Real},
    d_max::Real,
    follower_integer::Bool = false,
    safety::Real = 10.0,
)
    # ---- Boundary guards FIRST — fail here, not deep in objective assembly. ----------
    T >= 1 || throw(ArgumentError("build_bilevel_kkt needs T >= 1, got T=$T"))

    # ALLOWLIST, not an SOCP denylist (29-REVIEW.md WR-02): ACPowerFlow (NLP) and any
    # QP-class formulation would put a nonlinear term into this MILP and fail deep in
    # JuMP/HiGHS; DCPowerFlow is untested/undocumented here.
    pf isa LinDistFlow || throw(
        ArgumentError(
            "build_bilevel_kkt supports only LinDistFlow (a strictly affine network; " *
            "CONTEXT.md locked decision: DSO network LinDistFlow (LP) only) — got " *
            "$(typeof(pf))",
        ),
    )
    follower_integer && throw(
        ArgumentError(
            "build_bilevel_kkt: an integer follower is not supported in this phase " *
            "(continuous-only investment, 29-RESEARCH.md Open Question 3) — pass " *
            "follower_integer=false",
        ),
    )

    corridor_cap > 0 || throw(
        ArgumentError("build_bilevel_kkt needs corridor_cap > 0, got $corridor_cap"),
    )
    x_inv_max > 0 ||
        throw(ArgumentError("build_bilevel_kkt needs x_inv_max > 0, got $x_inv_max"))
    c_inv >= 0 || throw(ArgumentError("build_bilevel_kkt needs c_inv >= 0, got $c_inv"))
    c_y >= 0 || throw(ArgumentError("build_bilevel_kkt needs c_y >= 0, got $c_y"))
    y_max > 0 || throw(ArgumentError("build_bilevel_kkt needs y_max > 0, got $y_max"))
    d_max > 0 || throw(ArgumentError("build_bilevel_kkt needs d_max > 0, got $d_max"))
    safety > 0 || throw(ArgumentError("build_bilevel_kkt needs safety > 0, got $safety"))

    length(c_op) == T ||
        throw(ArgumentError("c_op has length $(length(c_op)), expected T=$T"))
    length(pi_tariff) == T ||
        throw(ArgumentError("pi_tariff has length $(length(pi_tariff)), expected T=$T"))
    length(q_op) == T ||
        throw(ArgumentError("q_op has length $(length(q_op)), expected T=$T"))
    length(v_d) == T ||
        throw(ArgumentError("v_d has length $(length(v_d)), expected T=$T"))

    all(q_op .>= 0) || throw(
        ArgumentError(
            "build_bilevel_kkt needs every q_op[t] >= 0 (convex follower cost), got " *
            "q_op=$q_op",
        ),
    )

    Np = length(feeder.buses)
    1 <= agg_bus <= Np || throw(
        ArgumentError("build_bilevel_kkt: agg_bus=$agg_bus is outside feeder buses 1:$Np"),
    )
    agg_bus != feeder.root || throw(
        ArgumentError(
            "build_bilevel_kkt: agg_bus=$agg_bus must not equal feeder.root=$(feeder.root) " *
            "(the elastic-demand bus must be a real, non-root bus)",
        ),
    )

    # ---- Derive the shared SOS1 complementarity bound in CLOSED FORM (CR-01). --------
    m_ub = _follower_kkt_dual_bound(;
        corridor_cap = corridor_cap,
        c_inv = c_inv,
        c_op = c_op,
        pi_tariff = pi_tariff,
        T = T,
        safety = safety,
    )

    # ---- Build ONCE: the single-level KKT-MILP. -------------------------------------
    model = Model(select_optimizer(MILP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    contribute!(pf, ctx, feeder; T = T)   # the embedded LinDistFlow network (Option B)

    # WR-03-style capability capture (mirrors solve_welfare): whether a REACTIVE channel
    # exists is decided by the FORMULATION, captured right after it contributes.
    reactive = haskey(ctx.residuals, :Rq)

    # ---- Leader/follower KKT variables. ---------------------------------------------
    @variable(model, 0 <= y_inv <= y_max)
    @variable(model, 0 <= x_inv <= x_inv_max)
    @variable(model, 0 <= z[t = 1:T] <= corridor_cap * x_inv_max)
    @variable(model, 0 <= d[t = 1:T] <= d_max)   # DSO's own served elastic demand
    @variable(model, 0 <= mu_cap[t = 1:T] <= m_ub)
    @variable(model, 0 <= rho_y <= m_ub)
    @variable(model, 0 <= rho_lo <= m_ub)
    @variable(model, 0 <= rho_max <= m_ub)   # WR-01: dual on the follower's x_inv <= x_inv_max
    @variable(model, 0 <= mu_lo[t = 1:T] <= m_ub)

    # ---- Follower KKT stationarity (linear equalities). -----------------------------
    # d/d(x_inv): x_inv is a SINGLE scalar shared across every t's cap constraint, so its
    # stationarity sums mu_cap over t. `rho_max` (WR-01) is the multiplier of the
    # follower's own `x_inv <= x_inv_max`; without it, a leader decision
    # `y_inv > x_inv_max` whose follower response hits `x_inv_max` has no feasible
    # KKT completion and the MILP wrongly declares it infeasible.
    @constraint(
        model,
        statio_x,
        c_inv - corridor_cap * sum(mu_cap[t] for t in 1:T) + rho_y + rho_max - rho_lo == 0
    )
    # d/d(z[t]): the q_op[t]*z[t] term is STILL AFFINE (z[t] to the first power with a
    # constant literal coefficient q_op[t]) — this is the linear KKT stationarity
    # condition of the follower's own quadratic cost, which never itself appears
    # verbatim in this file's objective/constraints. With q_op[t]=0 this reduces
    # byte-for-byte to the original (pre-BLOCKER-1) equation.
    @constraint(
        model,
        statio_z[t = 1:T],
        (c_op[t] - pi_tariff[t]) + q_op[t] * z[t] + mu_cap[t] - mu_lo[t] == 0
    )

    # ---- Complementarity slacks (finite-bound-derivable @expressions) + SOS1 pairs. -
    @expression(model, slack_cap[t = 1:T], corridor_cap * x_inv - z[t])
    @constraint(model, slack_cap_nonneg[t = 1:T], slack_cap[t] >= 0)
    @expression(model, slack_y, y_inv - x_inv)
    @constraint(model, slack_y_nonneg, slack_y >= 0)
    @expression(model, slack_max, x_inv_max - x_inv)   # >= 0 by x_inv's variable bound

    for t in 1:T
        @constraint(model, [slack_cap[t], mu_cap[t]] in MOI.SOS1([1.0, 2.0]))
        @constraint(model, [z[t], mu_lo[t]] in MOI.SOS1([1.0, 2.0]))
    end
    @constraint(model, [slack_y, rho_y] in MOI.SOS1([1.0, 2.0]))
    @constraint(model, [x_inv, rho_lo] in MOI.SOS1([1.0, 2.0]))
    @constraint(model, [slack_max, rho_max] in MOI.SOS1([1.0, 2.0]))

    # ---- Network coupling: the follower's delivered z enters at the root; the ---------
    # leader's own served elastic demand d draws at agg_bus.
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, z[t])
        add_to_residual!(ctx, :Rp, agg_bus, t, -d[t])
    end

    # ---- Close the residuals exactly like solve_welfare. ----------------------------
    size(ctx.residuals[:Rp]) == (Np, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)
    if reactive
        size(ctx.residuals[:Rq]) == (Np, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # ---- Leader objective — STRICTLY AFFINE (Pitfall 5: no quadratic term anywhere ---
    # in this single-level MILP's objective or constraints).
    @objective(model, Min, c_y * y_inv + sum(pi_tariff[t] * z[t] - v_d[t] * d[t] for t in 1:T))

    return BilevelKKT(model, y_inv, x_inv, z, d, mu_cap, rho_y, rho_lo, rho_max, mu_lo, m_ub, T)
end

"""
    solve_bilevel!(kkt::BilevelKKT) -> NamedTuple

Solve the built-ONCE [`BilevelKKT`](@ref) `kkt` via a SINGLE `assert_solved!(kkt.model;
dual = false)` call (MILP — post-SOS1-bridge binaries mean JuMP duals are not
available/meaningful; `dual=false` here is the CORRECT, not a weakened, gate).

Then runs the Pitfall-3 at-bound sanity check: for every complementarity variable
(`mu_cap[t]` ∀t, `rho_y`, `rho_lo`, `rho_max`, `mu_lo[t]` ∀t), asserts its solved value is NOT
within `1e-6` of `kkt.m_ub`. A dual sitting at its big-M bound is a hard error, never
a warning.

This check is NECESSARY, NOT SUFFICIENT (29-REVIEW.md CR-01; Pineda & Morales 2019,
"Solving linear bilevel problems using big-Ms: not all that glitters is gold"). If
`m_ub` were too small, the true optimum would be cut off. The MILP would then return
the best remaining leader decision, whose duals can sit strictly inside `[0, m_ub]`,
and the check would pass. The validity guarantee therefore rests on `m_ub` itself,
which [`_follower_kkt_dual_bound`](@ref) derives in closed form for every
`y_inv in [0, y_max]`. This check only catches a gross violation, such as a
caller-supplied `safety < 1`.

Returns `(; y, x_inv, z, d, total_cost, mu_cap, rho_y, rho_lo, rho_max, mu_lo, model)`.
"""
function solve_bilevel!(kkt::BilevelKKT)
    assert_solved!(kkt.model; dual = false)

    # Pitfall-3 validity check (mandatory, never skipped): a complementarity variable
    # sitting AT its derived SOS1 upper bound is proof the bound was too tight, not a
    # benign coincidence — this would silently misreport the bilevel optimum.
    atol_bound = 1e-6
    for t in 1:kkt.T
        v = value(kkt.mu_cap[t])
        isapprox(v, kkt.m_ub; atol = atol_bound) && error(
            "solve_bilevel!: complementarity variable mu_cap[$t] sits at (or within " *
            "$atol_bound of) the derived SOS1 bound m_ub=$(kkt.m_ub) (value=$v) — " *
            "refusing to trust a result where the true optimum may have been cut off; " *
            "re-derive a looser bound (increase `safety`) and re-build.",
        )
        v = value(kkt.mu_lo[t])
        isapprox(v, kkt.m_ub; atol = atol_bound) && error(
            "solve_bilevel!: complementarity variable mu_lo[$t] sits at (or within " *
            "$atol_bound of) the derived SOS1 bound m_ub=$(kkt.m_ub) (value=$v) — " *
            "refusing to trust a result where the true optimum may have been cut off; " *
            "re-derive a looser bound (increase `safety`) and re-build.",
        )
    end
    v = value(kkt.rho_y)
    isapprox(v, kkt.m_ub; atol = atol_bound) && error(
        "solve_bilevel!: complementarity variable rho_y sits at (or within $atol_bound " *
        "of) the derived SOS1 bound m_ub=$(kkt.m_ub) (value=$v) — refusing to trust a " *
        "result where the true optimum may have been cut off; re-derive a looser bound " *
        "(increase `safety`) and re-build.",
    )
    v = value(kkt.rho_lo)
    isapprox(v, kkt.m_ub; atol = atol_bound) && error(
        "solve_bilevel!: complementarity variable rho_lo sits at (or within $atol_bound " *
        "of) the derived SOS1 bound m_ub=$(kkt.m_ub) (value=$v) — refusing to trust a " *
        "result where the true optimum may have been cut off; re-derive a looser bound " *
        "(increase `safety`) and re-build.",
    )
    v = value(kkt.rho_max)
    isapprox(v, kkt.m_ub; atol = atol_bound) && error(
        "solve_bilevel!: complementarity variable rho_max sits at (or within $atol_bound " *
        "of) the derived SOS1 bound m_ub=$(kkt.m_ub) (value=$v) — refusing to trust a " *
        "result where the true optimum may have been cut off; re-derive a looser bound " *
        "(increase `safety`) and re-build.",
    )

    return (;
        y = value(kkt.y_inv),
        x_inv = value(kkt.x_inv),
        z = value.(kkt.z),
        d = value.(kkt.d),
        total_cost = objective_value(kkt.model),
        mu_cap = value.(kkt.mu_cap),
        rho_y = value(kkt.rho_y),
        rho_lo = value(kkt.rho_lo),
        rho_max = value(kkt.rho_max),
        mu_lo = value.(kkt.mu_lo),
        model = kkt.model,
    )
end

export BilevelKKT, build_bilevel_kkt, solve_bilevel!
