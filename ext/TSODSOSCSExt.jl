# ext/TSODSOSCSExt.jl
#
# Package extension for the open-source, first-order SCS conic solver (INFRA-02,
# D-20, opt-in). OWNER: plan 25-02.
#
# Loaded by Julia ONLY when both TSODSO and SCS are present in the active
# environment (weakdep + [extensions] gating — the modern replacement for
# Requires.jl). SCS is NEVER a hard dependency and stays removable: it appears
# only under [weakdeps] in Project.toml.
#
# This module adds an `alternative_optimizer(::SCSChoice, pc)` method — deliberately
# NOT `commercial_optimizer` (D-20): SCS is open-source, so routing it through a
# dispatch named/documented as "commercial" would be a semantic mismatch, even
# though (like the commercial backends) it is an opt-in weakdep extension. SCS is
# the Clarabel-vs-SCS crossover measurement's alternative first-order conic solver
# (SCALE-04) — a large-scale/scouting fallback, NEVER used to certify SOCP
# exactness or to report final DADPs (CLAUDE.md "What NOT to Use").
module TSODSOSCSExt

using TSODSO, SCS, JuMP

# Add the alternative method dispatched on the SCS marker. `pc::ProblemClass` is
# accepted for interface symmetry with `commercial_optimizer`; SCS handles the
# conic problem classes (QP/SOCP) through one optimizer, so the class does not
# change the backend here. `"verbose" => 0` mirrors the factory's existing
# solver-silencing convention (Clarabel `verbose => false`, HiGHS `output_flag =>
# false`, Ipopt `print_level => 0`).
TSODSO.alternative_optimizer(::TSODSO.SCSChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(SCS.Optimizer, "verbose" => 0)

end # module TSODSOSCSExt
