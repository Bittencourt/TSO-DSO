# Phase 5: Distribution Pricing — DADP & DLMP Decomposition - Research

**Researched:** 2026-07-18
**Domain:** Convex-duality post-processing of a solved SOCP branch-flow model (DLMP extraction, KKT-based four-way decomposition, welfare accounting) in Julia + JuMP
**Confidence:** HIGH on extraction/welfare-accounting/economic-checks (verified against thesis eqs. 3.31/3.38/3.46/3.47/4.1 and the Phase-4 source); MEDIUM on the exact DLMP four-way decomposition (the thesis describes it only qualitatively — Fig 4.5/4.6 text — so the closed-form component formulas are derived from standard branch-flow DLMP theory, not a numbered thesis equation)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
CONTEXT.md contains **no user-preference grey areas** — the phase is auto-generated (discuss skipped) because the DLMP decomposition, welfare split, and FIT baseline are all determined by the source thesis. The following are anchored to the thesis + Phase-4 duals (verbatim from CONTEXT.md "Claude's Discretion"):

- **DADP/DLMP extraction (PRICE-01):** the dual of the nodal active-power balance constraint (`dual(balance_p[node,t])`) that `welfare_solve` already exposes — per node per hour. Sign verified against a hand-solved 2-bus example (positive = marginal cost of consumption at that node/hour).
- **DLMP decomposition (PRICE-02):** decompose the nodal price into **energy + loss + congestion + voltage** components (from the duals of the corresponding constraints / KKT terms per the thesis), asserting the components SUM to the nodal price with correct sign. This is a post-solve computation reading the model's duals.
- **Welfare accounting (PRICE-03):** split total welfare into **social / DSO / prosumer surplus** with a **FIT (feed-in-tariff) baseline** counterfactual, reproducing the +25%-social-welfare headline (as a RATIO vs the FIT baseline — likely more robust than absolute numbers, which may be figure-bound like Phase 4's welfare). Pin a computed value + cross-check the thesis ratio.
- **Economic-direction checks (PRICE-04):** assert the price falls BELOW wholesale (λ₀) at PV glut and rises ABOVE it at congestion — the qualitative economic-correctness sanity checks.
- **Solver/status discipline (CLAUDE.md):** read duals only after `assert_solved!`/exactness gate; the SOCP exactness gate (PF-04) must have passed before any DLMP is trusted (prices refused if not).

### Claude's Discretion
- Module placement (`src/pricing/` vs `src/models/`), function signatures, and internal decomposition strategy.
- Whether the FIT baseline is thesis-faithful (full FIT-OPT + AC power flow) or a reduced counterfactual — recommend below.

### Deferred Ideas (OUT OF SCOPE)
- ADMM decomposition → Phase 6.
- Experiment harness / scenario sweeps that USE these prices → Phase 8.
- Reconciling the absolute welfare gap (thesis figure digitization) → the Phase-4 follow-up item in STATE.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PRICE-01 | Extract DADP/DLMP as the dual of the nodal active-power balance, per node per hour | `ctx.constraints[:balance_p]` is a `bus×time` `@constraint` array already registered by `welfare_solve` (welfare_solve.jl:214). `dual.(ctx.constraints[:balance_p][j, :])` yields node `j`'s DADP over the horizon — **per-node per-hour is fully recoverable today; NO Phase-4 change needed**. Sign pinned by a hand-solved 2-bus example. [VERIFIED: src/models/welfare_solve.jl] |
| PRICE-02 | Decompose DLMP into energy/loss/congestion/voltage summing to the nodal price (assertion-validated) | Derived from the KKT stationarity of the branch-flow variables (thesis 3.31/3.33/3.36/3.35/3.45). Requires a **small additive Phase-4 change**: register the voltage-drop (`vdrop`, 3.33) and apparent-power-limit (3.36) constraint handles so their duals are recoverable. Voltage-bound duals are already reachable via `ctx.meta[:pf_vars]`. Sum-to-λⱼ assertion is the safety net. [CITED: branch-flow DLMP theory] + [VERIFIED: src/powerflow/ConvexBranchFlow.jl] |
| PRICE-03 | Welfare accounting: social/DSO/prosumer surplus + FIT baseline, reproducing +25% headline | Prosumer surplus = positive value of AGR-OPT (3.46); DSO surplus = negative value of DSO-OPT (3.47); social = sum = the GLB-CVX objective (3.38) — an exact accounting identity to assert. FIT baseline = a separate FIT-OPT (3.24–3.28) + AC-PF solve; DSO benefit = (4.1). +25% = ratio social_DADP/social_FIT (thesis $1819/$1457 ≈ 1.25). [VERIFIED: thesis eqs. 3.38/3.46/3.47/4.1, page 98] |
| PRICE-04 | Economic-direction checks: price < wholesale at PV glut, > wholesale at congestion | Reuse `Phase4Fixtures.build_high_pv_aggregators` (PV glut, `allow_export=true`) and `build_ieee13_ground_aggregators` (head-branch congestion). Assert `dadp[t] < λ₀[t]` at over-generation hours, `dadp[t] > λ₀[t]` at congested hours (thesis Fig 4.5/4.6: node 9 at 15:00 < MEM, at 22:00 > MEM). [VERIFIED: test/fixtures_phase4.jl + thesis page 96] |
</phase_requirements>

## Summary

Phase 5 is a **pure convex-duality post-processing layer** over the Phase-4 SOCP solve. Nothing new is optimized except one counterfactual (the FIT baseline). The centralized GLB-CVX solve (`solve_welfare` / `operational_oracle`) already: (a) registers the nodal active balance as `ctx.constraints[:balance_p]` (a `bus×time` array), (b) gates every dual read behind `assert_solved!` and the PF-04 exactness certificate, and (c) stashes the SOCP branch/voltage variables under `ctx.meta[:pf_vars] = (;v, v̂, P, Q, l)`. This makes **PRICE-01 essentially free** — the per-node per-hour DADP is `dual.(ctx.constraints[:balance_p][j, :])`. The one gap is that `solve_welfare` currently only *returns* the first aggregator's DADP; the pricing module reads `ctx` directly instead.

The **DLMP four-way decomposition (PRICE-02)** is the only intellectually hard part. The thesis presents it **qualitatively** (Fig 4.5/4.6 narrative: distant nodes cost more from incremental losses, prices rise at congestion) but gives **no closed-form energy/loss/congestion/voltage equation**. The decomposition must therefore be **derived from the KKT stationarity of the branch-flow variables** and validated by asserting the four components sum to `dual(balance_p[j,t])`. This requires a **small additive Phase-4 change**: register the voltage-drop (3.33) and apparent-power-limit (3.36) constraint handles. The **welfare accounting (PRICE-03)** is exact and thesis-faithful: prosumer surplus = value of (3.46), DSO surplus = negative value of (3.47), social welfare = their sum = the GLB-CVX objective (3.38) — a clean identity to assert. The FIT baseline is the single new solve (FIT-OPT 3.24–3.28 + a plain AC power flow), and — because the Phase-4 absolute welfare is figure-bound — the +25% headline should be pinned as a **computed ratio with the thesis 1.25 as an approximate cross-check**, exactly matching the established Phase-4 computed-golden pattern.

**Primary recommendation:** Create a new `src/pricing/` module of throw-on-violation post-processing functions (`extract_dlmp`, `decompose_dlmp`, `welfare_accounting`, `fit_baseline`, `economic_direction_checks`) consuming a solved `ModelContext`; add the two `register_constraint!` calls to `ConvexBranchFlow.contribute!` for the decomposition; make the sum-to-λⱼ assertion and the surplus-sum-equals-objective identity the load-bearing correctness gates; pin ratios, not absolute welfare.

## Architectural Responsibility Map

This is a single-process research library, so "tiers" are the module layers the data flows through. Every Phase-5 capability lives in the **post-processing tier** — it reads a solved model, it does not build or solve one (except the FIT counterfactual, which is a genuine but self-contained solve).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| DADP extraction (PRICE-01) | Pricing post-processing (`src/pricing/`) | Model (`ctx.constraints[:balance_p]`) | Reads an already-registered dual; owns no model state |
| DLMP decomposition (PRICE-02) | Pricing post-processing | Power-flow (`ConvexBranchFlow` must expose 2 more constraint handles) | Needs branch/voltage-constraint duals the SOCP formulation owns |
| Welfare accounting (PRICE-03) | Pricing post-processing | Model + Devices (utility exprs, `objective_value`) | Reads primal values + duals; asserts an accounting identity |
| FIT baseline counterfactual (PRICE-03) | Model (a NEW small solve) | Devices (reuses device builders minus battery) | The only capability that optimizes; a separate per-prosumer solve + AC-PF |
| Economic-direction checks (PRICE-04) | Pricing post-processing | Data (`Phase4Fixtures` scenarios) | Reads DADP vs λ₀ on the PV-glut / congestion fixtures |

**Boundary rule (matches the codebase):** the pricing module NEVER names a solver and NEVER touches `ctx.residuals`; it only reads `ctx.constraints`, `ctx.meta[:pf_vars]`, `ctx.meta[:agg_device_vars]`, and `objective_value(ctx.model)`. The FIT baseline routes its solver through `select_optimizer(problem_class(pf))` like every other solve (INFRA-02).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 (pinned) | `dual()`, `reduced_cost()`, `value()`, `objective_value()` on the solved model | Already the project's modeling layer; per-constraint dual access is exactly why JuMP was chosen over Convex.jl (CLAUDE.md Deep-Dive #1). [VERIFIED: Project.toml] |
| Clarabel | 0.11.1 (pinned) | The SOCP solver whose accurate interior-point duals ARE the DADP; also solves the FIT baseline's AC-PF if posed as an SOCP | IPM accuracy >> first-order for price recovery (CLAUDE.md). [VERIFIED: Project.toml] |
| TSODSO internals | — | `solve_welfare`, `operational_oracle`, `ConvexBranchFlow`, `Aggregator`, device builders, `Phase4Fixtures` | Everything Phase 5 needs already exists and is tested. [VERIFIED: src/] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| HiGHS | 1.24.1 | LP/QP backend if the FIT baseline is posed as a plain AC power flow / LP | Only via `select_optimizer` if the FIT-PF is linear; Clarabel handles the SOCP case. [VERIFIED: Project.toml] |
| TestItemRunner / TestItems | 1.1.5 / 1.0.0 | `@testitem` / `@testmodule` test discovery | The established test idiom; new items filter by name substring. [VERIFIED: test/Project.toml] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Deriving loss/congestion/voltage from KKT duals | Finite-difference sensitivity (perturb load, re-solve, read Δwelfare) | Finite-difference gives λⱼ directly but NOT the four-way split, and costs N×T extra solves — reject for the decomposition; keep as an optional cross-check for the *total* λⱼ sign only |
| Thesis-faithful FIT-OPT + AC-PF | Reduced FIT counterfactual (fixed λ, same devices, drop battery incentive) | The reduced version is cheaper but drifts from the thesis 4.1 settlement; recommend thesis-faithful since correctness/traceability is the project's core value |

**Installation:** No new packages. This is pure post-processing over the existing stack.

**Version verification:** All versions are already pinned in `Project.toml`/`Manifest.toml` and were verified against the Julia General registry on 2026-07-18 (CLAUDE.md Sources). No registry lookup needed for Phase 5.

## Package Legitimacy Audit

**Not applicable — Phase 5 installs ZERO external packages.** It is post-processing over the already-pinned, already-audited Phase-1..4 dependency set (`JuMP`, `Clarabel`, `HiGHS`, `Ipopt`, `SCS`-not-used-here, `StableRNGs`, test-only `Aqua`/`JET`). No `Pkg.add`, no new registry surface, so the slopcheck / cross-ecosystem-confusion gate has nothing to evaluate. If a plan proposes adding a package, it must run the Package Legitimacy Gate first — but the thesis math needs none.

## Architecture Patterns

### System Architecture Diagram

```
                 Phase-4 (already built & tested)                    Phase 5 (this phase)
   ┌──────────────────────────────────────────────┐   ┌────────────────────────────────────────┐
   │  solve_welfare / operational_oracle            │   │  src/pricing/  (post-processing)        │
   │   (ConvexBranchFlow SOCP, allow_export)        │   │                                          │
   │        │                                       │   │                                          │
   │   assert_solved!  ──► assert_socp_exact! (gate)│   │                                          │
   │        │  (prices REFUSED if inexact)          │   │                                          │
   │        ▼                                       │   │                                          │
   │  solved ModelContext `ctx`                     │   │                                          │
   │   ├─ ctx.constraints[:balance_p]  (bus×time) ──┼──►│─► extract_dlmp(ctx)  ───────────► DADP    │  PRICE-01
   │   ├─ ctx.constraints[:balance_q]               │   │        (dual of 3.31, per node/hour)     │
   │   ├─ ctx.constraints[:vdrop]   *(add: 3.33)* ──┼──►│─► decompose_dlmp(ctx) ─► energy+loss+    │  PRICE-02
   │   ├─ ctx.constraints[:smax]    *(add: 3.36)* ──┼──►│     congestion+voltage  (Σ == DADP  ⚠assert)│
   │   ├─ ctx.meta[:pf_vars]=(v,v̂,P,Q,l) ──────────┼──►│        (voltage-bound duals via v,v̂)     │
   │   ├─ ctx.meta[:agg_device_vars]  ─────────────┼──►│─► welfare_accounting(ctx; baseline) ─────►│  PRICE-03
   │   └─ objective_value(ctx.model)  ─────────────┼──►│     social = prosumer + DSO  (== obj ⚠assert)│
   └──────────────────────────────────────────────┘   │        │                                  │
                                                       │        └─ fit_baseline(...) ── NEW solve  │  PRICE-03
   ┌──────────────────────────────────────────────┐   │           (FIT-OPT 3.24–3.28 + AC-PF)     │
   │  Phase4Fixtures (reused)                       │   │           social_DADP/social_FIT ≈ 1.25  │
   │   high_pv_feeder / build_high_pv_aggregators ──┼──►│─► economic_direction_checks(ctx; λ₀) ────►│  PRICE-04
   │   ieee13_modified / ground_aggregators ────────┼──►│     PV glut: DADP<λ₀ ; congestion: DADP>λ₀│
   └──────────────────────────────────────────────┘   └────────────────────────────────────────┘
```
`*(add)*` = the small additive Phase-4 change (two `register_constraint!` calls in `ConvexBranchFlow.contribute!`).

### Recommended Project Structure
```
src/pricing/
├── dlmp.jl        # extract_dlmp (PRICE-01) + decompose_dlmp (PRICE-02)
├── welfare.jl     # welfare_accounting + surplus identities (PRICE-03)
├── fit.jl         # fit_baseline: the FIT-OPT (3.24–3.28) + AC-PF counterfactual (PRICE-03)
└── checks.jl      # economic_direction_checks (PRICE-04)
```
Wire into `src/TSODSO.jl` with `include(...)` calls placed AFTER `models/oracle.jl` (pricing depends on `solve_welfare`/`operational_oracle`/`ConvexBranchFlow`). Follow the file-header SEAM/OWNER comment convention used everywhere in `src/`.

### Pattern 1: PRICE-01 — DADP extraction (post-processing, zero new solve)
**What:** Read the dual of the registered active-balance array for every node and hour.
**When to use:** The first thing the module does; everything else builds on it.
```julia
# Source: derived from src/models/welfare_solve.jl:213-214 (balance_p registered as bus×time)
"""
    extract_dlmp(ctx) -> Matrix{Float64}   # size (N_buses, T)

DADP/DLMP = dual of the nodal ACTIVE-power balance (thesis eq. 3.31), per node per hour.
Requires a solve that passed `assert_solved!(...; dual=true)` AND the PF-04 exactness gate
(both enforced inside `solve_welfare` before it returns `ctx`). Positive = marginal cost of
consumption at that node/hour (sign pinned by the 2-bus regression, PRICE-01).
"""
function extract_dlmp(ctx)
    bp = ctx.constraints[:balance_p]          # JuMP bus×time ConstraintRef array
    N, T = size(bp)
    return [dual(bp[j, t]) for j in 1:N, t in 1:T]
end
```
Note: `welfare_solve` returns only the first aggregator's DADP (welfare_solve.jl:254-255). Phase 5 reads `ctx` directly, so it recovers ALL nodes — no Phase-4 change for PRICE-01.

### Pattern 2: PRICE-02 — KKT branch-flow DLMP decomposition (the hard part)
**What:** Split `λⱼ = dual(balance_p[j,t])` into energy + loss + congestion + voltage, and ASSERT the four sum to `λⱼ`.
**When to use:** After extraction; needs the two additional registered duals.

**Derivation (traced to thesis eqs.):** In the radial branch-flow model, KKT stationarity of the Lagrangian w.r.t. the branch active flow `P_{i,j}` (which appears with coefficient `+λ_j` in the child balance 3.31, `−λ_i` in the parent balance, and in the voltage-drop 3.33 with the `vdrop` dual `β_{ij}`, the copy-drop 3.43, and the apparent-power limit 3.36 with dual `ν_{ij} ≥ 0`) yields a **per-branch recursion**:

```
λ_j − λ_i  =  (loss term from β_{ij} · ∂vdrop/∂P and the −r·l balance loss)
             + (congestion term  2·P_{ij}·ν_{ij})
             + (voltage term  from the v/v̂ bound duals feeding β_{ij}, γ_{ij})
```

Because the feeder is a **tree**, node `j` has a unique path `root(0) → j`. Summing the recursion along that path telescopes:

```
λ_j = λ_0            (ENERGY, the root/MEM price — same at every node)
    + Σ_{(i,k)∈path} Δλ^loss_{ik}       (LOSS)
    + Σ_{(i,k)∈path} Δλ^cong_{ik}       (CONGESTION, nonzero only where 3.36 binds)
    + Σ_{(i,k)∈path} Δλ^volt_{ik}       (VOLTAGE, nonzero only where 3.35/3.45 binds)
```

- **Energy** = `λ_0` = `dual(balance_p[root,t])` (= `π` from `operational_oracle`, oracle.jl:184), equal to the MEM price at optimum since `p_import` is priced at `λ₀`. **Same for every node** (standard DLMP energy component).
- **Congestion** = attributed from the apparent-power-limit dual `ν_{ij}` (dual of 3.36); zero unless the head branch `S_max,(0,1)=0.0686 pu` binds (the modified IEEE-13 is congestion-driven at the head only, ieee13.jl).
- **Voltage** = attributed from the voltage-bound duals on `v`/`v̂` (3.35/3.45); nonzero in the over-voltage regime (thesis Fig 4.4, `v₉[16]`).
- **Loss** = the remaining `λ_j − λ_0 − congestion − voltage`, physically the marginal-loss term (the `r·l`/`(r²+x²)·l` sensitivity). The thesis attributes exactly this to "pérdidas de potencia incrementales" (page 96).

**Two implementation strategies (recommend A, keep B as the validator):**
- **(A) Path-telescoping attribution (recommended, sum-exact by construction):** compute each branch increment `λ_k − λ_i` from the registered duals, attribute it to loss/congestion/voltage by which dual is active on that branch, and accumulate along root→j paths. The total telescopes to `λ_j − λ_0` automatically, so `energy + Σincrements ≡ λ_j` holds by construction; the assertion then guards the *attribution*, not the sum.
- **(B) Independent per-component reconstruction (the assertion target):** compute energy, congestion (Σ ν·shift), voltage (Σ voltage-dual·sensitivity), loss (from vdrop dual) each independently and ASSERT `energy+loss+congestion+voltage ≈ λ_j` within a relative tolerance — this is Success Criterion #2 and the safety net against a missing term.

```julia
# Source: KKT of thesis 3.31/3.33/3.36; branch-flow DLMP theory (Papavasiliou 2018)
"""
    decompose_dlmp(ctx) -> NamedTuple of (energy, loss, congestion, voltage, total)   # each (N,T)

Four-way DLMP decomposition (PRICE-02). `total .== energy .+ loss .+ congestion .+ voltage`
is asserted within `rtol` (Success Criterion #2). `total .== extract_dlmp(ctx)` is asserted too.
Reads: ctx.constraints[:balance_p] (λ_j), [:vdrop] (β, 3.33), [:smax] (ν, 3.36),
and voltage-bound duals via ctx.meta[:pf_vars] (v, v̂ ; 3.35/3.45).
Throws (refuses a component set) if the four do not reconstruct the nodal price.
"""
```

**REQUIRED additive Phase-4 change (small, in-scope):** `ConvexBranchFlow.contribute!` builds `vdrop` (3.33), `cpydrop` (3.43), `cone` (3.39), and the apparent-power SOC constraint (3.36) as *local* `@constraint`s but registers none of them. Add:
```julia
# in src/powerflow/ConvexBranchFlow.jl contribute!, after the @constraint blocks:
register_constraint!(ctx, :vdrop, vdrop)        # dual β_{ij} feeds the loss/voltage split (3.33)
register_constraint!(ctx, :cpydrop, cpydrop)    # optional: exactness-copy dual (3.43)
# and give the apparent-power cone a name so its dual (congestion ν) is recoverable:
smax = @constraint(m, [ (b,br) ∈ enumerate(B), t ∈ 1:T ; br.smax < _SMAX_NO_LIMIT ],
                   [br.smax, P[b,t], Q[b,t]] in SecondOrderCone())
register_constraint!(ctx, :smax, smax)          # dual ν_{ij} = congestion (3.36)
```
Voltage-bound duals need NO registration: `dual(LowerBoundRef(v[j,t]))` / `dual(UpperBoundRef(v[j,t]))` (or `reduced_cost(v[j,t])`) are reachable because `v`/`v̂` are in `ctx.meta[:pf_vars]`.

### Pattern 3: PRICE-03 — welfare accounting via the surplus identity
**What:** Prosumer + DSO surplus, cross-checked against the GLB-CVX objective; FIT baseline ratio.
**When to use:** After extraction; the identity assertion is a strong correctness gate.

**Exact definitions (traced to thesis, verified page 98):**
- **Prosumer surplus** = positive value of AGR-OPT (3.46), summed over aggregators, at the centralized optimum (residual `R_{p,j}=0`, so the penalty term drops):
  `Pro = Σ_j [ value(U_agj) − Σ_t λ_j[t]·value(p_agj[t]) ]`
  where `U_agj` is the aggregator utility QuadExpr (Aggregator.jl:159 adds it to `ctx.meta[:objective]`, but the per-aggregator utility is available from `contribute!`'s return), `λ_j = extract_dlmp` row, `p_agj[t]` = the aggregator net injection.
- **DSO surplus** = negative value of DSO-OPT (3.47) = DADP revenue from prosumers minus MEM purchase cost:
  `DSO = Σ_j Σ_t λ_j[t]·value(p_agj[t]) − Σ_t λ_0[t]·value(p_import[t])`.
- **Social welfare** = `Pro + DSO`. **The `Σ_j λ_j·p_agj` transfer cancels**, leaving `Σ_j U_agj − Σ_t λ_0[t]·p_import[t]` = the **GLB-CVX objective (3.38)**. Therefore:
  ```
  ASSERT:  prosumer_surplus + dso_surplus ≈ objective_value(ctx.model)   (within rtol)
  ```
  This identity is the load-bearing correctness check for PRICE-03 — it catches a sign error or a dropped term in either surplus.

**FIT baseline (the one new solve):** FIT-OPT (3.24–3.28) is per-prosumer with PV + flexible loads but **NO battery** and **no network constraints**; then aggregate (3.22–3.23) and run a plain AC power flow (**no** voltage limits 3.35 — thesis step "AC-PF, observe 3.35 not enforced"). DSO benefit under FIT = `B_DSO` (4.1). Import/self-consume/export split (3.25–3.27) uses `max/min(P_pv, p_h)` — a small modeling addition (introduces the three FIT flows). German-FIT prices calibrated to the MEM band: `λ_im=6.6, λ_e=9.6, λ_s=5.6 ¢$/kWh` (thesis page 93).
```julia
"""
    welfare_accounting(ctx; baseline=nothing) -> NamedTuple

(social, dso, prosumer) surplus (PRICE-03), asserting social == prosumer + dso ==
objective_value(ctx.model) within rtol. If `baseline` is a solved FIT context, also
returns `ratio = social_DADP / social_FIT` (the +25% headline; thesis ≈ 1.25).
"""
```

### Pattern 4: PRICE-04 — economic-direction checks (reuse Phase-4 fixtures)
```julia
"""
    economic_direction_checks(ctx; λ₀) -> NamedTuple(pv_glut_ok, congestion_ok)

PV glut (build_high_pv_aggregators, allow_export=true): at over-generating node/hours the
DADP falls BELOW λ₀ (thesis Fig 4.5, node 9 @ 15:00). Congestion (build_ieee13_ground_
aggregators, head-branch S_max binds): DADP rises ABOVE λ₀ (thesis Fig 4.6, node 9 @ 22:00).
Throws on a backwards price signal (RESEARCH Pitfall 7 directional check).
"""
```

### Anti-Patterns to Avoid
- **Reading the DADP before the exactness gate.** `solve_welfare` already refuses prices on an inexact cone (exactness.jl); never bypass it by building your own solve without `assert_socp_exact!`.
- **Defining loss as the residual and calling it validated.** If you compute loss = `λⱼ − energy − congestion − voltage`, the sum-assertion becomes tautological and hides a dropped voltage/congestion term. Use strategy (B) — reconstruct each component independently and assert the sum — as the real check.
- **Hard-coding `λ₀` as the energy component.** Read it as `dual(balance_p[root,t])` and *verify* it ≈ `λ₀[t]` (they coincide only at optimum with the priced frontier); a mismatch flags a modeling bug.
- **Matching the thesis absolute welfare ($1819).** It is figure-bound (STATE Phase-4 follow-up). Pin the computed ratio + cross-check ≈1.25.
- **Re-solving to get λⱼ.** It's already a dual of the existing solve — no re-solve (except the FIT counterfactual).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Nodal marginal price | A finite-difference load-perturbation loop | `dual(ctx.constraints[:balance_p][j,t])` | JuMP already exposes the exact dual; perturbation costs N×T solves and is noisier |
| Voltage-limit shadow price | Manual re-derivation | `dual(UpperBoundRef(v[j,t]))` / `reduced_cost(v[j,t])` | JuMP attaches bound duals to the variable; `v` is in `ctx.meta[:pf_vars]` |
| Solve-status / exactness gating | New status checks | `assert_solved!` + `assert_socp_exact!` (run inside `solve_welfare`) | Already the single choke point; duplicating risks divergence |
| Radial path root→j | A graph library | Walk `feeder.branches` parent pointers (tree, N−1 branches) | Feeder is validated radial (`assert_radial`); path is a trivial parent walk |
| Solver selection for FIT-PF | Naming Clarabel/HiGHS | `select_optimizer(problem_class(pf))` | INFRA-02: no model names a concrete solver |
| Reproducible FIT scenario | Ad-hoc profiles | `generate_profiles(seed=...)` + `Phase4Fixtures` builders | Seeded, bit-for-bit reproducible (INFRA-04) |

**Key insight:** Every quantity Phase 5 needs is a dual or primal value of a model that is already built, solved, and gated. The engineering is *reading and attributing* duals correctly and *asserting* the two identities (decomposition sum, surplus sum) — not building anything numerical.

## Common Pitfalls

### Pitfall 1: Wrong-sign or misidentified DADP (RESEARCH Pitfall 7)
**What goes wrong:** JuMP's dual sign depends on the objective sense (this is a `Max`) and the constraint sense (`R_{p,j} == 0`). A sign flip makes charges look like credits — internally consistent, silently backwards.
**Why it happens:** The balance is written with the aggregator net *injection* (`p_inject − Pdc`, Aggregator.jl:154) and the branch inflow, not the thesis's `−p_agj` consumption form; the DADP sign must be pinned empirically, not assumed.
**How to avoid:** Hand-solve a **2-bus, single-period, lossless, uncongested** case (one load node behind a low-r branch, interior solution). The DADP must be **positive** and ≈ `λ₀` (energy only). Assert both sign and magnitude in a `@testitem`. Then the decomposition and economic-direction checks inherit the pinned sign.
**Warning signs:** DADP negative where positive expected; PV-glut price *above* λ₀ or congestion price *below* λ₀ (PRICE-04 would fail).

### Pitfall 2: Decomposition doesn't sum to the nodal price (missing term)
**What goes wrong:** Loss/congestion/voltage computed from the wrong dual, or the copy-drop (3.43) / cone (3.39) contribution dropped, so `energy+loss+congestion+voltage ≠ λⱼ`.
**Why it happens:** The exactness copy (`v̂`, 3.43/3.45) and the rotated-cone dual (3.39) both feed the loss/voltage split; forgetting one leaves a residual.
**How to avoid:** Implement strategy (B) (independent reconstruction) and assert the sum within a *relative* tolerance (mirror `assert_socp_exact!`'s scale-free `rtol` style, exactness.jl:78). On failure, report the per-node residual so the missing term is localizable.
**Warning signs:** A near-constant residual across nodes (a global term dropped) or a residual that grows with path depth (a per-branch term dropped).

### Pitfall 3: Trusting a DLMP from an inexact SOCP (RESEARCH Pitfall 1)
**What goes wrong:** If the SOC relaxation is strict, `l` is a fictitious over-current and the DADP is physically meaningless — but the solve is `OPTIMAL`.
**Why it happens:** High-PV / over-voltage regimes (exactly PRICE-04's PV-glut case) are where exactness can fail.
**How to avoid:** Only ever price a `ctx` produced by `solve_welfare` (which runs `assert_socp_exact!` before returning). For the PV-glut fixture use `allow_export=true` (the SOC-exactness enabler; fixtures_phase4.jl:141-155). Never construct a bespoke solve that skips the gate.
**Warning signs:** `ctx.meta[:socp_maxgap]` absent or large; decomposition that won't sum.

### Pitfall 4: FIT baseline definition drift (welfare gap)
**What goes wrong:** Matching the thesis's absolute social welfare ($1819) fails because MEM price / temperature / house-count inputs are figure-bound (STATE Phase-4 follow-up).
**Why it happens:** The thesis figures 4.2/4.5 are only plotted, not tabulated; the ground fixture uses documented calibrated scales (`GROUND_LOAD_SCALE`, fixtures_phase4.jl:192).
**How to avoid:** Pin the **computed ratio** `social_DADP/social_FIT` as the golden and cross-check ≈1.25 as an approximate magnitude — the exact Phase-4 pattern (computed golden + thesis cross-check). Document the FIT prices used (6.6/9.6/5.6 ¢$/kWh).
**Warning signs:** A plan that asserts a hard absolute welfare equality; a ratio wildly off 1.25 (that IS a real bug, unlike the absolute gap).

### Pitfall 5: Unit inconsistency in surplus / price (RESEARCH Pitfall 3)
**What goes wrong:** `λ₀`, device utility coefficients, and DADP must share one monetary unit; mixing ¢$/kWh and $/MWh scales a surplus by 10×/100×.
**How to avoid:** The Phase-4 fixtures already keep λ₀ in the same ¢$/kWh-consistent unit as the device coefficients (fixtures_phase4.jl:17-19). Reuse them; do not introduce a second price unit. Add a magnitude-sanity assert on surpluses and the ratio.
**Warning signs:** Ratio or surplus off by a clean power of ten.

## Code Examples

### Reading a per-node DADP and its energy component
```julia
# Source: src/models/welfare_solve.jl:213-214, src/models/oracle.jl:184
dlmp   = extract_dlmp(ctx)                    # (N, T)
root   = ctx.meta[:feeder].root
energy = [dual(ctx.constraints[:balance_p][root, t]) for t in 1:size(dlmp,2)]  # = λ₀ at optimum
```

### Reading a voltage-bound dual (voltage component input)
```julia
# Source: JuMP dual/reduced_cost on variable bounds; v is in ctx.meta[:pf_vars]
using JuMP
v = ctx.meta[:pf_vars].v
volt_dual_hi = dual(UpperBoundRef(v[j, t]))   # nonzero ⇒ over-voltage binds at (j,t)
volt_dual_lo = dual(LowerBoundRef(v[j, t]))   # nonzero ⇒ under-voltage binds
# (or: reduced_cost(v[j,t]) for the combined bound reduced cost)
```

### Surplus identity assertion (PRICE-03 correctness gate)
```julia
# Source: thesis eqs. 3.38/3.46/3.47, page 98
acc = welfare_accounting(ctx)
@assert isapprox(acc.social, acc.prosumer + acc.dso; rtol=1e-6)
@assert isapprox(acc.social, objective_value(ctx.model); rtol=1e-6)  # == GLB-CVX obj (3.38)
```

## State of the Art

Not a fast-moving domain — DLMP decomposition for the SOCP branch-flow model is settled theory. The one currency note:

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Generic AC-OPF Jacobian sensitivities for DLMP split | Radial branch-flow (DistFlow) recursion — path-telescoping duals | Farivar–Low / Gan–Low convexification (2013), Papavasiliou DLMP analysis (2018) | On a tree the decomposition is a simple parent-path sum, not a full Jacobian inverse — much simpler to implement and exact-by-construction |

**Deprecated/outdated:** none relevant. The thesis's own method (duals of the SOCP GLB-CVX) is the current standard.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact energy/loss/congestion/voltage **coefficient formulas** follow standard branch-flow DLMP theory (Papavasiliou 2018), because the thesis gives only a qualitative decomposition (Fig 4.5/4.6 text), not a numbered equation | PRICE-02 / Pattern 2 | If the thesis intended a different attribution, component *labels* could differ; MITIGATED because the sum-to-λⱼ assertion (Success Criterion #2) validates completeness regardless of attribution convention |
| A2 | DADP is **positive = marginal cost of consumption** under this model's sign conventions | PRICE-01 | A flipped sign inverts all price signals; MITIGATED by the mandatory 2-bus hand-solved regression |
| A3 | Social welfare = prosumer surplus + DSO surplus = GLB-CVX objective (the transfer terms cancel) exactly at an exact SOCP optimum | PRICE-03 | If loss terms in (3.47) break the cancellation, the identity assertion needs a documented loss-adjustment term; verify empirically on the 2-bus and IEEE-13 cases |
| A4 | The FIT baseline is thesis-faithful FIT-OPT (3.24–3.28, no battery) + a plain AC power flow (no 3.35), DSO benefit (4.1) | PRICE-03 / fit.jl | A reduced FIT counterfactual would change the +25% ratio; thesis-faithful is recommended for traceability |
| A5 | Congestion in the modified IEEE-13 arises only at the head branch (S_max,(0,1)=0.0686 pu); interior branches carry the no-limit sentinel | PRICE-02/04 | If a plan adds interior limits, more `smax` duals become nonzero — the decomposition already sums over all registered `smax` constraints, so it stays correct |

**If this table is empty:** it is not — A1 (the decomposition formula) is the one claim needing researcher/thesis confirmation of the *attribution convention*; the *sum* is self-validating.

## Open Questions

1. **Exact thesis attribution of the four DLMP components**
   - What we know: the thesis computes and plots DADPs (Fig 4.5/4.6) and attributes their spatial/temporal variation to "incremental losses" and "congestion" narratively (page 96); the standard branch-flow KKT decomposition gives energy/loss/congestion/voltage.
   - What's unclear: whether the thesis (or Palacios' defense notes) writes a specific closed-form component split, or leaves it at the standard theory.
   - Recommendation: implement the KKT/path decomposition, make the sum-to-λⱼ assertion authoritative, and (optional) skim the thesis Chapter 4 / the "Notas de Gemini" reference PDF for any explicit split before locking labels. Low risk — the sum validates completeness either way.

2. **Does the surplus-sum identity hold exactly, or with a loss remainder?**
   - What we know: algebraically the `Σ λ_j·p_agj` transfer cancels, giving social = objective (3.38).
   - What's unclear: whether the `−r·l` loss terms in the DSO settlement (3.47) leave a small residual distinct from the objective at the SOCP optimum.
   - Recommendation: assert `social ≈ objective` with a relative tolerance first; if it fails by a loss-sized amount, add the documented loss term and re-derive. Verify on the 2-bus (lossless) case first, then IEEE-13.

3. **Is the FIT AC power flow feasible/exact on the same fixtures?**
   - What we know: the thesis runs a plain AC-PF (not OPF) for FIT, deliberately without voltage limits.
   - What's unclear: whether to reuse `ConvexBranchFlow` (SOCP) with relaxed/removed bounds or a dedicated power-flow evaluation.
   - Recommendation: reuse `ConvexBranchFlow` with the voltage bounds relaxed to model the AC-PF, or fix the aggregator injections and solve a feasibility SOCP; keep it behind `select_optimizer`. Decide during planning.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItemRunner 1.1.5 + TestItems 1.0.0 (`@testitem` / `@testmodule`) [VERIFIED: test/Project.toml] |
| Config file | `test/runtests.jl` = `@run_package_tests` (discovers every `@testitem` under `test/` and `src/`) |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("pricing", ti.name)'` (or `"dlmp"`/`"welfare"` substrings) |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PRICE-01 | DADP = dual(balance_p), per node/hour, sign +ve ≈ λ₀ on 2-bus | unit | `@run_package_tests filter=ti->occursin("dlmp", ti.name)` | ❌ Wave 0 |
| PRICE-02 | 4 components sum to λⱼ (rtol), on IEEE-13 + high-PV | unit/integration | same `dlmp` filter | ❌ Wave 0 |
| PRICE-03 | social == prosumer+dso == objective; FIT ratio ≈ 1.25 | integration | `filter=ti->occursin("welfare", ti.name)` (new items; name-disambiguate from Phase-3 `test_welfare_solve.jl`) | ❌ Wave 0 |
| PRICE-04 | DADP<λ₀ at PV glut; DADP>λ₀ at congestion | integration | `filter=ti->occursin("pricing", ti.name)` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the matching-substring quick filter above (seconds — post-processing over a cached solve).
- **Per wave merge:** full `test/runtests.jl` (the pricing items add one IEEE-13 SOCP solve + one high-PV solve + one FIT solve; all small).
- **Phase gate:** full suite green + the two identity assertions (decomposition sum, surplus sum) passing before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_dlmp.jl` — PRICE-01 (2-bus sign) + PRICE-02 (sum-to-price on IEEE-13 & high-PV) `@testitem`s.
- [ ] `test/test_pricing_welfare.jl` — PRICE-03 surplus identity + FIT ratio (name chosen so `occursin("welfare",…)` still selects it, but distinct file from the Phase-3 `test_welfare_solve.jl`).
- [ ] `test/test_economic_direction.jl` — PRICE-04 directional checks reusing `Phase4Fixtures`.
- [ ] A tiny **2-bus lossless fixture** for the hand-solved DADP sign regression (can live inline in the testitem, mirroring `test_exactness.jl`'s self-contained 2-bus models).
- [ ] Reuse `setup=[Phase4Fixtures]` for the IEEE-13 / high-PV items (no new fixture module needed).

*(Framework already installed; no install step. Existing test infrastructure covers everything except the four new files above.)*

## Security Domain

`security_enforcement` maps here to **research integrity and reproducibility** (PITFALLS.md "Security Mistakes"), not web/authz. The applicable controls for a pricing post-processing phase:

| Concern | Applies | Standard Control |
|---------|---------|-----------------|
| V5 Input validation | yes | Throw-on-violation guards (project convention: `error`/`ArgumentError`, never `@assert` which `-O` elides) on shape mismatches (λ₀ length, node index range) |
| Reproducibility integrity | yes | FIT scenario via seeded `generate_profiles`; pin the computed ratio as a regression golden (EXP-04); log the git commit/seed with any reported welfare number |
| Correctness invariants (silent-wrong risk) | yes | The two identity assertions (decomposition sum, surplus sum) + exactness-gate reuse; these are the "catch wrongness with an automated invariant" controls PITFALLS.md mandates |
| Commercial-solver leakage | yes | FIT solve routes through `select_optimizer` (open-source Clarabel/HiGHS default); no Gurobi/Mosek in the default path |

No ASVS V2/V3/V4/V6 (auth/session/access/crypto) categories apply — this is an offline research library with no external interface.

## Sources

### Primary (HIGH confidence)
- `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf` — read printed pages 63–98 this session: device models (3.2–3.20), aggregation (3.21–3.23), FIT-OPT (3.24–3.28, page 81), branch-flow model (3.29–3.37, page 82), GLB-OPT/GLB-CVX (3.38/3.44, pages 83–84), AGR-OPT (3.46, page 85), DSO-OPT (3.47, page 86), Algorithm 1 (page 87), FIT B_DSO (4.1, page 93), Case A results incl. +25% social welfare / DSO/prosumer surplus definitions (page 98), DADP-vs-MEM narrative (Fig 4.5/4.6, page 96).
- `src/models/welfare_solve.jl`, `src/models/oracle.jl`, `src/models/exactness.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/core/ModelContext.jl`, `src/core/status.jl`, `src/devices/Aggregator.jl`, `src/devices/PVBattery.jl`, `src/data/ieee13.jl`, `src/data/profiles.jl`, `test/fixtures_phase4.jl`, `test/test_welfare_solve.jl`, `test/test_exactness.jl` — read this session; the exact seams Phase 5 consumes.
- `.planning/research/THEORY-thesis.md`, `.planning/research/THEORY-papers.md`, `.planning/research/PITFALLS.md`, `.planning/REQUIREMENTS.md`, CONTEXT.md, `.planning/config.json`, `.planning/STATE.md` — project context.

### Secondary (MEDIUM confidence)
- Branch-flow / DistFlow DLMP decomposition into energy/loss/congestion/voltage: Papavasiliou, "Analysis of Distribution Locational Marginal Prices," IEEE Trans. Smart Grid, 2018; Farivar & Low, "Branch Flow Model: Relaxations and Convexification," IEEE TPS 2013 (the convexification the thesis relies on). Verified via WebSearch 2026-07-18 that DLMP = Lagrange multiplier of the nodal active-power balance and its components map to duals of loss/congestion/voltage constraints — consistent with the KKT derivation above.

### Tertiary (LOW confidence)
- The precise *attribution labels* of the four components as (possibly) named in the thesis Chapter 4 body / defense notes — not located verbatim this session (thesis gives them qualitatively). Flagged as Open Question 1; the sum-assertion makes this non-blocking.

## Metadata

**Confidence breakdown:**
- DADP extraction (PRICE-01): HIGH — `balance_p` registered as a bus×time array (welfare_solve.jl:214); per-node per-hour is a direct `dual()` read, no Phase-4 change.
- DLMP decomposition (PRICE-02): MEDIUM — derivation is standard branch-flow KKT and self-validating via the sum-to-λⱼ assertion, but the thesis gives no closed-form equation and two constraint handles must be newly registered.
- Welfare accounting (PRICE-03): HIGH on definitions/identity (thesis 3.38/3.46/3.47/4.1, page 98); MEDIUM on the FIT baseline effort (the one genuinely new solve) and on matching the thesis absolute welfare (figure-bound → use ratio).
- Economic-direction checks (PRICE-04): HIGH — fixtures exist (`build_high_pv_aggregators`, `build_ieee13_ground_aggregators`) and the expected directions are stated in thesis Fig 4.5/4.6.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 (stable — thesis math and pinned Julia stack do not drift; re-verify only if the Phase-4 `ConvexBranchFlow`/`welfare_solve` seams change)
