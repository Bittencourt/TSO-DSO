---
phase: 27-integer-planning-pricing-certificate-correctness
reviewed: 2026-09-29T14:05:00Z
depth: standard
iteration: 2
files_reviewed: 7
files_reviewed_list:
  - src/planning/benders.jl
  - src/experiments/mpc_loop.jl
  - src/pricing/dlmp.jl
  - src/models/exactness.jl
  - test/test_planning_certification_integer.jl
  - test/test_mpc_loop.jl
  - test/test_pricing_dlmp.jl
findings:
  critical: 0
  warning: 0
  info: 1
  total: 2
status: clean
---

# Phase 27: Code Review Report (re-review, iteration 2)

**Reviewed:** 2026-09-29T14:05:00Z
**Depth:** standard
**Files Reviewed:** 7 (diff scope: fix commits `ba01c6e`, `9ad07dd`, `570089d`, `2a3670b` vs base `4eda25e`)
**Status:** issues_found (1 new WARNING; both prior BLOCKERs confirmed genuinely resolved)

## Summary

Re-reviewed the four fix commits from iteration 1 (`ba01c6e` CR-01, `9ad07dd` CR-02, `570089d`
WR-01, `2a3670b` WR-02/WR-03) against the diff base `4eda25e`, with the specific adversarial
brief of confirming the CR-01/CR-02 regression tests are genuinely behavioral (not vacuous
`isdefined`/`UndefVarError` tripwires) and sanity-checking CR-01's termination argument.

**CR-01 (`_corner_recourse_joint` double-infeasible stall guard) — CONFIRMED GENUINELY FIXED,
test is behavioral.** Read the diff (`git show ba01c6e`) and the resulting source
(`src/planning/benders.jl:401-465`): the single-shot bisection was replaced by a genuinely
iterative halving loop bounded by `JOINT_RECOURSE_BISECT_MAX_DEPTH = 64`, shrinking
`[z_best, z_next]` toward the feasible anchor on each failed midpoint. The committed
`@testitem` (`test/test_planning_certification_integer.jl:666-748`) calls
`TSODSO.corner_recourse` — the real, exported/public production entry point — directly, not a
mocked or extracted helper, on a fixture whose oracle-infeasible-no-certificate band was
empirically measured to make the single-bisection midpoint land back inside the same band
(the exact double-infeasible scenario CR-01 fixes). I independently reproduced this fixture in
a standalone `julia --project=.` script (never TestItemRunner, per this repo's own established
trap) calling `TSODSO.corner_recourse` directly:

```
Q_control (y_inv=3.0, control)       = 4.250000006554955
Q_stress  (y_inv=10.0, iters=20)     = 4.250000006554955   (converged in 0.33s, well within iters=20)
grid_Q (15x15 dense-grid upper bound) = 4.250000006554955
Q_stress <= grid_Q + 1e-3             = true
```

This matches the fix commit's own claimed converged value exactly, confirms the loop makes
genuine progress and terminates well inside the `iters` budget (as opposed to the documented
pre-fix behavior of exhausting `iters` with zero progress), and confirms the returned value is
correct against an independent dense-grid reference. **Termination argument sanity-checked**:
the inner bisection loop only ever shrinks `z_hi` toward the fixed, always-feasible anchor
`z_lo = z_best` (never re-tests a stale `z_hi`), so after enough halvings `z_mid` becomes
bit-identical to `z_best`, whose `evaluate(...)` is guaranteed finite — guaranteeing
`progressed = true` within the 64-halving budget for any physically-scaled `z` (the `z ∈
[0, y_inv]` domain here never approaches the extreme dynamic range the comment's "any IEEE-754
double... extreme exponents" phrasing technically overclaims — see IN-01 below, informational
only). Every `UB` update inside the bisection comes from a genuine `evaluate()` call (a real
`solve_follower!`/`solve_planning_oracle!` solve), so the returned recourse value is always a
genuinely-achieved, feasible `Q` value, never a fabricated/interpolated one. CR-01 is resolved;
no residual defect found.

