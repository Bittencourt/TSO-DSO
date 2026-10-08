# Phase 29: Genuine Bilevel TSO-DSO Variant - Context

**Gathered:** 2026-09-30
**Status:** Ready for planning

<domain>
## Phase Boundary

BILEV-01/02: add a GENUINELY bilevel TSO–DSO planning variant (the existing `solve_stackelberg!` is
the integrated single-level problem decomposed by Benders), solve it with a documented appropriate
method, and certify on a fixture where the bilevel optimum provably differs from the joint optimum,
with the production method matching the bilevel answer. SOCP-in-the-loop Benders (Phase 30) and
the planning docs refresh (Phase 31, BILEV-08) are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Game formulation — BILEV-01
- DSO LEADER chooses investment y; the tariff π is EXOGENOUS (a parameter). TSO FOLLOWER chooses its
  supply/interface quantity z to minimize its OWN cost c(z) − π·z — which differs from the leader's
  valuation of z — so bilevel ≠ joint whenever π ≠ the leader's marginal value.
- Follower convex LP/QP; DSO network LinDistFlow (LP); small fixtures (2- and 3-bus, T ≤ 2). SOCP
  lower level is out of scope.
- Production method: in-house KKT single-level reformulation in JuMP (complementarity via SOS1, or
  Fortuny-Amat with a MEASURED big-M), solved as MILP by HiGHS; documented why plain Benders is
  invalid here (the follower's value function is not the leader's recourse).

### Certification — BILEV-02
- Two independent oracles: BilevelJuMP in a DIFFERENT mode than production (e.g. strong-duality or
  a different complementarity mode) AND brute-force enumeration over a leader decision grid.
- Fixture built so the follower's own cost makes it under-supply vs the joint optimum; assert a
  MEASURED bilevel-vs-joint gap well above tolerance, and production == bilevel ≠ joint.
- HiGHS `mip_rel_gap`/feasibility tolerances set explicitly and comparison epsilons MEASURED
  (memory: highs-exactness-defaults).

### API
- New entry point `solve_bilevel!` (or `strategy=:bilevel`); existing `solve_stackelberg!` stays
  byte-identical but its docstring is honestly relabelled "integrated problem, Benders-decomposed".
- Unsupported inputs (SOCP lower level, integer follower, …) throw a clear ArgumentError — never a
  silent fallback.

### Post-research amendment (2026-09-30)
- Complementarity: SOS1 via JuMP/MOI's automatic SOS1ToMILPBridge (verified working with HiGHS 1.24.1
  when every complementarity pair has FINITE bounds — derive valid primal/dual bounds; fail loudly otherwise).
- Certification oracle: BilevelJuMP StrongDualityMode (Ipopt) — its SOS1/Indicator modes fail with HiGHS.
- Leader welfare: Option B — embedded LinDistFlow network (per the locked LinDistFlow decision), not a fixed
  linear valuation.
- Do NOT reuse FollowerLP (pins z by equality Parameter — wrong coupling direction). MILP tolerance in
  select_optimizer(::MILP) must be re-measured for this consumer.

### Process (carried)
- ≤3 concurrent Julia executors; full suite after each wave with NO `.claude/worktrees/agent-*`
  present; executors never edit STATE/ROADMAP; findings → 29-FINDINGS.md (serialized) or SUMMARY;
  real executable verify scripts; long runs polled in the FOREGROUND (never end a turn waiting).

### Claude's Discretion
- SOS1 vs Fortuny-Amat choice (whichever HiGHS handles robustly — HiGHS has no native SOS1, so
  research must confirm), exact fixture numbers, result struct fields.

</decisions>

<code_context>
## Existing Code Insights

- `src/planning/` — benders.jl (solve_stackelberg!, corner_recourse incl. T>1 joint recourse from
  Phase 27), master.jl / master_integer.jl, follower.jl (solve_follower!), subproblem.jl
  (planning oracle, optimizer kwarg from 27-07), coupling.jl, nash.jl, trace.jl.
- Existing BilevelJuMP certification tests (Phase 24: test_planning_certification*.jl) — note memory:
  "BilevelJuMP certification cannot tell Stackelberg apart from joint optimisation" today.
- Pre-existing F-27-01-2: solve_follower!/HiGHS certificate-loss fragility (unscheduled).

</code_context>

<specifics>
## Specific Ideas

- The quality-audit memory flags that the current planning "Stackelberg" is only ever run on a
  2-bus T=1 LinDistFlow fixture and BilevelJuMP cannot distinguish it from joint — this phase
  must produce the distinguishing fixture.

</specifics>

<deferred>
## Deferred Ideas

- Price-setting leader (π as a leader decision) — possible follow-up.
- SOCP lower level — out of scope.
- Planning docs refresh / game-theory statement — Phase 31 (BILEV-08).

</deferred>
