---
phase: 16-reactive-power-consensus
plan: 03
subsystem: infra
tags: [julia, jump, dlmp, pricing, reactive-power, dual-extraction]

# Dependency graph
requires:
  - phase: 16-reactive-power-consensus (plan 02)
    provides: "qag_dso pinned coupling variable + assert_no_slack certificate on :balance_q (the trustworthy dual this plan reads)"
provides:
  - "extract_reactive_dlmp(ctx; bus, T) -> Matrix{Float64}|Vector{Float64}, mirroring extract_dlmp's shape/gate exactly, reading dual.(ctx.constraints[:balance_q]), with a presence guard (ArgumentError) for ctxs with no reactive channel"
  - "decompose_dlmp(ctx) gains a 6th-field-count NamedTuple with a new `reactive` field (extract_reactive_dlmp(ctx)), documented as a SEPARATE 5th DLMP component, never summed into `total`; the existing 4-term active sum-to-price assertion is unchanged"
  - "A hand-verified 2-bus reactive-price sanity pin (lossy r=0.01/x=0.02 fixture): root price degenerate (~0), load-bus price finite, finite-difference economic-consistency check against a perturbed power factor"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "one-shot certified dual read via _assert_priceable (PF-04 choke point), mirrored verbatim for a second constraint (:balance_q) -- no new certification philosophy invented, per 16-PATTERNS.md's central template"
    - "finite-difference economic-consistency check (envelope theorem: perturb a fixed model parameter, re-solve, confirm Delta(objective) matches dual * Delta(parameter) to first order) used in place of a further closed-form KKT derivation of the reactive price itself -- appropriate since REACT-02 asks for a single reactive price, not a further decomposition of it"

key-files:
  created: []
  modified:
    - src/pricing/dlmp.jl
    - test/test_pricing_dlmp.jl

key-decisions:
  - "reactive is a NamedTuple field, never summed into total -- decompose_dlmp's existing 4-term (energy+loss+congestion+voltage=total) sum-to-nodal-price assertion is byte-for-byte unchanged; reactive is documented as a dimensionally/economically distinct price signal (dual of :balance_q, not :balance_p)."
  - "extract_reactive_dlmp needs its OWN :balance_q presence guard (ArgumentError, not KeyError) even though decompose_dlmp itself does not need one -- decompose_dlmp already requires the ConvexBranchFlow-only :cone/:vdrop/:cpydrop/:smax handles, so any ctx reaching it always has :balance_q by construction; the guard exists only for extract_reactive_dlmp's direct/DC-only callers."
  - "finite-difference sanity pin uses a SUM over the horizon (Sigma_t d.reactive[2,t]*(q1[t]-q0[t])) matched against the single scalar Delta(objective) from solve_welfare, not a per-t comparison -- confirmed empirically first (probe script) that a per-t comparison under-predicts by ~3x on T=3 since the objective aggregates all hours identically under a uniform power-factor perturbation."

patterns-established:
  - "Any new dual-based price this project adds should gate on _assert_priceable first and mirror extract_dlmp's exact (bus=nothing/T=nothing) return-shape convention -- now demonstrated twice (extract_dlmp, extract_reactive_dlmp)."

requirements-completed: [REACT-02]

# Metrics
duration: ~55min
completed: 2026-07-26
---

# Phase 16 Plan 03: DLMP Reactive-Price Extraction Summary

