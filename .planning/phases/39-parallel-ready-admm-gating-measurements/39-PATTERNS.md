# Phase 39: Parallel-Ready ADMM & Gating Measurements - Pattern Map

**Mapped:** 2026-10-24
**Files analyzed:** 11 (4 modify, 7 create/extend)
**Analogs found:** 9 / 11 files have in-repo analogs (threading mechanics and BLAS-save/restore have none — see No Analog Found)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/admm/solve_admm.jl` (modify: `parallel::Bool=false` kwarg + guard) | orchestrator (public entry point) | request-response | itself — its own additive-kwarg precedents (`time_limit_s`, `atol_exact`, `rtol_exact`) + boundary-guard block | exact |
| `src/admm/admm_phases.jl` (modify: split execute step, `Threads.@spawn`) | service (named algorithm phases) | batch (per-iteration AGR solves) | itself — the AGR block in `_admm_iterate!` + ordered-write idioms | exact |
| `src/admm/admm_state.jl` (modify: per-aggregator snapshot helpers, PAR-05) | model/state | transform | `_react_outputs` in the same file (the `q_devices` per-bus Dict precedent) | exact |
| `src/experiments/store.jl` (modify: `julia_threads`/`blas_threads` keys) | persistence/provenance | CRUD (JLD2 save) | itself — `result_to_dict` additive-key precedents + `run_and_store` `@tagsave` | exact |
| `.planning/spikes/005-clarabel-concurrency/sweep.jl` (new) | test/measurement script | batch | `.planning/spikes/001-relaxation-validity-map/sweep.jl` header + CONVENTIONS.md | role-match |
| `.planning/spikes/005-clarabel-concurrency/README.md` (new) | documentation | — | `.planning/spikes/001-relaxation-validity-map/README.md` frontmatter | role-match |
| `scripts/benchmark_ieee8500.jl` + new staged harness (extend/new) | measurement harness | batch + file-I/O | `scripts/profile_ieee8500_memory.jl` (whole file) + `run_admm_point` RSS staging | exact |
| `results/ieee8500_benchmark/memory_attribution.csv` (new output) | data deliverable | file-I/O | `memory_profile.csv` producer's keyed-upsert idiom | exact |
| `docs/literate/ieee8500_scaling.jl` (append doc note) | documentation | — | its own "Post-refactor measured results" appended section (lines 216-228) | exact |
| `test/test_admm_parallel.jl` (new) | test | — | `test/test_admm_knifeedge_canary.jl` (fixture + pinned-run idiom) + `test/test_admm_phases.jl` (internal-phase style) | exact |
| `test/test_experiments.jl` (extend provenance item) | test | — | its own `"experiments: provenance tagsave"` testitem (lines 274-319) | exact |

Observed-only (no mutation): `src/solver/factory.jl` — its `attrs...` kwarg seam (lines 138-144) is where solver-thread pinning passes through at build time for the threaded path; its `QP()`/`SOCP()` defaults stay byte-identical (golden policy).

---

## Pattern Assignments

### `src/admm/solve_admm.jl` (orchestrator, request-response) — MODIFY

**Analog:** itself. Three prior additive kwargs (`time_limit_s`, `atol_exact`, `rtol_exact`) each landed as "default keeps pre-existing behavior byte-for-byte" — `parallel::Bool = false` is the fourth, same recipe.

**Signature + additive-kwarg pattern** (lines 260-281):
```julia
function solve_admm(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int = 24,
    ...
    time_limit_s::Union{Nothing, Real} = nothing,
    atol_exact::Union{Nothing, Real} = nothing,
    rtol_exact::Real = 1e-4,
)
```
→ append `parallel::Bool = false` as the last kwarg; document it in the docstring's Returns/Throws sections like the others.

**Fail-loud boundary guard pattern** (lines 282-301) — the template for the `parallel=true && Threads.nthreads()==1 → ArgumentError` guard:
```julia
    # ---- Boundary guards (fail here, not deep in the loop) -------------------------------------
    _check_admm_pair!(:solve_admm, feeder, pf)
    isempty(aggregators) && throw(ArgumentError("solve_admm needs at least one aggregator"))
    ...
    maxiter >= 1 ||
        throw(ArgumentError("solve_admm needs maxiter ≥ 1 (got maxiter=$maxiter)"))
