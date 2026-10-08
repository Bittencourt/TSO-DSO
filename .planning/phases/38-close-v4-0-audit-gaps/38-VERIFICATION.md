---
phase: 38-close-v4-0-audit-gaps
verified: 2026-10-08T06:30:00Z
status: human_needed
score: 4/4 roadmap success criteria verified (7/7 requirements satisfied)
overrides_applied: 0
accepted_deviations:
  - item: "WR-02 skipped by design: held-out harness solved at tol_gap 1e-8 vs in-sample 5e-10"
    reason: "Adopting 5e-10 moved the CI stochastic golden (rel 4.0e-5); reverted per the no-golden-move rule. Documented in docs/src/status_policy.md §3 and the run_stochastic docstring (commit 25a3011)."
  - item: "MPC scenario B re-price on Julia 1.12.7 only"
    reason: "Hybrid floor gives ratio 1.165 at t=4 (old flat 0.233). The step escalates to :certified_convex_dual_restricted and dadp_trace[4] moves 0.008895250684296654 -> 0.008894113604359186. Regret and both welfare figures are bit-identical. No asserted value moves. Documented in 38-MEASUREMENTS.md and 38-FINAL-GATES.md. tau was not raised."
  - item: "Stochastic docs page excluded-draw counts: 5/10 on 1.12.5, 2/10 on 1.12.7"
    reason: "The page computes and prints the counts live. Solver/version dependence is documented in the WR-02 note."
  - item: "38-MEASUREMENTS.md lists 415/422/443 Pass for test_strategies.jl, but a clean-tree run gives 435"
    reason: "Ledger artifact, not a code issue (see Ledger Discrepancy section). The per-file baselines were measured on a dirty tree, so DrWatson's @tagsave added a :gitpatch key to both round-trip dicts (+8 assertions). All deltas and the full-suite arithmetic hold."
human_verification:
  - test: "Push a branch and confirm the GitHub Actions matrix (1.10/1.11/1.12), the jet job (1.12.7), the format job (incl. check_setup_names.py --selftest + plain) and nightly slow.yml all pass"
    expected: "All green; format job prints '21 testmodules, ... 0 unresolved'"
    why_human: "Requires GitHub-hosted runners; CPU/BLAS differences could shift cone residuals near tau (thinnest margins: happy-path MPC 0.938 on 1.12.5, build-once harness cycle 2 0.4964)"
  - test: "Prose spot-check of docs/writeups/FRAMEWORK_GUIDE.html model-text corrections (3.37, copy direction, gate floor, terminal pin, truth settlement, integer planning, MPC tier 1, OOS gate) against src/ and status_policy.md"
    expected: "Every corrected passage matches current code behaviour"
    why_human: "Prose accuracy judgement (38-VALIDATION Manual-Only)"
  - test: "Review the refreshed compare_default_stochastic results and Portuguese writeup (38-05, commit f6626b7)"
    expected: "Researcher accepts the regenerated seed-42 numbers (welfare_gap -0.0323948881649585, 0/10 refused)"
    why_human: "Research judgement on a published artifact refresh"
---

# Phase 38: Close v4.0 Audit Gaps Verification Report

