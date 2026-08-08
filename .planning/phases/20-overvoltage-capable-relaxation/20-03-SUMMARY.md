---
phase: 20-overvoltage-capable-relaxation
plan: 03
subsystem: SOC-relaxation exactness theory / restricted-SOCP validity certificate
tags: [OVR-02, gan-low, socp-exactness, ac-oracle, certificate, opf-m]

requires:
  - phase: 20-02
    provides: "RestrictedBranchFlow <: AbstractPowerFlow implementing Gan-Low OPF-m (v̂_GL(s) ≤ v̄ shadow-voltage constraint), certifying socp_maxgap = 2.08e-8 on EXACT-04 via assert_socp_exact!"
provides:
  - "assert_restriction_exact!(ctx_restricted, ctx_ac; rtol, atol, unrestricted_cost, report) -> (; ac_feasible, optimality_loss, obj_gap, hours) (src/models/restriction_exactness.jl) — NEW, named, exported certificate, peer to assert_socp_exact!/assert_ac_exact!/assert_4q_complementarity!"
  - "Own measured tolerances (rtol=1e-3, atol=2e-5) on the RestrictedBranchFlow-vs-ACPowerFlow residual, never copied from assert_ac_exact!'s 1e-4/1e-6 defaults (D-07)"
  - "D-08 provenance stash (ctx.meta[:price_provenance]) — formulation/certificate/status, unconditional on pass and fail"
  - "Documented, causally-diagnosed finding: on the FULL EXACT-04 fixture, OPF-m's v̂_GL(s)≤v̄ constraint genuinely BINDS during the high-PV window (nonzero :opfm_shadow_voltage duals up to -24.18), so the restricted optimum diverges from the true AC optimum there (ac_feasible=false, optimality_loss≈-1.4326) — NOT a bug, the provable consequence of a genuine feasible-set restriction (D-01)"
affects: ["plan 20-04 (AC-dual fallback — this finding sharpens the fallback's rationale: OPF-m does NOT guarantee dispatch-level AC-optimality even when its OWN cone is exact)", "plan 20-05 (literate page — must narrate BOTH plan 20-02's cone-exactness result AND this plan's dispatch-match/optimality-loss finding as two DISTINCT questions with two DISTINCT answers on EXACT-04)"]

tech-stack:
  added: []
  patterns:
    - "certificate-composes-certificate: assert_restriction_exact! calls assert_ac_exact! internally with its OWN freshly-measured tolerances, reusing the per-hour loop rather than re-implementing it — a reusable pattern for any future 'certify formulation X against independently-solved formulation Y, plus a derived quantity' certificate"
    - "causal diagnosis via constraint dual, not just residual magnitude: confirming a restriction/relaxation finding by reading dual(ctx.constraints[:name]) rather than inferring bindingness from gap size alone (mirrors test_ac_oracle.jl's voltage_bound_hit/reverse_flow diagnostic pattern, generalized to a dual-based check)"

key-files:
  created:
    - src/models/restriction_exactness.jl
  modified:
    - src/TSODSO.jl
    - test/test_restricted_branch_flow.jl

key-decisions:
  - "Implemented assert_restriction_exact! exactly per the plan's Task 1 mechanism (calls assert_ac_exact! internally with fresh tolerances; computes ac_feasible/optimality_loss/obj_gap/hours; unconditional D-08 provenance stash; throw-by-default/report=true D-06 contract) — the STRUCTURE was correct and needed no change."
  - "Measured rtol/atol HONESTLY on the actual restricted-vs-AC residual rather than loosening them to force the plan's predicted ac_feasible=true outcome on EXACT-04 — loosening enough to swallow the genuine ~1e-2..3e-2 scale restriction-binding gaps at hours 9-12/14-15 would have been certificate-laundering (D-07/T-20-07), defeating the certificate's purpose."
  - "Adapted Task 2's testitem 5 assertions to the ACTUAL, causally-diagnosed measured behavior (ac_feasible=false, price_provenance.status=:cert_failed) rather than the plan's untested prediction (ac_feasible=true) — confirmed via a NEW diagnostic (nonzero :opfm_shadow_voltage constraint dual, up to -24.18) that the divergence is a genuine ACTIVE restriction effect, not noise or a bug."

requirements-completed: [OVR-02]

duration: ~70min
completed: 2026-08-08
---

# Phase 20 Plan 03: assert_restriction_exact! Certificate Summary

