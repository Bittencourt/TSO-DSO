# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)
- ✅ **v4.0 Correctness & Depth** — Phases 26–38 (shipped 2026-10-08)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md),
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md),
[`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md), and
[`milestones/v4.0-ROADMAP.md`](milestones/v4.0-ROADMAP.md).

## Phases

<details>
<summary>✅ v4.0 Correctness & Depth (Phases 26–38) — SHIPPED 2026-10-08</summary>

- [x] Phase 26: Network & Device Model Correctness
- [x] Phase 27: Integer Planning & Pricing Certificate Correctness
- [x] Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement
- [x] Phase 29: Genuine Bilevel TSO-DSO Variant
- [x] Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder
- [x] Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh
- [x] Phase 32: Declarative Power-Flow & Strategy Dispatch
- [x] Phase 33: Shared Abstractions — Feeder, Balance, Model Context
- [x] Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy
- [x] Phase 35: IEEE-8500 Scale After Refactor
- [x] Phase 36: Code & Export Cleanup
- [x] Phase 37: Test Infrastructure & Repo Hygiene
- [x] Phase 38: Close v4.0 Audit Gaps

</details>

No milestone in progress. Start the next one with `/gsd-new-milestone`.

## Deferred / Future-Milestone Notes

- **Large-lattice integer termination criterion** — a rigorous `δ_min` is not derivable (`Q`'s
  local slope is a continuous SOCP dual price with no established Lipschitz bound), so the
  enumeration-backed criterion (Phase 24, v3.0) is tractable only where enumeration is. BILEV-07
  (Phase 31, v4.0) extends integer investment to N>1 Nash but does not resolve this; still open
  past v4.0.

Items formerly listed here — **SCALE-STRETCH**, the Phase-18 `fit_baseline` convergence flake,
the MESH-06 composition advisory, and integer investment beyond single-distributor Stackelberg —
are now in scope for v4.0 as ARCH-10 (Phase 35), FIX-09 (Phase 27), ARCH-06 (Phase 34), and
BILEV-07 (Phase 31) respectively, and are no longer deferred.
