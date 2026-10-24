# Phase 40: 784-House Thesis Population - Research

**Researched:** 2026-10-24
**Domain:** Julia/JuMP experiment-harness extension — additive population selector, per-house deterministic seeding, centralized-vs-ADMM agreement measurement, measured scaling report
**Confidence:** HIGH (codebase seams verified by direct read; feasibility anchored on a measured in-repo precedent; two modeling decisions flagged for the planner)

## Summary

Phase 40 is almost entirely **orchestration on already-verified seams** — no new models, no new
devices, no new packages. Everything the phase needs exists and was read directly this session:
the `build_population` selector dispatch and `sub_seed` hash idiom
(`src/experiments/materialize.jl`), the `Scenario` population-selector validation tuple
(`src/experiments/Scenario.jl:48`), the Phase-39 threaded executor (`solve_admm(...;
parallel = true)`, fail-loud on `nthreads() == 1`), the ADMM iteration counter (`iters` in the
`solve_admm` return), the `:slow` test-tag mechanism (`TSODSO_TEST_SET`, TestItemRunner), and the
Phase-35 measurement-artifact pattern (committed CSVs under `results/` + a literate page that
reads them with only a tiny live solve).

**The single most load-bearing discovery:** `solve_admm` hard-enforces **one aggregator per load
node** (`src/admm/admm_phases.jl:67-74`: `length(aggregators) == length(load_nodes) || throw`,
plus a duplicate-bus guard). A population of 784 `Aggregator`s (~78 per bus) is **structurally
unsolvable by ADMM today**. The `:case_a_784` branch must therefore return exactly **10
bus-level `Aggregator`s**, each rolling up its ~78 houses' devices (concatenated device list) and
summed `Pdc` — the same roll-up `Aggregator.contribute!` already performs, so `solve_welfare`,
`solve_admm`, and the harness's `sort!([a.bus for a in aggs])` price extraction
(`src/experiments/run.jl:97`) all keep working unchanged. The 784-house granularity lives in the
**construction** (per-house seeded profile draws + device parameters), the **household map**
(pure accessor), and the **composition stats** — not in the solver-facing object count. This also
matches the thesis architecture at the aggregator tier (10 aggregators) while the thesis's
per-house separability is approximated by the Phase-39 threaded executor over the 10 bus
subproblems.

**Feasibility of POP-04 (the risky-looking requirement) is anchored, not guessed:** the committed
Phase-25/35 sweep CSV (`results/ieee8500_benchmark/density_sweep_full.csv`) records a
**centralized** Clarabel solve of 371,036 vars / 741,904 cons (ieee8500-mv, d=0.25, T=24) at
OPTIMAL in **50.0 s solve / 101.7 s total** on this same 4-core/15 GB host. The full 784-house
centralized model is ~134k vars (~2.8× smaller than that anchor) — it fits and solves with high
confidence; the ADMM iteration count at this size is the genuine unknown (canary takes 56
iterations on 10 one-house aggregators; the thesis reports 28 at 784 houses) and is exactly what
the ladder measures.

**Primary recommendation:** build `:case_a_784` as an additive `build_population` branch that
constructs 784 per-house-seeded devices rolled into 10 bus-level aggregators; measure agreement
at full scale with gate-then-golden tolerance in a `:slow` test; drive the threads sweep through
subprocess invocations (`julia -t N`) calling `solve_admm` directly (kwarg-only, no Scenario
seam); write CSVs to `results/case_a_population/` and a new literate page that loads the CSVs.

<user_constraints>

## User Constraints (from CONTEXT.md — LOCKED)

### Locked Decisions

**Population Construction & Selector API**
- New `Symbol` selector `:case_a_784` dispatched as an additive branch in `build_population`
  (existing selector-dispatch pattern); `:default` code path untouched.
- Per-bus house counts: distribute the 784 households across the 10 IEEE-13 load buses
  proportionally to the existing `:default` population's per-bus counts (rounded, residue assigned
  deterministically to the largest buses first), with the rule documented. Thesis-exact per-bus
  counts are unavailable (Appendix E).
- PV/non-PV split and elastic/inelastic load proportions: keep the `:default` population's
  fractions (continuity with the validated rescaled proxy), documented as calibration provenance.
- Seed derivation: extend the existing `sub_seed` hash idiom — each house seeded from
  `hash((master_seed, :house, bus, house_index))`; a test asserts all 784 seeds are distinct and
  that rebuilding reproduces the population exactly.

**Household Map & Device Mix**
- The household map is a pure function of (master seed, bus list, house indices) — a deterministic
  accessor (e.g. `case_a_household_map(...)`) rebuilds it without mutating `Aggregator` or changing
  `build_population`'s `Vector{<:Aggregator}` return type. Fields per house: bus, aggregator id,
  device set symbol, PV/non-PV group.
- Per-house devices reuse the existing `:default` device builders (PV + elastic/inelastic load
  devices), with per-house parameters drawn from the house's own seeded RNG — no new device types
  in this phase.
- Device-mix composition is measured from the built population and written into the docs page
  (counts, total PV capacity, elastic/inelastic load totals).

**Centralized vs ADMM Agreement**
- Agreement measured at the FULL 784-house population on the thesis Case A day, T=24, both
  centralized `solve_welfare` and ADMM.
- Tolerance is MEASURED then stated (gate-then-golden): run both, record the observed welfare and
  price deltas, pin the test with a band derived from the measurement — never pre-loosened.
- The agreement check is a `:slow`-tagged test (existing fast/slow suite split) so the default CI
  lane stays fast; documented in the doc page.

**Scaling Report**
- Threads sweep on the full-population ADMM solve via the Phase-39 executor opt-in
  (`parallel = true`): `-t 1` vs `-t 2` vs `-t 4` wall time, measured not assumed; an
  overhead-bound negative result is a valid, recorded outcome.
