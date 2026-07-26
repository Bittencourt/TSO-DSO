---
phase: 18-directional-thesis-reproduction
plan: 03
subsystem: docs-validation
tags: [julia, documenter, literate, thesis-reproduction, ieee123, honesty-mandate]

# Dependency graph
requires:
  - phase: 18-directional-thesis-reproduction
    plan: 01
    provides: "results/repro_stability_check/findings.txt's RECOMMENDED BAND + sign_flip_survives=false sweep finding, carried forward verbatim into this plan's assumptions page"
  - phase: 18-directional-thesis-reproduction
    plan: 02
    provides: "test/test_thesis_repro.jl's gate-then-golden REPRO-01 regression anchor, cited as the committed test artifact on the assumptions page"
provides:
  - "scripts/thesis_case123_repro.jl — the IEEE-123 real-impedance promotion-source script (DADP-vs-FIT DSO-surplus sign flip, reactive DLMP, \"directional, public-data\" qualifier)"
  - "docs/literate/thesis_reproduction_ieee123.jl — live-executed literate rung page (REPRO-01), registered in docs/make.jl"
  - "docs/literate/thesis_reproduction_assumptions.jl — consolidated assumptions/reduction chain page (REPRO-02), registered in docs/make.jl"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "\"directional, public-data\" qualifier convention: const REPRO_QUALIFIER + cite_repro(x) wrapper applied to every cited reproduction number in code (executed println/text! calls), NEVER embedded as a literal function call inside a Literate prose/comment line (comments are not executed — a fixed but instructive mistake caught and corrected mid-task: cite_repro(...) calls accidentally left inside `#`-prefixed prose lines render as literal text, not evaluated values; fixed by rewriting those paragraphs as plain bolded Markdown citations)"
    - "Literate page cross-references use the exact rendered header text (e.g. '[IEEE-123 Real Impedances — Public-Data Reduction](@ref)') to resolve cleanly under Documenter's warnonly :cross_references gate, matching the target page's actual `# Title` line rather than its shorter nav-tree label"

key-files:
  created:
    - scripts/thesis_case123_repro.jl
    - docs/literate/thesis_reproduction_ieee123.jl
    - docs/literate/thesis_reproduction_assumptions.jl
  modified:
    - docs/make.jl

key-decisions:
  - "Every reported number in the promotion script and both literate pages carries the 'directional, public-data' qualifier via a shared cite_repro(x) helper (redefined per-file, matching 18-PATTERNS.md's convention of no cross-page code sharing) — grep-checkable, not left to review discipline"
  - "The aggregate welfare delta (welfare_dadp - fb.social_fit) is printed ONLY as an explicitly-labeled 'secondary, fragile' line, never as the primary headline, and the sign-unsafe ratio welfare_dadp/welfare_fit is never computed or printed anywhere in the new script (Pitfall 1)"
  - "decompose_dlmp(ctx) is called on the plain solve_welfare ctx with no reactive_consensus kwarg anywhere in the three new files (Pitfall 3 — that mechanism is ADMM-only)"
  - "The assumptions page's Section 6 (welfare-ratio-vs-surplus-sign metric caveat) states plainly, without softening, that the thesis's +25% aggregate-welfare-ratio MAGNITUDE does not transfer to real public IEEE-123 data (measured +0.045% here) while the DSO-surplus sign flip is the robust, thesis-faithful signal — and Section 8 carries forward Plan 18-01's honest sign_flip_survives=false population-scale-sensitivity finding verbatim, without narrowing or omission"
  - "docs/src/api.md was left untouched — neither new file exports a src/ symbol, confirmed by an empty `git diff --stat docs/src/api.md` after the full build (avoids the Phase-15 checkdocs=:exports trap)"

patterns-established:
  - "Any future Literate page that wants to embed a per-number citation marker must call the wrapper function from EXECUTED code cells (println/text!/barplot label), never from inside a `#`-prefixed prose line — prose lines are literal Markdown text, not evaluated Julia"

requirements-completed: [REPRO-01, REPRO-02]

# Metrics
duration: ~55min
completed: 2026-07-26
---

# Phase 18 Plan 03: Live Literate Thesis Reproduction + Assumptions Chain Summary

**Promoted the phase's IEEE-123 real-impedance DADP-vs-FIT reproduction to a live-executed Documenter/Literate page (numbers cross-checked bit-for-bit against Plan 18-01's committed findings: DADP dso=+3.725705, FIT dso=-196.216447) and wrote a consolidated assumptions/reduction page that states plainly, without softening, that the thesis's +25% welfare-ratio magnitude does not transfer to real public data while the DSO-surplus sign flip does — completing ROADMAP Phase 18 success criteria 1-3.**

## Performance

