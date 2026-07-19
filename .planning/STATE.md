---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Plan 08-01 committed (b23c2d9) + summary written; experiment-harness foundation done, RED harness green-able by waves 08-02..04
last_updated: "2026-07-19T23:45:00.000Z"
last_activity: 2026-07-19 -- Plan 08-01 complete (foundation + RED harness); stale worktree removed
progress:
  total_phases: 9
  completed_phases: 7
  total_plans: 38
  completed_plans: 35
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-18)

**Core value:** A researcher expresses a scenario and model variant declaratively, runs it end-to-end with an open-source solver, and gets trustworthy, reproducible results and prices — every assumption documented, every layer swappable.
**Current focus:** Phase 08 — experiment-harness-reproducibility

## Current Position

Phase: 08 (experiment-harness-reproducibility) — EXECUTING
Plan: 1 of 4 COMPLETE — next: 08-02 (Scenario + materialize)
Status: Executing Phase 08
Last activity: 2026-07-19 -- Plan 08-01 complete (foundation + RED harness); stale worktree removed

Progress: [███░░░░░░░] 25%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Abstraction ladder rungs 0-5 map directly to phases; each phase is a runnable/validated end-to-end solve at increasing fidelity (mvp mode).
- Roadmap: Centralized SOCP (Phase 4) is the ground truth ADMM (Phases 6-7) is validated against; pricing (Phase 5) sits between to de-risk duals early.
- Roadmap: `operational_oracle(z)→(cost,π)` seam + SEAM-01 stubs land at the SOCP correctness milestone (Phase 4) so the deferred planning layer is additive, not a rewrite.

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

Last session: 2026-07-19
Stopped at: Plan 08-01 complete — foundation (DrWatson/CSV/DataFrames deps, re-resolved manifests, two-tier storage) + include-graph stubs + RED @testitem harness committed (639baa2, b23c2d9); 08-01-SUMMARY written; stale agent worktree removed. Next: execute 08-02 (Scenario + materialize).
Resume file: None
