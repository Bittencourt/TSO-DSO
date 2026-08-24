# Phase 23: Meshed Networks - Context

**Gathered:** 2026-08-10
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all three grey-area tables accepted as recommended

<domain>
## Phase Boundary

Fill the SEAM-01 meshed-formulation slot: a `MeshedFeeder` loop-carrying data type alongside the
radial `Feeder`, a `MeshedFlow <: AbstractPowerFlow` SOCP branch-flow formulation with explicit
cycle/loop consistency, a NEW angle-recoverability a-posteriori certificate (Gan–Low condition,
report-don't-throw, unrecoverable ⇒ SOCP value reported as a valid lower bound — a first-class
finding), and one live literate rung page combining the meshed formulation with Phase 19's 4Q-BESS
reactive price. Requirements: MESH-01, MESH-02, MESH-03, MESH-06. Depends on Phase 19 (4Q-BESS +
live reactive) and Phase 20 (restriction/AC-certificate pattern reused, never a divergent
certification strategy). Highest math risk in the milestone.

**Standing user flag (resolved by decision below):** the non-radial formulation choice
(cycle-basis signed incidence vs bus-injection/line-flow with loop constraints) is new model-math
flagged in STATE.md as needing its own theory research pass before planning. The user chose to
proceed autonomously WITH that deep research pass (D-03), and explicitly approved an HONEST-GAP
outcome (D-10): if the meshed fixture shows a structural relaxation gap, the certificate reporting
"unrecoverable; SOCP = valid lower bound" IS the rung's deliverable. Clear the STATE.md Phase-23
blocker entry once research resolves the formulation.

</domain>

<decisions>
## Implementation Decisions

### Meshed Data Type & Formulation Scope
- **D-01:** `MeshedFeeder` is a **separate struct alongside** the radial `Feeder` — `assert_radial`
  and every radial code path byte-untouched (MESH-01 locked). Shared helpers by composition only
  where free.
- **D-02:** Committed fixture: **smallest honest loop fixture** (3–4 bus, single loop) as the CI
  substrate; a meshed-IEEE-13-with-tie-switch variant only as literate/quarantined evidence.
- **D-03:** **The theory research pass decides the formulation** (cycle-basis signed incidence vs
  bus-injection/line-flow with loop constraints), with literature (Gan–Low meshed/OPF-m results,
  Bose et al. exactness conditions, Farivar–Low). Hard constraint locked by ROADMAP: explicit
  cycle/loop consistency — never the radial Baran–Wu variables alone.
- **D-04:** **No meshed ADMM this rung.** Centralized meshed SOCP + certificate satisfy the
  criteria; the literate page shows the 4Q-BESS reactive price on the meshed fixture via
  centralized `:balance_q` duals and references Phase 19's live μ-ascent (radial). Meshed
  decomposition is a later rung.

### Angle-Recoverability Certificate (MESH-03)
- **D-05:** New named exported certificate, **report-by-default** with an opt-in strict/throw
  kwarg — a deliberate, documented divergence from the family's throw-by-default because
  "unrecoverable" is a first-class scientific finding per MESH-03's own wording.
- **D-06:** The check is **angle recoverability per the Gan–Low condition**: cycle-consistency of
  the angle differences implied by the SOCP solution around every independent loop (exact math per
  the research pass). Never the per-branch cone residual alone (structurally blind to loop
  inconsistency — banned by MESH-03).
- **D-07:** Unrecoverable output: SOCP objective reported as a **valid lower bound**, with a
  structural status field (Phase-20 `price_provenance` precedent) and the inexactness stated as a
  finding. Recoverable output: recovered angles returned + certified.
- **D-08:** Tolerances **measured on the committed meshed fixture at its own scale**, docstring
  provenance table — never reused from sibling certificates (Phase-19 CR-01 lesson).

### Scope Guards & Evidence
- **D-09:** CI regression asserting radial behavior unchanged (radial goldens byte-identical;
  `assert_radial` untouched).
- **D-10:** **Honest-gap outcome allowed as the deliverable** (user-approved): a structural gap on
  the meshed fixture ships as the certificate's honest "unrecoverable / lower bound" finding —
  Pitfall 15 respected, no knife-edge fixture tuning to force exactness.
- **D-11:** **Anti-feature honored:** no IEEE-1547 Volt-VAR droop controller anywhere; optimal
  q(v) behavior characterized post-hoc ONLY if it falls out of solved results for free.
