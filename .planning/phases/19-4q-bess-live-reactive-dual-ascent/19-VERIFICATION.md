---
phase: 19-4q-bess-live-reactive-dual-ascent
verified: 2026-08-08T18:00:00Z
status: passed
score: 4/4 roadmap success criteria verified (plus 8/8 plan-level must_haves)
overrides_applied: 0
---

# Phase 19: 4Q-BESS + Live Reactive Dual-Ascent Verification Report

**Phase Goal:** A researcher can model a battery with genuine four-quadrant (P,Q) capability and
observe a live-converging reactive nodal price out of ADMM — not just the one-shot certified
dual v2.1 shipped — without touching the byte-identical default (no-4Q-BESS, no-dual-ascent)
path.
**Verified:** 2026-08-08T18:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Method

This verification did NOT rely on SUMMARY.md/REVIEW.md claims as evidence. For every roadmap
success criterion:

1. Read the actual current (post-fix, HEAD = `e58926e`) source of every file the 8 plans
   modified: `src/devices/FourQuadBESS.jl`, `src/devices/Aggregator.jl`,
   `src/devices/AbstractDevice.jl`, `src/models/complementarity_4q.jl`,
   `src/models/welfare_solve.jl`, `src/admm/ReactiveMode.jl`, `src/admm/DsoOpt.jl`,
   `src/admm/AgrOpt.jl`, `src/admm/solve_admm.jl`, `src/TSODSO.jl`.
2. Confirmed the 5 code-review fix commits (`8c7b455`/`14ed32e`, `b8b0c64`, `3866537`,
   `e304edb`, `d4364ff`) are present on the branch and that HEAD (`e58926e`) is the
   "mark review findings fixed" commit — i.e. verification ran against the fixed state, not
   the pre-fix state the review found issues in.
