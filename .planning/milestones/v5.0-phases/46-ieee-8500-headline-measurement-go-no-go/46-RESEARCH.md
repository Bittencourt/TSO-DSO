# Phase 46: IEEE-8500 Headline Measurement (go/no-go) - Research

**Researched:** 2026-11-05
**Domain:** Julia research bench (JuMP/Clarabel ADMM); declarative `Scenario` seam; per-process memory measurement harness; committed-CSV + Literate documentation
**Confidence:** HIGH on code seams, CSV numbers and repo gates (all read or run in this session); MEDIUM on host-dependent run behaviour (heap hint, runtime)

## User Constraints (from CONTEXT.md)

<user_constraints>

### Locked Decisions

(Copied verbatim from `46-CONTEXT.md` `## Implementation Decisions`.)

**Go/no-go (SCALE-07): NO-GO from data**
- The **headline point** is the one the milestone research named: `:ieee8500` (4,875 buses, full
  MV+LV), ADMM-only, density 0.1, T = 24.
- The decision is made **from the committed Phase-39 attribution**
  (`results/ieee8500_benchmark/memory_attribution.csv`, `point_resources.csv`). It is not re-run
  and not re-engineered:
  - T = 24 peak HWM was 11.75 GiB, above the ~10 GiB GO threshold on the 15 GB host.
  - Anchor delta was 9.296 GiB at 7 iterations, ending in `CertificateError`, SOCP gap ratio 223.7.
  - The components: 122 AgrOpt builds ≈ 4.0 GiB, DSO build ≈ 0.9 GiB, first iterate retained
    ≈ 2.9 GiB, iterates 2..N ≈ 0.65 GiB.
  - Phase 35 measured an earlier peak of 11.52 GiB, and d = 0.25 T = 24 was earlyoom-killed.
- Record **"memory-infeasible on this host"** with a **lower-bounded requirement**, derived only
  from measured numbers: peak ≥ the measured HWM, plus the stated headroom the host needs for
  the OS and baseline load. The derivation is shown, and every number cites its CSV row. No
  lever is claimed to exist.
- The decision record is a committed, dated artifact: a CSV row and/or a markdown/literate
  section next to the existing `docs/literate/ieee8500_scaling.jl`. It states the threshold, the
  measured value, the verdict and the lower bound.

**Measured run (SCALE-08): widen `Scenario` and run the feasible point**
- **Widen `SCENARIO_VALID_FEEDERS`** additively from `(:ieee13, :ieee123)` to include `:ieee8500`
  and `:ieee8500_mv` (`src/experiments/Scenario.jl:24`). `build_feeder` in `materialize.jl`
  already dispatches both.
  - The default `Scenario` and every existing selector behave identically.
  - Check the population, price and pf selector compatibility for 8500, including how
    `materialize` builds the 8500 population and density. Any combination 8500 cannot support
    gets an `ArgumentError` guard, not silent behaviour.
- **Run the largest memory-feasible point through `Scenario`/`run_scenario`**: `:ieee8500`,
  ADMM-only, d = 0.1, T = 10 (Phase 39 measured ~5.7–6.2 GiB peak). Commit the six-number table:
  size (buses, branches, houses or aggregators, variables/constraints if cheap), build time,
  solve time, iterations, peak memory (VmHWM/MaxRSS), and the exactness verdict.
  - "Refused with certificate" is the expected and accepted verdict. Phase 35/39 saw a
    `CertificateError` at T = 10, ratio ~569.
- The table also carries the **T = 24 NO-GO row**: status `memory_infeasible`, citing the
  measured peak, with no new run.
- If the `Scenario` path materially differs from the benchmark-harness path, the table states
  it, for example in population construction or default knobs. Any number that is compared with
  the Phase-35/39 harness numbers is labelled as coming from the different path.

**Host-memory hygiene for the run**
- The run is **detached and alone**, launched by the orchestrator, never by an executor. It
  uses the existing per-point wrapper pattern (`scripts/run_ieee8500_point.sh`) or an
  equivalent: `--heap-size-hint`, earlyoom awareness, and MaxRSS/oom_source/mem_avail_before
  recording, following the `point_resources.csv` conventions.
- A **pre-flight gate** requires at least 8 GiB of `MemAvailable` before launch. If it fails, or
  earlyoom kills the run, the outcome is recorded as a measured row (MaxRSS, oom_source, mem
  available before). Nothing is ever retuned to make it fit.
- Tests are tiny. The `Scenario` widening is tested on construction/validation and, if
  feasible, on a small 8500-family slice. **No test runs the full 8500 point.** The full suite
  must stay at about its current wall time.

### Claude's Discretion
- Script layout: extend `scripts/benchmark_ieee8500.jl` with a scenario mode, or add a small
  dedicated script. The CSV name and columns follow the established
  `results/ieee8500_benchmark/` conventions. The docs placement is an additive, dated section in
  `docs/literate/ieee8500_scaling.jl` or a new registered page.

### Deferred Ideas (OUT OF SCOPE)
- Memory levers for a future T = 24 GO: `HourSplitDsoOpt`, a per-hour solver-state pool,
  names off, an AgrOpt pool.
- A bigger-RAM host run of the d = 0.1 T = 24 headline.
- An SCS/first-order diagnostic at the headline point (still untested there).

Phase boundary reminders from CONTEXT: out of scope are memory re-engineering of the ADMM path,
runs on a bigger machine, convergence/exactness fixes at 8500 scale, and new densities or horizons
beyond the named points. The phase is additive; the knife-edge canary (56 iterations /
-4823.66604824162) and every golden stay byte-identical.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCALE-07 | Go/no-go recorded: GO only if attribution projects peak < ~10 GiB on the 15 GB host, otherwise "memory-infeasible on this host" with a lower-bounded requirement | Section "NO-GO record" (exact CSV rows, binary-GiB conversion, bound-vs-estimate derivation). Found a units error in the CONTEXT figure "11.75 GiB" (it is 11.21 GiB; verdict unchanged). |
| SCALE-08 | Headline point run through `Scenario` (feeder selector widened additively) and reported as a measured table: size, build time, solve time, iterations, peak memory, exactness verdict; a refusal counts as measured | Sections "Scenario widening", "Scenario path vs harness path divergences", "Recommended script design", "Size reporting". Density is NOT expressible in `Scenario` today; a population selector is the minimal additive change. |

</phase_requirements>

## Project Constraints (from ./CLAUDE.md)

- Julia + JuMP; solvers open-source first (Clarabel for the SOCP/QP core, HiGHS for LP/MILP). No solver is hard-coded in a model. This phase adds no solver code.
- Correctness and reproducibility first: seeded data, pinned environment; SOCP exactness is never loosened (SC3: no tolerance, tau, epsilon or hybrid floor changes).
- Documentation is a hard requirement: every modelling decision documented; literate pages compute numbers from committed CSVs.
- Clean idiomatic Julia; `ArgumentError` (never `@assert`) for construction invariants; `@testitem` conventions (no `try x = ...`, no outer reassignment in `for`, see memory notes).
- GSD workflow: edits go through GSD commands (this research writes only a planning file).
- `.github/scripts/check_planning_ids.py` must not gain hits (current baseline: 355 hits, see Repo gates).
- Memory notes that bind this phase: the host's earlyoom config prefers killing `julia`; run detached and alone; Julia 1.12.5 pinned for numerics (a 1.12.7 numerical difference is recorded for `td6node`, and `sub_seed` uses `Base.hash`); `Pkg.test()` rewrites `test/Project.toml` and `test/Manifest.toml` (restore with `git checkout -- test/Project.toml test/Manifest.toml`); keep scratch `.jl` files outside the repo (TestItemRunner scans them).

## Summary

The phase has two deliverables, and the first needs no new run. SCALE-07 is a recorded NO-GO derived from rows already committed in `memory_attribution.csv` and `point_resources.csv`. The T = 24 headline (`:ieee8500`, d = 0.1, ADMM-only) peaked at VmHWM 11,753,716 kB, which is **11.209 GiB in binary units** (11.754 in kB/10^6). The CONTEXT, the Phase-39 UAT note and the verification note all write this as "11.75 GiB". That is a units slip. The verdict is unchanged because 11.21 GiB and the independent Phase-35 MaxRSS of 11.52 GiB (12,079,316 kB) both exceed the ~10 GiB GO threshold. The decision artifact must carry raw kB beside the binary GiB. It must also state that this point **did complete twice on this host** (Phase 35 and the 2026-10-27 UAT run). The NO-GO is therefore a threshold verdict, not a proof that the point cannot run. The only measured kill is d = 0.25 (earlyoom, MaxRSS 12.05 GiB).

SCALE-08 needs one real design choice. `Scenario` has **no density field**, `build_population(:default, ...)` at 8500 builds every load bus (1,177 SX loads plus 4 capacitor aggregators = 1,181 aggregators, density 1.0, which OOM-killed in Phase 25), and the harness reaches d = 0.1 through a script-private `density_filtered_population`. Adding a field to `Scenario` would break `test_strategies.jl:108` (exact `fieldnames` assertion) and alter `savename`/filename identity. The minimal additive change is therefore one new population selector (recommended name `:default_10pct`) defined for the two 8500 feeders only, plus widening `SCENARIO_VALID_FEEDERS`. It needs a one-line edit of `test_flex_population.jl:20` (an exact-tuple assertion on `SCENARIO_VALID_POPULATIONS`). Even then the `Scenario` path **cannot reproduce the harness's numbers**: per-house profile seeds and the bus sample come from `sub_seed(s.seed, :population)` instead of the harness's literal 20260821. The table must label it "same size and structure, different draws".