```
Guards run BEFORE any build; each names the violated requirement in the message. The `parallel` guard belongs in this block: `parallel && Threads.nthreads() == 1 && throw(ArgumentError("solve_admm: parallel=true requires Threads.nthreads() > 1 — restart Julia with `julia -t N`. No silent serial fallback."))`.

**Fail-loud typed error** (lines 321-336) — `ConvergenceError` with diagnostics naming the violated quantities; PAR-03 rethrows must land with this same vocabulary.

**Certificate re-wrap seam** (lines 361-366) — the existing `catch`/`rethrow()` discipline PAR-03 must preserve:
```julia
    return try
        _admm_certify(st, rmode, mode, aggregators, λ₀, atol_exact, rtol_exact)
    catch err
        (err isa CertificateError && err.iterations === nothing) || rethrow()
        throw(CertificateError(err.msg; kind = err.kind, iterations = residuals.iters))
    end
```
Note the idiom: type-check THEN `rethrow()` for non-matching errors — the threaded join must do the same (`e isa TaskFailedException ? throw(e.task.exception) : rethrow()`).

**Threading the flag down:** `_admm_build` (line 312) and `_admm_iterate!` (line 313) are positional-arg calls — `parallel` rides into `_admm_iterate!` as an additional positional/kwarg; the threaded branch lands inside `admm_phases.jl`, not here.

---

### `src/admm/admm_phases.jl` (service, batch) — MODIFY

**Analog:** itself. The split-execute site and the float-order contract both live here.

**THE split site — AGR-solve block in `_admm_iterate!`** (lines 164-172). Serial branch keeps this exact loop; threaded branch replaces ONLY this block:
```julia
    for k in 1:maxiter
        # (1) AGR-OPT[j] ∀j: coeff −λ_j − ρ·c_j (thesis 3.46). Mid-loop: no battery/4Q certificate.
        for j in load_nodes
            _react_agr_solve!(rmode, st, j)
        end

        # (2) DSO-OPT: coeff −λ_j − ρ·a_j (thesis 3.47); LIVE first sets dso.qag coefficients.
        _react_dso_prepare!(rmode, st)
        dres = solve_dso!(dso, λ, a, st.ρf; check_exact = false, strict = false)
```
Steps (2)-(5) stay SHARED and serial for both executors (residual accumulation `for j in load_nodes, t in 1:T` at lines 183-191 is the float-order contract — never parallelized).

**Ordered-writes idiom to preserve** — `_adapt_rho!`'s `set_rho!` ladder (lines 128-134):
```julia
            if ρ_new != st.ρf
                st.ρf = ρ_new
                set_rho!(st.dso, st.ρf)
                for j in st.load_nodes
                    set_rho!(st.agr_by_bus[j], st.ρf)
                end
            end
```
dso first, then each AGR in `load_nodes` order — the file header (lines 1-9) declares this order binding; do not reorder while splitting.

**Certify-phase AGR re-solves** (lines 281-283) — second split site (same helper; can throw `CertificateError` → PAR-03 applies here too):
```julia
    for j in load_nodes
        _react_agr_solve!(rmode, st, j; final = true, has_4q = has_4q_by_bus[j])
    end
```

**Result NamedTuple assembly** (`_admm_certify` return, lines 324-337) — where PAR-05's additive keys attach; existing keys (`welfare`, `dadp`, `λ`, `iters`, `residuals`, `dso_ctx`, `exact_maxgap`, `mu_q`, `q_devices`, `reactive_consensus_mode`, `status`) must stay byte-identical.

**File-header documentation convention** (lines 1-9) — every modified src file carries the `# SEAM:` header block; the split must update it (statement order per iteration) rather than leaving stale prose.

---

### `src/admm/admm_state.jl` (model/state, transform) — MODIFY (PAR-05 helpers)

**Analog:** `_react_outputs` in the same file (lines 387-407) — the EXACT per-aggregator additive-output precedent:
```julia
function _react_outputs(::_ReactiveLive, st::AdmmState, agr_by_bus)
    load_nodes = st.load_nodes
    T = st.T
    ...
    mu_q_mat = reduce(vcat, (permutedims(-st.react.μq[j]) for j in load_nodes))
    q_devices = Dict{Int, Vector{Float64}}()
    for j in load_nodes
        for v in agr_by_bus[j].ctx.agg_device_vars[j]
            if haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)
                q_devices[j] = Float64[value(v.q[t]) for t in 1:T]
            end
        end
    end
    return (mu_q_mat, q_devices)
end
```
Copy for PAR-05: per-bus `Dict{Int, ...}` keyed by `load_nodes`; per-slot matrices via `reduce(vcat, permutedims(...))` in ascending-bus order; device reads via `agr.ctx.agg_device_vars[j]` value snapshots. The OFF/non-applicable variant returns stable `nothing` keys (lines 388-389) — mirror this: additive keys ALWAYS present, `nothing` when not populated.

