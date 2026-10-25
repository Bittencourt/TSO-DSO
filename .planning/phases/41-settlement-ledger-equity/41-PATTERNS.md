# Phase 41: Settlement, Ledger & Equity - Pattern Map

**Mapped:** 2026-10-24
**Files analyzed:** 12 (6 new `src/settlement/` files, 2–3 new test files, 1 script, 1 literate page, 2 modified configs)
**Analogs found:** 10 / 12 file groups (equity-metric math and rebound have no codebase analog — new math, guarded by known-value certificates per RESEARCH.md Pattern 5)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/settlement/SettlementLedger.jl` | model (post-solve accounting type + constructor) | transform | `src/pricing/welfare.jl` | exact |
| `src/settlement/run_inputs.jl` | adapter (run output → ledger input) | transform | `src/admm/solve_admm.jl` + `src/admm/admm_state.jl` (`_agr_result_keys`) + `welfare_accounting` guards | exact |
| `src/settlement/tariffs.jl` | utility (pure price construction) | transform | `src/pricing/welfare.jl` (pure arithmetic style) + `src/pricing/fit.jl` (module consts `FIT_λ_*`) | role-match |
| `src/settlement/price_taker.jl` | model (thin counterfactual QP builder) | request-response (solve) | `src/pricing/fit.jl` `_fit_opt_solve` + `src/admm/AgrOpt.jl` `build_agr_opt` | exact |
| `src/settlement/feasibility.jl` | service (AC-PF + diagnostics → status struct) | request-response | `src/pricing/fit.jl` SITE-2 block + `_fit_ac_settlement_violations` | exact |
| `src/settlement/equity.jl` | utility (pure math: Gini/Theil/Atkinson/Palma + breakouts + rebound) | transform | **no analog** — style only (`welfare.jl` docstring/guard discipline); formulas from RESEARCH.md Pattern 5 | none (new math) |
| `test/test_settlement.jl` (+ split files) | test | — | `test/test_pricing_welfare.jl` + `test/fixtures_ieee13.jl` | exact |
| `test/test_equity.jl` | test | — | `test/test_pricing_welfare.jl` known-value/golden shapes | role-match |
| `scripts/tariff_comparison.jl` | script (measurement artifact producer) | batch | `scripts/case_a_scaling.jl` | exact |
| `docs/literate/settlement_equity.jl` | docs (literate page) | — | `docs/literate/case_a_population.jl` + registration in `docs/make.jl` | exact |
| `src/TSODSO.jl` (modify) | config (include graph) | — | existing `pricing/` + `admm/` include blocks (lines 182–204) | exact |
| `docs/make.jl` (modify) | config (literate registration) | — | the `for src in (...)` list + `pages = [...]` (lines 19–59, 79–110) | exact |

---

## Pattern Assignments

### `src/settlement/SettlementLedger.jl` (model, post-solve accounting — transform)

**Analog:** `src/pricing/welfare.jl` — the aggregate-level settlement the per-actor ledger refines. Consumed, never modified (golden).

**Module header convention** (welfare.jl lines 1–17): every module file opens with a `# src/...` SEAM comment stating what it consumes and that it is post-solve ACCOUNTING, then declares its own `export`s:

```julia
# src/pricing/welfare.jl
#
# SEAM: welfare accounting — social = prosumer + DSO surplus split.
# ...
# Consumes ONLY the additive `ctx.meta[:agg_net]` stash + the registered `:balance_p` dual —
# no change to `solve_welfare`. DISTINCT from the operational solve
# (models/welfare_solve.jl): this is post-solve ACCOUNTING, not the optimization.

using JuMP
```

**Core algebra to refine per-actor** (welfare.jl lines 118–150) — the ledger's double-entry transfers are exactly this Σλ·net term recorded on BOTH sides, plus MS = DSO nodal collections − wholesale payment (already implicit in `dso`):

```julia
# Priced-frontier import p_import[t] (free-sign with allow_export) and its MEM cost.
pimp = value.(ctx.meta[:p_import])
mem_cost = sum(λ0[t] * pimp[t] for t in 1:T)      # Σ_t λ₀[t]·p_import[t]

# Price-transfer Σ_j Σ_t λ_j[t]·p_agⱼ[t] (thesis 3.46/3.47) — the term that cancels.
transfer = 0.0
for entry in ctx.meta[:agg_net]
    b = entry.bus
    (1 <= b <= size(λ, 1)) || throw(
        ArgumentError("welfare_accounting: aggregator bus=$b outside 1:$(size(λ, 1))"),
    )
    for t in 1:T
        transfer += λ[b, t] * value(entry.net[t])
    end
end
# ...
prosumer = util + transfer
dso = (_transfer_flip ? transfer : -transfer) - mem_cost
```

