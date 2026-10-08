---
phase: 36-code-export-cleanup
plan: 19
subsystem: hygiene
tags: [planning-id-scrub, tests]
requires: ["36-18"]
provides:
  - test/test_planning_*.jl free of planning identifiers (classifier TOTAL 0 over the whole plan file set, 26 files)
affects: [36-20]
key-files:
  modified:
    - test/test_planning_ac_recheck.jl
    - test/test_planning_alpha_bounds_stackelberg.jl
    - test/test_planning_benders.jl
    - test/test_planning_benders_ieee13.jl
    - test/test_planning_benders_integer.jl
    - test/test_planning_bilevel.jl
    - test/test_planning_certification.jl
    - test/test_planning_certification_bilevel.jl
    - test/test_planning_certification_bilevel_interior.jl
    - test/test_planning_certification_integer.jl
    - test/test_planning_checkpoint.jl
    - test/test_planning_coupling.jl
    - test/test_planning_feasibility_oracle.jl
    - test/test_planning_follower.jl
    - test/test_planning_goldens.jl
    - test/test_planning_hardening.jl
    - test/test_planning_ieee13_short_fixture.jl
    - test/test_planning_inexact_policy.jl
    - test/test_planning_master.jl
    - test/test_planning_master_integer.jl
    - test/test_planning_nash.jl
    - test/test_planning_nash_integer.jl
    - test/test_planning_noninteger.jl
    - test/test_planning_oracle.jl
    - test/test_planning_retry.jl
    - test/test_planning_trace.jl (a few carried only whitespace changes from the formatter)
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 19: Scrub of test_planning_* Summary

About 470 classifier hit lines (plus process phrasing the classifier cannot see) in 26 `test_planning_*` files were rewritten as plain prose. Rationale, measured numbers, thesis-equation and literature references were kept. Planning-artifact citations (research and review documents, plan/task/decision/requirement IDs, "code review iteration N", `.planning/` paths, quick-task numbers, "plan-checker", "Rule 1", "USER DECISION", "gap-closure", "this session") were replaced by the fact itself or dropped. HYG-01 stays pending.

## Commits
- 11e6386: scrub test_planning_[a-l]* (task 1)
- 1a6d85e: JuliaFormatter 2.10.2 pass over [a-l] (11 files touched)
- 3a55f2c: reword remaining process phrasing ("this plan's own <interfaces>", "REVISION 2 note", "this phase") in four [a-l] files found by the extended grep
- cb7db98: scrub test_planning_[m-z]* (task 2)
- 1705baa: JuliaFormatter 2.10.2 pass over [m-z] (7 files touched)

Formatter: `check_content_loss.py HEAD` printed `OK: no content change` before each formatter commit; a final formatter run over all `test_planning_*` files is a no-op.

## Verification
- Classifier: `TOTAL 0` over `test/test_planning_*.jl`.
- `ast_equiv.jl` and `ast_equiv.jl --literals` against the pre-plan commit 50cd219 (recorded in `.planning/tmp/36/p19_start.txt`): EQUAL for all 26 files. `test_planning_goldens.jl` prints `EQUAL (numeric literals)`, so no golden, tolerance, canary number or assertion value changed.
- `thesis_tokens.py` against 50cd219: OK for all files.
- Targeted tests (0 failed, 0 errored), run sequentially in the foreground-equivalent single background job each: all 18 [a-l] files 563 pass; all 8 [m-z] files plus four re-edited [a-l] files 930 pass with the one existing `@test_broken`; post-formatter spot run of noninteger, retry, goldens, master, trace, oracle 164 pass. No full suite run (last full suite remains p13 = 32202/0/0/5).
- Grepped `scripts/`, `.github/`, `docs/make.jl`, `test/runtests.jl`: no filter references any renamed test item name.

## Environment note
`scripts/run_tests_filtered.jl` evaluates each file with `cd(test/)`, so a relative `test` entry in `JULIA_LOAD_PATH` stops resolving the test-only deps (BilevelJuMP, Ipopt) and the run aborts with `Package BilevelJuMP not found`. Use an absolute path: `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`. The files not needing test-only deps were unaffected.

## Message changes
No `src/` messages changed. Error/label string literals changed inside test files (none is asserted on by any test; `--literals` AST check EQUAL):
- `test_planning_certification_integer.jl`: error message in `enumerate_lattice` `" (WR-01 regression, Phase 24 code review) -- should be "` became `" (tie-break regression) -- should be "`.
- `test_planning_noninteger.jl`: error message `... the PVAL-04 exemption is now stale/wrong` became `... the exemption is now stale/wrong`.
- `@info`/label text: `test_planning_bilevel.jl` `"CR-01 regression threw"` became `"regression: solve threw"`; `test_planning_retry.jl` `... skipping escalation branch (WR-04)` lost `(WR-04)`.

