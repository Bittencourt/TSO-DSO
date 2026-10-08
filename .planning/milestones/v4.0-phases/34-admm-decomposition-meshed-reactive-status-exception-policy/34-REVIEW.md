---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
reviewed: 2026-10-04T00:00:00Z
depth: standard
iteration: 2
files_reviewed: 29
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: issues_found
---

# Phase 34: Code Review Report (iteration 2)

WR-01..WR-04 from iteration 1 (see 34-REVIEW.iter1.md) are fixed correctly and completely
(commits 4a77eb7, 5381651, 0e0cd91, b8556b6). No regressions; no numeric SOCP path changed; no
golden/canary touched.

## Info

### IN-06: Stale docstrings still say ErrorException
`src/planning/ac_recheck.jl:63`, `src/experiments/mpc_loop.jl:144,1561`, `src/planning/benders.jl:813` —
these sites now throw `SolveFailedError`. Fix: update the docstrings.

### IN-07: WR-04 test cannot fail on the 4Q behaviour
`test/test_admm_generic_pf.jl` — fixture has no 4Q device. Fix: FourQuadBESS fixture with forced
simultaneous charge/discharge; assert warn with `report_4q=true`, `CertificateError` with `false`.

### IN-08: fit_baseline SITE 2 AC-PF failure still plain ErrorException (carried from IN-03)
`src/pricing/fit.jl:612` (+ `benders.jl:590,680`). Fix: migrate to `SolveFailedError(msg, model)` or
list in `docs/src/status_policy.md`'s deferral inventory.
