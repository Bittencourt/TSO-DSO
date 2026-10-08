---
phase: 37-test-infrastructure-repo-hygiene
fixed_at: 2026-10-06T00:00:00Z
review_path: .planning/phases/37-test-infrastructure-repo-hygiene/37-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 12
skipped: 0
status: all_fixed
---

# Phase 37: Code Review Fix Report

**Fixed at:** 2026-10-06
**Source review:** .planning/phases/37-test-infrastructure-repo-hygiene/37-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12 (2 critical, 10 warning). 6 of the 7 info items were also fixed
  because each was small (IN-01 to IN-07; IN-04 is documentation only).
- Fixed: 12. WR-07 is documentation only and **needs a user decision** (see below).
- Skipped: 0

Some findings touch the same lines, so they share a commit: WR-01, WR-09, WR-10 and IN-03
are all in `test/runtests.jl` and `test/runner_support.jl`; WR-02, WR-03 and IN-05 are all in
the JET ratchet.

## Fixed Issues

### CR-01: The FIT gate's `ALMOST_` prefix match turns near-infeasibility into an allowed Broken

**Files modified:** `test/test_pricing_welfare.jl`, `test/expected_broken.txt`
**Commit:** 37c961c
**Applied fix:** The gate now requires all three of these:
- `termination_status == MOI.ALMOST_OPTIMAL`;
- `primal_status == MOI.NEARLY_FEASIBLE_POINT`;
- the error was raised by `assert_solved!` called directly from `fit_baseline`. This is the
  seed AC-PF solve. The check reads the caught backtrace, so a failure from
  `_fit_opt_solve` (FIT-OPT) or another solve still fails.

Every other status or site is rethrown.
Verified with `scripts/run_tests_filtered.jl file:test_pricing_welfare.jl`:
- 1.12.7: gate `@info` printed (ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT / ALMOST_SOLVED), Pass 33, Broken 1.
- 1.12.5 (`+release`): no gate, Pass 38, Broken 1 (the thesis cross-check, gap 0.25).

### CR-02: The committed PV-boom report still describes the old 13:18 planning window

**Files modified:** `scripts/pv_boom_case_study.jl`, `scripts/lib/pv_boom_common.jl`, `scripts/pv_boom_report.jl`
**Commit:** 65db3a6 (artifacts regenerated in 35e8562)
**Applied fix:**
- The case study now stores `planning_hours` in `results.jld2`.
- `pv_boom_load_results` returns `planning_hours`. For older results files it falls back to
  the `const PLANNING_HOURS` line in `pv_boom_case_study.jl`. It errors unless the window is
  contiguous and its length equals `size(nash_result.z, 2)`.
- Sections 3.5 and 4.6 interpolate the window. "afternoon" and "13 through 18" are gone.
- The SVG citation is now a symbol citation (`distributor_calibration`). The other line
  citations in the report point at src files that did not change in this phase.
- `report.html` is gitignored. It was regenerated locally from the rerun results, so it is
  not committed.

### WR-01: The expected-broken guard is item-granular

**Files modified:** `test/runner_support.jl`, `test/runtests.jl`, `test/expected_broken.txt`, `scripts/run_tests_filtered.jl`, `README.md`
**Commit:** 928acac
**Applied fix:**
- New `expected_broken.txt` format: `kind | item | test expression | reason`. Each line
  allows one record and repeated lines allow more, so the list is compared as a multiset.
- The record key is `(kind, item at path depth 4, nested testsets / string(orig_expr))`.
- These now fail: a new `@test_broken`, `broken=` or `@test_skip` in an allowed item; a
  second firing of an allowed site; a record in a nested testset; a testset that only
  shares an allowed item's name; a skip at a broken-only site.
- The FIT item now has two entries, `gap < 0.1` and `false`.
- `run_tests_filtered.jl --selftest` covers all of these plus the real `broken=` key
  format, and passes on 1.10.11 and 1.12.5.
- A live runtests run passed the guard on 1.12.7 (3 allowed records) and on 1.12.5
  (2 allowed records).

### WR-02: The JET ratchet merges duplicate reports and accepts UNJUSTIFIED entries

