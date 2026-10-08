---
phase: 26-network-device-model-correctness
plan: 16
subsystem: testing
tags: [julia, jump, clarabel, socp, admm, tolerance-calibration, gap-closure]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "Plan 26-12's PM-03 reactive_consensus smart default (LIVE reactive coupling for flexible-load populations), which this plan's D-14 mu_q re-measurement and D-26-02 convergence-budget re-tune both run against"
provides:
  - "test_admm.jl's :27/:127 Phase6 two-bus crossval/loop testitems and test_planning_oracle.jl's PF-04 gate testitem solve at a calibrated, tightened Clarabel tol_gap (1e-10) instead of tripping the PF-04 exactness gate at the default 1e-8 precision floor"
  - "test_admm_reactive.jl's :286 mu_q cross-validation tolerance re-measured (fresh 5-seed sweep) and re-pinned from 1e-7 to 4e-7 against the current merged code"
  - "D-26-02 resolved: test_admm.jl's ieee13 crossval item's convergence budget re-tuned (maxiter 200->700, ε_abs/ε_rel added at 1e-6/1e-7) so the norm-based DADP-match assertion passes under Plan 26-12's now-correctly-engaged LIVE reactive coupling"
  - "26-16-repro-mu-q-sweep.jl fixed: its own include-path and @testmodule-loading bugs (present since planner authorship) corrected so it runs standalone as a genuine direct-script reproduction"
affects: [26-17, 26-18, 26-19, 26-20]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-fixture tol_gap tightening via select_optimizer(SOCP(); tol_gap_abs=1e-10, tol_gap_rel=1e-10) at the solve_welfare call site, per the established Plan 22-02/stochastic_welfare.jl precedent — never touching the PF-04 gate's own atol/rtol"
    - "When a wrapper function (operational_oracle) hardcodes its own optimizer with no override seam, and is out of the plan's file scope, substitute a direct call to the seam it wraps (solve_welfare) at the TEST call site rather than widening source scope — verified behavior-preserving by checking only the fields the wrapper itself would have returned are consumed downstream"
    - "Direct-script fixture reproduction for TestItems @testmodule files: textually rewrite '@testmodule Name begin' to 'module Name' and Base.include_string it, resolving fixture file paths via @__DIR__ (not the shell cwd, which Julia's include ignores for relative paths) — makes a committed repro script genuinely standalone/reproducible from any invocation directory"

key-files:
  created: []
  modified:
    - test/test_admm.jl
    - test/test_planning_oracle.jl
    - test/test_admm_reactive.jl
    - .planning/phases/26-network-device-model-correctness/26-16-repro-mu-q-sweep.jl

key-decisions:
  - "test_planning_oracle.jl's PF-04 testitem replaces its operational_oracle(...) call with a direct solve_welfare(...) call carrying the tightened optimizer, since operational_oracle hardcodes select_optimizer(problem_class(pf)) with no override kwarg and is not in this plan's declared files_modified — only ctx.meta[:p_import] (the same field operational_oracle itself reads to build zstar) is consumed downstream, so this is a behavior-preserving call-site substitution, not a semantic change to what the testitem exercises"
  - "solve_admm's own internal DSO-OPT/AGR-OPT subproblem solves on the Phase6 two-bus fixture did NOT need tol_gap tightening — verified empirically (both the :27 crossval item's cross-validation ADMM call and the :127 loop item's dual-ascent loop converge and pass at solve_admm's default optimizer); only the CENTRALIZED solve_welfare reference solves needed the tightened tol_gap, confirming the triage's own CSB-num diagnosis (precision-floor artifact in the centralized reference, not a genuine ADMM defect)"
  - "test_admm_reactive.jl:286's mu_q atol widened 1e-7 -> 4e-7 (not switched to elementwise max-abs) because the widened absolute atol comfortably clears the freshly-measured max (1.147e-7, ~3.5x margin) while preserving this file's existing norm-based isapprox idiom and its established 3.3x-6.2x margin convention for sibling tolerances in the same testitem"
  - "D-26-02 (orchestrator-assigned additional scope): re-tuned test_admm.jl's ieee13 crossval item's ADMM budget to maxiter=700 with ε_abs=1e-6/ε_rel=1e-7 (found by a direct sweep, not adopting D-26-02's own note's untuned maxiter=2000/ε_abs=1e-7/ε_rel=1e-8 wholesale) — converges in 535 iters to a ~2.4x margin under the pinned atol=1e-2, a genuine re-tune rather than the loosest budget that happens to pass"

