---
phase: 38-close-v4-0-audit-gaps
fixed_at: 2026-10-08T00:00:00Z
review_path: .planning/phases/38-close-v4-0-audit-gaps/38-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 4
skipped: 1
status: partial
---

# Phase 38: Code Review Fix Report

**Fixed at:** 2026-10-08
**Source review:** .planning/phases/38-close-v4-0-audit-gaps/38-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (WR-01..WR-05; the review has no Critical findings)
- Fixed: 4 (WR-01, WR-03, WR-04, WR-05)
- Skipped: 1 (WR-02: the measured fix moved the CI golden, so it was reverted. A doc note was committed instead.)
- Optional Info items fixed too: IN-01, IN-02, IN-04. IN-03, IN-05 (beyond the doc note added under WR-02), IN-06 and IN-07 were not touched.

All measurements: Julia 1.12.5 (`julia +release`), one Julia process at a time, targeted files only.
The knife-edge canary and every golden were left as they were. None was re-pinned.

## Fixed Issues

### WR-01: OOS exactness gate fails open on a NaN cone ratio

**Files modified:** `src/models/stochastic_welfare.jl`, `src/models/exactness.jl`
**Commit:** 32af868
**Applied fix:** `c.maxratio > 1 && throw(...)` became `c.maxratio <= 1 || throw(...)`, so a NaN ratio is now refused, as `assert_socp_exact!` refuses it. The `_socp_cone_check` docstring now states the invariant: `maxratio` is NaN whenever any cone value is NaN, so every consumer must use `<= 1`. I did not add a NaN unit test. It would need a solved JuMP model with NaN primal values, and I found no cheap way to build one. The invariant is documented on the kernel instead.
**Tests:** `file:test_stochastic_oos_harness.jl,test_exactness.jl` gave 50/50 Pass (unchanged).

### WR-03: Held-out gate verdicts depend on draw order (sticky escalation)

**Files modified:** `src/experiments/run_stochastic.jl`, `src/admm/DsoOpt.jl` (docstrings only)
**Commit:** 0fe8563
**Applied fix:** `_run_stochastic` snapshots the harness's ladder attributes right after the build, using the existing `_snapshot_ladder_attrs`. It restores them with `_restore_ladder_attrs!` before every held-out re-solve. The docstrings of both helpers now name this second caller.
**Measured (before -> after, 1.12.5):** at the default harness optimizer, no draw escalates in any of the three production scenarios. The `static_regularization_constant` stays at 1e-8 before and after every draw. Every value is bit-identical:
- CI golden `T=9, Stochastic(S=3, H_oos=5)`: welfare_gap -0.018591711034105174 -> -0.018591711034105174; 0/5 refused; ratios 0.2356, 0.2897, 0.1836, 0.1177, 0.366 (unchanged).
- Docs page (S=5, H_oos=10): 5/10 refused (draws 4, 6, 7, 9, 10) -> same; welfare_gap 0.03293196255276598 -> same.
- Compare script (seed 42): 0/10 refused; welfare_gap -0.0323948881649585 -> same.
- The stickiness is real once a solve escalates. With the tightened WR-02 optimizer, docs-page draw 1 escalates to 1e-6. Without the restore, every later draw inherits it and 7/10 are refused. With the restore, 4/10 are refused (draws 2, 3, 6, 7).
**Tests:** `file:test_run_stochastic.jl,test_stochastic_oos_harness.jl,test_status_policy.jl` gave 74/74 Pass (baseline 74).

### WR-04: The inexact-refusal test depends on solver imprecision

**Files modified:** `src/experiments/run_stochastic.jl`, `test/test_stochastic_oos_harness.jl`, `test/test_run_stochastic.jl`
**Commit:** c93733c
**Applied fix:**
- Refusal item (harness file): now uses the tightened optimizer (tol_gap 5e-10). The unperturbed solve is asserted exact (measured ratio 0.389). A forced slack, `l[1,1] >= value(l[1,1]) + 5e-6`, must then throw `CertificateError(:socp_exact)` (measured ratio 24.99; with δ=1e-6 it is 5.29, with 2e-5 it is 98.4). The helper must convert that refusal. Header note 3 is updated.
- New end-to-end item (run_stochastic file): `_run_stochastic` gained an internal keyword `solve_held_out! = _stoch_solve_held_out!`. This is a test seam; production behaviour is unchanged and `run_stochastic`/`run` do not pass it. A wrapper certifies the chosen draw first. It then forces a 5e-6 slack on the least-loaded branch at hour 1, using the real gate and the real conversion, and deletes the constraint afterwards. On the CI golden fixture the item checks:
  - status `:oos_inexact_skipped` and `inexact_h == [0,1,0,0,0]`;
  - ratio[2] > 1 (measured 24.54);
  - the other draws are bit-identical to an unperturbed run (measured diff 0.0);
  - `realized_welfare` is the mean over the 4 usable draws only (gap -0.026270859915143774, against -0.018591711034105174 unperturbed);
  - `welfare_gap = realized - in_sample`;
  - precedence over a stubbed infeasible draw (status inexact, both excluded, ratio NaN for the infeasible draw);
  - all 5 draws refused gives `realized_welfare`/`welfare_gap` NaN.
- No `:slow` tag: the file set ran in 1m47s against 1m52s before.
**Tests:** `file:test_run_stochastic.jl,test_stochastic_oos_harness.jl,test_status_policy.jl` went from 74 to 95 Pass: +1 assertion in the refusal item, +20 in the new item, items 15 -> 16. `--count-sets --strict`: all=518 fast=481 slow=37 files=99 canary=1 outside=0 (was 517/480).

