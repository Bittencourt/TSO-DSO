---
phase: 07-admm-convergence-scale
plan: 01
subsystem: infra
tags: [admm, cairomakie, weakdep, package-extension, residuals, testitems, ieee123, julia, jump]

# Dependency graph
requires:
  - phase: 06-admm-decomposition
    provides: "AdmmResiduals ledger, solve_admm dual-ascent loop, AgrOpt/DsoOpt subproblem builders"
  - phase: 04-socp-operational
    provides: "ieee13_modified feeder, ConvexBranchFlow, Phase4Fixtures _house_aggregator population"
provides:
  - "CairoMakie declared as a [weakdeps]/[extensions] TSODSOMakieExt (NOT a hard [deps]); core using TSODSO stays plot-free"
  - "Extended JuMP-free AdmmResiduals ledger: rho/eps_pri/eps_dual/price_gap traces + extended 8-arg record! + RETAINED 4-arg record! (NaN-pad) + two-residual converged(res,ε_pri,ε_dual)"
  - "diagnostics/plots.jl exported method-less plot_convergence/plot_price_convergence generics; ext/TSODSOMakieExt.jl scaffold"
  - "src/data/ieee123.jl fixture-seam stub (filled by 07-02)"
  - "RED @testitem harness (dualresid, adaptive/rho, transit/dso, ieee123, crossval, plot/makie, diag/resid) + Phase7Fixtures @testmodule (seeded IEEE-123 aggregator population, adaptive-ρ config)"
affects: [07-02-ieee123-fixture, 07-03-subproblem-rho-transit, 07-04-solve-admm, 07-05-ieee123-crossval, 07-06-plotting]

# Tech tracking
tech-stack:
  added: [CairoMakie 0.15 (weakdep only, not installed into the core env)]
  patterns:
    - "Weakdep package extension mirroring ext/TSODSOGurobiExt.jl (core exports method-less generics; ext supplies methods)"
    - "Retained-overload seam: extended + Phase-6-compatible record!/converged coexist so a mid-wave call-site switch never regresses the baseline"
    - "Defines-only @testmodule fixture (no top-level seam call) + isdefined/hasmethod-guarded RED @testitems"

key-files:
  created:
    - src/diagnostics/plots.jl
    - ext/TSODSOMakieExt.jl
    - src/data/ieee123.jl
    - test/fixtures_phase7.jl
    - test/test_admm_dualresid.jl
    - test/test_admm_adaptive.jl
    - test/test_ieee123.jl
    - test/test_ieee123_admm.jl
    - test/test_diagnostics_plot.jl
  modified:
    - Project.toml
    - Manifest.toml
    - Manifest-v1.10.toml
    - Manifest-v1.11.toml
    - Manifest-v1.12.toml
    - src/TSODSO.jl
    - src/admm/residuals.jl

key-decisions:
  - "CairoMakie mirrors the existing Gurobi/Mosek weakdep pattern exactly: recorded in Project.toml [weakdeps]+[extensions]+[compat] and the manifest TSODSO self-entry, but its package tree is NOT pulled into any Manifest / load path (uninstalled weakdeps are not tracked as full deps) — the safest supply-chain posture and the reason using TSODSO stays fast + plot-free"
  - "Retained a Phase-6 4-arg record!(res,k,primal,dual) overload that NaN-pads the four new traces, so the unmodified Phase-6 solve_admm keeps producing a length-consistent ledger — no mid-wave baseline regression; call-site switch deferred to 07-04"
  - "RED @testitem gates use isdefined(TSODSO,:set_rho!) (07-03 seam) and isdefined(TSODSO,:ieee123_modified) (07-02 seam); all behavioral asserts sit behind the guard so the runner reports RED assertions, never a crash"

patterns-established:
  - "Pattern 1: weakdep viz extension (CairoMakie → TSODSOMakieExt) keeps the heavy stack out of the core solve + headless CI"
  - "Pattern 2: coexisting extended/legacy method overloads bridge a multi-wave API migration without a baseline regression"
  - "Pattern 3: defines-only @testmodule + guarded RED @testitems for file-disjoint parallel waves"

requirements-completed: [ADMM-02, ADMM-05]

# Metrics
duration: 15min
completed: 2026-07-19
---

