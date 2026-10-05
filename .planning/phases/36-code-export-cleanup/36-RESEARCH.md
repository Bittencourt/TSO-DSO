# Phase 36: Code & Export Cleanup - Research

**Researched:** 2026-10-05
**Domain:** Julia package hygiene: comment/docstring scrub, dead-seam removal, export surface (`export` vs `public`), nested-module enum, test-fixture renames, CI grep guard
**Confidence:** HIGH on mechanics and counts (all measured in this tree, this session); MEDIUM on two docs-build interactions flagged in the Assumptions Log

## Summary

This is a pure-cleanup phase over a 84-file `src/`+`ext/` tree, 110 test files, 21 scripts and 20 literate pages. The main risks are **wide mechanical blast radius** (about 108 test, script and docs files must change when ~100 names are unexported; about 70 test files carry `setup=[PhaseNFixtures]`; about 6,400 lines carry planning IDs) and **silent semantic drift** while editing so many comments. The research therefore concentrates on cheap, automatable *invariant checks* that make each wave verifiable without the 27-60 min full suite.

Four findings change the plan relative to CONTEXT.md:

1. **`Compat` is not a direct dependency** of `TSODSO` (it is only transitive; 4.18.1 in every Manifest). `Compat.@compat public` therefore needs `Compat = "4.10"` added to `[deps]`+`[compat]` and **eight manifests re-resolved** (4 root `Manifest*.toml`, plus `test/`, `docs/`, `bench/`). A zero-dependency alternative exists (Open Question 1). `@compat public` is a verified no-op on 1.10.
2. **The nested-module enum makes `ReactiveMode` a module, not a type.** Annotations become `::ReactiveMode.T`. Only ~6 annotation sites exist, so this is cheap, but `docs/src/api.md` needs an explicit `@docs ReactiveMode` plus `modules=[TSODSO, TSODSO.ReactiveMode]`, because `@autodocs ... Order=[:type,:constant,:function]` does not surface a module docstring and `checkdocs=:exports` would then fail. There is also a structural audit test (`test_admm_phases.jl:119`) that forbids the bare words `OFF|CERTIFIED|LIVE` in the code lines of `solve_admm.jl` and `admm_phases.jl`.
3. **The ID regex set in CONTEXT.md under-counts.** Extending it to case-insensitive `phase N`, `SITE-/BLOCKER-/GATE-/WARNING-N`, `RESEARCH(.md)`, `CONTEXT.md`, `*-SUMMARY`, `.planning/`, `USER DECISION`, "code review", `quick task` gives **6,391 matching lines** (vs ~5,300). 81 of them are inside *runtime strings* (error/warn messages) in `src/`. About 74 lines mix a thesis equation reference with an ID (vs ~19).
4. **`DlmpDecomposition.loss/.voltage` deprecated aliases carry the text "removal scheduled for Phase 36"** (`src/pricing/dlmp.jl:246,262,269`; `docs/literate/pricing_dlmp.jl:57`), but CONTEXT.md/REQUIREMENTS do not list them. See Open Question 2.

**Primary recommendation:** Execute the CONTEXT order (stubs/shim -> exports -> fixtures/tags -> ID scrub -> guard), add a **Wave 0** that builds the verification tooling first (AST-equivalence checker, thesis-token checker, `names(TSODSO)` snapshot test, multi-file runner, ID classifier), and gate every wave with fast targeted runs, reserving the detached full suite for wave ends.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Planning-ID scrub (HYG-01)**
- Scope: `src/`, `ext/`, `test/`, `scripts/`, `docs/literate/` (~5,300 matching lines; src 80/80 files, test 108/110). The CI guard covers the same scope.
- Rewrite, don't just delete: each comment keeps its rationale in plain prose with the ID removed; delete only when the ID was the whole content. Thesis-equation refs (e.g. "(3.31)", "eq. 3.4x") and literature refs are never touched; the ~19 lines mixing a thesis ref with a planning ID are hand-edited.
- Rename internal constants `MEASURED_ε_FIX08` -> `MEASURED_REL_TOL_EXACT` and `TAU_SOLVER_FIX08` -> `TAU_SOLVER_EXACT` (non-exported; ~19 uses in src/test/scripts). Values unchanged.
- Guard: `.github/scripts/check_planning_ids.py` (alongside `check_content_loss.py`) invoked in the CI format job; regex over ID patterns (Phase N, NN-NN plan refs, D-NN, FIX/ARCH/CR/WR/IN/PM-NN, BILEV/MESH/SCALE/SEAM/DATA/INFRA/PF/HYG-, Wave N, Task N, T-NN-NN, 260xxx-yyy quick IDs, `_FIXNN`) plus the words "byte-identical" and "Pitfall N"; small allowlist file for unavoidable cases; runnable locally. Excludes `.planning/`.

**Stub & shim removal (HYG-02)**
- Remove `operational_oracle`'s `objective_hook`, `horizon_state` and `z` kwargs entirely (unknown-kwarg MethodError thereafter); remove `_coupling_dual`'s `z` throw path; delete the stub-kwarg tests and the two `z` `@test_throws` in `test/test_oracle.jl`; clean the referencing comments (`stochastic_welfare.jl`, `PVBattery.jl`).
- Remove the Bool and Symbol methods of `normalize_reactive_mode`; only the `ReactiveMode` enum is accepted; anything else -> `ArgumentError` naming the valid values. Migrate the ~35 test/fixture/script call sites to the enum form.
- Pure removal: all goldens + canary unchanged, full suite green.
- Record breaking removals in a "Breaking changes" note in the docs (status/API page) and the SUMMARY.

**Export trim (HYG-03)**
- `LP/QP/SOCP/NLP/MILP` problem-class singletons: unexported, names kept (`TSODSO.SOCP()`), declared public via `Compat.@compat public` (works on the 1.10 compat floor); migrate ~120 test/docs/script uses (qualified or explicit `using TSODSO: SOCP` in test setup).
- `ReactiveMode` enum: scoped in a module -> `ReactiveMode.OFF/CERTIFIED/LIVE`; export `ReactiveMode` only; bare `OFF`/`LIVE`/`CERTIFIED` no longer in the namespace.
- `record!`/`converged`: unexported (internal ADMM/MPC trace helpers). Full audit of the 199 exported names: keep researcher-facing API (entry points, feeders/data, device & model types, results/error types, solver factory, power-flow selectors); make internals non-exported (mark useful advanced ones `public`); fix the 4 names exported from multiple files (`record!`, `set_rho!`, `set_rho_q!`, `solve_follower!`).
- Rewrite the stale `src/TSODSO.jl` top-module docstring to describe the module as it is now.
- Gates: Aqua `test_all` (undefined exports) green; docs build with `checkdocs = :exports` green.