- Population ladder: deterministic nested prefixes of the seeded full population (no re-tuning per
  rung), e.g. ~6 rungs from small to 784; ADMM iterations and wall time recorded per rung.
- Deliverable: CSV under `results/case_a_population/` + a new literate page following the
  Phase-35/39 measurement-artifact pattern.

### the agent's Discretion
- Exact ladder rung sizes, internal helper naming, CSV column layout, and the doc page's section
  structure within the patterns above.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.

### Specific Ideas (from CONTEXT)
- The thesis Case A population replaces the 1-house-per-bus rescaled proxy at its true size —
  continuity of calibrated fractions matters more than novel re-tuning (PROJECT.md v5.0 goal).
- Phase-39 carry-over: scenario-level `parallel` passthrough was deliberately deferred as a
  Phase-40 (POP-05) concern — decide during planning whether the scaling report drives solves via
  direct `solve_admm` calls (kwarg) or needs the Scenario seam; **kwarg-only is sufficient for a
  measurement script** (research confirms: `run(::ADMM, s)` at `src/experiments/run.jl:116-142`
  never passes `parallel`; direct calls are the only way to reach the executor today).

### Project Constraints (from CLAUDE.md — repo has no AGENTS.md; CLAUDE.md is the operative instructions file)
- Julia + JuMP; open-source solvers (Clarabel default conic; never hard-code a solver).
- Reproducibility: seeded data generation, pinned environment (Project.toml/Manifest.toml).
- Documentation of every modeling decision is a hard requirement (Documenter + Literate).
- v5.0 policies bind: **golden policy** (`:default` byte-identical; canary `iters = 56`,
  `welfare = -4823.66604824162` never re-pinned) and **honesty policy** (measured-not-assumed;
  failed certificates reported; the exactness gate is never loosened).
- Test invocation: `julia --project=. -e 'import Pkg; Pkg.test()'` only (never
  `julia --project=test ... @run_package_tests` — worktree-contamination hazard recorded in
  STATE.md).

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POP-01 | Build the true 784-house Case A population via a new selector; `:default` byte-identical | Additive branch at `build_population` (`materialize.jl:342`); widen `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)` (`Scenario.jl:48`); `:default` golden guarded by existing test `test_ieee8500.jl:216` ("bit-for-bit identical to its golden") and the ADMM canary |
| POP-02 | Per-house hash seeding, reproducible, collision-free | `sub_seed` idiom (`materialize.jl:24`) extended to `hash((seed, :house, bus, house_index))` reduced `typemax(UInt32)`; `generate_profiles(seed=…)` is bit-reproducible (`src/data/profiles.jl`); distinctness + rebuild-reproducibility tests |
| POP-03 | Household map (house → bus, aggregator, device set, PV/non-PV group) | Pure deterministic accessor; derivable from the same (seed, bus, index) tuple as the build; no `Aggregator` mutation; bus-level aggregator id = the house's bus (10 aggregators, see Architecture) |
| POP-04 | 784-house case solves centralized AND by ADMM, agreeing within measured tolerance | `solve_welfare` accepts any aggregator vector (`welfare_solve.jl:106`); `solve_admm` accepts the 10-aggregator roll-up (1:1 guard satisfied); agreement precedent `test_admm.jl:66-72` (welfare `rtol=1e-4`, price `atol=1e-2/rtol=1e-3` on a small fixture); centralized feasibility anchored by the 371k-var measured point (density_sweep_full.csv) |
| POP-05 | Scaling report: wall time vs threads, ADMM iterations vs population size, measured | `solve_admm(; parallel = true)` fail-loud kwarg; `iters = residuals.iters` in the return; subprocess-per-thread-count sweep (Threads.nthreads() is fixed at process start); nested-prefix ladder; Phase-35 CSV/literate artifact pattern |
| POP-06 | Composition documented with calibration provenance + unavailable thesis parameters | Composition measured from the built population (device counts, PV nameplate, Pdc totals, device nominal bounds); thesis targets on record (PV=5 MWp, elastic=6.5 MW, inelastic=1.5 MW — THEORY-thesis.md); unavailable: per-house appliance ownership, per-house PV sizing, per-node house counts (Appendix E IP-blocked) |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Population construction (784 houses → 10 bus aggregators) | API/Backend (`src/experiments/materialize.jl`) | — | Selector-dispatch seam already owns materialization; additive branch, no solver change |
| Scenario validation of the new selector | API/Backend (`src/experiments/Scenario.jl`) | — | Construction-invariant guard tuple `SCENARIO_VALID_POPULATIONS` |
| Per-house seeding | API/Backend (data layer: `src/data/profiles.jl` idiom) | — | Pure hash derivation + StableRNG profile draws; never the global RNG |
| Household map accessor | API/Backend (pure function) | — | Deterministic rebuild from primitives; no state, no mutation |
| Centralized solve (POP-04 leg 1) | API/Backend (`solve_welfare`, existing) | — | Already accepts arbitrary aggregator vectors |
| ADMM solve (POP-04 leg 2) | API/Backend (`solve_admm`, existing) | Phase-39 executor (`parallel = true`) | 1:1 node↔aggregator coupling satisfied by the bus roll-up |
| Threads sweep + population ladder | Measurement script (`scripts/`) | OS process layer (`julia -t N`) | Thread count is process-level; script spawns subprocesses |
| CSV artifacts | `results/case_a_population/` (committed) | — | Diff-friendly CSV convention; figures gitignored |
| Composition/calibration doc | Docs (new literate page + `docs/make.jl` registration) | — | Literate→Documenter pipeline is the project's hard documentation requirement |

## Standard Stack

### Core (all already in the project — ZERO new packages this phase)

