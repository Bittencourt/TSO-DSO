# src/models/exactness.jl
#
# SEAM: SOCP relaxation exactness invariant — the price-refusal gate (PF-04).
# OWNER: plan 04-05.
#
# The headline correctness gate of the whole project. Defines
# `assert_socp_exact!(ctx; rtol, atol)`: after a trusted solve, it computes the per-branch,
# per-time relaxation gap `gap[b,t] = value(l[b,t])·value(v[from_b,t]) −
# (value(P[b,t])² + value(Q[b,t])²)` and asserts it is small RELATIVE to the cone magnitude:
# `|gap| ≤ atol + rtol·max(|l·v|, |P²+Q²|)` per branch (WR-01). This is a SCALE-FREE metric,
# so the gate's protective strength does NOT silently weaken with the per-unit base — the
# same physical cone slack is judged identically on a 1 MVA or a 100 MVA base.
# On FAILURE it THROWS, refusing to return any price: a strict cone at the optimum means
# `l` is a fictitious over-current and the DADP duals are physically meaningless, with no
# solver error to warn you (RESEARCH Pitfall 1). It is called inside `solve_welfare`
# AFTER `assert_solved!` and BEFORE any `dual()` read, gated on `haskey(ctx.meta[:pf_vars],
# :l)` so the DC/LinDistFlow paths are untouched (data-driven, no formulation branch). The
# returned `maxgap` (the absolute cone residual) is reported as a first-class output.
#
using JuMP

"""
    assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-8)
        -> maxgap::Float64

Certify that the SOC branch-flow relaxation is EXACT at the solved point, and REFUSE
prices (throw) if it is not. This is the headline correctness gate of the project (PF-04).

After a trusted solve, for every branch `b` (from-bus `feeder.branches[b].from`) and time
`t ∈ 1:T` it computes the relaxation gap between the two sides of the rotated SOC cone
(thesis 3.39):

    lhs   = value(l[b,t]) · value(v[from_b, t])          # l·v_from
    rhs   = value(P[b,t])² + value(Q[b,t])²              # P² + Q²
    gap   = |lhs − rhs|

and compares it to a RELATIVE threshold scaled by the cone magnitude (WR-01):

    gap ≤ atol + rtol · max(|lhs|, |rhs|)

tracking `maxrel = maxₜ,ᵦ gap / (atol + max(|lhs|, |rhs|))`. If any branch violates the
bound it raises a loud `error(...)` naming the worst relative gap and REFUSING prices
(thesis 3.43–3.45; PF-04); otherwise it returns `maxgap = maxₜ,ᵦ gap` — the absolute cone
residual — as a FIRST-CLASS output reported alongside the prices.

Why RELATIVE (WR-01): the cone residual `l·v − (P²+Q²)` is in per-unit², so its magnitude
scales with the per-unit base. An ABSOLUTE tolerance therefore accepts a larger fractional
cone slack on a big base (e.g. the 100 MVA IEEE-13 fixture, where `l·v ≈ 5e-3` pu²) than on
a small one — the SAME physical inexactness could pass on one base and be refused on another.
Normalizing by the cone magnitude makes the verdict depend on the physics, not the base. The
small `atol` floor guards near-zero (no-flow) branches against a divide-by-tiny blow-up.

Why this gate exists (RESEARCH Pattern 4 / Pitfall 1): a strict cone at the optimum means the
squared current `l` is a fictitious over-current and the recovered DADP duals are physically
meaningless — with NO solver error to warn you (the solve is `OPTIMAL`). The LinDistFlow
exactness copy (`v̂`, thesis 3.43/3.45) is what drives the cone tight on radial feeders; this
checker is the numerical certificate that it did.

Tolerance (RESEARCH Pitfall 2 / Assumption A5): the default `rtol = 1e-4` is a FRACTIONAL
cone-slack bound — a genuinely exact solve (relative gap ~`1e-6` on the exactness-copy'd
radial feeder) passes with ~2 orders of margin, while a truly strict cone (the high-PV /
over-voltage failure mode) has an O(1) relative gap and is caught. This is the physical
cone-feasibility tolerance and is DELIBERATELY distinct from the battery-complementarity
tolerance in `solve_welfare` (do not conflate the two, and do not confuse `rtol` here with
Clarabel's internal interior-point duality gap `tol_gap_abs/rel` — a different quantity in
the solver's own scaling).

Reads `ctx.meta[:pf_vars]` (the `(; v, v̂, P, Q, l)` stash), `ctx.meta[:feeder]`, and
`ctx.meta[:T]`. Uses an explicit `error(...)` (never `@assert`, which is elided under `-O`), per
project convention (`src/core/status.jl`).
"""
function assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-8)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    maxgap = 0.0        # absolute cone residual (first-class reported output)
    maxrel = 0.0        # worst RELATIVE cone slack (the scale-free gate quantity, WR-01)
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])   # l·v_from  (thesis 3.39 RHS side)
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2      # P² + Q²
        gap = abs(lhs - rhs)
        scale = atol + max(abs(lhs), abs(rhs))               # base-free normalizer + atol floor
        maxgap = max(maxgap, gap)
        maxrel = max(maxrel, gap / scale)
    end

    maxrel < rtol || error(
        "SOCP relaxation INEXACT: max relative cone slack=$maxrel ≥ rtol=$rtol " *
        "(max abs |l·v−(P²+Q²)|=$maxgap; atol=$atol) — " *
        "prices REFUSED (thesis 3.43-3.45; PF-04)",
    )
    return maxgap
end

export assert_socp_exact!
