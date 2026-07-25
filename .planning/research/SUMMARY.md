# Project Research Summary

**Project:** TSO-DSO Integration Optimization Framework (Julia) — v2.1 "Validation & Reproduction"
**Domain:** Hardening milestone for a Julia/JuMP power-systems transactive-energy research bench
(SOCP branch-flow + ADMM operational core, already shipped in v1.0/v2.0) — NOT a new research axis
**Researched:** 2026-07-25
**Confidence:** HIGH — all four researchers converge strongly and verified claims directly against
source files (`src/models/exactness.jl`, `src/admm/AgrOpt.jl`/`DsoOpt.jl`/`solve_admm.jl`,
`src/data/ieee123.jl`, `src/solver/factory.jl`) rather than assuming architecture.

## Executive Summary

This is a validation milestone, not a feature milestone: all four target capabilities — an
independent AC-OPF exactness oracle, a reactive-power (μ) ADMM consensus, real IEEE-123 impedances,
and a directional thesis reproduction — slot into **existing, already-proven architectural seams**
with **zero new main dependencies**. The AC-OPF oracle is a peer `AbstractPowerFlow` subtype reusing
the already-wired Ipopt/`NLP()` solver path; the reactive consensus is a feature-flagged mirror of
the existing active-power λ/ADMM machinery; the real impedances are an offline PMD-parse (weakdep,
never a runtime dependency) feeding a committed pure-data table; the reproduction reuses the
established literate-rung + gate-then-golden pattern from v2.0. All four researchers independently
reached this "additive extension, not restructuring" conclusion — the strongest signal that the
v1.0/v2.0 architecture is fit-for-purpose.

The recommended approach is dependency-ordered, not effort-ordered: (a) the AC-OPF oracle and (b)
the reactive-μ consensus are both structurally independent and can be built/tested in isolation
against existing fixtures; (c) real IEEE-123 impedances is a self-contained data-engineering task
whose *validation* benefits from (a) and (b) being available; (d) directional reproduction strictly
depends on (b)+(c) landing first, since the thesis's voltage-driven Case B result needs both real
data and priced reactive power to be a credible mechanism check. This ordering — independent code
changes first, convergent validation last — is both PROJECT.md's own stated sequencing intuition and
the architecture/pitfalls researchers' independently-derived recommendation.

The key risk this milestone must manage is epistemic, not technical: a "failing" validation check
(an AC-vs-SOCP gap, a slack voltage constraint, a wrong-sign reproduction) is not automatically a
bug — the SOCP relaxation is *known* from the literature to go genuinely inexact under high-PV
reverse flow, and this milestone's own instrumentation could surface that as a real, citable finding
rather than something to tolerance-adjust away. A second, concrete risk is a naming collision: the
reactive dual `μ_j[t]` this milestone introduces collides with an *already load-bearing* scalar
`μ::Real=10.0` (the adaptive-ρ residual-balancing band) that is part of `Scenario`'s golden-hash
schema — this must be resolved as literally the first design decision of the reactive-consensus
phase, before any code is written, or it risks silently corrupting existing reproducibility guarantees.

## Key Findings

### Recommended Stack

No new main dependencies for the entire milestone. Ipopt (already a main dep) is sufficient for the
AC-OPF oracle — the missing piece is a *formulation* (a new `AbstractPowerFlow` subtype), not a
solver. The Fortescue/positive-sequence reduction is ~15 lines of `LinearAlgebra` stdlib code (no
package exists or is needed). PowerModelsDistribution (PMD) 0.16.0 is added as a **weakdep + package
extension only** (mirroring the existing Gurobi/Mosek/CairoMakie pattern) — confirmed it no longer
transitively pulls in PowerModels.jl/Memento (dropped after PMD 0.10), and confirmed compatible with
the project's pinned JuMP 1.30.1. PMD is used strictly as an offline parsing oracle for the raw
OpenDSS `.dss` files (`eng["line"]`/`eng["linecode"]`, never `transform_data_model`) — never a
runtime/`[deps]` dependency, so ordinary `using TSODSO` sessions and CI never touch it.

