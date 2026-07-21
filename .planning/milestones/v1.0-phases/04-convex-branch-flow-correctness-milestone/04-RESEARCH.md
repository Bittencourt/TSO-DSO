# Phase 4: Convex Branch-Flow Correctness Milestone - Research

**Researched:** 2026-07-18
**Domain:** Convex SOCP branch-flow (DistFlow) optimization in Julia/JuMP + relaxation-exactness certification
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
The formulation, the exactness copy, and the ground-truth numbers all come from the source thesis
(Palacios 2022). There are **no user-preference grey areas** in this phase. Anchor everything to:

- **SOCP branch flow (PF-03):** a new concrete `AbstractPowerFlow` subtype implementing the DistFlow
  SOC relaxation — branch active/reactive flows `P_ij/Q_ij`, squared-current `l_ij`, squared-voltage
  `v_i`, the SOC cone `l_ij·v_i ≥ P_ij² + Q_ij²` (rotated-SOC in JuMP), the voltage-drop and
  active/reactive balance recursions — traced to thesis eqs. 3.31–3.45. It plugs into the Phase-1/2
  residual seam via `contribute!` (dispatch, no branching), interchangeable with DC and LinDistFlow.
- **LinDistFlow exactness copy (PF-03):** the aux `v̂` + affine voltage bounds trick (eqs. 3.40–3.45)
  that makes the SOC relaxation **exact** on radial feeders. Written explicitly as part of the model
  definition.
- **Exactness invariant (PF-04):** an automated post-solve assertion `max|l·v − (P²+Q²)| < τ` per
  branch, run on BOTH an easy fixture AND a high-PV/over-voltage fixture. **Prices (DADPs) are
  REFUSED (error) if exactness fails.** Headline correctness gate of the whole project.
- **Ground truth (OPT-02/OPT-03):** the centralized monolithic solve must reproduce the thesis
  DADP/voltage numbers (e.g. `v₉[16] ≈ 1.0493`) on the modified IEEE 13-node feeder, with the nodal
  active-balance dual available.
- **Solver:** SOCP + convex QP objective → `select_optimizer(SOCP())` → **Clarabel** (native SOC +
  quadratic, accurate duals). No model names a concrete solver.
- **operational_oracle + SEAM-01:** `operational_oracle(z) → (cost, π)` returns the frontier coupling
  dual; extension interfaces exist as STUBS (multi-scenario objective hook, rolling-horizon parameter,
  meshed-formulation slot, coupling-flow interface `z↔p_ag`, `λ_j↔π_s`, leader/follower role param).
- **Data (DATA-03):** the modified IEEE 13-node feeder as immutable JuMP-free structs (Phase-1
  `Feeder`), radial-validated, per-unit-converted-once.

### Claude's Discretion
- The exactness tolerance `τ` value (recommend `1e-5` per-unit; see Pitfall 1).
- Whether to route the SOCP class via a `problem_class(::AbstractPowerFlow)` trait or an explicit
  `optimizer` kwarg at the call site (recommend the trait — see Pattern 5).
- The precise minimal shape of the SEAM-01 stubs (kwargs vs. no-op hook functions).
- Whether to add PowerModelsDistribution as a cross-validation oracle (recommend **DEFER** — see
  Open Question 3).

### Deferred Ideas (OUT OF SCOPE)
- ADMM decomposition of the operational solve → Phase 6.
- The actual planning / Stackelberg-Nash equilibrium layer → later milestone (only the additive
  SEAM-01 stubs land here).
- Unbalanced 3-phase → out of scope for v1 entirely.
- Meshed (non-radial) power flow → v2 (MESH-01); only a documented seam slot here.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PF-03 | SOCP Convex Branch Flow formulation (DistFlow SOC relaxation) with the LinDistFlow exactness copy (aux `v̂` + affine voltage bounds) | Full formulation extracted (thesis eqs. 3.29–3.45); rotated-SOC JuMP syntax verified (Pattern 1–2); drop-in `AbstractPowerFlow` subtype design (Pattern 3) |
| PF-04 | Automated post-solve exactness invariant `max\|l·v − (P²+Q²)\| < τ` on easy + high-PV fixtures; prices refused on failure | Gap formula, τ guidance, refusal-hook placement (Pattern 4; Pitfall 1) |
| OPT-02 | Centralized monolithic solve = global optimum, nodal-balance dual available | GLB-CVX (3.44) maps onto existing `solve_welfare`; SOCP routing (Pattern 5); DADP already read as `dual.(balance_p)` |
| OPT-03 | Centralized solve exposed as `operational_oracle(z) → (cost, π)` returning frontier coupling dual | Oracle + SEAM-01 stub design (Pattern 6), z↔p_ag / λ_j↔π_s mapping from PSR planning note |
| DATA-03 | Modified IEEE 13-node feeder ships as a built-in fixture with thesis parameters | Complete Table 4.1 topology + limits + Fig 4.1 extracted (Data section) |
| SEAM-01 | Extension interface stubs: multi-scenario objective hook, rolling-horizon parameter, meshed slot, coupling-flow interface with leader/follower role | Verified JuMP `Parameter` API; minimal-stub design (Pattern 6) |
</phase_requirements>

## Summary

This phase adds the project's correctness keystone: a **third `AbstractPowerFlow` subtype** implementing
the Baran–Wu/DistFlow **Branch Flow Model relaxed to a Second-Order Cone Program**, together with the
**LinDistFlow "exactness copy"** (an auxiliary squared-voltage variable `v̂` plus affine voltage bounds)
that guarantees the SOC relaxation is *exact* on radial feeders — without which the recovered
distribution prices (DADPs) are physically meaningless. The formulation is fully specified in the
thesis (eqs. 3.29–3.45, extracted verbatim below) and drops cleanly into the existing residual seam:
it writes affine `:Rp`/`:Rq` contributions (now *with* the `r·l`/`x·l` loss terms) via
`add_to_residual!` and adds its cone / voltage-drop / apparent-power constraints directly to the model,
exactly as `LinDistFlow` already does, so DC ↔ LinDistFlow ↔ SOCP remain interchangeable by dispatch.

