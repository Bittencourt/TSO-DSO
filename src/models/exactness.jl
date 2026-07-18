# src/models/exactness.jl
#
# SEAM: SOCP relaxation exactness invariant — the price-refusal gate (PF-04).
# OWNER: plan 04-05.
#
# The headline correctness gate of the whole project. Defines
# `assert_socp_exact!(ctx; τ)`: after a trusted solve, it computes the per-branch,
# per-time relaxation gap `gap[b,t] = value(l[b,t])·value(v[from_b,t]) −
# (value(P[b,t])² + value(Q[b,t])²)` and asserts `max|gap| < τ` (recommended
# `τ = 1e-5` per-unit; well above Clarabel's `1e-8` gap tolerance — RESEARCH Pitfall 2).
# On FAILURE it THROWS, refusing to return any price: a strict cone at the optimum means
# `l` is a fictitious over-current and the DADP duals are physically meaningless, with no
# solver error to warn you (RESEARCH Pitfall 1). It is called inside `solve_welfare`
# AFTER `assert_solved!` and BEFORE any `dual()` read, gated on `haskey(ctx.meta[:pf_vars],
# :l)` so the DC/LinDistFlow paths are untouched (data-driven, no formulation branch). The
# returned `maxgap` is reported as a first-class output alongside the prices.
#
using JuMP

"""
    assert_socp_exact!(ctx::ModelContext; τ::Real = 1e-5) -> maxgap::Float64

Certify that the SOC branch-flow relaxation is EXACT at the solved point, and REFUSE
prices (throw) if it is not. This is the headline correctness gate of the project (PF-04).

After a trusted solve, for every branch `b` (from-bus `feeder.branches[b].from`) and time
`t ∈ 1:T` it computes the relaxation gap between the two sides of the rotated SOC cone
(thesis 3.39):

    gap[b,t] = value(l[b,t]) · value(v[from_b, t]) − (value(P[b,t])² + value(Q[b,t])²)

and tracks `maxgap = maxₜ,ᵦ |gap[b,t]|`. If `maxgap ≥ τ` it raises a loud `error(...)` naming
`maxgap` and `τ` and stating that prices are REFUSED (thesis 3.43–3.45; PF-04); otherwise it
returns `maxgap` as a FIRST-CLASS output to be reported alongside the prices.

Why this gate exists (RESEARCH Pattern 4 / Pitfall 1): a strict cone at the optimum means the
squared current `l` is a fictitious over-current and the recovered DADP duals are physically
meaningless — with NO solver error to warn you (the solve is `OPTIMAL`). The LinDistFlow
exactness copy (`v̂`, thesis 3.43/3.45) is what drives the cone tight on radial feeders; this
checker is the numerical certificate that it did.

Tolerance (RESEARCH Pitfall 2 / Assumption A5): the default `τ = 1e-5` per-unit sits ~2 orders
of magnitude above Clarabel's `tol_gap_abs/rel = 1e-8` interior-point gap, so a genuinely exact
solve passes with margin while a truly strict cone (the high-PV / over-voltage failure mode) is
still caught. It is DELIBERATELY distinct from the battery-complementarity tolerance in
`solve_welfare` (do not conflate the two).

Reads `ctx.meta[:pf_vars]` (the `(; v, v̂, P, Q, l)` stash), `ctx.meta[:feeder]`, and
`ctx.meta[:T]`. Uses an explicit `error(...)` (never `@assert`, which is elided under `-O`), per
project convention (`src/core/status.jl`).
"""
function assert_socp_exact!(ctx::ModelContext; τ::Real = 1e-5)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    maxgap = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])   # l·v_from  (thesis 3.39 RHS side)
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2      # P² + Q²
        maxgap = max(maxgap, abs(lhs - rhs))
    end

    maxgap < τ || error(
        "SOCP relaxation INEXACT: max|l·v−(P²+Q²)|=$maxgap ≥ τ=$τ — " *
        "prices REFUSED (thesis 3.43-3.45; PF-04)",
    )
    return maxgap
end

export assert_socp_exact!