- **Duration:** ~55 min (dominated by two Julia processes: the promotion script's ~2 min IEEE-123 SOCP solve + CairoMakie figure write, and the full `docs/make.jl` Documenter build re-executing all 12 rung pages, ~10-12 min)
- **Completed:** 2026-07-26
- **Tasks:** 3/3 completed
- **Files modified:** 4 (3 new: `scripts/thesis_case123_repro.jl`, `docs/literate/thesis_reproduction_ieee123.jl`, `docs/literate/thesis_reproduction_assumptions.jl`; 1 modified: `docs/make.jl`)

## Accomplishments

- **Task 1** — `scripts/thesis_case123_repro.jl` (343 lines): re-implements the Phase-17-retuned IEEE-123 population inline (mirroring `scripts/repro_stability_check.jl`'s established workaround for `Phase7Fixtures` being a no-op `@testmodule` outside `TestItemRunner`), solves the DADP welfare optimum + FIT baseline + reactive DLMP via the real `solve_welfare`/`fit_baseline`/`welfare_accounting`/`decompose_dlmp` entrypoints, prints every reported number with the `cite_repro`/`"directional, public-data"` wrapper, and writes `fig_dso_surplus_sign_flip.{pdf,png}` to `results/thesis_case123_repro/`. Ran end-to-end: exits 0, both figures written, `@assert acct.dso > 0.0 && fit_dso < 0.0` and `@assert acct.prosumer < fb.prosumer_surplus` both pass. Measured numbers (identical to Plan 18-01's pinned point): DADP dso=+3.725705, FIT dso=-196.216447, DADP prosumer=-41039.1293, FIT prosumer=-40857.4971, mean reactive DLMP=0.102886 pu, aggregate welfare delta=+0.0446% (printed only as an explicitly-labeled secondary/fragile line).
- **Task 2** — `docs/literate/thesis_reproduction_ieee123.jl` (125 lines): a live-executed Literate page narrating what's reproduced, why the aggregate welfare ratio is not the claim, then live-solving the same seam and ending with the terminal DSO-surplus tuple `(dso=3.7257047349195798, fit_dso=-196.21644693735288, prosumer=-41039.12932199452, fit_prosumer=-40857.497069915924)` — confirmed identical to the promotion script's own numbers by inspecting the rendered `docs/build/generated/thesis_reproduction_ieee123.html` after the full build. Registered in `docs/make.jl` (1 render-loop entry + 1 `Models` nav entry).
- **Task 3** — `docs/literate/thesis_reproduction_assumptions.jl` (140 lines): the consolidated assumptions/reduction narrative — units resolution and Fortescue reduction fidelity (cross-referenced to the `ieee123_impedances.jl` page, not re-derived), omitted regulators/caps/switches, the aggregator population re-tune and its Phase-17 asymmetric-voltage-binding rationale, the PV scenario, the HONESTY-MANDATE Section 6 (welfare-ratio-vs-surplus-sign metric caveat, stated plainly), Section 7's asymmetric voltage-binding caveat (`vmin_solved≈0.9487, vmax_solved≈1.0105`), and Section 8's verbatim carry-forward of Plan 18-01's `sign_flip_survives: false` sweep finding. Ends with a small live-checked code block (`length(ieee123_load_nodes())==85`, the re-tune constants re-asserted). Registered in `docs/make.jl`; ran the FULL `julia --project=docs docs/make.jl` build (all 12 pages, not just the 2 new ones) — completed cleanly (only the two pre-existing, unrelated Documenter warnings: the `repolink` navbar warning and one `@example` HTML-size fallback on `admm.md`), `docs/build/index.html` and both new pages' HTML written, `git diff --stat docs/src/api.md` confirmed empty.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write scripts/thesis_case123_repro.jl** - `5530b9f` (feat)
2. **Task 2: Promote to docs/literate/thesis_reproduction_ieee123.jl + register in docs/make.jl** - `396cd45` (docs)
3. **Task 3: Write docs/literate/thesis_reproduction_assumptions.jl, register it, verify full docs build** - `f1a27cd` (docs)

**Plan metadata:** (this commit, following SUMMARY.md write)

## Files Created/Modified

- `scripts/thesis_case123_repro.jl` — IEEE-123 real-impedance promotion-source script; DADP-vs-FIT DSO-surplus sign flip, reactive DLMP, "directional, public-data" qualifier on every cited number, never the sign-unsafe aggregate welfare ratio as primary metric.
- `docs/literate/thesis_reproduction_ieee123.jl` — live-executed literate rung page (REPRO-01), calling the real `solve_welfare`/`fit_baseline`/`welfare_accounting`/`decompose_dlmp` seam end-to-end.
- `docs/literate/thesis_reproduction_assumptions.jl` — consolidated assumptions/reduction narrative page (REPRO-02), enumerating the full 8-point chain including the honesty-mandate metric caveat and the sweep-robustness caveat.
- `docs/make.jl` — 2 new render-loop tuple entries + 2 new `Models` nav entries; `docs/src/api.md` untouched.

## Decisions Made

- **Qualifier applied only inside executed code, never inside Literate prose.** Mid-Task-3, an initial draft of the assumptions page embedded `cite_repro(...)` calls directly inside `#`-prefixed Markdown prose paragraphs (Sections 6-8) — since Literate comments are literal Markdown text, not evaluated Julia, this would have rendered the literal characters `", cite_repro("..."), "` in the built docs rather than a citation. Caught before running the Literate render command; fixed by rewriting those paragraphs as plain bolded Markdown text with the qualifier spelled out literally (`(directional, public-data)`), reserving the executable `cite_repro` helper for the page's actual code cells (the live-checked constants block).
- **Cross-references use exact rendered header text.** `[Text](@ref)` links to `ieee123_impedances.jl`'s and the assumptions page's headers were written matching the target's literal `# Title` line (e.g. `IEEE-123 Real Impedances — Public-Data Reduction`, not the shorter nav-tree label `IEEE-123 Real Impedances`) so the `warnonly = [:cross_references]` gate produces zero warnings rather than silently-tolerated broken links.
- **grep verification used the basename-without-extension convention, matching Task 2's established pattern**, for `docs/make.jl`'s registration count (`grep -c "thesis_reproduction_assumptions" docs/make.jl` == 2 — one render-tuple `.jl` entry, one nav `.md` entry). The plan's literal acceptance-criteria text appends `.jl` to the grep pattern, which (since `.` is an unescaped regex metacharacter matching any character) does not match the `.md` nav entry and undercounts to 1; the intended, functionally-verified state — exactly 2 registration entries — is confirmed by the basename-only grep and by direct inspection of the diff.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `cite_repro(...)` calls left inside Literate comment/prose lines instead of executed code**
- **Found during:** Task 3, drafting `docs/literate/thesis_reproduction_assumptions.jl`'s Sections 6-8
- **Issue:** Prose paragraphs describing the honesty-mandate caveat, the voltage-binding numbers, and the sweep-robustness finding were drafted with inline `", cite_repro("..."), "` fragments as if they were string-concatenation code — but these lines were `#`-prefixed Markdown comments, which Literate/Documenter render as literal text, not evaluated Julia. Left as-is, the built page would have shown the literal characters `", cite_repro("≈+0.045%"), "` instead of a clean citation.
- **Fix:** Rewrote the three affected paragraphs (Sections 6, 7, 8) as plain bolded Markdown text with the qualifier spelled out literally (e.g. `**≈+0.045% (directional, public-data)**`), reserving the executable `cite_repro` helper for the page's genuine code cells.
- **Files modified:** `docs/literate/thesis_reproduction_assumptions.jl`
- **Verification:** Re-ran `Literate.markdown(...)` standalone on the file (exit 0) and inspected the rendered `.md`/`.html` output — the qualifier now appears as clean prose, not literal function-call syntax.
- **Committed in:** `f1a27cd` (fixed before the first commit of this file; no separate remediation commit needed)

---

**Total deviations:** 1 auto-fixed (Rule 1 — a Literate authoring mistake caught before the file was ever committed or rendered into the published build).
**Impact on plan:** None on scope — the fix only corrects how the qualifier is displayed, not which numbers are cited or what the assumptions page claims.

## Issues Encountered

None beyond the auto-fixed Literate-authoring mistake above. Both long-running Julia processes (the promotion script's SOCP solve + the full Documenter build) completed without incident on the first run of each.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- ROADMAP Phase 18 success criteria 1-3 (literate page, "directional, public-data" qualifier on every citation, and the assumptions enumeration) are now complete; this was Phase 18's final (Wave 3) plan.
- The v2.1 Validation & Reproduction milestone's four target features (AC-exactness oracle, reactive-power consensus, real IEEE-123 impedances, directional thesis reproduction) are all now delivered across Phases 15-18.
- No blockers. Recommended next step: run `/gsd:complete-milestone` (or equivalent) to close out v2.1, per STATE.md's `Operator Next Steps`.

---
*Phase: 18-directional-thesis-reproduction*
*Completed: 2026-07-26*

## Self-Check: PASSED

- FOUND: scripts/thesis_case123_repro.jl
- FOUND: docs/literate/thesis_reproduction_ieee123.jl
- FOUND: docs/literate/thesis_reproduction_assumptions.jl
- FOUND commit: 5530b9f (Task 1)
- FOUND commit: 396cd45 (Task 2)
- FOUND commit: f1a27cd (Task 3)
- `grep -c "directional, public-data" scripts/thesis_case123_repro.jl` == 3 (>= 3 required)
- `grep -c "reactive_consensus" scripts/thesis_case123_repro.jl` == 0
- `grep -cE "welfare_dadp / |welfare_dadp/fb" scripts/thesis_case123_repro.jl` == 0
- `grep -c "directional, public-data" docs/literate/thesis_reproduction_ieee123.jl` == 5 (>= 2 required)
- `grep -c "directional, public-data" docs/literate/thesis_reproduction_assumptions.jl` == 7 (>= 2 required)
- `grep -c "thesis_reproduction_ieee123" docs/make.jl` == 2; `grep -c "thesis_reproduction_assumptions" docs/make.jl` == 2 (basename convention, matching Task 2's established check)
- `git diff --stat docs/src/api.md` empty (confirmed after full docs build)
- `julia --project=docs docs/make.jl` full build: exit clean, `docs/build/index.html` + both new pages' HTML written, no errors in build log
