# Phase 44: Aggregator as Actor - Research

**Researched:** 2026-11-02
**Domain:** Julia/JuMP transactive-energy bench: per-actor objective, slot-keyed ADMM consensus, wrapper-device behavioural scenarios, settlement
**Confidence:** HIGH on code facts (all read in this session, file:line cited), MEDIUM on behavioural-baseline design (needs one decision, see Open Questions)

All code citations below were read directly in this session and tagged `[VERIFIED: codebase]` unless marked otherwise. No external packages are added by this phase (pure in-repo Julia), so the Package Legitimacy Audit is "none".

<user_constraints>
## User Constraints (from CONTEXT.md, copied verbatim in substance)

### Locked Decisions
**Profit Objective & Wedge (ACTOR-01/02)**
- Where the objective lives: new `AbstractActorObjective` hierarchy, `WelfareObjective` default and `ProfitObjective(wedge)`. Selected per aggregator or actor through an additive keyword on `solve_admm` and `solve_welfare`. NOT a field on `Aggregator`, NOT a new `AbstractStrategy`. The welfare objective must leave the AGR build bit-identical: the accumulator `===` `ctx.objective`.
- The wedge: additive retail margin `m_t` (scalar or hourly vector). Customers' devices respond to `λ + m`, a linear term on `pag`, so the problem stays convex and the per-iteration ADMM lever is unchanged. Aggregator profit `Σ_t m_t · load_t` is reported. With `m = 0` the problem is exactly the welfare problem. Document honestly: a weighted objective inside the same price-taking equilibrium, not a strategic aggregator (no market power, no Stackelberg).
- Efficiency loss: `ΔW = W_opt − W_social(profit dispatch)`, absolute and relative. `W_social` always from device utilities − `λ₀ᵀp_import`. Actor profit is a separate line in the Phase-41 `SettlementLedger`.
- Pass-through test: `ProfitObjective(m = 0)` reproduces the welfare optimum on BOTH centralized and ADMM paths, within a MEASURED tolerance. Centralized side gets an objective hook through a new keyword; default path stays bit-identical. Each non-default objective is cross-validated centralized-vs-ADMM before ADMM use (DEV-10 pattern, Phase 43).

**Multi-Bus Portfolio (ACTOR-03)**
- Grouping only: an `Actor`/`Portfolio` is a set of ordinary single-bus site `Aggregator`s. `Aggregator` stays single-bus (`agg.bus` is the sole `:Rp/:Rq` writer). ADMM coupling axis becomes a SLOT keyed by (actor, bus): one consensus pair `(pag_s, pag_dso_s)` per slot. `PortfolioAgrOpt` (ACTOR-F2) deferred.
- Several actors per bus allowed; all slots inject into that bus's `:Rp` and share its nodal price. DADP still published per bus, shape `(n_load_nodes, T)` ascending. New slot-λ agreement certificate (`max_s |λ_s − λ_bus| ≤ tol`) reports, never throws. Per-slot λ exposed additively.
- Byte-identity: legacy `Vector{Aggregator}` input with no actors runs the unchanged code path; existing ADMM goldens untouched. New bitwise test: "each site is its own actor" equals legacy. In the 1:1 case slot id equals bus id. Legacy guard error messages stay on the legacy path.
- Objective attachment at actor level; same wedge applies to all of the actor's sites; profit summed per actor in the ledger; no per-site override.

**Behavioural Scenarios (ACTOR-04)**
- Wrapper devices (`PartialCompliance`, `OptOut`, `Rebound`) satisfying the existing device contract, applied once by a seeded opt-in population transform `BehaviourSpec(; compliance, opt_out, rebound, seed)`. No binaries, nothing changes inside the solves. SplitMix64 seeding as in `_flex_mix`, NOT `Base.hash`.
- Partial compliance ξ ∈ [0,1]: device follows fraction ξ of its deviation from a no-response baseline; baseline from the existing FIT counterfactual (`fit_baseline`), computed once at transform time, never in the loop. Opt-out: seeded fraction of houses fixed to that baseline (exogenous; endogenous is ACTOR-F3).
- Rebound: convex linear energy-recovery constraint: energy curtailed relative to baseline recovered within window `W` at factor `r ≥ 1`. Phase-41 `rebound` metric also reported.
- Reporting: sweep harness over (ξ, opt-out, r) on one fixture writing a committed CSV (welfare, DADP mean and max, ledger totals per actor, rebound metric) and a literate docs page (Phase 35/39/40 measurement-artifact pattern).

**Validation, Fixtures & Integration**
- IEEE-13 for unit/pass-through/cross-validation; IEEE-123 for the behavioural sweep; `:case_a_784` only centralized measurement if at all (ADMM ~900 s per rung).
- Centralized `solve_welfare` and `solve_admm` support actors/objectives/behaviour. MPC, stochastic and FIT reject non-default inputs with an `ArgumentError` guard mirroring `_reject_unsupported_flex_devices` (`src/pricing/fit.jl:80`).
- `Scenario` stays untouched; programmatic API only.
- Welfare honesty: every new result carries `welfare` (social), the actor objective value as a separate field, and `ΔW` vs the welfare optimum. A test asserts profit-dispatch social welfare ≤ welfare optimum (violation = impossible, PITFALLS C7).

### Claude's Discretion
Module/file layout (e.g. `src/admm/actor_objective.jl`, `src/actors/`), slot-table data structure, exact keyword names, CSV columns, sweep grid values, within established patterns.

### Deferred Ideas (OUT OF SCOPE)
ACTOR-F1 tariff-menu/strategic aggregator; ACTOR-F2 `PortfolioAgrOpt`; ACTOR-F3 endogenous participation equilibrium; additive `Scenario` fields for actors/behaviour; house-level slot granularity (`granularity = :house`).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACTOR-01 | Choose per aggregator social-welfare (default, unchanged) vs profit-with-wedge | §Wedge math; `agr_objective` + `agr_linear_offset` hook; `solve_agr!` overwrite trap (§Pitfall 1); centralized hook in `solve_welfare` |
| ACTOR-02 | Zero wedge reproduces welfare (pass-through); non-zero wedge reports efficiency loss; `welfare` stays social | §Wedge math (ADMM pass-through is bitwise by construction; centralized measured); §Welfare recompute (M4 avoided by construction) |
| ACTOR-03 | Multi-bus portfolio, consensus keyed by (aggregator, bus), single-bus byte-identical | §Slot-table design; §1:1 inventory; key insight: multi-bus portfolios with distinct buses need NO slot code, slots only for several-actors-per-bus |
| ACTOR-04 | Seeded partial compliance / opt-out / rebound with welfare, price, settlement effects reported | §Behavioural wrappers; §Settlement integration; §Sweep harness |
</phase_requirements>

## Summary

