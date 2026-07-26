---
spike: 002
name: ieee123-validity-map
type: standard
validates: "Given the spike-001 method applied to real IEEE-123 OpenDSS impedances, when the free cone-gap detector classifies a (pv × load × vmax) grid, then the exact/inexact boundary renders as a map"
verdict: PARTIAL
related: [001]
tags: [socp, exactness, relaxation, parameter-sweep, ieee123, real-impedances, null-result, tolerance, solver-noise]
---

# Spike 002: IEEE-123 Validity Map

## What This Validates

Same method as [spike 001](../001-relaxation-validity-map/README.md), different substrate:
`ieee123_modified()` — 123 buses / 122 branches / 85 load nodes, non-switch impedances from the
public IEEE-123 OpenDSS test case, positive-sequence Fortescue-reduced (`src/data/ieee123.jl:23-24`).

**Verdict: PARTIAL.** The sweep ran and a map rendered — but the map is of **solver noise, not
physics**. There is no exactness boundary on real IEEE-123 impedances in the swept region, and the
cells that classify "inexact" are interior-point convergence artifacts. The valuable output is a
**defect in the method**, not a boundary.

## How to Run

```bash
julia --project=. .planning/spikes/002-ieee123-validity-map/sweep.jl          # 54 pts, ~16 min
julia --project=. .planning/spikes/002-ieee123-validity-map/discriminator.jl  # tolerance ladder
julia --project=. .planning/spikes/002-ieee123-validity-map/plot_map.jl
```

Axes are **multipliers** on the Phase-17-retuned population point (`load 0.05 / pv 0.12`, seed
`20260719`, `docs/literate/thesis_reproduction_ieee123.jl:49-52`) — the point the thesis-reproduction
page and Phase 18-01 actually use, **not** the older `0.03/0.06` in `src/experiments/materialize.jl`.

## Results

`25 ratio ≤ 1 · 23 flagged ratio > 1 · 6 guard-tripped` — 48 solved of 54, 15.9 min wall.

**Positive control passed:** the thesis-reproduction point (`pv×1.0, load×1.0, vmax=1.10`) classifies
exact, `ratio = 0.217`, `vpeak = 1.0105`.

### Finding 1 — NULL RESULT: no structural inexactness, and no overvoltage at all

**The voltage upper bound is never active at any of the 48 solved points.** `vpeak` spans
**0.99969 – 1.0158** against caps of 1.05 / 1.075 / 1.10. Across a 5.5× PV range (`×0.4` → `×2.2`)
peak voltage moves 0.9998 → 1.0158.

Spike 001's whole mechanism — back-feed pins voltage at `V²max`, surplus can no longer leave, solver
dumps it into fictitious `l` — **cannot fire here.** Real IEEE-123 impedances (`r ∈ [0.0003, 0.0102]`,
`x ∈ [0.00015, 0.0103]`) are 5–35× lower than the 3-bus fixture's uniform `r=x=0.05`, so back-feed
barely swings voltage. Reverse flow is large and constant (`minP ≈ −3.5`) and causes no exactness
problem whatsoever, re-confirming spike 001's Finding 4 on an independent substrate.

### Finding 2 — METHOD DEFECT: the detector's default tolerance sits at the solver's noise floor

The 23 "inexact" flags are artifacts. Three independent lines of evidence:

**(a) Tolerance ladder — conclusive.** Worst point in the sweep (`vmax=1.05, load×1.05, pv×0.7`):

| tol_gap | ratio | maxgap | vpeak | objective |
|---|---|---|---|---|
| `1e-8` (project default) | **4.7604** | 5.116e-6 | 1.00025 | −41141.35221 |
| `1e-10` | **0.0028505** | 6.536e-9 | 1.00025 | −41141.35214 |

Ratio collapses **1670×** at an *identical optimum* (objective agrees to 7 digits, `vpeak` to 6). A
structural relaxation gap is a property of the optimum and cannot shrink under tolerance tightening.

**(b) Inactive-constraint sensitivity.** At `pv×1.0, load×1.0` — identical `vpeak = 1.01` and
`minP = −3.507` at all three `vmax`, bound inactive in all three:

| vmax | ratio | class |
|---|---|---|
| 1.050 | 1.727 | flagged |
| 1.075 | 0.293 | ok |
| 1.100 | 0.217 | ok |

Moving an **inactive** bound cannot change the optimum, yet the ratio moves 5.9×. And the direction is
random: at `pv×2.2, load×1.05` the same `1.05 → 1.075` change moves the ratio *up* 1.7× (1.181 →
1.973).

**(c) No spatial structure.** Flags are salt-and-pepper, non-monotone in every axis, including at the
**lowest** PV swept (`×0.4`, ratio 4.09). No physical relaxation-gap mechanism produces that.