**A new, named certificate `assert_restriction_exact!` (peer to `assert_socp_exact!`/`assert_ac_exact!`/`assert_4q_complementarity!`) certifies `RestrictedBranchFlow` against the independently-solved AC oracle and reports optimality loss in one call — and on the full EXACT-04 fixture it correctly, honestly reports `ac_feasible = false` with a substantial negative `optimality_loss`, because Gan-Low's OPF-m restriction genuinely and provably diverges from the true AC-optimal dispatch during the fixture's high-PV window (confirmed causally via nonzero `:opfm_shadow_voltage` constraint duals, not mere gap-size correlation).**

## Performance

- **Duration:** ~70 minutes (context read + measurement scripts + Task 1 + Task 2 + full-suite wait)
- **Started / Completed:** 2026-08-08
- **Tasks:** 2 of 2 completed
- **Files modified:** 3 (`src/models/restriction_exactness.jl` new, `src/TSODSO.jl`, `test/test_restricted_branch_flow.jl`)

## Accomplishments

- `assert_restriction_exact!(ctx_restricted, ctx_ac; rtol, atol, unrestricted_cost, report)
  -> (; ac_feasible, optimality_loss, obj_gap, hours)` — a genuinely NEW, exported
  certificate (never a modification of `assert_ac_exact!`/`assert_socp_exact!`), reusing
  `assert_ac_exact!`'s per-hour comparison loop internally with its OWN, freshly measured
  `rtol = 1e-3, atol = 2e-5` (never `assert_ac_exact!`'s literal `1e-4`/`1e-6` defaults —
  verified absent via `grep`).
- `optimality_loss` is a NAMED field (`Union{Float64,Nothing}`), never folded into
  `obj_gap`; `nothing` when `unrestricted_cost` is not supplied (D-05, T-20-09's documented
  contract).
- D-08 provenance stash `ctx_restricted.meta[:price_provenance] = (; formulation,
  certificate, status)` is UNCONDITIONAL — written on both the pass and fail path, so a
  stale `:certified_convex_dual` marker from a prior call can never survive a later failed
  certification on a reused `ctx` (T-20-08).
- Throw-by-default (D-06); `report = true` neutralizes to `@warn` and returns the full
  diagnostic — mirroring `assert_4q_complementarity!`'s contract exactly.
- Six `@testitem`s total in `test/test_restricted_branch_flow.jl` (2 new): the certificate's
  positive-diagnostic path (adapted, see Deviations) and the throw/report polarity test on a
  structural T-mismatch (D-06, unmodified from plan intent).
- Full-suite closing verification: **2536 passed / 0 failed / 3 pre-existing broken / 2539
  total** (15m27s) — reconciles EXACTLY against the 20-02 baseline (2524/0/3) plus this
  plan's 12 new `@test` assertions (10 in testitem 5 + 2 in testitem 6), zero regressions.

## Task Commits

1. **Task 1: assert_restriction_exact! — AC-feasibility + optimality-loss + provenance** -
   `997dae9` (feat)
2. **Task 2: Certificate tests — throw/report polarities + optimality-loss field** -
   `d6c7966` (test)

**Plan metadata:** SUMMARY commit (this commit, following).

## Files Created/Modified

- `src/models/restriction_exactness.jl` (NEW) — `assert_restriction_exact!`, full docstring
  with a "Tolerance provenance" section (clean-hour vs. binding-hour vs. coupling-artifact
  scale separation) and a "Verdict on EXACT-04" section documenting the measured finding.
- `src/TSODSO.jl` — one new `include("models/restriction_exactness.jl")`, positioned
  immediately after `models/ac_oracle.jl` (this file calls `assert_ac_exact!`, so it must
  load after it).
- `test/test_restricted_branch_flow.jl` — two new `@testitem`s appended to plans 20-01/20-02's
  four existing items (now 6 total): the certificate's positive-diagnostic path on EXACT-04
  (adapted per the measured finding) and the throw/report structural-mismatch polarity test.

## Decisions Made

See `key-decisions` in frontmatter. In prose: the certificate's STRUCTURE (what the plan's
Task 1 specified — reuse `assert_ac_exact!`'s loop with fresh tolerances, unconditional
provenance, throw/report contract, named optimality-loss field) needed zero adjustment and
was implemented exactly as written. What DID need adjustment was the plan's PREDICTED
OUTCOME on the EXACT-04 fixture (Task 2's `<verify>` script and testitem 5's action text
both assumed `report.ac_feasible == true`) — measurement showed the opposite, honest
verdict. Rather than loosening the certificate's tolerances to force the predicted outcome
(which the D-07/T-20-07 threat mitigation explicitly forbids — that would be
certificate-laundering, hiding a real finding), the tolerances were kept honest and Task
2's test assertions were adapted to match the causally-diagnosed reality.

