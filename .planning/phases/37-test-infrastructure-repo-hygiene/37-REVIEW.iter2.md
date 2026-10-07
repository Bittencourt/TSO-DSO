---
phase: 37-test-infrastructure-repo-hygiene
reviewed: 2026-10-06T00:00:00Z
depth: standard
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
  critical: 2
  warning: 10
  info: 7
  total: 19
status: issues_found
---

# Phase 37: Code Review Report

**Reviewed:** 2026-10-06
**Depth:** standard (Phase 37 diff, `08081f8^..HEAD`)
**Files Reviewed:** 57
**Status:** issues_found

## Summary

The src/ JET cleanup is fine. All 24 `_objective` call sites are mechanical
`objective_value(m)` -> `_objective(m)` swaps. None used `result=k`, none can reach a multi-objective
model, and the non-OPTIMAL paths behave as before: `objective_value` throws exactly as it did, and
every caller already runs `assert_solved!` or a status check first. The `pf_vars` local copy changes
no behaviour. The runner's set selection fails closed on a bogus `TSODSO_TEST_SET` and on an
empty selection. The step-level `env:` does reach `Pkg.test` through julia-runtest.

The problems are in the guards. Several new checks fail open, and I confirmed each with an
adversarial input (below):
- The FIT gate covers more statuses than the plan allowed.
- The expected-broken guard works per item, not per assertion.
- The JET ratchet merges duplicate reports and accepts UNJUSTIFIED entries.
- The scripts-index check matches by substring.
- The flake harness reports "pass" when it selects no items, and it crashes on Julia 1.10.

The PV-boom re-tune also left the committed HTML report describing the old 13:18 window.

Adversarial probes run:
- Synthetic nested testsets on Julia 1.10.11 and 1.12.7, fed through `broken_records` + `is_allowed`. A new `@test_broken` inside an allowed item, and inside a nested testset of an allowed item, is reported as **allowed**. A `@test_skip` inside an allowed `broken` item is correctly rejected.
- `check_scripts_index.missing_entries(["scripts/boom_report.jl", "scripts/archive/pv_boom_report.jl", ...], "`pv_boom_report.jl`")` returns `[]`, so all three count as indexed.
- `stale_entries([...], "`scripts/gone.jl` `b.toml` `foo.py`")` returns `[]`.
- `Test.get_test_counts` returns a `Tuple` on Julia 1.10.11 and a `Test.TestCounts` on 1.11/1.12.

## Critical Issues

### CR-01: The FIT gate's `ALMOST_` prefix match turns near-infeasibility into an allowed Broken

**File:** `test/test_pricing_welfare.jl:332-341` (with `test/expected_broken.txt:10`)

**Issue:** The gate treats any `SolveFailedError` whose status *starts with* `"ALMOST_"` as the known
1.12.7 flake. In MOI that prefix also covers `ALMOST_INFEASIBLE`, `ALMOST_DUAL_INFEASIBLE` and
`ALMOST_LOCALLY_SOLVED`, which are different failure modes. Two other problems widen the hole:
- `fit_baseline` runs several solves (FIT-OPT, social re-solve, site-3 retry). The gate does not care which one failed.
- `expected_broken.txt` allows `broken` for this item regardless of cause.

So a real regression that makes any FIT solve near-infeasible, on any Julia patch, becomes a
`@test_broken false`. The run stays green, and the ratio golden, the band check and the thesis
cross-check are all skipped. The plan (37-05-PLAN, Task 1) restricted the gate to
`ALMOST_OPTIMAL`/`ALMOST_SOLVED`. The 37-05 summary confirms the observed status was
`ALMOST_OPTIMAL` / `NEARLY_FEASIBLE_POINT`. CI's `'1.12'` leg resolves to 1.12.7+, so on that leg
the golden is already never asserted. The prefix match quietly widens that blind spot to every
leg.

**Fix:** Pin the gate to the observed outcome:
```julia
if err isa SolveFailedError &&
   err.termination_status == MOI.ALMOST_OPTIMAL &&
   err.primal_status == MOI.NEARLY_FEASIBLE_POINT
    return err
end
rethrow()
```
Optionally also record which site raised it (for example `occursin("FIT-OPT", err.msg)`), so a
failure at a different site still fails the run.

### CR-02: The committed PV-boom report still describes the old 13:18 planning window, and its source citation is stale

**File:** `scripts/pv_boom_report.jl:133`, `scripts/pv_boom_report.jl:623-625`, `scripts/pv_boom_report.jl:731`; committed artifact `results/pv_boom/report.html:568`

