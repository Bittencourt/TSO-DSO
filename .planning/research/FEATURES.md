# Feature Landscape: v5.0 Aggregator Layer at Scale

**Domain:** Transactive energy / DLMP-based DSO-aggregator coordination (research bench, convex, no binaries)
**Researched:** 2026-10-09
**Mode:** Ecosystem (features). Sources: project theory files (`PROJECT.md`, `THEORY-thesis.md`) + domain knowledge of the 2013-2025 literature.

**Confidence caveat (read first):** No live web verification was run in this session. Every citation below is from training knowledge and is marked MEDIUM (well-known, author/venue/year confident) or LOW (topic confident, exact bibliographic detail should be checked before it goes into a thesis bibliography). Treat "what a reviewer expects" statements as MEDIUM: they are field consensus, not quotes. Verify citations with a quick search at phase-planning time.

---

## Framing insights that shape every feature below

1. **First welfare theorem is the baseline.** A price-taking aggregator maximizing `U - lambda_j * p` (what AGR-OPT already is) reproduces the social optimum when `lambda_j` is the DLMP. "Profit-maximizing aggregator" only differs from welfare maximization when there is a **wedge** between the DSO nodal price and what customers pay or respond to (margin, uniform retail tariff, fee, compliance < 100%, or market power). The feature is therefore "aggregator with a wedge", not "aggregator with a different objective function". Without a wedge the result is a null result (identical to welfare max) and reviewers will say so. This is the central design decision for the aggregator-as-actor work.
2. **In a convex, lossless-information world a flexibility market equals a priced dual.** Quantity-based redispatch with divisible bids and uniform activation prices has the same duals as DLMP. Real differences come from baselines, payment rule (pay-as-bid vs uniform), bid format, and information, so the comparison must model at least one of those or it is vacuous.
3. **Flat vs nodal comparisons must be revenue-neutral.** Otherwise the "result" is just a different total revenue. Flat/TOU prices should be derived from the same DADP run (energy-weighted averages) so the DSO's revenue adequacy is held fixed and the difference is purely allocation + behaviour.
4. **Rebound, comfort, and compliance largely emerge from existing physics.** Thermostatic bounds, SOC dynamics, and deferrable energy windows already create payback. The new work is mostly *measuring* and *parameterizing* them (a responsiveness fraction, a comfort band, a rebound-peak metric), not new optimization structure.
5. **The new devices are variations on existing primitives:** EV = battery/deferrable with an availability window; heat pump = 2-state thermostatic with COP; Volt-VAR = the existing `FourQuadBESS` apparent-power-cone pattern attached to PV. This keeps convexity and limits new code.

---

## Table Stakes

Features a reviewer of a "transactive energy at scale with aggregator actors" paper expects. Missing = the claim is not credible.

### A. Scale and population

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| Parallel per-aggregator (and per-house) ADMM subproblem solves | ADMM's selling point (Boyd et al. 2011; Kraning et al. 2014; Peng & Low 2014 for radial OPF) is parallelism; a paper claiming scale must report speedup | Med | Existing `_admm_iterate!`/`AgrOpt` build-once models. Separate JuMP models per task are thread-safe; shared model is not. DSO-OPT is also separable per hour (no inter-temporal network coupling), so parallelize across hours too. Check Clarabel thread behaviour (BLAS/threads oversubscription). Results must be bit-comparable to serial within tolerance |
| Strong-scaling report: wall time vs threads, iterations vs N aggregators/houses, per-subproblem time, memory | Standard in distributed-OPF papers; ADMM iteration count vs problem size is a known sensitivity (rho tuning) | Low-Med | Reuse Phase 35 harness (per-point wrapper, memory profiler) |
| True 784-house Case A population (houses per node, device mix, PV, seeded Markov data) | Thesis claim is about this population; the 1-house-per-bus proxy is a known caveat | Med-High | Needs thesis houses-per-node table (App. D appliance data; node-level counts may be missing since App. E is IP-blocked per memory). Seeded generation exists. Document composition table (houses, devices, MWp) matching 5 MWp PV, 6.5 MW elastic, 1.5 MW inelastic |
| IEEE-8500 headline measurement: size, build time, solve time, peak memory, iterations, exactness verdict | A "measured at scale" claim needs these six numbers | Med | Phase 35 already characterized: ADMM converges 8 iterations at d=0.1 T=10, gate refuses (ratio 569), memory wall between d=0.1 and 0.25 at T=24. An honest refusal or OOM with numbers is publishable; do not tune tolerances to pass |
| Case A welfare-gain re-attempt reported as absolute and relative, with seed spread | A ratio on a small/negative base is unstable (thesis base is $1457 social, DSO surplus -$2829 under FIT). Reviewers expect absolute delta, % delta, and a CI over seeds | Low-Med | Existing welfare/surplus accounting, FIT baseline, `run_sweep`. Pin sign-flip result (already reproduced); report magnitude honestly (current directional result ~+0.26%) |
| Sensitivity/ablation of what moves the Case A ratio (FIT parameters, lambda range, S_max, device mix, PV scale) | Explains a failed magnitude reproduction instead of just stating it | Med | Sweep harness exists. Attribute the gap: FIT assumption vs population vs price range |