### WR-05: Breaking behaviour changes missing from "Breaking changes"

**Files modified:** `docs/src/status_policy.md`
**Commit:** 7ea3abf
**Applied fix:** three bullets added to section 7:
1. The public `solve_stochastic_oos_step!` now throws `CertificateError(:socp_exact)` on an inexact re-solve.
2. `Scenario(strategy = ADMM(), allow_export = false)` now throws at construction, and so does a `run_sweep` grid that contains that combination, before any scenario runs.
3. The MPC first-tier floor changed from a flat 1e-6 to the hybrid `max(2e-7, 1e-9·ref_b)`. This can change `cert_status_trace`, `status` (`:certified` -> `:degraded`) and `dadp_trace`. The measured flip is 1 step on 1.12.7 and 0 on 1.12.5.

## Skipped Issues

### WR-02: Held-out harness is solved looser than the in-sample model

**File:** `src/experiments/run_stochastic.jl:274-281`
**Reason:** the measured fix moved the CI golden, so it was reverted under the revert rule. Documentation commit 25a3011 records the dependence instead.
**Measured (harness built at the in-sample tol_gap 5e-10, 1.12.5):**

| scenario | default 1e-8 (shipped) | 5e-10 without the WR-03 restore | 5e-10 with the WR-03 restore |
|---|---|---|---|
| CI golden welfare_gap | -0.018591711034105174 | -0.018590973661162025 | -0.018590973661162025 (moved by 7.4e-7 abs, rel 4.0e-5, inside the pin's rtol 1e-4 but a move) |
| CI golden ratios | 0.236, 0.290, 0.184, 0.118, 0.366 | 0.203, 0.368, 0.320, 0.366, 0.344 | same as without |
| docs page refused | 5/10 (4, 6, 7, 9, 10) | 7/10 (2, 3, 5, 6, 7, 9, 10; draw 1 escalated, sticky) | 4/10 (2, 3, 6, 7) |
| docs page welfare_gap | 0.03293196255276598 | 0.03412264499013418 | -0.0027531631646979804 |
| docs page all-feasible-draw gap | 0.016867421597680732 | 0.016868409343146595 | 0.016868263000901607 |
| compare (seed 42) welfare_gap | -0.0323948881649585 | -0.03239409440516283 | -0.03239409440516283 (0/10 refused either way) |

The targeted files still passed with the fix applied (74/74 on the three stochastic files), because the golden moved inside its tolerance. It was reverted anyway, since the hard constraint says the CI golden must not move. The docs-page row backs the reviewer's bias concern: the certified-only gap changes sign across solver settings (-0.0028 to 0.0341), while the all-draw gap stays at 0.01687.
**Doc note added (commit 25a3011):** in `docs/src/status_policy.md` §3 and the `run_stochastic` docstring. It says:
- the held-out solves use tol_gap 1e-8 and the in-sample model uses 5e-10;
- the excluded count, and therefore the certified-only `realized_welfare`/`welfare_gap`, depend on the solver and Julia version (5/10 on 1.12.5, 2/10 on 1.12.7 for the docs scenario);
- why 5e-10 was not adopted;
- to compare against the all-feasible-draw mean, and to read the masks and counts rather than `status` alone (this also covers IN-05).

No count in the docs prose or in 38-MEASUREMENTS.md changed: the docs page computes its counts live, and the shipped optimizer is unchanged.
**Original issue:** `run_stochastic` builds the OOS harness with the default optimizer (tol_gap 1e-8). The in-sample model is solved at 5e-10, so the exclusion count depends on the solver build.

## Optional Info items fixed

- **IN-01** (876ea28): rewrote the stale "one-line `solve_with_retry!` delegation" comment in `src/models/stochastic_welfare.jl`.
- **IN-02** (4ee0f58): in `src/models/exactness.jl`, replaced "the plan's must_haves prose" with neutral wording, and replaced the single-call-site guard sentence with a description of the kernel's three consumers.
- **IN-04** (69eaefe): `docs/literate/stochastic_pv_demand.jl` now uses `isempty(oos_ratios) ? NaN : maximum(oos_ratios)`. The review suggested `init = NaN`, but that would always return NaN, because `max` propagates NaN. The literate page ran end to end on 1.12.5 (exit 0).

## Verification summary (Julia 1.12.5, final HEAD 69eaefe)

| file set | before | after |
|---|---|---|
| test_run_stochastic + test_stochastic_oos_harness + test_status_policy | 15 items / 74 Pass | 16 items / 95 Pass |
| the above + test_exactness | (exactness 28) | 22 items / 123 Pass |
| test_strategies (CI golden run_and_store round-trip, includes `:slow`) | 28 items / 435 Pass (re-measured on d738238) | 28 items / 435 Pass |

The 38-MEASUREMENTS.md ledger lists 443 for test_strategies. A fresh run on the pre-fix HEAD d738238 also gives 435, so these fixes did not cause that difference.

Before each commit, `check_planning_ids.py` passed. After each src/test/docs commit, `format210.jl` (JuliaFormatter 2.10.2) and `check_content_loss.py HEAD` passed. The only formatter change was one line wrap in the WR-04 test, folded into its commit.

The canary and the full suite were not run. No change touches the ADMM/canary path: WR-01 changes behaviour only for NaN ratios, and WR-03 is bit-identical as measured. The docs build was not run; the literate page and plain Markdown were checked as described above.

---

_Fixed: 2026-10-08_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
