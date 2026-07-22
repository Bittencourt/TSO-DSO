# Phase 11: Single-Distributor Stackelberg-Benders (Certified) - Research

**Researched:** 2026-07-22
**Domain:** Hand-rolled Benders decomposition (JuMP/Julia) for a Stackelberg leader-follower
investment game, with a BilevelJuMP MPEC cross-certification gate
**Confidence:** MEDIUM-HIGH (Benders/JuMP/HiGHS/BilevelJuMP mechanics HIGH; the exact leader/
follower cut-composition structure MEDIUM, deliberately left for empirical certification per
CONTEXT.md/PITFALLS.md — this is the phase's own stated success criterion, not a research gap)

## Summary

Phase 11 turns the Phase-10 oracle seam (`PlanningOracle`/`solve_planning_oracle!`, returning
`(cost, π, π_s, dadp, ctx)` at a pinned coupling-flow trial `z`) into a working, certified
single-distributor Stackelberg-Benders loop. Three new files are needed
(`src/planning/follower.jl`, `src/planning/master.jl`, `src/planning/benders.jl`), each following
the build-once/re-solve idiom already proven in `subproblem.jl`/`retry.jl`/`checkpoint.jl`. The
follower is a genuinely new, small, declarative transmission-reinforcement LP — distinct from the
reused operational oracle — whose infeasibility path must return a **real HiGHS Farkas dual ray**
(not a penalized-slack shortcut). The master is a build-once JuMP LP (HiGHS) with a **finite lower
bound on the epigraph variable** (the single most common Benders footgun: an initial master with
an unbounded `α` is `DUAL_INFEASIBLE`, not a modeling bug) that accumulates optimality cuts (from
the oracle's `π`, Phase-10 D-05 form) and feasibility cuts (from the follower's Farkas ray) as
persistent `@constraint` rows, gated by the strict `assert_solved!(...; allow_almost=false)` on
every cut-producing solve.

The phase's hardest technical question — which of the two convex subproblems (operational oracle
vs. the new transmission follower) plays the Benders "follower" role, and what sign the coupling
dual `π_s` carries in the leader's cut — is **explicitly not resolved by re-reading the PSR
source** (it is self-flagged MEDIUM-confidence and internally inconsistent on this exact point,
per `THEORY-papers.md`/`PITFALLS.md`). It is resolved empirically by building a tiny BilevelJuMP
MPEC (`Upper()`/`Lower()` blocks, `BigMMode` with HiGHS and `StrongDualityMode` with Ipopt) on a
hand-enumerable toy instance and checking which reading of the Benders wiring reproduces the same
investment/import decision — success criterion 4. BilevelJuMP 0.6.3 is added as a **test-only**
dependency (`test/Project.toml`), never touching the shipped package's `[deps]`.

**Primary recommendation:** Build `follower.jl` (small LP, HiGHS, genuine Farkas rays) and
`master.jl` (build-once LP epigraph with a finite lower bound, HiGHS) as independently testable
units first, each cutting the SAME epigraph `α` via its own optimality/feasibility cut — then wire
`benders.jl`'s outer loop, then build the BilevelJuMP certification case, and let its answer (not
a fresh reading of the PSR note) pin the final leader/follower/sign contract encoded as a tested
invariant.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Operational welfare cost at pinned `z` (`(cost, π)`) | Operational subproblem (`PlanningOracle`, SOCP/QP via Clarabel — Phase 10, reused unmodified) | — | Already built and certified in Phase 10; Phase 11 only *consumes* `solve_planning_oracle!`, never edits `subproblem.jl`. |
| Transmission-reinforcement cost + Farkas certs at pinned `z` | Follower subproblem (NEW `follower.jl`, LP via HiGHS) | — | Genuinely new small model — PLAN-04's literal scope (Farkas certificates) lives here, not in the oracle. |
| Investment decision + cut accumulation | Benders master (NEW `master.jl`, LP via HiGHS) | — | Leader's own problem: continuous investment vars + `z[t]` + epigraph `α`, persistent cut rows. |
| Outer-loop orchestration, convergence gap, checkpointing | Orchestration loop (NEW `benders.jl`, plain Julia — no JuMP model of its own) | Persistence (`checkpoint.jl`, reused) | Ties master ↔ oracle ↔ follower together; calls `checkpoint_iteration!` once per Benders iteration (Phase 10 D-10). |
| Empirical leader/follower/sign certification | Validation oracle (NEW test-only BilevelJuMP model, `Upper()`/`Lower()`) | — | Weakdep-gated, parallel path; never called from `benders.jl`/`master.jl` — test suite only (mirrors `ext/TSODSOGurobiExt` isolation pattern). |
| Solve-status trust gate | Cross-cutting (`assert_solved!`, `solve_with_retry!`, reused) | — | Every cut-producing solve (oracle, follower, master) routes through the existing INFRA-03 choke point; no new gate is introduced. |

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Follower LP `α(z)` design (PLAN-04)**
- Follower model is a **minimal PSR-note-faithful LP**: linear transmission-reinforcement capacity
  cost + operation subject to delivering the import profile `z[t]`, over a small declarative,
  seeded transmission-corridor fixture (project conventions). No multi-node DC transmission network
  in this phase.
- Infeasibility certificates are **genuine Farkas/dual rays from HiGHS**
  (`dual_status == INFEASIBILITY_CERTIFICATE`; disable presolve if needed to obtain rays) →
  feasibility cuts. No penalized-slack "always feasible" shortcut — success criterion 1 demands a
  real certificate.
- **Single deterministic scenario** in Phase 11, but the API is **scenario-indexed** (`α(z; s)`
  shape) so Phases 12/13 scale without signature breaks. Stochastic solving itself stays deferred
  (v2.x).
- Solver wiring goes through the existing **`select_optimizer(::ProblemClass)`** abstraction
  (HiGHS for follower LP and master). No solver named inside model code.

**Benders master & loop mechanics (PLAN-05/06)**
- **Build-once JuMP master** (continuous investment variables + `z[t]` + epigraph `α`); optimality
  and feasibility cuts appended as **persistent constraint rows** — never rebuilt. Optimality cuts
  use the full length-`T` dual vector per Phase 10 D-05:
  `α ≥ cost^k + Σ_t π[t]·(z[t] − z^k[t])`.
- Convergence: **relative gap `(UB−LB)/max(1,|UB|) ≤ tol` (default 1e-6)**, documented formula,
  plus an iteration cap that **raises loudly** on exhaustion (never silent — Phase 10 D-10).
- **Every cut-producing solve** (oracle, follower, master) goes through `solve_with_retry!` and the
  strict `assert_solved!(...; allow_almost=false)` gate; `checkpoint_iteration!` fires per Benders
  iteration exactly as designed in Phase 10 D-10.
- Code organization: new files **`src/planning/follower.jl`, `src/planning/master.jl`,
  `src/planning/benders.jl`**, mirroring the established `build_*` / `solve_*!` build-once naming
  used by `subproblem.jl` and the ADMM modules.

**BilevelJuMP certification gate (PLAN-07, PVAL-01)**
- Certification uses **both `BigMMode` and `StrongDualityMode`** on a tiny leader/follower
  instance, cross-checked against a **hand-worked enumeration** of the same toy case — three
  independent answers must agree (success criterion 4).
- BilevelJuMP is a **test-only dependency** (`test/Project.toml`) — production code never depends
  on MPEC machinery, honoring CLAUDE.md's "validation oracle only" rule.
- The invariant is a **permanent fast `@testitem`** (tagged `[:planning]`) asserting the Benders
  equilibrium matches the BilevelJuMP optimum within tolerance AND asserting the certified
  dual-sign/role convention. Retained forever per success criterion 5 — not a one-off script.
