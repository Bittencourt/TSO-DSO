---
phase: 24-discrete-integer-investment-expansion
verified: 2026-08-24T01:15:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 24: Discrete/Integer Investment Expansion Verification Report

**Phase Goal:** The single-distributor planning Benders loop supports genuine binary-expansion
integer investment, converging on real Laporte–Louveaux integer optimality cuts, with the
PVAL-04 no-binaries guard consciously scoped rather than deleted.
**Verified:** 2026-08-24T01:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Method

This verification did not trust SUMMARY.md/REVIEW.md narrative claims. For each requirement,
the actual source in `src/planning/master_integer.jl`, `src/planning/benders.jl`,
`src/planning/trace.jl`, `src/solver/factory.jl`, and the corresponding test files were read
directly. In addition, an independent test run was executed by this verifier (not copied from
any summary): `test/runtests.jl` was temporarily swapped for a filtered
`@run_package_tests filter=...` targeting every Phase-24 test file (`test_planning_master_integer.jl`,
`test_planning_benders_integer.jl`, `test_planning_certification_integer.jl`,
`test_planning_trace.jl`, `test_solver_factory_milp.jl`, `test_planning_noninteger.jl`), run via
the sanctioned `julia --project=. -e 'import Pkg; Pkg.test()'` entrypoint (never the sibling-worktree-
hazardous `--project=test` route), then `test/runtests.jl` was restored to its exact original
content (`git diff --stat test/runtests.jl` confirmed empty afterward). Result, this session,
independent of any prior claim:

```
Test Summary: | Pass  Total     Time
Package       |  413    413  2m16.6s
     Testing TSODSO tests passed
```

`git status --short` after restoring `test/runtests.jl` shows only pre-existing, unrelated local
drift (`Manifest-v1.12.toml`, `Project.toml` — the documented CairoMakie/Makie local drift from
MEMORY.md) plus an unrelated `.planning/tmp/` — no Phase-24 file was left dirty by this
verification.

