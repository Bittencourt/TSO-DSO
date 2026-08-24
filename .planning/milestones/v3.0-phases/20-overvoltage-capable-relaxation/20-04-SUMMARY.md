---
phase: 20-overvoltage-capable-relaxation
plan: 04
subsystem: SOC-relaxation exactness theory / nonconvex-AC-dual fallback pricer
tags: [OVR-03, ac-dual-fallback, ipopt, multi-start, quarantine, spike]

requires:
  - phase: 20-03
    provides: "assert_restriction_exact!(ctx_restricted, ctx_ac; report) -> (; ac_feasible, matches_ac_optimum, optimality_loss, obj_gap, hours), keyed price_provenance.status ∈ {:certified_convex_dual, :cert_failed} on ac_feasible — the D-09 trigger signal this plan's fallback is gated on by the CALLER, never by this file itself"
provides:
  - "ac_dual_fallback_price(feeder, aggregators; T, λ₀, allow_export, n_seeds) -> (; dadp, cost_ac, price_status = :local_ac_dual, agreement_report) (src/models/ac_dual_fallback.jl) — documented nonconvex-AC-dual fallback, ZERO new solve machinery (re-solves via the already-existing solve_welfare(..., ACPowerFlow(), ...) path)"
  - "5 deterministic Ipopt convergence-strategy seed variants (_FALLBACK_IPOPT_VARIANTS), D-11's multi-start evidence mechanism"
  - "CI-gated 2-seed @testitem (test/test_restricted_branch_flow.jl, 7th item) demonstrating D-09 trigger discipline against BOTH a genuinely-passing and a genuinely-failing certificate"
  - "Quarantined 5-seed multistart sweep (.planning/spikes/004-ovr-fallback-multistart/) — VALIDATED: all 5 variants agree to ~1e-7 on EXACT-04, positive control passes"
affects: ["plan 20-05 (literate page — should cite this plan's measured max_cost_spread=3.84e-7/max_dadp_spread=1.05e-7 and the fact that EXACT-04 itself never triggers this fallback, per plan 20-03's revised ac_feasible=true certificate semantics)"]

tech-stack:
  added: []
  patterns:
    - "deterministic-convergence-strategy multi-start (rather than randomized initial points) as D-11's 'seeded starts' evidence, when the underlying solve function has no custom-starting-point hook — reuses test_ac_oracle.jl's existing 2-variant local-optimum guard pattern, extended from 2 to 5 variants"
    - "quarantined spike replicates a certificate's genuine-failure fixture via a diagnostic override (rtol_exact = 1.0 on an UNRESTRICTED ConvexBranchFlow context) rather than searching for a naturally-failing fixture — mirrors plan 20-03's own synthetic-violation test pattern"

key-files:
  created:
    - src/models/ac_dual_fallback.jl
    - .planning/spikes/004-ovr-fallback-multistart/sweep.jl
    - .planning/spikes/004-ovr-fallback-multistart/README.md
    - .planning/spikes/004-ovr-fallback-multistart/sweep.csv
  modified:
    - src/TSODSO.jl
    - test/test_restricted_branch_flow.jl
    - .planning/spikes/MANIFEST.md

key-decisions:
  - "Adapted the plan's Task 2 trigger-discipline demonstration to the orchestrator note's finding: since RestrictedBranchFlow's own certificate PASSES on EXACT-04 (ac_feasible = true, plan 20-03's revised semantics), reading ctx_restricted's cert alone cannot demonstrate a real D-09 trigger. Added a genuinely-failing case (unrestricted ConvexBranchFlow at rtol_exact = 1.0, mirroring 20-03's own synthetic-violation test) alongside the passing case, so the test demonstrates BOTH sides of the trigger condition honestly rather than only the vacuous passing one."
  - "Kept the plan's own 'called REGARDLESS of cert.ac_feasible' mechanics-isolation design for the actual ac_dual_fallback_price call — the plan's own action text already anticipated this test exercises the fallback's mechanics, not a live trigger, and that design needed no change."
  - "5 Ipopt convergence-strategy variants (not randomized initial points) implement D-11's 'seeded starts', per the plan's own explicit Claude's-Discretion rationale: solve_welfare has no hook to inject a custom starting point without new solve machinery, which D-01 forbids."

