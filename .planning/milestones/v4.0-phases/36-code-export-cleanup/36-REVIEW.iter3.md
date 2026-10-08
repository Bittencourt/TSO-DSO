---
phase: 36-code-export-cleanup
reviewed: 2026-10-05T23:10:00Z
depth: standard
iteration: 2
files_reviewed: 70
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
  - .github/scripts/check_script_api.jl
  - scripts/reactive_flake_rate.jl
  - scripts/demo_mpc_plots.jl
findings:
  critical: 0
  warning: 6
  info: 3
  total: 9
status: issues_found
---

# Phase 36: Code Review Report (iteration 2)

**Reviewed:** 2026-10-05T23:10:00Z
**Depth:** standard
**Files Reviewed:** 70
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

This is a re-review after fix commits `14e67ad..40b745f`. I read the previous report (`36-REVIEW.iter2.md`) and the fix report (`36-REVIEW-FIX.md`). For each new tool, I tested its claims against probe inputs instead of relying on its own selftest. All probes were run on Julia 1.12.5 against the loaded package, and for the Python rules through `planning_id_rules.RULES`.

**Status of the previous findings**

| ID | Status | Notes |
|----|--------|-------|
| CR-01 (`reactive_flake_rate.jl` kwarg type) | Resolved, but the fix exposes a new problem | The kwarg type is fixed. The script now runs to completion and writes a findings file whose numbers are wrong. See WR-05. |
| CR-02 (`demo_mpc_plots.jl` imports) | Resolved | |
| WR-01 (planning-ID scrub and guard) | Partially resolved | Three plan references still survive, two of them in rendered docstrings. The widened guard cannot see their forms. See WR-01. |
| WR-02 (`ast_equiv.jl` string blanking) | Resolved | Docstring-only blanking is correct, including interpolated and `@doc` forms. The tool now fails open on a bad ref or a non-root path, and its `==` comparison hides some literal-type changes. See WR-04. |
| WR-03 (`NamedTuple(::DlmpDecomposition)`) | Resolved | The keys, test and doc note are consistent. |
| WR-04 (per-unit helpers public) | Resolved | `@compat public` works on 1.10. The test is version-guarded. |
| WR-05 (vacuous pass on empty selection) | Resolved for a fully empty selection | A stale spec or path still passes when combined with a valid one. See WR-06. |

**What I verified directly**
- `check_script_api.jl` selftest: 20 cases pass. A full scan reports 39 files OK, and the result does not depend on the current directory.
- `Base.isexported` exists on Julia 1.10.11.
- CI runs the API checker after `julia-buildpkg` with only parse and load, so no solver runs.
- `check_planning_ids.py --selftest` and `check_setup_names.py --selftest` both pass.
- A rooted chain such as `TSODSO.ReactiveMode.X` is validated correctly.
- No formerly exported name was deleted outright. `OFF`, `LIVE` and `CERTIFIED` moved into `ReactiveMode`. Every other formerly exported name is still defined.

The new checker does catch the two original CR patterns. However, it has concrete false-negative paths, and two of them are on exactly the API this phase changed (WR-02, WR-03).

## Warnings

### WR-01: Plan references survive in rendered docstrings, and the guard cannot see their forms

**Files:**
- `src/admm/AgrOpt.jl:226`: docstring, "preserves the plan-06-02 standalone behavior"
- `src/data/ieee123.jl:405`: docstring, "At the plan-07-05 population ..."
- `test/test_linear_solve.jl:36`: comment, "(26-07: device_vars[k] now holds ..."
- `.github/scripts/planning_id_rules.py:15, 18`