The three flagged Phase-4 blockers are **RESOLVED and verified live** against current docs
(2026-07-18): (a) JuMP's `RotatedSecondOrderCone` enforces `‖x‖² ≤ 2·t·u`, so `l·v ≥ P²+Q²` is written
`[0.5*l, v, P, Q] in RotatedSecondOrderCone()` [CITED: jump.dev manual/constraints]; (b) Clarabel is
literally "an interior-point solver for conic programs **with quadratic objectives**" — it handles the
SOCP cone *and* the concave-quadratic welfare objective natively, no manual epigraph
[CITED: oxfordcontrol/clarabeldocs citing.md]; (c) the JuMP `Parameter` API is
`@variable(m, p in Parameter(v))` + `parameter_value` / `set_parameter_value` [CITED: jump.dev
manual/variables]. The earlier CLAUDE.md flag that Clarabel is `copy_to`-only (so `direct_model` must
NOT be used with it) is already correctly captured in `src/solver/factory.jl` — no change needed.
`SOCP()` and `QP()` problem classes already exist and route to Clarabel.

**No new packages are required** — every dependency (JuMP 1.30.1, Clarabel 0.11.1, Ipopt 1.15.0) is
already pinned in `Project.toml`. The only regression risk is *data reproduction*: the headline
`v₉[16] ≈ 1.0493` and social-welfare `$1819` targets require the full thesis input data (MEM price
profile Fig 4.5, exterior-temperature profile Fig 4.2, per-house device parametrization, Markov PV),
only *partially* tabulated in the thesis — see Open Question 1.

**Primary recommendation:** Implement `ConvexBranchFlow <: AbstractPowerFlow` writing balances 3.31/3.32
(with loss terms), voltage drop 3.33, copy drop 3.43, SOC cone 3.39 (rotated form), and bounds 3.45 on
both `v` and `v̂`; add a `problem_class` trait routing it to `select_optimizer(SOCP())`; add an
`assert_socp_exact!(ctx; τ)` checker called inside `solve_welfare` *after* `assert_solved!` and *before*
reading any dual, gated on the presence of `l` in `ctx.meta[:pf_vars]`; ship the modified IEEE-13 feeder
as an immutable fixture from Table 4.1; and wrap it all in a thin `operational_oracle` with documented
SEAM-01 stubs.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SOCP branch-flow constraints (cone, drops, balances) | Power-flow formulation (`src/powerflow/`) | ModelContext residual seam | A formulation is the only thing that knows branch physics; it writes affine residuals + its own model constraints (mirrors `LinDistFlow`) |
| Exactness copy (`v̂`, 3.43, 3.45) | Power-flow formulation | — | Part of the *definition* of the SOCP model per thesis; lives with the cone, not in assembly |
| Welfare assembly / balance closure / DADP dual | Model assembly (`src/models/welfare_solve.jl`) | ModelContext constraint registry | Already the sole balance-closer and dual reader; SOCP is a drop-in `pf` |
| Exactness invariant (PF-04) | Model checker (`src/models/exactness.jl`, new) | assembly hook | A post-solve numerical assertion over `pf_vars`; must sit *between* solve and dual read |
| Solver selection (SOCP → Clarabel) | Solver factory (`src/solver/`) | `problem_class` trait | INFRA-02: only the factory names a solver; a trait maps `pf → ProblemClass` |
| Feeder fixture (IEEE-13) | Data layer (`src/data/` or `test/fixtures`) | PerUnit ingestion | Immutable, JuMP-free, radial-validated at construction |
| `operational_oracle` + SEAM-01 stubs | Model assembly / seam layer | — | A thin wrapper over `solve_welfare` exposing (cost, π); stubs are signatures only |

## Standard Stack

**No new packages.** Phase 4 is built entirely on the already-pinned, verified stack.

### Core
| Library | Version (pinned) | Purpose | Why Standard |
|---------|------------------|---------|--------------|
| JuMP | 1.30.1 | Algebraic modeling; `@constraint(..., in RotatedSecondOrderCone())`, per-constraint `dual()`, `Parameter` set | The Julia math-programming standard; exposes exactly the per-constraint dual (DADP) and cone syntax this phase needs [VERIFIED: Context7 /jump-dev/jump.jl] |
| Clarabel | 0.11.1 | Primary conic solver: SOCP + convex quadratic objective, high-accuracy duals | Native IPM conic solver "for conic programs **with quadratic objectives**" — prices ARE duals, IPM accuracy >> first-order [VERIFIED: Context7 /oxfordcontrol/clarabeldocs] |
| Ipopt | 1.15.0 | Cross-check NLP solver on the convex SOCP | Independent second solver for cross-solver objective/exactness agreement (Pitfall 4); already wired via `NLP()` class + `allow_local=true` |
| SparseArrays | stdlib | Incidence/topology structures | Feeder topology already sparse in Phase 1 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TestItemRunner / TestItems | 1.1.5 / 1.0.0 | `@testitem` test harness | Every Phase-4 test is a `@testitem` (name contains the filter substring), discovered by `@run_package_tests` |
| StableRNGs | 1.0.4 | Seeded PV/demand profile synthesis (`generate_profiles`) | Feeding the high-PV exactness-stress fixture reproducibly |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Clarabel (SOCP) | Mosek (`MosekTools`) | Gold-standard SOCP+duals but licensed; only behind the factory. Not needed. |
| Clarabel (SOCP) | SCS | First-order; loose duals — MUST NOT certify exactness or report final DADP with it (Pitfall 4). Scale-scouting only. |
| Ipopt cross-check | PowerModelsDistribution OPF oracle | Heavyweight new dep; DEFER (Open Question 3). Ipopt already gives an independent convex cross-check. |
| `RotatedSecondOrderCone` for `l·v ≥ P²+Q²` | Manual `SecondOrderCone` reformulation | Rotated form is the natural, minimal encoding; MOI bridges it to Clarabel's native SOC. |

**Installation:** none — all deps present in `Project.toml`. Verify the environment resolves:
```bash
julia --project=. -e 'using Pkg; Pkg.status(); Pkg.instantiate()'
```

**Version verification:** JuMP 1.30.1 and Clarabel 0.11.1 are pinned in `Project.toml [compat]`; local
Julia is 1.12.5 (compat floor 1.10 LTS). API surface re-verified live via Context7 on 2026-07-18 (see
Code Examples + Sources).

## Package Legitimacy Audit

> Phase 4 installs **no external packages**. All dependencies are already declared and pinned in
> `Project.toml`; the audit is therefore informational.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| JuMP 1.30.1 | Julia General | 10+ yrs | ecosystem-standard | github.com/jump-dev/JuMP.jl | n/a (Julia) | Already pinned — approved |
| Clarabel 0.11.1 | Julia General | ~3 yrs | wide | github.com/oxfordcontrol/Clarabel.jl | n/a (Julia) | Already pinned — approved |
| Ipopt 1.15.0 | Julia General | 10+ yrs | wide | github.com/jump-dev/Ipopt.jl | n/a (Julia) | Already pinned — approved |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Note: `slopcheck` targets npm/PyPI, not the Julia General registry, so it cannot verify Julia packages;
the packages above are established, high-reputation JuMP-ecosystem libraries confirmed via Context7 and
already committed to the pinned `Manifest.toml`. If PowerModelsDistribution is later adopted (Open
Question 3), pin it at 0.16.0 from the Julia General registry behind a human-verify checkpoint.*

