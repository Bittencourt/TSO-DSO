# Phase 45: Flexibility Market vs Price Coordination - Research

**Researched:** 2026-11-03
**Domain:** Two-stage DSO local flexibility market (baseline → divisible-bid SOCP redispatch → delivery), settled on the Phase-41 ledger, compared against DADP/flat/TOU/FIT
**Confidence:** HIGH for architecture and the IEEE-13 behaviour, which were measured end-to-end with a scratch prototype this session. MEDIUM-HIGH for IEEE-123: the `:default` population is refused by the DADP gate, while the `fixtures_ieee123` population at `tol_gap = 3e-9` certifies and is congested under flat. Stage 2 there was not run.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Market Formulation (SETL-07)
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

#### Payment Rule & Settlement (SETL-07)
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

#### Baseline Gaming Sensitivity (research PITFALLS M5)
- **Opt-in `baseline_inflation = β`:** the *reported* baseline is the true baseline × (1+β) on the
  up-direction in **congested hours**, where congestion is defined from the stage-2 binding constraints
  or the clearing-price spread. The exact definition is at Claude's discretion and must be documented.
- β changes **payments only, never physics**: the dispatch, welfare and AC feasibility are those of
  the truthful clear.
- Each row reports the overpayment against the true baseline.
- The sweep is β ∈ {0, 0.05, 0.10}. The default is β = 0, a truthful baseline.

#### Comparison Table & Artifacts (SETL-08)
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

#### Validation
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

### Deferred Ideas (OUT OF SCOPE)
- SETL-F1: aggregate-flexibility polytope bids, which keep intertemporal coupling in the bid;
  equity compensation mechanisms.
- Strategic bid shading or markups (beyond the exogenous β), and a market-power analysis.
- Additive `Scenario` fields for coordination schemes.
- A `case-a-784` flex-market leg (blocked by the Case A ADMM `CertificateError` recorded in Phase 41).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SETL-07 | A researcher can run a DSO flexibility market (explicit baseline and payment rule, uniform or pay-as-bid) as an alternative coordination scheme, producing the same settlement record as price-based coordination. | §Pattern 1 (fixed-net probe → convex secant bids), §Pattern 2 (stage 2 = `solve_welfare` over a bid pseudo-device: measured exact on IEEE-13), §Pattern 3 (L1 exact-penalty delivery), §Pattern 4 (`flex_payments` mirror-pair flow on `build_settlement_ledger`), §Q4 (uniform price = `dual(balance_p)` via `settlement_input`), §Q8 (congested hours from `decompose_dlmp`). |
| SETL-08 | A comparison table reports welfare, per-actor surplus, network feasibility and equity across FIT, TOU, flat, DADP and the flexibility market. | §Pattern 5 (append flex rows via `vcat(...; cols = :union)` after the untouched four-leg build), §Q5 column map, §Q6 welfare convention, §Q7 fence, §IEEE-123 (measured refusal + certified alternative), script/docs integration. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- JuMP for every model, with solvers only through the `select_optimizer` factory. Clarabel is used for the SOCP redispatch and the QPs, and no model names a solver. [CITED: CLAUDE.md TL;DR]
- Duals are the prices. Read a dual only after `assert_solved!` and the exactness gate. Never loosen τ, ε or the hybrid floor; tighten solver precision instead. [CITED: CLAUDE.md; memory `exactness-gate-hybrid-floor`]
- Build once and re-solve many times: mutate with `fix`/`set_normalized_rhs`/objective changes, and never rebuild inside a loop. This applies to the probes. [CITED: CLAUDE.md Deep-Dive §6]
- Rich step-by-step docs: a Literate page that executes is a hard requirement, and every modeling decision is documented. [CITED: CLAUDE.md Constraints]
- Reproducibility: seeded data, pinned env, and provenance on every artifact row. [CITED: CLAUDE.md Constraints]
- TestItems `@testitem`. Avoid the try-scoping trap (`x = try … end`, never `try x = …`), and wrap accumulators in functions. [CITED: memory `testitem-try-scoping-trap`]
- Never run TestItemRunner via `julia -e` or `--project=test`. Use `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=... julia --project=. -e 'import Pkg; Pkg.test()'`, then `git checkout -- test/Project.toml test/Manifest.toml`. [CITED: memory `gsd-plan-verify-testitemrunner-trap`, `local-project-toml-drift`]
- Keep scratch `.jl` outside the repo, because TestItemRunner scans all `.jl` files. [CITED: memory `testitemrunner-scans-scratch-jl`]
- Digest goldens are only valid on Julia 1.12.5, so gate them with `VERSION == v"1.12.5"` plus one `expected_broken.txt` skip record. [CITED: `test/test_actor_default_fence.jl:11-19`, `test/expected_broken.txt` last line]
- New planning IDs: `.github/scripts/check_planning_ids.py` already fails on main with 355 pre-existing hits. Phase-45 code should not add more (avoid `Phase 45`, `SETL-07`, `byte-identical`, `NN-NN` and similar in `src/`, `test/`, `scripts/`, `docs/literate/`). [VERIFIED: ran the guard this session]
- Executors never run the full suite, and never `git checkout -- .`, reset or stash. [CITED: CONTEXT.md Established Patterns]

## Summary

Every ingredient of the locked two-stage design already exists as a seam, and a scratch prototype confirmed the full pipeline on the IEEE-13 ground fixture this session. Each step reuses an existing seam:

- **Bids:** a fixed-net copy of the `price_taker_dispatch` build, with `pag[t]` fixed by `fix(...)` and re-solved. It reproduces the stage-1 utility to 2.7e-8 and costs 5.6 ms per probe solve warm.
- **Stage-2 redispatch:** a plain `solve_welfare(feeder, ConvexBranchFlow(), stage2_aggs; allow_export = true)`. Each `stage2_agg = Aggregator(bus, φ, [FlexBidDevice(...)], Pdc)` is a pseudo-device whose `p_inject = (b + Pdc) + Σu − Σw` and whose utility is `−Σ m·u + Σ g·w`. The network seam, `close_balance!`, the exactness gate, `extract_dlmp`/`settlement_input` and `decompose_dlmp` all apply unchanged. On the IEEE-13 flat baseline it solved OPTIMAL and exact (socp maxgap 3.7e-9) in 0.85 s.
- **Delivery:** an L1 exact-penalty tracking QP per aggregator.
- **Settlement:** a new opt-in `flex_payments` flow on `build_settlement_ledger`, mirroring `actor_wedges`.
- **Comparison:** rows appended to `compare_tariffs` through `vcat(...; cols = :union)` after the untouched four-leg build.

The measured IEEE-13 result is non-vacuous, and also clarifies what the market actually does there. The revenue-neutral flat price is **0.1534**, against a λ₀ mean of 5.60. The flat leg's signed-net weights nearly cancel on this self-balancing feeder, so the flat baseline consumes up to 10.7 pu per hour against a 0.0686 pu head branch. Stage 2 activates 236.9 pu·h of up-flex. Two different reasons drive that activation:
- **Congestion:** in hours 8–16 the network (congestion plus voltage-drop) components of the nodal price are about 4–5. In every other hour they are at most 0.005.
- **Energy mispricing:** in the uncongested hours the flat tariff is about 35× below λ₀, so curtailing is welfare-positive on its own.

Results of the clear:
- **Delivery:** the delivered dispatch misses its targets by only 0.30 pu·h, which is 0.13% of the activation. The shortfall is identical at penalty weights w = 90 and w = 900, so the remainder is genuine hour-separability infeasibility, not a penalty artifact.
- **AC check:** the delivered dispatch is AC-feasible, with a worst branch ratio of 0.967.
- **Welfare:** the delivered dispatch's lossless welfare is −4822.903, against DADP's −4822.881 computed in the same lossless convention. **The measured gap is 0.022, a relative 4.5e-6**, and the flat leg's ≈1134 welfare loss is almost entirely recovered.
- **Prices:** the uniform clearing prices differ from DADP by a mean of 0.62 and a maximum of 4.64 per (bus, hour). Hour-separable bids are not DLMPs, so the price cross-check needs a measured band, not a tight tolerance.

