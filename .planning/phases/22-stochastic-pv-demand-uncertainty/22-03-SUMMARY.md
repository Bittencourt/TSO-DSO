---
phase: 22-stochastic-pv-demand-uncertainty
plan: 03
subsystem: optimization
tags: [julia, jump, clarabel, socp, stochastic-programming, out-of-sample, parameter-pin]

# Dependency graph
requires:
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "build_stochastic_welfare(feeder, pf, scenario_aggs; probabilities, T, λ₀) —
      the S-scenario extensive-form welfare builder (STOCH-01/STOCH-02) from plan 22-02,
      plus its select_optimizer(::SOCP; attrs...) convergence-precision fix"
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "Scenario.jl stoch_* fields + Phase22Fixtures (test/fixtures_phase22.jl,
      stoch_feeder/stoch_scenario_aggregators) from plan 22-01"
provides:
  - "StochasticOosHarness struct + build_stochastic_oos_harness + solve_stochastic_oos_step! —
    the Parameter-pinned single-scenario out-of-sample re-solve harness (STOCH-03/D-09)"
  - "battery_pins/ppv_handles/tout_handles/agg_pdc_handles NamedTuple field convention for
    a build-once harness whose first-stage schedule is pinned via anonymous per-step
    Parameter equality constraints (never soc directly)"
