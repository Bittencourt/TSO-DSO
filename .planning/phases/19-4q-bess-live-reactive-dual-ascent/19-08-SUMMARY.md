---
phase: 19-4q-bess-live-reactive-dual-ascent
plan: 08
subsystem: testing
tags: [julia, jump, clarabel, admm, testitems, testitemrunner, socp, fourquadbess]

# Dependency graph
requires:
  - phase: 19-4q-bess-live-reactive-dual-ascent (waves 1-5, plans 19-01..19-07)
    provides: >
      ReactiveMode enum + normalize_reactive_mode; FourQuadBESS device + q_inject
      AbstractDevice contract; Aggregator q_inject roll-up; DsoOpt/AgrOpt LIVE reactive
      coupling blocks (qag_live, μ_j/d_j/ρ_q, set_rho_q!); solve_admm's 3-state
      reactive_consensus (:off/:certified/:live) with joint (λ,μ) two-block dual ascent,
      stable μ/q_devices return keys.
provides:
  - "Phase19Fixtures @testmodule: a FourQuadBESS-bearing 2-bus aggregator variant of the
    Phase6Fixtures fixture, plus a test-only centralized_welfare_4q workaround for the
    FourQuadBESS/ConvexBranchFlow :cone JuMP-object-dictionary collision"
  - "Measured (not assumed) welfare/λ/μ cross-validation tolerances for :live mode, each
    independently derived from a 5-seed sweep"
  - "3 new :live @testitems in test_admm_reactive.jl: convergence, cross-validation, and a
    genuine liveness (not-a-no-op) regression"
  - "1 quarantined IEEE-13 4Q-BESS supporting-evidence @testitem in test_ieee123_admm.jl,
    explicitly NOT part of the CI-gated primary evidence set"
  - "Final full-suite reconciliation: 2503 passed / 0 failed / 0 errored / 3 broken
    (unchanged pre-existing broken count) -- MESH-04/MESH-05 acceptance gate closed"
affects: [phase-20-overvoltage-relaxation, phase-23-meshed-networks]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JuMP.unregister(model, :cone) as a test-file-scope-safe workaround for a JuMP
      object-dictionary name collision between two independently-authored contribute!
      methods sharing one Model, without touching either src/ file"
    - "Relative @testmodule-to-@testmodule reference (`using ..OtherModule`) verified
      directly against TestItemRunner.jl's ensure_evaled/run_testitem source: every
      @testmodule is eval'd as a sibling child of ONE shared parent setup-module, so a
      LATER-listed setup module can `using ..EarlierModule` once TestItemRunner has
      already ensure_evaled it (order in the consuming testitem's `setup=[...]` array is
      load-bearing)"
    - "Measurement-before-golden tolerance calibration: run the centralized/ADMM pair
      across several seeds BEFORE picking a cross-validation atol/rtol, and use an
      ABSOLUTE tolerance (never relative) when the quantity itself is expected to be ≈0"

key-files:
  created:
    - test/fixtures_phase19.jl
  modified:
    - test/test_admm_reactive.jl
    - test/test_ieee123_admm.jl