**Issue:** The re-tune moved `PLANNING_HOURS` from `13:18` to `11:16` in
`scripts/pv_boom_case_study.jl:467`. The report narrative is a hardcoded string and still says
"over the afternoon PV-peak sub-horizon hours 13 through 18" (line 624-625) and "higher
PV-penetration afternoon flow" (line 731). The regenerated `results/pv_boom/report.html` contains
"hours 13 through 18", while `findings.txt` (same run) says 11:16. This contradicts the file's own
contract on line 8 ("Every quoted result number is computed live from data/pv_boom/results.jld2"),
and it is exactly the window the re-tune changed. The SVG citation
`scripts/pv_boom_case_study.jl:515-527, distributor_calibration` (line 133) is also stale: the
33-line calibration header pushed `distributor_calibration` down to line 560.

**Fix:** Store `planning_hours` in `results.jld2` from the case study (or derive it from
`size(nash_result.z, 2)` plus a stored first hour), and interpolate it into the narrative:
```julia
"... over the midday PV-peak sub-horizon hours $(first(ph)) through $(last(ph)) " *
"(<code>T_planning = $(length(ph))</code>)"
```
Replace the line-number citation with a symbol citation (`distributor_calibration` in
`pv_boom_case_study.jl`), then regenerate `report.html`.

## Warnings

### WR-01: The expected-broken guard is item-granular, so new Broken/skip records inside allowed items pass

**File:** `test/runner_support.jl:89`, `test/expected_broken.txt:7-12`

**Issue:** `is_allowed` accepts a record if *any* path component equals an allowed item name. I
confirmed on 1.10.11 and 1.12.7 that each of these is accepted:
- a second `@test_broken` added to an allowed item;
- a `@test_broken` inside a nested `@testset` of an allowed item;
- a `@testset` anywhere whose description equals an allowed item name.

Four allowed items are large acceptance/golden items (acceptance SC3, ieee13 ground golden,
thesis_repro sign-flip, FIT golden). A new `broken=` or `@test_broken` in any of them never trips
the guard. The FIT item's single allowance also absorbs both its regimes (CR-01). This weakens
the stated "observed is a subset of allowed" guarantee.

**Fix:** Allow per site rather than per item. Either allow `(kind, item, count)` and fail when the
observed count of records under that item exceeds `count`, or key on `string(r.orig_expr)` plus the
item name. Count only the item-level path component (index 4 under TestItemRunner 1.1.5's
`TSODSO / Package / file / item` layout), not any component.

### WR-02: The JET ratchet merges duplicate reports and accepts UNJUSTIFIED entries

**File:** `scripts/jet_check.jl:45`, `scripts/jet_check.jl:62-65`, `scripts/jet_check.jl:187-191`, `scripts/jet_check.jl:205-208`

**Issue:**
1. `current_signatures` runs `unique` and `diff_signatures` uses `Set`s. A new report whose
   normalized signature matches a baselined one (no line numbers) is invisible. Examples: another
   `iterate(::Nothing)` or `setindex!(::Nothing, ...)` in `run_nash!`, or any new
   `objective_value` union split routed through `_objective`. The ratchet does not tighten on
   multiplicity.
2. `--update` always exits 0, and check mode only prints `WARNING: baseline still contains
   UNJUSTIFIED entries` and still returns 0. Running `--update` and committing the result passes
   CI with unjustified entries, which defeats the "every entry justified" format the baseline
   header promises.

**Fix:** Keep a multiset: `countmap` of signatures in both current and baseline, and fail when the
current count exceeds the baseline count. In check mode, `return 1` when `UNJUSTIFIED_MARK` is
present in the baseline file.

### WR-03: The JET CI job floats on `'1.12'`, so a Julia patch release can break CI with no code change

**File:** `.github/workflows/CI.yml:65-88`, `scripts/jet_baseline.txt:3`

**Issue:** The baseline was recorded on Julia 1.12.7 / JET 0.11.6, and signatures embed
inferred type strings (for example the `kwcall(::NamedTuple{(:atol,), ...})` line). `setup-julia`
with `'1.12'` takes the newest 1.12 patch, and `version_warning` only prints a warning. When 1.12.8
changes inference output, the job goes red with NEW/FIXED churn unrelated to the commit.

**Fix:** Pin the job's version to the baseline's patch, `version: '1.12.7'`, and bump it together
with `jet_check.jl --update`. Alternatively, make a header/runtime version mismatch exit 2 with an
explicit message.

### WR-04: `scripts/flake_rate.jl` crashes on Julia 1.10, the project's compat floor

**File:** `scripts/flake_rate.jl:214-219`

**Issue:** `Test.get_test_counts` returns a 9-tuple on Julia 1.10 (verified on 1.10.11) and only
became a `TestCounts` struct in 1.11. `c.passes` / `c.cumulative_passes` throw on 1.10. The child
then never prints `FLAKE_RESULT`, and every row is recorded as `outcome=error`. Measured flake
rates on the LTS would read 100% error rather than a real measurement.

