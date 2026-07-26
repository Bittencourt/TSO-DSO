---
title: Overvoltage-capable relaxation (or AC-dual pricing path)
planted_date: 2026-07-26
trigger_condition: >
  v3.0 envelope sweep completes AND the pre-registered gate reads WIDE, i.e. there exists a
  measured-inexact point with vmax <= 1.05 AND pv_scale <= 1.0 AND population_scale in [0.98, 1.02].
status: dormant
---

# Overvoltage-capable relaxation (or AC-dual pricing path)

## Trigger — pre-registered, do not renegotiate after seeing the map

This seed germinates **only** if the v3.0 envelope sweep ([[socp-validity-envelope]]) yields:

```
WIDE  ⇔ ∃ measured-inexact point with   vmax ≤ 1.05
                                      ∧ pv_scale ≤ 1.0
                                      ∧ population_scale ∈ [0.98, 1.02]
```

If the gate reads NARROW: document the envelope, leave this seed dormant, and move to the next
research axis (stochastic, MPC/RTP, meshed+4Q-BESS).

The rule was fixed **before** the sweep ran, deliberately, so that "the region turned out narrow"
cannot become a judgment made while looking at the preferred answer. Compare the v2.0
"measure, don't assume" blocker. If the rule needs changing, change it *and say so in writing* —
do not quietly reinterpret it.

**Caveats that can legitimately reopen the gate** — all measurement objections, not preferences:

1. **The free detector misses invalid points.** If Q1(3) finds points with a *tight* cone but
   measurable AC disagreement, the dense sweep undercounts the region and a NARROW verdict is an
   artifact. See [[../research/questions.md — Q1]].
2. **The gate's own units are unresolved.** `pv_scale ≤ 1.0` is not stated in physical units and has
   two conflicting meanings in the tree — this gate CANNOT be honoured until that is fixed. See the
   two flagged defects in [[socp-validity-envelope]] § Pre-registered decision gate.
3. **The population window may be mis-specified.** `[0.98, 1.02]` sits at the inner edge of the
   ±2–5% band where fragility was actually measured. If it stays this narrow, the gate can read NARROW
   while the documented fragility is untouched.

Defects 2 and 3 mean the gate as written is **not yet honourable**. Fix them before the sweep runs,
not after — the whole point of pre-registration is lost if the rule is repaired once the answer is
visible.

## What germination would mean

Roughly a v3.1 milestone, ~4–5 phases, with real risk of a negative result. Two candidate
directions, not mutually exclusive:

### A. Overvoltage-capable formulation

Tighten the relaxation so it stays exact (or provably near-exact) with upper voltage bounds active.
Starting points to research at germination time, none yet validated:

- Additional valid inequalities / cuts that restore the exactness conditions under reverse flow
- The tightenings in the Gan et al. (2015) line of work and successors
- Convex-concave / penalty schemes that drive `l·v → P²+Q²` — note these forfeit the single-convex-
  solve property, which is load-bearing for the ADMM decomposition and for prices-as-duals

**Constraint:** whatever lands must preserve the residual-seam contract
(`AbstractPowerFlow` + `ctx.residuals`) so the ADMM and planning layers are untouched.

### B. Documented AC-dual pricing path

Return AC-oracle multipliers inside the region, explicitly and permanently labelled *local-optimum
duals, not market-clearing prices*, plus a comparison of what the SOCP and AC prices disagree about.
Cheaper than A and honest, but it does **not** repair the theoretical claim in
[[prices-as-duals-lapse]] — it documents the gap rather than closing it. Do not let it be presented
as a fix.

## Why this is deferred rather than declined

The hole is real and sits in the operating regime that motivates the whole research programme. But
the cost/benefit depends entirely on whether real feeders at standard voltage bands actually reach
it — which is exactly what v3.0 measures. Spending 4–5 phases on a remediation for an unreachable
region would be the expensive mistake; so would documenting a reachable one and moving on.
