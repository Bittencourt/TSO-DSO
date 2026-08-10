---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Research Extension Rungs
status: ready_to_plan
stopped_at: Phase 22 complete (5/5) — ready to discuss Phase 23
last_updated: 2026-08-10T07:07:43.300Z
last_activity: 2026-08-10 -- Phase 22 execution started
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 24
  completed_plans: 24
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-22)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Phase 23 — meshed networks

## Current Position

Phase: 23
Plan: Not started
Status: Ready to plan
Last activity: 2026-08-10

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

## Performance Metrics

**Velocity:**

- Total plans completed: 94 (v1.0: 43, v2.0: 13, v2.1: 14)
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
| 19 | 8 | - | - |
| 20 | 5 | - | - |
| 21 | 6 | - | - |
| 22 | 5 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

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

### Pending Todos

None yet.

### Blockers/Concerns

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
  the sweep solves **5/5** and the DSO-surplus sign flip holds at **every** point.
  **Outstanding corrections:** (4) ⬜ OWED Plan 18-02's golden band — its `1.5 × max|dso|` rule now
  implies **7.211** vs the pinned **5.5886** (test still passes, but rule and value disagree);
  (5) ⬜ OWED split `repro_stability_check.jl`'s try/catch per stage and thread the new `optimizer`
  kwarg. Evidence: `.planning/spikes/003-phase18-fragility-tolerance/`.

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

## Deferred Items

Items acknowledged and carried forward:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v3.0 stretch | Convex-hull/QC tightening for overvoltage (`OVR-STRETCH`) | Deferred past Phase 20 | v3.0 requirements definition |
| v3.0 stretch | Economic-MPC terminal value function / robust-tube MPC (`MPC-STRETCH`) | Deferred past Phase 21 | v3.0 requirements definition |
| v3.0 stretch | Formal scenario reduction, SAA/DRO/chance-constraints (`STOCH-STRETCH`) | Deferred past Phase 22 | v3.0 requirements definition |
| v3.0 stretch | QC/SDP tightening, phase-shifter convexification for meshed (`MESH-STRETCH`) | Deferred past Phase 23 | v3.0 requirements definition |
| v3.0 stretch | Integer Nash diagonalization (`INT-STRETCH`) | Deferred past Phase 24 | v3.0 requirements definition |
| v2.1+ extension | Exact-figure thesis reproduction (`REPRO-STRETCH-01`) | Deferred — contingent on IP-blocked thesis Appendix E | v2.1 requirements definition |

## Session Continuity

Last session: 2026-08-08T01:07:28.428Z
Stopped at: Phase 19 context gathered
Resume file: .planning/phases/19-4q-bess-live-reactive-dual-ascent/19-CONTEXT.md

## Operator Next Steps

- Review the ROADMAP draft; once approved, run `/gsd:plan-phase 19` to plan the first v3.0 phase (4Q-BESS + Live Reactive Dual-Ascent).
