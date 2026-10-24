---
phase: 39-parallel-ready-admm-gating-measurements
plan: 03
subsystem: experiments
tags: [provenance, drwatson, threads, blas, jld2, par-04, executor-blind]

# Dependency graph
requires:
  - phase: 39-01 (Clarabel concurrency spike)
    provides: measured threaded-executor context (julia -t 4, BLAS.set_num_threads(1)) that the new provenance keys will attribute saved runs against
provides:
  - "result_to_dict additive process-provenance keys d[:julia_threads] and d[:blas_threads], measured live at save time beside :julia_version"
  - "test-pinned PAR-04 executor-blindness: _scenario_identity record dict carries no executor keys; Scenario ==/hash/scenario_filename are scenario-pure"
  - "LinearAlgebra stdlib declared in root Project.toml (+ Manifest-v1.12) and test env — unblocks any future src/test use of BLAS (39-04's threaded executor pins it)"
affects: [39-04 threaded executor, 39-05 SCALE-06 attribution, phase verifier, any consumer of saved run JLD2s]

# Tech tracking
tech-stack:
  added: []
  patterns: ["process-provenance additive keys measured live at save time (Threads.nthreads()/BLAS.get_num_threads())", "executor-blind identity: executor state lands only AFTER the _scenario_identity call inside result_to_dict"]

key-files:
  created: []
  modified:
    - src/experiments/store.jl
    - test/test_experiments.jl
    - Project.toml
    - Manifest-v1.12.toml
    - test/Project.toml
    - test/Manifest.toml

key-decisions:
  - "julia_threads/blas_threads stored as process-level keys (never missing, every strategy) — they describe the PROCESS, not any executor choice, per D-10"
  - "LinearAlgebra declared as an explicit dependency (root + test env) after Julia 1.12 hard-errored on the undeclared stdlib use — matches the existing SparseArrays declaration convention"
  - "Qualified import style `using LinearAlgebra: BLAS` (not the whole namespace) in both store.jl and the testitem, keeping module namespaces tight"

patterns-established:
  - "Additive process-provenance keys: measured live at save time, positioned immediately after :julia_version in result_to_dict"
  - "Executor-blindness pinned by test: identity functions carry no executor/thread keys; two identically-constructed Scenarios are ==, hash-equal and filename-identical"

requirements-completed: [PAR-04]

# Metrics
duration: 37min
completed: 2026-10-24
---

# Phase 39 Plan 03: Parallel-Ready ADMM & Gating Measurements — Run Provenance Summary

**Run provenance records julia_threads/blas_threads as additive keys beside :julia_version in result_to_dict, measured live at save time, while Scenario identity stays executor-blind (PAR-04) — pinned by 9 new test assertions (targeted run 121/0/0).**

## Performance

- **Duration:** 37 min
- **Started:** 2026-10-24T04:02:08Z
- **Completed:** 2026-10-24T04:39Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- `result_to_dict` now stamps `d[:julia_threads] = Threads.nthreads()` and `d[:blas_threads] = BLAS.get_num_threads()` immediately after `d[:julia_version]` — process-level keys, present for every strategy, never `missing` (T-39-03-01 mitigation: live measurement, test asserts saved values equal live process values)
- The "experiments: provenance tagsave" testitem extended in place (no new expected_broken.txt entries): thread-key presence AND live values on the wload'd dict (String keys), plus executor-blind identity — `_scenario_identity(s; style = :record)` carries no `:julia_threads`/`:blas_threads`, and two identically-constructed `:admm` Scenarios are `==`, `hash`-equal and `scenario_filename`-identical (T-39-03-02 mitigation)
- `_scenario_identity`, `_strategy_knobs` and `scenario_filename` are textually untouched (verified against the pre-plan commit: no hunks inside those functions) — filenames and identity cannot move (golden policy)

## Task Commits

Each task was committed atomically:

1. **Task 1: julia_threads / blas_threads additive keys in result_to_dict** - `64fdd0e` (feat)
2. **Task 2: Extend the provenance testitem — key presence/values + executor-blind identity** - `4d753b1` (test)

## Files Created/Modified
- `src/experiments/store.jl` - `using LinearAlgebra: BLAS` import; the two additive provenance keys in `result_to_dict`; one additive docstring sentence (no JuliaFormatter `|`-continuation hazard)
- `test/test_experiments.jl` - provenance testitem: `using LinearAlgebra: BLAS`, 4 thread-key assertions, 5 executor-blind identity assertions
- `Project.toml` - `LinearAlgebra = "37e2e46d-..."` in [deps] + `LinearAlgebra = "1"` in [compat] (SparseArrays convention)
- `Manifest-v1.12.toml` - "LinearAlgebra" added to TSODSO's deps array (entry already present transitively; v1.10/v1.11 manifests carry no project entry, nothing to change)
- `test/Project.toml` - `LinearAlgebra` added as a direct test-env dep (the testitem module resolves against the test sandbox)
- `test/Manifest.toml` - project_hash refreshed by Pkg (transitive `[[deps.LinearAlgebra]]` entry already present)

