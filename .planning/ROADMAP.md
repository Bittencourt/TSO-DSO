# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)
- ✅ **v4.0 Correctness & Depth** — Phases 26–38 (shipped 2026-10-08)
- 🚧 **v5.0 Aggregator Layer at Scale** — Phases 39–46 (in progress)

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

### 🚧 v5.0 Aggregator Layer at Scale (Phases 39–46)

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

- [ ] **Phase 39: Parallel-Ready ADMM & Gating Measurements** - Opt-in threaded aggregator solves, additive result keys, Clarabel concurrency spike, and 8500 memory attribution
- [ ] **Phase 40: 784-House Thesis Population** - True Case A population via a new selector, per-house seeding, household map, centralized-vs-ADMM agreement and scaling report
- [ ] **Phase 41: Settlement, Ledger & Equity** - Conserved per-actor ledger, tariff schemes, AC feasibility status, equity metrics, rebound
- [ ] **Phase 42: Thesis Case A Magnitude** - Pre-registered protocol, honest DADP-vs-FIT gain on 784 houses, and gap ablation
- [ ] **Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter)** - Trait refactor then V1G/V2G EVs, 2R2C heat pumps and PV reactive capability, each validated against centralized
- [ ] **Phase 44: Aggregator as Actor** - Welfare vs profit (wedge) objectives, multi-bus portfolios, exogenous compliance/opt-out/rebound
- [ ] **Phase 45: Flexibility Market vs Price Coordination** - DSO flexibility market with explicit baseline/payment rule and the cross-scheme comparison table
- [ ] **Phase 46: IEEE-8500 Headline Measurement (go/no-go)** - Recorded go/no-go and a measured 8500 table through `Scenario`

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
**Plans**: TBD

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
**Plans**: TBD

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
**Plans**: TBD

### Phase 42: Thesis Case A Magnitude
**Goal**: A researcher gets an honest, pre-registered measurement of the DADP-vs-FIT welfare gain at the real 784-house population and an attribution of its gap to the thesis +25%.
**Depends on**: Phase 40, Phase 41
**Requirements**: REPRO-03, REPRO-04, REPRO-05
**Success Criteria** (what must be TRUE):
  1. The Case A protocol (welfare-gain definition, baseline, parameters) is written and committed before the Case A run is executed.
  2. Case A on the 784-house population reports the DADP-vs-FIT welfare gain as absolute and relative values with a seed spread, whatever its magnitude and sign.
  3. An ablation (FIT parameters, price range, population, device mix) attributes the remaining gap to +25% and is compared against the 1-house-per-bus proxy (≈+0.26%), with no parameter tuned toward the target.
**Plans**: TBD

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
**Plans**: TBD

### Phase 44: Aggregator as Actor
**Goal**: A researcher can give each aggregator its own objective, span a portfolio across buses, and apply exogenous behavioural scenarios, with welfare always reported as social welfare.
**Depends on**: Phase 41
**Requirements**: ACTOR-01, ACTOR-02, ACTOR-03, ACTOR-04
**Success Criteria** (what must be TRUE):
  1. A researcher chooses per aggregator between social-welfare (default, unchanged) and profit-with-wedge (DSO price vs retail tariff).
  2. With zero wedge the profit objective reproduces the welfare optimum (pass-through test), and a non-zero wedge reports its efficiency loss while `welfare` remains social welfare.
  3. One aggregator can hold a multi-bus portfolio with consensus keyed by (aggregator, bus), and single-bus aggregators remain byte-identical to v4.0.
  4. Partial compliance, opt-out and rebound are seeded scenario parameters whose effects on welfare, prices and settlement are reported.
**Plans**: TBD

### Phase 45: Flexibility Market vs Price Coordination
**Goal**: A researcher can run a DSO flexibility market as an alternative to price-based coordination and compare all schemes in one table.
**Depends on**: Phase 41, Phase 44
**Requirements**: SETL-07, SETL-08
**Success Criteria** (what must be TRUE):
  1. A researcher runs a flexibility market with an explicit baseline and payment rule (uniform or pay-as-bid) and gets the same settlement record as price-based coordination.
  2. A comparison table reports welfare, per-actor surplus, network feasibility and equity across FIT, TOU, flat, DADP and the flexibility market on the same scenario.
**Plans**: TBD

### Phase 46: IEEE-8500 Headline Measurement (go/no-go)
**Goal**: A researcher gets a recorded go/no-go and a measured IEEE-8500 outcome, where memory-infeasible or refused-with-certificate is an acceptable measured result.
**Depends on**: Phase 39, Phase 40
**Requirements**: SCALE-07, SCALE-08
**Success Criteria** (what must be TRUE):
  1. A go/no-go is recorded: GO only if attribution projects peak memory below ~10 GiB on the 15 GB host, otherwise "memory-infeasible on this host" with a lower-bounded requirement.
  2. On GO, the IEEE-8500 headline point runs through `Scenario` (feeder selector widened additively) and a table reports size, build time, solve time, iterations, peak memory and exactness verdict, with "refused with certificate" counting as measured.
  3. No tolerance, τ or hybrid floor is changed to obtain the outcome.
**Plans**: TBD

### Coherence notes (departures from the research order)

None: the eight phases follow the reconciled build order exactly. Two placement choices worth
noting: SETL-07/SETL-08 sit in Phase 45 (not Phase 41) because the flexibility market and the
five-scheme comparison need the aggregator actor; SCALE-06 (attribution) sits in Phase 39 and
SCALE-07/08 (decision and run) in Phase 46, splitting measurement from the headline run.

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 39. Parallel-Ready ADMM & Gating Measurements | 0/TBD | Not started | - |
| 40. 784-House Thesis Population | 0/TBD | Not started | - |
| 41. Settlement, Ledger & Equity | 0/TBD | Not started | - |
| 42. Thesis Case A Magnitude | 0/TBD | Not started | - |
| 43. Flexible Devices (EV, Heat Pump, Smart Inverter) | 0/TBD | Not started | - |
| 44. Aggregator as Actor | 0/TBD | Not started | - |
| 45. Flexibility Market vs Price Coordination | 0/TBD | Not started | - |
| 46. IEEE-8500 Headline Measurement (go/no-go) | 0/TBD | Not started | - |

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
