# Phase 14: Validation-Oracle Regression Hardening & Docs - Research

**Researched:** 2026-07-24
**Domain:** Julia test/docs infrastructure (TestItemRunner regression suite + Documenter/Literate literate docs) for an existing JuMP planning-layer codebase. No new modeling math.
**Confidence:** HIGH (all load-bearing claims below were verified by directly running the project's own tooling in this session, not inferred from training data)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Golden Fixture Pinning (PVAL-02)
- Pin BOTH canonical fixtures: N=1 certified Stackelberg equilibrium (z*=0.7, cost −0.245, coupling
  duals — the Phase 11 certification case) and the N=2 Nash fixture (z, x_inv, per-distributor cost,
  probe spread from Phase 13's hand-checked congested equilibrium).
- Golden values live as hardcoded literals in a new `test/fixtures_planning.jl` — matches the
  existing `fixtures_phaseN.jl` computed-golden convention (reproducibility anchors, commented).
- Two-layer gating semantics: BilevelJuMP agreement (N=1) and diagonalization convergence (N=2)
  are asserted as the GATE first, then value regression against the pinned goldens in the same
  testitems. Goldens are never trusted without the gate re-passing.
- Tolerance policy follows Phase 11 certification: rel 1e-6 on objective/z; looser, explicitly
  documented tolerance on duals; a rationale comment per pinned value.

#### Literate Documentation (PVAL-03)
- Two new Literate pages continuing the existing rung-ladder convention:
  "Rung 6: Stackelberg–Benders (planning)" and "Rung 7: Nash Diagonalization & Shared Corridor",
  wired as a new "Planning" section in `docs/make.jl` pages.
- Content contract: PSR problem-number ↔ code-symbol map, coupling-seam table (`z↔p_ag`,
  `λ_j↔π_s`), and the interpretive leader/follower choice INCLUDING the Phase 11 empirical
  certification story (StrongDualityMode / ProductMode / hand enumeration / production Benders
  4-way agreement).
- `@example` blocks execute live on tiny fixtures (seconds-scale), matching existing rung pages —
  real output rendered in the docs build.
- Exported planning symbols get docstrings surfaced via the existing `api.md` `@autodocs`
  (`checkdocs = :exports` already enforces coverage); no manual `@docs` blocks needed.

#### No-Binaries Guard (PVAL-04)
- Enforcement is a dedicated `@testitem` that BUILDS every planning-layer model via its public
  builder and asserts zero `is_binary`/`is_integer` variables — semantic check, not a grep lint.
- Builder coverage via an explicit registry (planning oracle, FollowerLP, BendersMaster,
  SharedTransmission) PLUS a tripwire asserting the registry covers all `src/planning/` builder
  entry points, so a future builder cannot silently skip the guard.
- Failure mode is fail-loud: name the offending variables and the owning builder.
- Guard is test-only (no runtime overhead; builders stay clean). No runtime `assert_continuous!`.

#### Regression Suite Wiring (PVAL-01 retention + CI gate)
- New `test/test_planning_goldens.jl` with default-on inclusion in the same `Pkg.test` gate as the
  existing acceptance regression — the same CI gate that runs PVAL-01.
- Runtime budget: tiny fixtures only; target <60s for the new golden set.
- PVAL-01 (`test/test_planning_certification.jl`) stays untouched and in-suite; the goldens file
  carries an explicit cross-reference documenting the gate relationship.
- Docs build stays OUT of `Pkg.test` (existing convention — docs CI builds separately); the
  goldens gate remains solver-only.

### Claude's Discretion
- Exact Literate page prose structure, section ordering, and figure choices.
- Naming of the builder-registry tripwire mechanism and its discovery heuristic.
- Whether the N=2 golden pins the probe spread value itself or a bound on it (pick whichever is
  robust to solver noise, with rationale documented).

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

### Additional Context Notes (Existing Code Insights, Specifics)
- Computed-golden convention: `test/test_acceptance.jl` ("pinned computed golden regression"
  @testitem) and `test/fixtures_phase4.jl` (COMPUTED golden as reproducibility anchor, commented).
- PVAL-01 permanent regression: `test/test_planning_certification.jl` (4-way certification,
  `[:planning]`-tagged).
- Phase 13 fixtures: hand-checked N=2 congested equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3]) and
  seed-liveness fixtures in `test/test_planning_nash.jl`; `run_nash_probe` 6-run gate.
- Literate pipeline: `docs/literate/*.jl` → `docs/src/generated/*.md`; six existing rung pages
  as structural templates (toy_dc.jl is the smallest example).
- `docs/make.jl`: pages tree with "Models" rung section; `checkdocs = :exports` (undocumented
  exported symbol FAILS the build); `remotes = nothing` for worktree-safe builds; api.md
  `@autodocs` with raised size_threshold.
- Tests: `@testitem` per concern, TestItemRunner, tags like `[:planning]`; fail-loud ArgumentError
  convention throughout planning layer.
- Known gotcha: bare `@run_package_tests` discovers `.claude/worktrees/` copies — verification
  should use explicit paths/filters from a scratch environment.
- Integration points: `docs/make.jl` pages array (add "Planning" section) and `docs/literate/`
  (new .jl sources); `test/runtests.jl` auto-discovers new test files (no wiring needed beyond
  file creation); `src/planning/` public builders: `build_planning_oracle`, `FollowerLP`,
  `BendersMaster`, `build_shared_transmission` — the guard registry's coverage set.
