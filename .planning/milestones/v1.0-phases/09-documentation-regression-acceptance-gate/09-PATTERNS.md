# Phase 9: Documentation & Regression Acceptance Gate - Pattern Map

**Mapped:** 2026-07-20
**Files analyzed:** 10 (new/modified)
**Analogs found:** 10 / 10

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `docs/literate/lindistflow.jl` | doc-page (literate) | transform (real solve → rendered math+numbers) | `docs/literate/toy_dc.jl` | exact |
| `docs/literate/convex_branch_flow.jl` | doc-page (literate) | transform | `docs/literate/toy_dc.jl` + `test/test_exactness.jl` (validation step) | exact |
| `docs/literate/prosumer_welfare.jl` | doc-page (literate) | transform | `docs/literate/toy_dc.jl` + `test/fixtures_phase4.jl` (aggregator build) | exact |
| `docs/literate/pricing_dlmp.jl` | doc-page (literate) | transform | `docs/literate/toy_dc.jl` + `test/test_pricing_welfare.jl` (DADP/DLMP extraction) | exact |
| `docs/literate/admm.jl` | doc-page (literate) | transform + streaming (iteration ledger) | `docs/literate/toy_dc.jl` + `test/test_ieee123_admm.jl` + `ext/TSODSOMakieExt.jl` (convergence figure) | role-match |
| `docs/make.jl` (modified) | config/build-script | batch (build-time codegen) | itself (extend in place) | exact |
| `docs/Project.toml` (modified) | config | — | itself (extend in place) | exact |
| `test/test_acceptance.jl` | test (integration/acceptance) | request-response (solve → assert) | `test/test_ieee123_admm.jl` (primary) + `test/test_ieee13.jl` (golden-pin idiom) | exact |
| `test/test_pricing_fit.jl` (extended) | test (regression) | CRUD (assert on golden) | itself — existing `@testitem`s in same file | exact |
| `.github/workflows/CI.yml` (modified / new docs job) | CI config | batch | existing `format` job in same file | role-match |

## Pattern Assignments

### `docs/literate/lindistflow.jl`, `convex_branch_flow.jl`, `prosumer_welfare.jl`, `pricing_dlmp.jl`, `admm.jl` (doc-page, transform)

**Analog:** `docs/literate/toy_dc.jl` (full file, 88 lines — read once, in context above)

**Structure to replicate (verbatim shape, not text):**
1. Title comment line `# # Rung N — <Name>` immediately followed by a short "what this
   page proves" paragraph naming the thesis threat/requirement it satisfies (mirrors
   `toy_dc.jl` lines 1-7 citing threat T-01-09).
2. Math block: prose + fenced ` ```math ... ``` ` LaTeX citing the thesis equation number
   in parentheses, e.g. `toy_dc.jl` lines 16-25:
   ```julia
   # ```math
   # S_\text{base} = 1.0~\text{MVA}, \qquad V_\text{base} = 4.16~\text{kV}
   # ```
   ```
   For the new pages substitute the CONTEXT.md-specified equation numbers:
   LinDistFlow → 3.43-3.45; SOCP cone → 3.39; nodal balance/DADP → 3.31;
   aggregator → 3.22/3.23/3.46.
3. Real construction/solve code — **never re-implement math**, only call existing
   `src/` entrypoints (`toy_dc.jl` lines 30-33, 65-72):
   ```julia
   buses = [Bus(1, 0.95, 1.05, true)]
   branches = Branch{Float64}[]
   feeder = Feeder(buses, branches, 1)
   ctx, objective, price = solve_toy_dc(feeder)
   ```
   New pages call `solve_welfare`, `operational_oracle`, `solve_admm`, `extract_dlmp`,
   `assert_socp_exact!`, `fit_baseline`, `welfare_accounting` — the exact same
   entrypoints the tests below already exercise. Reuse `Phase4Fixtures`/`Phase7Fixtures`
   fixture-builder LOGIC (not the `@testmodule` itself — literate pages cannot
   `setup=[...]`; either inline a small self-contained builder mirroring
   `fixtures_phase4.jl`'s `_house_aggregator`, or call the exported public builders if
   promoted to `src/`) — do not hand-roll a parallel JuMP model.
4. Bare-expression display lines (no `println`) so Documenter's `@example` renders the
   value inline — `toy_dc.jl` lines 76-87 (`objective`, `price`,
   `haskey(ctx.residuals, :nodal_balance)`). Use this idiom for every doc-visible number
   (welfare, exactness gap, DADP vector, ADMM iteration count) — never `@test`/assert
   inside a literate page (Pitfall 2: no `jldoctest` on floats).
5. Validation step at the end of each page, per CONTEXT.md's "math → assumptions →
   validation" structure:
   - `convex_branch_flow.jl` — exactness check, mirroring `test/test_exactness.jl`
     lines 36-41 pattern (`ctx.meta[:pf_vars]`, `assert_socp_exact!`) but as a bare
     `@example` display of `ctx.meta[:socp_maxgap]`, not a `@test`.
   - `pricing_dlmp.jl` — dual/price recovery, mirroring `test/test_pricing_welfare.jl`
     lines 43-48 (`extract_dlmp(ctx)`, `welfare_accounting(ctx; T=T)`), displayed not
     asserted.
   - `admm.jl` — ADMM-vs-centralized, mirroring `test/test_ieee123_admm.jl` lines 51-74
     (`solve_welfare` centralized + `solve_admm` + `isapprox` comparison), rendered as
     a displayed gap number, plus (guarded) a `plot_convergence`/`plot_price_convergence`
     figure call — see Shared Pattern "CairoMakie weakdep gating" below.

**Anti-pattern:** do not write a `jldoctest` block for any of these numbers (Pitfall 2 in
RESEARCH.md) — always `@example`-style bare display.

---

### `docs/make.jl` (build-script, batch)

**Analog:** itself — extend the existing 41-line file in place (full file content above).

**Migration (one-line, in the same edit that adds new pages):**
```julia
# CURRENT (deprecated, line 18-22):
Literate.markdown(
    joinpath(LITERATE_DIR, "toy_dc.jl"),
    GENERATED_DIR;
    documenter = true,
)

