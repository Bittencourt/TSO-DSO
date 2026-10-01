# Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder - Research

**Researched:** 2026-10-01
**Domain:** Julia/JuMP convex optimization — Benders decomposition with an SOCP (second-order
cone) branch-flow subproblem, feasibility-cut generation, and automatic epigraph-bound
derivation
**Confidence:** HIGH (every load-bearing claim below was verified by executing the REAL
production code — `build_planning_oracle`/`solve_planning_oracle!`/`build_master`/
`build_follower`/`assert_socp_exact!`/`assert_solved!` — against the real `ieee13_modified()`
feeder in this session; no claim about feasibility/inexactness/timing/bound-validity is
assumed from training data)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Benchmark fixture & convergence certification (BILEV-03)**
- Fixture: `ieee13_modified()` with a short multi-period horizon (T≈3–6), reusing existing
  IEEE-13 aggregator/device populations from the experiments layer.
- Convergence is certified by BOTH a closed LB/UB gap ≤ tol AND a cross-check against an
  independently solved monolithic (extensive-form joint) problem on the identical instance.
  The comparison tolerance is MEASURED (solver duality gaps / MIP tolerances), never picked.
- In-suite test budget ≈ ≤2 min. A larger T=24 IEEE-13 run lives as a Literate experiment
  script (runnable, documented), not a suite test.
- Use the DEFAULT (Gan–Low) exactness copy. Do not assume exactness: report the cone gap at the
  incumbent (Phase 28 showed the default is not unconditionally cone-exact).

**Oracle feasibility cuts (BILEV-04a)**
- Mechanism: a second, built-ONCE slack-minimization feasibility oracle with z as a JuMP
  `Parameter`: minimize ‖s‖₁ subject to the full network with the pin relaxed to
  `p_import = z + s⁺ − s⁻`. Its pin dual yields the cut `v + u'(z − z_k) ≤ 0`, in the SAME form
  as the existing `add_feasibility_cut!`. No Farkas-ray extraction from solver certificates.
- Coverage: separate fixtures for a voltage-infeasible pin and a thermal-infeasible pin, each
  shown to (a) produce a feasibility cut and (b) still let the loop converge.
- Loop order: follower feasibility check first (existing WR-01 behavior), then oracle
  feasibility, then the optimality cut. A feasibility cut never updates UB (T-11-06).

**SOCP-inexactness policy at a pinned z (BILEV-04b)**
- New keyword `inexact_policy`, default `:certify_incumbent`: a cut from the SOC relaxation is a
  valid under-estimator of the RELAXED value function, so it is accepted and its cone gap
  logged; at termination the incumbent is certified with the exactness gate; if the incumbent is
  inexact, a physical AC re-check via `ACPowerFlow(limits=false)` (per project memory:
  fixed-dispatch SOCP re-solves are structurally inexact) is run and its violation REPORTED on the
  result — never thrown, never silently passed.
