---
phase: quick-261008-aeg
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/models/exactness.jl
  - src/experiments/strategies.jl
  - src/experiments/run_stochastic.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - src/models/stochastic_welfare.jl
  - docs/src/status_policy.md
  - test/test_run_stochastic.jl
  - test/test_strategies.jl
  - test/test_exactness.jl
autonomous: true
requirements: [W-A, W-B, W-C, W-D, W-E]
must_haves:
  truths:
    - "socp_gap_report with no atol uses the same per-branch hybrid floor as assert_socp_exact!; an explicit atol still works"
    - "A saved MPC run records its status and cert_status_trace (Symbols); a saved Stochastic run records the run's own status, not a recomputation"
    - "collate_summary CSV carries welfare_gap, regret and the MPC status"
    - "status_policy.md no longer claims every breaking change fails loudly"
    - "A NaN cone ratio reads as a non-finite ratio in the OOS refusal text, never 'NaN > 1'"
    - "Deleting the per-draw ladder restore in _run_stochastic makes a test fail"
  artifacts:
    - {path: src/models/exactness.jl, provides: "socp_gap_report hybrid default"}
    - {path: src/experiments/store.jl, provides: "status persistence"}
    - {path: test/test_run_stochastic.jl, provides: "ladder-restore regression"}
  key_links:
    - {from: src/models/exactness.jl, to: "_cone_row", via: "socp_gap_report atol=nothing path", pattern: "_cone_row"}
    - {from: src/experiments/store.jl, to: "StochasticDetails.status", via: "result_to_dict", pattern: "det.status"}
---

<objective>
Close the v4.0 re-audit tech-debt warnings A-E: gap-report floor parity, run-status persistence,
status_policy wording, NaN refusal message, and a ladder-restore regression test.

Output: edits to the files above, tests, one commit per task, then one full-suite run.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/v4.0-MILESTONE-AUDIT.md
@.planning/phases/38-close-v4-0-audit-gaps/38-REVIEW.md
@src/models/exactness.jl
@src/experiments/strategies.jl
@src/experiments/store.jl
@src/experiments/sweep.jl
@src/experiments/run_stochastic.jl

<interfaces>
exactness.jl: `_cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)` returns `(; lhs, rhs, gap, atol_b, ratio)`; `atol === nothing` selects `max(τ_solver, ε*ref_b)`. `_socp_head_branch(feeder)` returns head branch index or nothing. Constants `MEASURED_REL_TOL_EXACT`, `TAU_SOLVER_EXACT`. `socp_gap_report(ctx; topn=20, rtol=1e-4, atol=1e-6)` currently computes lhs/rhs/gap and `tol = atol + rtol*max(...)` itself and builds `ratio = gap/tol`.
strategies.jl: `struct MPCDetails(regret, steps, day_ahead_welfare, forecast_settled_welfare, realized_welfare, raw::NamedTuple)`; `raw.status` (Symbol) and `raw.trace.cert_status_trace` (Vector{Symbol}) already exist. `struct StochasticDetails(in_sample::NamedTuple, oos::NamedTuple)`.
run_stochastic.jl: `_run_stochastic` returns NamedTuple with `.in_sample`, `.oos`, `.status`; `run(::Stochastic, s)` builds `StochasticDetails(r.in_sample, r.oos)` and drops `r.status`. `_stochastic_status(infeasible_h, inexact_h)`. Test hook kwarg `solve_held_out!` (called as `(h_oos, h)` returning `(welfare, infeasible, inexact)`); `ladder_baseline = _snapshot_ladder_attrs(h_oos.model)` at ~305 and `_restore_ladder_attrs!(h_oos.model, ladder_baseline)` at ~349 immediately before `solve_held_out!`. `LADDER_ATTR_NAMES` (src/admm/DsoOpt.jl) lists the Clarabel attributes; `get_optimizer_attribute`/`set_optimizer_attribute` access them.
</interfaces>
</context>

<hard_rules>
- Never re-pin goldens or the knife-edge canary (iters=56, welfare=-4823.66604824162). If a test value changes, keep the test's explicit atol or stop and document; never silently update a pinned literal.
- Never run two Julia processes concurrently (run commands strictly sequentially; no background Julia while another runs).
- No scratch .jl containing @testitem inside the repo; scratch only in /tmp/claude-1000/-home-pedro-programming-TSO-DSO/eacd2838-0d94-4eaa-90a7-d7a03a66f0df/scratchpad.
- No planning IDs (W-A..W-E, WR-xx, 38-xx, "Phase 38", D-xx) in src/test/scripts/docs/CI text. Check: `python3 .github/scripts/check_planning_ids.py`.
- Before each commit: run the formatter (find the exact invocation: `ls scripts/ | grep -i format`, expected `julia +release scripts/format210.jl`), then `python3 .github/scripts/check_content_loss.py HEAD`.
- Targeted tests: `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<x>.jl`. After targeted runs also run with `--count-sets --strict`; update test/expected_broken.txt only if the strict count requires it.
- Test-item gotcha: no `try x = ...` or for-loop reassignment of outer variables at @testitem top level; wrap in a function.
- Commit messages end with: Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
</hard_rules>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Gap-report floor parity, status_policy wording, NaN refusal text</name>
  <files>src/models/exactness.jl, docs/src/status_policy.md, src/models/stochastic_welfare.jl, src/experiments/run_stochastic.jl, test/test_exactness.jl</files>
  <behavior>
    - socp_gap_report(ctx) (no atol) rows have `ratio` equal to the matching `hybrid_ratios(ctx)` row ratio for the same (b,t)
    - socp_gap_report(ctx; atol=1e-6) reproduces the old flat-floor ratio (explicit override unchanged)
    - Refusal message with a NaN ratio contains "non-finite" and not "NaN >"; a finite ratio keeps "ratio > 1" wording
  </behavior>
  <action>
