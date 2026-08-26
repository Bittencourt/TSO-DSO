---
quick_id: 260826-8gb
subsystem: docs
tags: [documenter, literate, admm, socp, clarabel, numerical-conditioning, ci-integrity]

# Dependency graph
requires:
  - phase: .planning/debug/resolved/ieee13-admm-numerical-error.md
    provides: every measured number/fact reproduced verbatim (root cause, mechanism,
      two-commit fix f9d6ed7/d099821, canary regression posture)
provides:
  - docs/literate/admm.jl — new "Numerical robustness — the ADMM conditioning ladder
    (mid-loop knife-edge)" section (prose only, no new executable cell) on the Rung 5
    literate page, rendered to docs/src/generated/admm.md by the docs build
  - docs/src/index.md — two new paragraphs at the end of "## Validation & regression
    posture" summarizing the ADMM numerical-robustness net and the CI content-loss guard
affects: [future-touches-of-docs/literate/admm.jl, future-touches-of-docs/src/index.md,
  future-JuliaFormatter-version-bumps-on-this-repo]

tech-stack:
  added: []
  patterns:
    - "Literate.jl prose-only `##` sections for findings that must not add docs-build
      execution cost: document a general, fixture-measured property (IEEE-13) alongside
      a live toy example (3-bus/T=4) without re-running the expensive fixture in the
      docs build itself"
    - "state epistemic status in the reader's voice, not the author's: 'strongly
      supported by the measurements above rather than solver-internally certified',
      never 'so state the caveat honestly' (planning-note language leaking into
      published prose)"

key-files:
  created: []
  modified:
    - docs/literate/admm.jl
    - docs/src/index.md

key-decisions:
  - "Kept the new admm.jl section PROSE ONLY per the plan's explicit constraint — no new
    solve_admm/solve_welfare call was added, since the toy 3-bus/T=4 fixture already
    solved live on the page is too small to hit the knife-edge and a full IEEE-13
    58-iteration re-solve would be a real, unjustified recurring docs-build cost."
  - "Mid-execution correction (flagged by coordinator review): the original C2 caveat
    sentence ended with 'so state the caveat honestly rather than implying a certified
    proof' — an instruction addressed to the executor, not the reader. Rewrote it to
    state the epistemic status directly to a researcher reading the rendered page
    ('...so treat this mechanism as strongly supported by the measurements above rather
    than as solver-internally certified'), keeping every fact (KKT condition number
    never dumped, would need product-code instrumentation) unchanged — only the voice
    changed. Re-scanned the rest of the added prose for the same class of leak (second-
    person/process language, bare unexplained commit hashes) and found none."
  - "Because the coordinator's already-running background docs build had started before
    the voice fix, its docs/src/generated/admm.md was stale relative to the corrected
    source. Left that build running to completion as instructed (its exit-0 result and
    zero @ref-resolution warnings for the new refs remain valid evidence the structure
    is sound), then ran one additional full `julia --project=docs docs/make.jl` after
    the fix to obtain a build whose generated admm.md actually contains the corrected
    prose, and used that run as the authoritative Task C verification."

requirements-completed: []

duration: ~55min
completed: 2026-08-26
---

# Quick Task 260826-8gb: Document the ADMM conditioning ladder and the docs-integrity guard Summary

**Documented the IEEE-13 ADMM mid-loop `NUMERICAL_ERROR` knife-edge (anisotropic-Hessian mechanism, two-commit fix, canary regression posture) on the Rung 5 Documenter literate page, and summarized both that numerical-robustness net and the CI content-loss guard on the site Home page — verified end-to-end against a strict `julia --project=docs docs/make.jl` build that resolves every new `@ref` and regenerates `docs/src/generated/admm.md` untracked.**

## Performance

- **Duration:** ~55 min (including two full Documenter builds, each running the
  stochastic/meshed/planning-Benders experiment pages)
- **Completed:** 2026-08-26
- **Tasks:** 3 of 3 completed as planned (Task A: literate page section; Task B: Home
  page paragraphs; Task C: build/format/content-loss verification)
- **Files modified:** 2 (`docs/literate/admm.jl`, `docs/src/index.md`)

## Accomplishments

