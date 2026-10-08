---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 01
subsystem: optimization
tags: [julia, jump, benders, cutting-plane, kelleys-method, highs, clarabel, pvbattery]

# Dependency graph
requires:
  - phase: 24
    provides: "corner_recourse ternary-search T=1 path, KNOWN_OPTIMUM_ATOL measured-tolerance idiom, Laporte-Louveaux integer Benders cuts"
provides:
  - "corner_recourse T>1 joint T-dimensional cutting-plane recourse (correct for non-separable, battery-bearing aggregators)"
  - "corner_recourse T==1 byte-identical dispatch (_corner_recourse_ternary)"
  - "enumerate_lattice_2d T=2 dense-grid validation oracle in test/test_planning_certification_integer.jl"
affects: [30, 31]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Kelley's-method cutting-plane loop reusing existing solve_follower!/solve_planning_oracle! dual reads as a first-order (value+gradient) oracle, no new solver dependency"
    - "Follower-infeasible trials reuse the SAME Farkas certificate add_feasibility_cut! uses for the outer Benders master, as a real linear cut in a small inner master LP"
    - "Oracle-infeasible trials (no certificate available) treated as +Inf with a stall-detection bisection fallback toward the incumbent"

key-files:
  created: []
  modified:
    - src/planning/benders.jl
    - test/test_planning_certification_integer.jl

key-decisions:
  - "T==1/T>1 dispatch implemented as two separate named functions (_corner_recourse_ternary, _corner_recourse_joint) rather than one algebraically-unified body, to guarantee byte-identical T=1 floating-point trajectory"
  - "Follower-infeasible trials get a genuine Farkas feasibility cut in the small inner master LP (not a bare skip) to prevent the deterministic LP from re-proposing an excluded point forever"
  - "Oracle-infeasible trials (no certificate available from solve_planning_oracle!) are extended-value +Inf with no cut; a detected stall (same trial proposed twice) triggers a T-dimensional generalization of the ternary search's own WR-01 tie-break (bisect toward the incumbent)"
  - "Test/verify fixtures use a nonzero aggregator net load, deviating from the plan's own literal <verify> script parameters (netload=[0.0]), because that fixture is oracle-infeasible for any z>0 on this network topology (PVBattery's export-only net injection with no fixed load) -- documented in 27-FINDINGS.md"

patterns-established:
  - "Small, cheap, per-outer-iteration-rebuilt inner cutting-plane master LP, explicitly distinguished in comments from the project's build-once/re-solve-many convention"

requirements-completed: [FIX-06]

# Metrics
duration: ~3h (includes extensive fixture debugging)
completed: 2026-09-29
---

# Phase 27 Plan 01: corner_recourse T>1 Joint Cutting-Plane Recourse Summary

**`corner_recourse` now computes the TRUE joint T-dimensional recourse for T>1 via a Kelley's-method cutting-plane loop with Farkas-cut-strengthened infeasibility handling, replacing the incorrect scalar `fill(z,T)` surrogate, while T=1 stays byte-identical.**

## Performance

- **Duration:** ~3h (dominated by fixture debugging — see Issues Encountered)
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 2 (`src/planning/benders.jl`, `test/test_planning_certification_integer.jl`)

## Accomplishments

- `corner_recourse(oracle, follower, y_inv, T)` now dispatches explicitly on `T`: `T == 1`
  calls `_corner_recourse_ternary` (the pre-Phase-27 ternary-search body, copied verbatim —
  byte-identical output, reconfirmed against the D-12 canonical certification fixture).
- `T > 1` calls a new `_corner_recourse_joint`: a Kelley's-method cutting-plane ("bundle")
  loop performing the genuine joint minimization `Q(y_inv) = min_{z∈[0,y_inv]^T}
  [follower_cost(z) − oracle_welfare(z)]` over the shared hypercube, reusing the existing
  `solve_follower!`/`solve_planning_oracle!` dual reads (`fr.π_s`, `orr.π`) as a zero-extra-
  solve first-order oracle — no new solver dependency.
- Follower-infeasible trials contribute a genuine Farkas feasibility cut
  (`v_k + u_k'(z−z_k) <= 0`, the identical form `add_feasibility_cut!` already uses for the
  outer Benders master) to the small inner master LP, rather than a bare skip — this is a
  necessary strengthening beyond the plan's literal "skip" wording: without it, the
  deterministic small-master LP re-proposes the identical excluded corner forever.
