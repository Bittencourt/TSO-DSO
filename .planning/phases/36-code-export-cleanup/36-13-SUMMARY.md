---
phase: 36-code-export-cleanup
plan: 13
subsystem: hygiene
tags: [planning-id-scrub, devices, data, full-suite-checkpoint]
requires: ["36-12"]
provides:
  - src/devices and src/data (including the ieee8500 impedance table header) free of planning identifiers (classifier TOTAL 0 over the 17-file set)
  - full-suite checkpoint for the src/ext scrub stage (plans 08-13) green
affects: [36-14]
key-files:
  modified:
    - src/devices/AbstractDevice.jl
    - src/devices/Aggregator.jl
    - src/devices/Deferrable.jl
    - src/devices/FixedCapacitor.jl
    - src/devices/FourQuadBESS.jl
    - src/devices/Interruptible.jl
    - src/devices/PVBattery.jl
    - src/devices/Thermostatic.jl
    - src/data/Feeder.jl
    - src/data/MeshedFeeder.jl
    - src/data/ieee13.jl
    - src/data/ieee123.jl
    - src/data/ieee8500.jl
    - src/data/ieee8500_impedances.jl
    - src/data/mesh_topology.jl
    - src/data/profiles.jl
    - src/data/topology.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 13: Scrub of src/devices and src/data Summary

About 363 classifier hits (8 device files, 9 data files) were rewritten so each rationale survives as plain prose with no phase, plan, requirement, decision, threat, pitfall, quick-task or research-artifact identifiers. The classifier reports TOTAL 0 over the plan's file set. `ieee123_impedances.jl` needed no edits; `ieee8500_impedances.jl` had only its header comment lines changed (AST EQUAL, data rows untouched). Thesis-equation and literature references are untouched (thesis_tokens OK). HYG-01 stays pending.

## Commits
- a9d7b51: scrub src/devices
- 7a49108: scrub src/data
- 7f11839: JuliaFormatter 2.10.2 pass on src/data: only `mesh_topology.jl` (trailing blank line) and `profiles.jl` (a blank line and two `throw(ArgumentError(...))` calls collapsed onto one line); check_content_loss printed OK. The device files were already formatter-stable.

## Verification
- Classifier TOTAL 0 on the 17 files; ast_equiv.jl EQUAL for all of them (also against the scrub commits after formatting); thesis_tokens.py OK.
- Targeted tests (fourquadbess, pvbattery, thermostatic, deferrable, migration gate, ieee123, ieee13, ieee123_admm, aggregator, profiles): 1135 pass, 1 pre-existing broken.
- Full suite (`suite_detached.sh p13`, launched after the last code commit): 32202 pass / 0 failed / 0 errored / 5 broken, 32207 total; `check_suite_log.py p13 --same-pass-as p07` exits 0; canary welfare -4823.66604824162 present in the log.
- Aqua direct script: all checks pass.
- `src/TSODSO.jl` is scrubbed in the next plan and is covered by the final suite of the last plan.

## Message changes
Runtime strings changed (grep of `test/` found no assertion on any of them; `ast_equiv.jl --strings` output reviewed and every entry is listed). No `@testitem` names changed.

FourQuadBESS.jl
- Pch_max ArgumentError: `(MESH-04, D-02: ` + `grid-charging is capped ...` became `(` + `grid-charging is capped ...`.
- Pdch_max ArgumentError: `(MESH-04, ` + `D-04: independent of Pch_max)` became `(` + `independent of Pch_max)`.
- Smax ArgumentError: `(p²+q²≤Smax², MESH-04 D-03/D-04); got Smax=` became `(p²+q²≤Smax²); got Smax=`.
- Strict-ordering ArgumentError: `(MESH-04 D-05: the ` became `(the `.
- soc_terminal ArgumentError: `(Phase 26 FIX-04); got Symbol` became `; got Symbol` (`value, or :cyclic only; got Symbol :...`).

PVBattery.jl
- soc_terminal ArgumentError: same `(Phase 26 FIX-04)` removal.

profiles.jl
- `generate_profiles: demand_values must be non-negative (threat T-03-05)` and the matching `pv_values` message lost the ` (threat T-03-05)` suffix.

## ID-like identifiers found (for the guard plan)
None in these files (no code identifier carries a planning token). Test names and fixture docs in `test/` still cite MESH-04, FIX-04, D-09/D-10 and "Open Q1" (for example `test/test_aggregator.jl:96`, `test/test_fourquadbess.jl:12`, an `@info` note in the ieee13 test); those are out of this plan's file set.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded in the same files: `byte-identical`/`BYTE-UNCHANGED` (to `bit-for-bit identical`/`UNCHANGED`), `success criterion 2`, `Open Q2`, `Assumption A1/A2/A4` and `RESEARCH ...` citations (thesis assumptions A3/A6 kept), `this plan`/`this benchmark phase`, `.planning/...` and `*-RESEARCH.md`/`*-DATA-PROVENANCE.md` paths, quick-task numbers (the ieee8500 count-history comment keeps the numbers 4,875/2,521 to 4,872/2,518 to 4,866/2,512 without the task ids), `Rule 1` deviation headers.
- A scripted first pass (scratch scripts outside the repo) removed ID-only parentheticals; manual per-hunk review then fixed leftovers (orphaned punctuation such as `#.`, `—)`, `..`, a lowercase sentence start, a dangling `(`) before any commit. The AST check was clean throughout.
- One rewording worth noting: the FourQuadBESS complementarity note previously cited the earlier `EXACT-04` finding as "found interesting for a different reason"; it now says the regime is one in which the SOCP relaxation's exactness is delicate.

## Known Stubs
None.

## Self-Check: PASSED
