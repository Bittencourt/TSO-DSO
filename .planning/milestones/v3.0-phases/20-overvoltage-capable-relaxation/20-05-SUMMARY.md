---
phase: 20-overvoltage-capable-relaxation
plan: 05
subsystem: documentation / literate pages / phase acceptance
tags: [OVR-04, gan-low, socp-exactness, literate, documenter, acceptance]

requires:
  - phase: 20-01
    provides: "recover_lossfree_shadow_voltage, measured ε_measured = 0.005811069127373614, confirmed v ≥ v̂ (Assumption A1)"
  - phase: 20-02
    provides: "RestrictedBranchFlow <: AbstractPowerFlow implementing Gan-Low OPF-m (v̂_GL(s) ≤ v̄), plus the documented OPF-ε negative-result finding on EXACT-04"
  - phase: 20-03
    provides: "assert_restriction_exact!(ctx_restricted, ctx_ac; unrestricted_cost, report) -> (; ac_feasible, matches_ac_optimum, optimality_loss, obj_gap, hours)"
  - phase: 20-04
    provides: "ac_dual_fallback_price(feeder, aggregators; ...) -> (; dadp, cost_ac, price_status = :local_ac_dual, agreement_report), quarantined 5-seed spike evidence"
provides:
  - "docs/literate/restricted_branch_flow.jl — live-executed Rung 3 page narrating the Gan-Low condition (C1/C2, Theorem 1/2, Lemma 1, Definition 3), the honest OPF-ε negative-result finding, the OPF-m success, the free PF-04 signal, the OVR-02 certificate's two-question semantics, and the fallback semantics"
  - "docs/make.jl registration of the new page (Literate.markdown loop + Models pages list)"
  - "docs/src/api.md wiring for RestrictedBranchFlow/assert_restriction_exact!/ac_dual_fallback_price docstrings into @autodocs Pages lists — plus the pre-existing Phase-19 FourQuadBESS/ReactiveMode/complementarity_4q gap discovered and fixed while diagnosing the same checkdocs failure"
  - "Full-suite phase-acceptance run: 2546 passed / 0 failed / 3 pre-existing broken / 2549 total (18m21.4s) — zero default-path drift across the entire phase"
affects: []

tech-stack:
  added: []
  patterns:
    - "using TSODSO.JuMP (not a direct `using JuMP`) as the literate-page idiom for accessing JuMP's `value()` when docs/Project.toml does not list JuMP as a direct dependency — mirrors docs/literate/socp_applicability.jl's existing precedent"
    - "honest-fallback live computation when a paper's exact worked-example formula cannot be confidently re-derived from the research pass alone — recompute the SAME measured quantity a prior plan already validated (ε via recover_lossfree_shadow_voltage), state explicitly in prose what is deferred, cite the literature's own empirical finding as the grounded expectation, never fabricate a number"

key-files:
  created:
    - docs/literate/restricted_branch_flow.jl
  modified:
    - docs/make.jl
    - docs/src/api.md

key-decisions:
  - "Substituted the honest-fallback C1 live-computation (recompute ε_measured via the same recover_lossfree_shadow_voltage recipe plan 20-01 Task 2 used, inlined here) rather than deriving RESEARCH.md's paper-specific A₁·u₂ 2×2 worked-example formula, since that formula was not independently re-derived with confidence during this project's own research pass (RESEARCH.md Open Question #2's own explicit fallback instruction) — avoids fabricating a numeric 'C1 margin' figure never actually derived from the paper."
  - "Fixed docs/src/api.md's @autodocs Pages lists to wire in RestrictedBranchFlow.jl / restriction_exactness.jl / ac_dual_fallback.jl (Rule 3 — this plan's own blocking issue: `checkdocs = :exports` is a GLOBAL gate over the whole TSODSO module, not scoped per literate page, so any orphaned exported docstring anywhere in the module fails every docs build) — discovered in the same pass that Phase 19's FourQuadBESS/ReactiveMode/normalize_reactive_mode/assert_4q_complementarity! docstrings were ALSO never wired in, and fixed those too since the build cannot pass otherwise."

requirements-completed: [OVR-04]

