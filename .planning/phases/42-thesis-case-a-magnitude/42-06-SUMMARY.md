---
phase: 42-thesis-case-a-magnitude
plan: 06
subsystem: measurement-writeup
tags: [literate-writeup, pre-registered-measurement, reproducibility-band, gate-then-golden,
  honest-magnitude, sign-safe, protocol_sha-trail, docs-build, julia]

# Dependency graph
requires:
  - plan: 42-05
    provides: the committed measurement artifacts (magnitude/crosscheck/lens_summary/
      ablation/proxy CSVs) and the measured outcome this plan writes up
  - plan: 42-01
    provides: the pre-registered protocol (60e5d549) + its amendment (af815b0) — the
      protocol_sha trail the writeup prints
  - phase: 40-case-a-population
    provides: the 40-06 gate-then-golden band-pinning discipline (10× observed delta,
      floored at solver noise, constants verbatim with row citation)
provides:
  - docs/literate/case_a_magnitude.jl — the honest-magnitude writeup page: reads the
    committed CSVs only (NO solving), recomputes every derived percentage live
    (sign-safe), applies one qualifier helper to every magnitude print, and carries the
    headline / crosscheck / ablation / proxy / honesty / attribution sections
  - docs/make.jl — both registration sites (Literate tuple with the live/precomputed
    split comment; Experiments pages-tree entry)
  - test/test_case_a_magnitude.jl — the :slow seed-42 reproducibility item (tags
    [:magnitude, :slow]): live 784-house ladder+FIT re-run vs the committed row within
    the pinned band WELFARE_RTOL = 1e-8 (reproducibility of the plumbing, NOT a
    magnitude golden)
  - docs/src/api.md — the missing Settlement/Tariffs/Equity @autodocs section (Rule-3
    fix: pre-existing checkdocs=:exports build breakage from Phase 41 exports)