**Files modified:** `scripts/jet_check.jl`, `scripts/jet_baseline.txt`, `README.md`, `scripts/README.md`
**Commit:** 3f9a996
**Applied fix:**
- Signatures keep their duplicates and the diff compares multisets.
- Check mode exits 1 while the baseline still contains the UNJUSTIFIED marker.
- `--update` exits 1 when it writes UNJUSTIFIED entries. This is documented in the script
  header and both READMEs.
- The multiset check found one hidden duplicate: a second `setindex!(::Nothing, ...)`
  report for the same guarded `integer_buffer[i] = ...` line in `run_nash!`. It now appears
  twice in Group 2, with a justification. I checked the guard (`integer !== nothing`) in the
  source.
- Verified on 1.12.7: 12 current, 12 baseline, 0 NEW, 0 FIXED, rc 0.
- On a baseline missing one entry, `--update` exits 1 and the following check exits 1.
- The selftest passes on 1.10.11 and 1.12.5.

### WR-03: The JET CI job floats on '1.12'

**Files modified:** `.github/workflows/CI.yml`
**Commit:** 3f9a996
**Applied fix:** The JET job is pinned to `version: '1.12.7'`, the patch recorded in the
baseline header. A comment says to bump it together with `jet_check.jl --update`. The
baseline header now says that CI pins this patch. The YAML parses.

### WR-04: `scripts/flake_rate.jl` crashes on Julia 1.10

**Files modified:** `scripts/flake_rate.jl`
**Commit:** 37dfe63
**Applied fix:** `counts_from` handles both forms: the 9-tuple from
`Test.get_test_counts` on 1.10 and the `TestCounts` struct on 1.11+. Verified on 1.10.11:
the selftest runs a real testset, and a live child run of a small target reported
`outcome=pass passes=2`.

### WR-05: The flake harness reports `pass` when the child selects zero items

**Files modified:** `scripts/flake_rate.jl`, `scripts/README.md`
**Commit:** 37dfe63
**Applied fix:**
- The child counts filter matches.
- Zero selected items, or zero recorded results, give `outcome=no_items`. This is never
  counted as a pass, and the child exits 1.
- The parent writes the CSV, then exits 1 if any run was `no_items`.
- Verified on 1.10.11 with a target whose item name matches nothing: `no_items`, rc 1.

### WR-06: `check_scripts_index.py` matches by substring

**Files modified:** `.github/scripts/check_scripts_index.py`
**Commit:** 3789329
**Applied fix:**
- Matching uses whole path tokens taken from inline backtick spans and fenced blocks. A
  token right after `:` (a `file:` filter value) is not treated as a path.
- A bare basename counts only when it is unique among tracked files.
- `scripts/`-prefixed and scripts-relative tokens are checked for staleness (jl, sh, py,
  toml, txt, dss).
- The selftest now includes the reviewer's probes: overlapping names, duplicate basenames,
  and the `scripts/gone.jl` / `b.toml` / `foo.py` stale case.
- The real index passes. Removing a real entry is detected.

### WR-07: The core acceptance gate (SC3, ADMM≈centralized) no longer runs on any PR — NEEDS USER DECISION

**Files modified:** `README.md`
**Commit:** c2a9069
**Applied fix:** This change is documentation only, as instructed. The CI trigger shape is
unchanged because the earlier choice was "slow nightly + dispatch". The README testing
section now states the tradeoff: no push or PR run executes the SC3 acceptance,
ADMM cross-validation or planning-certification items, and a regression in them first
shows up in the next nightly run on `main`. **Options for the user:**
1. Add `push: branches: [main]` to `.github/workflows/slow.yml`. Every merge then runs the
   full suite; PRs still run only `fast`.
2. Move the IEEE-13 SC3 acceptance item (about 101 s locally) and the IEEE-13 ADMM
   cross-validation item (about 142 s) back to `fast`. This adds about 4 minutes to every
   push and PR run.

### WR-08: The PV-boom Part A2 "genuinely INEXACT" finding contradicts its own numbers

**Files modified:** `scripts/pv_boom_case_study.jl`, `scripts/lib/pv_boom_common.jl`, `scripts/pv_boom_report.jl`, `results/pv_boom/findings.txt`, `results/pv_boom/summary.csv`
**Commit:** 35e8562
**Applied fix:**
- **What changed:** only the wording logic. Both solves, their options (`allow_local = true`
  on the AC solve), the gates and the tolerances are unchanged.
