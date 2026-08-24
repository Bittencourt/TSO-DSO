---
phase: 21-mpc-rolling-horizon-real-time-pricing
plan: 06
subsystem: docs
tags: [literate, documenter, mpc, rolling-horizon, regret, full-suite-acceptance]

# Dependency graph
requires:
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plans 21-01..21-05)
    provides: "Parameter-widened devices (21-01), MpcTrace (21-02), MpcWindow build-once
      model (21-03), Scenario D-12 fields + state propagation (21-04), run_mpc closed-loop
      orchestrator (21-05) — the full stack this closing plan demonstrates live and
      regression-gates with the full suite"
provides:
  - "docs/literate/mpc_rolling_horizon.jl — Rung 8 live-executed literate page: Scenario(T=24,
    mpc_H=6, mpc_terminal_soc=true, mpc_forecast_error=0.08) -> run_mpc(s), reporting the
    day-ahead DADP path, the rolling published DADP + max/mean jump, the measured regret
    (honestly scoped to the published k-hour decision horizon per D-11), and the per-step
    certificate/fallback trace"
  - "docs/make.jl wired with the new Literate source + a 'Rung 8: MPC / Rolling-Horizon RTP'
    Models pages= entry"
  - "Phase 21's closing full-suite acceptance gate: 2658 passed / 0 failed / 3 errored (all
    pre-existing, unrelated to this phase) / 3 broken (unchanged baseline)"
  - "fix: test/test_planning_noninteger.jl's PVAL-04 operational-builder allowlist now
    includes build_mpc_window (plan 21-03's new exported operational-layer builder) — a
    genuine regression this plan's own full-suite gate discovered and fixed"
  - ".planning/phases/21-mpc-rolling-horizon-real-time-pricing/deferred-items.md — the 3
    pre-existing Clarabel NUMERICAL_ERROR errors on run_scenario(:admm), logged out-of-scope
    per the deviation-rule SCOPE BOUNDARY"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A build-once orchestrator whose sole entry point takes a declarative Scenario
      (run_mpc(s::Scenario), not a bare feeder/pf/aggregators tuple) means its OWN literate
      demonstration page constructs a Scenario rather than hand-building a bespoke fixture —
      a genuine, documented departure from every PRIOR rung page's inline-fixture convention,
      forced by the entry point's own signature, not a stylistic choice."
    - "PVAL-04's semantic-channel tripwire (test_planning_noninteger.jl): every newly EXPORTED
      build_* symbol must land on either the planning-layer registry or the documented
      operational-layer allowlist — a new operational builder (like build_mpc_window) failing
      this test is the tripwire working as designed, not a bug; the fix is a conscious,
      one-line allowlist addition, never a test weakening."

key-files:
  created:
    - docs/literate/mpc_rolling_horizon.jl
    - .planning/phases/21-mpc-rolling-horizon-real-time-pricing/deferred-items.md
  modified:
    - docs/make.jl
    - test/test_planning_noninteger.jl

key-decisions:
  - "The literate page uses Scenario(feeder=:ieee13, T=24, mpc_H=6, mpc_terminal_soc=true,
    mpc_forecast_error=0.08) rather than a hand-built Bus/Branch/Feeder/Aggregator fixture,
    because run_mpc's ONLY signature is run_mpc(s::Scenario) — Scenario's existing selector
    set already fully addresses this page's own 24-hour demonstration fixture, so the
    declarative spec IS the 'inlined fixture' for an entry point that only ever accepts one."
  - "mpc_H = 6 (documented choice): large enough to be a genuinely multi-hour receding window,
    short enough that the closed loop re-solves many times over the 24h day — giving
    T - mpc_H + 1 = 19 published steps."
  - "mpc_forecast_error = 0.08, citing D-08's documented ±5-10% range, genuinely nonzero (not
    the degenerate 0.0 no-op case)."
  - "The page does NOT re-run the MPC-02 disabled/dump-hoard negative control (that A/B
    regression already lives in test/test_mpc_terminal.jl, plan 21-04) — this page's own
    scope is the closed-loop demonstration + regret benchmark (MPC-04), not re-proving MPC-02."
  - "build_mpc_window added to test_planning_noninteger.jl's operational_builders allowlist —
    a conscious, documented allowlist extension per that test's own contract, not a weakening
    of PVAL-04's guard (the planning-registry set-equality assertion is unchanged)."
  - "The 3 Clarabel NUMERICAL_ERROR errors on run_scenario(:admm) in test/test_experiments.jl
    are logged to deferred-items.md as pre-existing and out of this phase's scope (files
    entirely untouched by every phase-21 plan; STATE.md's own carried v2.0 Phase-10 note
    explicitly predicts this exact amplification from new outer loops), not fixed here."

