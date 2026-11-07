# Phase 39: Parallel-Ready ADMM & Gating Measurements - Research

**Researched:** 2026-10-23
**Domain:** Julia `Threads.@spawn` task parallelism over independent JuMP/Clarabel QP subproblems; bitwise determinism under threading; memory attribution via staged RSS instrumentation
**Confidence:** HIGH (core determinism & exception claims empirically verified this session on the project's own pinned toolchain, in this repo's environment)

## Summary

Phase 39 adds an opt-in threaded executor to `solve_admm` with a bitwise-equality guarantee against the serial path, plus two gating measurements for later phases (Clarabel concurrency spike, SCALE-06 memory attribution). The codebase is unusually well-prepared: the aggregator solve is already an isolated grain (`_react_agr_solve!(rmode, st, j)` in `src/admm/admm_phases.jl`), every aggregator owns its own JuMP model + CachingOptimizer + Clarabel instance (the JuMP docs' "one model per task" rule is satisfied by construction), and all state writes are per-`j` keyed (`st.a[j]`, `st.util[j]`, `ls.b[j]`) so concurrent writes are disjoint.

**The decisive empirical result (this session, Julia 1.12.5 / JuMP 1.30.1 / Clarabel 0.11.1, `-t 4`):** Clarabel solves executed inside `Threads.@spawn` tasks are **bitwise-identical to serial** — solutions, both dual vectors, objective values, and barrier iteration counts all compared bit-equal across 6 seeded QPs, both at default BLAS threads and with `BLAS.set_num_threads(1)`. This is a strong preliminary pass of the spike's central question, but the full spike must still run on a real multi-aggregator ADMM fixture with the production configuration before the threaded executor is enabled.

Three exception-handling facts were verified live and shape PAR-03: `fetch` of a failed spawned task throws `TaskFailedException` (original preserved at `.task.exception`); `@sync` wraps failures in `CompositeException` (unusable for error parity); fetch-in-`load_nodes`-order plus `throw(e.task.exception)` reproduces serial's error type, message, kind, iterations, and first-failing-node attribution exactly. Two repo beliefs were also corrected live: `direct_model(Clarabel.Optimizer())` no longer errors at construction on the pinned versions — it fails at the first variable addition (`AddVariableNotAllowed`), which still settles the spike's `direct_model` question (the ADMM build-once/`set_objective_coefficient` pattern is impossible under direct construction); and both `MOI.NumberOfThreads() => 1` and `max_threads => 1` are accepted by Clarabel 0.11.1 (support added in 0.11.0).

**Primary recommendation:** split the AGR-solve step in `admm_phases.jl` into serial/`@spawn` variants sharing build + consensus; spawn one task per aggregator, **fetch in `load_nodes` order**, apply `st.a[j]`/`st.util[j]` writes in the serial region, unwrap and rethrow `.task.exception` on failure; pin `BLAS.set_num_threads(1)` once at executor entry; gate everything on the spike passing bitwise equality on a real fixture; keep the default serial path byte-identical (canary `iters = 56`, `welfare = -4823.66604824162` untouched).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Threaded Executor API**
- Opt-in via `parallel::Bool = false` keyword on `solve_admm` — additive; default keeps the serial path byte-identical (v5.0 golden policy).
- `parallel=true` with `Threads.nthreads()==1` fails loud with `ArgumentError` (project fail-loud policy) — no silent serial fallback.
- Task granularity: one `Threads.@spawn` task per aggregator per ADMM iteration, joined before the λ/dual update (aggregators are independent given λ).
- Threaded path lives as a split execute step inside `admm_phases.jl` (serial/threaded share build + consensus) — no new module.

**Determinism Bar & Solver Threading**
- Equality bar: serial and threaded runs are `==` on iterations, residual traces, welfare and prices on a multi-aggregator fixture; Clarabel solves inside tasks pinned to 1 solver thread.
- The Clarabel concurrency/determinism spike measures BOTH indirect (default) and `direct_model` construction under `-t 4`; threaded execution is only enabled if the production configuration passes.
- `BLAS.set_num_threads(1)` pinned per task (small aggregator QPs; oversubscription harms both determinism and performance).
- The default serial path must keep the IEEE-13 ADMM knife-edge canary unchanged (`iters = 56`, `welfare = -4823.66604824162`) — canary never re-pinned.

**Error Attribution & Run Provenance**
- Errors raised inside a parallel task are captured and rethrown after join as the ORIGINAL exception type (Clarabel error / `CertificateError` / `ConvergenceError`) with the same node attribution as serial — no new wrapper error type.
- Run provenance gains additive keys (`julia_threads`, `blas_threads`) in `result_to_dict`; the executor choice NEVER enters `_scenario_identity`, so scenario `==`, `hash` and saved filename are unchanged.
- ADMM results expose per-aggregator dispatch, utilities, import profile and per-slot prices as ADDITIVE keys on the certified result — existing consumers and goldens untouched.

**SCALE-06 Memory Attribution**
- Method: instrumented staged runs at the Phase-35 boundary points (IEEE-8500, d=0.1, T=10/24) — RSS deltas per stage (build / per-iteration / per-hour DSO solver state / consolidation) → CSV.
- Deliverable: documented CSV + doc note in `results/ieee8500_benchmark/` (Phase-35 pattern).
- Success bar: each component attributed within a stated measurement tolerance with the residual explained; a documented honest residual is an acceptable outcome (honesty policy).
- Sequencing: attribution runs after the parallel executor + additive keys land, reusing them.

### the agent's Discretion
- Specific spike harness mechanics, test file naming, and exact instrumented-run staging within the bounds above are at the agent's discretion.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PAR-01 | Opt-in threaded executor; serial default byte-identical (canary unchanged) | Parallel grain identified (`_react_agr_solve!` loop); split-execute pattern in `admm_phases.jl`; kwarg guard design; canary file + pin mechanics documented; executor-blind scenario identity via `Scenario.==`/`hash` analysis |
| PAR-02 | Threaded == serial on multi-aggregator fixture; gated on documented spike | **Empirically verified**: Clarabel solves under `Threads.@spawn` at `-t 4` are bitwise-identical to serial (6-seed probe, this repo's toolchain); spike design + conventions documented; equality-test field-selection trap documented (`AdmmResiduals` mutable → default `==` is identity) |
| PAR-03 | Parallel-task solver errors surface with same type + node attribution as serial | **Empirically verified**: `fetch`→`TaskFailedException` wrapper, `@sync`→`CompositeException`, fetch-in-order + `throw(.task.exception)` recipe reproduces serial attribution exactly |
| PAR-04 | Provenance records thread/BLAS counts; executor-blind scenario identity | `result_to_dict` additive-key seam located (`src/experiments/store.jl:191`); `_scenario_identity`/`scenario_filename` executor-blindness mechanism verified; `Scenario.==`/`hash` include strategy field-wise → `parallel` must NOT be a strategy field |
| PAR-05 | Per-aggregator dispatch, utilities, import profile, per-slot prices as additive keys | Key sources mapped: `st.util[j]`, `value.(agr.pag)`, device vars in `agr.ctx.agg_device_vars[j]` (the `q_devices` precedent), `st.p_import`, `λ_mat` rows; additive NamedTuple keys return unchanged |
| SCALE-06 | ~3.4 GiB unattributed IEEE-8500 memory growth profiled and attributed | Phase-35 baseline quantified from `results/ieee8500_benchmark/*.csv` (5.92 GiB peak T=10; +0.23 GiB build; +0.89 GiB first optimize; 4.56 GiB loop delta; 122 AgrOpt builds; 10.17 GiB at T=24); staged-RSS harness pattern located in `scripts/benchmark_ieee8500.jl`; docs pattern in `docs/literate/ieee8500_scaling.jl` |
</phase_requirements>

## Project Constraints (from CLAUDE.md / AGENTS.md)

No `AGENTS.md` exists; `CLAUDE.md` carries the binding directives:

- **Hand-roll ADMM/Benders** — no Coluna/StructJuMP (the threaded executor is a modification of the existing hand-rolled loop, consistent).
- **Solver discipline** — open-source defaults via the single factory (`select_optimizer`); models never name a solver; Clarabel is the conic/QP default.
- **Reproducibility** — seeded data generation, pinned `Project.toml`/`Manifest.toml`; results reproducible. This is what the bitwise-equality bar protects.
- **Documentation is a hard requirement** — the spike write-up and the SCALE-06 doc note are deliverables, not extras.
- **Test invocation hazard (from STATE.md, binding)**: run the suite via `julia --project=. -e 'import Pkg; Pkg.test()'` — NEVER `--project=test` sibling-worktree idiom.
- **JuliaFormatter** is active (`format_docstrings = true`); beware the documented docstring `|`-continuation content-loss hazard.
- **Julia compat floor 1.10**; test env resolves on 1.12 (the local toolchain is 1.12.5).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Threaded AGR subproblem execution | Julia runtime task layer (`Threads.@spawn`) inside `src/admm/admm_phases.jl` | — | Aggregator solves are pure-Julia QPs on independent JuMP models; no solver-side threading exists (Clarabel.jl QDLDL is single-threaded) — concurrency lives entirely at the task layer |
| Determinism guarantee | Solve layer (Clarabel per-instance determinism) + serial reduction region | BLAS config (`BLAS.set_num_threads(1)`) | IPM with fixed start is deterministic per instance; bitwise equality additionally requires the post-join reductions (residual accumulation, dual step) to keep the serial float order |
| Error capture/rethrow | `admm_phases.jl` join region | `src/core/errors.jl` types (unchanged) | Tasks return results or throw; join fetches in `load_nodes` order and rethrows the ORIGINAL exception object — no wrapper type |
| Provenance thread counts | `src/experiments/store.jl` (`result_to_dict`) | — | Additive keys measured at save time from the live process (`Threads.nthreads()`, `BLAS.get_num_threads()`) |
| Scenario identity (executor-blind) | `src/experiments/store.jl` (`_scenario_identity`) | `src/experiments/Scenario.jl` (`==`/`hash` — unchanged) | `parallel` stays a `solve_admm` kwarg, never a `Scenario`/strategy field |
| Per-aggregator result keys | `src/admm/admm_phases.jl` (`_admm_certify` return) | `src/experiments/run.jl` (`run(::ADMM, s)` passthrough if wired) | All quantities already exist in `AdmmState`/`AgrOpt` at certify time |
| Clarabel concurrency spike | `.planning/spikes/NNN-…/` (repo spike conventions) | `src/solver/factory.jl` (observations only — no mutation) | Spikes observe without mutating `src/` per `.planning/spikes/CONVENTIONS.md` |
| SCALE-06 memory attribution | `scripts/benchmark_ieee8500.jl` staged runs → `results/ieee8500_benchmark/*.csv` | `docs/literate/ieee8500_scaling.jl` (doc note) | Phase-35 measurement pattern extended with finer staging |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia `Threads` (stdlib) | shipped with 1.10/1.12 | `Threads.@spawn`, `Threads.nthreads()`, dynamic task scheduling | No new dependency; the project's Julia floor (1.10) has stable task-based parallelism with the `:default`/`:interactive` threadpool split (1.10+) [VERIFIED: julia --version + stdlib docs] |
| `LinearAlgebra.BLAS` (stdlib) | shipped | `set_num_threads(1)` / `get_num_threads()` | The only implicit thread source in pure-Julia Clarabel's numeric path (OpenBLAS via SuiteSparse); LBT config verified on this host [VERIFIED: local probe] |
| Clarabel.jl | **0.11.1** (pinned in `Project.toml` `[compat]`) | AGR-OPT QP / DSO-OPT SOCP solver | Pure-Julia IPM; per-instance deterministic; **no internal thread pool on the default QDLDL path** (QDLDL is "a single threaded solver" per official docs); `MOI.NumberOfThreads` + `max_threads` settings accepted in 0.11.1 [VERIFIED: local probe + ClarabelDocs + CHANGELOG 0.11.0 PR #196] |
| JuMP | **1.30.1** (pinned) | Model layer | Official parallelism tutorial prescribes exactly this phase's shape: independent models per task, solver thread pinning via `MOI.NumberOfThreads() => 1`, no shared-model mutation [CITED: jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism] |
| `CSV.jl` + `DataFrames.jl` | 0.10.16 / 1.8.2 (pinned) | Spike + SCALE-06 CSV outputs | Already in `Project.toml`; spike conventions use CSV output |
| DrWatson | 2.19.1 (pinned) | `@tagsave` provenance stamping | Existing `run_and_store` seam; additive keys ride the existing dict |

**No new packages are required.** Everything is stdlib or already pinned. This is deliberate: the locked design uses `Threads.@spawn` (stdlib), and the measurement deliverables reuse CSV/DataFrames/DrWatson.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Threads.@spawn` (dynamic scheduling) | `Threads.@threads :static for` | `@threads` needs a static schedule for safe per-iteration buffers and coerces the loop body; `@spawn` composes with fetch-in-order error handling and is the locked decision |
| `Channel{T}` result passing | Preallocated `Vector{Future}` + fetch-in-order | Channel adds ordering machinery for nothing; futures give per-task exception capture and deterministic fetch order for free |
| `OhMyThreads.jl` / `Folds.jl` | stdlib `@spawn` | Extra dependency for zero benefit at this grain size; locked decision already stdlib |
| Staged `/usr/bin/time -v` only | `Sys.maxrss()` deltas + `GC.gc()` staging inside the harness | Phase-35 harness already uses both; `Sys.maxrss()` is monotonic whole-process HWM (limits per-stage deltas — see Pitfall 7); `/proc/self/status` VmRSS snapshots complement it. Keep the existing mixed approach |

**Installation:** none (no new packages).

## Package Legitimacy Audit

> No external packages are installed by this phase. All libraries used are (a) Julia stdlib (`Threads`, `LinearAlgebra.BLAS`, `Sys`), or (b) already pinned in `Project.toml`/`Manifest.toml` (Clarabel 0.11.1, JuMP 1.30.1, CSV, DataFrames, DrWatson). A legitimacy check on already-pinned, already-vendored dependencies is out of scope for this gate — no new attack surface is introduced.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none — no new packages) | — | — | — | — | — | N/A |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                       solve_admm(feeder, pf, aggs; …, parallel::Bool = false)
                                              │
                        ┌─────────────────────┴─────────────────────┐
                        │  GUARD: parallel==true && nthreads()==1   │
                        │  → ArgumentError (fail loud, no fallback) │
                        └─────────────────────┬─────────────────────┘
                                              │
                                   _admm_build (SHARED, serial)
                        one AgrOpt per aggregator + one DsoOpt
                                              │
                            ┌─────────────────┴──────────────────┐
                            │  _admm_iterate!  (loop per k)      │
                            └─────────────────┬──────────────────┘
                                              │
                 ┌────────────────────────────┼─────────────────────────────┐
                 │ STEP 1: AGR solves         │ STEP 2..5 (serial, both     │
                 │ serial: for j in load_nodes│ executors, identical code)  │
                 │   _react_agr_solve!(j)     │                             │
                 │ threaded:                  │                             │
                 │   BLAS.set_num_threads(1)  │                             │
                 │   futs[j] = @spawn solve(j)│──join──▶ apply st.a[j]/     │
                 │   fetch in load_nodes order│          st.util[j] serially│
                 │   on failure: throw(        │                             │
                 │     fut.task.exception)    │                             │
                 ├────────────────────────────┤                             │
                 │ STEP 2: solve_dso!         │── residual accumulation     │
                 │ STEP 3: Boyd diagnostics   │   (fixed j,t order —        │
                 │ STEP 4: record!/converged? │   FLOAT-ORDER CONTRACT)     │
                 │ STEP 5: dual step + ρ adapt│── λ update before next k    │
                 └────────────────────────────┴─────────────────────────────┘
                                              │ converged
                                   _admm_certify (final AGR re-solves
                                   + DSO gate; AGR re-solves may reuse
                                   the same threaded split)
                                              │
                              result NamedTuple + NEW additive keys:
                     agr_dispatch / agr_utility / agr_import / agr_prices
                                              │
                              run_and_store → result_to_dict
                              + julia_threads, blas_threads  (additive)
                              (executor NEVER enters _scenario_identity →
                               scenario ==, hash, filename unchanged)
```

Side deliverables (independent of the loop):

```
Spike (.planning/spikes/NNN-clarabel-concurrency/):
  serial reference ──▶ threaded @spawn (-t 4, BLAS=1, solver threads=1) ──▶ bitwise compare
  indirect (CachingOptimizer Model) AND direct_model leg ──▶ verdict recorded
  PASS ──▶ threaded executor enabled;  FAIL ──▶ stays default-off (honest outcome)

SCALE-06 (scripts/benchmark_ieee8500.jl staged runs):
  stage RSS snapshots (build / first solve / per-iter state / AgrOpt builds /
  per-hour DSO solver state / consolidation) at d=0.1 T=10 & T=24
  ──▶ CSV in results/ieee8500_benchmark/ + doc note in docs/literate/ieee8500_scaling.jl
```

### Recommended Project Structure
```
src/admm/
├── admm_phases.jl        # split execute step lands HERE (locked decision): the
│                         # AGR-solve block gains a serial/threaded branch; no new module
├── admm_state.jl         # AdmmState (maybe gains per-aggregator snapshot fields for PAR-05)
├── solve_admm.jl         # `parallel::Bool = false` kwarg + guard
├── AgrOpt.jl             # unchanged (one model per aggregator — already the right grain)
└── DsoOpt.jl             # unchanged
src/experiments/
└── store.jl              # result_to_dict: + julia_threads, blas_threads (additive)
src/solver/
└── factory.jl            # solver-thread pinning applied by the ADMM executor, NOT a factory
│                         # default change (QP()/SOCP() defaults must stay byte-identical)
.planning/spikes/
└── NNN-clarabel-concurrency/   # sweep.jl + README.md + CSV (repo spike conventions)
scripts/
└── benchmark_ieee8500.jl       # extended staging for SCALE-06
results/ieee8500_benchmark/
└── memory_attribution.csv      # SCALE-06 deliverable
docs/literate/
└── ieee8500_scaling.jl         # appended doc note (Phase-35 pattern)
test/
└── test_admm_parallel.jl       # serial-vs-threaded equality + error parity (see Validation)
```

### Pattern 1: Split AGR-solve step with fetch-in-order join (the load-bearing pattern)

**What:** The AGR block inside `_admm_iterate!` (`for j in load_nodes; _react_agr_solve!(rmode, st, j); end`) becomes a branch: serial keeps the exact current loop; threaded spawns one task per aggregator, then a serial join applies results in `load_nodes` order.
**When to use:** both the mid-loop step and the `_admm_certify` final AGR re-solves (the certify step's certificates can throw, so error parity applies there too).
**Example (empirically verified semantics):**
```julia
# Threaded branch (schematic — inside admm_phases.jl)
BLAS.set_num_threads(1)                       # ONCE before spawning (global state; see Pitfall 1)
futs = [Threads.@spawn _agr_task(st, j) for j in load_nodes]
# serial join in load_nodes order = serial error attribution (PAR-03):
for (idx, j) in enumerate(load_nodes)
    r = try
        fetch(futs[idx])
    catch e
        e isa TaskFailedException ? throw(e.task.exception) : rethrow()  # ORIGINAL type
    end
    st.a[j] = r.pag; st.util[j] = r.utility   # writes happen in the SERIAL region (no Dict races)
end
```
The task body must read only `st` fields it needs (λ[j], c[j], ρf, react.μq[j], react.d[j], react.ρ_qf — all per-`j` or loop-invariant reads; no writes to `st` inside the task). Writes commute exactly (disjoint keys), and the residual accumulation that follows is serial in the fixed `for j in load_nodes, t in 1:T` order, so the FLOAT-ORDER CONTRACT (`admm_state.jl` header) is preserved — this is why `==` equality is achievable at all.

### Pattern 2: Exception capture verified live (PAR-03 recipe)

Verified on Julia 1.12.5, `-t 4`:
```julia
# fetch of a failed spawned task:
try
    fetch(fut)
catch e
    # e isa TaskFailedException; e.task.exception is the ORIGINAL error object
    throw(e.task.exception)   # type, msg, kind, iterations, MOI statuses all preserved
end
# NEVER @sync for this: a failing @sync block throws CompositeException of
# TaskFailedException entries — a NEW wrapper type, violating the locked decision.
# NEVER Base.lock-protect st.a writes from inside tasks either — apply in the join instead.
```
Fetch-in-order guarantees the FIRST failure in `load_nodes` order surfaces — matching serial's first-throw semantics. (Chronological-first, which raw `@sync` would give, does NOT match serial.)

### Pattern 3: Solver-thread pinning (Clarabel 0.11.1)
```julia
# Both accepted by Clarabel 0.11.1 through JuMP (verified live):
import JuMP: MOI
set_attribute(model, MOI.NumberOfThreads(), 1)   # supported since Clarabel.jl 0.11.0 (PR #196)
set_attribute(model, "max_threads", 1)           # low-level settings equivalent
# QDLDL (the default linear solver) is single-threaded anyway — pinning is belt-and-braces
# guarding the `direct_solve_method` selection (LDL :auto since 0.11.0) against picking a
# threaded backend. Applied where the ADMM builds models or in the spike — NOT by changing
# select_optimizer(QP())/SOCP() defaults (byte-identical factory discipline).
```

### Pattern 4: Provenance additive keys (executor-blind identity)
```julia
# src/experiments/store.jl — result_to_dict, right beside :julia_version:
d[:julia_threads] = Threads.nthreads()
d[:blas_threads]  = BLAS.get_num_threads()
# These describe the PROCESS, not the executor choice — measured, additive, and
# _scenario_identity is untouched, so scenario_filename / == / hash never move (PAR-04).
# CRITICAL: do NOT add `parallel` to the ADMM strategy struct — Scenario.== compares the
# strategy field-wise, so a `parallel` field would flip scenario == and hash (PAR-04 violation).
```

### Anti-Patterns to Avoid
- **`@sync` around the spawned tasks:** wraps failures in `CompositeException` (verified) — a new error type, violating the locked error decision.
- **Writing `st.a[j] = …` from inside the task:** Julia Dicts require manual locking when concurrently modified (official Julia manual); assigning to existing keys doesn't resize but is still formally a data race. Apply results in the serial join — it costs nothing and keeps a single writer.
- **`Threads.threadid()`-indexed state:** the thread a task runs on can change mid-task (JuMP docs "Danger" note); do not index buffers by threadid.
- **Closure variable shadowing (`Core.Box` race):** reusing a variable name inside and outside the `@spawn` body creates a silent data race (julia#14948, documented in JuMP's parallelism tutorial). Use distinct names or `local`.
- **Setting BLAS threads per-task:** `BLAS.set_num_threads` is process-global (LBT); calling it from N racing tasks is itself a race. Set once at executor entry (all tasks want 1 — semantically identical to "per task").
- **Making `parallel` a `Scenario`/strategy field:** changes `Scenario ==`/`hash`/filename — PAR-04 violation. Kwarg on `solve_admm` only (locked decision).
- **Tuning the exactness gate or re-pinning the canary** to accommodate threading: prohibited (honesty + golden policy). If threaded ≠ serial, the executor stays default-off and the spike documents why.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Task scheduling/joining | Custom thread pool or work queue | `Threads.@spawn` + `fetch` | Stdlib dynamic load balancing; custom pools reintroduce the bugs task scheduling already solved |
| Bitwise comparison of Float64 vectors | `isapprox` with tiny tolerances | literal `==` (or `isequal`) on the traces, and `reinterpret(UInt8, …)` byte comparison in the spike harness | The bar is BITWISE equality; `isapprox` would launder a genuine difference — the exact thing the golden policy forbids |
| Solver thread pinning | Env-var juggling (`OPENBLAS_NUM_THREADS` at launch) | `BLAS.set_num_threads(1)` in-process + `MOI.NumberOfThreads() => 1` | In-process pinning works under `Pkg.test()` regardless of launch env; env vars only set the default |
| Error attribution | A new error wrapper/carrying struct | existing `TSODSOError` types rethrown as-is | Locked decision: no new wrapper type; `TaskFailedException` unwrap gives exact parity for free |
| Provenance stamping | Custom git-stamping/serialization | existing `result_to_dict` + `@tagsave` seam | Already handles gitcommit/gitpatch/julia_version with the `pkgdir` gitpath fix |
| Memory staging | A new profiling package (MemoryProfiler.jl etc.) | `Sys.maxrss()` + `GC.gc()` staging + `/usr/bin/time -v` + `/proc/self/status` VmRSS — the Phase-35 harness idiom | Monotonic HWM + staged deltas already produced the Phase-35 CSVs; a new dependency adds nothing the raw counters don't (see Pitfall 7 for the HWM caveat) |
| Spike harness scaffolding | Ad-hoc script layout | `.planning/spikes/CONVENTIONS.md` structure (sweep.jl → CSV, README, controls) | Established, review-friendly, re-runnable |

**Key insight:** every hard part here (task runtime, solver determinism, error objects, provenance) already exists in the stack; the phase is precision wiring plus measurement, not infrastructure building.

## Runtime State Inventory

> Omitted — this phase adds a new opt-in code path and measurement deliverables; it is not a rename/refactor/migration of existing identifiers. (No stored-data keys, service configs, OS registrations, secret names, or build artifacts carry any renamed string; verified by reading the touched seams: `solve_admm` kwargs are additive, `result_to_dict` keys are additive, no data migrations exist in this repo — results live in gitignored `data/` + committed `results/*.csv`.)

## Common Pitfalls

### Pitfall 1: Global BLAS state leaks across the sequential test runner
**What goes wrong:** `BLAS.set_num_threads(1)` is process-global. TestItemRunner executes `@testitem`s **sequentially in one process** (verified in TestItemRunner 1.1.5 source: plain `for` loop over items). A parallel test that sets BLAS threads to 1 without restoring leaves every later item (including the knife-edge canary) running under a different BLAS config than the one its pins were measured under.
**Why it happens:** BLAS thread count can change floating-point reduction order inside BLAS calls; the canary sits on a documented numerical knife-edge where codegen/toolchain perturbations flip the trajectory. A BLAS-config change is exactly such a perturbation.
**How to avoid:** every test (or harness) that touches `BLAS.set_num_threads` must save and restore it in a `finally`. The canary must be re-verified green in the same process after the parallel tests run. (Mitigating data point: this session's probe found BLAS 2-vs-1 threads bitwise-identical on a representative QP — but the canary's real fixture is the arbiter, not a probe.)
**Warning signs:** canary `iters`/welfare flips only when the full suite runs (item order effects), never when the canary file runs alone.

### Pitfall 2: `@sync`/`fetch` wrapper types destroy error parity
**What goes wrong:** using `@sync begin … end` around the spawns converts a `CertificateError` into a `CompositeException` of `TaskFailedException`s (verified live); `catch` sites matching `err isa CertificateError` (e.g. `solve_admm`'s own re-wrap at `solve_admm.jl:361-366`) stop matching.
**How to avoid:** fetch-in-order + `throw(e.task.exception)` (Pattern 2). The rethrow must happen OUTSIDE the task; note `rethrow()` (no-arg) only works inside the original `catch` — use `throw(obj)` with the captured exception object.
**Warning signs:** PAR-03 test fails on type rather than message.

### Pitfall 3: `Scenario.==`/`hash` include the strategy struct field-wise
**What goes wrong:** adding `parallel::Bool` to the `ADMM` strategy struct changes `Scenario ==`, `hash`, and therefore `scenario_filename` — directly violating PAR-04's executor-blind requirement (verified: `Scenario.jl:372` compares `a.strategy == b.strategy`).
**How to avoid:** keep `parallel` a `solve_admm` kwarg only. Provenance records the measured `Threads.nthreads()`/`BLAS.get_num_threads()`. (If a Scenario-level selector is ever needed — e.g. Phase 40's POP-05 scaling report — that is a deliberate, separately-reviewed identity-policy change, not a silent field addition.)
**Warning signs:** any new `Scenario` field in this phase's diff.

### Pitfall 4: Comparing whole result NamedTuples with `==`
**What goes wrong:** `AdmmResiduals` is a **mutable** struct — default `==` is identity (pointer) comparison, so two runs with bit-identical traces still compare `false`; likewise `dso_ctx` (a `ModelContext` wrapping a JuMP model).
**How to avoid:** the PAR-02 equality test compares selected fields explicitly: `iters`, `primal_trace`, `dual_trace`, `rho_trace` (all `Vector{Float64}` — element-wise value `==`), `welfare`, `dadp`, `exact_maxgap` — never the whole NamedTuple.
**Warning signs:** an equality test that fails despite identical printed traces.

### Pitfall 5: Parallel tests can't run under the default 1-thread suite
**What goes wrong:** local default is `Threads.nthreads() == 1` (verified). Under `Pkg.test()` without `JULIA_NUM_THREADS`, a threaded-executor test hits the `ArgumentError` guard and fails — or worse, someone weakens the guard to "make CI green."
**How to avoid:** the parallel equality/error-parity test must (a) fail loud with a clear instruction when `Threads.nthreads() == 1`, and (b) be invoked with `JULIA_NUM_THREADS=4` (documented command; possibly gated behind an env selector like `TSODSO_TEST_FILES=test_admm_parallel.jl` so the default suite and CI stay on the serial path). Any `@test_skip` under 1 thread needs an `expected_broken.txt` entry (the runner guard fails unexpected skip records).
**Warning signs:** green locally, red in CI (or vice versa) with `ArgumentError: parallel=true requires Threads.nthreads() > 1`.

### Pitfall 6: The float-order contract is the whole equality claim
**What goes wrong:** any temptation to "clean up" during the split — fusing the per-j loops, reordering the `set_rho!` ladder (dso first, then each AGR in `load_nodes` order), or letting tasks write `st` in completion order — changes floating-point summation/argument order and can flip the canary or the threaded-vs-serial equality.
**How to avoid:** threaded tasks must not touch ANY shared reduction; all reductions (`sq_r`, `sq_ds`, …) stay in the existing serial `for j in load_nodes, t in 1:T` loop; the `_react_dso_prepare!`/`solve_dso!` sequence stays exactly where it is. The `admm_phases.jl`/`admm_state.jl` headers document this contract — treat it as binding.
**Warning signs:** threaded run differs from serial at ~1e-16 relative (order change), or the canary flips.

### Pitfall 7: `Sys.maxrss()` is a monotonic high-water mark, not a per-stage gauge
**What goes wrong:** reading `Sys.maxrss()` at each stage boundary reports the running MAXIMUM, so intermediate readings can't show a stage's *retained* memory, and freeing between stages is invisible. The existing harness already notes this ("MONOTONIC, WHOLE-PROCESS high-water").
**How to avoid:** attribute via cumulative deltas with `GC.gc()` between stages (the Phase-35 idiom), complement with instantaneous `VmRSS` from `/proc/self/status` per stage when a non-monotonic reading matters; run the T=10 and T=24 points as separate processes (as Phase 35 did) so HWM resets per point.
**Warning signs:** a stage "delta" that goes negative, or a total that doesn't reconcile with `/usr/bin/time -v`.

### Pitfall 8: Per-hour DSO solver state is a hypothesis, not a finding
**What goes wrong:** SCALE-06's hypothesis ("retained per-hour DSO solver state; growth ~linear in T") comes from only two T points and is recorded in the CSV notes as hypothesis-only. Building the attribution stages around the assumed mechanism risks confirmation bias.
**How to avoid:** stage boundaries should isolate the candidate mechanisms independently — (a) 122 AgrOpt models+contexts at build time, (b) per-iteration retained state (measure across k=1..n without consolidation), (c) per-hour DSO solver state (measure `build_dso_opt` + first `optimize!` vs after-k-iterations), (d) consolidation. Report each with its tolerance and let the residual speak (honesty policy: a documented residual is an acceptable outcome).
**Warning signs:** stages hand-wavingly assigned to fit the linear-in-T story without an isolating measurement.

### Pitfall 9: JuliaFormatter docstring content loss
**What goes wrong:** the standing hazard — `format_docstrings = true` silently deletes docstring text when a wrapped line's continuation starts with `|`. This phase adds several docstrings (`parallel` kwarg, additive keys, spike docs).
**How to avoid:** avoid line-wrapped inline code spans whose continuation line begins with `|`; run the formatter and diff-check docstrings (the CI content-loss guard exists — don't fight it).
**Warning signs:** unexplained shrinking docstrings in the format commit.

## Code Examples

### Verified: Clarabel concurrency probe (the spike's core question, pre-answered on toy QPs)
```julia
# Source: this session's probe, this repo, Julia 1.12.5 / JuMP 1.30.1 / Clarabel 0.11.1, julia -t 4
ref = [build_and_solve(s) for s in 1:6]                      # serial reference
futs = [Threads.@spawn build_and_solve(s) for s in 1:6]      # concurrent, one task per "aggregator"
par = fetch.(futs)
# RESULT: x, dual(SOC), dual(linear), objective, BarrierIterations() all BITWISE-equal
# for all 6 seeds; also bit-equal when re-run with BLAS.set_num_threads(1).
# The real spike must repeat this on a multi-aggregator ADMM fixture with production kwargs.
```

### Verified: exception semantics (PAR-03)
```julia
# Source: this session's probe, Julia 1.12.5
t = Threads.@spawn throw(FakeCertError("bus 3 certificate refused"))
try fetch(t) catch e end
# e isa TaskFailedException; e.task.exception isa FakeCertError (msg preserved)
# @sync with 1 or 2 failures → CompositeException of TaskFailedException entries (WRAPPED — avoid)
# fetch-in-order surfaces the first failure in FETCH order; throw(obj) preserves type+msg
```

### Verified: direct_model question (spike deliverable, settled on pinned versions)
```julia
# Source: this session's probe; updates src/solver/factory.jl's 2026-07-18 note
m = direct_model(Clarabel.Optimizer())   # constructs WITHOUT error on JuMP 1.30.1
@variable(m, x[1:3])                     # ERROR: MathOptInterface.AddVariableNotAllowed
# ⇒ Clarabel remains copy_to-only: the ADMM build-once/set_objective_coefficient loop CANNOT
#   run on a direct model. The spike records this as the documented direct_model answer.
```

### Verified: solver thread pinning accepted
```julia
# Source: this session's probe, Clarabel 0.11.1
set_attribute(model, JuMP.MOI.NumberOfThreads(), 1)   # ACCEPTED (support since 0.11.0)
set_attribute(model, "max_threads", 1)                # ACCEPTED
```

### ADMM provenance measurement keys
```julia
# Source: src/experiments/store.jl (existing seam), values measured live at save time
d[:julia_threads] = Threads.nthreads()          # e.g. 1 default, 4 under JULIA_NUM_THREADS=4
d[:blas_threads]  = BLAS.get_num_threads()      # OpenBLAS/LBT, default 2 on this host
```

### Equality test skeleton (field-wise, bitwise)
```julia
# Source: field layout from src/admm/residuals.jl + solve_admm return NamedTuple
kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
s = TSODSO.Scenario(; kw..., strategy = :admm)   # multi-aggregator fixture per the equality bar
r_serial = TSODSO.run_scenario(s)                # default path (parallel defaults false)
# threaded run requires a direct solve_admm call with parallel = true under JULIA_NUM_THREADS>1
@test r_serial.iters == r_threaded.iters
@test r_serial.residuals.primal_trace == r_threaded.residuals.primal_trace
@test r_serial.residuals.dual_trace    == r_threaded.residuals.dual_trace
@test r_serial.welfare == r_threaded.welfare     # bitwise, NOT isapprox
@test r_serial.dadp    == r_threaded.dadp
```

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The 6-seed toy-QP bitwise determinism result transfers to the real multi-aggregator ADMM fixture (production model sizes, LIVE reactive mode, presolve/equilibration on real data) | Summary / PAR-02 | Threaded executor must stay default-off and the spike documents the failure — phase still completes honestly, but PAR-01/02 would be blocked pending investigation |
| A2 | `TestItemRunner 1.1.5` runs items sequentially in-process on all supported Julia versions (source-verified for the test/Manifest-pinned 1.1.5; the 1.10 leg re-resolves to 1.3.x — assumed same sequential behavior) | Pitfall 1 / Validation | A parallel-executing runner would make BLAS-global-state reasoning wrong; mitigation (save/restore in `finally`) is correct under either behavior, so risk is contained |
| A3 | Clarabel's default QDLDL path stays single-threaded for this fixture (no `direct_solve_method` override anywhere in the repo) | Standard Stack | If a threaded linear solver were in play, bitwise concurrency could fail; the spike would catch it before the executor is enabled |
| A4 | CI currently runs the suite single-threaded (no JULIA_NUM_THREADS in workflows) | Pitfall 5 / Validation | If CI already runs threaded, the parallel tests could run there directly; plan should check `.github/workflows` at execution time (researched flag: not verified this session) |
| A5 | SCALE-06 can reuse the Phase-35 harness flags (`--admm-only`, `--density`, `--t-horizon`) with added staging without breaking existing CSV schemas (new columns additive) | Architecture / SCALE-06 | New CSV file (new name) avoids schema friction entirely — recommended |

## Open Questions (RESOLVED)

> All four questions were resolved during planning; the adopted answers below are locked into the phase plans (references in each RESOLVED line).

1. **Should `run(::ADMM, s)` gain a `parallel` passthrough this phase?**
   - What we know: the locked decision pins the kwarg on `solve_admm`; PAR-01 says "a researcher can run the … ADMM with aggregator subproblems solved concurrently". A Scenario-level selector would violate executor-blind identity unless carefully excluded from `_scenario_identity` AND from `Scenario ==`/`hash` (which are field-wise over the strategy struct — so it cannot be a strategy field at all without a deliberate `==` change).
   - What's unclear: whether PAR-01's "researcher" is satisfied by a direct `solve_admm(...; parallel = true)` call (this research's reading: yes — the equality test itself is such a caller), or demands Scenario-level plumbing.
   - Recommendation: kwarg-only this phase; Scenario wiring is Phase 40's POP-05 concern (scaling report), flagged there.
   - **RESOLVED — adopted: kwarg-only.** `parallel` exists only as a `solve_admm` kwarg; `run(::ADMM, s)` and every Scenario identity seam stay untouched (implemented in plans 39-02 and 39-03).

2. **Should the `_admm_certify` final AGR re-solves also run threaded?**
   - What we know: the locked decision says "one `Threads.@spawn` task per aggregator per ADMM iteration". The certify pass re-solves each aggregator with certificates (can throw → PAR-03 applies).
   - What's unclear: whether certify-phase threading is required for the speedup story (POP-05, Phase 40) or optional polish.
   - Recommendation: implement the same split for the certify AGR re-solves (same helper, error parity preserved); it keeps the executor semantics uniform ("all AGR solves are executor-dispatched") and costs little.
   - **RESOLVED — adopted: certify re-solves run threaded.** The shared split helper serves both the mid-loop step and the certify AGR re-solves (plan 39-02, Task 3).

3. **Where should solver-thread pinning live: the factory or the executor?**
   - What we know: `select_optimizer(QP())`/`SOCP()` defaults must stay byte-identical (golden policy). Clarabel 0.11.1 accepts `MOI.NumberOfThreads() => 1` / `max_threads => 1` (verified).
   - What's unclear: none materially — but the mechanical placement matters.
   - Recommendation: pin in the threaded executor path only — apply the attribute to each AGR model right before spawning (or pass attrs through the existing `select_optimizer(SOCP(); attrs...)` kwargs seam at build time for the threaded build), never as a factory default change.
   - **RESOLVED — adopted: executor-path pinning.** `BLAS.set_num_threads(1)` (saved/restored in solve_admm.jl's finally) + `MOI.NumberOfThreads()=1` per AGR model applied at threaded-executor entry only (plan 39-02, Task 3); factory defaults untouched.

4. **Will the knife-edge canary survive a BLAS 2→1 default difference if a test leaks?**
   - What we know: probe showed bitwise-identical results across BLAS thread counts on toy QPs; the canary's fixture is a LIVE-mode IEEE-13 ADMM on a documented numerical knife-edge.
   - What's unclear: no measurement exists of the canary under BLAS threads=1.
   - Recommendation: the plan's canary-protection step should run the canary once with BLAS threads=1 (save/restore) and record the result in the phase findings; if it flips, that's a *measured environment fact* to document (like the 1.10/1.11/1.12.5/1.12.7 escalations), not a re-pin.
   - **RESOLVED — adopted: canary-after-parallel check.** Plan 39-04, Task 3 runs the canary in the SAME process after the parallel items (BLAS restored) and must hold its pins; any flip is recorded as a measured environment fact. The standalone record-only BLAS=1 canary leg is optional extra evidence, not a deliverable.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia ≥ 1.10 | everything | ✓ | 1.12.5 (local) | — |
| `julia -t N` / `JULIA_NUM_THREADS` | threaded executor + tests | ✓ | verified `-t 4` works | — |
| Clarabel.jl | all solves | ✓ | 0.11.1 (pinned) | — |
| `MOI.NumberOfThreads` pinning | solver thread pinning | ✓ | accepted by 0.11.1 (verified live) | `max_threads => 1` (also verified) |
| OpenBLAS (LBT) | BLAS thread pinning | ✓ | `BLAS.get_config()` = OpenBLAS64, default 2 threads | `BLAS.set_num_threads(1)` works |
| TestItemRunner | test infrastructure | ✓ | 1.1.5 (test Manifest, 1.12) / 1.3.x (1.10 re-resolve) | — |
| `/proc/self/status`, `/usr/bin/time` | SCALE-06 RSS staging | ✓ | standard Linux | `Sys.maxrss()` alone (HWM caveat) |
| earlyoom-controlled 15.5 GiB host | SCALE-06 T=24 runs | ✓ (same host class as Phase 35) | earlyoom `-m 12` kills runaway runs | T=24 run must be separately invoked; OOM is a measured outcome (honesty policy) |
| MathOptInterface as a *direct* dep | `MOI.NumberOfThreads` attribute name | ✗ (weak/indirect only) | — | use `JuMP.MOI` (existing repo idiom, `src/core/errors.jl`) — verified `import MathOptInterface` FAILS outside JuMP |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** MathOptInterface direct import → `JuMP.MOI` idiom (must not be `Pkg.add`ed — it's JuMP's transitive dep).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` + TestItems/TestItemRunner 1.1.5 (`@testitem` per file, sequential in-process execution) |
| Config file | `test/runtests.jl` (discovery root `test/`; `TSODSO_TEST_SET`, `TSODSO_TEST_FILES`, `expected_broken.txt` guard) |
| Quick run command | `julia --project=. -e 'import Pkg; Pkg.test()'` (never `--project=test`) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~32k tests, Phase-38 gate: 32304/0/0/5 on 1.12.5) |
| Threaded subset command | `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Canary check | `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PAR-01 (guard) | `parallel=true` with 1 thread → `ArgumentError` | unit | `TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` (guard item runs fine at 1 thread) | ❌ Wave 0 |
| PAR-01 (default byte-identical) | default serial path unchanged; canary `iters = 56`, welfare band | regression (existing) | `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ `test/test_admm_knifeedge_canary.jl` |
| PAR-02 | threaded == serial bitwise on multi-aggregator fixture (iters, traces, welfare, prices) | integration (needs `JULIA_NUM_THREADS=4`) | `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 |
| PAR-02 (spike gate) | spike artifact exists; verdict recorded; threaded enabled only on pass | manual/scripted | `.planning/spikes/NNN-…/sweep.jl` run + README verdict (scripted, minutes) | ❌ Wave 0 (spike dir) |
| PAR-03 | parallel-task `CertificateError`/`SolveFailedError` surfaces with same type/kind/iterations/attribution as serial | integration (threaded) | same threaded command as PAR-02 | ❌ Wave 0 |
| PAR-04 | `julia_threads`/`blas_threads` present in saved dict; executor choice leaves `scenario_filename`, `Scenario ==`, `hash` unchanged | unit (1-thread-safe) | `TSODSO_TEST_FILES=test_experiments_store.jl julia --project=. -e 'import Pkg; Pkg.test()'` (extend the existing provenance item) | ✅ extend existing store/provenance testitem |
| PAR-05 | additive per-aggregator keys present and correct on certified result; existing keys unchanged | unit | `TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 |
| SCALE-06 | staged attribution CSV reconciles (components + tolerance + residual = observed growth); doc note exists | scripted measurement + doc check | `scripts/benchmark_ieee8500.jl` staged runs at d=0.1 T=10/24 → CSV; manual review vs docs note (minutes-hours; T=24 ~12 min per Phase-35 timings) | ❌ Wave 0 (harness staging + CSV) |

### Sampling Rate
- **Per task commit:** canary + `test_admm_parallel.jl` (fast items) via `TSODSO_TEST_FILES`
- **Per wave merge:** full suite `julia --project=. -e 'import Pkg; Pkg.test()'` (both 1-thread and, after executor-enabling tasks, the threaded subset)
- **Phase gate:** full suite green (0 fail/0 error, expected_broken unchanged) + spike verdict recorded + SCALE-06 CSV+doc note committed before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/test_admm_parallel.jl` — guard test (1-thread-safe), threaded equality + error parity items (thread-gated with fail-loud instruction), PAR-05 additive keys items
- [ ] `.planning/spikes/NNN-clarabel-concurrency/` — `sweep.jl` (serial vs threaded vs direct_model legs, bitwise byte-compare, controls per spike conventions) + `README.md` verdict
- [ ] `scripts/benchmark_ieee8500.jl` staging extension + `results/ieee8500_benchmark/memory_attribution.csv` schema (new file; existing CSVs untouched)
- [ ] BLAS save/restore helper for any test touching global BLAS state (Pitfall 1)
- [ ] Framework install: none needed — all tooling present

## Security Domain

> `security_enforcement` is not disabled in `.planning/config.json`; included for completeness. This phase is numerical-research code with no network, auth, or persistence attack surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — no user-facing surface |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes (internal) | existing fail-loud `ArgumentError` guards extended (1-thread guard); no external input |
| V6 Cryptography | no | N/A (note: `_stable_hex64` is a filename disambiguator, not a security hash — unchanged) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Data race corrupting solver state | Tampering | one model per task (JuMP rule); serial-join writes; no `threadid()` indexing |
| Silent result substitution (threaded ≠ serial reported as equal) | Repudiation | bitwise `==` assertions, not tolerances; spike verdict recorded before enabling |
| Reproducibility breakage (canary flip unnoticed) | Tampering | canary test in every per-commit sample; golden policy forbids re-pinning |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `direct_model(Clarabel…)` errors at construction (factory.jl note, 2026-07-18) | Constructs; fails at first variable addition (`AddVariableNotAllowed`) | between JuMP versions (verified live 2026-10-23 on JuMP 1.30.1) | Same conclusion (Clarabel unusable direct), different failure point — spike records the current error; consider updating the factory comment |
| Clarabel.jl `max_threads` setting only (0.10) | `MOI.NumberOfThreads` MOI-standard attribute | Clarabel.jl 0.11.0 (2025-05, PR #196) | The blessed JuMP-idiomatic pinning is available on the pinned 0.11.1 |
| `BLAS.set_num_threads` per-task folklore | Set once per parallel region (global LBT state) | standing Julia guidance | Avoids a self-inflicted race the "per task" wording could invite |
| Manual thread pools / `Threads.threadid()` indexing | `Threads.@spawn` dynamic task scheduling (1.10+ default/interactive pools) | Julia 1.10 LTS | `@spawn` is the locked, current idiom |

**Deprecated/outdated:**
- `Threads.@threads` with threadid-indexed buffers: unsafe with dynamic scheduling (task can migrate threads) — JuMP docs "Danger" note.
- Per-task BLAS pinning: global state; set once.

## Sources

### Primary (HIGH confidence)
- **This session's live probes** (this repo, pinned toolchain, 2026-10-23): Clarabel bitwise determinism under `Threads.@spawn` at `-t 4` (6 seeds, serial vs concurrent, BLAS 2/1); exception semantics (`TaskFailedException`/`CompositeException`/fetch-order/`throw(obj)` round-trip); `direct_model(Clarabel…)` current failure mode; `MOI.NumberOfThreads`/`max_threads` acceptance; environment (`julia -t`, BLAS config)
- Codebase (direct reads): `src/admm/solve_admm.jl`, `src/admm/admm_phases.jl`, `src/admm/admm_state.jl`, `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl` (greps), `src/admm/residuals.jl` (struct fields), `src/core/errors.jl`, `src/core/status.jl` (greps), `src/experiments/store.jl`, `src/experiments/run.jl`, `src/experiments/Scenario.jl` (`==`/`hash`), `src/solver/factory.jl`, `test/test_admm_knifeedge_canary.jl`, `test/runtests.jl`, TestItemRunner 1.1.5 source (sequential execution), `results/ieee8500_benchmark/{memory_wall_recharacterization,point_resources}.csv`, `scripts/benchmark_ieee8500.jl`, `docs/literate/ieee8500_scaling.jl`, `.planning/spikes/CONVENTIONS.md`, `Project.toml`, `CLAUDE.md`
- [JuMP Parallelism tutorial](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism/) — models not thread-safe; one model per task; `MOI.NumberOfThreads() => 1`; `Core.Box` closure hazard
- [Julia manual: Multi-threading](https://docs.julialang.org/en/v1/manual/multi-threading/) — Dict/collection locking; `@spawn` schedule nondeterminism; data-race-freedom responsibility
- [Clarabel solver settings](https://oxfordcontrol.github.io/ClarabelDocs/stable/api_settings/) — `max_threads`, `direct_solve_method`; [ClarabelDocs linsolvers](https://github.com/oxfordcontrol/ClarabelDocs/blob/main/docs/src/user_guide_linsolvers.md) — "QDLDL is a single threaded solver"
- [Clarabel.jl CHANGELOG](https://github.com/oxfordcontrol/Clarabel.jl/blob/main/CHANGELOG.md) — 0.11.0: MOI.NumberOfThreads support (#196), LDL :auto default, Julia min 1.10

### Secondary (MEDIUM confidence)
- [Clarabel.rs issue #59](https://github.com/oxfordcontrol/Clarabel.rs/issues/59) (maintainer goulart-paul): fresh solves identical to machine precision; warm start not automatic — corroborates per-instance determinism
- [Julia Discourse: HiGHS independent parallel solves](https://discourse.julialang.org/t/error-with-highs-independent-parallel-solves/96048) — general pattern: solver-internal threads must be pinned to 1 under Julia-threaded concurrent solves (HiGHS-specific; Clarabel QDLDL has none)

### Tertiary (LOW confidence)
- A4 (CI threading configuration) — not verified this session; check `.github/workflows` at planning/execution time.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; everything pinned and locally verified
- Architecture (executor split, error recipe, provenance seam): HIGH — grounded in direct code reads plus live-verified task/exception semantics
- Determinism claim (PAR-02 feasibility): HIGH on toy QPs (empirical), MEDIUM for the real fixture (A1 — the spike exists precisely to close this)
- SCALE-06 numbers: HIGH — read from the committed Phase-35 CSVs; the attribution itself is the phase's measured deliverable, not a research claim
- Pitfalls: HIGH — each anchored to verified mechanism (sequential runner source, `Scenario ==` source, mutable-struct `==`, global BLAS state, HWM semantics)

**Research date:** 2026-10-23
**Valid until:** 2026-11-22 (30 days — pinned toolchain; spike probes should be re-run if Clarabel/JuMP/Julia versions move)
