---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 08
subsystem: pricing-certificate
tags: [ipopt, ac-powerflow, mpc, jump, fix-10, gap-closure, user-decision]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    provides: "Plan 27-03's MPC truth-plant settlement scaffolding (clip/throw/measured-state trajectory); Plan 27-07's direct total-loss objective and the ESCALATED finding that the SOCP truth-resolve is genuinely inexact on 18/20 seeds"
  - phase: 26-network-device-model-correctness
    provides: "Plan 26-15's ACPowerFlow :smax_rev receiving-end limit and its documented Ipopt warm-start remedy for the l·v=P²+Q² degenerate all-zero KKT point"
provides:
  - "run_mpc's realized_welfare settled by a genuine AC power flow (ACPowerFlow/Ipopt) at the fixed realized/clipped dispatch — _mpc_truth_import_acpf, warm-started from the window's own P/Q/l/v, requiring LOCALLY_SOLVED (ALMOST_LOCALLY_SOLVED and worse treated as failure, throwing with hour+status)"
  - "run_mpc's internal _truth_settlement test seam (:ac default, :socp reaches the superseded _mpc_truth_import_socp_reference) enabling a same-trajectory AC-vs-SOCP cross-check"
  - "ESCALATED FINDING: the AC settlement's strict correctness (no relaxation slack) surfaces a GENUINE Ipopt LOCALLY_INFEASIBLE at the DEFAULT seed=1 on the forced-PV-shortfall and mpc_step-stride fixtures — confirmed a real thermal-limit violation under exact physics, not a numerics/warm-start artifact; seed=5 RETAINED (not reverted to seed=1) for those two items, deviating from this plan's own must_haves text"
  - "27-08-repro.jl: direct-script reproduction of every run_mpc-dependent FIX-10 item plus the documented seed=1 throw plus the seed=5 AC-vs-SOCP cross-check (measured rel_diff ~1.7e-10)"
affects: [28-thesis-reproduction-restatement, any future plan touching _mpc_truth_import_acpf or run_mpc's fixture seeds on the :ieee13/:default population]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AC-power-flow truth settlement: a fresh single-hour ACPowerFlow ModelContext with every device's realized injection FIXED, warm-started from the calling window's own SOCP-solved P/Q/l/v (mirrors 26-15's PV back-feed regression remedy), gated on is_solved_and_feasible(...; allow_local=true, allow_almost=false) — never assert_socp_exact! (no relaxation to certify)."
    - "Internal _truth_settlement test seam on run_mpc (mirrors _mpc_certify_and_price's own _solve_welfare/_ac_dual_fallback_price idiom): production default :ac, :socp reserved for a same-random-draw cross-check against the superseded reference implementation."
    - "When a stricter, non-relaxed re-solve GENUINELY throws where the old relaxed one silently succeeded, confirm it is real (re-solve with the suspected binding constraint removed; if THAT reaches LOCALLY_SOLVED, the limited problem's infeasibility is real, not numerical) before treating it as anything other than a correct finding."

key-files:
  created:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl
  modified:
    - src/experiments/mpc_loop.jl
    - test/test_mpc_loop.jl

key-decisions:
  - "Kept the superseded SOCP truth-resolve in source (renamed _mpc_truth_import_socp_reference) rather than deleting it, reachable ONLY via run_mpc's new _truth_settlement=:socp internal test seam — reuses run_mpc's own tested realized-injection accumulation for a true same-trajectory cross-check instead of hand-reconstructing injections in the repro script."
  - "Did NOT revert the forced-PV-shortfall and mpc_step-stride testitems' seed=5 to the default seed=1 the plan's must_haves asked for — MEASURED that seed=1 now throws a GENUINE Ipopt LOCALLY_INFEASIBLE under the strict AC settlement (confirmed real via a limits-removed re-solve reaching LOCALLY_SOLVED cleanly), not fixable without weakening the settlement's convergence bar (LOCKED policy). Retained seed=5 (measured to still clear the AC gate cleanly) and added a new @testitem documenting the seed=1 throw as a citable regression."
  - "Warm-start source is the CALLING WINDOW's own SOCP-solved P/Q/l/v at the applied hour (not a fresh flat-start or a hand-picked point) — closest available approximation to the true operating point, and the documented remedy (26-15) for Ipopt's l·v=P²+Q² degenerate zero-start KKT point."

