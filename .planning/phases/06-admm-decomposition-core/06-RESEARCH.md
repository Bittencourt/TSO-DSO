# Phase 6: ADMM Decomposition Core - Research

**Researched:** 2026-07-19
**Domain:** Convex dual decomposition (ADMM) of a social-welfare SOCP over a radial distribution feeder — Julia + JuMP, build-once/re-solve, prices-as-duals
**Confidence:** HIGH on the ADMM split math (traced to thesis 3.46/3.47 + derived from a single augmented Lagrangian), the code seams to reuse (read from source), and the JuMP re-solve API (verified live via Context7). MEDIUM on the exact printed sign in thesis 3.47 (digest transcription ambiguity — pinned operationally by the 2-bus regression) and the ρ value for these fixtures (needs empirical tuning; adaptive-ρ is Phase 7).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
CONTEXT.md marks this an **auto-generated decomposition-algorithm phase** — the discuss step was skipped because "the ADMM split, the dual-ascent update, and the parameter re-solve pattern all come from the thesis + CLAUDE.md's explicit ADMM guidance." There are **no user-preference grey areas**. The anchored decisions (all from source thesis + Phases 1–5 seams) are:

- **ADMM split (ADMM-01):** decompose the centralized GLB-CVX into `AGR-OPT` (per-node aggregator/device subproblem — house-separable QP) and `DSO-OPT` (per-hour network subproblem — the SOCP branch flow), coupled at the aggregator net injection `p_ag` / the nodal price `λ_j`. Dual ascent: `λ_j ← λ_j + ρ·R_{p,j}`. REUSE the exact same device (`contribute!`) and power-flow (`ConvexBranchFlow.contribute!`) builders as the centralized `solve_welfare` — ADMM is **orchestration, not a re-implementation**.
- **Build-once / re-solve (ADMM-03, the perf discipline — CLAUDE.md):** construct `AGR-OPT` and `DSO-OPT` JuMP models ONCE, then in the loop update price/penalty terms via JuMP `Parameter`s / `set_normalized_rhs` / `set_objective_coefficient` and WARM-START from the previous iterate. NEVER rebuild a JuMP model inside the loop. Track residuals in a small struct.
- **Cross-validation (ADMM-04):** an automated test asserting ADMM welfare AND duals (DADPs) match the centralized monolithic optimum within tolerance on every small fixture (2-bus, IEEE-13). This is the correctness gate.
- **Solver/status discipline (CLAUDE.md):** subproblems solved via `select_optimizer` (AGR-OPT QP → Clarabel; DSO-OPT SOCP → Clarabel), gated on `assert_solved!`; the SOCP exactness gate (PF-04) applies to the DSO-OPT subproblem so ADMM prices are only trusted when exact.
- **Hand-rolled loop (CLAUDE.md):** no decomposition mega-framework (Coluna/StructJuMP) — a hand-rolled dual-ascent loop with full control of the updates.

### Claude's Discretion
The concrete JuMP re-solve mechanics (parameters vs coefficient updates), the module layout under `src/admm/`, the residual-tracking struct shape, the ρ value for these fixtures, and the stopping rule for Phase-6 scope — all anchored to the seams above.

### Deferred Ideas (OUT OF SCOPE)
- Convergence hardening / adaptive-ρ / dual-residual stopping / IEEE-123 scale → **Phase 7** (ADMM-02, ADMM-05).
- Experiment harness / scenario sweeps using ADMM → **Phase 8** (EXP-01/02).
- Stochastic / rolling-horizon ADMM variants → later milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADMM-01 | ADMM solves the operational problem via per-node `AGR-OPT` + per-hour `DSO-OPT` with dual ascent, **reusing the same builders** as centralized. | The split derivation (§Architecture Pattern 1), the seam-reuse map (§Architecture Pattern 4), and the dual update (§Architecture Pattern 2) give the exact decomposition traced to thesis 3.46/3.47 and the concrete `contribute!` reuse. |
| ADMM-03 | ADMM subproblems built **once** and re-solved via parameter/coefficient updates + warm starts (no per-iteration rebuild). | §Architecture Pattern 3 gives the verified JuMP mutator surface (`set_objective_coefficient`, `set_normalized_rhs`, `Parameter`/`set_parameter_value`, `set_start_value`) and the recommended coefficient-update strategy that avoids the indefinite-QP trap. |
| ADMM-04 | Automated cross-validation asserts ADMM welfare **and** duals match the centralized optimum on every small fixture. | §Architecture Pattern 5 + §Validation Architecture give the metric, tolerance, fixtures (2-bus, IEEE-13 ground), and the `extract_dlmp` dual-match identity. |

> Note: the roadmap traceability table maps **ADMM-01, ADMM-03, ADMM-04** to Phase 6. (ADMM-02 residual-normalized adaptive-ρ and ADMM-05 diagnostics are Phase 7.) The REQUIREMENTS.md prose numbering and the traceability table differ slightly in which ID carries the "cross-validation" vs "build-once" text; this phase implements **the split + dual ascent (ADMM-01), the build-once/re-solve discipline, and the automated centralized cross-validation** — the three behaviors named in the CONTEXT and success criteria, regardless of the numbering skew.
</phase_requirements>

## Summary

The operational model is a **single-level convex social-welfare maximization** (`GLB-CVX`, thesis eq. 3.38) already implemented centrally in `src/models/welfare_solve.jl`. Phase 6 adds the **ADMM solve strategy** that decomposes it into per-node aggregator subproblems (`AGR-OPT`, thesis 3.46) and a network subproblem (`DSO-OPT`, thesis 3.47), coupled through the nodal active-power balance (3.31) whose dual `λ_j` **is** the day-ahead dynamic price (DADP). The transactive prices are dual variables, so the entire value of this phase is that **ADMM recovers the centralized optimum AND its duals** to tolerance — nothing else certifies correctness.

The single most important architectural finding: **this is genuine 2-block ADMM, and both blocks reuse the existing Phase-1–5 builders verbatim.** `DSO-OPT` reuses `ConvexBranchFlow.contribute!` (P, Q, v, v̂, l, cone, vdrop, cpydrop, smax, and the `:Rp`/`:Rq` residuals). `AGR-OPT` reuses each device's `contribute!` (returning `(; vars, p_inject, utility)`) and the `Aggregator` roll-up (3.21–3.23). ADMM changes only **how the coupling balance is closed** — a hard `== 0` constraint in the centralized model becomes a **linear price term + quadratic ρ-penalty in the objective** — and orchestrates the alternating solves plus the dual ascent `λ_j ← λ_j + ρ·R_{p,j}` (3.46/3.47 dual update). This is orchestration, not model re-implementation, exactly as CONTEXT locks.

The build-once/re-solve mechanics were **verified live against JuMP 1.30.1 docs (Context7)**. The recommended pattern introduces a single explicit coupling variable per (node, hour) — the aggregator net injection `pag_j[t]` — and updates only its scalar objective coefficient each iteration via `set_objective_coefficient` (one call per node/hour). This avoids the documented trap that **modeling the price `λ_j` as a JuMP `Parameter` produces an indefinite `λ·pag` bilinear term that Clarabel (a convex conic solver) rejects.** Clarabel is `copy_to`-only (a Phase-1-verified fact already encoded in `factory.jl`), so warm starts are a no-op for it and the re-solve still re-copies to the solver — but the JuMP-side rebuild (the expensive part Pitfall 5 targets) is eliminated, which is what ADMM-03 actually requires.

