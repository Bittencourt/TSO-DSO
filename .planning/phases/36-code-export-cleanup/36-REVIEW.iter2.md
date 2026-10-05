---
phase: 36-code-export-cleanup
reviewed: 2026-10-05T21:58:29Z
depth: standard
files_reviewed: 67
files_reviewed_list:
  - docs/make.jl
  - docs/src/api.md
  - docs/src/status_policy.md
  - .github/scripts/ast_equiv.jl
  - .github/scripts/check_planning_ids.py
  - .github/scripts/check_setup_names.py
  - .github/scripts/check_suite_log.py
  - .github/scripts/classify_planning_ids.py
  - .github/scripts/format210.jl
  - .github/scripts/planning_id_allowlist.txt
  - .github/scripts/planning_id_rules.py
  - .github/scripts/suite_detached.sh
  - .github/scripts/thesis_tokens.py
  - .github/workflows/CI.yml
  - Project.toml
  - scripts/run_tests_filtered.jl
  - src/admm/admm_phases.jl
  - src/admm/admm_state.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/ReactiveMode.jl
  - src/admm/residuals.jl
  - src/admm/solve_admm.jl
  - src/core/balance.jl
  - src/data/ieee123.jl
  - src/data/ieee8500.jl
  - src/data/mesh_topology.jl
  - src/data/profiles.jl
  - src/devices/AbstractDevice.jl
  - src/devices/Aggregator.jl
  - src/devices/PVBattery.jl
  - src/experiments/materialize.jl
  - src/experiments/strategies.jl
  - src/models/ac_dual_fallback.jl
  - src/models/ac_oracle.jl
  - src/models/exactness.jl
  - src/models/mpc_trace.jl
  - src/models/mpc_window.jl
  - src/models/oracle.jl
  - src/models/stochastic_welfare.jl
  - src/planning/ac_recheck.jl
  - src/planning/benders.jl
  - src/planning/bilevel_kkt.jl
  - src/planning/checkpoint.jl
  - src/planning/coupling.jl
  - src/planning/feasibility_oracle.jl
  - src/planning/follower.jl
  - src/planning/master_integer.jl
  - src/planning/master.jl
  - src/planning/nash.jl
  - src/planning/retry.jl
  - src/planning/subproblem.jl
  - src/planning/trace.jl
  - src/powerflow/AbstractPowerFlow.jl
  - src/powerflow/RestrictedBranchFlow.jl
  - src/pricing/dlmp.jl
  - src/pricing/fit.jl
  - src/solver/factory.jl
  - src/solver/ProblemClass.jl
  - src/solver/problem_class_trait.jl
  - src/TSODSO.jl
  - src/units/PerUnit.jl
  - test/test_exports.jl
  - test/test_oracle.jl
  - test/test_planning_oracle.jl
  - test/test_pricing_dlmp.jl
  - test/test_reactive_mode.jl
findings:
  critical: 2
  warning: 5
  info: 6
  total: 13
status: issues_found
---

# Phase 36: Code Review Report

**Reviewed:** 2026-10-05T21:58:29Z
**Depth:** standard
**Files Reviewed:** 67
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

I reviewed the Phase 36 diff (`438e162^..HEAD`) for the 67 in-scope files. Checks covered:

- the API removals (oracle kwargs, `_coupling_dual` z-path, reactive Bool/Symbol shim, `DlmpDecomposition` aliases);
- the `ReactiveMode` submodule;
- the export trim and the `@compat public` block;
- the new `.github/scripts` tooling and the CI wiring.

I also cross-checked `scripts/`, `docs/literate/`, `ext/` and `bench/` against the live unexported/public name set, which I dumped from a loaded `TSODSO` on Julia 1.12.5.

The `src/` side of the change is sound:
- `ReactiveMode.T` annotations, defaults and `normalize_reactive_mode` are consistent.
- The `@compat public` list resolves: all 84 names are defined, and the multi-line form parses on 1.10.11.
- `Base.isexported` exists on 1.10.
- The ext modules qualify every unexported name.
- `operational_oracle` and `_coupling_dual` have no leftover callers.

