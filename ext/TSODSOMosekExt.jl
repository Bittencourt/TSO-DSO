# ext/TSODSOMosekExt.jl
#
# Package extension for the commercial Mosek solver (INFRA-02, opt-in).
# OWNER: plan 01-03.
#
# Loaded by Julia ONLY when both TSODSO and MosekTools are present in the active
# environment (weakdep + [extensions] gating). MosekTools is NEVER a hard
# dependency and stays removable: it appears only under [weakdeps] in Project.toml.
#
# This module adds a `commercial_optimizer(::MosekChoice, pc)` method (Mosek is the
# SOCP gold standard) so the open-source default (select_optimizer) is unaffected.
module TSODSOMosekExt

using TSODSO, MosekTools, JuMP

# Add the commercial method dispatched on the Mosek marker.
TSODSO.commercial_optimizer(::TSODSO.MosekChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(MosekTools.Optimizer)

end # module TSODSOMosekExt