3. Wrote and ran two independent, throwaway Julia scripts (outside `test/`, using the
   project's own fixture modules `Phase6Fixtures`/`Phase19Fixtures` loaded directly, bypassing
   TestItemRunner per the project's documented `--project=.` incompatibility) that:
   - construct a `FourQuadBESS`, verify guard rejection, verify it composes in an
     `Aggregator` alongside `Thermostatic`/`Deferrable`/`PVBattery`;
   - run the centralized `solve_welfare` replica + `assert_4q_complementarity!` and confirm a
     PASS on a benign fixture, and a genuine THROW (plus `report=true` neutralization) on a
     synthetic 0.5·0.5 violation built directly against a solved JuMP model (not solver noise);
   - run `solve_admm(...; reactive_consensus = :live)` on the 2-bus + FourQuadBESS fixture and
     cross-validate welfare/λ/μ against the centralized solve;
   - run two `:live` solves differing only in the random seed feeding the aggregator profile,
     to prove the μ-ascent mechanism is genuinely live (not a no-op);
   - run `solve_admm` with `reactive_consensus` omitted vs. explicitly `false` on a
     non-4Q aggregator set, and confirm byte-identical welfare and `mu_q === nothing`;
   - confirm the WR-04 fail-loud guard actually throws `ArgumentError` when a `FourQuadBESS`
     is present under `OFF`.

All six checks passed with concrete measured numbers (below) — this is code-execution evidence,
not narrative.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Researcher can instantiate a `FourQuadBESS` exposing sign-free P/Q inside an apparent-power cone `p²+q²≤Smax²`, flowing device → aggregator → `:Rq` | ✓ VERIFIED | `src/devices/FourQuadBESS.jl:117-345` — struct, 2 constructors, guarded (`Pch_max>0`, `Pdch_max>0`, `Smax>0`, `η∈(0,1]`, SOC band, strict `λ` ordering), `contribute!` returns `q_inject`; `src/devices/Aggregator.jl:158-195` accumulates it additively into `:Rq`. Live-run script: `Aggregator devices = [Thermostatic, Deferrable, PVBattery, FourQuadBESS]`; negative `Pch_max` → `ArgumentError` confirmed by direct execution. |
| 2 | The no-binaries complementarity property is re-derived for 4Q or replaced by a hard post-solve numeric check — never silently inherited | ✓ VERIFIED | `src/models/complementarity_4q.jl` defines `assert_4q_complementarity!` (exported, own WR-01-idiom tolerance `atol=1e-8, rtol=1e-4`, throw-by-default, `report=true` kwarg); `welfare_solve.jl`'s `assert_battery_complementarity!` loop tightened with `!haskey(v,:q)` so the two checks are mutually exclusive over the same stash. Direct execution: centralized-fixture run passes (`maxratio=0.0233`); a synthetic `p_ch=p_dch=0.5` violation (built directly on a solved JuMP model, no solver noise) makes the certificate THROW with the documented message, and `report=true` converts it to a `@warn` returning `maxratio=2499.75` instead of throwing — the certificate is demonstrably not defeated. |
| 3 | Researcher can enable a live reactive μ-dual-ascent step on `:balance_q` that converges inside `solve_admm` on a `FourQuadBESS` fixture, cross-validated against the centralized solve, under its own two-block stopping treatment (not the single-block Boyd rule as-is) | ✓ VERIFIED | `src/admm/DsoOpt.jl` `LIVE` branch declares `qag_dso` unpinned with its own `ρ_q` penalty (no `:qag_pin`); `src/admm/AgrOpt.jl` `qag_live` mirrors `pag`'s pinning/penalty shape; `src/admm/solve_admm.jl:404-475` accumulates `_q`-suffixed residual terms in the SAME loop and calls `converged(...)` exactly ONCE on the JOINT stacked `(r_norm,s_norm,ε_pri,ε_dual)` — confirmed by `grep -c "converged("` = 1 non-comment call site. Direct execution on the 2-bus+4Q fixture: `iters=2`, `mu_q`/`q_devices` present as first-class NamedTuple keys; cross-validation `|Δwelfare|=2.1905e-5`, `|Δλ|max=1.044e-5`, `|Δμ|max=4.40e-9` — all within the phase's own measured/pinned tolerances (`atol=1e-4/5e-5/1e-7` respectively) and matching the SUMMARY's independently-cited measurement (`2.191e-5` at the default seed) to 4 significant figures. Liveness proven: two `:live` runs differing only in aggregator-profile seed converge to DIFFERENT `μ` (`|Δμ|=5.83e-9`, nonzero) — not a no-op. |
| 4 | With no `FourQuadBESS` present and dual-ascent disabled, ADMM and centralized welfare are byte-identical to pre-milestone behavior | ✓ VERIFIED | Direct execution: `solve_admm(feeder, pf, aggs_plain; ...)` with `reactive_consensus` OMITTED vs. explicitly `false` produce IDENTICAL `welfare = -483.81911704214497` (`==`, not `≈`) and both leave `mu_q === nothing`; the pre-existing Phase-16 regression `test_admm_reactive.jl` items ("default reactive_consensus omitted is byte-identical to today") were re-read and confirmed unmodified by Phase 19's diff. `src/admm/DsoOpt.jl`'s `OFF`/`CERTIFIED` branches are untouched code paths (D-12); WR-04's new guard only fires when a `q_inject`-carrying device is present, which the plain fixture has none of. |

**Score:** 4/4 roadmap success criteria verified.

### Plan-Level Must-Haves (cross-checked against all 8 plans' frontmatter)

| Plan | Must-have | Status | Evidence |
|------|-----------|--------|----------|
| 19-01 | `ReactiveMode` 3-state enum + Bool back-compat, wired into `TSODSO.jl` include graph | ✓ VERIFIED | `src/admm/ReactiveMode.jl` exports `ReactiveMode, OFF, CERTIFIED, LIVE, normalize_reactive_mode`; used throughout `DsoOpt.jl`/`AgrOpt.jl`/`solve_admm.jl`. |
| 19-02 | `FourQuadBESS` struct/constructors/`contribute!` + re-derived complementarity docstring | ✓ VERIFIED | See Truth 1/2 evidence; docstring derivation at `FourQuadBESS.jl:44-86` (4-step re-derivation, explicitly documents the D-08 honest boundary). |
| 19-03 | `build_dso_opt` 3-branch `reactive_consensus`, `DsoOpt.qag`, `set_rho_q!` | ✓ VERIFIED | `src/admm/DsoOpt.jl:303-333` three explicit `mode == OFF/CERTIFIED/LIVE` branches; `set_rho_q!` at line ~515. |
| 19-04 | `Aggregator.contribute!` widened, additive `:Rq`, byte-identical when absent | ✓ VERIFIED | `src/devices/Aggregator.jl:158-195`; confirmed via Truth 1/4 direct execution. |
| 19-05 | `assert_4q_complementarity!` new exported certificate, own tolerance, mutually exclusive with the old check | ✓ VERIFIED | See Truth 2 evidence. |
| 19-06 | `AgrOpt` `qag_live` + `solve_agr!` μ/d update + `check_4q` wiring | ✓ VERIFIED | `src/admm/AgrOpt.jl:148-169` (declare/pin under LIVE), `:240-300` (`solve_agr!` μ_j/d_j/check_4q kwargs). |
| 19-07 | `solve_admm` joint (λ,μ) stopping rule, `mu_q`/`q_devices` in return tuple, final-block `check_4q` wiring | ✓ VERIFIED | See Truth 3 evidence; return-tuple key confirmed `mu_q` (WR-03 fix), not bare `μ`. |
| 19-08 | `Phase19Fixtures` test module, measured cross-validation tolerances, liveness regression, IEEE-13 quarantined, final byte-identity diff | ✓ VERIFIED | `test/fixtures_phase19.jl` exists with `@testmodule Phase19Fixtures`, `two_bus_feeder_real_impedance`, `build_two_bus_aggregators_4q(_qbound)`, `centralized_welfare_4q`; `test/test_admm_reactive.jl` carries the `:live`/liveness/WR-02 sign-pin items; `test/test_ieee123_admm.jl` carries the quarantined 4Q supporting-evidence item under `AdmmRetryFixtures.retry_flaky_admm_solve`. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/admm/ReactiveMode.jl` | 3-state enum + normalizer | ✓ VERIFIED | Exports confirmed; used project-wide. |
| `src/devices/FourQuadBESS.jl` | Device struct/constructors/contribute! | ✓ VERIFIED | 348 lines, full docstrings, exported. |
| `src/models/complementarity_4q.jl` | New certificate | ✓ VERIFIED | 164 lines; exported `assert_4q_complementarity!`; throw+report kwarg confirmed live. |
| `src/devices/Aggregator.jl` | Widened `contribute!` | ✓ VERIFIED | `hasproperty(res, :q_inject)` accumulator confirmed present. |
| `src/admm/DsoOpt.jl` | 3-branch `build_dso_opt`, `qag` field, `set_rho_q!`, WR-04 guard | ✓ VERIFIED | All present; WR-04 guard fires as demonstrated. |
| `src/admm/AgrOpt.jl` | `qag_live`, `solve_agr!` μ/d/check_4q, `set_rho_q!` | ✓ VERIFIED | Confirmed by grep + docstring cross-reference. |
| `src/admm/solve_admm.jl` | Joint stopping rule, `mu_q`/`q_devices` return, final `check_4q` | ✓ VERIFIED | Single `converged(...)` call site confirmed; return tuple confirmed via live execution. |
| `test/fixtures_phase19.jl` | `Phase19Fixtures` module | ✓ VERIFIED | Loaded and exercised directly in this verification's own scripts. |
| `test/test_admm_reactive.jl` / `test/test_ieee123_admm.jl` | `:live` + liveness + WR-02 + quarantined IEEE-13 items | ✓ VERIFIED (by inspection) | Item names present; not individually executed via TestItemRunner in this session (see Constraints below) but their target behaviors were independently re-derived by this verification's own scripts and matched. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `FourQuadBESS.contribute!` | `Aggregator.contribute!` | `q_inject` NamedTuple field, `hasproperty` guard | ✓ WIRED | Confirmed by direct execution: `:Rq` residual accumulates the device's `q`. |
| `Aggregator` | `AgrOpt.qag_live` | aggregate `q_inject` pinning target under LIVE | ✓ WIRED | `AgrOpt.jl:161`: `qag_live_var[t] == qag[t] + res.q_inject[t]`. |
| `DsoOpt` LIVE `qag_dso` | `solve_admm` outer loop | unpinned coupling var + `ρ_q` penalty, μ-ascent | ✓ WIRED | Confirmed convergence (`iters=2`) and nonzero, seed-sensitive `mu_q`. |
| `solve_agr!`/final consolidation | `assert_4q_complementarity!` | `check_4q` kwarg, IPM-loosened tolerance at that call site | ✓ WIRED | `solve_admm.jl:652-668`; the CR-01 follow-up (`14ed32e`) documents and the code shows `rtol_4q=1e-3, atol_4q=1e-7` passed explicitly there. |
| `welfare_solve.jl` old check | `complementarity_4q.jl` new check | mutually-exclusive `:q`-key dispatch | ✓ WIRED | Both loop conditions read (old: `!haskey(v,:q)`; new: `haskey(v,:q)`) — structurally exclusive. |

### Data-Flow Trace

`mu_q`/`q_devices` are not hardcoded placeholders: direct execution shows they are populated
from the converged ADMM state (`mu_q` size `(1,24)`, nonzero, varies by aggregator-profile seed
in the liveness check), and are `nothing` under `OFF` (verified) rather than a silently-empty
container.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| FourQuadBESS composes in an Aggregator with other devices | direct script, `typeof.(agg.devices)` | `[Thermostatic, Deferrable, PVBattery, FourQuadBESS]` | ✓ PASS |
| Constructor guard rejects invalid `Pch_max` | direct script | `ArgumentError` thrown | ✓ PASS |
| Certificate passes on benign centralized 4Q solve | direct script | `maxratio = 0.0233` (≤1) | ✓ PASS |
| Certificate throws on a genuine violation | direct script, synthetic `p_ch=p_dch=0.5` | `ArgumentError`-style `error(...)` thrown with documented message | ✓ PASS |
| `report=true` neutralizes the throw | direct script | returns `maxratio=2499.75`, no exception | ✓ PASS |
| `:live` mode converges + cross-validates | direct script | `iters=2`, `\|Δwelfare\|=2.19e-5`, `\|Δλ\|=1.04e-5`, `\|Δμ\|=4.40e-9` | ✓ PASS |
| Liveness (mechanism genuinely live) | direct script, two seeds | `\|Δμ\|=5.83e-9 > 0` | ✓ PASS |
| Default path byte-identical to explicit OFF | direct script | `welfare` `==` (exact), `mu_q === nothing` | ✓ PASS |
| WR-04 guard fires for OFF + `FourQuadBESS` | direct script | `ArgumentError` thrown with WR-04 message | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|--------------|--------|----------|
| MESH-04 | 19-01, 19-02, 19-04, 19-05, 19-08 | 4Q-BESS device + re-derived/hard-checked complementarity | ✓ SATISFIED | Truths 1/2 above. |
| MESH-05 | 19-01, 19-03, 19-06, 19-07, 19-08 | Live reactive μ-dual-ascent, cross-validated, own two-block stopping | ✓ SATISFIED | Truth 3 above. |

No orphaned requirements: `.planning/REQUIREMENTS.md`'s traceability table maps only MESH-04 and
MESH-05 to Phase 19, and both are covered by at least one plan's `requirements:` frontmatter.

**Note (non-blocking):** `.planning/REQUIREMENTS.md`'s traceability table still shows MESH-04/
MESH-05 as `Pending` in the Status column — this is a documentation-bookkeeping field, not a
code truth; it should be updated to `Done` as part of phase close-out but does not affect goal
achievement.

### Anti-Patterns Found

None. Grepped every file `git log` shows modified by the phase's commits (`src/TSODSO.jl`,
`src/admm/ReactiveMode.jl`, `src/admm/DsoOpt.jl`, `src/admm/AgrOpt.jl`, `src/admm/solve_admm.jl`,
`src/devices/AbstractDevice.jl`, `src/devices/FourQuadBESS.jl`, `src/devices/Aggregator.jl`,
`src/models/complementarity_4q.jl`, `src/models/welfare_solve.jl`) for
`TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` — zero matches.

### Code Review Findings — Fix Verification

All 5 findings from `19-REVIEW.md` (1 Critical + 4 Warnings) were independently re-verified
fixed in the current HEAD (`e58926e`), not merely read as claimed in the review's own
"FIXED" annotations:

- **CR-01** (certificate tolerance defeated at per-unit scale): re-derived defaults
  (`rtol=1e-4, atol=1e-8`) confirmed in `complementarity_4q.jl`; confirmed by this
  verification's own synthetic-violation script that the certificate genuinely throws on a
  40%-of-rating-scale violation and passes on the benign fixture.
- **WR-01** (`:cone` name collision): `FourQuadBESS.jl:323` confirmed anonymous
  (`@constraint(m, [t=1:T], ...)`, no name); this verification's own script called
  `centralized_welfare_4q` (which internally exercises the same `ConvexBranchFlow` + device-cone
  composition WR-01 fixed) without any `JuMP.unregister` workaround and it ran cleanly.
- **WR-02** (μ sign convention unpinned): `test/fixtures_phase19.jl` confirmed to carry
  `two_bus_feeder_real_impedance`/`build_two_bus_aggregators_4q_qbound`; this verification's own
  `:live` cross-validation independently reproduced a `|Δμ|` consistent with correct sign
  (4.40e-9, matching the documented degenerate-near-zero regime rather than the ≥2.3e-3 flipped
  regime the review's own measurement cites).
- **WR-03** (`μ` kwarg/return-key collision): confirmed the return NamedTuple key is `mu_q`
  (verified live via `res_live.mu_q`), not bare `μ`.
- **WR-04** (OFF/CERTIFIED silently drops device reactive under a `q_inject`-carrying device):
  confirmed by direct execution — `solve_admm(...; reactive_consensus=false)` with a
  `FourQuadBESS`-bearing aggregator throws `ArgumentError` with the documented WR-04 message.

### Info Findings (open, out of fix scope — non-blocking)

IN-01 through IN-06 remain open per `19-REVIEW.md`'s own explicit classification
("Info findings were OUT of the `--fix` scope ... and remain open"). None of them contradict a
roadmap success criterion or a plan must-have; they are legitimate follow-up hygiene items
(e.g. IN-02's dual-residual-as-sum-of-norms vs. one-stacked-norm is a documented, CONSERVATIVE
deviation — confirmed by reading `solve_admm.jl:452`: `s_norm = ρf·sqrt(sq_ds) + ρ_qf·sqrt(sq_ds_q)`,
which upper-bounds the true stacked norm, so it can only make convergence stricter, never looser
or falsely-converged). Recommended to triage in a future phase, not a Phase-19 gap.

### Human Verification Required

None. Every roadmap success criterion and plan must-have in this phase is a numerical/code
correctness property, fully checkable by direct code execution — no UI, no real-time behavior,
no external service integration.

### Gaps Summary

No gaps. All 4 roadmap success criteria and all 8 plans' must-haves were independently
re-derived by direct code reading plus fresh, throwaway script execution against the current
HEAD (post-review-fix) — not accepted from SUMMARY.md or REVIEW.md narrative. The phase's
core deliverable (a genuinely live, converging reactive dual-ascent cross-validated against a
centralized solve, with a real 4Q device and a certificate that provably gates rather than
rubber-stamps) is demonstrably real in the codebase today.

---

_Verified: 2026-08-08T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