## Architecture Patterns

### System Architecture Diagram

```
                        operational_oracle(z; role, λ₀)              ← SEAM-01 wrapper (OPT-03)
                                     │
                                     ▼
   Feeder (IEEE-13,        ┌──────────────────────────┐
   immutable, radial) ───▶ │      solve_welfare        │  GLB-CVX (thesis 3.44)
   Aggregators + devices ─▶│  (existing assembly)      │
   λ₀ price profile ──────▶│                           │
                           └───────────┬───────────────┘
                                       │ contribute!(pf, ctx, feeder)   ← DISPATCH, no branching
                                       ▼
                  ┌───────────────────────────────────────────┐
                  │  ConvexBranchFlow <: AbstractPowerFlow       │  ← NEW (PF-03)
                  │  vars: P,Q (flows), l (sq-current),          │
                  │        v (sq-voltage), v̂ (exactness copy)    │
                  │  → :Rp += P − r·l − ΣP_jm     (3.31, affine) │
                  │  → :Rq += Q − x·l − ΣQ_jm     (3.32, affine) │
                  │  → vdrop:  v_j = v_i −2(rP+xQ)+(r²+x²)l (3.33)│
                  │  → cpydrop:v̂_j = v̂_i −2{r(P+rl)+x(Q+xl)} 3.43│
                  │  → cone:  [0.5l, v_i, P, Q] ∈ RotSOC   (3.39) │
                  │  → bounds:V²min ≤ v,v̂ ≤ V²max          (3.45) │
                  │  → Smax:  P²+Q² ≤ S²max                (3.36) │
                  │  stashes pf_vars=(;v,v̂,P,Q,l)                 │
                  └───────────────────┬───────────────────────────┘
                                      ▼
         aggregators contribute! ─▶ :Rp/:Rq (net injections)  +  objective (Σ U_ag)
                                      ▼
         close balance_p / balance_q == 0   ← register for dual (DADP)
                                      ▼
                              assert_solved!(dual=true)          ← INFRA-03 gate
                                      ▼
                  assert_socp_exact!(ctx; τ)   ← PF-04 GATE: max|l·v−(P²+Q²)|<τ
                                      │  (only when pf_vars has :l)
                        ┌─────────────┴─────────────┐
                   FAIL │                           │ PASS
                        ▼                           ▼
              THROW (refuse prices)    dadp = dual.(balance_p);  return (cost, π)
```

### Recommended Project Structure
```
src/
├── powerflow/
│   ├── AbstractPowerFlow.jl     # existing contract
│   ├── DCPowerFlow.jl           # existing
│   ├── LinDistFlow.jl           # existing
│   └── ConvexBranchFlow.jl      # NEW — SOCP + exactness copy (PF-03)
├── models/
│   ├── welfare_solve.jl         # extend: problem_class routing + exactness hook
│   ├── exactness.jl             # NEW — assert_socp_exact! (PF-04)
│   └── oracle.jl                # NEW — operational_oracle + SEAM-01 stubs (OPT-03/SEAM-01)
├── solver/
│   └── ProblemClass.jl          # SOCP() already present; add problem_class(pf) trait
└── data/
    └── fixtures/ieee13.jl       # NEW — modified IEEE-13 feeder (DATA-03)  [or test/fixtures]
```

### Pattern 1: The SOC cone as a rotated second-order cone (VERIFIED)
**What:** The DistFlow current definition `l_ij = (P²+Q²)/v_i` (thesis 3.34) is nonconvex; relaxed to
`l_ij ≥ (P²+Q²)/v_i` ⟺ `l_ij·v_i ≥ P²+Q²` (thesis 3.39), which is exactly a rotated second-order cone.
**When to use:** Every branch, every time step.
**Convention (VERIFIED):** JuMP `[t; u; x] in RotatedSecondOrderCone()` enforces `‖x‖₂² ≤ 2·t·u` with
`t, u ≥ 0`. To get `l·v ≥ P²+Q²` set `t = 0.5·l`, `u = v`, `x = [P, Q]`.
```julia
# Source: jump.dev docs/src/manual/constraints.md (Context7 /jump-dev/jump.jl, 2026-07-18)
# l_ij[b,t]·v_i[t] ≥ P_ij[b,t]² + Q_ij[b,t]²   (thesis eq. 3.39)
@constraint(m, cone[b = 1:nB, t = 1:T],
    [0.5 * l[b, t], v[B[b].from, t], P[b, t], Q[b, t]] in RotatedSecondOrderCone())
```
`v_i > 0` (bounded below by `V²min`) and `l ≥ 0` (add `@variable(m, l[...] >= 0)`) keep the rotated
cone's `t,u ≥ 0` requirement satisfied.

### Pattern 2: The LinDistFlow exactness copy — one aux `v̂` per bus, not a full second network
**What:** Thesis eqs. 3.40–3.42 introduce copy variables `P̂, Q̂, v̂`, but the substitution
`P̂_ij ≈ P_ij + r_ij·l_ij`, `Q̂_ij ≈ Q_ij + x_ij·l_ij` **collapses them into the single equation 3.43**,
which is written purely in terms of the *original* `P, Q, l` plus one new squared-voltage copy `v̂`.
**Key implementation insight:** you do **not** create separate `P̂, Q̂` flow variables — only `v̂[j,t]`
(one per bus per time) and constraint 3.43. Then bound *both* `v` and `v̂` by 3.45. After imposing 3.45,
the thesis notes the upper bound `v_i ≤ V²max` in 3.35 becomes redundant (keeping it is harmless).
```julia
# Source: thesis eqs. 3.42/3.43/3.45 (docs/references/86. Tesis...pdf pp. 84-85) [CITED: thesis]
@variable(m, v̂[j = 1:N, t = 1:T])
fix.(v̂[feeder.root, :], 1.0; force = true)      # copy root also fixed
# Exactness copy voltage drop (3.43) — expand P̂=P+rl, Q̂=Q+xl:
#   v̂_j = v̂_i − 2{ r(P + r·l) + x(Q + x·l) } = v̂_i − 2(rP+xQ) − 2(r²+x²)l
@constraint(m, cpydrop[b = 1:nB, t = 1:T],
    v̂[B[b].to, t] == v̂[B[b].from, t]
        - 2 * (B[b].r * (P[b,t] + B[b].r*l[b,t]) + B[b].x * (Q[b,t] + B[b].x*l[b,t])))
# Bounds 3.45 on BOTH v and v̂ (this is what forces exactness):
for j in 1:N, t in 1:T
    j == feeder.root && continue
    set_lower_bound(v[j,t],  vb.vmin^2); set_upper_bound(v[j,t],  vb.vmax^2)
    set_lower_bound(v̂[j,t], vb.vmin^2); set_upper_bound(v̂[j,t], vb.vmax^2)
end
```
**Why it works (Gan–Low / Farivar–Low adapted):** `v` (true drop 3.33) carries `+(r²+x²)l`; the copy
`v̂` carries `−2(r²+x²)l`. Upper-bounding `v̂ ≤ V²max` pushes the loss current `l` *down*, driving the
cone 3.39 to hold with equality (exact) at the optimum. **Omit these and the prices are garbage whenever
exactness fails — precisely in the high-PV/over-voltage regimes this research targets (Pitfall 1).**

