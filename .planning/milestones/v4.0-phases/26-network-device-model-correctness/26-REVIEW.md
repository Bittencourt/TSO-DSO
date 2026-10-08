---
phase: 26-network-device-model-correctness
reviewed: 2026-09-29T03:12:40Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - src/admm/solve_admm.jl
  - src/admm/DsoOpt.jl
  - src/experiments/run.jl
  - src/experiments/store.jl
  - src/devices/Interruptible.jl
  - test/test_pricing_dlmp.jl
  - test/test_aggregator.jl
findings:
  critical: 0
  warning: 0
  info: 3
  total: 4
status: clean
---

# Phase 26: Code Review Report (re-review, iteration 2)

**Reviewed:** 2026-09-29T03:12:40Z
**Depth:** standard
**Files Reviewed:** 7 (the fix-touched files from iteration 1: WR-01 commit `d05ff62`, WR-02
commit `d61ed2e`, WR-03 commit `da7824e`, WR-04 commit `70cf33c`, diffed individually against
their immediate parents, not cumulatively against `3f8bda7` — the cumulative range also contains
unrelated prior phase-26 work)
**Status:** issues_found (no BLOCKER-level defects; one new WARNING — a test-coverage gap on the
WR-01 fix itself — plus the three INFO items carried forward unchanged from iteration 1, which
were out of `fix_scope` and correctly left untouched)

## Summary

This is a targeted re-review of the four iteration-1 fixes (WR-01..WR-04), focused on whether the
fixes are genuinely correct and whether they introduced any new defect (return-tuple/struct-field
compatibility breaks, serialization regressions, constructor-arity breaks, vacuous new tests).

**WR-01 (thread resolved `reactive_consensus_mode` through `solve_admm` → `ScenarioResult` →
`store.jl`) — verified correct, no new defect, but no committed test covers it:**
- `solve_admm`'s return value is a `NamedTuple`; the new `reactive_consensus_mode` key is
  additive. Grepped every call site in `src/`, `test/`, `scripts/`, `docs/literate/` (24 call
  sites) — every one binds the whole result to a single identifier and reads fields by name
  (`r.welfare`, `res.dadp`, etc.); none destructures positionally, so the new key cannot break
  any caller.
- `ScenarioResult`'s new field is inserted in the struct definition in the same position it is
  passed in the single positional constructor call in `run.jl` (`src/experiments/run.jl:179-190`)
  — verified by direct read, both in the field list and the constructor argument list, they
  agree. Grepped for any other `ScenarioResult(...)` construction site — none exists, so no
  positional-arity break is possible.
- `ReactiveMode` is a plain `@enum` (`OFF`/`CERTIFIED`/`LIVE`), which round-trips through
  `@tagsave`/`wload` (JLD2) without issue — confirmed empirically (see below), not merely by
  code inspection.
- `sweep.jl`'s `collate_summary` does not include `reactive_consensus_mode` in its explicit
  `keep` column list, so it is silently dropped from the collated CSV — this is pre-existing
  `select`/`intersect` behavior (adding an unlisted column never breaks `select`), not a
  regression, and is out of this fix's stated scope.
- **Empirically re-verified end-to-end** (not just re-read): ran a live `Scenario(...;
  feeder=:ieee13, strategy=:admm, T=24)` through `run_scenario` — resolved
  `reactive_consensus_mode == LIVE` (IEEE-13's default population includes flexible loads) and
  round-tripped correctly through `result_to_dict` and a real `run_and_store` → JLD2 write (only
  pre-existing, unrelated `JLD2 Symbol-key→String` conversion warnings appeared; no error). See
  WR-05 (new finding) below — this exact path has zero *committed* test coverage.

**WR-02 (new `@testitem` for the `:smax_rev`-binding regime) — verified NOT vacuous:**
Reproduced the entire test body as a standalone script against a live `solve_welfare` solve:
`mag_fwd ≈ 2.76e-10`, `mag_rev ≈ 5.39` (receiving-end cone binds, sending-end slack, exactly the
calibration the test claims), and the load-bearing assertion
`cong_from_smax_rev > 100 * cong_from_smax` genuinely holds against real `dual(...)` reads, not a
stubbed/mocked context. The test is a real regression, not a tautology.

**WR-03 (`Interruptible` gets a `φ::Union{Nothing,T}` field) — verified no arity break:**
Grepped every `Interruptible(...)` construction site in `src/`, `test/`, `scripts/`,
`docs/literate/` (13 sites) — all are 5-positional-argument calls; the new `φ` is a keyword-only
argument with a `nothing` default on both the inner and outer constructors, so no existing call
site's positional arity is affected. Re-ran the new override test logic live (own script, not just
re-reading `test_aggregator.jl`): `Interruptible(...; φ=0.75).φ == 0.75`, and the `(0,1]` guard
correctly throws `ArgumentError` for `φ=0.0`/`φ=1.5`. `Aggregator.contribute!`'s
`hasproperty(d, :φ) && d.φ !== nothing` lookup requires no code change to pick up the new field
(confirmed by reading `Aggregator.jl` — the guard is structural, not a device-type enumeration).

**WR-04 (docstring/error-message wording fix in `DsoOpt.jl`) — confirmed doc-only:**
`git diff` of this commit against its parent touches only comment/docstring text in
`build_dso_opt`'s docstring; the runtime guard condition (`if mode != LIVE`, comparing the
*normalized* value) is byte-identical before and after. No functional risk.

