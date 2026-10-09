# Architecture Research — v5.0 Aggregator Layer at Scale

**Domain:** Brownfield integration of five feature groups onto the validated TSODSO Julia/JuMP package
(`src/TSODSO.jl` single-ownership include graph; operational layer = `AgrOpt` ⇄ `DsoOpt` ⇄ `solve_admm`).
**Researched:** 2026-10-09
**Confidence:** HIGH on integration points (read from code, file:line cited). MEDIUM on the forward-looking
designs (slots, actor objective, settlement types). LOW on 8500 memory attribution and on Volt-VAR
formulation (both flagged as needing a dedicated research/measurement step). No Julia was run; no tests were read
beyond headers, so every "risk to test X" below is inferred from the source, not verified.

---

## 1. System Overview (as-built facts that constrain v5.0)

```
experiments/  Scenario(selectors)+strategy ─materialize→ (feeder, λ₀, Vector{Aggregator}) ─run(::Strategy)→ ScenarioResult
                                                                                              (welfare, dadp, exact_maxgap, details)
admm/         _admm_build ─► DsoOpt (ONE whole-net SOCP, pag_dso[j,t]) + Dict{Int,AgrOpt} keyed by BUS (1:1 guard)
              _admm_iterate!: for j in load_nodes {AGR solve} → DSO solve → accumulate → record! → dual step → ρ adapt
              _admm_certify : final AGR re-solves (battery/4Q certs) → final DSO solve (SOC gate) → no-slack gates
pricing/      extract_dlmp / decompose_dlmp (duals of :balance_p), fit_baseline (German FIT, per-aggregator QP),
              welfare_accounting (social = prosumer + DSO; reads ctx.meta[:agg_net])
devices/      AbstractDevice → Thermostatic/Deferrable/PVBattery/FourQuadBESS/FixedCapacitor; Aggregator = SOLE :Rp/:Rq writer
data/         Feeder fixtures, generate_profiles (StableRNG), build_population lives in experiments/materialize.jl
```

Facts that drive every decision below:

| Fact | Where | Consequence |
|---|---|---|
| ADMM is hard-wired **1 aggregator per load bus**; throws on 2 per bus | `src/admm/admm_phases.jl:41-55` (guards), `AdmmState.agr_by_bus::Dict{Int,AgrOpt}` `admm_state.jl:98` | Multi-node portfolios and "house-level" parallel granularity both need a coupling-axis generalization. |
| The **centralized** path already accepts several aggregators per bus (residuals accumulate) | `Aggregator.jl:232-233`, `welfare_solve.jl:195-200` (`agg_net` is per aggregator), `build_dso_opt` already sums `q_draw` over aggregators sharing a bus `DsoOpt.jl:362-375` | Only the ADMM *coupling* is 1:1, not the physics. |
| `AgrOpt` objective is assembled once: `obj_expr = ctx.objective − ½ρΣpag²` (+LIVE term); per-iteration only the *linear* coefficient on `pag[t]` changes | `AgrOpt.jl:156,172,291` | An actor objective is a one-line change at model-build time, not a loop change. |
| ADMM loop mutates shared dicts inside the AGR step: `st.a[j]=`, `st.util[j]=`, `ls.b[j]=` | `admm_state.jl:158-159,203-207`, loop at `admm_phases.jl:166-168` | Not thread-safe as written; needs compute/commit split. |
| Float-order contract: accumulators iterate `for j in load_nodes, t in 1:T`; canary pins iters=56, welfare −4823.66604824162 | `admm_state.jl:6-12`, `admm_phases.jl:183-191`, `test/test_admm_knifeedge_canary.jl` | Any new path must leave the default call sequence untouched; new behaviour = new types/methods, never edits of the default method bodies. |
| `Scenario.feeder ∈ (:ieee13,:ieee123)` only; `build_feeder` already knows `:ieee8500(_mv)` | `Scenario.jl:24` vs `materialize.jl:35-52` | The headline 8500 run cannot go through `Scenario`/`run_scenario` until the tuple is widened (additive). |
| `Scenario` identity/filename: `_scenario_identity` adds optional keys conditionally (`pf_ε`, `pf_thesis_literal`) | `store.jl:90-119` | The precedent for adding selectors without changing existing filenames/provenance. |
| `ADMM` result NamedTuple exposes only `welfare,dadp,λ,iters,residuals,dso_ctx,exact_maxgap,mu_q,q_devices,…`; per-node `pag`, per-aggregator `util` are internal (`st.a`, `st.util`) | `admm_phases.jl:324-337` | Settlement/equity cannot be computed from an ADMM result today. Needs additive keys. |
| `Aggregator` rolls devices into ONE `p_inject` per bus; per-device/per-house injections are not retained | `Aggregator.jl:194-224` | Household-level equity is impossible without a house↔device map and per-device injection stash. |
| `build_dso_opt` guard + `_any_flexible_reactive` + `has_4q_by_bus` all special-case `FourQuadBESS`/`is_flexible_load` by type | `DsoOpt.jl:173,326`, `admm_phases.jl:278-280`, comment `DsoOpt.jl:318-321` ("probe should move to a contract-level trait") | New reactive-capable devices (smart inverter) hit this; add the trait first. |
| 8500: DSO build+first solve ≈1.1 GiB, ~3.4 GiB of T=10 `solve_admm` delta UNATTRIBUTED; d=0.1 T=10 converges in 8 iters but is REFUSED by the exactness gate (CertificateError, hybrid ratio 568.95) | STATE.md line 97 | Parallel AGR solves will not cure the 8500 wall (DSO-side/memory problem); gate refusal is a *finding*, not a bug to tune. |

