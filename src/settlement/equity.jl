# src/settlement/equity.jl
#
# SEAM: post-solve equity & rebound analytics — PURE MATH, no solver.
#
# This file declares its own `export`s:
#   - `gini`, `theil`, `atkinson`, `palma` — inequality metrics over per-household
#     bill/surplus vectors (SETL-04), each docstring carrying that metric's
#     negative-value convention (the docstring IS the locked deliverable).
#
# (The SETL-05 breakouts `load_terciles` / `equity_breakdown` and the SETL-06
# `rebound` metric extend this file and its export line in Tasks 2-3 of plan 41-02.)
#
# Consumes NOTHING but plain numeric vectors — zero solver calls, zero JuMP, no
# imports beyond the runtime (stdlib-free pure functions; the project keeps a minimal
# pinned dep set and this module adds none). DISTINCT from the operational solves
# (models/welfare_solve.jl, admm/): this is post-solve ANALYTICS, not optimization.
# GOLDEN POLICY: purely additive — `src/pricing/` and `src/admm/` are never touched.
#
# NO-INCOME-DATA STANCE (SETL-05, stated at module level): every metric in this file
# operates on per-household BILLS/SURPLUS only. NO income data exists in this
# framework and none is used anywhere. The proxy groupings (PV owner vs non-owner,
# electrical location, load-level terciles of baseline consumption) come from the
# `case_a_household_map` row shape — house, bus, aggregator, device_set, pv_group,
# house_index — no new data, and never an income variable.
#
# NEGATIVE-VALUE CONVENTIONS (normative spec: phase 41 RESEARCH.md Pattern 5,
# literature-grounded) — one convention PER METRIC, each in its own docstring:
#   Gini     over ALL values (relative mean-difference; may exceed 1; negatives are
#            NEVER zeroed or dropped — the documented bias finding);
#   Theil    positive-support subset, excluded count RETURNED (log domain);
#   Atkinson positive-support subset, excluded count RETURNED (geometric-mean form);
#   Palma    group-total ratio over the ascending-sorted FULL vector (totals cancel).

export gini, theil, atkinson, palma

# Atkinson's inequality-aversion parameter, fixed as an auditable module constant
# (the Phase-41 A6 resolution): 0.5 is the common default in the applied literature;
# any documented choice is equally valid. The chosen value travels inside
# `atkinson`'s returned NamedTuple so downstream artifacts always carry the epsilon
# actually used. Named module constant (not a magic literal) per the fit.jl
# named-constant discipline.
const _ATKINSON_EPSILON = 0.5

# Shared fail-loud input validation for the pure-metric functions (V5 boundary
# guards): empty vectors and non-finite entries are rejected with the function name
# localized — never `@assert`, never a silently-plausible number.
function _equity_input_check(name::Symbol, x::AbstractVector{<:Real})
    isempty(x) && throw(ArgumentError("$name: input vector is empty — nothing to measure."))
    all(isfinite, x) || throw(
        ArgumentError(
            "$name: input contains $(count(!isfinite, x)) non-finite entry(ies) — " *
            "equity metrics require finite bill/surplus values.",
        ),
    )
    return nothing
end

"""
    gini(x::AbstractVector{<:Real}) -> Float64

Gini coefficient in the population mean-absolute-difference form over ALL values,

    G = sum_i sum_j abs(x_i - x_j) / (2 n^2 mu),   mu = mean(x).

NEGATIVE-VALUE CONVENTION (documented, never violated): `x` may contain negatives
(surplus of PV exporters genuinely can be negative); the formula is applied to the
FULL vector — values are NEVER zeroed, clipped or dropped before the computation.
Zeroing or dropping negatives before a Gini is a documented bias on the resulting
comparisons (Raffinetti, Siletti and Vernizzi 2014; De Battisti, Ferragina and
Vernizzi 2019). Two intended consequences:

  - `G` here is a RELATIVE MEAN-DIFFERENCE measure, NOT a Lorenz-curve concentration
    index: it MAY EXCEED 1 on negative-bearing vectors. The pinned hand-computed
    certificate `gini([-2.0, 1.0, 3.0, 6.0]) == 0.8125` includes a negative.
  - The measure is scale-invariant (units cancel) but not translation-invariant:
    bills and surplus are different distributions by construction — report which.

Guards (fail loud, never `@assert`): an empty vector or any non-finite entry throws
`ArgumentError`. Degenerate cases by convention: an all-equal vector (including the
all-zero vector) has zero relative variation and returns `0.0` EXACTLY; a NON-uniform
vector with `mu == 0` makes the relative measure undefined and throws
`ArgumentError` naming the degeneracy.
"""
function gini(x::AbstractVector{<:Real})
    _equity_input_check(:gini, x)
    allequal(x) && return 0.0
    n = length(x)
    mu = sum(x) / n
    mu == 0 && throw(
        ArgumentError(
            "gini: mean(x) == 0 on a NON-uniform vector — the relative " *
            "mean-difference form is undefined at a zero mean. Shift the vector to a " *
            "documented reference (e.g. bills) or report the raw mean difference.",
        ),
    )
    S = sum(abs(xi - xj) for xi in x, xj in x)
    return S / (2 * n^2 * mu)
end