### Pattern 3: `ConvexBranchFlow` as a drop-in third `AbstractPowerFlow` subtype
**What:** Mirror `LinDistFlow.jl` exactly. The *only* differences from `LinDistFlow`:
1. add `l[b,t] ≥ 0` (squared current) and `v̂[j,t]` (exactness copy);
2. balances 3.31/3.32 now include the **loss terms** `− r·l` / `− x·l` (affine in `l`, so they still
   flow through `add_to_residual!(ctx, :Rp/:Rq, …)`);
3. true voltage drop 3.33 uses the `+(r²+x²)·l` term (`LinDistFlow` drops it);
4. add the copy drop 3.43, the rotated SOC cone 3.39, and apparent-power limits 3.36/3.37;
5. stash `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)` for the PF-04 checker.
**When to use:** As `pf` argument to `solve_welfare` / `operational_oracle`. `DCPowerFlow`,
`LinDistFlow`, `ConvexBranchFlow` remain mutually interchangeable by dispatch — no `if formulation ==`.
```julia
# Balances stay AFFINE (loss terms are linear in the variable l) → residual seam unchanged:
add_to_residual!(ctx, :Rp, j, t, pin - pout - r_in*l_in)   # R_p,j = ΣP_in − ΣP_out − r·l  (3.31)
add_to_residual!(ctx, :Rq, j, t, qin - qout - x_in*l_in)   # R_q,j                          (3.32)
```
Note on the loss term's node assignment: in `R_{p,j} = P_ij − r_ij·l_ij − p_ag − ΣP_jm` (3.31) the
`−r·l` loss is charged at the *child* node `j` of the incoming branch `(i,j)`. Assemble per bus by
iterating branches: the incoming branch to `j` contributes `+P − r·l`; outgoing branches contribute
`−P_jm`.

### Pattern 4: The exactness invariant as a hard, price-gating post-solve check (PF-04)
**What:** After a trusted solve, compute per branch/time
`gap[b,t] = value(l[b,t])·value(v[from_b, t]) − (value(P[b,t])² + value(Q[b,t])²)` and assert
`max|gap| < τ`. **On failure, THROW** — refuse to return any price.
**Where:** a dedicated `assert_socp_exact!(ctx; τ)` in `src/models/exactness.jl`, called inside
`solve_welfare` *after* `assert_solved!` and *before* `dadp = dual.(balance_p…)`, gated on
`haskey(ctx.meta[:pf_vars], :l)` so DC/LinDistFlow paths are untouched (data-driven, no formulation
branch).
```julia
# Source: thesis Julia-port checklist item 5 + Pitfall 1 [CITED: thesis §3, PITFALLS.md]
function assert_socp_exact!(ctx; τ::Real = 1e-5)
    pv = ctx.meta[:pf_vars]; feeder = ctx.meta[:feeder]; T = ctx.meta[:T]
    maxgap = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b,t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b,t])^2 + value(pv.Q[b,t])^2
        maxgap = max(maxgap, abs(lhs - rhs))
    end
    maxgap < τ || error("SOCP relaxation INEXACT: max|l·v−(P²+Q²)|=$maxgap ≥ τ=$τ — " *
                        "prices REFUSED (thesis 3.43-3.45; PF-04)")
    return maxgap    # report as a first-class output alongside prices
end
```
Report `maxgap` as a first-class output of every SOCP solve (log it next to the prices).

### Pattern 5: SOCP solver routing via a `problem_class` trait (INFRA-02 preserved)
**What:** `solve_welfare` currently defaults `optimizer = select_optimizer(QP())`. With the cone present
the problem is an SOCP; route it to `select_optimizer(SOCP())` (tighter gap tolerances `1e-8`, already
configured in the factory). Add a trait so the class is derived from the formulation, keeping the "no
model names a solver" rule.
```julia
problem_class(::AbstractPowerFlow) = QP()          # DC / LinDistFlow ⇒ convex QP
problem_class(::ConvexBranchFlow)  = SOCP()         # cone present ⇒ SOCP
# solve_welfare default becomes:  optimizer = select_optimizer(problem_class(pf))
```
Both `QP()` and `SOCP()` route to Clarabel, so a QP()-defaulted SOCP would still *solve*, but only the
`SOCP()` factory sets the tight `tol_gap_abs/rel = 1e-8` that the DADP accuracy and exactness check
depend on (Pitfall 4). Do **not** wrap a Clarabel factory in `direct_model` (copy_to-only — already
documented in `factory.jl`).