## Decisions Made
- Thread counts stored as **process-level** keys (never `missing`, every strategy) rather than ADMM-specific — they describe which process configuration produced the run (D-10: measured live at save time), not the executor flag.
- `using LinearAlgebra: BLAS` qualified import in both files — avoids pulling the LinearAlgebra namespace into TSODSO/the testitem module.
- Identity-group test constructs two identical `:admm` Scenarios but never solves them — the item stays fast and needs no expected_broken.txt change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Declared the LinearAlgebra stdlib in root Project.toml + Manifest-v1.12**
- **Found during:** Task 1 (store.jl edit)
- **Issue:** Julia 1.12.5 hard-errored at precompile: `ArgumentError: Package TSODSO does not have LinearAlgebra in its dependencies` — 1.12 loads stdlibs as regular packages, so `using LinearAlgebra: BLAS` in store.jl requires a declared direct dep (plan anticipated the import but not the declaration)
- **Fix:** added `LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"` to Project.toml [deps] (alphabetical), `LinearAlgebra = "1"` to [compat] (matching the SparseArrays = "1" precedent), and "LinearAlgebra" to TSODSO's deps array in Manifest-v1.12.toml (entry already present transitively; v1.10/v1.11 manifests have no project entry, nothing to change)
- **Files modified:** Project.toml, Manifest-v1.12.toml
- **Verification:** `julia --project=. -e 'using TSODSO'` loads clean (fresh precompile OK)
- **Committed in:** 64fdd0e (Task 1 commit)

**2. [Rule 3 - Blocking] Declared LinearAlgebra in the test environment (+ restored a Pkg-clobbered comment block)**
- **Found during:** Task 2 (targeted test run)
- **Issue:** `@testitem` modules resolve `using` against the Pkg.test sandbox (test/Project.toml deps only), which errored `Package LinearAlgebra not found in current path`; additionally `Pkg.add("LinearAlgebra")` silently stripped the 13-line supply-chain-integrity comment block above test/Project.toml's [compat]
- **Fix:** `julia --project=test -e 'import Pkg; Pkg.add("LinearAlgebra")'` (stdlib — no registry download), then restored the stripped comment block verbatim by hand; Pkg refreshed test/Manifest.toml's project_hash (the `[[deps.LinearAlgebra]]` entry already existed transitively)
- **Files modified:** test/Project.toml, test/Manifest.toml
- **Verification:** targeted run 121 pass / 0 fail / 0 error / 0 broken, 0 soft-scope warnings
- **Committed in:** 4d753b1 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both are dependency-declaration housekeeping forced by Julia 1.12's stdlib loading model — additive only, no behavioral scope creep. All plan acceptance criteria met as written.

## Issues Encountered
- First Task 2 test run failed on the undeclared test-env dep (fixed, see deviation 2); a `Pkg.add` side effect (comment stripping) was caught in the diff and reverted before commit.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PAR-04 complete: every saved run dict now attributes its producing process (`julia_threads`/`blas_threads`), consumed by 39-04 (threaded executor) and 39-05 (SCALE-06 attribution) without any filename or identity churn.
- `parallel` remains a `solve_admm` kwarg only — no `parallel` field anywhere in Scenario/strategy (golden policy held; `_scenario_identity`/`_strategy_knobs`/`scenario_filename` byte-identical).
- LinearAlgebra is now a declared dependency in both environments, unblocking 39-04's `BLAS.set_num_threads(1)` executor pinning.

---
*Phase: 39-parallel-ready-admm-gating-measurements*
*Completed: 2026-10-24*

## Self-Check: PASSED

- SUMMARY.md exists: `.planning/phases/39-parallel-ready-admm-gating-measurements/39-03-SUMMARY.md`
- `src/experiments/store.jl` present with both additive keys (grep-verified lines 207-208)
- Commit `64fdd0e` (Task 1, feat) found in git log
- Commit `4d753b1` (Task 2, test) found in git log
- Targeted verification: `TSODSO_TEST_FILES=test_experiments.jl julia --project=. -e 'import Pkg; Pkg.test()'` — 121 pass / 0 fail / 0 error / 0 broken, no new skip/broken records, 0 soft-scope warnings
