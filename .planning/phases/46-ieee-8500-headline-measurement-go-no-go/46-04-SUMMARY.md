---
phase: 46-ieee-8500-headline-measurement-go-no-go
plan: 04
subsystem: measurement / orchestrator-launched run
tags: [ieee8500, scenario, admm, measurement, memory, preflight, checkpoint]

requires:
  - phase: 46-03
    provides: scripts/ieee8500_scenario_point.jl tested and indexed; scenario_table.csv with the recorded_no_go row
provides:
  - measured row for run label p46-scn-ieee8500-d10-T10 in results/ieee8500_benchmark/scenario_table.csv (status refused_certificate), written by the orchestrator's run and still uncommitted (plan 05 commits it)
  - two wrapper rows for the same label in results/ieee8500_benchmark/point_resources.csv (attempt 1 preflight refusal, attempt 2 measured run)
  - wrapper evidence files results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.{free_before,time,pid,oom_kernel,oom_earlyoom} (attempt 2's copies; attempt 1's were overwritten because the label is the same)
affects: [46-05 data commit, docs section and requirement closure]

tech-stack:
  added: []
  patterns:
    - "One real 8500 measurement launched only by the orchestrator, detached and alone; executors verify readiness read-only"

key-files:
  created:
    - .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-04-SUMMARY.md
  modified: []

key-decisions:
  - "User decision 2026-11-05: launch anyway at about 7.1 GiB MemAvailable, below the planned 8 GiB pre-launch gate, because the host could not reach 8 GiB even after the user freed memory"
  - "The script's pre-flight reads MemAvailable after Julia startup and package load, so it sees roughly 0.9 GiB less than the wrapper's pre-launch reading; the in-script floor was lowered to 5.5 GiB for the second attempt as the post-load equivalent of the approved pre-launch level"
  - "Both wrapper rows are kept (point_resources.csv is append-only); the last wrapper row for the label is the one that joins the measured row"

requirements-completed: []

duration: orchestrator-run (attempts at 21:11:31 and 21:12:27 local, run wall 4:06.93); executor resume ~5 min
completed: 2026-11-05
---

# Phase 46 Plan 04: Orchestrator-launched T = 10 IEEE-8500 Scenario point Summary

**The orchestrator ran the single T = 10 IEEE-8500 point through `scripts/run_ieee8500_point.sh` with the Scenario script. The first attempt was refused by the script's own pre-flight. The second attempt, with a user-approved lower floor, completed and was refused with a certificate: 5 iterations, SOCP gap ratio 309.67, 4,866 buses, 122 aggregators, peak 6,059,204 kB = 5.779 GiB, no OOM. That is an accepted measured outcome, and nothing was retuned.**

## Performance

- **Executor resume:** about 5 minutes (verify, summary, commit). The run itself was the orchestrator's: attempt 1 started at 2026-11-05 21:11:31 and attempt 2 at 21:12:27 (local time), with a process wall time of 4:06.93 for attempt 2 (`runs/p46-scn-ieee8500-d10-T10.time`).
- **Tasks:** 2/2. Task 1 (the read-only readiness check) ran before the checkpoint. Task 2 (the human-action checkpoint) was resumed with "run complete".
- **Files:** none in the repository from this plan. The run wrote the two CSVs and the `runs/` files, and plan 05 commits them.

## Accomplishments

### Task 1: launch-readiness check (before the checkpoint, read-only)

The executor before the checkpoint checked all of this without solving anything on an 8500 feeder:
- the script's `--help` works;
- the wrapper is executable and parses with `bash -n`;
- no row for the label existed in either CSV;
- the tracked tree was clean.

It made no commit.

### Task 2: the orchestrator's run (resume signal "run complete")

**Host state.** MemTotal is 15,765,568 kB (15.035 GiB). The user decided on 2026-11-05 to launch anyway at about 7.1 GiB, because the host could not reach the planned 8 GiB MemAvailable gate even after the user freed memory. That decision lowered the plan's gate (step 1 of the checkpoint), and it is recorded here as the user's explicit override. Two wrapper readings were taken at launch:

| attempt | started (local) | wrapper `mem_avail_before_mb` | swap used before (MiB) | other julia procs |
|---|---|---|---|---|
| 1 | 2026-11-05 21:11:31 | 7,243 | 8,988 | 0 |
| 2 | 2026-11-05 21:12:27 | 7,247 | 8,986 | 0 |

**Attempt 1** used `--min-mem-avail-gib 7` and ended `preflight_refused`, an accepted outcome. The script reads MemAvailable after Julia startup and `using TSODSO`, and at that point it saw 6,475,956 kB = 6.176 GiB, which is below 7.0 GiB (7,340,032 kB). The difference from the wrapper's pre-launch 7,243 MiB (7,416,832 kB) is 940,876 kB ≈ 0.90 GiB, which is the process's own startup footprint as MemAvailable sees it. The research flagged this effect ("pre-flight reading its own footprint"). Nothing was materialized. The wrapper row has rc 0, peak 1,371,524 kB and oom_source none.

