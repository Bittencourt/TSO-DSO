# src/data/Feeder.jl
#
# Immutable, JuMP-free feeder data model (DATA-01). Concretely-typed parametrized
# structs holding PER-UNIT numbers only — no solver or JuMP knowledge lives here.
# Construction is the validation gate: the outer `Feeder(...)` constructor runs
# BOTH the radial-topology invariant (`assert_radial`, DATA-02) AND the per-unit
# magnitude tripwires (`assert_magnitudes`, INFRA-05) before returning, so an
# invalid feeder can never exist. Structs are immutable: validation is a
# construction invariant, never re-checked or mutated afterwards.
#
# Include-order note: `assert_magnitudes` (units/PerUnit.jl) is included BEFORE
# this file; `assert_radial` (data/topology.jl) is included AFTER. Both are
# called from inside the constructor body, so they resolve at call time (world
# age), not at definition time — no forward-declaration is needed.
#
# Convention (Phase 1): bus `id` equals its 1-based position in `buses`.

"""
    Bus{T<:Real}

A feeder bus. `id` is its 1-based index; `vmin`/`vmax` are per-unit voltage
bounds; `is_root` flags the single MEM/substation frontier (root) bus.
"""
struct Bus{T<:Real}
    id::Int
    vmin::T
    vmax::T
    is_root::Bool
end

"""
    Branch{T<:Real}

A feeder branch from bus `from` to bus `to`, with per-unit resistance `r`,
reactance `x`, and apparent-power limit `smax`.
"""
struct Branch{T<:Real}
    from::Int
    to::Int
    r::T
    x::T
    smax::T
end

"""
    Feeder{T<:Real}

An immutable radial feeder: its `buses`, `branches`, and the index `root` of the
single frontier bus. Construction runs BOTH invariants — `assert_radial`
(DATA-02) and `assert_magnitudes` (INFRA-05) — inside the inner constructor, so
an invalid feeder can never exist. Build one via `Feeder(buses, branches, root)`.

Validation lives in the INNER constructor deliberately: defining an inner
constructor suppresses Julia's auto-generated (non-validating) constructors, so
there is no way to bypass the checks (and no method-overwriting at precompile).
"""
struct Feeder{T<:Real}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    root::Int

    function Feeder{T}(
        buses::Vector{Bus{T}},
        branches::Vector{Branch{T}},
        root::Int,
    ) where {T<:Real}
        feeder = new{T}(buses, branches, root)
        assert_radial(feeder.buses, feeder.branches, feeder.root)  # DATA-02 topology invariant
        assert_magnitudes(feeder)                                  # INFRA-05 magnitude invariant
        return feeder
    end
end

"""
    Feeder(buses, branches, root) -> Feeder{T}

Construct a feeder, inferring `T` from the bus/branch element type and enforcing
both construction invariants before returning:

  * `assert_radial(buses, branches, root)` — radial tree (DATA-02); and
  * `assert_magnitudes(feeder)` — per-unit magnitude sanity (INFRA-05).

Throws `ArgumentError` on a non-tree feeder and `AssertionError` on out-of-band
magnitudes. Both fire on this live path, so any downstream consumer (e.g. the
walking-skeleton solve) inherits validated data for free.
"""
Feeder(buses::Vector{Bus{T}}, branches::Vector{Branch{T}}, root::Integer) where {T<:Real} =
    Feeder{T}(buses, branches, Int(root))

export Bus, Branch, Feeder
