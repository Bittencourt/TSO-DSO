---
phase: 19-4q-bess-live-reactive-dual-ascent
plan: 05
subsystem: optimization
tags: [jump, clarabel, socp, complementarity, certificate, mesh-04]

# Dependency graph
requires:
  - phase: 19-02
    provides: "FourQuadBESS device (contribute! returning (;vars,p_inject,q_inject,utility) with vars.q as the distinguishing 4Q field)"
provides:
  - "assert_4q_complementarity!(ctx; rtol, atol, T, report) — a new, exported, throw-by-default post-solve certificate for FourQuadBESS's p_ch*p_dch complementarity, with a measured (not copied) WR-01 tolerance"
  - "assert_battery_complementarity!'s tightened selection (excludes any :q-carrying device) so the two certificates are structurally mutually exclusive over ctx.meta[:agg_device_vars]"
  - "A demonstrated, reproducible honest-boundary fixture (grid-charging + tight SOC band) where the certificate legitimately throws (D-08), and its report=true neutralization"
affects: ["19-06", "19-07", "19-08"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Measurement-before-golden tolerance calibration: sweep a benign fixture, record the Clarabel noise floor, pin atol/rtol with documented margin — never copy another certificate's constant (certificate-laundering guard)"
    - "Peer certificate dispatch via a distinguishing NamedTuple key (haskey(v,:q)) rather than a device-type check, keeping ctx.meta[:agg_device_vars] device-agnostic"

key-files:
  created: []
  modified:
    - src/models/complementarity_4q.jl
    - src/models/welfare_solve.jl
    - test/test_fourquadbess.jl

key-decisions:
  - "Tolerance defaults (rtol=1e-6, atol=1e-6, combined as atol+rtol*scale^2 with scale=max(Pch_max,Pdch_max)) were measured against a 5-point lambda_test sweep on a benign FourQuadBESS fixture (noise floor <= 2.6e-9 absolute / <= 1.1e-10 relative-to-scale^2), then documented in the docstring with the measured values — never reused from assert_battery_complementarity!'s Pmax^2-scaled constant."
  - "The honest-boundary violating fixture drives grid-charging to its cap via a price signal while a tight upper SOC band (Emax only 0.2 above soc0) forces a compensating discharge, exploiting round-trip inefficiency (eta<1) to vent a large charge cheaply via a small discharge — a genuine, reproducible p_ch*p_dch~15.2 co-activation, not solver noise."

requirements-completed: [MESH-04]

# Metrics
duration: 35min
completed: 2026-08-08
---

# Phase 19 Plan 05: 4Q-BESS Complementarity Certificate Summary

**New `assert_4q_complementarity!` post-solve certificate with a measured (not copied) tolerance, mutually exclusive with the OLD battery check, demonstrating the honest D-08 negative-price + grid-charging boundary.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-08T08:20Z (approx.)
- **Completed:** 2026-08-08T08:46Z (approx.)
- **Tasks:** 2/2 completed
- **Files modified:** 3

## Accomplishments
- Implemented `assert_4q_complementarity!(ctx; rtol, atol, T, report) -> Float64` in `src/models/complementarity_4q.jl`: selects only `FourQuadBESS`-shaped vars (`haskey(v,:q)`), computes a WR-01 combined `atol + rtol*scale²` tolerance (`scale = max(Pch_max, Pdch_max)`, honoring D-02/D-04's independent caps), throws by default naming bus/time/values/tolerance, and a `report=true` kwarg neutralizes the throw into an `@warn` while still returning the worst ratio.
- Measured (not assumed) the `rtol`/`atol` defaults against this device's own Clarabel noise floor on a benign, positive-in-band-price fixture swept across 5 `λ_test` values — documented in the function's docstring with the exact measured values (D-07).
- Tightened `assert_battery_complementarity!`'s loop condition (`welfare_solve.jl`) with a minimal one-line change (`&& !haskey(v, :q)`) so it structurally never matches a `FourQuadBESS`'s vars (T-19-11).
- Constructed and verified a deliberate, reproducible negative-effective-price + grid-charging fixture (`Pch_max=Pdch_max=8`, tight `Emax` only 0.2 above `soc0`, `η=0.5`) that genuinely co-activates `p_ch·p_dch ≈ 15.2` at `t=1` — five orders of magnitude past the measured-tolerance threshold — proving the certificate throws on the honest D-08 boundary and that `report=true` neutralizes it without any other `src/` edit.
- Added 4 new `@testitem`s to `test/test_fourquadbess.jl` (tagged `:complementarity`) covering: benign pass + no-only-ctx callability + no-op absent stash; OLD-check-skips-4Q proof; honest-boundary throw; `report=true` neutralization.

## Task Commits

Both tasks were committed atomically:

1. **Task 1: `assert_4q_complementarity!` with a measured (not copied) tolerance** - `56995c5` (feat)
2. **Task 2: Disambiguate the OLD check + honest-boundary and report-kwarg tests** - `e32071b` (feat)

_Note: Task 1's `<files>` scope was `src/models/complementarity_4q.jl` only per the plan's task partition; the persisted test items proving Task 1's acceptance criteria (benign-pass, exported, only-ctx-callable) were added together with Task 2's tests in the second commit, since `test/test_fourquadbess.jl` was Task 2's listed file. Both tasks were verified via direct Julia/Test.jl scripts reproducing the relevant behavior before committing (per orchestrator guidance — the plan's literal `TestItemRunner.runtests(...)` verify commands do not resolve under `--project=.`)._

## Files Created/Modified
- `src/models/complementarity_4q.jl` - Filled in from a comment-only stub: `assert_4q_complementarity!` with its measured tolerance and docstring.
- `src/models/welfare_solve.jl` - `assert_battery_complementarity!`'s loop condition tightened (`&& !haskey(v, :q)`) + docstring note on the peer relationship.
- `test/test_fourquadbess.jl` - 4 new `@testitem`s appended (existing 11 items from plan 19-02 untouched).

## Decisions Made
- Tolerance provenance: measured a 5-point `λ_test` sweep (1.5, 2.5, 4.0, 6.0, 8.5) on a benign `FourQuadBESS` fixture (`Pch_max=4, Pdch_max=5, scale²=25`), observing `max|p_ch·p_dch|` in `[2.9e-10, 2.5e-9]` (relative-to-`scale²`: `[1.16e-11, 1.01e-10]`). Pinned `atol=1e-6`, `rtol=1e-6` — ~3-4 orders of margin above the measured floor, independent of and tighter than `assert_battery_complementarity!`'s SOCP-path `τ=1e-3`.
- Honest-boundary fixture design: rather than literally negating a single `λ_test` (which, in this harness's `objective = utility - λ_test*Σp_inject` sign convention, favors *discharge* when very negative and is self-limiting via SOC-floor throttling — verified empirically to NOT produce co-activation), the violating fixture uses a large *positive* `λ_test=9.0` that makes grid-charging independently attractive up to `Pch_max` (bound-constrained, since its unconstrained FOC optimum vastly exceeds the cap) while a tight `Emax` forces venting via discharge — the genuine, asymmetric-round-trip-efficiency mechanism the `FourQuadBESS.jl` derivation docstring's step 3 describes. This is documented in the new test's comment, explaining that discharging at the binding period nets an effective price of `-λ_test` (i.e., a *negative* effective per-unit price for injection), which is the reading of "negative effective nodal price" that matches D-08.

## Deviations from Plan

None — plan executed exactly as written; the test-item placement note above (Task 1's tests landing in Task 2's commit) is a scope clarification, not a deviation, since Task 1's `<files>` list explicitly excluded the test file.

## Issues Encountered
- The plan's literal `<verify>` commands (`julia --project=. -e 'using TestItemRunner; ...'`) do not resolve `TestItemRunner` under `--project=.` (confirmed: `ArgumentError: Package TestItemRunner not found in current path`), consistent with the orchestrator's prior-wave finding. Resolved by writing direct Julia scripts (`Pkg.activate("."); using TSODSO, JuMP, Test`) that reproduce the exact behavior of every new `@testitem`, plus a final `import Pkg; Pkg.precompile()` sanity check — all passed before committing the persisted test items.
- Deriving a genuine (not solver-noise) complementarity violation required understanding an asymmetric mechanism: round-trip inefficiency (`η<1`) makes "venting" an aggressively price-favored charge via a *small* compensating discharge cheap, while the mirror-image ("venting" a price-favored discharge via compensating charge, under a tight `Emin`) is *not* cheap and the optimizer self-throttles instead — confirmed empirically across several parameter sweeps before landing on the working fixture (`Pch_max=Pdch_max=8`, `Emax=soc0+0.2`, `η=0.5`, `λ_test=9.0`, T=2).
- Ran the full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`) after both commits to satisfy Task 2's explicit acceptance criterion (zero pre-existing item flips). Result: **2439 passed / 0 failed / 3 broken** (Total 2442) in 11m35.8s — the 3 broken items match the orchestrator's recorded pre-existing baseline exactly; no failures anywhere in the suite. The higher pass count vs. the orchestrator's cited "2359" figure reflects the cumulative tests already added by plans 19-01..19-04 (this worktree's base commit, `95d617d1`, already includes those waves) plus this plan's 4 new `@testitem`s — not a discrepancy.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `assert_4q_complementarity!` is implemented, exported, and measured — ready for plan 19-06/19-07 to wire its call site into `solve_agr!`/`solve_admm`'s final consolidation block (flagged in the plan's threat register, T-19-11, as the next mitigation step: a dedicated "the certificate actually executes" test at that call site).
- No blockers for downstream Phase 19 plans.

## Self-Check: PASSED

- FOUND: src/models/complementarity_4q.jl
- FOUND: src/models/welfare_solve.jl
- FOUND: test/test_fourquadbess.jl
- FOUND commit 56995c5 (Task 1)
- FOUND commit e32071b (Task 2)
- Full suite: 2439 passed / 0 failed / 3 broken (Total 2442), 11m35.8s — matches the recorded pre-existing broken-test baseline exactly, zero regressions.

---
*Phase: 19-4q-bess-live-reactive-dual-ascent*
*Completed: 2026-08-08*
