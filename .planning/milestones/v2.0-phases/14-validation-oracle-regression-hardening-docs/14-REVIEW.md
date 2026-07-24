---
phase: 14-validation-oracle-regression-hardening-docs
reviewed: 2026-07-24T11:30:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - test/fixtures_planning.jl
  - test/test_planning_goldens.jl
  - test/test_planning_noninteger.jl
  - test/test_planning_coupling.jl
  - test/test_planning_nash.jl
  - docs/src/api.md
  - docs/literate/stackelberg_benders.jl
  - docs/literate/nash_diagonalization.jl
  - docs/make.jl
  - src/planning/checkpoint.jl
  - src/solver/factory.jl
  - src/units/PerUnit.jl
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: clean
---

# Phase 14: Code Review Report — Iteration 2 (fix verification)

**Reviewed:** 2026-07-24
**Depth:** standard
**Files Reviewed:** 12
**Status:** clean (no Critical or Warning findings; 2 non-blocking Info observations recorded below)

## Summary

Iteration-2 re-review of the four fix commits (`22376a5` CR-01, `f00ba15` WR-01, `72068fc` WR-02, `9cfa683` WR-03). All four iteration-1 findings are **fixed correctly and completely**, and the src-touching fixes (checkpoint string keys, HiGHS `output_flag`) were verified live to not break behavior. The four in-scope test files not touched by the fixes are byte-identical to the iteration-1-reviewed state (`git diff d4f9..HEAD` empty for them). No new Critical or Warning defects were introduced. Two new Info-level observations (side effects of the WR-01/WR-02 fixes) are recorded; they do not gate.

### Fix-by-fix verification

