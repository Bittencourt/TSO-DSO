---
phase: 20-overvoltage-capable-relaxation
plan: 01
subsystem: SOC-relaxation exactness theory / AC oracle post-processing
tags: [OVR-01, gan-low, socp-exactness, ac-oracle, measurement]
dependency-graph:
  requires: []
  provides:
    - "recover_lossfree_shadow_voltage(ctx) -> Matrix{Float64} (src/models/ac_oracle.jl)"
    - "measured ε_measured = 0.005811069127373614 on the EXACT-04 fixture"
    - "numerically-confirmed v ≥ v̂ (RESEARCH.md Assumption A1)"
  affects:
    - "plan 20-02 (RestrictedBranchFlow default shrink kwarg)"
tech-stack:
  added: []
  patterns:
    - "pure post-processing function over an already-solved ModelContext (no new JuMP var, no solve)"
    - "BFS-rooted subtree loss accumulation (reverse-BFS bottom-up, then top-down forward recursion)"
key-files:
  created:
    - test/test_restricted_branch_flow.jl
  modified:
    - src/models/ac_oracle.jl
decisions:
  - "RESEARCH.md's 'Measuring ε' pseudo-code stated the accumulated-loss sign/inclusion backwards relative to this project's actual :Rp/:Rq balance convention (loss charged at child); re-derived the correct relationship directly from the balance recursion and implemented that instead (Rule 1 auto-fix bug), validated by the Lemma 1 sanity check (v̂_GL ≥ v everywhere) passing"
metrics:
  duration: "~35 minutes"
  completed: "2026-08-08"
---

# Phase 20 Plan 01: v ≥ v̂ Spot-Check + Gan-Low ε Measurement Summary

Numerically confirmed RESEARCH.md Assumption A1 on the EXACT-04 fixture (mingap = 0.0, i.e.
v ≥ v̂ holds with equality at the over-voltage bound) and measured the Gan-Low "modification
gap" ε = 0.005811069127373614 via a new `recover_lossfree_shadow_voltage` post-processing
helper — the prerequisite gate and the measured default plan 20-02's `RestrictedBranchFlow`
needs.

## Measured Values (for plan 20-02)

**These are the load-bearing numbers this plan exists to produce — record verbatim.**

| Quantity | Value | Source |
|----------|-------|--------|
| `mingap` (Task 1, RESEARCH Assumption A1 spot-check) | **0.0** | `test/test_restricted_branch_flow.jl`, first `@testitem`, on the EXACT-04 fixture (`high_pv_feeder()`, `pv_scale=1.2`) |
| `ε_measured` (Task 2, Gan-Low modification gap, Definition 3/eq. 18) | **0.005811069127373614** | `test/test_restricted_branch_flow.jl`, second `@testitem`, `ACPowerFlow()` solve on the same EXACT-04 fixture |

**Verdict on RESEARCH.md Assumption A1: CONFIRMED, not falsified.** `mingap = 0.0` means
`v[j,t] - v̂[j,t] = 0` at the binding hours on this fixture (both the true voltage and the
existing thesis exactness-copy shadow are pinned at the same value in the over-voltage regime)
— consistent with, and slightly stronger than, the derived `v ≥ v̂` inequality. The plan
proceeded past Task 1's gate as instructed (no contradiction found, no checkpoint needed).

`ε_measured` is a **pre-safety-multiplier** point estimate (RESEARCH.md D-03: a single
AC-oracle-solved point on the EXACT-04 fixture, no bisection/search). Plan 20-02 is expected to
apply a documented safety multiplier (RESEARCH.md suggests 1.1×–1.5×, mirroring this project's
`DSO_BAND_HI = 1.5 × max|dso|` precedent) on top of this exact value, citing this plan's second
`@testitem` as provenance.

## What Was Built

### Task 1 — `v ≥ v̂` sign-relationship spot-check (RESEARCH Assumption A1)