**Fail-loud boundary guards** (welfare.jl lines 80–98) — the ledger constructor copies this shape (missing stash → `ArgumentError` naming the key and the reason; empty contributions → `ArgumentError`; never `@assert`):

```julia
for key in (:agg_net, :p_import)
    haskey(ctx.meta, key) || throw(
        ArgumentError(
            "welfare_accounting: ctx.meta is missing :$key — this is not a solved " *
            "solve_welfare ModelContext carrying the surplus stash " *
            "(thesis 3.38/3.46/3.47).",
        ),
    )
end
```

**Identity assertion with magnitude in the message** (welfare.jl lines 166–178) — the ledger's sum-to-zero check should follow this style: compute the residual, the tolerance, and THROW with the magnitude localized (the ledger's version is exact-by-construction, so this is the self-test/guard form):

```julia
resid = abs((prosumer + dso) - social)
tol = atol + rtol * max(abs(social), abs(prosumer) + abs(dso))
resid <= tol || error(
    "welfare_accounting: surplus identity VIOLATED — |(prosumer+dso) − social| = $resid " *
    "exceeds tol=$tol (prosumer=$prosumer, dso=$dso, social=$social). ...",
)
```

**Magnitude-sanity band + docstring-contracted monetary units** (welfare.jl lines 154–164): `band = PRICE_MAX * (Np + 1) * T`; the CONTEXT locked decision "monetary units = welfare_accounting's units, documented in the module docstring" — copy welfare.jl's unit prose ("¢$/kWh-consistent ... a second unit would scale a surplus by 10×/100×", fit.jl lines 29–33).

---

### `src/settlement/run_inputs.jl` (adapter, run output → ledger input — transform)

**Analog A (centralized):** `welfare_accounting`'s stash reads (already excerpted above) + the documented extraction sequence from RESEARCH.md (verified code):

```julia
# src/pricing/welfare.jl:100-120 + src/models/welfare_solve.jl seam
ctx, welfare, dadp = solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
λ       = extract_dlmp(ctx)                    # (N, Tfull) nodal prices, exactness-gated
p_imp   = value.(ctx.meta[:p_import])          # frontier import per hour
net_j   = [value(e.net[t]) for e in ctx.meta[:agg_net], t in 1:T]
# welfare_accounting(ctx) → (; social, dso, prosumer): the ledger's MS must match .dso
```

**Analog B (ADMM converged):** `src/admm/solve_admm.jl` lines 249–276 documents the result contract — the adapter consumes these ADDITIVE keys, present ONLY on `:converged`:

```julia
# solve_admm returns (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap,
#   mu_q, q_devices, reactive_consensus_mode, status,
#   agr_dispatch, agr_utility, agr_import, agr_prices)
# `agr_dispatch`/`agr_utility`/`agr_import`/`agr_prices` are ADDITIVE per-aggregator keys
# (PAR-05, appended TRAILING on the converged path only): per-bus `Dict`s keyed over the
# ascending `load_nodes` ... `agr_prices[j]` equals the bus-j row of `dadp`.
```

**Sign/layout convention to preserve** (`src/admm/admm_state.jl` lines 447–474, `_agr_result_keys`):

```julia
# SIGN/LAYOUT CONVENTIONS (matching the published keys they mirror):
#   - `agr_prices[j]` is the PUBLISHED per-slot price for bus j — the negated internal
#     multiplier row, exactly `_admm_certify`'s `λ_mat = −λ` convention, so
#     `agr_prices[j] == dadp[row_of_j, :]` (row_of_j = the index of j in `load_nodes`).
function _agr_result_keys(st::AdmmState)
    agr_dispatch = Dict{Int, Vector{Float64}}(
        j => Float64[value(st.agr_by_bus[j].pag[t]) for t in 1:T] for j in load_nodes
    )
    agr_prices = Dict{Int, Vector{Float64}}(
        j => Float64[-st.λ[j][t] for t in 1:T] for j in load_nodes
    )
    return (; agr_dispatch, agr_utility, agr_import, agr_prices)
end
```

