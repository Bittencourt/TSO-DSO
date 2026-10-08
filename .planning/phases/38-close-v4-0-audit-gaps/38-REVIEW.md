---
phase: 38-close-v4-0-audit-gaps
reviewed: 2026-10-08T03:35:59Z
depth: standard
iteration: 2
files_reviewed: 8
files_reviewed_list:
  - docs/literate/stochastic_pv_demand.jl
  - docs/src/status_policy.md
  - src/admm/DsoOpt.jl
  - src/experiments/run_stochastic.jl
  - src/models/exactness.jl
  - src/models/stochastic_welfare.jl
  - test/test_run_stochastic.jl
  - test/test_stochastic_oos_harness.jl
findings:
  critical: 0
  warning: 0
  info: 5
  total: 5
status: issues_found
---

# Phase 38: Code Review Report (iteration 2)

**Reviewed:** 2026-10-08T03:35:59Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found (Info only)

## Summary

Scope: the fix range `32af868^..HEAD` (WR-01, WR-03, WR-04, WR-05, the WR-02 documentation
note, IN-01, IN-02, IN-04), read against the surrounding code. This was a static review. The
Julia suite was not run. `python3 .github/scripts/check_planning_ids.py` passes (250 files
scanned, no planning identifiers). The only planning reference in the diff is the removed
"plan's must_haves" line.

None of the fixes introduces a regression. The four checks requested:

- **Each fix resolves its finding.**
  - WR-01: the comparison is now `c.maxratio <= 1 || throw(...)`. The docstring's NaN claim is
    correct: `_socp_cone_check` accumulates with `max`, which propagates NaN, and a NaN `ref_b`
    also turns `atol_b` into NaN.
  - WR-04: the deterministic refusal works.
  - WR-05: the bullets are present, and their claims check out against the code. The
    Scenario guard throws `ArgumentError`. `run_sweep` builds every `Scenario` before the first
    `run_and_store`. The MPC first tier certifies with `_socp_cone_check(o.ctx).maxratio <= 1`.
  - IN-01, IN-02 and IN-04 are resolved. Avoiding `init = NaN` in IN-04 was right.
- **The test hook cannot affect production calls.** `solve_held_out!` is a keyword on the
  unexported, non-`public` `_run_stochastic`, and its default is `_stoch_solve_held_out!`. The
  only production callers (`run_stochastic`, at `run_stochastic.jl:421` and `:434`) pass
  positional arguments only. The production loop body does not change: the restore and the
  call happen in the same place for every caller.
- **The WR-03 snapshot/restore covers every setting the escalation mutates.**
  `solve_with_retry!` touches exactly the four attributes in `LADDER_ATTR_NAMES`
  (`retry.jl:142-157`), and `_snapshot_ladder_attrs` iterates that same constant. The snapshot
  is taken right after `build_stochastic_oos_harness`, before any solve. Only
  `set_parameter_value` calls sit between the snapshot and the loop. The restore runs before
  each `solve_held_out!`, so every draw's retry ladder starts at the as-built baseline.
  Backends that do not expose an attribute degrade to a no-op, as in the existing ADMM use.
- **The new end-to-end test is deterministic.** For a given build it is. The refusal comes
  from a forced `l ≥ value + 5e-6` slack, and nothing in the objective rewards closing that
  slack, so the cone gap is about δ·v and the ratio about 25, which is far from 1. The
  choice of the least-loaded branch is safe even with ties, because any near-zero-flow branch
  gives the same ratio. Bit-equality for the other draws holds: the cut is deleted, the
  ladder is restored, and Clarabel re-solves from scratch. `realized_welfare ==
  sum(welfare_h[usable]) / length(usable)` holds exactly, because the production mask
  `usable` selects the same elements in the same order. The one remaining dependence on
  default solver precision is described in IN-02.

The WR-02 documentation note (`status_policy.md` section 3 and the `run_stochastic`
docstring) is accurate:
- The held-out solves use the 1e-8 default. The in-sample model uses 5e-10 for SOCP
  (`stochastic_welfare.jl:182-186`).
- The docs scenario really is `T = 9, S = 5, H_oos = 10`.
- The 5/10 vs 4/10 subsets, the 0.01687 all-feasible-draw gap and the -0.0028..0.0341 range
  match the measurements in the fix report.
- The all-feasible-draw formula is correct.

The only nit: "in-sample ... is solved at `5e-10`" holds only for an SOCP power flow. It is
not counted, because the held-out exactness gate exists only there anyway.

## Prior findings disposition