| Library | Version (verified in Project.toml) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia | 1.12.5 local (`julia compat = 1.10`) [VERIFIED: codebase] | runtime | test/Manifest.toml resolves only on 1.12 (STATE.md hazard note); 1.12.5 is what CI's test leg pins |
| JuMP | 1.30.1 [VERIFIED: codebase] | modeling | existing; `Parameter` seams already anonymous-collision-safe |
| Clarabel.jl | 0.11.1 [VERIFIED: codebase] | conic QP/SOCP solves | duals-accurate IPM; Phase-39 spike proved threaded solves bitwise-equal under `-t 4` |
| StableRNGs | 1.0.4 [VERIFIED: codebase] | per-house profile RNG | `LehmerRNG` streams bit-stable across Julia versions (`src/data/profiles.jl` contract) |
| CSV.jl / DataFrames.jl | 0.10.16 / 1.8.2 [VERIFIED: codebase] | scaling-report CSV | Phase-35 artifact pattern |
| DrWatson | 2.19.1 [VERIFIED: codebase] | script provenance (`@quickactivate`, `projectdir`) | scripts convention (`scripts/thesis_caseA.jl:33-34`) |
| TestItemRunner | 1.1.5 (1.12 leg) / 1.3.x (1.10 leg) [VERIFIED: codebase] | `@testitem` + `tags = [:slow]` | existing tag split |

### Supporting
| Library | Purpose | When to Use |
|---------|---------|-------------|
| `TSODSO.extract_dlmp` / `welfare_accounting` (`src/pricing/`) | full-population price matrix + surplus split for the agreement measurement | POP-04 comparison metrics (precedent: `scripts/thesis_caseA.jl:84-87`) |
| `solve_admm` return fields `iters`, `residuals.*_trace`, `status`, `exact_maxgap` | scaling-report rows | POP-05 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bus-level roll-up (10 aggregators) | Generalize `solve_admm` to N aggregators per bus | Generalization is ACTOR-03 (Phase 44) territory; violates this phase's additive-only boundary; rejected |
| Direct `solve_admm` kwarg in script | Scenario-level `parallel` passthrough seam | Scenario identity deliberately excludes the executor (PAR-04); kwarg-only is sufficient for a measurement script (CONTEXT specifics); rejected |
| In-process thread sweep | Subprocess per `-t N` | In-process is impossible — `Threads.nthreads()` is fixed at process start; subprocess pattern already exists (`scripts/run_ieee8500_point.sh`, `scripts/flake_rate.jl`) |
| Thesis-MW-targeted calibration | `:default`-anchored per-house rescale | CONTEXT locks `:default`-fraction continuity; thesis MW targeting is Phase-42 ablation territory |

**Installation:** none. No new packages.

**Version verification:** all versions read directly from the repo's `Project.toml` `[compat]`
block this session (see table tags). No registry lookups needed — the phase installs nothing.

## Package Legitimacy Audit

**No external packages are installed in this phase** — the entire deliverable rides on the
pinned, already-vendored stack listed above (all present in `Project.toml` `[compat]` and
resolved in `Manifest-v1.12`/`test/Manifest.toml`). No slopcheck run required; no new
`checkpoint:human-verify` gates needed for installs.

## Architecture Patterns

### System Architecture Diagram

```
 Scenario(name, feeder=:ieee13, seed, T=24, population=:case_a_784, price=:mem, strategy)
     │
     ├─ seed ──► sub_seed(seed, :profiles) ──► generate_profiles(; T=24) ─┐
     │                                                                    │
     ├─ seed ──► sub_seed(seed, :population) = S_pop                      │
     │                │                                                   │
     │                ▼                                                   ▼
     │    build_population(:case_a_784, feeder, :ieee13, profiles, S_pop)
     │                │
     │     for bus in _load_buses (10 buses 2..11):
     │        for h in 1:n_bus[bus]:                        ← per-bus counts: proportional
     │            house_seed = Int(hash((S_pop, :house, bus, h))   to :default's [1×10]; residue
     │                                     % typemax(UInt32))     rule documented
     │            draw = generate_profiles(; seed = house_seed, T)   ← per-house (NOT seed+bus!)
     │            devices_h = [Thermostatic, Deferrable, PVBattery]  ← per-house seeded params
     │        Aggregator(bus, φ, vcat(devices of all houses at bus), Σ_h Pdc_h)
     │                │
     │                ▼
     │      Vector{<:Aggregator} (length 10 — ONE per load bus)
     │                │
     ├────────────────┼──────────────────────────────┐
     │                ▼                              ▼
     │   solve_welfare(feeder, CBF(), aggs;    solve_admm(...; ρ, maxiter,
     │     T=24, λ₀, allow_export=true)          parallel = true|false)
     │     → welfare_c, dlmp[10×24]             → welfare_a, λ[10×24],
     │                                            iters, residuals, status
     │                │                              │
     │                └──────────┬───────────────────┘
     │                           ▼
     │            agreement deltas (welfare, prices) ──► gate-then-golden :slow test
     │
     └── scripts/case_a_scaling.jl (+ per-threads shell driver)
            ├─ threads sweep: julia -t 1|2|4 driver → solve_admm(parallel=true) wall time
            ├─ ladder: nested prefixes (deterministic) → iters + wall per rung
            └─► results/case_a_population/*.csv ──► docs/literate/case_a_population.jl
                                                     (loads CSVs; tiny live slice only)
```

### Recommended Project Structure

