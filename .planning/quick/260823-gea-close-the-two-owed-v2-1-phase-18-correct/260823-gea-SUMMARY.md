---
quick_id: 260823-gea
subsystem: testing
tags: [clarabel, socp-exactness, repro-stability, measurement-before-golden, thesis-repro]

# Dependency graph
requires:
  - phase: v2.1 Phase 18 (directional thesis reproduction)
    provides: repro_stability_check.jl, test_thesis_repro.jl's pinned DSO_BAND_HI
  - quick_task: 260726-mo7
    provides: optimizer kwarg on fit_baseline
provides:
  - Per-stage try/catch attribution and optimizer/REPRO_TOL_GAP threading in
    scripts/repro_stability_check.jl (item 5, CLOSED)
  - A fresh, honestly-attributed re-measurement showing item 4 (golden-band re-derivation)
    does NOT currently have enough solving points to responsibly close (item 4, still OPEN)
affects: [v2.1-phase-18-followups, future-repro-stability-remeasurement]

tech-stack:
  added: []
  patterns:
    - "per-stage try/catch (one block per solve call, short-circuiting) instead of one
      catch-all wrapping multiple solves, to make failure attribution unambiguous"
    - "optimizer=nothing kwarg + opt_kwargs splat, mirroring fit_baseline/solve_welfare's
      own 'only pass an override when the caller actually gave one' discipline"

key-files:
  created: []
  modified:
    - scripts/repro_stability_check.jl
    - test/test_thesis_repro.jl
    - docs/literate/thesis_reproduction_assumptions.jl
    - .planning/notes/socp-validity-envelope.md
    - .planning/STATE.md

key-decisions:
  - "Left DSO_BAND_HI unchanged (5.58855710237937) rather than pin a new value: the fresh
    tol_gap=1e-10 re-measurement did not reproduce spike 003's 5/5 result, so re-deriving
    1.5*max|dso| would be over only 2 of 5 points — no stronger evidence than the original
    1-point derivation, and the never-actually-measured 7.211 projection was never adopted."
  - "Did not re-run the interrupted 20-repeat flake-rate measurement to completion; used only
    the partial evidence already produced (7 of 20 repeats logged, all fit_baseline
    ALMOST_OPTIMAL failures) rather than spend further unbounded solver time chasing a clean
    number, per this task's own measurement-before-golden/honest-negative-result mandate."

requirements-completed: []

duration: ~90min
completed: 2026-08-23
---

# Quick Task 260823-gea: Close the two owed v2.1 Phase-18 corrections Summary

**Closed item (5) — split `repro_stability_check.jl`'s try/catch per stage and threaded the `optimizer`/`REPRO_TOL_GAP` kwarg — but a fresh, honestly-attributed re-measurement showed item (4)'s golden-band re-derivation cannot yet be responsibly closed: at `tol_gap=1e-10` today, `solve_welfare`'s SOCP-exactness gate reproduces 5/5, but `fit_baseline`'s own nested solve fails with `ALMOST_OPTIMAL` at 3 of 5 points, leaving only 2/5 points with a full sign-flip confirmation — too few to re-derive `1.5 × max|dso|` more credibly than the existing 1-point pin. `DSO_BAND_HI` is left unchanged.**

## Performance

- **Duration:** ~90 min (including two full-precompile Julia measurement runs)
- **Completed:** 2026-08-23
- **Tasks:** 2 of 3 planned tasks fully executed as planned (A); 1 (B) partially executed with an honest-negative outcome instead of the planned golden-band update; 1 (C) executed with content adjusted to the real outcome
- **Files modified:** 5 (1 code, 4 docs/notes/state)

## Accomplishments

