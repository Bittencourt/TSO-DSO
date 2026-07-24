---
phase: 14-validation-oracle-regression-hardening-docs
fixed_at: 2026-07-24T00:00:00Z
review_path: .planning/phases/14-validation-oracle-regression-hardening-docs/14-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 14: Code Review Fix Report

**Fixed at:** 2026-07-24
**Source review:** `.planning/phases/14-validation-oracle-regression-hardening-docs/14-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (fix_scope = critical_warning; 4 Info findings out of scope)
- Fixed: 4
- Skipped: 0

**Verification performed:**
- Full docs build (`julia --project=docs docs/make.jl`) run twice from the fix worktree — final run **exit 0** with only the two pre-existing benign warnings (navbar repo-URL under `remotes = nothing`; the admm page's image-size fallback). Rendered Rung 6 page shows `UB = 17.75500113214901`, the new offset-corrected cost `-0.24499886785…` (≈ certified `-0.245`), and `z = 0.6985` with full reconciliation prose; **zero** JLD2/HiGHS noise lines on both new pages; `SMAX_NO_LIMIT` now surfaced on the API page.
- Filtered TestItemRunner run from a scratch env (explicit filename filter over `test_planning_noninteger.jl`, `test_planning_checkpoint.jl`, `test_planning_hardening.jl`, `test_factory.jl`): **58/58 pass**.
- All edited `.jl` files parse-checked (`Meta.parseall`).

## Fixed Issues

### CR-01: Rung 6 page's Deferrable-substitution equivalence claim wrong for objective values

**Files modified:** `docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl`
**Commit:** 22376a5
**Applied fix:** Rewrote the equivalence paragraph to state the substitution is exact only **up to the additive constant `(b/2)·E² = 18`** that `Deferrable`'s squared utility form keeps (and corrected the misattributed RESEARCH A5 citation — A5 sanctions dropping eq. 3.12's separate constant `c`, not the expansion term). The `UB` display is now explicitly labeled as the certified `−0.245` shifted by `+18` (expect `≈ 17.755`), a new `result.UB - 0.5 * 1.0 * 6.0^2` example renders the offset-corrected cost directly comparable to `−0.245`, and the `z` note explains the `max(1, |UB|)` relative-gap normalizer consequence (`z ≈ 0.6985`, ~17.8× effectively looser stop at the same `tol = 1e-6`). The Rung 7 page's inherited substitution paragraph got the matching one-paragraph qualification, noting that page displays no objective-level quantities.

### WR-01: Source-scan tripwire has silent false-negative shapes

**Files modified:** `test/test_planning_noninteger.jl`
**Commit:** f00ba15
**Applied fix:** Hardened per the review's intent, with two adaptations the review's literal snippet required (both verified against current sources):
1. **Docstring-state tracking added to the scan.** The review's widened regex `^\s*(?:function\s+)?(build_\w+)\s*\(` false-positives on docstring signature-convention lines and on `nash.jl:695`'s docstring prose line beginning `build_shared()`, which would have shipped a failing test. The scan now tracks triple-quote open/close state and skips docstring interiors; the widened regex + `walkdir` recursion otherwise applied as suggested (short-form, indented, and subdirectory definitions all now caught).
2. **Semantic channel scoped by an operational-builder allowlist.** The review's `union!` over all exported `build_*` symbols would fail today on the six exported non-planning builders (`build_agr_opt`, `build_dso_opt`, `build_ieee123`, `build_feeder`, `build_price`, `build_population`). The channel now unions `setdiff(exported build_*, documented allowlist)` — any NEW exported builder anywhere in the package (any syntax, any location) must land in the registry or the allowlist, loudly, which also covers the review's shape 4 (planning builder landing outside `src/planning/`).

### WR-02: `SMAX_NO_LIMIT` exported but undocumented; `Order` fragility; overstating make.jl comment

**Files modified:** `src/units/PerUnit.jl`, `docs/src/api.md`, `docs/make.jl`
**Commit:** 72068fc
**Applied fix:** (a) Promoted `SMAX_NO_LIMIT`'s comment block to a real docstring (now rendered in the API reference). (b) Added `:constant` uniformly to every `@autodocs` `Order` in `api.md` (no-op for sections without documented constants; removes the whole delayed-failure class). (c) Corrected the `make.jl` comment: `checkdocs = :exports` catches *documented-but-unsurfaced* exports only — an export with no docstring at all passes silently — and noted the `Order`/`:constant` coupling.

### WR-03: New docs pages emit repeated JLD2 warnings and raw HiGHS logs

**Files modified:** `src/planning/checkpoint.jl`, `src/solver/factory.jl`
**Commit:** 9cfa683
**Applied fix:** Root-caused both noise sources instead of suppressing in the docs pages:
1. `checkpoint_iteration!` now passes **string keys** (`"iteration"`, `"state"`) to `@tagsave`, silencing JLD2's per-save symbol-key warning at its source; `resume_from_checkpoint` already read string keys (JLD2 round-trip always returns `Dict{String,Any}`), so no reader change was needed.
2. The raw HiGHS log did **not** come from the retry ladder (it never touches solver verbosity — reviewer's guess adapted): the solver factory silenced Clarabel (`verbose => false`) and Ipopt (`print_level => 0`) but left HiGHS as the one unsilenced backend. Added `"output_flag" => false` to the LP/MILP HiGHS factories, matching the factory's own convention. Verified nothing in `src/` or `test/` depends on HiGHS console output; checkpoint/hardening/factory tests all pass.

**Incidental hazard caught during this fix:** placing the new factory comment *between* `select_optimizer`'s docstring and its first method silently **detached the docstring** (verified as a general Julia behavior), which the first docs build surfaced as a `Cannot resolve @ref` warning — and which `checkdocs = :exports` did NOT fail on, a live demonstration of the exact WR-02 limitation. The comment was moved above the docstring; the second full docs build is clean.

## Skipped Issues

None — all in-scope findings fixed. (IN-01 through IN-04 were out of scope under `fix_scope = critical_warning`.)

---

_Fixed: 2026-07-24_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
