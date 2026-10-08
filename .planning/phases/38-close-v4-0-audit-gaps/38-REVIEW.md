---
phase: 38-close-v4-0-audit-gaps
reviewed: 2026-10-08T02:55:50Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - docs/literate/ac_oracle.jl
  - docs/literate/mpc_rolling_horizon.jl
  - docs/literate/stochastic_pv_demand.jl
  - docs/src/status_policy.md
  - docs/writeups/README.md
  - .github/workflows/CI.yml
  - scripts/compare_default_stochastic.jl
  - src/core/errors.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run_stochastic.jl
  - src/experiments/Scenario.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - src/models/exactness.jl
  - src/models/stochastic_welfare.jl
  - src/TSODSO.jl
  - test/fixtures_mpc.jl
  - test/test_ac_oracle.jl
  - test/test_admm_timeout.jl
  - test/test_exactness.jl
  - test/test_mpc_loop.jl
  - test/test_run_stochastic.jl
  - test/test_status_policy.jl
  - test/test_stochastic_oos_harness.jl
  - test/test_strategies.jl
findings:
  critical: 0
  warning: 5
  info: 7
  total: 12
status: issues_found
---

# Phase 38: Code Review Report

**Reviewed:** 2026-10-08T02:55:50Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Scope: the Phase 38 diff (`28f5c71^..HEAD`) across the listed files. `FRAMEWORK_GUIDE.html`
and `compare_default_stochastic.typ` were excluded as instructed.

The `_socp_cone_check` extraction is a faithful refactor. It uses the same `_cone_row`
arithmetic, the same defaults and the same `maxratio <= 1` verdict in `assert_socp_exact!`, and
test_exactness pins its parity with `hybrid_ratios`. The MPC first tier now calls the shared
kernel. That call is correct: `ctx.T = H` is set in `build_mpc_window`, and `o.ctx.feeder ===
feeder` holds for the only production caller. The Scenario ADMM/`allow_export` guard sits in
the inner constructor, so it covers `with_strategy`, `run_sweep` and the legacy `:admm` path.
The stored reactive mode as a `Symbol`, the `oos_*` store/sweep fields and the CI step are
correct. I ran the CI Python checks locally: `check_setup_names.py --selftest`, then the real
check (0 unresolved), and `check_planning_ids.py`. All three pass.

No blockers found. The main concerns are in the new out-of-sample (OOS) exactness gate:

- It fails open on NaN. Its comparison is the inverse of the one `assert_socp_exact!` uses.
- Its verdict depends on things that should not matter: the solver build, the solver
  tolerance (the harness is solved looser than the in-sample model) and draw order (sticky
  retry escalation).
- `realized_welfare`/`welfare_gap` are now averaged over a draw subset that is build-dependent
  and possibly biased.

Out-of-scope observation, not counted: the modified line of `compare_default_stochastic.typ`
still carries planning IDs (D-02, PF-04, WR-05, D-06, D-09). `check_planning_ids.py` passes,
so `.typ` is presumably outside its scan set.

## Warnings

### WR-01: OOS exactness gate fails open on a NaN cone ratio (inverse comparison of `assert_socp_exact!`)

**File:** `src/models/stochastic_welfare.jl:772`
**Issue:** `assert_socp_exact!` refuses with `maxratio <= 1 || throw(...)`, and the MPC first
tier certifies with `cone_maxratio <= 1`. Both are NaN-safe: a NaN ratio is refused or
escalated. The new held-out gate uses `c.maxratio > 1 && throw(...)`. `NaN > 1` is `false`, so
a NaN ratio is silently certified. Julia's `max(x, NaN)` propagates NaN, so any NaN
`value(l|v|P|Q)` turns `maxratio` into NaN. That draw then counts as usable and is averaged
into `realized_welfare`. `socp_maxratio_h[h]` also shows `NaN`, which the docstring says means
"infeasible draw or no branch current", so the bad draw is indistinguishable in the report.
`assert_solved!` makes a NaN primal unlikely today. Still, the docstring calls this "the same
shared cone check as `assert_socp_exact!`", and it is not the same where it matters.
**Fix:**
```julia
c.maxratio <= 1 || throw(
    CertificateError(
        "held-out re-solve: SOCP relaxation INEXACT: worst " *
        "gap/(atol_b+rtol·|cone|)=$(c.maxratio) > 1 ..."; kind = :socp_exact,
    ),
)
```
Add a unit test with a NaN-valued stub, or document the `<=` invariant on `_socp_cone_check`
so every consumer uses it.

### WR-02: The held-out harness is solved looser than the in-sample model, so the OOS exclusion count depends on the solver build

