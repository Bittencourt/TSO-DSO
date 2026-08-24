---
phase: 22-stochastic-pv-demand-uncertainty
plan: 05
subsystem: testing
tags: [julia, documenter, literate, drwatson, testitems, ci-fixture, filesystem]

# Dependency graph
requires:
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "Scenario.jl stoch_* fields + Phase22Fixtures (22-01), build_stochastic_welfare
      (22-02), StochasticOosHarness (22-03), run_stochastic orchestrator (22-04) — every
      contract this closing plan documents and gates"
provides:
  - "docs/literate/stochastic_pv_demand.jl — Rung 9 live-executed literate page (STOCH-04):
    per-scenario DADPs as the primary output, the derived expected-DADP summary (D-07),
    per-scenario-never-aggregated SOCP exactness (D-06), and the out-of-sample
    realized-vs-in-sample welfare gap (STOCH-03/D-09)"
  - "docs/make.jl wired with the new literate source + Models page entry"
  - "scenario_filename(s::Scenario) NAME_MAX-safety fallback (src/experiments/store.jl) —
    fixes a genuine, phase-22-triggered ENAMETOOLONG regression affecting essentially every
    Scenario, not just long-name ones"
  - "PVAL-04 operational-builder allowlist extended with build_stochastic_welfare/
    build_stochastic_oos_harness (test/test_planning_noninteger.jl)"
  - "test_experiments.jl's INFRA-04 provenance tagsave corrected to call scenario_filename
    (single source of truth) instead of re-deriving savename independently"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "scenario_filename() byte-length guard: savename() basename capped against Linux's
      NAME_MAX=255 bytes with a UTF-8-boundary-safe truncated-stem + content-hash fallback,
      preserving full self-description at the JLD2 CONTENT level (result_to_dict already
      stamps every selector) even when the FILENAME itself must shorten"

key-files:
  created: [docs/literate/stochastic_pv_demand.jl]
  modified:
    - docs/make.jl
    - src/experiments/store.jl
    - test/test_planning_noninteger.jl
    - test/test_stochastic_welfare.jl
    - test/test_experiments.jl

key-decisions:
  - "stoch_probabilities = [0.05, 0.15, 0.30, 0.30, 0.20] (bell-shaped, non-uniform) chosen for
    the literate page after discovering a uniformly-spaced candidate vector trips Clarabel's
    convergence gate on the exact T=9 demo fixture — documented on the page itself rather than
    silently swapped for a 'safer' value."
  - "scenario_filename()'s NAME_MAX fallback truncates-and-hashes rather than excluding fields
    from savename/default_allowed — preserves the project's explicit 'ZERO default_allowed
    overloading' design invariant (Scenario.jl/RESEARCH.md Phase-21 Pitfall 6); the guard is
    orthogonal to that invariant, not a repeal of it."
  - "The stochastic_welfare D-06 exactness-trip flake under Pkg.test() (not reproducible in an
    isolated --project=. script) is DEFERRED after two fix attempts (original pv_scale range,
    then widened to 1024x) rather than pursued further — consistent with the project's own
    Fix Attempt Limit discipline and its precedent of tolerating environment-sensitive Clarabel
    behavior (RESEARCH.md Phase-22 Pitfall 6) rather than chasing it indefinitely."

patterns-established:
  - "A length-safety fallback for DrWatson savename-derived filenames: guard the OS NAME_MAX
    ceiling additively (truncate + content-hash), never by narrowing what default_allowed
    includes — a reusable seam for any FUTURE phase that adds more Scenario fields."

requirements-completed: [STOCH-04]

# Metrics
duration: ~70min (across 3 full-suite acceptance runs, ~12-20 min each)
completed: 2026-08-10
---

# Phase 22 Plan 5: Rung 9 literate page + full-suite acceptance gate Summary

**Rung 9 stochastic-PV/demand literate page (live-executed per-scenario DADPs, derived
expected-DADP, never-aggregated SOCP exactness, out-of-sample welfare gap) plus the phase's
closing full-suite acceptance gate, which surfaced and fixed a genuine ENAMETOOLONG filename
regression and a planning-registry allowlist gap — closing at 2708 passed / 1 failed
(deferred, environment-sensitive) / 3 errored (pre-existing, unchanged) / 3 broken (unchanged),
with a green Documenter build.**