**Core technologies:**
- **Ipopt 1.15.0** (existing main dep): nonconvex NLP backend for the new AC-OPF oracle — no version
  bump, no new wiring, `NLP()` already resolves to it via `select_optimizer`.
- **LinearAlgebra (stdlib)**: hand-rolled Fortescue reduction (`A = [1 1 1; 1 a^2 a; 1 a a^2]`,
  `a = e^{j120deg}`) collapsing 3x3 phase-impedance matrices to positive-sequence scalars — no
  third-party package exists or is warranted.
- **PowerModelsDistribution 0.16.0** (new weakdep + extension, `TSODSOOpenDSSExt`): parses the public
  IEEE-123 OpenDSS files, following `Redirect`/`Compile` directives natively; output is vendored as
  a committed, PMD-free, JuMP-free `const Dict` — PMD is never imported inside `src/` at runtime.

### Expected Features

The FEATURES researcher frames "table stakes" here as *what a citable validation claim in the SOCP/
AC-OPF/DLMP/reproducibility literature requires*, not general product completeness. All four
capabilities have a well-established literature basis (Farivar-Low, Gan-Li-Topcu-Low for SOCP
exactness on IEEE-13/34/37/123; Bhattacharya et al. for the 5-way DLMP decomposition including a
reactive-price component; ACM Artifact Review's "Reproduced vs. Replicated" distinction for the
directional-reproduction framing).

**Must have (table stakes):**
- Independent nonconvex AC-OPF oracle (Ipopt, multi-start, same feeder/dispatch snapshot as the
  SOCP) + objective/voltage/flow gap report alongside the existing cone-tightness gate.
- Genuine per-node reactive balance `R_{q,j}[t]=0` as a real DSO-OPT equality (replacing the free
  `q_import` aggregate slack), yielding `mu_j = dual(R_{q,j})` "for free" and a citable Q-DLMP.
- Real IEEE-123 impedances via the verified Fortescue-averaging reduction on public OpenDSS data,
  cross-checked against a PMD oracle fidelity measure.
- Directional welfare/DLMP reproduction: sign + magnitude-BAND pinned regression (never exact
  equality to a digitized figure) with explicit "Reproduced, not Replicated" framing stated before
  any numbers.

**Should have (differentiators):**
- Stress sweep deliberately hunting a genuine relaxation gap (high-PV reverse flow on IEEE-123) —
  this is the single most valuable finding the milestone could produce, not a nice-to-have.
- Reactive-price sensitivity plot (mu_j vs. voltage-band tightness).
- Directional reproduction of the thesis's own sensitivity sweep (battery x1.5, PV x1.5, willingness x1.5).

**Defer (v2+):**
- A live cross-subproblem mu ADMM dual-ascent loop requiring an actual AGR-side reactive decision
  variable (4Q-BESS/volt-var) — this is the deferred meshed+4Q-BESS research axis, explicitly out of
  scope; today's mu is a free dual read because AGR-side Q is fixed, not a live consensus quantity.
- A-priori exactness-condition auto-checker (Gan-Li-Topcu-Low style) — paper-worthy in its own right.
- Thesis-figure digitized overlay — gated on obtaining the IP-blocked Appendix E, stretch only.

### Architecture Approach

All four capabilities integrate as **additive extensions of existing seams**, confirmed by direct
source inspection, with no change required to `ModelContext.jl`, `ProblemClass.jl`,
`solver/factory.jl`, or the DC/LinDistFlow/ConvexBranchFlow formulation files.

**Major components:**
1. **`ACPowerFlow <: AbstractPowerFlow`** (new, `src/powerflow/`) — mirrors `ConvexBranchFlow`
   variable-for-variable but replaces the relaxed SOC inequality with the true nonconvex equality
   `l*v == P^2+Q^2`; dispatches through the *existing* `solve_welfare` entrypoint unchanged; a new
   sibling file `src/models/ac_oracle.jl` holds `assert_ac_exact!` as an independent gate alongside
   (not inside) `exactness.jl`.
