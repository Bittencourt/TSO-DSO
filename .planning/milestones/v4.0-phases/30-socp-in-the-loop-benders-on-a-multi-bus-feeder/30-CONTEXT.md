# Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder - Context

**Gathered:** 2026-10-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Make `solve_stackelberg!` (the integrated / Benders-decomposed Stackelberg variant — distinct
from Phase 29's genuinely-bilevel `solve_bilevel!`) run with the real branch-flow SOCP
(`ConvexBranchFlow`) on a realistic multi-bus, multi-period feeder (IEEE-13, T>1), with:
oracle feasibility cuts for voltage-/thermally-infeasible pinned z (BILEV-04a), a documented,
non-crashing policy for SOCP inexactness at a pinned z (BILEV-04b), and automatically derived
master α lower bounds with rejection of over-high user bounds (BILEV-05). Requirements:
BILEV-03, BILEV-04, BILEV-05.

Out of scope: the genuinely-bilevel KKT path (Phase 29), GNE/Nash fixtures and integer N>1
(Phase 31), IEEE-8500 scale (Phase 35).

</domain>

<decisions>
## Implementation Decisions

### Benchmark fixture & convergence certification (BILEV-03)
- Fixture: `ieee13_modified()` with a short multi-period horizon (T≈3–6), reusing existing
  IEEE-13 aggregator/device populations from the experiments layer.
- Convergence is certified by BOTH a closed LB/UB gap ≤ tol AND a cross-check against an
  independently solved monolithic (extensive-form joint) problem on the identical instance.
  The comparison tolerance is MEASURED (solver duality gaps / MIP tolerances), never picked.
- In-suite test budget ≈ ≤2 min. A larger T=24 IEEE-13 run lives as a Literate experiment
  script (runnable, documented), not a suite test.
- Use the DEFAULT (Gan–Low) exactness copy. Do not assume exactness: report the cone gap at the
  incumbent (Phase 28 showed the default is not unconditionally cone-exact).

### Oracle feasibility cuts (BILEV-04a)
- Mechanism: a second, built-ONCE slack-minimization feasibility oracle with z as a JuMP
  `Parameter`: minimize ‖s‖₁ subject to the full network with the pin relaxed to
  `p_import = z + s⁺ − s⁻`. Its pin dual yields the cut `v + u'(z − z_k) ≤ 0`, in the SAME form
  as the existing `add_feasibility_cut!`. No Farkas-ray extraction from solver certificates.
- Coverage: separate fixtures for a voltage-infeasible pin and a thermal-infeasible pin, each
  shown to (a) produce a feasibility cut and (b) still let the loop converge.
- Loop order: follower feasibility check first (existing WR-01 behavior), then oracle
  feasibility, then the optimality cut. A feasibility cut never updates UB (T-11-06).

### SOCP-inexactness policy at a pinned z (BILEV-04b)
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

### Automatic α lower bounds (BILEV-05)
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/subproblem.jl`: `PlanningOracle` / `build_planning_oracle` /
  `solve_planning_oracle!` — already routes `ConvexBranchFlow` to an SOCP, pins
  `p_import[t] == z[t]` via `Parameter`s (built once), runs `assert_socp_exact!` (throws on
  inexactness — the behavior BILEV-04b replaces by policy) and the battery complementarity gate.
- `src/planning/benders.jl`: `solve_stackelberg!` hand-rolled loop (build-once
  oracle/follower/master, follower feasibility cut branch first, incumbent tracking, checkpointing,
  `BendersTrace`), `add_feasibility_cut!`, `JOINT_RECOURSE_GAP_TOL` / `KNOWN_OPTIMUM_ATOL`
  measured-constant pattern; `_corner_recourse_joint` currently maps oracle throws to +Inf with no
  certificate (the gap BILEV-04a closes).
- `src/planning/master.jl` (`build_master`, takes explicit `α_op_lb`, `α_x_lb`),
  `src/planning/follower.jl`, `src/planning/trace.jl` (`BendersTrace`),
  `src/planning/retry.jl` (`solve_with_retry!`, the sole solve entry point).
- `src/data/ieee13.jl`: `ieee13_modified()`. `ACPowerFlow` exists in `src/powerflow/`.

### Established Patterns
- Build once, mutate `Parameter`s, never rebuild inside the loop.
- Every tolerance/golden is MEASURED and its derivation documented next to the constant.
- Fail loud with named diagnostics; boundary guards at the public entry point.
- Exactness gate: hybrid per-branch floor `atol_b = max(2e-7, 1e-9·ref_b)`; tighten tol_gap, never
  raise τ.

### Integration Points
- `solve_stackelberg!` keyword surface (new: `inexact_policy`, `:auto` α bounds), returned
  NamedTuple (new: incumbent exactness certificate + AC re-check report), `BendersTrace` columns.
- PVAL-04 planning-builder registry in `test/test_planning_noninteger.jl`: any NEW `build_*`
  planning builder (e.g. a feasibility oracle builder) must be registered there or the
  source-scan tripwire fails the suite (Phase 29 lesson).

</code_context>

<specifics>
## Specific Ideas

- The monolithic cross-check must be an independently built model, not a re-use of the Benders
  subproblems.
- Executors on this repo: verify via direct Julia scripts with `JULIA_LOAD_PATH="test:.:@stdlib"`
  (TestItemRunner does not resolve under `--project=.`); full suite only via one detached,
  orchestrator-run `Pkg.test()`.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
