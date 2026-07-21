---
phase: 04-convex-branch-flow-correctness-milestone
plan: 05
subsystem: optimization
tags: [socp, exactness, dadp, clarabel, branch-flow, transactive-pricing, pf-04]

# Dependency graph
requires:
  - phase: 04-02
    provides: ConvexBranchFlow SOCP formulation + LinDistFlow exactness copy + problem_class(::ConvexBranchFlow)=SOCP()
  - phase: 04-03
    provides: ieee13_modified feeder fixture
  - phase: 03-05
    provides: solve_welfare GLB-CVX centralized welfare solve + aggregator roll-up
provides:
  - "assert_socp_exact!(ctx; τ) — the PF-04 price-refusal gate: max|l·v−(P²+Q²)| < τ per branch, throws (refuses prices) on inexactness"
  - "solve_welfare hook: exactness gate runs after assert_solved!, before the dual read, gated on :l (DC/LinDistFlow untouched); stashes ctx.meta[:socp_maxgap]"
  - "solve_welfare priced frontier export (allow_export) — the SOC-exactness enabler for the over-voltage/reverse-flow regime"
  - "SOCP-aware default battery-complementarity tolerance (1e-4 SOCP / 1e-6 QP)"
affects: [04-06, phase-05, admm, dadp-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Post-solve invariant gate keyed on a stashed variable (:l) — data-driven, no formulation branch"
    - "Priced free-sign frontier exchange as the SOC-exactness sufficient condition (objective strictly decreasing in loss current l)"
    - "Problem-class-aware numeric tolerance via the problem_class(pf) trait (never an if formulation ==)"

key-files:
  created:
    - src/models/exactness.jl
  modified:
    - src/models/welfare_solve.jl
    - test/fixtures_phase4.jl
    - test/test_exactness.jl

key-decisions:
  - "Root cause of high-PV inexactness is the missing frontier export sink, NOT the exactness-copy voltage-bound placement — the ConvexBranchFlow formulation (04-02) is correct as-is and was not changed"
  - "Priced frontier export (allow_export, free-sign p_import at λ₀) restores the SOC-exactness sufficient condition; added as an opt-in kwarg (default off) so all import-only rungs and the WR-04 curtailment test are preserved"
  - "SOC exactness holds under over-voltage/reverse flow AS LONG AS the upper voltage bound does not strictly bind; an over-scaled back-feed that pins v at V²max is the one regime where it genuinely fails (and the gate correctly refuses)"
  - "Calibrated the high-PV fixture pv_scale 50 → 0.5 (peak ~1.04 pu, below the 1.05 cap) — a real over-voltage/reverse-flow regime that is exact, matching the thesis exact v≈1.049 pu result"
  - "Battery-complementarity τ is problem-class-aware (SOCP 1e-4 vs QP 1e-6) to match Clarabel's conic accuracy without loosening the QP path"

patterns-established:
  - "PF-04 gate: certify SOC exactness numerically post-solve and refuse prices on failure — prices are duals, an inexact relaxation yields meaningless duals with no solver error"

requirements-completed: [PF-04]

# Metrics
duration: ~90min
completed: 2026-07-18
---

# Phase 4 Plan 5: SOCP Exactness Gate (PF-04) Summary

**The project's headline correctness gate: `assert_socp_exact!` certifies `max|l·v−(P²+Q²)| < τ` per branch after every SOCP solve and REFUSES prices on failure — and the fix that makes a genuine over-voltage/reverse-flow case exact is a priced frontier export sink, not a formulation change.**

## Performance

- **Duration:** ~90 min (including a coordinator-directed root-cause investigation)
- **Tasks:** 3 (+ 1 phase-level correctness fix)
- **Files modified:** 3 (+ 1 created)

## Accomplishments

- **PF-04 gate** (`assert_socp_exact!`): per-branch/time gap `value(l)·value(v[from]) − (value(P)²+value(Q)²)`, throws with "REFUSED" when `max|gap| ≥ τ` (default `1e-5`), returns `maxgap` otherwise. Hooked into `solve_welfare` strictly after `assert_solved!` and before `dual.(balance_p)`, gated on `haskey(pf_vars, :l)` so DC/LinDistFlow are untouched; stashes `ctx.meta[:socp_maxgap]`.
- **SOCP solver routing** by trait: `solve_welfare` default optimizer is now `select_optimizer(problem_class(pf))`.
- **Root-caused and fixed** the high-PV over-voltage inexactness (see below): a priced frontier export sink restores SOC exactness; the high-PV fixture was recalibrated to a real, below-cap over-voltage regime.
- **Full suite green: 546 pass, 0 fail, 0 error.** The three "exact" testitems pass (throw-on-inexact, pass-on-exact, and a genuine high-PV over-voltage solve that stays exact with prices NOT refused).

## Task Commits

1. **Task 1: `assert_socp_exact!` exactness gate** — `315db14` (feat)
2. **Task 2 + frontier fix: wire gate + trait routing + priced export + SOCP battery tol into `solve_welfare`** — `251308d` (feat)
3. **Fix: calibrate high-PV fixture to the exact over-voltage regime** — `a787786` (fix)
4. **Task 3: high-PV exactness testitem solves SOCP, asserts real over-voltage** — `a3fff0d` (test)

(Interim `5d66c86` logged the blocker before the coordinator authorized the phase-level fix; its `deferred-items.md` was removed here since the item is resolved.)

## Root Cause & Fix (coordinator-directed investigation)

**Symptom:** with the PF-04 gate live, the high-PV/over-voltage testitem's SOCP solve was grossly inexact (`maxgap ≈ 1.07` at the fixture's `pv_scale=50`), so prices were correctly refused — contradicting the plan's premise that exactness holds there.