(A) First grep every test/script referencing `socp_gap_report` (`grep -rn socp_gap_report test scripts docs src`); currently test/test_exports.jl only checks the export and scripts/benchmark_ieee8500.jl:~1286 calls it. Record whether any asserted value depends on the default floor. Change the signature to `atol::Union{Nothing,Real} = nothing` and add `ε = MEASURED_REL_TOL_EXACT`, `τ_solver = TAU_SOLVER_EXACT` kwargs (same defaults as `_socp_cone_check`). Compute `head_b = _socp_head_branch(feeder)` (throw the same ArgumentError as hybrid_ratios if nothing) and obtain lhs/rhs/gap/ratio per row from `_cone_row` (never re-implement the formula), keeping the row NamedTuple fields and the sort/topn behaviour unchanged. Rewrite the docstring: remove the flat `1e-6` claim; state that `atol=nothing` uses the hybrid floor `max(τ_solver, ε·ref_b)` identical to `assert_socp_exact!`, that a Real `atol` is a flat override, and that `ratio > 1` is exactly what would have thrown for the same kwargs. If the benchmark script relied on the flat default, pass `atol = 1e-6` explicitly there ONLY if its reported numbers are pinned anywhere; otherwise leave it on the new default and say so in the commit body. Add a testitem in test/test_exactness.jl (use an existing fixture/setup in that file for building a solved ConvexBranchFlow ctx) asserting the behaviours above.

(C) In docs/src/status_policy.md section "Breaking changes" (~131-132) reword the preamble so it no longer says everything fails loudly: say most entries below raise an error, while the MPC first-tier certificate change instead re-prices with a `@warn` and can change `status`. Do not edit the bullets' technical content.

(D) Both refusal messages (src/models/stochastic_welfare.jl ~776-778 `solve_stochastic_oos_step!` CertificateError text, and src/experiments/run_stochastic.jl ~86-89 `@warn`) interpolate the ratio next to "> 1". Introduce one small internal helper (e.g. `_ratio_phrase(r)` in exactness.jl or next to stochastic_welfare.jl, defined before use) returning "gap/(atol_b+rtol·|cone|)=<r> > 1" when `isfinite(r)` else "gap/(atol_b+rtol·|cone|) is non-finite (NaN cone value)". Use it in both messages, keeping the `kind = :socp_exact` and all other text intact. Existing tests that match on the message text must still pass; update only message-substring asserts if they contain "NaN > 1", and add one assertion for the NaN path (a harness test that already forces NaN is preferred; else unit-test the helper directly).
  </action>
  <verify>
    <automated>JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_exactness.jl</automated>
  </verify>
  <done>Hybrid default in socp_gap_report with explicit-atol override working and new test green; docs preamble reworded; NaN message reads clearly; test_stochastic_oos_harness.jl and test_exports.jl still pass (run each targeted, sequentially); formatter, check_content_loss and check_planning_ids clean; committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Persist MPC and Stochastic run status through result_to_dict and collate_summary</name>
  <files>src/experiments/strategies.jl, src/experiments/run_stochastic.jl, src/experiments/store.jl, src/experiments/sweep.jl, test/test_strategies.jl</files>
  <behavior>
    - run(Stochastic) result: details carry the run's own status (equals `_run_stochastic(...).status`)
    - result_to_dict for MPC includes :mpc_status (Symbol) and :mpc_cert_status_trace (Vector{Symbol}); for Stochastic :oos_status equals the stored run status
    - collate_summary CSV includes columns welfare_gap, regret, mpc_status for a mixed sweep (missing for non-applicable rows), deterministic across two calls
  </behavior>
  <action>