patterns-established:
  - "AC-power-flow (not SOCP-relaxation) truth settlement for any future truth/certificate re-solve in this codebase that must be trustworthy against a real thermal/voltage limit, not merely feasible under a relaxation's slack."

requirements-completed: [FIX-10]

# Metrics
duration: ~90min
completed: 2026-09-29
---

# Phase 27 Plan 08: AC Power-Flow Truth Settlement for MPC (FIX-10, USER DECISION) Summary

**Replaced FIX-10's SOCP-relaxation truth-import re-solve with a genuine AC power flow (ACPowerFlow/Ipopt) at the fixed realized dispatch, and in doing so discovered — and did NOT paper over — a further genuine finding: the exact physics reveals the default seed=1 fixture is truly thermally infeasible on two of test_mpc_loop.jl's items, not merely SOCP-inexact.**

## Performance

- **Duration:** ~90 min
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 2 modified, 1 created

## Accomplishments

- `_mpc_truth_import_acpf` (`src/experiments/mpc_loop.jl`) is the new production truth-settlement
  function `run_mpc` calls by default: builds a fresh single-hour `ACPowerFlow` `ModelContext`
  with every `mpc_aggs` bus's realized/clipped net injection FIXED, warm-started from the
  calling window's own solved `P`/`Q`/`l`/`v` at that hour (26-15's documented remedy for
  Ipopt's `l·v=P²+Q²` degenerate all-zero-start KKT point), requires
  `is_solved_and_feasible(...; allow_local=true, allow_almost=false)` (so `LOCALLY_SOLVED`/
  `OPTIMAL` only — `ALMOST_LOCALLY_SOLVED` is TREATED AS A FAILURE), and throws a loud
  `ErrorException` naming the hour and the full solve status otherwise. `assert_socp_exact!`
  plays no role in this path — there is no relaxation to certify.
- The superseded SOCP re-solve survives as `_mpc_truth_import_socp_reference`, reachable ONLY
  via `run_mpc`'s new internal test seam `_truth_settlement::Symbol = :ac` (default) / `:socp`
  (mirrors `_mpc_certify_and_price`'s own `_solve_welfare`/`_ac_dual_fallback_price` idiom) — no
  production `Scenario`-driven caller ever passes `:socp`.
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl`: a
  direct `julia --project=.` script reproducing every run_mpc-dependent FIX-10 testitem body,
  PLUS the documented seed=1 genuine-infeasibility throw, PLUS the seed=5 AC-vs-SOCP
  cross-check (measured `rel_diff ≈ 1.7e-10` — solver-precision agreement when the SOCP
  re-solve is independently known exact). Exits 0.
- **ESCALATED FINDING** (full record below): the AC settlement's strict correctness surfaced
  that the DEFAULT `seed=1` on `test_mpc_loop.jl`'s forced-PV-shortfall and mpc_step-stride
  fixtures is genuinely thermally infeasible — the head branch's `smax=0.0686` rating is
  exceeded at BOTH ends under the true (unrelaxed) AC equality. This is confirmed real (not a
  warm-start/numerics artifact) and is NOT the same knife-edge 27-03/27-07 found; it is a MORE
  fundamental one the OLD SOCP relaxation's `l`-slack was silently absorbing. `seed=5` is
  RETAINED (not reverted to `seed=1`) for these two items, deviating from this plan's own
  must_haves text — a new `@testitem` documents the genuine `seed=1` throw as a citable
  regression (also satisfying Task 2's "settlement raises on a forced Ipopt failure"
  requirement with a real, not synthetic, fixture).

## Task Commits

1. **Task 1: AC power-flow truth settlement in run_mpc** - `2152d4e` (feat)
2. **Task 2: Document the AC settlement's genuine seed=1 infeasibility finding** - `cd61be5` (test)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `src/experiments/mpc_loop.jl` — `run_mpc` gains the `_truth_settlement::Symbol = :ac` internal
  test seam; the old `_mpc_truth_import_resolve` is renamed `_mpc_truth_import_socp_reference`
  (docstring updated to mark it SUPERSEDED, reachable only via the test seam); the new
  `_mpc_truth_import_acpf` is the production settlement path; `run_mpc`'s own docstring
  (`realized_welfare` bullet + a new "Post-research amendment history" paragraph) documents
  both the AC settlement and the seed=1 finding.
- `test/test_mpc_loop.jl` — forced-PV-shortfall and mpc_step-stride items' comments updated to
  document the NEW (plan 27-08) root cause for retaining `seed=5`; a new `@testitem` asserts
  the settlement throws (naming `abs_hour=5`, `LOCALLY_INFEASIBLE`) on the genuine seed=1
  infeasibility.
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl` (NEW) —
  direct-script reproduction of all FIX-10 items, the seed=1 throw, and the seed=5 cross-check.

## Decisions Made

- **Kept the SOCP reference function in source, gated behind an internal test seam**, rather
  than deleting it or hand-reconstructing its logic inside the repro script — reuses `run_mpc`'s
  own tested realized-injection accumulation loop for an apples-to-apples, same-random-draw
  cross-check (both settlements see IDENTICAL per-hour fixed injections), which a
  from-scratch repro-script reconstruction could not guarantee.
- **Warm-start source: the calling window's own last-solved SOCP point** (`o.ctx.meta[:pf_vars]`
  at the window-local position), not a hand-picked or flat start — the closest available
  approximation to the true AC operating point, and the SAME remedy 26-15 already established
  and validated for `ACPowerFlow`'s degenerate-start pathology.
