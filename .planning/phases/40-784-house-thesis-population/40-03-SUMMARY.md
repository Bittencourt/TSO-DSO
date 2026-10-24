---
phase: 40-784-house-thesis-population
plan: 03
subsystem: measurement-harness
tags: [julia, admm, centralized-welfare, agreement-measurement, gate-then-golden, certificate-refusal, honesty-policy, slow-test]

# Dependency graph
requires:
  - phase: 40 plan 01 (:case_a_784 selector)
    provides: build_population(:case_a_784, ...) (10 bus-level roll-ups, 784 houses),
      sub_seed streams, _CASE_A_TOTAL_HOUSES
  - phase: 40 plan 02 (scaling report)
    provides: the recorded full-population battery-certificate refusal (escalation
      signal), honest-recording CSV contract, case_a_scaling.jl conventions
  - phase: admm/welfare cores
    provides: solve_welfare (assert_socp_exact! gate + optimizer kwarg), solve_admm
      (iters/status/exact_maxgap, ρ required kwarg), extract_dlmp
provides:
  - "scripts/case_a_agreement.jl — full-population both-engines measurement
    (gate-then-golden producer): observed deltas, ADMM iters/status, recommended band
    derivation (when measurable), provenance-keyed CSV row"
  - "results/case_a_population/agreement.csv — the POP-04 agreement record: centralized
    certified at tol_gap_1e-10 (welfare -378163.58894571784); ADMM at executor defaults
    refused (error:CertificateError, 80 iters); no measurable agreement deltas"
  - "test/test_population_case_a_agreement.jl — :slow-tagged agreement testitem with the
    blocked band carried as a loud, allowlisted tracked skip + the centralized leg and a
    re-derived dual-sign noise-band anchor asserted"
affects: [40-04 calibration docs, phase verifier (POP-04 routing), certificate
  investigation backlog, phase-41]

# Tech tracking
tech-stack:
  added: []   # zero new packages
  patterns:
    - "Gate-then-golden under a blocked measurement: no band constants are invented —
      the missing pin is a loud tracked skip (expected_broken.txt exact-key allowance)
      citing the CSV + regeneration command, never a hand-picked band"
    - "Solver-precision response to a gate refusal: tol_gap_abs/rel = 1e-10 on the
      SOLVER, the gate never touched, the path recorded in the CSV
      (centralized_optimizer column)"
    - "Dual-sign anchor re-derivation: scale-dependent invariants are re-measured at
      the new scale before pinning (zero price floor at PV saturation)"

key-files:
  created:
    - scripts/case_a_agreement.jl
    - results/case_a_population/agreement.csv
    - test/test_population_case_a_agreement.jl
  modified:
    - scripts/README.md
    - test/expected_broken.txt

key-decisions:
  - "Band NOT pinned: the ADMM leg at executor defaults converges (80 iters) but the
    battery-complementarity certificate refuses the full-population point — no certified
    agreement point exists, so pinning any band would violate gate-then-golden; the
    missing pin is a loud tracked skip citing agreement.csv (lift on re-measurement)"
  - "Centralized leg records centralized_optimizer=tol_gap_1e-10: the default optimizer
    was refused (CertificateError kind=:socp_exact — research Pitfall 4 artifact at full
    scale); the SOLVER was tightened, the exactness/battery gates byte-identical
    (git diff over src/ empty)"
  - "Dual-sign anchor re-derived for the full population: all(>(0), dlmp_c) falsifies on
    solver noise at the ZERO price floor of midday PV saturation (16/240 elements in
    [-1.9893e-6, -1e-7], buses 4/9/10, hours 9-14); pinned as a noise-band check
    (10x the measured deepest excursion = 1.99e-5) + positivity at congestion hours"
  - "POP-04 deliberately NOT marked complete: the requirement's agreement-within-tolerance
    deliverable is blocked by the measured refusal — routed to the phase verifier instead
    of being papered over"

patterns-established:
  - "Blocked-band tracking: agreement-band assertions blocked by a measured refusal live
    as an exact-key expected_broken.txt skip whose message carries the blocker and the
    regeneration command — it cannot silently rot (unlisted skips fail the run)"

requirements-completed: []   # plan frontmatter says [POP-04]; NOT completed — see below
requirements-blocked:
  - "POP-04: centralized leg certified (tol_gap_1e-10 path); ADMM leg refused at the
    battery certificate at executor defaults, so no agreement tolerance is measurable;
    blocked pending the certificate investigation — routed to the phase verifier"