# REPLACE with (non-deprecated, identical output):
for src in (
    "toy_dc.jl", "lindistflow.jl", "convex_branch_flow.jl",
    "prosumer_welfare.jl", "pricing_dlmp.jl", "admm.jl",
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src), GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end
```

**`makedocs` call (lines 24-40) — extend, do not rewrite:**
- Keep `remotes = nothing` (line 31) — Pitfall 5 / Phase-1 rationale, unchanged.
- Extend `pages` (lines 32-35) with a nested `"Models" => [...]` group per RESEARCH.md
  Pattern 2 (exact ordering is Claude's discretion — CONTEXT.md).
- Tighten `checkdocs` from `:none` (line 38) to `:exports` (Pitfall 4) — keep
  `warnonly = [:missing_docs, :cross_references]` (line 39) unchanged so the build
  stays green while surfacing gaps, per CONTEXT.md.
- Add, after the `makedocs(...)` call, a CI-gated `deploydocs`:
  ```julia
  if get(ENV, "CI", nothing) == "true"
      deploydocs(; repo = "github.com/<ORG>/<REPO>.git")   # fill in the real slug
  end
  ```
  Mirrors the existing `prettyurls = get(ENV, "CI", nothing) == "true"` idiom already
  on line 28 of the same file — same `ENV["CI"]` guard pattern, just gating a second
  call instead of an option value.

---

### `test/test_acceptance.jl` (integration/acceptance test)

**Analog (primary):** `test/test_ieee123_admm.jl` (full file, 86 lines, read above).
**Analog (secondary, golden-pin idiom):** `test/test_ieee13.jl` lines 167-227 (the
"ground: pinned computed golden regression" `@testitem`).

**Imports / setup pattern** (from `test_ieee123_admm.jl` lines 20-22, `test_ieee13.jl`
lines 115-118):
```julia
@testitem "acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized (SC3)" tags = [
    :acceptance,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
```
For the IEEE-123 case, `setup = [Phase7Fixtures]` (mirrors `test_ieee123_admm.jl` line 21-22).

**Core pattern — centralized solve + ADMM + cross-validated DADP** (from
`test_ieee123_admm.jl` lines 31-74, adapted with IEEE-13 fixture calls from
`test_ieee13.jl` lines 119-128, 195):
```julia
feeder = TSODSO.ieee13_modified()
aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
λ₀ = Phase4Fixtures.mem_price_profile()

res = operational_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true)
ctx = res.ctx
@test ctx.meta[:socp_maxgap] < 1e-5                          # PF-04 exact relaxation

