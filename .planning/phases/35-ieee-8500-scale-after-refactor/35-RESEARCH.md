# Phase 35: IEEE-8500 Scale After Refactor - Research

**Researched:** 2026-10-04
**Domain:** Julia/JuMP/Clarabel SOCP exactness gate plumbing (ADMM final consolidation) + memory characterization of the IEEE-8500 benchmark harness
**Confidence:** MEDIUM-HIGH (plumbing and small-fixture behaviour MEASURED; the IEEE-8500 gate verdict is INFERRED from committed v3.0 data, not re-measured, because the full benchmark was out of scope for research)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Exactness gate at scale (SC1)
- `solve_admm`'s `atol_exact` default becomes `nothing` -> the hybrid floor
  `max(TAU_SOLVER_FIX08=2e-7, MEASURED_ε_FIX08=1e-9·ref_b)` applies on the ADMM consolidation path,
  matching the centralized path. An explicit value still overrides (bypass semantics unchanged).
  Thread `nothing` through `_admm_certify` -> `solve_dso!` (its default 1e-6 likewise). Every ADMM
  golden and the knife-edge canary (iters = 56, welfare = -4823.66604824162) must be bit-identical —
  NEVER re-pin.
- Near-zero-impedance branches (worst `L2916620->N1136366`, r_pu 2.4e-6): NOT excluded from the gate.
  Report the per-branch residual diagnostic; accept only if the hybrid floor clears them honestly.
- Proof: a fast regression test on a small proxy (e.g. IEEE-123 + an injected near-zero-r branch, or
  any small fixture whose converged consolidation has gap > 1e-6 but < hybrid floor) that THROWS under
  the old flat 1e-6 and PASSES under the new default; plus one real IEEE-8500 run recorded in the
  benchmark CSV.
- Negative test: a genuinely inexact point still raises `CertificateError`.

#### Headline measurement protocol (SC2)
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

#### Memory-reduction scope & reporting
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

### Deferred Ideas (OUT OF SCOPE)
- Deeper memory restructuring (per-hour DSO models, model rebuild strategy) — future milestone if the
  wall persists.
- Gate exclusion of near-zero-impedance branches (v3.0 Item 2) — not adopted.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARCH-10 | IEEE-8500 performance and memory work (carry-over SCALE-STRETCH): the final consolidation's `assert_socp_exact!` behaves correctly at scale, and at least one converged, memory-feasible headline point is measured, or the wall is re-characterized after the architecture changes. | Findings 1-3 below: exact plumbing change (3 signatures), measured no-regression evidence on existing goldens, the CRITICAL finding that the hybrid default is TIGHTER than 1e-6 and will not clear IEEE-8500's near-zero-r branch, memory-stage profiling plan, per-process wrapper, doc/status-note locations. |
</phase_requirements>

## Summary

The library change is tiny and mechanically safe: three signatures (`solve_admm` at `src/admm/solve_admm.jl:264`, `solve_dso!` at `src/admm/DsoOpt.jl:558`, and the pass-through in `_admm_certify` `src/admm/admm_phases.jl:260-293`) change `atol_exact::Real = 1e-6` to `atol_exact::Union{Nothing,Real} = nothing`. `assert_socp_exact!` already accepts `atol::Union{Nothing,Real} = nothing`, so `nothing` flows straight into the hybrid floor. `atol` only influences the pass/throw decision; `maxgap` (the returned/reported `exact_maxgap`) is `max |l·v − (P²+Q²)|`, independent of `atol`, and no solve is affected, so goldens are bit-identical by construction. MEASURED: with the patch applied in a scratch worktree, the full ADMM-related test set (953 assertions, includes the knife-edge canary, IEEE-13, IEEE-123, meshed, reactive, 4Q, timeout, adaptive, dual-residual, phases) passed with 0 failures and 0 canary movement.

Two findings change how the phase should be planned. (1) **The hybrid floor is TIGHTER than the old flat 1e-6 almost everywhere** (it is `max(2e-7, 1e-9·ref_b)`; it only exceeds 1e-6 on a thermally-limited branch with `smax > 31.6 pu`, i.e. `ref_b = smax² > 1e3`, and `SMAX_NO_LIMIT = 99` so at most ~9.8e-6). So the CONTEXT proof recipe ("gap > 1e-6 but < hybrid floor, THROWS under old, PASSES under new") describes a narrow window that no natural converged fixture sits in; the regression proof must be an assert-level synthetic with a limited high-`smax` branch, plus plumbing tests. (2) **The hybrid default will almost certainly NOT clear IEEE-8500's converged consolidation.** The committed gap report (post bus-merge, `socp_gap_report.csv`) shows the worst branch `L2916620->N1136366` (r_pu 2.4e-6) with `P≈-2e-8, Q≈-1e-8, l≈1.7e-3, v≈1.06` so `gap ≈ 1.8e-3` while the cone magnitude `l·v` is also ≈1.8e-3: the per-branch bound is `2e-7 + 1e-4·1.8e-3 ≈ 3.8e-7`, i.e. ratio ≈ 4,800 under hybrid (the CSV's recorded 1,541 used the flat 1e-6). The v3.0 ADMM consolidation gap at density 0.1 / T=10 was 1.3968e-4 (pre bus-merge) — also ≫ 2e-7. The loss cost of that slack is `r_pu·gap ≈ 2.4e-6 · 1.8e-3 ≈ 4e-9` pu, below Clarabel's `tol_gap 1e-6..1e-8`: the slack is solver-indistinguishable, which is why it is not driven to zero. Changing the default to `nothing` is still the right library change (consistency with the centralized path, decided by the user), but SC1 ("no spurious throw on a converged point") will most likely NOT be satisfied by it alone. The plan must contain an early measurement task and a decision checkpoint (see Open Questions 1).