**Primary recommendation:** Add `src/admm/` with (1) an `AgrOpt` per-node subproblem struct + builder reusing device/aggregator `contribute!`, (2) a `DsoOpt` network subproblem struct + builder reusing `ConvexBranchFlow.contribute!` and the priced-export frontier, (3) a hand-rolled `solve_admm` dual-ascent loop using single-variable `set_objective_coefficient` updates and a fixed ρ tuned on the 2-bus fixture, and (4) an automated `@testitem` cross-validation asserting ADMM welfare ≈ `objective_value(centralized)` and ADMM `λ_j` ≈ `extract_dlmp(centralized_ctx)` on the 2-bus and IEEE-13 ground fixtures, with `assert_socp_exact!` gating the final DSO-OPT.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-node device/aggregator scheduling (`AGR-OPT`) | Device/Aggregator layer (`src/devices/*`) | ADMM orchestrator (`src/admm/`) | Devices own their own vars/constraints/utility (thesis 3.2–3.20); AGR-OPT wraps the existing `contribute!` returns into a per-node QP. `[CITED: src/devices/AbstractDevice.jl]` |
| Network SOCP branch flow (`DSO-OPT`) | Power-flow layer (`src/powerflow/ConvexBranchFlow.jl`) | ADMM orchestrator | The SOCP + LinDistFlow exactness copy is already built and validated; DSO-OPT reuses `contribute!` and only re-closes the balance as a penalty. `[CITED: src/powerflow/ConvexBranchFlow.jl]` |
| Coupling constraint closure (3.31) | ADMM orchestrator (`src/admm/`) | — | The one thing that genuinely changes: `== 0` (centralized) → linear-price + ρ-penalty (ADMM). New code. |
| Dual ascent / price update `λ_j ← λ_j + ρ·R` | ADMM orchestrator | — | The outer loop; hand-rolled per CLAUDE.md. New code. |
| Solver selection + status gate | Solver layer (`factory.jl`, `status.jl`) | ADMM orchestrator | `select_optimizer(QP())`/`select_optimizer(SOCP())` + `assert_solved!` reused unchanged (INFRA-02/03). `[CITED: src/solver/factory.jl]` |
| SOCP exactness gate on DSO-OPT | Model layer (`exactness.jl`) | ADMM orchestrator | `assert_socp_exact!` reused on the converged DSO subproblem (PF-04). `[CITED: src/models/exactness.jl]` |
| Price extraction / cross-validation | Pricing layer (`dlmp.jl`) + test | ADMM orchestrator | `extract_dlmp` on the centralized ctx is the ground-truth dual ADMM must match. `[CITED: src/pricing/dlmp.jl]` |

## Standard Stack

**No new packages.** This phase is pure orchestration over the existing Phase-1–5 stack; every dependency is already resolved in the committed `Manifest.toml`.

### Core (already installed — versions read from `Manifest.toml`)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 | Algebraic modeling, per-constraint `dual()`, `Parameter`s, in-place coefficient/RHS mutators, warm starts | The re-solve API surface below is verified against this exact version. `[VERIFIED: Manifest.toml]` |
| MathOptInterface | 1.51.2 | Solver abstraction under JuMP; `MOI.Parameter` set handling | Transitive via JuMP; do not pin independently. `[VERIFIED: Manifest.toml]` |
| Clarabel | 0.11.1 | Primary conic solver for both `AGR-OPT` (QP) and `DSO-OPT` (SOCP); accurate duals (prices ARE duals) | Native quadratic objective + SOCP; high-accuracy IPM duals. `copy_to`-only (see Pitfall 4). `[VERIFIED: Manifest.toml]` |
| HiGHS | 1.24.1 | Optional warm-startable QP backend for `AGR-OPT` hot re-solves | Supports the incremental interface + warm starts, unlike Clarabel — a fallback if AGR-OPT re-copy overhead ever dominates (not expected at Phase-6 scale). `[VERIFIED: Manifest.toml]` |

### Supporting (already installed)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TestItemRunner / TestItems | 1.1.5 / 1.0.0 | `@testitem` cross-validation harness | The ADMM-04 correctness gate; name-substring filtered (`occursin("admm", ti.name)`). `[CITED: test/runtests.jl]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Clarabel for AGR-OPT | HiGHS (QP) | HiGHS warm-starts and supports the incremental interface, so re-solve avoids a full re-copy. But Clarabel gives tighter duals and keeps one solver for both blocks; the AGR-OPT dual is not the priced quantity (λ_j lives on the coupling), so accuracy pressure is lower — still, prefer Clarabel for uniformity and revisit only if profiling shows AGR re-copy dominates (Phase 7). |
| Hand-rolled loop | Coluna.jl / StructJuMP | Explicitly rejected by CLAUDE.md — heavyweight, impose structure that fights a research bench. |
| Coefficient-update re-solve | JuMP `Parameter`s throughout | Parameters are clean for the **penalty target** (wrapped in a convex square) but produce an **indefinite bilinear** `λ·pag` term for the price coefficient that Clarabel rejects — see Pitfall 5. Use coefficient updates for the price, parameters only where the term stays convex. |

**Installation:** none — `Pkg.instantiate()` against the committed `Manifest.toml` already provides everything.

**Version verification:** performed against the committed `Manifest.toml` (the reproducibility source of truth), not a live registry query, because the environment is pinned: JuMP 1.30.1, MOI 1.51.2, Clarabel 0.11.1, HiGHS 1.24.1. `[VERIFIED: Manifest.toml]`

## Package Legitimacy Audit

> **Not applicable.** This phase installs **no external packages** — it adds `src/admm/*.jl` files that depend only on already-vendored, already-pinned dependencies (JuMP, Clarabel, HiGHS, MOI). No registry install, no `Project.toml` `[deps]` change is required or recommended. slopcheck / registry verification is moot because the dependency set does not change. If planning later discovers a genuinely new dependency is wanted, gate it behind a `checkpoint:human-verify` and run the full legitimacy gate then.

## Architecture Patterns

### System Architecture Diagram

