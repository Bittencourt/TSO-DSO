---
phase: 21-mpc-rolling-horizon-real-time-pricing
plan: 05
subsystem: experiments
tags: [mpc, rolling-horizon, real-time-pricing, orchestrator, jump, parameter, regret]

# Dependency graph
requires:
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plan 21-01)
    provides: "PVBattery/Thermostatic/FourQuadBESS soc0/Tin0/Ppv_param/Tout_param Parameter
      handles, Aggregator.Pdc_param — the widened device return-tuple shapes this plan
      reads from ctx.meta[:agg_device_vars]"
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plan 21-02)
    provides: "MpcTrace + record!(trace, k, dadp, dadp_da, cert_status) — the price-
      consistency ledger this plan populates every published hour"
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plan 21-03)
    provides: "MpcWindow/build_mpc_window/solve_mpc_window! — the build-once receding-
      horizon window model this plan re-solves every s.mpc_step real hours"
  - phase: 21-mpc-rolling-horizon-real-time-pricing (plan 21-04)
    provides: "Scenario's mpc_H/mpc_step/mpc_terminal_soc/mpc_forecast_error fields,
      propagate_soc/propagate_tin/draw_forecast_error — the state-propagation primitives
      this plan's per-step loop calls"
  - phase: 20-overvoltage-capable-relaxation
    provides: "RestrictedBranchFlow/assert_restriction_exact!/ac_dual_fallback_price — the
      certificate/fallback ladder this plan's per-resolve escalation dispatches, never
      reinvented"
provides:
  - "run_mpc(scenario::Scenario) -> (; trace, day_ahead_welfare, realized_welfare, regret,
    day_ahead_dadp, steps) — the phase's single researcher-facing integration point,
    driving the FULL receding-horizon closed loop end-to-end"
  - "_mpc_certify_and_price(feeder, mpc_aggs, o, λ₀, t) — the internal, reusable per-resolve
    certificate-check + Phase-20 escalation helper run_mpc's loop and test_mpc_loop.jl both
    call directly"
  - "_mpc_device_hour_utility(d, varlist, τ) — the internal, reusable per-device per-hour
    utility-formula reader used identically for realized_welfare and the day-ahead regret
    comparison term"
  - "test/test_mpc_loop.jl: 3 permanent @testitems (happy-path end-to-end, forced-inexact
    never-throw escalation, mpc_step's genuine stride effect)"
  - "test/fixtures_phase21.jl: MPC_HIGH_PV_SCALE_MEASURED = 3.0, measured via the exact
    build_mpc_window/solve_mpc_window! shape run_mpc itself uses"
  - "fix(21-01): anonymized Parameter containers in PVBattery/Thermostatic/FourQuadBESS/
    Aggregator — a pre-existing, project-wide multi-aggregator collision bug this plan's
    own verify script discovered"
affects: [21-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deferrable-excluded aggregator list (mpc_aggs) for the receding-horizon window:
      a device whose own construction bakes an absolute-hour window into a horizon
      shorter than that window (Deferrable's energy-budget band, RESEARCH.md Pitfall 8)
      is filtered out of the WINDOW model's aggregator list, while the one-time day-ahead
      benchmark still uses the FULL, unfiltered population — the day-ahead-vs-realized
      regret comparison is scoped to the SAME (filtered) device set on both sides."
    - "Internal per-resolve helper extraction (_mpc_certify_and_price): factoring the
      certificate-check + escalation-ladder logic out of the main loop into a standalone
      function, callable both by the orchestrator's own loop and by a test driving it
      directly against a non-Scenario feeder/aggregator pair — avoids duplicating the
      ladder-dispatch logic in test code."
    - "Anonymous indexed/scalar JuMP Parameter construction (@variable(m, [t=1:T], set =
      Parameter(...)) / @variable(m, set = Parameter(...))): the fix for the multi-instance
      name-collision bug this plan discovered — mirrors FourQuadBESS's own anonymous
      apparent-power cone, now the project's standard idiom for ANY per-instance Parameter
      inside a model that may host more than one instance of the same device/aggregator
      type."

