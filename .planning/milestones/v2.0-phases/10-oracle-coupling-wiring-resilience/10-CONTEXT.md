# Phase 10: Oracle Coupling Wiring & Resilience - Context

**Gathered:** 2026-07-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Turn the three inert SEAM-01 stubs in `src/models/oracle.jl` into a live, resilient
coupling oracle — the load-bearing seam every later Benders/Nash phase re-solves against —
**before any Benders code depends on it**. Three requirements:

- **PLAN-01** — wire the real `p_import == z` coupling as a live JuMP `Parameter` constraint
  in a build-once subproblem and return its dual (superseding the current `ArgumentError`
  stub); `operational_oracle`/`solve_welfare` stay unmodified.
- **PLAN-02** — reconcile the hourly distribution dual `λ_j[t]` to a single per-scenario
  interconnection dual `π_s` (time-aggregation + sign convention), validated against a
  hand-computed toy case.
- **PLAN-03** — wrap oracle solves in bounded retry + checkpointing so the intermittent
  Clarabel `NUMERICAL_ERROR` (amplified by repeated re-solves) cannot silently corrupt or
  abort a run.

**Out of scope (own phases):** the Benders master/follower LP and leader/follower
*certification* (Phase 11), cut-store hardening at scale (Phase 12), the shared-transmission
`coupling.jl` model and Nash diagonalization (Phase 13). No binary/integer variables at any
point (continuous-only, enforced from this phase onward).
</domain>

<decisions>
## Implementation Decisions

### Coupling setpoint `z` and the pin (PLAN-01)
- **D-01:** `z` is a **per-hour profile `z[t]`** (length `T`), not a scalar. The pin is
  `pin[t]: p_import[t] == z[t]` for each hour — a 1:1 match with the existing hourly
  `p_import[t]` (`DsoOpt.jl` / `welfare_solve.jl`) and the `bus × time` `:balance_p` handle.
  The coupling dual is therefore naturally a length-`T` vector.
- **D-02:** Dual source is **branch-dependent, backward-compatible**:
  - `z !== nothing` → return `dual.(pin)` — the genuine pinned coupling price (the NEW path).
  - `z === nothing` → **unchanged Phase-4 behavior**: `π = dual.(balance_p[root, :])` (free
    import, frontier DADP). All v1 callers/tests stay valid; only the pinned branch is new.
- **D-03:** `operational_oracle`'s existing `z !== nothing` `ArgumentError` throw **stays in
  place** as the free-path guard. The new pinned path lives in the new `src/planning/` module
  (see D-11), so `operational_oracle`/`_coupling_dual` are not modified.

### `λ_j[t] → π_s` reconciliation (PLAN-02)
- **D-04:** `π_s` (the scalar per-scenario interconnection dual) is **reporting/interpretation
  only** — for tables, plots, and the TSO↔DSO interconnection headline. It is **never** fed
  back into an optimization.
- **D-05:** Benders optimality cuts use the **full length-`T` dual vector** exactly:
  `α ≥ cost^k + Σ_t π[t]·(z[t] − z^k[t])`. The exact gradient w.r.t. `z[t]` stays on the solve
  path; scalarization is lossless-by-design because it is off the solve path. (Wired for real
  in Phase 11 — Phase 10 only produces the length-`T` `π` and the reported `π_s`.)
- **D-06:** **Sign convention = raw JuMP dual**, documented as `π[t] := dual(pin[t]) =
  ∂(welfare optimum)/∂z[t]`. Pin it with **one hand-computed toy-case invariant** (success
  criterion 2). Do **NOT** pre-commit to a leader/follower economic reading — Phase 11's
  BilevelJuMP cross-check certifies (or flips) the sign empirically. Do NOT re-resolve the
  PSR-note ambiguity by re-reading `THEORY-papers.md` (STATE.md blocker).
- **D-07:** `π_s` aggregation = **duration-weighted sum** `π_s = Σ_t Δt·π[t]`. At the
  framework's `Δt = 1h` this equals a plain sum today, but writing it duration-weighted is
  correct-by-construction for any future non-uniform `Δt`. Units: price·hour = per-scenario
  interconnection value.