### B. Aggregator as actor

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| Aggregator that buys at DSO nodal price and sells at a **retail tariff** (wedge = margin/uniform tariff), with profit = revenue - purchase - customer compensation | The standard retailer/aggregator business-model formulation (Carrion, Conejo, Arroyo 2007; Zugno et al. 2013; Burger et al. 2017 review) | Med | Needs a `RetailTariff` abstraction (fixed, TOU, pass-through + adder, uniform-across-nodes). Customer side = existing AGR-OPT with a given price |
| Pass-through benchmark: `pi = lambda_j + m` recovers welfare optimum for any fixed adder `m` (energy-independent) | The sanity result every reviewer asks for; also a unit test | Low | Test: pass-through result == centralized welfare result |
| Efficiency-loss quantification of a margin/volumetric wedge vs welfare optimum | The point of comparing "profit-max vs social welfare" | Low-Med | Welfare accounting; Ramsey-style deadweight loss measured as welfare difference |
| Direct-load-control aggregator (aggregator dispatches devices, customers paid a rebate/individual-rationality constraint `bill + discomfort <= default bill`) | The other dominant aggregator model in the literature (Mohsenian-Rad et al. 2010 style DSM; Iria et al.; Carreiro et al. 2017 survey) | Med | Convex LP/QP: maximize aggregator profit subject to per-customer IR constraints. Customer IR constraints are linear in decision variables |
| Multi-node aggregator portfolio (aggregator owns houses at several nodes) with **portfolio-level coupling** | Pure relabeling is trivial for separable utilities; reviewers expect the coupling that makes it matter (uniform retail tariff across nodes, shared fleet constraints, portfolio import cap) | Med | ADMM: one subproblem per aggregator with vector of nodal residuals; dual update stays per node. Changes the `node -> aggregator` map from bijection to many-to-one. Existing `Aggregator` roll-up |
| Partial compliance parameter: fraction `theta` of houses/devices responsive, rest follow a default (inelastic or FIT) schedule | Universal behavioural-response knob (e.g. DR participation rates in every DR paper) | Low | Existing device sets; mark device subsets as fixed-profile parameters. Convex trivially |
| Comfort limits / opt-out via per-customer individual rationality (participation iff surplus >= default) | Opt-out is the standard second behavioural ingredient | Med | Opt-out is discrete; implement as an **outer fixed-point iteration** (drop customers with negative surplus, re-solve), not binaries. Report whether the iteration converges and that the result is "a participation equilibrium" (mirror the existing "a converged equilibrium" honesty language) |
| Rebound/payback metric: post-event peak vs baseline peak, and snapback ratio under flat/TOU vs DADP | Reviewers expect to see the new-peak (herding/avalanche) effect of uniform price signals (Gottwalt et al. 2011, LOW) and that network-aware prices mitigate it | Low-Med | Metric on existing solved profiles; no new optimization. The expected result: TOU creates a rebound peak, DLMP with congestion term suppresses it |

