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

> ⚠️ **THIRD-PASS CORRECTION (spike 002).** Tier 1 as written below is **not usable at default solver
> tolerance on a large feeder.** On real IEEE-123 (122 branches) Clarabel's cone residual at the default
> `tol_gap = 1e-8` is ~1e-6–5e-6 — the same size as the classifier's own `atol = 1e-6` — so 23 of 48
> swept points were flagged inexact by **noise**. Proven by tolerance ladder: worst ratio 4.76 → 0.0029
> at an identical optimum when `tol_gap` → 1e-10.
>
> WR-01 scales the threshold with quantity *magnitude*; it does **not** scale with solver *accuracy*, and
> accuracy degrades with problem size. Tier 1 therefore needs a step this brief never specified:
> **calibrate the solver noise floor per feeder and classify against that**, not against a fixed `rtol`.
> Naively tightening tolerance is not the fix — 2 of 3 discriminated points then fail `ALMOST_OPTIMAL`.
>
> Also from spike 002: on real IEEE-123 impedances the voltage upper bound is **never active**
> (`vpeak ≤ 1.016` vs caps ≥ 1.05), so the overvoltage mechanism the whole milestone is premised on does
> **not occur there**. See `.planning/spikes/002-ieee123-validity-map/README.md`.

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

### Tier 2: bound-and-report (certified welfare-optimality gap)

Because tier 1 finds the region for free, the AC oracle is **no longer needed to locate it**. Its job
narrows to quantifying *how much welfare is at stake* where the cone is slack — as a **certified
optimality gap**, not as an exactness verdict.

`solve_welfare` **maximizes** `Σ utility − λ₀ᵀ·p_import` (`src/models/welfare_solve.jl:67`), and the
SOCP relaxes the feasible set (`l·v ≥ P²+Q²` ⊇ `l·v == P²+Q²`). Larger feasible set + maximization ⇒

```
SOCP value  ≥  true global AC optimum  ≥  any AC-feasible point's value
    (upper bound)                              (lower bound)
```

`assert_ac_exact!` already computes the quantity: `obj_gap = objective_value(socp) −
objective_value(ac)` (`src/models/ac_oracle.jl:186`).

**Why this is the right FIRST measurement — the property that makes it unique here.** The certified
gap is valid **whether or not Ipopt found the global optimum.** A worse local optimum yields a
*looser* bound, never an invalid one; more starts only tighten it.

Every other measurement in this brief is contaminated by local optima — that is exactly why v2.1
needed a two-start guard on a single point, and why a precision/recall framing needs an
**inconclusive** cell. Bound-and-report is the only measurement in this space with **no
local-optimum caveat.** Do it first for that reason, not merely because it is cheap.

#### Four design decisions

1. **Normalization.** Welfare is `utility − import cost` and can sit near or across zero, so a bare
   relative gap `|ub−lb|/|lb|` is unsafe. Use the house WR-01 idiom
   (`atol + rtol·max(|ub|,|lb|)`) and report absolute **and** relative — never relative alone. Same
   trap `src/models/exactness.jl:48-55` already documents for cone slack on a 100 MVA base.
2. **AC feasibility must be verified, not assumed.** Ipopt's `LOCALLY_SOLVED` is not a feasibility
   certificate at publication tolerance. Check max violation on the true equality and the voltage
   bounds explicitly — an infeasible "lower bound" point makes the gap meaningless in the direction
   that matters.
3. **Multi-start is a pure win.** Best-of-N AC starts as the lower bound; no interpretive difficulty,
   unlike the exactness verdict.
4. **Do NOT weaken the PF-04 throw.** `assert_socp_exact!` refusing to price is a deliberate design
   choice. Add the gap as a *reported* quantity (mirroring how `assert_ac_exact!` reports rather than
   raises) so callers opt in. The ad-hoc version of this already exists — `rtol_exact = 1.0` at
   `test/test_ac_oracle.jl:181-187` — so this formalizes an existing pattern rather than inventing
   one.

#### What it buys, and what it does NOT

Buys: every result carries a certified welfare-optimality bound; the hard refusal inside the region
becomes a quantified caveat ("prices returned, welfare within X of global"); no new dependency.

**Does not buy:** any statement about whether the *prices* mean anything. A tight welfare gap with
meaningless prices is entirely possible — welfare is a scalar, prices are the duals. See
[[prices-as-duals-lapse]]; that question stays open.

#### How the two tiers compose

Cone gap (free, dense) says **where** to suspect. Bound-and-report (1..N AC solves, sparse) says
**how much welfare is at stake** there. They are complementary, not competing — a cleaner structure
than the precision/recall framing in the first draft of this brief.

## Deliverables

