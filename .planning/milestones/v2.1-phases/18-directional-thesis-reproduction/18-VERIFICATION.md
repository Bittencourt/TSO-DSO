---
phase: 18-directional-thesis-reproduction
verified: 2026-07-26T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 18: Directional Thesis Reproduction Verification Report

**Phase Goal:** A defensible, literate reproduction of the *direction and magnitude-band* of the
thesis welfare/surplus result on real, public IEEE-123 data — explicitly framed as "directional,
public-data," never an exact-figure claim.
**Verified:** 2026-07-26
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A literate rung/doc page plus a gate-then-golden test reproduces the SIGN and a pinned magnitude-BAND (never a point value) of the thesis welfare/surplus result on real IEEE-123 data with reactive pricing and real impedances both active | ✓ VERIFIED | `test/test_thesis_repro.jl` primary `@testitem` asserts (in order, all hard): `ctx.meta[:socp_maxgap] < 1e-5`, `acct.dso > 0.0`, `fit_dso < 0.0`, `acct.prosumer < fb.prosumer_surplus`, `DSO_BAND_LO < acct.dso < DSO_BAND_HI` (0.0, 5.58855710237937). Re-ran the scoped `thesis_repro`-filtered `TestItemRunner` command live this session: **6/6 passed** (5 primary hard gates + 1 secondary non-gated), matching the SUMMARY's claimed numbers bit-for-bit (`acct.dso=3.7257...`, `fit_dso=-196.2164...`). `docs/literate/thesis_reproduction_ieee123.jl` live-executes the same `solve_welfare`/`fit_baseline`/`welfare_accounting`/`decompose_dlmp` seam; inspected the actually-built `docs/build/generated/thesis_reproduction_ieee123.html` and confirmed the rendered, executed output shows `dso = 3.7257047349195798` (identical to the test and script) — not a stale/hollow doc page. |
| 2 | Every citation of the reproduction number carries the fixed "directional, public-data" qualifier phrase | ✓ VERIFIED | `grep -c "directional, public-data"`: `scripts/thesis_case123_repro.jl`=3, `docs/literate/thesis_reproduction_ieee123.jl`=5, `docs/literate/thesis_reproduction_assumptions.jl`=7. Confirmed live in the rendered HTML build (`docs/build/generated/thesis_reproduction_ieee123.html` contains 11 occurrences post-render, i.e. the qualifier survives Documenter execution, not just literal source text). |
| 3 | A consolidated assumptions/reduction doc page enumerates the full chain (units resolution, reduction fidelity, component omissions, aggregator population, PV scenario) | ✓ VERIFIED | `docs/literate/thesis_reproduction_assumptions.jl` (140 lines) enumerates all 8 required sections: (1) units resolution, (2) Fortescue reduction fidelity, (3) omitted regulators/caps/switches, (4) aggregator population re-tune + rationale, (5) PV scenario, (6) welfare-ratio-vs-surplus-sign honesty-mandate paragraph (states plainly the +25% thesis magnitude does NOT transfer; measured ≈+0.045% here), (7) asymmetric voltage-binding caveat, (8) verbatim carry-forward of the `sign_flip_survives: false` sweep finding. Registered in `docs/make.jl` and confirmed present in the actually-built `docs/build/generated/thesis_reproduction_assumptions.html`. |
| 4 | Repeated-run stability is checked and documented BEFORE the golden band is pinned | ✓ VERIFIED | `scripts/repro_stability_check.jl` + committed `results/repro_stability_check/findings.txt` (read in full): flake rate 0/20; ±2-5% population-scale sweep with `sign_flip_survives: false` reported honestly (all 4 non-zero sweep points FAIL the SOCP-exactness gate outright, not hidden or narrowed); `RECOMMENDED BAND: DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937`. Plan `18-02` (`depends_on: ["18-01"]`) hard-codes this exact band verbatim in `test/test_thesis_repro.jl` lines 37-38 — git commit ordering (`9238b79`/`99f0e69` before `b27a21c`) and the `depends_on` wave structure confirm the measurement genuinely preceded the pin. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/repro_stability_check.jl` | N≥20 flake-rate + population-scale sweep, ≥150 lines | ✓ VERIFIED | Exists, defines both `count_failures` and `sweep_population_scale`, calls `solve_welfare`/`welfare_accounting`/`fit_baseline` unmodified. |
| `results/repro_stability_check/findings.txt` | Committed measurement artifact | ✓ VERIFIED | Read in full — contains flake-rate table, sweep table (with honest FAILED rows + error detail), `sign_flip_survives: false`, `RECOMMENDED BAND:` line matching exactly what Plan 18-02 pins. |
| `test/test_thesis_repro.jl` | Gate-then-golden `@testitem`(s), contains `thesis_repro` | ✓ VERIFIED | Both item names contain `thesis_repro`; primary item is 5 hard gates in order; secondary is non-gated `broken=`. Live re-run this session: 6/6 pass. `grep -c reactive_consensus` == 0 (Pitfall 3 confirmed absent). |
| `scripts/thesis_case123_repro.jl` | IEEE-123 promotion-source script, ≥150 lines | ✓ VERIFIED | 343 lines; qualifier count 3; no `reactive_consensus`; no sign-unsafe ratio (`welfare_dadp / ` grep confirms only a prose mention explaining why it's NOT used, never computed as a value). |
| `docs/literate/thesis_reproduction_ieee123.jl` | Live-executed literate rung page, ≥40 lines | ✓ VERIFIED | 125 lines; live-calls the real seam end-to-end; registered in `docs/make.jl`; confirmed rendered with real executed numbers in `docs/build/generated/`. |
| `docs/literate/thesis_reproduction_assumptions.jl` | Consolidated assumptions page, ≥30 lines | ✓ VERIFIED | 140 lines; all 8 required sections present; live-checked constants block (`@assert n_load_nodes == 85` etc.) confirmed non-hollow. |
| `docs/make.jl` | 2 new Literate render entries + 2 new nav entries, contains `thesis_reproduction_ieee123` | ✓ VERIFIED | `grep -c "thesis_reproduction_ieee123" docs/make.jl` == 2, `grep -c "thesis_reproduction_assumptions" docs/make.jl` == 2 (basename match; one render-tuple entry + one nav entry each). `docs/src/api.md` confirmed untouched (`git diff --stat` empty). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `test/test_thesis_repro.jl` | `src/pricing/welfare.jl welfare_accounting` | direct call | ✓ WIRED | Called in both `@testitem`s, live-run confirms non-degenerate values. |
| `test/test_thesis_repro.jl` | `results/repro_stability_check/findings.txt` | `DSO_BAND_LO`/`DSO_BAND_HI` constants | ✓ WIRED | Values `0.0`/`5.58855710237937` match findings.txt exactly, byte-for-byte. |
| `docs/make.jl` | `docs/literate/thesis_reproduction_ieee123.jl` | Literate render-loop tuple entry | ✓ WIRED | Present in `for src in (...)` loop and `pages=` nav; full `docs/make.jl` build confirmed to produce `docs/build/generated/thesis_reproduction_ieee123.html` with real executed output. |
| `docs/make.jl` | `docs/literate/thesis_reproduction_assumptions.jl` | Literate render-loop tuple entry | ✓ WIRED | Same as above; both pages present among 12 total generated HTML pages in `docs/build/generated/`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `docs/literate/thesis_reproduction_ieee123.jl` | `acct.dso`, `fit_dso`, `acct.prosumer`, `fb.prosumer_surplus` | live `solve_welfare`/`fit_baseline`/`welfare_accounting` calls on `ieee123_modified()` | Yes | ✓ FLOWING — confirmed by inspecting the actually-built `docs/build/generated/thesis_reproduction_ieee123.html`, which shows the executed `println` output `DADP DSO surplus = 3.725705 (directional, public-data)`, identical to the test file's and promotion script's numbers. |
| `test/test_thesis_repro.jl` primary item | same quantities | same live seam | Yes | ✓ FLOWING — re-ran the scoped filter live this session; 6/6 pass with real solved values printed via `@info`. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `thesis_repro`-tagged @testitems pass with real solved numbers | `JULIA_LOAD_PATH=... julia -e 'using TestItemRunner, TSODSO; TestItemRunner.run_tests(...; filter=ti->occursin("thesis_repro", ti.name))'` | `Pass: 6, Total: 6` (27.2s); secondary item's fallback path triggered as expected and its sign-flip check evaluated true | ✓ PASS |
| Docs build actually executed the literate pages (not stale) | Inspected `docs/build/generated/thesis_reproduction_ieee123.html` and `_assumptions.html` for evaluated output | Both contain live-executed numeric output matching the SUMMARY's claimed values | ✓ PASS |

### Probe Execution

Not applicable — this phase is a research-validation/docs phase, not a migration/tooling phase with `scripts/*/tests/probe-*.sh` conventions. No probes declared in PLAN/SUMMARY files. Step 7c: SKIPPED (no probe convention applicable).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REPRO-01 | 18-02, 18-03 | Literate rung/doc page + gate-then-golden test reproduces direction+magnitude-band with "directional, public-data" qualifier | ✓ SATISFIED | `test/test_thesis_repro.jl` primary item + `docs/literate/thesis_reproduction_ieee123.jl`, both verified live. |
| REPRO-02 | 18-01, 18-03 | Consolidated assumptions/reduction doc page + stability check before golden pin | ✓ SATISFIED | `results/repro_stability_check/findings.txt` (measured before `18-02` pinned the band, enforced by `depends_on`) + `docs/literate/thesis_reproduction_assumptions.jl`. |

REQUIREMENTS.md cross-check: both REPRO-01 and REPRO-02 marked `[x]` and mapped only to Phase 18 in the coverage table (12/12 v2.1 requirements, no orphans). No orphaned requirement IDs for this phase.

### Anti-Patterns Found

None. Scanned all 6 phase-created/modified files (`scripts/repro_stability_check.jl`, `test/test_thesis_repro.jl`, `scripts/thesis_case123_repro.jl`, `docs/literate/thesis_reproduction_ieee123.jl`, `docs/literate/thesis_reproduction_assumptions.jl`, `docs/make.jl`) for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|not yet implemented|coming soon` — zero matches. The advisory `18-REVIEW.md` (0 critical, 4 warnings, 2 info) flags real but non-blocking maintainability concerns:
- WR-01: the golden band's upper bound is derived from a single successfully-solved sweep point (the same point the test also gates on), so it functions more as a "no >50% regression at this exact point" check than a population-scale-validated tolerance — this is disclosed honestly in `findings.txt` and the assumptions page (Section 8), not hidden.
- WR-02: the IEEE-123 population-construction fixture is duplicated verbatim across 4 files with no automated drift check.
- WR-03: bare `catch e` in the stability script cannot distinguish solver flakiness from a masked programming bug (pre-existing pattern from `reactive_flake_rate.jl`, not new).
- WR-04: the word "robustly" in the assumptions page's Section 6 could be misread in isolation as population-scale robustness, which Section 8 (two sections later) clarifies is not the case.

None of these rise to blocker level — they are quality/robustness suggestions for a future phase, not gaps in Phase 18's stated goal. The phase's own honesty mandate is met: the `sign_flip_survives: false` finding is reported and carried forward transparently in both the test file's header comment and the assumptions page, not suppressed.

### Human Verification Required

None. All must-haves are mechanically verifiable (grep counts, live test re-run, inspection of actually-built Documenter HTML output) and were verified directly against the codebase in this session, not merely accepted from SUMMARY claims.

### Gaps Summary

No gaps. All 4 roadmap success criteria are independently verified against the actual codebase:
1. Live-reran `test/test_thesis_repro.jl`'s `thesis_repro`-filtered suite this session (6/6 pass) and inspected the actually-built docs HTML — both the gate-then-golden test and the literate page reproduce the sign + pinned band on real IEEE-123 data.
2. Qualifier phrase counts confirmed in source AND in the executed HTML build output (survives Documenter execution).
3. Assumptions page enumerates all 8 required elements, confirmed by direct read.
4. Stability check (`results/repro_stability_check/findings.txt`) is dated/committed via commits `9238b79`/`99f0e69`, strictly before the golden-band pin commit `b27a21c`, enforced by the `depends_on: ["18-01"]` plan wave ordering — genuinely measurement-before-pin, not just claimed.

The full-suite exit-code caveat noted in the task brief (2 pre-existing Aqua failures, unrelated to this phase) is accepted per the explicit instruction and confirmed consistent with the SUMMARY's reported counts (2348 passed / 2 failed / 3 broken, +6 new passes from `test_thesis_repro.jl`, zero new failures).

---
*Verified: 2026-07-26*
*Verifier: Claude (gsd-verifier)*
