---
phase: 35-ieee-8500-scale-after-refactor
verified: 2026-10-05T05:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 35: IEEE-8500 Scale After Refactor Verification Report

**Phase Goal:** Researcher can trust the IEEE-8500 performance/memory characterization after the orchestration refactor.
**Status:** passed (one WARNING, no blockers)
**Re-verification:** No

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Final consolidation `assert_socp_exact!` behaves correctly at 8500 scale (no spurious throw). Per user decision: honest refusal when the gap is genuine. | VERIFIED | `atol_exact::Union{Nothing,Real} = nothing` in `src/admm/solve_admm.jl:282`, `src/admm/DsoOpt.jl:566`, and threaded through `_admm_certify` (`admm_phases.jl:266,293`). `DsoOpt.jl:673` records `meta[:socp_atol_exact]`. `hybrid_diagnostic.csv`: worst branch L2916620->N1136366 (r_pu 2.4e-6), gap 1.2e-4 against atol_b 2e-7, ratio 569, loss impact ~3e-10 to 4.4e-9 pu. This is a genuine cone gap, not spurious. The gate semantics are unchanged. The head row in `density_sweep.csv` records `ERROR:CertificateError` plus the `DIAGNOSTIC_BYPASS` row (8 iterations). |
| SC1b | Proof tests exist | VERIFIED | `test/test_admm_exactness_default.jl` has: smax=90 passes under hybrid and throws under flat 1e-6 (A); near-zero-r negative test throws `CertificateError` (N); default equals `nothing` plumbing (B, WR-06); `solve_dso!` final gate (WR-06); `hybrid_ratios` diagnostic. |
| SC2 | Converged memory-feasible headline point measured, or memory wall re-characterized honestly | VERIFIED (re-characterization branch) | ADMM converged at d=0.1 T=10 (8 iterations, 5.92 GiB peak) and ran to completion at T=24 (11.52 GiB, 678 s). d=0.25 T=24 was earlyoom-killed at 10.4 GiB anon RSS. `memory_wall_recharacterization.csv` (7 rows) holds the Phase 25 baseline, the death point, and the delta. `point_resources.csv` holds peak RSS, `oom_source` and host load. The certificate refuses prices at both completed points, so there is no price-certified headline point. The honest refusal is the documented outcome, and the re-characterization branch is satisfied. |
| ARCH-10 | Requirement accounted for | VERIFIED | Declared in plans 01-05. REQUIREMENTS.md:124 `[x]`, :201 "Phase 35 Complete". No orphaned IDs. |

**Score:** 4/4

## Regression Gate (re-run after review-fix changes to src/)

Full `Pkg.test()` launched detached on a quiet machine (no other julia process, no worktrees):

- **32177 passed, 0 failed, 0 errored, 5 broken** (total 32182, 26m57s). This is above the earlier 32157 baseline and has no regressions.
- The two known Aqua false failures did not appear in this run.
- The knife-edge canary (`test_admm_knifeedge_canary.jl`, iters=56, welfare=-4823.66604824162) is part of the suite and passes, so it is unchanged. I did not separately read the canary values from the log.

## Anti-Patterns

No unreferenced TBD/FIXME/XXX in the modified src, scripts or docs files. The one `XXXX` hit is a termination-status format comment.

## Warnings (non-blocking)

1. `.planning/STATE.md:103` still says "dominant consumer is per-hour DSO solver state retained across the ADMM loop (~linear in T)". Review-fix WR-01 downgraded this to an unattributed hypothesis in the docs and CSV, so the status note is stale.
2. `density_sweep.csv` keeps a `started` row for d=0.25 T=24 with empty fields, because the process was killed. It is explained in `memory_wall_recharacterization.csv`.
3. Review IN-08 is still open: `hybrid_diagnostic.csv` has no `admm_status` column, and the non-converged stale-row removal is untested.
4. `docs/src/generated/ieee8500_scaling.md` is gitignored, so it is generated and untracked. The CONTEXT note about a "tracked" copy no longer holds. The source `docs/literate/ieee8500_scaling.jl` has the "Post-refactor measured results (Phase 35)" section.

## Human Verification

None required.
