# Phase 38 — Measurements Ledger

Evidence ledger for the phase gate: per-plan measurements and test deltas. Each plan appends its
rows (test-file item/Pass deltas from filtered runs on Julia 1.12.5, plus any measured numbers it
relied on) so the gate plan can reconcile the full-suite totals against the per-plan claims.

## Test deltas

| plan | file | @testitems before -> after | Pass before -> after (1.12.5 filtered run) | note |
|------|------|----------------------------|--------------------------------------------|------|
| 38-01 | test/test_exactness.jl | 6 -> 6 | 20 -> 28 | +8 kernel parity assertions inside 2 existing items; combined filtered run with test_admm_exactness_default.jl: 62/62 |
| 38-02 | test/test_mpc_loop.jl | 11 -> 12 | 369 -> 376 | +1 item (hybrid-floor regression + parity, 7 assertions); RED run: 3 failed / 4 passed in the new item against the old inline loop |
| 38-04 | test/test_stochastic_oos_harness.jl + test/test_run_stochastic.jl + test/test_status_policy.jl | 14 -> 15 (5->6, 5, 4) | 56 -> 74 | +1 item (inexact refusal, 7 assertions); +7 in run_stochastic items (3-tuple flags, recovery ratio, inexact_h/socp_maxratio_h mask); +4 `_stochastic_status` 2-mask cases; golden pin unchanged |
| 38-06 | test/test_admm_timeout.jl | 0 (plain script, never discovered) -> 2 | 0 (not run by the suite) -> 19 | script converted to 2 fast `:admm` items (1 + 11 budget assertions; 7 convergence assertions); cap assertion tightened `Exception` -> `ConvergenceError`; isolated cold filtered run 55.4 s (incl. compile); no `:slow` tag (warm in-suite ≈ 13 s < 30 s). `--count-sets --strict` before: `all=513 fast=476 slow=37 files=98 canary=1 outside=0`; after: `all=515 fast=478 slow=37 files=99 canary=1 outside=0`; `test/expected_broken.txt` unchanged (no Broken) |
| 38-07 T1 | test/test_strategies.jl (+ test_scenario_pf.jl, test_experiments.jl in the same run) | 26 -> 27 (53 -> 54 over the three files) | strategies 415 -> 422; three files 600 -> 607 | +1 fast item, no solve (7 assertions): ADMM x `allow_export = false` throws `ArgumentError` on the keyword, legacy `:admm` and `run(ADMM(), ...)` paths; Centralized/MPC/Stochastic import-only still construct. RED (scratch script, src unchanged): 2/2 throws missing. Baseline 415 is the 38-04 measurement (file untouched since); the other two files' 185 is inferred from the after run. No existing test built an ADMM import-only Scenario (`grep allow_export = false`: only Centralized variants in test_experiments.jl and the mpc_window builder) |

## MPC first-tier ratios (old flat 1e-6 vs hybrid)

Measured BEFORE the MPC code change (HEAD 0a212f5) with a scratch-only monkey-patch of
`_mpc_certify_and_price` that logs, per resolve, the old flat-floor ratio
(`hybrid_ratios(o.ctx; atol = 1e-6)` max) and the new hybrid-floor ratio (`hybrid_ratios(o.ctx)`
max) while keeping the OLD decision. The scratch scripts (`p38/mpc_measure.jl`, `mpc_regression.jl`,
`mpc_highpv.jl`) live in the session scratchpad, not in the repo. Values are max OLD / max NEW over
all resolves, with the worst resolve t of the NEW ratio. All numbers agree with the research table
to rounding.