```
src/experiments/materialize.jl        # + :case_a_784 branch, _case_a_house/_case_a_counts
                                      #   helpers, case_a_household_map accessor
src/experiments/Scenario.jl           # SCENARIO_VALID_POPULATIONS widened to (:default, :case_a_784)
test/test_population_case_a.jl        # NEW: build/map/seeding/distinctness/:default-identity tests
test/test_population_case_a_agreement.jl or :slow item in the above   # POP-04 (tags = [:slow])
scripts/case_a_scaling.jl             # NEW: ladder + agreement data producer (writes CSVs)
scripts/ (shell driver or self-spawn) # per-thread-count subprocess wrapper (-t 1/2/4)
results/case_a_population/*.csv       # committed measurement artifacts
docs/literate/case_a_population.jl    # NEW page; registered in docs/make.jl tuple + pages list
scripts/README.md                     # index entry for the new script (CI guard enforced)
```

### Pattern 1: Additive selector branch (the `:ieee8500_mv` precedent)

**What:** new `elseif` branch in `build_population`; unknown-selector `ArgumentError` terminal
branch updated; `:default` branch textually untouched.
**When to use:** every new materializer selector.
**Example** (existing shape, `src/experiments/materialize.jl:342-349`):

```julia
function build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer)
    if sym !== :default          # ← becomes: if sym !== :default && sym !== :case_a_784
        throw(ArgumentError("build_population: unknown population selector ..."))
    end
    ...
end
```

Note the current guard is `sym !== :default` with the throw INSIDE — the additive change
restructures this into the two-positive-selectors + terminal-throw shape that `build_feeder`
(`materialize.jl:35-52`) already uses. Keep `SCENARIO_VALID_POPULATIONS` and the
`build_population` error message text in sync (both are user-facing).

### Pattern 2: Per-house seed derivation (extends `sub_seed`)

```julia
# Source: src/experiments/materialize.jl:24 (existing idiom, extended per CONTEXT decision)
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))
# House-level: same reduction, richer tuple. S_pop is build_population's `seed` argument
# (already sub_seed(scenario_seed, :population) — the two-level derivation mirrors how
# :default derives its per-bus draws from S_pop).
house_seed = Int(hash((S_pop, :house, bus, house_index)) % typemax(UInt32))
```

**Critical:** the per-house profile draw MUST be `generate_profiles(; seed = house_seed, T)`.
The `:default` helper `_default_house` uses `generate_profiles(; seed = seed + bus, T)`
(`materialize.jl:222`) — under that idiom every house on the same bus would receive an
IDENTICAL profile draw. Do not reuse `_default_house` as-is; either give the new branch its own
house builder (recommended — keeps `:default` byte-identical by construction) or refactor
`_default_house` to accept a precomputed seed (higher golden risk, no benefit).

### Pattern 3: Threads sweep via subprocess (thread count is process-level)

```bash
# One process per thread count; the script reads ARG "threads" and calls
# solve_admm(...; parallel = (t > 1)) — parallel=true on nthreads()==1 throws (fail-loud).
for t in 1 2 4; do
  julia --project=. -t $t scripts/case_a_scaling.jl --threads $t --mode threads-sweep
done
```

The parallel executor (`solve_admm` docstring, `src/admm/solve_admm.jl:206-227`) pins
`BLAS.set_num_threads(1)` itself at executor entry and restores it on every exit path; the
serial `-t 1` leg should pin BLAS=1 in-script for row-to-row comparability (record
`Threads.nthreads()` and `BLAS.get_num_threads()` per CSV row, PAR-04 style — `result_to_dict`
already stamps these keys, `src/experiments/store.jl:207-208`).

### Pattern 4: Agreement measurement (precedent metrics)

`test/test_admm.jl:66-72` (small fixture): welfare `isapprox(res.welfare, obj_c; rtol = 1e-4)`;
prices `isapprox(vec(res.λ), vec(dlmp_c); atol = 1e-2, rtol = 1e-3)`. At full scale the observed
deltas are MEASURED FIRST, then the band is pinned from the measurement (gate-then-golden), so
the final constants will differ from this precedent — the precedent is the METRIC SHAPE, not the
numbers.

### Anti-Patterns to Avoid

- **Feeding 784 `Aggregator`s to `solve_admm`** — throws (`admm_phases.jl:67-74`); also breaks
  `run(::Centralized, s)`'s `sort!([a.bus for a in aggs])` price extraction (duplicate bus rows).
- **Touching the `:default` path or its helpers' numerics** — the golden at
  `test_ieee8500.jl:216` pins `build_population(:default, ...)` output field-by-field, and the
  ADMM canary pins `iters = 56 / welfare = -4823.66604824162`.
- **Solving the full 784 case live in the literate page** — the docs CI job has
  `timeout-minutes: 30` with a measured ≈6.8 min baseline (ieee8500_scaling.jl header note);
  load committed CSVs, solve only a tiny live slice.
- **Re-tuning ρ/tolerances per ladder rung** — CONTEXT locks "no re-tuning per rung"; the ladder
  must show the SAME configuration's iteration behavior as N grows.
- **Silent serial fallback in the sweep** — `parallel = true` on a 1-thread runtime throws
  (`solve_admm.jl:317-324`); the sweep script must fail loudly, never degrade.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reproducible per-house randomness | custom RNG/global `Random.seed!` | `StableRNGs` via `generate_profiles(seed=…)` | global RNG not version-stable; profiles.jl contract is bit-stable 1.10→1.12 [VERIFIED: codebase] |
