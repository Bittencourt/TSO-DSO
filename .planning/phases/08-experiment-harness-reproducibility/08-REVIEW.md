---
phase: 08-experiment-harness-reproducibility
reviewed: 2026-07-19T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - src/experiments/run.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - test/test_experiments.jl
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: resolved
resolution:
  fixed: [CR-01, CR-02, WR-01, WR-03, WR-04, WR-05, WR-06]
  deferred: [WR-02]
  note: "WR-06 fixed in 64d935a (single-sourced scenario_filename). WR-02 (sub_seed Base.hash cross-version stability) deferred: mechanical replacement caused a numerical regression requiring researcher ρ/τ re-tuning — empirically stable on Julia 1.10/1.11/1.12 today. Tracked in deferred-items.md. Full suite: 1933 pass / 0 fail / 0 error / 2 broken (pre-existing)."
---

# Phase 08: Code Review Report (Iteration 3 — Resolved)

**Reviewed:** 2026-07-19
**Depth:** standard
**Files Reviewed:** 6
**Status:** resolved (all Critical + Warning fixed; WR-02 deferred to researcher)

## Summary

This is a re-review of fixes applied against the prior iteration-1 findings (2 Critical + 5
Warning + 1 Info). All six fixes were verified both by static line-by-line inspection against
the actual pinned DrWatson 2.19.1 source (`saving_files.jl`/`naming.jl`) and empirically by
running the full Phase-8 `@testitem` suite (`test/test_experiments.jl`, 12 items) plus the
whole package test suite end-to-end: **all 54 test items passed**, including every INFRA-04
same-seed/seed-sensitivity gate for both `:centralized` and `:admm` strategies, and the
provenance/tagsave roundtrip.

Verified correct, no regression:
- **CR-01** (`savename` collision / silent overwrite): `store.jl` now calls
  `savename(s, "jld2"; digits = 10)` and passes `safe = true` to `@tagsave`. Confirmed against
  DrWatson's `naming.jl` that `digits` overrides the default `sigdigits = 3` (line 98:
  `sigdigits = digits === nothing ? sigdigits : nothing`), and against `saving_files.jl` that
  `tagsave`/`@tagsave` accept `safe::Bool` and route through `safesave` (renames prior file to
  `_#1`/`_#2` instead of overwriting). Empirically re-verified `ρ=100.1/100.2/100.4` now produce
  distinct filenames under `digits=10`.
- **CR-02** (provenance omits ADMM knobs): `result_to_dict` now builds from
  `struct2dict(s)` (confirmed via DrWatson `saving_tools.jl` that this captures every
  `fieldnames(typeof(s))`, i.e. all 14 `Scenario` fields including `ρ`/`ε_abs`/`ε_rel`/
  `maxiter`/`τ_ratio`/`μ`/`allow_export`), and `sweep.jl`'s `keep`/`selector_cols` lists were
  extended to match. Verified the "INFRA-04 provenance tagsave" and "EXP-02 sweep diff-friendly"
  test items pass.
- **WR-01** (unvalidated ADMM float knobs): `Scenario`'s constructor now throws
  `ArgumentError` for `ρ <= 0`, `ε_abs <= 0 || ε_rel <= 0`, `τ_ratio <= 0 || μ <= 0`. All
  defaults remain valid (no regression to existing callers); confirmed via the passing test
  suite.
- **WR-03** (feeder-detection-by-bus-count heuristic): `_load_buses`/`build_population` now
  take an explicit `feeder_sym::Symbol` and dispatch on it directly. Confirmed the only call
  site (`run.jl:95-97`) passes `s.feeder` correctly, and no other caller of these two
  (underscore-private/module-internal) functions exists anywhere in `src/`.
- **WR-04** (incomplete sort key in `collate_summary`): `selector_cols` now lists all 14
  `Scenario` selector fields; `intersect(selector_cols, present)` preserves `selector_cols`'
  order and remains well-formed against the post-`select` `df` (every name in `selector_cols`
  that was `present` in the pre-select `df` is, by construction, also a member of `keep`, so it
  survives the `select`). No aliasing/ordering bug found.
- **WR-05** (no `:admm` reproducibility test): two new test items
  (`"INFRA-04 same-seed repro admm"`, `"INFRA-04 seed sensitivity admm"`) were added and pass.
- **WR-02** (`Base.hash`-based `sub_seed`) — confirmed untouched, as expected; this is the
  documented, intentional deferral (replacing it caused a numerical regression requiring
  researcher re-tuning). Not re-flagged.

## Narrative Findings (AI reviewer)

## Warnings

### WR-06: `scripts/run_scenario.jl`'s printed save path no longer matches the actual saved filename (fix-induced regression)

**File:** `scripts/run_scenario.jl:29` (not in this iteration's file list, but directly
downstream of the `store.jl` CR-01 fix and broken by it)

**Issue:** The CR-01 fix correctly changed `store.jl`'s actual on-disk save call to
`savename(s, "jld2"; digits = 10)`. However, `scripts/run_scenario.jl` — the researcher-facing
demo entry point for this exact API — still prints the OLD, bare-default filename:

```julia
println("stored under   = ", datadir("sims", savename(s, "jld2")))
```

Before the fix, this was consistent with what `run_and_store` actually saved (both used the
same bare `savename(s, "jld2")` call, so the printed path always matched the real file, even
though — per the CR-01 bug — that shared filename could silently collide across distinguishable
`Scenario`s). After the fix, `store.jl` and this script's println have DIVERGED: for any
`Scenario` whose float knobs (`ρ`/`ε_abs`/`ε_rel`/`τ_ratio`/`μ`) differ from another only below
DrWatson's default `sigdigits = 3` rounding threshold — precisely the scenario class CR-01 was
created to fix — the file is now correctly saved under the `digits=10` filename, but this
script prints a DIFFERENT (bare, rounded) filename that does not exist on disk. A researcher
following this script's own printed output to locate their result (e.g. `wload(printed_path)`)
will get a `SystemError`/`ArgumentError: no such file`, or worse, silently load a DIFFERENT,
unrelated prior run that happens to collide on the bare `savename`. This is a genuinely new
defect introduced as a side effect of applying the CR-01 fix in only one of the two call sites
that compute a `Scenario`'s save filename.

**Fix:** Make the filename computation single-sourced so it cannot drift again — either export
a small helper from `store.jl` and use it in both places:

```julia
# store.jl
scenario_filename(s::Scenario) = savename(s, "jld2"; digits = 10)
export scenario_filename
```

```julia
# scripts/run_scenario.jl
println("stored under   = ", datadir("sims", TSODSO.scenario_filename(s)))
```

or, at minimum, add `; digits = 10` to the script's println to match `store.jl`'s actual save
call:

```julia
println("stored under   = ", datadir("sims", savename(s, "jld2"; digits = 10)))
```

---

_Reviewed: 2026-07-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