| scenario | 1.12.5 max old / new (worst t) | 1.12.7 max old / new (worst t) | flips 1.12.5 / 1.12.7 | consumers |
|----------|--------------------------------|--------------------------------|-----------------------|-----------|
| A happy: `T=9, MPC(H=3, terminal_soc=true, forecast_error=0.0)` | 0.4204 / **0.9383** (t=4; b=9, gap 1.879e-7) | 0.1131 / 0.3230 (t=6) | 0/7 / 0/7 | test_mpc_loop "end-to-end … never escalates"; test_status_policy; test_strategies "run(MPC) common shape", "dispatch uniformity", "run_and_store round-trip" |
| B shortfall: `T=9, MPC(H=3, step=1, terminal_soc=true, forecast_error=0.3)`, seed 1 | 0.1574 / 0.7708 (t=4) | 0.2332 / **1.1653** (t=4; b=6, τ=3, gap 2.333e-7) | 0/7 / **1/7** | test_mpc_loop forced-PV-shortfall, "A6 call site", "AC truth settlement REPORTS" (none asserts status/cert trace/dadp) |
| C1 stride step=1: `MPC(H=3, terminal_soc=true, forecast_error=0.05, step=1)` | 0.2485 / 0.8338 (t=6) | 0.1439 / 0.3301 (t=4) | 0/7 / 0/7 | test_mpc_loop "mpc_step genuinely strides" |
| C2 stride step=2 | 0.0341 / 0.1704 (t=3) | 0.0356 / 0.1780 (t=3) | 0/4 / 0/4 | test_mpc_loop "mpc_step genuinely strides" |
| D default `MPC()` (H=6, fe=0.05), T=9 | 0.0643 / 0.3155 (t=3) | 0.0886 / 0.4424 (t=3) | 0/4 / 0/4 | test_strategies "fallback to defaults" (:slow) |
| E docs/script: `T=24, MPC(H=6, terminal_soc=true, forecast_error=0.08)` | 0.0895 / 0.4466 (t=11) | 0.0897 / 0.4478 (t=11) | 0/19 / 0/19 | docs/literate/mpc_rolling_horizon.jl, scripts/demo_mpc_plots.jl |
| High-PV `pv_scale=3.0`, `thesis_literal=true` (direct `_mpc_certify_and_price`, t=1 / t=4) | 9156.5 / 9177.7 (t=1); 9166.4 / 9172.5 (t=4) | 9156.5 / 9177.7; 9166.4 / 9172.5 | 0 / 0 (already escalates: `:certified_convex_dual_restricted` both ways) | test_mpc_loop forced-inexact, escalation at t > 1, ladder terminal failure |

Verdict flips: **none on 1.12.5; exactly one on 1.12.7** (B, t=4: old 0.233 certified -> new 1.165
escalates). No new flip beyond the one the research predicted. The happy-path fixture's worst
hybrid ratio is 0.9383 on 1.12.5 (6.6 % margin under its "never escalates" assertion). The knife-edge
canary is not an MPC scenario and is untouched.

Regression point (high-PV feeder, `pv_scale = 1.2`, default `ConvexBranchFlow()`, H = 3,
`terminal_soc = false`, slack `l[2,1] ≥ l* + δ` on the light interior branch 2->3, t = 1):

| δ | patch | unperturbed old / new | old ratio | new ratio | current code cert_status | fixed code cert_status |
|---|-------|-----------------------|-----------|-----------|--------------------------|------------------------|
| 3e-7 | 1.12.5 / 1.12.7 | 0.00231 / 0.0114 ; 0.00226 / 0.0111 | 0.3008 / 0.3007 | 1.4804 / 1.4798 | `:certified_convex_dual` | `:certified_convex_dual_restricted` (scratch NEW-mode decision) |
| **5e-7** | 1.12.5 / 1.12.7 | (same) | **0.4993 / 0.4992** | **2.4571 / 2.4566** | `:certified_convex_dual` | `:certified_convex_dual_restricted` (pinned by the new test item) |
| 7e-7 | 1.12.5 / 1.12.7 | (same) | 0.7024 / 0.7024 | 3.4562 / 3.4560 | `:certified_convex_dual` | `:certified_convex_dual_restricted` (scratch NEW-mode decision) |

## MPC explained moves

Shortfall fixture `Scenario(; name = "mpc_loop_fix10_shortfall", feeder = :ieee13, T = 9, seed = 1,
strategy = MPC(H = 3, step = 1, terminal_soc = true, forecast_error = 0.3))`, run with the
committed code (after) and with the pre-change `_mpc_certify_and_price` re-instated verbatim from
commit 134c096 (before), scratch scripts only.

| quantity | 1.12.7 before | 1.12.7 after | 1.12.5 before = after |
|----------|---------------|--------------|-----------------------|
| first-tier ratio at t=4 | 0.233 (old flat floor) | 1.165 (hybrid floor; b=6, τ=3, gap 2.333e-7) | 0.157 -> 0.771 (stays ≤ 1) |
| `cert_status_trace[4]` | `:certified_convex_dual` | `:certified_convex_dual_restricted` | `:certified_convex_dual` |
| `status` | `:certified` | `:degraded` | `:certified` |
| `dadp_trace[4]` | 0.008895250684296654 | 0.008894113604359186 | 0.008895156229228245 |
| other `dadp_trace` entries | — | bit-identical to before | unchanged |
| `regret` | -0.0469747761931103 | -0.0469747761931103 | -0.04697206392881981 |
| `realized_welfare` | -468.9958511666502 | -468.9958511666502 | -468.995848451271 |
| `forecast_settled_welfare` | -468.8911819809952 | -468.8911819809952 | -468.8911822070599 |

