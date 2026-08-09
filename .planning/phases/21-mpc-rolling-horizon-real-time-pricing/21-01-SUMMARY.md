---
phase: 21-mpc-rolling-horizon-real-time-pricing
plan: 01
subsystem: devices
tags: [jump, parameter, mpc, rolling-horizon, pvbattery, thermostatic, fourquadbess, aggregator]

# Dependency graph
requires:
  - phase: 20-overvoltage-capable-relaxation
    provides: RestrictedBranchFlow / assert_restriction_exact! pattern this plan's Parameter
      widening follows structurally (byte-identical-default discipline)
provides:
  - "PVBattery.contribute! returns vars.soc0 and vars.Ppv_param as genuine JuMP Parameter
    handles (soc0 the IC state, Ppv_param the per-step PV-availability profile)"
  - "Thermostatic.contribute! returns vars.Tin0 and vars.Tout_param as genuine JuMP
    Parameter handles (Tin0 the IC state, Tout_param the per-step ambient profile,
    t = 1:(T-1) only)"
  - "FourQuadBESS.contribute! returns vars.soc0 as a genuine JuMP Parameter handle"
  - "Aggregator.contribute! returns an additive Pdc_param field; the :Rp/:Rq residual
    writes now read Pdc_param instead of the literal agg.Pdc[t]"
  - "Every new Parameter defaults to the exact prior literal value (byte-identical
    default) and is re-settable via set_parameter_value/set_parameter_value. without
    adding any new variable or constraint"
affects: [21-02, 21-03, 21-04, 21-05, 21-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Device-level Parameter widening: `@variable(m, x in Parameter(literal))` +
      `@constraint(m, ... == x)` replaces a baked-in literal IC constraint — the same
      idiom PlanningOracle already applies to its coupling `z[t]` (subproblem.jl:194-195)."
    - "A Parameter cannot be passed as an `upper_bound=`/`lower_bound=` kwarg — only as
      the RHS of a constraint. Where a literal bounded a variable (PVBattery's
      `pv_used` PV limit), the bound moves to a separate `@constraint` against the new
      Parameter, and the variable keeps only its OWN structural bound(s)."
    - "Byte-identical-default verification is done via `parameter_value(...)` (reads
      the CURRENT value, no solve needed) plus a `num_variables`/`num_constraints`
      invariant check across `set_parameter_value` (the project's established
      test_planning_oracle.jl idiom, `count_variable_in_set_constraints = true`)."
    - "Widening an affine residual write's literal term into a Parameter changes the
      JuMP AffExpr's STRUCTURE (the term moves from `.constant` into `.terms` keyed by
      the new Parameter VariableRef) even though its EVALUATED value is unchanged —
      tests asserting the raw `.constant`/`.terms` shape must be updated to check the
      term-keyed structure instead of the byte-identical VALUE."

key-files:
  created: []
  modified:
    - src/devices/PVBattery.jl
    - src/devices/Thermostatic.jl
    - src/devices/FourQuadBESS.jl
    - src/devices/Aggregator.jl
    - test/test_pvbattery.jl
    - test/test_thermostatic.jl
    - test/test_fourquadbess.jl
    - test/test_aggregator.jl

key-decisions:
  - "PVBattery's pv_used PV-limit bound moved from a literal `upper_bound=` kwarg to a
    separate `@constraint` against the new `Ppv_param` Parameter (Pitfall 4: Parameters
    cannot be passed as bound kwargs)."
  - "Thermostatic's Tout_param covers ONLY t = 1:(T-1) since the RC/ETP recursion never
    reads Tout[T]; the T == 1 branch (no recursion constraint) is left structurally
    unchanged."
  - "Aggregator.Pdc widened beyond RESEARCH.md's literal Ppv/Tout-only sketch to
    genuinely satisfy D-08's 'PV and demand ground truth' perturbation requirement."
  - "Pre-existing tests asserting the raw AffExpr `.constant`/`.terms` shape of the
    Aggregator's :Rq residual write were updated (not left broken) to check the new
    term-keyed structure against `res.Pdc_param[t]`, since the byte-identical-default
    invariant is about the EVALUATED value, not the literal AffExpr shape."
  - "PVBattery's pre-existing exact-variable-count test (`length(vars) == 4T`) was
    updated to `5T + 1` since JuMP Parameters are genuine VariableRefs, legitimately
    counted by `all_variables` even though solved behavior stays byte-identical."

patterns-established:
  - "Pattern: MPC-01 seam widening — every stateful device's IC and every per-step
    input a future receding-horizon window must slide gets a genuine `Parameter`
    handle, additive to the device's return-tuple `vars`, defaulting to the exact
    prior literal (never changing default solved behavior)."

requirements-completed: [MPC-01]

# Metrics
duration: 20min
completed: 2026-08-09
---

# Phase 21 Plan 01: Parameter-widen stateful devices for the MPC-01 seam Summary