---

### `src/experiments/store.jl` (persistence, CRUD) — MODIFY

**Analog:** itself. `result_to_dict` (lines 191-216) — additive keys measured at save time:
```julia
function result_to_dict(res::ScenarioResult)
    d = _scenario_identity(res.scenario; style = :record)
    d[:welfare] = res.welfare
    ...
    d[:julia_version] = string(VERSION)          # ← line 202: the additive-key precedent;
    ...                                          #   julia_threads/blas_threads go right beside it:
    return d                                     #   d[:julia_threads] = Threads.nthreads()
end                                              #   d[:blas_threads]  = BLAS.get_num_threads()
```
Second precedent: `reactive_consensus_mode` (lines 199-201) — an ADMM-specific key stored as a primitive (`Symbol`), `missing` for non-ADMM runs. `julia_threads`/`blas_threads` are process-level (never `missing`), even simpler.

**Executor-blind identity seam — DO NOT TOUCH** (lines 90-119): `_scenario_identity` builds BOTH the record keys and the filename; `scenario_filename` (lines 147-165) consumes `style = :filename`. PAR-04 = these two functions produce identical output regardless of executor. The ONLY safe place for the new keys is AFTER the `_scenario_identity` call inside `result_to_dict`. NEVER add `parallel` to `_strategy_knobs` (lines 53-78) — that feeds both styles and would flip filenames.

**`@tagsave` provenance stamp** (lines 251-262) — unchanged by this phase, but the pattern any new persistence must reuse:
```julia
    @tagsave(
        joinpath(dir, scenario_filename(s)),
        dict;
        storepatch = true,
        gitpath = pkgdir(@__MODULE__),
        safe = true,
    )
```

---

### `.planning/spikes/005-clarabel-concurrency/sweep.jl` (measurement script, batch) — NEW

**Analog:** `.planning/spikes/001-relaxation-validity-map/sweep.jl` header + `.planning/spikes/CONVENTIONS.md`.

**Header pattern** (spike 001, lines 1-15):
```julia
# Spike 001 — relaxation validity map: the sweep.
#
# For each point of a (pv_scale × load_scale × vmax) grid, computes ...
#
# SUBSTRATE: ... replicated here because the original lives in
# a TestItems @testmodule. ...
#
# POSITIVE/NEGATIVE CONTROLS (non-negotiable): ...
#
# Run:  julia --project=. .planning/spikes/001-relaxation-validity-map/sweep.jl
```
Copy for 005: state the question (bitwise serial-vs-threaded Clarabel, `-t 4`), the substrate (a multi-aggregator ADMM fixture with production kwargs), and the controls (a known-passing serial reference re-solved within the same run must reproduce itself bitwise; a deliberately-corrupted copy must FAIL the byte-compare — the negative control proving the comparator works).

**Binding conventions from `.planning/spikes/CONVENTIONS.md`:**
- Observe without mutating `src/` (lines 32-34) — solver-thread pinning happens inside the spike via `set_attribute`, never as a factory change.
- Positive + negative controls in every sweep, checked on each run (lines 35-37).
- Failure classes are data (lines 41-43) — the `direct_model` leg's `AddVariableNotAllowed` error is a recorded OUTCOME, not a crash: catch it, keep the message, classify.
- Output: stdout table + CSV (sweep.csv in the spike dir); compute (sweep.jl) split from any plotting (plot_map.jl) (lines 12-28).
- Byte comparison idiom (RESEARCH "Don't Hand-Roll"): `reinterpret(UInt8, …)` compare or `isequal` — NEVER `isapprox`.

**README.md frontmatter pattern** (spike 001 README lines 1-8):
```markdown
---
spike: 001
name: relaxation-validity-map
type: standard
validates: "Given ... then ..."
verdict: VALIDATED
related: []
tags: [...]
---
```
For 005: `verdict:` starts as PENDING and is filled with PASS/FAIL + the bitwise-equality evidence; the `direct_model` answer is recorded as a documented finding either way (honesty policy: a FAIL keeps the executor default-off and documents why).

---

### Staged RSS attribution harness + `results/ieee8500_benchmark/memory_attribution.csv` — NEW/EXTEND

