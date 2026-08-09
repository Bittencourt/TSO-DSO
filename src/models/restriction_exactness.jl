# src/models/restriction_exactness.jl
#
# SEAM: restricted-SOCP physical-AC-feasibility + optimality-loss certificate (OVR-02).
# OWNER: plan 20-03; SEMANTICS REVISED by an orchestrator targeted-revision pass (see
#        20-03-SUMMARY.md's "## Addendum (orchestrator revision)" section) after the FIRST
#        implementation's certification predicate was found internally incoherent with D-05.
#
# A NEW, named certificate — a peer to `assert_socp_exact!` (models/exactness.jl, the
# SOCP-cone gate: is `l·v = P²+Q²` at THIS ONE solve), `assert_ac_exact!`
# (models/ac_oracle.jl, the AC-cross-check comparator this file's certificate INTERNALLY
# REUSES as a DIAGNOSTIC, never as the certification predicate itself — see REVISION NOTE
# below), and `assert_4q_complementarity!` (models/complementarity_4q.jl, the throw/report
# neutralization contract this certificate copies verbatim).
#
# REVISION NOTE (what changed and why, D-05 coherence): the FIRST implementation defined
# `ac_feasible` as "the restricted dispatch MATCHES the independently-solved AC-OPTIMAL
# dispatch" (i.e. it literally called `assert_ac_exact!` and required every hour `exact`).
# Under THAT definition, `ac_feasible = true` forces `optimality_loss ≈ 0` by construction —
# a restricted-but-suboptimal AC-feasible point can never pass, which makes D-05's "ONE
# certificate that certifies AC-feasibility AND reports optimality loss" internally
# incoherent: the loss clause only has meaning when a feasible-but-suboptimal point can
# still certify. `assert_restriction_exact!` NOW certifies PHYSICAL AC-feasibility of the
# RESTRICTED solution itself — the SAME per-branch, per-hour cone-equality residual
# `|l·v − (P²+Q²)|` that `assert_socp_exact!` gates (a restricted point whose cone is tight
# IS a genuine branch-flow / AC operating point, Gan-Low Theorem 2), computed HERE with
# THIS certificate's OWN freshly-measured `cone_rtol`/`cone_atol` — NEVER
# `assert_socp_exact!`'s literal `1e-4`/`1e-6` defaults (D-07 / certificate-laundering
# guard, T-20-07). The AC-oracle dispatch-MATCH comparison is KEPT as a separate,
# clearly-named diagnostic field, `matches_ac_optimum` (plus its full per-hour `hours`
# report) — the honest finding from the first implementation (OPF-m provably EXCLUDES the
# true AC optimum on EXACT-04's high-PV binding window, so the restricted dispatch does
# NOT match it, `optimality_loss ≈ −1.43`) remains fully surfaced, just correctly demoted
# from "the certification gate" to "a diagnostic this certificate ALSO reports."
#
# MECHANISM NOTE (inherited from plan 20-02, read before trusting the numbers below):
# `RestrictedBranchFlow` implements Gan-Low's OPF-m (a direct `v̂_GL(s) ≤ v̄` shadow-voltage
# constraint), NOT the simpler OPF-ε bound-shrink RESEARCH.md originally sketched. OPF-m
# genuinely CLOSES `assert_socp_exact!`'s own cone-tightness gap on EXACT-04 (`socp_maxgap
# = 2.08e-8`, plan 20-02) — this certificate's OWN, independently-computed cone residual on
# `ctx_restricted` (see below) reproduces that SAME `2.08e-8` absolute floor, confirming the
# restricted point is a real, physically-realizable branch-flow point. That is a DIFFERENT
# question from "does that real point match the INDEPENDENTLY-SOLVED, GLOBALLY AC-OPTIMAL
# dispatch" — a strictly harder bar, because OPF-m's added constraint is a genuine
# feasible-set RESTRICTION (Lemma 1: v ≤ v̂_GL(s) always, so the new `v̂_GL(s) ≤ v̄`
# constraint removes some AC-feasible points from consideration). When that removed region
# contains the true AC optimum, the restricted optimum is STRICTLY WORSE than (and
# dispatches differently from) the true AC optimum — not a bug, the expected, provable
# consequence of D-01's "genuine restriction, never a relaxation tightening" contract. See
# the docstring below for the measured verdict this produces on EXACT-04 (a genuine,
# documented finding — plan 20-03-SUMMARY.md and its orchestrator-revision addendum).
#
using JuMP

