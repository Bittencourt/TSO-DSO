# Phase 10: Oracle Coupling Wiring & Resilience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-22
**Phase:** 10-oracle-coupling-wiring-resilience
**Areas discussed:** z shape & pin form, λ_j[t]→π_s reconciliation, retry/checkpoint policy, build-once oracle home

---

## z shape & pin form (PLAN-01)

### Q1 — z shape

| Option | Description | Selected |
|--------|-------------|----------|
| Per-hour profile z[t] | length-T import profile; pin p_import[t]==z[t]; dual is length-T; matches existing hourly structure 1:1 | ✓ |
| Scalar per-scenario z | single interconnection quantity; one pin, one dual = π_s; aggregation lives in the constraint | |
| You decide | planner picks from Benders master variable dimensioning | |

**User's choice:** Per-hour profile z[t]
**Notes:** Keeps 1:1 match with existing `p_import[t]` / `balance_p` (bus×time); reconciliation to a scalar becomes a genuine PLAN-02 step.

### Q2 — Dual source

| Option | Description | Selected |
|--------|-------------|----------|
| Pin dual when pinned, keep free-path | z!==nothing → dual(pin); z===nothing → unchanged balance_p[root,:]; backward-compatible | ✓ |
| Always read balance_p[root,:] | one code path but risks silent-wrong price; contradicts PLAN-01 "returns ITS dual" | |
| You decide | planner picks from KKT relationship | |

**User's choice:** Pin dual when pinned, keep free-path
**Notes:** v1 free-import contract and all callers/tests stay valid; only the pinned branch is new.

---

## λ_j[t]→π_s reconciliation (PLAN-02)

### Q1 — π_s role

| Option | Description | Selected |
|--------|-------------|----------|
| Reporting/interpretation only | cuts use full length-T π[t] vector; π_s is a derived summary, never fed into optimization | ✓ |
| π_s drives the coupling | master/Nash consumes the scalar aggregate; higher stakes on the weighting | |
| You decide | planner determines from master/Nash dimensioning | |

**User's choice:** Reporting/interpretation only
**Notes:** Keeps the Benders cut mathematically exact (vector gradient); scalarization is off the solve path.

### Q2 — Sign convention

| Option | Description | Selected |
|--------|-------------|----------|
| Raw JuMP dual + toy-case invariant | π=∂(welfare)/∂z[t], documented, pinned by one hand-computed toy case; Phase 11 certifies/flips | ✓ |
| Economic 'DSO-pays-TSO' sign | flip into explicit signed price now; pre-commits to a leader/follower reading Phase 11 should resolve | |
| Parametrize the sign | carry a sign_convention flag; most flexible, adds config surface | |

**User's choice:** Raw JuMP dual + toy-case invariant
**Notes:** Honors STATE.md blocker — do not re-resolve the PSR-note ambiguity by re-reading THEORY-papers.md.

### Q3 — Aggregation rule

| Option | Description | Selected |
|--------|-------------|----------|
| Duration-weighted sum | π_s = Σ_t Δt·π[t]; plain sum at Δt=1h today, correct for future non-uniform Δt | ✓ |
| Plain sum | π_s = Σ_t π[t]; hard-codes 1h assumption | |
| Time-average | π_s = mean(π[t]); different units (average price not total) | |
| You decide | off the solve path, any documented choice defensible | |

**User's choice:** Duration-weighted sum
**Notes:** Units price·hour = per-scenario interconnection value.

---

## Retry/checkpoint policy (PLAN-03)

### Q1 — Retry strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Escalating conditioning perturbation | solve as-is, then perturb per-unit scaling / Clarabel settings; bounded N; duals stay Clarabel-grade | ✓ |
| Plain re-solve N times | no change per attempt; Clarabel deterministic so unlikely to recover | |
| Escalate to SCS fallback | last-resort SCS; rejected — noisy duals violate price-trust discipline | |
| You decide | researcher designs ladder empirically against fixtures | |

**User's choice:** Escalating conditioning perturbation
**Notes:** Targets the documented per-unit-base cone-slack root cause; never falls back to noisy SCS duals.

### Q2 — Exhaustion + checkpoint granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Raise + resumable checkpoint per oracle call | raise loudly on exhaustion; checkpoint keyed by (scenario, z-iterate) | |
| Raise + checkpoint per Benders iteration | same loud raise; coarser checkpoint (one per completed iteration) | ✓ |
| You decide | planner sets once Benders iteration structure is concrete | |

**User's choice:** Raise + checkpoint per Benders iteration
**Notes:** Never silent-skip/corrupt (STATE.md blocker); resume redoes the current iteration's scenario solves.

---

## Build-once oracle home (PLAN-01)

### Q1 — Home & reuse strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New src/planning/ module, mirror ADMM pattern | build_planning_oracle reuses contribute! verbatim, z as Parameter, zero edits to welfare_solve.jl/oracle.jl | ✓ |
| Refactor solve_welfare to share a builder | DRY-er but modifies a Phase-5 file; risks "unmodified" constraint | |
| You decide | planner chooses after reading welfare_solve.jl in full | |

**User's choice:** New src/planning/ module, mirror ADMM pattern
**Notes:** Mirrors build_dso_opt/solve_dso!; satisfies "solve_welfare/operational_oracle unmodified" by construction. src/planning/ is also Phase 13's coupling.jl home.

---

## Claude's Discretion

- Exact perturbation-ladder magnitudes and retry-budget N (measure empirical failure rate on planning fixtures — do not assume v1's rate).
- Checkpoint file format/location; `PlanningOracle` struct fields.
- Warm-starting the build-once model across successive z-iterates.
- The concrete toy-case fixture asserting the sign invariant.

## Deferred Ideas

- Benders master/follower LP + cut accumulation + UB/LB gap → Phase 11.
- Leader/follower + sign certification via BilevelJuMP MPEC → Phase 11.
- Retry-budget load-testing at realistic iteration counts → Phase 12.
- Shared-transmission coupling.jl + Nash diagonalization → Phase 13.
- Automated no-binaries CI guard → Phase 14.