### Pattern 6: `operational_oracle` + SEAM-01 stubs (minimal, additive)
**What:** A thin wrapper over `solve_welfare` returning `(cost, π)` where `cost` = the GLB-CVX optimum
and `π` = the frontier coupling dual. From the PSR planning note, the coupling variable is the
interconnection flow `z` (≈ the aggregator net-import profile `p_ag` / frontier import `p₀`), and `π_s`
is the dual of the coupling constraint `z_x = z_y`. In Phase 4 this is a **stub**: `z` optionally pins
the frontier import; `π` is the dual of that pin (or, when `z` is free, the frontier-node DADP).
```julia
# Source: THEORY-papers.md (PSR note eqs 1j/2e/4f: z↔p_ag, π_s = dual of coupling) [CITED: PSR note]
function operational_oracle(feeder, pf, aggregators; λ₀, T = 24,
        z = nothing,                       # coupling flow setpoint (frontier import target); nothing ⇒ free
        role::Symbol = :follower,           # SEAM-01: :leader | :follower (PSR: distributor = leader)
        objective_hook = identity,          # SEAM-01: multi-scenario objective composition (stub: identity)
        horizon_state = nothing)            # SEAM-01: rolling-horizon initial state (stub, see below)
    ctx, cost, dadp = solve_welfare(feeder, pf, aggregators; T, λ₀,
                                    optimizer = select_optimizer(problem_class(pf)))
    π = _coupling_dual(ctx, z)              # dual of the z-pin, else frontier DADP
    return (; cost, π, dadp, ctx)
end
```
**SEAM-01 stub inventory (interfaces only, no extension implemented):**
| Stub | Minimal shape | Made concrete in |
|------|---------------|------------------|
| Multi-scenario objective hook | `objective_hook::Function = identity` kwarg composing the per-scenario welfare | STOCH-01/02 (v2) |
| Rolling-horizon parameter | a JuMP `@variable(m, s0 in Parameter(…))` for battery `soc0`/forecast, re-settable via `set_parameter_value` | MPC-01/02 (v2) |
| Meshed-formulation slot | the `AbstractPowerFlow` seam itself + a documented note that `assert_radial` is bypassable by a future `MeshedFlow` type | MESH-01 (v2) |
| Coupling-flow interface | `z` kwarg (z↔p_ag) + returned `π` (λ_j↔π_s) + `role::Symbol` | PLAN-01/02 (Phase 8/9) |
**JuMP `Parameter` API (VERIFIED):** `@variable(m, p in Parameter(1.0))`; read `parameter_value(p)`;
update `set_parameter_value(p, v)` then re-`optimize!` (efficient re-solve, no rebuild) [CITED:
jump.dev manual/variables + manual/nonlinear].

### Anti-Patterns to Avoid
- **Shipping the bare SOC relaxation without the 3.43/3.45 exactness copy** — the single worst mistake
  in this domain; prices become meaningless exactly in the high-PV cases the research cares about.
- **Reading the DADP before the exactness gate** — the PF-04 check must sit between `assert_solved!`
  and the `dual()` read; a passing OPTIMAL status does NOT imply an exact relaxation.
- **Using `RotatedSecondOrderCone()` without the `0.5` factor** — `‖x‖² ≤ 2tu`, so a missing `0.5·l`
  silently doubles the allowed current and corrupts every voltage and price.
- **Wrapping Clarabel in `direct_model`** — Clarabel is copy_to-only; errors (already documented).
- **Trusting SCS or an `ALMOST_OPTIMAL` conic point for the DADP/exactness** — loose duals fail the gap.
- **Rebuilding the model to change the frontier setpoint** — use a JuMP `Parameter` (SEAM-01 rolling
  horizon), never rebuild.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SOC cone constraint | Manual quadratic `l*v >= P^2+Q^2` (nonconvex to a QP solver) | JuMP `RotatedSecondOrderCone()` | Native conic form; MOI bridges it to Clarabel's SOC; correct curvature |
| Convex-quadratic welfare + cone in one solve | Manual epigraph/SDP reformulation | Clarabel (native quadratic-objective conic IPM) | It is purpose-built for "conic programs with quadratic objectives" |
| Efficient re-solve for rolling horizon | Rebuild `Model` each step | JuMP `Parameter` + `set_parameter_value` | Documented efficient path; no rebuild |
| Solve-status / dual trust | Hand-check `termination_status == OPTIMAL` | existing `assert_solved!` (`is_solved_and_feasible`) | Also checks primal/dual status; project's single choke point |
| Balance/dual seam | New residual machinery | existing `add_to_residual!` / `register_constraint!` | Loss terms are affine — they fit the existing `:Rp`/`:Rq` seam unchanged |
| Radial validation of the fixture | New topology check | existing `assert_radial` (runs at `Feeder` construction) | DATA-02 already enforced; 11 buses/10 branches = tree |

**Key insight:** every heavy lift in this phase is already provided — the cone by JuMP/Clarabel, the
assembly/dual/status/seam by Phases 1–3. The genuinely new code is small: one formulation file, one
checker, one fixture, one oracle wrapper.

## Common Pitfalls

### Pitfall 1: SOCP relaxation inexact and nobody checks (THE headline risk)
**What goes wrong:** the relaxed problem always solves and returns a voltage/price profile, but if the
cone is *strict* at the optimum (`l·v > P²+Q²`), `l` is a fictitious over-current, voltages are wrong,
and the DADP duals are physically meaningless — with no solver error.
**Why it happens:** standard exactness conditions break under reverse power flow (PV back-feed) and
binding *upper* voltage limits (over-voltage) — exactly the high-PV regimes the thesis targets.
**How to avoid:** implement the 3.43/3.45 exactness copy as part of the model (Pattern 2); run the
`max|l·v−(P²+Q²)| < τ` invariant after *every* SOCP solve (Pattern 4) on BOTH an easy fixture and a
high-PV/over-voltage fixture; refuse prices on failure.
**Warning signs:** gap shrinks when you tighten solver tolerance (you were reading a loose point);
`l·v` noticeably exceeds `P²+Q²` on any branch.

### Pitfall 2: Wrong `τ` relative to solver tolerance
**What goes wrong:** `τ` set below Clarabel's achievable accuracy → false failures; `τ` too loose →
inexactness slips through.
**Why it happens:** conflating the *convergence* tolerance with the *exactness* tolerance.
**How to avoid:** Clarabel's `tol_gap_abs/rel = 1e-8` (SOCP factory) is far tighter than the recommended
per-unit exactness `τ = 1e-5` (thesis convergence used `ε = 5×10⁻⁵`). Keep `τ` ≈ `1e-5` per-unit and
scale-aware; make it a kwarg. The two-order-of-magnitude margin makes the check meaningful, not brittle.

### Pitfall 3: Unit/per-unit scaling silently corrupts prices
**What goes wrong:** mixing ¢$/kWh (battery `λ`) with $/MWh (MEM `λ₀`), or MW vs pu, makes one objective
term dwarf another; the solve succeeds but welfare/prices are off by 10×–100×.
**Why it happens:** the thesis uses ¢$/kWh for `λ_max/min/med` and $/MWh-style MEM prices; the feeder
data is pu on a 100 MVA / 13.2 kV base.
**How to avoid:** the IEEE-13 fixture must convert to pu once at ingestion (base **100 MVA, 13.2 kV** —
thesis Table 4.1) via the existing `PerUnit` helpers; `S_max,01 = 6.86 MVA` ⇒ `0.0686` pu. Keep a single
monetary unit through the objective. The existing magnitude tripwires (`assert_magnitudes`) guard the
electrical side; document every coefficient's unit.