affects: [the thesis writeup (the page IS the phase's public record), /gsd-verify-work
  42 (the phase's closure verification)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (threat register T-42-06-SC: empty by construction)
  patterns: [live-recomputation-from-committed-rows, single-qualifier-helper-on-magnitude-prints,
    reproducibility-band-not-magnitude-golden, quote-aware-csv-reader-for-docs-pages]

key-files:
  created:
    - docs/literate/case_a_magnitude.jl (529 lines)
  modified:
    - docs/make.jl (both registration sites)
    - test/test_case_a_magnitude.jl (+135 lines: the :slow item)
    - docs/src/api.md (Rule-3 fix: settlement/equity @autodocs section)

key-decisions:
  - "THE WRITEUP'S HEADLINE (honest, from the committed rows): W_DADP certified 5/5 seeds (mean −378163.55846378894, min–max spread 0.04837650043191388 ≈ 1.279e-7 relative — the Phase-40 anchor reproduced to 10 digits), but the FIT counterfactual is INFEASIBLE at attempt AND the single sanctioned retry on EVERY seed → the DADP-vs-FIT Δ% at the registered 784-house mix is UNDEFINED. This is a measured result of the honest-status discipline, not a failure of the measurement."
  - "Where the gain IS measurable (all certified pairs live-recomputed, sign-safe): device_mix/batteries_out +1.3277e-5 % (the only full certified pair at 784 houses — the A1/A4 asymmetry MEASURED: with batteries out both blocking mechanisms vanish, DADP certifies at default in 5 iters and FIT certifies); population rungs +1.8467e-5 % / +2.38e-6 %; proxy ieee123 +0.013516 % (factor 19.5 below the cited ≈+0.263 % provenance figure — reported proximity, never gated). All are 3.3–7.0 orders of magnitude below the thesis +25 % — the +25 % number is NOT reproduced at any measured point."
  - "ATTRIBUTION STATEMENT as written: the measured DADP-vs-FIT gap CANNOT be attributed to the thesis +25 % at the registered mix (no measurable FIT gain exists there); the explanations that DO hold are the A1/A4 batteryless-FIT asymmetry (it blocks the registered mix outright), the repo's congestion-calibrated fixture with its SOC-exactness + battery-complementarity gates, and the sign-safe definition; 'gap not fully attributed' is a recorded outcome (protocol §9) — closing to +25 % was never a success condition."
  - "The :slow band pins REPRODUCIBILITY, per the 40-06 discipline: a probe re-run measured the live-vs-committed deltas FIRST (welfare rel delta 0.0 — bit-exact reproduction: default error:CertificateError iters=80, gap_1e-10 converged iters=80, welfare −378163.5654347284, FIT error:SolveFailedError at attempt+retry — ALL identical), THEN the band was pinned verbatim: WELFARE_RTOL = 1e-8 = 10 × 0.0 floored at the 40-06 solver-noise welfare floor, cited at the pin site to the committed row [headline/gain/seed=42/gap_1e-10, sha 60e5d549]. No assertion touches ±25 % or any target."
  - "'welfare_fit likewise' is asserted as honest-STATUS agreement (the committed row records NO welfare_fit — the FIT refusal; the live leg refuses identically), and 'Δ identity exact' as (a) no fabricated delta columns on either side plus (b) the exact welfare_gain algebra anchor — the only reading consistent with the measured outcome and the honesty policy."
  - "RULE-3 BLOCKING FIX (pre-existing): docs/src/api.md had no Settlement/Tariffs/Equity section since Phase 41 — the 25 exported settlement/equity docstrings tripped checkdocs = :exports and terminated the docs build BEFORE rendering, blocking this plan's mandatory build gate. Fixed by adding the subsystem's @autodocs block (all seven src/settlement/ pages)."

patterns-established:
  - "Pattern: page-level live recomputation with fail-loud evidence-chain guards — the writeup errors at build time if a committed CSV is missing/empty/incomplete rather than rendering an empty page"
  - "Pattern: 'UNDEFINED' as a printed, qualified outcome — derived figures that have no denominator (no certified pair) print UNDEFINED with the cause, never zero, never blank"

requirements-completed: [REPRO-03, REPRO-04, REPRO-05]   # the evidence chain closed: protocol commit → guard → CSVs (protocol_sha) → writeup + reproducibility band

# Metrics
duration: 2.2h (+ ~1.6 h of measurement-process wall time inside test/probe runs)
completed: 2026-10-26
---

# Phase 42 Plan 06: The Writeup — Honest Magnitude, Reproducibility Band, Registration Summary

**The phase closed: the literate writeup (`docs/literate/case_a_magnitude.jl`, 529 lines) renders the committed measurement honestly — W_DADP certified 5/5 seeds (mean −378163.5585, spread 0.0484 ≈ 1.28e-7 relative), FIT INFEASIBLE at attempt+retry everywhere so the registered-mix Δ% is printed as UNDEFINED, the four measurable certified pairs recomputed live (3.3–7.0 orders below +25%, gap NOT FULLY ATTRIBUTED as a recorded outcome) — the `:slow` seed-42 reproducibility item passes against a bit-exact live re-run (band pinned 1e-8, verbatim-cited), the page is registered at both make.jl sites and renders in a green docs build, and the full fast suite is green (33186 pass / 6 allowed-broken).**

## Performance

- **Duration:** 2.2 h executor wall (probe 22.6 min + slow-item verify 47.2 min + docs builds 2 × 12.1 min + fast suite 15.6 min, strictly sequential, ONE julia process at a time, all foreground)
- **Started:** 2026-10-26T20:12:58Z
- **Completed:** 2026-10-26T22:25Z
- **Tasks:** 3/3

## Accomplishments

- **Task 1 — the `:slow` reproducibility item (`2da1ea0`).** New `@testitem "magnitude reproducibility: 784-house seed-42 ladder+gain re-run agrees with the committed magnitude.csv row"` (tags `[:magnitude, :slow]`): includes the runner itself (PROGRAM_FILE-guarded — `_measure_point` IS the headline code path), reads the committed seed-42 gain row (skip-proof: its absence is a LOUD error), re-runs the full registered measurement live, and asserts (1) certified welfare within the pinned band, (2) certified rung identity, (3) honest FIT-refusal status agreement, (4) the Δ identity exact (no fabricated columns + the algebra anchor), (5) the ladder history rung-for-rung (status + iters). Header states the golden policy: reproducibility of the plumbing only, NEVER a magnitude assertion. **Probe measured first** (40-06 gate-then-golden): the live re-run reproduced the committed row BIT-EXACTLY (welfare rel delta 0.0; all rung statuses and iteration counts identical) → band pinned `WELFARE_RTOL = 1e-8` (10 × 0.0, floored at the 40-06 welfare noise floor), comment at the pin site cites the row's provenance key + values + sha. Verify: `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_case_a_magnitude.jl Pkg.test()` → exit 0 (18/18, 47.2 min). Fast lane for the file untouched and green (599/599).
- **Task 2 — the literate writeup (`2547e54`).** `docs/literate/case_a_magnitude.jl` on the `settlement_equity.jl` skeleton: H1 + framing naming REPRO-03/04/05; the page contract (reads `results/thesis_case_a_magnitude/*.csv` exactly as committed, solves NOTHING); the locked-statements note (sign-safe definition, naive ratio banned, gates never loosened, ρ locked); seconds-scale live slice (quote-aware CSV reads — the settlement-page precedent, since CSV.jl is not a docs dep); protocol section (frozen config, seeds, ladder, four axes, amendment policy, protocol_sha trail); headline (per-seed table, live mean/spread, the honest UNDEFINED); crosscheck (W_CEN −378163.58894571784 via `tol_gap_1e-10`, |Δ| = 0.0235 rel 6.217e-8; price lens max|λ−λ₀| = 6.2197); ablation (4 certified pairs live; per-axis effects honestly UNDEFINED vs the pair-less registered mix; scale_0.5's four-rung exhaustion at iters=88 + scale_2.0 default at 52; the population curve with distance-below-+25% factors); proxy restatement (factor 19.5 below the cited ≈+0.263% provenance figure, never gated; ieee13-default honest status); honesty section (A1/A4 asymmetry as a MEASURED statement, the DSO sign flip +2.98 vs −1600.5/−1561.2, the 25-row refusal ledger, the no-tuning statement with the printed sha trail); the attribution statement (gap NOT FULLY ATTRIBUTED — recorded; +25% not reproduced at any measured point). Every derived percentage recomputes LIVE with sign-safe divisions; every magnitude print goes through the single `MAGNITUDE_QUALIFIER`/`cite_magnitude` helper (32 applications in the rendered HTML). Registered at BOTH make.jl sites (tuple comment + `"Case A Magnitude" => "generated/case_a_magnitude.md"`); page-executes check under `--project=docs` → exit 0.
- **Task 3 — gates + closure (`f1a02d7`).** Docs build: initially FAILED on a pre-existing breakage (see Deviations) — after the Rule-3 api.md fix: exit 0 (12.1 min) with the page rendered (`docs/build/generated/case_a_magnitude.html`, 57 KB, nav entry present). Full fast suite: exit 0 — **33186 pass / 6 broken (all six are the allowed conditional-broken records in `test/expected_broken.txt`) / 0 soft-scope warnings** (the authoritative grep), 15.6 min. Evidence chain printed as the closure record: protocol first commit `60e5d54` (42-01, pre-run) → amendment `af815b0` (append-only, dated) → guard in committed source (9 runner + 4 lib references) → 56 data rows across the five CSVs all protocol_sha-stamped (verified non-empty on every row live) → writeup page renders them (docs build exit 0).

## Task Commits

1. **Task 1:** `2da1ea0` — `test(42-06): :slow seed-42 reproducibility band (gate-then-golden on plumbing; NOT a magnitude golden)`
2. **Task 2:** `2547e54` — `feat(42-06): case-a-magnitude literate writeup — the honest, pre-registered measurement, registered at both make.jl sites`
3. **Task 3:** `f1a02d7` — `docs(42-06): case-a-magnitude writeup registered (both make.jl sites); docs build + fast suite green`

## Test Evidence

- **Slow (the plan's Task-1 verify, verbatim):** `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` → exit 0, 18/18 pass, 47.2 min (the live 784-house ladder + FIT inside the item).
- **Fast suite (the phase's merge gate):** `TSODSO_TEST_SET=fast julia --project=. -e 'import Pkg; Pkg.test()'` → exit 0, **33186 pass / 6 broken (all allowed)** / 33192 total, 15.6 min, soft-scope warning count 0.
- **Page executes:** `julia --project=docs -e 'include("docs/literate/case_a_magnitude.jl"); println("page executes clean")'` → exit 0, re-verified after JuliaFormatter.
- **Registration:** `grep -c "case_a_magnitude" docs/make.jl` → 3 (tuple entry + comment + pages-tree entry).
- **Docs build:** `julia --project=docs -e 'using Pkg; Pkg.instantiate(); include("docs/make.jl")'` → exit 0 (12.1 min); rendered page + nav entry verified in `docs/build/`.
- **Evidence-chain check:** protocol-first commit (`git log --follow`: `60e5d54` then `af815b0`), guard present in committed source, five CSVs committed with non-empty `protocol_sha` on all 56 data rows, writeup renders them.

## Measured Results (written up, never gated)

### The headline (recomputed live on the page from magnitude.csv)

| seed | certified rung | W_DADP | iters | FIT leg | Δ% |
|------|----------------|--------|-------|---------|----|
| 42 | gap_1e-10 (default refused, 80) | −378163.5654347284 | 80 | INFEASIBLE (attempt + retry) | UNDEFINED |
| 43 | default | −378163.57421763154 | 81 | INFEASIBLE (attempt + retry) | UNDEFINED |
| 44 | default | −378163.5258411311 | 82 | INFEASIBLE (attempt + retry) | UNDEFINED |
| 45 | default | −378163.5725944356 | 84 | INFEASIBLE (attempt + retry) | UNDEFINED |
| 46 | gap_1e-10 (default refused, 80) | −378163.5542310182 | 80 | INFEASIBLE (attempt + retry) | UNDEFINED |

Mean −378163.55846378894; min–max spread 0.04837650043191388 (≈1.279e-7 relative). **Zero certified pairs at the registered mix — the headline Δ% is honestly UNDEFINED.**

### Where the gain IS measurable (ablation.csv certified pairs, sign-safe, live)

| axis | variant | Δ% | factor below +25% |
|------|---------|----|-------------------|
| population | proxy_ieee123 (reused, seed 20260719) | +0.0135162 | ≈1.9e3 |
| population | rung_0.25 | +1.8467e-5 | ≈1.354e6 |
| population | rung_0.5 | +2.3801e-6 | ≈1.050e7 |
| device_mix | **batteries_out (784 houses)** | **+1.3277e-5** | ≈1.88e6 |

### The reproducibility band's pinned constants (with their row citation)

`WELFARE_RTOL = 1e-8` — 10 × the observed live-vs-committed welfare relative delta (**0.0**, bit-exact probe of 2026-10-26) floored at the 40-06 solver-noise welfare floor; cited at the pin site to `magnitude.csv` [mode=headline, kind=gain, seed=42, rung='gap_1e-10', protocol_sha=60e5d549…, welfare_dadp=−378163.5654347284]. No magnitude golden exists anywhere in the suite.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] api.md lacked the Settlement/Tariffs/Equity section (pre-existing docs-build breakage)**
- **Found during:** Task 3's mandatory docs build — `makedocs` terminated with `[:missing_docs]` (25 unsurfaced docstrings) BEFORE rendering, on ALL Phase-41 settlement/equity exports; `docs/src/api.md` was last touched in Phase 36 and no full docs build had run since Phase 41 added the exports.
- **Fix:** added the subsystem's `@autodocs` block (all seven `src/settlement/` pages, `Order = [:type, :constant, :function]` per the make.jl `:constant` note). Exactly the "fix any Literate/Documenter issue" class Task 3 authorizes; docs build then exit 0.
- **Files modified:** docs/src/api.md
- **Commit:** `f1a02d7`

**2. [Rule 1 - Bug] `DataFrameRow` UndefVarError in the :slow item**
- **Found during:** Task 1's first slow-run attempt — the item crashed at body eval (`UndefVarError: DataFrameRow not defined`), before any solving started (60 s loss).
- **Fix:** removed the unnecessary type-check line (`filter` returns a DataFrame; `gain_rows[end, :]` needs no check).
- **Commit:** within `2da1ea0`

**3. [Rule 1 - Bug] Three `@printf` calls used `*`-concatenated format strings**
- **Found during:** Task 2's page-executes check — `ArgumentError: First argument to @printf after io must be a format string` (the macro requires a literal).
- **Fix:** merged each into a single literal string.
- **Commit:** within `2547e54`

**4. [Rule 1 - Bug] Soft-scope `n_err += 1` in the page's refusal-ledger loop**
- **Found during:** Task 2's page-executes check — the exact hazard documented in `test/runtests.jl`'s header, hit for real (`Assignment to n_err in soft scope is ambiguous` → `UndefVarError`).
- **Fix:** the repo's established `let`-block idiom (accumulator inside a hard scope, returned to top level).
- **Commit:** within `2547e54`

**5. [Rule 1 - Bug] Inverted proxy-proximity factor (printed 0.1 instead of 19.5)**
- **Found during:** Task 2's page-executes check — `dp_proxy / PROVENANCE_PROXY_PCT` = 0.051 pointed the factor the wrong way.
- **Fix:** `PROVENANCE_PROXY_PCT / dp_proxy` with reworded print ("the measured figure sits a factor 19.5 BELOW the provenance restatement").
- **Commit:** within `2547e54`

### Deliberate Interpretations (within plan discretion)

- **"Full fast suite" run as `TSODSO_TEST_SET=fast`** (the CI footing and the plan action's own wording): the plan's Task-3 verify line omits the env var, which would select the "all" set and re-run EVERY historical `:slow` item repo-wide (hours) — the fast suite (15.6 min, 33186 green) plus this plan's own `:slow` item (47 min, green, its own plan-mandated verify) together cover both halves of the suite deliberately and sequentially.
- **Docs build run FOREGROUND** (12.1 min, timeout 30 min) instead of the plan's background scheduling — the orchestrator's binding discipline (session must outlive every process; ONE julia process at a time).
- **"welfare_fit likewise" asserted as honest-status agreement** and **"Δ identity exact" as no-fabricated-columns + exact algebra anchor**: the plan's wording presupposed a certified pair might exist; the committed row is an honest-terminal REFUSAL row (the measured outcome of 42-05), so the assertions compare what actually exists on both sides — the refusal itself — and never fabricate a denominator. The skip-proof loud-error requirement is implemented verbatim.
- **STATE.md/ROADMAP.md untouched** per the orchestrator's binding instructions (wave coordination handles state; ROADMAP.md explicitly forbidden).

## Known Stubs

None. The page reads only committed CSVs (fail-loud guards error the docs build if any is missing/empty/incomplete); no placeholder values, no unwired data.

## Threat Check

All register entries addressed: **T-42-06-1** (stale derived %) — every Δ%/spread/effect recomputed live in page code from the committed rows, sign-safe divisions (`abs` denominator), `cite_magnitude` on every magnitude print (32 in the rendered HTML); no Δ% literal exists in the page source. **T-42-06-2** (band widened to hide drift) — band pinned verbatim from the measured probe (0.0 delta → the 1e-8 floor) with the row citation at the pin site; the golden-policy header states reproducibility-only; "never widen the band to fit" stated in the item. **T-42-06-3** (unattributed figures) — every number cited to its CSV row key; the sha trail printed live in the no-tuning paragraph. **T-42-06-4** (docs budget) — no solve call exists on the page; committed-CSV reads only (12-min build, well under budget). **T-42-06-SC** — zero new packages. No new security-relevant surface beyond the plan's threat model (a docs page + a test item + an api.md docs section).

## TDD Gate Compliance

Task 1 carries `tdd="true"`. The behavior here is a live re-derivation whose RED state cannot precede its own implementation (the test IS the re-run; a "failing first" run would mean burning two 47-min measurement runs to no informational gain — the probe-first flow delivers the same gate-then-golden evidence: measure, pin, assert). The commit sequence is a single `test(...)` commit (`2da1ea0`) whose band constants are pinned verbatim from the independently-executed probe; the plan's own action text prescribes exactly this measure-then-pin-then-verify flow. No `test → feat` split applies (no production code changed in this plan; the item tests existing plumbing). Flagged per the gate-checking convention.

## Self-Check: PASSED

- `docs/literate/case_a_magnitude.jl` (529 lines ≥ 100) — FOUND, committed at `2547e54`.
- `docs/make.jl` contains `case_a_magnitude` at BOTH sites (grep count 3) — FOUND, committed at `2547e54`.
- `test/test_case_a_magnitude.jl` :slow item (tags `[:magnitude, :slow]`, name contains "magnitude", references `magnitude.csv`) — FOUND, committed at `2da1ea0`.
- `docs/src/api.md` settlement section — FOUND, committed at `f1a02d7`.
- Commits `2da1ea0`, `2547e54`, `f1a02d7` present in `git log 5d232f9..HEAD` — FOUND (3).
- Rendered page `docs/build/generated/case_a_magnitude.html` — FOUND (build artifact, intentionally untracked per .gitignore).
- Slow item exit 0 (18/18); fast suite exit 0 (33186/6/33192); docs build exit 0 — VERIFIED.