### C. Settlement and equity

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| `TariffScheme` abstraction: FIT, TOU, flat, nodal DADP, each giving a per-node-per-hour price series | Required to compare schemes on the same population | Med | Existing FIT baseline (`fit_baseline`) is one instance. Customer response to an exogenous price = AGR-OPT solved with fixed price (no ADMM) |
| Per-actor bill/surplus ledger: prosumer, aggregator, DSO, per node and per house | Core deliverable; "per-actor bills" in milestone goal | Med | Existing welfare/surplus accounting (DSO + prosumers); extend with aggregator and per-house granularity |
| Accounting identities as tests: sum of actor surpluses == social welfare; DSO revenue reconciliation `sum_j lambda_j p_j - lambda_0 p_0` equals loss + congestion + voltage rent from the DLMP decomposition | Reviewers in the DLMP literature expect merchandising surplus to be explained (Papavasiliou 2018; Huang et al. 2015) | Low-Med | Uses existing 4-way DLMP decomposition. High-value, cheap |
| Revenue-neutral flat and TOU prices derived from the DADP run | See framing insight 3 | Low | Energy-weighted averages of lambda_j[t] over nodes (flat) and over time blocks (TOU) |
| Network-feasibility check of price-response under flat/TOU/FIT (violations, or DSO redispatch cost), settled on AC physics | The central message of the thesis: price-based schemes without network terms do not guarantee security | Med | Existing FIT settlement on AC physics with violations reported; generalize to any tariff. Uses `ACPowerFlow(limits=false)` per memory note (fixed-dispatch SOCP re-solves are structurally inexact) |
| Equity metrics across nodes and households: bill change vs flat counterfactual (distribution, quantiles), share of winners/losers, Gini or Atkinson index of net bills, max/min nodal price ratio, end-of-feeder vs head-of-feeder bill gap | Standard distributional toolkit (Borenstein 2012; Burger et al. 2020; Sotkiewicz & Vignolo 2006 on nodal distribution prices punishing remote nodes) | Med | No income data exists; use proxies (PV/battery ownership, consumption, electrical location) and say so explicitly. Do not claim income equity |
| Prosumer vs non-prosumer group comparison | The cross-subsidy debate (net metering/FIT) is exactly this split (Brown & Sappington 2017; Schittekatte et al. 2018, LOW) | Low-Med | Needs a non-PV household group in the population |

### D. Devices

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| EV, unidirectional (V1G): arrival/departure window, energy requirement by departure (hard, or soft via quadratic shortfall penalty), charger P_max, SOC bounds | EV smart charging is in every DSO-pricing paper (Clement-Nyns et al. 2010; Gan, Topcu, Low 2013; Li, Wu, Oren 2014 for EV DLMP) | Low-Med | A deferrable/battery device with an availability mask (`p = 0` outside window, `soc` pinned at arrival, `soc >= target` at departure). Soft shortfall penalty keeps feasibility and matches the quadratic-utility style |
| EV arrival/departure/energy sampling model (seeded) with documented source | Reviewers ask where the sessions come from | Low | Truncated-normal arrival (~evening) / departure (~morning), lognormal energy; cite ACN-Data (Lee, Li, Low 2019) or NHTS. Parameters here are LOW confidence, must be checked |
| V2G with charge/discharge efficiency and a discharge degradation cost | Standard V2G convex model (Sortomme & El-Sharkawi 2012) | Med | **Binary-free caveat:** with eta < 1 simultaneous charge/discharge can be "optimal" at zero/negative prices (energy burning); the repo already found this (App. C eta<1 overlap). Mitigation: strictly positive degradation cost + report a post-hoc complementarity check in the style of `assert_4q_complementarity!` |
| Heat pump with 2-state building thermal model (indoor air + envelope mass, 2R2C), electric power `p` -> heat `COP * p`, comfort band (hard or quadratic penalty) | Reviewers will not accept a 1-state model as "building thermal model"; 2R2C/3R2C is the standard grey-box (Bacher & Madsen 2011; Reynders et al. 2014; ISO 13790 5R1C as reference) | Med | Extends existing thermostatic device (3.2) to two coupled states. Linear dynamics, convex. COP fixed from outdoor-temperature forecast (parameter) so `Q = COP[t] * p` stays linear |
| Heat pump thermal-storage payback (pre-heating then coast) visible in results | The flexibility signature of an HP; shows rebound naturally | Low | Falls out of the model; include plot |
| Smart-inverter apparent-power cone on PV: `p_pv^2 + q^2 <= S_inv^2` with `q` dispatched (optimal Volt-VAR) | Convex, the standard optimization view of inverter VAR control (Farivar et al. 2011; Turitsyn et al. 2011) | Med | Same pattern as `FourQuadBESS` + `reactive_consensus` LIVE mode (thesis A3 "DER active-only" is lifted for this device). Interacts with reactive DLMP (`extract_reactive_dlmp`) |
| Demonstration that Volt-VAR changes the voltage-binding DADP and (importantly) the SOCP exactness gap in the high-PV reverse-flow regime | The project's headline v2.1 finding is SOCP inexactness under high-PV reverse flow; reviewers will ask if Volt-VAR cures it | Med | Uses `assert_ac_exact!`/`assert_socp_exact!`. Honest outcome either way |

