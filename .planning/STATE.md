---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Awaiting next milestone
stopped_at: Plan 09-05 complete — docs CI job wired (dedicated job, docs-env instantiate, single pinned Julia 1.11), deploydocs repo-slug checkpoint resolved (placeholder kept per researcher decision). Phase 09 closed — all 5 plans complete.
last_updated: "2026-07-20T23:59:17.316Z"
last_activity: 2026-07-20 — Milestone v1.0 completed and archived
progress:
  total_phases: 9
  completed_phases: 9
  total_plans: 43
  completed_plans: 43
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-18)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Milestone complete

## Current Position

Phase: Milestone v1.0 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-07-20 — Milestone v1.0 completed and archived

## Performance Metrics

**Velocity:**

- Total plans completed: 9
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 08 | 4 | - | - |
| 09 | 5 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 08 P02 | 35min | 2 tasks | 2 files |
| Phase 08 P03 | 35min | 2 tasks | 2 files |
| Phase 08 P04 | 40min | 2 tasks | 5 files |
| Phase 09 P04 | 35min | 2 tasks | 6 files |
| Phase 09 P05 | 15min | 2 tasks | 2 files |

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
- [Phase 09]: Removed pricing_dlmp.jl's unused using JuMP import rather than adding JuMP to docs/Project.toml — no JuMP symbol was actually referenced (Rule 1 fix, 09-04)
- [Phase 09]: docs/Project.toml hard-depends on CairoMakie (0.15) for docs-only figure rendering, guarded per-page with Base.find_package; root Project.toml weakdeps/extensions untouched (09-04)
- [Phase 09]: docs CI job pinned to single Julia 1.11 (mirrors format job), not added as a 1.10/1.11/1.12 matrix leg — docs content is Julia-version-invariant (09-05)
- [Phase 09]: deploydocs repo-slug placeholder kept as-is per researcher decision on the Task 2 human-verify checkpoint (no git remote in this checkout); comment now documents it as a resolved decision with a pre-deploy TODO (09-05)

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

Last session: 2026-07-20T22:03:10.700Z
Stopped at: Plan 09-05 complete — docs CI job wired (dedicated job, docs-env instantiate, single pinned Julia 1.11), deploydocs repo-slug checkpoint resolved (placeholder kept per researcher decision). Phase 09 closed — all 5 plans complete.
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