The phase is mostly additive plumbing around three seams that already exist. The AGR objective is `ctx.objective − 0.5ρΣpag²` built once (`src/admm/AgrOpt.jl:173,189`); the per-iteration lever is a single `set_objective_coefficient(model, pag[t], −λ−ρc)` (`AgrOpt.jl:312`). The centralized path already keeps each aggregator's net injection expression (`welfare_solve.jl:194-200`) and the objective `ctx.objective − λ₀ᵀp_import` (`welfare_solve.jl:242`). The retail wedge is a linear term `m_t·pag_t`, so the equilibrium ADMM converges to is exactly `max Σ_s[U_s + m_s·pag_s] − λ₀ᵀp_import` over the unchanged feasible set. Social welfare is recomputed from `value(ctx.objective)` (utilities only) minus `λ₀ᵀp_import` on both paths, so the actor objective never leaks into `welfare` (M4 handled structurally, not by reconciliation).

**Two research findings change the recommended design versus the ARCHITECTURE.md sketch.**
1. `agr_objective(obj,U,pag,T)` alone is NOT enough on the ADMM path: `solve_agr!` calls `set_objective_coefficient(pag[t], −λ−ρc)` every iteration, which OVERWRITES any linear `m_t` baked into the built objective. Verified in a scratch JuMP/Clarabel run (baked coefficient 3, overwritten to 1, optimum x=1). The margin must be stored on the `AgrOpt` and added inside the coefficient update.
2. A multi-bus portfolio whose sites sit on DISTINCT buses is already legal under the legacy 1:1 path. The slot table is only required when two sites share a bus (several actors per bus). That lets the plan land ACTOR-01/02/03-grouping with zero ADMM structural risk, then isolate the slot generalisation in its own wave.

A third finding affects ACTOR-04: `fit_baseline` does NOT expose a per-device baseline (it returns per-aggregator `fit_flows`, drops the battery, runs a nested AC-PF and rejects EV/HeatPump/SmartInverterPV). A per-device no-response baseline must come from a small single-device solve at the FIT flat price (reusing the `price_taker_dispatch` shape). This is a deviation from the CONTEXT wording and needs planner/user confirmation (Open Question 1).

**Primary recommendation:** Four waves: (1) actor objective + `Portfolio` + centralized hook + ADMM wedge via stored offset + pass-through/ΔW tests; (2) slot-table ADMM generalisation, new-path-only, proven by bitwise "each site its own actor == legacy" plus split-bus equivalence; (3) behavioural wrappers + `BehaviourSpec` + per-device baseline + guards (can run in parallel with wave 2, disjoint files); (4) settlement actor-profit line + slot-aware adapters + sweep script/CSV + literate page + exports/docs/JET.

## Architectural Responsibility Map