**Fail-loud convergence guard** (RESEARCH Pitfall 4; `solve_admm.jl` lines 252–253 + 293–298): the `:budget_exceeded` path returns `dadp = welfare = λ = nothing` BY DESIGN — the adapter must throw a loud `ArgumentError` unless `status == :converged`, in the boundary-guard style above. `p_imp` for the ADMM leg reads `value.(r.dso_ctx.meta[:p_import])` (DsoOpt stash).

---

### `src/settlement/tariffs.jl` (utility, pure price construction — transform)

**Analog:** `src/pricing/fit.jl` module constants + `welfare_accounting`'s weighted-sum arithmetic. No solving in this file (RESEARCH: "pure arithmetic over one DADP run; no solver").

**Named-constant discipline** (fit.jl lines 29–36) — the TOU bin boundaries (locked decision: "fixed bin structure", planner pins hours, e.g. off-peak 00–05 / shoulder / peak 17–22) and Atkinson's ε (RESEARCH A6) become auditable module constants exactly like:

```julia
# German-FIT price triple (thesis page 93), in ¢$/kWh — the SAME monetary unit as the
# MEM price profile / λ₀ and the device utility coefficients (a
# second unit would scale a surplus by 10×/100×). Named module constants so the
# baseline calibration is auditable: a mis-specified FIT price silently
# inflates/deflates the +25% headline.
const FIT_λ_IMPORT = 6.6   # residual import from the grid  (λ_im, page 93)
```

**Revenue-neutral derivation** (RESEARCH Pattern 3, algebraically exact): quantity-weighted mean `p_flat = Σ λ_j,t·w_j,t / Σ w_j,t` satisfies `Σ p_flat·w ≡ Σ λ·w` in exact arithmetic; the "rescale to match total DADP payments" step is a no-op-guard scale `s = (Σ λ·w)/(Σ p_flat·w)` with an `isapprox(s, 1.0)` assertion (numerical hygiene, not a correction). Weights `w[j,t]` come from the run's OWN quantities (`agr_dispatch[j]` signed net, or gross load — pick ONE, document; RESEARCH A2). The fairness-condition test is structural: `Σ_j,t p_derived·q_j,t == Σ_j,t λ_j,t·q_j,t` exactly, plus a hand-computed 2-bus/2-hour known value.

---

### `src/settlement/price_taker.jl` (model, thin counterfactual QP — request-response)

**Analog A (the mechanism, verbatim reuse of `contribute!`):** `src/admm/AgrOpt.jl` lines 148–191 (`build_agr_opt`):

```julia
model = Model(optimizer)              # optimizer = select_optimizer(QP()) — never a named solver
ctx = ModelContext(model)
ctx.T = T

res = contribute!(agg, ctx; T = T)    # devices verbatim: p_inject, utility, battery stash

@variable(model, pag[1:T])
@constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
register_constraint!(ctx, :agr_coupling, coupling)

obj_expr = ctx.objective - 0.5 * ρ * sum(pag[t]^2 for t in 1:T)   # ← the settlement module DROPS this ρ term
@objective(model, Max, obj_expr)
```

