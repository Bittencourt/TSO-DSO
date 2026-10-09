# Project Research Summary

**Project:** TSODSO — milestone v5.0 Aggregator Layer at Scale (Julia/JuMP research framework, DSO⇄aggregator operational layer)
**Domain:** Transactive-energy / DLMP-based DSO–aggregator coordination, convex SOCP branch flow + ADMM, research bench
**Researched:** 2026-10-09
**Confidence:** MEDIUM (integration points HIGH; threading behaviour, 8500 memory, settlement/equity design and literature citations MEDIUM-LOW)

## Executive Summary

v5.0 extends a validated, bit-reproducible convex framework, so almost everything is *modeling* work on the existing JuMP + Clarabel + HiGHS stack (new objective types, devices, a settlement layer, a population builder). The only recommended new runtime dependency is OhMyThreads.jl. The binding constraints are not package choices but: (1) the default path must stay byte-identical (knife-edge canary `iters = 56`, `welfare = -4823.66604824162`, never re-pinned); (2) the host (4 cores / 15 GB RAM) already hits a memory wall at IEEE-8500; and (3) the project's honesty discipline (report-not-throw, never loosen the exactness gate, sign-safe goldens).

The recommended approach is additive everywhere: a compute/commit split of the AGR sweep behind an `AbstractAgrExecutor` (serial default = verbatim old loop; threaded path commits serially in index order → bit-identical), the ADMM coupling axis generalised from "bus" to "slot" (slot = bus by default), aggregator-as-actor as an *objective type* (`WelfareObjective` / `ProfitObjective`), not a new strategy, a new pure post-processing settlement/equity layer over a JuMP-free `DispatchRecord`, and new devices (EV, heat pump, smart-inverter capability cone) kept convex and binary-free. FEATURES and PITFALLS agree on one modeling point: a "profit-maximizing aggregator" in a convex price-taking world collapses to the welfare optimum unless there is a *wedge* (margin, uniform retail tariff, compliance < 100%). The feature must be built as "aggregator with a wedge", with the zero-wedge case as its liveness test.

Key risks, in priority order: (1) the IEEE-8500 headline may be infeasible on this host, and the gate already refuses the d=0.1 T=10 point (ratio 569), so the deliverable must be defined as a measurement that may honestly end "memory-infeasible" or "refused with certificate"; (2) thread-safety/determinism of parallel solves — Clarabel instance-level thread-safety is undocumented and needs a spike; (3) tuning pressure toward the thesis +25% (current ≈ +0.26%, App. E IP-blocked); (4) double counting in tariff accounting; (5) relaxation inexactness from V2G and Volt-VAR. Mitigations are structural: spike-gated parallel work, a conservation-tested ledger, a pre-registered Case A protocol, overlap/exactness certificates for new devices.

## Key Findings

### Recommended Stack (STACK.md)

The v1–v4 stack is unchanged. Additions only:

- **OhMyThreads.jl 0.8.7** — the one new runtime dependency: structured task parallelism, `TaskLocalValue`, index-addressed `tmap!`, Julia 1.10 compatible. (MEDIUM — plain `Threads` + preallocated vectors also works.)
- **Threads, not Distributed** — one copy of feeder/model memory; JuMP/Clarabel state is not transferable. Distributed only as DrWatson separate-process sweeps, never in `src/`.
- **Memory levers (no new dependencies):** `set_string_names_on_creation(false)`, GC hygiene, `--heap-size-hint`, staged `Profile.Allocs`/`maxrss` checkpoints, a pool of k reusable per-hour DSO solver instances (highest leverage, but only after the per-hour-state hypothesis is verified).
- **Hand-rolled in `src/` (~60–100 lines each):** equity metrics (Gini/Theil/Atkinson/Palma; reject stale `Inequality.jl` 0.0.4), seeded EV/heat-pump samplers on `StableRNG` (no `Distributions.jl`), settlement functions, piecewise-linear lookup.
- **Offline data toolchain:** Parquet2/Arrow in a separate `scripts/data_prep` environment, never in `[deps]`; vendored CSVs with license stamps (ACN-Data, When2Heat, NREL TEMPO — licenses unchecked).
- **Version floors:** keep JuMP 1.30.1 / HiGHS 1.24.1 (registry has 1.32.1 / 1.26.0); do not bump without re-verifying the canary (prior resolver-mismatch flake).

### Expected Features (FEATURES.md)

