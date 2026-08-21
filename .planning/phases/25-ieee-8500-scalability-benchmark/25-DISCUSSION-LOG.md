# Phase 25: IEEE-8500 Scale Benchmark - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-20
**Phase:** 25-IEEE-8500 Scale Benchmark
**Areas discussed:** Population density at 1,177 LV load buses; S_base vs the IMPEDANCE_PU_MAX
tripwire; What the benchmark deliverable actually is; Solver-comparison scope (the SCS problem);
Capacitor banks (SCALE-03)

**Note on grounding:** two questions were answered by computing from the source data rather than by
preference — the `S_base` table (worst-case CT5 per-unit impedance at 0.1 / 1 / 10 MVA) and the
capacitor-bus load/transit status. Those computations are recorded in CONTEXT.md.

---

## Population density at 1,177 LV load buses

| Option | Description | Selected |
|--------|-------------|----------|
| Density sweep, full density as top point | Populate 10/25/50/100% of load buses; output is a curve, separating network-size cost from AGR-OPT fan-out cost | ✓ |
| Full density only | 3-device house at all 1,177 load buses; single number, no cost attribution | |
| Coarse aggregation | One aggregator per service-transformer group or lateral (~few hundred); invents an aggregation rule not in the source data | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, MV-only control point | ~2.5k-bus MV-only variant with loads aggregated to MV node; only way to attribute cost to the LV rungs | ✓ |
| Full MV+LV only | Single fixture, tighter phase, but 'is the LV secondary what breaks it?' unanswerable | |

| Option | Description | Selected |
|--------|-------------|----------|
| Real kW from Loads.dss × seeded profile shape | Uses actual per-load kW at pf 0.97; removes a tuned magic constant | ✓ |
| Synthetic seeded scaling, new tuned constants | Follows the _IEEE13/_IEEE123_LOAD_SCALE precedent; invents magnitudes when real ones exist | |

| Option | Description | Selected |
|--------|-------------|----------|
| Keep the 3-device house fixed | Thermostatic + Deferrable + PVBattery, comparable to IEEE-13/123 | ✓ |
| Add a device-count axis too | 2-D cost surface; combinatorial on top of a density sweep | |
| You decide | Claude's discretion | |

**User's choice:** all four as recommended.
**Notes:** The density-sweep choice is what converts this phase's output from a point measurement into
a scaling curve. Combined with the MV-only control, the benchmark can attribute cost to three separate
causes (network size, LV depth, population fan-out).

---

## S_base vs the IMPEDANCE_PU_MAX tripwire

| Option | Description | Selected |
|--------|-------------|----------|
| 1 MVA, matching IEEE-13/123 | Worst case CT5 at r=3.60/x=4.08 pu — 82% of the 5.0 limit; preserves cross-fixture pu comparability | ✓ |
| 0.1 MVA for comfortable margin | Worst case 8% of limit, but breaks pu comparability and inflates smax 10× (head 27.5 → 275 pu, over SMAX_PU_MAX=100) | |
| You decide | Claude's discretion | |

| Option | Description | Selected |
|--------|-------------|----------|
| Keep every branch; report the spread as measured | ~9-order spread becomes a reported finding; merged variant only as data-driven follow-up | ✓ |
| Merge degenerate stubs up front | Cleaner numerics but pre-empts the finding the phase exists to produce | |
| Ship both variants in this phase | Best attribution, third axis, materially more work | |

| Option | Description | Selected |
|--------|-------------|----------|
| Per-level bands, LV floor from source data | MV 0.9–1.1; LV floor 0.88 as Loads.dss itself declares via Vminpu=.88 | ✓ |
| Uniform 0.9–1.1 everywhere | Consistent with existing fixtures but risks manufacturing infeasibility at 1,177 LV buses | |
| You decide | Claude's discretion | |

| Option | Description | Selected |
|--------|-------------|----------|
| Head-only real limit, interior sentinel | 27.5 MVA on head branch, SMAX_NO_LIMIT elsewhere; IEEE-123 precedent | ✓ |
| Real per-segment ampacity from linecode normamps | More faithful but a congestion study wearing a benchmark's clothes | |
| You decide | Claude's discretion | |

**User's choice:** all four as recommended.
**Notes:** A prior estimate of "~6 orders of magnitude" impedance spread was corrected to **~9 orders**
during this area (6.4e-9 pu for the 0.001 km HVMV_Sub_connector up to 4.08 pu for a CT5 transformer).
The same computation established that `S_base` shifts the whole distribution uniformly and therefore
cannot change the spread — reframing `S_base` as a tripwire-placement decision, not a conditioning
lever.

---

## What the benchmark deliverable actually is

| Option | Description | Selected |
|--------|-------------|----------|
| Fixture-parametrized script in scripts/ | Runs across ieee13/ieee123/ieee8500-mv/ieee8500; matches socp_applicability_sweep.jl precedent | ✓ |
| Inline in the literate page only | Least code; numbers not re-runnable across fixtures | |
| Exported module in src/ | First-class API but grows library surface with a non-capability | |

| Option | Description | Selected |
|--------|-------------|----------|
| Cheap smoke test only, no perf goldens (RECOMMENDED) | Fixture invariants + one small solve; avoids timing flake | |
| Perf regression goldens with generous bands | Catches regressions directly; timing goldens are the classic flake source | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Committed results artifact + small live slice (RECOMMENDED) | DrWatson tagsave once, page reads it; keeps docs build tractable | |
| Fully live-executed at docs build | Maximum reproducibility; unbounded runtime at 4,900 buses × sweep grid | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Full set with build-vs-solve split | Assembly vs solver time, iterations, peak memory, termination status, noise floor, exactness verdict | ✓ |
| Minimal: end-to-end time + iterations | Simpler, but can't separate 'JuMP assembly is slow' from 'the solver struggles' | |

