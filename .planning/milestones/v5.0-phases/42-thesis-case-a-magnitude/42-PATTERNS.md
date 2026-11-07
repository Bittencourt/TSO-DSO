# Phase 42: Thesis Case A Magnitude - Pattern Map

**Mapped:** 2026-10-26
**Files analyzed:** 6 (runner script, protocol doc, results CSVs, literate writeup + make.jl edits, test file)
**Analogs found:** 5 / 6 (no pre-registration precedent exists — discipline sources substituted)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/case_a_magnitude.jl` | measurement script (batch runner) | batch → CSV artifacts | `scripts/tariff_comparison.jl` | exact (role + data flow) |
| `results/thesis_case_a_magnitude/*.csv` | committed artifact | batch upsert | `results/settlement_comparison/*.csv` + `results/case_a_population/*.csv` | exact |
| `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` | pre-registration doc | — | **no analog** (first pre-registration in repo) | none — use discipline sources |
| `docs/literate/<case-a-magnitude page>.jl` (or Appended section) | literate writeup | transform (CSV → rendered) | `docs/literate/settlement_equity.jl` + `docs/literate/case_a_population.jl` | exact |
| `docs/make.jl` (modify, 2 sites) | config | — | itself (phase 41 edit) | exact |
| `test/test_case_a_magnitude.jl` | test | in-process | `test/test_settlement.jl` | exact |

---

## Pattern Assignments

### `scripts/case_a_magnitude.jl` (script, batch → CSV)

**Primary analog:** `scripts/tariff_comparison.jl` (586 lines, Phase 41)
**Secondary analogs:** `scripts/case_a_agreement.jl` (the precision ladder), `scripts/case_a_scaling.jl` (upsert/ladder origin), `scripts/thesis_case123_repro.jl` (sign-safe gain)

**What to copy — DrWatson scaffold + explicit TSODSO imports** (`tariff_comparison.jl:62-89`):

```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    SolveFailedError,
    UnconvergedAdmmError,
    _CASE_A_PV_FRACTION,
    _CASE_A_TOTAL_HOUSES,
    ...
    build_feeder,
    build_population,
    build_price,
    case_a_household_map,
    compare_tariffs,
    generate_profiles,
    solve_welfare,
    sub_seed
using CSV
using DataFrames: DataFrame, eachrow
using LinearAlgebra: BLAS
```

**What to copy — kv-flag parsing with validating `parse_args!`** (`tariff_comparison.jl:106-141`; identical helper in `case_a_agreement.jl:130-135`, `case_a_scaling.jl:106-111`):

```julia
function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    mode = let m = parse_kv_flag(args, "--mode", "ieee13-ground")
        (m in ("ieee13-ground", "case-a-784")) || throw(ArgumentError(...))
        m
    end,
    ...  # every flag validated inline; misuse = ArgumentError, exits nonzero
)
```

Rung/axis-value validation precedent (`case_a_agreement.jl:146-155`): the flag value must be a key of the pre-planned Dict or it throws listing the permitted values — copy this shape for ablation axis names.

**What to copy — honest solver-outcome recording, caught BY TYPE** (`tariff_comparison.jl:163-195`, `run_compare_outcome`):

```julia
function run_compare_outcome(compare::Function)
    local res; local status::String; local message::String; local iters
    try
        res = compare()
        return (; ok = true, res, status = "ok", message = "", iters = missing)
    catch err
        if err isa ConvergenceError || err isa CertificateError || err isa SolveFailedError
            status = "error:" * string(nameof(typeof(err)))
            message = first(string(err.msg), 400)
            iters = err.iterations === nothing ? -1 : Int(err.iterations)
        elseif err isa UnconvergedAdmmError
            status = "error:unconverged_admm"   # typed budget-stop guard, caught by type
            message = first(string(err.msg), 400)
            iters = missing
        else
            rethrow()   # misuse/bugs propagate and exit nonzero
        end
        ...
    end
end
```

Variants to reuse: `run_solve_outcome` (`case_a_scaling.jl:152-173`) for bare `solve_admm`/`solve_welfare` calls; `run_centralized` (`case_a_agreement.jl:200-240`) for the centralized cross-check leg — it tightens the SOLVER (`select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)`) on a `CertificateError` and NEVER a gate, recording `path` in the row.

**What to copy — the AGR precision ladder as a pre-planned script Dict** (`case_a_agreement.jl:106-126`) — the CONTEXT-locked refusal-handling answer:

```julia
const AGR_TOL_RUNGS = Dict{String, Union{Nothing, NamedTuple}}(
    "default"       => nothing,
    "gap_1e-10"     => (tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
    "gap_1e-12"     => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12),
    "gapfeas_1e-12" => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12,
                        tol_feas_abs = 1e-12, tol_feas_rel = 1e-12),
)
```

Policy baked into the analog: STOP-ON-FIRST-CERTIFIED, hard stop after last rung, rung names are plain **strings** (`:gap_1e-10` would parse as subtraction — `case_a_agreement.jl:22-24, 89-91`). The default rung splats NOTHING — the call stays byte-identical; a tightened rung threads `agr_optimizer = select_optimizer(QP(); rung_attrs...)` via conditional NamedTuple splat (`case_a_agreement.jl:271-285`). **Adapt:** the same Dict-of-rungs idiom generalizes to the OFAT ablation axes (each axis a pre-planned Dict of fixed values, committed pre-run; adding a value requires editing the script — the deliberate-act friction).

**What to copy — locked ρ and frozen configuration** (`tariff_comparison.jl:495-508`):

```julia
function caseA_main(T_H::Int, seed::Int, time_limit_s::Real)
    BLAS.set_num_threads(1)                                   # row-to-row comparability
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    ρ = ADMM().ρ   # the executor default — the locked no-re-tuning configuration
    aggs = build_population(:case_a_784, feeder, FEEDER_SYM, profiles,
                            sub_seed(seed, :population))
    map_rows = case_a_household_map(feeder, FEEDER_SYM, seed)
    houses = case_a_houses_flat(feeder, T_H, seed)
```

Per-house reconstruction `case_a_houses_flat` (`tariff_comparison.jl:471-493`) + the **drift tripwire** asserted before any solve (`tariff_comparison.jl:511-518`) — this fail-loud `error(...)`-before-solve guard is also the closest pattern for the **protocol-file-exists guard**:

```julia
length(houses) == length(map_rows) || error(
    "case-a-784: ... the reconstruction drifted from case_a_household_map (aborting loudly)")
```

**Adapt for Phase 42:**
- **Protocol guard (new):** `isfile(PROTOCOL_PATH) || error(...)` at the top of the case-a/ablation mains, before ANY solve — copy the tripwire's fail-loud shape above.
- **Seed spread (new):** the analogs pin a single seed (`const SEED = 42` / `mode_seed`). Phase 42 loops master seeds `(42, 43, 44, 45, 46)`; each iteration re-derives profiles/population via `sub_seed(master, :profiles)` / `sub_seed(master, :population)` (POP-02 hash seeding makes each a full honest re-draw). Keep `mode_seed`-style override (`tariff_comparison.jl:146-147`) with 42 as the registered default.
- **Headline gain (new computation, existing precedent):** the SIGN-SAFE form from `thesis_case123_repro.jl:337` — `100 * (welfare_dadp - fb.social_fit) / abs(fb.social_fit)`; report `ΔW = W_DADP − W_FIT` alongside. The naive ratio `welfare_dadp / welfare_fit` is BANNED (`thesis_case123_repro.jl:16-22, 308-311`; `thesis_caseA.jl:144` shows the ratio only as the banned-shape example).
- **Engines:** `compare_tariffs(...; engine = :admm, ρ, houses, map_rows, time_limit_s)` for the four-leg settlement (`tariff_comparison.jl:526-538`) + `solve_welfare` centralized cross-check (`case_a_agreement.jl:202-203`: `ctx, welfare, _ = solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)`). FIT leg unchanged (`fit_baseline`, `src/pricing/fit.jl:382`; consumed via documented `optimizer`/`on_inexact` kwargs only). Surplus-split lens via `welfare_accounting(ctx; T = T)` (`src/pricing/welfare.jl:71`; usage `thesis_case123_repro.jl:253`).
- **Console discipline:** `println` + `flush(stdout)` before/after each leg (`case_a_scaling.jl:307-311`); `wall_s = @elapsed outcome = ...` timing (`tariff_comparison.jl:526`).
- **Entry guard** (`tariff_comparison.jl:584-586`): `if abspath(PROGRAM_FILE) == @__FILE__; main(ARGS); end`.

---

### `results/thesis_case_a_magnitude/*.csv` (committed artifacts, batch upsert)

**Analogs:** `results/settlement_comparison/*.csv` (Phase 41), `results/case_a_population/*.csv` (Phase 40)

**Observed schemas (real headers):**

- `tariff_comparison.csv`: `tariff, engine, status, notes, welfare, total_payments, fairness_total, merchandising_surplus, dso_total, aggregators_total, wholesale_total, feasibility_status, n_thermal_violations, n_voltage_violations, max_overload_ratio, batt_ok, batt_refused, batt_not_checked, gini_*/theil_*/atkinson_*/palma_* (bills+surplus+excluded counts), rebound_amount, rebound_ratio, bills_granularity, julia_version, threads, blas_threads, t_horizon, mode, seed, iters` — note `mode`/`seed`/`iters` sit at the END: that is `cols = :union` schema evolution, live in the committed file. The `case-a-784 (run)` row (line 6) is the committed honest-refusal precedent: `status = "error:CertificateError"`, certified columns empty, `feasibility_status = "not_run"`, `iters = 80`, note flattened.
- `scaling_ladder.csv`: `mode, rung_label, fraction, julia_version, threads, blas_threads, seed, t_horizon, houses_actual, aggregators, iters, status, welfare, exact_maxgap, wall_s` — one row per rung, `status` carries `"converged"` or `"error:<Type>"`.
- `agreement.csv`: `julia_version, seed, t_horizon, houses, aggregators, centralized_optimizer, welfare_centralized, welfare_admm, welfare_abs_delta, welfare_rel_delta, price_max_abs_delta, price_max_rel_delta, admm_iters, admm_status, admm_exact_maxgap, recommended_*, agr_tol` — the committed row itself shows the refusal (`welfare_*_delta` empty, `admm_status = "error:CertificateError"`, `admm_iters = 80`, `centralized_optimizer = "tol_gap_1e-10"`, `agr_tol = "default"`).

**What to copy — the upsert idiom** (`tariff_comparison.jl:206-220`; origin `case_a_scaling.jl:184-198`; coalescing variant `case_a_agreement.jl:169-186`):

```julia
function upsert_row(path::String, row::NamedTuple; key::NTuple{N, Symbol} where {N})
    mkpath(OUT_DIR)
    new = DataFrame([row])
    df = if isfile(path)
        old = CSV.read(path, DataFrame)
        keyof(r) = Tuple(r[c] for c in key)
        new_keys = Set(keyof(r) for r in eachrow(new))
        keep = filter(r -> !(keyof(r) in new_keys), old)
        vcat(keep, new; cols = :union)
    else
        new
    end
    CSV.write(path, df)
    return nothing
