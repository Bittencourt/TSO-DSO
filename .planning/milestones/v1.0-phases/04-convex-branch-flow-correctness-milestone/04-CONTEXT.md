# Phase 4: Convex Branch-Flow Correctness Milestone - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Auto-generated (correctness-keystone modeling phase — decisions determined by source thesis; discuss skipped)

<domain>
## Phase Boundary

The **"if all else fails, this must work"** core: the **SOCP Convex Branch Flow** formulation *with
the LinDistFlow exactness copy* (aux `v̂` + affine voltage bounds), all Phase-3 devices, and the
GLB-CVX social welfare, proven **exact** on the **modified IEEE 13-node feeder** as centralized
ground truth — reproducing the thesis DADP/voltage numbers. Plus the `operational_oracle(z) →
(cost, π)` seam and the SEAM-01 extension stubs so the planning layer (Phase 8/9 and beyond) is
purely additive later.

In scope: PF-03 (SOCP branch flow + exactness copy), PF-04 (automated exactness invariant),
OPT-02/OPT-03 (monolithic solve reproducing thesis ground truth), DATA-03 (modified IEEE 13-node
feeder fixture), SEAM-01 (operational_oracle + extension interface stubs). Out of scope:
ADMM/decomposition (Phase 6+), the planning/Stackelberg-Nash layer itself (later milestone).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to source thesis + Phases 1–3 seams)
No user-preference grey areas — the formulation, the exactness copy, and the ground-truth numbers
all come from the thesis. Anchor to:

- **SOCP branch flow (PF-03):** a new concrete `AbstractPowerFlow` subtype implementing the DistFlow
  SOC relaxation — branch active/reactive flows `P_ij/Q_ij`, squared-current `l_ij`, squared-voltage
  `v_i`, the SOC cone `l_ij·v_i ≥ P_ij² + Q_ij²` (rotated-SOC in JuMP), the voltage-drop and
  active/reactive balance recursions — traced to the thesis equations (3.31–3.45). It plugs into the
  Phase-1/2 residual seam via `contribute!` (dispatch, no branching), interchangeable with DC and
  LinDistFlow.
- **LinDistFlow exactness copy (PF-03):** the aux `v̂` + affine voltage bounds trick (the LinDistFlow
  copy alongside the SOC model) that makes the SOC relaxation **exact** on radial feeders. Written
  explicitly as part of the model definition, toggled per the thesis.
- **Exactness invariant (PF-04):** an automated post-solve assertion `max|l·v − (P²+Q²)| < τ` per
  branch. It runs on BOTH an easy fixture AND a high-PV / over-voltage fixture. **Prices (DADPs) are
  REFUSED (error) if exactness fails** — a non-exact relaxation gives meaningless duals. This is the
  headline correctness gate of the whole project.
- **Ground truth (OPT-02/OPT-03):** the centralized monolithic solve must reproduce the thesis
  DADP/voltage numbers (e.g. `v₉[16] ≈ 1.0493`) on the modified IEEE 13-node feeder, with the nodal
  active-balance dual available. These numbers are the regression anchor for every later rung.
- **Solver:** SOCP + convex QP objective → `select_optimizer(SOCP())` (or the existing conic class) →
  **Clarabel** (native SOC + quadratic, accurate duals — prices ARE duals). RE-VERIFY the Clarabel
  API specifics flagged in STATE/CLAUDE.md at phase start (quadratic-objective attribute names, JuMP
  `Parameter` surface, and that Clarabel is copy_to-only so `direct_model` is NOT used with it — the
  Phase-1 research already corrected this; confirm). No model names a concrete solver.
- **operational_oracle + SEAM-01:** `operational_oracle(z) → (cost, π)` returns the frontier coupling
  dual; the extension interfaces exist as STUBS (multi-scenario objective hook, rolling-horizon
  parameter, meshed-formulation slot, coupling-flow interface `z↔p_ag`, `λ_j↔π_s`, with an explicit
  leader/follower role parameter). Stubs only — the planning layer is additive later.
- **Data (DATA-03):** the modified IEEE 13-node feeder as immutable JuMP-free structs (Phase-1
  `Feeder`), radial-validated, per-unit-converted-once, matching the thesis modification.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–3)
- `src/powerflow/{AbstractPowerFlow,DCPowerFlow,LinDistFlow}.jl` — the contract + the two linear
  formulations the SOCP joins as a third interchangeable subtype.
- `src/models/welfare_solve.jl` — the GLB-CVX assembly to run on the SOCP formulation (the SOCP is a
  drop-in `pf`); `src/models/linear_solve.jl` for reference.
- `src/core/ModelContext.jl` (residual + objective accumulators), `src/core/status.jl`
  (`assert_solved!`), `src/solver/factory.jl` + `ProblemClass.jl` (add/confirm an SOCP/conic class →
  Clarabel), `src/devices/*` (the full device library + Aggregator), `src/data/Feeder.jl`,
  `src/units/PerUnit.jl`, `src/data/profiles.jl`.

### Established Patterns
- Immutable structs; SparseArrays; dispatch-not-branching formulations; concave-utility→objective;
  `assert_solved!` gating; TestItems `@testitem` (name contains filter substring); throw-based
  validation; committed version-specific manifests; every constraint cites a thesis equation.

### Integration Points
- New `src/powerflow/` SOCP formulation + exactness copy; a `src/models/` exactness-invariant check
  (PF-04) callable after any SOCP solve; the modified IEEE-13 feeder fixture (test fixture / data
  loader); `operational_oracle` + SEAM-01 stub interfaces.

</code_context>

<specifics>
## Specific Ideas

Pull the SOCP branch-flow + LinDistFlow-exactness-copy equations (3.31–3.45), the modified IEEE
13-node feeder parameters, and the thesis DADP/voltage ground-truth numbers (v₉[16] ≈ 1.0493 and any
companion values) from the thesis reference material in `.planning/research/THEORY-thesis.md` /
`docs/references/` during research. Cross-validate the SOCP power flows/voltages against a PMD/PM
oracle on a no-DER baseline if feasible (CLAUDE.md validation strategy). RE-VERIFY Clarabel SOCP +
quadratic-objective + Parameter APIs live (the STATE Phase-4 blocker).

</specifics>

<deferred>
## Deferred Ideas

- ADMM decomposition of the operational solve → Phase 6.
- The actual planning / Stackelberg-Nash equilibrium layer → later milestone (only the additive SEAM-01
  stubs land here).
- Unbalanced 3-phase → out of scope for v1 entirely.

</deferred>
