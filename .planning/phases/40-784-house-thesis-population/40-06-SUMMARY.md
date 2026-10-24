---
phase: 40-784-house-thesis-population
plan: 06
subsystem: measurement-closure
tags: [julia, admm, clarabel, solver-precision-ladder, agreement-band, gate-then-golden,
  pop-04, honesty-policy, certificate-noise, slow-test, skip-lift]

# Dependency graph
requires:
  - phase: 40 plan 05 (solver-precision seam)
    provides: solve_admm's agr_optimizer kwarg -> build_agr_opt -> select_optimizer(::QP;
      attrs...) — the measured ladder's only src/ mechanism
  - phase: 40 plan 03 (agreement measurement)
    provides: scripts/case_a_agreement.jl (REUSED/extended, never rebuilt), the
      committed legacy agreement.csv row, the :slow testitem + tracked-skip scaffold
provides:
  - "The complete POP-04 ladder record in results/case_a_population/agreement.csv:
    default row (refusal reproduced + migrated in place) + the CERTIFIED gap_1e-10
    rung row (converged at 80 iters, all agreement deltas measured)"
  - "The PINNED agreement band, gate-then-golden: welfare rtol 6.217147850629488e-7,
    price atol/rtol 1.7819846607479022 (10x observed deltas, floored at solver
    noise), asserted LIVE in the :slow testitem — tracked skip LIFTED, allowance
    deleted, POP-04 [x] with citation"
  - "docs page agreement section rewritten to the measured closure (both engines
    certify and agree; ladder history + seam mechanism stated)"