key-decisions:
  - "Reused Phase6Fixtures.two_bus_feeder() (near-lossless, r=x=1e-3) exactly as the plan
    requires, rather than a differently-tuned feeder -- this makes μ genuinely degenerate
    (≈1e-8) on this fixture, confirmed empirically, and the tolerance/liveness design was
    built around that honest finding instead of hiding it."
  - "FourQuadBESS device scale (Pch_max=Pdch_max=0.02, Smax=0.03) chosen to match the
    fixture's OWN inelastic-demand magnitude (LOAD_SCALE_2BUS=0.02), not PVBattery's larger
    Pmax=0.1 -- a 10x-larger candidate tripped the D-08 honest grid-charging/negative-price
    boundary certificate (assert_4q_complementarity!) rather than staying interior."
  - "Liveness proof (Task 2, item 3) is driven by a DIFFERENT SEED (not a Smax perturbation)
    -- empirically, varying Smax alone left q_devices bit-for-bit unchanged (the device
    wasn't cone-bound either way, and μ≈0 gives no price incentive to move), while a
    different seed's demand/PV draw genuinely shifts the qag_live PINNING target and
    produces a ~0.016 trajectory difference vs. an exact 0.0 for matching seeds."
  - "IEEE-13 4Q-BESS item added to test_ieee123_admm.jl per the plan's files_modified scope,
    even though the retry-wrapping PATTERN it mirrors actually lives in test_admm.jl (the
    plan's own read_first citation of 'existing setup=[..., AdmmRetryFixtures] usage in
    this file' does not match this file's pre-existing content -- treated as a citation
    inaccuracy, not a scope license to touch test_admm.jl)."

patterns-established:
  - "Pattern: test-only workaround for a src/-level JuMP naming collision via
    JuMP.unregister, documented in the fixture file's own header, rather than editing the
    two colliding src/ files out of a plan's declared scope."

requirements-completed: [MESH-04, MESH-05]

# Metrics
duration: ~105min
completed: 2026-08-08
---

# Phase 19 Plan 08: 4Q-BESS + Live Reactive Dual-Ascent Acceptance Gate Summary

**Closed MESH-04/MESH-05 with a measured (not assumed) :live cross-validation gate on a
FourQuadBESS-bearing 2-bus fixture, a genuine liveness regression proving the reactive
dual-ascent mechanism reacts to its input, a quarantined IEEE-13 supporting-evidence item, and
a final 2503-passed/0-failed/3-broken full-suite reconciliation.**

## Performance

- **Duration:** ~105 min (includes two full-suite runs, ~12 min each)
- **Tasks:** 3/3 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- `Phase19Fixtures` (`test/fixtures_phase19.jl`): a FourQuadBESS-bearing 2-bus aggregator
  variant of `Phase6Fixtures.build_two_bus_aggregators`, plus `centralized_welfare_4q` — a
  test-only replica of `solve_welfare` that works around the FourQuadBESS/ConvexBranchFlow
  `:cone` JuMP object-dictionary collision (deferred-items.md) via `JuMP.unregister`, with zero
  `src/` changes.
- Welfare/λ/μ cross-validation tolerances MEASURED across a 5-seed sweep before being pinned
  (D-14): welfare atol=1e-4 (max observed 2.368e-5), λ atol=5e-5 (max 1.519e-5), μ atol=1e-7
  (max 1.610e-8 — μ is genuinely degenerate ≈0 on this near-lossless fixture, D-03, confirmed
  empirically rather than merely cited).
- 3 new `:live` `@testitem`s in `test_admm_reactive.jl`: convergence (no maxiter throw),
  cross-validation (welfare/λ/μ each against its own measured tolerance), and a liveness
  regression proving two runs differing only by seed converge to genuinely different
  (μ, q_devices) — sanity-checked this session by temporarily matching the seeds and confirming
  the assertion correctly fails (reverted before commit).
- 1 quarantined `@testitem` in `test_ieee123_admm.jl`: an IEEE-13 aggregator set with one
  FourQuadBESS added additively, `solve_admm(...; reactive_consensus = :live)` wrapped in the
  existing `AdmmRetryFixtures.retry_flaky_admm_solve` bounded-retry quarantine — explicitly
  documented as supporting evidence only, never part of the primary CI-gated evidence set.
- Final full-suite run: **2503 passed / 0 failed / 0 errored / 3 broken** (2506 total). Zero
  pre-existing regression; the 3 broken items are the project's own pre-existing `@test_broken`
  markers, unchanged.

## Task Commits

1. **Task 1: Phase19Fixtures + measurement-before-golden tolerance calibration** — `6ab41db` (test)
2. **Task 2: `:live` convergence + cross-validation + liveness regression** — `dc6876b` (test)
3. **Task 3: IEEE-13 quarantined supporting evidence + final byte-identity gate** — `1757dae` (test)

**Auto-fix (Rule 1/3):** `2a2fb77` (fix) — dropped an undeclared `LinearAlgebra` dependency
from Task 2's liveness item, found by the mandatory full-suite run (see Deviations below).

**Plan metadata:** this SUMMARY.md's own commit (below).

## Files Created/Modified

- `test/fixtures_phase19.jl` — `Phase19Fixtures` `@testmodule`: `build_two_bus_aggregators_4q`
  (2-bus + FourQuadBESS aggregator) and `centralized_welfare_4q` (test-only `solve_welfare`
  replica with the `:cone`-collision workaround), plus the measured 5-seed tolerance table in
  the file header.
- `test/test_admm_reactive.jl` — 3 new `:live` `@testitem`s appended after the 3 pre-existing
  OFF/CERTIFIED items (all re-verified passing unmodified).
- `test/test_ieee123_admm.jl` — 1 new quarantined IEEE-13 4Q-BESS `@testitem` appended after
  the 2 pre-existing IEEE-123 items (both re-verified passing unmodified).

## Decisions Made

See `key-decisions` in the frontmatter above for the full rationale on: (1) reusing the
near-lossless 2-bus feeder as-is rather than re-tuning it to force a non-degenerate μ; (2) the
FourQuadBESS device-scale calibration that avoids the D-08 grid-charging boundary; (3) using a
SEED perturbation (not Smax) for the liveness proof, based on empirical measurement that Smax
alone produced no observable difference; (4) placing the IEEE-13 item in
`test_ieee123_admm.jl` per the plan's `files_modified` scope despite the plan's `read_first`
citation of the retry pattern actually living in `test_admm.jl`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dropped an undeclared `LinearAlgebra` test dependency**
- **Found during:** Task 3's mandatory full-suite run (first `Pkg.test()` pass)
- **Issue:** Task 2's liveness `@testitem` used `using LinearAlgebra: norm`. This resolved
  fine under an ad-hoc `julia --project=.` script (where `LinearAlgebra` loads as an
  auto-available stdlib) but threw `Package LinearAlgebra not found in current path` inside
  `Pkg.test()`'s isolated per-testitem temp environment, since no file in this project declares
  or uses `LinearAlgebra` (grep-verified) and it is absent from `test/Project.toml`'s `[deps]`.
  This produced exactly 1 errored test in the first full-suite run (2501 passed / 0 failed /
  1 errored / 3 broken).
- **Fix:** Replaced the import with a 3-line Base-only `norm(x) = sqrt(sum(abs2, x))` helper
  local to the testitem — no new test dependency needed for one function.
- **Files modified:** `test/test_admm_reactive.jl`
- **Verification:** Re-ran the full suite; the item now shows 2 passes (was 1 error). Final
  clean run: 2503 passed / 0 failed / 0 errored / 3 broken.
- **Commit:** `2a2fb77`

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug, caught by the plan's own mandatory
full-suite verification step).
**Impact on plan:** Necessary for correctness; no scope creep — the fix stayed entirely within
`test/test_admm_reactive.jl`, the file this task already owned.