**Investigated (in coordinator's order):**

1. **Exactness-copy voltage-bound placement (hypothesis 1) — NOT the cause.** Empirically relaxing the upper bound on the SOC `v` (keeping it on `v̂`) did not restore exactness (and let voltage blow past the cap). A clean 2-bus solve using the *unmodified* `ConvexBranchFlow.contribute!` is exact under over-voltage, so the 04-02 formulation is correct and was left unchanged.
2. **Frontier export sink (hypothesis 2) — THE cause.** With the import-only frontier (`p_import ≥ 0`), a PV surplus can only be shed via line losses (`−r·l`) or PV curtailment, which are welfare-equivalent once `p_import` pins at 0. The objective is then NOT strictly decreasing in the loss current `l`, so the SOC cone `l·v ≥ P²+Q²` goes slack (inexact) — the standard SOC-exactness sufficient condition (objective strictly increasing in `l`) is violated. Adding a **priced free-sign frontier export** (sell surplus to the MEM at λ₀) makes every unit of `l` cost export revenue, restoring the strict penalization: the cone becomes tight. Confirmed: with `allow_export=true`, a genuine over-voltage/reverse-flow case is exact (gap `~1e-9`, `v ≈ 1.04–1.05` pu, `P < 0`).
3. **Battery-complementarity tolerance on the SOCP path (secondary).** Made the check's `τ` problem-class-aware (`1e-4` SOCP / `1e-6` QP) to match Clarabel's conic accuracy; the QP path is unchanged. (At the calibrated fixture the battery product is `3.5e-7`, already within even the QP tolerance, because export removes the need for the battery to cycle.)

**Key theoretical boundary discovered:** SOC exactness holds under over-voltage/reverse flow **until the upper voltage bound strictly binds** (voltage pinned at `V²max`). An over-scaled back-feed pins the cap — the one regime where the relaxation genuinely fails and the gate must refuse. The fixture's `pv_scale=50` sat there; `pv_scale=0.5` lands the peak at `≈1.04` pu (real over-voltage, headroom below the `1.05` cap), which is exact — matching the thesis's exact `v≈1.049` pu result.

**Final gap on the high-PV fixture:** `max|l·v−(P²+Q²)| = 4.8e-9` (≪ `τ = 1e-5`), `vmax = 1.0399` pu (over-voltage), `minP = −0.621` (reverse flow), DADPs finite — prices NOT refused.

## Deviations from Plan

**[Rule 4 → coordinator decision] Priced frontier export + fixture recalibration.** The plan assumed the high-PV fixture was exact under the import-only 03-05 welfare model; it is not (a genuine SOC-exactness limitation, not a bug in the gate). Per coordinator authorization for a phase-level correctness fix, added `allow_export` to `solve_welfare` (opt-in, default off) and recalibrated the high-PV fixture. The `ConvexBranchFlow` formulation (04-02) was investigated and found correct — NOT modified. No architectural change to the 03-05 default behavior (export is opt-in; import-only rungs and the WR-04 curtailment test are unaffected).

## Threat Model Coverage

- **T-04-01 (silent-wrong price from inexact relaxation):** mitigated — `assert_socp_exact!` throws before any dual read; `maxgap` is a first-class output (`ctx.meta[:socp_maxgap]`).
- **T-04-03 (reading a dual before the gate):** mitigated — gate placed after `assert_solved!`, before `dual.(balance_p)`; ordering verified.
- **T-04-14 (wrong τ):** mitigated — distinct `τ_exact = 1e-5` kwarg, not conflated with the battery-check `τ`; documented 2-order margin over Clarabel's 1e-8 gap.

## For the Next Phase

- **Priced export is now available** (`solve_welfare(...; allow_export = true)`) — a physically-complete transmission frontier for any high-PV/reverse-flow study; default remains import-only.
- **SOC exactness is regime-dependent:** trustworthy while the upper voltage bound has headroom; the gate is the safety net when a scenario pushes voltage onto the cap. Downstream ADMM/DADP work should keep the gate in the loop.

## Self-Check: PASSED

- Files created/modified all present (`exactness.jl`, `welfare_solve.jl`, `fixtures_phase4.jl`, `test_exactness.jl`, `04-05-SUMMARY.md`).
- Commits present: `315db14`, `251308d`, `a787786`, `a3fff0d`.
- Gate ordering verified: `assert_solved!` (L207) < `assert_socp_exact!` (L222) < `dual.(balance_p)` (L245).
- Full authoritative suite (`Pkg.test()`): **546 pass, 0 fail, 0 error.**