The measured run should be driven by a small dedicated script that materializes through `Scenario`/`TSODSO._materialize`/`build_powerflow` and then calls the ADMM phase functions (`_admm_build`, `_admm_iterate!`, `_admm_certify`) one by one. That is the only way to time build and solve separately and to read JuMP variable/constraint counts for free, because `run_scenario` returns only total `elapsed`. A parity test on IEEE-13 (2.5 s warm) pins the script's phase composition to `run_scenario`. The wrapper `scripts/run_ieee8500_point.sh` needs no edit: pass `--run-label` explicitly and set `JULIA_HEAP_SIZE_HINT` in the environment (an official Julia env var, no wrapper change).

**Primary recommendation:** (1) widen the feeder tuple, add the `:default_10pct` population selector with four `ArgumentError` guards, test construction and 8500 materialization only; (2) add `scripts/ieee8500_scenario_point.jl` (status rows, never throws on solver outcomes, MemAvailable >= 8 GiB pre-flight, keyed upsert into `results/ieee8500_benchmark/scenario_table.csv`) with a `--record-nogo` mode that computes the T = 24 row from the committed CSVs; (3) append a dated section to `docs/literate/ieee8500_scaling.jl` that recomputes every number from the CSVs with `Base` only.

## Architectural Responsibility Map

This is a single-process research bench (no browser/server tiers). The tiers below are the repo's layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Feeder selector validation + density-sampled population selector | `src/experiments` (`Scenario.jl`, `materialize.jl`) | — | Declarative selectors live in the `Scenario` seam; heavy objects are rebuilt in `materialize.jl` |
| ADMM execution and exactness certificate | `src/admm` (`solve_admm`, `_admm_*` phases) | — | Unchanged; phase functions already exist and are used by the profiler script |
| Build/solve timing, sizes, VmHWM, status rows | `scripts/` (new dedicated script) | `src/` untouched | Measurement is not a framework capability (same stance as `benchmark_ieee8500.jl` header); keeps `src/` additive |
| Per-process peak RSS, oom_source, mem_avail_before | `scripts/run_ieee8500_point.sh` | shell/OS (`/usr/bin/time`, `journalctl`) | Only an external process can see MaxRSS and the killer's log |
| Pre-flight MemAvailable gate and refused-row | `scripts/` Julia script | wrapper (records its own `mem_avail_before_mb`) | One place writes status rows; wrapper stays unchanged |
| NO-GO derivation | `scripts/` (`--record-nogo`) + literate page | committed CSVs | Numbers computed from CSV rows, not retyped |
| Documentation | `docs/literate/ieee8500_scaling.jl` (appended section) | `scripts/README.md` | Established pattern; page already registered in `docs/make.jl:44,112` |

## Standard Stack

No new libraries. Everything required is already a hard dependency or a stdlib. `[VERIFIED: Project.toml]`

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| TSODSO (this repo) | HEAD f9f6ccb | `Scenario`, `_materialize`, `build_powerflow`, `_admm_build/_iterate!/_certify` | The seam under test |
| JuMP | 1.30.1 (compat in `Project.toml`) | `num_variables`, `num_constraints` on the already-built models | O(1)/O(types) counts, no extra memory |
| StableRNGs | 1.0.4 | `LehmerRNG` + `StableRNGs.Random.randperm` for the density sample (same rule as the harness `sample_density_buses`, `scripts/benchmark_ieee8500.jl:252-257`) | Already used by `src/data/profiles.jl`; stable across Julia versions |
| CSV.jl, DataFrames.jl | 0.10.16 / 1.8.2 | Scripts only (committed CSV upsert, same as `benchmark_ieee8500.jl` and the profiler) | Existing convention |
| Julia | 1.12.5 (pinned for the run) | Runtime | Phase-39 runs used 1.12.5; `sub_seed` is `Base.hash`-derived |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `/usr/bin/time -v`, `journalctl`, `free -m`, `pgrep` | system (present) | Wrapper evidence | Already used by `run_ieee8500_point.sh` |
| `JULIA_HEAP_SIZE_HINT` env var | Julia 1.12 | Equivalent of `--heap-size-hint` | Orchestrator sets it; the script records it `[CITED: docs.julialang.org/en/v1/manual/environment-variables]` |
| docs environment | `docs/Project.toml` | Page build | No CSV/DataFrames in docs env: parse CSV with `Base` only (see `read_sweep_csv`, `docs/literate/ieee8500_scaling.jl:140-160`) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New population selector `:default_10pct` | New `Scenario` field `density` | Breaks `test_strategies.jl:108-120` `fieldnames` assertion; changes `==`/`hash`/`scenario_filename` identity; larger blast radius against "byte-identical" |
| Dedicated script | New mode in `benchmark_ieee8500.jl` (1,381 lines, three modes, `density_sweep.csv` schema keyed on `(fixture, density, solver, T_horizon)`) | Harness rows are keyed by `density`, and the Scenario-path row needs different keys/columns; mixing would blur the harness/Scenario provenance the CONTEXT requires to be labelled |
| Phase-function composition | `TSODSO.run_scenario(s)` literally | `run_scenario` returns only total `elapsed` and throws on `CertificateError`; no build/solve split, no model sizes. Fallback only if the planner rejects internals (then report `materialize_s` + total) |

**Installation:** none. **Version verification:** versions read from `Project.toml` compat lines and the project STACK table; no registry install is performed.

## Package Legitimacy Audit

No external packages are added or installed by this phase. `slopcheck` not run (nothing to check).

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — | — | — | — | — | n/a | none added |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                        (SCALE-07: no run)                        (SCALE-08: one detached run)
 memory_attribution.csv ─┐                         orchestrator: pgrep julia == 0, nothing else running
 point_resources.csv ────┼─► --record-nogo ─┐          │  JULIA_HEAP_SIZE_HINT=8G  SCRIPT=scripts/ieee8500_scenario_point.jl
 (committed rows)        │   (pure function)│          ▼
                         │                  │   scripts/run_ieee8500_point.sh <label> -- ... --run-label <label>
                         │                  │          │  free -m → mem_avail_before_mb ; /usr/bin/time -v → MaxRSS
                         │                  │          ▼
                         │                  │   julia scripts/ieee8500_scenario_point.jl
                         │                  │     1. MemAvailable (/proc/meminfo) >= 8 GiB ? ── no ─► row status=preflight_refused ─► exit 0
                         │                  │     2. s = Scenario(feeder=:ieee8500, population=:default_10pct, strategy=ADMM(), T=10)
                         │                  │     3. upsert row status=started   (a kill leaves a trace)
                         │                  │     4. t_mat   = @elapsed TSODSO._materialize(s)   (feeder, λ₀, 122 aggregators)
                         │                  │        pf      = TSODSO.build_powerflow(s)
                         │                  │     5. t_build = @elapsed _admm_build(...)         → counts: DSO + Σ AgrOpt
                         │                  │     6. t_solve = @elapsed _admm_iterate!(...)      → iterations, converged?
                         │                  │     7. t_cert  = @elapsed _admm_certify(...)       → certified | CertificateError(ratio)
                         │                  │     8. VmHWM, Sys.maxrss(); upsert final row
                         │                  ▼
                         └────────► results/ieee8500_benchmark/scenario_table.csv  (keyed upsert)
                                              │            ▲
                                              ▼            └── point_resources.csv (wrapper row, joined by label)
                              docs/literate/ieee8500_scaling.jl  (appended dated section, Base-only CSV read, all numbers computed)
