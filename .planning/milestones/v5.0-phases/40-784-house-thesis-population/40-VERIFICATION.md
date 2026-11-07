---
phase: 40-784-house-thesis-population
verified: 2026-10-24T22:16:58Z
status: passed
score: 6/6 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 5/6
  gaps_closed:
    - "The 784-house Case A case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance (POP-04 / roadmap SC-3)"
  gaps_remaining: []
  regressions: []
---

# Phase 40: 784-House Thesis Population — Verification Report

**Phase Goal:** A researcher can build, solve and scale the thesis Case A population at its true 784-household size, reproducibly and with documented calibration.
**Verified:** 2026-10-24T22:16:58Z
**Status:** passed
**Re-verification:** Yes — after gap closure (40-05 seam + 40-06 bounded ladder)

> **Supersession note.** This report SUPERSEDES the prior `gaps_found` (5/6) report for this same phase; the prior report is preserved in git history at commit `05167a8`. Its single gap — POP-04's agreement-within-measured-tolerance deliverable — is closed by plans 40-05/40-06 and is re-verified here in this verifier's own process, including a live re-run of the restricted slow lane.

## Goal Achievement

Every verb of the phase goal is now delivered and independently re-verified: the population **builds** (784 houses, 10 aggregators — re-exercised live by this verification's slow-lane run), **solves** (BOTH engines certify at full scale: centralized on the recorded `tol_gap_1e-10` path, ADMM at the certified `gap_1e-10` ladder rung — 14/14 slow-lane tests green in this verifier's own process, 36m28.6s), **scales** (measured ladder + threads-sweep CSVs intact and untouched), **reproducibly** (per-house hash seeding and structural rebuild equality untouched; the slow-lane agreement run itself is a deterministic seed-42 reproduction of the committed measurement), and is **documented** (docs page rewritten to the measured closure; built HTML content-verified figure-by-figure in this verifier's own process). With POP-04 closed, all six requirement IDs are satisfied and no gate, tolerance, or default was loosened anywhere — the whole closure's `src/` diff is exactly the 4-file additive solver-precision seam, with the default path provably byte-identical.

### Observable Truths

| # | Truth (roadmap SC + POP mapping) | Status | Evidence |
|---|----------------------------------|--------|----------|
| 1 | SC-1 / POP-01: `:case_a_784` selector over the 10 IEEE-13 aggregator nodes; `:default` stays byte-identical | ✓ VERIFIED | Quick regression (fully live-verified in the prior verification): selector branch + `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)` (Scenario.jl:48) intact; **whole-closure `git diff e5ea5b6..HEAD -- src/` touches ONLY the 4 seam files** (`factory.jl`, `AgrOpt.jl`, `admm_phases.jl`, `solve_admm.jl`) — `materialize.jl`/`Scenario.jl` diff-empty since the prior verification, so the prior live evidence stands; `:default` fall-through body still untouched; the seam's default path resolves to the identical factory expression (diff-reviewed) and the knife-edge canary (iters=56 / welfare=-4823.66604824162) is unre-pinned since phase 39 |
| 2 | SC-2 / POP-02+POP-03: per-house seeding from (master seed, bus, house index); rebuild reproduces exactly; no seed collisions; household map available | ✓ VERIFIED | Quick regression: `_case_a_house_seed` (materialize.jl:403) and `case_a_household_map` (materialize.jl:723) present and diff-untouched since the prior verification's live probes (784/784 distinct seeds; structural rebuild `==`; 784 map rows). Additionally re-exercised end-to-end by this verification's slow-lane run, which rebuilt the full seeded population and reproduced the committed measurement |
| 3 | SC-3 / POP-04: the 784-house case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance | ✓ VERIFIED | **FULL 3-level + live verification (the closed gap).** (1) EXISTS: `agreement.csv` winning row (`agr_tol=gap_1e-10`: converged, 80 iters, welfare_admm=-378163.5654347284, welfare_rel_delta=6.217147850629488e-8, price_max_abs/rel_delta=0.17819846607479023, admm_exact_maxgap=2.773411293424498e-10, populated `recommended_*` cells) beside the honestly-kept default-rung refusal row. (2) SUBSTANTIVE: this verifier **recomputed every band constant bit-for-bit in float arithmetic** — abs delta `0.023510989442002028` exact; rel delta `6.217147850629488e-8` exact; 10× rule → `6.217147850629488e-7` == `WELFARE_RTOL` and `1.7819846607479022` == `PRICE_ATOL`==`PRICE_RTOL`, matching the script's `max(10*delta, floor)` rule (floors 1e-8/1e-6 not binding) and the row's `recommended_*` cells. (3) WIRED: the rung threads `solve_admm(agr_optimizer = select_optimizer(QP(); rung_attrs...))` through the 40-05 seam (script lines 274-284; default rung splats `NamedTuple()` — byte-identical pre-ladder call); the `:slow` test asserts the band LIVE. (4) LIVE: **this verifier ran the restricted slow lane in its own process — 14 pass / 14 total / 0 skip / 0 fail, exit 0 (36m28.6s)**, including the full 784-house centralized solve AND the 784-house ADMM solve at the rung with the pinned `isapprox` assertions (a skip would have failed the run: the allowance is deleted and the runner fails unlisted skip records) |
| 4 | SC-4 / POP-05: scaling report gives measured wall time vs threads and ADMM iterations vs population size (negative result valid) | ✓ VERIFIED | Quick regression (fully verified prior): `scaling_ladder.csv` (6 measured rungs + header) and `threads_sweep.csv` (3 measured legs + header) intact and untouched by the closure (diff = 4 seam src files only); speedup 1.239x/1.444x recomputed in the prior verification; the ladder's honest refusal row is now complemented by the certified `gap_1e-10` resolution recorded in agreement.csv |
| 5 | SC-5 / POP-06: documentation states composition (PV capacity, elastic/inelastic load, device mix) with calibration provenance and which Appendix E parameters are unavailable | ✓ VERIFIED | Quick regression + closure re-check: composition/calibration/Appendix-E sections intact (figures live-recomputed in the prior verification); agreement section REWRITTEN to the measured closure with the winning figures; page registered at both `docs/make.jl` sites (lines 52, 101); **built HTML content-verified in this verifier's own process**: all winning figures present (`-378163.5654347284`, `converged`, `tol_gap_1e-10`, both band constants), ZERO stale `test_skip`/not-pinned prose, and the build is post-closure (mtime 18:29 local = 21:29 UTC, after the content commit 967755d at 18:11 local — repo clock is UTC-3) |

**Score:** 6/6 must-haves verified (POP-01..POP-06 all VERIFIED; POP-04 closed and re-verified live)

### Re-Verification: Gap Closure Audit (POP-04)

The prior gap's three stated closure conditions, each independently verified:

| Prior gap requirement | Closure evidence | Status |
| --------------------- | ---------------- | ------ |
| "A certified full-population ADMM point, so agreement deltas become measurable and the band can be pinned" | Bounded pre-planned ladder in `AGR_TOL_RUNGS` (default → gap_1e-10 → gap_1e-12 → gapfeas_1e-12, stop-on-first-certified, HARD stop — script lines 108-126): rung `gap_1e-10` CERTIFIED (converged, 80 iters, exact_maxgap 2.77e-10); **CSV contains exactly 2 rows — rungs 2-3 never run** (bounded, honest); band pinned verbatim from the row's `recommended_*` cells | ✓ CLOSED |
| "Solver-precision seam at the ADMM consolidation battery gate (fix path a)" | `select_optimizer(::QP; attrs...)` + `build_agr_opt(optimizer=...)` + `solve_admm(agr_optimizer=...)` — additive kwargs threaded end-to-end (full diff reviewed); **no tolerance default in the seam** (ladder values live in the script); gate surfaces (`src/welfare/`, `admm_state.jl` τ_batt=1e-3) diff-EMPTY across the whole closure; canary unre-pinned; fast-lane golden evidence in 40-05 SUMMARY | ✓ CLOSED |
| "EXPLICITLY NOT a fix: loosening any gate or tolerance" | `git diff 05167a8..HEAD -- src/` EMPTY (nothing in src/ touched after the prior verification); `git diff e5ea5b6..HEAD -- src/` = exactly the 4 additive seam files; **the pinned band is TIGHTER than any default** (welfare rtol 6.2e-7, price atol/rtol 1.78 vs the prior absence of any band) and is derived by the script's own 10×-floored rule from measured deltas — nothing pre-loosened | ✓ HONORED |

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `results/case_a_population/agreement.csv` | Complete POP-04 ladder record, all outcomes honest | ✓ VERIFIED | 2 rows: default refusal (legacy row superseded in place, identical measured values: welfare -378163.58894571784, 80 iters, error:CertificateError) + gap_1e-10 CERTIFIED row with all deltas and `recommended_*` populated; provenance columns complete; agr_tol upsert key |
| `test/test_population_case_a_agreement.jl` | `:slow` item with LIVE pinned band (skip lifted) | ✓ VERIFIED | 148 lines; zero `@test_skip`; `WELFARE_RTOL = 6.217147850629488e-7`, `PRICE_ATOL = PRICE_RTOL = 1.7819846607479022` — each citing its exact CSV row + the 10×-floored rule; asserts `:converged` + welfare/price `isapprox` live at the rung; **green in this verifier's own run** |
| `test/expected_broken.txt` | Allowance deleted in lockstep with the lift | ✓ VERIFIED | Zero phase-40/agreement/population entries; the runner's exact-match guard would fail ANY residual skip — and none exists |
| `scripts/case_a_agreement.jl` | Pre-planned bounded ladder + agr_tol column + legacy coalescing | ✓ VERIFIED | `AGR_TOL_RUNGS` Dict (4 keys), `--agr-rung` fail-loud validation, stop-on-first-certified policy documented, `rung_attrs` splat (default = byte-identical call), `max(10*delta, floor)` recommendation rule at lines 377-379 |
| `src/solver/factory.jl` + `src/admm/{AgrOpt.jl, admm_phases.jl, solve_admm.jl}` | The 40-05 additive seam, default byte-identical | ✓ VERIFIED | Whole-closure diff = exactly these 4 files; every new kwarg resolves to the identical pre-seam expression when omitted (diff-reviewed line by line); no tolerance literal in executable src lines (only the SOCP method's pre-existing 1e-8 defaults) |
| `docs/literate/case_a_population.jl` | Agreement section = the measured closure | ✓ VERIFIED | Selects the winning row explicitly by `agr_tol == "gap_1e-10"` via `only()` (fails loudly otherwise); ladder history + seam mechanism + gates-untouched stated; reads the CSV at build time; built HTML carries the figures (content-verified) |
| `.planning/REQUIREMENTS.md` | POP-04 [x] with citation | ✓ VERIFIED | Checkbox `[x]` (line 38) + traceability "Complete — certified via plan 40-06's bounded ladder: rung `gap_1e-10` … band pinned gate-then-golden from agreement.csv (welfare rtol 6.22e-7, price atol/rtol 1.78)" (line 117) |
| Phase-40 prior artifacts (materialize.jl, Scenario.jl, scaling CSVs, docs registration, scripts/README) | Unchanged / still wired | ✓ VERIFIED | Whole-closure src/ diff excludes them; CSVs and registrations spot-checked present |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `case_a_agreement.jl` rung | 40-05 seam | `agr_optimizer = select_optimizer(QP(); rung_attrs...)` splatted into `solve_admm` | ✓ WIRED | Script lines 274-284; default rung splats `NamedTuple()` (byte-identical pre-ladder call); fail-loud rung validation |
| `solve_admm` | `_admm_build` → `build_agr_opt` → factory | `agr_optimizer` kwarg threaded, resolved once when `nothing` | ✓ WIRED | Diff-reviewed: default resolves to `select_optimizer(QP())` — the identical previously-hardcoded expression; governs mid-loop AND certify re-solves (build-once) |
| test band constants | `agreement.csv` winning row | Per-constant comment citations (provenance key + observed deltas + rule) | ✓ WIRED | Constants == `recommended_*` cells bit-for-bit (recomputed by this verifier in float arithmetic) |
| test `:slow` item | `solve_welfare` + `solve_admm` at the rung | Live solves, same `aggs` object, BLAS pinned to 1 (measurement footing) | ✓ WIRED | **Executed green in this verifier's own process (36m28.6s)** |
| `docs/literate/case_a_population.jl` | `agreement.csv` winning row | `agr_tol`-keyed filter + `only()` loud-fail | ✓ WIRED | Content-verified in built markdown + HTML |
| `expected_broken.txt` | (removed allowance) | Lockstep skip-lift | ✓ WIRED | 0 phase-40 entries; runner fails unlisted skip records — and the slow lane passed with 0 skips |
| `REQUIREMENTS.md` | the measurement | POP-04 [x] + rung/band citation | ✓ WIRED | Line 38 + traceability line 117 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `test_population_case_a_agreement.jl` band | `WELFARE_RTOL`, `PRICE_ATOL/RTOL` | agreement.csv winning row's measured deltas (via the script's 10×-floored rule) | Yes — recomputed bit-for-bit by this verifier from the CSV cells | ✓ FLOWING |
| test assertions | `r.status`, `r.welfare`, `r.λ` vs `welfare_c`, `dlmp_c` | Live 784-house solves in the test's own process | Yes — 14/14 green in this verifier's run | ✓ FLOWING |
| `docs/literate/case_a_population.jl` agreement section | `agreement` row | agreement.csv, `agr_tol`-keyed selection at build time | Yes — built HTML carries the winning figures | ✓ FLOWING |
| `agreement.csv` winning row | all measured cells | Real full-scale ADMM solve at the rung through the seam (script), centralized leg reproduced exactly | Yes — internally consistent (abs/rel deltas recompute; exact_maxgap 2.77e-10 consistent with tol_gap 1e-10; centralized welfare identical across both rows) AND independently reproduced by the live test run | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| **POP-04 live: restricted slow lane** (784-house centralized solve + full 784-house ADMM solve at `gap_1e-10` + pinned-band `isapprox` assertions + dual-sign anchor) | `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_population_case_a_agreement.jl julia --project=. -e 'import Pkg; Pkg.test()'` (this verifier's own process) | **14 pass / 14 total / 0 skip / 0 fail, exit 0 (36m28.6s)** | ✓ PASS |
| Band constants == winning row's cells | python float recomputation from the CSV values (the same arithmetic Julia performs) | rel delta `6.217147850629488e-8`, 10× → `6.217147850629488e-7`; price ×10 → `1.7819846607479022`; abs delta `0.023510989442002028` — all EXACT | ✓ PASS |
| Docs closure content | grep of built `docs/src/generated/case_a_population.md` + `docs/build/generated/case_a_population.html` | All winning figures present; 0 `test_skip`; 0 not-pinned prose; `CertificateError` hits are the honest default-rung history row only | ✓ PASS |
| Ladder boundedness | CSV row audit + `AGR_TOL_RUNGS` Dict read | Exactly 2 rows (default + gap_1e-10); rungs 2-3 absent; stop-on-first-certified policy in code | ✓ PASS |
| No gate loosened | `git diff 05167a8..HEAD -- src/` (EMPTY), `git diff e5ea5b6..HEAD -- src/` (4 seam files only), `git diff e5ea5b6..HEAD -- src/welfare/ src/admm/admm_state.jl` (EMPTY), canary constants (`4823.66604824162` last touched phase 39 e3517fd) | Default path byte-identical; golden policy intact | ✓ PASS |
| POP-01/02/03 fast regression | existence + diff-untouched proof (prior live verification stands; population rebuilt live inside the slow-lane run above) | All symbols intact; files diff-empty since prior verification | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` files exist (find count: 0) and no probe is declared in any 40-xx PLAN (including the 40-05/40-06 closure plans). Phase verification ran through the repo's test suite (slow lane re-executed live above) and the committed measurement CSVs (audited above). **SKIPPED — no probes declared or conventional.**

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| POP-01 | 40-01 | 784 households over 10 IEEE-13 aggregator nodes via a new selector; `:default` byte-identical | ✓ SATISFIED | Selector + roll-up verified prior (live); untouched by the closure; seam default provably byte-identical |
| POP-02 | 40-01 | Per-household hash seeding; reproducible; no collisions | ✓ SATISFIED | `_case_a_house_seed` intact; determinism re-exercised by the live slow-lane reproduction of the committed measurement |
| POP-03 | 40-01 | Household map (house → bus, aggregator, device set, PV group) | ✓ SATISFIED | `case_a_household_map` intact (materialize.jl:723) |
| POP-04 | 40-03 (+ closure 40-05, 40-06) | Both engines at 784 houses agree on welfare and prices within a measured tolerance | ✓ SATISFIED | **CLOSED**: certified gap_1e-10 ADMM point; band pinned gate-then-golden (recomputed bit-for-bit); skip lifted in lockstep; `[x]` with citation; live slow lane green in this verifier's process |
| POP-05 | 40-02 | Scaling report: wall time vs threads; iterations vs population; measured not assumed | ✓ SATISFIED | Both CSVs intact with provenance; speedups recomputed prior |
| POP-06 | 40-04 | Composition documented with calibration provenance + Appendix E unavailability | ✓ SATISFIED | Docs page verified prior figure-by-figure; agreement section now states the measured closure (content-verified in built HTML) |

**Orphaned requirements:** none — REQUIREMENTS.md maps exactly POP-01..POP-06 to Phase 40; all six are claimed by plans (40-01: [POP-01..03]; 40-02: [POP-05]; 40-03: [POP-04]; 40-04: [POP-06]; 40-05/40-06: [POP-04]) and all are Complete in the traceability table.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | Zero TBD/FIXME/XXX/HACK/PLACEHOLDER markers and zero stub patterns across all closure-touched files (script, test, expected_broken, docs page, 4 src seam files) — grep-verified this run | — | Clean |
| `src/experiments/materialize.jl` | 141 | `_CASE_A_PV_FRACTION = 1.0` (all-PV population) | ℹ️ Info | Carried from prior report: documented locked decision (A2), Phase-41 lowering path; unchanged |
| repo-wide (pre-existing) | — | `check_planning_ids.py` hits in 20+ unrelated files | ℹ️ Info | Pre-dates Phase 40 (deferred-items.md); unchanged by the closure |

**Debt-marker gate:** no `TBD`/`FIXME`/`XXX` markers in any closure-touched file — gate passes.

### Human Verification Required

None. The prior report's single human item (browser rendering of the docs page) is closed at content level in this verifier's own process: the BUILT HTML was grep-verified to carry every winning figure with zero stale not-pinned/skip prose, the build is confirmed post-closure (mtime vs commit times, repo clock UTC-3), and the page renders through the repo's standard Documenter pipeline shared by all generated pages. No visual, real-time, or external-service behavior remains that grep/built-artifact checks cannot cover; the decisive behavioral check (the 784-house agreement band) was re-executed live in this verification.

### Gaps Summary

No gaps. The single prior gap (POP-04) is closed exactly along the fix path the prior report scoped as "candidate (a)", via two disciplined plans: 40-05 added the additive `agr_optimizer` seam (default path byte-identical — canary unre-pinned, gate diffs empty), and 40-06 ran a pre-planned, bounded solver-precision ladder whose FIRST rung (`gap_1e-10` — tightening the solver's own convergence tolerance, never a gate) certified the converged 784-house ADMM point (80 iters, exact_maxgap 2.77e-10). The agreement band was pinned gate-then-golden from that row's measured cells (welfare rtol 6.217147850629488e-7, price atol/rtol 1.7819846607479022 — each recomputed bit-for-bit by this verifier), the tracked skip was lifted with its allowance deleted in lockstep, REQUIREMENTS.md records POP-04 complete with citation, and the docs page documents the measured closure including the honest default-rung refusal history. `src/` received nothing after the prior verification; the whole-closure `src/` diff is the 4-file additive seam only. The prior report's Phase-42 planning concern is resolved by this closure: a certified decomposed configuration (`gap_1e-10` through the seam) now exists for certified-step protocols.

**This supersedes the `gaps_found` report from the same phase (prior report preserved in git history at commit `05167a8`).**

---

_Verified: 2026-10-24T22:16:58Z_
_Verifier: the agent (gsd-verifier)_
