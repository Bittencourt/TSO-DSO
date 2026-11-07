# Phase 41: Settlement, Ledger & Equity - Context

**Gathered:** 2026-10-24
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommended answers auto-accepted per operator instruction)

<domain>
## Phase Boundary

A researcher can settle any run into a money-conserving per-actor ledger, compare tariff schemes on
the same network and population, and read equity and rebound outcomes. Deliverables: per-actor
settlement ledger (DSO, each aggregator, each household, wholesale) summing to zero with an explicit
merchandising-surplus line; FIT/TOU/flat/nodal-DADP tariff comparison on one network+population with
flat and TOU derived revenue-neutral from the DADP run; per-tariff AC-physics feasibility STATUS
(reported, never thrown); Gini/Theil/Atkinson/Palma equity metrics with known-value tests including
negative values, broken out by PV ownership, electrical location and load level, with an explicit
no-income-data statement; and a rebound metric (load shifted into later hours after price-driven
reductions). Requirements: SETL-01..SETL-06.

v5.0 policies bind: honesty policy (feasibility statuses and negative equity results are first-class
outcomes), golden policy (existing `welfare_accounting`/`fit_baseline` behavior untouched).

</domain>

<decisions>
## Implementation Decisions

### Ledger Structure & Money Conservation
- New `src/settlement/` module. A `SettlementLedger` over actors: DSO, each aggregator, each
  household (via Phase-40's `case_a_household_map` granularity and per-aggregator additive keys),
  and a wholesale/slack actor. Entries are per-hour price×quantity transfers settled from a single
  run's own prices and dispatch — conservation is exact by construction (every transfer has a
  paying and a receiving side from the same numbers).
- The merchandising surplus (DSO net revenue after per-actor settlements) is an EXPLICIT named
  ledger line, never silently absorbed into the DSO entry.
- Monetary units: the framework's existing welfare units (same as `welfare_accounting`), documented
  in the module docstring; no currency conversion is introduced.
- The sum-to-zero test asserts the identity on a real run fixture; `welfare_accounting`'s aggregate
  identity (social == prosumer + dso) remains untouched (golden).

### Tariff Comparison
- Tariffs are pure price-construction functions over one solved DADP run: `:fit` (existing
  `fit_baseline` path), `:dadp` (the run's own nodal duals), `:flat` and `:tou` DERIVED from the
  DADP prices revenue-neutrally — flat = load-weighted mean of the DADP settlement prices rescaled
  to match total DADP payments; TOU = fixed bin structure (e.g. peak/shoulder/off-peak by hour
  blocks) with bin levels fit revenue-neutral by the same weighted-mean-per-bin construction.
- Comparison harness: one runner that rebuilds dispatch per tariff on the SAME feeder + population
  (counterfactual solves under each tariff price vector) and emits a comparison table/CSV following
  the Phase-35/39 measurement-artifact pattern.
- `fit_baseline` and `welfare_accounting` are consumed, not modified (golden).

### AC Feasibility Status (report, never throw)
- Per tariff's resulting dispatch: settle with the Phase-27 physics-only idiom —
  `ACPowerFlow(; limits = false)` on the fixed dispatch, then evaluate thermal/voltage limits as
  DIAGNOSTICS into a status struct (`:feasible` / violation list with branch/hour/quantity), never
  a throw. Reuses the existing report-don't-throw pattern from the MPC truth-import/FIT SITE-2 path.

### Equity Metrics & Rebound
- Gini, Theil, Atkinson, Palma implemented over per-household bill/surplus vectors with known-value
  unit tests including NEGATIVE values (define the metric conventions for negative surplus
  explicitly in docstrings — income-inequality formulas applied to surplus with stated conventions;
  Atkinson restricted to the positive-support subset with the exclusion reported).
- Breakouts: PV owner vs non-owner (household map), electrical location (bus grouping), load level
  (terciles of baseline consumption) — all from the household map, no new data.
- The writeup states explicitly that NO income data is used (bills/surplus only).
- Rebound metric: for hours after a price-driven reduction hour, measure load shifted into later
  hours relative to the counterfactual baseline profile; reported per run as a single number plus
  per-hour detail. Deferrable-load shifts and battery-driven shifts are both captured by the same
  net-load definition; the definition is documented.

### the agent's Discretion
- Module file layout within `src/settlement/`, exact metric edge-case conventions (documented),
  CSV column layouts, and comparison-harness naming within the established patterns are at the
  agent's discretion.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/pricing/welfare.jl` — `welfare_accounting` (prosumer/DSO surplus split, surplus-identity
  correctness net, throws on out-of-band surplus) — the aggregate-level settlement the ledger
  refines per actor; consumed untouched.
- `src/pricing/fit.jl` — `fit_baseline` (FIT counterfactual dispatch) — the `:fit` tariff leg.
- Phase-40 assets: `:case_a_784` population, `case_a_household_map` (house → bus, aggregator,
  device set, PV group), per-aggregator additive result keys (`agr_dispatch/utility/import/prices`).
- Phase-27 physics-only settlement idiom: `ACPowerFlow(; limits = false)` + diagnostics reporting
  (MPC truth import, FIT SITE-2) — the never-throw feasibility status template.
- DLMP extraction (`extract_dlmp`) and the ADMM result NamedTuple (welfare, dadp prices, per-slot λ).
- Measurement-artifact pattern: committed CSVs + dated literate sections (Phase-35/39/40).

### Established Patterns
- Honesty policy: statuses and negative results reported, never thrown away or loosened.
- Golden policy: existing pricing/accounting paths byte-identical; new module additive.
- Known-value tests for any new mathematical regime (v3.0 standing bar: each new metric gets its
  own certificate/known-value gate — no tolerance laundering).
- Julia test invocation: `julia --project=. -e 'import Pkg; Pkg.test()'` only.

### Integration Points
- `solve_welfare` / `solve_admm` run outputs → settlement input.
- Tariff counterfactual re-solves (dispatch under alternative price vectors) — the welfare solve
  accepts price-modified scenarios; the experiments harness materializes scenarios.
- `src/experiments/` sweep/store machinery for the comparison artifacts.
- Household map + per-aggregator keys for per-household attribution.

</code_context>

<specifics>
## Specific Ideas

- Revenue-neutrality of flat/TOU derivations is the comparison's fairness condition — the rescaling
  must be tested (total payments under derived tariff == total payments under DADP on the same run).
- The thesis context (PhD settlement/equity analysis) wants per-household bills as the primary
  artifact — the ledger's household level is the deliverable researchers read.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