admm = solve_admm(
    feeder, ConvexBranchFlow(), aggs;
    T = 24, λ₀ = λ₀, ρ = 100.0, allow_export = true,
)
@test isapprox(admm.welfare, res.cost; rtol = 1e-4)          # ADMM ≈ centralized (ADMM-03/04)
@test isapprox(admm.λ, res.dadp; atol = 1e-2, rtol = 1e-3)   # recovered DADP match
```
For IEEE-123, follow `test_ieee123_admm.jl` lines 51-74 nearly verbatim (it already
IS this pattern) — reuse `Phase7Fixtures.T`, `RHO0`, `EPS_ABS`, `EPS_REL`, `TAU`, `MU`,
`RHO_MIN`, `RHO_MAX` (from `fixtures_phase7.jl` lines 46-52) rather than inventing new
tolerances, per CONTEXT.md's "reuse the already-pinned per-phase tolerances" lock.

**Golden-pin idiom to reuse for the "COMPUTED golden, non-failing thesis cross-check"
half** (from `test_ieee13.jl` lines 174-226 — this is the exact convention the
acceptance file should reference/reuse, not duplicate a second set of constants for):
```julia
const GOLDEN_V9_16 = 1.0436080536
const GOLDEN_WELFARE = -4823.1598620624
const THESIS_V9_16 = 1.0493             # non-failing thesis cross-check

@test isapprox(v9_16, GOLDEN_V9_16; atol = 1e-4)             # HARD assertion on computed golden
gap = abs(v9_16 - THESIS_V9_16)
@info "thesis cross-check" v9_16 = v9_16 thesis = THESIS_V9_16 gap = gap
@test gap < 1e-2 broken = (gap >= 1e-2)                       # NEVER fails the suite
```
Per CONTEXT.md: "gate on the COMPUTED goldens... Keep the thesis +$1819/+25% headline
numbers as NON-FAILING, documented cross-checks." The acceptance file should assert the
`test_ieee13.jl` `GOLDEN_*` constants and `test_ieee123_admm.jl`'s contract by calling
the same entrypoints — do NOT re-derive new tolerances or new golden constants.

**Error handling:** none beyond the standard `@test`/`isapprox` — this project's test
convention has no try/catch; a failed `@test` is the error-reporting mechanism itself.
No exception-handling pattern to extract (consistent across all analog test files read).

---

### `test/test_pricing_fit.jl` (extended) — regression addition

**Analog:** the file's own existing `@testitem`s (full file, 90 lines, read above) plus
`test/test_pricing_welfare.jl` lines 275-338 (the `RATIO_GOLDEN` FIT-vs-DADP ratio
pinning pattern — this IS the reference regression to extend/pin further per CONTEXT.md
"Pin the FIT-vs-DADP comparison as a regression... on the computed golden").

**Golden constant + rtol pattern** (from `test_pricing_welfare.jl` lines 316-325):
```julia
RATIO_GOLDEN = 0.9999738567553946
@test acct.ratio ≈ RATIO_GOLDEN rtol = 1e-4
```
Extend `test_pricing_fit.jl` with an analogous inline `const`/local golden + `rtol`
assertion — same file, same `@testitem` idiom (lines 47-77, 91-109 of that file show
the existing non-golden structural assertions to keep unchanged) — do not introduce a
JLD2/CSV file for this pin (CONTEXT.md explicitly reserves that storage tier for
Phase-8 experiment outputs).

---

### `.github/workflows/CI.yml` — docs build job (new)

**Analog:** the existing `format` job in the same file (lines 49-68, read above) — a
single dedicated non-matrix job is the cost-appropriate template (RESEARCH Pitfall 6).

**Pattern to replicate:**
```yaml
  docs:
    name: Documentation build (Documenter + Literate)
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1.11'
      - uses: julia-actions/cache@v2
      - name: Build docs
        run: julia --project=docs docs/make.jl
        env:
          CI: 'true'
