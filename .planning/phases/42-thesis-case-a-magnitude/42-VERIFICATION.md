---
phase: 42-thesis-case-a-magnitude
verified: 2026-10-26T23:14:21Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 0
re_verification: none
human_verification:
  - test: "Visually review the rendered writeup page docs/build/generated/case_a_magnitude.html (nav entry, per-seed headline table, the printed UNDEFINED lines, the refusal-ledger listing, the attribution section, the 32 'measured, pre-registered' qualifier phrasings)."
    expected: "Page renders cleanly in the docs site with the nav entry 'Case A Magnitude'; every derived figure shown is qualified and cited to its CSV row; the UNDEFINED outcomes read as recorded findings, not as failures."
    why_human: "Rendering, typography and prose reading quality cannot be verified by grep; the docs build exit-0 and page-execute checks are committed evidence but the visual result needs eyes."
  - test: "Optionally re-run the :slow reproducibility item (TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()', ~47 min live 784-house seed-42 re-measurement)."
    expected: "exit 0; the live ladder reproduces the committed seed-42 rows bit-exactly (default error:CertificateError iters=80 → gap_1e-10 converged iters=80, welfare -378163.5654347284, FIT error:SolveFailedError at attempt+retry) within WELFARE_RTOL=1e-8."
    why_human: "The strongest independent confirmation that the committed CSV rows are machine-produced, but it is a ~47-min solving run — outside the verifier's fast spot-check budget; the 42-06 green run and the bit-exact probe are committed evidence."
  - test: "Read the attribution section of the writeup as a thesis author and confirm the honest-magnitude framing (headline UNDEFINED at the registered mix; every measurable point 3.3–7.0 orders below +25%; 'gap NOT FULLY ATTRIBUTED' as a pre-authorized recorded outcome) is the framing you want in the thesis."
    expected: "The framing is acceptable for the thesis narrative; no rewording needed — or requested edits are logged as follow-up prose work, not as a measurement gap."
    why_human: "Editorial/scientific judgment on the writeup's conclusions is a human decision; programmatically only the structural statements (present, live-computed) can be confirmed."
---

# Phase 42: Thesis Case A Magnitude — Verification Report

**Phase Goal:** A researcher gets an honest, pre-registered measurement of the DADP-vs-FIT welfare gain at the real 784-house population and an attribution of its gap to the thesis +25%.
**Verified:** 2026-10-26T23:14:21Z
**Status:** human_needed (all programmatic must-haves VERIFIED; 3 items need human eyes/compute)
**Re-verification:** No — initial verification