**Issue:** `check_planning_ids.py` reports `OK: 243 files scanned` while these three plan IDs remain. Two of them render in the API Reference. I confirmed through `R.RULES` that no rule matches `plan-06-02`, `plan-07-05` or `(26-07: device`. There are two reasons:
- The `plan` rule requires whitespace after `plan`, so a hyphen (`plan-06-02`) does not match. `bare_nn` cannot catch it either, because its lookbehind rejects a preceding `-`.
- The `bare_nn` lookahead `(?![\d\w.:/\-])` rejects a trailing `.`, `:`, `/` or `-`. That means a sentence-final or label-style plan ID is invisible. I probed `landed in 36-22.`, `see 36-22:`, `27-08.` and `36-21/22`, and all of them return no hit.

The "ascending unpadded pair" veto is not what lets these through. A sweep of every in-scope `NN-NN` with the veto removed found only these three sites.

**Fix:**
```python
'plan':    r'(?i)\bplans?[\s-]+\d{1,2}-\d{2}\b',
# allow sentence/label punctuation after the pair, but keep decimals excluded:
'bare_nn': r'(?<![\w.:/\-])(\d\d)-(\d\d)(?![\d\w/\-])(?!\.\d)(?!:\d)',
```
Add `plan-06-02`, `(26-07: x`, `see 36-22.` and `36-22:` to the selftest positives. Keep `0.10-0.12` and `12:30-13:45`-style cases as negatives. Then reword the three sites.

### WR-02: `check_script_api.jl`: a compound assignment registers the callee as a local function for the whole file

**File:** `.github/scripts/check_script_api.jl:286-301`
**Issue:** The compound-assignment branch (`h in (:+=, :-=, :*=, :/=)`) sends every argument to `bind!`, including the right-hand side. `bind!` on an `Expr(:call)` calls `bind_signature!`, which treats the call as a method definition. It adds the callee to `fbound` and its arguments to `bound`.

As a result, `total += max_jump(tr)` makes `max_jump` count as a locally defined function for the entire file. Every other hidden-name use is then suppressed as well, not just this line. I reproduced this with a two-line probe: `total += max_jump(tr)` followed by `y = max_jump(tr2)`. The checker reported `OK` and exit 0. Without the `+=` line, the same file is flagged.

**Fix:** Bind only the left-hand side and treat the right-hand side as a reference:
```julia
elseif h in (:+=, :-=, :*=, :/=) && A[1] isa Symbol
    bind!(fs, A[1]); ref!(fs, A[2])
elseif h in (:(=), :const, :local, :global)
    ...
```
Also add a selftest case: `"using TSODSO\ns = 0\ns += max_jump(t)"` should produce 1 finding.

### WR-03: `check_script_api.jl` does not validate `ReactiveMode.X` or `using TSODSO: x as y`, the forms this phase introduced

**File:** `.github/scripts/check_script_api.jl:179-181` (`check_qualified!`), `:198`, `:214`
**Issue:** The header promises that "removed or renamed API" is caught. Two common forms slip through.

1. **Submodule chains not rooted at `TSODSO`.** `check_qualified!` returns early unless `parts[1] === :TSODSO`. `ReactiveMode` is exported, and every one of the 22 `ReactiveMode.*` uses in `scripts/` and `docs/literate/` is written unrooted (`ReactiveMode.OFF`). A typo or later rename is therefore never checked. My probe confirmed this: `x = ReactiveMode.ON` and `reactive_consensus = ReactiveMode.Live` give no finding, while `TSODSO.ReactiveMode.ON` is flagged.
2. **Renamed imports.** In `using TSODSO: a, b`, the `names_` comprehension (line 198) keeps only `Expr(:.)` items. An `Expr(:as)` item is dropped, so the imported name is never checked for existence. The probe `using TSODSO: no_such_xyz as q` returned OK.

**Fix:**
```julia
# check_qualified!: also resolve chains rooted at an exported/imported TSODSO module
root = parts[1] === :TSODSO ? MOD :
       (parts[1] ∉ fs.bound && isdefined(MOD, parts[1]) &&
        getfield(MOD, parts[1]) isa Module) ? getfield(MOD, parts[1]) : nothing
root === nothing && return
# walk parts[2:end] from `root` (parts[3:end] when rooted at TSODSO)

# handle_using!: accept `as` items
for b in a.args[2:end]
    inner = b isa Expr && b.head === :as ? b.args[1] : b
    n = inner isa Expr && inner.head === :. ? inner.args[1] : nothing
    alias = b isa Expr && b.head === :as ? b.args[2] : n
    ...  # check isdefined(m, n); push!(fs.imported, alias)
end
```
Add selftest cases for `ReactiveMode.ON` (1 finding) and `using TSODSO: nope as q` (1 finding).

