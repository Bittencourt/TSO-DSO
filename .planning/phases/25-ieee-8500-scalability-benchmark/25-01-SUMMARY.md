---
phase: 25-ieee-8500-scalability-benchmark
plan: 01
subsystem: data
tags: [opendss, ieee8500, fortescue, per-unit, data-provenance, julia]

# Dependency graph
requires: []
provides:
  - Vendored, pinned-commit IEEE-8500 OpenDSS source (10 files) at scripts/data/ieee8500/
  - Dependency-free reduction script scripts/reduce_ieee8500_impedances.jl with --verify
  - Generated src/data/ieee8500_impedances.jl (6 const tables: MV/LV branch Ohms, xfmr edges,
    capacitor kvar, load kW, regulator/switch edge set)
affects: [25-02, 25-03, 25-04, 25-05, 25-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Line-by-line (never single cross-field regex) OpenDSS statement parsing — field order
      in the source text does not need to match a hardcoded regex sequence"
    - "assert-identical-then-keep-one dedupe for phase-collapsed parallel edges, generalized
      from reduce_ieee123_impedances.jl's LineRecord to a shared ImpedanceEdge type"
    - "parse_lower_triangular generalized to detect BOTH lower-triangular and full-matrix
      pipe-delimited conventions (the latter appears in Triplex_Linecodes.dss, never exercised
      by IEEE-123)"

key-files:
  created:
    - scripts/data/ieee8500/Master.dss
    - scripts/data/ieee8500/LineCodes2.DSS
    - scripts/data/ieee8500/Lines.dss
    - scripts/data/ieee8500/Transformers.dss
    - scripts/data/ieee8500/LoadXfmrCodes.dss
    - scripts/data/ieee8500/Triplex_Lines.DSS
    - scripts/data/ieee8500/Triplex_Linecodes.dss
    - scripts/data/ieee8500/Loads.dss
    - scripts/data/ieee8500/Capacitors.dss
    - scripts/data/ieee8500/Regulators.dss
    - scripts/reduce_ieee8500_impedances.jl
    - src/data/ieee8500_impedances.jl
  modified:
    - .planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md

key-decisions:
  - "Pinned the vendored source to commit 3b208397160213cae4a9e2d0a7d1aa3528ce26e1 (resolved
    from dss-extensions/electricdss-tst's master HEAD via git ls-remote), not the floating
    master ref the discovery fetch used"
  - "The 43 Lines.dss switch=y tie segments get D-13's near-ideal Assumption-A2 treatment,
    merged into IEEE8500_REGULATOR_EDGES alongside the 4 regulator banks + substation
    transformer — a plan-text gap fix (Rule 2): the plan's frontmatter must_haves truth
    explicitly requires 'Regulator AND switch segments' get this treatment, but Task 3's
    action text only named the regulator banks + substation transformer"
  - "parse_lower_triangular generalized to detect full-matrix (not just lower-triangular)
    pipe-delimited literals, since Triplex_Linecodes.dss uses the full-matrix convention"
  - "Triplex LV length (ft) to linecode base (kft) unit conversion applied explicitly
    (length_ft/1000) — a correctness requirement not flagged in 25-RESEARCH.md's prose"

# SCALE-01 intentionally NOT marked complete here: it also appears in 25-03's and 25-04's
# frontmatter requirements — the "committed fixture" SCALE-01 describes is the Feeder object
# built by ieee8500_modified() in 25-03, not yet realized by this plan's raw generated table.
# Deferred to whichever plan lands the last SCALE-01 contribution.
requirements-completed: []

# Metrics
duration: 80min
completed: 2026-08-21
---

# Phase 25 Plan 01: IEEE-8500 Data Vendoring & Reduction Summary

**Dependency-free OpenDSS-to-Julia reduction script for the IEEE-8500 balanced feeder, with a pinned-commit provenance chain and the corrected 3-winding transformer formula, producing a self-verifying generated impedance/load table (MV=2477, LV=1177, XFMR=1177, REG=48, CAP=4, LOAD=1177).**

## Performance

- **Duration:** ~80 min
- **Started:** 2026-08-21T08:57:00Z (approx.)
- **Completed:** 2026-08-21T09:16:26Z
- **Tasks:** 3
- **Files modified:** 12 created, 1 modified

## Accomplishments
- Vendored all 10 required IEEE-8500 OpenDSS source files at a pinned commit SHA, with sha256
  verification of the 9 previously-recorded checksums (zero upstream drift) plus a first-time
  checksum for `Triplex_Linecodes.dss`
- Built a dependency-free (Base + regex only) reduction script parsing MV lines, LV triplex,
  service transformers, regulators, switch ties, real per-load kW, and capacitor banks
- Implemented the CORRECTED 3-winding center-tap transformer reduction (D-05 REVISED:
  `R_total=ΣRs[1:3]`, `X_total=0.5(Xhl+Xht+Xlt)`), pinned-sanity-verified against CT5
  (`r_pct=3.00`, `x_pct=2.72`)
- Discovered and fixed two data-format surprises not flagged in prior research: a full-matrix
  (not lower-triangular) pipe-delimited linecode convention in `Triplex_Linecodes.dss`, and 2
  single-line inline-`r1=`/`x1=` linecode definitions in `LineCodes2.DSS`
- Generated and committed `src/data/ieee8500_impedances.jl` with all 6 const tables

## Task Commits

Each task was committed atomically:

1. **Task 1: Vendor pinned-commit OpenDSS source + update provenance record** - `9568b2d` (feat)
2. **Task 2: Reduction script Part A — topology parsing, dedupe, real per-load kW** - `8334329` (feat)
3. **Task 3: Reduction script Part B — transformer/regulator reduction, --verify, emit** - `707ea61` (feat)

**Plan metadata:** commit pending (this SUMMARY.md + REQUIREMENTS.md)

## Files Created/Modified
- `scripts/data/ieee8500/*.dss` (10 files) - Vendored IEEE-8500 OpenDSS source at pinned commit `3b208397160213cae4a9e2d0a7d1aa3528ce26e1`
- `scripts/reduce_ieee8500_impedances.jl` - Zero-dependency parser + reducer + `--verify` self-check + `emit_output`
- `src/data/ieee8500_impedances.jl` - Generated `const` tables (MV/LV branch Ohms, xfmr edges, capacitor kvar, load kW, regulator/switch edge set)
- `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` - Pinned the commit SHA, recorded fetch-verification date, added `Triplex_Linecodes.dss`'s checksum

## Decisions Made
- Pinned the vendored source to a real 40-char commit SHA (`3b208397160213cae4a9e2d0a7d1aa3528ce26e1`) resolved via `git ls-remote`, replacing the discovery fetch's floating `master` ref, per T-25-01's mitigation.
- Generalized `parse_lower_triangular` to detect BOTH the lower-triangular (row `i` has `i` values) and full-matrix (every row has `n` values) pipe-delimited conventions, since `Triplex_Linecodes.dss` uses the full-matrix form that `reduce_ieee123_impedances.jl` never had to handle.
- Applied the ft-to-kft length/linecode-base unit conversion for triplex LV segments (`length_ft/1000.0`) — required for correct LV impedance magnitudes; the mismatch between `Triplex_Lines.DSS`'s `units=ft` and `Triplex_Linecodes.dss`'s `units=kft` was not called out in `25-RESEARCH.md`'s prose.
- Merged the 43 `Lines.dss` `switch=y` tie segments into `IEEE8500_REGULATOR_EDGES` alongside the 4 regulator banks + substation transformer, all sharing D-13's near-ideal Assumption-A2 treatment (see Deviations below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Included the 43 `Lines.dss` `switch=y` tie segments in `IEEE8500_REGULATOR_EDGES`**
- **Found during:** Task 2/3 (topology parsing + regulator edge assembly)
- **Issue:** The plan's own frontmatter `must_haves.truths` states: "D-13: Regulator and switch segments carry the IEEE-123 near-ideal low-impedance treatment (Assumption A2 analog), and tap changing is not modeled." However, Task 2's action text scoped the inline-`r1=`/`x1=` parsing path to only `HVMV_Sub_connector` + the `CAP_*` capacitor jumpers, and Task 3's action text named only "the 4 regulator banks... plus the substation transformer" for `IEEE8500_REGULATOR_EDGES` — neither task text mentioned the 43 `switch=y` records in `Lines.dss`. Left unhandled, these 43 real, unique-bus-pair network edges (confirmed via independent cross-check: `Lines.dss` has exactly 2520 distinct bus-pair keys after dedupe, of which 43 are `switch=y`) would have been silently dropped from the topology entirely, contradicting the plan's own must-have and leaving a materially incomplete network for plan 25-03's `Feeder` construction.
- **Fix:** Added a third parsing branch to `parse_mv_lines` (checked first, before the linecode/inline-r1x1 branches, since `switch=y` records also contain a bare `R1=` token that could otherwise be misclassified) that extracts only the bus1/bus2 pair for `switch=y` records, and merged them into the same `Set{Tuple{String,String}}` that the regulator banks + substation transformer populate, all receiving the shared near-ideal Assumption-A2 treatment at fixture-build time (no real impedance value stored in this table for any of them, consistent with the plan's own emitted-header language).
- **Files modified:** scripts/reduce_ieee8500_impedances.jl
- **Verification:** `IEEE8500_REGULATOR_EDGES` has 48 entries (4 regulator/substation edges + 43 switch ties, with a `Set` naturally collapsing the regulator banks' 3-phase-record duplicates to 1 each — an independent Python cross-check confirmed `Lines.dss` alone has exactly 2520 distinct bus-pair keys after phase-suffix collapse, matching `IEEE8500_MV_BRANCH_RX_OHMS` (2477) + the 43 switch edges).
- **Committed in:** `707ea61` (Task 3 commit)

**2. [Rule 1 - Bug] Generalized `parse_lower_triangular` to handle a full-matrix pipe-delimited convention**
- **Found during:** Task 3 (running the full reduction against the real `Triplex_Linecodes.dss`)
- **Issue:** `reduce_ieee123_impedances.jl`'s `parse_lower_triangular` (specified for verbatim reuse by the plan) assumes every matrix literal is lower-triangular (row `i` has exactly `i` values). `Triplex_Linecodes.dss`'s two LV linecodes (`750_Triplex`, `4/0Triplex`) instead declare their 2x2 `rmatrix=`/`xmatrix=` as a FULL matrix (both rows have 2 values each, e.g. `"0.40995115 0.11809509 | 0.11809509 0.40995115"`) — a convention IEEE-123 never exercised. The verbatim function threw `ArgumentError: malformed lower-triangular matrix row 1 (expected 1 value(s), got 2)` on the real vendored file.
- **Fix:** Generalized `parse_lower_triangular` to detect the row-length pattern (either `1:n` for lower-triangular, or uniformly `n` for full-matrix) and parse accordingly, throwing loudly only if neither pattern matches.
- **Files modified:** scripts/reduce_ieee8500_impedances.jl
- **Verification:** Full `main()` run succeeds; LV branch table has 1177 entries with plausible Ω values (e.g. R1≈0.29 Ω/kft for `4/0Triplex` after Fortescue-reduction).
- **Committed in:** `707ea61` (Task 3 commit)

**3. [Rule 1 - Bug] Added a fallback to inline `r1=`/`x1=` single-line linecode definitions**
- **Found during:** Task 3 (running the full reduction against the real `LineCodes2.DSS`)
- **Issue:** 2 of `LineCodes2.DSS`'s 69 linecodes (`1P_1/0_AXNJ_DB`, `3P_1/0_AXNJ_DB`, referenced 113 times by `Lines.dss`) are defined as a single-line inline `r1=`/`x1=` positive-sequence pair rather than an `rmatrix=`/`xmatrix=` block. The verbatim block-only lookup threw `ArgumentError: could not find an rmatrix/xmatrix block for linecode.1p_1/0_axnj_db`.
- **Fix:** `parse_linecode_rx_by_name` now checks the single-line definition for an inline `r1=`/`x1=` pair first (returned directly, no Fortescue reduction needed since it's already positive-sequence), falling back to the matrix-block form otherwise.
- **Files modified:** scripts/reduce_ieee8500_impedances.jl
- **Verification:** Full `main()` run succeeds; MV branch table includes edges using both referenced codes.
- **Committed in:** `707ea61` (Task 3 commit)

**4. [Rule 1 - Bug] Applied the ft-to-kft length/linecode-base unit conversion for triplex LV segments**
- **Found during:** Task 2/3 (parsing `Triplex_Lines.DSS` against `Triplex_Linecodes.dss`)
- **Issue:** `Triplex_Lines.DSS` declares every record's `Length=` in `units=ft`, while `Triplex_Linecodes.dss` rates its `rmatrix=`/`xmatrix=` in `units=kft` (ohms per 1000 ft). Naively multiplying `R1_per_kft * length_ft` (mirroring the MV path's no-conversion-needed convention, where both files agree on `units=km`) would silently inflate every LV branch impedance by 1000x. This unit mismatch was not flagged in `25-RESEARCH.md`'s prose.
- **Fix:** Divided `length_ft` by 1000.0 before multiplying by the reduced R1/X1 in the LV branch computation.
- **Files modified:** scripts/reduce_ieee8500_impedances.jl
- **Verification:** LV branch Ω values are physically plausible (sub-Ohm per 50 ft triplex run, consistent with residential service-drop impedances) rather than 1000x too large.
- **Committed in:** `707ea61` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (1 missing critical, 3 bugs)
**Impact on plan:** All four fixes were required for correctness or to satisfy the plan's own stated must-have (D-13). None expand scope beyond what SCALE-01 and this plan's `must_haves` already require. No scope creep.

## Issues Encountered
None beyond the four deviations documented above — all were caught either by cross-referencing the plan's own frontmatter `must_haves` against the task action text, or by running the script against the real vendored data and letting it throw loudly (per the project's "throw loudly, never silently mis-shape" convention already established by `reduce_ieee123_impedances.jl`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
`src/data/ieee8500_impedances.jl` is committed and self-verified (`--verify` passes; `IEEE8500_XFMR_EDGES` has exactly 1177 entries; CT5 sanity-checks within tolerance). Plan 25-02/25-03 can now build `src/data/ieee8500.jl`'s `ieee8500_modified()`/`ieee8500_mv_modified()` fixture builders directly from these six tables via `include`, with no further reduction-script work needed. One open item for the fixture-builder plan to be aware of (not a blocker, just a fact to carry forward): the raw MV-only `Lines.dss` topology (2519 buses, 2520 edges after dedupe) has ONE more edge than a spanning tree needs (`edges = buses + 1`), meaning the real feeder is not a pure radial tree at the switch-tie level — whether `ieee8500_modified()`'s full topology (MV+LV+xfmr+regulator) resolves to exactly `buses-1` for `assert_radial`, or surfaces a genuine non-radiality finding requiring a documented decision, is unverified by this plan and is plan 25-03's construction-time concern.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- All 14 claimed files (10 vendored `.dss`, reduction script, generated table, updated provenance doc, this summary) verified present on disk.
- All 3 task commits (`9568b2d`, `8334329`, `707ea61`) verified present in `git log`.
