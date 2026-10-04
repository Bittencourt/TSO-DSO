# Phase 35: IEEE-8500 Scale After Refactor - Context

**Gathered:** 2026-10-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Close ARCH-10 (carry-over SCALE-STRETCH / v3.0 SCALE-05): (1) the ADMM final consolidation's
`assert_socp_exact!` behaves correctly at IEEE-8500 scale — no spurious throw on a converged point —
fixed in the LIBRARY, not only in the benchmark script; (2) at least one converged, memory-feasible
headline IEEE-8500 point is measured after the v4.0 architecture changes, or the memory wall is
re-characterized honestly with fresh measurements.

Out of scope: formulation changes, per-hour DSO model restructuring, loosening `assert_solved!`,
new solvers as headline.

</domain>

<decisions>
## Implementation Decisions

### Exactness gate at scale (SC1)
- `solve_admm`'s `atol_exact` default becomes `nothing` → the hybrid floor
  `max(TAU_SOLVER_FIX08=2e-7, MEASURED_ε_FIX08=1e-9·ref_b)` applies on the ADMM consolidation path,
  matching the centralized path. An explicit value still overrides (bypass semantics unchanged).
  Thread `nothing` through `_admm_certify` → `solve_dso!` (its default 1e-6 likewise). Every ADMM
  golden and the knife-edge canary (iters = 56, welfare = -4823.66604824162) must be bit-identical —
  NEVER re-pin.
- Near-zero-impedance branches (worst `L2916620->N1136366`, r_pu 2.4e-6): NOT excluded from the gate.
  Report the per-branch residual diagnostic; accept only if the hybrid floor clears them honestly.
- Proof: a fast regression test on a small proxy (e.g. IEEE-123 + an injected near-zero-r branch, or
  any small fixture whose converged consolidation has gap > 1e-6 but < hybrid floor) that THROWS under
  the old flat 1e-6 and PASSES under the new default; plus one real IEEE-8500 run recorded in the
  benchmark CSV.
- Negative test: a genuinely inexact point still raises `CertificateError`.

### Headline measurement protocol (SC2)
- Target ladder: headline `ieee8500` density 0.1, T=10 first (known to fit, ADMM converged in 8 iters
  in v3.0) — re-measure post-refactor; then step to T=24 and density 0.25 one step at a time.
- One point per process, wrapped in `/usr/bin/time -v` (peak RSS) plus `Sys.maxrss`; OOM kills
  captured from `journalctl -k` into the CSV automatically; run on a quiet machine (15 GiB RAM,
  4 cores — note other-process memory load in the record).
- Centralized ALMOST_OPTIMAL at T=10: recorded honestly as a conditioning wall; the ADMM point is the
  headline; centralized reference reported as "not certifiable". `assert_solved!` NOT loosened.
- Stop rule: one attempt per step; if T=24 still OOMs, write a memory-wall re-characterization table
  (points tried, peak RSS, death point, delta vs Phase 25, dominant consumer from profiling) — this
  satisfies the "or re-characterize" branch.

### Memory-reduction scope & reporting
- Only low-risk, bit-identical memory wins that profiling shows dominant (drop centralized model before
  ADMM, `GC.gc()` between stages, free consolidation model). No formulation changes; goldens + canary
  unchanged.
- Clarabel remains the headline solver; SCS one scouting run only if Clarabel OOMs, labelled scouting,
  never used for price claims.
- Results: update `results/ieee8500_benchmark/*.csv`, add a short measured-results section to the
  existing IEEE-8500 docs page, update the Phase-25 SCALE-05 status note.
- Harness (`scripts/benchmark_ieee8500.jl`): incremental per-point CSV writes, one point per process,
  typed exception names (`CertificateError`/`ConvergenceError`) handled, drop the script-side
  `EXACTNESS_ATOL` override once the library default is right (keep a CLI override flag).

### Claude's Discretion
- Choice of proxy fixture for the fast regression test; exact profiling method; the wrapper script
  shape for per-process runs.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/benchmark_ieee8500.jl` (980 lines): `IEEE8500_*_EXACT_ATOL` :138-145,
  `run_centralized_point` :479, `run_admm_point` :554 (atol_exact :567, Sys.maxrss :537-581),
  `T_HORIZON_FLOOR=10` :681, `run_sweep_mode` :693, `run_gap_report_mode` :873.
- `results/ieee8500_benchmark/density_sweep{,_full}.csv` — v3.0 baseline rows.
- Per-branch cone-residual diagnostic from quick task 260822-oi7.

### Established Patterns
- Exactness: `src/models/exactness.jl` — `MEASURED_ε_FIX08`, `TAU_SOLVER_FIX08` (~:75-84),
  `assert_socp_exact!` :170; docstring :136-142 states explicit `atol` bypasses the hybrid floor.
- Measured, not picked, tolerances (memory `highs-exactness-defaults`, `exactness-gate-hybrid-floor`).
- Typed errors from Phase 34: `CertificateError`, `ConvergenceError`, `SolveFailedError`.

### Integration Points
- `src/admm/solve_admm.jl:245` (defaults `atol_exact=1e-6, rtol_exact=1e-4` :264-265; `_admm_certify`
  call :343) → `src/admm/admm_phases.jl:260` `_admm_certify` (`solve_dso!` ~:285-294) →
  `src/admm/DsoOpt.jl:551` `solve_dso!` (default atol 1e-6 :558) → `assert_socp_exact!` :663.
- Build-once ADMM structure predates Phase 34 (one DSO model across hours + one AgrOpt per aggregator);
  `direct_model` barred for Clarabel (`src/solver/factory.jl:15-18`).

</code_context>

<specifics>
## Specific Ideas

- v3.0 evidence: headline OOM-killed at density 0.1 (×2) and 1.0, anon-rss 6.8–9.75 GiB on a shared
  15 GiB box with ~9 GiB swap used by others (`deferred-items.md:173-181`, `25-VERIFICATION.md:35`);
  T=10 density 0.1 fit at ~5.9 GB peak.
- The v3.0 SCALE-05 gap was accepted as an honest non-measurement — keep the same honesty standard.

</specifics>

<deferred>
## Deferred Ideas

- Deeper memory restructuring (per-hour DSO models, model rebuild strategy) — future milestone if the
  wall persists.
- Gate exclusion of near-zero-impedance branches (v3.0 Item 2) — not adopted.

</deferred>
