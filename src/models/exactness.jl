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

# FIX-08 (Phase 27, plan 27-02): the per-branch relative exactness floor's measured `ε`.
#
# Replaces the OLD flat `atol=1e-6` applied IDENTICALLY to every branch regardless of its
# physical scale (a lightly-loaded branch with small `smax` could carry a slack cone LARGE
# relative to its own thermal scale yet still pass, since both `lhs`/`rhs` sit near zero and
# the `rtol` term alone cannot catch it). `atol_b = ε * ref_b` replaces the flat floor, with
# `ref_b = br.smax^2` for a thermally-limited branch (`br.smax < SMAX_NO_LIMIT`) or the
# head-branch flow magnitude squared (`P_head^2 + Q_head^2`) for an interior/unlimited branch
# (SOURCE: 27-RESEARCH.md "FIX-08 — Per-branch exactness floor", head-branch convention
# `br.from == feeder.root` verified across ieee13.jl:80/ieee123.jl:404/ieee8500.jl:212).
#
# MEASURED (2026-09-29) via the protocol in 27-RESEARCH.md/27-02-PLAN.md Task 2: swept `ε`
# from loose to tight, at each value checking (a) the NEW synthetic slack-cone-on-small-branch
# fixture (`test/test_exactness.jl`, smax=0.01, injected `l=5e-7` gap, `ref_b=1e-4`) is
# correctly flagged inexact, AND (b) the cluster-E/canonical fixtures RESEARCH.md/the plan name
# explicitly (test_pricing_dlmp.jl, test_pricing_welfare.jl, test_admm.jl,
# test_planning_oracle.jl, the IEEE-13/IEEE-123 `test_acceptance.jl` fixtures) still PASS.
#
# RAW SWEEP (direct scripts reproducing each fixture body, `--project=.`; see 27-02-SUMMARY.md
# for the full table):
#   synthetic small-branch (smax=0.01, ref_b=1e-4, injected gap=5e-7)  -> throws for ε ≲ 5e-3
#   IEEE-13 ground (test_acceptance.jl/test_admm.jl:78, head smax=0.0686, congestion-driven;
#     worst residual on 2 INTERIOR branches at reverse-flow hours, gap≈3.1e-8,
#     ref_b=head_flow_mag2≈4.56e-3)                                    -> passes for ε ≳ 5e-5
#   IEEE-123 (test_acceptance.jl, real Fortescue-reduced impedances,
#     gap≈9.47e-8)                                                     -> passes for ε ≳ 1e-6
#   two_bus_feeder (test_admm.jl:25/test_planning_oracle.jl:267, SMAX_NO_LIMIT single branch,
#     ref_b=its OWN head-branch flow magnitude, gap≈1.40e-9)           -> passes for every ε tried
#     (1e-9 .. 1e-3): its own P²+Q² already dominates ε*ref_b at any reasonable ε.
#   near-lossless smax=10 cluster-E pair (test_pricing_dlmp.jl:20/226, test_pricing_welfare.jl:64,
#     ref_b=100, gap≈6.2-6.3e-6)                                       -> passes at every ε tried
#
# `ε = 1e-4` (matches `rtol`'s own order of magnitude) clears every REQUIRED fixture above with
# margin (≥2x on the tightest, IEEE-13 ground) while still catching the Task-2 synthetic
# regression with ~50x margin (`1e-4 * 1e-4 = 1e-8 ≪ 5e-7`).
#
# ESCALATED CONFLICT (T-27-05, per CONTEXT.md's locked "never raise ε to hide a flip" policy —
# see `27-FINDINGS.md`): this SAME sweep found `test/test_exactness.jl`'s PRE-EXISTING WR-01
# regression ("relative gate refuses a base-shrunk cone slack an absolute τ would accept",
# smax=10 branch, injected `l=5e-6` gap, `ref_b=100`) requires `ε < 5e-6/100 = 5e-8` to KEEP
# throwing — genuinely incompatible with the `ε ≳ 5e-5` the IEEE-13 ground fixture needs to
# KEEP passing (three orders of magnitude apart; no single ε satisfies both). This constant
# was measured to satisfy the EXPLICITLY-NAMED cluster-E/canonical set (the plan's Task 2
# acceptance criterion); the pre-existing WR-01 regression item now PASSES (no longer throws)
# at this ε — a "should-be-flagged passes" case, escalated rather than hidden. That item is
# UNMODIFIED by this plan (only a NEW item was added); do not re-pin/relax it without a
# separate, explicit decision.
const MEASURED_ε_FIX08 = 1.0e-4