```
                         solve_admm(feeder, ConvexBranchFlow(), aggregators; λ₀, T, ρ, maxiter, tol)
                                                     │
                    ┌────────────────────────────────┼─────────────────────────────────┐
                    │  BUILD ONCE (outside the loop)                                     │
                    │                                                                    │
        ┌───────────▼───────────┐                              ┌─────────────────────────▼──────────────┐
        │  AGR-OPT[j]  (per node)│  reuses                     │  DSO-OPT  (whole network, all T)         │
        │  QP, Clarabel          │  device.contribute!         │  SOCP, Clarabel                          │
        │  vars: device vars,    │  + Aggregator roll-up       │  reuses ConvexBranchFlow.contribute!     │
        │        pag_j[t]        │  (3.2–3.23)                 │  vars: P,Q,v,v̂,l, cone, pag_dso_j[t],    │
        │  obj: U_ag,j           │                             │        p_import (priced, free-sign)      │
        │       −λ_j·pag_j       │                             │  obj: λ₀ᵀp_import                        │
        │       −(ρ/2)(pag_j+c_j)²│                            │       −λ_j·pag_dso_j                      │
        └───────────┬───────────┘                              │       +(ρ/2)(pag_dso_j − a_j)²           │
                    │                                          └─────────────────────────┬──────────────┘
                    │                                                                    │
        ════════════╪═════════════════════ ADMM ITERATION k ═══════════════════════════╪════════════════
                    │                                                                    │
          (1) update AGR coeffs on pag_j[t]:                          (2) update DSO coeffs on pag_dso_j[t]:
              set_objective_coefficient(                                   set_objective_coefficient(
                agr, pag_j[t], −λ_j[t] − ρ·c_j[t])                           dso, pag_dso_j[t], −λ_j[t] − ρ·a_j[t])
              c_j[t] = netflow_j from prev DSO iterate                     a_j[t] = pag_j from current AGR iterate
                    │                                                                    │
          solve AGR-OPT[j] ∀j (assert_solved!)  ──── a_j = value(pag_j) ───►   solve DSO-OPT (assert_solved!)
                    │                                                                    │
                    │◄──────────── c_j = value(pag_dso_j) (network injection) ───────────┤
                    │                                                                    │
          (3) primal residual  R_p,j[t] = value(pag_j[t]) − value(pag_dso_j[t])          │
              dual update       λ_j[t] ← λ_j[t] + ρ·R_p,j[t]   (reactive: μ_j ← μ_j + ρ·R_q,j)
                    │
              STOP when max_{j,t}|R_p,j|, |R_q,j| ≤ ε  OR iter = maxiter (fail loud on cap)
                    │
        ════════════▼════════════════════════════════════════════════════════════════════════════════
              at convergence:
                • assert_socp_exact!(dso_ctx)   ← PF-04 gate on the final DSO subproblem
                • welfare  = Σ_j value(U_ag,j) − Σ_t λ₀[t]·value(p_import[t])
                • dadp     = λ   (converged coupling price)
              return (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)
```

### Recommended Project Structure

```
src/admm/
├── AgrOpt.jl        # per-node aggregator subproblem: struct + builder (reuses device/Aggregator contribute!) + coeff-update + solve
├── DsoOpt.jl        # network subproblem: struct + builder (reuses ConvexBranchFlow.contribute! + priced-export frontier) + coeff-update + solve
├── residuals.jl     # AdmmResiduals tracking struct (primal/dual residual traces, iters)
└── solve_admm.jl    # the hand-rolled dual-ascent loop + welfare recovery + PF-04 gate + return tuple

test/
├── fixtures_phase6.jl   # @testmodule Phase6Fixtures: two_bus_feeder() + build_two_bus_aggregators(); reuse Phase4Fixtures for IEEE-13
└── test_admm.jl         # @testitem cross-validation vs solve_welfare (welfare + duals), build-once assertion, exactness gate
```

Wire the four `src/admm/*.jl` includes into `src/TSODSO.jl` **after** `models/oracle.jl` and the pricing files (ADMM consumes the solved-ctx seams and `extract_dlmp`). Follow the existing include-graph convention (each seam file declares its own exports). `[CITED: src/TSODSO.jl]`

### Pattern 1: The ADMM split — one augmented Lagrangian, two blocks

**What:** Derive both subproblems from a *single* augmented Lagrangian of the centralized `GLB-CVX`, so the signs are guaranteed self-consistent (the digest's printed 3.47 sign is ambiguous — do not copy it blindly). `[CITED: .planning/research/THEORY-thesis.md §2.6, eqs 3.46/3.47]`

The centralized problem (thesis 3.38, as built in `solve_welfare`) maximizes welfare subject to the per-node active balance (3.31). At each **load** node `j` the balance in the code is `netflow_j + pag_j = 0` where `netflow_j` = branch inflow − losses − outflow (written by `ConvexBranchFlow.contribute!` into `ctx.residuals[:Rp][j]`) and `pag_j` = aggregator net injection `Σ_d p_inject − Pdc` (written by `Aggregator.contribute!`). `[CITED: src/powerflow/ConvexBranchFlow.jl, src/devices/Aggregator.jl]`

Augmented Lagrangian (MAX form; multiplier `λ_j`, penalty `ρ>0`; reactive analog with `μ_j`, `R_q,j`):

```
L_ρ = Σ_j U_ag,j  −  λ₀ᵀ p_import
      −  Σ_j Σ_t λ_j[t]·R_{p,j}[t]  −  (ρ/2) Σ_j Σ_t R_{p,j}[t]²          (+ reactive terms)
   where  R_{p,j}[t] = netflow_j[t] + pag_j[t]          (the physical balance 3.31)
```

**AGR-OPT[j]** (block 1, fix `netflow_j = c_j` from previous DSO iterate; separable per node → per-node QP, thesis 3.46):
```
max_{device vars}  U_ag,j(devices)  −  Σ_t λ_j[t]·pag_j[t]  −  (ρ/2) Σ_t ( c_j[t] + pag_j[t] )²
   s.t.  pag_j[t] = Σ_d p_inject_d[t] − Pdc[t]   (thesis 3.22),  device constraints (3.2–3.9)
```
(the dropped `−λ_j·c_j` is constant in this block). This is **exactly thesis eq. 3.46**: `max U_ag − λ_jᵀ p_ag − (ρ/2)‖R_{p,j}‖²`. `[CITED: THEORY-thesis.md eq 3.46]`

**DSO-OPT** (block 2, fix `pag_j = a_j` from current AGR iterate; whole network, thesis 3.47):
```
min_{P,Q,v,v̂,l,p_import}  λ₀ᵀ p_import  −  Σ_j Σ_t λ_j[t]·pag_dso_j[t]  +  (ρ/2) Σ_j Σ_t ( a_j[t] − pag_dso_j[t] )²
   s.t.  ConvexBranchFlow constraints (3.29–3.45),  and  netflow_j[t] + pag_dso_j[t] = 0  (hard balance)
```
Here `pag_dso_j := −netflow_j` is introduced as an explicit **coupling variable** (a renaming pinned by the hard balance), so the objective touches a *single* variable per (j,t) — the key that makes `set_objective_coefficient` a one-call update (Pattern 3). This is the **consensus-ADMM rendering** of thesis 3.47; it is mathematically identical to the thesis's direct dualization (where `pag` enters `netflow`'s balance as a parameter), and it maps cleanly onto the existing balance-closure code in `solve_welfare`. `[CITED: THEORY-thesis.md eq 3.47]`

**When to use:** always, for this phase. Deriving from one Lagrangian is the guard against the sign bug (Pitfall 6/7).

### Pattern 2: The dual (price) update — the DADP recovery identity

