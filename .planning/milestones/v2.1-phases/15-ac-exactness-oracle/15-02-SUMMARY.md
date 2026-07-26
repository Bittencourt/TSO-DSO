---
phase: 15-ac-exactness-oracle
plan: 02
subsystem: optimization
tags: [julia, jump, socp-exactness, ac-opf, certification, tolerance]

requires:
  - phase: 15-ac-exactness-oracle
    provides: ACPowerFlow peer formulation + recover_voltage_angles + pf_vars field-name convention (plan 15-01)
  - phase: 04-socp-exactness
    provides: assert_socp_exact! scale-free atol+rtol·magnitude tolerance idiom
provides:
  - assert_ac_exact!(ctx_socp, ctx_ac; rtol, atol) — per-hour SOCP-vs-AC certification returning (; obj_gap, hours::Vector{NamedTuple}), report-don't-throw on numeric gaps
affects: [15-03]

tech-stack:
  added: []
  patterns:
    - "Report-don't-throw certification: compare two independently-trusted solves, return an inspectable per-hour report, raise ONLY on structural mismatch"
    - "Reuse assert_socp_exact!'s scale-free atol + rtol·magnitude bound per-hour across two contexts instead of per-branch within one"

key-files:
  created: []
  modified:
    - src/models/ac_oracle.jl
    - test/test_ac_oracle.jl

key-decisions:
  - "assert_ac_exact! structurally cannot resolve to a throw on a numeric gap — the ONLY error() call is the T-mismatch structural guard; a genuine per-hour gap surfaces in the report (EXACT-03)"
  - "Return (; obj_gap, hours) as a plain Vector{NamedTuple} — no DataFrames dependency (RESEARCH Open Question 2 resolved to keep the file minimal)"
  - "The divergence from assert_socp_exact!'s throw-on-inexact contract is asserted directly by a non-throwing KNOWN-exact test + a throwing structural-mismatch test, not merely documented"

patterns-established:
  - "Two-context exactness certification distinct from single-context price refusal"

requirements-completed: [EXACT-02, EXACT-03]

duration: 8min
completed: 2026-07-26
---

# Phase 15 Plan 02: assert_ac_exact! Per-Hour Certification Summary

**assert_ac_exact! certifies the SOCP relaxation against the AC oracle per-hour on objective/voltage/branch-flow gaps using the scale-free atol+rtol·magnitude idiom, returning an inspectable Vector{NamedTuple} report and throwing ONLY on a structural T mismatch — never on a genuine numeric gap**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-26T00:29:14Z
- **Completed:** 2026-07-26T00:36:45Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `assert_ac_exact!(ctx_socp, ctx_ac; rtol=1e-4, atol=1e-6)` compares a solved `ConvexBranchFlow` context against a solved `ACPowerFlow` context on per-hour max voltage / active / reactive gaps, `exact = vgap ≤ atol + rtol·vmag && pgap ≤ atol + rtol·pmag` (the SAME scale-free bound `assert_socp_exact!` uses), returning `(; obj_gap, hours)` — `hours` a `Vector{NamedTuple}` of `(; t, vgap, pgap, qgap, exact)`, NEVER a bare Bool.
- The ONLY `error()` path in the whole file is the structural `T`-mismatch guard; a genuine numeric disagreement is REPORTED, never thrown (EXACT-03). Verified on a known-exact 2-bus solve: all hours exact, `obj_gap ≈ -2.9e-9`.
- Test coverage asserts the report-don't-throw divergence DIRECTLY: a non-throwing KNOWN-exact item and a throwing structural-mismatch (`@test_throws Exception`) item. All 4 `ac_oracle` @testitems GREEN (19 asserts).

## Task Commits

1. **Task 1: assert_ac_exact! per-hour report** - `9314b6a` (feat)
2. **Task 2: exact-fixture + structural-mismatch test coverage** - `0b30d90` (test)

## Files Created/Modified
- `src/models/ac_oracle.jl` - Appended assert_ac_exact! after recover_voltage_angles; extended export line to `recover_voltage_angles, assert_ac_exact!`
- `test/test_ac_oracle.jl` - Added KNOWN-exact and structural-mismatch @testitems (now 4 total)

## Decisions Made
- Followed plan as specified. Plain `Vector{NamedTuple}` return (no DataFrames dep).

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `assert_ac_exact!` ready for plan 15-03's high-PV stress fixture, which will feed it two solves in the exactness-boundary regime and assert a POSITIVE (non-throwing) finding.
- No new package added.

---
*Phase: 15-ac-exactness-oracle*
*Completed: 2026-07-26*