key-files:
  created:
    - src/experiments/mpc_loop.jl
    - test/test_mpc_loop.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md
    - test/fixtures_phase21.jl
    - src/devices/PVBattery.jl
    - src/devices/Thermostatic.jl
    - src/devices/FourQuadBESS.jl
    - src/devices/Aggregator.jl

key-decisions:
  - "run_mpc's own Task 1 <verify> script (and Task 3's tests) use T=9, not the plan's
    literal T=8 — materialize.jl's :default population's Deferrable device cannot even be
    CONSTRUCTED at T=8 for the :ieee13 feeder (its energy-budget window [t_start,t_end] =
    [8,8] has window_length=1, below its own E<=Pmax*window_length feasibility guard); T=9
    is the smallest value where construction succeeds. This is a pre-existing,
    MPC-unrelated constraint of materialize.jl's :default population, not a bug this plan
    introduced."
  - "mpc_aggs (Deferrable-excluded) is used for the WINDOW model and every per-step
    realized_welfare/regret accumulation; the ONE-TIME day-ahead benchmark still uses the
    FULL aggs (Deferrable genuinely contributes to day_ahead_welfare, the full-day number).
    regret's day-ahead comparison term is accumulated over the SAME mpc_aggs device set
    (never the full aggs) so both sides of the regret comparison are apples-to-apples."
  - "MPC_HIGH_PV_SCALE_MEASURED = 3.0 (Phase21Fixtures), measured via the EXACT
    build_mpc_window/solve_mpc_window! shape run_mpc uses (a Tsteps=T=8 PV draw sliced to
    H=3, never a bare Tsteps=H draw — which measures a materially different problem, as
    discovered empirically: pv_scale=1.2 trips ratio>1 under a bare Tsteps=H draw but stays
    comfortably exact, maxratio≈0.006, under the Tsteps=T-sliced-to-H shape). A sharp
    knife-edge sits between pv_scale=2.0 (maxratio≈0.0036) and pv_scale=2.5 (maxratio≈8510)
    — 3.0 sits comfortably past the edge with ~9157x margin."
  - "_mpc_certify_and_price factored out as an internal, reusable helper (not inlined in
    run_mpc's loop body) specifically so test_mpc_loop.jl's forced-inexact test could drive
    the escalation ladder directly against Phase21Fixtures' custom feeder without
    duplicating the dispatch logic — matching the plan's own explicit suggestion."

patterns-established:
  - "Pattern: MPC-04 regret accounting — realized_welfare and the day-ahead comparison term
    are BOTH accumulated via the SAME per-device utility-formula reader
    (_mpc_device_hour_utility), differing only in which solved ctx they read values from —
    guarantees an information-set-fair, apples-to-apples regret by construction rather than
    by convention."

requirements-completed: [MPC-03, MPC-04]

# Metrics
duration: 38min
completed: 2026-08-09
---

# Phase 21 Plan 05: run_mpc — the receding-horizon closed-loop orchestrator Summary

**`run_mpc(scenario::Scenario)` drives the full receding-horizon closed loop end-to-end — build-once window re-solved every `s.mpc_step` real hours, Phase-20's own non-throwing certificate/fallback ladder on every resolve, `MpcTrace`-recorded per published hour, and a measured regret against the perfect-foresight day-ahead optimum — plus a project-wide pre-existing multi-aggregator Parameter-collision bug (plan 21-01) discovered and fixed along the way.**

## Performance

- **Duration:** ~38 min
- **Started:** 2026-08-09T10:34:49-03:00 (worktree base commit `fce79b5`)
- **Completed:** 2026-08-09T11:13:06-03:00 (last task commit)
- **Tasks:** 3/3 completed (plus 1 pre-existing-bug-fix commit, see Deviations)
- **Files modified:** 9 (2 created, 7 modified — 4 of the 7 are the plan-21-01 device-file fix, outside this plan's own declared `files_modified`)

## Accomplishments

- `src/experiments/mpc_loop.jl`: `run_mpc(s::Scenario)` — materializes the same heavy
  objects `run_scenario` does, solves the perfect-foresight day-ahead benchmark via
  `solve_welfare` EXACTLY ONCE, builds `MpcWindow` ONCE, and strides the outer resolve loop
  genuinely by `s.mpc_step` (`for t in 1:s.mpc_step:(s.T - s.mpc_H + 1)`, never a hardcoded
  step — the checker-mandated fix). `n_apply`/`k` bookkeeping guarantees the published-hour
  count is always `s.T - s.mpc_H + 1` regardless of `s.mpc_step`.
- The per-resolve certificate check is a non-throwing inline reimplementation of
  `assert_socp_exact!`'s own cone-residual formula (its SAME `rtol=1e-4`/`atol=1e-6`
  defaults — the one deliberate tolerance copy, since it is the identical physical
  quantity). On failure it escalates through Phase-20's OWN ladder (`RestrictedBranchFlow`
  + `assert_restriction_exact!(report=true)` + `ac_dual_fallback_price`), factored into a
  reusable internal helper `_mpc_certify_and_price` — never a new tolerance, never a
  `try`/`catch`, never throws mid-loop.