affects: ["22-04", "22-05"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Anonymous per-step PIN Parameter + equality constraint (p_ch[t] == pin_p_ch[t]) —
      generalizes MpcWindow's single-target soc[H] == terminal_param idiom to a FULL
      per-step trajectory, pinning a caller-supplied in-sample optimum onto a build-once
      harness without ever pinning the recursive state variable (soc) directly."
    - "Single-scenario, single-contribute! harness (no JuMP.unregister needed) as the
      SEPARATE model housing STOCH-03's out-of-sample re-solve, deliberately distinct from
      the S-scenario extensive-form model that carries the in-sample nonanticipativity ties."

key-files:
  created: [test/test_stochastic_oos_harness.jl]
  modified: [src/models/stochastic_welfare.jl]

key-decisions:
  - "battery_pins/ppv_handles/tout_handles do NOT expose a soc0 handle — Pattern 5's
    documented 'pin only p_ch/p_dch, never soc' choice means the battery's initial
    condition stays fixed at its build-time literal across every held-out re-solve; this
    is the physically correct reading (the actual battery SOC at the start of the day is
    the SAME regardless of which held-out PV/demand draw is being scored against it)."
  - "solve_stochastic_oos_step! always solves with dual = false — STOCH-03's scope is the
    realized welfare only, never a per-scenario DADP (that stays STOCH-02's job)."

patterns-established:
  - "A build-once, single-contribute! harness is the correct home for an out-of-sample
    re-solve loop that must re-target Parameters against a FIXED caller-supplied schedule,
    as distinct from an in-sample S-scenario extensive form that ties schedules via
    equality constraints across independently-built network copies."

requirements-completed: [STOCH-03]

# Metrics
duration: ~19min
completed: 2026-08-10
---

# Phase 22 Plan 3: StochasticOosHarness out-of-sample re-solve harness Summary

**`StochasticOosHarness`/`build_stochastic_oos_harness`/`solve_stochastic_oos_step!` — a
build-once, single-scenario, `solve_welfare`-shaped model whose first-stage `p_ch`/`p_dch`
are Parameter-pinned to a caller-supplied in-sample optimum via anonymous per-step equality
constraints, and whose PV/demand/ambient Parameters re-slide per held-out scenario without
ever rebuilding.**

## Performance

- **Duration:** ~19 min
- **Started:** 2026-08-10T00:12:56-03:00
- **Completed:** 2026-08-10T00:31:34-03:00
- **Tasks:** 2/2 completed
- **Files modified:** 2 (1 modified, 1 created)

## Accomplishments
- `build_stochastic_oos_harness(feeder, pf, aggregators; T, λ₀)` builds the D-09
  out-of-sample harness exactly once: a single `contribute!` call (no `JuMP.unregister`
  needed, unlike the S-scenario extensive form), a named frontier `p_import`/`q_import`,
  and — for every battery-like device — two anonymous per-step PIN `Parameter`s
  (`pin_p_ch`/`pin_p_dch`) tied via `p_ch[t] == pin_p_ch[t]`/`p_dch[t] == pin_p_dch[t]`,
  generalizing `build_mpc_window`'s single-target `soc[H] == terminal_param` idiom to the
  FULL per-step trajectory. `soc` itself is never pinned directly.
- `solve_stochastic_oos_step!` is a one-line `solve_with_retry!(h.model; dual = false)`
  delegation — never adds a variable/constraint.
- Verified (Task 1's own inline harness build + 3 heterogeneous re-solve cycles, corrected
  magnitudes — see Deviations): `num_variables`/`num_constraints` unchanged across
  re-solves at different pinned/PV/demand/ambient values (build-once invariant, T-22-06),
  and the solved `value.(p_ch)` equals the pinned vector exactly (pin genuinely binding,
  T-22-05).
- `test/test_stochastic_oos_harness.jl` adds 3 `@testitem`s tagged
  `[:stochastic_oos_harness]`, `setup = [Phase22Fixtures]`: build-once invariance across
  charge-only/discharge-only/mixed-pin cycles, pin-correctness (two different pins on the
  same never-rebuilt model genuinely move the solved value), and boundary guards (empty
  aggregators, `T < 1`, `length(λ₀) != T`, out-of-range aggregator bus).

## Task Commits

Each task was committed atomically:

1. **Task 1: StochasticOosHarness — Parameter-pinned single-scenario build-once model (D-09)** -
   `913913b` (feat)
2. **Task 2: test_stochastic_oos_harness.jl — build-once invariant + pin correctness** -
   `6f7b51e` (test)

**Plan metadata:** (pending — final metadata commit follows this SUMMARY)

## Files Created/Modified
- `src/models/stochastic_welfare.jl` - Appended `StochasticOosHarness` struct,
  `build_stochastic_oos_harness`, and `solve_stochastic_oos_step!` after
  `build_stochastic_welfare` and its export line.
- `test/test_stochastic_oos_harness.jl` - New `@testitem`s covering the build-once
  invariant, pin correctness, and boundary guards.

## Decisions Made
- `soc0` is deliberately NOT exposed as a harness handle (Pattern 5's "pin only
  p_ch/p_dch, never soc" choice) — the battery's initial condition stays at its build-time
  literal across every held-out re-solve, which is the physically correct reading for an
  out-of-sample scoring harness (same starting state, different exogenous draw).
- `solve_stochastic_oos_step!` always uses `dual = false` per STOCH-03's own scope
  boundary against STOCH-02's in-sample pricing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PLAN.md's own Task 1 `<verify>` script pins p_ch at a magnitude that drives the fixture's SOC band infeasible within a single solve**
- **Found during:** Task 1's own `<verify>` script, running it exactly as written.
- **Issue:** PLAN.md's Task 1 `<verify>` script loops `trial in 1:3` pinning
  `p_ch = fill(0.0005 * trial, T)` (i.e. `0.0005, 0.001, 0.0015`) on the fixture's
  `PVBattery(bus=2, η=0.95, Δt=1.0, Pmax=0.002, Emin=0.0, Emax=0.008, soc0=0.004, ...)`
  at `T=6` (5 recursion steps), never resetting `soc0` (which the harness deliberately
  never exposes a handle for — see Decisions). At `trial=2` (`p_ch=0.001` constant across
  all `t`), the SOC recursion alone drives `soc[6] = soc0 + 5·η·p_ch = 0.004 + 5·0.95·0.001
  = 0.00875 > Emax = 0.008` — a genuine `PRIMAL_INFEASIBLE` within that ONE solve, not a
  cross-solve accumulation artifact (each `solve_stochastic_oos_step!` call recomputes
  `soc[1..T]` fresh from the current Parameter values every time).
- **Root cause (verified, not assumed):** isolated `trial=1` (solves `OPTIMAL`) from
  `trial=2` (throws `PRIMAL_INFEASIBLE` from `solve_with_retry!`'s own exhaustion path) by
  running each in isolation; confirmed the arithmetic above reproduces the exact bound
  violation. This is a genuine SOC-band feasibility bug in the plan's own verify-script
  literal magnitudes, not an implementation defect — the harness never claims a pinned
  `p_ch` is feasible regardless of magnitude; the SOC band constraint (eq. 3.9) is supposed
  to reject an infeasible pin exactly this way.
- **Fix:** re-ran the SAME harness build/pin/solve logic with SMALLER, verified-feasible
  pin magnitudes respecting `soc0 + 5·η·p_ch(max) ≤ Emax` (`test_mpc_window.jl`'s own cycle
  design already documents this discipline for the analogous `MpcWindow` re-solve loop).
  `test/test_stochastic_oos_harness.jl`'s own Item 1 uses `p_ch ∈ {0.0003, 0.0000,
  0.0004}` across three cycles (charge-only, discharge-only, mixed charge+discharge) —
  all verified feasible and exercising genuinely heterogeneous re-solves.
- **Files modified:** none beyond the plan's own declared scope — this is a
  verify-invocation correction (the `<verify>` script itself is never committed to the
  repo), documented here and reflected in `test/test_stochastic_oos_harness.jl`'s own file
  header.
- **Verification:** re-ran the corrected magnitudes 3× (once as an ad hoc harness build,
  once against the actual `Phase22Fixtures` fixture data, once inside
  `test/test_stochastic_oos_harness.jl`'s own Item 1 logic) — all pass; `num_variables`/
  `num_constraints` unchanged across all three cycles.
- **Committed in:** `913913b` (Task 1 implementation, unaffected — the fix is entirely in
  how the harness is EXERCISED, not in `build_stochastic_oos_harness`/
  `solve_stochastic_oos_step!` themselves), `6f7b51e` (Task 2, where the corrected
  magnitudes are the actual committed test values).

**2. [Rule 1 - Bug] Item 2's pin-correctness test needs Ppv_param raised before pinning a constant nonzero p_ch — the device's own default PV profile is zero at night**
- **Found during:** Task 2, writing `test/test_stochastic_oos_harness.jl`'s pin-correctness
  item.
- **Issue:** `PVBattery.contribute!`'s own `Ppv_param` Parameter defaults to the device's
  literal seeded daily PV profile (`Phase22Fixtures.stoch_scenario_aggregators`'s
  `generate_profiles`-derived `Ppv`), which is genuinely ZERO at night hours. Pinning
  `p_ch` to a CONSTANT nonzero value across every `t` (the whole point of this test item)
  is then infeasible at any night hour, since `p_ch[t] ≤ pv_used[t] ≤ Ppv_param[t]`
  (eq. 3.7) forces `p_ch[t] ≤ 0` there — independent of whether the pin mechanism itself
  is correct.
- **Root cause (verified, not assumed):** reproduced the SAME pin without overriding
  `Ppv_param` first; it throws `PRIMAL_INFEASIBLE`. With `Ppv_param` overridden to a flat
  `0.01` (comfortably above every pin value used) BEFORE pinning, the identical pin
  mechanics solve `OPTIMAL` and the pin-correctness assertions pass.
- **Fix:** Item 2 (`test/test_stochastic_oos_harness.jl`) overrides
  `ppv.Ppv_param` to a flat, sufficiently large value immediately after building the
  harness and before the first pin/solve cycle.
- **Files modified:** `test/test_stochastic_oos_harness.jl` (authored fresh in this task;
  the fix is reflected directly in the committed test, not a change to already-committed
  code).
- **Verification:** ran the pin-correctness logic both without (fails, `PRIMAL_INFEASIBLE`)
  and with (passes) the `Ppv_param` override, confirming the override is exactly what
  resolves the infeasibility and is not masking a different bug.
- **Committed in:** `6f7b51e` (Task 2 commit).

---

**Total deviations:** 2 auto-fixed (both Rule 1 — verify/test-invocation feasibility fixes;
neither touched `build_stochastic_oos_harness`/`solve_stochastic_oos_step!`'s own
implementation, which behaves exactly as specified — both fixes correct pin/PV magnitudes
used to EXERCISE the harness against this fixture's own structural bounds).
**Impact on plan:** No implementation scope creep. Both fixes were necessary to make the
plan's own acceptance criteria (build-once invariant, pin correctness) actually
demonstrable against feasible inputs; the harness's boundary guards and pin mechanics are
verified to work exactly as PLAN.md specifies once fed feasible magnitudes.

## Issues Encountered

Both deviations above were discovered by literally running PLAN.md's own `<verify>` script
text first (per the mandated execution discipline), then isolating the exact failing
`trial`/parameter combination via targeted re-runs rather than guessing — mirroring plan
22-02's own "measured, not guessed" discipline for its D-06 test design.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `StochasticOosHarness`/`build_stochastic_oos_harness`/`solve_stochastic_oos_step!` are a
  stable, exported, documented contract ready for plan 22-04 (the orchestrator that drives
  this harness across the held-out scenario budget `stoch_H_oos` to compute the
  realized-vs-in-sample welfare gap).
- The caller-side contract for plan 22-04: build the harness ONCE per in-sample scenario's
  optimum (or reuse across held-out draws of the SAME in-sample schedule), pin
  `battery_pins` from that in-sample `p_ch`/`p_dch` solution, then loop held-out scenarios
  re-sliding `ppv_handles`/`tout_handles`/`agg_pdc_handles` and calling
  `solve_stochastic_oos_step!` — reading `objective_value(h.model)` as the realized welfare.
- No blockers carried forward specific to this plan.

---
*Phase: 22-stochastic-pv-demand-uncertainty*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: src/models/stochastic_welfare.jl
- FOUND: test/test_stochastic_oos_harness.jl
- FOUND commit: 913913b (Task 1)
- FOUND commit: 6f7b51e (Task 2)
