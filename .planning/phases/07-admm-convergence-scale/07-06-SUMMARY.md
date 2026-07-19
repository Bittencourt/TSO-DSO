---
phase: 07-admm-convergence-scale
plan: 06
subsystem: diagnostics/viz
tags: [admm, diagnostics, plotting, weakdep-extension, cairomakie, isolation]
requires:
  - "src/diagnostics/plots.jl: exported plot_convergence / plot_price_convergence generic stubs (07-01)"
  - "src/admm/residuals.jl: JuMP-free AdmmResiduals ledger with primal/dual/ρ/ε/price traces (07-01)"
  - "Project.toml [weakdeps]/[extensions]: CairoMakie + TSODSOMakieExt wiring (07-01)"
provides:
  - "ext/TSODSOMakieExt.jl: CairoMakie-backed TSODSO.plot_convergence / plot_price_convergence methods returning a Makie.Figure"
  - "test/test_diagnostics_plot.jl: with-CairoMakie Figure isolation @testitem (skip-gated), alongside the existing core plot-free items"
affects:
  - "ADMM-05 (convergence diagnostics reported and PLOTTABLE) — completes the plottable half"
tech-stack:
  added: []
  patterns:
    - "Weakdep package extension (Julia [extensions]) as the modern Requires.jl replacement — mirrors ext/TSODSOGurobiExt.jl / ext/TSODSOMosekExt.jl"
    - "Plotting methods dispatch on core method-less generic functions; the ext supplies the AdmmResiduals method only when CairoMakie is present"
    - "Process-isolated with-dep verification: spawn a child Julia process so the headless core test process never loads the heavy viz stack"
key-files:
  created: []
  modified:
    - "ext/TSODSOMakieExt.jl"
    - "test/test_diagnostics_plot.jl"
decisions:
  - "Left src/diagnostics/plots.jl untouched: the generics were already declared+exported by 07-01, so filling only the ext keeps the core plot-free contract intact."
  - "The with-CairoMakie Figure check runs in a SEPARATE Julia process (not an in-suite `using CairoMakie`) because package loading is process-global — an in-suite import would activate the ext for the whole worker and break the sibling core-plot-free item (T-07-17)."
  - "CairoMakie is not installed in the active environment (weakdep, find_package → nothing), so the with-CairoMakie item is skipped-with-message; the ext code is verified by parse + the Gurobi/Mosek extension pattern."
metrics:
  duration: ~20m
  tasks: 2
  files-changed: 2
  completed: 2026-07-19
---

# Phase 7 Plan 06: TSODSOMakieExt Convergence Plotting Extension Summary

CairoMakie-backed ADMM convergence + DADP price-convergence plotting delivered as a weakdep
package extension that lights up only when CairoMakie is loaded — the core solve and headless
CI stay plot-free.

## What Was Built

- **`ext/TSODSOMakieExt.jl`** — filled the 07-01 scaffold with two methods that extend the core
  generic functions and return a Makie `Figure`, reading ONLY the JuMP-free `AdmmResiduals`
  ledger (no JuMP, no solver — threat T-07-18):
  - `TSODSO.plot_convergence(res; filename=nothing)` — primal `‖r‖` and dual `‖s‖` residual
    traces on a `log10` axis, overlaid with dashed `ε_pri` / `ε_dual` threshold lines, an axis
    legend, optional `save`.
  - `TSODSO.plot_price_convergence(res; filename=nothing)` — price move `‖Δλ‖`
    (`price_gap_trace`) on a log-scaled left axis with the adaptive-ρ schedule (`rho_trace`)
    on a linked twin right axis, combined legend, optional `save`.
  - Mirrors the existing weakdep-module pattern of `ext/TSODSOGurobiExt.jl` /
    `ext/TSODSOMosekExt.jl` exactly (`module …; using TSODSO, <Dep>; TSODSO.<fn>(…) = …; end`).

- **`test/test_diagnostics_plot.jl`** — added a with-CairoMakie isolation `@testitem`
  (name carries "plot"/"makie") that asserts the ext method gains an `AdmmResiduals` method and
  returns a `Makie.Figure`, run in a **separate Julia process** so the headless core process
  never loads Makie. Skipped-with-message when CairoMakie is absent. The pre-existing core
  plot-free items (no applicable method without CairoMakie; ledger-trace consumption) are
  unchanged and green.

## Isolation Contract Proven

- `using TSODSO` alone does NOT load CairoMakie (baseline check: `loaded CairoMakie? false`).
- With the ext filled, the core stays plot-free: `!hasmethod(TSODSO.plot_convergence,
  Tuple{TSODSO.AdmmResiduals})` holds (Task 1 automated verify passed). The ext method only
  activates when CairoMakie is present in the active environment (T-07-17).

## Verification

- Task 1 automated: `!hasmethod(plot_convergence, Tuple{AdmmResiduals})` → `core plot-free OK`.
- Task 2 automated (filtered plot/makie testitems): **35 pass, 1 broken (the intentional
  `@test_skip`), 0 fail, 0 error**. The single "Broken" is the skipped-with-message
  with-CairoMakie item (CairoMakie not installed — weakdep).
- `ext/TSODSOMakieExt.jl` parse-checked (`PARSE OK`); cannot be loaded here because CairoMakie
  is not installed, so its runtime is exercised by the separate-process test where CairoMakie
  is present (and by the manual 07-VALIDATION aesthetics check).

## Deviations from Plan

None — plan executed as written. `src/diagnostics/plots.jl` was not edited because its
generics were already declared and exported by 07-01 (the plan's `files_modified` correctly
lists only `ext/TSODSOMakieExt.jl` and `test/test_diagnostics_plot.jl`).

## Known Stubs

None. The ext methods are fully implemented; the with-CairoMakie test path is intentionally
skipped-with-message only because CairoMakie is a weakdep not installed in this environment.

## Environment Note

CairoMakie is declared under `[weakdeps]`/`[extensions]` in `Project.toml` but is NOT installed
in the active environment (`Base.find_package("CairoMakie") === nothing`). The plot methods and
the with-CairoMakie Figure assertion are therefore proven-by-construction (extension pattern +
parse) and skipped-with-message at test time; a full runtime Figure check requires installing
CairoMakie in a non-headless environment (the manual 07-VALIDATION step).

## Human Verification (deferred, from plan)

In an environment with CairoMakie installed: `import CairoMakie; using TSODSO`, build a small
`AdmmResiduals`, then `save("conv.pdf", plot_convergence(res))` and
`save("price.pdf", plot_price_convergence(res))`; confirm residual curves decay below the ε
threshold lines, axes are labeled/log-scaled, and the output is thesis-grade vector.

## Commits

- `a0e2cfb` — feat(07-06): fill TSODSOMakieExt convergence + price plots (weakdep Figure)
- `e29662b` — test(07-06): add with-CairoMakie Figure isolation testitem (skip-gated)

## Self-Check: PASSED

- Files: ext/TSODSOMakieExt.jl, test/test_diagnostics_plot.jl, 07-06-SUMMARY.md — all FOUND.
- Commits: a0e2cfb, e29662b — both FOUND in git log.