**Primary recommendation:** Do the 3-signature change + tests first (cheap, proven no-regression), then run ONE diagnostic IEEE-8500 T=10, density 0.1 ADMM point with `atol_exact = Inf` (explicit bypass, never throws) and compute the per-branch hybrid ratio from `res.dso_ctx`; if max ratio > 1, STOP and escalate the gate-semantics decision to the user instead of improvising a new tolerance.

## Architectural Responsibility Map

Single-process Julia library/research bench; tiers are modules, not web tiers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Exactness certificate (`assert_socp_exact!`, hybrid floor) | `src/models/exactness.jl` (model layer) | — | Fixture-agnostic gate; stays untouched except possibly an additive diagnostic |
| ADMM consolidation plumbing of `atol_exact` | `src/admm/` (`solve_admm` -> `_admm_certify` -> `solve_dso!`) | — | Library, not script: CONTEXT requires the fix in the LIBRARY |
| Per-point benchmark orchestration, CSV, OOM capture | `scripts/benchmark_ieee8500.jl` + new shell wrapper | `results/ieee8500_benchmark/` | Harness-only concerns (RSS, process isolation) |
| Docs measured-results section | `docs/literate/ieee8500_scaling.jl` -> `docs/src/generated/ieee8500_scaling.md` (tracked) | — | Literate page is the single doc source |

## Standard Stack

No new packages. Everything is already pinned (JuMP 1.30.1, Clarabel 0.11.1, SCS optional ext, CSV/DataFrames in the main env for the script). `/usr/bin/time` (GNU time) exists and reports "Maximum resident set size (kbytes)" [VERIFIED: ran `/usr/bin/time -v true`]. `journalctl -k` is readable by the user [VERIFIED: ran it]. `dmesg` is NOT permitted (Operation not permitted), so use `journalctl -k`.

### Package Legitimacy Audit
No external packages are added by this phase; audit not applicable. Packages removed/flagged: none.

## Architecture Patterns

### Data flow of the exactness gate (as built)

```
solve_admm(...; atol_exact, rtol_exact)                      src/admm/solve_admm.jl:245
   mid-loop: solve_dso!(...; check_exact=false)              admm_phases.jl:172   (gate never runs)
   converged -> _admm_certify(st,...,atol_exact,rtol_exact)  admm_phases.jl:260   (positional pass-through, :266/:293)
        -> solve_dso!(dso,λ,a,ρf; check_exact=true, strict=false, atol_exact, rtol_exact)   DsoOpt.jl:551
             -> solve_with_retry!(...) ; RESET-01 ladder reset before final solve
             -> assert_socp_exact!(ctx; rtol=rtol_exact, atol=atol_exact)                   DsoOpt.jl:663
                    atol===nothing -> atol_b = max(τ_solver, ε*ref_b)  per branch/hour
                    atol::Real      -> flat atol_b (bypass; byte-identical to pre-FIX-08)
             -> ctx.meta[:socp_maxgap] = maxgap   (independent of atol)
        exact_maxgap = dres_final.exact_maxgap  -> returned NamedTuple
```

### Pattern 1: the exact edit (verified by applying it in a scratch worktree)
```julia
# src/admm/solve_admm.jl:264 and src/admm/DsoOpt.jl:558
atol_exact::Union{Nothing, Real} = nothing,
```
Also update: the docstrings at `solve_admm.jl:177` (`atol_exact::Real = 1e-6`), `DsoOpt.jl:498-540` (the prose describing the 1e-6 default / "copied verbatim from assert_socp_exact!'s own current defaults"), and the `_admm_certify` argument is untyped so it needs no change. `JuliaFormatter` 2.10.x writes `Union{Nothing, Real}` (with a space) per the repo's pinned config: match the existing `time_limit_s::Union{Nothing, Real}` spelling (the solve_admm.jl:263 line) or the format check will fail [VERIFIED: existing code uses the spaced form].

### Pattern 2: harness drops its override
`scripts/benchmark_ieee8500.jl:138-145` `IEEE8500_*_EXACT_ATOL`/`EXACTNESS_ATOL`, `run_admm_point(..., atol_exact::Real)` (:554) and the call site :775. Make `run_admm_point` accept `Union{Nothing,Real}` and pass `nothing` unless `--admm-atol <float>` is given (new CLI override flag). The centralized verdict column (`exact_verdict = gap <= atol`, :504) still uses `EXACTNESS_ATOL`; keep it but relabel, since it is a CSV-comparability column, not a gate. `admm_atol_used` CSV column: write the string `"hybrid"` (or NaN) for `nothing` — CSV upsert uses `cols=:union`, so schema evolution is safe (quick task 260822-hld fix).

