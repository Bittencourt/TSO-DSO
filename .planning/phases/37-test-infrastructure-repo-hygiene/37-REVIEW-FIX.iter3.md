---
phase: 37-test-infrastructure-repo-hygiene
fixed_at: 2026-10-07T00:00:00Z
review_path: .planning/phases/37-test-infrastructure-repo-hygiene/37-REVIEW.md
iteration: 2
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 37: Code Review Fix Report

**Fixed at:** 2026-10-07
**Source review:** .planning/phases/37-test-infrastructure-repo-hygiene/37-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 5 (WR-01 to WR-05; fix_scope critical_warning)
- Fixed: 5
- Skipped: 0
- Also fixed as requested (out of scope, cheap): IN-01, IN-02, IN-03

## Fixed Issues

### WR-01: The `slow.yml` concurrency group drops queued runs

**Files modified:** `.github/workflows/slow.yml`, `README.md`
**Commit:** 2171a5a
**Applied fix:** The concurrency group is now
`${{ github.workflow }}-${{ github.event_name == 'push' && format('push-{0}', github.sha) || format('{0}-{1}', github.event_name, github.ref) }}`
with `cancel-in-progress: false`. Every push to `main` gets its own group, so no run is
queued behind, replaced or cancelled by another push. A burst of merges runs in parallel. A
single push that carries several commits is tested at its head commit. Scheduled and
dispatched runs share one group per event type and ref, and within that group GitHub still
keeps only one pending run. The workflow header and both README sentences now describe exactly
this. YAML parsed with PyYAML. actionlint is not installed, so the expression was not linted.

### WR-02: Part A2 wording blamed the wrong cause; fallback could claim "genuinely INEXACT" with a tight cone

**Files modified:** `scripts/pv_boom_case_study.jl`, `scripts/pv_boom_report.jl`, `scripts/lib/pv_boom_common.jl`, `scripts/README.md`, `results/pv_boom/findings.txt`
**Commit:** a021922
**Applied fix:**
- **Sign confirmed.** Both models are `MAX_SENSE` (welfare). `obj_gap = SOCP − AC = -0.4773`,
  so the SOCP optimum is worse than the AC solution. The SOCP model as configured is
  therefore not a relaxation of the AC model on this fixture. The `allow_local` explanation is
  removed everywhere.
- **The reviewer's hypothesis was tested and confirmed.** A diagnostic in the case-study
  script measures it. No src/, gate or tolerance change. On Julia 1.12.7:
  - the bound `v̂ ≤ vmax²` (ConvexBranchFlow, thesis 3.45; ACPowerFlow has no `v̂`) is active
    in the SOCP solution at hours [9, 10, 11, 12, 15];
  - the AC solution sits at `v = vmax²` at the same hours;
  - the `v̂` that the SOCP's copy recursion assigns to the AC point reaches 1.111137, above
    `vmax² = 1.1025`, so the AC point is infeasible for the SOCP at those hours;
  - re-solving the same SOCP with only the `v̂` upper bounds deleted moves `obj_gap` to
    -9.73e-6, which removes 99.998% of the gap. The cone max gap is then 1.66e-7, and SOCP
    and AC still differ at 1 hour ([7]), which was not diagnosed further.

  findings.txt states this as the measured cause, with these numbers. It labels the model
  disagreement UNRESOLVED.
- **Headings and wording.** Neither heading says "reproduced" any more. The wording now
  splits into four cases: all_exact, not_relaxation (measured vs not established),
  tight_differ, and inexact. "INEXACT" is used only when the cone is not tight and
  `obj_gap >= 0`.
- **No hard error on agreement.** The `isempty(inexact_hours) && error(...)` hard stop is
  removed. If the two models agree at every hour, the script reports that instead.
- **Report.** The report reads `case`, `cause_measured` and the evidence sentence from
  results.jld2 through `pv_boom_a2_check`. It errors on an older file and tells the user to
  rerun the case study. The text is HTML-escaped. The report was rendered to scratch and
  section 4.5 checked.
- **Regenerated outputs.** findings.txt was regenerated on Julia 1.12.7, the patch that
  reproduces the committed Part A numbers and `summary.csv` bit-for-bit (a 1.12.5 run moves
  `exact_maxgap` in the 3rd–4th digit). Only Part A2 changed. `summary.csv` is unchanged.
  `results.jld2` is gitignored, so it is not committed.
- **Status: fixed, requires human verification.** This finding is about research
  interpretation. Please confirm the wording, and decide whether the `v̂ ≤ vmax²` bound should
  be reconciled in src (that is a modelling decision and out of scope here).

### WR-03: The `planning_hours` fallback silently relabelled stale results

**Files modified:** `scripts/lib/pv_boom_common.jl`
**Commit:** 3626f0f
**Applied fix:** The fallback that parsed the window from the source file is removed. If the
`"planning_hours"` key is missing, the script errors and tells the user to rerun
`scripts/pv_boom_case_study.jl`. Smoke-tested both paths: a missing key errors, and 11:16
round-trips.

