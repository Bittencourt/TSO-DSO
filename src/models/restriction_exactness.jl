# src/models/restriction_exactness.jl
#
# SEAM: restricted-SOCP AC-feasibility + optimality-loss certificate (OVR-02).
# OWNER: plan 20-03.
#
# A NEW, named certificate — a peer to `assert_socp_exact!` (models/exactness.jl, the
# SOCP-cone gate: is `l·v = P²+Q²` at THIS ONE solve), `assert_ac_exact!`
# (models/ac_oracle.jl, the AC-cross-check comparator this file's certificate INTERNALLY
# REUSES rather than re-implementing), and `assert_4q_complementarity!`
# (models/complementarity_4q.jl, the throw/report neutralization contract this certificate
# copies verbatim). `assert_restriction_exact!` certifies a solved `RestrictedBranchFlow`
# context AC-feasible against the independently-solved AC oracle AND reports the
# optimality loss versus the unrestricted (inexact) SOCP bound, IN ONE CALL (D-05).
#
# Its `rtol`/`atol` are MEASURED on THIS comparison — `RestrictedBranchFlow` vs
# `ACPowerFlow` on the EXACT-04 fixture — NEVER copied from `assert_ac_exact!`'s or
# `assert_socp_exact!`'s defaults (D-07 / certificate-laundering guard, T-20-07).
#
# MECHANISM NOTE (inherited from plan 20-02, read before trusting the numbers below):
# `RestrictedBranchFlow` implements Gan-Low's OPF-m (a direct `v̂_GL(s) ≤ v̄` shadow-voltage
# constraint), NOT the simpler OPF-ε bound-shrink RESEARCH.md originally sketched. OPF-m
# genuinely CLOSES `assert_socp_exact!`'s own cone-tightness gap on EXACT-04 (`socp_maxgap
# = 2.08e-8`, plan 20-02) — but that is a DIFFERENT question from the one THIS certificate
# answers. `assert_socp_exact!` asks "is the relaxed point a physically real branch-flow
# point" (yes, on EXACT-04, per plan 20-02). THIS certificate asks "does that real point
# match the INDEPENDENTLY-SOLVED, GLOBALLY AC-OPTIMAL dispatch" — a strictly harder bar,
# because OPF-m's added constraint is a genuine feasible-set RESTRICTION (Lemma 1: v ≤
# v̂_GL(s) always, so the new `v̂_GL(s) ≤ v̄` constraint removes some AC-feasible points from
# consideration). When that removed region contains the true AC optimum, the restricted
# optimum is STRICTLY WORSE than (and dispatches differently from) the true AC optimum —
# not a bug, the expected, provable consequence of D-01's "genuine restriction, never a
# relaxation tightening" contract. See the docstring below for the measured verdict this
# produces on EXACT-04 (a genuine, documented finding — plan 20-03-SUMMARY.md).
#
using JuMP