**Fix:**
```julia
c = Test.get_test_counts(ts_ref[])
if c isa Tuple
    np, nf, ne, nb, ncp, ncf, nce, ncb = c[1:8]
    return (passes = np + ncp, fails = nf + ncf, errors = ne + nce, broken = nb + ncb, secs)
end
```
Alternatively, refuse to run on `VERSION < v"1.11"` with a clear message.

### WR-05: The flake harness reports `pass` when the child selects zero items

**File:** `scripts/flake_rate.jl:186-192`, `scripts/flake_rate.jl:200-232`

**Issue:** `verify_targets` only checks that the item name appears as text in the file. The child
never asserts that `item_filter` matched anything at runtime. Exact-name matching on long names
with Unicode characters (`≈`, `—`) is easy to break: a name with an escape, an interpolation, or
one renamed between the parent's check and the child's run gives 0/0/0/0 counts. `outcome_of`
maps that to `"pass"`, which inflates the measured pass rate.

**Fix:** Count matches inside the filter closure, and in `child_main` print
`outcome=error` (or `error("no items selected")`) when the count is 0. Also check
`passes + fails + errors + broken > 0`.

### WR-06: `check_scripts_index.py` matches by substring and ignores `scripts/`-prefixed stale references

**File:** `.github/scripts/check_scripts_index.py:20-28`, `.github/scripts/check_scripts_index.py:31-42`

**Issue:**
- `base not in readme_text` is a substring test. `boom_report.jl`, `archive/pv_boom_report.jl` and `pv_boom_report.jl` are all "indexed" by one mention of `pv_boom_report.jl` (verified). Two files with the same basename in different directories are also covered by one entry, although the docstring promises "by basename or by its path relative to scripts/".
- `stale_entries` skips every token starting with `scripts/`, so a stale `` `scripts/gone.jl` `` reference is never reported.
- Stale detection only covers `.jl|sh|dss|txt`.

The selftest only uses non-overlapping names, so it cannot catch any of this.

**Fix:** Tokenize the README into backticked or path-like tokens. Require each tracked file's
relative path (or its basename, when that basename is unique) to appear as a whole token. For
stale detection, strip a leading `scripts/` and check against `rels` instead of skipping. Add
selftest cases for overlapping names.

### WR-07: The core acceptance gate (SC3, ADMM≈centralized) no longer runs on any PR

**File:** `test/test_acceptance.jl:23-24`, `test/test_admm.jl` (crossval item), `.github/workflows/slow.yml:4-17`

**Issue:** The SC3 acceptance item, the ADMM cross-validation item and all
planning-certification items are now `:slow`. Per-push CI runs only `fast`. `slow.yml` runs only on
cron (default branch only) or manual dispatch. A PR that breaks the project's headline
correctness claim (exact relaxation + DADP + ADMM≈centralized) merges green, and the first signal
arrives the next night, on `main`. Per-push runtime is the stated goal, but none of the core-value
end-to-end gates now protects merges.

**Fix:** Keep at least one cheap core gate in `fast`, for example the IEEE-13 SC3 acceptance item
(or a reduced-horizon variant). Alternatively, add a `pull_request` trigger to `slow.yml`, gated on
a label or on changes under `src/`.

### WR-08: The PV-boom Part A2 "genuinely INEXACT" finding contradicts its own numbers

**File:** `scripts/pv_boom_case_study.jl:387-421`, `scripts/pv_boom_case_study.jl:751-757`; artifact `results/pv_boom/findings.txt`

**Issue:** The regenerated findings report the high-PV fixture as "genuinely INEXACT at 10/24
hours". In the same run, `socp_maxgap = 2.586680e-08` (cone tight) and
`obj_gap (SOCP - AC) = -4.77e-01`. A negative gap means the AC "oracle" found *higher* welfare than
its convex relaxation. That is impossible if both solve the same problem. The cause is that the AC
solve passes `allow_local = true` while the SOCP solve does not (lines 395-403), so they are
different models. The only guard is `isempty(inexact_hours)`, so this inconsistency was
regenerated and committed without comment. The script's own contract says to stop and report a
discrepancy.

**Fix:** Pass identical options to both solves (drop `allow_local` from the AC call, or add it to
the SOCP call). Add a guard `ac_report.obj_gap >= -tol || error("AC beat its relaxation: model mismatch")`
and regenerate `findings.txt`.

### WR-09: Test discovery still parses the whole repo, and `@testmodule` resolution depends on directory order

**File:** `test/runtests.jl:52-61`, `test/runner_support.jl:39`

