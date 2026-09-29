---
phase: 26-network-device-model-correctness
plan: 14
subsystem: optimization-models
tags: [julia, jump, battery-complementarity, ac-oracle, ipopt, socp, app-c, gap-closure]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: Plan 26-04's FIX-05 operating-point move, which exposed (did not cause) the App. C eta<1 gap on the EXACT-04 AC oracle fixture
provides:
  - "assert_battery_complementarity! on_violation mode (:error default, :warn) in src/models/welfare_solve.jl"
  - "AC/NLP call site in solve_welfare reports (never throws on) a genuine App. C eta<1 simultaneous charge/discharge instead of hard-failing"
  - "Documented App. C eta<1 finding (docs/literate/prosumer_welfare.jl + 26-FINDINGS.md) with an unscheduled backlog item for a proper complementarity treatment"
affects: [test_ac_oracle, test_restricted_branch_flow, phase-28-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Problem-class-aware on_violation mode threaded through a shared post-solve assertion function (:error for SOCP, :warn for AC/NLP), matching the existing problem-class-aware tolerance (tau) pattern already in this function"

key-files:
  created:
    - .planning/phases/26-network-device-model-correctness/26-FINDINGS.md
  modified:
    - src/models/welfare_solve.jl
    - docs/literate/prosumer_welfare.jl

key-decisions:
  - "Per locked decision PM-02: document as a finding and make the AC oracle report (not throw), rather than re-parametrizing App. C's battery utility or adding a complementarity constraint now — that remediation is deferred to an unscheduled future phase"
  - "on_violation defaults to :error so the 3 other call sites (src/planning/subproblem.jl, src/admm/AgrOpt.jl, src/models/stochastic_welfare.jl) and solve_welfare's own SOCP path are completely unaffected, verified byte-for-byte identical throw message"

patterns-established:
  - "Shared post-solve assertion functions can expose an on_violation mode (:error/:warn) keyed off problem_class(pf), letting the SAME correctness check serve both a hard gate (SOCP, convex/global optimum trusted) and a diagnostic (AC/NLP, where a genuine but model-parametrization-exposing optimum should not hard-fail the solve)"

requirements-completed: [FIX-04]

# Metrics
duration: 15min
completed: 2026-09-29
---

# Phase 26 Plan 14: AC Oracle Reports (Not Throws) on App. C eta<1 Battery Complementarity Summary

**`assert_battery_complementarity!` gains a problem-class-aware `on_violation` mode (`:error`/`:warn`) so the AC/NLP oracle in `solve_welfare` logs a genuine, KKT-consistent App. C eta<1 simultaneous charge/discharge instead of throwing, while the SOCP path is provably unchanged; the finding is documented in `docs/literate/prosumer_welfare.jl` and a new `26-FINDINGS.md` with an unscheduled backlog item.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `assert_battery_complementarity!` (`src/models/welfare_solve.jl`) now accepts `on_violation::Symbol = :error`; `:warn` logs the identical violation message via `@warn` and continues the loop (reports every violating `(bus,t)` pair), any other value raises an `ArgumentError`.
- `solve_welfare`'s single call site now passes `on_violation = (problem_class(pf) isa SOCP ? :error : :warn)` — verified live: the EXACT-04 AC (Ipopt) high-PV stress fixture (`pv_scale=1.2`) now solves to completion (`obj = -921.2769914316113`) with the violation logged at bus 2, t=7 (`p_ch·p_dch = 7.788e-6 ≥ τ·Pmax² = 1.0e-8`), matching the plan's cited numbers, instead of throwing.
- Confirmed the SOCP/default path is byte-for-byte unaffected: a direct re-run of `test_welfare_solve.jl`'s existing complementarity-violation cases still throws the identical message with the default (no `on_violation` passed).
- Documented the App. C eta<1 finding as fact in `docs/literate/prosumer_welfare.jl` (new subsection in the "PV + battery" App. C section) and in a new `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md`, both citing the EXACT-04 measured KKT identity and naming an explicitly unscheduled backlog item for a proper complementarity treatment.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add an on_violation mode to assert_battery_complementarity!, defaulting to :warn on the AC/NLP call site only** - `b26c205` (fix)
2. **Task 2: Document the App. C eta<1 finding in docs and 26-FINDINGS.md, with a backlog item** - `d5fbc39` (docs)

_No plan-metadata commit was made by this executor — per the objective, STATE.md/ROADMAP.md are orchestrator-owned and updated at phase close from `26-FINDINGS.md`._

## Files Created/Modified
- `src/models/welfare_solve.jl` - `assert_battery_complementarity!` gained `on_violation::Symbol = :error` (`:error`/`:warn`/ArgumentError-on-other); `solve_welfare`'s AC/NLP call site now passes `:warn`; docstring updated to explain the new mode and cite the App. C eta<1 finding.
- `docs/literate/prosumer_welfare.jl` - New "Finding (Plan 26-14, PM-02)" subsection in the App. C section stating the eta<1 gap as fact, with the KKT identity and the AC oracle's new report-not-throw behavior.
- `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md` - New file; `# Phase 26 Findings` header + `## Plan 26-14 — App. C eta<1 finding` section, condensed finding + explicit "unscheduled — needs a future phase slot" backlog item, mirroring `STATE.md`'s `[vX.Y ...]` bullet style.

## Decisions Made
- Followed the plan's locked PM-02 disposition exactly: document + report-not-throw, no utility/model change. No architectural deviation (Rule 4) was needed.
- `on_violation` validation (`ArgumentError` on any value other than `:error`/`:warn`) was added per the plan's explicit instruction ("Any other value throws an `ArgumentError` about the invalid mode") — verified live.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria were verified directly (see Issues Encountered for the one tooling workaround, which changed no code).

## Issues Encountered

- **Verify-command tooling gap (known trap, not a plan bug):** the plan's Task 1 `<automated>` verify command does `include("test/fixtures_phase4.jl")` under `julia --project=.`, but that file is a TestItems `@testmodule` (a TestItems-only macro; `TestItems`/`TestItemRunner` are test-only deps declared in `test/Project.toml`, not resolvable under the root `--project=.` environment) — matching the known trap in memory `gsd-plan-verify-testitemrunner-trap` and `testitem-try-scoping-trap`. Worked around by defining a minimal local `@testmodule` shim macro (`module <name> ... end`, no TestItems machinery) before including the fixture file, purely for this ad hoc verification run — no project file was changed. The verify then ran and matched the plan's acceptance criteria and cited numbers exactly (bus 2, t=7, `p_ch·p_dch = 7.788198173349456e-6`).
- **Worktree base drift at startup:** this worktree's HEAD was on an older commit (`3488bf5`, an ancestor of the expected base `7cde1cd`) rather than already at the expected base. The working tree was clean, so `git reset --hard 7cde1cd...` was applied per the `<worktree_branch_check>` protocol before any edits — not a plan deviation, a pre-task environment correction.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `test_ac_oracle.jl:182` (EXACT-04, `pv_scale=1.2`) and the downstream `test_restricted_branch_flow.jl` cases that solve the same fixture through the AC oracle should no longer throw on this complementarity check; a full-suite run (not performed here, per parallel-worktree guidance to avoid running the full suite on a shared 4-core machine) is the appropriate way to confirm those specific tests green end-to-end.
- The App. C eta<1 remediation (binary/MPEC or eta-aware round-trip penalty) remains an open, unscheduled backlog item — flagged in both `26-FINDINGS.md` and the literate docs for a future phase to claim.
- `.planning/STATE.md` was NOT touched by this plan; the orchestrator is expected to fold `26-FINDINGS.md`'s "Plan 26-14" section into `STATE.md`'s Blockers/Concerns at phase close.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `src/models/welfare_solve.jl`
- FOUND: `docs/literate/prosumer_welfare.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md`
- FOUND: commit `b26c205` (Task 1)
- FOUND: commit `d5fbc39` (Task 2)
