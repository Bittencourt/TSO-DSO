---
phase: 26-network-device-model-correctness
fixed_at: 2026-09-29T00:00:00Z
review_path: .planning/phases/26-network-device-model-correctness/26-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 26: Code Review Fix Report

**Fixed at:** 2026-09-29T00:00:00Z
**Source review:** .planning/phases/26-network-device-model-correctness/26-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (`fix_scope = critical_warning`): 4 (WR-01, WR-02, WR-03, WR-04; REVIEW.md
  reported 0 critical findings, so no CR-*/BL-* items existed to fix)
- Fixed: 4
- Skipped: 0
- Out of scope (not attempted, per `fix_scope`): IN-01, IN-02, IN-03 (Info-tier)

All four fixes were applied in an isolated git worktree/branch
(`gsd-reviewfix/26-2399363`), each verified against the actual current source (re-read before
editing) and each committed atomically. Verification used direct `julia --project=.` scripts
reproducing the relevant code paths and/or new `@testitem` bodies (never TestItemRunner under
`--project=.` — see the `gsd-plan-verify-testitemrunner-trap` project memory), since
TestItemRunner is a test-only dependency that does not resolve there. No pinned/golden values
were changed by any of the four fixes.

## Fixed Issues

### WR-01: PM-03's smart `reactive_consensus` default is invisible to experiment reproducibility metadata

**Files modified:** `src/admm/solve_admm.jl`, `src/experiments/run.jl`, `src/experiments/store.jl`
**Commit:** `d05ff62`
**Applied fix:** Threaded the RESOLVED `reactive_consensus` mode (`mode`, already computed once
near the top of `solve_admm`) back out into `solve_admm`'s return `NamedTuple` on BOTH the
`:converged` and `:budget_exceeded` return paths (new key `reactive_consensus_mode`). Added a
matching `reactive_consensus_mode::Union{Missing,ReactiveMode}` field to `ScenarioResult`
(`missing` for `:centralized`, the resolved `ReactiveMode` for `:admm`), wired it through
`run_scenario`'s dispatch, and stamped it into `result_to_dict`'s provenance dict in `store.jl`
so an on-disk `run_and_store` artifact is now self-describing even when the PM-03 smart default
resolved silently. Verified no existing call site of `ScenarioResult(...)` or `result_to_dict`
needed further changes (single construction site; no full-struct equality tests; no JLD2
round-trip back into `ScenarioResult` exists in this codebase, so the additive struct field is
safe). Verified via a direct script exercising `solve_admm` at both the smart-default-OFF and
explicit-`:live` paths, and a second script reproducing the "EXP-01 scenario centralized/admm"
`@testitem` bodies plus `result_to_dict`/`run_and_store` round-trips — all assertions passed.

### WR-02: `decompose_dlmp`'s new `:smax_rev` congestion term has no dedicated regression exercising the receiving-end-binding regime

**Files modified:** `test/test_pricing_dlmp.jl`
**Commit:** `d61ed2e`
**Applied fix:** Added a new `@testitem` combining a calibrated PV-back-feed 2-bus fixture (real
`solve_welfare` + `Aggregator` + `PVBattery`, since `decompose_dlmp` requires an actual solved
`ModelContext` with `ctx.meta[:feeder]`, `:balance_p`, and the PF-04 exactness certificate — the
existing raw-JuMP `ConvexBranchFlow`-only FIX-03 fixture in `test_convex_branch_flow.jl` cannot
be re-used directly) with `decompose_dlmp`. The fixture was calibrated (r=x=0.05, smax=0.5,
abundant PV) so the sending-end cone (`:smax`) is essentially slack
(`mag_fwd ≈ 2.76e-10`) while the receiving-end cone (`:smax_rev`) binds (`mag_rev ≈ 5.39`),
isolating exactly the regime the finding flagged. The new item asserts (a) the hard
sum-to-nodal-price identity explicitly (belt-and-suspenders on top of `decompose_dlmp`'s own
internal assertion), and (b) that `d.congestion` is driven by the `:smax_rev` dual specifically
(`cong_from_smax_rev > 100 * cong_from_smax`), not just nonzero — mirroring the existing
ConvexBranchFlow-level `mag_rev > 100 * mag_fwd` assertion style. Verified by reproducing the
entire `@testitem` body as a direct script (all assertions pass, including the calibration
sanity checks) and by a standalone `Meta.parseall` syntax check of the modified test file.

### WR-03: `Interruptible` was converted to the flexible-load contract but does not get the same per-device `φ` override field as `Thermostatic`/`Deferrable`

**Files modified:** `src/devices/Interruptible.jl`, `test/test_aggregator.jl`
**Commit:** `da7824e`
**Applied fix:** Added the same `φ::Union{Nothing,T}` field (with the same `(0,1]` constructor
guard) to `Interruptible`, mirroring `Thermostatic`/`Deferrable` exactly — the outer constructor
gained a `φ = nothing` keyword, fully backward-compatible with every existing 5-positional-arg
call site in `src/`, `test/`, and `docs/literate/` (verified by grep: all existing call sites are
positional 5-arg calls with no keyword arguments). `Aggregator.contribute!`'s existing
`hasproperty(d, :φ) && d.φ !== nothing` lookup picks up the new field with no further code
changes needed. Added a new `@testitem` in `test_aggregator.jl` mirroring the existing
Thermostatic-override coverage: constructs an `Interruptible` with its own `φ` override inside
an `Aggregator` with a different `φ`, asserts the device's override (not `agg.φ`) drives its
`q_inject` contribution, and asserts the `(0,1]` guard rejects `φ = 0.0`/`φ = 1.5`. Verified by
reproducing all pre-existing `Interruptible` construction/guard tests (byte-identical pass) plus
the new override/guard/type-promotion behavior via a direct script, and a standalone
`Meta.parseall` syntax check of the modified test file.

### WR-04: `_any_flexible_reactive`/`build_dso_opt`'s widened reactive-decision guard message references a raw symbol `:live` that does not match the actual runtime check

**Files modified:** `src/admm/DsoOpt.jl`
**Commit:** `70cf33c`
**Applied fix:** Reworded the `build_dso_opt` docstring's "Throws" paragraph (the phrase
"combined with `reactive_consensus != :live`") to explicitly name the NORMALIZED `mode` the
runtime guard (`if mode != LIVE`, line ~319) actually compares against, and added an explicit
warning against "simplifying" the guard to a literal `reactive_consensus != :live` comparison
(which would be wrong whenever `reactive_consensus` is passed as a `Bool`/`ReactiveMode` rather
than the bare `Symbol :live`). The thrown `ArgumentError` message itself was inspected and found
to already correctly say "`reactive_consensus` normalizes to `$(mode)`" (attributing the check to
the normalized value, not the raw argument) — no change was needed there. This is a
documentation-only change; no functional code was modified. Verified via a direct script
confirming `build_dso_opt`'s guard still throws identically for an explicit `OFF` override
against a flexible-load-bearing population, plus a full-package load to confirm the docstring
itself still parses cleanly.

## Skipped Issues

None — all 4 in-scope findings (WR-01 through WR-04) were fixed. IN-01/IN-02/IN-03 were
excluded by `fix_scope = critical_warning` and were not attempted.

---

_Fixed: 2026-09-29T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