### Retry + checkpoint resilience (PLAN-03)
- **D-08:** The retry wrapper sits **around `assert_solved!`** (the INFRA-03 choke point,
  `src/core/status.jl`) — that is exactly where the Clarabel `NUMERICAL_ERROR` surfaces (a
  failed `is_solved_and_feasible` → loud `error(...)`).
- **D-09:** **Escalating conditioning perturbation.** Attempt 1 solves as-is; on
  `NUMERICAL_ERROR` re-solve with progressively perturbed numerical conditioning (tiny
  relative per-unit-base rescale / Clarabel equilibration or iterative-refinement setting bump)
  — directly targeting the documented per-unit-base cone-slack root cause, since a plain
  re-solve of deterministic Clarabel cannot recover. Bounded attempt budget. **No SCS
  fallback** — the oracle's product IS the dual, so duals must stay Clarabel/IPM-grade.
- **D-10:** On budget exhaustion, **raise loudly** with full status diagnostics — never
  silent-skip, never silent-corrupt (STATE.md blocker: "cannot silently corrupt or abort").
  **Checkpoint granularity = per Benders iteration** (all scenarios for an iterate). On resume,
  the current iteration's scenario solves are redone; completed iterations are skipped.

### Build-once oracle home & reuse (PLAN-01)
- **D-11:** **New module under `src/planning/`** (the directory Phase 13's `coupling.jl` also
  lands in), mirroring the ADMM `build_dso_opt`/`solve_dso!` build-once pattern:
  - `build_planning_oracle(feeder, pf, aggregators; λ₀, T) -> PlanningOracle` builds the
    welfare model **once**, reusing `contribute!(pf, ctx, feeder)` + `contribute!(agg, ctx)`
    **verbatim** (same seams ADMM and `solve_welfare` use), declares `z[t]` as a JuMP
    `Parameter`, and adds `pin[t]: p_import[t] == z[t]`.
  - a `solve_planning_oracle!(o, zᵥ)` re-solve sets the `z` parameter
    (`set_parameter_value`) and returns `(; cost, π, π_s, dadp, ctx)`.
  - **Zero edits** to `welfare_solve.jl` / `oracle.jl` — the "`solve_welfare`/`operational_oracle`
    unmodified" constraint is satisfied *by construction* (RESEARCH Pattern 4: orchestration
    over already-validated builders). Rejected the alternative of extracting a shared
    `build_welfare_model` from `welfare_solve.jl` (would modify a Phase-5 file and require
    byte-identical v1 regression proof).

### Claude's Discretion
- Exact perturbation ladder magnitudes and the retry-budget count `N` — STATE.md says measure
  the **empirical** failure rate on the planning layer's own fixtures; do not assume v1's rate
  holds. Researcher/planner to design the ladder against real fixtures.
- Checkpoint file format/location and the `PlanningOracle` struct's precise fields.
- Whether/how to warm-start the build-once model across successive `z`-iterates.
- The concrete toy-case fixture used to assert the sign invariant (D-06).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The seam being replaced / extended
- `src/models/oracle.jl` — the SEAM-01 stub: `operational_oracle` + `_coupling_dual`, the
  `z !== nothing` `ArgumentError` throw that PLAN-01 supersedes, and the `z↔p_ag`, `λ_j↔π_s`
  bridge documentation. Stays UNMODIFIED (D-03).
- `src/models/welfare_solve.jl` — `solve_welfare`: the GLB-CVX centralized model (`p_import[t]`
  at `feeder.root`, `:balance_p` registration, `contribute!` seams, `ctx.meta[:p_import]`).
  Stays UNMODIFIED; its builder body is the reference for the new build-once model (D-11).

### Build-once / re-solve precedent to mirror
- `src/admm/DsoOpt.jl` — `build_dso_opt` (build-once, `contribute!(ConvexBranchFlow(),...)`
  verbatim) + `solve_dso!`/`set_rho!` (re-solve via parameter/coefficient updates). The
  structural template for `build_planning_oracle`/`solve_planning_oracle!`.
- `src/core/status.jl` — `assert_solved!` (the INFRA-03 choke point the retry wrapper wraps;
  `allow_almost` semantics) and `assert_no_slack`.
