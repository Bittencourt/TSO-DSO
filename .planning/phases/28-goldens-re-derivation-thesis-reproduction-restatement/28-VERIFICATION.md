---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
verified: 2026-09-30T00:00:00Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement Verification Report

**Phase Goal:** The project's headline findings (thesis reproduction, SOCP-inexactness) are re-run
against the corrected models and restated, and a cross-phase audit confirms every golden moved in
Phases 26–27 was re-derived with an explanation.

**Verified:** 2026-09-30
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A cross-phase golden audit lists every golden moved in Phases 26–27 with old value, new value, and explanation, confirming none was silently re-pinned | ✓ VERIFIED | `28-CROSS-PHASE-AUDIT.md` has all 3 required sections (Section 1/2/3 present, `grep -n "^## Section"` confirms). Independently re-ran `scripts/audit_goldens.py --base 5939799 --head HEAD` myself: exit 0, `13 attributed / 1 allowlisted (cited) / 0 unattributed` — exact match to the documented closing-gate result. `--selftest` passes. |
| 2 | The v2.1 thesis reproduction (DSO-surplus sign flip, welfare-magnitude gap) is re-run against the corrected model and PROJECT.md/literate docs restate whichever result changed | ✓ VERIFIED | `docs/literate/thesis_reproduction_ieee123.jl`/`thesis_reproduction_assumptions.jl` carry "Restated in v4.0 (Phase 28)" old-vs-new tables (`acct.dso` +3.725705→+3.739374, `fit_dso` -196.216447→-286.107696, sign flip unchanged). `PROJECT.md`'s Current State section states the same and links to `28-RESTATEMENT-SUMMARY.md`. A code-review pass (28-REVIEW.md) caught a real gap — the derived aggregate-welfare-gap % (≈+0.045%→≈+0.263%) was never recomputed — and it was fixed (commit `fbc1e35`) across `thesis_reproduction_assumptions.jl` Section 6 (now has an explicit `!!! warning "CORRECTED ..."` box), `scripts/thesis_case123_repro.jl` header, `docs/writeups/FRAMEWORK_GUIDE.html`, `PROJECT.md`, and `28-RESTATEMENT-SUMMARY.md`. Grepped the whole repo for `0.045%`/`-196.2`/`-196.22`: every remaining hit is either explicitly labeled stale/historical/corrected in Phase-28-or-later files, or lives in pre-Phase-26 historical milestone documents (v2.1/v3.0 archives, quick-task summaries) which are appropriately left as historical record. |
| 3 | The v2.1/v3.0 SOCP-inexactness findings (EXACT-04 etc.) are re-verified against the corrected exactness copy and restated if the verdict changed | ✓ VERIFIED | `test/test_ac_oracle.jl`'s stale "SOC relaxation genuinely INEXACT" comment is gone (grep confirms zero hits) and replaced with a gate-qualified dual-mode explanation. `docs/literate/ac_oracle.jl`/`restricted_branch_flow.jl`/`socp_applicability.jl` all carry gate-1/gate-2-qualified "Restated in v4.0 (Phase 28)" sections. `socp_applicability_sweep.jl` and its regenerated `results/socp_applicability/*` report both `ConvexBranchFlow()` and `thesis_literal=true` classifications. |
| 4 (CONTEXT.md) | Scripted audit script covers docs/PROJECT cited numbers, not just test/ diffs | ✓ VERIFIED | Plan 28-01 Task 2 grepped `.planning/PROJECT.md` and `docs/literate/*.jl` for the six known-moved headline values; `28-CROSS-PHASE-AUDIT.md` Section 3 states the prose-citation audit is clean. Confirmed independently via my own repo-wide greps above. |
| 5 (CONTEXT.md) | Full REPRO-01 re-run with sweep + figures + writeups | ✓ VERIFIED | `results/thesis_case123_repro/`, `results/thesis_caseA/`, `results/repro_stability_check/findings.txt` regenerated (Plan 28-02); `docs/writeups/thesis_caseA.pdf` recompiled via `typst compile --root .`. Stability sweep re-run: flake rate 13/20→1/20, sign-flip survival 2/5→5/5. |
| 6 (CONTEXT.md) | EXACT-04 under both copies with gate-1/gate-2 precision | ✓ VERIFIED | Plan 28-03 measured EXACT-04 under both `ConvexBranchFlow()` and `ConvexBranchFlow(; thesis_literal=true)` for both gates: gate 1 exact under both; gate 2 inexact under default, exact under thesis_literal — every restatement sentence names which gate. |
| 7 (CONTEXT.md) | MPC + DLMP restatements; in-place callouts; summary page linked from PROJECT.md; docs build executes | ✓ VERIFIED | `docs/literate/mpc_rolling_horizon.jl`/`scripts/demo_mpc_plots.jl` carry the FIX-10 truth-settlement restatement with live-measured numbers (3/19 hours overload); DLMP `.cone`/`.drop` closure (FIX-07) confirmed already complete (verification only). `28-RESTATEMENT-SUMMARY.md` is linked from `PROJECT.md`'s Current State section. Post-fix docs build log (`28-postfix-docs.log`) shows exit 0 (`28-postfix-docs.done` = `0`), confirmed present at current HEAD. |
| 8 | Full suite green at phase close, no regression vs Phase 27 baseline, no worktree contamination | ✓ VERIFIED | `28-postfix-suite.log` head line `HEAD=d8ccc1d`, tail shows `Test Summary: Pass 30703 Broken 5 Total 30708`, exit line "tests passed" — exact match to Phase 27 baseline (30703/0/0/5). `28-postfix-suite.done`/`28-postfix-docs.done` both contain `0`. Current git HEAD (`e0a4b0c`) is a docs-only commit on top of `d8ccc1d` (confirmed via `git diff d8ccc1d e0a4b0c --stat`: only log/review files changed), so the certified suite/docs-build results are current. `git status` is clean. |

