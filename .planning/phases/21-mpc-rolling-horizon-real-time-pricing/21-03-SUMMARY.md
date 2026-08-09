---
phase: 21-mpc-rolling-horizon-real-time-pricing
plan: 03
subsystem: models
tags: [jump, parameter, mpc, rolling-horizon, build-once, testitem]

# Dependency graph
requires:
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plan 21-01)
    provides: "PVBattery/Thermostatic/FourQuadBESS soc0/Tin0 IC Parameters,
      PVBattery.Ppv_param, Thermostatic.Tout_param, Aggregator.Pdc_param — the widened
      device return-tuple shapes this plan reads from ctx.meta[:agg_device_vars]"
  - phase: 10-stackelberg-nash-planning-equilibrium (plan 10-02)
    provides: "PlanningOracle/build_planning_oracle's build-once/Parameter-re-solve SHAPE
      (src/planning/subproblem.jl) — the ONLY prior build-once model in this codebase,
      generalized here from a single z-pin to the full set of per-step device Parameters"
provides:
  - "MpcWindow{F} struct + build_mpc_window(feeder, pf, aggregators; H, terminal_soc=true)
    + solve_mpc_window!(o; max_attempts=4, attempts_out=nothing) — the build-once
    [τ=1:H] welfare-shaped window model MPC-01's rolling-horizon step re-solves"
  - "MpcWindow.ic_handles::Vector{<:NamedTuple} — (; bus, kind::Symbol (:soc|:Tin),
    ic_param, terminal_param) per stateful device; MpcWindow.agg_pdc_handles — (; bus,
    Pdc_param) per aggregator"
  - "terminal_soc::Bool build-time toggle (MPC-02, D-06): true adds a hard
    soc[H] == terminal_param equality per battery-like device via an anonymous
    Parameter; false omits it entirely (a genuinely different model, not a no-op)"
  - "test/fixtures_phase21.jl: Phase21Fixtures @testmodule (mpc_feeder/
    build_mpc_aggregators short-T=8/H=3 happy-path fixture, mpc_high_pv_feeder/
    build_mpc_high_pv_aggregators the 3-bus forced-inexact substrate for a later wave)"
affects: [21-04, 21-05, 21-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-once receding-horizon window: mirrors PlanningOracle's shape (formulation-
      generic model factory, verbatim contribute! reuse, free-sign frontier, balance
      registration) but generalizes from ONE z-pin Parameter to the FULL widened device
      Parameter set (soc0/Tin0/Ppv_param/Tout_param/Pdc_param) plus a build-time
      terminal-condition toggle."
    - "Anonymous per-device Parameter/constraint for a build-time structural toggle:
      `@variable(model, base_name = \"...\", set = Parameter(v))` (no container/name
      syntax) avoids an object-dictionary symbol collision when the SAME toggle applies
      to multiple battery-like devices in one model — the same anonymity discipline
      FourQuadBESS's apparent-power cone already establishes in this codebase."
    - "Frontier price λ₀/p_import is NEVER a Parameter (Pitfall 2) — it slides via
      set_objective_coefficient, mirroring AgrOpt.jl's own avoidance of the
      Parameter-times-variable bilinear failure; MpcWindow's objective is built with a
      placeholder 0.0 coefficient that the caller (a later wave) always overwrites
      before the first solve."

key-files:
  created:
    - src/models/mpc_window.jl
    - test/fixtures_phase21.jl
    - test/test_mpc_window.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md

key-decisions:
  - "MpcWindow's field order and build_mpc_window/solve_mpc_window!'s exact signatures
    are pinned verbatim below for a later wave's mpc_loop.jl to call directly."
  - "ic_handles is built by walking ctx.meta[:agg_device_vars] (a Dict{Int,Vector{Any}}
    keyed by aggregator bus) rather than by asking each device type — this keeps
    build_mpc_window device-agnostic: any future stateful device that starts returning
    a soc0/Tin0 Parameter is picked up automatically, with no build_mpc_window edit."
  - "Test 3 (non-no-op soc0) builds its own window with terminal_soc = false to isolate
    the IC-parameter effect from the terminal-target constraint; Test 4 covers the
    toggle's structural effect independently."
  - "test_mpc_window.jl's build-once regression uses 3 explicit soc0/terminal-target
    pairs chosen to stay within the fixture battery's 2-step reachability envelope
    (±2·Pmax/η ≈ ±0.0042 pu over H-1=2 steps) — an arbitrary/unbounded target pair
    produced a genuine INFEASIBLE solve on the third cycle during verification (see
    Deviations below), which is the model correctly refusing an unreachable SOC
    trajectory, not a bug in build_mpc_window."