The defects are concentrated where the phase's own gates do not reach:
- **Researcher scripts** are not run by the suite or the docs build. Two of them are now broken by the shim removal and the export trim.
- **The planning-ID guard and the AST-equivalence tool** promise more than they check:
  - Planning-artifact references (`STATE.md`, `ROADMAP`, `MEMORY.md`, memory files) still survive in `src/`.
  - 12 `src/` files whose user-visible runtime strings changed were classed as "comment-only, AST-equal".
- **The test runner** silently passes when a filter matches nothing.

## Critical Issues

### CR-01: `scripts/reactive_flake_rate.jl` is unrunnable: Bool-typed kwarg now receives `ReactiveMode.T`

**File:** `scripts/reactive_flake_rate.jl:289` (callers at 343, 354, 363, 374)
**Issue:** The migration rewrote the four call sites from `reactive_consensus = false/true` to `ReactiveMode.OFF/CERTIFIED`. It did not change the local helper's signature, which still declares `reactive_consensus::Bool`:

```julia
function count_failures(feeder, aggs, λ₀; reactive_consensus::Bool, n_repeats::Int = 20, seed_offset::Int = 0)
...
fail_13_false = count_failures(feeder13, aggs13, λ0_13; reactive_consensus = ReactiveMode.OFF, ...)
```

The first measurement throws `TypeError: in keyword argument reactive_consensus, expected Bool, got a value of type TSODSO.ReactiveMode.T` before any solve runs. `try/catch` cannot hide it because the failure happens at the call boundary, outside the `try`. No gate exercises `scripts/`: the suite, the docs build and the "0 sites" migration scan all missed it.

The header comment (line 8, "`reactive_consensus ∈ (false, true)`") and the docstring at 274 are also stale.

**Fix:**
```julia
function count_failures(feeder, aggs, λ₀; reactive_consensus::ReactiveMode.T, n_repeats::Int = 20, seed_offset::Int = 0)
```
Also update the header comment to `ReactiveMode.OFF` / `ReactiveMode.CERTIFIED`, and add a parse-and-load smoke check for `scripts/*.jl` (e.g. `include` under a `--dry-run` guard, or JET `report_file`) so the next export trim is caught.

### CR-02: `scripts/demo_mpc_plots.jl` calls unexported `max_jump` / `mean_jump` unqualified

**File:** `scripts/demo_mpc_plots.jl:126-127, 164-165, 184-185, 194-195, 203-204, 222+, 522`
**Issue:** `max_jump` and `mean_jump` were removed from `export` in `src/models/mpc_trace.jl` and are now only `@compat public` (`src/TSODSO.jl:331-332`). The script's explicit import list (lines 43-49) brings in `any_cert_failed`, `build_feeder`, `build_mpc_window`, `build_population`, `build_price` and `solve_mpc_window!`, but not these two. The first `max_jump(r.trace)` at line 126 therefore throws `UndefVarError: max_jump not defined in Main`.

`36-FINAL-GATES.md` records the unexport migration scan as "0 sites in 0 files", but this site was missed. A likely cause is that the NamedTuple form `max_jump = max_jump(r.trace)` at line 164 made the tool treat the name as a local binding.
**Fix:**
```julia
using TSODSO:
    any_cert_failed,
    build_feeder,
    build_mpc_window,
    build_population,
    build_price,
    max_jump,
    mean_jump,
    solve_mpc_window!
```

## Warnings

### WR-01: The planning-ID scrub is incomplete and the guard has false-negative gaps