### Anti-Patterns to Avoid
- **Raising `TAU_SOLVER_FIX08`/`MEASURED_ε_FIX08` to make IEEE-8500 pass.** Memory `exactness-gate-hybrid-floor`: never raise τ or ε to hide it. Values 1e-3 vs 2e-7 are five orders apart; this would be certificate laundering (T-25-12).
- **Re-pinning any ADMM golden or the canary.** The patch cannot move them; if one moves, the change is wrong.
- **Fixed-dispatch SOCP re-solve as an "exact" cross-check** (structurally inexact; use `ACPowerFlow(limits=false)`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-branch gate diagnostic | A new residual loop | `socp_gap_report` (`src/models/exactness.jl:361`, additive, already exported) — but it takes a FLAT `atol` (default 1e-6) so its `ratio` column is the FLAT ratio, not hybrid | Reuse; if hybrid ratios are needed, add an additive `atol=nothing` mode or compute in the script (see probe in Code Examples) |
| Peak RSS | A sampling thread | `/usr/bin/time -v` "Maximum resident set size" plus `Sys.maxrss()` | Kernel-accurate high-water mark; `Sys.maxrss` is monotonic whole-process (documented harness caveat) |
| OOM detection | Parsing exit codes alone | `journalctl -k` AND `journalctl -u earlyoom` since the start timestamp | See Pitfall 3 |

## Runtime State Inventory

Not a rename/refactor/migration phase. Omitted. (Committed CSV rows in `results/ieee8500_benchmark/` are data, appended/upserted, never rewritten.)

## Finding 1: Default-change safety (bit-identical goldens)

**What `atol` influences:** only `assert_socp_exact!`'s `maxratio > 1` -> throw decision [VERIFIED: `src/models/exactness.jl:170-` reads; `maxgap` is `max gap` independent of `atol`]. `exact_maxgap` in the `solve_admm` result and `dso.ctx.meta[:socp_maxgap]` are therefore identical for any `atol`. The solve itself runs BEFORE the gate (`solve_with_retry!` then gate), so no numeric output depends on it.

**Hybrid vs flat 1e-6 per branch:** `atol_b = max(2e-7, 1e-9·ref_b)`; `ref_b = smax²` for limited branches (`smax < 99`), else head-branch `P²+Q²`. Hybrid < 1e-6 whenever `ref_b < 1e3`. [VERIFIED by measurement] fixtures: `ieee13_modified`: smax in [0.0686, 99] with 9/10 branches unlimited; `ieee123_modified`: [3.8, 99], 121/122 unlimited; `ieee8500_modified`: [55, 99], 4864/4865 unlimited (head smax = 55 pu, `ref_b = 3025`, `atol_b(head) = 3.0e-6`, all others `2e-7` unless head flow² > 1e3). So the new default is TIGHTER than 1e-6 on every unlimited branch; a pass->throw flip is possible only for a converged ADMM point whose cone gap lies in (2e-7, 1e-6] (plus the shared `rtol·max(lhs,rhs)` slack, identical in both).

**Measured margins on existing ADMM fixtures** (probe testitem in scratch worktree; ratio = max_b gap/(atol_b + 1e-4·max(lhs,rhs))):

| Fixture | ADMM iters | `exact_maxgap` | hybrid ratio | flat-1e-6 ratio |
|---------|-----------|----------------|--------------|-----------------|
| Phase6 2-bus | 2 | 8.39e-9 | 0.041 | 0.0083 |
| IEEE-13 ground (Phase4 aggs, ρ=100) | 103 | 4.87e-10 | 0.0024 | 0.00049 |

Hybrid margin >= 24x on both. [VERIFIED: measured 2026-10-04] The 2-bus fixture has the tightest margin (24x).

**Full-suite evidence:** with the 3-signature patch applied in a scratch worktree (`git worktree` at HEAD, JULIA_LOAD_PATH stacked recipe), the ADMM-related selection (`:admm` tag, names containing "admm"/"ieee123"; 953 assertions, 1 pre-existing `@test_broken`, 7m57s) passed with 0 failures [VERIFIED: measured]. That set contains `test_admm_knifeedge_canary.jl` (iters=56 / welfare=-4823.66604824162 pinned, untouched), `test_ieee123_admm.jl`, `test_admm.jl`, `_adaptive`, `_dualresid`, `_generic_pf`, `_meshed`, `_reactive`, `_timeout`, `_phases`. A second pass over the strategy/experiment/MPC/acceptance/thesis/exactness files is recorded under Validation Architecture (PASS2 RESULT).

**Every test that asserts ADMM exactness (all `< 1e-3`-style bounds on the reported `exact_maxgap`, none depends on `atol`):** `test_admm.jl:154,199,379`; `test_admm_adaptive.jl:107`; `test_admm_generic_pf.jl:94-101`; `test_admm_meshed.jl:55`; `test_admm_timeout.jl:85,109`; `test_ieee123_admm.jl:89,240`; `test_acceptance.jl:92,169`; `test_experiments.jl:41,53,159,199`; `test_scenario_pf.jl:127-161`; `test_strategies.jl:206-255`.
**Every test asserting a `CertificateError`:** NONE goes through the ADMM consolidation path today. `test_tsodso_errors.jl:87-123` (assert_socp_exact! direct, kind `:socp_exact`), `test_planning_inexact_policy.jl`, `test_fourquadbess.jl`, `test_admm_generic_pf.jl:191` (`solve_agr!`, battery), `test_mesh_angle_certificate.jl`. So the negative ADMM-path test is NEW work.
**Every caller passing `atol_exact` to the ADMM path:** only `scripts/benchmark_ieee8500.jl:554-567` (+ call site :775). `test/fixtures_phase19.jl:264,293,359` pass `atol_exact` to its OWN test-only centralized replica (`centralized_welfare_4q`, `assert_socp_exact!(ctx; atol=1e-5)`), not to ADMM — unaffected. `src/experiments/run.jl:124` (`run(ADMM, Scenario)`) and `docs/literate/admm.jl`, `meshed_reactive_price.jl`, `scripts/pv_boom_case_study.jl`, `reactive_flake_rate.jl`, `demo_flexibility_plots.jl` call `solve_admm` with the default and therefore pick up the new hybrid floor; the doc-build pages (admm.jl, meshed_reactive_price.jl) should be re-run in the docs env as a final check (see Validation).

**Behavioral change to document:** because the new default is tighter, a user-visible `CertificateError` can newly appear for ADMM consolidation points with gap in (2e-7, 1e-6]. This is intended (consistent with the centralized gate) but belongs in the docs/changelog.

## Finding 2: Proxy fixtures for the regression test

**The CONTEXT recipe cannot be satisfied by a natural ADMM point.** "gap in (1e-6, hybrid floor)" requires `atol_b > 1e-6`, i.e. a limited branch with `31.6 < smax < 99` pu. No existing fixture has a limited branch in that range except IEEE-8500's head (smax 55) where the gap is ~0. An IEEE-123 + "injected near-zero-r branch" does the OPPOSITE: it creates gap ≫ hybrid (exactly the IEEE-8500 failure), so it is a good NEGATIVE/diagnostic, not a pass-under-new proxy.

Recommended tests (all fast, use the `Branch(...)`/`Feeder` + fixed-variable pattern of `test/test_exactness.jl:92-183`, no ADMM solve needed for items A/B):

- **A (the "throws under old flat / passes under new default" proof, assert level):** 2-bus `Feeder` with `Branch(1,2,0.01,0.02, 90.0)` (limited: `ref_b = 8100`, `atol_b = 8.1e-6`), fix `v=v̂=1`, `P=Q=0`, `l = 5e-6` (gap 5e-6, `rtol` term 5e-10). `assert_socp_exact!(ctx; atol = 1e-6)` THROWS (old flat default); `assert_socp_exact!(ctx)` (hybrid = new `solve_admm` default) returns maxgap = 5e-6. This is the honest, deterministic realization of the CONTEXT proof; document that it exercises the gate function the ADMM default now forwards to. [ASSUMED: numbers computed from the documented formula, not run; trivial to confirm in Wave 0]
- **B (plumbing proof on the real ADMM path):** with the Phase6 2-bus fixture (`test/fixtures_phase6.jl`, `ρ=RHO_2BUS`), call `solve_admm(...)` default -> returns normally with `exact_maxgap ≈ 8.4e-9` (measured); then `solve_admm(...; atol_exact = 1e-30, rtol_exact = 0.0)` raises `CertificateError(kind=:socp_exact)` (explicit-bypass semantics preserved, proves the kwarg is live). Also assert `solve_admm(...; atol_exact = nothing)` is bit-equal to the default (`iters`, `welfare`, `exact_maxgap` all `==`).
- **C (default ≠ flat 1e-6 on the ADMM path, discriminating):** needs a DSO point with gap in (2e-7, 1e-6]. Not reachable via `solve_admm` without loosening the DSO Clarabel tolerance, and RESET-01 restores `ctx.meta[:ladder_baseline]` before the final solve (so `set_optimizer_attribute` after build is undone). Do NOT chase this; A+B cover it. If wanted: build the DSO with `build_dso_opt`, overwrite the tolerance entries in `dso.ctx.meta[:ladder_baseline]` too, call `solve_dso!(...; check_exact=true)` default vs `atol_exact=1e-6`. [ASSUMED mechanism from reading DsoOpt.jl:100-145, not run]
- **Negative (genuinely inexact still raises):** (i) `test_exactness.jl` already covers the gate function (smax=10, l=5e-6 THROWS ratio ~25, and smax=0.01 case). Add the ADMM-level one: B's explicit tiny-atol throw proves the `CertificateError` type propagates from `solve_admm`; additionally an IEEE-123-style or synthetic near-zero-r negative can be done at assert level (`Branch(1,2,2.4e-6,5.6e-6,SMAX_NO_LIMIT)`, `P=Q≈0`, `l=1.7e-3`, `v=1.06`) which must THROW under the default (ratio ~4,800) — this one test pins the exact IEEE-8500 failure mode and documents why Phase 35 does not simply claim SC1.

`@testitem` caveat (memory `testitem-try-scoping-trap`): wrap any `try`/`catch` capturing an exception in a function or `let`; do not reassign outer variables inside `try`/`for` at item top level. Use `@test_throws CertificateError` or a helper function `caught(f)`.

## Finding 3: Memory profile approach for IEEE-8500

**What is known (committed data):** headline fixture 4866 buses / 4865 branches (post bus-merge), 1177 load buses; density 0.1 -> 122 aggregators. Centralized MV-only T=10 model: 137,144 vars; T=24: 330,066 vars (~371k at density 0.25). v3.0 ADMM-only `admm_peak_rss_delta_mb`: 3,050-3,280 MB at headline density 0.1 / T=10 (converged in 8 iters, 227 s); kills at T=24 happened with anon-rss 6.8-9.75 GiB. IMPORTANT structural fact: in the v3.0 harness (`run_sweep_mode` :774-775) the centralized point ran FIRST in the same process, then ADMM, so (a) the OOM rows' RSS includes centralized, and (b) `Sys.maxrss` deltas for ADMM are measured above an already-high heap; glibc rarely returns freed arenas to the OS so RSS stays at the centralized peak. The T=24 headline kills are not attributable to ADMM, and "ADMM-only at T=24" has never been measured.

**Likely dominant consumers [ASSUMED, to be confirmed by the profiling task]:**
1. Clarabel KKT matrix + QDLDL factor for the whole-horizon SOCP (the DSO model is ONE model over all T hours; size scales ~linearly in T, factor fill-in with network/time coupling). Clarabel is `copy_to`-only (`src/solver/factory.jl:15-18`), so JuMP's CachingOptimizer keeps BOTH the MOI-level problem copy and Clarabel's internal copy. `direct_model` is barred.
2. JuMP/MOI model with string names: no `set_string_names_on_creation(model,false)` anywhere in `src/` (grep: 0 matches). Names for ~137k-370k variables and 2x constraints are pure overhead. Candidate bit-identical win IF no code or test reads names (check `name(`/`variable_by_name` in src/test before adopting).
3. Retained centralized model in the harness process (fixable by process isolation or `--admm-only`).
4. 122 per-aggregator `AgrOpt` models (small each; verify their sum by measurement).

**Profiling method (cheap, no full benchmark):** a script `scripts/profile_ieee8500_memory.jl` (run under `/usr/bin/time -v`, one stage-set per process) printing, at each stage, `VmRSS`/`VmHWM` from `/proc/self/status` and `Base.gc_live_bytes()`: (0) after `using`; (1) after `build_feeder`+`density_filtered_population`; (2) after `build_dso_opt` (model built, no solve); (3) after first `optimize!` of the DSO (Clarabel copy + factor); (4) after `GC.gc()` and again after `ccall(:malloc_trim, Cint, (Cint,), 0)`; (5) after building the AgrOpts. Stage 1-2 are safe on this machine (the T=10 MV model is ~137k vars); run stage 3 at T=10 only. Differences identify the dominant consumer for the re-characterization table. [A fixture-size/model-build-only measurement was NOT run in this research session: another multi-GiB test run was concurrently using the machine; deferred to the plan's first measurement task.]

**Bit-identical mitigations (ordered by expected value, each must be proven by golden/canary unchanged):**
1. `--admm-only` (or `--skip-centralized`) harness flag: ADMM point in its own process without the centralized model ever existing. Zero library risk. Probably the largest real win vs v3.0.
2. `r = nothing; GC.gc(); ccall(:malloc_trim, ...)` between stages in the harness; do not retain `res.dso_ctx` (the `solve_admm` result holds the live DSO model via `dso_ctx`).
3. `set_string_names_on_creation(model, false)` in `build_dso_opt`/AgrOpt (and welfare models) — touches library code on the golden path; names do not enter the numeric problem, but verify via full ADMM test set + canary; adopt only if profiling shows names are a measurable fraction.
4. Not recommended (changes numerics/structure): per-hour DSO models (deferred), bridges removal, lower precision.

**Per-point process wrapper (`scripts/run_ieee8500_point.sh`):**
```bash
#!/usr/bin/env bash
# usage: run_ieee8500_point.sh <outfile.json> -- <benchmark args...>
START="$(date '+%Y-%m-%d %H:%M:%S')"
free -m > "$OUT.free_before"                      # record other-process memory load
/usr/bin/time -v -o "$OUT.time" julia --project=. scripts/benchmark_ieee8500.jl "$@"
RC=$?
PEAK_KB=$(awk -F': ' '/Maximum resident set size/{print $2}' "$OUT.time")
KERN=$(journalctl -k --since "$START" --no-pager 2>/dev/null | grep -iE "out of memory|oom-kill|Killed process" || true)
EARLY=$(journalctl -u earlyoom --since "$START" --no-pager 2>/dev/null | grep -iE "sending|killing|SIGTERM|SIGKILL" || true)
# classify: RC=137 (SIGKILL) or KERN non-empty -> OOM_KILLED(kernel); RC=143 or EARLY non-empty -> OOM_KILLED(earlyoom)
```
Append a row (`peak_rss_kb`, `rc`, `oom_source`, `mem_avail_before_mb`, `swap_used_before_mb`) to the CSV from the wrapper itself, since the harness cannot observe its own SIGKILL (v3.0 constructed such rows manually). The Julia side should write its row incrementally (write a "started" row first, overwrite on completion) so a kill leaves a trace.

## Common Pitfalls

### Pitfall 1: The hybrid floor will not clear IEEE-8500 (SC1 may be unreachable by the default change)
**What goes wrong:** Phase 35 plans assume `nothing` fixes the spurious throw; it makes the gate STRICTER (2e-7 vs 1e-6). The converged IEEE-8500 consolidation has per-branch gap ~1e-3 on near-zero-r branches (`l` free because `r·l` loss cost 4e-9 is below solver tolerance), so ratio >> 1 and the default throws harder than the old flat 1e-6 did.
**Why:** formulation property of near-ideal branches; CONTEXT explicitly forbids excluding them and forbids raising τ/ε.
**How to avoid:** run the diagnostic point (Finding 3 order) BEFORE writing the docs claim; if hybrid ratio > 1, the honest outcomes are (a) report that the gate correctly refuses IEEE-8500 consolidation and re-read SC1 with the user, or (b) get an explicit user decision on a principled cost-weighted per-branch floor (e.g. accept residual when `r_pu·gap ≤ τ_cost`, a measured, documented, additive criterion) — which is a gate-semantics change, not in CONTEXT, so it is an OPEN QUESTION, not an implementation task.
**Warning signs:** `CertificateError` message naming `L2916620->N1136366`/`M…` branches; `exact_maxgap` ~1e-4..1e-3.

### Pitfall 2: Centralized-first harness ordering contaminates RSS
`run_sweep_mode` runs `run_centralized_point` then `run_admm_point` in one process; `Sys.maxrss` is a monotone high-water mark so the ADMM delta can read ~0 or be inflated. Use one point per process, ADMM-only for the headline, and report `/usr/bin/time -v` Maximum RSS as the authority.

### Pitfall 3: earlyoom, not the kernel, usually kills first on this machine
`/usr/bin/earlyoom -r 300 -m 12,6 -s 12,6` is running [VERIFIED: ps, `journalctl -u earlyoom` shows 5-minute status lines]: it sends SIGTERM when BOTH available memory < 12% and free swap < 12%, SIGKILL at 6%/6%. Swap is zram (6 GiB, prio 100) + a 4 GiB file. A kill therefore leaves exit code 143/137 and entries in `journalctl -u earlyoom`, NOT necessarily in `journalctl -k`. The CONTEXT's "OOM kills captured from `journalctl -k`" must be extended to `journalctl -u earlyoom`. Also note zram makes "swap used" look benign while RSS is high; record `free -m` before each run.

### Pitfall 4: `@testitem`/runner traps (memory)
Use direct `Test.jl` scripts or `JULIA_LOAD_PATH="<abs>/test:<abs>:@stdlib"` with ABSOLUTE paths (relative `test:.:@stdlib` failed to resolve TSODSO in the scratch worktree [VERIFIED]); never `@run_package_tests` via `julia -e`. Plans' `<verify>` blocks must not call TestItemRunner under `--project=.`.

### Pitfall 5: JuliaFormatter
Repo is pinned to JuliaFormatter 2.10.x with a content-loss guard; use `Union{Nothing, Real}` (spaced) to match existing lines or the CI format check fails.

### Pitfall 6: stale docs build
`docs/src/generated/ieee8500_scaling.md` is tracked in git, generated from `docs/literate/ieee8500_scaling.jl`. Editing only the literate source leaves the tracked `.md` stale; regenerate with the docs env (`JULIA_LOAD_PATH="<abs>/docs:<abs>:@stdlib"`, memory note) or edit consistently. The literate page reads `density_sweep_full.csv` at build time; new Phase-35 rows live in `density_sweep.csv`, so the new section needs its own (Base-only) CSV read or literal figures.

### Pitfall 7: `ALMOST_OPTIMAL` centralized reference
`assert_solved!` is strict by design; the T=10 centralized point at density 0.1 returned `ALMOST_OPTIMAL` in v3.0 and was refused. Record as "not certifiable" per CONTEXT; do not add `allow_almost`.

## Code Examples

### Hybrid per-branch ratio from a converged `ctx` (diagnostic; used for the 8500 decision and in the measured probe)
```julia
# Source: derived from src/models/exactness.jl hybrid definition (measured on 2-bus/IEEE-13 this session)
function hybrid_ratios(ctx; rtol = 1e-4)
    pv = ctx.pf_vars; f = ctx.feeder; T = ctx.T
    head = findfirst(br -> br.from == f.root || br.to == f.root, f.branches)
    out = NamedTuple[]
    for (b, br) in enumerate(f.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
        ref = br.smax < TSODSO.SMAX_NO_LIMIT ? br.smax^2 :
              value(pv.P[head, t])^2 + value(pv.Q[head, t])^2
        atol_b = max(TSODSO.TAU_SOLVER_FIX08, TSODSO.MEASURED_ε_FIX08 * ref)
        gap = abs(lhs - rhs)
        push!(out, (; b, t, gap, atol_b, ratio = gap / (atol_b + rtol * max(abs(lhs), abs(rhs)))))
    end
    return sort!(out; by = r -> -r.ratio)      # worst first
end
# Run an IEEE-8500 diagnostic WITHOUT throwing: explicit bypass with Inf, then inspect:
#   r = solve_admm(feeder, ConvexBranchFlow(), aggs; ..., atol_exact = Inf)
#   first(hybrid_ratios(r.dso_ctx), 20)
```
(If promoted to the library, put it next to `socp_gap_report` as an additive function; do not alter `assert_socp_exact!`.)

### Test A skeleton (assert-level, mirrors test_exactness.jl)
```julia
@testitem "admm default exactness floor: hybrid accepts what flat 1e-6 refuses (ARCH-10)" tags = [:exact, :admm] begin
    using TSODSO, JuMP
    using TSODSO: Bus, Branch, Feeder
    feeder = Feeder([Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
                    [Branch(1, 2, 0.01, 0.02, 90.0)], 1)   # ref_b = 8100 -> atol_b = 8.1e-6
    T, N, B = 1, 2, 1
    model = Model(select_optimizer(SOCP()))
    @variable(model, v[1:N, 1:T]); @variable(model, v̂[1:N, 1:T])
    @variable(model, P[1:B, 1:T]); @variable(model, Q[1:B, 1:T]); @variable(model, l[1:B, 1:T])
    fix.(v, 1.0; force = true); fix.(v̂, 1.0; force = true)
    fix.(P, 0.0; force = true); fix.(Q, 0.0; force = true); fix.(l, 5.0e-6; force = true)
    @objective(model, Max, 0); optimize!(model)
    ctx = TSODSO.ModelContext(model); ctx.feeder = feeder; ctx.T = T; ctx.pf_vars = (; v, v̂, P, Q, l)
    @test_throws CertificateError TSODSO.assert_socp_exact!(ctx; atol = 1e-6)   # old flat default
    @test TSODSO.assert_socp_exact!(ctx) ≈ 5.0e-6                                # new default (nothing)
end
```

## State of the Art

| Old | Current | When | Impact |
|-----|---------|------|--------|
| flat `atol=1e-6` in ADMM consolidation | hybrid `max(2e-7, 1e-9·ref_b)` (Phase 35 default) | v4.0 P27 (centralized), Phase 35 (ADMM) | tighter gate; IEEE-8500 near-zero-r branches cannot pass |
| script-side `EXACTNESS_ATOL` (1.1e-3/5e-3 measured floors) via `atol_exact` bypass | library default + optional `--admm-atol` CLI override | Phase 35 | the 1e-3 floors were never a certificate of exactness (T-25-12), only an override |
| centralized+ADMM in one process | one point per process, ADMM-only for headline | Phase 35 | RSS attributable |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | IEEE-8500 converged ADMM consolidation gap is >> 2e-7 (inferred from v3.0 ADMM 1.4e-4 pre-merge and centralized post-merge 1.8e-3; NOT re-measured post-refactor) | Summary / Pitfall 1 | If the post-merge ADMM consolidation gap is actually <~2e-7, SC1 is met by the default change alone (good outcome) |
| A2 | Test A numbers (`atol_b = 8.1e-6`, throws at flat 1e-6, passes hybrid) computed from the documented formula, not run | Finding 2 | Adjust `smax`/`l` in Wave 0 |
| A3 | Dominant memory consumer is Clarabel KKT/factor + MOI/Clarabel double copy + names | Finding 3 | Different mitigation ranking; the profiling task decides |
| A4 | `set_string_names_on_creation(false)` is bit-identical and unread by code/tests | Finding 3 | Test failures if any code reads names; revert |
| A5 | ADMM-only T=24 headline may fit (never measured in isolation) | Finding 3 | Re-characterization table branch instead |
| A6 | Mechanism C (overwriting `ladder_baseline`) works | Finding 2 | Skip C; A+B suffice |

## Open Questions (RESOLVED)

1. **If the diagnostic shows hybrid ratio > 1 at IEEE-8500, what does SC1 mean?**
   - Known: near-zero-r branch `L2916620->N1136366` has gap ~1.8e-3 = its whole cone magnitude, loss cost ~4e-9 pu; CONTEXT forbids excluding such branches and forbids raising τ/ε.
   - Unclear: whether the user accepts "the gate correctly refuses, documented as the new honest wall" (SC1 reinterpreted) versus ratifying a new principled cost-weighted floor (gate-semantics change).
   - Recommendation: plan a `checkpoint:decision` immediately after the diagnostic run. Default to option (a) (honest report, no gate change) unless the user ratifies (b).
   - **RESOLVED (user, 2026-10-04):** option (a) HONEST REFUSAL — no gate-semantics change; recorded in 35-CONTEXT.md Research Refinements. No checkpoint needed.
2. **Which point is "one real IEEE-8500 run recorded in the benchmark CSV" if the gate throws?** Recommend recording the converged ADMM point as `admm_status = ERROR:CertificateError` plus the diagnostic (hybrid ratio, worst branch) via the `atol_exact=Inf` run, labelled clearly, rather than a passing row.
   - **RESOLVED:** adopted in plans 35-02/35-03 (ERROR:CertificateError row + bypass diagnostic row).
3. **Do the v3.0 T=10 results (ADMM 8 iters, 227 s, 3.2 GB) still reproduce post-Phase-34 refactor and bus-merge (fixture is now 4866 buses; v3.0 numbers were on 4875/4872)?** Unknown; the first measurement task answers it.
   - **RESOLVED:** plan 35-03 measures it (T=10 ADMM-only re-measurement vs v3.0).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all | yes | 1.12.5 | — |
| `/usr/bin/time` (GNU) | peak RSS | yes | `-v` works | `Sys.maxrss` only |
| `journalctl -k` / `-u earlyoom` | OOM capture | yes (user-readable) | — | none needed |
| `dmesg` | — | NO (permission) | — | use journalctl |
| earlyoom | affects OOM semantics | running (`-m 12,6 -s 12,6`) | — | document |
| RAM / swap | headline runs | 15.5 GiB RAM, 6 GiB zram + 4 GiB swapfile | ~8 GiB available at research time with another job running | run on quiet machine |
| SCS ext | scouting only | optional weakdep | — | skip |
| `git worktree` + absolute-path `JULIA_LOAD_PATH` | scratch/regression | yes | — | — |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` + TestItems/TestItemRunner 1.1.5 (`@testitem`); mixed deps need the stacked load path |
| Config file | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| Quick run command | assert-level and plumbing items via a runner file: `cd <repo> && JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -t2 <runner.jl> $PWD` where runner.jl does `using TestItemRunner; TestItemRunner.run_tests(joinpath(ARGS[1],"test"); filter = ti -> :exact in ti.tags)` (runner must be a real file, never `julia -e`; ABSOLUTE paths) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~12-20 min; background; known-false Aqua failures per memory `local-project-toml-drift`) |
| Harness golden | `julia --project=. test/test_benchmark_ieee8500.jl` (10 D-16 goldens, plain script) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ARCH-10 / SC1 | default `atol_exact=nothing` hybrid accepts gap in (1e-6, 8.1e-6) on smax=90 branch, flat 1e-6 refuses | unit (assert-level) | runner filter `:exact` | Wave 0 (new item in `test/test_exactness.jl` or new `test/test_admm_exactness_default.jl`) |
| ARCH-10 / SC1 | `solve_admm` default == `atol_exact=nothing` bit-equal; explicit tiny atol raises `CertificateError(kind=:socp_exact)` | integration (2-bus, ~secs) | runner filter on item name | Wave 0 |
| ARCH-10 / SC1 | near-zero-r synthetic (r_pu 2.4e-6, l=1.7e-3) THROWS under default (pins the 8500 failure mode) | unit | runner filter `:exact` | Wave 0 |
| ARCH-10 / SC1 | all ADMM goldens + canary (iters=56, welfare=-4823.66604824162) unchanged | regression | runner filter `:admm` (7m57s, 953 assertions measured) | exists |
| ARCH-10 / SC2 | harness: `--admm-only`, `--admm-atol` flag parsing, row schema (hybrid label), typed exception names | unit/script | `julia --project=. test/test_benchmark_ieee8500.jl` | exists (extend) |
| ARCH-10 / SC2 | one real IEEE-8500 point recorded in `results/ieee8500_benchmark/density_sweep.csv` | manual/measurement (not CI) | `scripts/run_ieee8500_point.sh` | Wave 0 (new script) |
| ARCH-10 / docs | literate page + status notes updated; docs build | docs build | docs env literate run | exists |

### Sampling Rate
- **Per task commit:** the new `:exact`/default-floor items (< 1 min) + `test/test_benchmark_ieee8500.jl` when the script changes.
- **Per wave merge:** runner filter `:admm` (~8 min) + canary file explicitly.
- **Phase gate:** full `Pkg.test()` green except the 2 known Aqua items (memory `local-project-toml-drift`), plus the PASS2 set (strategies/experiments/MPC/acceptance/thesis_repro/exactness). Never run two suites concurrently in the same tree; do not run a suite while an IEEE-8500 measurement is running (memory `background-suite-orphan-race`; agent worktrees under `.claude/worktrees` contaminate main-tree runs).
- **Never** run the 8500 benchmark under test-time CI; headline points are manual, one per process, on a quiet machine.

### Wave 0 Gaps
- [ ] New default-floor test items (A, B, near-zero-r negative) — covers ARCH-10 SC1.
- [ ] `scripts/run_ieee8500_point.sh` wrapper and `scripts/profile_ieee8500_memory.jl` — covers SC2/profiling.
- [ ] Harness flags (`--admm-only`, `--admm-atol`) + golden extension.
- [ ] PASS2 result below to be re-run after the actual edit (it was run on a scratch-worktree edit).

**PASS2 RESULT (test_experiments, _strategies, _acceptance, _scenario_pf, _status_policy, _planning_hardening, _abstract_feeder, _agr, _tsodso_errors, _mpc_loop, _thesis_repro, _exactness with the patch applied):** 1175 passed, 1 broken (pre-existing), 0 failed, 6m17s [VERIFIED: measured].

## Security Domain

No new network/auth/crypto surface; local research code. ASVS V5 (input validation) applies only to the new CLI flag parsing (`--admm-atol`: parse as Float64, reject non-finite except the explicit documented `Inf` diagnostic or disallow it from the CLI) and to shell wrapper argument quoting (quote `"$@"`, no `eval`). No secrets handled. T-25-12 (anti-certificate-laundering) is the relevant integrity control: any tolerance used must be library-default or an explicitly labelled override recorded in the CSV.

## Where docs and status notes live (item 4)

- IEEE-8500 docs page source: `docs/literate/ieee8500_scaling.jl` (282 lines; sections: "Two walls, not one" l.12, "Live section" l.37, "Precomputed section" l.104, "The headline point, stated plainly" l.178 (currently states OOM_KILLED at density 1.0/0.1), "Synthesis" l.210, "Reproducing this" l.271). Wired in `docs/make.jl` lines 38-43 and nav line 90 ("Scaling to IEEE-8500" => `generated/ieee8500_scaling.md`). Rendered copy `docs/src/generated/ieee8500_scaling.md` IS tracked in git. Add a short "Post-refactor measured results (Phase 35)" section after the headline section, and amend the sentence at l.178-200 that says the headline never converged.
- Phase-25 SCALE-05 status note: `.planning/milestones/v3.0-phases/25-ieee-8500-scalability-benchmark/25-VERIFICATION.md` frontmatter gap (line ~19, `status: failed`, "Solve time, ADMM iteration count, and SOCP exactness are measured on the committed headline fixture...") and the table row at line 125 (`SCALE-05 ... BLOCKED (partial)`); `deferred-items.md` items 3 and 4 (the "STILL OPEN" caveat at ~l.165-190). Add a dated "superseded by Phase 35" note appended (the repo convention is append-only with dated sub-entries, as in 260822-pxb/rle; do not edit the original status). Also `.planning/STATE.md:102` (`verification_gap` row, explicitly "deliberately left as-is" — append the resolution, keep the history), `.planning/PROJECT.md:302-317` (SCALE-STRETCH candidate bullet), `.planning/REQUIREMENTS.md:124` (ARCH-10 checkbox) and line 199 traceability row.
- Results CSVs: `results/ieee8500_benchmark/density_sweep.csv` (current-method rows; has `admm_atol_used`, `admm_peak_rss_delta_mb`), `density_sweep_full.csv` (v3.0 OOM rows, keep), `noise_floor_calibration.csv`, `socp_gap_report.csv`. Add peak-RSS/OOM-source columns via `cols=:union` upsert.

## Sources

### Primary (HIGH confidence)
- Repo source read directly: `src/models/exactness.jl:60-215`, `src/admm/{solve_admm,admm_phases,DsoOpt,admm_state}.jl`, `scripts/benchmark_ieee8500.jl`, `src/solver/factory.jl`.
- Measured this session: fixture smax/r statistics; 953-assertion ADMM test subset with the patch applied (0 failures); 2-bus and IEEE-13 ADMM consolidation gaps and hybrid ratios; `/usr/bin/time -v`, `journalctl -k`, earlyoom presence.
- Committed measurement history: `.planning/quick/260822-{f0b,hld,oi7,pxb,rle}-*/…-SUMMARY.md`, `results/ieee8500_benchmark/*.csv`, `.planning/milestones/v3.0-phases/25-ieee-8500-scalability-benchmark/{deferred-items.md,25-VERIFICATION.md}`.
- Project memory notes: `exactness-gate-hybrid-floor`, `gsd-plan-verify-testitemrunner-trap`, `testitem-try-scoping-trap`, `background-suite-orphan-race`, `local-project-toml-drift`.

### Secondary / Tertiary
- None (no web sources needed; no external library behavior was asserted beyond what the repo already documents).

## Metadata

**Confidence breakdown:**
- Standard stack / plumbing change: HIGH — applied and tested in a scratch worktree.
- No-regression on goldens: HIGH for the ADMM subset (953/0); pass2 recorded below.
- IEEE-8500 gate verdict: MEDIUM — inferred from committed data (A1); the diagnostic run resolves it.
- Memory attribution: LOW-MEDIUM — hypotheses (A3), to be profiled.

**Research date:** 2026-10-04
**Valid until:** 2026-11-03 (stable codebase; invalidated by any change to `exactness.jl` constants)

## Research-session measurement log

(Scratch worktree `…/scratchpad/wt` at HEAD 2e3af4d with the 3-signature patch; main checkout untouched; worktree to be removed after the session.)
- ADMM subset: 953 passed, 1 broken, 0 failed, 7m56.6s.
- PASS2: 1175 passed, 1 broken, 0 failed, 6m17s.
- Combined: 2128 assertions across ADMM + strategy/experiment/MPC/acceptance/thesis/exactness files, 0 failures, no golden or canary movement.
