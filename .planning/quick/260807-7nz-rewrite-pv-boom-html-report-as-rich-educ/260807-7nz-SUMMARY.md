---
quick_id: 260807-7nz
title: Rewrite PV-boom HTML report as a rich educational walkthrough
date: 2026-08-07
subsystem: scripts (report-generator rewrite only; src/ and pv_boom_case_study.jl untouched)
tags: [html-report, mathml, education, dlmp, admm, exact-04, planning-nash, reproducibility]
requires: ["260806-ujj (scripts/pv_boom_case_study.jl, data/pv_boom/results.jld2, results/pv_boom/findings.txt)"]
provides: [scripts/pv_boom_report.jl (rewritten), results/pv_boom/report.html (regenerated, gitignored)]
affects: []
key-decisions:
  - "Computed every Section 4 number (welfare deltas, exact_maxgap per pv_mult, ADMM relative gap, Nash differentiation verdict) directly from the loaded results dict at report-generation time instead of re-typing findings.txt's prose, so the report can never drift from the data it cites."
  - "Used native <math> MathML for every equation (no KaTeX/MathJax/CDN) per the plan's offline-only constraint; equations hand-transcribed from the device/welfare_solve/dlmp source docstrings, verified against each source file before writing."
  - "Read the git commit stamp live via readchomp(`git rev-parse --short HEAD`) with a try/catch fallback, never hardcoded, then regenerated the report one final time after the last commit so the stamp matches the actual delivered commit."
metrics:
  duration: "~1 hour"
  completed: 2026-08-07
---

# Quick task 260807-7nz: Rewrite PV-boom HTML report as a rich educational walkthrough Summary

One-liner: rewrote `scripts/pv_boom_report.jl` from a terse 3-figure/2-table report into a 5-section, table-of-contents-navigated educational walkthrough with 21 native MathML equations (no CDN) transcribed from the actual source code, richly-interpreted results computed live from the loaded data, and a live git-commit reproducibility stamp.

## What Was Built

**`scripts/pv_boom_report.jl`** (rewritten, 243 → 775 lines). Kept the existing mechanics
unchanged per scope: `DrWatson.wload(datadir("pv_boom","results.jld2"))` as the sole data
source, the three `CairoMakie.Figure`s (price-reshaping curves, 4-way DLMP decomposition
stack, ADMM convergence via `TSODSO.plot_convergence`), the base64
`data:image/png;base64,...` embedding, and plain-HTML `<table>` string interpolation.
Replaced the terse `findings.txt`-slicing caption logic with five narrative sections:

- **Section 1 — Framing**: the two-layer TSO-DSO framework (operational day-ahead pricing +
  Stackelberg-Nash planning), attributed to J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022)
  and the PSR N1-N2 note, per `README.md`'s own language; states the PV-boom case study's
  three questions (price reshaping, SOCP exactness, Nash investment response).
