---
quick_id: 260825-eme
subsystem: admm
tags: [clarabel, socp, conditioning, retry, dso-opt, admm]

requires:
  - quick: 260822-f0b / 260822-hld chain
    provides: solve_dso!'s check_exact/strict split and the mid-loop solve_with_retry! routing (f9d6ed7) this task builds on
provides:
  - "solve_dso!'s FINAL/converged (check_exact = true) solve always runs at the DSO-OPT model's as-built Clarabel conditioning, never an inherited mid-loop escalation"
  - "LADDER_ATTR_NAMES (src/planning/retry.jl) — single source of truth for the 4 ladder attribute keys, exported"
affects: [admm, planning-retry, ieee13-admm-numerical-error-debug]

tech-stack:
  added: []
  patterns:
    - "Snapshot-once / restore-before-published-solve: build_dso_opt captures ctx.meta[:ladder_baseline] immediately after model construction (before any solve); solve_dso! restores it, gated on the function's own check_exact convergence flag rather than the (dead-in-production) strict flag."

key-files:
  created: []
  modified:
    - src/planning/retry.jl
    - src/admm/DsoOpt.jl
    - .planning/debug/ieee13-admm-numerical-error.md

key-decisions:
  - "Gated the reset on check_exact, not strict — solve_admm.jl's actual final-consolidation call passes strict = false at both call sites, so gating on strict alone would be dead code for the production path this fix protects."
  - "Snapshot the baseline from the model itself in build_dso_opt (once, before any solve), never hardcode Clarabel's 1e-8/10/10/1e-13 defaults."

requirements-completed: []

duration: ~25min
completed: 2026-08-25
---

# Quick Task 260825-eme: Reset ladder attributes before the final DSO-OPT solve Summary

**The published welfare/dadp solve now always runs at DSO-OPT's as-built Clarabel conditioning, gated on `check_exact` (not the dead-in-production `strict` flag) since `solve_admm.jl`'s real final call passes `strict = false`.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-08-25
- **Tasks:** 3/3 (A, B, C)
- **Files modified:** 3 (`src/planning/retry.jl`, `src/admm/DsoOpt.jl`, `.planning/debug/ieee13-admm-numerical-error.md`)

## Accomplishments

- `solve_dso!`'s FINAL/converged solve (`check_exact = true`) now resets the 4 Clarabel
  conditioning-ladder attributes to the as-built baseline immediately before solving, undoing
  any sticky mid-loop `solve_with_retry!` escalation (`f9d6ed7`, WR-01 contract) — verified by
  reading `static_regularization_constant` back off the same build-once model after
  `solve_admm` returns: `1.0e-8` (baseline), not `1e-6` (an inherited rung-2 escalation).
- Corrected a load-bearing mistaken claim discovered during planning and carried in both
  `DsoOpt.jl`'s inline comments and the debug log: escalation does NOT reach a
  `strict = true` branch in production, because `solve_admm.jl` never calls `solve_dso!` with
  `strict = true` — both its call sites pass `strict = false`. The reset is correctly gated on
  `check_exact` instead.
- Mid-loop stickiness (an escalation persisting across the remaining mid-loop iterations after
  a rescue) is deliberately preserved — the reset never fires on `check_exact = false` calls.
- INFRA-04 bit-for-bit reproducibility (`welfare`/`dadp`/`exact_maxgap`/`iters`, all `==`
  across two in-process `run_scenario` calls) verified intact after the change.

## Task Commits

1. **Task A + B: LADDER_ATTR_NAMES + snapshot/restore in DsoOpt.jl** - `d099821` (fix)
2. **Task C: RESET-01 debug evidence entry** - `f3a3ce7` (docs)

_No separate metadata commit — this quick task's docs commit is the debug evidence append
itself (task C's own deliverable), per the task instructions (STATE.md/PLAN.md/SUMMARY.md are
handled by the orchestrator)._

## Files Created/Modified

- `src/planning/retry.jl` — added `LADDER_ATTR_NAMES` (exported), the single source of truth
  for the 4 Clarabel ladder attribute keys (`static_regularization_constant`,
  `iterative_refinement_max_iter`, `equilibrate_max_iter`, `dynamic_regularization_eps`).
  Purely additive — `git diff` confirms zero changes to the `ladder` vector,
  `RETRYABLE_STATUSES`, or `solve_with_retry!`'s body.