- If certification contradicts the assumed leader/follower reading: **the empirical result is
  authoritative** — flip the convention in code + docs and record the resolution in
  STATE/PROJECT decisions. Phase 10 D-06 deliberately left the sign uncommitted for exactly this
  outcome. Do NOT re-resolve by re-reading THEORY-papers.md (STATE.md blocker).

### Claude's Discretion
- Exact toy-instance data for the certification case (must admit hand enumeration).
- Big-M bound derivation for `BigMMode` (this research pass covers Fortuny-Amat bound
  requirements — see Code Examples/Pitfalls below).
- Follower fixture parameterization (corridor capacity, reinforcement cost coefficients).
- Master warm-start strategy across Benders iterations.
- Whether `benders.jl` exposes a single `solve_stackelberg!` entry point or a small loop API.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Standing deferrals: integer investment, stochastic
scenarios, MCP/VI recast — tracked in STATE.md Deferred Items.) Also explicitly out of scope for
Phase 11: multiple distributors / Nash diagonalization (Phase 13), cut-store scale hardening
(Phase 12), integer/discrete investment (deferred milestone, PVAL-04 enforces continuous-only).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| PLAN-04 | Follower LP `α(z)` exposes coupling dual `π_s` + Farkas certificate for infeasible `z` | See "Follower LP: HiGHS Farkas certificates" (Code Examples, Pitfall F1); confirms `HiGHS.ComputeInfeasibilityCertificate()` defaults `true` but a presolve-detected primal infeasibility forces an internal no-presolve re-solve to get the ray — document, don't assume, and verify empirically on the actual fixture. |
| PLAN-05 | Build-once Benders master with persistent optimality + feasibility cut rows, strict `assert_solved!` gate | See "Architecture Patterns: Pattern 1 (build-once master + epigraph lower bound)" and the JuMP official Benders tutorial cut-accumulation pattern (Code Examples). |
| PLAN-06 | Single-distributor Stackelberg equilibrium converges end-to-end with documented UB/LB gap tolerance | See "Architecture Patterns: Pattern 2 (UB/LB gap convergence)" — official JuMP tutorial's exact gap formula, matched to CONTEXT.md's locked `(UB−LB)/max(1,|UB|) ≤ 1e-6`. |
| PLAN-07 | Leader/follower role + coupling-dual sign resolved empirically, encoded as a tested invariant | See "BilevelJuMP Certification" (Architecture Patterns, Code Examples, Pitfall B1/B2) — exact `BigMMode`/`StrongDualityMode` API surface, `DualOf`, solver-mode compatibility matrix. |
| PVAL-01 | Tiny BilevelJuMP single-level reduction certifies the equilibrium, retained as a permanent fast regression | See "BilevelJuMP Certification" + "Validation Architecture" (test file placement, tagging, test-only dependency wiring). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **JuMP, not Convex.jl** — direct constraint handles, named duals (`dual(pin)`, `dual(follower_coupling)`), JuMP `Parameter`s for cheap re-solves. Already the pattern in `subproblem.jl`; `follower.jl`/`master.jl` must follow it.
- **Clarabel primary conic solver** — unaffected by Phase 11 (only the oracle uses SOCP/QP; follower + master are LP → HiGHS per the factory).
- **HiGHS for LP/MILP** — the follower LP and the Benders master both route through `select_optimizer(LP())`. Never name HiGHS directly in `src/planning/*.jl`.
- **BilevelJuMP 0.6.3 as validation oracle only** — never the production solver; test-only dependency; never imported by `src/`.
- **Hand-roll ADMM and Benders** — no decomposition mega-framework (Coluna/StructJuMP). Confirmed still correct for Phase 11's continuous-only scope.
- **`select_optimizer(::ProblemClass)` is the sole solver-naming seam (INFRA-02)** — `follower.jl`/`master.jl` must call `Model(select_optimizer(LP()))`, never `Model(HiGHS.Optimizer)` directly. The BilevelJuMP certification test is the one place a bare solver constructor is unavoidable (see Pitfall B3) — document that exception explicitly in the test file header, don't silently violate the convention.
- **`assert_solved!`/`solve_with_retry!` are the sole solve-status choke points (INFRA-03)** — reused verbatim; no new gate.
- **JuliaFormatter v2, TestItems/TestItemRunner, Documenter+Literate** — new files follow the same `@testitem` `[:planning]`-tag convention as `test_planning_oracle.jl`/`test_planning_retry.jl`/`test_planning_checkpoint.jl`.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|---------------|
| JuMP | 1.30.1 (1.31.0 available; compat unaffected) [VERIFIED: local `Pkg.status()`, 2026-07-22] | Follower LP + Benders master model + cut constraints | Same modeling layer already used project-wide; direct constraint-handle duals are load-bearing for both Farkas rays and Benders cut coefficients. |
| HiGHS | 1.24.1 [VERIFIED: local `Pkg.status()` + `select_optimizer(LP())` already wired in `src/solver/factory.jl`] | Follower LP solve (Farkas rays) + Benders master LP solve | Already the project's `LP()`/`MILP()` default; supports affine (in)equalities/bounds, and computes infeasibility certificates by default (`HiGHS.ComputeInfeasibilityCertificate()`, default `true`) [CITED: jump.dev/JuMP.jl/stable/packages/HiGHS/]. |
| Clarabel | 0.11.1 [VERIFIED: local `Pkg.status()`] | Reused, unmodified — the operational oracle's SOCP/QP backend (Phase 10) | No change from Phase 10; Phase 11 never edits `subproblem.jl`'s solver routing. |