**CR-02 (MPC truth-settlement PV clip) — source fix CONFIRMED correct; regression test is
narrower than it should be (new WARNING, see WR-04 below).** Read the diff (`git show
9ad07dd`) and confirmed via `grep -n "pv_used" src/experiments/mpc_loop.jl` that the actual
accumulation site now reads `net_p += pv_used_true - p_ch_true + p_dch1`
(`mpc_loop.jl:579`) — genuinely replacing the pre-fix `net_p += pv_used1 - p_ch_true +
p_dch1` (raw, unclipped `pv_used`). Ran the actual production path end-to-end
(`run_mpc(Scenario(...; mpc_forecast_error=0.3, seed=1))`, the exact "forced-PV-shortfall"
fixture) directly via script and confirmed it completes without error and reproduces the
documented head-branch thermal-overload finding at `abs_hour=5` (`max_overload_ratio ≈
1.0418`), consistent with the FIX-10/plan-27-09 narrative. The source fix is genuine and
correctly wired.

However, per this task's specific brief: the committed `@testitem`
(`test/test_mpc_loop.jl:147-247`) is a **pure unit test of the extracted helper
`_mpc_pvbattery_true_clip` in isolation** — it constructs hand-derived numbers and calls the
helper directly; it never calls `run_mpc` or exercises the actual call site at
`mpc_loop.jl:579` where the original bug lived. I independently re-ran this exact test body as
a standalone script and confirmed all assertions pass against current source. This test would
NOT fail if a future edit reverted line 579 back to `pv_used1` (the exact historical bug)
while leaving `_mpc_pvbattery_true_clip` itself untouched and correct — the helper's own
correctness and its use-site wiring are two separate facts, and only the former is
regression-locked. See **WR-04** below.

**WR-01 (`DlmpDecomposition` `NamedTuple` conversion) — CONFIRMED resolved, test is
behavioral.** `Base.NamedTuple(::DlmpDecomposition)`/`Base.propertynames` are genuinely added
(`src/pricing/dlmp.jl:279-311`); the regression `@testitem`
(`test/test_pricing_dlmp.jl:551-597`) directly constructs a `DlmpDecomposition` (no network
solve needed — appropriately scoped to pin the conversion contract independent of any
fixture) and asserts the exact pre-FIX-07 field order/values via `keys`, `Tuple`, `collect
∘ values`, and `propertynames` — genuine `NamedTuple`-only operations that would `MethodError`
pre-fix. Confirmed correct by direct read; no residual defect.

**WR-02 (meshed-feeder head-branch `ref_b` scale choice) — CONFIRMED documentation-only, zero
behavior change.** `git show 2a3670b --stat` shows only `src/models/exactness.jl` with `+22
-0` (pure comment insertion, no code touched). The accepted-risk rationale (numeric gate is
data-driven on `ConvexBranchFlow`-only `ctx`s; the one known multi-root-branch feeder is
exercised exclusively via `MeshedFlow()`, which never reaches this gate) is a reasonable,
narrowly-scoped judgment call given the stated full-suite-verification cost of a `sum`/`max`
change touching 30+ call sites. This remains a real, if currently dormant, latent risk —
correctly left open/documented rather than silently declared closed.

**WR-03 (single-shot bisection)** is subsumed by CR-01's fix (the same iterative loop
generalizes past the specific double-infeasible case); no separate action was needed and none
was taken. Confirmed by reading the current code: the loop structure applies uniformly to
every qualifying stall, not just the one CR-01 names.

## Warnings

### WR-04: CR-02's regression test does not exercise `run_mpc`'s actual accumulation wiring — a revert of the fixed call site would not be caught

**File:** `test/test_mpc_loop.jl:147-247` (test); `src/experiments/mpc_loop.jl:579` (untested
call site)

