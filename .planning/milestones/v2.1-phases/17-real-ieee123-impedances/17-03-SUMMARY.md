---
phase: 17-real-ieee123-impedances
plan: 03
subsystem: test-validation
tags: [socp-exactness, voltage-binding, ieee123, admm]

# Dependency graph
requires:
  - phase: 17-02
    provides: "real per-segment IEEE-123 Ω impedances wired into ieee123_modified() via to_pu_impedance"
provides:
  - "test/test_ieee123_admm.jl: a numeric voltage-binding margin @testitem asserting the solved min/max |V| against the [0.9,1.1] band with documented, actual-observed thresholds"
  - "test/fixtures_phase7.jl: re-tuned LOAD_SCALE_IEEE123/PV_SCALE_IEEE123/DEV_SCALE_IEEE123 that restore SOCP exactness and ADMM behavioral bounds on the real-impedance feeder"
affects:
  - "Phase 18 (directional thesis reproduction): the IEEE-123 voltage-binding case now runs on real impedances with a documented, honest (asymmetric) voltage-binding margin -- Phase 18 must not assume the original synthetic-era 0.92/1.08 figures"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Population-scale re-tune search performed empirically (bisection/sweep over LOAD_SCALE/PV_SCALE), never by touching impedance/topology files -- the project's documented seam for this class of regression (17-PATTERNS.md 'TestItems @testmodule fixture-population seam')"

key-files:
  created: []
  modified:
    - test/test_ieee123_admm.jl
    - test/fixtures_phase7.jl

key-decisions:
  - "Re-tuned LOAD_SCALE_IEEE123 (0.03->0.05), PV_SCALE_IEEE123 (0.06->0.12), DEV_SCALE_IEEE123 (0.05->0.0833, ratio to load held at 5/3) after the original triple broke solve_welfare's SOCP-exactness gate outright on the real-impedance feeder (worst gap ratio 1.378 > 1) -- confirmed via an exhaustive empirical sweep, never by touching src/data/ieee123.jl or src/data/ieee123_impedances.jl."
  - "Widened the voltage-binding @testitem's thresholds from the originally-attempted 0.92 (lower) / 1.08 (upper) to the actual observed values (vmin_solved<=0.95, vmax_solved>=1.005; actual observed 0.9487/1.0105) per the plan's own documented fallback -- both the original attempt and the actual observed numbers are recorded inline so a future regression toward 'less binding' is still caught."
  - "Documented an HONEST, asymmetric finding rather than forcing symmetric binding: on this real-impedance feeder, the lower voltage band (toward 0.9) transfers well under load-scaling, but the upper band (toward 1.1) does not -- any population scale that pushes the solved max meaningfully above ~1.02-1.03 pu drives the SOC relaxation genuinely inexact before reaching 1.08 (the same high-PV/reverse-flow exactness boundary Phase 15's EXACT-04 finding documents on IEEE-13, hit here unintentionally rather than as a deliberate stress test)."

requirements-completed: [IMPED-03]

# Metrics
duration: ~70min
completed: 2026-07-26
---

# Phase 17 Plan 03: Voltage-Binding Re-Verification + Population Re-Tune Summary

Added the first-ever numeric voltage-binding assertion for the real-impedance IEEE-123 case and re-tuned the population scale (`test/fixtures_phase7.jl` only, impedances/topology untouched) after discovering the original scale broke SOCP exactness outright on the real feeder — settling on an honestly-documented, asymmetric voltage-binding regime (strong lower-band binding, weak upper-band binding, both numerically pinned).

## Performance

- **Duration:** ~70 min (includes an extensive empirical population-scale search across ~50 solve_welfare invocations)
- **Tasks:** 2 completed
- **Files modified:** 2 (test/test_ieee123_admm.jl, test/fixtures_phase7.jl)

## KEY OPEN QUESTION — Answered

**Does the IEEE-123 case remain voltage-binding once real impedances replace the synthetic uniform R=0.005/X=0.0025?**

**Answer: Partially, and asymmetrically — with numbers.**

