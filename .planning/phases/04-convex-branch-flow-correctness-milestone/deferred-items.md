# Deferred / Out-of-Scope Items — Phase 04

## From plan 04-05 (PF-04 exactness gate)

### D-04-05-1: High-PV fixture cannot demonstrate "exact over-voltage" (design contradiction)

**Discovered during:** 04-05 Task 3 (high-PV exactness testitem).

**Finding:** With the PF-04 gate correctly implemented, the
`exact: high-PV / over-voltage SOCP solve stays exact` testitem cannot pass, because the
`Phase4Fixtures.build_high_pv_aggregators` fixture (`pv_scale = 50`, `load_scale = 0.2`,
tiny battery, on the 3-bus `high_pv_feeder`) does not yield an exact SOC relaxation under
`solve_welfare` — and no rescaling of it can simultaneously satisfy all the plan's claims.

Empirical sweep (ConvexBranchFlow + solve_welfare, frontier import-only per 03-05):

| pv_scale | reverse flow / over-voltage | SOC exactness `max|l·v−(P²+Q²)|` |
|----------|-----------------------------|----------------------------------|
| 0.3–1.8  | NONE (vmax = 1.0 pu, minP = 0) | EXACT (~1e-8) |
| 2.0–6.0  | onset of surplus             | INEXACT (~0.45–0.56) |
| 50 (fixture value) | surplus dumped into losses | INEXACT (~1.07) |

**Root cause (SOC relaxation theory):** exactness of the DistFlow SOC relaxation requires the
objective to be strictly increasing in branch current `l` (loss minimization). In a pure-surplus
regime with an import-only frontier (`p_import ≥ 0`, the 03-05 design), excess PV can only be shed
via line losses `−r·l` or PV curtailment (`pv_used`), which are welfare-equivalent once
`p_import` is pinned at 0. The objective is then indifferent to `l`, so the solver returns a
slack-cone (inexact) optimum. Enabling frontier export makes it worse: the free, **unpriced**
`q_import` lets reactive losses `−x·l` inflate `l` at no welfare cost, and voltages cap at V²max.

Critically: for this fixture the exact regime (pv ≤ ~1.8) has **no** reverse flow / over-voltage,
and the over-voltage/reverse-flow regime is **never** exact — so the fixture cannot exhibit
"exact over-voltage" as the test asserts. Reducing `pv_scale` to make the test green would produce
a test that no longer exercises the regime it documents (a hollow/stub pass — forbidden).

**Independent second blocker:** `solve_welfare`'s battery-complementarity check
(`value(p_ch)·value(p_dch) < τ`, default `τ = 1e-6`) fails at **every** scale on this SOCP solve
(product ~1e-4). Clarabel's interior-point conic accuracy is looser than the QP tolerance the
`1e-6` default was calibrated for (Phase-3 LinDistFlow/DC). The SOCP+battery combination is
exercised only by this testitem, so this was previously unseen.

**Candidate resolutions (need a design decision — owner: 04-02 formulation / 03-05 welfare / fixture):**
1. **Formulation review (most likely correct):** verify the 04-02 LinDistFlow exactness copy
   (thesis 3.43–3.45) against the source — in particular whether the **upper** voltage bound
   should be imposed on the linear copy `v̂` alone (Huang et al. 2017 exact-relaxation condition),
   rather than on both `v` and `v̂`. If the copy is corrected, the over-voltage regime may become
   exact as the plan assumes.
2. **Frontier / model:** give surplus a strictly-penalized sink (priced export, or a small explicit
   loss/curtailment penalty) so the objective is strictly increasing in `l`; and price/bound
   `q_import` so reactive losses cannot inflate `l` for free.
3. **Fixture + tolerances:** redesign `high_pv_feeder`/`build_high_pv_aggregators` to a feasible
   regime that genuinely produces mild over-voltage while staying inside the exactness domain, and
   loosen the SOCP battery-complementarity tolerance to match Clarabel's conic accuracy.

**Status of the gate itself:** `assert_socp_exact!` (Task 1) and its `solve_welfare` hook (Task 2)
are implemented, committed, and verified CORRECT — the gate faithfully refuses prices when the
relaxation is inexact (it is doing its job by catching this). The two self-contained exactness
testitems (throw-on-inexact, pass-on-exact) pass; `conformance`/`socp`/`welfare` suites are green.
