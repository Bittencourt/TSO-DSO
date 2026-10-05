# src/experiments/sweep.jl
#
# SEAM: run_sweep (dict_list) + collate_summary (diff-friendly CSV).
#
# `run_sweep` builds `scenarios = [Scenario(; nt...) for nt in dict_list(params)]` (a Vector-valued parameter expands the Cartesian product, a scalar stays fixed)
# and calls `run_and_store` on each into `dir`. `collate_summary` reads
# `collect_results(dir)` into a DataFrame, `select`s an EXPLICIT fixed column order, `sort!`s
# rows deterministically by the scenario key columns, and DROPS the machine-local absolute
# `:path` column (keeping `:gitcommit`) before `CSV.write` — all THREE diff-friendly rules are
# mandatory, so two collations of the same run set are bit-for-bit identical (no
# git churn). The committed summary lives under `results/sweeps/` (two-tier storage split).

import DrWatson
using DrWatson: dict_list, datadir
using DataFrames: DataFrame, select, sort!, names
using CSV: CSV

# NOTE: `DrWatson.collect_results` is NOT a top-level export — it is only defined once
# DrWatson's `Requires`-gated `@require DataFrames begin ... end` block fires (DrWatson does
# not yet use native Julia package extensions for this). A restricted `using DrWatson:
# collect_results` at file-load time can race that gate during precompilation (observed: a
# "was undeclared at import time" precompile warning). Calling it fully-qualified as
# `DrWatson.collect_results` INSIDE `collate_summary` (i.e. at runtime, well after both
# DrWatson and DataFrames have loaded) sidesteps the race entirely.

"""
    run_sweep(params::Dict; dir::AbstractString = datadir("sims")) -> Vector{ScenarioResult}

Expand `params` via `dict_list` (Vector-valued entries expand the
Cartesian product, scalar entries stay fixed) into a `Scenario` per combination, then
`run_and_store` each into `dir` (default `datadir("sims")`, gitignored). Returns the
`Vector{ScenarioResult}` in `dict_list` order. `dir` is an explicit keyword so tests pass
`mktempdir()` and stay hermetic. A sweep Dict mixing strategies must not
carry knobs foreign to ANY listed strategy symbol (`ArgumentError` by design).
"""
function run_sweep(params::Dict; dir::AbstractString = datadir("sims"))
    scenarios = [Scenario(; nt...) for nt in dict_list(params)]
    return [run_and_store(s; dir = dir) for s in scenarios]
end