---

## 2. Recommended Architecture (delta view)

```
                               NEW                                   MODIFIED (additive only)
experiments/   Scenario: +selectors (actor, tariff…) conditional      Scenario.jl:24,48 widen tuples; strategies.jl ADMM gets `executor`
               ADMM.executor (excluded from ==/hash/filename)         materialize.jl build_population: +:thesis_caseA etc.
               run_with_record(s) → (ScenarioResult, DispatchRecord)  run.jl untouched default; store.jl conditional keys
settlement/    NEW DIR (after pricing/, before experiments/):         —
               tariffs.jl  dispatch_record.jl  settle.jl  equity.jl
admm/          executor.jl (Serial/Threaded sweeps)                   admm_phases.jl: sweep call; _admm_build slots; certify +keys
               slots.jl (CouplingSlot, slot table)                    AgrOpt.jl: objective kwarg; DsoOpt.jl: slot axis
               actor_objective.jl (Welfare / Profit)                  admm_state.jl: pure solve/commit split (new fns, old kept)
actors/        NEW DIR (after devices/Aggregator): Population,        —
               Actor, Portfolio, HouseRef, behavioural wrappers
devices/       EV.jl HeatPump.jl SmartInverterPV.jl                   AbstractDevice.jl: +has_reactive_decision trait
               Behavioural wrappers (PartialCompliance, OptOut)       Aggregator.jl: +device_p_inject in return NamedTuple
coordination/  FlexMarket (late phase)                                —
```

### Component responsibilities

| Component | Responsibility | New / Modified |
|---|---|---|
| `AbstractAgrExecutor` (`SerialExecutor`, `ThreadedExecutor`) | How the per-slot AGR subproblems of one ADMM sweep are scheduled | NEW `src/admm/executor.jl` |
| `CouplingSlot` / slot table | The ADMM coupling axis: one slot = one `(actor, bus)` consensus pair (`pag_s` vs `pag_dso_s`). Default: slot id == bus id | NEW `src/admm/slots.jl` |
| `AbstractActorObjective` (`WelfareObjective`, `ProfitObjective`) | Builds the AGR objective accumulator from `ctx.objective`, `pag`, tariff | NEW `src/admm/actor_objective.jl` |
| `Population`, `Actor`, `Portfolio`, `HouseRef` | Who owns which aggregators/houses; house↔device index map; grouping for settlement | NEW `src/actors/` |
| `DispatchRecord` | JuMP-free snapshot of a solved run: `pag[slot,t]`, per-site utility, `p_import`, `λ`, `λ₀`, per-device injections, slot→(actor,bus,house) maps | NEW `src/settlement/dispatch_record.jl` |
| `AbstractTariff` (`FIT`, `TOU`, `Flat`, `DADPTariff`, `NodalTariff`) + `settle` + equity metrics | Pure post-processing → per-actor/household bills, surplus, Gini/ratio metrics | NEW `src/settlement/` |
| `EV`, `HeatPump`, `SmartInverterPV` | New `AbstractDevice` subtypes obeying the aggregatable contract | NEW `src/devices/` |
| `FlexMarket` coordination | DSO procures redispatch quantities instead of publishing prices | NEW, last phase |

---

## 3. Answers to the specific integration questions

### 3.1 Where does parallelism go? (one JuMP model per aggregator per thread?)

**Yes: parallelize across the *independent* AGR-OPT models, one task per `AgrOpt`, never inside a model, and keep the DSO solve serial.**

- Granularity is already right: each `AgrOpt` owns its own `Model(select_optimizer(QP()))` + `ModelContext` (`AgrOpt.jl:131-132`); Clarabel is pure Julia and each model gets its own optimizer instance, so independent models share no solver state. No `direct_model` (Clarabel is copy_to-only, `factory.jl` header).
- **Not thread-safe today** (the loop body, not the solver): `_react_agr_solve!` writes `st.a[j]`, `st.util[j]`, `ls.b[j]` into shared `Dict`s (`admm_state.jl:158-159, 203-207`). Concurrent `Dict` mutation is a data race.
- **Pattern (compute/commit split):** add NEW functions `_agr_compute(rmode, st, j; final, has_4q) -> NamedTuple` (pure: reads `st.λ[j]`, `st.c[j]`, `st.ρf`, calls `solve_agr!` on `st.agr_by_bus[j]`, returns `(pag, utility, qag_live_values)`) and `_agr_commit!(rmode, st, j, r)` (the three dict writes). Task-parallel part runs `_agr_compute` into a preallocated `Vector` indexed by position in `load_nodes`; then a **serial** loop in `load_nodes` order commits. Every downstream accumulator (`for j in load_nodes, t in 1:T`, `admm_phases.jl:183`) stays untouched, so the floating-point order contract holds.
- **Executor as a type**, dispatched like the strategies:
  ```julia
  abstract type AbstractAgrExecutor end
  struct SerialExecutor   <: AbstractAgrExecutor end          # default; calls the EXISTING loop verbatim
  struct ThreadedExecutor <: AbstractAgrExecutor; ntasks::Int; end   # falls back to Serial if nthreads()==1
  _agr_sweep!(::SerialExecutor, rmode, st; kw...)   # = the current `for j in load_nodes; _react_agr_solve!(...)` block
  _agr_sweep!(ex::ThreadedExecutor, rmode, st; kw...) # compute in tasks, commit serially
  ```
  Call site: `admm_phases.jl:166-168` and the final-pass loop `admm_phases.jl:281-283`. The `SerialExecutor` method must be the literal old loop so the canary cannot move.
