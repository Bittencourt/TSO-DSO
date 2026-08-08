# src/admm/ReactiveMode.jl
#
# SEAM: ReactiveMode — the 3-state reactive-power consensus mode (MESH-05).
# OWNER: plan 19-01 (this plan fully implements it; consumed by plans 19-03/19-06/19-07).
#
# WHAT IT IS: a self-contained enum (zero dependency on any other Phase-19 file, no JuMP) that
# is the SINGLE source of truth for the 3-way distinction between how `qag_dso` (the reactive
# coupling variable introduced by REACT-01, Phase 16) is treated by `build_dso_opt`,
# `build_agr_opt`, and `solve_admm`:
#
#   * `OFF`       — reproduces today's constant reactive draw (`reactive_consensus = false`
#                   pre-Phase-16 default): `q_draw[j][t]` is injected directly into `:Rq`, no
#                   coupling variable exists.
#   * `CERTIFIED` — reproduces today's pinned one-shot `qag_dso` read, BYTE-IDENTICAL to
#                   `reactive_consensus = true` pre-Phase-19 (REACT-01/REACT-03): `qag_dso[j,t]`
#                   is a genuine JuMP variable but is PINNED to the fixed target `q_draw[j][t]`
#                   via an explicit equality (`:qag_pin`) — a one-shot certified dual read, not
#                   a live dual-ascent loop (thesis A3: `q_draw` never moves).
#   * `LIVE`      — the NEW Phase-19 μ-dual-ascent path: `qag_dso[j,t]` becomes a genuine
#                   ADMM consensus variable, updated by a μ dual-ascent step every iteration
#                   (mirroring the existing λ_j active-power dual-ascent), unlocking the live
#                   reactive pricing deferred in v2.1.
#
# `normalize_reactive_mode` accepts any of `Bool` (D-12 back-compat with the pre-Phase-19
# `reactive_consensus::Bool` kwarg: `false → OFF`, `true → CERTIFIED`), an existing
# `ReactiveMode` (identity), or a `Symbol` (`:off`, `:certified`, `:live`), and throws
# `ArgumentError` (never `@assert`, project convention — see `src/data/profiles.jl`) on any
# other value or unrecognized `Symbol`, naming the received value in the message.

"""
    ReactiveMode

3-state enum — the SINGLE source of truth for how the reactive coupling variable `qag_dso` is
treated across `build_dso_opt`, `build_agr_opt`, and `solve_admm` (MESH-05):

  - `OFF`: constant reactive draw, no coupling variable (pre-Phase-16 default behavior).
  - `CERTIFIED`: pinned one-shot `qag_dso` read, byte-identical to `reactive_consensus = true`
    pre-Phase-19 (REACT-01/REACT-03) — a certified dual, not a live dual-ascent loop.
  - `LIVE`: genuine μ-dual-ascent consensus on `qag_dso` every ADMM iteration (Phase 19, NEW).

Construct via [`normalize_reactive_mode`](@ref) rather than the enum constructor directly when
accepting user-facing input (`Bool` or `Symbol`), so back-compat and validation are applied
uniformly.
"""
@enum ReactiveMode OFF CERTIFIED LIVE

"""
    normalize_reactive_mode(m) -> ReactiveMode

Normalize `m` to a [`ReactiveMode`](@ref), accepting:

  - `m::Bool` — D-12 back-compat with the pre-Phase-19 `reactive_consensus::Bool` kwarg:
    `false → OFF`, `true → CERTIFIED`.
  - `m::ReactiveMode` — returned unchanged (identity).
  - `m::Symbol` — `:off → OFF`, `:certified → CERTIFIED`, `:live → LIVE`.

Throws `ArgumentError` (project convention: throw LOUDLY, never `@assert`, which `-O` can
strip) naming the received value, on any other type or an unrecognized `Symbol`.
"""
function normalize_reactive_mode(m::Bool)::ReactiveMode
    return m ? CERTIFIED : OFF
end

function normalize_reactive_mode(m::ReactiveMode)::ReactiveMode
    return m
end

function normalize_reactive_mode(m::Symbol)::ReactiveMode
    m === :off && return OFF
    m === :certified && return CERTIFIED
    m === :live && return LIVE
    throw(
        ArgumentError(
            "normalize_reactive_mode: unrecognized Symbol $(repr(m)); expected one of " *
            ":off, :certified, :live.",
        ),
    )
end

function normalize_reactive_mode(m)
    throw(
        ArgumentError(
            "normalize_reactive_mode: unsupported value $(repr(m)) of type $(typeof(m)); " *
            "expected a Bool, ReactiveMode, or Symbol (:off/:certified/:live).",
        ),
    )
end

export ReactiveMode, OFF, CERTIFIED, LIVE, normalize_reactive_mode
