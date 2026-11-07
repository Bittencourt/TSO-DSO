# Phase 42 Plan Check — Goal-Backward Review

---
revision: 1 applied
---

**Checked:** 2026-10-26
**Plans reviewed:** 42-01 … 42-06 (6 plans, 5 waves)
**Inputs:** ROADMAP Phase 42, REQUIREMENTS REPRO-03..05, 42-CONTEXT.md (locked decisions),
42-RESEARCH.md (incl. Validation Architecture + Q1–Q3), 42-PATTERNS.md, codebase spot-checks.
**Method:** goal-backward — every success criterion traced to producing tasks; dependency graph,
file-overlap per wave, task atomicity/verifiability, honest-measurement discipline, frontmatter
validity, heavy-run hygiene; in-repo claims verified at source.

## Verdict: NEEDS_REVISION

1 HIGH, 5 MED, 4 LOW. **No structural replanning is required** — the plan set is well-built
(protocol-first ordering is structurally enforced, machinery is certified at proxy scale before
the heavy run, and the heavy plan is context-light with per-unit commits). All findings are
small, localized fixes: three verify-block rewrites, one status-vocabulary constant, two
frontmatter/mode bookkeeping patches. Once HIGH-1 and MED-1..4 are patched, the set is
execution-ready.

---

## 1. Goal & Requirement Coverage

| Success criterion (ROADMAP Ph. 42) | Producing plans/tasks | Status |
|---|---|---|
| 1. Protocol (gain definition, frozen config, refusal ladder, ablation axes) committed BEFORE any Case A run | 42-01 Task 1 (own first commit) + fail-loud guard (42-01 Task 3) enforced as first executed code path in runner (42-03 Task 2) + source-contract test pinning the guard | COVERED (structurally enforced, not aspirational) |
| 2. Sign-safe DADP-vs-FIT gain at 784 houses, seeds 42–46, honest refusal rows, centralized cross-check | 42-03 (runner), 42-05 Task 1 (headline seeds) + Task 2 (crosscheck + lenses), 42-06 (writeup + :slow reproducibility) | COVERED — see HIGH-1 on Task 1's verify gate |
| 3. OFAT over 4 pre-registered axes + proxy restatement + non-tuned attribution statement | 42-01 §8 (axes pinned pre-run), 42-04 (modes + rebuild), 42-05 Task 3 (execution + completeness), 42-06 §5–6 (attribution prose) | COVERED — see MED-3 on the completeness gate |

| Requirement | Plans claiming it | Covered |
|---|---|---|
| REPRO-03 | 42-01, 42-03, 42-06 | ✅ |
| REPRO-04 | 42-02, 42-03, 42-05, 42-06 | ✅ |
| REPRO-05 | 42-02 (enabler), 42-03, 42-04, 42-05, 42-06 | ✅ |