### E. Flexibility market vs price-based

| Feature | Why Expected | Complexity | Dependencies / Notes |
|---------|--------------|------------|----------------------|
| DSO flexibility market: aggregators submit divisible up/down bids (convex marginal-cost blocks) against a baseline; DSO clears min-cost activation subject to the SOCP network constraints | The EU "local flexibility market" paradigm (Olivella-Rosell et al. 2018; Heinrich et al. 2020 EcoGrid 2.0 field trial) | Med-High | Two-stage: (1) aggregators optimize against a baseline tariff, (2) DSO redispatches to fix violations. Convex with divisible bids. Needs a baseline definition |
| Explicit baseline definition and its effect | Baseline gaming/inaccuracy is *the* known flaw of flexibility markets (Ziras et al. 2021, MEDIUM-LOW) | Med | Use the aggregator's stage-1 schedule as baseline; test inflated-baseline sensitivity |
| Uniform vs pay-as-bid activation payment | Without a payment-rule difference the comparison to DLMP is trivial (framing insight 2) | Low-Med | Settlement ledger |
| Comparison table: welfare, DSO cost, prosumer/aggregator surplus, violations, rebound peak, price volatility across {FIT, TOU, flat, DADP, flexibility market} | The headline result of the milestone | Med | Depends on `TariffScheme` + ledger |

---

## Differentiators

Not expected, but valued; chosen for fit with the existing framework's strengths (certificates, duals, honesty gates).

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Certified-exactness-aware settlement**: refuse to settle (or tag) any scheme whose SOCP is inexact | Few papers certify exactness before reporting prices; this is the repo's identity | Low | Reuse existing gate and status vocabulary |
| Tariff-menu aggregator by **outer enumeration** (grid/derivative-free search over a few TOU levels or the margin `m`, each point an inner convex equilibrium) | Gives Stackelberg-like "aggregator picks tariff" result without MPEC or binaries; tractable; honest "best of grid" label | Med | Inner = AGR-OPT with fixed price (cheap, parallel). Report as a lower bound on the leader's profit |
| Reactive-power remuneration of smart inverters at the certified reactive DLMP `mu_j` | Novel use of the existing reactive DLMP; closes the loop on settlement for Volt-VAR | Low-Med | Depends on `extract_reactive_dlmp` + `assert_no_slack` |
| Welfare decomposition of the aggregator wedge (margin deadweight loss, compliance loss, opt-out loss, network-blindness loss) | Clean attribution figure; strong thesis chapter | Med | Needs consistent counterfactual runs; sweep harness |
| Nodal-vs-flat equity with **compensation mechanism** (revenue recycling / locational hedge / price cap) and its welfare cost | Equity papers critique nodal pricing for remote-node penalty; showing a convex compensation fix is a contribution | Med | Compensation is a transfer, welfare-neutral by construction; check that behaviour is unchanged |
| Aggregate-flexibility representation per aggregator (feasible-set / polytope of nodal flexibility, e.g. outer box or Minkowski-sum approximation) for the flexibility market bids | Literature (Zhao et al. 2017 geometric aggregate TCL flexibility; Muller et al. 2019 zonotopes; Hao et al. 2015) uses this to submit bids without revealing devices | High | Defer unless flexibility market goes beyond marginal-cost blocks |
| Parallelism both across aggregators and across hours with a documented memory model (bytes per subproblem), extending the Phase 35 memory-wall work | Directly addresses the observed IEEE-8500 wall | Med | Build-once models cost memory; consider per-thread model pools and `direct_model` |
| Volt-VAR droop curve evaluated post-hoc on AC power flow (IEEE 1547-2018 style curve, Cat. B ~44% Q) as comparison against optimal Volt-VAR | Shows the gap between local rules and optimal dispatch (Zhu & Liu 2016; Farivar et al. 2013) | Med | Droop is a **fixed-point simulation**, not a convex constraint (piecewise-linear with deadband is not convex). Use as validation only; curve parameters are MEDIUM-LOW confidence |
| Heat pump + EV + PV joint household response with rebound/herding visualization | Strong narrative figure for DADP vs TOU | Low | Existing plotting (CairoMakie) |

