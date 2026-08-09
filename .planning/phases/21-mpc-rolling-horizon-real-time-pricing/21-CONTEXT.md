# Phase 21: MPC / Rolling-Horizon / Real-Time Pricing - Context

**Gathered:** 2026-08-09
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all three grey-area tables accepted as recommended

<domain>
## Phase Boundary

A researcher can run a closed-loop receding-horizon solve over the stateful devices (battery SOC,
thermostatic temperature), with rolling re-computed DADPs published as a real-time price signal,
and see the closed loop honestly benchmarked against the perfect-foresight day-ahead optimum.
Requirements: MPC-01..MPC-04. Depends on Phase 20 (a rolling window can traverse the
overvoltage-exactness boundary mid-simulation and needs the certified restriction/fallback rather
than undefined behavior). Shares an identical `Scenario.jl` schema-extension blast radius with
Phase 22 — field additions must be minimal, additive, and documented for the coordinated pair.

</domain>

<decisions>
## Implementation Decisions

### Rolling-Horizon Architecture
- **D-01:** The MPC loop lives in a **new sibling orchestrator module** (v2.0 `PlanningOracle`
  orchestrator precedent), wiring the SEAM-01 `horizon_state` stub (src/models/oracle.jl) —
  `welfare_solve.jl` stays untouched. Module location/name at Claude's discretion (e.g.
  `src/models/mpc_loop.jl` or `src/experiments/`).
- **D-02:** Each window solves the **centralized `solve_welfare`** problem — not ADMM. ADMM-in-the-
  loop is explicitly deferred.
- **D-03:** Horizon `H` and step size are **researcher-supplied kwargs with sane defaults** on the
  24h fixture. No auto-tuning. Window problem is **built once and re-solved per step via JuMP
  `Parameter` injection** of the measured state (MPC-01, locked by ROADMAP).
- **D-04:** Overvoltage boundary mid-simulation: **per-step certificate check using the Phase-20
  machinery**; on certificate failure at a step, record the status + Phase-20 fallback path in the
  trace and continue — **never throw mid-loop**.

### State Propagation & Terminal Condition
- **D-05:** "Measured" state comes from a **nominal plant**: apply each step's first-interval
  optimal controls to the ground-truth device dynamics (same device models, true realization).
  Model mismatch enters only via forecast error.
- **D-06:** Terminal-SOC condition (MPC-02): **hard equality to the day-ahead optimal SOC
  trajectory value at each window's end** — information-set-fair vs the benchmark. The MPC-02
  regression must demonstrate the dump/hoard artifact present when disabled, absent when enabled.
- **D-07:** **No terminal condition on thermostatic temperature** — the comfort band suffices.
- **D-08:** Forecast error: **seeded bounded perturbation** of PV + demand ground truth
  (magnitude kwarg, e.g. ±5–10%), constant within a window, regenerated per step. No
  horizon-decaying error sophistication (deferred).

