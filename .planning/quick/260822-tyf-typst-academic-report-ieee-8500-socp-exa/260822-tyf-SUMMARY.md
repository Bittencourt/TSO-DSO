---
quick_id: 260822-tyf
subsystem: docs
tags: [typst, documentation, ieee8500, socp, exactness, benchmark, writeup]

# Dependency graph
requires:
  - phase: 25-ieee-8500-scalability-benchmark
    provides: deferred-items.md/25-DATA-PROVENANCE.md (investigation record), quick tasks 260822-oi7/pxb/rle (diagnosis + two merge passes), results/ieee8500_benchmark/{socp_gap_report,noise_floor_calibration}.csv (committed evidence)
provides:
  - docs/writeups/ieee8500_exatidao_socp.typ — pt-BR academic report consolidating the eight-stage IEEE-8500 SOCP-exactness investigation (three explicitly-labelled wrong turns, three-pass result table, final mesh state)
affects: [docs/writeups/README.md, future thesis-appendix assembly, Phase 25 follow-up work referencing this investigation]

# Tech tracking
tech-stack:
  added: []
  patterns: ["house-style-matched pt-BR Typst investigation report (auditable-including-wrong-turns narrative pattern), reused thesis_caseA.typ/stackelberg_vs_psr_n1n2.typ preamble verbatim"]

key-files:
  created: [docs/writeups/ieee8500_exatidao_socp.typ]
  modified: [docs/writeups/README.md]

key-decisions:
  - "Transcribed every number verbatim from the plan's embedded content (itself sourced from deferred-items.md/25-DATA-PROVENANCE.md/three quick-task summaries/two CSVs) — no figure re-derived or rounded differently."
  - "Kept 'Superada no Estágio H' exactly as given (the Stage-H bus-merge is the actual superseding event for the Stage-B fabricated impedance, not 'Estágio F' as an earlier orchestrator framing had claimed) — per the plan's explicit correction, not reverted."
  - "Found and fixed a real Typst rendering bug during the mandatory PNG visual-inspection step: bare '~' in prose (\"~2.000x\", \"~40x\") is Typst markup for a non-breaking space, not a literal tilde — it silently disappeared from the rendered PDF despite a clean `typst compile` exit 0. Escaped both occurrences as `\\~`. `r_pu ~ 3,2e-6` inside backticks was unaffected (raw/code spans don't interpret markup)."

requirements-completed: []

# Metrics
duration: 25min
completed: 2026-08-22
---

# Quick Task 260822-tyf: IEEE-8500 SOCP-Exactness Investigation Writeup Summary

**New Typst report (`docs/writeups/ieee8500_exatidao_socp.typ`) consolidating the scattered eight-stage IEEE-8500 SOCP-exactness investigation — including three explicitly-labelled wrong turns and the three-pass bus-merge result table — into one pt-BR, house-style-matched document; found and fixed a silent Typst tilde-escaping bug during mandatory PNG rendering inspection.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-22T21:30:00Z (approx, worktree reset + file reads)
- **Completed:** 2026-08-22T21:55:00Z
- **Tasks:** 3/3 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Authored `docs/writeups/ieee8500_exatidao_socp.typ` verbatim per the plan's embedded content: preamble byte-identical to `stackelberg_vs_psr_n1n2.typ`/`thesis_caseA.typ`, nine sections (Resumo through Referências), all three wrong turns labelled `VOLTA ERRADA 1/2/3` (Estágio B — fabricated impedance; Estágio C — threshold misreported as a data property; Estágio E — extrapolated tolerance floor across operating points), the Estágio F per-branch diagnostic table, the Estágio H eight-segment table, and the three-pass result table.
- Registered the new writeup in `docs/writeups/README.md`'s table as the new last row, matching the `stackelberg_vs_psr_n1n2.typ` row's `—`/`—` style exactly.
- Compiled with `typst compile` (exit 0) and rendered all 5 pages to PNG for mandatory visual inspection — caught a real silent-failure bug (bare `~` swallowed as a non-breaking space in two prose spots) that a clean exit code alone would have missed, fixed it, and re-rendered to confirm.
- Spot-checked at least 8 numbers against committed sources: the pre-merge headline gap (`0.032501551229094705` in `noise_floor_calibration.csv` matches `3,250e-2`), the Pass-2 headline gap and new dominant offender's `r_pu` (`0.0018221290176472231` / `2.4010056218377727e-6` in `socp_gap_report.csv` match `1,822e-3` / `2,401e-6`), both `atol` constants (`0.0011460285861373265` / `0.004969145122458496` in `scripts/benchmark_ieee8500.jl` and `noise_floor_calibration.csv` match `1,1460e-3` / `4,9691e-3`), the pinned commit SHA (`3b208397160213cae4a9e2d0a7d1aa3528ce26e1` matches `25-DATA-PROVENANCE.md`), and the `assert_socp_exact!` throw message / combined-bound formula (verified verbatim in `src/models/exactness.jl`).

