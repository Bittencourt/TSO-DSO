# src/core/ModelContext.jl
#
# SEAM: model context + residual registry (PF-01).
# OWNER: plan 01-03.
#
# When filled, this file will provide the mutable `ModelContext` owning the JuMP
# `Model` plus named registries: `constraints` (name → ConstraintRef, for later
# `dual()` / DADP access), `residuals` (name → AffExpr accumulator — the shared
# nodal-balance seam that `AbstractPowerFlow` formulations write into with no
# `if formulation ==` branching), and `meta`. Helpers `register_constraint!` and
# `add_to_residual!` accompany it. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
