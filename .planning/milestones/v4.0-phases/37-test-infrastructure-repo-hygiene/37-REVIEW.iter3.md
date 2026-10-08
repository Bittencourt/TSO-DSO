---
phase: 37-test-infrastructure-repo-hygiene
reviewed: 2026-10-07T00:00:00Z
depth: standard
iteration: 2
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
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 37: Code Review Report (iteration 2)

**Reviewed:** 2026-10-07
**Depth:** standard (Phase 37 diff `08081f8^..HEAD`, focus on fixes `37c961c..35e8562` and `6b5a715`)
**Files Reviewed:** 57
**Status:** issues_found

## Summary

I re-checked every Critical and Warning from iteration 1 by trying inputs built to get past
each fix, without relying on the selftests. Most fixes hold. I found no new blocker. Five
warnings remain:
- two are regressions or gaps introduced by the fixes (WR-03, WR-05);
- one is a fix whose new wording is itself wrong (WR-02);
- one is a fail-open case the scripts-index fix does not cover (WR-04);
- one is a false guarantee in the new push trigger (WR-01).

**Prior findings verified as fixed (probes run):**
- **CR-01 (FIT gate).** It needs `ALMOST_OPTIMAL` and `NEARLY_FEASIBLE_POINT`, and the first
  non-`status.jl` frame after `assert_solved!` must be `fit_baseline` in `pricing/fit.jl`.
  `fit_baseline` calls `assert_solved!` directly only once (`src/pricing/fit.jl:515`, the seed
  AC-PF solve). SITE 2 raises `SolveFailedError` itself, not through `assert_solved!`, so
  it is rethrown. SITE 3 and `_fit_opt_solve` run from other frames, so they are rethrown too.
- **WR-01 (per-site guard).** I checked it under a real TestItemRunner run, not the synthetic
  tree: TestItemRunner 1.3.2 on Julia 1.10.11, with a scratch `test/` that has a subdirectory.
  The keys came out as `TSODSO / Package / <file> / <item>`. A nested testset gives the key
  `nested / false`. Each loop iteration of a `@test_broken` is its own record, and the
  multiset handles them. Skips are keyed `skipped`. A malformed `expected_broken.txt` line
  throws before the `@testset` starts, so the run fails closed. A test expression that
  contains ` | ` cannot be listed, which also fails closed. Errors and Fails are not
  Broken, so the outer testset still fails on them.
- **WR-09 (discovery rooted at `test/`).** I parsed all 511 `@testitem`s and 21 `@testsetup`s
  under `test/` with TestItemRunner's own detector. Every item except the 2 the fixer named
  has a full `using TSODSO`. No item relies on a selective `using TSODSO: x` while also using
  other exports. Those 2 items don't use TSODSO (one uses only BilevelJuMP and JuMP). 20 of
  the 21 setup modules import TSODSO. `BilevelCertFixture` doesn't, and doesn't need to.
  `test/Project.toml` has no `name`, so `package_name` is `""`, as the fixer said.
- **WR-02 / IN-05 (JET).** The multiset diff, the exit 1 on UNJUSTIFIED and the `--update`
  exit code are correct. The selftest passes on 1.10.11.
- **WR-03 (JET Julia version).** `setup-julia@v2` accepts the exact version `'1.12.7'`. The
  baseline header says 1.12.7.
- **WR-04 / WR-05 (flake harness).** The selftest passes on 1.10.11, including a real
  testset going through `counts_from`. `no_items` takes precedence over the other outcomes,
  and the parent exits 1 when any run is `no_items`.
- **WR-10.** Entries are trimmed. An empty entry and an unmatched name both fail closed.
- **IN-06.** The canary regex is anchored on the item's own `@info` block.
- **CI.yml.** The fast job still runs on push to `main`, on tags, on PRs and on dispatch, with
  `TSODSO_TEST_SET: fast`. `slow.yml` gets an empty `inputs.test_set` on push and falls back to
  `all`.

## Warnings

### WR-01: The `slow.yml` concurrency group drops queued runs, so "every merge triggers the full suite" is false

**File:** `.github/workflows/slow.yml:25-27`, `README.md:212-218`