**CR-01 (`22376a5`, docs pages) — VERIFIED FIXED.**
- `docs/literate/stackelberg_benders.jl:59-79` now states the equivalence precisely: `Deferrable` **keeps** the `−(b/2)·E²` constant (matches `src/devices/Deferrable.jl:212`'s `-(d.b/2)*(total_energy - d.E)^2` verbatim), the RESEARCH A5 misattribution is explicitly corrected ("A5 only sanctions dropping eq. 3.12's separate additive constant `c`, NOT this expansion term"), and the page pre-announces `UB ≈ −0.245 + 18 = 17.755`.
- The `result.UB` display (lines 135-139) is reconciled in place, and a new offset-corrected display `result.UB - 0.5 * 1.0 * 6.0^2` (line 144) makes the number directly comparable to the certified `−0.245`. Arithmetic checks: `(b/2)E² = 0.5·1.0·36 = 18`; `17.755 − 18 = −0.245` (matches iteration 1's live-executed `UB = 17.75500113…`).
- The gap-normalizer consequence (`~17.8× looser` = `17.755 / max(1, 0.245)`; converged `z` "a few 1e-3 short of 0.7", live `0.6985`) is stated at both the claim (lines 76-79) and the `result.z` display (lines 124-131). Numbers verified against benders.jl:99's `max(1, |UB|)` normalization.
- `docs/literate/nash_diagonalization.jl:66-77` carries the matching one-paragraph qualification, and its claim "This page displays no objective-level quantities" is verified true: the page displays only `result.converged`, `result.z`, `result.x_inv`, `probe.summary`, `probe.spread` — none carries the `+18` offset.

**WR-01 (`f00ba15`, tripwire) — VERIFIED FIXED.** All four silent false-negative shapes are closed (`test/test_planning_noninteger.jl:92-123`): short-form via `(?:function\s+)?`, indentation via `^\s*`, subdirectories via `walkdir`, out-of-tree builders via the semantic export channel. Verified by execution, not just reading:
- The hardened file-scan, run live against current `src/planning/`, finds exactly the 4 registry keys (follower.jl:94, subproblem.jl:110, coupling.jl:174, master.jl:92) with zero false positives — the triple-quote docstring tracker correctly skips all docstring signature-convention lines that would otherwise match the widened regex.
- The semantic channel, run live with `TSODSO` loaded: `names(TSODSO)` yields exactly 10 exported `build_*` symbols; the 6-entry `operational_builders` allowlist was verified entry-by-entry against actual `export` statements (ieee123.jl:446, AgrOpt.jl:237, DsoOpt.jl:372, materialize.jl:298); `setdiff` leaves exactly the 4 planning builders (coupling.jl:438 confirms `build_shared_transmission` is exported). `found == Set(keys(registry))` holds.
- The full testitem (plus the checkpoint suite) passes: 22/22.

**WR-02 (`72068fc`, docs plumbing) — VERIFIED FIXED.**
- `SMAX_NO_LIMIT` now has a properly attached docstring (`src/units/PerUnit.jl:62-73`, `"""` block immediately above the `const` — binds correctly), and the Units `@autodocs` block (`docs/src/api.md:35-39`) covers `units/PerUnit.jl` with `Order = [:type, :constant, :function]`, so the newly documented export is surfaced and `checkdocs = :exports` is satisfied. The `[`assert_magnitudes`](@ref)` link resolves within the same section (assert_magnitudes is documented at PerUnit.jl:95-109 and surfaced there).
- `:constant` was added uniformly to all 12 `@autodocs` blocks; cross-checked every `include` in `src/TSODSO.jl` against the union of api.md `Pages` filters — every source file is covered, so no documented export can fall outside a section.
- `docs/make.jl:69-80` now accurately describes `checkdocs = :exports` ("documented-but-UNSURFACED"), documents the known limit (undocumented exports pass silently), and records the `:constant`-in-`Order` invariant. No exported macros exist in `src/` (verified by grep), so the absence of `:macro` from `Order` is currently safe.

**WR-03 (`9cfa683`, checkpoint keys + HiGHS silence) — VERIFIED FIXED, src changes behavior-safe.** This was the flagged risk area; verified by live execution:
- **Checkpoint roundtrip:** `checkpoint_iteration!` now saves `Dict("iteration" => …, "state" => …)` (string keys) and `resume_from_checkpoint` reads `dict["iteration"]`/`dict["state"]` (checkpoint.jl:111) — consistent. Live roundtrip verified: fresh save → resume returns correct `(; iteration, state)`; redo-same-iteration (the safesave/`iter_NNNNN_#1` backup path, CR-02's regression case) → resume returns the *fresh* state, no JLD2 symbol-key warning emitted anywhere. Backward compatibility holds by construction: JLD2 always coerced symbol keys to strings on disk (that coercion *was* the warning), so pre-fix checkpoint files load identically.
- **Test suite:** `test/test_planning_checkpoint.jl` + `test/test_planning_noninteger.jl` pass 22/22.
- **HiGHS `output_flag`:** attribute name is correct and effective — live `solve_follower!` under `redirect_stdout` produced **0 bytes** of console output. Grep across `src/`, `test/`, `docs/` finds zero dependencies on HiGHS console output and zero other verbosity settings that could conflict. The `solve_with_retry!` escalation ladder (retry.jl) sets only Clarabel-specific attributes and never touches `output_flag`, so no re-verbose path exists. The factory comment's placement claim (comment above, not between, docstring and definition) is structurally correct — docstring attachment to `select_optimizer(::LP)` is preserved.
- Repo hygiene note: this review's own test-environment activation transiently touched `test/Project.toml`/`test/Manifest.toml`; both were restored to HEAD before writing this report. No source files were modified by the review.

The 4 iteration-1 Info findings (IN-01..IN-04) remain out of scope per the orchestrator instruction; none worsened (their files are unchanged).

## Info

*(Non-blocking observations arising from the fixes — recorded for the ledger, no gate.)*

### IN-05: api.md `Order` widening also surfaces documented **private** constants on the "public API" reference page

**File:** `docs/src/api.md:46,109` (Network Data Model, Experiment Harness sections)
**Issue:** Iteration 1's fix suggestion claimed adding `:constant` uniformly "is a no-op for sections with no documented constants" — that premise is wrong for two sections. Documenter's `@autodocs` defaults to `Private = true`, so the widened `Order` now additionally renders documented *non-exported* constants: `IEEE13_BASE`, `IEEE13_INTERIOR_SMAX` (ieee13.jl:29,50), `IEEE123_BASE`, `IEEE123_ROOT_TERMINAL`, `IEEE123_HEAD_SMAX_MVA`, `IEEE123_SWITCH_EDGES` (ieee123.jl), and the four `SCENARIO_VALID_*` constants (Scenario.jl:26-42) — under a page whose intro promises "the public `TSODSO` API". No build break (`checkdocs = :exports` ignores private symbols) and consistent in kind with pre-existing behavior (private documented functions/types were already included), but the page's "public API" framing is now slightly less accurate.
**Fix:** Either accept (internals-documented-too is defensible for a research bench) and soften the api.md intro sentence, or add `Private = false` to the `@autodocs` blocks if the page should be strictly public-API.

### IN-06: Tripwire's triple-quote tracker can be flipped by a stray odd count of `"""` in a comment line — residual (contrived) false-negative shape for *unexported* builders only

**File:** `test/test_planning_noninteger.jl:96-105`
**Issue:** A non-docstring line containing an odd number of `"""` occurrences (e.g. a `#` comment quoting a lone `"""`) inverts `in_docstring` and silently suppresses the file-scan for the remainder of that file. Unlike the widened regex's false *positives* (loud, correct polarity), this shape is a silent false *negative* — but only for a builder that is *also unexported*, since the semantic export channel (lines 108-122) independently catches every exported `build_*` regardless of file content. All four current builders are exported and no such stray `"""` exists in `src/planning/` today (verified by running the scan live). Materially narrower than the original WR-01 shapes; recorded for completeness.
**Fix:** None required. If ever hardened further, prefer `Meta.parse`-based walking of each file's expressions over line regexes.

---

_Reviewed: 2026-07-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (iteration 2 — fix verification with live execution of tripwire, checkpoint roundtrip, and solver-silence checks)_