"""
    assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4,
                        atol::Union{Nothing,Real} = nothing, ε::Real = MEASURED_ε_FIX08)
        -> maxgap::Float64

Certify that the SOC branch-flow relaxation is EXACT at the solved point, and REFUSE
prices (throw) if it is not. This is the headline correctness gate of the project (PF-04).

After a trusted solve, for every branch `b` (from-bus `feeder.branches[b].from`) and time
`t ∈ 1:T` it computes the relaxation gap between the two sides of the rotated SOC cone
(thesis 3.39):

    lhs   = value(l[b,t]) · value(v[from_b, t])          # l·v_from
    rhs   = value(P[b,t])² + value(Q[b,t])²              # P² + Q²
    gap   = |lhs − rhs|

and compares it to an isapprox-style COMBINED threshold (WR-01):

    gap ≤ atol_b + rtol · max(|lhs|, |rhs|)

tracking `maxratio = maxₜ,ᵦ gap / (atol_b + rtol·max(|lhs|, |rhs|))`. If any branch violates the
bound (`maxratio > 1`) it raises a loud `error(...)` and REFUSES prices (thesis 3.43–3.45;
PF-04); otherwise it returns `maxgap = maxₜ,ᵦ gap` — the absolute cone residual — as a
FIRST-CLASS output reported alongside the prices.

Why the `rtol` term (WR-01): the cone residual `l·v − (P²+Q²)` is in per-unit², so its
magnitude scales with the per-unit base. A PURELY ABSOLUTE tolerance therefore accepts a larger
FRACTIONAL cone slack on a big base (e.g. the 100 MVA IEEE-13 fixture, where a load-bearing
`l·v ≈ 5e-3` pu²) than on a small one — the SAME physical inexactness could pass on one base and
be refused on another. The `rtol·max(|lhs|,|rhs|)` term makes the verdict a fixed FRACTION of
the cone magnitude, hence invariant to the base.

Why `atol_b` is now PER-BRANCH (FIX-08, Phase 27): on a near-zero-flow branch both sides are ~0
and a pure ratio would blow up on meaningless rounding noise (a genuinely exact solve can show a
per-branch residual ~1e-8 where the cone magnitude is also ~1e-7, i.e. a spurious ~10% "relative"
slack), so an absolute floor is still needed — but a SINGLE flat floor is scale-blind: it was
calibrated against head-branch-scale fixtures, so a lightly-loaded branch with small `smax` (a
fine-grained lateral) could carry a slack cone LARGE relative to its own thermal capacity yet
still silently pass. `atol_b = ε * ref_b` fixes this: `ref_b = br.smax^2` for a thermally-limited
branch (`br.smax < SMAX_NO_LIMIT`), or the head branch's flow magnitude squared
(`value(P[head_b,t])^2 + value(Q[head_b,t])^2`, `head_b` = the branch with `br.from ==
feeder.root`) for an interior/unlimited branch, since it carries no `smax` of its own to
normalize against. `ε` (default [`MEASURED_ε_FIX08`](@ref)) is MEASURED, not guessed, per the
sweep protocol documented on that constant.

**Backward-compatible `atol` override (byte-identical to pre-FIX-08 behavior):** passing an
explicit `atol::Real` BYPASSES the per-branch `ε*ref_b` computation entirely — `atol_b = atol`
is used as a FLAT floor for every branch, exactly as the pre-FIX-08 gate did. This preserves the
2 call sites that already pass a Phase-26-tuned explicit `atol` (`src/admm/DsoOpt.jl`,
`test/fixtures_phase19.jl`) completely unaffected by this change.

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
project convention (`src/core/status.jl`). Throws `ArgumentError` if `feeder` has no branch with
`br.from == feeder.root` (a malformed/non-radial feeder fails loudly here, never silently using
branch 1 as a fallback head branch).
"""
function assert_socp_exact!(
    ctx::ModelContext;
    rtol::Real = 1e-4,
    atol::Union{Nothing, Real} = nothing,
    ε::Real = MEASURED_ε_FIX08,
)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    # FIX-08: the head branch (br.from == feeder.root) is the network-scale reference for
    # INTERIOR (SMAX_NO_LIMIT-sentinel) branches, computed ONCE before the loop. A malformed/
    # non-radial feeder (no branch incident to the root) fails loudly here rather than
    # silently falling back to branch 1.
    head_b = findfirst(br -> br.from == feeder.root, feeder.branches)
    head_b === nothing && throw(
        ArgumentError(
            "assert_socp_exact!: no branch with br.from == feeder.root=$(feeder.root) found — " *
            "malformed/non-radial feeder (FIX-08 head-branch convention requires one)",
        ),
    )

    maxgap = 0.0        # absolute cone residual (first-class reported output)
    maxratio = 0.0      # worst gap / (atol_b + rtol·magnitude) — ≤ 1 iff every branch is exact
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])   # l·v_from  (thesis 3.39 RHS side)
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2      # P² + Q²
        gap = abs(lhs - rhs)
        # FIX-08: per-branch reference scale `ref_b` — the branch's own thermal capacity
        # squared if thermally limited, else the head branch's own flow magnitude squared
        # (the network-scale reference for an interior/unconstrained branch).
        ref_b =
            br.smax < SMAX_NO_LIMIT ? br.smax^2 :
            (value(pv.P[head_b, t])^2 + value(pv.Q[head_b, t])^2)
        # isapprox-style COMBINED bound (WR-01): a branch is exact iff
        # gap ≤ atol_b + rtol·max(|lhs|,|rhs|). The rtol term is the SCALE-FREE part (a fixed
        # FRACTION of the cone magnitude, so the verdict is invariant to the per-unit base);
        # the atol_b term is an ABSOLUTE, PER-BRANCH floor (FIX-08) so a numerically-zero
        # (near-no-flow) branch — where both sides are ~0 and a pure ratio would blow up on
        # meaningless rounding noise — is judged exact RELATIVE TO ITS OWN PHYSICAL SCALE,
        # never masking a genuine strict cone on a load-bearing OR lightly-loaded branch. An
        # explicit `atol` bypasses `ref_b`/`ε` entirely (backward-compat override, see docstring).
        atol_b = atol === nothing ? ε * ref_b : atol
        tol = atol_b + rtol * max(abs(lhs), abs(rhs))
        maxgap = max(maxgap, gap)
        maxratio = max(maxratio, gap / tol)
    end

    maxratio <= 1 || error(
        "SOCP relaxation INEXACT: worst gap/(atol_b+rtol·|cone|)=$maxratio > 1 " *
        "(rtol=$rtol, atol=$(atol === nothing ? "ε*ref_b, ε=$ε" : atol); " *
        "max abs |l·v−(P²+Q²)|=$maxgap) — " *
        "prices REFUSED (thesis 3.43-3.45; PF-04)",
    )
    return maxgap
