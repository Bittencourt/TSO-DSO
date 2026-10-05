---
phase: 36-code-export-cleanup
fixed_at: 2026-10-05T23:45:00Z
review_path: .planning/phases/36-code-export-cleanup/36-REVIEW.md
iteration: 2
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 36: Code Review Fix Report (iteration 2)

**Fixed at:** 2026-10-05T23:45:00Z
**Source review:** .planning/phases/36-code-export-cleanup/36-REVIEW.md
**Iteration:** 2 (final)

**Summary:**
- Findings in scope: 9 (6 Warning + 3 Info; Info included by explicit instruction for this final iteration)
- Fixed: 9
- Skipped: 0

**Gates after all fixes (HEAD 64bd36d):**
- `check_planning_ids.py`: OK, 243 files. Selftest: 36 positive, 20 negative, 10 fail-closed cases.
- `check_script_api.jl`: selftest 45/45 cases, all asserted. Full scan OK, 39 files.
- `ast_equiv.jl --selftest`: OK. The WR-01 rewording is EQUAL against 40b745f under the new type-strict comparison.
- `check_setup_names.py --selftest`: OK.
- `run_tests_filtered.jl --selftest`: OK.
- Targeted run `file:test_exports.jl,test_admm_knifeedge_canary.jl`: 16/16 pass.
  - Canary unchanged: `iters = 56`, `welfare = -4823.66604824162`, `escalations = 0`.
  - No golden or canary was re-pinned.
- Aqua direct script: 11/11 pass.
- JuliaFormatter 2.10.2 on the edited `src/`, `test/` and `scripts/` files made no change beyond the intended edits.
- `CI.yml` parses (`yaml.safe_load`). Step order: buildpkg, runtest, coverage, codecov, then the API check.
- No solver behaviour change. The only `src/` edits are docstring rewording (proved by ast_equiv EQUAL) and two `@compat public` additions.

## Fixed Issues

### WR-01: Plan references survive in rendered docstrings, and the guard cannot see their forms

**Files modified:** `.github/scripts/planning_id_rules.py`, `.github/scripts/check_planning_ids.py`, `src/admm/AgrOpt.jl`, `src/data/ieee123.jl`, `test/test_linear_solve.jl`
**Commit:** 73dc1fa
**Applied fix:**
- The `plan` rule now accepts `plans?[\s-]+NN-NN`, so it catches `plan-06-02`.
- `bare_nn` now allows a trailing `.`, `:` or `/NN`. It still rejects decimals (`(?!\.\d)`), clock times (`(?!:\d)`) and the existing lookbehind cases.
- Selftest positives added: `plan-06-02`, `plan-07-05`, `landed in 36-22.`, `see 36-22:`, `(26-07: device_vars`, `36-21/22`. Negatives added: `12:30-13:45`, `0.10-0.12.`.
- Before reword, the new rules found exactly the three sites the review named and nothing else in the 243-file scope, so there are no new false positives on domain ranges.
- All three sites were reworded and ast_equiv reports EQUAL.

### WR-02: compound assignment registers the callee as a local function

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** 079fa3b
**Applied fix:**
- New `is_update_assign(head)` covers every updating assignment (`+=`, `-=`, `^=`, `.+=`, `.=`, ...).
- For these, only a Symbol LHS is bound. The RHS always goes through `ref!` and is never `bind!`-ed, so it can no longer be read as a method signature.
- Four selftests added, including the review's two-line `total += max_jump(tr)` / `y = max_jump(tr2)` probe, which now gives 1 finding.

### WR-03: `ReactiveMode.X` and `using TSODSO: x as y` not validated

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** df128ab
**Applied fix:**
- New `chain_root` resolves a dotted chain from any TSODSO module in scope:
  - `TSODSO` itself;
  - a module alias (`import TSODSO as T`, `import TSODSO.ReactiveMode as RM`, `using TSODSO: ReactiveMode as RM`, tracked in the new `FileScan.modalias`);
  - an exported or imported TSODSO submodule written unrooted, unless a local binding shadows it.
- `handle_using!` now reads `x as y` items through `import_item`. It checks that `x` exists and registers `y`. Non-TSODSO `as` items now bind the alias instead of being dropped.
- Nine selftests added: `ReactiveMode.ON`, `ReactiveMode.Live`, the valid `ReactiveMode.CERTIFIED`, the rooted typo, `using TSODSO: no_such as q`, a valid rename, a module-alias chain, a submodule-alias chain, and local shadowing.
- The full scan stays OK, so all 22 unrooted `ReactiveMode.*` uses in `scripts/` and `docs/literate/` resolve.

### WR-04: `ast_equiv.jl` fails open; EQUAL blind to literal types

