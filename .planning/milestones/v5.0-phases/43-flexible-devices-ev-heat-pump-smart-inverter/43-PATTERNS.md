# Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter) - Pattern Map

**Mapped:** 2026-10-26
**Files analyzed:** 13 (3 new device files, 4 modified src files, 1 new certificate, 4+ new test files, 1 optional measurement script)
**Analogs found:** 13 / 13 (2 partial — EV shortfall epigraph, trait-equivalence test)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/devices/ElectricVehicle.jl` | model (device) | request-response (`contribute!` NamedTuple) | `src/devices/PVBattery.jl` (+ `Deferrable.jl` window pins, `FourQuadBESS.jl` V2G) | exact |
| `src/devices/HeatPump.jl` | model (device) | request-response | `src/devices/Thermostatic.jl` | exact |
| `src/devices/SmartInverterPV.jl` | model (device, reactive) | request-response (`q_inject` widened contract) | `src/devices/FourQuadBESS.jl` (+ `PVBattery.jl` curtailment) | exact |
| `src/devices/AbstractDevice.jl` (modify) | model (trait) | — | self (`is_flexible_load` precedent, line 84) | exact |
| `src/admm/DsoOpt.jl` (modify) | service (ADMM subproblem) | request-response | self (`_any_flexible_reactive` probe, lines 170-176, 323-339) | exact |
| `src/admm/admm_state.jl` (modify) | service (ADMM state) | event-driven (hooks) | self (`_default_reactive_consensus` 409-410, var-sniff 439) | exact |
| EV certificate (`assert_ev_complementarity!` — new, location at planner's discretion) | utility (certificate) | post-solve check | `src/models/complementarity_4q.jl` + `welfare_solve.jl:352-388` | exact |
| `src/models/welfare_solve.jl` (modify, var-sniff → trait) | utility | post-solve check | self (`assert_battery_complementarity!` selection loop 364-366) | exact |
| `src/admm/AgrOpt.jl` (modify, EV-cert kwarg) | service (ADMM subproblem) | request-response | self (`check_battery`/`τ_batt` kwargs 199/268, gating 325-336) | exact |
| `src/TSODSO.jl` (modify) | config (wiring) | — | self (device include block 118-129, `@compat public` 332) | exact |
| `src/experiments/materialize.jl` (modify: EV sessions + population branch) | service (population build) | batch | self (`_case_a_house_seed` 403-404, `_case_a_house` 444-489, `build_population` 546+) | exact |
| `test/test_electricvehicle.jl`, `test_heatpump.jl`, `test_smartinverterpv.jl`, trait-equivalence test | test | — | `test/test_pvbattery.jl`, `test/test_device.jl`, `test/test_admm.jl` (crossval), fixtures modules | exact |
| `scripts/` exactness re-measurement (OPTIONAL per context) | utility (measurement) | batch | `scripts/socp_applicability_sweep.jl` + `benchmark_ieee8500.jl:810-829` upsert | role-match |

---

## Pattern Assignments

### `src/devices/ElectricVehicle.jl` (model, V1G/V2G storage + session window)

**Analog:** `src/devices/PVBattery.jl` — copy its file anatomy verbatim; `Deferrable.jl` supplies the window-pin idiom.

**File anatomy to copy (PVBattery.jl):**
1. Header comment block `# src/devices/X.jl` + `# SEAM: ...` naming the thesis eqs. and the no-binary argument (`PVBattery.jl:1-16`)
2. `using JuMP` (`PVBattery.jl:18`)
3. Docstring-heavy `struct ElectricVehicle{T <: Real} <: AbstractDevice` with field-by-field docs incl. the *load-bearing guard* explanation (`PVBattery.jl:20-91`)
4. Throw-guarded inner constructor — **project convention: throw, never `@assert`** ("`@assert` elides under -O", `PVBattery.jl:126`); each guard a separate `if ... throw(ArgumentError("...context...got X=$X"))` (`PVBattery.jl:105-161`)
5. Promotion outer constructor via `promote_type` over every scalar + `eltype` of every vector, `Int(bus)` conversion, keyword args (`φ`, flags) excluded from promote and separately `convert`ed (`PVBattery.jl:175-213`; `Union{Nothing,T}` kwarg handling: `Thermostatic.jl:197-208`)
6. `contribute!(d::ElectricVehicle, ctx::ModelContext; T::Int, ...)` returning `(; vars = (; ...), p_inject, utility)` — writes NOTHING to `ctx.residuals`, calls NO `add_to_objective!` (`PVBattery.jl:253-360`)
7. Final `export ElectricVehicle` (`PVBattery.jl:362`)