**Attempt 2** used `--min-mem-avail-gib 5.5`, the post-load equivalent of the user-approved 7.1 GiB pre-launch level. The script saw 6,455,204 kB = 6.156 GiB, which passes. The keyed upsert replaced the `preflight_refused` row with the measured row:

| column | value |
|---|---|
| row_kind / feeder / population / T / strategy | measured / ieee8500 / default_10pct / 10 / ADMM |
| seed / sub_seed_population | 1 / 411717551 |
| **status** | **refused_certificate** (CertificateError, kind socp_exact) |
| iters / gap_ratio | 5 / 309.6735071222779 |
| buses / branches / load buses | 4,866 / 4,865 / 1,177 |
| aggregators / capacitor aggregators / AgrOpt models | 122 / 4 / 122 |
| DSO vars / cons; AgrOpt vars / cons (summed) | 245,730 / 486,560; 14,516 / 26,670 |
| materialize / build / solve / certify (s) | 0.49 / 27.48 / 151.99 / 27.57 |
| VmHWM after each phase (kB) | materialize 1,382,068; build 3,356,184; solve 6,059,204; certify 6,059,204 |
| vmhwm_kb / vmhwm_gib / maxrss_gib | 6,059,204 / 5.779 / 5.779 |
| heap hint / julia / git_head / threads | 8G / 1.12.5 / 095d60c / 1 |
| wall-clock cap | 1200 s (harness default, recorded in the note; the library path has none) |

The wrapper row for attempt 2 has rc 0, peak_rss_kb 6,059,204, oom_source none and mem_avail_before_mb 7,247.

**Files the run wrote:**
- `scenario_table.csv` now has the `recorded_no_go` row (unchanged) and the measured row.
- `point_resources.csv` has two appended rows for the label (attempts 1 and 2).
- `runs/p46-scn-ieee8500-d10-T10.{free_before,time,pid,oom_kernel,oom_earlyoom}` are attempt 2's copies; the oom files are empty. Attempt 1's copies were overwritten because both attempts used the same label. Attempt 1's evidence survives in its wrapper row and in the scratchpad copies (its log and the pre-launch copy of its table row), which are not committed.

**Checkpoint verify:** passed. No `ieee8500_scenario_point` process was running, `pgrep -x julia` was empty, and a wrapper row for the label exists. No NOT-LAUNCHED marker was written, because the resume signal was "run complete".

## Task Commits

1. **Task 1: launch-readiness check:** no commit (read-only)
2. **Task 2: orchestrator run:** no commit by this plan. Plan 05 commits the data.

**Plan metadata:** see the `docs(46-04)` commit that adds this summary.

## Deviations from Plan

1. **[User decision: gate override] The run was launched below the planned 8 GiB MemAvailable gate.**
   - **Found during:** Task 2, checkpoint step 1.
   - **Issue:** after freeing memory the host reached about 7.1 GiB MemAvailable, not 8 GiB.
   - **Decision:** the user explicitly chose "Launch anyway at 7.1 GiB" on 2026-11-05. The plan's alternative was a launch that ends `preflight_refused`, and the user preferred a real attempt.
   - **Outcome:** the run peaked at 5.779 GiB with no OOM. The wrapper's `free -m` shows swap already at about 8.8 GiB before launch. The run's own swap use is not separately measured (`Swaps: 0` in `/usr/bin/time` counts whole-process swap-outs only).
2. **[Measured effect] The in-script pre-flight reads the process's own footprint, so a second attempt was needed.**
   - **Issue:** the script's MemAvailable read happens after Julia startup and package load. On this host it saw about 0.90 to 0.92 GiB less than the wrapper's pre-launch reading. The research had flagged this pitfall, and the fix it named (read "before any heavy work") was implemented after argument parsing, which is still after `using TSODSO`.
   - **Result:** with `--min-mem-avail-gib 7` the gate refused at 6.176 GiB. The orchestrator relaunched once with 5.5 GiB as the post-load equivalent of the approved pre-launch level. This is not a retune of any solver knob. Only the host-memory gate changed, with user approval.
   - **Consequence:** the documented 8 GiB in-script gate effectively demands about 8.9 GiB at launch on this host. That is stated in the plan 05 docs section.
3. **[Data shape] There are two wrapper rows for one label.**
   - **Issue:** the plan's must-have says "one wrapper row".
   - **Handling:** `point_resources.csv` is append-only, and both rows are genuine measurements, so both are kept. The last wrapper row for the label (attempt 2) joins the measured row. Plan 05 adapts its gates to that.

## Issues Encountered

None beyond the deviations.

## Next Phase Readiness

- Plan 05 commits the CSV rows and the `runs/` evidence files. Earlier runs' `runs/*.{free_before,time,pid,oom_kernel,oom_earlyoom}` files are tracked, so the new ones follow that convention. Plan 05 then writes the dated docs section and closes the requirements.

## Self-Check: PASSED

- FOUND: the measured row for p46-scn-ieee8500-d10-T10 in scenario_table.csv (status refused_certificate)
- FOUND: 2 wrapper rows for p46-scn-ieee8500-d10-T10 in point_resources.csv
- FOUND: results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.{free_before,time,pid,oom_kernel,oom_earlyoom}
- No julia process running at resume
