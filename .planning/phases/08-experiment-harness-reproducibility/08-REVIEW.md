---
phase: 08-experiment-harness-reproducibility
reviewed: 2026-07-19T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - src/experiments/run.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - scripts/run_scenario.jl
  - scripts/sweep.jl
  - test/test_experiments.jl
  - test/fixtures_phase8.jl
findings:
  critical: 2
  warning: 5
  info: 1
  total: 8
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-07-19
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

The Phase-8 experiment harness (`Scenario`, `materialize.jl`, `run_scenario`, `store.jl`,
`sweep.jl`) is well-documented, the `Scenario` struct is genuinely immutable and never mutated,
the `@kwdef` + custom validating inner-constructor pattern was verified to work correctly
end-to-end (empirically tested), and the enum-style selector validation (feeder/strategy/
price/population + T/seed/maxiter bounds) is sound. However, two claims that are foundational
to the phase's own stated "hard requirement" (INFRA-04, bit-for-bit reproducibility +
provenance) do not hold under inspection, and were confirmed empirically against the actual
DrWatson 2.19.1 install in this environment:

1. The header comment in `Scenario.jl` claims "two Scenarios differing in any selector never
   collide" in `savename`. This is false for any pair of `Scenario`s that differ only in a
   `Float64` field (e.g. `ρ`, `ε_abs`, `ε_rel`, `τ_ratio`, `μ`) by less than DrWatson's default
   3-significant-digit `savename` rounding — demonstrated below with `ρ = 100.1/100.2/100.4`
   all producing the identical `savename`. Since `run_and_store`/`@tagsave` do not use
   `safesave`, a collision silently **overwrites** the earlier run's JLD2 file — a real data-loss
   risk for any ADMM-knob sensitivity sweep.
2. `result_to_dict`/`collate_summary` silently drop the ADMM tuning knobs (`ρ`, `ε_abs`,
   `ε_rel`, `maxiter`, `τ_ratio`, `μ`) and `allow_export` from the persisted provenance
   dict/CSV, while `result_to_dict`'s own docstring claims the artifact is "self-describing
   without re-loading the Scenario." For any ADMM run with non-default knobs, it is not.

The remaining findings are lower-severity design/robustness gaps: no bounds-checking on the
ADMM float knobs at `Scenario` construction, a feeder-type-detection heuristic that silently
mis-scales for any future feeder sharing IEEE-123's bus count, an incomplete sort key in
`collate_summary` that can reintroduce filesystem-order non-determinism, reliance on
`Base.hash` (explicitly documented as unstable across process/version) for the
reproducibility-critical `sub_seed`, and a test-coverage gap where the harness's flagship
same-seed/seed-sensitivity reproducibility tests never exercise the `:admm` strategy.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: `savename` collisions on ADMM float knobs silently overwrite prior run artifacts

**File:** `src/experiments/Scenario.jl:9-12` (invariant claim), `src/experiments/store.jl:75-83`
(`run_and_store`, no collision guard)

**Issue:** The design comment at the top of `Scenario.jl` states:

> every field already sits inside DrWatson's `default_allowed` filter, so nothing is silently
> dropped from the generated filename and **two Scenarios differing in any selector never
> collide**.

This is false. DrWatson's `savename` rounds `AbstractFloat` fields to `sigdigits = 3` by
default (`valtostring`/`roundval` in `DrWatson.naming`), and `Scenario` has five `Float64`
knobs (`ρ`, `ε_abs`, `ε_rel`, `τ_ratio`, `μ`) that are exactly the kind of value a researcher
sweeps at sub-percent resolution around a magnitude like `ρ`'s default `100.0`. Verified
directly against this repo's pinned DrWatson (2.19.1):

```julia
julia> using DrWatson
julia> struct Toy; name::String; ρ::Float64; end
julia> savename(Toy("x", 100.1))
"name=x_ρ=100.0"
julia> savename(Toy("x", 100.2))
"name=x_ρ=100.0"
julia> savename(Toy("x", 100.4))
"name=x_ρ=100.0"
```

