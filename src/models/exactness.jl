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
# AFTER `assert_solved!` and BEFORE any `dual()` read, gated on `has_branch_current(ctx.pf)`
# so the DC/LinDistFlow paths are untouched (data-driven, no formulation branch). The
# returned `maxgap` (the absolute cone residual) is reported as a first-class output.
#
using JuMP

# FIX-08 (Phase 27, plan 27-02): the per-branch relative exactness floor, HYBRID revision.
#
# Replaces the OLD flat `atol=1e-6` applied IDENTICALLY to every branch regardless of its
# physical scale (a lightly-loaded branch with small `smax` could carry a slack cone LARGE
# relative to its own thermal scale yet still pass, since both `lhs`/`rhs` sit near zero and
# the `rtol` term alone cannot catch it). `atol_b = max(τ_solver, ε * ref_b)` replaces the flat
# floor, with `ref_b = br.smax^2` for a thermally-limited branch (`br.smax < SMAX_NO_LIMIT`) or
# the head-branch flow magnitude squared (`P_head^2 + Q_head^2`) for an interior/unlimited
# branch (SOURCE: 27-RESEARCH.md "FIX-08 — Per-branch exactness floor", head-branch convention
# `br.from == feeder.root` verified across ieee13.jl:80/ieee123.jl:404/ieee8500.jl:212).
#
# HISTORY — a PURE relative floor (`atol_b = ε*ref_b` alone) was tried FIRST and found
# IRRECONCILABLE: `test/test_exactness.jl`'s pre-existing WR-01 regression item (`smax=10`
# branch, injected `l=5e-6` gap, `ref_b=100`) needs `ε < 5e-8` to keep throwing, while the
# IEEE-13 ground canonical fixture needs `ε ≳ 5e-5` to keep passing — three orders of magnitude
# apart, because `ref_b = br.smax^2` (or the head branch's own flow magnitude for an interior
# branch) scales with the NETWORK's own thermal/flow scale, not with Clarabel's actual
# achievable cone-residual noise floor, which does NOT shrink with `smax`. This was escalated
# in `27-FINDINGS.md`; the user's resolution (2026-09-29) is this HYBRID formula: `ε` stays
# small (< 5e-8, so the per-branch RELATIVE term still does its job on large-`smax` branches),
# and a NEW, separately-measured ABSOLUTE floor `τ_solver` (Clarabel's own achievable cone
# residual, with a documented margin — same measure-then-pin discipline as
# `KNOWN_OPTIMUM_ATOL`, `src/planning/benders.jl:42`) protects lightly-loaded/interior branches
# from the noise floor without needing `ref_b` to carry that burden.
#
# MEASURED (2026-09-29), in 2 stages:
#
# Stage 1 — `τ_solver`: for every REQUIRED canonical/cluster-E fixture (IEEE-13 ground,
# IEEE-123, two_bus_feeder, the near-lossless smax=10 pair; direct scripts reproducing each
# fixture body, `--project=.`), computed `excess[b,t] = gap[b,t] - rtol*max(|lhs|,|rhs|)` — the
# residual that an ABSOLUTE floor alone must cover (independent of `ref_b`/`ε`; a NEGATIVE
# excess means the `rtol` term alone already passes that (b,t) regardless of any absolute
# floor). Worst positive excess found:
#   IEEE-13 ground (test_acceptance.jl/test_admm.jl:78; branch 5→6, t=16)     excess ≈ 3.08e-8
#   IEEE-123 (test_acceptance.jl; branch 48→49, t=9)                          excess ≈ 7.90e-8
#   two_bus_feeder (test_admm.jl:25/test_planning_oracle.jl:267)              excess < 0 (every b,t)
#   near-lossless smax=10 pair (test_pricing_dlmp.jl:20/226, test_pricing_welfare.jl:64)
#                                                                              excess < 0 (every b,t)
# Worst REQUIRED excess = 7.90e-8 (IEEE-123). `τ_solver = 2.0e-7` (≈2.53x margin over that
# worst excess) was chosen so it ALSO stays below half the Task-2 synthetic regression's
# injected gap (5e-7), the OTHER binding constraint (see Stage 2) — a strict 10x margin
# (`KNOWN_OPTIMUM_ATOL`'s own convention) would give `7.9e-7`, which is ITSELF larger than the
# synthetic regression's gap and would break requirement (2) below; `τ_solver=2e-7` is the
# largest value found that satisfies BOTH sides with a documented (~2.4-2.5x) margin — see
# 27-02-SUMMARY.md for the full sweep table and the reasoning for using a smaller-than-10x
# margin here.
#
# Stage 2 — verified, with `τ_solver = 2.0e-7` and `ε = 1.0e-9` (< 5e-8, so the RELATIVE term
# still governs any future large-`smax` branch), on ALL THREE required outcomes:
#   (1) test_exactness.jl's pre-existing WR-01 item (smax=10, l=5e-6 injected)   THROWS  (ratio≈24.9, 24.9x margin)
#   (2) the Task-2 synthetic slack-cone-on-small-branch item (smax=0.01, l=5e-7) THROWS  (ratio≈2.50, 2.5x margin)
#   (3) every REQUIRED canonical/cluster-E fixture                              PASSES  (worst margin ≈2.43x, IEEE-123)
# RESOLVED (27-FINDINGS.md updated from ESCALATED to RESOLVED — user chose hybrid, 2026-09-29).
const MEASURED_ε_FIX08 = 1.0e-9

