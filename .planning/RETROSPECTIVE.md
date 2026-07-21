# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Operational Transactive-Energy Core

**Shipped:** 2026-07-20
**Phases:** 9 | **Plans:** 43 | **Tasks:** 83

### What Was Built
- The full operational transactive-energy layer (rungs 0–5): solver abstraction, one swappable
  power-flow residual seam (DC / LinDistFlow / SOCP Convex Branch Flow with validated exactness),
  prosumer device library + aggregator + GLB-CVX social welfare, DADP/DLMP dual-based pricing with
  4-way decomposition, and ADMM decomposition validated against the centralized optimum on IEEE 13 + 123.
- A reproducible experiment harness (declarative `Scenario`, `run_scenario`/`run_sweep`, seeded
  bit-for-bit, provenance-stamped DrWatson storage).
- Literate per-model math documentation (Documenter + Literate, `@example`-executed) and an
  end-to-end regression acceptance gate with pinned fixtures.

### What Worked
- **The residual-seam contract** (locked in Phase 2) paid off: SOCP, pricing dual-extraction, and ADMM
  all reused it verbatim with zero divergent re-implementations — the integration check confirmed a
  single source of truth for every cross-phase seam.
- **Duals-as-prices via JuMP named constraints** made DADP/DLMP extraction a direct `dual(balance)` read.
- **Abstraction ladder**: each rung shipped a runnable, validated solve, so regressions surfaced immediately.
- **Adversarial re-review after each fix pass** caught real consequential defects a single pass missed
  (e.g. Phase-8 WR-06 stale save-path, Phase-9 CairoMakie manifest not re-resolved → silent figure no-op).

### What Was Inefficient
- **Requirement-checkbox bookkeeping drifted**: phases 1–7 never ticked their REQUIREMENTS.md checkboxes
  (only phase.complete for 8–9 did), forcing a milestone-close reconciliation of 33 stale entries.
- **Thesis-figure calibration gap surfaced late** (Phase 4/5): the +$1819 / +25% welfare headlines can't
  be reproduced without digitizing figure-bound inputs — pinned computed goldens instead; a documented
  follow-up rather than a blocker.
- A few executor Rule-1 deviations (default ADMM ρ too small, device-contract mismatch in a doc example)
  were only caught at solve time — earlier fixture-level checks would have pre-empted them.

### Patterns Established
- **One residual seam, many formulations**: `contribute!`/`add_to_residual!` is the only place branch/
  voltage math is written; every solve strategy consumes it.
- **Solve-before-dual gating**: `assert_solved!(; dual=true)` + `assert_socp_exact!` guards every price read.
- **Inline typed golden + `rtol`** for regression pins (not external golden files); JLD2/CSV reserved for
  experiment outputs.
- **Computed goldens as regression anchors** when the literature figure isn't reproducible from vendored
  data, with the thesis number kept as a non-failing `@test_broken`/`@info` cross-check.
- **Weakdep-gated optional deps** (Gurobi/Mosek/CairoMakie) with `Base.find_package(...) !== nothing` guards.

### Key Lessons
1. Lock the reusable seam against real math **before** generalizing — it prevented divergent power-flow
   implementations across four consumers.
2. When a literature headline number depends on figure-bound inputs, pin a **computed golden** and record
   the reproduction gap as an explicit, accepted deferral — don't let it block the milestone.
3. `phase.complete` must actually tick REQUIREMENTS.md checkboxes; otherwise traceability drifts silently
   until milestone close.
4. A second adversarial review pass after fixes is worth its cost — it repeatedly caught fix-induced
   regressions (stale paths, silently-skipped guards) that the first pass and the executor self-checks missed.

### Cost Observations
- Model mix: orchestration on Opus; all executor / researcher / planner / reviewer / verifier subagents on Sonnet.
- Parallelism: Phase-9 wave 1 ran 3 independent doc/test plans concurrently in isolated worktrees; the
  strictly-sequential dependency chains (Phase 8, and Phase-9 waves 2–3) ran sequentially on the main tree.
- Notable: the dominant wall-clock cost was the full test suite (~7–8 min incl. IEEE-123 ADMM), run at
  every wave boundary and every verification — the correct place to spend it for a correctness-first bench.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v1.0 | 9 | Established the GSD abstraction-ladder + residual-seam workflow; introduced VALIDATION.md (Nyquist) in Phase 9 |

### Cumulative Quality

| Milestone | Tests | Broken (documented) | Notes |
|-----------|-------|---------------------|-------|
| v1.0 | 1946 pass / 0 fail | 2 | 2 broken = non-failing thesis-figure cross-checks; docs build green |

### Top Lessons (Verified Across Milestones)

1. (v1.0) Lock reusable seams against real math before generalizing.
2. (v1.0) Pin computed goldens + keep literature numbers as non-failing cross-checks when inputs aren't reproducible.
