---
phase: 01-plumbing-solver-abstraction
plan: 01
subsystem: infra
tags: [julia, jump, pkgtemplates, testitems, package-extensions, reproducibility, manifest]

# Dependency graph
requires: []
provides:
  - "TSODSO Julia package that instantiates, precompiles, and loads from a committed, [compat]-floored environment (INFRA-01)"
  - "Full subfoldered src/ include graph as empty compiling seam stubs, each single-owned by a later plan (conflict-free parallelism for Waves 2-3)"
  - "Manifest.toml pinned to CLAUDE.md versions (JuMP 1.30.1, HiGHS 1.24.1, Clarabel 0.11.1, Ipopt 1.15.0)"
  - "Gurobi/MosekTools gated as [weakdeps] + package [extensions] (never hard deps, removable)"
  - "Red Wave 0 TestItems harness: one @testitem per architectural seam + Aqua quality item"
  - ".github/workflows/CI.yml matrix (Julia 1.10/1.11/1.12) + format check; .JuliaFormatter.toml v2 style"
affects: [01-02, 01-03, 01-04, phase-02, phase-04, phase-06, phase-07]

# Tech tracking
tech-stack:
  added: [JuMP 1.30.1, HiGHS 1.24.1, Clarabel 0.11.1, Ipopt 1.15.0, SparseArrays, TestItems, TestItemRunner, Aqua, JET]
  patterns: ["include-graph seam ownership (one file = one later plan)", "weakdeps + package extensions for optional commercial solvers", "committed Manifest + [compat] floors for reproducibility", "TestItems rung ladder (one @testitem per seam, tag-filterable)"]

key-files:
  created:
    - Project.toml
    - Manifest.toml
    - src/TSODSO.jl
    - src/solver/factory.jl
    - ext/TSODSOGurobiExt.jl
    - test/runtests.jl
    - test/test_toy_dc.jl
    - .github/workflows/CI.yml
  modified: []

key-decisions:
  - "Hand-wrote the scaffold instead of running PkgTemplates interactively: the repo root already holds .git/.planning, and PkgTemplates would generate into a subdirectory requiring a move. Hand-writing produced every required artifact with exact control over the seam layout."
  - "Loosened SparseArrays [compat] from the Pkg.add-generated exact '1.12.0' to '1' so the Julia 1.10 LTS floor (whose stdlib SparseArrays is 1.10) still resolves (INFRA-01)."
  - "Used Pkg.test() as the canonical harness runner instead of the plan's literal 'julia --project=. -e using TestItemRunner' verify command, because TestItemRunner is a test-only dependency (as the acceptance criteria itself requires)."
  - "TSODSO.jl exports nothing and only includes; each seam file declares its own exports when filled, so later plans never edit the shared top module."

patterns-established:
  - "Seam-ownership include graph: src/TSODSO.jl includes 9 comment-only stubs, each owned by exactly one later plan (01-02/01-03/01-04)."
  - "Optional commercial solvers via [weakdeps]+[extensions], never hard deps (INFRA-02 removability)."
  - "TestItems harness with one red @testitem per seam, substring-named for VALIDATION filters, tags=[:rung0] on the integration item."

requirements-completed: [INFRA-01]

# Metrics
duration: 29min
completed: 2026-07-18
---

# Phase 1 Plan 01: Package Scaffold & Wave 0 Test Harness Summary

**TSODSO walking-skeleton package scaffolded with a committed, [compat]-floored (Julia 1.10) Manifest pinned to CLAUDE.md versions, a 9-seam single-ownership include graph of compiling stubs, weakdep-gated Gurobi/Mosek extensions, a 1.10/1.11/1.12 CI matrix, and a healthy red Wave 0 TestItems harness (10 pass / 1 fail / 7 error, as intended).**

## Performance

- **Duration:** ~29 min
- **Started:** 2026-07-18T15:54:01Z
- **Completed:** 2026-07-18T16:23:29Z
- **Tasks:** 2
- **Files created:** 26