**Must have (table stakes):**
- Parallel per-aggregator ADMM with a strong-scaling report.
- True 784-house Case A population.
- Measured IEEE-8500 run: size, build time, solve time, peak memory, iterations, exactness verdict — a refusal counts as measured.
- Case A re-attempt: absolute + relative delta, seed spread, ablation.
- Aggregator with a retail-tariff wedge: pass-through test (`π = λ + m` equals welfare optimum), efficiency-loss quantification, partial compliance and rebound metric, multi-node portfolios with real coupling.
- `TariffScheme` (FIT / TOU / flat / nodal DADP), per-actor ledger with conservation identities, revenue-neutral flat/TOU derived from the DADP run, network feasibility settled on AC physics, equity metrics with proxy groups only (never income), prosumer vs non-prosumer comparison.
- EV (V1G, then V2G with strictly positive degradation cost), heat pump (2R2C, exogenous COP(T_out)), smart-inverter capability cone with exactness re-measurement.
- DSO flexibility market vs price coordination — needs an explicit baseline and payment rule or the comparison is vacuous; cross-scheme comparison table.

**Should have (differentiators):** exactness-aware settlement (refuses/tags inexact schemes); reactive remuneration at the certified reactive DLMP; welfare decomposition of the aggregator wedge; tariff-menu aggregator by outer enumeration (labelled a lower bound); documented per-subproblem memory model.

**Defer:** aggregate-flexibility polytope bids; equity compensation mechanisms; post-hoc droop simulation; strategic/bilevel aggregator at population scale; EPEC market power; binary EV/compressor logic; P2P trading; RL aggregators.

### Architecture Approach (ARCHITECTURE.md)

Strictly additive over the existing include graph; the default path executes the same statements in the same order (default method bodies are never edited — new types/methods are added and dispatched on).

**Major components:**
1. **`AbstractAgrExecutor`** (Serial default / Threaded / threaded build): pure `_agr_compute` + serial `_agr_commit!`, removing the data race on `st.a` / `st.util` / `ls.b` dicts. `executor` excluded from `==`/`hash`/filename identity. Per-task exceptions wrapped; the lowest-index failure rethrown so `CertificateError` still matches by type.
2. **`CouplingSlot` table:** ADMM consensus keyed by (actor, bus) instead of bus; 1:1 case slot = bus → byte-identical. Multi-node portfolios grouping-only first; coupled `PortfolioAgrOpt` deferred.
3. **`AbstractActorObjective`:** `WelfareObjective` returns the same `===` object; `ProfitObjective(retail_tariff)`. `welfare` stays social welfare from device utilities; actor profit is a separate reported quantity.
4. **`Population` / `Actor` / `HouseRef`:** new `:thesis_caseA` selector; per-house `sub_seed` hashing on `(master, :house, bus, h)` (never `seed + bus`); `device_p_inject` stash for house-level equity.
5. **`src/settlement/`:** `DispatchRecord`, tariffs, `settle`, `equity`, `run_with_record`; outside `welfare_accounting`; fixed-dispatch networks evaluated with `ACPowerFlow(limits=false)` returning a status (no throw).
6. **Devices** behind a `has_reactive_decision` trait (trait refactor first, no behaviour change); **`AbstractCoordination`** (`PriceBased`, `FlexMarket`) producing the same `DispatchRecord`.

### Critical Pitfalls (PITFALLS.md)

1. **Shared state / nondeterministic reduction (C1–C3)** — one model per task, index-addressed slots, serial reduction in `load_nodes` order, `BLAS.set_num_threads(1)`, Clarabel threads = 1, serial vs threaded tested with `==` (not `≈`), canary never re-pinned.
2. **Memory multiplication at 8500 and gate-loosening pressure (C4, C5)** — attribute the ~3.4 GiB unattributed growth before adding concurrency; cap DSO-hour concurrency separately from AGR concurrency; "refused with certificate" is a valid measured result; never raise τ or the hybrid floor.
3. **ADMM convergence collapse with heterogeneous agents (C6)** — per-agent/per-class residual scaling (adaptive-ρ normalisation `p_p = length(load_nodes)*T` must count slots); validate each device class against the centralized solve (feasible at 784 houses, not at 8500); add device classes one at a time.
4. **Profit-max turning bilevel/bilinear; behavioural nonconvexity (C7, C8)** — fix the formulation before coding: price-taker with fixed-margin wedge (convex) as default; zero-margin must equal social welfare; behaviour as an exogenous scenario axis in v5.0.
5. **Double counting, misread equity, tuning toward +25% (C13, C12, C14)** — one conserved ledger with explicit merchandising-surplus line and sum-to-zero test; household-weighted, sign-safe metrics; pre-registered Case A protocol, full sweep reported; goldens only on sign-safe quantities.
6. **Also:** V2G overlap and Volt-VAR droop nonconvexity (C9, C11) need certificates and a negative-price fixture; EV with `is_flexible_load=true` silently flips ADMM to `ReactiveMode.LIVE` — decide the trait knowingly.