"""
    assert_restriction_exact!(ctx_restricted::ModelContext, ctx_ac::ModelContext;
                               rtol::Real = 1e-3, atol::Real = 2e-5,
                               unrestricted_cost::Union{Real,Nothing} = nothing,
                               report::Bool = false)
        -> (; ac_feasible::Bool, optimality_loss::Union{Float64,Nothing}, obj_gap::Float64,
             hours::Vector{NamedTuple})

Certify a solved [`RestrictedBranchFlow`](@ref) context (`ctx_restricted`) against an
independently-solved [`ACPowerFlow`](@ref) context (`ctx_ac`, SAME problem data, own
re-optimization — the LOCKED "same operating point" contract `assert_ac_exact!` requires)
and, in the SAME call, report the optimality loss versus the unrestricted (inexact) SOCP
bound (D-05).

Implementation: calls `report_ac = assert_ac_exact!(ctx_restricted, ctx_ac; rtol = rtol,
atol = atol)` — REUSING the existing per-hour comparison loop verbatim (never
re-implemented) but supplying THIS function's OWN, freshly-measured `rtol`/`atol` (see
`# Tolerance provenance` below), never `assert_ac_exact!`'s defaults. `ac_feasible =
all(row.exact for row in report_ac.hours)` — true iff the restricted dispatch matches the
independently-solved AC-optimal dispatch at every hour within tolerance.
`optimality_loss = unrestricted_cost === nothing ? nothing : objective_value(ctx_restricted.model)
- unrestricted_cost` — a NAMED field, never silently folded into `obj_gap` (D-05: `nothing`
is an explicit, documented "not requested" contract, never silently treated as `0.0`,
T-20-09).

Stashes the D-08 provenance marker UNCONDITIONALLY, on both the pass and the fail path (so
a stale marker from a prior call on a reused `ctx` never survives a later failure,
T-20-08):

    ctx_restricted.meta[:price_provenance] = (; formulation = :RestrictedBranchFlow,
        certificate = :assert_restriction_exact!,
        status = ac_feasible ? :certified_convex_dual : :cert_failed)

If `!ac_feasible`: builds a loud message naming `rtol`/`atol`, the worst per-hour gap (from
`report_ac.hours`), and the phase citation ("Gan-Low OPF-m/OPF-ε, Theorem 2; OVR-02"); if
`report`, `@warn`s it and CONTINUES (this is D-09's trigger point — the CALLER is
responsible for invoking any fallback only after seeing `ac_feasible == false` from a
`report = true` call, never automatically inside this function); else `error(msg)` (throws
by default, D-06). Returns `(; ac_feasible, optimality_loss, obj_gap = report_ac.obj_gap,
hours = report_ac.hours)` in EITHER path — `report` mode always returns the full
diagnostic, mirroring `assert_4q_complementarity!`'s "return a diagnostic on success"
contract (here: "on non-throwing return", success or reported failure alike).

# Tolerance provenance (D-07, T-20-07 — measurement, not a copy)

Measured on the EXACT-04 fixture (`Phase4Fixtures.high_pv_feeder()`, `pv_scale = 1.2`,
`RestrictedBranchFlow()` vs `ACPowerFlow()`, both `allow_export = true`, AC also
`allow_local = true`), calling this file's OWN `assert_ac_exact!(ctx_restricted, ctx_ac;
rtol = 1e-4, atol = 1e-6)` diagnostically to READ the observed per-hour `vgap`/`pgap` scale
(2026-08-08):

  - **"Clean" hours (1–5, 16–24, where the OPF-m `v̂_GL(s) ≤ v̄` constraint is numerically
    SLACK — confirmed via `dual(ctx.constraints[:opfm_shadow_voltage][...])` ≈ 1e-7 or
    smaller):** `vgap` ≤ `1.44e-6` absolute / `1.36e-6` relative; `pgap` ≤ `9.18e-6`
    absolute / `8.05e-5` relative (hour 19's tiny `pmag ≈ 0.008` amplifies the ratio; the
    absolute floor is the more informative number there). This is the genuine Clarabel/
    Ipopt solver-noise floor — the scale RESEARCH.md's "~1e-6–~1e-7" prediction correctly
    describes, just for a DIFFERENT quantity (dispatch-match, not SOCP cone-tightness).

  - **Restriction-BINDING hours (9, 10, 11, 12, 14, 15 — confirmed via a LARGE nonzero dual
    on the `:opfm_shadow_voltage` constraint, up to `-24.18` at bus 3, hour 9):** `vgap` up
    to `5.44e-3`, `pgap` up to `3.09e-2` — six orders of magnitude above the clean-hour
    floor, and driven by a genuine ACTIVE constraint, not noise.

  - **Coupling-artifact hours (7, 8, 13 — dual ≈ 1e-7, i.e. NOT locally binding, yet
    elevated `vgap`/`pgap` up to `~2.3e-4`/`~3.5e-3`):** inter-temporal spillover from the
    adjacent binding hours (the battery/deferrable dispatch shifts in response), the SAME
    phenomenon `test_ac_oracle.jl`'s EXACT-04 item documents for the ORIGINAL SOCP-vs-AC
    finding.

Defaults are set ROUGHLY AN ORDER OF MAGNITUDE above the CLEAN-HOUR floor only (never
loosened toward the binding-hour scale — doing so would be certificate-laundering, T-20-07,
swallowing a genuine restriction effect as "noise"): `rtol = 1e-3` (≈12× the measured
`8.05e-5` clean-hour relative floor) and `atol = 2e-5` (≈14× the measured `1.44e-6`
clean-hour absolute floor) — DELIBERATELY DIFFERENT from `assert_ac_exact!`'s own
`rtol = 1e-4, atol = 1e-6` defaults (never copied) and from `assert_socp_exact!`'s
cone-tightness tolerance (a different quantity entirely).

# Verdict on EXACT-04 (documented finding, plan 20-03-SUMMARY.md)

At these measured defaults, `assert_restriction_exact!(ctx_restricted, ctx_ac)` on the FULL
EXACT-04 fixture (`pv_scale = 1.2`) returns **`ac_feasible = false`** (hours 7–15 fail) with
a substantial, NEGATIVE `optimality_loss` (measured ≈ `-1.4326`, i.e. the restricted
welfare sits genuinely below the unrestricted SOCP bound). This is the EXPECTED, PROVABLE
consequence of OPF-m being a genuine restriction (D-01) whose added constraint actively
binds during EXACT-04's high-PV over-voltage window — confirmed causally via the nonzero
`:opfm_shadow_voltage` constraint duals above, not merely correlated with it. It is NOT a
certificate bug and NOT evidence the tolerance is mis-measured (see the clean-hour vs.
binding-hour separation above): `assert_socp_exact!` (PF-04) still certifies the restricted
solution's OWN cone as exact (`socp_maxgap = 2.08e-8`, plan 20-02) — the restricted point
IS a real, physically-realizable branch-flow point; it is simply not the SAME point as the
globally AC-optimal dispatch once the restriction genuinely excludes that optimum. This is
precisely the finding `optimality_loss` exists to QUANTIFY rather than hide.

Reads `ctx_restricted.meta[:pf_vars]`/`[:feeder]`/`[:T]` and `ctx_ac.meta[:pf_vars]`/`[:T]`
(via the internal `assert_ac_exact!` call). Uses an explicit `error(...)`/`@warn(...)`
(never `@assert`, elided under `-O`), per project convention (`src/core/status.jl`).
"""
function assert_restriction_exact!(
    ctx_restricted::ModelContext,
    ctx_ac::ModelContext;
    rtol::Real = 1e-3,
    atol::Real = 2e-5,
    unrestricted_cost::Union{Real, Nothing} = nothing,
    report::Bool = false,
)
    # REUSE assert_ac_exact!'s per-hour loop verbatim — this function's OWN, freshly
    # measured rtol/atol, never assert_ac_exact!'s defaults (D-07/T-20-07 guard).
    report_ac = assert_ac_exact!(ctx_restricted, ctx_ac; rtol = rtol, atol = atol)

    ac_feasible = all(row.exact for row in report_ac.hours)

    optimality_loss =
        unrestricted_cost === nothing ? nothing :
        objective_value(ctx_restricted.model) - Float64(unrestricted_cost)

    # D-08 provenance, stashed UNCONDITIONALLY on both the pass and fail path (T-20-08: a
    # stale :certified_convex_dual marker must never survive a later failed certification on
    # a reused ctx).
    ctx_restricted.meta[:price_provenance] = (;
        formulation = :RestrictedBranchFlow,
        certificate = :assert_restriction_exact!,
        status = ac_feasible ? :certified_convex_dual : :cert_failed,
    )

    if !ac_feasible
        worst = report_ac.hours[argmax(row.vgap + row.pgap for row in report_ac.hours)]
        msg =
            "RestrictedBranchFlow solution NOT certified AC-feasible: worst hour t=$(worst.t) " *
            "vgap=$(worst.vgap), pgap=$(worst.pgap), qgap=$(worst.qgap) " *
            "(rtol=$rtol, atol=$atol) — Gan-Low OPF-m/OPF-ε, Theorem 2; OVR-02. If this " *
            "fixture has an actively-binding :opfm_shadow_voltage constraint at the worst " *
            "hour, this MAY be the honest restriction-induced optimality-loss boundary this " *
            "certificate's `optimality_loss` field quantifies, rather than a bug — see " *
            "restriction_exactness.jl's docstring EXACT-04 verdict"
        if report
            @warn msg
        else
            error(msg)
        end
    end

    return (; ac_feasible, optimality_loss, obj_gap = report_ac.obj_gap, hours = report_ac.hours)
end

export assert_restriction_exact!
