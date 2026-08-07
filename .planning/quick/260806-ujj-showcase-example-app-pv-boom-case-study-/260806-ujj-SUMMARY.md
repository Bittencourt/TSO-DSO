---
quick_id: 260806-ujj
title: PV-boom case study + self-contained HTML report
date: 2026-08-06
subsystem: scripts (showcase orchestration over src/experiments, src/models, src/admm, src/pricing, src/planning)
tags: [showcase, pv-sweep, dlmp, admm, exact-04, planning-nash, html-report]
requires: [Scenario/run_scenario (08-*), solve_welfare/extract_dlmp/decompose_dlmp (03-*/05-*), solve_admm (06-*/07-*), ACPowerFlow/assert_ac_exact! (15-*), build_shared_transmission/run_nash! (13-*)]
provides: [scripts/pv_boom_case_study.jl, scripts/pv_boom_report.jl, results/pv_boom/summary.csv, results/pv_boom/findings.txt]
affects: [.gitignore]
key-decisions:
  - "Substituted the planning-layer baseline distributor from the plan's suggested pv_mult=0.0 to pv_mult=0.7 after discovering pv_mult=0.0 is unconditionally infeasible under solve_stackelberg!'s Benders design (see Deviations)."
  - "Accepted the converged Nash equilibrium x_inv=[0,0] (non-differentiated) as an honest finding per the plan's own explicit allowance, rather than re-tuning to force a difference."
  - "Left the local Project.toml/Manifest-v1.12.toml CairoMakie weakdep->deps promotion UNCOMMITTED, matching Pedro's own established local-drift convention (project memory: local-project-toml-drift)."
metrics:
  duration: "~1.5 hours"
  completed: 2026-08-06
---

# Phase quick-260806-ujj: PV-boom case study + self-contained HTML report Summary

One-liner: a reproducible, narrated PV-penetration showcase spanning both framework layers — operational sweep + DLMP decomposition + ADMM cross-check + the certified EXACT-04 SOCP/AC exactness gap + a planning-layer Stackelberg-Nash investment game — rendered into one offline-openable HTML report.

## What Was Built

**`scripts/pv_boom_case_study.jl`** (new, ~753 lines) — a Literate-style narrative script, three parts:

