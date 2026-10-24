# Phase 41: Settlement, Ledger & Equity - Research

**Researched:** 2026-10-24
**Domain:** Per-actor settlement ledger, tariff counterfactual comparison, AC-feasibility status reporting, distributional (equity) metrics and rebound measurement over a solved DSO⇄aggregator run (Julia/JuMP codebase)
**Confidence:** HIGH (codebase seams read directly; equity-metric conventions literature-grounded; no external packages involved)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
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
- Tariffs are pure price-construction functions over one solved DADP run: `:fit` (existing
  `fit_baseline` path), `:dadp` (the run's own nodal duals), `:flat` and `:tou` DERIVED from the
  DADP prices revenue-neutrally — flat = load-weighted mean of the DADP settlement prices rescaled
  to match total DADP payments; TOU = fixed bin structure (e.g. peak/shoulder/off-peak by hour
  blocks) with bin levels fit revenue-neutral by the same weighted-mean-per-bin construction.
- Comparison harness: one runner that rebuilds dispatch per tariff on the SAME feeder + population
  (counterfactual solves under each tariff price vector) and emits a comparison table/CSV following
  the Phase-35/39 measurement-artifact pattern.
- `fit_baseline` and `welfare_accounting` are consumed, not modified (golden).
- Per tariff's resulting dispatch: settle with the Phase-27 physics-only idiom —
  `ACPowerFlow(; limits = false)` on the fixed dispatch, then evaluate thermal/voltage limits as
  DIAGNOSTICS into a status struct (`:feasible` / violation list with branch/hour/quantity), never
  a throw. Reuses the existing report-don't-throw pattern from the MPC truth-import/FIT SITE-2 path.
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
  CSV column layouts, and comparison-harness naming within the established patterns.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SETL-01 | Settle any run into a per-actor ledger (DSO, each aggregator, each household, wholesale); test verifies money conservation (actors sum to zero, explicit merchandising-surplus line) | Ledger input adapters for both run kinds: centralized `solve_welfare` ctx (`ctx.meta[:agg_net]`, `ctx.meta[:p_import]`, `extract_dlmp`) and converged ADMM result (`dadp`/`agr_dispatch`/`agr_utility`/`agr_prices`, `dso_ctx.meta[:p_import]`; guard `status == :converged`). Double-entry transfer construction from `welfare_accounting`'s algebra (transfer = Σ λ_j·net_j cancels prosumer/DSO; MS = DSO nodal collections − wholesale payment). Per-household split via price-taker separability (Pattern 2). |
| SETL-02 | Compare FIT/TOU/flat/nodal-DADP on same network+population, flat & TOU derived revenue-neutral from DADP run | `:fit` = `fit_baseline` as-is (golden); `:dadp` = the run itself; `:flat`/`:tou` = pure price-construction + a new thin price-taker dispatch builder in `src/settlement/` (Pattern 1 — mirrors `_fit_opt_solve`/`build_agr_opt`, no ρ penalty). Revenue-neutrality is algebraically exact with quantity-weighted means over the DADP run's own quantities (Pattern 3). |
| SETL-03 | AC feasibility of each tariff's dispatch reported as status, never thrown | `ACPowerFlow(; limits = false)` + violations-as-diagnostics template already exists verbatim in `_fit_ac_settlement_violations` (`src/pricing/fit.jl:746`) and `_mpc_settlement_violations` (`src/experiments/mpc_loop.jl`); wrap into a status struct (`:feasible` / violation list). |
| SETL-04 | Gini/Theil/Atkinson/Palma on per-household bills/surplus, sign-safe for negative values, known-value tests | Conventions resolved from the inequality-measurement literature (Pattern 5): Gini = mean-absolute-difference form over ALL values (relative-variability interpretation, may exceed 1); Theil & Atkinson = positive-support subset with exclusion reported; Palma = Σ(top 10%)/Σ(bottom 40%) (total cancels — most robust to negatives). Known-value anchors: uniform → (0, 0, 0, 0.25). |
| SETL-05 | Equity by proxy group (PV owner/non-owner, electrical location, load level); writeup states no income data | All groupings already in `case_a_household_map` rows (`bus`, `aggregator`, `pv_group`, `device_set`) + terciles of baseline consumption computable from the map/population. Writeup = the phase's literate/CSV artifact page (Phase-40 pattern). |
| SETL-06 | Rebound metric: load shifted into later hours after price-driven reductions | Baseline-vs-counterfactual convention grounded in DR measurement literature (snapback/rebound: smartEn position paper, CAISO DR AMM, Minnesota snapback study). Metric: reduction hours from Δ(Dispatch − Baseline) < 0, later-hour increases relative to the same baseline; single number + per-hour detail. |
</phase_requirements>

## Summary

Every seam this phase needs already exists and was read directly. The ledger's aggregate-level
algebra is `welfare_accounting` (`src/pricing/welfare.jl`): prosumer = Σ U_ag + Σ λ_j·net_j,
dso = −Σ λ_j·net_j − Σ λ₀·p_import, with the λ·net **transfer cancelling** between the two sides —
the per-actor ledger is a refinement of exactly this double-entry structure (each price×quantity
transfer recorded on both sides ⇒ sum-to-zero is exact by construction), and the merchandising
surplus is `welfare_accounting`'s `dso` split (nodal collections minus wholesale payment) made an
explicit named line. Two run kinds must be settled: a centralized `solve_welfare` `ModelContext`
(stashes `:agg_net` and `:p_import`; prices via `extract_dlmp`) and a converged `solve_admm`
NamedTuple (published `dadp == λ` matrix in ascending load-bus order, plus the PAR-05 additive keys
`agr_dispatch`/`agr_utility`/`agr_import`/`agr_prices` — present **only on the `:converged` path**).

The tariff comparison re-uses two existing counterfactual patterns without touching golden files.
`:fit` is `fit_baseline` unchanged. `:flat`/`:tou` need a **new thin price-taker dispatch builder**
in `src/settlement/`: at a FIXED price vector the per-aggregator problem (`Max U_ag + Σ_t p[t]·pag[t]`,
devices contributed verbatim via `contribute!`) is exactly the AGR-OPT subproblem minus the
ρ-penalty — `build_agr_opt`/`solve_agr!` prove the mechanism (prices are plain `Float64` vectors
installed by `set_objective_coefficient`; never JuMP `Parameter`s) but carry a fixed `−(ρ/2)·pag²`
term that would distort a price-taker optimum, so the settlement module mirrors the pattern rather
than reusing `solve_agr!`. Crucially, **at fixed prices the aggregator problem is separable across
member devices**, so per-household dispatch/bills are recoverable by re-solving each house's own
tiny QP at the same price and summing — verified against the per-aggregator keys within a measured
tolerance. Per-tariff AC feasibility then follows the Phase-27 physics-only idiom
(`ACPowerFlow(; limits=false)` + `_fit_ac_settlement_violations`-style per-hour diagnostics),
already written twice in this codebase.

The genuinely new mathematical regime is the equity metrics on possibly-negative per-household
surplus. Literature-grounded conventions (documented per metric, never silently zeroing/dropping):
Gini = standard mean-absolute-difference form over all values, interpreted as a relative
mean-difference measure (can exceed 1 with negatives); Theil and Atkinson restricted to the
positive-support subset with the exclusion count reported (both are non-computable for
non-positive values — this is the literature-standard treatment, and it is exactly what CONTEXT
locked for Atkinson); Palma = Σ(top decile)/Σ(bottom 40%), whose total cancels and is therefore
the most negative-robust of the four. Known-value anchors: identical vector ⇒ (Gini, Theil,
Atkinson, Palma) = (0, 0, 0, 0.25).

**Primary recommendation:** Build `src/settlement/` additively in five layers — (1) run-input
adapters (centralized ctx / converged ADMM result), (2) `SettlementLedger` double-entry
construction + merchandising-surplus line, (3) tariff price-construction (`:flat`/`:tou`
revenue-neutral from one DADP run) + price-taker dispatch builder, (4) AC feasibility status
wrapper, (5) equity metrics + rebound — with the comparison harness as a `scripts/` artifact
producer (committed CSV, Phase-40 pattern) and unit tests on the existing fast fixtures
(3-bus T=4 `FitFixtures`-style, 2-bus) plus the IEEE-13 ground fixture (T=24, `:slow` tag) for the
real-run settlement identity.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Ledger construction & conservation | `src/settlement/` (new, post-solve accounting) | — | Pure post-solve arithmetic over a run's own prices/quantities — mirrors `welfare_accounting`'s "accounting, not optimization" seam |
| Run output extraction (prices, dispatch, import) | Existing `extract_dlmp` / ADMM additive keys | `src/settlement/` adapters | Extraction is solved-path-owned (exactness-gated); the ledger only adapts/consumes |
| Tariff price construction (`:flat`/`:tou`) | `src/settlement/` (pure functions) | — | Pure arithmetic over one DADP run; no solver |
| Counterfactual dispatch under a price vector | `src/settlement/` (new thin QP builder) | existing `contribute!` device builders | Device models are owned by `src/devices/`; settlement only assembles Max U + Σ p·pag |
| `:fit` counterfactual | `src/pricing/fit.jl` `fit_baseline` (golden, consumed) | — | Locked decision: consumed, not modified |
| AC feasibility status | `src/settlement/` wrapper | `ACPowerFlow(; limits=false)` (`src/powerflow/`) | Physics model exists; settlement owns only the status struct |
| Equity metrics + rebound | `src/settlement/` (pure functions + known-value tests) | `case_a_household_map` (groupings) | v3.0 standing bar: each new metric gets its own known-value certificate |
| Comparison artifact (CSV + writeup) | `scripts/` + `results/` + `docs/literate/` | `src/experiments/` materialization idiom | Phase-35/39/40 measurement-artifact pattern; heavy runs stay out of the unit suite |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none — zero new packages) | — | Everything needed ships in the repo | Project keeps a minimal, pinned dep set; this phase is post-solve arithmetic + small QPs |

