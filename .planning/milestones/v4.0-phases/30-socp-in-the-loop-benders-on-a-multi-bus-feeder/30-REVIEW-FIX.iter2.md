---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
fixed_at: 2026-10-01T15:11:01Z
review_path: .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-REVIEW.md
iteration: 2
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 30: Code Review Fix Report (iteration 2)

**Fixed at:** 2026-10-01T15:11:01Z
**Source review:** .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-REVIEW.md
**Iteration:** 2 (the iteration-1 report is kept at `30-REVIEW-FIX.iter1.md`)

**Summary:**
- Findings in scope: 8 (2 Critical, 6 Warning)
- Fixed: 8
- Skipped: 0
- Info items: all 4 were small enough to fix, in 3 extra commits (listed at the end;
  not counted above).

All work was done directly on `main`, as instructed; no worktree was used. There is one
commit per finding.

**Golden impact:** no pre-Phase-30 golden moved. The Nash, certification, goldens,
integer and continuous Benders batches all pass with no changes to their expectations.
Two Phase-30-only test expectations changed, and both changes are intended:
- **`:reject` item.** It now converges instead of stalling (WR-02).
- **CR-02 end-to-end item.** It now asserts the certified point that used to be
  discarded (WR-01).

The T=24 Literate run is unchanged: iters=15, gap=3.09e-7, y=0.015, exact.

## Fixed Issues

