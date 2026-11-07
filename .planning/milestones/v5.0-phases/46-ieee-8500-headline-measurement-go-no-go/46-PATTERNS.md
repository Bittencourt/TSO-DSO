# Phase 46: IEEE-8500 Headline Measurement (go/no-go) - Pattern Map

**Mapped:** 2026-11-05
**Files analyzed:** 9 (2 src edits, 1 new script, 1 new CSV, 1 new test file, 1 test edit, 1 docs edit, 1 README edit, api.md check)
**Analogs found:** 9 / 9

All line numbers were read at HEAD 491e8f3. Corrections in CONTEXT "Post-Research Corrections" supersede earlier figures: 11.209 GiB (11,753,716 kB), 4.569 / 0.851 GiB, 4,866 buses / 4,865 branches, `:default_10pct` selector, no new `Scenario` field.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/experiments/Scenario.jl` (edit) | config / validation | request-response (constructor guards) | itself, lines 24, 48, 134-212 | exact |
| `src/experiments/materialize.jl` (edit) | service (population builder) | transform | `_build_population_core` `:case_a_784` branch (1041-1049) + `density_filtered_population` (`scripts/benchmark_ieee8500.jl:252-277`) | exact |
| `scripts/ieee8500_scenario_point.jl` (new) | script (measurement) | batch + file-I/O | `scripts/profile_ieee8500_memory_attribution.jl` (+ `case_a_magnitude.jl` status rows, `benchmark_ieee8500.jl` CLI) | role-match (composite) |
| `results/ieee8500_benchmark/scenario_table.csv` (new) | data artifact | file-I/O (keyed upsert) | `memory_attribution.csv`, `point_resources.csv` | role-match |
| `test/test_ieee8500_scenario.jl` (new) | test | request-response | `test/test_case_a_magnitude.jl:505-530` (script include), `test/test_strategies.jl`, `test/test_flex_population.jl` | role-match |
| `test/test_flex_population.jl` (edit, line 20) | test | - | itself | exact |
| `docs/literate/ieee8500_scaling.jl` (append) | docs | transform (reads CSV) | the 2026-10-24 appended section (lines 406-end) + `read_sweep_csv` (140-160) | exact |
| `scripts/README.md` (row) | docs index | - | row at README:25 / :37 / :46 | exact |
| `docs/src/api.md` | docs | - | no edit needed (autodocs, line 188) | n/a |

## Pattern Assignments

### `src/experiments/Scenario.jl` (config, constructor validation)

**Analog:** the file itself. Edits are additive; the struct, field order, `==`, `hash`, `scenario_filename` are untouched (pinned by `test/test_strategies.jl:108-120` `fieldnames` assertion).

**Selector tuples** (lines 24 and 48), widen:
```julia
const SCENARIO_VALID_FEEDERS = (:ieee13, :ieee123)           # -> (:ieee13, :ieee123, :ieee8500, :ieee8500_mv)
const SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)   # -> (:default, :case_a_784, :default_10pct)
```
Both have a docstring above them (lines 21-23, 45-47); update prose to name the 8500 family and that `:default_10pct` is 8500-only (density 0.1 of load buses, plus the 4 capacitor aggregators). The `Scenario` docstring interpolates `$(SCENARIO_VALID_FEEDERS)` (line 59) and `$(SCENARIO_VALID_POPULATIONS)` (line 62), so the API page updates itself. Update the "Construction errors" prose at lines 96-103 to list the new guards.

**Guard pattern to copy** (lines 134-141 for membership, 204-212 for a cross-field guard). Place the new guards after the `supports_pf` / ADMM `allow_export` guard (after line 212, before the `pf_ε` normalization at 213):
```julia
if feeder ∉ SCENARIO_VALID_FEEDERS
    throw(
        ArgumentError(
            "Scenario: unknown feeder selector $(repr(feeder)); expected one of " *
            "$(SCENARIO_VALID_FEEDERS)",
        ),
    )
end
...
if strategy isa ADMM && !allow_export
    throw(
        ArgumentError(
            "Scenario: strategy ADMM requires allow_export = true (the free-sign " * ...
        ),
    )
