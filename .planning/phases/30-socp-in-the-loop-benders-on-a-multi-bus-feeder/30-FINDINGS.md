# Phase 30 Findings: SOCP-in-the-Loop Benders on a Multi-Bus Feeder

**Phase:** 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
**Closed:** 2026-10-01 (pending orchestrator suite certification, see final section)
**Requirements:** BILEV-03, BILEV-04, BILEV-05

This document consolidates the fixture designs, measured numbers, and audit results across
plans 30-01 (feasibility oracle + AC re-check infra), 30-02 (`:auto` α-bound derivation +
`30-ALPHA-AUDIT.md`), 30-03 (tuned IEEE-13 fixture + independent joint reference), 30-04
(`solve_stackelberg!` `inexact_policy`/oracle-feasibility-cut/unconditional `bounds_ctx`/
AC-recheck wiring), and 30-05 (BILEV-03 headline convergence test + T=24 Literate
extension), per this plan's six required points plus the mandatory process notes.

## 1. BILEV-03: IEEE-13 short-horizon fixture, cross-check tolerance, converged numbers

**Fixture design (plan 30-03):** `test/fixtures_planning_ieee13_short.jl`
(`@testmodule IEEE13ShortHorizonFixtures`) — a `T=4`-parametrized `ieee13_modified()`
aggregator population (`PVBattery` + `Thermostatic` only, never `Deferrable`), chosen within
CONTEXT.md's mandated `T ∈ [3,6]` range. Re-probing 30-RESEARCH.md's own exploratory `T=4`
recipe (`load_scale=0.01, pv_scale=0.03, batt_pmax=0.02, batt_emax=0.1, batt_soc0=0.05`)
against the CURRENT codebase found `z=zeros(4)` is **already** oracle-feasible and SOCP-exact
(`cost=-609.0471557105552`, `maxgap=2.2407826061415185e-10`) — **no population retuning was
needed**, contrary to RESEARCH.md's own earlier (pre-Phase-26..29) measurement of the
identical recipe as `MOI.INFEASIBLE` at `z=0` (see point 3 below for the fuller statement of
this discrepancy). A measured feasible/exact/inexact/infeasible sweep map across
`z ∈ {-0.1, ..., 0.07}` pu/hr is documented in the fixture's own header comment as the
authoritative reference for the convergence test.

