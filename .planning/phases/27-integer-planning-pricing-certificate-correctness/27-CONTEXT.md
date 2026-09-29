# Phase 27: Integer Planning & Pricing Certificate Correctness - Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the integer Benders recourse correct for T>1 (FIX-06), name DLMP components after what they
mathematically are (FIX-07), give the SOCP exactness gate a per-branch relative floor (FIX-08),
certify the FIT-baseline counterfactual and root-cause the `ALMOST_OPTIMAL` flake (FIX-09), and
settle MPC realized welfare/regret against the true plant (FIX-10). Every moved golden re-derived
in-phase; suite green at close. Thesis-reproduction restatement is Phase 28.

</domain>

<decisions>
## Implementation Decisions

### corner_recourse T>1 — FIX-06
- IMPLEMENT the true T>1 recourse `Q(y) = min_{z∈[0,y]^T} [follower_cost(z) − oracle_welfare(z)]`
  as a genuine joint convex minimization (not per-hour-independent unless proven separable, not
  `fill(z,T)`); Phase 30's multi-bus Benders will need T>1.
- Validation oracle: exhaustive grid enumeration on a small T=2 fixture; the Laporte–Louveaux loop
  must match its optimum (and cuts) within a MEASURED tolerance.
- Remove the scalar `fill(z,T)` path; T=1 must stay byte-identical (the joint minimization reduces
  to the existing ternary search at T=1).

### DLMP component naming — FIX-07
- Rename components after their multipliers: `cone` (rotated-SOC cone-slot multiplier) and `drop`
  (voltage-drop / copy-drop multipliers); `congestion` and `energy` unchanged.
- Keep `loss`/`voltage` as DEPRECATED aliases (one-time deprecation warning), removal scheduled for
  Phase 36 (Code & Export Cleanup).
- Replace the "voltage component ≈ 0 when unbinding" test with correct properties on a
  realistic-impedance fixture (IEEE-13 slice): exact sum-to-price identity, and each component is
  zero iff its multiplier is zero.

### Per-branch exactness floor — FIX-08
- Per-branch absolute floor `atol_b = ε·ref_b` with `ref_b = S̄_b²` for thermally limited branches,
  else the head-branch flow magnitude; replaces the global `atol = 1e-6`.
- ε MEASURED on the canonical fixtures: the largest ε that flags the new synthetic slack-cone test
  while all genuinely-exact fixtures pass; measurement recorded.
- Any fixture newly flagged inexact is a FINDING: triage it and ESCALATE to the user before any
  relaxation — never raise ε to hide it.

### FIT certificate + MPC settlement — FIX-09/10
- FIT baseline: assert exactness by default (throw on inexact); opt-in `on_inexact=:report` returns
  the certificate in the result. Never skip.
- `ALMOST_OPTIMAL` flake at `tol_gap=1e-10`: root-cause first; if solver-intrinsic, explicitly
  bound it (accept ALMOST_OPTIMAL only with a certified gap under a documented tolerance).
- MPC truth plant: realized PV clips charging, settlement uses true import, and true-state
  propagation THROWS on an SOC bound violation; the forecast-settled number survives only as a
  clearly labelled `forecast_settled_welfare` diagnostic.

### Golden policy + process (SC-6, lessons from Phase 26)
- Same as Phase 26: every moved golden re-pinned in-phase with old→new + cause comment and a
  GOLDEN-AUDIT table; no silent re-pin.
- Run a full post-merge suite AFTER EACH WAVE (not only at phase end) and triage by root cause
  before the next wave — Phase 26 found 55 downstream failures only at the end.
- Executors in parallel worktrees never edit STATE.md/ROADMAP.md; findings go to 27-FINDINGS.md.
- Machine limit: ≤3 concurrent Julia executors (4 cores / 15 GB).

### Claude's Discretion
- Exact joint-minimization algorithm for T>1 (single JuMP model vs. projected descent), exact
  new DLMP field names' spelling, ε measurement protocol details.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/benders.jl` `corner_recourse` (ternary search, WR-01 tie-break, CR-01 zero-corner);
  `test/test_planning_certification_integer.jl` `enumerate_lattice` reference implementation.
- `src/pricing/dlmp.jl` `decompose_dlmp` (now also reads `:smax_rev`, Phase 26 26-10).
- `src/models/exactness.jl` `assert_socp_exact!(ctx; rtol=1e-4, atol=1e-6)`.
- `src/pricing/fit.jl` `fit_baseline`; `src/experiments/mpc_loop.jl` `run_mpc` realized/regret.

### Established Patterns
- Thesis-equation-number comments on every constraint; `throw(ArgumentError(...))` guards.
- Per-fixture Clarabel `tol_gap` via `select_optimizer(SOCP(); tol_gap_abs, tol_gap_rel)`.
- Direct `julia --project=.` verify scripts (TestItemRunner does not resolve under --project=.).

### Integration Points
- Phase 26 changed exactness-copy direction, added `:smax_rev`, soc[1:T+1], flexible-load q —
  goldens already re-pinned against those; FIX-08 floor change will interact with Phase 26's
  per-fixture tol_gap calibrations.

</code_context>

<specifics>
## Specific Ideas

- Phase 26 findings in `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md`
  (App. C η<1, Gan–Low restriction) are context, not scope.

</specifics>

<deferred>
## Deferred Ideas

- Removal of deprecated DLMP aliases — Phase 36.
- App. C η<1 complementarity treatment — unscheduled backlog (Phase 26 finding).

</deferred>
