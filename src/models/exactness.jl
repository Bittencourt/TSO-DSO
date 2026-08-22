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
    assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
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

    gap ≤ atol + rtol · max(|lhs|, |rhs|)

tracking `maxratio = maxₜ,ᵦ gap / (atol + rtol·max(|lhs|, |rhs|))`. If any branch violates the
bound (`maxratio > 1`) it raises a loud `error(...)` and REFUSES prices (thesis 3.43–3.45;
PF-04); otherwise it returns `maxgap = maxₜ,ᵦ gap` — the absolute cone residual — as a
FIRST-CLASS output reported alongside the prices.

Why the `rtol` term (WR-01): the cone residual `l·v − (P²+Q²)` is in per-unit², so its
magnitude scales with the per-unit base. A PURELY ABSOLUTE tolerance therefore accepts a larger
FRACTIONAL cone slack on a big base (e.g. the 100 MVA IEEE-13 fixture, where a load-bearing
`l·v ≈ 5e-3` pu²) than on a small one — the SAME physical inexactness could pass on one base and
be refused on another. The `rtol·max(|lhs|,|rhs|)` term makes the verdict a fixed FRACTION of
the cone magnitude, hence invariant to the base.

Why the `atol` term: on a near-zero-flow branch both sides are ~0 and a pure ratio would blow
up on meaningless rounding noise (a genuinely exact solve can show a per-branch residual ~1e-8
where the cone magnitude is also ~1e-7, i.e. a spurious ~10% "relative" slack). The absolute
`atol` floor (default 1e-6, an order below the legacy absolute τ = 1e-5) lets such numerically-
zero branches count as exact while never masking a genuine strict cone on a load-bearing branch.

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
function assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]

    maxgap = 0.0        # absolute cone residual (first-class reported output)
    maxratio = 0.0      # worst gap / (atol + rtol·magnitude) — ≤ 1 iff every branch is exact
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])   # l·v_from  (thesis 3.39 RHS side)
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2      # P² + Q²
        gap = abs(lhs - rhs)
        # isapprox-style COMBINED bound (WR-01): a branch is exact iff
        # gap ≤ atol + rtol·max(|lhs|,|rhs|). The rtol term is the SCALE-FREE part (a fixed
        # FRACTION of the cone magnitude, so the verdict is invariant to the per-unit base);
        # the atol term is an ABSOLUTE floor so a numerically-zero (near-no-flow) branch — where
        # both sides are ~0 and a pure ratio would blow up on meaningless rounding noise — is
        # judged exact. atol (default 1e-6) sits an order below the legacy absolute τ = 1e-5,
        # so it never masks a genuine strict cone on a load-bearing branch.
        tol = atol + rtol * max(abs(lhs), abs(rhs))
        maxgap = max(maxgap, gap)
        maxratio = max(maxratio, gap / tol)
    end

    maxratio <= 1 || error(
        "SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=$maxratio > 1 " *
        "(rtol=$rtol, atol=$atol; max abs |l·v−(P²+Q²)|=$maxgap) — " *
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
function socp_gap_report(ctx::ModelContext; topn::Int = 20, rtol::Real = 1e-4, atol::Real = 1e-6)
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
                b = b, from = br.from, to = br.to,
                r_pu = br.r, x_pu = br.x,
                l = l, v_from = v_from, P = P, Q = Q, t = t,
                gap = gap, ratio = gap / tol,
                reverse_flow = P < 0.0,
                loading = loading,
            ),
        )
    end
    sort!(rows; by = row -> (-row.gap, row.b, row.t))
    return rows[1:min(topn, length(rows))]
end

export assert_socp_exact!, socp_relaxation_gap, socp_gap_report
