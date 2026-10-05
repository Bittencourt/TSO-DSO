# src/experiments/store.jl
#
# SEAM: run_and_store — @tagsave per-run JLD2 + provenance stamp.
#
# `run_and_store(s::Scenario; dir)` calls `run_scenario(s)` (PATH-FREE), builds a
# Symbol-keyed provenance dict via `result_to_dict`, and `@tagsave`s it to a per-run JLD2
# named `scenario_filename(s)` under `dir` (`digits = 10` avoids
# DrWatson's lossy default float rounding colliding two distinguishable ADMM-knob Scenarios;
# `safe = true` additionally routes through `safesave` so any residual collision appends
# `_1`/`_2`... rather than silently overwriting). `@tagsave` stamps the saved dict with
# `:gitcommit` (+ `:gitpatch` on a dirty tree, since `storepatch = true`) and `:script`.
#
# NOTE (a common misreading is that the Manifest is embedded): `@tagsave`
# stamps the git COMMIT, not the Manifest. It does NOT embed `Project.toml`/`Manifest.toml`
# contents. The actual environment pin is the COMMITTED, version-specific `Manifest.toml`
# *at that commit* — `:gitcommit` + the committed Manifest together fully determine
# the resolved package versions. `:julia_version => string(VERSION)` is stored alongside to
# cover the one gap the Manifest itself doesn't pin: which Julia binary ran the solve.
#
# `dir` is an EXPLICIT keyword (default `datadir("sims")`) so tests pass `mktempdir()` and stay
# hermetic — `run_scenario` itself stays path-free; persistence lives only
# here. The per-run JLD2 is NEVER committed (data/ is gitignored).

using DrWatson: @tagsave, datadir, savename

"""
    _stable_hex64(bytes) -> String

Internal (unexported): a DETERMINISTIC, Julia-version-stable 64-bit FNV-1a digest of a
byte iterable, rendered as exactly 16 zero-padded lowercase hex characters. Used by
[`scenario_filename`](@ref) to fold `probabilities` — a
`Vector{Float64}` DrWatson's `default_allowed` filter silently DROPS from `savename` —
back into the filename. Deliberately NOT `Base.hash`, whose value is only stable within
a single Julia version (this project tests 1.10 LTS and 1.11+), and dependency-free (no
SHA import; `Project.toml` is untouched).
"""
function _stable_hex64(bytes)
    h = 0xcbf29ce484222325                      # FNV-1a 64-bit offset basis
    for b in bytes
        h = (h ⊻ UInt64(b)) * 0x00000100000001b3   # FNV-1a 64-bit prime (wrapping mul)
    end
    return string(h; base = 16, pad = 16)
end

# --- strategy flatten helpers (one method per strategy: a new strategy adds one method) ---
_strategy_label(::Centralized) = :centralized
_strategy_label(::ADMM) = :admm
_strategy_label(::MPC) = :mpc
_strategy_label(::Stochastic) = :stochastic

# Active-strategy knobs. :filename -> prefixed primitive names (probabilities dropped: folded
# into the name as a digest by `scenario_filename`); :record -> legacy flat keys.
_strategy_knobs(::Centralized, ::Symbol) = Pair{Symbol, Any}[]
function _strategy_knobs(st::ADMM, style::Symbol)
    pre = style === :filename ? "admm_" : ""
    return Pair{Symbol, Any}[
        Symbol(pre, "ρ") => st.ρ,
        Symbol(pre, "ε_abs") => st.ε_abs,
        Symbol(pre, "ε_rel") => st.ε_rel,
        Symbol(pre, "maxiter") => st.maxiter,
        Symbol(pre, "τ_ratio") => st.τ_ratio,
        Symbol(pre, "μ") => st.μ,
    ]
end
function _strategy_knobs(st::MPC, ::Symbol)
    return Pair{Symbol, Any}[
        :mpc_H => st.H,
        :mpc_step => st.step,
        :mpc_terminal_soc => st.terminal_soc,
        :mpc_forecast_error => st.forecast_error,
    ]
end
function _strategy_knobs(st::Stochastic, style::Symbol)
    knobs = Pair{Symbol, Any}[:stoch_S => st.S]
    style === :record && push!(knobs, :stoch_probabilities => copy(st.probabilities))
    push!(knobs, :stoch_H_oos => st.H_oos)
    return knobs
end