- `regret` is computed via an identical per-device utility-formula reader
  (`_mpc_device_hour_utility`) applied to BOTH the closed-loop realized trajectory and the
  day-ahead optimum's trajectory, restricted to the SAME published `k`-hour decision
  horizon — an information-set-fair comparison by construction.
- `test/test_mpc_loop.jl`: 3 permanent `@testitem`s (happy-path end-to-end, forced-inexact
  never-throw escalation, `mpc_step`'s genuine stride effect), each independently verified
  as a standalone plain script before being committed.
- `test/fixtures_phase21.jl`: `MPC_HIGH_PV_SCALE_MEASURED = 3.0`, measured against the
  EXACT window-building shape `run_mpc` itself uses.
- Discovered and fixed a project-wide, pre-existing bug (plan 21-01): every multi-instance
  Parameter widening used JuMP's NAMED container macro form, which collides ("An object of
  name ... is already attached to this model") the moment a SECOND instance of the same
  device/aggregator type contributes to the SAME model — breaking every existing
  multi-aggregator `solve_welfare`/`run_scenario`/`solve_admm` call project-wide, not just
  MPC. Fixed via JuMP's anonymous Parameter construction.

## Task Commits

Each task was committed atomically:

1. **fix(21-01): anonymize Parameter containers** - `3887eb7` (fix, pre-existing bug, see Deviations)
2. **Task 1: run_mpc — materialize, day-ahead benchmark, mpc_step-strided loop mechanics** - `f2ae950` (feat)
3. **Task 2: non-throwing per-resolve certificate check + Phase-20 escalation ladder** - `c580b7f` (feat)
4. **Task 3: test_mpc_loop.jl — happy path, forced-inexact escalation, mpc_step stride** - `bcedaa8` (test)

_No TDD RED/GREEN/REFACTOR gate sequence — Tasks 1-2 are `tdd="true"` but, like this
phase's established `MpcWindow`/`MpcTrace`/`Scenario`-fields precedents, they build a
from-scratch orchestrator verified via inline `<verify>` scripts (which fail before the
function exists, serving the RED-gate role) rather than a separate persistent RED test
commit; each task's single `feat` commit lands the passing implementation directly. Task 3
supplies the permanent, checked-in `@testitem` coverage in its own `test` commit._

## Files Created/Modified

- `src/experiments/mpc_loop.jl` — `run_mpc`, `_mpc_certify_and_price`,
  `_mpc_device_hour_utility`; exports `run_mpc`.
- `src/TSODSO.jl` — one new `include("experiments/mpc_loop.jl")` as the last line of the
  `experiments/` block.
- `docs/src/api.md` — extended the `## MPC / Rolling-Horizon` `Pages` list with
  `"experiments/mpc_loop.jl"`.
- `test/fixtures_phase21.jl` — `MPC_HIGH_PV_SCALE_MEASURED = 3.0` with a measurement-
  provenance comment; exported.
- `test/test_mpc_loop.jl` — 3 `@testitem`s tagged `[:mpc_loop]`, `setup = [Phase21Fixtures]`.
- `src/devices/PVBattery.jl`, `src/devices/Thermostatic.jl`, `src/devices/FourQuadBESS.jl`,
  `src/devices/Aggregator.jl` — anonymized their plan-21-01 Parameter containers (see
  Deviations).

## Decisions Made

- `mpc_aggs` (Deferrable-excluded) drives the window model and every per-step accumulation;
  the one-time day-ahead benchmark and `day_ahead_welfare` still use the FULL population.
- Task 1/Task 3's own verify scripts use `T=9` (not the plan's literal `T=8`) — the smallest
  `T` at which `materialize.jl`'s `:default` population's `Deferrable` device is even
  constructible for the `:ieee13` feeder.