## Issues Encountered

- **Literal plan `<verify>` commands don't resolve under `--project=.`** (orchestrator-flagged,
  known trap): every new `@testitem` was instead validated via a manual TestItemRunner-mechanics
  harness written this session, mirroring `TestItemRunner.jl`'s actual `ensure_evaled`/
  `run_testitem` source (read directly from `~/.julia/packages/TestItemRunner/GnoVt/src/`) —
  parsing each `@testmodule`/`@testitem` body's AST and evaluating it in a sandbox module with
  the correct relative `using` wiring, exactly matching the real mechanism. This is HOW the
  `LinearAlgebra` gap in Task 2's item was NOT caught until the real `Pkg.test()` run (the
  harness ran under `--project=.`, where the stdlib is auto-available) — the mandatory
  full-suite step in Task 3 is what actually caught it, confirming why that step is
  load-bearing and not skippable.
- **FourQuadBESS/ConvexBranchFlow `:cone` collision (deferred-items.md, plan 19-07's finding):**
  confirmed live this session (`"An object of name cone is already attached to this model"`).
  Worked around entirely within `test/fixtures_phase19.jl` via `JuMP.unregister(model, :cone)`
  — JuMP's own suggested fix for this exact error — between the network's and the aggregators'
  `contribute!` calls in a hand-written `centralized_welfare_4q` replica of `solve_welfare`. No
  `src/` file was touched; the deferred item's suggested permanent fix (renaming one of the two
  `:cone` registrations in `FourQuadBESS.jl`/`ConvexBranchFlow.jl`) remains open for a future
  plan that needs `solve_welfare` itself (not a replica) to accept a `FourQuadBESS`.
- **Device-scale tuning required two rounds:** a first FourQuadBESS parameter set mirroring
  `PVBattery`'s own `Pmax=0.1` scale tripped `assert_4q_complementarity!`'s D-08 honest
  grid-charging/negative-price boundary at t=1 on the 2-bus fixture (the battery was large
  enough, relative to the fixture's tiny inelastic demand, to occasionally flip the bus into a
  net-exporter at a negative effective price). Rescaling to match `LOAD_SCALE_2BUS`'s own
  magnitude (0.02) resolved it cleanly across a 5-seed sweep.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- MESH-04 and MESH-05 are both fully evidenced on the primary small-radial fixture; IEEE-13
  support runs quarantined and non-gating; the phase's byte-identity default-path guarantee
  (ROADMAP success criterion 4) is proven via the final 2503/0/0/3 reconciliation, not merely
  asserted.
- This is the last plan of Phase 19 — no blockers for the orchestrator to close out the phase.
- **Carried-forward, still-open item:** the FourQuadBESS/ConvexBranchFlow `:cone` name
  collision (deferred-items.md) remains unfixed in `src/` — only worked around in test code.
  Any FUTURE plan that needs the CENTRALIZED `solve_welfare` (not a test-only replica) to accept
  a `FourQuadBESS`-bearing aggregator directly will hit this and should apply the deferred
  item's suggested fix (rename one of the two `:cone` registrations) at that time.

## Self-Check: PASSED

- `test/fixtures_phase19.jl` — FOUND
- `test/test_admm_reactive.jl` — FOUND (modified)
- `test/test_ieee123_admm.jl` — FOUND (modified)
- Commit `6ab41db` — FOUND
- Commit `dc6876b` — FOUND
- Commit `1757dae` — FOUND
- Commit `2a2fb77` — FOUND

---
*Phase: 19-4q-bess-live-reactive-dual-ascent*
*Completed: 2026-08-08*