**Issue:** The new `push: branches: [main]` trigger shares one group with the nightly
`schedule` and with `workflow_dispatch` (`${{ github.workflow }}-${{ github.ref }}`). The
group uses `cancel-in-progress: false`. With that setting GitHub allows one running run and
**one** pending run per group. A newer pending run cancels the older pending one ("Canceling
since a higher priority waiting request exists"). It does not queue behind it. With a
120-minute timeout and a two-version matrix, a full run can take more than an hour. So:
- If three PRs merge within one run's duration, the middle commit never gets a slow run.
- A `workflow_dispatch` with `test_set=slow`, or a nightly run, can be cancelled while
  pending by the next push.

The README says "those gates first run when the change lands on `main`, where every merge
triggers the full suite", and the workflow header says "so the :slow end-to-end correctness
gates run on each merge". Neither holds when merges come in a burst. A later green run on
HEAD also covers the earlier commits' code, but if HEAD goes red, the commit that broke it is
not isolated.

**Fix:** Pick one of these:
- State the real guarantee in the README and the workflow comment: the latest `main` commit
  is always tested, and intermediate commits in a burst may be skipped.
- Make each push its own group, for example
  `group: ${{ github.workflow }}-${{ github.event_name == 'push' && github.sha || github.ref }}`.
  This runs every merge, at the cost of more concurrent runners.

### WR-02: The new Part A2 wording blames the wrong cause, and its fallback branch can still claim "genuinely INEXACT" when the cone is tight

**File:** `scripts/pv_boom_case_study.jl:430-453`, `scripts/pv_boom_case_study.jl:774-804`, `scripts/pv_boom_report.jl:66-103`; committed artifact `results/pv_boom/findings.txt` (Part A2)

**Issue:**
1. **The stated cause is wrong.** The committed findings and the report say the negative
   `obj_gap` happens because "the AC solve is a local NLP solve (ACPowerFlow,
   `allow_local = true`) while the SOCP solve is not". `allow_local` only lets the solver
   return `LOCALLY_SOLVED`. Any AC-feasible point, local optimum or not, is feasible for a
   true SOC relaxation of the same problem. So a local AC solve can never beat the
   relaxation's optimum, and local-vs-global cannot explain `obj_gap = -0.477`. What a
   negative gap does prove is that the SOCP model is not a relaxation of the AC model.
   A likely cause is in the code: `ConvexBranchFlow` bounds the LinDistFlow exactness copy
   with `set_upper_bound(v̂[j, t], vb.vmax^2)` (`src/powerflow/ConvexBranchFlow.jl:258`,
   thesis 3.45). Under high-PV reverse flow with `vmax = 1.05`, the lossless `v̂` overestimates
   voltage. That cuts off AC-feasible points, so the SOCP is an inner restriction there, not a
   relaxation. The committed research artifact therefore names a cause that cannot be right
   and leaves out the likely one.
2. **The headings still say "reproduced".** Line 774 writes "Part A2 — the documented
   high-PV exactness finding, reproduced", and line 326 prints the same. The paragraph under
   that heading now says it is "NOT evidence" of inexactness.
3. **The fallback branch ignores cone tightness.** The non-mismatch branch
   (`obj_gap >= -1e-6`) still prints "the SOC relaxation is genuinely INEXACT" even when
   `pv_boom_a2_cone_tight` is true. A tight cone means the SOCP point satisfies the AC branch
   equations, so "genuinely INEXACT" contradicts that case.
4. **The run is gated on the artifact.** Line 423 (`isempty(inexact_hours) && error(...)`)
   still makes the case study fail if the per-hour gaps go away. If someone reconciles the two
   models, the script errors instead of reporting exactness. It now gates on reproducing a
   disagreement that its own text calls an unresolved artifact.

**Fix:**
- Replace the causal sentence with what the numbers prove: "obj_gap < 0, so the SOCP model is
  not a relaxation of this AC model on this fixture (candidate: the `v̂ ≤ vmax²` exactness-copy
  bound in ConvexBranchFlow binds under reverse flow); local vs global AC optimality cannot
  produce this".
- Choose the "genuinely INEXACT" wording only when the cone is not tight and `obj_gap >= 0`.
- Rename both "reproduced" headings.
- Turn the `isempty(inexact_hours)` error into a reported outcome rather than a hard stop.
- Regenerate `findings.txt`.

### WR-03: The `planning_hours` fallback silently relabels stale results, which is the CR-02 failure mode again

**File:** `scripts/lib/pv_boom_common.jl:72-92`

**Issue:** `data/pv_boom/results.jld2` is gitignored (`.gitignore:12`), so every researcher's
copy is whatever their last local run produced. When the file has no `"planning_hours"` key,
the window comes from the *current* `const PLANNING_HOURS = 11:16` line in the case-study
source. A results file from before the re-tune came from a 13:18 run. It has no key, and its
Nash `z` has 6 columns. The new window also has length 6, so the length check
`length(hours) == T_solved` passes. The report then labels 13:18 data "hours 11 through 16".
CR-02 was about exactly this mislabeled window. The guard only compares lengths, and the
re-tune kept the length the same.

**Fix:** Remove the source-parsing fallback. When the key is missing, raise an error:
`error("results.jld2 predates planning_hours; re-run scripts/pv_boom_case_study.jl")`.
That is what the error message already advises for a length mismatch.

