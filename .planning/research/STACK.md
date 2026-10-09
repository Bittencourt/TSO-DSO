# Technology Stack — v5.0 Aggregator Layer at Scale (ADDITIONS ONLY)

**Project:** TSODSO (Julia/JuMP research framework)
**Milestone:** v5.0 Aggregator Layer at Scale
**Researched:** 2026-10-09
**Scope:** Only what is NEW for v5.0. The v1–v4 stack (JuMP, Clarabel, HiGHS, Ipopt, solver factory, DrWatson, CairoMakie ext, TestItemRunner, JET, Aqua, JuliaFormatter, Julia 1.10 floor) is validated and not re-researched.

## Bottom line

v5.0 needs **one new runtime dependency (OhMyThreads.jl)**, zero new solver dependencies, and a small offline-data toolchain that stays **out of the package `[deps]`**. Most of the milestone (profit-max aggregator, settlement, equity metrics, EV / heat pump / Volt-VAR devices, DSO flex market) is modeling work on top of JuMP + Clarabel + HiGHS, plus ~100 lines of hand-written code per item. Adding packages for those would cost more (reproducibility, version drift, Julia 1.10 compat) than it saves.

The real technical risks are **memory at 8500 scale** and **thread-safety / determinism of parallel solves**. They are engineering and measurement problems, not package-selection problems.

Host fact that drives every recommendation: dev machine is **4 cores / 15 GB RAM with earlyoom** (`nproc`=4, `free`=15 GiB). Prior measurement: IEEE-8500 d=0.1 T=24 ADMM-only peaked at 11.52 GiB, and d=0.25 was OOM-killed at ~10.4 GiB. Threading buys at most ~3-4x wall-clock and does **not** reduce memory, and it can multiply peak memory.

## Recommended additions

### Parallelism (new runtime dependency)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **OhMyThreads.jl** | **0.8.7** (registry 2026-10; compat `julia = "1.10.0 - 1"`, ChunkSplitters 3.x, ScopedValues, StableTasks, BangBang) | Structured task-parallel `tforeach`/`tmap!`/`tmapreduce`, explicit schedulers, `TaskLocalValue` for per-task workspaces | Base `Threads.@threads` is fine for the loop itself, but the hard part is **per-task model/workspace ownership**. The old `threadid()`-indexed buffer idiom is unsafe with task migration and interactive threads (1.12). OhMyThreads gives `TaskLocalValue` + `DynamicScheduler(nchunks=…)` / `StaticScheduler`, structured concurrency (errors propagate and tasks are joined), and `tmap!` writing into preallocated index-addressed arrays. That index-addressed write pattern is what makes the parallel path **bit-identical to serial**, which this repo's goldens/canary (`iters = 56`, `welfare = -4823.66604824162`) require. Compat floor matches our Julia 1.10 LTS. |

Stdlib only (no install): `Base.Threads`, `LinearAlgebra.BLAS.set_num_threads`, `Profile`, `Profile.Allocs`, `Statistics`, `Random`.

### Decision: multithreading, not Distributed (HIGH confidence on the choice, MEDIUM on solver thread-safety, see below)

| | Threads (recommended) | Distributed / pmap |
|---|---|---|
| Memory | One copy of feeder data/models. | One Julia process + full model copy per worker. On a 15 GB host with an 11.5 GB single-process peak this is fatal. |
| Model transfer | None; models are built once, mutated via `Parameter`s, and stay resident per task. | JuMP models and Clarabel solver state are not serializable. Each worker rebuilds, losing the build-once/re-solve design. |
| Fit to ADMM | Per-iteration `tforeach` over independent subproblems; very low latency. | Per-iteration RPC of λ/μ/ρ and results; latency comparable to a tiny QP solve. |
| Source | JuMP docs say JuMP *models* are not thread-safe, so use one model per task, never share one model across threads ([JuMP parallelism tutorial](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism/)). | Same doc supports `pmap` for fully independent solves (sweeps). |

