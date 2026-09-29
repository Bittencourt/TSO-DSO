---
phase: 27-integer-planning-pricing-certificate-correctness
fixed_at: 2026-09-29T13:12:15Z
review_path: .planning/phases/27-integer-planning-pricing-certificate-correctness/27-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 27: Code Review Fix Report

**Fixed at:** 2026-09-29T13:12:15Z
**Source review:** .planning/phases/27-integer-planning-pricing-certificate-correctness/27-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (2 critical, 3 warning; fix_scope=critical_warning)
- Fixed: 5
- Skipped: 0

Each fix was applied directly against the actual source (not blind-applied from the
review's suggested text), verified via a direct `julia --project=.` script (never
TestItemRunner under `--project=.`, per this repo's established trap), and committed
atomically. For both CRITICAL findings, the committed regression `@testitem` was
confirmed BY HAND to fail against the pre-fix code (via `git stash` on the affected
source file, re-running the exact same test body) and pass against the fix — evidence
recorded in the commit messages and the test files' own header comments. No `τ_solver`/`ε`
constants were touched. No golden moved (no numeric fixture pinned as a "golden" was
altered by these fixes; CR-01/CR-02's changes only affect previously-unreached/incorrect
code paths, and the new tests are additions, not re-pins). The full suite was NOT run
(per this pass's own instructions) — orchestrator's certifying suite run is the closing
gate.

## Fixed Issues

### CR-01: `_corner_recourse_joint`'s double-infeasible stall guard makes no progress and wastes the entire iteration budget

**Files modified:** `src/planning/benders.jl`, `test/test_planning_certification_integer.jl`
**Commit:** `ba01c6e`
**Applied fix:** Replaced the single-shot bisection attempt (on a repeated
oracle-infeasible-no-certificate trial) with a genuinely iterative halving loop, bounded
by a new `JOINT_RECOURSE_BISECT_MAX_DEPTH = 64` constant (a hard IEEE-754 double bound —
64 halvings of any bounded bracket drives the midpoint bit-identical to an endpoint — not
a tunable guess). The loop keeps shrinking the bracket `[z_best, z_next]` toward the
guaranteed-feasible anchor, trying a NEW midpoint each time, until a cut of either kind
(epigraph or feasibility) is produced (genuine progress, loop breaks and the outer Kelley
iteration continues) or the depth is exhausted (a diagnostic `error(...)` distinguishing a
genuine stall from "gap not yet met", never a silent non-convergence). This also resolves
**WR-03** (below) as a direct side effect, since the bisection is no longer single-shot on
ANY qualifying stall, not just the specific double-infeasible case CR-01 names.

Added a regression `@testitem` on a widened-follower-capacity (`corridor_cap=x_inv_max=
20.0`) T=2 PVBattery fixture, empirically measured to drive the master LP's proposed
trials into a wide oracle-infeasible-no-certificate band (`y_inv≈3.75` onward) AND make
the single-bisection midpoint land back inside that same band — the exact
double-infeasible-midpoint scenario CR-01 requires. Confirmed by hand (`git stash` on
`src/planning/benders.jl`, re-running the exact test body): pre-fix, `corner_recourse`
throws `"_corner_recourse_joint: exhausted 20 iteration(s) ..."`; post-fix, it converges
to `4.250000006554955`, cross-checked against a box-monotonicity control (`y_inv=3.0`,
same value) and an independent dense-grid upper bound (`n=15`, one-directional, avoiding a
two-sided Lipschitz tolerance since gradient norms on this fixture blow up ~15x near the
infeasibility boundary).

### CR-02: MPC truth settlement clips PV charging but not PV self-consumption/export, understating the correction FIX-10 exists to make

**Files modified:** `src/experiments/mpc_loop.jl`, `test/test_mpc_loop.jl`
**Commit:** `9ad07dd`
**Applied fix:** Extracted the A6 truth-settlement clip into a new internal, unexported,
pure helper `_mpc_pvbattery_true_clip(p_ch, pv_used, Ppv_true) -> (; p_ch_true,
pv_used_true)` (mirroring the existing `_mpc_pvbattery_utility` factoring pattern for
direct testability) and applied it to BOTH `p_ch` and `pv_used` identically in
`run_mpc`'s truth-settlement block — previously only `p_ch` was clipped, leaving
`pv_used` (which feeds `net_p`/`p_inject`/the AC-settled frontier import) unclipped, so
`fe.pv_factor > 1` could credit `realized_welfare`/`p_import_true` with PV energy the true
plant cannot physically supply. The `p_ch <= pv_used` PVBattery invariant is preserved
automatically (both quantities clipped by the same `min(·, Ppv_true)` rule). Also updated
the `realized_welfare` docstring to describe both quantities being clipped.

Added a regression `@testitem` directly unit-testing `_mpc_pvbattery_true_clip` with
hand-derived numbers (`p_ch=3.0, pv_used=4.0, Ppv_true=2.0` → both clip to exactly `2.0`),
asserting the core CR-02 invariant (neither clipped quantity exceeds true PV, individually)
plus a hand-derived exact welfare value (`4.675`, via the same `_mpc_pvbattery_utility`
formula `run_mpc` itself calls) and an explicit pre-fix-vs-post-fix net-PV-contribution
comparison (`2.5` unclipped vs. `0.5` clipped) demonstrating the "phantom PV energy" bug
directly. Confirmed by hand (`git stash` on `src/experiments/mpc_loop.jl`, re-running the
exact test body): pre-fix, `_mpc_pvbattery_true_clip` does not exist (`isdefined` check
fails, then `UndefVarError`); post-fix, all assertions pass.

### WR-01: `decompose_dlmp`'s return type changed from `NamedTuple` to a custom struct with a different field order

**Files modified:** `src/pricing/dlmp.jl`, `test/test_pricing_dlmp.jl`
**Commit:** `570089d`
**Applied fix:** Added `Base.NamedTuple(::DlmpDecomposition)` and `Base.propertynames`
methods. `NamedTuple(d)` reconstructs the EXACT pre-Phase-27 field names/order (`energy,
loss, congestion, voltage, reactive, total`) — deliberately NOT the new struct's own field
order, which additionally transposes `congestion`/`drop` relative to the old
`congestion`/`voltage` positions. Any "duck-typed as a NamedTuple" call site (none found
currently shipped, but the API is exported) can be repaired with a one-line
`NamedTuple(decompose_dlmp(...))` wrap. `propertynames` now also surfaces the deprecated
`.loss`/`.voltage` virtual properties so introspection isn't misleadingly incomplete.

Added a regression `@testitem` directly constructing a `DlmpDecomposition` and asserting
`NamedTuple(d)`'s exact keys/values/order, `Tuple(nt)`/`collect(values(nt))` (the genuine
NamedTuple-only operations WR-01 is about), and `propertynames` coverage — no network solve
needed. Confirmed by hand (`git stash` on `src/pricing/dlmp.jl`): pre-fix,
`NamedTuple(d)` throws `MethodError: no method matching iterate(::DlmpDecomposition...)`
(the generic `NamedTuple(itr)` fallback tries to iterate the struct and fails loudly, never
silently); post-fix, it reproduces the old shape exactly.

### WR-02: `assert_socp_exact!`'s interior-branch reference scale is an arbitrary choice on a meshed feeder with multiple root-incident branches

**Files modified:** `src/models/exactness.jl`
**Commit:** `2a3670b`
**Applied fix:** Chose the review's own **Option A** ("measure and document that the
chosen head branch's flow magnitude is always representative on the project's actual
meshed fixtures — i.e., establish this is a non-issue in practice") rather than Option B
(switch `ref_b` to `sum`/`max` over every root-incident branch). Measured: `assert_socp_
exact!`'s numeric gate only ever runs on a `ConvexBranchFlow`-formulated `ctx` (grepped —
`ConvexBranchFlow.jl` is the ONLY formulation module in the tree that stashes the `:l`
handle the gate is data-driven on). The one currently-known multi-root-branch feeder
(`Phase23Fixtures.mesh_feeder`'s 4-bus diamond, asymmetric loads by construction — its two
root branches genuinely carry different flow magnitudes) is exercised exclusively via
`MeshedFlow()` in `test_mesh_angle_certificate.jl`/`test_mesh_flow.jl` — confirmed by
grepping every `mesh_feeder(...)` call site in the tree — which never stashes `:l` and so
never reaches this gate. So WR-02's concern is real in principle (documented, with a named
revisit condition) but not a currently-live defect. Deliberately did NOT change `ref_b`'s
computation: `assert_socp_exact!` is called from 30+ `src`/`test`/`docs` sites, and a
`sum`/`max` change would shift the exactness pass/fail verdict on EVERY interior branch of
EVERY feeder in the suite — verifying no regression from that would require a full-suite
run explicitly out of scope for this fix pass. This is a documentation-only, zero-behavior
commit (confirmed via `julia --project=. -e 'using TSODSO'` reload).