Renamed `@testitem` names (all ID suffixes/prefixes removed; the descriptive core and the substrings "planning", the module name and tags kept; list produced from `ast_equiv.jl --strings`, 74 pairs):
- `ac_recheck`: dropped `(WR-03 iter 2)`.
- `alpha_bounds_stackelberg`: dropped `(Option A, Phase 31 WR-05/WR-03, Plan 31-07)`.
- `benders`: dropped `(WR-04)`, `(IN-02/IN-03)`.
- `benders_integer`: `byte-identical default path (PVAL-02 golden) ... (Blocker 2 regression)` became `bit-for-bit identical default path (golden) ...`; `WR-01 _oracle_or_infeasible ...` lost `WR-01`; dropped `(WR-01, Phase 31 code review)`.
- `bilevel`: dropped `(WR-01)`, `(WR-03)`, `(iteration-2 CR-01)`, `(iteration-2 WR-02)`.
- `certification`: `PVAL-01 permanent invariant` became `permanent invariant`.
- `certification_bilevel`: dropped `(BILEV-02)`.
- `certification_bilevel_interior`: dropped `(BILEV-02 BLOCKER-1)`, `(WR-07)`, `(WR-08)`.
- `certification_integer`: `INT-03 exhaustive-enumeration certification of the D-12 tiny instance (D-15 certificates 1+2, D-16 visibility, D-11 non-blocker documented) -- FIXED in gap-closure 24-05.1 (...)` became `exhaustive-enumeration certification of the canonical tiny instance (certificates 1+2, no-good visibility, secondary-certificate non-blocker documented) -- FIXED (...)`; dropped `(FIX-06, Phase 27 plan 27-01)`, `(CR-01, 27-REVIEW.md)`, `(plan-checker Blocker 2, closed for good)`.
- `checkpoint`: `(WR-03 filename contract)` became `(filename contract)`; dropped `(CR-02)`.
- `coupling`: dropped `Pitfall 3 regression`, `Revision 1` (two items), `PVAL-04`, `(WR-01, Phase 31 code review)`.
- `goldens` (three items): dropped `(PVAL-02)`.
- `hardening`: `measured 47-66 iters` became `measured 47 to 66 iters`.
- `inexact_policy`: dropped `(T-30-09, WR-02 iter 2)`, `(WR-06 backstop, WR-02 iter 2)` (now `(backstop)`), `(CR-01/CR-03)`, `(CR-02)`, `(CR-02 iter 2)`, `(WR-01 iter 2)`, `(WR-06 iter 2)`.
- `master`: dropped `(T-11-03)`, `(WR-03)`, `(Option A, Phase 31 WR-03, Plan 31-07)`, `(IN-03)`; `byte-identical` became `bit-for-bit identical`.
- `master_integer`: dropped `D-02`, `Assumption A1`, `(WR-02)`, `(IN-03)`, `(RESEARCH.md Finding 2)`, `(24-RESEARCH.md Priority Finding 1)`, `(Option A, ...)`; `(MILP analog of Pitfall M1)` became `(MILP analog of the continuous zero-cut solve)`.
- `nash`: dropped `PVAL-04`, `Pitfall 1`, `BILEV-06a/06b`, `CR-01/CR-02`, `NASH-04`, `existing Phase 11/12 call sites` became `existing call sites`, `per CONTEXT.md's N=2-hand-checkable/N=3-probe-only scope` became `N=2 is hand-checkable and N=3 is probe-only`, `Revision 1`.
- `nash_integer`: dropped `BILEV-07`, `WR-02`/`WR-06`, `(CR-01)`, `(CR-01, live)` (now `(live)`).
- `noninteger`: `planning PVAL-04: no-binaries guard ...` became `planning noninteger: no-binaries guard ...`.
- `oracle`: dropped `(D-06)`, `PF-04`, `(CR-03)`.
- `retry`: dropped `(CR-01)`.
- `trace`: `byte-identical to pre-24-03 behavior` became `bit-for-bit identical to the earlier behavior`.

## Hand-edited MIXED lines
Lines that combined an ID with a thesis or literature reference were edited by hand with the reference verbatim (BilevelJuMP/Laporte-Louveaux/Gauss-Seidel/Kelley references, thesis-equation-number comments in the oracle and feasibility files). `thesis_tokens.py` confirms no token lost.

## Deviations from Plan
- [Rule 1] Process wording that the classifier cannot catch was reworded: `Rule 1 auto-fix`, `DEVIATION`, `LOCKED USER DECISION`, `Claude's Discretion`, `plan-checker`, `Blocker N`, `Revision N`, `Pitfall N`, `this session`, `gap-closure`, `scratchpad/probe_*.jl` file names, `byte-identical`, `the plan's own <interfaces>/<behavior>`, `STATE.md` blocker mention, a `git stash` mention in a comment, `.planning/` artifact names. Large historical narratives (hardening iteration-floor note, certification_integer fix history) were condensed to technical rationale and measured numbers.
- The extended grep for these phrases found leftovers in four already-committed [a-l] files; they were fixed in a separate commit (3a55f2c) and re-tested in the [m-z] run.
- Variable names `NO_DEVIATION_TOL` and header words such as `NON-BLOCKER` are code identifiers/prose, not process IDs, and were kept.
- Dates of measurements (for example `2026-10-01`) were kept; they are data provenance, not planning IDs.
- Runtime-string literals that are not `@info`/`println` labels (two error messages in test files, listed above) were changed because the classifier flags them; none is asserted on.

## Known Stubs
None.

## Self-Check: PASSED