**Primary analog:** `scripts/profile_ieee8500_memory.jl` (entire file, 127 lines) — the Phase-35 staged-harness idiom, reusable almost wholesale for SCALE-06.

**Per-stage probe** (lines 24-29):
```julia
function proc_status_kb(key::String)
    for line in eachline("/proc/self/status")
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end
```

**Stage-report + row-accumulation pattern** (lines 36-55):
```julia
function report(stage::Int, name::String)
    rss, hwm = proc_status_kb("VmRSS"), proc_status_kb("VmHWM")
    live = Base.gc_live_bytes() / 2^20
    println(stage, "\t", name, "\t", rss, "\t", hwm, "\t", round(live; digits = 1))
    flush(stdout)
    push!(ROWS, (; fixture = FIXTURE, density = DENSITY, T = T_H, stage = stage,
                 name = name, VmRSS_kB = rss, VmHWM_kB = hwm, gc_live_MB = live))
    return nothing
end
```

**Staged measurement with GC boundaries** (lines 98-103) — the attribution idiom (GC.gc() between stages; malloc_trim to expose allocator retention):
```julia
    if max_stage >= 4
        GC.gc()
        report(4, "after_gc")
        ccall(:malloc_trim, Cint, (Cint,), 0)
        report(4, "after_malloc_trim")
    end
```
SCALE-06's new stages (build / per-iteration retained state / per-hour DSO solver state / consolidation) follow this exact `report(n, "name")` sequencing, one process per T point (10 and 24 separately — HWM resets per process).

**Keyed CSV upsert** (lines 109-121; same idiom at `scripts/benchmark_ieee8500.jl` lines 448-465):
```julia
    path = joinpath(out_dir(), "memory_profile.csv")
    mkpath(out_dir())
    df = DataFrame(ROWS)
    if isfile(path)
        old = CSV.read(path, DataFrame)
        k(r) = (string(r.fixture), r.density, r.T, r.stage, r.name)
        nk = Set(k(r) for r in eachrow(df))
        df = vcat(filter(r -> !(k(r) in nk), old), df; cols = :union)
    end
    CSV.write(path, df)
```
For a NEW deliverable, `memory_attribution.csv` starts empty — but keep the same keyed-upsert so re-runs replace their own rows (never silently drop others), and `cols = :union` for schema evolution.

**Whole-run RSS delta wrapper** — `scripts/benchmark_ieee8500.jl` `run_admm_point` (lines 626-675):
```julia
    t0 = time_ns()
    rss_before = Sys.maxrss()
    result = try
        r = solve_admm(...)
        ...
    catch err
        # Failure rows keep their evidence: iterations from the exception when it carries them
        ...
    end
    rss_after = Sys.maxrss()
    peak_delta_mb = (rss_after - rss_before) / (1024^2)
```
Two binding habits: (a) the documented `Sys.maxrss()` monotonic-HWM caveat sits in the docstring (lines 590-596) — replicate it; (b) failed runs produce EVIDENCE rows (`ERROR:<ExceptionType>`, iterations when the exception carries them, `-1` sentinel otherwise), never dropped rows (honesty policy).

**Harness safety:** `if abspath(PROGRAM_FILE) == @__FILE__` gate (profile lines 125-127) — the new harness must stay include-safe the same way.

---

### `docs/literate/ieee8500_scaling.jl` (documentation) — APPEND

**Analog:** its own "Post-refactor measured results" section (lines 216-228) — the Phase-35 doc-note pattern:
```julia
# ## Post-refactor measured results
#
# *(Appended 2026-10-04; provenance tightened 2026-10-05. The v3.0 text above is kept as
# history; ... Every figure below names its source: a file in `results/ieee8500_benchmark/` ...)
#
# **Units.** All memory figures in this section are binary: 1 GiB = 2^30 bytes ...
```
Copy: a dated "*(Appended 2026-10-…)*" preamble; every number names its source CSV + row key; a Units paragraph; honesty statements about what is NOT established (the section explicitly writes "What consumes the memory inside `solve_admm` is not established by the …" at line 297) — SCALE-06's note extends this with the per-component attribution, stated tolerances, and the documented residual.

---

### `test/test_admm_parallel.jl` (test) — NEW

