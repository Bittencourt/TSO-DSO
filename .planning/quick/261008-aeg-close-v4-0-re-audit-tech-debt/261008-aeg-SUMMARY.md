---
phase: quick-261008-aeg
plan: 01
status: complete
subsystem: exactness diagnostics, experiment storage, stochastic orchestration
tags: [tech-debt, v4.0-re-audit, exactness, provenance, regression-test]
requires: []
provides:
  - socp_gap_report hybrid-floor default (parity with assert_socp_exact!)
  - persisted MPC status / cert_status_trace and Stochastic run status
  - collated welfare_gap / regret / mpc_status CSV columns
  - non-finite ratio wording in SOCP refusal messages
  - ladder-restore regression test
affects: [src/models/exactness.jl, src/experiments/store.jl, src/experiments/sweep.jl]
tech-stack:
  added: []
  patterns: [shared _cone_row kernel for every cone diagnostic, details carry run status]
key-files:
  created: []
  modified:
    - src/models/exactness.jl
    - src/models/stochastic_welfare.jl
    - src/experiments/run_stochastic.jl
    - src/experiments/strategies.jl
    - src/experiments/store.jl
    - src/experiments/sweep.jl
    - docs/src/status_policy.md
    - test/test_exactness.jl
    - test/test_strategies.jl
    - test/test_run_stochastic.jl
decisions:
  - "socp_gap_report defaults to atol=nothing (hybrid floor via _cone_row); a Real atol is a flat override. scripts/benchmark_ieee8500.jl left on the new default (no test or golden pins its ratios)."
  - "_ratio_phrase also applied to assert_socp_exact!'s own refusal message (finite text byte-identical)."
  - "StochasticDetails keeps a 2-arg constructor deriving status with the run's rule; run() passes r.status explicitly."
metrics:
  duration: ~3h10m (incl. 30 min full suite)
  completed: 2026-10-08
---

# Quick 261008-aeg: Close v4.0 Re-audit Tech Debt (A-E) Summary

`socp_gap_report` now uses the same hybrid floor as the gate. MPC and Stochastic run statuses are
stored in the JLD2 and the collated CSV. NaN ratios read as "non-finite" instead of "NaN > 1".
The status_policy preamble is reworded. A test now fails if the per-draw ladder restore is
removed.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 9631fe9 | fix: socp_gap_report hybrid floor, NaN refusal text, status_policy wording |
| 2 | b59947f | feat: persist MPC and Stochastic run status in stored results |
| 3 | ec1403e | test: regression test for the per-draw solver-ladder restore |

## What changed

- **A (gap-report parity):** `socp_gap_report(ctx; atol = nothing, ε, τ_solver)` computes every
  row through `_cone_row`, so for the same kwargs its `ratio` equals `hybrid_ratios` and its max
  equals `_socp_cone_check().maxratio`. A Real `atol` reproduces the old flat formula. It throws
  `ArgumentError` on a feeder with no root-incident branch. Callers: only
  `scripts/benchmark_ieee8500.jl`, which stays on the new default because no test or golden reads
  its ratios. The regenerated `socp_gap_report.csv` ratios would differ, but that is a committed
  diagnostic artifact and was not regenerated.
- **B (status persistence):** `StochasticDetails.status::Symbol`, set by `run(::Stochastic)`
  from `r.status`. `result_to_dict` stores `:mpc_status`, `:mpc_cert_status_trace`
  (`Vector{Symbol}`) and `:oos_status = det.status`. `collate_summary` keeps
  `:welfare_gap, :regret, :mpc_status` after `:final_s` and before `:oos_inexact_draws`.
- **C (docs):** in the status_policy.md "Breaking changes" preamble, "Everything below fails
  loudly" becomes "Most entries raise an error; the MPC first-tier certificate re-prices with a
  `@warn` and can change `status`". Bullets are unchanged.
- **D (NaN text):** `_ratio_phrase(r)` is used in the held-out `CertificateError`, the
  `run_stochastic` skip `@warn` and `assert_socp_exact!`'s refusal.
- **E (ladder restore):** a new item mutates one exposed ladder attribute to a 10x sentinel after
  each draw and asserts that every draw starts at the as-built value.

## Verification

Per-file targeted runs (`+release` = 1.12.5, sequential):

| File | Items | Pass | Fail/Error |
|------|-------|------|------------|
| test_exactness.jl | 8 | 43 | 0 |
| test_stochastic_oos_harness.jl | 6 | 23 | 0 |
| test_exports.jl | 1 | 14 | 0 |
| test_strategies.jl | 29 | 476 | 0 |
| test_experiments.jl | 17 | 109 | 0 |
| test_run_stochastic.jl | 7 | 48 | 0 |

- **Mutation check (Task 3):** commenting out `_restore_ladder_attrs!` makes the new item fail
  2 of 6 assertions: `all(==(baseline), seen)`, and `r.status === :solved` becomes
  `:oos_inexact_skipped`. After restoring the line, `git diff` on the file is empty. The mutation
  was not committed.
- **count-sets --strict:** all=522, fast=484, slow=38, files=99, canary=1, outside=0, so
  `expected_broken.txt` is unchanged.
- **JET (`+1.12` = 1.12.7):** 12 current, 12 baseline, **0 NEW**, 0 FIXED.
- **Full suite (one detached run, label `aeg`, Julia 1.12.5, launched after ec1403e, 30 min):**
  **32379 pass / 0 fail / 0 error / 5 broken**. `check_suite_log.py aeg --broken 5` reports
  suite OK. Canary iters = 56, welfare = -4823.66604824162 (unchanged). No golden was touched.

### Pass delta itemization (+54 = 32379 - 32325)

| Source | +Pass |
|--------|-------|
| test_exactness: new "socp_gap_report uses the gate's hybrid floor..." | +9 |
| test_exactness: new "refusal ratio text names a NaN ratio as non-finite..." | +6 |
| test_strategies: "run(Stochastic) common shape" (+details.status check) | +1 |
| test_strategies: "run_and_store round-trip" explicit status/trace asserts | +7 |
| test_strategies: "run_and_store round-trip" per-key loop (2 new MPC keys x 4 asserts) | +8 |
| test_strategies: "run_and_store round-trip" collate block | +11 |
| test_strategies: new "stored Stochastic status is the run's own..." | +6 |
| test_run_stochastic: new "each held-out draw starts from the as-built solver ladder" | +6 |
| **Total** | **+54** |

The full suite exactly matches the predicted delta, with no unexplained change.

## Deviations from Plan

1. **[Rule 2 - consistency] `_ratio_phrase` also used in `assert_socp_exact!`.** The plan named
   two messages; the gate's own refusal had the same "NaN > 1" wording. Finite-ratio text is
   byte-identical, and the existing substring assert still passes. Commit 9631fe9.
2. **Content-loss check semantics.** `check_content_loss.py HEAD` lists every intentionally
   edited .jl file, since it compares against HEAD. To prove the formatter itself lost nothing,
   each format run was bracketed by a pre/post-format normalized comparison in the scratchpad.
   All runs showed whitespace/commas only. After the last commit, `check_content_loss.py HEAD`
   reports OK.
3. **Collated-header expectations:** no existing test asserted the column list, so nothing was
   extended. The new collate assertions live in the round-trip item.

No goldens, canary values or `expected_broken.txt` changed. No planning IDs appear in
src/test/docs.

## Known Stubs

None.

## Self-Check: PASSED

- Commits 9631fe9, b59947f, ec1403e exist on main.
- All modified files listed above exist; suite log `.planning/tmp/36/aeg.log` (gitignored)
  records the totals.