**Fixture/tag renames & sequencing (HYG-07)**
- Fixture files/modules renamed after content (planner produces a mapping table from each file's actual contents, e.g. `fixtures_phase6.jl`/`Phase6Fixtures` -> content name); `git mv` to keep history; update all ~46 `setup=[...]` users and docs prose references; regenerate affected docs pages.
- Tags `:phase7` / `:phase25` -> content tags (`:ieee123` / `:ieee8500` / `:admm` as fits); confirm no CI filter depends on the old tags (`scripts/run_tests_filtered.jl tag:` users updated).
- Order: (1) stub/shim removal -> (2) export trim -> (3) fixture/tag renames -> (4) ID scrub last, across every touched file -> (5) CI guard, fail-closed. Full suite after each wave, sequential on main tree; canary checked each time.
- `.planning/` out of scope; guard excludes it.

### Claude's Discretion
- Exact content names for fixtures/modules; exact keep/unexport classification of the 199 exports (documented in the plan); guard regex details and allowlist entries; wording of rewritten comments.

### Deferred Ideas (OUT OF SCOPE)
- JET in CI, `:slow` split, flakes, scripts index, root Manifest -- Phase 37.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HYG-01 | No plan/wave/task/decision/review-finding IDs in comments/docstrings; CI grep guard; thesis/literature refs stay | Sections "ID scrub strategy", "Guard design", "Runtime-string IDs", invariant checkers (AST-equivalence, thesis-token multiset), formatter/content-loss protocol |
| HYG-02 | Inert SEAM-01 stubs (`objective_hook`, `horizon_state`, `z`) and reactive Bool/Symbol shim removed | Sections "HYG-02 mechanics" (exact edit sites, hidden `false` sentinel defaults, third `z` throw test in `test_planning_oracle.jl`) |
| HYG-03 | Export list trimmed; generic names namespaced/unexported; top-module docstring current | Sections "`public` mechanics", "ReactiveMode scoping", "Export audit" (full 196-name classification), Documenter/Aqua interactions |
| HYG-07 | Fixture files and tags named after content | Section "Fixture and tag mapping" (9 files, dependents, tag map) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Julia + JuMP; **models never name a solver** (factory `select_optimizer`); Gurobi only behind the abstraction. Unexporting `GurobiChoice`/`MosekChoice`/`SCSChoice`/`alternative_optimizer`/`commercial_optimizer` must keep the weakdep extensions (which already use fully qualified `TSODSO.` names) loading.
- Correctness and reproducibility: pinned `Project.toml`/`Manifest.toml`; goldens and the knife-edge canary must not move (CONTEXT: iters = 56, welfare = -4823.66604824162).
- Documentation is a hard requirement: every modeling decision documented; rich docs. The docs build (`checkdocs = :exports`) is a gate.
- Clean, idiomatic Julia; JuliaFormatter 2.10.x pinned via `.JuliaFormatter.toml` (`format_docstrings = true`, margin 92).
- **GSD workflow enforcement:** all edits must start from a GSD command (`/gsd-execute-phase` here); no direct repo edits outside it.
- Memory traps that apply to every executor (see "Test-suite cost" and "Pitfalls"): never `@run_package_tests` via `julia -e`; TestItemRunner is not resolvable under `--project=.`; `try x = ...` / for-loop reassignment inside `@testitem` bodies break (top-level scope); detached full suite, no worktree contamination; `local-project-toml-drift`.

## Architectural Responsibility Map

This is a single-tier Julia library (no browser/server/DB tiers). The meaningful ownership split is by *artifact*:

| Capability | Primary Owner | Secondary | Rationale |
|------------|---------------|-----------|-----------|
| Export surface (`export`/`public`) | `src/**` per-file `export` + one `public` block | `src/TSODSO.jl` docstring | Julia resolves visibility at module level; a single `public` block makes the audit reviewable |
| Enum scoping | `src/admm/ReactiveMode.jl` (nested module) | `admm_state.jl`, `DsoOpt.jl`, `AgrOpt.jl`, `strategies.jl` consumers | Defining module owns the namespace; consumers qualify |
| Doc surfacing of nested module | `docs/src/api.md` + `docs/make.jl` `modules=` | -- | Documenter only checks modules listed in `modules` |
| ID guard | `.github/scripts/check_planning_ids.py` + `CI.yml` format job | allowlist file | Mirrors `check_content_loss.py` precedent |
| Fixture naming | `test/fixtures_*.jl` `@testmodule`s | `setup=[...]` in 70 test files, docs/script prose | `@testmodule` is discovered by name by TestItemRunner |
| Invariant tooling (AST/thesis-token/names snapshot) | Wave 0 scripts (+ one new `@testitem`) | -- | Makes mechanical waves verifiable cheaply |

## Standard Stack

### Core (no new runtime libraries except Compat, if its decision stands)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Compat.jl | 4.18.1 resolved in every manifest today (transitive); `[compat] Compat = "4.10"` needed | `@compat public` on Julia 1.10 floor | `@compat public foo, bar` marks public on 1.11+ and is a no-op on 1.10 and earlier (since Compat 3.47.0 / 4.10.0) [VERIFIED: Compat NEWS in local depot `~/.julia/packages/Compat/*/NEWS.md`; executed on Julia 1.10.11 and 1.12.7 in a temp env] |
| Aqua.jl | 0.8.16 (test env) | Quality gates (undefined exports, stale deps, compat bounds) | Already in `test/test_toy_dc.jl`; Aqua 0.8.16 does **not** inspect `public` names [VERIFIED: grep of `src/exports.jl`] |
| Documenter.jl | 1.17 (docs env) | `checkdocs = :exports` | `checkdocs` inspects only modules in `makedocs(modules=...)`; supports `:exports`, `:public`, `:all` [VERIFIED: `src/docchecks.jl` in local depot] |
| JuliaFormatter | **2.10.2** (depot has it) | Format check | CI pins `version="2.10"`; the *global* env has 2.12.6, which reformats ~48 files differently. Never format with the global env. |
| Python 3 + `re`, `subprocess` | system | ID guard, classifiers | Same stack as `check_content_loss.py` (stdlib only) |

### Supporting / rejected

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Compat.@compat public` | `@static if VERSION >= v"1.11.0-DEV.469"; eval(Meta.parse("public a, b")); end` | Zero new dependency, zero manifest churn, same effect. Not what CONTEXT locked; see Open Question 1 |
| Hand-rolled `module ReactiveMode; @enum T OFF CERTIFIED LIVE; end` | EnumX.jl `@enumx` | Same shape (`ReactiveMode.T`, `ReactiveMode.LIVE`), but adds a dependency + 8 manifest updates for no gain |
| Nested module | `Base.getproperty(::Type{ReactiveMode}, s)` overload so the *type* answers `.OFF` | Keeps `::ReactiveMode` annotations but is a hack (shadows DataType fields, confuses JET/Revise). Rejected |

**Installation (only if Compat is kept):**
```bash
# Project.toml: add to [deps]  Compat = "34da2185-b29b-5c13-b0c7-acf172513d20"
#               add to [compat] Compat = "4.10"
# Re-resolve every committed manifest with the matching Julia (juliaup channels 1.10/1.11/1.12 are installed):
for v in 1.10 1.11 1.12; do julia +$v --project=. -e 'import Pkg; Pkg.resolve()'; done   # then copy to Manifest-v$v.toml per commit 908adab's scheme
julia --project=docs  -e 'import Pkg; Pkg.resolve()'   # lists TSODSO deps (docs/Manifest.toml:1742 deps = [...])
julia --project=bench -e 'import Pkg; Pkg.resolve()'   # bench/Manifest.toml:752
julia --project=test  -e 'import Pkg; Pkg.resolve()'   # test/Manifest.toml (no TSODSO entry; project_hash only)
```
Note root `Manifest.toml` and `Manifest-v1.12.toml` have the same `project_hash` but differ byte-wise (line 726); re-resolve both.

**Version verification:** Compat 4.18.1 is the version already pinned in all manifests (uuid 34da2185-b29b-5c13-b0c7-acf172513d20, `Manifest.toml:92-96`) [VERIFIED: repo manifests]. It is a JuliaLang-org package already present transitively, so no new supply-chain surface.

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| Compat | Julia General | years (UUID in all 8 existing manifests) | transitive of most of the ecosystem (also a dep of Aqua, DataFrames, etc.) | github.com/JuliaLang/Compat.jl | n/a (slopcheck is a Python/npm tool; Julia registry not covered) | Approved: already resolved transitively in every manifest; promoted to direct dep only |

**Packages removed due to slopcheck [SLOP] verdict:** none (no new external package is introduced).
**Packages flagged as suspicious [SUS]:** none. No npm/pip/cargo packages are involved; slopcheck was not run because it does not cover the Julia registry. The only package touched is already in the lock files.

## Architecture Patterns

### Recommended wave structure (sequential, main tree, per CONTEXT)

```
Wave 0  Tooling + baselines (no src behavior change)
Wave 1  HYG-02 stub/shim removal                   -> full suite + canary
Wave 2  HYG-03 ReactiveMode scoping, export trim,   -> full suite + canary + Aqua + docs build
        public block, TSODSO.jl docstring
Wave 3  HYG-07 fixture/tag renames                  -> full suite + canary
Wave 4  HYG-01 ID scrub (per-directory plans)       -> AST/thesis/format checks per plan; full suite + docs build at end
Wave 5  Guard script + CI wiring, fail-closed       -> guard exit 0 on tree; self-test; negative test
```

Author hygiene rule for Waves 1-3: **new or rewritten text must already be ID-free** (otherwise Wave 4 pays twice).

### Pattern 1: `@compat public` as one reviewable block

```julia
# src/TSODSO.jl, after the last include, before `end # module`
import Compat: @compat           # keeps Aqua stale-deps green (Compat must be "used")
@compat public SOCP, QP, LP, NLP, MILP, GurobiChoice, MosekChoice, SCSChoice,
               problem_class, alternative_optimizer, commercial_optimizer
# ... one block per subsystem, mirroring docs/src/api.md sections
```
Source: Compat NEWS (local) + executed check: on Julia 1.12.7 `Base.ispublic(Foo,:SOCP) == true` and `Base.isexported == false`; on 1.10.11 the macro line is accepted (no-op). [VERIFIED: ran in temp env]

### Pattern 2: scoped enum (hand-rolled module)

```julia
# src/admm/ReactiveMode.jl
"""
    ReactiveMode

Namespace for the 3-state reactive coupling mode: `ReactiveMode.OFF`, `ReactiveMode.CERTIFIED`,
`ReactiveMode.LIVE`. The type is `ReactiveMode.T`.
"""
module ReactiveMode
@enum T OFF CERTIFIED LIVE
end

# consumers: annotate with ReactiveMode.T, compare with ReactiveMode.LIVE
normalize_reactive_mode(m::ReactiveMode.T) = m
function normalize_reactive_mode(m)
    throw(ArgumentError(
        "normalize_reactive_mode: expected a ReactiveMode ($(join(instances(ReactiveMode.T), ", "))); " *
        "got $(repr(m)) of type $(typeof(m))"))
end
export ReactiveMode      # bare OFF/CERTIFIED/LIVE are NOT exported
```
Measured behaviour of this layout (Julia 1.12.7, scratch test):
- `print`, `string`, string interpolation: `LIVE` (unchanged). Any message such as `"normalizes to $(mode), not LIVE"` is unchanged.
- `repr(x)`: `TSODSO.ReactiveMode.LIVE` (was `TSODSO.LIVE`); `show(MIME"text/plain")`: `LIVE::T = 2` (was `LIVE::ReactiveMode = 2`); `typeof`: `TSODSO.ReactiveMode.T`. No test in `test/`, `scripts/` or `docs/literate/` asserts on a quoted `"LIVE"/"CERTIFIED"/"OFF"` string or on `repr` of a mode [VERIFIED: grep]. `Int(x)`, `Symbol(x)`, `instances(ReactiveMode.T)`, `==` behave as before.

### Anti-Patterns to Avoid
- **Writing `ReactiveMode.OFF/LIVE/CERTIFIED` in the code lines of `src/admm/solve_admm.jl` or `src/admm/admm_phases.jl`.** `test/test_admm_phases.jl:119` asserts `!any(l -> occursin(r"\b(OFF|CERTIFIED|LIVE)\b", l), all_lines)` over the non-comment, non-docstring lines of exactly those two files (the module-qualified form still matches `\bLIVE\b`). Keep all mode literals in `admm_state.jl` / `DsoOpt.jl` / `AgrOpt.jl`; `solve_admm.jl:279` already routes through `_default_reactive_consensus`.
- **Leaving a `false` sentinel as the default.** `src/admm/admm_state.jl:365`, `DsoOpt.jl:178`, `DsoOpt.jl:280` and `solve_admm.jl:59` (signature text) use `_any_flexible_reactive(...) ? LIVE : false`, relying on the Bool method. Once Bool is rejected these become `ReactiveMode.LIVE : ReactiveMode.OFF`. Same numerics (`false -> OFF`), so the canary (which depends on this smart default) must not move.
- **Per-file `export` statements for names that become `public`.** Leaving them defeats the audit and re-introduces the multi-file-export defect.
- **Building rewritten docstrings with a wrapped inline code span whose continuation starts with `|`** (JuliaFormatter table-row data loss, STATE.md).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| `public` on 1.10 | manual `Expr(:public)` hacks | `Compat.@compat public` (locked) or the documented `@static`+`eval(Meta.parse)` fallback | Parser keyword exists only on 1.11+ |
| Scoped enum | custom `Enum` replacement | `@enum` inside a module | Keeps `instances`, `==`, `Int`, hashing |
| Proving "no code changed" across 100+ comment-rewrite files | eyeballing diffs | AST-equivalence checker (below) | 0.3 s for 3 files; sensitive to a one-token code edit, blind to comment edits [VERIFIED: prototype, hash equal after a comment edit, different after `res.cost`->`res.cos`] |
| Detecting formatter data loss | new tooling | existing `.github/scripts/check_content_loss.py` | Already compares ignoring whitespace/commas |
| Locating unexported-name breakage | running the suite to find UndefVarErrors | a static scan script (below) that lists, per `@testitem`, bare uses of newly unexported names | The suite takes 27-60 min; one UndefVarError per run is an expensive loop |

**Key insight:** every mechanical wave here has a *static* oracle (AST hash, name scan, `names()` snapshot, grep counts). Use those for the inner loop and keep the full suite for wave boundaries.

## 1. `public` mechanics (question 1)

- `Compat` is **not** in `Project.toml [deps]` (verified: deps = CSV, Clarabel, DataFrames, DrWatson, HiGHS, Ipopt, JuMP, SparseArrays, StableRNGs). It is in every Manifest as an indirect dep at 4.18.1.
- Needed for the locked decision: `Compat` in `[deps]`, `Compat = "4.10"` in `[compat]` (Aqua "Compat bounds" requires every dep to have a compat entry; Aqua "Stale dependencies" requires the dep to be `import`ed/`using`ed in `src/`), then re-resolve **root x4 (Manifest.toml, -v1.10, -v1.11, -v1.12), test/, docs/, bench/**. `docs/Manifest.toml:1742` and `bench/Manifest.toml:752` embed TSODSO's `deps = [...]` list; stale lists make `Pkg.instantiate` warn about outdated project hash and CI `julia-buildpkg` re-resolve. Precedent for multi-manifest re-resolve: commits `908adab`, `ee1cd5e`.
- Aqua 0.8.16 does not look at `public`; `Base.ispublic` exists on 1.11+ only, so any test asserting publicness must be `@static if VERSION >= v"1.11"`-gated.
- Documenter: `checkdocs = :exports` is unaffected by `public`. `checkdocs = :public` would additionally require every `public` name's docstring to be surfaced (Documenter uses `Base.ispublic` when defined). Because `api.md` `@autodocs` blocks include non-exported bindings, public-but-unexported names stay documented. Optional hardening: switch to `checkdocs = :public` (docs are built on Julia 1.12 in CI) -- recommended as a follow-up, not required.
- Local gate recipe (about 1 min, verified green today on the unmodified tree):
  `JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -e 'using TSODSO, Aqua, Test; Aqua.test_all(TSODSO)'`
  (All 8 Aqua checks pass today, including Persistent tasks, because the working tree is clean of the CairoMakie drift; `file:test_toy_dc.jl` under the filtered runner cannot find `Aqua` inside the testitem, use this direct script instead.)

## 2. ReactiveMode scoping (question 1, continued)

Exact sites that must change [VERIFIED: grep]:

| Site | Change |
|------|--------|
| `src/admm/ReactiveMode.jl` | nested module; delete Bool and Symbol methods; new fallback message naming valid values; `export ReactiveMode, normalize_reactive_mode` -> `export ReactiveMode` (+ `normalize_reactive_mode` unexported; public optional) |
| `src/admm/admm_state.jl:23-27, :365` | `_react_mode(m::ReactiveMode.T)`; `_default_reactive_consensus` -> `ReactiveMode.LIVE : ReactiveMode.OFF` |
| `src/admm/admm_phases.jl:25, :263` | `mode::ReactiveMode.T` (must stay free of bare mode words in code lines) |
| `src/admm/DsoOpt.jl:178, 280, 325, 420-450, 478` | defaults + `mode == ReactiveMode.X` branches + the "unreachable" error |
| `src/admm/AgrOpt.jl:129, 159` | `mode == ReactiveMode.LIVE` |
| `src/admm/solve_admm.jl:59, 279, 311` | signature docs (`reactive_consensus = false` text), default stays `_default_reactive_consensus(aggregators)` |
| `src/experiments/strategies.jl:197` | `reactive_consensus_mode::ReactiveMode.T` (`ADMMDetails`) |
| tests | `test_reactive_mode.jl` (rewrite: enum identity + Bool/Symbol/other -> `ArgumentError` naming valid values), `test_admm_phases.jl:13` (`instances(TSODSO.ReactiveMode.T)`), `:75` loop, `test_strategies.jl:185`, `test_experiments.jl:78` (`isa TSODSO.ReactiveMode.T`), `test_admm_reactive.jl` (~18 sites incl. `reactive_consensus = true` L120/190/367 and `:live/:certified` L241/288/359/380/385/429/492/503), `test_dso.jl` (5), `test_ieee123_admm.jl:236`, `test_admm_meshed.jl` (2 + L54), `fixtures_phase6.jl` (2 OFF refs), `fixtures_phase19.jl` |
| scripts / docs | `scripts/reactive_flake_rate.jl` (8 call sites: `reactive_consensus = false/true` L342/351/360/369 -> `ReactiveMode.OFF/CERTIFIED`), `docs/literate/meshed_reactive_price.jl` (3), `docs/literate/stackelberg_benders.jl` ("CERTIFIED" is the unrelated certificate word, leave) |

Behavioral/serialization impact:
- **Results:** `result_to_dict` stores the enum value itself (`src/experiments/store.jl:190`) into a JLD2 via `@tagsave`; `run.jl:37/49/142` forwards it. The stored JLD2 type path changes from `TSODSO.ReactiveMode` to `TSODSO.ReactiveMode.T`. No tracked JLD2/CSV in `data/` or `results/` contains the enum (verified: no tracked `.jld2`; no `reactive_consensus_mode` in tracked results). Only gitignored local `data/sims/*.jld2` written before this change would load as reconstructed types. Document in the breaking-changes note; no migration needed. CSV collation (`collate_summary`) does not include the mode column.
- **Printed `LIVE`** is unchanged (see Pattern 2). The only user-visible text changes are `repr`/`show` forms.
- **Knife-edge canary:** `test_admm_knifeedge_canary.jl` never names the mode; it relies on the smart default resolving to LIVE. Asserts `iters == 56` and `welfare ≈ -4823.66604824162 (rtol 1e-6, atol 1e-3)` (it is *not* a bit-identity assertion). For CONTEXT's bit-identical requirement, additionally grep the run log for the printed `welfare = -4823.66604824162` and the iteration count line. Baseline measured today: file runs in 55 s (2 passes).
- **Docs:** add `@docs ReactiveMode` to the `Module` block of `docs/src/api.md` (module docstring is category `:module`, not in `Order = [:type,:constant,:function]`); add the enum type to an autodocs block with `Modules = [TSODSO.ReactiveMode]` (or document it in the module docstring); and `makedocs(modules = [TSODSO, TSODSO.ReactiveMode])`. Documenter's `checkdocs` iterates only the modules passed in `modules` [VERIFIED: `docchecks.jl allbindings`], so a docstring-bearing exported `ReactiveMode` binding without a surfacing block fails the build. Explicit docs-build confirmation is required in Wave 2 (Assumption A3).
- Docs prose references: `docs/literate/meshed_reactive_price.jl`, `prosumer_welfare.jl`, `restricted_branch_flow.jl`, `mpc_rolling_horizon.jl`, `integer_investment.jl` use the word `LIVE` mostly in prose, only `meshed_reactive_price.jl` has code.

## 3. HYG-02 mechanics (stub removal)

Edit sites [VERIFIED: read]:
- `src/models/oracle.jl`: signature kwargs L96-99 (`z`, `objective_hook`, `horizon_state`; keep `role`, `allow_export`), docstring items 1-4 (L62-90) rewrite (keep role + meshed-slot prose without IDs), debug block L112-120, `_coupling_dual(ctx, z)` L162-177 -> `_coupling_dual(ctx)` (call site `π = _coupling_dual(ctx, z)` L145), final `export operational_oracle` stays.
- Comment-only references: `src/models/stochastic_welfare.jl:11-16`, `src/devices/PVBattery.jl:248`, `src/planning/subproblem.jl:7,100-111` (describes the stub as superseded), `src/TSODSO.jl:112`.
- Tests: `test/test_oracle.jl` L38-41 and L84-87 (kwargs in item 1 and item 2, keep the rest of those items), the whole `z`-pin item L106-end (L128 `@test_throws` + L139 `z = nothing`); `test/test_planning_oracle.jl` lines L109/195/256 (`z = nothing`) **and the third item at L218-L238 "free-path parity ... z !== nothing guard"** (`z = fill(0.05, T)` + `@test_throws ArgumentError`); CONTEXT only names `test_oracle.jl`. After removal `z = fill(...)` raises `MethodError`, not `ArgumentError`, so the `@test_throws ArgumentError` items would fail rather than pass vacuously. Also the header comments at `test_planning_oracle.jl:18`, `test_oracle.jl:1-5`.
- Count change: test counts drop (about 3 testitems edited/removed in `test_oracle.jl`, 1 in `test_planning_oracle.jl`). The post-wave baseline is "0 failed / 0 errored / 5 broken" with the pass count re-baselined; record the delta in the SUMMARY.
- Recommended new assertions: `@test_throws MethodError operational_oracle(...; z = nothing)` (documents the removal); `normalize_reactive_mode(true)`/`(:live)`/`(1)` -> `ArgumentError` whose message contains `"LIVE"`.

## 4. Export audit (question 2)

Measured: `names(TSODSO)` = 197 (incl. the module itself) = **196** unique exported names (CONTEXT's 199 counted multi-file duplicates and parse noise); 82 `export` statements in 76 files. Duplicates exported from more than one file: `record!` (`admm/residuals.jl`, `models/mpc_trace.jl`; one generic function, methods in two files), `set_rho!`/`set_rho_q!` (`AgrOpt.jl`, `DsoOpt.jl`), `solve_follower!` (`planning/coupling.jl`, `planning/follower.jl`).

**Recommended classification: 90 names stay exported, 3 collapse into the `ReactiveMode` module export, 103 become non-exported** (all remain reachable as `TSODSO.name`; tier P = additionally `@compat public`; tier I = internal, no `public`). Counts in parentheses are `test / literate+docs / scripts` occurrences of the name (comments included); "bare files" counts non-comment bare uses that break when unexported.

### KEEP exported (90), by file group
- **data**: `AbstractFeeder Branch Bus Feeder MeshedFeeder` (`Bus` 265/43/15 -- the most-used), `ieee13_modified ieee123_modified ieee8500_modified ieee8500_mv_modified generate_profiles assert_radial`
- **devices**: `AbstractDevice Aggregator Deferrable FixedCapacitor FourQuadBESS Interruptible PVBattery Thermostatic`
- **power flow**: `AbstractPowerFlow ACPowerFlow ConvexBranchFlow DCPowerFlow LinDistFlow MeshedFlow RestrictedBranchFlow`
- **core/extension API**: `ModelContext contribute! add_to_residual! register_constraint! add_to_objective!` (needed by anyone adding a device or formulation: the CLAUDE.md "swap device models" use case), `TSODSOError CertificateError ConvergenceError SolveFailedError assert_solved! assert_no_slack`
- **solver**: `ProblemClass select_optimizer`; **units**: `SMAX_NO_LIMIT` (53 test uses; the "no limit" sentinel researchers must write)
- **models/entry points**: `solve_welfare solve_toy_dc solve_linear operational_oracle assert_socp_exact! assert_ac_exact! assert_restriction_exact! certify_angle_recoverable! assert_4q_complementarity! assert_battery_complementarity! socp_relaxation_gap`
- **pricing**: `extract_dlmp decompose_dlmp DlmpDecomposition economic_direction_checks welfare_accounting fit_baseline`
- **ADMM**: `solve_admm AdmmResiduals build_agr_opt build_dso_opt AgrOpt DsoOpt solve_agr! solve_dso! ReactiveMode(module)`
- **experiments**: `Scenario ScenarioResult run_scenario run_and_store scenario_filename run_sweep collate_summary run_mpc run_stochastic ADMM Centralized MPC Stochastic AbstractStrategy`
- **planning**: `solve_stackelberg! run_nash! BendersTrace NashTrace build_shared_transmission SharedTransmission DistributorView`
- **diagnostics**: `plot_convergence plot_nash_convergence plot_price_convergence` (generic functions with weakdep-extension methods)
- Cross-check: every name used in `README.md`'s two code samples (`Scenario`, `ADMM`, `build_shared_transmission`, `run_nash!`) is in this set.

### UNEXPORT (103)
| Group | Names | Tier | Notes |
|-------|-------|------|-------|
| Problem classes + choices (CONTEXT-locked) | `LP QP SOCP NLP MILP` (SOCP 178 test uses/66 docs/57 scripts, 41 bare files), `GurobiChoice MosekChoice SCSChoice`, `problem_class alternative_optimizer commercial_optimizer` | P | extensions already fully qualified (`ext/*.jl` use `TSODSO.GurobiChoice` etc.) |
| ADMM internals (CONTEXT-locked) | `record!` (24 test, 4 files), `converged(` (14 test lines), `set_rho!` `set_rho_q!`, `admm_supported`, `normalize_reactive_mode` | I (`set_rho!`/`set_rho_q!`: P) | fixes 3 of the 4 duplicate exports; also `solve_follower!` below |
| Per-unit helpers | `I_base Z_base PerUnitBase to_pu_impedance to_pu_power assert_magnitudes assert_magnitudes_voltage` | I | all <= 5 external uses |
| Data helpers/constants | `IEEE8500_HEAD_SMAX_MVA IEEE8500_LV_BASE IEEE8500_MV_BASE IEEE8500_ROOT_BUS ieee8500_capacitor_buses ieee8500_load_nodes ieee8500_mv_load_buses ieee8500_mv_relabel_map ieee8500_relabel_map ieee123_load_nodes ieee123_relabel_map build_ieee123 assert_connected markov_path` | P for load-node/relabel helpers, I for the constants | `ieee123_load_nodes`: 9 bare files |
| Device/formulation traits | `has_branch_current has_reactive reactive_factor is_flexible_load close_balance!` | P | `close_balance!`: 13 uses in 1 file |
| Exactness internals | `hybrid_ratios socp_gap_report recover_lossfree_shadow_voltage recover_voltage_angles ac_dual_fallback_price` | P | |
| MPC / stochastic building blocks | `MpcTrace MpcWindow any_cert_failed max_jump mean_jump build_mpc_window solve_mpc_window! StochasticOosHarness build_stochastic_welfare build_stochastic_oos_harness solve_stochastic_oos_step!` | P | `max_jump`/`mean_jump` are generic names; `scripts/demo_mpc_plots.jl` has 39 bare uses |
| Experiments internals | `build_feeder build_population build_powerflow build_price sub_seed` | P | 12 bare files for `sub_seed` |
| Planning building blocks | `PlanningOracle build_planning_oracle solve_planning_oracle! FollowerLP build_follower solve_follower! BendersMaster build_master solve_master! add_feasibility_cut! add_optimality_cut! BendersMasterInteger build_master_integer add_ll_cut! add_nogood_cut! apply_integer_cuts! FeasibilityOracle build_feasibility_oracle solve_feasibility_oracle! ac_recheck_incumbent checkpoint_iteration! resume_from_checkpoint solve_with_retry! RETRYABLE_STATUSES LADDER_ATTR_NAMES BilevelKKT build_bilevel_kkt solve_bilevel! solve_variational_equilibrium run_nash_probe activate_distributor! update_coupling! write_back! is_converged trace_summary` | P | heaviest test usage (below) |
| Pricing minor | `FIT_λ_EXPORT FIT_λ_IMPORT FIT_λ_SELF extract_reactive_dlmp` | I (`extract_reactive_dlmp`: P) | |

**Migration cost if all 103 are unexported** (static scan, non-comment lines): **108 files, about 899 sites** (test 70 files, docs literate+md 22, scripts 16). Hot spots: `test_planning_master_integer.jl` 45, `test_planning_master.jl` 44, `scripts/demo_mpc_plots.jl` 39, `test_planning_bilevel.jl` 31, `test_planning_nash.jl` 29, `test_planning_certification_integer.jl` 27, `scripts/benchmark_ieee8500.jl` 26, `docs/literate/integer_investment.jl` 25, `test_planning_coupling.jl` 24.

**Cost lever (planner decision, discretion):** CONTEXT locks only the problem classes, `ReactiveMode`, `record!`, `converged` and the duplicate fix. If wave time is a concern, the "Planning building blocks" row can stay exported in a first pass (those names are specific, not generic, and the duplicates `solve_follower!` just needs one export statement kept). Even then do the rest. Mechanize either way with the scan below; do not hand-edit 900 sites.

**Mechanical migration script (Wave 0 tool):** for every `@testitem`/`@testmodule`/script/literate block, find non-comment, non-`TSODSO.`-qualified uses of the unexport set (regex `(?<![\w!.])NAME(?![\w!])`, with `converged(` anchored on the paren), then (a) test items: append `using TSODSO: n1, n2, ...` after the item's existing `using TSODSO`; (b) scripts and literate pages: insert the same `using TSODSO: ...` at the top of the script or the first `@example` that needs it, or qualify with `TSODSO.`; (c) src-internal uses need nothing (same module). Generic word hazards when scanning: `LP`, `QP`, `NLP`, `converged`, `record!`, `OFF`, `LIVE`, `CERTIFIED` also occur as plain words in comments/strings; the `converged` status-symbol (`:converged`, `r.converged`) must not count (anchor on `converged(` and exclude `.converged`/`:converged`).

**Single `public` block + trimmed exports:** remove the `export` of the 103 names from their files (including both halves of the four duplicates) and put one `@compat public` block per subsystem at the end of `src/TSODSO.jl`. Add a **new `@testitem`** (`test/test_exports.jl`) that snapshots `sort(string.(names(TSODSO)))` against the 90-name keep set plus `ReactiveMode`, asserts `:SOCP`/`:record!`/`:OFF` are not exported, and (gated `@static if VERSION >= v"1.11"`) that `Base.ispublic(TSODSO, :SOCP)`.

## 5. Fixture and tag mapping (question 3)

| Old file / module | Contents (verified) | Proposed new file / module | Dependents |
|---|---|---|---|
| `fixtures_phase3.jl` / `Phase3Fixtures` | 3-bus radial feeder `small_radial_feeder()`, `Tout`, `Pdc`, `Ppv`, `λ₀`, `T=24`; solver-free pure data | `fixtures_small_radial.jl` / `SmallRadialFixtures` | `test_close_balance`, `test_pvbattery`, `test_welfare_solve` (3 items files), 35 refs |
| `fixtures_phase4.jl` / `Phase4Fixtures` | IEEE-13 aggregator builders, MEM price + temperature profiles, 3-bus high-PV over-voltage stress feeder, ground-truth aggregators (seed 20260718) | `fixtures_ieee13.jl` / `IEEE13Fixtures` | 22 test files (+3 fixture files: 6, 7, 21 mention it), 200 refs; also prose in 6 scripts, 5 literate pages, 6 `src/` docstrings |
| `fixtures_phase6.jl` / `Phase6Fixtures` | 2-bus dual-sign-anchor feeder + seeded aggregators (with/without flex), `RHO_2BUS`, `λ₀`, `temperature_profile` | `fixtures_two_bus.jl` / `TwoBusFixtures` | 26 test files + `fixtures_phase19/7/21`, 407 refs (largest); prose in `src/planning/{benders,master}.jl`, `docs/literate/integer_investment.jl` |
| `fixtures_phase7.jl` / `Phase7Fixtures` | IEEE-123 seeded population (one house per load node), `λ₀`, adaptive-ρ/per-unit tolerance constants | `fixtures_ieee123.jl` / `IEEE123Fixtures` | 7 test files, 78 refs; `scripts/{repro_stability_check,reactive_flake_rate,thesis_case123_repro}.jl` and `docs/literate/thesis_reproduction_*.jl` cite the file path in prose only (scripts re-implement inline because `@testmodule` is a no-op outside TestItemRunner) |
| `fixtures_phase8.jl` / `Phase8Fixtures` | `minimal_scenario_kwargs()`, `with_tempdir(f)` | `fixtures_experiment_harness.jl` / `ExperimentHarnessFixtures` | `test_admm_knifeedge_canary` (setup), `test_experiments`, `test_planning_checkpoint`, `test_status_policy`, `test_strategies` |
| `fixtures_phase19.jl` / `Phase19Fixtures` | 4-quadrant BESS aggregators, real-impedance 2-bus feeder, `centralized_welfare_4q`; **`using ..Phase6Fixtures`** (sibling import; `setup=[Phase6Fixtures, Phase19Fixtures]` ordering is load-bearing) | `fixtures_four_quad_bess.jl` / `FourQuadBESSFixtures` | `test_admm_reactive`, `test_ieee123_admm` (note: `test_fourquadbess.jl` does not use it) |
| `fixtures_phase21.jl` / `Phase21Fixtures` | short-`T` (=8) MPC feeder/aggregators + forced-inexact high-PV fixture | `fixtures_mpc.jl` / `MPCFixtures` | `test_ac_oracle`, `test_close_balance`, `test_mpc_terminal`, `test_mpc_loop`, `test_mpc_window`, `test_stochastic_welfare`, `test_strategies`; prose in `src/experiments/mpc_loop.jl`, `docs/literate/{mpc_rolling_horizon,ac_oracle}.jl` |
| `fixtures_phase22.jl` / `Phase22Fixtures` | stochastic fixture (T=6, S=3, Deferrable-free) | `fixtures_stochastic.jl` / `StochasticFixtures` | `test_close_balance`, `test_stochastic_welfare`, `test_stochastic_oos_harness`, `test_run_stochastic` (106 refs) |
| `fixtures_phase23.jl` / `Phase23Fixtures` | 4-bus "diamond" meshed fixture, `:uniform`/`:heterogeneous` impedance profiles | `fixtures_mesh.jl` / `MeshFixtures` | `test_mesh_flow`, `test_mesh_angle_certificate`, `test_admm_meshed`, `test_tsodso_errors`; prose in `src/models/{exactness,mesh_angle_certificate}.jl`, `docs/literate/meshed_reactive_price.jl` |

Names do not collide with existing modules (`PlanningFixtures`, `IEEE13ShortHorizonFixtures`, `FitFixtures`, ...). 70 test files contain `setup=`; 51 of them list a fixture module. `git mv` + sed for `Phase{N}Fixtures` -> new name is purely textual. Total textual refs to rewrite: 3: 35, 4: 200, 6: 407, 7: 78, 8: 52, 19: 19, 21: 81, 22: 106, 23: 56 (1,034, which also removes most `phase` hits from the Wave 4 workload).

Also rename in prose: every `fixtures_phaseN.jl` path mention (about 60 lines in `scripts/`, `docs/literate/`, `src/`, `test/`), and the sibling-order comments in `fixtures_phase19.jl`/`test_admm_reactive.jl`.

**Tags** (`@testitem ... tags = [...]`, all `:phaseN` uses; no `.github/` or `scripts/` code filters on them; only `scripts/run_tests_filtered.jl` accepts an arbitrary `tag:<sym>`):

| Old | Where | New |
|---|---|---|
| `:phase25` (10 items) | `test/test_ieee8500.jl` only | `:ieee8500` |
| `:phase7` in `test_ieee123.jl` (5 items) | IEEE-123 feeder fixture tests | `:ieee123` |
| `:phase7` in `test_ieee123_admm.jl` (2 items, with `:admm`) | IEEE-123 ADMM end-to-end/crossval | `[:admm, :ieee123]` |
| `:phase7` in `test_admm_adaptive.jl` (3), `test_admm_dualresid.jl` (2), `test_agr.jl` (1), `test_dso.jl` (2) | adaptive-ρ / dual-residual / transit-node / `set_rho!` build-once | `:adaptive` (with the existing `:admm`/`:dso`) |
| comment `test_planning_hardening.jl:208` | mentions the `[:admm, :phase7]` precedent | reword |

No existing `:ieee123`/`:ieee8500`/`:adaptive` tags exist (check passed). After renaming, `grep -rE ':phase[0-9]+'` over `test scripts docs .github src` must be empty.

## 6. ID scrub strategy (question 4)

### Measured population (extended regex set, scope = src ext test scripts docs/literate)
**6,391 lines** (comment 3,478; docstring 1,423; executable code 1,486, of which 933 are `PhaseNFixtures` uses that vanish in Wave 3, leaving about 550 code-line hits, of which 81 are `src/` runtime strings).

| Directory | Files with hits | Lines |
|---|---|---|
| `src/TSODSO.jl` | 1 | 108 |
| `src/admm` | 7 | 300 |
| `src/core` / `solver` / `units` / `diagnostics` | 4/3/1/1 | 23 / 35 / 9 / 12 |
| `src/data` | 9 | 140 |
| `src/devices` | 8 | 224 |
| `src/experiments` | 8 | 277 |
| `src/models` | 13 | 467 |
| `src/planning` | 13 | 805 (`benders.jl` alone 222) |
| `src/powerflow` | 7 | 183 |
| `src/pricing` | 4 | 161 |
| `ext` | 4 | 17 |
| `scripts` | 19 | 393 (`benchmark_ieee8500.jl` 104) |
| `docs/literate` | 20 | 377 |
| `docs/make.jl`, `docs/src/status_policy.md`, `README.md`, `.github/workflows/CI.yml` | 4 | 23 + 2 + 2 + 6 |
| `test` (excl. fixtures) | 98 | 2,556 |
| `test/fixtures_*` | 11 | 304 |

Pattern counts (lines): requirement-style IDs 2,591; `phase N` 1,940; `PhaseNFixtures`/`fixtures_phaseN` 1,061; bare `NN-NN` 920; `plan NN-NN` 871; planning-artifact words 854; `D-NN` 714; `Pitfall N` 268; `T-NN-NN` 258; `Task N` 131; `byte-identical` 120; quick IDs 92; `Wave N` 66; `_FIX08` 18.

### Recommended guard regex set (precision-checked)
```python
# case-insensitive where marked (?i). Applied per physical line of tracked files.
PFX = r'(?:FIX|ARCH|CR|WR|IN|PM|BILEV|MESH|SCALE|SEAM|DATA|INFRA|PF|HYG|REACT|EXACT|OVR|MPC|STOCH|INT|DEV|OPT|EXP|IMPED|REPRO|PRICE|PLAN|PVAL|RESET|ADMM|NASH|SITE|BLOCKER|GATE|WARNING)'
RULES = {
 'phase':    r'(?i)\bphases?[\s-]?\d+',                   # also "Phase 13/31", "PRE-PHASE-27", "Phases 26-27"
 'plan':     r'(?i)\bplans?\s+\d{1,2}-\d{2}\b',
 'bare_nn':  r'(?<![\w.:/\-])(?:0\d|[12]\d|3\d)-(?:0\d|1\d|20)(?![\d\w.:/\-])',
 'dec':      r'\b[Dd]-\d{1,2}\b',
 'reqid':    r'\b' + PFX + r'-\d{1,3}[a-z]?\b',
 'wave':     r'(?i)\bwaves?(?:[\s-]?\d)?\b',              # standalone "wave" is also process language (27 extra lines)
 'task':     r'\bTask\s+\d\b',
 'tid':      r'\bT-\d{2}-\d{2}\b',
 'quick':    r'\b26\d{4}-[0-9a-z]{3}\b',
 'fixnn':    r'_FIX\d+',
 'byteid':   r'(?i)byte-?identical',
 'pitfall':  r'\bPitfall\s+[A-Z]?\d+',
 'artifact': r'\bRESEARCH(?:\.md)?\b|CONTEXT\.md|-SUMMARY|-REVIEW\.md|\.planning/|USER DECISION|[Cc]ode[- ]review|quick task|\bspike\s+\d{3}',
 'fxfile':   r'Phase\d+Fixtures|fixtures_phase\d+|:phase\d+',
}
```
False-positive analysis (from 98 lines hit *only* by bare `NN-NN`): about 94% true IDs; the false positives are hour ranges ("hours 13-18", `scripts/pv_boom_report*.jl`), source line ranges ("lines 11-14", `src/data/MeshedFeeder.jl:20`), iteration ranges, and `pp. 89-90`/`60(1):72-87` literature ranges (already excluded by the lookaround/second-number<=20 constraint, except hour/line ranges). Dates are excluded (`2026-10-04`: lookbehind `-`), version ranges (`0.10-0.12` excluded by `\.`), "3-phase" (digit before `-phase`, regex needs digits *after* `phase`), "T-24" horizons (no `T-NN-NN` match), "IEEE-8500" and "IEEE-123" (prefix not in `PFX`; 294 occurrences, intentionally not matched), hex (no `NN-NN` with word chars around). Lowercase "phase 1/2" in running prose was checked and every non-ID occurrence of `phases? ?\d` in scope is in fact a planning phase reference, so the case-insensitive rule is safe. Standalone `wave` has 27 non-numbered occurrences, all process language ("later wave", "mid-wave", "gap-closure wave"). Words **not** machine-checkable and left to rewrite judgment: "gap-closure", "post-merge triage", "checker feedback", "RED until ... lands" (TDD phrasing, 99 `RED/GREEN` lines).

**Scope additions recommended** (small, all currently carry IDs): `docs/make.jl` (23 lines), `docs/src/*.md` tracked pages (`status_policy.md` 2), `README.md` (2: "Phases 19-24"), `.github/workflows/CI.yml` (6: `INFRA-01`, `Pitfall 4`, `Phase-9 WR-04`, `plan 09-04`, `T-09-05`). Use `git ls-files` to enumerate; this skips untracked `docs/src/generated/` (gitignored, 375 hits that vanish when pages regenerate) and `docs/build/`.

### Hazards specific to the scrub
1. **81 runtime-string hits in `src/`** (error/`@warn`/`@debug` messages, e.g. `src/models/oracle.jl:108,177-180`, `src/devices/FourQuadBESS.jl:156-198`, `src/planning/benders.jl:384,545,792,1449,1458`, `src/pricing/{welfare,dlmp,checks,fit}.jl`, `src/powerflow/{Convex,Restricted,LinDist}Flow.jl` "per ARCH-03"). Rewrite them as part of the scrub; they change user-visible text. No test matches message text containing an ID (verified: no `occursin`/`@test_throws ... "msg"` patterns with IDs), and the AST checker ignores string contents. A message that cites `CONTEXT.md locked decision` (`src/planning/bilevel_kkt.jl:310,317`, `nash.jl:1187,1193`) must be reworded to state the actual restriction.
2. **`@testitem` names carry IDs** (`"... (EXACT-01, ...)"`, `"ARCH-01 _powerflow_from_selector ..."`). They are strings; renaming is safe for the suite but changes `occursin(..., ti.name)` filters. None is used by `run_tests_filtered.jl` (it filters by `tag:`/`file:`).
3. **The `MEASURED_ε_FIX08`/`TAU_SOLVER_FIX08` rename** (non-exported, `src/models/exactness.jl:75,85,219,220,451,452` + test/script uses; 21 occurrences / 18 lines) is a *code* change: do it in its own early task and verify with `grep -rn "FIX08"` = 0 and a targeted exactness run (`test_exactness.jl`, `test_exactness_verdict.jl`, `test_ieee13.jl`).
4. **Thesis references live on the same lines** as IDs far more often than the "~19" in CONTEXT: **74 lines** match a strict thesis-equation pattern (`(3.43)`, `thesis 3.39`, `eq. 3.3x`): 63 in `src`, 10 in `test`, 1 in docs. Classifier must tag these `MIXED` for hand edit; the thesis-token check below must pass.
5. **Stale line-number citations** (`PVBattery.jl:42-57`, `benders.jl:35-60`, `fixtures_phase7.jl:92-95`) are not IDs but rot; fix opportunistically when touched, do not add to the guard.
6. **The deprecation text "removal scheduled for Phase 36"** (`dlmp.jl`) must be resolved one way or the other (Open Question 2); it cannot survive the guard.

### Semi-automated workflow (per plan, per directory)
1. **Classifier** (`scratch` Python, reuse the RULES above): for a directory, output `file:line | kind (comment/docstring/code/string) | rules | MIXED? | text`, grouped by file, sorted by line. Suggested kind detection: `#`-prefixed -> comment; between `"""` fences -> docstring; else code (and, if the match is inside quotes, string).
2. Agent rewrites the file(s) of one directory batch (rewrite rationale in plain prose; delete only if the ID was the entire content; fix wrapped sentences left dangling).
3. **Mandatory checks before commit** (all seconds, all scriptable):
   - **AST-equivalence**: `Meta.parseall` both versions, drop `LineNumberNode`s, replace every `String` literal with `""`; hashes must match for every `.jl` file in the batch (comments and docstring/string *content* may differ; any code edit fails). Prototype verified (0.3 s for 3 files, 100% sensitive to a one-token code change). Exceptions: files touched by the FIX08 rename task.
   - **Thesis-token multiset**: per file, the multiset of `\b3\.\d{2}\b`, `Table \d`, `Fig(?:ure)? \d`, `App\. [A-Z]`, `pp?\. ?\d`, `thesis`, author-year literature citations must be identical before/after (catches an ID rewrite that also drops the equation).
   - **Guard on the batch**: `python3 .github/scripts/check_planning_ids.py <dir>` reports 0 for the batch.
   - **Formatter + content loss** (the STATE.md hazard): commit the rewritten text first, then run JuliaFormatter **2.10.x** (`julia -e 'using Pkg; Pkg.activate(temp=true); Pkg.add(name="JuliaFormatter", version="2.10"); using JuliaFormatter; format(["src","ext","test","docs"]; verbose=true)'`, depot has 2.10.2; do NOT use the global env's 2.12.6), then `python3 .github/scripts/check_content_loss.py HEAD` which must print `OK: no content change (whitespace/commas only)`. Order matters: the script compares the working tree to a ref ignoring whitespace and commas, so it only means "formatter lost nothing" if the ref already contains the intended rewrite; run it *before* committing the formatter's changes. A renamed file is invisible to it (new path = "new file"), so Wave 3 renames must be committed before any content-loss comparison.
4. Per-batch fast run (see section 7) is only needed for batches that touch non-comment code (the FIX08 rename, ReactiveMode, `src/TSODSO.jl` docstring).

### Splitting into plans without conflicts (sequential execution, main tree)
Plans are sequential, so conflicts arise only from *shared files*; split by directory and keep each file in exactly one plan. Suggested 9-10 plans of 300-900 lines each:
1. `src/planning` (805; or split `benders.jl` 222 + `nash.jl` 117 + `master*.jl` 187 from the rest) + the FIX08 constant rename (code change, own task)
2. `src/models` (467) + `src/pricing` (161)
3. `src/admm` (300) + `src/powerflow` (183)
4. `src/experiments` (277) + `src/devices` (224) + `src/data` (140) + remaining `src/{core,solver,units,diagnostics}` + `ext` (17)
5. `src/TSODSO.jl` (108 hits: include comments rewritten as section headers) + top-module docstring (already rewritten in Wave 2) + `docs/make.jl`, `docs/src`, `README.md`, `CI.yml`
6. `docs/literate` (377)
7. `scripts` (393)
8-10. `test/` in thirds (2,556 + 304 fixtures): e.g. admm+dso+pricing | planning+certification | everything else + fixtures

Because Waves 1-3 already edited many of these files, **Wave 4 must scan the working tree, not a precomputed list**: re-run the classifier at plan start.

## 7. Test-suite cost and verification recipes (question 5)

Baselines (STATE.md/Memory): Phase 35 close **32177 pass / 0 fail / 0 error / 5 broken**; full suite 27-60 min (slower under memory pressure); never > 10 min in a foreground Bash call (tool timeout kills it); launch detached:
```bash
nohup setsid bash -c "julia --project=. -e 'import Pkg; Pkg.test()' > $LOG 2>&1; echo \$? > $DONE" </dev/null &
```
and poll the marker in a bounded loop. Before certifying: `git worktree list` must show **no `.claude/worktrees/agent-*`** (two sibling worktrees currently exist under `../TSO-DSO.worktrees/`; they are siblings, not under the repo, and are not discovered by `Pkg.test`, but never use `julia -e '@run_package_tests'`). Compare the log's start time with the commit being certified.

**Verified fast-run recipe** (works; avoids both the TestItemRunner-resolution trap and `Pkg.develop` manifest mutation; ~25-30 s fixed startup per invocation):
```bash
JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_oracle.jl   # 21 passed, 32 s
JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" tag:ieee8500
```
Caveats measured today: (a) `JULIA_LOAD_PATH="test:.:@stdlib"` (the memory recipe) does **not** work with this runner (`Package TSODSO not found`); use `@:test:@stdlib` with `--project=.`. (b) Items doing `using Aqua` fail under this recipe ("Package Aqua not found"); run Aqua through the direct script in section 1. (c) The runner takes one spec; each invocation pays ~25 s startup, so **Wave 0 should extend it to accept several `file:` specs / `tag:` specs** (a 5-line change in `scripts/run_tests_filtered.jl`, Phase 37's scripts-index task does not conflict).

Per-wave fast sets:
| Wave | Fast set (minutes) | Mandatory full suite? |
|---|---|---|
| 0 | tooling self-tests only | no |
| 1 (HYG-02) | `test_oracle`, `test_planning_oracle`, `test_reactive_mode`, `test_admm_phases`, `test_admm_reactive` (27 KB, heavy), `test_dso`, `test_admm_meshed`, `test_ieee123_admm`, `test_admm_knifeedge_canary` (55 s), `test_strategies`, `test_experiments`, `test_admm` + `julia --project=docs` build of `meshed_reactive_price` | **Yes, at wave end** (default-value change flows into every ADMM item) |
| 2 (HYG-03) | per-batch: every test file in `git diff --name-only HEAD -- test`, then Aqua script, then `docs/make.jl` | **Yes + docs build** (touches 108 files) |
| 3 (HYG-07) | static: setup-name resolution script (every `setup=[X]` has a `@testmodule X`), `grep -rE 'Phase[0-9]+Fixtures|fixtures_phase|:phase[0-9]'` = 0, `tag:ieee123 tag:ieee8500 tag:adaptive` runs | **Yes** (textual but wide: 70 files) |
| 4 (HYG-01) | AST-equivalence + thesis-token + guard + formatter/content-loss (static, seconds); targeted tests only for the FIX08 rename task | **Yes once at the end**, plus docs build (docstrings render through Documenter) |
| 5 (guard) | guard self-test + `exit 0` on tree + negative test; YAML lint | no (CI run is the real gate) |

Docs build: `julia --project=docs docs/make.jl` (CI uses Julia 1.12 and a 30-minute timeout; the `socp_applicability` page alone solves live for ~70 s). Run locally at the end of Waves 1 (only the affected page), 2, and 4.

## 8. Guard design (HYG-01 CI)

- `.github/scripts/check_planning_ids.py`, stdlib only, mirrors `check_content_loss.py`: `git rev-parse --show-toplevel`, `git ls-files` for roots `src ext test scripts docs/literate docs/make.jl docs/src README.md .github/workflows`, extensions `.jl .py .sh .md .yml .toml`; excludes `.planning/`, the script itself, and the allowlist file; prints `path:line: [rule] text` and exits 1 on any hit; optional positional path args to scan a subtree (used per batch); `--selftest` runs built-in positive/negative cases (the negative set must include "3-phase", "T-24", "IEEE-8500", `2026-10-04`, `0.10-0.12`, "eq. 3.43", "Gan-Low 2015").
- Allowlist: `.github/scripts/planning_ids_allowlist.txt`, one entry per line `path<TAB>regex-fragment<TAB>reason`; match by path + text fragment, **not line number** (line numbers drift). Seed entries: the hour-range lines in `scripts/pv_boom_report*.jl` ("hours 13-18"), the "lines 11-14" style citations if any survive, and `docs/literate` literature page ranges. Keep it under about 10 entries; an allowlist hit that no longer matches anything should itself fail (stale-entry check) so it cannot rot.
- CI: add a step to the `format` job after "Check for formatter content loss": `python3 .github/scripts/check_planning_ids.py` (no `if: always()` needed; plain failure is correct). Fail-closed: any unreadable file or allowlist parse error exits non-zero.
- `check_content_loss.py` usage in CI stays as is (`HEAD` vs post-format tree).

## Common Pitfalls

### Pitfall 1: Unexporting a name silently breaks `@example` blocks in the docs build
**What goes wrong:** literate pages and `docs/src/index.md`/`status_policy.md` `@example` blocks call `SOCP()`, `max_jump(...)`, `record!(...)` bare; the failure appears only in the 15+ min docs build.
**How to avoid:** include `docs/literate` and `docs/src` in the migration scan (22 files); run the docs build at the end of Wave 2.

### Pitfall 2: `checkdocs = :exports` fails on the new `ReactiveMode` module binding
**Why:** the module docstring is not surfaced by `@autodocs` (`Order` lacks `:module`) and nested-module bindings are checked only if the module is in `modules`.
**How to avoid:** `@docs ReactiveMode` in the Module block, `modules = [TSODSO, TSODSO.ReactiveMode]`, and an explicit docs-build check (Assumption A3).

### Pitfall 3: Aqua stale deps / compat bounds after adding Compat
**How to avoid:** `import Compat: @compat` in `src/TSODSO.jl`, `Compat = "4.10"` in `[compat]`, all manifests re-resolved; run the direct Aqua script.

### Pitfall 4: Removing `z` makes the old `@test_throws ArgumentError` fail with `MethodError`
Covered in section 3 (third site in `test_planning_oracle.jl`).

### Pitfall 5: The `\b(OFF|CERTIFIED|LIVE)\b` audit test
Covered in Anti-Patterns; also `test_admm_phases.jl:119-126` has a second regex forbidding `reactive*mode` comparisons in those two files.

### Pitfall 6: Formatter data loss and the wrong formatter version
Use 2.10.x only, run `check_content_loss.py HEAD` before committing the formatter pass (section 6).

### Pitfall 7: TestItem body scoping when migrating tests
When inserting `using TSODSO: ...` or rewriting `try`/`for` blocks inside `@testitem`s, remember the body is top-level code: `try x = f() ...` and for-loop reassignment of outer variables break under TestItemRunner (memory: `testitem-try-scoping-trap`). Insert `using` lines only; do not restructure control flow.

### Pitfall 8: Renamed fixture files escape `check_content_loss.py`
`git show REF:newpath` fails -> treated as "new file". Commit renames separately and do content-loss checks in later waves.

### Pitfall 9: Stale `data/sims/*.jld2`
Local JLD2 provenance files written before Wave 2 store the old enum type path. Not tracked; mention in the breaking-changes note.

### Pitfall 10: Full-suite certification contaminated by stale runs or worktrees
Memory `background-suite-orphan-race`: compare log start time to the last commit; no `.claude/worktrees/agent-*`.

## Code Examples

### Multi-spec filtered runner (Wave 0, tiny extension)
```julia
# scripts/run_tests_filtered.jl: accept several specs, OR-combined
specs = ARGS[2:end]
preds = map(specs) do s
    kind, val = split(s, ":"; limit = 2)
    kind == "tag"  ? (ti -> Symbol(val) in ti.tags) :
    kind == "file" ? (ti -> basename(ti.filename) in split(val, ",")) :
    error("filter spec must be tag:<sym> or file:<a.jl[,b.jl]>, got $s")
end
TestItemRunner.run_tests(joinpath(root, "test"); filter = ti -> any(p -> p(ti), preds))
```

### AST-equivalence checker (Wave 0, `.github/scripts/` or scratch; verified prototype)
```julia
function norm(x)
    x isa String && return ""
    x isa LineNumberNode && return nothing
    x isa Expr || return x
    return Expr(x.head, (norm(a) for a in x.args if !(a isa LineNumberNode))...)
end
filehash(p) = hash(norm(Meta.parseall(read(p, String))))
# compare: hash of `git show HEAD:path` content vs working tree, for every changed .jl file
```

### Export-surface snapshot test (Wave 2)
```julia
@testitem "exports: public surface is the curated set" tags = [:exports] begin
    using TSODSO
    exported = Set(names(TSODSO))
    @test :ReactiveMode in exported
    for n in (:OFF, :LIVE, :CERTIFIED, :LP, :QP, :SOCP, :NLP, :MILP, :record!, :converged)
        @test n ∉ exported
    end
    @static if VERSION >= v"1.11"
        @test Base.ispublic(TSODSO, :SOCP)
    end
    @test TSODSO.SOCP() isa TSODSO.ProblemClass
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Everything `export`ed | `export` for entry points + `public` for advanced API | Julia 1.11 (`public` keyword) | `names()` shrinks; docs/`checkdocs=:public` can still cover public names |
| `@enum` with flat exported members | Enum inside a module (EnumX-style) | community convention | `ReactiveMode.LIVE`; type is `ReactiveMode.T` |

**Deprecated/outdated:** the `reactive_consensus::Bool` kwarg spelling (`false/true`) and `:off/:certified/:live` Symbols (removed here); `operational_oracle`'s `z`/`objective_hook`/`horizon_state` (removed here).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Wave 4 plan sizes (9-10 plans) are right for executors | ID scrub | Planner may resize; no correctness impact |
| A2 | Docs build duration locally is on the order of CI's 30 min budget (not measured) | Test cost | Wave 2/4 verification may need a detached run |
| A3 | `@docs ReactiveMode` + `modules=[TSODSO, TSODSO.ReactiveMode]` satisfies `checkdocs=:exports` for the nested module (derived from reading `docchecks.jl`, not executed) | ReactiveMode scoping, Pitfall 2 | Wave 2 docs build might fail; fall back to documenting the enum in the `ReactiveMode` module docstring only and leaving the nested module out of `modules` |
| A4 | The ~13 non-numbered "RED until ... lands"/"gap-closure" process phrases are acceptable to leave to rewrite judgment (not guard-enforceable) | Guard | HYG-01 wording "no plan/wave/task/decision IDs" is satisfied by IDs only |
| A5 | Adding `docs/make.jl`, `docs/src`, `README.md`, `CI.yml` to the scrub/guard scope is wanted (CONTEXT lists only 5 directories) | Guard | Cosmetic; drop from scope if the user prefers strict CONTEXT scope |
| A6 | Conservative cost lever: keeping the planning building blocks exported is acceptable | Export audit | HYG-03 text says "trimmed", not "minimal"; user may prefer the full trim |

## Open Questions (RESOLVED)

1. **Compat as a direct dependency vs the zero-dependency `public` fallback**
   - What we know: CONTEXT locks `Compat.@compat public`, assuming it is available; Compat is only transitive today. Making it direct costs 8 manifest re-resolves (precedent exists) and a `[compat]` entry. The documented `@static if VERSION >= v"1.11.0-DEV.469"; eval(Meta.parse("public ..."))` achieves the same with no dependency.
   - What's unclear: whether the user knowingly accepts the manifest churn (Phase 37 also touches manifests, HYG-08 "root Manifest.toml dropped or documented").
   - Recommendation: **honor the locked decision** (add Compat, re-resolve with `juliaup` 1.10/1.11/1.12), mention the fallback in the SUMMARY; if re-resolve proves messy, the fallback is a 3-line swap with identical behavior. Mark as needing a one-line confirmation at plan time.
   - **RESOLVED (user, 2026-10-05):** add Compat as a direct dependency.

2. **`DlmpDecomposition.loss`/`.voltage` deprecated aliases ("removal scheduled for Phase 36")**
   - What we know: `src/pricing/dlmp.jl:246,262,269` and `docs/literate/pricing_dlmp.jl:57` promise removal in this phase; CONTEXT and REQUIREMENTS do not list it. Users: `test/test_pricing_dlmp.jl:353-390` (alias test), `:582-584` (the `NamedTuple(d)` conversion intentionally keeps old names, unrelated), `scripts/pv_boom_report.jl:83,85` and `pv_boom_report_v2.jl:83,...` (`decomp.loss`, `decomp.voltage`).
   - What's unclear: whether the user wants the removal in this phase.
   - Recommendation: **remove** (the ID scrub forces touching those sentences anyway; the cost is deleting `getproperty`/`propertynames` extras, one test item, and 3 script lines -> `.cone`/`.drop`), recorded in the breaking-changes note; **needs user confirmation** because it is outside the named HYG-02 scope. If declined, reword to "deprecated; slated for removal" without a phase number.
   - **RESOLVED (user, 2026-10-05):** remove now; list in Breaking changes.

3. **Scope of the scrub/guard beyond the five CONTEXT directories** (`docs/make.jl`, `docs/src/status_policy.md`, `README.md`, `.github/workflows/CI.yml`; about 33 lines). Recommendation: include (A5).
   - **RESOLVED (user, 2026-10-05):** include. Also: planning-artifact path/name citations (RESEARCH.md, CONTEXT.md, `.planning/...`) are scrubbed + guarded.

4. **RESOLVED by CONTEXT:** ID-scrub rewrite policy; FIX08 constant names; guard location; `ReactiveMode` as `ReactiveMode.OFF/...` with only `ReactiveMode` exported; `record!`/`converged` unexported; Bool/Symbol removal with `ArgumentError`; sequencing (1)-(5); `.planning/` excluded; no golden re-pinned.

5. **RESOLVED by research:** "199 exported names" is 196 unique names (197 in `names()` incl. the module); `Compat` availability (not a direct dep); `show`/serialization impact (print unchanged; `repr` and JLD2 type path change; no tracked data affected).

6. **Third stub test:** `test/test_planning_oracle.jl:218-238` also holds a `z` `@test_throws` (CONTEXT mentions two in `test_oracle.jl` only). Recommendation: delete it in Wave 1.
   - **RESOLVED:** adopted in CONTEXT Research Refinements.

## Runtime State Inventory

This is a rename/refactor phase, so each category is answered explicitly:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Gitignored `data/sims/*.jld2` provenance files written by `run_and_store` hold a `ReactiveMode` enum value (type path `TSODSO.ReactiveMode`). No tracked JLD2/CSV in `data/`, `results/` contains the enum or `reactive_consensus_mode` | None for the repo. Note in breaking-changes doc that pre-existing local sims load with a reconstructed placeholder type |
| Live service config | None -- verified: no external services; CI is GitHub Actions defined in-repo | None |
| OS-registered state | None -- verified: no scheduled tasks, pm2/systemd units reference these names | None |
| Secrets/env vars | `DOCUMENTER_KEY`, `GITHUB_TOKEN`, `CI` (workflow-level) are unaffected by any rename | None |
| Build artifacts / installed packages | `docs/build/` (ignored) and `docs/src/generated/` (ignored; 375 stale ID lines) regenerate on docs build; `test/Manifest.toml`, `docs/Manifest.toml`, `bench/Manifest.toml` and 4 root manifests need re-resolve if Compat is added; precompile caches rebuild on first load | Re-resolve manifests (Open Question 1); rebuild docs |

**Canonical question:** after every file is updated, runtime systems holding the old names are only (a) local `data/sims` JLD2 files and (b) stale docs build outputs. Both are non-tracked.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all | yes | 1.12.5 (default), 1.10.11, 1.11.9, 1.12.7 via juliaup | -- |
| JuliaFormatter 2.10.x | format gate | yes in depot (2.10.2, 2.10.1); global env has 2.12.6 (wrong) | 2.10.2 | `Pkg.add(name="JuliaFormatter", version="2.10")` in a temp env (offline works) |
| Python 3 | guard + classifiers | yes | system python3 | -- |
| Documenter 1.17 / Literate 2.21 / CairoMakie | docs build | yes (docs/Manifest.toml; depot) | 1.17 | -- |
| Aqua 0.8.16 | quality gate | yes | 0.8.16 | direct script (see section 1) |
| git / `git mv` | fixture renames | yes | -- | -- |
| Extra git worktrees | `../TSO-DSO.worktrees/{operational-planning-integration,pdf-documentation-thesis-results}` exist | present | -- | do not use `julia -e @run_package_tests`; use the verified recipe |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` + TestItems/TestItemRunner (test env: Aqua 0.8.16, BilevelJuMP pinned, JET present but out of scope) |
| Config file | `test/Project.toml`, `test/runtests.jl` (`@run_package_tests`) |
| Quick run command | `JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<test_x.jl>` or `tag:<sym>` |
| Aqua gate | `JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -e 'using TSODSO, Aqua, Test; Aqua.test_all(TSODSO)'` (about 1 min) |
| Static gates | `python3 .github/scripts/check_planning_ids.py`, AST-equivalence checker, thesis-token checker, `python3 .github/scripts/check_content_loss.py HEAD` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (detached, 27-60 min; baseline 32177/0/0/5 before deletions) |
| Docs gate | `julia --project=docs docs/make.jl` (checkdocs = :exports, missing_docs fatal) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HYG-01 | Zero planning IDs in tracked scope | static | `python3 .github/scripts/check_planning_ids.py` (exit 0) | Wave 5 / Wave 0 prototype |
| HYG-01 | Guard regex quality (positives/negatives) | unit | `python3 .github/scripts/check_planning_ids.py --selftest` | Wave 5 |
| HYG-01 | Scrub changed no executable code | static | AST-equivalence checker vs `HEAD` per batch | Wave 0 |
| HYG-01 | Thesis/literature refs preserved | static | thesis-token multiset checker per file | Wave 0 |
| HYG-01 | Formatter lost no text | static | `check_content_loss.py HEAD` after 2.10.x format | exists |
| HYG-01 | Constants renamed, values unchanged | unit | `file:test_exactness.jl,test_exactness_verdict.jl,test_ieee13.jl`; `grep -rn FIX08` = 0 | exists |
| HYG-02 | `operational_oracle` rejects removed kwargs | unit | `file:test_oracle.jl` (new `@test_throws MethodError`) | edit in Wave 1 |
| HYG-02 | `normalize_reactive_mode` accepts only the enum; Bool/Symbol/other -> `ArgumentError` naming valid values | unit | `file:test_reactive_mode.jl` | rewrite in Wave 1 |
| HYG-02 | No behavior change: goldens + canary | integration | `file:test_admm_knifeedge_canary.jl` (log must show `welfare = -4823.66604824162`, iters 56) + full suite | exists |
| HYG-03 | Generic names not exported; keep-set exact | unit | `tag:exports` (`test/test_exports.jl`) | Wave 2 new |
| HYG-03 | No undefined exports, deps/compat clean | quality | Aqua direct script | exists (script) |
| HYG-03 | Docs build with `checkdocs = :exports` incl. nested module | docs | `julia --project=docs docs/make.jl` | exists |
| HYG-03 | Migrated call sites compile | unit | every file in `git diff --name-only HEAD -- test` | exists |
| HYG-07 | No `fixtures_phaseN` / `PhaseNFixtures` / `:phaseN` anywhere | static | `grep -rE 'Phase[0-9]+Fixtures|fixtures_phase[0-9]|:phase[0-9]+' src ext test scripts docs/literate docs/make.jl .github` = 0 | Wave 3 |
| HYG-07 | Every `setup=[X]` resolves to a `@testmodule X` | static | name-resolution script | Wave 0 |
| HYG-07 | Renamed tags select the right items | integration | `tag:ieee123`, `tag:ieee8500`, `tag:adaptive` (non-empty selections) | Wave 3 |

### Sampling Rate
- **Per task commit:** the static checks for the touched files (seconds) plus the targeted `file:` set (1-3 min).
- **Per wave merge:** full suite detached, sequential, main tree; compare against 32177/0/0/5 adjusted for deleted tests, canary line in log, Aqua script, docs build (Waves 2 and 4).
- **Phase gate:** full suite green, guard exit 0 on the tree, docs build green, canary `iters = 56` and `welfare = -4823.66604824162` unchanged, `git diff` of goldens empty.

### Wave 0 Gaps
- [ ] AST-equivalence checker script (Julia) -- covers HYG-01 "no code changed"
- [ ] Thesis-token multiset checker (Python) -- covers HYG-01 "refs preserved"
- [ ] ID classifier (Python, RULES above) with `MIXED` flagging and per-directory output
- [ ] Unexport-usage scanner / `using TSODSO:` inserter -- covers HYG-03 migration
- [ ] `setup=[...]` name-resolution script -- covers HYG-07
- [ ] `test/test_exports.jl` snapshot test -- covers HYG-03
- [ ] Multi-spec extension of `scripts/run_tests_filtered.jl`
- [ ] Baseline capture: full-suite counts and the canary log line recorded before Wave 1

## Security Domain

Security enforcement is not disabled in config; this phase is a refactor of a local research library with no network, auth, or untrusted-input surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | -- |
| V3 Session Management | no | -- |
| V4 Access Control | no | -- |
| V5 Input Validation | partly | `normalize_reactive_mode` fail-loud `ArgumentError` on any non-enum value (project convention: `throw`, never `@assert`) |
| V6 Cryptography | no | -- (the FNV digest in `store.jl` is a filename hash, untouched) |
| V14 Supply chain | yes | adding `Compat` only promotes an already-locked transitive package; committed manifests re-resolved, no new registry packages |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent semantic change while bulk-editing comments (tampering with code) | Tampering | AST-equivalence gate per batch; full suite at wave ends |
| Formatter silently deleting docstring text | Tampering | `check_content_loss.py` before committing formatter output |
| Loud-failure erosion (removing guards while removing stubs) | Repudiation | keep `role` validation; new `MethodError`/`ArgumentError` tests document the intended failure |
| Manifest drift / dependency confusion on `Compat` | Tampering | resolve from the General registry only; verify UUID `34da2185-b29b-5c13-b0c7-acf172513d20` against existing manifests |

## Sources

### Primary (HIGH confidence)
- Repository, measured this session: `Project.toml`, 4 root manifests + `test/` `docs/` `bench/` manifests, `src/**` (exports, `ReactiveMode.jl`, `oracle.jl`, `dlmp.jl`, `TSODSO.jl`), `test/**` (fixtures, tags, `test_admm_phases.jl:119`, canary), `docs/make.jl`, `docs/src/api.md`, `.github/workflows/CI.yml`, `.github/scripts/check_content_loss.py`, `scripts/run_tests_filtered.jl`, `.JuliaFormatter.toml`
- Local depot, read directly: `Compat/*/NEWS.md` (`@compat public`, since 3.47.0 / 4.10.0); `Documenter/*/src/docchecks.jl` (`allbindings`, `checkdocs` semantics); `Aqua/*/src/exports.jl` (no `public` handling)
- Executed: `@compat public` on Julia 1.10.11 and 1.12.7; scoped-enum `show`/`print`/`repr` on 1.12.7; Aqua `test_all` (all 8 pass) on the current tree; filtered runner for `test_oracle.jl`, `test_toy_dc.jl`, `test_admm_knifeedge_canary.jl`; AST-normalization prototype
- `.planning/phases/36-code-export-cleanup/36-CONTEXT.md`, `.planning/REQUIREMENTS.md` (HYG-01/02/03/07), `.planning/ROADMAP.md` (Phase 36 criteria), `.planning/STATE.md` (formatter hazard, baselines)
- Project memory notes: `gsd-plan-verify-testitemrunner-trap`, `testitem-try-scoping-trap`, `background-suite-orphan-race`, `local-project-toml-drift`

### Secondary (MEDIUM confidence)
- None needed; no web sources were used (all behavior was verified against the local tree and depot).

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Compat/Aqua/Documenter facts read from the local depot and executed
- Architecture (waves, classification): HIGH for mechanics, MEDIUM for the keep/unexport judgment (explicitly Claude's discretion, with a cost lever)
- Pitfalls: HIGH -- each was reproduced or located at a specific file:line
- Counts: HIGH for those quoted from scripts run today (6,391 / 196 / 108 files / 899 sites / 81 runtime strings); regexes may be tightened at plan time

**Research date:** 2026-10-05
**Valid until:** 2026-11-04 (stable tooling; counts drift only if other phases land first -- re-run the classifier at plan start)
