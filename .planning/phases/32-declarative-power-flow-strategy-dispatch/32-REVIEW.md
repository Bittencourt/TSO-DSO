---
phase: 32-declarative-power-flow-strategy-dispatch
reviewed: 2026-10-03T00:00:00Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - src/experiments/strategies.jl
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - src/experiments/run.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run_stochastic.jl
  - src/TSODSO.jl
  - test/test_strategies.jl
  - test/test_scenario_pf.jl
  - test/test_experiments.jl
  - test/test_mpc_loop.jl
  - test/test_run_stochastic.jl
  - test/test_planning_noninteger.jl
  - docs/literate/experiments.jl
  - docs/literate/mpc_rolling_horizon.jl
  - docs/literate/stochastic_pv_demand.jl
  - scripts/compare_default_stochastic.jl
  - scripts/demo_mpc_plots.jl
  - README.md
  - docs/src/api.md
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: issues_found
---

# Phase 32: Code Review Report (iteration 2)

**Reviewed:** 2026-10-03
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found (info only)

## Summary

Verified the five fixes (b89f8d5, b1ad445, 99853f2, 2f9aed3, a47e758) by reading the diffs and surrounding code. I did not run the test suite. All five are correct, and I found no regressions or new warnings or blockers.

- WR-01: `run_mpc` and `run_stochastic` now route through `with_strategy` when the substituted default strategy differs from `s.strategy`. This reuses the same pattern as `run(st, s)` and `_effective_scenario`, so the strategy x pf check re-runs. When the strategy already matches, `s` is passed through untouched, so there is no behavior change.
- WR-02: `isfinite` is checked on all five float knobs before the sign checks, so NaN and Inf are rejected. `maxiter` is an Int and needs no check.
- WR-03: `x + 0.0` turns `-0.0` into `+0.0` (IEEE: `-0.0 + 0.0 == +0.0`). `Scenario.pf_ε` and `MPC.forecast_error` are the only floats that admit zero. NaN is already rejected by the `isfinite` and range checks. The ADMM knobs must be > 0, and `Stochastic.probabilities` must be > 0, so `-0.0` cannot occur there.
- WR-04: `_check_probabilities` is shared by the constructor and `_run_stochastic`. Because it uses `all(>(0), ...)`, NaN entries fail it. The length check uses `st.S`, so a vector that was resized after construction is caught.
- WR-05: `_stable_hex64(codeunits(full))` is deterministic. It is zero-padded to 16 hex digits, matching the `hash_suffix_len` budget (2 + 16 + 5), so the length bound still holds.

## Info

### IN-01: `scenario_filename` docstring still says `_h<hash(full)>`

**File:** `src/experiments/store.jl:139`
**Issue:** After WR-05 the fallback suffix is `_h` plus a 16-digit FNV-1a digest from `_stable_hex64`, not `Base.hash`. The docstring is stale and contradicts the stable-digest claim made a few lines above it.
**Fix:** Replace it with `_h<16-hex FNV-1a digest of full>` and link `_stable_hex64`.

### IN-02: `Stochastic.probabilities` remains a mutable vector inside a value-hashed struct

**File:** `src/experiments/strategies.jl:130,164`
**Issue:** The WR-04 fix re-validates at run time, but `hash` and `==` still read the live vector. If a caller mutates `probabilities` after a `Scenario` has been placed in a `Dict` or `Set`, the stored hash goes stale. Mutation after a `scenario_filename` call would also yield a different filename. This is a documented, accepted trade-off from the fixer, and the risk is low for a research bench.
**Fix (optional):** Store an immutable `NTuple` or `SVector`, or document "do not mutate" in the `Stochastic` docstring.

---

_Reviewed: 2026-10-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
