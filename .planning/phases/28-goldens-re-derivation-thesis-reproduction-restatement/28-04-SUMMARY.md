---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
plan: 04
subsystem: docs
tags: [literate, documenter, mpc, ac-powerflow, cairomakie, restatement]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 03
    provides: "run_mpc's truth-settled realized_welfare/forecast_settled_welfare/regret split (FIX-10)"
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 09
    provides: "the FINAL FIX-10 settlement convention (ACPowerFlow(; limits=false) physics-only AC settlement + settlement_violations diagnostic, USER DECISION 2026-09-29), superseding 27-03/27-07's SOCP-based interim settlement"
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 04
    provides: "decompose_dlmp's .cone/.drop rename + Base.getproperty deprecation shim (FIX-07), already fully applied to docs/literate/pricing_dlmp.jl"
provides:
  - "docs/literate/mpc_rolling_horizon.jl restated with a 'Restated in v4.0 (Phase 28)' subsection in Section 3 (Regret) explaining FIX-10's truth-settled realized_welfare, the forecast_settled_welfare diagnostic, and the new settlement_violations diagnostic — with LIVE measured numbers from this page's own fixture, not hardcoded prose"
  - "scripts/demo_mpc_plots.jl header restatement note + baseline-case console diagnostics for forecast_settled_welfare/settlement_violations"
  - "A Rule-1 bug fix in scripts/demo_mpc_plots.jl's receding-plan SOC panel (DimensionMismatch from Phase 26's FIX-04 soc[1:(H+1)] recursion never being propagated to this plot's x-range)"
  - "results/demo_mpc_plots/*.{png,pdf} regenerated against Phase 27's corrected mpc_loop.jl"
  - "Explicit verdict: docs/literate/pricing_dlmp.jl's .cone/.drop + deprecated-alias restatement (FIX-07) is CONFIRMED already complete — verification only, not re-done"
  - "Explicit verdict: docs/literate/stochastic_pv_demand.jl's realized_welfare is an UNRELATED, STOCH-axis-specific concept (out-of-sample average over held-out draws, run_stochastic.jl) — no shared drift with run_mpc's FIX-10 semantics, no edit needed"
