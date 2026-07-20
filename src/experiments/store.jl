# src/experiments/store.jl
#
# SEAM: run_and_store — @tagsave per-run JLD2 + provenance stamp (EXP-02 / INFRA-04).
# OWNER: plan 08-04 (this plan) fills the 08-01 comment-only stub.
#
# `run_and_store(s::Scenario; dir)` calls `run_scenario(s)` (08-03, PATH-FREE), builds a
# Symbol-keyed provenance dict via `result_to_dict`, and `@tagsave`s it to a per-run JLD2
# named `savename(s, "jld2")` under `dir`. `@tagsave` stamps the saved dict with `:gitcommit`
# (+ `:gitpatch` on a dirty tree, since `storepatch = true`) and `:script`.
#
# NOTE (RESEARCH Pitfall 2 — the CLAUDE.md imprecision corrected by research): `@tagsave`
# stamps the git COMMIT, not the Manifest. It does NOT embed `Project.toml`/`Manifest.toml`
# contents. The actual environment pin is the COMMITTED, version-specific `Manifest.toml`
# (INFRA-01) *at that commit* — `:gitcommit` + the committed Manifest together fully determine
# the resolved package versions. `:julia_version => string(VERSION)` is stored alongside to
# cover the one gap the Manifest itself doesn't pin: which Julia binary ran the solve.
#
# `dir` is an EXPLICIT keyword (default `datadir("sims")`) so tests pass `mktempdir()` and stay
# hermetic (RESEARCH Pitfall 6) — `run_scenario` itself stays path-free; persistence lives only
# here. The per-run JLD2 is NEVER committed (data/ is gitignored, 08-01).

using DrWatson: @tagsave, datadir, savename

"""
    result_to_dict(res::ScenarioResult) -> Dict{Symbol,Any}

Build the Symbol-keyed provenance dict that [`run_and_store`](@ref) `@tagsave`s: the scalar
result fields (`welfare`, `exact_maxgap`, `iters`, `final_r`, `final_s`), the array `dadp`, the
scenario's own selectors (`name`, `feeder`, `strategy`, `seed`, `T`, `price`, `population`) so
the artifact is self-describing without re-loading the `Scenario`, and
`:julia_version => string(VERSION)` (the Manifest-gap workaround, RESEARCH Pitfall 2).
"""
function result_to_dict(res::ScenarioResult)
    s = res.scenario
    return Dict{Symbol,Any}(
        :name => s.name,
        :feeder => s.feeder,
        :strategy => s.strategy,
        :seed => s.seed,
        :T => s.T,
        :price => s.price,
        :population => s.population,
        :welfare => res.welfare,
        :dadp => res.dadp,
        :exact_maxgap => res.exact_maxgap,
        :iters => res.iters,
        :final_r => res.final_r,
        :final_s => res.final_s,
        :julia_version => string(VERSION),
    )
end

"""
    run_and_store(s::Scenario; dir::AbstractString = datadir("sims")) -> ScenarioResult

Run `s` via [`run_scenario`](@ref) and `@tagsave` a per-run provenance dict to a JLD2 file
named `savename(s, "jld2")` under `dir` (default `datadir("sims")`, gitignored). The saved
dict carries every field from [`result_to_dict`](@ref) PLUS `:gitcommit` (+ `:gitpatch` on a
dirty tree) and `:script`, stamped by `@tagsave` itself (`storepatch = true`).

Takes `dir` as an EXPLICIT keyword so tests can pass `mktempdir()` and stay hermetic
(RESEARCH Pitfall 6) — never rely on `datadir()` resolving under the test environment.
Returns the `ScenarioResult` (the same in-memory value `run_scenario` produced); the JLD2
write is a side effect, never re-loaded by this function.
"""
function run_and_store(s::Scenario; dir::AbstractString = datadir("sims"))
    res = run_scenario(s)
    dict = result_to_dict(res)
    @tagsave(joinpath(dir, savename(s, "jld2")), dict; storepatch = true)
    return res
end

export run_and_store
