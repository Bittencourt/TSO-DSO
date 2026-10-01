# TSO-DSO Integration Optimization Framework (Julia)

## What This Is

A Julia research framework for **experimenting with a TSO–DSO integration optimization theory**
built on transactive energy / dynamic distribution pricing and Stackelberg–Nash equilibria. It
implements the two-layer framework from J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022) and the
associated PSR N1–N2 expansion note: an **operational layer** (day-ahead dynamic pricing over a
convex branch-flow distribution network, solved as convex social-welfare maximization decomposed by
ADMM, with prices emerging as duals) and a **planning layer** (Stackelberg–Nash TSO–DSO investment
equilibria solved by Benders + diagonalization). It is the computational bench for Pedro's PhD:
reproducible experiments from simple to complex scenarios, with clean seams for model adaptations
and novel research extensions. Audience: the PhD researcher and collaborators (thesis, papers).

## Core Value

**A researcher can express a scenario and a model variant declaratively, run it end-to-end with an
open-source solver, and get trustworthy, reproducible results and prices — with every model
assumption documented and every layer swappable.** If everything else fails, this must work:
correct, validated optimization models that are easy to extend for research.

## Current Milestone: v4.0 Correctness & Depth

**Goal:** Fix the modeling defects confirmed by the 2026-09-28 full-project quality audit, deepen
the planning layer into a genuine bilevel TSO–DSO game on a real network, then restructure the
orchestration layer and clean the codebase — correctness first, depth second, structure third,
hygiene last.

**Target features:**
- **Correctness fixes (operational + integer planning)** — reversed LinDistFlow exactness copy in
  `ConvexBranchFlow` (v̂ ≤ v makes `v̂ ≥ V²min` a restriction, not a relaxation; verify thesis
  eq. 3.43 against the PDF); battery terminal SOC (`p_dch[T]` is free energy); reverse thermal
  limit (3.37); `corner_recourse` flat-profile Laporte–Louveaux cut invalid for T>1; flexible-load
  reactive draw (3.23); non-physical DLMP loss/voltage labels; exactness-gate absolute floor;
  uncertified FIT-baseline SOCP; MPC regret settled on forecast. Then re-pin goldens and re-run
  the thesis reproduction.
- **Planning depth** — a genuinely bilevel variant (TSO minimizes its own cost; DSO pays a tariff
  π·z) that the BilevelJuMP oracle can discriminate from joint optimization; SOCP
  (`ConvexBranchFlow`) on a multi-bus feeder inside the Benders loop with oracle-side feasibility
  cuts and inexactness handling; derived (not user-supplied) α lower bounds; a Nash fixture with
  interior caps that exposes GNE multiplicity (variational-equilibrium selection); refresh the
  stale PSR N1–N2 mapping writeup.
- **Architecture** — power-flow selector + strategy types in `Scenario` with `run(::Strategy, s)`
  dispatch covering MPC and stochastic; `AbstractFeeder` supertype; one `close_balance!` helper
  replacing 5 copies; split `solve_admm` and drop its `ConvexBranchFlow`-only typing; typed
  `ModelContext` metadata; one consistent report-vs-throw result/status policy; narrow the
  `mpc_loop` catch-alls.
- **Hygiene** — strip plan/wave/review IDs from source comments (keep thesis-equation refs);
  delete the inert SEAM-01 stubs and reactive-mode back-compat; trim generic exports; add a JET
  check; `:slow` test tag split; quarantine flakes; rename `fixtures_phaseN`; archive one-off
  scripts; drop the redundant root Manifest.

**Scope discipline:** the v1–v3 "byte-identical default path" rule is **consciously relaxed** for
the correctness track — fixes are expected to move pinned goldens and possibly the v2.1
thesis-reproduction numbers; every moved golden is re-derived and its change explained, never
silently re-pinned. Sequencing: Correctness → Planning depth → Architecture → Hygiene.

## Shipped Milestone: v3.0 Research Extension Rungs (2026-08-24)

Seven phases (19–25): 4Q-BESS + live reactive dual-ascent, overvoltage-capable restricted
relaxation, closed-loop MPC/RTP, two-stage stochastic extensive form, meshed SOCP with an
angle-recoverability certificate, discrete/integer investment via Laporte–Louveaux cuts, and the
IEEE-8500 benchmark (memory wall characterized honestly). See `milestones/v3.0-ROADMAP.md`.

## Shipped Milestone: v2.1 Validation & Reproduction (2026-07-26)

**Shipped 2026-07-26** — 4 phases, 14 plans, 27 tasks. Audit passed **12/12 requirements, 6/6
integration seams**; 2348 tests pass (the only 2 failures are pre-existing Aqua/CairoMakie
`Project.toml` drift, not regressions). Goal: harden the framework's core correctness claims so every
downstream extension — and the thesis itself — rests on validated, citable ground. No new research axis.

