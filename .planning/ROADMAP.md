# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md),
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md), and
[`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md).


## Phases

No active milestone. Run `/gsd:new-milestone` to define the next one.

## Progress

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 Operational Transactive-Energy Core | 1–9 | 43/43 | Complete | 2026-07-20 |
| v2.0 Stackelberg-Nash TSO–DSO Planning Game | 10–14 | 13/13 | Complete | 2026-07-24 |
| v2.1 Validation & Reproduction | 15–18 | 14/14 | Complete | 2026-07-26 |
| v3.0 Research Extension Rungs | 19–25 | 43/40 | Complete (1 gap accepted) | 2026-08-24 |

## Deferred / Future-Milestone Notes

- **SCALE-STRETCH** — performance and memory-footprint engineering driven by the Phase 25
  measurements: `solve_admm`'s hardcoded final-consolidation `assert_socp_exact!` throwing at
  IEEE-8500 scale even on a converged point, and reaching a converged, memory-feasible headline
  point at all. Deliberately separated from the benchmark that justifies it.
- **Phase-18 `fit_baseline` convergence** — nested solve returns `ALMOST_OPTIMAL` at 3/5 sweep
  points at `tol_gap=1e-10` (flake rate 13/20 = 0.650, all at that stage, reproduced across 3
  runs). Distinct from SOCP inexactness. Wants its own follow-up.
- **MESH-06 composition (advisory)** — `solve_admm` is typed to `pf::ConvexBranchFlow`, so meshed
  topology and live ADMM reactive pricing cannot compose at runtime today. Phase 23 discloses this
  and substitutes a centralized `:balance_q` dual. No requirement mandates the literal composition.
- **Integer investment in the N>1 Nash path** — Phase 24 is single-distributor Stackelberg only.
- **Large-lattice integer termination criterion** — a rigorous `δ_min` is not derivable (`Q`'s local
  slope is a continuous SOCP dual price with no established Lipschitz bound), so Phase 24's
  enumeration-backed criterion is tractable only where enumeration is.