**PVBattery/Thermostatic/FourQuadBESS initial-condition states and PVBattery/Thermostatic/Aggregator per-step profile inputs (Ppv, Tout, Pdc) are now genuine JuMP `Parameter` handles, re-settable without rebuilding, with byte-identical solved defaults.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-08-09T09:31:00-03:00 (worktree base commit)
- **Completed:** 2026-08-09T09:47:06-03:00 (last task commit) + verification
- **Tasks:** 3/3 completed
- **Files modified:** 8 (4 `src/devices/*.jl` + 4 `test/test_*.jl`)

## Accomplishments

- `PVBattery.contribute!` returns `vars.soc0` (SOC IC) and `vars.Ppv_param` (per-step PV
  availability) as genuine `Parameter` handles; the `pv_used` PV-limit bound moved from a
  literal `upper_bound=` to a `Ppv_param`-backed constraint.
- `Thermostatic.contribute!` returns `vars.Tin0` (temperature IC) and `vars.Tout_param`
  (per-step ambient temperature, `t = 1:(T-1)` only) as genuine `Parameter` handles; the
  RC/ETP recursion now reads `Tout_param[t]` instead of the literal `d.Tout[t]`.
- `FourQuadBESS.contribute!` returns `vars.soc0` as a genuine `Parameter` handle — the
  identical idiom `PVBattery` applies.
- `Aggregator.contribute!` returns an additive `Pdc_param` field; the `:Rp`/`:Rq` residual
  writes at `agg.bus` now reference `Pdc_param[t]` instead of the literal `agg.Pdc[t]`,
  genuinely satisfying D-08's "PV **and demand** ground truth" perturbation seam (beyond
  RESEARCH.md's literal Ppv/Tout-only sketch).
- Every new Parameter defaults to the EXACT prior literal value (verified via
  `parameter_value`), and `set_parameter_value`/`set_parameter_value.` never adds a new
  variable or constraint (verified via `num_variables`/`num_constraints` invariants).
- Four new permanent `@testitem` regressions (one per file) proving both the Parameter
  mechanics and the byte-identical default.

## Task Commits

Each task was committed atomically:

1. **Task 1: Parameter-widen PVBattery and Thermostatic** - `b7a60cb` (feat)
2. **Task 2: Parameter-widen FourQuadBESS and Aggregator.Pdc** - `aa90380` (feat)
3. **Task 3: Permanent regression coverage across all four widened files** - `bacc710` (test)

_No TDD RED/GREEN/REFACTOR gate sequence — this plan's tasks are `tdd="true"` but the
Parameter-widening is additive and non-breaking-by-construction; verification is
inline `<verify>` scripts and Task 3's permanent regressions, not a separate
test-then-implement gate. Consistent with the plan's own execution shape (no red-phase
gate specified)._

## Files Created/Modified

- `src/devices/PVBattery.jl` — `soc0`/`Ppv_param` Parameter widening; `pv_used` PV-limit
  bound moved to a constraint.
- `src/devices/Thermostatic.jl` — `Tin0`/`Tout_param` Parameter widening; RC/ETP recursion
  now reads `Tout_param[t]`.
- `src/devices/FourQuadBESS.jl` — `soc0` Parameter widening (identical idiom to
  PVBattery).
- `src/devices/Aggregator.jl` — `Pdc_param` Parameter widening; `:Rp`/`:Rq` residual
  writes now reference `Pdc_param[t]`.
- `test/test_pvbattery.jl` — new byte-identical-default regression item; fixed the
  pre-existing exact-variable-count assertion (`4T` → `5T + 1`).
- `test/test_thermostatic.jl` — new byte-identical-default regression item.
- `test/test_fourquadbess.jl` — new byte-identical-default regression item.
- `test/test_aggregator.jl` — new byte-identical-default regression item; fixed three
  pre-existing `Rq[bus,t].constant`/`.terms` assertions (structural AffExpr shape
  changed by the `Pdc_param` widening, evaluated value unchanged).

## Decisions Made

- Moved `pv_used`'s PV-limit bound from a literal `upper_bound=` kwarg to a
  `Ppv_param`-backed `@constraint` (Parameters cannot be passed as bound kwargs —
  RESEARCH.md Pitfall 4).
- Widened `Aggregator.Pdc` beyond RESEARCH.md's literal Ppv/Tout-only sketch, since
  `agg.Pdc` — not `Thermostatic.Tout` — is this project's actual inelastic-demand
  quantity D-08 requires perturbing.
- Updated (not left broken) three pre-existing structural AffExpr assertions in
  `test_aggregator.jl` and one exact-variable-count assertion in `test_pvbattery.jl`,
  since the widening legitimately changes the JuMP object SHAPE (a literal folding into
  `.constant` vs. a Parameter surfacing as a `.terms` entry; `all_variables` now
  counting the new Parameters) even though the SOLVED/EVALUATED behavior stays
  byte-identical — the tests' substantive intent is preserved via `parameter_value`-
  and coefficient-based checks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing `test_pvbattery.jl` exact-variable-count assertion**