# FIX-08 hybrid (Phase 27, plan 27-02): the measured ABSOLUTE floor `τ_solver` — Clarabel's own
# achievable cone-residual noise floor on a genuinely-exact solve, with a documented margin.
# See `MEASURED_ε_FIX08`'s comment immediately above for the full 2-stage measurement protocol
# and the worst-excess sweep table (worst REQUIRED excess = 7.90e-8, IEEE-123; `τ_solver` set to
# ≈2.53x that value, and independently verified to sit below half the Task-2 synthetic
# regression's injected gap so requirement (2) — that regression correctly THROWS — still
# holds). Used as `atol_b = max(τ_solver, ε * ref_b)` — the LARGER of the absolute solver-noise
# floor and the per-branch relative floor applies.
const TAU_SOLVER_FIX08 = 2.0e-7

# WR-02 (35-REVIEW, Phase 35): the head-branch convention and the per-(branch, hour) cone-row
# computation, factored out VERBATIM (same expressions, same evaluation order) from
# `assert_socp_exact!` so the `hybrid_ratios` diagnostic shares them instead of re-implementing
# them. Pure refactor: the gate's verdict, `maxgap`, `maxratio` and messages are unchanged.

# FIX-08 head branch: the FIRST branch incident to `feeder.root` in EITHER storage orientation
# (see the long rationale at the call site in `assert_socp_exact!`). `nothing` if none.
_socp_head_branch(feeder) =
    findfirst(br -> br.from == feeder.root || br.to == feeder.root, feeder.branches)

"""
    _cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver) -> NamedTuple

Internal. The ONE per-(branch `b`, hour `t`) exactness computation used by both
[`assert_socp_exact!`](@ref) and [`hybrid_ratios`](@ref): returns
`(; lhs, rhs, gap, atol_b, ratio)` with `gap = |l·v_from − (P²+Q²)|`,
`atol_b = atol === nothing ? max(τ_solver, ε·ref_b) : atol` and
`ratio = gap / (atol_b + rtol·max(|lhs|, |rhs|))` (`ratio ≤ 1` iff the row is exact).
"""
@inline function _cone_row(pv, br, b::Int, t::Int, head_b::Int, rtol, atol, ε, τ_solver)
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
    # the atol_b term is a HYBRID, PER-BRANCH floor (FIX-08, revised): the LARGER of a
    # separately-measured ABSOLUTE solver-noise floor (`τ_solver`, covers Clarabel's own
    # achievable cone-residual precision on a lightly-loaded/interior branch where `ref_b`
    # itself is small) and a per-branch RELATIVE floor (`ε * ref_b`, scales with the
    # branch's own thermal/flow scale for larger branches) — never masking a genuine
    # strict cone on a load-bearing branch while still catching a slack cone that is large
    # RELATIVE to a small branch's own scale. An explicit `atol` bypasses `τ_solver`/
    # `ref_b`/`ε` entirely (backward-compat override, see `assert_socp_exact!`'s docstring).
    atol_b = atol === nothing ? max(τ_solver, ε * ref_b) : atol
    tol = atol_b + rtol * max(abs(lhs), abs(rhs))
    return (; lhs, rhs, gap, atol_b, ratio = gap / tol)
end

