# Stack Research

**Domain:** Julia/JuMP TSO-DSO optimization framework — v3.0 "Research Extension Rungs" milestone
(five deferred research axes: overvoltage-capable relaxation, MPC/rolling-horizon/RTP, stochastic
PV/demand uncertainty, meshed networks + 4Q-BESS, discrete/integer investment expansion)
**Researched:** 2026-07-26
**Confidence:** HIGH on package versions/maintenance activity (verified live against the Julia General
registry `Versions.toml` and GitHub API commit/release timestamps, 2026-07-26); MEDIUM-HIGH on the
"no new package" architectural calls (reasoned by re-applying the project's own documented precedents
— the JuMP-vs-Convex.jl dual-access argument, the from-scratch-vs-PMD argument, the hand-rolled-Benders
argument — to each new axis, not independently re-litigated against a live implementation of each).

This is a **delta** stack document: it only covers what changes for v3.0. Everything already in
`Project.toml` (JuMP 1.30.1, MOI 1.51.2, Clarabel 0.11.1, HiGHS 1.24.1, Ipopt 1.15.0, SCS, CSV,
DataFrames, CairoMakie, DrWatson, SparseArrays, BilevelJuMP) is unchanged and re-used as-is. Prior
milestone stack rationale (v1.0/v2.0/v2.1) lives in `CLAUDE.md`'s Technology Stack section and the
archived `.planning/research/v1.0/` notes.

## Headline Answer

**Four of the five axes need zero new Julia packages.** The existing `select_optimizer` factory
(Clarabel/HiGHS/Ipopt, Gurobi/Mosek weakdep-gated) and the existing hand-rolled ADMM/Benders +
JuMP-`Parameter` build-once/re-solve idiom already cover everything these axes require — including
one previously-unverified fact that changes the calculus for two of them: **Clarabel already supports
the PSD cone** (`PSDTriangleConeT`, with chordal decomposition), so even an SDP-tightened relaxation
for meshed/overvoltage work needs no new solver package. The one axis with a real "should we adopt a
package" question — MPC/rolling-horizon (InfiniteOpt.jl, explicitly flagged for evaluation since v1's
CLAUDE.md) — is evaluated below and **rejected**, for the same dual-access reason Convex.jl was
rejected in the original stack decision, not because it is unmaintained (it is, in fact, actively
developed).

## Recommended Stack

### Core Technologies (no new main-dep additions)

All five axes run on the existing three-solver factory. Nothing here changes:

| Technology | Version | Purpose for v3.0 | Why no bump needed |
|------------|---------|-------------------|---------------------|
| **Clarabel** | 0.11.1 (confirmed still latest) | Conic backend for overvoltage-tightening (regularized/valid-inequality SOCP, or a PSD-tightened relaxation), the meshed bus-injection SOCP, and 4Q-BESS's reactive-capacity cone | Already handles `SecondOrderConeT` (used today) **and** `PSDTriangleConeT` with chordal decomposition, `ExponentialConeT`, `PowerConeT` — verified against Clarabel's own docs/README. No dedicated SDP solver (Mosek/COSMO/SDPT3) is needed even if a research direction calls for SDP-tightening. |
| **HiGHS** | 1.24.1 (confirmed still latest) | Benders master with binary-expansion integer investment variables (discrete/integer axis) | Already the project's LP/MILP solver; Benders decomposition's entire purpose is to confine integers to this LP/MILP master, so nothing beyond what's already wired is needed. |
| **Ipopt** | 1.15.0 (confirmed still latest) | Unchanged AC-exactness oracle (`ACPowerFlow`), reused as the correctness backstop for the overvoltage-tightened relaxation | Still the nonconvex NLP peer; the "pricing-capable" requirement for the overvoltage regime is a modeling change on top of the convex core, not something Ipopt itself needs to solve. |
| **JuMP** | 1.30.1 (current pin; 1.31.1 exists upstream — out of scope to re-pin this pass) | `Parameter`s for rolling-horizon state (SOC/temperature), scenario-indexed variables for the stochastic extensive form, `PSDCone()`/`SecondOrderCone()` constraint syntax for any relaxation tightening | All patterns below are native JuMP 1.x features already in use elsewhere in the codebase (ADMM/Benders `Parameter` idiom). |