# Phase 7 Plan 01: ADMM Convergence & Scale Foundation Summary

**CairoMakie weakdep + TSODSOMakieExt scaffold, a JuMP-free AdmmResiduals ledger extended with ρ/ε/price traces (plus a retained Phase-6 record! overload that NaN-pads them), and a RED @testitem harness — the single-owner shared-surface foundation that lets Phase-7 Waves 2–4 run file-disjoint.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-19T07:15:07Z
- **Completed:** 2026-07-19T07:30:02Z
- **Tasks:** 3
- **Files modified:** 16 (9 created, 7 modified)

## Accomplishments
- Wired CairoMakie as a `[weakdeps]`/`[extensions]` (`TSODSOMakieExt`) + `[compat] 0.15`, mirroring the Gurobi/Mosek pattern; re-resolved the main manifests on Julia 1.10/1.11/1.12; verified `using TSODSO` loads without importing CairoMakie/Makie (threat T-07-01).
- Created the plot API seam (`src/diagnostics/plots.jl` exported method-less generics), the extension scaffold (`ext/TSODSOMakieExt.jl`), and the IEEE-123 fixture stub (`src/data/ieee123.jl`); wired both new includes into `src/TSODSO.jl`.
- Extended the JuMP-free `AdmmResiduals` ledger with `rho_trace`/`eps_pri_trace`/`eps_dual_trace`/`price_gap_trace`, an extended 8-arg `record!`, a two-residual `converged(res,ε_pri,ε_dual)`, and — critically — a RETAINED 4-arg `record!` overload that NaN-pads the new traces so the unmodified Phase-6 `solve_admm` never regresses.
- Authored `Phase7Fixtures` (defines-only) and five RED `@testitem` files; full suite = 1155 Phase-6 tests green + 38 new green + 8 intended RED gates + 1 pre-existing broken, with no runner crash.

## Task Commits

Each task was committed atomically:

1. **Task 1: CairoMakie weakdep + manifests + include-graph + diagnostics/plot scaffold** - `d14129d` (feat)
2. **Task 2: Extend AdmmResiduals ledger + two-residual converged (JuMP-free)** - `0262317` (feat)
3. **Task 3: RED @testitem harness + Phase7Fixtures @testmodule** - `bd60524` (test)

_Task 2 is a `tdd="true"` task; its extended-ledger behavior is exercised (GREEN) by the Task-3 harness items `diagnostics resid` and `admm dualresid ... ledger`._

## Files Created/Modified
- `Project.toml` - CairoMakie under `[weakdeps]`+`[extensions]` (`TSODSOMakieExt`)+`[compat] 0.15`
- `Manifest.toml`, `Manifest-v1.10/1.11/1.12.toml` - re-resolved; record the extension decl in the TSODSO self-entry (CairoMakie/Makie tree stays OUT)
- `src/diagnostics/plots.jl` - exported method-less `plot_convergence`/`plot_price_convergence` generics, no CairoMakie import
- `ext/TSODSOMakieExt.jl` - weakdep extension scaffold (`using TSODSO, CairoMakie`); methods filled by 07-06
- `src/data/ieee123.jl` - comment-only IEEE-123 fixture stub (filled by 07-02)
- `src/TSODSO.jl` - include `data/ieee123.jl` (data block) + `diagnostics/plots.jl` (after admm/)
- `src/admm/residuals.jl` - extended ledger + extended/retained `record!` + two-residual/retained `converged`, JuMP-free
- `test/fixtures_phase7.jl` - `@testmodule Phase7Fixtures` (seeded IEEE-123 aggregator population, λ₀, adaptive-ρ config)
- `test/test_admm_dualresid.jl`, `test/test_admm_adaptive.jl`, `test/test_ieee123.jl`, `test/test_ieee123_admm.jl`, `test/test_diagnostics_plot.jl` - RED harness

