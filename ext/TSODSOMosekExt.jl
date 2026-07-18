# ext/TSODSOMosekExt.jl
#
# Package extension for the commercial Mosek solver (INFRA-02, opt-in).
# OWNER: plan 01-03.
#
# Loaded by Julia ONLY when both TSODSO and MosekTools are present in the active
# environment (weakdep + [extensions] gating). MosekTools is NEVER a hard
# dependency and stays removable.
#
# When filled, this module will `using TSODSO, MosekTools, JuMP` and register a
# Mosek-backed optimizer behind the solver factory (SOCP gold standard) so the
# open-source default is unaffected. Intentionally an empty compiling shell.
module TSODSOMosekExt
end # module TSODSOMosekExt