## Implications for Roadmap

### Build-order disagreements and reconciliation

| Source | Implied order |
|---|---|
| FEATURES | Settlement-first: ledger/tariffs → parallel ADMM + 784 population + Case A → aggregator → devices → inverter → equity/flex market → 8500 last |
| ARCHITECTURE | Parallel-first: parallel-ready ADMM → population → settlement ∥ devices → actors → 8500 → flex market → Case A last |
| PITFALLS | Parallel kernel + serial-equivalence tests first; ledger defined early (∥ actors); devices one class at a time, Volt-VAR last; Case A last; 8500 last |
| STACK | Clarabel thread-safety spike gates all parallel work; profiling first; go/no-go before any 8500 promise |

1. **Settlement-first vs parallel-first.** Reconciled: **parallel-first with a thin Phase 1** (zero-behaviour-change refactor + spikes + additive result keys `pag`, `util`, `p_import`, per-slot `λ` that settlement needs). The ledger and its conservation test then lead Phase 3 and feed every later comparison; FEATURES' dependency (ledger before actors/equity/flex) is preserved.
2. **Where 8500 sits.** Reconciled: **split** — memory attribution (measurement only) in Phase 1; the headline run as the last phase, behind a go/no-go.
3. **Case A timing.** Reconciled: right after Phase 3 (dependencies are only population + ledger); tuning risk handled by the pre-registered protocol written in Phase 2.
4. **DSO parallelism.** Reconciled: DSO solve serial by default; hour concurrency / `HourSplitDsoOpt` is an experiment gated on the memory attribution.
5. **`direct_model` for Clarabel.** STACK recommends it; ARCHITECTURE notes Clarabel is copy_to-only per `factory.jl`. **Unresolved** — small Phase 1 experiment before any plan relies on it.
6. **Opt-out modeling.** Reconciled: exogenous seeded compliance/opt-out fractions first; outer participation fixed point a late optional extension labelled "a participation equilibrium".
7. **Parallel library.** Adopt OhMyThreads (`tmap!` into index-addressed output) once the spike passes; the compute/commit design is library-independent.

### Suggested phases

