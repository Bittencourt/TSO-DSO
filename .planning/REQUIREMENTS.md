# Requirements — Milestone v5.0 Aggregator Layer at Scale

**Defined:** 2026-10-09
**Core Value:** A researcher can express a scenario and a model variant declaratively, run it
end-to-end with an open-source solver, and get trustworthy, reproducible results and prices — with
every model assumption documented and every layer swappable.

**Goal:** Make the DSO⇄aggregators operational layer realistic and publishable at true population
scale: real prosumer populations solved in parallel, aggregators modeled as actors with their own
objectives, per-actor settlement and equity outputs, and richer flexible devices.

**Golden policy (applies to every requirement):** unlike v4.0, the default path is **byte-identical
again**. New behaviour is opt-in (new types, selectors, kwargs); the knife-edge canary
(`iters = 56`, `welfare = -4823.66604824162`) and existing goldens are never re-pinned. New goldens
are pinned only on sign-safe, reproducible quantities.

**Honesty policy:** results that fail a certificate are reported, not hidden; the exactness gate
(τ, hybrid floor) is never loosened to make a run pass; "refused with certificate" and
"memory-infeasible" are valid measured outcomes.

Research: `.planning/research/SUMMARY.md` (+ STACK, FEATURES, ARCHITECTURE, PITFALLS).

## v5.0 Requirements

### Parallel ADMM (PAR)

- [ ] **PAR-01**: A researcher can run the DSO⇄aggregator ADMM with aggregator subproblems solved concurrently on threads (opt-in executor); the serial executor remains the default and is byte-identical to v4.0 (canary unchanged).
- [ ] **PAR-02**: Threaded and serial runs of the same scenario give identical results (`==` on iterations, residual traces, welfare and prices), verified by a test on a multi-aggregator fixture; parallel work is gated on a documented Clarabel concurrency/determinism spike.
- [ ] **PAR-03**: Solver errors raised inside a parallel task surface with the same error types and node attribution as in serial runs (certificate errors still match by type).
- [ ] **PAR-04**: Run provenance records the thread and BLAS-thread counts, and the executor choice does not change a scenario's identity (`==`, `hash`, saved filename).
- [ ] **PAR-05**: ADMM results expose the per-aggregator dispatch, utilities, import profile and per-slot prices needed downstream (additive result keys; existing keys unchanged).

### Population (POP)

- [ ] **POP-01**: A researcher can build the thesis Case A population with its true house count (784 households over the 10 IEEE-13 aggregator nodes) via a new selector, leaving the existing `:default` population byte-identical.
- [ ] **POP-02**: Each household is individually seeded from a hash of (master seed, bus, house index), so populations are reproducible and seeds never collide.
- [ ] **POP-03**: The population records a household map (house → bus, aggregator, device set, PV/non-PV group) usable for household-level settlement and equity.
- [ ] **POP-04**: The 784-house case solves both centralized and by ADMM, and the two agree on welfare and prices within a measured tolerance.
- [ ] **POP-05**: A scaling report gives wall time vs threads and ADMM iterations vs population size, with the speedup measured (not assumed).
- [ ] **POP-06**: The population's composition (PV capacity, elastic and inelastic load, device mix) is documented with calibration provenance, stating which thesis parameters are unavailable (Appendix E).

### Settlement & equity (SETL)

- [ ] **SETL-01**: A researcher can settle any run into a per-actor ledger (DSO, each aggregator, each household, wholesale), and a test verifies the ledger conserves money (actors sum to zero, with an explicit merchandising-surplus line).
- [ ] **SETL-02**: A researcher can compare tariff schemes on the same network and population — feed-in tariff, time-of-use, flat, and nodal day-ahead dynamic price — with flat and TOU derived revenue-neutral from the DADP run.
- [ ] **SETL-03**: Network feasibility of each tariff's resulting dispatch is evaluated on AC physics and reported as a status (never thrown).
- [ ] **SETL-04**: A researcher can compute equity metrics (Gini, Theil, Atkinson, Palma) on per-household bills/surplus, sign-safe for negative values, with known-value tests.
- [ ] **SETL-05**: Equity results are reported by proxy group (PV owners vs non-owners, electrical location, load level), and the writeup states that no income data is used.
- [ ] **SETL-06**: A rebound metric reports load shifted into later hours after price-driven reductions.
- [ ] **SETL-07**: A researcher can run a DSO flexibility market (explicit baseline and payment rule — uniform or pay-as-bid) as an alternative coordination scheme, producing the same settlement record as price-based coordination.
- [ ] **SETL-08**: A comparison table reports welfare, per-actor surplus, network feasibility and equity across FIT, TOU, flat, DADP and the flexibility market.

### Thesis Case A magnitude (REPRO)

