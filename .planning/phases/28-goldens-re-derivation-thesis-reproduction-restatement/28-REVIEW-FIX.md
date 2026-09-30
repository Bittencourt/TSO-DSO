---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
fixed_at: 2026-09-30T10:15:46Z
review_path: .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 28: Code Review Fix Report

**Fixed at:** 2026-09-30T10:15:46Z
**Source review:** .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (CR-01, WR-01, WR-02; fix_scope=critical_warning, IN-01 excluded)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-01: Stale aggregate-welfare-gap figure (and stale surplus numbers) left uncorrected in the "HONESTY-MANDATE PARAGRAPH"

**Files modified:** `docs/literate/thesis_reproduction_assumptions.jl`, `scripts/thesis_case123_repro.jl`, `docs/writeups/FRAMEWORK_GUIDE.html`, `.planning/PROJECT.md`, `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md`
**Commit:** `fbc1e35`
**Applied fix:** Recomputed the aggregate welfare-gap percentage against the current model by
actually running the live code (a throwaway script reproducing the exact `solve_welfare`/
`fit_baseline` call sites and `tol_gap` overrides from `scripts/thesis_case123_repro.jl`), never
by re-deriving from the reviewer's own arithmetic. Confirmed: `acct.dso=3.7393744862531797`,
`acct.prosumer=-41039.14373797347`, `fit_dso=-286.10769581257046`,
`fit_prosumer=-40857.49706991592`, giving `welfare_delta_pct=0.2629823100184308` — i.e. the
current aggregate welfare gap is **≈+0.2630%**, matching the reviewer's derivation almost
exactly. Fixed every occurrence found by a repo-wide grep for the stale `+0.045%` figure and the
stale `fit_dso≈-196.22`/`acct.dso≈+3.7257`/`acct.prosumer≈-41039.129` surplus figures:
- `docs/literate/thesis_reproduction_assumptions.jl` Section 6 — added a `!!! warning
  "CORRECTED ..."` box directly after the stale paragraph (mirroring the page's own established
  convention used in Sections 4/5/7/8), showing old→new for all four figures plus the derived
  percentage, with cause (FIX-01/FIX-02, FIX-09/FIX-10) and a forward pointer to the existing
  "Restated in v4.0" table.
- `scripts/thesis_case123_repro.jl` header (both the top "WHAT THIS DOES NOT CLAIM" paragraph and
  the "RESTATED IN v4.0" comment block) — updated the stale `≈+0.045%` text with the current value
  and an old→new note.
- `docs/writeups/FRAMEWORK_GUIDE.html` — a third, previously-unflagged occurrence of the stale
  `+0.045%` figure (found by grep, not in the reviewer's cited locations) plus its adjacent
  now-also-stale "knife-edge fragile" population-sweep characterization (contradicted by this
  same phase's own `sign_flip_survives: true` 5/5 finding) — both corrected.
- `.planning/PROJECT.md` (lines ~90-93 and ~415) — two more previously-unflagged occurrences
  (contrary to Plan 28-01's "zero hits" prose-citation audit, likely added to PROJECT.md after
  that audit ran) — corrected with an explicit `[RESTATED Phase 28 ...]` bracket, also retiring
  the stale "knife-edge-fragile" claim there.
- `28-RESTATEMENT-SUMMARY.md` — added the missing "Aggregate welfare gap" row to the phase's own
  old→new table, closing the exact gap CR-01 identified (this derived number was never restated
  anywhere despite the underlying `fit_dso` moving materially).
- Confirmed via grep that `docs/literate/thesis_reproduction_ieee123.jl` and
  `28-FINDINGS.md`/`README.md` already cite only current values or are out of the finding's
  named scope (historical phase narrative, not touched).

Verification: re-ran `docs/literate/thesis_reproduction_assumptions.jl` directly
(`julia --project=.`) after the edit — exits 0, live-checked assertions pass, no syntax errors.
Parsed `scripts/thesis_case123_repro.jl` with `Meta.parseall` — parses cleanly.

### WR-01: Regenerated `findings.txt` "RECOMMENDED BAND" no longer matches the golden it claims to be the verbatim source of

**Files modified:** `test/test_thesis_repro.jl`
**Commit:** `92e8f3b`
**Applied fix:** Re-pinned `DSO_BAND_HI` from `7.211125525764296` to `7.229422341375` (verified
against the committed `results/repro_stability_check/findings.txt`'s current "RECOMMENDED BAND:"
line — `1.5 × max|dso| = 1.5 × 4.819615 = 7.229422341375`, computed from the regenerated 5-point
sweep's `δ=+0.050` row). Added an old→new + cause comment matching the file's own established
`260823-gea` provenance-comment convention, both in the header block and inline at the constant
definition, restoring the "copied verbatim from the committed findings.txt" claim to true. The
pinned point (`acct.dso≈3.739`) sits inside both the old and new band, so the fix does not change
the test's pass/fail verdict.

Verification: wrote a direct `julia --project=.` script (not TestItemRunner, per this repo's own
known trap) reproducing the exact REPRO-01 `@testitem` body — same population builder, same
`tol_gap` overrides, same 5 assertions. All 5 assertions pass with the new band:
`socp_maxgap=9.466e-8 < 1e-5`, `acct.dso=3.739374 > 0`, `fit_dso=-286.108 < 0`,
`acct.prosumer=-41039.144 < fit_prosumer=-40857.497`, `0.0 < acct.dso=3.739374 <
DSO_BAND_HI=7.229422341375`. `Meta.parseall` confirms the file parses cleanly.

### WR-02: `audit_goldens.py`'s attribution-reference regex accepts a bare `D-` anywhere in the window

**Files modified:** `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py`
**Commit:** `efaf58e`
**Applied fix:** Tightened `ATTRIBUTION_REF_RE` from bare `Plan[- ]|FIX-|PM-|WR-|D-` substring
matching to require a decision-ID shape: `\bPlan[- ]\d+\b|\bFIX-\d+\b|\bPM-\d+\b|\bWR-\d+\b|
\bD-\d+\b|\b\d{2}-\d{2}\b` (the last alternative added per this fix's own scope to also accept a
bare plan id like `26-18`). Updated the module docstring's design section to document the
tightened behavior and the concrete false-positive risk it closes (a capital letter immediately
followed by a hyphen — e.g. "GRID-connected", "HYBRID-floor", "VALID-only" — with no real
`D-<number>` decision-ID nearby). Added a new selftest regression fixture
(`FIXTURE_FALSE_POSITIVE_BAIT_BODY`, a `"HYBRID-floor"`-containing comment with no real
decision-ID) that would have been wrongly marked `attributed=True` pre-fix and is correctly
`attributed=False` post-fix.

Verification: `python3 -W error audit_goldens.py --selftest` → `SELFTEST: PASS` (3/3 fixtures
correct, no syntax warnings). Live run `python3 audit_goldens.py --base 5939799 --head HEAD` →
exit 0, `13 attributed / 1 allowlisted / 0 unattributed` (one more attributed row than the
review's cited 12/1/0 split, because this same fixer session's WR-01 commit added a new,
properly-attributed golden move — `test/test_thesis_repro.jl:68->82`, attributed via its own
`WR-\d+` comment reference — confirming the tightened regex correctly recognizes real
attributions, not just correctly rejecting the bait fixture).

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-09-30T10:15:46Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