**Analog 1: fixture + pinned-run idiom** — `test/test_admm_knifeedge_canary.jl` (lines 34-56):
```julia
@testitem "admm knife-edge canary: IEEE-13 mid-loop SOCP pinned trajectory (canary, admm)" setup =
    [ExperimentHarnessFixtures] tags = [:admm, :canary] begin
    using TSODSO
    using Logging: with_logger, SimpleLogger, Warn

    kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
    s = TSODSO.Scenario(; kw..., strategy = :admm)
    ...
    r = with_logger(SimpleLogger(buf, Warn)) do
        TSODSO.run_scenario(s)
    end
    ...
    @info "IEEE-13 ADMM knife-edge canary" iters = r.iters welfare = r.welfare escalations =
        escalations
    @test r.iters == 56
    @test isapprox(r.welfare, -4823.66604824162; rtol = 1e-6, atol = 1e-3)
```
Copy: `setup = [ExperimentHarnessFixtures]`, tags `[:admm, :parallel]`-style, `minimal_scenario_kwargs()` + `strategy = :admm` for the multi-aggregator fixture, loud `@info` of measured numbers BEFORE assertions (attribution on failure), explicit pins.

**Analog 2: internal-phase unit style** — `test/test_admm_phases.jl` (lines 1-10, 44-55): direct `TSODSO._admm_build(...)`/internal calls against `TwoBusFixtures`/`ExperimentHarnessFixtures`, file-header note that goldens live elsewhere ("this file pins only dispatch/propagation behaviour"). The guard test (`parallel=true` at 1 thread → `ArgumentError`, 1-thread-safe) and PAR-05 additive-keys items follow this style.

**Equality-test field selection** (RESEARCH Pitfall 4 — no full in-repo analog): compare `iters`, `residuals.primal_trace`, `residuals.dual_trace`, `rho_trace`, `welfare`, `dadp`, `exact_maxgap` with literal `==` — `AdmmResiduals` is mutable, so never `==` whole result NamedTuples.

**Test runner contract** — `test/runtests.jl` lines 40-48: the new file is auto-discovered; thread-gated items must fail loud with the documented invocation when `Threads.nthreads() == 1`; any `@test_skip`/`@test_broken` needs an `expected_broken.txt` entry or the guard fails the run.

---

### `test/test_experiments.jl` (test, extend provenance item) — MODIFY

