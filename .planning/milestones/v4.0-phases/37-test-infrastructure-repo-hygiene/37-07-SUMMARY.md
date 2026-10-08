---
phase: 37-test-infrastructure-repo-hygiene
plan: 07
subsystem: testing
tags: [jet, static-analysis, ratchet, baseline]
requires: [37-06]
provides:
  - scripts/jet_check.jl two-way JET ratchet (check, --update, --baseline PATH, --selftest)
  - scripts/jet_baseline.txt (33 normalized, justified signatures)
affects: [ci-jet-job]
key-files:
  created: [scripts/jet_check.jl, scripts/jet_baseline.txt]
  modified: []
decisions:
  - Baseline header records JET 0.11.6 / Julia 1.12.7; a mismatch only prints a WARNING (observed on 1.12.5, still passes)
  - No src change; optional cleanups (objective helper, pf_vars local copy) left for plan 08
metrics:
  tasks: 3
  completed: 2026-10-06
---

# Phase 37 Plan 07: JET ratchet and baseline Summary

JET 0.11.6 `report_package` check reduced to normalized signatures (`kind | function | file | message head`, no line numbers, gensyms stripped, duplicates collapsed) and compared two-way against a justified baseline of 33 signatures.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 jet_check.jl | 58c0f7b | normalize/diff/rewrite core; `--selftest` runs without JET on any Julia (verified 1.11.9 and 1.12.7); real run on non-1.12 exits 2; `check_script_api.jl` green |
| 2 baseline | 0693f20 | 33 signatures in 3 justified groups: 23 `objective_value` `Union{Float64,Vector{Float64}}` artifacts, 7 `Union{Nothing,..}` field narrowing, 3 conditionally-defined locals (`q_import_t`, `qag_dso`, `seed_q_import`) |
| 3 reproducibility | (measurement) | identical result on 1.12.5 (`+release`) and 1.12.7 (`+1.12`): 33 current, 0 NEW, 0 FIXED, exit 0; planning-ID guard clean |

None of the 33 is a genuine undefined name or wrong-arity call, so no src fix was made.

## Ratchet proven both directions (copies in scratchpad via `--baseline`)

- Signature dropped from baseline: `33 current, 32 baseline, 1 NEW, 0 FIXED`, exit 1.
- Bogus signature added: `33 current, 34 baseline, 0 NEW, 1 FIXED`, exit 1.

## Deviations from Plan

None. The `--baseline PATH` override was added as the plan allowed. On 1.12.5 the version-header WARNING prints (expected, non-failing).

## Notes

Cold JET analysis ran about 46 s of analysis per run here. HYG-04 is intentionally not marked complete (CI wiring is a later plan).

## Self-Check: PASSED
Files and commits 58c0f7b, 0693f20 verified present.
