# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- 🚧 **v2.1 Validation & Reproduction** — Phases 15–18 (in progress, started 2026-07-25)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md) and
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md).

## Phases

- [ ] **Phase 15: AC-Exactness Oracle** - Certify the SOCP branch-flow relaxation against an independent nonconvex AC-OPF oracle, allowing a genuine inexactness to surface as a documented finding
- [ ] **Phase 16: Reactive-Power (μ) Consensus** - DSO-OPT enforces a genuine per-node reactive balance and yields a citable reactive nodal price, without regressing the active-only ADMM path
- [ ] **Phase 17: Real IEEE-123 Impedances** - Replace synthetic IEEE-123 impedances with real, positive-sequence values reduced from public OpenDSS data
- [ ] **Phase 18: Directional Thesis Reproduction** - Reproduce the sign and magnitude-band of the thesis welfare result on real data, framed as directional/public-data

## Phase Details

### Phase 15: AC-Exactness Oracle
**Goal**: A researcher can certify that the SOCP Convex Branch Flow relaxation matches true nonconvex
AC-OPF to a documented tolerance on radial fixtures — replacing today's toy-point + same-relaxation
self-check with an independent oracle — and a genuine relaxation gap (if one exists under high-PV
reverse flow) surfaces as a first-class, citable finding rather than a tuned-away test failure.
**Depends on**: Nothing (independent of Phases 16–18; builds on v1.0's `powerflow/` and `models/` seams)
**Requirements**: EXACT-01, EXACT-02, EXACT-03, EXACT-04
**Success Criteria** (what must be TRUE):
  1. Researcher can solve a true nonconvex AC-OPF via a new `ACPowerFlow <: AbstractPowerFlow` peer
     subtype (Ipopt, nonconvex SOC equality) at the *same* loads/PV operating point as an existing
     SOCP solve, dispatched through the existing `solve_welfare` entrypoint unchanged.
  2. `assert_ac_exact!` (peer to `assert_socp_exact!`) reports objective gap, max voltage deviation,
     and max branch-flow deviation using a scale-free `atol + rtol·magnitude` tolerance.
  3. The exactness check reports **per-hour/per-scenario** gaps in a table, never a single pass/fail
     boolean, so a genuine gap is investigated (reverse-flow/voltage-binding state) before any
     tolerance is touched.
  4. A high-PV/reverse-flow stress fixture exercises the exactness boundary, and the result — exact
     or genuinely inexact — is documented in a literate rung page beside the thesis equations.
**Plans**: 3 plans

Plans:
- [x] 15-01-PLAN.md — ACPowerFlow peer formulation + wiring + BLOCKING 2-bus angle-recovery gate (EXACT-01)
- [x] 15-02-PLAN.md — assert_ac_exact! per-hour report, report-don't-throw contract (EXACT-02, EXACT-03)
- [ ] 15-03-PLAN.md — high-PV stress fixture + literate rung page (EXACT-04)

### Phase 16: Reactive-Power (μ) Consensus
**Goal**: The ADMM operational layer carries a genuine reactive-power balance and a citable reactive
nodal price, closing the `AgrOpt.jl` placeholder, without regressing the already-shipped,
cross-validated active-only ADMM path.
**Depends on**: Nothing code-wise (touches only `src/admm/`, independent of Phase 15's `powerflow/`+
`models/` files); sequenced second because it is the most invasive change to an already-shipped path —
its goldens must be re-validated before Phases 17–18 build on top of it.
**Requirements**: REACT-01, REACT-02, REACT-03
**Success Criteria** (what must be TRUE):
  1. The `mu` naming collision (new reactive dual vs. the existing adaptive-ρ scalar `mu::Real=10.0`
     in `Scenario`'s golden-hash schema) is resolved — a distinct code identifier chosen and every
     existing `mu` usage grepped — *before* any `AgrOpt`/`DsoOpt` code changes land.
  2. With the new `reactive_consensus::Bool=false` kwarg at its default, the existing active-only
     ADMM path is byte-identical to pre-milestone behavior (pinned goldens pass unchanged).
  3. With `reactive_consensus=true`, DSO-OPT's per-node reactive-power balance is a genuine equality
     constraint (replacing the free reactive-import slack) in both the centralized and ADMM solves.
  4. A reactive nodal price (dual of the reactive balance) is extracted and appears as a documented,
     citable 5th component in the DLMP decomposition (`pricing/dlmp.jl`).
**Plans**: 4 plans

Plans:
- [ ] 16-01-PLAN.md — mu/mu naming-collision grep-audit (BLOCKING) + RED @testitem harness (test_admm_reactive.jl)
- [ ] 16-02-PLAN.md — qag_dso coupling variable + reactive_consensus kwarg + :balance_q assert_no_slack certificate
- [ ] 16-03-PLAN.md — extract_reactive_dlmp + decompose_dlmp reactive field + 2-bus reactive-price pin
- [ ] 16-04-PLAN.md — Clarabel flake-rate re-measurement (IEEE-13/123, N>=20) + rho/rho_q finding

### Phase 17: Real IEEE-123 Impedances
**Goal**: `ieee123.jl`'s topology is driven by real, standard, citable positive-sequence impedances
reduced from the public OpenDSS IEEE-123 dataset, and the case remains meaningful (voltage-binding)
for its intended purpose.
**Depends on**: Nothing code-wise (touches only `scripts/` + `src/data/`); its own *validation*
benefits from Phase 15's AC-exactness oracle and Phase 16's reactive pricing being available to
certify the real-data case, but does not require them to build.
**Requirements**: IMPED-01, IMPED-02, IMPED-03
**Success Criteria** (what must be TRUE):
  1. An offline, reproducible script parses the public OpenDSS IEEE-123 case
     (`IEEE123Master.dss` + `IEEELineCodes.DSS`) and reduces 3-phase line-code matrices to
     positive-sequence R1/X1 per segment via a documented Fortescue-averaging reduction, with PMD
     kept out of `Project.toml`'s runtime `[deps]` (weakdep + extension or throwaway env only).
  2. `ieee123.jl` consumes the committed real positive-sequence impedances as a pure-data `const`
     table in place of synthetic values (topology untouched), with reduction assumptions and
     caveats (transposition, single-phase laterals, regulators/caps/switches handling) documented.
  3. The real-impedance IEEE-123 case is verified to remain meaningful for its purpose
     (voltage-binding) — PV/aggregator population re-tuned and documented if required to restore it.
  4. Prior synthetic-fixture goldens are preserved as an independent parallel regression, or
     consciously re-pinned with an explicit before/after invariant-comparison rationale (voltage
     binding, exactness margin, iteration count).
**Plans**: 4 plans

Plans:
- [ ] 17-01-PLAN.md — vendor OpenDSS .dss fixtures + dependency-free regex parser + Fortescue reduction --verify self-check (IMPED-01)
- [ ] 17-02-PLAN.md — generate committed per-segment Ω const table + swap ieee123.jl ingestion + test_ieee123.jl spot-check (IMPED-02)
- [ ] 17-03-PLAN.md — numeric voltage-binding @testitem + ADMM behavioral-bound re-verification + population re-tune if needed (IMPED-03)
- [ ] 17-04-PLAN.md — literate reduction doc page + docs/make.jl registration (IMPED-01, IMPED-02)

### Phase 18: Directional Thesis Reproduction
**Goal**: A defensible, literate reproduction of the *direction and magnitude-band* of the thesis
welfare/surplus result on real, public data — explicitly framed as "directional, public-data,"
never an exact-figure claim.
**Depends on**: Phase 16 (reactive pricing needed for voltage/DLMP credibility) and Phase 17 (real
impedances) — strictly; the thesis's voltage-driven Case B result is not credible on synthetic
impedances or without priced reactive power. Optionally consumes Phase 15's AC-certification badge.
**Requirements**: REPRO-01, REPRO-02
**Success Criteria** (what must be TRUE):
  1. A literate rung/doc page (promoted from `scripts/thesis_caseA.jl`) plus a gate-then-golden test
     reproduces the sign and a pinned magnitude-band of the thesis welfare/surplus result on real
     IEEE-123 data with reactive pricing and real impedances both active — never a point value.
  2. Every citation of the reproduction number carries the fixed "directional, public-data"
     qualifier phrase.
  3. A consolidated assumptions/reduction doc page enumerates the full chain that produces the
     reported numbers (units resolution, reduction fidelity, component omissions, aggregator
     population, PV scenario).
  4. Repeated-run stability is checked and documented *before* the golden band is pinned, guarding
     against pinning transient Clarabel numerical noise as a permanent regression.
**Plans**: TBD

<details>
<summary>✅ v1.0 Operational Transactive-Energy Core (Phases 1–9) — SHIPPED 2026-07-20</summary>

- [x] Phase 1: Plumbing & Solver Abstraction (4/4 plans) — completed 2026-07-18
- [x] Phase 2: Linear Branch-Flow Residual Seam (4/4 plans) — completed 2026-07-18
- [x] Phase 3: Prosumer Device Library & Social-Welfare Solve (5/5 plans) — completed 2026-07-18
- [x] Phase 4: Convex Branch-Flow Correctness Milestone (6/6 plans) — completed 2026-07-19
- [x] Phase 5: Distribution Pricing — DADP & DLMP Decomposition (5/5 plans) — completed 2026-07-19
- [x] Phase 6: ADMM Decomposition Core (4/4 plans) — completed 2026-07-19
- [x] Phase 7: ADMM Convergence & Scale (6/6 plans) — completed 2026-07-19
- [x] Phase 8: Experiment Harness & Reproducibility (4/4 plans) — completed 2026-07-20
- [x] Phase 9: Documentation & Regression Acceptance Gate (5/5 plans) — completed 2026-07-20

Delivered: the full operational layer (rungs 0–5) — solver abstraction, residual-seam power-flow
(DC/LinDistFlow/SOCP Convex Branch Flow with validated exactness), prosumer device library +
GLB-CVX social welfare, DADP/DLMP dual-based pricing with 4-way decomposition, ADMM decomposition
validated against the centralized optimum (IEEE 13 + 123), a reproducible experiment harness, and
literate per-model docs + an end-to-end regression acceptance gate. 1946 tests pass.

</details>

<details>
<summary>✅ v2.0 Stackelberg-Nash TSO–DSO Planning Game (Phases 10–14) — SHIPPED 2026-07-24</summary>

- [x] Phase 10: Oracle Coupling Wiring & Resilience (2/2 plans) — completed 2026-07-22
- [x] Phase 11: Single-Distributor Stackelberg-Benders (Certified) (3/3 plans) — completed 2026-07-22
- [x] Phase 12: Cut-Store & Benders Master Robustness Hardening (2/2 plans) — completed 2026-07-23
- [x] Phase 13: Nash Diagonalization & Shared-Transmission Coupling (3/3 plans) — completed 2026-07-24
- [x] Phase 14: Validation-Oracle Regression Hardening & Docs (3/3 plans) — completed 2026-07-24

Delivered: the thesis's planning layer (rungs 6–7) — build-once Parameter-pinned planning oracle
with retry/checkpoint resilience, hand-rolled single-distributor Stackelberg-Benders certified
against BilevelJuMP MPEC reductions (leader/follower role + dual sign empirically pinned),
hardened cut store + BendersTrace ledger, SharedTransmission N-distributor corridor coupling,
run_nash! Gauss-Seidel diagonalization with nested tolerances + NashTrace two-level diagnostics,
run_nash_probe multi-seed/multi-order honesty gate ("a converged equilibrium", never "the"),
pinned computed goldens, a registry+tripwire no-binaries guard, and two live-executed literate
planning docs pages. Audit: 15/15 requirements, 10/10 integration seams. 2276 tests pass.

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–9 (archived) | v1.0 | 43/43 | Complete | 2026-07-20 |
| 10. Oracle Coupling Wiring & Resilience | v2.0 | 2/2 | Complete | 2026-07-22 |
| 11. Single-Distributor Stackelberg-Benders (Certified) | v2.0 | 3/3 | Complete | 2026-07-22 |
| 12. Cut-Store & Benders Master Robustness Hardening | v2.0 | 2/2 | Complete | 2026-07-23 |
| 13. Nash Diagonalization & Shared-Transmission Coupling | v2.0 | 3/3 | Complete | 2026-07-24 |
| 14. Validation-Oracle Regression Hardening & Docs | v2.0 | 3/3 | Complete | 2026-07-24 |
| 15. AC-Exactness Oracle | v2.1 | 2/3 | In Progress|  |
| 16. Reactive-Power (μ) Consensus | v2.1 | 0/4 | Planned | - |
| 17. Real IEEE-123 Impedances | v2.1 | 0/4 | Planned | - |
| 18. Directional Thesis Reproduction | v2.1 | 0/? | Not started | - |

## Deferred / Future-Milestone Notes

- **Meshed + 4Q-BESS** (deferred in v1.0 and again in v2.0): breaks the radial exactness proof —
  needs its own relaxation/exactness treatment.
- **Discrete/integer investment expansion** (binary-expansion + integer/Lagrangian cuts): explicitly
  out of v2.0 continuous-only scope; the PVAL-04 no-binaries guard must be consciously lifted when
  this milestone opens.
- **A live cross-subproblem reactive dual-ascent loop** requiring an actual AGR-side reactive
  decision variable (4Q-BESS/volt-var): deferred alongside meshed+4Q-BESS — v2.1's Phase 16 reads
  the reactive dual "for free" off a genuine equality constraint, not a live consensus loop, per
  thesis A3 (DERs are active-only).
- **Exact-figure thesis reproduction** (`REPRO-STRETCH-01`, the +$1,819/+25% headline): deferred,
  contingent on obtaining thesis Appendix E (currently behind an IP-blocked CONICET repository).
  v2.1's Phase 18 commits only to a directional (sign + band) reproduction.
- **Deferred tech debt**: see `milestones/v1.0-MILESTONE-AUDIT.md` and
  `milestones/v2.0-MILESTONE-AUDIT.md` (Info-severity review findings, user-local
  Project.toml/Manifest CairoMakie drift, Clarabel NUMERICAL_ERROR root cause).
</content>