end
```
New guards (all `ArgumentError`, never `@assert`; message starts `"Scenario: "`, uses `repr(...)`):
1. `population === :default_10pct && feeder ∉ (:ieee8500, :ieee8500_mv)`.
2. `population === :case_a_784 && feeder ∈ (:ieee8500, :ieee8500_mv)` (fail at construction; legacy `:ieee123 + :case_a_784` behaviour untouched, it still throws at materialization).
3. `feeder ∈ 8500 family && pf === :ac` (research A3, discretionary, accepted by CONTEXT).
4. `feeder ∈ 8500 family && strategy isa Union{MPC, Stochastic}` (research A3). `MPC` and `Stochastic` are already referenced in `supports_pf`/strategies; use `isa` exactly as line 204 does for `ADMM`.
Define one small private const (for example `const _SCENARIO_8500_FEEDERS = (:ieee8500, :ieee8500_mv)`) next to the other tuples rather than repeating the literal. Keep it un-exported (`test/test_exports.jl:37` curated list needs no edit).

**Do not** guard `population = :default` on 8500 (density 1.0, measured OOM; document only).

---

### `src/experiments/materialize.jl` (service, transform)

**Analog 1 (where to branch):** `_build_population_core` (lines 1033-1170). Existing structure: `if sym === :case_a_784 ... elseif sym !== :default throw ... end` then the `:default` body (8500 branch at 1099-1166, ends `return vcat(houses, cap_houses)`).

**Analog 2 (the rule to reproduce):** `scripts/benchmark_ieee8500.jl:252-277`:
```julia
function sample_density_buses(rng, buses::Vector{Int}, density::Real)
    density >= 1.0 && return sort(buses)
    n = clamp(round(Int, density * length(buses)), 1, length(buses))
    perm = StableRNGs.Random.randperm(rng, length(buses))
    return sort(buses[perm[1:n]])
end

function density_filtered_population(feeder, feeder_sym, profiles, seed, density, rng)
    buses = _harness_load_buses(feeder, feeder_sym)
    sampled = Set(sample_density_buses(rng, buses, density))
    full = build_population(:default, feeder, feeder_sym, profiles, seed)
    return filter(
        agg -> agg.bus in sampled || any(dv -> dv isa FixedCapacitor, agg.devices),
        full,
    )
end
```
`_harness_load_buses` (benchmark_ieee8500.jl:230-239) is identical to `_load_buses` (materialize.jl:193-203) for the 8500 symbols (`ieee8500_load_nodes()` / `ieee8500_mv_load_buses()`), so use `_load_buses`.

**Insert** a branch between the `:case_a_784` branch and the `elseif sym !== :default` guard (line 1087), converting that guard to an `elseif sym !== :default && sym !== :default_10pct`, and update its message ("expected :default, :default_10pct or :case_a_784"):
```julia
elseif sym === :default_10pct
    feeder_sym in (:ieee8500, :ieee8500_mv) || throw(ArgumentError("build_population(:default_10pct): defined over the IEEE-8500 fixtures only; got $(repr(feeder_sym))"))
    full  = _build_population_core(:default, feeder, feeder_sym, profiles, seed, sel)
    buses = _load_buses(feeder, feeder_sym)
    n     = clamp(round(Int, 0.1 * length(buses)), 1, length(buses))
    perm  = StableRNGs.Random.randperm(StableRNGs.LehmerRNG(seed), length(buses))
    keep  = Set(sort(buses[perm[1:n]]))
    return filter(a -> a.bus in keep || any(d -> d isa FixedCapacitor, a.devices), full)
```
`StableRNGs` is already in scope module-wide (`src/data/profiles.jl:13`, `using StableRNGs`, same module). Expected sizes: `:ieee8500` 1,177 load buses -> 118 + 4 capacitors = 122; `:ieee8500_mv` 1,138 -> 114 + 4 = 118. The `:default` branch stays byte-identical (build-full-then-filter, about 2.8 s).

**Wiring to copy:** how `sub_seed` reaches the selector (`materialize.jl:24`, `run.jl:61-73`):
```julia
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))
function _materialize(s::Scenario)
    feeder = build_feeder(s.feeder)
    profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
    λ₀ = build_price(s.price, s.T, profiles)
    aggs = build_population(s.population, feeder, s.feeder, profiles, sub_seed(s.seed, :population))
    return feeder, λ₀, aggs
