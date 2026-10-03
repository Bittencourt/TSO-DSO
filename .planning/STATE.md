---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Correctness & Depth
status: verifying
stopped_at: Phase 31 verified (UAT 5/5, suite 31260/0/0/5); next is Phase 32 — `/gsd-autonomous --from 32`
last_updated: "2026-10-03T19:32:16.590Z"
last_activity: 2026-10-03
progress:
  total_phases: 12
  completed_phases: 7
  total_plans: 58
  completed_plans: 59
  percent: 58
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-22)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Phase 32 — Declarative Power-Flow & Strategy Dispatch

## Current Position

Phase: 32 (Declarative Power-Flow & Strategy Dispatch) — EXECUTING
Plan: 7 of 7
Status: Phase complete — ready for verification
  (`31-UAT.md`); review cap reached with 0 critical / 0 warning / 2 info open (`31-REVIEW.md`).
  Next: Phase 32. `/gsd-secure-phase` not run for Phases 29–31 (security enforcement default-on).
Last activity: 2026-10-03

### Carry-over backlog — ALL CLOSED 2026-08-26 (see Quick Tasks table)

- B1 — repo-wide soft-scope sweep (grep the suite for Julia's own
  "Assignment to X in soft scope is ambiguous" warning; 2 instances of this class found so far)

- B2 — audit remaining solver-derived goldens pinned at default `≈` tolerance, and add a
  formatter content-loss guard to the CI format job (see below)

- ~~C3 — retire/repair `test/fixtures_retry.jl`~~ **CLOSED 2026-08-26 by quick task 260825-w5a**:
  deleted the module and unwrapped all three call sites; measured on Julia 1.10 (a genuinely
  failing toolchain) in a clean detached worktree that the production `solve_with_retry!` ladder
  alone rescues all three (30154 pass / 0 fail / 0 error, 13 production-ladder escalations fired
  and rescued).

- C4 — knife-edge canary: assert IEEE-13 ADMM converges with recorded iters/welfare, so a
  future codegen-level flip is attributable to a commit instead of surfacing as a mystery flake

- NEW — `test/Manifest.toml` resolves only on Julia 1.12 (PrecompileTools `StaticData`
  UndefVarError on 1.10/1.11), so there is no working local path to the test suite on the
  declared 1.10 compat floor

### Standing hazard — JuliaFormatter docstring data loss

JuliaFormatter 2.10.2 with `format_docstrings = true` SILENTLY DELETES text when an inline code
span wraps a line and the continuation line begins with `|` (CommonMark reads it as a table
row). Cost 148 characters of `src/models/restriction_exactness.jl`'s docstring before it was
caught. `format_docstrings` is deliberately kept `true`, so the hazard is live for any future
docstring using wrapped absolute-value notation. Detector:
`python3 <scratchpad>/check_content_loss.py <git-ref>` — compares every tracked .jl file
ignoring whitespace and commas. Promoting it into the CI format job is task B2.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260726-mo7 | Add optimizer kwarg to fit_baseline | 2026-07-26 | c099ee6 | [260726-mo7-add-optimizer-kwarg-to-fit-baseline](./quick/260726-mo7-add-optimizer-kwarg-to-fit-baseline/) |
| 260726-n7l | Correct the refuted sign_flip_survives claim in findings.txt and 18-01-SUMMARY | 2026-07-26 | b251f55 | [260726-n7l-correct-the-refuted-sign-flip-survives-c](./quick/260726-n7l-correct-the-refuted-sign-flip-survives-c/) |
| 260726-plf | Correct the 18-03 assumptions page — Section 8 refuted, Phase-17 re-tune premise undermined | 2026-07-26 | 2ac0089 | [260726-plf-correct-the-18-03-assumptions-page-secti](./quick/260726-plf-correct-the-18-03-assumptions-page-secti/) |
| 260726-pta | Publish the SOCP applicability maps + sweep experiments on the Documenter site | 2026-07-26 | (this commit) | [260726-pta-publish-the-socp-applicability-maps-and-](./quick/260726-pta-publish-the-socp-applicability-maps-and-/) |
| 260726-vn2 | Quarantine flaky IEEE-13 ADMM tests with a bounded solve retry | 2026-07-27 | e015529 | [260726-vn2-quarantine-flaky-ieee-13-admm-tests-with](./quick/260726-vn2-quarantine-flaky-ieee-13-admm-tests-with/) |
| 260728-co0 | Author the Stackelberg vs PSR N1-N2 note term-by-term mapping writeup | 2026-07-28 | 6b8b166 | [260728-co0-create-a-typst-writeup-like-thesis-casea](./quick/260728-co0-create-a-typst-writeup-like-thesis-casea/) |
| 260728-fast | Fix scrambled table rendering in stackelberg_vs_psr_n1n2.typ (auto-width Etiqueta column collapsed the fr columns to zero width) | 2026-07-28 | — | — |
| 260806-ujj | Showcase example app: PV-boom case study (scripts/pv_boom_case_study.jl) + self-contained HTML report (scripts/pv_boom_report.jl) | 2026-08-07 | 96688aa | [260806-ujj-showcase-example-app-pv-boom-case-study-](./quick/260806-ujj-showcase-example-app-pv-boom-case-study-/) |
| 260807-7nz | Rewrite PV-boom HTML report as rich educational walkthrough (MathML equations, model/experiment/results narrative) | 2026-08-07 | 7d41053 | [260807-7nz-rewrite-pv-boom-html-report-as-rich-educ](./quick/260807-7nz-rewrite-pv-boom-html-report-as-rich-educ/) |
| 260807-bv8 | PV-boom report v2 (scripts/pv_boom_report_v2.jl): review-hardened — source citations, provenance tags, notation table, SVG architecture diagram, limitations section; v1 kept byte-identical | 2026-08-07 | f7487fa | [260807-bv8-pv-boom-report-v2-review-hardened-educat](./quick/260807-bv8-pv-boom-report-v2-review-hardened-educat/) |
| 260822-f0b | Phase-25 follow-up — clarabel-tol flag, ADMM exactness-gate override seam, harness time-limit raise | 2026-08-22 | 8673cc1 | [260822-f0b-phase-25-followup-clarabel-tol-flag-admm](./quick/260822-f0b-phase-25-followup-clarabel-tol-flag-admm/) |
| 260822-hld | Thread the ADMM exactness atol seam into the harness + point-appropriate noise-floor calibration | 2026-08-23 | b1e42ef | [260822-hld-phase-25-round2-thread-admm-exactness-at](./quick/260822-hld-phase-25-round2-thread-admm-exactness-at/) |
| 260822-oi7 | Per-branch SOCP cone-residual diagnostic — pin the IEEE-8500 inexactness mechanism (verdict: STRUCTURAL) | 2026-08-23 | 55c5d39 | [260822-oi7-pin-ieee-8500-socp-inexactness-mechanism](./quick/260822-oi7-pin-ieee-8500-socp-inexactness-mechanism/) |
| 260822-pxb | Zero-length bus-merge reduction replacing impedance fabrication (3 merges) | 2026-08-23 | eeabcbe | [260822-pxb-ieee-8500-zero-length-bus-merge-replacin](./quick/260822-pxb-ieee-8500-zero-length-bus-merge-replacin/) |
| 260822-rle | Widen bus-merge threshold to sub-metre (6 more merges) — SOCP exactness recovered on all 3 points | 2026-08-23 | 8e804f7 | [260822-rle-widen-ieee-8500-bus-merge-threshold-to-s](./quick/260822-rle-widen-ieee-8500-bus-merge-threshold-to-s/) |
| 260822-tyf | Typst academic report: IEEE-8500 SOCP-exactness investigation (pt-BR) | 2026-08-23 | f360b50 | [260822-tyf-typst-academic-report-ieee-8500-socp-exa](./quick/260822-tyf-typst-academic-report-ieee-8500-socp-exa/) |
| 260823-gea | Phase-18 owed corrections — per-stage try/catch + optimizer kwarg in repro_stability_check.jl (item 5 CLOSED); golden-band re-derivation left OPEN, fit_baseline hits ALMOST_OPTIMAL at 3/5 points | 2026-08-23 | 56f007f | [260823-gea-close-the-two-owed-v2-1-phase-18-correct](./quick/260823-gea-close-the-two-owed-v2-1-phase-18-correct/) |
| 260824-vct | Fix Julia soft-scope bug in test_stochastic_welfare.jl's D-06 PF-04 gate scan (let-wrapped scan state; verified gate trips at pv_scale=2.0, 2/2 consecutive runs, 0 soft-scope warnings) | 2026-08-24 | d8e8999 | [260824-vct-fix-julia-soft-scope-bug-in-test-stochas](./quick/260824-vct-fix-julia-soft-scope-bug-in-test-stochas/) |
| 260825-w5a | Retire the no-op AdmmRetryFixtures test-level retry wrapper (deleted test/fixtures_retry.jl, unwrapped all 3 call sites, measured on Julia 1.10 that the production solve_with_retry! ladder alone rescues all 3) | 2026-08-26 | 5725f7f | [260825-w5a-retire-or-repair-the-no-op-admmretryfixt](./quick/260825-w5a-retire-or-repair-the-no-op-admmretryfixt/) |
| 260829-jzz | Fix CI red after f44ada4 — restore CairoMakie weakdep + revert Manifest-v1.12 (kills 1.10/1.11 buildpkg manifest error AND 1.12 Aqua stale-deps/persistent-tasks failures; verified locally on all three Julia versions) | 2026-08-29 | bed47c6 | [260829-jzz-fix-ci-restore-cairomakie-weakdep-and-re](./quick/260829-jzz-fix-ci-restore-cairomakie-weakdep-and-re/) |