## Accomplishments
- `TSODSO` package instantiates, precompiles, and `using TSODSO` succeeds from a clean committed environment (INFRA-01 keystone). Resolver landed exactly on the CLAUDE.md pins: JuMP 1.30.1, HiGHS 1.24.1, Clarabel 0.11.1, Ipopt 1.15.0.
- Full subfoldered `src/` (`units/ data/ solver/ core/ powerflow/ models/`) laid down as 9 empty compiling seam stubs, each header-tagged with its single owning plan + requirement — Waves 2-3 fill stubs without ever editing `src/TSODSO.jl`.
- Gurobi + MosekTools declared as `[weakdeps]` + package `[extensions]` (with `ext/` shells), keeping commercial solvers out of the default install and fully removable (INFRA-02 policy).
- `.github/workflows/CI.yml` runs the Julia 1.10 (LTS) / 1.11 / 1.12 matrix with clean-checkout `Pkg.instantiate` (buildpkg) + `Pkg.test` + a JuliaFormatter v2 format-check job.
- Wave 0 red TestItems harness: one `@testitem` per seam (perunit/feeder/topology/factory/status/context/toy) + an Aqua quality item; `Pkg.test()` confirmed the runner is healthy and every seam item is red (UndefVarError against empty stubs).

## Task Commits

1. **Task 1: Scaffold the TSODSO package with a pinned, reproducible environment** — `12e1966` (chore)
2. **Task 2: Wave 0 failing TestItems harness — one @testitem per seam** — `30c7e24` (test)

## Files Created/Modified
- `Project.toml` — deps + [compat] floors (incl. `julia = "1.10"`) + [weakdeps]/[extensions]
- `Manifest.toml` — committed pinned environment (INFRA-01), not git-ignored
- `src/TSODSO.jl` — `module TSODSO`; include graph over all 9 seams (exports nothing itself)
- `src/units/PerUnit.jl`, `src/data/{Feeder,topology}.jl`, `src/solver/{ProblemClass,factory}.jl`, `src/core/{ModelContext,status}.jl`, `src/powerflow/AbstractPowerFlow.jl`, `src/models/toy_dc.jl` — comment-only compiling seam stubs (owned by 01-02/01-03/01-04)
- `src/solver/factory.jl` — stub also records RESEARCH Pitfall-1 correction (Clarabel is copy_to-only; `direct_model` is HiGHS-only)
- `ext/TSODSOGurobiExt.jl`, `ext/TSODSOMosekExt.jl` — empty compiling extension shells
- `.github/workflows/CI.yml` — 1.10/1.11/1.12 matrix + format check
- `.JuliaFormatter.toml` — freeze v2 style (Pitfall 4)
- `.gitignore` — ignores docs/build + coverage; explicitly does NOT ignore Manifest.toml (Pitfall 3)
- `test/Project.toml` — isolated test env (Test, TestItems, TestItemRunner, Aqua, JET)
- `test/runtests.jl` — `using TestItemRunner; @run_package_tests`
- `test/test_{perunit,feeder,topology,factory,status,context,toy_dc}.jl` — one red `@testitem` per seam (+ Aqua quality item; toy tagged `[:rung0]`)

## Decisions Made
- Hand-wrote the scaffold rather than driving PkgTemplates interactively (repo root already contains `.git`/`.planning`; PkgTemplates generates into a subdirectory). All required artifacts (Project/Manifest, CI matrix, Aqua/JET wiring, Documenter-equivalent CI, `.JuliaFormatter.toml`) were produced directly. Docs skeleton was intentionally NOT created — it is not in this plan's `files_modified` ownership set (Literate `docs/` lands with plan 01-04 / later).
- `select_optimizer`/`ProblemClass` singleton-dispatch, `assert_solved!`, `Feeder{T}`, `ModelContext` residual registry are all described in the seam stub headers but implemented by their owning later plans (01-02/01-03/01-04) — Phase-1 plan 01-01 only owns the compiling chassis.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Loosened SparseArrays [compat] so the Julia 1.10 floor resolves**
- **Found during:** Task 1 (environment scaffold)
- **Issue:** `Pkg.add` on Julia 1.12 auto-wrote `SparseArrays = "1.12.0"` into `[compat]`. Since SparseArrays is a stdlib versioned with Julia, that exact bound would REJECT Julia 1.10 LTS (stdlib SparseArrays 1.10), breaking INFRA-01's "resolves cleanly on 1.10" requirement.
- **Fix:** Set `SparseArrays = "1"` (covers 1.10 through 1.12). Other deps kept at their CLAUDE.md pins.
- **Files modified:** Project.toml
- **Verification:** `Pkg.resolve()` + `Pkg.instantiate()` + `using TSODSO` exit 0; `julia = "1.10"` floor present.
- **Committed in:** `12e1966`