Ordered by dependency. The first two are spike-sized and gate everything after them.

1. **Certified welfare-optimality gap** (`welfare_bounds`) — bound-and-report per tier 2. No
   local-optimum caveat, no new dependency; ships independently of the rest of this brief.
   **Chosen as the first move.**
2. `socp_gap_report` — non-throwing cone-gap accessor, so sweeps record instead of aborting
3. The opening-question answer: do cone slackness and the Phase 18-01 fragility coincide?
4. Resolve the [[export-tightness-claim-contradiction]] — a live inconsistency in shipped code
5. 3D envelope over the axes above (free tier) + a publication figure (CairoMakie)
6. Binding-set diagnostic as the **interpretive** layer tying the region to the literature conditions
7. Every experiment result stamped inside/outside the envelope, with its certified gap
8. The theoretical claim written up — see [[prices-as-duals-lapse]], contingent on the prior-art check

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

### 🛑 PREREQUISITE — RESOLVED by spike 003: THE GATE'S PREMISE DOES NOT HOLD

The test is done. See `.planning/spikes/003-phase18-fragility-tolerance/README.md`.

**Phase 18-01's fragility is not a physical boundary.** Re-running the identical ±2–5% sweep with the
shipped gate armed and only the *solver* tolerance tightened:

- `solve_welfare`'s SOCP gate: **2/5 threw at default → 0/5 at `tol_gap = 1e-10`**, at optima agreeing
  to 6–7 significant figures. Purely numerical.
- `dadp_dso` across the band: **2.7098 → 3.2775 → 3.7257 → 4.1639 → 4.8074** — strictly positive,
  smooth, **monotone**. No knife edge in this quantity at all.
- **The sign flip survives δ = −0.05** (`dadp_dso = +2.71`, `fit_dso = −182.96`), a point the committed
  findings record as failing outright.
- 2 of the 4 recorded failures were **`fit_baseline`**, misattributed to `solve_welfare` because
  Phase 18-01 wrapped three solves in one try/catch. Ratios bit-identical to 16 digits — nothing flaky.

**Consequences for this milestone.** The overvoltage/binding-cap mechanism this brief is built on does
not occur on real IEEE-123 impedances (spike 002: bound never active), and the fragility that motivated
mapping its boundary was a tolerance artifact (spike 003). **The premise of the pre-registered gate
below — that there is a reachable inexact region to bound — is not supported on real public data.**

v3.0 should be re-scoped around what the spikes actually surfaced, which is a *measurement-hygiene*
problem, not a relaxation-theory problem:

1. Per-feeder solver-noise-floor calibration before any residual-based classification.
2. An `optimizer` kwarg on `fit_baseline` (`src/pricing/fit.jl:271`) — the blocking defect leaving 3/5
   sweep points unmeasurable.
3. Correcting the shipped `sign_flip_survives: false` claim in findings.txt, 18-01-SUMMARY.md, and the
   published assumptions literate page.
4. Re-deriving Plan 18-02's golden band — **CLOSED by quick task `260823-gea`**:
   `DSO_BAND_HI` re-pinned from `5.58855710237937` to **`7.211125525764296`**. The original
   "`1.5 × max|dso|` implies 7.211" framing was projected from an assumption that all 5 sweep
   points solve cleanly at `tol_gap=1e-10` — which `260823-gea` refuted: `solve_welfare`'s
   SOCP-exactness gate does resolve 5/5, but `fit_baseline`'s own nested solve returns
   `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` at 3 of 5 points (flake rate 13/20 = 0.650, all 13
   at that stage, reproduced across 3 runs), so only 2/5 points fully confirm the sign flip.
   The band was nevertheless re-derivable, via a different and stronger argument: the rule ranges
   over `dso`, produced by `solve_welfare` + `welfare_accounting`, while `fit_baseline` yields
   only `fit_dso` (needed for the sign-flip check, not for the band). `repro_stability_check.jl`
   had conflated these — gating the band on all-three-stages success AND discarding `acct.dso`
   as `NaN` on any `fit_baseline` throw. Both fixed in `260823-gea`; `dso` is trustworthy at 5/5
   points, so `1.5 × 4.807417 = 7.211125525764296` now comes out of the fixed script's own
   `RECOMMENDED BAND:` line. Same number as the old projection, sound derivation. The band
   widens; `DSO_BAND_LO = 0.0` and all other assertions unchanged; the pinned point
   (`|dso| = 3.7257`) is inside both bands, so no verdict moves. The `fit_baseline`-convergence
   problem is NOT closed by this and remains a live, separately-tracked numerical finding.

The 3-bus overvoltage inexactness (EXACT-04) remains real and reproducible — it is a property of that
stress fixture, not of real feeders at these scales.

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