- **Determinism:** each AGR solve depends only on its own `λ_j, c_j, ρ`; results are therefore bit-identical across thread counts *provided* the commit and all reductions stay serial and in `load_nodes` order. Enforce with a test `run(ADMM(executor=Threaded)) == run(ADMM(executor=Serial))` on `welfare`, `dadp`, `iters` (and `==` residual traces).
- **Exception handling pitfall:** `solve_admm` catches `CertificateError` by type (`solve_admm.jl:364`). An exception thrown inside `Threads.@spawn`/`@threads` surfaces as `TaskFailedException`/`CompositeException` and breaks that `isa` check and the report-vs-throw policy. Wrap each task body in `try … catch e; (; err=e) end`, and rethrow the **lowest-index** failure on the main thread (deterministic). The final certification pass (battery/4Q gates, `solve_agr!(…check_battery=true…)`) can use the same sweep.
- **Where `executor` lives:** a field on `ADMM` (`strategies.jl:38`) with default `SerialExecutor()`, **excluded** from `Base.:(==)`/`hash` (`strategies.jl:188-196`) and from `_strategy_knobs` (`store.jl:56-64`), because results are bit-identical by construction (same status as `elapsed`). Threads are a runtime resource (`julia -t N`); do not bake `N` into provenance except as an informational key in `ADMMDetails`.
- **Build-phase parallelism** (`_admm_build`, `admm_phases.jl:48-55` — thousands of `build_agr_opt` at 8500) can also use the executor: building independent JuMP models in tasks is safe (anonymous `@variable`/`@constraint` only; the one named object, `Pdc_param`, is already anonymous for exactly the multi-aggregator reason, `Aggregator.jl:189`). Put results in a `Vector`, fill the `Dict` serially.
- **What parallelism will NOT do:** DSO-OPT is one conic solve per iteration and dominates at scale (and all `AgrOpt`s are resident simultaneously — memory is the 8500 wall). Threads add allocation pressure/GC stop-the-world. Do not promise the 8500 headline from threading alone.
- **Rejected:** `Distributed`/process-parallel (duplicates feeder + model memory; the wall is memory); one *thread-shared* model with locks; Clarabel-internal multithreading (single-threaded QDLDL, nothing to gain).
- **Optional DSO split (opt-in, new type):** the network constraints are per-hour independent (devices carry the time coupling), so `DsoOpt` could be built as T per-hour SOCPs (`HourSplitDsoOpt`), parallelizable and individually smaller. It will NOT be bit-identical to the monolithic solve (different KKT assembly) → must be an opt-in strategy knob and may never become the default (canary). Whether it reduces *peak* memory is unknown (all T models stay resident under build-once) — **measure before building** (see §6, Phase 6).

### 3.2 Relaxing 1-aggregator-per-node → multi-node portfolios

**Make the ADMM coupling axis a *slot*, not a bus. One slot = one consensus pair `(pag_s, pag_dso_s)`. A bus may carry several slots; an actor's portfolio is the set of its slots.**

