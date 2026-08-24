# Phase 20: Overvoltage-Capable Relaxation - Context

**Gathered:** 2026-08-08
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all three grey-area tables accepted as recommended

<domain>
## Phase Boundary

Price the high-PV overvoltage regime that v2.1's AC oracle proved the plain SOCP relaxation cannot
solve exactly (EXACT-04, IEEE-13 `pv_scale=1.2`), keeping the "prices are duals of one convex
problem" story intact via a **feasible-set restriction** (never a heuristic penalty). Delivers: a
restricted-SOCP formulation variant dispatched through the existing `solve_welfare` path, a new
AC-certified validity certificate reporting optimality loss, a documented nonconvex-AC-dual
fallback (reported, never thrown), and a live-executed literate rung page. Requirements:
OVR-01..OVR-04.

**Standing user flag (resolved by decision below):** the exact convexification mechanism was
flagged in STATE.md as unresolved model-math requiring its own theory research pass before
planning. The user chose to proceed autonomously WITH that deep research pass — the plan-phase
researcher must resolve it (D-01) before plans are written.

</domain>

<decisions>
## Implementation Decisions

### Restriction Mechanism & Dispatch
- **D-01:** The **theory research pass decides the mechanism** among feasible-set-restriction
  candidates, with the Gan–Low-style reverse-flow-aware `V²max` shrink as the primary candidate.
  Hard constraint (locked by ROADMAP): it must be a *restriction* of the feasible set that
  guarantees AC-feasibility of the returned point — McCormick valid inequalities and PSD-style
  tightenings are relaxation *tightenings* (still upper bounds, no feasibility guarantee) and may
  appear only as documented rejected alternatives in the research/literate page.
- **D-02:** Dispatch as a **new formulation type** (e.g. `RestrictedBranchFlow <: AbstractPowerFlow`,
  final name at Claude's discretion) through the existing `solve_welfare` seam — exact `ACPowerFlow`
  v2.1 precedent (src/powerflow/ has AbstractPowerFlow + DC/LinDist/ConvexBranchFlow/AC concrete types).
- **D-03:** Restriction parameter (e.g. shrink amount) is a **researcher-supplied kwarg with a
  measured default** derived on the EXACT-04 fixture; the certificate validates the choice. No
  auto-tuning/bisection loop in this rung (minimal-validated-rung discipline).
- **D-04:** **IEEE-13 `pv_scale=1.2` (EXACT-04) is the CI-gated primary evidence**; IEEE-123
  overvoltage band is quarantined supporting evidence — mirrors Phase 19's D-13 quarantine pattern.

### Certificate & Pricing Semantics
- **D-05:** **One** new named, exported certificate (peer of `assert_socp_exact!` /
  `assert_ac_exact!` in the same family) that both certifies the restricted solution AC-feasible
  via the existing AC oracle AND reports the optimality loss vs the unrestricted (inexact) SOCP
  bound.
- **D-06:** **Throw by default, `report` kwarg to neutralize** — Phase 19 D-06 precedent,
  consistent certificate-family behavior.
- **D-07:** **Tolerances measured on the actual EXACT-04 fixture at its own scale**, derivation
  documented in the docstring. Never reuse another certificate's numbers (binding
  measurement-hygiene bar; Phase-19 CR-01 lesson: defaults derived at the wrong scale silently gut
  the gate).
- **D-08:** Restricted-regime DADPs use the **same result surface as normal solves plus an explicit
  provenance marker** (result field naming the formulation + certificate status) so downstream
  consumers can programmatically distinguish restricted-duals from plain-SOCP duals.

### Fallback & Evidence
- **D-09:** The nonconvex-AC-dual fallback **triggers only on certificate failure** of the
  restricted SOCP — never silently, never pre-emptively.
- **D-10:** Fallback prices carry a **structural status field** (e.g. `price_status = :local_ac_dual`)
  plus the documented local-optimum / not-market-clearing caveat — programmatically
  distinguishable, and *reported, never thrown*.
- **D-11:** **Multi-start evidence: 3–5 seeded Ipopt starts with an agreement report**; CI gates a
  cheap 2-start version, the fuller sweep is quarantined (Phase 19 quarantine pattern).
- **D-12:** **One live-executed literate rung page** covering the restriction mechanism beside the
  Gan & Low condition it implements, the measured optimality loss, and the fallback semantics —
  v2.1 literate-page pattern.

### Claude's Discretion
- Final names of the formulation type, certificate function, kwargs, and status symbols.
- Internal math plumbing of the restriction (which constraints are modified, where the shrink
  enters the branch-flow equations) — subject to D-01's research resolution.
- Exact seed count within the 3–5 multi-start band and the cheap-CI subset.
- Whether the optimality-loss report needs its own small result struct or plain named fields.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/powerflow/AbstractPowerFlow.jl` — the formulation seam (`abstract type AbstractPowerFlow`,
  `contribute!` contract); `ACPowerFlow` (v2.1) is the precedent for adding a formulation type.
- `src/powerflow/ConvexBranchFlow.jl` — the SOCP branch-flow the restriction modifies/extends.
- `src/models/ac_oracle.jl` + `assert_ac_exact!` — the existing AC oracle the new certificate
  re-uses for feasibility certification.
- `src/models/exactness.jl` — `assert_socp_exact!` certificate pattern (structure, throw/report,
  docstring tolerance-derivation style).
- `src/models/welfare_solve.jl` — the `solve_welfare` dispatch path the variant flows through.
- EXACT-04 stress fixture (IEEE-13 `pv_scale=1.2`) from v2.1 — the proven-inexact operating point.

### Established Patterns
- Certificate family: named, exported, throw-by-default + `report` kwarg, measured tolerances with
  docstring provenance tables (Phase 19 `assert_4q_complementarity!` is the freshest example).
- Quarantined expensive evidence vs CI-gated cheap evidence (Phase 19 D-13 / 19-08).
- Formulation-per-type dispatch, never formulation-by-kwarg.

### Integration Points
- `solve_welfare(...; power_flow=<new type>)` (or equivalent seam) — main entry.
- DADP extraction path must carry the provenance marker (D-08) without breaking existing consumers.
- Literate docs: docs/ Literate pages, v2.1 rung-page structure.

### Testing constraints (from Phase 19 execution)
- Plans' `<verify>` blocks must NOT use TestItemRunner under `--project=.` (test-only dep) — use
  direct Julia/Test.jl scripts + `Pkg.precompile()`; full suite via
  `julia --project=. -e 'import Pkg; Pkg.test()'` (~12–20 min, background).
- Full-suite green reference after Phase 19: 2513 passed / 0 failed / 3 pre-existing broken (plus
  2 known-false Aqua artifacts on the drifted main checkout only).

</code_context>

<specifics>
## Specific Ideas

- The restriction must keep the thesis narrative intact: "prices are duals of ONE convex problem."
  Any mechanism that cannot state its restricted problem as a single convex program violates the
  phase goal.
- The literate page should explicitly show the Gan & Low condition and where the implemented
  restriction sits relative to it (OVR-04 wording).
- STATE.md's Blockers/Concerns entry for this flag should be cleared once the research pass
  resolves the mechanism.

</specifics>

<deferred>
## Deferred Ideas

- Researcher opt-in kwarg to force the AC-dual fallback without certificate failure (Area 3 Q1
  alternative) — defer until a use case appears.
- Automatic restriction-parameter tuning (bisection-until-certified) — explicitly out of this rung.
- IEEE-123 overvoltage band as CI-gated (kept quarantined this phase).

</deferred>