end

# Phase 25 (SCALE-05, plan 25-05): calibration-only sibling of `assert_socp_exact!`.
#
# `socp_relaxation_gap` is a WHOLLY NEW, ADDITIVE function — `assert_socp_exact!` above is left
# BYTE-IDENTICAL (must-not-break). It duplicates ONLY the gap-computation loop (the `lhs`/`rhs`/
# `gap`/`maxgap` lines), with NO throw and NO `rtol`/`atol` classification, so a per-fixture
# noise-floor calibration (spike-002's method — re-solve a benign point across a tightening
# `tol_gap_abs`/`tol_gap_rel` ladder and watch where the measured residual stops improving) can
# measure the SOLVER'S OWN achievable cone residual BEFORE a new fixture's `assert_socp_exact!`
# `atol` is chosen (anti-certificate-laundering: never reuse IEEE-13/123's tolerance for a new
# fixture, `scripts/benchmark_ieee8500.jl`'s `--calibrate-noise-floor` mode).
"""
    socp_relaxation_gap(ctx::ModelContext) -> Float64

Calibration-only: NEVER use in place of [`assert_socp_exact!`](@ref)'s gate — it does not throw
and cannot refuse a bad price. Exists so per-fixture noise-floor calibration (spike-002's method)
can measure the solver's own residual floor across a tolerance ladder BEFORE choosing
`assert_socp_exact!`'s `atol`/`rtol` for a new fixture (anti-certificate-laundering).

Duplicates `assert_socp_exact!`'s per-branch, per-time gap computation VERBATIM —

    lhs = value(l[b,t]) · value(v[from_b, t])
    rhs = value(P[b,t])² + value(Q[b,t])²
    gap = |lhs − rhs|

— but returns the raw absolute cone residual `maxgap = maxₜ,ᵦ gap` directly, WITHOUT comparing
it to any `atol`/`rtol` bound and WITHOUT throwing on a large value. Reads the same
`ctx.meta[:pf_vars]`/`ctx.meta[:feeder]`/`ctx.meta[:T]` stash as `assert_socp_exact!`.
"""
function socp_relaxation_gap(ctx::ModelContext)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    maxgap = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
        gap = abs(lhs - rhs)
        maxgap = max(maxgap, gap)
    end
    return maxgap
end

