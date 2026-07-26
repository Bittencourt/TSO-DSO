---
title: SOCP Validity Envelope — v3.0 milestone brief
date: 2026-07-26
context: Exploration session between milestones (post-v2.1). Candidate scope for v3.0.
status: brief — not yet a milestone
---

# SOCP Validity Envelope — v3.0 milestone brief

> **Status note (2026-07-26, second pass):** the method section below was corrected after discovering
> that `src/models/exactness.jl` already computes the cone gap for free. The original two-tier plan
> over-engineered a heuristic predicate to stand in for an oracle that was never needed for
> detection. The milestone is **smaller** than first scoped. Two items remain open pending the
> researcher's judgement, both flagged inline: the gate's units (§ Pre-registered decision gate) and
> the exactness mechanism (§ Tier 1b).

## Why

v2.1 landed two findings that **may or may not** be one finding — see § Opening question:

1. The radial SOCP branch-flow relaxation is **genuinely inexact** under high-PV reverse flow
   (IEEE-13 `pv_scale=1.2`, obj gap ≈ 10.4, voltage pinned at V²max; independently re-hit on real
   IEEE-123 impedances in Phase 17).
2. The thesis DSO-surplus sign-flip reproduction is **knife-edge fragile** — it fails a ±2–5%
   population-scale sweep, *because the SOCP-exactness gate itself throws near that boundary*.

## Opening question — test this BEFORE anything else

Finding 2's fragility is plausibly a symptom of finding 1's boundary, but **this is a hypothesis, not
a result**, and an earlier draft of this brief wrongly carried it as motivating premise. If the
fragile population points have a different cause than the exactness boundary, much of the milestone's
rationale weakens — so it is the first thing to measure, not an assumption in the preamble.

**The test needs zero AC solves.** Sweep, recording `maxratio` from the free cone gap (tier 1), and
ask: are the Phase 18-01 fragile population points exactly the points where `maxratio > 1`? Sized as
a spike, not a phase. Everything downstream in this brief is contingent on its answer.

Today the framework's answer
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

## Two distinct exactness notions — do not conflate them

An earlier draft of this brief slid between these. They are different measurements answering
different questions, and the whole cost structure depends on keeping them apart:

| | what it measures | cost | status in tree |
|---|---|---|---|
| `assert_socp_exact!` | cone slack **within** one SOCP solve: `l·v > P²+Q²` | **free** | exists, **throws** |
| `assert_ac_exact!` | SOCP optimum **vs** an independent AC optimum | 1 nonconvex Ipopt solve (×2 for multi-start) | exists, reports |

Phase 18-01's sign-flip fragility was caused by the **first** one throwing. EXACT-04's
`pv_scale = 1.2` finding was the **second** one. Whether those are the same phenomenon is the
milestone's opening question, not its premise.

## Method — corrected

### Tier 1: the cone gap itself (dense grid, free)

`src/models/exactness.jl:8` already computes, per branch and hour:

```
gap[b,t] = |value(l[b,t])·value(v[from_b,t]) − (P² + Q²)|
```

scale-free (`|gap| ≤ atol + rtol·max(|l·v|, |P²+Q²|)`, WR-01), at zero cost beyond the SOCP solve.
Its header comment (line 68) already records that the over-voltage failure mode "has an O(1)
relative gap and is caught."

**This is the detector.** An earlier draft of this brief proposed a binding-set *heuristic* as a
cheap proxy for the AC oracle — that was wrong architecture: an exact, free measurement of the
relaxation gap was already in the tree. Do not rebuild it.

Only new code needed: a **non-throwing** accessor (`socp_gap_report`, mirroring how
`assert_ac_exact!` reports rather than raises) so a sweep can record `maxgap`/`maxratio` per point
instead of aborting at the first inexact one.

### Tier 1b: the binding-set diagnostic (explainer, not detector)

Voltage limits are plain JuMP **variable bounds**, not named constraints:

```julia
set_upper_bound(v[j, t], vb.vmax^2)      # src/powerflow/ConvexBranchFlow.jl:142
```

So these are also free: bound active → `value(v[j,t]) ≈ vmax^2`; shadow price →
`reduced_cost(v[j,t])`; reverse flow → `value(P[b,t]) < 0`.

