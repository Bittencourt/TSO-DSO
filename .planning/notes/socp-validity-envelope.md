---
title: SOCP Validity Envelope — v3.0 milestone brief
date: 2026-07-26
context: Exploration session between milestones (post-v2.1). Candidate scope for v3.0.
status: brief — not yet a milestone
---

# SOCP Validity Envelope — v3.0 milestone brief

## Why

v2.1 landed two findings that are probably one finding:

1. The radial SOCP branch-flow relaxation is **genuinely inexact** under high-PV reverse flow
   (IEEE-13 `pv_scale=1.2`, obj gap ≈ 10.4, voltage pinned at V²max; independently re-hit on real
   IEEE-123 impedances in Phase 17).
2. The thesis DSO-surplus sign-flip reproduction is **knife-edge fragile** — it fails a ±2–5%
   population-scale sweep, *because the SOCP-exactness gate itself throws near that boundary*.

Finding 2's fragility is plausibly a symptom of finding 1's boundary. Today the framework's answer
inside that region is *nothing*: `assert_socp_exact!` throws rather than return physically
meaningless prices. That refusal is the correct engineering call and also a real hole — the invalid
region is high-PV reverse flow with voltage at the upper bound, i.e. precisely the operating regime
that motivates transactive distribution pricing in the first place.

**Goal:** turn an unmapped knife edge into a measured, citable validity envelope, and stamp every
downstream result as inside or outside it.

## Scope decision (locked in this session)

**Map only. Remediation deferred behind a pre-registered gate** — see
[[overvoltage-capable-relaxation]] (seed) for the trigger.

Rationale: the map is cheap and low-risk with machinery that already exists; the remediation
(overvoltage-capable relaxation, or an AC-dual pricing path) is a new research axis with genuine
risk of ending in a negative result. Look at the actual map before making that bet.

## Axes

```
pv_scale          0.0 … 1.5
population_scale  0.95 … 1.05      (brackets the ±2–5% knife edge from Phase 18-01)
vmax              1.05 / 1.075 / 1.10
```

Held fixed: feeder topology, **real** IEEE-123 impedances (Phase 17), T=24.

**Why `vmax` is an axis and not a fixture constant.** The two feeders do not share a voltage band:

- `src/data/ieee13.jl:89` — `vmin, vmax = 0.95, 1.05`
- `src/data/ieee123.jl:420` — `vmin, vmax = 0.9, 1.1` (thesis Case B band)

If binding-at-V²max is the governing condition (it is, per the sufficient conditions we already
cite), band width may be most of why the two feeders behave differently. Promoting it to an axis
also converts a buried fixture constant into an explicit, stated modeling assumption.

## Method — two tiers

### Tier 1: the free predicate (dense grid)

Voltage limits are plain JuMP **variable bounds**, not named constraints:

```julia
set_upper_bound(v[j, t], vb.vmax^2)      # src/powerflow/ConvexBranchFlow.jl:142
```

So the binding-set diagnostic costs nothing beyond the SOCP solve already being done:

- upper bound active at bus `j`, hour `t` → `value(v[j,t]) ≈ vmax^2`
- its shadow price → `reduced_cost(v[j,t])`
- reverse flow on branch `b` → `value(P[b,t]) < 0`

This is exactly what the Farivar & Low (2013) / Gan et al. (2015) sufficient conditions are about:
exactness holds when upper voltage bounds do not bind and the objective stays monotone in branch
flow. `src/models/ac_oracle.jl:127` already *names* the diagnosis — "reverse-flow / voltage-binding
state" — it simply never computes it. That docstring is the seam.

Because tier 1 is free, it can sweep the full 3D grid.

### Tier 2: AC-verified subsample (boundary only)

`assert_ac_exact!` (`src/models/ac_oracle.jl:148`) certifies inexactness properly but needs a full
nonconvex Ipopt AC solve per point — the cost that makes a dense grid painful. Use it on a sparse
subsample near the predicted boundary to measure the predicate's **precision and recall**, not to
assume them.

## Load-bearing risk — predicate recall

The predicate's *recall* is the milestone's central measurement risk. If binding-at-V²max is
necessary-but-not-sufficient in practice — inexact points the free predicate misses — then the
cheap dense sweep **undercounts** the region and the pre-registered gate reads NARROW for the wrong
reason.

Consequence for design: the AC subsample must be chosen to **hunt false negatives** (points the
predicate calls exact), not merely to confirm true positives. A subsample drawn only from
predicate-flagged points cannot measure recall at all. See
[[research/questions.md — Q1]].

## Deliverables

- Binding-set predicate computed on every SOCP solve (free, always on)
- Measured precision/recall of the predicate against the AC oracle
- 3D envelope over the axes above + a publication figure (CairoMakie)
- Every experiment result stamped inside/outside the envelope
- The theoretical claim written up — see [[prices-as-duals-lapse]]

## Pre-registered decision gate

Written to REQUIREMENTS.md **before the sweep runs**, so the verdict cannot be rationalized after
seeing the map (cf. the v2.0 "measure, don't assume" blocker):

```
WIDE  ⇔ ∃ inexact point with   vmax ≤ 1.05
                             ∧ pv_scale ≤ 1.0
                             ∧ population_scale ∈ [0.98, 1.02]

else NARROW
```

WIDE → v3.1 remediation milestone. NARROW → document the envelope, move to the next research axis
(stochastic, MPC/RTP, meshed+4Q-BESS).

**Why reachability and not grid-volume fraction.** "12% of swept points are inexact" is an artifact
of where the sweep bounds were chosen, and a reviewer can move those bounds. Reachability at a
standard band under utility-plannable PV penetration is grid-choice independent and physically
meaningful.

## Open questions for /gsd:new-milestone

- Does the envelope need to be per-feeder, or is there a normalization that collapses IEEE-13 and
  IEEE-123 onto one picture?
- Does the validity stamp belong in the DrWatson result dict, the `ModelContext`, or both?
- Should the predicate ever *warn* (not throw) when a solve lands inside the envelope, given
  `assert_socp_exact!` already throws downstream?