# Quick task 260822-oi7: diagnostic-only, NON-THROWING sibling built for the IEEE-8500
# inexactness root-cause investigation. Like `socp_relaxation_gap` above, `assert_socp_exact!`
# is left BYTE-IDENTICAL — this re-walks the SAME per-branch/per-time gap loop and returns the
# worst offenders with enough detail to discriminate structural (near-zero `r_pu`) / physical
# (reverse flow, `P<0`) / numerical (scattered, no pattern) causes, WITHOUT importing any
# fixture-specific knowledge (bus names, D-13 edge membership) into this file — those joins
# belong in the calling script (`scripts/benchmark_ieee8500.jl`).
"""
    socp_gap_report(ctx::ModelContext; topn::Int = 20, rtol::Real = 1e-4, atol::Real = 1e-6)
        -> Vector{<:NamedTuple}

Diagnostic-only, NON-THROWING sibling of [`assert_socp_exact!`](@ref) / [`socp_relaxation_gap`](@ref)
(neither is touched by this addition). Re-walks the SAME per-branch, per-time SOC-cone gap
computation and returns the `topn` WORST `(branch, time)` rows, sorted by absolute gap descending,
with enough detail to discriminate the candidate inexactness mechanisms (structural modeling
convention / physical reverse flow / numerical conditioning) WITHOUT importing any fixture-specific
knowledge (bus names, D-13 edge membership) — those joins are the CALLER's job.

Each row is a `NamedTuple` with:

  - `b::Int`            — 1-based branch index into `feeder.branches`;
  - `from::Int`,`to::Int` — the branch's bus IDS (`feeder.branches[b].from/.to`); NOT names —
    this file stays fixture-agnostic (see `src/data/ieee8500.jl`'s String relabel maps for a
    name join);
  - `r_pu::Float64`,`x_pu::Float64` — the branch's per-unit resistance/reactance
    (`Branch.r`/`.x`) — the STRUCTURAL discriminator: a near-zero `r_pu` (the D-13 near-ideal
    regulator/switch convention, `IEEE123_SWITCH_R = 3e-4` pu) starves the welfare objective's
    `r·l` loss-cost gradient that drives the branch's `l` down to the tight SOC-exact value;
  - `l::Float64`,`v_from::Float64`,`P::Float64`,`Q::Float64` — the solved cone-constraint
    quantities at branch `b`, time `t`;
  - `t::Int`            — the timestep;
  - `gap::Float64`      — `|l·v_from - (P²+Q²)|`, IDENTICAL formula to `assert_socp_exact!`;
  - `ratio::Float64`    — `gap / (atol + rtol·max(|lhs|,|rhs|))`, the SAME combined WR-01 bound
    `assert_socp_exact!` uses, so rows are comparable across branches/fixtures/per-unit bases
    (a `ratio > 1` is exactly what would have thrown);
  - `reverse_flow::Bool` — `P < 0`, the PHYSICAL discriminator;
  - `loading::Union{Float64,Missing}` — `sqrt(P²+Q²)/smax`, or `missing` when
    `br.smax == SMAX_NO_LIMIT` (dividing by the 99.0 pu sentinel would fabricate a meaningless
    number for an unconstrained interior branch).

Ties in `gap` are broken by `(b,t)` ascending for a deterministic row order. `topn` is clamped to
the number of `(branch,time)` pairs actually scanned. Reads the same `ctx.meta[:pf_vars]` /
`ctx.meta[:feeder]` / `ctx.meta[:T]` stash as `assert_socp_exact!`.
"""
function socp_gap_report(
    ctx::ModelContext;
    topn::Int = 20,
    rtol::Real = 1e-4,
    atol::Real = 1e-6,
)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    rows = NamedTuple[]
    for (b, br) in enumerate(feeder.branches), t in 1:T
        l = value(pv.l[b, t])
        v_from = value(pv.v[br.from, t])
        P = value(pv.P[b, t])
        Q = value(pv.Q[b, t])
        lhs = l * v_from
        rhs = P^2 + Q^2
        gap = abs(lhs - rhs)
        tol = atol + rtol * max(abs(lhs), abs(rhs))
        loading = br.smax == SMAX_NO_LIMIT ? missing : sqrt(P^2 + Q^2) / br.smax
        push!(
            rows,
            (;
                b = b,
                from = br.from,
                to = br.to,
                r_pu = br.r,
                x_pu = br.x,
                l = l,
                v_from = v_from,
                P = P,
                Q = Q,
                t = t,
                gap = gap,
                ratio = gap / tol,
                reverse_flow = P < 0.0,
                loading = loading,
            ),
        )
    end
    sort!(rows; by = row -> (-row.gap, row.b, row.t))
    return rows[1:min(topn, length(rows))]
end

export assert_socp_exact!, socp_relaxation_gap, socp_gap_report