```
Mirrors the `format` job's shape exactly (checkout → setup-julia pinned to a single
version '1.11' → the actual check step) — same structural template, different payload.
Do not add a `version` matrix (Pitfall 6: docs content is Julia-version-invariant).

## Shared Patterns

### Real-entrypoint-only rule (applies to every literate page AND the acceptance test)
**Source:** `docs/literate/toy_dc.jl` lines 30-33/65-72 (calls `solve_toy_dc`, never
reimplements it); `test/test_ieee123_admm.jl` lines 51-68 (calls `solve_welfare` /
`solve_admm`, never a hand-rolled JuMP model).
**Apply to:** all 5 new literate pages + `test_acceptance.jl`.
Every number rendered or asserted must come from calling `operational_oracle`,
`solve_welfare`, `solve_admm`, `extract_dlmp`, `fit_baseline`, `welfare_accounting`,
`assert_socp_exact!`, `ieee13_modified`, `ieee123_modified`, `run_scenario` — never a
parallel/duplicate JuMP formulation.

### Golden-pin convention (inline typed constant + rtol/atol)
**Source:** `test/test_ieee13.jl` lines 185-189 (`GOLDEN_V9_16`, `GOLDEN_WELFARE`,
`GOLDEN_DADP16`, `GOLDEN_SUM_DADP`, `THESIS_V9_16`); `test/test_pricing_welfare.jl`
line 324 (`RATIO_GOLDEN`).
**Apply to:** `test_acceptance.jl`, the `test_pricing_fit.jl` extension.
```julia
const GOLDEN_X = 1.234567  # captured from the first trusted solve
@test isapprox(computed, GOLDEN_X; atol = 1e-4)   # HARD regression gate
```
Never externalize to JLD2/CSV for unit-test goldens (CONTEXT.md lock; that tier is
Phase-8 experiment-harness only).

### Non-failing thesis cross-check (`@info` + `broken` test)
**Source:** `test/test_ieee13.jl` lines 207-218; `test/test_pricing_welfare.jl` lines
330-338.
**Apply to:** any place `test_acceptance.jl` or the literate pages reference the thesis
$1819/+25%/v≈1.0493 headline numbers.
```julia
gap = abs(computed - THESIS_VALUE)
@info "cross-check" computed = computed thesis = THESIS_VALUE gap = gap
@test gap < TOL broken = (gap >= TOL)   # NEVER reddens the suite
```

### CairoMakie weakdep gating (docs figures + core-purity check)
**Source:** `ext/TSODSOMakieExt.jl` (full file, 102 lines — `plot_convergence`,
`plot_price_convergence` methods, only defined when `using TSODSO, CairoMakie` both
load); `test/test_diagnostics_plot.jl` lines 16-37 (core-stays-plot-free assertion) and
lines 90-119 (separate-process with-CairoMakie check).
**Apply to:** `docs/literate/admm.jl` (and any other page embedding a convergence/price
figure), `docs/Project.toml`.
```julia
# Inside a literate page — guard so the SAME source degrades gracefully:
if Base.find_package("CairoMakie") !== nothing
    using CairoMakie
    plot_convergence(res)   # method resolves only because CairoMakie is loaded
end
```
Add `CairoMakie` as a normal `[deps]` entry in `docs/Project.toml` (docs-only hard dep
is fine — root `Project.toml`'s `[weakdeps]`/`[extensions]` block, lines 17-24 of that
file, stays untouched by this phase — that is the boundary to preserve).

### `ENV["CI"]` gate idiom (docs deploy + docs CI job)
**Source:** `docs/make.jl` line 28 (`prettyurls = get(ENV, "CI", nothing) == "true"`).
**Apply to:** the new `deploydocs(...)` call in `docs/make.jl`; reuse the exact same
`get(ENV, "CI", nothing) == "true"` boolean expression already established in this file
— do not introduce a different CI-detection mechanism.

## No Analog Found

None — every file this phase touches has a strong (exact or role-match) analog already
in the repository; RESEARCH.md's own "Don't Hand-Roll" table confirms no new mechanism
is needed anywhere in this phase.

## Metadata

**Analog search scope:** `docs/`, `test/`, `ext/`, `.github/workflows/` (entire
directories listed and cross-referenced against CONTEXT.md/RESEARCH.md's explicit
file/analog callouts).
**Files scanned:** `docs/make.jl`, `docs/literate/toy_dc.jl`, `docs/Project.toml`,
`docs/src/index.md`, `test/test_ieee13.jl`, `test/test_ieee123_admm.jl`,
`test/fixtures_phase4.jl`, `test/fixtures_phase7.jl`, `test/test_pricing_fit.jl`,
`test/test_fit.jl`, `test/test_pricing_welfare.jl`, `test/test_exactness.jl`,
`test/runtests.jl`, `ext/TSODSOMakieExt.jl`, `test/test_diagnostics_plot.jl`,
`.github/workflows/CI.yml`, root `Project.toml` (weakdeps section).
**Pattern extraction date:** 2026-07-20