affects: [phase verifier (POP-04 now closed), phase-42 DADP-vs-FIT planning (the
  certified decomposed point unblocks certified-step protocols)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (40-RESEARCH.md Package Legitimacy Audit)
  patterns:
    - "Bounded pre-planned ladder as a script Dict: rung names are the ONLY
      permitted tolerances; stop-on-first-certified + HARD stop; adding a rung
      requires a script edit (deliberate-act friction)"
    - "Legacy-key coalescing on a CSV upsert: rows predating a new key column
      match the default key value and are superseded IN PLACE (no stale duplicate)"
    - "Band pin cites its exact CSV row (provenance key + observed deltas) in a
      comment at the pin site — gate-then-golden made auditable"

key-files:
  created: []
  modified:
    - scripts/case_a_agreement.jl
    - results/case_a_population/agreement.csv
    - test/test_population_case_a_agreement.jl
    - test/expected_broken.txt
    - docs/literate/case_a_population.jl
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Ladder stopped at rung 1 (gap_1e-10, the repo's sanctioned tightening):
    stop-on-first-certified — steps 2 (gap_1e-12) and 3 (gapfeas_1e-12) were never
    run, per the bounded-ladder policy"
  - "Winning-row constants pinned VERBATIM as the test band (no rounding, no
    extra headroom beyond the script's own 10x-floored rule): the pin IS the
    measurement's recommended_* cells, cited to the row"
  - "The default rung's deterministic refusal is KEPT in the CSV beside the
    certified rung — the honest history that motivated the ladder, not deleted"
  - "The default (no-kwarg) solve_admm path stays byte-identical: every src/ gate
    surface diff EMPTY across both gap plans; tau_batt=1e-3 and every band
    literal untouched"

patterns-established:
  - "Skip-lift lockstep: lifting a tracked skip deletes its expected_broken.txt
    allowance in the SAME change set — an unmatched allowance fails the run, so
    the mechanism cannot rot"

requirements-completed: [POP-04]

# Metrics
duration: ~1h55m (includes an operator pause with clean resume)
completed: 2026-10-24
---

# Phase 40 Plan 6: POP-04 Ladder Measurement & Band Pinning Summary

**POP-04 CLOSED BY MEASUREMENT: the bounded solver-precision ladder certified the
784-house ADMM point at its first rung (gap_1e-10 through the 40-05 seam; the
deterministic battery-certificate refusal at defaults reproduced exactly), the
agreement band is pinned gate-then-golden from that row (welfare rtol 6.22e-7, price
atol/rtol 1.78), the tracked skip is lifted, and src/ is diff-empty across the plan.**

## Performance

- **Duration:** ~1h55m wall (includes an operator pause: the session was cleanly
  stopped mid-Task-3 with all Julia processes killed; work resumed from the
  committed ladder rows and the recorded resume checklist, no measurement re-run)
- **Started:** 2026-10-24T19:39:00Z
- **Completed:** 2026-10-24T21:32:21Z
- **Tasks:** 3/3
- **Files modified:** 6

## Measured Results (the deliverable)

`results/case_a_population/agreement.csv` — the complete ladder record (Julia 1.12.5,
seed 42, T=24, 784 houses, 10 aggregators):

| agr_tol | admm_status | iters | welfare_admm | welfare_rel_delta | price_max_abs/rel_delta | verdict |
|---------|-------------|-------|--------------|-------------------|-------------------------|---------|
| `default` | error:CertificateError (kind=:battery) | 80 | — | — | — | refusal reproduced (deterministic); legacy row superseded in place |
| `gap_1e-10` | **converged** | 80 | -378163.5654347284 | 6.217147850629488e-8 | 0.17819846607479023 | **CERTIFIED — ladder stops (step 1 of 3)** |

- Centralized leg (both rows): `tol_gap_1e-10` path, welfare -378163.58894571784
  (reproduced exactly; default optimizer refused kind=:socp_exact as before).
- Winning-row recommended band (10× observed delta, floored at solver noise):
  `recommended_rtol_welfare = 6.217147850629488e-7`,
  `recommended_atol_price = recommended_rtol_price = 1.7819846607479022`.
- Rungs 2 (`gap_1e-12`) and 3 (`gapfeas_1e-12`) were NEVER run — stop-on-first-certified.

## Accomplishments

- **The POP-04 gap is closed the honest way:** a certified full-population ADMM point
  exists (converged, certificates green), the agreement deltas are measured, and the
  band is pinned FROM the measurement — no gate, tolerance, or default was loosened
  anywhere (`git diff HEAD -- src/` EMPTY for the whole plan).
- `scripts/case_a_agreement.jl` extended (not rebuilt): `AGR_TOL_RUNGS` Dict IS the
  bounded ladder spec; `--agr-rung` kv-flag with fail-loud validation; rung threaded
  through the 40-05 seam (default rung byte-identical); `agr_tol` column + extended
  upsert key with legacy coalescing (legacy row superseded in place, probed against a
  copy before touching the real CSV).
- `test/test_population_case_a_agreement.jl`: the tracked `@test_skip` REPLACED with
  live assertions — the ADMM leg re-solves at the winning rung (BLAS pinned to 1) and
  asserts `:converged` + welfare `isapprox(rtol = 6.217147850629488e-7)` + DADP
  `isapprox(atol = rtol = 1.7819846607479022)`; every pinned constant cites its exact
  CSV row and the 10×-floored rule in a comment (gate-then-golden, auditable).
- `test/expected_broken.txt`: the allowance DELETED in lockstep with the lift.
- `.planning/REQUIREMENTS.md`: POP-04 → `[x]` with the rung + band citation.
- `docs/literate/case_a_population.jl`: row filter selects the winning rung explicitly
  by `agr_tol`; prose rewritten to the measured closure (ladder history, seam
  mechanism, gates untouched); docs build green with the winning figures rendered.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend case_a_agreement.jl with the pre-planned rung ladder** - `99982c1` (feat)
2. **Task 2: Run the bounded ladder — stop-on-first-certified** - `e9ebb66` (data, step 0: default regression + legacy migration) + `eac9400` (data, step 1: gap_1e-10 CERTIFIED; steps 2-3 never run)
3. **Task 3: Land the terminal state — Branch A closure** - `967755d` (wip-labeled; see Deviations) 

## Files Created/Modified

- `scripts/case_a_agreement.jl` — the pre-planned ladder (Dict spec, flag, threading,
  agr_tol column + legacy coalescing)
- `results/case_a_population/agreement.csv` — the ladder record (2 rows, both honest)
- `test/test_population_case_a_agreement.jl` — skip lifted; live band assertions with
  per-constant CSV-row citations
- `test/expected_broken.txt` — the agreement-skip allowance removed
- `docs/literate/case_a_population.jl` — agreement section = the measured closure
- `.planning/REQUIREMENTS.md` — POP-04 complete with citation

## Decisions Made

- **Stop at the first certified rung:** gap_1e-10 cleared the 0.04%-over-band noise
  product exactly as the plan predicted; the deeper rungs stay untried by policy.
- **Pin verbatim from the row:** the test constants equal the row's `recommended_*`
  cells bit-for-bit (verified programmatically against the CSV post-pin).
- **Keep the refused default row:** the CSV carries both the refusal (default) and the
  certification (gap_1e-10) — the complete honest history.
- **Legacy coalescing in the upsert key:** rows without the rung column read back as
  `agr_tol = "default"`, so the re-measured default row replaced the legacy row in
  place (no stale duplicate; `only()` selections stay sound).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `get(::DataFrame, col, default)` does not exist — legacy
coalescing moved into the upsert `keyof`**
- **Found during:** Task 1 (probing the coalescing idiom against a copy of the real
  legacy CSV)
- **Issue:** the planned `coalesce.(get(old, :agr_tol, "default"), "default")`
  column-normalization throws (`no method matching get(::DataFrame, ::Symbol,
  ::String)`), and a column-existence guard + coalesce could not fit the verify's
  3-line `agr_tol` budget
- **Fix:** coalesced at KEY time instead — `keyof(r) = Tuple(coalesce(get(r, c,
  "default"), "default") for c in key)`; a DataFrameRow's `get` returns the default
  for an ABSENT column and `coalesce` maps a missing cell to `"default"`, exactly the
  plan's legacy-coalescing semantics (absent/missing → `"default"`), probed against a
  copy of the committed legacy CSV before the real run
- **Files modified:** scripts/case_a_agreement.jl (upsert_row)
- **Verification:** copy-of-CSV probe: legacy row superseded in place (1 row,
  values intact); rung rows coexist by key
- **Committed in:** 99982c1

**2. [Process note — not a code deviation] Task 3's changes landed in a WIP-labeled
commit (`967755d`) made during the operator pause**
- **Found during:** Task 3 close-out
- **Issue:** the session was cleanly stopped by the operator mid-Task-3 (Julia
  processes killed — the first two docs-build attempts died SIGTERM/SIGKILL); on
  resume the working tree held this plan's finished Task-3 edits, which were committed
  by the resuming hand as `wip(40-06)` alongside a `.continue-here.md` resume checklist
- **Fix:** no content change — the committed diff is exactly the intended Task-3 edit
  set (test item, allowance, docs, REQUIREMENTS); the remaining checklist items
  (band-vs-CSV verification, SUMMARY, tracking) were completed on resume; the commit
  is pushed, so no history rewrite
- **Files modified:** none beyond the Task-3 set
- **Verification:** slow lane 14/14 with 0 skips AFTER the resume; band constants
  programmatically verified == the winning row's recommended cells
- **Committed in:** 967755d (content), this SUMMARY (verification record)

---

**Total deviations:** 1 auto-fixed bug + 1 process note. **Impact on plan:** none on
the measurement or the terminal state; both gaps plans leave src/ byte-identical.

## Issues Encountered

- The docs build was killed twice (SIGTERM, then SIGKILL) by host memory pressure
  during the operator pause window; the retry on resume built green (exit 0), and the
  rendered HTML was verified to show the winning row's figures (welfare
  -378163.5654347284 certified, `converged`, all three band constants).
- None otherwise: the default-rung refusal reproduced deterministically, and the first
  tightened rung certified on the first attempt.

## User Setup Required

None - no external service configuration required.

## Threat Surface Scan

No new surface beyond the plan's `<threat_model>`: rungs only tighten Clarabel's own
convergence tolerances through the fixed Dict (T-40-06-01 — no gate kwarg exists in
the script; src/ diff empty); every executed run's outcome is committed (T-40-06-02 —
both the refusal and the certification are in the CSV); the pinned constants cite
their exact row (T-40-06-03 — programmatically re-verified); the ladder was bounded
and stopped at rung 1 (T-40-06-04); the docs page selects the cited row explicitly by
`agr_tol` (T-40-06-05 — `only()` fails loudly otherwise); the skip was lifted WITH its
allowance in the same change set (T-40-06-06 — no stale allowance); zero new packages
(T-40-06-SC).

