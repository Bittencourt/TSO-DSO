# src/experiments/sweep.jl
#
# SEAM: run_sweep (dict_list) + collate_summary (diff-friendly CSV) (EXP-02).
# OWNER: plan 08-01 (this plan) wires this STUB into the include graph; plan 08-04 FILLS it.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 4 (depends on 08-04 Task 1's run_and_store, same plan). Plan 08-04 fills:
#
#     run_sweep(params::Dict; dir::AbstractString = datadir("sims")) -> Vector{ScenarioResult}
#     collate_summary(dir::AbstractString, csvpath::AbstractString) -> DataFrame
#
# `run_sweep` builds `scenarios = [Scenario(; nt...) for nt in dict_list(params)]` (RESEARCH
# §Pattern 2 — a Vector-valued parameter expands the Cartesian product, a scalar stays fixed)
# and calls `run_and_store` on each. `collate_summary` reads `collect_results(dir)` into a
# DataFrame, `select`s an EXPLICIT fixed column order, `sort!`s rows deterministically by the
# scenario key columns, and DROPS the machine-local absolute `:path` column (keeping
# `:gitcommit`) before `CSV.write` — all THREE diff-friendly rules are mandatory (RESEARCH
# §Pattern 3), so two collations of the same run set are byte-identical (no git churn). The
# committed summary lives under `results/sweeps/` (two-tier storage split, 08-01).
#
# Filled by plan 08-04 (EXP-02 — RESEARCH §Pattern 2 dict_list sweep / §Pattern 3 two-tier
# storage + diff-friendly rules / §Don't Hand-Roll).
