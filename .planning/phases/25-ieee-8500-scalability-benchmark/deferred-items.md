# Deferred Items — Phase 25 (IEEE-8500 Scalability Benchmark)

Discoveries made during plan execution that are out of the discovering plan's `<files>` scope,
logged here per the executor's SCOPE BOUNDARY rule rather than fixed inline.

## Plan 25-05: near-zero-impedance MV connector breaks the naive SOC-exactness noise-floor calibration

**Found during:** Task 1's real 5-rung noise-floor calibration deliverable (`--calibrate-noise-floor`)
on both IEEE-8500 fixtures.

**What was found:** On BOTH `ieee8500_mv_modified()` and `ieee8500_modified()`, the worst-offending
branch in the SOCP cone-residual scan is, at every tolerance rung, the SAME real vendored MV
segment `HVMV_Sub_48332 -> _HVMV_Sub_LSB` — `IEEE8500_MV_BRANCH_RX_OHMS[("HVMV_Sub_48332",
"_HVMV_Sub_LSB")] = (1e-6 Ω, 1e-5 Ω)`. At `S_base = 0.5 MVA`, `V = 12.47 kV` this converts to a
genuinely near-zero per-unit impedance (`r ≈ 3.2e-9 pu`, `x ≈ 3.2e-8 pu`) — roughly SIX orders of
magnitude smaller than the D-13 near-ideal regulator/switch convention already used elsewhere in
this same fixture (`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` = 3e-4/1.5e-4 pu).

**Why this matters:** the LinDistFlow SOC-exactness argument relies on a strictly-positive
loss-cost gradient (`r·l` in the objective) to drive the squared-current variable `l` to its tight
minimal value at the optimum. On a near-zero-`r` branch that gradient is essentially absent, so the
cone residual on THIS branch does not shrink as the solver's `tol_gap` tightens — it is a
STRUCTURAL/ill-conditioning property of the branch, not shrinking numerical noise. Confirmed via a
real-entrypoint diagnostic (not a ratio-only conclusion): the SAME branch tops the worst-gap list on
both fixtures, at every density/seed tried.

**Consequence for this plan:** the calibrated `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL`
constants in `scripts/benchmark_ieee8500.jl` are measured HONESTLY (never inherited from
IEEE-13/123) but are consequently LARGE (0.1796 / 0.5653) — large enough that the harness's own
`exact_verdict` classification against them is a much weaker check than IEEE-13/123's `1e-6`-scale
gate. This is documented in-code and here, not silently absorbed.

**Deferred (out of plan 25-05's `<files>` scope — only `src/models/exactness.jl`,
`scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl` are authorized):**

- Whether `scripts/reduce_ieee8500_impedances.jl` / `src/data/ieee8500.jl` should apply the SAME
  D-13 near-ideal-branch treatment (assign `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` in place of the
  literal near-zero real Ω value) to this specific real connector segment — a documented
  data-shaping decision for whoever picks this up, not a calibration-harness fix.
- Whether `assert_socp_exact!`/`socp_relaxation_gap` should special-case or exclude near-zero-
  impedance branches from the max-gap scan, so a single degenerate connector cannot dominate (and
  effectively disable) the exactness gate for an otherwise well-conditioned network.
- `solve_admm`'s own hardcoded final-consolidation `assert_socp_exact!` call
  (`src/admm/solve_admm.jl`, `check_exact = true`) uses the PROJECT DEFAULT `atol = 1e-6`/
  `rtol = 1e-4` with no override parameter — meaning ADMM on either IEEE-8500 fixture will hit
  this SAME near-zero-impedance branch's residual and throw at the final consolidation gate
  REGARDLESS of density, population, or convergence quality. This is a real, reproducible finding
  (confirmed live during Task 2's `--quick` and `--time-limit 1` exercises: the ADMM point on
  `ieee8500-mv` never reaches a clean converged consolidation — it is intentionally exercised
  under a SHORT wall-clock budget in this plan specifically so `solve_admm`'s D-18 early exit
  (`:budget_exceeded`) fires before the final consolidation gate is ever reached). A future plan
  that wants a genuinely CONVERGED, CONSOLIDATED ADMM point on either IEEE-8500 fixture will hit
  this throw and needs either the same atol reasoning as `assert_socp_exact!`'s override seam
  (currently none exists on `solve_admm`) or the data-shaping fix above.

**Not a plan-25-05 blocker:** Task 1/2/3's own acceptance criteria do not require a converged
ADMM consolidation — they require an honestly-reported point (including `budget_exceeded`), which
this plan delivers. This item is flagged for plan 25-06 (headline results) and beyond.
