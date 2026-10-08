---
phase: 37-test-infrastructure-repo-hygiene
reviewed: 2026-10-07T00:00:00Z
depth: standard
iteration: 3
files_reviewed: 57
files_reviewed_list:
  - .github/scripts/check_script_api.jl
  - .github/scripts/check_scripts_index.py
  - .github/scripts/check_suite_log.py
  - .github/workflows/CI.yml
  - .github/workflows/slow.yml
  - .gitignore
  - README.md
  - scripts/README.md
  - scripts/archive/pv_boom_report_v1.jl
  - scripts/archive/reactive_flake_rate.jl
  - scripts/flake_rate.jl
  - scripts/jet_baseline.txt
  - scripts/jet_check.jl
  - scripts/lib/pv_boom_common.jl
  - scripts/pv_boom_case_study.jl
  - scripts/pv_boom_report.jl
  - scripts/repro_stability_check.jl
  - scripts/run_tests_filtered.jl
  - src/core/ModelContext.jl
  - src/experiments/run_stochastic.jl
  - src/models/ac_oracle.jl
  - src/models/linear_solve.jl
  - src/models/restriction_exactness.jl
  - src/models/stochastic_welfare.jl
  - src/models/toy_dc.jl
  - src/models/welfare_solve.jl
  - src/planning/ac_recheck.jl
  - src/planning/benders.jl
  - src/planning/bilevel_kkt.jl
  - src/planning/feasibility_oracle.jl
  - src/planning/follower.jl
  - src/planning/master.jl
  - src/planning/master_integer.jl
  - src/planning/subproblem.jl
  - src/pricing/fit.jl
  - src/pricing/welfare.jl
  - src/solver/factory.jl
  - test/expected_broken.txt
  - test/fixtures_retry.jl
  - test/runner_support.jl
  - test/runtests.jl
  - test/test_acceptance.jl
  - test/test_admm.jl
  - test/test_admm_adaptive.jl
  - test/test_benchmark_ieee8500.jl
  - test/test_experiments.jl
  - test/test_flake_retry.jl
  - test/test_ieee123_admm.jl
  - test/test_planning_certification_bilevel_interior.jl
  - test/test_planning_certification_integer.jl
  - test/test_planning_master_integer.jl
  - test/test_planning_nash.jl
  - test/test_planning_nash_integer.jl
  - test/test_pricing_welfare.jl
  - test/test_strategies.jl
  - test/test_thesis_repro.jl
  - test/test_toy_dc.jl
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 37: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-07
**Depth:** standard (Phase 37 diff `08081f8^..HEAD`; focus on fixes `2171a5a..a021922`)
**Files Reviewed:** 57
**Status:** issues_found

## Summary

All five iteration-2 Warnings (WR-01 to WR-05) and the three Info items fixed with them
(IN-01 to IN-03) hold up under probes. I found no blocker and no regression caused by the
fixes. One new Warning (the documented run command for the merged PV-boom report fails on a
clean checkout) and three Info items remain.

**Prior findings checked:**

- **WR-01 (slow.yml concurrency).** The group expression
  `github.event_name == 'push' && format('push-{0}', github.sha) || format('{0}-{1}', github.event_name, github.ref)`
  is valid GitHub expression syntax. `format()` always returns a non-empty string, so the
  `&& ||` ternary idiom cannot fall through by mistake. Each push gets the group
  `slow-push-<sha>`. Schedule runs get `slow-schedule-refs/heads/main` and dispatch runs get
  `slow-workflow_dispatch-refs/heads/main`, which are separate groups. On push,
  `inputs.test_set` is empty and falls back to `all`. The README (lines 211-220) and the
  workflow header describe this correctly, including the head-commit-only behaviour for a
  multi-commit push and the one-pending-run limit for schedule and dispatch runs.
- **WR-02 (PV-boom Part A2).** I re-ran `scripts/pv_boom_case_study.jl` from a `git archive
  HEAD` export on Julia 1.12.7. The regenerated `results/pv_boom/findings.txt` and
  `summary.csv` are byte-identical to the committed files. The run printed the same numbers:
  bound active at [9, 10, 11, 12, 15], AC-implied `v̂` max 1.111137 against 1.1025, and with
  the bound deleted, `OPTIMAL`, `obj_gap = -9.730037e-06`, cone maxgap 1.659e-07, hour [7]
  still differing. I traced the diagnostic:
  - `solve_welfare` does not mutate the model after `optimize!`
    (`src/models/welfare_solve.jl:241-287`). So the `delete_upper_bound` + re-`optimize!`
    re-solves exactly the model whose `obj_gap` was reported.
  - The loop deletes only `v̂[j,t]` upper bounds at non-root buses. The root `v̂` is fixed
    (`ConvexBranchFlow.jl:247`), so it is correctly left alone. The `v̂` lower bounds, the `v`
    bounds, the cones and `cpydrop` are untouched. Nothing in `src/` changed in `a021922`.
  - The AC-implied `v̂` recursion matches `cpydrop`'s default branch
    (`ConvexBranchFlow.jl:309-317`, `Prev = P − r·l`, `Qrev = Q − x·l`). `v̂` is fully
    determined by `(P, Q, l)` through that equality chain, so "the AC point is infeasible for
    the SOCP there" follows.
  - Signs are consistent. Both models are `Max` welfare. `obj_gap` uses the same `_objective`
    difference as `assert_ac_exact!`, and the hand-rolled cone residual matches
    `assert_socp_exact!`'s absolute `|l·v − P² − Q²|`.
  - The "measured cause" wording is gated on `share ≥ 0.999`, a non-empty bound-active set and
    an `OPTIMAL` re-solve. Every other outcome falls back to "cause not established".