**Analog:** its own `"experiments: provenance tagsave"` testitem (lines 274-319):
```julia
@testitem "experiments: provenance tagsave" setup = [ExperimentHarnessFixtures] begin
    using TSODSO
    using DrWatson: wload
    ...
        ExperimentHarnessFixtures.with_tempdir() do dir
            kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
            s = TSODSO.Scenario(; kw..., strategy = :centralized)
            TSODSO.run_and_store(s; dir = dir)
            f = joinpath(dir, TSODSO.scenario_filename(s))
            @test isfile(f)
            dict = wload(f)
            @test haskey(dict, "gitcommit")
            @test haskey(dict, "julia_version")
            @test dict["julia_version"] == string(VERSION)
            @test haskey(dict, "seed")
        end
    ...
end
```
PAR-04 extension: add `@test haskey(dict, "julia_threads")` / `"blas_threads"` here (String keys after `wload` — see the testitem's own lines 302-311 note), plus a filename-invariance assertion: `scenario_filename` unchanged when only the executor differs (it takes only `s::Scenario`, so assert the helper still round-trips identically with/without a parallel run in the process).

---

## Shared Patterns

### 1. Fail-loud boundary guards (ArgumentError, message names the requirement)
**Source:** `src/admm/solve_admm.jl` lines 282-301
**Apply to:** the `parallel` 1-thread guard; the spike harness's flag parsing (`parse_kv_flag` + `throw(ArgumentError(...))` in `scripts/profile_ieee8500_memory.jl` lines 58-71)
```julia
isempty(aggregators) && throw(ArgumentError("solve_admm needs at least one aggregator"))
maxiter >= 1 || throw(ArgumentError("solve_admm needs maxiter ≥ 1 (got maxiter=$maxiter)"))
```

### 2. Additive-key / byte-identical default (golden policy)
**Sources:** `src/experiments/store.jl` line 202 (`d[:julia_version] = string(VERSION)`); `src/planning/retry.jl` lines 123-127 (`attempts_out::Union{Nothing,Ref{Int}} = nothing` — "Defaults to nothing ... so every existing call site ... behaves IDENTICALLY to before"); `src/admm/solve_admm.jl` docstring lines 158-170 (`time_limit_s` — "The DEFAULT nothing preserves the pre-existing unbounded behavior BYTE-FOR-BYTE — this is purely additive")
**Apply to:** every file this phase touches — new kwargs default OFF, new dict/NamedTuple keys always present with `nothing`/`missing` when unpopulated, no existing key or filename moves.

### 3. Typed-error rethrow, no new wrapper types
**Source:** `src/core/errors.jl` (whole file) — `TSODSOError` hierarchy (`SolveFailedError` lines 33-59, `CertificateError` lines 71-82 with `kind`/`iterations`, `ConvergenceError` lines 91-96); re-wrap site `src/admm/solve_admm.jl` lines 361-366
**Apply to:** PAR-03 join logic — unwrap `TaskFailedException` → `throw(e.task.exception)` (ORIGINAL object); catch sites keep matching `err isa CertificateError` etc. NEVER `@sync` (would produce `CompositeException`).

### 4. SEAM file-header documentation
**Source:** every modified src file (`src/admm/solve_admm.jl` lines 1-50; `src/admm/admm_phases.jl` lines 1-9 — which pins the per-iteration statement order and `set_rho!` order)
**Apply to:** update (never stale-ify) headers when the split executor lands; document the threaded branch's contract in the same comment block.

### 5. Deterministic keyed CSV upsert
**Source:** `scripts/benchmark_ieee8500.jl` lines 448-465; `scripts/profile_ieee8500_memory.jl` lines 109-121
**Apply to:** `memory_attribution.csv` writer and the spike's `sweep.csv` writer — key rows, `cols = :union`, never drop other rows.

### 6. DrWatson provenance stamping
**Source:** `src/experiments/store.jl` lines 251-262 (`@tagsave(...; storepatch = true, gitpath = pkgdir(@__MODULE__), safe = true)`)
**Apply to:** unchanged this phase, but the `julia_threads`/`blas_threads` keys ride this exact dict — no new persistence path.

### 7. Per-command test selection + expected-broken guard
**Source:** `test/runtests.jl` lines 40-48 (`TSODSO_TEST_FILES` restriction; unexpected skip/broken records fail the run)
**Apply to:** thread-gated test invocation `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'`; the canary re-check `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl ...`.

---

## No Analog Found

| File / Concern | Role | Data Flow | Reason | Planner guidance |
|----------------|------|-----------|--------|------------------|
| `Threads.@spawn` task fan-out / fetch-in-order join | concurrency | event-driven | **Zero occurrences** of `Threads.@spawn`/`Threads.`/`BLAS.set_num_threads` in the repo (grep-verified across `src/`, `scripts/`, `test/`) | Use RESEARCH.md Patterns 1-3 verbatim (empirically verified this session on the pinned toolchain): spawn per aggregator, fetch in `load_nodes` order, `e isa TaskFailedException ? throw(e.task.exception) : rethrow()`, `BLAS.set_num_threads(1)` ONCE at executor entry, no `@sync`, no `threadid()` indexing, no `st` writes inside tasks |
| BLAS save/restore test helper | test utility | — | No existing global-state save/restore helper exists in `test/` | Wave 0 new item (RESEARCH Pitfall 1): save `BLAS.get_num_threads()`, restore in `finally`, re-verify canary green in the same process after parallel items |
| Per-iteration retained-state attribution stages (SCALE-06 stages beyond `profile_ieee8500_memory.jl`'s 0-5) | measurement | batch | The existing harness stops at stage 5 (`after_agr_opts`); mid-loop/per-hour/consolidation stages are new | Extend the `report(n, "name")` idiom — new stages are additive stage numbers, one process per T point; use `GC.gc()` + instantaneous VmRSS (HWM caveat, Pitfall 7) |

## Metadata

**Analog search scope:** `src/admm/`, `src/experiments/`, `src/core/`, `src/solver/`, `src/planning/`, `test/`, `scripts/`, `docs/literate/`, `.planning/spikes/`, `results/ieee8500_benchmark/`
**Files read in full or in targeted sections:** 18 (solve_admm.jl, admm_phases.jl, admm_state.jl [373-407], store.jl, retry.jl, factory.jl, errors.jl, runtests.jl, test_admm_knifeedge_canary.jl, test_admm_phases.jl [1-55], test_experiments.jl [265-339], benchmark_ieee8500.jl [425-469, 580-689], profile_ieee8500_memory.jl, ieee8500_scaling.jl [215-264], CONVENTIONS.md, spike 001 sweep.jl [1-60] + README [1-25], plus grep verification of Threads/BLAS absence)
**Pattern extraction date:** 2026-10-24
