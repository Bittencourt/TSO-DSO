# Phase 5: Distribution Pricing — DADP & DLMP Decomposition - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Auto-generated (pricing-analysis phase — decisions determined by source thesis; discuss skipped)

<domain>
## Phase Boundary

Extract and validate the **day-ahead dynamic price (DADP/DLMP)** as the dual of the nodal
active-power balance, **decompose** it into interpretable components (energy / loss / congestion /
voltage), and produce the **welfare accounting** (social / DSO / prosumer surplus with a FIT baseline)
that reproduces the headline research result (the +25%-social-welfare number). A small, cheap phase
depending only on the rung-2 (Phase-4 SOCP) duals — mostly post-processing of the solve output.

In scope: PRICE-01 (DADP/DLMP extraction as the nodal-balance dual, per node per hour, sign-verified),
PRICE-02 (DLMP decomposition into energy/loss/congestion/voltage summing to the nodal price),
PRICE-03 (welfare accounting: social/DSO/prosumer surplus, FIT baseline, +25% headline),
PRICE-04 (economic-direction checks: price below wholesale at PV glut, above at congestion). Out of
scope: ADMM (Phase 6+), the experiment harness (Phase 8), the planning layer (later milestone).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (anchored to source thesis + Phase 4 duals)
No user-preference grey areas — the DLMP decomposition, welfare split, and FIT baseline all come from
the thesis. Anchor to:

- **DADP/DLMP extraction (PRICE-01):** the dual of the nodal active-power balance constraint
  (`dual(balance_p[node,t])`) that `welfare_solve` already exposes — per node per hour. Sign verified
  against a hand-solved 2-bus example (positive = marginal cost of consumption at that node/hour).
- **DLMP decomposition (PRICE-02):** decompose the nodal price into **energy + loss + congestion +
  voltage** components (from the duals of the corresponding constraints / KKT terms per the thesis),
  asserting the components SUM to the nodal price with correct sign. This is a post-solve computation
  reading the model's duals.
- **Welfare accounting (PRICE-03):** split total welfare into **social / DSO / prosumer surplus** with
  a **FIT (feed-in-tariff) baseline** counterfactual, reproducing the +25%-social-welfare headline
  (as a RATIO vs the FIT baseline — likely more robust than absolute numbers, which may be
  figure-bound like Phase 4's welfare). Pin a computed value + cross-check the thesis ratio.
- **Economic-direction checks (PRICE-04):** assert the price falls BELOW wholesale (λ₀) at PV glut and
  rises ABOVE it at congestion — the qualitative economic-correctness sanity checks.
- **Solver/status discipline (CLAUDE.md):** read duals only after `assert_solved!`/exactness gate;
  the SOCP exactness gate (PF-04) must have passed before any DLMP is trusted (prices refused if not).

### Reuse
This phase is post-processing over `solve_welfare`/`operational_oracle` output — a new pricing module
consuming `ctx.meta` duals/vars, not a new optimization model. Prefer functions over new solves.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (Phases 1–4)
- `src/models/welfare_solve.jl` — exposes `dual(balance_p[...])` (the DADP) and the exactness gate;
  the pricing module reads its output. `src/models/oracle.jl` — `operational_oracle(z)→(cost,π,dadp,ctx)`.
- `src/models/exactness.jl` — `assert_socp_exact!` (prices only trusted when exact).
- `src/powerflow/ConvexBranchFlow.jl` — the SOCP whose branch/voltage duals feed the loss/congestion/
  voltage decomposition; `pf_vars=(;v,v̂,P,Q,l)`.
- `src/core/ModelContext.jl` (`ctx.meta`, residual registry), `src/data/ieee13.jl` (ground-truth
  feeder), `src/data/profiles.jl` (PV-glut / congestion scenario profiles), `src/devices/*`.

### Established Patterns
- Post-solve assertions; throw-on-violation; TestItems `@testitem` (name contains filter substring);
  every formula cites a thesis equation; computed-golden + thesis-ratio cross-check (Phase-4 pattern).

### Integration Points
- New `src/pricing/` (or `src/models/`) module: DLMP decomposition, welfare accounting, economic-direction
  checks — all consuming the Phase-4 solve output.

</code_context>

<specifics>
## Specific Ideas

Pull the DLMP component decomposition (energy/loss/congestion/voltage from the KKT/dual structure), the
welfare-split definitions (social/DSO/prosumer surplus, FIT baseline), and the +25% headline
methodology from the thesis reference material in `.planning/research/THEORY-thesis.md` /
`docs/references/` during research so every formula traces to a numbered source equation. Verify the
DADP sign against a hand-solved 2-bus example, and the decomposition-sums-to-price assertion. Note the
Phase-4 welfare-gap caveat: the +25% is likely a RATIO (more robust); pin a computed value + thesis
cross-check rather than a hard absolute match.

</specifics>

<deferred>
## Deferred Ideas

- ADMM decomposition → Phase 6.
- Experiment harness / scenario sweeps that USE these prices → Phase 8.
- Reconciling the absolute welfare gap (thesis figure digitization) → the Phase-4 follow-up item in STATE.

</deferred>
