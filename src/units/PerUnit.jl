# src/units/PerUnit.jl
#
# Per-unit system (INFRA-05). One documented per-unit base; SI inputs are
# converted to per-unit ONCE at ingestion (before any struct is constructed),
# then magnitude-sanity tripwires (explicit `throw(ArgumentError(...))`, NOT
# `@assert`, so they are never elided under `-O`/`--check-bounds=no`) guard
# against SI/pu mixing (RESEARCH Pattern 5, Pitfall 5). These bands are
# deliberately loud sanity
# checks, not physics — an Ω value where pu is expected, or a voltage bound
# outside [0.8, 1.2], fails immediately instead of producing a plausible-wrong
# result downstream.
#
# Documented placeholder base (RESEARCH Open-Question 3 / Assumption A4):
#     S_base = 1.0 MVA,  V_base = 4.16 kV   (IEEE-13-ish distribution level)
# This placeholder is superseded by real feeder fixtures in Phase 4 (DATA-03).
#
# NOTE: `to_pu_*` helpers live here, at ingestion, ONLY. They must never be
# called inside a model builder (that would reintroduce the SI/pu mixing this
# module exists to prevent).

"""
    PerUnitBase{T<:Real}

System per-unit base. `S_base` is the apparent-power base in MVA, `V_base` the
voltage base in kV. Derived bases:

  - `Z_base = V_base^2 / S_base`            (Ω)
  - `I_base = S_base / (√3 · V_base)`       (kA, three-phase)
"""
struct PerUnitBase{T <: Real}
    S_base::T   # MVA
    V_base::T   # kV
end

"""
Impedance base (Ω) for a per-unit system: `V_base^2 / S_base`.
"""
Z_base(b::PerUnitBase) = b.V_base^2 / b.S_base

"""
Current base (kA, three-phase) for a per-unit system: `S_base / (√3 · V_base)`.
"""
I_base(b::PerUnitBase) = b.S_base / (sqrt(3) * b.V_base)

"""
Convert an active/apparent power in MW/MVA to per-unit (÷ `S_base`). Ingestion only.
"""
to_pu_power(x_MW, b::PerUnitBase) = x_MW / b.S_base

"""
Convert an impedance in Ω to per-unit (÷ `Z_base`). Ingestion only.
"""
to_pu_impedance(z_Ω, b::PerUnitBase) = z_Ω / Z_base(b)

# --- Magnitude-sanity bands (heuristic tripwires, RESEARCH Assumption A2) ---
const VOLTAGE_PU_MIN = 0.8
const VOLTAGE_PU_MAX = 1.2
const IMPEDANCE_PU_MAX = 5.0     # per-unit r, x expected well below this
const SMAX_PU_MAX = 100.0        # per-unit apparent-power limit upper sanity bound
const PRICE_MAX = 1.0e4          # $/MWh monetary sanity bound (prices kept in SI)

"""
    SMAX_NO_LIMIT

Canonical "interior branch carries no binding thermal limit" sentinel (IN-01). A branch
tagged with this apparent-power limit gets NO power cone in the SOCP formulation (it is
effectively unconstrained). It must sit STRICTLY inside the `0 < smax < SMAX_PU_MAX` band
that [`assert_magnitudes`](@ref) enforces, so it is deliberately just below `SMAX_PU_MAX`.
This is the SINGLE SOURCE OF TRUTH: both the fixture (`ieee13.jl`) and the formulation
(`ConvexBranchFlow.jl`) reference it rather than re-declaring a bare `99.0` literal, so
the implicit "these two 99.0s must stay equal" coupling can never silently drift.
"""
const SMAX_NO_LIMIT = 99.0

"""
    assert_magnitudes_voltage(v)

Assert a single per-unit voltage magnitude lies in the sanity band
`[0.8, 1.2]`. Throws `ArgumentError` otherwise — a value far outside this band
almost always means an SI quantity leaked in where a per-unit value was expected.

Uses an explicit `throw` (not `@assert`) so the tripwire is never elided under
`-O`/`--check-bounds=no`, matching `topology.jl`'s convention (WR-02).
"""
function assert_magnitudes_voltage(v)
    VOLTAGE_PU_MIN ≤ v ≤ VOLTAGE_PU_MAX || throw(
        ArgumentError(
            "voltage $v pu out of per-unit sanity band [$(VOLTAGE_PU_MIN), $(VOLTAGE_PU_MAX)] " *
            "— check SI/pu conversion at ingestion",
        ),
    )
    return nothing
end

"""
    assert_magnitudes(feeder)

Loud magnitude tripwires over a constructed feeder (INFRA-05). Verifies every
bus voltage bound is in `[0.8, 1.2]` and ordered, every branch per-unit impedance
is `0 ≤ r,x < 5`, and every branch apparent-power limit is `0 < smax < 100`.
Throws `ArgumentError` (naming the offending bus/branch) on any out-of-band
quantity.

Uses explicit `throw`s (not `@assert`) so the tripwires are never elided under
`-O`/`--check-bounds=no`, matching `topology.jl`'s convention (WR-02).

Untyped on purpose: `Feeder` is defined in `data/Feeder.jl`, which is included
*after* this file, so this method is duck-typed and resolved at call time.
"""
function assert_magnitudes(feeder)
    for bus in feeder.buses
        VOLTAGE_PU_MIN ≤ bus.vmin ≤ bus.vmax ≤ VOLTAGE_PU_MAX || throw(
            ArgumentError(
                "voltage bounds [$(bus.vmin), $(bus.vmax)] out of per-unit band " *
                "[$(VOLTAGE_PU_MIN), $(VOLTAGE_PU_MAX)] (or unordered) at bus $(bus.id)",
            ),
        )
    end
    for br in feeder.branches
        0 ≤ br.r < IMPEDANCE_PU_MAX || throw(
            ArgumentError(
                "per-unit resistance $(br.r) implausible on branch $(br.from)->$(br.to) " *
                "(expected 0 ≤ r < $(IMPEDANCE_PU_MAX); is it in Ω?)",
            ),
        )
        0 ≤ br.x < IMPEDANCE_PU_MAX || throw(
            ArgumentError(
                "per-unit reactance $(br.x) implausible on branch $(br.from)->$(br.to) " *
                "(expected 0 ≤ x < $(IMPEDANCE_PU_MAX); is it in Ω?)",
            ),
        )
        0 < br.smax < SMAX_PU_MAX || throw(
            ArgumentError(
                "per-unit power limit $(br.smax) out of band on branch $(br.from)->$(br.to) " *
                "(expected 0 < smax < $(SMAX_PU_MAX))",
            ),
        )
    end
    return nothing
end

export PerUnitBase,
    Z_base,
    I_base,
    to_pu_power,
    to_pu_impedance,
    assert_magnitudes,
    assert_magnitudes_voltage,
    SMAX_NO_LIMIT