| Seed derivation | ad-hoc mixing functions | `hash(tuple) % typemax(UInt32)` idiom | matches `sub_seed`; golden-stable empirically across 1.10/1.11/1.12 |
| Per-bus device roll-up | manual injection summation | `Aggregator(bus, φ, devices, ΣPdc)` + `contribute!` | the roll-up (eqs. 3.21-3.23), battery/4Q var stashing, and reactive bookkeeping already live there |
| Timing | hand-rolled clocks scattered | `@elapsed` + CSV row (Phase-35 harness style); subprocess wall time via `@elapsed` around the solve inside each driver process | provenance-consistent, comparable rows |
| Peak-RSS capture | guessing from GC stats | `run_ieee8500_point.sh` / `memory_profile.csv` VmHWM pattern (only if the report wants memory) | measured precedent exists |
| CSV writing | println-based CSV | CSV.jl | already a dependency; diff-friendly committed artifacts |
| Wall-clock budget honesty | ad-hoc timeouts | `solve_admm(...; time_limit_s = …)` → `status = :budget_exceeded` | built-in honest early-exit path (`solve_admm.jl:397-416`) |

**Key insight:** every hard part of this phase (roll-up semantics, duals extraction, threaded
equality, honest measurement exits) is already implemented and golden-tested. The phase's work is
composition and measurement discipline, not new machinery.

## Common Pitfalls

### Pitfall 1: The 1:1 node↔aggregator ADMM guard
**What goes wrong:** `solve_admm(feeder, pf, aggs_784)` throws
`ArgumentError("solve_admm assumes one aggregator per load node...")`.
**Why it happens:** `AdmmState.agr_by_bus::Dict{Int,AgrOpt}` and the λ/c/a consensus dicts are
keyed per load node; `_admm_build` enforces `length(aggregators) == length(load_nodes)`
(`admm_phases.jl:67-74`).
**How to avoid:** roll houses up into exactly 10 bus-level `Aggregator`s (devices concatenated,
`Pdc` summed). Centralized gives the identical mathematical problem either way (`add_to_residual!`
is additive per bus).
**Warning signs:** any plan task that says "build 784 aggregators" without the roll-up step.

### Pitfall 2: `seed + bus` profile idiom silently duplicates houses
**What goes wrong:** all ~78 houses on a bus get identical profiles/devices — the population is
secretly 10 houses repeated, and no test that only checks bus-level totals will notice.
**Why it happens:** `_default_house`'s per-bus idiom (`seed + bus`) is the only precedent in
`src/`.
**How to avoid:** per-house `hash((S_pop, :house, bus, h))` seeds (locked decision); add a test
asserting two houses on the SAME bus have different `Pdc`/device parameters.
**Warning signs:** identical `Pdc` vectors across houses of a bus.

### Pitfall 3: In-process threads sweep
**What goes wrong:** trying to measure `-t 1/2/4` in one Julia process — impossible;
`Threads.nthreads()` is set at startup only.
**How to avoid:** subprocess per thread count (Pattern 3). `parallel = (t > 1)`; the `-t 1` leg
uses the serial executor.
**Warning signs:** a single script process claiming to sweep threads.

### Pitfall 4: Exactness gate refusing the large centralized point
**What goes wrong:** `assert_socp_exact!` (default rtol 1e-4) throws `CertificateError` on the
784-house centralized solve at Clarabel's default `tol_gap = 1e-8` — a solver-precision artifact,
not model inexactness.
**Why it happens:** measured in-repo precedent: on degenerate fixtures the achievable cone
residual sits at the solver noise floor; the established fix tightens the SOLVER's
`tol_gap` (`select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)`), never the gate
(`test_admm.jl:44-50` note; STATE.md measurement-hygiene standing bar).
**How to avoid:** if the gate refuses, run the tol_gap ladder measurement first, document, then
tighten solver precision only. Honesty policy: a refusal with certificate is a valid recorded
outcome if genuine.
**Warning signs:** `CertificateError` with `kind === :socp_exact` on the first full-scale run.

### Pitfall 5: ADMM iteration blow-up at heterogeneous scale (C6)
**What goes wrong:** iterations balloon or ρ adaptation thrashes when houses-per-bus multiplies
heterogeneity; the canary already needs 56 iterations on 10 uniform one-house aggregators.
**Why it happens:** single global ρ fits heterogeneous agent scales poorly (research PITFALLS.md
C6); residual normalization `p_p = length(load_nodes)·T` counts slots, not agents.
**How to avoid:** this is precisely what the ladder measures — report iterations per rung
honestly; no per-rung re-tuning (locked); if maxiter=200 is hit, that is a measured finding (or
use `time_limit_s` for the honest `:budget_exceeded` path).
**Warning signs:** residual plateau in `residuals.primal_trace`; superlinear iters-vs-N.

### Pitfall 6: Threads-sweep negative/absent speedup misread as failure
**What goes wrong:** treating a null speedup as a bug and "fixing" the executor.
**Why it happens:** 10 bus subproblems on 4 cores with per-task JuMP/Clarabel overhead may be
overhead-bound (research SUMMARY: "small QPs may be overhead-bound"); Clarabel's default QDLDL
backend is single-threaded (PITFALLS.md C2 note).
**How to avoid:** CONTEXT explicitly blesses the negative result — record it. Pin
BLAS=1 consistently; keep `MOI.NumberOfThreads()=1` per AGR model (executor does this).
**Warning signs:** speedup < 1.2× at `-t 4`.

### Pitfall 7: Docs CI budget blown by the new page
**What goes wrong:** the literate page solves the full case at build time; docs job
(30-min timeout) fails.
**How to avoid:** committed-CSV pattern (ieee8500_scaling.jl precedent): page reads
`results/case_a_population/*.csv`, optional tiny live slice with a `time_limit`.
**Warning signs:** page containing a full-population `solve_welfare` call.

### Pitfall 8: Repo CI guard failures for "unregistered" files
**What goes wrong:** new script not in `scripts/README.md` index → `check_scripts_index.py` CI
failure; new exported symbol without docstring → `checkdocs = :exports` docs-build failure.
**How to avoid:** register the script in the README table; keep `case_a_household_map`
UNEXPORTED like `build_population` (`test_exports.jl:57` asserts the materializer group stays
unexported — callers qualify `TSODSO.case_a_household_map`).
**Warning signs:** CI red on format/scripts-index/docs jobs after an otherwise-green test run.