Explanation: on 1.12.7 the t=4 window has a 2.333e-7 cone residual on an interior branch. The old
flat 1e-6 floor accepted it; the hybrid floor (atol_b = τ_solver = 2e-7 on that branch) refuses
it, so the resolve escalates to the restricted tier, whose dual is published instead. Escalation
only re-prices: the applied dispatch, regret and both welfare figures are unchanged. **No test
asserts these values** — the scenario name appears only in test/test_mpc_loop.jl (forced-PV
shortfall, "A6 call site", "AC truth settlement REPORTS" items), none of which reads `status`,
`cert_status_trace` or `dadp_trace`. On 1.12.5 nothing moves.

Margin note: the happy-path fixture's worst hybrid ratio is **0.938 on 1.12.5** (t=4, b=9, gap
1.879e-7), a 6.6 % margin under its "never escalates" assertion (0.323 on 1.12.7). τ is NOT raised.

## Cross-version (1.10 / 1.11) MPC checks

`juliaup status`: channels 1.10 (1.10.11) and 1.11 (1.11.9) installed; both environments
(`Manifest-v1.10.toml`, `Manifest-v1.11.toml`) loaded without modification. Committed code, scratch
script only (the MPCFixtures constructors loaded from test/fixtures_mpc.jl as a plain module; a
logging-only hook records the shipped first-tier ratio, decisions untouched).

| check | 1.10.11 | 1.11.9 | asserted by the new test item |
|-------|---------|--------|-------------------------------|
| regression point, unperturbed | `:certified_convex_dual`, ratio 0.0114 | `:certified_convex_dual`, ratio 0.0114 | `=== :certified_convex_dual` |
| regression point, 5e-7 slack: old flat ratio | 0.4993 | 0.4993 | `<= 1` |
| regression point, 5e-7 slack: hybrid ratio / `cone_maxratio` (parity) | 2.4571 / 2.4571 (exact equality) | 2.4571 / 2.4571 (exact equality) | `==`, `> 1` |
| regression point, 5e-7 slack: cert_status, prices | `:certified_convex_dual_restricted`, 3 finite | `:certified_convex_dual_restricted`, 3 finite | `===`, length H, all finite |
| scenario A (happy) status / per-step certs | `:certified`, 7 × `:certified_convex_dual` | `:certified`, 7 × `:certified_convex_dual` | "never escalates" |
| scenario A worst hybrid ratio | 0.9383 (t=4) | 0.9383 (t=4) | — (6.6 % margin, same as 1.12.5) |

Every assertion holds on 1.10 and 1.11; nothing marked as a MANUAL CI risk.

MPC consumer runs after the change (Julia 1.12.5 filtered runner): `file:test_mpc_loop.jl` 12 items /
376 Pass; `file:test_status_policy.jl,test_mpc_terminal.jl,test_mpc_window.jl` 10 items / 45 Pass;
`file:test_strategies.jl` (all 26 items, including the `:slow` "fallback to defaults") 415 Pass.
Formatter (`format210.jl`) produced no changes.

## Stochastic OOS ratios (hybrid gate)

Measured BEFORE the OOS code change (HEAD 0b58ec9) with a scratch-only monkey-patch of
`solve_stochastic_oos_step!` (session scratchpad `p38/oos_measure2.jl`, never under the repo) that
logs the worst hybrid ratio `maximum(hybrid_ratios(h.ctx)).ratio` of every successful held-out
re-solve without changing behaviour. Default harness optimizer (`tol_gap = 1e-8`) unless noted.
"Predicted" = mean of `welfare_h` over draws that are feasible AND exact (ratio ≤ 1), minus
`in_sample.welfare`, i.e. the value the exclude-and-report rule will publish.

