# src/data/MeshedFeeder.jl
#
# Immutable, JuMP-free MESHED feeder data model. A
# `MeshedFeeder` mirrors `Feeder`'s (data/Feeder.jl) field shape and
# construction-is-the-gate discipline EXACTLY, but admits a genuinely cyclic
# topology (`nB > N - 1`) that `Feeder`'s `assert_radial` rejects.
#
# LOCK: `Feeder`, `assert_radial`, and `data/topology.jl` are
# UNCHANGED by this file. `MeshedFeeder` is a WHOLLY SEPARATE struct --
# never a subtype or field of `Feeder` -- gated by `assert_connected`
# (`data/mesh_topology.jl`) instead of `assert_radial`. The `Bus`/`Branch`
# structs are REUSED AS-IS from `Feeder.jl` (not redefined here) so
# `solve_welfare`'s duck-typed feeder access works
# unmodified against either struct.
#
# Include-order note: `assert_connected` (data/mesh_topology.jl) must load
# BEFORE this file; `assert_magnitudes` (units/PerUnit.jl) already loads
# before data/Feeder.jl. Both are called from inside the constructor body, so
# they resolve at call time (world age), not at definition time -- mirroring
# the ordering note documented in `Feeder.jl` and `topology.jl`.

"""
    MeshedFeeder{T<:Real}

An immutable, CONNECTED (not necessarily radial) feeder: its `buses`,
`branches`, and the index `root` of the single frontier bus. Construction runs
BOTH invariants -- `assert_connected` (connectivity-only, no
tree/edge-count requirement) and `assert_magnitudes` -- inside the
inner constructor, so an invalid `MeshedFeeder` can never exist. Build one via
`MeshedFeeder(buses, branches, root)`.

`MeshedFeeder` is a SEPARATE struct from `Feeder` -- never a subtype or
field of it. `Feeder`/`assert_radial`/`data/topology.jl` remain
UNCHANGED: the SAME genuinely cyclic edge list that
`MeshedFeeder` accepts still makes `Feeder` throw `ArgumentError`, proving the
radial gate was never weakened to admit meshes.

Validation lives in the INNER constructor deliberately, exactly as `Feeder`
does: defining an inner constructor suppresses Julia's auto-generated
(non-validating) constructors, so there is no way to bypass the checks.
"""
struct MeshedFeeder{T <: Real} <: AbstractFeeder{T}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    root::Int

    function MeshedFeeder{T}(
        buses::Vector{Bus{T}},
        branches::Vector{Branch{T}},
        root::Int,
    ) where {T <: Real}
        feeder = new{T}(buses, branches, root)
        assert_connected(feeder.buses, feeder.branches, feeder.root)  # connectivity invariant
        assert_magnitudes(feeder)                                    # magnitude invariant
        return feeder
    end
end

"""
    MeshedFeeder(buses, branches, root) -> MeshedFeeder{T}

Construct a meshed feeder, inferring `T` from the bus/branch element type and
enforcing both construction invariants before returning:

  - `assert_connected(buses, branches, root)` — connectivity only, `nB > N - 1`
    loops are allowed; and
  - `assert_magnitudes(feeder)` — per-unit magnitude sanity (reused
    verbatim -- it has no topology dependence).

Throws `ArgumentError` on a disconnected/malformed feeder and (also
`ArgumentError`) on out-of-band magnitudes. Mirrors `Feeder`'s own outer
constructor exactly.
"""
MeshedFeeder(
    buses::Vector{Bus{T}},
    branches::Vector{Branch{T}},
    root::Integer,
) where {T <: Real} = MeshedFeeder{T}(buses, branches, Int(root))

export MeshedFeeder