**Files:** `.github/scripts/planning_id_rules.py:14-28`; surviving hits at `src/planning/nash.jl:1076`, `src/powerflow/MeshedFlow.jl:53`, `src/experiments/mpc_loop.jl:1399`, `src/pricing/dlmp.jl:253`, `test/test_planning_feasibility_oracle.jl:76`
**Issue:** CONTEXT says comments citing planning artifacts by name are planning references and must be scrubbed and guarded. The `artifact` rule only covers `RESEARCH`, `CONTEXT.md`, `-SUMMARY`, `-REVIEW.md`, `.planning/`, `USER DECISION`, `code review`, `quick task` and `spike NNN`. These survive in rendered docstrings and comments, and the guard reports OK:
- `nash.jl:1076`: "(STATE.md's own carried blocker)", in a docstring.
- `MeshedFlow.jl:53`: "(the ROADMAP's hard constraint)", in a docstring.
- `mpc_loop.jl:1399`: "(memory `v2.1-socp-inexactness-and-thesis-repro.md`)", a reference to a private Claude memory file.
- `dlmp.jl:253`: "Review fix (2026-09-29): ..."
- `test_planning_feasibility_oracle.jl:76`: "the repo's own MEMORY.md".

The numeric rules also have blind spots, all confirmed by probing the compiled regexes:
- `bare_nn` caps the plan part at `(?:0\d|1\d|20)`, so `(36-21)` and `see 36-22` (both plans in this phase) pass.
- Phases ≥ 40 pass, e.g. `40-01`.
- `task` matches a single digit only, so `Task 12` passes.

**Fix:** Extend `artifact` with `STATE\.md|ROADMAP|REQUIREMENTS\.md|MEMORY\.md|-PLAN\.md|-VERIFICATION|FINDINGS\.md|\bmemory\s+`|[Rr]eview fix`. Widen `bare_nn` to `(?:[0-9]\d)-(?:[0-9]\d)` and keep its existing lookarounds; the negative selftests still pass because dates and decimals are excluded by the lookbehind. Change `task` to `\bTask\s+\d+\b`. Add the new forms to `--selftest` positives, then rewrite the five lines above.

### WR-02: `ast_equiv.jl` blanks every string, so "AST-equal" does not prove "comment-only"

**File:** `.github/scripts/ast_equiv.jl:8`
**Issue:** `norm` maps every `String` to `""`, not only docstrings. That includes:
- error, `@warn` and `@info` messages;
- Dict and CSV keys;
- regex bodies (`r"..."` is a macrocall with a String arg);
- command literals (`` `...` ``);
- `@printf` format strings.

An `EQUAL` verdict therefore only proves the code is equal modulo all string literals. The "~170 files proven comment-only" classification inherits this weakness. Running `ast_equiv.jl --strings 438e162^` over `src/` shows runtime-string changes in 12 files that are outside this review's file list:

`FourQuadBESS.jl`, `Scenario.jl`, `mpc_loop.jl` (16 strings, including the `run_mpc` `@warn` messages), `run_stochastic.jl`, `complementarity_4q.jl`, `mesh_angle_certificate.jl`, `restriction_exactness.jl`, `welfare_solve.jl`, `ConvexBranchFlow.jl`, `LinDistFlow.jl`, `checks.jl`, `welfare.jl`.

The rewrites I inspected are benign. However, these files carry user-visible message changes and were excluded from logic review on a proof that does not cover them.
**Fix:** Blank only docstrings in the default mode, and compare all other strings exactly. Alternatively, make the default mode fail when `collect_strings!` multisets differ, and keep the current behaviour behind an explicit `--ignore-strings` flag.
```julia
function norm(x; indoc=false)
    x isa String && return indoc ? "" : x
    x isa LineNumberNode && return nothing
    x isa Expr || return x
    d = isdoc(x)
    Expr(x.head, (norm(a; indoc = d && i == 3) for (i, a) in enumerate(x.args) if !(a isa LineNumberNode))...)
