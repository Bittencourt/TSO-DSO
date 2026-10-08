---
phase: 26-network-device-model-correctness
plan: 06
subsystem: pricing
tags: [dlmp, kkt-duality, pricing, socp, re-certification]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness (plan 02)
    provides: "ConvexBranchFlow(; thesis_literal=false) — corrected default cpydrop sign (v̂ ≥ v)"
provides:
  - "decompose_dlmp's volt_b formula empirically re-certified unchanged after the FIX-01/02 cpydrop sign flip, on three distinct regimes (congestion-binding, voltage-engaged, uncongested/in-bound)"
  - "deferred-items.md — a confirmed, bisected, out-of-scope regression from Plan 26-03's FIX-04 in test_pricing_dlmp.jl's uncongested-2-bus fixture"
affects: [27-integer-planning-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Empirical re-certification via direct-script reproduction of @testitems, per the project's TestItemRunner-trap memory"

key-files:
  created:
    - .planning/phases/26-network-device-model-correctness/deferred-items.md
  modified:
    - src/pricing/dlmp.jl

key-decisions:
  - "No code change to volt_b's formula: P's own coefficient inside cpydrop (the quantity the KKT-stationarity derivation depends on) was not touched by Plan 26-02's fix — only the l-term's coefficient flipped — and this is now empirically confirmed, not just argued algebraically"
  - "The third canonical test fixture (test_pricing_dlmp.jl's PVBattery-based 'uncongested in-bound 2-bus') could not be re-exercised as written because of a pre-existing, unrelated SOCP-exactness regression from Plan 26-03 (FIX-04); bisected to commit cfa7e6e and logged to deferred-items.md rather than fixed, since it falls outside this plan's declared file scope (src/pricing/dlmp.jl only)"
  - "Substituted the plan's own <verify> smoke fixture (Deferrable load, r=0.01/x=0.02 2-bus) as the third regime's empirical evidence, since it exercises the identical uncongested/in-bound property (congestion ≈ 0, voltage ≈ 0) without the FIX-04 regression"

requirements-completed: [FIX-01, FIX-02]

# Metrics
duration: ~35min
completed: 2026-09-28
---

# Phase 26 Plan 06: DLMP Voltage-Coefficient Re-Certification (FIX-01/02 Follow-up) Summary

**Empirically re-verified that `decompose_dlmp`'s `volt_b` formula needs NO change after Plan
26-02's `cpydrop` sign flip — confirmed to machine precision on two of the three canonical
regimes plus a substitute for the third, whose original fixture was found (via bisection) to
be broken by an unrelated Plan 26-03 regression, now logged for the phase to resolve.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-28 (approx.)
- **Completed:** 2026-09-28
- **Tasks:** 1 completed
- **Files modified:** 1 modified, 1 created (SUMMARY not counted)

## Accomplishments

- Reproduced (as direct `julia --project=.` scripts, per the TestItemRunner-trap project memory)
  the three `decompose_dlmp`-consuming `@testitem`s in `test/test_pricing_dlmp.jl`:
  1. **"four components SUM to the DADP on IEEE-13 (congestion binds)"** — PASSED, worst
     residual `6.213970022540078e-12`.
  2. **"SUM holds and voltage is engaged on the high-PV over-voltage solve"** — PASSED, worst
     residual `1.7763568394002505e-15`.
  3. **"has ≈0 congestion/voltage on an uncongested in-bound 2-bus"** — could NOT be run as
     written: `solve_welfare` itself throws inside `assert_socp_exact!` (SOCP inexactness gap
     `4.39e-5`), before `decompose_dlmp` is ever reached. Bisected across 4 isolated codebase
     snapshots (`git archive` extracted to scratch dirs, each re-run with the exact fixture) and
     confirmed this is caused by **Plan 26-03's** battery SOC-horizon fix (commit `cfa7e6e`,
     FIX-04), NOT by Plan 26-02's cpydrop sign flip (commit `f677965` alone leaves this exact
     fixture exact to residual `0.0`). Logged to `deferred-items.md` as D-26-01, out of this
     plan's declared file scope (`src/pricing/dlmp.jl` only) — not fixed here.
