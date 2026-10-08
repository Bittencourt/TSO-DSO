---
phase: 36-code-export-cleanup
reviewed: 2026-10-05T23:59:00Z
depth: standard
iteration: 3
files_reviewed: 71
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
  - test/test_linear_solve.jl
  - .github/scripts/check_script_api.jl
  - scripts/reactive_flake_rate.jl
  - scripts/demo_mpc_plots.jl
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 36: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-05T23:59:00Z
**Depth:** standard
**Files Reviewed:** 71
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

This is a re-review after fix commits `73dc1fa..64bd36d`. I checked each prior finding against probe inputs written to slip past it, not against the tool's own selftest. Everything ran on Julia 1.12.5 with the package loaded.

**Status of the previous findings**

| ID | Status | Evidence |
|----|--------|----------|
| WR-01 (guard misses `plan-06-02` and `36-22.`) | Resolved | 24 probes. Hyphenated plan refs and trailing `.`, `:`, `,`, `;`, `)`, `/` are all caught. Decimals and clock times are still excluded. The guard reports `OK: 243 files`, and the selftest gives 36 positive, 20 negative and 10 fail-closed cases. Latent gaps remain (IN-02). |
| WR-02 (`+=` binds the callee) | Resolved | `s += f(x)`, `global s += f(x)`, `v[1] += f(x)`, `a += f(x)` after destructuring and `.-=` are all flagged. A neighbouring assignment form still has the same bug (WR-02 below). |
| WR-03 (unrooted `ReactiveMode.X`, `as` imports) | Resolved | Unrooted, rooted, `import TSODSO.ReactiveMode` and `import TSODSO.ReactiveMode: ON` typos are all flagged. |
| WR-04 (`ast_equiv` fail-open, literal types) | Mostly resolved | A bad REF, a `REF:path` passed as REF, and a run from `src/` with relative paths all behave correctly. Type-strict `streq` is correct for `QuoteNode`, `-0.0` and `NaN`. One fail-open path remains under `--allow-new` (WR-01 below). |
| WR-05 (flake script writes wrong findings) | Partially resolved | The all-failed run now aborts. Non-numerical errors are still counted as flakes, including Ctrl-C (WR-03 below). |
| WR-06 (per-spec / per-path fail-closed) | Resolved | `run_tests_filtered.jl --selftest` passes, including the three mixed live-plus-dead cases. A dead filter fails in the preflight, before any test item runs. `check_planning_ids.py src typo` exits 2. |
| IN-01 / IN-02 / IN-03 | Resolved | See the CI and test notes below. |

**CI.yml semantics, checked by hand because actionlint is unavailable.** The YAML parses. Step order is checkout, setup-julia, cache, buildpkg (`id: buildpkg`), runtest, processcoverage, codecov, then the API check.
- **The `if:` condition is correct.** `!cancelled() && steps.buildpkg.outcome == 'success'` contains a status-check function, so GitHub does not add an implicit `success()`.
- **Test failure.** If `julia-runtest` fails, the API check still runs and the job stays red.
- **Build failure.** If `buildpkg` fails or is skipped, the API check is skipped.
- **Cancellation or timeout.** On cancel or a timeout, the API check is skipped.
- **Shell.** `shell: bash` runs with `-eo pipefail`, so a selftest failure stops the full scan and fails the step.
- **Julia 1.10.** The checker uses only `Base.isexported`, which exists on 1.10. The `PerUnitBase` selftest asserts 1 finding, which holds on every version.

**Other checks**
- **`test_exports.jl`.** The new `ispublic` assertions sit inside the existing `@static if VERSION >= v"1.11"` guard.
- **Docstring rewording.** `ast_equiv.jl 40b745f` reports EQUAL for `src/admm/AgrOpt.jl`, `src/data/ieee123.jl` and `test/test_linear_solve.jl`.
- **Script scan.** `check_script_api.jl` passes its selftest (45 cases), and a full scan reports 39 files OK.

## Warnings

### WR-01: `ast_equiv.jl --allow-new` accepts a path that exists neither at REF nor in the working tree