- At the ORIGINAL population scale (`LOAD_SCALE=0.03`, `PV_SCALE=0.06`, `DEV_SCALE=0.05`, unchanged
  from the synthetic-impedance era), the real-impedance feeder's centralized `solve_welfare` SOCP
  relaxation is **outright INEXACT** (worst gap ratio 1.378 > 1) — `assert_socp_exact!` throws and
  refuses prices before any voltage can even be inspected. This is the exact regression flagged in
  17-02-SUMMARY.md.
- After the re-tune (`LOAD_SCALE=0.05`, `PV_SCALE=0.12`, `DEV_SCALE≈0.0833`), the relaxation is
  exact (`socp_maxgap ≈ 1.1e-6`) and the solved voltage extremes are:
  **`vmin_solved ≈ 0.9487`, `vmax_solved ≈ 1.0105`** (both logged via `@info` in the new testitem).
- An exhaustive empirical search (population-scale sweep over `LOAD_SCALE_IEEE123` ×
  `PV_SCALE_IEEE123`, ~50 `solve_welfare` calls, never touching impedance/topology files) found the
  achievable regime under real impedances is **genuinely asymmetric**:
  - The **lower** band (voltage drop toward 0.9) transfers reasonably well: pure load-scaling alone
    (e.g. `LOAD_SCALE=0.075`, `PV_SCALE=0.03`) reaches `vmin_solved ≈ 0.931` while staying exact,
    with the network going primal-infeasible only beyond `LOAD_SCALE ≈ 0.077`.
  - The **upper** band (voltage rise toward 1.1, driven by PV reverse-flow) does **not** transfer:
    every combination tried that pushed the solved max meaningfully above `≈1.02-1.03` pu drove the
    SOC relaxation genuinely inexact (worst gap ratios 1.2-10+) before reaching anywhere close to
    1.08. This is the SAME high-PV/reverse-flow exactness boundary Phase 15's EXACT-04 finding
    documents (pv_scale=1.2 on the IEEE-13 stress fixture, pinned at `V²max=1.1025`) — encountered
    here as an unintentional side-effect of trying to restore symmetric binding, not as a
    deliberate stress test. The exactness/vmax relationship near this boundary is genuinely
    non-monotonic/chaotic (small population-scale perturbations flip exact↔inexact
    unpredictably), consistent with a true numerical-boundary phenomenon rather than a smooth
    tuning curve.
- **Bottom line:** the real-impedance IEEE-123 case remains meaningfully voltage-binding on the
  LOWER side (a ~7 pu-percentage-point drop from nominal, close to the 0.9 floor) but is only
  WEAKLY binding on the UPPER side (~1 pu-percentage-point rise) while the SOC relaxation stays
  exact. Forcing stronger upper-band binding is possible but trades away exactness — the two
  properties are in genuine tension on this specific real-data network, not merely a
  population-scale-tuning inconvenience.

## Accomplishments
- Added `test/test_ieee123_admm.jl`'s new `@testitem "ieee123 admm: voltage-binding margin
  (ieee123, crossval)"`: computes `Vall = sqrt.(value.(ctx_c.meta[:pf_vars].v))` on the centralized
  solve, logs `vmin_solved`/`vmax_solved` via `@info`, and asserts both against the `[0.9,1.1]`
  band with widened, actual-observed thresholds (documented alongside the originally-attempted
  0.92/1.08 starting values). A strict sanity floor (`vmin_solved > 0.9`, `vmax_solved < 1.1`) is
  retained.
- Diagnosed the pre-existing SOCP-inexactness regression flagged in 17-02-SUMMARY.md (worst gap
  ratio 1.378) via an isolated diagnostic harness (scratch scripts, not committed) reproducing
  `Phase7Fixtures`'s house-aggregator shape at adjustable scale.
- Ran an exhaustive empirical population-scale search (~50 `solve_welfare` invocations across
  uniform-multiplier sweeps, load-only sweeps, PV-only sweeps, and combined sweeps) to characterize
  the achievable voltage-binding/exactness trade-off on the real-impedance feeder.