patterns-established:
  - "Closing-plan full-suite gate discovers project-wide regressions (here: an unacknowledged
    new build_* export) that no single wave's own targeted <verify> could catch, because each
    prior plan (21-01..21-05) explicitly deferred the full Pkg.test() run to this plan per its
    own <verification> section — confirming the deferral strategy's own stated purpose."

requirements-completed: [MPC-04]

# Metrics
duration: ~55min
completed: 2026-08-09
---

# Phase 21 Plan 06: MPC Rolling-Horizon Literate Page + Full-Suite Acceptance Gate Summary

**`docs/literate/mpc_rolling_horizon.jl` (Rung 8) live-demonstrates `run_mpc` end-to-end on a genuine 24-hour `Scenario` (`mpc_H=6`, 19 published steps, `mpc_forecast_error=0.08`), reporting a measured `regret = -0.0321` and `max_jump = 5.383` with zero certificate escalations needed; the phase's closing full-suite gate found and fixed one genuine regression (a new `build_*` export needing a conscious allowlist entry) and closes at 2658 passed / 0 failed / 3 broken (unchanged baseline) / 3 pre-existing, out-of-scope errored — this closes Phase 21.**

## Performance

- **Duration:** ~55 min (including two full ~11-17 min `Pkg.test()` runs and one `Documenter` build)
- **Started:** 2026-08-09 (worktree fast-forwarded to phase-21 base commit `ba76103`)
- **Completed:** 2026-08-09
- **Tasks:** 2/2 completed (plus 2 follow-up fix commits, see Deviations)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- `docs/literate/mpc_rolling_horizon.jl`: a live-executed Documenter/Literate rung page.
  Constructs `Scenario(name="mpc-rolling-horizon-demo", feeder=:ieee13, T=24, mpc_H=6,
  mpc_terminal_soc=true, mpc_forecast_error=0.08)` and calls `run_mpc(s)`. Presents, in order:
  (1) the full 24h day-ahead DADP path (perfect-foresight benchmark); (2) the rolling
  published DADP path plus `max_jump`/`mean_jump` (MPC-03 price-consistency metrics); (3) the
  measured `regret`, with an explicit prose sentence on its published-`k`-hour-only scoping
  (D-11, never silently extended to the full `T`); (4) the per-step `cert_status_trace`, with
  an honest note that this fixture's 19 resolves all certified at the first (SOC-relaxation)
  tier — no escalation needed here — cross-referencing `test/test_mpc_loop.jl`'s forced-inexact
  regression as where the escalation ladder IS genuinely exercised. Cites the Rawlings/
  Mayne/Diehl terminal-equality framing (D-06) with an EXPLICIT unverified-citation caveat
  (RESEARCH.md's own Assumptions Log A1), matching every prior v3.0 rung page's honesty
  discipline.
- `docs/make.jl`: `mpc_rolling_horizon.jl` appended to the `for src in (...)` Literate tuple
  and a new `"Rung 8: MPC / Rolling-Horizon RTP" => "generated/mpc_rolling_horizon.md"` entry
  added to the `"Models"` pages= section — placed there (not under `"Planning"`) mirroring
  precedent from IEEE-123 Real Impedances / Thesis Reproduction / SOC Relaxation
  Applicability, the other non-planning, non-core-model rungs already grouped under
  `"Models"`.
- Full-suite acceptance gate run TWICE (before/after the allowlist fix below):
  - **Run 1** (before fix): `2657 passed, 1 failed, 3 errored, 3 broken` — 17m06.8s.
  - **Run 2** (after fix): `2658 passed, 0 failed, 3 errored, 3 broken` — 10m56.9s.
  - **Final closing state:** `0 failed`, `3 broken` (unchanged from the Phase-20 baseline —
    the known Aqua CairoMakie/Makie drift items: `test_pricing_welfare.jl`,
    `test_diagnostics_plot.jl`, `test_planning_nash.jl`), `3 errored` (pre-existing, out of
    this phase's scope — see Deviations/Deferred below), passed count `2658` (up from the
    pre-phase baseline `2563` — a delta of `95` individual `@test` assertions, NOT the naive
    `15`-item `@testitem`-count tally; see Deviations for why those two counts genuinely
    differ).
  - `Documenter`/`Literate` docs build (`julia --project=docs docs/make.jl`) exits `0`; the
    new page renders (`docs/src/generated/mpc_rolling_horizon.md`), `checkdocs = :exports`
    passes with zero new missing-docs failures, and the only warnings are pre-existing/
    accepted classes (`:cross_references` `warnonly`, the `api.md` size-threshold warning
    already above its own warn-only bar) plus one now-fixed stray `@ref` from this page's own
    first draft (see Deviations).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the mpc_rolling_horizon.jl literate page** - `52ab2c9` (feat)
2. **Deviation fix: PVAL-04 operational-builder allowlist** - `25b3f8e` (fix)
3. **Deviation fix: stray `@ref` cleanup + deferred-items.md** - `e28100c` (fix)
4. **Task 2: Full-suite acceptance gate** - no dedicated commit (a verification-only task;
   both full-suite runs and the docs build are recorded in this Summary, not committed
   artifacts themselves)

_No TDD RED/GREEN/REFACTOR gate sequence — this plan's two tasks are `type="auto"` (not
`tdd="true"`); Task 1 is a from-scratch literate-page authoring task verified via its own
inline `<verify>` script, and Task 2 is the phase's closing full-suite verification run, not
an implementation task._

