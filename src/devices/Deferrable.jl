# src/devices/Deferrable.jl
#
# SEAM: deferrable (shiftable) flexible-load device (DEV-02).
# OWNER: plan 03-03.
#
# An `AbstractDevice` implementing a deferrable load: power drawn within a time
# window whose integral must meet an energy budget (thesis eqs. 3.4-3.5), with a
# concave-quadratic utility (eq. 3.12). Follows the `Interruptible` pattern:
# immutable concretely-typed struct, throw-based guards (concavity, feasible
# window/budget), and a `contribute!(d, ctx; T)` that adds the per-step power
# variables + energy-window coupling constraint and routes its concave utility to
# `add_to_objective!`. Network-agnostic (bus + parameters only; never a Feeder).
# Declares its own `export`s when plan 03-03 fills it; comment-only stub until then.
