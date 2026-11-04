# Phase 45: Flexibility Market vs Price Coordination - Context

**Gathered:** 2026-11-03
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase adds a **DSO flexibility market** as an alternative coordination scheme to price-based
(DADP) coordination. It has:
- an explicit baseline;
- an explicit payment rule, either uniform or pay-as-bid;
- the **same settlement record** as the Phase-41 tariff legs (SETL-07);
- a **comparison table** reporting welfare, per-actor surplus, AC network feasibility and equity
  across FIT, TOU, flat, DADP and the flexibility market on the same scenario (SETL-08).

The flexibility market is a coordination alternative, not a settlement variant (research
ARCHITECTURE.md §146). The phase is additive: the default `compare_tariffs` output, every solve
default, the goldens and the knife-edge canary stay byte-identical.

Out of scope:
- aggregate-flexibility polytope bids and equity compensation mechanisms (SETL-F1);
- indivisible or binary bids;
- strategic bidding beyond the exogenous baseline-inflation sensitivity;
- market power or EPEC;
- `Scenario` fields (programmatic API only, as in Phases 43 and 44).

</domain>

<decisions>
## Implementation Decisions

### Market Formulation (SETL-07)
- **API:**
  - `abstract type AbstractCoordination` with `PriceBased`, which is the existing DADP coordination,
    and `FlexMarket(; baseline_tariff = :flat, payment_rule = :uniform, n_blocks = 4, baseline_inflation = 0.0)`.
  - The keyword names are final; the internal layout is at Claude's discretion.
- **Two stages:**
  1. **Baseline (stage 1).** Each aggregator solves price-taker against the baseline retail tariff.
     The default is the revenue-neutral flat tariff (`flat_prices`, the same derivation as the
     existing flat leg); TOU is allowed. Use the `price_taker_dispatch` seam. That schedule is the
     baseline `b`.
  2. **DSO redispatch (stage 2).** A redispatch on the **same feeder, power-flow model (SOCP) and
     exactness gate** as the DADP run. Variables: the activated up and down quantities per
     aggregator, hour and block. Objective: minimise the cost of accepted bids plus the wholesale
     import cost `λ₀ᵀ p_import`. The network constraints are the existing `contribute!(pf, ctx, feeder)`
     and `close_balance!` seam, so there is no new network formulation.
- **Bids:**
  - Divisible, piecewise-linear, **hour-separable** blocks: `n_blocks` up and `n_blocks` down per
    aggregator per hour, 4 each by default.
  - Each aggregator generates them by **probing its own model**: single-hour perturbation re-solves
    around the baseline, with the other hours held at baseline.
  - Each block is a quantity and a price, giving a convex (non-decreasing marginal cost) curve. Bids
    are truthful by default: the cost is the aggregator's own utility loss.
  - Bid generation runs once per market clear, never inside an ADMM loop.
- **Delivery:**
  - Hour-separable bids lose intertemporal coupling (battery SOC, deferrable energy, EV and heat-pump
    state). So each aggregator **re-solves to follow its activated targets**: a tracking re-solve on
    its own devices, with a measured or documented penalty.
  - The **delivered dispatch** is what gets settled, welfare-evaluated and AC-checked.
  - The per-aggregator and per-hour delivery shortfall `|delivered − (b + Δ)|` is **reported, never
    hidden**.
- **Infeasibility:** if the offered flexibility cannot restore network feasibility in stage 2, the leg
  is a **status row** (for example `infeasible_redispatch`), never a crash and never a re-tune. This
  follows the honesty policy.
- **Solvers:** Clarabel for the redispatch SOCP and the QP re-solves, through the existing solver
  factory. Never hard-code a solver.

### Payment Rule & Settlement (SETL-07)
- **Both rules, every scenario:**
  - **Uniform:** activated flexibility at (bus, hour) is paid the **clearing price**, the dual of the
    stage-2 nodal balance at that bus and hour, in the existing `dual(balance)` sign convention.
  - **Pay-as-bid:** each activated block is paid its own bid price × quantity.
  - The dispatch is identical between the two rules; only the money differs.