2. **`DsoOpt`/`AgrOpt`/`solve_admm` reactive extension** (modified, `src/admm/`) — a
   `reactive_consensus::Bool=false` kwarg threading a real `qag_dso[j,t]` coupling variable and a
   `mu_j[t]` dual-ascent block through the same build-once/coefficient-mutate ADMM loop already used
   for the active block; `AgrOpt.qag` (already computed, documented as unread) becomes the consensus
   target `b_j`. Stop criterion becomes AND (both p- and q-blocks converged), never OR.
3. **Offline PMD-parse to committed pure-data pipeline** (new, `scripts/` + `src/data/`) — a
   throwaway-env script (`scripts/ieee123_opendss_reduce.jl`) parses OpenDSS once, applies the
   Fortescue reduction, and writes a committed `const Dict` (`src/data/ieee123_impedances.jl`)
   consumed by `ieee123.jl`'s existing topology/relabeling logic unchanged — PMD never enters
   `Project.toml`'s `[deps]`.
4. **Literate rung + gate-then-golden reproduction** (new, `docs/literate/` + `test/`) — reuses the
   exact Rung-6/7 / PVAL-02 pattern: gate on the run's own correctness checks first, THEN assert
   sign + a wide magnitude band (never exact equality) against pinned constants.

### Critical Pitfalls

1. **A genuine SOCP inexactness (high-PV reverse flow) gets tolerance-adjusted away instead of
   investigated** — the single most damaging failure mode, because it discards the milestone's most
   scientifically valuable possible finding. Avoid by treating disagreement as a candidate genuine
   inexactness first (check reverse-flow/voltage-binding state) and reporting a per-hour/per-branch
   table, never a single pass/fail boolean.