| ID | Disposition |
|----|-------------|
| WR-01 | **Resolved.** The gate uses `<= 1 ||` and the kernel docstring states the invariant. No NaN unit test; the reason is documented and acceptable. Wording nit tracked as IN-04 below. |
| WR-02 | **Skipped by design** (moving the CI golden is forbidden). The documentation note was checked and is accurate (see Summary). Not re-raised. |
| WR-03 | **Resolved.** The snapshot covers all four ladder attributes and is restored before every draw. No regression test (IN-03 below). |
| WR-04 | **Resolved.** The harness item forces a slack at the tightened optimizer. The new end-to-end item covers the usable-mask average, the precedence rule and the all-refused NaN case. One residual coupling remains (IN-02 below). |
| WR-05 | **Resolved.** Three bullets added and their claims verified. The section's preamble now contradicts one of them (IN-01 below). |
| IN-01 | Resolved. |
| IN-02 | Resolved. The new consumer sentence is slightly imprecise (IN-05 below). |
| IN-03 | Open, not touched. The `_socp_cone_check` docstring still says it throws `ArgumentError` "only" in one case. Carried over, not re-counted. |
| IN-04 | Resolved (`isempty(oos_ratios) ? NaN : maximum(oos_ratios)`). |
| IN-05 | Mitigated by the WR-02 note ("read the masks and counts, not `status` alone"). Closed. |
| IN-06 | Open, not touched (`scripts/compare_default_stochastic.jl` was out of this range). Carried over, not re-counted. |
| IN-07 | Open, not touched (`src/experiments/mpc_loop.jl` was out of this range). Carried over, not re-counted. |

## Info

### IN-01: The "Breaking changes" preamble now contradicts the new MPC bullet

**File:** `docs/src/status_policy.md:131-132` (preamble) vs the MPC bullet at the end of section 7
**Issue:** The section opens with "Everything below fails loudly instead of silently changing
behavior." The new "Tighter MPC first-tier certificate" bullet describes a change that does
not fail. It re-prices a step through the escalation ladder, which emits only a `@warn`
(`mpc_loop.jl:995`), and it changes `cert_status_trace`, `status` and `dadp_trace` in the
returned result. A reader who trusts the preamble will expect an exception and will miss
changed prices in a run that completes.
**Fix:** Qualify the preamble, e.g. "Every item below either fails loudly or, where noted, changes a
reported result with a warning", and say explicitly in the MPC bullet that it does not throw.

### IN-02: The end-to-end test's wrapper still needs the unperturbed draw to pass the gate at default precision

**File:** `test/test_run_stochastic.jl:164-175`
**Issue:** `forced_slack` pre-solves each targeted draw with
`TSODSO.solve_stochastic_oos_step!(h_oos)`, which runs the exactness gate and throws an
uncaught `CertificateError` if that draw is inexact at the default 1e-8. `r3` targets all five
draws. So the item depends on every CI-golden draw certifying at default precision, which is
the build-dependence the WR-02 note documents. Today this adds no new fragility, because the
mask item (`test_run_stochastic.jl:130-133`) already asserts `all(<=(1), ...)` on the same
fixture, measured ≤ 0.366 on 1.12.5 and 0.350 on 1.12.7. Still, the pre-solve only needs
primal values to place the cut, not a certificate. Separately, if `_stoch_solve_held_out!`
rethrows, the cut is never deleted, and every later draw in that run sees it, which makes the
resulting failures harder to read.
**Fix:**
```julia
TSODSO.solve_with_retry!(h_oos.model; dual = false)   # primal only, no gate
...
con = @constraint(h_oos.model, l[b, 1] >= value(l[b, 1]) + δ)
try
    return TSODSO._stoch_solve_held_out!(h_oos, i)
finally
    delete(h_oos.model, con)
end
```

### IN-03: The WR-03 draw-order restore has no regression test

**File:** `src/experiments/run_stochastic.jl:305, 349`
**Issue:** The fix report shows that the restore matters: without it, 7/10 draws are refused,
and with it, 4/10. No test would fail if someone deleted line 349. The new seam makes a cheap
test possible.
**Fix:** In `test_run_stochastic.jl`, wrap the solver so that draw 1 sets
`static_regularization_constant` to `1e-5` on `h_oos.model` before delegating. In draw 2, record
`get_optimizer_attribute(h_oos.model, "static_regularization_constant")` and assert that it
equals the as-built value.

### IN-04: The refusal message prints "NaN > 1" for the NaN case WR-01 now catches

**File:** `src/models/stochastic_welfare.jl:774-781` (and `_stoch_solve_held_out!`'s `@warn`, `run_stochastic.jl:83-85`)
**Issue:** The message is a fixed template, `"...=$(c.maxratio) > 1 ..."`. For the NaN path
that WR-01 just opened, it reads "ratio NaN > 1", which is false. The `@warn` in
`_stoch_solve_held_out!` repeats "(cone ratio $ratio > 1)". A user debugging a NaN primal gets
a misleading diagnostic.
**Fix:** Branch the message, e.g. `isnan(c.maxratio) ? "cone ratio is NaN (non-finite primal values)" : "...=$(c.maxratio) > 1 ..."`.

### IN-05: The rewritten consumer sentence overstates the `has_branch_current` guard

**File:** `src/models/exactness.jl:186-190`
**Issue:** The comment says `assert_socp_exact!`'s "solve-path callers check
`has_branch_current` first". Two callers do not:
- The caller at `nash.jl:1580` guards with `is_socp` (line 1578).
- The MPC local-AC tier (`mpc_loop.jl:1407`) calls it unguarded. It reads `l` itself just
  before, so it is safe.

Behaviour is unaffected. The comment is just less precise than it reads.
**Fix:** Reword it to "whose callers only reach it on a formulation that carries `l`
(`has_branch_current`, `is_socp`, or a model that reads `l` itself)".

---

_Reviewed: 2026-10-08T03:35:59Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2_