### WR-04: `ast_equiv.jl` fails open, and `EQUAL` does not prove that literals are unchanged

**File:** `.github/scripts/ast_equiv.jl:62-66, 93, 100-104, 111`
**Issue:** The tool was used to certify that every `src/` scrub edit is comment- or docstring-only. Two gaps remain.

1. **Fail-open.**
   - When `git show REF:path` fails, the file is printed as `NEW` and does not count against the exit code.
   - So a mistyped ref, a ref missing from a shallow CI clone, an absolute path, or a cwd-relative path from a subdirectory all yield "NEW ..." for every file and exit 0.
   - Reproduced: `ast_equiv.jl no-such-ref src/TSODSO.jl src/pricing/dlmp.jl` and `ast_equiv.jl HEAD $PWD/src/TSODSO.jl` both exit 0.
2. **Literal-type blindness.**
   - `norm(eo) == norm(en)` compares `Expr` arguments with `==`, which treats `1 == 1.0`, `true == 1` and `0x01 == 1` as equal.
   - A probe changing `x + 1` to `x + 1.0`, `flag = true` to `flag = 1`, and `0x01` to `1` reports `EQUAL`.
   - These edits change types and dispatch, so an `EQUAL` verdict does not "prove a docs/comment-only change" as the header claims. The old `hash`-based comparison had the same blind spot.

**Fix:**
```julia
# verify the ref once, fail closed
success(`git rev-parse --verify --quiet $ref^{commit}`) || (println("bad REF $ref"); return 2)
# make paths root-relative; treat NEW as a failure unless --allow-new is given
# type-strict structural equality:
streq(a, b) = a isa Expr ? (b isa Expr && a.head === b.head && length(a.args) == length(b.args) &&
                            all(streq.(a.args, b.args))) :
              (typeof(a) === typeof(b) && isequal(a, b))
```

### WR-05: `reactive_flake_rate.jl` now silently writes a wrong "measured flake rate" findings file

**File:** `scripts/reactive_flake_rate.jl:296-321, 384-424, 426-500`
**Issue:** This is not a re-raise of the accepted experiment-design problem. It is the effect the CR-01 fix has on that problem.
- **Before the fix**, the script failed loudly at the first call boundary (`TypeError`) and wrote nothing.
- **After the fix:**
  - Every one of the 80 solves throws the deterministic `ArgumentError` from the `build_dso_opt` population guard. The fix report confirms this.
  - The catch-all `catch e` at line 315 counts each of these as a "flake".
  - The script then writes `results/reactive_flake_rate/flake_rate_findings.txt`, headed "Measured NUMERICAL_ERROR-class flake rates". It contains rates of 1.000 for both modes, a delta of 0, and the sentence "This is a citable finding".
- That turns a refused configuration into a plausible-looking research artifact. The project's core value is trustworthy results, so this is a regression in kind, from a loud failure to a silent wrong output.
- **Stale labels:** the report table still labels the modes `"false"` and `"true"` (lines 396, 404, 412, 420, 446, ...) and says "Delta (true - false)". This is stale relative to the `ReactiveMode.OFF` / `CERTIFIED` header that the fix introduced.

**Fix:** This needs no redesign. Rethrow non-numerical errors, and refuse to write findings when every repeat failed:
```julia
catch e
    e isa ArgumentError && rethrow()          # configuration refusal, not a flake
    failures += 1
    ...
end
...
failures == n_repeats && error("all $n_repeats repeats failed for $reactive_consensus — not a flake measurement")
```
Also replace the `"false"`/`"true"` labels with `string(ReactiveMode.OFF)` / `string(ReactiveMode.CERTIFIED)`.