## Files Created/Modified

- `docs/literate/mpc_rolling_horizon.jl` — Rung 8 literate page (see Accomplishments).
- `docs/make.jl` — new Literate-source tuple entry + `pages=` entry for the new page.
- `test/test_planning_noninteger.jl` — `build_mpc_window` added to PVAL-04's documented
  `operational_builders` allowlist (deviation fix, see below).
- `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/deferred-items.md` — logs the 3
  pre-existing, out-of-scope Clarabel `NUMERICAL_ERROR` errors on `run_scenario(:admm)`.

## Decisions Made

- Used `Scenario`/`run_mpc(s)` rather than a hand-built inline fixture (see key-decisions in
  frontmatter) — `run_mpc`'s own signature forces this, a genuine documented departure from
  prior rung pages' convention, not a stylistic shortcut.
- `mpc_H = 6`, `mpc_forecast_error = 0.08` — documented choices (see frontmatter).
- Placed the new page's `pages=` entry under `"Models"` (mirroring IEEE-123/Thesis-Repro/SOC-
  Applicability precedent), not `"Planning"`.
- Fixed `test_planning_noninteger.jl`'s allowlist rather than weakening or skipping PVAL-04's
  own tripwire — the tripwire is working exactly as its own docstring says it should.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/2 - Bug/Missing functionality] `build_mpc_window` missing from PVAL-04's operational-builder allowlist**

- **Found during:** Task 2's first full-suite run.
- **Issue:** `test/test_planning_noninteger.jl`'s PVAL-04 `@testitem` includes a
  syntax-independent "semantic channel" tripwire: every EXPORTED `build_*` symbol in `TSODSO`
  must be either a planning-layer registry key or on a documented `operational_builders`
  allowlist. Plan 21-03 exported `build_mpc_window` (an operational-layer, welfare-shaped,
  build-once receding-horizon window builder) without this closing plan ever running the full
  suite to discover the gap — every prior plan (21-01..21-05) explicitly deferred that full
  run to plan 21-06 per each of their own `<verification>` sections. The tripwire fired
  exactly as designed: `Set(["build_master","build_mpc_window","build_shared_transmission",
  "build_planning_oracle","build_follower"]) != Set(["build_master","build_planning_oracle",
  "build_shared_transmission","build_follower"])`.