- **D-12:** Evidence split: small loop fixture CI-gated; meshed-IEEE variant and anything heavy
  quarantined/literate (Phase 19-22 precedent).

### Claude's Discretion
- All names (MeshedFeeder fields, MeshedFlow, certificate function, status symbols).
- Exact loop-fixture topology/parameters (subject to D-02's smallest-honest-loop bar).
- Angle-recovery algorithm details (BFS spanning tree + cycle closure check, or research's
  recommendation), provided D-06's condition is what is checked.
- Whether the 4Q-BESS lands on the loop fixture or the quarantined meshed-IEEE variant for the
  literate page's reactive-price demonstration.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- src/powerflow/AbstractPowerFlow.jl — the `pf` dispatch seam (MESH-02's insertion point);
  ACPowerFlow (v2.1) and RestrictedBranchFlow (Phase 20) are the precedents for adding types.
- src/powerflow/ConvexBranchFlow.jl — the radial SOCP the meshed formulation generalizes; its
  named-container collision lesson (JuMP.unregister, Phase 22) applies to any multi-block build.
- src/data/ (Feeder, topology.jl assert_radial) — the radial data layer MeshedFeeder sits beside.
- src/models/ac_oracle.jl — `recover_voltage_angles` (Baran–Wu BFS, v2.1) is the radial
  angle-recovery precedent the meshed certificate generalizes WITH the cycle-closure check;
  `recover_lossfree_shadow_voltage` (Phase 20) shows the branch-orientation-safe traversal idiom
  (signed branch index — CR-01 lesson: never assume parent→child orientation).
- src/models/restriction_exactness.jl — Phase-20 certificate pattern (provenance, measured
  tolerances, status field) MESH-03 reuses rather than diverging from.
- FourQuadBESS + Aggregator q_inject (Phase 19) — the reactive-price demonstration devices.
- Literate pattern: docs/literate/stochastic_pv_demand.jl (Rung 9) freshest example.

### Established Patterns
- Formulation-per-type dispatch; solver via select_optimizer(problem_class(pf)); solve_with_retry!.
- Certificate family discipline (measured tolerances, provenance docstrings, status fields).
- Quarantine split; api.md checkdocs wiring for every export.

### Integration Points
- solve_welfare's pf dispatch (or a meshed sibling entry if solve_welfare assumes radial Feeder —
  research must determine how deep the radial assumption runs in welfare_solve/devices/aggregator).
- docs/make.jl + api.md.

### Testing constraints (Phases 19-22 lessons — MANDATORY for plans)
- Plans' <verify> blocks: direct Julia/Test.jl scripts under `--project=.` ONLY; never
  TestItemRunner there; full suite only in the final acceptance plan
  (`julia --project=. -e 'import Pkg; Pkg.test()'`, ~12-20 min, background).
- Green reference after Phase 22 fixes: 2752 passed / 0 failed / 3 pre-existing intermittent
  Clarabel errored / 3 broken (+2 known-false Aqua on the drifted main checkout; the D-06
  stochastic test may fail-with-diagnostics under sandbox version skew — documented, not a
  regression).
- Keep the CI loop fixture SMALL; measure Clarabel capacity before pinning fixture sizes.

</code_context>

<specifics>
## Specific Ideas

- The certificate's two-sided honesty is the phase's heart: recovered angles must be VERIFIED
  (plug back into the loop-closure condition), and the unrecoverable branch must state the lower
  bound explicitly — mirroring how v2.1 shipped the radial inexactness as a citable finding.
- welfare_solve's radial assumptions (topology traversal, balance construction) must be audited by
  research BEFORE planning: if devices/aggregators are topology-agnostic (they should be — they
  couple only through :Rp/:Rq at buses), the meshed formulation slots in via contribute! alone.
- Clear the STATE.md Blockers/Concerns Phase-23 entry when research resolves the formulation.

</specifics>

<deferred>
## Deferred Ideas

- Meshed ADMM / decomposed meshed pricing — later rung (D-04).
- IEEE-1547 Volt-VAR droop controller — permanent anti-feature per MESH-06.
- Multi-loop / N-1 switching topologies — beyond the single-loop rung.
- Meshed planning-layer (Benders) integration — later milestone.

</deferred>
