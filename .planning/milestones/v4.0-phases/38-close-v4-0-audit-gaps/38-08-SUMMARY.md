---
phase: 38-close-v4-0-audit-gaps
plan: 08
subsystem: docs
tags: [framework-guide, api-sweep, planning-ids, writeups]
requires:
  - "38-07: Scenario rejects ADMM + allow_export = false at construction (now stated in the guide)"
provides:
  - "FRAMEWORK_GUIDE.html matches the current API (research Finding 7 categories A-G)"
  - "docs/writeups/README.md lists FRAMEWORK_GUIDE.html as a tracked, hand-maintained HTML guide"
affects: [38-09]
tech-stack:
  added: []
  patterns: ["edit the 2.9 MB guide only through a scratch count-asserting replacer with data-URI hash and tag-balance guards"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-08-SUMMARY.md
  modified:
    - docs/writeups/FRAMEWORK_GUIDE.html
    - docs/writeups/README.md
decisions:
  - "The EXACT-04 token also sat in the figure's img alt attribute; the same replacement fixed alt and figcaption (data URI untouched, hash-verified)"
  - "The DLMP formula's congestion term now includes the receiving-end dual (3.37), matching the decompose_dlmp docstring"
  - "TSODSO.run is internal (not public); the guide still names it as the dispatch point, always qualified, as the source docstrings do"
metrics:
  duration: ~30min
  completed: 2026-10-07
  tasks: 2
  files: 2
requirements: [HYG-02, HYG-03, ARCH-02]
---

# Phase 38 Plan 08: FRAMEWORK_GUIDE.html API and planning-ID sweep Summary

The framework guide now matches the current API. Code blocks qualify public names, DLMP text uses
`cone`/`drop` and the `DlmpDecomposition` struct, Scenario text uses strategy structs and
`TSODSO.run` dispatch, and no planning identifiers remain. The 16 embedded images are
byte-identical to 8018524.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Scripted, count-asserting API and planning-ID edits | 288d8d2 | docs/writeups/FRAMEWORK_GUIDE.html |
| 2 | Static re-verification and README listing | 00ac782 | docs/writeups/README.md |

## Replacements by category

The scratch editor `p38/guide_edit_api.py` ran 90 rules, 100 replacements in total. Every count
matched. The 16 data-URI SHA-256 values are unchanged. Start and end tag counts stay balanced: 55
new inline `<code>` spans were added and one `<strong>` was removed.

| Category | Count | What changed |
|----------|-------|--------------|
| A code blocks | 6 | `TSODSO.SOCP()` and qualified problem-class comments; `strategy = Centralized()` / `ADMM()` in the 3 Scenario examples; the `build_population(...)` block rewritten as valid Julia matching `_materialize` (`TSODSO.build_feeder`, `TSODSO.sub_seed`, `TSODSO.build_population(s.population, feeder, s.feeder, profiles, ...)`); `run_scenario(s)` annotated as `TSODSO.run(s.strategy, s)` |
| B unexported names | 35 | 26 public names qualified `TSODSO.x` in `<code>` spans; internal `converged` replaced by the public `status = :converged` reading; "one exported is_converged" becomes the public `TSODSO.is_converged(trace::NashTrace, tol_outer, N)` |
| C reactive forms | 4 | `ReactiveMode.LIVE` in the Step 7 heading and the meshed section; the `ReactiveMode` module and type `ReactiveMode.T` named; "Phase 19" and "normalization" removed |
| D DLMP naming | 13 | underbrace labels `cone`/`drop`, congestion now `(3.36/3.37)` with the receiving-end dual (checked against the `decompose_dlmp` docstring); bullet field names; the sum-back identity; `DlmpDecomposition` struct and `NamedTuple(d)` order; the physics word "marginal-loss" kept |
| E Scenario/strategy | 24 | strategy structs with their own knobs (`ADMM(; ρ, …)`, `MPC(; H, step, terminal_soc, forecast_error)`, `Stochastic(; S, probabilities, H_oos)`); `TSODSO.run(strategy, s)` dispatch incl. MPC/Stochastic; `MPC(terminal_soc = false)`; validation by the strategy constructors plus the ADMM/allow_export check; `ADMM()` default ρ; `scenario_filename` flattening; TOC entries and headings updated (anchor ids kept) |
| F exports/errors | 5 | 90 exported names plus the `public` advanced API (`TSODSO.x` / `using TSODSO: x`); no plan-ownership comments; `solve_admm` and Nash `max_sweeps` throw `ConvergenceError`; `time_limit_s` -> `status = :budget_exceeded` |
| G planning IDs | 13 | `.planning/` pointers -> README/docs pointers; `byte-identical` -> "bit-for-bit identical"/removed; EXACT-04 (alt + caption), PF-04 ×3, ADMM-04, Phase-6/7/19/26/27/28, CR-01, code-review and `INT-STRETCH` removed while keeping the sentence meaning |

## Verification

- Image hashes: all 16 equal to 8018524 (plan Task 1 verify passes).
- Planning IDs: 0 hits over tag-stripped text, and also 0 over raw text including attributes;
  `INT-STRETCH` absent.
- `p38/guide_verify.py`: OK. It re-runs `guide_scan.py` on a regenerated stripped copy, applies
  targeted stale-phrase checks for categories C-F, the planning-ID rules and the image hashes.
  Against the 8018524 guide the same checker reports 114 findings, so it is not vacuous.
  Allowlist (3 entries):
  - `run` in `src/experiments/run.jl`: a file name, not a call.
  - `run` in `run.jl`: a file name in the harness "Where it lives" list.
  - `_mpc_certify_and_price`: an underscore internal, named only as a source pointer.
  Categories not enforced, as informational heuristics: physics prose "loss term", the corrected
  `NamedTuple(d)` sentence, the word "export" in prose, and Base/JuMP call names.
- `check_script_api.jl` on the 9 re-extracted `<pre>` blocks (prelude
  `using TSODSO; using JuMP; T = 24; nB = 1`): `OK: 9 files checked against the TSODSO API surface`, exit 0.
- `check_planning_ids.py`: `OK: 250 files scanned, no planning identifiers`.

## Deviations from Plan

**1. [Rule 2 - Missing critical] Planning ID inside an `<img alt>` attribute**
- **Found during:** Task 1
- **Issue:** `EXACT-04` appeared in the alt text as well as the figcaption. The plan's tag-stripping
  check cannot see attributes.
- **Fix:** one replacement with count 2 covers alt and figcaption. The data URI is not touched and
  its hash is verified. `guide_verify.py` also scans raw text, attributes included.
- **Commit:** 288d8d2

**2. [Rule 1 - Bug] Additional stale statements in the edited passages**
- The ρ₀ = 100 default is attributed to `ADMM()`, not `Scenario`. "Naming and provenance for free"
  now names `scenario_filename` flattening, because `savename` drops the struct-valued strategy.
  The ScenarioResult paragraph mentions the typed `details` forwarding.
- **Commit:** 288d8d2

Model-text contradictions (category H: 3.37 "not implemented", exactness-copy direction, gate
tolerance, terminal SOC pin, truth settlement, integer planning, test count) were left for plan
38-09 as planned. The "Continuous investment only" bullet lost only its `INT-STRETCH` tag here.

## Self-Check: PASSED

- FOUND: docs/writeups/FRAMEWORK_GUIDE.html, docs/writeups/README.md
- FOUND: 288d8d2, 00ac782
