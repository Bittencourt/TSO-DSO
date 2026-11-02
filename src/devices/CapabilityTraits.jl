# src/devices/CapabilityTraits.jl
#
# SEAM: typed capability-trait overrides for the EXISTING device library.
#
# WHY THIS FILE EXISTS (and why the overrides do NOT live in the device files):
# the existing device source files (PVBattery.jl, Thermostatic.jl, FourQuadBESS.jl,
# FixedCapacitor.jl, Deferrable.jl, Interruptible.jl, Scenario.jl) are
# byte-identical GOLDEN files — the project's golden policy forbids touching them,
# and this phase's gate audit requires ZERO diffs on them. The `is_flexible_load`
# precedent (AbstractDevice.jl) defines traits on the abstract type with one-line
# defaults; its per-device overrides live inside the device files only because
# those files were being written anyway. For the REFACTOR traits
# (`has_reactive_decision`, `storage_kind`) the golden policy pins every existing
# device file, so their typed overrides are collected HERE — one file, one line
# per override, each citing the historical probe resolution it reproduces.
# New devices override the traits in their OWN files as usual (the include order
# puts this file after every existing device, before Aggregator.jl).

# --- has_reactive_decision ------------------------------------------------------------
# Default (AbstractDevice.jl): `has_reactive_decision(d) = is_flexible_load(d)` —
# already the flexible-load half of the historical probe. The isa half becomes
# this single typed override:
has_reactive_decision(::FourQuadBESS) = true

# --- storage_kind -----------------------------------------------------------------------
# Default (AbstractDevice.jl): `:none` at both the type and instance level.
# Historical selection: battery ⇔ stash entry carried :p_ch/:p_dch WITHOUT :q;
# four-quadrant ⇔ with :q. Reproduced per type (the values the certificate
# selection reads off the type-paired stash):
storage_kind(::Type{<:PVBattery}) = :battery
storage_kind(::Type{<:FourQuadBESS}) = :four_quadrant
# ElectricVehicle (43-02): its vars carry the battery SHAPE (p_ch/p_dch, no :q), which would
# false-match the battery certificate's shape predicate. `:ev` routes it to its OWN certificate
# (`assert_ev_complementarity!`) and keeps battery semantics off EV vars.
storage_kind(::Type{<:ElectricVehicle}) = :ev

# --- behavioural wrappers (phase 44, ACTOR-04) --------------------------------------------
# Wrapper traits FORWARD the inner device's (a wrapper must never acquire or lose another
# regime's semantics). OptOut stores the inner traits at construction and is `:none` for storage
# (a constant baseline has no storage dynamics, vars = (;)).
is_flexible_load(d::PartialCompliance) = is_flexible_load(d.inner)
is_flexible_load(d::Rebound) = is_flexible_load(d.inner)
is_flexible_load(d::OptOut) = d.flexible
has_reactive_decision(d::PartialCompliance) = has_reactive_decision(d.inner)
has_reactive_decision(d::Rebound) = has_reactive_decision(d.inner)
has_reactive_decision(d::OptOut) = d.reactive
storage_kind(::Type{<:PartialCompliance{D}}) where {D} = storage_kind(D)
storage_kind(::Type{<:Rebound{D}}) where {D} = storage_kind(D)
storage_kind(::Type{<:OptOut}) = :none

# --- type-paired stash-entry selection ----------------------------------------------------
# Selection over the device stash (`ctx.agg_device_vars`) for the certificate
# publishers (welfare_solve.jl's battery check, admm_state.jl's `_react_outputs`
# 4Q publish): an entry is classified by its PAIRED type (same bus, same index —
# both appended by `Aggregator.contribute!`'s per-device loop) whenever the
# provenance exists; production paths always pair (asserted by the stash-pairing
# test item). Entries WITHOUT (or with shorter) type lists — hand-built test
# contexts like the synthetic `ctx.agg_device_vars` entries in the certificate
# test files — FALL BACK to the legacy shape predicate, preserving the
# pre-refactor classification exactly so those fixtures stay green.
function _stash_entry_has_kind(
    types::Union{Nothing, Vector{DataType}},
    v,
    i::Int,
    kind::Symbol,
    legacy_shape::Function,
)
    if types !== nothing && length(types) >= i
        return storage_kind(types[i]) === kind
    end
    return legacy_shape(v)
end
