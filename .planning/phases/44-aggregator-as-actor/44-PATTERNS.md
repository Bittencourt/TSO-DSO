# Phase 44: Aggregator as Actor - Pattern Map

**Mapped:** 2026-11-02
**Files analyzed:** 22 (9 new src/script/doc files, 8 modified src files, 5 new tests)
**Analogs found:** 20 / 22 (the two exceptions are in "No Analog Found")

All line numbers were read in this session from the working tree on branch `agents/session-2026-10-23`. Line numbers for the larger files (`admm_phases.jl`, `DsoOpt.jl`, `admm_state.jl`) are taken from RESEARCH.md citations and were not re-read here. Re-grep before editing them.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/actors/actor_objective.jl` (new) | model (value types + dispatch hooks) | transform | `src/devices/CapabilityTraits.jl` (trait dispatch seam) and `src/devices/AbstractDevice.jl:75-115` (abstract type + one-line defaults) | role-match |
| `src/actors/Portfolio.jl` (new: `Portfolio`, `SlotTable`, `_expand_actors`) | model | transform | `Aggregator` struct in `src/devices/Aggregator.jl` and `case_a_household_map` (`materialize.jl:988-1031`) | partial |
| `src/actors/efficiency.jl` (new: `social_welfare`, ΔW) | utility | transform | `welfare_accounting` and `welfare_solve.jl:242` welfare expression | role-match |
| `src/devices/Behavioural.jl` (new wrappers) | device (wrapper) | request-response (`contribute!`) | `src/devices/ElectricVehicle.jl` plus `CapabilityTraits.jl` | role-match (no wrapper device exists) |
| `src/experiments/materialize.jl` (mod: `BehaviourSpec`, `apply_behaviour`, `_device_baseline`) | transform | batch, seeded | `build_population` + `_flex_mix` (`materialize.jl:557-574, 780-800`) | exact |
| `src/admm/AgrOpt.jl` (mod: `objective` kwarg, `linear_offset` field, `solve_agr!` coefficient) | service (subproblem) | request-response | itself (`:173`, `:189`, `:312`) | exact (self) |
| `src/admm/admm_phases.jl` (mod: slot branch in `_admm_build`, `has_4q_by_bus`) | orchestration | event-driven (iteration) | itself (`:61-95`, `:415`) | exact (self) |
| `src/admm/admm_state.jl` (mod: `slot_bus`, 18-arg ctor) | model (state) | CRUD | itself | exact (self) |
| `src/admm/DsoOpt.jl` (mod: slot-indexed `pag_dso`) | service | request-response | itself (`:366-385, 419-459`) | exact (self) |
| `src/admm/solve_admm.jl` (mod: `actors` kwarg + guards) | controller (entry point) | request-response | itself (`:313-336`) | exact (self) |
| `src/models/welfare_solve.jl` (mod: `actors`/wedge, `ctx.meta[:actor]`) | service | request-response | itself (`:194-200, 242`) | exact (self) |
| `src/pricing/fit.jl` (mod: guard Union) | utility (guard) | request-response | `_reject_unsupported_flex_devices` (`fit.jl:70-93`) | exact |
| `src/experiments/mpc_loop.jl` and stochastic entry (mod: guard calls) | controller | request-response | `fit.jl` guard call sites (`fit.jl:118`, `mpc_loop.jl:292`) | exact |
| `src/settlement/SettlementLedger.jl` (mod: `actor_wedges` kw) | service | transform | `_push_transfer_pair!` (`:105-130`) | exact |
| `src/settlement/run_inputs.jl` (mod: slot-aware adapters, per-bus sum) | adapter | transform | itself (`:125-160`, `:243-295`) | exact (self) |
| `scripts/actor_behaviour_sweep.jl` (new) | script | batch | `scripts/socp_highpv_remeasure.jl` | exact |
| `results/actor_behaviour/*.csv` (new, committed) | artifact | file-I/O | `results/socp_highpv/highpv_exactness.csv` | exact |
| `docs/literate/aggregator_actor.jl` (new) | docs | file-I/O | `docs/literate/socp_highpv_exactness.jl` | exact |
| `docs/make.jl`, `scripts/README.md`, `src/TSODSO.jl`, `test/test_exports.jl` (mod) | config | n/a | existing `socp_highpv` registration lines | exact |
| `test/test_actor_objective.jl`, `test_actor_portfolio.jl`, `test_behaviour.jl`, `test_actor_settlement.jl`, `test_actor_sweep.jl` (new) | test | n/a | `test/test_flex_population.jl`, `test/test_electricvehicle.jl`, `test/test_settlement.jl` | role-match |

## Pattern Assignments

### `src/actors/actor_objective.jl` (model, transform)

**Analog:** `src/devices/AbstractDevice.jl:75-115` (abstract type with one-line trait defaults) and `src/devices/CapabilityTraits.jl` (a seam file with a header comment explaining why it exists).

**File-header convention** (`CapabilityTraits.jl:1-19`): a comment block starting `# src/<path>`, then `# SEAM: ...` and `# WHY THIS FILE EXISTS`. Copy this for each new file. Follow it with a docstring per exported name.

**Default-by-dispatch pattern** (`AbstractDevice.jl:84,109`):
```julia
is_flexible_load(::AbstractDevice) = false
has_reactive_decision(d::AbstractDevice)::Bool = is_flexible_load(d)
```
Use the same shape for `agr_objective` and `agr_linear_offset`. The RESEARCH.md sketch is authoritative: `agr_objective(::WelfareObjective, U, pag, T) = U`, which must return the same object (`===`) so the built objective is bit-identical.

**Do not** make the objective a field of `Aggregator` or a new `AbstractStrategy` (locked).

**Name trap:** `Actor` is already `const Actor = Union{Symbol,Tuple{Symbol,Int}}` at `SettlementLedger.jl:37`. Use `Portfolio`. The ledger tuple `(:actor, id)` already fits that Union.

---

### `src/admm/AgrOpt.jl` (modify)

**Hook 1, `build_agr_opt` signature** (`AgrOpt.jl:134-141`, existing):
```julia
function build_agr_opt(
    agg::Aggregator,
    T::Int;
    ρ::Real,
    reactive_mode = ReactiveMode.OFF,
    ρ_q::Real = ρ,
    optimizer = select_optimizer(QP()),
)
```
Add a trailing `objective = WelfareObjective()` keyword, which is additive.

**Hook 2, objective accumulator** (`AgrOpt.jl:173`, existing):
```julia
obj_expr = ctx.objective - 0.5 * ρ * sum(pag[t]^2 for t in 1:T)
```
Change to `agr_objective(objective, ctx.objective, pag, T) - 0.5 * ρ * ...`. The LIVE branch at `:175-189` (`obj_expr -= ...`) stays untouched.

**Hook 3, constructor** (`AgrOpt.jl:191`, existing): `return AgrOpt(model, ctx, collect(pag), qag, qag_live, T, agg.bus, Float64(ρ))`. Add a trailing field `linear_offset`. The struct is only constructed here (per RESEARCH), so the added field is safe.

**Hook 4, `solve_agr!` coefficient update** (`AgrOpt.jl:311-316`, existing). This is the Pitfall-1 site:
```julia
for t in 1:agr.T
    set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
    if μ_j !== nothing
        set_objective_coefficient(agr.model, agr.qag_live[t], -μ_j[t] - ρ_q * d_j[t])
    end
end
```
Replace the pag line with the following. The legacy branch performs no extra float op.
```julia
coef = -λ_j[t] - ρ * c_j[t]
agr.linear_offset === nothing || (coef += agr.linear_offset[t])
set_objective_coefficient(agr.model, agr.pag[t], coef)
```
Any margin baked into the objective would be overwritten by `set_objective_coefficient`, so the offset must live on the `AgrOpt`.

---

### `src/models/welfare_solve.jl` (modify, centralized hook)

**Net-expression capture, already present** (`welfare_solve.jl:194-200`):
```julia
agg_net = Vector{NamedTuple}(undef, length(aggregators))
for (k, agg) in enumerate(aggregators)
    res = contribute!(agg, ctx; T = T)
    net = [res.p_inject[t] - agg.Pdc[t] for t in 1:T]   # net active injection p_agⱼ[t] (3.22)
    agg_net[k] = (; bus = agg.bus, net = net, utility = res.utility)
end
ctx.meta[:agg_net] = agg_net
```
**Welfare expression** (`:242`): `welfare = ctx.objective - sum(λ₀[t] * p_import[t] for t in 1:T)`, followed by `@objective(model, Max, welfare)`. Insert the wedge between these lines, on the non-default path only: `welfare += wedge_term(obj_k, agg_net[k].net, T)`.

- Never add the wedge to `ctx.objective`. `social_welfare = value(ctx.objective) - Σλ₀ value(p_import)` is then immune to constant offsets (M4).
- Do not edit `Aggregator.contribute!` (RESEARCH deviation from the CONTEXT wording: the `agg_net` expressions make that unnecessary).
- The return value is a 3-tuple that is destructured everywhere, so do not change it. Stash results in `ctx.meta[:actor]`, as `ctx.meta[:agg_net]` does at `:200`.
- Do not short-circuit an all-zero wedge. The centralized pass-through test would become vacuous.

---

### `src/admm/admm_phases.jl`, `DsoOpt.jl`, `admm_state.jl` (modify, slot table)

**Analog:** itself. These are the legacy 1:1 guards. Keep them verbatim on the legacy branch, which is taken when `actors === nothing`.

**Legacy guards to preserve** (`admm_phases.jl:61-81`):
```julia
length(aggregators) == length(load_nodes) || throw(
    ArgumentError(
        "solve_admm assumes one aggregator per load node (got $(length(aggregators)) " *
        "aggregators for $(length(load_nodes)) load nodes); multi-aggregator-per-bus " *
        "coupling is not supported",
    ),
)
agr_by_bus = Dict{Int, AgrOpt}()
for agg in aggregators
    haskey(agr_by_bus, agg.bus) && throw(
        ArgumentError("two aggregators share bus $(agg.bus); solve_admm assumes 1:1"),
    )
    agr_by_bus[agg.bus] = build_agr_opt(agg, T; ρ = ρf, reactive_mode = mode,
                                        ρ_q = ρ_qf, optimizer = agr_optimizer)
end
```
**State dicts** (`:87-95`): `λ`, `c`, `a`, `pag_dso_prev`, `util` are all `Dict{Int,...}` keyed by `j in load_nodes`. Setting `load_nodes := slot ids` on the slot branch makes these and the `set_rho!` loops work unchanged.

**Hidden 1:1 assumption** (`admm_phases.jl:415-417`):
```julia
has_4q_by_bus = Dict{Int, Bool}(
    agg.bus => any(dv -> dv isa FourQuadBESS, agg.devices) for agg in aggregators
)
```
This is keyed by `agg.bus` but indexed by slot id downstream, so it must be keyed by slot id on the slot path (Pitfall 3).

The full 1:1 inventory table (about 16 locations) is in 44-RESEARCH.md, Pattern 3. Plans should cite that table row by row.

**Constraints:**
- `DsoOpt` has 10 positional fields (built positionally at `test/test_admm_exactness_default.jl:45`), so do not add a field. Store `slot_bus` in `dso.ctx.meta[:slot_bus]`.
- `AdmmState` is built positionally by `scripts/profile_ieee8500_memory_attribution.jl:209` with 18 args. Add `slot_bus` as a trailing field plus an 18-arg outer constructor.
- Slot id rule: the first site at a bus gets `id = bus`; extra sites get `N + k`. In the 1:1 case `ids == load_nodes`.

**`solve_admm` signature** (`solve_admm.jl:313-336`): add `actors = nothing` as an additive trailing keyword after `parallel::Bool = false`. The default result NamedTuple key set and order must not change. Add the `actor` key on the non-default path only.

---

### `src/devices/Behavioural.jl` (device wrapper, request-response)

**Analog:** `src/devices/ElectricVehicle.jl` for the device contract, plus `CapabilityTraits.jl` for trait overrides. No wrapper device exists, so this is the first.

**Include position** (`src/TSODSO.jl`): after `devices/CapabilityTraits.jl` (`:136`) and before `devices/Aggregator.jl` (`:139`).

**Contract** (`AbstractDevice.jl:25-39`):
- `contribute!(dev, ctx; T)` writes nothing to residuals or the objective.
- It returns `(; vars, p_inject, utility[, q_inject])`.
- `contribute!` signature to mirror (`ElectricVehicle.jl:311-316`): `function contribute!(d::ElectricVehicle, ctx::ModelContext; T::Int, soc_terminal = nothing)`.
- All JuMP objects must be anonymous (`ElectricVehicle.jl` header: "Every JuMP object it creates is ANONYMOUS ... so any number of EVs coexist in one model"). The `rebound_u` variables follow the same rule: `@variable(m, [t = 1:T], lower_bound = 0.0)`, with no names.

**Trait forwarding** (types and one-liners from `CapabilityTraits.jl:21-35`):
```julia
has_reactive_decision(::FourQuadBESS) = true
storage_kind(::Type{<:PVBattery}) = :battery
storage_kind(::Type{<:ElectricVehicle}) = :ev
```
Write the wrapper equivalents. The type-level `storage_kind` is what `_stash_entry_has_kind` reads (`CapabilityTraits.jl:46-56`: `storage_kind(types[i]) === kind`), so it is mandatory for certificates to route correctly:
```julia
storage_kind(::Type{<:PartialCompliance{D}}) where D = storage_kind(D)
storage_kind(::Type{<:OptOut}) = :none
is_flexible_load(w::PartialCompliance) = is_flexible_load(w.inner)
has_reactive_decision(w::PartialCompliance) = has_reactive_decision(w.inner)
```
Also forward `φ`. `Aggregator.jl:216` reads it via `hasproperty(d, :φ) && d.φ !== nothing`. A wrapper without it silently falls back to `agg.φ`.

**Isa blindness.** `isa` probes that wrappers hide:
- `fit.jl:83` and `fit.jl:124`
- `admm_phases.jl:416`
- `materialize.jl:699`
- `mpc_loop.jl:298, 533-639`

Extend the guard Union (see the `fit.jl` section below). Reject `FourQuadBESS`, `SmartInverterPV` and `FixedCapacitor` at wrap time with `ArgumentError`. `ξ = 0` routes to `OptOut`.

---

### `src/experiments/materialize.jl` (modify: `BehaviourSpec`, `apply_behaviour`, `_device_baseline`)

**Analog:** the Phase-43 `flex_devices` opt-in (`materialize.jl:557-574` and `780-800`).

**SplitMix64 seed mix** (`:557-574`, copy verbatim; never `Base.hash`):
```julia
function _flex_mix(vals::Integer...)
    h = 0x9e3779b97f4a7c15 % UInt64
    for v in vals
        z = (h + (v % UInt64) + 0x9e3779b97f4a7c15) % UInt64
        z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
        z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
        h = z ⊻ (z >> 31)
    end
    return Int(h % UInt64(typemax(UInt32)))
end
const _FLEX_TAG_EV = 1
const _FLEX_TAG_HP = 2
const _FLEX_SUB_ARR = 11   # ... up to _FLEX_SUB_TIN0 = 15
```
Add integer tags in the same style, e.g. `const _BEH_TAG_OPTOUT = 21`. Draw `u = rand(StableRNGs.LehmerRNG(_flex_mix(seed, _BEH_TAG_OPTOUT, bus, device_index)))` (the RNG idiom is at `_flex_uniform`, `:577`), and opt out iff `u < opt_out`.

**Opt-in kwarg + byte-identity** (`materialize.jl:780-800`):
```julia
function build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer;
                          flex_devices = nothing)
    sel = _flex_selectors(flex_devices)   # validate first: unknown selector fails loud
    if isempty(sel)
        return _build_population_core(sym, feeder, feeder_sym, profiles, seed, sel)
    end
    ...
```
The default `BehaviourSpec()` (ξ=1, opt_out=0, no rebound) must make `apply_behaviour` return its input `===`. Validate first and fail loud, as `_flex_selectors` does. The `BehaviourSpec` transform goes next to `build_population` as a separate function, not a new kwarg of it. `Scenario` stays untouched.

**`_device_baseline`** copies the `price_taker_dispatch` single-model shape (`src/settlement/price_taker.jl:101-117`):
```julia
model = Model(select_optimizer(QP()))
ctx = ModelContext(model)
ctx.T = T
res = contribute!(agg, ctx; T = T)
@variable(model, pag[1:T])
@constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
register_constraint!(ctx, :price_taker_coupling, coupling)
@objective(model, Max, ctx.objective + sum(price[t] * pag[t] for t in 1:T))
assert_solved!(model; dual = false)
net = Float64[value(pag[t]) for t in 1:T]
utility = value(ctx.objective)
```
For a single device, use `res.p_inject` directly and read `b = value.(res.p_inject)` and `Ub = value(res.utility)`. The price is the flat FIT constant (`fit.jl:34`, `FIT_λ_IMPORT`), with no ρ term.

- Never name a solver. Use `select_optimizer(QP())`.
- Add a deterministic tie-break for EV non-uniqueness.
- Default-wrap flexible loads only. Storage is opt-in because the flat price makes it degenerate (`price_taker.jl:27-33`).
- This is the Open Question 1 deviation: the baseline is not `fit_baseline`. Document it.

---

### `src/pricing/fit.jl` (modify, guard)

**Analog and template** (`fit.jl:80-93`, existing):
```julia
function _reject_unsupported_flex_devices(devices, caller::AbstractString)
    bad = unique(
        nameof(typeof(d)) for
        d in devices if d isa Union{ElectricVehicle,HeatPump,SmartInverterPV}
    )
    isempty(bad) || throw(
        ArgumentError(
            "$caller does not support the phase-43 flexible devices " *
            "$(join(string.(bad), ", ")) (build_population `flex_devices` opt-in): they " *
            "have no FIT-OPT / MPC model here. Use the day-ahead centralized/ADMM " *
            "strategies, or drop `flex_devices`.",
        ),
    )
    return nothing
end
```
Extend the Union with `PartialCompliance, OptOut, Rebound`, and update the message text to name the behaviour wrappers. It is already called from `_fit_pv_and_flex` (`fit.jl:118`) and `run_mpc` (`mpc_loop.jl:292`). Add an equivalent guard call at the stochastic aggregator-taking entry, and a guard for the new `actors`/`objective` kwargs on MPC, stochastic and FIT paths, with the same `ArgumentError` shape.

`compare_tariffs` runs the `:fit` leg, so wrapped populations throw there by design. Do not route the sweep through it.

---

### `src/settlement/SettlementLedger.jl` (modify: `actor_wedges`)

**Analog:** `_push_transfer_pair!` (`:105-130`):
```julia
function _push_transfer_pair!(transfers::Vector{Transfer}, from::Actor, to::Actor,
                              t::Int, price::Float64, quantity::Float64)
    amount = price * quantity
    push!(transfers, (from = from, to = to, t = t, price = price, quantity = quantity, amount = amount))
    push!(transfers, (from = to, to = from, t = t, price = price, quantity = -quantity, amount = -amount))
    return nothing
end
```
The mirror row carries the exact negation, so the adjacent pair cancels bitwise in the sequential fold and `ledger_residual == 0.0` is preserved. Add the keyword `actor_wedges = nothing`, appended after the existing flows (c). When `nothing`, push no rows, so existing ledgers are bit-identical. Per site and hour: `_push_transfer_pair!(transfers, (:actor, id), (:aggregator, bus), t, Float64(m[t]), -Float64(net[t]))`.

**Ledger input constraint** (`SettlementLedger.jl:215-226`): buses must be unique and ascending. With several sites per bus, sum nets and utilities per bus before building the ledger.

**Finite guard** (`:134`): `_finite_or_throw(xs, name)` for the V5 input checks. Reuse it for wedge vectors.

---

### `src/settlement/run_inputs.jl` (modify, slot-aware adapters)

**Centralized adapter overwrite bug** (`run_inputs.jl:133-151`, existing):
```julia
entries = ctx.meta[:agg_net]
buses = Int[entry.bus for entry in entries]
issorted(buses) || throw(ArgumentError("settlement_input: ctx.meta[:agg_net] entry buses are not ascending ..."))
bus_nets = Dict{Int, Vector{Float64}}()
bus_utilities = Dict{Int, Float64}()
for entry in entries
    b = entry.bus
    bus_nets[b] = Float64[value(entry.net[t]) for t in 1:T]        # OVERWRITES for a shared bus
    bus_utilities[b] = Float64(value(entry.utility))
end
```
On the multi-site path, accumulate with `+=` per bus. `issorted` passes duplicates, so the silent-drop is real. The ADMM adapter (`:243-295`) treats `keys(agr_dispatch)` as buses and aligns `dadp` rows by `enumerate(buses)`, so it needs a slot-aware branch that sums per bus and takes the price row per bus.

---

### `src/devices/ElectricVehicle.jl` (analog only, no edit)

The EV device is the reference for how a Phase-43 device was added: constructor guards, `contribute!` guards (`:311-335`, with the horizon guard throwing `ArgumentError`), anonymous variables, and the trait overrides placed in `CapabilityTraits.jl` rather than in the device file. `test/test_electricvehicle.jl` gives the matching test shapes.

---

### `scripts/actor_behaviour_sweep.jl`, `results/actor_behaviour/*.csv`, `docs/literate/aggregator_actor.jl` (artifact trio)

**Analog:** `scripts/socp_highpv_remeasure.jl`, `results/socp_highpv/highpv_exactness.csv`, `docs/literate/socp_highpv_exactness.jl`.

**Script header** (`socp_highpv_remeasure.jl:1-5`): a comment block with the run command, "PURE ORCHESTRATION through the public API", the seeds, the verdict policy, and the CSV key:
```julia
using DrWatson
@quickactivate "TSODSO"

using TSODSO
using TSODSO: ...
using TSODSO.JuMP
using CSV, DataFrames
const OUT = projectdir("results", "socp_highpv", "highpv_exactness.csv")
```
**Write pattern** (`:297-306`): `mkpath(dirname(OUT))` then `CSV.write(OUT, df_final)`. Rows are upserted keyed by a string tuple (here `(fixture, variant, seed)`) with `cols = :union`. Key the sweep as `(fixture, xi, opt_out, r, seed)`. Refusals are recorded as first-class verdict rows, never errors (honesty policy).

**Sweep plumbing** (RESEARCH Pitfall 6). Build the rows from `settlement_input` plus `build_settlement_ledger` plus `rebound`. Do not use `compare_tariffs` (it forces the `:fit` leg and forbids shared buses, `comparison.jl:278-282`). Required columns:
- `welfare` (social), `actor_objective`, `ΔW_abs`, `ΔW_rel`
- DADP mean and max
- ledger totals per actor
- `rebound_amount`, `rebound_ratio` (keep `NaN` if no reduction)

**Docs page** (`socp_highpv_exactness.jl:1-40`): Literate `#` markdown header stating that the page reads the committed CSV and recomputes derived figures live, "so no number below is typed by hand". Start with `using TSODSO; using Printf` and a small `read_csv(path)` helper (`:36-40`).

**Registration:**
- `docs/make.jl:37`: `"socp_highpv_exactness.jl",   # DEV-09 ...` in the literate list.
- `docs/make.jl:108`: `"SOCP Exactness in High-PV (optimal Q)" => "generated/socp_highpv_exactness.md",` in the pages list.
- `scripts/README.md:48`: the table row format is `| \`script.jl\` | description | \`julia --project=. scripts/script.jl\` (runtime) | \`results/...csv\` | Maintained |`.
- `python3 .github/scripts/check_scripts_index.py` gates the index.

---

### `src/TSODSO.jl` and `test/test_exports.jl` (modify)

**Include insertion points:**
- `src/actors/actor_objective.jl` before `admm/AgrOpt.jl` (`:211`). Because it is also used by `welfare_solve.jl` (`:146`), place it early, before `models/welfare_solve.jl`.
- `src/actors/Portfolio.jl` before `models/welfare_solve.jl` (`:146`).
- `devices/Behavioural.jl` after `devices/CapabilityTraits.jl` (`:136`).

**Exports.** The curated list is a literal block of names in `src/TSODSO.jl`, mirrored by `keep` in `test/test_exports.jl` (`@test exported == keep`, an exact-set check). Add each new public name to both. Example existing line shape: `price_taker_dispatch price_taker_dispatches` and `gini theil atkinson palma load_terciles equity_breakdown rebound`.

---

### Tests (new `test/test_actor_*.jl`, `test_behaviour.jl`)

**Analog 1, the digest fence:** `test/test_flex_population.jl:1-70`. Copy the FNV-1a `fold` verbatim, then pin the pre-phase golden digests of the default `build_population` and the default `solve_admm` result before any src edit:
```julia
@testitem "flex population: byte-identity fence (kwarg absent == flex_devices=nothing)" tags = [:population] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed
    ...
    digest(aggs) = fold(0xcbf29ce484222325, aggs)
    golden = Dict(:default => 0x9358a27f6c14df69, :case_a_784 => 0x2c853fe6bee1cb41)
```
- Item names carry a common substring so a selector picks them up (e.g. every item name contains "actor objective").
- The existing `golden` values must never be re-pinned.
- The new fence for the default `solve_admm` result must also be captured before any src edit.

**Analog 2, device tests:** `test/test_electricvehicle.jl`. Item names are `"electricvehicle: <behaviour>"`, with tests for contract, sign convention, anonymous-object coexistence (`:374`), and zero binaries (`:331`). Mirror these for the wrappers (two wrapped devices in one model, no binaries, trait forwarding).

**Analog 3, settlement:** `test/test_settlement.jl` (61 KB) for `ledger_residual == 0.0` and the equity/rebound assertions.

**Run commands** (from RESEARCH Validation Architecture):
```
TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_actor_objective.jl julia --project=. -e 'import Pkg; Pkg.test()'
```
Slow items use `TSODSO_TEST_SET=all`.

**Test-writing rules** (MEMORY traps):
- `@testitem` bodies are top-level soft scope. Never write `try x = ...` or reassign outer variables in `for`/`try`. Wrap in a function or `let`.
- Never run TestItemRunner via `julia -e` or `--project=test` directly.
- After runs, `git checkout -- test/Project.toml test/Manifest.toml` if mutated.
- Keep scratch `.jl` files outside the repo, since TestItemRunner scans them.
- Run with Julia 1.12.5, not 1.12.7.

**Tolerance policy.** Tolerances are measured first (3 seeds, take 3x the observed max). Never picked.

**Key assertions to copy from RESEARCH:**
- ADMM `ProfitObjective(0)` is `==` on `welfare`, `dadp` and `iters` (bitwise).
- Centralized `m = 0` is within the measured tolerance.
- `W_soc ≤ W_opt` for m ≠ 0 (C7).
- Slot branch forced on the 10-aggregator IEEE-13 population equals legacy bitwise.
- The knife-edge canary stays at iters 56 and welfare -4823.66604824162 (never re-pin).

---

## Shared Patterns

### Opt-in additive keyword with a byte-identical default
**Source:** `src/experiments/materialize.jl:780-800` (`flex_devices = nothing`) and `src/admm/solve_admm.jl:313-336`.
**Apply to:** `solve_admm(actors=)`, `solve_welfare(actors=)`, `build_agr_opt(objective=)`, `settlement ... actor_wedges=`, `apply_behaviour`.
The default branch must be literally unchanged code, not merely equivalent. Prove it with a full-field digest fence.

### Fail-loud `ArgumentError` guards
**Source:** `src/pricing/fit.jl:80-93`.
**Apply to:** the MPC, stochastic and FIT rejection of non-default actors, objectives and behaviour, and the V5 checks:
- wedge length equals `T` and is finite
- ξ ∈ (0,1]
- 0 ≤ opt_out ≤ 1
- r ≥ 1
- W ≥ 1
- duplicate or unknown actor sites

### Report-never-throw certificates
**Source:** `price_taker_dispatch` (`price_taker.jl:121-139`), which `try`/`catch`es `CertificateError` into a recorded status (`battery_certificate = :refused`, plus message) and never rethrows or loosens τ.
**Apply to:** the slot-λ agreement certificate `max_s |λ_s − λ_bus|`, sweep refusals, and any wrapper certificate skip.

### Solver abstraction
**Source:** `Model(select_optimizer(QP()))` (`price_taker.jl:101`, `AgrOpt.jl` default kwarg `optimizer = select_optimizer(QP())`).
**Apply to:** `_device_baseline` and any new model. Never name Clarabel or HiGHS.

### Anonymous JuMP objects
**Source:** `Aggregator.jl:178-189` comment (named containers collide when two aggregators contribute to one model) and the `ElectricVehicle.jl` header.
**Apply to:** the wrapper `rebound_u` variables and anything created in `contribute!`.

### Exact money conservation via mirror pairs
**Source:** `SettlementLedger.jl:105-130`.
**Apply to:** the actor profit line. Never add new conservation logic.

### Seeding
**Source:** `_flex_mix` + `StableRNGs.LehmerRNG` (`materialize.jl:557-577`).
**Apply to:** the `BehaviourSpec` opt-out draw. Per-device granularity on `:default`, since one house maps to one bus aggregator.

### Welfare honesty (M4/C7)
**Source:** `welfare_solve.jl:242` structure.
**Apply to:** every non-default result. `welfare` is recomputed from utilities minus `λ₀ᵀ p_import`. The actor objective is a separate field. ΔW is reported absolute and relative. Assert `W_soc ≤ W_opt` within the measured tolerance.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `src/devices/Behavioural.jl` (wrapper composition) | device wrapper | request-response | No existing device wraps another device. `ElectricVehicle` is the closest for the contract, but delegation to `inner.contribute!`, the blending math, and trait forwarding are new. Use RESEARCH Pattern 4. |
| `Rebound` linear energy-recovery constraint | constraint | transform | No windowed recovery constraint exists. `Deferrable` window bounds (`_ev_in_window`) are the nearest idiom (pure bounds), but the `u_t ≥ c^b_t − c_t` and `Σ_{τ=t+1}^{t+W}(c_τ − c^b_τ) ≥ r·u_t` constraints come from RESEARCH Pattern 4. |

`SlotTable` has only a partial analog (`AdmmState.agr_by_bus` and `load_nodes` keyed dictionaries). Its design is in RESEARCH Pattern 3.

## Metadata

**Analog search scope:** `src/devices/`, `src/admm/`, `src/models/`, `src/pricing/`, `src/settlement/`, `src/experiments/`, `test/`, `scripts/`, `docs/`.
**Files read this session:** `AgrOpt.jl` (partial), `CapabilityTraits.jl`, `AbstractDevice.jl` (partial), `fit.jl` (partial), `materialize.jl` (partial), `price_taker.jl`, `SettlementLedger.jl` (partial), `equity.jl` (partial), `welfare_solve.jl` (partial), `ElectricVehicle.jl` (partial), `admm_phases.jl` (partial), `solve_admm.jl` (partial), `run_inputs.jl` (partial), `Aggregator.jl` (partial), `test_flex_population.jl` (partial), `socp_highpv_remeasure.jl` (partial), `socp_highpv_exactness.jl` (partial).
**Pattern extraction date:** 2026-11-02
