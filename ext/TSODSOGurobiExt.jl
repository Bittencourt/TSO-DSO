# ext/TSODSOGurobiExt.jl
#
# Package extension for the commercial Gurobi solver (INFRA-02, opt-in).
# OWNER: plan 01-03.
#
# Loaded by Julia ONLY when both TSODSO and Gurobi are present in the active
# environment (weakdep + [extensions] gating — the modern replacement for
# Requires.jl). Gurobi is NEVER a hard dependency and stays removable: it appears
# only under [weakdeps] in Project.toml.
#
# This module adds a `commercial_optimizer(::GurobiChoice, pc)` method so the
# open-source default (select_optimizer) is unaffected; commercial selection is
# opt-in behind the factory via the marker type.
module TSODSOGurobiExt

using TSODSO, Gurobi, JuMP

# Add the commercial method dispatched on the Gurobi marker. `pc::ProblemClass` is
# accepted for interface symmetry; Gurobi handles LP/QP/MILP/SOCP through one
# optimizer, so the class does not change the backend here.
TSODSO.commercial_optimizer(::TSODSO.GurobiChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(Gurobi.Optimizer)

end # module TSODSOGurobiExt
