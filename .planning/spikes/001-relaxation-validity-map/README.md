---
spike: 001
name: relaxation-validity-map
type: standard
validates: "Given a (pv_scale × load_scale × vmax) grid on the high-PV fixture, when the free cone-gap detector classifies each point, then the exact/inexact boundary is visible as a map and reproduces both known EXACT-04 control points"
verdict: VALIDATED
related: []
tags: [socp, exactness, relaxation, parameter-sweep, figure, validity-envelope]
---

# Spike 001: Relaxation Validity Map

## What This Validates

**Given** a `(pv_scale × load_scale × vmax)` grid on the 3-bus high-PV fixture, **when** each point
is classified by the cone-gap ratio that `src/models/exactness.jl:8` already computes for free,
**then** the exact/inexact boundary renders as a map — and both known EXACT-04 control points
reproduce.

Origin: `.planning/notes/socp-validity-envelope.md`. The user asked for a visual map of where the
relaxation works; this is that, and nothing more. **No AC/Ipopt oracle is involved anywhere.**

## Research

No external research needed — no new dependencies. Everything used is already exported from `src/`
(`solve_welfare`, `ConvexBranchFlow`, `Bus`/`Branch`/`Feeder`, `generate_profiles`, the device
constructors) plus `CSV`/`DataFrames`/`CairoMakie`, all already in `Project.toml`.

Two existing in-tree facts made the spike cheap:

1. **The detector already exists.** `src/models/exactness.jl:8` computes
   `gap[b,t] = |l·v − (P²+Q²)|` with the scale-free WR-01 bound. Free off the SOCP solve. No proxy
   heuristic was needed (an earlier draft of the v3.0 brief proposed one — wrong architecture).
2. **The gate can be neutralized without touching `src/`.** `rtol_exact` is already a `solve_welfare`
   kwarg used diagnostically at `test/test_ac_oracle.jl:181-187`. Passing `rtol_exact = 1e6` returns
   the inexact solve for classification instead of refusing it. **Zero `src/` changes.**

## How to Run

```bash
julia --project=. .planning/spikes/001-relaxation-validity-map/sweep.jl      # ~150 SOCP solves
julia --project=. .planning/spikes/001-relaxation-validity-map/plot_map.jl   # reads sweep.csv
```

Outputs: `sweep.csv`, `validity-map.png`, `validity-map.pdf`.

## What to Expect

150 points classified into four categories; a printed controls block that must show
`EXACT ✓` / `INEXACT ✓`; and a two-row faceted figure.

## Investigation Trail

### Iteration 1 — swept the wrong network, and it silently "passed"

First attempt swept `ieee13_modified()` with the calibrated residential scales
(`materialize.jl:121-123`) as multipliers: `pv_mult ∈ [0.5, 8.0]`, `load_mult ∈ [0.9, 1.1]`.

Result: **111/111 solved points EXACT, zero inexact.** Which looked like a clean answer and was
worthless. Two tells gave it away:

- `min_branch_P ≈ −0.0679` **constant** from `pv×0.5` to `pv×8.0`. Scaling PV 16× moved reverse flow
  not at all.
- `n_at_vmax = 0` at every one of the 111 points — the upper voltage bound never came close.

The PV was not reaching the network. Had this been reported as "the relaxation is exact everywhere,"
it would have been a fabricated finding built on an inert fixture.

**Cause:** `ieee13_modified()` is the wrong substrate. The EXACT-04 regime lives on
`Phase4Fixtures.high_pv_feeder()` (`test/fixtures_phase4.jl:184`) — a *purpose-built 3-bus* fixture
with low-impedance `r = x = 0.05` branches ("back-feed swings voltage fast") and `load_scale = 0.2`.
IEEE-13's impedances barely move voltage at these magnitudes.

**Lesson, now enforced:** the grid must contain a known-inexact **positive control**. A sweep that
cannot reproduce the one point already proven inexact cannot be trusted when it reports "all exact" —
that outcome is indistinguishable from a fixture where the mechanism cannot fire.

### Iteration 2 — correct substrate, controls pass

Replicated `high_pv_feeder()` + the `_house_aggregator` recipe (`fixtures_phase4.jl:118`) locally
(the originals live in a TestItems `@testmodule`, unreachable from a plain script). Verified the
temperature and MEM-price profiles byte-for-byte against `Phase4Fixtures`.

Controls, both reproduced:

| control | expected | got | ratio | vpeak |
|---|---|---|---|---|
| `pv=0.5, load=0.2, vmax=1.05` | EXACT | **EXACT ✓** | 0.0027 | 1.0399 |
| `pv=1.2, load=0.2, vmax=1.05` | INEXACT | **INEXACT ✓** | 9609 | 1.0500 |

`vpeak = 1.0399` matches the fixture docstring's documented "≈1.04 pu" exact regime independently.

### Iteration 3 — split the non-solved points

41/150 points did not solve. Merging them into one colour would have been dishonest, so each failure
message is now captured and classified. They are **two physically different things**:

