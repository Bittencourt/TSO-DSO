---
phase: 08-experiment-harness-reproducibility
verified: 2026-07-19T22:30:00Z
status: passed
score: 3/3 must-haves verified
overrides_applied: 0
---

# Phase 8: Experiment Harness & Reproducibility Verification Report

**Phase Goal:** Make experiments first-class — a researcher declares a scenario, runs it
end-to-end with either solve strategy, sweeps parameters, and every run records its
inputs/config/environment so results regenerate bit-for-bit on the open-source
(Clarabel/HiGHS/Ipopt) solver path.
**Verified:** 2026-07-19T22:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

**Note on ROADMAP `mode` field:** `gsd-sdk query roadmap.get-phase 8` reports `"mode": "mvp"`,
but the phase goal text does not match the required User Story shape (`As a ..., I want to
..., so that ...`) — `user-story.validate` returns `valid: false`. The phase's own planning
artifacts (4 `type: execute` PLAN.md files with full `must_haves`/`artifacts`/`key_links`
frontmatter, not a single mvp-phase plan) and the orchestrator's own verification brief (3
enumerated, testable success criteria) are unambiguously standard-mode phase artifacts. This
verification proceeds in standard goal-backward mode per the orchestrator's brief; the `mode:
mvp` tag on ROADMAP.md phase 8 appears to be stale/mistaggged metadata, not a live MVP-mode
phase. This is an informational note, not a gap — it does not affect the substance of the
verification below.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A researcher defines a scenario declaratively (feeder + devices + price profile + config) and runs it end-to-end with either the centralized or ADMM solve strategy | VERIFIED | `Scenario` (src/experiments/Scenario.jl) is an immutable `@kwdef` struct of primitive selectors only (feeder/strategy/seed/T/population/price/config knobs), validated at construction (throws `ArgumentError` on unknown selectors). `run_scenario(s)` (src/experiments/run.jl) dispatches `:centralized`→`solve_welfare`+`extract_dlmp` and `:admm`→`solve_admm`, normalizing both to a comparable node×T `ScenarioResult`. Live-executed both strategies against IEEE-13 during this verification (see Behavioral Spot-Checks) — both returned real welfare/dadp/exact_maxgap values. |
| 2 | Parameter sweeps over scenarios run and store results in a flat, versioned, diff-friendly format | VERIFIED | `run_sweep(params; dir)` (src/experiments/sweep.jl) expands a `dict_list` (Vector-valued params) into N `Scenario`s and stores each; `collate_summary(dir, csvpath)` collates into a CSV with an explicit fixed column order, deterministic `sort!` by every selector column, and the machine-local `:path` column dropped. Live-executed a 2-seed sweep + two independent collations during this verification: byte-identical CSV output confirmed, header contains no `path` token. |
| 3 | Every run records its inputs, config, and environment (seed logged) so results regenerate bit-for-bit on the open-source (Clarabel/HiGHS/Ipopt) solver path | VERIFIED | `run_and_store` (src/experiments/store.jl) `@tagsave`s a per-run JLD2 (gitignored, under `data/sims/`) stamped with `:gitcommit`/`:gitpatch` (via `@tagsave storepatch=true`), `:julia_version => string(VERSION)`, and `struct2dict(s)` (all 14 Scenario selectors incl. `:seed`). Live round-trip during this verification (`wload`) confirmed `gitcommit`, `julia_version`, `seed`, and every selector present. Same-Scenario+seed reproducibility confirmed both by the `@testitem` suite (`INFRA-04 same-seed repro` / `... admm`, both pass) and by the fact that no solver is named anywhere in `src/experiments/*.jl` — all solving routes through `select_optimizer`/`ConvexBranchFlow`, which resolve to Clarabel (SOCP/QP) and HiGHS/Ipopt per the project's existing solver-factory abstraction (INFRA-02 preserved). |

**Score:** 3/3 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `src/experiments/Scenario.jl` | Immutable primitive-selector `Scenario` + validation, savename-able | VERIFIED | 184 lines; `struct Scenario` with 14 primitive fields; inner constructor throws `ArgumentError` on unknown feeder/strategy/price/population and on non-positive ADMM knobs (WR-01 fix applied); exported. |
| `src/experiments/materialize.jl` | `sub_seed` + `build_feeder`/`build_price`/`build_population` | VERIFIED | 219 lines; `sub_seed(master,tag)` gives independent deterministic sub-streams; `build_feeder`/`build_price`/`build_population` reuse Phase 1–7 builders (`ieee13_modified`, `generate_profiles`, `Aggregator`); `feeder_sym`-based dispatch (WR-03 fix, no bus-count heuristic); no solver named. |
| `src/experiments/run.jl` | `ScenarioResult` + `run_scenario` dispatch + node×T normalization | VERIFIED | 154 lines; both `:centralized` and `:admm` branches implemented; terminal `else` throws `ArgumentError`; timings (`elapsed`) present but excluded from all equality comparisons. |
| `src/experiments/store.jl` | `run_and_store`: `@tagsave` provenance | VERIFIED | 109 lines; `@tagsave` with `storepatch=true`, `safe=true`, `gitpath=pkgdir(@__MODULE__)` (Rule-1 fix for `Pkg.test()` sandbox); `scenario_filename` single-sourced (WR-06 fix) and reused by `scripts/run_scenario.jl`. |
| `src/experiments/sweep.jl` | `run_sweep` (dict_list) + `collate_summary` (diff-friendly CSV) | VERIFIED | 110 lines; three diff-friendly rules all present: fixed explicit column `select`, `sort!` by every selector column (WR-04 fix), `:path` dropped while `:gitcommit` kept. |
| `scripts/run_scenario.jl` | `@quickactivate` single-run entry point | VERIFIED | Present, `@quickactivate "TSODSO"`, calls `run_and_store`, prints via the single-sourced `scenario_filename` helper (WR-06 fix confirmed applied). |
| `scripts/sweep.jl` | `@quickactivate` sweep entry point | VERIFIED | Present, `@quickactivate "TSODSO"`, calls `run_sweep` + `collate_summary`, writes to `results/sweeps/`. |
| `test/test_experiments.jl` | Complete `@testitem` suite covering EXP-01/EXP-02/INFRA-04 | VERIFIED | 12 `@testitem`s (all guarded with `isdefined` checks per the RED-harness convention); independently re-executed during this verification (see below) — all pass. |
| `test/fixtures_phase8.jl` | `@testmodule Phase8Fixtures` | VERIFIED | `minimal_scenario_kwargs()` + `with_tempdir()` present, defines-only (load-safe). |
| `Project.toml` / `test/Project.toml` | Hard `[deps]` + `[compat]` for DrWatson/CSV/DataFrames | VERIFIED | `DrWatson = "2.19.1"`, `CSV = "0.10.16"`, `DataFrames = "1.8.2"` present in both root and test `[compat]`; all 5 manifests (`Manifest.toml`, `Manifest-v1.10/1.11/1.12.toml`, `test/Manifest.toml`) present and committed. |
| `data/` / `results/sweeps/` | Two-tier storage split | VERIFIED | `data/` gitignored (`.gitignore` line 8, `git check-ignore` confirms); `results/sweeps/.gitkeep` tracked in git (`git ls-files` confirms). |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `src/TSODSO.jl` | `src/experiments/*.jl` | `include(...)` after admm/ and diagnostics/ | WIRED | 5 includes present in correct dependency order (Scenario → materialize → run → store → sweep), lines 118–122, positioned after `admm/solve_admm.jl` (line 99) and `diagnostics/plots.jl` (line 106). |
| `src/experiments/run.jl` | `solve_welfare`/`extract_dlmp`/`solve_admm` | strategy dispatch | WIRED | Both branches call the real Phase 3–7 functions; live-executed during this verification with real numeric output. |
| `src/experiments/store.jl` | `run_scenario` / `@tagsave` | provenance dict → gitignored JLD2 | WIRED | Live round-trip (`wload`) confirmed during this verification. |
| `src/experiments/sweep.jl` | `collect_results`/`CSV.write` | dict_list runs → DataFrame → sorted CSV | WIRED | Live sweep + double-collation confirmed byte-identical during this verification. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| `run_and_store` end-to-end (centralized, IEEE-13, seed=99) | `TSODSO.run_and_store(Scenario(...); dir=mktempdir())` then `DrWatson.wload` | `welfare=-4823.07`, `exact_maxgap=6.1e-9`; provenance dict contains `gitcommit`, `julia_version`, `seed`, all 14 selectors | PASS |
| `run_sweep` + double `collate_summary` (2-seed sweep) | `TSODSO.run_sweep(Dict(...:seed=>[1,2]))` then `collate_summary` twice into separate CSVs | `byte identical: true`; header `name,feeder,strategy,seed,T,price,population,allow_export,ρ,ε_abs,ε_rel,maxiter,τ_ratio,μ,welfare,exact_maxgap,iters,final_r,final_s,gitcommit` (no `path`) | PASS |
| Full package test suite (`Pkg.test()`, independently re-run by this verifier, not the orchestrator's prior run) | `julia --project=. -e 'using Pkg; Pkg.test()'` | `Package | 1933 Pass, 2 Broken, 1935 Total, 5m58.0s` — 0 fail, 0 error | PASS |
| Phase-8 `@testitem`s specifically (12 items: EXP-01 ×3, EXP-02 ×2, INFRA-04 ×7) | Included in the full-suite run above; item names confirmed present in `test/test_experiments.jl` | All 12 pass (subsumed in the 1933-pass total; independently spot-checked via live script execution above) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| EXP-01 | 08-01, 08-02, 08-03 | Declarative scenario, swappable solve strategy | SATISFIED | `Scenario` + `run_scenario` (:centralized/:admm), live-verified |
| EXP-02 | 08-01, 08-04 | Parameter sweeps, flat/versioned/diff-friendly storage | SATISFIED | `run_sweep` + `collate_summary`, byte-identical CSV live-verified |
| INFRA-04 | 08-01, 08-02, 08-03, 08-04 | Reproducibility — seeded, logged, bit-for-bit regeneration | SATISFIED | `sub_seed` (independent StableRNGs sub-streams), `run_and_store` provenance (`:gitcommit`/`:julia_version`/`:seed`), same-seed identity confirmed by test suite for both strategies |

No orphaned requirements: REQUIREMENTS.md maps only EXP-01, EXP-02, INFRA-04 to Phase 8, and all three appear in at least one plan's `requirements:` frontmatter field.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | none found | — | `grep -n -E "TBD\|FIXME\|XXX\|TODO\|HACK\|PLACEHOLDER"` across all `src/experiments/*.jl` and both scripts returned zero matches. No hardcoded-empty-return stubs, no `console.log`-only handlers (n/a, Julia), no unimplemented branches. |

WR-02 (`sub_seed`'s `Base.hash`-based derivation, not guaranteed cross-Julia-version-stable by
`Base.hash`'s own docstring) is a documented, explicitly-deferred code-review finding
(`deferred-items.md`), not an unresolved debt marker in the source — it is empirically
reproducible across Julia 1.10/1.11/1.12 today, and a mechanical fix was attempted and rolled
back because it required a research-level ρ/τ re-tuning decision. This is a long-term risk
flag, correctly scoped as out of this phase's automated-fix boundary; it does not block phase-8
goal achievement (the test suite's same-seed identity gates pass on all three supported Julia
versions today) but is worth the researcher's attention before any cross-version regression
test is added.

### Human Verification Required

None. All three success criteria were independently confirmed both by re-running the full
test suite (1933 pass / 0 fail / 0 error / 2 pre-existing broken, matching the orchestrator's
prior report) and by live, hands-on execution of `run_and_store` and `run_sweep`/
`collate_summary` against the real IEEE-13 fixture during this verification session (see
Behavioral Spot-Checks). No visual, UX, or external-service-dependent behavior is in scope for
this phase.

### Gaps Summary

No gaps. All three roadmap success criteria are observably true in the codebase: (1) a
researcher declares a `Scenario` via primitive selectors and runs it end-to-end with either
`:centralized` or `:admm`; (2) `run_sweep`/`collate_summary` produce a flat, versioned,
diff-friendly (byte-stable, `:path`-free, fixed-column, deterministically-sorted) CSV; (3)
`run_and_store` stamps every run with git commit, Julia version, and seed via `@tagsave`, and
same-Scenario+seed runs are bit-for-bit identical through the full Clarabel/HiGHS-backed solve
path (no solver named in the Phase-8 code itself, preserving INFRA-02). The one open item
(WR-02 sub_seed cross-version hash stability) is explicitly documented and deferred to the
researcher as a future research decision, not a phase-8 completion blocker.

---

_Verified: 2026-07-19T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
