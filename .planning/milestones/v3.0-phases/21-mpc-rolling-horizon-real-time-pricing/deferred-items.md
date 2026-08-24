# Phase 21 — Deferred Items

Out-of-scope discoveries found while executing plan 21-06's full-suite acceptance gate,
logged per the executor's deviation-rule SCOPE BOUNDARY (only auto-fix issues directly caused
by the current task's changes; pre-existing failures in unrelated files are logged here, not
fixed).

## D-1: Pre-existing, carried Clarabel `NUMERICAL_ERROR` on `run_scenario(:admm)` (test_experiments.jl)

- **Symptom:** `julia --project=. -e 'import Pkg; Pkg.test()'` reports 3 `Error During Test`
  entries, all in `test/test_experiments.jl`'s ADMM sub-tests: `EXP-01 scenario admm`,
  `INFRA-04 same-seed repro admm`, `INFRA-04 seed sensitivity admm`. Root cause (identical
  stack trace in all three, reproduced identically across two independent full-suite runs on
  this same worktree): `solve_admm` → `solve_dso!` (`src/admm/DsoOpt.jl:443`) →
  `assert_solved!` (`src/core/status.jl:57`) throws `"Solve failed — refusing to trust
  results: termination_status : NUMERICAL_ERROR"` from Clarabel on the default `:ieee13`
  population's ADMM path.
- **Why out of scope for plan 21-06 (or any 21-01..21-05 plan):** `test/test_experiments.jl`,
  `src/experiments/run.jl`, `src/admm/solve_admm.jl`, and `src/admm/DsoOpt.jl` are ALL outside
  every phase-21 plan's declared `files_modified` — none of the five prior plans nor this
  closing plan touch any of these files. `Scenario`'s four new `mpc_*` fields (D-12) are
  documented, explicit no-ops for the `:centralized`/`:admm` strategy dispatch (never read by
  `run_scenario`), so they cannot be the proximate cause either.
- **Pre-existing, tracked, and explicitly predicted:** `.planning/STATE.md`'s "[v2.0 Phase 10
  target]" note (carried since Phase 10, v2.0) reads verbatim: *"CI-flaky, version-independent,
  intermittent Clarabel `NUMERICAL_ERROR` on the IEEE-13 ADMM solve (root cause: cone-slack
  numerical sensitivity, per-unit-base dependent; never fixed in v1.0) is expected to be
  AMPLIFIED once new outer loops (rolling-horizon, extensive-form scenarios, meshed SOCP)
  re-solve it repeatedly. Re-measure empirically per phase, don't assume prior milestones'
  rates hold."* This is exactly that predicted amplification, measured empirically as this
  note instructs — not a new defect phase 21 introduced.
- **Not the same as the phase's own "3 pre-existing broken" bar:** the phase's `must_haves`
  and STATE.md's own Phase-20 green reference (2563 passed / 0 failed / 3 pre-existing broken)
  track `@test_broken` markers (`test_pricing_welfare.jl`, `test_diagnostics_plot.jl`,
  `test_planning_nash.jl` — the known Aqua CairoMakie/Makie drift items per the project's own
  MEMORY.md), a DISTINCT Test.jl reporting category from `Error`. Both full-suite runs this
  plan executed confirm the broken count stayed exactly `3`, unchanged.
- **Determinism check:** identical failure (same 3 sub-tests, same stack trace, same seed) on
  TWO independent full-suite runs on this worktree (before and after the `build_mpc_window`
  allowlist fix) — this is a deterministic-per-seed numerical sensitivity on this exact
  fixture/seed combination, not a nondeterministic intermittent flake on THIS specific run
  environment, though STATE.md's own framing ("CI-flaky... intermittent") suggests it may
  behave differently across CI runners/Julia versions.
- **Recommended follow-up (not performed here, out of this plan's scope):** a dedicated quick
  task or future phase should apply the SAME bounded-retry quarantine convention
  `test/fixtures_retry.jl` already establishes for `test_admm.jl`/`test_ieee123_admm.jl`'s two
  flaky IEEE-13 ADMM items, extended to `test_experiments.jl`'s three ADMM sub-tests — or,
  more fundamentally, investigate Clarabel's per-unit-base cone-slack sensitivity on this
  fixture directly (the STATE.md note's own suggested root-cause direction).

**Action taken:** none (per the SCOPE BOUNDARY rule — logged, not fixed). Not a blocker for
plan 21-06's own closing acceptance bar (0 failed, 3 broken — both satisfied); the phase's
own full-suite gate is measured and reported honestly in `21-06-SUMMARY.md`.
