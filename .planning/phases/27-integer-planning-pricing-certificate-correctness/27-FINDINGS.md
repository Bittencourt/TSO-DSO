# Phase 27 Findings

Findings discovered during Phase 27 gap-closure execution that are documented as facts (not
silently fixed) and folded into `.planning/STATE.md` by the orchestrator at phase close.
Executors in parallel worktrees append here — never edit `STATE.md` directly.

## Plan 27-02 — FIX-08 per-branch exactness floor: irreconcilable ε conflict (ESCALATED)

- **[v?.? Phase 27 finding, ESCALATED]:** the per-branch relative exactness floor
  `atol_b = ε * ref_b` (FIX-08, replacing the flat `atol = 1e-6` default in
  `assert_socp_exact!`) has NO single `ε` value that satisfies both:
  1. `test/test_exactness.jl`'s **pre-existing** WR-01 regression item ("relative gate refuses
     a base-shrunk cone slack an absolute τ would accept") — a `smax = 10` branch with an
     injected `l = 5e-6` gap (`ref_b = smax^2 = 100`) — which needs `ε < 5e-6/100 = 5e-8` to
     KEEP throwing (its documented purpose: prove the gate refuses a small-ABSOLUTE, large-
     RELATIVE cone slack that a purely-absolute tolerance would accept).
  2. The IEEE-13 ground canonical acceptance fixture (`test/test_acceptance.jl`'s "IEEE-13
     congestion" item, and the structurally-identical `test/test_admm.jl:78` /
     `test/test_planning_certification*` cross-validation path built on the SAME
     `Phase4Fixtures.build_ieee13_ground_aggregators` feeder) — a genuinely-exact solve whose
     worst residual (gap ≈ `3.1e-8`) sits on 2 INTERIOR branches (`from=2→5`, `from=5→6`) at
     PV-back-feed reverse-flow hours, where `ref_b = head_flow_mag2 ≈ 4.56e-3` — which needs
     `ε ≳ 5e-5` to KEEP passing (measured by direct binary search: throws at `ε=4e-5`, passes
     at `ε=5e-5`).
  - These two constraints are ~3 orders of magnitude apart (`5e-8` vs `5e-5`) — genuinely
    incompatible, not a matter of picking a better constant.
- **Root cause:** for a THERMALLY-LIMITED branch, `ref_b = br.smax^2` scales the floor UP as
  `smax` grows. The `smax=10` WR-01 regression fixture and the IEEE-13 ground fixture's head
  branch (`smax=0.0686`) sit at very different points on that scale, and the interior branches
  that drive the IEEE-13 conflict inherit the HEAD branch's own flow magnitude as `ref_b`
  (`head_flow_mag2 ≈ 4.56e-3`, itself already small because the IEEE-13 head branch is a
  SMALL-`smax` congestion-driven branch, `S_max,(0,1) = 0.0686` pu) — so the "same physical
  design" (scale the floor to the branch's own thermal capacity) produces a MUCH smaller floor
  on the small-`smax`-head IEEE-13 fixture than on the `smax=10` synthetic WR-01 fixture, while
  the ACTUAL numerical noise floor (Clarabel's own achievable cone residual, ~`1e-8`-`1e-7`
  everywhere) does not shrink with the network's `smax` — it is closer to a genuine solver
  invariant.
- **Disposition (measured, this plan):** `MEASURED_ε_FIX08 = 1e-4` was chosen to satisfy the
  plan's EXPLICITLY-NAMED "must still pass" set (Task 2's acceptance criterion): the new
  synthetic small-branch regression (throws, ~50x margin) AND the cluster-E/canonical fixtures
  RESEARCH.md names (`test_pricing_dlmp.jl:20/226`, `test_pricing_welfare.jl:64`,
  `test_admm.jl:25/78`, `test_planning_oracle.jl:267`, IEEE-13/IEEE-123 `test_acceptance.jl`) —
  all pass at `ε = 1e-4` with ≥2x margin on the tightest (IEEE-13 ground, threshold ≈`5e-5`).
  Per the LOCKED policy (CONTEXT.md / 27-02-PLAN.md), `ε` was **NOT** raised further to
  relax the gate for any fixture, and was **NOT** lowered to preserve the pre-existing WR-01
  item — the conflict is recorded here instead of silently resolved either way.
- **Consequence:** `test/test_exactness.jl`'s pre-existing item "exact: relative gate refuses
  a base-shrunk cone slack an absolute τ would accept (WR-01)" now PASSES (no longer throws)
  at the shipped `ε = 1e-4` default — this is a "should-be-flagged now passes" regression in
  that item's own documented intent, though the item's `@test_throws` assertion itself was
  NOT modified by this plan (only a NEW item was added to the file; this pre-existing item is
  byte-identical to before). Running the full suite will show this item FAILING
  (`@test_throws Exception` no longer observes an exception) until a follow-up decision is
  made.
- **ESCALATED — awaiting user triage.** Do not resolve by adjusting `ε` without an explicit
  decision. Candidate resolutions for a future plan/session (none applied here):
  (a) accept the WR-01 item's regression as a documented, intentional consequence of FIX-08's
  design (the item's ORIGINAL scale-dependence lesson — "small absolute ≠ exact" — is still
  true in principle, just no longer demonstrated by THIS specific fixture at THIS specific
  `smax`) and update/relabel the item to use a smaller `smax` that keeps demonstrating the
  same lesson under the new per-branch floor; (b) give the per-branch floor a SEPARATE,
  smaller floor constant for the WR-01-style "small absolute residual, near-zero-flow branch"
  regime distinct from the interior-branch head-flow-magnitude reference (an architectural
  change, Rule 4 territory, out of scope for this plan); (c) accept BOTH constraints cannot be
  met simultaneously and explicitly retire/relabel the WR-01 item's claim.
- **Measured raw numbers (full sweep table):** see `src/models/exactness.jl`'s
  `MEASURED_ε_FIX08` comment and `27-02-SUMMARY.md` for the complete per-fixture ε-threshold
  table (synthetic small-branch, IEEE-13 ground, IEEE-123, two_bus_feeder, near-lossless
  smax=10 cluster-E pair).