Use Distributed **only** for embarrassingly parallel scenario sweeps via `scripts/sweep.jl`-style drivers, if at all. DrWatson `@produce_or_load` over separate OS processes is already the cheaper way to get that. No `Distributed` import in `src/`.

### Integration rules for the parallel ADMM (design constraints, not packages)

1. **Two different parallel axes with opposite memory profiles.**
   - AGR-OPT (per node / per aggregator, tiny QPs): parallelize freely over aggregators. This is where 784 houses and multi-node portfolios will pay off. Per-task state is small.
   - DSO-OPT (per hour, one large SOCP over the whole network): parallelizing over T hours multiplies concurrent Clarabel KKT factorizations. At IEEE-8500 this is the memory wall. **Cap DSO-hour concurrency separately** (`ntasks_dso`, default 1 until measured; likely ≤2 on this host). Do not use one global thread count for both.
2. **One JuMP model + one optimizer per task, built once, owned via `TaskLocalValue` (or pre-built vector indexed by chunk, not by `threadid()`).** Never share a `Model` across tasks. Never build inside the loop. Build in serial, solve in parallel (JuMP guidance).
3. **Solver threads = 1 inside the parallel region.** Clarabel default `max_threads = 0` (automatic) and its default `:qdldl` is single-threaded pure Julia; keep it explicit (`MOI.NumberOfThreads` → 1 in the factory when `parallel=true`) so enabling `:faer` later cannot oversubscribe. Set `BLAS.set_num_threads(1)` for the duration of parallel regions.
4. **Deterministic reduction.** Each task writes its result into its own slot (`out[i] = …`) and the reduction runs serially in index order afterwards. Never accumulate with `atomic_add!`/locks in float, because summation order changes the last bits and moves goldens. Add a test: serial vs `-t 4` residual traces identical (`==`, not `≈`).
5. **Serial path stays the default and stays byte-identical.** `nthreads()==1` or `parallel=false` must run the existing code path, not a 1-chunk threaded path. Test the threaded path with an explicit `-t 2` job (new CI matrix leg / `julia_args=["-t2"]`); default test runs stay serial.
6. **Do not thread Ipopt** (MUMPS/global state, not safe to assume). Do not thread the AC oracle. HiGHS: set `threads=1` per instance and keep HiGHS use in parallel regions out of v5.0 unless measured (HiGHS has a process-global task scheduler; behavior with concurrent instances not verified here, LOW).
7. **Clarabel thread-safety is not documented either way** (neither the Clarabel docs nor README state it; I found nothing authoritative). Clarabel.jl is pure Julia with QDLDL.jl and no known global mutable solver state, so independent `Optimizer` instances per task are very likely safe (MEDIUM-LOW). **First task of the scale phase: a 2-hour spike** that solves N copies concurrently under `-t 4` and checks bitwise equality against serial. Gate the rest of the parallel work on it.

### Memory profiling / reduction for IEEE-8500 (no new dependency)

The existing `scripts/profile_ieee8500_memory.jl` staged profiler plus stdlib is sufficient. Add these techniques, ordered by expected payoff:

