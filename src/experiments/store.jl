# src/experiments/store.jl
#
# SEAM: run_and_store — @tagsave per-run JLD2 + provenance stamp (EXP-02 / INFRA-04).
# OWNER: plan 08-04 (this plan) fills the 08-01 comment-only stub.
#
# `run_and_store(s::Scenario; dir)` calls `run_scenario(s)` (08-03, PATH-FREE), builds a
# Symbol-keyed provenance dict via `result_to_dict`, and `@tagsave`s it to a per-run JLD2
# named `savename(s, "jld2"; digits = 10)` under `dir` (CR-01 fix: `digits = 10` avoids
# DrWatson's lossy default float rounding colliding two distinguishable ADMM-knob Scenarios;
# `safe = true` additionally routes through `safesave` so any residual collision appends
# `_1`/`_2`... rather than silently overwriting). `@tagsave` stamps the saved dict with
# `:gitcommit` (+ `:gitpatch` on a dirty tree, since `storepatch = true`) and `:script`.
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

using DrWatson: @tagsave, datadir, savename, struct2dict

"""
    scenario_filename(s::Scenario) -> String

Single source of truth for the JLD2 filename [`run_and_store`](@ref) saves `s` under:
`savename(s, "jld2"; digits = 10)` (CR-01 fix — see [`run_and_store`](@ref) for why
`digits = 10` is required). Any caller that needs to know/print/reconstruct the path
`run_and_store` will use (e.g. `scripts/run_scenario.jl`) MUST call this helper instead of
re-deriving its own `savename(s, "jld2")` call — a second, independently-maintained call site
is exactly how WR-06 (printed path silently diverging from the actual saved file) happened.
"""
scenario_filename(s::Scenario) = savename(s, "jld2"; digits = 10)

"""
    result_to_dict(res::ScenarioResult) -> Dict{Symbol,Any}

Build the Symbol-keyed provenance dict that [`run_and_store`](@ref) `@tagsave`s: EVERY
`Scenario` selector (`struct2dict(s)` — `name`, `feeder`, `strategy`, `seed`, `T`, `population`,
`price`, `allow_export`, `ρ`, `ε_abs`, `ε_rel`, `maxiter`, `τ_ratio`, `μ`) so the artifact is
self-describing without re-loading the `Scenario` (CR-02 fix: a hand-picked field subset
previously omitted the ADMM knobs and `allow_export`, silently breaking this exact guarantee
for any non-default `:admm` run), the scalar result fields (`welfare`, `exact_maxgap`, `iters`,
`final_r`, `final_s`), the array `dadp`, and `:julia_version => string(VERSION)` (the
Manifest-gap workaround, RESEARCH Pitfall 2).
"""
function result_to_dict(res::ScenarioResult)
    s = res.scenario
    d = struct2dict(s)   # ALL Scenario selectors (CR-02) — never a hand-picked subset
    d[:welfare] = res.welfare
    d[:dadp] = res.dadp
    d[:exact_maxgap] = res.exact_maxgap
    d[:iters] = res.iters
    d[:final_r] = res.final_r
    d[:final_s] = res.final_s
    d[:julia_version] = string(VERSION)
    return d
end

"""
    run_and_store(s::Scenario; dir::AbstractString = datadir("sims")) -> ScenarioResult

Run `s` via [`run_scenario`](@ref) and `@tagsave` a per-run provenance dict to a JLD2 file
named `savename(s, "jld2"; digits = 10)` under `dir` (default `datadir("sims")`, gitignored).
The saved dict carries every field from [`result_to_dict`](@ref) PLUS `:gitcommit` (+
`:gitpatch` on a dirty tree) and `:script`, stamped by `@tagsave` itself (`storepatch = true`).

Takes `dir` as an EXPLICIT keyword so tests can pass `mktempdir()` and stay hermetic
(RESEARCH Pitfall 6) — never rely on `datadir()` resolving under the test environment.
Returns the `ScenarioResult` (the same in-memory value `run_scenario` produced); the JLD2
write is a side effect, never re-loaded by this function.

NOTE (CR-01 fix): `savename`'s DEFAULT float formatting rounds `AbstractFloat` fields to
`sigdigits = 3`, which can collapse two `Scenario`s differing only in a sub-percent ADMM float
knob (`ρ`/`ε_abs`/`ε_rel`/`τ_ratio`/`μ`) onto the IDENTICAL filename — verified directly
against this repo's pinned DrWatson (2.19.1): `ρ = 100.1/100.2/100.4` all produced
`"...ρ=100.0..."` under the bare default. `digits = 10` makes the float component of the
filename round-trip losslessly (no more collisions from display rounding), **and** `safe = true` is passed so `@tagsave` routes through `safesave` (appends `_1`, `_2`, ... instead of
silently overwriting) as defense-in-depth against any RESIDUAL collision (e.g. two Scenarios
that are truly float-identical to 10 digits but differ in a field `default_allowed` excludes).
Together these close the "silently overwrites a prior run's JLD2" data-loss risk this function
previously had.

NOTE (Rule 1 fix, 08-04): `@tagsave`'s `gitpath` keyword defaults to `DrWatson.projectdir()`,
which resolves from the CURRENTLY ACTIVE project — under `Pkg.test()` that is a temporary
sandbox directory Pkg generates for the test run, NOT this package's actual git checkout, so
`gitdescribe` silently finds "not a Git repository" and `:gitcommit` is never stamped
(discovered running this plan's own INFRA-04 provenance testitem through `Pkg.test()`).
`gitpath` is pinned here to `pkgdir(@__MODULE__)` — the actual on-disk source directory of the
`TSODSO` package (always the real git checkout, however the file is dev-installed/sandboxed)
— so `:gitcommit` is stamped reliably both in a plain REPL/script run AND under `Pkg.test()`.
"""
function run_and_store(s::Scenario; dir::AbstractString = datadir("sims"))
    res = run_scenario(s)
    dict = result_to_dict(res)
    @tagsave(
        joinpath(dir, scenario_filename(s)),
        dict;
        storepatch = true,
        gitpath = pkgdir(@__MODULE__),
        safe = true,
    )
    return res
end

export run_and_store, scenario_filename