- Also provide `:strict` (today's throw — the current `assert_socp_exact!` behavior) and
  `:reject` (skip the inexact cut, report it), each covered by a test.
- `BendersTrace` gains per-iteration `socp_maxgap` and a policy-action column.
- Inexactness test fixture: a pinned z that MEASURABLY produces a slack cone, found by search and
  recorded with its measured gap — not a synthetic forced case.

**Automatic α lower bounds (BILEV-05)**
- Derivation by relaxed solves once at setup: `α_op_lb` = oracle optimum with the pin freed over
  z ∈ [0, y_max]; `α_x_lb` = the follower's relaxed minimum; each lowered by a MEASURED
  solver-tolerance margin.
- API: `α_op_lb = :auto` / `α_x_lb = :auto` become the default; explicit numbers are still
  accepted but validated.
- Rejection of an over-high user bound, two layers: build-time (user bound > derived minimum + tol
  → `ArgumentError`) and runtime (any evaluated `Q_j` below the bound in force → error). If an
  existing test turns out to have been passing an invalid bound, that is reported as a found bug,
  not silenced or re-pinned.

### Claude's Discretion
- Exact T within 3–6, exact tolerance values (must be measured), file/module layout of the
  feasibility oracle, and naming of new trace columns/result fields.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Out-of-phase-boundary items, restated from
CONTEXT.md's `<domain>` block: the genuinely-bilevel KKT path (Phase 29, done), GNE/Nash
fixtures and integer N>1 (Phase 31), IEEE-8500 scale (Phase 35).)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BILEV-03 | `solve_stackelberg!` runs with `ConvexBranchFlow` on a multi-bus feeder (IEEE-13) and T>1 inside the Benders loop, converging with a closed LB/UB gap. | §"Finding 1" (measured oracle solve time ~25–80ms/iteration, confirms ≤2min budget); §"Finding 2" (the narrow feasible-and-exact z window on the real feeder, needed to pick a T=3–6 population that actually converges); §Code Examples (working T=4 oracle-build recipe); §"monolithic cross-check" pattern (reuses Phase 29's `build_joint_reference` idiom). |
| BILEV-04 | The planning oracle produces feasibility cuts for voltage-/thermally-infeasible pinned z, and handles SOCP inexactness via a documented policy. | §"Finding 2/3" (concrete thermal- and voltage-infeasible z values, isolated by the relax-one-constraint-at-a-time diagnostic); §"Finding 4" (measured, naturally-occurring inexact pin z=0.06 on the real feeder, not synthetic); §"Finding 5" (the `ACPowerFlow(limits=false)` re-check requires bypassing `solve_planning_oracle!`/`solve_with_retry!` — `allow_local` is not threaded through either; verified working via a direct `assert_solved!(...; allow_local=true)` call); §Architecture Patterns (feasibility-oracle design, slack-based cut). |
| BILEV-05 | `α_op_lb`/`α_x_lb` derived automatically; an over-high user bound is detected and rejected. | §"Finding 6" (relaxed-oracle derivation verified numerically: `α_op_lb = -max_{z∈[0,y_max]^T} welfare(z)` computed via a box-bounded, pin-free one-time model, confirmed to upper-bound every pinned welfare value tried); §"Finding 7" (CONCRETE existing-test risk: ~90 call sites across 10 test files hardcode `α_op_lb=-5.0`, and `test_planning_hardening.jl` ALREADY documents that `-5.0` is an INVALID/too-tight bound at T=8 on its own fixture — the new validation must be run against every T>1 call site before BILEV-05 ships). |

</phase_requirements>

## Summary

This phase wires the already-production `PlanningOracle` (`ConvexBranchFlow`, the SOCP
branch-flow relaxation) into `solve_stackelberg!`'s Benders loop on a REAL multi-bus feeder
(`ieee13_modified()`, 11 buses / 10 branches) with T>1, instead of the toy 2-bus/T=1 fixture
every existing planning test uses. All prior planning-layer work (Phases 10–29) was built and
tested exclusively on toy fixtures where the oracle is essentially always feasible and always
exact; this phase is the first to actually exercise `assert_socp_exact!`'s throw path and
`solve_with_retry!`'s genuine-`INFEASIBLE` path from INSIDE the Benders loop, which is exactly
why BILEV-04/05 exist as separate requirements.

Live experimentation this session (not training-data guesses) on the real `ieee13_modified()`
feeder with a small T=4 aggregator population (PVBattery + Thermostatic, same calibration
style as `Phase4Fixtures.build_ieee13_ground_aggregators`) established FIVE concrete, load-bearing
facts: (1) the oracle's feasible-AND-exact window for a uniform hourly import pin on this feeder
is narrow (`z ∈ [0.01, 0.05]` pu/hr in the tested population; `z=0` itself is infeasible — the
toy follower's "z=0 is always feasible" invariant does NOT hold for the real network oracle);
(2) stepping just past that window (`z=0.06`) gives a NATURALLY-OCCURRING SOCP-inexact point
(measured cone-gap ratio ≈4852×, no synthetic injection needed) — exactly the BILEV-04b fixture
CONTEXT.md requires; (3) stepping further (`z≥0.0686`, the head branch's real thermal limit)
gives a genuine `MOI.INFEASIBLE` — confirmed THERMAL (not voltage) by a relax-one-constraint
ablation; (4) a genuinely VOLTAGE-only infeasibility requires either a dedicated
unconstrained-thermal fixture (e.g. reusing the project's existing `high_pv_feeder()` /
over-voltage stress-fixture pattern) or a much larger `z` on a thermally-widened IEEE-13 variant
— on the REAL unmodified feeder, thermal ALWAYS binds first as `z` grows, so "the" voltage-cut
fixture cannot be the same uniform-pin sweep as the thermal one; (5) the CONTEXT.md-specified
`ACPowerFlow(limits=false)` AC re-check CANNOT be done by calling `solve_planning_oracle!` on an
`ACPowerFlow`-built oracle as-is — `solve_with_retry!` has no `allow_local` passthrough and
`assert_solved!` defaults to rejecting Ipopt's `LOCALLY_SOLVED` status — the existing
`_mpc_truth_import_acpf` pattern (direct `assert_solved!(...; allow_local=true, dual=false)`,
bypassing the retry wrapper entirely) is the only path confirmed to work, and it is SLOW (≈15s
for one T=4 NLP solve versus ≈30ms for the SOCP), which locks in CONTEXT.md's own design choice
that this re-check must run ONCE on the converged incumbent, never per-iteration.

**Primary recommendation:** build the T=3–6 IEEE-13 convergence fixture with a FRESH, modest
aggregator population (not a verbatim reuse of `Phase4Fixtures.build_ieee13_ground_aggregators`,
whose `Deferrable` window `[8,16]` does not fit T<16); size battery/PV capacity generously enough
that `z=0` is balance-feasible (unlike this session's exploratory population) so the Benders
loop's natural trial range stays inside the feasible-and-exact window most of the time; build the
feasibility-cut fixtures as SEPARATE, purpose-built small feeders (one thermally-tight, one
voltage-tight/thermally-unconstrained) rather than trying to force both failure modes out of one
population; implement the BILEV-04b AC re-check as a direct `assert_solved!(...;
allow_local=true, dual=false)` call on a fresh `ACPowerFlow(limits=false)`-built context (mirror
`_mpc_truth_import_acpf`, do not reuse `solve_planning_oracle!`); implement BILEV-05's `α_op_lb`
as `-objective_value` of a ONE-TIME, pin-free, box-bounded (`0 <= p_import[t] <= y_max`) relaxed
rebuild of the oracle's network (not a reuse of `PlanningOracle`'s Parameter/pin machinery, which
cannot be "freed" without rebuilding); and, before shipping BILEV-05's rejection gate, audit
EVERY existing `α_op_lb=-5.0` call site at `T>1` against the new derivation formula — this is a
real, concrete bug-finding opportunity the user explicitly asked to surface, not silence.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Benders outer loop orchestration (`solve_stackelberg!`) | Optimization orchestration (`src/planning/benders.jl`) | — | Hand-rolled, build-once/re-solve-many loop; no network/API tier involved (research library, not a service) |
| Operational welfare subproblem / SOCP relaxation (`PlanningOracle`) | Optimization model layer (`src/planning/subproblem.jl` + `src/powerflow/ConvexBranchFlow.jl`) | Solver (Clarabel via `select_optimizer`) | The SOCP branch-flow physics and exactness gate live here; Clarabel is the execution backend behind the solver-abstraction factory |
| NEW: oracle feasibility-cut sub-oracle (slack-min) | Optimization model layer (new file under `src/planning/`, e.g. `feasibility_oracle.jl`) | Solver (same Clarabel/HiGHS factory, formulation-generic) | A second, independent JuMP model built once — not a variant of `PlanningOracle`, per CONTEXT.md's explicit "no Farkas-ray extraction" decision |
| NEW: AC physical re-check at the incumbent | Optimization model layer (reuses `contribute!(::ACPowerFlow, ...)`, new thin wrapper, NOT `solve_planning_oracle!`) | Solver (Ipopt) | Must bypass `solve_with_retry!`/`solve_planning_oracle!` entirely (verified: neither accepts Ipopt's `LOCALLY_SOLVED`); mirrors `_mpc_truth_import_acpf`'s established direct-`assert_solved!` pattern |
| NEW: automatic α-bound derivation | Optimization model layer (new one-time relaxed model builds, called from `build_master`/`solve_stackelberg!` setup) | — | A genuinely different model (box-bounded `p_import`, no pin) from both `PlanningOracle` and the relaxed `FollowerLP`; must be built once at setup, discarded after use |
| Benders master LP (`BendersMaster`) | Optimization model layer (`src/planning/master.jl`) | Solver (HiGHS) | Unchanged structurally; gains `:auto` bound validation |
| Convergence/diagnostics ledger (`BendersTrace`) | Diagnostics/reporting (`src/planning/trace.jl`) | — | Pure data, no JuMP — gains `socp_maxgap`/policy-action columns |
| Test/verification harness | Test tier (`test/test_planning_*.jl`, direct Julia scripts) | — | TestItemRunner does not resolve under `--project=.` in this repo (established project hazard) — executors must additionally verify via direct scripts |

## Standard Stack

No new external packages are introduced by this phase. Every library needed
(`JuMP`, `Clarabel`, `HiGHS`, `Ipopt`) is already a direct dependency in `Project.toml`
(verified: `Clarabel = "0.11.1"`, `HiGHS = "1.24.1"`, `Ipopt = "1.15.0"`, `JuMP = "1.30.1"`,
`[VERIFIED: Project.toml, this repo]`). The phase is pure in-tree Julia code: new files/functions
under `src/planning/`, reusing `select_optimizer`/`problem_class` (the existing solver-abstraction
factory, CLAUDE.md-mandated) and `contribute!(::ACPowerFlow, ...)` (already shipped, Phase 15/27).

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 [VERIFIED: Project.toml] | Algebraic modeling (oracle, feasibility oracle, master, follower, relaxed-bound models) | Already the project's sole modeling layer (CLAUDE.md mandate) |
| Clarabel | 0.11.1 [VERIFIED: Project.toml] | SOCP solve for `ConvexBranchFlow`-routed oracles | Project-standard conic solver (CLAUDE.md mandate); confirmed in this session to solve a T=4 IEEE-13 oracle re-solve in ~25–30ms |
| HiGHS | 1.24.1 [VERIFIED: Project.toml] | LP solves (master, follower, NEW feasibility oracle if `ConvexBranchFlow`'s own SOCP routing is NOT used for the slack-min oracle — see Open Questions) | Project-standard LP/MILP solver |
| Ipopt | 1.15.0 [VERIFIED: Project.toml] | `ACPowerFlow(limits=false)` physical re-check at the incumbent (BILEV-04b) | Confirmed in this session: reaches `LOCALLY_SOLVED`/`Solve_Succeeded` on the measured-inexact pin in ~15s (T=4) |

### Supporting
None new.

### Alternatives Considered
Not applicable — no new library decision in scope; all tooling is already locked by CLAUDE.md.

**Installation:** none required.

## Package Legitimacy Audit

Not applicable — this phase installs zero external packages. The Package Legitimacy Gate is
skipped per its own "whenever this phase installs external packages" scope condition.

## Architecture Patterns

### System Architecture Diagram

```
                         solve_stackelberg!  (src/planning/benders.jl, outer loop)
                                      │
            ┌─────────────────────────┼──────────────────────────────┐
            ▼ (build ONCE, before loop)                               │
   ┌──────────────────┐   ┌──────────────────┐   ┌─────────────────┐ │  ┌────────────────────────┐
   │ BendersMaster     │   │ PlanningOracle    │   │ FollowerLP      │ │  │ NEW: Feasibility oracle │
   │ (LP, HiGHS)       │   │ (SOCP, Clarabel)  │   │ (LP, HiGHS)     │ │  │ (slack-min, same class  │
   │ α_op_lb, α_x_lb   │   │ pin p_import=z    │   │ pin x_op=z      │ │  │ as the oracle, pin      │
   │   :auto (NEW) or  │   │                   │   │                 │ │  │ relaxed to z+s+-s-)     │
   │   explicit+valid  │   └──────────────────┘   └─────────────────┘ │  └────────────────────────┘
   └──────────────────┘            ▲                      ▲            ▲            ▲
            │  z_k                 │ re-solve             │ re-solve   │            │
            ▼                      │ (Parameter)          │ (Parameter)│            │
   ┌──────────────────┐            │                      │            │            │
   │ for k in 1:max_iter:          │                      │            │            │
   │  lb=solve_master!             │                      │            │            │
   │  fr=solve_follower!(z_k) ─────┘                      │            │            │
   │   infeasible? → add_feasibility_cut!, continue (never UB)         │            │
   │  or=solve_planning_oracle!(z_k) ──────────────────────┘           │            │
   │   assert_socp_exact! throws? → inexact_policy dispatch: ──────────┘            │
   │     :strict  → rethrow (today's behavior)                                      │
   │     :reject  → skip cut, log, continue                                         │
   │     :certify_incumbent → ACCEPT cut from relaxed value fn, log socp_maxgap     │
   │   oracle genuinely MOI.INFEASIBLE (no exactness issue)? → call NEW             │
   │     feasibility oracle at z_k ─────────────────────────────────────────────────┘
   │     feasible-but-infeasible-at-pin → pin-dual cut v+u'(z-z_k)<=0, continue (never UB)
   │  else: add_optimality_cut! (:op, :x), update incumbent UB, converge check      │
   │ END LOOP                                                                        │
   │ AT CONVERGENCE (ONCE, not per-iter):                                            │
   │   assert_socp_exact! on incumbent → if inexact: build ACPowerFlow(limits=false) │
   │   oracle pinned at incumbent z, assert_solved!(...;allow_local=true,dual=false),│
   │   REPORT violations (never throw)                                               │
   └──────────────────────────────────────────────────────────────────┘
            │
            ▼
   Independent MONOLITHIC joint model (BILEV-03 cross-check; separate JuMP build,
   same pattern as Phase 29's build_joint_reference — NOT a reuse of the Benders pieces)
```

### Recommended Project Structure
```
src/planning/
├── benders.jl              # solve_stackelberg! — gains inexact_policy kwarg, oracle-
│                            #   feasibility-cut branch, :auto α-bound wiring
├── subproblem.jl            # PlanningOracle — UNCHANGED structurally (its own exactness
│                            #   gate stays :strict-only; the POLICY lives in benders.jl,
│                            #   which decides what to DO when subproblem.jl throws)
├── feasibility_oracle.jl    # NEW — the slack-min second oracle (BILEV-04a)
├── ac_recheck.jl            # NEW — the incumbent-only ACPowerFlow(limits=false) re-check
│                            #   (BILEV-04b), mirrors _mpc_truth_import_acpf's direct-
│                            #   assert_solved! pattern
├── alpha_bounds.jl          # NEW — the one-time relaxed-oracle / relaxed-follower
│                            #   derivation (BILEV-05)
├── master.jl                # build_master — α_op_lb/α_x_lb gain Union{Symbol,Real},
│                            #   :auto resolution + over-high-bound ArgumentError
├── follower.jl               # UNCHANGED (or gains a `build_follower_relaxed` sibling for
│                            #   the α_x_lb derivation, consistent with feasibility_oracle.jl
│                            #   being a SEPARATE model, never a mutated copy)
└── trace.jl                 # BendersTrace — gains socp_maxgap_trace, policy_action_trace
```

### Pattern 1: Diagnose infeasibility cause by relaxing ONE constraint family at a time
**What:** Before writing a "thermal-infeasible" or "voltage-infeasible" fixture, build a second
copy of the feeder with ONLY the suspected constraint widened (e.g. `smax` to a large sentinel,
or `vmin`/`vmax` to a wide band) and re-run the SAME pinned-z solve. If widening constraint X
turns a genuine `MOI.INFEASIBLE` into either `OK` or `SOCP relaxation INEXACT` (a different,
non-infeasible failure mode), X was the binding cause. If it changes nothing, X was NOT the
cause — some other constraint (thermal, voltage, or DEVICE capacity) is.
**When to use:** Classifying BILEV-04a's two required fixtures (voltage- vs thermal-infeasible)
BEFORE writing them, since a given z can be infeasible for reasons that have nothing to do with
the network at all (see Pitfall 1 below).
**Example (measured this session, `JULIA_LOAD_PATH="test:.:@stdlib" julia script.jl`):**
```julia
# feeder0 = TSODSO.ieee13_modified(); aggs = <T=4 population>
function widen_smax(feeder; smax=90.0)
    branches2 = [TSODSO.Branch(br.from, br.to, br.r, br.x, smax) for br in feeder.branches]
    return TSODSO.Feeder(feeder.buses, branches2, feeder.root)
end
oracle0 = TSODSO.build_planning_oracle(feeder0, TSODSO.ConvexBranchFlow(), aggs; λ₀=λ0, T=4)
TSODSO.solve_planning_oracle!(oracle0, fill(0.0686, 4))   # THROWS: MOI.INFEASIBLE
oracleS = TSODSO.build_planning_oracle(widen_smax(feeder0), TSODSO.ConvexBranchFlow(), aggs; λ₀=λ0, T=4)
TSODSO.solve_planning_oracle!(oracleS, fill(0.0686, 4))   # SOLVES (feasible), but SOCP-INEXACT
# => the z=0.0686 infeasibility on the UNMODIFIED feeder is THERMAL, not voltage.
```

### Pattern 2: The incumbent-only AC re-check must bypass `solve_planning_oracle!`
**What:** `solve_planning_oracle!` always routes through `solve_with_retry!`, whose
`assert_solved!` call defaults `allow_local=false` and has NO keyword to change that. An
`ACPowerFlow`-built oracle genuinely reaches `termination_status = LOCALLY_SOLVED` /
`raw_status = "Solve_Succeeded"` — a real, trustworthy Ipopt success — but `is_solved_and_feasible`
rejects `LOCALLY_SOLVED` under the default gate, so the call throws even though the AC solve
succeeded.
**When to use:** Any time `ACPowerFlow`/Ipopt's NLP result needs to be accepted, per project
convention: `_mpc_truth_import_acpf` (`src/experiments/mpc_loop.jl:1557`) already does this
correctly.
**Example (Source: this session's direct probe, confirmed working):**
```julia
oracle_ac = TSODSO.build_planning_oracle(feeder0, TSODSO.ACPowerFlow(; limits=false), aggs; λ₀=λ0, T=4)
set_parameter_value.(oracle_ac.z, z_incumbent)
TSODSO.assert_solved!(oracle_ac.model; dual = false, allow_local = true)   # the ONLY path that works
# termination_status = LOCALLY_SOLVED, raw_status = "Solve_Succeeded" — genuinely trustworthy.
```

### Pattern 3: Deriving `α_op_lb` requires a genuinely separate, pin-free model
**What:** `PlanningOracle.z` is a JuMP `Parameter` tied to an EQUALITY pin
(`p_import[t] == z[t]`); you cannot "free" that pin into an inequality box by re-setting the
Parameter's value — it stays an equality at whatever value you set. The CONTEXT.md-specified
derivation ("oracle optimum with the pin freed over z ∈ [0, y_max]") requires building a SECOND,
one-time model with `p_import[t]` as a genuinely bounded VARIABLE (`0 <= p_import[t] <= y_max`),
no Parameter, no pin, reusing `contribute!(pf, ctx, feeder; T)` verbatim (the same builder
`PlanningOracle` uses) and the same aggregator writers.
**When to use:** BILEV-05's `α_op_lb = :auto` resolution, called ONCE at `solve_stackelberg!`
setup (or `build_master` setup, if the oracle has already been built by then).
**Example (Source: this session's direct probe, numerically confirmed to upper-bound every
pinned welfare value tried):**
```julia
@variable(model, 0 <= p_import[t=1:T] <= y_max)   # NOT a Parameter, NOT pinned to a specific z
# ... same contribute!/balance/objective wiring as build_planning_oracle ...
TSODSO.solve_with_retry!(model; dual=true)
α_op_lb = -objective_value(model)   # = -(max welfare over the box) — a valid global lower bound
```
Measured on the T=4 IEEE-13 fixture, `y_max=0.1`: relaxed welfare optimum `-609.008659` ⇒
`α_op_lb = 609.008659`; every tested pinned-z welfare (`z∈{0, 0.01, …, 0.05}`) was `≤` the
relaxed optimum (`-609.047 ≤ -609.009`, etc.) — confirming it IS a valid epigraph bound.

### Anti-Patterns to Avoid
- **Reusing `Phase4Fixtures.build_ieee13_ground_aggregators` verbatim for the T=3–6 fixture:**
  its `Deferrable` device has a HARDCODED window `[8,16]` and `generate_profiles(...; T=24)` — it
  cannot shrink to `T<16` without an `ArgumentError` from `Deferrable`'s own window-validity
  guard. A NEW, short-horizon population (PVBattery + Thermostatic only, or a `Deferrable` whose
  window is re-parametrized to fit `T∈[3,6]`) must be built for this phase, not a slice of the
  existing one.
- **Assuming `z=0` (or any single "obviously safe" pin) is always oracle-feasible:** confirmed
  false on the real IEEE-13 oracle in THIS session (`z=0` genuinely `MOI.INFEASIBLE` on the
  T=4 population tried) — unlike the toy `FollowerLP`, where `z=zeros(T)` is feasible by
  construction (`build_follower`'s box always includes 0). The real network oracle has NO such
  guarantee; `corner_recourse`'s own docstring already documents this ("CONFIRMED to occur on
  realistic non-separable battery fixtures") — size the new population's PV/battery capacity
  generously enough that the Benders loop's OWN natural starting trials land inside a feasible
  region, rather than assuming any specific z is safe.
- **Classifying an infeasible z as "voltage-infeasible" or "thermal-infeasible" without the
  relax-one-constraint ablation (Pattern 1):** this session found THREE distinct causes behind
  superficially similar `MOI.INFEASIBLE` results on the same fixture family — thermal limit,
  voltage limit, AND device/resource capacity (battery `Pmax`/PV magnitude too small to
  physically deliver the pinned import/export) — the last of which is NOT a network-feasibility
  issue at all and would make a mislabeled fixture.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AC physical feasibility check at a fixed dispatch | A new NLP solve wrapper with bespoke status handling | `assert_solved!(...; allow_local=true, dual=false)` directly, mirroring `_mpc_truth_import_acpf` | Already the project's established, tested pattern for exactly this situation (fixed-dispatch AC re-solve); re-deriving status-acceptance logic risks silently accepting a non-converged Ipopt result |
| Farkas-ray / infeasibility-certificate extraction from Clarabel | Parsing Clarabel's own conic infeasibility certificate (it DOES report one — `dual_status = INFEASIBILITY_CERTIFICATE` was observed in this session) | The CONTEXT.md-mandated slack-minimization second oracle (`minimize ‖s‖₁`, pin relaxed to `z+s⁺-s⁻`), whose ordinary EQUALITY-pin dual gives the cut | CONTEXT.md explicitly locks this decision ("No Farkas-ray extraction from solver certificates") — Clarabel's conic certificate format is solver-internal and not the stable, documented interface `solve_follower!`'s HiGHS Farkas ray is; the slack-oracle approach reuses the SAME dual-read pattern already proven for the follower |
| A custom "is this cone slack" classifier | `assert_socp_exact!`'s own returned `maxgap`/thrown-ratio (already computed) | Catch the throw, read `o.ctx.meta[:socp_maxgap]` before/instead of rethrowing, per `inexact_policy` | The exactness computation (hybrid per-branch floor, FIX-08) is already measured/tuned project-wide; duplicating it risks a second, drifting threshold |

**Key insight:** every "new" piece this phase needs (feasibility oracle, AC re-check, relaxed
α-bound solve) is a SMALL VARIANT of an existing, already-validated model-building pattern
(`contribute!(pf, ctx, feeder; T)` + aggregator writers + balance closure) — never a new power-flow
or device formulation. The risk in this phase is almost entirely in SOLVE-STATUS / GATE PLUMBING
(which function accepts which `TerminationStatus`), not in new physics.

## Common Pitfalls

### Pitfall 1: Not every "infeasible pinned z" is a network feasibility issue
**What goes wrong:** A fixture intended to exercise "voltage-infeasible" or "thermal-infeasible"
feasibility cuts actually exercises a THIRD failure mode: the aggregator population's own
resource capacity (PV magnitude, battery `Pmax`) is too small to physically deliver the pinned
import/export, regardless of network limits. This session measured this directly: on the T=4
IEEE-13 population, pinning `z=-0.2` (export) remained `MOI.INFEASIBLE` even with BOTH voltage
AND thermal limits artificially widened to near-unconstrained — the true cause was battery/PV
capacity, not the network.
**Why it happens:** `solve_with_retry!`/`assert_solved!` report the SAME `MOI.INFEASIBLE`
regardless of WHICH constraint family is responsible; there is no automatic attribution.
**How to avoid:** Use the relax-one-constraint-at-a-time ablation (Architecture Pattern 1) BEFORE
writing a fixture's docstring claim about what kind of infeasibility it exercises.
**Warning signs:** An infeasibility that persists after widening BOTH voltage and thermal bounds
generously.

### Pitfall 2: The real multi-bus oracle's feasible-and-exact z window can be narrow
**What goes wrong:** Choosing a T=3–6 population and a Benders fixture (`y_max`, `corridor_cap`,
follower costs) without first checking where the OPERATIONAL oracle itself is feasible/exact can
produce a master whose proposed trial `z_k` values mostly land in the infeasible or inexact
region, making the loop spend most of its iterations on feasibility cuts or `inexact_policy`
branches instead of genuine progress.
**Why it happens:** The real feeder's thermal limit (`0.0686` pu on the IEEE-13 head branch) is
tight relative to a residential-scale load/PV population; this session measured the
feasible-AND-exact uniform-pin window as roughly `[0.01, 0.05]` pu/hr on one T=4 population — a
span of only `0.04` pu.
**How to avoid:** Before finalizing the convergence fixture's `y_max`/`corridor_cap`, sweep a
handful of candidate `z` values through `solve_planning_oracle!` directly (as this session did)
and confirm the master's natural box `[0, y_max]` mostly overlaps the feasible-and-exact region,
or deliberately include SOME inexact/infeasible iterations if that is the point of the test.
**Warning signs:** The Benders loop converging only after many feasibility-cut iterations, or
never converging within `max_iter`.

### Pitfall 3: `solve_with_retry!`'s retry ladder does NOT help with genuine infeasibility
**What goes wrong:** Assuming the existing retry escalation (`RETRYABLE_STATUSES =
(NUMERICAL_ERROR, SLOW_PROGRESS, ALMOST_OPTIMAL)`) will eventually "fix" an infeasible pinned z.
**Why it happens:** `MOI.INFEASIBLE` is explicitly NOT in `RETRYABLE_STATUSES` (by design,
`retry.jl`'s own docstring) — the loop in `solve_with_retry!` raises immediately on attempt 1 for
a genuine infeasibility, confirmed in this session (every infeasible pin threw on "exhausted 1
attempt(s)", never escalating).
**How to avoid:** The feasibility-oracle branch (BILEV-04a) must be triggered on catching this
specific throw (or, better, on a structured check before calling `solve_planning_oracle!` at all,
if one is cheaply available) — never assumed away by retry tuning.
**Warning signs:** None needed — this is already the observed, confirmed behavior; design around
it directly.

### Pitfall 4: `α_op_lb=-5.0` is ALREADY documented as invalid at larger T, on the SAME shared toy fixture most planning tests use
**What goes wrong:** Roughly 90 call sites across 10 test files (`test_planning_benders.jl`,
`test_planning_benders_integer.jl`, `test_planning_certification.jl`,
`test_planning_certification_integer.jl`, `test_planning_goldens.jl`, `test_planning_master.jl`,
`test_planning_master_integer.jl`, `test_planning_nash.jl`, `test_planning_noninteger.jl`,
`test_planning_hardening.jl`) pass the SAME hardcoded `α_op_lb = -5.0, α_x_lb = 0.0` on variants
of the shared toy fixture (`Phase6Fixtures.two_bus_feeder()` + `ToyElasticDevice`). At `T=1` this
is valid by the fixture's OWN documented analytic welfare bound (`test_planning_master.jl`'s
comment: "conservative margin below the oracle's own analytic max welfare of 2.0" ⇒ the TRUE
threshold is `-2.0`, and `-5.0` is safely below it). BUT `test_planning_hardening.jl` (lines
186–267) ALREADY found and documents that on its OWN `T=8` fixture, `α_op_lb=-5.0` "silently
converges to a value that is NOT the true optimum," and had to be loosened to `-50.0` to get the
correct answer — i.e. `-5.0` IS an invalid (too-tight) bound there, and it was ALREADY silently
wrong before someone happened to check.
**Why it happens:** `α_op_lb` must be ≤ the TRUE minimum of `-welfare(z)` over the master's box;
that minimum scales with `T` (more hours ⇒ more welfare ⇒ a more negative `α_op_lb` threshold is
needed) and with the specific population, so one constant cannot be valid everywhere.
**How to avoid:** Before BILEV-05's new build-time rejection ships, run the new derivation
formula (relaxed-oracle optimum) against EVERY existing `α_op_lb=-5.0`/`α_x_lb=0.0` call site
that uses `T>1` (`grep -n "α_op_lb" test/*.jl` lists all of them) and report, per CONTEXT.md's
explicit instruction, ANY site where `-5.0` would now be rejected as a found bug — do NOT
silently raise the new gate's tolerance to let an already-known-wrong existing bound pass.
**Warning signs:** A test that passes today but whose Benders loop "converges" to a cost
strictly WORSE than brute-force/enumeration on the same fixture (exactly the symptom
`test_planning_hardening.jl` already documents).

### Pitfall 5: `generate_profiles`/`Deferrable`/`Thermostatic` have T-dependent validity constraints
**What goes wrong:** Reusing an existing device-population helper (`_house_aggregator`,
`build_ieee13_aggregators`, etc.) at a SHORTER `T` than it was designed for throws an
`ArgumentError` from the device constructor (`Deferrable`'s `t_start <= t_end <= T` window
guard), not from the oracle.
**Why it happens:** Those helpers hardcode `T=24`-shaped device parameters (`Deferrable(bus, 8,
16, ...)`) at module-constant scope (`Phase4Fixtures`'s `const T = 24`).
**How to avoid:** Write a NEW, T-parametrized population helper for this phase's fixture (PVBattery
+ Thermostatic are both fine at any `T≥1`; a `Deferrable` would need its window re-derived per
`T`, e.g. `t_start=1, t_end=T`).
**Warning signs:** `ArgumentError` from inside a `Deferrable(...)` constructor call, not from
`build_planning_oracle`/`solve_planning_oracle!`.

### Pitfall 6: PVAL-04's builder registry tripwire will fail the suite on ANY new `build_*` function
**What goes wrong:** Adding a new planning-layer builder (the feasibility oracle, the relaxed
α-bound model, etc.) without registering it in `test/test_planning_noninteger.jl`'s `registry`
Dict fails the suite's PVAL-04 source-scan tripwire (it unions a recursive grep over
`src/planning/` for `build_\w+` definitions with every exported `build_*` symbol, and asserts
the found set equals the registry's key set).
**Why it happens:** The tripwire is DELIBERATELY strict — Phase 29 hit exactly this when
`build_bilevel_kkt` shipped unregistered (see `29-FINDINGS.md`'s closing note).
**How to avoid:** Any NEW `build_*` function this phase adds (a feasibility-oracle builder, if
named with a `build_` prefix) MUST be added to the registry (as a binary-free entry, since it is
a plain slack-min LP/SOCP, not a MILP) in the SAME commit.
**Warning signs:** A full-suite run reporting a NEW failure in
`test_planning_noninteger.jl`'s PVAL-04 testitem after adding a builder.

## Code Examples

### Building a T=4 IEEE-13 oracle (verified working recipe, this session)
```julia
# Source: this session's direct verification, JULIA_LOAD_PATH="test:.:@stdlib" julia script.jl
const T = 4
feeder = TSODSO.ieee13_modified()
N = length(feeder.buses)

function house_agg(bus; seed, φ=0.90, load_scale=0.01, pv_scale=0.03,
                    batt_pmax=0.02, batt_emax=0.1, batt_soc0=0.05)
    prof = generate_profiles(seed = seed + bus, T = T)   # NOT Phase4Fixtures (T=24-locked)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0, 3.8, 6.2, 8.9, Ppv)
    return Aggregator(bus, φ, [therm, batt], Pdc)
end
aggs = [house_agg(bus; seed=20260718) for bus in 2:N]
λ0 = Float64[6.5, 6.2, 5.9, 5.7]

oracle = TSODSO.build_planning_oracle(feeder, TSODSO.ConvexBranchFlow(), aggs; λ₀=λ0, T=T)
# Measured: build ~19s (first call, JIT-dominated); re-solve via solve_planning_oracle! ~25-30ms.
```

### Measured feasible/exact/infeasible map on the UNMODIFIED `ieee13_modified()` feeder
(uniform `z` pin over all 4 hours, the T=4 population above; head branch `smax=0.0686` pu)

| `z` (pu/hr) | Outcome |
|---|---|
| `0.00` | `MOI.INFEASIBLE` (genuine — see Pitfall 1; not voltage, not thermal, per ablation) |
| `0.01` – `0.05` | OK, SOCP EXACT (`maxgap` ≈ `1e-9`–`3e-8`) |
| `0.06` | OK (feasible primal), SOCP **INEXACT** (`maxgap≈1.9e-3`, ratio≈4852× over tolerance) — the BILEV-04b fixture |
| `≥0.0686` | `MOI.INFEASIBLE`, confirmed **THERMAL** (disappears when `smax` alone is widened; persists when voltage alone is widened) — the BILEV-04a thermal fixture |
| `≤-0.01` (export) | `MOI.INFEASIBLE` on this population (battery/PV capacity-limited, NOT network — see Pitfall 1) |

### Isolating a genuine voltage-only infeasibility (this session, 3-bus `high_pv_feeder`-style fixture, smax=90 sentinel ⇒ thermally unconstrained)
```julia
# Source: this session's direct verification. On a thermally-unconstrained feeder,
# an import pin that is simply TOO LOW for the population to serve demand is infeasible
# for a DEVICE-capacity reason (Pitfall 1), not voltage — confirmed by widening voltage
# bounds and observing NO change in the feasible threshold (z=0.08 both before/after).
# A genuine voltage-only infeasibility on IEEE-13 scale was isolated instead on a
# LARGER, thermally-widened (smax=90) IEEE-13 variant with ample battery capacity:
# z ∈ {0.5, 1.0} -> MOI.INFEASIBLE when voltage bounds are the REAL [0.95,1.05] ones,
# but only SOCP-INEXACT (not infeasible) at the SAME z once voltage is ALSO widened —
# this is the clean voltage-only signature. z >= 2.0 remains infeasible even with BOTH
# widened (device/battery-capacity-limited at that scale).
```

### The AC re-check must bypass `solve_planning_oracle!` (this session, confirmed)
```julia
# Naive reuse THROWS even though Ipopt succeeded:
oracle_ac = TSODSO.build_planning_oracle(feeder, TSODSO.ACPowerFlow(; limits=false), aggs; λ₀=λ0, T=T)
TSODSO.solve_planning_oracle!(oracle_ac, z_incumbent)
# ERROR: solve_with_retry!: ... termination_status: LOCALLY_SOLVED, primal_status: FEASIBLE_POINT,
#        dual_status: FEASIBLE_POINT, raw_status: Solve_Succeeded   <- a REAL success, rejected
#        by assert_solved!'s default allow_local=false, which solve_with_retry! never overrides.

# The WORKING pattern (mirrors _mpc_truth_import_acpf, src/experiments/mpc_loop.jl:1557):
set_parameter_value.(oracle_ac.z, z_incumbent)
TSODSO.assert_solved!(oracle_ac.model; dual = false, allow_local = true)   # SUCCEEDS
# Measured: ~15s wall time for one T=4 Ipopt NLP solve (vs ~30ms for the SOCP) — confirms
# this MUST run once at convergence, never per Benders iteration (CONTEXT.md's own design).
```

### Deriving `α_op_lb` via a one-time relaxed, pin-free model (this session, confirmed valid)
```julia
# Cannot reuse PlanningOracle's Parameter-pinned p_import — must build a SEPARATE model.
function build_relaxed_oracle(feeder, pf, aggregators; λ₀, T, y_max)
    model = Model(TSODSO.select_optimizer(TSODSO.problem_class(pf)))
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T; ctx.meta[:problem_class] = TSODSO.problem_class(pf)
    TSODSO.contribute!(pf, ctx, feeder; T = T)
    @variable(model, 0 <= p_import[t=1:T] <= y_max)              # BOX, not a pin
    for t in 1:T; TSODSO.add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t]); end
    # ... (reactive channel, aggregator contribute!, balance closure — verbatim as
    #      build_planning_oracle) ...
    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t]*p_import[t] for t in 1:T))
    return model, ctx
end
TSODSO.solve_with_retry!(model_r; dual=true)
α_op_lb = -objective_value(model_r)
# Measured (T=4 IEEE-13, y_max=0.1): relaxed welfare = -609.008659 => α_op_lb = 609.008659;
# confirmed >= every tested pinned-z welfare (more negative values), i.e. a VALID global bound.
```

## State of the Art

| Old Approach (Phases 10–29) | New in This Phase | Changed | Impact |
|---|---|---|---|
| `solve_stackelberg!` exercised only on 2-bus/T=1 toy fixtures where the oracle is essentially always feasible/exact | Real multi-bus IEEE-13, T=3–6, with GENUINE feasibility/inexactness encountered inside the loop | Phase 30 | First real test of the feasibility-cut and exactness-policy code paths that were previously theoretical/docstring-only |
| `assert_socp_exact!` always THROWS on inexactness (no caller-selectable policy) | `inexact_policy` kwarg on `solve_stackelberg!` (`:strict`/`:reject`/`:certify_incumbent`) | Phase 30 (BILEV-04b) | `:strict` preserves today's behavior exactly; the other two are new, additive paths |
| `α_op_lb`/`α_x_lb` are always explicit, user-picked numbers (validated nowhere) | `:auto` default, derived from a one-time relaxed solve, with build-time + runtime rejection of invalid user-supplied bounds | Phase 30 (BILEV-05) | Surfaces the ALREADY-KNOWN `α_op_lb=-5.0`-invalid-at-T=8 issue (`test_planning_hardening.jl`) as a now-enforced invariant, and may surface MORE such cases across the other ~90 call sites |

**Deprecated/outdated:** none — this phase is purely additive (new kwargs default to today's
behavior; `α_op_lb`/`α_x_lb` still accept explicit numbers).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The feasibility-cut fixtures (BILEV-04a) do not need to reuse the EXACT same aggregator population/feeder as the BILEV-03 convergence fixture — CONTEXT.md's wording ("separate fixtures") is read as permitting purpose-built, possibly smaller feeders for the voltage/thermal cases. | User Constraints / Architecture Patterns | If the user intended ALL of BILEV-03/04/05 to run on literally the SAME IEEE-13+population instance, the voltage-infeasible fixture as scoped here (needing a thermally-widened variant) would need to be re-derived strictly within the unmodified feeder, which this session's probes suggest may require a much larger `z` and more careful population tuning to isolate cleanly |
| A2 | `house_agg`'s calibration style (PVBattery+Thermostatic, `load_scale`/`pv_scale`≈0.005–0.03, mirroring `GROUND_LOAD_SCALE`/`GROUND_PV_SCALE`) is a reasonable STARTING point for the T=3–6 fixture, not the final tuning — the plan should re-tune so `z=0` (or whatever the master's natural lower corner is) is balance-feasible | Summary / Pitfall 2 | A population where the natural Benders starting trials are mostly infeasible would make the loop spend most iterations on feasibility cuts, obscuring the BILEV-03 convergence demonstration |
| A3 | The new feasibility oracle (BILEV-04a) should be built via the SAME `problem_class(pf)`-routed `select_optimizer` factory as `PlanningOracle` (formulation-generic, not hardcoded to a specific solver) | Architecture Patterns / Don't Hand-Roll | If a different solver choice is assumed, the `∥s∥₁` slack objective (piecewise-linear, LP-representable even under an SOCP network) might need an explicit epigraph reformulation depending on solver support for mixed LP/SOCP objectives — worth a quick Clarabel-support check at implementation time |
| A4 | `BendersMasterInteger`/Nash (`run_nash!`) call sites are OUT of this phase's direct scope (Phase 31), so the `α_op_lb=-5.0` audit (Pitfall 4) should be run FOR AWARENESS across all call sites but the FIX (if any T>1 Nash/integer site is found invalid) may be deferred to Phase 31 if it touches integer-master-specific code, rather than blocking Phase 30 | Pitfall 4 | If the user intends BILEV-05's validation to apply repo-wide starting this phase, deferring any fix found in Nash/integer call sites would leave a known-invalid bound live past this phase's close |

## Open Questions

1. **Can the new feasibility (slack-min) oracle reuse `ConvexBranchFlow`'s existing SOC
   machinery directly, or does the `‖s‖₁` objective need a separate LP/QP epigraph reformulation
   under Clarabel?**
   - What we know: Clarabel natively handles SOCP + convex QP objectives (per CLAUDE.md's stack
     doc); a pure L1-norm minimization is LP-representable (`s = s⁺ - s⁻`, minimize
     `Σ(s⁺+s⁻)`), which composes fine as a LINEAR objective term even inside an SOCP-constrained
     model.
   - What's unclear: whether building this as `Model(select_optimizer(problem_class(pf)))` (SOCP
     factory, since the network constraints are still `ConvexBranchFlow`) just works with the
     added linear slack objective — never explicitly tried in this session (no budget remaining
     for another live probe).
   - Recommendation: verify with a short Julia probe at plan/implementation time; expected to be
     a routine LP-term-inside-an-SOCP-model case Clarabel handles natively, but confirm before
     committing to the design.

2. **What EXACT T and population tuning makes the T=3–6 BILEV-03 convergence fixture land
   mostly inside the feasible-and-exact z window while still occasionally exercising the
   feasibility-cut and `inexact_policy` paths (so the convergence test is a genuine, not vacuous,
   Benders run)?**
   - What we know: this session's exploratory T=4 population has a narrow (~0.04 pu/hr) window
     and goes infeasible/inexact quickly outside it, which is GOOD for stress-testing the new
     code paths but could make a "pure, uneventful convergence" certification fixture hard to
     separate from a "convergence under genuine feasibility/exactness friction" one.
   - What's unclear: whether CONTEXT.md intends the BILEV-03 fixture to encounter ZERO
     feasibility/inexactness events (a "clean" convergence demo) or to exercise them inline (a
     more realistic, harder test). Both are defensible readings.
   - Recommendation: given CONTEXT.md's phrasing "converging with a closed LB/UB gap" (success
     criterion 1) is stated separately from BILEV-04's feasibility/inexactness criteria, a clean
     BILEV-03 fixture (tuned to mostly avoid friction) plus SEPARATE BILEV-04 fixtures (this
     session's approach) is the safer reading — confirm at plan/discuss time if ambiguous.

3. **Does the follower's relaxed minimum (`α_x_lb`) ever need a genuine LP solve, or is `0.0`
   always provably correct given the project's cost-coefficient conventions?**
   - What we know: `build_follower` has NO guard requiring `c_inv >= 0`/`c_op[t] >= 0`; if both
     are non-negative (true of every existing fixture checked), the trivial `x_inv=x_op=0` point
     achieves cost `0`, which is the GLOBAL minimum with the coupling constraint removed.
   - What's unclear: whether BILEV-05 should hard-code this closed-form shortcut (fast, but
     silently wrong if a future fixture ever uses a negative cost coefficient) or always run the
     one-time relaxed LP solve (slower by a negligible amount — it's a trivial LP — but robust).
   - Recommendation: always solve the relaxed LP (cheap, HiGHS, <0.1s) rather than hard-coding
     the `0.0` shortcut — consistent with CONTEXT.md's own "derivation by relaxed solves" wording
     and avoids a silent-wrong-answer trap for a future negative-cost fixture.

## Environment Availability

Not applicable in the external-dependency sense — all required tools (Julia, Clarabel, HiGHS,
Ipopt, JuMP) are already installed project dependencies, and all were exercised live and
successfully in this research session (see Code Examples). No new external tool, service, or
runtime is introduced by this phase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` (`@testitem`) — but see the repo-wide hazard below |
| Config file | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| Quick run command | `JULIA_LOAD_PATH="test:.:@stdlib" julia <direct_script.jl>` — **NOT** `TestItemRunner.runtests(...)`, which does not resolve under `--project=.` in this repo (established, repeated project hazard — see memory `gsd-plan-verify-testitemrunner-trap`) |
| Full suite command | One detached, orchestrator-run `julia --project=. -e 'import Pkg; Pkg.test()'` (never `--project=test`, which risks sibling-worktree contamination — established project hazard). **Per this phase's explicit instruction: do NOT run `Pkg.test()` during research; only the plan's own execution/close phase runs it, detached, exactly once.** |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BILEV-03 | `solve_stackelberg!` converges on IEEE-13+T=3–6 with `ConvexBranchFlow`, closed LB/UB gap, matching an independent monolithic joint solve | integration (direct script first, then `@testitem`) | `JULIA_LOAD_PATH="test:.:@stdlib" julia test/test_planning_benders_ieee13.jl` (new file) | ❌ Wave 0 |
| BILEV-04a (voltage) | A voltage-infeasible pin produces a feasibility cut AND the loop still converges | integration | new `@testitem` in a new `test_planning_feasibility_oracle.jl` | ❌ Wave 0 |
| BILEV-04a (thermal) | A thermal-infeasible pin (confirmed via Pattern 1's ablation, e.g. `z≥0.0686` on IEEE-13) produces a feasibility cut AND the loop still converges | integration | same new file, second `@testitem` | ❌ Wave 0 |
| BILEV-04b | `inexact_policy ∈ {:strict,:reject,:certify_incumbent}` each behave as documented at the measured-inexact pin (`z=0.06` on the T=4 IEEE-13 fixture, or the final tuned fixture's own measured equivalent) | unit/integration | new `@testitem`s in `test_planning_inexact_policy.jl` (new file) | ❌ Wave 0 |
| BILEV-05 | `:auto` α-bounds derived correctly; an over-high explicit bound is rejected at build time; a found-invalid EXISTING bound (Pitfall 4) is reported | unit | extend `test_planning_master.jl` + a new audit script over the `α_op_lb=-5.0` call sites | ⚠️ partial — `test_planning_master.jl` exists but needs new testitems; the audit is a one-off script, not a suite test |

### Sampling Rate
- **Per task commit:** the relevant new/changed `test_planning_*.jl` file via direct Julia
  script (`JULIA_LOAD_PATH="test:.:@stdlib" julia test/test_planning_<x>.jl` does NOT work
  directly since these are `@testitem`-based — use a small ad hoc driver script that `include`s
  the file's logic directly, or extract the core assertions into a plain function callable from
  both the `@testitem` and a direct script, per this repo's established executor workaround).
- **Per wave merge:** re-run every new/changed planning test file's core logic directly (fast,
  since oracle re-solves measured at ~30ms and master/follower LPs at <0.1s — a full BILEV-03
  convergence run of even 50 iterations costs well under 10s of actual solve time, dominated by
  Julia/package load, not iteration count).
- **Phase gate:** ONE detached, orchestrator-run full `Pkg.test()` before `/gsd:verify-work`
  (never run casually; ~22 min per project memory).

### Wave 0 Gaps
- [ ] `test/test_planning_benders_ieee13.jl` — covers BILEV-03 (new T=3–6 IEEE-13 population
  helper + convergence + monolithic cross-check)
- [ ] `test/test_planning_feasibility_oracle.jl` — covers BILEV-04a (voltage + thermal fixtures)
- [ ] `test/test_planning_inexact_policy.jl` — covers BILEV-04b (`:strict`/`:reject`/
  `:certify_incumbent`, `BendersTrace`'s new columns)
- [ ] Extend `test/test_planning_master.jl` — covers BILEV-05 (`:auto` resolution, build-time
  rejection, runtime rejection)
- [ ] One-off audit script (not a suite test) — runs the new α-bound derivation against every
  existing `α_op_lb=-5.0`/`α_x_lb=0.0` call site at `T>1` and reports any now-rejected bound
  (Pitfall 4) — this is RESEARCH/VERIFICATION tooling, analogous to
  `.planning/phases/28-.../scripts/audit_goldens.py`, not a new permanent test file
- [ ] `test/test_planning_noninteger.jl`'s PVAL-04 `registry` — MUST gain an entry for any new
  `build_*` function this phase introduces (Pitfall 6)

## Security Domain

`security_enforcement` is absent from `.planning/config.json` (treated as enabled per protocol),
but this phase has essentially no attack surface: it is a research optimization library with no
network listener, no user-authentication boundary, no parsing of untrusted external input (all
data is either hardcoded fixture data or locally-generated seeded profiles), and no
serialization of untrusted data. The applicable ASVS categories below are therefore N/A almost
across the board — recorded for completeness, not because a real gap was found.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth boundary in a local optimization library |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | No multi-user access model |
| V5 Input Validation | yes (narrow) | Existing `ArgumentError` boundary guards (e.g. `T>=1`, `length(λ₀)==T`) — this phase's new kwargs (`inexact_policy`, `α_op_lb=:auto`) must get the SAME fail-loud-before-build discipline already used throughout `src/planning/` |
| V6 Cryptography | no | No secrets/crypto in this phase |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silently accepting a numerically-wrong "near enough" optimization result | Tampering (of trust in the result, not of data) | The project's existing `assert_solved!`/`assert_socp_exact!`/`solve_with_retry!` strict-gate discipline — this phase's `inexact_policy` MUST still report (never silently swallow) an inexact cut per CONTEXT.md's explicit requirement |
| An invalid epigraph lower bound silently producing a wrong "converged" answer | Tampering (of the optimization result's correctness, the project's actual core-value risk) | BILEV-05's two-layer rejection (build-time + runtime) — this IS the phase's own mitigation for exactly this pattern, already confirmed necessary by the pre-existing `test_planning_hardening.jl` finding (Pitfall 4) |

## Sources

### Primary (HIGH confidence — verified by direct execution this session)
- `src/planning/benders.jl`, `src/planning/subproblem.jl`, `src/planning/master.jl`,
  `src/planning/follower.jl`, `src/planning/retry.jl`, `src/planning/trace.jl`,
  `src/models/exactness.jl`, `src/powerflow/ACPowerFlow.jl`, `src/core/status.jl`,
  `src/data/ieee13.jl`, `src/data/Feeder.jl`, `src/data/profiles.jl` — read in full this session.
- Live Julia probes (11 scripts) run via `JULIA_LOAD_PATH="test:.:@stdlib" julia <script>.jl`
  against the real `ieee13_modified()` feeder and a 3-bus toy stress feeder, producing every
  concrete number in this document (feasible/exact/infeasible z windows, oracle/follower/master
  solve timings, the AC re-check's `allow_local` requirement, the relaxed α-bound derivation).
- `test/fixtures_phase4.jl` (`Phase4Fixtures` module) — read in full; confirms the `T=24`
  hardcoding issue (Pitfall 5).
- `grep -rn "α_op_lb" test/*.jl` — confirms the ~90-call-site `-5.0` pattern and
  `test_planning_hardening.jl`'s own pre-existing T=8 finding (Pitfall 4).
- `.planning/phases/29-genuine-bilevel-tso-dso-variant/29-FINDINGS.md` — confirms the
  PVAL-04 registry tripwire behavior (Pitfall 6) and the project's established pattern for
  building an independent monolithic/joint reference model (`build_joint_reference`).
- `Project.toml` — confirms no new package dependency is needed.

### Secondary (MEDIUM confidence)
- `src/experiments/mpc_loop.jl` (`_mpc_truth_import_acpf`, lines ~1286–1650) — read via
  targeted `grep`/`Read` of its docstring and call-site lines; the ARCHITECTURE of its
  direct-`assert_solved!(...; allow_local=true)` pattern is confirmed by this session's own
  direct reproduction (Code Examples), but the full function body was not read line-by-line.

### Tertiary (LOW confidence)
None — every claim in this document was either verified by direct code execution this session
or cited from a specific, named source file read in full.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all versions read directly from `Project.toml`.
- Architecture (feasibility oracle / AC re-check / α-bound derivation design): HIGH — every
  mechanism proposed was prototyped and confirmed working (or confirmed NOT working, e.g. the
  naive `solve_planning_oracle!` reuse for AC re-check) via direct execution this session.
- Pitfalls: HIGH for Pitfalls 1–3, 5–6 (directly observed/measured this session or confirmed by
  reading the exact source); HIGH for Pitfall 4 (the `test_planning_hardening.jl` finding is
  read directly from that file's own comments, not inferred).
- Fixture-tuning specifics (exact T, exact population magnitudes for the FINAL phase fixtures):
  MEDIUM — this session's exploratory population is a validated STARTING point and produces all
  the required phenomena (feasible/exact, inexact, thermal-infeasible, voltage-infeasible with a
  purpose-built variant), but final tuning for a clean BILEV-03 "mostly converges without
  friction" demonstration is left to planning/implementation (Open Question 2).

**Research date:** 2026-10-01
**Valid until:** 30 days (stable in-tree code; no external API/version drift risk — re-verify
only if `src/planning/*.jl`, `src/models/exactness.jl`, or `src/powerflow/ACPowerFlow.jl` change
before this phase is planned/executed)