### CR-01: `run_nash!` silently accepts relaxation-only best responses

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash.jl`, `docs/literate/integer_investment.jl`
**Commit:** 12bfef2
**Applied fix:**
- **New keyword.** `run_nash!` and `run_nash_probe` take `inexact_policy`, which defaults
  to `:strict`. It is checked at the boundary and forwarded to every inner
  `solve_stackelberg!`, so the pre-Phase-30 fail-loud behaviour is back.
- **Certificates.** If a caller opts into `:certify_incumbent` or `:reject`, every best
  response's certificate is collected on two new trailing result fields:
  - `certificates`: one row per best response with `sweep`, `distributor`,
    `incumbent_exactness`, `incumbent_socp_maxgap`, `ub_relaxation_only` and `ac_report`;
  - `any_relaxation_only`: true if any best response certified the relaxation only.
- **New test item.** It uses an N=2 IEEE-13 T=1 game with λ₀=[-1], which is measurably
  inexact:
  - the default `:strict` throws "SOCP relaxation INEXACT";
  - `:certify_incumbent` converges in 2 sweeps, and all 4 certificates are `:inexact`
    with maxgap 1.74e-2;
  - a bogus policy raises `ArgumentError`.
- **Literate page.** `integer_investment.jl` now passes `inexact_policy = :strict` to
  both calls and explains that this is a no-op on LinDistFlow.

**Nash goldens:** unchanged. All Nash fixtures use LinDistFlow, so `:strict` has no
effect on them.
**Status:** fixed

### CR-02: The integer-master recourse path ignores `inexact_policy`; bare `catch`

**Files modified:** `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`
**Commit:** 33ddc2f
**Applied fix:**
- **Policy threading.** `corner_recourse`, `_corner_recourse_ternary`,
  `_corner_recourse_joint` and `ll_cut_recourse` take `on_inexact`.
  `solve_stackelberg!` passes `:throw` under `:strict` and `:report` otherwise.
- **The bare `catch` is replaced by `_oracle_or_infeasible`.** Only an untrusted solve
  whose status is in `ORACLE_INFEASIBLE_STATUSES` maps to +Inf. Everything else is
  rethrown: non-`ErrorException`s such as `InterruptException`, throws from a trusted
  solve (exactness, complementarity), and any other status.
- **Ternary branch.** It uses the same classification. This only applies where it used
  to throw, so trajectories that previously completed are unchanged.
- **Why the LL cut stays valid.** Under `:report` the corner minimum is the
  relaxation's, which is never above the true minimum.
- **New test item (T=4).**
  - Classification: uniform z=0.07 maps to `nothing`, z=0.06 maps to `:inexact`.
  - At y=0.06, `:throw` now raises INEXACT. Before, it silently skipped the inexact
    region.
  - `:report` gives 609.0086589949267, which is ≤ the y=0.05 value 609.009650006013.

**Integer goldens:** unchanged (444/444 pass).
**Status:** fixed: requires human verification (LL-cut validity argument under `:report`)

### WR-01: Incumbent selection mixes relaxation-only and certified costs

**Files modified:** `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`
**Commit:** d366562
**Applied fix:**
- **Two incumbents.** The loop keeps the running-minimum incumbent, which drives
  convergence and is unchanged. It also tracks the best CERTIFIED iterate separately.
- **Ordering rule, in `_select_incumbent` (documented in the code):**
  - a certified running minimum is returned as-is;
  - a relaxation-only running minimum is replaced by the certified incumbent when that
    incumbent also passes the same convergence test against LB;
  - otherwise the relaxation-only point is returned, and the certified one is reported
    alongside.
- **New field.** `exact_incumbent = (; y, z, UB, gap, exactness, socp_maxgap)` is added
  at the end of the result, or `nothing`. Its `gap` is a real physical gap.
- **Tests.** A unit item covers the ordering. The CR-02 end-to-end item now asserts the
  certified point that used to be discarded: z≈0.010039, UB 12.2403, physical gap
  2.37e-3.

**Status:** fixed: requires human verification (ordering semantics)

### WR-02: `:reject` could never get past an inexact trial

**Files modified:** `src/planning/benders.jl`, `test/test_planning_inexact_policy.jl`, `30-FINDINGS.md`
**Commit:** c4430af
**Applied fix:**
- **New behaviour.** The review's design is sound and was adopted. A rejected trial now
  goes through the optimality branch: its `:op`/`:x` relaxation cuts and integer cuts
  are appended. These are valid lower bounds whatever the exactness verdict.
- **What stays barred.** A rejected trial never updates UB or the incumbent. Its trace
  row has `cut_type=:optimality` and `policy_action=:rejected`.
- **Stall guard.** It is kept as a backstop for the case where the relaxation's optimum
  is itself inexact.
- **Measured.**
  - T=4 fixture: `:reject` follows the same master trajectory as `:certify_incumbent`
    and converges at iteration 11 with the same exact incumbent
    (UB=609.0155321155983).
  - T=1 λ₀=[-1] fixture: the stall fires at iteration 5 at z=[0.04].
- **Tests.** Both cases are pinned.

**Status:** fixed: requires human verification

### WR-03: A post-convergence AC tooling failure discarded the converged result

**Files modified:** `src/planning/benders.jl`, `test/test_planning_ac_recheck.jl`, `test/test_planning_inexact_policy.jl`
**Commit:** 7fe353b
**Applied fix:**
- **Catching the failure.** `_incumbent_ac_report` catches an `ErrorException` from
  `ac_recheck_incumbent` and reports it in `ac_report`: `ok=false`,
  `raw_status="AC_RECHECK_FAILED"`, the welfare fields set to NaN, and the message in a
  new `error` field. `error` is `nothing` on success. Other exception types still
  propagate.
- **New test item.** The pin z=[0.0] (below the 0.01 load) makes Ipopt fail, and the
  failure shows up in `ac_report`.
- **IN-04, part 1.** The tautological `welfare_gap` equality was replaced by the measured
  magnitude (|gap| < 1e-6; measured 3e-10).

**Status:** fixed

### WR-04: `ac_report.ok` docstring over-claim

**Files modified:** `src/planning/ac_recheck.jl` (the `solve_stackelberg!` `ac_report` docstring was changed in 7fe353b)
**Commit:** dcfe43a
**Applied fix:** The docstring now explains what `ok` means. The model drops the limits
and re-optimizes, so:
- `ok = false` is a violation indicator ("not certified AC-realizable by this check"),
  not proof that no limit-respecting dispatch exists;
- `ok = true` is evidence, not proof.

It also notes that a limits-respecting `ACPowerFlow(limits = true)` feasibility solve
would be the real test, and leaves it as an extension: the BILEV-04b design fixes this
diagnostic to `limits = false`. This is a documentation-only change, as the orchestrator
directed.
**Status:** fixed

### WR-05: Build-time rejection slack vs runtime floor tolerance

**Files modified:** `src/planning/master.jl`, `src/planning/benders.jl`, `test/test_planning_alpha_bounds_stackelberg.jl`
**Commit:** 3488601
**Applied fix:**
- **Recorded slack.** `BendersMaster` gains `lb_slack = (; op, x)`:
  - `S + |gap_derive|` for an explicit bound validated against `bounds_ctx`;
  - 0 for `:auto` bounds and for unvalidated bounds.
- **Runtime check.** `_assert_epigraph_floor` adds this slack to its own tolerance
  (through `_accepted_lb_slack`, which returns 0 for `BendersMasterInteger`).
- **Proof (in the `ALPHA_LB_REJECTION_TOL` docstring).** An accepted bound can never
  fire the runtime check. A value below the derivation's own certified lower bound
  still fires.
- **New IEEE-13 T=4 item (y_max=0.05).** Measured values:
  - optimum 609.0096500784123, gap 1.525e-6, S 1.525e-5;
  - at the box argmax, cost_k = optimum − 1.68e-7 and tol_k = 6.09e-6.

  At α = optimum + S/2 the old rule false-fires and the new one does not. The item also
  checks that `:auto` bounds get slack 0.

**Status:** fixed: requires human verification

### WR-06: `FEAS_CUT_V_TOL` made a near-boundary infeasible trial fatal

**Files modified:** `src/planning/benders.jl`, `src/planning/trace.jl`, `test/test_planning_inexact_policy.jl`
**Commit:** d6f3275
**Applied fix:** `_feas_cut_class` applies a three-way rule, measured and documented:

| Measured v | Class | What happens |
|---|---|---|
| v > `FEAS_CUT_V_TOL` (1e-6) | separating | Cut appended, as before |
| `FEAS_CUT_V_NOISE` < v ≤ `FEAS_CUT_V_TOL` | weak | Cut appended with `policy_action=:oracle_feasibility_cut_weak` |
| v ≤ `FEAS_CUT_V_NOISE` | disagree | Error: the oracles disagree |

- **Noise floor.** `FEAS_CUT_V_NOISE` = 2.4e-9, which is 10× the 2.4e-10 noise measured
  at feasible pins for T=1 and T=4. No growth with T was observed, and this is
  documented.
- **Weak cuts.** These are still valid, by convexity of V. A deterministic
  re-proposal of the same z_k right after a weak cut raises a named stall error.
- **Trace.** `BendersTrace` gains an additive `feas_cut_v` column, which records v on
  every oracle-feasibility row.
- **What was not done.** The review's "repaired point" re-evaluation was not
  implemented, because it would put a point the master never proposed into the
  incumbent. The graceful-degradation rule above is used instead.
- **Tests.** A unit item covers the classification, and the T=4 run asserts that v is
  recorded.

**Status:** fixed: requires human verification (no natural fixture reaches the weak regime; only the classification is unit-tested)

## Info items (fixed; not counted above)

- **IN-01 (9370e05).** The stale `BendersTrace` docstrings were corrected:
  `cut_type :rejected`, `:certified_incumbent`, the four infeasibility statuses, and the
  new weak label.
- **IN-02 (5e36d48).** `solve_feasibility_oracle!` gains `attempts_out`. On the
  oracle-feasibility row, that solve is now timed and its retries are counted. The
  failed oracle solve's own attempts cannot be observed, and the code says so. The
  `:rejected` row already sums master and oracle retries, because WR-02 routes it
  through the optimality branch.
- **IN-03 and IN-04 (22b7eb5).**
  - `build_master` guards are now `(isa Real || === :auto)`, so `:atuo` raises
    `ArgumentError`; a new item covers this.
  - The rejection tests now match the message naming the rejected bound.
  - The IEEE-13 bracket comment states that only the LB side tests the decomposition.
  - The tautological `welfare_gap` equality was fixed in 7fe353b (see WR-03).

## Verification

Tests were run with the direct `@testitem` emulator only, all in the foreground (never
`Pkg.test()`):

| Batch | Test files | Result |
|---|---|---|
| 1 | oracle, benders, hardening, master, trace, noninteger | 186 pass / 0 fail |
| 2 | oracle, nash, coupling, certification, goldens | 194 pass / 0 fail / 1 broken (the existing CairoMakie `@test_skip`) |
| 3 | oracle, benders_integer, certification_integer, master_integer | 444 pass / 0 fail |
| 4 | Phase-30 files: oracle, feasibility_oracle, ac_recheck, alpha_bounds_stackelberg, inexact_policy, benders_ieee13, ieee13_short_fixture | 213 pass / 0 fail |

Literate scripts, each run end to end with exit code 0:
- `integer_investment.jl`, the touched one (`--project=.`);
- `nash_diagonalization.jl` and `stackelberg_benders.jl` (`--project=docs`).

The T=24 result is unchanged: iters=15, gap=3.0936e-7, y=0.015, `:exact`.

---

_Fixed: 2026-10-01T15:11:01Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
