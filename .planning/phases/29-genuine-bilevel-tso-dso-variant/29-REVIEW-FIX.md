---
phase: 29-genuine-bilevel-tso-dso-variant
fixed_at: 2026-09-30T00:00:00Z
review_path: .planning/phases/29-genuine-bilevel-tso-dso-variant/29-REVIEW.md
iteration: 2
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 29: Code Review Fix Report (iteration 2)

**Fixed at:** 2026-09-30
**Source review:** .planning/phases/29-genuine-bilevel-tso-dso-variant/29-REVIEW.md
**Iteration:** 2 (the iteration-1 report is kept at `29-REVIEW-FIX.iter1.md`)

**Summary:**
- Findings in scope: 3 (CR-01, WR-01, WR-02). The Info findings IN-01..IN-03 were out of scope.
- Fixed: 3
- Skipped: 0

**Production goldens are unchanged.** I measured them after the final commit:

| Fixture | y* | x_inv* | z* | total* |
|---|---|---|---|---|
| Corner | 0 | 0 | 0 | 0 |
| Interior | 0.148 | 0.148 | 1.48 | -1.4726 |
| d_max-binding | 0.1 | 0.1 | 1.0 | -0.995 |
| T=2 | 0.148 | 0.148 | [1.48, 1.0] | -2.9726 |

**No existing multiplier pin changed.** Every pinned value lies on a unique multiplier set, so the canonical certificate equals the old raw value there. That covers `rho_y` 9.8 / 0 / 4.8 / 14.8 / 2.8, `mu_cap` 0.5 / [0.02, 0], `rho_max` 4.8, and the complementarity products. No golden or pin was re-set.

**Verification:**
- Direct Julia scripts run with `JULIA_LOAD_PATH="test:.:@stdlib"`, using a scratch `@testmodule`/`@testitem` emulator (`scratchpad/emu.jl`) that runs each body statement by statement at module top level.
- `fixtures_planning.jl`, `test_planning_bilevel.jl`, `test_planning_certification_bilevel.jl` and `test_planning_certification_bilevel_interior.jl` all pass: 166/166. The baseline before any fix was 113/113.
- The reviewer's sweep `rand.jl` (safety = 1) gives 0/60 at-bound errors, down from 26/60. A safety = 10 copy also gives 0/60, down from 6/60. Worst `prod - bf` is 1.0e-7 and `nbad = 0`. (`rand10.jl` is byte-identical to `rand.jl`.)
- An extra 400-solve random sweep (`scratchpad/randcert.jl`: safety 1 and 10, about 30% with a random fixed `y_inv`) raised no errors. The worst stationarity / complementarity / sign residual of the returned multipliers was 3.8e-14, and none fell outside the box.
- `Pkg.test()` was NOT run.

## Fixed Issues

