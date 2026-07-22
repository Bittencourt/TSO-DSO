# Stack Research

**Domain:** Hand-rolled Benders decomposition + Gauss-Seidel diagonalization planning layer (Stackelberg-Nash TSO–DSO investment equilibrium), Julia + JuMP, wrapping the existing v1.0 `operational_oracle`.
**Researched:** 2026-07-22
**Confidence:** HIGH (all versions re-verified live against the Julia General registry today; BilevelJuMP mode/solver-support matrix re-verified against its own docs today; ecosystem-fit judgments MEDIUM-HIGH, consistent with and sharpening CLAUDE.md's existing LOCKED decisions)

## Recommended Stack

### Core Technologies

**No new core solver technology is needed.** v2.0's planning layer is CONTINUOUS-only (LP/QP master, LP/QP/SOCP subproblems) and reuses v1's `select_optimizer(::ProblemClass)` factory unchanged:

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **JuMP** | **1.31.0** (up from 1.30.1 four days ago; compat `"1.30.1"` in `Project.toml` already permits it) | Algebraic modeling for master + follower subproblems | v1.31.0 is nonlinear-expression/error-message/doc polish only (no breaking changes to `Parameter`, `dual()`, `SecondOrderCone`, or constraint-handle semantics) — safe to bump the installed version; no code changes required. Re-verified via GitHub release notes 2026-07-22. |
| **HiGHS** | **1.24.1** (unchanged) | Benders **master** problem (leader: `y_inv`, `y_inv,flex`, `y_op,s`, `α`, continuous LP with growing Benders-cut rows) via `select_optimizer(LP())` | The master (eq. 4a–4f in the PSR note) is a pure LP for v2.0 — no binaries until integer expansion lands. `select_optimizer(LP())` already exists in `src/solver/factory.jl` and needs no new `ProblemClass`. |
| **Clarabel** | **0.11.1** (unchanged) | Follower subproblem: N2 transmission-reinforcement LP/QP (eq. 2a–2e) and the reused N1 `operational_oracle` SOCP | Same factory dispatch already used by the operational layer (`select_optimizer(SOCP())` / `select_optimizer(QP())`); the follower's coupling dual `π_s` (eq. 2e) is read exactly like `_coupling_dual` already reads `:balance_p` — same `dual(constraint_handle)` pattern, no new library. |
| **Ipopt** | **1.15.0** (unchanged) | Only invoked if the BilevelJuMP validation oracle uses `StrongDualityMode`/`ProductMode` (see below) | Already wired via `select_optimizer(NLP())`; no new dependency. |

### Supporting Libraries — NEW for v2.0

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **BilevelJuMP.jl** | **0.6.3** (current; last release 2026-03-13, 356 commits, actively maintained — re-verified today) | **Small-case validation oracle only.** Reformulate a tiny single-distributor leader-follower instance as a compact single-level problem and check its optimum against the hand-rolled Benders loop. | Add as a **test-only** dependency (see Installation) — never imported by production planning code. Use on toy 2–5-node instances only (see solver-mode caveat below). |
| **Dualization.jl** | **0.3.5** (current) | Transitive dep of BilevelJuMP — builds the follower's dual/KKT problem for `StrongDualityMode`. | Pulled in automatically by BilevelJuMP; do not depend on it directly. |

### Supporting Libraries — deliberately NOT added for v2.0 (kept "on the shelf")

| Library | Version (for when it's revisited) | Why deferred |
|---------|-------|--------------|
| **PATHSolver.jl** | 1.7.9 (current) | Only needed if a future variant is recast as a genuine mixed-complementarity/VI equilibrium. v2.0's Nash equilibrium is solved by **Gauss-Seidel diagonalization** (a fixed-point outer loop over independent per-distributor Benders solves), not a monolithic complementarity system — no MCP formulation exists to hand PATH. |
| **Complementarity.jl** | 0.9.0 (current) | Same reasoning as PATHSolver — it is the JuMP-side modeling layer for exactly that MCP recast. Not needed while diagonalization is fixed-point, not simultaneous. |
| **DualDecomposition.jl** | 0.3.4 (current) | Targets Lagrangian dual decomposition of **stochastic MIPs** (Argonne). v2.0 has neither stochastic scenarios in the planning layer nor integer investment yet. Revisit only if/when a stochastic-scenario or integer-Lagrangian-cut planning milestone opens (both explicitly deferred per PROJECT.md). |
| **Coluna.jl / StructJuMP** | 0.8.2 / 0.3.2 | CLAUDE.md already declined these for v1; nothing about the v2.0 continuous-Benders scope changes that call — they impose annotation/structure that fights a hand-rolled, thesis-traceable decomposition. Do not reconsider unless scale genuinely forces it (integer-expansion milestone at the earliest). |
| **InfiniteOpt.jl** | 0.6.3 (current) | Targets the stochastic/MPC continuous-time-and-uncertainty extension axis, orthogonal to the planning layer's investment-equilibrium structure. Not in v2.0 scope. |

### Development Tools

No new dev tools. Reuse v1's `TestItemRunner` / `Aqua` / `JET` / `Documenter` + `Literate` / `JuliaFormatter` unchanged (see `.planning/research/v1.0/STACK.md`). The Benders/diagonalization outer loop and its convergence diagnostics should follow the same `@testitem`-per-rung idiom already used for ADMM (Phase 6/7).

## Installation

```julia
# In the project environment (activate the repo, then):
import Pkg

# Nothing new in the main Project.toml — v2.0 planning code depends ONLY on
# JuMP + the existing select_optimizer(LP()/QP()/SOCP()) factory already shipped.

# BilevelJuMP is a VALIDATION-ORACLE, test-only dependency (mirrors how CairoMakie/
# Gurobi/MosekTools are kept out of the hard [deps] via weakdeps/extensions):
Pkg.activate("test")
Pkg.add(["BilevelJuMP"])   # pulls in Dualization + Reexport transitively
```

Add `BilevelJuMP = "0.6.3"` to `test/Project.toml`'s `[compat]`, matching the existing pattern where `Aqua`/`JET`/`TestItemRunner` live in `test/Project.toml` and never touch the shipped package's `[deps]`. Do **not** add BilevelJuMP, PATHSolver, Complementarity, or DualDecomposition to the root `Project.toml` — none are production dependencies of the planning layer.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Hand-rolled Benders + Gauss-Seidel diagonalization | BilevelJuMP as the *production* solver | Never for v2.0 — CLAUDE.md explicitly declines this; MPEC single-level blowup diverges from the thesis's decomposition intent and scales poorly past toy cases. |
| BilevelJuMP `BigMMode` (HiGHS) or `StrongDualityMode`/`ProductMode` (Ipopt) as the validation oracle's default modes | `SOS1Mode` / `IndicatorMode` | Only if Gurobi is licensed — **HiGHS.jl does not implement `MOI.SOS1` or `MOI.Indicator` constraint types** (re-verified today against HiGHS.jl's supported-constraints list), so those two BilevelJuMP modes are open-source-solver-incompatible today. `BigMMode` only needs binary variables (HiGHS-native) and `StrongDualityMode`/`ProductMode` only need an NLP solver (Ipopt, already wired) — prefer these two for the open-source-first validation oracle. |
| `select_optimizer(LP())` for the Benders master | `select_optimizer(MILP())` | Only once integer/binary-expansion investment lands (explicitly deferred milestone) — v2.0's master has no binary/integer variables. |
| Gauss-Seidel diagonalization (fixed-point outer loop) | PATHSolver/Complementarity.jl (simultaneous MCP) | Only if a future milestone deliberately recasts the multi-distributor Nash game as one simultaneous complementarity system rather than sequential per-distributor Benders solves. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **BilevelJuMP as the production planning solver** | (Restated from CLAUDE.md/v1 STACK — still correct for v2.0.) Single-level MPEC reductions blow up and diverge from the thesis's Benders/diagonalization method; BilevelJuMP's own MIP-mode mechanics (`BigMMode`, binary complementarity indicators) don't scale to realistic multi-distributor, multi-scenario planning instances the way a hand-rolled Benders cut loop does. | Hand-rolled Benders + Gauss-Seidel diagonalization |
| **BilevelJuMP's `SOS1Mode`/`IndicatorMode` without a licensed MIP solver** | HiGHS.jl (the open-source default) does not support `MOI.SOS1`/`MOI.Indicator` constraint sets — re-verified today. Silently falling back to these modes with HiGHS would error at solve time, not model-build time. | `BigMMode` (HiGHS) or `StrongDualityMode`/`ProductMode` (Ipopt) for the open-source validation path; reserve `SOS1Mode`/`IndicatorMode` for a licensed-Gurobi validation run only. |
| **PATHSolver.jl / Complementarity.jl for v2.0** | No genuine MCP/VI formulation exists yet — the Nash equilibrium here is a sequential fixed-point (Gauss-Seidel diagonalization over independent Benders solves), not a simultaneous complementarity system. Adding these now is premature machinery with no consumer. | Hand-rolled diagonalization outer loop (plain Julia `while` loop calling per-distributor Benders solves) |
| **DualDecomposition.jl for v2.0** | Targets Lagrangian decomposition of **stochastic MIPs**; v2.0 has neither stochastic scenarios nor integers in the planning layer. | Hand-rolled Benders; revisit only at the stochastic-scenario or integer-Lagrangian-cut milestone |
| **Coluna.jl / StructJuMP for v2.0** | Already declined in CLAUDE.md/v1 STACK for the same structural reasons; the continuous-Benders v2.0 scope does not change that calculus. | Hand-rolled decomposition with JuMP `@constraint` cut accumulation |
| **Rebuilding the follower JuMP model each Gauss-Seidel/Benders iteration** | Same performance pitfall CLAUDE.md flags for ADMM — the follower subproblem (and the reused `operational_oracle` SOCP) should be built once per distributor and re-solved with updated coupling-flow trial points, not rebuilt. Note: unlike ADMM's `Parameter`-based re-solve, Benders **master** growth is via genuinely NEW constraint rows (cuts) each iteration — that structural growth is expected and is not the anti-pattern; the anti-pattern is rebuilding the **follower/subproblem** model instead of re-solving it with a new RHS/trial point. | Build the follower model once; re-solve with updated trial coupling flow (RHS or `Parameter`); accumulate Benders cuts as new `@constraint` rows in the persistent master model. |
| **Adding BilevelJuMP/PATHSolver/Complementarity/DualDecomposition to the root `Project.toml`** | None are production runtime dependencies; only BilevelJuMP is even a validation tool, and only for tests. Padding the hard `[deps]` breaks the "no bespoke dependency the framework doesn't need" and "must remain removable" ethos already enforced for Gurobi/Mosek via `[weakdeps]`. | BilevelJuMP in `test/Project.toml` only, exactly like `Aqua`/`JET`/`TestItemRunner` |

## Stack Patterns by Variant

**Benders master (leader, per distributor):**
- `Model(select_optimizer(LP()))`, built once per distributor; continuous `y_inv`, `y_inv,flex`, `y_op,s`, epigraph `α`.
- Each outer iteration: solve → get trial `z_{y,s}^k` (import profile) → call the follower → receive `(w^k, π_s^k)` → add ONE new `@constraint(master, α >= w^k + sum(π_s^k .* (z_y .- z_y^k)))` (persistent model, growing row count — this is normal Benders growth, not the rebuild anti-pattern).

**Follower (transmission reinforcement, N2), continuous v2.0:**
- `Model(select_optimizer(LP()))` (or `QP()` if `c_x,op` is quadratic) built once; RHS/trial-point (`z_{y,s}` from the current master iterate) updated via `set_normalized_rhs` or a JuMP `Parameter` and re-solved — same idiom as v1's ADMM subproblems.
- Read `π_s = dual(coupling_constraint[s])` directly — same `dual(handle)` pattern as `_coupling_dual` in `src/models/oracle.jl`.

**N1 operation (distributor's own operational layer):**
- Reuse `operational_oracle(feeder, pf, aggregators; z, role = :leader, ...)` UNCHANGED as the lower-level solve, once the (currently-stubbed, `ArgumentError`-guarded) `z`-pin extension (PLAN-01/02) is implemented: add the coupling constraint `p_import == z` to `solve_welfare`, and have `_coupling_dual` read ITS dual instead of throwing. This is an architecture task inside the existing model file, not a new library.

**Multiple distributors → Nash:**
- Plain Julia outer `while` loop (Gauss-Seidel diagonalization): for each distributor `i` in turn, re-solve its Benders leader problem holding `{z_{j,y,s}}_{j≠i}` fixed at their latest values; track a small convergence-residual struct (mirrors the ADMM residual-tracking pattern already in the codebase) and plot with CairoMakie (already in stack).

**Validation oracle (tiny instances only):**
- Build the SAME 2–5-node leader-follower instance in `BilevelJuMP` (`Upper`/`Lower` model blocks), reformulate with `BigMMode` (HiGHS) as the open-source-first default, cross-check against the hand-rolled Benders answer; use `StrongDualityMode`/`ProductMode` (Ipopt) as a second independent check when big-M sensitivity is a concern. Reserve `SOS1Mode`/`IndicatorMode` for an optional Gurobi-licensed run.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| JuMP 1.31.0 | MOI (Pkg-resolved) | Bump from 1.30.1 is additive/polish only (nonlinear-expression handling, error messages, docs); `Project.toml` compat `"1.30.1"` already admits it — no compat-bound edit needed, just `Pkg.up JuMP`. |
| BilevelJuMP 0.6.3 | JuMP 1.x, Dualization 0.3.5, Reexport | `Dualization` is pulled in transitively for `StrongDualityMode`; do not add it directly. |
| BilevelJuMP `BigMMode` | Any MIP solver with binary-variable support | HiGHS satisfies this — no licensed solver required. |
| BilevelJuMP `StrongDualityMode` / `ProductMode` | Any NLP solver (or MIP for binary-expansion products) | Ipopt satisfies this — already wired via `select_optimizer(NLP())`. |
| BilevelJuMP `SOS1Mode` / `IndicatorMode` | A MIP solver implementing `MOI.SOS1`/`MOI.Indicator` | **HiGHS.jl does NOT implement these MOI constraint sets** (re-verified 2026-07-22 against HiGHS.jl's README supported-constraints list) — these two modes require Gurobi/CPLEX/SCIP/Xpress. Gate behind the existing `GurobiChoice`/weakdep extension if ever used. |
| HiGHS 1.24.1 (`select_optimizer(LP())`) | Julia ≥ 1.10 | Already the Benders-master solver of record; no change from v1. |
| PATHSolver 1.7.9 / Complementarity 0.9.0 / DualDecomposition 0.3.4 | — | Confirmed current on the registry today; not added — kept on the shelf per "What NOT to Use" above. |

## Sources

- **Julia General registry `Versions.toml`** (raw.githubusercontent.com/JuliaRegistries/General), fetched 2026-07-22 — HIGH confidence: JuMP bumped **1.30.1 → 1.31.0** since the v1.0 STACK snapshot (2026-07-18); BilevelJuMP 0.6.3, PATHSolver 1.7.9, Complementarity 0.9.0, DualDecomposition 0.3.4, ParametricOptInterface 0.15.3, HiGHS 1.24.1, Clarabel 0.11.1, Ipopt 1.15.0, SCS 2.6.4, MathOptInterface 1.51.2, Dualization 0.3.5 all **unchanged and current**.
- **GitHub `jump-dev/JuMP.jl` release notes for v1.31.0**, fetched 2026-07-22 — HIGH confidence: nonlinear-expression/error-message/doc changes only, no breaking API changes affecting `Parameter`, `dual()`, or cone constraints.
- **`joaquimg/BilevelJuMP.jl` GitHub repo + docs (`tutorials/modes/`)**, fetched 2026-07-22 — HIGH confidence: current version 0.6.3 (2026-03-13, actively maintained, 356 commits); confirmed mode roster `SOS1Mode`, `IndicatorMode`, `BigMMode`, `ProductMode`, `StrongDualityMode`, `MixedMode` and their solver requirements.
- **`jump-dev/HiGHS.jl` README (supported MOI constraint types)**, fetched 2026-07-22 — HIGH confidence: HiGHS.jl supports affine (in)equalities, bounds, integer/binary, semicontinuous/semiinteger — **does NOT** support `MOI.SOS1` or `MOI.Indicator`, which rules out BilevelJuMP's `SOS1Mode`/`IndicatorMode` on the open-source-only path.
- **Julia General registry `Deps.toml`/`Package.toml` for BilevelJuMP**, fetched 2026-07-22 — HIGH confidence: hard deps are `Dualization`, `JuMP`, `LinearAlgebra`, `MathOptInterface`, `Reexport` — no hard dependency on PATHSolver (confirms PATHSolver is only needed for the user's own downstream MCP choice, not by BilevelJuMP itself).
- **Codebase** — `src/solver/ProblemClass.jl`, `src/solver/factory.jl`, `src/models/oracle.jl` (`operational_oracle`/`_coupling_dual`), `Project.toml`, `test/Project.toml` — read 2026-07-22 to confirm the existing `select_optimizer(::ProblemClass)` factory already covers every solver class v2.0's continuous Benders master/subproblems need, and to confirm the SEAM-01 z-pin stub is the concrete integration point for the follower coupling dual.
- **`.planning/PROJECT.md`, `CLAUDE.md`, `.planning/research/THEORY-papers.md` (Paper 2 / PSR N1–N2 note), `.planning/research/v1.0/STACK.md`** — project context and LOCKED v2.0 scope (continuous-before-integer, hand-rolled Benders + diagonalization, BilevelJuMP as validation-oracle-only).

---
*Stack research for: Julia (JuMP) Stackelberg-Nash TSO-DSO planning layer — hand-rolled Benders + Gauss-Seidel diagonalization, v2.0*
*Researched: 2026-07-22*
