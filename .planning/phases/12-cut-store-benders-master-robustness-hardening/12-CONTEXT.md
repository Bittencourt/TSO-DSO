# Phase 12: Cut-Store & Benders Master Robustness Hardening - Context

**Gathered:** 2026-07-22
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — proposals accepted per area by user

<domain>
## Phase Boundary

The Benders mechanics that Phase 13's Nash diagonalization loop will call repeatedly and at
higher volume — feasibility-cut edge cases, cut-store growth, retry-budget tuning,
convergence-gap instrumentation — are proven solid at single-distributor scale before a second
outer loop is nested on top. Hardening pass: deepens PLAN-05 (persistent cut accumulation) and
PLAN-06 (UB/LB gap convergence detection) from Phase 11; owns no new requirement IDs.

Out of scope: Nash diagonalization / shared-transmission coupling (Phase 13), any new
requirement IDs, binary/integer variables (PVAL-04 continuous-only), cut
dropping/aggregation (deferred unless load test proves it necessary — see decisions).

</domain>

<decisions>
## Implementation Decisions

### Convergence diagnostics struct (success criterion 2)
- **Purpose-built `BendersTrace`** — per-iteration rows recording (iter, LB, UB, gap, cut type
  added, subproblem statuses, retry count, solve time) with a `push!` / `is_converged` /
  summary API. Explicitly NOT a copy of ADMM's `AdmmResiduals` dual-ascent residual-based
  stopping criterion (roadmap criterion; PATTERNS.md Pitfall 7 from Phase 11).
- **Exposure:** the trace is included in `solve_stackelberg!`'s returned NamedTuple. A plotting
  helper is added only if `src/diagnostics/` already has an analog pattern to follow; otherwise
  CairoMakie convergence plotting is deferred (Phase 14 docs/regression phase can pick it up).
- **Always-on instrumentation** — cheap NamedTuple rows; the research bench favors full
  traceability over micro-optimization. No opt-in verbose flag.

### Edge-case & load-test scope (success criteria 1 & 3)
- **Degenerate feasibility-cut testitems:** near-boundary `z` (≈ deliverable cap ± 1e-9),
  zero-volume feasible set (corridor cap = 0), and repeated/duplicate Farkas cuts — each
  asserting the persistent cut store stays finite/valid and LB stays monotone
  non-decreasing across the episode.
- **Load test:** force realistic Benders iteration counts (~50–100) via tight tolerance on a
  cheap toy-oracle fixture, with the Phase-10 retry + checkpoint machinery ACTIVE. Measure the
  empirical retry rate (STATE.md blocker: measure on planning-layer fixtures, don't assume
  v1's Clarabel failure rate holds) and assert checkpoint round-trip integrity at high
  iteration numbers (e.g., resume from iter ≥ 50 reproduces the same trajectory). Do NOT use
  the full IEEE-13 SOCP oracle for the load test (slow, CI-hostile).
- **Cut-store growth policy: keep unbounded accumulation** (correctness-first research bench).
  Instrument cut-store growth in `BendersTrace`. Cut dropping/aggregation is deferred UNLESS
  the load test demonstrates master solve-time blowup — in which case surface the finding and
  defer the mitigation decision (do not silently add cut management).
- **Code/tests placement:** extend existing `src/planning/master.jl` / `src/planning/benders.jl`
  and existing `test_planning_*.jl` files; ONE new test file `test/test_planning_hardening.jl`
  for the edge-case and load suites. No new hardening module.

### Claude's Discretion
- Exact `BendersTrace` field names/types and summary-table format.
- Load-test fixture parameterization (how to force slow convergence: tolerance, fixture shape).
- Whether the ~50–100-iteration load test needs a `[:slow]`-style tag to keep the fast
  `:planning` filter under budget (measure first; keep total quick-run < ~2 min if possible).
- How duplicate Farkas cuts are handled (tolerate redundant rows vs. cheap dedup by hash) —
  as long as the store stays valid and the behavior is documented + tested.
- Retry-budget tuning outcome: whether the measured empirical failure rate justifies changing
  the default `max_attempts` (document the measurement either way).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/benders.jl` — `solve_stackelberg!` (incumbent-tracked UB, follower-first
  ordering, feasibility-cut branch, per-iteration `checkpoint_iteration!`, fail-loud maxiter).
- `src/planning/master.jl` — `BendersMaster`, `add_optimality_cut!`/`add_feasibility_cut!`
  (finiteness-guarded), `solve_master!`.
- `src/planning/follower.jl` — `FollowerLP`, Farkas certificates (verified vs pinned HiGHS 1.24.1).
- `src/planning/subproblem.jl`, `retry.jl` (`solve_with_retry!`), `checkpoint.jl`.
- Test fixtures: `ToyElasticDevice`, `Phase6Fixtures.two_bus_feeder()`, the Phase-11 toy
  Stackelberg fixture (y*=z*=0.7, cost −0.245) + the WR-04 boundary variant (x_inv_max=0.25).

### Established Patterns
- Build-once/re-solve; fail-loud `assert_solved!`; TestItems `[:planning]` tag; INFRA-02.
- Code-review lessons from Phase 11 now baked in: incumbent tracking, finiteness guards,
  feasibility-branch test coverage — hardening should extend these, not re-litigate.
- Info-level review findings carried from Phase 11's REVIEW.md worth addressing here if cheap:
  IN-01 (stale gap in exhaustion message), IN-02 (unchecked `tol`), IN-03 (`max_iter > 99999`
  late failure), IN-06 (Farkas `v > 0` guard), IN-07 (root-Project HiGHS compat caret vs comment).

### Integration Points
- `solve_stackelberg!` return NamedTuple grows a `trace` field (additive, non-breaking).
- `test/test_planning_hardening.jl` — new; other planning test files extended.
- Phase 13 consumes: `BendersTrace` per distributor + proven cut-store semantics.

</code_context>

<specifics>
## Specific Ideas

- Roadmap criterion 2's wording is a guardrail from research: ADMM's residual-based stop is a
  different mathematical object than Benders' UB/LB gap — the struct must make that
  distinction structurally impossible to confuse.
- STATE.md blocker: measure the empirical Clarabel NUMERICAL_ERROR rate on planning fixtures
  during the load test — this is the phase where that measurement naturally happens.

</specifics>

<deferred>
## Deferred Ideas

- Cut dropping/aggregation policy — deferred unless load test shows master solve-time blowup.
- CairoMakie convergence-plot helper — deferred to Phase 14 docs unless a diagnostics analog
  already exists.

</deferred>