- **Found during:** Task 1 (PVBattery Parameter widening)
- **Issue:** `@test length(vars) == 4T` asserted an exact `all_variables(model)` count
  that predates the widening. JuMP `Parameter`s are genuine `VariableRef`s, so adding
  `soc0` (1) and `Ppv_param` (T) legitimately raises the count to `5T + 1`. Confirmed
  empirically (T=4: 16 → 21 variables).
- **Fix:** Updated the assertion to `5T + 1` with an explanatory comment; the
  zero-binary/zero-integer invariant it guards remains intact and re-verified.
- **Files modified:** `test/test_pvbattery.jl`
- **Verification:** Ran the test body as a plain script; passes.
- **Committed in:** `b7a60cb` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed three pre-existing `test_aggregator.jl` Rq `.constant`/`.terms` assertions**
- **Found during:** Task 2 (Aggregator.Pdc_param widening)
- **Issue:** Three existing assertions checked `Rq[bus,t].constant == -Pdc[t]*tanφ` and
  `isempty(Rq[bus,t].terms)`, asserting the inelastic-demand contribution is a bare
  numeric constant. Replacing the literal `agg.Pdc[t]` with the Parameter `Pdc_param[t]`
  moves that contribution from `.constant` into a `.terms` entry keyed by the Parameter
  VariableRef (constant becomes 0.0) — an inherent JuMP mechanic of Parameters (they are
  syntactic variables, never folded into `.constant`, regardless of solved/default
  value). Confirmed empirically (constant 0.0, 1 term, before any solve).
- **Fix:** Updated the three assertion blocks to check `Rq[bus,t].constant ≈ 0.0` and
  `get(Rq[bus,t].terms, res.Pdc_param[t], 0.0) ≈ -tanφ`, plus a `parameter_value`
  byte-identical-default check — preserving each test's substantive verification intent
  (the reactive contribution genuinely equals `-Pdc[t]·tanφ`) against the new mechanic.
- **Files modified:** `test/test_aggregator.jl`
- **Verification:** Ran all three affected test bodies as plain scripts; all pass.
- **Committed in:** `aa90380` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — pre-existing test assertions invalidated
by the plan's own intentional, correctly-implemented widening, not by a code bug).
**Impact on plan:** Both fixes are mechanically necessitated by JuMP's `Parameter`
semantics (a genuine VariableRef, never a literal), not scope creep — the plan's own
must_haves require these four files' pre-existing tests to stay green, and doing so
required updating two tests' literal-shape assertions to check the equivalent
Parameter-aware structure. No other test files in the broader suite (test_admm*.jl,
test_agr.jl, test_dso.jl, test_device.jl, test_welfare*.jl, test_planning_*.jl,
test_powerflow.jl) were found to assert exact variable/constraint counts or raw
`.constant`/`.terms` shapes tied to these four devices (verified by grep across the full
test/ directory) — the risk flagged by threat T-21-02 appears contained to the two files
fixed here, though the plan's own `<verification>` correctly defers the FULL-suite
confirmation to plan 21-06.

## Issues Encountered

None beyond the two auto-fixed test-assertion breaks documented above.

## Widened Return-Tuple Shapes (for plan 21-03's window builder)

Recorded verbatim per the plan's `<output>` instruction — plan 21-03 reads these shapes
directly from `ctx.meta[:agg_device_vars]`:

- `PVBattery.contribute!` → `(; vars = (; p_ch, p_dch, soc, pv_used, soc0, Ppv_param), p_inject, utility)`
- `Thermostatic.contribute!` → `(; vars = (; p, Tin, Tin0, Tout_param), p_inject, utility)`
  (`Tout_param` has length `T-1`, or is an empty `Vector{VariableRef}` when `T == 1`)
- `FourQuadBESS.contribute!` → `(; vars = (; p_ch, p_dch, soc, q, soc0), p_inject, q_inject = q, utility)`
- `Aggregator.contribute!` → `(; vars = device_vars, p_inject, q_inject, utility, Pdc_param)`

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three `must_haves.truths` verified empirically:
  1. Every stateful device's IC constraint is backed by a genuine `Parameter`,
     re-settable via `set_parameter_value` without rebuilding.
  2. PV availability, ambient temperature, and inelastic demand are each Parameter-backed
     per time step.
  3. Every widened device's DEFAULT behavior is byte-identical to its pre-widening
     literal-constant behavior — confirmed for every pre-existing test in the four
     touched files (two required an assertion-shape update, documented above as
     deviations, not behavior changes).
- SEAM-01's `horizon_state` stub (`src/models/oracle.jl:76-80`) now has a concrete
  mechanism to consume in Wave 2: every IC/profile Parameter this plan created.
- Full-suite regression (welfare/ADMM/planning tests using these four devices) is
  explicitly deferred to plan 21-06 per this plan's own `<verification>` section and the
  threat model's T-21-02 disposition — a targeted grep across the broader test suite
  found no other exact-shape assertions at risk, but this is not a substitute for
  running the full `Pkg.test()` suite.

---
*Phase: 21-mpc-rolling-horizon-real-time-pricing*
*Completed: 2026-08-09*