# Metrics
duration: 32min
completed: 2026-10-24
---

# Phase 40 Plan 3: Centralized-vs-ADMM Agreement Measurement Summary

**Full-population POP-04 agreement measured gate-then-golden: the centralized 784-house
point certifies only under the tightened SOLVER (tol_gap 1e-10; default refused
kind=:socp_exact — welfare -378163.58894571784, gate untouched) while ADMM at executor
defaults converges (80 iters) and is refused by the battery-complementarity certificate —
so no agreement band is pinnable and the missing pin ships as a loud tracked :slow skip.**

## Performance

- **Duration:** 32 min
- **Started:** 2026-10-24T14:48:19Z
- **Completed:** 2026-10-24T15:20:43Z
- **Tasks:** 2/2
- **Files modified:** 3 created + 2 modified

## Measured Results (the deliverable)

`results/case_a_population/agreement.csv` (one provenance-keyed row: Julia 1.12.5,
seed 42, T=24, 784 houses, 10 aggregators):

| quantity | value |
|----------|-------|
| centralized_optimizer | `tol_gap_1e-10` (default optimizer REFUSED: `CertificateError kind=:socp_exact` — the research-Pitfall-4 solver-precision artifact, exactly as the plan anticipated) |
| welfare_centralized | -378163.58894571784 (certified; gates byte-identical) |
| admm_iters | 80 (dual-ascent loop CONVERGED) |
| admm_status | `error:CertificateError` (kind=:battery — the final consolidation's battery-complementarity gate refuses the converged point; the 40-02 escalation signal reproduced deterministically) |
| welfare_admm / deltas / recommended band | missing — no certified ADMM point exists at this configuration, so NO agreement delta is measurable and NO band constants are invented |

The A5 escalation signal is now recorded in the committed CSV: at executor defaults
(ρ = ADMM().ρ = 100, nothing re-tuned) the full-population ADMM point is refused by the
battery-complementarity certificate (~1e-12 relative band at the per-house-divided battery
scale; 40-02 diagnosed the converged product 0.04% over the band). This is a measured
finding for phase verification, never tuned away here.

## Accomplishments

- **POP-04 measured, honestly:** both engines ran on the SAME 10-aggregator roll-up
  (`aggs` constructed once); the centralized-vs-ADMM agreement state at full scale is now
  a committed CSV row, whatever its values.
- `scripts/case_a_agreement.jl` — the gate-then-golden producer: default-then-tightened
  centralized leg (the ONLY permitted response to a gate refusal: tighten the SOLVER,
  record the path), honest-recording of solver-outcome stalls as status rows
  (case_a_scaling.jl contract), provenance-keyed CSV upsert, fail-loud arg parsing,
  RECOMMENDED BAND derivation (10× observed delta, floored at solver noise) exercised
  when both legs certify.
- `test/test_population_case_a_agreement.jl` (`tags = [:population, :slow]`) — asserts
  what is honestly measurable (population shape; the centralized leg on the recorded
  tol_gap_1e-10 path certifies; DLMP finite + noise-band + congestion-hour positivity)
  and carries the BLOCKED band pin as one loud `@test_skip` allowlisted by exact key in
  `test/expected_broken.txt` — the repo's tracked-skip mechanism, so the skip cannot
  silently rot (unlisted skips fail the run).
- Dual-sign anchor re-derived gate-then-golden for the full population (see Deviations).
- `scripts/README.md` — `case_a_agreement.jl` indexed (CI guard green).
- Honesty policy intact: `git diff` over `src/` EMPTY for the whole plan — the exactness
  gate, battery gate, and every tolerance are byte-identical.

## Task Commits

Each task was committed atomically:

1. **Task 1: agreement measurement script + run — record observed deltas** - `0b9ecb8` (feat)
2. **Task 2: pin the band — `:slow` agreement testitem + README registration** - `6182abb` (test; band pin BLOCKED → tracked skip, see Deviations)

## Files Created/Modified

- `scripts/case_a_agreement.jl` — full-population both-engines agreement measurement
- `results/case_a_population/agreement.csv` — the measured POP-04 record (committed)
- `test/test_population_case_a_agreement.jl` — `:slow` agreement testitem (centralized
  leg asserted; band pin a tracked skip)
- `test/expected_broken.txt` — exact-key allowance for the blocked-band skip
- `scripts/README.md` — script index row

## Decisions Made

- **Band NOT pinned (the locked decision's honest outcome):** gate-then-golden forbids
  constants without a measurement; with the ADMM leg refused there is no measurement.
  The blocked assertion ships as the loud tracked skip instead of a vacuous or
  hand-picked band — exactly the plan's own "DO NOT paper over it — stop and surface at
  the phase level" instruction for this branch.
- **POP-04 deliberately left NOT-complete** (frontmatter `requirements-completed: []`
  despite the plan's `requirements: [POP-04]`): the requirement's
  agreement-within-tolerance deliverable does not exist yet. Marking it complete would
  launder the refusal. Routed to the phase verifier.
- **Centralized optimizer path recorded in the CSV** (`centralized_optimizer =
  tol_gap_1e-10`) with the header stating the gate was never modified
  (test_admm.jl:42-50 precedent).
- **ρ sourced from `ADMM().ρ`** at the ADMM call site (required kwarg; executor default —
  the locked A5 no-re-tuning configuration).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `solve_admm`'s `ρ` is a REQUIRED kwarg (the plan's literal call
would MethodError)**
- **Found during:** Task 1 (signature re-read; same discovery as 40-02's deviation #2)
- **Issue:** `solve_admm(feeder, PF, aggs; T = T, λ₀ = λ₀)` does not compile — `ρ::Real`
  has no default.
- **Fix:** pass `ρ = ADMM().ρ` (100.0, the strategy's own executor default) — the locked
  no-re-tuning configuration, not a tuning choice.
- **Files modified:** scripts/case_a_agreement.jl
- **Verification:** the ADMM leg ran at executor defaults (80 iters, refusal identical to
  the 40-02 ladder/sweep legs)
- **Committed in:** 0b9ecb8

**2. [Rule 2 - Missing Critical] Solver-outcome exceptions would kill the run and DROP
the measured outcome (both legs)**
- **Found during:** Task 1 (first run: the default-optimizer centralized leg THREW
  `CertificateError kind=:socp_exact`; the ADMM leg THROWS `CertificateError
  kind=:battery` at consolidation — the plan's "Record r.iters, r.status" assumes `r`
  exists)
- **Fix:** record solver-outcome exceptions (`ConvergenceError`/`CertificateError`/
  `SolveFailedError`) as honest status rows (iters from the error, welfare/exact_maxgap
  missing) — the exact contract 40-02 established (`f7711a0`); misuse errors still
  propagate. This recording path is what made the refusal row exist at all.
- **Files modified:** scripts/case_a_agreement.jl
- **Verification:** the committed CSV row carries `admm_status =
  error:CertificateError`, `admm_iters = 80`; the plan's automated verify passes
- **Committed in:** 0b9ecb8

**3. [Rule 1 - Bug] `:tol_gap_1e-10` parses as SUBTRACTION (`:tol_gap_1e - 10`)**
- **Found during:** Task 1 (first run: `MethodError: no method matching
  -(::Symbol, ::Int64)` exactly at the tightened-path return)
- **Issue:** Julia's parser reads `-` inside a bare Symbol literal as binary minus.
- **Fix:** hoisted `TOL_GAP_PATH = Symbol("tol_gap_1e-10")` and used it at both sites.
- **Files modified:** scripts/case_a_agreement.jl
- **Verification:** the tightened leg ran and the row records `tol_gap_1e-10`
- **Committed in:** 0b9ecb8

**4. [Rule 1 - Bug] The plan's literal dual-sign anchor `@test all(>(0), dlmp_c)`
falsifies at full scale on solver noise**
- **Found during:** Task 2 (first restricted slow-lane run: 1 fail at exactly that
  assertion)
- **Issue:** at the midday PV-saturation hours (9-14) the full-population DLMP floor is
  ZERO; a measurement probe showed 16/240 elements in [-1.9893e-6, -1.0e-7] at buses
  4/9/10 — solver noise around that floor (STATE.md: the detectability floor at default
  tolerance is ~1e-6), not genuine negative prices. test_admm.jl's positive-price
  invariant was calibrated on small fixtures and does not transfer.
- **Fix:** re-derived the anchor gate-then-golden for THIS population: `all(isfinite,
  dlmp_c)` + `minimum(dlmp_c) > -1.99e-5` (= 10× the measured deepest excursion,
  rounded up; derivation and probe cited in the file header) + `maximum(dlmp_c) > 0`
  (congestion/voltage hours still price strictly positive).
- **Files modified:** test/test_population_case_a_agreement.jl
- **Verification:** restricted slow lane exit 0 (11 pass / 1 allowlisted skip / 0 fail)
- **Committed in:** 6182abb

---

**Total deviations:** 4 auto-fixed (2 bugs, 1 missing-critical, 1 blocking)
**Impact on plan:** all fixes were required for the measurement to exist or be honest;
no scope creep; the gate/tolerance surfaces were never touched.

## Issues Encountered

- **THE blocker (recorded, routed):** the full-population agreement band is NOT pinnable
  because the ADMM leg at executor defaults is refused by the battery-complementarity
  certificate at the final consolidation (`CertificateError kind=:battery`, 80 iters —
  the same deterministic refusal 40-02 recorded four times and diagnosed: converged
  product 0.04% over a ~1e-12 relative band at the per-house-divided battery scale).
  Per the plan's own Task-2 instruction ("DO NOT paper over it — stop and surface at the
  phase level instead of pinning a vacuous test") the band pin is a loud tracked skip
  citing the CSV + regeneration command, and POP-04 is left open for the phase verifier.
  Fix path per repo policy: certificate-noise/solver-precision investigation (the
  Phase-26 η<1 KKT round-trip backlog item is the candidate mechanism), then re-measure
  and pin — never a tolerance loosening.
- The default-optimizer centralized leg refused with `kind=:socp_exact` (research
  Pitfall 4, anticipated by the plan); the sanctioned tol_gap tightening resolved it —
  recorded in the CSV, gate untouched.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. The blocked agreement-band assertion is a tracked, reason-carrying skip (not a
stub): it cites the measured blocker and the exact regeneration command, and the
centralized-leg assertions in the same item are live and green.

## Threat Surface Scan

No new surface beyond the plan's `<threat_model>`: T-40-08 (golden laundering) — no band
constants were pinned at all, so none could be laundered; T-40-09 (gate loosening) —
`git diff` over `src/` empty for the whole plan, the only solver move was tol_gap
tightening recorded in the CSV; T-40-10 (repudiation) — the row carries
julia_version/seed/t_horizon, keyed upsert, regeneration command in the script header;
T-40-11 (CI budget) — `TSODSO_TEST_SET=fast` selects 0 items from the new file (proven
by the fail-loud zero-selection guard).

## Next Phase Readiness

- Ready for 40-04 (composition/calibration docs): the population, scaling artifacts and
  the agreement record all exist; 40-04 can cite agreement.csv's honest state.
- **Escalation for the phase verifier:** POP-04's agreement-within-tolerance is BLOCKED
  by the battery-certificate refusal at full scale (centralized side certified; ADMM
  side refused). Candidate resolutions for a follow-up plan: (a) certificate-noise /
  solver-precision investigation of the consolidation battery gate (the 0.04%-over-band
  diagnosis suggests a precision fix, e.g. tighter subproblem tol_gap — requires a
  solve_admm solver-precision seam, currently absent), or (b) the Phase-26 η<1
  KKT-consistent round-trip backlog item (on_violation policy for the degenerate
  small-battery regime). Neither is a tolerance loosening.
- The tracked skip in `test/expected_broken.txt` is keyed exactly and self-documenting;
  lifting it after a re-measurement is a one-file + one-line change plus the pinned band.

## Self-Check: PASSED

- FOUND: scripts/case_a_agreement.jl, results/case_a_population/agreement.csv,
  test/test_population_case_a_agreement.jl, scripts/README.md (row),
  test/expected_broken.txt (allowance) — all on disk
- FOUND: commits 0b9ecb8 (Task 1) and 6182abb (Task 2) in git log
- `git diff HEAD -- src/` EMPTY (gate/tolerance surfaces byte-identical)
- `python3 .github/scripts/check_scripts_index.py` exit 0 (42 tracked files checked)
- Restricted slow lane: exit 0 — 11 pass / 1 allowlisted skip / 0 fail / 0 error,
  0 soft-scope warnings, 0 unexpected broken/skipped records
- Fast lane: `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_population_case_a_agreement.jl`
  fails loud with "entry matches no @testitem" — 0 fast items selected (T-40-11 verified)
- Plan-level Task-1 verify passed verbatim (schema + honesty on agreement.csv)

---
*Phase: 40-784-house-thesis-population*
*Completed: 2026-10-24*