| fixture | 1.12.5 per-solve ratios (refused) | 1.12.7 per-solve ratios (refused) |
|---------|-----------------------------------|-----------------------------------|
| CI golden `T=9, Stochastic(S=3, H_oos=5)` (= default `Stochastic()` at T=9) | 0.236, 0.290, 0.184, 0.118, 0.366 (**0/5**) | 0.350, 0.214, 0.257, 0.116, 0.283 (**0/5**) |
| docs page `T=9, S=5, p=[.05,.15,.30,.30,.20], H_oos=10` | 0.859, 0.677, 0.590, **1.308**, 0.885, **1.022**, **1.137**, 0.292, **1.634**, **1.072** (**5/10**) | 0.847, 0.860, 0.583, **1.941**, **1.084**, 0.978, 0.723, 0.672, 0.838, 0.679 (**2/10**) |
| compare script `scripts/compare_default_stochastic.jl` (seed 42, same S/p/H_oos as docs) | 0.125, 0.303, 0.388, 0.302, 0.104, 0.182, 0.083, 0.478, 0.246, 0.362 (**0/10**) | 0.126, 0.266, 0.230, 0.232, 0.101, 0.177, 0.092, 0.332, 0.176, 0.520 (**0/10**) |
| harness build-once (3 pin cycles) | **1.129**, **10.57**, 0.651 | same |
| harness pin-binding (2 solves) | **51.23**, **50.41** | same |
| harness FourQuadBESS (no Ppv_param) | 0.373 | same |
| harness FourQuadBESS q pin | **1.489** | same |
| run_stochastic infeasible -> recover | 1st INFEASIBLE (no ratio); recovery **7.294** | same |

Welfare under exclusion (current value -> predicted):

| fixture | patch | status now -> predicted | `realized_welfare` now -> predicted | `welfare_gap` now -> predicted |
|---------|-------|-------------------------|-------------------------------------|--------------------------------|
| CI golden | 1.12.5 | `:solved` -> `:solved` | -538.80426085285922 -> unchanged | -0.018591711034105174 -> **unchanged** |
| CI golden | 1.12.7 | `:solved` -> `:solved` | -538.80426081613405 -> unchanged | -0.018591674331901231 -> **unchanged** |
| docs page | 1.12.5 | `:solved` -> `:oos_inexact_skipped` | -538.79909522353591 -> -538.78303068258083 (5 usable) | 0.016867421597680732 -> 0.032931962552765981 |
| docs page | 1.12.7 | `:solved` -> `:oos_inexact_skipped` | -538.79909539186974 -> -538.7899694697544 (8 usable) | 0.016867253255441028 -> 0.025993175370786048 |
| compare script (seed 42) | 1.12.5 | `:solved` -> `:solved` | -538.78688296455698 -> unchanged | -0.032394888164958502 -> unchanged |
| compare script (seed 42) | 1.12.7 | `:solved` -> `:solved` | -538.78688300533611 -> unchanged | -0.032394929060160393 -> unchanged |

The CI golden refuses no draw on either patch (worst 0.366 / 0.350), so its pin
(`-0.018591711034105174`, rtol 1e-4) and `:solved` status cannot move. The compare script refuses
nothing on either patch (worst 0.478 / 0.520): its numbers do not move. The docs page is the one
explained move: 5/10 (1.12.5) vs 2/10 (1.12.7) draws excluded; the page must report the count
live. The refused docs rows are cone violations of 2.05-3.88e-7, just above τ_solver = 2e-7
(research diagnosis: solver-accuracy floor on the pinned-dispatch problem). No τ/ε was raised.

Direct-harness fixtures at the tightened optimizer `select_optimizer(SOCP(); tol_gap_abs = 5e-10,
tol_gap_rel = 5e-10)` (`OOS_TOL=5e-10`, harness only):

| fixture | 1.12.5 | 1.12.7 |
|---------|--------|--------|
| build-once | 0.0119, 0.4964, 0.0088 | 0.0119, 0.4964, 0.0088 |
| pin-binding | 0.3889, 0.3538 | 0.3889, 0.3538 |
| FourQuadBESS | 0.0056 | 0.0056 |
| FourQuadBESS q pin | 0.0370 | 0.0370 |
| infeasible -> recover | 1st still INFEASIBLE `(NaN, true)`; recovery 0.0778 | same; recovery 0.0777 |

So the infeasible -> recover item can switch to the tightened optimizer: its first solve stays
INFEASIBLE and its recovery is exact.

Baseline before the test edits (HEAD, 1.12.5 filtered run,
`file:test_stochastic_oos_harness.jl,test_run_stochastic.jl,test_status_policy.jl`): 14 @testitems
(5 + 5 + 4) / **56 Pass**.