**User's choice:** two of four **overrode the recommendation** — perf goldens in CI (not smoke-only),
and a fully live-executed docs page (not a committed artifact).
**Notes:** Rather than re-arguing, two follow-up questions were asked to make the overrides
implementable. The concerns were stated once: a fully-live build has no a-priori runtime bound
(unknowable, since runtime is what the phase measures), and wall-time goldens on shared CI runners
flake. Both were resolved below without walking back either choice.

### Follow-ups on the two overrides

| Option | Description | Selected |
|--------|-------------|----------|
| Live-execute every point with a per-point timeout | Exceeded point records a 'budget exceeded' row; keeps the page fully live AND bounds the build | ✓ |
| Full grid, no cap | Maximum fidelity; one non-convergent point can stall CI/docs indefinitely | |
| Live-execute a documented reduced grid | Bounded, but the headline 100%-density point may not appear in the page | |

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic quantities, wall time recorded not gated | Pin iteration counts, model dimensions, termination status — machine-independent | ✓ |
| Wall-time bands on cheap fixtures only | Gates real time, but bands loose enough not to flake also miss real regressions | |
| Wall-time bands on all fixtures including 8500 | Strongest coverage; CI runs the full 4,900-bus sweep every time | |

**Notes:** The timeout row is itself treated as an honest scaling finding rather than a build failure —
which is what makes the unbounded live-execution choice safe.

---

## Solver-comparison scope (the SCS problem)

| Option | Description | Selected |
|--------|-------------|----------|
| Weakdep + ext/TSODSOSCSExt.jl | Follows the Gurobi/Mosek extension precedent; no new hard runtime dep; stays removable | ✓ |
| Hard dependency in [deps] | Simplest to use; contradicts the milestone's zero-new-runtime-packages preference | |
| Drop SCS, compare Clarabel vs Ipopt | No new dep at all; drops the first-order-vs-IPM crossover SCALE-04 names | |

| Option | Description | Selected |
|--------|-------------|----------|
| Include a measured DADP-drift diagnostic | Reports how far SCS duals/cone residuals drift from Clarabel's; turns standing policy into evidence | ✓ |
| Timing and convergence only | Tighter scope; leaves the policy unmeasured | |
| You decide | Claude's discretion | |

**User's choice:** both as recommended.
**Notes:** This area existed because scouting found SCS absent from `Project.toml` — the ROADMAP's
SCALE-04 wording had assumed a "Clarabel-vs-SCS crossover" against a solver that wasn't a dependency.
The DADP-drift diagnostic is scoped as a column in the results table, not a price-quality study.

---

## Capacitor banks (SCALE-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed-Q device via the existing q_inject seam | Small q-only device in an Aggregator at each cap bus; reuses Phase 19 MESH-04/D-09; no core model change | ✓ |
| Documented omission, consequence estimated analytically | Cheapest, but can't measure its own consequence without building the injection anyway | |
| Omit in fixture, add a with-caps variant for comparison | Genuine measured consequence; yet another fixture variant | |

| Option | Description | Selected |
|--------|-------------|----------|
| Always-on at nameplate, switching out of scope | One documented assumption; follows the OVR-axis stance against decentralized control laws | ✓ |
| Fixed at a stage informed by CapControls.DSS | More faithful to intended operating point; must defend the chosen stage | |
| You decide | Claude's discretion | |

| Option | Description | Selected |
|--------|-------------|----------|
| Promote to load buses with zero inelastic demand | q-only Aggregator with Pdc=0; preserves the DEV-05 sole-:Rq-writer invariant | ✓ |
| Extend transit-node relaxation to accept constant q | Avoids a zero-demand aggregator but adds a second :Rq writer | |
| You decide | Claude's discretion | |

**User's choice:** all three as recommended.
**Notes:** This area was surfaced deliberately rather than decided silently, because it is
requirement-level (SCALE-03). Mid-area scouting changed the recommendation: Phase 19's optional
`q_inject` device seam already exists, so modeling the banks costs no core change — which made
omission the weaker option rather than the cheaper one. Separately verified that all 4 cap buses carry
no load and would otherwise be transit nodes.

---

## Claude's Discretion

- ADMM iteration cap and non-convergence policy at 1,177 aggregators (bounded by the standing
  honest-non-convergence-is-a-deliverable carry-forward and the per-point timeout).
- The cone-gap noise-floor calibration ladder at ~4,900 branches, and whether the calibrated floor is
  committed as fixture metadata.
- Density-sweep grid points (10/25/50/100% illustrative, not locked) and the per-point timeout value.
- All module/struct/function/kwarg/fixture-symbol names, the reduction script name, the generated
  impedance-table filename, and the q-only capacitor device type name.
- Whether the MV-only control is a separate committed builder or a documented reduction mode of one
  builder.

## Deferred Ideas

- SCALE-STRETCH performance engineering (`direct_model`, parallel AGR-OPT, preconditioning).
- High-PV DLMP case study at 8500 scale — the pricing story, not the scaling one.
- Degenerate-stub-merged fixture variant — only if measurement shows conditioning is the wall.
- Device-count axis on top of the density sweep.
- Real per-segment ampacity limits from linecode `normamps`.
- CapControl switched-capacitor behavior and regulator tap changing.
- Unbalanced three-phase use of the 8500 source data (permanently out of standing scope).
- Housekeeping: `/gsd:spike --wrap-up` to package `.planning/spikes/MANIFEST.md` findings as a
  discoverable skill.