### WR-03: T>1 stall bisection is single-shot even on its "working" branch

**Resolved by:** CR-01's fix, **commit `ba01c6e`** (no separate commit)
**Note:** WR-03 is explicitly framed in 27-REVIEW.md as "independent of CR-01's
double-infeasible failure mode" but the SAME single-shot-bisection code CR-01 rewrote.
The CR-01 fix's iterative bisection loop (bounded by `JOINT_RECOURSE_BISECT_MAX_DEPTH`)
applies to every qualifying stall, not only the specific double-infeasible case CR-01's
own title names — so a fixture whose feasible/infeasible boundary requires MULTIPLE
halvings to resolve (WR-03's exact concern) is now handled by the same loop, rather than
falling through to a second single bisection attempt on the next detected stall. No
additional test was written for WR-03 specifically since CR-01's own regression test
already exercises a multi-halving path on this fixture (the true recourse minimum sits
well inside `[0,3]^2`, so reaching it from a `y_inv=10.0` stalled trial via a *single*
halving alone would not converge to the correct value — the test's cross-checks against
the `y_inv=3.0` control and the dense-grid upper bound would have caught a
still-single-shot regression).

## Skipped Issues

None — all in-scope findings were addressed (either with a code fix + regression test, or,
for WR-02, a deliberate documentation-only resolution with an explicit, narrow risk
rationale — see above).

---

_Fixed: 2026-09-29T13:12:15Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