38-04 RED run (tests written, src unchanged; 1.12.5 filtered, same three files): 15 @testitems,
49 Pass / 2 Fail / 14 Error. Failures for the intended reasons: the step does not throw
(`No exception thrown`), the vocabulary lacks `:oos_inexact_skipped`, `_stochastic_status` has no
2-mask method, `_stoch_solve_held_out!` returns a 2-tuple (BoundsError on the 3rd element) and
`oos` has no `inexact_h`/`socp_maxratio_h`. The infeasible -> recover item uses the tightened
optimizer (measured above: first solve still INFEASIBLE, recovery exact).

38-04 GREEN (1.12.5 filtered): `file:test_stochastic_oos_harness.jl,test_run_stochastic.jl,test_status_policy.jl`
15 items / 74 Pass (baseline 56, +18); with `test_stochastic_welfare.jl` added: 22 items / 100 Pass.
`file:test_strategies.jl` (all 26 items incl. `:slow`, via suite_detached.sh): 415 Pass, unchanged
from 38-02. CI golden `welfare_gap` = -0.018591711034105174 on 1.12.5 (unchanged), status `:solved`.

## Cross-version (1.10 / 1.11) stochastic checks

Committed code (63816bb), scratch script `p38/oos_cross.jl` (StochasticFixtures loaded from
test/fixtures_stochastic.jl as a plain module), run sequentially. Both environments
(`Manifest-v1.10.toml`, `Manifest-v1.11.toml`) loaded without modification. 1.12.7 added for
completeness.

| check | 1.10.11 | 1.11.9 | 1.12.7 | asserted by |
|-------|---------|--------|--------|-------------|
| (i) CI golden `T=9, Stochastic(S=3, H_oos=5)`: status / `inexact_h` / `infeasible_h` | `:solved` / all false / all false | `:solved` / all false / all false | `:solved` / all false / all false | mask item, status-policy item |
| (i) golden max `socp_maxratio_h` | 0.3660 | 0.3660 | 0.3496 | `all(<=(1), …)` |
| (i) golden `welfare_gap` | -0.018591711034105174 (rel. diff 0) | -0.018591711034105174 (rel. diff 0) | -0.018591674331901231 (rel. diff 2.0e-6 < 1e-4) | golden pin rtol 1e-4 |
| (ii) pin-binding at DEFAULT optimizer | throws `CertificateError` `:socp_exact`, ratio 51.23; helper `(-44.4315, false, true)` | same | same | new refusal item |
| (iii) build-once at 5e-10 (3 solves) | 0.0119, 0.4964, 0.0088 | same | same | build-once item |
| (iii) pin-binding at 5e-10 (2 solves) | 0.3889, 0.3538 | same | same | pin-binding item |
| FourQuadBESS (no Ppv_param) at DEFAULT | 0.3729 | 0.3729 | 0.3729 | FourQuadBESS item (unchanged optimizer) |
| (iii) FourQuadBESS q pin at 5e-10 | 0.0370 | 0.0370 | 0.0370 | q-pin item |
| (iii) infeasible -> recover at 5e-10 | `(NaN, true, false)`; recovery `(-44.4731, false, false)`, ratio 0.0778 | same | same (0.0777) | infeasible -> recover item |

Every new assertion holds on 1.10 and 1.11; nothing marked as a MANUAL CI risk. The thinnest
margin is build-once cycle 2 (0.4964, about 2x below the gate) on every patch.

## Stochastic docs page (live)

`docs/literate/stochastic_pv_demand.jl` executed end-to-end as a script on Julia 1.12.5
(`JULIA_LOAD_PATH="docs:.:@stdlib" julia +release --project=. docs/literate/stochastic_pv_demand.jl`,
exit 0; the counts below printed by a one-off `include` of the same page with a trailing print).
The page now prints these counts live in section 4 and plots only usable draws (excluded-inexact
draws as hollow markers).

| quantity | 1.12.5 (live) |
|----------|---------------|
| held-out draws | 10 |
| excluded as inexact | **5** (draws 4, 6, 7, 9, 10) |
| excluded as infeasible | 0 |
| usable | 5 |
| status | `:oos_inexact_skipped` |
| per-draw hybrid ratio | 0.858, 0.677, 0.589, **1.308**, 0.885, **1.021**, **1.137**, 0.292, **1.634**, **1.072** |
| worst ratio | 1.633837830641987 |
| `realized_welfare` | -538.7830306825808 |
| `in_sample.welfare` | -538.8159626451336 |
| `welfare_gap` | 0.03293196255276598 (pre-gate 0.016867421597680732) |

