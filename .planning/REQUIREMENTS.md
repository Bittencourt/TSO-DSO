# Requirements — Milestone v2.1 Validation & Reproduction

**Goal:** Harden the framework's core correctness claims so every downstream extension — and the
thesis itself — rests on validated, citable ground. No new research axis; deepen trust in what exists.

Derived from `.planning/research/SUMMARY.md` (all four capabilities are additive extensions of
existing, proven seams — zero new *main* dependencies). REQ-IDs are stable handles for roadmap
traceability.

---

## v2.1 Requirements

### AC-Exactness Certification (`EXACT`)
Certify the SOCP Convex Branch Flow relaxation is exact against an *independent* true AC solution —
replacing today's toy-point + same-relaxation self-check.

- [x] **EXACT-01**: Researcher can solve a true nonconvex AC-OPF on a radial fixture via a new
      `ACPowerFlow <: AbstractPowerFlow` peer subtype (Ipopt), enforcing the branch-flow SOC as a
      nonconvex **equality**, at the same operating point (loads/PV) as the SOCP solve.
- [x] **EXACT-02**: Framework certifies exactness via `assert_ac_exact!` (peer to `assert_socp_exact!`)
      by comparing the SOCP solution to the AC oracle on objective gap, max voltage deviation, and max
      branch-flow deviation, using a scale-free `atol + rtol·magnitude` tolerance.
- [x] **EXACT-03**: The exactness check reports **per-hour / per-scenario** gaps (not one pass/fail)
      and is structured so a genuine relaxation gap surfaces as a first-class, documented finding —
      not a spurious test failure.
- [x] **EXACT-04**: A high-PV / reverse-flow stress fixture exercises the exactness boundary and
      documents where (and whether) the SOCP relaxation goes inexact for this framework's target regimes.

### Reactive-Power Consensus (`REACT`)
Restore a genuine reactive-power balance and a citable reactive price, closing the `AgrOpt.jl`
placeholder.

- [x] **REACT-01**: The DSO-OPT per-node **reactive-power balance is a genuine equality constraint**
      (replacing today's free reactive-import slack), enforced in both the centralized and ADMM solves.
- [x] **REACT-02**: A reactive nodal price `μ_j` (dual of the reactive balance) is extracted and
      contributes a documented reactive/voltage component to the DLMP decomposition in `pricing/dlmp.jl`.
- [x] **REACT-03**: Reactive consensus rolls out **without regressing the existing active-only
      cross-validated ADMM path** (feature-flagged/additive), with the `μ`-symbol naming collision
      (reactive dual vs. the existing adaptive-ρ band) resolved as the first design decision.

### Real IEEE-123 Impedances (`IMPED`)
Replace synthetic IEEE-123 impedances with real, standard, citable data.

- [ ] **IMPED-01**: An **offline, reproducible script** parses the public OpenDSS IEEE-123 case
      (`IEEE123Master.dss` + `IEEELineCodes.DSS`) and reduces the 3-phase line-code matrices to
      positive-sequence R₁/X₁ per segment (documented Fortescue-averaging reduction), with **PMD kept
      out of the runtime dependency graph** (throwaway env or weakdep+extension only).
- [ ] **IMPED-02**: `ieee123.jl` consumes the committed real positive-sequence impedances (a pure-data
      `const` table) in place of synthetic values, topology untouched, with the reduction assumptions
      and caveats (transposition, single-phase laterals, regulators/caps/switches handling) documented.
- [ ] **IMPED-03**: The real-impedance IEEE-123 case remains **meaningful for its purpose**
      (voltage-binding) — verified; PV/aggregator population re-tuned and documented if required.
      Prior synthetic-fixture goldens are preserved as an independent regression or consciously re-pinned
      with a before/after rationale.

### Directional Thesis Reproduction (`REPRO`)
Make a defensible reproduction claim on real, standard data.

- [ ] **REPRO-01**: A literate rung/doc page + gate-then-golden test reproduces the **direction and
      magnitude-band** of the thesis welfare/surplus result on real data (sign + band, not the exact
      figure), carrying a fixed "directional, public-data" qualifier phrase.
- [ ] **REPRO-02**: A consolidated **assumptions/reduction doc page** documents what makes the numbers
      what they are; repeated-run stability is checked before any new golden is pinned (guarding against
      pinning transient Clarabel numerical noise).

---

## Future Requirements (deferred — later milestone)

- [ ] **REPRO-STRETCH-01**: Exact-figure reproduction of the thesis welfare headline (+$1,819 / +25%),
      contingent on obtaining thesis Appendix E (currently behind an IP-blocked CONICET repository).
- Discrete/integer investment expansion (`PLAN-INT-01`), stochastic scenarios (`PLAN-STOCH-01`),
  MPC/rolling-horizon, meshed + 4Q-BESS — carried forward from v2.0 as later research thrusts.

## Out of Scope (v2.1)

- **Unbalanced three-phase modeling** — v2.1 stays balanced positive-sequence; the OpenDSS 3-phase data
  is *reduced*, not modeled per-phase. (Consistent with the project's standing scope.)
- **A full reactive-power dual-ascent ADMM loop** *if* the equality-constraint route yields `μ_j` for
  free — an implementation decision deferred to the REACT phase, not a committed requirement.
- **Modeling IEEE-123 regulators / capacitors / switches** as active devices — approximated/absorbed
  into the reduced feeder; explicitly documented, not simulated.
- **Exact thesis-figure reproduction** — moved to Future (data-gated). v2.1 commits only to directional.
- New research axes (integer/stochastic/MPC/meshed) — deferred by explicit choice.

## Traceability

| REQ-ID | Phase |
|--------|-------|
| EXACT-01 | Phase 15 |
| EXACT-02 | Phase 15 |
| EXACT-03 | Phase 15 |
| EXACT-04 | Phase 15 |
| REACT-01 | Phase 16 |
| REACT-02 | Phase 16 |
| REACT-03 | Phase 16 |
| IMPED-01 | Phase 17 |
| IMPED-02 | Phase 17 |
| IMPED-03 | Phase 17 |
| REPRO-01 | Phase 18 |
| REPRO-02 | Phase 18 |

**Coverage:** 12/12 v2.1 requirements mapped. No orphans.
</content>
