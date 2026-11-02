# Phase 44: Aggregator as Actor - Context

**Gathered:** 2026-11-02
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers three things:
- A per-aggregator **actor objective**: social welfare (the default, unchanged) or profit with a retail
  wedge.
- **Multi-bus portfolios**, with ADMM consensus keyed by an (actor, bus) slot.
- **Exogenous, seeded behavioural scenarios**: partial compliance, opt-out and rebound.

Their effects on welfare, prices and settlement are reported. Reported `welfare` is always social
welfare.

The single-bus, welfare-objective default path stays byte-identical to v4.0.

Out of scope (REQUIREMENTS.md Future/Out of Scope):
- strategic, bilevel or tariff-menu aggregators (ACTOR-F1);
- portfolio-coupled AGR subproblems with shared cross-bus constraints (ACTOR-F2);
- endogenous participation or opt-out equilibrium (ACTOR-F3);
- binaries;
- EPEC or market power.

</domain>

<decisions>
## Implementation Decisions

### Profit Objective & Wedge (ACTOR-01/02)
- **Where the objective lives:** a new `AbstractActorObjective` hierarchy, with `WelfareObjective` as the
  default and `ProfitObjective(wedge)`. It is selected per aggregator or actor through an additive
  keyword on `solve_admm` and `solve_welfare`. It is **not** a field on `Aggregator` and **not** a new
  `AbstractStrategy` (research ARCHITECTURE.md §3.3 calls those the wrong axis).
  - The welfare objective must leave the AGR build bit-identical: the accumulator `===` `ctx.objective`.
- **The wedge:** an additive retail margin `m_t`, either a scalar or an hourly vector. Customers' devices
  respond to `λ + m`, which is a linear term on `pag`, so the problem stays convex and the per-iteration
  ADMM lever is unchanged.
  - Aggregator profit `Σ_t m_t · load_t` is reported.
  - With `m = 0` the problem is exactly the welfare problem.
  - Document honestly that this is a *weighted objective inside the same price-taking equilibrium*.
    It is not a strategic aggregator: there is no market power and no Stackelberg game against the DSO
    price. The first-welfare-theorem framing is in research FEATURES.md insight 1.
- **Efficiency loss:** `ΔW = W_opt − W_social(profit dispatch)`, reported both absolute and relative.
  `W_social` is always computed from device utilities − `λ₀ᵀp_import`, which is the existing welfare
  definition. Actor profit is a separate line in the Phase-41 `SettlementLedger`.
- **Pass-through test:** `ProfitObjective(m = 0)` must reproduce the welfare optimum on **both** the
  centralized and the ADMM paths, within a **measured** tolerance.
  - The centralized side gets an objective hook on `Aggregator.contribute!` through a new keyword. The
    default path stays bit-identical.
  - Each non-default objective is cross-validated centralized-vs-ADMM before it is used under ADMM.
    This follows the DEV-10 pattern from Phase 43.

### Multi-Bus Portfolio (ACTOR-03)
- **Representation (grouping only):** an `Actor`/`Portfolio` is a set of ordinary single-bus site
  `Aggregator`s. `Aggregator` stays single-bus, because `agg.bus` is the sole `:Rp/:Rq` writer
  (`Aggregator.jl`, `add_to_residual!`).
  - The ADMM coupling axis becomes a **slot** keyed by (actor, bus): one consensus pair
    `(pag_s, pag_dso_s)` per slot.
  - The portfolio-coupled AGR model (`PortfolioAgrOpt`, ACTOR-F2) is deferred.
- **Several actors per bus are allowed.** The slot table lets several slots share a bus, and they all
  inject into that bus's `:Rp` and share its nodal price.
  - DADP is still published per bus, with shape `(n_load_nodes, T)`, ascending.
  - A new slot-λ agreement certificate (`max_s |λ_s − λ_bus| ≤ tol`) reports and never throws, per the
    status policy. Per-slot λ is exposed additively.
- **Byte-identity:** the legacy `Vector{Aggregator}` input with no actors runs the unchanged code path,
  and the existing ADMM goldens stay untouched.
  - A new bitwise test checks that "each site is its own actor" equals the legacy result.
  - In the 1:1 case, slot id equals bus id. The legacy guard error messages stay on the legacy path.
- **Objective attachment:** at actor level. The same `ProfitObjective`/wedge applies to all of the
  actor's sites, and profit is summed per actor in the ledger. There is no per-site override.

### Behavioural Scenarios (ACTOR-04)
- **Representation:** wrapper devices (`PartialCompliance`, `OptOut`, `Rebound`) that satisfy the
  existing device contract.
  - They are applied once by a seeded, opt-in population transform,
    `BehaviourSpec(; compliance, opt_out, rebound, seed)`.
  - There are no binaries and nothing changes inside the solves. Seeding uses SplitMix64, as in Phase 43
    `_flex_mix`, and **not** `Base.hash`.
- **Semantics:**
  - *Partial compliance* ξ ∈ [0, 1]: a device follows the fraction ξ of its deviation from a no-response
    baseline. The baseline comes from the existing FIT counterfactual (`fit_baseline`) and is computed
    once at transform time, never in the loop.
  - *Opt-out*: a seeded fraction of houses is fixed to that baseline. This is exogenous; the endogenous
    participation equilibrium is ACTOR-F3.
- **Rebound:** a convex, linear energy-recovery constraint. Energy curtailed relative to the baseline
  must be recovered within a window `W` at a factor `r ≥ 1`. The Phase-41 `rebound` metric
  (`src/settlement/equity.jl`) is also reported.