**File:** `src/experiments/run_stochastic.jl:274-281` (with `src/models/stochastic_welfare.jl:184-185`)
**Issue:** `build_stochastic_welfare` raises the Clarabel `tol_gap_abs/rel` to 5e-10. The
in-code reason is that the factory default of 1e-8 leaves cone residuals the gate refuses
(ratio 5.6 on the 2-bus fixture). `run_stochastic` builds the OOS harness with the default
`select_optimizer(problem_class(pf))`, which is 1e-8, and has no way to pass anything else.
The new tests document what follows:

- the same 2-bus pin-binding solve measures ratio ≈ 51 at the default and ≤ 0.5 at 5e-10
  (test_stochastic_oos_harness header note 3);
- the recovery solve in test_run_stochastic measures ≈ 7.3 at the default.

On the docs page the exclusion count is 5/10 on Julia 1.12.5 and 2/10 on 1.12.7. So the
published `realized_welfare`/`welfare_gap` average different draw subsets on different
builds. That undercuts the "reproducible results" constraint in CLAUDE.md. The excluded draws
are the ones whose pinned-dispatch solve is numerically hardest, which is plausibly
correlated with the draw's PV/load character. The surviving average can then be a biased
estimator of out-of-sample welfare, not just a noisier one. The `_stoch_solve_held_out!`
docstring says tightening does not fix IEEE-13. That may be true, but nothing threads the
in-sample tolerance through, so it is not even attempted in production.
**Fix:**
- Build the harness with the same optimizer as the in-sample extensive form, so both stages
  are certified at the same solver precision:
  ```julia
  oos_opt = problem_class(pf) isa SOCP ?
      select_optimizer(problem_class(pf); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10) :
      select_optimizer(problem_class(pf))
  h_oos = build_stochastic_oos_harness(feeder, pf, held_out_aggs[1]; T = s.T, λ₀ = λ₀,
                                       allow_export = s.allow_export, optimizer = oos_opt)
  ```
  Alternatively, expose `optimizer` on `Stochastic`.
- Also report the unfiltered all-draw mean next to `realized_welfare`, so the effect of the
  exclusion is visible.

### WR-03: Held-out gate verdicts depend on draw order through sticky `solve_with_retry!` escalation

**File:** `src/models/stochastic_welfare.jl:767` and `src/experiments/run_stochastic.jl:309-329`
**Issue:** `solve_with_retry!` documents its escalated Clarabel attributes as STICKY. Once
any held-out draw hits a retryable status, every later draw on the never-rebuilt harness is
solved with `static_regularization_constant` up to 1e-5. Before this phase that changed only
the precision of the objective. Now it feeds a hard exactness verdict at an absolute floor
of `τ_solver = 2e-7`. The documented refusals sit at 2–4e-7, right at that floor. So whether
draw `h` is refused, and therefore whether it counts toward `welfare_gap`, can depend on
whether some earlier draw `h' < h` triggered an escalation. The OOS evaluation should not
depend on the order of the draws.
**Fix:**
- Before each held-out re-solve, restore the harness's baseline optimizer attributes.
  Snapshot them after the build, then re-apply the snapshot at the top of the loop.
- Or record `attempts_out` per draw in the `oos` NamedTuple so an escalated (lower-precision)
  solve is visible beside its `inexact_h` verdict.

### WR-04: The inexact-refusal test depends on solver imprecision, not a constructed slack

**File:** `test/test_stochastic_oos_harness.jl:164-203`
**Issue:** The only test of the new refusal path relies on Clarabel at `tol_gap = 1e-8`
happening to leave a ratio of about 51 on this fixture. If Clarabel's defaults or accuracy
improve, `@test_throws CertificateError` fails. The test would then report a regression in
code that is actually correct. The MPC regression item in the same phase avoids this: it
forces a deterministic slack (`@constraint(o.model, l[2,1] >= l0 + 5e-7)`). Also, nothing
tests end to end what `_run_stochastic` does after an inexact draw: the `usable` mask
average, `n_usable == 0 → NaN`, and `status = :oos_inexact_skipped` coming through
`run_stochastic`. Only the helper and `_stochastic_status` are unit-tested.
**Fix:** Build the harness with the tightened optimizer, then force the slack directly, for
example `@constraint(h.model, h.ctx.pf_vars.l[b, t] >= value(h.ctx.pf_vars.l[b, t]) + δ)` with
δ sized well above the hybrid floor, and re-solve. Add one item that drives
`_run_stochastic`'s aggregation with a stubbed `_stoch_solve_held_out!` result, or with a
fixture that has a forced-slack draw, and checks `realized_welfare`, `welfare_gap` and
`status`.

### WR-05: Breaking behavior changes are missing from the "Breaking changes" section

**File:** `docs/src/status_policy.md:112-141`
**Issue:** Section 7 lists only the stored-provenance change from this phase. Three changes
that can break user code are not listed:
1. `solve_stochastic_oos_step!` is declared `public` (`src/TSODSO.jl:344`). It used to return
   the model on every successful solve. It now throws `CertificateError(kind = :socp_exact)`
   on an inexact one, so any direct caller (a custom OOS loop or script) now aborts.
