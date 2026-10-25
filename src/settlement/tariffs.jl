# src/settlement/tariffs.jl
#
# SEAM: tariff price-CONSTRUCTION — pure arithmetic over ONE solved DADP run.
#
# This file declares its own `export`s:
#   - `revenue_neutral_flat`, `revenue_neutral_tou` — the derivation kernels (pure,
#     no solver of any kind anywhere in this file);
#   - `flat_prices`, `tou_prices` — convenience wrappers over a packed
#     `SettlementInput` (41-01's adapter);
#   - `default_tou_bins` — the pinned 24-h bin structure accessor.
#
# THE LOCKED FAIRNESS CONDITION (Phase-41 CONTEXT): flat and TOU prices are DERIVED
# from the same DADP run revenue-neutrally — total payments under the derived tariff
# equal total payments under DADP on the SAME run. This is the comparison's fairness
# condition (SETL-02): every tariff leg must collect the same total from the same
# quantities, so a comparison isolates DISPATCH behavior, not tariff revenue.
#
# WEIGHT CHOICE (the Phase-41 A2 resolution, normative): the weights `w[j, t]` are
# the DADP run's OWN signed net quantities (`SettlementInput.bus_nets[j][t]`, net
# INJECTION per hour). Rationale: the fairness condition is on total PAYMENTS, and
# payments settle on net injections (exporter earns / importer pays, the same sign
# convention as `welfare_accounting`'s transfer term) — a quantity-weighted mean over
# those same quantities makes the identity ALGEBRAIC (see `revenue_neutral_flat`'s
# docstring), so the rescale step below is a numerical-hygiene no-op guard, never a
# correction. Other weight choices (e.g. gross load) would each be revenue-neutral
# too but would move the derived levels; the signed-net choice is the one where the
# fairness condition and the settlement quantities coincide.
#
# GOLDEN POLICY: purely additive — consumes only a `SettlementInput`'s published
# numbers; `src/pricing/` and `src/admm/` are never touched. Monetary units are the
# framework's existing welfare units (¢$/kWh-consistent, the same as `λ₀` and the
# device utility coefficients — a second unit would scale a surplus by 10×/100×).

export revenue_neutral_flat, revenue_neutral_tou, flat_prices, tou_prices, default_tou_bins

# --- Pinned TOU bin structure (the Phase-41 A4 resolution) -----------------------------
#
# Fixed hour blocks over the 24-h profile, pinned as auditable module constants in
# the fit.jl named-constant discipline (a mis-specified bin boundary would silently
# move the TOU levels and every downstream comparison row). 6/12/6 split matching
# the mem-price shape: overnight trough / broad shoulder / evening peak.
const _TOU_OFFPEAK_HOURS = 1:6                    # hours 1–6   (00:00–05:59)
const _TOU_SHOULDER_HOURS = vcat(7:16, 23:24)     # hours 7–16 + 23–24 (06:00–15:59, 22:00–23:59)
const _TOU_PEAK_HOURS = 17:22                     # hours 17–22 (16:00–21:59)

"""
    default_tou_bins(T::Int) -> Vector{Vector{Int}}

The pinned TOU bin structure (the Phase-41 A4 resolution) as a partition of `1:T`:
`[collect(_TOU_OFFPEAK_HOURS), collect(_TOU_SHOULDER_HOURS), collect(_TOU_PEAK_HOURS)]`
— off-peak 00:00–05:59, shoulder 06:00–15:59 ∪ 22:00–23:59, peak 16:00–21:59.

Defined for the 24-hour profile ONLY (`T == 24`): the bin boundaries are pinned to
hour-of-day blocks, and re-interpreting them at another horizon would silently
re-weight the TOU levels. Any other `T` throws an `ArgumentError` naming this
function — the caller must pass explicit `bins` to `revenue_neutral_tou` /
`tou_prices` for non-daily horizons (as the test fixtures at `T = 3` do).
"""
function default_tou_bins(T::Int)
    T == 24 || throw(
        ArgumentError(
            "default_tou_bins: the pinned TOU bins are hour-of-day blocks defined " *
            "for the 24-hour profile only (got T=$T) — pass explicit " *
            "bins::Vector{Vector{Int}} to revenue_neutral_tou/tou_prices for this " *
            "horizon.",
        ),
    )
    return [
        collect(_TOU_OFFPEAK_HOURS),
        collect(_TOU_SHOULDER_HOURS),
        collect(_TOU_PEAK_HOURS),
    ]
end

