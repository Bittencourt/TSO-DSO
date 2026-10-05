# src/admm/ReactiveMode.jl
#
# SEAM: ReactiveMode, the 3-state reactive-power consensus mode.
#
# A self-contained enum (no JuMP, no dependency on other ADMM files) that is the single source of
# truth for how `qag_dso`, the reactive coupling variable, is treated by `build_dso_opt`,
# `build_agr_opt` and `solve_admm`. The enum lives in its own module so the generic names
# `OFF`, `CERTIFIED` and `LIVE` never enter the package namespace: use `ReactiveMode.OFF`,
# `ReactiveMode.CERTIFIED`, `ReactiveMode.LIVE`; the type is `ReactiveMode.T`.
#
# `normalize_reactive_mode` accepts only a `ReactiveMode.T` and throws `ArgumentError` (never
# `@assert`, project convention) on anything else, listing the valid values.

"""
    ReactiveMode

Module holding the 3-state enum `ReactiveMode.T`, the single source of truth for how the reactive
coupling variable `qag_dso` is treated across `build_dso_opt`, `build_agr_opt` and `solve_admm`:

  - `ReactiveMode.OFF`: constant reactive draw, no coupling variable.
  - `ReactiveMode.CERTIFIED`: pinned one-shot `qag_dso` read, a certified dual and not a live
    dual-ascent loop.
  - `ReactiveMode.LIVE`: genuine mu-dual-ascent consensus on `qag_dso` every ADMM iteration.
"""
module ReactiveMode
@enum T OFF CERTIFIED LIVE
end

"""
    normalize_reactive_mode(m::ReactiveMode.T) -> ReactiveMode.T

Identity on a [`ReactiveMode.T`](@ref ReactiveMode). Any other value (`Bool`, `Symbol`, ...) throws
`ArgumentError` (thrown loudly, never `@assert`, which `-O` can strip) naming the received value
and the valid `ReactiveMode.OFF`, `ReactiveMode.CERTIFIED`, `ReactiveMode.LIVE`.
"""
normalize_reactive_mode(m::ReactiveMode.T)::ReactiveMode.T = m

function normalize_reactive_mode(m)
    throw(
        ArgumentError(
            "normalize_reactive_mode: unsupported value $(repr(m)) of type $(typeof(m)); " *
            "expected a ReactiveMode.T, one of $(join(instances(ReactiveMode.T), ", ")) " *
            "(ReactiveMode.OFF, ReactiveMode.CERTIFIED, ReactiveMode.LIVE).",
        ),
    )
end

export ReactiveMode