IEEE-123 is the main risk:
- **`:default` population refused:** `build_population(:default, ieee123)` at the ground seed is refused by the DADP exactness gate itself (ratio 1.062, gap 3.1e-7). The documented conditioning rungs do not clear it: at 3e-9 the result is bitwise identical, and 1e-10 ends ALMOST_OPTIMAL.
- **Certified alternative:** the repo's certified IEEE-123 configuration is the `fixtures_ieee123` population at `tol_gap = 3e-9` (`test/test_ieee123_admm.jl:48-60`). It needs a new default-`nothing` optimizer passthrough on `compare_tariffs`. **Measured on that configuration:** DADP is certified (maxgap 9.5e-8, 29 s), and the flat baseline **is congested** (1 thermal branch-hour at a ratio of 1.117; TOU reaches 1.26). Probes take 11.2 ms each, about 230 s for all 20,485.

**Primary recommendation:** build stage 2 as `solve_welfare` over a `FlexBidDevice` pseudo-aggregator, and settle through a new `flex_payments` ledger keyword. Build bids from secant differences of a fixed-net value function, with a range floor of 1e-6 pu and a monotone (PAV) repair. Deliver with an L1 exact-penalty tracking QP. Append the flex rows after the untouched four-leg build, with the default path fenced by a 1.12.5-gated FNV digest plus a version-independent column-list and same-process `isequal` check.

## Architectural Responsibility Map

This is a Julia research package, so the "tiers" here are its layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Baseline tariff derivation (flat/TOU) | Settlement (pure arithmetic, `tariffs.jl`) | — | Must equal the existing flat/TOU legs exactly (same `flat_prices(input)` call) |
| Stage-1 baseline dispatch | Aggregator device QP (`price_taker_dispatch`) | — | Locked seam; network-agnostic price taker |
| Bid probing (value function V_j) | Aggregator device QP (new fixed-net model) | — | The aggregator's own model, no network; one model per aggregator, re-solved |
| Bid pseudo-device | Device contract (`AbstractDevice` → `Aggregator` roll-up) | — | Lets the DSO SOCP see bids through the sole-writer seam with zero network code |
| Stage-2 redispatch + clearing price | Network/DSO SOCP (`solve_welfare`, `ConvexBranchFlow`) | Pricing (`extract_dlmp`, `decompose_dlmp`) | Same feeder/pf/gate as DADP; prices are duals |
| Delivery tracking | Aggregator device QP (new tracking model) | — | Aggregator-side re-solve; network-agnostic |
| Settlement (tariff, wholesale, flex payments) | Settlement ledger (`build_settlement_ledger`) | — | Double-entry mirror pairs; conservation exact |
| AC feasibility of delivered dispatch | Settlement feasibility (`ac_feasibility_status`) | — | Report, never gate; same as every leg |
| Comparison rows/equity | Settlement runner (`compare_tariffs`) | Equity (`equity.jl`) | Additive rows; default path untouched |
| Persistence/provenance | Script (`scripts/tariff_comparison.jl`) | Docs (Literate page) | No file IO in `src/` (comparison.jl header) |

## Standard Stack

