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
# FINITE bound, derived by measurement (`_measure_follower_kkt_bounds`), never guessed
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
  - `mu_lo::ML` (`Vector{VariableRef}`, length `T`) — the follower's own dual on
    `z[t] >= 0`.
  - `m_ub::Float64` — the single MEASURED (never guessed) upper bound shared by every
    complementarity dual in the KKT block (see
    [`_measure_follower_kkt_bounds`](@ref)).
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
    mu_lo::ML
    m_ub::Float64
    T::Int
end

"""
    _measure_follower_kkt_bounds(; corridor_cap, x_inv_max, c_inv, c_op, pi_tariff,
                                 q_op, y_max, T, safety) -> Float64

Pattern 2 (29-RESEARCH.md): derive the SINGLE shared upper bound for every
complementarity dual in the KKT block by solving the follower's OWN tiny LP/QP (a
THROWAWAY model, never part of the production single-level MILP) at the two extremes
of the leader's feasible investment range (`y_probe in (0.0, y_max)`), and reading
the resulting duals.

Uses `Model(select_optimizer(LP()))` when `all(iszero, q_op)` (byte-identical to the
pre-BLOCKER-1 probe) and `Model(select_optimizer(QP()))` (Clarabel) otherwise, since a
nonzero `q_op` makes this THROWAWAY probe itself a genuine QP — this is fine, it is
never part of the single-level MILP itself, only a measurement pre-pass, so Pitfall
5's "strictly affine MILP" rule does not apply to it.

Solves via `optimize!` directly (not `assert_solved!`, since `y_probe=0` forces a
fixed/degenerate `x_inv` that must still be accepted). If
`is_solved_and_feasible(m; dual=true)`, collects `abs(dual(inv_bound))` and
`abs(dual(cap[t]))` for every `t` (the follower's own NAMED-constraint duals — these
correspond to `mu_cap`/`rho_y` in the production KKT block) INTO a magnitudes vector,
AND ALSO `abs(reduced_cost(x_inv))`/`abs(reduced_cost(z[t]))` for every `t` (the
follower's own VARIABLE-BOUND duals on `x_inv >= 0`/`z[t] >= 0` — these correspond to
`rho_lo`/`mu_lo[t]` in the production KKT block, via the SAME stationarity identity
`statio_x`/`statio_z` already establish).

Rule 1 fix (auto-fixed bug, empirically found this session): named-constraint duals
ALONE are insufficient on a fixture where the follower's true optimum is a
DEGENERATE corner at BOTH probe extremes (e.g. a `pi_tariff` dominated enough that
`x_inv=z=0` is optimal regardless of `y_inv`) — `dual(inv_bound)`/`dual(cap[t])` both
measure exactly `0.0` there (the bound genuinely isn't economically binding), while
the production MILP's own `statio_x`/`statio_z` equalities still require a
NONZERO `rho_lo`/`mu_lo[t]` to balance (verified: `reduced_cost(x_inv)`/
`reduced_cost(z[t])` are the EXACT KKT multipliers `statio_x`/`statio_z` need at this
degenerate vertex, and are nonzero precisely when the named-constraint duals are
degenerately zero). Omitting them produced a genuinely `MOI.INFEASIBLE` single-level
MILP (no complementarity assignment fit inside `[0, m_ub]`), not merely a
too-tight-but-feasible bound.

Errors (naming both probe statuses) if the magnitudes vector is empty after both
probes — neither probe produced a trusted dual, so no safe bound can be derived;
never silently defaults to a guessed constant.

Returns `safety * max(1e-6, maximum(magnitudes))`.

BLOCKER-1 revision note: probing only the two EXTREMES remains valid for a
CONVEX-quadratic `q_op` follower cost because the follower's marginal value of
relaxing `x_inv <= y_inv` is monotonically NON-INCREASING in `y_inv` for a convex
follower cost — the extremes bracket the true maximum dual magnitude. A FUTURE
fixture whose dual is non-monotonic in `y_inv` would need a denser probe grid; not
needed here.
"""
function _measure_follower_kkt_bounds(;
    corridor_cap::Real,
    x_inv_max::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
    pi_tariff::AbstractVector{<:Real},
    q_op::AbstractVector{<:Real},
    y_max::Real,
    T::Int,
    safety::Real,
)
    magnitudes = Float64[]
    probe_statuses = String[]
    quadratic_probe = !all(iszero, q_op)

    for y_probe in (0.0, Float64(y_max))
        m = quadratic_probe ? Model(select_optimizer(QP())) : Model(select_optimizer(LP()))
        @variable(m, 0 <= x_inv <= x_inv_max)
        @variable(m, z[t = 1:T] >= 0)
        @constraint(m, cap[t = 1:T], corridor_cap * x_inv - z[t] >= 0)
        @constraint(m, inv_bound, x_inv <= y_probe)
        @objective(
            m,
            Min,
            c_inv * x_inv + sum(
                (c_op[t] - pi_tariff[t]) * z[t] + 0.5 * q_op[t] * z[t]^2 for t in 1:T
            )
        )
        optimize!(m)

        push!(
            probe_statuses,
            "y_probe=$y_probe: termination_status=$(termination_status(m)), " *
            "primal_status=$(primal_status(m)), dual_status=$(dual_status(m))",
        )

        if is_solved_and_feasible(m; dual = true)
            push!(magnitudes, abs(dual(inv_bound)))
            push!(magnitudes, abs(reduced_cost(x_inv)))
            for t in 1:T
                push!(magnitudes, abs(dual(cap[t])))
                push!(magnitudes, abs(reduced_cost(z[t])))
            end
        end
    end

    isempty(magnitudes) && error(
        "_measure_follower_kkt_bounds: neither probe (y_inv=0.0, y_inv=$y_max) " *
        "produced a trusted dual — cannot derive a safe complementarity bound, " *
        "refusing to silently default to a guessed constant. Probe statuses:\n" *
        join(probe_statuses, "\n"),
    )

    return safety * max(1e-6, maximum(magnitudes))
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