Existing (verified in `Project.toml` [VERIFIED: local Project.toml]): `JuMP 1.30.1` + `Clarabel 0.11.1`
(QP solves via `select_optimizer(QP())` factory — never name a solver), `Ipopt 1.15.0` (AC-PF NLP
via `select_optimizer(problem_class(ACPowerFlow()))`), `CSV 0.10.16` + `DataFrames 1.8.2`
(artifact CSVs), `DrWatson 2.19.1` (provenance stamps in scripts).

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Julia stdlib `Test` via TestItemRunner | (test env) | `@testitem` suite with `tags = [...]`, fast/slow split | All new tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-house Gini/Theil/Atkinson/Palma | an inequality-metrics package (e.g. InequalityMetrics.jl) | REJECTED: adds an unvetted dep; the project's v3.0 standing bar requires a known-value certificate per new metric anyway; conventions for negative values must be documented in OUR docstrings regardless. The four formulas are small, closed-form, and cheap to certify. |
| Reusing `build_agr_opt`+`solve_agr!` as the price-taker solve | new thin builder | `solve_agr!` carries a FIXED `−(ρ/2)·Σ pag²` penalty (production ρ=100 would materially shade a price-taker dispatch) and ADMM-specific certificate plumbing. A penalty-free mirror (~30 lines reusing `contribute!`) is cleaner and keeps ADMM files untouched. |
| Reusing `run(::Centralized/::ADMM, s)` for the comparison | direct `solve_welfare`/`solve_admm` calls | `ScenarioResult` normalizes away the ctx and the agr keys — the ledger needs the full outputs. Follow `run`'s `_materialize` sequence instead (same seed discipline), calling the solvers directly. |