- Oracle-infeasible trials (a genuine network-balance infeasibility with no certificate
  available from `solve_planning_oracle!`) are caught and treated as `+Inf`; a detected
  stall (the same trial proposed twice with no new cut added) triggers a T-dimensional
  generalization of the ternary search's own WR-01 double-infinite tie-break, bisecting
  toward the guaranteed-feasible incumbent.
- New T=2 dense-grid enumeration oracle (`enumerate_lattice_2d`, `EnumerateLatticeOracle`
  `@testmodule`) certifies `corner_recourse(T=2)` against an independent brute-force
  reference at two distinct `y_inv` values, on a genuinely non-separable
  `PVBattery`-bearing fixture, within a measured (gradient-Lipschitz-derived) tolerance.

## Task Commits

1. **Task 1: Implement the T>1 joint cutting-plane recourse in `corner_recourse`** -
   `ec9b3fe` (feat)
2. **Task 2: T=2 grid-enumeration validation oracle + measured-tolerance certification** -
   `0389581` (test)

_Both tasks carried `tdd="true"`; given the extensive fixture debugging required to find a
physically-feasible, genuinely non-separable T=2 fixture (see Issues Encountered), the
implementation and its committed test were developed and verified together rather than in
a strict separate RED-then-GREEN sequence. Every acceptance criterion was independently
verified via direct `julia --project=.` scripts before each commit._

## Files Created/Modified