patterns-established:
  - "Pattern: MPC-01/MPC-02 build-once window — a future receding-horizon orchestrator
    (mpc_loop.jl) builds ONE MpcWindow per (feeder, aggregators, H, terminal_soc)
    combination and re-solves it every step via set_parameter_value on ic_handles/
    agg_pdc_handles plus set_objective_coefficient on p_import, never rebuilding."

requirements-completed: [MPC-01, MPC-02]

# Metrics
duration: 45min
completed: 2026-08-09
---

# Phase 21 Plan 03: Build-once MpcWindow (MPC-01/MPC-02) Summary

**`MpcWindow`/`build_mpc_window`/`solve_mpc_window!` — a build-once, fixed-length `[τ=1:H]` welfare-shaped JuMP model generalizing `PlanningOracle`'s single-`z`-pin build-once precedent to the FULL set of per-step device Parameters (soc0/Tin0/Ppv_param/Tout_param/Pdc_param) plus an optional hard terminal-SOC toggle, with `num_variables`/`num_constraints` provably unchanged across heterogeneous re-solves.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-08-09 (worktree base commit `1f0e5dc`)
- **Completed:** 2026-08-09
- **Tasks:** 3/3 completed
- **Files modified:** 5 (3 created, 2 modified)

## Accomplishments

- `src/models/mpc_window.jl`: `MpcWindow{F}` struct (`model`, `ctx`, `H`, `agg_bus`,
  `feeder`, `p_import`, `ic_handles`, `agg_pdc_handles`, `terminal_soc`) +
  `build_mpc_window(feeder, pf, aggregators; H, terminal_soc = true)` +
  `solve_mpc_window!(o; max_attempts = 4, attempts_out = nothing)`, mirroring
  `PlanningOracle`'s build-once shape (`src/planning/subproblem.jl`) exactly, generalized
  from one `z`-pin to the full widened device-Parameter set.
- `terminal_soc = true` adds ONE anonymous hard equality `soc[H] == terminal_param` per
  battery-like device (MPC-02, D-06); `terminal_soc = false` omits it entirely — a
  genuinely different model (proven by `num_constraints` inequality, not a no-op flag).
  Thermostatic's `:Tin` entries never carry a terminal target (D-07).
- `p_import`/`λ₀` is NEVER wrapped in a `Parameter` (Pitfall 2) — the objective's
  `p_import` coefficient starts at a documented placeholder `0.0` and slides via
  `set_objective_coefficient` only.
- `test/fixtures_phase21.jl`: `Phase21Fixtures` `@testmodule` with the phase's short-`T`
  (T=8, H=3) happy-path 2-bus fixture (`mpc_feeder`/`build_mpc_aggregators`, Thermostatic +
  PVBattery only — no scheduled-load device, Pitfall 8) and the 3-bus high-PV forced-inexact
  substrate (`mpc_high_pv_feeder`/`build_mpc_high_pv_aggregators`, caller-supplied `pv_scale`
  with no default) a later wave calibrates.
