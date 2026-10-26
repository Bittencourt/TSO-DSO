---
phase: 42-thesis-case-a-magnitude
reviewed: 2026-10-26T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - CLAUDE.md
  - scripts/case_a_magnitude.jl
  - scripts/lib/case_a_common.jl
  - src/settlement/comparison.jl
  - test/test_case_a_magnitude.jl
  - docs/literate/case_a_magnitude.jl
  - docs/make.jl
  - scripts/README.md
  - .planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md
findings:
  critical: 1
  warning: 3
  info: 5
  total: 9
status: issues_found
---

# Phase 42: Code Review Report

**Reviewed:** 2026-10-26
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the Phase 42 pre-registered magnitude measurement end-to-end: the runner
(`scripts/case_a_magnitude.jl`), the shared lib, the `compare_tariffs` `agr_optimizer` seam
(diffed byte-for-byte against the phase-41 base `b99a5b7` — the change is exactly the kwarg
plus the docstring plus unconditional `nothing`-default forwarding; default behavior is
byte-identical), the structural/:slow tests, the literate writeup, both make.jl registration
sites, the README index, and protocol/script consistency (seeds, rungs, rung order, ladder
policy, FIT retry call, crosscheck tightening, ablation axes/variants, proxy fixtures and
seeds, amendment — all match the committed protocol text).

Verified clean: the sign-safe gain is computed only by `welfare_gain` and only on a
finite Real pair; ladder stop-on-first-certified + hard stop is correct; upsert keys
(`:mode|fixture|axis|variant` + seed + t_horizon + kind + rung) have no collision paths
(including the two distinct full-population reuse labels `rung_1.0`/`full_784`); reuse rows
copy source values verbatim and never re-solve; `protocol_sha` is stamped on every row path
(all mains call the gate before any write); no code path can fabricate a gain row; the
writeup's UNDEFINED headline is structural (computed ternary + NaN guard) and its derived
percentages recompute live from the CSVs (spot-checked against the committed rows — they
reproduce the committed `delta_pct` columns exactly); the :slow band is an agreement band on
plumbing, not a magnitude golden, per protocol §10.

One BLOCKER: the ladder's typed-failure recorder crashes with `FieldError` on
`SolveFailedError` (the type has no `iterations` field) — the honest-record path for a real,
occurring failure class is broken and would kill the run mid-ladder.

## Critical Issues (BL-)

### BL-01: Ladder rung recorder reads a nonexistent `iterations` field on `SolveFailedError` — FieldError crash instead of the honest error row

**File:** `scripts/case_a_magnitude.jl:520` (catch block at 515–522)

**Issue:** `run_rung_outcome` claims to record all three typed solver failures as
`error:<TypeName>` rows, with "iters from the typed error, −1 sentinel when the error
carries none" (header lines 84–85 and docstring 476–478). But `SolveFailedError`
(`src/core/errors.jl:33-39`) has fields `msg, termination_status, primal_status,
dual_status, raw_status` — **no `iterations` field**. When `solve_admm` throws
`SolveFailedError` (its documented behavior on solver failure, `solve_admm.jl:309-311` —
and INFEASIBLE `SolveFailedError` is this repo's most common 784-house failure class: every
FIT leg hit it), `err.iterations` at line 520 raises `FieldError` **inside the catch
handler**, which propagates: the rung's honest row is never written, the ladder never
reaches its `error:ladder_exhausted` terminal state, the FIT leg and gain row for that
point are lost, and in ablation modes all *subsequent variants* are lost — the opposite of
the phase's central honesty contract. Latent so far: the committed CSVs contain
`error:SolveFailedError` only on `kind=gain` rows (the FIT path via `run_fit_outcome`,
which safely reads only `err.msg`); no `kind=rung` SolveFailedError has occurred yet.

**Fix:**
```julia
iters = if err isa Union{ConvergenceError, CertificateError}
    err.iterations === nothing ? -1 : Int(err.iterations)
else
    -1   # SolveFailedError carries no iteration count — the documented sentinel
end
```
(Or `hasproperty(err, :iterations) && err.iterations !== nothing ? Int(err.iterations) : -1`.)
Add a RED→GREEN test item: a `SolveFailedError("x")` thrown from a stubbed solve must yield
`(status = "error:SolveFailedError", iters = -1)` from `run_rung_outcome`.

**Fixed (2026-10-26):** commit `4861c81` — field-aware iters extraction
(`hasproperty(err, :iterations) && err.iterations !== nothing ? Int(err.iterations) : -1`)
with the −1 sentinel for field-less types, exactly as suggested. RED→GREEN regression
test item "magnitude rung outcome: SolveFailedError records the honest error row
(field-aware iters)" (`solve_admm` stubbed at the dispatch seam — RED: FieldError inside
the catch handler, item errored; GREEN: the honest `error:SolveFailedError` row with
`iters = -1`, plus a `CertificateError` still carrying its own count). Fast suite green
(612/612).

