# src/experiments/store.jl
#
# SEAM: run_and_store — @tagsave per-run JLD2 + provenance stamp (EXP-02 / INFRA-04).
# OWNER: plan 08-01 (this plan) wires this STUB into the include graph; plan 08-04 FILLS it.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 4 (depends on 08-03's run_scenario / ScenarioResult). Plan 08-04 fills:
#
#     result_to_dict(res::ScenarioResult) -> Dict{Symbol,Any}
#     run_and_store(s::Scenario; dir::AbstractString = datadir("sims")) -> ScenarioResult
#
# `run_and_store` calls `run_scenario`, builds a Symbol-keyed provenance dict (scalar result
# fields + scenario selectors + `:julia_version => string(VERSION)`), and
# `@tagsave(joinpath(dir, savename(s, "jld2")), dict; storepatch = true)` so the saved
# artifact is stamped with `:gitcommit` (+ `:gitpatch` on a dirty tree) + `:script`. NOTE
# (RESEARCH Pitfall 2): `@tagsave` stamps the git COMMIT, not the Manifest — the committed
# version-specific Manifest (INFRA-01) is the actual environment pin; `:julia_version` covers
# the Manifest's Julia-binary gap. `dir` is an EXPLICIT keyword (default `datadir("sims")`) so
# tests pass `mktempdir()` and stay hermetic (RESEARCH Pitfall 6) — `run_scenario` itself stays
# path-free; persistence lives only here. The per-run JLD2 is NEVER committed (data/ gitignored
# from 08-01).
#
# Filled by plan 08-04 (EXP-02 / INFRA-04 — RESEARCH §Pattern 3 run_and_store / §Pitfall 2 /
# §Pitfall 6 / §Code Examples provenance dict).