### WR-04: `check_scripts_index.py` passes when a file is moved to `archive/` but its active-table entry is left unchanged

**File:** `.github/scripts/check_scripts_index.py:67`, `.github/scripts/check_scripts_index.py:89-90`

**Issue:** A bare basename indexes a tracked file in any subdirectory when the basename is
unique, and it is never reported stale when *any* tracked file has that basename. Archiving
a script moves it to `scripts/archive/<name>.jl` and leaves a unique basename behind. If the
README row `` `<name>.jl` | active ... `` is not touched, both checks pass. Probe:
`missing_entries(["scripts/archive/old.jl"], "Active: `old.jl` runs X") == []` and
`stale_entries(...) == []`. This repo's archive moves (`reactive_flake_rate.jl`,
`pv_boom_report_v1.jl`) are exactly this case, and keeping each file's status accurate is what
the index exists for.

**Fix:** Require a subdirectory file to be named by its relative path (`archive/old.jl` or
`scripts/archive/old.jl`). Allow bare basenames only for files directly under `scripts/`. In
`stale_entries`, a bare token is valid only if `scripts/<token>` is tracked. Add the probe above
to the selftest.

### WR-05: The guard's `ITEM_DEPTH = 4` depends on an unpinned TestItemRunner, and the Julia 1.10 CI leg already runs 1.3.2, not 1.1.5

**File:** `test/runner_support.jl:57-63`, `test/runtests.jl:44-53`, `test/Project.toml` (no `TestItemRunner` compat)

**Issue:** The fix replaced the any-path-component match, which did not depend on the
testset layout, with a fixed depth. The docstring says that depth is the "TestItemRunner
1.1.5" layout. `test/Manifest.toml` was resolved with `julia_version = "1.12.5"`. On Julia
1.10, `Pkg.test` re-resolves the sandbox. I ran it locally
(`TSODSO_TEST_FILES=test_flake_retry.jl`, Julia 1.10.11), and it loaded **TestItemRunner
v1.3.2** and JET 0.9.18. TestItemRunner 1.3.x builds a directory tree of testsets
(`build_tree`/`collapse_tree!`) instead of 1.1.5's flat `relpath` layout.

Today the depth happens to match: I checked that keys come out at depth 4 under 1.3.2,
including for a `test/sub/` file whose path is collapsed. However:
- If `test/` gets a subdirectory with two or more files, items sit at depth 5 under 1.3.x
  but depth 4 under 1.1.5.
- Any future layout change shifts the depth.

Either way every allowed record becomes "UNEXPECTED". That fails closed, but differently on
each CI leg, and it is not the version the comments describe. The `runtests.jl` header also
says the walk and setup-replacement behaviour is "TestItemRunner 1.1.5", which is not what
the 1.10 leg runs.

**Fix:** Pin TestItemRunner in `test/Project.toml` `[compat]` (`TestItemRunner = "= 1.1.5"`,
matching the policy already used for BilevelJuMP/HiGHS/Ipopt). Alternatively, find the item
level structurally: the child of the testset whose description ends in `.jl`. Then update the
comments to say which version runs on each leg.

## Info

### IN-01: The expected-broken key leaves out the file, and the FIT `false` key matches any `@test_broken false`

**File:** `test/runner_support.jl:92-97`, `test/expected_broken.txt:16`
**Issue:** The key is `(kind, item name, expression)`. TestItemRunner allows the same item name
in two files, so a copy of an allowed item in another file shares its allowance. The FIT
item's second entry has the expression `false`, so any `@test_broken false` added to that item
uses up the gate's allowance whenever the gate does not fire.
**Fix:** Add the file component (`path[ITEM_DEPTH-1]`) to the key. Give the gate's
`@test_broken` a distinctive expression, for example `@test_broken fit_gate_fired == false`.

### IN-02: A `TSODSO_TEST_FILES` name counts as matched even when the active set excludes all its items

**File:** `test/runtests.jl:66-74`
**Issue:** `file_hits` is incremented before set selection. With `TSODSO_TEST_SET=fast` and
`TSODSO_TEST_FILES=a.jl,slow_only.jl`, `slow_only.jl` counts as matched. Nothing from it runs,
and the run passes because `a.jl` selected items.
**Fix:** Count a hit only when `tso_selected(...)` is true.

### IN-03: The JET justification check only looks for the marker line

**File:** `scripts/jet_check.jl:93`, `scripts/jet_check.jl:260-265`
**Issue:** "Unjustified" means "the marker line is present". If someone deletes the
`# UNJUSTIFIED ...` line and leaves the signatures, they count as part of the preceding
justified group, and the check passes.
**Fix:** In check mode, require every signature line to follow a `# Group` comment, with
only signature lines and blank lines in between.

---

_Reviewed: 2026-10-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