## Deferred Items

Acknowledged at the v3.0 milestone close (2026-08-24). Recorded accurately rather than as
blanket "deferred work" — most of what `audit-open` flagged is not open work at all:

| Category | Item | Reality |
|----------|------|---------|
| quick_task | 16 tasks, all reported `status: missing` | **NOT open work.** All 16 have committed SUMMARY.md files and appear in the Quick Tasks Completed table above with commit hashes. `audit-open` flags them only because this repo's quick-task SUMMARY frontmatter carries `quick_id`/`subsystem`/`tags`/dependency-graph fields but no `status:` field, which the audit expects. A frontmatter-convention gap in the tooling contract, not unfinished work. Worth fixing in the template rather than in 16 files. |
| verification_gap | Phase 25 `25-VERIFICATION.md` status `gaps_found` | **Accurate and deliberately left as-is.** SCALE-04 was closed 2026-08-24 (see `25-SCALE-04-CLOSURE.md`), but SCALE-05 genuinely remains: the ~40x headline IEEE-8500 fixture was OOM-killed at every density, so solve time / ADMM iterations / exactness at headline scale were never measured. The researcher ACCEPTED this as an honest non-measurement at milestone close. The status field is not being edited to look clean — the gap is real, it is simply accepted. |

Genuinely open, carried past v3.0 (not blocking the close):

All three items below are now IN SCOPE for v4.0 (no longer deferred):

- **SCALE-STRETCH** -> ARCH-10, Phase 35 (IEEE-8500 Scale After Refactor).
- **Phase-18 `fit_baseline` convergence** -> FIX-09, Phase 27 (Integer Planning & Pricing
  Certificate Correctness).

- **MESH-06 advisory** -> ARCH-06, Phase 34 (ADMM Decomposition, Meshed Reactive & Status/
  Exception Policy).

Still genuinely open past v4.0: the large-lattice integer termination criterion (no rigorous
`δ_min` derivable) — see ROADMAP.md Deferred / Future-Milestone Notes.

## Performance Metrics

**Velocity:**