end
```

**What to copy — ensure-schema before the run-failure branch** (WR-04, `tariff_comparison.jl:244-248, 327-336`):

```julia
function ensure_schema(path::String, cols::Vector{Symbol})
    mkpath(OUT_DIR)
    isfile(path) || CSV.write(path, DataFrame([Any[] for _ in cols], cols))
    return nothing
end
# ensure_all_schemas() is called BEFORE the !outcome.ok branch in every mode:
# header-only tables must exist on every exit path.
```

Column lists as `const <NAME>_COLS = Symbol[...]` (`tariff_comparison.jl:250-325`).

**What to copy — provenance stamp + note hygiene** (`tariff_comparison.jl:222-234`):

```julia
provenance_row(T_H::Int, seed::Int) = (
    julia_version = string(VERSION),
    threads = Threads.nthreads(),
    blas_threads = BLAS.get_num_threads(),
    seed = seed,
    t_horizon = T_H,
)
flatten_note(s) = replace(replace(String(s), '\n' => "; ", '\r' => ""), '"' => "'")
```

**What to copy — the `(run)` status-row writer** (`tariff_comparison.jl:379-403`): tariff = `"(run)"`, certified values `missing`, `feasibility_status = "not_run"`, iterations from the error. **Adapt:** same shape for per-seed and per-ablation-point failure rows (tariff/seed/rung columns carry the identity; the key tuple gains the axis columns, e.g. `(:mode, :seed, :axis, :point, :t_horizon)` — mirror `case_a_agreement.jl:428` which keys on `(:julia_version, :seed, :t_horizon, :agr_tol)`).

---

### `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` (pre-registration)

**No analog exists.** `find .planning -iname "*PROTOCOL*"` returns nothing; no VALIDATION.md exists anywhere in the repo. This is the repo's FIRST pre-registration document.

**Discipline sources to model it on:**
- `scripts/case_a_agreement.jl:4-10` header — "MEASUREMENT FIRST (gate-then-golden)" framing: constants derived from committed measurements, never pre-loosened.
- `.planning/PROJECT.md:106` — "gate-then-golden on the DSO-surplus sign flip" as the established project discipline.
- `scripts/case_a_agreement.jl:106-115` — the rung table format (`| step | rung name | attrs | rationale |`) is a good template for freezing axis values with rationale.
- `test/test_settlement.jl:6-8` — "every tolerance is either algebraically exact or 10× a value measured live on this exact fixture, with the measured value cited at the pin site. NEVER invent a constant."

**What the protocol must contain (from CONTEXT decisions, already fixed):** the frozen registered configuration (`:case_a_784` over `:ieee13`, `ConvexBranchFlow()`, T=24, λ₀=`build_price(:mem)`, `allow_export=true`, both `sub_seed` derivations, ρ=`ADMM().ρ`), the sign-safe gain definition `100·(W_DADP−W_FIT)/|W_FIT|` + absolute ΔW, the master-seed set {42,43,44,45,46}, the AGR ladder rungs (the `AGR_TOL_RUNGS` values), the four OFAT axes AND their exact values, the no-tuning guard (structural: axes committed pre-run; every intermediate row committed; post-hoc constants require a protocol-amendment commit), and the honesty framing (refusal/infeasible FIT = recorded measured outcome). **The enforcing mechanism is the script-side guard** the planner must specify: `scripts/case_a_magnitude.jl` asserts the protocol file exists (fail-loud) before any Case A run; the protocol commit precedes the run commit (success criterion 1).

---

### Literate writeup + `docs/make.jl` (config, 2 registration sites)

**Analog page:** `docs/literate/settlement_equity.jl` (337 lines, Phase 41 — the closest: live slice + committed-CSV sections); **secondary:** `docs/literate/case_a_population.jl` (the Appended-section precedent, line 429).

**Site 1 — the Literate tuple** (`docs/make.jl:19-58`): add the new source filename to the tuple, with a preceding comment block explaining the page's live/precomputed split, exactly as `settlement_equity.jl` was added (lines 53-57). **Site 2 — the `pages` list** (`docs/make.jl:104-108`): `"Settlement, Tariffs & Equity" => "generated/settlement_equity.md"` under `"Experiments"` — a new page gets the same two-line treatment.

**What to copy — page structure** (`settlement_equity.jl:1-33`): H1 title; module-level framing paragraphs (what the page documents, which requirements); a `!!! note` carrying any locked statement; then "## The live slice" — a seconds-scale executable block — followed by sections that **read the committed CSVs** (line 125: "## The 784-house comparison — read from the committed CSVs"). The precomputed-results pattern is load-bearing: the full 784-house run exceeds docs-build budget, so the page reads `results/thesis_case_a_magnitude/*.csv` exactly as committed (page header states this explicitly, lines 12-15).

**What to copy — the dated Appended section** (`settlement_equity.jl:330-337`; origin `case_a_population.jl:429`):

```markdown
# *(Appended 2026-10-26. The live slice executes at docs-build time ... The 784-house
# sections read `results/settlement_comparison/*.csv` exactly as committed by
# `scripts/tariff_comparison.jl`: one row per tariff per mode with provenance ...)*
```

CONTEXT allows either a new page or a dated "Appended" section — both analogs exist. **Adapt:** derived percentages (`Δ%`, spread, ablation effects) must be **recomputed live from the committed rows** inside the page (Division → `@printf`), never restated as literals — the Phase-28 CR-01 discipline whose failure story is documented in `thesis_case123_repro.jl:34-44` (the stale ≈+0.045% incident). The sign-safe division in the page must itself use `abs(denominator)`.

**Also copy:** the "directional qualifier" convention (`thesis_case123_repro.jl:72-73`, `const REPRO_QUALIFIER` + `cite_repro(x)`) — adapt as a single qualifier constant for every magnitude number printed; and the A1-asymmetry statement pattern (`settlement_equity.jl:305-315` "The A1 asymmetry — the FIT leg is batteryless, and it shows") for the required writeup statement.

---

### `test/test_case_a_magnitude.jl` (test)

**Analog:** `test/test_settlement.jl` (1,470 lines, Phase 41)

**What to copy — file header + TestItem structure** (`test_settlement.jl:1-11`):

```julia
# Seam: ... Item names contain "settlement" so the
# `occursin` filters select them; the real-run item is additionally tagged `:slow`.
# Measured pins follow the gate-then-golden discipline (40-06 precedent): every tolerance
# is either algebraically exact or 10× a value measured live on this exact fixture ...
# NEVER invent a constant.

@testitem "settlement ledger: 2-bus DADP run — exact conservation, ..." tags =
    [:settlement] begin
    using TSODSO
    ...
end
```

**What to copy — `:slow` real-run items** (`test_settlement.jl:327-328, 1412-1413`):

```julia
@testitem "settlement ledger: IEEE-13 ground real-run identity — centralized AND ADMM" tags =
    [:settlement, :slow] setup = [IEEE13Fixtures] begin
```

Any item running a full-population solve gets `:slow` (CONTEXT-locked); hermetic/structural items stay untagged-slow. Item names must contain the stem the `occursin` filters select — name them with "case-a-magnitude" / "magnitude".

**What to copy — env selection contract** (`test/runtests.jl:40-48`): `TSODSO_TEST_SET` = `fast | slow | all` (unset = all; other values error); `TSODSO_TEST_FILES=a.jl,b.jl` restricts by basename; zero selection fails. Items that need TSODSO import it explicitly (no implicit `using TSODSO` — `runtests.jl:60-63`). Invocation is always `julia --project=. -e 'import Pkg; Pkg.test()'` (CONTEXT-established convention; the literate pages end with this snippet — `settlement_equity.jl:325-327`).

**Phase-42 test content (structural invariants only, per CONTEXT):** (1) sign-safety of the gain definition on negative-welfare fixtures (fixture: welfare ≈ −3.78e5 shape; assert the naive ratio would flip sign but the registered formula does not); (2) ledger conservation on measured runs; (3) the protocol-file-exists guard (assert the script errors when the protocol is absent — a fail-loud tripwire test). NO golden on the measured magnitude.

---

## Shared Patterns

### Honesty-policy status rows (apply to runner + CSVs + tests)
**Source:** `tariff_comparison.jl:38-48, 163-195, 379-403`; `case_a_scaling.jl:42-51`
`ConvergenceError` / `CertificateError` / `SolveFailedError` / `UnconvergedAdmmError` become `"error:<TypeName>"` status rows (iters from the error, −1 sentinel, certified values `missing`, `feasibility_status = "not_run"`, notes flattened via `flatten_note`); misuse errors `rethrow()` and exit nonzero. A refusal is answered ONLY by the pre-registered `AGR_TOL_RUNGS` ladder via `solve_admm`'s `agr_optimizer` seam; a FIT-leg failure is a status row answered only by the documented `fit_optimizer` passthrough. Gates, battery τ, and ρ are never touched.

### Upsert CSV contract (apply to every artifact CSV)
**Source:** `tariff_comparison.jl:206-248`; `case_a_scaling.jl:184-198`
`upsert_row` keyed on provenance identity with `cols = :union`; `ensure_schema`/`ensure_all_schemas` hoisted BEFORE the run-failure branch (WR-04); header-only table = "ran and certified nothing"; a kill mid-run leaves captured rows (a kill is a measured outcome).

### Provenance stamp (apply to every row)
**Source:** `tariff_comparison.jl:222-228`
`julia_version, threads, blas_threads, seed, t_horizon` on every row; script adds its own identity columns (`mode`, `axis`, `rung`, `seed`); BLAS pinned to 1 at main start.

### Seed handling (apply to runner + protocol)
**Source:** `tariff_comparison.jl:91-98, 138-147`; `case_a_scaling.jl:87`; CONTEXT decision
Master seeds {42 primary/registered, 43, 44, 45, 46}; households re-derive via `sub_seed(master, :profiles)` / `sub_seed(master, :population)`; seed 42 stays the continuity anchor with all prior Case A artifacts. Per-mode/per-seed defaults + `--seed` override pattern at `tariff_comparison.jl:143-147`.

### Pre-planned Dict = the only permitted values (apply to ladder + ablation axes)
**Source:** `case_a_agreement.jl:106-126, 146-155`
Rung/axis values live as strings in a script Dict; validation throws listing permitted values; adding a value requires editing the script (deliberate-act friction); stop-on-first-certified; hard stop after the last rung; every intermediate row is committed (no cherry-picking).

### Locked configuration (apply to runner)
**Source:** `tariff_comparison.jl:98-101, 500`; `case_a_scaling.jl:97, 102`
`ρ = ADMM().ρ` (a REQUIRED kwarg — the executor default, never re-tuned); `FEEDER_SYM = :ieee13`, `PRICE_SYM = :mem`, `T = 24`; population axis values from `DEFAULT_LADDER_FRACTIONS = (1/78, 0.125, 0.25, 0.5, 0.75, 1.0)` (`case_a_scaling.jl:97`) — the nested-prefix rungs REPRO-05's population axis reuses.

### Fail-loud guards (apply to protocol guard + drift tripwires)
**Source:** `tariff_comparison.jl:511-518`; `case_a_agreement.jl:341-346`
`cond || error("... (aborting loudly)")` before any solve: protocol file exists; house/map alignment; population shape (3 devices/house ⇒ `_CASE_A_TOTAL_HOUSES`).

### Naming & commit conventions (apply everywhere)
- **Scripts:** snake_case `case_a_*.jl` family — `scripts/case_a_magnitude.jl` continues `case_a_scaling.jl` / `case_a_agreement.jl`.
- **Modes/flag values:** kebab-case strings (`"case-a-784"`, `"ieee13-ground"`, `"threads-sweep"`); flags `--kebab-case`.
- **Results dir:** snake_case `results/thesis_case_a_magnitude/` (matches `results/thesis_caseA/`, `results/case_a_population/`).
- **Phase dir/doc:** `42-thesis-case-a-magnitude/` (kebab, zero-padded); protocol doc `42-CASE-A-PROTOCOL.md` (CONTEXT-locked path).
- **Plans:** zero-padded `42-01`, `42-02`, …; plan-scoped commits `feat(42-01): ...` (precedent `df14122 docs(41-04): ...`).
- **Commits:** Conventional Commits with phase scope — `feat(42): ...`, `fix(42): WR-05 — <what and why>`, `test(42): ...`, `docs(42): ...` (see `git log`: `0e6c7ca fix(41): WR-05 — typed UnconvergedAdmmError replaces :converged message-sniffing; ...`). The protocol commit must be its OWN commit before the run executes (success criterion 1).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `42-CASE-A-PROTOCOL.md` | pre-registration doc | — | First pre-registration in the repo — no PROTOCOL or VALIDATION.md exists anywhere. Model on the gate-then-golden/MEASUREMENT-FIRST discipline (`case_a_agreement.jl:4-10`, `PROJECT.md:106`, `test_settlement.jl:6-8`) and the rung-table freeze format (`case_a_agreement.jl:106-115`). |
| Multi-seed spread aggregation (mean + min–max per seed set) | computation | batch | All existing scripts pin one seed. The loop over master seeds with per-seed rows + aggregated spread row is new; per-seed rows reuse the upsert idiom unchanged. |
| OFAT ablation axis runner | computation | batch | `AGR_TOL_RUNGS` is the only pre-planned-value-Dict precedent (one axis, 4 rungs); generalizing to four axes with a per-axis key column is a mechanical extension, not a copy. |

## Metadata

**Analog search scope:** `scripts/`, `results/settlement_comparison/`, `results/case_a_population/`, `docs/literate/`, `docs/make.jl`, `test/`, `.planning/`
**Files read in full:** `tariff_comparison.jl` (586), `case_a_agreement.jl` (439), `case_a_scaling.jl` (443), `thesis_case123_repro.jl` (417), `docs/make.jl` (142), `settlement_equity.jl` (partial: 1-80, 283-337), `test_settlement.jl` (header + item index), `runtests.jl` (30-84)
**Files scanned:** results CSV headers; `thesis_caseA.jl` (targeted grep: FIT welfare construction at 142-145 — includes the banned ratio shape); `.planning/` protocol search (empty); `git log` commit style (15 commits)
**Pattern extraction date:** 2026-10-26
