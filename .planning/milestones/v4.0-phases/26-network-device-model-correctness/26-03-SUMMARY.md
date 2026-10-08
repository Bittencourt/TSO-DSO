---
phase: 26-network-device-model-correctness
plan: 03
subsystem: device-models
tags: [jump, socp, battery, mpc, soc-recursion]

# Dependency graph
requires: []
provides:
  - "PVBattery/FourQuadBESS soc[1:(T+1)] full-horizon SOC recursion (no more free hour-T energy)"
  - "Optional soc_terminal keyword (nothing | Real | :cyclic) on both battery contribute! methods"
  - "mpc_window.jl terminal wiring retargeted to soc[H+1]; obsolete H==1 double-pin guard removed"
affects: [26-network-device-model-correctness, mpc-rolling-horizon, stochastic-welfare]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Full-horizon SOC recursion (soc[1:(T+1)], unconditional t=1:T constraint) replacing the
       T-1-bounded guarded recursion — the FIX-04 correctness pattern for any future
       stateful-device temporal coupling"

key-files:
  created: []
  modified:
    - src/devices/PVBattery.jl
    - src/devices/FourQuadBESS.jl
    - src/models/mpc_window.jl
    - src/models/stochastic_welfare.jl (audit + doc-comment fix, no functional change)
    - test/test_pvbattery.jl
    - test/test_fourquadbess.jl
    - test/test_mpc_window.jl
    - test/test_stochastic_oos_harness.jl (doc-comment fix, no functional change)

