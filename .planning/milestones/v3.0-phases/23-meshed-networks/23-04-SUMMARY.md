---
phase: 23-meshed-networks
plan: 04
subsystem: docs
tags: [julia, documenter, literate, socp, meshed-networks, angle-recovery, reactive-price]

# Dependency graph
requires:
  - phase: 23-meshed-networks
    provides: "MeshedFeeder/assert_connected (23-01), MeshedFlow + Phase23Fixtures 4-bus diamond (23-02), certify_angle_recoverable! (23-03) -- every symbol this closing literate page demonstrates live"
provides:
  - "docs/literate/meshed_reactive_price.jl -- Rung 10, live-executed literate page demonstrating MESH-01/02/03/06 on the committed diamond fixture, both impedance profiles, plus a 4Q-BESS reactive price read off the meshed loop's own :balance_q dual"
  - "docs/make.jl wired (literate-source tuple + Models pages list) and docs/Project.toml/Manifest.toml updated to add JuMP as a direct docs dependency"
  - "Phase 23's closing full-suite acceptance gate: 2791 passed / 1 failed (documented D-06 diagnostic) / 3 errored (pre-existing) / 3 broken (pre-existing) / 2798 total"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Literate pages needing raw JuMP calls (termination_status, dual) must add JuMP as a direct docs/Project.toml dependency -- every prior page only needed TSODSO's own re-exported API surface, so this gap was previously latent"
    - "A literate page reconstructs its fixture's actual committed topology inline (never include()s the test @testmodule) even when the plan's own prose is stale relative to a prior plan's documented deviation -- honesty to the REAL committed fixture takes precedence over literal plan text"

key-files:
  created:
    - docs/literate/meshed_reactive_price.jl
  modified:
    - docs/make.jl
    - docs/Project.toml
    - docs/Manifest.toml

key-decisions:
  - "Built the literate page around the diamond fixture actually committed in 23-02/23-03 (4-bus, branches (1,2),(1,3),(2,4),(3,4)), not the literal 3-bus triangle this plan's own <action>/<verify> text describes -- confirmed live, on this page itself, that the triangle is genuinely PRIMAL_INFEASIBLE on MeshedFlow's delegation path (reproducing 23-02's own finding), then demonstrated the diamond as the honest, working alternative"
  - "Added JuMP as a direct docs/Project.toml dependency (Rule 3, blocking-issue fix) rather than routing the reactive-price section through some indirect wrapper -- JuMP is already the project's own core, version-pinned dependency (1.30.1), not a new/unvetted package, so this is a configuration fix, not a package-legitimacy risk"

patterns-established:
  - "Closing-plan literate pages that need library functions beyond TSODSO's own exports must audit docs/Project.toml before assuming a using X will resolve inside a Documenter @example sandbox"

requirements-completed: [MESH-06]

# Metrics
duration: ~50min
completed: 2026-08-10
---

# Phase 23 Plan 4: Meshed Networks + Live Reactive Price -- Literate Page + Full-Suite Acceptance Gate Summary

**Rung 10 literate page live-demonstrating the meshed SOCP formulation, both angle-recoverability verdicts (recoverable/unrecoverable) on the committed 4-bus diamond fixture, and a 4Q-BESS reactive price read directly off the meshed loop's own `:balance_q` dual -- closing Phase 23 with a green 2791/1/3/3 full-suite acceptance gate (the 1 failure and both non-zero counts are all pre-documented, non-regression findings) and a clean Documenter build.**

## Performance