`q_op` (BLOCKER-1 revision) is a NEW keyword defaulting to `zeros(T)`, so every
EXISTING call site (the plan 29-02 corner fixture) is byte-for-bit unaffected; only
plan 29-04's non-degenerate fixture passes a nonzero `q_op`.

# Boundary guards (each throws `ArgumentError` naming the offending value, BEFORE any
`@variable`/`@objective` assembly, mirroring `follower.jl`/`master.jl`):

  - `T >= 1`
  - `problem_class(pf) isa SOCP` — SOCP-class network formulations are out of scope
    for this phase (CONTEXT.md locked decision: DSO network LinDistFlow (LP) only).
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

Then measures the shared SOS1 complementarity bound via
[`_measure_follower_kkt_bounds`](@ref), builds `Model(select_optimizer(MILP()))`,
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

    problem_class(pf) isa SOCP && throw(
        ArgumentError(
            "build_bilevel_kkt: SOCP-class network formulations are out of scope for " *
            "this phase (CONTEXT.md locked decision: DSO network LinDistFlow (LP) " *
            "only) — got $(typeof(pf))",
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

    # ---- Pattern 2: MEASURE the shared SOS1 complementarity bound, never guess. -----
    m_ub = _measure_follower_kkt_bounds(;
        corridor_cap = corridor_cap,
        x_inv_max = x_inv_max,
        c_inv = c_inv,
        c_op = c_op,
        pi_tariff = pi_tariff,
        q_op = q_op,
        y_max = y_max,
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
    @variable(model, 0 <= mu_lo[t = 1:T] <= m_ub)

    # ---- Follower KKT stationarity (linear equalities). -----------------------------
    # d/d(x_inv): x_inv is a SINGLE scalar shared across every t's cap constraint, so its
    # stationarity sums mu_cap over t.
    @constraint(
        model,
        statio_x,
        c_inv - corridor_cap * sum(mu_cap[t] for t in 1:T) + rho_y - rho_lo == 0
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

    for t in 1:T
        @constraint(model, [slack_cap[t], mu_cap[t]] in MOI.SOS1([1.0, 2.0]))
        @constraint(model, [z[t], mu_lo[t]] in MOI.SOS1([1.0, 2.0]))
    end
    @constraint(model, [slack_y, rho_y] in MOI.SOS1([1.0, 2.0]))
    @constraint(model, [x_inv, rho_lo] in MOI.SOS1([1.0, 2.0]))

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

    return BilevelKKT(model, y_inv, x_inv, z, d, mu_cap, rho_y, rho_lo, mu_lo, m_ub, T)
end

"""
    solve_bilevel!(kkt::BilevelKKT) -> NamedTuple

Solve the built-ONCE [`BilevelKKT`](@ref) `kkt` via a SINGLE `assert_solved!(kkt.model;
dual = false)` call (MILP — post-SOS1-bridge binaries mean JuMP duals are not
available/meaningful; `dual=false` here is the CORRECT, not a weakened, gate).

Then runs the Pitfall-3 validity check: for every complementarity variable
(`mu_cap[t]` ∀t, `rho_y`, `rho_lo`, `mu_lo[t]` ∀t), asserts its solved value is NOT
within `1e-6` of `kkt.m_ub` — a binding "big-M" bound is invalid evidence the true
optimum was cut off, never a benign coincidence, so this is a hard error, never a
warning.

Returns `(; y, x_inv, z, d, total_cost, mu_cap, rho_y, rho_lo, mu_lo, model)`.
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

    return (;
        y = value(kkt.y_inv),
        x_inv = value(kkt.x_inv),
        z = value.(kkt.z),
        d = value.(kkt.d),
        total_cost = objective_value(kkt.model),
        mu_cap = value.(kkt.mu_cap),
        rho_y = value(kkt.rho_y),
        rho_lo = value(kkt.rho_lo),
        mu_lo = value.(kkt.mu_lo),
        model = kkt.model,
    )
end

export BilevelKKT, build_bilevel_kkt, solve_bilevel!