key-decisions:
  - "soc extended to 1:(T+1) with the recursion closing unconditionally over t=1:T (dropping the
     `if T > 1` guard), rather than leaving t=T unconstrained — matches the plan's Option A shape"
  - "mpc_window.jl's WR-03 H==1 guard removed entirely rather than relaxed — the double-pin
     collision it guarded against no longer exists once the terminal target is soc[H+1]"
  - "FourQuadBESS's zero-discharge-at-T regression uses an exogenous p_ch[1:(T-1)]==0 constraint
     (not the plan's literal shared fixture) because FourQuadBESS can rationally pre-charge from
     the grid — see Deviations"

patterns-established:
  - "Pattern: extend a stateful device's temporal state vector to T+1 and close the recursion
     unconditionally over the full horizon, rather than leaving the last step's controls
     structurally unconstrained by any state variable"

requirements-completed: [FIX-04]

# Metrics
duration: ~25min
completed: 2026-09-28
---

# Phase 26 Plan 03: Battery SOC Horizon Linking (FIX-04) Summary

**Closed the free-hour-T-energy defect: PVBattery/FourQuadBESS now carry `soc[1:(T+1)]` with an
unconditional whole-horizon recursion, an optional `soc_terminal` keyword, and `mpc_window.jl`'s
terminal wiring retargeted to `soc[H+1]` with the obsolete `H==1` double-pin guard removed.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3 completed
- **Files modified:** 8 (4 source, 4 test — 2 of the test files are doc-comment-only fixes for
  consistency, not in the plan's `files_modified` list)

## Accomplishments

- `PVBattery.jl` and `FourQuadBESS.jl` both declare `soc = @variable(m, [t = 1:(T + 1)], ...)`
  and close the SOC recursion unconditionally over `t = 1:T` (dropping the old `if T > 1` guard),
  so `p_ch[T]`/`p_dch[T]` always appear in a constraint — hour-T charge/discharge is no longer
  free energy.
- Both devices gained an optional `soc_terminal::Union{Nothing,Real,Symbol} = nothing` keyword on
  `contribute!`: `nothing` (default, byte-identical), a `Real` value (`soc[T+1] == value`), or
  `:cyclic` (`soc[T+1] >= soc0`, re-targets automatically under MPC re-solves).
- `src/models/mpc_window.jl`'s `build_mpc_window` retargets the terminal-condition constraint from
  `v.soc[H] == term` to `v.soc[H + 1] == term`, and the WR-03 `terminal_soc && H == 1` guard is
  removed entirely — `H = 1, terminal_soc = true` now builds successfully instead of throwing.
- `src/models/stochastic_welfare.jl` audited: no functional change needed (per-scenario copies
  delegate to `contribute!` verbatim, and the "soc deliberately not tied" argument holds
  independent of `soc`'s length); one stale `soc[H]` doc-comment citation updated for accuracy.
- Test goldens updated: `test_pvbattery.jl`'s `all_variables` count moved `5T+1 -> 5T+2`;
  `test_fourquadbess.jl`'s `length(soc)` moved `T -> T+1` (+ a new `soc[T+1]` bounds check);
  `test_mpc_window.jl`'s `H=1, terminal_soc=true` case flipped from `@test_throws` to a
  successful-build assertion. Two new zero-discharge-at-hour-T regressions added (one per device).

## Task Commits

1. **Task 1: Extend soc to 1:(T+1) with a full-horizon recursion in PVBattery and FourQuadBESS** -
   `cfa7e6e` (feat)
2. **Task 2: Retarget mpc_window.jl terminal wiring to soc[H+1] and drop the obsolete H==1 guard;
   audit stochastic_welfare.jl** - `9c43e11` (feat)
3. **Task 3: Update the affected test goldens and add the FIX-04 regressions** - `168e4c8` (test)

## Files Created/Modified

- `src/devices/PVBattery.jl` - `soc[1:(T+1)]`, unconditional whole-horizon recursion,
  `soc_terminal` keyword
- `src/devices/FourQuadBESS.jl` - same shape, byte-identical pattern to PVBattery
- `src/models/mpc_window.jl` - terminal target `soc[H] -> soc[H+1]`, `H==1` guard removed
- `src/models/stochastic_welfare.jl` - stale `soc[H]` doc-comment citation corrected to `soc[H+1]`
- `test/test_pvbattery.jl` - `5T+1 -> 5T+2` golden; new zero-discharge-at-T `@testitem`
- `test/test_fourquadbess.jl` - `T -> T+1` golden; new `soc[T+1]` bounds check; new
  zero-discharge-at-T `@testitem` (with the exogenous no-prior-charging constraint, see Deviations)
- `test/test_mpc_window.jl` - `H=1, terminal_soc=true` flipped from throw to successful build
- `test/test_stochastic_oos_harness.jl` - stale `soc[H]` doc-comment citation corrected

## Decisions Made

- Full-horizon recursion (Option A per plan): drop the `if T > 1` guard and close the recursion
  unconditionally over `t = 1:T` — the recursion always has at least the `t=1` term now, so the
  guard was purely a historical artifact of the old `1:(T-1)` range.
- `mpc_window.jl`'s `H==1` guard removed rather than relaxed to a narrower condition — the plan's
  own reasoning (the terminal target is a structurally different index from the IC once `soc` is
  `T+1` long) makes the guard's original collision impossible at any `H`, so there is no remaining
  case it needs to catch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Fixture bug] FourQuadBESS's Task-1/Task-3 zero-discharge-at-T verify fixture does
not demonstrate the intended property with the plan's literal shared args**
- **Found during:** Task 1, running the plan's own `<verify>` script
- **Issue:** The plan's Task 1 `<verify>` script uses the SAME literal constructor args for both
  `PVBattery` and `FourQuadBESS` to test "soc0=Emin + no prior charging headroom => zero
  hour-T discharge." For `PVBattery`, "no prior charging headroom" is physically enforced by
  `Ppv ≡ 0` (Assumption A6: charge from PV only) — `p_ch` is capped at zero regardless of
  incentive. `FourQuadBESS` has no such external limiter (D-02: it may charge from the grid), and
  its App. C utility gives a genuine, price-independent marginal benefit to charging whenever
  there is bound headroom. Running the plan's literal script showed `FourQuadBESS`'s `p_dch[T]`
  converges to `4.999999998` (≈`Pdch_max`), not `< 1e-6` — it rationally pre-charges at hours
  `1:(T-1)` (paying a real, book-kept quadratic utility cost) to unlock the hour-T discharge
  reward, since the reward (price=100) vastly outweighs the charging + discharge costs. This is
  NOT the old free-energy bug reappearing — the discharge is genuinely backed by real prior
  charging the now-closed recursion correctly accounts for — but it means the SAME fixture cannot
  demonstrate the SOC-closing property for `FourQuadBESS` the way it does for `PVBattery`.
- **Fix:** For `FourQuadBESS`'s zero-discharge-at-T regression only, added an EXOGENOUS
  `@constraint(model, [t = 1:(T-1)], res.vars.p_ch[t] == 0.0)` to the test, imposing "no prior
  charging headroom" directly (mirroring the PHYSICAL constraint `PVBattery` gets for free from
  `Ppv ≡ 0`) so the test isolates the SOC-closing property from `FourQuadBESS`'s own rational
  pre-charging economics. Verified numerically: with this constraint, `p_dch[T] ≈ 1.27e-11`.
  `PVBattery`'s regression uses the plan's original literal fixture unchanged (it already holds).
- **Files modified:** `test/test_fourquadbess.jl` (documented inline in the new `@testitem`'s
  comment block, matching this exact explanation)
- **Verification:** Direct script confirmed `p_dch[T] < 1e-6` for both devices under their
  respective (device-appropriate) "no prior charging headroom" fixtures; both devices' new
  `@testitem`s pass.
- **Committed in:** `168e4c8` (Task 3 commit)

**2. [Rule 1 - Doc accuracy] Two doc-comment citations left stale by the `soc[H]` -> `soc[H+1]`
retarget**
- **Found during:** Task 2's mandated grep audit
  (`git grep -n "soc\[H\]\|soc\[T\]\|length(soc)\|soc\[end\]" src/`)
- **Issue:** `src/models/stochastic_welfare.jl`'s `StochasticOosHarness` doc comment and
  `test/test_stochastic_oos_harness.jl`'s file-header comment both cited `mpc_window.jl`'s old
  `soc[H] == terminal_param` idiom by name, which would read as stale/incorrect after the retarget.
- **Fix:** Updated both citations to `soc[H + 1] == terminal_param`, noting the Phase 26 FIX-04
  retarget inline. No functional code change in either file.
- **Files modified:** `src/models/stochastic_welfare.jl`, `test/test_stochastic_oos_harness.jl`
- **Verification:** `git grep -n "soc\[H\]\|soc\[T\]\|length(soc)\|soc\[end\]" src/` now shows
  no stale live-code references (only the corrected citations and this plan's own new comments).
- **Committed in:** `9c43e11` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 fixture bug, 1 doc accuracy)
**Impact on plan:** Both deviations necessary for the tests to actually demonstrate the FIX-04
property and for documentation to stay accurate. No scope creep — no files outside the plan's
`files_modified` list were touched except the two doc-comment-only fixes, which are directly
caused by Task 2's retarget and are non-functional.

## Issues Encountered

None beyond the fixture design gap documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-04 is complete: both battery devices correctly link SOC across the whole horizon, with an
  optional terminal-condition keyword ready for future MPC/planning consumers.
- `mpc_window.jl` no longer artificially forbids `H=1, terminal_soc=true` — a previously-blocked
  single-hour receding-horizon configuration is now usable.
- `src/models/stochastic_welfare.jl` required no functional change (confirmed by audit), so
  Phase 26's stochastic-welfare seam is unaffected by this plan.
- No blockers for parallel plans 26-01/26-02/26-04 (disjoint files per the wave's isolation
  contract) or for subsequent Phase 26 plans depending on this one.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 9 claimed files verified present on disk (8 source/test files + this SUMMARY). All 3 task
commit hashes (`cfa7e6e`, `9c43e11`, `168e4c8`) verified present in the worktree's git history via
`git cat-file -t`. All per-task `<verify>` scripts and the additional spot-check of the two
edited existing `@testitem` bodies (fourquadbess variable/bounds, battery convex-QP golden) were
re-run directly and passed.