## Warnings

### WR-01: Non-converged, non-budget result is labeled `:budget_exceeded` without checking the status

**File:** `scripts/case_a_magnitude.jl:504-513`

**Issue:** The `else` branch of `run_rung_outcome` stamps ANY non-certified returned result
as `status = ":budget_exceeded"` with a message asserting a wall-clock budget exit. Today
`solve_admm` returns only `:converged | :budget_exceeded` (`STATUS_VOCABULARY`,
`errors.jl:136`), so the branch is budget-only — but nothing asserts that. If the status
vocabulary ever gains a member, it would be silently recorded with a fabricated
explanation — exactly the dishonest-status-labeling the phase guards against elsewhere.

**Fix:** Guard before labeling:
```julia
r.status === :budget_exceeded || error(
    "run_rung_outcome: unexpected non-certified status $(repr(r.status)) — refusing " *
    "to label it :budget_exceeded (record it deliberately instead)",
)
```

**Fixed (2026-10-26):** commit `a1cc417` — implemented as record-verbatim rather than
throw (keeps the honest-record contract): the else branch labels `:budget_exceeded` only
when `r.status === :budget_exceeded`; any other non-certified status is recorded AS
ITSELF (`:<status>`, no welfare, note naming the actual status) instead of receiving a
fabricated budget explanation. RED→GREEN pin: "magnitude rung outcome: a non-budget,
non-certified status is recorded verbatim" (out-of-vocabulary stub status — RED: 4
assertions failed on the fabricated `:budget_exceeded` label; GREEN: verbatim status,
iters kept, no budget story in the note). Fast suite green (612/612).

### WR-02: Structural test's ledger-alias assertion is wrong for the FIT leg — spurious suite failure on the first honest FIT-ok lens row

**File:** `test/test_case_a_magnitude.jl:252-262` (counter-example: `src/settlement/comparison.jl:733`)

**Issue:** The test asserts `merchandising_surplus ≈ dso_total` on every lens row where
both are finite Reals, justified as "the ledger's named-line ALIAS". That alias holds for
dadp/flat/tou (`comparison.jl:531-532, 630-631`), but the FIT-ok leg sets
`merchandising_surplus = dso_total - wholesale_total` (`comparison.jl:733`) — deliberately
NOT the alias. The assertion is currently masked because every committed FIT lens row is
refused (values `missing` → guard skips), but FIT certifies at proxy scale
(`proxy.csv` ieee123-default), so any future lens run where FIT certifies produces a
committed artifact that fails the fast structural suite spuriously — and until then the
test encodes a false model invariant.

**Fix:** Restrict the alias assertion to `r.tariff in ("dadp", "flat", "tou")`, and for the
FIT leg assert the actual identity (`merchandising_surplus ≈ dso_total - wholesale_total`)
when both sides exist.

**Fixed (2026-10-26):** commit `f6fad01` — as suggested: the alias now asserts only on
dadp/flat/tou rows; FIT rows assert the actual identity
(`merchandising_surplus ≈ dso_total − wholesale_total`) when all three columns are
finite Reals (refused FIT rows still guard-skip on missing values). The item's
docstring comment states the per-kind identity. Fast suite green (612/612) over the
committed `lens_summary.csv`; a future honest FIT-ok lens row now asserts the right
identity instead of failing spuriously.

### WR-03: Writeup prose embeds hand-derived figures that restate the live computations and can silently desync from the committed CSVs

**File:** `docs/literate/case_a_magnitude.jl:161-163, 296-298, 483-493, 472-475`

**Issue:** The page contract (lines 19–22) promises "Every relative figure below is
RECOMPUTED LIVE from the committed rows". The live slices do recompute — but the
surrounding prose hard-codes derived values that narrate them: "seeds 42 and 46 at the
`gap_1e-10` rung … 43/44/45 at the `default` rung", "refusal at iters = 80" (161–163),
"all four pre-registered rungs refuse at iters = 88" (297), and the attribution section's
rounded Δ% values and +25%-distance factors "≈+1.4e-2 % (≈1.9e3)", "≈+1.8e-5 % (≈1.4e6)",
"≈+2.4e-6 % (≈1.1e7)", "≈+1.3e-5 % (≈1.9e6)" (488–493), plus the sha-trail annotation
"(60e5d549… = the pre-run protocol; af815b0… = the amendment)" (472–475). If any CSV is
re-measured, the live prints change and the prose silently goes stale — the exact
Phase-28-CR-01 failure mode this page cites. (The UNDEFINED headline and the
per-axis-effect UNDEFINED strings ARE structural — computed ternaries/NaN guards; only
these prose restatements drift.)