(B) strategies.jl: add a `status::Symbol` field to `StochasticDetails` and update its docstring; keep a 2-argument outer constructor `StochasticDetails(in_sample, oos)` that derives status via `_stochastic_status(oos.infeasible_h, oos.inexact_h)` so existing test/doc call sites compile (grep all constructions in src/test/scripts/docs first; define `_stochastic_status` access order so the outer constructor works at call time, it lives in run_stochastic.jl). In `run(::Stochastic, s)` pass `r.status` explicitly. In store.jl `result_to_dict`: for `MPCDetails` store `d[:mpc_status] = det.raw.status` and `d[:mpc_cert_status_trace] = Symbol.(det.raw.trace.cert_status_trace)` (Vector{Symbol}); for `StochasticDetails` store `d[:oos_status] = det.status` (no recompute). Update the result_to_dict docstring to list the new keys. In sweep.jl add `:welfare_gap`, `:regret`, `:mpc_status` to `keep` (place after `:exact_maxgap`/before `:oos_inexact_draws` keeping RULE 1 fixed order; `:mpc_cert_status_trace` is NOT a CSV column, like `:stoch_probabilities`) and update the collate docstring. Check how collect_results handles keys absent from some rows and mirror existing handling for `:oos_*`. Grep tests that assert the collated CSV header/column list and extend those expectations to the new columns; do not alter any numeric golden. Add tests to test/test_strategies.jl (or the existing store/sweep test file that already runs a small MPC and Stochastic scenario; reuse its fixtures and sizes, e.g. the T=9 ieee13 Stochastic(S=3,H_oos=5) used in test_run_stochastic.jl) covering the behaviors above, including an inexact-skipped Stochastic case via the `solve_held_out!` hook if feasible through `_run_stochastic`, asserting stored `:oos_status` equals the run status.
  </action>
  <verify>
    <automated>JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_strategies.jl</automated>
  </verify>
  <done>New keys persisted, columns collated, tests green; also run targeted files containing result_to_dict/collate_summary/StochasticDetails tests (grep), sequentially; JLD2 dict still primitives-only; formatter/content-loss/planning-ids clean; committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Regression test for the per-draw solver-ladder restore</name>
  <files>test/test_run_stochastic.jl</files>
  <behavior>
    - A wrapper around solve_held_out! mutates one ladder attribute on draw 1's model after the real solve; the wrapper records the attribute value it SEES at the start of draw 2; it equals the as-built baseline
    - With the restore line removed (mutation check), the same test fails
  </behavior>
  <action>
(E) Add a @testitem to test/test_run_stochastic.jl (tags [:run_stochastic], setup [StochasticFixtures], same scenario as the neighbouring items) using the `solve_held_out!` hook. The wrapper: on each call record `get_optimizer_attribute(h_oos.model, name)` for one name from `TSODSO.LADDER_ATTR_NAMES` (pick the first one the backend exposes; skip with a clear @test on the recorded baseline being non-missing), then delegate to `TSODSO._stoch_solve_held_out!`, then set that attribute to a clearly different sentinel value (e.g. 10x baseline for a numeric attribute) via `set_optimizer_attribute`. Record into a Vector captured by the closure (mutate with push!, never reassign outer variables). Run `TSODSO._run_stochastic(s, s.strategy; solve_held_out! = wrapper)` and assert every recorded start-of-draw value equals draw 1's recorded value (the as-built baseline) and that the sentinel differs from it (so the test is non-vacuous). Run the test; then perform the mutation check manually: temporarily comment out the `_restore_ladder_attrs!` line at run_stochastic.jl ~349, rerun the targeted file and confirm the new item FAILS, then restore the line (`git diff src/experiments/run_stochastic.jl` must show no leftover change from this step). Do not commit the mutation. Keep the testitem free of top-level try/reassignment (wrap helpers in functions).
  </action>
  <verify>
    <automated>JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_run_stochastic.jl</automated>
  </verify>
  <done>New item passes with the restore present and fails with it deleted (mutation observed, then reverted); formatter/content-loss/planning-ids clean; committed.</done>
</task>

</tasks>

<verification>
Run strictly sequentially, after the last src/test commit:
1. `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" --count-sets --strict`; update test/expected_broken.txt only if required.
2. `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. scripts/jet_check.jl` expect 0 NEW.
3. Full suite on 1.12.5 (once): `TSODSO_TEST_SET=all .github/scripts/suite_detached.sh aeg julia +release --project=. -t2 -e 'import Pkg; Pkg.test()'`, then `python3 .github/scripts/check_suite_log.py aeg --broken 5`. Baseline Pass 32325, 0 fail, 0 error, Broken 5; Pass must equal baseline plus the added tests, and each delta must be itemized (per new testitem: its assertion count) in the SUMMARY. Confirm `julia +release` is 1.12.5 (`julia +release --version`). Canary (iters=56, welfare=-4823.66604824162) and all goldens unchanged.
4. `python3 .github/scripts/check_planning_ids.py` and `python3 .github/scripts/check_content_loss.py HEAD`.
</verification>

<success_criteria>
All five debts closed with tests; full suite at baseline plus itemized new passes, 0 fail/error, Broken 5; JET 0 NEW; no goldens/canary touched; three commits with the required co-author trailer.
</success_criteria>

<output>
Create `.planning/quick/261008-aeg-close-v4-0-re-audit-tech-debt/261008-aeg-SUMMARY.md` when done
</output>