"""
    _scenario_identity(s::Scenario; style::Symbol) -> Dict{Symbol,Any}

Single source of truth flattening a `Scenario` (whose `strategy` is a struct) to primitive
fields. `style = :filename` yields prefixed names for [`scenario_filename`](@ref)
(`strategy => :ADMM`, `admm_ρ`, ...; `pf_ε` only under `:restricted_branch_flow`,
`pf_thesis_literal` only under `:convex_branch_flow`); `style = :record` yields the legacy flat
keys for [`result_to_dict`](@ref) (lowercase `:strategy`, `:ρ`, ..., `:pf`, `:pf_thesis_literal`,
`:pf_ε` always). Only the ACTIVE strategy's knobs appear in either style.
"""
function _scenario_identity(s::Scenario; style::Symbol)::Dict{Symbol, Any}
    style in (:filename, :record) || throw(
        ArgumentError(
            "_scenario_identity: style must be :filename or :record; got $(repr(style))",
        ),
    )
    d = Dict{Symbol, Any}(
        :name => s.name,
        :feeder => s.feeder,
        :seed => s.seed,
        :T => s.T,
        :population => s.population,
        :price => s.price,
        :allow_export => s.allow_export,
        :pf => s.pf,
    )
    if style === :filename
        s.pf === :restricted_branch_flow && (d[:pf_ε] = s.pf_ε)
        s.pf === :convex_branch_flow && (d[:pf_thesis_literal] = s.pf_thesis_literal)
        d[:strategy] = Symbol(nameof(typeof(s.strategy)))
    else
        d[:pf_thesis_literal] = s.pf_thesis_literal
        d[:pf_ε] = s.pf_ε
        d[:strategy] = _strategy_label(s.strategy)
    end
    for (k, v) in _strategy_knobs(s.strategy, style)
        d[k] = v
    end
    return d
end

"""
    scenario_filename(s::Scenario) -> String

Single source of truth for the JLD2 filename [`run_and_store`](@ref) saves `s` under.

DrWatson's `savename` silently DROPS struct-valued fields (`Scenario.strategy` is a struct), so
the name is built from the explicit flattened `Dict` of `_scenario_identity`
(`style = :filename`): `savename(dict, "jld2"; digits = 10)` (keys sorted alphabetically;
`digits = 10` keeps float knobs from colliding under display rounding; `run_and_store` adds
`safe = true` as defense-in-depth). Only the ACTIVE strategy's knobs appear
(`strategy=ADMM`, `admm_ρ=...`), which also keeps names well under the NAME_MAX ceiling.

For a `Stochastic` strategy with non-uniform `probabilities` (a `Vector{Float64}` that `savename`
drops) a `_p<digest>` component is folded in before `.jld2`: a deterministic, Julia-version-stable
FNV-1a over the raw `Float64` bytes ([`_stable_hex64`](@ref)) — a filename disambiguator, NOT a
security hash. Uniform vectors add nothing (they are determined by `stoch_S`).

NOTE: filename STRINGS were changed when the selector set was restructured (prefixed knob names, `strategy=`, `pf=`), orphaning
older `data/sims` artifacts (gitignored, never committed). The NAME_MAX = 255-byte guard is kept
(rarely hit now): an over-long name is truncated on a UTF-8 boundary and suffixed with
`_h<_stable_hex64(codeunits(full))>` (16-hex FNV-1a, stable across Julia versions); no information is lost because [`result_to_dict`](@ref) stamps every selector
inside the JLD2 itself.

Any caller that needs the path `run_and_store` will use MUST call this helper rather than
re-deriving a `savename` call.
"""
function scenario_filename(s::Scenario)
    full = savename(_scenario_identity(s; style = :filename), "jld2"; digits = 10)
    st = s.strategy
    if st isa Stochastic && !allequal(st.probabilities)
        digest = _stable_hex64(reinterpret(UInt8, st.probabilities))
        full = string(chop(full; tail = 5), "_p", digest, ".jld2")   # 5 = length(".jld2")
    end
    name_max = 255                    # Linux/most filesystems' hard basename byte ceiling.
    safesave_buffer = 10              # room for `safesave`'s own `_1`/`_2`/... suffix.
    hash_suffix_len = 2 + 16 + 5      # "_h" + 16 hex digits + ".jld2".
    target = name_max - safesave_buffer
    sizeof(full) <= target && return full
    # Fallback: truncated STEM (snapped to a UTF-8 boundary via `thisind`) plus a hash of the
    # COMPLETE descriptive string so prefix-sharing Scenarios never collide.
    stem_budget = target - hash_suffix_len
    stem_end = thisind(full, min(sizeof(full), stem_budget))
    stem = full[1:stem_end]
    return stem * "_h" * _stable_hex64(codeunits(full)) * ".jld2"