**Issue:** The CR-02 fix correctly changes `src/experiments/mpc_loop.jl:579` from
`net_p += pv_used1 - p_ch_true + p_dch1` (bug: raw, unclipped `pv_used`) to `net_p +=
pv_used_true - p_ch_true + p_dch1` (fix: clipped `pv_used_true`) — confirmed correct by direct
read. But the committed regression `@testitem` only unit-tests the extracted pure helper
`_mpc_pvbattery_true_clip(p_ch, pv_used, Ppv_true)` with hand-picked numbers; it never calls
`run_mpc` (or even `_mpc_pvbattery_true_clip`'s actual call site inside the loop) at all. The
helper's correctness and its use at line 579 are two independently-editable facts — the test
locks in only the first. A future edit that silently reverted line 579 to read `pv_used1`
(e.g. during an unrelated refactor of the accumulation block) — reintroducing the EXACT CR-02
bug — would leave every currently-committed test green: `_mpc_pvbattery_true_clip`'s own unit
test would still pass (the helper itself is untouched), and the only other test exercising
`fe.pv_factor != 1` end-to-end (`test_mpc_loop.jl:52-93`, "forced-PV-shortfall") only asserts
`!isapprox(r.realized_welfare, r.forecast_settled_welfare; atol=1e-9)` — a "something changed"
check that passes identically whether `pv_used` is clipped or not (any nonzero perturbation
trips it).

I confirmed via a live `run_mpc` call (the same "forced-PV-shortfall" `Scenario`,
`mpc_forecast_error=0.3, seed=1`) that the current, fixed code runs end-to-end without error
and produces the documented thermal-overload finding at `abs_hour=5`, so there is no live
defect today — this is a test-adequacy gap, not a functional bug.

**Fix:** Add an end-to-end assertion driven through `run_mpc`'s public path under
`fe.pv_factor > 1` that bounds the realized/truth-settled quantities against the TRUE PV
availability — e.g., at a specific `abs_hour` where `draw_forecast_error(...).pv_factor > 1`
is known (the header comment of the existing "forced-PV-shortfall" test already cites the
per-hour `pv_factor` values measured on that fixture), assert that the AC-truth-settled net
PV contribution at that hour does not exceed `d.Ppv[abs_hour]` (the exact CR-02 invariant,
checked through the real call site rather than only through the isolated helper). This closes
the gap between "the helper is correct" and "the helper is actually used correctly."

## Info

### IN-01: `JOINT_RECOURSE_BISECT_MAX_DEPTH`'s comment overclaims "any extreme exponents"

**File:** `src/planning/benders.jl:101-109`

**Issue:** The comment justifying `JOINT_RECOURSE_BISECT_MAX_DEPTH = 64` states that "64
halvings exhausts any representable gap even for extreme exponents" for an IEEE-754 double.
This is not literally true in the fully general case (the full double exponent range spans
roughly 2074 bits from the smallest denormal to the largest normal, not 64) — but it is true
and sufficient in the actual context this constant is used in: `z_lo`/`z_hi` here are always
two points within the SAME bounded box `[0, y_inv]` (comparable magnitude, no extreme-exponent
spread), so 64 halvings is comfortably more than the ~52-60 needed to reach bit-identity in
practice. Verified empirically: the stress test above converges in a small number of halvings,
far short of 64.

**Fix:** Optional — narrow the comment's claim to "for two values of comparable magnitude
within a bounded physical domain" rather than "any... extreme exponents," to avoid an
over-general claim that isn't load-bearing for correctness here but could mislead a future
reader reusing this constant/idiom in a context with genuinely extreme-magnitude brackets.

---

_Reviewed: 2026-09-29T14:05:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (re-review, iteration 2)_

---

## Iteration 3 (orchestrator re-review)

WR-04 resolved by `7c3e401`: new `pvbattery_truth_trace` diagnostic wraps the real `net_p` accumulation line; committed testitem drives `run_mpc` public path (pv_factor > 1) and was demonstrated to FAIL with the pre-CR-02 `pv_used1` line and pass with the fix. No critical/warning remain.
