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
# COMMENT-ONLY STUB — no code, no exports. Filled by plan 04-05 (PF-04).
