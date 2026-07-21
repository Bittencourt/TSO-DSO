---
phase: 09-documentation-regression-acceptance-gate
verified: 2026-07-20T23:15:00Z
status: passed
score: 3/3 must-haves verified
overrides_applied: 0
deferred:
  - truth: "~104 exported-symbol docstrings surfaced in a rendered API-reference manual (@docs/@autodocs blocks)"
    addressed_in: "Post-v1 follow-up (tracked in deferred-items.md, not a milestone phase)"
    evidence: "09-REVIEW.md WR-01 + deferred-items.md 'Docstring-manual wiring': docstrings exist in src/ but are not yet spliced into docs/src/*.md pages via @docs/@autodocs; checkdocs=:exports + warnonly keeps the build green. Explicitly out of EXP-03's literate-page scope (EXP-03 requires per-model math docs, which are the six rung pages, not a full API reference)."
  - truth: "JuliaFormatter coverage extended to docs/"
    addressed_in: "Deliberate hand-reviewed formatting pass (deferred-items.md WR-04), not a v1 blocker"
    evidence: "deferred-items.md WR-04: mechanical reformat would detach inline equation-comments from device-constructor args, violating the CLAUDE.md equations-beside-code requirement; needs a hand pass, tracked as follow-up."
  - truth: "deploydocs real GitHub org/repo slug wired"
    addressed_in: "Pre-first-deploy checklist item (deferred-items.md WR-05), settled user decision 2026-07-20"
    evidence: "No git remote configured in this checkout; deploydocs is CI-env-gated so the placeholder is inert until the first real gh-pages deploy — explicitly accepted, not a v1 acceptance-gate requirement."
---

# Phase 9: Documentation & Regression Acceptance Gate Verification Report