**What:** After both blocks solve, compute the primal coupling residual and take one gradient-ascent step on the dual: `[CITED: THEORY-thesis.md §2.6 dual update]`
```
R_{p,j}[t] = value(pag_j[t])  −  value(pag_dso_j[t])      # consensus violation (→ 0 at optimum)
λ_j[t]  ←  λ_j[t]  +  ρ · R_{p,j}[t]                       # thesis: λ ← λ + ρ·R_{p,j}
R_{q,j}[t] = value(qag_j[t])  −  value(qag_dso_j[t])
μ_j[t]  ←  μ_j[t]  +  ρ · R_{q,j}[t]                       # thesis: μ ← μ + ρ·R_{q,j}
```
`ρ` is both the penalty weight *and* the dual step (standard ADMM). At convergence `R_{p,j} → 0` (the balance 3.31 holds) and `λ_j → the DADP` = the dual of the centralized `:balance_p[j]`. This is the load-bearing identity the cross-validation checks. `[CITED: THEORY-thesis.md §2.6; src/pricing/dlmp.jl extract_dlmp]`

**Sign convention (critical — Pitfall 7):** `λ_j` converges to `dual(balance_p[j,t])` from the centralized solve **up to the sign convention JuMP uses for equality duals under a `Max` objective**. Pin the sign on the 2-bus fixture where the price is analytically known, and assert it. The consensus form above is written so the recovered `λ_j` carries the same sign as `extract_dlmp` returns (positive = marginal cost of consumption, per `dlmp.jl`'s pinned convention) — but **verify, don't assume**. `[CITED: src/pricing/dlmp.jl]`

### Pattern 3: Build-once / re-solve — the verified JuMP mutator surface (ADMM-03)

**What:** Build each subproblem model once; between iterations mutate only the objective coefficient of the single coupling variable. **Verified live against JuMP 1.30.1.** `[VERIFIED: Context7 /jump-dev/jump.jl, docs/src/manual/objective.md + variables.md]`

Per-iteration update — **one call per (node, hour), each block:**
```julia
# AGR-OPT[j]: linear coeff on pag_j[t] is −λ_j[t] − ρ·c_j[t]  (penalty quadratic coeff −ρ/2 is FIXED, built once)
set_objective_coefficient(agr.model, agr.pag[t], -λ[j][t] - ρ * c[j][t])

# DSO-OPT: linear coeff on pag_dso_j[t] is −λ_j[t] − ρ·a_j[t]  (penalty quadratic coeff +ρ/2 is FIXED, built once)
set_objective_coefficient(dso.model, dso.pag[j, t], -λ[j][t] - ρ * a[j][t])
```
`set_objective_coefficient(model, x, c)` modifies a linear coefficient in place (works for linear and quadratic objectives). The **quadratic** self-term `pag²` is built once and never touched (its coefficient is the fixed ∓ρ/2); only the linear coefficient absorbs both the price `λ_j` and the shifted penalty target. `[VERIFIED: Context7 objective.md "Modify an objective coefficient"]`

Derivation of the coefficient (AGR-OPT, MAX): `−(ρ/2)(pag+c)² = −(ρ/2)pag² − ρc·pag − (ρ/2)c²`; combined with `−λ·pag` the linear-in-`pag` coefficient is `−λ − ρc`, the quadratic coefficient is `−ρ/2` (fixed), and the constant `−(ρ/2)c²` is dropped (does not change the argmax; welfare is recomputed from primal values for reporting — see Pattern 5).

Available mutators (all verified) and when to use them:
| Mutator | Verified signature | Use in ADMM |
|---------|--------------------|-------------|
| `set_objective_coefficient` | `set_objective_coefficient(model, x, c)` (linear); `set_objective_coefficient(model, x, y, c)` (quadratic) | **Primary** — update the price+penalty-shift linear coefficient on `pag_j`/`pag_dso_j` each iteration. `[VERIFIED: Context7]` |
| `set_normalized_rhs` | `set_normalized_rhs(con, v)`; read `normalized_rhs(con)` | **Alternative** for the DSO penalty target: if `pag_dso_j` is pinned by a constraint `pag_dso_j == a_j`, update `a_j` via RHS instead of a coefficient. Either works; coefficient-update keeps one code path. `[VERIFIED: Context7 constraints.md]` |
| `@variable(m, p in Parameter(v))` + `set_parameter_value(p, v)` / `parameter_value(p)` | as shown | **Only for the penalty target** `c_j`/`a_j` (safe — wrapped in a convex square). **Do NOT** use for `λ_j` (indefinite bilinear — Pitfall 5). `[VERIFIED: Context7 variables.md/nonlinear.md]` |
| `set_start_value` / `start_value` | `set_start_value(x, v)` | Express warm starts from the previous iterate for interface-completeness and a future HiGHS AGR route; **Clarabel ignores them** (IPM, `copy_to`-only — Pitfall 4). `[VERIFIED: Context7 variables.md; src/solver/factory.jl comment]` |

**When to use:** always. The recommended path is the single-coupling-variable + `set_objective_coefficient` design (no `Parameter`s, no indefinite terms, one call per (j,t)).

### Pattern 4: Reusing the builders — ADMM is orchestration (ADMM-01)

**What:** The subproblem builders call the exact same `contribute!` methods as `solve_welfare`. `[CITED: src/models/welfare_solve.jl, src/devices/Aggregator.jl, src/powerflow/ConvexBranchFlow.jl]`

**AGR-OPT[j] builder** (thin wrapper, per aggregator):
1. `model = Model(select_optimizer(QP()))`; `ctx = ModelContext(model)`; stash `T`. `[CITED: src/solver/factory.jl]`
2. Roll up the aggregator's devices exactly as `Aggregator.contribute!` does — drive each `res = contribute!(d, ctx; T)`, sum `res.p_inject` and `res.utility` (3.21–3.22). **Reuse the aggregator's roll-up logic; do not re-derive it.** Two options: (a) call `Aggregator.contribute!` and read the returned `(; vars, p_inject, utility)` (it also writes `:Rp`/`:Rq`, which AGR-OPT can simply ignore — those residuals are never closed here), or (b) a small `agr_rollup!` helper factored out of `Aggregator.contribute!` that returns the same tuple without the residual write. Prefer (a) for zero new logic; the stray `:Rp` write is harmless because AGR-OPT never pins it.
3. Create the coupling variable `pag_j[t]` and constrain `pag_j[t] == Σ res.p_inject[t] − Pdc[t]` (thesis 3.22). Add the objective `add_to_objective!`-style: `U_ag,j − (ρ/2)·pag_j²` (fixed part) and the per-iteration linear term via `set_objective_coefficient`.
4. Reactive: `qag_j[t] == −Pdc[t]·tan(arccos φ)` (thesis 3.23) — this is a **constant** (no device reactive), so `qag_j` is fixed; still expose it for the μ update.
5. Run the **mandatory App. C battery-complementarity check** on the AGR-OPT solution (`assert_battery_complementarity!`) — the batteries live in AGR-OPT now. `[CITED: src/models/welfare_solve.jl assert_battery_complementarity!]`

**DSO-OPT builder** (one network model, all T):
1. `model = Model(select_optimizer(SOCP()))`; `ctx = ModelContext(model)`; stash `feeder`/`T`; register the SOC bridges exactly as `solve_welfare` does. `[CITED: src/models/welfare_solve.jl]`
2. `contribute!(ConvexBranchFlow(), ctx, feeder; T)` — builds P, Q, v, v̂, l, `cone`, `vdrop`, `cpydrop`, `smax`, `:Rp`, `:Rq`, and stashes `pf_vars`. **Verbatim reuse.** `[CITED: src/powerflow/ConvexBranchFlow.jl]`
3. Priced frontier at root: `p_import` (and `q_import`) as in `solve_welfare(allow_export=true)` — **free-sign export is mandatory** (the SOC-exactness enabler, PF-04). Add `−λ₀ᵀp_import` cost. `[CITED: src/models/welfare_solve.jl step 4]`
4. Root balance closed **hard** (`:Rp[root] + p_import == 0`) — the root has no aggregator. Load-node balances closed with the coupling variable `pag_dso_j` (`:Rp[j] + pag_dso_j == 0`), then penalized against `a_j`.
5. `assert_solved!(model; dual=true)` each solve; `assert_socp_exact!(ctx)` on the **converged** solve (Pattern 5 / Pitfall 3).

**What thin wrappers are needed:** an `agr_rollup!` (or direct `Aggregator.contribute!` reuse) and the two coupling-variable closures. Nothing re-implements device physics, network physics, the exactness copy, the exactness gate, the battery check, or the solver factory.

### Pattern 5: Cross-validation against centralized (ADMM-04) — the correctness gate

**What:** An automated `@testitem` that solves the **same** fixture both ways and asserts agreement. `[CITED: .planning/research/PITFALLS.md Pitfall 2, Pitfall 7]`
```julia
# ground truth (Phase 4/5)
ctx_c, obj_c, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs; T, λ₀, allow_export=true)
dlmp_c = extract_dlmp(ctx_c)                       # (N,T) centralized duals — the DADP ground truth

# ADMM
res = solve_admm(feeder, ConvexBranchFlow(), aggs; T, λ₀, ρ, maxiter, tol, allow_export=true)

@test isapprox(res.welfare, obj_c; rtol = welfare_rtol)          # welfare match
@test isapprox(res.λ,       dlmp_c[load_buses, :]; atol, rtol)   # DUAL (price) match — the load-bearing one
@test res.exact_maxgap < exact_τ                                 # PF-04 on the converged DSO-OPT
```
- **Welfare metric:** `res.welfare` (recomputed from primal `Σ U_ag − λ₀ᵀp_import`, *not* the penalized subproblem objective) vs `objective_value(centralized)`. Suggested `rtol ≈ 1e-4`.
- **Dual metric:** ADMM `λ_j` vs `extract_dlmp(ctx_c)` at the load buses. This is the definitive DADP check and the whole point of the phase. Tolerance is looser than the solver's dual accuracy because ADMM stops at a finite residual `ε`; suggest `atol` tied to `ρ·ε` and `rtol ≈ 1e-3` (tune with ρ/ε). `[CITED: PITFALLS.md Pitfall 7 "ADMM dual must equal centralized dual"]`
- **Fixtures:** the **2-bus** (new, minimal, analytic price) and the **IEEE-13 ground** fixture (`build_ieee13_ground_aggregators`, `allow_export=true`). Both are "small enough to solve monolithically," which is the ADMM-04 predicate. `[CITED: test/fixtures_phase4.jl build_ieee13_ground_aggregators]`

**When to use:** this is the acceptance gate for the phase — the false-convergence safety net that Pitfall 2 warns primal-residual stopping alone cannot provide.

### Anti-Patterns to Avoid
- **Modeling `λ_j` as a JuMP `Parameter`.** `λ_j·pag_j` becomes an indefinite bilinear term; Clarabel (convex conic) rejects it. Use `set_objective_coefficient` for the price. (Pitfall 5.)
- **Rebuilding the JuMP models each iteration.** The dominant avoidable perf sink and an architecture-rewrite risk (Pitfall 1). Build once, mutate coefficients.
- **Reading the penalized subproblem objective as "welfare."** It includes the ρ-penalty and dual terms; recompute welfare from primal values.
- **Trusting DSO-OPT prices before the exactness gate.** A strict SOC cone makes `l` fictitious and the duals meaningless; run `assert_socp_exact!` on the converged DSO subproblem (PF-04). (Pitfall 3.)
- **Copying the thesis 3.47 sign literally.** Derive both blocks from one Lagrangian; pin the recovered-price sign on the 2-bus fixture. (Pitfall 6.)
- **Stopping on the primal residual with no maxiter cap / no centralized cross-check.** Cap iterations and fail loud; the cross-validation is the real correctness net. (Pitfall 2.)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-node device scheduling QP | A fresh device model in ADMM | `contribute!(device, ctx; T)` + `Aggregator` roll-up | Physics + utility + App. C battery proof already implemented and tested (Phase 3). `[CITED: src/devices/*]` |
| Network SOCP + exactness copy | A re-derived branch-flow model | `contribute!(ConvexBranchFlow(), ctx, feeder; T)` | The LinDistFlow exactness copy is subtle and load-bearing; reuse the validated one. `[CITED: src/powerflow/ConvexBranchFlow.jl]` |
| SOCP exactness certification | A bespoke `l·v ≈ P²+Q²` check in ADMM | `assert_socp_exact!(dso_ctx)` | Scale-free relative gate + price refusal already built (PF-04). `[CITED: src/models/exactness.jl]` |
| Solver selection + status gate | Naming Clarabel/HiGHS in ADMM | `select_optimizer(QP()/SOCP())` + `assert_solved!` | INFRA-02/03; no model may name a solver. `[CITED: src/solver/factory.jl, src/core/status.jl]` |
| Ground-truth duals for the test | A separate reference computation | `extract_dlmp(centralized_ctx)` | The DADP definition + PF-04 refusal gate already there. `[CITED: src/pricing/dlmp.jl]` |
| In-place objective mutation | Manual objective re-assembly | `set_objective_coefficient` / `set_normalized_rhs` | JuMP-native, verified, avoids rebuild. `[VERIFIED: Context7]` |
| Radial root→node path for per-node coupling | A graph library | walk `feeder.branches` parent pointers | Already done in `dlmp.jl _path_branches` if needed. `[CITED: src/pricing/dlmp.jl]` |

**Key insight:** every hard part of this phase (device physics, SOCP exactness, price extraction, solver discipline) is already built and tested. Hand-rolling any of it re-introduces bugs the earlier phases already closed. The *only* genuinely new code is the coupling-closure swap, the dual-ascent loop, and the residual struct.

## Runtime State Inventory

> This is a code-only, greenfield-within-the-repo phase (adds `src/admm/*` + tests). There is **no rename/refactor/migration** and **no runtime state** to migrate.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no database, datastore, collection, or persisted key is introduced or renamed. Verified by inspecting `src/` (all in-memory JuMP models + immutable structs). | None |
| Live service config | None — no external service; solves are in-process Clarabel/HiGHS. | None |
| OS-registered state | None — no scheduler task, daemon, or service registration. | None |
| Secrets/env vars | None — no secrets; solvers are open-source `*_jll` binaries, no license/env key. (Gurobi/Mosek remain opt-in weakdeps, untouched.) | None |
| Build artifacts | None new — no `Project.toml` `[deps]` change, so no re-instantiate/egg-info/binary rebuild. New `src/admm/*.jl` are picked up by the existing `include` graph on next load. | None |

**Nothing found in any category — verified by reading `src/TSODSO.jl`, `factory.jl`, and the absence of any datastore/service in the codebase.**

## Common Pitfalls

### Pitfall 1: `λ_j` as a `Parameter` → indefinite QP → Clarabel rejects it
**What goes wrong:** Modeling the price `λ_j` as `@variable(m, λ in Parameter(...))` and writing `−λ*pag` makes JuMP emit a **quadratic (bilinear) term**; its Hessian block `[[0,−1],[−1,0]]` is indefinite, so Clarabel (a convex conic solver) errors "not convex" or returns garbage. `[VERIFIED: Context7 variables.md "Parameter Multiplication Results in Quadratic Expression"]`
**Why it happens:** JuMP docs are explicit that parameter×variable is treated as quadratic even when mathematically linear; the price term looks linear, so it is tempting to parameterize it.
**How to avoid:** keep `λ_j` a plain `Float64` and update the linear coefficient via `set_objective_coefficient`. Only the penalty target `c_j`/`a_j` may be a `Parameter` (it is wrapped in a convex square `(pag±c)²`, whose Hessian is PSD).
**Warning signs:** Clarabel `TerminationStatus` non-optimal on a model that *should* be a convex QP; objective type unexpectedly `QuadExpr` with cross terms.

### Pitfall 2: Wrong ρ → oscillation or slow crawl; primal-only stopping → false convergence
**What goes wrong:** The thesis `ρ=1000` is tuned to its per-unit scale (¢/kWh, MW); on the 100 MVA-base fixtures with O(0.01–1) pu magnitudes it will likely oscillate (ρ too large) or crawl. Stopping on the primal residual alone can halt at a non-consensus point with wrong DADPs. `[CITED: PITFALLS.md Pitfall 2]`
**Why it happens:** copying `ρ=1000` without rescaling; the thesis's own stated criterion is primal-only.
**How to avoid (Phase-6 scope):** pick a **fixed** ρ empirically on the 2-bus fixture (start O(1)–O(10) given pu scaling; target ~tens of iterations like the thesis's ~28). Stop on the primal residual **and** a maxiter cap that **fails loud**. Track the dual residual `ρ·Δ(coupling)` in diagnostics even though the hard dual-residual stop and adaptive-ρ are Phase 7 — because the **centralized cross-validation is the true false-convergence net** for Phase 6. `[CITED: THEORY-thesis.md §2.6; PITFALLS.md Pitfall 2]`
**Warning signs:** iteration count ≫ ~28; residual plot plateaus above ε or oscillates; ADMM welfare/duals disagree with centralized.

### Pitfall 3: DSO-OPT converges to an inexact SOC point → meaningless prices
**What goes wrong:** ADMM can "converge" (residual small) while the DSO network subproblem's SOC relaxation is strict (`l·v > P²+Q²`), making the recovered `λ_j` physically meaningless. `[CITED: PITFALLS.md Pitfall 2.4, Pitfall 1]`
**Why it happens:** the exactness enabler in the centralized solve is the **priced free-sign frontier export** (makes welfare strictly decreasing in loss current `l`). DSO-OPT must retain it.
**How to avoid:** build DSO-OPT with the `allow_export`-style free-sign `p_import` + `−λ₀ᵀp_import` cost (mirroring `solve_welfare(allow_export=true)`), and run `assert_socp_exact!(dso_ctx)` on the **converged** DSO solve; refuse the ADMM prices if it throws. Do **not** run the gate mid-loop (early iterates are legitimately inexact and would throw). `[CITED: src/models/welfare_solve.jl step 4; src/models/exactness.jl]`
**Warning signs:** `assert_socp_exact!` reports a large `maxgap`; voltages pinned at the upper bound with PV back-feed; DLMP components don't sum.

### Pitfall 4: Assuming Clarabel warm-starts / supports `direct_model`
**What goes wrong:** Clarabel is `copy_to`-only (`supports_incremental_interface == false`): `direct_model(Clarabel.Optimizer())` **errors**, and `set_start_value` is ignored. Expecting warm-start speedups from Clarabel is a false premise. `[VERIFIED: src/solver/factory.jl Phase-1 comment]`
**Why it happens:** the original CLAUDE.md perf note suggested `direct_model` for hot loops; Phase 1 corrected this specifically for Clarabel.
**How to avoid:** use a standard `Model(select_optimizer(...))` (auto-wrapped in a CachingOptimizer). The ADMM-03 win is **not rebuilding the JuMP model** (eliminating macro expansion + MOI cache population + GC churn); the per-iteration `copy_to` to Clarabel still happens and is acceptable at Phase-6 scale. If AGR-OPT re-copy ever dominates, route AGR-OPT to HiGHS (QP, warm-startable) — but keep DSO-OPT on Clarabel for dual accuracy. Be honest in docs: coefficient-update ≠ zero re-copy on Clarabel; it means zero JuMP-side rebuild.
**Warning signs:** an error from `direct_model` with a Clarabel factory; expecting iteration count to drop from warm starts and seeing no change.

### Pitfall 5: Sign/identity error in the recovered DADP
**What goes wrong:** `λ_j` recovered with the wrong sign (flips the price signal) or matched against the wrong centralized constraint. `[CITED: PITFALLS.md Pitfall 7]`
**Why it happens:** JuMP's equality-dual sign depends on `Max`/`Min` and constraint sense; the thesis 3.47 printed sign is ambiguous in the digest.
**How to avoid:** derive both blocks from one Lagrangian (Pattern 1); pin the sign on a 2-bus fixture with an analytically known price; assert `res.λ ≈ extract_dlmp(ctx_c)` at the load buses (same-sign, same-constraint). `[CITED: src/pricing/dlmp.jl]`
**Warning signs:** prices negative where positive expected; ADMM dual = −(centralized dual).

### Pitfall 6: Accidentally re-implementing physics instead of reusing `contribute!`
**What goes wrong:** writing new device or branch-flow constraints in ADMM, diverging from the validated centralized model, so ADMM optimizes a *different* problem and can never match. `[CITED: PITFALLS.md Pitfall 2 "wrong split"]`
**How to avoid:** call the exact `contribute!` methods; the only new constraints are the two coupling-variable equalities and the priced frontier. Add a build-once assertion in the test (Pattern 3): after one iteration, re-solving with only a coefficient change must not have added variables/constraints (compare `num_variables`/`num_constraints` before/after a loop step).
**Warning signs:** ADMM welfare systematically offset from centralized regardless of ρ/ε; variable/constraint counts growing across iterations.

## Code Examples

Verified re-solve mechanics (JuMP 1.30.1). `[VERIFIED: Context7 /jump-dev/jump.jl]`

### Build-once coefficient update (the ADMM-03 core)
```julia
# Source: Context7 jump.jl docs/src/manual/objective.md
model = Model()
@variable(model, pag)
@objective(model, Max, -0.5 * ρ * pag^2)          # FIXED quadratic penalty part, built ONCE
# ... each ADMM iteration, update ONLY the linear coefficient (price + shifted target):
set_objective_coefficient(model, pag, -λ - ρ * c)  # one call per (node, hour)
optimize!(model)
```

### Parameter for the (convex) penalty target only — NEVER for the price
```julia
# Source: Context7 jump.jl docs/src/manual/nonlinear.md (Parameter set) + variables.md caveat
@variable(model, c in Parameter(0.0))              # SAFE: c only appears inside a convex square
@variable(model, pag)
@objective(model, Max, -0.5 * ρ * (pag + c)^2)     # PSD Hessian in (pag, c) — convex
set_parameter_value(c, new_netflow_value)          # update between solves
# DO NOT: @variable(model, λ in Parameter(...)); @objective(model, Max, -λ*pag)  # indefinite → Clarabel rejects
```

### Solver + status discipline (reused verbatim)
```julia
# Source: src/solver/factory.jl, src/core/status.jl
agr_model = Model(select_optimizer(QP()))     # Clarabel; never names a solver (INFRA-02)
dso_model = Model(select_optimizer(SOCP()))   # Clarabel, tight duality gap
assert_solved!(agr_model; dual = true)        # INFRA-03 gate before any dual/value read
assert_socp_exact!(dso_ctx)                   # PF-04 gate on the CONVERGED DSO subproblem
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `direct_model(Clarabel.Optimizer())` for hot loops (original CLAUDE.md note) | Standard `Model(...)`; `direct_model` reserved for HiGHS | Phase 1 (2026-07-18) | Clarabel is `copy_to`-only; `direct_model` errors. `[VERIFIED: src/solver/factory.jl]` |
| Manual objective re-assembly per iteration | `set_objective_coefficient` / `set_normalized_rhs` in place | JuMP ≥ 1.x (stable in 1.30.1) | Build-once/re-solve without rebuild. `[VERIFIED: Context7]` |
| Fixed constants via re-`@objective` | `@variable(... in Parameter(v))` + `set_parameter_value` | JuMP ≥ 1.18 (Parameter set) | Efficient constant updates; but watch param×var quadratic. `[VERIFIED: Context7]` |

**Deprecated/outdated:**
- ECOS as the conic solver (superseded by Clarabel) — irrelevant here, already on Clarabel.
- Primal-only ADMM stopping (thesis §2.6) — kept for Phase-6 scope but backstopped by the centralized cross-check; upgraded to primal+dual+adaptive-ρ in Phase 7.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact printed sign of the linear price term in thesis eq. 3.47 (DSO-OPT) is a transcription ambiguity in the digest; both blocks are derived self-consistently from one augmented Lagrangian and the sign is pinned by the 2-bus regression. | Architecture Pattern 1/2 | If the thesis uses a different multiplier convention, the *recovered* λ sign flips — caught by the 2-bus test, so low residual risk, but plan should read the thesis PDF eqs 3.46–3.47 to confirm. |
| A2 | A fixed ρ in the O(1)–O(10) range (not the thesis's 1000) converges on the 2-bus / IEEE-13 pu-scaled fixtures in ~tens of iterations. | Pitfall 2, Open Questions | If ρ needs heavy retuning, iteration counts balloon; mitigated because Phase 6 only needs *a* working ρ per fixture and adaptive-ρ is Phase 7. Empirically tune during implementation. |
| A3 | Reusing `Aggregator.contribute!` inside AGR-OPT (option a) and ignoring its stray `:Rp`/`:Rq` writes (never closed there) is harmless. | Architecture Pattern 4 | If some later assertion in the aggregator path assumes the residual is closed, option (a) breaks — fall back to a factored `agr_rollup!` helper (option b). Low risk. |
| A4 | Per-node AGR-OPT + whole-network DSO-OPT (one model over all T, not per-hour) is acceptable for Phase-6 correctness; per-hour DSO decomposition is a Phase-7 perf choice. | Architecture Pattern 4 | None for correctness (network has no inter-hour coupling); only affects parallelism/scale, which is Phase 7. |
| A5 | The DSO-OPT free-sign priced frontier (`allow_export` analog) keeps the SOC relaxation exact at ADMM convergence, as it does centrally. | Pitfall 3 | If the ρ-penalty distorts the loss-penalization enough to open the cone, `assert_socp_exact!` throws and refuses prices (fail-safe, not silent-wrong). Verify the gate passes on the IEEE-13 ground fixture. |

**If any assumption proves false, the failure mode is a *thrown gate* or a *failing cross-validation test*, not a silently-wrong published price** — the phase's invariants are fail-loud by construction.

## Open Questions

1. **Exact ρ (and ε) per fixture.**
   - What we know: ρ is both penalty and dual step; thesis used ρ=1000, ε=5e-5, ~28 iters at its scale.
   - What's unclear: the value that converges on the 100 MVA-base, ¢/kWh-priced 2-bus and IEEE-13 fixtures.
   - Recommendation: empirically sweep ρ on the 2-bus fixture during implementation; pin a per-fixture constant in `Phase6Fixtures`; leave a `ρ` keyword on `solve_admm`. Adaptive-ρ is Phase 7.
2. **AGR-OPT solver choice under re-solve pressure.**
   - What we know: Clarabel gives best duals but is `copy_to`-only (re-copies each solve); HiGHS QP warm-starts.
   - What's unclear: whether AGR-OPT re-copy overhead matters at Phase-6 scale (2-bus, IEEE-13 × 24h × ~tens of iters).
   - Recommendation: default Clarabel for uniformity; profile only if slow; the AGR-OPT dual is not the priced quantity so HiGHS is a safe fallback.
3. **Thesis 3.47 printed sign.**
   - What we know: the digest's outer-minus rendering makes the penalty appear as `−(ρ/2)‖R‖²` inside a `min` (unbounded), i.e. a transcription artifact.
   - What's unclear: the exact multiplier convention in the PDF.
   - Recommendation: read `docs/references/…Palacios….pdf` eqs 3.46–3.47 during planning to confirm; regardless, the one-Lagrangian derivation + 2-bus sign assertion is authoritative for the port.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ (pinned ≥1.10 LTS / 1.11) | per `Project.toml` compat | — |
| JuMP | modeling + re-solve API | ✓ | 1.30.1 | — |
| Clarabel | AGR-OPT (QP) + DSO-OPT (SOCP) | ✓ | 0.11.1 | — |
| HiGHS | optional warm-startable AGR-OPT | ✓ | 1.24.1 | Clarabel (default) |
| MathOptInterface | bridges / Parameter set | ✓ | 1.51.2 | — |
| TestItemRunner | cross-validation `@testitem` | ✓ | 1.1.5 | — |

**Missing dependencies with no fallback:** none — all are in the committed `Manifest.toml`.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems 1.0.0 + TestItemRunner 1.1.5 (`@testitem` / `@testmodule`) `[CITED: test/runtests.jl]` |
| Config file | none — `test/runtests.jl` calls `@run_package_tests`; items discovered under `test/` and `src/` |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter = ti -> occursin("admm", ti.name)'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` (runs `test/runtests.jl`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADMM-01 | ADMM split solves via AGR-OPT[j] + DSO-OPT with dual ascent, reusing builders | integration | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("admm", ti.name)'` | ❌ Wave 0 (`test/test_admm.jl`) |
| ADMM-03 | Subproblems built once; re-solve mutates coefficients, no rebuild (assert `num_variables`/`num_constraints` stable across a loop step) | unit | same filter (`occursin("admm: build-once", ti.name)`) | ❌ Wave 0 |
| ADMM-04 | ADMM welfare ≈ `objective_value(centralized)` AND ADMM `λ_j` ≈ `extract_dlmp(centralized)` on 2-bus + IEEE-13 ground; `assert_socp_exact!` passes | integration | same filter (`occursin("admm: cross-validation", ti.name)`) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the filtered ADMM item command above (fast — 2-bus fixture is tiny).
- **Per wave merge:** `Pkg.test()` full suite (ADMM must not regress Phases 1–5).
- **Phase gate:** full suite green before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/fixtures_phase6.jl` — `@testmodule Phase6Fixtures`: `two_bus_feeder()` (root + one load bus, analytic price) + `build_two_bus_aggregators()` (a single small aggregator; seeded), reusing `generate_profiles`. Reuse `Phase4Fixtures.build_ieee13_ground_aggregators` + `ieee13_modified` for the IEEE-13 case.
- [ ] `test/test_admm.jl` — the three `@testitem`s above (split-solves, build-once, cross-validation), `setup=[Phase6Fixtures]` (+ `Phase4Fixtures` for IEEE-13), name-substring `"admm"`.
- [ ] Framework install: none — TestItemRunner already present.

*(The 2-bus fixture is new; everything else — IEEE-13, profiles, exactness gate, `extract_dlmp` — is reused.)*

## Security Domain

> `security_enforcement` is not set in `.planning/config.json` (treated as enabled by default). This is a **Julia offline mathematical-optimization research library** — no network surface, no authentication, no session, no untrusted input, no persistence, no user data. The standard web/app ASVS threat model does not apply; "security" here maps to **research integrity and reproducibility** (per `PITFALLS.md §Security Mistakes`).

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface (offline library). |
| V3 Session Management | no | No sessions. |
| V4 Access Control | no | No multi-user/access boundary. |
| V5 Input Validation | partial (integrity, not security) | Constructor/argument guards already throw on bad shapes/units (e.g. `solve_welfare` λ₀ length, aggregator bus range); ADMM inherits these. Reuse the same fail-loud `throw` convention. `[CITED: src/models/welfare_solve.jl]` |
| V6 Cryptography | no | No secrets/crypto. Solvers are open-source `*_jll`; no keys. |

### Known Threat Patterns for {Julia optimization research bench}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silently-wrong prices (inexact SOC / wrong dual sign / false convergence) | Tampering (of results) | `assert_socp_exact!` gate + centralized dual cross-validation + 2-bus sign assertion (Patterns 3/5, Pitfalls 3/5). |
| Non-reproducible ADMM run (unpinned env / unseeded fixture) | Repudiation (of a figure) | Committed `Manifest.toml` (no new deps this phase); seeded `Phase6Fixtures` via `generate_profiles`. `[CITED: test/fixtures_phase4.jl]` |
| Hidden solver slack read as a solution | Tampering | `assert_solved!` (INFRA-03) before any `value()`/`dual()`; optional `assert_no_slack` on coupling equalities. `[CITED: src/core/status.jl]` |

## Sources

### Primary (HIGH confidence)
- Context7 `/jump-dev/jump.jl` (JuMP 1.30.1 manual: `objective.md`, `variables.md`, `nonlinear.md`, `constraints.md`) — `set_objective_coefficient`, `set_normalized_rhs`, `Parameter`/`set_parameter_value`/`parameter_value`, `set_start_value`, and the "parameter×variable ⇒ quadratic" caveat. Verified this session.
- `.planning/research/THEORY-thesis.md` §2.5–2.6 (eqs 3.31/3.38/3.46/3.47, dual update, ρ/ε) — the ADMM split and price-as-dual identity.
- Source files read this session (the reuse seams): `src/models/welfare_solve.jl`, `src/core/ModelContext.jl`, `src/devices/{AbstractDevice,Aggregator,Interruptible,PVBattery}.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/solver/{factory,ProblemClass}.jl`, `src/core/status.jl`, `src/models/{exactness,oracle,linear_solve}.jl`, `src/pricing/dlmp.jl`, `src/TSODSO.jl`, `test/{runtests,fixtures_phase4,test_welfare_solve}.jl`.
- `Manifest.toml` — pinned versions (JuMP 1.30.1, MOI 1.51.2, Clarabel 0.11.1, HiGHS 1.24.1).

### Secondary (MEDIUM confidence)
- `.planning/research/PITFALLS.md` (Pitfalls 1–8; ADMM convergence, dual sign, rebuild, solver mismatch) — cross-referenced with the thesis and solver behavior.
- `./CLAUDE.md` Technology Stack (ADMM guidance, hand-rolled loop, no Coluna/StructJuMP, Clarabel/HiGHS routing).

### Tertiary (LOW confidence)
- The exact printed sign of thesis eq. 3.47 (digest transcription) — flagged in Assumptions A1/A3; to be confirmed against the PDF during planning.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; versions read from the committed `Manifest.toml`.
- Architecture (the split + reuse map): HIGH — derived from one augmented Lagrangian and read directly from the source seams; the "orchestration not re-implementation" design is concrete and grounded.
- Re-solve API (ADMM-03): HIGH — every mutator verified live against JuMP 1.30.1 docs, including the `Parameter`-price trap.
- Pitfalls: HIGH on the code-grounded ones (Clarabel copy_to, exactness gate, solver discipline); MEDIUM on ρ tuning (needs empirical work) and the thesis 3.47 sign (transcription).

**Research date:** 2026-07-19
**Valid until:** ~2026-08-18 for the JuMP API surface (stable, pinned env); ρ/ε values are fixture-empirical and settled during implementation, not time-sensitive.

## Project Constraints (from CLAUDE.md)

- **JuMP, not Convex.jl** — need per-constraint duals (`λ_j`), manual constraint control, `Parameter`s, warm starts. ADMM honors this (all subproblems are JuMP). ✓
- **No solver named in a model** (INFRA-02) — use `select_optimizer(QP()/SOCP())`. ADMM subproblem builders must not name Clarabel/HiGHS. ✓
- **Every solve gated on OPTIMAL** (INFRA-03) — `assert_solved!` on each AGR/DSO solve before reading any value/dual. ✓
- **SOCP exactness validated** (PF-04) — `assert_socp_exact!` on the converged DSO-OPT; prices refused if inexact. ✓
- **Build once, re-solve many; never rebuild inside the loop** — coefficient/RHS/parameter mutation only. ✓ (ADMM-03)
- **Hand-rolled ADMM; no Coluna/StructJuMP** — a plain dual-ascent loop with full control of updates. ✓
- **`direct_model` NOT with Clarabel** (Phase-1 correction) — standard `Model(...)`; reserve `direct_model` for HiGHS. ✓
- **Reproducible + seeded** — seeded `Phase6Fixtures`; committed `Manifest.toml` (no dep change). ✓
- **Every step cites a thesis equation** — 3.31/3.38/3.46/3.47/3.22/3.23 traced throughout; rich per-decision docs are a hard requirement. ✓
- **Correctness/clarity/traceability over performance** — the phase's value is the centralized cross-validation, not speed. ✓