"""
    assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4,
                        atol::Union{Nothing,Real} = nothing, ε::Real = MEASURED_ε_FIX08,
                        τ_solver::Real = TAU_SOLVER_FIX08)
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
bound (`maxratio > 1`) it raises a `CertificateError` and REFUSES prices (thesis 3.43–3.45;
PF-04); otherwise it returns `maxgap = maxₜ,ᵦ gap` — the absolute cone residual — as a
FIRST-CLASS output reported alongside the prices.

Why the `rtol` term (WR-01): the cone residual `l·v − (P²+Q²)` is in per-unit², so its
magnitude scales with the per-unit base. A PURELY ABSOLUTE tolerance therefore accepts a larger
FRACTIONAL cone slack on a big base (e.g. the 100 MVA IEEE-13 fixture, where a load-bearing
`l·v ≈ 5e-3` pu²) than on a small one — the SAME physical inexactness could pass on one base and
be refused on another. The `rtol·max(|lhs|,|rhs|)` term makes the verdict a fixed FRACTION of
the cone magnitude, hence invariant to the base.

Why `atol_b` is now PER-BRANCH and HYBRID (FIX-08, Phase 27, revised per the escalated finding
in `27-FINDINGS.md`): on a near-zero-flow branch both sides are ~0 and a pure ratio would blow
up on meaningless rounding noise (a genuinely exact solve can show a per-branch residual ~1e-8
where the cone magnitude is also ~1e-7, i.e. a spurious ~10% "relative" slack), so an absolute
floor is still needed — but a SINGLE flat floor is scale-blind (a lightly-loaded branch with
small `smax` could carry a slack cone LARGE relative to its own thermal capacity yet still
silently pass), while a PURE per-branch RELATIVE floor alone was found IRRECONCILABLE (a
`smax=10` WR-01 regression fixture needs `ε<5e-8` to keep throwing, while the IEEE-13 ground
canonical fixture needs `ε≳5e-5` to keep passing — see `MEASURED_ε_FIX08`'s comment for the
full history). `atol_b = max(τ_solver, ε * ref_b)` fixes this: `ref_b = br.smax^2` for a
thermally-limited branch (`br.smax < SMAX_NO_LIMIT`), or the head branch's flow magnitude
squared (`value(P[head_b,t])^2 + value(Q[head_b,t])^2`, `head_b` = the branch with `br.from ==
feeder.root`) for an interior/unlimited branch, since it carries no `smax` of its own to
normalize against; `τ_solver` (default [`TAU_SOLVER_FIX08`](@ref)) is a separately-measured
ABSOLUTE floor covering Clarabel's own achievable cone-residual noise floor, independent of
`ref_b`. `ε` (default [`MEASURED_ε_FIX08`](@ref)) is MEASURED, not guessed, per the sweep
protocol documented on that constant; the LARGER of the two terms applies per branch/hour.

**Backward-compatible `atol` override (byte-identical to pre-FIX-08 behavior):** passing an
explicit `atol::Real` BYPASSES the hybrid `max(τ_solver, ε*ref_b)` computation entirely —
`atol_b = atol` is used as a FLAT floor for every branch, exactly as the pre-FIX-08 gate did.
This preserves the 2 call sites that already pass a Phase-26-tuned explicit `atol`
(`src/admm/DsoOpt.jl`, `test/fixtures_phase19.jl`) completely unaffected by this change.

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

Reads `ctx.pf_vars` (the `(; v, v̂, P, Q, l)` stash), `ctx.feeder`, and
`ctx.T`. Uses an explicit `CertificateError` (never `@assert`, which is elided under `-O`), per
project convention (`src/core/status.jl`). Throws `ArgumentError` if `feeder` has NO branch
incident to `feeder.root` in either storage orientation (`br.from == feeder.root` OR `br.to ==
feeder.root`, FIX-08/plan 27-07) — a malformed/non-radial feeder fails loudly here, never
silently using branch 1 as a fallback head branch. A feeder whose root fans out to MULTIPLE
branches (a legitimate meshed topology, e.g. `test_mesh_angle_certificate.jl`'s 4-bus diamond)
deterministically takes the FIRST match (by branch index) — this mirrors the pre-27-07 code's
own tolerance for that case (it never required uniqueness either) and is orientation-invariant
in effect since `ref_b` only reads `P²+Q²` (squared).
"""
function assert_socp_exact!(
    ctx::ModelContext;
    rtol::Real = 1e-4,
    atol::Union{Nothing, Real} = nothing,
    ε::Real = MEASURED_ε_FIX08,
    τ_solver::Real = TAU_SOLVER_FIX08,
)
    pv = _require_pf_vars(ctx)
    feeder = _require_feeder(ctx)
    T = _require_T(ctx)

    # FIX-08 (Phase 27, plan 27-07 revision): the head branch — the FIRST branch incident to
    # feeder.root in EITHER storage orientation (`br.from == feeder.root` OR `br.to ==
    # feeder.root`) — is the network-scale reference for INTERIOR (SMAX_NO_LIMIT-sentinel)
    # branches, computed ONCE before the loop. Orientation-agnostic per the CR-01/WR-03
    # storage-orientation discipline (`test_mesh_angle_certificate.jl`'s reversed-orientation
    # regression, ac_oracle.jl's "Branch orientation" note): a branch's stored `(from, to)`
    # direction is a book-keeping choice, not a physical constraint (assert_connected places
    # no requirement on which end is "from"), so a feeder root-inward-reversed relative to the
    # OLD `br.from`-only convention (every branch stored child->parent) must resolve to the
    # SAME (index-wise) head branch. `ref_b` below reads `P[head_b,t]^2 + Q[head_b,t]^2`, which
    # is orientation-INVARIANT (squared), so no sign correction is needed once the right branch
    # index is found.
    #
    # DEVIATION from a literal "throw on >1 match" reading of the plan's must_haves prose:
    # kept `findfirst` (not `findall`+uniqueness), i.e. tolerate MULTIPLE root-incident
    # branches by deterministically taking the FIRST one found (mirrors the OLD `br.from`-only
    # code's own tolerance — it never checked for uniqueness either). A meshed feeder's root CAN
    # legitimately fan out to more than one branch (e.g. `test_mesh_angle_certificate.jl`'s own
    # 4-bus diamond: `mesh_feeder`'s root=1 has TWO branches with `br.from==1`, and this is the
    # CURRENTLY-PASSING, unmodified forward-orientation fixture — not malformed). Requiring
    # strict uniqueness would newly THROW on that pre-existing, already-green fixture (a
    # regression), not just on a genuinely malformed feeder. Only a ZERO-match feeder (no branch
    # touches the root at all) is malformed/non-radial and fails loudly.
    #
    # WR-02 (27-REVIEW.md, 2026-09-29, code-review-fixer pass): the concern raised is that on a
    # meshed feeder with MULTIPLE root-incident branches carrying materially different flow
    # magnitudes, `findfirst`'s branch-STORAGE-ORDER-dependent choice could under/over-state the
    # `ref_b` scale for OTHER interior branches. MEASURED 2026-09-29: this gate's numeric check
    # only runs on a `ctx` whose formulation carries the branch-current variable (the
    # `has_branch_current(ctx.pf)` guard at this function's call site). The ONE currently-known
    # multi-root-branch feeder, `Phase23Fixtures.mesh_feeder`'s 4-bus diamond (asymmetric loads
    # at buses 2/3, so its two root branches (1,2)/(1,3) DO carry different flow magnitudes by
    # construction), is exercised via `MeshedFlow()` in `test_mesh_angle_certificate.jl`
    # /`test_mesh_flow.jl`. MeshedFlow delegates to the shared SOCP body, which stashes `:l`, so
    # `solve_welfare(MeshedFlow)` DOES run this gate (`assert_socp_exact!` passes in test_mesh_flow).
    # Its `head_b`/`ref_b` logic therefore DOES run on that fixture, and the gate passes there
    # in the current suite, so WR-02's scale-choice concern is not a currently observed defect
    # (no verdict flips), but it is unproven for other disparate-flow meshed fixtures.
    # Left as `findfirst` rather than `sum`/`max`-over-root-branches (the
    # review's own alternative fix) because that numeric change would touch `ref_b` — and hence
    # the exactness PASS/FAIL verdict — for EVERY interior branch on EVERY feeder in the suite
    # (this gate is called from 30+ src/test/docs sites), and verifying no regression requires a
    # full-suite run genuinely out of scope for this fix pass (per this pass's own instructions).
    # Revisit with a full-suite-verified `sum`/`max` change if/when a `ConvexBranchFlow` meshed
    # fixture with disparate root-branch flows is added.
    head_b = _socp_head_branch(feeder)
    head_b === nothing && throw(
        ArgumentError(
            "assert_socp_exact!: no branch incident to feeder.root=$(feeder.root) found " *
            "(checked br.from == root OR br.to == root) — malformed/non-radial feeder " *
            "(FIX-08 head-branch convention requires at least one)",
        ),
    )

    maxgap = 0.0        # absolute cone residual (first-class reported output)
    maxratio = 0.0      # worst gap / (atol_b + rtol·magnitude) — ≤ 1 iff every branch is exact
    for (b, br) in enumerate(feeder.branches), t in 1:T
        # WR-02 (35-REVIEW): the per-(b,t) gap/floor/ratio arithmetic lives in `_cone_row`,
        # shared VERBATIM with the `hybrid_ratios` diagnostic so the two can never drift.
        row = _cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)
        maxgap = max(maxgap, row.gap)
        maxratio = max(maxratio, row.ratio)
    end

    maxratio <= 1 || throw(CertificateError(
        "SOCP relaxation INEXACT: worst gap/(atol_b+rtol·|cone|)=$maxratio > 1 " *
        "(rtol=$rtol, atol=$(atol === nothing ? "max(τ_solver=$τ_solver, ε*ref_b, ε=$ε)" : atol); " *
        "max abs |l·v−(P²+Q²)|=$maxgap) — " *
        "prices REFUSED (thesis 3.43-3.45; PF-04)";
        kind = :socp_exact,
    ))
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
`ctx.pf_vars`/`ctx.feeder`/`ctx.T` stash as `assert_socp_exact!`.
"""
function socp_relaxation_gap(ctx::ModelContext)
    pv = _require_pf_vars(ctx)
    feeder = _require_feeder(ctx)
    T = _require_T(ctx)

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
the number of `(branch,time)` pairs actually scanned. Reads the same `ctx.pf_vars` /
`ctx.feeder` / `ctx.T` stash as `assert_socp_exact!`.
"""
function socp_gap_report(
    ctx::ModelContext;
    topn::Int = 20,
    rtol::Real = 1e-4,
    atol::Real = 1e-6,
)
    pv = _require_pf_vars(ctx)
    feeder = _require_feeder(ctx)
    T = _require_T(ctx)

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

