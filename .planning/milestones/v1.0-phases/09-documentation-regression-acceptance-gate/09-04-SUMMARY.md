---
phase: 09-documentation-regression-acceptance-gate
plan: 04
subsystem: docs
tags: [documenter, literate, cairomakie, admm, docs-ci]

# Dependency graph
requires:
  - phase: 09-documentation-regression-acceptance-gate
    provides: "plans 09-01/09-02 — the five prior literate pages (lindistflow, convex_branch_flow, prosumer_welfare, pricing_dlmp)"
  - phase: 06-admm-decomposition-core
    provides: "solve_admm hand-rolled dual-ascent ADMM loop"
  - phase: 07-admm-convergence-scale
    provides: "AdmmResiduals ledger, TSODSOMakieExt plot_convergence weakdep extension"
provides:
  - "docs/literate/admm.jl — Rung 5 literate page (ADMM decomposition + convergence, thesis 3.46/3.47)"
  - "docs/make.jl fully wired: all six literate pages, checkdocs=:exports, CI-gated deploydocs"
  - "docs/Project.toml + re-resolved docs/Manifest.toml with CairoMakie as a docs-only hard dep"
affects: [09-05-documentation-regression-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "docs/Project.toml may hard-depend on a root [weakdeps] package (CairoMakie) for figure rendering, guarded per-page with Base.find_package, without touching root Project.toml's weakdep discipline"
    - "Literate.markdown(...; flavor = Literate.DocumenterFlavor()) replaces the deprecated documenter=true kwarg across all Literate.markdown call sites in docs/make.jl"

key-files:
  created:
    - docs/literate/admm.jl
  modified:
    - docs/Project.toml
    - docs/Manifest.toml
    - docs/make.jl
    - docs/src/index.md
    - docs/literate/pricing_dlmp.jl

key-decisions:
  - "Used a 3-bus radial feeder with two PVBattery aggregators (T=4) for the ADMM page — the same feeder shape as pricing_dlmp.jl — satisfying solve_admm's 1:1 aggregator-per-load-node requirement while keeping the doc build fast"
  - "ρ=5.0 initial penalty (matching the RHO_2BUS test precedent) converges in 6 iterations on this small scenario"
  - "Removed pricing_dlmp.jl's unused `using JuMP` import rather than adding JuMP to docs/Project.toml — no JuMP symbol was actually referenced on that page, so dropping the dead import is the minimal fix (Rule 1)"

patterns-established:
  - "Full docs/make.jl build (all rungs wired) is the actual EXP-03 acceptance gate — a page can pass its own standalone `include` smoke test yet still break the real makedocs @example execution if it imports a package absent from docs/Project.toml; the full build must be run at least once before declaring EXP-03 complete"

requirements-completed: [EXP-03]

# Metrics
duration: 35min
completed: 2026-07-20
---

# Phase 9 Plan 4: ADMM Literate Page + Full docs/make.jl Build Wiring Summary

**Rung-5 ADMM literate page cross-validating `solve_admm` against `solve_welfare` on a real 3-bus scenario, plus `docs/make.jl` fully extended to build all six abstraction-ladder pages with `checkdocs=:exports`, CI-gated `deploydocs`, and a re-resolved `docs/Manifest.toml` that actually renders CairoMakie convergence figures.**

## Performance

- **Duration:** ~35 min (includes two full CairoMakie/Makie precompilation cycles, ~7-8 min each)
- **Completed:** 2026-07-20
- **Tasks:** 2 completed
- **Files modified:** 1 created, 5 modified

## Accomplishments
- `docs/literate/admm.jl` (rung 5): cites thesis 3.46 (AGR-OPT per-node block), 3.47 (DSO-OPT whole-network block), and the dual-ascent update `λ_j ← λ_j + ρ·R_p,j`, naming the build-once/re-solve discipline (ADMM-03/04) as the practical payoff. Solves the SAME 3-bus/2-aggregator scenario via `solve_welfare` (centralized) and `solve_admm` (decomposed), displaying `admm.iters` (6), the welfare gap (`abs(admm.welfare - obj_c)` ≈ 0.072 on an objective of ≈139), and `admm.exact_maxgap` (≈6.4e-9) as the ADMM≈centralized validation.
- `docs/Project.toml` gained `CairoMakie` under `[deps]`/`[compat]` "0.15", and `docs/Manifest.toml` was re-resolved via `Pkg.resolve()` — verified `Base.find_package("CairoMakie") !== nothing` succeeds under `--project=docs` before relying on it, so the figure guard in `admm.jl` is provably live, not a silent no-op.
- `docs/make.jl` fully rewritten: the single `documenter = true` call became a `for`-loop over all six literate sources using `flavor = Literate.DocumenterFlavor()` (migrating the pre-existing `toy_dc.jl` call in the same edit); `pages` grew a nested `"Models"` group listing all five new rungs; `checkdocs` tightened `:none` → `:exports`; a CI-gated `deploydocs` call was added with a clearly-commented placeholder repo slug (`github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git`, pending plan 09-05's human-verify checkpoint).
- `docs/src/index.md` gained a "Model Documentation" section linking all five new generated pages.
- **Full build verified twice**: `julia --project=docs docs/make.jl` exits 0 with all six pages rendered. The build log confirms the ADMM convergence figure actually renders as a PNG (`docs/build/generated/admm-*.png`, HTML-writer's "text/html representation above threshold, using PNG fallback" message) — not silently skipped.

## Task Commits

Each task was committed atomically:

1. **Task 1: ADMM literate page (rung 5) + docs/Project.toml CairoMakie dep, re-resolved** - `7893c66` (feat)
2. **Task 2: docs/make.jl full extension — migrate, wire all 6 pages, tighten checkdocs, CI-gated deploydocs** - `375c2d2` (feat)

_Note: no TDD tasks in this plan; no test → feat → refactor split._

## Files Created/Modified
- `docs/literate/admm.jl` - Rung 5 literate page: math (3.46/3.47) → 3-bus feeder + two PVBattery aggregators → `solve_welfare` (centralized) + `solve_admm` (decomposed, ρ=5.0, T=4) → displays `admm.iters`, welfare gap, `admm.exact_maxgap` → guarded `plot_convergence(admm.residuals)` figure
- `docs/Project.toml` - added `CairoMakie` under `[deps]`/`[compat]` "0.15" (docs-only hard dep)
- `docs/Manifest.toml` - re-resolved (`Pkg.resolve()`) so CairoMakie actually pins under `--project=docs`
- `docs/make.jl` - migrated all `Literate.markdown` calls to `flavor = Literate.DocumenterFlavor()`; nested `"Models"` pages group (6 pages); `checkdocs = :exports`; added CI-gated `deploydocs` with placeholder slug
- `docs/src/index.md` - added "Model Documentation" section linking all 5 new generated pages
- `docs/literate/pricing_dlmp.jl` - removed unused `using JuMP` import (see Deviations)

## Decisions Made
- Reused the exact 3-bus/two-PVBattery-aggregator feeder shape from `pricing_dlmp.jl` (plan 09-02) for the ADMM page, since it already satisfies `solve_admm`'s 1:1 aggregator-per-load-node requirement and is independently proven to solve cleanly.
- Chose `ρ = 5.0` (matching the `RHO_2BUS` test precedent) and `T = 4` — small enough for a fast doc build, large enough to exercise a real multi-iteration dual-ascent trajectory (6 iterations to convergence, both Boyd residuals below threshold).
- Kept `warnonly = [:missing_docs, :cross_references]` unchanged per plan instruction — `checkdocs = :exports` surfaces real gaps (numerous exported-but-undocumented symbols, e.g. `TSODSO.Bus`, `TSODSO.Feeder`) as warnings, not build failures, matching CONTEXT.md's "stay green while surfacing gaps" lock.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed `pricing_dlmp.jl`'s unused `using JuMP` import**
- **Found during:** Task 2 (full `docs/make.jl` build verification)
- **Issue:** Running the full `julia --project=docs docs/make.jl` build (the first time all six pages were ever assembled together — plans 09-01/09-02 only verified their pages via standalone `include`) failed with `ArgumentError: Package JuMP not found in current path` while executing the `@example` block on `docs/src/generated/pricing_dlmp.md:74-78`. `docs/literate/pricing_dlmp.jl` (committed in plan 09-02) has a top-level `using JuMP` that is never actually used — no `JuMP.` symbol appears anywhere in the page — and `docs/Project.toml` (correctly) does not list JuMP as a docs-env dependency.
- **Fix:** Deleted the dead `using JuMP` line from `docs/literate/pricing_dlmp.jl`. Verified the page's actual behavior is unchanged (it never referenced any JuMP symbol) and the full docs build now proceeds past that page.
- **Files modified:** `docs/literate/pricing_dlmp.jl`
- **Verification:** `julia --project=docs docs/make.jl` exits 0, all six pages render, `docs/src/generated/pricing_dlmp.md` shows the same displayed values as before (unaffected by the import removal).
- **Committed in:** `375c2d2` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug, surfaced only once all six pages were wired into a real `makedocs` run for the first time)
**Impact on plan:** Necessary to make the acceptance criterion "the full docs build exits 0 with no `@example` execution error" true. No scope creep — a one-line dead-import removal in a file this plan was already responsible for wiring into the build; no behavioral change to the page's displayed content.

## Issues Encountered
- The first full-build attempt correctly surfaced the `pricing_dlmp.jl` blocking bug above (see Deviations); a second full build after the fix confirmed exit 0.
- `CairoMakie`/`Makie` precompilation on this machine takes ~7-8 minutes per cold build; both the standalone `admm.jl` verification and the full `docs/make.jl` build were run as background processes to accommodate this.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All six literate pages (toy_dc, lindistflow, convex_branch_flow, prosumer_welfare, pricing_dlmp, admm) are wired into `docs/make.jl` and the full site builds cleanly with `checkdocs = :exports` and a re-resolved `docs/Manifest.toml` that genuinely renders CairoMakie figures.
- The `deploydocs` call's placeholder repo slug (`github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git`) is ready for plan 09-05's human-verify checkpoint to confirm/replace with the real GitHub org/repo before any CI deploy.
- No blockers for 09-05 (the remaining docs-CI-workflow / acceptance-gate wave of this phase).

---
*Phase: 09-documentation-regression-acceptance-gate*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: docs/literate/admm.jl
- FOUND: docs/make.jl (Literate.DocumenterFlavor, checkdocs = :exports, deploydocs)
- FOUND: docs/Manifest.toml (re-resolved, CairoMakie pinned)
- FOUND commit: 7893c66
- FOUND commit: 375c2d2
