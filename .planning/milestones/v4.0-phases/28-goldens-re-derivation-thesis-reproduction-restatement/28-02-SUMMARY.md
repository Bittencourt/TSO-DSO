---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
plan: 02
subsystem: docs
tags: [julia, clarabel, socp-exactness, thesis-reproduction, literate-docs, cairomakie, typst]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    provides: "FIX-08 hybrid exactness floor, FIX-09/FIX-10 physics-only AC settlement for fit_baseline/MPC"
  - phase: 26-network-device-model-correctness
    provides: "FIX-01/FIX-02 Gan-Low default ConvexBranchFlow(), FIX-04 battery soc[T+1] extension"
provides:
  - "Measured (not assumed) disposition of the REPRO-01 population-point SOCP-exactness drift (F-27-05-2): PRECISION-ARTIFACT, confirmed by direct measurement, resolved by the SAME tol_gap overrides test/test_thesis_repro.jl already carries"
  - "Restated docs/literate/thesis_reproduction_ieee123.jl and thesis_reproduction_assumptions.jl with old-vs-new headline numbers and named causes (FIX-01/02, FIX-09/10)"
  - "Regenerated results/thesis_case123_repro/, results/thesis_caseA/ (6 figure pairs), results/repro_stability_check/findings.txt against the corrected Phase 26/27 model"
  - "Recompiled docs/writeups/thesis_caseA.pdf against the regenerated figures"
affects: [28-05-phase-closing-gate, thesis-reproduction-narrative]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Measure-first exactness-gate disposition: never raise τ_solver/ε; measure a tighter solver tol_gap and confirm via a throwaway script before touching any consumer file"
    - "'Restated in v4.0 (Phase 28)' prose callout with an explicit old-vs-new table + named FIX-0x cause, mirroring convex_branch_flow.jl's 'PM-01 (phase 26-18)' precedent"

