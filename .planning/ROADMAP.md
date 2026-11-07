# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)
- ✅ **v4.0 Correctness & Depth** — Phases 26–38 (shipped 2026-10-08)
- 🚧 **v5.0 Aggregator Layer at Scale** — Phases 39–47 (in progress)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md),
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md),
[`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md), and
[`milestones/v4.0-ROADMAP.md`](milestones/v4.0-ROADMAP.md).

## Phases

<details>
<summary>✅ v4.0 Correctness & Depth (Phases 26–38) — SHIPPED 2026-10-08</summary>

- [x] Phase 26: Network & Device Model Correctness
- [x] Phase 27: Integer Planning & Pricing Certificate Correctness
- [x] Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement
- [x] Phase 29: Genuine Bilevel TSO-DSO Variant
- [x] Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder
- [x] Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh
- [x] Phase 32: Declarative Power-Flow & Strategy Dispatch
- [x] Phase 33: Shared Abstractions — Feeder, Balance, Model Context
- [x] Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy
- [x] Phase 35: IEEE-8500 Scale After Refactor
- [x] Phase 36: Code & Export Cleanup
- [x] Phase 37: Test Infrastructure & Repo Hygiene
- [x] Phase 38: Close v4.0 Audit Gaps

</details>

### 🚧 v5.0 Aggregator Layer at Scale (Phases 39–47)

**Milestone goal:** Make the DSO⇄aggregators operational layer realistic and publishable at true
population scale: real prosumer populations solved in parallel, aggregators modeled as actors with
their own objectives, per-actor settlement and equity outputs, and richer flexible devices.

**Policies inherited by every phase (stated once):**

- **Golden policy** — the default path is byte-identical to v4.0. New behaviour is opt-in (new
  types, selectors, kwargs). The knife-edge canary (`iters = 56`, `welfare = -4823.66604824162`)
  and all existing goldens are never re-pinned; new goldens are pinned only on sign-safe,
  reproducible quantities.

- **Honesty policy** — results that fail a certificate are reported, not hidden; the exactness
  gate (τ, hybrid floor) is never loosened to make a run pass; "refused with certificate" and
  "memory-infeasible" are valid measured outcomes.

Build order follows the reconciled research order (`research/SUMMARY.md`) unchanged: parallel-first
with a thin Phase 39, population, settlement, Case A, devices (may run concurrently with 41–42),
aggregator actor, flexibility market, and the IEEE-8500 headline last behind a go/no-go.

- [x] **Phase 39: Parallel-Ready ADMM & Gating Measurements** - Opt-in threaded aggregator solves, additive result keys, Clarabel concurrency spike, and 8500 memory attribution (completed 2026-10-24)
- [x] **Phase 40: 784-House Thesis Population** - True Case A population via a new selector, per-house seeding, household map, centralized-vs-ADMM agreement and scaling report (completed 2026-10-24)
- [x] **Phase 41: Settlement, Ledger & Equity** - Conserved per-actor ledger, tariff schemes, AC feasibility status, equity metrics, rebound (completed 2026-10-26)
- [x] **Phase 42: Thesis Case A Magnitude** - Pre-registered protocol, honest DADP-vs-FIT gain on 784 houses, and gap ablation (completed 2026-10-26)
- [x] **Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter)** - Trait refactor then V1G/V2G EVs, 2R2C heat pumps and PV reactive capability, each validated against centralized (completed 2026-11-02)
- [x] **Phase 44: Aggregator as Actor** - Welfare vs profit (wedge) objectives, multi-bus portfolios, exogenous compliance/opt-out/rebound (completed 2026-11-03)
- [x] **Phase 45: Flexibility Market vs Price Coordination** - DSO flexibility market with explicit baseline/payment rule and the cross-scheme comparison table (completed 2026-11-05)
- [x] **Phase 46: IEEE-8500 Headline Measurement (go/no-go)** - Recorded go/no-go and a measured 8500 table through `Scenario` (completed 2026-11-05)
- [ ] **Phase 47: v5.0 Audit Gap Closure** - Honest V2G certificates on the flex-market and price-taker paths; loud refusal of actors and reactive/flex devices where unsupported (gap closure from v5.0-MILESTONE-AUDIT.md)

## Phase Details

### Phase 39: Parallel-Ready ADMM & Gating Measurements

**Goal**: A researcher can opt in to solving aggregator subproblems concurrently with results identical to serial, and the gating facts for later phases (Clarabel concurrency, 8500 memory attribution) are measured.
**Depends on**: Nothing (first v5.0 phase)
**Requirements**: PAR-01, PAR-02, PAR-03, PAR-04, PAR-05, SCALE-06
**Success Criteria** (what must be TRUE):

  1. A documented Clarabel concurrency/determinism spike exists (including the `direct_model` question) and states whether threaded solves are bitwise-equal to serial under `-t 4`; threaded execution is only enabled if it passes.
  2. A researcher selects the threaded executor opt-in, and on a multi-aggregator fixture threaded and serial runs are `==` on iterations, residual traces, welfare and prices; the default serial path still hits the canary (`iters = 56`, `welfare = -4823.66604824162`) unchanged.
  3. A solver or certificate error raised inside a parallel task surfaces with the same error type and node attribution as in serial.
  4. Run provenance records thread and BLAS-thread counts, while the executor choice leaves scenario `==`, `hash` and saved filename unchanged.
  5. ADMM results expose per-aggregator dispatch, utilities, import profile and per-slot prices as additive keys; and the ~3.4 GiB unattributed IEEE-8500 memory growth is profiled and attributed in a documented result.

**Plans**: 5 plans

Plans:
**Wave 1**

- [x] 39-01-PLAN.md — Clarabel concurrency/determinism spike (bitwise serial-vs-threaded under `-t 4`, direct_model answer) — PAR-02 gate
- [x] 39-03-PLAN.md — Provenance thread counts + executor-blind scenario identity — PAR-04

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 39-02-PLAN.md — Opt-in threaded executor on solve_admm (kwarg + fail-loud guard, split AGR step, fetch-in-order join) — PAR-01, PAR-03

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 39-04-PLAN.md — Bitwise equality + error-parity tests, per-aggregator additive result keys — PAR-02, PAR-03, PAR-05

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 39-05-PLAN.md — SCALE-06 staged RSS memory attribution (d=0.1 T=10/24) + doc note

### Phase 40: 784-House Thesis Population

**Goal**: A researcher can build, solve and scale the thesis Case A population at its true 784-household size, reproducibly and with documented calibration.
**Depends on**: Phase 39
**Requirements**: POP-01, POP-02, POP-03, POP-04, POP-05, POP-06
**Success Criteria** (what must be TRUE):

  1. A researcher selects the 784-house Case A population via a new selector over the 10 IEEE-13 aggregator nodes, and the existing `:default` population stays byte-identical.
  2. Each house is seeded from (master seed, bus, house index): rebuilding reproduces the population exactly and no two houses share a seed; a household map (house → bus, aggregator, device set, PV/non-PV group) is available.
  3. The 784-house case solved centralized and by ADMM agrees on welfare and prices within a measured, stated tolerance.
  4. A scaling report gives measured wall time vs threads and ADMM iterations vs population size (speedup measured, not assumed, including a negative result if overhead-bound).
  5. Documentation states the population's composition (PV capacity, elastic/inelastic load, device mix) with calibration provenance and which thesis (Appendix E) parameters are unavailable.

**Plans**: 6 plans (2 gap-closure plans added 2026-10-24 for the POP-04 verification gap)

Plans:
**Wave 1**

- [x] 40-01-PLAN.md — Additive `:case_a_784` selector: per-house hash seeding, 10-bus roll-up (1:1 ADMM guard), household map accessor, fast test file — POP-01, POP-02, POP-03

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 40-02-PLAN.md — Scaling report: subprocess threads sweep (-t 1/2/4) + nested-prefix population ladder → committed CSVs + smoke test — POP-05

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 40-03-PLAN.md — Centralized-vs-ADMM agreement at full scale: measure deltas → pin band gate-then-golden in a `:slow` test — POP-04

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 40-04-PLAN.md — Composition/calibration literate page (build-only live slice, CSV-sourced measurements) + both make.jl registrations — POP-06

**Gap closure** *(verification 2026-10-24: gaps_found — POP-04 agreement band; fix path (a) the bounded precision seam)*

- [x] 40-05-PLAN.md — Additive AGR solver-precision seam: `select_optimizer(QP; attrs...)` + `build_agr_opt`/`solve_admm` `agr_optimizer` kwarg; default path byte-identical (canary pinned) — POP-04
- [x] 40-06-PLAN.md — Bounded solver-precision ladder at full scale (default + gap_1e-10 → gap_1e-12 → gapfeas_1e-12, stop-on-first-certified, hard stop) → agreement.csv record → pin the band / document non-closure (terminal state) — POP-04

### Phase 41: Settlement, Ledger & Equity

**Goal**: A researcher can settle any run into a money-conserving per-actor ledger, compare tariff schemes on the same network and population, and read equity and rebound outcomes.
**Depends on**: Phase 39, Phase 40
**Requirements**: SETL-01, SETL-02, SETL-03, SETL-04, SETL-05, SETL-06
**Success Criteria** (what must be TRUE):

  1. A run settles into a ledger over DSO, each aggregator, each household and wholesale, and a test shows actors sum to zero with an explicit merchandising-surplus line.
  2. FIT, TOU, flat and nodal DADP tariffs can be compared on the same network and population, with flat and TOU derived revenue-neutral from the DADP run.
  3. Each tariff's resulting dispatch has an AC-physics network-feasibility status that is reported, never thrown.
  4. Gini, Theil, Atkinson and Palma on per-household bills/surplus pass known-value tests, including negative values, and results are broken out by PV owner/non-owner, electrical location and load level, with the writeup stating no income data is used.
  5. A rebound metric reports load shifted into later hours after price-driven reductions.

**Plans**: 4 plans

Plans:
**Wave 1**

- [x] 41-01-PLAN.md — Settlement core: double-entry `SettlementLedger` (DSO/aggregators/households/wholesale, explicit merchandising-surplus line, exact sum-to-zero) + run-input adapters (centralized ctx / converged ADMM, loud non-converged guard) + conservation/sign/oracle tests incl. `:slow` IEEE-13 T=24 real-run identity — SETL-01

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 41-02-PLAN.md — Equity & rebound layer: Gini/Theil/Atkinson/Palma with documented negative-value conventions + known-value certificates, PV/bus/load-tercile breakouts from the household map, rebound metric — SETL-04, SETL-05, SETL-06

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 41-03-PLAN.md — Tariff construction & counterfactuals: revenue-neutral flat/TOU price derivation (pinned TOU bins), thin penalty-free price-taker dispatch QP (battery-certificate report semantics, per-house separability), AC-feasibility status wrapper (report, never throw) — SETL-02, SETL-03

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 41-04-PLAN.md — Comparison deliverable: `compare_tariffs` runner, scripts/tariff_comparison.jl committed CSVs (784-house + ground modes, honest status rows), literate writeup with the no-income-data statement registered at both make.jl sites — SETL-02, SETL-05

### Phase 42: Thesis Case A Magnitude

**Goal**: A researcher gets an honest, pre-registered measurement of the DADP-vs-FIT welfare gain at the real 784-house population and an attribution of its gap to the thesis +25%.
**Depends on**: Phase 40, Phase 41
**Requirements**: REPRO-03, REPRO-04, REPRO-05
**Success Criteria** (what must be TRUE):

  1. The Case A protocol (welfare-gain definition, baseline, parameters) is written and committed before the Case A run is executed.
  2. Case A on the 784-house population reports the DADP-vs-FIT welfare gain as absolute and relative values with a seed spread, whatever its magnitude and sign.
  3. An ablation (FIT parameters, price range, population, device mix) attributes the remaining gap to +25% and is compared against the 1-house-per-bus proxy (≈+0.26%), with no parameter tuned toward the target.

**Plans**: 6 plans in 5 waves (one 784-house measurement process at a time; the heavy run is a single late plan; all machinery certified on small fixtures first)

**Wave 1** *(parallel: protocol docs+lib / settlement seam)*

- [x] 42-01-PLAN.md — Pre-registration: commit 42-CASE-A-PROTOCOL.md (own commit, before any run) + sign-safe `welfare_gain` + fail-loud protocol guard in `scripts/lib/case_a_common.jl` + fast-lane tests — REPRO-03
- [x] 42-02-PLAN.md — `compare_tariffs` additive `agr_optimizer` passthrough (byte-identical default; Option B) so settlement lenses run at the ladder-certified point — REPRO-04/05 enabler

**Wave 2** *(blocked on Wave 1)*

- [x] 42-03-PLAN.md — Runner `scripts/case_a_magnitude.jl`: protocol-gated headline+proxy modes, AGR ladder, honest status rows, upsert CSVs; certified end-to-end on the IEEE-123/IEEE-13 proxy fixtures (proxy.csv committed) — REPRO-03/04/05

**Wave 3** *(blocked on Wave 2)*

- [x] 42-04-PLAN.md — OFAT ablation modes (4 protocol-pinned axes as committed Dicts), device-mix script-side rebuild + map-consistency tripwire, small-scale certification row — REPRO-05

**Wave 4** *(blocked on Wave 3; heavy — background per-unit invocations, kill-anytime)*

- [x] 42-05-PLAN.md — THE MEASUREMENT: 784-house headline seeds 42–46, centralized cross-check + settlement lenses (seed 42), full four-axis ablation → committed magnitude/crosscheck/lens_summary/ablation CSVs — REPRO-04/05

**Wave 5** *(blocked on Wave 4)*

- [x] 42-06-PLAN.md — Closure: `:slow` seed-42 reproducibility band (gate-then-golden on plumbing, not magnitude), literate writeup reading committed CSVs (live-recomputed figures, A1/A4 asymmetry, honest-magnitude framing), both make.jl registrations — REPRO-03/04/05

### Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter)

**Goal**: A researcher can add EVs, heat pumps and smart-inverter PV as convex, binary-free devices, each validated against the centralized solve before ADMM use.
**Depends on**: Phase 39 (independent of 41–42; may run concurrently with them)
**Requirements**: DEV-06, DEV-07, DEV-08, DEV-09, DEV-10
**Success Criteria** (what must be TRUE):

  1. The device-capability trait refactor lands first and existing fixtures keep their resolved reactive mode and goldens unchanged.
  2. A researcher adds EVs with seeded arrival/departure sessions and a soft departure energy target (V1G), then enables V2G with strictly positive degradation cost; a certificate reports any simultaneous charge/discharge, including on a negative-price fixture.
  3. A researcher adds heat pumps with a 2R2C thermal model, exogenous COP(T_out) and a comfort band under a consistent terminal-temperature rule.
  4. PV can supply optimal reactive power within an apparent-power cone, with SOCP exactness re-measured in the high-PV regime and a Volt-VAR droop curve evaluated only post hoc as a comparator.
  5. Each new device class matches the centralized solve before it is used under ADMM.

**Plans**: 5 plans

Plans:
- [x] 43-01-PLAN.md — Capability-trait refactor (has_reactive_decision + storage_kind) with classification-equivalence test; FixedCapacitor asymmetry preserved — DEV-10
- [x] 43-02-PLAN.md — ElectricVehicle V1G/V2G (session windows as bounds, quadratic soft target, c_deg > 0, EV certificate + negative-price fixture) + crossval gate — DEV-06/07/10
- [x] 43-03-PLAN.md — HeatPump 2R2C (exogenous COP, comfort band, joint terminal rule, flexible-load roll-up) + crossval gate — DEV-08/10
- [x] 43-04-PLAN.md — SmartInverterPV (anonymous apparent-power cone, zero-utility Q through reactive consensus, μ crossval) — DEV-09/10
- [x] 43-05-PLAN.md — build_population flex_devices opt-in + hash-seeded EV sessions (Scenario untouched); SOCP exactness re-measurement script + committed CSV + droop post-hoc comparator + literate page — DEV-06/09

### Phase 44: Aggregator as Actor

**Goal**: A researcher can give each aggregator its own objective, span a portfolio across buses, and apply exogenous behavioural scenarios, with welfare always reported as social welfare.
**Depends on**: Phase 41
**Requirements**: ACTOR-01, ACTOR-02, ACTOR-03, ACTOR-04
**Success Criteria** (what must be TRUE):

  1. A researcher chooses per aggregator between social-welfare (default, unchanged) and profit-with-wedge (DSO price vs retail tariff).
  2. With zero wedge the profit objective reproduces the welfare optimum (pass-through test), and a non-zero wedge reports its efficiency loss while `welfare` remains social welfare.
  3. One aggregator can hold a multi-bus portfolio with consensus keyed by (aggregator, bus), and single-bus aggregators remain byte-identical to v4.0.
  4. Partial compliance, opt-out and rebound are seeded scenario parameters whose effects on welfare, prices and settlement are reported.

**Plans**: 7 plans (44-01..44-07)

### Phase 45: Flexibility Market vs Price Coordination

**Goal**: A researcher can run a DSO flexibility market as an alternative to price-based coordination and compare all schemes in one table.
**Depends on**: Phase 41, Phase 44
**Requirements**: SETL-07, SETL-08
**Success Criteria** (what must be TRUE):

  1. A researcher runs a flexibility market with an explicit baseline and payment rule (uniform or pay-as-bid) and gets the same settlement record as price-based coordination.
  2. A comparison table reports welfare, per-actor surplus, network feasibility and equity across FIT, TOU, flat, DADP and the flexibility market on the same scenario.

**Plans**: 7 plans in 7 waves (sequential: the plans share test/test_flex_market.jl, src/TSODSO.jl and docs/src/api.md; the default-path fence lands before any src edit)

Plans:
- [x] 45-01-PLAN.md — Default-path digest fence (captured with src unchanged) + coordination types `AbstractCoordination`/`PriceBased`/`FlexMarket`, injective row names, exports, api.md block — SETL-07/08
- [x] 45-02-PLAN.md — Ledger `flex_payments` mirror-pair flow (residual == 0.0) + bid probing on the aggregator's own fixed-net model (range floor, PAV repair) — SETL-07
- [x] 45-03-PLAN.md — Stage-2 redispatch via `solve_welfare` over bid pseudo-devices (status mapping, gated prices, congested hours) + L1 delivery tracking with reported shortfall — SETL-07
- [x] 45-04-PLAN.md — Uniform / pay-as-bid / β payment rows, exported `clear_flex_market`, conservation tests + liveness vs the centralized social-welfare optimum — SETL-07
- [x] 45-05-PLAN.md — `compare_tariffs` `flex_market` + `welfare_optimizer` keywords (`:admm` refusal, FixedCapacitor guard), additive flex rows/columns incl. lossless welfare gap, JET — SETL-08
- [x] 45-06-PLAN.md — Script `--flex-market`, `ieee123` / `ieee123-default` modes, committed CSV rows (run_wall_s, shortfall in bills/rebound), slow IEEE-13/IEEE-123 tests — SETL-07/08
- [x] 45-07-PLAN.md — Literate page with the honest framings, docs/scripts registration, api.md checkdocs gap closure, formatter/JET/guard gates, requirement closure — SETL-07/08

### Phase 46: IEEE-8500 Headline Measurement (go/no-go)

**Goal**: A researcher gets a recorded go/no-go and a measured IEEE-8500 outcome, where memory-infeasible or refused-with-certificate is an acceptable measured result.
**Depends on**: Phase 39, Phase 40
**Requirements**: SCALE-07, SCALE-08
**Success Criteria** (what must be TRUE):

  1. A go/no-go is recorded: GO only if attribution projects peak memory below ~10 GiB on the 15 GB host, otherwise "memory-infeasible on this host" with a lower-bounded requirement.
  2. On GO, the IEEE-8500 headline point runs through `Scenario` (feeder selector widened additively) and a table reports size, build time, solve time, iterations, peak memory and exactness verdict, with "refused with certificate" counting as measured.
  3. No tolerance, τ or hybrid floor is changed to obtain the outcome.

**Plans**: 5 plans in 5 waves (sequential; the measured T = 10 run is launched by the orchestrator at the 46-04 checkpoint)

Plans:
- [x] 46-01-PLAN.md — Widen `Scenario` feeders to `:ieee8500`/`:ieee8500_mv`, `:default_10pct` population selector, guards for unmeasured combinations, tiny construction/materialization/harness-equivalence tests — SCALE-08
- [x] 46-02-PLAN.md — `scripts/ieee8500_scenario_point.jl`: phase-timed Scenario run with status rows, MemAvailable pre-flight, keyed upsert, `--record-nogo` — SCALE-07/08
- [x] 46-03-PLAN.md — Script helper tests + IEEE-13 parity with `run_scenario`, scripts index row, committed T = 24 NO-GO row — SCALE-07/08
- [x] 46-04-PLAN.md — Launch-readiness check + orchestrator-launched detached T = 10 IEEE-8500 point (user-approved 7.1 GiB launch; outcome refused_certificate) — SCALE-08
- [x] 46-05-PLAN.md — Committed measured rows, dated docs section computed from the CSVs (NO-GO threshold verdict, B1/B2, Scenario-path table, divergences, supersessions), gates, requirement closure — SCALE-07/08

### Phase 47: v5.0 Audit Gap Closure

**Goal**: Every certificate on the price-taker and flex-market paths reports only checks that actually ran, and every combination the milestone did not wire is refused loudly instead of silently mis-handled.
**Depends on**: Phase 43, Phase 44, Phase 45
**Requirements**: DEV-07, SETL-07, SETL-08 (gap closure; audit items B1, B2, W2, W3 in `.planning/v5.0-MILESTONE-AUDIT.md`)
**Gap Closure**: Closes B1 (V2G EV certificate falsely `:ok` on `price_taker_dispatch` / `clear_flex_market`), B2 (actor objectives not wired into the flex market or `compare_tariffs`: recorded scope decision + guard), W2 (`compare_tariffs` refuses Phase-43 devices only after expensive solves), W3 (reactive-capable devices' q silently dropped in flex stage 2).
**Success Criteria** (what must be TRUE):

  1. On `price_taker_dispatch` and `clear_flex_market`, battery-certificate selection uses the device-type trait (not the variable shape), and populations with V2G EVs get the EV co-charge certificate run and reported as its own recorded status. A V2G fixture on each path (including a negative-price co-charge case) shows the certificate reporting, never a false `:ok`.
  2. `compare_tariffs` and `clear_flex_market` refuse actor inputs (non-welfare objectives / portfolios) with an `ArgumentError`, and the scope decision "actors × flexibility market / tariff comparison is future work" is recorded in REQUIREMENTS.md, the audit and the docs limitations.
  3. `compare_tariffs` refuses unsupported Phase-43 devices before any solve; flex stage 2 refuses devices with a reactive decision (`SmartInverterPV`, `FourQuadBESS`) the same way it refuses `FixedCapacitor`. Each guard is tested.
  4. Default paths, goldens and the knife-edge canary stay byte-identical; no tolerance, τ, ε or hybrid floor changes; committed result CSVs are unchanged.

**Plans**: TBD

### Coherence notes (departures from the research order)

None: the eight phases follow the reconciled build order exactly. Two placement choices worth
noting: SETL-07/SETL-08 sit in Phase 45 (not Phase 41) because the flexibility market and the
five-scheme comparison need the aggregator actor; SCALE-06 (attribution) sits in Phase 39 and
SCALE-07/08 (decision and run) in Phase 46, splitting measurement from the headline run.

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 39. Parallel-Ready ADMM & Gating Measurements | 5/5 | Complete    | 2026-10-24 |
| 40. 784-House Thesis Population | 6/6 | Complete    | 2026-10-24 |
| 41. Settlement, Ledger & Equity | 4/4 | Complete    | 2026-10-26 |
| 42. Thesis Case A Magnitude | 6/6 | Complete    | 2026-10-26 |
| 43. Flexible Devices (EV, Heat Pump, Smart Inverter) | 5/5 | Complete    | 2026-11-02 |
| 44. Aggregator as Actor | 7/7 | Complete    | 2026-11-03 |
| 45. Flexibility Market vs Price Coordination | 7/7 | Complete    | 2026-11-05 |
| 46. IEEE-8500 Headline Measurement (go/no-go) | 5/5 | Complete    | 2026-11-06 |
| 47. v5.0 Audit Gap Closure | 0/? | Not started | - |

## Deferred / Future-Milestone Notes

- **Large-lattice integer termination criterion** — a rigorous `δ_min` is not derivable (`Q`'s
  local slope is a continuous SOCP dual price with no established Lipschitz bound), so the
  enumeration-backed criterion (Phase 24, v3.0) is tractable only where enumeration is. BILEV-07
  (Phase 31, v4.0) extends integer investment to N>1 Nash but does not resolve this; still open
  past v4.0.

Items formerly listed here — **SCALE-STRETCH**, the Phase-18 `fit_baseline` convergence flake,
the MESH-06 composition advisory, and integer investment beyond single-distributor Stackelberg —
are now in scope for v4.0 as ARCH-10 (Phase 35), FIX-09 (Phase 27), ARCH-06 (Phase 34), and
BILEV-07 (Phase 31) respectively, and are no longer deferred.
