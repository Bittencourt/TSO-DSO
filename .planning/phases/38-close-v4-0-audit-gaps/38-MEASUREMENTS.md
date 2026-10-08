# Phase 38 — Measurements Ledger

Evidence ledger for the phase gate: per-plan measurements and test deltas. Each plan appends its
rows (test-file item/Pass deltas from filtered runs on Julia 1.12.5, plus any measured numbers it
relied on) so the gate plan can reconcile the full-suite totals against the per-plan claims.

## Test deltas

| plan | file | @testitems before -> after | Pass before -> after (1.12.5 filtered run) | note |
|------|------|----------------------------|--------------------------------------------|------|
| 38-01 | test/test_exactness.jl | 6 -> 6 | 20 -> 28 | +8 kernel parity assertions inside 2 existing items; combined filtered run with test_admm_exactness_default.jl: 62/62 |

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