### Supporting Libraries — evaluated, **none recommended for adoption**

| Library | Version (verified 2026-07-26) | Axis considered for | Verdict |
|---------|-------------------------------|----------------------|---------|
| **InfiniteOpt.jl** | 0.6.3 (released 2026-05-25; last commit 2026-07-06 — actively maintained; `JuMP = "1.29.3"` compat, fine with pinned 1.30.1) | MPC/rolling-horizon, stochastic | **Do not adopt** — see Deep-Dive §1. Architectural rejection, not a maintenance concern. |
| **StochasticPrograms.jl** | 0.6.4 (last commit **2022-09-04** — dead upstream, own CI matrix only ever tested Julia 1.6/1.8) | Stochastic PV/demand | **Do not adopt** — clear negative claim, verified via GitHub API, not a hunch. |
| **DualDecomposition.jl** | 0.3.4 (last commit 2024-08-01 — ~2yr stale, not dead) | Stochastic (Lagrangian scenario decomposition) | **Keep on the shelf**, unchanged from existing CLAUDE.md guidance — revisit only if scenario count later forces genuine Lagrangian decomposition; out of scope for a "minimal validated rung." |
| **Juniper.jl** | 0.9.4 (last commit 2026-03-17 — active; needs an NLP subsolver, e.g. Ipopt) | Discrete/integer investment | **Not needed** — solves monolithic MINLP; Benders keeps integers confined to the LP/MILP master, so no MINLP is ever formed. |
| **Pavito.jl** | 0.3.9 (last commit 2025-04-11) | Discrete/integer investment | **Not needed**, same reason as Juniper. |
| **BranchFlowModel.jl** | 0.5.0 (JuMP-native, `JuMP = "1"` compat) | Meshed networks | **Do not adopt** — niche/low-adoption (~2 GitHub stars), still fundamentally a radial-oriented Branch Flow Model package; same "more overriding than building" argument that rejected PowerModelsDistribution.jl for the operational core. |
| **PowerModels.jl** | 0.21.6 (`JuMP ≥ 1.15` compat, fine with 1.30.1) | Meshed/overvoltage formulation reference | **Reference only — zero runtime or test dependency.** Its `QCWRPowerModel`/`SOCWRPowerModel` formulations are useful to *read* as a literature reference for the meshed bus-injection model and any QC-style tightening, mirroring the existing PM/PMD-as-reference pattern — but per the more aggressive v2.1 precedent (dropping PMD entirely from runtime deps in favor of a ~50-line dependency-free OpenDSS parser), do not even wire it in as a test dependency. |
| **COSMO.jl** | 0.8.11 (active, last commit 2026-07-07) | Considered as an SDP-capable alternative solver | **Not needed** — first-order ADMM-style conic solver, same accuracy caveat already documented against SCS ("do not use for exactness certification or final duals"). Clarabel already covers the PSD cone natively with IPM accuracy. |

### Development Tools (unchanged)

No new dev-tool additions for v3.0. TestItems/TestItemRunner, JuliaFormatter, Documenter+Literate,
Aqua, JET, BenchmarkTools all carry over unchanged; each new rung gets its own `@testitem`s and (per
the "rich documentation" constraint) a Literate page, exactly as v1.0/v2.0/v2.1 did.

## Installation

```julia
# No Project.toml [deps]/[weakdeps] changes are recommended for v3.0.
# All five axes are new *code* (formulations, orchestration loops, cut-generation logic)
# on the EXISTING solver factory and dependency set.

# If, contrary to this research, the team later wants PowerModels.jl purely as a
# dev-time formulation cross-check (NOT recommended as a default — see "What NOT to Use"):
# Pkg.add(Pkg.PackageSpec(name = "PowerModels", version = "0.21.6"))  # would need to be a
# weakdep + extension, mirroring the existing Gurobi/Mosek/CairoMakie/PMD pattern, never [deps].
```