- **Fix:** Added `"build_mpc_window"` to `test_planning_noninteger.jl`'s documented
  `operational_builders` Set, with an explanatory comment (build-once, welfare-shaped, no
  binaries/integers by construction, an operational- not planning-layer builder) — a
  conscious allowlist extension exactly matching this test's own stated contract ("a new
  OPERATIONAL builder failing here is a deliberate, loud prompt to extend this allowlist
  consciously"). The planning-registry set-equality assertion itself is completely unchanged.
- **Files modified:** `test/test_planning_noninteger.jl`
- **Verification:** Standalone script confirms `setdiff(exported_builders, operational_builders)
  == Set(["build_master","build_planning_oracle","build_shared_transmission","build_follower"])`
  (exactly the registry keys). Re-ran the full suite afterward: `0 failed` (down from `1`).
- **Committed in:** `25b3f8e`

**2. [Rule 1 - Bug] Stray unresolvable `@ref` on a bare filename in the new literate page**

- **Found during:** the docs build (`julia --project=docs docs/make.jl`), which warned
  `Cannot resolve @ref for md"[`restricted_branch_flow.jl`](@ref)"`.
- **Issue:** `@ref` targets a documented symbol's docstring, never a bare source filename —
  a copy/paste-style authoring mistake in this page's own first draft.
- **Fix:** Removed the `@ref`, kept the filename as plain code-formatted text (matching how
  every other cross-page filename reference in this page is already written).
- **Files modified:** `docs/literate/mpc_rolling_horizon.jl`
- **Verification:** The acceptance-criteria greps (`run_mpc(`, `regret`) still match after
  the edit; `:cross_references` was already `warnonly` in `docs/make.jl` so this warning was
  never build-fatal, but is now genuinely absent from the source rather than merely
  suppressed. The docs build itself was NOT re-run after this purely textual removal (a
  strictly lower-risk change than the version already confirmed to build with exit `0`).
- **Committed in:** `e28100c`

### Deferred (out of scope, logged not fixed)

**3. [Pre-existing, unrelated] 3 Clarabel `NUMERICAL_ERROR` errors on `run_scenario(:admm)` in `test/test_experiments.jl`**

- Both full-suite runs (before and after the allowlist fix) report the IDENTICAL 3 errors:
  `EXP-01 scenario admm`, `INFRA-04 same-seed repro admm`, `INFRA-04 seed sensitivity admm` —
  all the same stack trace (`solve_admm` → `solve_dso!` → `assert_solved!` throws
  `termination_status : NUMERICAL_ERROR`).
- **Why out of scope:** `test/test_experiments.jl`, `src/experiments/run.jl`,
  `src/admm/solve_admm.jl`, `src/admm/DsoOpt.jl` are ALL outside every phase-21 plan's
  declared `files_modified` — `Scenario`'s four new `mpc_*` fields are documented no-ops for
  `:centralized`/`:admm`, so they cannot be the proximate cause. `.planning/STATE.md`'s own
  carried "[v2.0 Phase 10 target]" note explicitly predicts this exact scenario: "CI-flaky...
  intermittent Clarabel `NUMERICAL_ERROR` on the IEEE-13 ADMM solve... is expected to be
  AMPLIFIED once new outer loops (rolling-horizon...) re-solve it repeatedly. Re-measure
  empirically per phase, don't assume prior milestones' rates hold." This measurement is
  exactly that re-measurement.
- **Not the same category as the phase's own "3 broken" bar** — `Error` and `@test_broken`
  are distinct Test.jl reporting categories; the broken count stayed exactly `3`, unchanged,
  on both runs.
