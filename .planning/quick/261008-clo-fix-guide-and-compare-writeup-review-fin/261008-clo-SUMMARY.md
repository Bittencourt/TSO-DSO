---
quick_id: 261008-clo
status: complete
completed: 2026-10-08
commits:
  - f7a8a05  # Task 1: compare_default_stochastic.typ
  - bb257cb  # Task 2: FRAMEWORK_GUIDE.html
key-files:
  modified:
    - docs/writeups/compare_default_stochastic.typ
    - docs/writeups/FRAMEWORK_GUIDE.html
---

# Quick 261008-clo: review fixes for the compare writeup and FRAMEWORK_GUIDE

Docs only. No src/ or test/ changes, no Julia runs, ROADMAP and STATE not touched.

## Task 1: compare_default_stochastic.typ (f7a8a05)

Claims were checked against `results/compare_default_stochastic/{summary,dadp_tidy,oos_draws}.csv`,
`scenario_fan.png`, and `src/experiments/run_stochastic.jl` / `src/core/errors.jl`.

- F1: applied. The raw difference is 0,14 (−538,8957 − (−538,7545) = −0,1413).
- F2: applied. The default exceeds the scenario max at h3 (+0,020), h6 (+0,005), h9 (+0,018) and
  marginally at h1 (+0,0003).
- F3: applied, with an adjustment. Scenario 4 has PV ≈0,17 at h7, the highest at that hour, and
  demand 0,6. Scenario 1's trace sits under the orange one: it has the same h5+ PV and the same
  h7 demand, yet pays 4,843. The text now says that h7 alone does not explain the whole price.
- F4: applied. The h1 spread is 8,6e-9, so the text says "nula até a precisão do solver".
- F5: applied. The h2 deviation is −0,0007. The sign list now reads positive h1, 3, 6–9 and
  negative h2, 4, 5.
- F6: applied with the requested wording. No re-run.
- F7: applied, but the "≈0,5 do piso" clause was dropped because the per-draw ratio is not
  recorded in the results folder. tol_gap 1e-8 vs 5e-10 and `:solved`/`:oos_inexact_skipped`
  were checked in the code.
- F8 and F9: applied. All planning IDs were removed and the typo "máscarado" was fixed.
- The file compiles with typst. No PDF is tracked, so none was regenerated. The grep finds only
  the feeder name `IEEE-13` and no `Fase N`.

## Task 2: FRAMEWORK_GUIDE.html (bb257cb)

Edited with `scratchpad/clo/guide_edit_clo.py`: 21 exact replacements, each asserted to match
count 1.

- F1: applied to the ops bullet, the TOC, the h3 heading and a caption note. The anchor id is
  kept so links don't break.
- F2: applied to the list, the increment equation, the ν^rev definition and "Where it lives",
  which now includes `:smax_rev` (dlmp.jl, ConvexBranchFlow.jl:354-357).
- F3: applied to both ranges.
- F4: applied, with an adjustment. "AC-feasible operating point" is now qualified with "when the
  exactness certificate passes". The hours 6–15 and −921.754/−921.277 figures were checked in
  `docs/literate/ac_oracle.jl` and `test/test_ac_oracle.jl`.
- F5: applied. `MPC(step = …)` defaults to 1 and `forecast_error` to 0.05 (strategies.jl:126).
- F6: applied. The shapes and NaN cases match the `ScenarioResult` docstring (run.jl).
- F7: applied. The centralized path refuses through `_assert_priceable`; ADMM uses
  `_react_certify_q!` → `assert_no_slack(:balance_q)`.
- F8: applied as a note paragraph after the sweep code block.
- Cosmetic: the stray dot was the broadcast form (`set_parameter_value.(…)` in src/planning). It
  now reads `set_parameter_value.(z, z_k)` (broadcast). The header now reads "Generated 2026-08-11;
  revised 2026-10-08."

## Verification

- All 16 `data:` URI sha256 hashes are identical to HEAD~ and html.parser raises no exceptions.
- `check_planning_ids.py` reports OK after both tasks.
- No planning IDs were added. The only pattern hits outside the base64 are `IEEE-13`.

## Self-Check: PASSED
