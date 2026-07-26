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
- **Report fixture-relative axes as fixture-relative.** `pv_scale`/`load_scale` are dimensionless
  multipliers on a synthetic profile, not PV penetration. Do not dress them as physical units.

## Spikes

| # | Name | Type | Validates | Verdict | Tags |
|---|------|------|-----------|---------|------|
| 001 | relaxation-validity-map | standard | Given a (pv_scale × load_scale × vmax) grid on the high-PV fixture, when the free cone-gap detector classifies each point, then the exact/inexact boundary renders as a map and both EXACT-04 controls reproduce | ✓ VALIDATED | socp, exactness, relaxation, parameter-sweep, figure, validity-envelope |

### Deferred (decomposed, then dropped as out of scope)

Spike 001 was originally decomposed into three spikes for a *bound-and-report* certified
welfare-optimality gap (bound direction, AC primal feasibility, multi-start monotonicity). The
actual ask was the visual map, so those were dropped before any code was written. They remain the
natural next spikes if the welfare-magnitude question is picked up — see
`.planning/notes/socp-validity-envelope.md` § Tier 2, which retains the four design decisions.