New `test/test_restricted_branch_flow.jl` with a `@testitem` tagged `:restricted_branch_flow`
that solves `ConvexBranchFlow()` on the EXACT-04 fixture (`Phase4Fixtures.high_pv_feeder()`,
`pv_scale = 1.2`) with the diagnostic `rtol_exact = 1.0` override (same pattern
`test_ac_oracle.jl`'s EXACT-04 item uses), reads `v`/`v̂` off the solved context, and asserts
`min(v - v̂) >= -1e-9` across every bus/hour. This is the BLOCKING analytic gate RESEARCH.md
requires before any restriction code exists — it passed (`mingap = 0.0`), so the plan proceeded.

### Task 2 — `recover_lossfree_shadow_voltage` + measured ε

New exported function `recover_lossfree_shadow_voltage(ctx::ModelContext) -> Matrix{Float64}`
in `src/models/ac_oracle.jl`, positioned immediately after `recover_voltage_angles` and before
`assert_ac_exact!` (mirroring that function's docstring shape and pure-post-processing
contract: reads `ctx.meta[:feeder]`/`[:T]`/`[:pf_vars]` only, creates no JuMP variable, invokes
no solver). It computes Gan, Li, Topcu & Low's (2015) loss-free "shadow" squared voltage
`v̂_GL(s)` (Definition 3 / eq. 18) via a BFS-rooted parent/child tree, a reverse-BFS closed-
subtree loss accumulation, and a top-down forward recursion.

A second `@testitem` in `test/test_restricted_branch_flow.jl` solves `ACPowerFlow()` (a
genuine AC-feasible point) on the same EXACT-04 fixture, calls
`TSODSO.recover_lossfree_shadow_voltage(ctx_ac)`, sanity-checks Lemma 1 (`v̂_GL ≥ v`
everywhere — the OPPOSITE sign from Task 1's `v ≥ v̂`, confirming the two shadows are distinct
mechanisms), and asserts the measured `ε_measured > 0.0`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected RESEARCH.md's "Measuring ε" pseudo-code sign/inclusion convention**

- **Found during:** Task 2, first verification run — the Lemma 1 sanity assertion
  (`v̂_GL ≥ v`) FAILED with `minimum(...) = -0.005811069127373614` (a real, non-noise-scale
  violation, not a `-1e-9`-level numerical artifact).
- **Issue:** RESEARCH.md's "Measuring ε" section states `P̌[b] = P[b] + AccumLossR[to]` where
  `AccumLossR[j] := Σ` over branches STRICTLY downstream of `j` (excluding the branch entering
  `j` itself). Re-deriving this project's actual `:Rp`/`:Rq` balance recursion directly
  (`pin[j] - pout[j] = -inj[j]`, loss charged at the child per `ConvexBranchFlow.jl`'s own
  documented convention) shows the correct relationship telescopes to
  `P̌[b] = P[b] - LossInclR[i]`, where `LossInclR[i]` is the total `r·ℓ` over the CLOSED subtree
  rooted at `i` — INCLUSIVE of the branch feeding `i` from its parent, not exclusive of it — and
  with a MINUS sign, not a plus.
- **Fix:** Implemented the corrected formula (minus sign, inclusive accumulation) in
  `recover_lossfree_shadow_voltage`, with the full derivation documented in the function's
  docstring (including the balance-recursion unrolling that shows the sign/inclusion must be
  this way, independent of the sign convention chosen for `inj[j]`).
- **Verified:** Re-ran both verification commands after the fix — Lemma 1 now holds exactly at
  the magnitude the bug had gotten backwards (`minimum(v̂_GL - v) = 0.0 ± ~1e-16`,
  `ε_measured = +0.005811069127373614`, the exact negation of the pre-fix failure value,
  confirming the fix is a pure sign/inclusion correction and nothing else changed).
- **Files modified:** `src/models/ac_oracle.jl`
- **Commit:** `9a5bb78` (folded into Task 2's commit; the bug was caught and fixed within the
  same task before committing, so no separate fix-commit was needed)

### Minor Task-Boundary Note (not a deviation from functionality)

Both `@testitem`s were authored into `test/test_restricted_branch_flow.jl` in a single `Write`
during Task 1 (the file did not yet exist, so it was natural to draft both items' final shape
at once). Task 1's commit therefore already contains the SOURCE TEXT of Task 2's second
`@testitem` (which calls `TSODSO.recover_lossfree_shadow_voltage`, not yet defined at that
commit) — harmless because `@testitem` bodies are inert until executed by the test runner, and
Task 1's own verification command (a standalone `julia --project=.` script, not the
`@testitem` itself) never touches that second item. Task 2's commit then added only
`src/models/ac_oracle.jl`. Both tasks' individual `<verify>` commands and `<acceptance_criteria>`
passed independently; the final full-suite run confirms both `@testitem`s pass together.

## Verification

- Task 1 quick-check (`julia --project=.` inline script): PASSED, `mingap = 0.0`.
- Task 2 quick-check (`julia --project=.` inline script): PASSED after the Rule 1 fix,
  `ε_measured = 0.005811069127373614`.
- `isdefined(TSODSO, :recover_lossfree_shadow_voltage)`: PASSED.
- Export-line acceptance criteria (`grep` checks for the replaced export line and the new
  export presence): PASSED.
- Full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`, background, ~13 min):
  **2518 passed / 0 failed / 3 broken** — matches the reference green baseline
  (2513 passed / 0 failed / 3 pre-existing broken) plus the 5 additional assertions this
  plan's two new `@testitem`s contribute. No other test file was touched; `test_ac_oracle.jl`'s
  own items remain green in the same run (confirmed no regression, including its own EXACT-04
  item).

## Known Stubs

None — both new pieces of code (`recover_lossfree_shadow_voltage`, the two `@testitem`s) are
fully wired to real, already-existing infrastructure (`ACPowerFlow`, `ConvexBranchFlow`,
`Phase4Fixtures`) with no placeholder data paths.

## Self-Check: PASSED

- `test/test_restricted_branch_flow.jl` exists: FOUND.
- `src/models/ac_oracle.jl` contains `function recover_lossfree_shadow_voltage`: FOUND
  (verified via `grep`, positioned before `assert_ac_exact!`).
- Commit `a5323ac` (Task 1) exists in `git log`: FOUND.
- Commit `9a5bb78` (Task 2) exists in `git log`: FOUND.