- The "never THE equilibrium" reporting language (Phase 13's structural rule) should carry into
  the Rung 7 docs page verbatim — report "a converged equilibrium (spread: …)".
- Golden regression must remain meaningful under the documented CairoMakie-weakdep broken-test
  skips; the goldens file must not depend on plotting.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PVAL-02 | Canonical single- and multi-distributor fixtures are pinned as computed goldens, gated by BilevelJuMP agreement and diagonalization convergence (no external numerical reference exists). | Exact N=1 golden values (`z*=0.7`, `cost=-0.245`) and N=2 golden values (`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`) verified from `test/test_planning_certification.jl` and `test/test_planning_nash.jl`; `fixtures_phase4.jl`/`test_acceptance.jl` computed-golden convention identified as the template to follow; Open Question 2 flags the probe-spread pin-vs-bound decision. |
| PVAL-03 | Literate Documenter documentation maps the planning math (PSR problem numbers, coupling seam, the interpretive leader/follower choice) to the code, `@example`-executed. | Verified (by running the actual build) that the Documenter pipeline is currently BROKEN due to 33 orphaned planning docstrings — this is the actual prerequisite work, not just adding 2 pages. Concrete `docs/make.jl`/`api.md` diffs provided, including the `Order = [:type, :constant, :function]` fix required for `RETRYABLE_STATUSES`. Anti-pattern section resolves the BilevelJuMP-in-docs architecture question. |
| PVAL-04 | An automated no-binaries guard on every planning-layer subproblem builder enforces the continuous-only scope of this milestone. | All 4 builder signatures (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`) verified with minimal-fixture invocations; existing partial (SharedTransmission-only) guard implementations identified in `test_planning_coupling.jl`/`test_planning_nash.jl`; a concrete consolidated-registry + source-scan-tripwire implementation pattern provided in Architecture Patterns. |
</phase_requirements>

## Summary

This phase does not add new optimization code — it hardens what Phases 10-13 already built. Three
independent, verifiable pieces of infrastructure are missing: (1) the two one-off validation
results (BilevelJuMP N=1 certification, hand-checked N=2 Nash equilibrium) are pinned as hardcoded
regression values today only inside `test_planning_certification.jl`/`test_planning_nash.jl`, not
as a dedicated goldens file gated the way `test_acceptance.jl`/`fixtures_phase4.jl` gate the v1.0
operational goldens; (2) **the Documenter build is currently BROKEN** — verified by directly
running `julia --project=docs docs/make.jl` in this session: it fails with
`ERROR: LoadError: makedocs encountered an error [:missing_docs]` because 33 exported planning-layer
docstrings (all of `src/planning/*.jl`) have never been added to any `@autodocs`/`@docs` block, so
`checkdocs = :exports` fails the build; (3) a no-binaries guard exists today for only ONE of the
four planning-layer builders (`SharedTransmission`, duplicated across two test files) — `PlanningOracle`,
`FollowerLP`, and `BendersMaster` have no such regression at all.

**Primary recommendation:** Treat the broken docs build as a P0 prerequisite of PVAL-03 — add a new
`## Planning Layer` `@autodocs` section to `docs/src/api.md` covering all nine `src/planning/*.jl`
files (including `Order = [:type, :constant, :function]`, not the existing pages' `[:type, :function]`,
because `RETRYABLE_STATUSES` is a `const`) BEFORE or alongside adding the two new Literate rung pages.
Consolidate the no-binaries guard into one `@testitem` with an explicit 4-builder registry
(`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`) plus a
source-scanning tripwire that greps `src/planning/*.jl` for `function build_\w+\(` and asserts the
result set equals the registry. Pin both goldens (N=1: `z*=0.7`, `cost=-0.245`; N=2:
`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`) in a new `test/fixtures_planning.jl` matching the
`fixtures_phase4.jl` "COMPUTED golden, commented" convention, gated by the existing certification/
convergence assertions re-run first, values second.

## Architectural Responsibility Map

This project has no browser/frontend/API tiers; the relevant "tiers" are the project's own toolchain
stages.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Golden fixture pinning (PVAL-02) | Test Suite (TestItemRunner, `test/`) | Source (`src/planning/*.jl` builders, unmodified) | Goldens are regression data living in test/, asserted against unmodified production entry points. |
| No-binaries guard (PVAL-04) | Test Suite (semantic `@testitem`) | Source (`src/planning/*.jl` file listing, for the tripwire) | Guard is test-only per CONTEXT.md (no runtime `assert_continuous!`); the tripwire must read the Source tier's file list to detect drift. |
| Literate math docs (PVAL-03) | Documentation Build (`docs/literate/*.jl` -> Documenter `@example`) | Source (`src/planning/*.jl` docstrings, surfaced via `api.md`) | Docs pages execute real code (Documentation Build) but the underlying math/API docstrings live at the Source tier and must be wired into the same build. |
| CI gating (regression suite + docs build) | CI (`.github/workflows/*.yml`) | Test Suite / Documentation Build | CI is two SEPARATE jobs today (`test` and `docs`) — the goldens gate belongs in `test`, never in `docs` (CONTEXT.md locked). |

## Standard Stack

No new packages are introduced by this phase. Every dependency needed is already pinned and
installed.

### Core (already present, reused as-is)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Documenter.jl | 1.17.0 [VERIFIED: ran `julia --project=docs docs/make.jl`, confirmed `Documenter/AXNMp` on disk] | Docs build, `checkdocs = :exports` enforcement | Already the project's docs engine (Phase 1/9). |
| Literate.jl | 2.21.0 [CITED: docs/Project.toml `[compat]`] | `.jl` -> Documenter markdown | Existing rung-ladder convention (6 pages already). |
| TestItemRunner.jl / TestItems.jl | pinned per root CLAUDE.md (1.1.5 / 1.0.0) [ASSUMED — not re-verified this session, unchanged since Phase 1] | Test discovery/execution | Existing `@testitem`/`@testmodule` convention across all of `test/`. |
| BilevelJuMP.jl | `= 0.6.3` [VERIFIED: `test/Project.toml` `[compat]` exact pin] | N=1 certification oracle, test-only | Already installed and exercised by Phase 11's `test_planning_certification.jl`; PVAL-02/PVAL-04 reuse it, do not add a new dependency. |
| HiGHS.jl / Ipopt.jl | `= 1.24.1` / `= 1.15.0` [VERIFIED: `test/Project.toml` `[compat]` exact pins] | BilevelJuMP's bare-constructor requirement (test-only, INFRA-02 documented exception) | Same exception already documented in `test_planning_certification.jl`'s header comment. |

### Package Legitimacy Audit

**Not applicable — no new packages are installed by this phase.** All packages referenced above are
pre-existing, already-vetted dependencies (BilevelJuMP/HiGHS/Ipopt exact-pinned since plan 11-03;
Documenter/Literate since Phase 1/9). The Package Legitimacy Gate protocol is scoped to *new*
installs; skip slopcheck/registry verification here and flag any *actual new* package the planner
introduces (none expected) for a follow-up audit.

**Packages removed due to slopcheck [SLOP] verdict:** none (N/A — no new packages)
**Packages flagged as suspicious [SUS]:** none (N/A — no new packages)

## Architecture Patterns

### Docs build data flow (verified this session)

```
docs/literate/*.jl (Literate source, "using TSODSO" only)
        │  Literate.markdown(..., flavor=DocumenterFlavor())
        ▼
docs/src/generated/*.md  (@example blocks still LIVE Julia code)
        │
        ▼
makedocs(modules=[TSODSO], pages=[...], checkdocs=:exports, warnonly=[:cross_references])
        │
        ├─ SetupBuildDirectory → Doctest (executes every @example) → ExpandTemplates
        ├─ CrossReferences (warnonly — broken @ref never fails the build)
        └─ CheckDocument  ◄── HARD GATE: every EXPORTED symbol's docstring must be
                              surfaced by SOME @docs/@autodocs block in the `pages` tree.
                              Currently FAILS (33 planning-layer docstrings orphaned).
```

**Verified fact, not assumed:** running `julia --project=docs docs/make.jl` in this repository's
current state (Phase 13 complete, Phase 14 not yet started) terminates with:

```
ERROR: LoadError: `makedocs` encountered an error [:missing_docs] -- terminating build before rendering.
```

listing exactly 33 orphaned docstrings, one per exported symbol across every file in
`src/planning/` (`PlanningOracle`, `build_planning_oracle`, `solve_planning_oracle!`, `FollowerLP`,
`build_follower`, `solve_follower!` (both methods), `BendersMaster`, `build_master`,
`add_optimality_cut!`, `add_feasibility_cut!`, `solve_master!`, `solve_stackelberg!`,
`SharedTransmission`, `build_shared_transmission`, `activate_distributor!`, `update_coupling!`,
`write_back!`, `DistributorView`, `NashTrace`, `run_nash!`, `run_nash_probe`, `BendersTrace`,
`is_converged` (both methods), `trace_summary` (both methods), `solve_with_retry!`,
`RETRYABLE_STATUSES`, `checkpoint_iteration!`, `resume_from_checkpoint`). `docs/src/api.md` has
**no** "Planning" section at all today — grep confirms zero occurrences of "planning" anywhere
under `docs/src/`. `plot_nash_convergence` (in `src/diagnostics/plots.jl`) is the ONE planning-adjacent
export already covered, because it lives on the existing "Diagnostics" `@autodocs` page.

**Why this matters for planning this phase:** PVAL-03's own content contract (two new Literate
pages) is necessary but NOT sufficient to make the docs build pass again. A plan that only adds the
two new Literate pages, without also adding a "Planning" `@autodocs` section enumerating all nine
`src/planning/*.jl` files, will still fail `makedocs` on the pre-existing orphaned docstrings —
this is not new breakage the two Literate pages would introduce, but a standing defect from Phases
10-13 that this phase is the first opportunity to fix (docs CI has presumably been red or unrun
since Phase 10 merged; nothing in Phase 10-13's own scope touched `docs/`).

**Required `Order` fix, verified:** every existing `@autodocs` block in `api.md` uses
`Order = [:type, :function]`. `RETRYABLE_STATUSES` (`src/planning/retry.jl`) is a top-level `const
RETRYABLE_STATUSES = (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS, MOI.ALMOST_OPTIMAL, ...)` — Documenter
category `:constant`. Copying the existing `Order = [:type, :function]` verbatim into a new
"Planning Layer" section will silently leave `RETRYABLE_STATUSES` orphaned and the build will still
fail. The new section needs `Order = [:type, :constant, :function]` (or an explicit `@docs`
block for just this one constant).

### Recommended docs/make.jl addition

```julia
# New Literate sources (append to the existing tuple, same loop, same flavor):
for src in (
    "toy_dc.jl", "lindistflow.jl", "convex_branch_flow.jl",
    "prosumer_welfare.jl", "pricing_dlmp.jl", "admm.jl",
    "stackelberg_benders.jl",   # NEW: Rung 6
    "nash_diagonalization.jl",  # NEW: Rung 7
)
    Literate.markdown(joinpath(LITERATE_DIR, src), GENERATED_DIR; flavor = Literate.DocumenterFlavor())
end
```

```julia
# pages tree: new "Planning" subsection alongside "Models"
"Planning" => [
    "Rung 6: Stackelberg-Benders" => "generated/stackelberg_benders.md",
    "Rung 7: Nash Diagonalization & Shared Corridor" => "generated/nash_diagonalization.md",
],
```

```markdown
<!-- docs/src/api.md: NEW section, note the Order difference from every existing section -->
## Planning Layer

\`\`\`@autodocs
Modules = [TSODSO]
Pages = [
    "planning/retry.jl",
    "planning/checkpoint.jl",
    "planning/trace.jl",
    "planning/subproblem.jl",
    "planning/follower.jl",
    "planning/master.jl",
    "planning/benders.jl",
    "planning/coupling.jl",
    "planning/nash.jl",
]
Order = [:type, :constant, :function]
\`\`\`
```

### Pattern: Literate rung page, `using TSODSO` only, no direct solver imports

**What:** Every existing `docs/literate/*.jl` page does `using TSODSO` (sometimes plus `using
TSODSO: Bus, Branch, Feeder` for constructing a toy feeder inline) and NEVER imports HiGHS/Clarabel/
Ipopt directly — the solver factory (`select_optimizer`) resolves transitively through `TSODSO`'s
own `Project.toml` deps, which `docs/Manifest.toml` already pulls in as part of resolving `TSODSO`
itself.
**Verified:** the just-executed docs build compiled and ran `solve_admm`/`solve_welfare` (which
internally call Clarabel/HiGHS) inside `docs/literate/admm.jl`'s `@example` blocks with zero
solver-related errors — `docs/Project.toml` needs no direct HiGHS/Clarabel entry for this.
**When to use:** Rung 6 and Rung 7 pages should follow this pattern exactly — call
`build_planning_oracle`/`solve_stackelberg!`/`build_shared_transmission`/`run_nash!` through
`using TSODSO` only.
**Example:**
```julia
# Source: docs/literate/admm.jl (existing convention, lines 48-49)
using TSODSO
using TSODSO: Bus, Branch, Feeder
```

### Anti-Pattern to Avoid: executing BilevelJuMP live inside the docs build

CONTEXT.md's content contract for Rung 6 requires narrating "the interpretive leader/follower choice
INCLUDING the Phase 11 empirical certification story (StrongDualityMode/ProductMode/hand
enumeration/production Benders 4-way agreement)". This does NOT require literally re-executing
`BilevelModel(...)`/`optimize!` inside a docs `@example` block. Doing so would require adding
BilevelJuMP + HiGHS + Ipopt as new **direct** `docs/Project.toml` dependencies (today `docs/Project.toml`
has only `CairoMakie`, `Documenter`, `Literate`, `TSODSO`) and re-resolving the committed, Julia-
1.12.5-pinned `docs/Manifest.toml`. It would also blur CLAUDE.md's explicit "BilevelJuMP as a
validation-oracle-only, test-only dependency (never imported by src/)" boundary — the docs site is
published, user-facing content, not a test artifact, and `test_planning_certification.jl`'s own
header comment states BilevelJuMP is imported ONLY there and in `ext/TSODSOGurobiExt.jl`'s sibling
exception. **Recommendation:** Rung 6's `@example` block should execute ONLY `solve_stackelberg!`
(already a `TSODSO` export, no new dependency) to reproduce `z*≈0.7`/`cost≈-0.245` live, and narrate
the BilevelJuMP cross-certification as prose/a markdown table citing the pinned golden and
`test/test_planning_certification.jl` by name — never as executed docs code. This is a genuinely
open architectural decision (not dictated by CONTEXT.md, which left "exact Literate page prose
structure" to Claude's discretion) — flag it explicitly to the planner rather than silently picking
one path.

### Recommended no-binaries guard shape (`test/test_planning_noninteger.jl`, new file)

```julia
# Registry: every planning-layer builder that returns a JuMP Model, paired with a
# CHEAP fixture invocation. Mirrors the existing per-builder checks already scattered
# across test_planning_coupling.jl / test_planning_nash.jl (SharedTransmission only) —
# this file CONSOLIDATES + extends to the other three builders.
@testitem "planning PVAL-04: no-binaries guard covers all four planning-layer builders" tags = [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: all_variables, is_binary, is_integer

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])

    registry = Dict(
        "build_planning_oracle" => () -> build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = [4.0], T = 1).model,
        "build_follower" => () -> build_follower(; T = 1, corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5]).model,
        "build_master" => () -> build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0).model,
        "build_shared_transmission" => () -> build_shared_transmission(;
            N = 2, T = 1, corridor_cap = 2.0, x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0], c_op = [[0.5], [0.5]]).model,
    )

    for (name, build) in registry
        model = build()
        offenders = [v for v in all_variables(model) if is_binary(v) || is_integer(v)]
        @test isempty(offenders) # fail-loud message should name `name` and `offenders` on failure
    end

    # Tripwire: every `function build_\w+\(` in src/planning/*.jl must be in `registry`
    # (naming convention already 100% consistent across the four existing builders).
    planning_dir = joinpath(pkgdir(TSODSO), "src", "planning")
    found = Set{String}()
    for f in readdir(planning_dir; join = true)
        endswith(f, ".jl") || continue
        for line in eachline(f)
            m = match(r"^function (build_\w+)\(", line)
            m !== nothing && push!(found, m.captures[1])
        end
    end
    @test found == Set(keys(registry))
end
```

This directly answers the research question "how to introspect a built JuMP model for binary/
integer variables": `JuMP.is_binary`/`JuMP.is_integer` over `JuMP.all_variables(model)`, EXACTLY the
idiom already used (twice, for `SharedTransmission` only) in `test_planning_coupling.jl` and
`test_planning_nash.jl` — no new API surface needed. `build_planning_oracle` needs a `feeder`+
`pf`+`aggregators` (the only "heavier" builder among the four, but the existing `Phase6Fixtures.
two_bus_feeder()` + `ToyElasticDevice` toy fixture — already used in `test_planning_certification.jl`
— is a single-bus, single-hour, sub-millisecond LP; cheap). `build_follower`, `build_master`, and
`build_shared_transmission` are all standalone LPs with no feeder dependency, cheaper still. The
tripwire's `readdir` + regex approach is a pure-Julia, zero-new-dependency way to detect a future
builder file/function the registry doesn't cover — verified the naming convention
(`function build_\w+\(`) is consistent across all four current builders via direct grep this
session.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting binary/integer JuMP variables | A custom AST/string scan of model-building code | `JuMP.is_binary(v)`/`JuMP.is_integer(v)` over `JuMP.all_variables(model)` | Already the project's own idiom (2 existing occurrences); semantically correct regardless of HOW a variable was declared (`Bin`, `Int`, or a later `set_binary!` mutation) — a source-text grep would miss the latter. |
| Docstring-coverage enforcement | A custom script scanning `src/` for undocumented exports | Documenter's own `checkdocs = :exports` (already wired) | Already enabled and already catching real gaps (33 orphaned docstrings, verified this session) — the missing piece is CONTENT (the `@autodocs` Pages list), not a new enforcement mechanism. |
| Golden-value storage | A YAML/JSON fixture file + a custom loader | Plain Julia `const` literals in `test/fixtures_planningXXX.jl`, matching `fixtures_phase4.jl`'s "COMPUTED golden, commented" convention | Zero new dependency, consistent with every prior phase's fixture file, diff-reviewable in code review. |

**Key insight:** every piece PVAL-02/03/04 needs is either (a) a data file in the exact shape of an
existing convention, or (b) a config-only addition (an `@autodocs` Pages list entry) to an
enforcement mechanism ALREADY installed and already working correctly (it just caught real gaps).
There is no new tooling to hand-roll here — the risk in this phase is entirely about *completeness*
of wiring, not about picking or building new mechanisms.

## Common Pitfalls

### Pitfall 1: Assuming the docs build is currently green
**What goes wrong:** A plan that scopes PVAL-03 as "add two Literate pages" and stops there will
still fail CI's `docs` job, because the build was ALREADY broken before this phase (33 orphaned
planning docstrings, verified this session) — the plan will look complete but CI will redden on a
defect this phase did not (directly) cause but is positioned to fix.
**Why it happens:** `test`/`format`/`docs` are three SEPARATE GitHub Actions jobs; Phases 10-13
never touched `docs/`, so nobody has run `julia --project=docs docs/make.jl` since before Phase 10,
and a red `docs` job on a non-`main`-blocking check is easy to miss.
**How to avoid:** Make "docs build passes (`checkdocs=:exports` green)" an explicit phase-level
verification step, not just "two new pages render". Run `julia --project=docs docs/make.jl` locally
before considering PVAL-03 done.
**Warning signs:** `ERROR: LoadError: makedocs encountered an error [:missing_docs]` with a list of
orphaned docstrings.

### Pitfall 2: Copying `Order = [:type, :function]` verbatim for the new Planning `@autodocs` section
**What goes wrong:** `RETRYABLE_STATUSES` (a `const`) is silently excluded, and `checkdocs` still
fails after the Planning section is added, misleadingly suggesting the fix didn't work.
**Why it happens:** Every existing `api.md` section happens to have no top-level constants, so
`Order = [:type, :function]` has never needed a `:constant` entry before. `src/planning/retry.jl` is
the first file in the whole project to export a `const`.
**How to avoid:** Use `Order = [:type, :constant, :function]` for the new Planning section (or add
a standalone `@docs` block for `RETRYABLE_STATUSES`).
**Warning signs:** `checkdocs` reports exactly one remaining orphaned docstring after the rest are
fixed, naming `TSODSO.RETRYABLE_STATUSES`.

### Pitfall 3: Executing BilevelJuMP inside docs `@example` blocks
See "Anti-Pattern to Avoid" above. **Warning sign:** a new `docs/Project.toml` diff adding
BilevelJuMP/HiGHS/Ipopt as direct (non-`TSODSO`-transitive) deps, or a docs build that takes
noticeably longer / becomes flaky due to an Ipopt MPEC solve running on every CI docs build.

### Pitfall 4: TestItemRunner cross-worktree test discovery (documented, Phase 13)
**What goes wrong:** running the bare `@run_package_tests` macro (or `TestItemRunner` invoked via
`-e` inline code) from inside a git worktree can scan a SIBLING worktree's test files too, because
the macro's scan path resolves relative to `dirname(__source__.file)`, which for `-e` code resolves
to the shared `.claude/worktrees/` parent directory.
**How to avoid:** call `TestItemRunner.run_tests(<explicit absolute test directory path>;
filter=...)` directly, never the bare macro, when verifying from a worktree — exactly the workaround
already used and documented in `13-02-SUMMARY.md`/`13-03-SUMMARY.md`.
**Warning signs:** test counts or failures from files that don't exist in the current worktree's
`test/` directory.

### Pitfall 5: The root `Project.toml`'s uncommitted CairoMakie promotion
**What goes wrong:** `git status` at research time shows `Project.toml` (root) and
`Manifest-v1.12.toml` as MODIFIED, UNCOMMITTED. `git diff` confirms `CairoMakie` has been moved from
`[weakdeps]` (committed state, alongside `Gurobi`/`MosekTools`) into `[deps]` (working-tree-only
state) — i.e., in the current working tree CairoMakie is a HARD dependency of the main package,
contradicting the documented weakdep/extension convention (`TSODSOMakieExt` in `[extensions]`) and
the multiple existing tests (`test_diagnostics_plot.jl`, `test_planning_nash.jl`'s
`plot_nash_convergence` item) that branch on `Base.find_package("CairoMakie") === nothing` to decide
whether to `@test_skip`. With CairoMakie hard-installed, that branch always resolves to "installed",
silently changing which code path those tests exercise versus what was validated when they were
written.
**Why it happens:** Likely leftover, uncommitted local experimentation from a prior session (e.g.
manually promoting CairoMakie to test the `TSODSOMakieExt` path in a subprocess) that was never
reverted.
**How to avoid:** Before starting Phase 14 work (which touches both `test/` and `docs/`, both
sensitive to this exact weakdep boundary), either revert the uncommitted root `Project.toml`/
`Manifest-v1.12.toml` diff to restore CairoMakie as a weakdep, or — if the promotion is actually
intended as a permanent change — make that an explicit, separate, reviewed decision BEFORE Phase 14
plans build on top of an ambiguous dependency shape. Do not let Phase 14 plans silently commit on
top of this diff without addressing it.
**Warning signs:** `git status` showing `Project.toml`/`Manifest-v1.12.toml` modified with no
corresponding phase attributing the change; CairoMakie-conditional tests behaving differently than
their own `@test_skip`/`@info` messages describe.

## Code Examples

### Reading pinned N=1 goldens (verified values, from `test/test_planning_certification.jl`)
```julia
# Source: test/test_planning_certification.jl (BilevelCertFixture), lines 72-74
const Y_HAND = 0.7
const Z_HAND = 0.7
const OBJ_HAND = -0.245
```
Also independently reproduced by the production Benders loop in the same file (`result.y`,
`result.z[1]`, `result.UB` all match `Y_HAND`/`Z_HAND`/`OBJ_HAND` within `atol = 1e-3`).

### Reading pinned N=2 goldens (verified values, from `test/test_planning_nash.jl`)
```julia
# Source: test/test_planning_nash.jl, testitem "planning nash: N=2 Gauss-Seidel converges..."
# result = run_nash!(specs, shared; z0 = zeros(2, 1), tol_outer = 1e-4, max_sweeps = 50, ...)
@test result.converged
@test isapprox(result.z, [0.6, 0.6]; atol = 1e-3)
@test isapprox(result.x_inv, [0.3, 0.3]; atol = 1e-3)
```
The hand-derivation is documented in the same file's header comment (lines 242-255): symmetric
fixed point at pooled capacity `corridor_cap*(x_inv_1+x_inv_2) = 2.0*(0.3+0.3) = 1.2`, so
`z_1 = z_2 = 0.6` binds below each distributor's unconstrained optimum `z*=0.7`.

### `run_nash_probe` return shape (for a probe-spread golden, if CONTEXT.md's discretion picks a
### value rather than a bound)
```julia
# Source: test/test_planning_nash.jl, testitem "...N=2 gating probe..."
result = run_nash_probe(specs, build_shared; seeds = seeds, orders = orders, tol_outer = 1e-4, max_sweeps = 50, checkpoint_dir = mktempdir())
result.n_runs        # == 6 (3 seeds x 2 orders)
result.runs           # Vector of per-run results, each with .result.converged
result.summary        # String, must contain "a converged equilibrium", never "the equilibrium"
result.spread.z_spread, result.spread.x_inv_spread, result.spread.cost_spread  # >= 0, finite
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| PVAL-01's certification lives only in `test_planning_certification.jl`, no dedicated goldens module | PVAL-02 adds `test/fixtures_planning.jl` alongside it, cross-referenced | Phase 14 (this phase) | Matches the v1.0 pattern (`fixtures_phase4.jl` -> `test_acceptance.jl`) where a dedicated fixtures file backs a "pinned computed golden regression" testitem. |
| No-binaries checks scattered/duplicated (SharedTransmission only, in 2 files) | A single consolidated `@testitem` with an explicit 4-builder registry + source-scan tripwire | Phase 14 (this phase) | Removes duplication (`test_planning_coupling.jl` and `test_planning_nash.jl` both currently assert the identical SharedTransmission-only check) and closes the gap for the other 3 builders. |

**Deprecated/outdated:** none — no library APIs changed; this is entirely internal-convention
hardening.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | TestItemRunner/TestItems exact versions (1.1.5/1.0.0) are unchanged since Phase 1 | Standard Stack | Low — not re-verified this session via `Pkg.status`, but no phase has touched this dependency; if wrong, only affects a version-number citation, not the plan's logic. |
| A2 | The "Claude's Discretion" prose-structure choice to narrate (not execute) BilevelJuMP in Rung 6 is the right tradeoff | Anti-Pattern to Avoid / Architecture Patterns | Medium — this is a genuine content/architecture decision CONTEXT.md leaves open; if the user actually wants the certification story LIVE-EXECUTED in docs, the plan needs a different (heavier) docs dependency path. Flagged explicitly for planner/user confirmation, not silently decided. |

**If empty:** N/A — see table above; both entries are low-to-medium risk and explicitly flagged.

## Open Questions (RESOLVED)

1. **Should Rung 6's docs page execute BilevelJuMP live, or only narrate it?**
   - RESOLVED: narrate only — encoded as a locked decision in 14-03-PLAN.md (BilevelJuMP
     certification story appears as prose citing test/test_planning_certification.jl; no new
     docs dependency; not open for re-litigation by the executor).
   - What we know: CONTEXT.md requires the certification STORY to appear; it does not say "executed
     live". `docs/Project.toml` today has zero BilevelJuMP/HiGHS/Ipopt-as-docs-deps; adding them
     means a new docs/Manifest.toml resolve (Julia 1.12.5-pinned) and a slower, Ipopt-MPEC-solving
     CI docs build.
   - What's unclear: whether "traceability to the actual code" (PVAL-03's stated goal) is satisfied
     by a prose/table narration citing the test file, or requires the docs reader to see the MPEC
     solve happen.
   - Recommendation: narrate only (see Anti-Pattern section); this is explicitly a planner/discuss
     decision point, not something this research resolves unilaterally.

2. **Does the N=2 golden pin the exact probe spread value, or a bound on it?**
   - What we know: CONTEXT.md explicitly defers this to Claude's Discretion ("pick whichever is
     robust to solver noise, with rationale documented"). `run_nash_probe`'s spread fields
     (`z_spread`, `x_inv_spread`, `cost_spread`) are all asserted `>= 0.0 && isfinite(...)` in the
     existing Phase 13 test, never pinned to an exact value today.
   - What's unclear: how numerically stable the exact spread value is across HiGHS versions/BLAS
     versions on this tiny toy fixture (the CI matrix runs Julia 1.10/1.11/1.12).
   - RESOLVED: pin a loose upper bound — encoded in 14-01-PLAN.md (probe-spread golden asserts
     an empirically-derived loose upper bound, with rationale comment).
   - Recommendation: pin a LOOSE UPPER BOUND on the spread (e.g. `z_spread < 0.05`) rather than an
     exact value with a tight tolerance — the equilibrium POINT (`z=[0.6,0.6]`) is the hand-derived,
     stable quantity; the spread across seeds/orders is inherently a solver-numerics-sensitive
     diagnostic, not a closed-form invariant.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 [VERIFIED: `julia --version` this session] | — |
| `docs/Manifest.toml` (committed, pre-instantiated) | Docs build | ✓ | resolved for Julia 1.12.5 [VERIFIED: build ran without an instantiate step] | — |
| BilevelJuMP/HiGHS/Ipopt (test env) | PVAL-01 retention, PVAL-02 gate | ✓ | pinned exact in `test/Project.toml` [VERIFIED: file read] | — |
| GitHub Actions `docs` job | CI enforcement of the fixed build | — (not run locally, only inferred from `.github/workflows/*.yml`) | timeout-minutes: 30, Julia 1.12 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — everything the phase needs is already installed and
version-pinned; the work is wiring, not procurement.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItemRunner.jl (`@testitem`/`@testmodule`), invoked via `Pkg.test()` / `test/runtests.jl`'s `@run_package_tests` |
| Config file | `test/Project.toml` (deps + `[compat]`); no separate test-framework config file |
| Quick run command | `julia --project=test -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter=ti->occursin("planning", lowercase(ti.name)))'` (mirrors the Phase 13 documented worktree-safe workaround — NEVER the bare `@run_package_tests` macro from a worktree, Pitfall 4 above) |
| Full suite command | `Pkg.test("TSODSO")` (root project) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PVAL-02 | N=1/N=2 goldens gated by certification/convergence, values pinned | unit/regression | `TestItemRunner.run_tests(...; filter=ti->occursin("planning goldens", ti.name))` | ❌ Wave 0 (`test/fixtures_planning.jl`, `test/test_planning_goldens.jl` both new) |
| PVAL-03 | Docs build green with 2 new pages + full planning docstring coverage | build/manual | `julia --project=docs docs/make.jl` (must exit 0) | ❌ Wave 0 (`docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl`, `docs/src/api.md` Planning section all new/modified) |
| PVAL-04 | No binary/integer variable in any planning-layer builder's model | unit/regression | `TestItemRunner.run_tests(...; filter=ti->occursin("no-binaries guard", ti.name))` | ❌ Wave 0 (`test/test_planning_noninteger.jl` new — consolidates the 2 existing partial `SharedTransmission`-only checks) |

### Sampling Rate
- **Per task commit:** quick run command above, filtered to `[:planning]`-tagged items (existing
  convention; all new files should carry `tags = [:planning]`).
- **Per wave merge:** `Pkg.test("TSODSO")` (full suite) AND `julia --project=docs docs/make.jl`
  (docs build — NOT part of `Pkg.test`, per CONTEXT.md's explicit "docs build stays OUT of
  `Pkg.test`" decision; must be run and gated separately).
- **Phase gate:** both the full test suite AND the docs build green before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/fixtures_planning.jl` — new `@testmodule` (or plain file, matching `fixtures_phase4.jl`'s
  non-testmodule constant-only convention) holding the N=1/N=2 pinned goldens.
- [ ] `test/test_planning_goldens.jl` — new file, default-on in the same `Pkg.test` gate; re-asserts
  the BilevelJuMP/diagonalization GATE first, then the pinned-value regression.
- [ ] `test/test_planning_noninteger.jl` — new file, consolidated 4-builder no-binaries guard +
  source-scan tripwire (see Code Examples above). Consider removing the now-duplicated
  `SharedTransmission`-only checks from `test_planning_coupling.jl`/`test_planning_nash.jl` in favor
  of this single consolidated file, OR leave them as harmless redundant coverage — planner's call.
- [ ] `docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl` — new Literate
  sources.
- [ ] `docs/src/api.md` — new "Planning Layer" `@autodocs` section (the actual prerequisite fix for
  the currently-broken build).
- [ ] `docs/make.jl` — wire the 2 new Literate sources into the `for src in (...)` loop and the
  `pages` tree's new "Planning" subsection.
- Framework install: none — everything is already installed (see Environment Availability).

## Security Domain

This is a research optimization framework with no network-facing surface, no authentication, and no
user data; the project has never adopted OWASP ASVS (its own `T-XX-YY` threat-numbering convention
in code comments covers numerical/reproducibility threats instead, e.g. `T-04-08`, `T-09-05`,
`T-01-09` referenced throughout `docs/make.jl`/test files). Most ASVS categories do not apply.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — no network-facing service |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes (narrow) | The project's own `ArgumentError`-on-boundary-guard convention, already used consistently in every `build_*` function (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission` all guard shape/positivity before any `@variable`/`@objective` assembly) — new test/docs code in this phase should not introduce a bypass. |
| V6 Cryptography | no | N/A |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent drift between a documented docs page's rendered numbers and the actual `src/` code | Tampering (of the "trusted" doc artifact) | `@example`-executed Literate blocks (already the project's own convention, T-01-09/T-09-03) — never hardcode a number in a docs page. |
| A future planning-layer builder silently introduces a binary/integer variable, breaking the continuous-only v2.0 scope (PLAN-INT-01 is explicitly deferred) | Tampering (of the modeling assumption the Benders/diagonalization math depends on) | The consolidated no-binaries guard + tripwire (this phase's PVAL-04 deliverable) — a semantic JuMP-introspection check, not a grep lint, so it survives refactors that keep the same file names but change how a variable is declared. |
| Supply-chain: a new test/docs dependency introduced without an exact `[compat]` pin | Tampering/Repudiation (of the dependency graph) | Already the project's convention since plan 11-03 (`= 0.6.3` style exact pins for BilevelJuMP/HiGHS/Ipopt in `test/Project.toml`) — carry the same discipline if any NEW dependency is added (none expected this phase). |

## Sources

### Primary (HIGH confidence — verified by direct execution this session)
- `julia --project=docs docs/make.jl` (this session) — confirmed the docs build currently fails
  with `[:missing_docs]`, listing all 33 orphaned planning-layer docstrings; confirmed `Documenter`
  installed at path `~/.julia/packages/Documenter/AXNMp/` (build ran without an instantiate step).
- Direct `Read`/`grep` of `src/planning/{retry,checkpoint,trace,subproblem,follower,master,benders,
  coupling,nash}.jl` — confirmed every `export` statement and every `struct`/`function build_*`
  signature cited above.
- Direct `Read` of `test/test_planning_certification.jl` and `test/test_planning_nash.jl` — confirmed
  the exact N=1 (`z*=0.7`, `cost=-0.245`) and N=2 (`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`) golden values,
  and the existing (partial, SharedTransmission-only) no-binaries checks.
- Direct `Read` of `docs/make.jl`, `docs/Project.toml`, `docs/src/api.md`, all `docs/literate/*.jl` —
  confirmed the Literate/Documenter pipeline shape, the `using TSODSO`-only import convention, and
  the absence of any "Planning" section in `api.md`.
- `git diff Project.toml` (this session) — confirmed the uncommitted CairoMakie weakdep-to-hard-dep
  promotion in the working tree.
- `grep -rn "Bin)\|, Int)\|Integer)" src/` (this session) — confirmed zero binary/integer JuMP
  variable declarations exist anywhere in `src/` today (the guard is protecting a currently-true
  invariant).

### Secondary (MEDIUM confidence)
- `.github/workflows/*.yml` (read directly, not executed this session) — the `docs` job's
  Julia-1.12-pin and 30-minute timeout, and that `test`/`format`/`docs` are three independent jobs.

### Tertiary (LOW confidence)
- TestItemRunner/TestItems exact version numbers (1.1.5/1.0.0) — cited from root `CLAUDE.md`, not
  re-verified against `test/Manifest.toml` this session (see Assumption A1).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all cited versions are either directly read from
  `[compat]` blocks or verified by running the actual build.
- Architecture: HIGH — the broken-docs-build finding and the no-binaries-guard gap were both
  independently reproduced this session, not inferred.
- Pitfalls: HIGH — all five pitfalls are either directly reproduced (docs build failure, CairoMakie
  diff) or drawn verbatim from this project's own Phase 13 postmortems (TestItemRunner
  cross-worktree gotcha).

**Research date:** 2026-07-24
**Valid until:** 30 days (stable internal-convention work; re-verify if `main` advances past Phase 14
before planning starts, since the working-tree CairoMakie diff (Pitfall 5) may be resolved or
changed by then).