- Re-tuned `test/fixtures_phase7.jl`'s three population-scale constants (never impedance/topology
  files) to the best-available joint operating point, with a full before/after/broken-bound
  documentation block committed directly above the constants.
- Re-verified ALL existing ADMM/acceptance behavioral bounds pass cleanly at the new scale:
  `res.iters<300`, `res.iters<=100`, `isapprox(res.welfare, obj_c; rtol=1e-4)`,
  `res.exact_maxgap<1e-3`, `isapprox(res.λ, dlmp_c; atol=1e-2, rtol=1e-3)` — both in
  `test_ieee123_admm.jl`'s crossval item and `test_acceptance.jl`'s IEEE-123 acceptance item.
- Ran the full suite (`julia test/runtests.jl`, scoped via an explicit worktree path to avoid the
  known `.claude/worktrees/` TestItemRunner cross-contamination gotcha): 2343 passed, 1 failed
  (known Aqua "Persistent tasks" Project.toml-drift failure, pre-existing/local, not caused by this
  plan), 3 broken (pre-existing `@test_broken` markers) — within the documented acceptable-failure
  baseline.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the numeric voltage-binding @testitem** - `d42f363` (test)
2. **Task 2: Re-verify ADMM behavioral bounds; re-tune population scale** - `623d8d0` (fix)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified
- `test/test_ieee123_admm.jl` - New `@testitem "ieee123 admm: voltage-binding margin (ieee123,
  crossval)"` asserting the solved min/max `|V|` against the `[0.9,1.1]` band; existing crossval
  item unchanged.
- `test/fixtures_phase7.jl` - `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123` re-tuned
  (0.03/0.06/0.05 -> 0.05/0.12/0.0833); a full before/after/broken-bound documentation comment block
  added directly above the three constants.

## Decisions Made
- Diagnosed via scratch/uncommitted Julia scripts (deleted before the final commit) rather than
  modifying any committed test/src file during the investigation phase — kept the committed diff
  surgical (only the two files the plan's `files_modified` frontmatter declares).
- Chose the re-tune triple by maximizing the JOINT (lower-band, upper-band) voltage-binding margin
  subject to the hard constraint of SOCP exactness and ADMM/acceptance behavioral-bound
  preservation, rather than optimizing either band in isolation — e.g. rejected a load-only
  re-tune (`LOAD_SCALE=0.075`, `PV_SCALE=0.03`: `vmin≈0.931`, `vmax≈1.0` exactly, i.e. NO upper-band
  movement at all) in favor of the chosen `LOAD_SCALE=0.05`/`PV_SCALE=0.12` combination, which
  trades a slightly weaker lower bound (`0.9487` vs `0.931`) for a genuinely non-trivial upper-band
  excursion (`1.0105` vs exactly `1.0`).
- Held `DEV_SCALE_IEEE123`'s ratio to `LOAD_SCALE_IEEE123` fixed at the original `5/3`
  (`0.05/0.03`) rather than independently re-deriving it — the plan's own read_first material
  documents this ratio as the seam that keeps flexible-device ratings at residential order without
  a single house dominating the feeder; no bound in the read_first material required touching it
  independently.
- Verified via explicit-path `TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=...)` rather
  than bare `julia -e '... @run_package_tests ...'` for scoped runs, per the project's own recorded
  memory (`local-project-toml-drift.md`): bare `@run_package_tests` invoked via `-e` resolves its
  package-test-root two directories up from the eval'd expression's (non-real) source file,
  discovering and running sibling `.claude/worktrees/*` agents' test copies alongside this
  worktree's — the full-suite run via `julia test/runtests.jl` (a real file, not `-e`) does not have
  this issue and was used unmodified per the plan's `<test_env_note>`.

## Deviations from Plan

**1. [Rule 1 - Bug/discovery, within declared scope] The plan's Task 1 could not be verified before Task 2's fix.**
- **Found during:** Task 1's own `<verify>` step.
- **Issue:** The plan sequences Task 1 (add voltage-binding testitem) before Task 2 (re-tune
  scale if required), but the ORIGINAL population scale broke `solve_welfare`'s SOCP-exactness
  gate outright (`assert_socp_exact!` threw), so Task 1's testitem could not even reach its own
  assertions — this is exactly the regression 17-02-SUMMARY.md's "Next Phase Readiness" section
  flagged as Plan 17-03's first concrete task.
- **Fix:** Performed Task 2's population-scale investigation/re-tune FIRST (as an uncommitted
  working-tree change) to unblock Task 1's test, then committed each task's file in the plan's
  declared order (Task 1's test file first, Task 2's fixture file second) — both commits reflect
  a working tree in which the new testitem genuinely passes, satisfying each task's own
  `<verify>`/acceptance criteria independently and in the declared sequence.