**The mechanism.** Clarabel's achievable cone residual on this 122-branch problem at
`tol_gap = 1e-8` is ~1e-6 – 5e-6. The classifier bound is `atol + rtol·magnitude` with
**`atol = 1e-6`** (`src/models/exactness.jl`). On low-magnitude branches the bound *is* ~1e-6 while
the noise is ~5e-6 ⇒ ratio ≈ 5. The threshold is being compared against the noise floor.

The WR-01 idiom scales the threshold with *quantity magnitude*. It does **not** scale with *solver
accuracy*, and accuracy degrades with problem size. On 3 buses structural gaps were 1e3–1e4, far
above any floor; on 122 branches the floor has risen into the threshold.

### Finding 3 — spike 001's Findings 2 and 3 do NOT generalize

- **Zero false negatives (001 Finding 2): dead.** Point 9 here is flagged inexact with the bound
  inactive. Recall was 100% on 3 buses because inexactness there was structural and always
  bound-driven; here the flags aren't structural at all.
- **The cliff / ~350× empty band (001 Finding 3): dead.** 001 spanned ratios 0.0008 → 9609 with
  nothing between 0.024 and 8.45. Here everything sits in **0.055 – 4.76**, straddling the threshold
  continuously. Threshold placement fully determines the map.

Both were substrate-specific. Reporting them as general properties in 001 was an over-generalization
from a single synthetic fixture.

### Finding 4 (HYPOTHESIS, high stakes) — this may explain v2.1's "knife-edge fragility"

`assert_socp_exact!` ships with `rtol = 1e-4`, `atol = 1e-6`, and it **throws**. At default solver
tolerance on IEEE-123 that gate would fire spuriously on roughly **half** the operating points swept
here.

Phase 18-01 reported that the thesis DSO-surplus sign flip "breaks down under any ±2-5%
population-scale perturbation, **because the SOCP-exactness gate itself throws** near that boundary."
If that throwing is the artifact characterised above, then the documented "knife-edge fragility" is
**partly or wholly a tolerance artifact, not a physical boundary** — and the honest-negative
robustness result recorded in v2.1 would need revisiting.

**Not proven.** Phase 18-01 used the shipped default `rtol_exact`, whereas this sweep neutralized the
gate and classified externally, so the two aren't identical paths. The test is cheap and specific:
re-run the Phase 18-01 ±2-5% population sweep at `tol_gap = 1e-10` and see whether the gate still
throws. **This should be done before any v3.0 scoping treats the fragility as physical.**

### Finding 5 — tightening tolerance is not a free fix

Only 1 of the 3 discriminated points reached `1e-10`. The other two return `ALMOST_OPTIMAL`, which
`assert_solved!` correctly refuses. So "just tighten the solver" trades false-positive inexactness for
outright solve failures. A per-feeder **noise-floor calibration** (solve a known-benign point at
several tolerances, take the residual spread, classify against *that*) is the more promising route.

## Investigation Trail

1. Timed one anchor solve: **68.5 s** — grid sized down 150 → 54 to fit ~1 h. Stated, not hidden.
2. Discovered the baseline is `load 0.05 / pv 0.12` (Phase-17-retuned), **not** `0.03/0.06`
   (`materialize.jl`, older Phase-7 values). Anchoring to the wrong pair would have made the map
   uncomparable to the Phase 18-01 finding it exists to explain.
3. Point 1 (`pv×0.4`): `ratio = 0.133` — already 5× above 001's *worst* exact ratio. First hint the
   noise floor was different here.
4. Point 9: flagged inexact with the bound inactive → first false negative for 001's predicate. **At
   this stage I wrongly concluded the v3.0 pre-registered gate reads WIDE.** That claim treated
   `ratio = 1.727` as genuine while simultaneously arguing ratios near 1 were near-arbitrary. Withdrawn
   at point 18.
5. Point 18 vs 9, then 27 vs 9: same optimum, inactive bound moved, ratio changed by factors of a few
   in *both* directions → noise signature.
6. Built `discriminator.jl` (tolerance ladder). Should have been in the sweep from the start: the
   3-bus ratios were 1e3 and these were 1e0 — a three-order-of-magnitude difference in the *strength of
   evidence*, not just the value.

## Honest Limits

1. **This does NOT prove the relaxation is exact on IEEE-123.** It shows the free detector cannot tell
   at default tolerance, and that no *overvoltage-driven* inexactness occurs in the swept region.
   Certifying exactness needs the AC oracle or reliably converged tight solves — neither done here.
2. **Only 1 of 3 flagged points was conclusively discriminated.** The other two are argued by analogy
   (same `maxgap` order of magnitude) plus the structural evidence in (b) and (c).
3. **6 of 54 points unmeasured** (battery-complementarity guard trips), same amber category as 001.
4. **Coarse grid, narrow load band.** `load ∈ ×{0.95, 1.00, 1.05}` only weakly probes the ±2-5%
   fragility band, which is the thing Finding 4 says needs re-testing properly.
5. **Single seed** (`20260719`). No seed-sensitivity check.
6. `pv`/`load` remain fixture-relative multipliers — the units defect in
   `socp-validity-envelope.md` § gate is still unresolved.