**Added `extract_reactive_dlmp` (mirroring `extract_dlmp`'s shape/PF-04 gate exactly) and a new `reactive` field on `decompose_dlmp`'s NamedTuple, reading the dual of the now-certified `:balance_q` (Plan 16-02) as a documented, citable 5th DLMP component that is never summed into the existing 4-term active-price total.**

## Performance

- **Duration:** ~55 min (dominated by a ~17 min full-suite `Pkg.test()` verification run, plus an initial 590s-timeout retry)
- **Tasks:** 2
- **Files modified:** 2 (`src/pricing/dlmp.jl`, `test/test_pricing_dlmp.jl`)

## Accomplishments

- `extract_reactive_dlmp(ctx; bus = nothing, T = nothing)`: gated by the SAME `_assert_priceable` PF-04 exactness certificate `extract_dlmp` requires, plus its own presence guard (`ArgumentError`, never `KeyError`) for ctxs with no `:balance_q` (e.g. a hand-built DC-only ctx). Returns `dual.(ctx.constraints[:balance_q])`, same `(bus, T)` slicing convention as `extract_dlmp`.
- `decompose_dlmp(ctx)` now returns `(; energy, loss, congestion, voltage, reactive, total)` — `reactive = extract_reactive_dlmp(ctx)`, added as a 6th field on BOTH the full-matrix and per-bus return branches. The existing 4-term `energy+loss+congestion+voltage ≈ total` hard assertion is byte-for-byte unchanged (confirmed by inspection and by the dlmp-filtered test suite staying green with no term-count change).
- New `@testitem` on the lossy 2-bus fixture (`Branch(1,2,0.01,0.02,10.0)`, mirroring `test_ac_oracle.jl`) with a non-degenerate aggregator power factor (`φ=0.9`): confirms `d.reactive[1,t] ≈ 0` (atol=1e-6) at the root — the free-sign, zero-objective-coefficient `q_import`'s own KKT stationarity forces its dual to exactly zero — and `isfinite(d.reactive[2,t])` at the load bus.
- Finite-difference economic-consistency pin: perturbed the SAME aggregator's `φ` by `δ=1e-4`, re-solved, and confirmed `Σ_t d.reactive[2,t]·(q1[t]-q0[t])` matches the welfare objective's actual change to first order (`atol=1e-8, rtol=5e-2`), using `reactive_factor` (the same formula the production `Aggregator.contribute!` path uses) to compute `q0`/`q1`. Empirically probed first (a throwaway script) to confirm the SUM-over-horizon form is the correct comparison (a per-hour comparison under-predicted by ~3× on `T=3` since a uniform `φ` perturbation affects every hour identically while the objective delta aggregates all of them).
- Extended the existing IEEE-13 "decompose_dlmp four components SUM" test item with a parallel, non-summed finite-check loop (`for f in (d.energy, d.loss, d.congestion, d.voltage, d.reactive); @test all(isfinite, f); end`) — additive only, the 4-term sum-to-price assertion in that same item is untouched.
- Verified: `dlmp`-filtered suite 688/688 → 700/700 pass (12 new items) after Task 1, then 700/700 after Task 2's additions. Full `Pkg.test()`: **2337 passed, 3 broken (pre-existing markers), 0 failed**, 2340 total — the wave-merge regression gate per 16-VALIDATION.md.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add extract_reactive_dlmp and decompose_dlmp's reactive field** - `e734565` (feat)
2. **Task 2: Hand-verified 2-bus reactive-price sanity pin + degeneracy/finite checks** - `9af6cc2` (test)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `src/pricing/dlmp.jl` — New `extract_reactive_dlmp(ctx; bus, T)` immediately after `extract_dlmp`, mirroring its body exactly but reading `:balance_q` with an added presence guard. `decompose_dlmp` gains `reactive = extract_reactive_dlmp(ctx)` on both return branches (full matrix / per-bus). File header comment block and `decompose_dlmp`'s docstring extended to document the new 5th component; `extract_reactive_dlmp` added to the `export` statement.
- `test/test_pricing_dlmp.jl` — New `@testitem` ("dlmp: reactive price is degenerate at the root and finite/economically-consistent at a load bus on a lossy 2-bus (REACT-02)") pinning the root-degeneracy, load-bus-finiteness, and finite-difference economic-consistency behaviors on the lossy 2-bus fixture. The existing IEEE-13 "four components SUM" item gained a parallel, non-summed `d.reactive` finiteness check.

## Decisions Made

- **`reactive` is documented as a SEPARATE price signal, never summed into `total`:** the existing 4-term active sum-to-nodal-price assertion (a correctness NET per RESEARCH Pitfall 2 / threat T-05-02) is untouched — verified by inspection (no line changed a 4-term expression to 5-term) and by the dlmp-filtered suite staying green.
- **`extract_reactive_dlmp` carries its own `:balance_q` presence guard; `decompose_dlmp` does not need a duplicate one** — `decompose_dlmp` already hard-requires the `ConvexBranchFlow`-only `:cone`/`:vdrop`/`:cpydrop`/`:smax` handles, so any ctx that reaches the `reactive = extract_reactive_dlmp(ctx)` call site is by construction a `ConvexBranchFlow` solve and therefore always carries `:balance_q`. The guard exists solely for `extract_reactive_dlmp`'s standalone/direct callers (e.g. a hand-built DC-only ctx).
- **The finite-difference sanity pin sums over the horizon, not per-hour** — empirically confirmed (via a throwaway probe script, not committed) that comparing `d.reactive[2,t]*(q1[t]-q0[t])` against the FULL welfare objective delta per-t under-predicts by roughly the horizon length (T=3), since a uniform power-factor perturbation shifts every hour's reactive demand identically while `solve_welfare`'s returned objective aggregates all `T` hours. Summing the predicted per-hour contributions before comparing to the single scalar `Δobjective` matches to within `rtol=5e-2` at `δ=1e-4` (first-order finite-difference error, consistent with the chosen step size).

## Deviations from Plan

None — plan executed exactly as written. The only investigative step beyond the plan's literal task text was a throwaway Julia probe script (not committed, deleted after use) run to empirically confirm the finite-difference comparison's correct aggregation form (sum-over-horizon vs. per-hour) and the reactive price's numeric sign/magnitude before committing the hard-coded test assertion — this is exploratory verification work, not a code or behavior change, and required no deviation-rule justification.

## Issues Encountered

- **First full-suite verification attempt hit a 590-second shell-level `timeout` wrapper** before Julia's `Pkg.test()` (which takes ~17 min on this machine) could finish, silently truncating the log with no visible "Test Summary" line (the wrapper's `echo EXIT:$?` printed `EXIT:124` to a separate output stream, not the log file itself — easy to miss). Re-ran fully backgrounded with no artificial timeout cap (mirroring Plan 16-02's own resolution of the identical issue); the second run completed cleanly: **2337 passed, 3 broken (pre-existing, unrelated markers), 0 failed**.
- A pre-existing, unrelated `DrWatson`/`git diff HEAD` `ProcessFailedException` warning (exit code 129) appears repeatedly in the full-suite log during ADMM sweep tests, caused by the worktree's `--git-dir`/`--work-tree` layout confusing DrWatson's commit-tagging helper. This is an ambient environment warning, not a test failure (all affected tests still pass), and is out of scope for this plan (not caused by, and unrelated to, `src/pricing/dlmp.jl`/`test/test_pricing_dlmp.jl`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- REACT-02 is fully implemented: `extract_reactive_dlmp` is exported and `decompose_dlmp(ctx).reactive` is a documented, citable, hand-verified reactive nodal price.
- `src/experiments/Scenario.jl` was not touched, preserving the phase-wide DrWatson golden-hash non-perturbation constraint.
- Plan 16-04 (per phase's own plan sequencing) can now build on a fully-priced reactive channel across both the centralized `solve_welfare` and (per Plan 16-02) the certified ADMM `:balance_q` dual.
- No blockers.

---
*Phase: 16-reactive-power-consensus*
*Completed: 2026-07-26*