key-files:
  created: []
  modified:
    - docs/literate/thesis_reproduction_ieee123.jl
    - docs/literate/thesis_reproduction_assumptions.jl
    - scripts/thesis_case123_repro.jl
    - scripts/thesis_caseA.jl
    - results/repro_stability_check/findings.txt
    - results/thesis_case123_repro/fig_dso_surplus_sign_flip.{pdf,png} (gitignored, regenerated on disk)
    - results/thesis_caseA/*.{pdf,png} (6 pairs, gitignored, regenerated on disk)
    - docs/writeups/thesis_caseA.pdf (gitignored, recompiled on disk)

key-decisions:
  - "Task 1 measurement (not assumption) verdicted PRECISION-ARTIFACT for both (b) solve_welfare/fit_baseline bare defaults and (c) thesis_case123_repro.jl's own fit_baseline call — all three residuals match already-documented Phase 26/27 precision-floor numbers almost exactly and are cleanly resolved by the SAME committed tol_gap overrides."
  - "scripts/thesis_case123_repro.jl's solve_welfare call (not explicitly named in this plan's own interfaces section) also needed the tol_gap override — verified empirically via the identical throw Task 1 measured on the same population/call signature; threaded through as a Rule 1 extension beyond the plan's literal text."
  - "Fixed a genuine DimensionMismatch crash in scripts/thesis_caseA.jl (Phase 26 FIX-04 made battery soc T+1-long; this pre-existing plotting script still assumed T) — Rule 1 auto-fix, mirrors scripts/demo_mpc_plots.jl's own soc[1:T] convention. This file is not in this plan's files_modified list but the fix was required to regenerate the figures Task 2 needed."
  - "typst compile requires --root . for docs/writeups/thesis_caseA.typ (its ../../results/ image references escape the default per-file sandbox root) — the plan's own <verify> block for Task 4 omits this flag and would fail exit 1 as written; documented here as a plan-script gap, not a content bug."

patterns-established:
  - "Old-vs-new headline-number restatement table format (Quantity | OLD | NEW | Named cause), now used in both thesis_reproduction_ieee123.jl and thesis_reproduction_assumptions.jl."

requirements-completed: [FIX-11]

# Metrics
duration: 37min
completed: 2026-09-30
---

# Phase 28 Plan 02: REPRO-01 Re-run + Restatement Summary

**Measured the REPRO-01 exactness-gate drift as a precision-floor artifact (not a genuine new inexactness), threaded the same tol_gap overrides through the live docs page and figure-regen scripts, and restated old-vs-new headline numbers with named causes — the DSO-surplus sign flip and prosumer-decrease claims are unchanged; only `fit_dso`'s magnitude moved (FIX-09/10's AC-settlement change), and the v2.1 "knife-edge-fragile" stability characterization no longer holds (flake rate 13/20 → 1/20, sign-flip survival 2/5 → 5/5 swept points).**

## Performance

- **Duration:** ~37 min
- **Started:** 2026-09-30T00:30:00Z (approx.)
- **Completed:** 2026-09-30T01:07:00Z
- **Tasks:** 4 (Task 1 measurement-only, no commit; Tasks 2-3 committed; Task 4 verified on-disk, no trackable diff)
- **Files modified:** 4 tracked (docs/literate x2, scripts x2) + 1 tracked artifact (findings.txt) + gitignored figure/PDF regeneration

## Accomplishments
- Measured (never assumed) that the REPRO-01 population-point SOCP-exactness drift flagged by Phase 27's F-27-05-2 is a PRECISION-ARTIFACT at all three bare call sites, confirmed by an independent throwaway script whose printed gap/ratio numbers match the already-documented Phase 26/27 residuals almost exactly (4.384e-6/19.25 for `solve_welfare`; 8.207e-7/2.50 for `fit_baseline`'s SITE-3).
- Threaded the identical committed `tol_gap_abs=tol_gap_rel=3e-9`/`1e-9` overrides into `docs/literate/thesis_reproduction_ieee123.jl` and `scripts/thesis_case123_repro.jl`, so both now execute live without throwing.
- Restated old-vs-new headline numbers with named causes in both docs pages: `fit_dso` moved from ≈-196.22 to ≈-286.11 (FIX-09/FIX-10's physics-only AC settlement changing the network-settlement term; `fit_prosumer` itself barely moves), `acct.dso` moved from ≈+3.7257 to ≈+3.7394 (FIX-01/FIX-02's Gan-Low default). The sign flip and prosumer-decrease claims are unaffected.
- Regenerated `results/thesis_case123_repro/fig_dso_surplus_sign_flip.{pdf,png}` and all 6 `results/thesis_caseA/*.{pdf,png}` figure pairs against the corrected model (fixing a genuine Phase-26-FIX-04-driven crash in `thesis_caseA.jl` along the way).
- Re-ran the 5-point stability sweep + 20-repeat flake-rate check at the measured `tol_gap=1e-9`: flake rate dropped from 13/20=0.650 (all `fit_baseline`) to 1/20=0.050, and `sign_flip_survives` flipped from `false` (2/5 points) to `true` (5/5 points) — the v2.1 "knife-edge-fragile" characterization is retired by measurement, restated as a genuinely positive finding.
- Recompiled `docs/writeups/thesis_caseA.pdf` against the freshly regenerated PNGs (`typst compile --root .`).

## Task Commits

1. **Task 1: Measure the REPRO-01 population-point drift disposition** — no commit (measurement only, throwaway script at `/tmp/phase28_measure_repro_drift.jl`, per plan's own `<files>` spec: "none committed")
2. **Task 2: Thread the measured override into the live consumer files, regenerate figures** - `0b28f99` (docs)
3. **Task 3: Re-run the stability sweep, finalize the restatement narrative** - `6c700c2` (docs)
4. **Task 4: Recompile docs/writeups/thesis_caseA.typ against the regenerated figures** - no commit (`.typ` unmodified; `.pdf` gitignored per `.gitignore:43`, verified via mtime comparison against the regenerated PNGs, not staged)

**Plan metadata:** this commit (docs: complete plan, includes this SUMMARY.md)

## Files Created/Modified
- `docs/literate/thesis_reproduction_ieee123.jl` - Threaded measured tol_gap overrides into `solve_welfare`/`fit_baseline`; added "Restated in v4.0 (Phase 28)" old-vs-new table
- `docs/literate/thesis_reproduction_assumptions.jl` - Added matching restatement section with the full fit_dso/fit_prosumer/acct.dso mechanism explanation
- `scripts/thesis_case123_repro.jl` - Threaded the same overrides into both its `solve_welfare` and `fit_baseline` call sites; regenerated its figure
- `scripts/thesis_caseA.jl` - Fixed a T vs T+1 SOC-length crash (Rule 1); regenerated all 6 figure pairs
- `results/repro_stability_check/findings.txt` - Freshly re-measured at `REPRO_TOL_GAP=1e-9`
- `results/thesis_case123_repro/*.{pdf,png}`, `results/thesis_caseA/*.{pdf,png}` - Regenerated on disk (gitignored)
- `docs/writeups/thesis_caseA.pdf` - Recompiled on disk (gitignored)

## Decisions Made
- Task 1's measurement is the hard gate before any consumer-file edit, per CONTEXT.md's locked "measure first" policy — executed literally: wrote and ran a throwaway script reproducing `test/test_thesis_repro.jl`'s `@testitem` body verbatim (both with its committed overrides and without any override), and separately measured `scripts/thesis_case123_repro.jl`'s own `fit_baseline` call site.
- All three measured gaps/ratios were classified PRECISION-ARTIFACT because they are cleanly resolved by the SAME overrides already committed for the identical fixture, and their magnitudes match already-documented Phase 26/27 residuals (F-27-05-2's 4.38e-6/19.25; `test_thesis_repro.jl`'s own header comment's 8.21e-7/2.50) almost exactly — never a new, invented tolerance, and never a raised `τ_solver`/`ε`.
- Extended the override to `scripts/thesis_case123_repro.jl`'s `solve_welfare` call even though the plan's own `<interfaces>` section named only its `fit_baseline` call site — verified empirically that the identical population/call signature throws under the same measured mechanism, so leaving it un-overridden would have made the script itself throw, defeating Task 2's must-have ("the live... calls execute without throwing").
- Fixed `scripts/thesis_caseA.jl`'s SOC-plotting crash even though the file is not in this plan's `files_modified` list — Rule 1 (auto-fix bugs) applies because without it, Task 2's own regeneration of `results/thesis_caseA/*` (explicitly in `files_modified`) could not complete.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `scripts/thesis_caseA.jl` crashed regenerating figA2 — Phase 26 FIX-04's `soc[T+1]` vs a T-long hour axis**
- **Found during:** Task 2's first run of `scripts/thesis_caseA.jl`
- **Issue:** `PVBattery`'s `soc` variable is `T+1` elements long since Phase 26 plan 26-03 (FIX-04). This script (pre-dating that change) plotted `batt9_soc` (25 elements) against `hours .+ 1` (24 elements), causing a `DimensionMismatch` that aborted the script before any of the 6 figure pairs after `figA` were written.
- **Fix:** `batt9_soc = Float64[value.(v9[3].soc)...][1:T]`, mirroring `scripts/demo_mpc_plots.jl:173`'s own already-established convention for the identical situation.
- **Files modified:** `scripts/thesis_caseA.jl`
- **Verification:** Re-ran the script; all 6 figure pairs now write successfully, no throw.
- **Committed in:** `0b28f99` (Task 2 commit)

**2. [Rule 1 - Bug] Throwaway measurement script's own soft-scope bug (Julia top-level `try`/`catch` shadowing)**
- **Found during:** Task 1's first run
- **Issue:** The measurement script (never committed to the repo) assigned to outer-scope verdict variables inside bare top-level `try`/`catch` blocks without an explicit `global` keyword on every branch; Julia's soft-scope rule silently created new local bindings on some branches, so the FINAL summary lines printed "NO-THROW-AT-DEFAULTS" even though the actual measured evidence (printed directly inside the `catch` blocks, unaffected by the bug) correctly showed `THROW`. This is the exact class of bug documented in this project's own `testitem-try-scoping-trap` memory.
- **Fix:** Added explicit `global` to every assignment inside the `try`/`catch` blocks; reran for a clean, self-consistent log.
- **Files modified:** `/tmp/phase28_measure_repro_drift.jl` (not committed, per Task 1's own `<files>` spec)
- **Verification:** Re-ran; final "VERDICT:" lines now agree with the evidence printed inside each `catch` block.
- **Committed in:** N/A (throwaway script, never committed)

**3. [Rule 3 - Blocking, plan-script gap] `typst compile` requires `--root .`**
- **Found during:** Task 4
- **Issue:** The plan's own `<verify>` block for Task 4 invokes `typst compile docs/writeups/thesis_caseA.typ` with no `--root` flag. Run as written, this exits 1: `error: path "../../results/thesis_caseA/figA_dadp_vs_mem.png" would escape the project root` — typst's default sandbox root is the input file's own directory (`docs/writeups/`), and the `../../results/...` image references legitimately escape that.
- **Fix:** Ran `typst compile --root . docs/writeups/thesis_caseA.typ` from the repo root instead (matching the actual repo layout, not a content bug — no `.typ` prose edit was needed).
- **Files modified:** none (no code change; this is a documented invocation correction)
- **Verification:** Exit 0; `docs/writeups/thesis_caseA.pdf` regenerated and confirmed newer than every `results/thesis_caseA/*.png` via `find ... -newer`.
- **Committed in:** N/A (no trackable file changed; `.pdf` is gitignored)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking/plan-script gap)
**Impact on plan:** All three were necessary for the plan's own stated must-haves (figures regenerate; docs pages execute without throwing; the writeup recompiles) — no scope creep beyond what was required to satisfy this plan's own success criteria.

## Old vs New Headline Numbers (REPRO-01 restatement, per CONTEXT.md's locked framing)

| Quantity | OLD (pre-Phase-26/27) | NEW (this session, measured live) | Named cause |
|---|---|---|---|
| `acct.dso` (DADP DSO surplus) | ≈ +3.725705 | ≈ +3.739374 | FIX-01/FIX-02 (Phase 26): default `ConvexBranchFlow()` switched from thesis-literal lower-band restriction to Gan-Low upper-band restriction |
| `fit_dso` (FIT DSO surplus) | ≈ -196.216447 | ≈ -286.107696 | FIX-09/FIX-10 (Phase 27, plan 27-09): `fit_baseline`'s internal settlement moved to a genuine physics-only `ACPowerFlow(; limits=false)` — `fit_prosumer` itself is essentially unchanged (-40857.497 → -40857.497 to 8 sig. figs), so the whole shift is in the network-settlement term |
| Sign flip (`fit_dso<0`, `acct.dso>0`) | holds | **still holds** | unaffected |
| Prosumer decrease | holds | **still holds** | unaffected |
| Exactness gate at DEFAULT `tol_gap=1e-8` | untested at this exact point pre-Phase-27 | THROWS on `solve_welfare` (gap=4.384e-6, ratio=19.25) and `fit_baseline` SITE-3 (gap=8.207e-7, ratio=2.50) | FIX-08's tighter hybrid floor; VERDICT PRECISION-ARTIFACT, resolved by the pre-existing tol_gap overrides, confirmed by measurement this session |
| Flake rate (20-repeat, `REPRO_TOL_GAP=1e-9`) | 13/20=0.650 (all `fit_baseline`, 2026-08-23) | 1/20=0.050 (still `fit_baseline`, but 13x fewer) | FIX-09/FIX-10 closed the dominant fragility source |
| 5-point sweep `sign_flip_survives` | `false` (2/5 points, `fit_baseline` failed at δ=-0.02,0.00,0.05) | `true` (5/5 points) | same cause |
| Recommended `DSO_BAND_HI` | 7.211125525764296 | 7.229422341375 | ~0.25% widening from the sweep's slightly different δ=0.05 endpoint (4.819615 vs old 4.807417); the currently-committed `test/test_thesis_repro.jl` golden band is UNAFFECTED — measured `acct.dso=3.739` sits comfortably inside both |
| Aggregate welfare delta (secondary, fragile, never the primary claim) | ≈+0.045% | ≈+0.263% | same FIX-01/02/09/10 causes combined; still small and fragile, still explicitly labeled non-primary in `scripts/thesis_case123_repro.jl`'s own output |

**Verdict: the reproduction's actual pinned claim (DSO-surplus sign flip + prosumer-surplus decrease) reproduces unchanged under the corrected Phase 26/27 model. The v2.1 "knife-edge-fragile" population-scale-sensitivity characterization does NOT still hold — it is retired by measurement (5/5 points now solve cleanly and show the flip), a genuinely positive restatement, not a regression, per CONTEXT.md's "never silently drop or soften the caveat" instruction (the caveat is retired by evidence, not by omission).**

## Issues Encountered
None beyond the three auto-fixed deviations above, all resolved within this plan's own scope.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 28-05 (phase-closing gate) can fold this plan's restatement table directly into its own cross-phase findings/PROJECT.md update — the old-vs-new numbers and named causes above are ready to cite verbatim.
- `test/test_thesis_repro.jl`'s committed `DSO_BAND_HI=7.211125525764296` golden remains valid and untouched (out of this plan's scope); a future plan MAY choose to re-pin it to the freshly measured `7.229422341375` for tighter margin tracking, but this is not required — the current band still certifies the measured point correctly.
- No blockers for Plan 28-01/28-03 (disjoint files, ran independently this wave).

## Self-Check: PASSED

All claimed files verified present on disk (docs/literate x2, scripts x2, findings.txt, all
7 thesis_caseA figure pairs, thesis_case123_repro figure pair, docs/writeups PDF, this
SUMMARY.md). Both task commit hashes (`0b28f99`, `6c700c2`) verified present in `git log
--oneline --all`.

---
*Phase: 28-goldens-re-derivation-thesis-reproduction-restatement*
*Completed: 2026-09-30*