```

### Recommended Project Structure
```
src/experiments/Scenario.jl      # widen SCENARIO_VALID_FEEDERS, SCENARIO_VALID_POPULATIONS; 4 guards; docstring
src/experiments/materialize.jl   # one new branch in _build_population_core (+ a tiny sampler helper)
scripts/ieee8500_scenario_point.jl   # new, include-safe (main only when entry point), status rows
scripts/README.md                # one new row in `## Scripts` (check_scripts_index.py)
results/ieee8500_benchmark/scenario_table.csv   # committed measurement + NO-GO rows
results/ieee8500_benchmark/runs/<label>.*       # wrapper evidence for the one run
docs/literate/ieee8500_scaling.jl               # appended dated section
test/test_ieee8500_scenario.jl                  # tiny @testitems (construction, materialize, NO-GO derivation, parity)
test/test_flex_population.jl                    # one-line edit: line 20 tuple
```

### Pattern 1: Widen selectors additively
**What:** extend the two curated tuples and add construction-time guards in the inner constructor next to the other `ArgumentError`s (`src/experiments/Scenario.jl:134-212`). Defaults, `==`, `hash` and `scenario_filename` are untouched (no struct change).
**Guards to add** (all `ArgumentError`, placed after the selector-membership checks at `Scenario.jl:134-157`):
1. `population === :default_10pct` with `feeder ∉ (:ieee8500, :ieee8500_mv)`: the sampler is defined for the 8500 fixtures (cannot-support).
2. `population === :case_a_784` with `feeder ∈ (:ieee8500, :ieee8500_mv)`: `_build_population_core` already throws at materialization (`materialize.jl:1041-1049`); fail at construction instead, only for the *new* feeder values so legacy `:ieee123 + :case_a_784` behaviour is untouched.
3. `feeder ∈ 8500 family` with `pf === :ac`: unmeasured at this scale (`build_powerflow` docstring, `materialize.jl:1303-1304`: "only `:ieee13` has been measured") [ASSUMED: guard preferred over doc-only, see A3].
4. `feeder ∈ 8500 family` with strategy `MPC` or `Stochastic`: unmeasured and would silently launch many 8500-scale solves [ASSUMED, see A3].
`population = :default` at 8500 stays allowed (it is density 1.0, 1,181 aggregators, measured OOM) and is documented, not guarded: a bigger host may run it legitimately. A `T < 9` check is not needed: the `Deferrable` energy-budget guard already throws `ArgumentError` at materialization (verified: `T = 8` throws, `T = 9` builds; harness floor is 10, `benchmark_ieee8500.jl:774`).

### Pattern 2: Population selector reproducing the harness sampling rule
**What:** `:default_10pct` = the `:default` 8500 population (unchanged builder) filtered to a seeded 10% bus sample plus the 4 capacitor aggregators, using the exact harness rule so selection is bitwise the harness's *given the same seed*.
```julia
# src/experiments/materialize.jl, a new branch in _build_population_core
# placed before the `elseif sym !== :default` guard (line 1087). Source rule:
# scripts/benchmark_ieee8500.jl:252-277 (sample_density_buses, density_filtered_population).
elseif sym === :default_10pct
    feeder_sym in (:ieee8500, :ieee8500_mv) || throw(ArgumentError("..."))
    full  = _build_population_core(:default, feeder, feeder_sym, profiles, seed, sel)
    buses = _load_buses(feeder, feeder_sym)
    n     = clamp(round(Int, 0.1 * length(buses)), 1, length(buses))
    perm  = StableRNGs.Random.randperm(StableRNGs.LehmerRNG(seed), length(buses))
    keep  = Set(sort(buses[perm[1:n]]))
    return filter(a -> a.bus in keep || any(d -> d isa FixedCapacitor, a.devices), full)