"""
    assert_restriction_exact!(ctx_restricted::ModelContext, ctx_ac::ModelContext;
                               cone_rtol::Real = 5e-4, cone_atol::Real = 2e-7,
                               rtol::Real = 1e-3, atol::Real = 2e-5,
                               unrestricted_cost::Union{Real,Nothing} = nothing,
                               report::Bool = false)
        -> (; ac_feasible::Bool, matches_ac_optimum::Bool,
             optimality_loss::Union{Float64,Nothing}, obj_gap::Float64,
             hours::Vector{NamedTuple})

Certify a solved [`RestrictedBranchFlow`](@ref) context (`ctx_restricted`) PHYSICALLY
AC-FEASIBLE — i.e. a genuine, implementable branch-flow operating point, NOT necessarily
the globally AC-optimal one — and, in the SAME call, report (a) whether it happens to
MATCH the independently-solved [`ACPowerFlow`](@ref) optimum (`ctx_ac`, SAME problem data,
own re-optimization — the LOCKED "same operating point" contract `assert_ac_exact!`
requires) and (b) the optimality loss versus the unrestricted (inexact) SOCP bound (D-05).

# What "AC-feasible" means here (the certification gate)

`ac_feasible` is decided by THIS solve's OWN per-branch, per-hour SOC-cone residual — the
IDENTICAL quantity `assert_socp_exact!` (models/exactness.jl) gates, `gap[b,t] =
|value(l[b,t])·value(v[from_b,t]) − (value(P[b,t])² + value(Q[b,t])²)|` — compared against
a SCALE-FREE combined bound `gap ≤ cone_atol + cone_rtol·max(|l·v|, |P²+Q²|)` (WR-01's
philosophy, reproduced here rather than re-imported so this certificate owns its own
tolerance decision independently of `assert_socp_exact!`'s internal call inside
`solve_welfare`). `ac_feasible = true` iff EVERY branch-hour satisfies that bound. A tight
cone at a solved branch-flow point is, by the branch-flow model's own physics, a genuine AC
operating point (Gan-Low Theorem 2) — this is the correctness bar D-05 requires the
certificate to enforce, independent of whether that point happens to be globally optimal.

`cone_rtol`/`cone_atol` are MEASURED on THIS quantity, on `ctx_restricted` itself, on the
EXACT-04 fixture — NEVER copied from `assert_socp_exact!`'s `1e-4`/`1e-6` defaults (D-07 /
certificate-laundering guard, T-20-07; see `# Tolerance provenance` below).

# What "matches_ac_optimum" means (a diagnostic, NOT the certification gate)

`matches_ac_optimum` answers the STRICTLY HARDER, SEPARATE question the first
implementation of this certificate mistakenly used AS the certification gate: does the
restricted dispatch equal the independently-solved, globally AC-optimal dispatch at every
hour? Computed by calling `report_ac = assert_ac_exact!(ctx_restricted, ctx_ac; rtol = rtol,
atol = atol)` — REUSING the existing per-hour comparison loop verbatim (never
re-implemented), with `rtol`/`atol` measured on THIS restricted-vs-AC residual (kept from
this certificate's original measurement — see `# Tolerance provenance` below; unrelated to
`cone_rtol`/`cone_atol` above, a DIFFERENT quantity). `matches_ac_optimum =
all(row.exact for row in report_ac.hours)`. The full per-hour `report_ac.hours` (and
`report_ac.obj_gap`) are ALWAYS returned so a caller can inspect exactly which hours
diverge and by how much — this is D-05's "report the optimality loss" half of the contract,
generalized to the full per-hour diagnostic, never suppressed.

`optimality_loss = unrestricted_cost === nothing ? nothing : objective_value(ctx_restricted.model)
- unrestricted_cost` — a NAMED field, never silently folded into `obj_gap` (D-05: `nothing`
is an explicit, documented "not requested" contract, never silently treated as `0.0`,
T-20-09).

Stashes the D-08 provenance marker UNCONDITIONALLY, on both the pass and fail path (so
a stale marker from a prior call on a reused `ctx` never survives a later failure,
T-20-08), keyed on the PHYSICAL-feasibility verdict (never on `matches_ac_optimum`):

    ctx_restricted.meta[:price_provenance] = (;
        formulation = get(ctx_restricted.meta, :formulation, :unknown),
        certificate = :assert_restriction_exact!,
        status = ac_feasible ? :certified_convex_dual : :cert_failed)

The `formulation` field is READ from the `ctx.meta[:formulation]` marker the solved
formulation's own `contribute!` stashed (`RestrictedBranchFlow.contribute!` writes
`:RestrictedBranchFlow` there for exactly this purpose) — NEVER hardcoded by this
certificate (review WR-01): the certificate accepts ANY solved branch-flow context (its own
tests exercise it on a plain `ConvexBranchFlow` context), and fabricating
`:RestrictedBranchFlow` provenance for a non-restricted solve would be false provenance. A
context whose formulation never stashed the marker reports `formulation = :unknown` —
honest, programmatically distinguishable, never a fabricated name.

If `!ac_feasible`: builds a loud message naming `cone_rtol`/`cone_atol`, the worst per-branch
cone-residual ratio, and the phase citation ("Gan-Low OPF-m/OPF-ε, Theorem 2; OVR-02"); if
`report`, `@warn`s it and CONTINUES (this is D-09's trigger point — the CALLER is
responsible for invoking any fallback only after seeing `ac_feasible == false` from a
`report = true` call, never automatically inside this function); else `error(msg)` (throws
by default, D-06). Returns `(; ac_feasible, matches_ac_optimum, optimality_loss,
obj_gap = report_ac.obj_gap, hours = report_ac.hours)` in EITHER path — `report` mode always
returns the full diagnostic, mirroring `assert_4q_complementarity!`'s "return a diagnostic on
success" contract (here: "on non-throwing return", success or reported failure alike).

Structural guard (unchanged, inherited from `assert_ac_exact!`): a differing horizon `T`
between `ctx_restricted` and `ctx_ac` raises UNCONDITIONALLY (never neutralized by
`report = true` — that kwarg neutralizes AC-INFEASIBILITY findings, never STRUCTURAL
mismatches). This function calls `assert_ac_exact!` to compute the `matches_ac_optimum`
diagnostic regardless of the physical-feasibility verdict, so that guard fires before this
function's own `report`/`error` branching in either case.

# Tolerance provenance (D-07, T-20-07 — measurement, not a copy)

**`cone_rtol`/`cone_atol` (the NEW certification-gate tolerance, measured on
`ctx_restricted`'s OWN cone residual):** measured on the EXACT-04 fixture
(`Phase4Fixtures.high_pv_feeder()`, `pv_scale = 1.2`, solved `RestrictedBranchFlow()`,
`allow_export = true`), computing `gap[b,t] = |value(l[b,t])·value(v[from_b,t]) −
(value(P[b,t])² + value(Q[b,t])²)|` directly over every branch-hour (2026-08-08): the
observed absolute floor is `2.08e-8` (worst branch `b=2`, hour `t=19`) — reproducing plan
20-02's `socp_maxgap` EXACTLY, confirming this certificate's independent computation agrees
with `assert_socp_exact!`'s internal one — and the observed relative floor (gap /
max(|l·v|,|P²+Q²|)) is `5.08e-5` at that SAME worst branch-hour. Defaults are set roughly
ONE ORDER OF MAGNITUDE above that measured floor (mirroring `assert_4q_complementarity!`'s
sizing discipline): `cone_atol = 2e-7` (≈10× the measured `2.08e-8` absolute floor) and
`cone_rtol = 5e-4` (≈10× the measured `5.08e-5` relative floor) — DELIBERATELY DIFFERENT
from `assert_socp_exact!`'s own `rtol = 1e-4, atol = 1e-6` cone-tightness defaults (never
copied, per the certificate-laundering guard) even though both gate the SAME physical
quantity — this certificate's defaults are independently derived on THIS restricted
formulation's own solve, not inherited. At these defaults, the worst-branch-hour ratio on
EXACT-04 is `≈0.051` (well inside the `≤1` pass bound, ~20× margin) — `ac_feasible = true`.

**`rtol`/`atol` (the `matches_ac_optimum` DIAGNOSTIC tolerance, unchanged from this
certificate's original measurement — a genuinely DIFFERENT quantity, the restricted-vs-AC
dispatch gap, not the cone residual):** measured on the SAME EXACT-04 fixture,
`RestrictedBranchFlow()` vs `ACPowerFlow()` (both `allow_export = true`, AC also
`allow_local = true`), calling `assert_ac_exact!(ctx_restricted, ctx_ac; rtol = 1e-4,
atol = 1e-6)` diagnostically to READ the observed per-hour `vgap`/`pgap` scale
(2026-08-08):

  - **"Clean" hours (1–5, 16–24, where the OPF-m `v̂_GL(s) ≤ v̄` constraint is numerically
    SLACK — confirmed via `dual(ctx.constraints[:opfm_shadow_voltage][...])` ≈ 1e-7 or
    smaller):** `vgap` ≤ `1.44e-6` absolute / `1.36e-6` relative; `pgap` ≤ `9.18e-6`
    absolute / `8.05e-5` relative (hour 19's tiny `pmag ≈ 0.008` amplifies the ratio; the
    absolute floor is the more informative number there). This is the genuine Clarabel/
    Ipopt solver-noise floor.

  - **Restriction-BINDING hours (9, 10, 11, 12, 14, 15 — confirmed via a LARGE nonzero dual
    on the `:opfm_shadow_voltage` constraint, up to `-24.18` at bus 3, hour 9):** `vgap` up
    to `5.44e-3`, `pgap` up to `3.09e-2` — six orders of magnitude above the clean-hour
    floor, and driven by a genuine ACTIVE constraint, not noise.

  - **Coupling-artifact hours (7, 8, 13 — dual ≈ 1e-7, i.e. NOT locally binding, yet
    elevated `vgap`/`pgap` up to `~2.3e-4`/`~3.5e-3`):** inter-temporal spillover from the
    adjacent binding hours.

Defaults `rtol = 1e-3` (≈12× the measured `8.05e-5` clean-hour relative floor) and
`atol = 2e-5` (≈14× the measured `1.44e-6` clean-hour absolute floor) — DELIBERATELY
DIFFERENT from `assert_ac_exact!`'s own `rtol = 1e-4, atol = 1e-6` defaults (never copied).
At these defaults, hours 7–15 fail the `matches_ac_optimum` diagnostic on EXACT-04 (see
verdict below) — this is now a REPORTED finding, never a certification failure.

# Verdict on EXACT-04 (documented finding, plan 20-03-SUMMARY.md + its orchestrator-revision
addendum)

At these measured defaults, `assert_restriction_exact!(ctx_restricted, ctx_ac;
unrestricted_cost = cost_unrestricted)` on the FULL EXACT-04 fixture (`pv_scale = 1.2`)
returns **`ac_feasible = true`** (the restricted solution's OWN cone is tight — a genuine
branch-flow point, reproducing plan 20-02's `socp_maxgap = 2.08e-8`), **`matches_ac_optimum =
false`** (hours 7–15 diverge from the independently-solved AC optimum), and a substantial,
NEGATIVE `optimality_loss` (measured ≈ `-1.4326`, i.e. `cost_restricted − cost_unrestricted`:
the restricted welfare sits genuinely below the unrestricted SOCP bound — SIGN CONVENTION:
negative means the restriction cost the researcher welfare relative to the looser,
inexact bound; it is never positive because `RestrictedBranchFlow`'s feasible set is a
genuine SUBSET of the unrestricted relaxation's, per D-01). This is the EXPECTED, PROVABLE
consequence of OPF-m being a genuine restriction (D-01) whose added constraint actively
binds during EXACT-04's high-PV over-voltage window — confirmed causally via the nonzero
`:opfm_shadow_voltage` constraint duals (up to `-24.18` at bus 3, hour 9), not merely
correlated with it. It is NOT a certificate bug: the restricted point IS a real,
physically-realizable branch-flow point (now this certificate's OWN headline verdict, not
just a cross-reference to plan 20-02); it simply is not the SAME point as the globally
AC-optimal dispatch once the restriction genuinely excludes that optimum. `optimality_loss`
exists precisely to QUANTIFY that divergence, and `matches_ac_optimum = false` exists to
FLAG that the certified-feasible point is not the global optimum — two distinct, both now
correctly-scoped findings D-05 requires in the SAME call.

Reads `ctx_restricted.meta[:pf_vars]`/`[:feeder]`/`[:T]` and `ctx_ac.meta[:pf_vars]`/`[:T]`
(via the internal `assert_ac_exact!` call). Uses an explicit `error(...)`/`@warn(...)`
(never `@assert`, elided under `-O`), per project convention (`src/core/status.jl`).
"""
function assert_restriction_exact!(
    ctx_restricted::ModelContext,
    ctx_ac::ModelContext;
    cone_rtol::Real = 5e-4,
    cone_atol::Real = 2e-7,
    rtol::Real = 1e-3,
    atol::Real = 2e-5,
    unrestricted_cost::Union{Real, Nothing} = nothing,
    report::Bool = false,
)
    # --- Certification gate: PHYSICAL AC-feasibility of ctx_restricted itself, via the SAME
    # per-branch, per-hour cone-equality residual assert_socp_exact! gates — but with THIS
    # certificate's OWN, independently-measured cone_rtol/cone_atol (never
    # assert_socp_exact!'s 1e-4/1e-6 defaults, D-07/T-20-07 guard). Reimplemented inline
    # (rather than delegating to assert_socp_exact!) so this certificate owns its own
    # throw/report decision instead of inheriting assert_socp_exact!'s unconditional throw.
    pv = ctx_restricted.meta[:pf_vars]
    feeder = ctx_restricted.meta[:feeder]
    T = ctx_restricted.meta[:T]

    cone_maxgap = 0.0     # absolute cone residual (worst branch-hour)
    cone_maxratio = 0.0   # worst gap / (cone_atol + cone_rtol·magnitude) — ≤ 1 iff exact
    worst_cone = nothing
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
        gap = abs(lhs - rhs)
        tol = cone_atol + cone_rtol * max(abs(lhs), abs(rhs))
        ratio = gap / tol
        cone_maxgap = max(cone_maxgap, gap)
        if ratio > cone_maxratio
            cone_maxratio = ratio
            worst_cone = (; b, t, gap, tol, ratio)
        end
    end
    ac_feasible = cone_maxratio <= 1

    # --- Diagnostic: does the restricted dispatch MATCH the independently-solved AC
    # optimum? A STRICTLY HARDER, SEPARATE question from ac_feasible above — REUSES
    # assert_ac_exact!'s per-hour comparison loop verbatim (never re-implemented), with this
    # certificate's OWN, freshly-measured rtol/atol (never assert_ac_exact!'s defaults).
    # Called UNCONDITIONALLY (regardless of ac_feasible) so the structural T-mismatch guard
    # inside assert_ac_exact! fires before this function's own report/error branching below,
    # and so the full per-hour diagnostic is always available.
    report_ac = assert_ac_exact!(ctx_restricted, ctx_ac; rtol = rtol, atol = atol)
    matches_ac_optimum = all(row.exact for row in report_ac.hours)

    optimality_loss =
        unrestricted_cost === nothing ? nothing :
        objective_value(ctx_restricted.model) - Float64(unrestricted_cost)

    # D-08 provenance, stashed UNCONDITIONALLY on both the pass and fail path (T-20-08: a
    # stale :certified_convex_dual marker must never survive a later failed certification on
    # a reused ctx), keyed on the PHYSICAL-feasibility verdict (ac_feasible), never on the
    # matches_ac_optimum diagnostic. The formulation is READ from the D-08 marker the solved
    # formulation's own contribute! stashed (RestrictedBranchFlow.jl writes
    # :RestrictedBranchFlow there for exactly this purpose) — never hardcoded here, so a
    # plain ConvexBranchFlow (or any other) context is never handed fabricated
    # :RestrictedBranchFlow provenance (review WR-01).
    ctx_restricted.meta[:price_provenance] = (;
        formulation = get(ctx_restricted.meta, :formulation, :unknown),
        certificate = :assert_restriction_exact!,
        status = ac_feasible ? :certified_convex_dual : :cert_failed,
    )

    if !ac_feasible
        msg =
            "RestrictedBranchFlow solution NOT certified PHYSICALLY AC-feasible: worst cone " *
            "residual at branch b=$(worst_cone.b), t=$(worst_cone.t): |l·v-(P²+Q²)|=$(worst_cone.gap) " *
            "vs tol=$(worst_cone.tol) (ratio=$(worst_cone.ratio), cone_rtol=$cone_rtol, " *
            "cone_atol=$cone_atol) — the l·v = P²+Q² cone is not tight at this solve, so it is " *
            "NOT a genuine branch-flow / AC operating point (Gan-Low OPF-m/OPF-ε, Theorem 2; " *
            "OVR-02). See restriction_exactness.jl's docstring for the EXACT-04 reference verdict."
        if report
            @warn msg
        else
            error(msg)
        end
    end

    return (;
        ac_feasible,
        matches_ac_optimum,
        optimality_loss,
        obj_gap = report_ac.obj_gap,
        hours = report_ac.hours,
    )
end

export assert_restriction_exact!