(Julia research bench, no browser/CDN tiers; tiers mapped to the framework's own layers.)

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Actor objective type + wedge term | Model layer (`src/actors/` or `src/admm/`) | — | Pure value types; consumed by both solve paths |
| Centralized profit hook | Centralized solve (`solve_welfare`) | — | Already holds `agg_net` expressions; no `Aggregator` edit needed |
| ADMM wedge | AGR-OPT subproblem (`AgrOpt`/`solve_agr!`) | — | Per-iteration lever lives here; DSO block is unaware of m |
| Slot table / consensus keyed by (actor, bus) | ADMM orchestration (`_admm_build`, `AdmmState`) | DSO-OPT (`build_dso_opt`) | Coupling axis is owned by both blocks |
| Portfolio grouping | Population/actor layer | Settlement | Grouping only; physical roll-up stays single-bus `Aggregator` |
| Behavioural wrappers | Device layer (`src/devices/`) | Population transform (`materialize.jl`) | Must satisfy the `contribute!` contract; seeded at build |
| Per-device baseline | Population transform (one-off solves) | — | Computed once, never in the loop |
| Actor profit line, ΔW report | Settlement layer (post-solve accounting) | Reporting script | Pure accounting; ledger conservation untouched |
| Sweep CSV + docs | Scripts + docs | — | Phase 35/39/40 artifact pattern |

## Standard Stack

No new libraries. Everything uses the project stack already pinned in `Project.toml` (JuMP, Clarabel via `select_optimizer(QP()/SOCP())`, DataFrames/CSV for the sweep artifact, StableRNGs already used by `_flex_trunc_normal`). Do not add packages.

### Package Legitimacy Audit
Not applicable: no external package is installed by this phase. `Packages removed: none. Packages flagged: none.`

## Architecture Patterns

### System Architecture Diagram

```
 Researcher inputs
   Vector{Portfolio} (sites::Vector{Aggregator}, objective)   BehaviourSpec(ξ, opt_out, rebound, seed)
        |                                                          |
        |                                         apply_behaviour(aggs, spec; T) -> wraps devices once
        |                                         (per-device baseline solve, SplitMix64 opt-out draw)
        v                                                          v
   _expand_actors(portfolios) -> flat Vector{Aggregator}, per-site objective, SlotTable
        |
        +--> solve_welfare(...; actors=)  [centralized]
        |      contribute!(site) x k  -> agg_net[k].net (AffExpr)
        |      welfare_expr = ctx.objective - λ0'p_import  (+ Σ m·net only if non-default)
        |      result: ctx (ctx.meta[:actor] = social W, actor obj value, profit per actor)
        |
        +--> solve_admm(...; actors=)     [decomposed]
               legacy branch (actors === nothing): code UNCHANGED
               slot branch (several sites/bus):  SlotTable(slot id, bus, actor)
                 AGR-OPT[s]  coeff = -λ_s - ρ c_s + m_s[t]       (offset stored on AgrOpt)
                 DSO-OPT     pag_dso[s,t] -> :Rp[bus(s)]
                 dual ascent per slot; DADP published per BUS; slot λ agreement cert (report only)
        |
        v
   social welfare = Σ util - λ0'p_import (recomputed from utilities)  |  ΔW = W_opt - W_social
   settlement_input (slot-aware, sums per bus) -> build_settlement_ledger(...; actor_wedges=)
   -> actor profit line (conserving mirror rows) -> rebound(baseline_net_load, scenario_net_load)
   -> sweep CSV + literate page
```

### Recommended Project Structure
```
src/
├── actors/
│   ├── actor_objective.jl   # AbstractActorObjective, WelfareObjective, ProfitObjective, agr_objective, agr_linear_offset
│   ├── Portfolio.jl         # Portfolio (NOT `Actor`: name taken, see Pitfall 7), SlotTable, _expand_actors
│   └── efficiency.jl        # actor_efficiency / ΔW helper, social_welfare(ctx)
├── devices/
│   └── Behavioural.jl       # PartialCompliance, OptOut, Rebound + trait forwarding (after CapabilityTraits.jl)
├── experiments/materialize.jl   # BehaviourSpec + apply_behaviour + _device_baseline (next to build_population)
scripts/actor_behaviour_sweep.jl     # IEEE-123 sweep -> results/actor_behaviour/*.csv
docs/literate/aggregator_actor.jl    # registered in docs/make.jl and scripts/README.md
test/test_actor_objective.jl  test/test_actor_portfolio.jl  test/test_behaviour.jl
test/test_actor_settlement.jl test/test_actor_sweep.jl (slow)
```
Include order: `src/actors/actor_objective.jl` must precede `src/admm/AgrOpt.jl` (include list `src/TSODSO.jl:211`); `devices/Behavioural.jl` after `devices/CapabilityTraits.jl` (`TSODSO.jl:136`) and before `Aggregator.jl`; `Portfolio.jl` before `models/welfare_solve.jl` (`TSODSO.jl:146`).

### Pattern 1: Wedge math and what ADMM converges to (answers focus item 1)

Sign conventions (read from code): `pag = Σ p_inject − Pdc` is net INJECTION (`AgrOpt.jl:161`, `Aggregator.jl:238`), load negative. Internal multiplier `λ_int = −DADP` (`admm_phases.jl:86,462`); the AGR coefficient on `pag` is `−λ_int − ρc = +DADP − ρc`, so exporting earns DADP. A customer facing retail price `DADP + m_t` has marginal value `DADP + m_t` per unit of `pag` (a symmetric additive tariff offset: the same `m` applies to exports, document it; aggregator profit is `−Σ m_t·pag_t`, positive on net load).

ADMM block objectives become:
- AGR_s: `max U_s + Σ m_s,t·pag_s,t − Σ λ_s,t pag_s,t − ρ/2 Σ (c+pag)²` i.e. coefficient `−λ_int − ρc + m_t` (new term `+m_t`).
- DSO: unchanged (it sees DADP only).

At a consensus fixed point the multipliers are the nodal duals and the AGR optimum is the maximizer of the centralized problem

    max  Σ_s [ U_s(x_s) + Σ_t m_s,t · pag_s,t ]  −  Σ_t λ₀,t · p_import,t     s.t. the unchanged network + device constraints.

Social welfare at that dispatch is `W_soc = Σ_s U_s − λ₀ᵀp_import`; `W_opt` is the `m = 0` optimum over the SAME feasible set, so `W_soc ≤ W_opt` always (x_profit is feasible for the welfare problem). `ΔW = W_opt − W_soc ≥ 0`, and for smooth strictly concave `U` it is O(m²) (A4, to be measured), while profit `−Σ m·pag` is O(m). Constant offsets: `pag` contains the literal `−Pdc` (`Aggregator.jl:238`), so `Σ m·net` carries a constant `−Σ m·Pdc`; therefore the reported actor objective value includes it while `W_soc` never does because `W_soc` is recomputed from `value(ctx.objective)` (utilities only; the wedge is added to a separate local expression, never to `ctx.objective`). Never report `objective_value` as welfare for a non-default objective.

### Pattern 2: Hook placement (answers focus item 1)

```julia
# src/actors/actor_objective.jl
abstract type AbstractActorObjective end
struct WelfareObjective <: AbstractActorObjective end
struct ProfitObjective{M} <: AbstractActorObjective
    wedge::M          # Real or AbstractVector{<:Real} (hourly); validated to length T at use
end
# static part of the AGR objective: WelfareObjective returns U itself (===) => build bit-identical
agr_objective(::WelfareObjective, U, pag, T) = U
agr_objective(::ProfitObjective, U, pag, T) = U            # margin is NOT baked in (solve_agr! overwrites linear coeff)
# per-iteration linear offset consumed by solve_agr!
agr_linear_offset(::WelfareObjective, T) = nothing
agr_linear_offset(o::ProfitObjective, T) = _wedge_vec(o.wedge, T)   # Vector{Float64}
# centralized: additive term built from the already-captured net expressions
wedge_term(::WelfareObjective, net, T) = nothing
wedge_term(o::ProfitObjective, net, T) = sum(m[t] * net[t] for t in 1:T)
```
- `build_agr_opt(...; objective = WelfareObjective())` (`AgrOpt.jl:134-141`): line 173 becomes `obj_expr = agr_objective(objective, ctx.objective, pag, T) - 0.5*ρ*sum(...)`. For `WelfareObjective` that is the same object, so the built objective is unchanged. Store `agr_linear_offset(objective, T)` in a NEW `AgrOpt` field (struct is only constructed inside `build_agr_opt`, `AgrOpt.jl:191`; safe to add a trailing field).
- `solve_agr!` (`AgrOpt.jl:311-316`): `coef = -λ_j[t] - ρ*c_j[t]; agr.linear_offset === nothing || (coef += agr.linear_offset[t])`. Legacy branch performs no extra float op, so default is bitwise identical.
- ADMM pass-through is bitwise by construction: `x + 0.0 == x` in IEEE-754, so `ProfitObjective(0)` through `solve_agr!` produces the identical coefficients and the identical trajectory. Assert `==` on `welfare`, `dadp`, `iters` for ADMM; this is stronger than a measured tolerance and is the right liveness anchor for the ADMM hook. (It does not prove the profit term does anything: the non-zero-m test below does.)
- Centralized (`solve_welfare`): do NOT edit `Aggregator.contribute!`. After the loop at `welfare_solve.jl:194-199`, add `welfare = ctx.objective - Σλ₀p_import` (line 242 unchanged) and, only when some objective is non-default, `welfare += Σ_k wedge_term(obj_k, agg_net[k].net, T)` before `@objective`. CONTEXT says "hook on `Aggregator.contribute!` through a new keyword"; the `agg_net` expressions make that unnecessary and keep `Aggregator.jl` untouched. Centralized pass-through with explicit zero coefficients is NOT bitwise (zero-coefficient terms still change the MOI objective sparsity); assert within a MEASURED tolerance (measure 3 seeds, take 3x observed max per the repo pattern). Do not short-circuit all-zero wedges, or the test becomes vacuous.
- Result fields: `solve_welfare` returns a 3-tuple destructured everywhere, so do not change it. Stash `ctx.meta[:actor] = (; social_welfare, actor_objective_value, profit_by_actor, retail_wedge)` only when non-default; add `social_welfare(ctx)` helper `= value(ctx.objective) - Σ λ₀ value(p_import)` (needs λ₀ from the caller or stash). For ADMM add an `actor` key to the result NamedTuple on the non-default path only (the default NamedTuple key set and order must not change; `test_strategies.jl:218` only checks `:iters` but goldens fold results).

### Pattern 3: Slot table (answers focus item 2)

Minimal, new-path-only design:

```julia
struct SlotTable
    ids::Vector{Int}                 # ascending slot ids
    bus::Dict{Int,Int}               # slot id -> bus
    actor::Dict{Int,Int}             # slot id -> portfolio index
    site::Dict{Int,Int}              # slot id -> index into flat site vector
end
```
- Slot id rule: the FIRST site (in portfolio order) at a bus gets `id = bus`; further sites at the same bus get `N + k` (N = `length(feeder.buses)`), deterministic. Then in the 1:1 case `ids == load_nodes` ascending and every dict/loop is the same object sequence as legacy (satisfies "slot id equals bus id").
- Legacy branch literally unchanged: `solve_admm(feeder, pf, aggregators; ...)` with `actors === nothing` runs the current `_admm_build` guards (`admm_phases.jl:61-81`, messages preserved). A slot branch is taken only if `actors` is given AND (a bus has >1 site); a portfolio set with all-distinct buses is flattened and routed through the legacy branch (still correct, still bitwise).
- Because `slot id == bus id` for the first site, the identity case flows through the SAME generalized code with `slot_bus = identity`; prove with a bitwise test that the slot branch forced on the 10-aggregator IEEE-13 population equals legacy on `welfare`, `dadp`, `iters`, the full residual traces and `agr_*` keys.

Every 1:1 baked assumption (all `[VERIFIED: codebase]`):

| Location | Assumption | Slot-branch change |
|----------|-----------|--------------------|
| `admm_phases.jl:61-67` | `length(aggregators) == length(load_nodes)` | replace by slot-table well-formedness; legacy message stays on legacy path |
| `admm_phases.jl:68-81` | `agr_by_bus[agg.bus]`, duplicate-bus throw | key by slot id; build via `build_agr_opt(site; objective)` |
| `admm_phases.jl:87-95` | λ, c, a, pag_dso_prev, util keyed by `load_nodes` | keys = slot ids (works unchanged once `load_nodes = slot ids`) |
| `admm_phases.jl:157-159` | `set_rho!` loop over `st.load_nodes` | unchanged (slot ids) |
| `admm_phases.jl:330` | `p_p = length(load_nodes)*T` | counts slots automatically if `load_nodes` = slot ids; equals legacy when 1:1 |
| `admm_phases.jl:415-417` | `has_4q_by_bus` keyed by `agg.bus`, indexed `[j]` in `_agr_solve_step!` (`:207,234`) | MUST key by slot id (else KeyError for extra slots) |
| `admm_phases.jl:459,462` | welfare sums `util[j]`; `λ_mat` rows per `load_nodes` | welfare unchanged (sum over slots); `λ_mat` must be one row PER BUS (primary slot or mean) + per-slot `λ_slots` additive key + agreement cert |
| `admm_state.jl:96-115` | `AdmmState` positional 18 fields; `agr_by_bus::Dict{Int,AgrOpt}` | keep field name; carry slot_bus in a trailing field WITH an 18-arg outer constructor: `scripts/profile_ieee8500_memory_attribution.jl:209` builds `AdmmState` positionally |
| `admm_state.jl:451-452` | `agr_by_bus[j].ctx.agg_device_vars[j]` (inner key is `agg.bus`, not slot id) | index inner dict with `slot_bus[j]` on slot path (LIVE reactive 4Q publish) |
| `admm_state.jl:480-494` | `_agr_result_keys` keyed by load_nodes = "buses" | keyed by slot id on slot path + `slot_bus`/`slot_actor` result keys |
| `DsoOpt.jl:303-313` | aggregator bus range/root guards | keep (apply per site bus) |
| `DsoOpt.jl:366-368` | `load_nodes = sort(Set(agg.bus))`, `transit_nodes` from bus set | `transit_nodes` from bus set unchanged; `load_nodes := slot ids` |
| `DsoOpt.jl:372-385` | `q_draw` per bus, summed over aggregators at the bus | per slot (each site's own `−Pdc·tanφ`); identical when 1:1 |
| `DsoOpt.jl:419-422` | `pag_dso[j,t]` into `:Rp[j]` | `pag_dso[s,t]` into `:Rp[bus(s)]` |
| `DsoOpt.jl:428-459` | OFF: `Rq[j] += q_draw[j]`; CERTIFIED/LIVE `qag_dso[j,t]` per j | per slot, inject at `bus(s)` |
| `DsoOpt.jl:483-489,716-760` | penalty/`set_rho!` loops over `load_nodes` | unchanged (slot ids) |
| `DsoOpt` struct (10 positional fields) | built positionally in `test/test_admm_exactness_default.jl:45` | do NOT add a field; store `slot_bus` in `dso.ctx.meta[:slot_bus]` |
| `solve_admm.jl:313-336` | signature | additive kwargs `actors = nothing`, (`objectives` via portfolios) |
| `run_inputs.jl:243-295` | ADMM adapter treats `keys(agr_dispatch)` as buses and aligns `dadp` rows by `enumerate(buses)` | slot-aware branch: sum nets/utilities per bus, price row per bus |
| `run_inputs.jl:133-151` | centralized adapter `bus_nets[b] = ...` OVERWRITES when two entries share a bus; `issorted` passes duplicates | sum per bus on the multi-site path (silent-drop bug otherwise) |
| `SettlementLedger.jl:215-226` | ledger requires unique ascending buses | feed per-bus summed inputs |
| `comparison.jl:278-282` | `compare_tariffs` rejects shared buses | out of scope; sweep script must not use `compare_tariffs` (see Pitfall 6) |

Parallel executor: `_agr_solve_step!` and `_react_agr_solve_only` loop `st.load_nodes` (`admm_phases.jl:202-262`), so slot ids work without change; join order stays ascending slot id (document: with extra slots N+k the order is primary slots then extras, still deterministic).

DSO-side math with two slots at one bus: stationarity gives `β_bus = λ_s` for every slot at consensus, so all slot multipliers agree and equal −DADP; the per-slot penalty is strictly convex so the nodal total is split uniquely. Published `dadp` row for a bus = its primary slot's `−λ` (or the slot mean, pick one and test); agreement certificate `max_s|λ_s − λ_bus|` is REPORTED (status policy), never thrown.

Centralized side with several aggregators per bus (answers focus item 3): ALREADY SUPPORTED. `solve_welfare` loops `contribute!` per aggregator (`welfare_solve.jl:195-199`); `add_to_residual!` accumulates into the same `:Rp[bus]` (`Aggregator.jl:238-239`); the `Pdc_param` is anonymous so no name collision (`Aggregator.jl:178-189` comment, "multi-aggregator" case); `agg_device_vars`/`agg_device_types` are appended in lockstep per bus (`Aggregator.jl:229,246`) so certificates still pair. `dadp` is read at `aggregators[1].bus` (`welfare_solve.jl:293`). The only gap is downstream: `settlement_input(ctx)` overwrite (table above). DsoOpt build already tolerates several aggregators per bus (set + summed `q_draw`, `DsoOpt.jl:366-385`); only the ADMM guards forbid it.

### Pattern 4: Behavioural wrappers (answers focus item 4)

Contract (`AbstractDevice.jl:25-39`): `contribute!(dev, ctx; T)` returns `(; vars, p_inject, utility[, q_inject])`, writes nothing to residuals/objective. Aggregator treats the return generically (`Aggregator.jl:198-230`), derives the flexible-load reactive draw from the RETURNED `p_inject` (`:215-221`) and reads `d.φ` via `hasproperty(d,:φ) && d.φ !== nothing` (`:216`).

Wrapper semantics (each is exact in expectation for a population / Bernoulli(ξ) compliance draw):
- `PartialCompliance{D}(inner, ξ, b, Ub)`: `res = contribute!(inner)`; `p' = b + ξ(p − b)`; `U' = (1−ξ)·Ub + ξ·U` where `b` is the baseline `p_inject` vector and `Ub` the inner utility at the baseline. The inner device still optimizes `ξ[U + Λp] + const`, i.e. its own optimum `x*(Λ)`; the realized deviation is damped by ξ. Both `E[p']` and `E[U']` are exact for a population share ξ complying, so no Jensen caveat is needed under that interpretation (flag as A2 for user confirmation). Pitfall: ξ = 0 leaves inner vars unconstrained by the objective (degenerate, arbitrary x triggers certificates); route ξ = 0 to `OptOut`, require ξ ∈ (0,1] for `PartialCompliance`.
- `OptOut{D}(inner_type_info, b, Ub)`: no variables; `p_inject = b` (constants as `AffExpr`), `utility = Ub` (constant `QuadExpr`), `vars = (;)`. `storage_kind` must be `:none` (type-level) so certificates skip it.
- `Rebound{D}(inner, b, W, r)`: on the wrapped (possibly already compliance-damped) injection `p'`, consumption `c_t = −p'_t`, baseline `c^b_t = −b_t`. Add `u_t ≥ 0`, `u_t ≥ c^b_t − c_t`, and `Σ_{τ=t+1}^{min(t+W,T)} (c_τ − c^b_τ) ≥ r·u_t`. This is LP-representable and exact (curtailment `u_t=(c^b−c)^+` is convex, recovery is affine; affine ≥ convex defines a convex set). The baseline `c = c^b` is always feasible (u=0), so the constraint never makes the device infeasible; near the horizon end curtailment simply cannot be recovered and is forced to 0 (document: window clipped at `T`, no wrap). Returns `vars = merge(inner.vars, (; rebound_u = u))` when `vars isa NamedTuple`.
- Composition order: `Rebound(PartialCompliance(inner))` is the recommended stack so rebound acts on realized power.

Trait forwarding (must be written; defaults are wrong for wrappers): `is_flexible_load`, `has_reactive_decision` (`AbstractDevice.jl:84,109`) forward to the inner; `storage_kind(::Type{<:PartialCompliance{D}}) where D = storage_kind(D)` (type-level, mirrors `CapabilityTraits.jl:30-35`), `OptOut` → `:none`; expose `φ` (forward the inner's `φ` field via a field or `getproperty`, else `Aggregator.jl:216` silently falls back to `agg.φ`, changing reactive draw). Restrict wrapping to active-only devices without `q_inject` (reject `FourQuadBESS`, `SmartInverterPV`, `FixedCapacitor` with `ArgumentError`).

`isa` checks that wrappers hide (all must be made wrapper-aware or guarded): `fit.jl:83` (EV/HP/SIPV guard), `fit.jl:124` (`PVBattery`), `admm_phases.jl:416` (`FourQuadBESS`), `materialize.jl:699` (`PVBattery`), `mpc_loop.jl:298,533-639`. Recommended: add the three wrapper types to the Union in `_reject_unsupported_flex_devices` (`fit.jl:83`), which already guards `fit_baseline` (`fit.jl:118`) and `run_mpc` (`mpc_loop.jl:292`), plus an equivalent `ArgumentError` at the stochastic aggregator-taking entry points. `compare_tariffs` runs the `:fit` leg and lets `ArgumentError` propagate, so wrapped populations cannot use `compare_tariffs`.

Baseline (focus item 4, important): `fit_baseline` returns `(; ctx, social_fit, welfare, ratio, prosumer_surplus, fit_flows, socp_maxgap, ac_status, ac_violations)` (`fit.jl:372-397`). `fit_flows` is PER-AGGREGATOR `(Ppv, p_h, self, imp, exp, net)` (`fit.jl:253-263`), no per-device profile; the FIT-OPT DROPS the battery storage (`fit.jl:123-136`) and rejects EV/HeatPump/SmartInverterPV (`fit.jl:118`), and each call runs a nested `solve_welfare` plus an Ipopt AC-PF on the whole feeder. So a per-device baseline is NOT recoverable from it. Recommended replacement (Open Question 1): `_device_baseline(d, T; price = FIT_λ_IMPORT)` = one tiny QP per device via the `price_taker_dispatch` shape (`price_taker.jl:101-117`: `Model(select_optimizer(QP()))`, `contribute!`, `Max ctx.objective + price·Σp_inject`, no ρ term), returning `b = value.(p_inject)` and `Ub = value(utility)`. This keeps the FIT price constant (`fit.jl:34`) so it stays "the FIT counterfactual" in spirit, is per-device, includes batteries/EV/HP, runs once at transform time. Hazards: (i) flat price makes storage arbitrage degenerate and interior-point solutions can co-activate charge/discharge (documented at `price_taker.jl:27-33`) so default `BehaviourSpec` wraps only flexible loads (`is_flexible_load(d)`, HeatPump, EV), storage opt-in; (ii) EV charging under a flat price is non-unique, so add a deterministic tie-break (tiny time-ordered cost) or assert uniqueness; the baseline must be reproducible.

Seeding (focus item 4): `_flex_mix(vals::Integer...)` is SplitMix64 (`materialize.jl:557-566`), integer tags only (`:568-574`). Add `_BEH_TAG_OPTOUT = 21`, draw `u = rand(StableRNGs.LehmerRNG(_flex_mix(seed, _BEH_TAG_OPTOUT, bus, device_index)))` and opt out iff `u < opt_out`. Per-device unit, not per-house, because `:default` has ONE house per bus aggregator and the `:case_a_784` bus aggregator concatenates house devices (`materialize.jl:845-853`) so house boundaries are positional only; the Phase-40 `case_a_household_map` (`materialize.jl:988-1031`) gives house→bus/house_index but not device→house. For IEEE-123 (`:default`, 85 load buses) per-device opt-out is the natural granularity (state it in docs; house-level grouping is a discretion extension for `:case_a_784`). Default `BehaviourSpec()` (ξ=1, opt_out=0, no rebound) must return its input `===` (byte-identity fence).

### Pattern 5: Settlement integration (answers focus item 5)

`build_settlement_ledger` (`SettlementLedger.jl:191-457`) takes per-bus `prices`, `bus_nets`, `bus_utilities`; flows are adjacent mirror pairs via `_push_transfer_pair!` (`:105-130`) so the sequential fold is exactly 0.0 (`:392-399`, `ledger_residual :472-478`). `Actor = Union{Symbol,Tuple{Symbol,Int}}` (`:37`).
- Add an additive keyword `actor_wedges = nothing` (a vector of `(; actor_id, bus, m, load_net_bus_share)`; simplest: per site `(; actor, bus, m::Vector, net::Vector)`), appended AFTER flow (c). For each site and hour push `_push_transfer_pair!(transfers, (:actor, id), (:aggregator, bus), t, m_t, −net_t)`: positive amount means the site's customers pay the actor `m_t·load`, so `balances[(:actor,id)] = Σ m·load` (the reported profit) and the pair cancels exactly, keeping `ledger_residual == 0.0`. Default (`nothing`) adds no rows so existing ledgers are bit-identical. Note the tuple `(:actor, id)` fits `Actor` without changing the const.
- With several sites per bus the per-bus ledger input must be summed (`bus_nets[b] = Σ_sites`, utilities summed); per-site profit uses the site's own net. Provide the slot-aware branch in `settlement_input(ctx)` and `settlement_input(r)`.
- `rebound(baseline_net_load, counterfactual_net_load)` (`equity.jl:339-359`) takes net-LOAD (negated injection) per hour and counts increases strictly after the first reduction. Recommended use in the sweep: baseline = aggregate no-response net load (Σ device baselines + Pdc, from the transform's `b`), counterfactual = scenario realized net load; reports `rebound_amount`, `rebound_ratio` (`NaN` if no reduction; keep the NaN convention).
- Reuse for the sweep: `settlement_input` → `build_settlement_ledger`, `rebound`, `gini`/etc. as needed. Do NOT call `compare_tariffs` (it forces the `:fit` leg → `fit_baseline` guard → `ArgumentError`, and forbids shared buses `comparison.jl:278-282`).

### Anti-Patterns to Avoid
- Baking `m_t·pag_t` into the built AGR objective (overwritten by `solve_agr!`).
- Adding a field to `DsoOpt` (positional construction in `test_admm_exactness_default.jl:45`) or breaking the 18-arg `AdmmState` constructor used by `scripts/profile_ieee8500_memory_attribution.jl:209`.
- Naming the new type `Actor` (collides with `const Actor` at `SettlementLedger.jl:37`; use `Portfolio`).
- Reporting `objective_value` as welfare for profit runs; re-pinning or loosening any golden/tolerance (honesty policy).
- Short-circuiting zero wedges on the centralized path (kills the liveness test).
- Putting `ProfitObjective` into `AbstractStrategy` or `Aggregator` (locked out).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reproducible seeded draws | `Base.hash`, global RNG | `_flex_mix` + `StableRNGs.LehmerRNG` (`materialize.jl:557,577`) | `hash` changed in Julia 1.12 |
| Per-device baseline | A new optimizer or `fit_baseline` plumbing | Single-device QP in the `price_taker_dispatch` shape (`price_taker.jl:79-144`) | Already measured penalty-free price-taker pattern |
| Money accounting | New conservation logic | `_push_transfer_pair!` mirror pairs (`SettlementLedger.jl:105`) | Exact bitwise cancellation |
| Rebound metric | New metric | `rebound` (`equity.jl:339`) | Phase-41 locked definition |
| Solver choice | Naming Clarabel/HiGHS | `select_optimizer(QP()/SOCP())` | Solver abstraction rule |
| Tolerances | Picked epsilons | Measured per repo rule (3x observed max); HiGHS-style defaults silently undercut "exact" (memory note) | Honesty policy |
| Complementarity certificates | New checks | Existing battery/EV/4Q certificates, type-routed by `storage_kind` | Wrappers must forward the trait |

## Runtime State Inventory
Not a rename/refactor/migration phase. Omitted.

## Common Pitfalls

### Pitfall 1: `solve_agr!` overwrites the wedge
**What goes wrong:** Margin baked into the objective via `agr_objective` disappears after the first coefficient update; ProfitObjective silently equals welfare (a vacuous pass-through).
**Why:** `set_objective_coefficient(model, pag[t], c)` replaces the whole linear coefficient [VERIFIED: scratch run; also `AgrOpt.jl:312`].
**Avoid:** store the offset on `AgrOpt`, add it in the coefficient update (Pattern 2). **Detect:** non-zero-m ADMM result must differ from m=0, and match the weighted centralized solve.

### Pitfall 2: ΔW sign and constants (M4, C7)
**Avoid:** recompute `W_soc` from `value(ctx.objective)` / `util` (utilities only). Assert `W_soc ≤ W_opt + tol_measured`; a violation means a bug, never a finding. Compare differences, not levels.

### Pitfall 3: Slot bookkeeping KeyErrors
`has_4q_by_bus` (`admm_phases.jl:415`), `_react_outputs` inner `agg_device_vars[j]` (`admm_state.jl:451`), `_agr_result_keys` and the settlement ADMM adapter all assume key == bus. Extra slots (id N+k) hit KeyError/misaligned `dadp` rows. Cover each in a test with a two-sites-one-bus case under LIVE reactive and with a FourQuadBESS site.

### Pitfall 4: Wrapper trait/`isa` blindness
Wrappers hide the inner type from every `isa` probe and default all traits (flexible-load reactive draw lost, EV certificate skipped or mis-routed, FIT/MPC guards bypassed, `φ` override lost). Forward traits, expose `φ`, extend the guard Union.

### Pitfall 5: Degenerate / non-unique baselines
Flat-price baselines are non-unique for EVs and degenerate for storage; ξ=0 leaves inner vars free. Use tie-breaks, default-wrap flexible loads only, treat ξ=0 as `OptOut`.

### Pitfall 6: Wrong sweep plumbing
`compare_tariffs` throws on wrapped devices (fit leg) and on shared buses. Build the sweep from `settlement_input` + `build_settlement_ledger` + `rebound`.

### Pitfall 7: Name/ordering collisions
`Actor` const exists; new exports must be added to the exact-set test (`test_exports.jl`: `@test exported == keep`). The testitem scoping traps (try/for reassignment) apply.

### Pitfall 8: Adaptive-ρ normalization and iteration counts
`p_p = length(load_nodes)*T` (`admm_phases.jl:330`) counts slots automatically if `load_nodes` carries slot ids; more consensus pairs can change iteration counts (ARCHITECTURE §8 Q2). Do not claim parity of iterations for multi-slot buses; report measured counts.

### Pitfall 9: Opt-out loses ε-flex certificates
Fixed (`OptOut`) devices contribute no variables; an aggregator whose flexible devices are all opted out must still pass (`Aggregator` only needs ≥1 device). Test an all-opt-out aggregator.

## Code Examples

### Hook in `build_agr_opt` and `solve_agr!` (sketch)
```julia
# AgrOpt.jl, build_agr_opt (replaces line 173); other lines unchanged
obj_expr = agr_objective(objective, ctx.objective, pag, T) - 0.5 * ρ * sum(pag[t]^2 for t in 1:T)
...
return AgrOpt(model, ctx, collect(pag), qag, qag_live, T, agg.bus, Float64(ρ),
              agr_linear_offset(objective, T))            # NEW trailing field

# solve_agr! loop (replaces line 312)
for t in 1:agr.T
    coef = -λ_j[t] - ρ * c_j[t]
    agr.linear_offset === nothing || (coef += agr.linear_offset[t])
    set_objective_coefficient(agr.model, agr.pag[t], coef)
    ...
end
```

### Centralized wedge in `solve_welfare` (sketch)
```julia
welfare = ctx.objective - sum(λ₀[t] * p_import[t] for t in 1:T)          # unchanged (line 242)
if actor_active                                                          # any non-WelfareObjective
    for k in eachindex(aggregators)
        term = wedge_term(site_objective[k], agg_net[k].net, T)
        term === nothing || (welfare += term)
    end
end
@objective(model, Max, welfare)
# after solve (non-default only):
ctx.meta[:actor] = (; social_welfare = value(ctx.objective) - Σ λ₀ value(p_import), ...)
```

### Mirror-pair actor profit line (sketch)
```julia
_push_transfer_pair!(transfers, (:actor, id), (:aggregator, bus), t, Float64(m[t]), -Float64(net[t]))
# amount = m*load > 0: customers pay the actor; pair cancels, ledger_residual stays 0.0
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| ARCH §3.3: "nothing in `solve_agr!` changes" | Offset must be threaded into `solve_agr!` | design correction (Pitfall 1) |
| ARCH §3.3: hook on `Aggregator.contribute!` | Wedge from `agg_net` in `solve_welfare` | `Aggregator.jl` untouched |
| ARCH §3.3: baseline "FIT-style solve, `fit.jl:91`-like" | Per-device price-taker solve at `FIT_λ_IMPORT` | `fit_baseline` has no per-device output |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Per-device baseline via single-device flat-price QP is acceptable in place of `fit_baseline` | Pattern 4, OQ1 | CONTEXT locked "from `fit_baseline`"; user must confirm or accept the deviation |
| A2 | Partial compliance blend `p'=b+ξ(p−b)`, `U'=(1−ξ)Ub+ξU` interpreted as exact expectation for a ξ-share population | Pattern 4 | If a single-device reading is wanted, utility is a Jensen lower bound |
| A3 | Slot id = bus for first site, `N+k` for extras | Pattern 3 | Another scheme is fine if 1:1 ⇒ id == bus holds |
| A4 | ΔW is O(m²) for smooth strictly concave devices | Pattern 1 | Kinked utilities give piecewise behaviour; measure before pinning a scaling test |
| A5 | IEEE-123 default ADMM per sweep point is ~tens of seconds warm | Sweep | Only one cold run measured (51 s incl. compile, 4 iters); measure before sizing the grid |
| A6 | Symmetric wedge on exports (customers face `DADP+m` for both buy and sell) | Pattern 1 | A buy-only markup would be a kinked, still convex tariff; document the choice |

## Open Questions

1. **Baseline source (A1).** CONTEXT locks `fit_baseline`; it yields no per-device profile (per-aggregator `fit_flows`, batteryless, rejects flex devices, runs AC-PF). Recommendation: per-device flat-price (`FIT_λ_IMPORT`) single-device solve; planner should surface this deviation for confirmation before Wave 3 starts.
2. **Published per-bus DADP with several slots:** primary-slot value vs slot mean. Recommend primary slot value (row-identical to legacy when 1:1) plus the agreement certificate; choose in Wave 2 and test.
3. **Wedge on exports (A6)** and whether Wave 1 should also support a buy-only kinked wedge (not needed for requirements).
4. **Opt-out granularity** on `:default`: per device (recommended) vs per aggregator.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all | yes | 1.12.5 (matches the pinned patch; do not use 1.12.7, td6node memory note) | — |
| Clarabel/HiGHS/Ipopt | solves | yes (project env, ran solves) | pinned | — |
| Threads > 1 | parallel-equality tests | not by default | — | thread-gated tests already skip with exact invocation (`expected_broken.txt`) |

Measured this session (warm, Julia 1.12.5): IEEE-13 ADMM 6.3 s, 56 iters, welfare −4823.66604824162 (knife-edge canary values); IEEE-13 centralized 3.4 s, welfare −4823.678195611889 (ADMM-vs-central relative gap about 2.5e-6, use as the order of magnitude when measuring crossval tolerances); IEEE-123 default ADMM cold 51 s total, 4 iters, welfare −41046.52372980704. `:case_a_784` ADMM about 900 s per rung (CONTEXT; centralized-only here).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test + TestItems `@testitem` (TestItemRunner via `Pkg.test`), tags drive fast/slow |
| Config file | `test/runtests.jl`, `test/expected_broken.txt`, fixtures `test/fixtures_two_bus.jl`, `fixtures_ieee13.jl`, `fixtures_ieee123.jl`, `fixtures_experiment_harness.jl` |
| Quick run | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_actor_objective.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Slow items (IEEE-123 sweep, tagged `:slow`) | `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_actor_sweep.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Hygiene | after any run `git checkout -- test/Project.toml test/Manifest.toml` if mutated; never TestItemRunner via `julia -e` or `--project=test`; do not run the full suite |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| ACTOR-01 | `agr_objective(WelfareObjective, U,…) === U`; welfare AGR build bit-identical (num vars/cons, objective, default digest fence); per-actor objective selection API; non-zero m changes the dispatch vs m=0 | unit | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_actor_objective.jl …Pkg.test()` | Wave 0 |
| ACTOR-01 | Default-path full-field digest fence: `solve_admm` default result (traces, welfare, dadp, `agr_*`) unchanged; canary stays iters 56 / −4823.66604824162 | regression | `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl,test_admm.jl,test_agr.jl,test_admm_phases.jl` | exists |
| ACTOR-02 | ADMM `ProfitObjective(0)` == welfare ADMM bitwise (`==` on welfare/dadp/iters); centralized m=0 within MEASURED tol; ADMM vs centralized crossval for m≠0 (welfare, dadp, retail price = dadp+m) on 2-bus and IEEE-13 (DEV-10) | integration | `…TEST_FILES=test_actor_objective.jl` | Wave 0 |
| ACTOR-02 | `W_soc(profit) ≤ W_opt` (+ measured tol); ΔW>0 and absolute/relative reported; `welfare` field is social (recomputed) and differs from actor objective; ΔW(2m) vs ΔW(m) scaling only if A4 measured | integration | same | Wave 0 |
| ACTOR-03 | "each site its own actor" slot branch == legacy bitwise (welfare, dadp, iters, residual traces, `agr_*`); multi-bus portfolio on distinct buses == legacy; split-bus equivalence (one bus split into 2 sites/actors ≈ merged aggregator on welfare and dadp within measured tol, centralized and ADMM); slot-λ agreement cert reported; `dadp` shape `(n_load_nodes,T)`; LIVE-reactive + FourQuadBESS multi-slot (no KeyError); legacy guard messages intact on legacy path | integration | `…TEST_FILES=test_actor_portfolio.jl` | Wave 0 |
| ACTOR-03 | Existing 1:1 guards unchanged: `test_admm.jl`, `test_dso.jl`, `test_admm_reactive.jl`, `test_admm_exactness_default.jl`; threaded == serial bitwise needs `JULIA_NUM_THREADS=4` | regression | `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl …` | exists |
| ACTOR-04 | `BehaviourSpec()` default returns input `===` and a digest fence on `:default` population; seeded determinism (same seed ⇒ same draws; different seed ⇒ different), SplitMix64 not `hash`; ξ=1 ⇒ identical dispatch to unwrapped; opt_out=1 ⇒ fixed baseline; wrapper traits forward (`is_flexible_load`, `has_reactive_decision`, `storage_kind`, `φ`); rebound constraint feasible, baseline feasible, recovery inequality holds at the solution; FIT/MPC/stochastic guards throw `ArgumentError` naming wrappers | unit | `…TEST_FILES=test_behaviour.jl` | Wave 0 |
| ACTOR-04 | Effects on welfare/prices/settlement: sweep point on IEEE-13 (fast) with ledger conservation `ledger_residual == 0.0`, actor profit line `= Σ m·load`, rebound ratio present; `assert_no_slack` and cone exactness still pass with wrappers | integration | `…TEST_FILES=test_actor_settlement.jl` | Wave 0 |
| ACTOR-04 | IEEE-123 sweep artifact: committed CSV schema, rows reproduce at a reference point (reads CSV, re-solves one point) | slow | `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_actor_sweep.jl …` | Wave 0 |
| All | Exact export set updated; JET ratchet; scripts index; docs page registered | repo gates | `TSODSO_TEST_FILES=test_exports.jl …`; `julia --project=. scripts/jet_check.jl --selftest`; `python3 .github/scripts/check_scripts_index.py`; JET full check on Julia 1.12 per `scripts/jet_check.jl` header | exists |

### Sampling Rate
- Per task commit: the single new test file for that task (fast set) plus `test_admm_phases.jl`.
- Per wave merge: new files + `test_admm_knifeedge_canary.jl, test_admm.jl, test_agr.jl, test_dso.jl, test_admm_reactive.jl, test_welfare_solve.jl, test_settlement.jl, test_flex_population.jl, test_exports.jl`.
- Phase gate: orchestrator-run full suite before `/gsd:verify-work` (not run by agents).

### Wave 0 Gaps
- [ ] `test/test_actor_objective.jl`, `test/test_actor_portfolio.jl`, `test/test_behaviour.jl`, `test/test_actor_settlement.jl`, `test/test_actor_sweep.jl`
- [ ] Measure tolerances first (3 seeds, 3x observed max): centralized pass-through gap, ADMM-vs-central profit crossval gap, split-bus equivalence gap, ΔW ≥ 0 slack.
- [ ] Pre-phase golden digests of default `solve_admm` result fields and default `build_population` captured BEFORE any src change (pattern: `test_flex_population.jl` FNV fold).
- [ ] Framework install: none.

Test-writing rules: `@testitem` bodies are top-level (soft scope): never `try x = …` or reassign outer variables in `for`/`try`; wrap in a function or `let`. Exports: update `keep` in `test/test_exports.jl` exactly. New `broken`/`skip` entries must be listed in `test/expected_broken.txt` (avoid creating any).

## Security Domain

Research bench with no network, auth, or secrets; `security_enforcement` not set false so a minimal pass:

| ASVS Category | Applies | Control |
|---------------|---------|---------|
| V2/V3/V4 auth/session/access | no | — |
| V5 Input validation | yes | fail-loud `ArgumentError` guards: wedge length = T, finite, ξ ∈ (0,1], 0 ≤ opt_out ≤ 1, r ≥ 1, W ≥ 1, duplicate/unknown actor sites, unsupported device types |
| V6 Cryptography | no | — |
| Data integrity | yes | ledger conservation guard stays exact; non-finite solver outputs refused at adapter boundary (existing `_finite_or_throw*`) |

## Sources

### Primary (HIGH, read in this session)
- `src/admm/AgrOpt.jl`, `admm_phases.jl`, `admm_state.jl`, `DsoOpt.jl`, `solve_admm.jl`
- `src/devices/Aggregator.jl`, `AbstractDevice.jl`, `CapabilityTraits.jl`
- `src/models/welfare_solve.jl`
- `src/pricing/fit.jl`, `src/settlement/{SettlementLedger,run_inputs,equity,price_taker,comparison}.jl`
- `src/experiments/materialize.jl`, `test/test_exports.jl`, `test_admm_knifeedge_canary.jl`, `test_flex_population.jl`, `test_admm_phases.jl`, `scripts/jet_check.jl`, `docs/make.jl`
- `.planning/research/ARCHITECTURE.md` §3.2/3.3/§8, `PITFALLS.md` C7/C8/M3/M4, `FEATURES.md` framing insights, Phase 43 summaries
- Scratch run: JuMP/Clarabel confirmation that `set_objective_coefficient` overwrites a baked-in linear term; warm timing runs listed above.

### Secondary / Tertiary
None (no web sources needed).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (no new packages)
- Architecture (hook, slot table, ledger): HIGH, read from code and verified by one empirical check
- Behavioural baseline and utility blending: MEDIUM (A1, A2 need confirmation)
- Pitfalls: HIGH for code-derived ones, MEDIUM for EV degeneracy (not run)

**Research date:** 2026-11-02
**Valid until:** 2026-12-02 (stable internal code; re-check line numbers if Phase 43 follow-ups touch `src/admm/`)

## Recommended Wave / Plan Decomposition (focus item 7)

| Wave | Plan | Scope | Depends on | Key risks |
|------|------|-------|-----------|-----------|
| 0 | 44-01 prep (can be folded into wave 1) | measure tolerances, capture default digests, write failing tests | — | golden drift if captured after src edits |
| 1 | 44-02 Actor objective + Portfolio + centralized + ADMM wedge | `actor_objective.jl`, `Portfolio` + `_expand_actors`, `build_agr_opt(objective)`, `AgrOpt.linear_offset`, `solve_agr!`, `solve_welfare(actors/objectives)` + `ctx.meta[:actor]`, `solve_admm(actors=)` for distinct-bus portfolios (legacy path), ΔW helper, pass-through + crossval + ΔW tests | Phase 41 | Pitfall 1 (offset overwrite), centralized non-bitwise pass-through, name collision |
| 2 | 44-03 Slot-table ADMM generalisation | `SlotTable`, `_admm_build` slot branch, `build_dso_opt` slot kwarg (meta-stored `slot_bus`), `has_4q`/`_react_outputs`/`_agr_result_keys` slot keys, per-bus DADP + agreement cert + `λ_slots`, 18-arg `AdmmState` constructor kept, bitwise identity + split-bus equivalence tests | Wave 1 | Pitfalls 3, 8; threaded executor ordering; LIVE reactive |
| 3 | 44-04 Behavioural wrappers + BehaviourSpec | `Behavioural.jl`, trait forwarding, `_device_baseline`, `apply_behaviour`, guards (`fit.jl:83` Union, stochastic), tests | Phase 43 (parallel to wave 2; disjoint files except `fit.jl` guard and `materialize.jl`) | Pitfalls 4, 5, 9; OQ1 decision needed first |
| 4 | 44-05 Settlement + sweep + docs | `actor_wedges` ledger line, slot-aware `settlement_input`, `scripts/actor_behaviour_sweep.jl` → `results/actor_behaviour/*.csv`, literate page, `docs/make.jl`, `scripts/README.md`, `test_exports.jl`, JET baseline update, IEEE-123 slow test | Waves 1-3 | Pitfall 6; sweep runtime (A5); JET ratchet drift |

Phase-level risks: (1) the OQ1 baseline deviation; (2) ADMM vs centralized agreement tolerance for non-zero wedge is unmeasured; (3) more slots change ADMM iteration counts and adaptive-ρ trajectory; (4) the knife-edge canary must stay at iters 56 / welfare −4823.66604824162 (never re-pin); (5) JET baseline (`scripts/jet_baseline.txt`) must be updated with justification if new reports appear.