**Score:** 8/8 truths verified

### Code Review Loop

A `gsd-code-reviewer` pass (`28-REVIEW.md`, standard depth, 18 files) independently re-ran the
EXACT-04 fixture and the full IEEE-123 REPRO-01 reproduction directly against HEAD and confirmed
every gate-1/gate-2/cost/surplus number in the restated pages matched to cited precision. It found
one CRITICAL issue (CR-01: stale aggregate-welfare-gap % and surplus figures left uncorrected in
`thesis_reproduction_assumptions.jl`'s Section 6, contradicting the same page's own restatement
table) and two WARNINGs (WR-01: `test/test_thesis_repro.jl`'s `DSO_BAND_HI` golden's provenance
comment claimed "copied verbatim" from a `findings.txt` that had since moved past it; WR-02:
`audit_goldens.py`'s attribution regex too loosely matched a bare `D-` substring). All three were
fixed in commits `fbc1e35`/`92e8f3b`/`efaf58e`, re-certified at HEAD `d8ccc1d` (suite 30703/0/0/5,
docs build exit 0), and the orchestrator's iteration-2 re-review confirmed `status: clean`
(0 critical, 0 warning, 1 info carried forward — IN-01, a documented, non-blocking heuristic
limitation in the audit script's own replace-block pairing, explicitly deferred as informational).

I independently re-verified all three fixes rather than trusting the REVIEW-FIX.md narrative:
recomputed the welfare-gap arithmetic by reading the corrected files directly (Section 6 now
carries a `!!! warning "CORRECTED ..."` box with the right numbers), confirmed `DSO_BAND_HI` in
`test/test_thesis_repro.jl` is now `7.229422341375` with an old→new+cause comment, and re-ran
`audit_goldens.py` myself against the live repo (exit 0, 13/1/0 split, matching the fix report).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.../scripts/audit_goldens.py` | Mechanical unattributed-golden-move detector, self-testing | ✓ VERIFIED | Exists, `--selftest` passes (re-ran twice), live run against `5939799..HEAD` exits 0 |
| `.../28-CROSS-PHASE-AUDIT.md` | Consolidated Phase 26+27 audit, 3 sections + verdict | ✓ VERIFIED | All 3 sections present verbatim, closing verdict states SC-1 satisfied |
| `docs/literate/thesis_reproduction_ieee123.jl` | Restated, non-throwing REPRO-01 page | ✓ VERIFIED | Carries restatement table; confirmed non-throwing via post-fix docs build log |
| `docs/literate/thesis_reproduction_assumptions.jl` | Restated assumptions page, no stale contradiction | ✓ VERIFIED (after fix) | Section 6 corrected with warning box; restatement table intact |
| `results/thesis_case123_repro/`, `results/thesis_caseA/`, `results/repro_stability_check/findings.txt` | Regenerated against corrected model | ✓ VERIFIED | Regenerated per 28-02-SUMMARY.md, confirmed via mtime checks documented there; not independently re-run here per task's "do NOT rerun the full suite" instruction, but content matches restated numbers cross-checked live in the code-review pass |
| `docs/writeups/thesis_caseA.pdf` | Recompiled after figure regen | ✓ VERIFIED | `typst compile --root .` documented; gitignored artifact, existence not re-checked on disk (not required — build mechanism verified) |
| `test/test_ac_oracle.jl` | Corrected EXACT-04 comment, dual-mode gate-qualified | ✓ VERIFIED | Stale "genuinely INEXACT" framing removed (grep confirms), replaced with gate-2 mechanism |
| `docs/literate/{ac_oracle,restricted_branch_flow,socp_applicability}.jl` | Dual-mode, gate-qualified restatement | ✓ VERIFIED | All 3 carry "Restated in v4.0 (Phase 28)" with gate-1/gate-2 language |
| `docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl` | MPC truth-settlement restatement | ✓ VERIFIED | "Restated in v4.0 (Phase 28)" present in both, with live-measured overload numbers |
| `.planning/PROJECT.md` | Current State updated, links to restatement summary | ✓ VERIFIED | Phase 28 COMPLETE paragraph present, links to `28-RESTATEMENT-SUMMARY.md`; historical sections untouched (only Current State + one table row updated by the CR-01 fix) |
| `.../28-FINDINGS.md`, `.../28-RESTATEMENT-SUMMARY.md` | Consolidated findings + old→new table | ✓ VERIFIED | Both exist, one `##` section per plan in FINDINGS.md, full old→new table with named causes (including the CR-01-added welfare-gap row) in RESTATEMENT-SUMMARY.md |
| `28-postfix-suite.log`/`.done`, `28-postfix-docs.log`/`.done` | Post-review-fix certification | ✓ VERIFIED | Present, HEAD=d8ccc1d, 30703/0/0/5, docs build exit 0, both `.done` files contain `0` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `scripts/audit_goldens.py` | `test/*.jl` diffs | `git diff 5939799..HEAD -- test/` | WIRED | Re-ran live, exit 0 |
| `.planning/PROJECT.md` | `28-RESTATEMENT-SUMMARY.md` | forward link in Current State | WIRED | `grep -c "28-RESTATEMENT-SUMMARY" PROJECT.md` ≥ 1, confirmed by direct read |
| `test/test_thesis_repro.jl` | `results/repro_stability_check/findings.txt` | "copied verbatim" `DSO_BAND_HI` provenance | WIRED (after WR-01 fix) | Value now matches (`7.229422341375`), attributed |
| `docs/literate/thesis_reproduction_assumptions.jl` §6 | its own "Restated in v4.0" table | forward-pointer warning box | WIRED (after CR-01 fix) | No longer contradicts itself |

### Data-Flow Trace (Level 4)

Not applicable in the conventional sense — this is a docs/restatement phase, not a UI/data-pipeline
phase. The equivalent check (do the restated numbers reflect live re-computation, not
hand-transcription?) was performed via the code-review pass's independent re-execution of the
EXACT-04 and REPRO-01 fixtures directly against HEAD, and my own re-run of `audit_goldens.py` and
direct reads of the corrected source files — all numbers traced back to live solver output, not
copied prose.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Audit script self-test | `audit_goldens.py --selftest` | `SELFTEST: PASS` | ✓ PASS |
| Audit script live run at final HEAD | `audit_goldens.py --base 5939799 --head HEAD` | `13 attributed / 1 allowlisted / 0 unattributed`, exit 0 | ✓ PASS |
| No stale headline numbers repo-wide | `grep -rn "0.045%\|-196.22\|-196.216"` | All remaining hits explicitly labeled stale/historical or in pre-Phase-26 archives | ✓ PASS |
| No un-negated "genuine relaxation" claims | `grep -rn "genuine relaxation"` | All occurrences are negated (NOT/NEVER/NEITHER a genuine relaxation) — a Phase-26 finding, unaffected by and consistent with Phase 28 | ✓ PASS |
| DLMP voltage-component wording | `grep -n "voltage" docs/literate/pricing_dlmp.jl` | `.cone`/`.drop` used throughout with a deprecated-alias note for `.loss`/`.voltage` | ✓ PASS |
| `test_ac_oracle.jl` no longer claims cone-inexactness under default | `grep "SOC relaxation genuinely INEXACT" test/test_ac_oracle.jl` | zero hits | ✓ PASS |

### Probe Execution

Not applicable — no `scripts/*/tests/probe-*.sh` convention used by this project; verification
relied on the phase's own committed `audit_goldens.py` (re-run above) and the documented
`28-postfix-suite.log`/`28-postfix-docs.log` (not re-run, per the task's explicit instruction not
to re-run the full suite/docs build; instead the logs' HEAD line and Test Summary were read and
cross-checked against current `git rev-parse HEAD` ancestry).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FIX-11 | 28-01 through 28-05 | Cross-phase golden audit + REPRO-01 re-run/restatement + SOCP-inexactness dual-mode re-verification + deferred MPC/DLMP restatements | ✓ SATISFIED | All sub-clauses (SC-1/SC-2/SC-3) verified above; code-review gaps found and fixed; suite/docs certified post-fix |

Note: `.planning/REQUIREMENTS.md` and `.planning/ROADMAP.md`/`STATE.md` still show FIX-11/Phase 28
as "Pending"/"Executing" — this is expected: per this phase's own plans ("Do NOT edit
STATE.md/ROADMAP.md — the orchestrator does that at phase close"), that bookkeeping update happens
after verification passes, mirroring the same pattern already used for Phases 26/27.

### Anti-Patterns Found

No TBD/FIXME/XXX debt markers found in any file this phase modified. No placeholder/stub patterns
found — this is a docs/test-comment/results-regeneration phase with zero `src/` changes (confirmed
via `git diff 9ff2127..HEAD --stat -- src/` returning empty). One informational item carried
forward: IN-01 (`audit_goldens.py`'s replace-block pairing can leave excess lines in an
asymmetric-length replace block unchecked) — documented as a known, non-blocking heuristic
limitation, not a blocker for this phase's goal.

### Human Verification Required

None. All must-haves are verifiable via grep/direct-file-read/committed-log inspection; the
phase's own code-review loop already performed independent live re-execution of the headline
numeric claims (EXACT-04, REPRO-01), which I additionally spot-checked myself against the
corrected source.

### Gaps Summary

No gaps. The phase's own code-review gate caught one genuine material defect (CR-01: a stale
derived percentage left uncorrected, an actual instance of the class of bug FIX-11 exists to
prevent) plus two lower-severity provenance/robustness issues (WR-01, WR-02); all three were fixed,
independently re-verified by me against the current committed state, and re-certified with a fresh
full-suite + docs-build run (post-fix HEAD `d8ccc1d`, current HEAD `e0a4b0c` is a superset
docs-only commit). The cross-phase golden audit script, independently re-run in this verification
pass, confirms zero unattributed golden moves at the current HEAD. All three phase success
criteria and all CONTEXT.md-locked decisions are satisfied with codebase evidence, not just
SUMMARY.md narrative.

---

_Verified: 2026-09-30_
_Verifier: Claude (gsd-verifier)_