Matches the 38-04 prediction for 1.12.5 exactly (5/10, gap 0.032931962552765981). The page's
former hard-coded "small and POSITIVE" sign sentence was replaced by a reference to the live
value; on 1.12.7 the prediction is 2/10 excluded (gap 0.025993), which the page reports live.

## compare_default_stochastic (seed 42) explained moves

Re-run of the inexact-aware `scripts/compare_default_stochastic.jl` on Julia 1.12.5, launched via
`suite_detached.sh p38-compare-stoch` (done marker `0`). The script now applies the same usable mask
as `run_stochastic` (`.!(infeasible_h .| inexact_h)`), prints the inexact count and the run status,
writes `oos_inexact_draws` to summary.csv and an `inexact` column to oos_draws.csv, and draws
excluded-inexact points as hollow markers.

**Gate effect: none.** 0/10 draws refused (status `:solved`), and the published `welfare_gap`
-0.0323948881649585 equals the pre-gate value measured in 38-04 (-0.032394888164958502) to the last
printed digit.

**But the tracked artifacts were stale.** `results/compare_default_stochastic/` and the writeup were
last regenerated on 2026-09-08 (ab14c67), before the v4.0 modeling fixes (exactness copy direction,
battery hour-T energy link, reverse thermal limit, flexible-load reactive draw) and later changes.
Re-running with the current code moves these numbers. The cause was not bisected; it is not the gate,
since the gate refused nothing and the gap matches the pre-gate measurement.

| quantity | HEAD (2026-09-08 artifact) | re-run (1.12.5) | cause |
|----------|----------------------------|-----------------|-------|
| oos inexact draws | (not reported) | **0 / 10** | new column/row; gate refused nothing |
| run status | (not reported) | `:solved` | — |
| `oos_welfare_gap` | -0.03598937873448449 | **-0.0323948881649585** | stale artifact (modeling changes since 2026-09-08), not the gate |
| `oos_realized_welfare` | -538.7522475069767 | -538.786882964557 | same |
| `stoch_insample_welfare` | -538.7162581282422 | -538.754488076392 | same |
| `default_welfare` | -538.8475100160589 | -538.8957427671698 | same |
| `default_exact_maxgap` | 1.0646e-8 | 2.1427e-8 | same |
| `stoch_exact_maxgap_max` | 3.6416e-9 | 1.8695e-9 | same |
| `stoch_expected_dadp_mean` | 3.253686339420884 | 3.1645738082799464 | same (hours 4–6 prices) |
| DADP hours 4–6 (all sources) | ≈ 0.217–0.339 | ≈ 0.003–0.025 | same; hours 1–3 and 7–9 unchanged to 3 decimals (scenario 1 h3 3.583 -> 3.582) |
| `dadp_spread_max` | 0.1273970562276423 | 0.1273970528079511 | same (hour 7) |
| per-hour spread h4–h6 | 0.012–0.026 | 0.0072, 0.0122, 0.0168 | same |
| oos per-draw welfare | e.g. h1 -538.6315 | h1 -538.6655 (all 10 shifted ≈ -0.03 to -0.05) | same |
| summary.csv notes | contained planning identifiers | plain text (script scrubbed earlier) | script already scrubbed; artifact was stale |
| solve times | 51.27 s / 9.59 s | 47.93 s / 9.45 s | wall time, not a result |

Result files: summary.csv, oos_draws.csv, dadp_tidy.csv and the dadp_comparison, price_envelope and
welfare_robustness PDFs/PNGs changed in content and are committed. scenario_fan.png is
byte-identical (the exogenous draws did not move); scenario_fan.pdf differed only in metadata and
was restored with `git checkout`.

Writeup `docs/writeups/compare_default_stochastic.typ` (Portuguese) updated: every moved number
above, the DADP table hours 4–6, the midday collapse range, the "< 1 % / ≤ 2.7 % of the local price"
claims (now qualified: they hold outside the PV valley, where the price is near zero), the
held-out certification sentence (0/10 inexact), and a header note that the numbers were refreshed
by a re-run with the current code. Compiles with `typst compile --root .`.