- **How the wording is chosen:** the case-study findings and the report choose the text
  from the numbers, using a wording-only threshold of 1e-6.
- **Text for a negative `obj_gap`:** it now says that:
  - the SOC cone is tight (`socp_maxgap` 2.585e-8);
  - `obj_gap` = -0.477 means the AC solve (local NLP, `allow_local = true`) beat its own
    convex relaxation, so the two solves are not the same problem solved to optimality;
  - the per-hour gaps therefore measure a model or solve mismatch, not a relaxation gap;
  - the question is UNRESOLVED.
- **Otherwise:** the original "genuinely INEXACT" text is kept.
- **Regeneration:** the case study is cheap, so instead of hand-correcting `findings.txt` I
  reran it in full on 1.12.7. Compared with the previous committed run, only
  `exact_maxgap`/`socp_maxgap` changed (at the 1e-9 to 1e-8 level), welfare changed in the
  11th significant digit, and the Part A2 text is new.
- **Other report fixes:** a wrong cross-reference (Section 4.4 -> 4.5). Two "genuine
  inexactness" phrasings in Sections 3.4 and 4.2 now say "can lose tightness" and "probe".

### WR-09: Test discovery still parses the whole repo

**Files modified:** `test/runtests.jl`
**Commit:** 928acac
**Applied fix:**
- `runtests.jl` now calls `TestItemRunner.run_tests(test_dir; filter, verbose)` instead of
  `@run_package_tests`. Discovery and `@testsetup` resolution then come only from `test/`,
  and `.claude/worktrees` is never parsed. `run_tests_filtered.jl` and `flake_rate.jl`
  already used this path.
- Side effect: test/ has no package name, so items no longer get an implicit
  `using TSODSO`. I scanned all 511 items: the only 2 without `using TSODSO` don't use it.
- This is documented in the runtests.jl header and the README.

### WR-10: `TSODSO_TEST_FILES` entries are not trimmed

**Files modified:** `test/runner_support.jl`, `test/runtests.jl`, `README.md`
**Commit:** 928acac
**Applied fix:**
- Entries are trimmed, and an empty entry throws.
- The guards fail when a requested basename matches no item under test/.
- Verified: `" a.jl, b.jl "`-style input works (live run on 1.12.7). `...,nosuch.jl` fails
  the guard on 1.12.5 with "TSODSO_TEST_FILES entry matches no @testitem: nosuch.jl".

### Info items also fixed

- **IN-01** (`src/solver/factory.jl`, commit 6edb457; the baseline comment is in 3f9a996):
  the `_objective` docstring now says "return-type conversion (convert + typeassert)" and
  mentions the `MethodError` for a multi-objective model.
- **IN-02** (`src/models/stochastic_welfare.jl`, 6edb457): dropped the redundant
  `Float64(...)`. JET is still 12/12 with 0 NEW and 0 FIXED.
- **IN-03** (928acac): the runtests.jl header comment is corrected.
- **IN-04** (`test/fixtures_retry.jl`, fadf44a): FlakeRetry is documented as reserved, with
  a note about the `ConvergenceError` default. The default itself is unchanged.
- **IN-05** (3f9a996): a `#` comment after the UNJUSTIFIED marker ends the unjustified
  block. Covered by the selftest.
- **IN-06** (`.github/scripts/check_suite_log.py`, bc679e2): the canary `iters` and
  `welfare` checks are anchored on the canary item's own `@info` block. Checked against a
  real full-suite log.
- **IN-07** (35e8562): the calibration header says that Part A moved because of upstream
  src changes, not the re-tune.

## Verification summary

- JuliaFormatter 2.10.2 was run on every touched src/test file. After the final run the
  working tree was clean (no formatter diff).
- `check_script_api.jl`: OK (40 files).
- `check_planning_ids.py`: OK.
- `check_scripts_index.py` (and its selftest): OK.
- CI.yml parses as YAML. `slow.yml` is untouched.
- Exports are untouched, so the direct Aqua script was not rerun.
- No solver behaviour, gate, tolerance, canary or golden was changed.
- The `--broken N` default (5) in `check_suite_log.py` still holds. Only one of the FIT
  item's two allowed sites can fire in a run.

---

_Fixed: 2026-10-06_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