- **Reporting:** a sweep harness over (ξ, opt-out, r) on one fixture. It writes:
  - a committed CSV with welfare, DADP mean and max, settlement-ledger totals per actor, and the rebound
    metric;
  - a literate docs page.

  This follows the Phase 35/39/40 measurement-artifact pattern.

### Validation, Fixtures & Integration
- **Fixtures:** IEEE-13 for the unit, pass-through and cross-validation tests, and IEEE-123 for the
  behavioural sweep. `:case_a_784` is used only for centralized measurement, if at all, because its
  ADMM ladder takes about 900 s per rung.
- **Solve paths:** centralized `solve_welfare` and `solve_admm` support actors, objectives and behaviour.
  MPC, stochastic and FIT reject non-default inputs with an `ArgumentError` guard, mirroring
  `_reject_unsupported_flex_devices` in `src/pricing/fit.jl`.
- **`Scenario` stays untouched.** The features are available through the programmatic API only (solve
  keywords plus the population transform), consistent with Phase 43.
- **Welfare honesty:** every new result carries three things:
  - `welfare`, which is social welfare;
  - the actor objective value, as a separate field;
  - `ΔW` against the welfare optimum.

  A test asserts that profit-dispatch social welfare ≤ the welfare optimum, which is flagged as
  impossible if violated (research PITFALLS.md C7 detection).

### Claude's Discretion
- Module and file layout: for example `src/admm/actor_objective.jl` and `src/actors/`. The slot-table
  data structure, exact keyword names, CSV columns and the sweep grid values are at Claude's discretion,
  within the established patterns.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/admm/AgrOpt.jl`: `build_agr_opt` (line ~134). The objective accumulator built from
  `ctx.objective` minus the ρ-penalty is the single hook point for `agr_objective(obj, U, pag, T)`.
- `src/devices/Aggregator.jl`: `contribute!(agg, ctx; T)` (line ~159). The centralized objective hook
  is a new keyword on a new method, and the default stays unchanged.
- `src/admm/admm_phases.jl`:
  - `_admm_build` (line ~36) holds the 1:1 guards: `length(aggregators) == length(load_nodes)` and
    duplicate-bus checks. These become slot-table checks on the new path only.
  - `_admm_certify` publishes `dadp` and `welfare`.
- `src/admm/DsoOpt.jl`: `pag_dso[j = load_nodes, t]` (line ~419) is injected into `:Rp[j]`. It becomes
  slot-indexed, with `:Rp[bus(s)]`, on the new path only.
- `src/admm/admm_state.jl`: `AdmmState.agr_by_bus::Dict{Int,AgrOpt}` and `load_nodes`. Keep the field
  name, keyed by slot id, and add `slot_bus` (identity when 1:1).
- `src/settlement/`: `SettlementLedger` / `build_settlement_ledger` / `ledger_residual`,
  `price_taker_dispatch`, `equity.jl` `rebound`, and the tariffs and comparison harness (Phase 41).
- `src/pricing/fit.jl`: `fit_baseline` (the no-response baseline) and
  `_reject_unsupported_flex_devices` (the guard template).
- `src/experiments/materialize.jl`: `build_population` (line ~780), the opt-in `flex_devices` keyword
  pattern, and the `_flex_mix` SplitMix64 seeding.

### Established Patterns
- Golden policy: the default path is byte-identical, and goldens and gates are never re-pinned or
  loosened. New features are opt-in keywords with a full-field digest fence on the default.
- Honesty policy: tolerances are measured, never picked; certificates report and never throw; refusals
  are reported.
- New device classes and new objectives are cross-validated against the centralized solve before ADMM
  use (DEV-10).
- Measurement artifacts are committed CSVs plus dated literate docs pages, registered in
  `docs/make.jl` and `scripts/README.md`.
- Tests are `@testitem` in `test/test_*.jl`, run with targeted
  `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=...`. Avoid `try x = ...` and outer-variable reassignment in
  for-loops inside test items.
- Exports go through the curated list in `src/TSODSO.jl`, mirrored in `test/test_exports.jl`.

### Integration Points
- `solve_admm` → `_admm_build` → `build_dso_opt` / `build_agr_opt`: takes the actors, slots and
  objective keywords.
- `solve_welfare` → `contribute!`: takes the objective hook.
- The settlement ledger gains the actor-profit line, and the sweep harness consumes the ledger.
- The population transform (`BehaviourSpec`) sits next to `build_population`.

</code_context>

<specifics>
## Specific Ideas

- The pass-through identity (`m = 0` ⇒ welfare optimum) is the liveness test for the profit objective.
  Without a wedge the result is null by design (first welfare theorem), and the docs must say so.
- Watch for constant offsets when comparing objectives (PITFALLS.md M4, the Deferrable +18 precedent).
  Compare social welfare recomputed from utilities, not raw objective values.
- Adaptive-ρ residual normalization uses `p_p = length(load_nodes)*T`. Under slots it must count slots,
  and must stay unchanged when 1:1.

</specifics>

<deferred>
## Deferred Ideas

- ACTOR-F1: a tariff-menu (strategic) aggregator chosen by outer enumeration, labelled a lower bound.
- ACTOR-F2: a portfolio-coupled AGR subproblem (`PortfolioAgrOpt`, shared fleet constraints).
- ACTOR-F3: an endogenous participation equilibrium (an outer fixed point on opt-out).
- Additive `Scenario` fields for actors and behaviour, so the run/sweep harness can drive them.
- House-level slot granularity (`granularity = :house`) for parallelism. Its effect on ADMM iteration
  counts is unmeasured.

</deferred>