### WR-04: `check_scripts_index.py` passed a script moved to `archive/` with an unchanged active row

**Files modified:** `.github/scripts/check_scripts_index.py`
**Commit:** 648cbf9
**Applied fix:**
- A file in a subdirectory must now be named by its path relative to `scripts/`. A bare
  basename names only `scripts/<name>`.
- The stale check uses the same rule, so the reviewer's probe (`archive/old.jl` listed as
  `old.jl`) is reported as both NOT INDEXED and STALE.
- New MISLOCATED check, comparing the first column of each table: the `## Scripts` table may
  not list an `archive/` entry, and the `## Archive` table may list only `archive/` entries.
- The selftest covers the probe, the subdirectory-basename case and both mislocation
  directions. The selftest and the real-tree check pass.

### WR-05: `ITEM_DEPTH = 4` depended on an unpinned TestItemRunner

**Files modified:** `test/runner_support.jl`, `test/runtests.jl`, `scripts/run_tests_filtered.jl`
**Commit:** ab3a652
**Applied fix:** I made the guard robust rather than pinning TestItemRunner. The new
`item_index(path)` locates the `@testitem` level from the testset tree itself: it is the child
of the first testset below the root whose name ends in `.jl`. `ITEM_DEPTH` is removed. The
comments now say which version each CI leg runs:
- Julia 1.12: TestItemRunner 1.1.5, from test/Manifest.toml.
- Julia 1.10: TestItemRunner 1.3.2 and TestItems 1.1.0. Confirmed: `Pkg.test` re-resolves to
  these on 1.10.11.

The guard selftest now also covers the 1.3.x layouts: `sub / file.jl`, a collapsed
`sub/file.jl`, and nesting two levels deep. Verification:
- Guard selftest passes on 1.10.11 and 1.12.7.
- Real `Pkg.test` runs with `TSODSO_TEST_FILES=test_diagnostics_plot.jl,test_pricing_welfare.jl`:
  - 1.10.11 (TestItemRunner 1.3.2): 76 pass, 2 broken, guards green.
  - 1.12.7 (TestItemRunner 1.1.5): 71 pass, 2 broken. The FIT gate fired and the guards
    were green.

### IN-01 (extra): expected-broken key had no file; the FIT gate's `false` matched any `@test_broken false`

**Files modified:** `test/runner_support.jl`, `test/runtests.jl`, `test/expected_broken.txt`, `test/test_pricing_welfare.jl`, `scripts/run_tests_filtered.jl`, `README.md`
**Commit:** 433a44c
**Applied fix:** The key is now `(kind, file, item, test)`, where file is the basename of the
file testset. `expected_broken.txt` gains a file column, and the parser requires it to end in
`.jl`. The FIT gate now records `@test_broken !(fit_outcome isa SolveFailedError)`. This
changes only the expression of an expected-broken record. No golden or canary was touched.
The selftest adds a case where an item with the same name in another file is rejected. The
real 1.12.7 run confirmed that the gate's new key matches.

### IN-02 (extra): a `TSODSO_TEST_FILES` name counted as matched when the set excluded its items

**Files modified:** `test/runtests.jl`, `test/runner_support.jl`, `README.md`
**Commit:** dd662b7
**Applied fix:** `file_hits` is incremented only when `tso_selected(...)` is true. The
docstring and README are updated to match.

### IN-03 (extra): JET justification only looked for the marker line

**Files modified:** `scripts/jet_check.jl`
**Commit:** 1e2bd3a
**Applied fix:** New `unjustified_signatures(lines)`. Every signature line must follow a
`# Group` comment block directly, and a blank line, the marker, or a non-Group comment after
the signatures ends the group. Both check mode and `--update` fail on loose lines. The selftest
covers the reviewer's probe: once the marker is deleted, the line is still reported. It also
asserts that the committed baseline is clean under the new rule. The selftest passes on 1.10
and 1.12. The full JET analysis was not rerun, because the baseline file is unchanged.

## Verification run

- `check_planning_ids.py` (+ selftest), `check_scripts_index.py` (+ selftest) and
  `check_script_api.jl` (+ selftest) all pass. For `check_script_api.jl`, the case study's
  `MOI.OPTIMAL` comparison was replaced with the equivalent status string.
- JuliaFormatter 2.10.2 dry run over src/ext/test/docs: already formatted.
  `check_content_loss.py HEAD`: OK.
- The fixes were made in an isolated worktree, `main` was fast-forwarded to a021922, and the
  worktree, temp branch and sentinel were removed.
- Note: the main checkout's gitignored `data/pv_boom/results.jld2` predates the new Part A2
  fields. Rerun `scripts/pv_boom_case_study.jl` (about 2 min on `julia +1.12`) before building
  the report.

---

_Fixed: 2026-10-07_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