- `scripts/repro_stability_check.jl`'s `count_failures` and `sweep_population_scale` now run
  `solve_welfare` → `welfare_accounting` → `fit_baseline` in three sequential, independent
  `try/catch` blocks per point/repeat, short-circuiting on the first failure. A failure is now
  attributable to exactly one stage, both in-memory (`failed_stage`/`by_stage`) and in
  `findings.txt` (`FAILED(stage)` cells, a `failures_by_stage` line). This directly fixes the
  misattribution mechanism spike 003 identified (2 of 4 original sweep "failures" were actually
  `fit_baseline` throwing, not `solve_welfare`'s SOCP gate).
- Both functions accept an `optimizer=nothing` kwarg; a new `REPRO_TOL_GAP` env var drives a
  module-level `REPRO_OPTIMIZER` (unset ⇒ `nothing` ⇒ byte-for-byte unchanged default path;
  set ⇒ a `Clarabel.Optimizer` with `tol_gap_abs`/`tol_gap_rel` pinned to that value, same
  attribute pair as `.planning/spikes/003-phase18-fragility-tolerance/check.jl`).
- Verified the default path is numerically unchanged (`sweep_population_scale(feeder;
  deltas=(0.0,))` at default tolerance reproduces the committed `dso=3.725705`,
  `socp_maxgap≈3.06e-7` to the previously-committed precision) and that passing a tightened
  optimizer is actually consumed (measurably smaller `socp_maxgap`).
- **The real finding:** re-ran the fixed script (and, independently, the unmodified spike 003
  `check.jl`, 3 times, all consistent) at `tol_gap=1e-10`. `solve_welfare`'s SOCP-exactness gate
  does resolve 5/5 (0/5 THREW), confirming that part of `260726-mo7`'s finding still holds. But
  `fit_baseline`'s own internal nested `solve_welfare` call (a separate call site, per
  `260726-mo7`'s "SITE 3 of 3") now returns `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` at 3 of the
  5 swept points (`δ=-0.02, 0.00, +0.05`), not the 0/5 recorded in the committed
  `run-after-kwarg.log`. This is a genuinely different numerical failure mode (solver
  convergence at an extreme tolerance) from the one Phase 18 originally diagnosed (SOCP
  relaxation inexactness), and it means `260726-mo7`'s "5/5 show the sign flip" claim does not
  reproduce today — likely environment drift (Clarabel/Julia/dependency patch versions) between
  when that log was captured and now.
- Corrected the demonstrably-false narration this finding makes obsolete regardless of the
  band's fate: `test/test_thesis_repro.jl`'s header comment claiming "all 4 non-zero [sweep]
  points FAIL the SOCP-exactness gate outright" (already known false per `260726-mo7`, but never
  fixed in this file's prose), `docs/literate/thesis_reproduction_assumptions.jl`'s "5/5 solve;
  the DSO-surplus sign flip holds at every point" claim (now qualified with a `CORRECTED`
  admonition matching this page's own established convention), and
  `.planning/notes/socp-validity-envelope.md`'s "now implies 7.211" framing (now explicit that
  this projection was never actually measured and remains unadopted).
- `.planning/STATE.md`'s Phase 18 corrections-owed bullet: item (5) flipped to ✅ (done); item
  (4) stays ⬜, its text updated in place to record the stronger, now-measured finding (deviating
  from the plan's original "flip glyphs only" scope note, per explicit direction to also fix the
  now-known-stale surrounding prose in that specific bullet — see Deviations).

## Task Commits

1. **Task A: split try/catch per stage, thread `optimizer`/`REPRO_TOL_GAP`** — `f913dbb` (refactor)
2. **Task B (adjusted): correct `test_thesis_repro.jl`'s stale narration; leave `DSO_BAND_HI` unchanged** — `36b31a3` (docs)
3. **Task C (adjusted): correct stale prose in the assumptions page and validity-envelope notes** — `56f007f` (docs)

`.planning/STATE.md` was edited but is left staged for the orchestrator's final metadata commit, per this task's constraints.

## Files Created/Modified

