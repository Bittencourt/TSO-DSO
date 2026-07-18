# src/models/linear_solve.jl
#
# SEAM: rung-1 linear central-assembly model (integration).
# OWNER: plan 02-04.
#
# The rung-1 counterpart of `models/toy_dc.jl`: builds a `ModelContext`, lets a chosen
# `AbstractPowerFlow` (DC or LinDistFlow) and the feeder's devices each `contribute!`
# into the SHARED residual / welfare accumulators with no formulation-flag
# branching, pins the per-bus/time nodal balance to zero (registering the constraint so
# its dual — the distribution price / DADP — is recoverable), sets the welfare
# objective from `ctx.meta[:objective]` minus the priced frontier import, and solves as
# the `QP()` factory backend through `assert_solved!(...; dual = true)`. Central, single-solve
# assembly; the ADMM decomposition lands in Phase 6.
#
using JuMP

"""
    solve_linear(feeder, pf::AbstractPowerFlow, devices::Vector{<:AbstractDevice};
                 T::Int = 1, λ₀) -> (ctx::ModelContext, objective::Float64, dadp::Vector{Float64})

Build and solve the rung-1 centralized linear model for `feeder`, returning the first
distribution price. This generalizes `solve_toy_dc` to a real multi-bus feeder, a
swappable `AbstractPowerFlow`, and a vector of `AbstractDevice`s that all meet ONLY at
the shared nodal-balance residual:

1. build `Model(select_optimizer(QP()))` — the concave-quadratic device utility makes the
   welfare a QP, routed by problem class to the accurate-dual conic backend (prices ARE
   duals); this file NEVER names a concrete solver (INFRA-02);
2. wrap it in a [`ModelContext`](@ref); stash `feeder`/`T` in `ctx.meta`;
3. let the power-flow formulation `contribute!` its branch/voltage terms into
   `ctx.residuals[:Rp]` (and `:Rq` for `LinDistFlow`), and each device `contribute!` its
   signed injection into `:Rp` plus its concave utility into `ctx.meta[:objective]` — the
   device variables are stashed under `ctx.meta[:device_vars]`;
4. inject a frontier import `p_import[t] ≥ 0` at `feeder.root` (`+p_import`, mirroring the
   toy-DC convention) so the root balance closes; it is priced at `λ₀`;
5. close EVERY residual present — `:Rp` always, `:Rq` only when `haskey(ctx.residuals, :Rq)`.
   This keys off the residual registry's CONTENTS, not a formulation flag: there is NO
   branching on the formulation type, so swapping DC↔LinDistFlow changes only which
   residuals exist and this loop handles both unchanged (success criterion 4). Both closures are
   registered (`:balance_p` / `:balance_q`) so their duals are recoverable;
6. maximize welfare `Σ utility − λ₀ᵀ·p_import` (thesis eq. 3.38 shape);
7. solve through [`assert_solved!`](@ref)`(...; dual = true, allow_local = false)` — the
   dual is read ONLY after this OPTIMAL gate (Pitfall 5, threat T-02-05).

The returned `dadp` is the dual of the ACTIVE balance `:balance_p` at the FIRST device's
bus (the priced load bus) over the horizon — the first distribution price (DADP). Its
sign follows the toy-DC convention (frontier import positive, load negative ⇒ positive
price = marginal cost, threat T-02-01). Returns `(ctx, objective_value, dadp)`.
"""
function solve_linear(
    feeder,
    pf::AbstractPowerFlow,
    devices::Vector{<:AbstractDevice};
    T::Int = 1,
    λ₀,
)
    # WR-01: an empty `devices` has no priced load — `ctx.meta[:objective]` is never
    # created (bare `KeyError` at welfare assembly) and `devices[1].bus` would
    # `BoundsError`. The rung-1 model is defined around at least the priced load, so
    # reject the empty case up front with a clear message instead of a cryptic crash.
    isempty(devices) &&
        throw(ArgumentError("solve_linear needs at least one device (the priced load)"))

    model = Model(select_optimizer(QP()))   # concave-quad utility ⇒ QP factory backend (INFRA-02)
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    Np = length(feeder.buses)

    # CR-01: every device must sit on a real feeder bus. A device at `bus > Np` grows
    # `:Rp` beyond the balance-closure loop (rows `1:Np`), so its `−p` injection is never
    # pinned to zero and silently vanishes from the network balance — the solver then
    # manufactures welfare from power sourced nowhere (verified: welfare 10.0 vs 2.0). For
    # a bench whose value IS trustworthy prices this must fail loudly, not solve wrong.
    for (k, d) in enumerate(devices)
        1 <= d.bus <= Np ||
            throw(ArgumentError("device[$k] bus=$(d.bus) is outside feeder buses 1:$Np"))
    end

    # Formulation: subtract branch/voltage terms into :Rp (and :Rq for LinDistFlow).
    contribute!(pf, ctx, feeder; T = T)
    # Devices: add signed injection into :Rp + concave utility into ctx.meta[:objective].
    # Stash the returned per-device variables for post-solve inspection.
    ctx.meta[:device_vars] = [contribute!(d, ctx; T = T) for d in devices]

    # Frontier import at the root, priced at λ₀ (thesis §1). Injected like a device
    # (+p_import) so the root active balance closes — mirrors the toy-DC sign convention.
    @variable(model, p_import[t = 1:T] >= 0)
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    # Close EVERY residual present — DATA-DRIVEN on registry CONTENTS, never a branch on
    # the formulation type. :Rp is always populated; :Rq only when the chosen
    # formulation wrote it (LinDistFlow), detected via haskey. Swapping DC↔LinDistFlow
    # changes which residuals exist, and this same loop closes both (criterion 4).
    # CR-01: assert no residual row escaped the feeder before pinning it. If `:Rp` is any
    # bigger than `(Np, T)` an index slipped past the bus range and the closure loop below
    # would leave that row unpinned (a free injection) — fail loudly instead of solving a
    # silently-wrong optimum.
    size(ctx.residuals[:Rp]) == (Np, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)
    if haskey(ctx.residuals, :Rq)                             # registry contents, NOT a flag
        size(ctx.residuals[:Rq]) == (Np, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # Welfare (thesis eq. 3.38 shape): Σ device utility − λ₀ᵀ·p_import.
    welfare = ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T)
    @objective(model, Max, welfare)

    # INFRA-03 gate: never trust (or read) a dual before an OPTIMAL+feasible solve
    # (Pitfall 5, threat T-02-05). assert_solved! raises loudly otherwise.
    assert_solved!(model; dual = true, allow_local = false)

    # DADP = dual of the ACTIVE balance at the priced (first-device) bus (Pitfall 5).
    priced = devices[1].bus
    dadp = dual.(balance_p[priced, :])
    return ctx, objective_value(model), dadp
end

export solve_linear