## Per-Axis Verdict

### 1. Overvoltage-capable relaxation — NO new packages
The v2.1 finding is that the radial SOCP relaxation goes inexact under high-PV reverse flow because
the loss inequality `l·v ≥ P²+Q²` stops binding (no incentive to minimize losses once the net nodal
injection reverses sign) — the classic Gan/Li/Topcu/Low exactness-failure mode for radial branch-flow
relaxations. This is a **modeling** fix, solved by the same optimizer already in the factory:
- **Restoration term**: add a small linear penalty on `l_ij` (or `ε·Σl_ij`) to the objective inside the
  existing `ConvexBranchFlow`/`DSO-OPT` JuMP model — the standard exactness-restoring trick in the
  relaxation literature, requiring only an `@objective` edit and a documented, validated `ε` sweep.
- **Valid-inequality tightening** (RLT/McCormick-style bound tightening on `v`, `l`, `P`, `Q`) —
  hand-written `@constraint`s in the same JuMP model; PowerModels.jl's `QCWRPowerModel` is a
  formulation reference to *read*, not a dependency (see table above).
- **If a tighter (SDP-style) relaxation is ultimately needed**: Clarabel already exposes
  `PSDTriangleConeT` with chordal decomposition — the single most load-bearing finding of this
  research pass. A `@variable(model, X[1:n,1:n], PSD)` / `X in PSDCone()` JuMP block solves on the
  exact same optimizer already in the factory; this forecloses any perceived need for a dedicated SDP
  solver (Mosek/SDPT3/COSMO) for this axis.