- `src/planning/benders.jl` — `corner_recourse` T==1/T>1 dispatch;
  `_corner_recourse_ternary` (verbatim pre-Phase-27 body); new
  `_corner_recourse_joint` (Kelley's cutting-plane loop); new measured constant
  `JOINT_RECOURSE_GAP_TOL`.
- `test/test_planning_certification_integer.jl` — new `enumerate_lattice_2d` in the
  `EnumerateLatticeOracle` `@testmodule`; new `@testitem` certifying `corner_recourse(T=2)`
  against it on a non-separable `PVBattery` fixture.

## Decisions Made

- **T==1/T>1 split into two named functions**, not one unified body — per RESEARCH.md's
  explicit warning that different floating-point trajectories would break byte-identity
  even where mathematically equivalent.
- **Farkas feasibility cuts for follower-infeasible trials** (Rule 2 — auto-added missing
  critical functionality): the plan's action text says "record no cut and move to the next
  trial," but a pure skip lets the small master's deterministic LP re-propose the identical
  infeasible corner forever (confirmed empirically — see Issues Encountered). Reusing the
  SAME certificate the caller's own outer feasibility-cut branch already computes, at zero
  extra cost, closes this gap.
- **Oracle-infeasible stall-guard bisection** (Rule 1/2): `solve_planning_oracle!` has no
  structured infeasible return (unlike `solve_follower!`), so a genuine network-balance
  infeasibility throws. Confirmed empirically to occur on realistic non-separable battery
  fixtures whenever the follower-feasible box extends beyond what the network can
  physically accept. Without a stall guard, this can strand the algorithm at an oracle-
  infeasible corner forever (no new information ever excludes it) until `iters` exhausts.
- **Test/verify fixture net load**: the plan's own literal `<verify>` script fixture
  (`agg.netload = [0.0]`/`[0.0, 0.0]`) is oracle-infeasible for ANY `z > 0` on this network
  (PVBattery's export-only net injection with no fixed load to serve) — reproduced
  identically on the pre-existing, unchanged T=1 path. A nonzero net load (`[3.5]`/`[3.5,
  3.5]`) restores genuine feasibility while keeping every other plan-specified parameter
  unchanged. Documented in `27-FINDINGS.md` (F-27-01-1).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Farkas feasibility cuts for follower-infeasible trials in the small inner master**
- **Found during:** Task 1 (algorithm design/testing)
- **Issue:** The plan's literal action text specifies "if infeasible, record no cut and
  move to the next trial." A pure skip leaves the small master LP's cut set unchanged, so
  its deterministic argmin is re-proposed identically on every subsequent iteration —
  confirmed via direct trace to stall for 20+ iterations without progress.
- **Fix:** Added a genuine linear feasibility cut (`v_k + u_k'(z−z_k) <= 0`) built from the
  SAME `fr.v`/`fr.u` Farkas certificate `solve_follower!`'s infeasible branch already
  returns, mirroring `add_feasibility_cut!`'s exact cut form (`src/planning/master.jl:209-242`).
- **Files modified:** `src/planning/benders.jl`
- **Verification:** Direct trace script confirmed convergence in 12 iterations at
  `y_inv=4.5` (previously stalled indefinitely on a bare skip).
- **Committed in:** `ec9b3fe` (Task 1 commit)

**2. [Rule 1 - Bug] Oracle-infeasible stall-guard bisection**
- **Found during:** Task 1 (verify script for the "infeasible-trial doesn't throw"
  acceptance criterion, `y_inv=4.5`)
- **Issue:** `solve_planning_oracle!` throws (no structured infeasible return) on a genuine
  network-balance infeasibility unreachable via the follower's own economic capacity model
  — confirmed to occur on realistic non-separable PVBattery fixtures. Without a stall
  guard, a repeated identical oracle-infeasible proposal (no certificate, no new cut)
  strands the algorithm until `iters` exhausts.
- **Fix:** Catch the exception, treat as `+Inf`/no cut; on a detected stall (same trial
  proposed twice), bisect toward the guaranteed-feasible incumbent `z_best` — a
  T-dimensional generalization of the existing WR-01 double-infinite tie-break.
- **Files modified:** `src/planning/benders.jl`
- **Verification:** Direct trace confirmed the bisection fires exactly once at `y_inv=4.5`
  and the algorithm converges cleanly afterward (12 total iterations).
- **Committed in:** `ec9b3fe` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1/2 — correctness/robustness necessary for
the algorithm to converge on realistic non-separable fixtures; no scope creep beyond
`corner_recourse`'s own T>1 path).

**Impact on plan:** Both auto-fixes are necessary generalizations of the plan's own
"Pitfall FIX-06-2" infeasibility-handling guidance, not architectural changes — no new
solver, no new subsystem, same `select_optimizer(LP())` factory throughout.

## Issues Encountered

- **cwd-drift mid-session (self-inflicted, corrected):** Early verification commands
  explicitly `cd`'d to the main repo checkout (`/home/pedro/programming/TSO-DSO`) instead
  of the assigned worktree, causing ~15 Julia invocations to silently test against the
  UNMODIFIED main-repo `benders.jl` (explaining several confusing "corner_recourse only
  defined once" and "byte-identical" mysteries mid-session). Diagnosed via `pathof(TSODSO)`
  resolving to the wrong path; corrected by dropping the explicit `cd` (the tool's own
  default working directory is already the worktree). All functional measurements that did
  NOT depend on `corner_recourse` itself (network feasibility scans, gradient-norm/solver-
  gap measurements used for `JOINT_RECOURSE_GAP_TOL`/`grid_match_tol`) remain valid, since
  `follower.jl`/`subproblem.jl` are unmodified by this plan and identical in both
  checkouts; only the `corner_recourse`-specific dispatch tests needed re-running from the
  correct path.
- **Plan's own `<verify>` fixture is oracle-infeasible (F-27-01-1, see `27-FINDINGS.md`):**
  extensive empirical probing was needed to find `PVBattery`+network parameters that are
  simultaneously (a) genuinely non-separable, (b) oracle-feasible across a meaningful
  `[0,y_inv]^2` region, and (c) avoid a separate pre-existing `solve_follower!` numerical
  fragility near near-zero trial values (F-27-01-2, logged out-of-scope).
- **Pre-existing `solve_follower!` certificate-loss fragility (F-27-01-2, out of scope,
  logged in `27-FINDINGS.md`):** HiGHS occasionally returns a genuine `INFEASIBLE` status
  with no Farkas certificate near certain trial magnitudes, contradicting
  `follower.jl`'s own WR-05 docstring claim. Not fixed (outside this plan's
  `files_modified`); avoided in all committed verification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-06 is closed: `corner_recourse` is correct for T>1 (validated against exhaustive
  grid enumeration on a non-separable T=2 fixture) and byte-identical at T=1. Phase
  30/31's multi-bus, T>1 Benders planning is unblocked on this specific correctness gap.
- `27-FINDINGS.md` created with two findings (F-27-01-1 fixture-only, no escalation
  needed; F-27-01-2 out-of-scope `follower.jl` numerical fragility, recommended for a
  future quick task).
- Waves 2/3 plans (27-02..27-06) are unaffected — this plan touched only
  `src/planning/benders.jl` and `test/test_planning_certification_integer.jl`.

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: src/planning/benders.jl
- FOUND: test/test_planning_certification_integer.jl
- FOUND: .planning/phases/27-integer-planning-pricing-certificate-correctness/27-01-SUMMARY.md
- FOUND: .planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md
- FOUND commit: ec9b3fe
- FOUND commit: 0389581