1. **Parallel-Ready ADMM and Gating Measurements** — compute/commit split, executors (Serial default, Threaded, threaded build), per-task exception unwrapping, additive result keys, `Scenario` feeder tuple widened to `:ieee8500(_mv)`, `executor` on `ADMM` excluded from identity, threads/BLAS counts in provenance. Spikes: (a) concurrent Clarabel under `-t 4` bitwise vs serial (gates all parallel work); (b) `direct_model` feasibility; (c) AGR speedup at 784-house scale with `nchunks` batching; (d) attribution of the ~3.4 GiB 8500 growth. Avoids C1–C3, M1; canary first, serial==threaded with `==`.
2. **Population and Houses (784-house Case A)** — `Population`/`HouseRef`, `:thesis_caseA`, per-house `sub_seed`, `device_p_inject` stash, `granularity` (node vs per-house slots), non-PV household group, scaling report (wall time vs threads, iterations vs N), composition table (5 MWp PV, 6.5 MW elastic, 1.5 MW inelastic), pre-registered Case A protocol. Avoids C6, M6.
3. **Settlement, Ledger and Equity** — conservation test first (Σ actors = Δwelfare incl. merchandising-surplus line), `DispatchRecord`, `TariffScheme` (FIT via `fit_baseline`, revenue-neutral flat/TOU from DADP, nodal, DADP), `settle`, `run_with_record`, AC-physics feasibility status (no throw), rebound metric, hand-rolled sign-safe equity metrics with known-value tests, prosumer vs non-prosumer. Check ρ→0 re-dispatch well-posedness. Avoids C12, C13.
4. **Case A Magnitude Re-attempt** — absolute/relative delta with seed spread, ablation (FIT parameters, price range, population, device mix), sign-safe goldens only, +25% as `@info`/`@test_broken`, comparison with the 1-house-per-bus proxy (+0.26%). Avoids C14.
5. **Devices (EV, Heat Pump, Smart-Inverter Cone)** — can run concurrently with 3–4; one class at a time, each re-validated against centralized. `has_reactive_decision` trait refactor first (resolved `ReactiveMode` identical on existing fixtures); EV V1G → V2G with degradation cost + overlap certificate, window masks, soft departure target, terminal-SOC rule, overnight and negative-price fixtures; HeatPump 2R2C, exogenous COP, exact discretisation, periodic temperature; SmartInverterPV capability cone riding FourQuadBESS reactive consensus, exactness re-measured in the high-PV regime. Volt-VAR droop as a hard constraint is an anti-feature. Avoids C9–C11, M2, m4, m5.
6. **Aggregator as Actor** — slot table and multi-actor per bus, grouping-only portfolios, `ProfitObjective` (wedge/retail tariff), pass-through and zero-margin liveness tests, efficiency-loss quantification, behavioural wrappers (`PartialCompliance`, `OptOut`, rebound), weighted centralized cross-check; `PortfolioAgrOpt` only if research demands. No `ProfitADMM` strategy, no multi-bus `Aggregator`. Avoids C7, C8, M3, M4.
7. **Flexibility Market vs Price-Based Coordination** — `AbstractCoordination`, `FlexMarket` as a redispatch SOCP on the `close_balance!` seam, explicit baseline and payment rule (uniform vs pay-as-bid), comparison table FIT/TOU/flat/DADP/flex market. Avoids M5, C13.
8. **IEEE-8500 Headline Measurement (go/no-go gated)** — measured table (size, build, solve, iterations, peak RSS, exactness verdict) through the per-point wrapper; solver-state pool / `HourSplitDsoOpt` only if attribution supports. Avoids C4, C5, M1.

### Go/no-go checkpoint for the 8500 headline run

Decision point: end of Phase 2 (after Phase 1 attribution and Phase 2 scaling numbers), re-confirmed on entry to Phase 8. Thresholds are a proposal needing the user's confirmation.

- **GO only if** attribution shows a lever (names off + GC hygiene + verified bounded per-hour solver-state pool, DSO-hour concurrency = 1) projecting peak VmRSS < ~10 GiB for ADMM-only d=0.1 T=24 (earlyoom killed at ~10.4 GiB; last completed point peaked at 11.52 GiB).
- **NO-GO is an honest end state:** record "memory-infeasible on this 15 GB host" with a lower-bounded requirement; never tune tolerances, raise τ, or loosen the hybrid floor. A bigger-RAM machine is out of the repo's scope.
- **The deliverable is satisfiable either way:** "measured" explicitly includes "refused with certificate" (d=0.1 T=10 converged in 8 iterations, refused at ratio 569). Requirements must say so; the roadmap must not promise convergence at a headline point.
- If the Phase 1 Clarabel spike fails, parallelism drops to AGR build only (or is deferred) and the go/no-go uses serial numbers.

### Phase ordering rationale

- Dependencies: P1 → record keys + executor; P2 → population; P3 → ledger; P4 needs P2+P3; P5 independent; P6 needs P3; P7 needs P3 (benefits from P6); P8 needs P1 + P2 scaling numbers.
- Grouping follows architecture seams (executor/slot/objective in `admm/`; population; isolated `settlement/`; devices behind a trait).
- Determinism and conservation tests precede the features that depend on them; the noisiest risk (8500) goes last behind an explicit checkpoint.
- P5 may run concurrently with P3–P4; the only shared touch is the `has_reactive_decision` trait — do that refactor in P1 or at the start of P5.

### Research flags

Needs deeper research at plan time: Phase 1 (Clarabel thread-safety/determinism, `direct_model`, HiGHS concurrency, 8500 attribution — spikes), Phase 2 (Case A population reconstruction without App. E, per-house vs per-node granularity, EV data sourcing/licenses), Phase 5 Volt-VAR only (droop vs capability cone — decide with the thesis owner), Phase 6 (profit-objective economics, equilibrium interpretation, weighted centralized cross-check), Phase 7 (baseline, payment rule, bid curves), Phase 8 (attribution results, pool design).

