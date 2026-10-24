---
phase: 40-784-house-thesis-population
verified: 2026-10-24T18:47:20Z
status: gaps_found
score: 5/6 must-haves verified
overrides_applied: 0
gaps:
  - truth: "The 784-house Case A case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance (POP-04 / roadmap SC-3)"
    status: partial
    reason: >
      Both engines RAN at full scale and their outcomes are committed
      (agreement.csv: centralized CERTIFIED at the recorded tol_gap_1e-10 solver
      path, welfare -378163.58894571784, gate untouched; ADMM loop CONVERGED at
      80 iterations) — but the battery-complementarity certificate REFUSES the
      converged ADMM point at the final consolidation (deterministic,
      error:CertificateError kind=:battery, reproduced 5x across ladder/sweep/
      agreement runs). Therefore NO welfare/price agreement deltas exist, no
      tolerance is stated, and the :slow agreement-band pin ships as a loud
      allowlisted @test_skip (test/expected_broken.txt) instead of a pinned
      band. The truth's first clause (both engines solve) is TRUE; its second
      clause (agreement within a measured, stated tolerance) is not satisfiable
      today. Deliberately left unchecked in REQUIREMENTS.md by plan 40-03 and
      routed here. Per repo policy the fix is NEVER a tolerance loosening.
    artifacts:
      - path: results/case_a_population/agreement.csv
        issue: "welfare_admm / welfare_abs_delta / welfare_rel_delta / price_max_abs_delta / price_max_rel_delta / recommended_* cells are EMPTY — no certified ADMM point exists at executor defaults"
      - path: test/test_population_case_a_agreement.jl
        issue: "the agreement-band assertions are a tracked @test_skip (allowlisted in test/expected_broken.txt), not a pinned gate-then-golden band"
    missing:
      - "A certified full-population ADMM point, so agreement deltas become measurable and the band can be pinned (re-measure via julia --project=. scripts/case_a_agreement.jl, then pin 10x observed delta floored at solver noise, then lift the skip)"
      - "Candidate fix path (a): solver-precision/certificate-noise seam at the ADMM consolidation battery gate — the converged product sits 0.04% over a ~1e-12 relative band at the per-house-divided battery scale (diagnosis in 40-02/40-03 summaries); requires a solve_admm solver-precision seam, currently absent"
      - "Candidate fix path (b): the Phase-26 eta<1 KKT-consistent round-trip backlog item (on_violation policy for the degenerate small-battery regime)"
      - "EXPLICITLY NOT a fix: loosening the exactness gate, the battery certificate band, or any tolerance (honesty policy, ROADMAP.md:53-55)"
---

# Phase 40: 784-House Thesis Population — Verification Report

**Phase Goal:** A researcher can build, solve and scale the thesis Case A population at its true 784-household size, reproducibly and with documented calibration.
**Verified:** 2026-10-24T18:47:20Z
**Status:** gaps_found (one precisely-scoped gap: POP-04's agreement band; all other must-haves verified in this verifier's own process)
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal's verbs are all delivered and independently reproduced here: the population **builds** (784 houses verified live), **solves** (both engines ran at full scale; the centralized point certifies — asserted green in this verifier's own slow-lane run), **scales** (measured threads sweep + population ladder, committed provenance-stamped CSVs), **reproducibly** (per-house hash seeding, structural rebuild equality, 52/52 targeted tests green in this run), and is **documented** (literate page live-measures composition; every figure this verifier recomputed matched exactly). What the goal does NOT yet deliver is the roadmap's SC-3 agreement claim: the decomposed leg's certificate refusal means no agreement tolerance is measurable or stated. POP-04 is the single open requirement.

### Observable Truths