**Fix:** Either compute the rounded factors live (the `25.0 / dp` pattern at 348–357
already does this for two variants — extend it and delete the prose numbers), or qualify
each prose figure as a dated citation of the page source ("as committed at page-source
write time"), so a future re-measurement visibly contradicts rather than silently
disagrees.

**Fixed (2026-10-26):** commit `b5ece3a` — the first option, implemented live: the
seed→rung attribution, the price-range verdicts (exhaustion terminal state, rung-row
count and iters; the certifying rung and iters), the sha-trail annotation (live
distinct-sha count + the dated amendment citation; no hand-copied prefixes), and an
every-certified-pair-vs-+25% table (sign-safe Δ% and the 25.0/Δ% factor — the 348–357
pattern extended to all pairs plus the proxy) all recompute from the committed CSVs
adjacent to their use; the hand-copied prose numbers are deleted. The structural
UNDEFINED/NOT-FULLY-ATTRIBUTED ternaries are untouched (as verified correct).
Verified: `julia --project=docs -e 'include("docs/literate/case_a_magnitude.jl")'`
exits 0, and the live prints reproduce the previously hand-copied values (attribution
42/46→gap_1e-10, 43/44/45→default, refusal iters 80; scale_0.5 exhausted at iters 88,
scale_2.0 certified at default iters 52; Δ%/factors 1.35e-2 %/1.85e3, 1.85e-5/1.35e6,
2.38e-6/1.05e7, 1.33e-5/1.88e6).

## Info

### NF-01: Hand-copied provenance constant `0.263` is unpinned, and the section header overstates the restatement outcome

**File:** `docs/literate/case_a_magnitude.jl:359, 372`

**Issue:** `const PROVENANCE_PROXY_PCT = 0.263` is transcribed from
`scripts/thesis_case123_repro.jl` with no source-contract pin — if the upstream
restatement figure is ever revised, this citation drifts silently. Additionally the
section header "The proxy restatement — ≈+0.263% under the registered definition" reads as
the outcome, while the measured value under the registered definition is ≈+0.0135% (the
live print directly below honestly reports a factor ≈19.5 below the citation; protocol §8's
"same order of magnitude is expected" is not met, and is not claimed to be).

**Fix:** Pin the constant with a source-contract assertion (an `occursin` test on
`thesis_case123_repro.jl`), and reword the header to name both numbers, e.g. "measured
≈+0.0135% vs the cited ≈+0.263% (reported proximity, never gated)".

### NF-02: Crosscheck `status` column conflates the two independent legs

**File:** `scripts/case_a_magnitude.jl:1337`

**Issue:** `status = welfare_c isa Real ? "ok" : "error:CertificateError"` — a row whose
price re-fetch refused but whose centralized leg certified still stamps `ok` (the missing
price lens is discoverable only by reading the note), and the failure label is
hardwired to `CertificateError` regardless of which leg failed or how.

**Fix:** Derive status from both legs, e.g. `ok` / `error:centralized:<kind>` /
`error:price_refetch:<kind>` (or keep `ok` but only when both lens quantities are present).

### NF-03: Centralized leg records only `CertificateError` refusals; other typed failures crash instead of recording

**File:** `scripts/case_a_magnitude.jl:1209, 1228`

**Issue:** `_run_centralized_leg` catches only `CertificateError`; a `ConvergenceError` or
`SolveFailedError` from `solve_welfare` propagates and kills `crosscheck_main`. The
header-only-CSV guarantee (`ensure_all_schemas`) still holds, but protocol §6's "a
still-refused centralized solve is a recorded outcome" is implemented for one failure class
only.

**Fix:** Widen the two catch filters to the solver-failure trio (as `run_fit_outcome`
does) and record `error:<Type>` rows with `centralized_optimizer = "refused:..."`.

### NF-04: FIT leg has no wall-clock budget path

**File:** `scripts/case_a_magnitude.jl:673-739, 761`

**Issue:** `--time-limit-s` bounds the AGR ladder (and `compare_tariffs`' ADMM engine), but
`run_fit_outcome` accepts and forwards no budget: a budget-bounded headline/ablation run
can still stall unboundedly in the FIT leg, and the honest `:budget_exceeded` vocabulary
has no FIT counterpart.

**Fix:** Either document that the budget intentionally scopes the ladder only, or thread a
deadline into the FIT attempt/retry and record a `:budget_exceeded`-style row on expiry.

### NF-05: `LENS_COLS` is declared but never enforced

**File:** `scripts/case_a_magnitude.jl:954-987` (declaration), `1458-1469` (unguarded write)

**Issue:** The declared-column guard (`all(c in keys(row) for c in cols) || error(...)`)
exists only in `write_point_rows`; lens rows are upserted directly without it, so a future
`compare_tariffs` summary-schema change could silently drop declared columns from
`lens_summary.csv` (`cols = :union` fills nothing for absent keys).

**Fix:** Apply the same merged-row guard before the lens `upsert_row` calls (both the
summary path and the `(run)` refusal row).

---

_Reviewed: 2026-10-26_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
