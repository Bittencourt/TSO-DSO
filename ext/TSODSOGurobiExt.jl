# ext/TSODSOGurobiExt.jl
#
# Package extension for the commercial Gurobi solver (INFRA-02, opt-in).
# OWNER: plan 01-03.
#
# Loaded by Julia ONLY when both TSODSO and Gurobi are present in the active
# environment (weakdep + [extensions] gating — the modern replacement for
# Requires.jl). Gurobi is NEVER a hard dependency and stays removable.
#
# When filled, this module will `using TSODSO, Gurobi, JuMP` and register a
# Gurobi-backed optimizer behind the solver factory so the open-source default
# is unaffected. Intentionally an empty compiling shell in plan 01-01.
module TSODSOGurobiExt
end # module TSODSOGurobiExt