No BLOCKER-level defect was found in any of the four fixes. One new WARNING is raised below
(missing regression coverage for the WR-01 fix itself). The three iteration-1 INFO items (IN-01
through IN-03) were correctly left untouched (out of `fix_scope = critical_warning`) and are
carried forward unchanged for visibility.

## Warnings

### WR-05: The WR-01 fix (`reactive_consensus_mode` provenance threading) has zero committed regression coverage

**File:** `test/test_experiments.jl:52-69` (existing `"EXP-01 scenario admm"` item),
`src/experiments/run.jl`, `src/experiments/store.jl`, `src/admm/solve_admm.jl`

**Issue:** The WR-01 fix added a new field end-to-end (`solve_admm`'s return tuple →
`ScenarioResult.reactive_consensus_mode` → `result_to_dict`'s provenance dict) specifically to
close a reproducibility gap. The iteration-1 fix report (`26-REVIEW-FIX.md`) states this was
verified via ad-hoc scripts run during the fix session, but no `@testitem` was added asserting
any of: (a) `run_scenario(s).reactive_consensus_mode` is populated (not `missing`) for an
`:admm` `Scenario`, (b) it is `missing` for `:centralized`, or (c) `result_to_dict`/
`run_and_store`'s saved JLD2 actually carries the key. The existing `"EXP-01 scenario admm"`
item in `test/test_experiments.jl` (the natural home for this assertion — it already runs
`run_scenario` on an `:admm` `Scenario` and checks several other result fields) does not
mention `reactive_consensus_mode` at all, and the existing `"INFRA-04 provenance tagsave"` item
only exercises the `:centralized` strategy (where the field is trivially `missing`), so it
provides no coverage either. A future refactor of `solve_admm`'s return tuple or
`ScenarioResult`'s field list could silently drop or rename this field with no test failing —
exactly the kind of silent regression WR-01 itself was fixing (a "reproducible... every model
assumption documented" gap, now on the fix's own new contract instead of the original one). I
independently re-verified the fix is currently correct by running it live end-to-end (see
Summary above), but that verification is not preserved as a repeatable test.

**Fix:** Add two assertions to the existing `"EXP-01 scenario admm"` `@testitem`
(`test/test_experiments.jl:52-69`) — `@test r.reactive_consensus_mode isa TSODSO.ReactiveMode`
after the existing block — and a `@test ismissing(r.reactive_consensus_mode)` in the sibling
`":centralized"` item (`test/test_experiments.jl:26-50`). Optionally extend
`"INFRA-04 provenance tagsave"` with an `:admm`-strategy sub-case asserting the saved JLD2's
`wload`ed dict has a `"reactive_consensus_mode"` key.

## Info (carried forward from iteration 1, unchanged — out of `fix_scope`, not re-verified further)

### IN-01: `RestrictedBranchFlow.jl`'s `_EXACT04_MEASURED_ε` carries three superseded numeric values in one comment block

**File:** `src/powerflow/RestrictedBranchFlow.jl:61-89`

**Issue:** The comment above `_EXACT04_MEASURED_ε` accumulates the full re-measurement history
across three phases in one block; a future reader must parse ~30 lines of historical narrative to
identify which of the three numbers is currently load-bearing.

**Fix:** Move the historical re-measurement narrative to the SUMMARY docs it already references,
leaving only the current provenance inline.

### IN-02: `decompose_dlmp` assumes but never asserts that `:smax` and `:smax_rev` share identical (branch, time) key sets

**File:** `src/pricing/dlmp.jl:288-295,315-317`

**Issue:** `smaxkeys` is built once from `:smax` and reused unchanged for `:smax_rev`, on the
assumption both were registered under the identical filter predicate. True today, but unasserted
— a future divergent registration would silently read `0.0` rather than throwing (likely still
caught downstream by the hard sum-to-price assertion, so this is defence-in-depth, not an
exploitable defect).

**Fix:** Build `smaxkeys` from `union(eachindex(smax), eachindex(smax_rev))`, or assert the two
key sets are equal when `smax_rev !== nothing`.

### IN-03: `test_thesis_repro.jl`'s IEEE-123 golden band was not re-derived after phase 26's physics fixes

**File:** `test/test_thesis_repro.jl:19-22,64-68`

**Issue:** `DSO_BAND_HI = 7.211125525764296` predates phase 26's FIX-01 through FIX-05; the band
is wide enough to still pass, but its provenance comment reads as if the number reflects current
model physics, when it does not (deferred to Phase 28 per CONTEXT.md).

**Fix:** Add a one-line note cross-referencing this as an open item for Phase 28's restatement.

---

_Reviewed: 2026-09-29T03:12:40Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2 (re-review of WR-01..WR-04 fixes from 26-REVIEW-FIX.md)_

---

## Iteration 3 (orchestrator re-review)

WR-05 resolved by `c7aa143` (two assertions in existing `EXP-01 scenario centralized/admm` testitems, verified by direct-script reproduction). No new defects. Remaining: IN-01..IN-03 (info, out of fix scope). Post-fix full suite at `9d00b82`: 30213 pass / 0 fail / 0 error / 5 broken (exit 0).