---

## Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Strategic aggregator as a bilevel MPEC at population scale (aggregator picks retail tariff, customers respond) | Needs KKT + complementarity (binaries/SOS1) and does not scale; breaks "convex, no binaries" | Outer enumeration over tariff parameters (see Differentiators); if a certified small-case check is wanted, reuse `build_bilevel_kkt` (KKT-MILP with SOS1, planning layer) on a toy fixture only, labelled non-convex oracle |
| Aggregator market power / strategic bidding across multiple nodes (Cournot/EPEC) | Equilibrium problem with equilibrium constraints, non-unique, huge | Price-taking aggregator with an explicit wedge; mention strategic behaviour as future work |
| Binary EV charging (on/off, minimum charge power), heat-pump compressor cycling, min up/down times | Binaries; breaks the project constraint | Continuous charging with soft comfort/shortfall penalties; state the continuous-relaxation assumption in docs |
| COP as a decision-dependent function (COP depends on indoor/supply temperature variables) | Bilinear/nonconvex | COP from outdoor-temperature forecast (parameter) |
| Opt-out as binary decision variables inside the optimization | Binaries | Outer fixed-point iteration with participation equilibrium honesty language |
| Battery/EV degradation as nonconvex cycle counting (rainflow) | Nonconvex | Linear or quadratic throughput cost on discharge |
| Volt-VAR droop curve as a hard constraint in the SOCP | Piecewise-linear decreasing curve with deadband is not convex | Optimal Volt-VAR in the convex model; droop as post-hoc AC simulation |
| Claiming income-based equity | No income data in the project; would be fabricated | Proxy groups (PV ownership, load level, node location) and say so |
| Retuning tolerances to make IEEE-8500 or Case A "pass" | Violates the repo's honesty gates (per memory: never raise tau, measure comparison epsilons) | Report refusal/non-convergence with numbers |
| Peer-to-peer trading market, blockchain, reinforcement-learning aggregator | Out of scope; different literature | None |
| Network fixed-cost (sunk grid cost) recovery and tariff redesign | Large scope; energy-only per thesis | Note that DADP is energy charges only; flag as limitation |
| TSO coupling / unbalanced three-phase / OLTC | Explicitly out of milestone | Defer |

---

## Feature Dependencies

```
Existing: Device library, Aggregator roll-up, AgrOpt/DsoOpt ADMM, Scenario/run, fit_baseline,
          welfare/surplus accounting, DLMP decomposition, reactive DLMP, FourQuadBESS, exactness gates

Parallel ADMM ---------------------> IEEE-8500 headline measurement (needs memory model)
Parallel ADMM ---------------------> true 784-house Case A (house-level separability, speed)
True 784-house population ---------> Case A magnitude re-attempt, equity per-house metrics
Population with non-PV group ------> prosumer vs non-prosumer equity

TariffScheme abstraction ----------> per-actor ledger -----> equity metrics
                         \-----------> network-feasibility check under flat/TOU/FIT
                         \-----------> retail-tariff aggregator (wedge)
DADP run -> revenue-neutral flat/TOU prices -> scheme comparison

RetailTariff + wedge --------------> profit-maximizing aggregator ---> tariff-menu enumeration
Multi-node aggregator -------------> ADMM aggregator-subproblem refactor (many-to-one node map)
Partial compliance / opt-out ------> behavioural-response study ----> rebound metric

EV (availability-masked battery) --> V2G (needs complementarity check + degradation cost)
Heat pump 2R2C -------------------> rebound/payback study
Smart-inverter cone --------------> reactive_consensus LIVE (qag no longer pinned) -> reactive remuneration
                                 \-> exactness gap re-measurement (high-PV regime)

Flexibility market ---------------> baseline definition + TariffScheme ledger
All scheme comparisons -----------> ledger + exactness-aware settlement
```

Key coupling risks with existing code: (1) many-to-one aggregator/node map touches `Aggregator`, `AgrOpt`, and ADMM residual bookkeeping; (2) Volt-VAR relaxes thesis assumption A3 (active-only DER), so it must flow through the reactive consensus path, not bypass it; (3) the ledger must keep the byte-identical default path for existing goldens.

---

