---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Research Extension Rungs
status: planning
last_updated: "2026-07-27T00:10:08.401Z"
last_activity: 2026-07-27
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-22)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Milestone complete

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-07-27 — Milestone v3.0 started

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260726-mo7 | Add optimizer kwarg to fit_baseline | 2026-07-26 | c099ee6 | [260726-mo7-add-optimizer-kwarg-to-fit-baseline](./quick/260726-mo7-add-optimizer-kwarg-to-fit-baseline/) |
| 260726-n7l | Correct the refuted sign_flip_survives claim in findings.txt and 18-01-SUMMARY | 2026-07-26 | b251f55 | [260726-n7l-correct-the-refuted-sign-flip-survives-c](./quick/260726-n7l-correct-the-refuted-sign-flip-survives-c/) |
| 260726-plf | Correct the 18-03 assumptions page — Section 8 refuted, Phase-17 re-tune premise undermined | 2026-07-26 | 2ac0089 | [260726-plf-correct-the-18-03-assumptions-page-secti](./quick/260726-plf-correct-the-18-03-assumptions-page-secti/) |
| 260726-pta | Publish the SOCP applicability maps + sweep experiments on the Documenter site | 2026-07-26 | (this commit) | [260726-pta-publish-the-socp-applicability-maps-and-](./quick/260726-pta-publish-the-socp-applicability-maps-and-/) |

## Performance Metrics

**Velocity:**

- Total plans completed: 63 (v1.0: 43, v2.0: 13)
- Average duration: —
- Total execution time: 0 hours (v2.1)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 09 | 5 | - | - |
| 10-14 (v2.0) | 13 | - | - |
| 10 | 2 | - | - |
| 11 | 3 | - | - |
| Phase 12 P02 | 65min | 2 tasks | 2 files |
| 12 | 2 | - | - |
| 13 | 3 | - | - |
| 14 | 3 | - | - |
| 15-18 (v2.1) | TBD | - | - |
| 16 | 4 | - | - |
| 18 | 3 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 18 P01 | 45min | 2 tasks | 2 files |
| Phase 18 P02 | 35min | 2 tasks | 1 files |
| Phase 18 P03 | 55min | 3 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap (v2.1): Phases derived 1:1 from the research SUMMARY.md's dependency-ordered 4-phase
  structure — Phase 15 (AC-exactness oracle) and Phase 16 (reactive-μ consensus) are code-independent
  of each other, sequenced 15-then-16 because Phase 16 is the more invasive change to an
  already-shipped/cross-validated ADMM path and its goldens need re-validation before Phases 17-18
  build on `admm/`.

- Roadmap (v2.1): Phase 17 (real IEEE-123 impedances) is code-independent of Phases 15/16 (touches
  only `scripts/`+`src/data/`) but its *validation* (still voltage-binding? still SOC-exact?)
  benefits from Phase 15's AC oracle and Phase 16's reactive pricing existing — not a hard build
  dependency, a validation-quality one.

- Roadmap (v2.1): Phase 18 (directional thesis reproduction) is the only phase with a genuine
  hard dependency — strictly depends on Phase 16 (reactive pricing) + Phase 17 (real impedances)
  both landing, since the thesis's voltage-driven Case B result is not credible on synthetic
  impedances or without priced reactive power.