Three distinguishable `ρ` values collapse to the identical `savename`. Because
`run_and_store` (`store.jl:78-81`) calls `@tagsave(joinpath(dir, savename(s, "jld2")), dict;
storepatch = true, gitpath = ...)` **without** `safe = true` (i.e. never routes through
`safesave`), a second run whose `Scenario` collides on `savename` **silently overwrites** the
first run's JLD2 file — the first run's welfare/DADP/provenance is permanently lost with no
warning, no error, and no indication in `run_sweep`'s return value that anything was lost.
This directly threatens INFRA-04 (the project's stated hard reproducibility/provenance
requirement) for the exact workflow the codebase's own comments describe as expected (ADMM
knob sensitivity sweeps — see the `ρ` calibration discussion in `Scenario.jl:59-65`).

**Fix:** Do not rely on `savename`'s lossy default float formatting as a uniqueness key for
on-disk storage. Either:
- Use a collision-safe filename, e.g. `savename(s, "jld2"; digits = 10)` (or an explicit
  `val_to_string` override) so floats round-trip losslessly into the filename, **and**
  additionally pass `safe = true` to `@tagsave` (routes through `safesave`, which never
  overwrites, appending `_1`, `_2`, ... instead), or
- Hash the full `struct2dict(s)` (not the display-rounded `savename`) into the filename, e.g.
  `savename(s, "jld2"; digits = 10)` plus a content hash suffix, so no two distinguishable
  `Scenario`s can ever collide on disk regardless of float magnitude.

```julia
@tagsave(
    joinpath(dir, savename(s, "jld2"; digits = 10)), dict;
    storepatch = true, gitpath = pkgdir(@__MODULE__), safe = true,
)
```

### CR-02: Persisted provenance omits ADMM tuning knobs — contradicts the "self-describing" claim

