---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
fixed_at: 2026-10-01T13:58:16Z
review_path: .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-REVIEW.md
iteration: 1
findings_in_scope: 13
fixed: 13
skipped: 0
status: all_fixed
---

# Phase 30: Code Review Fix Report

**Fixed at:** 2026-10-01T13:58:16Z
**Source review:** .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 13 (3 Critical, 10 Warning; Info excluded by `fix_scope = critical_warning`)
- Fixed: 13
- Skipped: 0

Work was done directly on `main`, as instructed; no worktree was used. Some findings
touched the same lines and were committed together: CR-01+CR-03, CR-02+WR-09+WR-10, and
WR-03+WR-04. IN-02 and IN-04 were fixed as a side effect and are noted below.

**Golden / production-answer impact:** no pre-Phase-30 planning golden moved. All
pre-Phase-30 planning test files pass unchanged, with one exception:
`test_planning_oracle.jl`'s return-shape assertion was extended to cover the two new
trailing fields (the five existing keys keep their names and order). Two Phase-30-only
`:auto`-bound trajectories were re-measured:
- **IEEE-13 T=4 headline test: moved slightly.** WR-04 lowers α_op_lb by the measured
  margin. UB went from 609.0113506 to 609.0113390, still 6 iterations. The header was
  updated with the re-measured values.
- **T=24 Literate run: unchanged.** It still gives iters=15, gap=3.09e-7, y=0.015.

## Fixed Issues

### CR-01: `:certify_incumbent` (the DEFAULT) silently bypasses the battery-complementarity gate

**Files modified:** `src/planning/subproblem.jl`, `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`, `test/test_planning_oracle.jl`
**Commits:** 2bdefc2, 16ebf45 (shape-test follow-up)
**Applied fix:**
- `solve_planning_oracle!` gained `on_inexact ∈ (:throw, :report)`. The default `:throw`
  behaves exactly as before.
- It now returns `exactness` and `socp_maxgap` as two extra trailing fields.
- Under `:report`, the exactness verdict is returned instead of thrown. Execution still
  goes through `assert_battery_complementarity!`, so every returned result passes the
  gate, inexact ones included.
- The hand-built result in `:certify_incumbent` is gone (this also fixes IN-02: `π_s`
  now uses `Δt`).
- A stale `:socp_maxgap` certificate is cleared at the start of each solve.
- New test: a negative τ trips the gate on an inexact `:report` result.

**Status:** fixed: requires human verification (policy-dispatch logic)

### CR-02: An inexact incumbent returns a "converged" UB/gap that is only a relaxation value, and `ac_report.ok` is always `true`

**Files modified:** `src/planning/benders.jl`, `src/planning/ac_recheck.jl`, `test/test_planning_ac_recheck.jl`, `test/test_planning_inexact_policy.jl`, `test/test_planning_alpha_bounds_stackelberg.jl`, `test/test_planning_benders_ieee13.jl`, `30-FINDINGS.md`
**Commit:** 34df23b
**Applied fix:**
- **New result fields.** The result now carries `incumbent_exactness`
  (:exact/:inexact/:not_applicable, which also fixes IN-04), `incumbent_socp_maxgap` and
  `ub_relaxation_only`. All three are recorded from the solve that produced UB.
- **Documentation.** The docstring states that UB and gap certify only the relaxation
  when `ub_relaxation_only` is true.
- **`ac_report` contents.** It now includes `socp_welfare`, `ac_welfare` and
  `welfare_gap`.
- **`ok` is computed, not hard-coded.** It is `n_thermal == 0 && n_voltage == 0`.
  Violations are counted beyond a per-instance measured tolerance: 10δ, where δ is the
  AC solve's own maximum primal residual, measured at 2e-9 to 1e-8.
- **Unit test.** The test that locked in `ok = true` now asserts `!r.ok`.
- **New end-to-end test.** It reaches the populated `ac_report` path through
  `solve_stackelberg!`, using single-Thermostatic T=1 IEEE-13 with λ₀=[-1.0]. The
  incumbent is z=0.04 and is inexact (measured maxgap 1.74e-2).
- **Docs.** The false claim in 30-FINDINGS.md §3 is corrected.

**Status:** fixed: requires human verification (certificate semantics)

### CR-03: The exactness-vs-other-throw disambiguation is wrong for formulations without an `:l` stash, so the original error is replaced by a FieldError

**Files modified:** `src/planning/subproblem.jl`, `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`
**Commit:** 2bdefc2 (together with CR-01)
**Applied fix:**
- The policy now dispatches on the explicit `oracle_res.exactness` verdict. It no longer
  checks whether `:socp_maxgap` is present.
- Any throw from a trusted solve is rethrown unchanged. That covers complementarity
  failures on any formulation and exactness failures under `:strict`.