- **Task A** — Appended a "## Numerical robustness — the ADMM conditioning ladder
  (mid-loop knife-edge)" section to the end of `docs/literate/admm.jl`, after the
  existing convergence-figure section. Covers, with every measured number verbatim from
  the resolved debug doc: the iteration-28 knife-edge (`ρ₀ = 100` → `ρ = 200` at
  `τ = 2`, nowhere near `ρ_max = 1e4`), the anisotropic-objective-Hessian mechanism (240
  of 1536 variables carry the `0.5ρ` diagonal curvature; the rest rely on Clarabel's
  `1.0e-8` static regularization; rung 2's `1e-6` is a 100x cut of exactly that spread),
  the honest solver-certification caveat, the two-commit fix (`f9d6ed7` routes the
  mid-loop solve through `solve_with_retry!`; `d099821` snapshots/restores the as-built
  ladder baseline before every published solve), why the published DADP (`dadp == λ`,
  the outer multiplier) can never be contaminated, and the canary test's regression
  posture (`test/test_admm_knifeedge_canary.jl` hard-asserts `iters == 58` and welfare,
  only reports the ladder-firing count). PROSE ONLY — zero new executable Julia cells.
- **Task B** — Appended two paragraphs to the end of `docs/src/index.md`'s
  "## Validation & regression posture" section: one on the ADMM numerical-robustness net
  (linking to `generated/admm.md`, naming `solve_with_retry!`/`build_dso_opt` and the
  canary test), one on the CI content-loss guard (`.github/scripts/check_content_loss.py`,
  the `|`-continuation JuliaFormatter hazard it exists to catch, its stated boundary —
  catches formatting-introduced loss only, not loss already committed to a clean `HEAD`
  — and the `PackageSpec(name = "JuliaFormatter", version = "2.10")` pin resolving to
  `[2.10.0, 2.11.0)`).
- **Mid-execution fix** (coordinator review) — the C2 caveat sentence in Task A's new
  section originally ended with instruction-to-self language ("so state the caveat
  honestly rather than implying a certified proof"). Rewrote it to address the reader
  directly and state the epistemic status in-voice; re-scanned all new prose in both
  files for the same class of leak (grep for "this task"/"the plan"/"this
  session"/"verified this"/bare unexplained commit hashes) and found nothing else to
  fix. `docs/src/index.md` needed no change (confirmed correct as written).
- **Task C** — Verified formatter cleanliness
  (`format("docs/literate/admm.jl"; overwrite=false)` → `true`, both before and after
  the voice fix — the file needed zero reformatting at any point, so there was never
  formatting-induced content-loss risk), ran the content-loss guard informationally
  (`check_content_loss.py HEAD` flags `docs/literate/admm.jl` as `+4095` chars changed
  vs `HEAD` — expected, since this task deliberately adds new content; the load-bearing
  check is the formatter before/after diff, which showed zero drift), and ran the full
  strict Documenter build twice: once via the coordinator's already-running background
  process (exit 0, zero `@ref`-resolution warnings for the four refs this task adds),
  and once more after the voice fix to obtain a build whose `docs/src/generated/admm.md`
  actually contains the corrected prose (exit 0, same zero-new-warnings result,
  confirmed via grep that the fixed sentence — not the original — is present in the
  rendered output). `docs/src/generated/admm.md` regenerated and stayed untracked
  (`git status --porcelain docs/src/generated/` empty both times, matching
  `.gitignore:15`).

## Task Commits

1. **Task A + Task B (single commit, plan-scoped to two files):** `362e745` (docs) —
   `docs(admm): document the ADMM conditioning ladder and docs-integrity guard`
2. **Task C:** verification only, no commit (build/format/content-loss checks against
   the committed state)

_Note: the plan scoped both content tasks to two files with one combined `done`
criterion per file; both were completed and verified together before a single commit
covering exactly `docs/literate/admm.jl` and `docs/src/index.md`, staged by explicit
path only. Pre-existing uncommitted drift (`Manifest-v1.12.toml`, `Project.toml`,
`.planning/tmp/`) was left untouched throughout._

## Files Created/Modified

- `docs/literate/admm.jl` — new prose-only "Numerical robustness" section (72 added
  lines) documenting the IEEE-13 ADMM knife-edge, its mechanism, fix, and regression
  posture.
- `docs/src/index.md` — two new paragraphs (27 added lines) at the end of "Validation &
  regression posture" summarizing the ADMM robustness net and the CI docs-integrity
  guard.

## Decisions Made

See `key-decisions` in frontmatter. Most consequential: correcting the leaked
instruction-to-self voice in the C2 caveat sentence without altering any of its
substance (mechanism strongly supported, KKT condition number never dumped, claim
therefore uncertified), and re-running the full docs build a second time after that fix
so the verified `docs/src/generated/admm.md` output actually reflects the committed
source rather than a build that started before the correction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Instruction-to-self language leaked into published Literate prose**
- **Found during:** Task C verification, flagged by coordinator review of the rendered
  Rung 5 page before commit.
- **Issue:** The C2 caveat sentence in `docs/literate/admm.jl` ended "...so state the
  caveat honestly rather than implying a certified proof" — phrasing addressed to the
  document's author, not to a researcher reading the rendered page.
- **Fix:** Rewrote the clause to address the reader directly: "...so treat this
  mechanism as strongly supported by the measurements above rather than as
  solver-internally certified." Substance unchanged (mechanism measured/consistent, KKT
  condition number never dumped, claim uncertified) — only the voice changed.
  Re-scanned all newly added prose in both files for the same defect class (second-person
  or process language, unexplained bare commit-hash references) via targeted grep; none
  found. `docs/src/index.md` required no change.
- **Files modified:** `docs/literate/admm.jl` (single-clause edit within the section
  added by this task, before its first commit).
- **Verification:** re-ran the Task A automated checks (grep counts, section-header
  count, wrapped-`|` guard) — all still pass; re-ran the formatter check
  (`overwrite=false` → `true`); re-ran the full docs build and confirmed via grep that
  `docs/src/generated/admm.md` contains the corrected sentence, not the original.
- **Committed in:** `362e745` (the fix was applied before the first and only commit of
  these two files — no separate commit needed).

---

**Total deviations:** 1 auto-fixed (Rule 1, prose-voice correction caught by review
before commit — no functional or factual change).
**Impact on plan:** None on scope or facts. The correction only changed how one
sentence addresses its reader; every measured number and the fix/mechanism/regression
narrative required by the plan's `must_haves` remained exactly as specified.

## Issues Encountered

The docs build is genuinely long-running (the `ExpandTemplates` step executes every
Literate page's code, including the heavier IEEE-123, meshed-reactive, stochastic-PV,
and planning-Benders/diagonalization experiment pages) — both full builds in this
session ran well past the foreground 10-minute Bash timeout and had to be tracked as
detached background processes, waited out with `tail --pid=<pid> -f /dev/null` rather
than polling. No functional issue; documented here only because it materially affected
how long Task C's verification took (~55 min of this task's total duration was two full
docs builds, not editing).

## Known Stubs

None — this task adds documentation prose only; no UI, data-rendering, or executable
surface was touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes.
This task only adds prose to a Documenter site describing already-shipped,
already-reviewed production code (`solve_with_retry!`, `build_dso_opt`, `solve_dso!`)
and an already-shipped CI script (`check_content_loss.py`); no new attack surface.

## Self-Check: PASSED

- `docs/literate/admm.jl` contains the new "## Numerical robustness" section (verified:
  `grep -n "^# ## Numerical robustness" docs/literate/admm.jl` → exactly 1 match at line
  133) with the corrected reader-voice caveat (verified: `grep -n "treat this mechanism
  as strongly supported" docs/literate/admm.jl` → present; `grep -n "so state the
  caveat" docs/literate/admm.jl` → absent).
- `docs/src/index.md` contains both new paragraphs at the end of "## Validation &
  regression posture" (verified: `grep -c "check_content_loss.py\|solve_with_retry!\|
  knifeedge_canary" docs/src/index.md` → 3; `tail -5 docs/src/index.md` ends with the
  `VersionRange`/`[2.10.0, 2.11.0)` sentence).