### CR-01: `solve_bilevel!` throws "true optimum may have been cut off" on correct optima whenever `x_inv* = 0`

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`
**Commit:** 81cc227
**Status:** fixed: requires human verification (the validity check's logic changed)
**Applied fix:**
- New `_recover_kkt_certificate(kkt)`. It fixes the solved primal `(y_inv, x_inv, z)` and solves a small HiGHS LP (`select_optimizer(LP())`) over `mu_cap, mu_lo, rho_y, rho_lo, rho_max >= 0` with:
  - the follower's `statio_x` and `statio_z[t]` at the fixed primal;
  - complementarity on the solved active set: a multiplier is fixed to 0 when its primal slack is above `act_tol = 1e-6`;
  - a min-max objective, `min s` subject to `multiplier_i - lim_i <= s`.
- The at-bound check now fails only if `s* > 0`, meaning no valid certificate respects the limits. The error names the multiplier that attains `s*`, and the message still contains "`<name> sits at (or within`". It no longer tells the user to raise `safety` and retry in a loop that cannot succeed.
- **Design deviation from the review sketch: the limit is per variable.**
  - `lim_i = ub_i - 1e-6`, where `ub_i = upper_bound(var)` in the MILP. Using the actual variable bound rather than `m_ub` is what lets the WR-01 `set_upper_bound` stress test reach the check.
  - The exception: when `ub_i >= m_ub_proven`, `lim_i = max(ub_i - 1e-6, m_ub_proven + 1e-6)`, where `m_ub_proven = m_ub / safety` is the unscaled closed-form bound.
  - Why the exception is needed: at `safety = 1` with `x_inv* = 0` and a profitable follower, the smallest valid certificate sits exactly at the proven bound (`rho_y = 14.8 = m_ub` on the interior data with `v_d = [1.0]`). The derivation shows this certificate is admissible. The review's plain `objective_value(cert) < m_ub - atol` would therefore still have raised false errors at `safety = 1`, which `rand.jl` exercises.
- `BilevelKKT` gains the fields `m_ub_proven`, `corridor_cap`, `x_inv_max`, `c_inv`, `margin` and `q_op`. The constructor is internal; its only call site is `build_bilevel_kkt`.
- Docstrings for `solve_bilevel!` and `_recover_kkt_certificate` explain the degenerate-face failure. They also keep the iteration-1 "necessary, not sufficient" caveat.
- **Regression testitem:** interior data with `v_d = [1.0]`, with `c_y = 20`, and with `y_inv` fixed at 0, each at `safety = 10` and `safety = 1`. It expects `y = x_inv = z = 0`, `total = 0`, and no throw. All 6 cases failed against the pre-fix source and all pass now.
- **Human check requested:**
  - the per-variable `lim_i` rule, especially the `m_ub_proven` exception;
  - the choice `act_tol = 1e-6` for the active set.

### WR-01: `safety` in `(0, 1)` is accepted, but the validity proof needs `safety >= 1`

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`
**Commit:** a8f4411
**Applied fix:**
- The guard is now `safety >= 1 || throw(ArgumentError(...))`, and the docstring guard list is updated.
- The too-tight-bound stress test (the iteration-1 WR-06 test) now builds with `safety = 1` (`m_ub = 14.8`) and calls `set_upper_bound(tight.rho_y, 9.8)`. `y_inv` is fixed at 0.05, where `rho_y = 9.8` is unique, so the at-bound error path is still reached and asserted.
- The positive control (`safety = 1`, `rho_y = 9.8`) is unchanged.
- The boundary-guard testitem now asserts that `safety = 0.5` throws `ArgumentError` and that `safety = 1.0` builds.

### WR-02: Returned multipliers are arbitrary points on a non-unique multiplier face

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`
**Commit:** 23a72b1
**Status:** fixed: requires human verification (it changes what the returned multipliers mean)
**Applied fix:**
- Once the check passes, the same recovery LP computes a canonical certificate inside the MILP box by lexicographic minimization:
  1. `min Σ(mu_cap + mu_lo)`;
  2. then `min rho_y + rho_lo + rho_max`;
  3. then `min rho_y`.
- `solve_bilevel!` returns this certificate in place of HiGHS's raw vertex. The raw values are still available on `kkt.mu_cap` and the other fields.
- **Deviation from the guidance's single `min Σ multipliers`:** that LP is not unique. On the corner fixture (`corridor_cap = 2`), every point `mu_cap = δ ∈ [0, 0.5]`, `mu_lo = 0.3 + δ`, `rho_lo = 1 - 2δ` has the same total of 1.3. The docstring shows the lexicographic order is unique on every active set this model can produce:
  - `x_inv > 0`: everything except the `rho_y`/`rho_max` split at `y = x_inv = x_inv_max` is already determined, and stage 3 sets `rho_y = 0` there. That is the marginal value of raising `y`, which cannot help when `x_inv_max` binds.
  - `x_inv = 0`: the result is exactly the certificate from the `_follower_kkt_dual_bound` derivation, `mu_cap = a⁺`, `mu_lo = a⁻`, `rho_y = (cap·Σa⁺ - c_inv)⁺`, `rho_lo = (c_inv - cap·Σa⁺)⁺`.
- The docstring says the returned duals are the canonical minimal valid KKT multipliers. On degenerate sets they are one valid certificate among many, to be read as one-sided shadow values, not as prices.
- **Multiplier values that changed** (only on degenerate sets; none was pinned by an existing test). Each new value is the hand-derived lexicographic minimum, and each is now pinned in a new testitem:

| Case | Raw HiGHS vertex (old) | Canonical certificate (new) |
|---|---|---|
| Corner fixture (`x = y = 0`) | `mu_cap = 0.5`, `mu_lo = 0.8`, `rho_lo = 0` | `mu_cap = 0`, `mu_lo = 0.3`, `rho_y = 0`, `rho_lo = 1` |
| Interior, `v_d = [1.0]` | `mu_cap = 14.82`, `rho_y = 148` | `mu_cap = 1.5`, `mu_lo = 0`, `rho_y = 14.8`, `rho_lo = 0` |

  The new testitem also covers the `y = x_inv = x_inv_max = 0.1` corner (`rho_y = 0`, `rho_max = 4.8`) and checks both stationarity equations. It fails against the raw-value code (6 failures).
- `mu_cap = a⁺` and `mu_lo = a⁻` are also the componentwise minimum of `mu_cap` given `mu_cap - mu_lo = a` and `mu_lo >= 0`. In that sense they are provably minimal.

---

_Fixed: 2026-09-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