2. **The `mu` naming collision**: the new reactive-consensus dual `mu_j[t]` and the *already
   load-bearing* adaptive-rho scalar `mu::Real=10.0` (threaded through `solve_admm`'s kwargs AND
   `Scenario`'s golden-hash-serialized schema) are two completely different objects that both want
   the same Greek letter. Must be the first design decision of the reactive-consensus phase — grep
   every existing `mu` usage and pick a distinct code identifier before any new field is added.
3. **AC-OPF comparison artifacts masquerading as relaxation failures**: Ipopt local-optimum
   convergence, mismatched problem data between the SOCP and AC models, unit/per-unit mismatches, or
   angle-recovery bugs can all produce a false "inexact" verdict. Avoid via: same feeder/aggregator/
   dispatch snapshot on both sides (never re-sampled), multi-start Ipopt with SOCP warm start, and
   validating angle recovery on a trivial 2-bus fixture first.
4. **Adding Q-consensus silently breaks the already-shipped active-only regression**: a second
   consensus dual changes DSO-OPT's cone structure and may compound the project's own documented,
   accepted, intermittent Clarabel `NUMERICAL_ERROR` flake. Gate behind a feature flag defaulting to
   the old behavior; prove the active-only path byte-identical with the flag off before touching any
   Q-consensus fixture; empirically re-measure the flake rate under Q-consensus rather than assuming
   v1.0's rate transfers.
5. **Silent golden re-pinning masks real regressions**: swapping synthetic to real IEEE-123
   impedances changes every downstream pinned number; "re-pin to whatever comes out" cannot
   distinguish "real data is legitimately different" from a units bug (feet-vs-miles, a ~1000x or
   ~5280x silent global rescale is the classic IEEE-123 OpenDSS trap), a reduction error, or an
   omitted regulator/capacitor silently un-tightening the deliberately-tuned voltage-binding case.
   Require a before/after invariant comparison (voltage-binding, exactness margin, iteration count)
   and keep the old synthetic goldens as an independent parallel regression.

## Cross-Cutting Decisions (surfaced across all four researchers)

- **AC oracle is designed to ALLOW a genuine inexactness finding.** All four researchers agree this
  is a feature of the design, not a risk to eliminate — the high-PV/reverse-flow stress fixture and
  per-hour/per-branch gap reporting are gating deliverables specifically so a real relaxation gap
  can surface and be documented as a milestone finding (bounding where operational-layer prices can
  be trusted), rather than engineered away by tolerance-tuning.
- **`qag`/naming resolution is a phase-1 design gate, not implementation detail.** FEATURES argues a
  full live mu dual-ascent loop may be unnecessary at all (DERs are active-only per thesis A3 — making
  the reactive balance a genuine per-node equality yields `mu_j = dual(R_{q,j})` "for free" without a
  separate outer-loop dual-ascent). ARCHITECTURE and PITFALLS agree the `mu` naming collision with the
  existing adaptive-rho band must be resolved before any code lands. Rollout must be behind a feature
  flag (default off) to protect the cross-validated active-only regression.
- **IEEE-123 pipeline: offline script to committed pure-data file, PMD never in `Project.toml`.** All
  four researchers independently converge on this exact shape: `scripts/ieee123_opendss_reduce.jl`
  (own throwaway env) to `src/data/ieee123_impedances.jl` (committed `const Dict`, PMD-free, JuMP-free)
  to `ieee123.jl`'s existing lookup, topology untouched. Risk flagged by ARCHITECTURE and PITFALLS
  alike: real impedances may loosen or tighten the SOC cone / shift the voltage-binding property the
  synthetic fixture was hand-tuned for — population/PV re-tuning may be required as part of this
  phase's own acceptance criteria, not an assumed side effect.
- **Directional reproduction reuses the v2.0 literate-rung + gate-then-golden pattern verbatim**, with
  a wide sign+magnitude-band assertion (never exact equality to the thesis's `+$1,819/+25%` — Appendix
  E is IP-blocked). Exact-figure overlay is an explicit, contingent stretch goal only.
- **Dependency-aware build order maps directly to 4 phases**, converging across ARCHITECTURE and
  PROJECT.md's own stated intuition:
  1. AC-OPF oracle — fully independent (touches `powerflow/`, `models/` only).
  2. Reactive mu-consensus — independent code-wise (touches `admm/` only) but most invasive to an
     already-shipped path; sequenced second so its goldens are re-validated before Phase 3/4 build on it.
  3. Real IEEE-123 impedances — independent data-engineering, but its *validation* (still
     voltage-binding? still SOC-exact? still well-conditioned?) benefits from Phases 1 and 2 existing.
  4. Directional reproduction — strictly depends on Phases 2+3 landing (voltage-driven Case B needs
     both real data and priced reactive power to be a credible mechanism check); optionally reports
     an AC-certification badge from Phase 1.

## Implications for Roadmap

### Phase 1: AC-OPF Exactness Oracle
**Rationale:** Fully self-contained (new `ACPowerFlow` subtype + `ac_oracle.jl`; reuses the existing
Ipopt/`NLP()` wiring and `solve_welfare` entrypoint unchanged); no dependency on the other three
capabilities; can be developed and tested against existing 2-bus/IEEE-13/synthetic-IEEE-123 fixtures
immediately.
**Delivers:** A new `AbstractPowerFlow` peer subtype enforcing the true nonconvex AC equality;
`assert_ac_exact!` gate reporting objective/voltage/flow gaps alongside the existing cone-tightness
check; a deliberate high-PV/reverse-flow stress fixture designed to allow (not suppress) a genuine
inexactness finding; a literate rung page.
**Addresses:** AC-OPF oracle table stakes (FEATURES Capability A) — independent oracle, multi-start
Ipopt guard, objective/voltage/flow comparison report, written methodology note.
**Avoids:** Pitfall 1 (comparison artifacts masquerading as relaxation failures — same-snapshot
contract, angle-recovery validation on a trivial fixture, multi-start) and Pitfall 2 (genuine
inexactness tolerance-adjusted away — per-hour/per-branch reporting, investigate before touching tolerances).

### Phase 2: Reactive-Power (mu) Consensus in ADMM
**Rationale:** Independent of Phase 1's files (`admm/` vs `powerflow/`+`models/`); sequenced second
because it is the most invasive change to an already-shipped, cross-validated build path — its own
goldens must be re-validated before Phases 3/4 build on top of it. The naming-collision decision and
feature-flag design must happen first, before any `AgrOpt`/`DsoOpt` code changes.
**Delivers:** A `reactive_consensus::Bool=false` kwarg (default preserving old behavior byte-for-byte)
introducing a genuine per-node `R_{q,j}=0` equality, a distinctly-named reactive dual (NOT `mu`, which
collides with the existing adaptive-rho band), and `mu_j[t]`/`dual(R_{q,j})` as a first-class reported
Q-price, extending the existing 4-way DLMP decomposition to 5-way.
**Implements:** ARCHITECTURE's "feature-flagged structural change with a compatibility overload"
pattern (mirroring the project's own Phase-6-to-7 `record!` precedent).
**Uses:** No stack changes — pure orchestration extension of `src/admm/AgrOpt.jl`, `DsoOpt.jl`,
`solve_admm.jl`, `residuals.jl`.
**Avoids:** Pitfall 3 (naming collision — resolve first, before code), Pitfall 4 (Q-consensus
degrading convergence + breaking the active-only regression — feature-flag, prove byte-identical
with flag off, re-derive joint residual balancing, pin the reactive DLMP on a from-scratch 2-bus toy
case), and Pitfall 5 (Clarabel `NUMERICAL_ERROR` amplification — empirically re-measure, don't assume).

### Phase 3: Real IEEE-123 Impedances
**Rationale:** Code-independent of Phases 1/2 (touches `data/`, `scripts/` only), but its own
validation (is the case still voltage-binding? still SOC-exact? still well-conditioned?) benefits
from Phases 1 and 2's instrumentation being available to certify the real-data case on the new topology.
**Delivers:** An offline PMD-parse script (weakdep+extension, never a runtime dep) producing a
committed, pure-data impedance table via the verified Fortescue-averaging reduction; explicit
per-component-type modeling decisions for regulators/capacitors/switches; a binding-voltage-constraint
acceptance test; before/after invariant comparison for any golden re-pin, with old synthetic goldens
kept as an independent parallel regression.
**Uses:** PowerModelsDistribution 0.16.0 as a weakdep+extension (`TSODSOOpenDSSExt`); stdlib
`LinearAlgebra` for the Fortescue reduction.
**Addresses:** FEATURES Capability C table stakes (documented reduction, PMD-oracle-only parsing,
written caveat enumerating approximation error sources, quantitative fidelity cross-check).
**Avoids:** Pitfall 6 (length/units ambiguity — silent global rescale; PMD-parse + published-reference
cross-check), Pitfall 7 (per-linecode reduction validity — fidelity metric per linecode, not just one
verified case), Pitfall 8 (regulators/capacitors silently un-tightening the voltage-binding case —
explicit decisions + acceptance test), and Pitfall 9 (silent golden re-pin masking a regression).

### Phase 4: Directional Thesis Reproduction
**Rationale:** Strictly depends on Phase 2 (reactive pricing needed for DLMP/voltage credibility) and
Phase 3 (real, standard data) both landing — the thesis's voltage-driven Case B result is not
credible on synthetic impedances or without priced reactive power. Optionally consumes Phase 1 for an
AC-certification badge on the reproduction run. Last phase by design.
**Delivers:** A literate reproduction rung (promoted from the existing exploratory
`scripts/thesis_caseA.jl`), a dedicated fixtures module with a pinned sign + magnitude BAND (never a
point value), a gate-then-golden test asserting the run's own correctness gates before the directional
check, and a single consolidated "reproduction assumptions" doc page enumerating the full chain
(units resolution, reduction fidelity, component omissions, aggregator population, PV scenario).
**Addresses:** FEATURES Capability D table stakes — "Reproduced, not Replicated" framing stated
before any numbers, sign check, pinned band regression, qualitative DADP-shape plot.
**Avoids:** Pitfall 10 (overclaiming / undocumented assumption chain — fixed qualifier phrase +
consolidated doc page, everywhere the number is cited) and Pitfall 11 (pinning transient Clarabel-flake
jitter as a golden — repeated-run stability check before committing).

### Phase Ordering Rationale

- **Dependency graph, not effort, drives the order.** Phases 1 and 2 are code-independent of each
  other and of 3/4, so they could in principle run in parallel — sequenced 1-then-2 here because
  Phase 2 is the more invasive change (touches an already-shipped, cross-validated path) and its own
  goldens need re-validation before anything else builds on `admm/`.
- **Phase 3 is data-engineering, gated on Phase 1/2 existing for its OWN validation**, not for its
  code — the real-data fixture's acceptance criteria (still voltage-binding? still SOC-exact?) is
  most rigorously checked using the Phase 1 AC oracle and Phase 2 reactive pricing.
- **Phase 4 is strictly last** — it is the only phase with a genuine code/data dependency on prior
  phases (needs real impedances from 3 and reactive pricing from 2 for the reproduction to
  credibly track the thesis's voltage-driven mechanism).
- **Every phase's own acceptance criteria must include the cross-cutting Pitfall 12 checklist**
  (positive-mechanism test — not just "it runs"; full `docs/make.jl` build checked, not just
  `Pkg.test()`; constant/offset reconciliation for any new algebraic doc narration) — this is a
  standing item across all four phases, not owned by any single one.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (AC-OPF oracle):** the angle-recovery formula for the radial network (SOCP is
  magnitude-only; the AC oracle needs real voltage phasors) needs to be worked out and validated on
  a trivial fixture before trusting it on IEEE-13/123 — this is genuinely new math for the codebase.
- **Phase 3 (real IEEE-123 impedances):** the PMD `ENGINEERING` dict traversal (`eng["line"]`/
  `eng["linecode"]`), the exact length/units convention resolution, and per-component-type
  (regulator/capacitor/switch) handling decisions are all new integration surface with a
  well-documented but non-trivial community trap (the classic feet-vs-miles rescale).
- **Phase 2 (reactive consensus):** whether a shared `rho` is adequate for the joint (p,q) residual
  balancing, or whether a distinct `rho_q` is needed, is a genuine open judgment call (MEDIUM
  confidence per ARCHITECTURE) that should be empirically resolved, not assumed.

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 4 (directional reproduction):** reuses the v2.0 literate-rung + gate-then-golden pattern
  verbatim (Rung 6/7, PVAL-02) — no new mechanism, just applying an established convention to a new case.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All version numbers verified against Julia General registry `Versions.toml`/`Deps.toml`/`Compat.toml`; PMD's dropped `PowerModels`/`Memento` deps confirmed directly. Zero new main deps to track. |
| Features | MEDIUM-HIGH | SOCP exactness theory and DLMP decomposition are HIGH confidence (canonical, well-cited literature: Farivar-Low, Gan-Li-Topcu-Low, Bhattacharya et al.). The positive-sequence reduction recipe is HIGH confidence, already numerically verified in this repo's own memory notes. The "directional reproduction" convention is MEDIUM confidence — a methodological norm, not a single citable theorem. |
| Architecture | HIGH | All four capabilities verified against actual source files (not summarized from docs); the "additive extension, not restructuring" conclusion is independently corroborated by direct code inspection across all researchers. |
| Pitfalls | HIGH (project-specific) / MEDIUM (domain-general) | HIGH confidence on the project's own code contracts (read directly: `exactness.jl`, `solve_admm.jl`, `AgrOpt.jl`, `DsoOpt.jl`, `ieee123.jl`, `factory.jl`) and the documented, accepted Clarabel flake. MEDIUM on IEEE-123 length/units ambiguity and reduction fidelity — public community knowledge, not independently re-verified against the live dataset this session. |

**Overall confidence:** HIGH — this is an unusually well-converged research set: all four
researchers independently arrived at the same "additive extension of existing seams" architectural
conclusion, the same 4-phase dependency ordering, and flagged the same cross-cutting risks (the `mu`
naming collision, the genuine-vs-artifact inexactness distinction, silent golden re-pinning).

### Gaps to Address

- **PMD `ENGINEERING` dict traversal specifics** (exact `eng["line"]`/`eng["linecode"]` field
  shapes, `Redirect`/`Compile` directive following) were verified against official docs, not
  against a live parse this session — treat as MEDIUM confidence, verify by actually running the
  parse early in Phase 3.
- **Whether reactive consensus needs its own `rho_q` or can share the active block's `rho`** is an open
  judgment call (ARCHITECTURE flags MEDIUM confidence) — resolve empirically in Phase 2, not by
  assumption.
- **Whether the real-impedance IEEE-123 case remains voltage-binding** after the impedance swap is
  unverified (no real impedance data exists yet to test against) — Phase 3's acceptance criteria
  must include an explicit binding-constraint check and be prepared to re-tune the aggregator/PV
  population if the property doesn't transfer.
- **Exact theorem wording for Gan-Li-Topcu-Low's checkable exactness condition** should be verified
  against the source PDF before citing a numbered theorem in any thesis-chapter-grade writeup
  (FEATURES flags this as MEDIUM-HIGH, not HIGH, confidence).

## Sources

### Primary (HIGH confidence)
- Julia General registry `Versions.toml`/`Deps.toml`/`Compat.toml` (JuMP 1.30.1, Ipopt 1.15.0,
  PowerModelsDistribution 0.16.0 and its dependency graph) — fetched 2026-07-25.
- Direct source inspection: `src/models/exactness.jl`, `src/models/welfare_solve.jl`,
  `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`, `src/admm/residuals.jl`,
  `src/data/ieee123.jl`, `src/experiments/Scenario.jl`, `src/solver/factory.jl`,
  `src/solver/ProblemClass.jl`, `src/TSODSO.jl`, `docs/make.jl`, `.planning/STATE.md`,
  `.planning/PROJECT.md`.
- PowerModelsDistribution official docs (`parse_file`/`transform_data_model` behavior,
  `ENGINEERING` `line`/`linecode` fields) — HIGH confidence.

### Secondary (MEDIUM-HIGH confidence)
- Farivar, M. & Low, S.H., "Branch Flow Model: Relaxations and Convexification," IEEE Trans. Power
  Systems 28(3), 2013 — canonical SOCP exactness theory.
- Gan, Li, Topcu & Low, "Exact Convex Relaxation of Optimal Power Flow in Radial Networks," IEEE
  Trans. Automatic Control 60(1), 2015 — empirically verifies IEEE 13/34/37/123-bus feeders.
- Bhattacharya et al., "Distribution Locational Marginal Pricing for Congestion Management and
  Voltage Support," IEEE Trans. Smart Grid 2018 — 5-way DLMP decomposition including reactive price.
- `memory/ieee123-real-impedances-source.md` (project's own prior research) — Fortescue-averaging
  recipe already numerically verified on linecode.1.

### Tertiary (MEDIUM confidence)
- ACM Artifact Review and Badging terminology ("Reproduced" vs. "Replicated") — closest formal
  analogue for the directional-reproduction framing, not a power-systems-specific standard.
- IEEE-123/OpenDSS community knowledge on the length/units ambiguity — well-documented community
  trap, not independently re-verified against the live dataset this session.

---
*Research completed: 2026-07-25*
*Ready for roadmap: yes*