**Phase Goal:** Close the milestone with the hard documentation requirement and the v1 acceptance
gate — literate per-model math docs (Documenter + Literate), pinned regression fixtures catching
numerical drift, and an end-to-end reproduction of the IEEE 13 + 123 reference cases with exact
relaxation, recovered DADP, and ADMM matching centralized.
**Verified:** 2026-07-20T23:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every model has literate, reproducible documentation stating its math (eq. refs), assumptions, validation, built via Documenter + Literate | VERIFIED | All 6 `docs/literate/*.jl` pages exist (`toy_dc.jl`, `lindistflow.jl`, `convex_branch_flow.jl`, `prosumer_welfare.jl`, `pricing_dlmp.jl`, `admm.jl`), each cites specific thesis equations (3.2-3.9, 3.21-3.23, 3.31-3.33, 3.36, 3.38-3.39, 3.43-3.47), states assumptions (e.g. strict λ_min<λ_med<λ_max battery ordering, b>0 convexity), and ends with a real-solve validation step. Independently ran `julia --project=docs docs/make.jl` — **exit code 0**, confirmed via a separate un-piped invocation. All 6 `.md` pages + 6 `.html` pages generated in `docs/build/generated/`, including a real rendered CairoMakie PNG (`admm-*.png`, 91 KB) which I visually inspected — a correct, correctly-labeled log-scale ADMM primal/dual residual convergence plot. |
| 2 | Regression fixtures pin reference results (IEEE 13/123, FIT comparison) so numerical drift is caught automatically | VERIFIED | `test/test_acceptance.jl` reuses `test_ieee13.jl`'s exact pinned goldens (`GOLDEN_WELFARE = -4823.1598620624`, `GOLDEN_V9_16 = 1.0436080536`, byte-identical to the source file) and `test_ieee123_admm.jl`'s tolerances/fixtures. `test/test_pricing_fit.jl` adds a new pinned `FIT_RATIO_GOLDEN = 0.6428101637491034` (rtol 1e-4). Pre-existing pins (`test_ieee13.jl`, `test_ieee123.jl`, `test_ieee123_admm.jl`, `test_pricing_welfare.jl`'s `RATIO_GOLDEN`) remain intact and unmodified — additive, not replaced. |
| 3 | v1 acceptance gate passes E2E: IEEE-13 congestion + IEEE-123 voltage, exact relaxation + recovered DADP + ADMM matching centralized | VERIFIED | Independently ran the full suite (`julia --project=. -e 'using Pkg; Pkg.test()'`, not trusting SUMMARY): **1946 pass / 0 fail / 2 broken / 1948 total, 8m20.8s, "Testing TSODSO tests passed."** Both `:acceptance`-tagged testitems in `test/test_acceptance.jl` executed and passed: IEEE-13 asserts `ctx.meta[:socp_maxgap] < 1e-5`, welfare golden match, `admm.exact_maxgap < 1e-3`, ADMM≈centralized welfare, ADMM DADP≈centralized DLMP, and the hard `v9_16 ≈ GOLDEN_V9_16` voltage regression; IEEE-123 asserts iteration bound, welfare match, exactness, and DADP match. The exactly 2 "broken" items are the documented non-failing thesis-headline cross-checks (v9[16] thesis gap ≈0.0057, +25% welfare-ratio headline) — confirmed via live `@info` log output matching the expected values, not new/unexplained failures. Solver path is open-source (HiGHS/Clarabel via the solver factory) throughout. |

**Score:** 3/3 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `docs/literate/lindistflow.jl` | Rung 1-2 literate page | VERIFIED | 79 lines; cites 3.31/3.32/3.43; calls real `solve_linear` |
| `docs/literate/convex_branch_flow.jl` | Rung 3 literate page | VERIFIED | 96 lines; cites 3.39/3.43/3.45; calls real `solve_welfare`, displays `ctx.meta[:socp_maxgap]` |
| `docs/literate/prosumer_welfare.jl` | Rung 2a literate page | VERIFIED | 159 lines; cites 3.2-3.23/3.38; builds Thermostatic+Deferrable+PVBattery+Aggregator, real `solve_welfare` |
| `docs/literate/pricing_dlmp.jl` | Rung 4 literate page | VERIFIED | 118 lines; cites 3.31/3.36/3.39/3.46-3.47; calls real `extract_dlmp`/`decompose_dlmp`/`welfare_accounting` |
| `docs/literate/admm.jl` | Rung 5 literate page | VERIFIED | 120 lines; cites 3.46/3.47; calls real `solve_admm` cross-validated against `solve_welfare`; renders CairoMakie figure |
| `docs/make.jl` | Full 6-page Documenter+Literate build, `DocumenterFlavor`, `checkdocs=:exports`, CI-gated `deploydocs` | VERIFIED | All 6 `Literate.markdown(...; flavor = Literate.DocumenterFlavor())` calls present; `checkdocs = :exports`; `deploydocs` gated on `ENV["CI"]=="true"`; independently built, exit 0 |
| `test/test_acceptance.jl` | SC3 E2E acceptance gate, `tags = [:acceptance]` | VERIFIED | Both IEEE-13 and IEEE-123 testitems present, real entrypoints, reused goldens/tolerances |
| `test/test_pricing_fit.jl` | Extended FIT regression golden | VERIFIED | `FIT_RATIO_GOLDEN` pinned test added; existing FIT tests untouched |
| `.github/workflows/CI.yml` | Dedicated `docs:` job with docs-env instantiate | VERIFIED | `docs:` job present, separate from the 1.10/1.11/1.12 test matrix, `julia-actions/julia-buildpkg@v1` with `project: docs` runs before `julia --project=docs docs/make.jl` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `docs/literate/lindistflow.jl` | `src/models/linear_solve.jl solve_linear` | direct call | WIRED | `solve_linear(feeder, LinDistFlow(), [device]; ...)` at line 62 |
| `docs/literate/convex_branch_flow.jl` | `solve_welfare` + `assert_socp_exact!` | direct call | WIRED | `solve_welfare(feeder, ConvexBranchFlow(), [agg]; ...)`; `ctx.meta[:socp_maxgap]` displayed |
| `docs/literate/prosumer_welfare.jl` | `solve_welfare` + `Aggregator` | direct call | WIRED | Real `Thermostatic`/`Deferrable`/`PVBattery` + `Aggregator` + `solve_welfare` |
| `docs/literate/pricing_dlmp.jl` | `extract_dlmp`/`decompose_dlmp`/`welfare_accounting` | direct call on solved ctx | WIRED | Internal hard assertions in `decompose_dlmp`/`welfare_accounting` pass silently (validation-by-non-throw) |
| `docs/literate/admm.jl` | `solve_admm` + `solve_welfare` + `plot_convergence` | direct call | WIRED | Cross-validates `admm.welfare` vs `obj_c`; CairoMakie guarded by `Base.find_package` |
| `docs/make.jl` | all 6 literate sources | `Literate.markdown(...; flavor=DocumenterFlavor())` | WIRED | Confirmed by successful independent build producing all 6 generated `.md`/`.html` pages |
| `test/test_acceptance.jl` | `operational_oracle`/`solve_admm`/`extract_dlmp` | real entrypoints, `setup=[Phase4Fixtures]`/`[Phase7Fixtures]` | WIRED | Confirmed by live test run: both acceptance testitems executed, asserted, passed |
| `test/test_pricing_fit.jl` | `src/pricing/fit.jl fit_baseline` | pinned golden + rtol | WIRED | `FIT_RATIO_GOLDEN` assertion ran and passed in the live suite |
| `.github/workflows/CI.yml docs job` | `docs/make.jl` | `run: julia --project=docs docs/make.jl` | WIRED | Job present, `env: CI: 'true'` set so `deploydocs`/`prettyurls` gates activate |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite green | `julia --project=. -e 'using Pkg; Pkg.test()'` | 1946 pass / 0 fail / 2 broken / 1948 total, 8m20.8s, "tests passed" | PASS |
| Docs build succeeds | `julia --project=docs docs/make.jl` (un-piped, explicit `$?` check) | Exit code 0 | PASS |
| CairoMakie figure renders correctly | Visual inspection of `docs/build/generated/admm-*.png` | Clean, correctly-labeled log-scale primal/dual residual plot with ε thresholds | PASS |
| Acceptance gate items actually execute (not vacuous) | grep of live test-run `@info`/assertion output for `"acceptance ieee13"` | Present, matches expected numeric values (v9_16=1.0436080535989598, gap≈0.00569) | PASS |
| No debt markers (TBD/FIXME/XXX) in phase-touched files | `grep -n -E "TBD\|FIXME\|XXX"` across all 11 phase-modified files | No matches | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| EXP-03 | 09-01, 09-02, 09-04, 09-05 | Literate per-model math docs via Documenter+Literate | SATISFIED | 6 pages built and executed; ROADMAP.md/REQUIREMENTS.md checkbox marked complete |
| EXP-04 | 09-03 | Regression fixtures pin IEEE-13/123 + FIT results | SATISFIED (code) / STALE (traceability doc) | `test_acceptance.jl` + `test_pricing_fit.jl` fully implement and pass this requirement in the live suite, but `.planning/REQUIREMENTS.md` line 100/184 still shows EXP-04 as an unchecked `[ ]` / "Pending" — a stale bookkeeping entry, not a functional gap (see Anti-Patterns below). |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/REQUIREMENTS.md` | 100, 184 | `EXP-04` still marked `[ ]` / "Pending" despite being fully implemented and verified (plan 09-03, committed before the 09-04 commit that last touched this file) | INFO/WARNING (documentation hygiene) | Does not affect functional correctness — the actual code satisfies EXP-04 in full (verified above). Recommend flipping the checkbox and the traceability-table status to "Complete" before formally closing the v1 milestone, since this is the milestone-closing phase and the ledger should be accurate for the historical record. |
| `docs/make.jl` | 61-62 | `checkdocs=:exports` with `warnonly=[:missing_docs, :cross_references]` — ~104 docstrings not yet spliced into the manual via `@docs`/`@autodocs`, ~15 unresolved `@ref`s | INFO (accepted deferral) | Explicitly a locked CONTEXT.md decision ("keep warnonly for the remainder so the build stays green") and documented in `deferred-items.md`; NOT part of EXP-03's per-model literate-page scope. Confirmed the build still exits 0 and only these two non-fatal categories are involved (independently re-ran the build). |
| `docs/make.jl` | 68-75 | `deploydocs` placeholder repo slug (`PLACEHOLDER-ORG/PLACEHOLDER-REPO`) | INFO (accepted deferral, WR-05) | Settled user decision 2026-07-20; `deploydocs` is CI-env-gated so this is inert for the v1 acceptance gate; tracked as a pre-first-deploy TODO in `deferred-items.md`. |
| `docs/` (whole tree) | — | Not covered by the CI `format:` job (JuliaFormatter) | INFO (accepted deferral, WR-04) | Documented rationale: mechanical reformat would detach inline equation-comments from device-constructor args, violating the CLAUDE.md "equations beside code" requirement; needs a deliberate hand pass. |

No blocker-level anti-patterns found. No unresolved `TBD`/`FIXME`/`XXX` markers in any of the 11 phase-touched files.

### Human Verification Required

None. The two items flagged as "manual-only" in `09-VALIDATION.md` are both resolved:
- `deploydocs` repo-slug correctness — resolved as a settled user decision (WR-05, deferred-items.md), inert until a real CI deploy.
- CairoMakie figure aesthetics — spot-checked directly by this verifier (image read and visually inspected): the generated `admm-*.png` is a correctly rendered, clearly labeled, publication-quality log-scale convergence plot. No rendering defects observed.

### Gaps Summary

No blocking gaps. All three ROADMAP.md success criteria are independently verified against the live
codebase (not SUMMARY claims): the full test suite was re-run from scratch (1946/0/2, matching the
code-review's own independently-reproduced numbers) and the Documenter+Literate docs build was
re-run from scratch with an unambiguous exit-code check (0). The code review for this phase is
`resolved` (both blockers fixed; 2 warnings explicitly deferred with documented, accepted rationale).

One non-blocking documentation-hygiene item was found: `.planning/REQUIREMENTS.md`'s EXP-04
traceability line was not flipped to "Complete" despite the requirement being fully satisfied in
code. This is flagged for a quick fix before formally closing the v1 milestone but does not affect
phase-9 goal achievement.

---

_Verified: 2026-07-20T23:15:00Z_
_Verifier: Claude (gsd-verifier)_
