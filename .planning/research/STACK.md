# Stack Research

**Domain:** Julia/JuMP TSO-DSO optimization framework — v2.1 "Validation & Reproduction" milestone
(AC-OPF oracle, ADMM reactive consensus, real IEEE-123 impedance ingestion, directional thesis
reproduction)
**Researched:** 2026-07-25
**Confidence:** HIGH (versions verified against Julia General registry `Versions.toml`/`Deps.toml`;
PMD/OpenDSS API behavior verified against official PowerModelsDistribution docs)

This is a **delta** stack document: it only covers what changes for v2.1. Everything already in
`Project.toml` (JuMP 1.30.1, Clarabel 0.11.1, HiGHS 1.24.1, **Ipopt 1.15.0**, CSV, DataFrames,
CairoMakie, DrWatson, SparseArrays, StableRNGs) is unchanged and re-used as-is. Prior milestone
stack rationale (v1.0/v2.0) lives in `CLAUDE.md`'s Technology Stack section and the archived
`.planning/research/v1.0/` notes.

## Recommended Stack

### Core Technologies (no new main-dep additions)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|------------------|
| **Ipopt** | **1.15.0** (already a main dep — unchanged, confirmed still current) | Nonconvex NLP backend for the new AC-OPF oracle rung | Already wired behind `select_optimizer`; no version bump needed. It is *sufficient on its own* to solve a hand-rolled nonconvex AC bus-injection power-flow model — the missing piece for v2.1 target (a) is a **formulation**, not a solver. |
| **LinearAlgebra** (stdlib) | Julia-bundled | Fortescue/symmetrical-component (positive-sequence) reduction of 3×3 phase impedance matrices | The reduction is a fixed 3×3 unitary similarity transform (`A = [1 1 1; 1 a² a; 1 a a²]`, `a = exp(2πi/3)`) applied to a `Z_abc` matrix — nothing more than a change of basis. This is ~15 lines of code, not a library problem. **No package exists or is needed for this** (verified by search — no hit surfaced a Julia "Fortescue transform"/"symmetrical components" utility; only power-systems theory references and non-Julia tools appeared). Hand-roll it in `src/data/`, documented as a numbered helper (`fortescue_reduce(Zabc) -> (Z0, Z1, Z2)`), keeping only `Z1`. |

### Supporting Libraries (new optional/weak dependency)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|--------------|
| **PowerModelsDistribution.jl (PMD)** | **0.16.0** (confirmed latest published — no 0.16.1/0.17 exists yet) | Parse the real public OpenDSS IEEE-123 case (`IEEE123Master.dss` + `IEEELineCodes.DSS`) into a structured Julia dict, for one-time/occasional impedance ingestion only | **Add it now — this is exactly the milestone CLAUDE.md already earmarked PMD for** ("Data-import oracle — PMD parses OpenDSS"). `PowerModelsDistribution.parse_file("IEEE123Master.dss")` natively follows the file's internal `Redirect`/`Compile` directives (so `IEEELineCodes.DSS`, load files, etc. load automatically — no manual multi-file wiring) and returns the `ENGINEERING` dict with `eng["line"]` (per-segment `linecode` reference + `length`) and `eng["linecode"]` (`rs`/`xs` 3×3 Ω/length matrices). **Do not call `transform_data_model`/`eng2math`** — that produces PMD's own per-unit multiconductor MATHEMATICAL bus/branch model, a second, PMD-flavored per-unit convention layered on top of data this milestone only needs as raw Ω. Instead walk `eng["line"]`/`eng["linecode"]` directly, multiply `rs`/`xs` by segment length to get Ω, then apply the hand-rolled Fortescue reduction (above) to collapse each 3×3 (or 2×2/1×1, for single/two-phase laterals) matrix to a scalar positive-sequence `(r,x)` pair per branch, expressed in the framework's own `IEEE123_BASE` per-unit convention. |

### Development Tools (unchanged)

No new dev-tool additions for v2.1. Existing TestItems/TestItemRunner, JuliaFormatter, Documenter+Literate, Aqua, JET all carry over unchanged; the new AC-OPF rung and the PMD-ingestion extension each get their own `@testitem`s and (per the "rich documentation" constraint) a Literate page.

## Installation

