---
phase: 17-real-ieee123-impedances
verified: 2026-07-26T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 17: Real IEEE-123 Impedances Verification Report

**Phase Goal:** `ieee123.jl`'s topology is driven by real, standard, citable positive-sequence
impedances reduced from the public OpenDSS IEEE-123 dataset, and the case remains meaningful
(voltage-binding) for its intended purpose.
**Verified:** 2026-07-26
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | An offline, reproducible script parses the public OpenDSS IEEE-123 case and reduces 3-phase line-code matrices to positive-sequence R1/X1 via a documented Fortescue-averaging reduction, with PMD kept out of `Project.toml`'s runtime `[deps]` | ✓ VERIFIED | `scripts/reduce_ieee123_impedances.jl` read in full: zero `using` statements, regex-only parser (`parse_line_records`, `parse_lower_triangular`, `fortescue_reduce` implementing `R1 = mean(diag) - mean(offdiag)`), `--verify` self-check re-run live this session: `PASS: 12 linecodes ingested; linecode.1 R1=0.057967171666666664, X1=0.11875631333333338`. `grep -c "PMD\|PowerModelsDistribution" Project.toml` = 0 (no `[deps]`, `[weakdeps]`, or `[extensions]` entry). Vendored `.dss` files (`scripts/data/IEEE123Master.dss`, `IEEELineCodes.DSS`) each carry a `!`-comment provenance header (source URL + fetch date 2026-07-25). |
| 2 | `ieee123.jl` consumes the committed real positive-sequence impedances as a pure-data `const` table in place of synthetic values (topology untouched), with reduction assumptions/caveats documented | ✓ VERIFIED | `src/data/ieee123.jl` read in full: `include("ieee123_impedances.jl")` loads `IEEE123_BRANCH_RX_OHMS` (117 entries, confirmed by reading `src/data/ieee123_impedances.jl`); `ieee123_modified()`'s branch loop does `r_Ω, x_Ω = IEEE123_BRANCH_RX_OHMS[(p, c)]; r, x = to_pu_impedance(r_Ω, IEEE123_BASE), to_pu_impedance(x_Ω, IEEE123_BASE)` for non-switch edges — the old `IEEE123_LINE_R=0.005`/`IEEE123_LINE_X=0.0025` uniform scalars are gone (confirmed via `git show ecb2571`). Topology: `git diff d16095f..HEAD -- src/data/ieee123.jl` shows the `IEEE123_EDGES` array untouched and `IEEE123_SWITCH_EDGES`'s tuple content unchanged (only a docstring/format wrap changed around it) across the entire Phase-17 span — no edge was added, removed, or reordered. DATA PROVENANCE header documents the reduction assumptions (transposition, single-phase-lateral short-circuit, regulator/switch handling). |
| 3 | The real-impedance IEEE-123 case is verified to remain meaningful for its purpose (voltage-binding) — PV/aggregator population re-tuned and documented if required | ✓ VERIFIED | `test/test_ieee123_admm.jl`'s new `@testitem "ieee123 admm: voltage-binding margin (ieee123, crossval)"` computes `Vall = sqrt.(value.(ctx_c.meta[:pf_vars].v))` and asserts `vmin_solved <= 0.95`, `vmax_solved >= 1.005`, plus sanity floor `> 0.9`/`< 1.1` — a genuine numeric assertion, not a "solves without erroring" check. **Independently re-executed this session** (not merely trusted from SUMMARY): `JULIA_LOAD_PATH=... julia -e '... filter=ti->occursin("ieee123", ...)'` → live output `vmin_solved = 0.9487492294439277`, `vmax_solved = 1.010467974302812`, **649/649 assertions pass**, exactly matching the SUMMARY's claimed numbers. `test/fixtures_phase7.jl` documents the re-tune (`LOAD_SCALE_IEEE123: 0.03→0.05`, `PV_SCALE_IEEE123: 0.06→0.12`, `DEV_SCALE_IEEE123: 0.05→0.0833`) with an explicit before/after/broken-bound comment block directly above the constants — never touching impedance/topology files. The asymmetric finding (strong lower band, weak upper band capped by the SOCP-inexactness boundary Phase 15's EXACT-04 also documents) is honestly recorded in both the test file and the fixture file, not hidden. |
| 4 | Prior synthetic-fixture goldens are preserved as an independent parallel regression, or consciously re-pinned with an explicit before/after invariant-comparison rationale (voltage binding, exactness margin, iteration count) | ✓ VERIFIED | `test/fixtures_phase7.jl` lines ~55-91 carry a full "BEFORE → AFTER" documentation block naming all three re-tuned constants, the broken bound at the old triple (`assert_socp_exact!` threw, worst gap ratio 1.378), and the restored/re-verified behavioral bounds at the new triple (`res.iters<300`, `res.iters<=100`, `isapprox(res.welfare,...; rtol=1e-4)`, `res.exact_maxgap<1e-3`, DADP cross-validation, plus the new voltage-binding numbers) — this is the "consciously re-pinned with an explicit before/after invariant-comparison rationale" branch of SC4, satisfied in full (not the "parallel regression" branch, which was not attempted and is not required since the rationale branch is an explicit either/or). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/data/IEEE123Master.dss` | Vendored OpenDSS master file, offline-reproducible | ✓ VERIFIED | 225 lines, provenance header confirmed, `git check-ignore` shows not gitignored |
| `scripts/data/IEEELineCodes.DSS` | Vendored OpenDSS line-code file (exact case) | ✓ VERIFIED | 218 lines, provenance header confirmed |
| `scripts/reduce_ieee123_impedances.jl` | Dependency-free parser + Fortescue reduction + `--verify` | ✓ VERIFIED | Read in full; zero `using`; `--verify` re-run live, PASS |
| `src/data/ieee123_impedances.jl` | Generated `IEEE123_BRANCH_RX_OHMS` const table (117 entries) | ✓ VERIFIED | Read header + first 13 entries; generated-file provenance header present; keyed by original `IEEE123_EDGES` tuples |
| `src/data/ieee123.jl` | Real-data ingestion via `to_pu_impedance`, topology untouched | ✓ VERIFIED | Read in full; branch loop, DATA PROVENANCE header, docstring all consistent with real-data path |
| `test/test_ieee123.jl` | Pinned real-data spot-check `@testitem` | ✓ VERIFIED | New item asserts `(149,1)` branch pu r/x matches `to_pu_impedance(0.057967*0.4, ...)`/`to_pu_impedance(0.118756*0.4, ...)` |
| `test/test_ieee123_admm.jl` | Numeric voltage-binding margin `@testitem` | ✓ VERIFIED | Read in full; genuine `vmin_solved`/`vmax_solved` extrema assertions against documented thresholds |
| `test/fixtures_phase7.jl` | Re-tuned population scale + before/after rationale | ✓ VERIFIED | `LOAD_SCALE_IEEE123=0.05`, `PV_SCALE_IEEE123=0.12`, `DEV_SCALE_IEEE123=0.05*(0.05/0.03)`, documented |
| `docs/literate/ieee123_impedances.jl` | Literate reduction doc page (source, formula, units-trap, caveats) | ✓ VERIFIED | 122 lines read in full; worked `linecode.1` numeric example, units-trap citation, reduction caveats, ends with live `ieee123_modified()` call + `throw(ArgumentError(...))` radial check (WR-02 compliant, no `@assert`) |
| `docs/make.jl` | Page registered in Literate render loop + `pages=` nav | ✓ VERIFIED | `grep -c ieee123_impedances docs/make.jl` = 2 (render tuple + `"Models"` pages entry) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `scripts/reduce_ieee123_impedances.jl` | `scripts/data/*.dss` | `@__DIR__`-relative read | ✓ WIRED | `SCRIPT_DIR = @__DIR__`; `MASTER_DSS`/`LINECODES_DSS` built from it; live `--verify` run reads both files successfully |
| `src/data/ieee123.jl` | `src/data/ieee123_impedances.jl` | `include(...)` + `IEEE123_BRANCH_RX_OHMS[(p,c)]` lookup | ✓ WIRED | `include("ieee123_impedances.jl")` present; lookup used inside `ieee123_modified()`'s branch loop |
| `src/data/ieee123.jl` | `src/units/PerUnit.jl` (`to_pu_impedance`) | Ω→pu conversion at ingestion | ✓ WIRED | `to_pu_impedance(r_Ω, IEEE123_BASE)` / `to_pu_impedance(x_Ω, IEEE123_BASE)` called exactly at ingestion, never in the script |
| `test/test_ieee123_admm.jl` | `ctx_c.meta[:pf_vars].v` | `sqrt.(value.(...))` extrema sweep | ✓ WIRED | Confirmed via re-run: live `@info` line printed the extrema, test passed |
| `docs/make.jl` | `docs/literate/ieee123_impedances.jl` | Literate render loop entry | ✓ WIRED | `grep -c` = 2 (render tuple + pages nav) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `ieee123_modified()` branch r/x | `r, x` per non-switch branch | `IEEE123_BRANCH_RX_OHMS[(p,c)]` (generated const table, 117 real Ω entries from public OpenDSS data) | Yes — live `--verify` self-check + pinned `(149,1)` spot-check both confirm real, non-uniform values (not `0.005`/`0.0025` uniform placeholders) | ✓ FLOWING |
| `test_ieee123_admm.jl` voltage-binding testitem | `vmin_solved`, `vmax_solved` | `solve_welfare(feeder, ConvexBranchFlow(), aggs; ...)` on the real-impedance `ieee123_modified()` feeder | Yes — live re-execution this session reproduced the exact documented numbers (0.9487.../1.0104...) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Reduction script self-check | `julia --project scripts/reduce_ieee123_impedances.jl --verify` | `PASS: 12 linecodes ingested; linecode.1 R1=0.057967171666666664, X1=0.11875631333333338` | ✓ PASS |
| IEEE-123 test suite (filtered, live re-run, not from SUMMARY) | `JULIA_LOAD_PATH="test:.:@stdlib" julia -e '... filter=ti->occursin("ieee123", ti.name)'` | `Package | 649 649 | 2m39.6s`; `@info` line: `vmin_solved=0.9487492294439277, vmax_solved=1.010467974302812` | ✓ PASS |
| No PMD in runtime deps | `grep -n "PMD\|PowerModelsDistribution" Project.toml` | 0 matches | ✓ PASS |
| Topology byte-identical across Phase 17 | `git diff d16095f..HEAD -- src/data/ieee123.jl` (inspected `IEEE123_EDGES`/`IEEE123_SWITCH_EDGES` hunks) | No content change to either array (only comment/format reflow near `SWITCH_EDGES`) | ✓ PASS |

### Probe Execution

Not applicable — Phase 17 has no `scripts/*/tests/probe-*.sh` convention; verification used the project's own `--verify` self-check and TestItems suite instead (both re-run live above, not just trusted from SUMMARY.md).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|------------|--------------|--------|----------|
| IMPED-01 | 17-01, 17-04 | Offline reproducible script, Fortescue reduction, PMD kept out of runtime deps | ✓ SATISFIED | `scripts/reduce_ieee123_impedances.jl` + vendored `.dss` + live `--verify` PASS + `Project.toml` grep clean |
| IMPED-02 | 17-02, 17-04 | Real impedance const table consumed at ingestion, topology untouched, caveats documented | ✓ SATISFIED | `src/data/ieee123_impedances.jl` + `src/data/ieee123.jl` wiring + `git diff` topology check + literate doc page caveats |
| IMPED-03 | 17-03 | Case remains meaningfully voltage-binding; population re-tuned/documented if needed | ✓ SATISFIED | Numeric voltage-binding testitem, live-reproduced numbers, `fixtures_phase7.jl` before/after rationale |

No orphaned requirements — `REQUIREMENTS.md`'s traceability table maps exactly IMPED-01/02/03 to Phase 17, and all three are claimed across the four plans' frontmatter (`requirements-completed`).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/data/ieee123.jl` | 23 | "placeholder" (in prose) | ℹ️ Info | Narrative reference to the *retired* synthetic placeholder being replaced — not a live stub; the code path it describes is the new real-data path |
| `test/fixtures_phase7.jl` | 57, 64 | "placeholder" (in prose) | ℹ️ Info | Same — documents the *old* synthetic scale that was replaced; not a stub in the current code |

No `TBD`/`FIXME`/`XXX`/`HACK` markers found in any Phase-17-touched file. No empty-implementation patterns (`return null`, `=> {}`, hardcoded empty dicts feeding render paths) found — this is a data/test-generation phase, not a UI phase, and every artifact traced back to a live, non-trivial computation.

### Minor Documentation-Sync Note (non-blocking)

`ROADMAP.md`'s Phase 17 plan checklist still shows `17-03-PLAN.md` and `17-04-PLAN.md` as `[ ]` unchecked, even though both have completed SUMMARY.md files, all commits exist, and the underlying code/tests are verified working. This is bookkeeping drift in the roadmap checklist, not a gap in the delivered code — flagged for the phase-completion commit to reconcile, not a phase-goal blocker.

### Human Verification Required

None. Every must-have in this phase resolves to a numeric, grep-able, or live-re-executable check (parser self-check, topology diff, impedance lookup, voltage-binding assertion) — no visual, UX, or subjective-judgment items are in scope for a data-ingestion/test phase.

### Gaps Summary

No gaps. All four ROADMAP success criteria and all three IMPED requirements are verified against the actual codebase (not SUMMARY claims): the reduction script is genuinely dependency-free and self-verifying, `ieee123.jl` genuinely consumes real per-segment Ω data with topology proven untouched via `git diff` across the full Phase-17 commit span, and the voltage-binding re-verification is not only documented but was independently re-executed this session, reproducing the exact numbers claimed (`vmin_solved≈0.9487`, `vmax_solved≈1.0105`) with 649/649 assertions passing. The asymmetric voltage-binding finding (strong lower band, weak upper band bounded by the same SOCP-inexactness boundary Phase 15's EXACT-04 documents) is an honest, well-documented research finding, not a phase failure — Phase 18 should treat it as the new baseline, not the retired synthetic-era 0.92/1.08 figures.

The two pre-existing Aqua "Stale dependencies"/"Persistent tasks" failures (from uncommitted local `CairoMakie`/`Project.toml` drift, documented in project memory `local-project-toml-drift.md`) are out of scope for this phase — no Phase-17 commit touches `Project.toml`/`Manifest.toml`, confirmed via `git status --porcelain` showing zero diff on any Phase-17-relevant file.

---

*Verified: 2026-07-26*
*Verifier: Claude (gsd-verifier)*