- `scripts/repro_stability_check.jl` — per-stage try/catch split, `optimizer`/`REPRO_TOL_GAP` threading, updated header comment and findings-writer sections.
- `test/test_thesis_repro.jl` — corrected the false "all 4 non-zero points FAIL outright" claim; added a paragraph recording the `ALMOST_OPTIMAL` finding and explicitly marking the golden-band re-derivation OPEN. `DSO_BAND_HI` constant itself is UNCHANGED.
- `docs/literate/thesis_reproduction_assumptions.jl` — added a `CORRECTED 2026-08-23` admonition on the 5/5-sweep section; rewrote the golden-band paragraph to explain why it is left unpinned.
- `.planning/notes/socp-validity-envelope.md` — rewrote item 4 of the "still owed" list to record the same finding, explicit "STILL OPEN."
- `.planning/STATE.md` — item (5) flipped to ✅; item (4) text updated with the new finding (left unstaged for the orchestrator).

## Deviations from Plan

### Auto-fixed Issues

None applicable in the Rule 1-3 sense — the deviations below are Rule 4 (architectural/scope) escalations, handled via mid-task coordinator direction rather than silent auto-fix.

### Rule 4 escalation — Task B's re-measurement did not reproduce spike 003's 5/5 result

- **Found during:** Task B, step 1-2 (running the fixed script at `REPRO_TOL_GAP=1e-10`).
- **Issue:** The plan's Task B explicitly required stopping if any point fails to solve at
  `tol_gap=1e-10` ("this would mean the spike 003 result did not reproduce and needs
  investigation before any golden is touched"). That condition was hit: `fit_baseline` failed
  with `ALMOST_OPTIMAL` at 3 of 5 points, both in the fixed script's own 20-repeat flake-rate
  measurement (interrupted mid-run; 7 of 20 repeats logged, all `fit_baseline` failures at the
  exact retuned point) and, independently, in 3 re-runs of the unmodified spike 003 `check.jl`.
- **Resolution (per coordinator direction, escalated and confirmed mid-task):** did not re-run
  the measurement further (a 20-repeat flake-rate sweep failing ~7/20 mid-run is out of scope
  for a quick task, and repeated re-attempts risk exactly the "massage a knife-edge number until
  it looks clean" pattern this project's measurement discipline forbids). Left `DSO_BAND_HI`
  unchanged; documented the finding honestly in `test/test_thesis_repro.jl`, the assumptions
  page, the validity-envelope notes, and `STATE.md`; explicitly recorded what a future phase
  would need (a bounded, budgeted re-measurement) to close item (4).
- **Files affected:** `test/test_thesis_repro.jl`, `docs/literate/thesis_reproduction_assumptions.jl`, `.planning/notes/socp-validity-envelope.md`, `.planning/STATE.md`.
- **Commits:** `36b31a3`, `56f007f` (STATE.md left unstaged).

### Rule 4 escalation — STATE.md's bullet text updated, not just its checkbox glyphs

- **Found during:** Task C.
- **Issue:** The plan's original Task C scope note said to flip ONLY the two checkbox glyphs in
  STATE.md's Phase 18 bullet and reword nothing else, treating the bullet as an untouched
  historical record. That scope note assumed item (4) would be closed with a fresh number; since
  it was NOT closed, leaving the surrounding prose as-is would have left STATE.md asserting a
  stale, now-directly-contradicted claim ("the sweep solves 5/5 ... holds at every point") right
  next to a checkbox this task is flipping.
- **Resolution:** per explicit coordinator direction, updated item (4)'s text in place (not just
  the glyph) to record the new, stronger finding, while leaving the rest of the bullet (the
  spikes 002/003 attribution, the `tol_gap` values) untouched.
- **Files affected:** `.planning/STATE.md` (edited, left unstaged for the orchestrator).

## Known Stubs

None — this task only modified an existing internal measurement script and documentation/comments; no UI or data-rendering surface was touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes were introduced. This task only changed error-handling granularity in an internal research script and corrected documentation prose.

## Self-Check: PASSED

- `scripts/repro_stability_check.jl` exists and contains the per-stage try/catch + `optimizer`/`REPRO_TOL_GAP` code (verified by direct read after edit).
- `test/test_thesis_repro.jl` exists; `DSO_BAND_HI = 5.58855710237937` is unchanged; the "all 4 non-zero points FAIL outright" string now appears only inside a quoted historical claim immediately followed by "was itself a MISATTRIBUTION" — it is no longer asserted as current fact (verified by targeted read/grep).
- `docs/literate/thesis_reproduction_assumptions.jl` exists; `grep -n "should be re-derived deliberately"` returns no matches (plan's own verify command, run directly — 0 matches confirmed).
- `.planning/notes/socp-validity-envelope.md` exists; both remaining `7.211` mentions read as historical/never-measured framing, not "still an open live discrepancy" framing (verified by direct read).
- `.planning/STATE.md` exists; `grep -n '(4) ⬜\|(5) ✅'` finds both markers in the Phase 18 bullet (verified).
- Commit `f913dbb` exists: `git log --oneline --all | grep f913dbb` → found.
- Commit `36b31a3` exists: `git log --oneline --all | grep 36b31a3` → found.
- Commit `56f007f` exists: `git log --oneline --all | grep 56f007f` → found.

---

## ADDENDUM — item (4) subsequently CLOSED (same quick task, after user decision)

The body of this summary above records item (4) as deliberately left OPEN. That was correct at
the time it was written, but the task did not end there. Two background runs completed after the
executor reported done, and they surfaced a distinction that made the band re-derivable after all.
The user was presented with the options and chose to decouple and re-pin.

**The distinction.** The band rule `1.5 × max|dso|` ranges over `dso` — the DADP DSO surplus,
produced by `solve_welfare` + `welfare_accounting`. `fit_baseline` produces `fit_dso`, which the
sign-flip check needs and the band does not. `scripts/repro_stability_check.jl` conflated them in
two separate ways:

1. the band's `successful` filter required all three stages to have succeeded, and
2. the failure branch of `sweep_population_scale` recorded `dso = NaN` whenever `fit_baseline`
   threw — discarding an `acct.dso` that had already been computed successfully.

So the band was simultaneously *gated on* and *starved by* a stage orthogonal to it.

**Both fixed**, and re-measured with the fixed script at `REPRO_TOL_GAP=1e-10`:

| quantity | value |
|---|---|
| `dso`-trustworthy points | **5 of 5** |
| all-three-stages points | 2 of 5 |
| `max\|dso\|` | 4.807417 |
| script `RECOMMENDED BAND:` | **`DSO_BAND_HI = 7.211125525764296`** |
| previous pin | 5.58855710237937 |
| flake rate | 13/20 = 0.650, all 13 at `fit_baseline` (reproduced, 3 runs) |

The pinned value was taken from the script's own `RECOMMENDED BAND:` line, not computed by hand —
measurement-before-golden preserved. It coincides numerically with the `7.211` long flagged in the
planning notes, but is reached by the decoupling argument above rather than by the refuted
"the sweep solves 5/5 everywhere" assumption that figure was originally projected from. That
distinction is the whole substance of the close.

**Verified:** the pinned point `|dso| = 3.7257047351781196` sits inside both the old and the new
band, so the band widening moves no verdict. `DSO_BAND_LO = 0.0` and every other assertion in
`test/test_thesis_repro.jl` are unchanged — nothing was weakened to accommodate the new number.

**Still live, NOT closed by this:** `fit_baseline`'s convergence at `tol_gap=1e-10` (13/20 flake
rate, `sign_flip_survives: false`, 2/5 points fully confirming the flip). A solver-convergence
issue distinct from SOCP inexactness, deserving its own follow-up.

Commit: `c284a7e`. Both items (4) and (5) are now ✅ in STATE.md.