requirements-completed: [OVR-03]

duration: ~55min
completed: 2026-08-08
---

# Phase 20 Plan 04: Nonconvex-AC-Dual Fallback Pricer Summary

**`ac_dual_fallback_price` re-solves the AC oracle from 5 deterministic Ipopt convergence-strategy starts (D-11), tags every result `price_status = :local_ac_dual` with a mandatory agreement report (D-10), never self-triggers off the certificate (D-09) — and on the EXACT-04 fixture all 5 seeds agree to `~1e-7` (`max_cost_spread = 3.84e-7`), both at the CI-gated 2-seed level and the quarantined full 5-seed spike.**

## Performance

- **Duration:** ~55 minutes (context read + Task 1 + Task 2 + spike run + full-suite wait)
- **Started / Completed:** 2026-08-08
- **Tasks:** 2 of 2 completed
- **Files modified:** 6 (`src/models/ac_dual_fallback.jl` new, `src/TSODSO.jl`, `test/test_restricted_branch_flow.jl`, 3 new spike files under `.planning/spikes/004-ovr-fallback-multistart/`, `.planning/spikes/MANIFEST.md`)

## Accomplishments

- `ac_dual_fallback_price(feeder, aggregators; T, λ₀, allow_export = true, n_seeds = 2)
  -> (; dadp, cost_ac, price_status::Symbol, agreement_report)` — the documented
  nonconvex-AC-dual fallback (OVR-03), requiring ZERO new solve machinery: it is a second,
  seeded call to the already-existing `solve_welfare(..., ACPowerFlow(), ...; allow_local =
  true)` path.
- `price_status = :local_ac_dual` is a MANDATORY, always-present field on every returned
  `NamedTuple` — no code path omits it (T-20-10 mitigation).
- `n_seeds` bounded `2:5` by an explicit `ArgumentError` guard, never silently clamped
  (T-20-12 mitigation).
- `ac_dual_fallback.jl` has NO import or call relationship with
  `assert_restriction_exact!`/`solve_restricted` — confirmed via grep (T-20-11 mitigation;
  see Deviations for the one minor grep-count nuance).
- Seventh `@testitem` in `test/test_restricted_branch_flow.jl` demonstrates D-09's trigger
  discipline against BOTH a genuinely-PASSING certificate (`ctx_restricted` on EXACT-04,
  `ac_feasible = true`) and a genuinely-FAILING one (unrestricted `ConvexBranchFlow` at
  `rtol_exact = 1.0`), then exercises the fallback's own 2-seed mechanics.
- Quarantined spike `.planning/spikes/004-ovr-fallback-multistart/`: the FULL 5-variant
  sweep on the same fixture — **VALIDATED**, `max_cost_spread = 3.841654461211874e-7`,
  `max_dadp_spread = 1.0506617220684689e-7`, positive control (`< 1e-2`) passes with ~4
  orders of magnitude of margin.
- Full-suite closing verification: **2546 passed / 0 failed / 3 pre-existing broken / 2549
  total** (12m35.8s) — reconciles EXACTLY against the 20-03 baseline (2539/0/3/2542) plus
  this plan's 7 new `@test` assertions in the seventh `@testitem`, zero regressions.

## Task Commits

1. **Task 1: ac_dual_fallback_price — seeded multi-start Ipopt re-price + agreement report**
   - `3077a02` (feat)
2. **Task 2: CI-gated 2-seed test (trigger discipline) + quarantined 3-5-seed spike** -
   `9f51740` (test)

**Plan metadata:** SUMMARY commit (this commit, following).

## Files Created/Modified