duration: ~60min
completed: 2026-08-08
---

# Phase 20 Plan 05: Overvoltage-Capable Restriction Literate Page + Full-Suite Acceptance Summary

**A live-executed literate page (`docs/literate/restricted_branch_flow.jl`) narrates the full two-mechanism Phase 20 story — the Gan-Low C1/C2 condition, the honest OPF-ε negative result, the OPF-m success (`socp_maxgap = 2.08e-8`), the certificate's `ac_feasible = true` / `matches_ac_optimum = false` / `optimality_loss ≈ -1.4326` distinction, and the fallback semantics — and the phase closes with a full-suite acceptance run at exactly the documented baseline: 2546 passed / 0 failed / 3 pre-existing broken / 2549 total.**

## Performance

- **Duration:** ~60 min (context read across all 4 prior SUMMARYs + RESEARCH.md + source files, Task 1 authoring + docs-build debugging, Task 2 full-suite wait)
- **Started / Completed:** 2026-08-08
- **Tasks:** 2 of 2 completed
- **Files modified:** 3 (`docs/literate/restricted_branch_flow.jl` new, `docs/make.jl`, `docs/src/api.md`)

## Accomplishments

- **The literate page tells the TRUE, revised story**, not the RESEARCH.md's original single-mechanism plan: it opens motivating from the previous page's EXACT-04 finding, states Theorem 1's C1/C2 conditions and Theorem 2's fix, live-recomputes a citable (non-fabricated) `ε_measured` while EXPLICITLY deferring C1's full symbolic verification, solves all three formulations (`ConvexBranchFlow(rtol_exact=1.0)`, `ACPowerFlow()`, `RestrictedBranchFlow()` at its bare default), shows the free PF-04 signal collapsing `10.4377... → 2.080e-8`, calls `assert_restriction_exact!` live and prints its full report (`ac_feasible = true`, `matches_ac_optimum = false`, `optimality_loss ≈ -1.4326`), documents the fallback semantics WITHOUT triggering it (D-09, the cert passes on this fixture), and closes citing the quarantined 5-seed spike evidence.
- **Every number on the page is live-recomputed at doc-build time** — confirmed by inspecting the built HTML output: `ε_measured = 0.005811069127373614` (exactly matches plan 20-01's measured value), `ctx_socp.meta[:socp_maxgap] = 10.437737223498573`, `ctx_restricted.meta[:socp_maxgap] = 2.080395211699962e-8` (matches plan 20-02's `2.08e-8`), and `restriction_report = (ac_feasible = true, matches_ac_optimum = false, optimality_loss = -1.4325921942337345, obj_gap = -0.5625114149354431, ...)` (matches plan 20-03's Addendum-revised verdict exactly).
- **`docs/make.jl` registers the new page** in both the `Literate.markdown` loop (immediately after `ac_oracle.jl`) and the `Models` pages list (immediately after "Rung 3: AC-Exactness Oracle").
- **Fixed a genuine blocking `checkdocs = :exports` failure** (Rule 3): `RestrictedBranchFlow`, `assert_restriction_exact!`, and `ac_dual_fallback_price`'s docstrings were never wired into any `@autodocs` `Pages` list in `docs/src/api.md` — T-20-15's mitigation claim ("api.md's existing @autodocs block already sweeps the whole module") was INCORRECT; the blocks are scoped per-file via explicit `Pages` lists, not a module-wide sweep. Fixing this ALSO surfaced (and required fixing) a pre-existing Phase 19 gap: `FourQuadBESS`, `ReactiveMode`, `normalize_reactive_mode`, and `assert_4q_complementarity!` had the identical problem, left over from Phase 19's own plans. Since `checkdocs = :exports` is a single GLOBAL gate over the whole `TSODSO` module (not scoped per literate page), the docs build could not pass without fixing both.
- **Full-suite acceptance run**: `julia --project=. -e 'import Pkg; Pkg.test()'` (background, 18m21.4s) — **2546 passed / 0 failed / 3 pre-existing broken / 2549 total**, exactly matching plan 20-04's own closing baseline (this plan adds zero new test items — Task 1 is docs-only, Task 2 is verification-only), confirming zero default-path drift across the entire phase (OVR-01..04).

## Task Commits

1. **Task 1: docs/literate/restricted_branch_flow.jl + docs/make.jl registration (+ docs/src/api.md blocking fix)** - `20ffb52` (docs)
2. **Task 2: Full-suite acceptance run** — no file changes (verification-only, per the plan's own empty `<files>` field); result recorded below and in this SUMMARY's own closing commit.

**Plan metadata:** SUMMARY commit (this commit, following).

## Files Created/Modified

- `docs/literate/restricted_branch_flow.jl` (NEW) — the OVR-04 literate rung page: fixture (verbatim from `ac_oracle.jl`) → Gan-Low condition narrative + live `ε` recomputation → three-formulation solve → free PF-04 signal → `assert_restriction_exact!` live call → fallback semantics (prose-only, D-09) → Finding.
- `docs/make.jl` — one new entry in the `Literate.markdown` loop, one new entry in the `Models` pages list.
- `docs/src/api.md` — three `@autodocs` `Pages` lists extended: `"devices/FourQuadBESS.jl"` (Prosumer Devices), `"powerflow/RestrictedBranchFlow.jl"` (Power-Flow Formulations), `"models/restriction_exactness.jl"`, `"models/ac_dual_fallback.jl"`, `"models/complementarity_4q.jl"` (Models & Centralized Solve), `"admm/ReactiveMode.jl"` (ADMM Decomposition).

## Decisions Made

See `key-decisions` in frontmatter. In prose: (1) rather than deriving the paper's exact 2×2 `A₁·u₂` worked-example formula for C1 — which RESEARCH.md's own Open Question #2 flagged as NOT independently re-derived with confidence this session — the page live-recomputes the SAME measured `ε` quantity plan 20-01 already validated, using the identical `recover_lossfree_shadow_voltage`-based recipe inlined here, and states in prose exactly what is deferred versus what is a citable literature-grounded expectation (Gan-Low's own Section VI empirical finding). This satisfies D-12's requirement for a NEW "Gan-Low condition" subsection without fabricating a number. (2) The `checkdocs = :exports` failure (see Deviations) required fixing `docs/src/api.md` beyond this plan's own three new files, because the gate is module-global.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `docs/make.jl docs/make.jl` build failed with `checkdocs = :exports` errors for orphaned exported docstrings, including this plan's own three new symbols AND a pre-existing Phase 19 gap**

- **Found during:** Task 1's own `<verify>` command (`julia --project=docs docs/make.jl`).
- **Issue:** `makedocs` reported 8 docstrings "not included in the manual": this plan's own `RestrictedBranchFlow`, `assert_restriction_exact!`, `ac_dual_fallback_price` (plans 20-02/20-03/20-04's exports, never wired into any `@autodocs` `Pages` list in `docs/src/api.md`), PLUS 5 pre-existing Phase 19 symbols (`FourQuadBESS` ×2 methods, `ReactiveMode`, `normalize_reactive_mode`, `assert_4q_complementarity!`) that had the identical problem, left over from Phase 19's own plans. Confirmed via a controlled experiment (stashing this plan's own two file changes and re-running the build): the Phase 19 symbols were ALREADY orphaned before this plan touched anything — this plan's threat model entry T-20-15 ("api.md's existing @autodocs block already sweeps the whole module, requiring no per-symbol registration") was based on an incorrect premise; the `@autodocs` blocks are scoped per-file via explicit `Pages =` lists, not a module-wide sweep.
- **Fix:** Added the three new Phase 20 files' paths to their respective existing `@autodocs` `Pages` lists in `docs/src/api.md` (`powerflow/RestrictedBranchFlow.jl` → Power-Flow Formulations; `models/restriction_exactness.jl`, `models/ac_dual_fallback.jl` → Models & Centralized Solve). Because `checkdocs = :exports` is a SINGLE GLOBAL gate over the whole `TSODSO` module (not scoped per literate page or per plan), the docs build could not exit 0 without ALSO fixing the pre-existing Phase 19 gap — added `devices/FourQuadBESS.jl` (Prosumer Devices), `admm/ReactiveMode.jl` (ADMM Decomposition), and `models/complementarity_4q.jl` (Models & Centralized Solve).
- **Verified:** Re-ran `julia --project=docs docs/make.jl` — exits 0, `docs/src/generated/restricted_branch_flow.md` produced, no `:missing_docs` or `:example_block` errors.
- **Files modified:** `docs/src/api.md`.
- **Commit:** `20ffb52` (folded into Task 1's commit; discovered and fixed within the same task, before committing).

**2. [Rule 1 - Bug] `using JuMP` fails in the literate page — `docs/Project.toml` does not list JuMP as a direct dependency**

- **Found during:** Task 1's first `<verify>` run — `ArgumentError: Package JuMP not found in current path` inside the first `@example` block.
- **Issue:** The literate page needs JuMP's `value()` function to read solved variable values (mirroring `docs/literate/socp_applicability.jl`'s own pattern), but `docs/Project.toml`'s `[deps]` only lists `CairoMakie`, `Documenter`, `Literate`, `TSODSO` — not `JuMP` directly.
- **Fix:** Changed `using JuMP` to `using TSODSO.JuMP` — the exact idiom `docs/literate/socp_applicability.jl` already uses to access JuMP's `value()` without adding JuMP as a direct docs dependency (TSODSO itself depends on JuMP; `TSODSO.JuMP` accesses it as a re-exported submodule reference).
- **Verified:** Re-ran the build — the `value()` calls resolve correctly, no further `UndefVarError`.
- **Files modified:** `docs/literate/restricted_branch_flow.jl`.
- **Commit:** `20ffb52` (folded into Task 1's commit; caught and fixed before committing).

**3. [Rule 1 - Bug] Broken `[Rung 3: AC-Exactness Oracle](@ref)` page-title cross-reference produced a spurious cross-reference warning**

- **Found during:** Task 1's build verification — `Cannot resolve @ref for md"[Rung 3: AC-Exactness Oracle](@ref)"` (resolved to a nonsensical `Base.:` binding).
- **Issue:** The opening paragraph linked to the previous page using its `pages =` sidebar label ("Rung 3: AC-Exactness Oracle"), but Documenter's page-heading `@ref` resolution matches the page's actual markdown `#` heading text ("Rung 3 — AC-Exactness Oracle: Certifying the SOCP Relaxation Against a True Nonconvex AC-OPF"), not the sidebar label — the mismatch caused the `@ref` to fail resolution. Non-fatal (`:cross_references` is in `warnonly`), but confusing and worth fixing cleanly.
- **Fix:** Replaced the broken `@ref` link with plain quoted prose ("Rung 3: AC-Exactness Oracle") — no hyperlink, but no broken cross-reference either.
- **Verified:** Re-ran the build — no `Cannot resolve @ref` warning for this page.
- **Files modified:** `docs/literate/restricted_branch_flow.jl`.
- **Commit:** `20ffb52` (folded into Task 1's commit).

---

**Total deviations:** 3 auto-fixed (1 Rule 3 blocking `checkdocs` registration fix spanning this plan's own files plus a pre-existing Phase 19 gap, 2 Rule 1 bug fixes in the new literate page itself).
**Impact on plan:** All three fixes were necessary for Task 1's own `<verify>`/`<done>` criteria (`docs/make.jl` must exit 0) to be satisfiable at all — none were scope creep beyond what was needed to make this plan's own deliverable build. No architectural changes; no Rule 4 escalations.

## Issues Encountered

None beyond the documented deviations above. No auth gates. The full-suite log contains the same benign, pre-existing `gitpatch`/`git diff` warnings from `DrWatson`'s provenance tagging running inside a git worktree that plan 20-04's summary already documented — unrelated to this plan's changes, caught and handled gracefully by `DrWatson` itself (never surfaced as a test failure).

## Known Stubs

None — the literate page is fully wired to real, already-existing infrastructure (`RestrictedBranchFlow`, `assert_restriction_exact!`, `ac_dual_fallback_price`, `recover_lossfree_shadow_voltage`, all from plans 20-01..04) with no placeholder data paths. The fallback semantics section is deliberately prose-only (does not trigger `ac_dual_fallback_price`) per D-09 and the plan's own explicit instruction — documented as intentional, not a stub.

## Threat Flags

None — this plan's only new surface is a documentation page (`docs/literate/restricted_branch_flow.jl`) executed entirely locally during `makedocs`, matching the plan's own threat model's trust-boundary description exactly (T-20-13/T-20-14/T-20-15, all addressed above). No new network endpoint, auth path, file access, or schema change was introduced.

## Verification

- Task 1 acceptance-criteria greps: all 5 PASSED (`# ## The Gan-Low condition` subsection present; `RestrictedBranchFlow()` bare-default call present; `assert_restriction_exact!` present; `restricted_branch_flow` appears twice in `docs/make.jl`; `docs/src/generated/restricted_branch_flow.md` exists after a clean rebuild).
- `julia --project=docs docs/make.jl`: **exits 0**, `docs/src/generated/restricted_branch_flow.md` produced, no `:missing_docs`/`:example_block` errors, no cross-reference warning attributable to the new page.
- Live-computed values inspected directly in the built HTML output (`docs/build/generated/restricted_branch_flow.html`), confirming every number matches the prior plans' documented measurements exactly:
  - `lemma1_mingap = 0.0`, `ε_measured = 0.005811069127373614` (plan 20-01's exact value)
  - `ctx_socp.meta[:socp_maxgap] = 10.437737223498573` (matches the "≈10.4" narrative)
  - `ctx_restricted.meta[:socp_maxgap] = 2.080395211699962e-8` (matches plan 20-02's `2.08e-8`)
  - `restriction_report = (ac_feasible = true, matches_ac_optimum = false, optimality_loss = -1.4325921942337345, obj_gap = -0.5625114149354431, hours = [...])` (matches plan 20-03's Addendum-revised verdict, `optimality_loss ≈ -1.4326`)
- **Full suite** (`julia --project=. -e 'import Pkg; Pkg.test()'`, background, 18m21.4s): **2546 passed / 0 failed / 3 pre-existing broken / 2549 total** — EXACTLY matches plan 20-04's closing baseline (this plan adds zero new tests). Confirmed via the `Test Summary` table at the log's tail (`Package | 2546 3 2549 18m21.4s`, `Testing TSODSO tests passed`). Zero regressions across the entire phase.

## Self-Check: PASSED

- `docs/literate/restricted_branch_flow.jl` exists: FOUND.
- `docs/src/generated/restricted_branch_flow.md` exists after a clean rebuild: FOUND.
- `docs/make.jl` contains `restricted_branch_flow` twice (Literate loop + pages list): FOUND.
- `docs/src/api.md` contains the six new `Pages` entries (`RestrictedBranchFlow.jl`, `restriction_exactness.jl`, `ac_dual_fallback.jl`, `FourQuadBESS.jl`, `ReactiveMode.jl`, `complementarity_4q.jl`): FOUND.
- Commit `20ffb52` exists in `git log`: FOUND.
- Full-suite run: **2546 passed / 0 failed / 3 pre-existing broken / 2549 total (18m21.4s)** — FOUND (log tail: `Package | 2546 3 2549 18m21.4s`).

## Next Phase Readiness

**Phase 20 (overvoltage-capable relaxation) is COMPLETE.** All four requirements (OVR-01 `RestrictedBranchFlow`, OVR-02 `assert_restriction_exact!`, OVR-03 `ac_dual_fallback_price`, OVR-04 this literate page) are independently satisfied and verifiable in `src/`, `test/`, and `docs/`. The full test suite is green end to end (2546/0/3/2549) with zero default-path drift across the entire phase. Terminology correction for STATE.md's next update, per RESEARCH.md's Open Question #1 (RESOLVED): this phase's fixture is `Phase4Fixtures.high_pv_feeder()`, a purpose-built 3-bus radial fixture — it is NOT the 13-bus IEEE feeder, despite loose prior-project shorthand calling it "IEEE-13." All new code/docs across plans 20-01..20-05 consistently say "the EXACT-04 fixture" / "the high-PV stress fixture."

---
*Phase: 20-overvoltage-capable-relaxation*
*Completed: 2026-08-08*