**Files modified:** `.github/scripts/ast_equiv.jl`
**Commit:** ce94e77
**Applied fix:**
- The REF is checked once with `git rev-parse --verify --quiet REF^{commit}`. A bad REF exits 2.
- Paths can be absolute or cwd-relative and are mapped to root-relative. A path outside the repo exits 2, and so does a call with no `.jl` path.
- A path absent at REF prints NEW and counts as a failure (exit 1) unless `--allow-new` is given.
- EQUAL now uses `streq`, a type-strict structural comparison (`typeof(a) === typeof(b) && isequal(a, b)` at the leaves, recursing into `QuoteNode`). So `1`/`1.0`, `true`/`1`, `0x01`/`1` and `0.0`/`-0.0` are all DIFF.
- New `--selftest`: 8 equality cases, plus 9 command-line fail-closed cases run on a throwaway git repo.
- The review's probes now behave as expected:
  - `ast_equiv.jl no-such-ref ...` exits 2.
  - `ast_equiv.jl HEAD $PWD/src/TSODSO.jl` resolves to `src/TSODSO.jl` and reports EQUAL.
  - A run from `src/` with relative paths works.

### WR-05: `reactive_flake_rate.jl` writes a wrong findings file

**Files modified:** `scripts/reactive_flake_rate.jl`
**Commit:** 364289b
**Applied fix:**
- `count_failures` rethrows `ArgumentError`, because a configuration refusal is not a flake.
- If every repeat fails, it throws a clear "all N repeats failed ... Refusing to write findings" error, so the script exits non-zero before it reaches the report.
- Report and findings rows are labelled `ReactiveMode.OFF` / `ReactiveMode.CERTIFIED` through `mode_label`, and the delta line now reads `(CERTIFIED - OFF)`.
- The experiment design is unchanged; Phase 37 owns that.
- Verified with a live run:
  - It exits 1 on the first solve with the `build_dso_opt` population-guard `ArgumentError`.
  - The tracked `results/reactive_flake_rate/flake_rate_findings.txt` is untouched.

### WR-06: fail-closed is per run, not per spec/path

**Files modified:** `scripts/run_tests_filtered.jl`, `.github/scripts/check_planning_ids.py`
**Commit:** a9a2fbc
**Applied fix:**
- **`run_tests_filtered.jl`:**
  - Each spec is split into atomic filters: one per tag, and one per comma-separated file name. Empty file names (`file:a.jl,`) are rejected.
  - A discovery-only preflight (`filter` always returns false) counts matches per atom. It errors with the dead atoms listed, before any test item runs.
  - Selftest gains three mixed live-plus-dead cases (`file:` list, two `file:` specs, `file:` plus a dead `tag:`) and two new malformed specs.
  - A valid `file:test_exports.jl` run still passes, at 13/13.
  - Side effect: the preflight prints an extra empty `Package | 0` test summary before the real run.
- **`check_planning_ids.py`:**
  - Exits 2 when any given path yields no in-scope file, even alongside valid paths. Example: `src typo/` now prints `ERROR: no in-scope files found under: typo/`.
  - Three selftest cases added.

### IN-01: selftest no-op case and missing coverage

**Files modified:** `.github/scripts/check_script_api.jl`
**Commit:** 49c122c
**Applied fix:**
- The `want < 0` skip is removed, so every case is asserted.
- The `PerUnitBase` case now asserts **1** finding, not the 0 the review suggested. `public` is not `export`, so a bare `PerUnitBase` after `using TSODSO` throws `UndefVarError` on every Julia version. Flagging it is correct, and I confirmed `Base.isexported(TSODSO, :PerUnitBase) == false` on 1.12.
- Qualified and explicitly imported forms of `PerUnitBase` assert 0.
- Broadcast (`max_jump.(trs)`), higher-order (`map(max_jump, trs)`) and function-as-value cases were added.
- The WR-02 and WR-03 regression cases landed with those fixes.

### IN-02: checker assumes `using TSODSO`; CI placement masks suite results

**Files modified:** `.github/scripts/check_script_api.jl`, `.github/workflows/CI.yml`
**Commit:** 0e1625a
**Applied fix:**
- `FileScan` now tracks three things: `touches` (any TSODSO import form), `using_all` (a plain `using TSODSO`, including `using TSODSO, X`), and `using_mods` (other plainly `using`-ed modules).
- In a file that imports from TSODSO but has no plain `using TSODSO`, a bare exported name that was not imported is flagged.
- That check is skipped when the name comes from Base/Core or is exported by another loaded `using`-ed module. Files with no TSODSO import at all, such as included helpers, are unaffected.
- Seven selftests added: `import TSODSO`, an `import TSODSO:` list, an explicit import, a qualified use, `using` plus `import`, a `using` list, and a no-import helper.
- **CI:**
  - The API-check step moved after `julia-runtest`, coverage and codecov, with `if: ${{ !cancelled() && steps.buildpkg.outcome == 'success' }}`.
  - `julia-buildpkg` gained `id: buildpkg`.
  - A script finding still fails the job, but it no longer skips the test suite.

### IN-03: doc-linked `MpcWindow` / `admm_supported` neither exported nor public

**Files modified:** `src/TSODSO.jl`, `test/test_exports.jl`
**Commit:** 64bd36d
**Applied fix:**
- `MpcWindow` was added to the MPC `@compat public` group and `admm_supported` to the ADMM group. Neither is exported.
- `test_exports.jl` asserts both are public and not exported on Julia 1.11 and later. The export snapshot (`keep`) is unchanged.
- Verified by the targeted test_exports and canary run plus the Aqua direct script. The docs already include both docstrings through `@autodocs`.

---

_Fixed: 2026-10-05T23:45:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