end
```
`build_population` (public wrapper, lines 1011-1031) treats any non-`:case_a_784` selector as per-bus aggregators and skips pure-capacitor ones for `flex_devices`, so `:default_10pct` composes unchanged. Update the `build_population` docstring (ends ~line 1010) to document the new selector, and the `build_powerflow` docstring needs no change.

---

### `scripts/ieee8500_scenario_point.jl` (new; script, batch + file-I/O)

**Header/imports and include-safe gate** (analog: `scripts/profile_ieee8500_memory_attribution.jl:66-68`, `benchmark_ieee8500.jl:91-93,1379-1381`):
```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO, JuMP, CSV, DataFrames, StableRNGs
...
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
```
Header comment style: a multi-paragraph `# scripts/<name>.jl` block with usage lines, status vocabulary and honesty note (see profile script lines 1-64). Reference docs/CSVs by path, never by phase/requirement IDs (planning-ID guard, `scripts/` is in scope).

**Qualified internals** (check_script_api.jl flags bare unexported names): call `TSODSO._materialize`, `TSODSO.build_powerflow`, `TSODSO._admm_build`, `TSODSO._admm_iterate!`, `TSODSO._admm_certify`, `TSODSO.normalize_reactive_mode`, `TSODSO._default_reactive_consensus`, `TSODSO._react_mode`, `TSODSO.select_optimizer`, `TSODSO.QP` (same qualification as profile script lines 153-165).

