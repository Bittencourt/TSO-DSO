# Phase 27 — Findings Log

Findings discovered by parallel executor worktrees during phase execution. Per
27-CONTEXT.md's golden/process policy, executors never edit STATE.md/ROADMAP.md directly —
findings requiring triage or escalation are recorded here instead.

## Plan 27-01 (FIX-06: `corner_recourse` T>1)

### F-27-01-1 — Plan's own `<verify>` fixture is oracle-infeasible for any z > 0 (fixture defect, not a code defect)

**Found during:** Task 1 verify.

**Issue:** Task 1's `<verify>` block's exact literal fixture (`PVBattery(...,[3.0])`,
`Aggregator(2, 0.9, [dev1], [0.0])` — a zero fixed net load) makes
`solve_planning_oracle!` genuinely, structurally INFEASIBLE (`MOI.INFEASIBLE`) for ANY
`z > 0`, at BOTH `T=1` (pre-existing, unchanged ternary-search path) and `T=2`. Root
cause: with no fixed consuming load at the aggregator's bus, `PVBattery.p_inject =
pv_used - p_ch + p_dch >= 0` ALWAYS (Assumption A6: the battery charges only from its own
co-located, curtailable PV, never the grid — `src/devices/PVBattery.jl:29-30`), so the bus
can only ever ABSORB surplus (net injection `>= 0`), never present a net DEMAND — the
substation's own `p_import` (pinned to `z`) can therefore only ever be `<= 0`
(confirmed empirically: `solve_planning_oracle!` at `z ∈ {0.05, 0.1, ..., 0.5}` all throw
`MOI.INFEASIBLE`, reproduced identically on the pre-existing, UNCHANGED T=1 path with the
plan's own literal parameters).

**Disposition:** Not a code defect in `corner_recourse`/`_corner_recourse_joint` — the
plan's own `<verify>` script's chosen fixture parameters do not exercise a feasible `z>0`
region on this network topology. The executor substituted a nonzero fixed net load
(`agg.netload = [3.5, 3.5]` for T=2 / `[3.5]` for the T=1 sanity check reusing the D-12
device) for its own ad hoc verification scripts, keeping every other parameter (device
type, `corridor_cap`, `x_inv_max`, `c_inv`, `c_op`, `λ₀`) identical to the plan's own
values. The COMMITTED `test/test_planning_certification_integer.jl` `@testitem` uses this
corrected fixture (documented inline in that file's own header comment).

**Escalate?** No user action required — a verification-script parameter choice, not a
correctness gap in the committed source/test files.

### F-27-01-2 — Pre-existing `solve_follower!` numerical fragility: HiGHS occasionally returns no Farkas certificate near degenerate trial values

**Found during:** Task 1 exploratory testing (constructing a T=1 sanity fixture using
`PVBattery` + a nonzero net load).

**Issue:** `solve_follower!`'s own docstring (`src/planning/follower.jl`, WR-05 note)
states the infeasible branch is "VERIFIED to receive `MOI.INFEASIBILITY_CERTIFICATE` for
BOTH infeasible regimes of this LP against the EXACT-pinned HiGHS 1.24.1" and documents a
fallback (`set_optimizer_attribute(model, "presolve", "off")`) for if this ever changes.
Empirically observed THIS SESSION (2026-09-29, HiGHS 1.24.1, unchanged from that
docstring's own pin): on a `FollowerLP` fixture whose ternary-search-driven minimizer
converges toward a trial `z` very close to (but not exactly) zero (order `1e-7`–`1e-8`),
`solve_follower!` genuinely returns `termination_status = INFEASIBLE` with
`dual_status = NO_SOLUTION` (no certificate at all) rather than
`MOI.INFEASIBILITY_CERTIFICATE` — triggering the function's own loud `else`-branch
`error(...)`, NOT the documented `(; feasible = false, v, u)` return. This reproduces
deterministically on the specific fixture that hit it (a `T=1` `PVBattery`+netload=3.5
sanity fixture the executor tried and discarded in favor of the D-12 canonical fixture for
its own T=1 check — see F-27-01-1).

**Disposition:** OUT OF SCOPE for plan 27-01 (`files_modified` is
`src/planning/benders.jl` + `test/test_planning_certification_integer.jl` only —
`src/planning/follower.jl` is untouched by this plan). Per the executor scope-boundary
rule, this is logged, not fixed. The NEW `_corner_recourse_joint` (T>1) and the UNCHANGED
`_corner_recourse_ternary` (T=1) both fail LOUDLY (an uncaught `ErrorException` propagates
to the caller) rather than silently on this class of trial — matching the project's
fail-loud convention — but neither path currently catches/gracefully degrades this
SPECIFIC HiGHS-certificate-loss case the way it catches a genuine
`MOI.INFEASIBILITY_CERTIFICATE` or an oracle-side exception. All committed verification
(the T=1 D-12 reproduction, the T=2 PVBattery fixture at `y_inv ∈ {0.5, 1.5, 4.5}`) avoids
triggering this specific edge — it never arose in any COMMITTED test or source path, only
in a discarded ad hoc exploration fixture.

**Escalate?** Recommend a follow-up quick task (or a future phase's scope) apply
`follower.jl`'s OWN documented fallback (`set_optimizer_attribute(model, "presolve",
"off")`) or otherwise re-verify the WR-05 docstring's "both infeasible regimes" claim
against HiGHS 1.24.1 — the claim is not universally true as currently written. No
correctness impact on any code this plan modifies or any currently-committed test.