- **Files modified:** test/test_ieee123_admm.jl (Task 1 commit), test/fixtures_phase7.jl (Task 2
  commit) — exactly the plan's declared `files_modified`.
- **Commits:** `d42f363`, `623d8d0`

No other deviations — every other action matches the plan's explicit instructions, including the
requirement that impedance/topology files (`src/data/ieee123.jl`, `src/data/ieee123_impedances.jl`)
were never touched to compensate for the population-scale problem.

## Issues Encountered

- **`.claude/worktrees/` TestItemRunner cross-contamination on bare `-e` invocations.** Running
  `julia -e 'using TestItemRunner; @run_package_tests filter=...'` resolves the package-test-root
  via `dirname(__source__.file)/..`, and for an `-e`-evaluated expression `__source__.file` is not a
  real path, causing the macro to resolve TWO directories up from the process's `pwd()` (i.e.
  `.claude/worktrees/` itself) rather than this worktree's own `test/` directory — discovering and
  running a SIBLING worktree agent's `test_ieee123_admm.jl` copy in the same run (observed directly:
  a second `agent-a5ed290be5eecbc99/test/test_ieee123_admm.jl` path appeared in one scoped-run's
  output, which was NOT this worktree). This is the exact gotcha already recorded in this project's
  own `local-project-toml-drift.md` memory. Resolved by using
  `TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=...)` (an explicit absolute path) for
  all scoped verification runs; the full-suite `julia test/runtests.jl` command works correctly
  unmodified because it is a real file (not `-e`), so `__source__.file` resolves correctly.
- **The population-scale/exactness relationship near the boundary is genuinely non-monotonic.**
  Small perturbations to `PV_SCALE_IEEE123` (e.g. 0.5% steps) flip the SOCP relaxation between
  exact and inexact unpredictably (observed: 0.045 exact, 0.05 inexact, 0.055 exact, 0.06 inexact
  at fixed `LOAD_SCALE=0.07`) — consistent with a genuine numerical-boundary phenomenon (matching
  Phase 15's own characterization of the high-PV exactness boundary), not a smooth function that
  can be "dialed in" precisely. The chosen re-tune values were confirmed to sit with reasonable
  margin from this boundary (`socp_maxgap ≈ 1.1e-6`, well inside the `atol=1e-6`+`rtol·cone`
  combined threshold), not exactly on the knife-edge.

## Next Phase Readiness
- The real-impedance IEEE-123 case now has a genuine, numerically-pinned, honestly-documented
  voltage-binding characterization (asymmetric: strong lower-band, weak upper-band) that Phase 18
  (directional thesis reproduction) can build on without assuming the original synthetic-era
  0.92/1.08 figures transfer.
- `test/fixtures_phase7.jl`'s population-scale re-tune is the SOLE seam touched; `src/data/`
  impedance/topology files remain exactly as Plan 17-02 left them.

## Self-Check: PASSED

- FOUND: test/test_ieee123_admm.jl
- FOUND: test/fixtures_phase7.jl
- FOUND: .planning/phases/17-real-ieee123-impedances/17-03-SUMMARY.md
- FOUND commit: d42f363 (test(17-03): add numeric voltage-binding margin assertion for real-impedance IEEE-123)
- FOUND commit: 623d8d0 (fix(17-03): re-tune IEEE-123 population scale for real-impedance exactness)

---
*Phase: 17-real-ieee123-impedances*
*Completed: 2026-07-26*