- `src/core/ModelContext.jl`, `src/solver/factory.jl` (`select_optimizer(problem_class(pf))`),
  `src/powerflow/AbstractPowerFlow.jl` — the `ctx`, solver-factory (INFRA-02), and `contribute!`
  interfaces reused verbatim.

### Requirements & theory
- `.planning/REQUIREMENTS.md` — PLAN-01/02/03 statements + Traceability table.
- `.planning/ROADMAP.md` §"Phase 10" — goal + 4 success criteria (authoritative scope).
- `.planning/STATE.md` — the three carried blockers: Clarabel `NUMERICAL_ERROR` amplification
  (drives PLAN-03), PSR-note leader/follower inconsistency (why D-06 defers to Phase 11).
- `.planning/research/THEORY-papers.md` (PSR N1–N2 note) — MEDIUM confidence, internally
  inconsistent on leader/follower + sign. **Reference only** — do NOT use it to settle the sign
  convention (D-06); Phase 11 resolves it empirically.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `contribute!(pf, ctx, feeder; T)` and `contribute!(agg, ctx; T)` — reused **verbatim** by the
  new build-once oracle (same as ADMM did); no device/power-flow source is touched.
- `build_dso_opt`/`solve_dso!` (`DsoOpt.jl`) — direct structural template for the new
  `build_planning_oracle`/`solve_planning_oracle!`.
- `assert_solved!` (`status.jl`) — the single solve choke point the retry wrapper composes over.
- `ctx.meta[:p_import]` (stashed by `solve_welfare`) — the frontier variable the pin constrains;
  the new model builds its own `p_import` the same way.

### Established Patterns
- **Build-once, re-solve via `Parameter`/coefficient update, warm-start** (RESEARCH Pattern 6;
  ADMM Pitfall: never rebuild in the loop). `z` as `Parameter` is the canonical re-settable seam.
- **Fail loudly, never `@assert`** — `ArgumentError`/`error(...)` on any untrusted result; the
  retry exhaustion path (D-10) follows this.
- **Prices are duals; duals only from a STRICT `assert_solved!(...; dual=true)` solve** — the
  returned `π` must come from a strictly-solved model (no `allow_almost` on the price-producing
  solve).
- **Never name a solver in a model** — `select_optimizer(problem_class(pf))` (INFRA-02).
- **Continuous-only** — no binary/integer variable anywhere in the planning subproblem.

### Integration Points
- New `src/planning/` directory, `include`d in `src/TSODSO.jl` after `models/` and `admm/`
  (it orchestrates over those already-validated builders). Phase 13's `coupling.jl` will join
  the same directory.
- The length-`T` `π` returned here is consumed by the Phase-11 Benders cut (D-05); the scalar
  `π_s` is reporting-only.

</code_context>

<specifics>
## Specific Ideas

- Preferred return shape: `solve_planning_oracle!(o, zᵥ) -> (; cost, π, π_s, dadp, ctx)` —
  `π` length-`T` (cut gradient), `π_s` scalar (duration-weighted report), `dadp` passed through,
  `ctx` for any other dual.
- The sign invariant should be a **fast, permanent** toy-case test (not a one-off), consistent
  with Phase 11/14 turning validation runs into pinned regressions.

</specifics>

<deferred>
## Deferred Ideas

- **Benders master/follower LP, feasibility/optimality cut accumulation, UB/LB gap** — Phase 11
  (PLAN-04/05/06). Phase 10 only supplies the oracle + length-`T` `π`.
- **Leader/follower + sign *certification*** via BilevelJuMP MPEC cross-check — Phase 11
  (PLAN-07, PVAL-01). Phase 10 documents a provisional raw-dual convention only (D-06).
- **Retry-budget load-testing at realistic Benders iteration counts** — Phase 12 (hardening).
  Phase 10 delivers the mechanism; Phase 12 stress-tests it.
- **Shared-transmission `coupling.jl` + Nash diagonalization** — Phase 13 (NASH-01..04).
- **Automated no-binaries CI guard** — Phase 14 (PVAL-04). Phase 10 upholds continuous-only by
  convention; Phase 14 enforces it mechanically.

</deferred>

---

*Phase: 10-oracle-coupling-wiring-resilience*
*Context gathered: 2026-07-22*