### WR-06: Fail-closed is per run, not per spec or path, so a stale filter still passes silently

**Files:** `scripts/run_tests_filtered.jl:27-35`; `.github/scripts/check_planning_ids.py:105, 115-118`
**Issue:**
- **`run_tests_filtered.jl`:** a single `nmatch` counter covers the OR of every spec and every comma-separated file name. So `tag:phase7 file:test_exports.jl` (with a renamed tag) and `file:test_exports.jl,old_name.jl` (with a renamed file) both run green. The stale part selects nothing, and nothing reports it. That is the exact scenario the previous WR-05 described ("a stale `tag:phase7` or `file:old_name.jl` in a plan ... passes").
- **`check_planning_ids.py`:** `check_planning_ids.py src typo/` is the same case. The empty-scope check only fires when the whole union is empty.

**Fix:** Count matches per predicate. For `file:` specs, count per file name. Fail if any count is zero:
```julia
counts = zeros(Int, length(preds))
filt = ti -> (hits = map(p -> p(ti), preds); counts .+= hits; any(hits))
...
dead = [specs[i] for i in eachindex(specs) if counts[i] == 0]
isempty(dead) || error("filter(s) matched no @testitem: $(join(dead, ' ')) (fail-closed)")
```
In `check_planning_ids.py`, check each `paths` entry against `files` and raise `GuardError` for any entry with no match.

## Info

### IN-01: The `check_script_api.jl` selftest contains a no-op case and misses the known gaps

**File:** `.github/scripts/check_script_api.jl:474, 481`
**Issue:**
- The `PerUnitBase` case has `want = -1` and is skipped by `want < 0 && continue`, so it asserts nothing while being counted in "20 cases".
- The selftest has no case for compound assignment, the `as` import form, unrooted submodule chains, or broadcast/`map(f, ...)` value use. These are the forms behind WR-02 and WR-03.

**Fix:** Now that WR-04 has landed, make the `PerUnitBase` case `want = 0` on Julia 1.11 and later. Add regression cases for WR-02 and WR-03.

### IN-02: The API checker assumes `using TSODSO`, and its CI placement masks suite results

**File:** `.github/scripts/check_script_api.jl:451-456`; `.github/workflows/CI.yml:43-48`
**Issue:**
- **Assumed `using TSODSO`.** `exported_set()` is treated as in scope in every file, whether the file did `using TSODSO` or only `import TSODSO` / `import TSODSO: a, b`. `scripts/thesis_caseA.jl:108` uses the `import TSODSO:` form. A bare exported name in such a file throws `UndefVarError` at runtime but passes the check.
- **CI placement.** The step runs before `julia-runtest` without `if: always()`. A single script finding therefore skips the entire test suite on all three matrix versions. The job stays red, but the suite's diagnostic output is lost.

**Fix:**
- Record whether the file contains `using TSODSO` (or `using TSODSO, ...`), and treat exported names as in scope only when it does.
- Move the step after `julia-runtest`, or add `if: always()` to `julia-runtest`.

### IN-03: Doc-linked types and traits that are neither exported nor public

**File:** `src/models/mpc_window.jl:61`; `docs/literate/mpc_rolling_horizon.jl:62`; `docs/literate/admm.jl:52`
**Issue:**
- `MpcWindow` is the return type of the public `build_mpc_window`, and the MPC tutorial links to it. However, it is neither exported nor `public`.
- `admm_supported` is in the same position, linked from the ADMM tutorial.

Under the new module-docstring policy, both are "internal helpers ... no stability promise", yet the manual presents them as API. This is the same class of issue as the previous WR-04, at a lower impact because they are only referenced, not called.

**Fix:** Add `MpcWindow` and `admm_supported` to the appropriate `@compat public` groups. Alternatively, drop the `@ref` links from the tutorials.

---

_Reviewed: 2026-10-05T23:10:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
