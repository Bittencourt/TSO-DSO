---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
reviewed: 2026-09-30T10:03:56Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - docs/literate/ac_oracle.jl
  - docs/literate/mpc_rolling_horizon.jl
  - docs/literate/prosumer_welfare.jl
  - docs/literate/restricted_branch_flow.jl
  - docs/literate/socp_applicability.jl
  - docs/literate/thesis_reproduction_assumptions.jl
  - docs/literate/thesis_reproduction_ieee123.jl
  - docs/make.jl
  - results/repro_stability_check/findings.txt
  - results/socp_applicability/highpv_3bus_findings.txt
  - results/socp_applicability/highpv_3bus_sweep.csv
  - results/socp_applicability/ieee123_findings.txt
  - results/socp_applicability/ieee123_sweep.csv
  - scripts/demo_mpc_plots.jl
  - scripts/socp_applicability_sweep.jl
  - scripts/thesis_case123_repro.jl
  - scripts/thesis_caseA.jl
  - test/test_ac_oracle.jl
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: issues_found
---

# Phase 28: Code Review Report

**Reviewed:** 2026-09-30T10:03:56Z
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

Reviewed the diff vs `9ff2127` for Phase 28 (goldens re-derivation / thesis-reproduction
restatement, FIX-11). Scope is entirely docs/scripts/tests/results — no `src/` files changed,
consistent with a restatement-only phase.

