# Phase 27 Findings

Findings discovered during Phase 27 gap-closure execution that are documented as facts (not
silently fixed) and folded into `.planning/STATE.md` by the orchestrator at phase close.
Executors in parallel worktrees append here — never edit `STATE.md` directly.

## Plan 27-02 — FIX-08 per-branch exactness floor: irreconcilable ε conflict (RESOLVED — hybrid floor)

**Status: RESOLVED (2026-09-29).** The user reviewed this escalation and directed a HYBRID
floor: `atol_b = max(τ_solver, ε·ref_b)`, with `τ_solver` a separately-measured ABSOLUTE
Clarabel cone-residual floor and `ε` kept small (`< 5e-8`) so the pre-existing WR-01 item
keeps throwing. See "Resolution" at the end of this entry for the measured numbers. The
original escalation is preserved below UNEDITED for the record.

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

### Resolution (2026-09-29) — hybrid floor `atol_b = max(τ_solver, ε·ref_b)`

The user's directive: keep `ε` small (`< 5e-8`, so the per-branch RELATIVE term still does its
original job on large-`smax` branches) and add a SEPARATELY-MEASURED ABSOLUTE floor `τ_solver`
(Clarabel's own achievable cone-residual noise floor, measured with a documented margin,
mirroring the `KNOWN_OPTIMUM_ATOL` measure-then-pin protocol) to protect lightly-loaded/
interior branches without needing `ref_b` to carry that burden. `atol_b = max(τ_solver,
ε·ref_b)` — the LARGER of the two applies per branch/hour.

**Measurement protocol (2 stages), direct scripts reproducing each fixture body under
`julia --project=.`:**

1. **`τ_solver`:** for every REQUIRED canonical/cluster-E fixture, computed
   `excess[b,t] = gap[b,t] - rtol·max(|lhs|,|rhs|)` — the residual an ABSOLUTE floor alone
   must cover, independent of `ref_b`/`ε` (a negative excess means the `rtol` term alone
   already passes that (b,t) regardless of any absolute floor choice).

   | Fixture | Worst excess | Note |
   |---|---|---|
   | IEEE-13 ground (branch 5→6, t=16) | ≈3.08e-8 | interior branch, small head-flow ref_b |
   | **IEEE-123 (branch 48→49, t=9)** | **≈7.90e-8** | **worst REQUIRED excess — binding** |
   | two_bus_feeder | < 0 (every b,t) | fully covered by `rtol` regardless of atol |
   | near-lossless smax=10 pair (dlmp/welfare) | < 0 (every b,t) | fully covered by `rtol` (real, non-trivial flow; rtol_term ≈1.76e-5 ≫ gap ≈6.3e-6) |

   Worst REQUIRED excess = **7.90e-8** (IEEE-123). A strict 10x margin (the
   `KNOWN_OPTIMUM_ATOL` convention) would give `τ_solver = 7.9e-7`, which is ITSELF larger
   than the Task-2 synthetic regression's injected gap (`5e-7`) and would break requirement
   (2) below — so a smaller, explicitly-documented margin was used instead: `τ_solver = 2.0e-7`
   (≈2.53x the worst measured excess), chosen as the largest value in the numerically-narrow
   feasible window `[1.635e-7, 2.5e-7]` (lower bound: 2x margin on the IEEE-123 pass side;
   upper bound: 2x margin on the Task-2 synthetic throw side).

2. **Verification of all three required outcomes**, with `τ_solver = 2.0e-7` and
   `ε = 1.0e-9` (well under the `< 5e-8` bound):

   | Requirement | Result | Margin |
   |---|---|---|
   | (1) WR-01 pre-existing item (smax=10, l=5e-6) must THROW | **THROWS** | ratio ≈24.9 (24.9x) |
   | (2) Task-2 synthetic (smax=0.01, l=5e-7) must THROW | **THROWS** | ratio ≈2.50 (2.5x) |
   | (3a) IEEE-13 ground must PASS ≥2x | **PASSES** | ≈6.47x |
   | (3b) IEEE-123 must PASS ≥2x | **PASSES** | ≈2.43x (tightest) |
   | (3c) two_bus_feeder must PASS ≥2x | **PASSES** | ≈145.8x |
   | (3d) near-lossless smax=10 pair (dlmp) must PASS ≥2x | **PASSES** | ≈2.81x |
   | (3e) near-lossless smax=10 pair (welfare) must PASS ≥2x | **PASSES** | (rtol-dominated, same fixture family as 3d) |

All three required outcomes hold simultaneously — the hybrid floor is FEASIBLE (the
coordinator's fallback — `ε=1e-4` + rescoping the WR-01 fixture — was NOT needed). Implemented
in `src/models/exactness.jl` (commit `5b72c74`): `MEASURED_ε_FIX08 = 1.0e-9`,
`TAU_SOLVER_FIX08 = 2.0e-7`, `atol_b = atol === nothing ? max(τ_solver, ε * ref_b) : atol`.
`test/test_exactness.jl`'s pre-existing WR-01 item is UNCHANGED (byte-identical) and now
throws again, confirmed by direct execution of its exact literal fixture body. The 2
explicit-`atol` call sites (`src/admm/DsoOpt.jl`, `test/fixtures_phase19.jl`) remain on the
unchanged bypass path.

**Caveat carried forward:** the margin on requirement (3b) (IEEE-123, ≈2.43x) and the throw
margin on requirement (2) (≈2.5x) are the TIGHTEST in this set — both comfortably clear the
plan's ≥2x bar but leave less headroom than a textbook 10x margin would. If a FUTURE fixture
(e.g. IEEE-8500, not swept in this plan — see `27-02-SUMMARY.md`) produces a genuinely-exact
excess above ≈1.5e-7, or a stricter synthetic regression is added with an injected gap below
≈4e-7, this hybrid pair should be re-measured, not assumed to generalize indefinitely.