- **Settlement record:** reuse the Phase-41 `SettlementLedger` and `build_settlement_ledger`, or a thin
  adapter onto it.
  - Households and aggregators pay the **baseline tariff on metered (delivered) energy**.
  - The DSO pays wholesale λ₀ on import.
  - The DSO pays aggregators the **flexibility payments**. These are booked as mirrored transfer pairs,
    the 44-06 actor-wedge pattern, so `ledger_residual == 0.0` exactly.
  - The merchandising-surplus line is kept.
  - The output uses the same per-actor totals and summary-row schema as the other legs (SETL-07, "same
    settlement record").
- **Conservation test:** a test asserts `ledger_residual == 0.0` and that the actor totals sum to zero
  for both payment rules.

### Baseline Gaming Sensitivity (research PITFALLS M5)
- **Opt-in `baseline_inflation = β`:** the *reported* baseline is the true baseline × (1+β) on the
  up-direction in **congested hours**, where congestion is defined from the stage-2 binding constraints
  or the clearing-price spread. The exact definition is at Claude's discretion and must be documented.
- β changes **payments only, never physics**: the dispatch, welfare and AC feasibility are those of
  the truthful clear.
- Each row reports the overpayment against the true baseline.
- The sweep is β ∈ {0, 0.05, 0.10}. The default is β = 0, a truthful baseline.

### Comparison Table & Artifacts (SETL-08)
- `compare_tariffs` gains an opt-in keyword, `flex_market = nothing`, which takes one or more
  `FlexMarket`s.
  - It appends flex-market rows to the **same summary DataFrame schema** as the dadp, flat, tou and fit
    legs. The `tariff` column holds `flex_uniform`, `flex_pab`, and the β variants.
  - **With the default `nothing`, the output is byte-identical to today.** Pin this with a digest or
    equality fence against the pre-change output.
- Every flex row reports:
  - welfare, which is **always social welfare** computed from the delivered dispatch (device utilities
    − `λ₀ᵀ p_import`, the existing definition);
  - per-actor surplus and totals from the ledger;
  - the AC `FeasibilityStatus` via `ac_feasibility_status`, recorded and never a gate;
  - the equity metrics on bills and surplus, at the same granularity rules as the other legs;
  - the delivery shortfall and the β overpayment.

  Add any new columns additively; never drop or reorder the existing ones.
- **Fixtures:**
  - **IEEE-13** (`ieee13-ground` mode) for the tests and the primary measurement. There, flat and TOU
    fail AC feasibility and DADP has a branch at 0.989 of its limit, so redispatch has congestion to
    relieve.
  - **Also an IEEE-123 measurement row set** (user decision 2026-11-03): a new script mode, for
    example `ieee123`. Wall time is measured and reported; a timeout or refusal is a recorded outcome.
- **Artifacts:**
  - upserted rows in the committed `results/settlement_comparison/tariff_comparison.csv` (`cols = :union`,
    with provenance), written through `scripts/tariff_comparison.jl` with a `--flex-market` flag or the
    new modes;
  - a new literate docs page registered in `docs/make.jl` and `scripts/README.md`.
- **Expected result, to be stated honestly whatever is measured:**
  - Under uniform pricing with truthful divisible bids, flex-market welfare should match DADP up to
    the bid-discretisation and hour-separability gap (FEATURES insight 2, the first-welfare-theorem
    analogue).
  - Pay-as-bid should give the same dispatch but move money from aggregators to the DSO.
  - Report the measured gap. If the gap is null, say so.
- FIT's existing `error:SolveFailedError` row on IEEE-13 stays as recorded and is never back-filled.

### Validation
- Tolerances are measured (3x the observed max over seeds), never picked.
- Certificates report and never throw.
- Cross-validate the flex-market clear against the centralized welfare optimum on a small fixture:
  - the uniform-price welfare gap is within the measured discretisation gap;
  - with exact-cost (many-block) bids, the gap shrinks toward zero. This is the liveness check.
- The redispatch duals are cross-checked against the DADP prices where both are defined.
- Tests are `@testitem` in `test/test_flex_market*.jl`, run with targeted
  `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=...`. IEEE-123 items are `:slow`.
- Exports go through the curated list in `src/TSODSO.jl`, mirrored in `test/test_exports.jl`. The JET
  ratchet must not grow from phase-45 code.

### Claude's Discretion
- The file layout (for example `src/coordination/` or `src/settlement/flex_market.jl`) and the
  internal struct layout.
- The probe step sizes, the block-quantity spacing and the tracking-penalty weight. Measure them and
  document them.
- The congested-hour definition for β.
- The CSV column names for the new fields and the script flag names.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/settlement/comparison.jl`:
  - `compare_tariffs` (line ~249), with legs dadp, flat, tou and fit;
  - `_summary_row` (line ~121), the full column set;
  - `_rows_to_dataframe`, `_equity_columns`.
- `src/settlement/price_taker.jl`: `price_taker_dispatch`, `price_taker_dispatches` and
  `household_dispatches`, which give the per-aggregator and per-house dispatch at given prices
  (stage 1, probing and delivery).
- `src/settlement/tariffs.jl`: `flat_prices`, `tou_prices`, `revenue_neutral_flat` and
  `revenue_neutral_tou` (the baseline tariffs).
- `src/settlement/SettlementLedger.jl` and `run_inputs.jl`:
  - `SettlementLedger`, `build_settlement_ledger(...; actor_wedges)`;
  - the mirror-pair pattern (`_push_transfer_pair!`, `actor_wedge_rows`);
  - `ledger_residual`, `settlement_input`.
- `src/settlement/feasibility.jl`: `ac_feasibility_status` and `FeasibilityStatus`.
- `src/settlement/equity.jl`: gini, theil, atkinson, palma, `equity_breakdown` and `rebound`.
- `src/models/welfare_solve.jl` (`solve_welfare`) and `src/admm/DsoOpt.jl` (`build_dso_opt`): the
  network-constraint seam (`contribute!(pf, ctx, feeder)`, `close_balance!`) and the `dual(balance)`
  price reading.
- `scripts/tariff_comparison.jl`: the modes `ieee13-ground` and `case-a-784`, and the CSV upsert
  idiom with provenance.
- `src/actors/` (Phase 44), for reference: the opt-in keyword pattern and the default-path digest
  fence.

### Established Patterns
- Golden policy: the default path is byte-identical, and goldens and gates are never re-pinned or
  loosened. New features are opt-in keywords with a digest fence.
- Honesty policy: tolerances are measured, never picked; certificates report and never throw;
  refusals and failures are status rows; null results are stated as null.
- Measurement artifacts are committed CSVs plus dated literate pages.
- New formulations are cross-validated against the centralized solve (the DEV-10 pattern).
- Executors never run the full suite (the orchestrator does) and never `git checkout -- .`, reset or
  stash.

### Integration Points
- `compare_tariffs(...; flex_market)` takes stage 1 from `price_taker_dispatch`, then the
  stage-2 redispatch, then delivery re-solves, then the ledger, then `ac_feasibility_status`, then
  equity, then the summary rows.
- `scripts/tariff_comparison.jl` writes the CSV rows, and the literate page consumes the CSV.

</code_context>

<specifics>
## Specific Ideas

- The ieee13-ground finding from Phase 41 makes this phase non-vacuous: flat and TOU dispatch fail AC
  feasibility (`solve_failed`), while DADP is feasible at an overload ratio of 0.989. A flat-baseline
  flexibility market has to fix that.
- Compare **social welfare recomputed from utilities**, never raw objective values: the constant
  offsets from PITFALLS.md M4 apply.
- The payment-rule difference is what makes the DADP comparison non-trivial (FEATURES insight 2).
  The literate page must state the first-welfare-theorem framing.
- State known limitations in the docs:
  - baseline manipulation, quantified by the β rows;
  - the loss of hour-separability, quantified by the delivery shortfall;
  - truthful bidding as an assumption.

</specifics>

<deferred>
## Deferred Ideas

- SETL-F1: aggregate-flexibility polytope bids, which keep intertemporal coupling in the bid;
  equity compensation mechanisms.
- Strategic bid shading or markups (beyond the exogenous β), and a market-power analysis.
- Additive `Scenario` fields for coordination schemes.
- A `case-a-784` flex-market leg (blocked by the Case A ADMM `CertificateError` recorded in Phase 41).

</deferred>