### Pitfall 4: Solver mismatch / loose duals on the SOCP
**What goes wrong:** using Ipopt as the *primary* SOCP solver (treats the cone as smooth NLP, stalls
near the boundary, KKT duals need care), or reading an `ALMOST_OPTIMAL`/low-accuracy conic point as the
DLMP, or handing the SOCP to HiGHS (LP/MILP/QP only — no SOCP).
**How to avoid:** route SOCP → Clarabel via `SOCP()` (Pattern 5); use Ipopt only as an independent
cross-check (`select_optimizer(NLP())`, `allow_local=true`) and assert objective + exactness gap agree;
never certify exactness/DADP with SCS.
**Warning signs:** cross-solver objective disagreement; gap that moves with tolerance.

### Pitfall 5: DADP dual sign
**What goes wrong:** JuMP's dual sign depends on constraint sense and objective sense (Max here); getting
it wrong flips the price signal (charges look like credits), yet the result is internally consistent and
feasible.
**How to avoid:** the balance is `balance_p[j,t]: R_p == 0` under `Max`; `dadp = dual.(balance_p[…])` is
already the convention `solve_welfare` uses. Phase 4 only needs the dual *available and finite*; the
sign/decomposition validation is PRICE-01/02 (Phase 5). Add a hand-checked sign regression when Phase 5
lands. Note the frontier/MEM-node dual should track `λ₀` (marginal cost of import).

### Pitfall 6: Loss term charged at the wrong node
**What goes wrong:** placing `−r·l` at the parent instead of the child of branch `(i,j)` shifts losses
and corrupts the balance.
**How to avoid:** per eq. 3.31 the incoming branch `(i,j)` contributes `+P_ij − r_ij·l_ij` at child `j`;
outgoing branches `(j,m)` contribute `−P_jm` at `j`. Assemble by iterating branches with explicit
from/to, mirroring the existing `LinDistFlow` inflow/outflow loop.

## Code Examples

### Modified IEEE-13 feeder fixture (DATA-03)
```julia
# Source: thesis Table 4.1 + Figure 4.1 (pp. 89-90); base 100 MVA / 13.2 kV [CITED: thesis]
# 11 nodes: 0 = MEM frontier (root, |V0|=13.2 kV), 1..10 = aggregator load nodes. 10 branches (radial).
# Bus ids are 1-based positions ⇒ thesis node k → struct index k+1 (root=1). Voltage 0.95..1.05 pu.
# Branch (from,to) r[pu]   x[pu]        (from,to) r[pu]   x[pu]
#  (0,1)  0.310  0.155      (1,6)  0.300  0.150
#  (1,2)  0.310  0.155      (2,7)  0.300  0.150
#  (2,3)  0.310  0.155      (3,8)  0.300  0.150
#  (1,4)  0.150  0.075      (3,9)  0.600  0.300
#  (4,5)  0.150  0.075      (2,10) 0.300  0.150
# Head-branch limit S_max,(0,1) = 6.86 MVA ⇒ 0.0686 pu on 100 MVA base (apply to branch (0,1)).
function ieee13_modified()
    vmin, vmax = 0.95, 1.05
    buses = [Bus(i, vmin, vmax, i == 1) for i in 1:11]      # index 1 = thesis node 0 (root)
    # (thesis_from, thesis_to, r, x, smax_pu) — shift node k → index k+1:
    raw = [(0,1,0.310,0.155,0.0686), (1,2,0.310,0.155,100.0), (2,3,0.310,0.155,100.0),
           (1,4,0.150,0.075,100.0),  (4,5,0.150,0.075,100.0), (1,6,0.300,0.150,100.0),
           (2,7,0.300,0.150,100.0),  (3,8,0.300,0.150,100.0), (3,9,0.600,0.300,100.0),
           (2,10,0.300,0.150,100.0)]
    branches = [Branch(f+1, t+1, r, x, s) for (f,t,r,x,s) in raw]
    return Feeder(buses, branches, 1)     # assert_radial + assert_magnitudes run here
end
```
Note: non-head branches have no explicit thermal limit in the thesis; use a large `smax` (or the head
value) so `assert_magnitudes` passes and only branch (0,1) actually binds (the case is congestion-driven
at the head). Confirm per Open Question 2.

### GLB-CVX solve on the SOCP formulation (OPT-02)
```julia
feeder = ieee13_modified()
aggs   = build_ieee13_aggregators(feeder)          # 10 aggregators, nodes 1..10 (φ∈[0.85,0.95])
ctx, cost, dadp = solve_welfare(feeder, ConvexBranchFlow(), aggs;
                                T = 24, λ₀ = mem_price_profile(),
                                optimizer = select_optimizer(SOCP()))   # or via problem_class trait
# assert_socp_exact! ran inside (gated on :l) → dadp is trustworthy; nodal-balance dual available.
```