**Verification stance note (per dispatch):** REPRO-04 is judged on the HONESTY and COMPLETENESS of the measurement (pre-registration → execution → refusal ledger → honest status), NOT on whether a positive gain number exists. The protocol (§5, §9, §10) explicitly pre-authorized refusals, the documented non-closure, and "gap not fully attributed" as recorded outcomes. The measured outcome — FIT INFEASIBLE on every seed, headline Δ% UNDEFINED, measurable gains 3–7 orders below +25% — is therefore a *complete, honest* phase result, not a gap.

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | Protocol (gain definition, baseline, parameters) written and committed BEFORE any Case A run | ✓ VERIFIED | `42-CASE-A-PROTOCOL.md` committed `60e5d54` at **07:39:42**; first runner commit `72f55cb` **09:45:51**; first results commit `83bd6a7` **10:01:40**; headline seeds committed 11:32–12:36. Ordering holds for every artifact. Protocol is substantive (285 lines: §1 sign-safe definition + ban, §2 frozen config, §3 seeds 42–46, §4 AGR ladder, §5 FIT refusal policy, §6 crosscheck, §7 four axes with exact values, §8 proxy, §9 no-tuning guard, §10 golden policy) |
| 2 | Script fail-loud pre-registration guard is structural, not aspirational | ✓ VERIFIED | `assert_protocol_registered` in `scripts/lib/case_a_common.jl:90-101` (errors on missing file AND on uncommitted file); called as **first statement of all 9 runner mains** (`case_a_magnitude.jl` lines 1070–2088). Live spot-check: committed path → returns SHA; missing path → ErrorException; uncommitted file (no git history) → ErrorException. Test items cover all three branches (`test/test_case_a_magnitude.jl` items at lines 64/83/104) |
| 3 | Sign-safe gain definition in code; naive ratio banned | ✓ VERIFIED | `welfare_gain` at `case_a_common.jl:55-56` = `100·(W_DADP−W_FIT)/\|W_FIT\|`; live spot-check: W_DADP=−4.725e5 vs W_FIT=−3.78e5 → Δpct=**−25.0** (the banned ratio would print +1.25). Algebra-anchor + sign-safety test items exist; the committed-CSV structural item re-derives delta_pct = 100·delta_w/\|welfare_fit\| |
| 4 | Honest headline measurement at 784 houses, seeds 42–46, with seed spread | ✓ VERIFIED | `magnitude.csv`: 12 rows; seeds **42–46 all present** with full per-rung ladder history + terminal gain row. W_DADP certified **5/5**; recomputed live: mean = **−378163.55846378894**, min–max spread = **0.04837650043191388** (1.2792e-7 relative) — bit-identical to the writeup's claims. Seed 42's certified row (−378163.5654347284 at gap_1e-10, iters=80) reproduces the Phase-40 `agreement.csv` anchor |
| 5 | Honest refusal handling: FIT leg recorded, not fabricated | ✓ VERIFIED | All 5 gain rows carry `status=error:SolveFailedError` with notes naming **attempt AND the single sanctioned retry** (termination INFEASIBLE), and **empty delta_w/delta_pct columns** — zero fabricated gain rows (verifier-checked). Δ% printed as UNDEFINED with cause (10 UNDEFINED occurrences in rendered HTML). IEEE-13-ground FIT-INFEASIBLE precedent generalized to scale, exactly as protocol §5 pre-registered |
| 6 | Complete refusal ledger (no cherry-picking) | ✓ VERIFIED | **25 error rows** across the two ledgers the writeup counts live: 7 in magnitude.csv + 18 in ablation.csv (verifier recounted independently = 25, matching the rendered page's "total honest error rows in the two ledgers: 25"). Includes scale_0.5's ladder exhaustion (4 rung refusals + `error:ladder_exhausted` terminal) and the two headline default-rung CertificateError rows with the battery-complementarity violation text |
| 7 | Crosscheck + settlement lenses at the certified point | ✓ VERIFIED | `crosscheck.csv`: W_CEN=−378163.58894571784 via `centralized_optimizer=tol_gap_1e-10` (which-path column recorded, never loosened); \|Δ\|=0.023510989442002028 — **identity re-verified** by the verifier from the row's own welfare columns. `lens_summary.csv`: 4 legs; dadp ok with **dso_total=+2.9799 POSITIVE** vs flat −1600.51 / tou −1561.18 (DSO-surplus sign flip confirmed at full scale); fit leg honest `error:SolveFailedError` |
| 8 | OFAT ablation over the 4 pre-registered axes, complete, honest statuses | ✓ VERIFIED | `ablation.csv`: **35 rows, 4 axes, 18 axis/variant groups** at seed 42 — every protocol-pinned variant ran (fit_params ×3, price_range ×3, population 9 variants incl. reuse rows, device_mix ×3). 4 certified pairs with sign-safe Δ% **arithmetically re-verified by the verifier**: proxy_ieee123 +0.0135162, rung_0.25 +1.8467e-5, rung_0.5 +2.3801e-6, batteries_out +1.3277e-5 (the only full certified pair at 784 houses — the A1/A4 asymmetry MEASURED). scale_0.5 = documented ladder exhaustion; scale_2.0 certified at default iters=52 |
| 9 | No parameter tuned toward the +25% target | ✓ VERIFIED | Axes AND exact values frozen pre-run (protocol §7 = committed runner Dicts = source-contract test items pinning `lam_export_half/scale_0.5/batteries_out/pv_half` to the protocol). Per-unit commit audit trail (16 measurement commits, every refusal individually committed). The ONE post-run constant change went through the protocol's own amendment procedure: `af815b0` append-only (**0 deleted lines** in the protocol file, verifier-checked), solver-attr spelling repair only, `AGR_TOL_RUNGS` edited in the same commit. protocol_sha on **all 61 data rows** across the 5 CSVs, non-empty; exactly 2 distinct SHAs (60e5d549… pre-run / af815b0… post-amendment) — both match `git rev-parse` exactly, and the ledger splits visibly at the amendment. The writeup asserts only 25.0/Δ% distance factors, never toward ±25% |
| 10 | Proxy restatement + comparison against ≈+0.26% | ✓ VERIFIED | `proxy.csv`: ieee123-default gain ok, Δ%=+0.0135162 (sign-safe identity verified); ieee13-default honest refusal row. Writeup reports proximity to the cited ≈+0.263% provenance figure (`thesis_case123_repro.jl:11,44` — external literature value, correctly labeled NOT a gate), factor 19.5 below, "never gated" |
| 11 | Writeup: live recomputation, structural UNDEFINED/NOT-FULLY-ATTRIBUTED statements, registered | ✓ VERIFIED | `docs/literate/case_a_magnitude.jl` (605 lines): quote-aware committed-CSV reads with fail-loud build guards; mean/spread/Δ%/factors/sha-trail all recomputed in page code. **Stale-literal scan: zero measured values appear as code literals** (the only grep hit is a comment citing the Phase-40 agreement.csv anchor). No solve call exists on the page. Attribution statement present (4 numbered points: UNDEFINED at registered mix → all measurable points orders below +25% → stated explanations → NOT FULLY ATTRIBUTED as recorded outcome). Registered at BOTH `docs/make.jl` sites (line 65 Literate tuple + line 116 pages tree); `scripts/README.md` registered; rendered HTML exists (57,680 bytes) with 32 qualifier applications and 10 UNDEFINED prints, matching the 42-06 claims |

**Score:** 11/11 truths verified

### Deferred Items

None — no must-have failed, so Step 9b filtering had nothing to defer.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` | Pre-registered protocol: gain definition, frozen config, ladder, 4 axes, seeds, proxy fixture; SIGN-SAFE | ✓ VERIFIED | 285 lines, committed pre-run (60e5d54), append-only amendment (af815b0), all executed values traceable to §2/§3/§4/§5/§7 |
| `scripts/lib/case_a_common.jl` | Guard + gain + provenance helpers + device-variant rebuild | ✓ VERIFIED | 297 lines (≥40); all named exports present; live-tested (3 guard branches + sign-safety); WIRED (included by runner + tests) |
| `scripts/case_a_magnitude.jl` | Runner: headline/proxy/crosscheck/lenses/4×ablation modes, guard-first, upsert CSVs | ✓ VERIFIED | 2158 lines (≥150); 9 mains all guard-first; AGR_TOL_RUNGS Dict matches protocol incl. amended rung; fit_baseline unchanged + on_inexact=:report + single pinned retry; WIRED (produced all 5 CSVs) |
| `test/test_case_a_magnitude.jl` | Fast-lane structural items + :slow reproducibility band | ✓ VERIFIED | 729 lines; sign-safety, 3 guard branches, source-contract items pinning Dicts to protocol, committed-CSV schema/identity item, :slow item with WELFARE_RTOL=1e-8 pinned verbatim from the bit-exact probe (golden-policy header present) |
| `results/thesis_case_a_magnitude/magnitude.csv` | Per-seed headline + ladder history, protocol_sha per row | ✓ VERIFIED | 12 rows; 5 seeds; honest statuses; sha-stamped; identities re-verified |
| `results/thesis_case_a_magnitude/ablation.csv` | OFAT table: 4 axes × pinned variants at seed 42 | ✓ VERIFIED | 35 rows / 18 groups; honest statuses incl. exhaustion + reuse-with-source rows; sha-stamped |
| `results/thesis_case_a_magnitude/crosscheck.csv` | Centralized bound + which-optimizer + price lens | ✓ VERIFIED | tol_gap_1e-10 recorded; delta identity verified |
| `results/thesis_case_a_magnitude/lens_summary.csv` | Four-leg settlement at certified point | ✓ VERIFIED | dadp +2.9799 / flat −1600.51 / tou −1561.18 / fit honest refusal; post-amendment sha (re-run after notes flattening) |
| `results/thesis_case_a_magnitude/proxy.csv` | Proxy restatement artifact, honest statuses | ✓ VERIFIED | Committed 10:01 (42-03); ieee123 ok +0.0135%; ieee13 honest refusal |
| `docs/literate/case_a_magnitude.jl` | Honest-magnitude writeup, ≥100 lines, live-recomputed | ✓ VERIFIED | 605 lines; no stale literals; no solve calls; fail-loud evidence guards |
| `docs/make.jl` | Both registration sites | ✓ VERIFIED | Lines 65 (Literate tuple) + 116 (pages tree) |
| `docs/src/api.md` | Settlement/Tariffs/Equity @autodocs section (Rule-3 fix) | ✓ VERIFIED | Present; unblocked the docs build (exit 0 per 42-06) |

All phase artifacts are **committed** — `git status --porcelain` over the phase file set is empty.

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `case_a_common.jl` | `42-CASE-A-PROTOCOL.md` | PROTOCOL_PATH + isfile/git-log guard | ✓ WIRED | Guard resolves the locked path and returns the true git SHA (live-verified = af815b0…) |
| `case_a_magnitude.jl` | `case_a_common.jl` | include of shared helpers | ✓ WIRED | welfare_gain/flatten_note/provenance/rebuild all consumed |
| `case_a_magnitude.jl` | `solve_admm` | agr_optimizer per AGR_TOL_RUNGS, stop-on-first-certified | ✓ WIRED | Ladder history in magnitude.csv proves per-rung execution (default→gap_1e-10→…→hard stop) |
| `case_a_magnitude.jl` | `fit_baseline` | on_inexact=:report + ONE pinned retry | ✓ WIRED | Every refusal note records attempt AND pinned retry verbatim |
| CSVs | Protocol | protocol_sha column | ✓ WIRED | 61/61 rows sha-stamped; SHAs == git rev-parse of the two protocol commits |
| `test/test_case_a_magnitude.jl` | runner/lib/CSVs | include + source-contract + committed-CSV items | ✓ WIRED | Fast lane green (599→612 across the phase; final sweep 612/612 after review fixes) |
| Writeup | 5 CSVs | quote-aware fail-loud reads | ✓ WIRED | Page errors the docs build if any CSV is missing/empty/incomplete; recomputes everything live |
| `compare_tariffs` (42-02 seam) | `solve_admm` | agr_optimizer kwarg, default byte-identical | ✓ WIRED | Review diffed byte-for-byte vs phase-41 base b99a5b7: exactly kwarg + docstring + nothing-default forwarding |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `docs/literate/case_a_magnitude.jl` | MAG/XCHK/ABL/LENS/PROXY | Committed CSVs under `results/thesis_case_a_magnitude/` | Yes — verifier recomputed mean/spread/Δ%/delta identities from the same rows and got bit-identical values | ✓ FLOWING |
| `magnitude.csv` / `ablation.csv` rows | welfare/rung/status | Guarded runner (9 mains), per-unit commits | Yes — 16 per-unit measurement commits (043f008…3b64b5f) each landing rows before the next unit; sha stamps + arithmetic identities + seed-dependent ladder behavior (42/46 refused at default, 43/44/45 certified at default) are consistent with machine-produced data | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Headline mean/spread honest | python3 csv recompute | mean −378163.55846378894, spread 0.04837650043191388 (bit-identical to writeup) | ✓ PASS |
| Sign-safe Δ% identity on all 4 certified pairs | python3: 100·(wd−wf)/\|wf\| | All 4 pairs exact (<1e-9 rel); no fabricated deltas | ✓ PASS |
| Crosscheck delta identity + which-optimizer | python3 | abs_delta exact; tol_gap_1e-10 recorded | ✓ PASS |
| Refusal ledger count | python3 error-row count | 25 (7 mag + 18 abl) = writeup's live count | ✓ PASS |
| Guard: committed path returns SHA | julia assert_protocol_registered() | af815b06578a457a5424e2116c21be53539d09b4 | ✓ PASS |
| Guard: missing file fails loud | julia, nonexistent path | ErrorException "PRE-REGISTRATION VIOLATION" | ✓ PASS |
| Guard: uncommitted file fails loud | julia, tmp file, no git history | ErrorException "PRE-REGISTRATION VIOLATION" | ✓ PASS |
| Sign-safety on negative welfare | julia welfare_gain(−4.725e5, −3.78e5) | Δpct = −25.0 (banned ratio would give +1.25) | ✓ PASS |
| Writeup freshness | grep measured values as code literals | 0 hits (only a comment citing the Phase-40 anchor) | ✓ PASS |
| Rendered page | grep docs/build/generated/case_a_magnitude.html | 57,680 bytes; 32 qualifiers; 10 UNDEFINED | ✓ PASS |
| Registrations | grep make.jl / scripts/README.md | both make.jl sites (3 mentions) + README (1) | ✓ PASS |

### Probe Execution

No probes declared in any 42-PLAN/42-SUMMARY and no conventional `scripts/*/tests/probe-*.sh` exist → SKIPPED (nothing to run). The 42-06 "probe" was the gate-then-golden measurement run that pinned the :slow band; its persistent form is the `:slow` test item (47-min live run → routed to human verification below).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| REPRO-03 | 42-01, 42-03, 42-06 | Case A protocol pre-registered in writing before the run | ✓ SATISFIED | Truths 1–3: protocol committed 07:39 (first), fail-loud guard first in every main, sign-safe definition |
| REPRO-04 | 42-02, 42-03, 42-05, 42-06 | Run Case A on real 784-house population; DADP-vs-FIT gain as absolute + relative with seed spread, honest whatever the magnitude | ✓ SATISFIED (honest-UNDEFINED outcome) | Truths 4–7: 5/5 seeds, absolute W_DADP + spread reported bit-exactly; relative Δ% honestly UNDEFINED (FIT INFEASIBLE at attempt+retry on every seed — a protocol §5 pre-authorized recorded outcome); refusal ledger complete; crosscheck + lenses at full scale |
| REPRO-05 | 42-02, 42-03, 42-04, 42-05, 42-06 | Ablation over FIT params, price range, population, device mix attributes the gap; compared with 1-house-per-bus proxy (≈+0.26%); nothing tuned toward target | ✓ SATISFIED | Truths 8–11: full 4-axis OFAT; proxy comparison reported-not-gated; no-tuning guard structural (pre-run freeze + sha trail + append-only amendment); attribution statement present and honest (NOT FULLY ATTRIBUTED as pre-authorized outcome) |

**Orphaned requirements:** none — REQUIREMENTS.md maps exactly REPRO-03/04/05 to Phase 42 (lines 126–128); all three are claimed by plan frontmatter and all have committed evidence.

### Code Review Follow-Through

1 BLOCKER (BL-01) + 3 WARNINGS (WR-01/02/03) found in `42-REVIEW.md`; all 4 fixed per `42-REVIEW-FIX.md` (status: all_fixed, final fast sweep 612/612) — fix commits verified present: `4861c81` (field-aware iters), `a1cc417` (budget-status vocabulary), `f6fad01` (per-kind lens ledger identity), `b5ece3a` (writeup prose figures recomputed live). WR-03's fix is directly load-bearing for this verification: it eliminated the last hand-copied derived numbers from the writeup.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER/placeholder-language scanned across all 11 phase-touched source + artifact files | — | Zero debt markers. No empty implementations, no hardcoded empty data flowing to output |

### Human Verification Required

See frontmatter `human_verification`. Summary:

1. **Rendered writeup page visual review** — the page is the phase's public record; build + page-execute + content greps are green, but rendering/prose need eyes.
2. **Optional: re-run the :slow reproducibility item** (~47 min) — strongest independent confirmation the committed rows are machine-produced; committed evidence (bit-exact probe, green 18/18 slow run) already stands in.
3. **Editorial sign-off on the honest-magnitude/attribution framing** for the thesis narrative.

### Gaps Summary

**No gaps.** Every gap-class check the dispatch specified came back clean:

- **Protocol-first ordering holds** — protocol commit 07:39 precedes the runner (09:45), the first results artifact (10:01), and every headline run (11:32+); the guard makes future violations structurally impossible.
- **No gain row fabricated** — all 5 headline gain rows and 12 of 14 ablation gain rows are honest refusals with empty delta columns; the 4 certified pairs' Δ% re-derive exactly under the registered sign-safe definition.
- **Refusal rows present and complete** — 25-row ledger, live-counted by the writeup, individually committed per unit; ladder exhaustion recorded as the documented non-closure.
- **Writeup does not hand-copy stale numbers** — zero measured literals in page code; the review's WR-03 fix removed the last of them; every figure recomputes from the committed CSVs.
- **Attribution statement present and untuned** — 4-point statement resolves the +25% question honestly (UNDEFINED at the registered mix; every measurable point 3.3–7.0 orders below; NOT FULLY ATTRIBUTED as protocol §9 pre-authorized); the single post-run protocol change was a solver-attribute spelling repair through the amendment procedure, with the sha trail splitting the ledger visibly.

The phase's negative/UNDEFINED measurement outcome is the protocol working as designed, not a phase failure. Status is `human_needed` solely for the rendering/visual and heavy-compute items above — the automated evidence chain (pre-registration → guarded execution → committed honest rows → live writeup) is fully verified.

---

_Verified: 2026-10-26T23:14:21Z_
_Verifier: the agent (gsd-verifier)_

---

## Human Verification Resolution (2026-10-27)

All three human_verification items RESOLVED via conversational UAT (42-HUMAN-UAT.md, status: complete, commit 38b5840):

1. **Rendered writeup page — PASS.** Docs rebuilt 2026-10-27 09:23 after WR-03 (b5ece3a): exit 0, 62.8 KB page; structural UNDEFINED headline ("certified pairs 0 of 5 seeds"), live seed→rung attribution, 47 honest refusal rows, "The gap is NOT FULLY ATTRIBUTED" section. User confirmed.
2. **Optional :slow reproducibility re-run — SKIPPED (with reason).** Band already certified bit-exact (delta 0.0, WELFARE_RTOL=1e-8) during 42-06; CSVs + per-row protocol SHAs + per-unit commits carry the audit trail. User declined re-run.
3. **Editorial sign-off on honest-magnitude/attribution framing — PASS.** Framing approved for thesis: W_DADP certified 5/5 seeds (mean -378163.5585, spread 1.3e-7 rel, crosscheck |Δ|=0.0235); registered-mix Δ% UNDEFINED (FIT INFEASIBLE on every seed, stated as measured property); certified pairs 3-7 orders below +25%; NOT FULLY ATTRIBUTED as permitted terminal state (protocol §9), no tuning. User signed off.