- No wrapped line begins with `|` in the new prose (verified:
  `python3 -c "import re; ... re.search(r'\n#\s*\|', t)"` → `OK`).
- Commit `362e745` exists and touches exactly the two intended files (verified:
  `git show --stat HEAD` and `git diff --diff-filter=D --name-only HEAD~1 HEAD` →
  empty, no accidental deletions).
- `format("docs/literate/admm.jl"; overwrite=false)` under pinned JuliaFormatter 2.10 →
  `true` (formatter-clean), checked both before and after the voice-fix edit.
- `python3 .github/scripts/check_content_loss.py HEAD` → exit 1, flagging
  `docs/literate/admm.jl` as `+4095` chars changed — expected per the plan (deliberate
  new content vs. `HEAD`); the load-bearing formatter before/after diff showed zero
  content drift at any point.
- `julia --project=docs docs/make.jl` → exit 0 on both the coordinator's pre-fix build
  and this task's post-fix rerun; zero `@ref`-resolution warnings for `build_dso_opt`,
  `solve_dso!`, `solve_with_retry!`, or `solve_admm` (the only `CrossReferences`
  warning, `stall_z_atol` in `docs/src/api.md`, is pre-existing and out of this task's
  scope).
- `docs/src/generated/admm.md` regenerated after the post-fix build and remains
  untracked (verified: `git status --porcelain docs/src/generated/` → empty output,
  matching `.gitignore:15`).

## Next Phase Readiness

- No blockers. The two pages a researcher would actually land on — the Rung 5 ADMM
  literate page and the site Home page's regression-posture section — now both
  document this session's numerical finding and its CI-integrity guard, closing the
  documentation gap CLAUDE.md's "rich, step-by-step docs" requirement flagged.
- `docs/src/api.md`, `docs/make.jl`, and `README.md` were correctly left untouched, per
  the plan's verified-out-of-scope audit.

---
*Quick task: 260826-8gb*
*Completed: 2026-08-26*