- Roadmap (v2.1): Phase 16's success criteria lead with the `mu` naming-collision resolution
  (reactive dual vs. the existing adaptive-ρ `mu::Real=10.0` in `Scenario`'s golden-hash schema) as
  its own criterion, per research SUMMARY.md's "first design decision" flag — must be resolved
  before any `AgrOpt`/`DsoOpt` code change.

- Roadmap (v2.1): Phase 15's design explicitly ALLOWS a genuine high-PV/reverse-flow inexactness
  finding as a first-class documented result (per-hour/per-branch gap table, never a single
  pass/fail) — not something to tolerance-adjust away.

- Roadmap (v2.0): Phase 10 splits PLAN-01/02/03 (oracle-coupling wiring + retry/checkpoint
  resilience) out as its own phase BEFORE the full Benders loop, proven before Benders depends on it.

- Roadmap (v2.0): Phase 11 carries the BilevelJuMP leader/follower certification gate (PLAN-07,
  PVAL-01) alongside the Benders master/follower work (PLAN-04/05/06) — gate stays in the phase
  that assigns leader/follower roles, per research SUMMARY.md.

- Roadmap (v2.0): Phase 12 (cut-store/master hardening) intentionally owns no new requirement
  IDs — it deepens PLAN-05/PLAN-06 at scale before Phase 13 nests a second (Nash) outer loop.

- Roadmap (v2.0): `src/planning/coupling.jl` (NASH-01) is sequenced at Phase 13, not earlier — a
  genuinely new shared-transmission model that only becomes necessary once distributors need
  something shared to iterate on.

- Roadmap (v2.0): Phases 11 and 13 flagged for `--research-phase` (BilevelJuMP mode API +
  leader/follower resolution; Gauss-Seidel diagonalization convergence + coupling.jl design).

- [Phase 12]: Plan 02 load-test fixture raised T from 1 to 8 (Claude's Discretion over fixture shape, 12-CONTEXT.md): the literal T=1 fixture's Benders gap floors at a fixed numerical point after 16 iterations regardless of tol, never reaching >=50 genuinely-converging iterations.
- [Phase 12]: Plan 02: alpha_op_lb loosened from -5.0 to -50.0 for the T=8 load-test fixture -- a correctness requirement at that scale (verified against a hand-derived closed form z*=1.4, cost=-7.84), not merely a convergence-speed tweak.
- [Phase 18, CORRECTED 2026-07-26]: ~~RECOMMENDED BAND derived from only the exact retuned point; the +/-2%/+/-5% sweep points all fail the SOCP-exactness gate outright (sign_flip_survives=false), so the sign flip is NOT confirmed population-scale-robust.~~ REFUTED: those failures were solver under-convergence at the default tol_gap=1e-8. At 1e-10 all 5 points solve and ALL show the sign flip, both surpluses monotone. The band still passes (max|dso|=4.807417 < 5.5886) but its own `1.5 x max|dso|` rule now implies 7.211. See the Phase 18 blocker below.
- [Phase 18]: REPRO-01 gate-then-golden test pins the DSO-surplus sign flip + magnitude band (DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937), never the aggregate welfare ratio, band sourced verbatim from Plan 18-01's committed findings.txt
- [Phase 18]: Plan 03: every reproduction number carries the "directional, public-data" qualifier via a per-file cite_repro(x) helper (executed code only, never inside Literate prose comments); the aggregate welfare ratio is never computed as the primary claim (Pitfall 1).
- [Phase 18]: Plan 03: the assumptions page states plainly that the thesis's +25% welfare-ratio magnitude does not transfer to real public IEEE-123 data (measured ~+0.045%), while the DSO-surplus sign flip is the robust signal. **[CORRECTED 2026-07-26]** The page no longer carries Plan 18-01's `sign_flip_survives=false` finding — Section 8 was rewritten to "Yes, at all five swept points" (quick task 260726-plf). The +25%-does-not-transfer statement is UNAFFECTED and still correct.

### Pending Todos

None yet.

### Blockers/Concerns

- [v2.1 Phase 16 research flag]: whether reactive consensus needs its own `rho_q` or can share the
  active block's `rho` for joint (p,q) residual balancing is an open judgment call (MEDIUM
  confidence per research SUMMARY.md ARCHITECTURE) — resolve empirically during Phase 16, not by
  assumption.

- [v2.1 Phase 15 research flag]: the angle-recovery formula for the AC oracle on a radial network
  (SOCP is magnitude-only; AC oracle needs real voltage phasors) is genuinely new math for this
  codebase — validate on a trivial 2-bus fixture before trusting it on IEEE-13/123.

- [v2.1 Phase 17 research flag]: PMD `ENGINEERING` dict traversal specifics (`eng["line"]`/
  `eng["linecode"]` field shapes, `Redirect`/`Compile` directive following) and the classic
  feet-vs-miles IEEE-123 OpenDSS unit trap were verified against docs, not a live parse — verify by
  actually running the parse early in Phase 17.

- [v2.1 Phase 17 unresolved]: whether the real-impedance IEEE-123 case remains voltage-binding after
  the impedance swap is unverified (no real impedance data exists yet) — Phase 17's acceptance
  criteria must include an explicit binding-constraint check and be prepared to re-tune the
  aggregator/PV population if the property doesn't transfer.

- [v2.0 Phase 10 target]: CI-flaky, version-independent, intermittent Clarabel `NUMERICAL_ERROR`
  on the IEEE-13 ADMM solve (root cause: cone-slack numerical sensitivity, per-unit-base
  dependent; never fixed in v1.0) is expected to be AMPLIFIED once the oracle is re-solved inside
  a Benders × scenario × distributor × diagonalization nest. PLAN-03 (Phase 10) makes bounded
  retry + checkpointing a day-one co-requirement; measure empirical failure rate on the planning
  layer's own fixtures, don't assume v1's rate holds. v2.1 Phase 16 must also re-measure this
  flake's rate under Q-consensus rather than assuming v1.0's rate transfers.

- [v2.0 Phase 12 measured]: the Phase-10 blocker above was measured, not assumed, in this
  phase's load test (`test/test_planning_hardening.jl`) — `solve_with_retry!` escalated 0
  time(s) across 66 Benders iterations on the planning-layer toy fixture (a 0% escalation
  rate), sourced from `BendersTrace.retry_count_trace` (plan 12-01's `attempts_out` mechanism)
  and cross-checked exactly against an independently captured `@warn` count from the same run;
  the run converged without ever exhausting the 4-rung retry budget or losing a checkpoint. The
  default `max_attempts=4` budget appears sufficient at this scale — the toy fixture's tiny
  per-period LPs never hit Clarabel's/HiGHS's numerical-conditioning edge cases at T=8, so no
  empirical evidence yet exists to justify tuning the retry budget; the amplification concern
  the Phase-10 blocker names is specifically about the IEEE-13 ADMM oracle's cone-slack
  sensitivity, which this toy-fixture load test intentionally does not exercise (CONTEXT.md's
  explicit prohibition on using the full SOCP oracle here) — re-measure on a real feeder-scale
  planning fixture if/when one is introduced.

- [v2.0, no general guarantee]: Gauss-Seidel Nash diagonalization (Phase 13) has no general
  uniqueness/convergence guarantee — every reported equilibrium must carry a multi-seed/
  multi-order probe (NASH-04); never present one run as "the" equilibrium.

- [v2.0, source ambiguity]: The PSR N1-N2 note is self-flagged MEDIUM confidence and internally
  inconsistent on leader/follower labeling and integer-cut correctness. Phase 11's BilevelJuMP
  certification gate (PLAN-07) resolves this empirically — do not re-resolve by re-reading
  THEORY-papers.md.

- [carried from v1.0]: thesis welfare-headline figure digitization and `sub_seed` cross-version
  hash stability remain deferred, unaffected by v2.1 scope; IEEE-123 exact App. E impedances is now
  ACTIVE as v2.1 Phase 17 (real public-data impedances, not App. E — see PROJECT.md v2.1 Key
  context). See `milestones/v1.0-MILESTONE-AUDIT.md`.

- [v2.1 Phase 18 REFUTED — corrections owed]: the recorded `sign_flip_survives: false` is **wrong**.
  Spikes 002/003 plus quick task 260726-mo7 showed the ±2-5% "population-scale fragility" was a
  solver-tolerance artifact: `assert_socp_exact!`'s `atol = 1e-6` sits at Clarabel's achievable cone
  residual on the 122-branch IEEE-123 feeder at the default `tol_gap = 1e-8`. At `tol_gap = 1e-10`
  the sweep solves **5/5** and the DSO-surplus sign flip holds at **every** point, with both
  surpluses monotone (`dadp_dso` 2.71→4.81, `fit_dso` −183→−210). Two of the four recorded failures
  were also **misattributed** — they were `fit_baseline`, not `solve_welfare`, because
  `scripts/repro_stability_check.jl` wraps three solves in one try/catch.
  **Corrections:** (1) ✅ DONE `results/repro_stability_check/findings.txt` — `!!! CORRECTION` banner
  prepended (quick task 260726-n7l); NOTE the file is **generated** by
  `scripts/repro_stability_check.jl:343`, so the banner is lost on any re-run until (5) lands;
  (2) ✅ DONE `milestones/v2.1-phases/18-directional-thesis-reproduction/18-01-SUMMARY.md` — banner +
  8 inline annotations + `## Correction` section; (3) ✅ DONE the published 18-03 assumptions page
  (`docs/literate/thesis_reproduction_assumptions.jl` + regenerated `.md`) — Section 8 rewritten to
  "Yes, at all five swept points" (quick task 260726-plf); (4) ⬜ OWED Plan 18-02's golden band — its `1.5 × max|dso|` rule now implies **7.211** vs
  the pinned **5.5886** (`test_thesis_repro.jl` passes — verified 6/6 under the pinned env — but rule
  and value disagree); (5) ⬜ OWED split `repro_stability_check.jl`'s try/catch per stage and thread
  the new `optimizer` kwarg. Evidence: `.planning/spikes/003-phase18-fragility-tolerance/`.

- [v2.1 Phase 17 premise REFUTED 2026-07-26]: the page-documented justification for the Phase-17
  population re-tune (`0.03/0.06/0.05 -> 0.05/0.12/0.0833`) — that the original synthetic-impedance
  triple "broke solve_welfare's SOCP-exactness gate outright on the real network, worst gap ratio
  1.378 > 1" — is a **solver-tolerance artifact**. Tested directly: the original triple on the REAL
  feeder throws at default `tol_gap=1e-8` (ratio 1.3781586234547918) and **PASSES at 1e-10**
  (`socp_maxgap=1.673e-08`, `vpeak=1.00198`, `dso=+0.662750` — still positive). The re-tune was NOT
  necessary for exactness. The re-tuned point remains valid and nothing downstream is wrong; but
  Sections 5/7 of the assumptions page (the "asymmetric achievable regime / upper band limited by
  inexactness" rationale) rest on the same default-tolerance evidence and are now flagged
  *evidence undermined, needs re-measurement at tight tolerance*. Phase 17's full search space was NOT
  re-swept — the lower-band bind (`vmin≈0.9487`) is real physics and unaffected. **OWED: re-measure
  Phase 17's population-scale search at tight tolerance.**

- [test-invocation hazard, cost a misdiagnosis 2026-07-26]: **never run the suite via
  `julia --project=test -e '... @run_package_tests ...'`.** Two distinct problems, both real:
  **(a) sibling-worktree contamination (this is what bites).** In a `-e` string there is no real
  `__source__.file`, so TestItemRunner resolves the package/test root via cwd and its
  `joinpath(…,"..")` walk picks up
  `/home/pedro/programming/TSO-DSO.worktrees/pdf-documentation-thesis-results/`, whose fixtures carry
  the pre-Phase-17-retune `LOAD_SCALE_IEEE123 = 0.03`. That yields a spurious REPRO-01
  `assert_socp_exact!` failure at gap ratio **1.378** / gap 1.54e-6. **Filtering `ti.filename` on
  `.worktrees` does NOT help** — the item reports under the *main* path because the contamination is in
  setup-module/fixture resolution. Reproduced bit-for-bit against a clean env.
  **(b) `Pkg.develop(path=".")` mutates the PINNED test env** (rewrote `test/Manifest.toml` 1232 lines

  + `test/Project.toml` 14 lines). Separate bug; did NOT cause (a).
  **Use `julia --project=. -e 'import Pkg; Pkg.test()'`** — real `test/runtests.jl` entrypoint, immune
  to the walk, temp env from the pinned manifest, mutates nothing. Verified good state:
  **2358 pass / 1 fail / 3 broken**, the single failure being the known-false Aqua CairoMakie
  stale-deps from the root `Project.toml` drift.
  ⚠️ The 1.378 ratio is in the SAME band as the genuine noise-floor artifacts above (1.10–4.76) — two
  unrelated defects with indistinguishable symptoms. "The number looks like noise" is not a diagnosis.

- [measurement hygiene, project-wide]: residual-based classification must be calibrated against the
  **solver noise floor per feeder**. The WR-01 `atol + rtol·magnitude` idiom scales with quantity
  magnitude but NOT with solver accuracy, and accuracy degrades with problem size. On IEEE-123 at
  default tolerance this produced a **48% false-positive** inexactness rate
  (`.planning/spikes/002-ieee123-validity-map/`). A cone-gap ratio near 1 is not evidence — the
  3-bus structural gaps were 1e3-1e4.

## Deferred Items

Items acknowledged and carried forward, now refined by v2.1 REQUIREMENTS.md:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2.x+ extension | Stochastic PV/demand (`PLAN-STOCH-01`) | Deferred to future milestone | v2.0 requirements definition |
| v2.x+ extension | MPC / rolling-horizon RTP | Deferred to future milestone | Roadmap creation (v1.0) |
| v2.x+ extension | Meshed networks + 4Q-BESS | Deferred to future milestone | Roadmap creation (v1.0) |
| v2.x+ extension | Integer/discrete investment (`PLAN-INT-01`) | Deferred — v2.0 continuous-only, enforced by PVAL-04 | v2.0 requirements definition |
| v2.x+ extension | Real-data flexibility-aggregator valuation (`PLAN-RT-01`) | Deferred to future milestone | v2.0 requirements definition |
| v2.x+ extension | MCP/VI recast (`PLAN-MCP-01`) | Deferred — only if diagonalization proves unreliable | v2.0 requirements definition |
| v2.1+ extension | Exact-figure thesis reproduction (`REPRO-STRETCH-01`) | Deferred — contingent on IP-blocked thesis Appendix E | v2.1 requirements definition |
| v2.1+ extension | Live cross-subproblem reactive dual-ascent loop (4Q-BESS/volt-var) | Deferred alongside meshed+4Q-BESS | v2.1 requirements definition |

## Session Continuity

Last session: 2026-07-26T23:23:40.597Z
Stopped at: Phase 18 complete -- all 3 plans (18-01, 18-02, 18-03) executed; v2.1 Validation & Reproduction milestone target features all delivered.
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
