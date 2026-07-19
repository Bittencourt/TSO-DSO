# src/pricing/dlmp.jl
#
# SEAM: DLMP extraction + four-way decomposition (PRICE-01 / PRICE-02).
# OWNER: plan 05-02.
#
# Pure convex-duality POST-PROCESSING over a solved `ModelContext` from
# `solve_welfare(feeder, ConvexBranchFlow(), aggs; allow_export=true)`. Reads duals only;
# builds and solves nothing (no model here names a solver). Two public functions:
#
#   * `extract_dlmp(ctx)`    — the day-ahead dynamic price / DLMP: the dual of the nodal
#     ACTIVE-power balance (thesis eq. 3.31), per node per hour. Positive = marginal cost of
#     consumption (sign pinned by the 2-bus regression). REFUSES prices (throws) on an
#     UNGATED SOCP ctx — one carrying a squared-current `:l` but no PF-04 exactness
#     certificate `ctx.meta[:socp_maxgap]` — because a strict SOC relaxation makes `l` a
#     fictitious over-current and the recovered duals physically meaningless (PF-04).
#
#   * `decompose_dlmp(ctx)`  — the four-way DLMP split into energy + loss + congestion +
#     voltage that provably SUMS to the nodal price (added by Task 2 of plan 05-02).
#
# Consumes ONLY the additive Phase-4 seam registered by plan 05-01 (`:cone`, `:vdrop`,
# `:cpydrop`, `:smax`, and `ctx.meta[:pf_vars]`) plus the always-present `:balance_p` — no
# change to `solve_welfare` or the power-flow formulations.

using JuMP

# ---------------------------------------------------------------------------------------------
# Price-refusal gate (PF-04). A dual is a valid price ONLY if the SOCP exactness gate certified
# the cone. `solve_welfare` runs `assert_socp_exact!` (stashing `ctx.meta[:socp_maxgap]`)
# whenever the formulation carries a squared current `:l`; if that certificate is ABSENT on an
# `:l`-bearing ctx the solve was never gated (or was hand-built bypassing the gate) and its
# DADP duals must be REFUSED, not returned (RESEARCH Anti-Pattern "reading the DADP before the
# exactness gate"; threat T-05-01). DC/LinDistFlow ctxs carry no `:l` and are priced normally.
# ---------------------------------------------------------------------------------------------
function _assert_priceable(ctx::ModelContext)
    haskey(ctx.constraints, :balance_p) || throw(
        ArgumentError(
            "extract_dlmp: ctx has no registered :balance_p — this is not a solved " *
            "welfare ModelContext (thesis eq. 3.31)",
        ),
    )
    if haskey(ctx.meta, :pf_vars) &&
       haskey(ctx.meta[:pf_vars], :l) &&
       !haskey(ctx.meta, :socp_maxgap)
        throw(
            ArgumentError(
                "extract_dlmp: refusing to price an UNGATED SOCP ctx — the PF-04 exactness " *
                "certificate `ctx.meta[:socp_maxgap]` is ABSENT while a squared-current `:l` " *
                "is present, so the SOC relaxation was never certified exact. A strict cone " *
                "makes `l` a fictitious over-current and the DADP duals physically meaningless " *
                "(thesis 3.43-3.45; PF-04 gate — see assert_socp_exact!).",
            ),
        )
    end
    return nothing
end

"""
    extract_dlmp(ctx; bus = nothing, T = nothing) -> Matrix{Float64} | Vector{Float64}

The day-ahead dynamic price (DADP / DLMP) — the dual of the nodal ACTIVE-power balance
(thesis eq. 3.31), per node per hour (PRICE-01). Positive = marginal cost of consumption at
that node/hour (sign pinned by the 2-bus hand-solved regression, RESEARCH Pitfall 1).

Requires a `ctx` from `solve_welfare(...)`, which gates every dual behind `assert_solved!`
AND — for a SOCP formulation — the PF-04 exactness certificate. This function REFUSES prices
(throws an `ArgumentError`, never `@assert`) if handed an `:l`-bearing SOCP ctx that lacks
`ctx.meta[:socp_maxgap]` (ungated / inexact cone; threat T-05-01).

With `bus === nothing` (default) it returns the full `(N_buses, T)` DADP matrix
`dual.(ctx.constraints[:balance_p])`. Passing `bus` returns that bus's length-`T` price
vector (`T` defaults to the full horizon; a shorter `T` truncates the leading hours).
"""
function extract_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    bp = ctx.constraints[:balance_p]          # bus × time ConstraintRef array (thesis 3.31)
    N, Tfull = size(bp)
    M = Float64[dual(bp[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end

export extract_dlmp
