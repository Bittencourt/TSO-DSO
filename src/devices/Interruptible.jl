# src/devices/Interruptible.jl
#
# SEAM: interruptible (curtailable) flexible-load device (DEV-03).
# OWNER: plan 02-03.
#
# The first `AbstractDevice` implementation: an interruptible load with a concave
# quadratic utility of served power. Implements the dispatched `contribute!` — adds its
# per-time served-power variable and bounds to `ctx.model`, injects `-p[t]` (a
# consumption withdrawal) into `ctx.residuals[:Rp]` at its bus via the indexed
# `add_to_residual!`, and accumulates `Σ_t (a·p[t] - (b/2)·p[t]^2)` into the welfare
# objective via `add_to_objective!`. Traces thesis eqs. 3.10 (utility) and 3.13–3.14
# (flexibility limits).
#
# Filled in wave 2 (plan 02-03) — comment-only stub for now.