- Total plans completed: 143 (v1.0: 43, v2.0: 13, v2.1: 14)
- Average duration: —
- Total execution time: 0 hours (v3.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1-9 (v1.0) | 43 | - | - |
| 10-14 (v2.0) | 13 | - | - |
| 15-18 (v2.1) | 14 | - | - |
| 19. 4Q-BESS + Live Reactive Dual-Ascent | TBD | - | - |
| 20. Overvoltage-Capable Relaxation | TBD | - | - |
| 21. MPC / Rolling-Horizon / RTP | TBD | - | - |
| 22. Stochastic PV/Demand Uncertainty | TBD | - | - |
| 23. Meshed Networks | TBD | - | - |
| 24. Discrete/Integer Investment Expansion | TBD | - | - |
| 25 (v3.0) | 8 | - | - |
| 26. Network & Device Model Correctness (v4.0) | TBD | - | - |
| 27. Integer Planning & Pricing Certificate Correctness (v4.0) | TBD | - | - |
| 28. Goldens Re-Derivation & Thesis Reproduction Restatement (v4.0) | TBD | - | - |
| 29. Genuine Bilevel TSO-DSO Variant (v4.0) | TBD | - | - |
| 30. SOCP-in-the-Loop Benders on a Multi-Bus Feeder (v4.0) | TBD | - | - |
| 31. GNE Nash Fixture, Integer N>1 & Planning Docs Refresh (v4.0) | TBD | - | - |
| 32. Declarative Power-Flow & Strategy Dispatch (v4.0) | TBD | - | - |
| 33. Shared Abstractions — Feeder, Balance, Model Context (v4.0) | TBD | - | - |
| 34. ADMM Decomposition, Meshed Reactive & Status/Exception Policy (v4.0) | TBD | - | - |
| 35. IEEE-8500 Scale After Refactor (v4.0) | TBD | - | - |
| 36. Code & Export Cleanup (v4.0) | TBD | - | - |
| 37. Test Infrastructure & Repo Hygiene (v4.0) | TBD | - | - |
| 19 | 8 | - | - |
| 20 | 5 | - | - |
| 21 | 6 | - | - |
| 22 | 5 | - | - |
| 23 | 4 | - | - |
| 260824-vc0 | Pin JuliaFormatter to 2.10 in the CI format-check job | 2026-08-25 | d369f5c | [260824-vc0-pin-juliaformatter-to-2-10-in-ci-workflo](./quick/260824-vc0-pin-juliaformatter-to-2-10-in-ci-workflo/) |
| 260824-vct | Fix Julia soft-scope bug in the D-06 PF-04 gate scan | 2026-08-25 | d8e8999 | [260824-vct-fix-julia-soft-scope-bug-in-test-stochas](./quick/260824-vct-fix-julia-soft-scope-bug-in-test-stochas/) |
| 260824-vdh | Give the D-11 welfare_gap golden a measured rtol=1e-4 | 2026-08-25 | ff8f71f | [260824-vdh-give-the-d-11-run-stochastic-welfare-gap](./quick/260824-vdh-give-the-d-11-run-stochastic-welfare-gap/) |
| 260824-vxn | Reformat 48 drifted files to pinned JuliaFormatter 2.10.2 (+ docstring rewrap) | 2026-08-25 | 0debac9 | [260824-vxn-reformat-48-drifted-files-under-pinned-j](./quick/260824-vxn-reformat-48-drifted-files-under-pinned-j/) |
| 260825-eme | Reset DSO-OPT conditioning ladder before the final solve (published solve runs at as-built baseline) | 2026-08-25 | d099821 | [260825-eme-reset-ladder-attributes-before-the-final](./quick/260825-eme-reset-ladder-attributes-before-the-final/) |
| 260825-w58 | Add formatter content-loss guard to the CI format job (if: always()) | 2026-08-26 | 3ba4b6f | [260825-w58-add-formatter-content-loss-guard-to-the-](./quick/260825-w58-add-formatter-content-loss-guard-to-the-/) |
| 260825-w5a | Retire the no-op AdmmRetryFixtures test-level retry wrapper (3 call sites) | 2026-08-26 | 5725f7f | [260825-w5a-retire-or-repair-the-no-op-admmretryfixt](./quick/260825-w5a-retire-or-repair-the-no-op-admmretryfixt/) |
| 260826-0y4 | Fix the vacuous `caught` soft-scope gate in INT-03; record detection method | 2026-08-26 | 79c1107 | [260826-0y4-fix-vacuous-caught-assertion-soft-scope-](./quick/260826-0y4-fix-vacuous-caught-assertion-soft-scope-/) |
| 260825-w5b | Add IEEE-13 ADMM knife-edge canary (pinned iters/welfare, ladder reported) | 2026-08-26 | 2648dfb | [260825-w5b-add-ieee-13-admm-knife-edge-canary-test](./quick/260825-w5b-add-ieee-13-admm-knife-edge-canary-test/) |
| 260826-8gb | Document the ADMM conditioning ladder + knife-edge and the CI docs-integrity guard in the Documenter site | 2026-08-26 | 362e745 | [260826-8gb-document-the-admm-conditioning-ladder-an](./quick/260826-8gb-document-the-admm-conditioning-ladder-an/) |
| 260826-cjh | Replace the fragile `iters >= 50` load-test bound with an intent-shaped structural floor (measured spread 47-66) | 2026-08-26 | c2b95a6 | [260826-cjh-replace-the-fragile-iters-50-bound-in-th](./quick/260826-cjh-replace-the-fragile-iters-50-bound-in-th/) |
| 26 | 20 | - | - |
| 27 | 9 | - | - |
| 28 | 6 | - | - |
| 29 | 4 | - | - |
| 30 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 29 P01 | 25min | 2 tasks | 5 files |
| Phase 29 P02 | 25min | 2 tasks | 2 files |
| Phase 29 P04 | 33min | 2 tasks | 1 files |
| Phase 29 P03 | 90min | 2 tasks | 2 files |
| Phase 30 P01 | 55min | 3 tasks | 6 files |
| Phase 30 P02 | 75min | 3 tasks | 5 files |
| Phase 30 P04 | 95min | 3 tasks | 5 files |
| Phase 30 P05 | 50min | 2 tasks | 2 files |
| Phase 30 P06 | 15min | 2 tasks | 1 files |
| Phase 31 P01 | 100min | 1 tasks | 2 files |
| Phase 31 P04 | 95min | 2 tasks | 3 files |
| Phase 31 P05 | 20min | 2 tasks | 8 files |
| Phase 31 P06 | 35min | 2 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Quick task 260728-co0: found and documented that `THEORY-papers.md`'s N1/N2-to-side paraphrase
  was reversed relative to the PSR primary source (correct reading: N1 = transmission, N2 =
  distributor) — the primary PDF and the `src/planning/` implementation are mutually consistent;
  only the digest's introductory prose had the labels backwards. Documented in
  `docs/writeups/stackelberg_vs_psr_n1n2.typ`'s game-structure section rather than silently
  picking a reading.

- Roadmap (v3.0): Phases derived from the 5 research axes but the MESH axis is SPLIT across two
  phases per the flagged PROJECT.md interdependency — Phase 19 ships 4Q-BESS device + live reactive
  dual-ascent (MESH-04/05, dependency-free, lowest risk) first; Phase 23 ships the meshed topology/
  formulation/certificate (MESH-01/02/03) plus the combined literate page (MESH-06) later, after
  Phase 20 (Overvoltage) establishes the reusable restriction/certificate pattern it reuses.

- Roadmap (v3.0): Phase 20 (Overvoltage) is sequenced before Phase 21 (MPC) — not just before Phase 23
  — because a rolling-horizon window can legitimately drift into the same high-PV overvoltage regime;
  resolving Phase 20 first gives MPC a defined fallback instead of an undefined catch-and-continue.

- Roadmap (v3.0): MPC (Phase 21) and Stochastic (Phase 22) are kept as two separate, tightly
  sequenced phases (not merged into one) per the "fine" granularity setting — but their identical
  `Scenario.jl` schema-extension blast radius means both axes' schema diffs should land as one
  coordinated, tightly-reviewed pair rather than two independently-reviewed changes to the same
  schema-fragile, golden-hash-bearing file.

- Roadmap (v3.0): Phase 24 (Integer investment expansion) is sequenced last — structurally
  independent of Phases 19-23 (touches only `src/planning/`) but carries the highest algorithmic
  risk in the milestone (integer-cut correctness, weaker Laporte-Louveaux convergence theory);
  ordering it last keeps the other four validated rungs unblocked while its correctness concerns
  are resolved. Its correctness argument depends on the v2.0 continuous Benders baseline
  (PVAL-02..04 goldens) staying stable to diff against.

- Roadmap (v3.0): All 22 v3.0 REQ-IDs mapped 1:1 to exactly one of Phases 19-24 — full coverage,
  no orphans. See REQUIREMENTS.md Traceability table.

- Roadmap (v2.1): Phases derived 1:1 from the research SUMMARY.md's dependency-ordered 4-phase
  structure — Phase 15 (AC-exactness oracle) and Phase 16 (reactive-μ consensus) are code-independent
  of each other, sequenced 15-then-16 because Phase 16 is the more invasive change to an
  already-shipped/cross-validated ADMM path and its goldens need re-validation before Phases 17-18
  build on `admm/`.

- Roadmap (v2.1): Phase 18 (directional thesis reproduction) is the only phase with a genuine
  hard dependency — strictly depends on Phase 16 (reactive pricing) + Phase 17 (real impedances)
  both landing, since the thesis's voltage-driven Case B result is not credible on synthetic
  impedances or without priced reactive power.

- [Phase 29]: Measured SOS1 bounds must include both named-constraint duals AND variable-bound reduced costs -- the research's illustrative probe (named-constraint duals only) silently underestimates on a fixture whose follower optimum is a degenerate corner at both probe extremes
- [Phase 29]: Phase 29 P02: BILEV_GAP_FLOOR derived as 10x the production MILP's measured mip_feasibility_tolerance=1e-9 (never as a fraction of the observed bilevel-vs-joint gap); stacked JULIA_LOAD_PATH="test:.:@stdlib" verification idiom resolves both main-env TSODSO and test-only BilevelJuMP/Ipopt without Pkg.develop mutation
- [Phase 29]: Phase 29 P04 (BILEV-02 BLOCKER-1): closed the fixture-adequacy gap with a second, non-degenerate (q_op=1.0) interior certification fixture in test/test_planning_certification_bilevel_interior.jl, self-contained (no edits to test/fixtures_planning.jl); GAP_FLOOR_INTERIOR/Z_GAP_FLOOR_INTERIOR set to 1e-6 (looser than plan 29-02's 1e-8) from this fixture's own measured cross-solver (HiGHS-MILP-KKT vs Clarabel-QP) residual ~3.7e-5
- [Phase 29]: P03 (phase close): audit_goldens.py scoped --base to the recorded Phase-28 close commit (3d4beb0), isolating exactly what Phase 29 changed; zero flagged golden moves across the whole phase at both pre-review (990b51c) and post-review (a5e9900) HEADs
- [Phase 29]: P03 close: full suite certified 30871/0/0/5 (+168 over Phase-28's 30703/0/0/5, fully attributed: +166 bilevel test files incl. a 3-iteration code-review hardening cycle, +2 PVAL-04 build_bilevel_kkt registration); zero goldens re-pinned, zero worktree contamination
- [Phase 30-01]: Feasibility-cut gradient sign empirically re-derived as u=+dual.(pin) (un-negated), opposite convention from solve_planning_oracle!'s own pi -- verified against the full measured feasible/infeasible map on ieee13_modified()
- [Phase 30-01]: Voltage-infeasible fixture uses a thermally-widened (smax=90) IEEE-13 variant with an ample-battery population, not the unmodified feeder -- thermal always binds first as z grows on the real feeder
- [Phase 30]: ALPHA_LB_MARGIN=ALPHA_LB_REJECTION_TOL=1e-6, measured on the toy two-bus/ToyElasticDevice fixture at T=1 — Single shared probe sufficient: oracle gap ~2.85e-9, follower gap 0.0; max(1e-6,10*gap) dominated by the floor
- [Phase 30]: Repo-wide T>1 alpha-bound audit (test/ and src/) found no previously-unknown invalid bound — Only T>1 site is test_planning_hardening.jl's T=8 fixture (alpha_op_lb=-50.0), already fixed in-repo and accepted by the new derivation formula
- [Phase 30]: Phase 30-04: genuine-infeasibility routing (BILEV-04a) is unconditional regardless of inexact_policy; only the exactness-class throw is policy-dispatched
- [Phase 30]: Phase 30-04: :reject's deterministic stall confirmed empirically (no cut appended on a rejected trial => identical master LP re-proposes the same trial forever) -- accepted per T-30-09, not engineered around
- [Phase 30]: Phase 30-04: W2 overhead measured -- derive_alpha_op_lb ~13.1ms vs ~695.5ms full solve_stackelberg! best-response (~1.9%) on the toy two-bus fixture, now paid unconditionally through every solve_stackelberg!/run_nash! best-response; carried to Phase 31 FINDINGS
- [Phase 30]: Extended the BILEV-03 cross-check tolerance formula to a THIRD source (Benders loop's own converged |UB-LB| absolute gap) beyond the two solver-precision duality gaps the plan named — found necessary by direct measurement (the two-source formula fails the cross-check by ~53x).
- [Phase 30]: T=24 Literate IEEE-13 demonstration tightens follower/master investment-ceiling kwargs vs the T=4 headline test, after a live probe found the T=4-scale kwargs throw a genuine assert_battery_complementarity! violation under the full 24-hour price swing.
- [Phase 30]: Phase 30-06: golden-audit base corrected to the TRUE Phase-29 close commit e5dc782 (not the plan's own flawed tail-1-grep result 990b51c, an intermediate Phase-29 commit) -- exit 0, zero flagged moves, re-confirmed after the post-handoff code review
- [Phase 30]: Phase 30 certified complete: 31091 pass / 0 fail / 0 error / 5 broken (+220 over Phase-29 baseline, zero new broken); 3-iteration code review left 3 open Laporte-Louveaux integer-recourse warnings (unconfirmed ALMOST_INFEASIBLE handling, unenforced Q_nu>=L cut precondition, unwidened convergence certificate under accepted bound slack), carried forward as Phase 31/BILEV-07 input
- [Phase 31-01]: WR-01 (confirmed ALMOST_INFEASIBLE via feas_oracle) fixed and committed (986aa4b); WR-03 (widen convergence certificate by _accepted_lb_slack) NOT implemented — the plan's directed fix (30-REVIEW.md Option B) breaks pre-existing pinned Benders goldens (test_planning_benders.jl flagship N=1 case) because build_master's WR-05 lb_slack (~2e-6) already exceeds the project's standard tol=1e-6 for ANY explicit-bound solve_stackelberg! call, not just near-the-edge bounds; reverted rather than move a golden or touch master.jl (Option A's fix) outside this plan's file scope -- recommended as follow-up (candidate 31-02)
- [Phase 31-04]: run_nash! integer kwarg: fresh build_master_integer per best response via solve_stackelberg!'s master= keyword; exact-binary-state Dict cycle detection (never tolerance); found+fixed a Rule-1 bug in solve_follower!(::DistributorView) -- a confirmed MOI.INFEASIBLE without a Farkas ray was previously an unrecoverable error, now returns feasible=false (v=NaN,u=NaN) since corner_recourse's own ternary search only reads .feasible
- [Phase 31]: 31-05 docs refresh: integer-extension deviation documented as two independent axes (target variable y_inv/N2 vs x_inv/N1; mechanism Laporte-Louveaux vs Lagrangian relaxation)
- [Phase 31]: User force-added (git add -f) the two refreshed writeup PDFs despite the project-wide .gitignore convention (track .typ source, regenerate PDF); .gitignore itself left untouched
- [Phase 31]: 31-06 (phase close): golden-move audit exit 0 (base 36e3c1e); consolidated 31-FINDINGS.md; orchestrator certified full suite 31190/0/0/5 (+99 over Phase-30, zero regressions, zero new broken); post-certification code review found 2 OPEN critical findings (CR-01 integer cycle-detection false positive, CR-02 vacuous VE selection on the shipped interior-cap fixture) -- user stopped autonomous mode before a fix round, so phase is test-certified but explicitly NOT marked verified

### Roadmap Evolution

- Roadmap (v4.0) added 2026-09-28: 12 phases (26-37), continuing numbering from v3.0's Phase 25.
  All 37 v4.0 REQ-IDs (FIX-01..11, BILEV-01..08, ARCH-01..10, HYG-01..08) mapped 1:1 to exactly one
  phase — full coverage, no orphans. See REQUIREMENTS.md Traceability table.

  Sequencing (user-approved): Correctness -> Planning depth -> Architecture -> Hygiene.

  - FIX-01 (thesis 3.43 verdict) precedes FIX-02 within Phase 26; FIX-11 (goldens/repro
    restatement) is its own capstone Phase 28, strictly after all other FIX items land.

  - FIX-06 (integer LL T>1 fix) sits in Phase 27 with the pricing/certificate fixes — a
    planning-code fix kept in the correctness track because it must precede BILEV-07 (Phase 31).

  - BILEV-03/04/05 (Phase 30) depend on the corrected network model (FIX-01..03, Phase 26).
    BILEV-01/02 (Phase 29, genuine bilevel) is sequenced before Phase 30 as a distinct concern.
    BILEV-08 (docs refresh) closes out Phase 31, the last planning-depth phase.

  - ARCH-01/02 (Phase 32) is one coherent declarative-Scenario phase. ARCH-05 precedes ARCH-06
    within Phase 34 (solve_admm split before meshed+live-reactive composition). ARCH-10
    (Phase 35) runs after all architecture refactors (Phases 32-34).

  - HYG-01..03/07 (Phase 36, code/export cleanup) is sequenced after every refactor phase so
    comment/dead-code cleanup isn't redone; HYG-04..06/08 (Phase 37, test infra & repo hygiene)
    is kept as a separate phase per the user's split.

  - Absorbed into v4.0 (removed from ROADMAP.md's Deferred notes): SCALE-STRETCH -> ARCH-10,
    Phase-18 `fit_baseline` convergence -> FIX-09, MESH-06 composition -> ARCH-06, integer N>1
    Nash -> BILEV-07.

- Phase 25 added 2026-08-20: IEEE-8500 Scale Benchmark. Requirements SCALE-01..05 added to
  REQUIREMENTS.md (v3.0 now 27 requirements, all mapped). User-chosen scope: scalability benchmark
  (not a pricing case study), **full MV + LV secondary** (not MV-only), landed as a v3.0 phase.
  Structurally independent of Phase 24 — either order, or parallel.

  Scoping already done at add time (feed this to /gsd-discuss-phase 25, do not re-derive):

  - Source data is public and available: `dss-extensions/electricdss-tst`,
    `Version8/Distrib/IEEETestCases/8500-Node/`. The feeder ships its own **balanced load case**
    `Master.dss`, which matches the standing balanced-positive-sequence project scope — no
    unbalanced-to-balanced conversion needed.

  - `Master.dss` redirects `LoadXfmrCodes.dss` and comments out `LoadXfmrs.dss` because
    `LoadXfmrCodes.dss` contains BOTH the 9 XfmrCodes AND all 1177 service-transformer instances.
    The balanced case is fully connected: MV `L*` -> center-tap service xfmr -> `X*` LV -> triplex
    -> `SX*` load bus. Do not conclude the secondaries are disconnected.

  - Inventory: ~2526 MV line records, 1177 triplex secondaries, 1177 balanced loads (0.208 kV,
    pf 0.97), 1177 service transformers (9 XfmrCode sizes, 5-100 kVA, Xhl~2.04%, %Rs=[0.6 1.2 1.2]),
    4 capacitor banks (3x300 + 400 + 900 kvar), 3 single-phase FEEDER_REG regulators + substation
    115/12.47 kV transformer. Impedances are Ohm matrices in `LineCodes2.DSS` (units=km) —
    Fortescue-reducible by the same method as `scripts/reduce_ieee123_impedances.jl`.

  - "8500-node" counts per-phase nodes. After positive-sequence collapse expect **~4.9k buses**, not
    8500. Same IN-02 naming caveat already carried by `ieee13.jl`/`ieee123.jl`.
  - Two known scope risks, both load-bearing for the plan: (a) **no shunt/capacitor support exists
    anywhere in `src/`** — the 4 cap banks need fixed-Q injection or a documented omission;
    (b) **`IMPEDANCE_PU_MAX = 5.0`** (`src/units/PerUnit.jl:58`) will be crowded — a 5 kVA service
    transformer at Xhl=2.04% is ~4.1 pu on a 1 MVA base before %Rs, while 0.001 km MV stubs sit at
    ~1e-5 pu. That ~6-orders-of-magnitude spread, not raw bus count, is the suspected conditioning
    wall, which makes the `S_base` choice a real decision rather than a formality.

  - `Feeder`/`Branch` store per-unit only, so multi-voltage-base ingestion needs no core struct
    change — just the right `PerUnitBase` per voltage level at ingestion time.

### Pending Todos

None yet.

### Blockers/Concerns

- [v4.0 Phase 31 — RESOLVED 2026-10-03, `31-FINDINGS.md` "Post-review fix cycle" / `31-REVIEW.md`]:
  the two critical findings that blocked verification are fixed — CR-01 integer cycle detection now
  keys on the full committed state (binaries + (z, x_inv) within ω·tol_outer/2) and requires a
  strictly non-decreasing residual (live damped ω=0.5 run converges; sign-flipping −0.9 history not
  flagged); CR-02 VE non-uniqueness on the symmetric fixture documented (VE = whole split segment,
  GNE set strictly larger incl. free-riding equilibria) plus a new asymmetric fixture
  (`c_inv=[1.0,1.4]`) with a unique hand-derived VE `x_inv=(0.7,0)`, `z=(0.7,0.7)`. WR-01..WR-06
  fixed. Open (info only): docstring/writeup precision — "residual strictly decreases" holds for
  potential games only; free-riding range should read `p ∈ [0, 0.5)`; the writeup's "não ciclam"
  sentence omits the ties caveat. Human full read of the two writeup PDFs still pending.

- [v4.0 Phase 28 restatement — `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md`]:
  every golden moved in Phases 26–27 is attributed (audit script: 13 attributed / 1 allowlisted / 0
  unattributed). REPRO-01 DSO-surplus sign flip STILL reproduces; fit_dso ≈−196.22→≈−286.11;
  aggregate welfare gap ≈+0.045%→≈+0.263% (thesis +25% magnitude still NOT reproduced); stability
  flake 13/20→1/20, sign-flip survival 2/5→5/5 (v2.1 "knife-edge-fragile" no longer holds).
  EXACT-04: gate-1 (cone) exact under both copies; gate-2 (AC dispatch) inexact under default
  (restriction suboptimality), exact under thesis_literal. Default NOT unconditionally cone-exact
  (3/150 high-PV sweep points). MPC: 3/19 settled hours genuinely overload thermally.

- [v4.0 Phase 27 findings — full text in `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`]:
  (1) Exactness gate is now a HYBRID per-branch floor `atol_b = max(τ_solver=2e-7, ε·ref_b)`, ε=1e-9
  (pure relative floor was infeasible: WR-01 needs ε<5e-8, IEEE-13 ground ≳5e-5). Margins only ~2.4x;
  IEEE-8500 NOT swept — re-measure in Phase 35. At DEFAULT Clarabel tol_gap the gate's detectability
  floor is solver precision (~1e-6): several fixtures now carry measured tighter tol_gap.
  (2) Fixed-dispatch SOCP re-solves (MPC truth import, FIT SITE-2 AC-PF) are STRUCTURALLY inexact (loss
  current free; gap 211 on REPRO-01, 18/20 MPC seeds). Both now settle via AC power flow, PHYSICS ONLY
  (`ACPowerFlow(; limits=false)`), limit violations reported as diagnostics. Realized MPC dispatch under
  5% forecast error genuinely overloads the IEEE-13 head branch (seed=1).
  (3) FIT SITE-3 `ALMOST_OPTIMAL` at tol_gap=1e-10 is a genuine Clarabel conditioning wall (max_iter
  refuted); bounded by measured `FIT_SITE3_ALMOST_GAP_TOL`. Repro population point's SOCP exactness has
  drifted since Phase 18 — Phase 28 must re-check.
  (4) corner_recourse T>1 is a joint Kelley cutting-plane (T=1 byte-identical); pre-existing
  `solve_follower!`/HiGHS certificate-loss fragility logged (F-27-01-2), unscheduled.
  (5) Phase 28 restatement items: MPC realized_welfare/regret semantics changed (docs/literate/
  mpc_rolling_horizon.jl, scripts/demo_mpc_plots.jl); DLMP `loss`/`voltage` → `cone`/`drop` (aliases
  until Phase 36).

- [v4.0 Phase 26 findings — full text in `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md`]:
  (1) The corrected `ConvexBranchFlow` default (Gan–Low copy, v̂ ≥ v) is Gan–Low's *modified* OPF —
  a conservative RESTRICTION on the upper voltage band, exact by theorem (EXACT-04: SOCP −921.754 vs
  AC −921.277, ≈0.05%); the old `thesis_literal=true` copy restricts the LOWER band. Neither is a
  genuine relaxation. The thesis's own eq. 3.43 algebra contradicts its adjacent redundancy claim.
  (2) The v2.1 "SOCP knife-edge under high-PV reverse flow" finding no longer reproduces under the
  default; it still reproduces under `thesis_literal=true` (escalation tests re-forced that way).
  (3) App. C battery: with η < 1 simultaneous charge/discharge is NOT strictly dominated
  ((λ_med − DLMP)(1 − η²) > 0) — affects every PVBattery result; AC oracle now reports instead of
  throwing. BACKLOG (unscheduled): proper complementarity treatment / η-aware re-parametrisation.
  (4) Uniform mesh diamond loses cone exactness once loads draw reactive power (pf 0.95); fixture
  pinned φ = 1.0. (5) Headline goldens moved (IEEE-13 h16 DADP 1.402→0.394, |V₉[16]| 1.0436→1.0360
  farther from thesis, FIT ratio 0.643→0.772, exporter surplus 65.6→47.4) — see
  `26-GOLDEN-AUDIT.md`; restate in Phase 28.

- [v3.0 Phase 23 research flag — RESOLVED 2026-08-10]: `.planning/phases/23-meshed-networks/23-RESEARCH.md`
  resolves the non-radial formulation question: `ConvexBranchFlow`'s existing KCL/v-drop/cone
  constraints are ALREADY graph-generic (verified by direct code read, `src/powerflow/ConvexBranchFlow.jl`) —
  `MeshedFlow` delegates to them near-verbatim (no bus-injection/loop-constraint reformulation
  needed); explicit "cycle/loop consistency" (MESH-02) is realized as the NEW a-posteriori
  angle-recoverability certificate (MESH-03), never a hard convex constraint (angle closure is a
  nonconvex trig identity, cannot be a JuMP constraint on angle-eliminated branch-flow variables —
  matches Farivar-Low's own BFM treatment). The fixture question is also resolved: a live Julia/
  Clarabel spike this session shows a clean, 3-order-of-magnitude separation between a
  uniform-R/X-ratio loop (angle-recoverable, residual ~1e-5) and a heterogeneous-R/X-ratio loop
  (structurally unrecoverable, residual ~1e-3 to 6e-3) on the SAME small topology — the committed
  fixture should toggle impedance profile to exercise BOTH certificate branches (Pitfall 15
  respected: no knife-edge sweep, a qualitative topology choice).

- [v3.0 Phase 24 research flag]: whether standard Benders optimality cuts remain valid at the chosen
  binary-expansion granularity, and whether BilevelJuMP's KKT/SOS1/Fortuny-Amat modes support any
  mixed-integer follower at all, are both open questions the research explicitly could not resolve
  without implementation-time verification — check HiGHS/BilevelJuMP docs directly at Phase 24 start;
  fall back to brute-force enumeration for small-instance validation if BilevelJuMP's modes don't apply.

- [v3.0 Phase 22 flag]: no empirical measurement yet exists of Clarabel's scenario-count ceiling on
  the stochastic extensive form — must be established on IEEE-13/123 fixtures before scaling scenario
  count (Pitfall 11).

- [v3.0 cross-cutting standing bar]: every new mathematical regime in this milestone gets its OWN new
  certificate/gate — never a reused tolerance ("certificate laundering" is the dominant risk flagged
  across Phases 19/20/23/24 in research PITFALLS.md). Byte-identical default paths when new flags are
  off; gate-then-golden ordering; measurement-before-golden for any pinned economic/numeric band;
  honest-finding-as-deliverable if a genuine negative result surfaces.

- [v2.1 Phase 17 unresolved]: whether the real-impedance IEEE-123 case remains voltage-binding after
  the impedance swap is unverified (no real impedance data exists yet) — Phase 17's acceptance
  criteria must include an explicit binding-constraint check and be prepared to re-tune the
  aggregator/PV population if the property doesn't transfer.

- [v2.0 Phase 10 target]: CI-flaky, version-independent, intermittent Clarabel `NUMERICAL_ERROR`
  on the IEEE-13 ADMM solve (root cause: cone-slack numerical sensitivity, per-unit-base
  dependent; never fixed in v1.0) is expected to be AMPLIFIED once new outer loops (rolling-horizon,
  extensive-form scenarios, meshed SOCP) re-solve it repeatedly. Re-measure empirically per phase,
  don't assume prior milestones' rates hold.

- [v2.0, no general guarantee]: Gauss-Seidel Nash diagonalization (Phase 13) has no general
  uniqueness/convergence guarantee — every reported equilibrium must carry a multi-seed/
  multi-order probe (NASH-04); never present one run as "the" equilibrium.

- [carried from v1.0]: thesis welfare-headline figure digitization and `sub_seed` cross-version
  hash stability remain deferred, unaffected by v3.0 scope. See `milestones/v1.0-MILESTONE-AUDIT.md`.

- [v2.1 Phase 18 REFUTED — corrections owed]: the recorded `sign_flip_survives: false` is **wrong**.
  Spikes 002/003 plus quick task 260726-mo7 showed the ±2-5% "population-scale fragility" was a
  solver-tolerance artifact: `assert_socp_exact!`'s `atol = 1e-6` sits at Clarabel's achievable cone
  residual on the 122-branch IEEE-123 feeder at the default `tol_gap = 1e-8`. At `tol_gap = 1e-10`
  `solve_welfare`'s SOCP-exactness gate resolves **5/5** — but see (4): the FULL sign-flip
  confirmation does **not** hold at every point, so the original "5/5 everywhere" wording was
  too strong.
  **Outstanding corrections:** (4) ✅ CLOSED by quick task 260823-gea — golden band re-derived
  and re-pinned: `DSO_BAND_HI` **5.58855710237937 → 7.211125525764296**. The band rule
  `1.5 × max|dso|` ranges over `dso` (from `solve_welfare` + `welfare_accounting`), NOT over
  `fit_baseline`, which yields only `fit_dso` for the sign-flip check. `repro_stability_check.jl`
  had conflated the two — gating the band on all-three-stages success AND discarding `acct.dso`
  as NaN on any `fit_baseline` throw. Both fixed; `dso` is trustworthy at **5/5** swept points
  (2/5 clear all three stages), so the fixed script's own `RECOMMENDED BAND:` line now reads
  `1.5 × 4.807417 = 7.211125525764296`. Numerically the long-flagged "7.211", but reached by
  this decoupling argument rather than the refuted "sweep solves 5/5 everywhere" assumption it
  was originally projected from. Band widens; `DSO_BAND_LO = 0.0` and every other assertion
  unchanged; pinned point `|dso| = 3.7257` inside both old and new bands, so no verdict moves.
  (5) ✅ split `repro_stability_check.jl`'s try/catch per stage and thread the new `optimizer`
  kwarg — DONE by 260823-gea (commit `f913dbb`).
  **Still live (NOT part of items 4/5):** `fit_baseline`'s nested solve does not converge at
  `tol_gap=1e-10` — discrete flake rate **13/20 = 0.650**, all 13 at that stage, 0 at
  `solve_welfare`/`welfare_accounting`, reproduced across 3 runs; `sign_flip_survives: false`,
  with only 2/5 points fully confirming the flip. This is a solver-convergence issue distinct
  from SOCP inexactness and wants its own follow-up.
  Evidence: `.planning/spikes/003-phase18-fragility-tolerance/`,
  `.planning/quick/260823-gea-*/`, `results/repro_stability_check/findings.txt`.

- [v2.1 Phase 17 premise REFUTED 2026-07-26]: the page-documented justification for the Phase-17
  population re-tune is a solver-tolerance artifact (passes at `tol_gap=1e-10` without the re-tune).
  The re-tuned point remains valid; OWED: re-measure Phase 17's population-scale search at tight
  tolerance if that page is revisited.

- [test-invocation hazard, cost a misdiagnosis 2026-07-26]: **never run the suite via
  `julia --project=test -e '... @run_package_tests ...'`** — sibling-worktree contamination via cwd
  resolution, plus `Pkg.develop(path=".")` mutating the pinned test env. **Use
  `julia --project=. -e 'import Pkg; Pkg.test()'`** instead — the real `test/runtests.jl` entrypoint,
  immune to the walk, mutates nothing. Verified good state: 2358 pass / 1 fail / 3 broken (the known
  Aqua CairoMakie stale-deps drift).

- [measurement hygiene, project-wide]: residual-based classification must be calibrated against the
  **solver noise floor per feeder**. On IEEE-123 at default tolerance this produced a **48%
  false-positive** inexactness rate (`.planning/spikes/002-ieee123-validity-map/`). A cone-gap ratio
  near 1 is not evidence — genuine structural gaps were 1e3-1e4.

- [RESOLVED by 31-07, Option A build-time clamp] [Phase 31 plan 01] WR-03 convergence-certificate widening (30-REVIEW.md Option B, _accepted_lb_slack) breaks pre-existing pinned Benders goldens at the project's standard tol=1e-6 -- build_master's WR-05 lb_slack is nonzero (~2e-6) for ANY explicit-bound solve_stackelberg! call since Phase 30's unconditional bounds_ctx wiring, not just near-the-edge bounds. Measured on test_planning_benders.jl's flagship N=1 golden + test_planning_alpha_bounds_stackelberg.jl; very likely affects test_planning_goldens.jl/test_planning_nash.jl/test_planning_certification.jl/test_planning_noninteger.jl too (same fixture pattern, not individually re-run). Reverted, not committed. WR-01 (same plan) IS fixed and committed. Recommended: Option A (build-time clamp in master.jl, out of this plan's file scope) in a follow-up plan (candidate 31-02).

## Deferred Items

Items acknowledged and carried forward:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v3.0 stretch | Convex-hull/QC tightening for overvoltage (`OVR-STRETCH`) | Deferred past Phase 20 | v3.0 requirements definition |
| v3.0 stretch | Economic-MPC terminal value function / robust-tube MPC (`MPC-STRETCH`) | Deferred past Phase 21 | v3.0 requirements definition |
| v3.0 stretch | Formal scenario reduction, SAA/DRO/chance-constraints (`STOCH-STRETCH`) | Deferred past Phase 22 | v3.0 requirements definition |
| v3.0 stretch | QC/SDP tightening, phase-shifter convexification for meshed (`MESH-STRETCH`) | Deferred past Phase 23 | v3.0 requirements definition |
| v2.1+ extension | Exact-figure thesis reproduction (`REPRO-STRETCH-01`) | Deferred — contingent on IP-blocked thesis Appendix E | v2.1 requirements definition |

*(Removed from this table 2026-09-28: `INT-STRETCH` integer Nash diagonalization is now in scope as BILEV-07, v4.0 Phase 31.)*

## Session Continuity

Last session: 2026-10-03T18:22:59.625Z
Stopped at: Phase 31 verified (UAT 5/5, suite 31260/0/0/5); next is Phase 32 — `/gsd-autonomous --from 32`
Resume file: None

## Operator Next Steps

- Review the v4.0 ROADMAP draft; once approved, run `/gsd:plan-phase 26` to plan the first phase
  (Network & Device Model Correctness — FIX-01..05).