### Pitfall 9: Test-level soft-scope accumulator bugs
**What goes wrong:** loop accumulators in `@testitem` bodies silently don't update (module
top-level + soft scope), producing vacuous passing tests — hit the suite twice before.
**How to avoid:** `let`-wrap mutable scan state (the established fix idiom, runtests.jl header);
the authoritative detector is Julia's own "soft scope is ambiguous" warning over a full-suite log.
**Warning signs:** a test loop that passes no matter what the body does.

### Pitfall 10: JuliaFormatter docstring content loss
**What goes wrong:** JuliaFormatter 2.10.2 with `format_docstrings = true` silently deletes
docstring text when a wrapped inline code span's continuation line starts with `|` (STATE.md
standing hazard).
**How to avoid:** avoid wrapped `|`-leading continuation lines in new docstrings; run the
pinned formatter (92-col) on touched files and diff for content loss.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 | — (1.10 floor declared; test Manifest resolves on 1.12 only) |
| CPU threads for `-t 4` | POP-05 sweep | ✓ | 4 cores | `-t 2` leg still meaningful |
| RAM ≥ ~4 GB free | POP-04 centralized solve | ✓ (15 GB total; ~5 GB available at research time — other processes loaded) | — | ladder rungs measure incrementally; `time_limit_s` budget honesty |
| Clarabel 0.11.1 | all solves | ✓ | 0.11.1 | SCS 2.6.4 present but NEVER for certified prices/exactness (CLAUDE.md policy) |
| CSV.jl / DataFrames.jl | scaling report | ✓ | 0.10.16 / 1.8.2 | — |
| `results/` + `docs/` env | artifacts + page | ✓ | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test stdlib + TestItemRunner (1.1.5 on the 1.12 CI leg; 1.3.x on 1.10), `@testitem` + `tags` |
| Config file | `test/runtests.jl` + `test/runner_support.jl` (`TSODSO_TEST_SET = fast|slow|all`; expected_broken.txt guard); no per-test config file |
| Quick run command | `TSODSO_TEST_FILES=test_population_case_a.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (all); fast lane: `TSODSO_TEST_SET=fast ...`; slow lane: `TSODSO_TEST_SET=slow ...` |
| Current scale | 628 `@testitem`s in 101 files; CI runs the **fast** set only (60-min timeout); ~5 existing `:slow`-tagged items |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| POP-01 | `:case_a_784` builds 784 houses over 10 buses; total house count + per-bus counts match the documented rule | unit | `TSODSO_TEST_FILES=test_population_case_a.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 (`test/test_population_case_a.jl`) |
| POP-01 | `:default` byte-identical after the additive change | unit (existing golden re-run) | `TSODSO_TEST_FILES=test_ieee8500.jl,test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ (`test_ieee8500.jl:216` golden; canary item) |
| POP-02 | 784 house seeds distinct; rebuild is `==`-reproducible; same-bus houses differ | unit | same quick command (new item) | ❌ Wave 0 |
| POP-03 | `case_a_household_map` pure/deterministic: same inputs → identical map; fields bus/aggregator/device-set/PV-group present and consistent with the built population | unit | same quick command (new item) | ❌ Wave 0 |
| POP-04 | Full-population centralized vs ADMM welfare + prices within the MEASURED band | integration, `tags = [:slow]` | `TSODSO_TEST_SET=slow julia --project=. -e 'import Pkg; Pkg.test()'` (band pinned only AFTER the measurement script produces it — gate-then-golden) | ❌ Wave 0 (band constants Wave 1+, post-measurement) |
| POP-05 | Threads-sweep + ladder produce well-formed CSV rows (helper-level test on a TINY prefix: e.g. T=2, 2 rungs, serial only — fast) | unit/smoke | same quick command (new item) | ❌ Wave 0 |
| POP-05 | Actual sweep + ladder measurement | script (long-running, not a unit test) | `julia --project=. -t N scripts/case_a_scaling.jl --mode ...` per leg | ❌ Wave 0 (script) — result committed as CSV |
| POP-06 | Doc page exists, states composition + calibration provenance + unavailable App. E parameters; composition numbers match the committed CSV | docs build + reviewer check | `julia --project=docs docs/make.jl` (CI docs job) | ❌ Wave 0 (page) |

**Justifications for non-automated coverage:** POP-05's full measurement and POP-06's prose are
deliverables, not unit-testable behavior; their automated proxies are the CSV smoke test (POP-05
helper) and the docs build (POP-06) respectively.

### Sampling Rate
- **Per task commit:** quick command (new phase test file, file-scoped).
- **Per wave merge:** fast lane (`TSODSO_TEST_SET=fast`) — keeps CI-lane parity.
- **Phase gate:** full suite (`all`) green + `:slow` lane green (agreement test) + scripts-index
  and docs CI jobs green.

### Wave 0 Gaps
- [ ] `test/test_population_case_a.jl` — covers POP-01/02/03 + POP-05 smoke (new file)
- [ ] `scripts/case_a_scaling.jl` + threads driver — POP-05 producer (new file; register in `scripts/README.md`)
- [ ] `results/case_a_population/` — artifact directory + first committed CSVs
- [ ] `docs/literate/case_a_population.jl` + `docs/make.jl` registration (tuple + `pages`) — POP-06
- [ ] `SCENARIO_VALID_POPULATIONS` widening + `build_population` branch — the code under test
- No framework install needed (TestItemRunner et al. already wired).

## Code Examples

### The ADMM constraint that shapes the design (verified)
```julia
# Source: src/admm/admm_phases.jl:67-74
length(aggregators) == length(load_nodes) || throw(
    ArgumentError(
        "solve_admm assumes one aggregator per load node (got $(length(aggregators)) " *
        "aggregators for $(length(load_nodes)) load nodes); multi-aggregator-per-bus " *
        "coupling is not supported",
    ),
)
```

### Bus-level roll-up of per-house devices (shape — planners write the real thing)
```julia
# Per house: per-house seeded draw + existing device builder literals (:default house shape).
prof = generate_profiles(; seed = house_seed, T = T)      # per-house, NOT seed + bus
therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, Pmax_h, 0.5, _temperature_profile(T))
defer = Deferrable(bus, min(8, T), min(16, T), E_h, Pmax_dh, 0.5)
batt  = PVBattery(bus, 0.95, 1.0, pmax_h, 0.0, emax_h, soc0_h,
                  _DEFAULT_BATT_λ_MIN, _DEFAULT_BATT_λ_MED, _DEFAULT_BATT_λ_MAX,
                  Float64[pv_scale_h * p for p in prof.pv])
