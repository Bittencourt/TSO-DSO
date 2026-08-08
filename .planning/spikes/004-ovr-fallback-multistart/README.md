---
spike: 004
name: ovr-fallback-multistart
type: standard
validates: "Given the EXACT-04 fixture's nonconvex-AC-dual fallback re-solved from 5 distinct seeded Ipopt starts, when costs/dadps are compared pairwise, then no local-optimum artifact is masking a genuinely unstable fallback price"
verdict: VALIDATED — no instability found; all 5 Ipopt convergence-strategy variants agree to ~1e-7
related: [001, 002, 003]
tags: [ovr, ac-dual-fallback, multi-start, ipopt]
---

# Spike 004: does `ac_dual_fallback_price`'s multi-start agreement hold at the full 5-seed sweep?

## Verdict

**VALIDATED.** All 5 `_FALLBACK_IPOPT_VARIANTS` Ipopt convergence-strategy starts converge to
the SAME local optimum on the EXACT-04 fixture (`Phase4Fixtures.high_pv_feeder()`,
`pv_scale = 1.2`), to within solver noise. No local-optimum artifact is masking a genuinely
unstable fallback price — the CI-gated 2-seed test's own agreement finding (plan 20-04's
seventh `@testitem`) generalizes cleanly to the fuller 5-seed sweep.

## How to Run

```bash
julia --project=. .planning/spikes/004-ovr-fallback-multistart/sweep.jl
```

Replicates the EXACT-04 fixture inline (per `CONVENTIONS.md`: `Phase4Fixtures` is a
TestItems `@testmodule`, unreachable from a plain script — the copy is verified against the
original's shape at the top of the run: 3 buses, 2 branches, 2 aggregators).

## Results

```
seed_variant | cost               | max |dadp - dadp[1]|
-------------|--------------------|---------------------
1 (default)                          | -922.9416693226153 | 0.0
2 (mu_strategy=adaptive)             | -922.9416689384499 | 1.0506617220684689e-7
3 (mu_strategy=monotone)             | -922.9416693226153 | 0.0
4 (nlp_scaling_method=none)          | -922.9416693226153 | 0.0
5 (adaptive + nlp_scaling_method=none) | -922.9416689384499 | 1.0506617220684689e-7

max_cost_spread = 3.841654461211874e-7
max_dadp_spread = 1.0506617220684689e-7
price_status  = :local_ac_dual
```

**Positive control PASSED:** `max_cost_spread = 3.84e-7 < 1e-2` — several orders of magnitude
inside the sanity bound. The 5 variants split into two exact clusters (`{1, 3, 4}` and
`{2, 5}`, distinguished only by `mu_strategy = "adaptive"`), agreeing to Ipopt's own
convergence-tolerance floor (`~1e-7`), not merely "close." This is the SAME solver-noise
scale plan 20-03's certificate measured on its own clean (non-restriction-binding) hours,
confirming the fallback's multi-start agreement is genuine numerical convergence, not a
coincidence of this particular fixture.

## Interpretation

- The fallback's `dadp`/`cost_ac` at `n_seeds = 2` (the CI-gated subset shipped in
  `test/test_restricted_branch_flow.jl`'s seventh `@testitem`) is representative of the
  FULL 5-variant population on this fixture — the cheap CI subset is not hiding a wider
  disagreement among the 3 untested variants.
- D-10's caveat ("a LOCAL optimum of a nonconvex problem, NOT a market-clearing convex
  dual") remains fully in force regardless of this agreement — multi-start agreement rules
  out ONE failure mode (a genuinely unstable/multi-modal local optimum on THIS fixture), not
  the structural fact that the AC-OPF itself is nonconvex. A different fixture (e.g. a
  larger feeder, a different PV/load regime) could exhibit genuine multi-modality; this
  spike validates EXACT-04 specifically, not the mechanism in general.
- Per plan 20-04's own orchestrator-note adaptation (see `20-04-SUMMARY.md`): on EXACT-04
  itself, `RestrictedBranchFlow`'s own certificate PASSES (`ac_feasible = true`, plan
  20-03's revised semantics), so this fallback is not actually EXACT-04's required answer —
  this spike exercises the fallback's OWN multi-start mechanics in isolation, exactly as
  the CI-gated test above does, not a live D-09 trigger on this fixture.

## Honest Limits

1. **One fixture, one seed base** (`seed = 20260406`, per aggregator bus). Shows the
   fallback's multi-start mechanics are stable HERE; does not establish stability across a
   wider population of fixtures/regimes.
2. **All 5 variants are deterministic Ipopt convergence-strategy changes**, not randomized
   initial points (D-11's documented Claude's-Discretion choice, `src/models/
   ac_dual_fallback.jl`'s header comment) — a genuinely different starting POINT (rather
   than a different convergence trajectory to the same starting point) is not exercised
   here.
3. No AC-oracle cross-check beyond the fallback's own re-solves — this spike measures
   INTERNAL agreement among the fallback's 5 seeds, not agreement against an independent
   ground truth.
