# Phase 9: Documentation & Regression Acceptance Gate - Research

**Researched:** 2026-07-20
**Domain:** Julia scientific-documentation tooling (Documenter.jl + Literate.jl) and
TestItemRunner-based regression/acceptance testing
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Literate Documentation Scope (EXP-03)
- One literate page per rung of the abstraction ladder — extend the existing `docs/literate/toy_dc.jl`
  pattern with pages for: LinDistFlow (linear branch flow), SOCP Convex Branch-Flow + exactness,
  Prosumer devices + GLB-CVX social-welfare solve, DADP/DLMP decomposition, and ADMM (~5–6 new pages).
- Math rendered as KaTeX equations inline, each citing the thesis equation number (e.g. "(3.31)",
  "(3.39)", "(3.43–3.45)") beside the corresponding code — per the CLAUDE.md hard requirement that
  every model's equations sit next to the code.
- Numbers in docs come from real `@example` solves executed during `makedocs` (rendered numbers
  cannot drift from the code), extending the toy_dc `documenter = true` pattern.
- Each page follows the structure: math → assumptions → validation (exactness check `l·v ≈ P²+Q²`,
  dual/price recovery, ADMM-vs-centralized), so every modeling decision is documented with its math.

#### v1 Acceptance Gate (SC3)
- Form: a dedicated `test/test_acceptance.jl` @testitem that runs both headline cases end-to-end —
  IEEE-13 congestion and IEEE-123 voltage — asserting exact relaxation + recovered DADP + ADMM ≈
  centralized optimum in one place.
- Tolerances: reuse the already-pinned per-phase tolerances (exactness ~1e-6…1e-9, ADMM-vs-centralized
  welfare gap ~1e-6, DADP match) — do not invent new/looser acceptance tolerances.
- Solver path: open-source only (Clarabel / HiGHS / Ipopt), matching the reproducibility requirement.
- Known welfare-headline gaps: gate on the COMPUTED goldens (the reproducibility anchors already
  accepted by the researcher in Phase 4/5). Keep the thesis +$1819 / +25% headline numbers as
  NON-FAILING, documented cross-checks. Do NOT block the gate on thesis-numeric welfare match
  (figure-digitization is a deferred TODO).

#### Regression Fixture Strategy (EXP-04)
- Keep the existing, working inline per-phase pins (1933 tests green) and ADD a consolidated
  regression/acceptance layer that references them — do not rip out working pins.
- Pin the FIT-vs-DADP comparison as a regression (extends existing `test_pricing_fit` / `test_fit`)
  on the computed golden.
- Golden storage format: inline typed constants + `rtol` (the established project convention);
  reserve the Phase-8 JLD2/CSV harness for experiment outputs, not unit-test goldens.
- Drift detection: `@test` with `rtol` on pinned constants — numerical drift is caught by the CI
  test run.

#### Docs Build & CI
- Docs build runs in CI: `makedocs` with `@example` execution is itself the docs reproducibility gate.
- Tighten `checkdocs` for public API docstrings (from `:none`), keeping `warnonly` for the remainder
  so the build stays green while surfacing missing docs.
- Wire `deploydocs` gated on the `CI` env var (never deploy from a local/worktree checkout — the
  Phase-1 `remotes = nothing` note documents why).
- Include CairoMakie figures (convergence residuals, voltage profiles, DLMP decomposition) in the
  relevant pages — weakdep-gated so the build degrades gracefully when CairoMakie isn't installed.

### Claude's Discretion
- Exact page ordering, filenames, and Documenter `pages` tree layout.
- How the consolidated acceptance/regression testitem is wired relative to the existing per-case tests.
- Whether the docs CI job is a separate workflow file or a step in the existing matrix.

### Deferred Ideas (OUT OF SCOPE)
- Thesis-figure digitization (recover exact MEM price / temperature / house-count inputs to close the
  Phase-4 welfare gap and the Phase-5 +25% headline) — documented TODO in STATE.md, NOT part of v1.
- WR-02 (Phase-8 code review): replace `sub_seed`'s `Base.hash` derivation with a cross-version-stable
  hash and re-tune ADMM ρ / battery τ defaults — researcher decision, tracked in Phase-8 deferred-items.
- IEEE-123 exact thesis App. E per-terminal impedances (current fixture uses representative in-band
  per-unit values at 1 MVA base) — documented Phase-7 follow-up.
- CairoMakie visual-aesthetic eyeball check in a non-headless env (Phase-7 deferred manual item).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXP-03 | Every model has literate, reproducible documentation stating its math (equation references), assumptions, and validation, built via Documenter + Literate. | Standard Stack, Architecture Patterns (Pattern 1/2), Code Examples, Pitfalls 1/2/4 — the exact `Literate.markdown`/`makedocs` API surface, the non-deprecated `flavor` kwarg, the `checkdocs=:exports` level, and the math→assumptions→validation page structure to replicate 5-6× from `toy_dc.jl`. |
| EXP-04 | Regression fixtures pin reference results (IEEE 13/123, FIT comparison) so numerical drift is caught. | Don't Hand-Roll (golden storage row), Architecture Pattern 3, Validation Architecture (Phase Requirements → Test Map) — confirms the existing inline-constant/`rtol` convention across 40 test files and identifies exactly which existing goldens (`test_ieee13.jl`, `test_pricing_welfare.jl` `RATIO_GOLDEN`, `test_pricing_fit.jl`) the new consolidated layer must reference, not duplicate. |
</phase_requirements>

## Summary

Phase 9 closes v1 with two additive layers over an already-complete, 1933-test-green
framework: (1) rich literate math documentation per model rung (EXP-03), and (2) a
consolidated end-to-end acceptance test plus a light regression layer (EXP-04/SC3).
Nothing here is greenfield — every number the docs render and every assertion the
acceptance gate makes must come from `src/` entrypoints that already exist and are
already exercised by per-phase tests (`operational_oracle`, `solve_welfare`,
`solve_admm`, `extract_dlmp`, `fit_baseline`, `welfare_accounting`,
`assert_socp_exact!`, `run_scenario`). The work is 100% "wire existing pieces into new
surfaces," never "build a new solve path."