**File:** `src/experiments/store.jl:33-51` (`result_to_dict`), `src/experiments/sweep.jl:73-76`
(`collate_summary`'s `keep` column list)

**Issue:** `result_to_dict`'s docstring states the dict includes "the scenario's own selectors
(`name`, `feeder`, `strategy`, `seed`, `T`, `price`, `population`) so the artifact is
**self-describing without re-loading the Scenario**." The implementation, however, omits
`allow_export`, `ρ`, `ε_abs`, `ε_rel`, `maxiter`, `τ_ratio`, and `μ` entirely. For any
`:admm` run that overrides even one of these (a completely ordinary research workflow — the
whole point of exposing them as `Scenario` fields, per `Scenario.jl:56-65`'s own commentary
on ADMM knob tuning), the persisted JLD2 dict and the collated CSV (`collate_summary`'s
`keep` list has the same gap, plus also drops `price`/`population`) cannot reconstruct which
configuration actually produced a given `welfare`/`dadp`/`exact_maxgap` value. Two ADMM runs
that differ only in `ρ` are indistinguishable in the stored artifact and in the collated
summary (the one place that *could* disambiguate them — the on-disk filename via `savename`
— is explicitly the machine-local `:path` column that `collate_summary` deliberately drops).
This is a genuine provenance/reproducibility gap against the phase's stated hard requirement
(INFRA-04), not merely a documentation inaccuracy.

**Fix:** Persist every `Scenario` selector, not a hand-picked subset — e.g. replace the
hand-built `Dict` in `result_to_dict` with `merge(struct2dict(res.scenario), Dict(:welfare =>
..., :dadp => ..., ...))`, and extend `collate_summary`'s `keep` list to include `:ρ`,
`:ε_abs`, `:ε_rel`, `:maxiter`, `:τ_ratio`, `:μ`, `:allow_export`, `:price`, `:population`.

```julia
function result_to_dict(res::ScenarioResult)
    s = res.scenario
    d = struct2dict(s)   # ALL Scenario selectors, not a hand-picked subset
    d[:welfare] = res.welfare
    d[:dadp] = res.dadp
    d[:exact_maxgap] = res.exact_maxgap
    d[:iters] = res.iters
    d[:final_r] = res.final_r
    d[:final_s] = res.final_s
    d[:julia_version] = string(VERSION)
    return d
end
```

## Warnings

### WR-01: ADMM float knobs (`ρ`, `ε_abs`, `ε_rel`, `τ_ratio`, `μ`) are never validated at construction

**File:** `src/experiments/Scenario.jl:87-146`

**Issue:** The constructor's own docstring (`Scenario.jl:67-69`) and inline comment
(`Scenario.jl:103-105`, threat T-08-05) both claim "a `Scenario` must never silently
underdetermine its run" — every selector is "checked LOUDLY." In practice only `feeder`,
`strategy`, `price`, `population` (enum membership) and `T`/`seed`/`maxiter` (lower bounds)
are checked. The five ADMM numeric knobs — `ρ`, `ε_abs`, `ε_rel`, `τ_ratio`, `μ` — have no
range validation at all: `Scenario(; ρ = -5.0, ε_abs = -1.0, μ = 0.0)` constructs without
error, and would only fail (or silently misbehave — e.g. non-convergence, `NaN` propagation,
or a `maxiter`-bounded infinite-seeming loop) much later, deep inside `solve_admm`, far from
the point where the researcher made the mistake.

**Fix:** Add the same loud-`throw` pattern already used for `T`/`seed`/`maxiter`:

```julia
if ρ <= 0
    throw(ArgumentError("Scenario: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
end
if ε_abs <= 0 || ε_rel <= 0
    throw(ArgumentError("Scenario: ε_abs/ε_rel must be > 0; got ε_abs=$ε_abs, ε_rel=$ε_rel"))
end
if τ_ratio <= 0 || μ <= 0
    throw(ArgumentError("Scenario: τ_ratio/μ must be > 0; got τ_ratio=$τ_ratio, μ=$μ"))
end
```

### WR-02: `sub_seed` relies on `Base.hash`, which is not guaranteed stable across processes/versions

**File:** `src/experiments/materialize.jl:25`

**Issue:** `sub_seed(master, tag) = Int(hash((master, tag)) % typemax(UInt32))` is the sole
mechanism deriving every reproducibility-critical sub-stream (`:profiles`, `:population`).
`Base.hash`'s own docstring explicitly disclaims the exact guarantee this code depends on:
*"The hash value may change when a new Julia process is started."* This repo's own CLAUDE.md
mandates CI across Julia 1.10 (LTS) + 1.11 + nightly. Empirically, `hash((1, :profiles))`
happens to agree across the 1.10.11 / 1.11.9 / 1.12.5 toolchains installed in this
environment — but that agreement is an implementation detail, not a documented contract.
INFRA-04 is described as a hard, long-lived reproducibility requirement (the project is a
multi-year PhD research bench); a future Julia point release that changes the `hash` mixing
function for `Tuple{Int,Symbol}` (Julia has changed its hash algorithm across versions before)
would silently change every derived seed, and hence every stored experiment result, with
**no existing test able to detect it** — the current reproducibility tests only ever compare
two `run_scenario` calls within the same process/version.

**Fix:** Replace `Base.hash` with a project-owned, explicitly-specified, versioned mixing
function (e.g. a fixed SplitMix64/FNV-1a-style integer hash over `(master, Int(tag_id))`)
that this package controls and can pin/test independently of core Julia's hash implementation.

### WR-03: Feeder-type detection by bus count is fragile and fails silently for future feeders

**File:** `src/experiments/materialize.jl:129-134` (`_load_buses`), `materialize.jl:193-197`
(`build_population`)

**Issue:** Both functions distinguish "is this the IEEE-123 feeder" by comparing
`length(feeder.buses)` (or `N`) against `length(ieee123_relabel_map())`, rather than
dispatching on the already-known, already-validated `Scenario.feeder::Symbol` selector (which
`build_feeder` consumed to build this very `feeder` object a few lines earlier in
`run_scenario`). If a future feeder fixture (any new entry added to
`SCENARIO_VALID_FEEDERS`) happens to share IEEE-123's bus count, `_load_buses` silently
returns the wrong load/transit split and `build_population` silently applies the wrong
residential per-unit scale (`_IEEE123_*` vs `_IEEE13_*`) — with no `ArgumentError`, no
warning, just a quietly wrong (but numerically plausible) population.

**Fix:** Thread the `Symbol` selector (or the `Feeder` type/tag) through instead of
re-deriving it from an incidental structural property:

```julia
function _load_buses(feeder, feeder_sym::Symbol)
    return feeder_sym === :ieee123 ? ieee123_load_nodes() :
           [b.id for b in feeder.buses if !b.is_root]
end
```

### WR-04: `collate_summary`'s determinism claim is incomplete — sort key omits several varying fields

**File:** `src/experiments/sweep.jl:70-85`

**Issue:** The docstring states the 3 diff-friendly rules are "mandatory," including
"deterministic row order" via `sort!(df, [:feeder, :strategy, :seed])`. But `keep` (and hence
any future sweep) also varies `:T`, `:name`, `:price`, `:population`, and (per CR-02) the
ADMM knobs — none of which are part of the sort key. Any sweep that holds
`(feeder, strategy, seed)` fixed while varying one of those (e.g. an ADMM-knob sensitivity
sweep, or a multi-horizon `T` sweep) produces tied sort keys; row order among tied rows then
falls back to `collect_results`' underlying scan order (`readdir`-derived), which is not
guaranteed stable across filesystems, operating systems, or even repeated runs on the same
machine if files are rewritten. This silently breaks the "two collations produce byte-
identical CSVs, no git churn" guarantee for exactly the sweep shapes the harness is built to
support.

**Fix:** Extend the sort key to every column that can vary within a sweep and is present in
`df`, e.g. `sort!(df, intersect([:feeder, :strategy, :seed, :T, :name], present))`, or safer,
sort by literally every `keep` column before dropping any.

### WR-05: No test exercises `:admm`-strategy bit-for-bit reproducibility

**File:** `test/test_experiments.jl:134-165` (`"INFRA-04 same-seed repro"`,
`"INFRA-04 seed sensitivity"`)

**Issue:** Both `INFRA-04`-tagged reproducibility test items hard-code
`strategy = :centralized`. The `:admm` path is the iterative, floating-point-order-sensitive
strategy (adaptive-ρ residual comparisons, iteration-count-dependent convergence checks) and
is exactly where non-determinism (thread-pool/BLAS ordering, convergence-tolerance-driven
branch decisions) is most likely to leak in. `run.jl`'s own docstring asserts bit-for-bit
identity holds for `:admm` too ("two calls with the SAME `Scenario` ... return `==`-identical
... INFRA-04"), but nothing in the test suite verifies it for that branch — the only
`:admm`-strategy test (`"EXP-01 scenario admm"`) calls `run_scenario` once and never compares
two calls.

**Fix:** Add an `:admm` variant of the same-seed/seed-sensitivity test items, mirroring the
existing `:centralized` ones:

```julia
s = TSODSO.Scenario(; kw..., strategy = :admm)
r1 = TSODSO.run_scenario(s)
r2 = TSODSO.run_scenario(s)
@test r1.welfare == r2.welfare && r1.dadp == r2.dadp && r1.iters == r2.iters
```

## Info

### IN-01: Hardcoded `24` duplicates the length of `_TEMPERATURE_PROFILE_24H`

**File:** `src/experiments/materialize.jl:118`

**Issue:** `_temperature_profile(T::Int) = Float64[_TEMPERATURE_PROFILE_24H[mod1(t, 24)] for t
in 1:T]` hardcodes the literal `24` instead of `length(_TEMPERATURE_PROFILE_24H)`. If the
pinned array's length is ever edited (e.g. a future finer-grained horizon), this call site
silently desyncs from the actual array length.

**Fix:** `mod1(t, length(_TEMPERATURE_PROFILE_24H))` (matches the pattern already used in
`build_price`'s `mod1(t, length(base))`, one line up in the same file's sibling function).

---

_Reviewed: 2026-07-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