- **WR-03.** Fixed. The `planning_hours` source-parsing
  fallback is gone (`scripts/lib/pv_boom_common.jl:88-93`), so a missing key is now a hard
  error.
- **WR-04 (scripts index).** The selftest passes and the real tree passes (37 files). The
  probe `archive/old.jl` listed as `old.jl` is reported as both missing and stale. An
  `archive/` entry in the Scripts table and a non-archive entry in the Archive table are both
  reported as MISLOCATED. One fail-open path remains; see IN-01 below.
- **WR-05 / IN-01 (guard).** `item_index` returns the child of the first `*.jl` component at
  index ≥ 2. If a future TestItemRunner drops the file level, every record keys to
  `("broken","","",expr)`. Those keys are never in `expected_broken.txt`, which the parser
  requires to name a `.jl` file, so the guard fails closed.
  - The 1.3.x layouts work because the `basename` of a collapsed `sub/file.jl` is
    `file.jl`, and a deeper tree just moves the index.
  - The FIT `@test_broken !(fit_outcome isa SolveFailedError)` (`test_pricing_welfare.jl:373`)
    only runs inside the `fit_outcome isa SolveFailedError` branch. There it evaluates to
    `false` and records Broken. On the success path it is never reached.
  - Its key `string(orig_expr)` is `!(fit_outcome isa SolveFailedError)`. This is
    printer-stable across 1.10 and 1.12 and matches `expected_broken.txt:16`.
- **IN-02.** `file_hits` is now incremented only inside `if m` (`runtests.jl:68-75`).
- **IN-03.** `unjustified_signatures` behaves correctly on all the probes:
  - a deleted marker;
  - a signature line after a blank line;
  - a signature line after a non-Group comment;
  - a signature line under the header.

  The committed 12-line baseline is clean under it.

## Warnings

### WR-01: The documented run command for `pv_boom_report.jl` (and six other scripts) fails on a clean checkout: CairoMakie is only a weak dependency

**File:** `scripts/README.md:22` (also rows for `benders_toy.jl`, `compare_default_stochastic.jl`, `demo_flexibility_plots.jl`, `demo_mpc_plots.jl`, `thesis_case123_repro.jl`, `thesis_caseA.jl`); `scripts/lib/pv_boom_common.jl:12`

**Issue:** The index this phase introduced gives
`julia --project=. scripts/pv_boom_report.jl [results.jld2 [outdir]]` as the way to build the
report. `pv_boom_common.jl:12` does `using CairoMakie`, but the committed `Project.toml` lists
CairoMakie only under `[weakdeps]`. I ran that exact command from a `git archive HEAD` export
after `Pkg.instantiate()`, on Julia 1.12.7. It fails with
`ArgumentError: Package CairoMakie not found in current path`. The fixer's "report rendered to
scratch" check most likely passed only because the main checkout carries the known local
`Project.toml` drift, which promotes CairoMakie to `[deps]`. So the WR-02 report path has not
been verified on committed state. The same applies to every other script in the list above.

**Fix:** Document the extra environment in `scripts/README.md`, for example a Conventions
bullet such as "Figure scripts need CairoMakie (a weak dependency): run them with a stacked
env, e.g. `julia --project=. -e 'using Pkg; Pkg.activate(temp=true); Pkg.develop(path=\".\"); Pkg.add(\"CairoMakie\")' ...`".
Better, add a small `scripts/Project.toml` env that includes TSODSO (dev) and CairoMakie, and
change those Run cells to `julia --project=scripts ...`. Then re-render the report from a
clean export to verify section 4.5.

## Info

### IN-01: `mislocated_entries` is silently a no-op if the `## Scripts` / `## Archive` headings are renamed

**File:** `.github/scripts/check_scripts_index.py:98-117`
**Issue:** The check only runs inside sections titled exactly `Scripts` or `Archive`. I renamed
the heading to `## Active scripts` and it returned `[]` with no diagnostic. That makes the
WR-04 archive-status guarantee depend on heading text that nothing enforces.
**Fix:** In `main`, fail (exit 1) when either heading is missing from the README. Add a
selftest case for it.

### IN-02: Part A2 "measured cause" leaves a residual gap 10x the script's own not-a-relaxation threshold without characterising it

**File:** `scripts/pv_boom_case_study.jl:519-524`, `scripts/pv_boom_case_study.jl:548-559`; `results/pv_boom/findings.txt` (Part A2)
**Issue:** After deleting the bound, `obj_gap = -9.73e-06`. The script's own classification
threshold is `A2_WORDING_TOL = 1e-6` (`a2_not_relaxation = obj_gap < -1e-6`), so under that
rule the bound-deleted model is still "not a relaxation". The text reports the number and
says hour 7 is "not diagnosed further", which is honest. But "99.998% of the gap removed"
next to "Measured cause" reads as complete. The text does not say whether `-9.7e-6` is within
the Ipopt/Clarabel solve tolerance relative to the welfare magnitude.
**Fix:** Add one clause to the summary, for example "residual −9.7e-6 (relative X to |welfare|,
within / outside solver tolerance)". Alternatively, classify the bound-deleted re-solve with
the same `A2_WORDING_TOL` rule and print the result.

### IN-03: README JET paragraph does not mention the new loose-signature rule

**File:** `README.md:233-239`
**Issue:** The README still says the check fails "while the baseline still has an UNJUSTIFIED
block". Since `1e2bd3a`, it also fails on any signature line that is not directly under a
`# Group` comment block, and `--update` exits 1 in that case too. A contributor who edits the
baseline by hand, guided by the README, would not expect that failure.
**Fix:** Add: "and when any signature line is not directly under a `# Group ...` comment block
(no blank line between)."

---

_Reviewed: 2026-10-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
