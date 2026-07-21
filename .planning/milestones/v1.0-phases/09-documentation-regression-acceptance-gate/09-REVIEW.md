---
phase: 09-documentation-regression-acceptance-gate
reviewed: 2026-07-20T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - test/test_acceptance.jl
  - test/test_pricing_fit.jl
  - docs/make.jl
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: resolved
resolution:
  fixed: [CR-01, CR-02, WR-01, WR-02, WR-03, "iter2-comment-scope"]
  deferred: [WR-04, WR-05]
  note: "Both blockers fixed. iter2 comment-scope warning fixed (docstrings exist but aren't wired into @docs/@autodocs — not 104 undocumented symbols). WR-04 (JuliaFormatter on docs/) deferred: mechanical reformat detaches inline equation-comments from device args, harming the CLAUDE.md 'equations beside code' requirement — needs a deliberate hand pass. WR-05 (deploydocs placeholder) is a settled user decision (keep placeholder + TODO). Info items are traceability notes only. Suite: 1946 pass / 0 fail / 2 broken; docs build exits 0."
---

# Phase 9: Code Review Report

**Reviewed:** 2026-07-20T00:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

This is iteration 2 of the fix→re-review loop. Scope is the three files touched by the fixer:
`test/test_acceptance.jl`, `test/test_pricing_fit.jl`, `docs/make.jl`. I did not re-review
`docs/literate/*.jl` or `.github/workflows/CI.yml` (out of this iteration's file scope; WR-04/
WR-05 from iteration 1 concern those files and were explicitly deferred, not re-checked here).

I did not take the fixer's claims on faith. I instantiated the project (`Project.toml` +
`test/Project.toml`), **actually ran** the two test files end-to-end via
`TestItemRunner.@run_package_tests` with a name filter (82/82 tests pass, including both
acceptance items and all six FIT items), independently recomputed `v₉[16]` for the IEEE-13
acceptance item standalone and confirmed it matches the pinned `GOLDEN_V9_16` to ~1e-11, and
**actually ran** `julia --project=docs docs/make.jl` to completion and inspected its warning
output line-by-line against `src/` docstrings.

**Verified as correctly fixed:**
- **CR-02** — `test/test_acceptance.jl:66` now asserts `@test admm.exact_maxgap < 1e-3` on the
  IEEE-13 item, with the identical tolerance and field as the IEEE-123 sibling
  (`test_acceptance.jl:122`, `test_ieee123_admm.jl:73`). Confirmed non-vacuous: the assertion
  ran and passed against a real computed `admm.exact_maxgap` in the actual test run (not a
  literal `true` or an unreachable branch).
- **WR-03** — `test/test_acceptance.jl:80` restores `@test isapprox(v9_16, GOLDEN_V9_16; atol =
  1e-4)` as a genuine hard (non-`broken`) assertion. `GOLDEN_V9_16 = 1.0436080536` (line 36)
  matches `test_ieee13.jl:185`'s `const GOLDEN_V9_16 = 1.0436080536` exactly (same computed
  digits). I independently recomputed `v9_16` for this exact scenario standalone and got
  `1.0436080535989598` — matches to ~1e-11, well inside the `atol = 1e-4` gate. Not
  tautological: this is a distinct assertion from the immediately-following non-failing
  `@test gap < 1e-2 broken = (gap >= 1e-2)` thesis cross-check, and it can genuinely fail if a
  future regression moves the computed voltage.
- **WR-01** — the added notes (`test_acceptance.jl:68-73`, `:123-124`) correctly describe
  Julia's `AbstractArray` `isapprox` as norm-based
  (`norm(x-y) <= max(atol, rtol*max(norm(x),norm(y)))`), not elementwise — this matches Base
  Julia's actual implementation.
- **WR-02** — the corrected comments (`test_acceptance.jl:12-15`, `test_pricing_fit.jl:6-9`)
  accurately state that `test/runtests.jl`'s `@run_package_tests` passes no `filter` keyword, so
  tags are metadata only. Confirmed against the actual `test/runtests.jl` (`@run_package_tests`
  with zero arguments).

**Not (fully) verified as fixed — see WR-01 below:** the `docs/make.jl` `checkdocs` comment
(originally CR-01) was corrected for behavior (it no longer claims the build "fails" — it now
correctly says `warnonly` makes the check non-fatal, which I confirmed by running the doc build:
exit code 0, with the "104 docstrings..." warning routed through the `:missing_docs` category
that is indeed in `warnonly`). However, the corrected comment introduces a new factual
inaccuracy in its characterization of *what* those 104 items are: it calls them "undocumented
exported symbols," but Documenter's own warning text — and my direct inspection of a sample of
the 104 listed bindings in `src/` — shows most of them **do** have docstrings; the actual gap is
that those docstrings aren't spliced into the rendered manual via `@docs`/`@autodocs` blocks.
This is a materially different, smaller remediation task than "write 104 docstrings." See WR-01.

No reproducibility hazards were introduced by any of the applied fixes: all pinned goldens
reproduce bit-for-bit/to-tolerance, and no new nondeterminism (unseeded RNG, wall-clock, etc.)
was added.

## Warnings

### WR-01: `docs/make.jl`'s corrected `checkdocs` comment still mischaracterizes the 104-item backlog as "undocumented exported symbols" — it is actually "documented but not linked into the manual"

**File:** `docs/make.jl:49-58`
**Issue:** The comment (as fixed this iteration) reads:

