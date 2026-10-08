# Phase 38 Final Gates (plan 38-10)

Static gates run at HEAD ab18f3e (plans 38-01..09 complete), clean tree. Pre-flight: `pgrep -af julia` empty
(only the earlyoom daemon and the probing shell), `git worktree list` has no `.claude/worktrees/agent-*`
entry (the two sibling worktrees live under `../TSO-DSO.worktrees/`, outside the repo), no untracked `.jl`
files. The only ignored `.jl` under `.planning/tmp` that mentions `@testitem` is
`.planning/tmp/37/check_tag_only_diff.jl`, as a string literal `Symbol("@testitem")`, not a macro call;
discovery is rooted at `test/` and count-sets reports `outside=0`. Toolchain: `julia +release` = 1.12.5,
`julia +1.12` = 1.12.7.

Sequential runs, never concurrent (`pgrep -x julia` empty before each launch, clean tree each time):
static gates and JET at ab18f3e, then `p38-full125` at 958cc98, then `p38-full127` and `p38-docs-final`
at 806c4cd. Each log was validated by `check_suite_log.py` (`suite OK` / `docs OK`) before the next
commit; the verifies after a commit read the `.done` / `.totals` / `.log` files.

## Full runs

| Run | Command | Pass | Fail | Error | Broken | Total | check_suite_log |
|---|---|---:|---:|---:|---:|---:|---|
| p38-full125 | `TSODSO_TEST_SET=all TSODSO_TEST_VERBOSE=1`, `julia +release` (1.12.5), `--broken 5` | 32304 | 0 | 0 | 5 | 32309 | `suite OK` |
| p38-full127 | `TSODSO_TEST_SET=all`, `julia +1.12` (1.12.7), `--broken 5` | 32299 | 0 | 0 | 5 | 32304 | `suite OK` |
| p38-docs-final | `julia +release --project=docs docs/make.jl`, `--mode docs` | — | — | — | — | — | `docs OK`, exit 0, 0 `Cannot resolve @ref` |

Canary: `iters = 56` in both runs; welfare `-4823.66604824162` (1.12.5) and `-4823.666048218671`
(1.12.7, 4.8e-12 relative to the golden, inside the 1e-9 check; same printed value as Phase 37's
1.12.7 run). `escalations = 0` in both. `soft scope is ambiguous`: 0 in both.

EXPECTED_COUNT_SETS=count-sets: all=517 fast=480 slow=37 files=99 canary=1 outside=0

The expected line is the ledger's running total (38-MEASUREMENTS.md, 38-07 T2 row): baseline
all=511 fast=474 slow=37 files=98, then +1 (38-02 MPC regression item), +1 (38-04 OOS inexact-refusal item),
+2 items and +1 file (38-06 `test_admm_timeout.jl`), +2 (38-07 ADMM import-only rejection, stored Symbol
reactive mode). All additions are fast items.

## Static and hygiene gates