## Next Phase Readiness

- **POP-04 is closed:** the roadmap's SC-3 agreement claim now holds with a measured,
  stated tolerance; the :slow lane asserts it live (28m54s full run incl. the
  784-house ADMM solve at the rung).
- **Phase 42 note (from the verification report) is resolved:** the DADP-vs-FIT
  protocol can require certified decomposed points — the certified gap_1e-10
  configuration is the measured answer to the refusal it would have hit.
- The default solve_admm path remains byte-identical everywhere (canary + gate diffs
  untouched across both gap plans); the seam is documented and additive.

---
*Phase: 40-784-house-thesis-population*
*Completed: 2026-10-24*

## Self-Check: PASSED

- FOUND on disk: scripts/case_a_agreement.jl, results/case_a_population/agreement.csv
  (2 rows: default refusal + gap_1e-10 certification), test/test_population_case_a_agreement.jl
  (skip lifted, live band), test/expected_broken.txt (allowance deleted),
  docs/literate/case_a_population.jl, .planning/REQUIREMENTS.md (POP-04 [x])
- FOUND in git log: 99982c1 (Task 1), e9ebb66 + eac9400 (Task 2, steps 0-1), 967755d
  (Task 3 content); 40-05's 2283c3a / 87f1ad2 / 04342b2 also present
- Band constants programmatically verified == the winning row's recommended_* cells
- Restricted slow lane: exit 0 — 14 pass / 0 skip / 0 fail (post-resume)
- Fast separation lane: exit 0 — 76 pass; docs build exit 0 (winning figures rendered)
- `git diff HEAD -- src/` EMPTY; tau_batt=1e-3 and every gate literal byte-identical