- **Root `v` excluded from the warm-start loop** — it is `fix()`ed to `1.0` in `ACPowerFlow`'s
  own `contribute!`, so setting a start value there is a no-op at best; skipped for clarity.
- **Did not weaken `is_solved_and_feasible`'s `allow_almost` bar** anywhere in
  `_mpc_truth_import_acpf` — per the plan's own explicit instruction and this project's LOCKED
  "never raise a tolerance/relax a gate to hide a genuine finding" policy, confirmed BEFORE
  accepting it as final by an independent limits-removed re-solve (see Findings below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking, escalated per the LOCKED "never weaken the convergence bar to hide it" policy] The DEFAULT seed=1 is genuinely thermally infeasible under the strict AC settlement on two testitems; `seed=5` is retained instead of reverted**
- **Found during:** Task 1 verification (writing `27-08-repro.jl`'s seed=1 reproduction,
  per the plan's own instruction to "Confirm it fails at seed=1 before the change" — here,
  confirming the NEW code's behavior at seed=1 surfaced a different, deeper failure than the
  one the plan anticipated fixing).
- **Issue:** `test_mpc_loop.jl`'s forced-PV-shortfall item (`T=9, mpc_H=3,
  mpc_forecast_error=0.3`) at the DEFAULT `seed=1` throws
  `run_mpc: AC power-flow truth settlement FAILED to reach LOCALLY_SOLVED at abs_hour=5 —
  termination_status=LOCALLY_INFEASIBLE`. The mpc_step-stride item's `seed=1, mpc_step=2`
  throws identically at `abs_hour=4`. Both were EXPECTED (per this plan's own must_haves) to
  clear cleanly once the SOCP knife-edge was removed.
- **Root-cause investigation:** re-solved the IDENTICAL fixed-injection `ACPowerFlow` model
  with the `:smax`/`:smax_rev` thermal-limit constraints DELETED — this reaches
  `LOCALLY_SOLVED`/`FEASIBLE_POINT` cleanly, with the head branch's forward apparent-power
  magnitude ≈0.0701 and receiving-end magnitude ≈0.0715, BOTH exceeding the branch's own
  `smax=0.0686` rating. This rules out a numerics/warm-start artifact (a genuine convergence
  failure would also fail without the limits) and confirms the realized/clipped dispatch at
  this seed is TRULY not servable within the feeder's thermal rating once the exact (unrelaxed)
  `l·v=P²+Q²` equality replaces the old SOCP relaxation's `l`-slack. This matches, and sharpens,
  27-07-SUMMARY.md's own prior measurement that this exact fixture's head branch was already
  loaded to "≈98% of its thermal limit" under the OLD (relaxed) settlement — the AC settlement
  correctly reveals that operating point tips OVER 100% once physics is enforced exactly.
- **Fix:** Per the parallel_execution instruction ("do not weaken the status check — report it
  as an ESCALATION"), the settlement's convergence bar was NOT weakened. Instead, `seed=5`
  (the pre-existing substitute from plans 27-03/27-07, MEASURED via a fresh seed sweep 1-12 to
  be one of only 3 seeds — {5, 7, 11} — that clear the AC settlement's strict gate at every
  applied hour on the forced-PV-shortfall fixture, and one of 8 — {2,4,5,7,8,9,11,20} — on the
  mpc_step-stride fixture) is RETAINED (not reverted to `seed=1`) for both items. Comments in
  both testitems and in `run_mpc`'s own docstring were rewritten to document the NEW root
  cause. A new `@testitem` ("AC truth settlement THROWS on a genuine Ipopt infeasibility...")
  asserts the seed=1 throw directly, turning the finding into a citable regression instead of
  an undocumented reason two tests still use a non-default seed.
- **Files modified:** `src/experiments/mpc_loop.jl` (docstring), `test/test_mpc_loop.jl`
  (comments + new testitem), `.planning/.../27-08-repro.jl` (documents both behaviors).
- **Verification:** `27-08-repro.jl` exits 0 — it explicitly reproduces BOTH the seed=1 throw
  (as an expected, asserted `ErrorException`) and each item's own intended behavior at the
  retained seed=5.
- **Committed in:** `2152d4e` (docstring), `cd61be5` (test file).

---

**Total deviations:** 1 (Rule 3, blocking, escalated per the LOCKED policy — NOT a relaxation of
any tolerance or gate; the settlement's correctness bar is untouched and, if anything, stricter
than before).
**Impact on plan:** Task 1's own code (the AC settlement, the warm-start, the throw-on-failure
contract) is implemented exactly per PLAN.md's instructions with no shortcuts. Task 2's LITERAL
acceptance criterion `grep -n "seed *= *5" test/test_mpc_loop.jl` returns nothing is NOT met —
`seed=5` remains in 2 of 3 `run_mpc`-driving testitems, each now carrying a full, measured
justification citing THIS plan (27-08) rather than the superseded 27-03/27-07 one. This is a
genuine, measured physical finding, not a shortcut: forcing `seed=1` to "pass" would require
either weakening `_mpc_truth_import_acpf`'s convergence bar (explicitly forbidden) or changing
the feeder/fixture's thermal rating (an architectural change outside this plan's scope, Rule 4
territory — not taken without a specific request).

## Findings (for the orchestrator / future MPC work)

### Finding 1 — AC settlement correctly reveals a real thermal violation the SOCP relaxation was silently absorbing

At `test_mpc_loop.jl`'s forced-PV-shortfall and mpc_step-stride fixtures' DEFAULT `seed=1`, the
realized/clipped dispatch genuinely violates the IEEE-13-derived head branch's `smax=0.0686`
apparent-power rating once served by the exact (unrelaxed) AC equations — confirmed via a
limits-removed re-solve reaching `LOCALLY_SOLVED` with both the forward (≈0.0701) and
receiving-end (≈0.0715) magnitudes over the limit. 27-07-SUMMARY.md had ALREADY measured this
SAME operating point loaded to "≈98% of its thermal limit" under the OLD SOCP relaxation
(inexact by a factor of ~1400-1700x on the cone residual, per 27-07's own finding) — the AC
settlement does not introduce a new problem; it correctly stops accepting a dispatch the old,
relaxed settlement was quietly tolerating past its true physical limit. A seed sweep (1-12 for
the shortfall fixture, 1-20 reused from 27-07 for the stride fixture) confirms this is a
SEED-SPECIFIC forecast-error draw interacting with an ALREADY-TIGHT fixture, not a general
failure of the AC settlement or this feeder: most other seeds clear the AC gate cleanly (indeed,
MORE seeds clear the mpc_step-stride fixture's AC gate — 8 of the swept 13 — than cleared the
OLD SOCP gate — 2 of 14, per 27-07's own count — since AC settlement removes the OLD
SOCP-relaxation knife-edge for most seeds even as it correctly surfaces the seed=1-specific
genuine infeasibility).

**Recommendation for Phase 28 / future MPC work:** if a future plan needs the DEFAULT `seed=1`
specifically on THIS `:ieee13`/`:default`-population, `T=9, mpc_H=3` fixture family at
`mpc_forecast_error ≳ 0.05`, it will hit this SAME genuine infeasibility and will need either a
feeder with more head-branch thermal headroom (an architectural fixture change) or a smaller
forecast-error/compounding-drift budget — not a settlement-side fix.

### Finding 2 — AC-vs-SOCP agreement at solver precision when the SOCP relaxation is independently exact

At `seed=5` (measured exact by 27-03/27-07's own prior work), the AC-settled and SOCP-settled
`realized_welfare` agree to `rel_diff ≈ 1.7e-10` — essentially solver precision, far tighter
than the `rtol=1e-4` bound pinned in `27-08-repro.jl`. This confirms the two formulations are
solving for the SAME unique physical operating point whenever the SOCP relaxation happens to
bind tight, as expected.

## Issues Encountered

The majority of this plan's time went into diagnosing the seed=1 `LOCALLY_INFEASIBLE` result
(documented above): confirming it was NOT a warm-start/convergence artifact (re-solving without
the warm start reproduces the same status; re-solving WITHOUT the `:smax`/`:smax_rev`
constraints reaches `LOCALLY_SOLVED` cleanly, isolating the thermal limit as the exact cause),
then sweeping seeds for both affected fixtures to confirm `seed=5` remains a valid, measured
substitute under the NEW settlement (it does, for both items, independently).

All temporary diagnostic scripts used during this investigation were written to the session
scratchpad directory (never inside the repository) and are not part of this commit.

## Known Stubs

None — the AC settlement, the warm-start, the throw-on-failure contract, the internal test
seam, and both new/updated tests are fully wired and exercised by `27-08-repro.jl`.

## Threat Flags

None — this plan touches only existing internal MPC-loop settlement logic (no new network
endpoint, auth path, or schema surface), matching the plan's own `<threat_model>` (the sole risk
it names — "silently accepting a non-converged AC settlement" — is exactly what this plan's
strict `LOCALLY_SOLVED` requirement and the seed=1 finding above demonstrate is NOT happening).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- FIX-10 (AC power-flow truth settlement, USER DECISION) is complete: `run_mpc`'s
  `realized_welfare` is settled by a genuine AC power flow, never a relaxation re-solve, in
  production. `27-08-repro.jl` exits 0.
- **Carried-forward finding for Phase 28 / any future MPC-touching plan:** the DEFAULT `seed=1`
  is now confirmed genuinely thermally infeasible (not merely SOCP-inexact) on two
  `test_mpc_loop.jl` fixtures at `mpc_forecast_error ≳ 0.05` — see Finding 1. Any future work
  reusing this exact fixture family at that seed will hit the SAME genuine infeasibility.
- `docs/literate/mpc_rolling_horizon.jl`'s prose (per 27-03-SUMMARY.md's own note, Phase 28
  restatement scope) will need to additionally reflect that `realized_welfare` is now
  AC-settled, not SOCP-loss-exact-settled — a semantic refinement, not a shape change.
- Orchestrator should re-run the full post-merge suite to confirm no other `(seed,
  mpc_forecast_error)` combination elsewhere in the suite newly surfaces the same class of
  genuine AC infeasibility (none found in this plan's own scope — only `test_mpc_loop.jl` calls
  `run_mpc`).

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Plan: 08*
*Completed: 2026-09-29*

## Self-Check

- FOUND: `src/experiments/mpc_loop.jl`
- FOUND: `test/test_mpc_loop.jl`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl`
- FOUND commit: `2152d4e` (Task 1)
- FOUND commit: `cd61be5` (Task 2)
- `julia --project=. .planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl` exits 0 (verified by direct execution twice, post both commits)

## Self-Check: PASSED
