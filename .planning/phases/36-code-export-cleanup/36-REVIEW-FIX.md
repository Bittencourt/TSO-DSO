---
phase: 36-code-export-cleanup
fixed_at: 2026-10-05T00:00:00Z
review_path: .planning/phases/36-code-export-cleanup/36-REVIEW.md
iteration: 3
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 36: Code Review Fix Report

**Fixed at:** 2026-10-05
**Source review:** .planning/phases/36-code-export-cleanup/36-REVIEW.md
**Iteration:** 3 (final)

**Summary:**
- Findings in scope: 7 (3 Warning, plus all 4 Info, because this is the final iteration)
- Fixed: 7
- Skipped: 0

No `src/` file was edited, so there is no solver behaviour change and nothing to reformat (the CI formatter covers only `src`, `ext`, `test` and `docs`). No canary or golden was re-pinned. The repo-wide guards still pass:
- `check_planning_ids.py`: OK, 243 files.
- `check_script_api.jl`: OK, 39 files.
- `ast_equiv.jl --selftest`: OK.

## Fixed Issues

### WR-01: `ast_equiv.jl --allow-new` accepts a path that exists neither at REF nor in the working tree

**Files modified:** `.github/scripts/ast_equiv.jl`
**Commit:** f7b0599
**Applied fix:**
- The working tree is now checked before a file is classified as NEW.
- A path that is missing both at REF and on disk prints `ERROR: <p> exists neither at REF nor in the working tree` and exits 1, with or without `--allow-new`.
- Header usage and exit docs are updated to match.
- Two selftest cases were added: `nope.jl`, and `--allow-new nope.jl`, both of which must exit 1.
- The reviewer's reproduction (`--allow-new HEAD src/admm/AgrOpt.jl src/admm/Agropt_typo.jl`) now exits 1.

### WR-02: `check_script_api.jl`: `local`/`global` assignments register the name as a function

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** 4423260
**Applied fix:**
- In the `local`/`global`/`const` branch, only `const` or a lambda/`function` right-hand side now counts as a function binding.
- `local x = f(...)` and `global x = f(...)` treat the RHS call as a use.
- Four selftests were added:
  - `local max_jump = max_jump(tr)` gives 1 finding.
  - `global max_jump = max_jump(tr)` gives 1 finding.
  - A global lambda gives 0.
  - A const alias gives 0.
- Selftest: 49 cases OK. The full scan is still OK.

### WR-03: `reactive_flake_rate.jl` still counts non-numerical errors as flakes, including Ctrl-C

**Files modified:** `scripts/reactive_flake_rate.jl`
**Commit:** 9641bb3
**Status:** fixed: requires human verification (it changes error-classification logic; the 80-solve experiment was not run)
**Applied fix:**
- **Typed catch.** Only `TSODSO.SolveFailedError` and `TSODSO.CertificateError` are counted as flakes. Everything else is rethrown: `InterruptException`, `ArgumentError`, `ConvergenceError`, `KeyError`, `BoundsError`, `OutOfMemoryError` and so on.
- **All-failed guard.** It no longer stands in for "configuration error". A 100% numerical-failure rate is now reported as a measured rate with a loud `@warn`, instead of aborting.
- **Docs.** The docstring is updated. The experiment design is unchanged.
- **To confirm:** `ConvergenceError` (ADMM hitting `maxiter = 500`) is rethrown, as the constraints require. If the experiment should count non-convergence as a flake, add it to the typed list.

### IN-01: `check_script_api.jl` treats `TSODSO` as always bound; module aliases override local bindings

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** 22121e3
**Applied fix:**
- **Unbound `TSODSO.x`.** `chain_root` now reports `TSODSO.x` once per file when the file touches TSODSO but `TSODSO` itself is not bound. That happens with `using TSODSO: x`, `import TSODSO: x`, `import TSODSO.Sub` and `import TSODSO as T`.
  - I checked this empirically: `using/import LinearAlgebra.BLAS`, `import LinearAlgebra as LA` and `using LinearAlgebra: norm` all leave `LinearAlgebra` unbound.
  - Files with no TSODSO import, i.e. included helpers, still assume it is bound.
  - `using TSODSO: TSODSO` is honoured.
- **Lookup order.** A local binding is now checked before the module-alias table. This removes the `import TSODSO as T` plus `where {T}` false positive.
- Six selftests were added. Selftest: 55 cases OK. The full scan is still OK.

### IN-02: Planning-ID guard misses `NN-NN-PLAN` / `NN-NN-NN`, `plan06-02` and Unicode-dash forms

**Files modified:** `.github/scripts/planning_id_rules.py`, `.github/scripts/check_planning_ids.py`
**Commit:** 1a80520
**Applied fix:**
- **`bare_nn`.** It now accepts a trailing `-` when the next thing is `PLAN`, `SUMMARY` or `\d\d`. A sequence like `17-20-22` is still vetoed as a range.
- **`plan`.** The separator is now `[\s\-‑–]*`, which also allows no separator at all (`plan06-02`). The pair dash also accepts a non-breaking hyphen or an en dash.
- **Bare Unicode-dash pairs (`36–22`) are deliberately not matched.** The tree has many zero-padded en-dash hour ranges, so matching them would cause false hits. This limit is recorded in a rule comment.
- Six positives were added (`36-22-PLAN`, `36-22-01`, `36-22-SUMMARY`, `plan06-02`, en dash, non-breaking hyphen). Four negatives were added, including `# 00–05 overnight trough` and `hours 17-20-22`.
- Selftest: 42 positive, 24 negative and 10 fail-closed cases OK. The tree is still clean (243 files).

### IN-03: The format job's planning-ID guard is skipped whenever formatting fails

**Files modified:** `.github/workflows/CI.yml`
**Commit:** 5b901e6
**Applied fix:**
- Added `if: ${{ !cancelled() }}` to "Check for planning identifiers", with a comment explaining why.
- I validated it by loading the YAML: it parses, and the step `if:` expressions are:
  - The API check (test job): `${{ !cancelled() && steps.buildpkg.outcome == 'success' }}`
  - Content loss: `always()`
  - The planning-ID guard: `${{ !cancelled() }}`

### IN-04: Bindings in `check_script_api.jl` are file-global and flow-insensitive

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** 973384d
**Applied fix:** I documented the limit without redesigning anything. The header has a new "Scope limits" section. It says that binding analysis is file-global and flow-insensitive, and lists the reviewer's three probes as known misses. It also says that the call-position override applies only to plain-variable bindings, that included helpers are assumed to have TSODSO bound, and that only TSODSO-owned names are checked.

---

_Fixed: 2026-10-05_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