## Decisions Made
- **Weakdep, not installed:** CairoMakie is recorded in Project.toml and the manifest self-entry but its dependency tree is deliberately NOT instantiated into any manifest — identical to the existing Gurobi/Mosek weakdeps. This keeps `using TSODSO` fast and plot-free and avoids downloading a heavy tree; researchers add CairoMakie in their own env when they want plots (RESEARCH Pattern 6 install note).
- **Coexisting overloads:** kept both the Phase-6 (`record!/4-arg`, `converged/tol`) and Phase-7 (`record!/8-arg`, `converged/ε_pri,ε_dual`) methods so 07-04 can switch the `solve_admm` call site without this wave touching `solve_admm.jl`.

## Deviations from Plan

**1. [Rule 1 - Factual correction] Manifests record only the extension declaration; CairoMakie's package tree is NOT resolved into any manifest, and `test/Manifest.toml` needed no change**
- **Found during:** Task 1 (manifest re-resolution)
- **Issue:** The plan/environment note anticipated that "weakdeps resolve into the manifest" and listed `test/Manifest.toml` among files_modified. Empirically, `Pkg.resolve()` does NOT pull an uninstalled weakdep's tree into the manifest (confirmed by the existing Gurobi/Mosek weakdeps, which are likewise absent from every manifest and depot). Resolve reported "No Changes" for the package graph; only the TSODSO self-entry's `[extensions]`/`[weakdeps]` declaration + `project_hash` changed in the four main manifests. The test env does not declare TSODSO's weakdeps, so `test/Manifest.toml` was correctly unchanged.
- **Fix:** Accepted the correct behavior (it is the desired supply-chain + fast-load posture, threat T-07-01/T-07-SC) rather than forcing a spurious install. Synced the generic `Manifest.toml` to the re-resolved `Manifest-v1.12.toml` to preserve the project's `Manifest.toml == default(1.12) resolve` invariant.
- **Files modified:** Manifest.toml, Manifest-v1.10/1.11/1.12.toml (self-entry decl only)
- **Verification:** `grep -c '[[deps.CairoMakie]]\|[[deps.Makie]]'` == 0 in all five manifests; `using TSODSO` on 1.12 loads with CairoMakie/Makie NOT in `Base.loaded_modules`.
- **Committed in:** d14129d (Task 1 commit)

---

**Total deviations:** 1 (factual correction, no scope change)
**Impact on plan:** None — the observed weakdep behavior is the intended, safest outcome and matches the established Gurobi/Mosek pattern; all success criteria met.

## Issues Encountered
- The `julia +1.12` channel does not exist in this juliaup install (1.12.5 is the `release`/default channel); used the default `julia`/`+release` for the 1.12 resolves. The `1.10`/`1.11` named channels worked as written.
- `TestItemRunner` lives in the test env, so the plan's `julia --project=. -e 'using TestItemRunner; ...'` verify cannot run from the main project; used the canonical `Pkg.test()` full-suite gate instead (it discovers all `@testitem`s and is the real regression gate).

## Next Phase Readiness
- Shared surfaces are all owned by this plan and now stable: `Project.toml`/manifests, `src/TSODSO.jl` include graph, and `src/admm/residuals.jl`. Waves 2–4 are file-disjoint.
- 07-02 fills `src/data/ieee123.jl` (`ieee123_modified`) → greens `test_ieee123.jl`.
- 07-03 adds `set_rho!` + the DSO-OPT transit-node relaxation → greens `test_admm_adaptive.jl` (adaptive/rho, transit/dso).
- 07-04 switches `solve_admm.jl` to the extended `record!`/two-residual `converged` and the adaptive-ρ policy → greens `test_admm_dualresid.jl`.
- 07-05 greens the end-to-end `test_ieee123_admm.jl`; 07-06 fills `ext/TSODSOMakieExt.jl` methods.

## TDD Gate Compliance
- Task 2 (`tdd="true"`) landed as a `feat` implementation whose behavior is pinned by the Task-3 harness (RED-for-seams, GREEN-for-ledger). The ledger GREEN items (`diagnostics resid`, `admm dualresid ... ledger`) confirm the extended `AdmmResiduals` contract; no separate RED `test(...)` commit precedes it because the shared test harness is authored atomically in Task 3 per the plan's task ordering.

## Self-Check: PASSED
- All 9 created source/test files + SUMMARY.md present on disk.
- All three task commits (d14129d, 0262317, bd60524) present in git history.

---
*Phase: 07-admm-convergence-scale*
*Completed: 2026-07-19*