"""
    hybrid_ratios(ctx::ModelContext; rtol = 1e-4, atol = nothing, ε = MEASURED_ε_FIX08,
                  τ_solver = TAU_SOLVER_FIX08) -> Vector{NamedTuple}

Phase 35 (ARCH-10) additive DIAGNOSTIC mirror of [`assert_socp_exact!`](@ref): per
`(branch, hour)` row it reports `gap = |l·v_from − (P²+Q²)|`, the floor `atol_b` (default: the
hybrid `max(τ_solver, ε·ref_b)`; a `Real` `atol` makes it flat, exactly as in the gate),
`ratio = gap / (atol_b + rtol·|cone|)`, `r_pu`, and `loss_impact = r_pu·gap`. The kwargs and their
defaults are IDENTICAL to `assert_socp_exact!`'s, and both functions compute every row through the
same internal helper (WR-02, 35-REVIEW), so for the SAME kwargs `ratio ≤ 1` on every row iff the
gate accepts — pass the kwargs the gate was run with to explain its verdict. Rows are sorted
worst-first (descending `ratio`, ties by `(b, t)`). It is NEVER used to decide pass/fail
(T-25-12: anti-certificate-laundering) -- it only explains which branches dominate a refusal.
Reads the same `ctx.pf_vars`/`ctx.feeder`/`ctx.T` stash as `assert_socp_exact!`.
"""
function hybrid_ratios(
    ctx::ModelContext;
    rtol::Real = 1e-4,
    atol::Union{Nothing, Real} = nothing,
    ε::Real = MEASURED_ε_FIX08,
    τ_solver::Real = TAU_SOLVER_FIX08,
)
    pv = _require_pf_vars(ctx)
    feeder = _require_feeder(ctx)
    T = _require_T(ctx)
    head_b = _socp_head_branch(feeder)
    head_b === nothing && throw(
        ArgumentError("hybrid_ratios: no branch incident to feeder.root=$(feeder.root)"),
    )
    rows = NamedTuple[]
    for (b, br) in enumerate(feeder.branches), t in 1:T
        row = _cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)
        push!(
            rows,
            (;
                b = b,
                t = t,
                from = br.from,
                to = br.to,
                r_pu = br.r,
                gap = row.gap,
                atol_b = row.atol_b,
                ratio = row.ratio,
                loss_impact = br.r * row.gap,
            ),
        )
    end
    sort!(rows; by = row -> (-row.ratio, row.b, row.t))
    return rows
end

export assert_socp_exact!, socp_relaxation_gap