### Verified JuMP Parameter (SEAM-01 rolling-horizon stub)
```julia
# Source: jump.dev manual/variables + manual/nonlinear (Context7, 2026-07-18) [CITED]
@variable(m, soc0 in Parameter(1.0))       # rolling-horizon initial state; battery SOC IC
set_parameter_value(soc0, new_state)        # re-set between horizons, then optimize! (no rebuild)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ECOS / SCS as default conic solver | Clarabel (native quadratic-objective IPM, accurate duals) | ~2022–2024 | Clarabel is the community-default open-source conic solver; correct choice for price-as-dual work |
| `termination_status == OPTIMAL` hand-check | `is_solved_and_feasible(model; dual, allow_local)` | JuMP 1.x | Already adopted in `assert_solved!`; also checks primal/dual status |
| Manual SOC epigraph reformulation | `RotatedSecondOrderCone()` + MOI bridges | JuMP 1.x | Direct cone syntax; solver-agnostic |
| `direct_model(Clarabel.Optimizer())` for speed | standard `Model(...)` (Clarabel is copy_to-only) | verified 2026-07-18 | Already corrected in `factory.jl`; `direct_model` reserved for HiGHS |

**Deprecated/outdated:**
- The CLAUDE.md perf note suggesting `direct_model` for Clarabel — superseded; `factory.jl` documents
  the correction.
- ECOS anywhere in this stack — superseded by Clarabel.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `v₉[16] ≈ 1.0493` is the **voltage magnitude** \|V₉\| at node 9, hour 16 (Fig 4.4 y-axis is "Tensión [p.u.]", peak ≈1.05), not the squared variable `v` (which would be 1.0243) | Open Q1 | Regression assert on the wrong quantity; assert on `sqrt(value(v))` and confirm against √ |
| A2 | Reproducing `v₉[16]` and welfare `$1819` requires the full thesis input data (MEM profile Fig 4.5, temp Fig 4.2, per-house device params, Markov PV) not fully tabulated | Open Q1 | Cannot bit-reproduce; must pin a computed golden value instead |
| A3 | 10 aggregators sit on nodes 1–10 (one per non-root bus per Fig 4.1); house counts (784 total / 112 per node) imply ~7 house-bearing nodes — a thesis inconsistency | Data / Open Q1 | Load scaling off; social-welfare number won't match |
| A4 | Non-head branches carry no binding thermal limit; only `S_max,(0,1)=6.86 MVA` binds (congestion-driven case) | Data / Open Q2 | Over/under-constrained network; wrong prices |
| A5 | `τ = 1e-5` per-unit is the right exactness tolerance (thesis ε=5e-5, Clarabel gap 1e-8) | Pitfall 2 | False pass/fail on the PF-04 gate |
| A6 | The reactive frontier free-sign `q_import` (Phase-3 WR-03 fix) is correct for the SOCP reactive balance too | Pattern 3 | Reactive balance infeasible or Q≡0 forced |
| A7 | Apparent-power limits 3.36 (forward) suffice; the receiving-end limit 3.37 (`P_ji²+Q_ji²`) is secondary on a radial feeder with a single directed flow variable | Pattern 3 | Missing a binding reverse-flow limit under heavy PV export |

**If this table is empty:** it is not — these need confirmation before the ground-truth regression is
locked. A1–A3 in particular gate whether OPT-02/OPT-03 can *reproduce* the thesis or must pin a
self-consistent golden value.

## Open Questions (RESOLVED)

> RESOLVED: Q1 (exact thesis reproduction) → pin a computed golden as the primary anchor + assert 1.0493 as an approximate `|V|=sqrt(v)` cross-check within tolerance, with a blocking human-verify checkpoint (04-06); Q2 (interior thermal limits) → 99.0 pu sentinel honoring the strict assert_magnitudes band (04-03); Q3 (PMD oracle) → DEFER (Ipopt cross-check + thesis ground truth suffice).

1. **Can the thesis ground-truth numbers (`v₉[16] ≈ 1.0493`, welfare `$1819`) be reproduced exactly?**
   - What we know: the feeder topology/limits (Table 4.1), voltage bounds, head-branch limit, battery
     price triple (`λ_max=8.9, λ_min=3.8, λ_med=6.2` ¢$/kWh), and φ range are tabulated; ρ=1000,
     ε=5e-5, 28 iterations, exact relaxation confirmed.
   - What's unclear: the MEM 24h price profile (Fig 4.5, only plotted), exterior-temperature profile
     (Fig 4.2, plotted), full per-house device parametrization (App. C/D/E), Markov-generated PV/demand,
     and the house-count inconsistency (A3). The centralized objective = social welfare = the DADP-case
     `$1819` (Table 4.4), so it *should* be reproducible given identical inputs.
   - Recommendation: treat PF-04 (exactness gap) and the feeder-fixture structs as the HARD, achievable
     Phase-4 gates. For OPT-02/OPT-03, **pin the current computed `(v₉[16], objective, DADP)` as a
     golden regression** once inputs are fixed (digitize Fig 4.5/4.2 if fidelity to `$1819` is required),
     and assert `v₉[16]` to `~1e-3`. Confirm A1 (magnitude vs. squared) with the researcher.

2. **Thermal limits on non-head branches.**
   - What we know: only `S_max,(0,1) = 6.86 MVA` is given; the case is described as congestion-driven at
     the head.
   - What's unclear: whether interior branches are meant to be unconstrained.
   - Recommendation: leave interior branches effectively unconstrained (large `smax`) and apply the SOC
     apparent-power limit only where a real limit exists; confirm with the researcher.

3. **PowerModelsDistribution cross-validation oracle — adopt or defer?**
   - What we know: CLAUDE.md lists PMD 0.16.0 as a data/validation oracle (parse OpenDSS IEEE-13,
     cross-check a no-DER AC-OPF baseline). It is a heavyweight new dependency.
   - Recommendation: **DEFER.** The independent Ipopt cross-check (`NLP()` factory, `allow_local=true`)
     already provides cross-solver objective/exactness agreement (Pitfall 4), and the thesis provides
     the ground truth. Adopt PMD only if a no-DER AC power-flow oracle later proves necessary; if so,
     pin 0.16.0 behind a human-verify checkpoint.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 (floor 1.10 LTS) | — |
| JuMP | modeling / cones / duals | ✓ (pinned) | 1.30.1 | — |
| Clarabel | SOCP + QP solve | ✓ (pinned) | 0.11.1 | Mosek (licensed) / SCS (scouting only) |
| Ipopt | cross-check | ✓ (pinned) | 1.15.0 | — |
| TestItemRunner/TestItems | test harness | ✓ (test/Project.toml) | 1.1.5 / 1.0.0 | plain `@testset` |
| StableRNGs | seeded profiles | ✓ (pinned) | 1.0.4 | — |
| ctx7 (docs) | research-time only | ✓ | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none required. (PowerModelsDistribution is *not* added — deferred.)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItemRunner 1.1.5 + TestItems 1.0.0 (Test stdlib) |
| Config file | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| Quick run command | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("socp", ti.name)'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

Convention: each `@testitem` name **contains the filter substring** so `occursin(...)` selects it (e.g.
`"socp: ..."`, `"exactness: ..."`, `"ieee13: ..."`, `"oracle: ..."`). Fixtures shared via `setup=[...]`
modules (see `test/fixtures_phase3.jl` pattern).

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PF-03 | `ConvexBranchFlow` writes `:Rp`/`:Rq` (with loss), cone, drops, `v̂`, 3.45 bounds by dispatch | unit | `... filter=ti->occursin("socp",ti.name)` | ❌ Wave 0 (`test/test_convex_branch_flow.jl`) |
| PF-03 | DC↔LinDistFlow↔SOCP interchange (zero-edit swap) extends the conformance test | integration | `... occursin("conformance",ti.name)` | ⚠️ extend `test/test_conformance.jl` |
| PF-04 | `assert_socp_exact!` passes on easy fixture; **throws** on inexact; gap reported | unit | `... occursin("exactness",ti.name)` | ❌ Wave 0 (`test/test_exactness.jl`) |
| PF-04 | Exactness holds on a high-PV/over-voltage stress fixture (prices NOT refused) | integration | `... occursin("exactness",ti.name)` | ❌ Wave 0 |
| OPT-02 | GLB-CVX solves on IEEE-13 to OPTIMAL; nodal-balance dual finite | integration | `... occursin("ieee13",ti.name)` | ❌ Wave 0 (`test/test_ieee13.jl`) |
| OPT-02 | Cross-solver (Clarabel vs Ipopt) objective + gap agree | integration | `... occursin("ieee13",ti.name)` | ❌ Wave 0 |
| OPT-02/03 | Regression: `v₉[16]`, objective, DADP match pinned golden (see Open Q1) | regression | `... occursin("ieee13",ti.name)` | ❌ Wave 0 |
| OPT-03/SEAM-01 | `operational_oracle` returns `(cost, π)`; stub kwargs (`role`, `objective_hook`, `z`, rolling `Parameter`) present | unit | `... occursin("oracle",ti.name)` | ❌ Wave 0 (`test/test_oracle.jl`) |
| DATA-03 | `ieee13_modified()` constructs (radial + magnitudes pass); topology matches Table 4.1 | unit | `... occursin("ieee13",ti.name)` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the filtered `@testitem` for the file just edited (`occursin("<substring>",...)`).
- **Per wave merge:** full `Pkg.test()` (also runs Aqua + JET).
- **Phase gate:** full suite green + the PF-04 exactness gate demonstrably throwing on the inexact
  fixture before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_convex_branch_flow.jl` — covers PF-03 (formulation-level dispatch/shape)