**Independent joint reference:** `solve_joint_reference` (same file) — a monolithic,
single-shot SOCP built from scratch (reusing only `contribute!`/`add_to_residual!`/
`register_constraint!`, never `PlanningOracle`/`FollowerLP`/`BendersMaster`), with `z[t]`
reused as both the frontier import and the follower's delivered flow. Its `UB ≈
-welfare_total` sign convention is documented inline.

**Headline `@testitem`** (plan 30-05, `test/test_planning_benders_ieee13.jl`): the FIRST
multi-bus fixture in the suite to run the real `solve_stackelberg!` Benders loop with
`ConvexBranchFlow()` on `ieee13_modified()` AND to exercise `build_master`'s new `:auto`
`α_op_lb`/`α_x_lb` default end-to-end (both keys omitted entirely from `master_kwargs`,
reusing plan 30-03's own smoke-test kwargs tuple verbatim: `follower_kwargs` =
`corridor_cap=1.0, x_inv_max=0.05, c_inv=0.01, c_op=fill(0.01,T)`; `master_kwargs` =
`c_y=0.01, y_max=0.05`).

**Converged numbers:** `iters=6`, `gap=3.141107077821004e-7` (well inside `tol=1e-6`).

**Code-review correction (WR-07) — the three-source tolerance below is RETIRED.** It froze
`10·(UB−LB)` of one run as a literal (10× looser than the certificate it checked, and not
re-measured if UB−LB changes) and cited a `joint.gap` field that did not exist. The test
now asserts Benders' own bracket `LB − ε ≤ J* ≤ UB + ε` with
`ε = 10·max(oracle_gap, joint.gap)` read at runtime (`solve_joint_reference` now solves
with `dual = true`, returns `gap`, and certifies its own cone exactness via
`assert_socp_exact!`). Re-measured: ε = 2.78e-6, J* = 609.0112017 inside
[LB, UB] = [609.0111466, 609.0113390]. The "reusable three-source convention" claimed
below should NOT be reused. Original text follows.

**Cross-check tolerance — measured, three sources (found correction to the plan's own
two-source recipe):** the plan's `<action>` text named "10x the worse of the two solvers'
own certified duality gaps" as the recipe. Measured directly: `10 * max(oracle_gap=2.79e-7,
joint_gap=1.92e-7) = 2.79e-6`, which **FAILS** the cross-check — the actual observed
discrepancy `|UB - (-welfare_total)| = 1.489e-4` is ~53x larger than that two-source
tolerance. Root cause (measured, not assumed): `result.UB` is only certified by
`solve_stackelberg!`'s own convergence gate to lie within the Benders loop's own `|UB-LB|`
absolute gap (`1.913e-4` this session) of the TRUE joint optimum — this gap is structurally
larger than either solver's own interior-point duality gap because `tol` (a *relative* gap,
`1e-6`) only loosely bounds it in absolute terms at this objective magnitude (`|UB| ≈ 609`).
A third source, `ub_lb_gap = |UB - LB|`, was therefore added: `measured_tol =
10 * max(oracle_gap, joint_gap, ub_lb_gap) = 1.913e-3`. The actual discrepancy
(`1.489e-4`) now sits comfortably inside it (~13x margin) — a real, non-trivial margin, not
a tautology. This refines, not contradicts, the plan's own recipe (which also allowed "the
MIP/SOCP duality gap each solver reports" as an alternative source; the Benders loop's own
certified `|UB-LB|` gap is read here as exactly that, for the decomposed side of the
comparison). **This three-source pattern (oracle gap / joint-reference gap / Benders
UB-LB gap) is a reusable convention for any future Benders-vs-monolithic cross-check in this
codebase.**

**Incumbent cone-gap/exactness status:** the fixture's kwargs keep the entire Benders trial
box inside the documented feasible-and-exact `z ∈ [-0.05, 0.05]` window, so every iteration
came back genuinely SOCP-exact this session: `result.ac_report === nothing` and
`all(isnan, result.trace.socp_maxgap_trace)`. This is one of the two outcomes plan 30-05
explicitly anticipated (exact throughout vs. inexact-triggering-AC-recheck); the headline
test positively asserts the exact outcome and explicitly contrasts, in its own comments,
against `test_planning_inexact_policy.jl`'s fixture (point 3 of BILEV-04b below), which
deliberately drives the inexact branch instead.

**T=24 Literate extension** (`docs/literate/stackelberg_benders.jl`, plan 30-05 Task 2,
outside the ≤2min suite budget): a full day-ahead `ConvexBranchFlow` Stackelberg-Benders run
on `ieee13_modified()`, confirmed end-to-end (`julia --project=. docs/literate/
stackelberg_benders.jl`, exit code 0, ~130s wall time): `iters=15`, `gap≈3.09e-7`, `y=0.015`,
`ac_report=nothing` (SOCP-exact throughout). The T=4-scale investment-ceiling kwargs
(`y_max=0.05`/`corridor_cap=1.0`/`x_inv_max=0.05`) were found, by live probe, to throw a
genuine `assert_battery_complementarity!` violation at `t=7` once the full 24-hour price
swing is in play — an out-of-scope-for-`inexact_policy` complementarity throw, not an
exactness-class one. The T=24 run therefore uses a tightened investment ceiling
(`y_max=0.03`/`corridor_cap=0.5`/`x_inv_max=0.03`) to stay inside the complementarity-safe
region. **This is recorded here as a genuine, known limitation (a T=4-tuned investment scale
does not transfer unmodified to T=24 under this population), not hidden or silently
retuned-away.**

## 2. BILEV-04a: oracle feasibility cuts

**Cut-gradient sign (plan 30-01, empirically re-derived, not assumed):** the slack-
minimization `FeasibilityOracle`'s cut gradient is `u = dual.(fo.pin)` — **UN-negated**,
the opposite convention from `solve_planning_oracle!`'s own `π` (which IS sign-flipped per
the project's D-06 precedent). The plan's own docstring template initially assumed
`u = -π` by analogy with D-06; this analogy does **not** transfer. Verified by solving the
feasibility oracle at a known-thermally-infeasible anchor `z_k=0.08` and checking both
candidate signs against the full measured feasible/infeasible map on `ieee13_modified()`
across `z ∈ {0.0, 0.01, 0.02, 0.05, 0.0686, 0.08, 0.09}`: `u=+π` reproduces the real `0.0686`
pu thermal threshold exactly (excludes `z >= 0.0686`, holds at every feasible point tried);
`u=-π` wrongly violates the cut inequality at every known-feasible `z` tried, which would
incorrectly exclude the entire feasible region from the master. This sign was carried
forward verbatim and consumed unchanged by plan 30-04's `solve_stackelberg!` wiring.

**Thermal + voltage fixtures (plan 30-01):** the thermal-infeasible fixture uses the real,
unmodified `ieee13_modified()` feeder. The voltage-infeasible fixture required a dedicated,
thermally-widened (`smax=90`) IEEE-13 variant with a 10-aggregator ample-battery population
(not the unmodified feeder) — a direct probe confirmed thermal always binds first on the
real feeder as `z` grows (matching 30-RESEARCH.md's own prediction), so a separate,
purpose-built fixture was needed to isolate the voltage-infeasible branch (per CONTEXT.md's
Assumption A1, "separate fixtures" is permitted). Both fixtures are preceded by a
relax-one-constraint ablation confirming causation, and both confirm the loop still
converges after the feasibility-cut recovery.

**End-to-end confirmation (plan 30-04):** beyond plan 30-01's own purpose-built fixtures,
`test_planning_inexact_policy.jl`'s own T=4 IEEE-13 fixture (tuned for near-zero
leader/follower costs so the Benders loop's OWN natural trajectory explores the space)
triggers a genuine `MOI.INFEASIBLE` oracle throw **naturally**, 3 times en route to
convergence — confirming the oracle-feasibility-cut branch recovers correctly not just on
synthetic fixtures but on a realistic run. `test_planning_feasibility_oracle.jl` additionally
gained two `solve_stackelberg!` end-to-end items (thermal + voltage) satisfying the "loop
still converges" criterion on realistic trajectories, each confirmed via the same
relax-one-constraint ablation technique.

**Loop order:** follower feasibility check first (pre-existing WR-01 behavior), then oracle
feasibility, then the optimality cut — unchanged, per CONTEXT.md's decision. A feasibility
cut never updates `UB` (T-11-06), confirmed by the `:rejected`/feasibility-cut trace rows.

## 3. BILEV-04b: SOCP-inexactness policy (`inexact_policy`)

**Dispatch mechanism (plan 30-04):** `solve_stackelberg!` gains `inexact_policy::Symbol =
:certify_incumbent`, disambiguated using ONLY information `solve_planning_oracle!` already
computes — `is_solved_and_feasible` plus the `:socp_maxgap` stash timing — with **no
string-matching on error messages and no duplicated tolerance logic** (T-30-07 mitigation).
The genuine-infeasibility check (`!is_solved_and_feasible`, BILEV-04a's recovery) is checked
BEFORE the `:socp_maxgap`-based exactness disambiguation and fires identically under every
policy; only a genuine exactness-class throw is policy-dispatched.

**Measured-inexact pin used for the 3-policy test matrix:** `test_planning_inexact_policy.jl`
reuses plan 30-03's own `IEEE13ShortHorizonFixtures` (T=4, `ieee13_modified()`) with
near-zero leader/follower costs, so the Benders loop's OWN natural trajectory (never a
synthetic forced `z`) passes through a measured SOCP-inexact pin at `z~0.0504`
(`maxgap~1.7e-3-2.4e-3`).

**Observed per-policy behavior:**
- `:strict` — reproduces today's byte-identical throw on reaching the inexact pin (no
  behavior change from pre-Phase-30 `assert_socp_exact!`).
- `:reject` — skips the inexact cut (no `UB` update, `:rejected` trace row). Confirmed
  **empirically** (not assumed) to be **deterministic**: since no cut is ever appended on a
  rejected trial, the master's LP is byte-identical on the next iteration and re-proposes the
  SAME trial forever once it first lands in the inexact zone. (Code-review update, WR-06:
  `:reject` is now FAIL-FAST — the first deterministic repeat raises a named "`:reject`
  stalled at the SOCP-inexact trial z=…" error at iteration 8 instead of burning the
  budget to a generic "exhausted" error; the test pins the stall message and the 7
  completed checkpoints.) The test cross-references the companion `:certify_incumbent`
  item (same fixture/configuration) to show the pin is genuinely inexact-but-feasible,
  never a true infeasibility (T-30-09). (Code-review iteration 2, WR-02: the fail-fast
  version above could never get past an inexact trial. `:reject` now APPENDS the inexact
  trial's relaxation cuts, which are valid lower bounds whatever the exactness verdict,
  and only bars it from UB/the incumbent. On this fixture it follows the identical master
  trajectory as `:certify_incumbent` and converges at iteration 11 with the same exact
  incumbent, UB = 609.0155321155983; rows 7, 8 and 10 are `:rejected`. The "stalled" error
  remains as a backstop for the case where the relaxation's optimum is itself inexact:
  measured on the single-Thermostatic T=1 λ₀=[-1] fixture, it fires at iteration 5 at
  z = [0.04].)
- `:certify_incumbent` (default) — reconstructs the already-solved model's `(cost, π, π_s,
  dadp, ctx)` and proceeds normally, logging the cone gap.

**`ac_report` population status — CORRECTED by the Phase 30 code review (CR-02).** The
original text of this paragraph claimed the populated-`ac_report` path "IS exercised
end-to-end through `solve_stackelberg!` by `test_planning_inexact_policy.jl`'s
`:certify_incumbent` item". **That was false**: that item asserts
`result.ac_report === nothing`, because its converged incumbent is itself SOCP-exact (the
inexact iterates there are transient). No phase-30 test reached the populated path through
`solve_stackelberg!`; it was only unit-tested via `ac_recheck_incumbent`, whose `ok` field
was additionally hard-coded `true` (and a unit test asserted `r.ok` next to
`n_thermal_violations > 0`). Fixed in the code-review pass: `ok` is now
`n_thermal_violations == 0 && n_voltage_violations == 0` beyond a per-instance measured
tolerance (`10·δ`, `δ` = the AC solve's own max primal residual, measured 2e-9–1e-8), the
result carries an explicit `incumbent_exactness`/`incumbent_socp_maxgap`/
`ub_relaxation_only` certificate (UB/gap certify the relaxation only when the incumbent is
inexact), and a new item in `test_planning_inexact_policy.jl` drives an SOCP-inexact
incumbent end-to-end (single-Thermostatic T=1 `ieee13_modified()`, λ₀ = [-1.0], incumbent
z = 0.04 with measured maxgap 1.74e-2) and asserts the populated report.

**Trace extensions:** `BendersTrace` gains additive `socp_maxgap_trace`/
`policy_action_trace` columns and a `:rejected` `cut_type` kind; `trace_summary` gains
`n_inexact_iterations`. Every pre-existing `push!` call site (omitting the new keywords)
still compiles and records `NaN`/`:none` sentinels — confirmed by zero regressions on the
pre-existing planning suite.

**Universal runtime floor guard:** `_assert_epigraph_floor` fires unconditionally on the
optimality branch regardless of how either master bound was derived or validated at build
time — defense-in-depth per BILEV-05, reusing `ALPHA_LB_REJECTION_TOL` (plan 30-02) verbatim
rather than introducing a second, drifting constant.

## 4. BILEV-05: automatic α lower bounds

**Full `30-ALPHA-AUDIT.md` content, restated:**

The repo-wide T>1 `α_op_lb`/`α_x_lb` census (independently re-verified, not copy-pasted from
30-RESEARCH.md Pitfall 4) covers all 10 planning test files AND every `src/`-level
`solve_stackelberg!`/`build_master` call site:

| File | α_op_lb/α_x_lb line(s) | Governing `T` | Notes |
|---|---|---|---|
| `test_planning_benders.jl` | 51, 130, 186, 233 | 1 | — |
| `test_planning_benders_integer.jl` | 26, 99 | 1 | — |
| `test_planning_certification.jl` | 181 | 1 | — |
| `test_planning_certification_integer.jl` | 357, 473, 548 | 1 | own `T=2` sites (612, 691) call `build_planning_oracle`/`build_follower` directly, never `build_master` — no literal to audit |
| `test_planning_goldens.jl` | 31, 77, 110 | 1 | — |
| `test_planning_master.jl` (pre-30-02) | 25, 32, 39, 49, 62, 92, 101, 114, 134, 153 | 1 | — |
| `test_planning_master_integer.jl` | 10 occurrences | 1 | — |
| `test_planning_nash.jl` | 13 occurrences | 1 | every `build_shared_transmission(...)` call (11 sites) passes `T=1` explicitly |
| `test_planning_noninteger.jl` | 70, 96 | 1 | — |
| `test_planning_hardening.jl` | 50, 83, 116, 139 | 1 | — |
| `test_planning_hardening.jl` | **267** | **8** | **THE ONLY T>1 site**: `α_op_lb=-50.0, α_x_lb=0.0`, reached via `solve_stackelberg!` (not a direct `build_master` call) |

`src/`-level census (checker BLOCKER 1/2): `src/planning/benders.jl:741`
(`solve_stackelberg!`'s sole `build_master` call site, forwards `master_kwargs`, no literal
of its own) and `src/planning/nash.jl:475` (`run_nash!`'s indirection, forwards
`specs[i].master_kwargs`, always supplies a pre-built `DistributorView` follower). **No T>1
literal reaches `run_nash!` anywhere in this repo today.**

Derivation-formula audit of the one T>1 shape found:
```
test_planning_hardening.jl:267  T=8
  α_op_lb: literal=-50.0  derived=-16.000001000000015  VERDICT=accepted
  α_x_lb:  literal=0.0  derived=-1.0e-6  VERDICT=accepted