- `src/models/ac_dual_fallback.jl` (NEW) — `ac_dual_fallback_price`, `_FALLBACK_IPOPT_VARIANTS`
  (5 deterministic Ipopt convergence-strategy `NamedTuple`s), full docstring with D-09/D-10/
  D-11 provenance.
- `src/TSODSO.jl` — one new `include("models/ac_dual_fallback.jl")`, positioned immediately
  after `models/restriction_exactness.jl`.
- `test/test_restricted_branch_flow.jl` — one new `@testitem` (7th total) demonstrating the
  fallback's D-09/D-10/D-11 contract against both a passing and a genuinely-failing
  certificate.
- `.planning/spikes/004-ovr-fallback-multistart/sweep.jl` (NEW) — self-contained 5-seed
  sweep, replicates the EXACT-04 fixture inline, verifies the copy, writes `sweep.csv`.
- `.planning/spikes/004-ovr-fallback-multistart/README.md` (NEW) — filled-in verdict
  (VALIDATED) with the actual measured spreads.
- `.planning/spikes/004-ovr-fallback-multistart/sweep.csv` (NEW) — per-seed cost/dadp-deviation
  table.
- `.planning/spikes/MANIFEST.md` — one new row for spike `004`.

## Decisions Made

See `key-decisions` in frontmatter. In prose: the plan's Task 1 mechanism (deterministic
Ipopt convergence-strategy variants as D-11's "seeded starts", `price_status =
:local_ac_dual`, the `2:5`-bounded `n_seeds` guard) needed zero adjustment and was
implemented exactly as specified. Task 2's trigger-discipline demonstration needed one
adaptation (see Deviations) to remain a genuine, non-vacuous test of D-09 given plan
20-03's orchestrator-revised certificate semantics.

## Deviations from Plan

### Auto-adapted (pre-authorized by the orchestrator's mechanism-update note)

**1. [Mechanism-note-authorized adaptation] Task 2's D-09 trigger-discipline demonstration
adapted to certify against a genuinely-failing case, not only the always-passing EXACT-04
restricted context.**

- **Found during:** Reading the orchestrator's launch-context note before starting Task 2:
  "the fallback triggers ONLY on `price_provenance.status == :cert_failed` /
  `ac_feasible == false` (D-09). On EXACT-04 the certificate passes, so your fallback tests
  need a fixture where the restricted SOCP genuinely FAILS its certificate."
- **Issue:** The plan's own Task 2 action text checks
  `assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)` on `ctx_restricted`
  (the `RestrictedBranchFlow` solve on EXACT-04) BEFORE calling the fallback, "to
  demonstrate the trigger discipline." Under plan 20-03's orchestrator-revised semantics,
  that specific call ALWAYS returns `ac_feasible = true` on EXACT-04 (the restricted
  solution's own cone is tight) — so checking it alone can never actually exercise a
  FAILING certificate, making the "trigger discipline" demonstration one-sided /
  potentially vacuous (it only shows "the fallback is not needed here," never "the fallback
  activates when the cert fails").
- **Fix:** Added a SECOND, genuinely-failing certificate check in the SAME `@testitem`,
  reusing plan 20-03's own synthetic-violation pattern: an UNRESTRICTED `ConvexBranchFlow`
  context on the SAME EXACT-04 fixture, solved with `rtol_exact = 1.0` (neutralizes PF-04
  so the genuinely cone-inexact solution is returned rather than refused). Asserted
  `cert_failing.ac_feasible == false` and
  `ctx_unrestricted.meta[:price_provenance].status == :cert_failed` — the genuine D-09
  trigger condition a real caller would gate the fallback on. The fallback call itself
  (`ac_dual_fallback_price(...)`) is still made UNCONDITIONALLY afterward, exactly as the
  plan's own action text specifies, because this test exercises the fallback's OWN
  mechanics in isolation, not a live production trigger.
- **Files modified:** `test/test_restricted_branch_flow.jl` (7th `@testitem`, plus a
  module-level comment block explaining the adaptation before it).
- **Commit:** `9f51740` (Task 2).
- **Why this needed no new checkpoint:** the orchestrator's own launch-context note
  explicitly pre-authorized this class of adaptation ("your fallback tests need a fixture
  where the restricted SOCP genuinely FAILS its certificate... Adapt your plan's
  trigger-wiring and tests to this reality; document adaptations as deviations") — this is
  precisely that adaptation, resolved by adding a genuine failure case alongside the
  plan's original passing-case check, not by removing or contradicting anything the plan
  specified.

### Minor note (acceptance-criteria raw grep count, not a functional deviation)

Task 2's acceptance criteria specify `grep -c '@testitem' test/test_restricted_branch_flow.jl`
returns `7`. The RAW grep count is `10` (same class of imprecision plans 20-02/20-03 already
documented): pre-existing header/module-level comments (carried over from plans 20-01
through 20-03, plus this plan's own new comment block explaining the D-09 adaptation above)
contain the literal substring `@testitem` in prose. There are exactly **7 actual `@testitem`
DECLARATIONS** (confirmed via `grep -c '^@testitem'` = 7, matching lines 20, 57, 98, 137,
223, 310, 373), matching the plan's own `<verify>` command's `Confirm all seven @testitems`
intent. Resolved by satisfying the INTENT (7 real items) rather than the literal
raw-grep-count text, exactly as plans 20-02/20-03 resolved the analogous imprecision.

**Task 1's acceptance criteria also specify** `grep -n
'assert_restriction_exact!\|solve_restricted' src/models/ac_dual_fallback.jl` returns NO
matches. The raw grep DOES match 4 lines (10, 16, 58, 60) — all comment lines or docstring
prose explaining the D-09 trigger discipline (a requirement the plan's own action text
mandates: "State explicitly: ... it is NEVER invoked automatically by
`assert_restriction_exact!` (D-09 ...)"). None is an actual Julia code line calling or
importing the certificate function — confirmed by inspecting each matched line's full text.
The certificate's INTENT (no import/call relationship, no self-triggering) is fully
satisfied; only the raw grep count differs from the literal criterion text, for the same
reason the file's own docstring must NAME the function it explicitly does NOT call.

---

**Total deviations:** 1 pre-authorized adaptation (Task 2's trigger-discipline test
strengthened to cover a genuinely-failing certificate case, per the orchestrator's own
launch-context guidance) + 2 minor acceptance-criteria raw-grep-count/grep-match
imprecisions (both resolved by satisfying intent, matching the established plans
20-02/20-03 precedent).

**Impact on plan:** Both tasks complete, all acceptance criteria satisfied in substance.
The fallback ships exactly the D-09/D-10/D-11 contract the plan specified, and its test
coverage is MORE RIGOROUS than the plan's original one-sided draft — it now demonstrates
both the passing and failing sides of the trigger condition, which plan 20-05's literate
page should cite directly rather than only the passing case.

## Issues Encountered

None beyond the documented deviations above. No auth gates. No blocking issues requiring
Rule 3 auto-fixes. The full-suite log contains benign, pre-existing `gitpatch`/`git diff`
warnings from `DrWatson`'s provenance tagging running inside a git worktree (`Not a git
repository` / `ProcessFailedException... Returning nothing instead`) — these are caught and
handled gracefully by `DrWatson` itself (never surfaced as a test failure) and are
unrelated to this plan's changes; several other pre-existing test items intentionally
exercise solver-retry-escalation (`ALMOST_OPTIMAL`) and HiGHS-cannot-solve-MIQP error paths
as their own documented behavior, not regressions.

## Known Stubs

None — `ac_dual_fallback_price` is fully wired to real, already-existing infrastructure
(`solve_welfare`, `ACPowerFlow`, `Ipopt.Optimizer` already imported via `src/solver/
factory.jl`) with no placeholder data paths.

## Threat Flags

None — this plan's only new input (`n_seeds`, a researcher-supplied `Int` bounded `2:5` by
an explicit guard) matches the plan's own threat model's trust-boundary description
exactly; no new network endpoint, auth path, file access, or schema change was introduced.

## Verification

- Task 1 quick-check (`julia --project=.` inline script, exact command from the plan):
  PASSED — `isdefined(TSODSO, :ac_dual_fallback_price)`, printed `OK`.
- Task 1 acceptance-criteria greps: 3 of 4 literal-match PASSED; the 4th
  (self-trigger-guard grep) matches only comment/docstring prose, satisfying intent (see
  Deviations).
- Task 2 quick-check (plain `Test.jl` script, adapted per the documented deviation to add
  the genuinely-failing certificate case): PASSED — all `@test` assertions green, including
  `cert.ac_feasible == true` (EXACT-04's restricted solve), `cert_failing.ac_feasible ==
  false` / `price_provenance.status == :cert_failed` (the unrestricted synthetic
  violation), `result.price_status == :local_ac_dual`, 2-seed cost agreement
  (`rtol = 1e-3`), and `all(isfinite, result.dadp)`.
- Quarantined 5-seed spike (`julia --project=.
  .planning/spikes/004-ovr-fallback-multistart/sweep.jl`): exits 0, produces `sweep.csv`,
  positive control (`max_cost_spread = 3.84e-7 < 1e-2`) PASSES with ~4 orders of magnitude
  of margin — VALIDATED verdict.
- Full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`, background, 12m35.8s):
  **2546 passed / 0 failed / 3 pre-existing broken / 2549 total** — reconciles exactly
  against the 20-03 baseline (2539/0/3/2542) plus this plan's 7 new `@test` assertions. No
  other test file was touched; `test_ac_oracle.jl` and all `test_restricted_branch_flow.jl`
  items from plans 20-01/20-02/20-03 remain green in the same run (zero regressions).