```julia
# In the project environment (activate the repo, then):

# (a) AC-OPF oracle — NO new package. Ipopt is already a main dep.
#     New code: a 4th `AbstractPowerFlow` concrete type (e.g. `TrueACPowerFlow`) in
#     src/powerflow/, dispatched exactly like DCPowerFlow/LinDistFlow/ConvexBranchFlow,
#     solved via select_optimizer(NLP()) (add an `NLP` problem-class trait if not already present).

# (b)/(c) Real IEEE-123 impedance ingestion — PMD as a WEAKDEP + package extension
#     (mirrors the existing Gurobi/Mosek/CairoMakie weakdep+ext pattern already in Project.toml).
Pkg.add(Pkg.PackageSpec(name = "PowerModelsDistribution", version = "0.16.0"))  # dev-only / weakdep

# Project.toml additions (weakdeps + extensions section, NOT [deps]):
# [weakdeps]
# PowerModelsDistribution = "d7431456-977f-11e9-2de3-97ff7677985e"
# [extensions]
# TSODSOOpenDSSExt = "PowerModelsDistribution"
# [compat]
# PowerModelsDistribution = "0.16"
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|--------------|-------------|--------------------------|
| Hand-rolled nonconvex AC bus-injection formulation in JuMP + Ipopt (new `AbstractPowerFlow` rung) | `PowerModels.jl` `ACPPowerModel` (single-phase-equivalent polar AC-OPF) or PMD's `ACPUPowerModel` as the oracle | If the team ever wants a *published, independently-audited* formulation rather than an in-house one for the "true AC" reference. Feasible today since PMD 0.16 **no longer hard-depends on PowerModels.jl** (dropped after PMD 0.10 — confirmed via registry `Deps.toml`), so pulling in `PowerModels.jl` would be a second, separate, deliberate addition, not a PMD transitive freebie. Rejected as the *default* choice here because PowerModels'/PMD's bus/generator/branch data model doesn't map cleanly onto this project's custom prosumer/aggregator net injections (the same argument CLAUDE.md already uses against building the SOCP core on PMD/PM) — you'd spend the effort translating solved net nodal injections into a synthetic generator-per-bus dict instead of writing ~40 lines of polar power-balance equations directly against the existing `Feeder` struct, with byte-identical topology/impedance data (zero mapping seam, zero risk of a silent unit/convention mismatch between the SOCP and AC oracle). |
| PMD data-import path (`eng["line"]`/`eng["linecode"]`, no `transform_data_model`) | PMD's full `transform_data_model` → MATHEMATICAL per-unit dict | If a future milestone needs PMD's own multiconductor per-unit OPF machinery (e.g., a genuine unbalanced 3-phase extension) rather than just raw Ω impedances to reduce by hand. Out of scope for v2.1 (project stays balanced positive-sequence). |
| PMD as a **weakdep + extension** | PMD as a **main dependency** | Never, for this milestone — PMD ingestion is a one-time/occasional data-regeneration step, not something 99% of `using TSODSO` sessions touch. A main dep would force every researcher (and CI matrix run) to precompile PMD's dependency chain even when doing pure operational/planning-layer work with no OpenDSS involvement. |
| PMD as a **weakdep + extension** | PMD confined to a **standalone script with its own nested `Project.toml`**, fully decoupled from the package manifest | Viable and lower-friction (matches the `scripts/` DrWatson convention already in this repo, e.g. `scripts/thesis_caseA.jl`). Prefer the weakdep+extension over this **only if** the ingestion should be a live, checked, re-derivable regression (a test that re-parses the DSS files and asserts the committed `IEEE123_BRANCH_DATA` still matches, catching silent drift) — that fits the project's reproducibility/traceability mandate better than an unchecked one-off script. If that regression isn't valued, the standalone-script route is simpler and keeps `Project.toml` untouched entirely; either is defensible, but the weakdep route keeps the ingestion logic living *inside* the documented, tested package per CLAUDE.md's "every model assumption documented" constraint. |
| Fortescue reduction hand-rolled with stdlib `LinearAlgebra` | Any third-party "symmetrical components" package | None found in the Julia ecosystem (verified by search — only power-systems-theory references and non-Julia tools surfaced). Do not add a dependency for a fixed 3×3 matrix transform. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| Building the AC-OPF oracle **on top of PowerModels.jl or PowerModelsDistribution's `ACPPowerModel`/`ACPUPowerModel` formulations** | Same data-model mismatch CLAUDE.md already flags for the SOCP core: PowerModels'/PMD's generator/bus/branch templates don't map onto this project's aggregator-driven net nodal injections; more translation overhead than value for an oracle whose whole point is per-branch/per-bus traceability to thesis equations 3.31–3.39. | Hand-rolled nonconvex polar (or rectangular) AC power-flow equations as a new `AbstractPowerFlow` rung, solved via the already-wired Ipopt, on the SAME `Feeder`/`Branch`/`Bus` structs the SOCP model already uses. |
| Adding PMD to `[deps]` (main dependency) | Bloats precompile/install for every researcher and CI job; PMD ingestion is occasional, not part of the live runtime API surface. | `[weakdeps]` + a package extension (`TSODSOOpenDSSExt`), exactly mirroring the existing `TSODSOGurobiExt`/`TSODSOMosekExt`/`TSODSOMakieExt` pattern already in `Project.toml`. |
| Calling PMD's `transform_data_model`/`eng2math` for this milestone | Produces PMD's own per-unit multiconductor MATHEMATICAL model — a second, foreign per-unit convention layered on top of data this milestone only needs as raw Ω impedances. | Read `eng["line"]`/`eng["linecode"]` directly from the `ENGINEERING` dict `parse_file` already returns; do the Ω→pu conversion once, in the framework's own `PerUnitBase` (`IEEE123_BASE`), exactly as `ieee123.jl` already does for the head-branch `S_max`. |
| Assuming PMD still transitively pulls in `PowerModels.jl`/`Memento` | **Outdated** — verified against the registry: PMD dropped `PowerModels` and `Memento` as dependencies after version 0.10 (now uses stdlib `Logging`/`LoggingExtras` instead of `Memento`). Current PMD 0.16 deps are `InfrastructureModels`, `JuMP`, `CSV`, `PolyhedralRelaxations`, `FilePaths`, `Glob`, `SpecialFunctions`, `Graphs`, `JSON`, `LoggingExtras` + stdlibs (`LinearAlgebra`, `Dates`, `Logging`, `SparseArrays`, `Statistics`). | Treat PMD 0.16 as a moderate — not enormous — transitive footprint; still a weakdep, but the "it drags in the whole PowerModels ecosystem" fear from older PMD versions no longer applies. |
| Modeling the reactive-power (μ) ADMM consensus as anything other than a mirror of the existing active-power (λ) consensus pattern | `AgrOpt.jl`'s `qag` field is explicitly documented as a placeholder for exactly this extension (`AgrOpt.jl:48`, "no reactive dual update exists yet... kept as the documented seam"); a bespoke reactive-consensus mechanism would diverge from the thesis's symmetric λ/μ dual-ascent structure (eq. 3.46) and from the ADMM-03 build-once/re-solve discipline already proven for `pag`. | Mirror `pag`/`λ_j` exactly: promote `qag` from a constant vector to a genuine coupling variable pinned the same way `pag` is pinned (thesis 3.22/3.23 symmetry), add a `μ_j` dual-ascent update alongside the existing `λ_j ← λ_j + ρ·R_{p,j}` in `solve_admm.jl`, and reuse `set_objective_coefficient`/`set_rho!` verbatim for the new quadratic/linear reactive terms — **no new package required**, this is pure orchestration-layer work already scoped by the existing ADMM machinery. |

## Stack Patterns by Variant

**AC-exactness certification (v2.1 target 1):**
- Fix the SOCP-solved (or ADMM-converged) net nodal active/reactive injections `p_inject[j,t]`, `q_inject[j,t]` as constants (or JuMP `Parameter`s, for repeated re-solves) on a NEW `TrueACPowerFlow <: AbstractPowerFlow` rung.
- Write the standard nonconvex bus-injection AC power-flow equations directly against the existing `Feeder`/`Branch` structs (variables: voltage magnitude `|V_j|` and angle `θ_j`, or rectangular `(e_j,f_j)`; branch flow via the admittance `y = 1/(r+jx)`). `Ipopt` via `select_optimizer(NLP())` (extend the existing solver-selection trait with an `NLP()` problem class if not already present) solves it directly — no cone, no relaxation.
- Compare voltages/branch flows to the SOCP solution; report the deviation alongside the existing `assert_socp_exact!` cone-gap as a second, independent correctness signal.
- Optionally, ALSO run PMD's `ACPPowerModel`/plain OPF on a no-DER baseline (as CLAUDE.md's existing "Cross-validation" bullet already suggested) as a cheap secondary smoke-check — not the primary certification path, and would require the separate `PowerModels.jl` addition discussed above (not recommended as a default for v2.1).

**Reactive-power (μ) ADMM consensus (v2.1 target 2):**
- No new package. Pure extension of `src/admm/AgrOpt.jl` + `DsoOpt.jl` + `solve_admm.jl`, mirroring the existing active-power pattern (see "What NOT to Use" row above).

**Real IEEE-123 impedances (v2.1 target 3):**
- `PowerModelsDistribution.parse_file` (weakdep+extension) → walk `eng["line"]`/`eng["linecode"]` → per-segment Ω `rs`/`xs` (length-scaled) → hand-rolled Fortescue reduction (`LinearAlgebra`, stdlib) → scalar positive-sequence `(r,x)` per branch → feed into `IEEE123_BRANCH_DATA` in the framework's existing `IEEE123_BASE` per-unit convention. Regenerate as a **committed artifact** (e.g. `data/ieee123_impedances.jl` or `.csv`) so `src/data/ieee123.jl` never needs PMD loaded at ordinary runtime — only the (optional, weakdep-gated) regeneration/regression path does.

**Directional thesis reproduction (v2.1 target 4):**
- No stack changes — this is a scenario/goldens exercise on the already-existing `Scenario`/`run_scenario` + DrWatson `tagsave` machinery, using the newly-real IEEE-123 data as input.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|------------------|-------|
| PowerModelsDistribution 0.16.0 | JuMP ≥ 1.23.2 (project has 1.30.1) | Confirmed via registry `Compat.toml`: `["0.16-0"] JuMP = "1.23.2-1"` — no conflict with the project's pinned JuMP 1.30.1. |
| PowerModelsDistribution 0.16.0 | Julia ≥ 1.10 | No native binary deps beyond its own Julia-package tree; consistent with the project's Julia 1.10 LTS floor. |
| PowerModelsDistribution 0.16.0 | **Does NOT depend on PowerModels.jl or Memento** | Verified via registry `Deps.toml`: `PowerModels`/`Memento` deps only existed for PMD `0-0.10`; dropped since. Adding PMD 0.16 as a weakdep does *not* transitively install `PowerModels.jl`. |
| Ipopt 1.15.0 | JuMP 1.30.1, Julia ≥ 1.10 | Unchanged from the existing project stack; confirmed still the latest published Ipopt.jl release (registry `Versions.toml` — no 1.16.x published as of 2026-07-25). |

## Sources

- **Julia General registry** (`raw.githubusercontent.com/JuliaRegistries/General`) `Versions.toml`/`Deps.toml`/`Compat.toml` for `PowerModelsDistribution`, `PowerModels`, `InfrastructureModels`, `Ipopt`, `JuMP`, `Graphs`, `PolyhedralRelaxations`, `FilePaths`, `Glob`, `JSON`, `LoggingExtras`, `SpecialFunctions` — fetched 2026-07-25, HIGH confidence on all version numbers and dependency-graph claims (PMD 0.16.0 latest, dropped `PowerModels`/`Memento` deps after 0.10; Ipopt 1.15.0 still latest).
- **PowerModelsDistribution official docs** (`lanl-ansi.github.io/PowerModelsDistribution.jl/stable/manual/quickguide.html`, `.../dev/reference/data_models.html`) — HIGH confidence on `parse_file`/`transform_data_model` behavior, `ENGINEERING` `line`/`linecode` `rs`/`xs` fields, `apply_kron_reduction!`/`kron_reduce_implicit_neutrals!` (neutral-conductor Kron reduction — distinct from, and NOT a substitute for, the Fortescue positive-sequence reduction this milestone needs), and available formulations (`ACPUPowerModel`, `SDPUBFPowerModel`).
- **WebSearch** (multiple queries) confirming OpenDSS's `Redirect`/`Compile` multi-file convention is natively followed by PMD's parser (MEDIUM confidence, community/docs-derived, not a single authoritative doc page quoted verbatim) and confirming no Julia package implements a generic Fortescue/symmetrical-components transform (an absence-of-evidence claim, flagged honestly as needing validation at implementation time, but corroborated by the triviality of the math — a fixed 3×3 unitary matrix, not something requiring a package).
- **Project context** — `CLAUDE.md` Technology Stack section (existing PMD-as-oracle policy, solver-abstraction/weakdep-extension precedent via Gurobi/Mosek/CairoMakie), `.planning/PROJECT.md` (v2.1 milestone scope), `src/models/exactness.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/admm/AgrOpt.jl`, `src/data/ieee123.jl` (current implementation state, confirming the μ/`qag` placeholder and the synthetic-impedance provenance note this milestone replaces).

---
*Stack research for: TSO-DSO Integration Optimization Framework — v2.1 Validation & Reproduction*
*Researched: 2026-07-25*
