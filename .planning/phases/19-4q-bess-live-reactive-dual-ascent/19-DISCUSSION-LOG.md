# Phase 19: 4Q-BESS + Live Reactive Dual-Ascent - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-07
**Phase:** 19-4Q-BESS + Live Reactive Dual-Ascent
**Areas discussed:** 4Q-BESS device semantics, Complementarity guarantee, Aggregator contract widening, Live μ-ascent config & validation

---

## 4Q-BESS device semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone battery (Recommended) | Pure battery + 4Q inverter, no PV field; PV prosumers keep PVBattery alongside | ✓ |
| 4Q PV+battery | Extends PVBattery semantics; couples PV curtailment, charging, and the cone | |
| Both via composition | Standalone now + composed PV+4Q variant in a fixture | |

**User's choice:** Standalone battery

| Option | Description | Selected |
|--------|-------------|----------|
| Grid charging, unrestricted (Recommended) | Sign-free p within symmetric bounds and the cone | |
| Grid charging, capped | Sign-free p with an explicit charge-rate cap separate from discharge (asymmetric bounds) | ✓ |
| You decide | Claude picks for cleanest convex structure | |

**User's choice:** Grid charging, capped
**Notes:** User chose the more realistic asymmetric-inverter option over the recommended unrestricted variant. A6 (charge-from-PV-only) documented as PVBattery-specific.

| Option | Description | Selected |
|--------|-------------|----------|
| Free within cone (Recommended) | q priced purely by network μ duals; q may be degenerate at μ≈0 | ✓ |
| Small quadratic q cost | ε·q² inverter-loss proxy; regularizes q but taints pure-dual narrative | |
| You decide | Pick after checking degeneracy on the fixture | |

**User's choice:** Free within cone

| Option | Description | Selected |
|--------|-------------|----------|
| Split p_ch/p_dch, net p (Recommended) | Convex round-trip-η modeling; complementarity question stays live | ✓ |
| Single sign-free p, lossless | η = 1, no split, no complementarity question, less credible BESS | |
| You decide | Weigh SOC fidelity vs simplicity in planning | |

**User's choice:** Split p_ch/p_dch, net p

---

## Complementarity guarantee

| Option | Description | Selected |
|--------|-------------|----------|
| Both: derive + always check (Recommended) | Re-derive conditions for p_ch·p_dch = 0 under grid charging AND hard post-solve check every solve | ✓ |
| Hard check only | Check is the guarantee; no theory for when violations expected | |
| Derivation only | Constructor guards enforce derived conditions; roadmap forbids silent inheritance | |

**User's choice:** Both: derive + always check

| Option | Description | Selected |
|--------|-------------|----------|
| Throw by default, kwarg to report (Recommended) | Mirrors assert_socp_exact!/rtol_exact diagnostic-neutralization pattern | ✓ |
| Report-don't-throw | Structured finding, never aborts; risks contaminating goldens | |
| Always throw, no escape hatch | Blocks legitimate research into violation regimes | |

**User's choice:** Throw by default, kwarg to report

| Option | Description | Selected |
|--------|-------------|----------|
| Named certificate function (Recommended) | Exported gate, own WR-01 scale-free tolerance, noise-floor calibrated; Phase 23 reusable | ✓ |
| Inline at solve layer | Private check; harder to reuse, weaker traceability | |
| You decide | Honor the standing certificate bar either way | |

**User's choice:** Named certificate function

| Option | Description | Selected |
|--------|-------------|----------|
| Honest finding + documented boundary (Recommended) | Characterize violating regime as first-class finding; certificate throws there | ✓ |
| Constructor guard excludes it | Restrict parameters so violations unreachable; forbids negative-price arbitrage scenarios | |
| You decide | Decide once derivation shows the violating region's shape | |

**User's choice:** Honest finding + documented boundary

---

## Aggregator contract widening

| Option | Description | Selected |
|--------|-------------|----------|
| Optional q_inject field (Recommended) | (; vars, p_inject, q_inject, utility); absent = zero; existing devices untouched | ✓ |
| All devices return q_inject | Explicit q_inject = 0 in five stable files for zero behavioral change | |
| 4Q-only special path | Aggregator special-cases by type; doesn't generalize for Phase 23 | |

**User's choice:** Optional q_inject field

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, purely additive (Recommended) | :Rq = −Pdc·tanφ + Σ device q_inject; inelastic term untouched → structural byte-identity | ✓ |
| Refactor Rq assembly | General composition loop; byte-identity must be re-proven | |
| You decide | Pick the shape with easiest byte-identity proof | |

**User's choice:** Yes, purely additive

| Option | Description | Selected |
|--------|-------------|----------|
| First-class, peer of λ (Recommended) | μ-per-bus-per-hour + q trajectories in the same results/DataFrame surface as λ | ✓ |
| Minimal exposure | dual()/value() extraction only; every consumer re-derives it | |
| You decide | Match v2.1's certified-dual-read surface, extend only if needed | |

**User's choice:** First-class, peer of λ

---

## Live μ-ascent config & validation

| Option | Description | Selected |
|--------|-------------|----------|
| Promote to 3-state mode (Recommended) | reactive = :off \| :certified \| :live, Bool back-compat; one knob, no invalid combos | ✓ |
| New layered Bool kwarg | reactive_dual_ascent::Bool requiring reactive_consensus = true; two coupled Bools | |
| You decide | Keep default byte-identical either way | |

**User's choice:** Promote to 3-state mode

| Option | Description | Selected |
|--------|-------------|----------|
| Small fixture primary + IEEE-13 quarantined (Recommended) | CI gate on small radial fixture with 4Q-BESS; IEEE-13 under existing bounded-retry quarantine | ✓ |
| IEEE-13 primary | Stronger headline but stacks new outer loop on known-flaky solve | |
| You decide | Measure μ-ascent solve-failure rate per fixture first | |

**User's choice:** Small fixture primary + IEEE-13 quarantined

| Option | Description | Selected |
|--------|-------------|----------|
| Welfare + λ + μ, own tolerances (Recommended) | Three checks, each newly measured (measurement-before-golden); μ matching is the deliverable | ✓ |
| Welfare + λ only, μ reported | Gate on what v2.1 gates; headline claim ships ungated | |
| You decide | Gate all three unless genuine μ degeneracy shows; then document honest boundary | |

**User's choice:** Welfare + λ + μ, own tolerances

| Option | Description | Selected |
|--------|-------------|----------|
| Docstrings + derivation note only (Recommended) | House-style docstrings + 4Q complementarity derivation beside the code; literate page waits for Phase 23 | ✓ |
| Small standalone doc page now | Early visibility, superseded by Phase 23's combined page | |
| You decide | Based on whether the derivation wants rendered math | |

**User's choice:** Docstrings + derivation note only

---

## Claude's Discretion

- Two-block convergence/stopping treatment math (residual choice, μ update rule, whether the
  reactive block gets its own ρ) — only constraint: not the single-block Boyd rule as-is.
- μ initialization / warm-start (e.g. from the :certified one-shot read).
- Utility parametrization of the 4Q battery's charge/discharge preference.
- Naming of the device struct, certificate function, and mode symbols.
- Whether AGR-OPT going conic (SOCP) with a 4Q device present needs solver-path adjustment.

## Deferred Ideas

None — discussion stayed within phase scope.