- The existing `ACPowerFlow` (Ipopt) oracle stays the correctness backstop; it does not itself satisfy
  the "pricing-capable" requirement (nonconvex, local KKT duals aren't certified global prices), so the
  convex tightening above is still the deliverable.

### 2. MPC / rolling-horizon / RTP — NO new packages (InfiniteOpt.jl evaluated and rejected)
CLAUDE.md flagged InfiniteOpt.jl for evaluation "when this milestone opens." Evaluated this pass:
- **Currently healthy upstream**: v0.6.3 (released 2026-05-25), last commit 2026-07-06, `JuMP =
  "1.29.3"` compat (clean against the pinned 1.30.1), solver-agnostic.
- **The rejection is architectural, not maintenance-related.** InfiniteOpt transcribes the
  infinite-dimensional model into a discretized JuMP model under the hood. Querying a dual requires
  `dual(c1)` on the *infinite* constraint handle, which returns an **array of duals across the
  transcribed support points**, or dropping to `transcription_constraint(c)`/`map_optimizer_index` on
  the underlying JuMP model for a single point (confirmed via InfiniteOpt's own docs, `guide/result.md`
  and `guide/transcribe.md`). This is exactly the indirection CLAUDE.md's Deep-Dive §1 already used to
  reject Convex.jl: *"recovering the dual of one original physical constraint is awkward and fragile —
  unacceptable when duals are your product."* The rolling DADP is precisely that per-step, per-node
  dual read.
- A live upstream GitHub discussion ("Warm starting an Optimal Control Problem,"
  infiniteopt/InfiniteOpt.jl discussions #338) shows warm-starting across re-solves is not a
  first-class, batteries-included feature — a second signal against adopting it for a workload whose
  entire performance model is "build once, re-solve many, warm-start."
- **Recommended path**: extend the already-proven idiom used for ADMM/Benders. The multi-period
  operational JuMP model already exists; wrap it in an outer Julia loop that (a) pins battery-SOC /
  thermostatic-temperature state via the same JuMP `Parameter` mechanism already used for `λ_j, μ_j, ρ`
  in ADMM, (b) slides the horizon window, (c) re-solves with `set_start_value` warm starts, (d) records
  the first-step decision + that step's DADP as the rolling RTP signal. Zero new dependencies; this is
  architecturally identical to the ADMM outer loop already in the codebase.

### 3. Stochastic PV/demand uncertainty — NO new packages
- **StochasticPrograms.jl is dead upstream** (last commit 2022-09-04, own CI matrix only ever tested
  Julia 1.6/1.8) — do not adopt; a clear, verified negative claim.
- **DualDecomposition.jl** (Argonne, Lagrangian dual decomposition for stochastic MIPs) is stale (last
  commit 2024-08-01) but not dead. Per existing CLAUDE.md guidance, keep it shelved: the v3.0 scope is
  a "minimal validated rung" (a seeded Markov scenario generator already exists per PROJECT.md), which
  the extensive-form approach handles directly.
- **Recommended path**: build the deterministic-equivalent extensive form directly in JuMP —
  scenario-indexed variables (`@variable(m, p[s in scenarios, t in 1:T])`), probability-weighted
  objective, solved by the same Clarabel/HiGHS factory — exactly the pattern already sketched in
  CLAUDE.md's "Stack Patterns by Variant" ("Scenario-based extensive form ... first"). DrWatson
  (already a dependency) handles scenario-tree bookkeeping/provenance. Revisit DualDecomposition.jl
  only if a later, paper-grade milestone needs genuine scenario-count scaling a monolithic extensive
  form can't handle in reasonable build/solve time.

### 4. Meshed networks + 4Q-BESS — NO new packages
- **4Q-BESS** is a modeling addition only: a genuine reactive decision variable `q_bess` inside the
  existing `SecondOrderCone` apparent-power-capacity constraint pattern (`[s_max; p; q] in
  SecondOrderCone()`), unlocking the reactive dual-ascent already deferred in v2.1 (`qag_dso` was a
  fixed constant because DERs were active-only under thesis A3; a real Q variable now needs a live
  μ-dual update in the ADMM loop, reusing the ADMM machinery already built for the active-power
  dual-ascent). Zero new packages.
- **Meshed topology** breaks the LinDistFlow linear voltage-drop recursion (which assumes a tree). The
  project's own from-scratch-with-reference precedent generalizes cleanly: hand-write a
  **bus-injection-model SOCP** (Jabr-style, generalizing the branch-flow cone off the radial recursion)
  in the same JuMP model, still solved by Clarabel.
- Evaluated and **rejected as runtime/even test dependencies**: BranchFlowModel.jl (JuMP-native,
  v0.5.0, but niche/low-adoption and still fundamentally a radial Branch Flow Model package — same
  "more overriding than building" argument that rejected PMD originally) and PowerModels.jl (0.21.6,
  whose `QCWRPowerModel`/`SOCWRPowerModel` meshed-capable formulations are read as a **formulation
  reference only**, mirroring the PM/PMD precedent — and per the more aggressive v2.1 precedent
  (dropping PMD entirely rather than keeping it as a weakdep for IEEE-123 impedances), do not even wire
  it in as a test dependency).
- **If exactness needs a tighter relaxation on the meshed case**: same Clarabel PSD-cone finding as
  axis 1 applies — no new solver.

### 5. Discrete/integer investment expansion — NO new packages
- The Benders master (HiGHS, already pinned 1.24.1 — confirmed current) is exactly the tool for
  binary-expansion integer investment variables: HiGHS is a full LP/MILP solver, and Benders
  decomposition's entire point is to keep integer variables confined to the LP/MILP master while
  subproblems (continuous investment-cost/operational recourse) stay LP/SOCP, solved by HiGHS/Clarabel
  as today. No monolithic mixed-integer-nonlinear problem is ever formed.
- **Juniper.jl** (0.9.4, active, MINLP branch-and-bound heuristic needing an NLP subsolver like Ipopt)
  and **Pavito.jl** (0.3.9, convex-MINLP outer-approximation) were evaluated because "integer +
  nonlinear" sounds MINLP-shaped at first glance — but neither is needed **because Benders
  decomposition is precisely the technique that avoids ever solving a monolithic MINLP.** Keep both on
  the shelf, same footing as PATHSolver/Complementarity.jl in existing CLAUDE.md: relevant only if the
  architecture is deliberately changed to pose the planning layer as a single monolithic (rather than
  decomposed) problem, which is not this milestone's scope.
- The only real new code need is **integer/Lagrangian (integer L-shaped) cut generation** inside the
  hand-rolled Benders loop — a cut-generation algorithm, not a package. `@constraint` cut rows
  accumulate exactly as the continuous optimality/feasibility cuts already do (per Phase 12's
  `BendersTrace`/cut-store instrumentation) — the PVAL-04 no-binaries guard is scoped down (not
  deleted) to allow binaries in the master only, per PROJECT.md's stated intent.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|--------------|-------------|--------------------------|
| Hand-rolled objective-regularization / valid-inequality tightening on the existing SOCP (axis 1) | Full nonconvex AC-OPF (`ACPowerFlow`/Ipopt) as the "pricing" formulation | Never as the default — nonconvex local duals aren't a certified global price; the existing AC oracle stays the correctness backstop, not the pricing formulation. |
| Clarabel's native `PSDTriangleConeT` for any SDP-tightened relaxation (axes 1, 4) | Mosek (`MosekTools`) | Licensed environment; gold-standard SDP accuracy/robustness at scale — same posture already documented for Clarabel-vs-Mosek on SOCP. |
| Hand-rolled JuMP-`Parameter` rolling-horizon loop (axis 2) | InfiniteOpt.jl | If a future milestone deliberately wants a declarative infinite-dimensional modeling *front end* and is willing to accept per-support-point dual indirection as an acceptable cost — not recommended given the DADP-as-dual requirement. |
| Hand-rolled deterministic-equivalent extensive form (axis 3) | DualDecomposition.jl | If scenario count later grows enough that a monolithic extensive form becomes intractable to build/solve — a genuinely later, paper-grade milestone concern, not v3.0's "minimal validated rung." |
| Hand-written bus-injection SOCP for meshed networks (axis 4) | PowerModels.jl `SOCWRPowerModel`/`QCWRPowerModel` (as a *reference*, never a dependency) | If the team wants a published, independently-audited meshed formulation to *read* while writing the from-scratch version — feasible today (PM 0.21.6, JuMP ≥1.15 compat) but not recommended to add even as a test dependency, per the v2.1 zero-PMD-runtime-dep precedent. |
| HiGHS MILP master + hand-rolled integer/Lagrangian cuts (axis 5) | Juniper.jl / Pavito.jl | Only if the architecture changes to require solving a genuine monolithic MINLP rather than a Benders-decomposed problem — not this milestone. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| **InfiniteOpt.jl for MPC/rolling-horizon or stochastic modeling** | Actively maintained and technically correct, but its transcription layer interposes between the researcher and a *specific* constraint's dual — the same "hides the dual seam" problem that already ruled out Convex.jl for the framework core; thin evidence of first-class warm-start support for the "re-solve every step" workload this axis needs | Extend the existing JuMP-`Parameter` build-once/re-solve idiom already proven for ADMM/Benders |
| **StochasticPrograms.jl** | Dead upstream (last commit 2022-09-04, CI only ever tested Julia 1.6/1.8) | Hand-rolled deterministic-equivalent extensive-form JuMP model |
| **DualDecomposition.jl for v3.0** | Stale (~2yr, last commit 2024-08-01); the scenario-count scale that would justify it is out of "minimal validated rung" scope | Extensive-form JuMP model now; revisit only if a later milestone needs genuine scenario-scale decomposition |
| **Juniper.jl / Pavito.jl for the planning master** | Solve monolithic MINLP; Benders decomposition's entire purpose is to avoid ever forming one | HiGHS MILP master (binary expansion) + Clarabel/HiGHS continuous subproblems, unchanged |
| **BranchFlowModel.jl** | Niche (~2 stars), radial-oriented, JuMP-native but would require overriding more than it saves — same argument that rejected PowerModelsDistribution.jl originally | Hand-written bus-injection SOCP generalization of the existing from-scratch model |
| **PowerModels.jl as a runtime or test dependency for meshed/overvoltage work** | Per the v2.1 precedent (PMD dropped entirely from runtime deps in favor of a dependency-free parser), even a "reference-only" dependency is avoidable — its formulations are public and readable without adding the package | Read `QCWRPowerModel`/`SOCWRPowerModel` source as a literature/formulation reference only |
| **COSMO.jl or SCS for any relaxation-tightening SDP work** | First-order accuracy — same caveat already documented against SCS for exactness certification/final duals | Clarabel's native `PSDTriangleConeT` (chordal decomposition), same IPM accuracy already relied on for SOCP |

## Stack Patterns by Variant

**Overvoltage-capable relaxation (axis 1):**
- Add an `ε·Σ l_ij` (or similar) restoration term to the existing `ConvexBranchFlow`/`DSO-OPT`
  objective; validate against the AC oracle (`assert_ac_exact!`) across the `pv_scale` sweep that
  originally surfaced the v2.1 inexactness finding. If insufficient, add hand-written valid
  inequalities (McCormick/RLT-style) or a `PSDCone()`-based tightening — same Clarabel solve either way.

**MPC / rolling-horizon / RTP (axis 2):**
- Reuse the existing multi-period JuMP model; wrap it in an outer loop with JuMP `Parameter`s pinning
  battery-SOC/thermostatic-temperature state, sliding-window re-solve with warm starts
  (`set_start_value`), record first-step decision + DADP per step, benchmark against the perfect-
  foresight day-ahead solve. No InfiniteOpt.jl.

**Stochastic PV/demand uncertainty (axis 3):**
- Build scenarios via the existing seeded Markov generator; construct one JuMP model with
  scenario-indexed variables and a probability-weighted objective (deterministic equivalent /
  extensive form); solve with Clarabel; document stochastic DADP semantics as the dual of the
  scenario-weighted nodal balance. No StochasticPrograms.jl, no DualDecomposition.jl.

**Meshed networks + 4Q-BESS (axis 4):**
- New bus-injection SOCP formulation (Jabr-style) replacing the radial LinDistFlow recursion for this
  rung only (existing radial rungs untouched); add `q_bess` as a real decision variable inside the
  existing apparent-power cone; wire a live μ-dual update into the ADMM loop mirroring the existing
  λ-dual pattern. Same Clarabel solve; PowerModels.jl read only as a formulation reference, never added
  as a dependency.

**Discrete/integer investment expansion (axis 5):**
- Binary-expansion of continuous investment variables in the Benders master (HiGHS, unchanged);
  hand-rolled integer/Lagrangian (integer L-shaped) cut generation added to the existing
  `BendersTrace`/cut-store machinery; PVAL-04 no-binaries guard scoped down (not deleted) to the master
  only. No Juniper.jl/Pavito.jl.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|------------------|-------|
| InfiniteOpt 0.6.3 | JuMP ≥ 1.29.3 | Compatible with the pinned JuMP 1.30.1; rejected on architectural grounds (see Deep-Dive §2), not compatibility. |
| Clarabel 0.11.1 | `PSDTriangleConeT` (chordal decomposition), `ExponentialConeT`, `PowerConeT`, `GenPowerConeT` | Confirmed via Clarabel docs/README — SDP-capable natively; no separate SDP solver package needed for meshed/overvoltage tightening. |
| PowerModels 0.21.6 | JuMP ≥ 1.15 | Fine with 1.30.1 if ever read/run standalone for reference; not recommended as a project dependency. |
| Juniper 0.9.4 | JuMP `1`, needs Ipopt/HiGHS/SCS as subsolvers | Would work if a monolithic MINLP were ever formed; not applicable to the Benders-decomposed planning layer. |
| Pavito 0.3.9 | JuMP `0.22, 0.23, 1` | Same non-applicability as Juniper; also the least actively maintained of the packages evaluated (last commit 2025-04-11). |
| BranchFlowModel 0.5.0 | JuMP `1` | Technically drop-in; rejected on adoption-risk/architecture-fit grounds, not compatibility. |
| HiGHS 1.24.1 / Ipopt 1.15.0 / Clarabel 0.11.1 | JuMP 1.30.1, Julia ≥ 1.10 | Unchanged from the existing project stack; confirmed still latest published releases as of 2026-07-26. |

## Sources

- **Julia General registry `Versions.toml`** (raw.githubusercontent.com/JuliaRegistries/General),
  fetched 2026-07-26 — HIGH confidence on all version numbers: InfiniteOpt 0.6.3, StochasticPrograms
  0.6.4, DualDecomposition 0.3.4, Juniper 0.9.4, Pavito 0.3.9, COSMO 0.8.11, PowerModels 0.21.6,
  BranchFlowModel 0.5.0, PowerModelsAnnex 0.11.0; and re-confirmed unchanged: JuMP 1.30.1 (current pin;
  1.31.1 exists upstream but out of scope to re-pin this pass), HiGHS 1.24.1, Ipopt 1.15.0, Clarabel
  0.11.1, DrWatson 2.19.1.
- **GitHub API commit/release timestamps** (`api.github.com/repos/.../commits`,
  `.../releases/latest`), fetched 2026-07-26 — HIGH confidence on maintenance-activity claims:
  InfiniteOpt last commit 2026-07-06 (release v0.6.3 on 2026-05-25); StochasticPrograms last commit
  2022-09-04 (dead); DualDecomposition last commit 2024-08-01; Juniper last commit 2026-03-17; Pavito
  last commit 2025-04-11; COSMO last commit 2026-07-07.
- **Package `Project.toml` `[compat]` sections** (raw.githubusercontent.com, per-package master
  branch), fetched 2026-07-26 — HIGH confidence on JuMP-compat claims for InfiniteOpt, Juniper, Pavito,
  COSMO, PowerModels, BranchFlowModel.
- **InfiniteOpt.jl official docs** (infiniteopt.github.io/InfiniteOpt.jl/stable/guide/result.md,
  guide/transcribe.md) + GitHub discussion #338 ("Warm starting an Optimal Control Problem") — MEDIUM-
  HIGH confidence on the dual-access-indirection and warm-start-immaturity findings that drove the
  rejection; both independently corroborate (docs describe the transcription indirection explicitly;
  the discussion is a live user asking how to do something the ADMM/Benders idiom already does).
- **Clarabel.jl official docs/README** (clarabel.org, github.com/oxfordcontrol/Clarabel.jl) — HIGH
  confidence on native PSD-cone (`PSDTriangleConeT`) + chordal-decomposition support — the load-bearing
  fact that forecloses adopting a dedicated SDP solver for axes 1 and 4.
- **Project context** — `.planning/PROJECT.md` (v3.0 milestone scope, five axes, "minimal validated
  rung" discipline, PVAL-04 no-binaries guard intent), `CLAUDE.md` (existing pinned stack, the
  JuMP-vs-Convex.jl dual-access argument re-applied here to InfiniteOpt, the from-scratch-vs-PMD
  argument re-applied here to BranchFlowModel.jl/PowerModels.jl, the hand-rolled-Benders/Coluna
  argument re-applied here to Juniper/Pavito), `.planning/research/v1.0/STACK.md` (original core-stack
  rationale, unchanged and re-used).

---
*Stack research for: TSO-DSO Integration Optimization Framework — v3.0 Research Extension Rungs*
*Researched: 2026-07-26*