2. `Scenario(strategy = ADMM(), allow_export = false)`, and any `run_sweep` grid crossing
   `:admm` with `allow_export = [true, false]`, now throws at construction, before any
   scenario in the sweep runs. Before, it failed only at that scenario's solve.
3. The MPC first-tier floor is tighter: a flat `1e-6` became the hybrid `max(2e-7, 1e-9·ref_b)`
   floor. Steps that used to certify can now escalate, so `cert_status`, the run `status` and
   the published `dadp_trace` change. The phase context measured one such flip on Julia
   1.12.7.
**Fix:** Add one bullet for each of these to section 7.

## Info

### IN-01: Stale comment says `solve_stochastic_oos_step!` is a one-line delegation

**File:** `src/models/stochastic_welfare.jl:491-494`
**Issue:** The comment still says the function is "a one-line `solve_with_retry!` delegation".
It now also runs the exactness gate, writes `ctx.meta` and can throw. The docstring was
updated, but this comment was not.
**Fix:** Reword the comment to match the docstring, or delete it.

### IN-02: The moved head-branch rationale refers to a single call site and to "the plan's must_haves"

**File:** `src/models/exactness.jl:170-205`
**Issue:** The block moved verbatim into `_socp_cone_check` still says the numeric check
"only runs on a ctx whose formulation carries the branch-current variable (the
`has_branch_current(ctx.pf)` guard at this function's call site)". The kernel now has three
callers, and the MPC first tier calls it without a `has_branch_current` guard. The block also
cites "the plan's must_haves prose", a planning-artifact reference in `src/`. It is not an ID,
so the CI planning-ID check does not catch it.
**Fix:** Rewrite the paragraph to describe the three consumers, and drop the reference to the
plan.

### IN-03: Head-branch lookup and zero-match error are duplicated in `assert_socp_exact!`

**File:** `src/models/exactness.jl:309-320`
**Issue:** `assert_socp_exact!` runs `_socp_head_branch` and its zero-match `ArgumentError`,
then `_socp_cone_check` runs both again with a different message. The two messages can drift
apart. The `_socp_cone_check` docstring also says it throws `ArgumentError` "only" on the
zero-match case. It can also throw from `_require_pf_vars`, `_require_feeder` and `_require_T`.
**Fix:** Add a `caller::String` keyword to the kernel and build the message from it, or make
the docstring say "e.g.".

### IN-04: Literate page `maximum(filter(!isnan, ...))` throws when no draw has a ratio

**File:** `docs/literate/stochastic_pv_demand.jl:260`
**Issue:** If every held-out draw is infeasible (all `socp_maxratio_h` are NaN), `maximum` of
an empty collection throws, and the docs build fails for that reason rather than reporting
the result.
**Fix:** `maximum(filter(!isnan, r.oos.socp_maxratio_h); init = NaN)` (Julia ≥ 1.6 supports `init`).

### IN-05: The run status hides infeasible draws when an inexact one is present

**File:** `src/experiments/run_stochastic.jl:373-377`
**Issue:** `:oos_inexact_skipped` takes precedence. A caller that checks
`status == :oos_infeasible_skipped` to detect committed-schedule infeasibility misses it
whenever at least one draw is also inexact. This is documented, and the store keeps both
counts. Still, the status alone is lossy.
**Fix:** Keep the precedence, but have the status-policy page tell callers to check the masks
or counts rather than test `status` alone.

### IN-06: Inconsistent summary key names and missing per-draw ratio in the script artifacts

**File:** `scripts/compare_default_stochastic.jl:400-401, 458-463`
**Issue:** `summary.csv` mixes `oos_n_infeasible` with the new `oos_inexact_draws`. The store
uses `oos_infeasible_draws` and `oos_inexact_draws`. `oos_draws.csv` records the `inexact`
mask but not `socp_maxratio_h`, so an excluded draw cannot be read off the artifact alongside
how far it was over the floor.
**Fix:** Name the key `oos_inexact_draws` next to an `oos_infeasible_draws` key (keep the old
key for continuity if needed), and add a `socp_maxratio = oos.socp_maxratio_h` column.

### IN-07: `_mpc_certify_and_price` feeder check uses identity, not equality

**File:** `src/experiments/mpc_loop.jl:867-869`
**Issue:** `o.ctx.feeder === feeder` rejects an equal feeder that was built separately, for
example `mpc_high_pv_feeder()` called twice in a test. That is stricter than the intent
("must be the window's own feeder") needs. It is correct for the one production caller. The
seam could simply read `o.ctx.feeder` itself.
**Fix:** Derive `feeder = o.ctx.feeder` inside the function and drop the parameter, or keep the
parameter and document that it must be the same object.

---

_Reviewed: 2026-10-08T02:55:50Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