No new packages. Every capability uses the pinned environment. [VERIFIED: codebase, scratch prototype ran under `--project=.`]

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.x (pinned Manifest) | probe, tracking and stage-2 models; `fix`/`unfix`/`set_normalized_rhs`/`@objective` mutation | project modeling layer [CITED: CLAUDE.md] |
| Clarabel (via `select_optimizer(QP())` / `select_optimizer(SOCP())`) | 0.11.x | QP probes and tracking; SOCP stage 2 | project default conic/QP solver; accurate duals [CITED: CLAUDE.md] |
| Ipopt (via `ac_feasibility_status`) | 1.15.x | AC feasibility of the delivered dispatch | existing report-never-gate seam [VERIFIED: `src/settlement/feasibility.jl:273-415`] |
| DataFrames / CSV | 1.8 / 0.10 | runner rows; script upsert | existing runner/script idiom [VERIFIED: `comparison.jl:75-89`, `scripts/tariff_comparison.jl:206-221`] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `solve_welfare` + `FlexBidDevice` | A hand-built stage-2 builder (copying `solve_welfare`'s sequence: `contribute!(pf)` → per-bus fixed injections → `p_import`/`q_import` → `close_balance!` → objective → `assert_solved!` → `assert_socp_exact!`) | Duplicates about 60 lines and the gate ordering, and risks drift from the DADP physics. Only worth it if a later need, such as a per-bus reactive capability, cannot be expressed as a device. Not needed now. |
| Secant block prices | Breakpoint duals (`dual(pag[h] == rhs)`) | Duals give the marginal at breakpoints, which are endpoints and not block averages. Measured on agg 1, h = 12: dual at δ = 0 is 0.153382, exactly the flat price, while the secant m₁ = 0.9617 because of a kink. Secants give the exact PWL interpolation of the loss at breakpoints. Use duals only as a diagnostic. |
| L1 tracking penalty | Quadratic tracking penalty | A quadratic penalty is never exact: it leaves a residual of size dual/w even when the targets are feasible, and it biases welfare by w. L1 is an exact penalty above a finite threshold (measured: shortfall unchanged from w = 90 to 900). |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed by this phase, so slopcheck was not applicable. **Packages removed:** none. **Packages flagged:** none.

## Architecture Patterns

### System Architecture Diagram

```
compare_tariffs(feeder, pf, aggs; T, λ₀, ..., flex_market = nothing | FlexMarket | Vector)
  │
  ├─(unchanged)─ DADP run ─► input::SettlementInput ─► dadp/flat/tou/fit legs ─► 4 DataFrames
  │                                                                              │
  │   flex_market === nothing ──────────────────────────────────────────────────► return (identical)
  │
  └─ for each distinct (baseline_tariff, n_blocks) clear key:
        baseline price p = flat_prices(input) | tou_prices(input; bins)
          │
          ▼
     STAGE 1  price_taker_dispatches(aggs, p) ─► b_j[t], U_j(b), batt certs
          │
          ▼
     BIDS  per aggregator: fixed-net model (build once) ─ fix pag[t]=b[t] ─► V_j(b)
           per hour h: range LPs (max/min pag[h]) ─► R↑, R↓   (R < 1e-6 pu ⇒ no block)
                       n_blocks probes each side ─► V_j(b ± δ_k e_h) ─► secant prices
                       PAV monotone repair (report max repair) ─► convex PWL bid
          │
          ▼
     STAGE 2  stage2_aggs = [Aggregator(bus, φ, [FlexBidDevice(b+Pdc, blocks)], Pdc)]
              solve_welfare(feeder, pf, stage2_aggs; T, λ₀, allow_export=true[, optimizer])
                 ├─ SolveFailedError(INFEASIBLE) ─► status "infeasible_redispatch" row
                 ├─ CertificateError(:socp_exact) ─► status "inexact_redispatch" row
                 └─ OK ─► π = settlement_input(ctx2).prices ; u,w accepted blocks ; Δ = Σu−Σw
                          congested hours = decompose_dlmp(ctx2) (|cong|+|drop| > κ·λ₀[t])
          │
          ▼
     DELIVERY per aggregator: max U + p·pag − w·Σ|pag − (b+Δ)|  (L1 exact penalty)
              ─► n_j (delivered), U_j(n), batt certs, shortfall s_j[t]
          │
          ▼
  per FlexMarket (payment_rule, β):
     flex payment rows (uniform: π·Δ ; PAB: m_k·u_k − g_k·w_k ; + β phantom)
     build_settlement_ledger(P_tariff, n, U(n), p_imp_lossless(n), λ₀, buses; flex_payments=rows)
     ac_feasibility_status(feeder, aggs, n) ; equity ; rebound vs DADP
     ─► summary row (base schema + additive flex columns), bill rows, rebound rows
  │
  ▼
vcat(base_tables, flex_tables; cols = :union) ─► returned DataFrames ─► script upsert ─► CSV ─► Literate page
```

### Recommended Project Structure
```
src/coordination/
├── coordination.jl     # AbstractCoordination, PriceBased, FlexMarket (validated kwargs), row naming
└── flex_market.jl      # fixed-net probe model, flex_bids, FlexBidDevice, clear_flex_market,
                        # tracking delivery, flex payment rows, congested-hour classifier
src/settlement/SettlementLedger.jl   # + `flex_payments = nothing` keyword, flow (e)
src/settlement/run_inputs.jl         # + forward `flex_payments` in the SettlementInput overload
src/settlement/comparison.jl         # + `flex_market = nothing` (+ optimizer passthrough, see IEEE-123)
src/TSODSO.jl                        # include coordination/*.jl AFTER settlement/equity.jl, BEFORE settlement/comparison.jl
scripts/tariff_comparison.jl         # + --flex-market flag, + --mode ieee123
docs/literate/flex_market.jl         # new page; register in docs/make.jl (list ~l.38-59, nav ~l.110-119)
test/test_flex_market.jl             # fast: bids, stage 2, delivery, ledger, rules, β, liveness, guards
test/test_flex_market_fence.jl       # default-path fence (captured BEFORE any src edit)
test/test_flex_market_ieee.jl        # :slow IEEE-13 compare rows + IEEE-123 smoke
```
The include order matters: `flex_market.jl` uses `price_taker`, `feasibility` and `decompose_dlmp`, and `comparison.jl` uses `flex_market.jl` [VERIFIED: `src/TSODSO.jl:306-312`].

### Pattern 1: Fixed-net probe model (bids)
**What:** This is a copy of the `price_taker_dispatch` build shape (`price_taker.jl:100-108`): `Model(select_optimizer(QP()))` → `ModelContext` → `contribute!(agg, ctx; T)` → `pag[t] == p_inject[t] − Pdc[t]`. The model is built once per aggregator. All hours are fixed at `b` with `fix(pag[t], b[t]; force = true)`, under the objective `Max ctx.objective`; this gives `V_j(b)`. For each hour h, unfix `pag[h]`, then:
- range: `Max pag[h]` and `Min pag[h]` give `R↑ = sup − b_h` and `R↓ = b_h − inf`;
- probes: restore `Max ctx.objective`, fix `pag[h] = b_h ± k·R/K` for k = 1..K, and record V;
- re-fix `pag[h] = b_h`.

**Why the curve is convex (theory):** V_j(x) = max U s.t. pag = x is the value function of a concave maximisation with affine RHS. It is therefore concave in x, so the single-hour loss L(δ) = V(b) − V(b+δe_h) is convex and its secant slopes are monotone in exact arithmetic. [ASSUMED: standard parametric convex-programming result; consistent with the measurements below]

**Measured (IEEE-13 ground, flat baseline, K = 4):**
- V(b) reproduces the stage-1 utility (−461.5112607 against −461.5112607, Δ = 2.7e-8).
- **Noise on tiny ranges:** without a floor, the worst monotonicity violation is 0.389, and the down-block-1 price exceeds the up-block-1 price (g₁ − m₁) by 4.66. Both come from secant noise on a near-zero range: agg 6, h = 23, R↓ = 4.7e-9. 88 of 240 agg-hours have 1e-9 < R↓ < 1e-3.
- **With a range floor ≥ 1e-6 pu:** the worst violation is 9.2e-5 (agg 9, h = 7, R↓ = 1.9e-3), and g₁ − m₁ ≤ −0.476 everywhere. The bid–ask gap is strictly positive, so there are no wash trades.
- R↑ ≈ 1.0 pu per agg-hour, from thermostatic Pmax = 1·dev_scale. R↓ = 0 in 24 of 240 agg-hours: at a price of 0.153, devices are already at maximum consumption.
- Breakpoint duals confirm the theory: `dual(pag[12] == b)` equals 0.153382, exactly the flat price.
[VERIFIED: scratch prototype this session]

**Prescription:** use secant prices `m_k = (V_{k−1} − V_k)/(δ_k − δ_{k−1})` (up) and `g_k = (V_k^dn − V_{k−1}^dn)/(δ_k − δ_{k−1})` (down), with equal spacing δ_k = k·R/K. If R < R_min = 1e-6 pu, emit no blocks in that direction. After that, apply a pool-adjacent-violators monotone repair (m non-decreasing, g non-increasing, g₁ ≤ m₁). **Report** the maximum repair magnitude per clear (measured ≤ 9.2e-5 on IEEE-13), and pin the tolerance at 3× the maximum over seeds. Any probe that is not OPTIMAL drops its block and counts toward `n_probe_failed`; it never throws.

### Pattern 2: Stage 2 = `solve_welfare` over a bid pseudo-device
```julia
# internal, unexported; lives in src/coordination/flex_market.jl
struct FlexBidDevice <: AbstractDevice
    gross::Vector{Float64}    # b[t] + Pdc[t]  (baseline gross device injection)
    up_q::Matrix{Float64}     # T × K block widths (0 ⇒ no block)
    up_m::Matrix{Float64}     # T × K up prices (non-decreasing in k)
    dn_q::Matrix{Float64}
    dn_g::Matrix{Float64}     # T × K down values (non-increasing in k)
end
function contribute!(d::FlexBidDevice, ctx::ModelContext; T::Int)
    m = ctx.model; K = size(d.up_q, 2)
    u = @variable(m, [t = 1:T, k = 1:K], lower_bound = 0.0, upper_bound = d.up_q[t, k])
    w = @variable(m, [t = 1:T, k = 1:K], lower_bound = 0.0, upper_bound = d.dn_q[t, k])
    p_inject = AffExpr[d.gross[t] + sum(u[t, k] for k in 1:K) - sum(w[t, k] for k in 1:K) for t in 1:T]
    utility = zero(QuadExpr)
    for t in 1:T, k in 1:K
        add_to_expression!(utility, -d.up_m[t, k], u[t, k])
        add_to_expression!(utility, d.dn_g[t, k], w[t, k])
    end
    return (; vars = (; u, w), p_inject, utility)   # NO q_inject; traits default (not flexible load, :none storage)
end
stage2_aggs = [Aggregator(a.bus, a.φ, [FlexBidDevice(b[k] .+ a.Pdc[1:T], ...)], a.Pdc) for (k, a) in enumerate(aggs)]
ctx2, _obj2, _ = solve_welfare(feeder, pf, stage2_aggs; T, λ₀, allow_export = true)  # + optimizer when supplied
in2 = settlement_input(ctx2; T, λ₀)   # in2.prices = π (gated), in2.bus_nets = b+Δ, in2.p_import = SOCP import
# NEVER use in2.bus_utilities in the ledger: it is −(bid cost), not device utility.
```
**Why this satisfies "same feeder, SOCP, exactness gate, seam":** `solve_welfare` runs, in order:
1. `contribute!(pf, ctx, feeder)` (`welfare_solve.jl:193`);
2. the aggregator roll-up, the sole `:Rp`/`:Rq` writer (`Aggregator.jl:237-240`);
3. the free-sign priced `p_import` (`:246-254`);
4. `close_balance!` (`:267`);
5. `Max Σ utility − λ₀ᵀp_import` (`:270`), which here is exactly `−(bid cost) − λ₀ᵀp_import`, the locked objective;
6. `assert_solved!` (`:284`);
7. `assert_socp_exact!` (`:304-306`);
8. the battery and EV certificates, which are no-ops because `storage_kind(FlexBidDevice) = :none` (`welfare_solve.jl:436-444`, `CapabilityTraits.jl`).

**Measured:** on the IEEE-13 flat baseline, OPTIMAL, maxgap 3.7e-9, 0.85 s. The maximum simultaneous up and down acceptance ("wash") was 3.5e-9. `decompose_dlmp(ctx2)` succeeds. [VERIFIED: scratch prototype]

**Reactive power q (answer to Q1):** with this pseudo-device, `:Rq` at bus j = `−Pdc·tanφ` (`Aggregator.jl:239`). That is q **fixed at the inelastic baseline draw, not free**. This is deliberate:
- It is identical to the reactive model of `ac_feasibility_status` (`feasibility.jl:339`), so the stage-2 SOCP and the AC verdict see the same q.
- It is the default (non-LIVE) reactive model of DSO-OPT (`DsoOpt.jl:28-34`).
- Holding q at the full baseline value instead would make stage 2 infeasible, so that option is ruled out. The baseline value includes the flexible-load draw `p·tanφ` (`Aggregator.jl:215-223`), and under the flat baseline that is about 0.48 × 10 pu ≈ 4.8 pu, far above the 0.0686 pu head branch.
- The flex product is active power only. Reactive-decision devices (FourQuadBESS, SmartInverterPV) have no reactive bid, and their price-taker q is degenerate anyway (zero utility, `SmartInverterPV.jl:16-22`).
- The documented difference from DADP is that the centralized DADP SOCP includes the flexible-load reactive draw, and stage 2 does not.
- If a population contains `FixedCapacitor` aggregators (only IEEE-8500 builds them, `materialize.jl:1149-1164`), add a constant `q_inject` for the nameplate kvar to the pseudo-device, or refuse with an `ArgumentError`. Out of scope for IEEE-13/123.

**Device classes (answer to Q1):** every device class is handled generically. The probe fixes the *aggregator* net `pag`, and devices re-arrange behind the meter:

| Class | What the probe/delivery sees | Note |
|---|---|---|
| Thermostatic / HeatPump | p shift at h changes later temperatures; the loss includes the comfort cost of those later hours (others' net fixed) | HeatPump: COP is a parameter, still linear |
| Deferrable | total-energy utility `−b/2 (E_tot − E)²`, soft (`Deferrable.jl:238-248`) | single-hour flex comes from deviating the total, priced by the quadratic |
| PVBattery / EV | SOC can buffer within the hour, since other hours' net is fixed but internal re-routing is allowed | EV window: zero flex when unavailable. Run the EV/battery certificates on **delivery** solves only (report counts) |
| FourQuadBESS / SmartInverterPV | active leg flexes; q is degenerate in the price-taker and not used by stage 2 | see the reactive paragraph above |
| Interruptible | exactly hour-separable (`Interruptible.jl` utility Σ_t a·p − b/2·p²) | the liveness fixture (Pattern 6) |
| OptOut/PartialCompliance/Rebound wrappers | forwarded traits (`CapabilityTraits.jl` behaviour block) | nothing special |

### Pattern 3: Delivery = L1 exact-penalty tracking QP
The model is the same build as Pattern 1 (a fresh model per aggregator is fine; it is a single solve), plus `s[t] ≥ ±(pag[t] − target[t])`. The objective is `Max ctx.objective + Σ p_t·pag_t − w·Σ s_t`, where `target = b + Δ` is read from `in2.bus_nets`. With `w > max |dual of pag[t] == target[t]|`, the L1 penalty is exact: zero shortfall whenever the joint targets are feasible.

The weight is w = 10·max(max|π|, max λ₀, max|p|). This is documented, and the sensitivity is measured: on IEEE-13, w = 90 and w = 900 give an identical shortfall of 0.2961 pu·h and identical delivered welfare to 1e-6.

The shortfall is `s_j[t] = |n_j[t] − (b_j[t] + Δ_j[t])|`. Report Σ, maximum, the ratio to Σ|Δ| (measured 0.13%), and per-(j,t) detail rows if desired. The penalty is a modeling device: it is **not** booked as money in the ledger; see Open Q2. [VERIFIED: scratch prototype]

### Pattern 4: Ledger `flex_payments` keyword (44-06 mirror pattern)
Add `flex_payments = nothing` to the primitive `build_settlement_ledger` (`SettlementLedger.jl:197-208`) and forward it in the `SettlementInput` overload (`run_inputs.jl:523-540`).
- **Validation (V5):** each row is `(; bus, t, price, quantity)`; the bus must be one of the ledger buses; 1 ≤ t ≤ T; all values finite. Follow the `actor_wedges` validation block (`SettlementLedger.jl:336-369`).
- **New flow (e), after (d):** `_push_transfer_pair!(transfers, (:aggregator, bus), :dso, t, price, quantity)`. The amount is `price·quantity`, and `balances[(:aggregator, bus)] += amount`, i.e. the aggregator earns when it delivers up-flex.
- **Default:** with `nothing`, no row is added and the ledger is identical, the same `==` test as 44-06.

**Row construction:**
- Uniform: one row per (j,t) with Δ ≠ 0, `price = π_j,t`, `quantity = Δ_j,t = Σ_k u − Σ_k w`.
- PAB: one row per accepted block, up `(price = m_k, quantity = +u_k)` and down `(price = g_k, quantity = −w_k)`.
- β phantom rows: see Q8 below.

The other flows stay as they are:
- (a) the tariff on **delivered** energy: `prices` = the uniform baseline-tariff matrix (same `uniform_matrix` as the flat/tou legs, `comparison.jl:450-456`) and `bus_nets` = delivered n;
- (b) wholesale on the lossless delivered import.

`ledger_residual == 0.0` holds by construction (IEEE adjacent-pair argument, `SettlementLedger.jl:101-130,444-459`).

### Pattern 5: Additive rows without touching the default build
`_rows_to_dataframe` takes its column set from the **first** row (`comparison.jl:77`). Appending a NamedTuple with extra fields into `summary_rows` would therefore **silently drop the new columns**. Instead:
- leave lines 249-772 unchanged;
- just before `return`, `if flex_market !== nothing`, build the flex rows as `merge(_summary_row(...), (; new_cols...))`;
- convert them with `_rows_to_dataframe`;
- return `vcat(summary, flex_summary; cols = :union)`, and the same for `household_bills` and `rebound`.

`cols = :union` appends new columns after `t_horizon` and fills the four base rows with `missing`. The default path executes not a single new statement.

### Pattern 6: Liveness fixture (hour-separable)
Use a 2-bus feeder (`Feeder([Bus(1,…,true), Bus(2,…)], [Branch(1,2,r,x,smax)], 1)`, the `test_settlement.jl:1099-1103` shape) at T = 2–3, with `Interruptible` devices. Choose **φ = 1.0** so that tanφ = 0: the DADP flexible-load q and the stage-2 q are then both zero, and the two physics are identical. Set smax tight enough to bind in one hour.
- V_j is exactly hour-separable, so the only gap is the PWL discretisation. For a quadratic utility the interpolation error per block is b·h²/8, so the gap is O(1/K²).
- Compare `W_socp = Σ U(n) − λ₀ᵀ p_import(stage 2)`, valid when shortfall = 0, against the `solve_welfare` objective for K ∈ {1, 2, 4, 8, 16}. Assert monotone decrease and the final gap below 3× the measured maximum.
- **Analytic anchor:** for Interruptible at an interior baseline p₀ with tariff price π₀, the loss is L(δ) = π₀δ + b·δ²/2. So `m_k = π₀ + b(δ_{k−1}+δ_k)/2`, which is hand-checkable.

### Anti-Patterns to Avoid
- **Reading `in2.bus_utilities` as utility.** On the stage-2 ctx it is −(bid cost), which is offset from device utility by Σ V_j(b). PITFALLS M4: never compare objective values across schemes.
- **Calling `solve_agr!` or adding a ρ term** to probes or tracking (`price_taker.jl:6-18`).
- **Modifying `price_taker_dispatch` or `_summary_row`.** Both feed the default output; add new internal builders instead.
- **Holding q at the baseline including flexible-load draw.** Stage 2 becomes infeasible for a reason unrelated to the flex product.
- **Secant bids on near-zero ranges.** Noise of order 1e-8·|V|/δ (measured 4.66 at δ = 1.2e-9).
- **Building probe models per solve.** Build once per aggregator and mutate with `fix`/objective (measured 5.6 ms per solve warm).
- **Using the price spread at non-activated buses.** π is non-unique inside the bid–ask gap [g₁, m₁] where nothing clears.

## Answers to the Research Questions (with references)

**Q1, Stage 2:** see Pattern 2. The pseudo-device, the network seam, the gate and duals all apply unchanged. q is fixed at `−Pdc·tanφ`, the inelastic baseline draw, and is not free.

**Q2, Bid probing:** `price_taker_dispatch` has no hook to fix a single hour, since its only constraint is the coupling (`price_taker.jl:106-108`). Do **not** modify it, because it feeds the default flat/tou legs. Add the internal fixed-net model of Pattern 1.
- **Cost:** one JuMP build per aggregator (~16 ms, the measured price-taker build+solve) plus one Clarabel re-solve per probe.
- **Solves per aggregator:** `1 + T·(2 + 2K)`, which is 241 at T = 24, K = 4.
- **IEEE-13:** 10 aggregators → 2,410 solves, **measured 13.4 s warm (5.57 ms per solve)**.
- **IEEE-123:** 85 aggregators → 20,485 solves; **measured 11.2 ms per re-solve** on an IEEE-123 fixture aggregator, so about 230 s.
- **Convexity:** guaranteed in exact arithmetic, and holds to 9.2e-5 with the 1e-6 pu range floor.
- **Block quantity range per hour:** R↑/R↓ from the two range LPs with other hours fixed. Measured R↑ ≈ 1.0 pu and R↓ ∈ [0, 0.45] pu per agg-hour on IEEE-13.

**Q3, Delivery:** L1 exact penalty, w = 10·max(|π|, λ₀, |p|), with a measured insensitivity check at 10w. Shortfall `|n − (b+Δ)|` per (j,t). See Pattern 3.

**Q4, Uniform clearing price:** π_j,t = `dual(balance_p[j,t])` of the stage-2 ctx, read only through `settlement_input(ctx2)` → `extract_dlmp` (gated, `dlmp.jl:142-150`, `_assert_priceable`).
- **Sign:** the same as DADP. `dual(balance_p[root,t]) = λ₀[t]` at the priced frontier (`run_inputs.jl` λ₀ comment). π > 0 is the marginal value of an injection, so an up-activation earns π·Δ and a down-activation pays π·|Δ|.
- **KKT:** for an interior accepted up block, m_k = π. For an accepted down block, g_k = π. Rejected blocks satisfy m_k ≥ π ≥ g_k.
- **Buses and hours with no activation:** π is defined but non-unique inside [g₁, m₁], and the payment is 0 because Δ = 0. Report it, but use it for nothing.
- **Transit buses** (IEEE-123) have prices but no aggregator, so they are ignored.
- **Measured on IEEE-13:** π ∈ [0.90, 8.79] against DADP λ ∈ [0, 8.80]. |π − λ| has a mean of 0.62 and a maximum of 4.64.

**Q5, Ledger mapping:** see Pattern 4.
- **Entry point:** the primitive `build_settlement_ledger(P_tariff, n_by_bus, U_by_bus, p_imp_lossless, λ₀, buses; T, source = :flex_market, flex_payments = rows)`.
- **Summary-row mapping** onto `_summary_row` (`comparison.jl:121-186`):

| Field | Value |
|---|---|
| `tariff` | `_flex_row_name(fm)` |
| `engine` | the run's engine string |
| `status` | `ok`, `infeasible_redispatch`, `inexact_redispatch` or `error:<Type>` |
| `welfare` | the Q6 value |
| `total_payments` | `−aggregators_total`, which includes the flex income |
| `fairness_total` | `missing`: flex payments are not one price vector (the fit-leg precedent, `comparison.jl:732`) |
| `merchandising_surplus` = `dso_total` | `led.balances[:dso]`, the DSO net after flex payments (the ledger's own line) |
| `aggregators_total`, `wholesale_total` | from the ledger |
| feasibility | from `ac_feasibility_status(feeder, aggs, n)` |
| battery counts | from the delivery solves |
| equity | `bills = −balances[(:aggregator, b)]`, `surplus = U(n) + balance`, at bus granularity |
| rebound | `rebound(dadp_netload, flex_netload)` |
| `bills_granularity` | `"bus"` |

- **New columns, appended:** `coordination`, `baseline_tariff`, `payment_rule`, `n_blocks`, `baseline_inflation`, `flex_payments_total`, `energy_merchandising_surplus` (= MS + flex payments, i.e. collections − wholesale), `flex_up_total`, `flex_down_total`, `delivery_shortfall_total`, `delivery_shortfall_max`, `delivery_shortfall_ratio`, `baseline_overpayment`, `n_congested_hours`, `redispatch_socp_maxgap`, `redispatch_p_import_total`, `welfare_socp_import`, `welfare_gap_vs_dadp_lossless`, `price_gap_vs_dadp_max`, `bid_repair_max`, `n_probe_solves`, `n_probe_failed`, `flex_wall_s`.
- **Houses:** with `houses !== nothing` plus `flex_market`, throw an `ArgumentError` before solving. Household attribution of flex payments belongs to the deferred case-a-784 leg.

**Q6, Welfare of the delivered dispatch:** `Σ_j U_j(n_j) − Σ_t λ₀[t]·(−Σ_j n_j[t])`. This is the **lossless** import, the same convention as the flat/tou legs (`comparison.jl:562-563,627`). The delivered dispatch comes from device-level QPs with no network state.
- **Do not** use the stage-2 SOCP import for the primary welfare column: it belongs to the targets b+Δ, not to n.
- Report `welfare_socp_import = Σ U(n) − λ₀ᵀ p_import(stage 2)` as an auxiliary column, exact only when the shortfall is 0.
- The DADP row's welfare uses its own loss-inclusive import. To avoid the misreading "flex beats DADP" (measured: flex lossless −4822.903 sits *above* DADP's SOCP −4823.014 only because it omits about 0.13 of loss cost), report `welfare_gap_vs_dadp_lossless = W_flex − (Σ U_dadp − λ₀ᵀ(−Σ net_dadp))`. Measured −0.0216.
- PITFALLS M4: utilities are recomputed from the same device models (`value(ctx.objective)`), so constant offsets such as Deferrable's `−b/2·E²` cancel in differences. Never compare the stage-2 objective (−203.92) with DADP welfare. The bid-model "welfare" Σ V(b) + obj₂ = −4819.03 is a fiction: it is optimistic because hour-separability ignores cross-hour costs.

**Q7, Byte-identity fence:** see §Validation Wave 0. Capture before any `src/` edit:
- an FNV-1a digest (the `test_actor_default_fence.jl:30-80` fold) of the four `compare_tariffs` DataFrames, every column name and every cell, on the hermetic 2-bus T = 3 fixture (`test_settlement.jl:1091-1140`, fast). Gate it on Julia 1.12.5, with one `skipped` record in `expected_broken.txt`;
- version-independent checks: `names(res.summary) == PINNED_37_COLS`, `res.summary.tariff == ["dadp","flat","tou","fit"]`, and same-process `isequal(compare_tariffs(...), compare_tariffs(...; flex_market = nothing))` for all four tables;
- for the ledger: `build_settlement_ledger(...)` vs `(...; flex_payments = nothing)`, with `==` on `transfers` and `balances`.

**Q8, Congested-hour definition (discretion; recommended):** hour t is congested iff `max_j (|congestion_{j,t}| + |drop_{j,t}|) > κ·λ₀[t]`, from `decompose_dlmp(ctx2)` on the **truthful** stage-2 clear, with κ = 1e-2. `cone` (losses) and `energy` are excluded.
- **Measured on IEEE-13:** hours 8–16 have components in [4.03, 5.23], which is 0.6–0.9 λ₀; all other hours are ≤ 0.005, at most 6e-4 λ₀. The two decades of separation make the classification identical for any κ ∈ [1e-3, 0.5]. Record this robustness on the page.
- **Primal cross-check:** the head-branch loading in congested hours ≥ 1 − 1e-6. The targets' AC check shows 9 branch-hours at a ratio of 1 + 6.4e-8.
- **β phantom:** for congested t with Δ↑_j,t > 0, `phantom_j,t = β·max(−b_j,t, 0)`. The consumption baseline is inflated, and net exporters are not inflated, because inflating a positive baseline would under-pay.
  - Paid at π_j,t (uniform), or at the price of the marginal accepted up block (PAB).
  - `baseline_overpayment = Σ price·phantom` is booked as extra flex-payment rows, so the money is real and the residual stays 0.0.
  - Physics, welfare and AC come from the truthful clear, which is computed once and shared.

**Q9, IEEE-123:** see §IEEE-123.

**Q10, Literature (brief):** see §State of the Art.

## IEEE-123

Measured this session with scratch probes. Each run ran DADP centralized, then the flat/TOU baselines, then `ac_feasibility_status`, then a probe-timing loop. [VERIFIED: scratch runs `flex_123.jl`, `flex_123_fx.jl`]

| Configuration | DADP centralized outcome | Flat baseline AC | TOU baseline AC | Probe re-solve |
|---|---|---|---|---|
| `build_population(:default, feeder, :ieee123, profiles, sub_seed(20260718, :population))`, default SOCP tol | **REFUSED**: `CertificateError` SOCP INEXACT, ratio 1.0623, gap 3.14e-7 (hybrid-floor band) | — | — | — |
| same population, `tol_gap = 3e-9` | **REFUSED**, bitwise identical (the IPM stop did not move) | — | — | — |
| same population, `tol_gap = 1e-10` | `SolveFailedError` ALMOST_OPTIMAL / NEARLY_FEASIBLE (strict gate) | — | — | — |
| **`fixtures_ieee123` population** (seed 20260719, load 0.05, PV 0.12, dev 0.05·5/3; the copy used by `scripts/actor_behaviour_sweep.jl:73-141`) + `tol_gap = 3e-9` (the documented conditioning, `test/test_ieee123_admm.jl:48-60`) | **CERTIFIED**: maxgap 9.47e-8, 28.9 s, AC feasible at a ratio of 1.0000 | **infeasible**: 1 thermal branch-hour, ratio **1.117** (Σ net peaks at +4.09 pu of export against the 3.8 pu head branch) | infeasible: 3 branch-hours, ratio 1.26 | **11.2 ms/solve** |

Findings:
- **Congestion exists on IEEE-123 under flat, so the activation is not null.** On the certified configuration, the flat baseline overloads the head branch in reverse flow at the PV peak (ratio 1.117), and TOU is worse.
- The flat level is 1.4495 against a λ₀ mean of 5.60, about 4× low. As on IEEE-13, part of the activation will be energy-value correction rather than congestion relief.
- DADP's own network price components are small except at hour 12 (0.226; elsewhere ≤ 0.004).
- 29 of 85 baseline battery certificates are refused at flat (degenerate constant price), the same class as IEEE-13.
- **Guard compatibility:** 85 aggregators on 85 distinct load buses (`ieee123_load_nodes()`), so the one-aggregator-per-bus guard (`comparison.jl:278-282`) passes. The ~37 transit buses carry prices but no aggregator.
- **Runtime estimate for the ieee123 mode** [ASSUMED from the component timings above]:
  - DADP: 29 s;
  - probes: 85 × 241 = 20,485 solves × 11.2 ms ≈ 230 s;
  - stage-2 SOCP: of the order of the DADP solve (~30 s; must use the same 3e-9 conditioning);
  - AC checks: ~9–12 s each × about 5 legs;
  - `fit_baseline`: unmeasured;
  - total about 6–10 min plus compile; memory well within the host (one probe model alive at a time).

**Prescription:**
- **(a)** Add a default-`nothing` passthrough, `welfare_optimizer = nothing`, to `compare_tariffs`. Forward it to the centralized DADP `solve_welfare` and to the stage-2 `solve_welfare` using the `fit_optimizer` if/else shape (`comparison.jl:658-669`), so that with `nothing` the call is identical. This is a conditioning seam, not a gate change: `assert_socp_exact!`, τ and ε stay untouched, per the project's tighten-precision-never-loosen policy.
- **(b)** The `--mode ieee123` script mode uses the `fixtures_ieee123` population copied verbatim (the precedent of `actor_behaviour_sweep.jl`), with `welfare_optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)` and engine `:centralized`.
- **(c)** Record the `build_population(:default, :ieee123)` refusal honestly, as a sentence on the literate page or as an optional `(run)` status row under a distinct mode such as `ieee123-default`.
- **(d)** If stage 2 on IEEE-123 is refused by the gate even at 3e-9, the flex rows become `inexact_redispatch` status rows. That is a measured outcome; never loosen.
- **(e)** The `:slow` IEEE-123 test item asserts only "outcome recorded, never a crash". Do not pin welfare numbers until they are measured over seeds.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stage-2 network model | a new DSO redispatch builder | `solve_welfare` + `FlexBidDevice` | gate ordering, frontier, reactive closure and the battery/EV certificates are already right and tested |
| Clearing price | reading `dual(...)` on a raw constraint | `settlement_input(ctx2).prices` (→ `extract_dlmp`) | refuses ungated or inexact duals (`_assert_priceable`) |
| Congestion detection | thresholding price spreads | `decompose_dlmp(ctx2)` congestion + drop | the four-way split is certified to sum to the price (`dlmp.jl` header) |
| Conservation | summing balances | `_push_transfer_pair!` + `ledger_residual` | exact by the IEEE adjacent-pair argument |
| AC check | a new Ipopt PF | `ac_feasibility_status` | warm-start remedy, report semantics |
| Baseline prices | recomputing flat/TOU | `flat_prices(input)` / `tou_prices(input; bins)` | must equal the flat/tou legs |
| Error→status mapping | catch-all | catch `SolveFailedError` (`termination_status ∈ {INFEASIBLE, INFEASIBLE_OR_UNBOUNDED}` → `infeasible_redispatch`) and `CertificateError` (`kind == :socp_exact` → `inexact_redispatch`), and rethrow the rest | fields exist (`errors.jl:33-39,71-75`) |

## Common Pitfalls

### Pitfall 1: The IEEE-13 flat baseline is mispriced, not just congested
**What goes wrong:** the page claims that the "flex market relieves congestion" when most activation is energy-value correction.
**Why:** the revenue-neutral flat level = Σλ·net/Σnet with signed nets (`tariffs.jl:195-204`). On a nearly self-balanced feeder (DADP Σ net ≈ −0.43 pu·h) this gives 0.1534, about 35× below λ₀.
**Avoid:** report `n_congested_hours` (9 of 24) beside Σ|Δ|, and state both drivers on the page. A `:tou` baseline row gives a second reading.

### Pitfall 2: The new columns are dropped by `_rows_to_dataframe`
**What goes wrong:** flex rows pushed into `summary_rows` lose their extra fields, because the schema comes from the first row (`comparison.jl:77`).
**Avoid:** Pattern 5 (`vcat` with `cols = :union`).

### Pitfall 3: Secant noise on tiny ranges makes bids non-convex
Measured 0.389 / 4.66 without a floor. **Avoid:** range floor R_min = 1e-6 pu, a PAV repair, and report `bid_repair_max`.

### Pitfall 4: Wash trades
If g₁ ≥ m₁, the LP can accept up and down at once at no cost, which inflates PAB money. Measured wash 3.5e-9 with strict g₁ < m₁. **Avoid:** after the repair, assert g₁ < m₁ (report it, don't throw). Post-solve, net u and w per (j,t) for the payment rows and record `max_wash`.

### Pitfall 5: The AC verdict at the limit
The stage-2 targets sit exactly on the head-branch limit, and the strict AC check flags them `infeasible` at a ratio of 1 + 6.4e-8. The delivered dispatch was feasible at 0.967 only because the shortfall relieved loading. **Avoid:** never assert `feasible` in tests (assert membership in the status set), and never add slack to smax. Report the targets' verdict optionally, as a diagnostic column.

### Pitfall 6: Lossless vs loss-inclusive welfare
A flex row can look better than DADP by the DADP loss cost (measured about 0.13). **Avoid:** the `welfare_gap_vs_dadp_lossless` column and the page text (Q6).

### Pitfall 7: Battery certificate refusals in the baseline
The flat leg already records `batt_refused = 10` (CSV). The constant price makes arbitrage degenerate (`price_taker.jl:65-70`). The flex baseline is the same dispatch, so it inherits that. **Avoid:** report baseline and delivery certificate counts; never tighten τ.

### Pitfall 8: An IEEE-123 refusal before any flex code runs
See §IEEE-123. A "(run)" status row is a valid outcome, so never loosen the gate to obtain IEEE-123 rows.

### Pitfall 9: Duplicate row names break the CSV upsert
The upsert key is `(:mode, :tariff, :seed, :t_horizon)` (`scripts/tariff_comparison.jl:352`). Two FlexMarkets mapping to the same name would silently overwrite. **Avoid:** `_flex_row_name` must be injective over (rule, tariff, n_blocks, β), and duplicates throw an `ArgumentError` before solving.

### Pitfall 10: TestItem traps
Use `x = try … catch; nothing end`; wrap loops in functions; mark IEEE-123 and IEEE-13 compare items `:slow`.

## Code Examples

### Fixed-net probe (verified in prototype)
```julia
fm = (m = Model(select_optimizer(QP())); set_silent(m); c = ModelContext(m); c.T = T;
      r = contribute!(agg, c; T = T); @variable(m, pag[1:T]);
      @constraint(m, [t = 1:T], pag[t] == r.p_inject[t] - agg.Pdc[t]); (; m, c, pag))
for t in 1:T; fix(fm.pag[t], b[t]; force = true); end
@objective(fm.m, Max, fm.c.objective); optimize!(fm.m); V0 = objective_value(fm.m)
unfix(fm.pag[h]); @objective(fm.m, Max, fm.pag[h]); optimize!(fm.m); Rup = value(fm.pag[h]) - b[h]
@objective(fm.m, Max, fm.c.objective)
for k in 1:K
    fix(fm.pag[h], b[h] + k * Rup / K; force = true); optimize!(fm.m)   # gate: termination_status == OPTIMAL
    Vk = objective_value(fm.m)                                          # secant m_k = (V_{k-1} − V_k)/(Rup/K)
end
fix(fm.pag[h], b[h]; force = true)
```
In production, gate every probe on `termination_status(m) == MOI.OPTIMAL && primal_status(m) == FEASIBLE_POINT`. Count failures and never throw.

### Ledger flow (e)
```julia
# in build_settlement_ledger, after flow (d); `nothing` ⇒ no rows (default identical)
if flex_payments !== nothing
    for f in flex_payments
        _push_transfer_pair!(transfers, (:aggregator, Int(f.bus)), :dso, Int(f.t),
                             Float64(f.price), Float64(f.quantity))
    end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Pay-as-bid LFM clearing (most pilots) | Debate on uniform/pay-as-clear vs PAB; uniform reported to reduce DSO payments in a two-stage design | 2022–2025 | Our truthful, convex model shows the static ordering: PAB ≤ uniform payments, with identical dispatch |
| Baseline-and-deviation settlement | Critiques favour capacity-limitation products over baselines | 2021 | β sensitivity quantifies the gaming exposure |

- Olivella-Rosell et al., "Local Flexibility Market Design for Aggregators Providing Multiple Flexibility Services at Distribution Network Level", *Energies* 11(4):822, 2018. LFM operated by an aggregator; DSO, BRP and end users as buyers and sellers. [CITED: mdpi.com/1996-1073/11/4/822]
- Heinrich, Ziras, Syrri, Bindner, "EcoGrid 2.0: A large-scale field trial of a local flexibility market", *Applied Energy* 261:114399, 2020. About 800 households and heating units; real-life baseline problems for DSO services. [CITED: ideas.repec.org/a/eee/appene/v261y2020ics0306261919320860.html]
- Ziras, Heinrich, Bindner, "Why baselines are not suited for local flexibility markets", *RSER* 135:110357, 2021. Proposes capacity-limitation services instead of baselines. [CITED: orbit.dtu.dk]
- Hennig, Tindemans, de Vries (EEM 2022; *Utilities Policy* 85, 2023). Most LFM proposals use pay-as-bid; market failures and strategic behaviour are possible. [CITED: repository.tudelft.nl]
- A 2025 *Utilities Policy* paper reports that a uniform-pricing two-stage auction reduces DSO payments relative to a single-stage auction. It was seen only as a search snippet, so it is LOW confidence. [CITED: ideas.repec.org/a/eee/juipol/v93y2025ics0957178725000049.html]
- **Uniform = DLMP under convexity (derivation, not a citation):** with divisible bids that equal the exact separable loss, the stage-2 KKT conditions (m_k = π for an accepted marginal block, and the network KKT shared with `solve_welfare`) coincide with the centralized KKT, so π = λ. This is the first-welfare-theorem and LP-duality analogue (FEATURES insight 2). Our bids are hour-separable approximations of a coupled V, so the equality is approximate. Measured mean |π − λ| = 0.62 on IEEE-13. [ASSUMED: standard duality argument]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | V_j(x) is concave, so single-hour losses are convex | Pattern 1 | Low: measured monotone to 9.2e-5 above the floor |
| A2 | IEEE-123 total mode runtime of about 6–10 min (composed from measured components; `fit_baseline` and stage 2 unmeasured there) | §IEEE-123 | The script needs a longer budget; a timeout is a recorded outcome |
| A3 | A uniform = DLMP equivalence for exact separable bids | State of the Art | Liveness test would fail; it is designed to detect exactly this |
| A4 | κ = 1e-2 for the congested-hour threshold transfers to IEEE-123 | Q8 | β rows mis-attributed; mitigated by reporting robustness over κ |
| A5 | Paying activated (not delivered) quantity is the intended reading of "activated flexibility is paid" | Q5 / Open Q2 | Money split changes; physics is unaffected |

## Open Questions

1. **Tariff on the activated deviation: a consequence of the locked settlement, not a conflict.** Aggregators pay the baseline tariff on metered (delivered) energy *and* receive π·Δ on the deviation. So an up-activated unit earns p + π, while under DADP the marginal unit earns λ ≈ π. Truthful gross-utility bids then over-compensate aggregators by p·Δ relative to a "baseline-settled" design: tariff on b only, plus flex on Δ (equivalently, premium bids m − p paid (π − p)·Δ). This moves money only; dispatch and welfare are unaffected. On IEEE-13, with p = 0.153, it is about 0.153 × 236.9 ≈ 36 units. **Recommendation:** implement as locked, and add an informational column `tariff_on_activation = Σ p_t·Δ_j,t` plus a paragraph on the page. Raise it with the researcher if a baseline-settled variant is wanted (it would be an additive rule).
2. **Pay activated or delivered quantities?** The locked text says "activated". Recommendation: pay activated Δ (plus the β phantom), report the shortfall, and do not book a non-delivery penalty. An optional informational column `flex_payment_on_delivered` would recompute payments on n − b.
3. **IEEE-123 configuration choice:** recommended is the `fixtures_ieee123` population + `tol_gap = 3e-9` (certified, congested under flat). The `build_population(:default, :ieee123)` population is refused by the DADP gate at every documented rung. This needs one new default-`nothing` kwarg, `welfare_optimizer`, on `compare_tariffs`. That is additive and does not conflict with the locked decisions, but it is a public-signature change the planner should make explicit.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 | — (digest goldens are 1.12.5-only) |
| Clarabel / JuMP / Ipopt (pinned) | probes, stage 2, AC | ✓ | pinned Manifest | — |
| RAM | IEEE-123 run | ~1–2 GB free at research time | — | one julia process at a time; per-aggregator probe models are freed after use |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` + TestItems `@testitem` via `Pkg.test()` (TestItemRunner configured in `test/runtests.jl`; tags `:fast`/`:slow`) |
| Config file | `test/runtests.jl`, `test/expected_broken.txt` |
| Quick run command | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl julia --project=. -e 'import Pkg; Pkg.test()'`, then `git checkout -- test/Project.toml test/Manifest.toml` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (orchestrator only, detached via `.github/scripts/suite_detached.sh`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SETL-07 | `FlexMarket` kwarg validation (rule ∈ {:uniform, :pay_as_bid}, tariff ∈ {:flat, :tou}, n_blocks ≥ 1, β ≥ 0 finite); `PriceBased <: AbstractCoordination`; `_flex_row_name` injective, duplicates throw | unit | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl` | ❌ Wave 0 |
| SETL-07 | Bids: Interruptible analytic anchor `m_k = π₀ + b(δ_{k−1}+δ_k)/2`; V(b) = stage-1 utility (measured tol); monotone after the floor; g₁ < m₁; zero range ⇒ no block | unit | same | ❌ Wave 0 |
| SETL-07 | Stage 2 on 2-bus: OPTIMAL + exact; π read via `settlement_input`; infeasible offer (smax below the reachable range) ⇒ `infeasible_redispatch` status, no throw | unit | same | ❌ Wave 0 |
| SETL-07 | Delivery: separable fixture ⇒ shortfall ≤ measured tol; coupled fixture ⇒ shortfall reported > 0; w vs 10w identical within measured tol | unit | same | ❌ Wave 0 |
| SETL-07 | Ledger: `flex_payments = nothing` ⇒ `==` default; uniform and PAB both `ledger_residual == 0.0` and Σ actor balances == 0; PAB dispatch `==` uniform dispatch; PAB aggregators_total ≤ uniform (truthful convex) | unit | same | ❌ Wave 0 |
| SETL-07 | β: overpayment linear in β (0, 0.05, 0.10); physics columns identical across β; congested hours from `decompose_dlmp` | unit | same | ❌ Wave 0 |
| SETL-07 | Liveness: 2-bus Interruptible φ = 1, K ∈ {1,2,4,8,16} ⇒ welfare gap vs `solve_welfare` decreasing and final gap ≤ 3× measured; π vs DADP λ within measured band | integration | same | ❌ Wave 0 |
| SETL-08 | Default fence: 1.12.5 FNV digest of the 4 DataFrames + version-independent column list + same-process `isequal` | regression | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_fence.jl` | ❌ Wave 0 (capture BEFORE src edits) |
| SETL-08 | `welfare_optimizer = nothing` ⇒ `isequal` to the default call; a supplied factory reaches both DADP and stage 2 (signature contract, the `agr_optimizer` test precedent at `test_settlement.jl:984-1090`) | unit | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_fence.jl` | ❌ Wave 0 |
| SETL-08 | `compare_tariffs(...; flex_market = [...])` on the hermetic 2-bus: base 4 rows equal the default, flex rows appended with the full base schema + new columns, statuses populated | integration | `TSODSO_TEST_FILES=test_flex_market.jl` | ❌ Wave 0 |
| SETL-08 | IEEE-13 ground with flex: rows present, status ∈ allowed set, feasibility ∈ status set, welfare gap reported (no golden on the gap until measured over seeds) | slow | `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_flex_market_ieee.jl` | ❌ Wave 0 |
| SETL-08 | IEEE-123 smoke: outcome recorded (ok or status row), never a crash | slow | same | ❌ Wave 0 |
| Both | exports set, JET ratchet, scripts index, docs registration | repo gates | `TSODSO_TEST_FILES=test_exports.jl`; `julia --project=. scripts/jet_check.jl --selftest`; `python3 .github/scripts/check_scripts_index.py` | ✅ |

### Sampling Rate
- **Per task commit:** the task's test file (fast set), plus `test_settlement.jl` when the ledger or comparison is touched.
- **Per wave merge:** `test_flex_market.jl, test_flex_market_fence.jl, test_settlement.jl, test_actor_settlement.jl, test_exports.jl, test_welfare_solve.jl`.
- **Phase gate:** the full suite green against the baseline before `/gsd:verify-work`, with only the known Aqua/CairoMakie drift attributions.

### Wave 0 Gaps
- [ ] `test/test_flex_market_fence.jl`: capture the digest of the default `compare_tariffs` (hermetic 2-bus T = 3) and the default ledger **before any `src/` edit** (`git diff -- src` empty at capture), plus one `skipped` line in `test/expected_broken.txt`.
- [ ] `test/test_flex_market.jl` and `test/test_flex_market_ieee.jl` (`:slow`).
- [ ] Measured tolerances, 3× the maximum over 3 seeds:
  - V(b) reproduction;
  - bid repair maximum;
  - separable shortfall;
  - liveness final gap;
  - π vs λ band;
  - w-sensitivity.
- [ ] Framework install: none.

## Security Domain

This is a research numerics package with no network, auth or crypto surface. ASVS V5 (input validation) is the only applicable category:
- **Inputs:** `ArgumentError` on non-finite or misshaped `flex_payments` rows, bad `FlexMarket` kwargs, duplicate row names, and `houses` + `flex_market`.
- **Solver numbers:** finite guards on NaN/Inf before they reach the ledger. This is the existing `_finite_or_throw` idiom.

| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Solver NaN poisoning artifacts | Tampering (integrity) | finite guards at the ledger/adapters (existing) |
| Silent CSV overwrite via name collision | Tampering | injective names + duplicate guard |

## Sources

### Primary (HIGH confidence)
- Codebase (read this session): `src/settlement/{comparison,price_taker,SettlementLedger,run_inputs,tariffs,feasibility,equity}.jl`, `src/models/welfare_solve.jl`, `src/devices/{Aggregator,AbstractDevice,SmartInverterPV,CapabilityTraits,Interruptible,Deferrable,Thermostatic}.jl`, `src/admm/DsoOpt.jl`, `src/pricing/dlmp.jl`, `src/core/{balance,status,errors}.jl`, `src/experiments/materialize.jl`, `src/data/ieee123.jl`, `scripts/tariff_comparison.jl`, `scripts/actor_behaviour_sweep.jl`, `test/test_actor_default_fence.jl`, `test/test_settlement.jl`, `test/test_ieee123_admm.jl`, `test/test_exports.jl`, `results/settlement_comparison/tariff_comparison.csv`.
- Scratch prototype measurements (this session; scripts outside the repo, in the session scratchpad: `flex_proto.jl`, `flex_123*.jl`).

### Secondary (MEDIUM confidence)
- [Olivella-Rosell et al. 2018, Energies 11(4):822](https://www.mdpi.com/1996-1073/11/4/822)
- [Heinrich et al. 2020, EcoGrid 2.0, Applied Energy 261](https://ideas.repec.org/a/eee/appene/v261y2020ics0306261919320860.html)
- [Ziras et al. 2021, RSER 135:110357](https://orbit.dtu.dk/en/publications/why-baselines-are-not-suited-for-local-flexibility-markets/)
- [Hennig, Tindemans, de Vries: LFM market failures (TU Delft)](https://repository.tudelft.nl/record/uuid:a4bf6019-7064-448e-b199-fbc109fd06da)

### Tertiary (LOW confidence)
- [2025 Utilities Policy two-stage uniform auction](https://ideas.repec.org/a/eee/juipol/v93y2025ics0957178725000049.html), seen as a snippet only.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. No new packages; every seam was read.
- Architecture: HIGH. The full pipeline was prototyped end-to-end on IEEE-13 (stage 2 exact, delivery feasible).
- Pitfalls: HIGH for IEEE-13 (measured). MEDIUM-HIGH for IEEE-123: the DADP, baseline and AC outcomes were measured on both populations; stage 2 and the full mode runtime there are unmeasured.

**Research date:** 2026-11-03
**Valid until:** 2026-12-03 (stable codebase seams; re-measure if `ConvexBranchFlow`, the exactness floor or the price-taker build change).