```
Build-full-then-filter is deliberate: it leaves the existing `:default` branch byte-identical and costs ~2.8 s (measured: full 8500 population 2.77 s, 1,181 aggregators, process VmHWM 0.83 GiB). Measured sizes: `:ieee8500` 1,177 load buses -> `round(117.7) = 118` + 4 capacitors = **122 aggregators** (matches the "122 models" in `memory_attribution.csv`); `:ieee8500_mv` 1,138 load buses -> 114 + 4 = 118 (matches "118 models").
`flex_devices` composes unchanged (`build_population` public wrapper, `materialize.jl:1011-1031`, treats any non-`:case_a_784` selector as per-bus aggregators and skips pure-capacitor ones).

### Pattern 3: Measurement script with status rows (precedent: `scripts/case_a_magnitude.jl`)
`run_rung_outcome` (`case_a_magnitude.jl:482`) records `ConvergenceError`/`CertificateError`/`SolveFailedError` as `error:<Type>` rows (iterations from the error, -1 sentinel) and lets anything else (misuse, a bug) propagate. Mirror that: refusals are rows, bugs are not swallowed. A whole-process kill is recorded by the wrapper (`oom_source`).

### Anti-Patterns to Avoid
- **Comparing the Scenario-path numbers to Phase-35/39 numbers without a label.** Different draws (see divergences).
- **Calling `run_scenario` and treating its throw as a script failure.** `run(::ADMM)` lets `CertificateError` propagate (`run.jl:116-150`), so a refused point yields no result object.
- **Rebuilding JuMP models to count variables.** Read `num_variables(st.dso.model)` and each `st.agr_by_bus[b].model` after `_admm_build`; the models already exist.
- **Re-running the T = 24 point "to double-check".** CONTEXT: no new run; the host has ~4 GiB available now.
- **Editing prose in older docs sections.** Append-only; supersede by stating the correction in the new dated section.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-point peak RSS / OOM attribution | A second RSS/OOM recorder | `scripts/run_ieee8500_point.sh` unchanged | Already attributes oom_source by child PID and records `mem_avail_before_mb`, `swap_used_before_mb`, `other_julia_procs` |
| Heap-size hint plumbing | A wrapper flag | `JULIA_HEAP_SIZE_HINT` env var (inherited by the exec'd julia, `run_ieee8500_point.sh:47-50`) | Official Julia mechanism; the script only records `ENV["JULIA_HEAP_SIZE_HINT"]` |
| VmHWM reading | New parser | Copy `proc_status_kb` from `profile_ieee8500_memory_attribution.jl:70-75` | Same `/proc/self/status` source as the committed attribution rows |
| Keyed CSV upsert with schema evolution | New logic | `vcat(filter(r -> !(key in new), old), new; cols = :union)` as in `upsert_sweep_rows` (`benchmark_ieee8500.jl:810-829`) | Proven; tolerates older column sets |
| Density sampling rule | A different sampler | The harness rule (`randperm` on a `LehmerRNG`, sorted, capacitors always kept) | A different rule would make the Scenario selector incomparable even at equal seed |
| ADMM phases | A re-derived loop | `TSODSO._admm_build`, `_admm_iterate!`, `_admm_certify` as `solve_admm` calls them (`solve_admm.jl:455-558`) | Already used verbatim by the profiler (`profile_ieee8500_memory_attribution.jl:233-298`) |
| Docs CSV reading | CSV.jl in docs | `Base` parsing (`read_sweep_csv` pattern) | docs env deliberately minimal; adding deps forces `docs/Manifest.toml` re-resolve |

**Key insight:** every piece of this phase already exists as a seam. The phase is wiring, labelling and honest recording; any new numerical logic is a smell.

## Research Answers (with file:line evidence)

### Q1. `Scenario` widening and materialization

**What `Scenario` validates** (`src/experiments/Scenario.jl:121-227`): feeder in `SCENARIO_VALID_FEEDERS = (:ieee13, :ieee123)` (:24, check :134); price in `(:mem,)` (:43, :142); population in `(:default, :case_a_784)` (:48, :150); `T >= 1` (:158); `seed >= 1` (:161); pf in `(:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)` (:38, :168); `pf_ε` finite and `>= 0` (:176); foreign `pf_*` options (:179, :187); `supports_pf(strategy, pf, thesis_literal)` (:195); ADMM requires `allow_export = true` (:204). Fields: `name, feeder, seed, T, population, price, allow_export, pf, pf_thesis_literal, pf_ε, strategy` (:108-119). **There is no density field.**

**Materialization** (`src/experiments/run.jl:61-73`): `build_feeder(s.feeder)`; `generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)`; `build_price(s.price, s.T, profiles)`; `build_population(s.population, feeder, s.feeder, profiles, sub_seed(s.seed, :population))`. `build_feeder` already dispatches `:ieee8500` and `:ieee8500_mv` (`materialize.jl:40-43`). Measured: `build_feeder(:ieee8500)` takes 0.01 s and yields **4,866 buses / 4,865 branches / 1,177 load buses**; `:ieee8500_mv` 2,512 buses / 2,511 branches / 1,138 load buses. (`docs/literate/ieee8500_scaling.jl:8,24,50,183` and CONTEXT say 4,875/4,874 and 2,521; `src/data/ieee8500.jl:12-19` documents the later merges that moved the counts to 4,866/2,512. Use the measured numbers; do not edit the old prose.)

**8500 population today** (`materialize.jl:1099-1166`): `:default` only, one `_ieee8500_house` per load bus (real per-SX-load kW, `materialize.jl:280-313`) plus 4 `FixedCapacitor` aggregators. `:case_a_784` is ieee13-only (`materialize.jl:1041-1049`, throws at materialization). Price `:mem` is cycled to any `T` (`materialize.jl:98-109`) and is compatible. pf: `:convex_branch_flow` with ADMM is the measured combination; the other pf selectors are Centralized-only (`Scenario.jl:73-78` table).

**Density:** not expressible. The harness builds the full population and filters it in the script (`benchmark_ieee8500.jl:269-277`) using `LehmerRNG(_SWEEP_SEED)` with `_SWEEP_SEED = 20260821` (:762, :977). **Minimum additive change** that lets `Scenario(feeder = :ieee8500, ...)` run the d = 0.1 ADMM-only point: widen the feeder tuple, add the `:default_10pct` population selector (Pattern 2), add the four guards (Pattern 1), update the two docstrings. Tests that this edit touches: `test_flex_population.jl:20` asserts `TSODSO.SCENARIO_VALID_POPULATIONS == (:default, :case_a_784)` and must become the widened tuple (the only existing-test edit; the sibling `test_population_case_a.jl:302` comment already says the tuple was widened once before). No test asserts `SCENARIO_VALID_FEEDERS`; `test_experiments.jl:88-91` and `test_strategies.jl:158` only use unknown selectors (`:bogus`, `:ieee14`) and stay green.

**ADMM-only meaning:** `--admm-only` skips the centralized model entirely (stub `cpoint` with `termination_status = "skipped_admm_only"`, `benchmark_ieee8500.jl:1019-1031`; header note lines 2026-10-04). `run(::ADMM, s)` never runs a centralized solve either, so "ADMM-only" is structural on the Scenario path.

### Q1b. Divergences between the Scenario path and the harness path that change numbers

| # | Item | Harness (`benchmark_ieee8500.jl`) | Scenario path | Effect |
|---|------|-----------------------------------|---------------|--------|
| 1 | Population seed | literal `_SWEEP_SEED = 20260821` (:998) | `sub_seed(s.seed, :population)` = `hash((seed, :population)) % typemax(UInt32)` (`materialize.jl:24`, `run.jl:70`; e.g. seed 1 -> 411717551) | **Different per-house profile draws** (`generate_profiles(seed + bus)`, `materialize.jl:281`) -> different `Pdc`/`Ppv`; numbers differ. Cannot be reproduced by choosing `s.seed` (hash). |
| 2 | Bus sample | `LehmerRNG(20260821)` | `LehmerRNG(pop sub-seed)` | Different 118 buses (same count, same rule) |
| 3 | `profiles` argument | seed 20260821 | seed `sub_seed(seed, :profiles)` | **No effect at 8500**: `_ieee8500_house` ignores `profiles` except `length(profiles.demand)` |
| 4 | λ₀ | `build_price(:mem, T, nothing)` | `build_price(:mem, T, profiles)` | Identical (profiles unused by `:mem`) |
| 5 | pf object | `ConvexBranchFlow()` (:631) | `build_powerflow(s)` = `ConvexBranchFlow(; thesis_literal = false)` | Identical (docstring `materialize.jl:1302`) |
| 6 | ADMM knobs | `ρ = 100.0`; rest solve_admm defaults (`maxiter = 200, ε_abs = 1e-4, ε_rel = 1e-3, τ = 2, μ = 10`) | `ADMM()` defaults are the same six values (`strategies.jl:78-85`) | Identical |
| 7 | Wall-clock cap | `time_limit_s = 1200` (`_DEFAULT_TIME_LIMIT_S`, :728) | `run(::ADMM)` passes none (`run.jl:122-135`); only `maxiter = 200` bounds it | **Behavioural**: Scenario path cannot end `budget_exceeded`; a non-converging point runs up to 200 iterations then `ConvergenceError`. The script should pass the harness's 1200 s to `_admm_iterate!` and record it. |
| 8 | Exactness gate | `atol_exact = nothing` (library hybrid floor) unless `--admm-atol` (:900-911, :1038) | `solve_admm` default `atol_exact = nothing`, `rtol_exact = 1e-4` (`solve_admm.jl:358-359`) | Identical gate; per-fixture `EXACTNESS_ATOL`/Clarabel tol `1e-7` apply only to the centralized point (not run here) |
| 9 | Solver conditioning | `agr_optimizer = nothing` -> `select_optimizer(QP())` | same (`solve_admm.jl:452`) | Identical |
| 10 | Outcome on refusal | caught -> `admm_status = "ERROR:CertificateError"` row (:646-662) | `TSODSO.run` propagates the throw (`run.jl:116-150`, `solve_admm.jl:538-558`) | The new script must catch and record |
| 11 | Timing scope | `admm_time_s` = whole `solve_admm` (build + loop + certify) (:626-664) | `ScenarioResult.elapsed` additionally includes materialization (`run.jl:119-121`) | Compare only like with like; the script reports the phases separately |
| 12 | Peak memory | `Sys.maxrss` delta and absolute (:627-672) | none | Script records `VmHWM` + `Sys.maxrss()` |
| 13 | Process baseline | `GC.gc()` before ADMM (:1035) | not applicable | Minor |
| 14 | Julia-version coupling | `LehmerRNG` is version-stable | `sub_seed` uses `Base.hash` | Record `VERSION` and the derived seed; run on 1.12.5 as the Phase-39 runs did |

Consequence for the table: the Scenario-path row reports **its own** iterations/ratio. The Phase-35/39 values (8 iterations, ratio 568.95, peak 5.69-5.92 GiB) are cited as harness-path comparators and labelled "different path: same size and structure, different seed draws". The verdict may differ from the harness's refusal; whatever it is, it is recorded.

### Q2. Byte-identity surface

- **`SCENARIO_VALID_FEEDERS`:** referenced only in `Scenario.jl` (:24, :59 docstring interpolation, :134-139 message) and in comments (`test_mpc_loop.jl:16`, `test_population_case_a.jl:302`). No test asserts its value. `docs/writeups/FRAMEWORK_GUIDE.html:3522` (tracked, hand-written) says `feeder ∈ (:ieee13, :ieee123)`; it is a stale writeup, outside any gate. The Scenario docstring uses `$(SCENARIO_VALID_FEEDERS)` interpolation, so the rendered API page (`docs/src/api.md:188` autodocs `experiments/Scenario.jl`) updates automatically. Also update the docstring prose in "Construction errors" (:96-103) and add the new guards and a 8500 note.
- **`SCENARIO_VALID_POPULATIONS`:** exact-tuple assertion at `test/test_flex_population.jl:20` (must be edited); `test_population_case_a.jl:302-309` only constructs `:case_a_784` and a bogus selector (green).
- **`fieldnames(Scenario)`:** exact assertion at `test_strategies.jl:108-120`. This is why no field is added.
- **`test_exports.jl`:** curated export list (`Scenario ScenarioResult run_scenario ...`, line 37). No new exports are needed; new selectors are plain symbols, helpers live in the script. No change.
- **Aqua:** no new dependency, no new exports; unaffected. (Memory note: two known-false Aqua failures on the main checkout from local `Project.toml` drift; not caused by this phase.)
- **JET ratchet:** baseline 20 signatures (`scripts/jet_baseline.txt`, check via `scripts/jet_check.jl`, Julia 1.12 + JET from the test env). The only new `src/` code is one branch using `StableRNGs`/`filter`; keep it type-simple. Run `jet_check.jl` once at the end of the phase: expected 0 new, 0 fixed.
- **Canary / goldens:** `test_admm_knifeedge_canary.jl` (56 / -4823.66604824162) exercises ieee13 paths; nothing here touches it. The default `:default` branch is not edited (new branch is additive). `scenario_filename` only differs for scenarios that name the new selector.
- **Docs pages that change:** only `docs/literate/ieee8500_scaling.jl` (appended section) and the auto-interpolated API page. `docs/make.jl` and `docs/src/*.md` need no edit (page already registered, `docs/make.jl:44,112`).

### Q3. Measurement harness mechanics

**`scripts/run_ieee8500_point.sh`** (94 lines): usage `scripts/run_ieee8500_point.sh <label> -- <args...>`; `SCRIPT` env selects the script (:23). It records `free -m` before the run (:36-40: `mem_avail_before_mb` = column 7 "available", `swap_used_before_mb`, `other_julia_procs` via `pgrep -c -x julia`), wraps the child in `/usr/bin/time -v` after writing its own PID (:45-50, child `exec`s julia), parses `Maximum resident set size` (kB, :54), collects `journalctl -k` and `journalctl -u earlyoom` since START (:56-59), and attributes `oom_source` only when RC != 0 and a log line names the child PID (`kernel` | `earlyoom` | `signal_unattributed` | `none`, :67-83). It always exits 0 (an OOM is a recorded outcome) and appends one row to `point_resources.csv` with header `run_label,rc,peak_rss_kb,oom_source,mem_avail_before_mb,swap_used_before_mb,other_julia_procs,started_at,args` (:85-92). Evidence files go to `results/ieee8500_benchmark/runs/<label>.{free_before,time,pid,oom_kernel,oom_earlyoom}` (tracked, not ignored).

Gaps: the wrapper adds `--run-label` only when `basename($SCRIPT) == benchmark_ieee8500.jl` (:33-36). For the new script, pass `--run-label <label>` explicitly inside the args after `--` (recorded in the `args` column; no wrapper edit). There is no heap-size flag: set `JULIA_HEAP_SIZE_HINT` in the environment (inherited by the exec'd child). `[CITED: docs.julialang.org/en/v1/manual/environment-variables]` accepts `B/K/M/G/T/%`.

**Attribution script VmHWM:** `proc_status_kb(key)` reads `/proc/self/status` and returns the first integer after `"VmHWM:"` in kB (`profile_ieee8500_memory_attribution.jl:70-75`); `VmRSS` is instantaneous, `VmHWM` whole-process high-water (:83-94 docstring). `Sys.maxrss()` returns bytes. The CSV stores kB and GiB side by side (`VmRSS_kB, VmHWM_kB, ..., gib`); GiB = kB / 1,048,576.

**Recommended design: a dedicated script, `scripts/ieee8500_scenario_point.jl`**, include-safe (`abspath(PROGRAM_FILE) == @__FILE__` gate as in `benchmark_ieee8500.jl:1379-1381`), `using TSODSO` with qualified internals (`TSODSO._materialize`, `TSODSO._admm_build`...; `check_script_api.jl` flags *bare* unexported names, qualified ones pass). Flags: `--feeder ieee8500` (default), `--T 10`, `--seed 1`, `--run-label`, `--time-limit 1200`, `--min-mem-avail-gib 8` (0 disables, used by tests), `--results-dir`, `--record-nogo`, `--help`. Sequence per the diagram. Row key for upsert: `(row_kind, feeder, population, T, strategy)`; a re-run replaces its row (`started` row replaced on completion, as `benchmark_ieee8500.jl:1005-1017,1168`). Status vocabulary: `ok` (converged and certified), `refused_certificate`, `convergence_error`, `budget_exceeded`, `error:<TypeName>` for other `TSODSOError`s, `preflight_refused`, `memory_infeasible` (NO-GO row), `started` (killed mid-run; the wrapper row then carries rc/oom_source). A killed process cannot write its own final row; that is exactly what the `started` row plus the wrapper's `point_resources.csv` row (joined by `run_label`) record.

**Phases and what each yields** (mirror of `solve_admm`; code in Code Examples):
- `t_materialize = @elapsed TSODSO._materialize(s)` (feeder + λ₀ + 122 aggregators; seconds).
- `t_build = @elapsed st = TSODSO._admm_build(feeder, pf, aggs, T, λ₀, ρ, ρ_q, mode, rmode)` (DSO build + 122 AgrOpt builds; the 0.41 + 1.72 GiB components at T = 10).
- `t_solve = @elapsed TSODSO._admm_iterate!(st, rmode, maxiter, ε_abs, ε_rel, τ, μ, ρ_min, ρ_max, time_limit_s, false)` -> `st.residuals.iters`, `st.converged_flag`, `st.budget_exceeded_flag`.
- `t_certify = @elapsed TSODSO._admm_certify(st, rmode, mode, aggs, λ₀, nothing, 1e-4, false)` inside `try`/`catch` for `CertificateError`; re-wrap `iterations = st.residuals.iters` exactly as `solve_admm.jl:549-557` does.
- Not-converged and not-budget -> record `convergence_error` (the `ConvergenceError` message construction at `solve_admm.jl:503-513` need not be reproduced; the row carries `maxiter`).
Parity risk (the script reimplements about 25 lines of `solve_admm` plumbing) is closed by a tiny IEEE-13 test asserting that the script's phase function and `run_scenario` agree on `iters`, welfare, `exact_maxgap` and `dadp` (`==`). Measured: IEEE-13 ADMM T = 10 seed 3 converges in 43 iterations, 2.5 s warm.

**Pre-flight gate.** Read `MemAvailable` (kB) from `/proc/meminfo` first thing after argument parsing and before `_materialize`. If `< 8 GiB` (8,388,608 kB), write one row (`status = preflight_refused`, `mem_avail_before_kb`, all measurements `missing`/`NaN`, the reason in `note`), print it, and exit 0. Do not retry or retune. The wrapper still writes its `point_resources.csv` row (rc 0, tiny MaxRSS). Operational reality for the orchestrator: **right now the host has 4.12 GiB MemAvailable (4,324,172 kB) and 9.7 GiB swap used**, so the gate would refuse today. Freeing the host (browser etc.) before launching is an orchestration decision; a `preflight_refused` row is an accepted measured outcome, but the orchestrator should not launch into a known refusal. For reference: the Phase-39 T = 10 run started with 5,734 MiB available and succeeded (peak 5.69 GiB).

**Runtime expectation** (measured): Phase-35 T = 10 harness point: `admm_time_s` 286.6 s, process wall 5:35 (`runs/p35-head-d0.1-T10.time`); Phase-39 T = 10 anchor 425 s under swap pressure (`anchor_time_s`), process 14:59 including the staged stages the new script does not run. Expect roughly 5-8 minutes; use the harness's 1200 s cap.

### Q4. NO-GO record: exact rows and lower-bound derivation

**Units.** `memory_attribution.csv` stores kB (`VmRSS_kB`, `VmHWM_kB`) and binary GiB (`gib`, `rss_delta_gib`); `point_resources.csv` `peak_rss_kb` is `/usr/bin/time` MaxRSS in kB; `free -m` columns are MiB. 1 GiB = 1,048,576 kB. **The "11.75 GiB" in CONTEXT, `39-HUMAN-UAT.md` and the Phase-39 verification is 11,753,716 kB / 10^6 (a decimal GB figure); in binary GiB it is 11.209.**

**Rows (T = 24, `fixture = ieee8500`, `density = 0.1`)** from `results/ieee8500_benchmark/memory_attribution.csv` (rows landed in commit `26a6a9f`, the 2026-10-27 UAT run; no wrapper row exists for that run, so the peak below is the in-process `VmHWM`, not `/usr/bin/time` MaxRSS):

| Quantity | Row key (stage, name) | Raw | Binary GiB |
|---|---|---|---|
| Process baseline | (1, `after_using`) VmHWM_kB | 1,335,580 kB | 1.274 |
| Anchor `Sys.maxrss` after | (1, `anchor_after`) VmHWM_kB | 11,082,624 kB | 10.569 (matches the in-message `peak=10.569 GiB`) |
| Anchor delta | (1, `anchor_after`) `gib` / `anchor_delta_gib` | — | **9.2955** |
| Anchor iterations / time | (1, `anchor_after`) `anchor_iters`, `anchor_time_s` | 7 iterations, 804.52 s | — |
| **Peak HWM (whole run)** | (3, `iter_7`) onward `VmHWM_kB` | **11,753,716 kB** | **11.209** |
| `comp_dso_build` | (9, `reconciliation:comp_dso_build`) | — | 0.8513 (tol 0.0851) |
| `comp_agr_builds` | (9, `...comp_agr_builds`) | — | **4.5694** (tol 0.4569) |
| `comp_first_iter_retained` | (9, `...comp_first_iter_retained`) | — | 2.9242 (tol 0.2924) |
| `comp_iter_retained` | (9, `...comp_iter_retained`) | — | 0.6477 (tol 0.0648) |
| `comp_certify` | (9, `...comp_certify`) | — | -0.0760 |
| `components_total` | (9, `...components_total`) | — | 8.9166 (tol 0.5552) |
| `residual` | (9, `residual`) | — | 0.3789 (tol 0.5552) |
| Verdict | `anchor_status` | `ERROR:CertificateError`, gap ratio 223.680501440749, max abs `|l·v-(P²+Q²)|` = 4.5759654535372564e-5 | — |

CONTEXT says "122 AgrOpt builds ≈ 4.0 GiB". The committed T = 24 stage-2 value is **4.569 GiB**; 4.024 (and DSO 0.922) were the earlier build-only run's numbers quoted in the Phase-39 docs section, which the later full run upsert-replaced. Use the CSV (4.569, DSO 0.851). The staged certify row says `iterations=6` versus anchor 7 (the profiler's documented one-count undercount, `ieee8500_scaling.jl` appended section); the production number of record is 7.

**Comparators (`point_resources.csv`, wrapper `/usr/bin/time` MaxRSS):**
- `p35-head-d0.1-T24`: rc 0, `peak_rss_kb` 12,079,316 = **11.520 GiB**, `oom_source` none, `mem_avail_before_mb` 10,334, `swap_used_before_mb` 1,553, started 2026-10-04 21:22:20 (process wall 12:07.62, `admm_time_s` 677.5 s in `density_sweep.csv`).
- `p35-head-d0.25-T24`: rc 143, `peak_rss_kb` 12,636,180 = **12.051 GiB**, `oom_source` earlyoom, `mem_avail_before_mb` 11,483 (killed in the ADMM loop; a lower bound on that point's requirement, never completed).
- `p39-attr-d0.1-T24`: rc 143 earlyoom, 7,820,096 kB = 7.458 GiB (launched with 6,307 MiB available, 10,057 MiB swap used).
- Earlyoom evidence (`runs/p39-attr-d0.1-T24.oom_earlyoom`): "low memory! at or below SIGTERM limits: mem 12.00%, swap 12.00%".
- Host total: `free_before` `Mem: total` 15,908 MiB (2026-10-04) and 15,396 MiB (2026-10-24); `/proc/meminfo` MemTotal now 15,765,568 kB = 15.03 GiB. "15 GB host" = ~15.0-15.5 GiB.

**Decision.** Threshold ~10 GiB (ROADMAP Phase 46 SC1, `REQUIREMENTS.md` SCALE-07). Measured peak 11.209 GiB (in-process) and 11.520 GiB (wrapper) both exceed it. Verdict `memory_infeasible` (NO-GO), recorded as a threshold verdict.

**Lower-bounded requirement (separate bounds from estimates):**
1. **Bound B1 (a measured lower bound):** the point's true peak resident set is at least the largest observed peak: **>= 11.520 GiB** (`p35-head-d0.1-T24` MaxRSS; the 11.209 GiB HWM is a second, independent observation of the same point). A host must be able to hold at least this resident in RAM for the process, plus whatever the OS keeps. This uses only measured numbers.
2. **Bound B2 (conditional on this host's killer configuration):** earlyoom sends SIGTERM when MemAvailable <= 12% of RAM **and** swap free <= 12% (committed log line). 12% of 15,396-15,908 MiB is 1.80-1.86 GiB. To keep MemAvailable above that floor at the peak instant without leaning on swap, the requirement becomes **>= 11.52 + 1.80 = 13.3 GiB MemAvailable-equivalent**. This is an *estimate specific to the earlyoom setting* (the swap condition makes it not strict), labelled as such. Do not present B2 as a hard bound.
3. **Observed counter-fact (must be stated):** the point completed twice on this host with *less* than B1 available at launch (10,334 MiB at Phase 35; the UAT run recorded "10 GiB RAM + 16 GiB swap headroom"), because page cache is reclaimable and swap absorbed the rest. At the Phase-35 T = 24 launch, `used` was 5,574 MiB and the peak was 11.52 GiB, so the sum 16.96 GiB exceeded 15.54 GiB of RAM: the run succeeded only by cache eviction/swap. So the honest NO-GO statement is: "exceeds the ~10 GiB GO threshold; leaves <= ~3.5 GiB of a 15.0 GiB host for the OS and everything else; completes only when the host is quiet and swap absorbs the overflow; d = 0.25 was killed at 12.05 GiB". It must **not** claim the point is impossible, and it must not claim any lever exists.
4. Phrase the requirement on **available** RAM (CONTEXT "Specific Ideas"): `MemAvailable` at the peak, not installed RAM.
Cross-check with the earlier wall characterization (`memory_wall_recharacterization.csv`: kill between d = 0.1 and 0.25 at T = 24) and Phase 40's 784-house memory wall; no new claim needed.

### Q5. Size reporting (cheap, no extra memory)

- Buses/branches: `length(feeder.buses)`, `length(feeder.branches)` on the feeder returned by `_materialize` (4,866 / 4,865 measured; mv 2,512 / 2,511).
- Load buses / houses / aggregators: `length(TSODSO._load_buses(feeder, :ieee8500))` = 1,177 (candidate houses at density 1.0); aggregators after the selector = `length(aggs)` = 122, of which `count(a -> any(d -> d isa FixedCapacitor, a.devices), aggs)` = 4 capacitor aggregators and 118 houses (one house per sampled SX load; `_ieee8500_house` builds exactly one).
- JuMP sizes: after `_admm_build`, `JuMP.num_variables(st.dso.model)` and `JuMP.num_constraints(st.dso.model; count_variable_in_set_constraints = true)` (same call shape as `benchmark_ieee8500.jl:554-557`), plus the sums over `values(st.agr_by_bus)` of the same on each `.model`. `DsoOpt` and `AgrOpt` each hold `model::Model` (`DsoOpt.jl:85-86`, `AgrOpt.jl:67-68`). These calls read model metadata (O(1) / O(constraint types)) and allocate nothing material. Do **not** build extra models to count; the counts come from the models the measured run already holds.
- Record `n_agr_models` as well so the table reads "DSO 1 model + 122 AgrOpt models".

### Q6. Test strategy (tiny, no 8500 solve)

Measured cost basis: `build_feeder(:ieee8500)` 0.01 s; full `:default` 8500 population 2.77 s; the new selector builds the full population then filters, so ~3 s per 8500-family materialization. No cheap solved 8500 slice exists (the harness `--quick` mv point is ~70-80 s: `benchmark_ieee8500.jl:729-741`; `test_benchmark_ieee8500.jl` already runs it as a subprocess), so tests cover **construction, validation, materialization and the NO-GO derivation only**. New file `test/test_ieee8500_scenario.jl`, untagged `@testitem`s (untagged = fast, `runner_support.jl:56`):

1. Widened construction: `Scenario(name="x", feeder=:ieee8500)` and `:ieee8500_mv` construct; defaults for `:ieee13` unchanged; `SCENARIO_VALID_FEEDERS` contains the four symbols.
2. Guards (each `@test_throws ArgumentError`): `:default_10pct` on `:ieee13`/`:ieee123`; `:case_a_784` on 8500; `pf = :ac` on 8500; `strategy = MPC()` and `Stochastic()` on 8500; existing `feeder = :bogus` still throws.
3. Materialization (no solve): `TSODSO._materialize(Scenario(name="x", feeder=:ieee8500, population=:default_10pct, T=10, strategy=ADMM()))` returns a 4,866-bus feeder and **122** aggregators with exactly 4 capacitor aggregators; same for `:ieee8500_mv` -> 118; deterministic (`==` on bus lists and `Pdc` across two calls); differs across seeds.
4. Harness equivalence at equal seed: `build_population(:default_10pct, feeder, :ieee8500, profiles, S)` has the same aggregator buses and `Pdc` as `density_filtered_population(feeder, :ieee8500, profiles, S, 0.1, LehmerRNG(S))` from `scripts/benchmark_ieee8500.jl` (include-safe; `test_case_a_magnitude.jl:518,573` is the precedent for `include`-ing a script inside a `@testitem`). This pins "same rule, different seed source" as the only divergence.
5. Default fence: `build_population(:default, ...)` on `:ieee13` and `:ieee123` is unchanged (`==` before/after is impossible to compare across commits, so assert structural facts already pinned elsewhere; `test_flex_population.jl` carries the bit-level fence and is kept green).
6. Script helpers (include the new script): the NO-GO derivation function on the committed CSVs returns `vmhwm_kb == 11_753_716`, `vmhwm_gib ≈ 11.209` (binary), `p35_maxrss_kb == 12_079_316`, anchor delta ≈ 9.2955, `anchor_iters == 7`, ratio ≈ 223.68, status `memory_infeasible`; the unit conversion is binary (1,048,576). Pre-flight parsing: a synthetic `/proc/meminfo` text with `MemAvailable: 4324172 kB` yields refused at 8 GiB; `--min-mem-avail-gib 0` passes. Upsert: keyed replace (a `started` row is replaced; other keys kept) in a `mktempdir()`.
7. Phase-composition parity (IEEE-13, ~3-5 s): the script's phase function vs `TSODSO.run_scenario` on `Scenario(name, feeder=:ieee13, strategy=ADMM(), T=10, seed=3)` agree `==` on `iters`, welfare, `exact_maxgap`, `dadp`.
`@testitem` hygiene: no `try x = ...`, no outer-variable reassignment in loops (wrap in functions or `let`). Run the file with `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl,test_flex_population.jl,test_strategies.jl,test_experiments.jl julia --project=. -e 'import Pkg; Pkg.test()'`, then `git checkout -- test/Project.toml test/Manifest.toml`. Full suite wall time grows by roughly 10-20 s (two 3 s materializations, one 3-5 s parity solve); baseline for comparison is the recorded 35194/0/0/7 (memory note).

### Q7. Docs

`docs/literate/ieee8500_scaling.jl` is 534 lines. Sections: Two walls (:12), Live (:38; a live Clarabel point on `ieee8500-mv` d = 0.1 T = 24 with a 90 s time limit, ~76-80 s), Precomputed (:105), headline stated plainly (:181), Post-refactor results (:216), Synthesis (:333), Reproducing (:394), then the appended dated Phase-39 attribution section (:406 to end, "*(Appended 2026-10-24...)*"). Pages read CSVs with `Base` only (`read_sweep_csv`, :140-160; the docs env has no CSV/DataFrames), so the new section must parse `scenario_table.csv`, `memory_attribution.csv` and `point_resources.csv` with a small `Base` parser (split with `limit = ncols` because free-text columns contain commas; quoted fields exist in `point_resources.csv`' `args` column and in `note`/`message` columns, so use a minimal quote-aware splitter or keep free text in the last column). The page **does execute** in `docs/make.jl` (Literate.markdown with DocumenterFlavor, list at `docs/make.jl:44`); the measured docs build is ~6.8 min against a 30-minute CI timeout (`ieee8500_scaling.jl:41-48`), and an appended CSV-reading section adds well under a second. No `docs/make.jl` edit is needed (page already registered at :44 and :112). A new page would need entries in both places; not recommended.

**Append a new dated section** (e.g. "Headline measurement and go/no-go (appended 2026-11-05)") that: states the threshold; recomputes every number from the CSV rows (binary GiB; raw kB beside); shows the B1/B2 derivation and the counter-fact; shows the Scenario-path table with the divergence table; **states the supersession** that the older attribution section says the T = 24 loop attribution "NOT ESTABLISHED" and "the full run was earlyoom-killed", whereas the CSV has carried the completed T = 24 rows since the 2026-10-27 UAT run (and its build numbers 4.569/0.851 supersede 4.024/0.922); notes the "11.75 GiB" label correction; notes the 4,875/4,866 bus-count prose staleness. Do not edit older text. **Planning-ID guard:** new prose must not contain `Phase NN`, `SCALE-0x`/`REQ-NN` ids, `byte-identical` (say `bit-identical`), `RESEARCH`/`CONTEXT.md`/`.planning/`, `wave`, `Task N`, `Pitfall N`, `D-NN`, etc. (patterns in `.github/scripts/planning_id_rules.py:12-48`). Refer to "the earlier attribution run" and to CSV row keys instead.

**`scripts/README.md`:** add one row under `## Scripts` for `ieee8500_scenario_point.jl` (the checker, `.github/scripts/check_scripts_index.py`, requires every tracked file under `scripts/` as a backticked whole-path token; `results/` tokens are ignored). Existing rows to imitate: `benchmark_ieee8500.jl` (README:25), `run_ieee8500_point.sh` (:46). No other registration.

### Q8. Repo gates

| Gate | Command | State / requirement |
|------|---------|--------------------|
| Planning-ID guard | `python3 .github/scripts/check_planning_ids.py` | Currently reports **355 hit(s), 0 stale** (baseline; the allowlist is intentionally empty). Scope: `src ext test scripts docs/literate docs/make.jl docs/src README.md .github/workflows/CI.yml` (`planning_id_rules.py:80-86`); `.planning/` excluded. New code/docs/tests/scripts must add **zero** hits, so the count must stay 355. Hits today: `ieee8500_scaling.jl` 18, `materialize.jl` 12, `profile_ieee8500_memory_attribution.jl` 12, `test_flex_population.jl` 7, `scripts/README.md` 5 (do not "fix" these; unrelated churn). |
| Scripts index | `python3 .github/scripts/check_scripts_index.py` | New script needs a README row |
| API-surface lint | `julia --project=. --startup-file=no .github/scripts/check_script_api.jl` (scripts + `docs/literate`) | Qualify unexported names (`TSODSO._materialize`, `TSODSO.build_powerflow`) or import them explicitly |
| Formatter | `.github/workflows/CI.yml` format job: JuliaFormatter 2.10 on `src ext test docs` (scripts are NOT formatted) | New `src`, `test`, `docs/literate` code must be formatter-clean (`.github/scripts/format210.jl`); `check_content_loss.py` follows |
| `@testitem` setup names | `python3 .github/scripts/check_setup_names.py` | Only if `setup = [...]` is used (not needed) |
| JET ratchet | `scripts/jet_check.jl` (Julia 1.12, JET in test env) | baseline 20; expect 0 new |
| Docs build | `julia --project=docs docs/make.jl` | Appended section only; `checkdocs = :exports` unaffected |
| Suite | `Pkg.test()` fast set | Expected-broken guard `test/expected_broken.txt`: add no `@test_broken` |

## Common Pitfalls

### Pitfall 1: Quoting 11.75 GiB
**What goes wrong:** the decision artifact repeats "11.75 GiB" and a reader converting from kB gets 11.21.
**Why it happens:** 11,753,716 kB / 10^6; binary GiB is /1,048,576.
**How to avoid:** store raw kB and binary GiB side by side; the CSV row and docs compute GiB from kB; add one sentence correcting the earlier label. Verdict is unchanged (11.21 > 10).
**Warning signs:** a hand-typed GiB figure that does not equal kB/1,048,576.

### Pitfall 2: Treating "NO-GO" as "cannot run"
**What goes wrong:** the doc claims the headline is impossible on this host while two committed runs completed.
**How to avoid:** state B1 (bound), B2 (conditional estimate) and the counter-fact in the same paragraph; say "exceeds the GO threshold", never "cannot run"; claim no lever.

### Pitfall 3: Comparing unlike numbers
**What goes wrong:** the Scenario-path T = 10 row is read as a re-measurement of the harness point.
**How to avoid:** the table's note column and the docs section say "Scenario path: sub-seeded draws; harness comparators come from the harness path"; never subtract numbers across paths.

### Pitfall 4: `Pkg.test()` side effects
**What goes wrong:** `test/Project.toml`/`Manifest.toml` get modified and committed.
**How to avoid:** `git checkout -- test/Project.toml test/Manifest.toml` after every test run; commit only intended files.

### Pitfall 5: Concurrent Julia processes and detached-run races
**What goes wrong:** a suite run or an agent worktree run shares the host; earlyoom kills the 8500 run; stale logs give phantom results.
**How to avoid:** the orchestrator launches the point alone (check `pgrep -x julia` returns nothing; the wrapper records `other_julia_procs`), never during a test-suite run, never from an executor. The point is a single process; no retry after a kill (one attempt, the repo's ladder protocol).

### Pitfall 6: Pre-flight reading its own footprint
**What goes wrong:** gating after `using TSODSO` (about 1.3 GiB RSS, `after_using` 1,335,580 kB) understates availability.
**How to avoid:** read `MemAvailable` before any heavy work and also record the wrapper's `mem_avail_before_mb`; the 8 GiB gate leaves ~2 GiB margin over the expected ~5.6-6.2 GiB peak.

### Pitfall 7: `sub_seed` is not version-stable
**What goes wrong:** the same `Scenario` yields different draws on another Julia patch (`Base.hash`).
**How to avoid:** record `VERSION`, `s.seed`, and the derived population seed in the row; run on 1.12.5 like the Phase-39 runs; note it in the docs section.

### Pitfall 8: Silent heap-hint effect
**What goes wrong:** `JULIA_HEAP_SIZE_HINT` changes GC pacing and so the peak, making numbers incomparable to the unhinted harness runs.
**How to avoid:** record the value in the row; a hint above the expected peak (8G vs ~6 GiB) should be inert [ASSUMED]; label the run "hinted" in the comparison; do not claim any memory benefit (no lever is claimed).

### Pitfall 9: Test-environment scope traps
**What goes wrong:** `try x = ...` / for-loop reassignment inside a `@testitem` creates locals; `include`-ing the benchmark script runs `@quickactivate` and needs CSV/DataFrames in the test env.
**How to avoid:** wrap blocks in functions; follow `test_case_a_magnitude.jl` for script includes; keep scratch `.jl` outside the repo.

## Code Examples

### Phase-composed Scenario run (mirror of `run(::ADMM, s)` + `solve_admm` plumbing)
```julia
# Sources: src/experiments/run.jl:61-73,116-150; src/admm/solve_admm.jl:440-558;
#          scripts/profile_ieee8500_memory_attribution.jl:153-165,233-245,298.
function scenario_admm_phases(s::Scenario; time_limit_s = 1200.0)
    st_ = s.strategy                                   # ADMM
    t_mat = @elapsed (feeder, λ₀, aggs = TSODSO._materialize(s))
    pf   = TSODSO.build_powerflow(s)
    mode = TSODSO.normalize_reactive_mode(TSODSO._default_reactive_consensus(aggs))
    rmode = TSODSO._react_mode(mode)
    local st
    t_build = @elapsed (st = TSODSO._admm_build(
        feeder, pf, aggs, s.T, λ₀, st_.ρ, st_.ρ, mode, rmode;
        agr_optimizer = TSODSO.select_optimizer(TSODSO.QP())))
    sizes = (dso_vars = num_variables(st.dso.model), agr_models = length(st.agr_by_bus), ...)
    t_solve = @elapsed TSODSO._admm_iterate!(
        st, rmode, st_.maxiter, st_.ε_abs, st_.ε_rel, st_.τ_ratio, st_.μ,
        1e-2, 1e4, time_limit_s, false)
    # then: budget_exceeded -> status row; not converged -> convergence_error row;
    # else try _admm_certify(st, rmode, mode, aggs, λ₀, nothing, 1e-4, false)
    #   catch CertificateError -> status = refused_certificate, ratio parsed from msg
    #   (re-wrap iterations = st.residuals.iters as solve_admm.jl:549-557 does)
end
```
(`ρ_min = 1e-2`, `ρ_max = 1e4` are the `solve_admm` defaults, `solve_admm.jl:352-353`.)

### Hybrid ratio from the refusal message
```julia
# message form (memory_attribution.csv, anchor rows):
# "SOCP relaxation INEXACT: worst gap/(atol_b+rtol·|cone|)=568.9541645248668 > 1 (rtol=0.0001, ..."
m = match(r"worst gap/\(atol_b\+rtol·\|cone\|\)=([0-9.eE+-]+)", msg)
ratio = m === nothing ? NaN : parse(Float64, m.captures[1])   # parse BEFORE truncating the message
```

### Pre-flight gate
```julia
function mem_available_kb(path = "/proc/meminfo")
    for line in eachline(path)
        startswith(line, "MemAvailable:") && return parse(Int, split(line)[2])
    end
    return -1
end
preflight_ok(kb, min_gib) = min_gib <= 0 || kb >= round(Int, min_gib * 1024^2)   # kB
```

### NO-GO row from committed CSVs (binary units)
```julia
kb_to_gib(kb) = kb / 1024^2
# memory_attribution.csv: filter(fixture == "ieee8500", density == 0.1, T == 24); peak = maximum VmHWM_kB
# point_resources.csv: rows p35-head-d0.1-T24 (12_079_316 kB) and p35-head-d0.25-T24 (12_636_180 kB, rc 143)
# B1 = max(observed peaks);  B2_estimate = B1 + 0.12 * MemTotal_gib   (labelled estimate)
```

### Launch (orchestrator, not an executor)
```bash
# only after: pgrep -x julia returns nothing and MemAvailable >= 8 GiB
JULIA_HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl \
  scripts/run_ieee8500_point.sh p46-scn-ieee8500-d10-T10 -- \
  --feeder ieee8500 --T 10 --run-label p46-scn-ieee8500-d10-T10
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| T = 24 attribution "not established" (earlyoom kill, build-only rows) | Full T = 24 rows committed, completed on 2026-10-27 | commit `26a6a9f` | The new docs section supersedes the older prose; build numbers are 4.569/0.851 GiB, not 4.024/0.922 |
| Phase-35 standing T = 24 figures (11.52 GiB peak, 10.17 GiB loop delta) | UAT note says these are superseded by 11.75 GiB / 9.296 GiB | 2026-10-27 | The 11.75 is mislabelled kB/10^6; the binary figure is 11.21 GiB. Both peaks are cited |
| 8500 bus count 4,875 / 2,521 | 4,866 / 2,512 | bus-merge widening (`src/data/ieee8500.jl:12-19`) | Table uses measured counts |

**Deprecated/outdated:** CONTEXT's "4.0 GiB AgrOpt" and "11.75 GiB" and "4,875 buses" (see above); `docs/writeups/FRAMEWORK_GUIDE.html` selector list.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `JULIA_HEAP_SIZE_HINT=8G` is inert at an expected ~6 GiB peak (no GC pacing change that moves the peak materially) | Pitfall 8, launch | Peak differs from unhinted harness runs; mitigated by recording the value and labelling |
| A2 | The host's earlyoom keeps the committed `-m 12 -s 12` SIGTERM limits during the run (committed log lines show 12.00%/12.00%; `/etc/default/earlyoom` read this session shows `-m 12,6 -s 12,6`) | Q4 B2 | B2 headroom estimate is off; B1 stands |
| A3 | Guarding `pf = :ac`, `MPC` and `Stochastic` on the 8500 feeders is preferred over documenting them as unmeasured | Pattern 1 guards 3-4 | If the owner wants researchers free to try them, drop guards 3-4 (guards 1-2 are factual) |
| A4 | Expected run wall time ~5-8 min (from Phase-35 5:35 wall / 287 s solve and Phase-39 425 s anchor under swap) | Q3 | Longer on a loaded host; the 1200 s cap bounds the loop |
| A5 | The `Scenario`-path verdict at T = 10 may differ from the harness's `CertificateError` ratio ~569 (different draws); any verdict is acceptable | Q1b | None: all verdicts are recorded outcomes |
| A6 | `hash`-derived `sub_seed` is stable within Julia 1.12.5 | Pitfall 7 | A later patch changes the draws; run is pinned and versions recorded |

## Open Questions (RESOLVED)

1. **How is density expressed in a `Scenario`? (RESOLVED)**
   - What we know: no field; `test_strategies.jl:108` pins `fieldnames`; the harness filters in-script.
   - Resolution: one new population selector `:default_10pct` (8500 family only), widened tuple, one-line edit of `test_flex_population.jl:20`. No struct change.
2. **`run_scenario` literally, or phase functions? (RESOLVED)**
   - Resolution: phase functions called in `run(::ADMM)`'s order from `Scenario` selectors (needed for build/solve split and free model counts), pinned to `run_scenario` by an IEEE-13 parity test; `materialize_s` is also timed through `TSODSO._materialize`. State the composition in the table note.
3. **Where does the NO-GO record live? (RESOLVED)**
   - Resolution: a `row_kind = recorded_no_go` row in `scenario_table.csv` computed by `--record-nogo` from the committed CSVs, plus the dated docs section recomputing it. No new run.
4. **CONTEXT's "11.75 GiB"? (RESOLVED)**
   - Resolution: it is 11.209 GiB binary (11,753,716 kB). Record raw kB and binary GiB; verdict unchanged.
5. **Where does the pre-flight gate live? (RESOLVED)**
   - Resolution: in the Julia script (`--min-mem-avail-gib`, default 8, reads `/proc/meminfo` before any heavy work); the wrapper is unchanged and still records `mem_avail_before_mb`.
6. **Heap-size-hint plumbing? (RESOLVED)**
   - Resolution: `JULIA_HEAP_SIZE_HINT=8G` in the environment; the script records it; no wrapper edit.
7. **Wrapper `--run-label`? (RESOLVED)**
   - Resolution: pass `--run-label <label>` explicitly after `--`; no wrapper edit.
8. **Which combinations get guards? (RESOLVED)**
   - Resolution: guards 1-4 in Pattern 1 (A3 flags 3-4 as a preference). `:default` at 8500 stays allowed and documented (density 1.0, OOM-measured). `T < 9` is already a loud `ArgumentError` at materialization.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all | yes | 1.12.5 (juliaup default) | — |
| `/usr/bin/time`, `journalctl`, `pgrep`, `free` | wrapper | yes | system | — |
| earlyoom | host safety (informational) | yes (service active) | `-r 300 -m 12,6 -s 12,6 --prefer julia` | — |
| python3 | repo gates | yes | 3.14.4 | — |
| 4 cores | run | yes (`nproc` = 4; Julia `nthreads` = 1 default) | — | — |
| **MemAvailable >= 8 GiB** | pre-flight gate for the T = 10 run | **no, right now** | 4.12 GiB available, 9.7 GiB swap used at research time | free the host before launch, else a `preflight_refused` row is the accepted outcome |

**Missing dependencies with no fallback:** none for code work. **Blocking for the run only:** host memory (orchestration decision; do not retune).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test.jl + TestItemRunner (`@testitem`), runner in `test/runtests.jl` with `runner_support.jl` |
| Config file | `test/Project.toml` (test env), `test/expected_broken.txt` |
| Quick run command | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl julia --project=. -e 'import Pkg; Pkg.test()'` then `git checkout -- test/Project.toml test/Manifest.toml` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (detached, alone; `.github/scripts/suite_detached.sh` + `check_suite_log.py`) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCALE-08 | Widened feeder tuple constructs `:ieee8500`/`:ieee8500_mv`; default and `:bogus` behaviour unchanged | unit | quick run above (item 1) | Wave 0 |
| SCALE-08 | Four `ArgumentError` guards fire | unit | quick run (item 2) | Wave 0 |
| SCALE-08 | `:default_10pct` materializes 122 / 118 aggregators, 4,866 buses, deterministic | unit (3 s) | quick run (item 3) | Wave 0 |
| SCALE-08 | Selector equals harness `density_filtered_population` at equal seed | unit (3 s) | quick run (item 4) | Wave 0 |
| SCALE-08 | Script phase composition == `run_scenario` on IEEE-13 | unit (3-5 s) | quick run (item 7) | Wave 0 |
| SCALE-08 | Row building, status vocabulary, keyed upsert, ratio parse, pre-flight parse | unit | quick run (item 6) | Wave 0 |
| SCALE-07 | NO-GO derivation from committed CSVs: peak 11,753,716 kB = 11.209 GiB binary, B1 = 11.520, status `memory_infeasible` | unit | quick run (item 6) | Wave 0 |
| SCALE-08 | The measured T = 10 row exists, has status in the allowed vocabulary, joined wrapper row present | data check (post-run, no solve) | `julia --project=. -e` CSV assertion script or test item reading `scenario_table.csv` | Wave 0 (written, run after the orchestrator's run) |
| SC3 | No tolerance/tau/hybrid floor changed | diff gate | `git diff --stat` over `src/admm`, `src/models/exactness.jl`, solver factory: empty; canary file unchanged and green | existing tests |
| Existing | Default-path byte identity | regression | `TSODSO_TEST_FILES=test_strategies.jl,test_experiments.jl,test_flex_population.jl,test_admm_knifeedge_canary.jl,test_exports.jl` | exist |

### Sampling Rate
- **Per task commit:** the quick run for the touched file(s).
- **Per wave merge:** fast set for the five files named in "Existing" plus the new file; planning-ID, scripts-index and API-lint checkers.
- **Phase gate:** full suite green and unchanged in count apart from the new items (baseline recorded 35194/0/0/7), `check_planning_ids.py` still 355, `jet_check.jl` 0 new, docs build green, `git diff` shows no solver-config changes; then `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_ieee8500_scenario.jl`: covers SCALE-07/08 items 1-7 above.
- [ ] One-line edit `test/test_flex_population.jl:20` (tuple widened) is part of the same change, not a gap.
- [ ] No framework install needed.

## Security Domain

`security_enforcement` is absent (treated as enabled). This phase has no network, auth, session or secrets surface.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Script CLI flags validated up front (`ArgumentError`), selectors validated in the `Scenario` constructor; `--run-label` restricted to `[A-Za-z0-9._-]+` (the wrapper already enforces this, `run_ieee8500_point.sh:19-21`) |
| V6 Cryptography | no | — |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path/label injection into CSV or filenames | Tampering | Label whitelist; write only under `results/ieee8500_benchmark/` (or `--results-dir`) |
| CSV injection through free-text columns | Tampering | Keep `note`/message columns quoted by CSV.jl; docs parser is read-only |
| Resource exhaustion (OOM) of a shared host | Denial of service | 8 GiB pre-flight gate, one process, earlyoom awareness, detached-and-alone launch |

## Sources

### Primary (HIGH confidence)
- Repo code read this session: `src/experiments/Scenario.jl`, `materialize.jl`, `run.jl`, `strategies.jl`; `src/admm/solve_admm.jl`, `admm_phases.jl`; `scripts/benchmark_ieee8500.jl`, `profile_ieee8500_memory_attribution.jl`, `run_ieee8500_point.sh`, `case_a_magnitude.jl`; `docs/literate/ieee8500_scaling.jl`, `docs/make.jl`; `.github/scripts/*`, `.github/workflows/CI.yml`.
- Committed CSVs: `results/ieee8500_benchmark/memory_attribution.csv`, `point_resources.csv`, `density_sweep.csv`, `memory_wall_recharacterization.csv`; run evidence `runs/p35-head-d0.1-T24.*`, `runs/p39-attr-d0.1-T24.*`.
- `.planning/phases/39-.../39-VERIFICATION.md`, `39-HUMAN-UAT.md` (diff of commit `26a6a9f`), `.planning/research/SUMMARY.md`, `ARCHITECTURE.md`.
- Live measurements this session (tiny snippets, no solve at 8500): feeder sizes and population construction times; IEEE-13 ADMM T = 10 (43 iterations, 2.5 s warm); `T = 8` throws, `T = 9` builds; `/proc/meminfo`, `free -m`, `/etc/default/earlyoom`.
- Julia manual, environment variables: https://docs.julialang.org/en/v1/manual/environment-variables/ (`JULIA_HEAP_SIZE_HINT` equals `--heap-size-hint`, units B/K/M/G/T/%).

### Secondary (MEDIUM confidence)
- Phase-35/39 narrative in `docs/literate/ieee8500_scaling.jl` (consistent with the CSV rows; its older prose is superseded where noted).

### Tertiary (LOW confidence)
- None used as a basis for a recommendation; A1/A4 are flagged assumptions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new packages; versions from `Project.toml`.
- Architecture (selector, script design, gates): HIGH - every seam and test constraint read with line evidence.
- NO-GO derivation: HIGH for the CSV values and units; MEDIUM for B2 (conditional on earlyoom configuration).
- Pitfalls: HIGH for repo-specific traps; MEDIUM for heap-hint behaviour.

**Research date:** 2026-11-05
**Valid until:** 2026-12-05 (stable repo seams; re-check host memory and the planning-ID count at plan time)