| Gate | Command | Result |
|---|---|---|
| Formatter | `julia --startup-file=no .github/scripts/format210.jl src ext test docs` (JuliaFormatter 2.10.2) | no changes; `git status --porcelain` empty |
| Content loss | `python3 .github/scripts/check_content_loss.py HEAD` | `OK: no content change` (219 tracked .jl files) |
| Planning-ID guard | `check_planning_ids.py` / `--selftest` | OK, 250 files / selftest OK (42 positive, 24 negative, 10 fail-closed) |
| Scripts index | `check_scripts_index.py` / `--selftest` | complete (37 tracked files) / selftest OK |
| Setup names | `check_setup_names.py --selftest` / plain | selftest OK (4 cases) / 21 testmodules, 222 setup uses, 0 unresolved |
| Script API | `julia +release --project=. --startup-file=no .github/scripts/check_script_api.jl` / `--selftest` | `OK: 40 files checked` / selftest OK (55 cases) |
| Runner selftest | `run_tests_filtered.jl "$PWD" --selftest` (1.12.5) | selftest OK (probe item Broken 2 by design) |
| count-sets | `run_tests_filtered.jl "$PWD" --count-sets --strict` (1.12.5) | `count-sets: all=517 fast=480 slow=37 files=99 canary=1 outside=0`, exit 0; equals `EXPECTED_COUNT_SETS` |
| JET 1.12.7 | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl` / `--selftest` | `12 current, 12 baseline, 0 NEW, 0 FIXED`, exit 0 / selftest OK (`scripts/jet_baseline.txt` not touched in Phase 38) |
| Workflows | `yaml.safe_load` of CI.yml and slow.yml | both parse; CI.yml format job runs `check_setup_names.py --selftest` and plain (lines 166-167) |
| tmp / Manifest | `git ls-files .planning/tmp Manifest.toml` | empty |
| src diff | `git diff --shortstat 4ab43d6 HEAD -- src` | 9 files, 314+/156-: shared cone-check kernel (exactness.jl), MPC first tier (mpc_loop.jl), OOS gate (stochastic_welfare.jl, run_stochastic.jl), ADMM import-only rejection (Scenario.jl, sweep.jl), Symbol reactive mode (store.jl), prose (TSODSO.jl), status vocabulary `:oos_inexact_skipped` (errors.jl). No canary or golden value edited |

## Cross-version checks

Copied from 38-MEASUREMENTS.md. Both measured locally on 1.10.11 and 1.11.9 with the committed code and
unmodified `Manifest-v1.10.toml` / `Manifest-v1.11.toml`, scratch scripts only.

- MPC (plan 38-02): regression point unperturbed `:certified_convex_dual` (ratio 0.0114); with the 5e-7
  slack, old flat ratio 0.4993, hybrid ratio = `cone_maxratio` = 2.4571 (exact equality), cert status
  `:certified_convex_dual_restricted` with 3 finite prices; happy-path scenario A `:certified` with
  7 x `:certified_convex_dual`, worst hybrid ratio 0.9383 (t=4). Identical on 1.10 and 1.11. Every
  assertion of the new item holds.
- Stochastic (plan 38-04): CI golden `:solved`, no draw inexact or infeasible, max ratio 0.3660,
  `welfare_gap` -0.018591711034105174 (rel. diff 0 against the pin); pin-binding fixture at the default
  optimizer throws `CertificateError` (`:socp_exact`, ratio 51.23); tightened-optimizer harness fixtures
  (build-once 0.0119/0.4964/0.0088, pin-binding 0.3889/0.3538, FourQuadBESS q pin 0.0370, infeasible ->
  recover `(NaN, true, false)` then ratio 0.0778); FourQuadBESS at the default optimizer 0.3729. Identical
  on 1.10 and 1.11. Every new assertion holds.

Nothing was recorded as "not measurable locally", so no cross-version item is a CI risk beyond the
Actions run itself (see MANUAL).

## Full run, Julia 1.12.5

Launched at HEAD 958cc98 (Task 1 commit), clean tree, no other Julia process:
`TSODSO_TEST_SET=all TSODSO_TEST_VERBOSE=1 .github/scripts/suite_detached.sh p38-full125 julia +release --project=. -t2 -e 'import Pkg; Pkg.test()'`.
`.start` 1791423708 > HEAD commit time 1791423696 (not stale). `.done` = 0. Wall time 28m20s.
`python3 .github/scripts/check_suite_log.py p38-full125 --broken 5` printed `suite OK` before any later
commit; `.totals`: `Pass=32304 Fail=0 Error=0 Broken=5 Total=32309`.

Canary @info block: `iters = 56`, `welfare = -4823.66604824162`, `escalations = 0`.
`grep -c 'soft scope is ambiguous'` = 0.

EXPECTED_PASS_1125=32304

### Pass arithmetic, 1.12.5

| plan | file(s) | items | Pass delta | what |
|---|---|---:|---:|---|
| baseline | — | 511 | 32224 | Phase 37 verified run on 1.12.5 (37-VERIFICATION.md: 32223 at plan 37-13 + 1 for `@test isempty(dead)` in the `guards` testset, review fix IN-02) |
| 38-01 | test/test_exactness.jl | +0 | +8 | kernel parity assertions inside 2 existing items (20 -> 28) |
| 38-02 | test/test_mpc_loop.jl | +1 | +7 | hybrid-floor regression + parity item (369 -> 376) |
| 38-04 | test_stochastic_oos_harness.jl, test_run_stochastic.jl, test_status_policy.jl | +1 | +18 | inexact-refusal item (+7), run_stochastic 3-tuple flags / recovery ratio / masks (+7), `_stochastic_status` 2-mask cases (+4) (56 -> 74) |
| 38-06 | test/test_admm_timeout.jl | +2 | +19 | plain script converted to 2 fast `:admm` items (12 budget + 7 convergence assertions; 0 -> 19) |
| 38-07 T1 | test/test_strategies.jl | +1 | +7 | ADMM x `allow_export = false` rejection, no solve (415 -> 422) |
| 38-07 T2 | test/test_strategies.jl | +1 | +21 | stored Symbol reactive mode item (+4), run_and_store round-trip extension (+5 direct, +12 `is_prim` loop) (422 -> 443) |
| **total** | | **+6 -> 517** | **+80** | 32224 + 80 = **32304** |

Observed 32304, delta 0: every unit is accounted for by the ledger. Plans 38-03, 38-05, 38-08 and 38-09
changed no assertion (comment edits in test/fixtures_mpc.jl and test/test_ac_oracle.jl only; docs,
scripts, writeups). Broken 5 = baseline. Total 32309 = 32304 + 5.

### Log observations, 1.12.5

- `run_mpc: per-resolve cone check failed` warnings: **7** (Phase 37 run: 6). Six come from the high-PV
  `pv_scale = 3.0` forced-inexact fixtures (forced-inexact, escalation at t > 1, ladder terminal
  failure x3), now reporting the hybrid-floor ratio 9177.66 / 9172.54 instead of the old flat-floor
  9156.55 / 9166.37 (same as the ledger's High-PV row; the verdict is unchanged). The seventh is the new
  38-02 regression item (t = 1, `cone_maxratio = 2.457082735245664`, `:certified_convex_dual_restricted`),
  which escalates by design. No happy-path MPC item escalates (scenario A's worst ratio is 0.938 on this
  patch). `EVERY escalation tier failed` warnings: 3, same as Phase 37.
- `admm_timeout` items: `TSODSO_TEST_VERBOSE=1` printed only the outer `TSODSO` totals row (no per-item
  rows), so the run has no in-suite per-item timing. 38-06 measured the file at 55.4 s isolated cold
  (including compile) and about 13 s warm in-suite, under the 30 s `:slow` threshold; the items stay fast.
  No code change.

## Full run, Julia 1.12.7

Launched at HEAD 806c4cd (Task 2 commit) after p38-full125 had finished, clean tree, no other Julia
process: `TSODSO_TEST_SET=all .github/scripts/suite_detached.sh p38-full127 julia +1.12 --project=. -t2 -e 'import Pkg; Pkg.test()'`.
`.start` 1791425508 > HEAD commit time 1791425505. `.done` = 0. Wall time 28m17s.
`check_suite_log.py p38-full127 --broken 5` printed `suite OK`; `.totals`:
`Pass=32299 Fail=0 Error=0 Broken=5 Total=32304`.

EXPECTED_PASS_1127=32299

### Pass arithmetic, 1.12.7

32219 (Phase 37 verified 1.12.7 baseline; 5 below 1.12.5 because of the gated `fit_baseline` FIT item,
see 37-FINAL-GATES.md) + 80 (the same per-plan deltas as on 1.12.5: 8 + 7 + 18 + 19 + 7 + 21) =
**32299**. Observed 32299, delta 0. The 1.12.5 / 1.12.7 difference stays at 5, as in Phase 37. The 1.12.7
MPC verdict flip (below) moves no asserted value, so it changes no count.

### Log observations, 1.12.7

`run_mpc: per-resolve cone check failed` warnings: **10** (Phase 37 1.12.7 run: 6) = 6 high-PV
forced-inexact fixtures (ratios 9177.66 / 9172.54, as on 1.12.5) + 1 new regression item (t = 1, ratio
2.4566478055472456) + **3 x scenario B** (t = 4, `cone_maxratio = 1.1652607234868668`), one per test item
that runs the shortfall fixture (forced-PV-shortfall, "A6 call site", "AC truth settlement REPORTS").
That is exactly the flip 38-02 predicted (ledger: 1.165, b = 6, τ = 3). `EVERY escalation tier failed`: 3,
unchanged.

## Docs build

`.github/scripts/suite_detached.sh p38-docs-final julia +release --project=docs docs/make.jl`, launched
after p38-full127 had finished. `.done` = 0; `check_suite_log.py p38-docs-final --mode docs` -> `docs OK`;
`grep -c 'Cannot resolve @ref'` = 0. Remaining warnings are benign and pre-existing: PlotUtils "No strict
ticks found" (x2), the navbar repo URL, the api.md and search-index size thresholds, and the 18 @example
blocks rendered through PNG fallbacks. All literate pages executed.

Stochastic page (`generated/stochastic_pv_demand.html`, live on 1.12.5):
`(held_out = 10, excluded_inexact = 5, excluded_infeasible = 0, usable = 5, status = :oos_inexact_skipped)`,
worst held-out hybrid ratio 1.633837830641987, `in_sample.welfare` -538.8159626451336,
`oos.realized_welfare` -538.7830306825808. Matches the 38-04 prediction and the 38-05 live run exactly.
The docs build runs on 1.12.5; on 1.12.7 the page would report 2/10 excluded (38-04 prediction, gap
0.025993), which the page prints live rather than stating in prose.

## Explained moves

- **MPC, 1.12.7, scenario B** (`mpc_loop_fix10_shortfall`, `MPC(H = 3, step = 1, terminal_soc = true,
  forecast_error = 0.3)`, seed 1), t = 4: the old flat floor accepted the first-tier ratio 0.233. The hybrid
  floor gives 1.165 (2.333e-7 cone residual on interior branch b = 6, atol_b = τ_solver = 2e-7), so the
  resolve escalates to `:certified_convex_dual_restricted`, the run status becomes `:degraded`, and
  `dadp_trace[4]` goes 0.008895250684296654 -> 0.008894113604359186. Dispatch, regret
  (-0.0469747761931103) and both welfare figures are bit-identical, and no test asserts status, the
  certificate trace or the DADP for this fixture. Confirmed in the run log (3 warnings at t = 4, ratio
  1.16526). On 1.12.5 nothing moves (0.157 -> 0.771). The happy-path fixture never escalates (worst 0.938 on
  1.12.5, 6.6 % margin; 0.323 on 1.12.7). τ was not raised.
- **MPC high-PV fixtures**: the logged ratio moves 9156.55 -> 9177.66 (t = 1) and 9166.37 -> 9172.54
  (t = 4) because of the hybrid arithmetic. The verdict is the same (the rtol term dominates), and the
  tests and fixture comments now say "≈ 9.2×10³".
- **Stochastic docs page**: 5/10 held-out draws excluded as inexact on 1.12.5 (2/10 predicted on 1.12.7),
  status `:oos_inexact_skipped`, `welfare_gap` 0.016867421597680732 -> 0.03293196255276598. The page
  reports the counts live and draws excluded draws as hollow markers. Refused draws have cone violations of
  2.05-3.88e-7, just above τ_solver = 2e-7.
- **compare_default_stochastic (seed 42)**: the gate refuses 0/10 draws (`:solved`), and the published
  `welfare_gap` -0.0323948881649585 equals the pre-gate value. The tracked results and the Portuguese
  writeup were re-generated because they predated the v4.0 modeling fixes (2026-09-08 artifact). That stale
  artifact, not the gate, accounts for the moved numbers (38-05).
- **CI stochastic golden** `T=9, Stochastic(S=3, H_oos=5)`: unchanged. The gate refuses 0/5 draws on both
  patches (worst 0.366 / 0.350), status `:solved`, `welfare_gap` -0.018591711034105174 (pin rtol 1e-4,
  passes on both patches).
- **Knife-edge canary**: unchanged (iters 56, welfare -4823.66604824162 on 1.12.5, 4.8e-12 relative on
  1.12.7). Not re-pinned; no golden was re-pinned in this phase.

## Success-criterion mapping

1. **MPC first tier on the shared arithmetic.** `_mpc_certify_and_price` calls the shared non-throwing
   kernel `_socp_cone_check` (38-01, 38-02), which `assert_socp_exact!` also uses (+8 parity assertions).
   The regression item (high-PV `pv_scale = 1.2` window, `l[2,1] ≥ l* + 5e-7`: old flat 0.499 certifies, hybrid
   2.457 escalates to the restricted tier) passes on 1.12.5 and 1.12.7 and was measured on 1.10/1.11. The
   canary is unchanged. The only moved MPC value (1.12.7 scenario B, `dadp_trace[4]`) is documented above
   and in 38-MEASUREMENTS.md with its old and new ratios.
2. **ADMM timeout test in the suite.** `test/test_admm_timeout.jl` is two fast `:admm` items (19 Pass;
   `:budget_exceeded` with no price fields, maxiter cap throws `ConvergenceError`, unbudgeted run
   converges). Count-sets went to files=99, all=517, and both full runs include it. It stays fast
   (about 13 s warm < 30 s).
3. **Stale prose corrected.** The dispatch notes in `src/TSODSO.jl` and the two literate pages (38-03);
   the `store.jl` docstring, which now matches the stored Symbol (38-07); `FRAMEWORK_GUIDE.html` swept against
   the current API, with planning IDs removed and the guide listed in the writeups README (38-08), and false model
   statements corrected (38-09). `check_planning_ids.py` OK on 250 files, `check_script_api.jl` OK.
   Accuracy of the prose is a manual spot-check (38-VALIDATION Manual-Only).
4. **Hardening.** `Scenario(strategy = ADMM(), allow_export = false)` throws `ArgumentError` at
   construction (38-07, +7). `solve_stochastic_oos_step!` runs the shared gate and throws
   `CertificateError`; `run_stochastic` excludes and reports the draw (`inexact_h`, `:oos_inexact_skipped`,
   status vocabulary and status_policy.md updated; 38-04/05, +18). `check_setup_names.py`
   (`--selftest` + plain) runs in the CI format job (38-06; CI.yml lines 166-167).

Requirements (gap closure, already complete in REQUIREMENTS.md; this phase closes the audit gaps against them):

| Req | Evidence |
|---|---|
| FIX-08 | shared hybrid-floor kernel used by `assert_socp_exact!`, the MPC first tier and the OOS step (criteria 1, 4) |
| FIX-10 | MPC truth-settled welfare/regret unchanged under the new first tier (scenario B: regret and both welfare figures bit-identical); guide's settlement text corrected (38-09) |
| ARCH-02 | `Scenario` rejects ADMM x import-only at construction; MPC/Stochastic dispatch prose corrected (criteria 3, 4) |
| ARCH-08 | `:oos_inexact_skipped` in `STATUS_VOCABULARY` and status_policy.md; ADMM `:budget_exceeded` now tested in the suite (criteria 2, 4) |
| HYG-02 | FRAMEWORK_GUIDE no longer cites removed kwargs/stubs (38-08) |
| HYG-03 | FRAMEWORK_GUIDE qualifies unexported names and uses `ReactiveMode.LIVE` (38-08); stored reactive mode is a Symbol (38-07) |
| HYG-05 | timeout items discovered and fast; count-sets strict all=517 fast=480 slow=37 files=99 |

## MANUAL (needs GitHub)

- The CI `format` job runs `check_setup_names.py --selftest` and plain on Actions (parses locally; not
  executed on Actions here).
- The full Actions matrix (Julia 1.10 / 1.11 / 1.12) on a pushed branch. Locally, 1.10.11 and 1.11.9 were
  measured for every new MPC and stochastic assertion (see Cross-version checks) and nothing was
  "not measurable locally", so the residual risk is the hosted runners only (CPU / BLAS differences could
  shift a cone residual near τ). The thinnest margins are the happy-path MPC fixture (0.938 on 1.12.5) and
  the build-once harness cycle 2 (0.4964).
- The `jet` job (pinned 1.12.7) and the nightly `slow.yml` on Actions.
- FRAMEWORK_GUIDE prose accuracy spot-check (38-VALIDATION Manual-Only).

## Verdict

All local gates green: Fail 0 / Error 0 / Broken 5 on 1.12.5 (Pass 32304) and 1.12.7 (Pass 32299), each
exactly baseline + 80 with every unit itemized; canary iters 56 on both; count-sets match the ledger;
JET 0 NEW / 0 FIXED; docs build `docs OK` with 0 unresolved @ref; all guards and selftests pass. The
only behaviour move is the documented 1.12.7 MPC scenario B re-price and the stochastic docs page
exclusions. Phase 38 success criteria 1-4 are met locally; the MANUAL items above remain GitHub-side.
