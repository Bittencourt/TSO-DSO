# src/models/ac_dual_fallback.jl
#
# SEAM: nonconvex-AC-dual fallback pricer (OVR-03).
# OWNER: plan 20-04.
#
# This function requires ZERO new solve machinery: it is a second, seeded call to the
# ALREADY-EXISTING `solve_welfare(..., ACPowerFlow(), ...; allow_local = true)` path — the
# SAME oracle `test_ac_oracle.jl`'s own 2-start local-optimum guard (lines 213-243) and plan
# 20-03's certificate already use. It is NEVER invoked automatically by
# `assert_restriction_exact!` (D-09 — the CALLER decides, after observing a `report = true`
# certificate failure, exactly like every other certificate-driven decision in this
# codebase).
#
# TRIGGER DISCIPLINE (D-09, sharpened by plan 20-03's orchestrator-revision addendum): call
# this function ONLY after observing
# `assert_restriction_exact!(ctx_restricted, ctx_ac; report = true).ac_feasible == false`
# (equivalently `ctx_restricted.meta[:price_provenance].status == :cert_failed`). On the
# EXACT-04 fixture at `pv_scale = 1.2`, `RestrictedBranchFlow`'s OWN cone certifies exact
# (`ac_feasible = true`, plan 20-03) — so this fallback is NOT EXACT-04's answer there; it
# remains the documented safety net for a fixture/regime where the restricted SOCP's own
# cone genuinely fails to close (see 20-04-SUMMARY.md for the fixture this plan uses to
# exercise a genuine `ac_feasible = false` trigger).
#
using JuMP

# D-11: "seeded starts" implemented as distinct, DETERMINISTIC NLP-backend
# convergence-strategy variants — the SAME kind of solver-trajectory diversity
# `test_ac_oracle.jl`'s existing 2-variant guard already uses, extended from 2 to 5 —
# rather than randomized initial points, because `solve_welfare` has no hook to inject a
# custom starting point without new solve machinery (which D-01's "Don't Hand-Roll" table
# forbids). The variant list itself lives in `nlp_multistart_variants()`
# (src/solver/factory.jl), and each variant is applied via `select_optimizer(NLP();
# variant...)`: the attribute vocabulary is inherently backend-specific, and the factory is
# the ONLY core file that names concrete solvers or their option vocabulary (INFRA-02,
# review WR-04) — this file names none.

"""
    ac_dual_fallback_price(feeder, aggregators::AbstractVector; T::Int, λ₀,
                            allow_export::Bool = true, n_seeds::Int = 2)
        -> (; dadp, cost_ac, price_status::Symbol, agreement_report)

The documented nonconvex-AC-dual fallback pricer (OVR-03). Re-solves the SAME problem data
via the already-existing `ACPowerFlow` oracle (`solve_welfare(feeder, ACPowerFlow(),
aggregators; allow_local = true, ...)`, ZERO new solve machinery) from `n_seeds` distinct,
deterministic NLP-backend convergence-strategy variants ([`nlp_multistart_variants`](@ref),
each applied through the solver factory as `select_optimizer(NLP(); variant...)` — this
file names no concrete solver, INFRA-02/review WR-04), and reports multi-start agreement
evidence (D-11) alongside the price.

**D-10's caveat, stated explicitly:** the returned `dadp` is a LOCAL optimum of a nonconvex
problem, NOT a market-clearing convex dual — publish it only alongside this caveat and the
`agreement_report`, never as a bare price. `price_status = :local_ac_dual` is the MANDATORY,
always-present structural marker (T-20-10) that a downstream consumer must check before
treating `dadp` as an ordinary DADP.

# Trigger discipline (D-09)

This function is NEVER called automatically by `assert_restriction_exact!` or any other
certificate in this codebase — there is no import or call relationship in either direction
(confirmed by `grep -n 'assert_restriction_exact!\\|solve_restricted'` returning no matches
in this file). A caller must invoke this function ONLY after observing a `report = true`
certificate failure (`ac_feasible == false` / `price_provenance.status == :cert_failed`);
this file has no opinion on, and does not read, that certificate's verdict.

# Multi-start agreement evidence (D-11)

For `i in 1:n_seeds`, solves `ctxs[i], costs[i], dadps[i] = solve_welfare(feeder,
ACPowerFlow(), aggregators; T, λ₀, allow_local = true, allow_export, optimizer =
<variant i>)`. Computes `max_cost_spread = maximum(costs) - minimum(costs)` and
`max_dadp_spread = maximum(maximum(abs.(dadps[i] .- dadps[1])) for i in 1:n_seeds)`, and
returns them (plus the raw `costs`/`dadps` vectors and `n_seeds`) in `agreement_report`.
Returns `dadp = dadps[1]`, `cost_ac = costs[1]` — the FIRST seed's result, evidenced (never
silently overridden) by the agreement report's spreads.

`n_seeds` is bounded `2:length(nlp_multistart_variants())` by an explicit `ArgumentError`
guard (T-20-12 — no silent clamping, so a caller's typo about how much multi-start evidence
was actually gathered is never masked).
"""
function ac_dual_fallback_price(
    feeder,
    aggregators::AbstractVector;
    T::Int,
    λ₀,
    allow_export::Bool = true,
    n_seeds::Int = 2,
)
    variants = nlp_multistart_variants()
    2 <= n_seeds <= length(variants) ||
        throw(ArgumentError("n_seeds must be in 2:$(length(variants))"))

    costs = Vector{Float64}(undef, n_seeds)
    dadps = Vector{Vector{Float64}}(undef, n_seeds)

    for i in 1:n_seeds
        # INFRA-02 / review WR-04: the concrete NLP solver (and its option vocabulary) is
        # named ONLY by the factory — this call layers the variant's attributes on the
        # factory's own NLP base.
        opt = select_optimizer(NLP(); variants[i]...)
        _, cost_i, dadp_i = solve_welfare(
            feeder,
            ACPowerFlow(),
            aggregators;
            T = T,
            λ₀ = λ₀,
            allow_local = true,
            allow_export = allow_export,
            optimizer = opt,
        )
        costs[i] = cost_i
        dadps[i] = dadp_i
    end

    max_cost_spread = maximum(costs) - minimum(costs)
    max_dadp_spread = maximum(maximum(abs.(dadps[i] .- dadps[1])) for i in 1:n_seeds)

    agreement_report = (; costs, dadps, max_cost_spread, max_dadp_spread, n_seeds)

    return (;
        dadp = dadps[1],
        cost_ac = costs[1],
        price_status = :local_ac_dual,
        agreement_report,
    )
end

export ac_dual_fallback_price