To verify claims rather than trust them, I independently re-ran the EXACT-04 high-PV 3-bus
fixture (`ac_oracle.jl` / `restricted_branch_flow.jl` / `test_ac_oracle.jl`'s shared fixture)
and the full IEEE-123 REPRO-01 reproduction (`thesis_reproduction_ieee123.jl` /
`thesis_case123_repro.jl` / `test_thesis_repro.jl`'s shared population) directly against current
`HEAD` with `julia --project=.`, outside the test suite. Every gate-1/gate-2 number, cost value,
and DSO/prosumer surplus figure quoted in the restated literate pages and test comments
reproduced to the cited precision:

- `cost_socp`(default)=-921.7543, `cost_socp`(thesis_literal)=-921.27700, `cost_ac`=-921.27699,
  `socp_maxgap`(default)=2.587e-8, `socp_maxgap`(thesis_literal)=9.053e-9,
  `inexact_hours`(default)=6:15, `inexact_hours`(thesis_literal)=[] — all match.
- `acct.dso`=3.739374, `acct.prosumer`=-41039.144, `fit_dso`=-286.107696,
  `fit_prosumer`=-40857.497, `socp_maxgap`=9.47e-8 — all match the restated headline table in
  `thesis_reproduction_ieee123.jl` and `28-RESTATEMENT-SUMMARY.md`.
- `scripts/audit_goldens.py --selftest` and a live `--base 5939799 --head HEAD` run reproduce
  exactly the documented 12-attributed/1-allowlisted/0-unattributed, exit 0.
- `results/socp_applicability/*_findings.txt` classification counts (98/3/19/30 default,
  104/5/11/30 thesis_literal on the 3-bus grid; 18/27/9 and 19/26/9 on IEEE-123) match every
  number cited in `socp_applicability.jl`'s prose and `28-FINDINGS.md`.

This is a well-executed restatement in the aggregate — the gate-1/gate-2 disambiguation is
correct and independently verified, the dual-mode sweep data is internally consistent, and the
audit script's mechanics check out. However, spot-checking the ONE quantity the restatement did
NOT recompute (the aggregate DADP-vs-FIT welfare-gap percentage) surfaced a genuine, material,
unflagged inaccuracy — see CR-01 below — plus a golden-provenance drift the phase's own audit
discipline should have caught (WR-01) and a latent robustness gap in the audit script itself
(WR-02).

## Critical Issues

### CR-01: Stale aggregate-welfare-gap figure (and stale surplus numbers) left uncorrected in the "HONESTY-MANDATE PARAGRAPH", contradicted by the same page's own restatement table

**File:** `docs/literate/thesis_reproduction_assumptions.jl:101-117` (Section 6), also
`scripts/thesis_case123_repro.jl:9-19` (header)

**Issue:** Section 6 of `thesis_reproduction_assumptions.jl` — the page's own
"HONESTY-MANDATE PARAGRAPH", written to be the plain, trustworthy statement of what does and
does not reproduce — states:

> the aggregate welfare gap between DADP and FIT is only **≈+0.045% (directional, public-data)**
> ... the FIT baseline's DSO surplus is negative (**fit_dso ≈ -196.216447** ...), the DADP
> optimum's DSO surplus is positive (**acct.dso ≈ +3.725705** ...), and the prosumer surplus
> decreases under DADP (**acct.prosumer ≈ -41039.129** < fit_prosumer ≈ -40857.497 ...)

These are the **pre-Phase-26/27** values. They are directly contradicted 130 lines later on the
very same page, in the "## Restated in v4.0 (Phase 28)" table, which gives the corrected
`fit_dso ≈ -286.107696` and `acct.dso ≈ +3.739374` (FIX-01/02, FIX-09/10). Section 6 itself was
never touched by this phase's restatement pass, so a reader who stops at Section 6 (the page's
own designated "state this plainly" paragraph) gets numbers that are now wrong, with no pointer
telling them to keep reading for the correction — unlike Section 8, which got explicit
`!!! warning "CORRECTED ..."` admonitions for its own stale claims.

Worse, the **derived** aggregate-welfare-gap percentage was never recomputed at all, anywhere in
the restatement, and it moved by more than an order of magnitude in relative terms. I verified
this directly: running the current `HEAD` code with the exact population Section 6/the restated
table both reference gives `acct.dso=3.7393744862531797`, `acct.prosumer=-41039.14373797347`,
`fit_dso=-286.10769581257046`, `fit_prosumer=-40857.49706991592`. Using the codebase's own
identity `social == prosumer + dso` (`src/pricing/welfare.jl:30,158`):

```
welfare_dadp_new = acct.dso + acct.prosumer       = -41035.404363
welfare_fit_new   = fit_dso + fit_prosumer         = -41143.604766
gap%_new = 100*(welfare_dadp_new - welfare_fit_new)/abs(welfare_fit_new) = +0.2630%
```

versus the OLD numbers Section 6 still prints (`fit_dso=-196.216447`, `fit_prosumer=-40857.497`,
`acct.dso=3.725705`, `acct.prosumer=-41039.129`) which reproduce the stale "+0.045%" figure
exactly (`gap%_old = +0.0446%`). The **current, correct aggregate welfare gap is ≈+0.26%, about
5.9× larger than what both `thesis_reproduction_assumptions.jl:105` and
`scripts/thesis_case123_repro.jl:11` still assert.** The direction (small, positive, fragile) is
unchanged, but the magnitude claim is now materially wrong and was never re-measured — exactly
the class of defect this entire phase (FIX-11, "never silently drop or soften a caveat") exists
to catch, and exactly what this review's priority #1 asks to be checked. `scripts/
thesis_case123_repro.jl`'s own live-computed `welfare_delta_pct` (line 332) *would* print the
correct new value at runtime, but the static header-comment claim on line 11 was never updated to
match.

**Fix:** Recompute the aggregate welfare-gap percentage against the current model (≈+0.26% per
the derivation above; verify by actually running `scripts/thesis_case123_repro.jl` and reading
`welfare_delta_pct`) and update both citing locations. Rewrite Section 6 to either state the
current numbers directly, or explicitly mark it historical/pre-restatement with a forward
pointer to the "Restated in v4.0" table (mirroring the `!!! warning "CORRECTED ..."` treatment
already used in Sections 4/5/7/8 of the same page), so the two sections of the page no longer
contradict each other.

## Warnings

### WR-01: Regenerated `findings.txt` "RECOMMENDED BAND" no longer matches the golden it claims to be the verbatim source of

**File:** `results/repro_stability_check/findings.txt:24-28` (this diff), vs.
`test/test_thesis_repro.jl:19-22,64-68` (unchanged by this diff)

**Issue:** `test/test_thesis_repro.jl`'s header states the golden band constants are "copied
VERBATIM from the committed `results/repro_stability_check/findings.txt` 'RECOMMENDED BAND:'
line — NOT invented here" and pins `DSO_BAND_HI = 7.211125525764296`. This phase's Plan 28-02
regenerated `results/repro_stability_check/findings.txt` (part of this diff) with fresh
population-scale-sweep numbers (correctly reporting `sign_flip_survives: true` and the
1/20 flake rate) — but its own "RECOMMENDED BAND" line now computes to
`DSO_BAND_HI = 7.229422341375` (`1.5 × max|dso| = 1.5 × 4.819615`), not `7.211125525764296`.
`test/test_thesis_repro.jl` was not touched by this diff, so its "copied verbatim" provenance
claim is now false: the committed artifact it cites no longer contains the value it claims to
have copied.

This does not currently break anything — the pinned point (`acct.dso≈3.739`) sits comfortably
inside both the old and the new band — but (a) it silently violates the exact "verbatim, never
invented, never silently drifted" discipline this whole phase is chartered to uphold, invisible
to `scripts/audit_goldens.py` because that script only scans `git diff -- test/` and
`test/test_thesis_repro.jl` itself didn't change; and (b) the currently-committed golden
(`7.211125525764296`) is now *tighter* than the freshly-measured evidence would justify
(`7.229422341375`), so a future legitimate re-measurement landing between those two values would
cause a spurious, hard-to-diagnose test failure against a golden whose own cited provenance
document has already moved past it.

**Fix:** Either update `test/test_thesis_repro.jl`'s `DSO_BAND_HI` to the new
`results/repro_stability_check/findings.txt` value (`7.229422341375`) with an attributed
old→new comment (matching this file's own established convention, e.g. the 260823-gea
precedent), or add a note to `results/repro_stability_check/findings.txt` explaining that its
own "RECOMMENDED" band was deliberately NOT re-pinned this session and citing why the old,
tighter golden remains valid.

### WR-02: `audit_goldens.py`'s attribution-reference regex accepts a bare `D-` anywhere in the window, which is a latent false-attribution risk

**File:** `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py:72`

**Issue:** `ATTRIBUTION_REF_RE = re.compile(r"(Plan[- ]|FIX-|PM-|WR-|D-)")` treats any
occurrence of the two characters `D-` (a capital D immediately followed by a hyphen) anywhere in
the ±5-line window as sufficient evidence of an attribution comment. This is far looser than
`FIX-`/`PM-`/`WR-`, which are effectively unambiguous project ID prefixes. `D-` alone will also
match ordinary hyphenated prose that is extremely common in this codebase's own comment style —
e.g. "closed-loop", "based-on-", "measured-", "applied-", "bound-driven", "hand-derived" all
contain the literal substring `D-`. A future diff that moves a golden value inside a comment
block containing any such word — with no real `D-<number>` decision-ID reference nearby — would
be silently marked `attributed = True` by this heuristic, precisely reintroducing the failure
mode SC-1 exists to prevent (an unattributed golden move slipping through unnoticed).

I confirmed this is not presently causing a false pass: of the 13 flagged pairs in the current
`5939799..HEAD` run, the only one whose attribution rests on `ATTRIBUTION_REF_RE` alone
(`test/test_admm_reactive.jl:286->315`) is attributed via genuine `D-14`/`D-03` decision-ID
citations in its comment block, not a stray hyphenated word. But this is incidental to the
current diff's prose, not a property the regex itself enforces — the tool's own soundness
depends on nobody ever writing "load-driven", "value-based", or similar near a future golden
change.

**Fix:** Tighten the pattern to require a decision-ID shape, e.g. `\bD-\d+\b`, matching the
existing `\bFIX-\d+\b`-style precision already implicit in `FIX-`/`PM-`/`WR-` (which are almost
always followed by digits in this repo's convention). Re-run the self-test and the
`5939799..HEAD` audit after tightening to confirm the same 12/1/0 split still holds.

## Info

### IN-01: Asymmetric replace-block pairing in `audit_goldens.py` can leave extra added/removed lines unchecked

**File:** `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py:191-203`

**Issue:** `process_hunk` pairs qualifying removed/added lines strictly position-wise and stops
at `pair_count = min(len(qual_removed), len(qual_added))`. In a replace block where the removed
and added runs have different qualifying-line counts (e.g. one line replaced by two, or vice
versa), any qualifying lines beyond the shorter run's length are never compared against anything
and so can never be flagged, even if one of them introduces a new, unattributed numeric literal.
The script's own docstring acknowledges it targets "the classic unified-diff 'replace' block"
pattern, so this is a known, reasonably-scoped heuristic limitation rather than a defect — noted
here only because it's a real gap in the tool's coverage a future maintainer should be aware of
if a golden-move diff ever doesn't fit that classic shape.

**Fix:** No action required now; consider a follow-up note in the script's own "Known false
positives/negatives" section documenting this specific pairing-count asymmetry explicitly (it is
currently not called out, unlike the other three documented blind spots).

---

_Reviewed: 2026-09-30T10:03:56Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