**Issue:** The test/-only filter applies to `@testitem`s only. TestItemRunner 1.1.5 still
`walkdir`s the whole package root, so `.claude/worktrees/*`, `.planning/**`, `scripts/` and
`results/` are all parsed:
1. A syntax error in any `.jl` file anywhere, including an agent worktree, aborts the whole run.
2. `testsetups[name]` is overwritten by the *last* file walked that defines that name. Main-tree
   `test/` currently wins only because `test` sorts after `.claude`/`.planning`. A future top-level
   directory sorting after `test` (for example `tmp/`, `worktrees/`) that holds a copy of a fixture
   would silently replace the fixture module used by every item.

**Fix:** Call `TestItemRunner.run_tests(joinpath(@__DIR__); filter = filt)` (root = `test/`)
instead of `@run_package_tests`, as `flake_rate.jl` and `run_tests_filtered.jl` already do. Then
both items and setups come only from `test/`.

### WR-10: `TSODSO_TEST_FILES` entries are not trimmed, and a typo is accepted silently

**File:** `test/runner_support.jl:22-25`

**Issue:** `TSODSO_TEST_FILES="a.jl, b.jl"` yields `" b.jl"`, which matches nothing. Because the
guard only requires `selected[] > 0`, the run passes with `b.jl` silently skipped. The same applies
to misspelled names. `run_tests_filtered.jl` deliberately fails closed per file, so the two entry
points are inconsistent.

**Fix:** `String.(strip.(split(s, ",")))`, then fail when any requested basename matches zero items
(track matches per name in the filter, as `run_filtered` does).

## Info

### IN-01: The `_objective` docstring calls the conversion an assertion

**File:** `src/solver/factory.jl:235-242`

**Issue:** A `f(x)::Float64 = ...` return annotation runs `convert(Float64, ...)` followed by a
typeassert, not a bare assertion. The baselined JET entry is itself the `convert(::Type{Float64},
::Vector{Float64})` report. Behaviour is fine for `Float64`. If a multi-objective model ever
appears, it fails with a `convert` `MethodError` rather than a clear message.
**Fix:** Reword the docstring to "return-type conversion", or use `objective_value(model)::Float64`
(a real typeassert) with an explicit error for `Vector` results.

### IN-02: Redundant `Float64(...)` around `_objective`

**File:** `src/models/stochastic_welfare.jl:463`
**Issue:** `Float64(_objective(model))`: `_objective` already returns `Float64`.
**Fix:** Drop the outer `Float64(...)`.

### IN-03: The runtests header comment still says items under `src/` are discovered and run

**File:** `test/runtests.jl:3-5`
**Issue:** "TestItemRunner discovers every `@testitem` under `test/` (and `src/`)": the new filter
excludes anything outside `test/`. Lines 40-44 contradict this.
**Fix:** Update the comment.

### IN-04: `FlakeRetry` is exercised only by its own unit tests

**File:** `test/fixtures_retry.jl`, `test/test_flake_retry.jl:3-4`
**Issue:** No production item uses `with_solve_retry`, so the "retries the solve, never the @test"
contract has no real consumer. Default `retry_on` also retries `ConvergenceError`. For a
deterministic ADMM this just repeats the same failure up to 3 times, which costs time and adds no
information.
**Fix:** Either wire it into the measured-flaky items, or document it as reserved. Consider leaving
`ConvergenceError` out of the default `retry_on`.

### IN-05: `jet_check.jl --update` moves trailing justified groups back under the UNJUSTIFIED marker

**File:** `scripts/jet_check.jl:76-89`
**Issue:** Once the marker line is seen, `in_unjust` stays `true` until EOF. If a user justifies
entries by adding a `# Group N` comment *below* the marker without deleting the marker, the next
`--update` drops those signatures from their group and re-appends them as unjustified.
**Fix:** Reset `in_unjust = false` on any `#` comment line that follows the marker.

### IN-06: The canary log check matches any `welfare = -4823.x` line in the log

**File:** `.github/scripts/check_suite_log.py:86-91`
**Issue:** `iters = 56` and the welfare value are searched anywhere in the log, not in the canary
item's output. Another item printing a near-identical welfare would satisfy the check. This was
equally true of the previous exact-string match, so the risk is low.
**Fix:** Anchor on a canary-specific prefix in the canary item's `@info`/`println`.

### IN-07: The PV-boom header says the window is "the ONLY fixture change", but Part A sweep results also moved

**File:** `scripts/pv_boom_case_study.jl:27-60`; artifact `results/pv_boom/findings.txt`
**Issue:** Part A welfare at `pv_mult >= 1.0` and the ADMM cross-check (`iters` 42 -> 92,
`dadp_maxgap` 0.064 -> 0.18) changed in the committed findings. Part A does not use
`PLANNING_HOURS`, so this is src drift since the previous run, but nothing in the header or
summary records it.
**Fix:** Add one line to the calibration header or the findings stating that Part A numbers moved
because of upstream model changes since the last run, not the re-tune.

---

_Reviewed: 2026-10-06_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