```
(`ALPHA_LB_REJECTION_TOL = 1e-6`.) The pre-fix literal this same file's own header comment
documents as invalid, `-5.0`, WOULD be rejected (`-5.0 > -16.000001 + 1e-6` is `true`) —
confirmed independently in `test_planning_master.jl`'s own item 5.

**Verdict: no previously-unknown invalid bound found.** The only T>1 site is ALREADY-fixed
(from the originally-invalid `-5.0` to the now-valid `-50.0`), and the new derivation formula
accepts it exactly as 30-RESEARCH.md's own prediction anticipated.

**Discrepancy with RESEARCH.md Pitfall 4 — resolved, RESEARCH.md was WRONG on this point.**
30-RESEARCH.md's Pitfall 4 asserted that `test_planning_hardening.jl`'s `α_op_lb=-5.0` at
T=8 is **invalid**. The independently re-run audit (this phase, `30-ALPHA-AUDIT.md` Step 2)
found the IN-REPO literal at the time of this phase's audit is actually **`-50.0`**, not
`-5.0` — the file had already been fixed (presumably during the Phase 26-29 correctness
work) from the originally-invalid `-5.0` to a valid `-50.0`, and RESEARCH.md's claim was
checked against a stale reading of the file. The new derivation formula's own verdict table
shows explicitly: `-50.0` (today's literal) is **accepted** (`derived minimum=-16.000001`),
while `-5.0` (the OLD, pre-fix literal RESEARCH.md was describing) WOULD be rejected by the
same formula. Both facts are therefore true and consistent: RESEARCH.md's underlying
mathematical claim (`-5.0` is invalid at T=8) is correct, but its claim that this invalid
value is what's **currently in the repo** is outdated — the file was already corrected
before this phase's audit ran. No new fix was needed as part of Phase 30; the audit is a
confirmation of an already-landed correction plus a forward-looking live-validation wire-up
(below).

**Live-validation wiring (plan 30-04):** `solve_stackelberg!` now ALWAYS constructs and
threads `bounds_ctx` into `build_master` on every `master === nothing` call path (including
through `run_nash!`'s `master_kwargs` literal) — `α_op_lb` is validated unconditionally;
`α_x_lb` is validated wherever a sound derivation exists (a `follower_kwargs` `NamedTuple` or
a pre-built `FollowerLP`), and honestly SKIPPED (never silently passed) for `DistributorView`
pooled-capacity coupling, which has no sound per-object relaxed minimum. Confirmed: zero
regression on every one of the ~90 pre-existing explicit-bound `build_master` call sites
(byte-identical resolution path when `bounds_ctx === nothing`), per plan 30-02's own Task 2
acceptance criteria and plan 30-04's full `test_planning_nash.jl` regression run (Nash
results unchanged).

**Measured constants (superseded in part by the code-review pass, WR-03/WR-04):** the
margin applied is now scale-aware and measured per instance,
`max(1e-6, 10·gap, 1e-8·|optimum|)` with `gap` the derive solve's own duality gap, and
rejection compares against the UN-margined optimum plus that slack (the old rule's
margin and tolerance cancelled to zero tolerance). Re-measured derive gaps: toy T=1/T=8
`2.9e-9`/`2.5e-8` (floor dominates, unchanged), IEEE-13 T=4 `1.5e-6`–`4.5e-6`, T=24
`4.2e-5` — the old absolute `1e-6` sat below the solver's own error on the IEEE-13
instances. Original text: `ALPHA_LB_MARGIN = ALPHA_LB_REJECTION_TOL = 1e-6`, derived from ONE
shared probe (the toy two-bus/`ToyElasticDevice` fixture at T=1, mirroring
`test_planning_master.jl`'s own fixture): oracle primal/dual gap `~2.85e-9`, follower gap
`0.0` exactly (trivial `x_inv=x_op=0` LP optimum) — `max(1e-6, 10*max_gap)` is dominated by
the `1e-6` floor in both cases, so one probe sufficed for both constants.

## 5. Design deviations (restated honestly, not silently reconciled)

- **(30-03)** No population retuning was needed for the T=4 IEEE-13 fixture — contradicts
  30-RESEARCH.md's own earlier measurement of the identical recipe as infeasible at `z=0`
  (see point 1/3 above). Attributed to Phase 26-29's exactness/complementarity-gate fixes
  landing between RESEARCH.md's probe and this plan's execution, not a modeling error in
  either document.
- **(30-04)** W2 overhead (checker-flagged): `derive_alpha_op_lb`'s one-time relaxed solve
  costs ~13.1ms on the toy two-bus/`ToyElasticDevice` fixture, vs. ~695.5ms for a full
  `solve_stackelberg!` best-response — **~1.9% overhead per `build_master` call**, now paid
  unconditionally through every `solve_stackelberg!`/`run_nash!` best-response (20-iteration
  average each). **Carried forward explicitly for Phase 31's own FINDINGS** (this is an
  always-on cost from this phase forward, not a one-time setup cost).
- **(30-04)** `DistributorView`'s `α_x_lb` build-time validation is deliberately SKIPPED (not
  silently passed) — no sound per-object relaxed minimum exists for its pooled-capacity
  coupling. The universal runtime floor guard (`_assert_epigraph_floor`) remains the
  defense-in-depth for this case.
- **(30-04)** One pre-existing, unrelated `1 Broken` test item was observed consistently
  across full regression runs including `test_planning_nash.jl`/
  `test_planning_benders_integer.jl` (e.g. `376 pass / 1 broken / 0 fail / 377 total`, exit 0).
  Grepped every included file for `@test_broken`/`broken=` — zero matches anywhere, including
  this phase's own new files. Not attributable to any file this phase touches; logged per the
  Scope Boundary rule as pre-existing, out-of-scope. (This matches the Phase-29 close
  baseline's own recorded `5 broken` count — see the certification section below; this single
  item is one of those five, not a new regression.)
- **(30-05)** The cross-check tolerance formula needed a third source beyond the plan's own
  two-source recipe (see point 1 above) — a found, documented refinement, not a
  contradiction.
- **(30-05)** The T=24 Literate run required a tighter investment ceiling than the T=4
  headline test's kwargs, to avoid a genuine `assert_battery_complementarity!` violation
  under the full 24-hour price swing — a known limitation of the T=4-tuned population at T=24
  scale, recorded here rather than hidden.
- **Process note (30-05, carried forward per this plan's own `<findings_must_include>`):**
  the 30-05 executor's backgrounded T=24 Literate verification run died when the prior
  agent session paused mid-execution (the sandboxed Bash tool's background/detached-process
  survival limit — see the memory note `background-suite-orphan-race` and the Phase 29
  precedent below). It was re-run detached (`nohup setsid`) and polled to completion in a
  follow-up turn, producing the fully trustworthy exit-code-0 confirmation (`~130s` wall
  time) reported in point 1 above. The underlying script and its numbers were unaffected —
  this was purely a verification-robustness step, not a code change.
- **Process note (cross-referenced from Phase 29, same class of issue this plan's own
  Task 2 handoff design exists to prevent):** Phase 29's own 29-03 closing plan hit the
  identical sandboxed-background-process-survival limitation in its own `Pkg.test()`
  certification step — three overlapping, uncoordinated `Pkg.test()` launches landed before
  the orchestrator intervened, killed all three, and ran the one clean certified suite
  itself (HEAD `a5e9900`, see `29-FINDINGS.md`'s own "Process deviation" section). This
  plan's Task 2 (below) makes that same handoff the documented, planned design for Phase 30
  rather than repeating it as an ad hoc mid-execution deviation.

## 6. Golden-move audit result

**The plan's own `<verify>` script picks the WRONG base commit — found bug, auto-fixed
(Rule 1), documented, not silenced.** The plan's literal verify command (`BASE=$(git log
--oneline --all | grep -i "29-03\|phase 29" | tail -1 | cut -d' ' -f1)`) resolves to
`990b51c` (`docs(29-03): golden-move audit + consolidated phase findings`) — an
**intermediate** Phase-29 commit, not the actual Phase-29 **close** commit. Three further
Phase-29 code-review commits (`78e5066`/`310f59b`/`817734b`/`ec36025`/`07b3822`, the WR-01/
04/05/07/08 fixes) and two closing-docs commits (`a98ac98`/`e5dc782`) landed AFTER `990b51c`
and BEFORE Phase 30's own first commit. Running the audit against `990b51c` therefore
incorrectly attributes Phase 29's OWN post-`990b51c` code-review diffs to Phase 30, flagging
2 "unattributed" golden-looking lines (exit code 1):

```
test/test_planning_certification_bilevel.jl:148->161          NONE -> 1e-7
test/test_planning_certification_bilevel_interior.jl:170->179 NONE -> 1e-6
```

Direct verification (`git diff 990b51c..e5dc782 --stat -- <both files>` shows 328 combined
line changes from 5 Phase-29 WR-* commits; `git diff e5dc782..HEAD --stat -- <both files>`
shows **zero** changes) confirms these two lines are entirely Phase-29's own work, landed
before Phase 30 began — **not** Phase 30 golden moves at all.

**Correct base:** `e5dc782` (`docs(29-03): complete [phase close] plan`) — the actual final
commit of Phase 29's own closing plan 29-03, the true "state of the repo when Phase 30
began." STATE.md's own recorded Phase 29 P03 close entry (the `Performance Metrics` table's
"Phase 29 P03 | 90min | 2 tasks | 2 files" row) and 29-FINDINGS.md's own certification
section (final commits `a98ac98`/`e5dc782` postdating the certified-suite HEAD `a5e9900`)
corroborate this is the correct close point, not a guess.

**Audit result at the correct base:**
```
python3 .planning/.../scripts/audit_goldens.py --base e5dc782 --head HEAD
# Golden-move audit: e5dc782..HEAD -- test/
Total flagged numeric-literal moves: 0
Attributed: 0  Allowlisted: 0  Unattributed: 0
AUDIT_EXIT: 0
```

**Exit code 0, zero flagged moves at all** (not zero-unattributed-among-many-flagged) —
confirming Phase 30 only ADDS new named constants (`ALPHA_LB_MARGIN`,
`ALPHA_LB_REJECTION_TOL`, the BILEV-03 three-source cross-check tolerance, the
feasibility-oracle's empirically-verified sign `u=+dual.(pin)`, etc.) and never touches,
moves, or re-pins any pre-existing golden value.

---

## READY FOR ORCHESTRATOR SUITE CERTIFICATION

**HEAD sha:** `38b2e05` (`docs(30-06): golden-move audit + consolidated phase findings` —
this plan's own Task 1 commit). `git status --short` is clean at this sha: all Phase 30
work (plans 30-01 through 30-05, plus this plan's Task 1 findings) is committed; there were
no outstanding `src/`/`test/` changes left for this Task 2 to commit.

**Preconditions confirmed:**

1. `git worktree list` — **no `.claude/worktrees/agent-*` entries.** Two UNRELATED, stale
   worktrees exist at a different path pattern (`TSO-DSO.worktrees/operational-planning-
   integration` on branch `agents/operational-planning-integration`, last commit
   2026-08-29; `TSO-DSO.worktrees/pdf-documentation-thesis-results` on branch
   `agents/pdf-documentation-thesis-results`, last commit 2026-07-25) — these do NOT match
   the `background-suite-orphan-race` contamination pattern (which is specifically about
   live `.claude/worktrees/agent-*` sessions doubling the reported suite count), are weeks
   stale, and are outside this repo's own `test/`/`src/` tree scope. Reported here per the
   plan's own "report, don't silently pass" instruction; not treated as a blocking
   precondition failure since the pattern genuinely doesn't match.
2. No stale `Pkg.test`/julia processes running — confirmed via `ps aux | grep -i
   "julia\|Pkg.test"` (filtered of self-matching grep/pgrep artifacts): zero real matches.
3. `git status --short` clean at HEAD `38b2e05`; all Phase 30 work committed.

**Phase-29 close baseline to compare against:** **30871 pass / 0 fail / 0 error / 5
broken** (recorded in `29-FINDINGS.md`'s own certification section, HEAD `a5e9900`,
confirmed unchanged through the two subsequent docs-only closing commits `a98ac98`/
`e5dc782`).

**This phase's new/extended test files** whose `@testitem`s should be added to that
baseline when the orchestrator certifies:
- `test/test_planning_feasibility_oracle.jl` (new, plan 30-01; extended, plan 30-04)
- `test/test_planning_ac_recheck.jl` (new, plan 30-01)
- `test/test_planning_noninteger.jl` (PVAL-04 registry addition, plan 30-01)
- `test/test_planning_master.jl` (7 new `@testitem`s, plan 30-02)
- `test/fixtures_planning_ieee13_short.jl` (new `@testmodule`, plan 30-03)
- `test/test_planning_ieee13_short_fixture.jl` (new, plan 30-03)
- `test/test_planning_alpha_bounds_stackelberg.jl` (new, plan 30-04)
- `test/test_planning_inexact_policy.jl` (new, plan 30-04)
- `test/test_planning_benders_ieee13.jl` (new, plan 30-05)

**Fail/error must stay 0. Broken must stay 5** (Phase 30 adds no new `@test_broken`,
confirmed by a grep finding zero `@test_broken`/`broken=` matches in any file this phase
touches — see the "Design deviations" section above).

**This plan's own executor never launches, polls, or waits for `Pkg.test()`.** The
ORCHESTRATOR is responsible for: launching the single detached `julia --project=. -e
'import Pkg; Pkg.test()'` run via its own persistent background-process mechanism,
confirming the log's first timestamp postdates HEAD `38b2e05`, filtering for zero
`.claude/worktrees/` contamination, comparing the final tallies against the baseline above,
and appending those final tallies directly into this file (or resuming this plan with the
tallies for a follow-up write-up step).

<!-- ORCHESTRATOR: append certified full-suite tallies below this line once the run completes. -->