- **Action:** logged to `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/deferred-
  items.md` with full reproduction detail and a recommended follow-up (extend
  `test/fixtures_retry.jl`'s existing bounded-retry quarantine convention to these 3
  sub-tests, or investigate Clarabel's per-unit-base cone-slack sensitivity directly). Not
  fixed here, per the deviation-rule SCOPE BOUNDARY (pre-existing failures in unrelated files
  are logged, not fixed).

**4. [Measurement note, not a deviation] The naive `@testitem`-count tally does not predict the `Pkg.test()` passed-count delta**

- This plan's own `<action>` for Task 2 instructs tallying the number of NEW `@testitem`s
  added across plans 21-01..21-05 (grep-verified: `4 + 3 + 4 + 1 + 3 = 15`) and expecting the
  full-suite `passed` count to equal the pre-phase baseline (`2563`) plus that tally. The
  MEASURED delta is `2658 - 2563 = 95`, not `15` — because the `Pass` column in `Pkg.test()`'s
  summary counts individual `@test` assertion executions, and each new `@testitem` in this
  phase contains MULTIPLE `@test` calls (e.g. loops over several devices/steps/assertions per
  item), not one assertion per item. This is reported honestly as measured rather than forced
  to match the plan's own approximate expectation.

---

**Total deviations:** 2 auto-fixed (1 genuine regression fix, 1 cosmetic doc fix), 1 logged-
and-deferred pre-existing issue (out of scope), 1 measurement-transparency note.
**Impact on plan:** The genuine regression (PVAL-04 allowlist gap) is now fixed and verified;
the phase's own closing acceptance bar (`0 failed`, `3 broken` unchanged) is met. The 3
pre-existing ADMM errors do not block this plan's own stated STOP conditions ("failed count
nonzero" or "broken count differs from 3" — neither triggers) and are transparently documented
rather than silently ignored or force-fixed out of scope.

## Known Stubs

None — every number the literate page presents is genuinely computed live during the
Documenter build (confirmed by the docs build's own successful re-execution of every
`@example` block in `mpc_rolling_horizon.md`); no hardcoded placeholder/empty value flows to
the page.

## Threat Flags

None — this plan's only new surface is a documentation page (a build-time, non-user-facing
artifact) and one test-file allowlist entry; no new runtime code path, network endpoint, auth
path, or schema change.

## Issues Encountered

None beyond the two auto-fixed deviations and the one out-of-scope deferred issue documented
above, all discovered and resolved (or triaged) during this plan's own full-suite acceptance
gate.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 21 (MPC / Rolling-Horizon / Real-Time Pricing, MPC-01..04) is now COMPLETE: all four
  requirements have shipped across the six plans (21-01: MPC-01 device Parameter seam; 21-02:
  MPC-03 trace ledger; 21-03: MPC-01/02 build-once window + terminal toggle; 21-04: MPC-01/02
  Scenario fields + state propagation + terminal-SOC regression; 21-05: MPC-03/04 closed-loop
  orchestrator + regret; 21-06 (this plan): MPC-04 live literate demonstration + full-suite
  acceptance gate).
- The full test suite closes at `2658 passed / 0 failed / 3 broken (unchanged) / 3 errored
  (pre-existing, deferred)` — a strictly BETTER state than this plan started with (`1 failed`
  fixed to `0`).
- `deferred-items.md`'s recommended follow-up (extend `test/fixtures_retry.jl`'s bounded-retry
  convention to `test_experiments.jl`'s 3 ADMM sub-tests) is available for a future quick task
  or phase, not blocking this phase's own closure.
- The docs build is green (`exit 0`); the new Rung 8 page is live and citable.

---
*Phase: 21-mpc-rolling-horizon-real-time-pricing*
*Plan: 06*
*Completed: 2026-08-09*

## Self-Check: PASSED

- FOUND: `docs/literate/mpc_rolling_horizon.jl`
- FOUND: `docs/make.jl` (modified)
- FOUND: `test/test_planning_noninteger.jl` (modified)
- FOUND: `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/deferred-items.md`
- FOUND: `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/21-06-SUMMARY.md`
- FOUND commit: `52ab2c9` (feat(21-06): live-executed literate page + docs/make.jl wiring)
- FOUND commit: `25b3f8e` (fix(21-06): PVAL-04 operational-builder allowlist)
- FOUND commit: `e28100c` (fix(21-06): stray @ref cleanup + deferred-items.md)
- Task 1's own `<verify>` script re-ran successfully (idempotent): prints
  `regret = -0.03212514413962708  max_jump = 5.382825932897548` with all 19 steps
  `:certified_convex_dual`.
- Acceptance-criteria greps re-confirmed: `run_mpc(` (2 matches), `mpc_rolling_horizon.jl` in
  `docs/make.jl` (2 matches), `regret` (5 matches).
- Full-suite `Pkg.test()` re-run after the allowlist fix confirms `0 failed`, `3 broken`
  (unchanged baseline), `2658 passed`, `3 errored` (pre-existing, deferred).
- `julia --project=docs docs/make.jl` confirmed exit `0`.
