---
phase: 18-directional-thesis-reproduction
plan: 01
subsystem: research-validation
tags: [julia, jump, clarabel, socp, welfare-accounting, fit-baseline, reproducibility, drwatson]

# Dependency graph
requires:
  - phase: 17-real-ieee123-impedances
    provides: "Real, Fortescue-reduced per-segment IEEE-123 impedances + the retuned population scale (LOAD_SCALE_IEEE123=0.05, PV_SCALE_IEEE123=0.12, DEV_SCALE_IEEE123≈0.0833) that keeps solve_welfare's SOCP-exactness gate passing at the pinned point"
  - phase: 16-reactive-power-consensus
    provides: "Reactive-pricing seam (decompose_dlmp(ctx).reactive) — not directly consumed by this measurement script, but the prerequisite ROADMAP dependency for Phase 18 overall"
provides:
  - "scripts/repro_stability_check.jl — a re-runnable, DrWatson-convention measurement script (N=20-repeat discrete flake-rate harness + a NEW ±2-5% population-scale sensitivity sweep on the real-impedance IEEE-123 fixture)"
  - "results/repro_stability_check/findings.txt — the committed measurement artifact Plan 18-02 hard-codes its golden band from"
  - "[CORRECTED 2026-07-26 — see ## Correction below] The DSO-surplus sign flip (FIT dso<0 -> DADP dso>0) is confirmed at the exact Phase-17-retuned point AND survives ±2%/±5% population-scale perturbation in BOTH directions (5/5 sweep points solve at tol_gap=1e-10; both surpluses monotone). The originally-recorded 'does NOT survive / all 4 points fail the SOCP-exactness gate outright' was a SOLVER-TOLERANCE ARTIFACT, and 2 of those 4 failures were fit_baseline misattributed to solve_welfare."