end

"""
    result_to_dict(res::ScenarioResult) -> Dict{Symbol,Any}

Build the Symbol-keyed provenance dict that [`run_and_store`](@ref) `@tagsave`s, from the same
flatten helper as [`scenario_filename`](@ref) (`style = :record`): the common selectors
(`name`, `feeder`, `seed`, `T`, `population`, `price`, `allow_export`), `:pf`,
`:pf_thesis_literal`, `:pf_ε`, lowercase `:strategy`, and the legacy flat knob keys of the
ACTIVE strategy only (`:ρ ... :μ` / `:mpc_*` / `:stoch_*`); plus `welfare`, `dadp`,
`exact_maxgap`, `iters`, `final_r`, `final_s`, `reactive_consensus_mode` (`missing` for
non-ADMM), `:julia_version = string(VERSION)`, for MPC `:regret`/`:steps`, and for Stochastic
`:welfare_gap`. Only primitives/arrays are stored — never strategy objects, `MpcTrace`,
NamedTuples or details structs — so the JLD2 loads without TSODSO types.

NOTE: `reactive_consensus_mode` is the RESOLVED `ReactiveMode` for
ADMM, stamped so the artifact is self-describing.
"""
function result_to_dict(res::ScenarioResult)
    d = _scenario_identity(res.scenario; style = :record)
    d[:welfare] = res.welfare
    d[:dadp] = res.dadp
    d[:exact_maxgap] = res.exact_maxgap
    d[:iters] = res.iters
    d[:final_r] = res.final_r
    d[:final_s] = res.final_s
    d[:reactive_consensus_mode] = res.reactive_consensus_mode
    d[:julia_version] = string(VERSION)
    det = res.details
    if det isa MPCDetails
        d[:regret] = det.regret
        d[:steps] = det.steps
    elseif det isa StochasticDetails
        d[:welfare_gap] = det.oos.welfare_gap
    end
    return d
end

"""
    run_and_store(s::Scenario; dir::AbstractString = datadir("sims")) -> ScenarioResult

Run `s` via [`run_scenario`](@ref) and `@tagsave` a per-run provenance dict to a JLD2 file
named `scenario_filename(s)` under `dir` (default `datadir("sims")`, gitignored).
The saved dict carries every field from [`result_to_dict`](@ref) PLUS `:gitcommit` (+
`:gitpatch` on a dirty tree) and `:script`, stamped by `@tagsave` itself (`storepatch = true`).

Takes `dir` as an EXPLICIT keyword so tests can pass `mktempdir()` and stay hermetic —
never rely on `datadir()` resolving under the test environment.
Returns the `ScenarioResult` (the same in-memory value `run_scenario` produced); the JLD2
write is a side effect, never re-loaded by this function.

NOTE: `savename`'s DEFAULT float formatting rounds `AbstractFloat` fields to
`sigdigits = 3`, which can collapse two `Scenario`s differing only in a sub-percent ADMM float
knob (`ρ`/`ε_abs`/`ε_rel`/`τ_ratio`/`μ`) onto the IDENTICAL filename — verified directly
against this repo's pinned DrWatson (2.19.1): `ρ = 100.1/100.2/100.4` all produced
`"...ρ=100.0..."` under the bare default. `digits = 10` makes the float component of the
filename round-trip losslessly (no more collisions from display rounding), **and** `safe = true` is passed so `@tagsave` routes through `safesave` (appends `_1`, `_2`, ... instead of
silently overwriting) as defense-in-depth against any RESIDUAL collision (e.g. two Scenarios
that are truly float-identical to 10 digits but differ in a field `default_allowed` excludes).
Together these close the "silently overwrites a prior run's JLD2" data-loss risk this function
previously had.

NOTE: `@tagsave`'s `gitpath` keyword defaults to `DrWatson.projectdir()`,
which resolves from the CURRENTLY ACTIVE project — under `Pkg.test()` that is a temporary
sandbox directory Pkg generates for the test run, NOT this package's actual git checkout, so
`gitdescribe` silently finds "not a Git repository" and `:gitcommit` is never stamped
(observed when running the provenance testitem through `Pkg.test()`).
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