requirements-completed: [FIX-03, FIX-04]

# Metrics
duration: 45min
completed: 2026-09-28
---

# Phase 26 Plan 16: Precision-floor tol_gap calibration + mu_q re-pin + D-26-02 convergence-budget re-tune (PM-05) Summary

**Three Phase6 two-bus/planning-oracle testitems recalibrated to a tightened Clarabel `tol_gap=1e-10` (objective value unchanged to >=6 sig digits), `test_admm_reactive.jl`'s degenerate `mu_q` cross-validation atol re-measured and re-pinned `1e-7 -> 4e-7` via a fresh 5-seed sweep, and (orchestrator-assigned additional scope) `test_admm.jl`'s IEEE-13 ADMM convergence budget re-tuned (`maxiter` `200 -> 700`, `ε_abs/ε_rel` `1e-6/1e-7`) to resolve D-26-02's post-PM-03 DADP-match miss.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-28T21:35:00Z (approx, worktree base-correction + context gathering)
- **Completed:** 2026-09-28T22:16:00Z
- **Tasks:** 2 plan tasks completed + 1 orchestrator-assigned additional-scope item (D-26-02)
- **Files modified:** 4 (3 test files, 1 repro script)

## Accomplishments
- **Task 1** — `test/test_admm.jl`'s `:27` ("cross-validation 2-bus welfare + DADP sign") and the Phase6-two-bus `"loop"` testitem's centralized `solve_welfare` reference-solve calls, and `test/test_planning_oracle.jl`'s PF-04-gate testitem, all now pass an explicit `optimizer = select_optimizer(SOCP(); tol_gap_abs=1e-10, tol_gap_rel=1e-10)`. Verified via direct-script reproduction (all 3 pass) that this is a genuine precision-floor fix, not a masked regression: the baseline (default `tol_gap=1e-8`) throws `SOCP relaxation INEXACT: ratio=4.00...` on all 3 items; at `1e-10` the objective is `-483.81912360853147` (matches the triage's own `-483.819124` measurement to >=6 sig digits) and all downstream assertions pass.
- **Task 2** — Re-measured `test_admm_reactive.jl`'s `mu_q` cross-validation via a fresh 5-seed sweep (`SEED_2BUS..SEED_2BUS+4 = 20260719..20260723`, same procedure as the original D-14 measurement) against the CURRENT merged code (through Plan 26-12): measured max `‖Δmu_q‖₂ = 1.147e-7`, already above the old `atol=1e-7` pin. Re-pinned to `atol=4e-7` (~3.5x margin) with an inline old->new+cause comment. Also fixed two latent bugs in the plan's own `26-16-repro-mu-q-sweep.jl` (an `include` path that resolved relative to the shell cwd rather than the including file's directory per Julia semantics, and a raw `@testmodule` load that requires TestItems.jl, unavailable under `--project=.`) so the committed repro script now genuinely runs standalone.
- **D-26-02 (orchestrator-assigned additional scope, `test/test_admm.jl`)** — Resolved the deferred convergence-budget gap: `test_admm.jl`'s ieee13 crossval item's PRE-PM-03 budget (`ρ=100, maxiter=200`, default `ε_abs/ε_rel`) was swept before Plan 26-12's smart default made this fixture's `reactive_consensus` correctly engage `LIVE`; post-26-12 it still converges (`iters=103 < 200`, no fail-loud throw) but the DADP misses the norm-based `atol=1e-2` check by up to `0.139` at the PV back-feed hours. A direct sweep found `maxiter=700, ε_abs=1e-6, ε_rel=1e-7` converges in `iters=535` to max elementwise `|Δ|=4.24e-3` (~2.4x margin under `atol=1e-2`), `exact_maxgap` unchanged at `~1.9e-9`. This is a smaller, more targeted budget than D-26-02's own note's untuned `maxiter=2000/ε_abs=1e-7/ε_rel=1e-8` (which converges in 792 iters) — genuinely re-measured, not adopted wholesale.

## Task Commits

Each task was committed atomically:

1. **Task 1: Tighten tol_gap on the Phase6 two-bus fixture in test_admm.jl (:27, :127) and test_planning_oracle.jl (:269)** - `1537617` (fix)
2. **Task 2: Re-measure and re-pin test_admm_reactive.jl's mu_q cross-validation tolerance** - `0357de8` (fix)
3. **Additional scope: Resolve D-26-02 — re-tune ADMM IEEE-13 convergence budget for LIVE reactive coupling** - `3894ccd` (fix)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified
- `test/test_admm.jl` - `:27` crossval and `"loop"` testitems' centralized `solve_welfare` calls carry a tightened `tol_gap` optimizer on the Phase6 two-bus fixture; the ieee13 crossval item's ADMM budget re-tuned (`maxiter_ieee13=700`, `ε_abs_ieee13=1e-6`, `ε_rel_ieee13=1e-7`) resolving D-26-02.
- `test/test_planning_oracle.jl` - The PF-04-gate testitem's `operational_oracle(...)` call replaced with a direct `solve_welfare(...)` call carrying the same tightened `tol_gap` optimizer (since `operational_oracle` hardcodes its own optimizer with no override seam).
- `test/test_admm_reactive.jl` - `:286`'s `mu_q` comparison `atol` re-pinned `1e-7 -> 4e-7` with an old->new+cause comment quoting the freshly re-measured 5-seed sweep result.
- `.planning/phases/26-network-device-model-correctness/26-16-repro-mu-q-sweep.jl` - Fixed the `include`/`read` path resolution (now `@__DIR__`-relative, invocation-directory-independent) and the raw `@testmodule` load (now textually transformed to a plain `module` and `include_string`-ed) so the script runs standalone.

## Decisions Made
- **`test_planning_oracle.jl` call-site substitution** — Documented above in `key-decisions`. Verified behavior-preserving: only `ctx.meta[:p_import]` is consumed from the prior `operational_oracle` result, and a direct `solve_welfare` call registers the identical `ctx.meta[:p_import]` key.
- **`solve_admm`'s own subproblems left untouched** — Confirmed via direct-script reproduction that `solve_admm`'s internal DSO-OPT/AGR-OPT solves on the Phase6 two-bus fixture do NOT trip the PF-04 gate at the default `tol_gap`; only the centralized `solve_welfare` reference calls needed tightening. This matches the plan's own `<action>` guidance ("if `solve_admm` has no such override, only its `solve_welfare` reference-solve sibling needs the change") — confirmed empirically rather than assumed, since `solve_admm` indeed has no `optimizer` override kwarg.
- **`mu_q` widened-atol over elementwise max-abs** — Chose the simpler widened-absolute-atol fix (`4e-7`) over switching to an elementwise max-abs comparison, since the measured max-abs (`3.11e-8`) is already far tighter than the norm (`1.147e-7`) — the norm-based comparison with a modestly widened atol clears comfortably and preserves the file's existing idiom.
- **D-26-02 budget chosen by direct measurement, not adopted from the deferred-items note verbatim** — The deferred-items.md note's own measurement (`maxiter=2000, ε_abs=1e-7, ε_rel=1e-8` -> 792 iters) was explicitly flagged there as "not swept... a smaller, still-comfortable margin under atol=1e-2 should be findable with less iteration budget." This plan swept several candidate budgets and found `maxiter=700, ε_abs=1e-6, ε_rel=1e-7` (535 iters) clears the same margin with under half the iteration budget of the deferred note's own untuned suggestion.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `26-16-repro-mu-q-sweep.jl`'s own `include`/`read` calls never resolved from any invocation directory**
- **Found during:** Task 2 verification (running the plan's own `<verify>` script)
- **Issue:** The script (already committed as a plan artifact, in `files_modified`) called `include("test/fixtures_phase6.jl")` and `read("test/test_admm_reactive.jl", String)` with paths relative to the process's shell cwd — but Julia's `include`/relative-path convention resolves against the INCLUDING FILE's own directory (`.planning/phases/26-network-device-model-correctness/`), which has no `test/` subdirectory, so the script threw `SystemError: opening file ... No such file or directory` regardless of invocation directory (including the plan's own literal `cd /home/pedro/programming/TSO-DSO && julia --project=. ...` invocation, which does not change this — `include`'s relative-path base is the source file's location, not the shell cwd). Separately, `test/fixtures_phase6.jl`/`fixtures_phase19.jl` are TestItems `@testmodule`s, which throw `UndefVarError: @testmodule not defined` under a plain `--project=.` load (TestItems is test-only; per the `gsd-plan-verify-testitemrunner-trap` project memory).
- **Fix:** Added `_load_testmodule_as_plain` (resolves each fixture path via `@__DIR__`-relative `REPRO_REPO_ROOT`, textually rewrites `@testmodule Name begin` -> `module Name`, and `Base.include_string`s the result) and fixed the trailing `read(...)` call to the same `REPRO_REPO_ROOT`-relative path.
- **Files modified:** `.planning/phases/26-network-device-model-correctness/26-16-repro-mu-q-sweep.jl`
- **Verification:** The script now runs standalone from the worktree root and prints `MEASURED: norm(Δmu_q) = 1.1470317907143747e-7  maxabs(Δmu_q) = 3.108071497715192e-8`, `PARSED pinned atol = 4.0e-7`, `OK: mu_q comparison clears the pinned atol=4.0e-7`.
- **Committed in:** `0357de8` (Task 2 commit)

**2. [Rule 1 - Bug, scope-adjacent] `test_planning_oracle.jl`'s testitem could not carry the tightened optimizer through `operational_oracle` as the plan's literal `<action>` text assumed**
- **Found during:** Task 1 implementation
- **Issue:** The plan's `<action>` instructs adding the tightened `optimizer` kwarg "to the `solve_welfare` ... call(s) on this fixture," but `test_planning_oracle.jl`'s `:269` testitem calls `solve_welfare` indirectly via `operational_oracle`, which hardcodes `optimizer = select_optimizer(problem_class(pf))` with no override kwarg — confirmed by reading `src/models/oracle.jl`'s `operational_oracle` signature in full (no `optimizer` parameter, no kwarg splat).
- **Fix:** Replaced the `operational_oracle(...)` call in this testitem with a direct `solve_welfare(...)` call carrying the tightened optimizer, extracting `zstar` from `ctx.meta[:p_import]` (the identical field `operational_oracle` itself would have returned). No change to `src/models/oracle.jl` (out of this plan's declared file scope).
- **Files modified:** `test/test_planning_oracle.jl` only (already in the plan's declared `files_modified`).
- **Verification:** Direct-script reproduction of the full testitem body (fixture build, tightened `solve_welfare`, `build_planning_oracle`/`solve_planning_oracle!`) passes all of the item's original assertions (`socp_maxgap < 1e-5`, `length/isfinite` on `π`/`dadp`).
- **Committed in:** `1537617` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking-fix to a plan-authored artifact, 1 bug/scope-adjacent call-site substitution); both stayed within the plan's own declared `files_modified` list. Plus 1 orchestrator-assigned additional-scope item (D-26-02), tracked separately (not a deviation from this plan's own scope — explicitly assigned by the orchestrator's `<parallel_execution>` instructions).
**Impact on plan:** All fixes were necessary to make the plan's own `<verify>` scripts and acceptance criteria actually executable/correct. No scope creep beyond the plan's declared files and the orchestrator's explicit additional-scope assignment.

## Issues Encountered
- None beyond the auto-fixed items above. All three testitems in Task 1's scope, the `mu_q` re-pin in Task 2, and the D-26-02 convergence-budget re-tune were verified via direct-script reproduction (TestItemRunner traps under `--project=.` per the `gsd-plan-verify-testitemrunner-trap` project memory) before committing.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 4 precision-floor/tolerance items in this plan's declared scope (Task 1's 3 testitems, Task 2's `mu_q` re-pin) pass via calibrated, documented per-fixture tolerances — never a gate loosening, never a guessed number, per the plan's own `<success_criteria>`.
- D-26-02 (orchestrator-assigned additional scope) is resolved in `test/test_admm.jl`; its `deferred-items.md` entry is left untouched for the orchestrator to close, per the orchestrator's own instructions.
- `test_acceptance.jl:82` record 1 (the SAME D-26-02 convergence-budget gap, on a different test file) remains explicitly out of this plan's scope — the orchestrator's instructions assign it to Plan 26-19.
- `assert_socp_exact!`'s own `atol`/`rtol` (the PF-04 gate itself) were never touched by any change in this plan — confirmed via `git diff` review of every commit (no changes to `src/models/exactness.jl`).

## Known Stubs
None - no stub patterns introduced by this plan's test-file tolerance/budget edits.

## Threat Flags
None - this plan edits only test-file solver-tolerance keywords, one comparison tolerance constant, and one convergence budget; no new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `test/test_admm.jl`
- FOUND: `test/test_planning_oracle.jl`
- FOUND: `test/test_admm_reactive.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-16-repro-mu-q-sweep.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-16-SUMMARY.md`
- FOUND: commit `1537617` (Task 1)
- FOUND: commit `0357de8` (Task 2)
- FOUND: commit `3894ccd` (D-26-02 additional scope)