**Core model pattern** (`PVBattery.jl:276-330`):
```julia
# Continuous decision variables ONLY — NO binary/integer (App. C keeps this a QP).
p_ch  = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)   # (3.8)
p_dch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)
soc = @variable(m, [t = 1:(T + 1)], lower_bound = d.Emin, upper_bound = d.Emax) # T+1 long!
...
@constraint(m, [t = 1:T],
    soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt)   # WHOLE horizon 1:T
if soc_terminal isa Real
    @constraint(m, soc[T + 1] == soc_terminal)
elseif soc_terminal === :cyclic
    @constraint(m, soc[T + 1] >= soc0)        # vs the SAME soc0 Parameter
end
```
The EV must keep: `soc` `T+1`-long recursion closing the WHOLE horizon (never `1:(T-1)` — free hour-T energy bug is documented at `PVBattery.jl:317-320`), and the `soc_terminal::Union{Nothing,Real,Symbol}` kwarg with the `:cyclic`-against-Parameter idiom (`PVBattery.jl:253-266` kwarg validation + `326-330`).

**Session window — HARD bounds, binary-free.** Copy `Deferrable.jl:222-228`'s conditional-bound pin (this is the established no-binary availability idiom; `Deferrable` is documented as the "washer, EV charge" device, `Deferrable.jl:5,21`):
```julia
p = @variable(m, [t = 1:T], lower_bound = 0.0,
    upper_bound = (d.t_start <= t <= d.t_end ? d.Pmax : 0.0))   # pinned to 0 outside window
```
Plus the window-fits-horizon guard to copy (`Deferrable.jl:211-219`: `d.t_end > T` → `ArgumentError`). EV applies the same to `p_ch`/`p_dch` over `[t_arr, t_dep]` and pins `soc[1]` at the arrival SOC.