# Internal: validate `bins` as a PARTITION of 1:T — every hour exactly once, no
# empty bin, no out-of-range hour, no gap, no overlap (fail-loud boundary guard;
# a silent double-count would corrupt the revenue-neutrality identity itself).
function _validate_tou_bins(bins::Vector{Vector{Int}}, T::Int)
    isempty(bins) &&
        throw(ArgumentError("bins is empty — expected a non-empty partition of 1:$T"))
    for (k, bin) in enumerate(bins)
        isempty(bin) &&
            throw(ArgumentError("bins[$k] is empty — every bin must carry at least one hour"))
        for h in bin
            1 <= h <= T || throw(
                ArgumentError(
                    "bins[$k] contains hour $h outside 1:$T — bins must partition 1:$T",
                ),
            )
        end
    end
    seen = falses(T)
    for (k, bin) in enumerate(bins), h in bin
        seen[h] && throw(
            ArgumentError(
                "hour $h appears in more than one bin (bins[$k] overlaps an earlier " *
                "bin) — bins must partition 1:$T with every hour exactly once",
            ),
        )
        seen[h] = true
    end
    all(seen) || throw(
        ArgumentError(
            "bins leave hours unassigned (gap at $(findall(!, seen))) — bins must " *
            "partition 1:$T",
        ),
    )
    return nothing
end

# Internal: shared guards + the Σλw / Σw folds for the derivation kernels.
function _tariff_folds(λ::AbstractMatrix{<:Real}, w::AbstractMatrix{<:Real}, who::AbstractString)
    size(λ) == size(w) || throw(
        ArgumentError(
            "$who: λ has size $(size(λ)) but w has size $(size(w)) — they must match " *
            "(aggregator buses × hours).",
        ),
    )
    nb, T = size(λ)
    T >= 1 || throw(ArgumentError("$who: horizon T=$T must be at least 1"))
    for arr in (λ, w), v in arr
        isfinite(v) || throw(
            ArgumentError("$who: non-finite value ($v) in the price/weight matrices"),
        )
    end
    tot_pq = 0.0   # Σ_{j,t} λ·w   (total DADP payments over the weights)
    tot_q = 0.0    # Σ_{j,t} w      (signed weight sum)
    tot_qabs = 0.0 # Σ_{j,t} |w|    (weight mass)
    for t in 1:T, j in 1:nb
        tot_pq += λ[j, t] * w[j, t]
        tot_q += w[j, t]
        tot_qabs += abs(w[j, t])
    end
    tot_qabs > 0.0 || throw(
        ArgumentError(
            "$who: Σ|w| = $tot_qabs — all-zero weights carry no settlement quantity, " *
            "so no revenue-neutral tariff is defined.",
        ),
    )
    tot_q != 0.0 || throw(
        ArgumentError(
            "$who: Σw = 0.0 (signed weights cancel; Σ|w| = $tot_qabs) — the " *
            "quantity-weighted mean divides by Σw, which is undefined here. Use a " *
            "weight basis with a nonzero signed sum (e.g. the run's own net " *
            "injections, which cannot all cancel at settlement time).",
        ),
    )
    return (; nb, T, tot_pq, tot_q)
end

# Internal: the no-op-guard GLOBAL rescale. In exact arithmetic s == 1.0
# identically (see `revenue_neutral_flat`); the assert is numerical hygiene — a
# mis-derived level cannot masquerade as revenue-neutral (threat T-41-10).
function _rescale_guard(tot_pq::Float64, scaled_total::Float64, who::AbstractString)
    s = tot_pq / scaled_total
    isapprox(s, 1.0; rtol = 1e-9) || error(
        "$who: the no-op rescale factor is s = $s, expected ≈ 1.0 (rtol 1e-9) — " *
        "the weighted-mean construction is algebraically revenue-neutral, so a " *
        "rescale this far from unity is a numerical failure, not a correction.",
    )
    return s
end

"""
    revenue_neutral_flat(λ::AbstractMatrix, w::AbstractMatrix) -> Vector{Float64}

Revenue-neutral FLAT price construction (SETL-02): one scalar level per hour
(the same flat price for every hour and bus), quantity-weighted from one solved
DADP run's prices `λ` (buses × hours) and quantities `w` (buses × hours, the run's
OWN signed net injections — see the module header's A2 note).

The algebra (why the identity is EXACT): with
`p̂ = Σ_{j,t} λ[j,t]·w[j,t] / Σ_{j,t} w[j,t]`, the derived total

    Σ_{j,t} p̂·w[j,t] = p̂ · Σ_{j,t} w[j,t] = Σ_{j,t} λ[j,t]·w[j,t]

is the DADP total *identically* — the locked fairness condition holds by
construction, before any rescale. The final `s = (Σ λ·w)/(Σ p̂·w)` rescale is a
NO-OP GUARD for floating-point hygiene only: `s` is asserted ≈ 1.0 (rtol 1e-9) and
an `ErrorException` carrying `s` is thrown otherwise (a mis-derived level cannot
masquerade as revenue-neutral). The structural-vs-solver assertion split (project
convention): on exactly-representable hand values the totals identity holds with
literal `==`; on real runs it holds to measured rounding dust.

Guards: `size(λ) == size(w)`, all entries finite, `Σ|w| > 0`, and `Σw ≠ 0` (signed
weights that cancel make the weighted mean undefined) — each an `ArgumentError`
carrying the offending magnitudes.

See also [`revenue_neutral_tou`](@ref), [`flat_prices`](@ref).
"""
function revenue_neutral_flat(λ::AbstractMatrix{<:Real}, w::AbstractMatrix{<:Real})
    folds = _tariff_folds(λ, w, "revenue_neutral_flat")
    p̂ = folds.tot_pq / folds.tot_q
    scaled_total = 0.0
    for t in 1:folds.T, j in 1:folds.nb
        scaled_total += p̂ * w[j, t]
    end
    s = _rescale_guard(folds.tot_pq, scaled_total, "revenue_neutral_flat")
    return Float64[s * p̂ for _ in 1:folds.T]