**The one deliberate difference (locked by RESEARCH Pattern 1):** the price-taker objective is `Max ctx.objective + Σ_t p[t]·pag[t]` — NO `−(ρ/2)·Σ pag²` penalty (production ρ = 100 materially distorts a price-taker optimum) and NO `set_objective_coefficient` mid-loop machinery (that is ADMM's build-once handle; `solve_agr!` line 308: `set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])`). Prices are plain `Float64` vectors, NEVER JuMP `Parameter`s (AgrOpt.jl header lines 22–24).

**Analog B (structure + gates of a self-contained counterfactual solve):** `src/pricing/fit.jl` lines 155–245 (`_fit_opt_solve`) — per-aggregator loop, length guards on `agg.Pdc`, `@objective(model, Max, surplus)`, then:

```julia
# OPTIMAL gate before any value is read (no dual is consumed here — the FIT flows carry
# no price we recover, so `dual = false`).
assert_solved!(model; dual = false)

# Read the numeric FIT schedule per aggregator.
per_agg = map(built) do b
    ...
    net = exp_v .- imp_v
    return (; bus = b.bus, φ = b.φ, ..., net)
end
```

**Battery-complementarity handling (Pitfall 1):** run `assert_battery_complementarity!(ctx; τ = τ_batt, T = T; on_violation = :report)` post-solve — the `on_violation` symbol switch idiom is `solve_agr!` lines 326–333 (`assert_battery_complementarity!(agr.ctx; τ = τ_batt, T = agr.T, on_violation = battery_on_violation)`); refusals are recorded outcomes, never τ-loosened.

**Sign convention (matches `agr_prices` and `welfare_accounting`'s transfer):** `p` is the PUBLISHED price; `pag > 0` (net exporter) EARNS `p·pag`, importer pays. Per-house attribution (RESEARCH Pattern 2): re-solve each house's own tiny QP at the same price — houses rebuilt via `TSODSO._case_a_house(bus, house_index, counts[bus], s_pop, T; scales...)` with seed `_case_a_house_seed(s_pop, bus, house_index)` (see `src/experiments/materialize.jl` lines 403–404, 444–488) — and verify `Σ_h U_h ≈ agr_utility[j]`, `Σ_h net_h ≈ agr_dispatch[j]` within a MEASURED, gate-then-golden tolerance (Pitfall 5: never present as bitwise).

---

### `src/settlement/feasibility.jl` (service, AC feasibility status — request-response)

**Analog (verbatim template, third copy of the Phase-27 idiom):** `src/pricing/fit.jl` lines 746–788 (`_fit_ac_settlement_violations`) — per-hour thermal/voltage diagnostics from a solved `ACPowerFlow(; limits = false)` context, never a throw:

```julia
function _fit_ac_settlement_violations(feeder, pf_vars::NamedTuple, T::Int)
    B = feeder.branches
    Np = length(feeder.buses)
    out = Vector{NamedTuple}(undef, T)
    for t in 1:T
        n_thermal = 0
        max_ratio = 0.0
        for (b, br) in enumerate(B)
            br.smax < _SMAX_NO_LIMIT || continue          # skip-listed sentinel branch
            Pb = value(pf_vars.P[b, t]); Qb = value(pf_vars.Q[b, t])
            lb = value(pf_vars.l[b, t])
            s_fwd = sqrt(Pb^2 + Qb^2)
            s_rev = sqrt((Pb - br.r * lb)^2 + (Qb - br.x * lb)^2)
            ratio = max(s_fwd, s_rev) / br.smax
            ratio > 1.0 && (n_thermal += 1)
            max_ratio = max(max_ratio, ratio)
        end
        # ... voltage loop over non-root buses: vj = sqrt(max(value(pf_vars.v[j, t]), 0.0))
        out[t] = (; t, n_thermal_violations = n_thermal, max_overload_ratio = max_ratio,
                     n_voltage_violations = n_voltage, min_voltage = min_v,
                     max_voltage = max_v, voltage_violated = n_voltage > 0)
    end
    return out
end
```

**The physics-only ACPF build + warm-start idiom** (fit.jl lines 533–635, SITE-2): fix each actor's net injection and `−Pdc·tanφ` reactive draw via `add_to_residual!(ctx, :Rp/:Rq, bus, t, value)`, free-sign priced frontier at the root, then:

```julia
ac = ACPowerFlow(; limits = false)
model = Model(_site2_ac_optimizer)         # = select_optimizer(problem_class(ACPowerFlow()))
# ... contribute!(ac, ctx, relaxed; T = T), fix injections, frontier var, balances ...
# Warm start P/Q/l/v from a seed solve (Ipopt's degenerate all-zero start):
for b in eachindex(Bf), t in 1:T
    set_start_value(pv_ac.P[b, t], value(pv_seed.P[b, t]))
    set_start_value(pv_ac.Q[b, t], value(pv_seed.Q[b, t]))
    set_start_value(pv_ac.l[b, t], value(pv_seed.l[b, t]))
end
# ...
ok = is_solved_and_feasible(model; dual = false, allow_local = true, allow_almost = false)
ac_status = termination_status(model)
```

**The wrap:** the new status struct (`:feasible` | violation list with branch/hour/quantity) composes these two — the settlement module owns ONLY the struct; never throws on violations. The second precedent is `_mpc_settlement_violations` (`src/experiments/mpc_loop.jl:1413–1483`, single-hour variant) — same field set. Deliberately keep code unshared (fit.jl docstring lines 741–744: "two small, independently-readable functions rather than one over-parametrized one").

---

### `src/settlement/equity.jl` (utility, pure math — transform) — **NO ANALOG**

No inequality metrics or DR-rebound measurement exist anywhere in the codebase. Planner must build from RESEARCH.md Pattern 5 (literature-grounded conventions table: Gini over ALL values incl. negatives; Theil/Atkinson on positive-support subset with exclusion count reported; Palma Σ top-decile/Σ bottom-40%) and SETL-06's baseline-vs-counterfactual rebound definition. Style must still follow the codebase: thesis-grounded docstrings stating the NEGATIVE-value convention per metric (the docstring IS the locked deliverable), `ArgumentError` guards on empty/mixed-degenerate vectors, known-value anchors: uniform ⇒ `(0, 0, 0, 0.25)`; hand-computed 4-vector with a negative `[-2.0, 1.0, 3.0, 6.0]` ⇒ pinned exact Gini. Breakouts consume `case_a_household_map` rows (`house, bus, aggregator, device_set, pv_group, house_index`, materialize.jl lines 739–746) + load terciles from baseline consumption — no new data.

---

### `test/test_settlement.jl`, `test/test_equity.jl` (test — fixture reuse)

**Analog:** `test/test_pricing_welfare.jl` — the entire file is the shape to copy:

- **Hand-built minimal fixture** (lines 30–45) — 2-bus radial + one PVBattery aggregator, `solve_welfare(...; allow_export = true)`:

```julia
feeder = Feeder(
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
    [Branch(1, 2, 0.01, 0.02, 10.0)],
    1,
)
T = 3
batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
ctx, obj, _dadp = solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T,
                                λ₀ = fill(40.0, T), allow_export = true)
```

- **Sign tests asserting independently-computed expectations** (lines 154–205): exporter-earns (`prosumer ≈ util + transfer`, pinned values `47.38684825193795; atol = 0.1`) vs importer-pays — the ledger's exporter/importer household items mirror these directly.
- **Non-vacuous throw test** (lines 108–138): `@test_throws ErrorException welfare_accounting(ctx; T = T, _transfer_flip = true)` — the ledger's sum-to-zero check needs the same kind of self-test proof.
- **Real-run identity on the IEEE-13 ground fixture** (lines 255–287): `setup = [IEEE13Fixtures]`, `ieee13_modified()`, `IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)`, `IEEE13Fixtures.mem_price_profile()` — the SETL-01 `:slow` integration test copies this verbatim.
- **Golden + non-failing cross-check split** (lines 394–416): PRIMARY golden pinned tight (`RATIO_GOLDEN = 0.9999738567553946; rtol = 1e-4`), generous physical band, and the figure-bound cross-check as `broken = (...)` so it NEVER fails. Revenue-neutral tolerances and house↔aggregator reconciliation follow this gate-then-golden discipline.
- **Fixture module** (`test/fixtures_ieee13.jl` lines 25–71): `@testmodule IEEE13Fixtures` defining functions/consts only, `setup = [IEEE13Fixtures]` consumption; per-house fixtures use `_case_a_house` + `_case_a_house_seed` (script lines 210–229 show the exact reconstruction idiom).

**Test-infra constraints** (`test/runtests.jl`): `@testitem "..." tags = [:settlement]` (names feed the `occursin` filters); items import `TSODSO` explicitly (no implicit using); soft-scope hazard — put mutable accumulators in `let` blocks (runtests.jl lines 8–38); any new `@test_broken`/`@test_skip` MUST get an `expected_broken.txt` line in the same commit (lines 45–48). Invocation ONLY via `julia --project=. -e 'import Pkg; Pkg.test()'` with `TSODSO_TEST_FILES=` / `TSODSO_TEST_SET=fast|slow|all` selection.

---

### `scripts/tariff_comparison.jl` (script, measurement artifact — batch)

**Analog:** `scripts/case_a_scaling.jl` (full read). Copy its skeleton:

- **Header + usage block** (lines 1–58): mode docs, CSV contract prose ("rows are UPSERTED keyed on their provenance identity ... a kill mid-run leaves the rows already captured — a kill is a MEASURED OUTCOME"), Case-A constants (T = 24, SEED = 42, :ieee13, :mem).
- **DrWatson provenance + explicit qualified imports** (lines 59–85):

```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO: ADMM, CertificateError, ... _case_a_house, build_feeder, build_population,
    build_price, solve_admm, sub_seed
using CSV
using DataFrames
using LinearAlgebra: BLAS
```

- **The upsert contract** (lines 184–198) — reuse verbatim (`cols = :union`, key-tuple arg, header on create):

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

- **Honest-outcome recording** (lines 152–173 `run_solve_outcome`): `CertificateError`/`SolveFailedError`/`ConvergenceError` become status rows with missing certified values; misuse errors propagate nonzero. For the comparison harness: per-tariff AC-status refusals and battery-certificate refusals are CSV rows, never legs dropped (Pitfall 1).
- **Provenance columns** (lines 321–337): `julia_version, threads, blas_threads, seed, t_horizon` + the identity key; `BLAS.set_num_threads(1)` before solving (lines 254–256); `if abspath(PROGRAM_FILE) == @__FILE__` entry (lines 441–443).
- Direct solver calls (`solve_admm(feeder, pf, aggs; T, λ₀, ρ = ADMM().ρ, ...)`, lines 312–320) — NOT the `ScenarioResult` seam (RESEARCH Alternative: `run(::Centralized/::ADMM, s)` normalizes away the ctx/keys the ledger needs).

---

### `docs/literate/settlement_equity.jl` + `docs/make.jl` (docs)

**Analog:** `docs/literate/case_a_population.jl` (the Phase-40 committed-CSV writeup page) registered in `docs/make.jl`:

```julia
# docs/make.jl lines 48-53 — the list entry:
    # The thesis-scale Case A population (784 houses → 10 bus-level aggregators):
    # composition measured LIVE (build-only — no solves), calibration provenance, and
    # the agreement/scaling sections read from results/case_a_population/ (the
    # committed-CSV pattern this page set's precomputed pages follow).
    "case_a_population.jl",
# lines 99-102 — the pages entry:
        "Experiments" => [
            "The Experiment Harness" => "generated/experiments.md",
            "Case A Population (784 houses)" => "generated/case_a_population.md",
        ],
```

`Literate.markdown(...; flavor = Literate.DocumenterFlavor())` executes every `@example` block during `makedocs`; heavy sections read from committed `results/` CSVs rather than solving live (the precomputed-results precedent, make.jl lines 33–42). The writeup must carry the locked **no-income-data statement** (bills/surplus only). Note `checkdocs = :exports` + `:missing_docs` NOT in `warnonly` (make.jl lines 111–124): every newly EXPORTED settlement symbol needs a docstring surfaced via `api.md`'s `@autodocs`, or the docs build fails.

---

### `src/TSODSO.jl` (modify — include graph)

**Analog:** the existing `pricing/` and `admm/` blocks (lines 182–204). New `settlement/` block goes AFTER the admm block and AFTER `experiments/mpc_loop.jl`/`run_stochastic.jl` (it consumes ADMM result keys and `case_a_household_map`) — place it before the `@compat public` declarations (line 282+), following the established comment convention:

```julia
# --- Distribution pricing: DLMP decomposition, FIT baseline, checks, welfare accounting ---
# Loaded AFTER models/oracle.jl (each consumes a solved
# ctx / the operational oracle). Dependency order: dlmp → fit → checks → welfare. Each file
# declares its own exports.
include("pricing/dlmp.jl")      # DLMP extraction + four-way decomposition
...
```

Each `src/settlement/*.jl` file declares its own `export`s (include-graph convention — welfare.jl line 5, AgrOpt.jl line 4); dependency order within the block: `SettlementLedger` (types) → `run_inputs` → `tariffs` → `price_taker` → `feasibility` → `equity`. Each new file opens with a SEAM header comment in the welfare.jl/AgrOpt.jl style.

---

## Shared Patterns

### Fail-loud boundary guards (ArgumentError, never @assert)
**Source:** `src/pricing/welfare.jl:80-98`, `src/pricing/fit.jl:415-424`, `src/admm/AgrOpt.jl:277-282`
**Apply to:** every public function in `src/settlement/` (V5 input-validation row of RESEARCH's Security Domain: length/shape/status checks — `λ₀ length == T`, `status == :converged`, bus-in-range).
```julia
isempty(aggregators) && throw(ArgumentError("fit_baseline needs at least one aggregator (thesis 3.24)"))
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
on_inexact in (:error, :report) || throw(ArgumentError("...invalid on_inexact=$(repr(on_inexact))..."))
```

### Solver abstraction (never name a solver; gate before reading values)
**Source:** `src/admm/AgrOpt.jl:148,319-322`, `src/pricing/fit.jl:166,217,534-535,597-603`
**Apply to:** `price_taker.jl` (QP) and `feasibility.jl` (NLP).
```julia
model = Model(select_optimizer(QP()))                       # QP legs
model = Model(select_optimizer(problem_class(ACPowerFlow())))  # AC legs
assert_solved!(model; dual = true)   # when duals are read
assert_solved!(model; dual = false)  # when they are not
is_solved_and_feasible(model; dual = false, allow_local = true, allow_almost = false)  # AC legs
```

### Report-don't-throw (honesty policy)
**Source:** `src/pricing/fit.jl:724-788` (`ac_violations` "A REPORT, never a gate"), `scripts/case_a_scaling.jl:152-173` (`run_solve_outcome`)
**Apply to:** `feasibility.jl` status struct; comparison-harness per-tariff rows; battery-certificate `on_violation = :report`. Violations/refusals/non-convergences are measured outcomes recorded alongside the numbers — never dropped, never τ-loosened.

### Published-price / net-injection sign conventions (three colliding conventions)
**Source:** `src/admm/admm_state.jl:452-456` (`agr_prices[j] == dadp[row_of_j, :]`, published = negated internal λ), `src/pricing/welfare.jl:136-150` (transfer prices net INJECTION: exporter earns, importer pays), `src/pricing/fit.jl:225` (`net = exp − imp`)
**Apply to:** ALL settlement arithmetic. Settle from PUBLISHED prices (`dadp` rows / `agr_prices`) and net injections (`agr_dispatch` / re-solved `pag`); bill = `−Σ_t p·net` (payment), surplus = `U + Σ_t p·net`. Unit-test exporter-earns/importer-pays on a hand-built 2-house fixture (mirror `test_pricing_welfare.jl:154-253`).

### Structural-vs-solver assertion split (no tolerance laundering)
**Source:** `test/test_pricing_welfare.jl:98-106` (identity exact on near-lossless), `:391-407` (golden + band), RESEARCH Pitfall 8
**Apply to:** every settlement test — assert STRUCTURAL identities exactly (double-entry sum-zero, revenue-neutral rescale, MS ↔ `welfare_accounting.dso` on the same numbers); assert solver COMPARISONS within measured, gate-then-golden-pinned tolerances. Every tolerance is either algebraically exact or measured from a live run — never invented.

### Known-value certificate per new mathematical regime (v3.0 standing bar)
**Source:** `test/test_pricing_welfare.jl:194-204` (pinned sign-values), `:402-416` (golden + non-failing cross-check), RESEARCH "Known-value anchors"
**Apply to:** equity metrics (uniform ⇒ (0,0,0,0.25); hand-computed negative-value Gini; exclusions reported) and the revenue-neutral derivation (hand-computed 2-bus/2-hour value).

### CSV measurement-artifact contract
**Source:** `scripts/case_a_scaling.jl:38-51, 184-198, 152-173`
**Apply to:** `scripts/tariff_comparison.jl` + `results/settlement_comparison/*.csv` — upsert on provenance key, `cols = :union`, provenance columns per row, statuses-as-rows, kill = measured outcome.

## No Analog Found

| File | Role | Data Flow | Reason | Planner guidance |
|------|------|-----------|--------|------------------|
| `src/settlement/equity.jl` (metric math) | utility | transform | No inequality/rebound metrics exist in the codebase | Use RESEARCH.md Pattern 5 conventions table + SETL-06 definition verbatim; docstrings carry the negative-value conventions; known-value certificates mandatory |
| `docs/literate/settlement_equity.jl` body (equity sections) | docs | — | First equity writeup | Follow `case_a_population.jl`'s committed-CSV page structure; the no-income-data statement is a locked deliverable |

## Metadata

**Analog search scope:** `src/pricing/`, `src/admm/`, `src/experiments/` (materialize, mpc_loop via grep), `src/powerflow/` (SMAX_NO_LIMIT confirmed referenced at `fit.jl:754`), `scripts/`, `docs/`, `test/`, `src/TSODSO.jl`
**Files read:** 14 (welfare.jl, fit.jl, AgrOpt.jl, admm_state.jl, solve_admm.jl, materialize.jl ×2 slices, TSODSO.jl, runtests.jl, test_pricing_welfare.jl, fixtures_ieee13.jl, case_a_scaling.jl, make.jl, CONTEXT.md, RESEARCH.md)
**Pattern extraction date:** 2026-10-24