**Soft departure target (V1G).** No in-repo epigraph precedent (closest is `Deferrable.jl:248`'s direct concave soft-target `utility = -(d.b / 2) * (total_energy - d.E)^2` — a LIVE preference whose budget is an INEQUALITY, `Deferrable.jl:230-236`). The quadratic epigraph `s ≥ E_target − soc[t_dep+1]`, `−(κ/2)·s²` is new math — build it as a `QuadExpr` utility term with an explicit `s ≥ 0` variable; the concavity reasoning to document mirrors `Deferrable.jl:87-96`'s `b > 0` guard.

**V2G + certificate hook.** Copy `FourQuadBESS.jl`'s independent-caps treatment (`p_dch` with its own bound, `FourQuadBESS.jl:337`) and its re-derived no-binary docstring structure (`FourQuadBESS.jl:48-90` — "the argument must be RE-EARNED, not transferred"): the EV docstring must extend App. C by `c_deg > 0` and cite the repo's own η<1 co-charge finding (`welfare_solve.jl:276-283`). Add `c_deg * p_dch[t]` into the utility sum (linear cost term, cf. `−a_dch * p_dch[t]` in `PVBattery.jl:346-352`).

**Anonymous Parameter discipline.** If the EV carries `soc0`/availability Parameters, they MUST be anonymous (`@variable(m, set = Parameter(d.soc0))`, `PVBattery.jl:309-316`; the named-form collision failure mode is documented at `PVBattery.jl:294-304` and `Aggregator.jl:178-188`).

**Adapt:** session fields (`t_arr::Int`, `t_dep::Int`, `E_target::T`, `v2g::Bool`-style opt-in kwarg mirroring `φ`'s `Union{Nothing,T}` kwarg treatment), arrival-SOC pin replacing the free `soc[1]`.

---

### `src/devices/HeatPump.jl` (model, 2R2C flexible load)

**Analog:** `src/devices/Thermostatic.jl` — copy the file end to end.

**Struct + guards** (`Thermostatic.jl:62-162`): `bus::Int`, scalar `T`-typed params, profile `Vector{T}`, `φ::Union{Nothing,T}`; concavity guard (`b <= 0` → throw, lines 91-98), band-order guard (99-106), power-bound guard (107-114), physical-sign guards on recursion coefficients (119-138), IC-inside-band guard (142-149), `φ` override guard (152-159). HeatPump needs the same class of guards for its 2R2C coefficients (both coupling fractions ≥ 0, gains sign-correct, both ICs inside their bands).

**Trait override** (`Thermostatic.jl:164-166`) — one line after the struct, before the outer constructor:
```julia
# A Thermostatic load's own consumption draws power-factor reactive power via the
# Aggregator roll-up (thesis eq. 3.23).
is_flexible_load(::Thermostatic) = true
```
HeatPump copies this verbatim (`is_flexible_load(::HeatPump) = true`).

**Exogenous-profile validation at contribute! time** (`Thermostatic.jl:257-266`) — the exact `COP::Vector{T}` guard:
```julia
if length(d.Tout) < T
    throw(ArgumentError("Thermostatic ambient profile Tout has length $(length(d.Tout)) < " *
        "horizon T=$T (thesis eq. 3.2 recursion)"))
end
```
Per context: COP mirrors `Tout` (validated `length ≥ T`), NOT a JuMP `Parameter` seam.

**Two-state recursion** (`Thermostatic.jl:293-302` is the 1-state form): adapt to the 2R2C coupled pair — BOTH states `T+1` long (the PVBattery whole-horizon rule, `PVBattery.jl:278-280`), recursion over `t = 1:T` unconditionally closing on `state[T+1]`, comfort band applying at `T+1`, optional `terminal` kwarg mirroring `soc_terminal`. Note `Thermostatic.jl:301`'s `T == 1` fallback (`Tout_param = JuMP.VariableRef[]`) if any Parameter is used.

**Utility + injection** (`Thermostatic.jl:304-312`): concave-quadratic `−(b/2)·Σ(Tin−Tmin)²` as `QuadExpr`; `p_inject = AffExpr[-p[t] for t in 1:T]` (load = NEGATIVE injection). Heat-pump draw is `p ∈ [0, Pmax]` (heating convention `+COP·p`, constructor-sign-guarded).

**Adapt:** second state `Tem`, ambient coupling between the two states, no change to `Thermostatic.jl` itself (byte-identical golden policy).

---

### `src/devices/SmartInverterPV.jl` (model, reactive-capable PV generator)

**Analog:** `src/devices/FourQuadBESS.jl` (reactive contract + cone) + `PVBattery.jl` (curtailment).

**Widened contract** (`FourQuadBESS.jl:302-305, 406`): return `(; vars, p_inject, q_inject, utility)` with `q_inject = q` the SAME `Vector{VariableRef}`; `AbstractDevice.jl:49-62` documents the optional-`q_inject` widening; `Aggregator.jl:203-207` consumes it via `hasproperty(res, :q_inject)` — **no Aggregator change needed**.

**The cone — copy VERBATIM** (`FourQuadBESS.jl:377-385`):
```julia
# Apparent-power cone: p²+q²≤Smax² ⟺ ‖(p_net,q)‖₂ ≤ Smax — the SAME idiom ...
# Un-registered (device-level ...) and ANONYMOUS: a NAMED `cone[t = 1:T]` container
# claims the JuMP object-dictionary symbol `:cone` ... anonymity is exactly why multiple
# devices compose.
@constraint(m, [t = 1:T], [d.Smax, p_net[t], q[t]] in SecondOrderCone())
```
Context pins this as `FourQuadBESS.jl:385` verbatim. For SmartInverterPV the leg is `[S_inv, pv_used[t], q[t]] in SecondOrderCone()`.

**No utility on q** (`FourQuadBESS.jl:341-343, 387-393`): `q = @variable(m, [t = 1:T])` free-sign, unbounded, and the utility sum contains NO `q` term anywhere — copy the comment ("no cost or utility term on reactive power anywhere").

**Curtailment** (`PVBattery.jl:281-307`): `pv_used = @variable(m, [t = 1:T], lower_bound = 0.0)`; if the PV limit is a literal profile bound keep `pv_used[t] <= Ppv_param[t]` (307) or a plain `upper_bound` if no Parameter seam is wanted (context: no MPC seam this phase — a literal bound is fine).

**Constructor guards** (`FourQuadBESS.jl:136-220`): independently-checked positive caps + the `Smax > 0` guard (169-176) → `S_inv > 0` per context.

**Adapt:** no battery fields at all (no `soc`, no λ-triple needed unless V1G-style economics are wanted — context says Q carries no utility; the active side is a PV generator, so utility may be zero/absent and `p_inject[t] = pv_used[t]`).

---

### Capability traits on `src/devices/AbstractDevice.jl` (MODIFY)

**Analog (self):** `is_flexible_load` — `AbstractDevice.jl:74-86`:
```julia
"""
    is_flexible_load(d::AbstractDevice) -> Bool

Trait identifying devices whose CONSUMPTION should draw power-factor reactive power ...
Defaults to `false` for any device; ...
"""
is_flexible_load(::AbstractDevice) = false
```
New traits (`has_reactive_decision`, storage classification) copy this shape: docstring + one-line default method on the abstract type; overrides as one-liners in each device file (`Thermostatic.jl:166`, `Deferrable.jl:144`). Defaults MUST classify every existing device exactly as today; export via the `@compat public` list (`TSODSO.jl:330-335`).

**Probe sites to refactor (behavior-identical):**
- `src/admm/DsoOpt.jl:170-176` `_any_flexible_reactive` — `any(dv -> dv isa FourQuadBESS || is_flexible_load(dv), agg.devices)` (line 173) → trait-driven predicate
- `src/admm/DsoOpt.jl:323-339` the OFF/CERTIFIED guard — same probe at line 326 (keep the `normalize_reactive_mode` discipline documented at 229-234)
- `src/admm/admm_state.jl:409-410` `_default_reactive_consensus(aggregators) = _any_flexible_reactive(aggregators) ? LIVE : OFF`
- `src/admm/admm_state.jl:437-443` `_react_outputs` — `haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)` sniff (439) → storage-class trait
- `src/models/welfare_solve.jl:364-366` — the symmetric battery sniff `(haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q)) || continue` → trait, keeping the battery/4Q checks mutually exclusive (`complementarity_4q.jl:33-38` documents the exclusivity contract)

---

### EV certificate (`assert_ev_complementarity!`-style)

**Analog:** `src/models/complementarity_4q.jl:115-156` — copy its full skeleton:
```julia
function assert_4q_complementarity!(ctx::ModelContext; rtol = 1e-4, atol = 1e-8,
                                    T::Int = _require_T(ctx), report::Bool = false)
    !isempty(ctx.agg_device_vars) || return 0.0
    for (bus, varlist) in ctx.agg_device_vars
        for v in varlist
            (haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)) || continue  # own shape
            ... scale recovery via has_upper_bound/upper_bound (131-133), tol = atol + rtol·scale² (134)
            ... ratio tracking, maxratio = max(maxratio, ratio) (137-138)
            prod <= tol && continue
            msg = "..."   # names bus/time/values/tolerance
            report ? @warn msg : throw(CertificateError(msg; kind = :four_quadrant))
```
Also copy from `welfare_solve.jl:352-388`: the `on_violation in (:error, :warn)` kwarg validation with `ArgumentError` (358-362), the scale-free `prod >= τ · scale²` relative test (369-377), `CertificateError(msg; kind = ...)` (379).

**MANDATORY conventions from `complementarity_4q.jl`:**
- Tolerance provenance section documenting OWN measured noise floor — "reusing another device's constant would be certificate-laundering (the v3.0 standing bar: every new mathematical regime earns its OWN measured tolerance)" (`complementarity_4q.jl:60-95`). The EV certificate's `τ·Pmax²` form + its own measured `τ`.
- `report = true` neutralization kwarg so the negative-price co-charge boundary is reportable, not muted (`complementarity_4q.jl:14-18, 147-151`) — this is exactly the honesty-policy vehicle for the negative-price fixture.
- Selection by the device's OWN distinguishing var shape; never silently overlapping the battery or 4Q checks.
- `error(...)`/throw, never `@assert` (`complementarity_4q.jl:112-113`).

**ADMM wiring analog:** `src/admm/AgrOpt.jl:199` (`check_battery::Bool = true, τ_batt::Real = 1e-6, strict::Bool = true` kwarg style), 268 (function signature), 325-336 (mid-loop off / final on gating) — the EV cert follows the same kwargs-and-gating pattern. `solve_welfare`'s own call-site pattern: `welfare_solve.jl:284-285` (problem-class-aware `on_violation`).

---

### `src/TSODSO.jl` wiring (MODIFY)

**Analog:** the devices block `TSODSO.jl:118-129`:
```julia
include("devices/AbstractDevice.jl")
include("devices/Interruptible.jl")
...
include("devices/PVBattery.jl")
include("devices/FourQuadBESS.jl")
include("devices/FixedCapacitor.jl")
...
include("devices/Aggregator.jl")   # devices BEFORE Aggregator (Aggregator contribute!s them)
```
New device includes go after `FourQuadBESS.jl` (context decision) and before `Aggregator.jl`. Per-file exports are the convention — "file declares its own exports" (`TSODSO.jl:185, 197` comments; each device file ends with its own `export X`). Trait generics go in the `@compat public` list (`TSODSO.jl:330-335` — `is_flexible_load` precedent at line 332).

---

### `src/experiments/materialize.jl` — EV session generation + population opt-in (MODIFY)

**Seeded-draw idiom** (`materialize.jl:24, 388-404`):
```julia
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))          # line 24
_case_a_house_seed(s_pop::Integer, bus::Int, house_index::Int) =
    Int(hash((s_pop, :house, bus, house_index)) % typemax(UInt32))                           # 403-404
```
EV sessions follow with a richer tag tuple (`hash((seed, :ev, bus, house_index))`-style per context). Document: per-HOUSE never per-bus (collapsing rationale at `materialize.jl:397-401`), collision-freeness asserted by test.

**Per-house construction analog** (`_case_a_house`, `materialize.jl:444-489`): scales divided by houses-per-bus (`hs/ps/ds`, 455-457), profile via `generate_profiles(; seed = _case_a_house_seed(...), T)` (458), device construction with the `_DEFAULT_BATT_λ_*` constants (475-487), returned inside `Aggregator(bus, 0.90, [devices], Pdc)` (488). EV construction slots in here (or a sibling `_case_a_ev` helper) with documented low-confidence session parameters.

**Population opt-in** (`build_population`, `materialize.jl:546+`): the `:case_a_784` branch (547-555) shows the additive-branch pattern — a `sym === :...` branch + per-selector `ArgumentError` guard. New devices enter via an additive selector branch/kwarg; `:default` and `:case_a_784` stay byte-identical; `Scenario.jl` untouched (schema-fragile, golden-hash-bearing).

---

### Test files (`test/test_electricvehicle.jl`, `test_heatpump.jl`, `test_smartinverterpv.jl`, trait-equivalence)

**Analog item anatomy** (`test/test_pvbattery.jl`):
- Header comment naming the seam + selection substring ("Every item name contains 'battery' so `occursin(...)` selects it", lines 1-11)
- `@testitem "battery: ..." tags = [:battery] setup = [SmallRadialFixtures] begin ... end` (13-14); explicit `using TSODSO` in EVERY item (no implicit using — `runtests.jl:61-63`)
- Constructor-guard item: valid `good()` factory + one `@test_throws ArgumentError` per guard + mixed-type promotion test (26-183)
- Standalone-solve item: `Model(select_optimizer(TSODSO.QP()))` + `ModelContext(model)`, device contributed with NO feeder, objective closed by a hand price vector, `TSODSO.assert_solved!(model; dual = true, allow_local = false)` solve gate (185-215), property assertions on the returned NamedTuple (201-206)
- **Zero-binary invariant — copy for every new device** (`test_pvbattery.jl:234-246`):
```julia
vars = all_variables(model)
@test length(vars) == 5T + 2       # exact counted-variable golden (count YOUR model's own)
@test count(is_binary, vars) == 0
@test count(is_integer, vars) == 0
```
- Contract-shape checks (`test/test_device.jl:44-47, 57-77`): `propertynames(res) == (:vars, :p_inject, :utility)` (or the widened 4-tuple), `isempty(ctx.residuals)`, `isempty(ctx.objective.terms)`, `p_inject` sign convention, `utility isa QuadExpr` with curvature retained

**Centralized-vs-ADMM gate (gate-then-golden)** — `test/test_admm.jl:25-77`:
```julia
ctx_c, obj_c, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs;
    T = Th, λ₀ = λ₀, allow_export = true,
    optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10))   # 51-59
res = solve_admm(...)
@test isapprox(res.welfare, obj_c; rtol = 1e-4)                          # 73 welfare match
@test isapprox(vec(res.λ), vec(dlmp_c); atol = 1e-2, rtol = 1e-3)        # 75 dual match
```
MEASURE the agreement bands on the new fixtures first, then pin them (gate-then-golden — the 2-bus fixture's own precision-floor note at 42-50 shows the measurement-before-pinning discipline). Fixtures: `@testmodule` function/const-only modules — `SmallRadialFixtures` (`fixtures_small_radial.jl:13-57`: `const T = 24`, sinusoidal `Tout/Pdc/Ppv/λ₀` consts, explicit `export`) or `IEEE13Fixtures` (`fixtures_ieee13.jl:25+`; `high_pv_feeder` 184, `build_high_pv_aggregators` 222 — the high-PV substrate for SmartInverterPV; "defines functions and consts ONLY, no load-time evaluation", lines 8-11).

**Infra rules** (`runtests.jl`, `runner_support.jl`): `TSODSO_TEST_SET` = fast|slow|all (`runtests.jl:40-48`); `:slow` gating is `(set == "slow") == (:slow in ti.tags)` (`runner_support.jl:56`) — tag heavy crossval items `tags = [..., :slow]`; any new `@test_broken`/`@test_skip` must be listed in `test/expected_broken.txt` or the run fails (`runtests.jl:45-48`); avoid soft-scope bare reassignment inside item-top-level loops — use a `let` block (`runtests.jl:8-33`).

**Trait-equivalence test:** no direct precedent (nearest topical: `test/test_reactive_mode.jl` for ReactiveMode unit coverage). Prove `has_reactive_decision`/storage traits classify every existing device exactly as the old `dv isa FourQuadBESS || is_flexible_load(dv)` probes and the `haskey` sniffs did — enumerate device instances and assert old==new for each.

---

### `scripts/` exactness re-measurement (OPTIONAL — planner's discretion per context)

**Analog:** `scripts/socp_applicability_sweep.jl` — `using CSV, DataFrames` (34), `const OUT = projectdir("results", "socp_applicability")` (94), `CSV.write(joinpath(OUT, "highpv_3bus_sweep.csv"), df)` (508, 586). `scripts/pv_boom_case_study.jl` is the high-PV-regime narrative precedent (header 1-40: pure orchestration through the public API, no `src/` edits) with `CSV.write(projectdir("results", "pv_boom", "summary.csv"), summary_df)` (318).

**CSV upsert** — `scripts/benchmark_ieee8500.jl:808-829`:
```julia
function upsert_sweep_rows(csv_path::AbstractString, df_new::DataFrame)
    df_final = if isfile(csv_path)
        df_old = CSV.read(csv_path, DataFrame)
        keyfn(r) = (r.fixture, r.density, r.solver, ...)   # YOUR measurement's key
        new_keys = Set(keyfn(r) for r in eachrow(df_new))
        vcat(filter(r -> !(keyfn(r) in new_keys), df_old), df_new; cols = :union)
    else
        df_new
    end
    CSV.write(csv_path, df_final)
end
```
`cols = :union` is mandatory for schema evolution (820-822). Measurement through the standard gates: `assert_socp_exact!` / `hybrid_ratios` / `socp_gap_report` (exported via `TSODSO.jl:337-340`; `welfare_solve.jl:268-270` shows the `ctx.meta[:socp_maxgap]` stash). "Refused with certificate" is a valid recorded outcome (honesty policy).

---

## Shared Patterns

### Fail-loud constructor guards
**Source:** `PVBattery.jl:105-161`, `Thermostatic.jl:91-159`, `FourQuadBESS.jl:136-220`
**Apply to:** all three new device files
```julia
if !(λ_min < λ_med < λ_max)
    throw(ArgumentError("PVBattery requires STRICT λ_min < λ_med < λ_max (...reason...); got λ_min=$λ_min, ..."))
end
```
Reason-in-message, values in message, `throw` never `@assert`. Promotion outer constructors: `PVBattery.jl:175-213` (positional) / `Thermostatic.jl:184-222` (with `Union{Nothing,Real}` kwarg handling).

### ANONYMOUS JuMP construction
**Source:** `PVBattery.jl:294-307`, `FourQuadBESS.jl:377-385`, `Aggregator.jl:178-189`
**Apply to:** every `@variable`/`@constraint`/cone/Parameter in all new files. Named containers register object-dictionary symbols that collide the moment a SECOND instance contributes to the shared model ("An object of name X is already attached to this model") — the recurring production failure documented at each site.

### T+1 state, whole-horizon closure, terminal kwarg
**Source:** `PVBattery.jl:278-330`, `FourQuadBESS.jl:338-371`
**Apply to:** EV `soc`, HeatPump `Tin`/`Tem`. Recursion `t = 1:T` closing on `state[T+1]`; optional `terminal::Union{Nothing,Real,Symbol}` kwarg with `:cyclic` against the IC Parameter.

### Aggregatable return contract
**Source:** `AbstractDevice.jl:25-39, 49-62`; return sites `PVBattery.jl:359`, `FourQuadBESS.jl:406`, `Thermostatic.jl:312`
**Apply to:** all new devices. Return `(; vars, p_inject, [q_inject], utility)`; write NOTHING to residuals/objective; `Aggregator.contribute!` (`Aggregator.jl:198-224`) consumes it unchanged — `hasproperty(res, :q_inject)` (203) and `is_flexible_load(d)` (215-221) are the two opt-in seams; **zero Aggregator edits required**.

### Certificate discipline (own tolerance, :error/:warn, CertificateError kind)
**Source:** `complementarity_4q.jl:60-102, 115-156`; `welfare_solve.jl:352-388`
**Apply to:** the EV certificate (and any new gate). Never reuse another regime's tolerance; document the measured noise floor; `on_violation`/`report` kwarg; iterate `ctx.agg_device_vars`; select by the device's own var shape.

### Byte-identical default path
**Source:** context + `materialize.jl` (`:default` untouched), `PVBattery.jl:249-251` (Parameter-widening invariant)
**Apply to:** trait refactor (defaults resolve-identical), new device files (opt-in only), population branch (`:default`/`:case_a_784` byte-identical), canary (`iters = 56`, `welfare = -4823.66604824162`) never re-pinned.

### Naming & commit conventions
- Files: one struct per file in `src/devices/`, file name = struct name (`ElectricVehicle.jl`, `HeatPump.jl`, `SmartInverterPV.jl`); each file ends with its own `export X` (`PVBattery.jl:362`).
- Tests: `test_<device>.jl` with a tag per class (`tags = [:electricvehicle]`-style; precedent `[:battery]`, `[:device]`, `[:admm]`), item names carrying the selection substring.
- Commits: conventional commits scoped to the phase — `feat(43): ...`, `fix(43): ...`, `test(43): ...`, `docs(43): ...` (git log precedent: `feat(42-06): ...` 2547e54, `fix(42): WR-01 ...` a1cc417, `docs(43): smart discuss context` a5dc4d5). Plan-scoped `feat(43-XX): ...` matches the 42-06 precedent. **Do NOT commit** (orchestrator instruction).
- Formatting: JuliaFormatter pinned 2.10.2, 92-col; tests only via `julia --project=. -e 'import Pkg; Pkg.test()'`.

## No Analog Found

| File / Concern | Role | Data Flow | Reason | Fallback |
|----------------|------|-----------|--------|----------|
| EV quadratic shortfall epigraph (`s ≥ E_target − soc[t_dep+1]`, `−(κ/2)s²`) | model fragment | — | No in-repo epigraph-variable precedent; `Deferrable.jl:248`'s direct quadratic soft target is the nearest shape | RESEARCH.md features rows 65-71; document concavity like `Deferrable.jl:87-96` |
| Trait-equivalence regression test | test | — | First trait-refactor in repo history | Enumerate existing devices, assert old probe == new trait per instance |
| Volt-VAR droop post-hoc comparator | diagnostic | post-solve | No droop code exists (DEV-F1 future); physics-only rerun idiom exists: `ACPowerFlow(; limits = false)` (`src/powerflow/ACPowerFlow.jl:94-113`, usage `test/test_fit.jl:60`, `test/test_mpc_loop.jl:64`) | Evaluate fixed dispatch through ACPowerFlow physics-only mode, report diagnostics in artifact |

## Metadata

**Analog search scope:** `src/devices/`, `src/admm/`, `src/models/`, `src/experiments/`, `src/TSODSO.jl`, `test/`, `scripts/`
**Files read:** 16 in full or targeted (`AbstractDevice`, `PVBattery`, `Thermostatic`, `FourQuadBESS`, `Deferrable`, `Aggregator`, `welfare_solve`, `complementarity_4q`, `DsoOpt`, `admm_state`, `materialize`, `TSODSO`, `AgrOpt` (grep), `test_pvbattery`, `test_device`, `test_admm`, `runtests`, `runner_support` (grep), fixture modules, `benchmark_ieee8500` (targeted), `socp_applicability_sweep`/`pv_boom_case_study` (grep))
**Pattern extraction date:** 2026-10-26