The one non-trivial finding: the project's own `docs/make.jl` uses `Literate.markdown(...;
documenter = true)`, a keyword that has been **deprecated since Literate 2.9.0 (2021)**
in favor of `flavor = Literate.DocumenterFlavor()`. It still works (with a
`DeprecationWarning`) at the pinned Literate 2.21, but every new literate page this
phase adds should use the current, non-deprecated API — and fixing the existing
`toy_dc.jl` build call is a one-line, in-scope cleanup. Documenter 1.17's `checkdocs`,
`warnonly`, `doctest`, and `deploydocs`/CI-gating APIs are otherwise stable and match
what `docs/make.jl` already does; this phase mostly *extends* the existing pattern
(more Literate sources, a `pages` tree, `checkdocs` tightened from `:none`) rather than
introducing new mechanisms.

**Primary recommendation:** Extend `docs/make.jl` in place — new `Literate.markdown`
calls (using `flavor = Literate.DocumenterFlavor()`) for each of the ~5–6 new pages,
each page's `@example` blocks calling the real `src/` entrypoints (never re-implementing
math), a `pages` tree grouping them under a "Models" section, `checkdocs = :exports`
(cross-version-safe under the 1.10 floor), and a `test/test_acceptance.jl` `@testitem`
that reuses `Phase4Fixtures`/`Phase7Fixtures`-style setups to call `operational_oracle`
+ `solve_admm` + `extract_dlmp` on both headline feeders and assert the already-pinned
tolerances — no new tolerances, no new solve paths.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-model math documentation (EXP-03) | Docs build (Documenter+Literate, `docs/`) | Core library (`src/`, read-only) | Docs is a separate build target that *executes* `src/` code via `@example`; it must never fork or reimplement model logic — it is a presentation layer over the existing API. |
| Regression fixture pins (EXP-04) | Test suite (`test/`) | — | Pins live exactly where the 1933 existing pins live: inline typed constants in `@testitem`/fixture files. No new storage tier. |
| Acceptance gate (SC3) | Test suite (`test/test_acceptance.jl`) | Core library (calls `operational_oracle`/`solve_admm`/`extract_dlmp`) | The gate is pure orchestration/assertion over existing core entrypoints — it owns no new solve logic. |
| CairoMakie figures in docs | Docs build (`ext/TSODSOMakieExt.jl` consumer) | Core library (`AdmmResiduals` producer) | Figures are generated by the weakdep extension already built in Phase 7; docs pages only need to *call* `plot_convergence`/`plot_price_convergence` when CairoMakie is present, mirroring the existing `test_diagnostics_plot.jl` gating pattern. |
| CI docs build/deploy | CI / infra (`.github/workflows/`) | — | A new job (or step) in the existing Actions matrix; does not touch `src/`. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Documenter.jl | 1.17 (pinned, `docs/Project.toml` compat) [VERIFIED: docs/Project.toml + Context7 /juliadocs/documenter.jl] | Docs site generator, doctest runner, `checkdocs` API-coverage gate, `deploydocs` | Already adopted in Phase 1; the standard Julia-ecosystem docs tool; renders `@example` output and KaTeX math. |
| Literate.jl | 2.21 (pinned, `docs/Project.toml` compat) [VERIFIED: docs/Project.toml + Context7 /fredrikekre/literate.jl] | Turns commented `.jl` scripts into Documenter markdown pages that execute during `makedocs` | Already adopted (`docs/literate/toy_dc.jl`); the idiomatic "one source, runnable script + rendered docs" tool. |
| TestItemRunner.jl / TestItems.jl | already pinned (`Manifest.toml`, project-wide) [VERIFIED: existing test suite] | `@testitem`-based regression/acceptance tests, auto-discovered | Already the project's sole test framework; `test/test_acceptance.jl` is discovered automatically, no config change needed. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CairoMakie.jl | 0.15 (weakdep, `[weakdeps]` in root `Project.toml`) [VERIFIED: Project.toml] | Convergence/voltage/DLMP figures embedded in docs pages | Only inside literate pages that plot; gated so the docs build degrades gracefully without it (see Pitfalls). |
| JuMP.jl / Clarabel / HiGHS / Ipopt | already pinned | Solved by the reused `src/` entrypoints | No direct new usage — docs/tests call `solve_welfare`/`solve_admm`, which already select the right solver via the factory. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@example` blocks (execute, show output, no assertion) | `jldoctest` blocks (execute, exact-string-match assertion) | `jldoctest` would fail intermittently on floating-point solve output (no numeric tolerance in Documenter's doctest matcher — confirmed no built-in `atol`/`rtol` support) [CITED: documenter.juliadocs.org/stable/man/doctests/, community reports of doctest float flakiness]. Stick with `@example` for all numeric solve output; reserve `jldoctest` (if used at all) for pure-syntax/API docstring examples with no floats. |
| Inline typed-constant goldens (existing convention) | External golden files (JLD2/CSV) | CONTEXT.md explicitly locks the inline-constant convention for unit-test goldens and reserves JLD2/CSV for experiment-harness (Phase 8) outputs — do not mix the two storage tiers. |
| One consolidated `test/test_acceptance.jl` | Duplicating assertions inline in each per-phase test file | CONTEXT.md locks the consolidated-file decision; per-phase tests stay as the fine-grained regression net, the acceptance file is the single SC3 gate. |

**Installation:** No new packages required. `docs/Project.toml` already has
`Documenter = "1.17"`, `Literate = "2.21"`. Root `Project.toml` already has
`CairoMakie` under `[weakdeps]`. If the docs build wants to *render* CairoMakie
figures (not just structurally reference them), add `CairoMakie` to `docs/Project.toml`
so the docs env can `using CairoMakie` — see Pitfall 3 below for the weakdep-gating
implication.

**Version verification:** Confirmed via `docs/Project.toml` `[compat]` (Documenter
"1.17", Literate "2.21") and cross-checked against Context7 `/juliadocs/documenter.jl`
and `/fredrikekre/literate.jl` — both current/actively maintained as of this session.
`docs/Manifest.toml` resolves concrete `Documenter`/`Literate` deps consistent with
those compat bounds.

## Package Legitimacy Audit

**No new external packages are introduced by this phase.** Documenter, Literate, and
CairoMakie are all already-pinned dependencies (`docs/Project.toml` / root
`Project.toml`) that passed legitimacy review in earlier phases. The Package
Legitimacy Gate is not applicable — skip the slopcheck/registry-verification steps.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────┐
                    │   src/ (unchanged — read-only from Phase 9)  │
                    │  operational_oracle · solve_welfare ·        │
                    │  solve_admm · extract_dlmp · fit_baseline ·  │
                    │  welfare_accounting · assert_socp_exact! ·   │
                    │  ieee13_modified · ieee123_modified ·        │
                    │  run_scenario · AdmmResiduals                │
                    └───────────────┬───────────────┬─────────────┘
                                    │                │
                     calls (real   │                │ calls (real solve,
                     solve, no     │                │ pinned tolerances)
                     reimplementation)               │
                                    ▼                ▼
        ┌───────────────────────────────┐  ┌──────────────────────────────┐
        │  docs/literate/*.jl (EXP-03)  │  │ test/test_acceptance.jl       │
        │  one page per abstraction     │  │ (EXP-04 / SC3)                │
        │  rung: LinDistFlow, SOCP+     │  │ IEEE-13 congestion +          │
        │  exactness, devices+GLB-CVX,  │  │ IEEE-123 voltage, each:       │
        │  DADP/DLMP, ADMM              │  │  exact relaxation (PF-04)     │
        │  → @example blocks execute    │  │  + recovered DADP             │
        │    during makedocs            │  │  + ADMM ≈ centralized         │
        └───────────────┬───────────────┘  └──────────────┬────────────────┘
                         │ Literate.markdown                │ @testitem
                         │ (flavor=DocumenterFlavor)         │ (TestItemRunner
                         ▼                                   │  auto-discovers)
        ┌───────────────────────────────┐                    ▼
        │  docs/make.jl → makedocs(...)  │        ┌──────────────────────────┐
        │  pages tree, checkdocs=:exports│        │ Existing per-phase test  │
        │  warnonly=[...], KaTeX math    │        │ files (1933 tests, inline│
        │  optional CairoMakie figures   │        │ golden pins) — UNCHANGED,│
        │  (weakdep-gated)               │        │ acceptance file REFERENCES│
        └───────────────┬───────────────┘         │ their tolerances, does   │
                         │                          │ not duplicate/rip them   │
                         ▼                          └──────────────────────────┘
        ┌───────────────────────────────┐
        │ CI: docs build job (new step/  │
        │ workflow) — gated on CI env    │
        │ var before deploydocs;         │
        │ existing test/format jobs      │
        │ unchanged                      │
        └───────────────────────────────┘
```

### Recommended Project Structure
```
docs/
├── make.jl                      # extended: pages tree + tightened checkdocs
├── literate/
│   ├── toy_dc.jl                 # existing — migrate documenter=true → flavor=...
│   ├── lindistflow.jl             # NEW — Rung 1/2: DC/LinDistFlow (PF-02)
│   ├── convex_branch_flow.jl      # NEW — SOCP + exactness copy (PF-03/PF-04, eq. 3.39/3.43-3.45)
│   ├── prosumer_welfare.jl        # NEW — devices + Aggregator + GLB-CVX (DEV-*, OPT-01, eq. 3.22/3.23/3.46)
│   ├── pricing_dlmp.jl            # NEW — DADP/DLMP decomposition (PRICE-01/02, eq. 3.31)
│   └── admm.jl                    # NEW — ADMM decomposition + convergence (ADMM-01..05)
├── src/
│   ├── index.md                   # extended: links to all generated pages
│   └── generated/                 # Literate output (gitignored, build artifact)
└── references/                    # already vendored: thesis PDFs (equation source)
test/
├── test_acceptance.jl             # NEW — consolidated SC3 gate
└── (all existing 40 test_*.jl / fixtures_phaseN.jl UNCHANGED)
```

### Pattern 1: Literate page = math → assumptions → validation (per CONTEXT.md)
**What:** Each new literate page follows the `toy_dc.jl` structure: markdown-commented
prose stating the thesis equation(s) in a `` ```math ``` `` block, immediately followed
by the JuMP/TSODSO code that implements it, then an `@example`-executed validation step
(exactness check, dual/price recovery, or ADMM-vs-centralized comparison).
**When to use:** Every one of the 5-6 new pages.
**Example (adapting the existing pattern, migrated off the deprecated kwarg):**
```julia
# Source: docs/literate/toy_dc.jl (existing pattern) + Literate.jl DocumenterFlavor docs
# ## SOC relaxation exactness (thesis eq. 3.39, 3.43-3.45)
#
# ```math
# l_{ij} v_i \ge P_{ij}^2 + Q_{ij}^2 \qquad \text{(3.39, SOC cone)}
# ```
#
# The LinDistFlow exactness copy (3.43-3.45) adds an auxiliary $\hat v$ and affine
# voltage bounds so the relaxation is tight on radial trees (PF-04).

ctx, obj, dadp = solve_welfare(feeder, ConvexBranchFlow(), aggs; T = 24, λ₀ = λ₀)
maxgap = ctx.meta[:socp_maxgap]     # PF-04 exactness gate result, real solve
```
```julia
# docs/make.jl — CURRENT (deprecated) API in the repo today:
Literate.markdown(joinpath(LITERATE_DIR, "toy_dc.jl"), GENERATED_DIR; documenter = true)

# RECOMMENDED (non-deprecated, same output, Literate >= 2.9):
Literate.markdown(
    joinpath(LITERATE_DIR, "toy_dc.jl"), GENERATED_DIR;
    flavor = Literate.DocumenterFlavor(),
)
```
Source: [Literate.jl output-formats docs](https://fredrikekre.github.io/Literate.jl/v2/outputformats/), Context7 `/fredrikekre/literate.jl`.

### Pattern 2: `pages` tree groups the abstraction ladder
**What:** `makedocs(; pages = [...])` with a nested `"Models" => [...]` group so the
five-to-six new pages read as a ladder (Rung 0 toy → LinDistFlow → SOCP/exactness →
devices/welfare → pricing → ADMM), matching the project's abstraction-ladder framing.
**Example:**
```julia
# Source: Documenter.jl guide.md (Context7 /juliadocs/documenter.jl) — nested pages syntax
pages = [
    "Home" => "index.md",
    "Models" => [
        "Rung 0: Toy DC" => "generated/toy_dc.md",
        "Rung 1-2: LinDistFlow" => "generated/lindistflow.md",
        "Rung 3: SOCP + Exactness" => "generated/convex_branch_flow.md",
        "Rung 3: Devices + GLB-CVX" => "generated/prosumer_welfare.md",
        "Rung 4: DADP/DLMP Pricing" => "generated/pricing_dlmp.md",
        "Rung 5: ADMM Decomposition" => "generated/admm.md",
    ],
]
```

### Pattern 3: Acceptance test reuses fixtures, never re-derives calibration
**What:** `test/test_acceptance.jl` should `setup = [Phase4Fixtures]` (IEEE-13) and
`setup = [Phase7Fixtures]` (IEEE-123) — the same setup modules `test_ieee13.jl` /
`test_ieee123_admm.jl` already use — and call the exact same entrypoints
(`operational_oracle`, `solve_admm`, `extract_dlmp`). It re-asserts the *already-pinned*
golden values (or references them via `include`/shared constants) rather than
recomputing new tolerances.
**Example (skeleton, values are the EXISTING pinned goldens from `test_ieee13.jl` /
`test_ieee123_admm.jl`, not new):**
```julia
@testitem "acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized (SC3)" tags = [
    :acceptance,
] setup = [Phase4Fixtures] begin
    using TSODSO, JuMP
    feeder = TSODSO.ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    λ₀ = Phase4Fixtures.mem_price_profile()

    res = operational_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true)
    @test res.ctx.meta[:socp_maxgap] < 1e-5                     # PF-04 exact relaxation
    @test isapprox(res.cost, -4823.1598620624; rtol = 1e-4)      # existing golden (test_ieee13.jl)

    admm = solve_admm(feeder, ConvexBranchFlow(), aggs; T = 24, λ₀ = λ₀, ρ = 100.0, allow_export = true)
    @test isapprox(admm.welfare, res.cost; rtol = 1e-4)          # ADMM ≈ centralized (ADMM-03)
    @test isapprox(admm.λ, res.dadp; atol = 1e-2, rtol = 1e-3)   # recovered DADP match
end
```

### Anti-Patterns to Avoid
- **Reimplementing a solve inside a literate page or the acceptance test:** every page
  and the acceptance gate must call the existing `src/` entrypoint, never hand-roll a
  parallel JuMP model — that would silently fork the math from the validated core.
- **Using `jldoctest` for numeric solve output:** exact-string-match doctests on
  floating-point results are the textbook flaky-CI trap in Julia docs (see Pitfall 2).
- **Inventing new acceptance tolerances:** CONTEXT.md locks "reuse the already-pinned
  per-phase tolerances... do not invent new/looser acceptance tolerances."
- **Hard-depending on CairoMakie from `docs/make.jl`:** would break the weakdep
  isolation Phase 7 built (`ext/TSODSOMakieExt.jl`) and the "headless build must
  succeed" property Phase 1 established (`remotes = nothing`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Literate → Documenter markdown pipeline | A custom script that runs `.jl` files and pastes output into `.md` | `Literate.markdown(...; flavor = Literate.DocumenterFlavor())` | Already solved, already adopted (Phase 1); handles `@example` block emission, `#hide` directives, `EditURL` metadata. |
| API-coverage checking | A grep-based "which functions lack docstrings" script | `makedocs(; checkdocs = :exports)` | Documenter already does this natively and fails the build (or warns) on gaps. |
| Doctest / example execution during CI | A separate script that `include()`s literate sources and diffs output | `makedocs` itself executing `@example` blocks (already the mechanism in `docs/make.jl`) | This IS the reproducibility gate CONTEXT.md specifies ("`makedocs` with `@example` execution is itself the docs reproducibility gate"). |
| Regression golden storage | A JLD2/CSV golden-file diffing harness for unit tests | Inline typed constants + `rtol`/`atol` in `@testitem`s (existing convention, 1933 tests) | CONTEXT.md explicitly reserves JLD2/CSV for Phase-8 experiment-harness outputs, not unit-test goldens — two different storage tiers serve two different purposes. |
| End-to-end acceptance orchestration | A new "runner" script outside the test suite | A `@testitem` in `test/test_acceptance.jl`, auto-discovered by TestItemRunner | Keeps the acceptance gate inside the same `Pkg.test()` / CI path as everything else — no second CI mechanism to maintain. |

**Key insight:** Every tool this phase needs (Documenter, Literate, TestItemRunner,
CairoMakie weakdep ext) is already installed, already pinned, and already has a working
example in the repo (`docs/make.jl` + `docs/literate/toy_dc.jl` for docs;
`test_ieee13.jl` + `test_ieee123_admm.jl` for the acceptance pattern;
`ext/TSODSOMakieExt.jl` + `test_diagnostics_plot.jl` for the weakdep-gating pattern).
Phase 9 is pure "extend the existing pattern N more times," not "adopt a new tool."

## Common Pitfalls

### Pitfall 1: `Literate.markdown(...; documenter = true)` is deprecated
**What goes wrong:** Every new literate page written with the same `documenter = true`
kwarg the existing `toy_dc.jl` build call uses emits a `DeprecationWarning` at build
time; it still works today (Literate 2.21 still honors the old kwarg) but is a
paper cut that will eventually break on a Literate major bump.
**Why it happens:** The kwarg was deprecated in Literate **2.9.0 (2021-07-09)** in favor
of `flavor = Literate.DocumenterFlavor()` / `Literate.CommonMarkFlavor()`, but the
project's Phase-1 `docs/make.jl` predates this research and still uses the old form.
**How to avoid:** Write every new `Literate.markdown(...)` call in `docs/make.jl` with
`flavor = Literate.DocumenterFlavor()`; migrate the existing `toy_dc.jl` build call in
the same edit (one line, zero behavior change — output markdown is identical).
**Warning signs:** A `DeprecationWarning` line in the `julia docs/make.jl` build log.
[VERIFIED: Context7 /fredrikekre/literate.jl + Literate.jl CHANGELOG.md, cross-checked]

### Pitfall 2: `jldoctest` blocks are not float-tolerant
**What goes wrong:** If a docstring or page uses a `jldoctest` block (exact string-match
assertion) on output containing a solved floating-point number, a harmless BLAS/solver
version bump or platform difference can flip the doctest red — a documented, recurring
Documenter.jl community pain point.
**Why it happens:** Documenter's doctest matcher does exact string comparison; it has no
built-in `atol`/`rtol` numeric-tolerance mode (unlike e.g. Python's `scipy_doctest` or
`pytest.approx`).
**How to avoid:** Use `@example` blocks (execute + render output, no pass/fail assertion)
for every solve-derived number, exactly as `toy_dc.jl` already does. Reserve
`jldoctest`/`doctest = true` only for pure-syntax examples with no floating-point solve
output (or keep `doctest = false`/`:only`-scoped if any docstrings do carry doctests).
**Warning signs:** A previously-green docs build turning red after an unrelated solver
or Julia-version bump, with the failure localized to a `jldoctest` numeric comparison.
[CITED: documenter.juliadocs.org/stable/man/doctests/; community reports, MEDIUM confidence — no single canonical source but consistent across multiple discussions]

### Pitfall 3: CairoMakie figures in docs need their own weakdep gate
**What goes wrong:** Adding `using CairoMakie` directly inside a literate page (or
`docs/make.jl`) that is loaded whenever `docs/Project.toml` is instantiated makes
CairoMakie an effective **hard dependency of the docs build**, defeating the weakdep
isolation Phase 7 built (`ext/TSODSOMakieExt.jl` — CairoMakie must never load in the
headless core test process, threat T-07-01) and risking docs-build failure in any CI
runner without a display/backend quirk (rare for CairoMakie specifically, since it's
headless-safe, but still an unnecessary hard coupling).
**Why it happens:** The docs environment (`docs/Project.toml`) is a *separate* Julia
environment from the package's own `[weakdeps]` — Documenter loads `TSODSO` and
whatever the docs env has installed; nothing forces the same weakdep discipline there.
**How to avoid:** Add `CairoMakie` to `docs/Project.toml` `[deps]` (it is fine for the
*docs* environment specifically to hard-depend on it — that's a separate concern from
`src/`'s core purity) but keep every plotting call inside literate pages guarded by
`if Base.find_package("CairoMakie") !== nothing` (mirroring `test_diagnostics_plot.jl`'s
existing pattern) so the *same* literate source still degrades gracefully if someone
builds docs without CairoMakie installed, OR simply document that `docs/Project.toml`
requiring CairoMakie is the intended scope boundary (CairoMakie is headless-safe, small,
and open-source — a reasonable docs-only hard dep). Either resolution is acceptable;
CONTEXT.md only requires the *core* `src/`/`Project.toml` stay weakdep-gated, which is
already satisfied.
**Warning signs:** `docs/Project.toml` growing a `CairoMakie` entry is not itself a
problem — check instead that root `Project.toml`'s `[weakdeps]`/`[extensions]` block is
untouched by this phase.

### Pitfall 4: `checkdocs` default (`:all`) will fail the build on internal/private symbols
**What goes wrong:** Naively flipping `checkdocs` from `:none` straight to the Documenter
default (`:all`) will fail-hard on every internal helper function across 40+ source
files that (correctly) has no docstring — a huge, disproportionate build break for an
EXP-03 task that only asks for *public-API* doc coverage.
**Why it happens:** `:all` checks every name with a docstring attached anywhere in the
module, not just exported ones; `:exports` checks only exported names; `:public` (Julia
≥ 1.11 semantics) checks exported names plus anything marked with the `public` keyword.
**How to avoid:** Use `checkdocs = :exports` — it is available on both the 1.10 LTS
floor and 1.11+ (on 1.10, `:public` and `:exports` behave identically since the `public`
keyword doesn't exist pre-1.11; `:exports` is therefore the cross-version-safe choice
matching the project's dual-Julia-version CI matrix). Keep `warnonly` covering any
residual gaps so the build stays green while surfacing them, per CONTEXT.md.
**Warning signs:** `makedocs` throwing dozens of "missing docstring" errors for clearly
internal (non-exported) helpers immediately after flipping `checkdocs`.
[VERIFIED: Context7 /juliadocs/documenter.jl syntax.md + public.md]

### Pitfall 5: `deploydocs` must never run from a local/worktree checkout
**What goes wrong:** Calling `deploydocs(...)` unconditionally (even wrapped in the
normal `makedocs` call) attempts to push to `gh-pages` using local git state; in a
worktree or detached checkout (exactly the situation the Phase-1 `remotes = nothing`
note already documents) this fails or, worse, could push from an unintended local state.
**Why it happens:** Documenter's `deploy_config` auto-detection looks for CI-specific
environment variables (`GITHUB_ACTIONS`, `CI`, etc.); a bare local run has none of these
and will simply skip deployment IF `deploydocs` uses its own auto-detection — but an
explicit unconditional call without the `CI`-gate CONTEXT.md specifies removes that
safety net.
**How to avoid:** Wrap the `deploydocs(...)` call in `if get(ENV, "CI", nothing) ==
"true"` (matching the existing `prettyurls` pattern already in `docs/make.jl`) OR rely
on Documenter's built-in GitHub Actions auto-detection (`deploy_config` defaults to
auto-detecting CI) — CONTEXT.md already locks the explicit-gate approach, which is the
more defensive of the two and consistent with the project's existing `ENV["CI"]` idiom.
**Warning signs:** A `deploydocs` call with no CI/environment guard anywhere in
`docs/make.jl`.
[CITED: documenter.juliadocs.org/stable/man/hosting.md — deploy_config auto-detection; CONTEXT.md lock]

### Pitfall 6: Docs build cost in the CI matrix
**What goes wrong:** Each new literate page's `@example` blocks re-solves a real SOCP
(potentially the IEEE-123 ADMM loop, ~17 iterations) during `makedocs` — on top of the
existing 3-way Julia-version test matrix (1.10/1.11/1.12), a naive "add docs to every
matrix leg" design multiplies build time for no benefit (docs content doesn't change
by Julia version).
**Why it happens:** Documenter builds are not test-matrix-parallel by nature; running
the same doc build 3× wastes CI minutes.
**How to avoid:** Run the docs build as a **single dedicated job** (one Julia version,
e.g. '1.11' matching the existing `format` job's choice) — not inside the `test` job's
version matrix. CONTEXT.md leaves "separate workflow file or a step in the existing
matrix" to Claude's discretion; a single extra job (not a matrix leg) is the
cost-appropriate choice.
**Warning signs:** CI wall-clock time roughly tripling after adding docs, with three
near-identical docs-build logs (one per Julia version).

## Code Examples

### Verified Documenter/Literate migration + extension pattern
```julia
# Source: Context7 /juliadocs/documenter.jl (guide.md, syntax.md) +
#         Context7 /fredrikekre/literate.jl (outputformats.md)
using Documenter
using Literate
using TSODSO

const LITERATE_DIR = joinpath(@__DIR__, "literate")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

for src in (
    "toy_dc.jl", "lindistflow.jl", "convex_branch_flow.jl",
    "prosumer_welfare.jl", "pricing_dlmp.jl", "admm.jl",
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src), GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),   # non-deprecated (Pitfall 1)
    )
end

makedocs(;
    sitename = "TSODSO",
    modules = [TSODSO],
    authors = "Pedro Bittencourt",
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    remotes = nothing,                          # still required (bare/worktree checkouts)
    pages = [
        "Home" => "index.md",
        "Models" => [
            "Rung 0: Toy DC" => "generated/toy_dc.md",
            "Rung 1-2: LinDistFlow" => "generated/lindistflow.md",
            "Rung 3: SOCP + Exactness" => "generated/convex_branch_flow.md",
            "Rung 3: Devices + GLB-CVX" => "generated/prosumer_welfare.md",
            "Rung 4: DADP/DLMP Pricing" => "generated/pricing_dlmp.md",
            "Rung 5: ADMM Decomposition" => "generated/admm.md",
        ],
    ],
    checkdocs = :exports,                        # tightened from :none (Pitfall 4)
    warnonly = [:missing_docs, :cross_references],
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(; repo = "github.com/<org>/TSO-DSO.jl.git")   # CI-gated (Pitfall 5)
end
```

### Verified acceptance-gate skeleton (values are existing pinned goldens, not new)
```julia
# Source: test/test_ieee13.jl (GOLDEN_* constants), test/test_ieee123_admm.jl (contract)
@testitem "acceptance: IEEE-123 voltage — exact relaxation + DADP + ADMM≈centralized (SC3)" tags = [
    :acceptance,
] setup = [Phase7Fixtures] begin
    using TSODSO
    feeder = ieee123_modified()
    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
    load_buses = [a.bus for a in aggs]
    λ₀ = Phase7Fixtures.ieee123_lambda0()

    ctx_c, obj_c, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs; T = Phase7Fixtures.T, λ₀ = λ₀, allow_export = true)
    dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Phase7Fixtures.T)' for b in load_buses))

    res = solve_admm(
        feeder, ConvexBranchFlow(), aggs; T = Phase7Fixtures.T, λ₀ = λ₀, ρ = Phase7Fixtures.RHO0,
        ε_abs = Phase7Fixtures.EPS_ABS, ε_rel = Phase7Fixtures.EPS_REL, τ = Phase7Fixtures.TAU,
        μ = Phase7Fixtures.MU, ρ_min = Phase7Fixtures.RHO_MIN, ρ_max = Phase7Fixtures.RHO_MAX,
        maxiter = 300, allow_export = true,
    )
    @test res.exact_maxgap < 1e-3
    @test isapprox(res.welfare, obj_c; rtol = 1e-4)
    @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `Literate.markdown(...; documenter = true)` | `Literate.markdown(...; flavor = Literate.DocumenterFlavor())` | Literate 2.9.0 (2021-07-09) | Old kwarg still works (deprecation warning only) at the pinned 2.21; migrate for cleanliness, not correctness. |
| `checkdocs` binary-ish (`:all`/`:none`) mental model | `:all` / `:exports` / `:public` (Julia ≥ 1.11 `public` keyword-aware) / `:none` | Documenter added `:public` for Julia 1.11's `public` keyword | Project's 1.10 LTS floor means `:exports` and `:public` are equivalent in practice today; `:exports` is the safe cross-version choice. |

**Deprecated/outdated:**
- `documenter = true`/`documenter = false` kwargs to `Literate.markdown`/`Literate.notebook`:
  deprecated since 2021, replaced by `flavor = Literate.DocumenterFlavor()` /
  `Literate.CommonMarkFlavor()`. No forced-removal timeline found in the CHANGELOG as of
  Literate 2.21 (2025-11-19) — still functional, just noisy.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `checkdocs = :exports` is the intended "public API docstrings" tightening level (vs. `:public` or `:all`) | Common Pitfalls #4, Code Examples | Low — `:exports` is strictly more permissive than `:all`/`:public`+strict private-check; if the researcher wants a stricter gate, this is a one-word change in `docs/make.jl`, not a re-architecture. Flagged for planner/researcher confirmation since CONTEXT.md left exact tightening level unspecified beyond "from :none." |
| A2 | The docs CI job should be one dedicated non-matrix job (not a matrix leg) | Common Pitfalls #6 | Low — CONTEXT.md explicitly delegates this to Claude's discretion; if the researcher prefers matrix-parallel docs builds for some reason, this is a workflow-YAML-only change. |
| A3 | Six new literate pages (one per named rung in CONTEXT.md) is the right granularity, rather than fewer/more pages | Architecture Patterns, Recommended Project Structure | Low — CONTEXT.md explicitly lists "~5-6 new pages" and names the topics; page-count is Claude's discretion within that range. |

**If this table is empty:** N/A — see above; none of these are HIGH-risk since all are
explicitly scoped as "Claude's Discretion" in CONTEXT.md and are cheap to adjust later.

## Open Questions

1. **Exact `docs/Project.toml` treatment of CairoMakie** (RESOLVED)
   - What we know: root `Project.toml` keeps CairoMakie as a `[weakdeps]` extension
     target; `docs/Project.toml` is a wholly separate environment.
   - What's unclear: whether the researcher wants `docs/Project.toml` to hard-depend on
     CairoMakie (simplest, since docs-only) or to mirror the weakdep-gated pattern
     inside literate pages too (more defensive, matches `test_diagnostics_plot.jl`).
   - Recommendation: add `CairoMakie` as a normal `[deps]` entry in `docs/Project.toml`
     (docs-only environments hard-depending on a plotting library is completely normal
     and does not violate the core-library weakdep discipline), but still guard each
     plotting `@example` block with `if Base.find_package("CairoMakie") !== nothing`
     as defensive belt-and-suspenders — cheap insurance, matches an existing test
     pattern, and future-proofs against someone stripping the docs Manifest.

   - RESOLVED: CONTEXT.md locked the `[deps]`-with-guard approach described above.
     Plan 09-04 Task 1 implements it: `CairoMakie` is added to `docs/Project.toml`
     `[deps]`/`[compat]` AND `docs/Manifest.toml` is re-resolved (`Pkg.resolve()`) and
     committed in the same task, so `Base.find_package("CairoMakie")` actually succeeds
     under `--project=docs` rather than silently no-opping on a stale Manifest.

2. **Repo URL for `deploydocs`** (RESOLVED)
   - What we know: `docs/make.jl` currently sets `remotes = nothing` specifically
     because Documenter cannot infer a remote in this checkout state (documented
     Phase-1 rationale).
   - What's unclear: the actual GitHub org/repo slug to pass to `deploydocs(repo=...)`
     — not discoverable from the local repo state researched here.
   - Recommendation: planner should insert a `checkpoint:human-verify` (or leave a
     clearly marked placeholder) for the `deploydocs(repo = "github.com/<ORG>/<REPO>.git")`
     string; this is a one-line fill-in the researcher can confirm at execution time,
     not a design decision.

   - RESOLVED: plan 09-04 Task 2 wires `deploydocs(; repo = "github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git")`
     behind the `CI` env-var gate with a clearly-commented placeholder slug; plan 09-05
     Task 2 is the blocking `checkpoint:human-verify` where the researcher confirms/updates
     the real org/repo slug before any real CI deploy.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | docs build + tests | ✓ | — (project already runs on 1.10/1.11/1.12 CI matrix) | — |
| Documenter.jl (docs env) | EXP-03 build | ✓ (pinned `docs/Project.toml`) | 1.17 (compat) | — |
| Literate.jl (docs env) | EXP-03 build | ✓ (pinned `docs/Project.toml`) | 2.21 (compat) | — |
| CairoMakie.jl | Optional figures in docs pages | Weakdep only in root env; NOT currently in `docs/Project.toml` [ASSUMED — not directly probed in a live env this session, inferred from Project.toml contents] | 0.15 (compat, root `[weakdeps]`) | Docs build degrades gracefully (guard with `Base.find_package`), or add to `docs/Project.toml` per Open Question 1 |
| GitHub Actions runner | CI docs job | ✓ (existing `.github/workflows/CI.yml` matrix proves the runner works) | ubuntu-latest | — |

**Missing dependencies with no fallback:** None identified — every tool this phase
needs is already pinned in a `Project.toml` somewhere in the repo.

**Missing dependencies with fallback:** CairoMakie in the docs env (see above); falls
back to "figures section shows structural-only note" if not added, matching the
pre-existing `test_diagnostics_plot.jl` skip-with-message idiom.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItemRunner.jl / TestItems.jl (pinned project-wide; already used by all 40 `test_*.jl` files) |
| Config file | `test/runtests.jl` (`@run_package_tests`) — no changes needed; new `test/test_acceptance.jl` is auto-discovered |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test(; test_args=["acceptance"])'` (TestItemRunner honors tag/name filters — mirrors the existing `occursin("ieee13", ti.name)`-style filtering already used by other phases) |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXP-03 | Literate math docs render + execute for every model rung | docs-build (executable, not a `@testitem`) | `julia --project=docs docs/make.jl` (must exit 0, no `@example` errors) | ❌ Wave 0 — `docs/make.jl` needs the new `Literate.markdown` calls + `pages` entries |
| EXP-04 | Regression fixtures pin IEEE-13/123 + FIT comparison | unit (existing pins) + consolidated | Existing: `julia --project=. -e 'using Pkg; Pkg.test()'` already covers per-phase pins; NEW: same command exercises `test_acceptance.jl` once added | ❌ Wave 0 — `test/test_acceptance.jl` does not yet exist |
| SC3 (acceptance gate) | IEEE-13 congestion + IEEE-123 voltage, each exact relaxation + DADP + ADMM≈centralized, in one place | integration (`@testitem`) | `julia --project=. -e 'using Pkg; Pkg.test(; test_args=["acceptance"])'` | ❌ Wave 0 — same new file as EXP-04's consolidated layer |

### Sampling Rate
- **Per task commit:** targeted `Pkg.test(; test_args=["acceptance"])` (or the relevant
  new literate page's standalone `include(...)` smoke-run) — fast, avoids re-running the
  full 1933-test suite on every edit.
- **Per wave merge:** full `Pkg.test()` (all 1933+ existing tests + new acceptance
  items) AND a full `julia --project=docs docs/make.jl` build.
- **Phase gate:** both the full test suite green AND the docs build exiting 0 (no
  `@example` execution errors, no `checkdocs` failures) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `docs/literate/lindistflow.jl`, `convex_branch_flow.jl`, `prosumer_welfare.jl`,
      `pricing_dlmp.jl`, `admm.jl` — five new literate sources (page count is Claude's
      discretion within CONTEXT.md's "~5-6" guidance).
- [ ] `docs/make.jl` — extend with the new `Literate.markdown` calls (migrated to
      `flavor = Literate.DocumenterFlavor()`), the nested `pages` tree, `checkdocs =
      :exports`, and the CI-gated `deploydocs` call.
- [ ] `test/test_acceptance.jl` — new consolidated `@testitem` file (does not exist yet).
- [ ] `docs/Project.toml` — optionally add `CairoMakie` (Open Question 1).
- [ ] `.github/workflows/CI.yml` (or a new workflow file) — a docs-build job/step.
- [ ] Framework install: none — `Pkg.instantiate()` in the existing `docs/` env already
      resolves Documenter 1.17 / Literate 2.21 from the committed Manifest.

*(No gaps beyond the above — existing per-phase test infrastructure fully covers the
regression-pin half of EXP-04; only the consolidated acceptance layer and the docs
build are net-new.)*

## Security Domain

This phase adds documentation-build tooling and test-only code; it introduces no
network-facing surface, no authentication, no session handling, and no
externally-supplied untrusted input beyond what earlier phases already validate
(feeder magnitude/topology assertions, INFRA-05). ASVS categories V2/V3/V4/V6 are
**not applicable** to a local research library's docs/test build. The one
loosely-relevant control:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth surface in a local Julia library |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Marginal | `deploydocs`'s repo string and any `docs/Project.toml` additions are researcher-authored, not externally supplied; no new validation need beyond existing `assert_radial!`/`assert_magnitudes!` (unchanged by this phase) |
| V6 Cryptography | No | N/A — `DOCUMENTER_KEY`/`GITHUB_TOKEN` secrets (if `deploydocs` is wired to actually push) are handled entirely by GitHub Actions' existing secret-injection mechanism, not by any code this phase writes |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Accidental docs deploy from an untrusted/local checkout | Tampering / Elevation of privilege (unintended gh-pages push) | CI-env-var gate on `deploydocs` (Pitfall 5) — already locked by CONTEXT.md |
| Leaking `DOCUMENTER_KEY`/`GITHUB_TOKEN` in build logs | Information Disclosure | Standard GitHub Actions secret masking; do not `println`/log `ENV` dumps in `docs/make.jl` |

## Sources

### Primary (HIGH confidence)
- Context7 `/juliadocs/documenter.jl` — `checkdocs`, `warnonly`, `doctest`, `pages`
  nesting, `mathengine`/KaTeX default, `deploydocs`/GitHub Actions hosting pattern.
- Context7 `/fredrikekre/literate.jl` — `flavor = Literate.DocumenterFlavor()` current
  API, deprecation of `documenter=true`, `@example` block emission semantics.
- `docs/make.jl`, `docs/literate/toy_dc.jl`, `docs/Project.toml`, `docs/Manifest.toml`
  (this repo) — the existing working pattern being extended.
- `test/test_ieee13.jl`, `test/test_ieee123_admm.jl`, `test/test_ieee123.jl`,
  `test/test_pricing_welfare.jl`, `test/test_pricing_fit.jl`, `test/test_diagnostics_plot.jl`,
  `ext/TSODSOMakieExt.jl`, `src/TSODSO.jl`, root `Project.toml` (this repo) — existing
  entrypoints, exports, golden-pin conventions, and weakdep-gating pattern this phase reuses.
- `.planning/phases/09-documentation-regression-acceptance-gate/09-CONTEXT.md`,
  `.planning/REQUIREMENTS.md`, `.planning/STATE.md` — locked decisions and traceable
  welfare-gap / IEEE-123-impedance deferrals this phase must respect (non-failing
  cross-checks, not new gates).

### Secondary (MEDIUM confidence)
- WebSearch on Literate.jl CHANGELOG — confirmed `documenter` kwarg deprecated at
  2.9.0 (2021-07-09), still functional (warning only) at 2.21 (2025-11-19), no removal
  scheduled as of that release.
- WebSearch + Documenter doctest docs — doctest float-flakiness is a known, recurring
  community pain point (no single canonical source, but consistent across multiple
  GitHub issues/Discourse threads).

### Tertiary (LOW confidence)
- None — every finding here was cross-checked against either Context7 or the repo's
  own existing, working code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every library is already pinned and working in this exact
  repo; no new-tool adoption risk.
- Architecture: HIGH — the docs/test patterns to extend are already implemented and
  passing (1933 tests, one working Literate page) with only volume/breadth added.
- Pitfalls: HIGH — the Literate deprecation was directly confirmed via Context7 +
  CHANGELOG; the checkdocs/deploydocs/weakdep pitfalls are directly confirmed via
  Context7 docs pages and the repo's own existing Phase-1/7 rationale comments.

**Research date:** 2026-07-20
**Valid until:** 30 days (Documenter/Literate are stable, slow-moving libraries; the
project's own `src/` entrypoints this phase depends on are frozen post-Phase-8)
