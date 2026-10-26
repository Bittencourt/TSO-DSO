# Phase 41 — Deferred Items (out-of-scope discoveries)

## Pre-existing JuliaFormatter drift in two files (found 2026-10-26, plan 41-04 Task 2)

Running JuliaFormatter 2.10.x over the whole `src`/`test`/`docs` trees (the CI format
job's exact scope) reflows two files that plan 41-04 does NOT own:

- `src/experiments/materialize.jl` — `_case_a_rung_counts` docstring rewrap + the
  `isempty(full_counts)` guard collapse (10 lines)
- `test/test_population_case_a_scaling.jl` — 52 lines of the same reflow class

Both were reverted untouched by 41-04 (scope boundary: only fix what the current task's
changes caused). The drift is pre-existing at 41-03's HEAD; whether it fails the CI
format job depends on the exact 2.10.x patch resolving locally vs the CI pin
(2.10.2) — worth a standalone `format(...)` + commit by the phase owner before the next
CI run, or a re-check with the pinned patch version.