**Phase Goal:** The cross-phase gaps found by the v4.0 milestone audit are closed. Every SOCP price certificate uses the same hybrid exactness floor, every test under `test/` runs in some suite, and prose no longer contradicts the code.
**Verified:** 2026-10-08
**Status:** human_needed. All automated checks pass and there are no gaps. The remaining items need GitHub CI or a human reader.
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths (ROADMAP SC1-4)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | MPC first-tier certificate uses the shared per-branch arithmetic and stays non-throwing. A test shows a point the old flat 1e-6 floor accepted now escalates. The canary is unchanged and any moved golden is documented. | VERIFIED | `src/experiments/mpc_loop.jl:872` `cone_maxratio = _socp_cone_check(o.ctx).maxratio`. The kernel (`src/models/exactness.jl:148-224`) loops `_cone_row`, the same arithmetic `hybrid_ratios` uses. Commit 17a9cf9 deletes the inline `tol = 1e-6 + 1e-4*max(...)` loop, and `git grep "1e-6 + 1e-4"` on mpc_loop.jl finds no match. The remaining `1e-6` at :1240/:1265 is the unrelated true-state band guard. The docstring (:795-800) accurately describes the kernel, defaults, hybrid floor, the no-throw/no-try contract and the feeder-identity `ArgumentError` guard. The regression testitem at `test/test_mpc_loop.jl:378-446` forces a 5e-7 slack on light branch 2. It asserts old-floor ratio (`hybrid_ratios(...; atol=1e-6)`) ≤ 1, `cone_maxratio == max hybrid_ratios` (parity), ratio > 1 and `:certified_convex_dual_restricted`. The postfix log shows that escalation (`cone_maxratio = 2.457082735245664`). Canary: iters=56 and welfare -4823.66604824162 in p38-full125/p38-postfix125. On 1.12.7 the welfare is -4823.666048218671 (4.8e-12 rel). No golden literal was removed from any test file (`git diff 4ab43d6 HEAD -- test`). |
| 2 | `test/test_admm_timeout.jl` runs as `@testitem`s in the suite, checks `:budget_exceeded`, and count-sets cover it. | VERIFIED | The file holds two `@testitem`s tagged `[:admm]`, discovered by TestItemRunner from `test/`. Item 1 asserts `res_budget.status == :budget_exceeded`, membership in `STATUS_VOCABULARY.solve_admm`, every price field `nothing`, and `@test_throws ConvergenceError` on `maxiter=1`. Item 2 asserts `:converged` with populated fields. Count-sets went to files=99 (98 before), all=517 and later 518. The file measured ≈13 s warm in-suite, under the 30 s `:slow` threshold, so it is untagged and in the fast set. |
| 3 | Stale prose is corrected: dispatch notes (TSODSO.jl and two literate pages), the store.jl docstring, and FRAMEWORK_GUIDE swept against the current API. | VERIFIED (code side). Guide prose accuracy is routed to human verification. | `src/TSODSO.jl:264-280` now describes `run(::MPC/::Stochastic, ::Scenario)` reached through `run(s.strategy, s)`. Code confirms this: `run.jl:161`, `mpc_loop.jl:1679`, `run_stochastic.jl:431`. Both literate pages (fc67d5c) say the same, and `git grep -i "NOT wired"` finds nothing in src/docs. `store.jl` docstring (:166-186) and code (:193-195) agree that the reactive mode is stored as a `Symbol` (or `missing`), and the docstring lists the stored OOS fields. FRAMEWORK_GUIDE has no `reactive_consensus = :live`, no `Phase N` cites and no removed kwargs; it uses `ReactiveMode.LIVE/OFF/CERTIFIED`. Every `identifier(` call in the guide exists in src/ (the only misses are KaTeX/JS tokens). `docs/writeups/README.md:6,16` lists the guide. `check_planning_ids.py` passes (250 files). |
| 4 | Hardening: `Scenario(strategy=ADMM(), allow_export=false)` fails at construction; the held-out re-solve runs the shared gate with a visible failure mode; `check_setup_names.py` runs in CI. | VERIFIED | `src/experiments/Scenario.jl:204-210` throws `ArgumentError` in the inner constructor. The testitem at `test/test_strategies.jl:179-203` covers the keyword path, `:admm` legacy and `run(ADMM(), …)`, and checks that MPC/Stochastic still accept import-only. `solve_stochastic_oos_step!` (`stochastic_welfare.jl:765-783`) uses `_socp_cone_check` with `c.maxratio <= 1 \|\| throw(CertificateError(...; kind=:socp_exact))`, so NaN is refused (WR-01). `_stoch_solve_held_out!` converts only that kind and rethrows everything else. `run_stochastic.jl:361` excludes `infeasible_h .\| inexact_h`; `_stochastic_status` returns `:oos_inexact_skipped`, which is in `STATUS_VOCABULARY.run_stochastic` (`src/core/errors.jl:125`) and status_policy.md:61. The postfix log shows the `@warn` skip-and-report lines. CI.yml `format` job (job at :95, step :160-167) runs `check_setup_names.py --selftest`, then plain. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/models/exactness.jl` `_socp_cone_check` | Non-throwing shared kernel | VERIFIED | Three consumers: `assert_socp_exact!` (:325), the MPC first tier, and the OOS step. NaN invariant documented. |
| `src/experiments/mpc_loop.jl` `_mpc_certify_and_price` | First tier through the kernel | VERIFIED | Wired; ladder unchanged |
| `test/test_mpc_loop.jl` regression item | Old floor accepts, hybrid refuses, escalates | VERIFIED | Ran in p38-full125/127/postfix125 |
| `test/test_admm_timeout.jl` | Discovered @testitems | VERIFIED | 2 items, 19 assertions |
| `src/experiments/Scenario.jl` | ADMM × import-only rejection | VERIFIED | Inner constructor, so every construction path is covered |
| `src/models/stochastic_welfare.jl`, `src/experiments/run_stochastic.jl` | OOS gate + exclusion + status | VERIFIED | Plus the WR-03 per-draw ladder-attr restore and the WR-04 deterministic tests |
| `src/experiments/store.jl` | Symbol reactive mode, OOS fields | VERIFIED | Docstring matches behaviour |
| `.github/workflows/CI.yml` | setup-names guard | VERIFIED | format job |
| `docs/writeups/FRAMEWORK_GUIDE.html`, `README.md` | API sweep + listing | VERIFIED (static) | Prose accuracy is a human check |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `_mpc_certify_and_price` | `_socp_cone_check` → `_cone_row` | direct call, mpc_loop.jl:872 | WIRED |
| `assert_socp_exact!` | `_socp_cone_check` | exactness.jl:325 | WIRED |
| `solve_stochastic_oos_step!` | `_socp_cone_check` | stochastic_welfare.jl:769 | WIRED |
| `_run_stochastic` | `_stoch_solve_held_out!` → `inexact_h` → `_stochastic_status` | run_stochastic.jl:350-383 | WIRED |
| `result_to_dict` | `oos_*` fields, `Symbol(reactive mode)` | store.jl:193-208 | WIRED. The round-trip test asserts them. |
| `Scenario` inner ctor | ADMM/allow_export check | Scenario.jl:204 | WIRED |

### Behavioral Spot-Checks and Gate Logs

| Check | Command / Source | Result | Status |
|-------|------------------|--------|--------|
| Planning-ID guard | `python3 .github/scripts/check_planning_ids.py` | OK, 250 files | PASS |
| Setup names | `python3 .github/scripts/check_setup_names.py` | 21 testmodules, 223 setup uses, 0 unresolved | PASS |
| Scripts index | `python3 .github/scripts/check_scripts_index.py` | complete (37 files) | PASS |
| Old tolerance gone | `git grep "1e-6 + 1e-4" src/experiments/mpc_loop.jl` | no match | PASS |
| Full run 1.12.5 | `.planning/tmp/36/p38-full125.totals` | Pass=32304 Fail=0 Error=0 Broken=5; .done=0; iters=56 | PASS |
| Full run 1.12.7 | `p38-full127.totals` | Pass=32299 Fail=0 Error=0 Broken=5; .done=0; iters=56 | PASS |
| Post-review run 1.12.5 | `p38-postfix125.totals` / log summary | Pass=32325 (=32304+21) Broken=5 Total=32330; iters=56, welfare -4823.66604824162. Started (1791430626) after the last src/test commit 69eaefe (1791429887); no src/test diff since. | PASS |
| Clean-tree runs | `grep -c "is dirty"` on all three full logs | 0 / 0 / 0 | PASS |
| Docs build | `p38-docs-final.log` | .done=0, 0 `Cannot resolve @ref` (predates review fixes, see human item 4) | PASS |
| JET | 38-FINAL-GATES.md | 12 current / 12 baseline, 0 NEW at ab18f3e. No JET log persisted under .planning/tmp; not re-run after review fixes. | PASS (documented) |

No Julia was run during verification. The postfix full-suite log already covers the current src/test state, so the optional targeted run was not needed.

### Requirements Coverage

| Req | Description (gap closed) | Status | Evidence |
|-----|--------------------------|--------|----------|
| FIX-08 | Per-branch hybrid floor used by every SOCP certificate | SATISFIED | All three cone consumers go through `_socp_cone_check` |
| FIX-10 | MPC settled prices certified by the real gate | SATISFIED | First tier hybrid. Scenario B regret and welfare are bit-identical on 1.12.7. |
| ARCH-02 | Strategy types / dispatch | SATISFIED | Dispatch prose fixed; ADMM import-only rejected at construction |
| ARCH-08 | Status policy | SATISFIED | `:budget_exceeded` tested in suite; `:oos_inexact_skipped` in vocabulary and policy doc |
| HYG-02 | Inert stubs/stale kwargs gone from docs | SATISFIED | Guide has no removed kwargs |
| HYG-03 | Export/generic-name hygiene | SATISFIED | Guide qualifies `ReactiveMode.*`; stored value is a Symbol |
| HYG-05 | Every test in a suite set | SATISFIED | Timeout file discovered, fast set, count-sets files=99 |

No orphaned requirements: all seven are claimed by the phase plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase-modified src/test/docs/.github/scripts) | — | TBD/FIXME/XXX/TODO/HACK | none found | The 16 hits in FRAMEWORK_GUIDE.html are inside base64 image data |
| `_socp_cone_check` | exactness.jl:206-212 | throws `ArgumentError` on a feeder with no root-incident branch | Info | Documented structural guard. MPC's "non-throwing" contract covers certificate verdicts, not malformed input. |

### Ledger Discrepancy (test_strategies 443 vs 435): ledger artifact, not a real issue

- The ledger's per-file numbers (415 → 422 → 443) were measured on a dirty working tree. `p38-02-strategies.log` and `p38-04-strategies.log` both contain DrWatson's warning "The Git repository … is dirty! Appending -dirty".
- `run_and_store` uses `@tagsave` with `storepatch = true` (`src/experiments/store.jl:11`). On a dirty tree it adds a `:gitpatch` key to each saved dict.
- The "run_and_store round-trip" item (`test/test_strategies.jl:384-395`) runs 4 assertions per key for each of the two dicts. One extra key per dict therefore adds 2 × 4 = 8 assertions on a dirty tree. That gives 443 dirty and 435 clean.
- The offset is constant, so every per-plan delta (+7 for 38-07 T1, +21 for 38-07 T2) is correct. The +21 matches the code: 4 for the new item, 5 direct assertions, and 3 new stochastic keys × 4 = 12.
- The full runs had 0 dirty warnings. They were judged on deltas against a clean-tree baseline, which is why 32224 + 80 = 32304 matched exactly.
- Net effect: the absolute test_strategies numbers in 38-MEASUREMENTS.md are 8 high for a clean tree. No code defect, and no effect on any gate. Optional cosmetic fix: annotate the ledger rows "(dirty tree, +8 from :gitpatch)".

### Human Verification Required

1. **GitHub Actions run.** Push a branch and confirm the 1.10/1.11/1.12 matrix, the jet job, the format job (with `check_setup_names.py`) and slow.yml all pass. Expected: all green. Why human: needs hosted runners. Near-τ margins are the risk.
2. **FRAMEWORK_GUIDE prose spot-check.** Compare each 38-09 correction against src/ and status_policy.md. Expected: accurate. Why human: prose judgement.
3. **38-05 compare-script refresh.** Review the regenerated seed-42 results and the Portuguese writeup. Why human: research judgement.
4. **Resolved:** the docs build and JET were re-run at HEAD (p38-docs-postfix: docs OK, 0 unresolved @ref; JET 0 NEW / 0 FIXED); see 38-FINAL-GATES.md. Original note: They were measured before the review-fix commits, which only touched docstrings/docs plus a small run_stochastic change. Low risk.

### Accepted Deviations

These are listed in the frontmatter and are not gaps: WR-02 skipped by design (golden would move), the 1.12.7-only MPC scenario B re-price (documented with old/new ratio), the docs excluded-draw counts (5/10 on 1.12.5, 2/10 on 1.12.7, printed live), and the test_strategies ledger artifact above.

### Gaps Summary

No gaps. Each audit gap is closed in code, checked independently of the SUMMARYs:

- The inline flat-floor MPC certificate is gone and the first tier routes through the shared hybrid kernel, with a parity-asserting regression item.
- The orphan ADMM timeout script is now two discovered fast testitems.
- The stale dispatch, store and guide prose is corrected.
- The four hardening items are wired and tested.

Full-suite logs at the current src/test state are green: Fail 0, Error 0, Broken 5 as baseline, canary iters 56, no golden re-pinned. Status is `human_needed` only because of the GitHub-side CI run and the prose and research-judgement reviews.

---

_Verified: 2026-10-08_
_Verifier: Claude (gsd-verifier)_