| Technique | Source | Why / expected effect |
|-----------|--------|-----------------------|
| `JuMP.set_string_names_on_creation(model, false)` for every large model | JuMP API | Variable/constraint name strings are a significant share of JuMP-side memory at 10^5-10^6 rows. Zero deps; names only matter for debug builds. Keep a debug flag. |
| `direct_model(Clarabel.Optimizer())` or `Model(optimizer; add_bridges=false)` for the hot DSO per-hour models | JuMP/MOI | Avoids the MOI caching copy (problem data held twice: JuMP-side cache and solver-side). The earlier `direct_model` note in CLAUDE.md applies here as a memory measure, not just speed. Re-check which `ModelContext` accessors need cached model (duals via `dual()` work on direct models). |
| Hold per-hour solver state only for **active** hours | Design | ~3.4 GiB of T=10 loop growth was unattributed and is hypothesized to be per-hour DSO solver state, linear in T. Options: keep T Clarabel instances alive (current, fastest) vs a small pool of ≤k reusable instances re-pointed via `Parameter`/RHS updates per hour. The pool approach caps memory at k×(one state) and **also** gives the DSO-hour concurrency cap in rule 1. This is the highest-leverage change, but requires the hypothesis to be verified first. |
| `Profile.Allocs` + `Base.gc_live_bytes()` / `Sys.maxrss()` at staged checkpoints | stdlib | Attributes the unattributed 3.4 GiB (live vs garbage vs solver-internal). `maxrss` is what earlyoom acts on, so report VmRSS too. |
| `GC.gc(true)` between stages plus `--heap-size-hint=10G` for headline runs | Julia runtime | Prevents the GC from deferring collection into the OOM zone; set in `run_ieee8500_point.sh`. |
| Clarabel `direct_solve_method = :faer` | [Clarabel settings](https://clarabel.org/stable/api_settings/) | Multithreaded supernodal LDL; options are `:qdldl` (default), `:mkl`, `:panua`, `:ma57`, `:cholmod`, `:faer`. Candidate for per-hour solve time, **but** unverified in the Julia package's current version for memory behavior, and non-default KKT backends change duals at the 1e-9 level (golden risk). Treat as an opt-in experiment, measure before adopting; `:mkl`/`:panua` are not open-source-friendly. LOW-MEDIUM. |
| `PProf.jl` / `ProfileView` | optional | Flamegraphs only if needed. Dev-environment only, never in `[deps]`. |

**Planning implication:** the "measured IEEE-8500 headline run" is a measurement deliverable that may end honestly as "memory-infeasible on this host"; budget a go/no-go checkpoint after the profiling phase. A remote/bigger-RAM machine is outside the repo's scope but is the realistic alternative. Do not promise convergence to a headline point in the roadmap.

### Realistic population / device data (offline toolchain, not runtime deps)

Principle: runtime `[deps]` stays lean (CSV, DataFrames, StableRNGs already there). External datasets are converted **once, offline**, into small vendored, license-stamped CSV fixtures under `data/` (like the IEEE-123 reduction), with a provenance README. Tests and docs never download.

| Need | Recommendation | Notes |
|------|----------------|-------|
| 784-house thesis Case A population | Generate from the existing seeded `StableRNGs` machinery; do not add a package | The shortfall was the 1-house-per-bus proxy, not a missing library. Needs a population builder (house to bus map, per-house device parameters), pure model code. Thesis App. E parameters remain IP-blocked, so state calibration provenance explicitly. |
| EV arrival/departure/energy | Hand-written seeded sampler (truncated-normal arrival/departure, lognormal energy need) fitted offline to a public dataset; ship fitted parameters as a small CSV/`const` table | Candidate public sources: [ACN-Data](https://ev.caltech.edu/) (Caltech/JPL sessions, API token required, check license before vendoring parameters), [NREL TEMPO/dsgrid charging profiles](https://opennetzero.org/national-renewable-energy-laboratory-nrel/demand-side-grid-dsgrid-tempo-light-duty-vehicle-charging-profiles-v2022), [open high-resolution uni/bidirectional/dynamic EV charging dataset](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12246261/) (relevant to V2G). Raw sessions never enter the repo. |
| Heat-pump outdoor-temperature-dependent COP & building parameters | Hand-written COP(T_out) curve (linear or quadratic fit) plus 1R1C/2R2C thermal parameters as `const` | [When2Heat](https://data.open-power-system-data.org/when2heat/) (hourly heat demand + COP, 16 European countries, 2008-2018) is a citable reference to calibrate against. Climate is European, whereas the thesis is Argentine/San Juan, so document the mismatch rather than hide it. COP depends only on exogenous outdoor temp, so it is a **known per-hour constant** and the model stays LP/QP/convex. |
| Household base-load shapes | Reuse the existing profile generation; optionally vendor a tiny normalized shape CSV from a public dataset | `Parquet2.jl` 0.2.37 / `Arrow.jl` 2.8.1 only if converting NREL ResStock/EULP parquet; **keep them in a separate `scripts/data_prep/Project.toml`**, not in the package. |

### Settlement, equity, flexibility market (no new dependency)

| Need | Recommendation | Why not a package |
|------|----------------|-------------------|
| Per-actor settlement (FIT/TOU/DADP/flat/nodal) | Pure functions over the existing result structs + DataFrames tables | Accounting identities are the research content. Must reconcile with the existing DLMP 4-way decomposition (settlement sums == welfare identities are a mandatory test). |
| Gini, Theil-T/L, Atkinson(ε), Palma, quantile ratios, per-node/household distributions | Hand-roll ~60 lines in `src/` with known-value tests (e.g. Gini of `[0,0,0,1]` = 0.75, perfect-equality = 0, Atkinson(ε=0) = 1 − geo-mean/mean) | The registry's only inequality package is `Inequality.jl` at **v0.0.4** (single stale release, pulls DataFrames+Documenter+StatsBase as runtime deps), so it is not a safe dependency. Negative or zero-valued surplus (common here: bills can be negative) breaks naive Gini/Atkinson. Handling that explicitly (shift/clip convention, documented) is research-relevant and should be owned in-repo. |
| Bootstrap CIs / quantiles on equity metrics | `Statistics` stdlib (`quantile`, `mean`) + `StableRNGs` | `StatsBase` 0.34.13 only if weighted quantiles are really needed. |
| DSO flexibility market vs price coordination | Plain JuMP LP/QP with Clarabel/HiGHS (merit-order / bid-clearing with network constraints) | No market-simulation package exists in the ecosystem that matches the Branch Flow seam. |
| Profit-maximizing aggregator (price-taking, fixed retail tariff) | Same JuMP QP/LP; new objective plugged into AGR-OPT | Convex, so ADMM/duals unchanged. If the aggregator also **chooses** the customer tariff, that is bilevel: use the existing hand-rolled KKT/SOS1 path (`solve_bilevel!`) with **BilevelJuMP 0.6.3 (already a test dep) as oracle only**. Note HiGHS must be configured exact (memory: `mip_rel_gap`, `mip_feasibility_tolerance` defaults silently undercut "exact" claims). |

### Device models (no new dependency; modeling constraints to carry into the roadmap)

- **EV / V2G:** battery-with-availability-window (`p_ch,p_dch` bounded to 0 outside [arrival, departure], required SOC at departure, optional V2G via `p_dch`). Binaries are banned in the device library, so charge/discharge simultaneity is **not enforced**; expect the same η<1 overlap artifact already found for BESS (App. C). Do not add binaries: HiGHS would then be required for the operational layer and duals (DADP) would be lost. Document it as a relaxation with a post-solve overlap diagnostic, and a small cycling/degradation cost to discourage artifacts.
- **Heat pump + RC thermal model:** discretized 1R1C (optionally 2R2C) linear dynamics, electric power = thermal power / COP(T_out,t) (constants per hour), comfort band as hard-with-slack box. Min-on/min-off and compressor ramp need binaries, so use a continuous relaxation (ramp limits as linear constraints). Closest existing device is thermostatic; extend it rather than duplicating.
- **Smart-inverter Volt-VAR:** a droop curve `Q(V)` inside a convex branch-flow model is not convex as an equality. The two defensible options are (a) reactive power as an **optimized variable** inside the existing apparent-power cone (already shipped for 4Q-BESS) = "ideal inverter control", an upper bound on droop benefit; (b) fixed-point iteration over a given piecewise-linear curve with the existing AC oracle (`ACPowerFlow`) as certificate. Recommend (a) first and (b) as the "realistic" comparator. No package; piecewise-linear lookup is ~15 lines.

## What NOT to add

| Avoid | Why | Instead |
|-------|-----|---------|
| `Distributed.jl` / `pmap` in `src/` | Duplicates memory per worker on a 15 GB host; JuMP/Clarabel state is not transferable; destroys build-once/re-solve. | OhMyThreads in-process; processes only for DrWatson sweeps. |
| `MPI.jl`, `ClusterManagers` | Wrong scale and complexity for a PhD bench. | n/a |
| `FLoops.jl`, `ThreadsX.jl`, `Folds.jl`, `Transducers.jl` | Superseded/low-activity relative to OhMyThreads; extra transitive weight. | OhMyThreads |
| `ParametricOptInterface.jl` (0.15.3) | JuMP ≥1.30 has native `Parameter`; the repo already uses it (MPC, planning oracle). | Native `Parameter`. |
| `CUDA`/`CuClarabel`/GPU | Not open-hardware-portable, immature for per-hour SOCP duals; this is a CPU memory problem. | n/a |
| Switching conic solver default for scale (e.g., SCS) | Noisy duals break DADP/price claims. Memory is not the reason to trade accuracy. | Clarabel; `:faer` as an opt-in experiment only. |
| `Inequality.jl` (0.0.4) and similar | Stale, v0.0.x; hides the negative-surplus convention. | Own ~60-line metrics module. |
| `Distributions.jl` for EV/household samplers | Heavy dependency; the sampling algorithms for non-uniform distributions are not guaranteed bit-stable across versions, which defeats the `StableRNGs` + seeded-population reproducibility goal. | Hand-rolled inverse-CDF/Box-Muller on `StableRNG` (verify `randn` stream stability is acceptable; otherwise Box-Muller from `rand`). If it is ever needed, make it a weakdep for non-golden paths. |
| `Parquet2`, `Arrow`, `ZipFile`, HTTP clients in `[deps]` | Download/convert is one-off; runtime must not need network. | Separate `scripts/data_prep` env; vendor small CSVs with licenses. |
| `Graphs.jl` for portfolio topology | Multi-node aggregator portfolios are an index map (aggregator to bus set) on existing radial data. | Existing feeder structs + `SparseArrays`. |
| `PowerModelsDistribution` / OpenDSS bindings for 8500 | Existing dependency-free parser/reducer already handled IEEE-123 and 8500. | Existing `scripts/reduce_ieee8500_impedances.jl`. |
| Binary variables in new devices | Break convexity and DADP duals. | Convex relaxations + diagnostics (above). |
| JuMP/Clarabel version pin bumps | Registry shows JuMP 1.32.1 and HiGHS 1.26.0 now available vs our 1.30.1 / 1.24.1 pins. The repo already hit a `Pkg.test` resolver mismatch (JuMP 1.31 vs 1.30) that caused a flake root-cause. | Keep compat floors; verify golden canary on the resolved versions before changing floors. Clarabel 0.11.1 is still current. |

## Installation

```julia
# Runtime (package) — the ONLY new runtime dep
using Pkg; Pkg.activate(".")
Pkg.add(name="OhMyThreads", version="0.8.7")   # then set compat OhMyThreads = "0.8.7" in Project.toml
# Optional: keep as a plain `[deps]` entry (not weakdep); parallelism is core, but the default path must stay serial.

# Offline data prep (separate env, NOT in package deps)
# scripts/data_prep/Project.toml:  Parquet2 = "0.2.37", Arrow = "2.8.1", CSV, DataFrames
```

CI/test runs:
```bash
julia --project=. -t 4 -e 'using Pkg; Pkg.test()'     # threaded leg (new)
JULIA_NUM_THREADS=1 julia --project=. ...             # default serial leg unchanged
```
Respect the TestItemRunner caveats already recorded (plans' `<verify>` commands, scratch `.jl` scanning): add any threaded test as an ordinary `@testitem` with an internal `Threads.nthreads()` guard (`@test_skip`-style when `nthreads()==1` is **not** acceptable. Instead run a dedicated `-t2` job, and keep the item's serial reference computation inside the same item).

## Version verification (Julia General registry, fetched 2026-10-09)

| Package | Registry latest | Repo pin | Note |
|---------|----------------|----------|------|
| OhMyThreads | 0.8.7 | (new) | compat julia 1.10.0-1 |
| ChunkSplitters | 3.2.0 | transitive | |
| Clarabel | 0.11.1 | 0.11.1 | current |
| JuMP | 1.32.1 | 1.30.1 | floors only; see above |
| HiGHS | 1.26.0 | 1.24.1 | floors only |
| ParametricOptInterface | 0.15.3 | not used | |
| StatsBase | 0.34.13 | not used | |
| Distributions | 0.25.131 | not used | |
| Parquet2 / Arrow | 0.2.37 / 2.8.1 | data-prep only | |
| Inequality | 0.0.4 | rejected | stale |
| ThreadPinning | 1.1.1 | optional | pin threads to cores for benchmarks only; dev/bench env |

## Confidence

| Area | Level | Basis |
|------|-------|-------|
| OhMyThreads version + choice | HIGH (version), MEDIUM (choice) | Registry verified; Julia 1.10 compat verified; choice is ecosystem judgment (base `@threads` + `TaskLocalValue`-style pools would also work) |
| Threads over Distributed | HIGH | Memory arithmetic on this host + JuMP docs |
| JuMP models not thread-safe, one model per task | HIGH | Official JuMP parallelism tutorial |
| Clarabel instance-level thread-safety | LOW-MEDIUM | Not documented; inferred from pure-Julia design; **requires spike** |
| HiGHS concurrent instances | LOW | Not verified |
| Clarabel `:faer` benefits for memory | LOW | Settings list verified; effect on memory/duals not measured |
| DSO-hour concurrency worsens memory wall | MEDIUM | Reasoned from measured 11.5 GiB single-process peak and linear-in-T unattributed growth; to be confirmed by profiling |
| Data sources (ACN, TEMPO, When2Heat) | MEDIUM | Existence/scope verified via search; licensing/terms not checked, so check before vendoring |
| No equity package needed | MEDIUM-HIGH | Registry check showed only a stale 0.0.4 package |

## Sources

- JuMP parallelism tutorial (thread safety, one model per thread, Distributed `pmap`): https://jump.dev/JuMP.jl/stable/tutorials/algorithms/parallelism/
- Clarabel settings (`direct_solve_method`, `max_threads`, presolve): https://clarabel.org/stable/api_settings/
- Clarabel paper (Julia/Rust implementations, QDLDL, faer option): https://arxiv.org/pdf/2405.12762
- Julia General registry `Versions.toml`/`Compat.toml` (OhMyThreads, Clarabel, JuMP, HiGHS, Inequality, etc.), fetched 2026-10-09
- Julia Discourse threads on JuMP multithreading overheads (solves of 10-30 s needed to outweigh overhead; small QPs gain less): https://discourse.julialang.org/t/jump-slowed-down-in-multithreading/92206
- Data: ACN-Data https://ev.caltech.edu/ ; NREL TEMPO/dsgrid EV profiles https://opennetzero.org/national-renewable-energy-laboratory-nrel/demand-side-grid-dsgrid-tempo-light-duty-vehicle-charging-profiles-v2022 ; EV V2G-capable dataset https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12246261/ ; When2Heat https://data.open-power-system-data.org/when2heat/
- Project context: `.planning/PROJECT.md`, `CLAUDE.md`, memory notes (HiGHS exactness defaults, TestItemRunner traps, 8500 memory-wall measurements)

## Open items for phase-level research

1. Spike: concurrent independent Clarabel `Optimizer`s under `-t 4`, bitwise determinism vs serial (gate for all parallel work).
2. Spike: per-iteration speedup realistically available for AGR-OPT at 784 houses. Small QPs may be overhead-bound, so batch several aggregators per task (`nchunks`) and measure; the Discourse evidence suggests gains appear only when each task is meaningfully heavy.
3. Attribute the 3.4 GiB unattributed memory (per-hour DSO state hypothesis) before designing the solver-state pool.
4. Decide Volt-VAR formulation (optimized-Q upper bound vs fixed-point curve) with the thesis owner.
5. Confirm data licenses (ACN-Data terms, When2Heat CC-BY) before vendoring any derived parameters.