- `socp_relaxation_gap` is only read inside the oracle, when `:l` exists.
- New tests check that LinDistFlow reports `:not_applicable` and that its
  complementarity error propagates with its own message.

**Status:** fixed: requires human verification

### WR-01: Any failed oracle solve is routed to an oracle feasibility cut and labelled `:genuinely_infeasible`, with no check that the cut separates z_k

**Files modified:** `src/planning/benders.jl`
**Commit:** f080d8a
**Applied fix:**
- Only statuses in `ORACLE_INFEASIBLE_STATUSES` (INFEASIBLE, INFEASIBLE_OR_UNBOUNDED,
  LOCALLY_INFEASIBLE, ALMOST_INFEASIBLE) reach the feasibility-cut branch. Any other
  failure is rethrown.
- The trace records the real termination status.
- A cut is appended only if `v > FEAS_CUT_V_TOL = 1e-6`; otherwise a named
  "oracles disagree" error is raised. How the threshold was chosen:
  - noise at feasible pins: |v| ≤ 2.4e-10;
  - the master's HiGHS feasibility tolerance: 1e-7;
  - the smallest genuine v observed: 3.86e-5.

**Status:** fixed: requires human verification

### WR-02: "Always feasible by construction" is an overclaim, and a feasibility-oracle failure masks the original error

**Files modified:** `src/planning/feasibility_oracle.jl`, `src/planning/benders.jl`
**Commit:** d5ac07b
**Applied fix:** The docstrings and comments now say the model is feasible only if some
`p_import` admits the network. If `solve_feasibility_oracle!` fails inside the loop, the
error is rethrown with both diagnoses and `z_k`.
**Status:** fixed

### WR-03: The build-time rejection threshold has zero tolerance, because margin and tolerance cancel exactly

**Files modified:** `src/planning/master.jl`, `test/test_planning_master.jl`, `30-FINDINGS.md`
**Commit:** 98ffa19
**Applied fix:**
- New functions `alpha_op_lb_derivation` and `alpha_x_lb_derivation` return
  `(optimum, gap, margin, bound)`.
- Rejection fires when `α > optimum + max(rejection_tol, 10·gap, 1e-8·|optimum|)`. The
  comparison is against the un-margined optimum. Because the true minimum lies within
  `gap` of the reported optimum, a bound equal to the true minimum is accepted with at
  least 9·gap of room.
- The T=8 test was updated to this rule.
- New test: a bound inside the slack above the optimum is accepted (the old rule
  rejected it), and a bound beyond the slack is still rejected.

**Status:** fixed: requires human verification

### WR-04: The α-bound margin and runtime-floor tolerance are absolute, toy-measured and not scale-aware, yet are applied to IEEE-13 SOCP

**Files modified:** `src/planning/master.jl`, `src/planning/benders.jl`
**Commit:** 98ffa19 (together with WR-03)
**Applied fix:**
- **New margin.** `margin = alpha_lb_margin(optimum, gap) = max(1e-6, 10·gap,
  ALPHA_LB_RTOL·|optimum|)`, where `ALPHA_LB_RTOL = 1e-8` (Clarabel's configured
  `tol_gap_rel`).
- **Re-measured duality gaps of the derivation solve:**

  | Case | Duality gap | Margin applied |
  |---|---|---|
  | Toy | 2.9e-9 / 2.5e-8 | 1e-6 floor (behaviour unchanged) |
  | IEEE-13 T=4 | 1.5e-6 to 4.5e-6 | 1.5e-5 / 4.5e-5 |
  | T=24 | 4.2e-5 | 4.2e-4 |

  The old 1e-6 margin was smaller than the solver's own error on the IEEE-13 cases.
- **Runtime floor check.** `_assert_epigraph_floor` uses the same formula, fed with the
  oracle's measured duality gap at each iteration.

**Status:** fixed: requires human verification

### WR-05: `socp_maxgap` is discarded on every exact iteration, contradicting CONTEXT and the trace docstring

**Files modified:** `src/planning/benders.jl`, `src/planning/trace.jl`, `test/test_planning_inexact_policy.jl`, `test/test_planning_benders_ieee13.jl`, `docs/literate/stackelberg_benders.jl`
**Commit:** 72a6410
**Applied fix:**
- The measured gap is now recorded on every row where the oracle solved, exact rows
  included. `NaN` remains only on feasibility rows and for formulations without a cone.
- `n_inexact_iterations` now counts `:certified_incumbent`/`:rejected` rows.
- The incumbent's own gap is returned.
- The tests now assert measured values:
  - on the inexact-policy run, inexact rows are more than 1000× the exact rows
    (1.7e-3 vs ≤ 1.4e-8);
  - on IEEE-13, every row is finite and exact.
- The Literate T=24 prose was re-measured: rows k=1, 14 and 15 give 3.02e-9, 3.03e-9
  and 4.09e-9.