## Self-Check: PASSED

- `src/models/ac_dual_fallback.jl` exists and contains `function ac_dual_fallback_price`:
  FOUND.
- `src/TSODSO.jl` contains the `models/ac_dual_fallback.jl` include line, positioned after
  `models/restriction_exactness.jl`: FOUND.
- `test/test_restricted_branch_flow.jl` contains 7 `@testitem` DECLARATIONS: FOUND
  (`grep -c '^@testitem'` = 7).
- `.planning/spikes/004-ovr-fallback-multistart/{sweep.jl,README.md,sweep.csv}` all exist:
  FOUND.
- `.planning/spikes/MANIFEST.md` has a new row for `004`: FOUND.
- Commits `3077a02` (Task 1) and `9f51740` (Task 2) exist in `git log`: FOUND.
- Full-suite run: **2546 passed / 0 failed / 3 pre-existing broken / 2549 total** — FOUND
  (log tail: `Package | 2546 3 2549 12m35.8s`).

## Next Phase Readiness

**Ready for plan 20-05 (literate page).** The fallback exists, is tested at both the
CI-gated 2-seed level and the quarantined full 5-seed level, and both levels agree the
mechanism is stable on EXACT-04 (`max_cost_spread ≈ 3.84e-7`). Plan 20-05 should narrate
THREE distinct, now-measured findings from plans 20-02/20-03/20-04 as separate questions:
(1) does the restricted SOCP's OWN cone close? (yes, plan 20-02, `socp_maxgap = 2.08e-8`);
(2) does the restricted dispatch MATCH the true AC optimum? (no, during the binding window,
plan 20-03, `matches_ac_optimum = false`, `optimality_loss ≈ -1.4326`); (3) is the fallback
pricer (this plan) actually needed on EXACT-04? (no — RestrictedBranchFlow's own
`ac_feasible` certificate passes there; the fallback is a general safety net for a
regime/fixture where it does NOT, exercised here only via the synthetic-violation test and
spike, never as EXACT-04's live answer).

---
*Phase: 20-overvoltage-capable-relaxation*
*Completed: 2026-08-08*