## Task Commits

Each task was committed atomically:

1. **Task 1: author the writeup** - `f4ef73e` (docs)
2. **Task 2: register in README.md** - `4e5dc45` (docs)
3. **Task 3 fix found during compile/render verification** - `63768e1` (fix)

**Plan metadata:** (this commit, handled by orchestrator)

## Files Created/Modified

- `docs/writeups/ieee8500_exatidao_socp.typ` - New Typst document: the full eight-stage IEEE-8500 SOCP-exactness investigation, house-style-matched (pt-br, New Computer Modern, `#set heading(numbering: "1.1")`, gray references footer), all figures traced to committed sources.
- `docs/writeups/README.md` - Added a table row for the new writeup, matching the existing three-row style (`—` for companion script/figures).

## Decisions Made

See `key-decisions` in frontmatter: verbatim transcription discipline (no invented/re-derived numbers), kept the plan's "Superada no Estágio H" correction as given, and fixed a real Typst tilde-escaping rendering bug found during the mandatory PNG-inspection step.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Escaped literal tildes silently swallowed by Typst markup**
- **Found during:** Task 3 (mandatory PNG-page visual inspection after `typst compile` exit 0)
- **Issue:** The plan's embedded content used bare `~` in two prose sentences ("inventaria ~2.000x sua resistência" and "ponto-título de ~40x em `T = 24`"). In Typst, a bare `~` outside raw/code spans is markup for a non-breaking space, not a literal tilde character — it compiled cleanly (exit 0) but silently dropped the tilde in the rendered PDF, leaving only a double space and losing the "approximately" meaning. This is exactly the class of silent failure the plan's gotcha warnings called out for the `auto`-column bug — a clean exit is not evidence of correct rendering.
- **Fix:** Escaped both occurrences as `\~` so Typst renders a literal tilde. Left `r_pu ~ 3,2e-6` (inside backticks, a raw/code span) untouched since raw content doesn't interpret markup and it was already rendering correctly.
- **Files modified:** `docs/writeups/ieee8500_exatidao_socp.typ`
- **Verification:** Recompiled (exit 0), re-rendered pages 3 and 5 to PNG, visually confirmed both `~2.000x` and `~40x` now render with a literal tilde.
- **Committed in:** `63768e1`

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Necessary for correctness of the rendered document — no scope creep. Caught only because the plan's mandatory PNG-inspection step was followed rather than trusting the compile exit code alone.

## Issues Encountered

None beyond the deviation above.

## Known Stubs

None.

## Threat Flags

None — this task adds no new network endpoint, auth path, file-access pattern, or schema change. It is a documentation-only writeup; no source files under `src/` or `scripts/` were modified.

## Next Phase Readiness

- The new writeup is discoverable from `docs/writeups/README.md`.
- The IEEE-8500 SOCP-exactness investigation (deferred-items.md Items 1/3/5) now has a single reader-facing, thesis-appendix-ready document consolidating what was previously scattered across `deferred-items.md`, `25-DATA-PROVENANCE.md`, three quick-task summaries, and two CSVs.
- Open items already flagged in `deferred-items.md` (the true ~40x T=24 headline point never measured, the 53 untouched 1m stubs, the SCS-on-global-Julia reproducibility gap, the tautological-ratio certificate-hygiene gap) are carried forward honestly in the report's "Itens em aberto" section, not resolved here.
- No blockers for subsequent work; this is a terminal documentation deliverable.

## Self-Check: PASSED

- FOUND: docs/writeups/ieee8500_exatidao_socp.typ
- FOUND: docs/writeups/ieee8500_exatidao_socp.pdf (compiled artifact, correctly untracked/gitignored)
- FOUND: f4ef73e (in git log)
- FOUND: 4e5dc45 (in git log)
- FOUND: 63768e1 (in git log)
- Confirmed via grep: 3 occurrences of "VOLTA ERRADA"; 4 word-boundary occurrences of `atol`; 0 `auto` on any `columns:` line; all 5 rendered PNG pages visually inspected with no scrambled/overlapping table text; `git status --porcelain docs/writeups/` shows no output (fully committed, `.pdf` correctly absent).