- [ ] **REPRO-03**: The Case A protocol (welfare-gain definition, baseline, parameters) is pre-registered in writing before the run.
- [ ] **REPRO-04**: A researcher can run Case A on the real 784-house population and get the DADP-vs-FIT welfare gain as absolute and relative values with a seed spread, reported honestly whatever its magnitude.
- [ ] **REPRO-05**: An ablation attributes the remaining gap to the thesis +25% (FIT parameters, price range, population, device mix), and it is compared with the 1-house-per-bus proxy (≈+0.26%); no parameter is tuned toward the target.

### Devices (DEV)

- [ ] **DEV-06**: A researcher can add EVs with arrival/departure windows and a (soft) departure energy target as smart-charging (V1G) devices, with seeded session sampling.
- [ ] **DEV-07**: A researcher can enable V2G on EVs with a strictly positive degradation cost, and a certificate reports any simultaneous charge/discharge (including a negative-price fixture).
- [ ] **DEV-08**: A researcher can add heat pumps with a 2R2C building thermal model, an exogenous COP(T_out) profile and a comfort band, with a consistent terminal-temperature rule.
- [ ] **DEV-09**: A researcher can give PV a smart-inverter reactive capability (apparent-power cone, optimal Q), with SOCP exactness re-measured in the high-PV regime; a Volt-VAR droop curve is evaluated only after the fact as a comparator.
- [ ] **DEV-10**: Each new device class is validated against the centralized solve before ADMM use, and existing fixtures keep their resolved reactive mode (the device-capability trait refactor changes no behaviour).

### Aggregator as actor (ACTOR)

- [ ] **ACTOR-01**: A researcher can choose an aggregator objective — social welfare (default, unchanged) or profit between the DSO price and a retail tariff (wedge) — per aggregator.
- [ ] **ACTOR-02**: With a zero wedge the profit objective reproduces the welfare optimum (pass-through test), and the efficiency loss of a non-zero wedge is reported; reported `welfare` always stays social welfare.
- [ ] **ACTOR-03**: A researcher can assign one aggregator a portfolio spanning several buses, with ADMM consensus keyed by (aggregator, bus); single-bus aggregators are byte-identical to v4.0.
- [ ] **ACTOR-04**: A researcher can set partial compliance, opt-out and rebound as exogenous seeded scenario parameters and see their effect on welfare, prices and settlement.

### Scale at IEEE-8500 (SCALE)

- [ ] **SCALE-06**: The ~3.4 GiB of unattributed memory growth in IEEE-8500 runs is profiled and attributed, with the result documented.
- [ ] **SCALE-07**: A go/no-go decision for the headline run is recorded: GO only if attribution projects peak memory below ~10 GiB on the 15 GB host; otherwise "memory-infeasible on this host" is recorded with a lower-bounded requirement.
- [ ] **SCALE-08**: The IEEE-8500 headline point is run through `Scenario` (feeder selector widened additively) and reported as a measured table — size, build time, solve time, iterations, peak memory, exactness verdict — where "refused with certificate" counts as a measured outcome.

## Future Requirements

Deferred; tracked but not in this roadmap.

- **ACTOR-F1**: Tariff-menu (strategic) aggregator choosing its tariff by outer enumeration, labelled a lower bound.
- **ACTOR-F2**: Portfolio-coupled aggregator subproblem (shared constraints across a portfolio's buses).
- **ACTOR-F3**: Endogenous participation equilibrium (outer fixed point on opt-out).
- **SETL-F1**: Aggregate-flexibility polytope bids; equity compensation mechanisms.
- **DEV-F1**: Volt-VAR droop as an outer fixed-point control loop.
- **PAR-F1**: Parallel / hour-split DSO network solve (only if 8500 attribution supports it).

## Out of Scope

| Feature | Reason |
|---------|--------|
| TSO network model / T&D coupling | Separate future milestone (see the 6-node T&D case study) |
| OLTC, switched capacitors, unbalanced 3-phase, systematic back-feed exactness study | DSO physics deferred to a later milestone |
| Strategic / bilevel aggregator at population scale, EPEC market power | Nonconvex; breaks duals-as-prices; KKT-MILP only on small fixtures |
| Binary EV / compressor on-off logic | Project rule: convex device models, no binaries |
| P2P trading, RL-based aggregators | Different research question |
| Income-based equity | No income data; proxy groups only |
| Raising τ / hybrid floor or re-pinning goldens to make a run pass | Violates the project's honesty and golden policies |
| Bigger-RAM machine for 8500 | Outside the repo's scope; memory-infeasible is an acceptable outcome |

## Traceability

Filled by the roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|

**Coverage:**
- v5.0 requirements: 34 total
- Mapped to phases: 0 (pending roadmap)

---
*Requirements defined: 2026-10-09*