- `DsoOpt` currently has `pag_dso[j,t]` indexed by bus (`DsoOpt.jl:409`) and injects it into `:Rp[j]` (`:411`). Index it by slot id instead and inject into `:Rp[bus(s)]`. Two slots on one bus just add two variables to the same nodal balance; the nodal price (dual of `:balance_p[j]`) is shared, so all slot multipliers `λ_s` converge to the same −DADP. The ρ-penalty is strictly convex per slot, so the DSO's split of the nodal total across slots is unique. This is plain 2-block consensus ADMM (no sharing-problem derivation needed).
- **Bit-identity trick:** in the default 1:1 case slot id == bus id and `slots == load_nodes` (ascending). Then `pag[j,t]`, `λ[j]`, `a[j]`, `agr_by_bus[j]`, the accumulator order and `_react_*` hooks are *the same objects in the same order*. Keep the field name `agr_by_bus` (key = slot id); add `slot_bus::Dict{Int,Int}` (identity when 1:1). `q_draw` (`DsoOpt.jl:362`) is per bus today: under slots it must be per slot (each aggregator's own `−Pdc·tanφ`); sum remains identical when 1:1.
- Guards to convert: `admm_phases.jl:41-47` (length equality `aggregators == load_nodes`) and `:49-52` (duplicate bus) become "slot table well-formed" checks; the legacy error messages must stay for the legacy path (tests may match them — treat as a risk to verify).
- `_admm_certify` publishes `dadp` as `(n_load_nodes, T)` ascending-bus (`admm_phases.jl:319`, consumed as `extract_dlmp(ctx)[load_buses,:]` in `run.jl:102`). Keep that *nodal* shape: with several slots per bus publish one row per bus (slot multipliers agree at convergence; assert `max_s |λ_s − λ_bus| ≤ tol` as a new certificate, report-don't-throw per `status_policy.md`), and expose per-slot λ additively.
- **Multi-node portfolio, two levels of ambition:**
  1. *Grouping-only (recommended first):* an `Actor` = `Vector` of site `Aggregator`s at different buses; each site is an ordinary slot; the portfolio exists in `Population`/settlement (bills, profit, equity) and in the profit objective's *sum* — no new solver block. Works because `Aggregator` stays the physical, single-bus, sole-`:Rp/:Rq`-writer roll-up (do **not** make `Aggregator` multi-bus: its `bus::Int` field and `add_to_residual!(…, agg.bus, …)` are load-bearing, `Aggregator.jl:59-93,232`).
  2. *Portfolio-coupled (only if research demands it):* actor-level constraints/objective across sites (fleet energy budget, portfolio flexibility cap, cross-node arbitrage). Add `PortfolioAgrOpt` (ONE JuMP model containing several sites' `contribute!` + the shared constraint, exposing `pag::Vector{Vector{VariableRef}}`), with a small `AbstractAgrBlock` interface (`solve_agr!`, `set_rho!`, `set_rho_q!`, `pag` accessor). Default `AgrOpt` implements it unchanged. This is a larger refactor of `AdmmState`; defer until Phase 5b.
- House-level parallel granularity is the same mechanism: `build_population(...; granularity=:house)` can emit one `Aggregator` per house (many slots per bus), giving 784 independent tasks for Case A instead of 10. Trade-off: 784×T extra DSO coupling variables and multipliers, and ADMM convergence behaviour changes (more consensus pairs) — measure iteration counts before making it the recommended mode. Node-level (≈78 houses → ~234 devices in one QP) is the faithful thesis layout and is cheap (QP is sparse).

### 3.3 Profit objective vs welfare objective (strategy/type?)

**A small type hierarchy on the AGR objective, not a new solve strategy, and not a flag inside `Aggregator`.**

- Strategies (`Centralized/ADMM/MPC/Stochastic`) answer *how to solve*; the actor objective answers *what the agent wants*. They are orthogonal axes — adding `ProfitADMM <: AbstractStrategy` would square the strategy×pf matrix (`supports_pf`, `strategies.jl:216-232`).
- Add `abstract type AbstractActorObjective`, `WelfareObjective` (default), `ProfitObjective(retail::AbstractTariff; utility_weight=0.0, …)` with one method:
  ```julia
  agr_objective(::WelfareObjective, U, pag, T) = U                       # `===` ctx.objective ⇒ build is bit-identical
  agr_objective(o::ProfitObjective, U, pag, T) = o.w*U + Σ_t retail_term(o, pag[t], t)   # linear in pag ⇒ same ADMM handle
  ```
  Called at `AgrOpt.jl:156` (`obj_expr = agr_objective(objective, ctx.objective, pag, T) − 0.5ρΣpag²`). `build_agr_opt` gains `objective = WelfareObjective()`; `solve_admm` gains `actors`/`objective` kwarg threaded through `_admm_build` (`admm_phases.jl:54`). Nothing in `solve_agr!`, `set_rho!`, the loop, or the residual hooks changes, because only the *accumulator built once* differs and the per-iteration lever (the linear coefficient on `pag`) is unchanged.
- **Semantics to document honestly (research-critical):** all price-taking concave agents + DSO clearing ⇒ ADMM converges to the optimum of `Σ_a f_a − λ₀ᵀp_import` (first welfare theorem). So "profit" with retail revenue is a *different weighted objective inside the same equilibrium machinery*, not a strategic aggregator (no market power, no Stackelberg against the DSO price). `welfare` in `ScenarioResult`/`_admm_certify` (`welfare = Σ util − λ₀ᵀp_import`, `admm_phases.jl:316`) must remain **social welfare computed from device utilities**, independent of the actor objective; actor profit is a separate reported quantity (settlement). Cross-validation against `solve_welfare` only holds for `WelfareObjective`; for profit, the cross-check is a *weighted* centralized solve (`Aggregator.contribute!` would need the same `agr_objective` hook at `Aggregator.jl:237` — add it as a kwarg on a new method, default path unchanged) or the equilibrium identity.
- Customers' response to the retail price vs the nodal price is the settlement/tariff axis (§3.4): "customers respond to τ, aggregator exposed to λ" is a bilevel-flavoured model; keep v5.0 to the single-level weighted-objective form and mark the strategic/bilevel form out of scope.
- **Behavioural response** (partial compliance ξ, opt-out/comfort limits, rebound): implement as *wrapper devices* satisfying the existing contract — `PartialCompliance(inner, ξ, baseline)`, `OptOut(inner, p_out)` — so they compose inside any `Aggregator` with no core change. Rebound = an energy-recovery constraint over a window (extend `Deferrable`-style constraint in the wrapper). Needs a no-response baseline profile (a FIT-style solve, `fit.jl:91`-like) as input; compute once at population build, not in the loop.

### 3.4 Where do settlement and equity live?

**A new `src/settlement/` layer, pure post-processing of a JuMP-free `DispatchRecord`, included after `pricing/` and consumed by `experiments/`.** It must not live inside `welfare_accounting` (`pricing/welfare.jl`), which is tied to a solved centralized `ctx` (`ctx.meta[:agg_net]`) and has a hard social=prosumer+dso identity gate.

- **Why a record:** ADMM results don't carry `pag`/`util` (`admm_phases.jl:324-337`); centralized results keep them inside `ctx`. Add additive keys to the `_admm_certify` NamedTuple (`pag`, `util`, `p_import`, per-slot `λ`) and write `dispatch_record(::AdmmResult)`/`dispatch_record(ctx)`. Verify no test asserts the exact key set of that NamedTuple before adding (grep `test_admm*.jl`; risk flagged).
- **Do not change `ScenarioResult`/`run`:** add `TSODSO.run_with_record(s) -> (ScenarioResult, DispatchRecord)` (new function; `run.jl:116-150` untouched). This avoids touching `ADMMDetails`/JLD2 provenance and `result_to_dict`.
- **House level:** needs (a) a `HouseRef(agg_index, device_range, …)` table produced by the population builder, and (b) per-device injections: extend `Aggregator.contribute!`'s return NamedTuple with `device_p_inject` (additive key, `Aggregator.jl:242`; callers destructure by name) and stash in `ctx.meta[:device_p_inject]` in `build_agr_opt` (`AgrOpt.jl:140`). Without this, equity "across households" is not computable — only across nodes/aggregators.
- **Tariffs change customer dispatch, so cross-tariff settlement is "re-dispatch under tariff, then bill":**
  - `FIT`: existing `fit_baseline` (`pricing/fit.jl:382`) already solves per-prosumer FIT-OPT and is the template; keep it (it is certified/gated; there are known flakes — STATE.md fit_baseline ALMOST_OPTIMAL todo).
  - `Flat/TOU/NodalTariff(τ)`: customers are price takers at τ with *no network*: reuse `build_agr_opt`+`solve_agr!` with `λ_j := τ_j`, `c_j := 0`, tiny proximal ρ (ρ→0 may leave non-strictly-concave devices degenerate; measure), or a dedicated one-shot builder in the style of `_fit_opt_solve` (`fit.jl:155`). One-shot, not a hot loop → build-once is not required.
  - `DADPTariff`: the ADMM/centralized result itself.
  - **Network consequence of a tariff-driven dispatch** = push the fixed injections into the network and re-solve: such fixed-dispatch SOCP re-solves are structurally inexact (memory: exactness-gate note) → evaluate with `ACPowerFlow(limits=false)` / report the certificate, never throw. This is a report-vs-throw (`status_policy.md`) case: return a `Settlement` carrying `status`/`exact_maxgap` rather than raising.
- **Equity:** `equity(settlement; by=:house|:node|:actor)` → distributional metrics (bill shares, Gini, quantile ratios, price-vs-bill regressivity by node distance from root — nodal DADP is higher at feeder ends, so nodal vs flat is the headline comparison). Pure functions on arrays; trivially testable and golden-able.
- **Flexibility market vs prices:** a coordination alternative, not a settlement variant. Design as `abstract type AbstractCoordination` (`PriceBased` = existing ADMM/DADP, `FlexMarket`) producing the same `DispatchRecord`, so settlement/equity compare them uniformly. `FlexMarket` = baseline dispatch under tariff τ → DSO redispatch SOCP over bounded quantity offers (`Δp[s,t] ∈ [−F↓,F↑]`, bid cost curve from the aggregator's own marginal cost), built on the same `contribute!(pf, ctx, feeder)` + `close_balance!` seam as `build_dso_opt`. Highest research risk; last phase (§6).

### 3.5 How new devices plug into `AbstractDevice`

All three follow the aggregatable contract in `AbstractDevice.jl:25-62`: `contribute!(d, ctx; T) -> (; vars, p_inject, utility[, q_inject])`, write **nothing** to residual/objective, network-agnostic (bus + parameters only), constructor validation by `throw(ArgumentError)`, concave quadratic utility, **no binaries**. Each is one file in `src/devices/` plus one `include` line in `TSODSO.jl` between `FixedCapacitor.jl` (line 126) and `Aggregator.jl` (line 129), plus an export.

| Device | Contract notes | Integration hazards |
|---|---|---|
| `EV` | `p_ch[t] ≤ Pmax·avail[t]` (avail ∈ {0,1} parameter vector from arrival/departure); SOC recursion like `PVBattery`; departure target `soc[dep] ≥ E_req` as a **soft** constraint (convex slack penalty) to avoid infeasible populations; V2G = `p_dch` with the App. C strict ordering `λ_min<λ_med<λ_max` (copy `PVBattery`'s constructor guard — correctness rests on it, `PVBattery.jl:36-50`). Name vars `p_ch`/`p_dch` so `assert_battery_complementarity!` (consumes `ctx.agg_device_vars`) checks V2G automatically — **verify how it identifies batteries before relying on that**. Constructor default `φ=1.0` if it is a `is_flexible_load` (unity-pf charger). | `is_flexible_load(::EV)=true` flips `_any_flexible_reactive` ⇒ ADMM default goes to `ReactiveMode.LIVE` (`DsoOpt.jl:170-176`, `admm_state.jl:371`), changing the ADMM path for any population containing an EV. Either set the trait false for unity-pf EVs (no reactive draw) or accept LIVE knowingly and document. V2G with positive `p_inject` × `tanφ` gives wrong-sign `q` (`Aggregator.jl:215-221`) — another reason for φ=1. |
| `HeatPump` | Generalizes `Thermostatic` (first-order `Tin[t+1]=Tin+α(Tout−Tin)+β·P`, `Thermostatic.jl:62`) to a building RC (2R2C: air + envelope states, still linear). COP(Tout) is a *parameter vector* ⇒ electrical power = thermal/COP stays linear. Comfort band as hard limits + concave comfort utility. `is_flexible_load=true`. | Same LIVE-mode trigger as above (existing behaviour for `Thermostatic`, so heat pumps change nothing new). Larger state ⇒ more variables per house at 784 scale (check AGR build time/memory). |
| `SmartInverterPV` (Volt-VAR) | **Contract strain:** a Volt-VAR *droop* is `q = f(v_j)`, but devices never see network variables (`AbstractDevice.jl:64-71`) and ADMM puts `v` in DSO-OPT. Two options: (a) *OPF-optimal reactive capability* — PV inverter with `pv_used² + q² ≤ S²` (SOC constraint) and a genuine `q_inject` decision, riding the **existing** `q_inject` contract + LIVE reactive consensus exactly like `FourQuadBESS` (recommended first; no contract change); (b) *droop curve* as a DSO-side affine/inequality constraint on `v` and `qag_dso` — a node-attached controller object in the DSO layer, not a device; the clamped curve is non-convex as an equality, so only a convex inner/outer approximation is admissible (**research needed**). | The type-specific probes must be generalized first: add trait `has_reactive_decision(::AbstractDevice)=false` (true for `FourQuadBESS`, `SmartInverterPV`) and replace the `dv isa FourQuadBESS || is_flexible_load(dv)` probes at `DsoOpt.jl:173,326`; `has_4q_by_bus` (`admm_phases.jl:278`) stays 4Q-specific (an inverter needs no complementarity cert). `_react_outputs` q_devices scan (`admm_state.jl:401`) keys on `p_ch/p_dch/q` — decide whether inverter `q` should be published. Default path unchanged because the trait defaults match the old behaviour. |

### 3.6 How population builders scale to 784 houses

Today a "house" = one `Aggregator` with `[Thermostatic, Deferrable, PVBattery]`; `build_population(:default)` = 1 house per load bus (`materialize.jl:429-443`); Case A's 784 houses (10 aggregators, ~78/node) is only a rescaled proxy (`scripts/thesis_caseA.jl` header).

- **New selector, not a modified one:** `:thesis_caseA` (and later `:ieee8500_real`) added to `SCENARIO_VALID_POPULATIONS` (`Scenario.jl:48`) and a new branch in `build_population` *before* the `:default` guard (`materialize.jl:343-349`). The `:default`/`:ieee13`/`:ieee123`/`:ieee8500` branches stay byte-identical (their goldens depend on `seed + bus` per-bus profile draws, `materialize.jl:222`).
- **Seeds:** per-house draws must not use `seed + bus` (collides across houses on a bus). Use `sub_seed(master, tag)`-style hashing on `(master, :house, bus, h)` (`materialize.jl:24`; pure hash, never global RNG) → `generate_profiles(seed=…)` per house. Inelastic `Pdc` of an aggregator = Σ of its houses' `Pdc` (the `Aggregator.Pdc` is one vector per aggregator, `Aggregator.jl:63`); PV/battery live per house in each `PVBattery.Ppv`.
- **Return type:** `Population` (aggregators + `HouseRef` table + optional `Actor/Portfolio` grouping) instead of a bare `Vector{Aggregator}`; keep `build_population`'s old return for old selectors and make `_materialize` (`run.jl:61-73`) take `.aggregators`. `run` stays path-free.
- **Build cost:** `Aggregator.contribute!` accumulates `p_inject[t] += res.p_inject[t]` with immutable `+` (`Aggregator.jl:201`) — O(houses²·T) term copying per aggregator (78 houses ≈ 234 devices ⇒ ~6·10⁵ term-copies per aggregator-hour-set; acceptable) but wasteful; replacing with `JuMP.add_to_expression!` is bit-safe for coefficients but is an edit to the default path ⇒ do it only behind a measured need and re-run the canary. Same for `ctx.objective + expr` (`ModelContext.jl:234`).
- **8500:** `_ieee8500_house` builds one house per SX load (`materialize.jl:273`); real count/density is already parameterised in the benchmark harness (`scripts/benchmark_ieee8500.jl`). `Scenario` must accept `:ieee8500`/`:ieee8500_mv` (`Scenario.jl:24`) for the headline run via the standard harness.
- **Centralized cross-check at 784:** `solve_welfare` already handles many devices per aggregator; only run it for Case A (not 8500).

---

## 4. Data-flow changes

```
Population ──(slot table)──► _admm_build ─► DsoOpt[slot axis] + {AgrOpt per slot, objective = agr_objective(actor, …)}
                                   │
 _admm_iterate!: _agr_sweep!(executor) ─► (compute ∥) ─► commit serial ─► DSO solve (serial) ─► accumulators (serial, load_nodes order)
                                   │
 _admm_certify ─► result NamedTuple  + pag, util, p_import, λ_slot  (additive)
                                   │
 run_with_record ─► DispatchRecord ──► settle(record, tariff, actors) ─► Settlement ─► equity(...) ─► tables/figures
 (centralized: dispatch_record(ctx) from ctx.meta[:agg_net], :device_p_inject)
```

Default path (`WelfareObjective`, `SerialExecutor`, 1:1 slots, `:default` population) executes the same statements in the same order as today.

---

## 5. Risks to goldens / canary (hard constraints: never re-pin the knife-edge canary or goldens)

| Change | Risk | Mitigation |
|---|---|---|
| `_admm_iterate!` AGR loop → `_agr_sweep!` | Reordering/float-order change moves iters=56 / welfare −4823.66604824162 (`test_admm_knifeedge_canary.jl`) | `SerialExecutor` method is the old loop verbatim; threaded path only commits serially; add equality tests Serial==Threaded; run canary first after Phase 1. |
| Slots generalization (`DsoOpt` axis, `q_draw`, guards) | `DenseAxisArray` indexed by slot id vs bus id; objective term order in `sum(pag_dso[j,t]^2 …)` (`DsoOpt.jl:475`) changes Clarabel input ordering ⇒ different iterates | Iterate slots in the same ascending order; when 1:1, assert the built `MOI` objective/variable order equals legacy (compare `num_variables`, objective terms, `Clarabel` iter count on IEEE-13). Keep a legacy-guard test for the 1:1 error messages. |
| `agr_objective` hook | `ctx.objective − …` vs `agr_objective(...) − …` could change QuadExpr term order | `WelfareObjective` must return the very same object (`===`) and not wrap/copy. |
| Extra keys in `_admm_certify` NamedTuple / `Aggregator.contribute!` return | Tests destructuring positionally or asserting `keys` | grep tests first; add keys at the end only. |
| `Scenario` new selectors / `ADMM` new field | `==`/`hash`/`scenario_filename` changes invalidate stored-run identity and tests comparing filenames | Conditional keys in `_scenario_identity` (precedent `pf_ε`); `executor` excluded from identity; `Scenario` inner constructor positional signature used in `with_strategy` (`Scenario.jl:355-368`) — add fields last with outer-constructor defaults, and update `with_strategy`, `==`, `hash` together. |
| Trait refactor for reactive probes | `_any_flexible_reactive` semantics shift ⇒ default `ReactiveMode` flips for existing populations | New trait defaults reproduce the old predicate exactly (`FourQuadBESS`→true, `is_flexible_load`→true); test equality of resolved mode over existing fixtures. |
| New devices with `is_flexible_load=true` | Populations with EV/HP resolve to LIVE ⇒ different (new) path, not a regression | Document; keep unity-pf EV off the trait. |
| `ACPowerFlow`/exactness for settlement re-dispatch | Laundering inexact points as priced results | Report-vs-throw: attach certificate/status to `Settlement`; never raise `atol_exact` (`solve_dso!` seam is for independently measured floors only). |
| 8500 headline | Gate refusal (CertificateError, ratio 568.95 at d=0.1 T=10) | Headline script catches `CertificateError` and *records* the refusal + `iterations` field; do not weaken the hybrid floor; report as the finding. |
| Test-suite hygiene (memory notes) | New `@testitem` scratch files under repo counted by `Pkg.test()`; `try x=…` scoping in `@testitem`; `--project=.` TestItemRunner trap | Keep scratch outside repo; wrap in functions; use `Pkg.test()` entrypoint. |
| `public`/export lists | `test_exports.jl` and `docs/src/api.md` enumerate API | New types: decide exported vs `@compat public` (advanced: executors, slots, record) and update the tests/docs in the same plan. |

---

## 6. Suggested build order (respecting dependencies)

Dependency sketch: `P1 (compute/commit + executor + additive result keys)` → `P5 (slots/actors)`; `P2 (population+houses)` → `P3 (settlement)` → `P7 (flex market)`; `P4 (devices)` independent; `P6 (8500)` needs P1; `P8 (Case A magnitude)` needs P2+P3 (+P5 optional).

1. **Phase 1 — Parallel-ready ADMM, zero behaviour change.** Compute/commit split, `AbstractAgrExecutor` (+ threaded build), error unwrapping, additive `_admm_certify` keys (`pag`, `util`, `p_import`), widen `Scenario` feeder tuple to the 8500 selectors, `executor` on `ADMM` (excluded from identity). Gate: canary + full suite bit-identical; Serial==Threaded equality tests. *Standard patterns; low research need.*
2. **Phase 2 — Population & houses.** `Population`/`HouseRef`, `:thesis_caseA` selector, per-house `sub_seed`, `device_p_inject` stash, `granularity` option. Centralized + ADMM at 784 for timing/memory. *Needs measurement, little research.*
3. **Phase 3 — Settlement & equity.** `DispatchRecord`, tariffs (`FIT` via `fit_baseline`, `Flat/TOU/Nodal/DADP`), `settle`, equity metrics, `run_with_record`. Report-vs-throw statuses. *Moderate research: tariff re-dispatch semantics; inexact-network evaluation via AC oracle.*
4. **Phase 4 — Devices** (can run in parallel with 3): `has_reactive_decision` trait refactor first (no behaviour change), then `EV`, `HeatPump`, `SmartInverterPV` (capability-cone version). *Volt-VAR droop = research flag.*
5. **Phase 5 — Actors.** 5a: slots + multi-actor per bus + grouping-only portfolios + `AbstractActorObjective` (Welfare/Profit) + behavioural wrappers; 5b (only if justified): `PortfolioAgrOpt`/`AbstractAgrBlock`. *Needs a short model-math research pass (equilibrium interpretation, weighted centralized cross-check).*
6. **Phase 6 — IEEE-8500 headline run.** First step is *measurement*: re-run `scripts/profile_ieee8500_memory.jl` with threaded build to attribute the 3.4 GiB unattributed delta (AGR models vs DSO per-hour state); only then decide on `HourSplitDsoOpt`. Deliverable is a measured table (solve time, iterations, exactness verdict) even if the gate refuses. *Deepest uncertainty; research flag.*
7. **Phase 7 — Flexibility market vs prices.** `AbstractCoordination`, `FlexMarket` redispatch model, comparison via Phase 3 settlement. *Research flag: market design, bid curves, uniform vs pay-as-bid.*
8. **Phase 8 — Case A magnitude re-attempt.** Experiment/literate page on the 784-house population using `fit_baseline` + `welfare_accounting` ratio (`_fit_ratio`, `welfare.jl:197`); report honestly (prior public-data result ≈ +0.26%, thesis ≈ +25%, App. E IP-blocked). Pure experiment; no new `src/` beyond what 2–3 provide.

## 7. Anti-patterns to avoid

- **Editing the default method bodies** (`_react_agr_solve!`, `build_agr_opt`, `solve_dso!`) to "also support" the new modes. Add new methods/types and dispatch; keep the default call sequence literal.
- **A `ProfitADMM` strategy / profit flag on `Aggregator`.** Wrong axis; squares the strategy matrix and entangles the physical roll-up with the agent's objective.
- **Multi-bus `Aggregator`.** Breaks the sole-writer seam (`add_to_residual!(…, agg.bus,…)`); portfolios belong in an `Actor` layer.
- **Threading the DSO solve or sharing models/dicts across tasks; `Distributed` for memory-bound scale.**
- **Computing settlement inside `welfare_accounting`/`solve_welfare`** (couples accounting to a solved centralized ctx and its identity gate).
- **Treating the exactness refusal at 8500 as a tolerance problem** (violates the certificate-laundering rule documented at `DsoOpt.jl:533-549`).
- **Deriving per-house seeds as `seed + bus`** (collisions) or using the global RNG.

## 8. Open questions for phase-level research

1. Memory attribution at 8500 (AGR resident models vs DSO per-hour state) — measure, don't guess.
2. Does per-house slot granularity change ADMM iteration counts materially vs per-node? (Convergence of more consensus pairs; adaptive-ρ residual normalization uses `p_p = length(load_nodes)*T`, `admm_phases.jl:197`, which would need to count slots.)
3. Profit objective: exact economic definition (retail revenue, compensation, utility weight) and the right centralized cross-check.
4. Volt-VAR droop convexification vs capability-cone approximation.
5. How `assert_battery_complementarity!` selects batteries (relevant to EV V2G); read `src/models/welfare_solve.jl`/`exactness.jl` before Phase 4.
6. Whether `tariff re-dispatch` with ρ→0 is well-posed for non-strictly-concave devices (PVBattery/Deferrable).

## Sources (all in-repo, read directly)

- `src/TSODSO.jl` (include graph 42-280); `src/admm/{admm_phases,admm_state,AgrOpt,DsoOpt,solve_admm}.jl`
- `src/devices/{AbstractDevice,Aggregator,PVBattery,Thermostatic}.jl`; `src/core/ModelContext.jl`
- `src/experiments/{strategies,Scenario,materialize,run,store}.jl`; `src/pricing/{welfare,fit}.jl`; `src/models/welfare_solve.jl`; `src/solver/factory.jl`
- `.planning/PROJECT.md`, `.planning/STATE.md` (8500 findings line 97), `scripts/thesis_caseA.jl`, `scripts/profile_ieee8500_memory.jl`, `test/test_admm_knifeedge_canary.jl` header
- Not verified by reading: Julia threading behaviour of Clarabel/JuMP model construction (inferred from architecture; confirm with a Serial==Threaded equality test), and the contents of tests that may assert exact key sets or error messages.

---
*Architecture research for: v5.0 Aggregator Layer at Scale*
*Researched: 2026-10-09*