## Deviations from Plan

### Auto-adapted findings (pre-authorized by the orchestrator's mechanism-update note)

**1. [Mechanism-note-authorized adaptation] The plan's Task 2 predicted `ac_feasible ==
true` on the FULL EXACT-04 fixture; measurement shows `ac_feasible == false`, and this is
the correct, honest certificate behavior.**

- **Found during:** Task 1's own tolerance-measurement step (per the plan's own action
  text: "call the file's OWN `assert_ac_exact!`... diagnostically to READ the observed
  `vgap`/`pgap`/`qgap` scale — RESEARCH.md predicts this collapses to `~1e-6`-`~1e-7`").
- **Measurement (2026-08-08, `RestrictedBranchFlow()` vs `ACPowerFlow()`, EXACT-04 fixture,
  `pv_scale = 1.2`, both `allow_export = true`, AC also `allow_local = true`):**
  - **Clean hours (1–5, 16–24):** `vgap` ≤ `1.44e-6` absolute, `pgap` ≤ `9.18e-6`
    absolute — matches RESEARCH.md's `~1e-6`-`~1e-7` prediction exactly (this is the
    genuine Clarabel/Ipopt solver-noise floor).
  - **Restriction-BINDING hours (9, 10, 11, 12, 14, 15):** `vgap` up to `5.44e-3`, `pgap`
    up to `3.09e-2` — six orders of magnitude above the clean-hour floor.
  - **Coupling-artifact hours (6, 7, 8, 13):** intermediate elevated gaps (`~2.3e-4` to
    `~3.5e-3`) with near-zero constraint duals — inter-temporal spillover from the adjacent
    binding hours, the same phenomenon `test_ac_oracle.jl`'s ORIGINAL EXACT-04 finding
    documents.
- **Causal diagnosis (not merely correlational):** `dual(ctx_restricted.constraints[:opfm_shadow_voltage][...])`
  is a LARGE nonzero value (up to `-24.18` at bus 3, hour 9) at exactly the binding hours,
  confirming the OPF-m `v̂_GL(s) ≤ v̄` constraint is ACTIVELY EXCLUDING the true AC-optimal
  dispatch there — not a numerical artifact. `assert_socp_exact!` (PF-04) still certifies
  the restricted solution's OWN cone as exact at this SAME point
  (`socp_maxgap = 2.08e-8`, unchanged from plan 20-02) — the restricted point IS a real,
  physically-realizable branch-flow point; it is simply NOT the same point as the
  independently-solved AC-optimal dispatch, because the restriction (Lemma 1: `v ≤
  v̂_GL(s)` always, so `v̂_GL(s) ≤ v̄` is a genuine feasible-set RESTRICTION, D-01)
  provably excludes the AC optimum from consideration during this window.
  `cost_restricted = -923.5042 < cost_ac = -922.9417 < cost_unrestricted = -922.0716`
  confirms the expected Theorem-2-consistent welfare ordering (restricted-feasible-set ⊆
  AC-feasible-set ⊆ unrestricted-SOCP-relaxed-feasible-set), i.e. `optimality_loss =
  cost_restricted - cost_unrestricted ≈ -1.4326` is a real, principled quantity, not noise.
- **Resolution:** implemented the certificate's own tolerances HONESTLY (`rtol = 1e-3, atol
  = 2e-5`, ~12-14× the measured clean-hour floor, mirroring `assert_4q_complementarity!`'s
  sizing discipline) rather than loosening toward the binding-hour scale (which the D-07/
  T-20-07 threat mitigation forbids as certificate-laundering). Adapted testitem 5's
  assertions to the ACTUAL, causally-diagnosed outcome: `report.ac_feasible == false`,
  `report.optimality_loss <= 1e-6` (a real, negative loss), `price_provenance.status ==
  :cert_failed`. Kept the certificate's own structure, docstring contract, and Task 1's
  full acceptance criteria unmodified — only the TEST'S expected verdict on this ONE
  fixture changed, matching reality.
- **Why this was resolved without a new checkpoint:** the orchestrator's launch context
  explicitly pre-authorized this class of adaptation ("Where your plan's tasks reference ε
  semantics, adapt to the actual OPF-m implementation... the certificate must certify what
  the code actually does. Document any such adaptation as a deviation") — this plan's own
  Task 1 measurement work surfaced an analogous "the mechanism's real behavior differs from
  RESEARCH.md's prediction" finding (structurally the SAME class of finding 20-02
  escalated via Rule 4 for OPF-ε), but for THIS finding the resolution required no
  structural/architectural change — only an honest tolerance measurement and a matching
  test-assertion update, both squarely within the certificate's own D-07 mandate. No new
  Rule-4 checkpoint was needed.
- **Files modified:** `src/models/restriction_exactness.jl` (docstring documents both the
  clean-hour floor and the binding-hour finding, with the causal dual-based diagnosis
  cited); `test/test_restricted_branch_flow.jl` (testitem 5 renamed and its assertions
  adapted to the measured verdict, with a module-level comment block explaining the
  deviation before the two new items).
- **Commits:** `997dae9` (Task 1, certificate + docstring), `d6c7966` (Task 2, adapted
  tests).

### Minor note (acceptance-criteria raw grep count, not a functional deviation)

Task 2's acceptance criteria specify `grep -c '@testitem' test/test_restricted_branch_flow.jl`
returns `6`. The RAW grep count is `9` because the file's PRE-EXISTING header comments
(carried over from plans 20-01/20-02, e.g. "The FIRST `@testitem` below is...") already
contained 3 comment-line substring matches of the literal text `@testitem` BEFORE this
plan touched the file (confirmed: `grep -c` on the pre-20-03 file returns `7`, not `4`).
There are exactly **6 actual `@testitem` DECLARATIONS** (confirmed via `grep -n '@testitem'`
— lines 20, 57, 98, 137, 217, 294), matching the plan's own `<done>` criterion ("Six green
@testitems total") and `<verification>`'s "Confirm all six `@testitem`s ... pass". This is
the same class of minor plan-text imprecision plan 20-02 documented for its `cpydrop`
acceptance-criteria self-contradiction — resolved by satisfying the INTENT (6 real items)
rather than the literal raw-grep-count text.

---

**Total deviations:** 1 pre-authorized adaptation (measured, honest certificate behavior
differs from the plan's untested prediction on the EXACT-04 fixture; resolved by keeping
the certificate's tolerances honest and adapting the test's expected verdict, fully
causally diagnosed) + 1 minor acceptance-criteria raw-grep-count imprecision (resolved by
satisfying intent).

**Impact on plan:** Both tasks complete, all acceptance criteria satisfied in substance.
The certificate ships exactly the D-05/D-06/D-07/D-08 contract the plan specified. Its
behavior on EXACT-04 is now a MORE INFORMATIVE finding than the plan anticipated: OPF-m
closing `assert_socp_exact!`'s cone-tightness gap (plan 20-02) does NOT imply
dispatch-level AC-optimality once the restriction genuinely binds — a distinction plans
20-04 (fallback) and 20-05 (literate page) should narrate explicitly as two separate
questions with two separate, both-now-measured answers on this fixture.

## Issues Encountered

None beyond the documented deviation above. No auth gates. No blocking issues requiring
Rule 3 auto-fixes.

## Known Stubs

None — the certificate is fully wired to real, already-existing infrastructure
(`assert_ac_exact!`, `RestrictedBranchFlow`, `ACPowerFlow`, `ConvexBranchFlow`,
`Phase4Fixtures`) with no placeholder data paths. `unrestricted_cost = nothing` (default)
producing `optimality_loss = nothing` is a DOCUMENTED, explicit contract (T-20-09, accepted
disposition in the plan's threat model), not a stub.

## Threat Flags

None — the certificate's only new input (`unrestricted_cost`, a researcher-supplied local
`Float64`/`nothing`) matches the plan's own threat model's trust-boundary description
exactly; no new network endpoint, auth path, file access, or schema change was introduced.

## Verification

- Task 1 quick-check (`julia --project=.` inline script, exact command from the plan):
  PASSED — `isdefined(TSODSO, :assert_restriction_exact!)`, printed `OK`.
- Task 1 acceptance-criteria greps: all 4 PASSED (function-def grep matches once;
  reuse-grep matches; copy-guard grep returns NO matches; provenance grep matches).
- Task 2 quick-check (plain `Test.jl` inline script, adapted per the documented deviation
  to assert the ACTUAL measured verdict instead of the plan's untested prediction): PASSED
  — all `@test` assertions green, including the causal `:opfm_shadow_voltage` dual check
  (`maximum(opfm_duals) > 1.0`), `report.ac_feasible == false`,
  `report.optimality_loss ≈ -1.4326`, `price_provenance.status == :cert_failed`, and both
  structural-mismatch throw assertions (default and `report = true`).
- Full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`, background, 15m27s):
  **2536 passed / 0 failed / 3 pre-existing broken / 2539 total** — reconciles exactly
  against the 20-02 baseline (2524/0/3) plus this plan's 12 new `@test` assertions. No
  other test file was touched; `test_ac_oracle.jl` and all `test_restricted_branch_flow.jl`
  items from plans 20-01/20-02 remain green in the same run (zero regressions).