end
```
Note that the index shifts once the LineNumberNode is dropped, so compute `i` before filtering.

### WR-03: The deprecated `loss` / `voltage` names survive in `NamedTuple(::DlmpDecomposition)`

**File:** `src/pricing/dlmp.jl:250-273`; `docs/src/status_policy.md:124-125`
**Issue:** The Breaking-changes note says the deprecated `.loss` and `.voltage` properties are removed and tells users to use `.cone` and `.drop`. However, `Base.NamedTuple(d)` still produces keys `(:energy, :loss, :congestion, :voltage, :reactive, :total)`, and `test/test_pricing_dlmp.jl:577-585` pins that. The deprecated vocabulary therefore remains public, exported-type API through the conversion, and the user doc does not mention it.

The conversion's docstring also still opens with a dated "Review fix (2026-09-29)" provenance line (see WR-01).
**Fix:** Pick one of two options:
- Remove the conversion along with the aliases and list it in status_policy §7.
- Keep it as an explicitly legacy-shaped helper, rename it (e.g. `legacy_namedtuple(d)`) so `NamedTuple(d)` is not silently old-vocabulary, and document it under Breaking changes.

### WR-04: The Rung-0 tutorial depends on names that are neither exported nor public

**File:** `docs/literate/toy_dc.jl:31-34`; `src/TSODSO.jl:33-40`
**Issue:** The first manual page now does `using TSODSO: I_base, PerUnitBase, Z_base`. All three were unexported in this phase and are not in any `@compat public` block; `Base.ispublic` is `false` for each. The new module docstring states that such names are "purely internal helpers ... carry no stability promise". The entry tutorial therefore teaches researchers to depend on non-API names. The same applies to `to_pu_impedance` and `to_pu_power`, which ingestion code is told to use (`src/units/PerUnit.jl` header).
**Fix:** Add `PerUnitBase, Z_base, I_base, to_pu_impedance, to_pu_power` to a `@compat public` block (Units). Alternatively, rewrite the tutorial to avoid them.

### WR-05: Tooling passes vacuously on an empty match set

**Files:** `scripts/run_tests_filtered.jl:9-20`; `.github/scripts/check_planning_ids.py:128`; `.github/scripts/check_setup_names.py:14`
**Issue:**
- `run_tests_filtered.jl` exits 0 when no `@testitem` matches the filters. This phase renamed `:phase7` / `:phase25` and the fixture files, so a stale `tag:phase7` or `file:old_name.jl` in a plan, CI job or note now "passes" while running nothing. This is the same green-on-nothing pattern as the TestItemRunner trap in project memory. A spec without `:` also dies with an opaque `BoundsError` from destructuring `split`.
- `check_planning_ids.py` prints `OK: 0 files scanned` and exits 0 when the git scope is empty (wrong cwd, sparse checkout, or a typo'd path argument). That contradicts its "fail-closed" contract.
- `check_setup_names.py` globs the relative path `test/**`, so from any cwd other than the repo root it reports "0 testmodules, 0 setup uses, 0 unresolved" and exits 0.

**Fix:**
```julia
# run_tests_filtered.jl
occursin(':', s) || error("filter spec must be tag:<sym> or file:<...>, got $s")
# count matches before running; error if zero
```
```python
# check_planning_ids.py, after computing `files`
if not files:
    print("ERROR: no in-scope files found", file=sys.stderr); return 2
# check_setup_names.py
os.chdir(subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip())
if not mods: print("no @testmodule found"); sys.exit(2)
```

## Info

### IN-01: Scrub left dangling punctuation in a rendered docstring and a comment

**File:** `src/pricing/dlmp.jl:285-286`; `src/planning/nash.jl:349`
**Issue:**
- In `dlmp.jl`, the docstring paragraph now reads "...so a missing term is localizable\n). This 4-term reconstruction..." because "(RESEARCH Pitfall 2; threat T-05-02)" was removed down to just its closing parenthesis. It renders in the API Reference.
- In `nash.jl`, the comment reads "progress (, iter 2)".

**Fix:** Change the `dlmp.jl` line to "...so a missing term is localizable. This 4-term reconstruction...". Reword the `nash.jl` comment to "progress (from iteration 2)" or drop the parenthetical.

### IN-02: The module docstring points to a non-existent "architecture" page

**File:** `src/TSODSO.jl:39-40`
**Issue:** The docstring says "See the API and architecture pages of the documentation". `docs/make.jl` has no architecture page; `docs/src` only has `index.md`, `api.md`, `status_policy.md` and `generated/`.
**Fix:** Say "See the API Reference and the Status & Exception Policy pages", or add the page.

### IN-03: Guard rules are prone to false positives on domain prose, and `Manifest.toml` is in scope

**File:** `.github/scripts/planning_id_rules.py:16-19, 37`
**Issue:**
- `wave` matches any "wave" or "waves" word, case-insensitively ("square wave").
- `dec` matches the power-market term "D-1" (day-ahead).
- `bare_nn` matches hour ranges such as "17-20".
- `SCOPE_EXTS` includes `.toml`, so the generated `test/Manifest.toml` is scanned. A package name or version could block a manifest re-resolve with a confusing guard failure.

**Fix:** Require a digit for `wave` (`\bwaves?[\s-]?\d\b`). Exclude `Manifest.toml`. Accept allowlist entries for genuine domain terms.

### IN-04: The CI planning-ID step is masked by formatter failures, and the selftest is not run

**File:** `.github/workflows/CI.yml:107-109`
**Issue:** The new step has no `if: always()`, so any formatter failure skips it and planning-ID hits only surface on the next push. `--selftest` is never executed in CI, so a regex regression in `planning_id_rules.py` would go unnoticed.
**Fix:** Add `if: always()` and run `python3 .github/scripts/check_planning_ids.py --selftest && python3 .github/scripts/check_planning_ids.py`.

### IN-05: Phase-specific constants in committed tooling, plus small robustness gaps

**Files:** `.github/scripts/check_suite_log.py:13, 75-80`; `.github/scripts/suite_detached.sh:9-17`; `.github/scripts/format210.jl:11-13`; `.github/scripts/check_planning_ids.py:96-100`
**Issue:**
- **Hard-coded values.** `.planning/tmp/36`, `Broken == 5` and the canary literals are hard-coded in `.github/scripts`, outside the guard's scope, so these tools are single-use.
- **`suite_detached.sh`:**
  - It writes `$DONE` non-atomically (`echo $? > "$DONE"`), so `check_suite_log.py` can read an empty marker and report a spurious failure.
  - Nothing prevents a second launch with the same LABEL while one is running (the orphan race noted in project memory).
- **`check_suite_log.py`:** it verifies that the run is newer than HEAD, but not that the working tree was clean.
- **`format210.jl`:** it `cd`s to the repo root before `format(ARGS)`, so relative paths given from a subdirectory resolve wrongly.
- **`check_planning_ids.py`:** `--allowlist` or `--root` without a value yields `None`. For `--allowlist`, that ends in a `TypeError` traceback (exit 1, not 2).

**Fix:**
- Parameterize the phase directory and expectations through CLI flags.
- Write the marker atomically (`echo $? > "$DONE.tmp" && mv "$DONE.tmp" "$DONE"`) and add a pidfile check.
- Check `git status --porcelain` at launch.
- Validate option arguments.

### IN-06: The provenance docstring contradicts storing a TSODSO enum

**File:** `src/experiments/store.jl:175-191` (consumer of the `ReactiveMode.T` change)
**Issue:** `result_to_dict` says "Only primitives/arrays are stored ... so the JLD2 loads without TSODSO types". It then stores `res.reactive_consensus_mode`, which is a `TSODSO.ReactiveMode.T`. This phase changed that type's path, and status_policy §7 now has to warn that old files load "with a reconstructed type". This is a pre-existing contradiction, made concrete by the module move.
**Fix:** Store `string(res.reactive_consensus_mode)` (e.g. `"LIVE"`) so stored artifacts are type-free and immune to future renames, and correct the docstring.

---

_Reviewed: 2026-10-05T21:58:29Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