## Features that require binaries or bilevel structure (flagged) and convex alternatives

| Feature | Why it needs binaries/bilevel | Convex / tractable alternative |
|---------|------------------------------|--------------------------------|
| Strategic aggregator choosing retail tariff | Bilevel: follower KKT (SOS1) | Outer enumeration over tariff parameters; KKT-MILP only as small-case oracle |
| Aggregator market power in nodal markets | EPEC | Wedge-based price-taker |
| Opt-out decisions | Integer participation | Outer fixed-point participation iteration |
| EV on/off, min charge power; compressor cycling | Semicontinuous variables | Continuous with penalty |
| Simultaneous charge/discharge exclusion in V2G (eta < 1) | Complementarity | Positive degradation cost + post-hoc certificate |
| Droop-curve Volt-VAR as constraint | Nonconvex piecewise relation | Optimal Volt-VAR + post-hoc droop simulation |
| Flexibility market with indivisible bids | Binary acceptance | Divisible bids (uniform price clearing = dual) |

---

## MVP Recommendation (ordering for roadmap)

Prioritize (cheap, unblock everything, high reviewer value):
1. **TariffScheme + per-actor ledger + accounting identities + revenue-neutral flat/TOU** (Low-Med, enables C, B, E).
2. **Parallel ADMM + scaling report** (Med), then **true 784-house population** and the **Case A re-attempt with seed spread and ablation** (Med-High; data availability is the main risk).
3. **Retail-tariff aggregator (wedge, pass-through test) + partial compliance + rebound metric** (Med).
4. **EV (V1G then V2G) and heat pump 2R2C** (Low-Med, Med).
5. **Smart-inverter cone via reactive consensus + exactness re-measurement** (Med).
6. **Equity metrics + flexibility market comparison** (Med; depends on 1 and 3).
7. **IEEE-8500 measurement** last: depends on parallelism and is bounded by the known memory wall; deliver as honest measurement.

Defer: aggregate-flexibility polytope bids, tariff-menu enumeration beyond a small grid, compensation mechanisms, droop post-hoc simulation (differentiators once the table stakes land).

**Phases likely needing deeper research:** flexibility market design (baseline and payment rule choices), equity metric selection with proxy groups, EV session data sourcing, Case A population reconstruction (missing App. E/node-level house counts), threading behavior of Clarabel/JuMP at scale.

---

## Key citations (confidence in brackets)