Pdc_h = Float64[load_scale_h * d for d in prof.demand]
# Bus-level aggregator: devices concatenated, inelastic demands summed.
Aggregator(bus, 0.90, reduce(vcat, house_devices), reduce(+, house_Pdcs))
```

### The two solve engines + iteration exposure (verified signatures)
```julia
# Source: src/models/welfare_solve.jl:106 / src/admm/solve_admm.jl:289-311
ctx, welfare_c, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs10;
                                  T = 24, λ₀ = λ₀, allow_export = true)
dlmp_c = extract_dlmp(ctx)[load_buses, :]              # (10, 24) — full price matrix
r = solve_admm(feeder, ConvexBranchFlow(), aggs10; T = 24, λ₀ = λ₀, ρ = ρ,
               parallel = true)                        # requires julia -t N, N > 1
r.iters          # ADMM iterations (residuals.iters) — the ladder's y-axis
r.status         # :converged | :budget_exceeded
r.exact_maxgap   # certified SOC cone residual at the converged point
```

### Literate page registration (verified — both sites required)
```julia
# Source: docs/make.jl — add to the Literate tuple AND the pages tree
for src in (..., "case_a_population.jl")   # tuple entry
...
"Experiments" => ["The Experiment Harness" => "generated/experiments.md",
                  "Case A Population (784 houses)" => "generated/case_a_population.md"],