"""
    collate_summary(dir::AbstractString, csvpath::AbstractString) -> DataFrame

Collate every per-run JLD2 artifact under `dir` (written by [`run_and_store`](@ref)/
[`run_sweep`](@ref)) into ONE diff-friendly, committed CSV at `csvpath`.
All THREE diff-friendly rules are mandatory:

 1. **Fixed column order** — an EXPLICIT `select` on
    `[:name, :feeder, :strategy, :seed, :T, :price, :population, :allow_export, :ρ, :ε_abs, :ε_rel, :maxiter, :τ_ratio, :μ, :welfare, :exact_maxgap, :iters, :final_r, :final_s, :gitcommit]` (the ADMM tuning knobs + `:price`/`:population`/`:allow_export` are
    now kept alongside the result columns, so the collated CSV — like the per-run JLD2, since
    `result_to_dict` persists `struct2dict(s)` — is self-describing without re-loading the
    `Scenario` even for a non-default `:admm` sweep), intersected with the columns actually
    present (tolerant of a `:centralized`-only sweep where `:iters`/`:final_r`/`:final_s` are
    still columns of `missing`, since they were populated as `missing` per-run — the intersect
    guard exists for robustness against any future column-set drift, not for these expected
    columns).
 2. **Deterministic row order** — `sort!` by EVERY `Scenario` selector column present in `df`
    (`[:feeder, :strategy, :seed, :T, :name, :price, :population, :allow_export, :ρ, :ε_abs, :ε_rel, :maxiter, :τ_ratio, :μ]`, intersected with `present`). Sorting by only
    `[:feeder, :strategy, :seed]` left `:T`/`:name`/`:price`/`:population`/the ADMM knobs
    unsorted, so any sweep holding `(feeder, strategy, seed)` fixed while varying one of those
    (e.g. an ADMM-knob sensitivity sweep, or a multi-horizon `T` sweep) produced tied sort keys
    whose row order then fell back to `collect_results`' `readdir`-derived scan order — not
    guaranteed stable across filesystems/OSes/re-runs, silently breaking the "bit-for-bit identical, no
    git churn" guarantee for exactly the sweep shapes this harness targets. Sorting by every
    selector column removes every possible tie (two rows tie here only if their `Scenario`s are
    themselves selector-identical, i.e. re-runs of the literal same scenario).
 3. **Drop the machine-local `:path` column** — `collect_results` adds an absolute,
    non-reproducible path; keeping it would make every collation on a different checkout
    churn the committed CSV. `:gitcommit` IS kept (it is the provenance anchor, not a
    machine-local path) — `collect_results`' OWN default `black_list` excludes `:gitcommit`
    alongside `:gitpatch`/`:script`, so it is explicitly restored here by overriding
    `black_list` to only `["gitpatch", "script"]` (verified live: `collect_results`'
    `to_data_row` keys its `black_list` by the ACTUAL on-disk key type — `String`, since
    JLD2/FileIO always round-trips dict keys as strings, as the stored-key type shows,
    so the override must be `String`, not `Symbol`, entries).

In a mixed-strategy sweep, knob keys absent from a run's JLD2 (inactive strategy) surface as
`missing` cells; `sort!` places `missing` last deterministically. `:stoch_probabilities` is
deliberately NOT a column (a vector is not CSV-friendly; its digest lives in the filename).

Two `collate_summary` calls over the SAME run directory produce bit-for-bit identical CSV files
(no git churn) because all three rules are deterministic given the same on-disk artifacts.
"""
function collate_summary(dir::AbstractString, csvpath::AbstractString)
    df = DrWatson.collect_results(dir; black_list = ["gitpatch", "script"])

    keep = [
        :name,
        :feeder,
        :strategy,
        :seed,
        :T,
        :price,
        :population,
        :allow_export,
        :pf,
        :pf_thesis_literal,
        :pf_ε,
        :ρ,
        :ε_abs,
        :ε_rel,
        :maxiter,
        :τ_ratio,
        :μ,
        :mpc_H,
        :mpc_step,
        :mpc_terminal_soc,
        :mpc_forecast_error,
        :stoch_S,
        :stoch_H_oos,
        :welfare,
        :exact_maxgap,
        :iters,
        :final_r,
        :final_s,
        :gitcommit,
    ]
    present = Symbol.(names(df))
    df = select(df, intersect(keep, present))   # RULE 1: fixed, explicit column order

    # RULE 2: deterministic row order — sort by every Scenario selector column present,
    # not just [:feeder, :strategy, :seed], so no sweep shape can tie on the sort key and
    # fall back to a non-deterministic filesystem scan order.
    selector_cols = [
        :feeder,
        :strategy,
        :seed,
        :T,
        :name,
        :price,
        :population,
        :allow_export,
        :pf,
        :pf_thesis_literal,
        :pf_ε,
        :ρ,
        :ε_abs,
        :ε_rel,
        :maxiter,
        :τ_ratio,
        :μ,
        :mpc_H,
        :mpc_step,
        :mpc_terminal_soc,
        :mpc_forecast_error,
        :stoch_S,
        :stoch_H_oos,
    ]
    sort!(df, intersect(selector_cols, present))

    # RULE 3: :path is never in `keep`, so `select` above already dropped it.
    CSV.write(csvpath, df)
    return df
end

export run_sweep, collate_summary
