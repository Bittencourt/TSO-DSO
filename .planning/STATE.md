---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: "Plan 08-04 complete — run_and_store (@tagsave provenance: gitcommit+julia_version+seed) + run_sweep/collate_summary (dict_list -> diff-friendly byte-stable CSV) + scripts/run_scenario.jl + scripts/sweep.jl committed (d834ac3, f9eeaf6); four Rule-1 deviations fixed (wload/collect_results String-key round-trip, DrWatson.collect_results precompile race, @tagsave gitpath under Pkg.test()); full Pkg.test() 1922 pass/0 fail/2 pre-existing broken. Phase 08 (experiment-harness-reproducibility) COMPLETE."
last_updated: "2026-07-20T11:24:04.792Z"
last_activity: 2026-07-20 -- Phase 09 execution started
progress:
  total_phases: 9
  completed_phases: 8
  total_plans: 43
  completed_plans: 38
  percent: 88
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-18)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Phase 09 — documentation-regression-acceptance-gate

## Current Position

Phase: 09 (documentation-regression-acceptance-gate) — EXECUTING
Plan: 1 of 5
Status: Executing Phase 09
Last activity: 2026-07-20 -- Phase 09 execution started

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 4
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 08 | 4 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 08 P02 | 35min | 2 tasks | 2 files |
| Phase 08 P03 | 35min | 2 tasks | 2 files |
| Phase 08 P04 | 40min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Abstraction ladder rungs 0-5 map directly to phases; each phase is a runnable/validated end-to-end solve at increasing fidelity (mvp mode).
- Roadmap: Centralized SOCP (Phase 4) is the ground truth ADMM (Phases 6-7) is validated against; pricing (Phase 5) sits between to de-risk duals early.
- Roadmap: `operational_oracle(z)→(cost,π)` seam + SEAM-01 stubs land at the SOCP correctness milestone (Phase 4) so the deferred planning layer is additive, not a rewrite.
- [Phase 08]: Base.@kwdef struct + hand-written positional inner constructor combine cleanly for a validated, keyword-defaulted Scenario (verified in REPL before adopting the pattern).
- [Phase 08]: Scenario price/population valid-selector sets are narrow ({:mem}/{:default} only), matching exactly the build_price/build_population branches materialize.jl implements.
- [Phase 08]: build_population dispatches residential-magnitude scale constants by feeder bus count (123 vs else) since the two shipped feeders sit on drastically different per-unit bases (1 MVA vs 100 MVA).
- [Phase 08]: Scenario's default ADMM rho bumped from 1.0 to 100.0 (matches test_admm.jl's empirically-validated ieee13 penalty) — run_scenario(:admm) end-to-end on the default scenario hit a Clarabel NUMERICAL_ERROR at the too-small starting rho before adaptive-rho could rescue it (Rule 1 bug fix, 08-03)
- [Phase 08]: DrWatson/JLD2 always round-trip dict keys as String (wload never returns Symbol keys) — fixed the INFRA-04 provenance testitem's key-type assertions and collect_results black_list override accordingly (Rule 1, 08-04)
- [Phase 08]: @tagsave's default gitpath=projectdir() resolves to Pkg.test()'s sandbox (not a git repo); run_and_store pins gitpath=pkgdir(@__MODULE__) so :gitcommit is stamped reliably under both plain runs and Pkg.test() (Rule 1, 08-04)

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 4]: ~~Re-verify Clarabel API specifics~~ RESOLVED (Phase-4 research, 2026-07-18): RotatedSecondOrderCone form `[0.5l, v, P, Q] in RotatedSecondOrderCone()`, Clarabel handles SOCP+quadratic natively, `Parameter` API confirmed, Clarabel copy_to-only (no direct_model). No factory change needed.
- [Phase 7]: Adaptive-ρ / dual-residual tuning on the SOCP subproblem is partial-research; may warrant `--research-phase`.
- [Phase 4 follow-up — welfare gap]: The IEEE-13 ground-truth solve reproduces the thesis VOLTAGE well (v₉[16]=1.0436 vs 1.0493, 0.5%; A1 confirmed = |V| magnitude, node 9=struct index 10) but the WELFARE (−4823) differs from the thesis +$1819 because the MEM price / temperature profiles / house-counts are figure-bound (not recoverable from the thesis figures). A COMPUTED GOLDEN is pinned as the regression anchor (accepted by researcher 2026-07-18). TODO (later reconciliation pass): digitize thesis figures ~4.2/4.5 to recover the exact MEM/load/PV inputs and close the welfare gap; then re-pin the golden and tighten the thesis cross-check.
- [Phase 5 follow-up — +25% headline (SAME root cause as above)]: The DLMP extraction, four-way decomposition (KKT identity certified to ~1e-15), the surplus identity (social=prosumer+DSO=objective, rtol 1e-6 lossless / 1e-4 IEEE-13), the FIT baseline, and the economic-direction checks (DADP<λ₀ glut, >λ₀ congestion) all PASS. But the +25% social-welfare headline is NOT quantitatively reproduced: the computed ratio is ≈1.0 (social_DADP=−4821.96 vs social_FIT=−4822.08) because absolute welfare is NEGATIVE in the ¢$/kWh calibration (demand cost dominates utility), so the ratio of two negatives inverts. Dynamic pricing DOES improve welfare directionally (social_DADP > social_FIT). The computed ratio is pinned as the golden; thesis 1.25 is a NON-FAILING broken cross-check. TODO: same figure-digitization pass (recover the thesis's positive-welfare calibration) will restore the +25% quantitative match. Accepted by researcher 2026-07-18 ("flag for follow-up").

- [Phase 7 follow-up — IEEE-123 impedances]: The IEEE-123 fixture (`src/data/ieee123.jl`) ships the canonical IEEE-123 radial TOPOLOGY (123 buses, relabeled, radialized, 85 load / 37 transit) but with REPRESENTATIVE in-band per-unit impedances at a 1 MVA feeder-scale base (a DATA PROVENANCE note is atop the file), NOT the thesis App. E exact per-terminal r/x — those numbers are not vendored in the repo (no thesis PDF; THEORY-thesis.md has only Case-B params). ADMM converges on it in ~17 iters (adaptive ρ, welfare gap 1.2e-6, |λ−DADP|~0.003 pu, PF-04 exact 1e-9, voltage-binding) — the CONVERGENCE & SCALE goal is met. Numerical insight: the SOC exactness robustness hinges on the per-unit base (cone-slack ratio ~1e-7 at 1 MVA vs ~1 at 100 MVA). TODO (Phase-9 regression / later): transcribe the thesis App. E impedance table (or the public IEEE-123 test-feeder data) into the branch table without touching topology/relabel/tests, for a true thesis-numeric IEEE-123 reproduction.

- [Phase 7 deferred manual check — CairoMakie figures]: Phase-7 verification is 3/3 must-haves PASSED; the only open item is a pre-declared VISUAL-ONLY check — the CairoMakie convergence figures (`plot_convergence`, `plot_price_convergence` in `ext/TSODSOMakieExt.jl`). CairoMakie is a `[weakdeps]` NOT installed in the current env, so the runtime Figure render is skipped-with-message and the plot functions are verified structurally only (weakdep-gated, return a Makie Figure). TODO (manual, non-blocking): in a non-headless env, `Pkg.add("CairoMakie")` (or add to the docs env), `using CairoMakie`, call the two plot functions on a solved `AdmmResiduals`, and eyeball the vector PDFs for aesthetics. Advisory polish; does not gate the phase.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 extension | Stochastic PV/demand (STOCH-01/02) | Deferred to future milestone | Roadmap creation |
| v2 extension | MPC / rolling-horizon RTP (MPC-01/02) | Deferred to future milestone | Roadmap creation |
| v2 extension | Meshed networks + 4Q-BESS (MESH-01/02) | Deferred to future milestone | Roadmap creation |
| v2 extension | Stackelberg-Nash planning game (PLAN-01…04) | Deferred to future milestone | Roadmap creation |

## Session Continuity

Last session: 2026-07-20T01:30:52.470Z
Stopped at: Plan 08-04 complete — run_and_store (@tagsave provenance: gitcommit+julia_version+seed) + run_sweep/collate_summary (dict_list -> diff-friendly byte-stable CSV) + scripts/run_scenario.jl + scripts/sweep.jl committed (d834ac3, f9eeaf6); four Rule-1 deviations fixed (wload/collect_results String-key round-trip, DrWatson.collect_results precompile race, @tagsave gitpath under Pkg.test()); full Pkg.test() 1922 pass/0 fail/2 pre-existing broken. Phase 08 (experiment-harness-reproducibility) COMPLETE.
Resume file: None