- **Part A** — sweeps `pv_mult = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]` on the modified IEEE-13
  feeder via the new `pv_boom_population` wrapper (a thin re-parametrization of the
  already-`pv_scale`-capable `TSODSO._default_house`), solving `solve_welfare` +
  `extract_dlmp`/`decompose_dlmp` at each point with per-point `try`/`catch` (mirrors
  `scripts/socp_applicability_sweep.jl`'s own pattern). All 6/6 points solved
  successfully (welfare ranges -4830.13 → -4820.08 as PV rises). Cross-checks the
  `pv_mult=1.0` point against the declarative `Scenario`/`run_scenario` entry point
  (welfare and DADP match to floating-point tolerance) and against `solve_admm` at
  `ρ=100.0` (relative welfare gap 7.3e-7, `max|DADP_admm − DADP_centralized| = 6.4e-2`,
  42 ADMM iterations). Persists `data/pv_boom/results.jld2` (gitignored) and
  `results/pv_boom/summary.csv` (committed).
- **Part A2** — reproduces the certified EXACT-04 finding verbatim on the 3-bus
  high-PV stress fixture (`pv_scale=1.2`, `load_scale=0.2`, `vmax=1.05`,
  `test/fixtures_phase4.jl`'s own substrate, reproduced locally per the no-`src/`-
  and-no-`test/`-dependency scope): the SOC relaxation is genuinely INEXACT at 10/24
  hours (`obj_gap=0.870`, `socp_maxgap=10.44` under the documented `rtol_exact=1.0`
  diagnostic override). The script errors loudly if this ever comes back all-exact
  (drift detector).
- **Part B** — two IEEE-13-scale distributor specs, sliced to the afternoon PV-peak
  sub-horizon (hours 13:18), play a Gauss-Seidel Stackelberg-Nash investment game over
  a shared transmission-reinforcement corridor (`build_shared_transmission`/
  `run_nash!`). Converges (`converged=true`, 1 sweep, 2 total Benders iterations) to
  the honest corner solution `x_inv=[0.0, 0.0]` (no investment, no coupling flow) —
  reported as a non-differentiated finding, not forced apart. See Deviations for why
  the baseline distributor uses `pv_mult=0.7` instead of the plan's suggested `0.0`.

**`scripts/pv_boom_report.jl`** (new, ~243 lines) — loads `data/pv_boom/results.jld2`,
builds three `CairoMakie.Figure`s (price-reshaping curves, 4-way DLMP stacked
decomposition, ADMM convergence via the existing `TSODSO.plot_convergence` — never
reimplemented), embeds each as a base64 `data:image/png;base64,...` URI, and assembles
one self-contained `results/pv_boom/report.html` (gitignored, ~486 KB) with two plain
HTML tables (sweep summary, Nash equilibrium) and captions drawn from `findings.txt`.
Verified offline-openable: `grep -E "https?://|<link |<script src="` finds nothing.

**`.gitignore`** — added `/results/**/*.html` alongside the existing `.pdf`/`.png`/`.svg`
regenerable-figure exclusions.

## Deviations from Plan

### Auto-fixed / adapted issues

**1. [Rule 1 — structural finding, not a tuning knob] Planning-layer baseline distributor substituted from pv_mult=0.0 to pv_mult=0.7**
- **Found during:** Task 2, Part B calibration.
- **Issue:** `solve_stackelberg!`'s Benders master ALWAYS proposes `z=0` (no frontier
  import) as its unconditional first trial (zero cuts ⇒ epigraph variables at their free
  lower bound ⇒ `z` forced to its own box lower bound). Only the follower's shell
  transmission-corridor LP gates feasibility before this trial reaches the oracle
  (`benders.jl`'s own documented ordering) — the oracle itself has NO feasibility-cut
  recovery path and raises a hard `ErrorException` on a genuinely infeasible pinned
  point. A `pv_mult=0.0` (zero-PV) residential network has literally zero generation
  anywhere, so `z=0` is physically infeasible (no way to self-balance real inelastic
  demand with zero import) — not a calibration/margin issue that `α_op_lb`/`x_inv_max`/
  `c_op` tuning can fix.
- **Verification:** Directly probed `solve_planning_oracle!(oracle, zeros(T_planning))`
  at `pv_mult ∈ {0.0, 0.3, 0.5}` — all raise `INFEASIBLE`/`PRIMAL_INFEASIBLE`;
  `pv_mult ∈ {0.7, 1.0}` are feasible (enough curtailable local PV headroom to net
  exactly to the zero-import trial via the continuous `0 ≤ pv_used ≤ Ppv` freedom).
- **Fix:** Substituted the "baseline" distributor to `pv_mult = 0.7` (materialized via
  the identical `pv_boom_population` + `BASE_SEED` methodology as the Part-A sweep, not
  one of the 6 headline sweep points) — preserving the intended "low PV vs PV boom"
  contrast against `pv_mult = 2.5` while keeping the game playable under
  `solve_stackelberg!`'s existing, unmodified Benders design.
- **Files modified:** `scripts/pv_boom_case_study.jl` (Part B population sourcing +
  documented Deviation comment above `slice_aggregator`).
- **Commit:** f026fe7

**2. [Rule 3 — missing referenced environment state] CairoMakie promoted from `[weakdeps]` to `[deps]` locally, left uncommitted**
- **Found during:** Task 3, first `scripts/pv_boom_report.jl` run.
- **Issue:** The plan's own read-first notes assumed CairoMakie is "already a project
  dependency, not a weakdep-only extension" — true of Pedro's own dirty main checkout
  (per project memory `local-project-toml-drift`), but the CLEAN, committed worktree
  environment this executor forked from has CairoMakie only under `[weakdeps]`
  (triggering `ext/TSODSOMakieExt.jl`), so `using CairoMakie` failed with "Package not
  found."
- **Fix:** `Pkg.add(PackageSpec(name="CairoMakie", uuid="13f3f980-…"))` — the EXACT UUID
  already declared in the committed `Project.toml`'s own `[weakdeps]` entry (no new/
  unverified package name), which Julia's package manager promotes to `[deps]` and
  resolves into the Manifest. This is a `Pkg.resolve`/`Pkg.add`-class operation on an
  ALREADY-declared, UUID-pinned dependency, not an install of a new/ambiguous package
  name — exempted from the package-legitimacy checkpoint on that basis. Per the
  project's own established convention (never commit this local promotion — it defeats
  the `ext/TSODSOMakieExt.jl` optional-extension design for the mainline checkout),
  `Project.toml`/`Manifest-v1.12.toml` are left MODIFIED BUT UNCOMMITTED in this
  worktree; only `scripts/`/`.gitignore`/`results/` changes were committed.
- **Files modified (uncommitted, by design):** `Project.toml`, `Manifest-v1.12.toml`.
- **Commit:** none (deliberately left out of every commit).

None of the other deviations noted in the script's own inline comments (the Deferrable
window re-indexing for the sliced sub-horizon) rise to the level of a plan deviation —
they are documented directly in `slice_aggregator`'s own docstring as a coordinate
change, not a parameter retune.

## Self-Check

```
FOUND: scripts/pv_boom_case_study.jl
FOUND: scripts/pv_boom_report.jl
FOUND: results/pv_boom/summary.csv
FOUND: results/pv_boom/findings.txt
FOUND: data/pv_boom/results.jld2 (gitignored, present on disk)
FOUND: results/pv_boom/report.html (gitignored, present on disk)
FOUND commit 025194e (Task 1)
FOUND commit f026fe7 (Task 2)
FOUND commit 96688aa (Task 3)
```

## Self-Check: PASSED

## Known Stubs

None — every number in `results/pv_boom/summary.csv`, `findings.txt`, and
`report.html` traces to a real `solve_welfare`/`solve_admm`/`assert_ac_exact!`/
`run_nash!` call recorded in this run's `data/pv_boom/results.jld2`.

## Threat Flags

None — every code path in both new scripts is orchestration over already-validated,
already-gated public API (`solve_welfare`, `solve_admm`, `extract_dlmp`/
`decompose_dlmp`, `assert_ac_exact!`, `run_nash!`); no new network endpoint, auth path,
file-access pattern, or schema change at a trust boundary is introduced.