### Supporting — NEW for Phase 11 (test-only)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| BilevelJuMP.jl | 0.6.3 (current; registry entries confirmed live 2026-07-22 up through 0.6.3, repo `joaquimg/BilevelJuMP.jl`) [VERIFIED: Julia General registry `Package.toml`/`Versions.toml` fetched directly + official docs `joaquimg.github.io/BilevelJuMP.jl` fetched directly, 2026-07-22] | Tiny leader/follower MPEC certification (`BigMMode`, `StrongDualityMode`) | `test/Project.toml` only — never `Project.toml`. |
| Dualization.jl | 0.3.5 (transitive) [CITED: BilevelJuMP `Package.toml` deps list — pulled in automatically] | Builds the follower's KKT/dual problem for `StrongDualityMode` | Never depend on it directly; comes in via BilevelJuMP. |
| Ipopt | 1.15.0 [VERIFIED: local `Pkg.status()`, already wired via `select_optimizer(NLP())`] | Solver backend for BilevelJuMP's `StrongDualityMode`/`ProductMode` (bilinear strong-duality constraint when the follower's RHS depends on the leader's `z`) | Only inside the BilevelJuMP certification test — not used by `follower.jl`/`master.jl` themselves. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `BigMMode` (HiGHS) / `StrongDualityMode` (Ipopt) as the certification's two independent modes | `SOS1Mode` / `IndicatorMode` | Requires `MOI.SOS1`/`MOI.Indicator` support — **HiGHS.jl does not implement these** [CITED: `.planning/research/STACK.md`, re-verified against HiGHS.jl's supported-constraints list 2026-07-22 session] — reserve for an optional Gurobi-licensed run only, never the default open-source path. |
| Genuinely separate `follower.jl` LP as the Benders "follower" | Treating `PlanningOracle` itself as the follower (Reading A, per `THEORY-papers.md`'s "Natural architecture" paragraph) | CONTEXT.md's locked decision already picks the separate-follower structure (Reading B) for Phase 11's file layout; Reading A is not ruled out mathematically but is NOT the structure to build per the locked file list (`follower.jl` distinct from `subproblem.jl`). The BilevelJuMP certification is what empirically checks this wiring reproduces the correct decision — see Open Questions. |
| Single combined epigraph `α` fed by both the oracle's cut and the follower's cut | Two separate epigraph variables (`α_op`, `α_x`), i.e. classical "multi-cut" Benders | Multi-cut is more standard when a leader's cost-to-go decomposes into independent convex pieces (oracle cost + transmission cost) — each piece gets its own supporting-hyperplane cut and is independently unit-testable. CONTEXT.md's literal text describes ONE `α` receiving the oracle's D-05-form cut; whether the follower's cut lands on the SAME `α` (single-cut, summed subgradient) or a SEPARATE second epigraph term is left open — see Open Questions; both are valid convex-analysis-wise. |

**Installation:**
```julia
# In the project environment (activate the repo, then):
import Pkg

# Nothing new in the main Project.toml — follower.jl/master.jl/benders.jl depend ONLY on
# JuMP + the existing select_optimizer(LP()) factory already shipped.

# BilevelJuMP is a VALIDATION-ORACLE, test-only dependency:
Pkg.activate("test")
Pkg.add(Pkg.PackageSpec(name = "BilevelJuMP", version = "0.6.3"))   # pulls in Dualization + Reexport transitively
```
Add `BilevelJuMP = "0.6.3"` to `test/Project.toml`'s `[compat]` block, alongside the existing
`Aqua`/`JET`/`TestItemRunner` entries. Do **not** touch the root `Project.toml`.

**Version verification:** re-confirmed live against the Julia General registry today
(`raw.githubusercontent.com/JuliaRegistries/General/master/B/BilevelJuMP/{Package,Versions}.toml`)
— repo `https://github.com/joaquimg/BilevelJuMP.jl.git`, versions through `0.6.3` present. Root
`Project.toml` packages (JuMP, HiGHS, Clarabel, Ipopt) confirmed via local `Pkg.status()` against
the already-resolved `Manifest.toml` (Julia 1.12.5 installed on this machine, compat floor
unaffected).

## Package Legitimacy Audit

> This phase's only new dependency is a Julia package (BilevelJuMP.jl), not an npm/PyPI/crates
> package. `slopcheck` targets those ecosystems and does not recognize the Julia General registry
> — the ecosystem-appropriate verification here is the Julia General registry itself (the
> authoritative source of truth for Julia package identity, analogous to `npm view`/`pip index`).

| Package | Registry | Age | Activity | Source Repo | Ecosystem Check | Disposition |
|---------|----------|-----|----------|--------------|------------------|-------------|
| BilevelJuMP | Julia General | First registered 2020 (v0.1.0); current 0.6.3, last release 2026-03-13 [CITED: `.planning/research/STACK.md`, this session's registry fetch] | 356 commits, actively maintained | `github.com/joaquimg/BilevelJuMP.jl` (confirmed via registry `Package.toml`) | `Package.toml`/`Versions.toml` fetched directly — real UUID (`485130c0-...`), real repo URL, monotonic version history 0.1.0→0.6.3, no anomalous single-version-then-abandoned pattern | Approved |
| Dualization | Julia General | Long-established, current 0.3.5 [CITED: `.planning/research/STACK.md`] | Transitive only — pulled in by BilevelJuMP, never added directly | `github.com/jump-dev/Dualization.jl` (JuMP-ecosystem-owned) | Not independently re-verified this session (transitive, JuMP-dev-org-owned — low risk) | Approved (transitive) |

**Packages removed due to a `[SLOP]`-equivalent verdict:** none.
**Packages flagged as suspicious:** none — no anomalous registry signal found on either package.

*slopcheck itself was not run (Julia is out of its target ecosystem scope); the Julia General
registry cross-check above is the ecosystem-appropriate substitute, and both packages independently
verify against `joaquimg.github.io`/`jump-dev` official documentation fetched directly this
session — treat as [VERIFIED: Julia General registry + official docs], not `[ASSUMED]`.*

## Architecture Patterns

### System Architecture Diagram

```
                         ┌───────────────────────────────────────────┐
                         │        benders.jl (plain Julia loop)       │
                         │  solve_stackelberg!(...) — orchestration   │
                         └───────────────┬─────────────────────────────┘
                                         │  iterate k = 1, 2, ...
                                         ▼
        ┌──────────────────────────────────────────────────────────┐
        │  master.jl :: BendersMaster (build-once JuMP LP, HiGHS)   │
        │  vars: y_inv, y_inv,flex, z[t], α (epigraph, α >= α_lb)   │
        │  solve → (y*, z_k, LB = objective_value(master))         │
        └───────────────┬────────────────────────────────────────────┘
                         │ trial z_k
             ┌───────────┴────────────┐
             ▼                        ▼
┌─────────────────────────┐  ┌──────────────────────────────────────┐
│ PlanningOracle (reused,  │  │ follower.jl :: FollowerLP (build-once │
│ Phase 10 subproblem.jl)  │  │ JuMP LP, HiGHS)                       │
│ solve_planning_oracle!   │  │ solve_follower!(f, z_k) ->            │
│  -> (cost, π, π_s, ...)  │  │   FEASIBLE:  (w_k, π_s_k)             │
│ strict assert_solved!    │  │   INFEASIBLE: Farkas ray (v_k, u_k)   │
└───────────┬─────────────┘  └───────────────┬────────────────────────┘
            │ optimality cut                  │ optimality OR feasibility cut
            └───────────────┬──────────────────┘
                             ▼
              α >= cost_k + Σ_t π[t]*(z[t]-z_k[t])          (optimality)
              v_k + Σ_t u[t]*(z[t]-z_k[t]) <= 0              (feasibility)
              appended as NEW @constraint rows to master.jl (persistent, never rebuilt)
                             │
                             ▼
              UB = min(UB, y_cost(y*) + oracle_cost_k + follower_cost_k)
              gap = (UB - LB) / max(1, |UB|)  ->  converged?  -> checkpoint_iteration!
                             │
                             ▼ (once converged)
        ┌───────────────────────────────────────────────────────────┐
        │  TEST-ONLY, PARALLEL PATH (never called from the above):  │
        │  BilevelJuMP certification — Upper()/Lower() MPEC on a    │
        │  tiny hand-enumerable instance; BigMMode (HiGHS) AND      │
        │  StrongDualityMode (Ipopt); asserts investment/z/objective│
        │  match the Benders answer AND the hand enumeration.       │
        └───────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
src/planning/
├── subproblem.jl   # (Phase 10, unmodified) PlanningOracle — operational cost at pinned z
├── retry.jl        # (Phase 10, unmodified) solve_with_retry!
├── checkpoint.jl   # (Phase 10, unmodified) checkpoint_iteration! / resume_from_checkpoint
├── follower.jl     # NEW: FollowerLP struct, build_follower, solve_follower! -> (; feasible, cost/w, π_s/dual_ray, ...)
├── master.jl       # NEW: BendersMaster struct, build_master, add_optimality_cut!, add_feasibility_cut!, solve_master!
└── benders.jl      # NEW: solve_stackelberg!(...) outer loop — orchestrates master/oracle/follower, UB/LB gap, checkpointing

test/
├── test_planning_follower.jl        # NEW — Farkas-certificate regression, build-once invariance
├── test_planning_master.jl          # NEW — cut accumulation, epigraph lower-bound regression
├── test_planning_benders.jl         # NEW — end-to-end convergence, UB/LB gap
└── test_planning_certification.jl   # NEW — BilevelJuMP BigMMode + StrongDualityMode, permanent [:planning] regression
```

### Pattern 1: Build-once Benders master with a FINITE epigraph lower bound

**What:** `@variable(model, α >= α_lb)` where `α_lb` is a conservative, cheaply-computed lower
bound on the true cost-to-go (e.g. a large negative number, or a bound derived from the follower's
own known cost floor) — declared at build time, before any cut exists.
**When:** Always, for any Benders master with an epigraph variable. Without it, iteration 1's
master (zero cuts) is **unbounded** (`α` free in a `Min` objective with a positive coefficient) and
returns `MOI.DUAL_INFEASIBLE` — not a bug, but a well-known first-iteration footgun if not
anticipated.
**Example:**
```julia
# Source: JuMP official Benders decomposition tutorial (jump.dev/JuMP.jl/stable/tutorials/algorithms/benders_decomposition/)
M = <a valid lower bound on the true cost-to-go, e.g. a large negative number>
first_stage_model = Model(select_optimizer(LP()))     # INFRA-02: never Model(HiGHS.Optimizer) directly
@variable(first_stage_model, α >= M)
@objective(first_stage_model, Min, <investment cost> + α)
```

### Pattern 2: UB/LB gap convergence (never ADMM's residual criterion)

**What:** Each iteration: `LB = objective_value(master)`; `UB = min(UB, <leader's own cost at z_k> + oracle_cost_k + follower_cost_k)`; `gap = (UB - LB) / max(1, abs(UB))`; stop when `gap <= tol` (locked default `1e-6`).
**When:** Always, for the Benders/Stackelberg outer loop — this is a **structurally different**
stopping criterion from ADMM's residual-shrinking test (`src/admm/residuals.jl`). Per
`PITFALLS.md` Pitfall 7: do not reuse or adapt `AdmmResiduals`; build a purpose-specific struct so
the two are never silently interchanged.
**Example:**
```julia
# Source: JuMP official Benders decomposition tutorial (adapted to this project's cut form)
for k in 1:MAX_ITER
    optimize_master!(master)                      # solve_with_retry! + assert_solved!(allow_almost=false)
    LB = objective_value(master.model)
    z_k = value.(master.z)
    oracle_res   = solve_planning_oracle!(oracle, z_k)      # (cost, π, ...)
    follower_res = solve_follower!(follower, z_k)            # (; feasible, ...)
    if !follower_res.feasible
        add_feasibility_cut!(master, follower_res.v, follower_res.u, z_k)
        continue   # a feasibility cut does not update UB
    end
    add_optimality_cut!(master, oracle_res.cost, oracle_res.π, z_k)
    add_optimality_cut!(master, follower_res.cost, follower_res.π_s, z_k)   # or a combined cut — see Open Questions
    UB = min(UB, <leader_investment_cost>(value.(master.y)) + oracle_res.cost + follower_res.cost)
    gap = (UB - LB) / max(1, abs(UB))
    checkpoint_iteration!((; k, LB, UB, gap, z_k), k)
    gap <= TOL && break
    k == MAX_ITER && error("Benders loop exhausted $MAX_ITER iterations without converging (gap=$gap) — refusing to silently return a non-converged result")
end
```

### Pattern 3: Follower LP as a build-once model with a genuine RHS/`Parameter` trial point

**What:** Build the transmission-reinforcement follower LP exactly once; re-solve at each Benders
trial `z_k` via `set_normalized_rhs`/`set_parameter_value` — mirrors the oracle's own
`Parameter`-typed `z[t]` idiom.
**When:** Every Benders iteration's follower call — never rebuild the model.
**Example:**
```julia
# Source: mirrors src/planning/subproblem.jl's build_planning_oracle/solve_planning_oracle! idiom,
# and the JuMP official Benders tutorial's fix.(model[:x_copy], x) re-solve pattern.
function build_follower(; T::Int, corridor_cap::Real, c_inv::Real, c_op::Vector{<:Real})
    model = Model(select_optimizer(LP()))             # INFRA-02
    @variable(model, x_inv >= 0)
    @variable(model, x_op[1:T] >= 0)
    @variable(model, z[t = 1:T] in Parameter(0.0))     # the SAME Parameter idiom as subproblem.jl
    @constraint(model, invest_op[t = 1:T], x_op[t] <= corridor_cap * x_inv)   # (2b)-shaped
    @constraint(model, coupling[t = 1:T], x_op[t] == z[t])                   # (2d)/(2e)-shaped — its dual is π_s
    @objective(model, Min, c_inv * x_inv + sum(c_op[t] * x_op[t] for t in 1:T))
    return (; model, x_inv, x_op, z, coupling)
end

function solve_follower!(f, z_trial; max_attempts = 4)
    set_parameter_value.(f.z, z_trial)
    optimize!(f.model)     # NOT solve_with_retry! blindly — infeasibility must be OBSERVED, not retried away
    if is_solved_and_feasible(f.model; dual = true)
        return (; feasible = true, cost = objective_value(f.model), π_s = dual.(f.coupling))
    elseif dual_status(f.model) == MOI.INFEASIBILITY_CERTIFICATE
        return (; feasible = false, v = dual_objective_value(f.model), u = dual.(f.coupling))
    else
        error("follower LP neither solved nor produced an infeasibility certificate — refusing to trust: " *
              "termination_status=$(termination_status(f.model)) dual_status=$(dual_status(f.model))")
    end
end
```
Note the deliberate departure from `solve_with_retry!` here: `RETRYABLE_STATUSES` in
`retry.jl` does not include `INFEASIBLE`/`INFEASIBILITY_CERTIFICATE` (by design — retrying a
genuine infeasibility wastes budget), so the follower's own infeasibility branch must be checked
directly against `is_solved_and_feasible`/`dual_status`, not routed through the oracle's retry
wrapper. `solve_with_retry!` remains the right tool for the master's and oracle's cut-producing
solves, which are never expected to be infeasible by construction (the master always has at least
the origin as a feasible point; the oracle's feasibility depends on the fixture — see Pitfall O1).

### Pattern 4: BilevelJuMP certification — both `Upper()`/`Lower()` and `DualOf`

**What:** Build the SAME tiny leader/follower instance twice — once as the hand-rolled
Benders loop (production code), once as a single compact `BilevelModel` — and require the decisions
and objective value (not intermediate duals, which live in different reformulated spaces) to agree,
per Pitfall 6/`PITFALLS.md`.
**When:** The certification test, `test/test_planning_certification.jl`, is a permanent
`[:planning]`-tagged `@testitem`, not a throwaway script.
**Example:**
```julia
# Source: joaquimg.github.io/BilevelJuMP.jl/stable/tutorials/getting_started/ and .../tutorials/modes/
# and .../tutorials/lower_duals/ (fetched directly this session)
using BilevelJuMP, HiGHS, Ipopt   # test-only import — see Pitfall B3 for the INFRA-02 exception note

# Mode 1: BigMMode (open-source, HiGHS, MIP-capable — only needs binaries)
model_bigm = BilevelModel(
    HiGHS.Optimizer,
    mode = BilevelJuMP.BigMMode(primal_big_M = 100, dual_big_M = 100),
)
@variable(Upper(model_bigm), y_inv >= 0)      # leader: flexibility investment
@variable(Lower(model_bigm), x_op[1:T] >= 0)  # follower: transmission reinforcement operation
@objective(Upper(model_bigm), Min, c_y_inv * y_inv + <leader's own operational proxy>)
@objective(Lower(model_bigm), Min, sum(c_x_op[t] * x_op[t] for t in 1:T))
@constraint(Lower(model_bigm), coupling[t = 1:T], x_op[t] == <z as a function of y_inv>[t])
optimize!(model_bigm)

# Mode 2: StrongDualityMode (Ipopt — needed because the coupling RHS depends on the UPPER variable,
# making the primal-cost == dual-cost strong-duality equality genuinely bilinear)
model_sd = BilevelModel(Ipopt.Optimizer, mode = BilevelJuMP.StrongDualityMode())
# ... same Upper()/Lower() blocks ...
@variable(Upper(model_sd), π_s_dual, DualOf(coupling[1]))   # if the sign/role invariant needs the RAW dual exposed
optimize!(model_sd)

# Certification assertion (decisions + objective only — NOT intermediate duals, per Pitfall B2):
@assert isapprox(value(y_inv, model_bigm), value(y_inv, model_sd); rtol = 1e-4)
@assert isapprox(objective_value(model_bigm), objective_value(model_sd); rtol = 1e-4)
@assert isapprox(value(y_inv, model_bigm), y_inv_hand_enumerated; rtol = 1e-4)
```

### Anti-Patterns to Avoid

- **Retrying a genuine follower infeasibility through `solve_with_retry!`.** `RETRYABLE_STATUSES`
  deliberately excludes `INFEASIBLE`; the follower's infeasibility path must be read directly
  (`is_solved_and_feasible`/`dual_status`), not routed through the oracle's retry wrapper, or the
  Farkas-certificate path (success criterion 1) is unreachable.
- **Rebuilding `follower.jl`'s or `master.jl`'s JuMP model each Benders iteration.** The master's
  row-count growth (new cuts) is expected structural growth, not a rebuild — CLAUDE.md explicitly
  calls out "Rebuilding JuMP models each ADMM/Benders iteration" as the single biggest avoidable
  performance sink.
- **Comparing BilevelJuMP's KKT/complementarity multipliers directly against the Benders `π^k`.**
  They live in different reformulated spaces (Pitfall 6) — only decisions, `z`, and objective value
  are guaranteed comparable.
- **Building the Benders loop's happy path first and adding the epigraph lower bound "later."**
  The very first master solve (zero cuts) needs it — this is not an edge case to defer.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting/reading an infeasibility (Farkas) certificate | A custom "try the LP, catch the error, guess a cut direction" heuristic | `dual_status(model) == MOI.INFEASIBILITY_CERTIFICATE`, `dual.(...)`, `dual_objective_value(model)` — JuMP/MOI's own certificate machinery [CITED: jump.dev/JuMP.jl/stable/moi/background/infeasibility_certificates/] | The certificate's algebra (dual improving ray `d` with `-Σ Aᵢᵀdᵢ = 0`, `-Σ bᵢᵀdᵢ > 0`) is exactly the feasibility-cut coefficient set — reinventing it risks a sign/scale bug identical in spirit to Pitfall 3. |
| Cross-checking a bilevel/Stackelberg equilibrium's correctness | A second hand-rolled KKT/MPEC reformulation | BilevelJuMP.jl (`BigMMode`/`StrongDualityMode`), test-only | It already implements Fortuny-Amat/strong-duality reductions correctly, with solver-mode compatibility documented; hand-rolling a second reformulation defeats the purpose of an *independent* check. |
| Benders master convergence bookkeeping | Reusing/adapting `admm/residuals.jl`'s `AdmmResiduals` struct | A new, purpose-built UB/LB-gap struct | Pitfall 7 — the two algorithms' "convergence" means structurally different things; silently sharing a struct invites reusing the wrong stopping criterion. |
| The epigraph lower bound `α_lb` | An arbitrary large negative literal picked without derivation | A documented, derived bound (e.g. the follower's own known cheapest feasible cost, or `-sum(follower's max possible cost)` mirroring the official tutorial's `M = -sum(G)` pattern) | An `α_lb` that is too loose can slow convergence; one that is too tight (above the true optimum) silently makes the master infeasible/wrong — document the derivation, don't guess. |

**Key insight:** Every "hand-roll risk" in this phase has an existing, already-verified JuMP/MOI or
BilevelJuMP primitive behind it — the phase's actual work is *composition* (wiring the oracle,
the new follower, the new master, and the certification test together correctly), not inventing
new numerical machinery.

## Common Pitfalls

### Pitfall M1: Unbounded first-iteration master (no epigraph lower bound)

**What goes wrong:** The very first master solve (zero Benders cuts yet) has `α` free in a `Min`
objective with `+α` — the LP is unbounded, HiGHS returns `MOI.DUAL_INFEASIBLE`, and
`assert_solved!` throws (correctly, since an unbounded LP has no trustworthy primal to extract a
trial `z_k` from).
**Why it happens:** Benders is usually first coded/taught against a master that already "has" its
epigraph bounded implicitly; the very first iteration is the one case with truly zero information.
**How to avoid:** Declare `@variable(model, α >= α_lb)` at build time with a documented, derived
`α_lb` (Pattern 1/Don't-Hand-Roll table) — never omit the bound and special-case iteration 1.
**Warning signs:** `assert_solved!` throwing on the very first master solve, before any cut exists.

### Pitfall O1: Oracle infeasibility for an out-of-band trial `z` is a REAL risk this phase's literal scope doesn't cover

**What goes wrong:** Phase 10's own SUMMARY documents empirically that `PlanningOracle` is
INFEASIBLE for `z = 0` (and other arbitrary fixed vectors) on `Phase6Fixtures`'s real aggregator —
only a narrow band around the network's own unconstrained free-import optimum is feasible. PLAN-04
requires a Farkas-certificate path only for the **follower** LP; nothing in the phase's success
criteria asks for oracle-side infeasibility handling, yet `solve_with_retry!`/`assert_solved!`
raise loudly (an `ErrorException`, no certificate) if the master ever proposes a `z_k` outside the
oracle's feasible band — this would crash the whole Benders loop mid-run, not degrade gracefully.
**Why it happens:** The master's own feasible region (investment vars + `z[t]`) has no a-priori
knowledge of the oracle's feasibility band unless it is explicitly bounded to it.
**How to avoid:** Two documented options (Claude's Discretion: "follower fixture parameterization"
covers exactly this choice) —
  1. **Recommended:** use a loosely-bounded, smooth aggregator (mirroring Phase 10's
     `ToyElasticDevice` pattern — DEV-05-conformant, separable concave utility, interior optimum at
     every hour) for THIS phase's oracle instance, so the oracle stays feasible over a wide `z`
     range by construction, concentrating the phase's designed infeasibility risk in the NEW
     follower's corridor-capacity constraint — exactly matching PLAN-04's literal Farkas scope.
  2. Alternatively, add an explicit box constraint on `z[t]` in the master derived from the
     oracle's known feasible band (measured empirically on the actual fixture, not assumed) — more
     faithful to a "realistic" fixture, but adds an out-of-scope oracle-feasibility characterization
     step this phase's requirements don't ask for.
**Warning signs:** `solve_planning_oracle!` throwing mid-loop with no informative "which iteration,
which `z_k`" context; a Benders run that dies deep into iteration 8+ with all prior cuts lost (no
checkpoint captured the failure point).
**Phase to address:** THIS phase, at follower/oracle-fixture design time — before the outer loop is
wired, decide (and document in the module header) which of the two options above is taken.

### Pitfall F1: HiGHS Farkas certificate availability depends on presolve/detection path

**What goes wrong:** HiGHS.jl computes an infeasibility certificate by default
(`HiGHS.ComputeInfeasibilityCertificate()` defaults `true`), but if primal infeasibility is
detected **during presolve**, no dual ray is available from that pass alone — HiGHS's C API
internally re-solves the feasibility LP **without presolve** to compute the ray on request. In
practice this usually "just works" through HiGHS.jl's own attribute, but CONTEXT.md's own locked
decision text ("disable presolve if needed to obtain rays") reflects the more conservative,
solver-version-independent fallback.
**Why it happens:** Presolve can eliminate rows/columns before the simplex method ever runs on the
"real" infeasible LP, and a dual ray computed on the *presolved* problem does not map 1:1 back to
the original constraints without postsolve translation.
**How to avoid:** First measure (mirroring the project's existing "measure, don't guess" discipline
from `10-RESEARCH.md` Pitfall 4 / `test_planning_retry.jl`'s WR-04 pattern): build the follower LP
with default HiGHS settings, force an infeasible trial `z`, and check whether `dual_status ==
MOI.INFEASIBILITY_CERTIFICATE` is reliably returned. If not, explicitly `set_attribute(model,
"presolve", "off")` on the follower model (a follower-model-local setting is safe — it never
touches the master's or oracle's solver attributes).
**Warning signs:** `dual_status(follower.model)` returning `NO_SOLUTION` instead of
`INFEASIBILITY_CERTIFICATE` on a deliberately-infeasible trial `z` during test development.
**Phase to address:** This phase, `follower.jl`'s own test suite (`test_planning_follower.jl`) —
the Farkas-certificate regression is exactly the place to discover and document which setting this
project's actual fixture needs.

### Pitfall B1: Big-M bounds in `BigMMode` — silently wrong solution if too small, slow/fragile if too large

**What goes wrong:** `BilevelJuMP.BigMMode(primal_big_M = ..., dual_big_M = ...)` (the Fortuny-Amat/
McCarl reformulation) requires finite bounds on **every** primal and dual variable of the lower
level. A big-M that is too small can cut off the true optimum (a silently WRONG solution that still
"solves" without error); one that is too large makes the MIP numerically fragile and slow.
**Why it happens:** The bounds are a modeling input, not something BilevelJuMP derives or validates
against the actual problem data — there is no automatic warning if a chosen `M` is too tight.
**How to avoid:** For the tiny hand-enumerable certification instance (Claude's Discretion), derive
`primal_big_M`/`dual_big_M` directly from the instance's own known bounds (e.g., the corridor
capacity and the largest plausible dual value at any hand-enumerated candidate solution) rather
than picking a round number; use `BilevelJuMP.set_primal_upper_bound_hint`/
`set_dual_upper_bound_hint` for per-variable refinement if a single global `M` proves too loose.
Cross-check `BigMMode`'s answer against `StrongDualityMode` (a structurally different
reformulation with no big-M) — persistent disagreement between the two on a tiny instance is the
signal a chosen `M` is wrong, not that the Benders loop is wrong.
**Warning signs:** `BigMMode` and `StrongDualityMode` disagree with each other but each "solves"
without error; the optimal solution has a variable sitting exactly at its big-M bound (a classic
tell that the bound, not the true optimum, is binding).
**Phase to address:** This phase's certification-instance design step (before trusting either
mode's answer as ground truth).

### Pitfall B2: Comparing BilevelJuMP's own reformulated duals against Benders' `π^k`

**What goes wrong:** BilevelJuMP's KKT-stationarity multipliers (or Fortuny-Amat complementarity
indicators) are outputs of a genuinely different mathematical reduction than a Benders cut
coefficient — they are not the same object even when both are "correct." Treating a
match/mismatch between them as diagnostic (rather than comparing decisions + objective value only)
produces false confidence or false alarms.
**How to avoid:** Restrict the certification assertion to: final investment decision, final
coupling flow `z`, and total objective value. Use `DualOf` only if the certification is
specifically checking the coupling-dual **sign convention** itself (success criterion 4's second
half) — and even then, treat it as ONE additional data point, not a full substitute for the
decision/objective comparison.
**Phase to address:** This phase's certification test design.

### Pitfall B3: BilevelJuMP's `solver` argument requires a bare zero-arg constructor — the one place INFRA-02's test-file convention needs a documented exception

**What goes wrong:** `BilevelModel(solver::Function; mode, add_bridges)` requires `solver` to be "a
function that takes no arguments and returns a JuMP solver object" [CITED:
joaquimg.github.io/BilevelJuMP.jl/stable/reference/] — i.e. a bare `HiGHS.Optimizer`/
`Ipopt.Optimizer` or a `() -> Backend.Optimizer()` lambda, NOT an `OptimizerWithAttributes` object
(what `select_optimizer(::ProblemClass)` returns). The project's established test convention (every
other `test_planning_*.jl` file routes solver selection through `TSODSO.select_optimizer(...)`,
never `import HiGHS`/`import Clarabel` directly) cannot be followed literally here.
**Why it happens:** BilevelJuMP is architecturally a parallel, test-only validation oracle
(ARCHITECTURE.md §4) that is never part of the production solver-abstraction seam INFRA-02
protects — but its own API surface still requires a concrete solver type name at the call site.
**How to avoid:** Document this explicitly as a **sanctioned, scoped exception**, not a silent
convention violation: `test/test_planning_certification.jl`'s module header should state that
`import HiGHS`/`import Ipopt` are used directly ONLY here, ONLY because `BilevelModel`'s own
constructor contract demands a bare optimizer type, mirroring how `ext/TSODSOGurobiExt.jl` is the
one sanctioned place a commercial solver identity is named. No other test file, and no `src/` file,
gets this exception.
**Phase to address:** This phase, at certification-test authoring time — write the exception into
the file header before code review flags it as an INFRA-02 violation.

### Pitfall S1: Cut validity depends on the SAME pitfalls Phase 10 already flagged for the oracle — re-verify at every Benders trial point, not once

**What goes wrong:** (Carried forward from `PITFALLS.md` Pitfall 1, now load-bearing.) A Benders
optimality cut from the oracle is only a valid supporting hyperplane if the pinned subproblem is
strictly `OPTIMAL` (never `ALMOST_OPTIMAL`) and — for the SOCP path — the relaxation is exact
(`assert_socp_exact!`) at THAT trial point specifically, not just at model-build time.
**How to avoid:** `solve_planning_oracle!` already runs both gates on every call (Phase 10,
verified) — Phase 11 must not bypass them by calling `o.model`'s solve directly. Add an automated
cut-validity check as a test invariant: for a later-evaluated `z'`, assert
`oracle_res(z').cost >= cut.cost_k + dot(cut.π_k, z' .- cut.z_k) - tol` never fires.
**Phase to address:** `test_planning_master.jl` / `test_planning_benders.jl`.

## Code Examples

### Reading a Farkas certificate and forming a feasibility cut (LP, minimize sense)

```julia
# Source: JuMP official infeasibility-certificates background page
# (jump.dev/JuMP.jl/stable/moi/background/infeasibility_certificates/) + Benders tutorial
# (jump.dev/JuMP.jl/stable/tutorials/algorithms/benders_decomposition/), fetched directly this session.
optimize!(follower.model)
if dual_status(follower.model) == MOI.INFEASIBILITY_CERTIFICATE
    v = dual_objective_value(follower.model)      # -Σ bᵢᵀdᵢ for a Min-sense LP
    u = dual.(follower.coupling)                    # the certificate vector d, restricted to the coupling rows
    # Feasibility cut, appended as a PERSISTENT master row:
    @constraint(master.model, v + sum(u[t] * (master.z[t] - z_k[t]) for t in 1:T) <= 0)
end
```

### Master epigraph with a derived (not guessed) lower bound

```julia
# Source: adapted from the official JuMP Benders tutorial's M = -sum(G) pattern
α_lb = -(worst_case_follower_cost(follower_fixture) + worst_case_oracle_cost(oracle_fixture))
@variable(master.model, α >= α_lb)
```

### BilevelJuMP `DualOf` for exposing a lower-level coupling dual to the upper level

```julia
# Source: joaquimg.github.io/BilevelJuMP.jl/stable/tutorials/lower_duals/ (fetched directly)
@constraint(Lower(model), coupling[t = 1:T], x_op[t] == z_from_upper[t])
@variable(Upper(model), π_s[t = 1:T], DualOf(coupling[t]))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-------------------|---------------|--------|
| N/A — no prior Benders/BilevelJuMP code exists in this codebase | This phase is greenfield for `follower.jl`/`master.jl`/`benders.jl` | — | No migration; only the general JuMP 1.30.1→1.31.0 minor bump noted in `.planning/research/STACK.md` is relevant, and it is additive/non-breaking for `Parameter`/`dual()`/cone-constraint semantics. |

**Deprecated/outdated:** None specific to this phase's scope.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact cut-composition structure (single combined epigraph vs. two separate epigraph terms for oracle-cost vs. follower-cost) is presented as an open design choice, not a settled fact | Architecture Patterns, Open Questions | Low — this is explicitly the phase's own empirical-resolution mandate (success criterion 4); the planner should encode whichever choice the BilevelJuMP certification confirms, not lock one in from this research alone. |
| A2 | HiGHS.jl reliably returns a Farkas certificate on this project's actual follower fixture without needing `presolve => "off"` | Pitfall F1 | Low-medium — if wrong, the fix is a one-line attribute change on the follower model only (documented fallback already given); does not affect any other model. |
| A3 | A loosely-bounded oracle aggregator (mirroring Phase 10's `ToyElasticDevice`) is the recommended way to keep Pitfall O1 out of this phase's literal scope | Pitfall O1 | Medium — if the planner instead reuses `Phase6Fixtures`'s real aggregator for the oracle side, out-of-band `z_k` trials from the master WILL eventually crash the loop (empirically confirmed in Phase 10); this must be explicitly decided, not defaulted into. |

**If this table is empty:** N/A — see entries above; all package/version claims elsewhere in this
document are `[VERIFIED]`/`[CITED]` against directly-fetched sources (Julia General registry,
`joaquimg.github.io/BilevelJuMP.jl`, `jump.dev/JuMP.jl`, local `Pkg.status()`), not `[ASSUMED]`.

## Open Questions

1. **Which subproblem(s) feed the master's epigraph, and in what combination?**
   - What we know: CONTEXT.md locks the optimality-cut FORM (`α ≥ cost^k + Σ_t π[t]·(z[t]−z^k[t])`,
     Phase-10 D-05) and separately locks that the follower LP produces both optimality and
     feasibility cuts. `THEORY-papers.md`'s "Natural architecture" paragraph and `ARCHITECTURE.md`
     §3's Reading A/B split leave open whether the oracle's cut and the follower's cut land on the
     SAME `α` (summed subgradient) or on two independent epigraph terms.
   - What's unclear: the exact JuMP-level wiring (one `@variable(model, α)` vs. two).
   - Recommendation: build both subproblems as independently-cutting units (Pattern 3, multi-cut
     style) — it is the more standard, more testable structure, and is trivially convertible to a
     single summed-cut form later if the certification prefers that reading. Let the BilevelJuMP
     certification (success criterion 4) be the actual tie-breaker, exactly as CONTEXT.md mandates.

2. **Does the certification's `BigMMode` instance need per-variable bound hints, or does a single global `M` suffice?**
   - What we know: `set_primal_upper_bound_hint`/`set_dual_upper_bound_hint` exist for refinement.
   - What's unclear: whether the tiny hand-enumerable instance (Claude's Discretion) is small enough
     that a single conservative global `M` avoids Pitfall B1 entirely.
   - Recommendation: start with a single derived `M`; only reach for per-variable hints if
     `BigMMode` and `StrongDualityMode` disagree (Pitfall B1's own warning sign).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Julia | Everything | ✓ | 1.12.5 (compat floor 1.10 LTS unaffected) | — |
| JuMP | follower.jl, master.jl, benders.jl | ✓ | 1.30.1 (installed; 1.31.0 available, non-breaking) | — |
| HiGHS | follower.jl, master.jl (LP) | ✓ | 1.24.1 | — |
| Clarabel | PlanningOracle (reused, Phase 10) | ✓ | 0.11.1 | — |
| Ipopt | BilevelJuMP `StrongDualityMode` (test-only) | ✓ | 1.15.0 | — |
| DrWatson | checkpoint.jl (reused, Phase 10) | ✓ | 2.19.1 | — |
| BilevelJuMP | Certification test only | ✗ (not yet added) | Target 0.6.3 | None needed — this phase's first task is adding it to `test/Project.toml`; no fallback required since it is the phase's own deliverable dependency. |
| Dualization | Transitive (BilevelJuMP `StrongDualityMode`) | ✗ (pulled in automatically once BilevelJuMP is added) | Target 0.3.5 | — |

**Missing dependencies with no fallback:** None — BilevelJuMP/Dualization are simply not yet
installed because adding them IS part of this phase's scope (test-only `Pkg.add`).

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` (`@testitem`/`@testmodule`, `@run_package_tests` in `test/runtests.jl`) |
| Config file | `test/Project.toml` (test-only deps; this phase adds `BilevelJuMP = "0.6.3"` to `[compat]`) |
| Quick run command | `julia --project=. -e 'import Pkg; Pkg.test(test_args=["--tags", "planning"])'` (mirrors the project's documented deviation: `TestItemRunner.runtests(filter=...)` does not exist as a standalone entry point — every prior phase SUMMARY records this) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (the authoritative gate used in every prior phase's RED/GREEN commits) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|---------------------|--------------|
| PLAN-04 | Follower LP returns `π_s` for feasible `z`, Farkas certificate for infeasible `z` | unit (`@testitem`) | `julia --project=. -e 'import Pkg; Pkg.test()'` (filters to `test_planning_follower.jl`'s `[:planning]`-tagged items) | ❌ Wave 0 — `test/test_planning_follower.jl` does not exist yet |
| PLAN-05 | Master accumulates persistent optimality + feasibility cut rows, strict `assert_solved!` gate | unit (`@testitem`) | same | ❌ Wave 0 — `test/test_planning_master.jl` |
| PLAN-06 | End-to-end convergence with documented UB/LB gap | integration (`@testitem`, full loop on a small fixture) | same | ❌ Wave 0 — `test/test_planning_benders.jl` |
| PLAN-07 | Leader/follower + sign convention resolved empirically, tested invariant | integration (`@testitem`, BilevelJuMP-backed) | same | ❌ Wave 0 — `test/test_planning_certification.jl` |
| PVAL-01 | BilevelJuMP certification retained as a permanent, fast regression | regression (`@testitem`, `[:planning]` tag, part of the default full-suite run) | same | ❌ Wave 0 — same file as PLAN-07's test |

### Sampling Rate

- **Per task commit:** `julia --project=. -e 'import Pkg; Pkg.test()'` filtered to the `:planning`
  tag (mirrors every prior phase's RED/GREEN commit discipline).
- **Per wave merge:** full `Pkg.test()` (no filter) — confirms zero Phase 1-10 regressions, exactly
  as Phase 10's SUMMARY records (1978 passed / 2 documented-broken baseline).
- **Phase gate:** full suite green before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `test/test_planning_follower.jl` — covers PLAN-04 (Farkas certificate regression, build-once
      invariance, feasible/infeasible branches).
- [ ] `test/test_planning_master.jl` — covers PLAN-05 (cut accumulation, epigraph lower-bound
      regression, strict-gate enforcement).
- [ ] `test/test_planning_benders.jl` — covers PLAN-06 (end-to-end convergence gap on a small
      fixture, iteration-cap loud-failure regression).
- [ ] `test/test_planning_certification.jl` — covers PLAN-07/PVAL-01 (BilevelJuMP `BigMMode` +
      `StrongDualityMode` vs. hand enumeration vs. Benders answer, permanent regression).
- [ ] `test/Project.toml` — add `BilevelJuMP = "0.6.3"` to `[compat]` and `[deps]` (framework
      install gap, not a test-file gap).
- [ ] No new fixture module strictly required — reuse `Phase6Fixtures`/`ToyDeviceFixture` shapes,
      but per Pitfall O1, the oracle side of THIS phase's fixture should likely be the loose-bounded
      `ToyElasticDevice` pattern rather than the real aggregator, to keep the follower's corridor
      capacity as the sole designed infeasibility surface.

## Security Domain

> This is a single-user, offline, research-optimization framework (no network listener, no
> authentication surface, no external user input beyond CLI/script arguments and static fixture
> files) — most web-application ASVS categories do not apply. The closest analogs are noted below;
> `security_enforcement` is not set to `false` in `.planning/config.json`, so this section is
> included per protocol even though the applicable surface is minimal.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|----------------|---------|--------------------|
| V2 Authentication | No | No auth surface in a local research library. |
| V3 Session Management | No | N/A. |
| V4 Access Control | No | N/A. |
| V5 Input Validation | Partial | Existing project convention: loud `ArgumentError` guards on shape/bound mismatches (e.g. `build_planning_oracle`'s `λ₀` length check, `checkpoint_iteration!`'s `0:99999` range guard). Phase 11's `follower.jl`/`master.jl` should follow the same pattern for fixture parameters (corridor capacity > 0, `T` consistency across oracle/follower/master). |
| V6 Cryptography | No | N/A — no secrets, no crypto in this phase. |
| V14 Configuration / Dependency Integrity | Yes | Supply-chain integrity for the new test-only dependency: BilevelJuMP verified against the Julia General registry (real UUID, real repo, monotonic version history) — see Package Legitimacy Audit. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|------------------------|
| A silently-wrong Benders cut (inexact SOC relaxation, `ALMOST_OPTIMAL` dual, or a bad `BigMMode` bound) permanently corrupting the master's feasible region with no self-correction | Tampering (of the model's own internal trust chain, not an external attacker) | Strict `assert_solved!(...; allow_almost=false)` on every cut-producing solve (already the locked decision); the automated cut-validity check (Pitfall S1); the BilevelJuMP certification gate itself as an independent cross-check. |
| A malicious/compromised test-only dependency (BilevelJuMP or its transitive `Dualization`) | Tampering / Supply chain | Registry provenance check (Package Legitimacy Audit) before adding to `test/Project.toml`; pin an exact `[compat]` version, never a floating range. |
| Silent data corruption from resuming a crashed Benders checkpoint mid-write | Tampering (of persisted state) | Already handled by `checkpoint.jl`'s `safe = true` (`DrWatson.safesave`) and canonical-filename-only scan (Phase 10, reused unmodified). |

## Sources

### Primary (HIGH confidence)
- `src/planning/subproblem.jl`, `src/planning/retry.jl`, `src/planning/checkpoint.jl`,
  `src/solver/factory.jl`, `src/solver/ProblemClass.jl`, `src/core/status.jl` — read directly this
  session, the exact reused API contracts (`solve_planning_oracle!`'s NamedTuple shape,
  `solve_with_retry!`'s `RETRYABLE_STATUSES` exclusion of `INFEASIBLE`, `select_optimizer(::LP())`).
- `test/test_planning_retry.jl`, `.planning/phases/10-.../10-02-SUMMARY.md` — read directly this
  session, confirming the empirically-observed oracle-infeasibility-for-out-of-band-`z` finding
  (Pitfall O1's factual basis) and the project's TestItems/`[:planning]`-tag test conventions.
- `joaquimg.github.io/BilevelJuMP.jl/stable/tutorials/getting_started/`,
  `.../tutorials/modes/`, `.../tutorials/lower_duals/`, `.../reference/` — fetched directly this
  session: exact `BilevelModel`/`Upper()`/`Lower()`/mode-constructor/`DualOf` syntax and the
  `solver` argument's "bare zero-arg constructor" contract (Pitfall B3's basis).
- `jump.dev/JuMP.jl/stable/tutorials/algorithms/benders_decomposition/`,
  `.../moi/background/infeasibility_certificates/`, `.../packages/HiGHS/` — fetched directly this
  session: the official build-once/re-solve pattern, optimality/feasibility cut algebra, and
  HiGHS.jl's default certificate-computation behavior.
- Julia General registry `raw.githubusercontent.com/JuliaRegistries/General/.../BilevelJuMP/{Package,Versions}.toml`
  — fetched directly this session: confirmed repo identity and version history for the Package
  Legitimacy Audit.
- Local `julia --version` / `Pkg.status()` on the actual project environment — confirmed installed
  versions of Julia/JuMP/HiGHS/Clarabel/Ipopt/DrWatson (Environment Availability table).

### Secondary (MEDIUM confidence)
- WebSearch cross-verification of HiGHS presolve/dual-ray interaction (`ERGO-Code/HiGHS` GitHub
  issue discussion) — consistent with, and used to caveat, the primary HiGHS.jl docs fetch
  (Pitfall F1).
- `.planning/research/{ARCHITECTURE,PITFALLS,STACK,THEORY-papers}.md` (this project's own prior
  research session, dated 2026-07-22, self-flagged MEDIUM confidence on the PSR source's
  leader/follower ambiguity specifically) — used extensively as the basis for the Architecture
  Patterns / Open Questions / Pitfalls sections above; NOT independently re-verified against the
  original PSR note this session (correctly, per CONTEXT.md's explicit instruction not to
  re-resolve the ambiguity by re-reading `THEORY-papers.md`).

### Tertiary (LOW confidence)
- None — every claim above traces to a directly-fetched official source, a directly-read codebase
  file, or the project's own already-vetted prior research artifacts.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every package version independently re-verified against the Julia General
  registry and/or local `Pkg.status()` this session.
- Architecture (Benders/HiGHS/JuMP mechanics): HIGH — official JuMP tutorial and MOI background
  docs fetched directly.
- Architecture (BilevelJuMP mode API): HIGH — official BilevelJuMP docs fetched directly this
  session (the roadmap's own flagged "HIGH-priority focused research pass" target).
- Leader/follower cut-composition structure: MEDIUM — deliberately left open per CONTEXT.md's own
  design (resolved by the phase's BilevelJuMP certification, not by this research).
- Pitfalls: HIGH — largely carried forward from the project's own extensive, already-researched
  `PITFALLS.md`, cross-checked against this session's fresh BilevelJuMP/HiGHS doc fetches, plus two
  NEW pitfalls (M1 epigraph lower bound, O1 oracle-infeasibility scope gap) discovered this session
  from the official JuMP tutorial and Phase 10's own SUMMARY respectively.

**Research date:** 2026-07-22
**Valid until:** 30 days for the Julia/JuMP/HiGHS mechanics (stable ecosystem); 7 days for the
BilevelJuMP-specific guidance if the phase's execution slips significantly past this window (it is
a smaller, faster-moving package — 356 commits/current release 2026-03-13 — re-check its docs if
implementation starts more than ~2 weeks after this research).