affects: [28-thesis-reproduction-restatement (this plan closes FIX-11's remaining deferred-restatement sub-clause), phase-36-code-export-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Restatement-in-place callout ('## Restated in v4.0 (Phase 28)') with LIVE re-executed numbers, matching this literate page's own established 'nothing below re-solves anything / every number is recomputed live' idiom — never a frozen prose claim describing stale semantics"

key-files:
  created: []
  modified:
    - docs/literate/mpc_rolling_horizon.jl
    - scripts/demo_mpc_plots.jl
  regenerated:
    - results/demo_mpc_plots/mpc_price_diagnostics.{pdf,png}
    - results/demo_mpc_plots/mpc_receding_plan.{pdf,png}
    - results/demo_mpc_plots/mpc_sweeps.{pdf,png}
    - results/demo_mpc_plots/mpc_welfare_regret.{pdf,png}

key-decisions:
  - "docs/literate/pricing_dlmp.jl (FIX-07's DLMP .cone/.drop rename) verified as ALREADY complete by direct read (lines 52-57's deprecated-alias note, plus every `.cone`/`.drop` reference throughout the page's math/prose/figure legend) — recorded as 'already satisfied, verified', NOT re-edited, per the plan's explicit anti-duplication instruction."
  - "docs/literate/stochastic_pv_demand.jl grepped for 'regret' (zero hits) and its own `realized_welfare` usage read in context (lines 220-244): this is `run_stochastic`'s OWN, unrelated out-of-sample uniform-weight average over 10 held-out re-solves of a FIXED first-stage schedule (STOCH-03/D-09, two-stage extensive-form) — a structurally different quantity from `run_mpc`'s rolling-horizon truth-settlement (FIX-10), confirmed independently of (and consistent with) 27-03-SUMMARY.md's own cross-plan observation 3. No edit needed; not added to this plan's touched-file list."
  - "Fixed (Rule 1 — blocking bug found while regenerating figures) a DimensionMismatch crash in scripts/demo_mpc_plots.jl's mpc_receding_plan SOC panel: Phase 26's FIX-04 closed PVBattery/FourQuadBESS's `soc[1:(H+1)]` recursion unconditionally (H+1=7 points at H=6), but this plot's x-range for the SOC line/terminal-target scatter was still the pre-FIX-04 H=6-long `p.t:(p.t+H-1)` — a genuine array-length mismatch that pre-dated this plan and had never been exercised/caught until this figure-regeneration run. Fixed by widening the SOC panel's x-range to `p.t:(p.t+H)` (length H+1, matching soc_plan) and the terminal-target scatter's x-coordinate to `p.t+H` (the hour soc[H+1] structurally represents); price/import/Tin panels (still genuinely H-long) were left untouched. This is a plotting-code fix only — no claim is made or implied about the semantic correctness of the day-ahead terminal-target VALUE assignment inside `src/experiments/mpc_loop.jl`/`src/models/mpc_window.jl` (out of this plan's file scope; `test/test_mpc_terminal.jl`, plan 21-04, is the existing correctness gate for that)."

patterns-established: []

requirements-completed: [FIX-11]

# Metrics
duration: ~35min
completed: 2026-09-29
---

# Phase 28 Plan 04: MPC Truth-Settlement Restatement + DLMP Closure Verification (FIX-11) Summary

**Restated `docs/literate/mpc_rolling_horizon.jl`'s and `scripts/demo_mpc_plots.jl`'s prose to describe Phase 27's truth-settled `realized_welfare`/`forecast_settled_welfare`/`settlement_violations` semantics (measured live: 3/19 published hours report a modest head-branch thermal overload on this fixture), regenerated all 4 MPC demo figures against the Phase-27-corrected `mpc_loop.jl`, fixed a genuine pre-existing DimensionMismatch crash in the SOC receding-plan panel along the way, and confirmed the DLMP `.cone`/`.drop` naming restatement (FIX-07) was already fully complete.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 2 (`docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl`); 8 regenerated artifacts (4 figures × 2 formats, gitignored)

## Accomplishments

- **Task 1 (verification only, zero edits):** confirmed `docs/literate/pricing_dlmp.jl` already carries the FIX-07 `.cone`/`.drop` rename throughout (math, prose, code, figure legend) plus its deprecated-alias note — direct re-read found nothing stale, so it was NOT re-edited. Grepped `docs/literate/stochastic_pv_demand.jl` for `"regret"` (zero hits) and read its own `realized_welfare` usage in context: it is `run_stochastic`'s own unrelated out-of-sample average over held-out re-solves (STOCH-03/D-09), not a consumer of `run_mpc`'s FIX-10 semantics — confirmed no shared drift, no edit needed.
- **Task 2:** added a "Restated in v4.0 (Phase 28)" subsection to `mpc_rolling_horizon.jl`'s §3 (Regret) stating FIX-10's truth-settlement contract (AC-physics-only settlement via `ACPowerFlow(; limits = false)`, the PV/battery A6 clip, throw-not-clamp state propagation) and displaying LIVE `r.forecast_settled_welfare` and a live-computed `settlement_violations` overload count — measured on this page's own 24-hour `:ieee13` fixture at **3 of 19 published hours** (abs_hour 10, 13, 14) reporting a genuine head-branch thermal overload (`max_overload_ratio` ≈ 1.02 / 1.004 / 1.001), zero voltage violations. Added the matching (shorter) restatement note to `scripts/demo_mpc_plots.jl`'s header, plus two new console-diagnostic lines (`forecast_settled_welfare`, a `settlement_violations` overload count) in its baseline-case printout.
- Regenerated all 4 `results/demo_mpc_plots/*.{png,pdf}` figure pairs against the current, Phase-27-corrected `src/experiments/mpc_loop.jl` — confirmed via direct execution (`julia --project=. scripts/demo_mpc_plots.jl`, exit 0) and file mtimes newer than the pre-run marker.
- **Found and fixed (Rule 1) a genuine, pre-existing crash** while regenerating: the `mpc_receding_plan` figure's SOC panel threw `DimensionMismatch` because Phase 26's FIX-04 extended `PVBattery`/`FourQuadBESS`'s window SOC recursion from `H` to `H+1` points (`soc[1:(H+1)]`, closing the terminal-target index), but this plotting code's x-range was never updated to match — a length-6-vs-7 mismatch. Fixed the plot's own x-range (not the underlying model), verified the full script now runs to completion.

## Task Commits

Each task was committed atomically:

1. **Task 1: Verify DLMP closure + check stochastic_pv_demand.jl for shared MPC drift** — no commit (verification-only, zero files touched; both verdicts recorded above and in this SUMMARY per the plan's own instruction not to re-edit an already-satisfied file).
2. **Task 2: Restate MPC truth-settlement semantics + regenerate figures** - `c17958b` (docs)

## Files Created/Modified

- `docs/literate/mpc_rolling_horizon.jl` — new "Restated in v4.0 (Phase 28)" subsection in §3 (Regret): explains `realized_welfare`'s truth-settlement (AC power flow, physics only, FIX-10), displays `r.forecast_settled_welfare` live, and displays a live-computed `settlement_violations` overload count with measured prose (3/19 hours, specific overload ratios) rather than a hand-waved "this fixture never overloads" claim (which would have been false — measured directly before writing the prose).
- `scripts/demo_mpc_plots.jl` — header restatement note (shorter form of the above); two new `@printf`/`println` diagnostics in the baseline-case console output (`forecast_settled_welfare`, `settlement_violations` overload count); the SOC receding-plan panel's x-range fix (Rule 1 bug, see Decisions).
- `results/demo_mpc_plots/{mpc_price_diagnostics,mpc_receding_plan,mpc_sweeps,mpc_welfare_regret}.{pdf,png}` — regenerated (8 files; gitignored per `/results/**/*.{pdf,png,svg,html}`, not committed to git, but present on disk and newer than the Phase-27 `mpc_loop.jl` commit).

## Decisions Made

See `key-decisions` in the frontmatter for full rationale. Briefly: DLMP restatement confirmed already-complete (not re-done); `stochastic_pv_demand.jl` confirmed unrelated (not edited); a genuine pre-existing SOC-panel DimensionMismatch bug fixed as an in-scope Rule-1 correction while regenerating figures, without touching the underlying `mpc_loop.jl`/`mpc_window.jl` model code (out of this plan's file scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed a DimensionMismatch crash in `scripts/demo_mpc_plots.jl`'s SOC receding-plan panel**
- **Found during:** Task 2's figure-regeneration step (`julia --project=. scripts/demo_mpc_plots.jl`)
- **Issue:** `lines!(axb, p.t:(p.t + H - 1), p.soc_plan; ...)` — `p.t:(p.t+H-1)` has length `H=6`, but `p.soc_plan = Float64[value.(v_soc.soc)...]` now has length `H+1=7`, because Phase 26's FIX-04 (`src/models/mpc_window.jl`) closes the battery SOC recursion unconditionally over the WHOLE window (`soc[1:(H+1)]`, terminal target at `soc[H+1]`) — a shape change this demo script's plotting code was never updated to match. Confirmed the length mismatch is real (not a transient/solver issue) by reading `src/models/mpc_window.jl`'s own docstring ("`soc[H + 1]` is a DIFFERENT index from the IC `soc[1]` even at `H = 1`") and `Thermostatic.jl`'s `Tin`/`p` declarations (still genuinely `1:T`/`1:H`-long, confirming ONLY the SOC panel was affected, not the price/import/Tin panels).
- **Fix:** Widened the SOC line's x-range to `p.t:(p.t + H)` (length `H+1`, matching `soc_plan`) and the terminal-target scatter's x-coordinate to `p.t + H` (the absolute hour `soc[H+1]` structurally represents). Left the day-ahead terminal-target VALUE assignment itself (`src/experiments/mpc_loop.jl`/`src/models/mpc_window.jl`) completely untouched — that is a separate, out-of-scope question of model correctness (not this plan's file scope; `test/test_mpc_terminal.jl`, plan 21-04, is its existing correctness gate).
- **Files modified:** `scripts/demo_mpc_plots.jl`
- **Verification:** Re-ran the full script after the fix; exited 0, all 4 figure pairs saved, console diagnostics printed as expected.
- **Committed in:** `c17958b` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug, found and fixed within this plan's own file scope while completing its own acceptance criteria).
**Impact on plan:** Necessary — without this fix, Task 2's own acceptance criterion ("regenerated figure files are newer than the Phase 27 `mpc_loop.jl` commit") could not be met at all (the script crashed before writing 3 of 4 figures). No scope creep: fixed only the plotting x-range in the one file already in this plan's `files_modified` list; did not touch `mpc_loop.jl`/`mpc_window.jl`.

## Issues Encountered

Initial drafting of the "Restated in v4.0" prose in `mpc_rolling_horizon.jl` guessed (before measuring) that the settlement-violations count on this fixture would be zero — measured it directly via a throwaway probe script BEFORE committing and found 3/19 hours genuinely overload (a modest, single-digit-percent head-branch thermal overload, no voltage violation). Rewrote the prose to report the measured count and specific per-hour ratios rather than publish an unverified/incorrect claim — consistent with this project's "never state a number without measuring it" convention.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-11's remaining deferred-restatement sub-clause (MPC truth-settlement + DLMP naming) is now closed: `docs/literate/mpc_rolling_horizon.jl` and `scripts/demo_mpc_plots.jl` accurately describe FIX-10's current (post-27-09) semantics with live-measured numbers; `results/demo_mpc_plots/` is regenerated against the Phase-27-corrected model; the DLMP `.cone`/`.drop` closure (FIX-07) is confirmed complete, not silently duplicated or skipped.
- No golden numbers were re-pinned by this plan (none of this plan's files carry a pinned/golden numeric literal — the restated numbers are all live-recomputed at doc-build/script-run time, per this page's own long-standing "nothing here is a frozen number" convention).
- Cross-plan awareness for the orchestrator/28-CROSS-PHASE-AUDIT: the SOC-panel DimensionMismatch bug fixed here (Rule 1) was a LATENT, pre-existing defect from Phase 26 (FIX-04) that had apparently never been exercised by re-running this specific script since FIX-04 landed — worth a note in the cross-phase audit that regenerating this figure is what caught it, not a dedicated test (no `@testitem` in `test/test_mpc_loop.jl`/`test/test_mpc_terminal.jl` exercises `scripts/demo_mpc_plots.jl`'s own plotting code directly).

---
*Phase: 28-goldens-re-derivation-thesis-reproduction-restatement*
*Completed: 2026-09-29*

## Self-Check

- `docs/literate/mpc_rolling_horizon.jl`: FOUND (modified, contains "Restated in v4.0 (Phase 28)")
- `scripts/demo_mpc_plots.jl`: FOUND (modified, contains "Restated in v4.0 (Phase 28)")
- `results/demo_mpc_plots/{mpc_price_diagnostics,mpc_receding_plan,mpc_sweeps,mpc_welfare_regret}.{pdf,png}`: FOUND (8 files present, regenerated this session)
- Commit `c17958b`: FOUND in `git log --oneline`

## Self-Check: PASSED
