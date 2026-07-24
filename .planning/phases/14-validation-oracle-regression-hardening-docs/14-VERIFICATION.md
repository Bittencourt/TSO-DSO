---
phase: 14-validation-oracle-regression-hardening-docs
verified: 2026-07-24T11:27:32Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 14: Validation-Oracle Regression Hardening & Docs Verification Report

**Phase Goal:** One-off validation runs (BilevelJuMP certification, diagonalization
convergence) become permanent regression infrastructure, the planning math is
literate-documented and traced to code, and continuous-only scope is enforced
automatically rather than by convention.

**Verified:** 2026-07-24T11:27:32Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Canonical N=1/N=2 fixtures pinned as computed goldens, gated by BilevelJuMP agreement (N=1) and diagonalization convergence (N=2) | VERIFIED | `test/fixtures_planning.jl` (63 lines, 8 named consts, all values/comments match Phase 11/13 certified sources) + `test/test_planning_goldens.jl` (3 `@testitem`s). Ran live via `TestItemRunner` from a scratch dev-linked env: **14/14 pass**. Read source: gate assertion (`result.gap<=1e-6` / `result.converged` / `result.n_runs==6`+honesty-string checks) precedes the pinned-value `isapprox`/`<=` assertions in all 3 testitems — gate-then-golden ordering confirmed by direct code inspection, not just claimed. |
| 2 | Literate Documenter pages map PSR problem numbers, coupling seam (`z↔p_ag`, `λ_j↔π_s`), and the leader/follower choice to code, `@example`-executed | VERIFIED | `docs/literate/stackelberg_benders.jl` (144 lines) and `docs/literate/nash_diagonalization.jl` (178 lines) both exist with problem-number maps, coupling-seam tables, and live solve calls. Ran `julia --project=docs docs/make.jl` myself: **exit 0**, both `docs/src/generated/*.md` produced non-empty. Parsed the built HTML directly (not the SUMMARY's claim): `result.UB = 17.75500113214901`, offset-corrected `= -0.24499886785098823` (matches certified `-0.245` to atol), `result.z = [0.6,0.6]`, `result.x_inv=[0.3,0.3]` (exact hand-checked match), `probe.summary` contains `"a converged equilibrium"` and not `"the equilibrium"`. No `using BilevelJuMP/HiGHS/Ipopt` in either page (grepped directly). |
| 3 | Automated no-binaries guard fails CI/tests if any planning-layer subproblem builder introduces a binary/integer variable | VERIFIED | `test/test_planning_noninteger.jl` (124 lines): 4-builder registry + source-scan tripwire (recursive `walkdir`, docstring-aware regex, plus a syntax-independent semantic export-diff channel per WR-01 hardening). Ran live: **5/5 pass**. **Actively tested the tripwire's failure mode**: appended a dummy `function build_fake_probe_thing(...)` to `src/planning/coupling.jl`, re-ran the guard — it failed loudly (`Set(...) == Set(...)` mismatch showing the new unregistered name) exactly as designed. Reverted the probe edit (`git checkout --`, confirmed clean `git diff --stat`). |
| 4 | BilevelJuMP certification case (PVAL-01) remains green in the permanent regression suite, wired into the same CI gate as the new goldens | VERIFIED | `test/test_planning_certification.jl` untouched, still tagged `[:planning]` (same tag/gate as the new goldens files), containing the `StrongDualityMode`/`ProductMode` agreement testitem and the `solve_stackelberg!` production-Benders-agreement testitem — both still present at lines 133/170, unmodified by this phase. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fixtures_planning.jl` | `@testmodule PlanningFixtures` with 8 pinned/bounded consts | VERIFIED | Exists, 63 lines, exactly 8 consts (`N1_Y_HAND`, `N1_Z_HAND`, `N1_OBJ_HAND`, `N2_Z_HAND`, `N2_XINV_HAND`, 3×`N2_PROBE_*_SPREAD_MAX`), all exported, each with rationale/derivation comment, no top-level solve call |
| `test/test_planning_goldens.jl` | 3 gate-then-golden `@testitem`s | VERIFIED | 157 lines, 3 testitems tagged `[:planning]`, all `setup=[Phase6Fixtures, ToyDeviceFixture, PlanningFixtures]`; ran live 14/14 pass |
| `test/test_planning_noninteger.jl` | Consolidated 4-builder no-binaries guard + tripwire | VERIFIED | 124 lines, 1 testitem covering all 4 builders + hardened tripwire; ran live 5/5 pass; tripwire failure mode actively exercised and confirmed |
| `docs/src/api.md` | New "Planning Layer" `@autodocs` section, `Order=[:type,:constant,:function]`, 9 files | VERIFIED | Section present at line 112, exact 9-path list, correct `Order` (deliberately includes `:constant` for `RETRYABLE_STATUSES`) |
| `docs/literate/stackelberg_benders.jl` | Rung 6 literate page | VERIFIED | 144 lines; live `solve_stackelberg!` call; renders genuinely computed `result.gap/y/z/UB` |
| `docs/literate/nash_diagonalization.jl` | Rung 7 literate page | VERIFIED | 178 lines; live `run_nash!`/`run_nash_probe` calls; "a converged equilibrium" present, "the equilibrium" absent |
| `docs/make.jl` | Wires both new Literate sources + "Planning" pages subsection | VERIFIED | `for src in (...)` tuple includes both new files after `admm.jl`; `pages` array has a `"Planning"` entry before `"API Reference"` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `test/test_planning_goldens.jl` | `test/fixtures_planning.jl` | `setup=[..., PlanningFixtures]` | WIRED | Confirmed by direct read; all `PlanningFixtures.N1_*`/`N2_*` references resolve to fixture consts |
| `test/test_planning_goldens.jl` | `src/planning/benders.jl`, `src/planning/nash.jl` | direct `solve_stackelberg!`/`run_nash!`/`run_nash_probe` calls | WIRED | Confirmed by direct read and live execution (14/14 pass) |
| `test/test_planning_noninteger.jl` | `src/planning/{subproblem,follower,master,coupling}.jl` | direct `build_*` calls + `walkdir`/regex scan | WIRED | Confirmed by direct read, live execution, and an injected-failure test of the tripwire itself |
| `docs/make.jl` | `docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl` | `Literate.markdown` loop + `pages` tree | WIRED | Confirmed by direct read and a full `docs/make.jl` run (exit 0, both generated `.md`/`.html` produced) |
| `docs/literate/stackelberg_benders.jl` | `src/planning/benders.jl` (`solve_stackelberg!`) | live `@example` call | WIRED, DATA FLOWING | Confirmed by parsing built HTML: displayed numbers are genuinely computed (`17.75500113214901`, not a copy-pasted literal) |
| `docs/literate/nash_diagonalization.jl` | `src/planning/nash.jl` (`run_nash!`, `run_nash_probe`) | live `@example` calls | WIRED, DATA FLOWING | Confirmed by parsing built HTML: `result.z=[0.6,0.6]`, `result.x_inv=[0.3,0.3]`, `probe.spread` all genuinely computed |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `docs/literate/stackelberg_benders.jl` | `result.gap/y/z/UB` | live `solve_stackelberg!` call, Documenter `@example`-executed at build time | Yes — parsed `docs/build/generated/stackelberg_benders.html` directly, values are non-trivial floats consistent with the certified fixture up to the documented `+18` offset | FLOWING |
| `docs/literate/nash_diagonalization.jl` | `result.converged/z/x_inv`, `probe.summary/spread` | live `run_nash!`/`run_nash_probe` calls, Documenter `@example`-executed | Yes — parsed `docs/build/generated/nash_diagonalization.html` directly, `z=[0.6,0.6]`/`x_inv=[0.3,0.3]` match the hand-checked golden exactly, `probe.spread` shows genuine floating-point noise values (`4.44e-16`), not a hardcoded 0 | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Planning goldens regression | `TestItemRunner.run_tests(...; filter=occursin("planning goldens", ...))` from scratch dev-linked env | 14/14 pass | PASS |
| No-binaries guard | `TestItemRunner.run_tests(...; filter=occursin("no-binaries guard", ...))` from scratch dev-linked env | 5/5 pass | PASS |
| No-binaries tripwire actually fires on a new builder | Appended `build_fake_probe_thing` to `src/planning/coupling.jl`, re-ran guard, reverted | Test failed loudly naming the new builder; reverted cleanly (`git diff --stat` empty after) | PASS |
| Existing partial checks (coupling/nash) — no regression | `TestItemRunner.run_tests(...; filter=occursin("planning coupling",...)\|\|occursin("planning nash",...))` | 118 pass / 1 broken (documented CairoMakie weakdep skip) / 0 fail | PASS |
| Documenter full build | `julia --project=docs docs/make.jl` | Exit 0; both new pages rendered; `checkdocs=:exports` is NOT in `warnonly` (grepped `docs/make.jl` directly — confirms the gate is real, not suppressed) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|-------------|-------------|--------|----------|
| PVAL-02 | 14-01-PLAN.md | Canonical single-/multi-distributor fixtures pinned as computed goldens, gated by BilevelJuMP agreement and diagonalization convergence | SATISFIED | `test/fixtures_planning.jl` + `test/test_planning_goldens.jl`, 14/14 live pass |
| PVAL-03 | 14-03-PLAN.md | Literate Documenter documentation maps the planning math to code, `@example`-executed | SATISFIED | Rung 6/7 pages + api.md fix; `docs/make.jl` exit 0; live-computed values confirmed in built HTML |
| PVAL-04 | 14-02-PLAN.md | Automated no-binaries guard on every planning-layer subproblem builder | SATISFIED | `test/test_planning_noninteger.jl`; guard's failure mode actively exercised and confirmed |
| PVAL-01 | Phase 11 (retained) | BilevelJuMP certification permanent regression | SATISFIED (unchanged) | `test/test_planning_certification.jl` untouched, still `[:planning]`-tagged, in the same gate |

No orphaned requirements: `.planning/REQUIREMENTS.md`'s Phase 14 row lists exactly PVAL-02/03/04, all three claimed by a plan's `requirements:` frontmatter field (14-01→PVAL-02, 14-02→PVAL-04, 14-03→PVAL-03).

**Minor documentation-tracking note (non-blocking):** `.planning/REQUIREMENTS.md`'s status table (lines 94-97) still lists PVAL-02/03/04 as "Pending" and their checkboxes (lines 51-56) as unchecked, even though the functional deliverables are complete and verified. This mirrors the pattern of other completed phases where that table is updated during a separate phase-closure step (e.g. the "evolve PROJECT.md after phase completion" commit seen for Phase 13), which had not yet run for Phase 14 at verification time. This is a bookkeeping gap, not a functional one — it does not affect the phase goal's achievement and requires no code/test/docs fix, only the standard post-verification tracking-update step.

### Anti-Patterns Found

None. Scanned all 7 new/modified phase files (`test/fixtures_planning.jl`, `test/test_planning_goldens.jl`, `test/test_planning_noninteger.jl`, `docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl`, `docs/src/api.md`, `docs/make.jl`) for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|placeholder|coming soon|not yet implemented` — zero matches.

Code review (`14-REVIEW.md`, iteration 2, post-fix): status `clean`, 0 critical, 0 warning, 2 non-blocking info items (both already reconciled/verified live per the review's own iteration-2 fix-verification narrative — the Deferrable `+18` offset reconciliation and the tripwire's residual triple-quote edge case, which the review itself confirms does not affect any of the 4 current, all-exported builders).

### Human Verification Required

None. All must-haves in this phase are objectively, programmatically checkable (test pass/fail counts, docs build exit code, literal-string/grep checks, live-executed numeric values parsed from built HTML) and were independently re-verified in this session rather than taken from SUMMARY.md claims.

### Gaps Summary

No gaps. All 4 ROADMAP success criteria and all 3 plans' frontmatter must-haves were independently re-verified against the actual codebase (not inferred from SUMMARY.md): file contents read directly, tests re-run from a scratch dev-linked environment, the no-binaries tripwire's failure mode actively exercised via an injected dummy builder (then cleanly reverted), and the Documenter build re-run with its generated HTML parsed directly to confirm displayed numbers are live-computed rather than hardcoded.

---

*Verified: 2026-07-24T11:27:32Z*
*Verifier: Claude (gsd-verifier)*
