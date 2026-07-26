# Spike Conventions

Patterns and stack choices established across spike sessions. New spikes follow these unless the
question requires otherwise.

## Stack

Julia, run against the project environment — `julia --project=. .planning/spikes/NNN-name/script.jl`.
No separate spike environment, no added dependencies: everything used so far
(`CSV`, `DataFrames`, `CairoMakie`, `JuMP`, `Clarabel` via the solver factory) is already in
`Project.toml`.

**Output format:** stdout table + CSV + a CairoMakie figure (PNG at `px_per_unit = 2` for review, PDF
for thesis use). No web UI — these spikes answer numerical questions, and the figure *is* the
experience.

## Structure

```
.planning/spikes/NNN-name/
  sweep.jl        # compute → CSV   (re-runnable, self-contained)
  plot_map.jl     # CSV → figure    (separate so re-plotting needs no re-solve)
  sweep.csv
  *.png / *.pdf
  README.md
```

Splitting compute from plotting matters: sweeps cost minutes, figure iteration should cost seconds.

## Patterns

- **Observe without mutating `src/`.** Use existing diagnostic kwargs (e.g. `rtol_exact = 1e6` to
  neutralize the PF-04 exactness gate) and compute classifications in the spike. A spike that needs a
  `src/` change to observe something is a signal the seam is missing — log it, don't patch it.
- **Positive + negative controls in every sweep**, printed and checked on each run. A sweep that
  cannot reproduce a known result cannot be trusted when it reports a clean one. This caught a
  completely inert fixture in spike 001.
- **Replicate `@testmodule` fixtures locally, and verify the copy.** Test fixtures under
  `test/fixtures_*.jl` are TestItems `@testmodule`s, unreachable from a plain script. Copy the recipe
  into the spike and check profile constants against the original rather than assuming.
- **Failure classes are data.** Catch per-point errors, keep the message, classify (`infeasible` vs
  guard-trip vs solver), and render each distinctly. Never merge or drop.
- **Scale-free thresholds only** — the house WR-01 `atol + rtol·max(|lhs|,|rhs|)` idiom.
- **Report absolute and relative**, never relative alone (welfare and per-unit quantities can straddle
  zero or sit on wildly different MVA bases).
- **Run a tolerance ladder before believing any residual-based classification.** Re-solve flagged points
  at progressively tighter solver tolerances: a structural property PERSISTS, numerical noise SHRINKS.
  Spike 002 saw a "worst case" ratio of 4.76 collapse to 0.0029 at an identical optimum when `tol_gap`
  went 1e-8 → 1e-10. Ship the ladder alongside the sweep, not after someone doubts the result.
- **Sanity-check for spatial structure.** A physical mechanism produces a connected region, monotone in
  its driving parameter. Salt-and-pepper scatter — or a flag at the *lowest* value of the driving axis —
  is noise. This is free to check and would have caught spike 002's artifact before the tolerance ladder.
- **Watch for sensitivity to inactive constraints.** If moving a bound that is not active changes a
  measured quantity, the quantity is tracking solver trajectory, not the optimum. A cheap, decisive
  noise test that fell out of spike 002 by accident.

## Tools & Libraries

- `CairoMakie` + `cgrad(colors, n, categorical = true)` for categorical region maps; `:vik` diverging
  for signed log-scale quantities.
- Faceting by the third axis into `fig[row, k]` reads better than a 3-D surface for a 3-axis sweep.
- Mark auxiliary diagnostics as scatter overlays on the categorical map (e.g. a dot where the voltage
  bound is active) — it lets one figure carry both the verdict and its explanation.

## Gotchas

- `CairoMakie` currently sits in `[deps]` only via the *uncommitted* `Project.toml` drift. If that
  drift is ever reverted, spike plotting breaks. (Same drift causes the 2 known-false Aqua failures.)
- Irregularly spaced grid axes: heatmap on **index** positions with value tick labels, not on the
  values themselves, or the cells come out unevenly sized and misleading.