- **Section 2 — The operational model, equation by equation**: the GLB-CVX objective
  (eq. 3.38), all four device utilities (Interruptible eq. 3.10; Thermostatic eqs.
  3.2/3.3/3.11; Deferrable eqs. 3.4/3.5/3.12; PV+battery eqs. 3.6-3.9/3.15-3.20 plus the
  App. C no-binary argument), the branch-flow SOC cone (eq. 3.39) and LinDistFlow
  exactness copy (eqs. 3.43/3.45), the DADP/DLMP dual (eq. 3.31) and its 4-way
  decomposition derivation, and the ADMM AGR-OPT/DSO-OPT split (eqs. 3.46/3.47) — every
  equation rendered as native `<math>` MathML, transcribed verbatim from
  `src/models/welfare_solve.jl`, `src/devices/*.jl`, `src/powerflow/ConvexBranchFlow.jl`,
  `src/pricing/dlmp.jl`, `src/admm/{AgrOpt,DsoOpt}.jl`. Includes a mandatory, visually
  distinct callout (`.finding` box) on the dropped additive constant `c` (every device
  docstring's own "RESEARCH A5") and why that makes welfare LEVELS (not deltas or duals)
  economically meaningless in isolation.
- **Section 3 — Experiment design**: feeder/horizon/`BASE_SEED` reproducibility, the
  `PV_MULTS` sweep grid and what it scales, the ADMM `ρ=100.0`/`pv_mult=1.0`-only choice,
  the EXACT-04 3-bus stress fixture parameters and why a dedicated fixture is needed, the
  Nash game setup, and the honest `pv_mult=0.0→0.7` baseline-substitution deviation
  (verbatim from the case study's own Deviation comment).
- **Section 4 — Results, richly interpreted**: one guided-reading subsection per artifact
  (price-reshaping figure + computed welfare deltas, sweep table + computed
  `exact_maxgap`s, decomposition figure, ADMM figure + computed relative gap, EXACT-04
  finding box, Nash table + computed differentiation verdict) — every cited number is
  computed live from `sweep`/`admm_crosscheck`/`ac_stress`/`nash_result` (never re-typed
  from `findings.txt`), so the report cannot silently drift from the data it describes.
- **Section 5 — Reproducibility**: the two re-run commands, the `BASE_SEED` note, and a
  live `git rev-parse --short HEAD` stamp (try/catch, never hardcoded).

A sticky table-of-contents `<nav>` links all 5 `<h2 id="sectionN">` anchors. New CSS:
`.eq-block` (equation styling), `.eqref` (thesis-equation-number citation), `nav.toc`.

## Verification

```
julia --project=. scripts/pv_boom_report.jl   → exits 0, both after Task 1 (old assembly,
                                                  4 new constants unused) and Task 2 (full
                                                  rewire)
grep -c '<math' report.html                    → 21
grep -Ev '^\s*(#|//)' report.html \
  | grep -Ec 'https?://|<link |<script src='    → 0
grep -c 'EXACT-04' report.html                 → 4
grep -c 'id="section' report.html              → 5
grep -c 'data:image/png;base64,' report.html    → 3
grep -Eic 'kkatex|mathjax|cdn\.' report.html    → 0
test -f results/pv_boom/report.html             → present
```

Spot-checked the rendered numbers against `findings.txt`: welfare deltas +4.10/+6.82/
+8.09/+9.10/+10.05, `exact_maxgap` 1.696e-09…7.428e-09 across all 6 `pv_mult` points,
ADMM relative gap 7.288e-7, `dadp_maxgap`/iters (42), EXACT-04's 10/24 inexact hours,
Nash `x_inv=[0.0, 0.0]` non-differentiated finding — all match exactly (computed live from
the same underlying data, not re-typed).

## Deviations from Plan

None — plan executed as written. Two auto-fixes during execution, both Rule 3 (blocking):

**1. [Rule 3 — blocking] `using Printf` placement**
- **Found during:** Task 2, first `julia --project=.` run after adding `@printf`-based
  computed-number formatting to the new Section 4 content.
- **Issue:** `@printf` calls were added mid-file before any `using Printf` import; Julia
  parses/evaluates the script top-to-bottom, so a `using Printf` placed after first use
  would still work at *parse* time but is fragile/non-idiomatic and one draft attempt
  placed it after the first `@printf` call site, which is the wrong order for a linear
  script.
- **Fix:** Added `using Printf` to the top-of-file `using` block alongside `DrWatson`,
  `TSODSO`, `CairoMakie`, `Base64`.
- **Files modified:** `scripts/pv_boom_report.jl`.
- **Verification:** `julia --project=. scripts/pv_boom_report.jl` exits 0.
- **Committed in:** 7d41053 (Task 2 commit).

## Self-Check

```
FOUND: scripts/pv_boom_report.jl
FOUND: results/pv_boom/report.html (gitignored, present on disk, 525495 bytes)
FOUND commit 4654538 (Task 1 — CSS + 4 unwired section constants)
FOUND commit 7d41053 (Task 2 — full rewire, results content, live git stamp)
```

## Self-Check: PASSED

(Re-verified: `[ -f scripts/pv_boom_report.jl ]`, `[ -f results/pv_boom/report.html ]`,
`git log --oneline --all | grep -q 4654538`, `git log --oneline --all | grep -q 7d41053` —
all four checks passed.)

## Known Stubs

None — every equation traces to a read source-file docstring (verified against
`src/models/welfare_solve.jl`, `src/devices/{Interruptible,Thermostatic,Deferrable,
PVBattery}.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/pricing/dlmp.jl`,
`src/admm/{AgrOpt,DsoOpt}.jl` before writing), every experiment parameter traces to
`scripts/pv_boom_case_study.jl`, and every Section 4 result number is computed live from
`data/pv_boom/results.jld2` at generation time (not hardcoded).

## Threat Flags

None — this is a read-only report generator over already-persisted `results.jld2` data;
no new network endpoint, auth path, file-access pattern, or schema change at a trust
boundary is introduced. The only new "input" is `git rev-parse --short HEAD` via
`readchomp`, wrapped in try/catch with a safe string fallback.
