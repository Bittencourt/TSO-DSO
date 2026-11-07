---
phase: 44-aggregator-as-actor
fixed_at: 2026-11-02T00:00:00Z
review_path: .planning/phases/44-aggregator-as-actor/44-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 44: Code Review Fix Report

**Fixed at:** 2026-11-02
**Source review:** .planning/phases/44-aggregator-as-actor/44-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (WR-01..WR-07; Info items out of scope)
- Fixed: 7
- Skipped: 0

All fixes were made in an isolated worktree and fast-forwarded onto `agents/session-2026-10-23`. The worktree, temp branch and recovery sentinel were removed. WR-06 and WR-07 share one commit because both edit the same literate-page passages.

## Fixed Issues

### WR-01: Slot-lambda agreement certificate tolerance

**Files modified:** `src/admm/admm_phases.jl`, `src/admm/solve_admm.jl`, `docs/literate/aggregator_actor.jl`
**Commit:** 32a6436
**Status:** fixed: requires human verification (tolerance choice)
**Applied fix:**
- Dropped the `slot_tol` keyword, which was fed the superseded `tol`. Added the named constant `SLOT_LAMBDA_AGREE_TOL = 1e-12`, with its measurement documented next to it.
- The observed max gap is 2.7e-15 on the shared-bus fixtures, as recorded in the `test_actor_portfolio.jl` header.
  - 3x observed is 8.1e-15, a few ulps of λ.
  - I pinned the repo's numerical-zero floor 1e-12 (`PortfolioFixtures.TOL_FLOOR`) instead, so the reported flag is not platform-fragile.
  - Say so if you want the literal 3x value.
- Docs and the `solve_admm` docstring now say what is compared: the primary slot's multiplier at the same bus, not `dual(balance_p)`. The certificate stays report-only and never throws.

**Verified:** Julia 1.12.5, `test_actor_portfolio.jl`: 171/171 pass. `jet_check` shows 0 new entries.

### WR-02: Opt-out RNG collision for several sites at one bus

**Files modified:** `src/experiments/materialize.jl`, `test/test_behaviour.jl`
**Commit:** 6acba96
**Applied fix:**
- `apply_behaviour` computes a per-bus occurrence rank. The first site at each bus has rank 0.
- The rank joins the SplitMix64 key only when it is greater than 0. Single-site-per-bus draws, which are every existing path and the pinned `test_behaviour.jl` draw test, are bit-identical.
- Added a testitem. Under `opt_out = 0.5` and `seed = 5`, the first site matches the single-site draws exactly. For at least one seed in 1:8, a twin site at the same bus gets a different opt-out pattern.

**Verified:** `test_behaviour.jl`: 201/201 pass, including the existing draw-pinning item.

### WR-03: Default-path byte-identity fence inert off 1.12.5

**Files modified:** `test/test_actor_default_fence.jl`
**Commit:** dd74dad
**Applied fix:**
- Kept the 1.12.5 digest gate and the goldens untouched.
- The fence header now documents the rationale: a deliberate plan decision, never re-pinned.
- Added version-independent assertions that run on every Julia version, for the IEEE-13 ground fixture:
  - Default `solve_admm` equals, bitwise, the `actors=[Portfolio per site]` plus `_force_slot_path=true` run on welfare, dadp, iters, every residual field and the key set.
  - Default `solve_welfare` equals, bitwise, the all-welfare-actors call on objective and dadp.

**Verified:** `test_actor_default_fence.jl`: 15/15 pass on 1.12.5. A first draft compared the `AdmmResiduals` struct with `==`, which has no value equality. I switched to fieldwise comparison.

### WR-04: JET baseline provenance and README counts

**Files modified:** `scripts/jet_baseline.txt`, `scripts/README.md`, `README.md`
**Commit:** eb82e36
**Applied fix:**
- README entry counts updated to 20 (`scripts/README.md:34` and `README.md:288`).
- Group 4 comment rewritten:
  - It names `has_4q_by_bus[j]` / `has_4q_by_bus[jj]` as the pre-existing `admm_phases.jl` source.
  - It records the measurement method: `jet_check.jl --update --baseline <scratch>` in a detached worktree at 1506ef5, Julia 1.12.7, JET 0.11.6.
  - It states that Phase 44's own `objectives[...]` / `site_objectives[...]` code adds no report.
- No baseline entries were added or changed.

**Verified:**
- Pre-phase 1506ef5 yields the same 20 signatures as the current tree.
- `jet_check.jl` on the fixed tree: 20 current, 20 baseline, 0 NEW, 0 FIXED. This also confirms WR-01..WR-03 introduced no new reports.
- `--selftest` OK.

### WR-05: Sweep CSV column order and runtime_s

**Files modified:** `scripts/actor_behaviour_sweep.jl`, `results/actor_behaviour/actor_behaviour_sweep.csv`, `docs/literate/aggregator_actor.jl`
**Commit:** f7bada4
**Applied fix:**
- Added the explicit `COLS` tuple and `ordered_columns`, used in `upsert!`. A column not listed is an error. A column no row carries is omitted.
- `runtime_s` is documented in the script header, at `COLS` and on the page as non-reproducible wall-clock. It stays because `test_actor_sweep.jl` requires it.
- The committed CSV was re-ordered only. No solves were re-run.

**Verified:**
- Every column's values and the row order are identical to the old file (22 rows, same column set).
- `test_actor_sweep.jl` with `TSODSO_TEST_SET=all`: 113/113 pass.

### WR-06: IEEE-123 null result and noise reference

**Files modified:** `docs/literate/aggregator_actor.jl`
**Commit:** 7fc0cf8 (shared with WR-07)
**Applied fix:**
- Section 4 now states the IEEE-123 behaviour grid is a null result at this fixture scale, with mixed-sign `dW` consistent with ADMM slack.
- The bitwise-identical `xi = 0` rows are labelled as not a noise measure.
- A live "noise floor" line was added, computed from the sign-mixed `dW` of the non-trivial rows.
  - Committed values: max |dW| = 1.41e-4 over 11 rows, 7 positive and 4 negative.
  - Welfare spread is 3.4e-9 relative. Mean DADP moves by at most 7.9e-6.
- The untested "saturation" mechanism claim is removed. The page now prints the m=1 to m=2 increment (5.9e-6) next to the ADMM-vs-centralized gap at m=0 (1.13e-4), both live.

**Verified:** `julia --project=. docs/literate/aggregator_actor.jl` runs end to end. Every printed figure is computed from the committed CSV.

### WR-07: Symmetric wedge and negative actor profit

**Files modified:** `docs/literate/aggregator_actor.jl`
**Commit:** 7fc0cf8 (shared with WR-06)
**Applied fix:**
- Section 1 states the wedge is a symmetric price shift (assumption A6): it is paid on net injection of both signs, so a net-exporting portfolio books a loss.
- Section 2 adds a live line: actor profit is negative on 3 of 3 `m > 0` rows (-0.1438, -0.2889, -0.5777).
- Also fixed the IN-04 markup typo in the same sentence (`ProfitObjective(m)`).

**Verified:** Same page run as WR-06.

---

_Fixed: 2026-11-02_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