- Boyd, Parikh, Chu, Peleato, Eckstein, "Distributed Optimization and Statistical Learning via ADMM," Found. Trends Mach. Learn., 2011 [MEDIUM-HIGH]
- Kraning, Chu, Lavaei, Boyd, "Dynamic Network Energy Management via Proximal Message Passing," Found. Trends Optim., 2014 [MEDIUM]
- Peng & Low, "Distributed Algorithm for Optimal Power Flow on a Radial Network," IEEE CDC 2014 / TSG [MEDIUM]
- Molzahn et al., "A Survey of Distributed Optimization and Control Algorithms for Electric Power Systems," IEEE TSG 2017 [MEDIUM]
- Farivar & Low, "Branch Flow Model: Relaxations and Convexification," IEEE TPWRS 2013; Gan, Li, Topcu, Low, "Exact Convex Relaxation of OPF in Radial Networks," IEEE TAC 2015 [HIGH]
- Papavasiliou, "Analysis of Distribution Locational Marginal Prices," IEEE TSG 2018 [MEDIUM-HIGH]
- Huang, Wu, Oren, Li, Liu, "Distribution Locational Marginal Pricing Through Quadratic Programming for Congestion Management," IEEE TPWRS 2015 [MEDIUM]
- Li, Wu, Oren, "Distribution Locational Marginal Pricing for Optimal EV Charging Management," IEEE TPWRS 2014 [MEDIUM-HIGH]
- Sotkiewicz & Vignolo, "Nodal Pricing for Distribution Networks," IEEE TPWRS 2006 [MEDIUM]
- Burger, Chaves-Avila, Batlle, Perez-Arriaga, "A Review of the Value of Aggregators in Electricity Systems," RSER 2017 [MEDIUM]
- Carrion, Conejo, Arroyo, "Forward Contracting and Selling Price Determination for a Retailer," IEEE TPWRS 2007 [MEDIUM]
- Zugno, Morales, Pinson, Madsen, "A Bilevel Model for Electricity Retailers' Participation in a Demand Response Market Environment," Energy Econ. 2013 [MEDIUM]
- Mohsenian-Rad, Wong, Jatskevich, Schober, Leon-Garcia, "Autonomous Demand-Side Management Based on Game-Theoretic Energy Consumption Scheduling," IEEE TSG 2010 [MEDIUM-HIGH]
- Carreiro, Jorge, Antunes, "Energy Management Systems Aggregators: A Literature Survey," RSER 2017 [LOW-MEDIUM]
- Kok & Widergren, "A Society of Devices: Integrating Intelligent Distributed Resources with Transactive Energy," IEEE Power Energy Mag. 2016 [MEDIUM]
- Borenstein, "The Redistributional Impact of Nonlinear Electricity Pricing," AEJ: Economic Policy 2012 [MEDIUM]
- Burger, Knittel, Perez-Arriaga, Schneider, vom Scheidt, "The Efficiency and Distributional Effects of Alternative Residential Electricity Rate Designs," Energy Journal 2020 [MEDIUM]
- Brown & Sappington, "Designing Compensation for Distributed Solar Generation: Is Net Metering Ever Optimal?" Energy Journal 2017 [LOW-MEDIUM]
- Schittekatte, Momber, Meeus, "Future-proof tariff design," Energy Policy 2018 [LOW]
- Gottwalt, Ketter, Block, Collins, Weinhardt, "Demand Side Management: A Simulation of Household Behavior under Variable Prices," Energy Policy 2011 [LOW]
- Clement-Nyns, Haesen, Driesen, "Impact of Charging PHEVs in a Residential Distribution Grid," IEEE TPWRS 2010 [MEDIUM]
- Gan, Topcu, Low, "Optimal Decentralized Protocol for Electric Vehicle Charging," IEEE TPWRS 2013 [MEDIUM-HIGH]
- Sortomme & El-Sharkawi, "Optimal Scheduling of Vehicle-to-Grid Energy and Ancillary Services," IEEE TSG 2012 [MEDIUM-HIGH]
- Lee, Li, Low, "ACN-Data: Analysis and Applications of an Open EV Charging Dataset," ACM e-Energy 2019 [MEDIUM]
- Bacher & Madsen, "Identifying Suitable Models for the Heat Dynamics of Buildings," Energy and Buildings 2011 [MEDIUM-HIGH]
- Reynders, Diriken, Saelens, "Quality of Grey-Box Models and Identified Parameters as Function of Data Information Content," Energy and Buildings 2014 [MEDIUM]
- Hao, Sanandaji, Poolla, Vincent, "Aggregate Flexibility of Thermostatically Controlled Loads," IEEE TPWRS 2015; Zhao, Zhang, Hao, Zhang, "A Geometric Approach to Aggregate Flexibility Modeling of TCLs," IEEE TPWRS 2017 [MEDIUM]
- Farivar, Clarke, Low, Chandy, "Inverter VAR Control for Distribution Systems with Renewables," IEEE SmartGridComm 2011; Turitsyn, Sulc, Backhaus, Chertkov, "Options for Control of Reactive Power by Distributed Photovoltaic Generators," Proc. IEEE 2011 [MEDIUM-HIGH]
- Zhu & Liu, "Fast Local Voltage Control Under Limited Reactive Power: Optimality and Stability Analysis," IEEE TPWRS 2016 [MEDIUM]
- IEEE Std 1547-2018 (Volt-VAR categories A/B; Cat. B ~44% Q) [MEDIUM; check exact curve numbers]
- Olivella-Rosell et al., "Local Flexibility Market Design for Aggregators Providing Multiple Flexibility Services at Distribution Network Level," Energies 2018 [MEDIUM]
- Heinrich, Ziras, Syrri, Bindner, "EcoGrid 2.0: A Large-Scale Field Trial of a Local Flexibility Market," Applied Energy 2020; Ziras, Heinrich, Bindner, "Why Baselines Are Not Suited for Local Flexibility Markets," RSER 2021 [MEDIUM-LOW]
- Palacios, Samper, Vargas, IET GTD 13(9) 2019 and PhD thesis UNSJ 2022 (project source) [HIGH, in repo]
- Project memory/history: Phase 35 IEEE-8500 results, v2.1 SOCP inexactness finding, App. C eta<1 overlap, hybrid exactness floor [HIGH, in repo]