"""
    theil(x::AbstractVector{<:Real}) -> (; theil, n_excluded, n)

Theil T index computed on the POSITIVE-SUPPORT subset of `x`,

    T = (1 / n_pos) * sum over x_i > 0 of (x_i / mu_pos) * log(x_i / mu_pos).

NEGATIVE-VALUE CONVENTION (documented): the Theil index is NON-COMPUTABLE for
non-positive values — the log domain requires x_i > 0 (GE-family measure; see the
inequality-measurement overview cited in the phase research, s11403-020-00295-1).
The literature-standard treatment is EXCLUSION WITH DISCLOSURE, and the excluded
count is a RETURNED value: `n_excluded = count(<=(0), x)`. Exclusion is therefore
never silent — callers must report it alongside the index. Every value non-positive
=> `theil` is `NaN` with `n_excluded == n`: honestly non-computable, reported —
never a fake zero and never a throw. Compare the index with `isnan` / `isequal`,
not `==` (NaN convention; the Phase-39 NaN-bearing-key precedent).

Guards: an empty vector or any non-finite entry throws `ArgumentError`.
"""
function theil(x::AbstractVector{<:Real})
    _equity_input_check(:theil, x)
    n = length(x)
    xp = filter(>(0), x)
    n_excluded = n - length(xp)
    isempty(xp) && return (; theil = NaN, n_excluded, n)
    mu = sum(xp) / length(xp)
    T = sum(xi -> (xi / mu) * log(xi / mu), xp) / length(xp)
    return (; theil = T, n_excluded, n)
end

"""
    atkinson(x::AbstractVector{<:Real}; epsilon = _ATKINSON_EPSILON)
        -> (; atkinson, n_excluded, n, epsilon)

Atkinson inequality index computed on the POSITIVE-SUPPORT subset of `x`,

    A = 1 - ( (1 / n_pos) * sum over x_i > 0 of x_i^(1-eps) )^(1/(1-eps)) / mu_pos,

with the inequality-aversion parameter fixed by the module constant
`_ATKINSON_EPSILON = 0.5` (the Phase-41 A6 resolution) and reported back in the
result so artifacts carry the epsilon actually used.

NEGATIVE-VALUE CONVENTION (documented — the CONTEXT-locked treatment): the
power-mean/geometric form is non-computable for x_i <= 0, so non-positives are
EXCLUDED WITH DISCLOSURE — the excluded count is a RETURNED value, `n_excluded`;
every value non-positive => `atkinson` is `NaN` with `n_excluded == n` (compare
with `isnan`, never `==`).

`epsilon = 1` is the LOG form of the index — a different formula this module does
not implement by design; passing it throws `ArgumentError`. Valid epsilons lie in
(0, 1) ∪ (1, ∞).

Uniform positive subset => `0.0` returned EXACTLY: the uniform distribution has
zero inequality by definition, and the short-circuit avoids an IEEE round-trip
artifact of ~1 ulp through the power mean (the pinned uniform anchor asserts the
exact zero).

Guards: an empty vector or any non-finite entry throws `ArgumentError`.
"""
function atkinson(x::AbstractVector{<:Real}; epsilon::Real = _ATKINSON_EPSILON)
    _equity_input_check(:atkinson, x)
    (epsilon > 0 && epsilon != 1) || throw(
        ArgumentError(
            "atkinson: epsilon must lie in (0, 1) ∪ (1, ∞); got epsilon = $(epsilon). " *
            "epsilon = 1 is the LOG form of the index — unimplemented here by design.",
        ),
    )
    n = length(x)
    xp = filter(>(0), x)
    n_excluded = n - length(xp)
    eps_used = Float64(epsilon)
    isempty(xp) && return (; atkinson = NaN, n_excluded, n, epsilon = eps_used)
    allequal(xp) && return (; atkinson = 0.0, n_excluded, n, epsilon = eps_used)
    mu = sum(xp) / length(xp)
    e = 1 - eps_used
    A = 1 - (sum(xi -> xi^e, xp) / length(xp))^(1 / e) / mu
    return (; atkinson = A, n_excluded, n, epsilon = eps_used)
end

"""
    palma(x::AbstractVector{<:Real}) -> Float64

Palma ratio over the ascending-sorted FULL vector,

    palma = sum(top 10 percent) / sum(bottom 40 percent).

NEGATIVE-VALUE CONVENTION (documented — the most negative-robust of the four
metrics): the ratio is formed from GROUP TOTALS on the sorted full vector, so the
overall total cancels and no income SHARES (which would need a positive
denominator) are ever taken. Count convention pinned for small n:
`n_top = max(1, floor(0.1 n))`, `n_bottom = max(1, floor(0.4 n))` — exact 10/40
percent shares whenever n is a multiple of 10 (the uniform anchor at n = 10 gives
exactly 0.25; at n = 4 both counts pin to 1).

SIGN CAVEAT: when the bottom-40-percent sum is NEGATIVE the ratio is negative and
reads as "the top decile total divided by a negative bottom share" — reported as
computed, never clipped (the pinned certificate
`palma([-2.0, 1.0, 3.0, 6.0]) == -3.0` exercises exactly this branch). A
bottom-40-percent sum of EXACTLY 0 makes the ratio undefined => `NaN` (compare
with `isnan`), never `Inf` and never a throw.

Guards: an empty vector or any non-finite entry throws `ArgumentError`.
"""
function palma(x::AbstractVector{<:Real})
    _equity_input_check(:palma, x)
    n = length(x)
    xs = sort(x)
    n_top = max(1, floor(Int, 0.1 * n))
    n_bottom = max(1, floor(Int, 0.4 * n))
    top_sum = sum(@view xs[(end - n_top + 1):end])
    bottom_sum = sum(@view xs[1:n_bottom])
    bottom_sum == 0 && return NaN
    return top_sum / bottom_sum
end