- Since the third fixture's intended REGIME (uncongested, in-bound — both congestion and
  voltage components ≈0) is what actually needed confirming, independently re-verified the
  same property using this plan's own `<verify>` smoke fixture (a `Deferrable` load on a
  genuinely non-degenerate `r=0.01/x=0.02` 2-bus feeder, avoiding `PVBattery`/FIX-04 entirely):
  residual `2.2204460492503131e-16`, `congestion ≈ 7.86e-14`, `voltage ≈ 4.89e-13` — all ≈0/
  machine precision.
- **Conclusion: the existing `volt_b = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))`
  formula is EMPIRICALLY RE-CERTIFIED UNCHANGED** across all three regimes (congestion-binding,
  voltage-engaged, uncongested/in-bound) after the FIX-01/02 cpydrop sign flip — no code change
  to the formula was made, matching the task's own stated expectation that "P's own coefficient
  inside cpydrop... was not changed by [Plan 26-02], only the l-term's."
- Updated `src/pricing/dlmp.jl`'s header derivation comment to record exactly what was
  empirically verified this phase (fixtures used, residuals measured, and the caveat about the
  third fixture's substitution and the deferred D-26-01 regression) — per the file's own
  established "empirically certified to machine precision on named fixtures" documentation
  convention.
- Created `.planning/phases/26-network-device-model-correctness/deferred-items.md` documenting
  the discovered Plan 26-03 regression (D-26-01) with full bisection evidence (4 isolated
  codebase snapshots tested), root cause, and the action needed before phase close.

## Task Commits

1. **Task 1: Empirically re-certify (or re-derive) decompose_dlmp's voltage-component
   coefficient** - `589f8aa` (docs) — no formula code change; header comment updated;
   `deferred-items.md` created.

## Files Created/Modified

- `src/pricing/dlmp.jl` — header derivation comment (lines ~34-53 region) extended with a
  "[Phase 26 / FIX-01-02 re-certification, plan 26-06]" block stating the three regimes tested,
  their measured residuals, and the D-26-01 deferred-item pointer. `volt_b`'s formula itself
  (line ~267, now shifted a few lines down) is **byte-identical** to before this plan.
- `.planning/phases/26-network-device-model-correctness/deferred-items.md` (new) — D-26-01,
  the confirmed-by-bisection Plan 26-03 SOCP-exactness regression.

## Decisions Made

- **No formula change.** The task's own acceptance criteria allowed either outcome ("empirically
  re-verified unchanged" or "re-derived"); the evidence from the two fixtures that DID solve
  (IEEE-13 congestion-binding, high-PV voltage-engaged) showed machine-precision residuals with
  the EXISTING formula, confirming the task's own hypothesis (P's coefficient inside `cpydrop`
  is untouched by Plan 26-02's `l`-term-only sign flip) rather than requiring a rediscovery.
- **Substitute fixture for the third regime, not a code fix.** Rather than attempting to fix
  Plan 26-03's PVBattery/SOCP-exactness interaction (which is out of this plan's `files_modified`
  scope: `src/pricing/dlmp.jl` only, per the plan's own frontmatter), the uncongested/in-bound
  REGIME was independently re-confirmed via this plan's own sanctioned `<verify>` smoke fixture,
  which exercises the identical property (both congestion and voltage components ≈0) without
  depending on the broken `PVBattery` SOC-horizon interaction.
- **Logged, not fixed, the discovered Plan 26-03 regression** (D-26-01), per the SCOPE BOUNDARY
  discipline — the regression's root cause and fix both live in `PVBattery.jl`/
  `ConvexBranchFlow.jl` (26-03's or 26-02's territory), not `dlmp.jl`.

## Deviations from Plan

### Auto-fixed Issues

None — no bugs were found that were both in-scope (`src/pricing/dlmp.jl`) and fixable; the
formula required no change.

### Out-of-Scope Discovery (logged, not auto-fixed)

**1. [SCOPE BOUNDARY — deferred, not Rule 1-3] Plan 26-03's battery SOC-horizon fix broke SOCP
exactness on `test_pricing_dlmp.jl`'s "uncongested in-bound 2-bus" fixture**
- **Found during:** Task 1's direct-script reproduction of the three canonical `decompose_dlmp`
  regression fixtures.
- **Issue:** `solve_welfare(feeder, ConvexBranchFlow(), [agg_with_PVBattery]; T=3, ...)` on the
  exact fixture in `test_pricing_dlmp.jl` lines 227-243 now throws inside `assert_socp_exact!`
  (SOCP relaxation inexact, gap `4.39e-5`) instead of solving to an exact, priceable optimum.
- **Root cause (bisected across 4 isolated `git archive` snapshots):** Plan 26-03's commit
  `cfa7e6e` ("extend battery soc to T+1 with full-horizon recursion", FIX-04). The cpydrop sign
  flip alone (commit `f677965`, Plan 26-02) leaves this fixture exact to residual `0.0`; the
  pre-wave-1 baseline (commit `5939799`) is also exact (residual `7.1e-15`).
- **Fix:** NOT applied — logged to `deferred-items.md` (D-26-01) for the phase's wave-merge/
  full-suite step or a follow-up plan in `PVBattery.jl`/`ConvexBranchFlow.jl` territory to
  resolve. This is a real defect that WILL surface as a failure/error in `test/test_pricing_dlmp.jl`
  when the phase's full `Pkg.test()` suite is run — flagging explicitly so it is not missed.
- **Files that would need to change (not touched by this plan):** likely
  `src/devices/PVBattery.jl` and/or `test/test_pricing_dlmp.jl`'s fixture parameters (re-tuning),
  possibly `src/powerflow/ConvexBranchFlow.jl` if a genuine interaction exists.
- **Commit:** N/A (not fixed; documented in `589f8aa` and `deferred-items.md`).

## TDD Gate Compliance

Task 1 carries `tdd="true"` in the plan frontmatter, but this plan's `type` is `execute` (not
`tdd`), and the task's own `<verify>` block is an inline diagnostic Julia script, not a
separately-committed failing-test artifact. No formula code change was made (the empirical
re-certification concluded "unchanged"), so there is no RED→GREEN pair to point to — the single
commit is a `docs`-type commit recording the re-certification evidence, consistent with the
task's own instruction that "make NO code change to the formula itself" is a valid, honest
outcome when the three fixtures (or their regime-equivalent substitutes) pass unchanged.

