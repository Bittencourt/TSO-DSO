# Phase 37: Test Infrastructure & Repo Hygiene - Research

**Researched:** 2026-10-05
**Domain:** Julia CI/test infrastructure (JET, TestItemRunner filtering, flake quarantine), repo hygiene
**Confidence:** HIGH for measured items (JET, TestItemRunner source, manifests, timings); MEDIUM for CI-environment behaviour not run here (GitHub Actions env passthrough, nightly cron)

## Summary

Everything below was measured on this machine on 2026-10-05 (Julia 1.12.5 and 1.12.7, 1.11.9, 1.10.11 via juliaup; 4 cores) unless tagged otherwise. No package installs are needed: JET, TestItemRunner and TestItems are already in `test/Project.toml` and `test/Manifest.toml`; JuliaFormatter is already installed ad hoc by the CI `format` job. Registry/legitimacy audit is therefore a no-op (see Package Legitimacy Audit).

Seven facts that change how the phase should be planned:

1. **JET works today and is cheap.** `JET.report_package(TSODSO; target_modules=(TSODSO,))` on Julia 1.12 gives **42 reports / 33 unique normalized signatures in about 61 s** (after a one-time ~204 s JET precompile on a cold depot). The 33 signatures are **identical on Julia 1.12.5 and 1.12.7**. About 22 are one root cause (JuMP's `objective_value` is typed `Union{Float64,Vector{Float64}}`), 8 are `Nothing`-narrowing false positives on struct fields, 3 are conditionally-defined locals. **No genuine undefined global / wrong-arity bug was found**; the "trivially-real" set is empty or tiny (see JET section).
2. **`@run_package_tests` roots at the REPO ROOT, not `test/`** (`joinpath(dirname(__source__.file), "..")`), walks every `.jl` under it (including `.planning/`, `docs/`, sibling worktrees inside the repo), and the filter receives only `(filename, name, tags)`. A filter on `startswith(ti.filename, test_dir)` is the correct restriction. `run_tests` returns `nothing`; per-item times are only printed with `verbose=true`.
3. **The macro's comma form does not work**: `@run_package_tests filter=f, verbose=true` parses as `filter = (f, verbose=true)`. Use space-separated args or a named filter function.
4. **Root `Manifest.toml` can be dropped.** Measured: `Pkg.Types.Context().env.manifest_file` is `Manifest-v1.10.toml` on Julia 1.10.11, `-v1.11.toml` on 1.11.9, `-v1.12.toml` on 1.12.7, with or without a root `Manifest.toml` present. Pkg docs say versioned manifests are a 1.11 feature, but 1.10.11 honours them. Earlier 1.10 patches are unverified.
5. **Julia patch-level numeric sensitivity is real and already bites.** The `welfare surplus accounting: +25% FIT ratio golden + non-failing thesis cross-check` item (`test/test_pricing_welfare.jl:301`) **passes on Julia 1.12.5 and ERRORS deterministically on 1.12.7** (3/3 runs): `fit_baseline` throws `SolveFailedError` with `ALMOST_OPTIMAL`/`ALMOST_SOLVED` at `src/pricing/fit.jl:515` (through `assert_solved!`). CI uses `version: '1.12'` which floats to the latest patch. This is a HYG-06 target and must be in the flake harness.
6. **`scripts/pv_boom_case_study.jl` and both `pv_boom_report*.jl` are broken at HEAD** and cannot be regenerated end to end: the case study's Part B (`run_nash!`) now fails the exactness gate on the boom fixture ("SOCP relaxation INEXACT ... prices REFUSED", all 3 calibration attempts); the existing local `data/pv_boom/results.jld2` is stale (stores `decomp` NamedTuples with `loss`/`voltage` keys, while the report reads `.cone`/`.drop`, so v1 and v2 both crash at line 86 with `FieldError`). The committed `results/pv_boom/summary.csv` is also stale relative to HEAD (welfare differs for pv_mult >= 1.0). "Regenerated HTML matches v2" therefore needs the remap-driver verification described below, and the case-study breakage must be recorded as a status, not fixed here (model behaviour is out of scope).
7. **`scripts/run_scenario.jl` is not a stale fixture**: the demo `Scenario(... seed = 42 ...)` hits the genuine, loud battery-complementarity gate (ADMM at bus 2, t=16; centralized at bus 5, t=16). Seeds 1 and 7 run fine with `:admm` (seed 7: 56 iters, welfare -4823.666048218671, exact_maxgap 5.5e-10). Fix = change the demo seed to 7 with a one-line comment; no archive needed.

**Primary recommendation:** Per-item `:slow` tags driven by one instrumented `verbose=true` full run on Julia 1.12 latest (which doubles as the 1.12.7 regression check against 32205/0/0/5); `runtests.jl` wraps `@run_package_tests filter=...` in an outer `@testset` to collect `Test.Broken` records for the allowed-list check; JET job in a stacked load path with a committed signature baseline; drop root `Manifest.toml`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### JET in CI (HYG-04)
- `JET.report_package(TSODSO; target_modules=(TSODSO,))` in its own CI job on Julia 1.12 (JET tracks
  the latest Julia minor).
- Ratchet baseline: committed file of normalized report signatures (kind + function + message, no
  line numbers); CI fails only on reports NOT in the baseline; fixed reports must be removed from it.
- Fix trivially-real findings (undefined names, wrong-arity calls, etc.) in-phase; baseline the rest
  with a short per-category justification. Any src/ fix must keep goldens + canary bit-identical.
- `scripts/jet_check.jl` runs the same check locally and regenerates the baseline with `--update`.

#### Fast/slow split (HYG-05)
- `:slow` = measured rule: `@testitem`s in files taking >= 30 s in a full run (about 10-14 heavy files:
  acceptance, ieee123_admm, experiments, admm, certification_*, strategies, planning_nash,
  admm_adaptive, thesis_repro, integer planners...; per-item timings from one instrumented run). The
  knife-edge canary stays FAST (every push).
- `test/runtests.jl` honours env `TSODSO_TEST_SET` = `fast` (exclude `:slow`) / `slow` (only `:slow`) /
  `all` or unset (everything - local `Pkg.test()` stays the full suite).
- CI: push/PR -> fast set on Julia 1.10/1.11/1.12; separate `slow` workflow -> full suite nightly (cron)
  + `workflow_dispatch`, on 1.10 and 1.12.
- Restrict `@run_package_tests` discovery to items whose file lies under `test/` (kills the
  stray-`.jl`-testitem hazard from `.planning/`/scratch files).

#### Flakes (HYG-06)
- Measure before deciding: new `scripts/flake_rate.jl` runs the IEEE-13 ADMM items and the
  stochastic-welfare items 20x each in fresh processes; per-item pass/fail + solver status recorded in
  `results/flake_rate/`.
- If a flake reproduces: retry-and-report quarantine - up to 3 tries, each retry logged via `@info`,
  passes only if a retry succeeds, summary reports retry use; all-fail = real failure. Deterministic
  failures -> `@test_broken` with reason.
- Archive `scripts/reactive_flake_rate.jl` (broken by design), superseded by the new harness, which
  measures against `ReactiveMode.LIVE`/current defaults and counts `ConvergenceError` as a labelled
  flake category (settles the Phase 36 deferred decision).
- Keep the documented conditional `broken=` sites and CairoMakie `@test_skip`s (reason in names); add
  a check that the broken/skip set equals an expected list so no new broken slips in silently.

#### Repo hygiene (HYG-08) + leftovers
- `scripts/README.md` index (purpose, how to run, outputs, status). `git mv` to `scripts/archive/`:
  `reactive_flake_rate.jl`, `run_scenario.jl` (first check whether its battery-complementarity failure
  is a stale fixture - fix if trivial, else archive with a note). Keep `benders_toy.jl` and
  `compare_default_stochastic.jl` (docs-referenced). `check_script_api.jl` skips `scripts/archive/`.
- pv_boom: extract shared helpers (figure data URI, sweep/nash tables, ...) into
  `scripts/lib/pv_boom_common.jl`; v2 becomes the single `pv_boom_report.jl` using it; archive v1;
  verify the regenerated HTML matches v2's structure.
- Root `Manifest.toml` (byte-identical to `Manifest-v1.12.toml`): drop it if every supported Julia
  (1.10/1.11/1.12) resolves via `Manifest-v1.x.toml` (research to verify 1.10 behaviour); otherwise
  keep and document why (.gitignore comment / README).
- Untrack `.planning/tmp/` (currently `docs-work-manifest.json`) and ignore the whole dir.
- Phase 36 leftovers: fix the `test/test_benchmark_ieee8500.jl` docstring so JuliaFormatter is clean
  (content-loss check OK); fix the 4 docs `@ref` warnings; wire `test_benchmark_ieee8500.jl` as a
  `:slow` testitem wrapper or document it as manual.

### Claude's Discretion
- Exact JET normalization format; per-item timing method; flake harness CLI; README layout; shared-lib
  API names.

### Deferred Ideas (OUT OF SCOPE)
- Large-lattice integer termination criterion - past v4.0 (ROADMAP).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HYG-04 | JET check runs in CI over the package, report mode, agreed baseline | JET measured (61 s, 33 unique sigs, stable across 1.12.5/1.12.7); normalization recipe; stacked-load-path job recipe; JET-per-Julia compat table |
| HYG-05 | `:slow` tag; fast job per push, slow suite separate/nightly | TestItemRunner source-verified filter API; env-var design; candidate slow list from `p05.log`; per-item timing via `verbose=true`; workflow skeleton |
| HYG-06 | Known flakes fixed or quarantined so green means green | Flake harness design with measured per-process cost; new deterministic 1.12.7 failure in `fit_baseline` item; retry helper design (retry the solve, not the assertion); allowed-broken check verified by experiment |
| HYG-08 | `scripts/` index, archive, pv_boom merge, root manifest, `.planning/tmp/` | Manifest experiment; pv_boom function map + breakage findings; run_scenario diagnosis; docs `@ref` fixes; ieee8500 test status |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Fast/slow selection | `test/runtests.jl` (filter + env var) | `.github/workflows/*.yml` (sets env) | Selection logic must work locally with `Pkg.test()`; CI only sets the env var |
| JET check | `scripts/jet_check.jl` + baseline file | CI job (runs the script) | Same script local and CI; baseline is data, not workflow logic |
| Flake measurement | `scripts/flake_rate.jl` (fresh processes) | `results/flake_rate/` | Measurement is out-of-suite; suite only carries the quarantine helper |
| Quarantine helper | `test/` `@testmodule` (shared) | test items | Test-side only; no `src/` change |
| Broken/skip allowed-list | `test/runtests.jl` outer testset + `test/` data file | - | Needs access to the testset tree, only possible around the runner call |
| Scripts index/archive | `scripts/README.md`, `scripts/archive/` | `check_script_api.jl` skip rule | Pure repo hygiene |
| Manifests | git-tracked files | CI `julia-buildpkg` proves resolution | Julia selects versioned manifest itself |

## Standard Stack

### Core (all already present; no installs)
| Library | Version (measured) | Purpose | Source |
|---------|--------------------|---------|--------|
| JET | 0.11.6 (pinned by `test/Manifest.toml`; registry latest 0.12.3) | `report_package` static analysis | `test/Manifest.toml`; General registry `Versions.toml` [VERIFIED: local registry] |
| TestItemRunner | 1.1.5 | `@run_package_tests`, filter, verbose timing | `test/Manifest.toml` + source read [VERIFIED: ~/.julia/packages/TestItemRunner/GnoVt] |
| TestItems | 1.0.0 | `@testitem`/`@testmodule` | `test/Manifest.toml` |
| Test (stdlib) | - | `Test.Broken`, `DefaultTestSet` tree walk | experiment below |
| JuliaFormatter | 2.10.x (CI-installed, `version = "2.10"`) | formatter + content-loss check | `.github/workflows/CI.yml` |

### JET version per Julia minor (from General registry Compat.toml)
| Julia | JET versions resolvable |
|-------|------------------------|
| 1.10 | 0.8.22 - 0.9.18 |
| 1.11 | 0.9.19 - 0.9.x |
| 1.12 | 0.10.x, 0.11.x, 0.12.x (0.10-0.10.14 / 0.11-0.11.3 require exactly 1.12) |
[VERIFIED: ~/.julia/registries/General/J/JET/Compat.toml]

Consequence: `test/Project.toml` has no JET compat entry and must not get a `= 0.11.6` pin (it would make the test env unresolvable on 1.10/1.11). The JET job runs only on 1.12 and takes its pin from `test/Manifest.toml` (1.12.5-resolved). The baseline file header should record `JET <ver> / Julia <ver>` and `jet_check.jl` should print a warning (not fail) on mismatch.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-item `:slow` tags | per-file filter by basename list | Files like `test_toy_dc.jl` (Aqua item + a fast toy item), `test_strategies.jl` (26 items, 82 s total) mix cheap and expensive items; CONTEXT and HYG-05 require an actual `:slow` tag, so per-item tagging after one measured run |
| Dedicated JET env with its own Manifest | stacked `JULIA_LOAD_PATH="@:test:@stdlib"` with `--project=.` | Stacked path is the already-established repo recipe and was verified for JET below; no new manifest to maintain |

**Installation:** none. For the JET job: `julia --project=. -e 'using Pkg; Pkg.instantiate()'` and `julia --project=test -e 'using Pkg; Pkg.instantiate()'`, then run with `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`.

## Package Legitimacy Audit

No new external packages are introduced by this phase. JET 0.11.6, TestItemRunner 1.1.5, TestItems 1.0.0, DrWatson, CairoMakie, JuliaFormatter 2.10 are already pinned in committed manifests / the existing CI workflow. slopcheck not run (nothing to install).

| Package | Registry | Age | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-------------|-----------|-------------|
| (none new) | - | - | - | n/a | n/a |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
push / PR ──> CI.yml
   ├─ test (1.10, 1.11, 1.12)  env TSODSO_TEST_SET=fast ──> julia-runtest ──> Pkg.test ──> test/runtests.jl
   ├─ jet (1.12) ──> instantiate root + test envs ──> scripts/jet_check.jl ──> diff vs test/jet_baseline.txt
   ├─ format ──> JuliaFormatter 2.10 + content-loss + planning-id guard
   └─ docs ──> Documenter build (must emit 0 "Cannot resolve @ref")

cron nightly / workflow_dispatch ──> slow.yml
   └─ test (1.10, 1.12) env TSODSO_TEST_SET=slow (or all) ──> same runtests.jl

test/runtests.jl
   read TSODSO_TEST_SET ──> predicate over (filename, name, tags)
        restrict: startswith(ti.filename, test dir)
        fast: !(:slow in tags) | slow: :slow in tags | all: true
   @testset "outer" ──> @run_package_tests filter=pred [verbose]
        └─ after run: walk outer testset tree, collect Test.Broken
              observed ⊆ allowed (test/expected_broken data)  ──> @test

scripts/flake_rate.jl (manual / out of CI)
   parent ──> N x fresh `julia` child ──> child runs named testitems via TestItemRunner.run_tests(test/; filter by name)
   child writes JSON line (item, outcome, status strings, Julia VERSION) ──> results/flake_rate/
```

### Recommended Project Structure
```
test/
├── runtests.jl              # TSODSO_TEST_SET selection + broken-allowed-list check
├── expected_broken.txt      # allowed Broken/skip records (item name + expr), commented with reasons
├── fixtures_retry.jl        # @testmodule: with_solve_retry helper + atexit summary
└── jet_baseline.txt         # (or scripts/jet_baseline.txt) normalized signatures + category comments
scripts/
├── README.md                # index: purpose / how to run / outputs / status
├── jet_check.jl             # --update, --selftest
├── flake_rate.jl            # fresh-process harness
├── lib/pv_boom_common.jl
├── pv_boom_report.jl        # former v2
└── archive/                 # reactive_flake_rate.jl, pv_boom_report (v1, renamed e.g. pv_boom_report_v1.jl)
.github/workflows/{CI.yml, slow.yml}
```

### Pattern 1: TestItemRunner filter (verified from source)
**What:** the filter receives `(filename = <abs normpath>, name = <String>, tags = <Vector{Symbol}>)`.
**When:** always, in `runtests.jl`.
```julia
# Source: ~/.julia/packages/TestItemRunner/GnoVt/src/TestItemRunner.jl (v1.1.5), lines 134-190 and macro at the end
using TestItemRunner, Test
const TEST_DIR = @__DIR__
const SET = get(ENV, "TSODSO_TEST_SET", "all")
SET in ("all", "fast", "slow") ||
    error("TSODSO_TEST_SET must be fast|slow|all, got $(repr(SET))")
tso_filter(ti) =
    startswith(ti.filename, TEST_DIR) &&
    (SET == "all" || (SET == "slow") == (:slow in ti.tags))
# Space-separated macro args (comma form mis-parses). verbose=true only for timing runs:
@run_package_tests filter = tso_filter verbose = (get(ENV, "TSODSO_TEST_VERBOSE", "") == "1")
```
Notes: `verbose=` must be a literal assignment expression accepted by the macro (`i.args[1] in (:filter, :verbose)`); the RHS may be any expression. `ti.filename` is the `normpath`ed absolute path, so `startswith` against `@__DIR__` is exact; discovery still parses every `.jl` under the repo root (a syntactically broken stray `@testitem` anywhere aborts the run, filter or not).
**Default usings:** `package_name` comes from `<root>/Project.toml`; with root = repo root items get `using TSODSO` automatically. `scripts/run_tests_filtered.jl` calls `run_tests(joinpath(root,"test"))` instead, where `test/Project.toml` has no `name`, so default `using TSODSO` is NOT injected there (items evidently import it explicitly; keep in mind if the runner or harness is reused).

### Pattern 2: collect Broken/skip records (verified by experiment)
`run_tests` returns `nothing`, but running it inside an outer `@testset` leaves the inner "Package" testset in `outer.results`.
```julia
function broken_records(ts, path = String[], out = NamedTuple[])
    for r in ts.results
        if r isa Test.DefaultTestSet
            broken_records(r, vcat(path, r.description), out)
        elseif r isa Test.Broken
            push!(out, (; where = join(path, " / "), kind = r.test_type, expr = string(r.orig_expr)))
        end
    end
    return out
end
@testset "TSODSO" begin
    @run_package_tests filter = tso_filter
    observed = broken_records(Test.get_testset())
    unexpected = [o for o in observed if !(allowed(o))]   # compare item name + kind (+ expr)
    @test isempty(unexpected)
end
```
Experiment output (Julia 1.12.7): `("Package / test_ieee13.jl / ieee13 ground: pinned computed golden regression + thesis v₉[16] cross-check", :test, "gap < 0.01")` and `("Package / test_diagnostics_plot.jl / diagnostics plot: ext returns a Makie Figure ... (plot, makie)", :skipped, "Base.find_package(\"CairoMakie\") !== nothing")`.
**Use "observed ⊆ allowed", not equality**: conditional `broken=` sites only record Broken when the condition fires, and fast/slow subsets see different items. Expected current records (5): `test_acceptance.jl:114`, `test_ieee13.jl:244`, `test_pricing_welfare.jl:366` (all `broken = (gap >= ...)`), and `@test_skip` at `test_planning_nash.jl:589`, `test_diagnostics_plot.jl:107`. `test_thesis_repro.jl:256` (`broken = !sign_flip_holds`) is currently passing (sign flip holds 5/5) and must be in the allowed list as conditional. Note the outer-testset wrapper changes the summary header (one extra nesting level) — `check_suite_log.py` totals parsing must be re-verified against the new log shape.

### Pattern 3: JET signature normalization (prototype run, 1.12.5 and 1.12.7 identical)
```julia
using JET
rep = JET.report_package(TSODSO; target_modules = (TSODSO,))
function sig(r)
    kind = string(nameof(typeof(r)))                         # MethodErrorReport / UndefVarErrorReport / ...
    mi = r.vst[end].linfo                                     # innermost frame = where the error is
    fn = string(mi.def.module, ".", mi.def.name)
    fn = replace(fn, r"^(TSODSO\.)#(.*)#\d+$" => s"\1\2")     # kwarg-body gensyms  "#f#779" -> "f"
    file = basename(string(r.vst[end].file))                  # file basename, NO line number
    m = let io = IOBuffer(); JET.print_report_message(io, r); replace(String(take!(io)), r"\s+" => " ") end
    head = first(split(m, r"\): |:\s+(?=[A-Za-z@_#])"; limit = 2))   # keep the message head, drop the printed expression tail
    return "$kind | $fn | $file | $(strip(head))"
end
sigs = sort!(unique(sig.(JET.get_reports(rep))))
```
Why this survives line shifts: no line numbers; `#name#NNN` gensym counters stripped; the printed expression tail (which carries `::T` annotations that differ between duplicate reports) dropped; duplicates collapse (42 reports -> 33 signatures). It is NOT immune to renaming a function or moving it to another file (that correctly looks like "new + fixed"). `JET.print_report_message` and `r.vst[i].{file,line,linfo}`/`.sig`/`.union_split` are JET-internal-ish API in 0.11.6; pin JET via the manifest and add `--selftest` coverage in `jet_check.jl` (feed a fabricated signature set to the diff logic).

### Anti-Patterns to Avoid
- **`@run_package_tests` via `julia -e`**: root resolves via cwd (memory: sibling worktrees, e.g. `~/programming/TSO-DSO.worktrees/*`, contaminate). Always a real file.
- **Retrying an `@test`**: failures inside an attempt are recorded in the enclosing testset immediately and cannot be withdrawn. Retry the *solve* (see Pattern 4).
- **Scratch `.jl` with `@testitem` anywhere under the repo** (memory `testitemrunner-scans-scratch-jl`). All scratch drivers used in this research live in the session scratchpad outside the repo.

### Pattern 4: retry-and-report helper (design)
Shared `@testmodule` (e.g. `FlakeRetry`) exposing
```julia
with_solve_retry(f; tries = 3, label, retry_on = (SolveFailedError, ConvergenceError)) -> value of f()
```
- Calls `f()`; on a listed typed error logs `@info "flake retry" label attempt error status` and retries; after `tries` failures rethrows the last error (all-fail = real failure).
- `f` must only compute the numbers (build + solve); the item makes its `@test`s on the returned value afterwards, so a retried attempt never leaves failed assertions behind.
- Records `(label, attempts_used)` in a module-level `Vector`; `atexit` hook prints a `RETRY SUMMARY` (and `@warn`s if any retry was used). Item ordering is not controllable, so a "last item prints the summary" design is unreliable; `atexit` is.
- A `@testmodule` is evaluated once per process (`ensure_evaled`), so state is shared across items in one run.
- Reuse `TSODSO.RETRYABLE_STATUSES` (`src/planning/retry.jl`: `NUMERICAL_ERROR`, `SLOW_PROGRESS`, `ALMOST_OPTIMAL`) to decide whether a `SolveFailedError` is retryable; do not retry infeasibility.
- Test the helper itself with a deterministic fake `f` (fails twice then returns; fails 3x) asserting on returned counts/exceptions via `@test_throws`, not by nesting failing `@test`s.
- Deterministic failures (e.g. the 1.12.7 `fit_baseline` ALMOST_OPTIMAL) are NOT flakes: use `@test_broken` with a reason that names the Julia patch, or catch `SolveFailedError` around the solve and record a `@test_broken`, then add the item name to the allowed-Broken list.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-item timing | custom timer macros in every item | `verbose=true` on the runner | TestItemRunner's `DefaultTestSet` prints `Time` per item (verified: 63.9 s first item vs 0.9 s next) |
| Fast/slow selection | tag-parsing scripts | the runner `filter` kwarg | tags are `ti.tags` (`Vector{Symbol}`) |
| Julia version-specific manifest handling | custom resolve logic | Pkg's built-in `Manifest-v1.x.toml` lookup | verified on 1.10.11/1.11.9/1.12.7 |
| JET baseline diffing | text diff of raw JET output | normalized signature set + set difference | raw output has gensym counters, line numbers, long type dumps |
| Fresh-process orchestration | `Distributed` workers | `run(`julia ...`)` children | `Distributed` shares nothing but also hides per-process compile/JIT state; CONTEXT locks fresh processes |

## Runtime State Inventory

(Manifest drop and archiving are the only rename/migration-like parts.)

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `.planning/tmp/docs-work-manifest.json` tracked (the only tracked file under `.planning/tmp/`); `.gitignore` currently ignores only `/.planning/tmp/36/` | `git rm --cached` the file, change ignore to `/.planning/tmp/` (keeps working copy). Data deletion not needed |
| Live service config | None - verified: no external services reference script names; docs reference only `benders_toy.jl`, `compare_default_stochastic.jl` (kept) | none |
| OS-registered state | None - no scheduled tasks; the new nightly cron lives in the workflow file | none |
| Secrets/env vars | New env `TSODSO_TEST_SET` (and optional `TSODSO_TEST_VERBOSE`); no secrets | document in README/CI |
| Build artifacts | `.github/scripts/suite_detached.sh` hardcodes `.planning/tmp/36/` (still fine once the whole dir is ignored); `results/pv_boom/report*.html` are gitignored artifacts | consider parametrising the label dir; no migration |

Other references to moved files: comments in `scripts/repro_stability_check.jl` (lines 5, 12, 19, 284, 552) and `results/repro_stability_check/findings.txt` mention `scripts/reactive_flake_rate.jl`; update the comment paths to `scripts/archive/` (the committed findings file is a historical artifact; leave it or note). `.github/scripts/check_script_api.jl:collect_files` walks `scripts` with `walkdir` and must skip any path component `archive`; add a selftest case. The planning-ID guard scopes `scripts`, `.md`, `.yml`, `.sh`, `.py`: new README/workflow/script files must not contain phase/plan/requirement IDs, `RESEARCH`, `CONTEXT.md`, or `.planning/` strings.

## Common Pitfalls

### Pitfall 1: Comma-separated macro args
**What goes wrong:** `@run_package_tests filter=f, verbose=true` becomes `filter = (f, verbose = true)`. **How to avoid:** space-separated args (verified with `Meta.parse`).

### Pitfall 2: Slow tagging polluted by first-process compile cost
**What goes wrong:** the first solver-using item in a process pays JuMP/Clarabel/HiGHS/BilevelJuMP compile. Measured: `stochastic_welfare` file = 76 s in a fresh process (63.9 s in the first item) vs 4.0 s when compile was already paid; in the full run it measured 2.3 s. Several `p05.log` "slow" files are partly compile (see candidate list). **How to avoid:** per-item timing from the instrumented run; treat borderline items (30-50 s) with the compile note; a ">= 30 s" cut inside the full suite is a CI-budget decision, so compile is paid by whichever fast item runs first anyway.

### Pitfall 3: Julia patch-level numerics (new, measured)
`+25% FIT ratio golden` passes on 1.12.5, errors on 1.12.7 (3/3). CI `'1.12'` floats. Run the instrumented full run on `julia +1.12` (1.12.7) and compare against the 1.12.5 baseline 32205/0/0/5 before trusting the new tags/allowed list. The same item's comment says "non-failing cross-check", so catching `SolveFailedError` -> `@test_broken` is consistent with its design. Do not pin CI to 1.12.5 to hide it.

### Pitfall 4: `check_suite_log.py` vs the outer testset
Wrapping the runner in an outer `@testset` shifts nesting and header text; re-run `check_suite_log.py` against a short log from the new `runtests.jl` before relying on it (not verified here).

### Pitfall 5: Local `Project.toml` drift / Aqua
Memory `local-project-toml-drift`: Aqua failures from uncommitted CairoMakie `[deps]` drift. `git status` was clean at research time. Aqua lives in `test/test_toy_dc.jl` (2 items; the Aqua item is "quality: Aqua package checks ..."). Decide its tag from the per-item measurement; it needs the real committed `Project.toml`, so it must not be skipped from the fast job without a deliberate decision.

### Pitfall 6: Dropping the root manifest
Verified only for Julia 1.10.11 (and 1.11.9, 1.12.7). Pkg docs describe versioned manifests as 1.11+; `[compat] julia = "1.10"` admits 1.10.0-1.10.7 where a versioned manifest may be ignored (they would resolve fresh). CI `setup-julia version: '1.10'` picks the latest 1.10.x so CI is covered. Also, after the drop, a future Julia 1.13 resolves fresh (no `Manifest-v1.13.toml`); that is the honest behaviour but should be stated in the README. `.gitignore` header comment ("Manifest.toml is intentionally COMMITTED ... Do NOT add Manifest.toml here") must be rewritten to describe the versioned scheme. `test/`, `docs/`, `bench/` keep their single unversioned manifests.

### Pitfall 7: Docs job manifest coupling
`docs/Manifest.toml` is 1.12-only (comment in CI.yml). Untouched by this phase; the JET job also pins 1.12.

### Pitfall 8: Retry helper summary lost
Without `atexit`, retries inside one item are invisible. Also, `@info` inside `Pkg.test` is captured in the CI log only; keep the `RETRY SUMMARY` line grep-able.

## Code Examples

### `jet_check.jl` diff semantics
```julia
# baseline file: one signature per line; '#' comment lines carry the per-category justification
baseline = Set(strip.(filter(l -> !isempty(strip(l)) && !startswith(l, "#"), readlines(path))))
new   = setdiff(current, baseline)    # CI fails on these
fixed = setdiff(baseline, current)    # CI fails too ("remove fixed reports from the baseline") per the ratchet decision
--update : rewrite baseline from `current`, preserving category comments via a header block keyed by kind
```

### CI jobs (skeleton)
```yaml
# CI.yml additions
  jet:
    name: JET (Julia 1.12)
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with: { version: '1.12' }
      - uses: julia-actions/cache@v2
      - run: julia --project=. --startup-file=no -e 'using Pkg; Pkg.instantiate()'
      - run: julia --project=test --startup-file=no -e 'using Pkg; Pkg.instantiate()'
      - run: julia --project=. --startup-file=no -t2 scripts/jet_check.jl
        env: { JULIA_LOAD_PATH: "@:test:@stdlib" }
```
```yaml
# test job: add to the julia-runtest step
      - uses: julia-actions/julia-runtest@v1
        env: { TSODSO_TEST_SET: fast }
# slow.yml: on: { schedule: [{cron: '17 3 * * *'}], workflow_dispatch: {} }
#           matrix version [1.10, 1.12], env TSODSO_TEST_SET: slow (or all), timeout-minutes: 120
```
Env passthrough: step-level `env:` is inherited by `Pkg.test`'s child Julia (the SciML-style `GROUP` env-var pattern); [ASSUMED] not run on GitHub here. Scheduled workflows only run from the default branch. The last full-suite CI (2026-10-04, run 37223710620) took 15 min (1.10), 20 min (1.11), 21 min (1.12), well under the current 60-min cap. `jet` job timing estimate: cold JET precompile about 204 s + report 61 s (measured locally, uncached).

## Item 2/3: Candidate `:slow` files from `.planning/tmp/36/p05.log` (97 files, total 1678 s, Julia 1.12.5)

Files >= 30 s (13 files, 1320 s = 79% of total):

| s | file | #testitems | note |
|---|------|-----------|------|
| 237.0 | test_acceptance.jl | 2 | |
| 202.5 | test_ieee123_admm.jl | 3 | contains the 21 s IEEE-13 4Q-BESS item (measured) |
| 171.2 | test_experiments.jl | 17 | per-item split likely worthwhile |
| 138.1 | test_admm.jl | 5 | IEEE-13 crossval item alone = 104 s in a fresh process (about 60 s compile) |
| 85.3 | test_planning_certification_bilevel_interior.jl | 3 | BilevelJuMP compile suspect |
| 82.3 | test_strategies.jl | 26 | per-item split needed |
| 80.6 | test_planning_nash.jl | 21 | per-item split needed |
| 79.3 | test_admm_adaptive.jl | 3 | |
| 66.2 | test_toy_dc.jl | 2 | mostly first-solve compile + Aqua; the toy DC item is trivial |
| 48.4 | test_planning_certification_integer.jl | 4 | |
| 44.1 | test_planning_nash_integer.jl | 4 | |
| 43.1 | test_planning_master_integer.jl | 14 | HiGHS MILP compile suspect |
| 42.1 | test_thesis_repro.jl | 2 | |

Just under the cut (stay fast unless per-item data says otherwise): admm_knifeedge_canary 25.2 s (**must stay fast**), admm_generic_pf 25.0, planning_alpha_bounds_stackelberg 23.3, planning_inexact_policy 22.6, welfare_solve 20.6. Expected fast-set wall time about 358 s of test time plus compile (about 8-10 min per CI job) vs about 28 min full locally.

**Per-item timing, cheapest way:** `TSODSO_TEST_VERBOSE=1` makes `runtests.jl` pass `verbose=true`; one detached full run (`.github/scripts/suite_detached.sh LABEL julia +1.12 --project=. -e 'import Pkg; Pkg.test()'` with the env var set) prints every item's `Time`. Per-file is enough for files with <= 5 items; the instrumented run is only mandatory to split `experiments`, `strategies`, `planning_nash`, `planning_master_integer`, `admm_generic_pf`, and `toy_dc`. Tag edits: items use `tags = [...]` on a continuation line (`@testitem "..." tags =\n    [:planning] setup = [...] begin`); `test_strategies.jl` items carry no `tags` at all, so those need `tags = [:slow]` added. `fast + slow == all` must be asserted by a discovery-only count (extend the preflight idea in `scripts/run_tests_filtered.jl`); currently 605 testitems / 113 files.

## Item 5: Flake harness (`scripts/flake_rate.jl`)

**Measured costs (fresh process, Julia 1.12.7, `-t2`):**
- `stochastic_welfare:` items only: 81 s wall (63.9 s of it the first item's compile).
- IEEE-13 ADMM crossval (`admm: cross-validation ieee13 ...`) + `ieee13 admm 4q-bess ...` + all stochastic_welfare items in ONE process: 144 s wall (crossval 104 s, 4q-bess 21 s, stochastic 4 s warm).
- A 4-core, 15 GB machine: serial 20 repeats of the combined set about 48 min; with `--jobs 2` about 25 min. Never run concurrently with the full suite; check `pgrep -af julia` first.
- All three target groups passed on their single run on 1.12.7. Prior history (Phase 16 `results/reactive_flake_rate/flake_rate_findings.txt`, 2026-07, solved in-process with `solve_admm`): IEEE-13 `NUMERICAL_ERROR` rate 11/20 (OFF) and 3/20 (CERTIFIED), IEEE-123 1/20 - measured on much older code and with the `reactive_consensus::Bool` API that no longer exists. In-process repeats did vary there, so keep an optional `--inprocess N` mode in addition to fresh-process mode (the locked default); fresh-process cost is dominated by compile, so fresh process x 20 is the expensive but decision-grade path.

**Design:**
- Parent `flake_rate.jl --repeats 20 --jobs 1 --targets ieee13_admm,stochastic_welfare,fit_baseline` spawns `run(pipeline(`julia --project=. -t2 scripts/flake_rate.jl --child <target>`; ...))` with `JULIA_LOAD_PATH="@:test:@stdlib"` (children need TestItemRunner from the test env).
- Child: `TestItemRunner.run_tests(joinpath(root,"test"); filter = ti -> ti.name in NAMES)` per item inside `try/catch Test.TestSetException`, using `Test.TestSetException`'s `.pass/.fail/.error/.broken` counts; additionally scan the captured log text for `NUMERICAL_ERROR|ALMOST_|SLOW_PROGRESS|ConvergenceError|SolveFailedError` and label them. Print one JSON-ish line: item, outcome, label list, `VERSION`, wall seconds.
- Record `VERSION` (patch-level sensitivity!) and run the harness on both 1.12.5 and 1.12.7 for the `fit_baseline` item.
- Target names (verified present): `test_admm.jl` "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)"; `test_ieee123_admm.jl` "ieee13 admm 4q-bess: live reactive dual-ascent supporting evidence, NOT CI-gating (ieee13, 4q)"; the seven `stochastic_welfare:` items in `test_stochastic_welfare.jl` (the historical "no-trip" flake there was root-caused as a soft-scope bug and is fixed, per the comments at lines 117-200); and `test_pricing_welfare.jl` "+25% FIT ratio golden ...".
- Outputs: `results/flake_rate/<timestamp>.csv` plus a `findings.txt` summary (same shape as the existing findings files).
- Archive `scripts/reactive_flake_rate.jl` to `scripts/archive/`; its `reactive_consensus = true/false` Bool calls no longer match `ReactiveMode`.

**Decision rule after measurement:** 0/20 and 0/20 with all-pass -> record "no reproducible flake", keep the retry helper available and covered by its unit test, quarantine nothing (do not add speculative retries). Reproduces non-deterministically -> `with_solve_retry`. Deterministic (as `fit_baseline` on 1.12.7) -> `@test_broken` with a reason + allowed-list entry.

## Item 4: Versioned manifests (measured)

Scratch copy (`Project.toml` + `Manifest-v1.1{0,1,2}.toml`, tiny `src/`) in the session scratchpad; `Pkg.Types.Context().env.manifest_file`:

| Julia | with only versioned manifests | plus a root `Manifest.toml` |
|-------|------------------------------|------------------------------|
| 1.10.11 | `Manifest-v1.10.toml` | `Manifest-v1.10.toml` |
| 1.11.9 | `Manifest-v1.11.toml` | `Manifest-v1.11.toml` |
| 1.12.7 | `Manifest-v1.12.toml` | `Manifest-v1.12.toml` |

Also the Phase 36 full-suite log shows the root-level warning "Entry in manifest ... differs from that in Manifest-v1.12.toml", i.e. the root `Manifest.toml` is already shadowed on 1.12. **Recommendation: drop it** (`git rm Manifest.toml`), keep `Manifest-v1.10/1.11/1.12.toml`, rewrite the `.gitignore` comment and the README statement; CI's `julia-buildpkg` step on 1.10/1.11/1.12 is the proof of clean-checkout resolution. Pkg docs (pkgdocs.julialang.org/v1/toml-files) describe the feature as 1.11+; 1.10 support above is empirical on 1.10.11 only.

## Item 6: pv_boom merge

**Function/section map** (v1 `pv_boom_report.jl`, 795 lines; v2 `pv_boom_report_v2.jl`, 1014 lines; `diff` = 315 changed lines, almost all in v2's added sections):
- Identical mechanics (v2 lines 14-222): `wload(datadir("pv_boom","results.jld2"))` and the four keys (`sweep`, `admm_crosscheck`, `nash_result`, `ac_stress`); `ok_rows`; the stressed-bus selection; Figure 1 (price curves), Figure 2 (4-way DLMP decomposition), Figure 3 (`TSODSO.plot_convergence`); `figure_to_data_uri`; `welfare_deltas_html`, `exact_maxgaps_html`; `sweep_table_html`, `nash_table_html`. v2 differs only by `provenance` spans on two lists and `report_v2` in error text/usage.
- v2-only (stays in the single report): notation table, SVG architecture diagram, sections 1-5 text with source citations, limitations, CSS, live git stamp, assembly; output name `report_v2.html` -> `report.html`.
- **API for `scripts/lib/pv_boom_common.jl`** (names are discretionary):
```julia
pv_boom_load_results(path = datadir("pv_boom", "results.jld2")) -> (; sweep, admm_crosscheck, nash_result, ac_stress, ok_rows)
pv_boom_stressed_bus(ok_rows) -> Int
pv_boom_figures(results, stressed_bus) -> (fig1, fig2, fig3)
figure_to_data_uri(fig) -> String
sweep_table_html(rows); nash_table_html(nash_result)
welfare_deltas_html(sweep; provenance = true); exact_maxgaps_html(sweep; provenance = true)
```
Loaded with `include(joinpath(@__DIR__, "lib", "pv_boom_common.jl"))` (it must carry its own `using CairoMakie, Base64, Printf`). `check_script_api.jl` walks `scripts/` recursively, so the lib file is covered automatically.

**Findings that constrain verification (measured):**
- `data/pv_boom/results.jld2` exists locally (gitignored, Aug 6) but is stale: `decomp` NamedTuples have `energy, loss, congestion, voltage, reactive, total`; the script reads `.cone` and `.drop` (renamed in Phase 36) -> `FieldError` at v2 line 86. v1 has the same lines. (The WR-03 commit message claims "nothing in scripts/results reads stored NamedTuples" - incorrect for this stored file.)
- Re-running `scripts/pv_boom_case_study.jl` at HEAD in a scratch worktree (2 min 26 s; `data/` written, tracked `results/pv_boom/summary.csv` modified, so ALWAYS do this in a scratch worktree outside the repo) fails in Part B: all 3 calibration attempts end in "SOCP relaxation INEXACT: worst gap/(...)=4679 > 1 ... prices REFUSED"; `results.jld2` then lacks `nash_result` and the report scripts die with `KeyError: "nash_result"`. Part A (sweep, ADMM cross-check) runs; its welfare values differ from the committed `summary.csv` for pv_mult >= 1.0 (e.g. pv_mult 1.0: -4823.30851835154 committed vs -4823.645333291668 now).
- So the pipeline cannot be regenerated end to end at HEAD. **Verification recipe that works without that:** a scratch driver (outside the repo) that `wload`s the stale `results.jld2`, rewrites every `decomp` NamedTuple key `loss -> cone`, `voltage -> drop`, then runs the merged report via a function entry (`main(results; outdir)`), writes to a scratch dir, and compares to the pre-merge `results/pv_boom/report_v2.html` (saved before refactor) after replacing `data:image/png;base64,[A-Za-z0-9+/=]+` with a placeholder and the git-commit stamp with a fixed token. Equality of that normalized text is a stronger check than a heading skeleton; if not byte-equal, fall back to comparing `<h1..h3>` text, `id="..."` anchors, and counts of `<img`, `<table`, `<section`. For this the report script should be structured as functions + a thin `if abspath(PROGRAM_FILE) == @__FILE__` main.
- Report runtime: v2 takes about 40-51 s warm in the docs env (CairoMakie load/compile); first run after a Julia patch change precompiles Makie for >10 min (observed on 1.12.7). Run with `JULIA_LOAD_PATH="docs:.:@stdlib"` (memory: scripts using CairoMakie need the docs env).
- Both v1/v2 outputs and the saved baseline: `results/pv_boom/*.html` are gitignored.
- **Status to record in `scripts/README.md`:** `pv_boom_case_study.jl` = "Part B currently fails the exactness gate (boom fixture); needs a modelling decision"; the report = "needs a results file from a successful case study". Do not alter solver behaviour in this phase.

## Item 7: `run_scenario.jl`

`Scenario(name="demo", feeder=:ieee13, strategy=:admm, seed=42, T=24)` -> `Battery complementarity violated at bus 2, t=16: p_ch·p_dch = 1.03e-8 >= tau*Pmax^2 = 6.25e-9` (loud gate, thrown from `solve_admm` line 365 via `run_and_store`). `:centralized`, seed 42 also fails (bus 5, t=16: 5.8e-8). ADMM seeds 1 and 7 succeed (seed 7: welfare -4823.666048218671, 56 iters, exact_maxgap 5.5e-10; seed 1: 106 iters). Cause: seed-specific population hitting a correct fail-loud gate, not stale data. **Fix:** `seed = 7` plus a comment that some seeds trip the battery-complementarity gate by design. Keep the script (then CONTEXT's archive list shrinks to `reactive_flake_rate.jl` and pv_boom v1). The script also writes under `data/sims` (gitignored); run once to confirm. Whether the default seed 42 population tripping the gate is a model-quality concern is an Open Question.

## Item 8: docs `@ref` warnings and `test_benchmark_ieee8500.jl`

Four warnings from the docs build (`.planning/tmp/36/p22docs.log`), all in `docs/src/api.md`, all caused by `[`name`](@ref)` links in docstrings pointing at things Documenter cannot bind (an undocumented non-exported constant, a struct field, an undocumented helper):
1. `src/pricing/fit.jl:337` `[`FIT_SITE3_ALMOST_GAP_TOL`](@ref)` (const at line 68 has no docstring)
2. `src/planning/master.jl:512` `[`BendersMaster.lb_clamped`](@ref)` (a field, not a binding)
3. `src/planning/master_integer.jl:192` `[`BendersMasterInteger.lb_clamped`](@ref)` (same)
4. `src/planning/master_integer.jl:813` `[`stall_z_atol`](@ref)` (function at line 790 has no docstring)
**Fix:** replace each with a plain code span `` `NAME` `` (docstring text only; zero behaviour change). Re-run the docs build and confirm no `Cannot resolve @ref`. (Adding docstrings + `@docs` entries is the heavier alternative; not recommended.)

`test/test_benchmark_ieee8500.jl` (228 lines): a plain `Test.jl` script (not a `@testitem`), never run by `Pkg.test()`; it runs `julia --project=<root> scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick` twice as subprocesses and pins `model_vars == 137258`, `model_cons == 274570`, `admm_iters == 1`. The formatter issue is the `run_quick()` docstring (lines 55-64): one very long paragraph line ending "`--quick` always produces. `main(ARGS)` overwrites/replaces ..." that JuliaFormatter's docstring reflow rewrites (+4 chars, so `check_content_loss.py` flags it). **Fix:** hand-reflow that docstring into short paragraphs (one sentence per line, no code span spanning a join point), then run the pinned formatter (`Pkg.add(PackageSpec(name="JuliaFormatter", version="2.10"))` in a throwaway env) and `python3 .github/scripts/check_content_loss.py HEAD`; iterate until the formatter output is a no-op. I did not execute the formatter (not installed locally). **Wiring:** a `@testitem ... tags = [:slow]` wrapper that does `run(`$(Base.julia_cmd()) --project=$root test/test_benchmark_ieee8500.jl`)` under `withenv("JULIA_LOAD_PATH" => nothing, "JULIA_PROJECT" => nothing)` (the root project already has `CSV` and `DataFrames`; under `Pkg.test` the inherited sandbox `JULIA_LOAD_PATH` would otherwise leak into the child). Runtime of the two `--quick` subprocesses was not measured; if above about 10 min or memory-heavy (137k vars), document as manual instead. [ASSUMED: wrapper viability under `Pkg.test`; verify with one run.]

## State of the Art

| Old approach | Current approach | Impact |
|--------------|------------------|--------|
| `Manifest.toml` + versioned copies | versioned manifests only (Pkg picks by Julia minor) | root file is dead weight (identical bytes to `-v1.12`) |
| JET ad hoc | `report_package` + signature baseline ratchet | CI stays green while new inference regressions fail |

**Deprecated:** `scripts/reactive_flake_rate.jl` (Bool `reactive_consensus` API, pre-`ReactiveMode`).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Step-level `env:` on `julia-actions/julia-runtest@v1` reaches the `Pkg.test` child | CI skeleton | fast/slow selection silently runs everything (caught: fast job duration check) |
| A2 | Julia 1.10.0-1.10.7 may ignore `Manifest-v1.10.toml` (docs say 1.11+; verified only on 1.10.11) | Manifest drop | only matters for local users on very old 1.10 patches |
| A3 | `:slow` per-item split of `experiments/strategies/planning_nash/master_integer` will leave a useful fast subset | Slow list | if few items are cheap, per-file tagging is enough |
| A4 | Wrapper test for `test_benchmark_ieee8500.jl` works under `Pkg.test` after env scrub, within an acceptable runtime | Item 8 | fall back to "manual" documentation |
| A5 | `check_suite_log.py` still parses the summary after the outer-testset change | Pitfall 4 | CI/local gate regressions; verify early |
| A6 | JET API (`print_report_message`, `vst`, `get_reports`) is stable for the pinned 0.11.6 only | Pattern 3 | baseline tooling breaks on a JET bump; guarded by version header + selftest |
| A7 | GitHub cron schedules from the default branch | Workflow | nightly not firing until merged |

## Open Questions (RESOLVED)

1. **pv_boom case study broken at HEAD (Part B exactness gate refuses prices on the boom fixture).**
   - What we know: reproducible in a scratch worktree, 3/3 attempts fail; committed `results/pv_boom/summary.csv` is stale vs HEAD.
   - Unclear: whether the fixture should be re-tuned (model behaviour; out of scope for this phase) or the script archived.
   - Recommendation: in this phase merge the report code as locked, verify via the remap driver, mark both scripts "needs results from a passing case study" in the README, and surface the breakage to the user for a follow-up decision.
   - **RESOLVED (user, 2026-10-06):** RE-TUNE the boom fixture now (in this phase), re-run the case study, regenerate results + reports from the merged shared-lib report script.
2. **Default demo seed 42 trips the battery-complementarity gate.** Recommendation: change the demo to seed 7 now; whether the gate firing on a default-population seed deserves a model-quality follow-up is the user's call.
   - **RESOLVED (user, 2026-10-06):** INVESTIGATE seed 42 as a separate debug task OUTSIDE this phase (pending todo filed). Phase 37 does not change `run_scenario.jl`'s seed; README status notes the known failure + todo.
3. **`+25% FIT ratio golden` ALMOST_OPTIMAL on Julia 1.12.7.** Recommendation: `@test_broken` with reason + allowed-list entry (deterministic), plus a harness measurement on both patches; whether `fit_baseline` should itself retry `ALMOST_OPTIMAL` is a src/ behaviour change and out of scope. Needs a user-visible note in the phase summary.
   - **RESOLVED (user, 2026-10-06):** version-gated `@test_broken` (only where it fails on the running Julia), measured on both patches in the flake harness, backlog note; no src change.
4. **Does the full suite pass on 1.12.7?** Unknown; the instrumented timing run on `julia +1.12` answers it. Compare to 32205/0/0/5 (1.12.5).
   - **RESOLVED:** answered by the plan's instrumented run; any further 1.12.7-only failure is handled the same way as Q3 and reported.
5. **JET "trivially-real" fixes.** RESOLVED by research as far as measured: none of the 33 signatures is a genuine undefined name or wrong-arity bug. The three `UndefVarError` reports (`qag_dso` in `src/admm/DsoOpt.jl:~478`, `q_import_t` in `src/experiments/mpc_loop.jl:~1616`, `seed_q_import` in `src/pricing/fit.jl:~590`) are branch-guarded definitions whose uses are guarded by the same condition; the `Nothing` family is `Union{Nothing,...}` fields (`pf_vars`, `qag_live`, `integer_buffer`, `findfirst`) guarded earlier by `!== nothing`/`μ_j !== nothing`. Optional safe src cleanups (all value-preserving): a helper `_objective(model)::Float64 = objective_value(model)` removes about 22 of 33 signatures at once (verify goldens and canary stay bit-identical); copying `ctx.pf_vars` to a local before the `!== nothing && haskey` test removes the `has_branch_current` report. Planner decides whether to take them; CONTEXT allows baselining.
6. **Where does the baseline file live** (`test/jet_baseline.txt` vs `scripts/`)? **RESOLVED (discretion):** keep it next to `jet_check.jl` and outside any directory the planning-ID guard reads loosely.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia (juliaup) | everything | yes | 1.10.11, 1.11.9, 1.12.5, 1.12.7 (default `release` = 1.12.5; 1.13.1 offered) | - |
| JET | HYG-04 | yes | 0.11.6 (test manifest) | - |
| TestItemRunner | HYG-05/06 | yes | 1.1.5 | - |
| CairoMakie (docs env) | pv_boom report | yes (precompile of Makie on a new Julia patch >10 min) | docs manifest | - |
| JuliaFormatter 2.10 | ieee8500 docstring | not installed locally | CI installs | install into throwaway env |
| `gh` CLI | CI log inspection | yes | - | - |
| Machine | harness | 4 cores, 15 GB RAM | - | `--jobs 1` |

**Missing with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItemRunner 1.1.5 / TestItems 1.0.0 (+ plain Test), JET 0.11.6 as a static check |
| Config file | `test/runtests.jl`, `test/Project.toml`; no JET/flake config yet (Wave 0) |
| Quick run command | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<x>.jl` (filtered recipe) |
| Full suite command | `.github/scripts/suite_detached.sh LABEL` (detached, about 28 min; never concurrent with any Julia run; `pgrep -af julia` first) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HYG-04 | JET finds only baselined signatures | static | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl` (about 61 s warm) | Wave 0 |
| HYG-04 | diff/normalize logic correct | unit | `... scripts/jet_check.jl --selftest` | Wave 0 |
| HYG-05 | fast + slow == all; no empty set; unknown env value errors | discovery-only | extend `scripts/run_tests_filtered.jl --selftest`-style count check (no items run) | Wave 0 |
| HYG-05 | fast set runs in CI budget | integration | `TSODSO_TEST_SET=fast julia --project=. -e 'import Pkg; Pkg.test()'` (detached, about 8-10 min) | Wave 0 |
| HYG-05 | canary stays in fast | discovery-only | assert `:canary`-tagged items are not `:slow` | Wave 0 |
| HYG-06 | retry helper semantics | unit (`@testitem`) | `... run_tests_filtered.jl "$PWD" file:test_flake_retry.jl` | Wave 0 |
| HYG-06 | no new Broken/skip outside allowed list | suite-level | part of `runtests.jl` outer testset; check with a filtered run of `test_ieee13.jl`/`test_diagnostics_plot.jl` | Wave 0 |
| HYG-06 | flake rates recorded | measurement | `julia scripts/flake_rate.jl --repeats 20` (about 25-48 min, manual) | Wave 0 |
| HYG-08 | README lists every `scripts/*` file; archive skipped by API check | script check | `julia --project=. .github/scripts/check_script_api.jl --selftest && ... check_script_api.jl` | exists; skip-rule Wave 0 |
| HYG-08 | `.planning/tmp/` untracked | shell | `git ls-files .planning/tmp | wc -l` = 0 and `git check-ignore .planning/tmp/x` | - |
| HYG-08 | no root `Manifest.toml`; 1.10/1.11/1.12 resolve | CI | `julia-buildpkg` per matrix entry; local: `Pkg.Types.Context().env.manifest_file` per `julia +1.x` | CI |
| HYG-08 | pv_boom merged report equals pre-merge v2 (normalized) | scratch driver | remap driver (see Item 6); about 1 min warm | Wave 0 (scratch, not committed) |
| HYG-08 | docs build emits no `Cannot resolve @ref` | build | `JULIA_LOAD_PATH` docs recipe / `.github/scripts/suite_detached.sh docs ...` | CI `docs` job |
| HYG-08 | ieee8500 test formatter/content-loss clean | CI | `python3 .github/scripts/check_content_loss.py HEAD` after formatting | exists |
| All | planning-id guard clean on new/moved files | script | `python3 .github/scripts/check_planning_ids.py` | exists |

### Sampling Rate
- **Per task commit:** the relevant filtered run or script (<= 60 s), plus `check_planning_ids.py` and `check_script_api.jl`.
- **Per wave merge:** fast set (`TSODSO_TEST_SET=fast`), JET check, docs build when docs/src touched.
- **Phase gate:** one detached full run (`all`, 1.12 latest) reproduces 32205/0/0/5 or documents each delta (the 1.12.7 `fit_baseline` item is the known one); canary iters = 56 and welfare = -4823.66604824162 untouched; any `src/` edit passes goldens bit-identically.

### Wave 0 Gaps
- [ ] `scripts/jet_check.jl` + baseline + `--selftest`
- [ ] `test/runtests.jl` rewrite (env selection, test-dir restriction, outer testset + allowed-Broken list file)
- [ ] `test/fixtures_retry.jl` (`@testmodule`) + `test/test_flake_retry.jl`
- [ ] discovery-count check (fast + slow == all == 605) and canary-stays-fast assertion
- [ ] `scripts/flake_rate.jl`
- [ ] `.github/workflows/slow.yml`; `jet` job and `TSODSO_TEST_SET` env in `CI.yml`
- [ ] `check_script_api.jl` skip `archive` + selftest case

## Security Domain

ASVS applies minimally: build/CI tooling, no network services or user input handling.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3/V4 | no | - |
| V5 Input Validation | partial | validate `TSODSO_TEST_SET` (fail closed on unknown value); CLI arg validation in new scripts |
| V6 Cryptography | no | - |
| V14 Config/Supply chain | yes | pinned manifests; JuliaFormatter pinned `2.10`; no new packages; workflow `permissions:` minimal on the new cron workflow |

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unpinned action/tool drift | Tampering | keep `actions/*@v4`, `julia-actions/*` versions as in existing CI; no `npx`/unverified installs |
| Secrets in the nightly workflow | Info disclosure | the slow workflow needs no secrets (omit codecov token or keep `fail_ci_if_error: false`) |

## Sources

### Primary (HIGH confidence)
- `~/.julia/packages/TestItemRunner/GnoVt/src/TestItemRunner.jl` (v1.1.5) - full source read: filter fields, discovery root, verbose, macro parsing, return value
- Local General registry `J/JET/{Compat,Versions}.toml` - JET vs Julia compat
- Experiments run this session on Julia 1.10.11/1.11.9/1.12.5/1.12.7: JET report (61 s, 42 -> 33 sigs, identical across 1.12.5/1.12.7); manifest selection; Broken-record walk; `verbose=true` per-item timing; `run_scenario` seeds; pv_boom report/case-study runs; `+25% FIT ratio` on 1.12.5 vs 1.12.7
- Repo files: `.github/workflows/CI.yml`, `scripts/run_tests_filtered.jl`, `test/runtests.jl`, `.planning/tmp/36/p05.log`, `.planning/tmp/36/p22docs.log`, `results/reactive_flake_rate/flake_rate_findings.txt`, CI run 37223710620 job timings (`gh run view`)

### Secondary (MEDIUM confidence)
- pkgdocs.julialang.org/v1/toml-files/ (versioned manifests described as 1.11+; contradicted empirically for 1.10.11)

### Tertiary (LOW confidence)
- GitHub Actions env-var passthrough to `Pkg.test` and cron-on-default-branch behaviour: well-known practice, not executed here (A1, A7)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - nothing new, versions read from manifests
- Architecture: HIGH for runner/filter/Broken collection (source + experiment); MEDIUM for CI YAML (not executed)
- Pitfalls: HIGH (each measured), except A1/A2/A4/A5

**Research date:** 2026-10-05
**Valid until:** about 2026-11-05 for JET/TestItemRunner facts; the Julia 1.12 patch sensitivity finding should be re-checked on every new 1.12.x patch