affects: [18-02, 18-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirrors scripts/reactive_flake_rate.jl's exact DrWatson scaffold / try-catch flake-counter / committed open(...,\"w\") findings shape, extended with a per-sweep-point try/catch so a genuine SOCP-exactness failure is recorded as data (a FAILED row + error detail) instead of crashing the whole measurement"

key-files:
  created:
    - scripts/repro_stability_check.jl
    - results/repro_stability_check/findings.txt
  modified: []

key-decisions:
  - "The population-scale sensitivity sweep's per-point solve is wrapped in try/catch (not left to propagate) so a real assert_socp_exact! throw is captured and reported as an honest FAILED data point, per the plan's own threat T-18-02 mandate — an uncaught crash would have produced ZERO findings, a worse honesty failure than reporting the failure"
  - "RECOMMENDED BAND (DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937) is derived ONLY from the 1/5 sweep points that solved successfully (delta=0.0, the exact Phase-17-retuned point) — the other 4 points are explicitly excluded and the band's derivation text flags this as not certifying cross-scale robustness"
  - "[CORRECTED 2026-07-26] sign_flip_survives=false was reported honestly given what was measured — the sweep was NOT narrowed and no failing point was omitted. But the verdict itself was WRONG: the four 'failures' were solver under-convergence at the default tol_gap=1e-8, not a physical exactness boundary. Honest reporting of a measurement does not make the measurement correct; the missing step was a tolerance ladder on any residual-based verdict. See ## Correction below."

patterns-established:
  - "Sweep-point-level try/catch + FAILED-row reporting: the correct shape for any future population-scale sensitivity script in this repo when the underlying solve can legitimately throw (SOCP exactness, infeasibility) rather than just return a different number"

requirements-completed: [REPRO-02]

# Metrics
duration: 45min
completed: 2026-07-26
---

# Phase 18 Plan 01: Repro Stability Check Summary

> ⚠️ **SUPERSEDED HEADLINE — see [## Correction](#correction-added-2026-07-26-after-milestone-archival) at the end of this file.**
> The DSO-surplus sign flip **does** survive ±2-5% population perturbation (5/5 points, both surpluses
> monotone). The "breaks down / the gate throws near that boundary" conclusion was a **solver-tolerance
> artifact**, and 2 of the 4 recorded failures were `fit_baseline` misattributed to `solve_welfare`.

~~**Measured (not assumed) that the thesis-mirroring DSO-surplus sign flip holds at the exact Phase-17-retuned IEEE-123 population point but breaks down under any ±2-5% population-scale perturbation, because the SOCP-exactness gate itself throws near that boundary — an honest negative robustness result that Plan 18-02's golden band and Plan 18-03's assumptions page must both carry forward.**~~

## Performance

- **Duration:** ~45 min (dominated by two Julia solve runs: ~10 min flake-rate + sweep pre-fix, ~13 min post-fix re-run; wall-clock includes solver warm-up/precompilation)
- **Started:** 2026-07-26T05:40:00Z (approx.)
- **Completed:** 2026-07-26T09:22:00Z
- **Tasks:** 2/2 completed
- **Files modified:** 2 (both new: `scripts/repro_stability_check.jl`, `results/repro_stability_check/findings.txt`)

## Accomplishments

- Wrote `scripts/repro_stability_check.jl` (460 lines): re-implements the IEEE-123 Phase-17-retuned population inline (mirroring `scripts/reactive_flake_rate.jl`'s established `@testmodule`-no-op workaround), defines `count_failures` (N=20-repeat discrete Clarabel flake-rate harness) and `sweep_population_scale` (NEW ±2-5% population-scale sensitivity sweep), calling `solve_welfare`/`welfare_accounting`/`fit_baseline` unmodified throughout.
- Ran the script twice (once pre-fix, once post-fix) against the real `ieee123_modified()` feeder and committed the resulting `results/repro_stability_check/findings.txt`.
- **Measured results (from the actual committed findings.txt):**
  - **Flake rate:** 0/20 = 0.0000 at the exact retuned point — no discrete Clarabel `NUMERICAL_ERROR`-class flakes.
  - **At delta=0.0 (the exact Phase-17-retuned point):** `dso=+3.725705` (DADP), `fit_dso=-196.216447` (FIT) — genuine sign flip confirmed; `prosumer=-41039.129322` (DADP) `< fit_prosumer=-40857.497070` (FIT), matching the thesis's qualitative "prosumer surplus decreases under DADP" direction; `socp_maxgap=3.060e-07` (exact).
  - ~~**Sweep at delta in {-0.05, -0.02, 0.02, 0.05}:** ALL FOUR points FAIL outright — `solve_welfare`'s `assert_socp_exact!` throws (`SOCP relaxation INEXACT`, worst gap/tol ratios ranging 1.10–3.23), exactly the near-boundary knife-edge risk 18-RESEARCH.md's Pitfall 4 flagged as a live possibility (not resolved as safe).~~
    **[CORRECTED]** Two of the four were `fit_baseline`, **not** `solve_welfare` — the script's single try/catch covered three solves, so the attribution was inferred rather than observed. All four are numerical: at `tol_gap=1e-10` they solve. Pitfall 4's knife-edge is **not** what was observed; on IEEE-123 the voltage upper bound is never even active.
  - ~~**`sign_flip_survives: false`** — reported honestly; the sweep range was not narrowed and no failing point was omitted.~~
    **[CORRECTED] `sign_flip_survives: TRUE` at all five points.** See ## Correction below.
  - **RECOMMENDED BAND: `DSO_BAND_LO=0.0`, `DSO_BAND_HI=5.58855710237937`** — derived as `1.5 * max(|dso|)` over ONLY the 1/5 successfully-solved points (delta=0.0), explicitly flagged in findings.txt as not certifying cross-scale robustness.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write scripts/repro_stability_check.jl** - `9238b79` (feat)
2. **Task 2: Run the stability check and commit its findings** - `99f0e69` (feat — includes the Rule-1 try/catch fix discovered while executing this task)

**Plan metadata:** (this commit, following SUMMARY.md write)

## Files Created/Modified

- `scripts/repro_stability_check.jl` - DrWatson-convention measurement script: N=20-repeat discrete flake-rate harness + ±2-5% population-scale sensitivity sweep on the real-impedance IEEE-123 fixture, calling `solve_welfare`/`welfare_accounting`/`fit_baseline` unmodified; sweep points are individually try/catch-wrapped so a genuine SOCP-exactness failure is recorded as a `FAILED` data row rather than crashing the script.
- `results/repro_stability_check/findings.txt` - committed measurement artifact (flake-rate table, sweep table with FAILED rows + error detail, `sign_flip_survives: false`, `RECOMMENDED BAND: DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937`), generated exclusively by the script's own `open(...,"w") do io ... end` block. **[CORRECTED 2026-07-26: no longer true — a hand-written `!!! CORRECTION` banner was prepended to that file because its verdict was refuted. Since the file IS generated, re-running the script overwrites the banner; fix the script first (see ## Correction, "Still owed").]**

## Decisions Made

- **Sweep failures are data, not crashes.** The plan's own task description anticipated `sign_flip_survives == false` as a possible honest outcome, but the initial script implementation had no error handling around the sweep's `solve_welfare` call. On the first real run, `δ=-0.05` threw `SOCP relaxation INEXACT` and killed the entire script before any findings.txt could be written. This is a Rule-1 bug fix (broken behavior: the script cannot fulfill its own committed-findings mandate if it crashes), not a scope change — I wrapped each sweep point in try/catch, recording `(; δ, failed=true, error_msg)` on failure, and updated `sign_flip_survives`/the RECOMMENDED BAND derivation/the findings.txt narrative to treat failed points honestly (a stronger, not weaker, form of "does not survive").
- **The RECOMMENDED BAND is derived from 1/5 points, explicitly flagged as such.** Rather than silently averaging over failures (impossible — they are NaN) or refusing to produce a band at all (which would block Plan 18-02 entirely), the band uses the one point that solved (the exact retuned point) with the documented 1.5x safety margin, and findings.txt explicitly states this does not certify cross-scale robustness — carrying the caveat forward rather than hiding it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `sweep_population_scale` had no error handling; a real SOCP-exactness failure crashed the entire script before any findings could be committed**
- **Found during:** Task 2 (first live run of the script)
- **Issue:** The Task 1 implementation called `solve_welfare` inside the sweep loop with no `try/catch`. On the real IEEE-123 fixture, `δ=-0.05` (a −5% population-scale perturbation) hit `assert_socp_exact!`'s exactness gate and threw `SOCP relaxation INEXACT` (worst gap/tol ratio 2.685 > 1), which propagated uncaught and terminated the Julia process before `results/repro_stability_check/findings.txt` was ever written — i.e., the REPRO-02-mandated committed artifact would not have existed at all.
- **Fix:** Wrapped each sweep point's `solve_welfare` + `welfare_accounting` + `fit_baseline` call in a `try/catch`, recording a `(; δ, failed=true, dso=NaN, ..., error_msg)` NamedTuple on failure (with a `@warn` including the caught exception + backtrace) instead of letting the exception propagate. Updated `sign_flip_survives` to treat any failed point as non-survival, and the `RECOMMENDED BAND` derivation to use only the successfully-solved points, with the findings.txt narrative explicitly flagging both the failure(s) and the reduced-evidence caveat on the band.
  **[CORRECTED 2026-07-26 — this fix is the ROOT CAUSE of the misattribution.]** Wrapping *three*
  solves in *one* `try/catch` means a `FAILED` row cannot say which call threw, and the narrative then
  attributed all four failures to `solve_welfare`'s gate — two were `fit_baseline`. Also: treating any
  failed point as non-survival conflates "measured as not surviving" with "could not be measured", and
  both were in fact "under-converged". Correct shape: one try/catch **per stage**, and a tolerance
  ladder before any residual-based verdict.
- **Files modified:** `scripts/repro_stability_check.jl`
- **Verification:** Re-ran the full script after the fix; it completed end-to-end and produced the committed `results/repro_stability_check/findings.txt` with all 4 non-zero sweep points reported as `FAILED` rows plus their exact error messages, and `sign_flip_survives: false` reported honestly. **[CORRECTED 2026-07-26: "correctly reported" overstated it — the rows were faithfully *recorded* but wrongly *attributed* and wrongly *concluded from*. That the script ran end-to-end and wrote its artifact verified the harness, not the finding.]**
- **Committed in:** `99f0e69` (folded into the Task 2 commit, since the fix was discovered and applied while executing Task 2's run-and-commit action)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug fix, discovered while running the script the plan mandated).
**Impact on plan:** Necessary for correctness — without it, the script could not fulfill its own stated deliverable (a committed findings.txt) whenever the sweep hit the documented near-boundary exactness knife-edge, which it did on the very first real run. No scope creep: the fix only makes an already-planned measurement complete instead of crashing.

## Issues Encountered

The SOCP-exactness failure itself (not the script bug) is a substantive research finding, not merely an "issue resolved": the DSO-surplus sign flip's robustness is genuinely fragile to population-scale perturbation in this regime — Plan 18-03's assumptions page must document this as a caveat (the sign-flip finding is anchored to ONE specific, carefully-retuned population point, not a broad basin).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 18-02 can now hard-code `DSO_BAND_LO=0.0`, `DSO_BAND_HI=5.58855710237937` as its gate-then-golden magnitude band, sourced from this plan's committed `findings.txt`, per REPRO-02's blocking ordering constraint (measurement before golden).
  **[CORRECTED 2026-07-26 — rule and value now disagree.]** `DSO_BAND_HI` was `1.5 × max|dso|` over
  solved points, which was **1** point. With 5 solving, `max|dso| = 4.807417`, so the same rule implies
  **7.211**. `test/test_thesis_repro.jl` does **not** break (4.8074 < 5.5886), so this is not urgent —
  but the band should be re-derived deliberately rather than left as a value its own stated rule no
  longer produces.
- ~~Plan 18-03's assumptions/reduction doc page MUST document the sweep's honest negative result (`sign_flip_survives: false`) as an explicit caveat: the DSO-surplus sign-flip finding is confirmed only at the exact Phase-17-retuned population scale, not across a ±2-5% neighborhood — any future population re-tune must re-run `scripts/repro_stability_check.jl` before trusting the golden band again.~~
  **[CORRECTED 2026-07-26]** 18-03 acted on this instruction, so **the published assumptions page now
  carries a caveat that is false** and is the highest-priority remaining correction (still owed — not
  fixed by this quick task). The sign flip is population-robust across ±5%. The "re-run
  `repro_stability_check.jl` after any re-tune" advice remains sound, but the script must first be
  fixed (split its three-solve try/catch; thread the `optimizer` kwarg from commit `c099ee6`).
- No blockers for Plan 18-02/18-03.

---
*Phase: 18-directional-thesis-reproduction*
*Completed: 2026-07-26*

## Self-Check: PASSED

- FOUND: scripts/repro_stability_check.jl
- FOUND: results/repro_stability_check/findings.txt
- FOUND: .planning/phases/18-directional-thesis-reproduction/18-01-SUMMARY.md
- FOUND commit: 9238b79 (Task 1)
- FOUND commit: 99f0e69 (Task 2)
- `grep -c "RECOMMENDED BAND" results/repro_stability_check/findings.txt` == 2 (label line + printed value line, >= 1 required)
- `grep -c "sign_flip_survives" results/repro_stability_check/findings.txt` == 1 (>= 1 required)

---

## Correction (added 2026-07-26, after milestone archival)

> **`sign_flip_survives: false` — the headline result of this plan — is REFUTED.**
> The four "failed" sweep points were **solver under-convergence**, not a physical exactness
> boundary. Nothing in the plan's execution was dishonest; the verdict was simply wrong, and the
> missing step was a tolerance ladder on a residual-based conclusion.

### What is actually true

Re-measured with the shipped exactness gate still **armed** (default `rtol_exact = 1e-4`), changing
only the *solver* tolerance to `tol_gap = 1e-10`:

| δ | socp_maxgap | dadp_dso | fit_dso | sign flip |
|---|---|---|---|---|
| −0.05 | 3.505e-08 | 2.709838 | −182.9611 | **YES** |
| −0.02 | 1.900e-08 | 3.277535 | −190.8755 | **YES** |
| 0.00 | 1.162e-08 | 3.725742 | −196.2165 | **YES** |
| +0.02 | 4.610e-08 | 4.163925 | −201.6167 | **YES** |
| +0.05 | 1.342e-08 | 4.807417 | −209.9950 | **YES** |

**5/5 solve. The sign flip holds at every point.** Both surpluses are monotone in population scale
(`dadp_dso` 2.71→4.81, `fit_dso` −183→−210) — no boundary, no discontinuity, no knife edge.

### Why the original measurement failed

`assert_socp_exact!`'s `atol = 1e-6` sits **at** Clarabel's achievable cone residual on this
122-branch feeder at the default `tol_gap = 1e-8`. Tightening shrinks the residual 1–2 orders of
magnitude while the optimum is unchanged (`dadp_dso` agrees to 6–7 significant figures) — a
structural relaxation gap is a property of the optimum and cannot behave that way.

Independently: on real IEEE-123 impedances the voltage upper bound is **never active** across a 5.5×
PV range (`vpeak ≤ 1.016` against caps ≥ 1.05), so the overvoltage mechanism that drives genuine SOC
inexactness does not occur on this feeder at all. 18-RESEARCH.md's Pitfall 4 knife-edge was therefore
not what this sweep observed.

### The misattribution

Ratios are bit-identical to 16 digits between the committed findings and the per-stage re-run, so
nothing was flaky — Clarabel is deterministic. But the *thrower* differed for half the points:

| δ | recorded ratio | actually threw in |
|---|---|---|
| −0.05 | 2.685423204302964 | `solve_welfare` ✓ as recorded |
| −0.02 | 3.227073440795618 | **`fit_baseline`** ✗ |
| +0.02 | 1.1425393613288473 | `solve_welfare` ✓ as recorded |
| +0.05 | 1.1002062714021996 | **`fit_baseline`** ✗ |

Root cause: `scripts/repro_stability_check.jl` wraps `solve_welfare` + `welfare_accounting` +
`fit_baseline` in **one** try/catch, so a `FAILED` row cannot identify which call threw. The
attribution in this summary was inferred from the error text, not observed.

`fit_baseline`'s failures were untestable at the time because it took no `optimizer` kwarg. That was
added in commit `c099ee6`, which is what made the 5/5 re-measurement possible.

### Lesson for future measurement plans

A cone-gap ratio near 1 is **not evidence** — structural inexactness on the 3-bus stress fixture
produces ratios of 1e3–1e4. Ratios of 1.1–3.2 must be tolerance-discriminated (re-solve tighter: a
structural property persists, numerical noise shrinks) before being reported as a finding. The WR-01
`atol + rtol·magnitude` idiom scales with quantity *magnitude* but **not** with solver *accuracy*, and
accuracy degrades with problem size.

### Still owed (NOT fixed by this correction)

1. **The published 18-03 assumptions literate page** carries the false fragility caveat — highest
   priority.
2. **Plan 18-02's golden band.** `DSO_BAND_HI` was derived as `1.5 × max|dso|` over solved points
   (then 1 point). With 5 solving, `max|dso| = 4.807417` ⇒ the rule implies **7.211** vs the pinned
   **5.5886**. `test/test_thesis_repro.jl` does not break (4.8074 < 5.5886), but rule and value
   disagree.
3. **`scripts/repro_stability_check.jl`** — split the three-solve try/catch; thread the `optimizer`
   kwarg. **Note `results/repro_stability_check/findings.txt` is generated by that script**, so its
   hand-added correction banner is overwritten on any re-run.

### Evidence

- `.planning/spikes/003-phase18-fragility-tolerance/README.md` — the investigation
- `.planning/spikes/003-phase18-fragility-tolerance/run.log` / `run-after-kwarg.log` — before / after
- `.planning/spikes/002-ieee123-validity-map/README.md` — the noise-floor proof
- `.planning/quick/260726-mo7-add-optimizer-kwarg-to-fit-baseline/` — the enabling change
- commits `c099ee6` (kwarg), `7705889` (spike 003)

**Equivalence control:** the re-measurement reproduces this plan's `δ=0` row bit-for-bit
(`dso = 3.725705`, `socp_maxgap = 3.060e-07`), so the comparison is valid rather than merely similar.