- [ ] `test/test_exactness.jl` — covers PF-04 (pass, throw-on-inexact, gap report)
- [ ] `test/test_ieee13.jl` — covers DATA-03 + OPT-02/03 (fixture, solve, cross-solver, regression)
- [ ] `test/test_oracle.jl` — covers OPT-03 + SEAM-01 (oracle signature, stub kwargs)
- [ ] `test/fixtures_phase4.jl` — shared setup module: `ieee13_modified()`, easy + high-PV fixtures,
      MEM/temp profiles (digitized or approximated), aggregator builder
- [ ] extend `test/test_conformance.jl` — add the SOCP arm to the DC↔LinDistFlow swap contract
- [ ] Framework install: none — TestItemRunner already in `test/Project.toml`

## Security Domain

> `security_enforcement` is not set in `.planning/config.json`; treated as enabled. This is a
> single-user research library with no authentication, network surface, or untrusted input, so most
> ASVS categories are N/A. The relevant discipline is **input/numerical validation**.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface (local research CLI) |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes | Loud `throw(ArgumentError/error)` on malformed feeders (`assert_radial`, `assert_magnitudes`), shape mismatches (`λ₀` length), and — new here — the PF-04 exactness gate refusing prices; never `@assert` (elided under `-O`) |
| V6 Cryptography | no | N/A — no secrets/crypto |

### Known Threat Patterns for {Julia/JuMP research bench}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent-wrong result from inexact relaxation | Tampering (data integrity) | PF-04 exactness gate throws; report `maxgap` as first-class output |
| Trusting a loose/`ALMOST_OPTIMAL` dual as a price | Tampering | `assert_solved!(dual=true)` + tight Clarabel gap; cross-solver agreement |
| Unit/scale confusion corrupting objective | Tampering | Single per-unit system, ingestion-time conversion, magnitude tripwires |
| Non-reproducible experiment (unseeded RNG) | Repudiation | Seeded `StableRNGs` profiles (existing `generate_profiles`) |

## Sources

### Primary (HIGH confidence)
- Context7 `/jump-dev/jump.jl` — `RotatedSecondOrderCone`/`SecondOrderCone` syntax (`‖x‖²≤2tu`),
  `Parameter` set + `parameter_value`/`set_parameter_value` (manual/constraints, manual/variables,
  manual/nonlinear). Fetched 2026-07-18.
- Context7 `/oxfordcontrol/clarabeldocs` — Clarabel is "an interior-point solver for conic programs with
  quadratic objectives"; SOCP + quadratic-objective support confirmed. Fetched 2026-07-18.
- Thesis PDF `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf` — formulation eqs.
  3.29–3.45 (pp. 81–85), GLB-OPT/GLB-CVX (pp. 83–84), modified IEEE-13 Table 4.1 + Fig 4.1 (pp. 89–90),
  voltage/head-branch limits + `v₉[16]=1.0493` + 28-iteration/exact-relaxation result (pp. 94–95),
  welfare/energy ground truth Tables 4.4–4.5 (pp. 99–100).
- Existing source (read this session): `src/powerflow/{AbstractPowerFlow,DCPowerFlow,LinDistFlow}.jl`,
  `src/models/{welfare_solve,linear_solve}.jl`, `src/core/{ModelContext,status}.jl`,
  `src/solver/{factory,ProblemClass}.jl`, `src/data/{Feeder,topology,profiles}.jl`,
  `src/units/PerUnit.jl`, `src/devices/{AbstractDevice,Aggregator,PVBattery,Interruptible}.jl`.
- `.planning/research/PITFALLS.md` — SOCP inexactness (Pitfall 1), solver mismatch (Pitfall 4), dual
  sign, unit scaling; cites Farivar–Low / Gan–Low exactness literature.
- `.planning/research/THEORY-thesis.md` + `THEORY-papers.md` — model digest + PSR planning-note coupling
  (z↔p_ag, π_s = dual of coupling; distributor = leader).

### Secondary (MEDIUM confidence)
- CLAUDE.md Technology Stack — version pins (JuMP 1.30.1, Clarabel 0.11.1, Ipopt 1.15.0, PMD 0.16.0) from
  the Julia General registry (dated 2026-07-18); Clarabel `copy_to`-only correction already applied in
  `factory.jl`.

### Tertiary (LOW confidence)
- Figure-derived quantities (MEM price profile Fig 4.5, temperature Fig 4.2, `v₉[16]` magnitude-vs-squared
  reading) — plotted, not tabulated; flagged in Assumptions Log / Open Q1.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; JuMP/Clarabel API re-verified live via Context7.
- Architecture (formulation + exactness copy + seam fit): HIGH — full equations extracted; drops onto
  the proven `LinDistFlow` pattern.
- Ground-truth reproduction (OPT-02/03 numbers): MEDIUM — feeder/params tabulated, but profiles/house
  counts partly figure-bound (Open Q1). Exactness gate (PF-04) is HIGH-confidence and achievable.
- Pitfalls: HIGH — corroborated by PITFALLS.md and established relaxation-exactness literature.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 (stable stack; JuMP/Clarabel APIs settled). Re-check only if JuMP major or
Clarabel minor bumps before implementation.