Standard patterns: Phase 3 (verify metric definitions), Phase 4, Phase 5 EV V1G / heat pump 2R2C (V2G needs the overlap certificate, no new research).

## Confidence Assessment

| Area | Confidence | Notes |
|---|---|---|
| Stack | MEDIUM-HIGH | Registry versions verified 2026-10-09; threads-over-Distributed HIGH; Clarabel thread-safety LOW-MEDIUM and HiGHS concurrency LOW (spike-gated); `:faer` unmeasured; data licenses unchecked |
| Features | MEDIUM | Project theory + field consensus; no live web verification; several citations LOW |
| Architecture | HIGH (integration points) / MEDIUM (forward designs) | Read from code with file:line refs; no Julia run, test files not read |
| Pitfalls | MEDIUM | Project history HIGH; threading/relaxation established practice; accounting/equity MEDIUM-LOW |

**Overall: MEDIUM.** Direction and architecture are consistent across all four documents; the main uncertainty is empirical (threading and memory on this host), which the Phase 1 spikes and the go/no-go are designed to resolve.

### Gaps to address (open questions carried forward)

- Clarabel thread-safety/determinism under `-t 4` (Phase 1 spike; gates all parallel work).
- AGR speedup at 784 houses — small QPs may be overhead-bound; batch with `nchunks` and measure.
- Attribution of the ~3.4 GiB unattributed growth (per-hour DSO state hypothesis) before any pool / `HourSplitDsoOpt` design.
- `direct_model` for Clarabel (STACK vs ARCHITECTURE disagree) — resolve in Phase 1.
- Volt-VAR formulation: all four agree on optimal-Q capability cone first, droop as fixed-point comparator — confirm with the thesis owner.
- Data licenses (ACN-Data terms, When2Heat CC-BY); document the European vs San Juan climate mismatch.
- Per-house slot granularity: effect on iteration counts and adaptive-ρ residual normalisation.
- Profit-objective economics and the right centralized cross-check.
- How `assert_battery_complementarity!` identifies batteries (before V2G).
- Tariff re-dispatch with ρ→0 for non-strictly-concave devices (PVBattery, Deferrable).
- Tests that may assert `_admm_certify` NamedTuple key sets, legacy guard error messages, `test_exports.jl` / `docs/src/api.md` lists — grep before editing; add keys at the end only.
- EV and `is_flexible_load`: decide knowingly whether EV populations resolve to `ReactiveMode.LIVE`.
- Thesis Case A node-level house counts / App. E parameters remain IP-blocked — state calibration provenance; +25% may be unreproducible by construction.
- Equity scope: no income data → proxy groups, said explicitly.
- Go/no-go thresholds (~10 GiB projected VmRSS) need confirmation.
- Deferred v4.0 debts touching this milestone's tests: `fit_baseline` ALMOST_OPTIMAL on Julia 1.12.7; `sub_seed` cross-version hash stability; the 2 known Aqua failures.

## Sources

**Primary (HIGH):** in-repo code (`src/admm/*`, `src/devices/*`, `src/experiments/*`, `src/pricing/*`, `src/solver/factory.jl`, canary test header, STATE.md 8500 findings); `.planning/PROJECT.md`; repo memory notes; Julia General registry `Versions.toml`/`Compat.toml` (2026-10-09); JuMP parallelism tutorial (https://jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism/).

**Secondary (MEDIUM):** Clarabel settings and paper (https://clarabel.org/stable/api_settings/, https://arxiv.org/pdf/2405.12762); Julia Discourse on JuMP multithreading overhead; ACN-Data, NREL TEMPO/dsgrid, When2Heat (existence verified, licenses unchecked); literature from training knowledge (Boyd et al. 2011; Farivar & Low 2013; Gan et al. 2015; Papavasiliou 2018; Huang et al. 2015; Li, Wu & Oren 2014; Sortomme & El-Sharkawi 2012; Bacher & Madsen 2011; Burger et al. 2017/2020; Borenstein 2012).

**Tertiary (LOW, validate):** FEATURES.md LOW citations (Gottwalt 2011, Schittekatte 2018, Brown & Sappington 2017, Ziras 2021, IEEE 1547-2018 curve numbers); HiGHS concurrent-instance behaviour; Clarabel `:faer` memory/dual effects; equity and tariff-accounting design judgments.

---
*Research completed: 2026-10-09 — ready for requirements and roadmap*
