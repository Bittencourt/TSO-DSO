# Shared nodal-balance closing helper. Loaded after core/ModelContext.jl because it
# relies on `register_constraint!`.

# Validate that residual `name` exists, is an indexed `Matrix{AffExpr}` and has shape (N, T).
function _check_residual(ctx::ModelContext, name::Symbol, N::Int, T::Int, label)
    r = get(ctx.residuals, name, nothing)
    r isa Matrix{AffExpr} || throw(
        ArgumentError(
            "close_balance!: $(label)residual :$name is missing or not an indexed Matrix{AffExpr} " *
            "(got $(typeof(r))) — no formulation/aggregator has contributed it",
        ),
    )
    size(r) == (N, T) || error(
        "$(label)residual :$name is $(size(r)), expected ($N, $T) — an index escaped the feeder",
    )
    return r
end

"""
    close_balance!(ctx::ModelContext, N::Int, T::Int; reactive::Bool, label::AbstractString = "")
        -> (balance_p, balance_q_or_nothing)

Close the nodal residuals: build `Rp[j,t] == 0` (and, if `reactive`, `Rq[j,t] == 0`) for
`j = 1:N`, `t = 1:T`, register them in `ctx.constraints` as `:balance_p` / `:balance_q`, and
return `(balance_p, balance_q)` (`balance_q === nothing` when `reactive = false`).

This is the single implementation of the block that every builder previously repeated. Operation order is fixed and identical to the former inline blocks: `:Rp` size check,
`:Rp` constraints, register `:balance_p`, then (if `reactive`) `:Rq` size check, `:Rq`
constraints, register `:balance_q`. JuMP/MOI constraint creation order is therefore unchanged.

A residual of the wrong shape raises
`"<label>residual :Rp is (…), expected (N, T) — an index escaped the feeder"` (same for `:Rq`)
before any constraint is built; `label` (e.g. `"scenario 3 "`) prefixes the message.

# Dual recovery (DADP)

The returned container is the very object stored in `ctx.constraints`, so
`dual.(balance_p[priced, :])` remains the distribution price `λ_j[t]` exactly as before.

# Anonymous containers

The constraints are created with `base_name = "balance_p"` / `"balance_q"` rather than a named
`@constraint(model, balance_p[...] ...)`, so nothing is added to the model's object dictionary.
Several scenario contexts can therefore share one model without name collisions, while MOI
names (`balance_p[j,t]`) stay identical.

# Left to the caller

Frontier `p_import`/`q_import` creation and DsoOpt transit-node zero injections are NOT done
here; they must be added to the residuals before calling this function.
"""
function close_balance!(
    ctx::ModelContext,
    N::Int,
    T::Int;
    reactive::Bool,
    label::AbstractString = "",
)
    model = ctx.model
    (N > 0 && T > 0) ||
        throw(ArgumentError("close_balance!: $(label)N=$N and T=$T must both be positive"))
    _check_residual(ctx, :Rp, N, T, label)
    bp = @constraint(
        model,
        [j = 1:N, t = 1:T],
        ctx.residuals[:Rp][j, t] == 0,
        base_name = "balance_p"
    )
    register_constraint!(ctx, :balance_p, bp)          # dual = λ_j (DADP)
    bq = nothing
    if reactive
        _check_residual(ctx, :Rq, N, T, label)
        bq = @constraint(
            model,
            [j = 1:N, t = 1:T],
            ctx.residuals[:Rq][j, t] == 0,
            base_name = "balance_q"
        )
        register_constraint!(ctx, :balance_q, bq)
    end
    return bp, bq
end
