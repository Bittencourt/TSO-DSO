---
phase: 40-784-house-thesis-population
fixed_at: 2026-10-24T18:20:00Z
review_path: .planning/phases/40-784-house-thesis-population/40-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 40: Code Review Fix Report

**Fixed at:** 2026-10-24T18:20:00Z
**Source review:** .planning/phases/40-784-house-thesis-population/40-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (WR-01, WR-02, WR-03; Info findings out of scope per dispatch)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### WR-01: `case_a_household_map`'s `seed` argument is never used, and its docstring claims it is

**Files modified:** `src/experiments/materialize.jl`, `test/test_population_case_a.jl`, `docs/literate/case_a_population.jl`
**Commit:** 5e6e286
**Status:** fixed
**Applied fix:** Took the REVIEW's preferred (behavior-preserving) option after reading
40-01-PLAN.md Task 2 and the tests: the plan claimed the map consumes
`_case_a_house_seed(seed, bus, h)`, but the shipped implementation is genuinely
seed-independent (the seed only drives `build_population`'s profile draws, which the map
never performs) — so the docstring and signature were aligned to the TRUTH and the
behavior kept byte-identical:

- Renamed the positional parameter `seed` → `seed_unused` in the signature and the
  docstring's signature line (positional calls are unaffected — zero call-site churn;
  all tests/docs call positionally).
- Docstring now states explicitly: `seed_unused` is accepted for call-site symmetry with
  `build_population` and is NOT used; the map encodes only assignment structure
  (`bus` / `house_index` / `pv_group`) and is identical for every seed; per-house
  seeding lives exclusively in `build_population`'s profile draws via
  `_case_a_house_seed`.
- Corrected the primitive list: dropped `_case_a_house_seed` from the "SAME primitives"
  sentence (now `_load_buses`, `_case_a_house_counts`, `_case_a_pv_group`).
- Test: added the cross-seed assertion `m1 == case_a_household_map(feeder, :ieee13, 999)`
  to the "household map consistency + purity" item, codifying the documented
  seed-independence as a test-enforced contract (previously untestable per the review).
- Docs page: added a source comment at the `case_a_household_map(feeder, :ieee13, s_pop)`
  call site stating the seed argument is accepted for symmetry and NOT used, removing the
  wrong impression the review flagged.

**Test evidence:**
- `TSODSO_TEST_FILES=test_population_case_a.jl julia --project=. -e 'import Pkg; Pkg.test()'`
  → 52/52 pass (30.1 s), including the new cross-seed assertion.
- Knife-edge canary re-run → `iters = 56`, `welfare = -4823.66604824162` — byte-exact
  against the pinned values (`:default` path untouched).
- All edited lines ≤ 92 textwidth (JuliaFormatter width); `Meta.parseall` clean.

### WR-02: "Fast lane" scaling smoke runs two full-scale ADMM solves (up to ~240 s) in the default CI lane

**Files modified:** `test/test_population_case_a_scaling.jl`
**Commit:** cb0a962
**Status:** fixed
**Applied fix:** Combined the review's options (a)+(c), per the dispatch instruction
("keep a genuinely small smoke in the fast lane; move the heavy legs behind `:slow`"):

- Item 2 (fast, `tags = [:population]`) retitled "…(fast smoke)": keeps the script's
  exact construction path (full 784-house build + prefix slicing — no solves, measured
  cheap) but now solves two TINY nested rungs — `1/78` (10 houses) and `0.125`
  (90 houses; committed-ladder precedent: 4 iters / 4.6 s at T = 24) — under a
  60 s honesty cap (bounded worst case). Structural assertions (10 bus-level
  aggregators, ascending buses, 3× devices, nestedness at the solve level) unchanged in
  shape; `:budget_exceeded` remains an accepted recorded status (no gate loosened).
- New item 3 (slow, `tags = [:population, :slow]`) "…(slow)": the full-scale legs
  (`0.5` = 390 houses, `1.0` = 784 houses) at T = 10 under the original 120 s caps,
  with the original assertions, plus a header comment citing the scaling_ladder.csv
  rung6 = 508 s precedent and the slow-lane invocation.
- File header comment rewritten to describe the split honestly.

`expected_broken.txt` verified unaffected: it holds NO entry for this file (the only
phase-40 entry keys on `test_population_case_a_agreement.jl`, which was not modified —
its `(kind, file, item, expr)` key is byte-identical by construction).

**Test evidence:**
- Fast lane: `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_population_case_a_scaling.jl`
  → 27/27 pass in 2m33s (bounded; previously up to ~4 min of solver time alone).
- Slow lane: `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_population_case_a_scaling.jl`
  → 18/18 pass in 5m0s — proves the retag selects the full-scale legs ONLY in the slow
  lane (and confirms, at ~5 min wall, exactly why they must not sit in CI's fast lane;
  CI.yml pins `TSODSO_TEST_SET: fast`).

### WR-03: Docs page `only(...)` on `agreement.csv` hard-fails the docs build the moment the CSV legitimately grows

**Files modified:** `docs/literate/case_a_population.jl`
**Commit:** bcff112
**Status:** fixed
**Applied fix:** Replaced `only(read_case_a_csv(...))` with the review's provenance-keyed
selection, keyed on the page's own constants (single source of truth inside the page):

```julia
agreement_rows = read_case_a_csv(...)
agreement = only(filter(
    r -> r["seed"] == string(CASE_A_SEED) && r["t_horizon"] == string(T_HORIZON),
    agreement_rows,
))
```

`only` is retained as the exactly-one assertion (still fails loudly if the recorded
seed=42 / t_horizon=24 row disappears — or if a same-key re-measure on a newer Julia
lands, where a page refresh is the honest outcome, per the in-code comment). The appended
provenance note was reworded: figures come from "the row keyed `seed=42, t_horizon=24`
(recorded on `julia_version=1.12.5`)"; rows on other provenance upsert beside it and do
not affect the page.

**Test evidence:**
- Full docs build: `julia --project=docs docs/make.jl` → success; page generated
  (`docs/src/generated/case_a_population.md`); rendered HTML shows
  `centralized leg optimizer path : tol_gap_1e-10`; only pre-existing warnings
  (size thresholds / ticks / repo URL), none from this change.
- Growth simulation: augmented a temp copy of agreement.csv with a `--seed 43` row and a
  T=12 row (3 rows total) → the filter selects exactly the recorded
  `julia_version=1.12.5, seed=42, t_horizon=24` row; the build no longer couples to CSV
  growth.

## Skipped Issues

None — all in-scope findings were fixed.

---

_Binding-constraint checks: `:default` population path untouched (WR-01 is a
signature/docstring/test/comment change only; knife-edge canary byte-exact: iters=56,
welfare=-4823.66604824162). Honesty policy upheld: no gate loosened; the scaling items
keep `:budget_exceeded` as an accepted recorded status under honesty caps; the
`test_population_case_a_agreement.jl` allowlisted skip is untouched (file not modified;
`expected_broken.txt` unmodified). Each fix committed atomically with hooks on, in its
own isolated worktree branch (`gsd-reviewfix/40-1423547`) fast-forwarded to
`agents/session-2026-10-23`. 40-REVIEW.md left unmodified (no per-finding status
fields, per convention)._

_Fixed: 2026-10-24T18:20:00Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