- `test/test_mpc_window.jl`: 4 permanent `@testitem`s — boundary guards, build-once
  invariance across 3 heterogeneous re-solve cycles (soc0/Tin0/terminal-target/forecast
  slices + λ₀, all kept within the fixture battery's reachability envelope), non-no-op
  `set_parameter_value` on `soc0`, and the `terminal_soc` toggle's structural difference.

## Task Commits

Each task was committed atomically:

1. **Task 1: MpcWindow struct + build_mpc_window (build-once model, terminal-SOC toggle)** - `8c2bf75` (feat)
2. **Task 2: Phase21Fixtures — the phase's short-T CI substrate + high-PV forced-inexact fixture** - `feb0eb7` (test)
3. **Task 3: test_mpc_window.jl — build-once invariance + non-no-op Parameter re-solve correctness** - `9d3240c` (test)

_No TDD RED/GREEN/REFACTOR gate sequence — Task 1 is `tdd="true"` but, like the project's
established `PlanningOracle`/`MpcTrace` precedents, this is a from-scratch new-file build-once
seam verified via an inline `<verify>` script (which fails before the file exists, serving the
RED-gate role) rather than a separate persistent RED test commit; the single `feat` commit lands
the passing implementation directly. Task 3 supplies the permanent, checked-in `@testitem`
coverage in its own `test` commit._

## Files Created/Modified

- `src/models/mpc_window.jl` — `MpcWindow{F}` struct, `build_mpc_window`,
  `solve_mpc_window!`; exports all three.
- `test/fixtures_phase21.jl` — `Phase21Fixtures` `@testmodule`: `T`, `H`, the App. C
  battery triple, fixture-tuning constants, `temperature_profile`, `mpc_lambda0`,
  `mpc_feeder`, `build_mpc_aggregators`, `mpc_high_pv_feeder`,
  `build_mpc_high_pv_aggregators`.
- `test/test_mpc_window.jl` — 4 `@testitem`s tagged `[:mpc_window]`, `setup =
  [Phase21Fixtures]`.
- `src/TSODSO.jl` — one new `include("models/mpc_window.jl")` line after
  `models/mpc_trace.jl` (plan 21-02's line).
- `docs/src/api.md` — extended the `## MPC / Rolling-Horizon` section's `Pages` list with
  `"models/mpc_window.jl"`.

## Decisions Made

- `build_mpc_window`'s signature is
  `build_mpc_window(feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator}; H::Int, terminal_soc::Bool = true) -> MpcWindow`.
- `solve_mpc_window!`'s signature is
  `solve_mpc_window!(o::MpcWindow; max_attempts::Int = 4, attempts_out::Union{Nothing,Ref{Int}} = nothing) -> Model`
  (a one-line delegation to `solve_with_retry!`).
- `MpcWindow`'s final field order: `model::Model`, `ctx::ModelContext`, `H::Int`,
  `agg_bus::Int`, `feeder::F`, `p_import::Vector{VariableRef}`,
  `ic_handles::Vector{<:NamedTuple}`, `agg_pdc_handles::Vector{<:NamedTuple}`,
  `terminal_soc::Bool`.
- `ic_handles` entries: `(; bus::Int, kind::Symbol, ic_param, terminal_param)`, `kind ∈
  (:soc, :Tin)`, `terminal_param` is `nothing` unless `kind == :soc && terminal_soc`.
- `agg_pdc_handles` entries: `(; bus::Int, Pdc_param)`.
- Terminal-target Parameters are built ANONYMOUSLY (`@variable(model, base_name = "...",
  set = Parameter(v))`, no container/name syntax) so multiple battery-like devices never
  collide on a shared object-dictionary symbol — the same discipline `FourQuadBESS`'s
  anonymous apparent-power cone already establishes in this codebase.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Comments in `test/fixtures_phase21.jl` literally containing the string
"Deferrable" broke the plan's own acceptance-criteria grep**
- **Found during:** Task 2, immediately after writing the file's explanatory header
  comment and docstrings.
- **Issue:** The plan's Task 2 acceptance criteria require
  `grep -n 'Deferrable' test/fixtures_phase21.jl` to return NO matches (a blunt textual
  grep with no comment/code distinction). My first draft's header comment and two
  docstrings explained the deliberate exclusion using the literal word "Deferrable",
  which the grep flags regardless of context.
- **Fix:** Rewrote every mention to describe the excluded device type obliquely (e.g.
  "the project's scheduled-energy-budget flexible-load device") without ever spelling
  the literal identifier, preserving the substantive explanation (Pitfall 8: its
  within-window energy budget resets every window under a rolling horizon).
- **Files modified:** `test/fixtures_phase21.jl`
- **Verification:** `grep -n 'Deferrable' test/fixtures_phase21.jl` now returns no matches.
- **Committed in:** `feb0eb7` (Task 2 commit — fixed before the first commit, not a
  follow-up).

**2. [Rule 1 - Bug] Similarly, a docstring comment in `test/test_mpc_window.jl` literally
containing the string "@testitem" broke the plan's own acceptance-criteria count**
- **Found during:** Task 3, verifying `grep -c '@testitem' test/test_mpc_window.jl`
  returns exactly 4 as required.
- **Issue:** Test 3's body contained an explanatory comment referencing "Task 4's own
  `@testitem`", which the literal-string grep counted as a fifth `@testitem` occurrence.
- **Fix:** Reworded the comment to "the FINAL test item below" — same substance, no
  literal `@testitem` token.
- **Files modified:** `test/test_mpc_window.jl`
- **Verification:** `grep -c '@testitem' test/test_mpc_window.jl` returns `4`.
- **Committed in:** `9d3240c` (Task 3 commit — fixed before the commit).

**3. [Rule 1 - Bug] The build-once regression's first-drafted soc0/terminal-target pairs
were numerically unreachable within the fixture battery's per-window charge/discharge
envelope, producing a genuine `INFEASIBLE` solve on the third re-solve cycle**
- **Found during:** Task 3, standalone verification of the build-once `@testitem`'s body
  (run as a plain script per the orchestrator's tooling note, since TestItemRunner is not
  invoked under `--project=.` in this plan) before committing.
- **Issue:** The fixture battery has `Pmax = 0.1·LOAD_SCALE_MPC = 0.002` pu and
  `η = 0.95`, so over `H − 1 = 2` steps the maximum reachable `|Δsoc|` is
  `2·Pmax/η ≈ 0.0042` pu (discharge direction) or `2·η·Pmax ≈ 0.0038` pu (charge
  direction). The initial draft's third cycle asked for `soc0 = 0.001 → term = 0.007`
  (`Δsoc = 0.006`), exceeding both bounds — `solve_with_retry!` correctly refused the
  resulting genuinely infeasible model (`MOI.INFEASIBLE`, never retried, per
  `RETRYABLE_STATUSES`), which is `build_mpc_window`/`solve_mpc_window!` behaving
  CORRECTLY, not a defect in either.
- **Fix:** Re-derived all three cycles' `soc0`/`term` pairs to stay strictly inside the
  reachability envelope (verified empirically with a standalone script re-running each
  cycle's raw `optimize!` status before committing to the permanent test), and updated
  both the permanent `test/test_mpc_window.jl` and my own verification script
  accordingly. No change to `src/models/mpc_window.jl` — the model's constraints are
  physically correct as specified; only the TEST's own trial values needed reconsidering.
- **Files modified:** `test/test_mpc_window.jl` (values corrected before the file was
  ever committed).
- **Verification:** All three cycles now solve `OPTIMAL`/`FEASIBLE_POINT`; the full
  4-`@testitem` body re-run (via a standalone re-implementation script, since
  TestItemRunner is out of scope for this plan) passes end-to-end.
- **Committed in:** `9d3240c` (Task 3 commit — the file was written correctly before
  its first and only commit; no follow-up fix commit was needed).

---

**Total deviations:** 3 auto-fixed (all Rule 1 — two verification-script/acceptance-grep
mismatches caught before committing, and one test-fixture numeric-envelope miscalibration
caught and corrected before committing). No deviation required any change to
`src/models/mpc_window.jl` itself, which matches the plan's `<action>` specification exactly.
**Impact on plan:** None — every fix landed inside its own task's FIRST commit; no plan
requirement was weakened, and `build_mpc_window`'s boundary guards / terminal-SOC mechanism /
Parameter re-solve invariants all hold exactly as specified.

## Issues Encountered

None beyond the three auto-fixed deviations documented above, all caught during this plan's
own pre-commit verification (not discovered later).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `MpcWindow`/`build_mpc_window`/`solve_mpc_window!`'s exact signatures and `MpcWindow`'s
  final field order are pinned verbatim above — a later wave's `mpc_loop.jl` can call
  these directly.
- `Phase21Fixtures.mpc_high_pv_feeder`/`build_mpc_high_pv_aggregators` exist with a
  caller-supplied, no-default `pv_scale` — a later wave's task must MEASURE the value
  that genuinely trips the forced-inexact certificate-escalation path at this fixture's
  short `Tsteps`/`H`, documenting that measurement in its own plan/summary (not here).
- Targeted regression only (per this plan's own `<verification>` section): `Pkg.precompile()`
  ran clean, and all three task-level `<verify>` inline scripts re-ran successfully
  (idempotent, side-effect-free) after all three tasks landed. `@testitem`/TestItemRunner
  execution of `test/test_mpc_window.jl`'s 4 permanent items, and the full-suite regression
  across every pre-existing test file, are explicitly DEFERRED to the phase-closing plan
  21-06 — not run here. As an additional confidence step (not a plan requirement), I
  re-implemented and ran all 4 `@testitem` bodies as a standalone plain script under
  `--project=.`; all 4 passed, but this is not a substitute for the actual TestItemRunner
  discovery/execution 21-06 will perform.

---
*Phase: 21-mpc-rolling-horizon-real-time-pricing*
*Plan: 03*
*Completed: 2026-08-09*

## Self-Check: PASSED

- FOUND: `src/models/mpc_window.jl`
- FOUND: `test/fixtures_phase21.jl`
- FOUND: `test/test_mpc_window.jl`
- FOUND: `src/TSODSO.jl` (modified)
- FOUND: `docs/src/api.md` (modified)
- FOUND: `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/21-03-SUMMARY.md`
- FOUND commit: `8c2bf75` (feat(21-03): MpcWindow build-once receding-horizon model)
- FOUND commit: `feb0eb7` (test(21-03): Phase21Fixtures short-T CI substrate + high-PV fixture)
- FOUND commit: `9d3240c` (test(21-03): permanent @testitem coverage for MpcWindow)
- All three task-level `<verify>` inline scripts re-ran successfully (idempotent) after
  all three tasks landed.
- `Pkg.precompile()` ran clean.
- All acceptance-criteria greps for Tasks 1-3 confirmed passing.
- All 4 permanent `@testitem` bodies in `test/test_mpc_window.jl` re-ran (as a standalone
  plain-script re-implementation, since TestItemRunner execution is deferred to plan 21-06)
  and pass.
