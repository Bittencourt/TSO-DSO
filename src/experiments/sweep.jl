# src/experiments/sweep.jl
#
# SEAM: run_sweep (dict_list) + collate_summary (diff-friendly CSV) (EXP-02).
# OWNER: plan 08-04 (this plan) fills the 08-01 comment-only stub.
#
# `run_sweep` builds `scenarios = [Scenario(; nt...) for nt in dict_list(params)]` (RESEARCH
# §Pattern 2 — a Vector-valued parameter expands the Cartesian product, a scalar stays fixed)
# and calls `run_and_store` (08-04 Task 1) on each into `dir`. `collate_summary` reads
# `collect_results(dir)` into a DataFrame, `select`s an EXPLICIT fixed column order, `sort!`s
# rows deterministically by the scenario key columns, and DROPS the machine-local absolute
# `:path` column (keeping `:gitcommit`) before `CSV.write` — all THREE diff-friendly rules are
# mandatory (RESEARCH §Pattern 3), so two collations of the same run set are byte-identical (no
# git churn). The committed summary lives under `results/sweeps/` (two-tier storage split, 08-01).

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

Expand `params` via `dict_list` (RESEARCH §Pattern 2 — Vector-valued entries expand the
Cartesian product, scalar entries stay fixed) into a `Scenario` per combination, then
`run_and_store` each into `dir` (default `datadir("sims")`, gitignored). Returns the
`Vector{ScenarioResult}` in `dict_list` order. `dir` is an explicit keyword so tests pass
`mktempdir()` and stay hermetic (RESEARCH Pitfall 6).
"""
function run_sweep(params::Dict; dir::AbstractString = datadir("sims"))
    scenarios = [Scenario(; nt...) for nt in dict_list(params)]
    return [run_and_store(s; dir = dir) for s in scenarios]
end

"""
    collate_summary(dir::AbstractString, csvpath::AbstractString) -> DataFrame

Collate every per-run JLD2 artifact under `dir` (written by [`run_and_store`](@ref)/
[`run_sweep`](@ref)) into ONE diff-friendly, committed CSV at `csvpath` (RESEARCH §Pattern 3).
All THREE diff-friendly rules are mandatory:

1. **Fixed column order** — an EXPLICIT `select` on
   `[:name, :feeder, :strategy, :seed, :T, :welfare, :exact_maxgap, :iters, :final_r,
   :final_s, :gitcommit]`, intersected with the columns actually present (tolerant of a
   `:centralized`-only sweep where `:iters`/`:final_r`/`:final_s` are still columns of
   `missing`, since they were populated as `missing` per-run — the intersect guard exists
   for robustness against any future column-set drift, not for these expected columns).
2. **Deterministic row order** — `sort!` by the scenario key columns
   `[:feeder, :strategy, :seed]`.
3. **Drop the machine-local `:path` column** — `collect_results` adds an absolute,
   non-reproducible path; keeping it would make every collation on a different checkout
   churn the committed CSV. `:gitcommit` IS kept (it is the provenance anchor, not a
   machine-local path) — `collect_results`' OWN default `black_list` excludes `:gitcommit`
   alongside `:gitpatch`/`:script`, so it is explicitly restored here by overriding
   `black_list` to only `["gitpatch", "script"]` (verified live: `collect_results`'
   `to_data_row` keys its `black_list` by the ACTUAL on-disk key type — `String`, since
   JLD2/FileIO always round-trips dict keys as strings, RESEARCH-adjacent to Pitfall 2 —
   so the override must be `String`, not `Symbol`, entries).

Two `collate_summary` calls over the SAME run directory produce byte-identical CSV files
(no git churn) because all three rules are deterministic given the same on-disk artifacts.
"""
function collate_summary(dir::AbstractString, csvpath::AbstractString)
    df = DrWatson.collect_results(dir; black_list = ["gitpatch", "script"])

    keep = [
        :name, :feeder, :strategy, :seed, :T,
        :welfare, :exact_maxgap, :iters, :final_r, :final_s, :gitcommit,
    ]
    present = Symbol.(names(df))
    df = select(df, intersect(keep, present))   # RULE 1: fixed, explicit column order

    sort!(df, [:feeder, :strategy, :seed])      # RULE 2: deterministic row order

    # RULE 3: :path is never in `keep`, so `select` above already dropped it.
    CSV.write(csvpath, df)
    return df
end

export run_sweep, collate_summary