No PROJECT.md requirement maps to Phase 42 beyond REPRO-03..05 (REQUIREMENTS.md §Phase map:
42 → REPRO-03/04/05 only). Deferred ideas correctly excluded: no SETL-08 five-way table, no
Appendix E digitization, no new devices (device-mix axis rebuilds the existing registered mix
only). **Scope-reduction scan: clean** — no "v1"/"static for now"/"future enhancement"/stub
language anywhere; every locked decision is delivered in full (Option B src seam is the
CONTEXT-sanctioned "unless genuinely necessary" clause, blessed in ROADMAP's own plan list).

## 2. Dependency & Wave Correctness

| Plan | Wave | depends_on | Verdict |
|---|---|---|---|
| 42-01 | 1 | [] | ✅ |
| 42-02 | 1 | [] | ✅ |
| 42-03 | 2 | [42-01, 42-02] | ✅ (uses 42-01 lib + 42-02 seam) |
| 42-04 | 3 | [42-03] | ✅ (extends 42-03 runner) |
| 42-05 | 4 | [42-03, 42-04] | ✅ |
| 42-06 | 5 | [42-05] | ✅ |

Acyclic; wave = max(deps)+1 everywhere; all context-referenced files exist by execution time
(proxy.csv/ablation.csv before 42-05; all five CSVs before 42-06; agreement.csv and
40-06-SUMMARY.md exist today). **Wave-1 parallel file overlap: none** (42-01: protocol/lib/
magnitude-test/README vs 42-02: comparison.jl/settlement-test). First measurement execution is
42-03 Task 3 (wave 2) — strictly after the protocol commit (wave 1), and the guard makes the
ordering self-enforcing. ✅

Protocol ordering within 42-01 is itself correct: Task 1 commits the protocol alone BEFORE the
RED test commit and the lib commit.

## 3. Scope Sanity

| Plan | Tasks | Files | Heavy runtime | Verdict |
|---|---|---|---|---|
| 42-01 | 3 | 4 | none (fast lane) | ✅ |
| 42-02 | 2 | 2 | full fast suite ~30–60 min (justified: byte-identical golden gate) | ✅ |
| 42-03 | 3 | 4 | proxy run, minutes | ✅ |
| 42-04 | 3 | 4 | 1/78-rung run, minutes | ✅ |
| 42-05 | 3 | 4 listed (⚠ see MED-1) | ~6–12 h serial, backgrounded per-unit | ✅ design |
| 42-06 | 3 | 3 | one :slow 784 re-run ~25–40 min + docs build | ✅ |

All plans 2–3 tasks, ≤4 files. The heavy work is deliberately one-plan-isolated with upsert
kill-anytime semantics and per-unit commits — context budget safe.

## 4. Honest-Measurement Discipline

- ✅ Protocol committed in its own commit before any run; guard fails loud on missing AND
  uncommitted protocol; `protocol_sha` stamped per row; append-only amendment policy.
- ✅ No golden on the measured magnitude anywhere; only sanctioned pins: the algebraically-exact
  `welfare_gain(110,100)` anchor and the 42-06 reproducibility band (band between two runs of
  the same code, verbatim-cited per 40-06 discipline, "never widen to fit" stated).
- ✅ Kill-anytime upsert; refusals are rows (`error:<Type>`, `fit_inexact`,
  `error:ladder_exhausted`, `:budget_exceeded`); gates/ρ/τ never touched; FIT retry is the ONE
  pre-registered solver tightening; ratio ban encoded in protocol + tests + source contract.
- ✅ 42-05 hygiene: ONE measurement process at a time (~4 GB), every heavy invocation backgrounded
  with generous timeouts (90/120 min), per-seed/per-axis commits, sequential execution, no
  poll-spin, kill-and-resume contract, no test suite concurrently.
- ❌ But see HIGH-1: Task 1's verify gate contradicts the honesty policy in exactly the
  pre-registered honest-failure cases.

## 5. Findings

### HIGH

**HIGH-1 [42-05 / Task 1 / verification_derivation — verify gate contradicts honesty policy]**
Task 1's `<verify>` asserts gain rows (`delta_pct` non-missing) for **exactly** seeds
[42,43,44,45,46]. But the plan's own execution notes (and the protocol) declare two honest
no-gain-row outcomes valid completions: `error:ladder_exhausted` (all rungs refused) and a
FIT leg still refused after the one sanctioned retry (42-03: "missing Δ columns with the honest
statuses"). If any seed hits either, the verify hard-fails — the executor is then forced to
choose between stopping mid-heavy-plan or manufacturing a gain row to pass the gate. A binding
gate that structurally incentivizes fabrication is a goal-level defect in the one phase whose
purpose is honest measurement.
**Fix (exact):** rewrite Task 1's verify to accept honest terminal states, e.g.:
```julia
gains = filter(r -> r.mode == "headline" && !ismissing(r.delta_pct), df)
covered = sort(unique([gains.seed;
    filter(r -> r.mode == "headline" && occursin("ladder_exhausted", string(r.status)), df).seed;
    filter(r -> r.mode == "headline" && startswith(string(r.status), "error:") && ismissing(r.delta_pct), df).seed]))
@assert covered == [42,43,44,45,46] "seeds without any committed outcome: ..."
@assert !isempty(gains) "no seed produced a gain row — report the refusal ledger"
@assert all(!isempty, gains.protocol_sha)
println("headline: ", nrow(gains), " gain rows (seeds ", unique(gains.seed),
        "), honest terminal rows for seeds ", setdiff(covered, gains.seed))
```
and reword the `<done>` to "gain rows for every seed that certified; honest terminal rows for
every seed that did not; spread reported over the certifying seeds" (success criterion 2's
"whatever its magnitude and sign" is then satisfiable under any honest outcome).

### MEDIUM

**MED-1 [42-05 / frontmatter + Task 2 — crosscheck/lenses modes unplanned upstream; files_modified incomplete]**
Task 2 runs `--mode crosscheck` and `--mode lenses`, but no upstream plan builds them: 42-03
defines exactly `headline`+`proxy`; 42-04 adds the four `ablation-*` modes. Task 2 says "add it
now as a small runner extension", yet 42-05's `files_modified` lists only the four result CSVs —
`scripts/case_a_magnitude.jl`, `scripts/README.md` (how-to-run cell), and possibly
`test/test_case_a_magnitude.jl` (whitelist contract) are missing. Risk: the executor modifies
files outside the declared set, and the 42-03 source-contract item ("the mode whitelist
`headline`/`proxy`") may fail if written as an exact-set assertion.
**Fix (exact):** (a) add `scripts/case_a_magnitude.jl` and `scripts/README.md` to 42-05
`files_modified`; (b) in 42-03 Task 1, state the whitelist assertion is `occursin`-contains (each
mode name present), never exact-set — or add a line to 42-05 Task 2: "extend the 42-03
source-contract item's mode list in the same commit"; (c) note in 42-05 Task 2 that
`ensure_all_schemas` must gain `crosscheck.csv` + `lens_summary.csv` before the failure branch
(WR-04), and that `git diff 42-04-SHA..HEAD -- src/` stays empty (the extension is script-side).

**MED-2 [42-03 ↔ 42-04 / cross-plan data contract — status vocabulary omits "reused"]**
42-04 Task 2 appends `proxy_ieee123`/`ieee13_default`/`full_784` rows to `ablation.csv` with
`status = "reused"` (provenance-transparent reuse). But 42-03 Task 3's committed-CSV structural
item pins the status vocabulary to `{ok, converged, error:CertificateError, error:ConvergenceError,
error:SolveFailedError, error:unconverged_admm, error:ladder_exhausted, fit_inexact}`
("prefix `error:` or the known ok-forms") over **every** CSV under `results/thesis_case_a_magnitude/`.
"reused" is neither — the suite goes red at 42-04/42-05 through no fault of the run.
**Fix (exact):** add `"reused"` to the status-vocabulary set in 42-03 Task 3's `<behavior>`
(and to the protocol's status list in 42-01 §5/§6, so protocol and test agree), with its
definition: "row copied from another committed CSV; `note` names the source file+row; never
re-solved, never fabricated".

**MED-3 [42-05 / Task 3 — population-axis completeness not gated; literal completeness check contradicts reuse design]**
The Task 3 `<verify>` checks only the 9 fixed (axis,variant) pairs (fit_params×3, price_range×3,
device_mix×3) and consciously skips the population axis ("labeled as rung_/proxy/reused rows").
The population curve is REPRO-05's gain-vs-population evidence — its presence is currently
enforced only by prose. Worse, the action's completeness check as literally written ("every
(axis, variant) pair in protocol section 8 appears in ablation.csv **at seed 42**; if any is
missing, RUN IT") would flag `proxy_ieee123`/`ieee13_default` (fixture seeds 20260719/20260718)
and demand re-running them at seed 42 — contradicting the pre-registered reuse design.
**Fix (exact):** extend the Task 3 verify with a population-axis assertion, e.g.:
```julia
pop = filter(r -> r.axis == "population", df42)
@assert !isempty(pop) "population axis missing"
@assert Set(pop.status) ⊆ Set(["ok","converged","reused", v for v in ["error:CertificateError","error:ConvergenceError","error:SolveFailedError","error:unconverged_admm","error:ladder_exhausted"]])
@assert any(occursin("rung", string(v)) for v in pop.variant) "rung curve missing"
```
and reword the action's completeness gate: "every fixed pair at seed 42; population axis =
rung rows (any honest status) + `proxy_ieee123`/`ieee13_default`/`full_784` rows present with
`status = "reused"` and their native fixture seeds in `note`".

**MED-4 [42-04 / frontmatter — wrong artifact path]**
`must_haves.artifacts[0].path` is `scripts/case_a_common.jl`; the file (per `files_modified`
and the artifact's own `provides` note) is `scripts/lib/case_a_common.jl`. Artifact-path-keyed
tooling (verification, undo, review scoping) would look for a non-existent file.
**Fix (exact):** change the path to `scripts/lib/case_a_common.jl`.

**MED-5 [systemic / all plans — `| tail -N` swallows verify exit codes]**
Multiple load-bearing `<automated>` verifies end in `... 2>&1 | tail -3`, which makes the
pipeline's exit status tail's (0) — the verify cannot fail on a red suite. Affected green-gates:
42-01 Task 3, 42-02 Task 2 (first clause), 42-03 Task 1/3 (second clause), 42-04 Task 1/2/3,
42-06 Task 1 (**the :slow reproducibility gate**) and Task 3 (**the phase closure fast-suite
gate**). For a measurement-honesty phase, gates that cannot fail are a real weakness.
**Fix (exact):** append an explicit exit-code check after each piped test command, e.g.
`...; test ${PIPESTATUS[0]} -eq 0` (bash) or drop the pipe and capture output to a file then
grep it; minimally, add it to 42-06 Task 1 and Task 3 and 42-01 Task 3 — the gates that
actually certify the phase.

### LOW

**LOW-1 [42-RESEARCH.md — `## Open Questions` lacks the `(RESOLVED)` marker].** Substance is
resolved and visibly adopted (Q1 → ieee123-primary/ieee13-secondary proxy pin in 42-01 §8c +
42-03; Q2 → Option B in 42-02; Q3 → generous budgets in 42-05). Fix: relabel the heading
`## Open Questions (RESOLVED)` with one-line resolutions.

**LOW-2 [42-06 / Task 2 verify — junk statement + docs-env risk].** `grep -c "make.jl" /dev/null`
is a no-op that always exits 1 (harmless only because it's `;`-chained — delete it). Also
`julia --project=. include("docs/literate/case_a_magnitude.jl")` will fail if the page imports
docs-env-only packages (CairoMakie is docs-env per RESEARCH). Fix: run the page-executes check
under the docs env (`julia --project=docs`), or state the page imports nothing beyond
CSV/DataFrames/stdlib.

**LOW-3 [42-04 / Task 3 — `--variant` token form ambiguous for the population axis].** Action
passes `--variant 0.01282051282051282` while the axis Dict/source contract pins fractions as
`1/78, 0.125, …` and rows as `rung_<fraction>`. Fix: state the accepted CLI token (e.g. accept
the decimal fraction and normalize to the Dict key, or accept `rung-1/78`) in Task 2's flag
validation.

**LOW-4 [coverage note — lens-row ledger conservation].** RESEARCH's test map lists "ledger
double-entry on any lens rows" under REPRO-03/04; no plan explicitly adds that item to the
committed-CSV structural test (42-03 Task 3 covers schema/status/Δ-identity only). Acceptable —
lens rows are persisted `compare_tariffs` output whose ledger conservation is already
golden-tested in test_settlement.jl — but a one-line Δ/conservation re-derivation for
lens_summary rows in 42-03 Task 3's item would close the map completely.

## 6. Codebase Spot-Checks (all claims verified at source)

| Claim (plan) | Verified |
|---|---|
| `compare_tariffs` signature has `fit_optimizer`/`time_limit_s`; `:admm` branch if/else at ~:303–323; no `agr_optimizer` (42-02) | ✅ exact |
| `solve_admm` `agr_optimizer` seam, default `nothing` byte-identical, untyped (42-02) | ✅ docstring verbatim |
| `AGR_TOL_RUNGS` String-keyed 4-rung Dict, stop-on-first-certified, hard stop (42-01/03) | ✅ `case_a_agreement.jl:118–127` |
| Sign-safe form `100·(w_dadp − w_fit)/abs(w_fit)` (42-01) | ✅ `thesis_case123_repro.jl:337`; `SEED_IEEE123 = 20260719` at :88 |
| `provenance_row`/`flatten_note` shape (42-01) | ✅ `tariff_comparison.jl:222–234` |
| `fit_baseline` λ_import/λ_export/λ_self + `optimizer` kwargs; FIT_λ_EXPORT = 9.6 (→4.8/19.2); social_fit cancellation (42-01/04) | ✅ `fit.jl:34–36, 382–396, 638–643` |
| `_case_a_house` fixed 3-device set, `pv_fraction` not used; `_case_a_rung_counts` nested prefixes; `case_a_household_map` (42-04) | ✅ `materialize.jl:349–394, 444–522, 723`; fractions = `DEFAULT_LADDER_FRACTIONS` (`case_a_scaling.jl:97`) |
| `build_population(sym, feeder, feeder_sym, profiles, seed)` arity (42-03) | ✅ `materialize.jl:546` |
| Registered config precedent: `welfare_admm = −378163.5654…` at `gap_1e-10`, 80 iters; centralized `tol_gap_1e-10` (42-01/05) | ✅ `agreement.csv` row 2 (note: `welfare_centralized` is −378163.5889 — plans cite the correct ADMM column) |
| `docs/make.jl` two registration sites (Literate tuple ~:19–58, pages tree "Experiments" ~:104–108); `settlement_equity.jl` structure + A1-asymmetry pattern :305–315 (42-06) | ✅ |
| Test harness: `TSODSO_TEST_SET` fast/slow/all, `TSODSO_TEST_FILES`, explicit `using TSODSO`, `expected_broken.txt` guard (all plans) | ✅ `runtests.jl:40–66` |
| CI scripts-index guard + expected_broken.txt exist | ✅ |
| 40-06-SUMMARY.md (band-pinning discipline input) exists | ✅ |
| `check_scripts_index.py` registration requirement (42-01/03) | ✅ `.github/scripts/check_scripts_index.py` |

## 7. Dimension Notes

- **Nyquist (Dim 8):** `nyquist_validation: true`; RESEARCH carries the Validation Architecture
  (test map + sampling + Wave-0 gaps) and every map row lands in a plan (sign-safety+guard →
  42-01; Δ-identity/CSV structure → 42-03; ablation integrity → 42-04/05; :slow re-run → 42-06).
  Every implementation task has an `<automated>` verify; no watch modes; no `MISSING` Wave-0
  references. Note: no separate `42-VALIDATION.md` file exists — this repo's convention keeps the
  test map in RESEARCH.md (PATTERNS confirms none exists repo-wide); treated as covered, not a
  finding beyond this note.
- **Research resolution (Dim 11):** see LOW-1 (marker only).
- **Pattern compliance (Dim 12):** all PATTERNS.md classifications are honored — runner →
  `tariff_comparison.jl` idioms (kv-flags, upsert, honest rows, entry guard) cited in 42-03;
  protocol → discipline sources (no analog) in 42-01; page → `settlement_equity.jl` + both
  make.jl sites in 42-06; tests → `test_settlement.jl` conventions throughout; shared patterns
  (honesty rows, upsert, provenance, seed handling, pre-planned Dicts, locked config, fail-loud
  guards, naming/commit conventions) referenced by every relevant plan.
- **Tier compliance (Dim 7c):** responsibility map respected — all measurement logic script-side;
  `src/` touched only by the sanctioned 42-02 additive kwarg; `fit_baseline`/`materialize`/
  `comparison` consumed, never modified; every plan re-asserts the `src/`-diff-is-empty check.
- **Context compliance (Dim 7/7b):** all locked decisions implemented (protocol path+ordering,
  sign-safe form + ratio ban, lenses-never-replace-headline, ladder-via-seam, frozen config,
  seeds 42–46 + spread + seed-42 anchor, FIT honest rows + one sanctioned retry, A1/A4 statement,
  4 pinned axes, no-tuning structural guard, upsert/kill-anytime, live-recomputed writeup,
  structural-only tests). Discretion areas (seed count=5, variant values, column layout, page
  structure) exercised within bounds. No deferred-scope creep.

## 8. Required Revisions Before Execution (checklist)

1. **HIGH-1** — rewrite 42-05 Task 1 verify + done for honest no-gain-row outcomes.
2. **MED-1** — 42-05 `files_modified` += runner/README; 42-03 whitelist = contains-not-exact (or
   same-commit test extension note); schema note for the two new CSVs.
3. **MED-2** — add `"reused"` to 42-03 Task 3 status vocabulary (+ protocol status list).
4. **MED-3** — 42-05 Task 3: automated population-axis assertion + per-type completeness gate.
5. **MED-4** — 42-04 artifact path → `scripts/lib/case_a_common.jl`.
6. **MED-5** — exit-code propagation on piped verifies (minimally 42-06 Tasks 1+3, 42-01 Task 3).
7. LOW-1..4 — optional but cheap.

All fixes are localized text edits to the plan files; no re-planning, no re-research, no
restructuring. After items 1–6, this plan set is APPROVED for execution.

---

## Revision 1 (2026-10-26) — APPLIED

All HIGH + MED findings applied; LOW-1..4 applied (advisory, trivial). Commits:

| Finding | Fix applied | Commit |
|---|---|---|
| HIGH-1 | 42-05 Task 1 verify rewritten: per-seed gain row OR honest terminal status (`error:ladder_exhausted` / `fit_inexact` / `error:<Type>` with missing Δ); ≥1 gain row overall asserted; `<done>` + must-have truth + success criterion reworded to "spread over the certifying seeds" | 84f5798 |
| MED-1 | 42-05 owns the crosscheck/lenses mode build (action + `files_modified` += `scripts/case_a_magnitude.jl`, `scripts/README.md`; `ensure_all_schemas` gains the two new CSVs pre-failure-branch; src-diff-stays-empty note); 42-03 whitelist contract is contains-not-exact | 84f5798 / 6dbf074 |
| MED-2 | `"reused"` added to 42-03 Task 3 status vocabulary (with definition) and pinned in the 42-01 protocol §8c reuse clause | 6dbf074 / 6c11f6b |
| MED-3 | 42-05 Task 3: automated population-axis assertions (rung curve present, honest-status subset incl. `reused`, three reuse rows at `status = "reused"`); completeness gate split per type (fixed pairs at seed 42; reuse rows at native fixture seeds in `note`) | 84f5798 |
| MED-4 | 42-04 `must_haves.artifacts[0].path` → `scripts/lib/case_a_common.jl` | 1f4db53 |
| MED-5 | All 12 `... \| tail -N` verifies across 42-01..42-06 now end with `test ${PIPESTATUS[0]} -eq 0` (green gates) / `-ne 0` (RED gates, asserting the expected failure) — incl. 42-06 :slow gate and phase-closure fast-suite gate | 6c11f6b / 9763318 / 6dbf074 / 1f4db53 / 8b2c419 |
| LOW-1 | 42-RESEARCH `## Open Questions (RESOLVED)` + one-line resolutions | eb3f5ac |
| LOW-2 | 42-06 Task 2: junk `grep -c "make.jl" /dev/null` removed; page-executes check runs under the docs env (`julia --project=docs`); page-imports note added to the action | 8b2c419 |
| LOW-3 | 42-04: `--variant` accepts Dict-key fraction or decimal token, normalized to the Dict key; Task 3 run uses `--variant 1/78` | 1f4db53 |
| LOW-4 | 42-03 Task 3 structural item: lens_summary ledger conservation re-derivation (`welfare ≈ dso_total + merchandising_surplus + aggregators_total`) | 6dbf074 |

All six plans re-validated after edits: `frontmatter.validate` (schema plan) and
`verify.plan-structure` both pass for 42-01..42-06.
