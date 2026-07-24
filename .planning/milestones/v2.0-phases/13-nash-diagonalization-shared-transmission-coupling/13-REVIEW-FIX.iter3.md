---
phase: 13-nash-diagonalization-shared-transmission-coupling
fixed_at: 2026-07-24T04:06:39Z
review_path: .planning/phases/13-nash-diagonalization-shared-transmission-coupling/13-REVIEW.md
iteration: 2
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 13: Code Review Fix Report

**Fixed at:** 2026-07-24T04:06:39Z
**Source review:** .planning/phases/13-nash-diagonalization-shared-transmission-coupling/13-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 1 (fix_scope = critical_warning; IN-08/IN-09 out of scope)
- Fixed: 1
- Skipped: 0

**Verification:** Beyond syntax — the extended seed-liveness testitem was run from a
scratch environment via
`TestItemRunner.run_tests("test"; filter = ti -> occursin("seeds genuinely enter", ti.name))`
against the fixed worktree: **23 pass, 0 fail** (53s; 14 pre-existing + 9 new
assertions). The `Pkg.develop` churn on `test/Project.toml`/`test/Manifest.toml` from
the scratch-env run was reverted before committing — only the test file is in the
commit.

## Fixed Issues

### WR-05: CR-01 seed-liveness regression never varies `z0` — the z-Parameter half of the seeding (the only dimension `run_nash_probe` probes) can silently regress

**Files modified:** `test/test_planning_nash.jl`
**Commit:** 81f342f
**Applied fix (adapted — see note):** Added a third run ("run C") to the existing
seed-liveness testitem that differs from run B in **`z0` ONLY** (identical explicit
`x_inv0 = [0.0, 0.3]`): `z0 = [0.0; 0.6;;]`. In run C distributor 2's seeded flow 0.6
consumes ALL the pooled headroom its seeded investment provides
(`corridor_cap * 0.3 = 0.6`), so distributor 1's sweep-1 best-response collapses back
to `z_1 <= 2*x_inv_1` → BR `(0.6, 0.3)`, sweep-1 residual 0.6, settling on the
symmetric equilibrium `[0.6, 0.6]` — whereas run B (same `x_inv0`, `z0 = 0`) has
sweep-1 residual 0.7 and free-rides to `[0.7, 0.0]`. New assertions pin **exact**
sweep-1 residual values (0.7 for B, 0.6 for C, asserted distinct) AND the equilibrium
fork on `z0` alone (`[0.7, 0.0]` vs `[0.6, 0.6]`, max component gap > 0.05).

Regression coverage argument (documented in-test): if a refactor drops or reorders
around the z-Parameter commit (`set_parameter_value.(shared.z[j,:], z0[j,:])` in
`run_nash!`'s pre-sweep `write_back!` loop, `src/planning/nash.jl:479-481`) while
keeping the investment pinning, run C's distributor 1 sees `z_2 = 0` at pins
`[_, 0.3]` and replays run B exactly — residual 0.7 and equilibrium `[0.7, 0.0]` —
so both new assertion families fail loudly on precisely that partial-CR-01
recurrence. Full deletion of the seed loop remains pinned by run B's pre-existing
assertions. Together, runs B + C pin both halves of the seeding mechanism
independently.

**Adaptation note (deviation from the review's literal suggestion):** The review's
first suggested variant — a hot-`z0` run with the **derived** `x_inv0` default (e.g.
the probe's `skewed` seed `[0.5; 0.1;;]`) vs the cold run — is **vacuous** for this
purpose and was deliberately not used: with `T = 1`, the derived minimal investment
`x_inv0[j] = z0[j]/corridor_cap` makes a pinned neighbor's seeded consumption and
seeded headroom cancel *exactly* in the pooled capacity row
(`z_1 + z0_2 <= cap*(x_1 + z0_2/cap)` ⇔ `z_1 <= cap*x_1`), so every derived-default
seed yields the cold run's sweep-1 feasible set whether or not the z commit is live;
the residuals would differ only through the Julia-side `z_prev` (which never touches
the model), making the suggested assertion pass even with a dead z-Parameter commit.
This cancellation trap is documented in the test so the regression is never
"simplified" back into the vacuous form. The review's alternative "and/or" variant
(direct `parameter_value` assertion of `write_back!`'s z round-trip) is already
covered by `test/test_planning_coupling.jl` (which asserts
`parameter_value.(shared.model[:z][1,:])` round-trips); the missing link WR-05
identified — `run_nash!`'s own seed loop feeding `z0` into that mechanism — is what
run C now pins end-to-end.

## Commits

The fix commit was made on a temporary branch in an isolated worktree and
fast-forwarded onto `main`:

| Commit | Finding | Files |
|--------|---------|-------|
| 81f342f | WR-05 | test/test_planning_nash.jl |

---

_Fixed: 2026-07-24T04:06:39Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
