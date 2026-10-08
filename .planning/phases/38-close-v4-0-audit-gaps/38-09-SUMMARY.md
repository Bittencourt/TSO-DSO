---
phase: 38-close-v4-0-audit-gaps
plan: 09
subsystem: docs
tags: [framework-guide, model-text, version-notes, writeups]
requires:
  - "38-08: guide API + planning-ID sweep (editor/verifier design reused)"
  - "38-02: MPC first tier routed through the shared exactness kernel"
  - "38-04: held-out OOS re-solves gate-checked (inexact_h, :oos_inexact_skipped)"
provides:
  - "FRAMEWORK_GUIDE.html model text consistent with current src/ and docs (research Finding 7 category H)"
affects: [38-10]
tech-stack:
  added: []
  patterns: ["model-text corrections carry a short '(Changed in vX.Y: ...)' note; derivations get a corrective note, not a rewrite"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-09-SUMMARY.md
  modified:
    - docs/writeups/FRAMEWORK_GUIDE.html
decisions:
  - "Version notes use plain <em>(Changed in vX.Y: ...)</em>; the guide has no note/aside class"
  - "Gate constants are written as math (tau_solver = 2e-7, eps = 1e-9), not as the internal TAU_SOLVER_EXACT / MEASURED_REL_TOL_EXACT names, which are neither exported nor public"
  - "Section 6 high-PV finding gets a v4.0 note: 1.2x is cone-exact under both copies now; inexactness reproduces only with thesis_literal = true at 1.4x; the applicability-map image predates the change (image left untouched)"
metrics:
  duration: ~30min
  completed: 2026-10-07
  tasks: 2
  files: 1
requirements: [FIX-08, FIX-10, ARCH-02]
---

# Phase 38 Plan 09: FRAMEWORK_GUIDE model-text corrections Summary

The guide no longer contradicts the code on any of the category-H points. Each correction carries a
short "(Changed in v4.0 / v3.0: ...)" note. Section 5.1 keeps the thesis-literal derivation and gains
one corrective paragraph. The text now describes this phase's two behaviour changes: the MPC first
tier uses the shared exactness check, and held-out OOS re-solves are gate-checked.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Scripted model-text corrections with version notes | fd0b209 | docs/writeups/FRAMEWORK_GUIDE.html |
| 2 | Re-run all guide static checks | (no changes; verification only) | n/a |

The editor `p38/guide_edit_model.py` is a copy of plan 08's `guide_edit_api.py` with a new
replacement list. It ran 21 rules and 21 replacements, and every count matched. The 16 data-URI
hashes are unchanged. Tags stay balanced, with added spans only: code +17, em +11, p +3, li +1.

## Corrections (old → new, source checked)

| H item | Old fragment | New text | Checked against |
|--------|--------------|----------|-----------------|
| 3.37 | "reverse-direction limit (3.37) is not implemented … (3.36) already bounds P²+Q² symmetrically" | receiving-end limit `(P−rℓ)²+(Q−xℓ)² ≤ S²max` on the same limited branches (`:smax_rev`); back-feed can violate it while (3.36) is slack; summary now "(3.31)–(3.37)"; note v4.0 | src/powerflow/ConvexBranchFlow.jl:5,73-75 (docstring 3.37), :357 (`smax_rev` constraint); ROADMAP Phase 26 SC-3 |
| Exactness copy (overview) | "a parallel loss-less LinDistFlow constraint copy" | "LinDistFlow-style" copy + v4.0 note: default is Gan–Low direction, a slight restriction of the upper band | ConvexBranchFlow.jl:18-36 (header verdict, labelling note) |
| Exactness copy §5.1 | derivation shows `P̂ = P + rℓ` with the −2(r²+x²)ℓ argument (kept) | corrective paragraph: derivation is the thesis-literal copy (v̂ ≤ v, restricts the lower band); since v4.0 the default is `P̂ = P − rℓ`, drop carries +2(r²+x²)ℓ, v̂ ≥ v, `v̂ ≤ V²max` load-bearing; Gan–Low modified OPF, ~0.05% welfare loss; `ConvexBranchFlow(; thesis_literal = true)` reproduces the thesis | ConvexBranchFlow.jl:76-120 (3.43 bullet, verdict, labelling note with -921.754 vs -921.277) |
| Gate tolerance §5.2 | "defaults r_tol = 10⁻⁴, a_tol = 10⁻⁶" | `gap ≤ a_b + r_tol·max(…)`, `a_b = max(τ_solver, ε·ref_b)`, τ = 2×10⁻⁷, ε = 10⁻⁹, ref_b = S²max or head-branch P²+Q²; explicit `atol` = flat floor; note v4.0 | src/models/exactness.jl:73,83 (constants), :104-126 (`_cone_row`), :262-277 (assert docstring incl. atol override) |
| Terminal pin (6.1) | `soc[H] = soc^DA[min(t+H−1, T)]` | `soc[H+1] = soc^DA[t+H]` | src/models/mpc_window.jl:107-117 (builder step 7), :138-144 (guard removed); src/experiments/mpc_loop.jl:355-361, 430-437 |
| H ≥ 2 / step guard | "pin requires H ≥ 2 … with stateful devices Δ ≤ H−1" | SOC spans H+1 states, any H ≥ 1 accepted; Δ ≤ H−1 only with thermostatic devices (Tin recursion τ ≤ H−1); note v4.0 | mpc_window.jl:138-144; mpc_loop.jl:295-320 (guard narrowed to Tin0 devices) |
| MPC Tier 1 | "Tier 1 — inline cone check … rtol 1e-4, atol 1e-6 … computed inline" | "Tier 1 — shared exactness check": same per-branch arithmetic and defaults as `assert_socp_exact!` (r_tol 1e-4 + hybrid floor), non-throwing; note v4.0; forced-inexact ratio "≈ 9.2×10³ … under the shared exactness check" | mpc_loop.jl:795-799 (docstring), :870-873 (`_socp_cone_check(o.ctx).maxratio`); docs/literate/mpc_rolling_horizon.jl:274 |
| MPC settlement | "Settlement is forecast-consistent, not truth-settled … Truth-re-settlement is explicitly deferred"; "truth-anchored even though settlement is not" | realized welfare settled against the truth plant: PV clip to true availability, frontier import by `ACPowerFlow(; limits = false)`, `realized_welfare`/`regret` truth-settled, overloads reported in `settlement_violations`, `forecast_settled_welfare` kept as diagnostic; step 4 wording; note v4.0 | mpc_loop.jl:110-183 (realized_welfare, settlement_violations), :202-221 (forecast_settled_welfare, regret); docs/literate/mpc_rolling_horizon.jl:217-243 |
| §6 high-PV finding (extra, Rule 1) | the 1.2× inexactness narrative stated without qualification | v4.0 note: 1.2× point cone-exact under both copies; inexactness reproduces only with `thesis_literal = true` at 1.4×; default 3/150 vs literal 5/150 inexact grid points; map predates the change | docs/literate/socp_applicability.jl:243-256; docs/literate/ac_oracle.jl:212-236; ConvexBranchFlow.jl:117-120 |
| Integer planning (§ model) | "continuous-only by enforced design: no binary or integer variable exists anywhere in src/planning/" | continuous by design for its subproblem builders; integer investment in `TSODSO.build_master_integer` / `TSODSO.BendersMasterInteger` with Laporte–Louveaux cuts, the one guard exemption; note v3.0 (+ v4.0 Nash) | src/planning/master_integer.jl:1-40; src/TSODSO.jl:231,361-365; test/test_planning_noninteger.jl:89-136 (EXEMPT); MILESTONES v3.0 (INT-01..04) |
| Integer planning (scope bullet) | "Continuous investment only. No binary/integer variable exists anywhere in src/planning/" | "Integer investment only on the distributor side": MILP master, certified against exhaustive lattice enumeration (Rung 11 page), `run_nash!(...; integer = (; K))`; rest of PSR problems 8–9 still deferred; note v3.0/v4.0 | src/planning/nash.jl:486-507 (`integer` kwarg); docs/literate/integer_investment.jl:1-12; MILESTONES v3.0 |
| No-binaries guard (validation) | "tripwire over every planning-layer subproblem builder" (unqualified) | + "the integer master is its one explicit exemption" | test/test_planning_noninteger.jl:89-136 |
| Test-suite size (×2) | "~2,800-test suite" | "about 32,000 assertions in over 500 test items as of v4.0" | 38-CONTEXT/RESEARCH baseline 32224 assertions, count-sets all=511; `@testitem` grep 628 occurrences |
| OOS gate | "average realized welfare over the *feasible* held-out draws F" | new step: every held-out re-solve gated by the shared exactness check, inexact draw kept in `welfare_h`, flagged in `inexact_h`, excluded; F = usable (feasible and exact); `status` `:oos_infeasible_skipped` / `:oos_inexact_skipped` (precedence); "infeasibility and inexactness masks"; note v4.0 | src/experiments/run_stochastic.jl:130-165, 301-338, 363-374; src/models/stochastic_welfare.jl:769; docs/src/status_policy.md:60-64 |

Version attribution was checked against ROADMAP v4.0 Phases 26 and 27 (copy flip, 3.37, SOC
horizon linking and the step-guard re-scope, hybrid gate, MPC truth settlement) and Phase 38 (MPC
first tier and OOS gate). Integer planning is attributed to MILESTONES v3.0 (INT-01..04), and its
N>1 Nash extension to v4.0 Phase 31. The guide cites versions only, never phase or plan IDs.

## Verification (Task 2)

- Semantic check: 17 old fragments are absent and all 21 new markers are present (plan Task 1
  verify).
- Image hashes: all 16 data URIs are equal to 8018524. The applicability-map image was left as is;
  the text notes that it predates v4.0.
- Planning IDs: 0 hits over tag-stripped text. `check_planning_ids.py` reports `OK: 250 files
  scanned`.
- `guide_verify.py`: OK, with the same 3 allowlist entries as plan 08 and no new findings in
  enforced categories. Informational category J (Base/JuMP call names) is unchanged.
- `check_script_api.jl` on the 9 re-extracted `<pre>` blocks (prelude `using TSODSO; using JuMP;
  T = 24; nB = 1`): `OK: 9 files checked against the TSODSO API surface`, exit 0. Only one Julia
  process was running.

## Deviations from Plan

**1. [Rule 1 - Bug] Additional now-false statements next to the H list**
- **Found during:** Task 1 (checking each H passage against src/docs)
- **Issue:**
  - The MPC step guard said "with stateful devices Δ ≤ H−1". Since v4.0 this applies to
    thermostatic devices only.
  - Section 6 presented the 1.2× high-PV inexactness without qualification. Under v4.0 it no
    longer reproduces at that point.
  - The overview called the copy "loss-less".
  - The branch-flow summary listed only "(3.31)–(3.36)".
  - The forced-inexact cone ratio was quoted as ≈9157×. The literate page now gives ≈9.2×10³
    under the shared check.
- **Fix:** I made small replacements, each with a version note where it states a change. Every fix
  was checked against the cited source.
- **Commit:** fd0b209

**2. Tag-balance guard widened**
- The editor's balance check now allows balanced additions of `em`, `p`, and `li` as well as
  `code`. The corrective notes need them. The rule still requires start and end deltas to be equal
  and non-negative.

## Self-Check: PASSED

- FOUND: docs/writeups/FRAMEWORK_GUIDE.html
- FOUND: fd0b209