- `src/admm/DsoOpt.jl` — new private helpers `_snapshot_ladder_attrs`/`_restore_ladder_attrs!`;
  `build_dso_opt` snapshots `ctx.meta[:ladder_baseline]` once, immediately after model
  construction; `solve_dso!` restores it immediately before every `check_exact = true` call,
  gated on `check_exact` (not `strict`); corrected the HONEST CAVEAT and SCOPE comments (and
  the struct/function docstrings) that had claimed escalation "reaches the final
  `strict = true` solve".
- `.planning/debug/ieee13-admm-numerical-error.md` — appended a dated 2026-08-25 `RESET-01`
  evidence entry correcting the C1-landing entry's premise and recording the measured numbers
  below.

## Decisions Made

- Gate the reset on `check_exact`, not `strict` — verified by direct source read + grep of
  `solve_admm.jl` that both `solve_dso!` call sites pass `strict = false`; gating on `strict`
  would have been a no-op on the production path.
- Snapshot the baseline from the model itself (`get_optimizer_attribute`), once, at build time
  — never hardcode Clarabel's `1e-8`/`10`/`10`/`1e-13` defaults anywhere, so the fix survives a
  future solver-factory swap or Clarabel default change without edits.
- Graceful degradation in both helpers (`try`/`catch` around `get_optimizer_attribute` /
  `set_optimizer_attribute`): a non-Clarabel backend that lacks a given attribute simply omits
  it from the snapshot / skips restoring it, rather than failing `build_dso_opt` or
  `solve_dso!` outright (INFRA-02).

## Deviations from Plan

None — plan executed exactly as written, including the load-bearing `check_exact`-vs-`strict`
gating correction the plan itself called out during planning.

## Verification Evidence (Julia 1.10.11 — a toolchain that fails without the original C1 fix)

1. Format check (`JuliaFormatter` 2.10.2, isolated scratch env, `overwrite=false`): `true`
   (already clean, no reformatting needed on either edited file).
2. Module load / syntax check: `julia --project=. -e 'include("src/TSODSO.jl")'` — exits 0, no
   `MethodError`/`UndefVarError`. `TSODSO.LADDER_ATTR_NAMES` prints the 4-string tuple.
3. `reset01_probe.jl` (direct `solve_admm` call, `dso_ctx.model` inspected post-return):
   ```
   PROBE OK iters=58 welfare=-4822.90361661042
   FINAL static_regularization_constant = 1.0e-8
   RESET-01 CHECK: OK (baseline restored)
   ```
   `welfare` is 1.7e-11 relative from the known-good `-4822.903616694139` (well inside the
   ~2e-9 cross-environment noise floor documented in the debug log). Exactly **1**
   `escalating conditioning` warning in the log (`grep -c` confirmed).
4. `reset01_infra04.jl` (two in-process `run_scenario` calls, same `Scenario`):
   ```
   INFRA-04 CHECK: OK
   ```
   `welfare`, `dadp`, `exact_maxgap`, `iters` all `==` across both calls. Exactly **2**
   `escalating conditioning` warnings (`grep -c` confirmed) — one per independent
   `run_scenario` call, matching the debug log's own established INFRA-04 pattern.
5. `git diff HEAD~2 HEAD~1 -- src/planning/retry.jl` (Task A's commit) shows only the additive
   `LADDER_ATTR_NAMES` const/docstring/export change — the other `solve_with_retry!` callers
   (`planning/subproblem.jl`, `planning/master.jl`, `planning/master_integer.jl`,
   `models/stochastic_welfare.jl`, `models/mpc_window.jl`) are unaffected by construction.
6. Post-commit deletion check on both commits (`git diff --diff-filter=D --name-only HEAD~1
   HEAD`): empty both times — no unexpected file deletions.
7. Content-loss check (`check_content_loss.py HEAD`, run before the commit against the
   pre-edit tree): reported `+793`/`+5821` char deltas on the two edited files — both
   POSITIVE (net-new authored content), confirming no formatter-induced docstring deletion
   (the formatter made zero changes per point 1, so this diff is 100% my own edits).

## Known Stubs

None.

## Threat Flags

None — this change only affects internal Clarabel solver-conditioning state on an
already-existing, already-trusted model; it introduces no new network endpoint, auth path,
file access pattern, or schema change.

## Self-Check: PASSED

- `src/planning/retry.jl` — FOUND (edited, committed in `d099821`)
- `src/admm/DsoOpt.jl` — FOUND (edited, committed in `d099821`)
- `.planning/debug/ieee13-admm-numerical-error.md` — FOUND (edited, committed in `f3a3ce7`)
- commit `d099821` — FOUND (`git log --oneline --all | grep d099821`)
- commit `f3a3ce7` — FOUND (`git log --oneline --all | grep f3a3ce7`)