Their job is **interpretation**, not detection: they connect the measured region to the
Farivar & Low (2013) / Gan et al. (2015) sufficient conditions, which turn on upper voltage bounds
and objective monotonicity in branch flow. `src/models/ac_oracle.jl:127` already names this
diagnosis — "reverse-flow / voltage-binding state" — and never computes it. That docstring is the
seam.

⚠️ **Unverified:** the precise mechanism by which a binding upper bound plus reverse flow makes
inflated `l` attractive to the optimizer has NOT been derived here. The characterization of the
Farivar–Low / Gan et al. conditions above is a recollection needing a source check. Pin the exact
condition before the interpretive claim goes anywhere near a paper.

### Tier 2: AC oracle (few points, different question)

Because tier 1 finds the region for free, the AC oracle is **no longer needed to locate it**. Its
job narrows to: *where the cone is slack, how wrong are the prices and the dispatch?* — welfare
error magnitude and implementability of the SOCP optimum. Far fewer points than a boundary-hunting
subsample.

**Cost caveat:** this is not one Ipopt solve per point. v2.1 needed a two-start comparison to rule
out a local-optimum artifact on a *single* point, so budget ≥2× — and some points will return
**inconclusive** rather than exact/inexact. Any precision/recall framing needs a cell for that;
neither draft of this brief had one.

## Deliverables

- `socp_gap_report` — non-throwing cone-gap accessor, so sweeps record instead of aborting
- The opening-question answer: do cone slackness and the Phase 18-01 fragility coincide?
- 3D envelope over the axes above (free tier) + a publication figure (CairoMakie)
- Binding-set diagnostic as the **interpretive** layer tying the region to the literature conditions
- AC-oracle magnitude study on a small point set: how wrong are prices where the cone is slack
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
standard voltage band is grid-choice independent.

### ⚠️ TWO DEFECTS IN THIS GATE — resolve before it is honoured

**1. `pv_scale ≤ 1.0` is not stated in physical units.** The gate was originally justified as "PV
penetration a utility would plan for." That justification is **not supported by the code.**
`pv_scale` has two different meanings in the tree:

- `src/experiments/materialize.jl:122,128` — `_IEEE13_PV_SCALE = 0.03`, `_IEEE123_PV_SCALE = 0.06`:
  absolute per-unit magnitude constants, on *different* bases (100 MVA vs 1 MVA, see the comment at
  `materialize.jl:111-114`)
- `test/fixtures_phase4.jl:230` — a caller-tunable multiplier on the high-PV stress fixture, default
  `0.5` (documented at line 209 as "the documented EXACT regime"); EXACT-04 used `1.2`
  (`test/test_ac_oracle.jl:178`)

Neither is a penetration ratio. There is no mapping anywhere in the repo from `pv_scale` to
"% of feeder peak served by rooftop PV," so a reviewer asking "is `pv_scale = 1.0` a lot?" has no
answer. Two ways out, researcher's call: **(a)** build the penetration mapping (PV nameplate ÷ feeder
peak load) and restate the gate in those units — defensible externally, more work; **(b)** restate
the gate in fixture-relative terms and drop the utility-planning language — cheap and honest, but
weaker as an external claim.

*(Numerically the threshold is not absurd: `0.5` is documented exact and `1.2` inexact on that
fixture, so `≤ 1.0` sits inside the interval where the boundary already lives. It simply does not
mean what the original justification said.)*

**2. `population_scale ∈ [0.98, 1.02]` contradicts the measurement it responds to.** Phase 18-01
measured the sign flip breaking under **±2–5%** perturbation. This window is the *inner edge* of that
band. If inexactness bites at 3–5% but not 2%, the gate reads NARROW while the documented fragility
is entirely untouched. Either widen to ±5%, or state explicitly that the gate deliberately tests a
stricter condition than Phase 18-01 observed.

## Open questions for /gsd:new-milestone

- Does the envelope need to be per-feeder, or is there a normalization that collapses IEEE-13 and
  IEEE-123 onto one picture?
- Does the validity stamp belong in the DrWatson result dict, the `ModelContext`, or both?
- Should the predicate ever *warn* (not throw) when a solve lands inside the envelope, given
  `assert_socp_exact!` already throws downstream?