- `MPC_HIGH_PV_SCALE_MEASURED = 3.0`, measured against the exact
  `build_mpc_window`/`solve_mpc_window!` shape `run_mpc` itself uses (a `Tsteps=T` PV draw
  sliced to `H`), not a bare `Tsteps=H` draw.
- `_mpc_certify_and_price` factored into a standalone, reusable internal function so
  `test_mpc_loop.jl`'s forced-inexact test could drive it directly without duplicating the
  ladder-dispatch logic.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, pre-existing, plan 21-01] Fixed a project-wide multi-aggregator Parameter name collision**
- **Found during:** Task 1, running this task's own `<verify>` script against the default
  10-aggregator `:ieee13` population.
- **Issue:** `PVBattery.jl`/`Thermostatic.jl`/`FourQuadBESS.jl`/`Aggregator.jl` (plan 21-01)
  each declared their new `Parameter` handles via the NAMED `@variable(m, name[...] in
  Parameter.(...))`/`@variable(m, name in Parameter(...))` macro forms, which register a
  symbol in the JuMP model's object dictionary. A SECOND instance of the same
  device/aggregator type contributing to the SAME model throws `"An object of name ... is
  already attached to this model"` — confirmed to break EVERY existing multi-aggregator
  `solve_welfare` call (e.g. the plain default `:ieee13` population, 10 aggregators, with
  no MPC involvement at all), not just this plan's own code. `Pkg.test()` had not been
  re-run since plan 21-01 landed (each of 21-01..21-04's summaries explicitly deferred the
  full-suite regression to plan 21-06), so this was undiscovered until this plan's own
  broader-than-single-device verify script exercised it.
- **Fix:** Converted all four Parameter declarations to JuMP's anonymous construction
  (`@variable(m, [t=1:T], set = Parameter(...))` / `@variable(m, set = Parameter(...))`),
  mirroring `FourQuadBESS`'s own pre-existing anonymous apparent-power cone. Verified
  byte-identical values/behavior via a standalone smoke test (parameter defaults, two
  same-type-device-in-one-model no-collision checks for `PVBattery`/`Thermostatic`/
  `FourQuadBESS`, and the full 10-aggregator default population solving end-to-end).
- **Files modified:** `src/devices/PVBattery.jl`, `src/devices/Thermostatic.jl`,
  `src/devices/FourQuadBESS.jl`, `src/devices/Aggregator.jl`
- **Verification:** Standalone smoke test (multi-instance, byte-identical-default) passed;
  `solve_welfare` against the full 10-aggregator default `:ieee13` population at `T=24`
  now solves cleanly (previously threw on the second aggregator).