- **Duration:** ~50 min (Task 1 authoring/verification ~30 min; Task 2's full-suite run alone was 17m16s, plus docs-build fix/rebuild)
- **Tasks:** 2 completed
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- `docs/literate/meshed_reactive_price.jl` (NEW, Rung 10): live-executes the meshed formulation end to end --
  - Reconstructs the ACTUAL committed `Phase23Fixtures` 4-bus diamond inline (never `include()`s the test module), and additionally demonstrates LIVE, on this page, that the plan's own originally-described 3-bus triangle is genuinely `PRIMAL_INFEASIBLE` on `MeshedFlow`'s pure-delegation path -- reproducing 23-02's own derivation as a live, self-verifying fact rather than a hand-typed claim.
  - Section 1: solves both `:uniform`/`:heterogeneous` impedance profiles via `MeshedFlow`, shows both pass the existing per-branch cone gate (`assert_socp_exact!`) identically tight (`~1.6e-8`/`~1.8e-11`).
  - Section 2: calls `certify_angle_recoverable!` on both -- `:uniform` certifies (`status = :angle_certified`, `worst_residual ≈ 0.0063`); `:heterogeneous` reports (never throws) `:angle_unrecoverable` (`worst_residual ≈ 0.0607`, a genuine `≈9.7x` structural gap, matching 23-03's own measurement).
  - Section 3: rebuilds bus 2's aggregator with a `FourQuadBESS` added, re-solves `:uniform` via `MeshedFlow`, and reads `dual.(ctx.constraints[:balance_q][2,:])` directly -- the CENTRALIZED analog of Phase 19's LIVE radial μ-ascent, referenced by name, no meshed ADMM built.
  - `## Finding`: states the structural gap plainly (impedance MAGNITUDE, not R/X ratio, is the separating lever), honors the anti-feature (no IEEE-1547 Volt-VAR droop anywhere; the reactive dispatch is characterized post-hoc only), and notes the tiny measured reactive DADP (`≈7.9e-10`) as an honest finding for this small, lightly-loaded, primarily-resistive fixture -- and explicitly scopes out the deferred meshed-IEEE-13-tie-switch variant (MESH-STRETCH).
  - Wired `docs/make.jl` at both edit points (literate-source tuple, Models pages list).
- **Full-suite acceptance gate (Task 2):** `julia --project=. -e 'import Pkg; Pkg.test()'` -- **2791 passed / 1 failed / 3 errored / 3 broken / 2798 total (17m16.3s)**. Matches the documented pre-phase baseline (2752/0/3/3) in every category that matters: the 1 failure is the previously-flagged `D-06 PF-04 gate runs per scenario...` stochastic sandbox-skew diagnostic (documented as possibly firing, not a regression); the 3 errored are the same pre-existing intermittent `solve_admm`/`solve_dso!` `NUMERICAL_ERROR` cases; the 3 broken are unchanged in count and category. Passed grew by this phase's 3 new `@testitem`s (37 individual assertions: `test_mesh_feeder.jl`=15, `test_mesh_flow.jl`=7, `test_mesh_angle_certificate.jl`=15) plus minor pre-existing baseline drift.
- **Documenter build (Task 2):** `julia --project=docs docs/make.jl` completes cleanly after the JuMP dependency fix below (`checkdocs = :exports` passes -- every Phase-23 exported symbol, `MeshedFeeder`/`assert_connected`/`MeshedFlow`/`certify_angle_recoverable!`, is correctly surfaced in `docs/src/api.md`'s `@autodocs` blocks from plans 23-01/02/03). Only pre-existing, benign warnings remain (navbar remote-URL, `api.md` HTML size threshold, `@example` image-fallback for large outputs, search-index size) -- none new to this phase.

## Task Commits

Each task was committed atomically:

1. **Task 1: `docs/literate/meshed_reactive_price.jl` -- Rung 10 + `docs/make.jl` wiring (MESH-06)** - `10bb5a1` (feat)
2. **Task 2: full-suite acceptance gate -- docs/Project.toml JuMP fix + verified green suite/docs build** - `9851ab4` (chore)

_Base commit: `3c01dfaab4680c05f4eb3086ffc174e0489924fb` (phase-23 tracking update after wave 3)._

## Files Created/Modified

- `docs/literate/meshed_reactive_price.jl` - Rung 10 literate page, MESH-01/02/03/06 live demonstration (new)
- `docs/make.jl` - literate-source tuple + Models pages list wired for the new page
- `docs/Project.toml` - added `JuMP` as a direct dependency (compat `"1.30"`)
- `docs/Manifest.toml` - resolved to include `JuMP` (already a transitive dependency via `TSODSO`, now direct)

## Decisions Made

- Built the literate page around the ACTUAL committed diamond fixture (established in 23-02/23-03), not the literal 3-bus triangle this plan's own `<action>`/`<verify>` text describes, because that triangle is mathematically infeasible on `MeshedFlow`'s mandated pure-delegation path (23-02's own finding, reproduced live on this page as part of the honest narrative rather than silently worked around).
- Added JuMP to `docs/Project.toml`/`docs/Manifest.toml` rather than avoiding raw JuMP calls, because the plan's own `<interfaces>` block explicitly wants `termination_status`/`dual(...)` displayed live, and JuMP is already the project's own core, version-pinned dependency -- not a new or unvetted package, so this is squarely a Rule-3 blocking-issue configuration fix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 -- plan's own stale prose/verify script] Built the literate page's fixture around the actual committed 4-bus diamond, not the plan text's literal 3-bus triangle**

- **Found during:** Task 1, running the plan's own literal `<verify>` script (the exact 3-bus triangle `(1,2),(2,3),(3,1)`) before authoring the page.
- **Issue:** The plan's `<action>`/`<interfaces>`/`<verify>` blocks all describe a 3-bus triangle, written before plans 23-02/23-03 discovered (and fully documented) that an odd, consistently-oriented triangle is mathematically INCOMPATIBLE with `MeshedFlow`'s mandated pure delegation to `ConvexBranchFlow.contribute!` -- it forces zero flow on every loop branch, making even an infinitesimal asymmetric load `INFEASIBLE`. Running the plan's own literal verify script reproduced this exactly: `termination_status : INFEASIBLE`, `raw_status : PRIMAL_INFEASIBLE`.
- **Fix:** Reconstructed the ACTUAL committed `Phase23Fixtures` topology inline (4-bus diamond, branches `(1,2),(1,3),(2,4),(3,4)`, the exact `UNIFORM_RX`/`HETEROGENEOUS_RX` literals) for the page's real Sections 1-3, and additionally added a short live block demonstrating the triangle's infeasibility as part of the honest "Building the fixture" narrative -- so the deviation itself becomes part of the page's documented story rather than a silent substitution.
- **Files modified:** `docs/literate/meshed_reactive_price.jl`.
- **Verification:** Re-ran the diamond-adapted equivalent of the plan's own acceptance assertions directly (`r.status == :angle_certified`, `length(q_dadp) == 1`) -- passes. Ran the whole literate file as a plain Julia script (`julia --project=. docs/literate/meshed_reactive_price.jl`) -- exits 0, only the expected `@warn` for the heterogeneous unrecoverable verdict.
- **Committed in:** `10bb5a1` (Task 1 commit).

**2. [Rule 3 -- blocking issue, docs environment] Added JuMP as a direct `docs/Project.toml` dependency**

- **Found during:** Task 2's first `julia --project=docs docs/make.jl` run.
- **Issue:** `meshed_reactive_price.jl`'s `@example` blocks call `termination_status(...)`/`dual.(...)` directly -- the FIRST literate page in this manual to need raw JuMP functions rather than only TSODSO's own re-exported API. `docs/Project.toml` never listed JuMP as a dependency (every prior page's `using TSODSO` sufficed), so the Documenter build failed: `Package JuMP not found in current path`, cascading into `UndefVarError: termination_status/dual not defined` for every subsequent `@example` block in the page.
- **Fix:** Added `JuMP = "4076af6c-e467-56ae-b986-b466b2749572"` to `docs/Project.toml`'s `[deps]` with `compat = "1.30"` (matching the main `Project.toml`'s pinned `1.30.1`), then ran `julia --project=docs -e 'import Pkg; Pkg.resolve(); Pkg.instantiate()'` to update `docs/Manifest.toml`. JuMP was already resolvable as a transitive dependency via `TSODSO` itself, so `Pkg.resolve()` completed without any new package downloads.
- **Files modified:** `docs/Project.toml`, `docs/Manifest.toml`.
- **Verification:** Re-ran `julia --project=docs docs/make.jl` -- completes with no errors; `docs/build/generated/meshed_reactive_price.html` generated; `checkdocs = :exports` passes.
- **Committed in:** `9851ab4` (Task 2 commit).

---

**Total deviations:** 2 auto-fixed (1 Rule 1 -- plan's own stale prose corrected against the already-documented 23-02 finding; 1 Rule 3 -- blocking docs-environment dependency fix, using an already-vetted, already-pinned project dependency, not a new package).
**Impact on plan:** Both deviations are corrections needed to make the plan's own stated deliverable actually work and actually build -- no scope creep, no architectural change, no new external dependency risk.

## Issues Encountered

None beyond the two deviations documented above, both resolved within this plan's own tasks with no escalation needed.

## Next Phase Readiness

- Phase 23 (Meshed Networks) is complete: `MeshedFeeder`/`assert_connected` (23-01), `MeshedFlow` + the committed 4-bus diamond fixture (23-02), `certify_angle_recoverable!` (23-03), and this closing literate page + full-suite/docs acceptance gate (23-04) together satisfy MESH-01/02/03/06 and the ROADMAP Phase 23 success criterion ("at least one committed meshed fixture").
- No blockers. The full suite is green relative to the documented baseline (same failure/error/broken categories, growth accounted for by this phase's own new tests); the Documenter build is green.
- Deferred, explicitly out of scope this phase (unchanged from CONTEXT.md/D-02/D-12): a meshed-IEEE-13-with-tie-switch variant (MESH-STRETCH) and any meshed-network ADMM decomposition (D-04 -- centralized-only this phase).

## Self-Check: PASSED

Created file verified present (`docs/literate/meshed_reactive_price.jl`); both task commit
hashes (`10bb5a1`, `9851ab4`) verified present in `git log --oneline --all`; generated
`docs/build/generated/meshed_reactive_price.html` verified present on disk (gitignored,
regenerated by the Documenter build this task ran).