## Self-Check: PASSED

- `src/models/restriction_exactness.jl` exists and contains `function assert_restriction_exact!`:
  FOUND.
- `src/TSODSO.jl` contains the `models/restriction_exactness.jl` include line, positioned
  after `models/ac_oracle.jl`: FOUND.
- `test/test_restricted_branch_flow.jl` contains 6 `@testitem` DECLARATIONS: FOUND
  (`grep -n '@testitem'` lines 20, 57, 98, 137, 217, 294).
- Commits `997dae9` (Task 1) and `d6c7966` (Task 2) exist in `git log`: FOUND.
- Full-suite run: **2536 passed / 0 failed / 3 pre-existing broken / 2539 total** — FOUND
  (log tail: `Package | 2536 3 2539 15m27.0s`).

## Addendum (orchestrator revision)

**Date:** 2026-08-08 (same day, targeted revision pass after this plan's initial merge).

**What changed and why (D-05 coherence):** the implementation above defined `ac_feasible`
as "the restricted dispatch MATCHES the independently-solved AC-optimal dispatch" — i.e.
`assert_restriction_exact!` literally required `all(row.exact for row in
assert_ac_exact!(ctx_restricted, ctx_ac).hours)`. Under that definition,
`ac_feasible = true` forces `optimality_loss ≈ 0` by construction: a restricted point can
only pass certification if it happens to reproduce the AC-optimal dispatch exactly, which
makes D-05's contract — "**one** certificate that certifies AC-feasibility **and** reports
the optimality loss vs the unrestricted bound" — internally incoherent. The `optimality_loss`
field only has meaning for a point that is feasible but NOT optimal; the original predicate
structurally excluded that case from ever certifying.

`assert_restriction_exact!` was revised to certify PHYSICAL AC-feasibility of the restricted
solution itself, rather than dispatch-match with the independently-solved AC optimum:

- **New certification gate (`ac_feasible`):** the SAME per-branch, per-hour cone-equality
  residual `assert_socp_exact!` gates — `gap[b,t] = |value(l[b,t])·value(v[from_b,t]) −
  (value(P[b,t])² + value(Q[b,t])²)|` — computed directly on `ctx_restricted` (reimplemented
  inline rather than delegating to `assert_socp_exact!`, so this certificate owns its own
  throw/report decision), against a SCALE-FREE bound `gap ≤ cone_atol + cone_rtol·max(|l·v|,
  |P²+Q²|)`. A tight cone at a solved branch-flow point IS, by the model's own physics, a
  genuine AC operating point (Gan-Low Theorem 2) — this is now the correctness bar the
  certificate enforces, independent of global optimality.
- **New tolerances (`cone_rtol = 5e-4`, `cone_atol = 2e-7`):** freshly measured on
  `ctx_restricted`'s own cone residual on the EXACT-04 fixture (never copied from
  `assert_socp_exact!`'s `1e-4`/`1e-6` defaults, per D-07/T-20-07). The measured floor
  reproduces plan 20-02's finding EXACTLY: absolute floor `2.08e-8`, relative floor
  `5.08e-5` (both at branch `b=2`, hour `t=19`) — confirming this certificate's independent
  cone computation agrees with `assert_socp_exact!`'s internal one. Defaults are set ~10×
  above that floor, mirroring the existing sizing discipline; at these defaults the
  worst-branch-hour ratio on EXACT-04 is `≈0.051` (well inside the `≤1` pass bound).
- **Demoted diagnostic (`matches_ac_optimum`, NEW field):** the original dispatch-match
  check (`assert_ac_exact!(ctx_restricted, ctx_ac; rtol, atol)`, unchanged `rtol = 1e-3,
  atol = 2e-5` — a genuinely different quantity from the new cone tolerances, kept as-is
  since it was already honestly measured) is retained VERBATIM as a diagnostic field rather
  than the certification gate. The full per-hour `hours` report and `obj_gap` are still
  always returned.
- **`price_provenance.status`** is now keyed on the new `ac_feasible` (physical-feasibility)
  verdict, never on `matches_ac_optimum` — `:certified_convex_dual` iff the cone-tightness
  predicate passes, `:cert_failed` otherwise.

**Revised verdict on EXACT-04 (full fixture, `pv_scale = 1.2`):**
`assert_restriction_exact!(ctx_restricted, ctx_ac; unrestricted_cost = cost_unrestricted)`
now returns **`ac_feasible = true`** (the restricted solution's own cone is tight — a
genuine branch-flow point), **`matches_ac_optimum = false`** (hours 7–15 still diverge from
the independently-solved AC optimum, unchanged finding), and **`optimality_loss ≈ -1.4326`**
(unchanged magnitude/sign: `cost_restricted − cost_unrestricted`, negative because
`RestrictedBranchFlow`'s feasible set is a genuine subset of the unrestricted relaxation's,
D-01). The prior implementation's honest empirical finding — OPF-m's `v̂_GL(s) ≤ v̄`
constraint genuinely and causally binds during the high-PV window, confirmed via nonzero
`:opfm_shadow_voltage` duals up to `-24.18` — is unchanged and fully preserved, just now
correctly reported as a `matches_ac_optimum = false` diagnostic rather than an
`ac_feasible = false` certification failure. `assert_socp_exact!` (PF-04) still independently
certifies the same cone exact (`socp_maxgap = 2.08e-8`, plan 20-02) — this revision makes
`assert_restriction_exact!` agree with that finding instead of contradicting it.

**Additional test coverage added:** a synthetic-violation check in the fifth `@testitem` —
an UNRESTRICTED `ConvexBranchFlow` context solved on the same EXACT-04 fixture with
`rtol_exact = 1.0` (neutralizing PF-04 so the genuinely cone-INEXACT solution is returned
rather than refused) is passed to the revised `assert_restriction_exact!` and correctly
fails the new `ac_feasible` gate (`report = true` returns `ac_feasible = false`,
`price_provenance.status = :cert_failed`; the default `report = false` call throws) —
confirming the certificate actually gates cone-tightness rather than trivially passing any
solved context. The sixth `@testitem` (structural T-mismatch throw/report polarity) is
unaffected by the semantic change and was left unmodified; both its assertions were
independently re-verified to still hold under the revised implementation.

**Verification:**
- Standalone `Test.jl` script (`--project=.`) exercising the positive path (EXACT-04
  restricted solve, `ac_feasible = true`, `matches_ac_optimum = false`, `optimality_loss ≈
  -1.4326`), the synthetic violation (unrestricted inexact context, `ac_feasible = false`),
  and the structural T-mismatch guard (throws unconditionally under both `report = false`
  and `report = true`): **all assertions PASSED**.
- Full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`, background, 12m21.1s):
  **2539 passed / 0 failed / 3 pre-existing broken / 2542 total** — reconciles exactly
  against this plan's original 2536/0/3/2539 baseline plus the 3 new synthetic-violation
  `@test` assertions this revision added. Zero regressions; the same 3 pre-existing broken
  items are unchanged (`test_ac_oracle.jl` and the rest of `test_restricted_branch_flow.jl`
  remain green in the same run).

**Files modified (this revision):**
- `src/models/restriction_exactness.jl` — certification predicate, tolerance parameters,
  docstring, and header comment rewritten; commit `512aa9d`
  (`fix(20-03): certify physical AC-feasibility instead of dispatch-match`).
- `test/test_restricted_branch_flow.jl` — fifth `@testitem`'s assertions and module-level
  comment updated to the revised semantics, plus the new synthetic-violation check; commit
  `59f49fd` (`fix(20-03): adapt certificate tests to physical-feasibility semantics`).

**Impact:** D-05's contract is now internally coherent — the certificate can certify a
feasible-but-suboptimal restricted point (the common, expected case whenever OPF-m's
restriction genuinely binds) while still reporting exactly how far that point's welfare and
dispatch diverge from the unrestricted bound and the true AC optimum, respectively. Plans
20-04 (AC-dual fallback) and 20-05 (literate page) should cite `ac_feasible` (physical
feasibility) as the fallback trigger per D-09, and `matches_ac_optimum`/`optimality_loss` as
the two separate quantitative findings to narrate — not the reverse.

---
*Phase: 20-overvoltage-capable-relaxation*
*Completed: 2026-08-08*
*Revised: 2026-08-08 (orchestrator targeted-revision pass — see Addendum above)*
