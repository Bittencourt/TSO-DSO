---
phase: 46-ieee-8500-headline-measurement-go-no-go
plan: 05
subsystem: measurement data / literate docs / requirement closure
tags: [ieee8500, scenario, go-no-go, docs, literate, memory, requirements]

requires:
  - phase: 46-03
    provides: committed recorded_no_go row, tested scenario point script
  - phase: 46-04
    provides: orchestrator-written measured row (refused_certificate) and two wrapper rows for p46-scn-ieee8500-d10-T10
provides:
  - committed measured T = 10 Scenario-path row and its wrapper rows and runs/ evidence files
  - dated docs section "Headline measurement and go/no-go" in docs/literate/ieee8500_scaling.jl, computed from four committed CSVs with a Base-only quote-aware reader
  - SCALE-07 and SCALE-08 closed in REQUIREMENTS.md; ROADMAP Phase 46 plan list and 5/5 progress row
affects: [orchestrator: full detached suite and full docs build; phase verification]

tech-stack:
  added: []
  patterns:
    - "Base-only quote-aware CSV line splitter with a per-row field-count check (quoted free text in non-last columns)"
    - "Docs asserts that the committed decision row equals its recomputation from the source rows"
    - "Status-branched prose generated in code so any measured outcome reads plainly"

key-files:
  created:
    - .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-05-SUMMARY.md
    - results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.{free_before,time,pid,oom_kernel,oom_earlyoom}
  modified:
    - results/ieee8500_benchmark/scenario_table.csv
    - results/ieee8500_benchmark/point_resources.csv
    - docs/literate/ieee8500_scaling.jl
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "Both wrapper rows for the label are kept (append-only file); the last wrapper row joins the measured row, checked by peak_rss_kb == vmhwm_kb and the 5.5 GiB floor in its args"
  - "runs/ evidence files are committed because earlier runs' files (including .pid) are tracked; scratchpad logs are not committed"
  - "The docs compute the pre-flight startup footprint from the second attempt's two committed readings (0.921 GiB), because the first attempt's in-script reading was replaced by the keyed upsert and survives only outside the repository"
  - "The docs reader is quote-aware instead of split(limit = ncols), because memory_attribution.csv and density_sweep.csv carry quoted free text in columns that are not last"

requirements-completed: [SCALE-07, SCALE-08]

duration: ~15min
completed: 2026-11-05
---

# Phase 46 Plan 05: Measured rows, go/no-go docs section and requirement closure Summary

**The measured T = 10 IEEE-8500 Scenario-path row (`refused_certificate`, 5 iterations, gap ratio 309.67, VmHWM 6,059,204 kB = 5.779 GiB) is committed together with both of its wrapper rows. The scaling page has a new dated section that prints, from the CSVs, the NO-GO threshold verdict (11.209 and 11.520 GiB against 10.0), B1 as a measured bound, B2 as an earlyoom-dependent estimate, the counter-fact, the measured table with its path-divergence label, the pre-flight startup-footprint effect and the supersessions. SCALE-07 and SCALE-08 are closed.**

## Performance

- **Duration:** about 15 minutes of executor time. The page run took 1m46s, JET about 2 minutes and the regression set 3m19s.
- **Tasks:** 3/3
- **Files:** 7 committed data/evidence files, 1 docs page, 2 planning files

## Accomplishments

### Task 1: data validation and commit

The plan's CSV assertion passed: exactly one measured row, with label, feeder, population, T 10, strategy ADMM and a status in the allowed vocabulary. The `recorded_no_go` row is unchanged (`cmp` against HEAD) and no line was removed from the CSVs.

The verify was adapted to the two wrapper rows: the *last* wrapper row for the label has rc 0, `peak_rss_kb == vmhwm_kb` (6,059,204), and args containing `--min-mem-avail-gib 5.5`.

Committed with this data:
- the five `runs/p46-scn-ieee8500-d10-T10.*` evidence files, which are attempt 2's copies;
- nothing from the scratchpad.

### Task 2: docs section "Headline measurement and go/no-go (Appended 2026-11-05)"