**File:** `.github/scripts/ast_equiv.jl:148-154`
**Issue:** `gitshow` returning `nothing` is read as "the file is new". The tool never checks that the file actually exists in the working tree. With `--allow-new`, a mistyped path is therefore certified.

Reproduced:
```
$ julia .github/scripts/ast_equiv.jl --allow-new HEAD src/admm/AgrOpt.jl src/admm/Agropt_typo.jl
EQUAL src/admm/AgrOpt.jl
NEW src/admm/Agropt_typo.jl
exit=0
```
- **With `--allow-new`:** this is the exact fail-open class that WR-04 set out to close. A typo'd or stale path passes, and the file the author meant to certify is never compared.
- **Without `--allow-new`:** the same typo is mislabelled `NEW ... (absent at REF)` instead of "no such file". That points the user towards `--allow-new` as the remedy.

**Fix:** Check the working tree before classifying a file as NEW:
```julia
old = gitshow(root, ref, p)
file = joinpath(root, p)
if !isfile(file)
    println(old === nothing ? "ERROR: $p0 exists neither at $ref nor in the working tree" :
                              "MISSING $p (absent in working tree)")
    bad = true
    continue
end
if old === nothing
    println("NEW $p", allow_new ? "" : " (absent at $ref; pass --allow-new to accept)")
    allow_new || (bad = true)
    continue
end
```
Add a selftest case: `q("--allow-new", "HEAD", "nope.jl") == 1`.

### WR-02: `check_script_api.jl`: `local`/`global` assignments register the name as a function, so `local max_jump = max_jump(tr)` slips through

**File:** `.github/scripts/check_script_api.jl:374-376`
**Issue:**
- **The contract.** The header (lines 18-19) promises that "a call `f(...)` of such a name is flagged even if the file also binds `f` as a plain variable ... (the `max_jump = max_jump(tr)` pattern)". The plain `=` branch (line 367) honours this by binding with `fn = false`.
- **The bug.** The `local`/`global`/`const` branch binds every `x = ...` with `fn = true` (line 376). That puts the name in `fbound`, which legitimises calls to it everywhere in the file.
- **Probes.** Both of these report 0 findings, although each throws `UndefVarError` at runtime:
  ```julia
  using TSODSO
  function g(tr)
      local max_jump = max_jump(tr)
  end
  ```
  ```julia
  using TSODSO
  global max_jump = max_jump(tr)
  ```
- **Why it is realistic.** `scripts/` uses `global x = ...` heavily (`demo_mpc_plots.jl:420-426`, `demo_flexibility_plots.jl:256`, `benders_toy.jl:157`). No current script hits this, so it is latent, but it is the same "an assignment form legitimises a hidden callee" class that WR-02 just fixed for `+=`.

**Fix:** Only `const` (and an RHS that is a lambda or function) should count as a function binding:
```julia
for a in A
    if a isa Expr && a.head === :(=)
        isfn = h === :const || (a.args[2] isa Expr && a.args[2].head in (:->, :function))
        bind!(fs, a.args[1]; fn = isfn); ref!(fs, a.args[2])
    else
        h === :const ? ref!(fs, a) : bind!(fs, a)
    end
end
```
Add the two probes above to the selftest, each expecting 1 finding.

### WR-03: `reactive_flake_rate.jl` still counts non-numerical errors as flakes, including Ctrl-C

**File:** `scripts/reactive_flake_rate.jl:329-333`
**Issue:** The fix narrows the catch-all by exactly one type, `ArgumentError`. Every other exception still lands in `failures += 1` and is labelled a NUMERICAL_ERROR-class flake. That includes:
- `InterruptException`. Ctrl-C during a solve is swallowed, counted as a flake, and the loop continues with the next repeat. A user who interrupts once mid-run gets a findings file with an inflated rate, and the script cannot be stopped cleanly.
- Data-dependent `KeyError`, `BoundsError`, `DimensionMismatch` and `OutOfMemoryError` that hit some repeats but not all. The all-failed guard only catches errors that are 100% deterministic.