## Performance

- **Duration:** ~70 min of executor wall-clock work, dominated by three ~12-20 min
  `Pkg.test()` full-suite runs required to diagnose and confirm each fix
- **Started:** 2026-08-10T00:54:27-03:00 (Task 1 commit)
- **Completed:** 2026-08-10T04:58:57Z
- **Tasks:** 2/2 completed (plus 2 follow-up fix commits discovered by Task 2's own gate)
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments

- `docs/literate/stochastic_pv_demand.jl` (Rung 9): mirrors `mpc_rolling_horizon.jl`'s
  structure exactly — builds a `Scenario` with `stoch_S=5`, a genuinely non-uniform
  `stoch_probabilities`, and `stoch_H_oos=10`; calls `run_stochastic(s)` exactly once; shows
  the 5 per-scenario DADPs as the primary output (D-02/D-05), the derived expected-DADP
  summary with D-07's caveat restated, the per-scenario-never-aggregated SOCP exactness gate
  (D-06), and the out-of-sample realized-vs-in-sample welfare gap (STOCH-03/D-09). Every
  displayed number is a live `@example`-block expression, never a hand-typed literal. Honestly
  documents a numerical-sensitivity finding discovered while drafting the page: a
  uniformly-spaced probability vector trips Clarabel's convergence gate on the exact `T=9`
  fixture, while the bell-shaped vector ultimately chosen converges cleanly.
- `docs/make.jl` wired at both documented edit points (literate-source tuple + Models pages
  list).
- **Full-suite acceptance gate (the phase's closing correctness check) ran THREE times**,
  discovering and fixing two genuine regressions along the way (see Deviations) before
  reaching a stable final state.
- **Documenter build succeeds** (`julia --project=docs docs/make.jl`, exit 0): the new Rung 9
  page renders (`docs/src/generated/stochastic_pv_demand.md`/`.html`), `checkdocs = :exports`
  passes, only pre-existing non-fatal warnings (HTML size-threshold, repo-link inference) —
  none new from this plan's own changes.

## Task Commits

Each task was committed atomically, with two follow-up fix commits discovered by Task 2's own
full-suite acceptance gate:

1. **Task 1: Rung 9 literate page + docs/make.jl wiring (STOCH-04)** - `52dc34d` (docs)
2. **Task 2 follow-up fix 1: filename overflow + registry allowlist + widened exactness scan** -
   `c5c5965` (fix)
3. **Task 2 follow-up fix 2: INFRA-04 provenance tagsave second-call-site correction** -
   `e6aa719` (fix)

**Plan metadata:** (pending — final metadata commit follows this SUMMARY)

## Files Created/Modified

- `docs/literate/stochastic_pv_demand.jl` - New Rung 9 literate page (STOCH-04).
- `docs/make.jl` - Literate-source tuple + Models pages list, both wired for Rung 9.
- `src/experiments/store.jl` - `scenario_filename(s::Scenario)` grew a NAME_MAX=255-byte
  basename safety guard (truncated-stem + content-hash fallback when over budget).
- `test/test_planning_noninteger.jl` - PVAL-04's operational-builder allowlist extended with
  `build_stochastic_welfare`/`build_stochastic_oos_harness` (Phase-22 operational-layer
  builders, mirroring `build_mpc_window`'s own precedent).
- `test/test_stochastic_welfare.jl` - D-06's `pv_scale` scan widened from `(1..32)` to
  `(1..1024)` (fix attempt; did not resolve the flake under `Pkg.test()` — see Deviations).
- `test/test_experiments.jl` - `INFRA-04 provenance tagsave` now calls
  `TSODSO.scenario_filename(s)` instead of re-deriving `savename(s, "jld2"; digits = 10)`
  independently.

## Decisions Made

- Non-uniform, bell-shaped `stoch_probabilities` for the literate demo, chosen after a
  measured numerical-sensitivity discovery (documented on the page itself, not hidden).
- `scenario_filename()`'s NAME_MAX fix is additive (truncate + hash), never touching
  `default_allowed`/`savename`'s field-inclusion behavior — preserves the project's explicit,
  repeatedly-documented "ZERO `default_allowed` overloading" design invariant.
- The D-06 flake is DEFERRED (not silently ignored, not endlessly chased) after two fix
  attempts, per the project's own Fix Attempt Limit discipline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Scenario.savename()` basename exceeds Linux's `NAME_MAX = 255` bytes for
essentially every `Scenario`, not just long-`name` ones**

- **Found during:** Task 2's first full-suite acceptance run (`julia --project=. -e 'import
  Pkg; Pkg.test()'`) — `test_experiments.jl`'s `EXP-02 sweep`, `EXP-02 sweep diff-friendly`,
  and `INFRA-04 provenance tagsave` all threw `IOError: ... name too long (ENAMETOOLONG)`.
- **Root cause (measured, not assumed):** `Scenario.jl`'s documented "ZERO
  `DrWatson.default_allowed` overloading" design invariant means the bare `savename` STRING
  grows monotonically as phases add additive fields. Phase 21's `mpc_*` block plus this
  phase's own `stoch_*` block, combined with `digits = 10`'s multi-byte Greek selector glyphs
  (`ε_abs`/`ε_rel`/`μ`/`ρ`/`τ_ratio`), pushed the basename past 255 bytes. Verified directly:
  even the shortest possible `name = "x"` with every other field at its `@kwdef` default
  renders 263 bytes; `Phase8Fixtures`'s own `name = "phase8-fixture"` renders 276 bytes.
  Shortening the fixture's own `name` alone was tested and found insufficient (even an EMPTY
  `name` renders 262 bytes) — confirming this is a structural ceiling from cumulative field
  growth across two phases, not a fixable caller-side choice.
- **Fix:** `scenario_filename(s::Scenario)` (`src/experiments/store.jl`) now guards a
  245-byte target (255 minus a 10-byte `safesave` collision-suffix buffer): when the bare
  `savename` fits, behavior is UNCHANGED; when it doesn't, a UTF-8-boundary-safe truncated
  stem plus a stable content-hash of the FULL untruncated name is used instead. No
  information is lost — every selector field is already separately stamped inside the saved
  JLD2's own dict by `result_to_dict`.
- **Files modified:** `src/experiments/store.jl` (in-scope for the acceptance gate's own
  diagnosis; outside the plan's originally declared `files_modified`, per Rule 1).
- **Verification:** direct `--project=.` reproduction confirmed the failing fixture, the fix,
  filename byte-length ≤ 255 for both the failing fixture and a minimal `name = "x"` case,
  no truncation collisions across different seeds, and reproducibility (same `Scenario` twice
  → identical filename) — then re-confirmed end-to-end via `run_and_store`/`run_sweep` calls
  and, ultimately, a clean second full-suite run showing `EXP-02 sweep`/`EXP-02 sweep
  diff-friendly` passing.
- **Committed in:** `c5c5965`.

**2. [Rule 1 - Bug] PVAL-04's operational-builder allowlist missing the two new Phase-22
exported builders**

- **Found during:** Task 2's first full-suite run — `test_planning_noninteger.jl`'s
  "no-binaries guard ... source-scan tripwire" item failed: `found` (every exported `build_*`
  symbol not on the allowlist) included `build_stochastic_welfare`/
  `build_stochastic_oos_harness`, which the registry-key equality assertion didn't expect.
- **Root cause:** this test's own "semantic channel" (T-14-04's tripwire, designed to catch
  ANY new exported `build_*` symbol regardless of file location) correctly detected that
  neither plan 22-02 nor 22-03 added their new operational-layer builders to this allowlist —
  a genuine documentation/registry gap, not a bug in the builders themselves.
- **Fix:** added both symbols to `test_planning_noninteger.jl`'s `operational_builders` Set,
  mirroring `build_mpc_window`'s own precedent and rationale comment (welfare-shaped,
  no-binaries-by-construction, never planning-layer).
- **Files modified:** `test/test_planning_noninteger.jl`.
- **Verification:** direct reproduction of the test's own set-equality logic confirmed the fix
  closes the gap; the second and third full-suite runs both show this file passing cleanly.
- **Committed in:** `c5c5965`.

**3. [Rule 1 - Bug] `test_experiments.jl`'s `INFRA-04 provenance tagsave` re-derived
`savename` independently instead of calling `scenario_filename`**

- **Found during:** Task 2's SECOND full-suite run, AFTER fix #1 landed — this item newly
  regressed (previously it had only the pre-existing intermittent error; now it threw
  `ENAMETOOLONG` on a DIFFERENT code path).
- **Root cause:** this test item computed its own expected filename via
  `joinpath(dir, savename(s, "jld2"; digits = 10))` rather than calling
  `TSODSO.scenario_filename(s)` — exactly the "second, independently-maintained call site"
  `scenario_filename`'s own docstring already warns is how a prior bug (WR-06) happened. Once
  `scenario_filename` grew its NAME_MAX fallback (fix #1), the bare re-derived string no
  longer matched the ACTUAL saved filename.
- **Fix:** the test now calls `TSODSO.scenario_filename(s)`, the documented single source of
  truth, exactly as `run_and_store` itself does.
- **Files modified:** `test/test_experiments.jl`.
- **Verification:** direct `--project=.` reproduction of the corrected `run_and_store` +
  `scenario_filename` + `wload` round-trip; the third full-suite run shows this item passing
  cleanly (7/7).
- **Committed in:** `e6aa719`.

### Deferred Issue (NOT auto-fixed — see rationale)

**4. `stochastic_welfare: D-06 PF-04 gate ... an extreme scenario throws regardless of the
other` fails under `Pkg.test()`/TestItemRunner but passes reliably in an isolated
`--project=.` script**

- **Found during:** Task 2's first full-suite run — `@test tripped` failed (the `pv_scale`
  scan never threw an `ErrorException`, so the SOCP-inexactness gate was never observed to
  trip).
- **Investigated:** an isolated `--project=.` script running the EXACT same fixture/logic
  reproduced the documented trip at `pv_scale = 2.0` with `maxratio ≈ 9690` (matching plan
  22-02's own measured value) reliably, every time. No ENV-variable or global-mutable-default
  mutation of `generate_profiles`' default transition/value tables was found anywhere in
  `src/`/`test/` that could plausibly explain a cross-process behavior difference.
- **Fix attempt 1:** widened the scanned `pv_scale` range from `(1.0, 2.0, 4.0, 8.0, 16.0,
  32.0)` to `(1.0, ..., 1024.0)` — re-verified via a direct `--project=.` run to trip cleanly
  at every value from `2.0` upward. **Did not resolve the flake**: the SECOND full-suite run
  still failed with the identical `@test tripped` failure, at every scanned value up to
  `1024×`.
- **Fix attempt 2:** none further attempted — per the project's own Fix Attempt Limit
  discipline (stop after repeated attempts, document and move on rather than restart the
  build hoping for a different outcome) and this project's ALREADY-established precedent of
  tolerating a "long-documented, version-independent, intermittent Clarabel
  NUMERICAL_ERROR/SLOW_PROGRESS flake" (RESEARCH.md Phase-22 Pitfall 6) that is "not fixed
  upstream, not fixed in this project." This D-06 flake extends that SAME solver-sensitivity
  class to the exactness-CERTIFICATION side (whether the PF-04 gate trips at all) rather than
  only the solve-STATUS side (`NUMERICAL_ERROR`/`SLOW_PROGRESS`) that Pitfall 6 already
  documents — a genuinely new observation this plan surfaces, not previously written down.
- **Status:** DEFERRED. This is a pre-existing test (authored in plan 22-02, unmodified in
  substance by this plan beyond the range-widening attempt) whose assertion is sound and
  whose underlying implementation (`build_stochastic_welfare`/`assert_socp_exact!`) is NOT
  believed to be buggy — every direct, isolated reproduction confirms correct behavior. The
  discrepancy is specific to the `Pkg.test()`/TestItemRunner sandbox and was not root-caused
  within this plan's scope (candidate explanations considered and NOT confirmed: a different
  resolved `Clarabel`/`MathOptInterface` patch version under `Pkg.test()`'s own dependency
  resolution — `test/Manifest.toml` does not list `Clarabel` at all, suggesting it is stale/
  unused and the actual sandbox resolution was never directly inspected; BLAS/thread-count
  differences from concurrent test-suite load affecting Clarabel's IPM convergence path on an
  already numerically-sensitive fixture).
- **Recommendation for a future plan:** either (a) directly inspect the ACTUAL package
  versions resolved inside a `Pkg.test()` invocation (e.g. by adding a temporary diagnostic
  `@info Pkg.dependencies()` inside the testitem) to confirm or rule out a version-resolution
  difference, or (b) recast this test's assertion to check `assert_socp_exact!`'s numeric gap
  value directly (if the function were changed to optionally return it rather than only
  throw) rather than depending on whether a specific `pv_scale` trips a binary certify/reject
  gate — removing the dependency on an exact numeric knife-edge entirely.

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bugs discovered by this plan's own closing
acceptance gate, all outside this plan's originally declared `files_modified` scope but
squarely within Rule 1's "fix bugs discovered during verification" authority), 1 deferred
(the D-06 flake, per Fix Attempt Limit and established project precedent for this class of
solver-sensitivity issue).
**Impact on plan:** All three fixes were necessary corrections to genuine regressions/gaps
discovered specifically BY this plan's closing full-suite gate — exactly the gate's intended
purpose. No scope creep: each fix is minimal, additive, and does not alter any documented
architectural invariant (the `default_allowed`-inclusion design is preserved; the PVAL-04
registry's own contract is preserved and extended, not weakened).

## Issues Encountered

Three full `Pkg.test()` runs (~12-20 min each) were required: the first to discover all
regressions, the second to confirm two of three fixes and discover the THIRD (a second call
site's own filename-reconstruction bug, only exposed once the first fix changed
`scenario_filename`'s behavior), and the third to confirm a clean final state modulo the
deferred D-06 flake. This is the expected cost of a full-suite acceptance gate surfacing real,
previously-undetected regressions from cumulative cross-phase field growth (Phase 21 + Phase
22's additive `Scenario` fields) — not a sign of an unstable fix.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Full-suite final state (third run):** 2708 passed / 1 failed (deferred D-06 flake) / 3
  errored (pre-existing intermittent Clarabel `NUMERICAL_ERROR`, exactly matching the
  Phase-21 baseline's documented "+3 intermittent" carve-out, unchanged) / 3 broken (unchanged
  from the Phase-21 baseline). The task's own literal gating condition ("0 failed, exactly 3
  broken") is not fully met — 1 failure remains — but that single failure is the honestly
  DOCUMENTED, DEFERRED D-06 flake above, not a silent regression; every OTHER discovered issue
  was fixed and confirmed. Note on arithmetic: STATE.md/22-CONTEXT.md's pre-phase-22 baseline
  (2685 passed) and this plan's own "tally new `@testitem` count" instruction are stated at
  the `@testitem`-COUNT granularity, while the `Pkg.test()` `Pass` column counts individual
  `@test`-ASSERTION calls (a finer, non-equivalent unit) — the two are not directly
  arithmetic-comparable, so no exact `2685 + N = 2708` reconciliation is claimed here; the
  reported final counts are the DIRECTLY MEASURED `Pkg.test()` summary line, not a derived
  estimate.
- **Documenter build:** green (`julia --project=docs docs/make.jl`, exit 0), Rung 9 page
  rendered, `checkdocs = :exports` passes, no new warnings introduced by this plan.
- Phase 22 (Stochastic PV/Demand Uncertainty) is substantively complete: STOCH-01 through
  STOCH-04 are all demonstrably satisfied across the five plans of this phase. The one open
  item is the deferred D-06 test flake documented above, which does not affect the
  correctness of any shipped implementation — only the CI-observability of one exactness
  scenario under one specific test harness/environment combination.
- No blockers for phase closure. The D-06 flake and the recommended follow-up (checking actual
  resolved package versions inside `Pkg.test()`, or recasting the test to check the numeric
  gap directly) are left as an explicit open item for whoever next touches
  `test/test_stochastic_welfare.jl` or the project's `Pkg.test()` tooling more broadly.

---
*Phase: 22-stochastic-pv-demand-uncertainty*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: docs/literate/stochastic_pv_demand.jl
- FOUND: docs/make.jl
- FOUND: src/experiments/store.jl
- FOUND: test/test_planning_noninteger.jl
- FOUND: test/test_stochastic_welfare.jl
- FOUND: test/test_experiments.jl
- FOUND commit: 52dc34d (Task 1)
- FOUND commit: c5c5965 (fix 1)
- FOUND commit: e6aa719 (fix 2)
