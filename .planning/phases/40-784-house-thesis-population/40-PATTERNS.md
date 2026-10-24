# Phase 40: 784-House Thesis Population - Pattern Map

**Mapped:** 2026-10-24
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9 (8 exact, 1 role-match)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/experiments/materialize.jl` (modify: `:case_a_784` branch + house builder) | service (materializer) | transform (seed → devices → aggregators) | same file: `build_feeder` dispatch shape + `_ieee8500_house` new-code-path precedent | exact |
| `src/experiments/materialize.jl` (modify: `case_a_household_map` accessor) | utility (pure accessor) | transform | `_load_buses` (pure selector-derived fn) + project NamedTuple idiom | role-match |
| `src/experiments/Scenario.jl` (modify: widen `SCENARIO_VALID_POPULATIONS`) | config (construction invariant) | validation | same file: existing selector-guard tuples + `ArgumentError` guards | exact |
| `test/test_population_case_a.jl` (new: fast items POP-01/02/03 + POP-05 smoke) | test (unit) | n/a | `test/test_admm.jl` `@testitem` shape; `test/test_experiments.jl` population items | exact |
| `test/test_population_case_a*.jl` (`:slow` agreement item, POP-04) | test (integration) | n/a | `test/test_admm.jl:79+` ieee13 crossval item (`tags = [:admm, :slow]`) | exact |
| `scripts/case_a_scaling.jl` (new: ladder + threads-sweep producer) | measurement harness script | batch (measure → CSV) | `scripts/profile_ieee8500_memory_attribution.jl` + `scripts/thesis_caseA.jl` header | exact |
| threads-sweep shell driver (new `.sh` or self-spawn) | script driver | batch / subprocess | `scripts/run_ieee8500_point.sh` | role-match |
| `results/case_a_population/*.csv` (new, committed) | data artifact | n/a | `results/ieee8500_benchmark/` keyed-CSV + upsert pattern | exact |
| `docs/literate/case_a_population.jl` (new) + `docs/make.jl` + `scripts/README.md` (modify) | docs / config | n/a | `docs/literate/ieee8500_scaling.jl` + `docs/make.jl` registration | exact |

---

## Pattern Assignments

### `src/experiments/materialize.jl` — `:case_a_784` branch (service, transform)

**Analog:** the same file. Two precedents to copy:

**(a) Selector-dispatch shape.** `build_population`'s current guard (lines 342-349) is
`sym !== :default` with the throw INSIDE — the additive change restructures into the
two-positive-selectors + terminal-throw shape `build_feeder` already uses (lines 35-52):

```julia
# Source: src/experiments/materialize.jl:35-52 (the TARGET shape)
function build_feeder(sym::Symbol)
    if sym === :ieee13
        return ieee13_modified()
    elseif sym === :ieee123
        return ieee123_modified()
    ...
    else
        throw(
            ArgumentError(
                "build_feeder: unknown feeder selector $(repr(sym)); expected :ieee13, " *
                ":ieee123, :ieee8500, or :ieee8500_mv",
            ),
        )
    end
end
```

**(b) Per-house device construction.** The 3-device house body to copy for `_case_a_house`
is `_default_house` (lines 209-253). Note the **seed idiom pitfall**: line 222 uses
`generate_profiles(; seed = seed + bus, T)` — the per-BUS idiom. Under it, every house on the
same bus gets an IDENTICAL draw. The new branch must seed per-house (see Shared Patterns).
The cleaner "new code path" precedent is `_ieee8500_house` (lines 256-306), whose docstring
explicitly states the body is "copied VERBATIM from `_default_house`" as a genuinely new
function rather than a parameterized modification:

```julia
# Source: src/experiments/materialize.jl:273-306 (new-code-path precedent)
function _ieee8500_house(bus::Int, kw_pu::Float64, profiles, seed::Integer, T::Int)
    prof = generate_profiles(; seed = seed + bus, T = T)   # ← REPLACE with per-house seed
    dev_scale = 1.0
    Ppv = Float64[kw_pu * p for p in prof.pv]
    Pdc = Float64[kw_pu * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5,
                         _temperature_profile(T))
    defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, 0.5 * kw_pu, 0.0, 2.0 * kw_pu, 1.0 * kw_pu,
                     _DEFAULT_BATT_λ_MIN, _DEFAULT_BATT_λ_MED, _DEFAULT_BATT_λ_MAX, Ppv)
    return Aggregator(bus, 0.90, [therm, defer, batt], Pdc)
end
```

**(c) Bus-level roll-up + return type.** `build_population` returns `Vector{<:Aggregator}`
(line 309 docstring; `:default` terminal return at 429-443). The 784 houses roll up into
exactly 10 bus-level `Aggregator(bus, φ, devices, Pdc)`s (devices concatenated, `Pdc`
summed) because of the ADMM 1:1 guard (see Shared Patterns). Scale constants live as module
`const`s (pattern: `_IEEE13_LOAD_SCALE` at lines 126-128); per-bus counts helper follows
`_load_buses` (lines 186-195): a pure function of validated selectors.

### `case_a_household_map` accessor (utility, transform)

**Analog:** `_load_buses` (materialize.jl:186-195) — pure, selector-derived, no state, no
mutation; returns a simple `Vector{Int}`. The household map returns richer data; the project's
idiom for that is the NamedTuple (`generate_profiles` returns `(; demand, pv)`,
profiles.jl:217; `read_sweep_csv` rows are NamedTuples, ieee8500_scaling.jl:143-157).
Per CONTEXT: fields per house = bus, aggregator id (= the house's bus), device-set symbol,
PV/non-PV group. **Keep UNEXPORTED** — see Shared Patterns (exports guard).

### `src/experiments/Scenario.jl` — selector validation (config)

**Analog:** same file. The tuple (line 48) and the guard shape (feeder guard shown; the
population guard deeper in the constructor is identical in shape):

```julia
# Source: src/experiments/Scenario.jl:45-48 (widen to (:default, :case_a_784))
"""
Valid `population` selectors a `Scenario` may name (dispatch target: `build_population`, materialize.jl).
"""
const SCENARIO_VALID_POPULATIONS = (:default,)

# Source: src/experiments/Scenario.jl:134-140 (guard shape — ArgumentError, never @assert)
        if feeder ∉ SCENARIO_VALID_FEEDERS
            throw(
                ArgumentError(
                    "Scenario: unknown feeder selector $(repr(feeder)); expected one of " *
                    "$(SCENARIO_VALID_FEEDERS)",
                ),
            )
```

Keep the tuple and `build_population`'s error message text in sync (both user-facing;
CONTEXT locks this). Materialization call site that consumes the selector — `run.jl:61-73`
(`_materialize`) — needs NO change; it already passes `s.population` through.

### `test/test_population_case_a.jl` (test, unit — fast items)

**Analog:** `test/test_admm.jl`. Item structure to copy: `@testitem` with explicit
`setup`/`tags`, `using TSODSO` + qualified unexported names inside, `isdefined` guard as
first assertion, heavily-commented measured constants:

```julia
# Source: test/test_admm.jl:25-33 (item skeleton)
@testitem "admm: cross-validation 2-bus welfare + DADP sign (crossval)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO
    using TSODSO: SOCP
    @test isdefined(TSODSO, :solve_admm)
```

Population-specific analogs exist in `test/test_experiments.jl` (scenario/population items,
lines 53/95 carry `tags = [:slow]` when they solve). Assertions needed (POP-01/02/03):
784 total houses via the map, per-bus counts match the documented rule, 784 distinct seeds,
rebuild `==`-reproducibility, same-bus houses differ in `Pdc`/device params (anti-Pitfall-2),
`build_population(:default, ...)` still golden (existing guard lives at
`test/test_ieee8500.jl:216`). **Soft-scope rule:** `let`-wrap loop accumulators in testitem
bodies (runtests.jl header convention; Pitfall 9 in RESEARCH.md).

### `:slow` agreement test item (test, integration — POP-04)

**Analog:** `test/test_admm.jl:79-130` — the ieee13 cross-validation item. Copy its exact
metric SHAPE; the constants are re-measured gate-then-golden (never copied):

```julia
# Source: test/test_admm.jl:79-80 (tags) and 129-130+ (both engines)
@testitem "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm, :slow] begin
    ...
    ctx_c, obj_c, _ = solve_welfare(feeder, ..., aggs; T = Th, λ₀ = λ₀,
                                    allow_export = true, optimizer = select_optimizer(...))

# Source: test/test_admm.jl:73-75 — THE METRIC SHAPE (numbers re-measured at 784 scale):
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match
        @test all(>(0), dlmp_c)                                  # dual-SIGN anchor: positive price
        @test isapprox(vec(res.λ), vec(dlmp_c); atol = 1e-2, rtol = 1e-3)   # DADP match
```

Price matrix extraction precedent (full population): `src/experiments/run.jl:101-102` —
`load_buses = sort!([a.bus for a in aggs]); dadp = extract_dlmp(ctx)[load_buses, :]`
(same idiom at `scripts/thesis_caseA.jl:84`). **Exactness-gate note:** if
`assert_socp_exact!` refuses the large centralized point, the fix tightens the SOLVER
(`select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)` — the pattern used at
test_admm.jl:58), never the gate (comment block at test_admm.jl:42-50 documents this
precedent in full).

### `scripts/case_a_scaling.jl` (measurement harness, batch)

**Analog A:** `scripts/profile_ieee8500_memory_attribution.jl` — header/usage/arg-parsing/
CSV-upsert conventions:

```julia
# Source: scripts/profile_ieee8500_memory_attribution.jl:1-12 (header: usage + CSV contract)
# scripts/profile_ieee8500_memory_attribution.jl ...
#   julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 10
# ...
# Prints one TSV line per stage and upserts rows into
# results/ieee8500_benchmark/memory_attribution.csv keyed by (fixture, density, T, stage, name)
# with `cols = :union` — re-runs replace their own rows and never drop others. ... a kill mid-run
# ... leaves the evidence rows it had already captured — a kill is a MEASURED OUTCOME, not a
# missing run (honesty policy).

# Source: lines 63-68 (DrWatson provenance + imports) and 95-108 (kv-flag arg parsing + fail-loud validation)
using DrWatson
@quickactivate "TSODSO"
using TSODSO, JuMP, CSV, DataFrames, StableRNGs
...
function attribution_main(args)
    global DENSITY = parse(Float64, parse_kv_flag(args, "--density", "0.1"))
    ...
    max_bounded >= 1 ||
        throw(ArgumentError("--max-bounded-iters must be ≥ 1 (got $max_bounded)"))
```

**Analog B:** `scripts/thesis_caseA.jl` — the Case A protocol itself (feeder, seed, T,
price, population build, both solve engines, price extraction, welfare accounting):

```julia
# Source: scripts/thesis_caseA.jl:33-40 (imports) and 56-69 (Case A constants + population)
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO: SOCP, build_feeder, build_population, build_price, problem_class, sub_seed
...
const T = 24
const SEED = 42
const FEEDER = build_feeder(:ieee13)
const PF = ConvexBranchFlow()
const λ₀ = build_price(:mem, T, nothing)
const load_buses = sort!([b.id for b in FEEDER.buses if !b.is_root])   # [2..11]
const aggs = build_population(
    :default, FEEDER, :ieee13,
    generate_profiles(; seed = sub_seed(SEED, :profiles), T = T),
    sub_seed(SEED, :population),
)

# Source: scripts/thesis_caseA.jl:82-88 (solve engines + surplus/dlmp extraction)
ctx_dadp, welfare_dadp, _ =
    solve_welfare(FEEDER, PF, aggs; T = T, λ₀ = λ₀, allow_export = true, τ = 1e-2)
dadp = extract_dlmp(ctx_dadp)[load_buses, :]
decomp = decompose_dlmp(ctx_dadp)
acct = welfare_accounting(ctx_dadp; T = T)
```

Per-research: direct `solve_admm(...; parallel = (t > 1))` kwarg calls (no Scenario seam);
pin `BLAS.set_num_threads(1)` in the serial leg; stamp `Threads.nthreads()` +
`BLAS.get_num_threads()` on every CSV row; `@elapsed` around each solve; ADMM rows record
`r.iters`, `r.status`, `r.exact_maxgap`. Ladder = deterministic nested prefixes of the same
seeded population, same ρ/tolerances at every rung (no re-tuning — locked).

### Threads-sweep shell driver (script driver, subprocess)

**Analog:** `scripts/run_ieee8500_point.sh` — one process per measurement point, label
validation, evidence files, CSV append:

```bash
# Source: scripts/run_ieee8500_point.sh:1-12 (contract header)
#!/usr/bin/env bash
# Per-process wrapper for ONE IEEE-8500 measurement point.
#
# usage: scripts/run_ieee8500_point.sh <label> -- <benchmark args...>
...
# One row is appended to results/ieee8500_benchmark/point_resources.csv. An OOM is a
# RECORDED OUTCOME: the wrapper exits 0 even when the point is killed; it exits nonzero
# only for wrapper misuse.
set -u
...
# Source: lines 24-29 (repo-root anchoring) and 85-92 (CSV header-on-create + append)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
...
if [ ! -f "$CSV" ]; then
  echo "run_label,rc,peak_rss_kb,..." > "$CSV"
fi
printf '%s,%s,...\n' ... >> "$CSV"
```

Phase-40 shape: `for t in 1 2 4; do julia --project=. -t $t scripts/case_a_scaling.jl
--threads $t --mode threads-sweep; done` — thread count is fixed at process start, hence
subprocess-per-leg. **No silent fallback:** `parallel = true` on a 1-thread runtime throws
(fail-loud); the driver must surface that, never degrade.

### `results/case_a_population/*.csv` (data artifact, committed)

**Analog:** `results/ieee8500_benchmark/` conventions — keyed rows (upsert-safe,
`cols = :union`), CSVs committed / figures gitignored, every figure in docs traces to a named
file + row key. Reader-side precedent: `docs/literate/ieee8500_scaling.jl:134-163`
(`read_sweep_csv` — Base-only parser, docs env pins minimal deps; NamedTuple rows with a
`num` tryparse helper). Provenance columns to mirror: thread count, BLAS threads, Julia
version, seed, mode, rung/point label.

### `docs/literate/case_a_population.jl` + `docs/make.jl` + `scripts/README.md` (docs/config)

**Analog:** `docs/literate/ieee8500_scaling.jl` — the Phase-35 measurement-artifact page.
Three conventions to copy:

**(1) Tiny live slice + precomputed CSVs, with the budget measured:**

```julia
# Source: docs/literate/ieee8500_scaling.jl:40-48 (the !!! note pattern)
# !!! note "Sized against a measured docs-build baseline, not guessed"
#     `julia --project=docs docs/make.jl` ... completed in **≈6.8 minutes** wall time. Against
#     the shared `timeout-minutes: 30` documentation CI job ... that leaves ≈23 minutes of real
#     headroom ... This live point's own Clarabel `time_limit` below is set to **90 s** ...
# Source: lines 105-124 ("This curve is precomputed, and deliberately so" + regeneration cmd)
```

**(2) Dated, attributed "Appended" section** (lines 216-223): every figure names its source
file and row key — the doc page's composition/calibration numbers must match the committed
CSVs exactly (POP-06).

**(3) Registration — BOTH sites in `docs/make.jl`:**

```julia
# Source: docs/make.jl:19-48 (Literate tuple — add "case_a_population.jl" here)
for src in (
    "toy_dc.jl",
    ...
    "experiments.jl",
)
# Source: docs/make.jl:94 (pages tree — add to the "Experiments" section)
        "Experiments" => ["The Experiment Harness" => "generated/experiments.md"],
```

Docs-env import style (ieee8500_scaling.jl:29-34): `using TSODSO` +
`using TSODSO: <unexported names>` + `using TSODSO.JuMP`, and CSV parsing with `Base` only
(no CSV/DataFrames in the docs env). **`scripts/README.md`** — add the new script row to the
index table (format: lines 22-24); the CI guard
(`.github/scripts/check_scripts_index.py`) fails on any unlisted `scripts/` file
(README lines 3-6, 87).

---

## Shared Patterns

### Per-house seed derivation (THE load-bearing seeding pattern)
**Source:** `src/experiments/materialize.jl:24` extended per CONTEXT (locked);
`src/data/profiles.jl:155-159, 206-211` (StableRNG contract)
**Apply to:** the `:case_a_784` branch, the household map, and both test/script consumers
```julia
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))
# House level — same reduction, richer tuple. S_pop = sub_seed(scenario_seed, :population):
house_seed = Int(hash((S_pop, :house, bus, house_index)) % typemax(UInt32))
prof = generate_profiles(; seed = house_seed, T = T)   # per-house. NEVER `seed + bus`
```
`generate_profiles` threads ONE `StableRNGs.LehmerRNG(seed)` through both walks and is
bit-reproducible across Julia 1.10/1.11/1.12; never `Random.seed!` (profiles.jl contract).

### Selector dispatch + fail-loud errors
**Source:** `src/experiments/materialize.jl:35-52`; `src/experiments/Scenario.jl:134-140`
**Apply to:** `build_population` restructure, new helpers, script arg validation
`throw(ArgumentError("...: unknown selector $(repr(sym)); expected ..."))` — positive
selector branches + terminal throw. Project-wide convention: `ArgumentError`, never
`@assert` (profiles.jl:44-46).

### The ADMM 1:1 roll-up constraint (shapes the whole construction)
**Source:** `src/admm/admm_phases.jl:67-74` (quoted in RESEARCH.md, verified)
**Apply to:** the `:case_a_784` branch — return exactly 10 bus-level aggregators
```julia
length(aggregators) == length(load_nodes) || throw(ArgumentError(
    "solve_admm assumes one aggregator per load node ..."))
# ⇒ Aggregator(bus, φ, reduce(vcat, house_devices), reduce(+, house_Pdcs))  per bus
```
Centralized (`solve_welfare`, welfare_solve.jl:106) accepts any aggregator vector either way.

### Gate-then-golden agreement metrics
**Source:** `test/test_admm.jl:73-75` (shape), 42-50 (never touch the gate, tighten the solver)
**Apply to:** the `:slow` POP-04 item — run both engines first, record observed welfare/price
deltas, then pin the band from the measurement.

### Measured-artifact honesty conventions
**Source:** `scripts/profile_ieee8500_memory_attribution.jl:11-18`; `scripts/run_ieee8500_point.sh:10-11`;
`docs/literate/ieee8500_scaling.jl:193-208`
**Apply to:** script + CSVs + doc page — a kill/refusal/budget-exceeded is a RECORDED
outcome (row with status + evidence), never dropped or retried into a pass; `time_limit_s`
gives the honest `:budget_exceeded` path; negative speedup is a valid result (CONTEXT-locked).

### Naming/exports discipline
**Source:** `test/test_exports.jl:57` — `(:build_feeder, :build_population, :build_powerflow,
:build_price, :sub_seed)` asserted ABSENT from exports
**Apply to:** `case_a_household_map` and all new helpers stay UNEXPORTED; callers qualify
(`TSODSO.case_a_household_map`). Docstrings on new public-facing functions follow the
existing docstring style (see `_load_buses`/`_default_house` — every src/ function documented,
including internals).

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `case_a_household_map` (part of materialize.jl) | utility / pure accessor | transform | No existing house→metadata accessor exists; compose from `_load_buses` (pure-function shape) + NamedTuple-return idiom (`generate_profiles`, `read_sweep_csv`). Planner defines exact return shape at discretion (CONTEXT). |

## Metadata

**Analog search scope:** `src/experiments/`, `src/data/`, `src/admm/` (via research line
refs), `test/`, `scripts/`, `docs/literate/`, `results/`
**Files read in full or in relevant part:** materialize.jl (488), Scenario.jl (140 of 405),
profiles.jl (220), run.jl (163), test_admm.jl (130 of 383), test_exports.jl (30-89),
thesis_caseA.jl (25-104), profile_ieee8500_memory_attribution.jl (1-130),
run_ieee8500_point.sh (94), scripts/README.md (103), docs/make.jl (128),
ieee8500_scaling.jl (300 of 534)
**Pattern extraction date:** 2026-10-24
