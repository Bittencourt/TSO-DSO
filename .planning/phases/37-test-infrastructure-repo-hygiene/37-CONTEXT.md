# Phase 37: Test Infrastructure & Repo Hygiene - Context

**Gathered:** 2026-10-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Close HYG-04, HYG-05, HYG-06, HYG-08: a JET check runs in CI in report mode against an agreed
baseline; tests carry a `:slow` tag with a fast CI job per push and the slow suite separately/nightly;
known flakes are fixed or quarantined honestly so a green suite means green; `scripts/` is indexed,
one-off/superseded scripts archived, `pv_boom_report*` duplication merged into shared code, the
redundant root `Manifest.toml` dropped or documented, `.planning/tmp/` untracked.

Last phase of milestone v4.0. No solver/model behaviour change: canary (iters = 56,
welfare = -4823.66604824162) and goldens never re-pinned. Current full suite: 32205/0/0/5 (~28 min).

</domain>

<decisions>
## Implementation Decisions

### JET in CI (HYG-04)
- `JET.report_package(TSODSO; target_modules=(TSODSO,))` in its own CI job on Julia 1.12 (JET tracks
  the latest Julia minor).
- Ratchet baseline: committed file of normalized report signatures (kind + function + message, no
  line numbers); CI fails only on reports NOT in the baseline; fixed reports must be removed from it.
- Fix trivially-real findings (undefined names, wrong-arity calls, etc.) in-phase; baseline the rest
  with a short per-category justification. Any src/ fix must keep goldens + canary bit-identical.
- `scripts/jet_check.jl` runs the same check locally and regenerates the baseline with `--update`.

### Fast/slow split (HYG-05)
- `:slow` = measured rule: `@testitem`s in files taking ≥ 30 s in a full run (≈10–14 heavy files:
  acceptance, ieee123_admm, experiments, admm, certification_*, strategies, planning_nash,
  admm_adaptive, thesis_repro, integer planners…; per-item timings from one instrumented run). The
  knife-edge canary stays FAST (every push).
- `test/runtests.jl` honours env `TSODSO_TEST_SET` = `fast` (exclude `:slow`) / `slow` (only `:slow`) /
  `all` or unset (everything — local `Pkg.test()` stays the full suite).
- CI: push/PR → fast set on Julia 1.10/1.11/1.12; separate `slow` workflow → full suite nightly (cron)
  + `workflow_dispatch`, on 1.10 and 1.12.
- Restrict `@run_package_tests` discovery to items whose file lies under `test/` (kills the
  stray-`.jl`-testitem hazard from `.planning/`/scratch files).

### Flakes (HYG-06)
- Measure before deciding: new `scripts/flake_rate.jl` runs the IEEE-13 ADMM items and the
  stochastic-welfare items 20× each in fresh processes; per-item pass/fail + solver status recorded in
  `results/flake_rate/`.
- If a flake reproduces: retry-and-report quarantine — up to 3 tries, each retry logged via `@info`,
  passes only if a retry succeeds, summary reports retry use; all-fail = real failure. Deterministic
  failures → `@test_broken` with reason.
- Archive `scripts/reactive_flake_rate.jl` (broken by design), superseded by the new harness, which
  measures against `ReactiveMode.LIVE`/current defaults and counts `ConvergenceError` as a labelled
  flake category (settles the Phase 36 deferred decision).
- Keep the documented conditional `broken=` sites and CairoMakie `@test_skip`s (reason in names); add
  a check that the broken/skip set equals an expected list so no new broken slips in silently.

### Repo hygiene (HYG-08) + leftovers
- `scripts/README.md` index (purpose, how to run, outputs, status). `git mv` to `scripts/archive/`:
  `reactive_flake_rate.jl`, `run_scenario.jl` (first check whether its battery-complementarity failure
  is a stale fixture — fix if trivial, else archive with a note). Keep `benders_toy.jl` and
  `compare_default_stochastic.jl` (docs-referenced). `check_script_api.jl` skips `scripts/archive/`.
- pv_boom: extract shared helpers (figure data URI, sweep/nash tables, …) into
  `scripts/lib/pv_boom_common.jl`; v2 becomes the single `pv_boom_report.jl` using it; archive v1;
  verify the regenerated HTML matches v2's structure.
- Root `Manifest.toml` (byte-identical to `Manifest-v1.12.toml`): drop it if every supported Julia
  (1.10/1.11/1.12) resolves via `Manifest-v1.x.toml` (research to verify 1.10 behaviour); otherwise
  keep and document why (.gitignore comment / README).
- Untrack `.planning/tmp/` (currently `docs-work-manifest.json`) and ignore the whole dir.
- Phase 36 leftovers: fix the `test/test_benchmark_ieee8500.jl` docstring so JuliaFormatter is clean
  (content-loss check OK); fix the 4 docs `@ref` warnings; wire `test_benchmark_ieee8500.jl` as a
  `:slow` testitem wrapper or document it as manual.

### Claude's Discretion
- Exact JET normalization format; per-item timing method; flake harness CLI; README layout; shared-lib
  API names.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/CI.yml` (jobs `test` 1.10/1.11/1.12 + `format`; script-API check after tests);
  `.github/scripts/suite_detached.sh`, `check_suite_log.py`, `check_script_api.jl`,
  `check_planning_ids.py`, `ast_equiv.jl`, `format210.jl`; `scripts/run_tests_filtered.jl`
  (`tag:`/`file:` specs, fail on empty selection).
- Per-file wall times in `.planning/tmp/36/p05.log` (97 files, ~1678 s).
- `src/planning/retry.jl:31` `RETRYABLE_STATUSES` (incl. NUMERICAL_ERROR); typed errors
  `SolveFailedError`/`CertificateError`/`ConvergenceError`.

### Established Patterns
- `test/runtests.jl` = `@run_package_tests` (no filter); 605 testitems / 113 files / 41 tag sets; no
  `:slow` tag. JET in `test/Project.toml` but unused.
- Broken sites: conditional `broken=` at `test_thesis_repro.jl:256`, `test_ieee13.jl:244`,
  `test_acceptance.jl:114`, `test_pricing_welfare.jl:366`; `@test_skip` (CairoMakie) at
  `test_planning_nash.jl:589`, `test_diagnostics_plot.jl:107`.
- Manifests: root + `-v1.10/-v1.11/-v1.12` + test/docs/bench, all tracked.

### Integration Points
- Memory: `background-suite-orphan-race`, `testitemrunner-scans-scratch-jl`,
  `gsd-plan-verify-testitemrunner-trap` (runner recipe `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`),
  `local-project-toml-drift`.

</code_context>

<specifics>
## Specific Ideas

- Planning-ID guard and script-API check from Phase 36 must stay green (no IDs in new files).

</specifics>

<deferred>
## Deferred Ideas

- Large-lattice integer termination criterion — past v4.0 (ROADMAP).

</deferred>