**Installation:** none.

## Package Legitimacy Audit

No new external packages are installed by this phase (zero-dep design; all solver/artifact
infrastructure already pinned in `Project.toml`). Audit table is empty by construction — no
slopcheck run required. Any planner temptation to add a metrics/CSV helper package should be
resisted per the Alternatives table above.

## Architecture Patterns

### System Architecture Diagram

```
                       ONE solved DADP run (same feeder + population)
   ┌───────────────────────────────────────────────────────────────────────────┐
   │  centralized: solve_welfare → ctx          ADMM: solve_admm → NamedTuple  │
   │    prices = extract_dlmp(ctx)                dadp == λ  (n_load_nodes×T)  │
   │    stash  :agg_net, :p_import               agr_dispatch/utiliy/import/   │
   │                                             agr_prices  (per-bus Dicts)   │
   └───────────────┬───────────────────────────────────┬───────────────────────┘
                   │  run-input adapter                 │  (guard status==:converged)
                   ▼                                    ▼
        ┌─────────────────────────────────────────────────────────┐
        │  SettlementLedger (double-entry, per-hour price×qty)    │
        │   households ⇄ aggregator ⇄ DSO ⇄ wholesale             │
        │   MS line = DSO nodal collections − wholesale payment   │
        └───────┬──────────────────────────────┬──────────────────┘
                │                              │
                ▼                              ▼
   ┌──────────────────────────┐    ┌─────────────────────────────────────┐
   │ Tariff price construction│    │ Equity & rebound (pure functions)   │
   │  :flat / :tou revenue-   │    │  Gini/Theil/Atkinson/Palma on       │
   │  neutral from DADP run   │    │  per-household bills/surplus;       │
   └───────────┬──────────────┘    │  breakouts via household map        │
               │ exogenous p[t]    └─────────────────────────────────────┘
               ▼
   ┌──────────────────────────┐    ┌─────────────────────────────────────┐
   │ Price-taker dispatch     │    │ :fit  → fit_baseline (golden)       │
   │ QP per house/aggregator  │    │ :dadp → the run itself              │
   │ (Max U + Σ p·pag)        │    └─────────────────────────────────────┘
   └───────────┬──────────────┘
               │ fixed dispatch (net injections per bus)
               ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ ACPowerFlow(; limits=false) → per-hour thermal/voltage       │
   │ diagnostics → FeasibilityStatus (:feasible | violation list) │
   └───────────┬──────────────────────────────────────────────────┘
               ▼
   comparison table/CSV (scripts/ artifact, committed under results/)
```

Primary use case trace: solve DADP once → adapt to ledger input → `SettlementLedger` (sum-zero +
MS line) → derive flat/TOU prices → price-taker re-solves per tariff → AC status per tariff →
equity metrics on per-household bills + rebound vs counterfactual → comparison CSV.

### Recommended Project Structure
```
src/settlement/
├── SettlementLedger.jl   # actor/transfer types, double-entry construction, MS line, conservation
├── run_inputs.jl         # adapters: centralized ctx → ledger input; converged ADMM result → ditto
├── tariffs.jl            # :flat/:tou revenue-neutral price construction from a DADP run (pure)
├── price_taker.jl        # thin counterfactual dispatch QP (Max U + Σ p·pag) per aggregator/house
├── feasibility.jl        # ACPowerFlow(; limits=false) + diagnostics → status struct
└── equity.jl             # Gini/Theil/Atkinson/Palma + breakouts + rebound metric
test/test_settlement.jl   # (+ split as needed: test_settlement_ledger.jl, test_equity.jl, ...)
scripts/tariff_comparison.jl  # heavy :case_a_784 comparison → results/settlement_comparison/*.csv
docs/literate/settlement_equity.jl  # writeup incl. the no-income-data statement
```
All files declare their own `export`s (include-graph convention); register includes in
`src/TSODSO.jl`.

### Pattern 1: Price-taker dispatch under an exogenous price vector
**What:** the counterfactual dispatch for `:flat`/`:tou` legs. At a fixed price vector `p[t]`,
each aggregator (or each house) solves `Max U_ag(devices) + Σ_t p[t]·pag[t]` s.t.
`pag[t] == Σ_d p_inject_d[t] − Pdc[t]`, devices contributed verbatim via `contribute!`.
**When to use:** every non-FIT, non-DADP tariff leg.
**Why NOT `solve_agr!`:** it installs coefficient `−λ_j[t] − ρ·c_j[t]` AND carries the fixed
quadratic `−(ρ/2)·Σ pag²` from `build_agr_opt` — at the production `ρ = 100.0` that penalty
materially distorts a price-taker optimum, and its mid-loop `strict=false`/certificate plumbing is
ADMM-specific. [VERIFIED: direct read, `src/admm/AgrOpt.jl:173,308`]
**Example** (structural; follows `_fit_opt_solve` `src/pricing/fit.jl:155-245` and `build_agr_opt`
`src/admm/AgrOpt.jl:134-192`):
```julia
model = Model(select_optimizer(QP()))          # never name a solver
ctx   = ModelContext(model); ctx.T = T
res   = contribute!(agg, ctx; T = T)           # devices verbatim: p_inject, utility, vars
@variable(model, pag[1:T])
@constraint(model, coupling[t=1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])  # thesis 3.22
@objective(model, Max, ctx.objective + sum(p[t] * pag[t] for t in 1:T))
assert_solved!(model; dual = true)
assert_battery_complementarity!(ctx; τ = τ_batt, T = T; on_violation = :report)  # see Pitfall 1
net = value.(pag);  utility = value(ctx.objective)
```
Sign convention (matches `agr_prices` and `welfare_accounting`'s transfer): `p` is the PUBLISHED
price; a net exporter (`pag > 0`) EARNS `p·pag`, an importer PAYS.

### Pattern 2: Per-household attribution via fixed-price separability
**What:** at a FIXED price, the aggregator problem is the exact SUM of its members' problems
(the only coupling variable `pag` enters linearly and `Pdc` is additive). Re-solving each house's
own QP at the same price gives per-household dispatch and utility whose sums reproduce the
aggregator's — up to solver degeneracy ties (equal-objective alternate optima can split hours
differently house-to-house).
**When to use:** the ledger's household level, for EVERY tariff leg (including `:dadp` — re-solve
at the run's published `agr_prices[j]` row).
**Verification gate:** `Σ_h U_h ≈ agr_utility[j]` and `Σ_h net_h ≈ agr_dispatch[j]` within a
MEASURED tolerance pinned gate-then-golden from a live run (never an invented constant).
Houses are rebuilt from the Phase-40 construction primitives
(`TSODSO._case_a_house(bus, house_index, counts[bus], seed, T; scales...)`, seed =
`_case_a_house_seed(s_pop, bus, house_index)`) — identical to `build_population(:case_a_784)`'s
own draw, so attribution cannot drift from the population. [VERIFIED: direct read,
`src/experiments/materialize.jl:388-590`]