```

## Runtime State Inventory

Omitted — this is an additive greenfield-selector phase, not a rename/refactor/migration.
(No stored-data keys, service configs, OS registrations, secret names, or build artifacts carry
a name this phase changes.)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Thesis: per-house ADMM subproblems (AGR-OPT per house) | This repo: per-BUS subproblems, houses rolled up inside | repo architecture since v1.0 ADMM | Parallelism is over 10 aggregators; speedup ceiling correspondingly modest — set expectations in the report |
| 1-house-per-bus rescaled proxy (10 houses) | True 784-house construction | this phase | Composition becomes house-realistic; thesis-MW matching stays a Phase-42 concern |
| Serial ADMM only | Phase-39 opt-in threaded executor (`parallel = true`), bitwise-equal to serial | Phase 39 (2026-10) | POP-05's instrument; Scenario identity deliberately executor-blind |

**Deprecated/outdated:** none affecting this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Per-house device magnitudes must be rescaled (recommend: `:default` per-house scale ÷ houses-per-bus, so bus totals match the validated `:default` regime); keeping raw `:default` per-house scales would put ~78× the calibrated load through a 6.86 MVA head branch and is almost certainly infeasible, which would make POP-04 unsatisfiable | Architecture / Open Questions | If the planner instead keeps raw scales, the first full solve will be infeasible or gate-refused — the ladder's small rungs will expose this early, but the phase wastes a cycle |
| A2 | PV/non-PV group: `:default` is 100%-PV (every house carries a `PVBattery`), so "keep `:default` fractions" read literally means all-PV; success criterion 2 and SETL-05 (Phase 41) both want the group field to exist — recommend a generic group field + a named PV-fraction constant whose default follows the locked decision (1.0), with the doc page stating the triviality honestly | Open Questions | If the user intends a <1.0 PV fraction, the composition doc and map change; cheap to change later if the field is generic from day one |
| A3 | Centralized 784-house solve fits host memory and ≤ a few minutes: ~134k vars estimated from 169 decision vars/house (Thermostatic 48 + Deferrable 24 + PVBattery 97, T=24) [VERIFIED: codebase var reads]; anchored on the measured 371k-var OPTIMAL-in-50 s point [VERIFIED: results/ieee8500_benchmark/density_sweep_full.csv] | Feasibility | If quadratic-objective density pushes Clarabel memory harder than the anchor suggests, the ladder surfaces it incrementally; `time_limit_s` + ladder provide the honest exit |
| A4 | Residue rule: since `:default` has exactly 1 house per bus (uniform), "largest buses first" has no size signal — the plan must define the tiebreak (recommend: descending `:default` per-bus `Pdc` sum at the scenario seed, tie-broken by ascending bus id; simpler alternative: plain ascending bus id) | Open Questions | Any deterministic documented rule satisfies POP-01; risk is only doc/plan ambiguity, not correctness |
| A5 | ADMM at 784 houses converges within maxiter=200 without re-tuning — UNKNOWN; thesis reported 28 iterations at this size, the repo canary needs 56 at 10 houses | Pitfall 5 | If it stalls, the honest outcomes are documented (raise maxiter as a measured finding, or `:budget_exceeded` with `time_limit_s`); never re-tune per rung (locked) |
| A6 | `hash` tuple stability across Julia versions (seed derivations are golden-bearing): already relied upon by pinned goldens; v1.0 carried an explicit deferred note on `sub_seed` cross-version hash stability | Pattern 2 | A future Julia version changing `hash` would move all seeds — accepted standing risk, unchanged by this phase |

## Open Questions (RESOLVED)

All four questions were resolved during planning and adopted in the phase plans; the original
recommendations stand as written below.

1. **Per-house magnitude scale (A1) — the phase's biggest modeling decision.**
   - What we know: CONTEXT locks *fractions* from `:default`, not absolute per-house magnitudes;
     `:default` per-house scales on IEEE-13 are ~300 kW inelastic / 3 MWp PV / large
     utility-capped flexible devices per bus-house; 78× replication is certainly infeasible on
     the 6.86 MVA head.
   - What's unclear: whether the user wants (a) bus-total-preserving per-house rescale
     (`:default` scale ÷ houses-per-bus — recommended; makes houses residential-scale and
     preserves the validated solve regime), (b) thesis-MW targeting (Phase-42 territory), or
     (c) something else.
   - Recommendation: (a), documented as calibration provenance in the doc page; confirm at
     plan review.
   - **Resolution:** option (a) adopted — `_case_a_house` divides the `:default` scales by
     houses-per-bus, rationale recorded in the docstring; implemented in **40-01 Task 1**,
     provenance documented in **40-04** (calibration section).

2. **PV/non-PV split realization (A2).**
   - What we know: `:default` is 100% PV; success criterion 2 requires the group field; Phase-41
     SETL-05 requires owner/non-owner proxy groups.
   - Recommendation: generic group field + named PV-fraction constant (default 1.0 per the
     locked decision, trivial-but-honest), so Phase 41 can lower the constant without redesign.
   - **Resolution:** adopted — generic `_case_a_pv_group` field plus named const
     `_CASE_A_PV_FRACTION = 1.0`; implemented in **40-01 Task 1**, triviality stated honestly
     in **40-04**.

3. **Residue tiebreak definition (A4)** — planner picks; document in the doc page either way.
   - **Resolution:** ascending bus-id tiebreak adopted — residue assigned to the first `r`
     buses in ascending bus-id order in `_case_a_house_counts`; implemented in **40-01 Task 1**,
     rule documented in **40-04**.

4. **ADMM configuration for the 784 point (A5):** start from the `ADMM()` defaults
   (ρ=100, ε_abs=1e-4, ε_rel=1e-3, maxiter=200) for BOTH the agreement run and every ladder rung;
   any change is a measured, documented move, never per-rung tuning.
   - **Resolution:** executor defaults adopted everywhere — ladder mode passes no ρ/maxiter/tol
     overrides (**40-02 Task 1**), agreement run uses executor defaults with non-convergence
     recorded honestly as the A5 escalation signal, not tuned away (**40-03 Task 1**; band
     pinning / phase-level stop in **40-03 Task 2**).

## Sources

### Primary (HIGH confidence)
- `src/experiments/materialize.jl` — `build_population`, `sub_seed`, `_default_house`/
  `_ieee8500_house` precedents, `_load_buses` (read in full)
- `src/experiments/Scenario.jl` — `SCENARIO_VALID_POPULATIONS`, validation guards, identity
- `src/admm/solve_admm.jl` + `src/admm/admm_phases.jl` + `src/admm/admm_state.jl` — signature,
  1:1 guard, executor contract, return fields, `iters`
- `src/models/welfare_solve.jl` — `solve_welfare` signature, gates, returns
- `src/devices/Aggregator.jl`, `Thermostatic.jl`, `Deferrable.jl`, `PVBattery.jl` — struct
  fields, constructor guards, decision-variable counts
- `src/data/profiles.jl` — StableRNG contract (read in full)
- `src/experiments/run.jl`, `src/experiments/store.jl` — Scenario seam, provenance keys
- `test/runtests.jl`, `test/runner_support.jl`, `test/expected_broken.txt` — tag split, guard
- `test/test_admm.jl`, `test/test_ieee8500.jl`, `test/test_scenario_pf.jl`,
  `test/test_exports.jl`, `test/test_experiments.jl` — agreement precedent, goldens, guard tests
- `docs/make.jl`, `docs/literate/ieee8500_scaling.jl` — page registration + CI-budget pattern
- `scripts/thesis_caseA.jl`, `scripts/README.md`, `scripts/run_ieee8500_point.sh` — Case A
  protocol, script conventions, subprocess measurement pattern
- `results/ieee8500_benchmark/density_sweep_full.csv` — the 371k-var centralized feasibility anchor

### Secondary (MEDIUM confidence)
- `.planning/research/THEORY-thesis.md` — thesis Case A totals (5 MWp / 6.5 MW / 1.5 MW, 28
  iterations, S_max 6.86 MVA), Appendix E unavailability
- `.planning/research/PITFALLS.md` (C2/C4/C6), `.planning/research/SUMMARY.md`,
  `FEATURES.md` — overhead-bound speedup risk, convergence-collapse risk, composition targets
- `.planning/STATE.md` — host memory wall history, test-invocation and formatter hazards

### Tertiary (LOW confidence)
- Absolute Clarabel runtime/memory for the ~134k-var point (extrapolated from the anchor;
  measured only at execution time)

## Metadata

**Confidence breakdown:**
- Seams/APIs (selector dispatch, executor, tests, docs): HIGH — every claim read from source this session
- Feasibility (POP-04 solves at all): MEDIUM-HIGH — measured in-repo anchor + var-count arithmetic
- Scale behavior (ADMM iterations, thread speedup): LOW-MEDIUM — genuinely unmeasured until the ladder runs; honesty policy covers it

**Research date:** 2026-10-24
**Valid until:** 2026-11-23 (repo seams are stable; re-verify only if Phase-39 code or CI moves)
