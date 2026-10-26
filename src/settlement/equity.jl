# src/settlement/equity.jl
#
# SEAM: post-solve equity & rebound analytics — PURE MATH, no solver.
#
# This file declares its own `export`s:
#   - `gini`, `theil`, `atkinson`, `palma` — inequality metrics over per-household
#     bill/surplus vectors (SETL-04), each docstring carrying that metric's
#     negative-value convention (the docstring IS the locked deliverable);
#   - `load_terciles`, `equity_breakdown` — proxy-group breakouts (SETL-05);
#   - `rebound` — load shifted into later hours after price-driven reductions (SETL-06).
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
#   Gini     over ALL values (relative mean-difference; may exceed 1; the sign
#            follows the mean — NEGATIVE on net-earning populations, reported as
#            computed; negatives are NEVER zeroed or dropped — the documented bias
#            finding);
#   Theil    positive-support subset, excluded count RETURNED (log domain);
#   Atkinson positive-support subset, excluded count RETURNED (geometric-mean form);
#   Palma    group-total ratio over the ascending-sorted FULL vector (totals cancel).

export gini, theil, atkinson, palma, load_terciles, equity_breakdown, rebound

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
Vernizzi 2019). Three intended consequences:

  - `G` here is a RELATIVE MEAN-DIFFERENCE measure, NOT a Lorenz-curve concentration
    index: it MAY EXCEED 1 on negative-bearing vectors. The pinned hand-computed
    certificate `gini([-2.0, 1.0, 3.0, 6.0]) == 0.8125` includes a negative.
  - A NEGATIVE MEAN (`mu < 0`, a net-earning population) makes `G` NEGATIVE — the
    sign of `G` follows the sign of `mu` and is REPORTED AS COMPUTED, never clipped
    to non-negative (the docs page pins this convention: the Gini "may be negative
    on net-earning populations"). Mirror-pair certificate: `gini([-3.0, -1.0]) ==
    -0.25 == -gini([1.0, 3.0])` — identical dispersion, the sign carries the mean's.
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

"""
    load_terciles(totals::AbstractVector{<:Real}) -> Vector{Symbol}

Classify each household into load-level terciles `:low` / `:mid` / `:high` from its
baseline consumption total — the SETL-05 "load level" proxy grouping, computed from
the population itself (NO income data exists in this framework and none is used).

Count convention (documented, remainder to the MIDDLE): `n_lo = n ÷ 3`,
`n_hi = n ÷ 3`, `n_mid = n - n_lo - n_hi` — so n = 10 splits 3/4/3, n = 4 splits
1/2/1, n = 3 splits 1/1/1. Assignment walks the STABLE ascending `sortperm`:
rank 1..n_lo => `:low`, the next n_mid ranks => `:mid`, the last n_hi ranks =>
`:high`. Ties therefore resolve by stable index order — deterministic across runs
and platforms (a property the breakouts and writeups rely on).

Guards: an empty vector or any non-finite entry throws `ArgumentError`.
"""
function load_terciles(totals::AbstractVector{<:Real})
    _equity_input_check(:load_terciles, totals)
    n = length(totals)
    n_lo = n ÷ 3
    n_hi = n ÷ 3
    n_mid = n - n_lo - n_hi
    labels = Vector{Symbol}(undef, n)
    for (rank, idx) in enumerate(sortperm(totals))
        labels[idx] = rank <= n_lo ? :low : rank <= n_lo + n_mid ? :mid : :high
    end
    return labels
end

"""
    equity_breakdown(values::AbstractVector{<:Real}, groups::AbstractVector{G})
        -> Dict{G, NamedTuple}

Per-group equity metric set for any household-shaped group vector: each entry is

    (; n, gini, theil, theil_n_excluded, atkinson, atkinson_n_excluded, palma)

with the same documented negative-value conventions as the underlying metrics
(gini over ALL values; theil/atkinson exclusions REPORTED per group; palma
group-total ratio). Atkinson uses the module constant `_ATKINSON_EPSILON`.

GROUPING SOURCE (SETL-05): `groups` is any per-household key vector built from the
`case_a_household_map` row shape (house, bus, aggregator, device_set, pv_group,
house_index) — PV owner vs non-owner (`pv_group`), electrical location (`bus`), or
the load-level terciles of baseline consumption (`load_terciles`). NO income data
exists in this framework and none is used anywhere — bills/surplus only (the
locked no-income-data stance; restated in the phase writeup page).

Guards: a length mismatch between `values` and `groups`, an empty values vector,
or any non-finite entry throws `ArgumentError` (each group is non-empty by
construction — the check names the group should a future shape ever violate it).
"""
function equity_breakdown(
    values::AbstractVector{<:Real},
    groups::AbstractVector{G},
) where {G}
    length(values) == length(groups) || throw(
        ArgumentError(
            "equity_breakdown: length mismatch — $(length(values)) values vs " *
            "$(length(groups)) group keys (one group key per household).",
        ),
    )
    _equity_input_check(:equity_breakdown, values)
    out = Dict{G, NamedTuple}()
    for g in unique(groups)
        member_vals = values[groups .== g]
        isempty(member_vals) &&
            throw(ArgumentError("equity_breakdown: group $(repr(g)) is empty."))
        t = theil(member_vals)
        a = atkinson(member_vals)
        out[g] = (
            n = length(member_vals),
            gini = gini(member_vals),
            theil = t.theil,
            theil_n_excluded = t.n_excluded,
            atkinson = a.atkinson,
            atkinson_n_excluded = a.n_excluded,
            palma = palma(member_vals),
        )
    end
    return out
end

"""
    rebound(baseline_net_load::AbstractVector{<:Real},
            counterfactual_net_load::AbstractVector{<:Real})
        -> (; delta, reduction_hours, increase_hours, rebound_amount, rebound_ratio)

Rebound (snapback) of load shifted into later hours after price-driven reductions
(SETL-06): one single number plus FULL per-hour detail.

INPUT DEFINITION (documented, CONTEXT-locked): both arguments are NET-LOAD profiles
per hour — grid consumption, i.e. the NEGATED net injection (caller converts).
Because a household's net load already nets out behind-the-meter battery charging
and deferrable-load rescheduling, battery-driven shifts and deferrable-driven
shifts are BOTH captured by this one definition — no device-level decomposition is
needed or attempted.

Per-hour detail: `delta[t] = counterfactual[t] - baseline[t]`;
`reduction_hours` = the hours with `delta[t] < 0` (price-driven reductions);
`increase_hours` = the hours with `delta[t] > 0` that come strictly AFTER the
FIRST reduction hour — only those are shifts-into-later-hours; an increase before
any reduction is NOT rebound and is excluded.

Scalars: `rebound_amount = sum of delta over increase_hours`;
`rebound_ratio = rebound_amount / (-sum of delta over reduction_hours)` — the
fraction of the shed load that reappears later. UNDEFINED-RATIO CONVENTION
(matching the theil / atkinson / palma NaN conventions above): with NO reduction
hours the ratio is `NaN` (reported, never a fake 0 or `Inf` — compare with
`isnan`); reductions without any later increase give ratio `0.0` (defined zero).

Convention grounded in demand-response snapback/rebound measurement practice
(smartEn 2025 position paper; CAISO Demand Response Advanced Measurement
Methodology 2022; Minnesota DR snapback study 2021 — see the phase research).

Guards: mismatched profile lengths, an empty profile, or any non-finite entry
throws `ArgumentError`.
"""
function rebound(
    baseline_net_load::AbstractVector{<:Real},
    counterfactual_net_load::AbstractVector{<:Real},
)
    length(baseline_net_load) == length(counterfactual_net_load) || throw(
        ArgumentError(
            "rebound: profile length mismatch — baseline has $(length(baseline_net_load)) " *
            "hours, counterfactual has $(length(counterfactual_net_load)).",
        ),
    )
    _equity_input_check(:rebound, baseline_net_load)
    _equity_input_check(:rebound, counterfactual_net_load)
    T = length(baseline_net_load)
    delta = Float64[counterfactual_net_load[t] - baseline_net_load[t] for t in 1:T]
    reduction_hours = [t for t in 1:T if delta[t] < 0]
    first_reduction = isempty(reduction_hours) ? T + 1 : first(reduction_hours)
    increase_hours = [t for t in 1:T if delta[t] > 0 && t > first_reduction]
    rebound_amount = sum(delta[t] for t in increase_hours; init = 0.0)
    denominator = -sum(delta[t] for t in reduction_hours; init = 0.0)
    rebound_ratio = denominator == 0 ? NaN : rebound_amount / denominator
    return (; delta, reduction_hours, increase_hours, rebound_amount, rebound_ratio)
end