**Status:** fixed

### WR-06: `:reject` deterministically burns the entire remaining iteration budget

**Files modified:** `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`, `30-FINDINGS.md`
**Commit:** 1d9b642
**Applied fix:**
- `:reject` now fails fast. If the same z (within 1e-9) is proposed again right after
  being rejected, the loop raises a named "`:reject` stalled at the SOCP-inexact trial"
  error at once.
- A no-good exclusion cut was not used: excluding a single point is not possible in a
  continuous LP master.
- The test asserts the stall message and 7 checkpoints; the stall comes at iteration 8,
  instead of running to `max_iter` and reporting "exhausted".

**Status:** fixed: requires human verification

### WR-07: The cross-check tolerance is a frozen, partly circular literal that is 10× looser than the certificate it checks, and its derivation is not reproducible

**Files modified:** `test/fixtures_planning_ieee13_short.jl`, `test/test_planning_benders_ieee13.jl`, `30-FINDINGS.md`
**Commit:** 512b7d6
**Applied fix:**
- **Joint reference.** `solve_joint_reference` now solves with `dual = true`, returns
  its own `gap`, and checks its own cone exactness with `assert_socp_exact!`
  (`socp_maxgap` = 2.1e-10).
- **New assertion.** The test checks `LB − ε ≤ J* ≤ UB + ε`, with
  `ε = 10·max(oracle_gap, joint.gap)` read at runtime. Measured ε = 2.78e-6, and J*
  sits strictly inside [LB, UB].
- **Header.** The citation of a nonexistent `joint.gap` and the frozen `10·(UB−LB)`
  literal are removed. The header now states that the reference only validates the
  decomposition, not the formulation.

**Status:** fixed

### WR-08: No test pins the sign or validity of the feasibility cut

**Files modified:** `test/test_planning_feasibility_oracle.jl`
**Commit:** 083f7c3
**Applied fix:** This covers both the thermal cut (z_k=0.07, feasible z=0.02) and the
voltage cut (z_k=0.5, feasible z=0.0). For each, the tests assert:
- `v > FEAS_CUT_V_TOL`;
- the cut excludes z_k;
- the cut keeps the measured feasible z;
- with u = −π the cut would exclude that feasible z, so a wrong sign fails the test;
- the re-solved master respects the cut.

**Status:** fixed

### WR-09: The AC re-check re-optimizes dispatch instead of evaluating the incumbent, and reports `p_import` for hour 1 only

**Files modified:** `src/planning/ac_recheck.jl`, `test/test_planning_ac_recheck.jl`
**Commit:** 34df23b (together with CR-02)
**Applied fix:**
- The docstring now says plainly what is checked: an AC dispatch re-optimized at the
  pinned z, with limits dropped, compared against the original limits.
- `p_import` is returned as the full length-T vector, together with `ac_welfare`.
- A wrong `length(z_incumbent)` now raises `ArgumentError`, and a test covers it.

**Status:** fixed

### WR-10: The incumbent re-check at convergence ignores `inexact_policy` and is affected by sticky retry attributes

**Files modified:** `src/planning/benders.jl`
**Commit:** 34df23b (together with CR-02)
**Applied fix:**
- The second oracle solve at convergence was removed. The incumbent's exactness is now
  the verdict of the solve that set UB, so sticky retry attributes cannot change it.
- That verdict can only be inexact under `:certify_incumbent`:
  - `:strict` throws on any inexact solve;
  - `:reject` never lets an inexact iterate become the incumbent.
- So `ac_report` is produced only under `:certify_incumbent`.
- After a run returns, `result.oracle` holds the state from the last iteration, as
  before Phase 30.

**Status:** fixed: requires human verification

## Verification

Tests were run with the direct `@testitem` emulator only (never `Pkg.test()`), all in
the foreground:

| Batch | Test files | Result |
|---|---|---|
| 1 | oracle, benders, hardening, master (incl. Phase-30 items), trace, noninteger | 182 pass / 0 fail |
| 2 | oracle, nash, certification, goldens | 163 pass / 0 fail / 1 broken (the existing `@test_skip` on CairoMakie in `test_planning_nash.jl:588`) |
| 3 | oracle, benders_integer, certification_integer | 72 pass / 0 fail |
| 4 | Phase-30 files: oracle, feasibility_oracle, ac_recheck, alpha_bounds_stackelberg, inexact_policy, benders_ieee13, ieee13_short_fixture | 154 pass / 0 fail |

`test_planning_oracle.jl`'s items run in every batch because its `ToyDeviceFixture` module
has to be loaded.

The Literate script `docs/literate/stackelberg_benders.jl` was re-run end to end: exit 0,
same T=24 numbers as before.

---

_Fixed: 2026-10-01T13:58:16Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
