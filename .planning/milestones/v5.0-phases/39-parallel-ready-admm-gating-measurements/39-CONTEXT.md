# Phase 39: Parallel-Ready ADMM & Gating Measurements - Context

**Gathered:** 2026-10-23
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommended answers auto-accepted per operator instruction)

<domain>
## Phase Boundary

A researcher can opt in to solving aggregator subproblems concurrently with results identical to
serial, and the gating facts for later phases (Clarabel concurrency, 8500 memory attribution) are
measured. Deliverables: a documented Clarabel concurrency/determinism spike (including the
`direct_model` question); a threaded-executor opt-in on `solve_admm` with serial-identical results;
error-parity for parallel tasks; run-provenance thread counts with executor-invariant scenario
hash/filename; per-aggregator additive result keys; and a documented attribution of the ~3.4 GiB
unattributed IEEE-8500 memory growth (SCALE-06). Requirements: PAR-01..05, SCALE-06.

v5.0 policies bind this phase: **golden policy** (default path byte-identical, canary never
re-pinned) and **honesty policy** (report failed certificates, never loosen the gate; memory-
infeasible/refused are valid outcomes).

</domain>

<decisions>
## Implementation Decisions

### Threaded Executor API
- Opt-in via `parallel::Bool = false` keyword on `solve_admm` — additive; default keeps the serial
  path byte-identical (v5.0 golden policy).
- `parallel=true` with `Threads.nthreads()==1` fails loud with `ArgumentError` (project fail-loud
  policy) — no silent serial fallback.
- Task granularity: one `Threads.@spawn` task per aggregator per ADMM iteration, joined before the
  λ/dual update (aggregators are independent given λ).
- Threaded path lives as a split execute step inside `admm_phases.jl` (serial/threaded share
  build + consensus) — no new module.

### Determinism Bar & Solver Threading
- Equality bar: serial and threaded runs are `==` on iterations, residual traces, welfare and
  prices on a multi-aggregator fixture; Clarabel solves inside tasks pinned to 1 solver thread.
- The Clarabel concurrency/determinism spike measures BOTH indirect (default) and `direct_model`
  construction under `-t 4`; threaded execution is only enabled if the production configuration
  passes.
- `BLAS.set_num_threads(1)` pinned per task (small aggregator QPs; oversubscription harms both
  determinism and performance).
- The default serial path must keep the IEEE-13 ADMM knife-edge canary unchanged
  (`iters = 56`, `welfare = -4823.66604824162`) — canary never re-pinned.

### Error Attribution & Run Provenance
- Errors raised inside a parallel task are captured and rethrown after join as the ORIGINAL
  exception type (Clarabel error / `CertificateError` / `ConvergenceError`) with the same node
  attribution as serial — no new wrapper error type.
- Run provenance gains additive keys (`julia_threads`, `blas_threads`) in `result_to_dict`; the
  executor choice NEVER enters `_scenario_identity`, so scenario `==`, `hash` and saved filename
  are unchanged.
- ADMM results expose per-aggregator dispatch, utilities, import profile and per-slot prices as
  ADDITIVE keys on the certified result — existing consumers and goldens untouched.

### SCALE-06 Memory Attribution
- Method: instrumented staged runs at the Phase-35 boundary points (IEEE-8500, d=0.1, T=10/24) —
  RSS deltas per stage (build / per-iteration / per-hour DSO solver state / consolidation) → CSV.
- Deliverable: documented CSV + doc note in `results/ieee8500_benchmark/` (Phase-35 pattern).
- Success bar: each component attributed within a stated measurement tolerance with the residual
  explained; a documented honest residual is an acceptable outcome (honesty policy).
- Sequencing: attribution runs after the parallel executor + additive keys land, reusing them.

### the agent's Discretion
- Specific spike harness mechanics, test file naming, and exact instrumented-run staging within
  the bounds above are at the agent's discretion.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/admm/solve_admm.jl` — single entry point, build-once/iterate named phases
  (`_admm_build` / `_admm_iterate!` / `_admm_certify` in `src/admm/admm_phases.jl`); aggregator
  solves are the natural parallel grain.
- IEEE-13 ADMM knife-edge canary test (quick task 260825-w5b) — pinned iters/welfare regression
  guard for the default serial path.
- Provenance seam: `result_to_dict` + `run_and_store` `@tagsave` (DrWatson) in
  `src/experiments/store.jl`; `_scenario_identity` savename-based filename with stable-hex hash.
- Phase-35 measurement artifacts: `results/ieee8500_benchmark/{hybrid_diagnostic,point_resources,
  memory_wall_recharacterization}.csv` — the ~3.4 GiB unattributed growth baseline being attributed.
- Hybrid ADMM exactness gate (defaulted in Phase 35) — certificate refusal semantics to preserve
  under parallelism.

### Established Patterns
- Fail-loud typed errors (`ConvergenceError`, `CertificateError` with kinds) — never swallowed.
- Golden policy: additive keys / new flags default off; byte-identical default path; canary never
  re-pinned; gate-then-golden ordering; measurement-before-golden for pinned numeric bands.
- Honesty policy: failed certificates reported, not loosened; memory-infeasible/refused are valid
  measured outcomes.
- Single-seed determinism idiom (StableRNG threaded through) — bit-identical repeat runs expected.
- Test invocation hazard: use `julia --project=. -e 'import Pkg; Pkg.test()'`, never
  `--project=test` sibling-worktree idiom.

### Integration Points
- `solve_admm` kwargs + returned NamedTuple (additive per-aggregator keys attach here).
- `admm_phases.jl` iterate loop — the aggregator-solve step is where `Threads.@spawn` lands.
- `result_to_dict`/`run_and_store` provenance stamp — thread-count keys + executor invariance.
- `_scenario_identity` — must remain executor-blind.
- Clarabel solver factory (`src/solver/factory.jl`) — where solver-side thread pinning applies.

</code_context>

<specifics>
## Specific Ideas

- ROADMAP research flags to carry into planning: Clarabel concurrency spike, the `direct_model`
  question, and 8500 memory attribution (echoed in STATE.md Operator Next Steps).
- Spike must record whether threaded solves are bitwise-equal to serial under `-t 4`; threaded
  execution enabled ONLY on a pass.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