**2. [Rule 3 - Blocking] Used Pkg.test() instead of the plan's literal quick-run verify command**
- **Found during:** Task 2 (test harness verification)
- **Issue:** The plan's `<automated>` verify `julia --project=. -e 'using TestItemRunner; @run_package_tests'` cannot load TestItemRunner, which is (correctly) a test-only dependency — the acceptance criteria itself mandates "Test env resolves TestItems, TestItemRunner, Aqua, JET". The two are mutually exclusive.
- **Fix:** Ran the canonical `julia --project=. -e 'import Pkg; Pkg.test()'`, which merges package + test/Project.toml deps and runs `@run_package_tests`. Confirmed a healthy harness with the intended red state.
- **Files modified:** none (verification method only)
- **Verification:** Test Summary produced by the runner: 10 pass / 1 fail / 7 error; all 7 seam items red via UndefVarError; Aqua item red on "Stale dependencies". No runner-infrastructure crash.
- **Committed in:** n/a (no code change)

**3. [Rule 2 - Missing Critical] Added .gitignore protecting the committed Manifest**
- **Found during:** Task 1 (environment scaffold)
- **Issue:** No `.gitignore` existed; RESEARCH Pitfall 3 warns that a default template `.gitignore` can silently ignore `Manifest.toml`, breaking reproducibility. `.gitignore` was not in the plan's `files_modified` list.
- **Fix:** Added a minimal Julia `.gitignore` that ignores `docs/build` + coverage artifacts and carries an explicit note NOT to ignore `Manifest.toml`.
- **Files modified:** .gitignore
- **Verification:** `git check-ignore Manifest.toml` returns empty (not ignored); Manifest committed in Task 1.
- **Committed in:** `12e1966`

---

**Total deviations:** 3 (2 blocking, 1 missing-critical) — 1 is verification-method-only.
**Impact on plan:** All deviations serve the plan's own INFRA-01 reproducibility and Wave-0 acceptance intent. No scope creep; no seam logic was implemented.

## Known Stubs

All `src/**/*.jl` seam files and both `ext/*.jl` files are **intentional empty compiling stubs** — this is the explicit design of plan 01-01 (lock reproducibility and file ownership before any logic exists). Each stub's header names its single owning plan and requirement:

| Stub | Owner | Requirement |
|------|-------|-------------|
| src/units/PerUnit.jl | 01-02 | INFRA-05 |
| src/data/Feeder.jl | 01-02 | DATA-01 |
| src/data/topology.jl | 01-02 | DATA-02 |
| src/solver/ProblemClass.jl | 01-03 | INFRA-02 |
| src/solver/factory.jl | 01-03 | INFRA-02 |
| src/core/ModelContext.jl | 01-03 | PF-01 |
| src/core/status.jl | 01-03 | INFRA-03 |
| src/powerflow/AbstractPowerFlow.jl | 01-03 | PF-01 |
| src/models/toy_dc.jl | 01-04 | rung-0 integration |
| ext/TSODSOGurobiExt.jl, ext/TSODSOMosekExt.jl | 01-03 | INFRA-02 |

These stubs are the reason the Wave 0 `@testitem`s are red; they are NOT unintended stubs and each is scheduled for a specific later plan.

## Issues Encountered
- First `Pkg.add` and first `Pkg.test()` each took several minutes (Clarabel ~280s, JuMP ~136s, MathOptInterface ~117s precompile; JET/Aqua/TestItemRunner in the test env). Expected per the environment notes; allowed to finish.

## User Setup Required
None for local work. **Manual/CI-only:** INFRA-01's "resolves cleanly on Julia 1.10 LTS" cannot be verified locally (1.10 not installed — only 1.11/1.12). It is delegated to the CI matrix, or verifiable locally via `juliaup add 1.10 && julia +1.10 --project=. -e 'import Pkg; Pkg.instantiate()'`.

## Next Phase Readiness
- Chassis is ready. Waves 2-3 (plans 01-02, 01-03, 01-04) can now fill their owned seam stubs in parallel with zero shared-file conflicts and drive their red `@testitem`s green.
- Canonical local runners: `julia --project=. -e 'import Pkg; Pkg.test()'` (full suite) and `Pkg.test()`-based filtering for per-rung runs.
- Note for later plans: SparseArrays currently shows as an unused (stale) dependency — Aqua's "Stale dependencies" check will stay red until `data/topology.jl` (plan 01-02) uses it.

---
*Phase: 01-plumbing-solver-abstraction*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All key created files exist (Project.toml, Manifest.toml, src/TSODSO.jl, seam stubs, ext shells, test harness, CI.yml, SUMMARY).
- Both task commits exist in git history: `12e1966` (Task 1, chore), `30c7e24` (Task 2, test).
