# Spike Manifest

## Idea

Map the region of parameter space where the SOC branch-flow relaxation is **exact** — turning v2.1's
knife-edge inexactness finding from an unmapped hazard into a visible, citable validity envelope.
Scoping context and the wider milestone shape live in `.planning/notes/socp-validity-envelope.md`.

The central enabling insight: the detector is **free**. `src/models/exactness.jl:8` already computes
the cone residual `|l·v − (P²+Q²)|` off every SOCP solve, so a dense parameter sweep costs one
Clarabel solve per point and **no AC/Ipopt oracle at all**.

## Requirements

Design decisions that emerged while spiking. Non-negotiable for the real build.

- **Never modify `src/` to observe the relaxation.** Neutralize the PF-04 gate via the existing
  `rtol_exact` kwarg (the diagnostic pattern already at `test/test_ac_oracle.jl:181-187`) and classify
  externally. Spike 001 needed zero `src/` changes.
- **Every sweep must contain a known-inexact positive control.** Spike 001's first iteration reported
  "111/111 exact" on an inert fixture; without a positive control that outcome is indistinguishable
  from a working one. Controls are printed and checked on every run.
- **Non-solved points are never one colour.** `infeasible` (physically unserveable — legitimate white
  space) and guard-tripped (genuinely **unmeasured**) are categorically different and must render
  differently. Never silently dropped.
- **Scale-free classification only** — the house WR-01 `atol + rtol·magnitude` idiom, never a bare
  absolute threshold.
- **Calibrate the solver noise floor before classifying anything, on every new feeder.** WR-01 scales
  the threshold with quantity *magnitude* but NOT with solver *accuracy*, and accuracy degrades with
  problem size. On 122 branches Clarabel's cone residual at the default `tol_gap = 1e-8` is ~1e-6–5e-6,
  which is the `atol` itself — so 48% of spike 002's points were flagged inexact by noise. Establish
  the floor per feeder (re-solve a benign point across a tolerance ladder) and classify against it.
- **A cone-gap ratio near 1 is not evidence.** Structural inexactness on the 3-bus fixture gave 1e3–1e4.
  Ratios of 1–5 must be tolerance-discriminated before being called a finding.
- **Never generalize a boundary finding from one substrate.** Two of spike 001's three headline findings
  died on the second substrate.
- **Report fixture-relative axes as fixture-relative.** `pv_scale`/`load_scale` are dimensionless
  multipliers on a synthetic profile, not PV penetration. Do not dress them as physical units.

## Spikes

| # | Name | Type | Validates | Verdict | Tags |
|---|------|------|-----------|---------|------|
| 001 | relaxation-validity-map | standard | Given a (pv_scale × load_scale × vmax) grid on the high-PV fixture, when the free cone-gap detector classifies each point, then the exact/inexact boundary renders as a map and both EXACT-04 controls reproduce | ✓ VALIDATED<br>*(findings 2 & 3 later shown substrate-specific by 002)* | socp, exactness, relaxation, parameter-sweep, figure, validity-envelope |
| 002 | ieee123-validity-map | standard | Given the 001 method on real IEEE-123 OpenDSS impedances, when the detector classifies a (pv × load × vmax) grid, then the boundary renders as a map | ⚠ PARTIAL — no boundary exists; flags are solver noise. Yielded a **method defect** instead | socp, exactness, ieee123, real-impedances, null-result, tolerance, solver-noise |

| 003 | phase18-fragility-tolerance | standard | Given Phase 18-01's ±2-5% sweep re-run at tightened solver tolerance with the gate armed, when failures are attributed per-call, then we learn whether the recorded fragility is artifact or physical | ✓ VALIDATED — **overturns a shipped v2.1 finding** | tolerance, phase18, thesis-reproduction, correction, fit-baseline, misattribution |

**Headline across all three.** The free cone-gap detector is sound in principle but **not usable at
default tolerance on a 122-branch feeder** — its `atol = 1e-6` sits at Clarabel's noise floor there. On
real IEEE-123 impedances there is no overvoltage at all (bound never active, `vpeak ≤ 1.016` vs caps
≥ 1.05), so the 3-bus mechanism does not transfer.

Spike 003 then closed the question spike 002 raised, and the answer is a **correction to shipped work**:
v2.1's `sign_flip_survives: false` is wrong. `solve_welfare`'s gate failures are purely numerical (0/5
throw at `tol_gap=1e-10`, unchanged optima), `dadp_dso` is positive and monotone across the whole ±5%
band, and the sign flip **survives δ=−0.05**. Two of the four recorded failures were `fit_baseline`,
misattributed to `solve_welfare` by a combined try/catch.

**Blocking `src/` defect:** `fit_baseline` (`src/pricing/fit.jl:271`) has no `optimizer` kwarg, so its
exactness gate cannot be tolerance-conditioned and 3 of 5 points remain unmeasurable. Adding it —
mirroring `solve_welfare` — is the one change that makes population robustness answerable.

### Deferred (decomposed, then dropped as out of scope)

Spike 001 was originally decomposed into three spikes for a *bound-and-report* certified
welfare-optimality gap (bound direction, AC primal feasibility, multi-start monotonicity). The
actual ask was the visual map, so those were dropped before any code was written. They remain the
natural next spikes if the welfare-magnitude question is picked up — see
`.planning/notes/socp-validity-envelope.md` § Tier 2, which retains the four design decisions.
