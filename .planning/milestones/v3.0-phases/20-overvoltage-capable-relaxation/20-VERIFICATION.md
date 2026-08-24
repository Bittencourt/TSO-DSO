---
phase: 20-overvoltage-capable-relaxation
verified: 2026-08-09T01:55:33Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 20: Overvoltage-Capable Relaxation Verification Report

**Phase Goal:** A researcher can price the high-PV overvoltage regime that v2.1's AC oracle
proved the plain SOCP relaxation cannot solve exactly (EXACT-04), keeping the "prices are
duals of one convex problem" story intact via a feasible-set restriction rather than a
heuristic penalty.
**Verified:** 2026-08-09T01:55:33Z
**Status:** passed
**Re-verification:** No — initial verification (no prior `*-VERIFICATION.md` existed)

## Goal Achievement

### Observable Truths (Success Criteria, roadmap owner's amended mechanism: OPF-m)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Restricted SOCP (`RestrictedBranchFlow`, Gan-Low OPF-m shadow-voltage restriction) solves EXACT-04 through `solve_welfare` as a formulation variant, cone-exact where the unrestricted relaxation was proven genuinely inexact | ✓ VERIFIED | Live-executed (this verification, not just SUMMARY): `solve_welfare(feeder, RestrictedBranchFlow(), aggs; T=24, λ₀=mem_price, allow_export=true)` on the EXACT-04 fixture (`pv_scale=1.2`) returns `ctx.meta[:socp_maxgap] = 2.080395211699962e-8` (< 1e-5 gate, matches plan 20-02's/20-05's documented value exactly), vs. the unrestricted `ConvexBranchFlow(rtol_exact=1.0)` diagnostic solve's `10.437737223498573`. Dispatch confirmed by Julia multiple-dispatch alone — `problem_class(::RestrictedBranchFlow) = SOCP()`, zero `if formulation ==` branching in `src/models/welfare_solve.jl` (unchanged) or `src/powerflow/RestrictedBranchFlow.jl`. |
| 2 | New validity certificate `assert_restriction_exact!` (peer of `assert_socp_exact!`/`assert_ac_exact!`, own measured tolerances) certifying physical AC-feasibility + reporting optimality loss vs. the unrestricted SOCP bound, with `matches_ac_optimum` diagnostic | ✓ VERIFIED | Live-executed: `assert_restriction_exact!(ctx_restricted, ctx_ac; unrestricted_cost=cost_unrestricted)` returns `(ac_feasible=true, matches_ac_optimum=false, optimality_loss=-1.4325921942337345, obj_gap=-0.5625114149354431, hours=[...])` — reproduced independently by this verifier and matching `20-03-SUMMARY.md`'s Addendum and the live docs build byte-for-byte. `cone_rtol=5e-4`/`cone_atol=2e-7` (certification gate) and `rtol=1e-3`/`atol=2e-5` (`matches_ac_optimum` diagnostic) are documented in-docstring as independently measured on `ctx_restricted`'s own residual — grep-confirmed absent of `assert_socp_exact!`'s/`assert_ac_exact!`'s literal `1e-4`/`1e-6` defaults. `price_provenance` stashed unconditionally (`src/models/restriction_exactness.jl:243,294-298`), scrubbed first to prevent stale-marker survival past a structural throw (review WR-02 fix, `c81a5e7`). |
| 3 | DADP prices as genuine convex duals of the restricted problem with provenance marker; documented nonconvex-AC-dual fallback (`price_status` structural field, multi-start evidence, triggered only on certificate failure, reported never thrown) | ✓ VERIFIED | `ctx.meta[:price_provenance] = (; formulation=:RestrictedBranchFlow, certificate=:assert_restriction_exact!, status=:certified_convex_dual)` on the passing EXACT-04 solve (`formulation` read from `ctx.meta[:formulation]`, never fabricated — review WR-01 fix `b5ac2bd`, confirmed live: an unrestricted `ConvexBranchFlow` context correctly reports `formulation=:unknown`). `ac_dual_fallback_price(feeder, aggs; T=24, λ₀=mem_price, n_seeds=5)` live-executed by this verifier: returns `price_status=:local_ac_dual`, `agreement_report` with `max_cost_spread=3.95e-7`, `max_dadp_spread=1.07e-7` (matches the quarantined spike's `~1e-7` verdict). `grep -n 'assert_restriction_exact!\|solve_restricted' src/models/ac_dual_fallback.jl` returns zero matches — no call relationship in either direction, confirming D-09's "caller decides" discipline structurally. Certificate `error()`s by default, `@warn`s under `report=true` — confirmed via direct throw/no-throw test on a synthetic cone-inexact `ConvexBranchFlow` context. |
| 4 | Live-executed literate rung page documenting the mechanism (incl. the honest OPF-ε negative result), measured optimality loss, and fallback semantics beside the Gan & Low condition | ✓ VERIFIED | `docs/literate/restricted_branch_flow.jl` (324 lines, no stubs/placeholders) covers: fixture construction, "The Gan-Low condition" (C1/C2, Theorem 1/2, Lemma 1, Definition 3) as its own subsection, live `ε_measured`/Lemma-1 recomputation, three-formulation solve, the free PF-04 signal, the live `assert_restriction_exact!` certificate call, fallback semantics (prose-only per D-09, not triggered since the cert passes), and a closing "Finding" section narrating the honest OPF-ε failure alongside the OPF-m success. `julia --project=docs docs/make.jl` executed live by this verifier: **exits 0**, registered in both the `Literate.markdown` loop and the `Models` pages list (`docs/make.jl` lines with `restricted_branch_flow.jl`/`.md`), all three new exported docstrings (`RestrictedBranchFlow`, `assert_restriction_exact!`, `ac_dual_fallback_price`) wired into `docs/src/api.md`'s `@autodocs` `Pages` lists (no `checkdocs=:exports` failure). Inspected the built HTML (`docs/build/generated/restricted_branch_flow.html`) directly: every live number matches this verifier's own independent script run exactly — `socp_maxgap`: `10.437737223498573` → `2.080395211699962e-8`; `ac_feasible=true`, `matches_ac_optimum=false`, `optimality_loss=-1.4325921942337345`; `ε_measured=0.005811069127373614`; `lemma1_mingap=0.0`. Title correctly reads "A Gan-Low OPF-m Restriction" (review WR-05 fix `485bb55` confirmed applied — no stale "OPF-ε" mislabel). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/powerflow/RestrictedBranchFlow.jl` | `RestrictedBranchFlow <: AbstractPowerFlow`, delegate-then-restrict `contribute!`, `problem_class`, export | ✓ VERIFIED | Exists, exported, wired (dispatched live). Constructor rejects negative `ε` via `ArgumentError` on both kwarg and positional paths (review WR-06 fix `5707073`, confirmed via `@test_throws` and direct execution). |
| `src/models/restriction_exactness.jl` | `assert_restriction_exact!` peer certificate | ✓ VERIFIED | Exists, exported, wired, produces correct, reproducible verdict live. |
| `src/models/ac_dual_fallback.jl` | `ac_dual_fallback_price` fallback pricer | ✓ VERIFIED | Exists, exported, wired, routes NLP solver through the factory (`select_optimizer(NLP(); variants[i]...)`), review WR-04 fix `671f7a5` confirmed — no `Ipopt.Optimizer` literal in this file. |
| `src/models/ac_oracle.jl` (`recover_lossfree_shadow_voltage`) | Gan-Low shadow-voltage post-processing helper, plan 20-01 | ✓ VERIFIED | Exists, exported, byte-identical math to the OPF-m model-build constraint. CR-01 orientation fix (`6be860b`) confirmed present (tree-parent + signed branch index in both the post-processing helper AND the model-build loop) and independently regression-tested (`test/test_restricted_branch_flow.jl:502-600`, reversed-branch fixture agrees to `<1e-12` with the parent→child encoding). |
| `test/test_restricted_branch_flow.jl` | Growing `@testitem` suite across plans 20-01..04 + post-review fixes | ✓ VERIFIED | 9 `@testitem`s (7 from plans + 2 added by the review-fix pass: WR-06 constructor guard, CR-01 orientation regression), all substantive, none stubbed. |
| `docs/literate/restricted_branch_flow.jl` + `docs/make.jl` + `docs/src/api.md` | Live-executed literate rung page + registration + docstring wiring | ✓ VERIFIED | `julia --project=docs docs/make.jl` exits 0 in this verification session; generated markdown/HTML inspected directly. |
| `.planning/spikes/004-ovr-fallback-multistart/` | Quarantined 5-seed multi-start sweep (D-11) | ✓ VERIFIED | `sweep.jl`, `sweep.csv`, `README.md` (verdict: "VALIDATED — no instability found; all 5 Ipopt convergence-strategy variants agree to ~1e-7") all present; `.planning/spikes/MANIFEST.md` row 004 present. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `RestrictedBranchFlow.contribute!` | `ConvexBranchFlow.contribute!` | delegation (correctness-drift avoidance) | ✓ WIRED | First line of `contribute!`; confirmed by source read. |
| `RestrictedBranchFlow` | `solve_welfare` | `problem_class(::RestrictedBranchFlow) = SOCP()` dispatch trait | ✓ WIRED | Zero `welfare_solve.jl` changes across the whole phase (confirmed: no phase-20 commit touches that file); dispatch confirmed live. |
| `assert_restriction_exact!` | `assert_ac_exact!` | internal call reusing per-hour loop, fresh tolerances | ✓ WIRED | `src/models/restriction_exactness.jl:279`; confirmed no re-implementation of the per-hour loop. |
| `ac_dual_fallback_price` | `solve_welfare(..., ACPowerFlow(), ...)` | seeded-variant re-solve | ✓ WIRED | `src/models/ac_dual_fallback.jl:99-108`; live-executed, all 5 seeds solve and agree. |
| `ac_dual_fallback_price` | `select_optimizer(NLP(); ...)` / `nlp_multistart_variants()` | solver-factory seam (INFRA-02) | ✓ WIRED | `src/solver/factory.jl:103-108`; confirmed no concrete-solver literal in `ac_dual_fallback.jl`. |
| `docs/literate/restricted_branch_flow.jl` | `RestrictedBranchFlow`/`assert_restriction_exact!`/`ac_dual_fallback_price` (documented, not called) | live `@example` execution + prose-only fallback section | ✓ WIRED | Confirmed via live docs build; fallback section correctly does NOT call `ac_dual_fallback_price` (D-09 discipline preserved in the page itself). |

### Data-Flow Trace (Level 4)

Not applicable in the UI-rendering sense (this is a research/optimization library, not a
frontend). The equivalent check — "does every reported number originate from a real solve,
never a hardcoded/pasted literal" — was performed directly: this verifier independently
re-executed the full mechanism (both via a standalone Julia script and via the live
`docs/make.jl` build) and every reported number (`socp_maxgap`, `ac_feasible`,
`matches_ac_optimum`, `optimality_loss`, `ε_measured`, fallback `agreement_report` spreads)
matched the SUMMARYs' claimed values exactly, byte-for-byte on the deterministic ones. No
disconnect between claimed and actual behavior was found.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `RestrictedBranchFlow` closes the SOCP-exactness gap on EXACT-04 | Live `julia --project=.` script (this session) reproducing plan 20-02's/20-05's exact fixture | `socp_maxgap = 2.080395211699962e-8` | ✓ PASS |
| `assert_restriction_exact!` returns the documented (ac_feasible, matches_ac_optimum, optimality_loss) triple | Same script | `(true, false, -1.4325921942337345)` | ✓ PASS |
| Unrestricted `ConvexBranchFlow` context fails the certificate's physical-feasibility gate (synthetic-violation coverage) | Same script | `ac_feasible=false`, `formulation=:unknown` (WR-01 confirmed) | ✓ PASS |
| `ac_dual_fallback_price` 5-seed agreement | Same script, `n_seeds=5` | `price_status=:local_ac_dual`, `max_cost_spread=3.95e-7`, `max_dadp_spread=1.07e-7` | ✓ PASS |
| Negative `ε` rejected at construction | Same script | `ArgumentError` raised | ✓ PASS |
| Full docs build (`julia --project=docs docs/make.jl`) | Live-run this session, background, ~4 min | exit 0, `restricted_branch_flow.md`/`.html` produced, no missing-docs/example-block error | ✓ PASS |
| Module load + all 4 new exported symbols defined | `using TSODSO; isdefined(...)` | true for all 4 | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh`-style probes exist for this phase (not a migration/CLI-tooling
phase); the project's per-task `<verify>` blocks and the `Pkg.test()` full-suite entrypoint
serve this role, per `20-VALIDATION.md`. This verifier substituted equivalent direct
`julia --project=.` and `julia --project=docs docs/make.jl` executions (see Behavioral
Spot-Checks above) rather than accepting SUMMARY.md PASS-marker claims.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|------------|--------------|--------|----------|
| OVR-01 | 20-01, 20-02 | Restricted SOCP dispatched through `solve_welfare` at the EXACT-04 operating point | ✓ SATISFIED | `RestrictedBranchFlow` exists, dispatches by type, closes the cone gap live. |
| OVR-02 | 20-03 | Own validity certificate, AC-feasibility + optimality loss, never a reused tolerance | ✓ SATISFIED | `assert_restriction_exact!` exists, own measured tolerances confirmed absent of copied literals, live-verified verdict. |
| OVR-03 | 20-04 | Convex-dual DADPs + documented nonconvex-AC-dual fallback, report-don't-throw | ✓ SATISFIED | `price_provenance` marker + `ac_dual_fallback_price` with `price_status`/`agreement_report`, D-09 trigger discipline structurally confirmed (no call relationship). |
| OVR-04 | 20-05 | Live-executed literate rung page beside the Gan & Low condition | ✓ SATISFIED | `docs/literate/restricted_branch_flow.jl` live-built this session, all numbers independently reproduced. |

No orphaned requirements: `.planning/REQUIREMENTS.md`'s Traceability table maps exactly
OVR-01..04 to Phase 20, and all four appear in a plan's `requirements:` frontmatter field
(20-01/20-02 → OVR-01, 20-03 → OVR-02, 20-04 → OVR-03, 20-05 → OVR-04). Note: the
Traceability table still lists all four as "Pending" and the requirement bullets as
unchecked (`- [ ]`) — this matches the project's own established pattern (compare
`MESH-04`/`MESH-05` → Phase 19 → "Complete", ticked by the `docs(phase-19): complete phase
execution` commit that ran *after* Phase 19's own verification passed) — i.e., this is the
normal phase-closing bookkeeping step, expected to happen in this phase's own closing commit
after this verification, not a gap in the phase's actual delivered work.

### Anti-Patterns Found

None. Scanned every file this phase touched or the review fixed
(`src/powerflow/RestrictedBranchFlow.jl`, `src/models/restriction_exactness.jl`,
`src/models/ac_dual_fallback.jl`, `src/models/ac_oracle.jl`, `src/solver/factory.jl`,
`test/test_restricted_branch_flow.jl`, `docs/literate/restricted_branch_flow.jl`,
`docs/make.jl`, `docs/src/api.md`, `src/TSODSO.jl`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/
`PLACEHOLDER`/"not yet implemented"/etc. — zero matches. `20-REVIEW.md`'s 1 Critical + 6
Warning findings (CR-01, WR-01..06) are all confirmed FIXED in the current `HEAD` (commits
`6be860b`..`5707073`), independently re-verified by this report (not merely re-reading the
review's own Fix Status table). The review's 5 Info findings (IN-01..05, e.g. the flat
`opfm_shadow_voltage` constraint container, stale plan-comments, unused locals, `qgap`
excluded from `matches_ac_optimum`) remain open — correctly scoped as non-blocking per the
review's own `fix_scope: critical_warning` frontmatter, and none affect the phase's observable
truths.

### Human Verification Required

None. Every claim in this phase is programmatically verifiable (no UI, no external service,
no visual/subjective judgment call) and was independently re-executed by this verifier rather
than accepted from SUMMARY.md text.

### Gaps Summary

No gaps found. All four roadmap success criteria (as amended: Gan-Low OPF-m, not OPF-ε) are
independently, live-verified against the current `HEAD` (`c80463d`), including the
post-review-fix state. The mid-phase OPF-ε → OPF-m escalation (Rule 4, 20-02-SUMMARY) and the
certificate-semantics revision (orchestrator addendum, 20-03-SUMMARY) are both correctly
reflected in the shipped code, not just narrated in the SUMMARYs — this verifier reproduced
the exact numeric verdicts (`socp_maxgap=2.08e-8`, `ac_feasible=true`,
`matches_ac_optimum=false`, `optimality_loss≈-1.4326`) from a cold, independent script run and
from a live `docs/make.jl` build, not by trusting the documentation.

---

*Verified: 2026-08-09T01:55:33Z*
*Verifier: Claude (gsd-verifier)*
