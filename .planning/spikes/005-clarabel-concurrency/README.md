---
spike: 005
name: clarabel-concurrency
type: standard
validates: "Given the production multi-aggregator ADMM fixture (IEEE-13, 10 aggregators, seed 7, T=24, ConvexBranchFlow, LIVE) solved under the production configuration (julia -t 4, BLAS.set_num_threads(1), MOI.NumberOfThreads()=1), when each aggregator's iteration-1 AGR-OPT solve is executed inside a Threads.@spawn task and compared BITWISE to the serial solve, then the threaded results are bitwise-equal to serial (PASS) and the PAR-02 gate for enabling the Phase-39 threaded ADMM executor has its artifact"
verdict: PASS
related: [39-01]
tags: [admm, clarabel, concurrency, determinism, threading, bitwise, par-02, gate]
---

# Spike 005: Clarabel Concurrency & Determinism (PAR-02 gate)

## What This Validates

**Given** the production multi-aggregator ADMM fixture — IEEE-13, seed 7, T=24,
`ConvexBranchFlow()`, LIVE reactive consensus (the production smart default: the population
carries a flexible-load member) — built by the **production factory** `TSODSO._admm_build`,
**when** every aggregator's iteration-1 AGR-OPT solve (coefficient −λ_j − ρ·c_j on `pag` +
`optimize!` of that aggregator's own JuMP model — exactly the `_react_agr_solve!` mid-loop
step, minus the `st` writes) is executed inside a `Threads.@spawn` task under
`julia -t 4` with the production solver-thread pinning, **then** the threaded solutions are
**bitwise-equal** to the serial ones, the comparator is proven live by controls on every
run, and the `direct_model` question is settled as a classified outcome.

This is the **PAR-02 gate artifact**: per the locked decision (D-06), the Phase-39 threaded
ADMM executor is enabled **only** if this spike records a PASS on a real multi-aggregator
fixture under the production configuration.

## Method

`.planning/spikes/005-clarabel-concurrency/sweep.jl`, one fresh `AdmmState` per leg:

1. **`serial_ref`** — solve all 10 aggregators sequentially (per-j: `value.(agr.pag)`,
   `objective_value`, `utility`, `MOI.BarrierIterations()`).
2. **`serial_recheck`** — identical re-run on a **freshly built state** — the POSITIVE
   control: must reproduce leg 1 **bitwise** on every aggregator.
3. **`threaded`** — fresh state; `BLAS.set_num_threads(1)` once (process-global LBT state —
   per-task calls would themselves race); `set_attribute(model, MOI.NumberOfThreads(), 1)`
   on **every** AGR model (belt-and-braces; QDLDL is single-threaded anyway); one
   `Threads.@spawn` task per aggregator doing its own coeff-set + `optimize!`, **fetched in
   `load_nodes` order** with the `TaskFailedException` unwrap the locked executor design
   prescribes. Tasks touch only their own `AgrOpt.model`; NO `st` writes inside any task.
4. **`direct_model`** — attempt `JuMP.direct_model(Clarabel.Optimizer())` + a first
   `@variable`; catch and record the exception type as a classified outcome row (failure
   classes are data).

**Comparator — BITWISE, never `isapprox`:** Float64 vectors via `reinterpret(UInt8, ·)` byte
equality, scalars via `isequal`, plus an FNV-1a sha-style byte digest per (leg, aggregator)
over (pag bytes, objective bits, utility bits, barrier-iteration bits) so any mismatch is
attributable. All rows land in `sweep.csv`.

**Controls (non-negotiable, checked on every run):**

- POSITIVE: `serial_recheck` ≡ `serial_ref` bitwise on all 10 aggregators — **PASS**.
- CROSS-STATE (free third check): an unperturbed solve on a fourth fresh state also
  reproduces `serial_ref` bitwise — **PASS**.
- NEGATIVE: perturb ONE aggregator's coupling price `λ_j[1]` and require the byte-compare vs
  `serial_ref` to **FAIL**. The plan's flat 1-ulp (`+eps()`) perturbation was **absorbed**
  by the solver (bit-identical output), so the control escalates ulp-by-ulp — the
  perturbation became visible at `eps()*2^1` and the compare **FAILED AS DESIGNED**
  (comparator proven live; the ulp count is recorded as a `negative_control` row in
  `sweep.csv`). Either control misbehaving errors the script loudly.

## Production Configuration

| Knob | Value |
|------|-------|
| Julia | 1.12.5, `julia -t 4` (`Threads.nthreads() = 4`) |
| BLAS | `BLAS.set_num_threads(1)` (host default was 2) |
| Solver threads | `MOI.NumberOfThreads() => 1` on every AGR model (accepted by Clarabel 0.11.1) |
| Clarabel.jl | 0.11.1 (pinned) |
| JuMP | 1.30.1 (pinned) |
| Construction | indirect `Model(select_optimizer(QP()))` via the factory (CachingOptimizer) |
| Reactive consensus | LIVE (production `_default_reactive_consensus` for this population) |
| ADMM knobs | ρ = ρ_q = 100.0 (`ADMM()` defaults); iteration-1 AGR-OPT solve-only grain |

## Results

Three consecutive runs (fresh `julia -t 4` processes), all identical:

- **`threaded` vs `serial_ref`: BITWISE-EQUAL on every aggregator** — `pag`, `objective_value`,
  `utility` and `BarrierIterations()` all byte-equal (per-leg digests in `sweep.csv`,
  `verdict,ALL,threaded_vs_serial,BITWISE-EQUAL` row).
- POSITIVE control: **PASS** every run. CROSS-STATE control: **PASS** every run.
- NEGATIVE control: **FAILED AS DESIGNED** every run (comparator detects a 2-ulp coupling-price
  perturbation; 1 ulp is solver-absorbed — recorded as data).
- This confirms the research session's toy-QP probe on the REAL fixture: the three source
  facts all held — (a) bitwise serial-vs-threaded equality under the production
  configuration, (b) `AddVariableNotAllowed` as the `direct_model` failure, (c)
  `MOI.NumberOfThreads() => 1` accepted by Clarabel 0.11.1.

## The `direct_model` Answer

`direct_model(Clarabel.Optimizer())` **constructs without error** on JuMP 1.30.1 but **fails
at the first variable addition** with `MathOptInterface.AddVariableNotAllowed`
("Adding variables cannot be performed…"). Recorded as a classified outcome row in
`sweep.csv`, not a crash.

⇒ Clarabel remains **copy_to-only**: the ADMM build-once / `set_objective_coefficient`
re-solve loop **cannot** run on a direct model. This refines (does not contradict) the
2026-07-18 note in `src/solver/factory.jl`, which recorded the older failure mode ("errors
at construction") — the modern failure mode is at first variable addition. The factory note
itself is intentionally NOT edited here (spikes observe without mutating `src/`).

## Consequence

**PASS — the Phase-39 threaded ADMM executor is enabled** per the locked decision: threaded
execution is only enabled on a documented pass of this spike on a real multi-aggregator
fixture with the production configuration. The plan 39-02/39-04 serial-vs-threaded equality
tests remain the end-to-end arbiter (this spike measures the solve-only per-aggregator grain
at iteration 1; the executor adds the shared serial consensus/reduction region on top).
The knife-edge canary (`iters = 56`, welfare −4823.66604824162) is untouched — this spike
runs in its own process and never re-pins anything.

## How to Run

```bash
julia -t 4 --project=. .planning/spikes/005-clarabel-concurrency/sweep.jl
```

Re-runnable; rewrites `sweep.csv` each run; errors loudly if any control misbehaves.
Observe-only — `git status --porcelain src/` is empty after a run.
