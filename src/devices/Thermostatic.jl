# src/devices/Thermostatic.jl
#
# SEAM: thermostatic (A/C) flexible-load device (DEV-01).
# OWNER: plan 03-03.
#
# An `AbstractDevice` implementing a thermostatically-controlled load: an indoor
# temperature state that evolves by an RC/ETP-style linear recursion in power
# (thesis eqs. 3.2-3.3), kept inside a comfort band, with a concave-quadratic
# comfort utility (eq. 3.11, curvature b > 0 for concavity per 3.13-3.14). Follows
# the `Interruptible` pattern: immutable concretely-typed struct, throw-based
# constructor guards, a `contribute!(d, ctx; T)` that adds the per-step power and
# temperature variables + temporal-coupling constraints and routes its concave
# utility to `add_to_objective!`. Network-agnostic (holds bus + parameters only;
# never a Feeder). Declares its own `export`s when plan 03-03 fills it; comment-
# only stub until then.