**CLI parsing** (copy `parse_kv_flag` / `has_flag`, `benchmark_ieee8500.jl:776-783`; if the new script `include`s the harness, as the profiler does at line 66-67, it gets them free, but that drags in the harness's DrWatson/CSV setup. Prefer copying the two 8-line helpers so the script is standalone):
```julia
function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end
has_flag(args, flag::String) = flag in args
```
Flags (research Q3): `--feeder` (default `ieee8500`), `--T` (10), `--seed` (1), `--run-label`, `--time-limit` (1200), `--min-mem-avail-gib` (8), `--results-dir` (or env `TSODSO_IEEE8500_RESULTS_DIR`, as the harness does), `--record-nogo`, `--help` with a `const USAGE = """..."""` (analog `benchmark_ieee8500.jl:870-887`). Validate every flag before any heavy work (`ArgumentError`, as harness lines 891-896 and the `--topn` check).

**VmHWM reader** (copy verbatim, `profile_ieee8500_memory_attribution.jl:70-75`):
```julia
function proc_status_kb(key::String)
    for line in eachline("/proc/self/status")
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end
```
Binary GiB = kB / 1024^2; keep raw kB beside GiB in the row.

**Phase calls** (copy the exact signatures; this is `run(::ADMM)` + `solve_admm`, `src/experiments/run.jl:116-135`, `src/admm/solve_admm.jl:440-558`, and the profiler's staged equivalents at lines 153-165, 233-245, 298):
```julia
s = Scenario(; name = "ieee8500-scn", feeder = :ieee8500, population = :default_10pct, strategy = ADMM(), T = T, seed = seed)
t_mat = @elapsed ((feeder, λ₀, aggs) = TSODSO._materialize(s))
pf    = TSODSO.build_powerflow(s)
mode  = TSODSO.normalize_reactive_mode(TSODSO._default_reactive_consensus(aggs))
rmode = TSODSO._react_mode(mode)
st = ... ; t_build = @elapsed (st = TSODSO._admm_build(feeder, pf, aggs, s.T, λ₀, ρ, ρ, mode, rmode;
        agr_optimizer = TSODSO.select_optimizer(TSODSO.QP())))
t_solve = @elapsed TSODSO._admm_iterate!(st, rmode, A.maxiter, A.ε_abs, A.ε_rel, A.τ_ratio, A.μ,
        1e-2, 1e4, time_limit_s, false)
# certify (solve_admm defaults: atol_exact = nothing, rtol_exact = 1e-4, parallel = false)
TSODSO._admm_certify(st, rmode, mode, aggs, λ₀, nothing, 1e-4, false)
```
(`A = s.strategy`; `ρ_min = 1e-2`, `ρ_max = 1e4` are `solve_admm.jl:352-353` defaults; `_admm_iterate!` positional order per `solve_admm.jl:481-493` is `st, rmode, maxiter, ε_abs, ε_rel, τ, μ, ρ_min, ρ_max, time_limit_s, parallel`.) Note `@elapsed (a, b = f())` needs the destructuring parenthesized inside a block; define `local` first (research code example uses `local st`).

**Post-iterate branching** to mirror (`solve_admm.jl:495-558`): not converged and not budget -> `convergence_error` row; `st.budget_exceeded_flag` -> `budget_exceeded` row (no welfare, honest early exit); else `_admm_certify` inside `try`, and the iteration-count rewrap:
```julia
catch err
    (err isa CertificateError && err.iterations === nothing) || rethrow()
    throw(CertificateError(err.msg; kind = err.kind, iterations = residuals.iters))
end
```
In the script, catch `CertificateError` and write a `refused_certificate` row with `iterations = st.residuals.iters`; parse the gap ratio from the message BEFORE truncating (research "Hybrid ratio" snippet, regex `worst gap/\(atol_b\+rtol·\|cone\|\)=([0-9.eE+-]+)`).

**Status-row precedent** (`scripts/case_a_magnitude.jl:482-560`, `run_rung_outcome`): expected solver outcomes (`ConvergenceError`, `CertificateError`, `SolveFailedError`) become `error:<Type>` / status rows; `iters` from the error with `-1` sentinel (`hasproperty(err, :iterations) && err.iterations !== nothing ? Int(err.iterations) : -1`); `first(string(err.msg), 400)` for the message; anything else `rethrow()`:
```julia
catch err
    if err isa ConvergenceError || err isa CertificateError || err isa SolveFailedError
        iters = hasproperty(err, :iterations) && err.iterations !== nothing ? Int(err.iterations) : -1
        return (; status = "error:" * string(nameof(typeof(err))), welfare = missing, iters = iters, message = first(string(err.msg), 400))
    else
        rethrow()
    end
end
```
Status vocabulary for this script: `ok`, `refused_certificate`, `convergence_error`, `budget_exceeded`, `error:<TypeName>`, `preflight_refused`, `memory_infeasible`, `started`.

**Pre-flight gate** (new, no analog in repo; use research snippet; run it first thing after arg parsing, before `_materialize`):
```julia
function mem_available_kb(path = "/proc/meminfo")
    for line in eachline(path)
        startswith(line, "MemAvailable:") && return parse(Int, split(line)[2])
    end
    return -1
end
preflight_ok(kb, min_gib) = min_gib <= 0 || kb >= round(Int, min_gib * 1024^2)
```
Refusal writes one `preflight_refused` row and exits normally (exit 0), like the wrapper's "an OOM is a recorded outcome" stance (`scripts/run_ieee8500_point.sh:8-10`). Take `path` as an argument so the test can feed a synthetic meminfo.

**Keyed CSV upsert with schema evolution** (analogs: `benchmark_ieee8500.jl:810-829` and `profile_ieee8500_memory_attribution.jl:628-642`):
```julia
function write_rows()
    path = joinpath(out_dir(), "memory_attribution.csv")
    mkpath(out_dir())
    df = DataFrame(ROWS)
    if isfile(path)
        old = CSV.read(path, DataFrame)
        k(r) = (string(r.fixture), r.density, r.T, r.stage, r.name)
        nk = Set(k(r) for r in eachrow(df))
        df = vcat(filter(r -> !(k(r) in nk), old), df; cols = :union)
    end
    CSV.write(path, df)
    return nothing
end
```
For this script the key is `(row_kind, feeder, population, T, strategy)`. Write a `started` row before heavy work and replace it with the final row (same pattern as `benchmark_ieee8500.jl:1005-1017,1168`), so a kill leaves a trace; the profiler upserts after every report for the same reason (header lines 14-18). Wrap the upsert function so it takes `(csv_path, df_new)` for the `mktempdir()` test.

**`--record-nogo` mode:** a pure function over the committed CSVs (read with CSV.jl in the script). Inputs, with row keys:
- `memory_attribution.csv` columns `fixture,density,T,stage,name,VmRSS_kB,VmHWM_kB,gc_live_MB,rss_delta_gib,gib,tol_gib,note,anchor_status,anchor_iters,anchor_delta_gib,anchor_time_s`; filter `fixture == "ieee8500" && density == 0.1 && T == 24`; peak = `maximum(VmHWM_kB)` (expected 11,753,716); components from `(9, "reconciliation:comp_agr_builds")` (4.569), `comp_dso_build` (0.851); anchor row `(1, "anchor_after")` for delta 9.2955, iters 7, ratio 223.68.
- `point_resources.csv` header `run_label,rc,peak_rss_kb,oom_source,mem_avail_before_mb,swap_used_before_mb,other_julia_procs,started_at,args` (the `args` column is quoted); rows `p35-head-d0.1-T24` (12,079,316 kB) and `p35-head-d0.25-T24` (12,636,180, rc 143, earlyoom). CSV.jl handles the quoting.
Emit `row_kind = recorded_no_go`, `status = memory_infeasible`, raw kB and binary GiB side by side, B1 (measured bound) and B2 labelled `estimate` (research Q4). Do not hand-type any derived number.

---

### `results/ieee8500_benchmark/scenario_table.csv` (new; data artifact)

**Analogs:** `memory_attribution.csv` (kB raw beside binary GiB: `VmRSS_kB,VmHWM_kB,...,gib`; keyed rows; free-text `note` column) and `point_resources.csv` (join key `run_label`; `mem_avail_before_mb`, `oom_source`, `started_at`).

Column conventions to copy: raw kB column plus `*_gib` computed as kB/1024^2; seconds columns suffixed `_s` (`anchor_time_s`, `admm_time_s`); `status` as a single token; free text last (`note`, `message`) so a `limit = ncols` Base-split works in the docs page. Planned columns (minimum): `row_kind,feeder,population,T,strategy,seed,sub_seed_population,status,n_buses,n_branches,n_load_buses,n_aggregators,n_cap_aggregators,dso_vars,dso_cons,agr_vars,agr_cons,materialize_s,build_s,solve_s,certify_s,iters,gap_ratio,vmhwm_kb,vmhwm_gib,maxrss_gib,mem_avail_before_kb,heap_size_hint,julia_version,git_head,threads,run_label,note`. Two row kinds: `measured` (T = 10) and `recorded_no_go` (T = 24). Rows come from `--record-nogo` and the orchestrator's detached run; executors commit only the `recorded_no_go` row and never launch the 8500 run.

---

### `test/test_ieee8500_scenario.jl` (new; test)

**Style analogs:** `@testitem` conventions in `test/test_experiments.jl:23,53,78` (untagged = fast lane; `tags = [:slow]` for heavy); `test/test_flex_population.jl:12-20` for population fences; `test/test_strategies.jl:90-120` for selector/`fieldnames` assertions.

**Safe script include inside a `@testitem`** (analog `test/test_case_a_magnitude.jl:517-518`):
```julia
using TSODSO
include(joinpath(@__DIR__, "..", "scripts", "case_a_magnitude.jl"))
```
Same form for the new script: `include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))`. This works because the gate is `abspath(PROGRAM_FILE) == @__FILE__` and the test env carries `CSV`, `DataFrames`, `DrWatson`, `StableRNGs` (`test/Project.toml` lines 4-13). For the harness-equivalence check, `include(.../benchmark_ieee8500.jl)` is not done in any existing test (`test_benchmark_ieee8500.jl:60` states it is never included in-process, only the profiler script includes it), so replicate the harness rule inline in the test (the ~8 lines of `sample_density_buses` + filter, copied from `benchmark_ieee8500.jl:252-277`) or include the harness only if it loads cleanly in the test env; prefer the inline copy.

**Items** (from research Q6, exactly seven):
1. Widened construction (`ieee8500`, `ieee8500_mv` construct; `:ieee13` defaults unchanged; tuple contains four symbols; `:bogus`/`:ieee14` still throw).
2. Guards: each `@test_throws ArgumentError` (`:default_10pct` on 13/123; `:case_a_784` on 8500; `pf = :ac` on 8500; `MPC()`/`Stochastic()` on 8500).
3. Materialization without solve: `TSODSO._materialize(Scenario(...))` gives 4,866 buses, 122 aggregators with exactly 4 capacitor aggregators (118 / 4 for mv), deterministic, differs across seeds.
4. Equal-seed equivalence with the harness sampling rule.
5. Default fence (structural facts only; the bit-level fence is in `test_flex_population.jl`).
6. Script helpers: NO-GO derivation (`vmhwm_kb == 11_753_716`, `vmhwm_gib ≈ 11.209`, `p35_maxrss_kb == 12_079_316`, delta ≈ 9.2955, iters 7, ratio ≈ 223.68, status `memory_infeasible`), pre-flight parsing with a synthetic meminfo (`MemAvailable: 4324172 kB` refused at 8, passes at 0), keyed upsert in `mktempdir()`.
7. IEEE-13 phase-composition parity vs `TSODSO.run_scenario` (`Scenario(name, feeder=:ieee13, strategy=ADMM(), T=10, seed=3)`, compare `iters`, welfare, `exact_maxgap`, `dadp` with `==`).

**Hygiene (project memory):** no `try x = ...` and no outer-variable reassignment in a top-level `for` inside a `@testitem` (wrap in a function or `let`; see the soft-scope rule noted at `test_flex_population.jl:~10`). Never run the full 8500 point. Scratch `.jl` stays outside the repo (TestItemRunner scans it). No `@test_broken` (`test/expected_broken.txt` guard).

### `test/test_flex_population.jl` (edit, line 20)

Current line 20, the only existing-test edit:
```julia
    @test TSODSO.SCENARIO_VALID_POPULATIONS == (:default, :case_a_784)
```
becomes `(:default, :case_a_784, :default_10pct)` (order must match the tuple in Scenario.jl). The item title says "byte-identity fence"; leave the title (and the `byte-identical` wording, already counted in the baseline) untouched.

---

### `docs/literate/ieee8500_scaling.jl` (append dated section)

**Analog:** the existing appended section "Memory attribution of the `solve_admm` loop" (starts line ~406, header `# ## ...` then `# *(Appended 2026-10-24. ...)*`, a `# **Units.**` paragraph, `# **Method.**`, a closing `# **Reproducing this ...**` with a fenced command block). Copy that structure for "## Headline measurement and go/no-go" `*(Appended 2026-11-05 ...)*`. Append only; never edit earlier prose, state supersessions in the new section (the old "NOT ESTABLISHED"/"earlyoom-killed" statements, 4.024 vs 4.569 GiB, "11.75 GiB" vs 11.209 GiB, 4,875 vs 4,866 buses).

**CSV reading with Base only** (docs env has no CSV/DataFrames; copy `read_sweep_csv`, lines 135-160):
```julia
lines = readlines(path)
header = split(first(lines), ',')
idx = Dict(strip(h) => i for (i, h) in enumerate(header))
ncols = length(header)
num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
return map(lines[2:end]) do ln
    f = split(ln, ','; limit = ncols)
    (; fixture = strip(f[idx["fixture"]]), density = num(f[idx["density"]]), ...)
end
```
Path expression: `joinpath(pkgdir(TSODSO), "results", "ieee8500_benchmark", "<file>.csv")` (line 163-165). The `point_resources.csv` `args` column is quoted and `limit = ncols` keeps it in the last field, which is what the split above relies on; keep free-text columns last in `scenario_table.csv` for the same reason. Compute every number from the rows (kB -> binary GiB); `println` them as the existing section does.

**Planning-ID guard for the new prose:** avoid `Phase NN`, `SCALE-0x`, `REQ-`, `byte-identical` (write `bit-identical`), `RESEARCH`, `CONTEXT.md`, `.planning/`, `wave`, `Task N`, `Pitfall N`, `D-NN` (patterns in `.github/scripts/planning_id_rules.py:12-48`). Refer to "the earlier attribution run" and to CSV row keys. Formatter: `docs` is in the CI formatter scope.

No `docs/make.jl` edit (page registered at `docs/make.jl:44` and `:112`). Executing the page adds under a second to the ~6.8 min build.

### `scripts/README.md` (one row)

**Analog rows** (table `## Scripts`, columns `Script | Purpose | How to run | Outputs | Status`):
```
| `benchmark_ieee8500.jl` | IEEE-8500-scale benchmark harness: noise-floor calibration and density sweep | `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500-mv` (see header for the sweep mode) | CSVs under `results/ieee8500_benchmark/` | Maintained; long-running |
| `run_ieee8500_point.sh` | Per-process wrapper for one IEEE-8500 point: records peak RSS, free memory and OOM evidence | `scripts/run_ieee8500_point.sh <label> -- <benchmark args...>` | One row in `results/ieee8500_benchmark/point_resources.csv` | Maintained |
```
Insert alphabetically between `benchmark_ieee8500.jl`/`benders_toy.jl` and the `profile_*` rows (the table is alphabetical: `i` goes after `benders_toy.jl`, before `profile_ieee8500_memory.jl`). The script path must appear as a backticked whole-path token `` `ieee8500_scenario_point.jl` `` (checker `.github/scripts/check_scripts_index.py` requires every tracked file under `scripts/`; tokens under `results/` are ignored). Suggested "How to run": `JULIA_HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>`; mention `--record-nogo`. Keep prose free of planning IDs (README.md is in the guard scope, currently 5 existing hits; do not touch them).

### `docs/src/api.md`

No edit. `docs/src/api.md:188` autodocs `experiments/Scenario.jl`; no new exported or documented symbol (`test/test_exports.jl:37` curated list unchanged). The `:default_10pct` documentation lives in the `Scenario`/`build_population` docstrings.

---

## Shared Patterns

### Honesty policy (refusals are rows)
**Source:** `scripts/case_a_magnitude.jl:482-560`; `scripts/benchmark_ieee8500.jl` `ERROR:CertificateError` rows (research Q1b #10).
**Apply to:** the new script and the docs section. Certificates report, expected solver outcomes are status rows, anything else propagates. No tolerance, tau, epsilon or hybrid floor is changed (`git diff` over `src/admm`, `src/models/exactness.jl`, the solver factory must be empty).

### Binary units
**Source:** `profile_ieee8500_memory_attribution.jl` header (last paragraph): "All memory figures are binary GiB (1 GiB = 2^30 bytes); `VmRSS_kB`/`VmHWM_kB` are the raw KiB counters, kept beside the GiB conversions".
**Apply to:** script rows, docs, tests. 11,753,716 kB = 11.209 GiB, 12,079,316 kB = 11.520 GiB.

### Wrapper-run provenance
**Source:** `scripts/run_ieee8500_point.sh:1-94`. Usage `scripts/run_ieee8500_point.sh <label> -- <args...>`, `SCRIPT=` env selects the script (line 23); it adds `--run-label` only for `benchmark_ieee8500.jl` (lines 33-36), so pass `--run-label <label>` explicitly for the new script; it always exits 0 and appends a `point_resources.csv` row; label must match `[A-Za-z0-9._-]+`. No wrapper edit. Heap hint via `JULIA_HEAP_SIZE_HINT` env, recorded in the row. The orchestrator launches the run (detached, alone, `pgrep -x julia` empty, MemAvailable >= 8 GiB); executors do not.

### Selector/error style
**Source:** `Scenario.jl:134-212` (`ArgumentError`, messages prefixed `Scenario:`, `repr(sym)`, `expected one of $(TUPLE)`); `materialize.jl:1041-1049` (`build_population(:sel): ...` prefix).

## No Analog Found

| File / piece | Role | Data Flow | Reason |
|--------------|------|-----------|--------|
| Pre-flight `/proc/meminfo` MemAvailable gate | utility | file-I/O | No existing script reads `/proc/meminfo`; the wrapper reads `free -m` in shell. Use the research snippet. |
| `--record-nogo` derivation (B1/B2) | utility | transform | No existing script derives a verdict from committed CSVs; follow the research Q4 bound/estimate separation. |
| Per-phase timing of `_admm_*` in one script | script | batch | Only the profiler calls the phases, with GC staging; this script is the first to time build/iterate/certify separately without the staged GC (so it must not add `GC.gc()` between phases, to keep peak comparable). |

## Repo Gates the Executor Must Pass

| Gate | Command | Requirement |
|------|---------|-------------|
| Planning-ID guard | `python3 .github/scripts/check_planning_ids.py` | Baseline verified at map time: `FAIL: 355 hit(s), 0 stale allowlist entr(y/ies)`. Must stay exactly 355 (new `src`, `test`, `scripts`, `docs/literate` text adds zero hits; scope in `.github/scripts/planning_id_rules.py:80-86`; `.planning/` excluded). Do not "fix" existing hits (`ieee8500_scaling.jl` 18, `materialize.jl` 12, profiler 12, `test_flex_population.jl` 7, `scripts/README.md` 5). |
| Scripts index | `python3 .github/scripts/check_scripts_index.py` | README row for `ieee8500_scenario_point.jl`. |
| Script API lint | `julia --project=. --startup-file=no .github/scripts/check_script_api.jl` | New script qualifies unexported names (`TSODSO._...`) or imports them explicitly. |
| Formatter | `julia --startup-file=no .github/scripts/format210.jl src ext test docs` | JuliaFormatter 2.10.x (never 2.12.x), repo `.JuliaFormatter.toml`. CI format job (`.github/workflows/CI.yml:100-130`) covers `src ext test docs`; `scripts/` is NOT formatted, but keep it tidy. Run it on the touched files only and commit the formatted result. |
| Content loss | `python3 .github/scripts/check_content_loss.py HEAD` | Run after formatting; compares `.jl` under `src ext test docs` to HEAD ignoring whitespace/commas; new files skipped; a docstring damaged by the formatter (for example a `|`-continued inline code span in a docstring table) is flagged. Run it BEFORE committing the formatted edits (it diffs against HEAD). |
| `@testitem` setup names | `python3 .github/scripts/check_setup_names.py` | Only if `setup = [...]` is used (not needed). |
| JET ratchet | `julia --project=. --startup-file=no -t2 scripts/jet_check.jl` | Baseline 20 signatures in `scripts/jet_baseline.txt`; expect 0 new, 0 fixed. Only new `src/` code is one branch; keep it type-simple. |
| Quick tests | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl,test_flex_population.jl,test_strategies.jl,test_experiments.jl,test_exports.jl,test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` | Then `git checkout -- test/Project.toml test/Manifest.toml` (Pkg.test rewrites them). Canary stays 56 iterations / -4823.66604824162. |
| Docs build | `julia --project=docs docs/make.jl` | Appended section only; page already registered. |
| Full suite | detached and alone (`.github/scripts/suite_detached.sh` + `check_suite_log.py`) | Recorded baseline 35194/0/0/7 plus the new items; no `@test_broken`. |

## Metadata

**Analog search scope:** `src/experiments/`, `src/admm/`, `scripts/`, `test/`, `docs/literate/`, `results/ieee8500_benchmark/`, `.github/scripts/`, `.github/workflows/CI.yml`
**Files read for excerpts:** Scenario.jl, materialize.jl (1005-1170, 15-30, 190-205, 1264-1306), run.jl (55-150), solve_admm.jl (440-558), benchmark_ieee8500.jl (240-285, 776-783, 805-832, 860-930, 1370-1381), profile_ieee8500_memory_attribution.jl (1-100, 150-165, 225-300, 600-650), case_a_magnitude.jl (440-560), run_ieee8500_point.sh, test_case_a_magnitude.jl (505-530), test_flex_population.jl (1-26), ieee8500_scaling.jl (135-165, 400-end), scripts/README.md rows, CSV headers
**Pattern extraction date:** 2026-11-05