```julia
# Tightened from :none (Phase 1) to :exports (Phase 9 EXP-03): check undocumented
# PUBLIC-API (exported) symbols and broken `@ref`s, ...
# ... it SURFACES undocumented exports and unresolved `@ref`s as build warnings ...
# ... There is a real, tracked backlog of ~104 undocumented exported symbols today
# (see 09-REVIEW.md CR-01); documenting them all and dropping `:missing_docs`/
# `:cross_references` from `warnonly` ... is deferred, not done here.
checkdocs = :exports,
warnonly = [:missing_docs, :cross_references],
```

I ran `julia --project=docs docs/make.jl` to completion. The actual warning text (verbatim, via
`~/.julia/packages/Documenter/.../src/docchecks.jl:missingdocs`) is:

```
Warning: 104 docstrings not included in the manual:
    TSODSO.Bus
    TSODSO.Feeder
    TSODSO.AbstractPowerFlow
    TSODSO.MILP
    ... (104 total)
These are docstrings in the checked modules (configured with the modules keyword)
that are not included in canonical @docs or @autodocs blocks.
```

This is `Documenter.missingdocs`, which checks whether docstrings that **exist** in the checked
modules are reachable from an `@docs`/`@autodocs` block somewhere in the rendered manual — it is
not a "does this symbol have a docstring at all" check. I spot-checked several of the 104 listed
bindings directly in `src/` and confirmed they have docstrings today: `Bus` (`src/data/Feeder.jl:18-23`,
`"""Bus{T<:Real} ... """`), `Branch`, `Feeder`, `AbstractPowerFlow`
(`src/powerflow/AbstractPowerFlow.jl:16-21`), `MILP` (`src/solver/ProblemClass.jl:26-27`,
`"Mixed-integer linear program. Default backend: HiGHS."`), `GurobiChoice`, `MosekChoice`,
`plot_convergence` — all have docstrings. So the comment's framing ("undocumented exported
symbols"; "documenting them all ... is deferred") is factually wrong for the great majority of
the 104: the actual deferred work is adding `@docs`/`@autodocs` blocks to `docs/src/*.md` (or a
new API-reference page) so the existing docstrings get spliced into the built manual — a
narrower, cheaper task than writing ~104 new docstrings from scratch. A future contributor
reading this comment and picking up the "deferred" work would likely start writing docstrings
that already exist, rather than wiring up the missing `@docs`/`@autodocs` blocks that are the
real gap.

**Fix:** Reword to match what Documenter is actually reporting, e.g.:

```julia
# ... `checkdocs = :exports` also runs Documenter's missingdocs check: docstrings that EXIST in
# the checked modules but are not reachable from any @docs/@autodocs block in the rendered
# manual are reported (routed through :missing_docs, hence non-fatal via warnonly below).
# ~104 such docstrings exist today (most exported types/functions already have a docstring in
# src/; they are simply not yet spliced into any docs/src/*.md page via @docs/@autodocs).
# Wiring up an API-reference page (or per-model @docs blocks) to close this gap, and then
# dropping :missing_docs/:cross_references from warnonly, is deferred, not done here.
```

## Info

### IN-01: Live verification results (for the record, not a defect)

Recorded for traceability of this iteration's re-review:
- `julia --project=test -e 'using TestItemRunner; @run_package_tests filter = ti ->
  occursin("test_acceptance.jl", ti.filename) || occursin("test_pricing_fit.jl", ti.filename)'`
  → **82/82 pass**, ~1m22s, no failures/errors/broken (the `broken = (gap >= 1e-2)` thesis
  cross-check item reported Pass, gap ≈ 0.00569).
- Standalone recomputation of the IEEE-13 acceptance scenario's `v₉[16]` reproduces
  `1.0436080535989598`, matching `GOLDEN_V9_16 = 1.0436080536` to ~1e-11.
- `julia --project=docs docs/make.jl` completes with exit code 0; the only `:missing_docs`
  warning is the "104 docstrings not included in the manual" one addressed in WR-01, plus ~15
  `Cannot resolve @ref` warnings for the same underlying reason (docstring exists but isn't
  spliced into the page it's referenced from) — both categories are in `warnonly` and do not
  fail the build, consistent with the (corrected) comment's behavioral claim.

### IN-02: Fixer comments hard-reference specific finding IDs in this mutable review document (`09-REVIEW.md CR-01`, `09-REVIEW WR-01/02/03`)

**File:** `docs/make.jl:56`, `test/test_acceptance.jl:12,68,75`, `test/test_pricing_fit.jl:6`
**Issue:** Several source comments cite specific finding IDs from this review
(e.g. `# NOTE (09-REVIEW WR-01): ...`, `(see 09-REVIEW.md CR-01)`). This iteration overwrote the
review with fresh IDs (this file no longer has a `CR-01` or a `WR-01` about the same topics as
iteration 1 — e.g. iteration 1's `CR-01` is now referenced from `make.jl` but this iteration's
`CR-01` slot is unused and the docstring-backlog topic is now `WR-01` here). If review IDs are
renumbered or the finding is later marked resolved and removed, these source comments become
stale/orphaned cross-references pointing at content that no longer exists at that ID. This is
low-severity (informational/traceability comments only, no behavior depends on them) but worth
noting: prefer citing a stable artifact (a `CONTEXT.md` decision, a GitHub issue, or a plan ID)
rather than a specific finding ID in a document that gets overwritten every review iteration.
**Fix:** Not required to act on now; consider migrating these cross-references to a stable
tracking mechanism (issue/TODO tag) if the docstring-backlog work is picked up later.

---

_Reviewed: 2026-07-20T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