### Pattern 3: Revenue-neutral flat/TOU derivation
**What:** with weights `w[j,t]` = the DADP run's own quantities (recommend: signed `net_j[t]` from
`agr_dispatch`, or |gross load| — pick ONE, document), the quantity-weighted mean
`p_flat = Σ λ_j,t·w_j,t / Σ w_j,t` satisfies `Σ p_flat·w ≡ Σ λ·w` **identically in exact
arithmetic** — the explicit "rescale to match total DADP payments" step is then a no-op-guard
scale factor `s = (Σ λ·w)/(Σ p_flat·w)` applied for numerical hygiene (≈1.0; assert closeness).
TOU: fixed hour bins (module constant, e.g. off-peak 00–05, shoulder, peak 17–22 over the 24-h
profile), same weighted-mean construction per bin, one global rescale.
**Verification gate (locked fairness condition):** `Σ_j,t p_derived·q_j,t == Σ_j,t λ_j,t·q_j,t`
on the same run — plus a HAND-COMPUTED known-value test on a toy 2-bus/2-hour price vector
(new-math certificate; no tolerance laundering).

### Pattern 4: AC feasibility status (report, never throw)
Copy the Phase-27 idiom a third time: fix the tariff dispatch as bus injections
(`add_to_residual!` of `net_j[t]` and the `−Pdc·tanφ` reactive draw, free-sign priced frontier at
the root), solve `ACPowerFlow(; limits = false)` (Ipopt via
`select_optimizer(problem_class(ACPowerFlow()))`), warm-start P/Q/l/v from a seed solve when the
formulation stashes `:l` (the `_fit_opt_solve`→SITE-2 remedy for Ipopt's degenerate zero start),
then evaluate limits as diagnostics — `_fit_ac_settlement_violations` (`src/pricing/fit.jl:746`)
is the exact template (per-hour `(; n_thermal_violations, max_overload_ratio, n_voltage_violations,
min_voltage, max_voltage, voltage_violated)`). Wrap into a status struct: `:feasible` or a
violation list with branch/hour/quantity. `smax ≥ SMAX_NO_LIMIT` branches are skip-listed by the
existing sentinel (`src/powerflow/ConvexBranchFlow.jl:56`). [VERIFIED: direct read]

### Pattern 5: Equity metric conventions for negative surplus (literature-grounded)
| Metric | Convention (document in docstring) | Negative-value behaviour | Source |
|--------|------------------------------------|--------------------------|--------|
| Gini | `G = Σ_i Σ_j |x_i − x_j| / (2 n² μ)` (population form; use `n(n−1)` pairwise variant only if documented — state the choice) over ALL values | Remains a relative mean-difference measure; **not** a concentration index; may exceed 1. Do NOT zero/drop negatives (biases comparisons — Raffinetti et al.) | [CITED: doi.org/10.1285/i20705948v12n1p85 (De Battisti et al. 2019); doi.org/10.1007/s11403-020-00295-1] |
| Theil (T) | `(1/n) Σ (x_i/μ) ln(x_i/μ)` on the positive-support subset; report excluded count | Not computable for x_i ≤ 0 (log/mean-log domain) — standard practice is exclusion with disclosure | [CITED: doi.org/10.1007/s11403-020-00295-1 ("the Theil index … are not computable" with non-positive incomes)] |
| Atkinson | `1 − (Σ x_i^(1−ε)/n)^(1/(1−ε)) / μ` on the positive-support subset (ε = 0.5 fixed module constant); report excluded count | Same positive-support restriction — exactly the CONTEXT-locked treatment | [CITED: Atkinson 1970 via ourworldindata/s11403 sources] |
| Palma | `Σ(top decile) / Σ(bottom 40%)` over the ascending-sorted FULL vector (total cancels — no shares needed) | Most negative-robust: needs only positive group sums; document the sign caveat if the bottom-40 sum ≤ 0. Uniform vector ⇒ 0.25 | [CITED: Palma definition via s11403-020-00295-1's GE-family overview; property verified algebraically] |
Metric input choice (bills vs surplus): compute on BOTH the payment (`bill = −Σ_t p·net_h[t]`,
positive when importing) and the surplus (`U_h + Σ_t p·net_h[t]`) vectors, report per tariff; the
surplus vector is where negatives genuinely arise (PV exporters).

### Anti-Patterns to Avoid
- **Absorbing the merchandising surplus into the DSO balance** — it must be a named line (locked).
- **Zeroing/dropping negative surplus before Gini** — the literature explicitly flags this as
  biasing; the honesty policy forbids silent data shaping.
- **Reusing `solve_agr!` with production ρ for price-taker legs** — the fixed quadratic penalty
  distorts the counterfactual (see Pattern 1).
- **Re-pinning or touching `welfare_accounting`/`fit_baseline`** — golden; consumed only.
- **Throwing on AC limit violations or certificate refusals inside the harness** — statuses are
  measured outcomes (honesty policy); the report-don't-throw idiom is the established pattern.
- **Invented tolerances** — every tolerance in this phase (house↔aggregator reconciliation,
  revenue-neutrality, MS↔`welfare_accounting.dso` cross-check) is either algebraically exact or
  pinned gate-then-golden from a live measurement.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AC power flow on fixed dispatch | custom DistFlow/AC solve | `ACPowerFlow(; limits = false)` + `contribute!` + warm-start idiom | Exists, validated, and the loss-current degeneracy remedy (seed solve + warm start) is already encoded |
| Nodal price extraction | reading `dual(:balance_p)` ad hoc | `extract_dlmp(ctx)` | It carries the SOCP-exactness gate (refuses ungated ctx) and the (N, Tfull) layout convention |
| Aggregate surplus split / units | re-derived accounting | `welfare_accounting` as the cross-check oracle | Ledger MS on the DADP leg must equal its `dso` field — free correctness net |
| Household → bus/aggregator/PV-group assignment | new mapping code | `case_a_household_map` + `_case_a_house`/`_case_a_house_seed` | Single source of truth shared with `build_population` (drift-proof by construction) |
| Per-aggregator quantities from ADMM | re-solving the whole loop | the PAR-05 additive keys on the result NamedTuple | Already populated at certify time in every reactive mode; `agr_prices[j] == dadp[row_of_j, :]` pinned by test |
| Device physics in the counterfactual | custom device schedules | `contribute!(agg, ctx; T)` | The FIT/AGR-OPT builders prove reuse verbatim; device models stay owned by `src/devices/` |
| CSV artifact writing | bespoke file IO | `CSV.jl`/`DataFrames` with the Phase-40 upsert contract (rows keyed on provenance identity, `cols = :union`, statuses recorded as rows) | Established, honest-on-kill convention (`scripts/case_a_scaling.jl` header) |
| **The four equity metrics** | — a package | **deliberately in-house** + known-value certificates | v3.0 standing bar: every new mathematical regime gets its own known-value gate; conventions must live in OUR docstrings. This is the sanctioned hand-roll (see Alternatives). |

**Key insight:** this phase is almost entirely *assembly* of validated pieces; the only new math
is (a) the ledger's per-actor refinement (guarded by the `welfare_accounting` oracle) and (b) the
equity/rebound metrics (guarded by known-value certificates). Resist introducing new solves or new
model formulations anywhere.

## Common Pitfalls

### Pitfall 1: Battery-complementarity certificate refuses degenerate flat-price dispatches
**What goes wrong:** under a constant (`:flat`) price the PVBattery's arbitrage problem is
degenerate — many SOC profiles are optimal — and interior-point solvers co-activate
charge/discharge; `assert_battery_complementarity!` can refuse the counterfactual.
**Why it happens:** the certificate is a property of a strictly-priced optimum; a flat price
removes the strictness. Phase 40 already recorded this class at scale: "Full-population ADMM
certificate refusal (battery complementarity, ~1e-12 band at per-house-divided battery scale)"
recorded as data, plus the standing seed-42 battery-complementarity todo. [VERIFIED: STATE.md
Decisions + Deferred Items]
**How to avoid:** price-taker solves run the App. C check with `on_violation = :report` (or the
ADMM-consolidation `τ_batt = 1e-3` discipline at most), record refusals as measured statuses in
the comparison CSV — never loosen τ to make a leg pass, never drop the leg.
**Warning signs:** a `CertificateError` on the `:flat` leg while `:tou`/`:dadp` certify cleanly.

### Pitfall 2: The `:fit` leg's known ALMOST_OPTIMAL flakes
**What goes wrong:** two distinct, root-caused flakes live inside `fit_baseline`:
(1) the SITE-3 nested `solve_welfare` cross-check at tight `tol_gap` — already mitigated inside
`fit_baseline` by the bounded `FIT_SITE3_ALMOST_GAP_TOL` fallback (measured 7.74884392740205e-5);
(2) the seed AC-PF solve (`assert_solved!` on the Clarabel seed model) ending
`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` **on Julia 1.12.7** (deterministic there; NOT observed on
1.12.5) — already gated `@test_broken` in `test/expected_broken.txt`. [VERIFIED: `src/pricing/fit.jl:38-68,334-343,677-704`; `test/expected_broken.txt`; `test/test_pricing_welfare.jl:299-360`]
**How to avoid:** the harness may pass a tighter-conditioned `optimizer` factory to
`fit_baseline` (the documented, tested use case — "tightening solver tolerance preserves the
optimum", `test_pricing_fit.jl:268`) — the quick-task 260726-mo7 precedent — and/or accept an
honest `on_inexact = :report` NaN leg as a measured outcome in the CSV. Local runtime is Julia
**1.12.5** (flake not observed there). NEVER modify `fit_baseline` (golden).
**Warning signs:** `SolveFailedError` with `termination_status == MOI.ALMOST_OPTIMAL` raised from
`pricing/fit.jl` inside `fit_baseline`.

### Pitfall 3: Sign conventions (three colliding conventions)
**What goes wrong:** internal ADMM `st.λ` is the NEGATED published price (`agr_prices[j] =
−st.λ[j][t] == dadp[row_of_j, :]`); `welfare_accounting`'s transfer prices net INJECTION
(exporter earns); device `p_inject` is negative for loads.
**How to avoid:** settle everything from PUBLISHED prices (`dadp` rows / `agr_prices`) and net
injections (`agr_dispatch` / re-solved `pag`); the bill is `−Σ p·net` (payment) and surplus is
`U + Σ p·net`. Unit-test the exporter-earns/importer-pays signs on a hand-built 2-house fixture
(mirroring `test_pricing_welfare.jl`'s individual-surplus-sign items). [VERIFIED:
`src/admm/admm_state.jl:452-473`; `src/pricing/welfare.jl:136-150`]

### Pitfall 4: The ledger silently divides by an unconverged or budget-exceeded run
**What goes wrong:** the ADMM additive keys exist ONLY on the `:converged` path; the
`:budget_exceeded` path returns `dadp = welfare = λ = nothing` by design.
**How to avoid:** the ADMM adapter throws a loud `ArgumentError` unless `status == :converged`
(fail-loud boundary guard, project convention). [VERIFIED: `src/admm/solve_admm.jl:249-259,443-448`]

### Pitfall 5: Per-household sums not reconciling with per-aggregator keys
**What goes wrong:** degenerate ties make per-house re-solves split differently than the
aggregator solve (equal-objective alternate optima), so `Σ_h net_h ≠ agr_dispatch[j]` bitwise.
**How to avoid:** treat the household re-solve as the settlement source of truth and PIN the
reconciliation tolerance from a live measurement (gate-then-golden); assert the AGGREGATE
identities (utility sum, transfer sum, MS) on the aggregator-level run numbers so conservation
never depends on the split. Never present bitwise equality as achievable.

### Pitfall 6: New `@test_broken`/`@test_skip` records fail the whole suite
**What goes wrong:** `test/runtests.jl` enforces `expected_broken.txt` coverage — any new
broken/skipped record not listed there fails the run.
**How to avoid:** if any conditional-broken site is introduced (e.g. a Julia-version-gated FIT
leg), add the exact `(kind, file, item, test)` line to `test/expected_broken.txt` in the same
commit. [VERIFIED: `test/runtests.jl:40-48`, `test/expected_broken.txt` header]

### Pitfall 7: The suite only runs via `Pkg.test()`
**What goes wrong:** running `julia --project=test -e '@run_package_tests'` contaminates sibling
worktrees and mutates the pinned test env (documented misdiagnosis hazard in STATE.md).
**How to avoid:** every invocation is `julia --project=. -e 'import Pkg; Pkg.test()'`; use
`TSODSO_TEST_FILES=` / `TSODSO_TEST_SET=` for selection. [VERIFIED: STATE.md test-invocation
hazard]

### Pitfall 8: Equality assertions on solver-produced floats across tariff legs
**What goes wrong:** welfare/dispatch numbers from Clarabel/Ipopt are deterministic per process
but knife-edge; asserting raw equality across independently-solved legs invites flakes.
**How to avoid:** assert STRUCTURAL identities exactly (double-entry sum-zero, revenue-neutral
rescale, MS↔`welfare_accounting.dso` on the same numbers) and SOLVER-COMPARISONS within
measured tolerances pinned from live runs (project's gate-then-golden discipline).

## Runtime State Inventory

Not a rename/refactor/migration phase — omitted. (No stored keys, service configs, OS
registrations, secret names, or build artifacts carry renamed strings.)

## Code Examples

### Reading the quantities a ledger needs from a centralized run
```julia
# Source: src/pricing/welfare.jl:100-152, src/models/welfare_solve.jl:106-126
ctx, welfare, dadp = solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
λ       = extract_dlmp(ctx)                    # (N, Tfull) nodal prices, exactness-gated
p_imp   = value.(ctx.meta[:p_import])          # frontier import per hour
net_j   = [value(e.net[t]) for e in ctx.meta[:agg_net], t in 1:T]  # per-aggregator net injection
# welfare_accounting(ctx) → (; social, dso, prosumer): the ledger's MS must match .dso
```

### Reading the same from a converged ADMM run
```julia
# Source: src/admm/solve_admm.jl:249-276, src/admm/admm_state.jl:460-474
r = solve_admm(feeder, pf, aggs; T = T, λ₀ = λ₀, ρ = ADMM().ρ, allow_export = true)
r.status == :converged || error("settlement needs a converged run")
# r.dadp == r.λ  (n_load_nodes × T, ascending load-bus order)
# r.agr_dispatch[j] :: Vector{T}; r.agr_utility[j] :: Float64
# r.agr_prices[j] == r.dadp[row_of_j, :];  r.agr_import[j] == shared frontier profile
p_imp = value.(r.dso_ctx.meta[:p_import])      # DsoOpt stashes it (src/admm/DsoOpt.jl:405)
```

### The double-entry transfer set (conservation by construction)
```julia
# Every flow recorded on BOTH sides from the SAME numbers:
#   h  pays   T_h = Σ_t p_bus(h)[t]·(−net_h[t])     | aggregator j receives Σ_h T_h
#   agg j pays T_j = Σ_t λ_j[t]·net_j[t]            | DSO receives Σ_j T_j
#   DSO pays  W  = Σ_t λ₀[t]·p_import[t]            | wholesale receives W
# Σ actors == 0 exactly (each side from the same floats);
# MS (explicit line) = Σ_j T_j − W  == welfare_accounting(ctx).dso on the DADP leg.
```

### Known-value anchors for the equity metrics
```julia
# uniform vector: Gini 0, Theil 0, Atkinson 0, Palma 0.25 (0.1n·μ / 0.4n·μ)
# hand-computed 4-house vector WITH a negative, e.g. surplus = [-2.0, 1.0, 3.0, 6.0]:
#   Gini via S = Σᵢⱼ|xᵢ−xⱼ| (compute by hand, pin exact value)
#   Theil/Atkinson: n_pos = 3 reported alongside; Palma over sorted full vector
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed-dispatch SOC re-solve "AC-PF" | physics-only `ACPowerFlow(; limits=false)` + diagnostics | Phase 27 (v4.0) | SETL-03's template; structurally-inexact SOC re-solves retired |
| `fit_baseline` SITE-3 flake unbounded | bounded `FIT_SITE3_ALMOST_GAP_TOL` fallback | 2026-09-29 (FIT_SITE3 comment) | `:fit` leg stable at tight tol_gap |
| Per-bus population only | 784-house population + household map + additive keys | Phase 39 (PAR-05) / Phase 40 (POP) | per-household attribution is NEW here but rests on shipped seams |
| Gini on non-negative incomes only | documented negative-value conventions per metric | this phase | literature-grounded (2014/2019/2020/2024 papers) |

**Deprecated/outdated:** DLMP `loss`/`voltage` names → `cone`/`drop` (aliases until Phase 36) —
relevant only if the writeup decomposes prices; use the current names.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The tariff counterfactual should keep ALL devices (incl. batteries) for `:flat`/`:tou` legs, unlike `fit_baseline`'s batteryless A4 | Pattern 1 / Pitfall 1 | Comparison asymmetry vs `:fit` leg; must be documented in the CSV/writeup if accepted. Planner may instead mirror A4 — a discuss/plan-level decision, flagged here |
| A2 | Quantity weights for revenue-neutral derivation use the DADP run's own per-bus quantities (signed net or gross load — one must be chosen and documented) | Pattern 3 | Different weight choices give different (each revenue-neutral) flat/TOU levels; the comparison's fairness condition holds either way, but levels move |
| A3 | Per-house re-solves reproduce aggregator dispatch only within a solver-tolerance band (not bitwise) due to degenerate ties | Pattern 2 / Pitfall 5 | If actually bitwise in practice, the reconciliation test can be tightened — measure first, then pin |
| A4 | Fixed TOU bin boundaries (hour blocks) are a documented module constant (e.g. off-peak 00–05 / shoulder / peak 17–22 on the 24-h profile) | Pattern 3 | Bin choice changes TOU levels; locked decision says "fixed bin structure" without pinning hours — planner should pin in plan with rationale |
| A5 | The heavy `:case_a_784` tariff comparison is a script artifact (results/ CSV + literate), not a suite test | Validation Architecture | If the planner wants a suite-level 784 test it must be `:slow`-tagged and will cost minutes (784-house ADMM ≈ 10 min serial per Phase-40 measurement) |
| A6 | Atkinson's inequality-aversion ε fixed at 0.5 (module constant) | Pattern 5 | ε is a free parameter; 0.5 is the common default; any other choice is equally valid if documented |

## Open Questions

1. **House-set availability for `:dadp` household attribution on the IEEE-13 ground fixture.**
   - What we know: `case_a_household_map` is `:ieee13`-only; the IEEE-13 *test* fixture
     (`build_ieee13_ground_aggregators`, seed 20260718) builds per-bus aggregators directly.
   - What's unclear: whether the settlement tests use `build_population(:case_a_784)` at reduced
     house counts, the test fixture's own 1-aggregator-per-bus shape (household = bus), or a new
     small multi-house fixture.
   - Recommendation: household-level unit tests on a small hand-built multi-house fixture
     (3-bus × N houses, `FitFixtures`-style); the real-run settlement identity test on the
     IEEE-13 ground fixture where each bus's aggregator IS the household granularity; reserve
     `:case_a_784` map granularity for the script artifact.

2. **Whether `welfare_accounting` runs on the ADMM `dso_ctx`.**
   - What we know: `welfare_accounting` requires `ctx.meta[:agg_net]` + `:p_import` and non-empty
     `agg_device_vars`; the ADMM `dso_ctx` is built by `build_dso_opt` (stashes `:p_import`) but
     the `:agg_net` stash is the `solve_welfare` seam — likely absent, so the MS cross-check
     applies to CENTRALIZED runs only.
   - Recommendation: verify at implementation time with one probe; if absent, cross-check the
     ADMM ledger against `welfare ≈ Σ agr_utility − Σ λ₀·p_import` (the ADMM's own primal-welfare
     recomputation) instead. Never add the stash to ADMM (that would touch solved-path files).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 (local; compat floor 1.10, Manifest resolves on 1.12) | — |
| Clarabel (QP/SOCP) | price-taker QPs, DADP run | ✓ | 0.11.1 (pinned) | — |
| Ipopt | AC-PF feasibility legs | ✓ | 1.15.0 (pinned) | — |
| CSV/DataFrames | comparison CSV | ✓ | 0.10.16 / 1.8.2 (pinned) | — |
| `:slow`-set wall time | IEEE-13 T=24 settlement test | ✓ | ADMM crossval precedent (minutes) | `TSODSO_TEST_SET=fast` excludes it |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` via TestItemRunner (test env, pinned Manifest) |
| Config file | `test/runtests.jl` (+ `test/expected_broken.txt` guard, `runner_support.jl`) |
| Quick run command | `TSODSO_TEST_FILES=test_settlement.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| Selection env vars | `TSODSO_TEST_SET=fast|slow|all` (tag `:slow` in the item), `TSODSO_TEST_FILES=a.jl,…` |

**Invocation constraint (project rule):** the ONLY supported invocation is
`julia --project=. -e 'import Pkg; Pkg.test()'` — never `--project=test` / `@run_package_tests`.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SETL-01 | Ledger sums to zero on a real run; MS explicit line; MS == `welfare_accounting.dso` (centralized leg) | unit (small fixture) + integration (IEEE-13 T=24, `:slow`) | `TSODSO_TEST_FILES=test_settlement.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 (`test/test_settlement.jl`) |
| SETL-01 | ADMM converged-run adapter (agr keys → ledger); loud error on `:budget_exceeded` | unit | same | ❌ Wave 0 |
| SETL-02 | flat/TOU revenue-neutral vs DADP (identity + hand-computed known value) | unit | same | ❌ Wave 0 (`test/test_tariffs.jl` or same file) |
| SETL-02 | per-tariff dispatch legs solve; comparison row emitted (mktempdir hermetic) | unit | same | ❌ Wave 0 |
| SETL-03 | AC status struct: `:feasible` on a benign dispatch; violation list on a stress dispatch; never throws | unit | same | ❌ Wave 0 (`test/test_settlement_feasibility.jl`) |
| SETL-04 | Gini/Theil/Atkinson/Palma known values incl. negatives; uniform anchor; positive-support exclusions reported | unit | same | ❌ Wave 0 (`test/test_equity.jl`) |
| SETL-05 | breakouts by pv_group / bus / load tercile from the household map | unit | same | ❌ Wave 0 |
| SETL-06 | rebound metric known-value on a synthetic shift profile (reduction + later-hour increase) | unit | same | ❌ Wave 0 |
| — | existing goldens untouched (FIT ratio 0.772018581825438, welfare identity, knife-edge canary) | existing suite | full suite command | ✅ |

### Sampling Rate
- **Per task commit:** `TSODSO_TEST_FILES=<touched test files> julia --project=. -e 'import Pkg; Pkg.test()'`
- **Per wave merge:** full suite command (≈ tens of minutes on 1.12; Phase-38 gate precedent
  ~32.3k tests)
- **Phase gate:** full suite green (0 fail / 0 error; only `expected_broken.txt`-listed broken)
  before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/test_settlement.jl` (ledger + adapters + conservation) — covers SETL-01
- [ ] `test/test_equity.jl` (four metrics + breakouts + rebound) — covers SETL-04/05/06
- [ ] AC-feasibility status items (in `test_settlement.jl` or `test_settlement_feasibility.jl`) — covers SETL-03
- [ ] Fixture reuse: `FitFixtures`-style 3-bus T=4 (seed ~20260718 idiom) + `TwoBusFixtures`; new
      multi-house fixture only if household-split tests need it
- [ ] No framework install needed (suite infra exists)

## Security Domain

Not security-relevant in the ASVS sense (offline scientific computing; no auth, sessions, crypto,
or untrusted network input). Applicable discipline is the project's existing input-validation
convention:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | `ArgumentError` boundary guards on every public function (length/shape/status checks) — e.g. ledger adapters refuse `status != :converged`, `λ₀` length == T |
| V6 Cryptography | no | — |
| V7+ Errors/Logging | partial | fail-loud errors carrying magnitudes (project convention); statuses reported, never swallowed (honesty policy) |

Known threat patterns for this stack: none beyond numerical-integrity threats already covered by
Pitfalls (tolerance laundering, silent shaping of negative results).

## Sources

### Primary (HIGH confidence)
- Direct code reads (this session): `src/pricing/welfare.jl` (full), `src/pricing/fit.jl` (full),
  `src/admm/AgrOpt.jl` (full), `src/admm/admm_state.jl:430-474`, `src/admm/solve_admm.jl:40-140,
  240-300`, `src/experiments/run.jl` (full), `src/experiments/store.jl` (full),
  `src/experiments/Scenario.jl:1-110`, `src/experiments/materialize.jl:193-216, 388-470, 525-604,
  690-780`, `test/runtests.jl` (full), `test/expected_broken.txt` (full),
  `test/test_pricing_fit.jl:1-60`, `test/test_pricing_welfare.jl:299-360`,
  `test/fixtures_ieee13.jl` (grep), `scripts/case_a_scaling.jl` (header),
  `docs/literate/case_a_population.jl` (header), `Project.toml` [deps/compat].
- `.planning/CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md` (phase inputs).

### Secondary (MEDIUM confidence)
- Gini with negative values: De Battisti, Ferragina & Vernizzi (2019),
  doi.org/10.1285/i20705948v12n1p85; Raffinetti, Siletti & Vernizzi (2014/2015 line),
  hdl.handle.net/2434/241235; Wikipedia/OurWorldinData Gini overviews (cross-checked).
- GE-family (Theil/Atkinson) non-computability under non-positive incomes:
  doi.org/10.1007/s11403-020-00295-1.
- Rebound/snapback measurement conventions: smartEn position paper (2025),
  CAISO Demand Response Advanced Measurement Methodology (2022), Minnesota DR snapback study
  (Michaels Energy, 2021), LBNL Residential DR scoping study.

### Tertiary (LOW confidence)
- None — all load-bearing claims are code-verified or literature-cited above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; all pinned versions read from `Project.toml`
- Architecture: HIGH — every seam (ledger algebra, additive keys, counterfactual patterns, AC
  idiom, artifact pattern) read directly in source this session
- Pitfalls: HIGH — each pitfall cites a measured project precedent (STATE.md,
  `expected_broken.txt`, Phase-40 refusal records) except A2/A4/A6 (documented design freedoms)
- Equity conventions: MEDIUM-HIGH — literature-grounded; the docstring wording is a plan/execute
  task, not a research risk

**Research date:** 2026-10-24
**Valid until:** 2026-11-23 (stable: local codebase; literature settled)