It is appended after line 534 and no earlier line changed (the diff's removed-line count is 0). It has a Units paragraph, a Method paragraph and the following subsections, all computed live:

1. **Decision.**
   - Threshold 10.0 GiB, read from the `recorded_no_go` row.
   - VmHWM 11,753,716 kB = 11.209 GiB (the maximum over `memory_attribution.csv` rows with ieee8500 / 0.1 / T 24).
   - Wrapper MaxRSS 12,079,316 kB = 11.520 GiB (`p35-head-d0.1-T24`).
   - The page prints "verdict: NO-GO", and `@assert` checks that the committed row equals the recomputation.
   - The prose says what NO-GO means: the threshold was not met. It does not mean "cannot run".
2. **Lower-bounded requirement.**
   - B1 = 11.520 GiB, a measured bound that is checked against the row.
   - B2 = 13.324 GiB, labelled an estimate that depends on earlyoom, with the 15.035 GiB host total cross-checked against `free -m` in the run's `free_before` file.
   - The requirement is phrased on MemAvailable at the peak.
   - Counter-fact: `p35-head-d0.1-T24` completed (rc 0) with 10.092 GiB available at launch, below B1, and the attribution `anchor_after` row completed with CertificateError after 7 iterations, delta 9.2955 GiB, ratio 223.68. The d = 0.25 point was killed by earlyoom at 12.051 GiB.
   - Components: AgrOpt builds 4.569 GiB, DSO build 0.851 GiB, first iterate 2.924 GiB, later iterates 0.648 GiB.
   - No lever is claimed.
3. **Measured table at T = 10.**
   - The six numbers: size (4,866 buses, 4,865 branches, 1,177 load buses, 122 aggregators of which 4 are capacitor aggregators, 122 AgrOpt models, DSO 245,730 / 486,560, AgrOpt 14,516 / 26,670), build 27.48 s, solve 151.99 s, 5 iterations, VmHWM 5.779 GiB, and `refused_certificate` with ratio 309.67.
   - Also printed: materialize 0.49 s, certify 27.57 s and the provenance.
   - The prose for each outcome is generated from the status, so a refusal, a kill or a not-launched run each read plainly.
   - Both wrapper attempts are printed.
   - The startup footprint is 965,724 kB = 0.921 GiB, which means the default 8 GiB in-script gate implies about 8.92 GiB at launch.
   - The user's approval of the 7.1 GiB launch is stated.
4. **Path-divergence label.** A table lists seven divergences. The prose says the comparison is "same size and structure, different seed draws". The harness comparators are printed by row key:
   - `p35-head-d0.1-T10`: CertificateError, 286.6 s, ratio 568.95;
   - the T = 10 attribution `anchor_after` row: 8 iterations;
   - MaxRSS 5.918 GiB for `p35-head-d0.1-T10` and 5.693 GiB for `p39-attr-d0.1-T10`.
5. **Supersessions** (the old text is not edited):
   - T = 24 "NOT ESTABLISHED" / "earlyoom-killed" is superseded: the `anchor_after` row exists, along with 10 loop/certify rows.
   - 4.024 / 0.922 GiB is superseded by 4.569 / 0.851 GiB.
   - "11.75" was kB divided by 10^6. The binary value is 11.209 GiB.
   - 4,875 / 4,874 is superseded by 4,866 / 4,865, the counts from the measured row.
6. **Reproducing.** A fenced block with the wrapper launch command and `--record-nogo`, plus the pre-flight floor note.

### Task 3: style pass, gates and closure

- The style commit formats only the new section.
- REQUIREMENTS.md: SCALE-07 and SCALE-08 are ticked, and their traceability rows say Complete with pointers to the CSV and the docs section.
- ROADMAP.md: the Phase 46 line is checked, the plan list 46-01..46-05 is added, and the progress row reads 5/5 Complete 2026-11-05.
- STATE.md was not touched and `phase.complete` was not run, as the orchestrator instructed.

## Task Commits

1. **Task 1: measured rows:** `8b2b3e4` (data)
2. **Task 2: docs section:** `673d359` (docs)
3. **Task 3: style:** `6f5af6c` (style). **Closure:** `c3bef88` (docs: REQUIREMENTS and ROADMAP)

Plan 04's summary commit, from the resumed checkpoint: `f14fc07`.

## Verification

- **Task 1 verify:** the plan's CSV assertion passed, plus the adapted last-wrapper-row join (output `TASK1_VERIFY_OK`).
- **Task 2 verify:**
  - The full page ran standalone with `julia --project=docs docs/literate/ieee8500_scaling.jl`: rc 0 in 1m46s, and the earlier live point stayed `OPTIMAL ... verdict=exact` at 84.6 s.
  - The required strings were found: NO-GO, estimate, 11.209 and the run label, plus status and iters in the output.
  - "2026-11-05" is in the page, the planning-ID count is 355, and the page diff has 0 removed lines.
  - The formatted section was re-run and gave the same output.
- **Gates:**
  - Formatter: the second pass changed nothing.
  - Content loss: `check_content_loss.py HEAD` was OK before the style commit and OK against `HEAD~1` after it.
  - Planning-ID: 355, against a baseline of 355.
  - Scripts index: complete (48 files).
  - Script-API lint: the only findings are the 2 pre-existing ones at `scripts/profile_ieee8500_memory_attribution.jl:115,117`. There are no new findings, and the new docs code is clean.
  - JET: 20 current, 20 baseline, 0 NEW, 0 FIXED, on 1.12.5. It warns that the baseline was recorded on 1.12.7, which is informational.
  - SC3: `git diff 7f13ec4..HEAD --stat -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` is empty.
- **Regression set:** `TSODSO_TEST_SET=fast` over `test_ieee8500_scenario.jl`, `test_strategies.jl`, `test_experiments.jl`, `test_flex_population.jl`, `test_admm_knifeedge_canary.jl` and `test_exports.jl` passed **753/753** in 3m18.8s, the same as plan 03. The canary is unchanged. `test/Project.toml` and `test/Manifest.toml` were restored afterwards.
- **Not run (orchestrator-only):**
  - the detached full suite: baseline 36668 pass / 0 fail / 0 error / 7 broken, plus this phase's new items, through `.github/scripts/suite_detached.sh` and `check_suite_log.py`;
  - the full docs build, `julia --project=docs docs/make.jl`.
  - No 8500 solve was run.

## Deviations from Plan

1. **[Data shape, orchestrator-directed] Two wrapper rows for one label.**
   - **Issue:** the must-have and the 46-04 interfaces assumed one wrapper row. `point_resources.csv` has two: attempt 1 refused by the pre-flight, and attempt 2 measured.
   - **Handling:** both are kept (append-only). The gate was adapted to "the last wrapper row for the label joins the measured row", and the docs print both attempts.
2. **[User decision, documented] The launch gate was overridden and the in-script floor lowered.**
   - **What happened:** the user approved launching at about 7.1 GiB instead of 8 GiB. The script's gate reads MemAvailable after package load (the research-flagged footprint pitfall) and refused the first attempt at 7 GiB. The second attempt used 5.5 GiB, the post-load equivalent of the approved level.
   - **Where it is recorded:** the docs state the override and print the footprint and the launch level that the 8 GiB default implies.
   - **Data limits:** the first attempt's in-script reading (6,475,956 kB) is not in committed data, because the keyed upsert replaced that row. The docs therefore compute the footprint from the second attempt (0.921 GiB). The plan 04 summary records the first attempt's value (0.90 GiB) from the scratchpad log.
3. **[Rule 3: blocking] The CSV reader is quote-aware instead of `split(ln, ','; limit = ncols)`.**
   - **Issue:** `memory_attribution.csv` (`note`, followed by `anchor_*` columns) and `density_sweep.csv` (`error_msg`, `admm_error_msg`) have quoted, comma-bearing free text in columns that are not last, so splitting with a column limit would misalign fields.
   - **Fix:** a ~25-line Base-only splitter handles `""` escapes and checks that every row's field count equals the header's. It is still Base only, so the docs environment did not change.
4. **[Process: FMT rule, known deferred item 1]** I ran `format210.jl` on the touched file only, instead of `src ext test docs`, followed by the revert of 22 unrelated drifted files. The literal Task 3 verify (`format210 src ext test docs && git diff --quiet`) cannot pass on this tree because of that pre-existing drift. The second-pass no-op on the touched file stands in for it.
5. **[Process: Script-API lint, known deferred item 2]** The literal verify chain requires `check_script_api.jl` to exit 0. It reports `FAIL: 2 finding(s)`, both pre-existing in `scripts/profile_ieee8500_memory_attribution.jl`. There are no new findings, and the remaining gates were run individually.
6. **[Evidence files] Attempt 1's `runs/` files were overwritten.** Both attempts used the same label. The committed `runs/p46-scn-ieee8500-d10-T10.*` are attempt 2's; attempt 1 survives as its wrapper row.

## Known Stubs

None. The section prints a not-launched branch, which is unused because a measured row exists.

## Threat Flags

None. The changes are a docs page reading committed CSVs, committed data rows and planning files. They add no network, auth or trust-boundary surface.

## Self-Check: PASSED

- FOUND: docs/literate/ieee8500_scaling.jl (contains 2026-11-05), results/ieee8500_benchmark/scenario_table.csv (measured row), point_resources.csv (2 rows for the label), runs/p46-scn-ieee8500-d10-T10.{free_before,time,pid,oom_kernel,oom_earlyoom}
- FOUND commits: f14fc07, 8b2b3e4, 673d359, 6f5af6c, c3bef88
- No file deletions in 095d60c..HEAD