### RTP Trace & Benchmark Semantics
- **D-09:** New exported **trace struct following the `AdmmResiduals`/`BendersTrace` convention**
  (name at Claude's discretion, e.g. `MpcTrace`): per-step published DADPs, step-to-step price
  jumps, cumulative deviation vs the day-ahead DADP path, per-step certificate/fallback status.
- **D-10:** Exact price-consistency norms (max/mean jump etc.) at Claude's discretion, provided
  both MPC-03 metrics (step-to-step jumps, cumulative deviation) are recorded and documented.
- **D-11:** Benchmark framing (MPC-04): **regret** — closed-loop realized welfare vs the
  perfect-foresight day-ahead optimum computed on the same realized truth (information-set-fair),
  plus the price-deviation path, under seeded synthetic forecast error, in a live-executed
  literate rung page.
- **D-12:** `Scenario.jl` extension: **minimal additive `@kwdef` fields with defaults that
  preserve existing golden hashes** (schema-fragile, golden-hash-bearing file), explicitly
  documented to compose with Phase 22's coming scenario-tree fields (coordinated-diff note).

### Claude's Discretion
- Module/struct/function/kwarg names throughout (loop orchestrator, trace struct, terminal-SOC
  kwarg, forecast-error kwargs).
- Exact default values for H, step, forecast-error magnitude (measure what makes the fixture
  demonstrative), and the exact price-consistency norm definitions (D-10).
- Which fixture drives CI (small radial per Phase-19 D-13 precedent) vs quarantined evidence.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- SEAM-01 `horizon_state` stub — src/models/oracle.jl (the seam MPC-01 makes load-bearing).
- `Scenario` (`Base.@kwdef struct`, src/experiments/Scenario.jl:92) + `run_scenario`/`ScenarioResult`
  (src/experiments/run.jl) — declarative scenario layer; golden-hash-bearing, treat as fragile.
- JuMP `Parameter` re-solve pattern — already proven in the v2.0 planning oracle (`p_import == z`
  Parameter pin) and ADMM build-once/re-solve machinery.
- Phase-20 machinery: `RestrictedBranchFlow`, `assert_restriction_exact!` (price_provenance.status),
  `ac_dual_fallback_price` (price_status=:local_ac_dual) — the per-step boundary handling (D-04).
- Trace-struct convention: `AdmmResiduals` (src/admm/residuals.jl), `BendersTrace`, `NashTrace`.
- Literate rung-page pattern: docs/literate/restricted_branch_flow.jl is the freshest example.

### Established Patterns
- Certificate family: throw-by-default + report kwarg, measured tolerances with docstring
  provenance (if any new gate is added — e.g. MPC-02's regression is a test, not a certificate).
- Quarantined expensive evidence vs CI-gated cheap evidence (Phase 19/20 precedent).
- Build once, re-solve many: never rebuild JuMP models inside a loop (CLAUDE.md hard rule).

### Integration Points
- New orchestrator consumes `solve_welfare` + device state extraction; publishes trace + prices.
- Scenario.jl additive fields (D-12) feed the orchestrator declaratively.
- docs/make.jl literate pages list; docs/src/api.md @autodocs (remember Phase-20's checkdocs
  lesson: EVERY new exported symbol must be wired into api.md or the docs build fails).

### Testing constraints (from Phase 19/20 execution — MANDATORY for plans)
- Plans' <verify> blocks: direct Julia/Test.jl scripts under `--project=.` ONLY. NEVER
  TestItemRunner under --project=. ; never `@run_package_tests` via `julia -e`.
- Full suite: `julia --project=. -e 'import Pkg; Pkg.test()'` (~13-18 min, background). Green
  reference after Phase 20 fixes: 2563 passed / 0 failed / 3 pre-existing broken.
- MPC closed loops solve many windows — keep the CI fixture SMALL (2-3 bus, short T) so the loop
  test stays in seconds/minutes; the 24h full demonstration belongs in the literate page /
  quarantined evidence.

</code_context>

<specifics>
## Specific Ideas

- MPC-01's "built once and re-solved per step, never rebuilt" is a hard acceptance criterion —
  the regression should assert the same model object is reused (e.g. via objectid or solve-count
  instrumentation), not just that results look right.
- The literate page must present the regret benchmark honestly: perfect-foresight optimum is an
  upper bound computed on the realized truth; closed-loop regret should be reported as measured,
  not tuned to look small.
- Per-step published price for already-elapsed hours is final; price-consistency metrics compare
  successive windows' overlapping hours.

</specifics>

<deferred>
## Deferred Ideas

- ADMM-in-the-loop (per-window decomposition) — deferred.
- Plant-model mismatch beyond forecast error — deferred.
- Horizon-decaying forecast-error models — deferred (natural Phase-22 composition point).
- Soft/penalized terminal-SOC variants — this rung is the hard terminal target only.

</deferred>