## Issues Encountered

- The original third canonical fixture (PVBattery-based, `test_pricing_dlmp.jl` lines 219-272)
  could not be run to completion due to the discovered D-26-01 regression — worked around via a
  substitute fixture exercising the identical regime; the underlying regression remains open
  (see deferred-items.md).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `decompose_dlmp`'s sum-to-price identity is now confirmed re-certified against the corrected
  default `ConvexBranchFlow`, closing out the DLMP-side obligation Plan 26-02's own threat model
  (T-26-03) deferred to this plan.
- **D-26-01 must be resolved before Phase 26 closes** (its own SC-6 "full suite green" policy) —
  either by re-tuning `test_pricing_dlmp.jl`'s battery fixture or by fixing a genuine
  `PVBattery`/`ConvexBranchFlow` SOCP-exactness interaction introduced by Plan 26-03's FIX-04.
  This was NOT fixed in this plan (out of its `src/pricing/dlmp.jl`-only file scope) — flagged
  for the orchestrator's wave-merge full-suite step or a follow-up plan.
- Plan 26-05 (parallel, in its own worktree) adds a new `:smax_rev` receiving-end cone to
  `ConvexBranchFlow.jl`; per this plan's context brief, a NEW `:smax_rev` dual does NOT enter
  `decompose_dlmp`'s existing 4-way split (which only reads `:cone`, `:vdrop`, `:cpydrop`,
  `:smax` — the SENDING-end cone). No DLMP-side change is needed for 26-05's addition; Phase 27
  (or a later DLMP-naming pass) should confirm this remains true after 26-05 merges, since
  `:smax_rev`'s dual (receiving-end congestion, thesis 3.37) is a economically real quantity that
  is currently NOT reflected anywhere in the `congestion` component — worth flagging to
  whichever plan next touches `decompose_dlmp`.
- No blockers for proceeding to the next plan in this wave, other than D-26-01 (tracked
  separately, does not block THIS plan's own deliverable).

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `src/pricing/dlmp.jl` (modified, header comment present)
- FOUND: `.planning/phases/26-network-device-model-correctness/deferred-items.md`
- FOUND commit: `589f8aa` (Task 1)