| # | Truth (roadmap SC + POP mapping) | Status | Evidence |
|---|----------------------------------|--------|----------|
| 1 | SC-1 / POP-01: `:case_a_784` selector over the 10 IEEE-13 aggregator nodes; `:default` stays byte-identical | ✓ VERIFIED | `build_population(:case_a_784, ...)` branch (materialize.jl:547-593) builds exactly 10 bus-level Aggregators over buses 2-11 (live probe); `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)` (Scenario.jl:48); **whole-phase `git diff` over `src/` deletes exactly 3 lines** (the old dispatch guard x2 + selector tuple) — the `:default` fall-through body, `_default_house`, and every gate file (`src/welfare/`, `src/admm/`, `src/solvers/`) have an EMPTY diff; 52/52 targeted tests green in this verifier's own run (includes the `:default` structural regression item) |
| 2 | SC-2 / POP-02+POP-03: per-house seeding from (master seed, bus, house index); rebuild reproduces exactly; no two houses share a seed; household map available | ✓ VERIFIED | `_case_a_house_seed(s_pop, bus, idx) = Int(hash((s_pop, :house, bus, idx)) % typemax(UInt32))` (materialize.jl:403); live probe: 784/784 distinct seeds; rebuild structural `==` asserted by tests (52/52 this run); `case_a_household_map` (materialize.jl:711-774) returns 784 `@NamedTuple` rows (house, bus, aggregator, device_set, pv_group, house_index), bus-major 2→11, seed-independent (WR-01 fix verified in code + test); 3x2352 devices live-verified |
| 3 | SC-3 / POP-04: the 784-house case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance | ✗ FAILED | Both engines ran and are recorded (agreement.csv: `centralized_optimizer=tol_gap_1e-10`, `welfare_centralized=-378163.58894571784`, `admm_iters=80`, `admm_status=error:CertificateError`; all delta/band cells EMPTY). The ADMM loop converged but the battery-complementarity certificate refuses the converged point at consolidation — deterministically, 5x across independent runs. No agreement delta exists anywhere; no tolerance is stated; the band pin is a loud allowlisted `@test_skip`. Gate surfaces untouched: `git diff 68cafad..HEAD -- src/welfare/ src/admm/ src/solvers/` is EMPTY. Centralized-leg certification re-verified live: slow lane 11 pass / 1 allowlisted broken / 0 fail (2m44s, this verifier's own process) |
| 4 | SC-4 / POP-05: scaling report gives measured wall time vs threads and ADMM iterations vs population size (negative result valid) | ✓ VERIFIED | `threads_sweep.csv`: measured 593.37 s / 478.75 s / 410.83 s at -t 1/2/4, executor column serial\|parallel, full provenance (julia_version, blas_threads, seed, t_horizon) — speedup recomputed by this verifier: 1.239x / 1.444x (matches claims); `scaling_ladder.csv`: 6 measured rungs 10→784 houses, iters 2,4,5,5,91,80 with statuses incl. the honest `error:CertificateError` row (not dropped, not retried); subprocess driver (`run_case_a_scaling.sh`) runs one `julia -t N` process per leg with `|| exit $?` propagation; fast smoke 27/27 green in this verifier's own run (1m36s) |
| 5 | SC-5 / POP-06: documentation states composition (PV capacity, elastic/inelastic load, device mix) with calibration provenance and which Appendix E parameters are unavailable | ✓ VERIFIED | `docs/literate/case_a_population.jl` (425 lines): composition computed LIVE from the built population (no literal numerals for measured quantities), calibration provenance (per-house scale ÷ houses-per-bus, `:default` fractions, counts rule + residue tiebreak, hash-seeding rule), Appendix E table of 3 unavailable parameters each with its replacement rule; reads all three committed CSVs at build time (lines 245/317/348); registered at BOTH make.jl sites (lines 52, 101); zero solve calls (grep = 0). **This verifier recomputed the composition live: 784 houses, 784x3 devices, 26.6162 MWp PV, 3.19722 MW inelastic, 1000+500 MW elastic bounds, 2.5 MW / 10 MWh battery fleet — every figure matches the page's claims exactly.** Generated artifacts exist (`docs/src/generated/case_a_population.md` 19.7 KB, `docs/build/generated/case_a_population.html` 37 KB) |

**Score:** 5/6 must-haves verified (POP-01, POP-02, POP-03, POP-05, POP-06 VERIFIED; POP-04 FAILED/partial — see gap)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| POP-01 | 40-01 | 784 households over 10 IEEE-13 aggregator nodes via a new selector; `:default` byte-identical | ✓ SATISFIED | Selector branch + 10-aggregator roll-up live-verified; 3-line total src/ deletion diff; Scenario guard widened |
| POP-02 | 40-01 | Per-household hash seeding from (master seed, bus, house index); reproducible; no collisions | ✓ SATISFIED | `_case_a_house_seed`; 784/784 distinct seeds live-verified; structural rebuild `==` test green this run |
| POP-03 | 40-01 | Household map (house → bus, aggregator, device set, PV/non-PV group) | ✓ SATISFIED | `case_a_household_map` — 784 rows, all fields, pure + seed-independent (WR-01 fix verified) |
| POP-04 | 40-03 | Both engines at 784 houses agree on welfare and prices within a measured tolerance | ✗ BLOCKED | Centralized certified (tol_gap_1e-10 path, live re-verified); ADMM converged (80 iters) but certificate refuses → no deltas, no stated tolerance; band = loud tracked skip. Correctly left unchecked in REQUIREMENTS.md (`[ ]`, traceability "Pending"). Structured as the phase's single gap below |
| POP-05 | 40-02 | Scaling report: wall time vs threads; iterations vs population; measured not assumed | ✓ SATISFIED | Both CSVs committed with provenance; speedup recomputed 1.444x; ladder shows the measured iteration blow-up (5→91 between 390 and 584 houses); negative-result path implemented (honest stall recording) though the measured outcome was a modest positive |
| POP-06 | 40-04 | Composition documented with calibration provenance + Appendix E unavailability | ✓ SATISFIED | Literate page live-verified figure-by-figure; Appendix E table present; registered both sites |

**Orphaned requirements:** none — REQUIREMENTS.md maps exactly POP-01..POP-06 to Phase 40, and all six appear in plan frontmatter (40-01: [POP-01, POP-02, POP-03]; 40-02: [POP-05]; 40-03: [POP-04]; 40-04: [POP-06]).

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `src/experiments/materialize.jl` | `:case_a_784` branch + 4 helpers + `_case_a_rung_counts` + `case_a_household_map` | ✓ VERIFIED | 810 lines; all symbols present and live-exercised; `:default` body byte-identical |
| `src/experiments/Scenario.jl` | `SCENARIO_VALID_POPULATIONS` widened | ✓ VERIFIED | Line 48 `(:default, :case_a_784)`; guard auto-lists tuple; Scenario constructed with the selector in a live probe |
| `test/test_population_case_a.jl` | Fast testitems POP-01/02/03 | ✓ VERIFIED | 321 lines, 6 items, 55 assertions — **52/52 pass in this verifier's own run (29.8s)** |
| `scripts/case_a_scaling.jl` | Ladder + threads-sweep harness | ✓ VERIFIED | 443 lines; kwarg-only `solve_admm` with `parallel = Threads.nthreads() > 1`; honest stall recording; BLAS pinned; keyed CSV upsert |
| `scripts/run_case_a_scaling.sh` | Subprocess driver | ✓ VERIFIED | 54 lines; one `julia -t N` per leg; nonzero exits propagate; `--ladder-only`/`--sweep-only` |
| `results/case_a_population/scaling_ladder.csv` | ~6 measured rungs | ✓ VERIFIED | 6 rows + header; provenance columns; rung 6 carries the honest refusal row |
| `results/case_a_population/threads_sweep.csv` | 3 measured legs | ✓ VERIFIED | 3 rows; executor column; walls match claimed speedups |
| `scripts/case_a_agreement.jl` | Both-engines measurement | ✓ VERIFIED | 353 lines; default-then-tightened centralized leg; `TOL_GAP_PATH` symbol-parsing fix in place; CertificateError handler tightens SOLVER only |
| `results/case_a_population/agreement.csv` | The POP-04 record | ⚠️ PARTIAL | Row exists with centralized certification + ADMM refusal recorded; delta/band cells honestly empty (this IS the gap) |
| `test/test_population_case_a_agreement.jl` | `:slow` agreement testitem | ⚠️ PARTIAL | 111 lines; centralized leg + re-derived dual-sign anchor asserted (green this run); band = tracked skip |
| `test/expected_broken.txt` | Exact-key skip allowance | ✓ VERIFIED | Phase entry present with full blocker explanation + regeneration command |
| `test/test_population_case_a_scaling.jl` | Rung derivation + micro-ladder smoke | ✓ VERIFIED | 287 lines, 3 items — **27/27 pass in this verifier's own run (1m36s)**, fast/slow split per WR-02 |
| `docs/literate/case_a_population.jl` | Composition/calibration page | ✓ VERIFIED | 425 lines; live composition + 3 CSV reads + Appendix E; zero solve calls |
| `docs/make.jl` | Both registrations | ✓ VERIFIED | Literate tuple (line 52) + Experiments pages tree (line 101) |
| `scripts/README.md` | Index rows | ✓ VERIFIED | All three scripts indexed (lines 26, 27, 42) |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `Scenario.jl` | `materialize.jl` | selector tuple names what `build_population` dispatches | ✓ WIRED | Tuple matches dispatch exactly; live Scenario construction succeeded |
| `:case_a_784` branch | `generate_profiles` | per-house seed (never `seed + bus`) | ✓ WIRED | `_case_a_house_seed` hash tuple; distinctness test-enforced (would collapse to 10 under the bad idiom) |
| `:case_a_784` branch | `Aggregator` | bus-level roll-up (vcat devices, + Pdc) | ✓ WIRED | `reduce(vcat, ...)` / `reduce(+, ...)` at materialize.jl:582-590; satisfies the ADMM 1:1 guard |
| `case_a_scaling.jl` | `solve_admm` | kwarg-only, `parallel = nthreads()>1` | ✓ WIRED | Direct calls; no Scenario seam; ρ from `ADMM().ρ` |
| `case_a_scaling.jl` ladder | `:case_a_784` helpers | nested prefixes; 1.0 == full tripwire | ✓ WIRED | `_case_a_rung_counts`; structural tripwire proven live during the measured run |
| `run_case_a_scaling.sh` | julia subprocess legs | process-level thread count | ✓ WIRED | `-t 1` ladder + `-t 1/2/4` sweep legs, `|| exit $?` |
| `test_population_case_a_agreement.jl` | `agreement.csv` | band cited to measurement | ✓ WIRED | Header + skip message cite the CSV and regeneration command |
| `case_a_agreement.jl` | `solve_welfare` + `solve_admm` | both engines, same roll-up | ✓ WIRED | Same `aggs` object; CertificateError → solver tighten (gate untouched, src/ diff empty) |
| `case_a_population.jl` | `scaling_ladder.csv` | Base-only CSV read at build time | ✓ WIRED | Line 317 via `read_case_a_csv` |
| `case_a_population.jl` | `agreement.csv` | provenance-keyed row selection | ✓ WIRED | Line 245; WR-03 fix (keyed filter, growth-proof) verified in code |
| `docs/make.jl` | `case_a_population.jl` | Literate tuple + pages tree | ✓ WIRED | Both sites present; generated MD + HTML artifacts exist |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `docs/literate/case_a_population.jl` composition | `aggs`, `households`, `devices` | live `build_population` + `case_a_household_map` at build time | Yes — verifier recomputed identical figures (26.6162 MWp, 3.19722 MW, 1000/500 MW, 2.5 MW/10 MWh) | ✓ FLOWING |
| `docs/literate/case_a_population.jl` agreement/scaling sections | `agreement_rows`, `ladder`, `sweep` | the three committed CSVs | Yes — CSVs carry real measured solves (values internally consistent; speedup recomputes exactly) | ✓ FLOWING |
| `test_population_case_a_agreement.jl` | `welfare_c`, `dlmp_c` | live `solve_welfare` on the recorded tol_gap_1e-10 path | Yes — assertions green in this verifier's own slow-lane run | ✓ FLOWING |
| `results/*.csv` | all measured columns | real full-scale `solve_admm` runs (subprocess legs, BLAS pinned) | Yes — walls/iters internally consistent across all three files (same 80-iter refusal in 4 independent legs) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| POP-01/02/03 test file (counts, seeds, rebuild, map, `:default` regression, guards) | `TSODSO_TEST_FILES=test_population_case_a.jl ... Pkg.test()` | 52 pass / 0 fail / 0 error (29.8s) | ✓ PASS |
| POP-05 harness fast lane (rung derivation + T=10 micro-ladder through the script's own path) | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_population_case_a_scaling.jl ...` | 27 pass / 0 fail / 0 error (1m36s) | ✓ PASS |
| POP-04 slow lane (centralized certification on the recorded path + dual-sign anchor + tracked band skip) | `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_population_case_a_agreement.jl ...` | 11 pass / 1 allowlisted broken / 0 fail / 0 error (2m44s) | ✓ PASS |
| Population build at full scale | live julia probe | 10 aggregators, buses 2-11, 2352 devices, 4.3 s build | ✓ PASS |
| Seed distinctness + map purity | live julia probe | 784/784 distinct seeds; 784 map rows; seed-independent; all-:pv per the locked A2 decision | ✓ PASS |
| Composition figures vs docs claims | live julia probe (page's own computation) | 784 / 784x3 / 26.6162 MWp / 3.19722 MW / 1000+500 MW / 2.5 MW·10 MWh — exact match | ✓ PASS |
| Speedup arithmetic | recomputed from threads_sweep.csv | 1.239x (t2), 1.444x (t4) — matches claimed 1.24x / 1.44x | ✓ PASS |
| Selector guards + unknown selectors | live julia probe | ArgumentError on `:nope` and on non-`:ieee13` feeder | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` files exist (find count: 0) and no probe was declared in any 40-xx PLAN. Phase verification ran through the repo's test suite (executed above) and the committed measurement CSVs (audited above). **SKIPPED — no probes declared or conventional.**

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | Zero TBD/FIXME/XXX/HACK/PLACEHOLDER markers across all 10 phase-touched files; zero stub returns; zero empty handlers | — | Clean |
| `src/experiments/materialize.jl` | 141 | `_CASE_A_PV_FRACTION = 1.0` (all-PV population) | ℹ️ Info | Not a stub: documented locked decision (A2), named constant with a Phase-41 lowering path, generic `pv_group` field already in the map |
| `test/test_population_case_a_agreement.jl` | 105 | `@test_skip` for the agreement band | ℹ️ Info | Not a stub: the repo's sanctioned tracked-skip mechanism, exact-key allowlisted (unlisted skips FAIL the run), message carries the measured blocker + regeneration command |
| repo-wide (pre-existing) | — | `check_planning_ids.py` fails at HEAD with 63 hits across 20+ files | ℹ️ Info | Pre-dates Phase 40 (logged in deferred-items.md); this phase's new files add ZERO hits (scoped scan verified by the executor); repo-hygiene task, not a Phase-40 must-have |

**Debt-marker gate:** no `TBD`/`FIXME`/`XXX` markers in any phase file — gate passes.

### Human Verification Required

Automated verification covered everything programmatically checkable, including recomputing the docs figures and re-running all three phase test lanes in this verifier's own process. One item remains browser-side only:

### 1. Docs page renders correctly in a browser

**Test:** Open `docs/build/generated/case_a_population.html` (or serve `docs/build/`) and confirm the Case A Population page renders its tables (per-bus counts, composition, agreement row with "-" cells, ladder + sweep with computed speedup column).
**Expected:** All tables render with the verified figures; the agreement section states the band is NOT pinned and why.
**Why human:** HTML layout/visual rendering cannot be verified by grep; content was verified via the generated markdown + the executor's three green builds.

### Gaps Summary

One gap, precisely scoped: **POP-04's agreement-within-tolerance deliverable does not exist** — and cannot exist today without a solver/certificate investigation, because the ADMM leg at executor defaults deterministically refuses at the final consolidation's battery-complementarity gate (converged in 80 iterations; the certified product sits 0.04% over a ~1e-12 relative band at the per-house-divided battery scale). The phase handled this exactly as its own honesty policy demands: the refusal was diagnosed, recorded in committed CSVs, escalated loudly through a tracked skip that cannot silently rot, documented as NOT-pinned in the docs page, and never papered over with invented band constants or a loosened gate (`git diff` over all gate surfaces: empty — verified). The roadmap's v5.0 header (ROADMAP.md:53-55) pre-authorizes "refused with certificate" as a valid measured outcome — but a validly-measured refusal is not an agreement claim, and SC-3's truth ("agrees on welfare and prices within a measured, stated tolerance") is observably false in the codebase today.

**This looks intentional and pre-authorized.** If the developer judges the honest-refusal outcome an acceptable terminal state for this phase, add this override to the frontmatter instead of funding a closure plan:

```yaml
overrides:
  - must_have: "The 784-house case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance (POP-04 / roadmap SC-3)"
    reason: "Honest measured outcome per ROADMAP.md v5.0 honesty policy: both engines ran at full scale and are recorded (centralized certified at tol_gap_1e-10, welfare -378163.58894571784; ADMM converged 80 iters, refused by the battery-complementarity certificate at consolidation — deterministic, diagnosed 0.04%-over-band). No agreement claim is made anywhere; the missing band is a loud tracked skip citing agreement.csv + regeneration. Resolution deferred to the certificate-investigation backlog (consolidation precision seam or Phase-26 eta<1 KKT round-trip); tolerance loosening forbidden."
    accepted_by: "{developer}"
    accepted_at: "{ISO timestamp}"
```

Otherwise, `/gsd-plan-phase --gaps` can scope a closure plan from the two candidate fix paths documented in the frontmatter gap entry (consolidation battery-gate precision seam; Phase-26 η<1 KKT round-trip backlog item) — neither is a tolerance loosening.

**Note for Phase 42 planning:** the Case A magnitude phase (REPRO-03/04/05) runs the 784-house population through the DADP-vs-FIT protocol and will hit the same refusal at any step requiring a certified decomposed point; resolving POP-04 first (or via override with an explicitly centralized-only protocol) should be a deliberate decision.

---

_Verified: 2026-10-24T18:47:20Z_
_Verifier: the agent (gsd-verifier)_
