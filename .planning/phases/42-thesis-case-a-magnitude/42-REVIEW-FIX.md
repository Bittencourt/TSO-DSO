---
phase: 42-thesis-case-a-magnitude
fixed_at: 2026-10-26T00:00:00Z
review_path: .planning/phases/42-thesis-case-a-magnitude/42-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 42: Code Review Fix Report

**Fixed at:** 2026-10-26
**Source review:** `.planning/phases/42-thesis-case-a-magnitude/42-REVIEW.md`
**Iteration:** 1
**Scope:** BL-01, WR-01, WR-02, WR-03 (the 5 INFO findings are out of scope per the orchestrator)

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

**Test evidence (fast lane, `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_case_a_magnitude.jl`, one foreground Julia process at a time):**
- RED (BL-01): `599 passed, 0 failed, 1 errored` — the new item errored with the diagnosed `FieldError` on `err.iterations` inside the catch handler.
- RED (WR-01): `608 passed, 4 failed, 0 errored` — the stub's out-of-vocabulary status was mislabeled `:budget_exceeded` with the fabricated budget note.
- GREEN after each fix; final sweep after all commits: **exit 0, 612/612 passed**.
- Literate page execution check (`julia --project=docs -e 'include("docs/literate/case_a_magnitude.jl")'`): **exit 0**; live prints reproduce the previously hand-copied figures (attribution 42/46→`gap_1e-10`, 43/44/45→`default`, refusal iters 80; `scale_0.5` exhausted at iters 88, `scale_2.0` certified at `default` iters 52; Δ%/factors 1.35e-2 %/×1.85e3, 1.85e-5/×1.35e6, 2.38e-6/×1.05e7, 1.33e-5/×1.88e6).

## Fixed Issues

### BL-01: Ladder rung recorder reads a nonexistent `iterations` field on `SolveFailedError`

**Files modified:** `scripts/case_a_magnitude.jl`, `test/test_case_a_magnitude.jl`
**Commit:** `4861c81`
**Applied fix:** Field-aware iters extraction in `run_rung_outcome`'s typed-failure recorder — `hasproperty(err, :iterations) && err.iterations !== nothing ? Int(err.iterations) : -1`; `SolveFailedError` (no `iterations` field, `src/core/errors.jl:33-39`) now yields the documented −1 sentinel instead of a `FieldError` inside the catch handler. New RED→GREEN regression item "magnitude rung outcome: SolveFailedError records the honest error row (field-aware iters)": the stub extends `TSODSO.solve_admm` with a marker-typed signature the real method (`AbstractFeeder, AbstractPowerFlow, AbstractVector{<:Aggregator}`) cannot accept, so dispatch lands on the stub — no solving, seconds. RED: item errored with the FieldError; GREEN: `(status = "error:SolveFailedError", iters = -1)`, welfare missing, message kept, plus a `CertificateError` pin showing a carried iteration count (37) survives.
**Status:** fixed (logic test-pinned — the exact corrected behavior is asserted by the passing regression test)

### WR-01: Non-converged, non-budget result is labeled `:budget_exceeded` without checking the status

**Files modified:** `scripts/case_a_magnitude.jl`, `test/test_case_a_magnitude.jl`
**Commit:** `a1cc417`
**Applied fix:** Implemented the orchestrator's record-verbatim variant (not the review's throw): the else branch labels `:budget_exceeded` only when `r.status === :budget_exceeded`; any other non-certified returned status is recorded AS ITSELF (`":" * string(r.status)`, welfare `missing`, `iters` kept, note naming the actual status and never relabeled). Docstring contract updated accordingly. Note: a future vocabulary member lands in the CSV as `:<status>`, which the structural status-vocabulary gate then refuses until admitted deliberately — the same deliberate-act friction the phase uses everywhere else. RED→GREEN pin: "magnitude rung outcome: a non-budget, non-certified status is recorded verbatim" (RED: 4 failures on the fabricated `:budget_exceeded` label; GREEN: verbatim status, iters 11, no "budget" in the note).
**Status:** fixed (logic test-pinned)

### WR-02: Structural test's ledger-alias assertion is wrong for the FIT leg

**Files modified:** `test/test_case_a_magnitude.jl`
**Commit:** `f6fad01`
**Applied fix:** The `merchandising_surplus` identity is now per-kind: the named-line alias (`merchandising_surplus ≈ dso_total`, `SettlementLedger.jl:403`) asserts only on `dadp`/`flat`/`tou` rows; `fit` rows assert the actual identity (`merchandising_surplus ≈ dso_total − wholesale_total`, `comparison.jl:733`) when all three columns are finite Reals — refused FIT rows still guard-skip on missing values. The item's docstring comment now states the per-kind contract. Fast suite green over the committed `lens_summary.csv`; the first honest FIT-ok lens row will assert the right identity instead of failing spuriously.

### WR-03: Writeup prose embeds hand-derived figures that can silently desync

**Files modified:** `docs/literate/case_a_magnitude.jl`
**Commit:** `b5ece3a`
**Applied fix:** The review's first option, implemented live (the `25.0/dp` pattern extended): (1) headline prose genericized + a live seed→rung attribution print (certified rung → seeds, and the default-rung refusal iters); (2) price-range prose genericized + live verdict prints (exhaustion terminal state, rung-row count, per-rung iters; the certifying rung and iters) ahead of the per-rung ledger; (3) attribution item 2's rounded Δ%/factors deleted, replaced by an every-certified-pair-vs-+25% table (sign-safe Δ% and the `25.0/Δ%` factor over all ablation pairs plus the proxy); (4) the sha-trail annotation replaced by a live distinct-`protocol_sha` count plus the dated amendment citation — no hand-copied sha prefixes. The structural UNDEFINED/NOT-FULLY-ATTRIBUTED ternaries are untouched, as instructed. Verified: page execution exits 0 and every live print reproduces the previously hand-copied value (see evidence above).
**Status:** fixed (one iteration mid-fix: `@printf` rejects a `*`-concatenated format string — "First argument to `@printf` after `io` must be a format string"; the sha-trail line was switched to `println` with interpolation. Caught by the page execution check, re-run green.)

## Out of Scope (not attempted, per orchestrator)

The 5 INFO findings (NF-01..NF-05) remain open, untouched: NF-01 (provenance constant pin), NF-02 (crosscheck status conflation), NF-03 (centralized leg catches only `CertificateError`), NF-04 (FIT leg has no wall-clock budget path), NF-05 (`LENS_COLS` declared but unenforced).

## Commits (in execution order, on `gsd-reviewfix/42-*` → fast-forwarded to the session branch)

1. `4861c81` — fix(42): BL-01 — field-aware iters in the ladder's typed-failure recorder + honest-error-row regression test
2. `a1cc417` — fix(42): WR-01 — only the actual budget status earns `:budget_exceeded`; others recorded verbatim (RED→GREEN pin)
3. `f6fad01` — fix(42): WR-02 — lens ledger-alias assertion is per-kind (derived tariffs alias; FIT-ok asserts `dso_total − wholesale_total`)
4. `b5ece3a` — fix(42): WR-03 — writeup prose figures recomputed live; no hand-copied derived numbers
5. `0243127` — docs(42): mark review findings fixed (the **Fixed** notes in `42-REVIEW.md`)

---

_Fixed: 2026-10-26_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