Numerical failures are already typed in the package: `SolveFailedError` (`src/core/status.jl:55`) and `CertificateError` (`src/admm/solve_admm.jl:364-365`). Note also that the new all-failed guard rejects a genuine 100% numerical-failure rate, which is a legitimate (if alarming) measurement. With a typed catch, that guard is no longer needed to distinguish "broken setup" from "always flakes".

**Fix:** Count only the numerical failure types and rethrow everything else:
```julia
catch e
    (e isa TSODSO.SolveFailedError || e isa TSODSO.CertificateError) || rethrow()
    failures += 1
    @warn ...
end
```
Then either keep the all-failed guard as an explicit "100% numerical failure" message, or report it as a measured rate. It should no longer be a proxy for configuration errors.

## Info

### IN-01: `check_script_api.jl` treats `TSODSO` as always bound, and module aliases override local bindings

**File:** `.github/scripts/check_script_api.jl:201-203`
**Issue:**
- `chain_root` returns `MOD` for `:TSODSO` unconditionally. After `using TSODSO: solve_admm` or `import TSODSO: solve_admm` alone, the name `TSODSO` is not bound. I verified the analogous case: `using LinearAlgebra: norm; LinearAlgebra.dot` throws `UndefVarError`. A later `TSODSO.max_jump(t)` therefore fails at runtime but passes the check (probe: 0 findings). No current script uses this form.
- `haskey(fs.modalias, s)` is checked before `s in fs.bound`. So `import TSODSO as T` plus `f(x::T) where {T} = T.a` gives a false `T.a is not defined` finding.

**Fix:**
- When `fs.touches` is true, return `MOD` only if `:TSODSO in fs.bound` or `:TSODSO in fs.imported`. Otherwise report "`TSODSO` is not bound (only `using TSODSO: ...`)".
- Check `fs.bound` before `fs.modalias`, or accept the false positive and document it.

### IN-02: Planning-ID guard still misses `NN-NN-PLAN` / `NN-NN-NN`, `plan06-02` and Unicode-dash forms

**File:** `.github/scripts/planning_id_rules.py:16, 21`
**Issue:** These probes all return no rule hit:
- `see 36-22-PLAN for`. The `artifact` rule requires `-PLAN.md`, and `bare_nn` rejects a trailing `-`.
- `in 36-22-01`
- `plan06-02`
- `plan 06–02` and `36–22` (en dash), and `36‑22` (non-breaking hyphen)

A `git grep` sweep found no such site in the current tree, so this is latent. Adding Unicode dashes needs care, because the tree has many zero-padded en-dash hour ranges (`# 00–05 overnight trough`), and the ascending-unpadded veto would not cover them.

**Fix:**
- Extend `bare_nn` to allow a trailing `-` when it is followed by `PLAN`, `SUMMARY` or `\d\d`.
- Make the `plan` separator `[\s\-‑–]*`.
- Add positives for `36-22-PLAN` and `36-22-01`.

### IN-03: The format job's planning-ID guard is skipped whenever formatting fails

**File:** `.github/workflows/CI.yml:100-102`
**Issue:** "Check for planning identifiers" has no `if:`. A format failure therefore skips the guard, and a planning ID introduced in the same push is only reported on the next run. This is the masking pattern that IN-02 fixed for the API check, and the step just above it already uses `if: always()`. This was not introduced in this iteration.
**Fix:** Add `if: ${{ !cancelled() }}` to the guard step.

### IN-04: Bindings in `check_script_api.jl` are file-global and flow-insensitive

**File:** `.github/scripts/check_script_api.jl:83-84, 498-503`
**Issue:** A binding anywhere in the file legitimises the name everywhere. Each of these probes reports 0 findings, but the code would fail at runtime:
- `function outer(); max_jump(x) = 1; end` then a top-level `max_jump(tr)`.
- A function argument named `max_jump` elsewhere, then `map(max_jump, trs)`.
- A struct field named `SOCP`, then `select_optimizer(SOCP)`.

This is a design limit rather than a regression, but the header reads as if these forms were covered.
**Fix:** State the limitation in the header ("binding analysis is file-global; a name bound anywhere suppresses checks everywhere"). Alternatively, scope `bound`/`fbound` per top-level statement and per function body.

---

_Reviewed: 2026-10-05T23:59:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