`git log --oneline -- src/planning/master.jl` was independently re-checked: the file's last
touching commits predate Phase 24 entirely (Phase 11/12), corroborating D-05's byte-identical
claim directly from git history, not merely from the SUMMARY's own `git diff` assertion.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | INT-01: Planning master supports binary-expansion integer investment as a HiGHS MILP behind `select_optimizer`, single-distributor scope | ✓ VERIFIED | `src/planning/master_integer.jl:157-193` builds `y_inv = (y_max/2^K)*Σ 2^(k-1)*b_k` over `@variable(model, b[1:K], Bin)`, `model = Model(select_optimizer(MILP()))` (never `Model(HiGHS.Optimizer)` directly). `select_optimizer(::MILP)` in `src/solver/factory.jl:97-102` is the only concrete-solver naming site (HiGHS). K defaults to 4 (`build_master_integer(; K::Int = 4, ...)`). `MILP <: ProblemClass` pre-existed (D-09 correctly not adding a new one — confirmed no new `ProblemClass` subtype was added). `test/test_solver_factory_milp.jl` proves a standalone knapsack solves exactly via this seam. |
| 2 | INT-02: Convergence driven by genuine Laporte–Louveaux cuts over raw binaries; LP cuts retained; no-good only as anti-stall fallback, never the convergence argument; iteration behavior re-measured | ✓ VERIFIED | `add_ll_cut!` (`master_integer.jl:432-451`) writes the cut over `master.b` (raw binaries) exclusively — `master.y_inv` is never read inside it (grep-confirmed). `add_optimality_cut!`/`add_feasibility_cut!` are reused verbatim (GBD convexity argument documented). `add_nogood_cut!` fires only from `apply_integer_cuts!`'s genuine-stall branch (D-16); certified run reports `converged_via = :clean`, `nogood_count = 0` (independently re-run, see below). Exhaustive 256-pair (16 incumbents × 16 corners) tightness/slackness proof in `test/test_planning_master_integer.jl` plus a real JuMP re-optimize reinforcement check. Iteration count (9, well inside `max_iter=50`) is a measured, reported number from this phase's own certification, not inherited. |
| 3 | INT-03: Certified on a tiny instance against an independent oracle (exhaustive enumeration); BilevelJuMP unavailability documented as non-blocker | ✓ VERIFIED | `test/test_planning_certification_integer.jl`'s `EnumerateLatticeOracle` `@testmodule` enumerates all `2^K = 16` lattice points (`for i in 0:(n-1)`) via REAL `solve_follower!`/`solve_planning_oracle!` production calls (no closed-form, no sampling). `@test length(enum_result.all_totals) == 16`. Certified run's `result.UB` matches `enum_result.best_total` to `atol=1e-6` (measured machine-precision agreement, ~1.6e-16, per the file's own commentary). D-15 certificate 1 (per-cut LL validity against the true enumerated optimum, `violations` list empty) and certificate 2 (continuous-relaxation lower bound + lattice-neighbor bracket of the continuous golden `y=0.7`) are both genuine `@test`s, not `@test_broken`. D-11/D-10 BilevelJuMP unavailability is documented in the file header with a specific, verified technical reason (StrongDualityMode/ProductMode reject `ZeroOne`; BigMMode hits the pre-existing MIQP `OTHER_ERROR` regression already asserted elsewhere) — correctly scored as a non-blocker, not a gap. |
| 4 | INT-04: PVAL-04 guard scoped (not deleted) — registry exemption for the lifted builder only, unmodified guard still green for every non-lifted builder, live-executed literate page | ✓ VERIFIED | `test/test_planning_noninteger.jl` registers `build_master_integer` (source-scan tripwire requires it — confirmed unweakened: the recursive `walkdir` + docstring-aware regex + exported-symbol semantic channel is untouched), places it on a self-verifying `EXEMPT` set (`@test EXEMPT ⊆ Set(keys(registry)) || error(...)`), and asserts it genuinely contains binaries (`@test !isempty(offenders)` — a verified statement, not a blind skip) while the other 4 registry entries (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`) still run the ORIGINAL, unmodified `@test isempty(offenders)` no-binaries assertion. `docs/literate/integer_investment.jl` (490 lines) calls `build_master_integer`/`solve_stackelberg!` live and is wired into `docs/make.jl`'s `Literate.markdown` loop and the `"Planning"` pages tree as "Rung 11"; zero `TODO`/`FIXME`/`XXX`/`TBD`/placeholder markers found by direct grep. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/planning/master_integer.jl` | `BendersMasterInteger`/`build_master_integer`/`add_ll_cut!`/`add_nogood_cut!`/`apply_integer_cuts!` | ✓ VERIFIED | 615 lines; all functions present, exported, exercised by tests; read in full |
| `src/planning/benders.jl` | `master=nothing`/`known_optimum` injection seam, `corner_recourse`, `ll_cut_recourse`, `nogood_count`/`converged_via` on the return NamedTuple | ✓ VERIFIED | 662 lines; mutual-exclusivity guards present (`master`/`master_kwargs`, `follower`/`follower_kwargs`); `converged_now` is a genuine exclusive branch (`known_optimum === nothing ? (gap <= tol) : isapprox(...)`), never `\|\|` — confirmed by direct code read at line ~619 |
| `src/planning/trace.jl` | Additive `nogood_count_trace` column, `total_nogoods` in `trace_summary` | ✓ VERIFIED | Guard rejects negative values; omitted keyword records `0`; both behaviors independently test-passed in this session's run |
| `src/solver/factory.jl` | `select_optimizer(::MILP)` with `mip_rel_gap=>0.0`, HiGHS behind the seam | ✓ VERIFIED | `mip_feasibility_tolerance => 1e-9` also present (gap-closure fix), documented with a forward-compatibility warning (WR-03 fix) |
| `test/test_planning_noninteger.jl` | PVAL-04 guard extended with EXEMPT scoping | ✓ VERIFIED | Read in full; tripwire logic unmodified in substance |
| `docs/literate/integer_investment.jl` | Live-executed literate rung page | ✓ VERIFIED | 490 lines; calls live `solve_stackelberg!`/`build_master_integer`; wired into `docs/make.jl` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `solve_stackelberg!` | `BendersMasterInteger` | `master=` injection kwarg | WIRED | Mutual-exclusivity guard against `master_kwargs`; default path (`master=nothing`) rebuilds `build_master` unchanged |
| `solve_stackelberg!` optimality branch | `apply_integer_cuts!` | generic dispatch (`::BendersMaster` no-op vs `::BendersMasterInteger` real) | WIRED | Confirmed via `test_planning_benders_integer.jl`'s smoke test and the certification test's cut-count assertions |
| `apply_integer_cuts!` | `add_ll_cut!` / `add_nogood_cut!` | direct calls, gated by `stalled` | WIRED | `add_ll_cut!` unconditional every optimality iteration; `add_nogood_cut!` only on genuine stall |
| `docs/make.jl` | `docs/literate/integer_investment.jl` | `Literate.markdown` loop + `"Planning"` page tree entry | WIRED | Grep-confirmed both entries present |
| `test_planning_noninteger.jl` registry | `build_master_integer` | EXEMPT allowlist | WIRED | Self-verifying (`EXEMPT ⊆ registry keys`), tripwire discovers it independently via source-scan |

### Behavioral Spot-Checks / Independent Test Execution

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All Phase-24 `@testitem`s pass under the real TestItemRunner gate | `test/runtests.jl` temporarily filtered to Phase-24 test files, `julia --project=. -e 'import Pkg; Pkg.test()'`, then restored | `413 passed, 413 total, "Testing TSODSO tests passed"` | ✓ PASS (independently executed by this verifier, not copied from SUMMARY/REVIEW-FIXES) |
| `master.jl` untouched since before Phase 24 | `git log --oneline -- src/planning/master.jl` | Last commits are Phase 11/12 (`5f4c8e6`, `a71b266`, `afb00e5`) | ✓ PASS |
| No debt markers in phase-24 files | `grep -nE "TBD\|FIXME\|XXX"` across all 12 touched files | zero matches | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| INT-01 | 24-01 | Binary-expansion HiGHS MILP master behind `select_optimizer` | ✓ SATISFIED | See Truth #1 |
| INT-02 | 24-02, 24-03, 24-04, 24-05.1 | Laporte–Louveaux cuts drive convergence; no-good only anti-stall; re-measured behavior | ✓ SATISFIED | See Truth #2 |
| INT-03 | 24-05 | Certified against exhaustive enumeration; BilevelJuMP non-blocker documented | ✓ SATISFIED | See Truth #3 |
| INT-04 | 24-02, 24-06 | PVAL-04 scoped not deleted; live literate page | ✓ SATISFIED | See Truth #4 |

No orphaned requirements found in `.planning/REQUIREMENTS.md` for this phase beyond INT-01..04.

### Anti-Patterns Found

None. Zero `TODO`/`FIXME`/`HACK`/`PLACEHOLDER`/`TBD`/`XXX` markers in any of the 12 files this
phase touched. The code-review process (24-REVIEW.md) found one CRITICAL (CR-01) and four
WARNING-level defects during standard-depth review; all five were independently confirmed FIXED
by direct code inspection during this verification (`corner_recourse`'s `y_inv<=0` branch now
genuinely calls `Qfun(0.0)`; the WR-01 ternary-search tie-break shrinks from the right on a
double-Inf tie with a loud `isfinite` guard; `stall_z_atol` now scales with the lattice step;
`enumerate_lattice` is consolidated into a single `@testmodule`; the MILP factory carries a
forward-compatibility comment). Two INFO items from the original review were not independently
re-verifiable (the review-fixer's own report notes `24-REVIEW.md` had gone missing from the
worktree by the time fixes were applied, so their text could not be recovered) — these are
INFO-severity by the original review's own classification, non-blocking, and not required
must-haves for this phase's goal.

### Human Verification Required

None required to certify the phase goal. All four success criteria are backed by automated,
independently-re-run tests plus direct source inspection (no UI, no external service, no visual
judgment call). One item is noted for completeness rather than as a gap:

1. **Rendered Documenter HTML output for the new "Rung 11" page** — not visually inspected in
   this verification (nor was a full `julia --project=docs docs/make.jl` site build run in this
   session or, per 24-06-SUMMARY.md, in the phase's own closing session). The page's actual Julia
   code was, however, confirmed to execute for real: it calls the live production
   `build_master_integer`/`solve_stackelberg!` entrypoints (grep-confirmed at lines 289/403/413),
   and 24-06-SUMMARY.md documents an independent `Literate.script` extraction + direct
   `julia --project=.` execution of the extracted script before commit — the code-execution risk
   is covered; only the final rendered-markdown/HTML formatting is unverified. Optional: run
   `julia --project=docs docs/make.jl` and open `docs/build/generated/integer_investment.html` to
   confirm formatting/cross-references render as intended.

### Gaps Summary

No gaps. All four Phase 24 requirements (INT-01..04) and all four ROADMAP.md success criteria
are genuinely implemented, correctly scoped per the 16 locked CONTEXT.md decisions (D-01..D-16),
and independently re-verified against the codebase and a live test run by this verification pass
— not accepted on SUMMARY.md's word. The one prior CRITICAL code-review finding (CR-01) and four
WARNINGs were all independently confirmed fixed in the shipped source. The BilevelJuMP secondary
oracle's documented unavailability (D-10/D-11) and the deferred large-lattice termination
criterion (D-14) are explicitly out of scope for this phase per CONTEXT.md and are not scored as
gaps.

---

_Verified: 2026-08-24T01:15:00Z_
_Verifier: Claude (gsd-verifier)_