**Delivered:**
- **AC-exactness oracle** — `ACPowerFlow <: AbstractPowerFlow` (Ipopt, true nonconvex equality
  `l·v==P²+Q²`) dispatched through the unchanged `solve_welfare`; `assert_ac_exact!` certifies the SOCP
  solution per-hour (report-don't-throw); `recover_voltage_angles` (Baran–Wu BFS) validated on a 2-bus
  closed form.
- **Reactive-power consensus** — `reactive_consensus::Bool=false` kwarg (default byte-identical);
  `qag_dso` pinned coupling variable; `assert_no_slack` certificate on `:balance_q`; `extract_reactive_dlmp`
  adds a certified, citable reactive component to the DLMP decomposition (never summed into the active total).
- **Real IEEE-123 impedances** — dependency-free OpenDSS regex parser + Fortescue positive-sequence
  reduction (PMD kept out of runtime `[deps]`); real per-segment `const` table; topology untouched.
- **Directional thesis reproduction** — gate-then-golden on the DSO-surplus sign flip + two live literate
  pages, framed "directional, public-data," with a measurement-before-golden stability harness.

**Two headline scientific findings (both honest, both cross-cutting):**
1. **The radial SOCP relaxation is genuinely INEXACT under high-PV reverse flow** — found by the AC
   oracle on IEEE-13 (`pv_scale=1.2`, gap≈10.4, voltage pinned at V²max) and independently re-hit on
   real IEEE-123 (upper/overvoltage band cannot reach ~1.05 while exact). Surfaced as a citable finding,
   not tuned away.
2. **Thesis reproduction is DIRECTIONAL only** — the DSO-surplus sign flip reproduces on real public
   data (FIT −286.11 → DADP +3.74; prosumer surplus decreases), but the headline +25% welfare magnitude
   does **not** (~+0.263%). [RESTATED Phase 28 (plan 28-05 code review FIX, CR-01): figures above are
   current, superseding the stale pre-Phase-26/27 FIT −196.22 → DADP +3.73 / ~+0.045% figures. The
   "knife-edge-fragile" population-sweep characterization was also RETIRED BY MEASUREMENT in Phase 28
   (plan 28-02): flake rate dropped 13/20→1/20 and the sign flip now survives 5/5 swept points, not
   2/5 — see `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md`.]
   The exact +$1,819/+25% figure remains deferred (needs thesis App. E).

See `milestones/v2.1-ROADMAP.md` and `milestones/v2.1-MILESTONE-AUDIT.md`, and
`memory/v2.1-socp-inexactness-and-thesis-repro.md`.

## Requirements

### Validated

- ✓ Convex operational model: branch-flow (DistFlow/SOCP) power flow with voltage & congestion limits,
      LinDistFlow exactness constraints, validated exact on radial test feeders — v1.0
- ✓ Prosumer device models (thermostatic, deferrable, interruptible, PV+battery — no binaries) with
      concave quadratic utility/cost — v1.0
- ✓ Aggregator aggregation of prosumer devices into nodal net power + utility — v1.0
- ✓ Network & device model correctness (FIX-01..05: Gan–Low exactness-copy verdict, receiving-end limit
      3.37, full-horizon SOC, flexible-load reactive draw) — Validated in Phase 26: Network & Device Model Correctness
- ✓ Integer planning & pricing certificate correctness (FIX-06..10: T>1 recourse, DLMP naming, per-branch
      exactness floor, FIT certificate, MPC truth-plant settlement) — Validated in Phase 27: Integer Planning & Pricing Certificate Correctness
- ✓ Social-welfare maximization (`GLB-CVX`): Σ aggregator utility − wholesale purchase — v1.0
- ✓ Two selectable solve strategies — centralized monolithic **and** ADMM (`AGR-OPT`/`DSO-OPT`, DADP as
      duals, convergence diagnostics), cross-validated on IEEE 13 + 123 — v1.0
- ✓ DADP/DLMP extraction + 4-way decomposition (energy/loss/congestion/voltage) — v1.0
- ✓ Scenario & network data layer + IEEE 13/123 radial fixtures — v1.0
- ✓ Abstraction ladder (toy DC → SOCP/multi-period/ADMM) with stable interfaces per rung — v1.0
- ✓ Open-source solver integration behind `select_optimizer` (HiGHS/Ipopt/Clarabel; Gurobi/Mosek fallback) — v1.0
- ✓ Rich per-model documentation (Documenter + Literate, math+assumptions+validation) + reproducible experiment scripts — v1.0
- ✓ Extension seams (SEAM-01) for stochastic / MPC-RTP / meshed+4Q-BESS / Stackelberg-Nash — delivered as inert stubs — v1.0
- ✓ Planning oracle coupling (`p_import == z` Parameter pin, per-scenario dual `π_s`) with
      retry/checkpoint resilience (PLAN-01..03) — v2.0
- ✓ Single-distributor Stackelberg-Benders, hand-rolled, certified against BilevelJuMP MPEC
      reductions (leader/follower role + dual sign empirically pinned) (PLAN-04..07, PVAL-01) — v2.0
- ✓ Nash via Gauss-Seidel diagonalization over a shared transmission corridor
      (`SharedTransmission`, `run_nash!`, nested tolerances, two-level `NashTrace`,
      multi-seed/multi-order `run_nash_probe` honesty gate) (NASH-01..04) — v2.0
- ✓ Planning-layer permanent regressions: pinned computed goldens, no-binaries guard + tripwire,
      literate planning docs (Rung 6/7) (PVAL-02..04) — v2.0
- ✓ AC-exactness certification vs. an independent Ipopt AC-OPF oracle (`ACPowerFlow`, `assert_ac_exact!`
      per-hour report) — found + documented a genuine high-PV/reverse-flow SOCP inexactness (EXACT-01..04) — v2.1
- ✓ Reactive-power (μ) consensus: certified, citable reactive DLMP component off `:balance_q`, with a
      byte-identical default path (`reactive_consensus`, `qag_dso`, `extract_reactive_dlmp`) (REACT-01..03) — v2.1
- ✓ Real IEEE-123 impedances from public OpenDSS data via a dependency-free Fortescue reduction (no PMD
      runtime dep); honest asymmetric voltage-binding characterization (IMPED-01..03) — v2.1
- ✓ Directional ("directional, public-data") thesis reproduction — DSO-surplus sign flip reproduces on
      real data; the +25% welfare-ratio magnitude does not (REPRO-01..02) — v2.1

### Active

*(v4.0 Correctness & Depth — REQ-IDs defined in `.planning/REQUIREMENTS.md`)*

- Correctness: fix the audit-confirmed operational and integer-planning modeling defects; re-pin
  goldens and re-run the thesis reproduction with every change explained.
- Planning depth: genuine bilevel TSO–DSO variant, SOCP-in-the-loop Benders on a multi-bus feeder,
  derived bounds, GNE-multiplicity Nash fixture.
- Architecture: declarative power-flow + strategy selection in `Scenario`, shared balance helper,
  decomposed `solve_admm`, typed context, consistent status policy.
- Hygiene: readable source (no process IDs), dead code removed, lean exports, JET + slow/fast
  test split, flake quarantine, tidy scripts/manifests.

### Out of Scope

- Full planning-layer (N1–N2 Stackelberg–Nash expansion) *implementation* in v1 — architecture and
  interfaces must accommodate it, but the operational layer ships first. *(Deferred, not excluded.)*
- Real-time hardware / market integration, GUI/dashboards — this is a research/experiment library.
- Reproducing the original MATLAB+CVX codebase line-for-line — we port the *theory*, not the code.
- Unbalanced three-phase / phase-detailed modeling in v1 (thesis uses balanced positive-sequence).
- Stochastic/robust solving as a v1 deliverable — it is a designed-for extension, not initial scope.

## Context

- **Origin theory** (see `.planning/research/THEORY-thesis.md` and `THEORY-papers.md` for the full
  extraction with equation numbers):
  - Operational layer (Palacios thesis / IET GTD 2019): a **single-level convex social-welfare
    maximization** over a 24h horizon on a **Convex Branch Flow Model** (Baran–Wu DistFlow with SOC
    relaxation + LinDistFlow exactness), with quadratic prosumer utilities, solved **distributedly by
    ADMM**; the day-ahead dynamic price (DADP/DLMP) is the **dual of the nodal active-power balance**.
    *It is not itself an MPEC* — the leader/follower story is conceptual; the machinery is convex
    dual decomposition. Reference cases: modified IEEE 13-node (congestion) and 123-node (voltage)
    feeders. Original implementation: MATLAB + CVX.
  - Planning layer (PSR N1–N2 note): the **explicit Stackelberg–Nash game** — distributor = leader
    choosing flexibility investment + import profile, transmission reinforcement = follower; solved
    by **Benders decomposition**; multiple distributors → **Nash via Gauss–Seidel diagonalization**;
    integer investments → **binary-expansion + Lagrangian/integer-L-shaped cuts**. Coupling variable
    = N1↔N2 interconnection flow; linking price = interconnection dual ≈ DLMP.
- **Named research extension axes** (all four flagged as targets): stochastic PV/demand uncertainty;
  MPC / rolling-horizon / real-time pricing; meshed networks + four-quadrant BESS (Q-V, ancillary
  services); TSO–DSO planning coupling + real-data flexibility-aggregator valuation (Octopus/PSR
  collaboration angle noted in meeting notes).
- **Motivation** (from thesis intro): rising DER/PV penetration in Latin America, flat tariffs that
  don't reflect real costs, prosumer proliferation causing congestion & voltage issues, need for
  dynamic tariff signals coordinating many devices without compromising network security.

## Current State

**Phase 29 (Genuine Bilevel TSO-DSO Variant) COMPLETE 2026-09-30.** BILEV-01/BILEV-02 validated:
new production entry point `solve_bilevel!` / `build_bilevel_kkt` (`src/planning/bilevel_kkt.jl`)
solves a genuinely bilevel game — DSO leader with its own LinDistFlow valuation, TSO follower
minimizing its own cost `c(z) - pi_tariff*z` — as ONE single-level KKT-MILP (follower stationarity +
`MOI.SOS1` complementarity, closed-form proven dual bound `m_ub`, post-solve KKT-certificate LP that
returns unique minimal multipliers). Certified three ways (production == BilevelJuMP StrongDualityMode
== brute-force grid, all measurably != joint single-planner) on a corner fixture AND a non-degenerate
interior fixture (`y*=0.148`, `z*=1.48`, SOS1 branch switching, z≡0 stub rejected), plus d_max-binding
and T=2 fixtures. `solve_stackelberg!` (Benders) is unchanged — relabelled as the integrated variant.
3-iteration code review (cap reached; 1 warning — stale multipliers if a built model is mutated in place
— documented in `phases/29-*/29-REVIEW.md`). Suite 30871/0/0/5 (+168 bilevel/PVAL-04 assertions vs
Phase 28's 30703), zero golden moves.

**Phase 28 (Goldens Re-Derivation & Thesis Reproduction Restatement) COMPLETE 2026-09-30.**
FIX-11 validated: a mechanical, self-testing audit script confirms every golden moved across
Phases 26-27 was re-derived with a stated cause (`phases/28-*/28-CROSS-PHASE-AUDIT.md`); the
v2.1 thesis reproduction was re-run against the corrected Phase 26/27 model — the DSO-surplus
sign flip and prosumer-surplus decrease reproduce unchanged, and the v2.1 "knife-edge-fragile"
population-scale-sensitivity characterization is retired by measurement (flake rate
13/20->1/20, sign-flip survival 2/5->5/5); EXACT-04 and the SOC-relaxation applicability maps
were re-verified under both the default Gan-Low copy and the thesis-literal copy, correcting a
stale test comment that had conflated the two exactness gates; MPC truth-settlement and DLMP
naming restatements (deferred from Phase 27) are complete. Full suite certified at an EXACT
match to the Phase 27 close baseline (30703 pass / 0 fail / 0 error / 5 broken); the full
Documenter/Literate docs build is green after fixing two genuine pre-existing bugs (a latent
`DimensionMismatch` in `prosumer_welfare.jl`'s SOC plot, `api.md`'s HTML size threshold).
Every headline old->new number restated this phase, with its named cause, is consolidated in
[`28-RESTATEMENT-SUMMARY.md`](phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md).

**Phase 27 (Integer Planning & Pricing Certificate Correctness) COMPLETE 2026-09-29.** FIX-06..10 validated:
T>1 joint Benders recourse, DLMP `cone`/`drop` naming, hybrid per-branch exactness floor, FIT/MPC settlement
on AC physics (violations reported), ALMOST_OPTIMAL flake bounded. Suite 30703/0/0/5.

**v4.0 in progress — Phase 26 (Network & Device Model Correctness) COMPLETE 2026-09-29.** FIX-01..05
validated: default `ConvexBranchFlow` exactness copy now Gan–Low direction (honestly labelled a
conservative upper-band restriction, exact by theorem; thesis-literal copy kept as opt-in), receiving-end
thermal limit 3.37 in SOCP + AC formulations, battery SOC linked over `soc[1:T+1]`, flexible loads draw
`q = p·tanφ`, ADMM live reactive coupling by default with flexible loads. Headline goldens moved (see
`phases/26-*/26-GOLDEN-AUDIT.md`); thesis-repro restatement is Phase 28. New findings: App. C η<1
charge/discharge overlap; v2.1 high-PV knife-edge no longer reproduces under the default.

**v3.0 Research Extension Rungs — SHIPPED 2026-08-24.** All 7 phases (19–25) complete; milestone
archived to [`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md), audit `gaps_accepted`. 26 of
27 requirements satisfied; SCALE-05 accepted as an honest non-measurement (the ~40x headline
IEEE-8500 fixture OOM-killed at every density, so headline-scale timings/iterations/exactness were
never measured — true memory requirement lower-bounded only).

Seven research axes now ship as documented rungs, each with **its own** certificate — verified at
audit to reuse no other regime's tolerance: 4Q-BESS + live reactive dual-ascent; overvoltage-capable
restricted relaxation (with an honest OPF-ε negative result); closed-loop MPC/rolling-horizon RTP
(genuinely reusing Phase 20's escalation ladder); two-stage stochastic extensive form; meshed
non-radial SOCP with an angle-recoverability certificate exercising both verdicts; discrete/integer
investment via Laporte–Louveaux cuts certified against exhaustive enumeration, PVAL-04 guard scoped
not deleted; and the IEEE-8500 benchmark that characterized a memory wall honestly.

**Next milestone goals (candidates, not yet scoped):**
- **SCALE-STRETCH** — performance/memory-footprint engineering driven by the Phase 25 measurements:
  `solve_admm`'s hardcoded final-consolidation `assert_socp_exact!` at scale, and reaching a
  converged memory-feasible headline point. Deliberately separated from the benchmark justifying it.
- **Phase-18 `fit_baseline` convergence** — `ALMOST_OPTIMAL` at 3/5 sweep points at `tol_gap=1e-10`
  (flake rate 13/20, reproduced across 3 runs); distinct from SOCP inexactness.
- **Meshed + ADMM composition** — `solve_admm` is typed to `pf::ConvexBranchFlow`, so the literal
  meshed + live-reactive-price composition is structurally impossible today (MESH-06 advisory).
- **Integer investment beyond single-distributor Stackelberg** — the N>1 Nash/diagonalization path,
  plus a large-lattice termination criterion (a rigorous `δ_min` is provably not derivable).

Run `/gsd:new-milestone` to scope the next cycle.

<details>
<summary>Previous state (v3.0 in progress — click to expand)</summary>


**v3.0 in progress — Phase 23 complete (2026-08-10):** Meshed Networks (MESH-01/02/03/06).
`MeshedFeeder` + `assert_connected` beside the byte-untouched radial layer; `MeshedFlow` as pure
delegation (ConvexBranchFlow proven graph-generic); `certify_angle_recoverable!` chord-aware
certificate (report-by-default; recoverable → certified angles, unrecoverable → SOCP welfare as a
valid **upper** bound). Three honest findings shipped: the 3-bus triangle is degenerate under the
exactness-copy machinery (fixture = 4-bus diamond, triangle infeasibility demonstrated live on the
Rung 10 page); impedance magnitude — not R/X-ratio heterogeneity — separates the certificate
branches (0.00627 vs 0.0607 residuals, ~9.7×); the review caught the bound direction stated
backwards + a Phase-20-class orientation bug (both fixed, reversed-orientation regression added).
Review 2 Critical + 3 Warnings all fixed; verification 4/4 + UAT passed; suite 2801 pass / 3
pre-existing errored / 3 broken. Follow-up flagged: radial `recover_voltage_angles` carries the
same latent backward-edge defect (byte-locked by D-09, deferred). Next: Phase 24 (final).

**v3.0 Phase 22 complete (2026-08-10):** Stochastic PV/Demand Uncertainty
(STOCH-01..04). Two-stage extensive-form welfare (`build_stochastic_welfare`) over 3–5 seeded
Markov scenarios: nonanticipativity ties on battery p_ch/p_dch (+4Q q; redundant soc ties dropped
for IPM conditioning), per-scenario PF-04 gates, per-scenario DADPs de-scaled by probability as
THE price output (expectation only a labeled summary; degenerate S=1 reduction anchored to
solve_welfare). `StochasticOosHarness` Parameter-pinned out-of-sample evaluation with
skip-and-report infeasibility handling; `run_stochastic` orchestrator with measurement-before-
golden welfare gap (−0.02516, 3-run bit-stable). Rung 9 literate page. Review 1 Critical + 10
Warnings all fixed; D-06 test-sandbox flake ROOT-CAUSED (Pkg.test resolves JuMP 1.31 vs pinned
1.30 — diagnostics now baked into the test). Verification 4/4; suite 2752 pass / 0 fail / 3
pre-existing errored / 3 broken. Next: Phase 23 (Meshed Networks).

**v3.0 Phase 21 complete (2026-08-09):** MPC / Rolling-Horizon / Real-Time Pricing
(MPC-01..04). Build-once `MpcWindow` re-solved per step via JuMP `Parameter` injection (devices
Parameter-widened, anonymized containers), `run_mpc` closed-loop orchestrator with an
`mpc_step`-strided loop, hard terminal-SOC (A/B dump/hoard regression at ~35,530× margin),
`MpcTrace` RTP price-consistency ledger, and a genuinely never-throwing Phase-20 certificate
escalation ladder (`:certified_convex_dual(_restricted)` / `:cert_failed` provenance). Honest
regret benchmark vs perfect-foresight day-ahead on the same device set: regret ≈ −0.0321 on the
T=24 IEEE-13 literate page (Rung 8). Review 3 Critical + 7 Warnings all fixed (escalation window
bug, reachable throws, benchmark bias). Verification 4/4; suite 2685 pass / 3 pre-existing broken.
Known documented limits: Deferrable excluded from windows; forecast-consistent settlement.
Next: Phase 22 (Stochastic PV/Demand Uncertainty).

**v3.0 Phase 20 complete (2026-08-09):** Overvoltage-Capable Relaxation
(OVR-01..04). `RestrictedBranchFlow` implements Gan–Low's **OPF-m** shadow-voltage restriction
(`v̂_GL(s) ≤ v̄`) — cone-exact on the EXACT-04 high-PV fixture (gap 2.08e-8) where the plain SOCP
was proven inexact; the simpler OPF-ε bound-shrink was **proven insufficient** (full feasible-range
sweep, reverse-flow-driven residual — kept as a citable negative result). `assert_restriction_exact!`
certifies physical AC-feasibility + reports optimality loss (≈1.43 vs unrestricted bound;
`matches_ac_optimum=false` diagnostic — OPF-m provably excludes the AC optimum there);
`ac_dual_fallback_price` gives factory-routed multi-start Ipopt local duals with structural
`price_status` on certificate failure. Live literate rung page. Verification 4/4; review 1 Critical
+ 6 Warnings all fixed; suite 2563 pass / 0 fail / 3 pre-existing broken. Next: Phase 21 (MPC).

**v3.0 Phase 19 complete (2026-08-08):** 4Q-BESS + Live Reactive Dual-Ascent
(MESH-04/MESH-05). `FourQuadBESS` device (apparent-power cone, anonymous constraints), Aggregator
`q_inject` roll-up, `assert_4q_complementarity!` certificate with measurement-derived tolerances,
3-state `ReactiveMode` (OFF/CERTIFIED/LIVE), and a jointly-converging (λ, μ_q) two-block dual
ascent in `solve_admm`, cross-validated against centralized on 2-bus and IEEE-13 fixtures; the
default no-4Q path stays byte-identical. Verification 4/4; review 1 Critical + 4 Warnings all
fixed; suite 2513 pass / 0 fail / 3 pre-existing broken. Next: Phase 20 (Overvoltage-Capable
Relaxation).

**Shipped v1.0 "Operational Transactive-Energy Core" (2026-07-20)** — 9 phases, 43 plans, 83 tasks.

The operational transactive-energy layer is complete and validated end-to-end:
- **Solver abstraction** (`select_optimizer(::ProblemClass)`; Clarabel/HiGHS/Ipopt default, Gurobi/Mosek weakdep-gated), `assert_solved!` fail-loud status gate, `ModelContext` residual registry.
- **Power flow** via one swappable residual seam: DC, LinDistFlow, and SOCP Convex Branch Flow with the LinDistFlow exactness copy — relaxation validated exact on radial fixtures.
- **Prosumer device library** (thermostatic, deferrable, interruptible, PV+battery — no binaries) + aggregator roll-up + `GLB-CVX` social-welfare centralized solve + `operational_oracle(z)→(cost,π)`.
- **Pricing**: DADP/DLMP as the dual of the nodal active-power balance, 4-way DLMP decomposition, welfare/surplus accounting + FIT baseline, economic-direction checks.
- **ADMM** decomposition (AGR-OPT / DSO-OPT, adaptive ρ, primal+dual residual stop, build-once/re-solve) validated against the centralized optimum on IEEE 13 (congestion) + 123 (voltage).
- **Reproducibility**: declarative `Scenario` + `run_scenario`/`run_sweep`, seeded/bit-for-bit, provenance-stamped storage (DrWatson).
- **Docs & gate**: literate per-model math pages (Documenter + Literate, `@example`-executed), an end-to-end regression acceptance gate, and pinned regression fixtures.

**Health:** 1946 tests pass / 0 fail / 2 documented-broken (thesis-figure cross-checks); docs build green.

**Known deferred tech debt** (accepted; see `milestones/v1.0-MILESTONE-AUDIT.md`): thesis welfare-headline
figure digitization (Phase 4/5), IEEE-123 exact App. E impedances (Phase 7), `sub_seed` cross-version
hash stability (Phase 8), and an intermittent version-independent Clarabel `NUMERICAL_ERROR` on the
IEEE-13 ADMM solve (post-v1, flagged in STATE.md). *Closed post-v1 (2026-07-20/22):* published docs site
(`DOCUMENTER_KEY` + Pages), docstring `@docs` manual wiring, JuliaFormatter-on-`docs/`, `deploydocs` slug.

</details>

## Shipped Milestone: v2.0 Stackelberg-Nash TSO–DSO Planning Game (2026-07-24)

**Shipped 2026-07-24** — 5 phases, 13 plans, 25 tasks, +24,760 LOC. Audit passed 15/15
requirements, 10/10 integration seams, 2276 tests pass (health baseline; the only failing check
on a dirty local checkout is the user-local CairoMakie Project.toml drift — see v2.0 audit).
Next milestone not yet scoped — run `/gsd:new-milestone`.

**Progress:** All phases 10–14 complete (2026-07-24).
- Phase 14 — Validation-Oracle Regression Hardening & Docs: planning goldens pinned
  (`test/fixtures_planning.jl` + gate-then-golden `test_planning_goldens.jl` — N=1 certified
  equilibrium and N=2 Nash equilibrium, probe spread bounded), consolidated 4-builder
  no-binaries guard + source/export tripwire (`test_planning_noninteger.jl`, negative-tested),
  and the Documenter build fixed red→green with a Planning Layer @autodocs section plus two
  live-executed literate rung pages (Rung 6 Stackelberg–Benders narrating the BilevelJuMP
  certification; Rung 7 Nash diagonalization, "a converged equilibrium" language).
  Verification 4/4; review clean after 4 fixes (incl. Deferrable +18 objective-offset
  reconciliation in docs).
- Phase 13 — Nash Diagonalization & Shared-Transmission Coupling: `SharedTransmission` pooled
  N2-corridor coupling model (`coupling.jl`, per-distributor `x_inv[i]` ownership over one shared
  capacity row, build-once/`Parameter`-pinned, `DistributorView` atomic best-response),
  `run_nash!` outer Gauss-Seidel loop with nested-tolerance guard + damping + `NashTrace`
  two-level ledger, `plot_nash_convergence` (CairoMakie ext), and `run_nash_probe` — the NASH-04
  honesty gate: ≥3 seeds × 2 sweep orders, max-pairwise-distance spread, structural
  "**a** converged equilibrium" reporting. Verification 5/5; code review clean after a 3-iteration
  fix loop (6 fixes, incl. CR-01 seed-liveness making the multi-seed dimension genuinely live,
  proven by a distinct-equilibria regression: cold `[0.6,0.6]` vs hot-seed `[0.7,0.0]`).
- Phase 12 — Cut-Store & Benders Master Robustness Hardening: purpose-built `BendersTrace`
  per-iteration convergence ledger (retry counts, master/oracle statuses, solve-only timing),
  degenerate feasibility-cut edge cases proven safe, 66-iteration load test with retry +
  checkpoint active (measured 0 Clarabel escalations on planning fixtures), cut-store growth
  instrumented (unbounded accumulation retained). 4097 tests pass / 0 fail; review clean.
- Phase 10 — Oracle Coupling Wiring & Resilience: `build_planning_oracle`/`solve_planning_oracle!`
  (build-once, `Parameter`-pinned `p_import == z` coupling, per-scenario dual `π_s`),
  `solve_with_retry!` (bounded Clarabel-conditioning ladder), `checkpoint_iteration!`/resume.
- Phase 11 — Single-Distributor Stackelberg-Benders (Certified): `FollowerLP` (genuine HiGHS
  Farkas certificates), `BendersMaster` (build-once, persistent optimality + feasibility cut
  rows, incumbent-tracked UB), `solve_stackelberg!` (end-to-end convergence, rel-gap 1e-6,
  per-iteration checkpointing). **Leader/follower role + coupling-dual sign convention
  empirically certified**: StrongDualityMode, ProductMode, hand enumeration, and the production
  Benders loop independently agree (y*=z*=0.7, cost −0.245) — permanent `[:planning]` regression;
  BigMMode+HiGHS MIQP incapacity pinned as an asserted negative regression. 4039 tests pass /
  0 fail; phase code review clean after 6 fixes.

**Goal:** Add the thesis's planning layer — a bilevel TSO–DSO investment equilibrium where
distributor-leaders choose flexibility investment / import profiles against a transmission-reinforcement
follower, reaching a Nash equilibrium across multiple distributors via Gauss-Seidel diagonalization.

**Target scope:**
- **Multiple distributors → Nash** (Gauss-Seidel diagonalization; each solves its own bilevel vs shared transmission)
- **Continuous investment variables first** — convex Benders master (LP/QP); discrete/integer expansion (binary-expansion + integer/Lagrangian cuts) deferred to a later milestone
- **Hand-rolled Benders + diagonalization** (per CLAUDE.md); **BilevelJuMP as a small-case validation oracle only**, never the production solver
- **Reuses v1's `operational_oracle(z)→(cost,π)`** as the lower level — the coupling seam (`z↔p_ag`, `λ_j↔π_s`, leader/follower role) shipped as SEAM-01 stubs in v1

**Key context / risks:** Source (PSR N1–N2 note) is MEDIUM-confidence; the author flagged
**leader/follower-role inconsistency** and **integer-cut correctness** as open concerns. Mitigation:
research-first, continuous-before-integer, single-bilevel-before-Nash sequencing, and BilevelJuMP
KKT/SOS1/Fortuny-Amat cross-validation on tiny instances. Coupling variable = N1↔N2 interconnection
flow; linking price = interconnection dual ≈ DLMP.

## Constraints

- **Tech stack**: Julia + JuMP for optimization modeling — the natural ecosystem for research-grade
  math programming with swappable solvers and good performance.
- **Solvers**: Favor open source — HiGHS (LP/MILP), Ipopt (NLP), Clarabel/SCS (conic/SOCP). Gurobi
  permitted only as a commercial fallback, behind a solver-abstraction so no model hard-depends on it.
- **Correctness**: SOCP relaxation must be validated **exact** on radial fixtures (LinDistFlow trick);
  results must be reproducible (seeded data generation, pinned environment via `Project.toml`/`Manifest.toml`).
- **Extensibility**: architecture must let a researcher swap the power-flow model, device models,
  objective, and solve strategy independently — model adaptations are a first-class use case.
- **Documentation**: rich, step-by-step docs of every modeling decision and its math are a hard
  requirement, not optional. Clean, idiomatic, well-organized Julia code.
- **Audience/purpose**: PhD thesis research — favor clarity, correctness, and traceability to the
  source theory over premature performance optimization.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v1 targets the **operational layer** first (transactive pricing / dynamic pricing) | It is the validated core of the framework and the foundation the planning layer sits on | ✓ Good — v1.0 delivered the full operational layer, all 35 requirements verified |
| **Abstraction ladder** (toy → full AC/ADMM) rather than replicate-then-extend | Prioritizes clean, extensible architecture; validation grows with complexity | ✓ Good — rungs 0–5 each shipped a runnable, validated end-to-end solve |
| Support **both** centralized (monolithic) **and** ADMM decomposition, selectable per experiment | Centralized = clarity/small cases; ADMM = scale + matches thesis & yields prices as duals | ✓ Good — ADMM cross-validated against centralized on IEEE 13 + 123 (welfare rtol 1e-4) |
| Julia + **JuMP** with a **solver-abstraction** layer | Research-grade modeling, swappable open-source solvers, Gurobi only as fallback | ✓ Good — `select_optimizer(::ProblemClass)` factory; no model names a solver; Gurobi/Mosek weakdep-gated |
| Operational layer built as **convex SOCP + ADMM**, *not* MPEC | Matches the actual thesis math; MPEC/bilevel tooling is reserved for the planning layer | ✓ Good — SOCP Convex Branch Flow with validated exactness; DADP = dual of nodal balance |
| Design **extension seams** for stochastic / MPC-RTP / meshed+4Q-BESS / TSO-DSO Stackelberg-Nash | All four are declared PhD research directions; scaffolding must not preclude them | ✓ Good — SEAM-01 stubs (multi-scenario hook, rolling-horizon param, meshed slot, coupling-flow z↔p_ag/λ_j↔π_s + leader/follower role) delivered inert in Phase 4; the Stackelberg-Nash seam was consumed live in v2.0 with zero seam rework |
| **Hand-rolled Benders + Gauss-Seidel diagonalization**, BilevelJuMP as validation oracle only | Matches thesis method; MPEC single-level blowup scales poorly and diverges from decomposition intent | ✓ Good — v2.0 production loop is hand-rolled; BilevelJuMP certified the tiny case (4-way agreement) and stays a `[:planning]` regression |
| **Per-distributor investment ownership** over one pooled corridor capacity row (vs equal-split joint investment) | Resolves the N-distributor cost-allocation ambiguity the PSR source leaves open; game-theoretically cleaner best-response pricing | ✓ Good — v2.0 `SharedTransmission`; departure from equal-split documented in coupling.jl for thesis traceability |
| **Continuous-only planning scope**, enforced by an automated no-binaries guard | Convex Benders masters first; integer expansion deferred until Lagrangian/integer-L-shaped cuts milestone | ✓ Good — PVAL-04 guard + tripwire negative-tested; lift consciously when the integer milestone opens |
| **Fresh cut store per Nash best-response** (no cut reuse across sweeps) | Cuts computed at old z_{-i} are generally invalid once neighbors move; correctness-first | ✓ Good — rebuild cost instrumented in trace; cut-reuse deferred until a validity argument exists |
| **"A converged equilibrium" reporting language** (never "the equilibrium"), encoded in code | Diagonalization has no uniqueness guarantee; honesty gate is structural, not prose convention | ✓ Good — run_nash_probe multi-seed/multi-order spread reporting; carried into Rung 7 docs |
| **AC oracle is a genuinely independent nonconvex peer** (`ACPowerFlow`, true equality `l·v==P²+Q²`), and `assert_ac_exact!` **reports per-hour, never throws** on a numeric gap | An oracle that re-solved the same relaxed cone would prove nothing; a genuine inexactness is the milestone's most valuable finding, not a defect to suppress | ✓ Good — v2.1; the high-PV SOCP inexactness surfaced as a citable finding (EXACT-04), reproduced again on real IEEE-123 |
| **Reactive dual read "for free" off a certified `:balance_q`** — no live μ dual-ascent loop | Thesis A3 makes DERs active-only, so `qag_dso` is a fixed constant; a one-shot certified dual suffices and avoids over-building | ✓ Good — v2.1; `assert_no_slack` gate makes the reactive DLMP trustworthy; `Scenario.jl` golden-hash untouched |
| **Real IEEE-123 impedances via a dependency-free regex parser** (PMD dropped entirely, not weakdep) | The `.dss` files are simple; a ~50-line parser satisfies "PMD out of runtime deps" trivially and is more reproducible | ✓ Good — v2.1; zero new deps; linecode.1 sanity-pinned (R1≈0.05797) |
| **Thesis golden pinned on the DSO-surplus SIGN FLIP, not the welfare ratio** | The aggregate `welfare_dadp/welfare_fit` ratio sign-inverts on negative welfare; the surplus sign flip is the thesis's own framing and is sign-safe | ✓ Good — v2.1; honest directional-only result — +25% magnitude does not transfer (~+0.263%, restated Phase 28 CR-01 from the stale ~+0.045% figure), stated plainly |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-30 — Phase 29 complete (v4.0 Correctness & Depth)*
