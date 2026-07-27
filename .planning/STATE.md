---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Research Extension Rungs
status: planning
last_updated: "2026-07-27T00:40:20.000Z"
last_activity: 2026-07-27
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-22)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Phase 19 — 4Q-BESS + Live Reactive Dual-Ascent

## Current Position

Phase: 19 of 24 (4Q-BESS + Live Reactive Dual-Ascent)
Plan: — of TBD in current phase
Status: Ready to plan
Last activity: 2026-07-27 — ROADMAP.md created (Phases 19-24), all 22 v3.0 requirements mapped, REQUIREMENTS.md traceability updated

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260726-mo7 | Add optimizer kwarg to fit_baseline | 2026-07-26 | c099ee6 | [260726-mo7-add-optimizer-kwarg-to-fit-baseline](./quick/260726-mo7-add-optimizer-kwarg-to-fit-baseline/) |
| 260726-n7l | Correct the refuted sign_flip_survives claim in findings.txt and 18-01-SUMMARY | 2026-07-26 | b251f55 | [260726-n7l-correct-the-refuted-sign-flip-survives-c](./quick/260726-n7l-correct-the-refuted-sign-flip-survives-c/) |
| 260726-plf | Correct the 18-03 assumptions page — Section 8 refuted, Phase-17 re-tune premise undermined | 2026-07-26 | 2ac0089 | [260726-plf-correct-the-18-03-assumptions-page-secti](./quick/260726-plf-correct-the-18-03-assumptions-page-secti/) |
| 260726-pta | Publish the SOCP applicability maps + sweep experiments on the Documenter site | 2026-07-26 | (this commit) | [260726-pta-publish-the-socp-applicability-maps-and-](./quick/260726-pta-publish-the-socp-applicability-maps-and-/) |

## Performance Metrics

**Velocity:**

- Total plans completed: 70 (v1.0: 43, v2.0: 13, v2.1: 14)
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

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

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

- [v3.0 Phase 20 research flag]: the actual convexification mechanism (tightened SOC restriction vs.
  McCormick valid inequalities vs. PSD-style tightening) is unresolved model-math, not an architecture
  question — flagged in research SUMMARY.md as needing its own theory research pass before planning
  constraints.
- [v3.0 Phase 23 research flag]: the non-radial branch-flow formulation (signed incidence over a
  cycle basis, or bus-injection/line-flow with loop constraints) is new model-math with the same
  "needs its own research pass" flag; also unresolved whether the meshed test fixture will show a
  structural gap requiring an "honest gap" deliverable instead of an exact relaxation (Pitfall 15:
  don't mistake a structural gap for a tunable knife-edge).
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

Last session: 2026-07-27T00:40:20.000Z
Stopped at: ROADMAP.md created for v3.0 (Phases 19-24), all 22 requirements mapped 1:1 with 100% coverage validated; REQUIREMENTS.md traceability updated; STATE.md refreshed.
Resume file: None

## Operator Next Steps

- Review the ROADMAP draft; once approved, run `/gsd:plan-phase 19` to plan the first v3.0 phase (4Q-BESS + Live Reactive Dual-Ascent).
