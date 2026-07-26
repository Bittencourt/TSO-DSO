# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md), and
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md).

## Phases

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

<details>
<summary>✅ v2.1 Validation & Reproduction (Phases 15–18) — SHIPPED 2026-07-26</summary>

- [x] Phase 15: AC-Exactness Oracle (3/3 plans) — completed 2026-07-26
- [x] Phase 16: Reactive-Power (μ) Consensus (4/4 plans) — completed 2026-07-26
- [x] Phase 17: Real IEEE-123 Impedances (4/4 plans) — completed 2026-07-26
- [x] Phase 18: Directional Thesis Reproduction (3/3 plans) — completed 2026-07-26

Delivered: the framework's validation & reproduction layer — an independent nonconvex AC-OPF oracle
(`ACPowerFlow` + `assert_ac_exact!`, Ipopt, true equality `l·v==P²+Q²`) that certifies the SOCP
relaxation per-hour and surfaces a **genuine high-PV/reverse-flow inexactness as a first-class citable
finding** (`pv_scale=1.2`, gap≈10.4) rather than tuning it away; a genuine reactive-power balance with a
**certified, citable reactive DLMP component** (`reactive_consensus` flag + `qag_dso` pinned coupling +
`assert_no_slack` on `:balance_q`, byte-identical default path); **real positive-sequence IEEE-123
impedances** reduced from public OpenDSS data via a dependency-free Fortescue parser (PMD kept out of
runtime `[deps]`), with an honest **asymmetric voltage-binding** finding (lower band transfers, upper
overvoltage band sits on the SOCP-inexactness knife-edge); and a defensible **directional, public-data**
thesis reproduction — the **DSO-surplus sign flip reproduces** (FIT −196.22 → DADP +3.73, prosumer
decreases) while the **+25% welfare magnitude does NOT** (~+0.045%), stated plainly, with a
measurement-before-golden stability harness. Audit: 12/12 requirements, 6/6 integration seams. 2348
tests pass (the only 2 failures are pre-existing Aqua/CairoMakie `Project.toml` drift, not regressions).

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–9 (archived) | v1.0 | 43/43 | Complete | 2026-07-20 |
| 10–14 (archived) | v2.0 | 13/13 | Complete | 2026-07-24 |
| 15. AC-Exactness Oracle | v2.1 | 3/3 | Complete | 2026-07-26 |
| 16. Reactive-Power (μ) Consensus | v2.1 | 4/4 | Complete | 2026-07-26 |
| 17. Real IEEE-123 Impedances | v2.1 | 4/4 | Complete | 2026-07-26 |
| 18. Directional Thesis Reproduction | v2.1 | 3/3 | Complete | 2026-07-26 |

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
  v2.1's Phase 18 delivered only a directional (sign + band) reproduction — and found the +25%
  welfare magnitude does not transfer to real public data (only the DSO-surplus sign flip does).
- **v2.1 overvoltage / SOCP-exactness knife-edge**: on real IEEE-123 impedances the upper voltage
  band (PV overvoltage, the thesis's voltage-driven regime) cannot be pushed toward ~1.05 while the
  SOCP relaxation stays exact — any future work needing that regime must use Phase 15's AC oracle
  or a different relaxation. See `milestones/v2.1-MILESTONE-AUDIT.md`.
- **Deferred tech debt**: see `milestones/v1.0-MILESTONE-AUDIT.md`, `milestones/v2.0-MILESTONE-AUDIT.md`,
  and `milestones/v2.1-MILESTONE-AUDIT.md` (unflipped Nyquist flags, ROADMAP "reactive pricing"
  wording, the `julia -e '@run_package_tests'` sibling-worktree gotcha, user-local Project.toml/Manifest
  CairoMakie drift, Clarabel NUMERICAL_ERROR root cause).