- **30 `infeasible`** — all at `load_scale = 0.4`. Genuine `INFEASIBLE` with a dual infeasibility
  certificate: the 3-bus fixture cannot serve that load inside `vmin = 0.95`. Legitimate white space,
  not a measurement failure.
- **11 `guard`** — `assert_battery_complementarity!` trips (`p_ch·p_dch` above the relative-τ bound).
  These are **genuinely unmeasured** and rendered amber, never as a verdict.

## Results

**Verdict: VALIDATED.** The map exists, the boundary is sharp, and both controls reproduce.

`43 exact · 66 inexact · 30 infeasible · 11 guard-tripped (unmeasured)`

### Finding 1 — voltage headroom is the first-order control; load is second-order

Largest `pv_scale` still exact:

| load_scale | vmax=1.05 | vmax=1.075 | vmax=1.10 |
|---|---|---|---|
| 0.10 | 0.5 | 0.7 | 1.0 |
| 0.15 | 0.5 | 0.7 | 1.0 |
| 0.20 | 0.5 | 0.7 | 1.0 |
| 0.30 | 0.7 | 0.9 | 1.1 |
| 0.40 | — (infeasible) | — | — |

Each `+0.025` pu of headroom buys `≈ +0.2` of `pv_scale`, near-linearly. Load moves the boundary by
at most one grid step across its whole swept range.

**Consequence for the v3.0 pre-registered gate:** the gate's sensitive axis is `vmax`, *not*
`population_scale`. The worry logged in `socp-validity-envelope.md` about the `[0.98, 1.02]` window
being too narrow is largely moot — at this fixture's resolution, load barely matters. Promoting
`vmax` to a first-class axis was the right call, and for a stronger reason than anticipated.

### Finding 2 — the binding-set predicate has ZERO false negatives here

Predicate = "upper voltage bound active at ≥1 `(bus,hour)`" vs. cone inexactness, over 109 solved
points:

|  | inexact | exact |
|---|---|---|
| bound active | **66** (TP) | 4 (FP) |
| bound inactive | **0 (FN)** | 39 (TN) |

Recall **66/66 = 100%**, precision 66/70 = 94%. **The dangerous cell is empty** — the predicate never
missed an inexact point. That is the good outcome for
[[../../research/questions.md — Q1]], which flagged recall as the load-bearing risk.

All 4 false positives sit exactly *on* the boundary (`vpeak == vmax` to 5 digits, `n_at_vmax == 1` —
the bound just touched at a single bus-hour). A refined predicate (bound active at ≥2 bus-hours, or a
shadow-price threshold) would plausibly be perfect. Not tested.

### Finding 3 — the transition is a cliff, not a gradient

Max ratio among exact points: **0.024**. Min ratio among inexact points: **8.45**. A **~350× empty
band**, with no point inside it.

So the boundary's *position* is completely insensitive to where the threshold is placed — anything
from 0.03 to 8 yields the identical map. The knife-edge is in **parameter space**, not in the
measurement. This makes the map far more defensible than expected: a reviewer cannot move the
boundary by arguing about tolerance.

### Finding 4 — reverse flow alone does NOT predict inexactness

`min_branch_P < 0` at **every one of the 109 solved points**, including all 43 exact ones. Reverse
flow is necessary-but-not-sufficient; the *binding upper voltage bound* is the discriminator.

This refines the v2.1 narrative, which frames the failure mode as "high-PV reverse flow." Reverse
flow is the setting; the binding cap is the cause. Consistent with the mechanism stated at
`test/fixtures_phase4.jl:213-216` — once voltage is pinned at `V²max` the surplus can no longer
leave, so the solver dumps it into a fictitious loss current.

### Finding 5 (hypothesis) — the guard trips may be a second symptom of the same pathology

The 11 `assert_battery_complementarity!` failures cluster at high-PV/low-load — inside or adjacent to
the inexact region, not scattered randomly. Simultaneous charge+discharge is *also* a fictitious sink
for surplus energy, structurally the same pathology as slack `l`.

**Not tested.** If true, the complementarity guard is an independent detector of the same condition,
which would be a useful cross-check. Flagged, not claimed.

## Honest Limits

1. **One synthetic fixture.** A 3-bus purpose-built stress substrate. Iteration 1 proved these
   numbers do **not** transfer to `ieee13_modified()`, and nothing here speaks to real IEEE-123
   impedances. The *method* generalizes; the *boundary values* do not.
2. **`pv_scale`/`load_scale` are fixture-relative, not physical.** They are dimensionless multipliers
   on a seeded synthetic profile. No mapping to PV penetration % exists — the units defect logged in
   `socp-validity-envelope.md` § gate is **not** fixed by this spike.
3. **"Inexact" means cone-slack, not welfare-wrong.** This is the relaxation's own self-report. No AC
   oracle ran, so the map says nothing about how much welfare or how wrong the prices are. That is
   bound-and-report, still unbuilt.
4. **11/150 points unmeasured** (amber). Not swept around, not resolved.
5. **Grid resolution is coarse.** The boundary is located to within one grid step; it was not refined.