- **Committed in:** `3887eb7` (its own dedicated `fix(21-01):` commit, landed BEFORE Task 1,
  for auditability — this fix is outside plan 21-05's own declared `files_modified`).

**2. [Rule 3 - Blocking issue] Deferrable-excluded aggregator list for the window model**
- **Found during:** Task 1, running this task's own `<verify>` script.
- **Issue:** `materialize.jl`'s ONLY `:default` population selector includes a `Deferrable`
  device per house whose energy-budget window `[t_start, t_end]` is baked, at construction
  time, against the FULL day-ahead horizon `s.T` (e.g. hours 8-16 of a longer day) —
  virtually always longer than any sane MPC window `s.mpc_H`. `Deferrable.contribute!`'s
  own temporal-infeasibility guard (`d.t_end > T`) throws whenever `build_mpc_window` tries
  to contribute it at `T = s.mpc_H`, and `Deferrable` has no inter-temporal recursion to
  propagate across MPC steps in the first place (generalizing RESEARCH.md Pitfall 8's own
  documented reasoning, there scoped only to "keep the CI fixture Deferrable-free", one
  level up to the orchestrator).
- **Fix:** `run_mpc` builds a separate, Deferrable-excluded aggregator list (`mpc_aggs`) for
  the window model and every per-step accumulation, while the one-time day-ahead benchmark
  still uses the full, unfiltered population (`day_ahead_welfare` genuinely includes
  Deferrable's contribution). `regret`'s day-ahead comparison term is accumulated over the
  SAME `mpc_aggs` device set (never the full population) so both sides of the comparison
  are apples-to-apples.
- **Files modified:** `src/experiments/mpc_loop.jl` (within this plan's own declared scope).
- **Verification:** `run_mpc` against the default `:ieee13` population at `T=9`/`mpc_H=3`
  completes end-to-end, reproducibly, with a finite regret.
- **Committed in:** `f2ae950` (Task 1's own commit).

**3. [Rule 1 - Bug] Task 1/Task 3's own literal `T=8` verify value fails at population materialization**
- **Found during:** Task 1, running this task's own `<verify>` script exactly as written.
- **Issue:** `materialize.jl`'s `:default` population builds `Deferrable(bus, min(8,T),
  min(16,T), E=1.0, Pmax=0.5, b=0.5)` per house. At `T=8`, `t_start=t_end=8`
  (`window_length=1`), and `Deferrable`'s OWN constructor guard requires `E <=
  Pmax*window_length = 0.5` — `1.0 > 0.5` throws `ArgumentError` at MATERIALIZATION time,
  before `run_mpc`/`build_mpc_window` are even reached. This is a pre-existing constraint of
  `materialize.jl`'s `:default` population (unrelated to MPC), unnoticed until this plan's
  own verify script used the plan's literal `T=8`.
- **Fix:** Used `T=9` (the smallest value at which `:default` population construction
  succeeds for `:ieee13`) in place of the plan's literal `T=8`, preserving the INTENT of
  every acceptance-criteria formula (`steps == T - mpc_H + 1`, etc.) by substituting the
  adjusted `T` consistently.
- **Files modified:** None (verify-script-only substitution; `test/test_mpc_loop.jl` uses
  `T=9` throughout for the same reason).
- **Verification:** All Task 1/Task 3 verify scripts and acceptance criteria pass at `T=9`.
- **Committed in:** `f2ae950`/`bcedaa8` (the adjusted `T` value appears directly in the
  committed test/verify code, not a follow-up fix).

---

**Total deviations:** 3 (1 pre-existing bug from plan 21-01, fixed in its own dedicated
commit; 1 blocking architectural gap resolved via a scoped, documented device-exclusion
inside this plan's own file; 1 verify-script numeric adjustment). **Impact on plan:** None
of `run_mpc`'s own must_haves are weakened — `mpc_H`/`mpc_step` semantics, the never-throw
certificate ladder, `MpcTrace` population, and the information-set-fair regret scoping all
hold exactly as specified. The Deferrable exclusion and the `T=9` substitution are both
narrowly scoped, thoroughly documented, and verified not to affect any other plan's files or
tests.

## Known Stubs

None — every returned field is genuinely computed from a solved model; no hardcoded
placeholder/empty value flows to any consumer.

## Threat Flags

None — this plan's only new surface (the `mpc_aggs` Deferrable-exclusion and the
`_mpc_certify_and_price`/`_mpc_device_hour_utility` internal helpers) is pure in-process
orchestration over already-certificated builders, matching the plan's own `<threat_model>`
dispositions (T-21-13, T-21-14, T-21-15, T-21-19 — all `mitigate`, all addressed as
specified: the inline cone check is a literal copy of `assert_socp_exact!`'s formula/
defaults, the forced-inexact `@testitem` proves the full escalation path never throws on a
measured real trigger, the `regret` scoping is documented in-code, and `1:s.mpc_step:` is
literally present in the loop header).

## Issues Encountered

None beyond the three auto-fixed deviations documented above, all caught during this plan's
own pre-commit verification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `run_mpc(scenario::Scenario)` exists, is exported, reproducible under a repeated
  same-seed call, and provably NEVER throws mid-loop even when a step is genuinely
  SOC-inexact (measured on `Phase21Fixtures`' high-PV fixture at `MPC_HIGH_PV_SCALE_MEASURED
  = 3.0`, cone ratio ≈ 9157× over threshold, resolved by `RestrictedBranchFlow` alone in the
  observed run — `cert_status` stayed `:certified_convex_dual`, never fell through to
  `:local_ac_dual` on THIS particular fixture/seed, though the ladder's second tier is fully
  wired and exercised by the SAME test's assertion that `cert_status ∈
  (:certified_convex_dual, :local_ac_dual)`).
- `run_mpc`'s exact return-tuple shape: `(; trace::MpcTrace, day_ahead_welfare::Float64,
  realized_welfare::Float64, regret::Float64, day_ahead_dadp::Vector{Float64},
  steps::Int)`.
- Measured `mpc_step=1` vs `mpc_step=2` difference (T=9, mpc_H=3, mpc_forecast_error=0.05,
  seed=1, `:ieee13` default population): `realized_welfare` -468.9144874129807 (step=1) vs
  -468.9105456768124 (step=2); `regret` 0.009131876269464101 (step=1) vs
  0.013073612437779047 (step=2) — both runs published `steps=7` (`= T - mpc_H + 1`,
  invariant to `mpc_step`, per Pitfall 5), confirming `mpc_step` is a genuine stride on the
  resolve cadence, not a silently-inert kwarg.
- Observed forced-inexact `cert_status_trace` entry (`Phase21Fixtures.mpc_high_pv_feeder()`
  + `build_mpc_high_pv_aggregators(feeder; pv_scale=3.0)`, flat `λ₀=4.0`, `H=3`,
  `terminal_soc=false`): `cone_maxratio ≈ 9156.55`, `cert_status = :certified_convex_dual`
  (the restriction tier alone certified it; `RestrictedBranchFlow`'s own cone was tight even
  though the plain `ConvexBranchFlow` relaxation's was not).
- `MPC_HIGH_PV_SCALE_MEASURED = 3.0` is exported from `Phase21Fixtures`, ready for the
  literate page (21-06) to cite verbatim, along with the knife-edge measurement
  (`pv_scale=2.0` → `maxratio≈0.0036`; `pv_scale=2.5` → `maxratio≈8510`).
- The plan 21-01 Parameter-collision fix means EVERY pre-existing multi-aggregator test
  across the whole suite (ADMM, sweep, planning layer, etc.) is now unblocked rather than
  latently broken — this is a net POSITIVE surface for plan 21-06's full-suite regression,
  not a new risk it introduces.
- Full-suite regression (`Pkg.test()`) is explicitly deferred to plan 21-06 per this plan's
  own `<verification>` section; only targeted regression (`Pkg.precompile()`, this plan's
  own inline `<verify>` scripts, and the three permanent `@testitem` bodies run as
  standalone plain scripts) was performed here.

---
*Phase: 21-mpc-rolling-horizon-real-time-pricing*
*Plan: 05*
*Completed: 2026-08-09*

## Self-Check: PASSED

- FOUND: `src/experiments/mpc_loop.jl`
- FOUND: `test/test_mpc_loop.jl`
- FOUND: `src/TSODSO.jl` (modified)
- FOUND: `docs/src/api.md` (modified)
- FOUND: `test/fixtures_phase21.jl` (modified)
- FOUND: `src/devices/PVBattery.jl`, `src/devices/Thermostatic.jl`,
  `src/devices/FourQuadBESS.jl`, `src/devices/Aggregator.jl` (modified, deviation fix)
- FOUND: `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/21-05-SUMMARY.md`
- FOUND commit: `3887eb7` (fix(21-01): anonymize Parameter containers)
- FOUND commit: `f2ae950` (feat(21-05): run_mpc loop mechanics, Task 1)
- FOUND commit: `c580b7f` (feat(21-05): certificate check + escalation ladder, Task 2)
- FOUND commit: `bcedaa8` (test(21-05): test_mpc_loop.jl, Task 3)
- All acceptance-criteria greps for Tasks 1-3 confirmed passing.
- `Pkg.precompile()` ran clean.
- All three `@testitem` bodies in `test/test_mpc_loop.jl` re-ran as standalone plain scripts
  and pass (TestItemRunner discovery/execution deferred to plan 21-06 per this plan's own
  `<verification>` section).
- The plan's own closing `<verification>` command re-run: prints `OK, cert statuses =
  [:certified_convex_dual, ...]` (7 entries, T=9/mpc_H=3/mpc_forecast_error=0.05).