end

"""
    revenue_neutral_tou(λ::AbstractMatrix, w::AbstractMatrix; bins::Vector{Vector{Int}}) -> Vector{Float64}

Revenue-neutral TOU price construction (SETL-02): per-bin quantity-weighted mean
levels (the same `revenue_neutral_flat` algebra WITHIN each bin), broadcast to the
bin's hours, followed by ONE GLOBAL rescale over all hours — `s = (Σ λ·w)/(Σ p̂·w)`
with the same ≈ 1.0 no-op-guard assert. One global (not per-bin) rescale is what
keeps the identity algebraic while preserving the bin levels' RELATIVE shape.

`bins` must be a partition of `1:T` — every hour exactly once, no empty bin, no
out-of-range hour — validated loudly (`ArgumentError` naming the defect: overlap /
gap / out-of-range / empty). For the 24-hour profile use
[`default_tou_bins`](@ref); other horizons pass explicit bins.

See also [`revenue_neutral_flat`](@ref), [`tou_prices`](@ref).
"""
function revenue_neutral_tou(
    λ::AbstractMatrix{<:Real},
    w::AbstractMatrix{<:Real};
    bins::Vector{Vector{Int}},
)
    folds = _tariff_folds(λ, w, "revenue_neutral_tou")
    _validate_tou_bins(bins, folds.T)
    p̂ = Vector{Float64}(undef, folds.T)
    for bin in bins
        bin_pq = 0.0
        bin_q = 0.0
        for t in bin, j in 1:folds.nb
            bin_pq += λ[j, t] * w[j, t]
            bin_q += w[j, t]
        end
        bin_q != 0.0 || throw(
            ArgumentError(
                "revenue_neutral_tou: bin $bin has Σw = 0.0 (Σ|w| = " *
                "$(sum(abs(w[j, t]) for t in bin, j in 1:folds.nb))) — the bin's " *
                "weighted-mean level is undefined on these weights.",
            ),
        )
        level = bin_pq / bin_q
        for t in bin
            p̂[t] = level
        end
    end
    scaled_total = 0.0
    for t in 1:folds.T, j in 1:folds.nb
        scaled_total += p̂[t] * w[j, t]
    end
    s = _rescale_guard(folds.tot_pq, scaled_total, "revenue_neutral_tou")
    return Float64[s * p̂[t] for t in 1:folds.T]
end

# Internal: pack a SettlementInput's per-bus quantities into a (buses × hours)
# weight matrix in `input.buses` order (ascending — the adapters assert it).
function _input_weight_matrix(input::SettlementInput)
    w = Matrix{Float64}(undef, length(input.buses), input.T)
    for (i, j) in enumerate(input.buses), t in 1:input.T
        w[i, t] = input.bus_nets[j][t]
    end
    return w
end

"""
    flat_prices(input::SettlementInput) -> Vector{Float64}

Revenue-neutral flat prices derived from ONE solved run's packed
[`SettlementInput`](@ref): `revenue_neutral_flat` over the run's published prices
(`input.prices`, ascending-bus rows) weighted by the run's OWN signed net
injections (`input.bus_nets`, the A2 choice — see the module header). Returns a
length-`T` vector (the same flat level every hour — that is what `:flat` means).
"""
function flat_prices(input::SettlementInput)
    return revenue_neutral_flat(input.prices, _input_weight_matrix(input))
end

"""
    tou_prices(input::SettlementInput; bins = default_tou_bins(input.T)) -> Vector{Float64}

Revenue-neutral TOU prices derived from ONE solved run's packed
[`SettlementInput`](@ref): `revenue_neutral_tou` over the run's published prices
weighted by the run's OWN signed net injections (the A2 choice). `bins` defaults
to the pinned 24-h structure via [`default_tou_bins`](@ref) (so non-daily horizons
must pass explicit bins).
"""
function tou_prices(input::SettlementInput; bins::Vector{Vector{Int}} = default_tou_bins(input.T))
    return revenue_neutral_tou(input.prices, _input_weight_matrix(input); bins = bins)
end
