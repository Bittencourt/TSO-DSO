# Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter) - Research

**Researched:** 2026-10-26
**Domain:** Convex, binary-free prosumer device models in the existing JuMP welfare/ADMM framework (EV V1G/V2G storage, 2R2C heat pump, smart-inverter PV reactive capability) + device-capability trait refactor
**Confidence:** HIGH (all claims grounded in this repo's own source, read this session; external math citations marked individually)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**EV Device Model (V1G / V2G, DEV-06/07)**
- New dedicated `ElectricVehicle{T} <: AbstractDevice` struct in `src/devices/ElectricVehicle.jl`
  (one struct per device is the project convention — `PVBattery`/`Thermostatic`/`FourQuadBESS`
  precedents; throw-guarded inner constructor + promotion outer constructor), NOT a parameterized
  reuse of `PVBattery` or `Deferrable`. It mirrors the `PVBattery` App. C shape (η, Δt, Pmax,
  Emin/Emax band on `soc`, strict λ-triple utility) with EV-specific session data.
- Charging windows are HARD BOUNDS, binary-free by construction: `p_ch` (and V2G `p_dch`) are
  constrained to zero outside the session window `[t_arr, t_dep]` (zero upper bounds / `== 0`
  constraints), `soc[1]` pinned at the arrival SOC. NO big-M and NO availability mask via binary —
  big-M is a disguised binary (banned by the project rule) and degrades QP conditioning. `soc` is
  `T+1` long with the recursion closing the WHOLE horizon (the PVBattery free-energy rule).
- Soft departure energy target (V1G): convex quadratic epigraph — an auxiliary `s ≥ 0` with
  `s ≥ E_target − soc[t_dep+1]` and a concave-from-the-welfare-side penalty `−(κ/2)·s²` (or affine
  `−κ·s`; exact form chosen at planning with the QP-style quadratic preferred) — keeping the model
  a convex QP and always feasible. A hard `soc[t_dep+1] ≥ E_target` constraint is the alternative,
  rejected as the default (infeasibility risk).
- V2G: discharge enabled with a STRICTLY POSITIVE linear degradation cost `c_deg·p_dch[t]`. A
  DEDICATED `assert_ev_complementarity!`-style post-solve certificate (scale-free `p_ch·p_dch <
  τ·Pmax²` form, same `:error`/`:warn` convention) is MANDATORY, exercised on a negative-price
  fixture where co-charge would appear without the degradation cost. V2G is opt-in (a constructor
  field/kwarg); the V1G default path stays the smaller model.

**Heat Pump (DEV-08)**
- New dedicated `HeatPump{T} <: AbstractDevice` struct in `src/devices/HeatPump.jl` with a 2R2C
  two-state building thermal model (indoor-air `Tin` + envelope-mass `Tem` states, coupled linear
  recursion with the ambient profile) — `Thermostatic` is NOT modified (byte-identical golden
  policy; realized as a new device following the `Thermostatic` template).
- COP is an EXOGENOUS per-step parameter vector `COP::Vector{T}` (validated `length ≥ T` at
  `contribute!` time, exactly like `Thermostatic`'s `Tout`), so heat `Q = COP[t]·p` stays LINEAR
  and the model convex. No endogenous temperature-dependent (Carnot) expression. No JuMP
  `Parameter` seam in this phase for COP (mirror `Tout`, not `Ppv_param`).
- Comfort band is a HARD band on the indoor-air state plus the concave-quadratic comfort utility
  (the `Thermostatic` eq. 3.3 + 3.11 pattern, curvature `b > 0` guard). Consistent
  terminal-temperature rule: BOTH states are `T+1` long, the recursion unconditionally covers
  `t = 1:T` closing on `state[T+1]` with the band applying at `T+1` (the PVBattery whole-horizon
  closure rule), plus an optional `terminal` kwarg mirroring `PVBattery`'s `soc_terminal`
  (`nothing` default / `Real` / `:cyclic` against the initial-condition Parameter).
- The heat pump is a flexible LOAD: `is_flexible_load(::HeatPump) = true`, so it inherits the
  eq. 3.23 power-factor reactive draw through the existing `Aggregator` roll-up (with the
  per-device `φ` override convention); electric draw `p ∈ [0, Pmax]` in the heating convention
  (`+COP·p` heat gain, constructor-guarded signs).

**Smart-Inverter PV (DEV-09)**
- New dedicated `SmartInverterPV{T} <: AbstractDevice` struct in `src/devices/SmartInverterPV.jl`
  (the `FourQuadBESS` precedent): a PV generator with curtailable `pv_used` (the `PVBattery`
  curtailment pattern) and an optimal-Q reactive decision `q[t]`. `PVBattery` itself is NOT
  widened; households without batteries still get smart-inverter PV. Battery+inverter co-location
  via a combined device is a noted non-goal for this phase.
- Apparent-power cone: ONE ANONYMOUS per-t `SecondOrderCone` constraint
  `[S_inv, pv_used[t], q[t]] in SecondOrderCone()` — the `FourQuadBESS.jl:385` idiom verbatim
  (anonymous; never a named container). `S_inv > 0` constructor guard.
- Q carries NO device utility term (zero-cost optimal Q, the `FourQuadBESS` convention); welfare
  sees Q only through the network, priced only by the certified reactive DLMP
  (`extract_reactive_dlmp`, untouched). Thesis A3 is LIFTED for this device by routing its
  `q_inject` through the EXISTING reactive-consensus path (`qag_dso` pin / LIVE dual ascent) —
  never bypassing it.
- SOCP exactness re-measured in the high-PV regime: a fixture at high `pv_scale` (EXACT-04 /
  pv-boom regime) with and without optimal Q, measured through the standard gates
  (`assert_socp_exact!`/hybrid ratios) — "refused with certificate" is a valid measured outcome.
  Volt-VAR droop: POST-HOC comparator ONLY (the Phase-27/41 physics-only idiom,
  `ACPowerFlow(; limits = false)` + reported diagnostics) in the validation
  artifacts/literate page; NEVER a convex constraint; droop-as-control-loop remains DEV-F1.

**Capability Trait Refactor, Validation & Registration (DEV-10)**
- The refactor lands FIRST (success criterion 1): small trait functions on `AbstractDevice.jl` —
  (a) a reactive-capability trait (e.g. `has_reactive_decision(d)::Bool`, default `false`)
  replacing the hard-coded `dv isa FourQuadBESS || is_flexible_load(dv)` probes in `DsoOpt.jl` /
  `admm_state.jl`'s `_default_reactive_consensus`, and (b) a storage-classification trait so the
  battery-complementarity predicate's var-shape sniffing (`haskey(v, :p_ch) && haskey(v, :p_dch)
  && !haskey(v, :q)`) becomes trait-driven and the EV/V2G certificate reuses the same machinery.
  Defaults set so EVERY existing device classifies exactly as today — a test proves the
  equivalence (existing fixtures keep their resolved reactive mode; `:default` goldens unchanged).
- Per-device-class validation BEFORE ADMM use: one test file per new device
  (`test_electricvehicle.jl`, `test_heatpump.jl`, `test_smartinverterpv.jl` — the
  `test_pvbattery.jl`/`test_device.jl` convention), each with a small fixture (two-bus/IEEE-13
  scale) cross-validating the centralized `solve_welfare` optimum against the ADMM result
  (agreement bands MEASURED then pinned — gate-then-golden; `:slow`-tagged where heavy). A device
  class is used under ADMM only after its centralized match passes.
- Registration/naming: new files in `src/devices/` each declaring their own exports; include
  ordering after `PVBattery`/`FourQuadBESS` in `TSODSO.jl`. EV session sampling is seeded via the
  established hash idiom (`hash((seed, :ev, bus, house_index))`-style, the
  `_case_a_house_seed` pattern) with truncated-normal arrival/departure + lognormal energy draws
  whose parameters are DOCUMENTED as low-confidence calibration (ACN-Data/NHTS as check-later
  source).
- Population entry: new devices reach experiments through population-construction opt-ins
  (`build_population`-level selector branch/kwarg, the `:case_a_784` additive-branch pattern) —
  the `Scenario` schema is NOT touched in this phase. `:default` and `:case_a_784` stay
  byte-identical.

### the agent's Discretion
- Exact trait function names/signatures, the soft-target penalty's exact quadratic-vs-affine form,
  session-distribution parameter values (documented, low-confidence), fixture sizes, test/CSV
  naming, and whether the smart-inverter exactness re-measurement lands as a test or a literate
  artifact.

### Deferred Ideas (OUT OF SCOPE)
- Volt-VAR droop as an outer fixed-point control loop — DEV-F1.
- Reactive-power REMUNERATION of smart inverters in the settlement ledger — Phase 45.
- Battery + smart-inverter co-location in ONE device struct.
- EV session recalibration against ACN-Data/NHTS empirical data.
- Binary EV on/off, minimum charge power, compressor cycling — permanently out of scope.
- Aggregator-actor (ACTOR) coupling of the new devices — Phase 44 scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-06 | EVs with arrival/departure windows and a (soft) departure energy target as V1G devices, with seeded session sampling | EV formulation §EV Convex Formulation; window hard-bounds idiom (`Deferrable.jl:223-228`); seeding idiom (`materialize.jl:24,403-404`); soft-target epigraph pattern |
| DEV-07 | V2G with strictly positive degradation cost + certificate reporting simultaneous charge/discharge (negative-price fixture) | V2G linear degradation cost + `assert_ev_complementarity!`-style scale-free certificate; certificate machinery precedent (`welfare_solve.jl:352-388`, `complementarity_4q.jl`); App. C η<1 co-charge finding (`welfare_solve.jl:309-321`) |
| DEV-08 | Heat pumps with 2R2C thermal model, exogenous COP(T_out) profile, comfort band, consistent terminal rule | §2R2C Thermal Dynamics (literature-verified ODE + discretization); `Thermostatic` template (`Thermostatic.jl`); PVBattery T+1 closure rule |
| DEV-09 | PV smart-inverter reactive capability (apparent-power cone, optimal Q), SOCP exactness re-measured in high-PV regime, droop post-hoc only | `FourQuadBESS` cone idiom (`FourQuadBESS.jl:385`); reactive-consensus path (§Reactive-Consensus Path); `assert_socp_exact!` gates; `ACPowerFlow(; limits=false)` post-hoc idiom (`feasibility.jl:326`) |
| DEV-10 | Per-device-class centralized-vs-ADMM validation before ADMM use; trait refactor changes no behaviour | §Validation Harness Pattern (measured-tolerance tables, `:slow` policy); §Trait Refactor Seams (exact probe sites + equivalence-test design) |
</phase_requirements>

## Summary

Phase 43 adds three convex, binary-free devices to an already-mature device library whose
templates are unambiguous: `ElectricVehicle` clones the `PVBattery` storage anatomy (App. C
λ-triple, T+1 whole-horizon SOC closure, anonymous `soc0` Parameter) plus `Deferrable`'s
zero-upper-bound window idiom, a quadratic-epigraph soft departure target, and — for the V2G
opt-in — a linear degradation cost with its OWN measured-tolerance post-solve certificate;
`HeatPump` clones the `Thermostatic` thermal template extended to the standard 2R2C two-state
recursion (verified this session against the building-dynamics literature) with an exogenous
`COP::Vector` keeping heat linear; `SmartInverterPV` clones `FourQuadBESS`'s anonymous per-t
`SecondOrderCone` and no-utility-on-q convention attached to `PVBattery`'s curtailable-PV
pattern. All three plug into the EXISTING aggregator roll-up unchanged: `p_inject` always,
`q_inject` for SmartInverterPV, `is_flexible_load` power-factor draw for HeatPump, and the
`ctx.agg_device_vars` stash that feeds the complementarity certificates. No new Julia packages,
no new solvers, no Scenario schema changes.

Two refactor seams are load-bearing and must land FIRST: (1) the reactive-probe
`dv isa FourQuadBESS || is_flexible_load(dv)` appears at 3 code sites (`DsoOpt.jl:173`,
`DsoOpt.jl:326`, `admm_state.jl:409` via `_any_flexible_reactive`) and must become a trait with
a proven classification-equivalence test; (2) the battery-complementarity predicate
`haskey(v,:p_ch) && haskey(v,:p_dch) && !haskey(v,:q)` (`welfare_solve.jl:366`) will
**misclassify an EV's vars as a battery** the moment the EV lands (same `:p_ch`/`:p_dch` shape,
no `:q`) — so the storage-classification trait is not cosmetic: without it,
`assert_battery_complementarity!` runs battery semantics on EV vars and, on the V2G
negative-price fixture, throws on a legitimate optimum before the EV certificate can report it.
This is the concrete correctness reason success criterion 1 orders the trait refactor first.

Validation follows the established per-device gate-then-golden pattern: one test file per
device, each anchored on the two-bus fixture family, cross-validating `solve_welfare` against
`solve_admm` with tolerances MEASURED across multiple seeds then pinned (the
`fixtures_four_quad_bess.jl:40-49` measured table is the exact template), with `:slow` tags on
anything population-scale and the SOCP exactness re-measurement in the high-PV regime treated as
a measurement (a refusal is a recorded outcome, not a failure).

**Primary recommendation:** Land the trait refactor as its own plan with its equivalence test
green before any device file exists; then build the three devices as PVBattery/FourQuadBESS/
Thermostatic-template clones (one struct per device, anonymous JuMP objects, throw-guarded
constructors), each with its per-device centralized-vs-ADMM gate test, exercising the EV
certificate on a purpose-built negative-price fixture.

## Architectural Responsibility Map

Tier vocabulary adapted to this framework's layers (device → aggregator → model/ADMM →
experiment):

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| EV storage dynamics (soc recursion, windows, soft target) | Device (`ElectricVehicle.jl`) | — | Device owns its vars/constraints only; writes nothing to residuals/objective (aggregatable contract) |
| V2G co-charge certificate | Models (`assert_ev_complementarity!`-style, peer of `complementarity_4q.jl`) | `Aggregator` (stash provider) | Certificates are post-solve, iterate `ctx.agg_device_vars`; never inside the device |
| 2R2C thermal dynamics + comfort band | Device (`HeatPump.jl`) | — | Same contract; state recursion + band are device-local constraints |
| Heat-pump power-factor reactive draw (3.23) | Aggregator roll-up | Device (`is_flexible_load = true`, `φ` field) | Aggregator is the SOLE `:Rp`/`:Rq` writer; device only opts in via trait + override field |
| Smart-inverter apparent-power cone + optimal Q | Device (`SmartInverterPV.jl`) | — | Device-level cone, anonymous, un-registered (FourQuadBESS precedent) |
| Reactive pricing / Q consensus (LIVE μ-ascent, CERTIFIED pin) | ADMM (`DsoOpt.jl`, `admm_state.jl`) + `extract_reactive_dlmp` | Device (`q_inject` return only) | Devices never touch consensus; SmartInverterPV routes through the EXISTING path |
| Reactive/storage classification | Device traits (`AbstractDevice.jl`) | Consumers (`DsoOpt`, `admm_state`, certificates) | Traits live on the device hierarchy; consumers switch from shape-sniffing to trait calls |
| EV session seeding / population opt-in | Experiments (`materialize.jl`) | — | `build_population` selector/kwarg + `_case_a_house_seed` hash idiom; Scenario schema untouched |
| SOCP exactness re-measurement + droop comparator | Validation artifacts (test or literate + `results/` CSV) | `assert_socp_exact!` / `ACPowerFlow(; limits=false)` | Post-hoc measurement, never model constraints |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia | 1.12.5 local (compat floor 1.10) [VERIFIED: `julia --version`] | runtime | Pinned Manifest; unchanged from Phase 42 |
| JuMP | pinned in Manifest (1.30.x line) | modeling | `@variable` bounds/`Parameter`s/`SecondOrderCone`/QuadExpr utilities — every needed construct already used by the templates |
| Clarabel | pinned in Manifest | conic/QP solver | Accurate duals (prices are duals); handles QP + SOCP natively |
| Test + TestItemRunner | pinned | testing | `@testitem` per device class is the established harness |
| CSV + DataFrames | pinned | results CSVs (exactness re-measurement rows) | `upsert_sweep_rows` idiom already in `scripts/` |

**No new packages.** Every construct the three devices need (anonymous `Parameter`s, anonymous
`SecondOrderCone`s, QuadExpr utilities, dual-registered balances) is already exercised by
`PVBattery`/`FourQuadBESS`/`Thermostatic` in this repo.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Dedicated `ElectricVehicle` struct | Reusing/parameterizing `PVBattery` | LOCKED against: one-struct-per-device convention; session fields + soft-target + V2G kwarg would contaminate `PVBattery`'s golden-tested surface |
| Quadratic shortfall penalty `−(κ/2)s²` | Affine `−κ·s` | LOCKED to plan's choice, quadratic preferred: matches the codebase's quadratic-utility style; affine is exact too (linear penalty on the epigraph var drives `s` to the shortfall) but is a degenerate LP piece |
| Exact ZOH 2R2C discretization (`A = exp(ÃΔt)`) | Forward-Euler α/β coefficients (Thermostatic idiom) | Euler mirrors `Thermostatic`'s existing math and its constructor-guard style; exact discretization is unconditionally stable and literature-canonical. Planner picks; if Euler, add a stability note/guard on coefficients (see Pitfall 12) |
| Droop as post-hoc comparator | Droop as convex constraint | LOCKED against: piecewise-linear-with-deadband is nonconvex (FEATURES row 112) |

**Installation:** none (no `Pkg.add`).

**Version verification:** no ecosystem packages added this phase; Manifest already pins the
stack. Julia 1.12.5 confirmed on this machine this session.

## Package Legitimacy Audit

> No external packages are installed by this phase (Julia stdlib + already-pinned deps only).
> Audit not applicable; no slopcheck run needed.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none — zero new dependencies) | — | — | — | — | — | n/a |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                         build_population (materialize.jl)
                          (opt-in kwarg/branch: EV/HP/SIPV sessions,
                           hash-seeded per house; Scenario schema untouched)
                                      │  Vector{Aggregator} (devices concatenated)
                                      ▼
   ┌──────────────────────────  DEVICE LAYER (src/devices/)  ──────────────────────────┐
   │ ElectricVehicle        HeatPump              SmartInverterPV                      │
   │  soc 1:(T+1)           Tin, Tem 1:(T+1)      pv_used ≤ Ppv_param, q free          │
   │  windows ⇒ 0-bounds    hard band on Tin      [S_inv, pv_used[t], q[t]] ∈ SOC      │
   │  soft target s (epi)   Q=COP[t]·p (linear)   (ANONYMOUS per-t cone)               │
   │  V2G: +p_dch, −c_deg·p_dch utility                                            │
   │  traits: is_flexible_load=false   =true              has_reactive_decision=true │
   └──────┬────────────────────────┬───────────────────────────┬──────────────────────┘
          │ return                 │ return                    │ return
          │ (;vars,p_inject,       │ (;vars,p_inject,          │ (;vars,p_inject,
          │   utility)             │   utility)                │   q_inject, utility)
          ▼                        ▼                           ▼
   ┌───────────────────────  Aggregator.contribute! (sole :Rp/:Rq writer)  ─────────┐
   │ p_inject summed (3.22) · q_inject summed (hasproperty) ·                        │
   │ is_flexible_load ⇒ +p·tan(acos φ_used) (3.23) · utility summed (3.21) ·         │
   │ stash vars → ctx.agg_device_vars[bus]  ◄── now trait-classified (refactor b)    │
   └──────┬─────────────────────────────────────────────────────────┬──────────────┘
          ▼                                                         ▼
   solve_welfare (centralized)                              build_dso_opt / AgrOpt (ADMM)
    ├─ assert_solved!                                        ├─ reactive_consensus default
    ├─ assert_socp_exact!  ◄── re-measured high-PV           │    = _default_reactive_consensus
    │     (refusal = recorded outcome)                       │    (trait refactor a; LIVE for
    ├─ assert_battery_complementarity!  ── trait-routed:     │    HP/SIPV populations, OFF for EV-only)
    │     battery / 4Q / EV certificates mutually exclusive  ├─ LIVE: μq dual ascent on qag_dso
    └─ dual(:balance_p) → DADP prices                        └─ extract_reactive_dlmp (certified μ)
          │                                                         │
          └────────────► per-device test gates: solve_welfare vs solve_admm ◄────┘
                         (test_{electricvehicle,heatpump,smartinverterpv}.jl;
                          tolerances MEASURED then pinned — gate-then-golden)
```

Primary use case trace: researcher flips a `build_population` opt-in → houses get seeded EV/HP/
SIPV devices → aggregator rolls them up (no aggregator changes) → centralized and ADMM engines
both see identical injections → the per-device gate test proves welfare/price agreement → only
then ADMM use.

### Recommended Project Structure
```
src/devices/
├── AbstractDevice.jl        # + new traits (refactor, lands FIRST)
├── ElectricVehicle.jl       # NEW — storage template clone + sessions
├── HeatPump.jl              # NEW — thermal template clone, 2R2C
├── SmartInverterPV.jl       # NEW — 4Q cone + curtailable PV
├── PVBattery.jl             # UNTOUCHED (golden)
├── Thermostatic.jl          # UNTOUCHED (golden)
├── FourQuadBESS.jl          # UNTOUCHED (golden)
└── Aggregator.jl            # UNTOUCHED (stash already generic)
src/models/
└── (EV certificate file — peer of complementarity_4q.jl; placement per convention)
test/
├── test_electricvehicle.jl  # NEW
├── test_heatpump.jl         # NEW
├── test_smartinverterpv.jl  # NEW
└── (trait-equivalence item — location at planner's discretion; test_admm_reactive.jl is the
     reactive-classification precedent)
src/TSODSO.jl                # includes after FixedCapacitor (line 126), before Aggregator (129)
```

### Pattern 1: The aggregatable-device contract (what every new device must satisfy)
**What:** `contribute!(dev, ctx; T)` builds ONLY its vars/constraints on `ctx.model`, writes
NOTHING to `ctx.residuals`/`ctx.objective`, RETURNS `(; vars, p_inject, [q_inject], utility)`.
**When to use:** all three new devices.
**Example (PVBattery.jl:353-360 — the exact return shape):**
```julia
p_inject = [pv_used[t] - p_ch[t] + p_dch[t] for t in 1:T]
return (; vars = (; p_ch, p_dch, soc, pv_used, soc0, Ppv_param), p_inject, utility)
# FourQuadBESS adds:  q_inject = q  (FourQuadBESS.jl:406)
```

### Pattern 2: Windows as hard bounds (zero upper bounds — no big-M)
**Source:** `Deferrable.jl:223-228` — the EV window idiom verbatim:
```julia
p = @variable(
    m,
    [t = 1:T],
    lower_bound = 0.0,
    upper_bound = (d.t_start <= t <= d.t_end ? d.Pmax : 0.0),
)
```
EV applies the same to `p_ch` (and V2G `p_dch`) over `[t_arr, t_dep]`, with the
`d.t_end > T` temporal guard (`Deferrable.jl:212-219`) adapted to `t_dep ≤ T`.

### Pattern 3: Anonymous JuMP objects (multi-instance composition)
**Source:** `FourQuadBESS.jl:377-385`, `PVBattery.jl:294-315`, `Aggregator.jl:178-189`. Any named
container/cone/Parameter claims an object-dictionary symbol and collides the moment a SECOND
instance contributes to the same model. All three devices must use:
```julia
@constraint(m, [t = 1:T], [d.S_inv, pv_used[t], q[t]] in SecondOrderCone())   # anonymous cone
soc0 = @variable(m, set = Parameter(d.soc0))                                   # anonymous Parameter
```

### Pattern 4: Soft departure target as convex epigraph (EV)
```julia
# s ≥ shortfall, penalty −(κ/2)·s²  (concave contribution to welfare; model stays QP)
s = @variable(m, lower_bound = 0.0)
@constraint(m, s >= d.E_target - soc[d.t_dep + 1])
utility = ... - (d.κ / 2) * s^2        # QuadExpr; always feasible (s unbounded above)
```

### Pattern 5: Post-solve complementarity certificate (own measured tolerance)
**Source:** `welfare_solve.jl:352-388` (scale-free `τ·Pmax²`, `on_violation = :error/:warn`,
`CertificateError(; kind = :battery)`) and `complementarity_4q.jl` (selection by distinguishing
key, `atol + rtol·scale²` combined tolerance, `report = true` neutralizer, `maxratio` return,
MEASURED tolerance provenance). The EV certificate is a new peer — never reuse the battery `τ`
(certificate-laundering doctrine, `complementarity_4q.jl` header).

### Anti-Patterns to Avoid
- **big-M availability masks:** a disguised binary; banned by the project rule and degrades QP
  conditioning. Windows are bounds (Pattern 2).
- **Named JuMP containers/cones/Parameters:** collides on the second instance in one shared
  model (the recurring multi-aggregator crash class).
- **Recursion over `t = 1:(T-1)` with a `1:T` state:** the "free hour-T energy" bug
  (`PVBattery.jl:317-325` history). Both EV (`soc`) and HeatPump (`Tin`,`Tem`) use `1:(T+1)`
  states with recursion `t = 1:T`.
- **`@assert` in constructors:** elides under `-O`; project convention is `throw(ArgumentError)`.
- **Copying a peer certificate's tolerance:** every new mathematical regime earns its OWN
  measured tolerance (v3.0 standing bar).
- **Bypassing the reactive-consensus path** for SmartInverterPV's Q (e.g. writing `:Rq`
  directly): A3 is lifted ONLY by routing through `qag_dso` pin/LIVE ascent.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Co-charge detection | New ad-hoc product check per call site | Certificate peer machinery (`welfare_solve.jl` / `complementarity_4q.jl` shape): scale-free relative test, `on_violation`, stash iteration | Proven error/warn semantics, bus/t diagnostics, mutual-exclusion discipline |
| Windowing logic | Availability-mask variables or re-solve tricks | `Deferrable.jl:223-228` zero-upper-bound idiom | Zero-cost bounds, no conditioning damage, already golden-proven |
| Per-house seeding | `seed + bus` arithmetic | `sub_seed`/`_case_a_house_seed` hash idiom (`materialize.jl:24,403-404`) | Per-house independence is hash-based and test-enforced (784-distinct-seed test) |
| SOCP exactness verdict | Hand-computed cone residuals | `assert_socp_exact!` (returns `maxgap`; stash in `ctx.meta[:socp_maxgap]`) | Scale-free combined tolerance with measured-history provenance |
| Post-hoc voltage/physics comparator | Custom sweep of AC equations | `ACPowerFlow(; limits = false)` idiom (`src/settlement/feasibility.jl:326`, `src/planning/ac_recheck.jl`) | Physics-only re-check precedent already validated |
| Results CSV append | Ad-hoc CSV writes | `upsert_sweep_rows` keyed upsert, `cols = :union` (`scripts/benchmark_ieee8500.jl:808-810`) | Schema evolution + idempotent re-runs |
| Reactive-mode plumbing | New consensus machinery per device | Existing `ReactiveMode` OFF/CERTIFIED/LIVE + `qag_dso` pin/ascent | SmartInverterPV/HeatPump ride the existing path unchanged |

**Key insight:** the device templates in this repo already encode every hard-won lesson (free
hour-T energy, object-dictionary collisions, App. C strict ordering, certificate
mutual-exclusion). Phase 43 is disciplined cloning plus two small traits — new math appears only
in the 2R2C recursion, the epigraph target, and the degradation cost.

## Existing Device-Model Anatomy (plug-in points, verified this session)

### Struct + constructor conventions (all three devices clone this)
- `struct X{T<:Real} <: AbstractDevice` with a throw-guarded inner constructor
  (`PVBattery.jl:105-161`: strict `λ_min < λ_med < λ_max` guard is the load-bearing App. C
  invariant, `Pmax > 0`, `η ∈ (0,1]`, `Emin ≤ soc0 ≤ Emax`) and a promotion outer constructor
  (`PVBattery.jl:175-213` via `promote_type` over all scalars + `eltype` of profile vectors).
- `Thermostatic.jl` additionally shows the `φ::Union{Nothing,T}` per-device power-factor
  override field with its own `(0,1]` guard (`Thermostatic.jl:152-159`) — REQUIRED on `HeatPump`
  because the Aggregator's flexible-load branch reads `hasproperty(d, :φ) && d.φ !== nothing`
  (`Aggregator.jl:216`).

### contribute! variable construction precedents
| Device | Vars | Recursion coverage | Terminal rule | Parameters |
|--------|------|--------------------|---------------|------------|
| `PVBattery.jl:253-360` | `p_ch, p_dch ≤ Pmax`; `soc` 1:(T+1) banded; `pv_used` | `t = 1:T` (whole horizon, 321-325) | `soc_terminal::Union{Nothing,Real,Symbol}` kwarg; `:cyclic` ⇒ `soc[T+1] ≥ soc0` vs the SAME Parameter (326-330) | `soc0` (315), `Ppv_param` (306) — anonymous |
| `FourQuadBESS.jl:319-407` | `p_ch ≤ Pch_max`, `p_dch ≤ Pdch_max`; `soc` 1:(T+1); `q` free sign-free (343) | `t = 1:T` (362-366) | same kwarg shape | `soc0` (355) |
| `Thermostatic.jl:256-313` | `p ∈ [Pmin,Pmax]`; `Tin` 1:T banded (comfort band) | `t = 1:(T-1)` (293-302) — NOTE: Thermostatic does NOT close the whole horizon | none | `Tin0` (291), `Tout_param` over 1:(T-1) (294) |
| `Deferrable.jl:210-255` | `p` with window zero-bounds | — (budget band `Σ p` over window) | — | none |

Key nuance for `HeatPump`: the locked decision imposes PVBattery's closure discipline (both
states `1:(T+1)`, recursion `t = 1:T`, band at `T+1`) — a deliberate DEVIATION from
`Thermostatic`'s `1:(T-1)` recursion, following the newer whole-horizon rule. `Tout` is then
read at `t = 1:T` (not `1:(T-1)`), so the COP/Tout length guards are `length ≥ T`.

### Certificates and the stash
- `Aggregator.contribute!` stashes per-device vars: `append!(get!(ctx.agg_device_vars, agg.bus,
  Vector{Any}()), device_vars)` (`Aggregator.jl:240`). The stash is `Dict{Int,Vector{Any}}`
  (`ModelContext.jl:53,73`) holding the device's returned `vars` NamedTuples — **not device
  objects**.
- `assert_battery_complementarity!` (`welfare_solve.jl:352-388`): mandatory in `solve_welfare`
  (step 9, after `assert_solved!` and the exactness gate); scale-free
  `value(p_ch[t])·value(p_dch[t]) < τ·Pmax²` with `Pmax` recovered from the variable's upper
  bound (`welfare_solve.jl:369-370`); `on_violation = :error/:warn`; class-aware `τ`
  (`1e-6` QP path / `1e-3` SOCP path, `welfare_solve.jl:114`).
- **Predicate (the refactor seam b):** `haskey(v, :p_ch) && haskey(v, :p_dch) &&
  !haskey(v, :q)` (`welfare_solve.jl:366`) — battery; `... && haskey(v, :q)` — 4Q
  (`admm_state.jl:439`, `complementarity_4q.jl`). An EV's vars match the battery predicate
  today.
- `assert_4q_complementarity!` (`complementarity_4q.jl:115-156`): the richer peer —
  `atol + rtol·scale²` combined tolerance, `report = true` diagnostic mode returning `maxratio`,
  re-measured noise floors documented in-file (2026-08-08, three device scales). This is the
  template for the EV certificate's tolerance-provenance section.
- The App. C η<1 co-charge finding is IN-REPO: `welfare_solve.jl:309-321` documents that for
  `DLMP < λ_med`, an SOC-neutral round trip earns `(λ_med−DLMP)(1−η²) > 0` — the exact mechanism
  the EV negative-price fixture exercises, and the reason the AC path already uses
  `on_violation = :warn` there.
- AgrOpt battery-check kwargs (`AgrOpt.jl:199,234-243,325-326`): `check_battery = false`
  mid-loop / `true` on the final solve; `check_4q` likewise gated — the EV certificate needs the
  same mid-loop/final split consideration if it hooks `solve_admm`'s certify path.

### Other stash consumers the new devices must not silently break (grep-verified)
- `stochastic_welfare.jl:576,670-675`: battery-like sniff `haskey(v, :soc0)` ⇒ per-step PIN
  `Parameter`s under MPC/stochastic seams.
- `mpc_window.jl:209-230`: `ic_handles` walk — `haskey(v, :soc0)` ⇒ `:soc`-kind IC re-target,
  `haskey(v, :Tin0)` ⇒ `:Tin`-kind (terminal_param always `nothing` for `:Tin`).
- `mpc_loop.jl:1214-1232`: `_mpc_device_hour_utility` has per-concrete-device methods
  (`PVBattery`/`FourQuadBESS`/`Thermostatic`) — a new device type in an MPC population would
  `MethodError` there; MPC is out of scope but the walk behavior must be documented/tested for
  the new vars shapes.
- `pricing/welfare.jl:92`, `settlement/price_taker.jl:123-128`, `experiments/run_stochastic.jl:243`,
  `experiments/mpc_loop.jl:363,445,517,739`: iterate the stash generically (safe for any vars
  NamedTuple) or sniff `:soc`/`:soc0`/`:q` keys.
- Design implication for the storage trait: because the stash holds NamedTuples, trait-driven
  classification needs device-type information alongside vars (e.g. `Aggregator` — which has `d`
  in hand — stashing a parallel per-bus device-type list, or the trait exposed as a function
  over the device while the stash gains a companion). This is the one genuinely new plumbing
  piece; planner designs the exact mechanism (discretion), but the equivalence test must prove
  existing fixtures classify identically.

## Reactive-Consensus Path (SmartInverterPV Q routing + trait seams)

Exact sites to refactor (all verified this session):

| Site | File:Line | Current code | Role |
|------|-----------|--------------|------|
| 1 | `src/admm/DsoOpt.jl:172-176` | `_any_flexible_reactive`: `any(dv -> dv isa FourQuadBESS \|\| is_flexible_load(dv), agg.devices)` | shared probe for BOTH smart defaults |
| 2 | `src/admm/DsoOpt.jl` (signature ~line 237, `reactive_consensus = _any_flexible_reactive(...) ? LIVE : OFF`) | context-sensitive kwarg default | DSO-OPT smart default |
| 3 | `src/admm/DsoOpt.jl:326-330` | same probe inside the `mode != LIVE` fail-loud guard (compares the NORMALIZED mode value, never the raw kwarg spelling) | guard against silently dropping device reactive terms under OFF/CERTIFIED |
| 4 | `src/admm/admm_state.jl:409-410` | `_default_reactive_consensus(aggregators) = _any_flexible_reactive(aggregators) ? ReactiveMode.LIVE : ReactiveMode.OFF` | `solve_admm` smart default |
| 5 | `src/admm/admm_state.jl:429-445` | `_react_outputs` sniffs `haskey(v,:p_ch) && haskey(v,:p_dch) && haskey(v,:q)` to publish `q_devices` | var-shape sniffing (secondary; may stay shape-based or go trait-driven with refactor b) |

Mode machinery: `ReactiveMode.T ∈ {OFF, CERTIFIED, LIVE}` (`ReactiveMode.jl:23-25`);
`normalize_reactive_mode` throws on `Bool`/`Symbol`. CERTIFIED pins `qag_dso[j,t]` via registered
`:qag_pin` equality (one-shot certified dual); LIVE runs genuine μq dual ascent per iteration
(`admm_state.jl:416-423` no-slack certificate; `:balance_q` registered for duals).

Classification semantics the refactor must preserve (today → trait):
- `FourQuadBESS` ⇒ reactive-decision device (genuine `q_inject`) ⇒ `has_reactive_decision = true`
- `Thermostatic`/`Deferrable`/`Interruptible` ⇒ `is_flexible_load = true` ⇒ today probe-true
- `PVBattery`, `FixedCapacitor` ⇒ probe-false today (FixedCapacitor carries `q_inject` but the
  probe at sites 1/3/4 does NOT match it — **verify**: `FixedCapacitor` is included after
  `FourQuadBESS` and is "second q_inject consumer" (`TSODSO.jl:126`); the trait must reproduce
  today's resolution INCLUDING this asymmetry, i.e. the trait is about the *probe's* meaning
  ("reactive decision NOT the constant `-Pdc·tanφ` draw alone"), and FixedCapacitor's fixed
  reactive is part of that constant draw — trait must stay `false` for it unless measurement
  says otherwise. This is exactly why the equivalence test is gate-first.)
- New: `SmartInverterPV` ⇒ `true` (genuine `q`); `HeatPump` ⇒ `true` (via `is_flexible_load =
  true`); `ElectricVehicle` ⇒ `false` (active-only; see Assumptions A1).

Equivalence-test design: for each existing fixture population (two-bus, IEEE-13 default,
4Q fixture, `:case_a_784` proxy scale), assert `_default_reactive_consensus(aggs)` (and the
`build_dso_opt` guard outcome) is unchanged pre/post refactor, plus a per-device truth table
`has_reactive_decision(d) == (d isa FourQuadBESS || is_flexible_load(d))` over every existing
device type.

## 2R2C Heat-Pump Thermal Dynamics (literature-standard, convex)

Verified against the building grey-box literature this session:
[CITED: Kircher, "Thermal modeling of buildings" (Purdue ME 597 DER course notes),
kevinjkircher.com/der-buildings-2.pdf — gives the canonical 2R2C circuit, ODEs, and exact ZOH
discretization]; [CITED: FEATURES.md row 68 — Bacher & Madsen 2011; Reynders et al. 2014
(2nd-4th-order RC adequate, ≥2nd order expected by reviewers); ISO 13790 5R1C as reference];
[CITED: IBPSA/CTSM-R grey-box literature — 2R2C = indoor-air node + envelope-mass node is the
standard "TiTe" structure]. Bibliographic precision for the thesis itself is MEDIUM confidence
(per FEATURES.md's own caveat — re-verify exact citations at writeup time).

Canonical continuous-time form (Kircher topology: ambient—Rout—Tin—Rm—Tem, heat input at Tin):
```
C_in  · dTin/dt = (Tem − Tin)/Rm + (Tout − Tin)/Rout + Q_hp
C_env · dTem/dt = (Tin − Tem)/Rm
```
with `Q_hp[t] = COP[t]·p[t]` (exogenous `COP[t] > 0` keeps the map from `p` to heat LINEAR —
the locked decision).

**Discretization at the project's T=24, Δt = 1 h resolution — two defensible forms:**

(a) *Exact ZOH* (literature-canonical, unconditionally stable):
`x[t+1] = A·x[t] + B·u[t] + E·Tout[t]` with `A = exp(Ã·Δt)`, `B = (A − I)·Ã⁻¹·B̃` — constant
2×2 matrices computed once in `contribute!` (no JuMP objects; `LinearAlgebra.exp` or the closed
form for 2×2). Coefficients stay constant ⇒ every constraint stays affine ⇒ hard bands convex.

(b) *Forward-Euler in the `Thermostatic` idiom* (maximal template consistency):
```
Tin[t+1] = Tin[t] + α_ie·(Tem[t] − Tin[t]) + α_ia·(Tout[t] − Tin[t]) + β·COP[t]·p[t]
Tem[t+1] = Tem[t] + α_me·(Tin[t] − Tem[t]) + α_ma·(Tout[t] − Tem[t])
```
with all `α ≥ 0`, `β > 0` (heating: power RAISES `Tin` — constructor-guarded signs, the
`Thermostatic.jl:115-137` sign-guard pattern adapted: negative `α` reverses heat flow;
`β ≤ 0` silently flips heating/cooling). Forward Euler is stable iff the eigenvalues of
`I + Δt·Ã` lie in the unit disc — with hourly Δt and residential R/C values this holds for
sane parameters, but the constructor should guard or document it (Pitfall 12).

Both keep the welfare a convex QP. Form (b) maximizes traceability to `Thermostatic` (thesis
eq. 3.2 extension, "two coupled states" per the research line); form (a) is the physics-exact
option. Planner picks; either satisfies the locked decisions.

**Model assembly (locked):** both states `1:(T+1)`; recursion `t = 1:T` unconditionally;
hard band `Tmin ≤ Tin[t] ≤ Tmax` including `t = T+1`; `Tem` bounded by a physical envelope range
(or free — discretion, flagged OQ3); IC `Tin[1] == Tin0`, `Tem[1] == Tem0` as anonymous
Parameters (mirrors `Tin0`); `terminal` kwarg mirroring `soc_terminal` (`nothing`/`Real`/`:cyclic`
against the IC Parameter); comfort utility `−(b/2)·Σ_t (Tin[t] − Tmin)²`, `b > 0` constructor
guard (3.11/3.13-3.14 pattern); `COP::Vector{T}` validated `length ≥ T` at `contribute!` time
(`Thermostatic.jl:259-266` guard idiom); NO JuMP Parameter seam for COP this phase (plain
constraint coefficients, mirror `Tout`); `is_flexible_load(::HeatPump) = true`; `p_inject =
−p` (heating load, negative-injection convention); `p ∈ [0, Pmax]` (heating convention,
`Pmin = 0`-style single-sided bounds); `φ::Union{Nothing,T}` override field so the Aggregator's
per-device override branch works.

## EV Convex Formulation

**Energy dynamics + band (PVBattery clone):**
```
soc[t+1] = soc[t] + (η·p_ch[t] − p_dch[t]/η)·Δt        t = 1:T   (whole-horizon closure)
Emin ≤ soc[t] ≤ Emax                                     t = 1:(T+1)
soc[1] == soc0                                           (arrival SOC; anonymous Parameter)
```

**Windows as hard bounds (binary-free):** `p_ch[t]` (and V2G `p_dch[t]`) `upper_bound =
(t_arr ≤ t ≤ t_dep ? Pmax : 0.0)`; guard `1 ≤ t_arr ≤ t_dep ≤ T` at `contribute!` (the
`Deferrable.jl:212-219` temporal guard adapted). No big-M, no mask variables.

**Soft departure target (V1G):** auxiliary `s ≥ 0`, `s ≥ E_target − soc[t_dep+1]`, welfare
penalty `−(κ/2)·s²` (quadratic preferred; affine `−κ·s` exact alternative — plan's choice).
Always feasible; concave-from-the-welfare-side; keeps QP. Note the target uses the SOC *state*
(energy in the band convention) at `t_dep + 1` — the same `T+1` index the closure rule guarantees
exists.

**V2G (opt-in constructor field/kwarg):** `p_dch` enters with utility term `−c_deg·p_dch[t]`,
`c_deg > 0` STRICTLY enforced at construction (the constructor guard is the no-binary
justification's first half). The App. C dominance argument EXTENDS: for fixed external price
λ, discharging only pays when λ > marginal cost; with `c_deg > 0` and `η² < 1`, internal
round-trips remain strictly dominated at non-negative prices — but at NEGATIVE effective prices
co-charge is KKT-optimal (the in-repo App. C η<1 finding, `welfare_solve.jl:309-321`, and the
FourQuadBESS grid-charging derivation, `FourQuadBESS.jl:48-90`). Hence the certificate is
mandatory, not decorative.

**EV certificate (`assert_ev_complementarity!`-style, new peer):**
- Test: `value(p_ch[t])·value(p_dch[t]) < τ_ev·Pmax²` (scale-free — base-invariant by the
  same argument as `welfare_solve.jl:324-336`).
- `on_violation = :error/:warn` convention; `CertificateError` with its own `kind`.
- `τ_ev` (or `atol + rtol·scale²` in the 4Q style) MEASURED on the EV fixtures' per-unit scales
  and documented in-file (tolerance-provenance doctrine).
- Selection: trait-driven (refactor b) so the battery certificate skips EV vars and the 4Q
  certificate never matches (EV has no `:q`).
- Exercised on the negative-price fixture: co-charge reported there is the certificate working
  (honesty policy) — the test asserts the REPORT fires, not that it never does.
- AgrOpt/solve_admm hook: mirror the `check_battery` mid-loop/final split pattern
  (`AgrOpt.jl:234-243,325-326`) so off-consensus iterates don't false-positive.

**Signature/injection:** `p_inject = p_dch − p_ch` (V1G: `−p_ch` with `p_dch` absent or
zero-bounded). Active-only (`p_inject` returned; no `q_inject`; `is_flexible_load` stays
default `false` — Assumption A1). Vars: mirror PVBattery (`p_ch, p_dch?, soc, soc0`) so the
`:soc0` MPC/stochastic walks keep working; whether V1G omits `p_dch` from `vars` entirely or
zero-bounds it is a planner choice with a classification consequence (trait must handle both —
Assumption A2).

## Centralized-vs-ADMM Validation Harness Pattern (gate-then-golden)

**The precedent table** (`test/fixtures_four_quad_bess.jl:40-49`, verified verbatim): 5 seeds
(`SEED_2BUS`..`+4`), `centralized_welfare_4q` (a `solve_welfare` replica over public seams,
kept for measurement provenance) vs `solve_admm(; reactive_consensus = LIVE)`:

| seed | \|Δwelfare\| | \|Δλ\|₂ (T=24) | \|Δμ\|₂ (T=24) |
|------|--------------|----------------|----------------|
| max over 5 seeds | 2.368e-5 | 1.519e-5 | 1.610e-8 |

These were MEASURED then PINNED — that two-step is the gate-then-golden discipline the three
new device files must repeat: (1) solve both engines on the device's small fixture across ≥5
seeds; (2) record the observed max deltas; (3) pin those numbers as the test's bands (never
invented constants, never "0.01 to be safe").

**What "validated against centralized before ADMM use" means operationally:** the per-device
test file's cross-validation item (fast set, two-bus/IEEE-13 scale, `T = 24`) is the gate. It
must be green — for every device class — in the same commit that introduces ADMM-scenario use
of that device. There is no runtime lock; the gate is the test suite itself plus the plan's
task ordering (device test before any ADMM-population use).

**Per-device gate shape:**
- `test_electricvehicle.jl`: V1G 2-bus fixture (windows spanning arrival→departure, soft
  target active) — constructor guards; standalone QP solve reaches target when cheap / backs off
  when dear (Deferrable-style live-target assertion); certificate fires on the negative-price
  V2G fixture (assert the report); V1G-vs-centralized and V2G-vs-centralized crossval items.
- `test_heatpump.jl`: 2R2C recursion sanity (closed-form one-step check), comfort band holds,
  terminal kwarg variants, `is_flexible_load` roll-up (q draw appears in `:Rq`), crossval item
  (LIVE reactive mode — flexible-load member ⇒ LIVE default).
- `test_smartinverterpv.jl`: cone binding behavior (q ≠ 0 when voltages need support),
  zero-utility-on-q invariant, `q_inject` routed through `:qag_pin`/LIVE, crossval with μ
  agreement (the `test_admm_reactive.jl:240` item is the template), SOCP exactness
  re-measurement in the high-PV regime (below).
- Reactive-mode expectations per device in ADMM: EV-only population ⇒ default OFF (unchanged
  from a no-reactive population); HeatPump or SmartInverterPV present ⇒ default LIVE (probe
  true). The trait equivalence test pins these resolutions for existing fixtures first.

**`:slow` policy (measured budgets):** `TSODSO_TEST_SET` = fast|slow|all, unset = all;
`(set == "slow") == (:slow in ti.tags)` selects (`runner_support.jl:56`). Small-fixture
crossvals are fast-set items (4Q precedent converges in `iters = 2` on the deliberately
interior two-bus fixture). Population-scale (`:case_a_784`) runs are NOT suite tests — they are
script artifacts (results/ CSV + literate; 41-RESEARCH A5: 784-house ADMM ≈ 10 min serial).
Any suite item that solves a full population gets `tags = [:slow]` (42-RESEARCH). The
`expected_broken.txt` guard fails the run on any new unlisted broken/skip record — same-commit
registration if a conditional-broken site appears.

**SOCP exactness re-measurement (DEV-09):** fixture at high `pv_scale` (the EXACT-04/pv-boom
regime; `scripts/pv_boom_case_study.jl` and `test/fixtures_ieee13.jl`'s certified high-PV
stress substrate are the precedents — the script itself documents "fixture copied verbatim,
never re-tuned"), solved with and without optimal Q, verdicts read through the standard gates
(`assert_socp_exact!` `maxgap`/ratios, hybrid AC ratios). "Refused with certificate" is a valid
measured outcome and must land as a recorded row, not a test failure. Rows land in `results/`
CSVs via the keyed upsert idiom; test vs literate artifact is the planner's discretion.

## build_population Opt-In (Scenario schema untouched)

- `_case_a_house` (`materialize.jl:444-489`) builds the FIXED 3-device set
  (`Thermostatic`+`Deferrable`+`PVBattery`, `_DEFAULT_BATT_λ_*`, φ = 0.90) — new devices do NOT
  enter here by default (byte-identical `:case_a_784`).
- The opt-in point is `build_population` (`materialize.jl:546+`): a new kwarg with a
  no-op default (e.g. `flex_devices = nothing`-shaped selector) or an additive selector branch,
  following the `:case_a_784` additive-branch pattern. Call sites: `run.jl:65` (`_materialize`)
  passes positional args only — so the default kwarg keeps every Scenario-based run
  byte-identical; scripts/tests opt in by calling `build_population` directly. NOTE:
  `SCENARIO_VALID_POPULATIONS = (:default, :case_a_784)` (`Scenario.jl:48`) stays untouched —
  a new Scenario *selector symbol* would be a schema change; a kwarg/branch is not.
- EV session seeding: extend the hash idiom — `Int(hash((s_pop, :ev, bus, house_index)) %
  typemax(UInt32))` (`_case_a_house_seed` shape, `materialize.jl:403-404`; `sub_seed` at
  `materialize.jl:24`). Per-house, never per-bus (the 784-collision lesson,
  `materialize.jl:397-401`). Truncated-normal arrival (~evening)/departure (~morning) +
  lognormal energy draws; parameters DOCUMENTED as low-confidence calibration (FEATURES row 66;
  ACN-Data (Lee, Li, Low 2019)/NHTS are the check-later sources).
- Canary invariants: `:default` population, `:case_a_784`, canary `iters = 56`,
  `welfare = -4823.66604824162` — never re-pinned, never behaviourally touched.

## Runtime State Inventory

Omitted — not a rename/refactor/migration phase (greenfield device addition on existing
infrastructure; no stored-string rename, no live-service config, no OS-registered state).

## Common Pitfalls

### Pitfall 1: EV vars match the battery-certificate predicate — trait refactor is a hard ordering
**What goes wrong:** land `ElectricVehicle` before refactor (b) and
`assert_battery_complementarity!` runs on EV vars (`haskey :p_ch && :p_dch && !:q` matches),
throwing `:error` on the legitimate V2G negative-price optimum inside `solve_welfare` before
the EV certificate can report it.
**Why it happens:** the stash holds NamedTuples; classification is shape-based.
**How to avoid:** success criterion 1 ordering is binding — trait refactor + equivalence test
green FIRST, in its own plan, before any device file.
**Warning signs:** a plan whose first task creates a device file.

### Pitfall 2: Symbol-subtraction trap in names
**What goes wrong:** `:gap_1e-10` parses as `:gap_1e - 10`; same for tolerance/rung names in
measurement CSVs and Dict keys (`42-RESEARCH.md` Pitfall 6, `case_a_agreement.jl:88-90`).
**How to avoid:** plain `String` keys for rungs/ratios; explicit `Symbol("tol_1e-10")` where a
Symbol tag is unavoidable. EV `τ_ev`, SOCP-exactness rows and window labels frequently want
exponent names.
**Warning signs:** a `Symbol` literal containing `e-`.

### Pitfall 3: Object-dictionary collisions on the second instance
**What goes wrong:** a named cone/Parameter/container (`cone`, `soc0`, `pv_used`...) works in a
one-device test and crashes (`"An object of name X is already attached to this model"`) the
moment two of the new devices share one model — i.e. any population.
**How to avoid:** ANONYMOUS everything in `contribute!` (`FourQuadBESS.jl:385`,
`PVBattery.jl:306,315`); never `register_constraint!` device-level cones.
**Warning signs:** any named `@variable(m, name[...])` in new device code.

### Pitfall 4: Free hour-T energy (recursion coverage)
**What goes wrong:** state `1:T` with recursion `1:(T-1)` leaves the last interval's power free.
**How to avoid:** states `1:(T+1)`, recursion `t = 1:T` (PVBattery/4Q rule; LOCKED for both EV
and HeatPump states); HeatPump reads `Tout`/`COP` at `t = 1:T` so length guards are `≥ T`.
**Warning signs:** `1:(T-1)` loops in new device code.

### Pitfall 5: `:slow` budget erosion and unregistered artifacts
**What goes wrong:** (a) heavy crossvals left untagged slow every full-suite run (default set is
"all"); (b) new measurement scripts missing from `scripts/README.md` fail CI
(`check_scripts_index.py`); (c) new `@test_broken`/`@test_skip` records fail the whole suite
unless listed in `test/expected_broken.txt` same-commit.
**How to avoid:** two-bus crossvals stay fast; anything population-scale `:slow`-tagged or made
a script artifact; register scripts/pages at BOTH literate registration sites in `docs/make.jl`.
**Warning signs:** minutes-long items in the fast set.

### Pitfall 6: Golden policy violations
**What goes wrong:** "improving" `Thermostatic` into the HeatPump (it is a NEW file —
`Thermostatic` is byte-identical golden), widening `PVBattery` with a Q kwarg, or re-pinning
the canary (`iters = 56`, `welfare = -4823.66604824162`).
**How to avoid:** one struct per device; existing device files and fixtures untouched
behaviourally; `:default`/`:case_a_784` byte-identical; trait defaults resolve existing devices
exactly as today (proven by test).
**Warning signs:** diffs touching `Thermostatic.jl`/`PVBattery.jl`/`Scenario.jl` in this phase.

### Pitfall 7: Certificate tolerance laundering
**What goes wrong:** EV certificate defaults copied from the battery `τ` (1e-6/1e-3) or the 4Q
`rtol`/`atol` — constants calibrated against a DIFFERENT device's numerics at DIFFERENT per-unit
scales (the 4Q file documents a real re-measurement where the original defaults were masked by
~5 orders of magnitude).
**How to avoid:** measure the EV noise floor on the committed EV fixtures; document provenance
in-file (`complementarity_4q.jl` header is the template).
**Warning signs:** a certificate default with no measurement table/comment.

### Pitfall 8: Reactive-mode guard vs raw kwarg spelling
**What goes wrong:** "simplifying" the `build_dso_opt` guard to `reactive_consensus !=
ReactiveMode.LIVE` breaks when callers pass non-normalized values — the guard must compare the
NORMALIZED mode (`DsoOpt.jl:326-330` note).
**How to avoid:** keep `normalize_reactive_mode` in the guard path during the trait refactor;
the trait changes WHO matches, not HOW the mode is validated.
**Warning signs:** trait refactor PR touching the normalize call.

### Pitfall 9: Equality assertions on solver floats across seeds
**What goes wrong:** `==` across independently solved legs/seed variants flakes on knife-edge
degeneracies.
**How to avoid:** assert structural identities exactly; numeric agreement via measured bands
(42-RESEARCH Pitfall 8); record honest refusal rows instead of `@test_broken` where a leg
genuinely refuses.
**Warning signs:** `@test obj_c == res.welfare`.

### Pitfall 10: Soft-scope accumulators in `@testitem` bodies
**What goes wrong:** bare reassignment inside nested `for`/`try` creates a throwaway local —
tests go permanently VACUOUS (hit twice historically; `runtests.jl` header).
**How to avoid:** `let`-wrap mutable scan state; grep full-suite logs for
`soft scope is ambiguous` (must be 0).
**Warning signs:** an `@test` that passes after the loop it depends on did nothing.

### Pitfall 11: Upsert/CSV measurement idioms
**What goes wrong:** appending rows with silently diverging schemas; duplicate rows on re-run.
**How to avoid:** `upsert_sweep_rows` keyed upsert with `cols = :union`
(`scripts/benchmark_ieee8500.jl:808-810`); `started`-row-then-replace for long solves; NaN
normalization discipline for rows written pre-completion.
**Warning signs:** raw `CSV.write(..., append = true)` in new measurement code.

### Pitfall 12: Forward-Euler stability of the 2R2C recursion at Δt = 1 h
**What goes wrong:** with stiff coupling (small R·C), explicit Euler diverges — temperatures
blow up, band constraints force infeasibility with no obvious cause.
**How to avoid:** constructor-guard the coefficient regime (diagonal dominance of the discrete
update), or use the exact ZOH discretization (`A = exp(ÃΔt)` — unconditionally stable); either
way document the choice in the struct docstring.
**Warning signs:** comfort-band infeasibility with sane demand and a stiff envelope.

### Pitfall 13: Docstring formatting / formatter traps
**What goes wrong:** `|`-leading wrapped docstring lines lost by a JuliaFormatter
continuation bug; 92-col violations.
**How to avoid:** avoid `|`-leading wraps; run pinned JuliaFormatter (2.10.2) before commit
(42-RESEARCH Pitfall 7c/d).

## Code Examples

### EV `contribute!` skeleton (assembly of verified idioms)
```julia
# Windows as bounds (Deferrable.jl:223-228 idiom) + PVBattery storage core
p_ch = @variable(m, [t = 1:T],
    lower_bound = 0.0,
    upper_bound = (d.t_arr <= t <= d.t_dep ? d.Pmax : 0.0))
soc = @variable(m, [t = 1:(T+1)], lower_bound = d.Emin, upper_bound = d.Emax)
soc0 = @variable(m, set = Parameter(d.soc0))               # anonymous (PVBattery.jl:315)
@constraint(m, soc[1] == soc0)
@constraint(m, [t = 1:T],
    soc[t+1] == soc[t] + (d.η*p_ch[t] - p_dch[t]/d.η)*d.Δt) # t = 1:T closure
# Soft target epigraph (convex, always feasible)
s = @variable(m, lower_bound = 0.0)
@constraint(m, s >= d.E_target - soc[d.t_dep + 1])
utility = appC_charge_utility(...) - (d.κ/2)*s^2            # QuadExpr, concave sum
```

### HeatPump 2R2C recursion (Euler form; both states T+1, band at T+1)
```julia
length(d.COP) >= T || throw(ArgumentError(...))            # Thermostatic.jl:259 guard idiom
Tin = @variable(m, [t = 1:(T+1)], lower_bound = d.Tmin, upper_bound = d.Tmax)
Tem = @variable(m, [t = 1:(T+1)], lower_bound = d.Tem_min, upper_bound = d.Tem_max)
Tin0 = @variable(m, set = Parameter(d.Tin0)); Tem0 = @variable(m, set = Parameter(d.Tem0))
@constraint(m, Tin[1] == Tin0); @constraint(m, Tem[1] == Tem0)
@constraint(m, [t = 1:T], Tin[t+1] == Tin[t]
    + d.α_ie*(Tem[t] - Tin[t]) + d.α_ia*(Tout[t] - Tin[t]) + d.β*d.COP[t]*p[t])
@constraint(m, [t = 1:T], Tem[t+1] == Tem[t]
    + d.α_me*(Tin[t] - Tem[t]) + d.α_ma*(Tout[t] - Tem[t]))
utility = sum(-(d.b/2)*(Tin[t] - d.Tmin)^2 for t in 1:T)   # eq. 3.11 pattern, b > 0
```

### SmartInverterPV cone (FourQuadBESS.jl:385 idiom verbatim, PV-normalized)
```julia
q = @variable(m, [t = 1:T])                                 # sign-free, NO utility term
@constraint(m, [t = 1:T], [d.S_inv, pv_used[t], q[t]] in SecondOrderCone())  # ANONYMOUS
return (; vars = (; pv_used, q, ...), p_inject, q_inject = q, utility)
```

### Certificate peer shape (4Q template)
```julia
function assert_ev_complementarity!(ctx::ModelContext; τ_ev::Real = MEASURED,
                                    T::Int = _require_T(ctx), on_violation::Symbol = :error)
    # trait-routed selection over ctx.agg_device_vars; scale-free p_ch·p_dch < τ_ev·Pmax²;
    # CertificateError(kind = :ev) / @warn; return a worst-ratio diagnostic (4Q contract)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 1-state (3.2) thermal device only | 2R2C two-state grey-box is the reviewer minimum for "building thermal model" | FEATURES row 68 (Bacher & Madsen 2011 lineage) | HeatPump is a new device, `Thermostatic` untouched |
| EV availability via binary/big-M | Continuous windows as bounds + soft convex target | project rule (REQUIREMENTS Out-of-Scope) | Binary-free QP, duals preserved |
| Droop curve as constraint | Optimal-Q in cone + droop as post-hoc comparator | FEATURES rows 97/112 | Nonconvexity avoided; DEV-F1 defers the loop |
| Battery cert reused for new devices | Per-regime measured certificates, trait-routed | v3.0 standing bar; 4Q re-measurement (2026-08-08) | EV gets its own measured τ_ev |

**Deprecated/outdated:** ECOS/SCS for certification (repo already Clarabel-only for final
numbers); `seed + bus` per-bus seeding (per-house hash idiom since Phase 40).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ElectricVehicle` is active-only (`is_flexible_load` stays `false`, no `q_inject`) — inferred from the PVBattery/A3 precedent; CONTEXT locks only HeatPump's trait | EV Formulation | If EV should draw power-factor reactive, aggregator roll-up expectations and the trait truth table change (small code change, but crossval bands re-measured) |
| A2 | V2G opt-in is a constructor field/kwarg; V1G either omits `p_dch` from vars or zero-bounds it — mechanism is planner discretion | EV Formulation | Var-shape classification and certificate selection must handle whichever shape is chosen; crossval fixture count changes |
| A3 | HeatPump `terminal` kwarg applies to BOTH states jointly (single `Union{Nothing,Real,Symbol}`), `:cyclic` vs each state's IC Parameter | 2R2C section | Per-state terminal control would need a richer kwarg type — pure API-shape risk, no math risk |
| A4 | Storage-classification trait needs device-type info stashed beside vars (stash currently NamedTuple-only); mechanism (parallel stash vs pairs) is planner discretion | Anatomy section | A purely shape-based "trait" would not actually solve the EV misclassification for the certificate path |
| A5 | 2-bus fixtures can host the high-PV exactness re-measurement, or the certified IEEE-13 high-PV stress substrate is copied verbatim instead (pv_boom precedent) | Validation section | Wrong fixture choice → exactness verdicts not comparable to EXACT-04 history; measurement redo cost |
| A6 | EV session distribution parameters (truncated-normal arrival/departure, lognormal energy) are LOW-confidence placeholders by design (locked as documented-low-confidence) | build_population section | None this phase — recalibration is deferred by locked decision |
| A7 | 2R2C bibliographic citations (Bacher & Madsen 2011; Reynders et al. 2014; Kircher notes) are MEDIUM confidence pending thesis-time verification; the ODE/discretization FORM was verified this session via the Kircher notes | 2R2C section | Citation corrections at writeup time only; math unaffected |
| A8 | `FixedCapacitor` must classify `has_reactive_decision = false` (today's probe does not match it despite carrying `q_inject`) — its fixed reactive belongs to the constant draw | Reactive-Consensus section | Getting this backwards flips reactive consensus defaults on `:ieee8500*` populations → the equivalence test catches it (that is its job) |
| A9 | The EV/HeatPump IC Parameters (`soc0`, `Tin0`, `Tem0`) keep the `:soc0`/`:Tin0` stash-key compatibility walks (`mpc_window`, `stochastic_welfare`) working unchanged | Anatomy section | If vars naming diverges, MPC/stochastic seams silently skip IC re-targeting for new devices (out of scope this phase, but a trap for Phase 44+) |

## Open Questions

1. **Does the V1G model include a `p_dch` variable at all?**
   - What we know: V2G is opt-in; "the V1G default path stays the smaller model".
   - What's unclear: omit-vs-zero-bound changes the vars NamedTuple shape the certificates and
     MPC walks see.
   - Recommendation: include `p_dch` only when `v2g = true` (smaller model), and make the
     storage trait/certificate selection robust to its absence; document the shape in the struct
     docstring.
2. **`Tem` terminal handling.**
   - What we know: both states T+1 with band at T+1 is locked for `Tin`; the envelope state's
     terminal constraint is not explicitly locked.
   - Recommendation: `terminal` kwarg pins/cyclicizes BOTH states when supplied (A3); `Tem`
     keeps a wide physical band otherwise.
3. **Exactness re-measurement as test vs literate artifact.**
   - What we know: planner discretion is explicit; rows go to `results/` CSV either way.
   - Recommendation: script + committed CSV + literate page (the 41/42 pattern), with at most a
     `:slow` structural test — keeps the suite fast and the measurement honest.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 [VERIFIED] | — (pinned Manifest) |
| Clarabel (conic/QP solver) | all solves | ✓ | pinned Manifest | — |
| TestItemRunner/TestItems | per-device test files | ✓ | pinned (test/Manifest.toml) | — |
| JuliaFormatter | formatting gate | ✓ | pinned 2.10.2, 92-col | — |
| New external tools | — | n/a | — | none required |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + TestItemRunner.jl (pinned; `@testitem` per device class) |
| Config file | `test/runtests.jl` (TSODSO_TEST_SET fast|slow|all; expected_broken.txt guard) |
| Quick run command | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_electricvehicle.jl,test_heatpump.jl,test_smartinverterpv.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (tests only — project convention) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEV-10a | Trait refactor changes no classification on existing fixtures | unit (fast) | `TSODSO_TEST_SET=fast ... Pkg.test()` (equivalence item) | ❌ Wave 0 |
| DEV-06 | EV V1G window/soft-target/seeded sessions; centralized-vs-ADMM gate | unit + integration crossval (fast) | `... TSODSO_TEST_FILES=test_electricvehicle.jl ...` | ❌ Wave 0 |
| DEV-07 | V2G `c_deg > 0`; certificate reports co-charge on negative-price fixture | unit (fast; certificate report assert) | `... test_electricvehicle.jl ...` | ❌ Wave 0 |
| DEV-08 | 2R2C recursion + band + terminal kwarg; power-factor roll-up; crossval | unit + integration crossval (fast) | `... test_heatpump.jl ...` | ❌ Wave 0 |
| DEV-09 | Cone/Q dispatch; Q through reactive consensus; high-PV exactness re-measured | crossval (fast) + measurement (script/CSV, or `:slow` structural) | `... test_smartinverterpv.jl ...`; script run for CSVs | ❌ Wave 0 |
| DEV-10b | Per-device gate before ADMM use | ordering enforced by plan; gates are the three crossval items | fast suite | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the touched device's fast test file + trait-equivalence item.
- **Per wave merge:** full fast suite.
- **Phase gate:** fast suite green + each device's crossval band green + any `:slow` item the
  planner created green (or its honest refusal row recorded).

### Wave 0 Gaps
- [ ] `test/test_electricvehicle.jl` — covers DEV-06/07 (incl. negative-price certificate item)
- [ ] `test/test_heatpump.jl` — covers DEV-08
- [ ] `test/test_smartinverterpv.jl` — covers DEV-09 (crossval + measurement landing)
- [ ] Trait-equivalence test item — covers DEV-10 (lands in the FIRST plan)
- [ ] Measurement script + `results/` CSV registration (if exactness lands as artifact) +
      `scripts/README.md` entry

## Security Domain

> `security_enforcement` is not disabled in `.planning/config.json` (absent = enabled).
> Applicability is minimal: this is an offline Julia research optimization framework — no
> network listeners, no authentication, no user input beyond fixtures/scripts, no secrets, no
> cryptography. The relevant "input validation" is the project's own fail-loud constructor
> discipline.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a (offline research code) |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes (domain sense) | Throw-guarded inner constructors (`ArgumentError`, never `@assert`) for every physical/consistency invariant — the established project convention all three devices must follow |
| V6 Cryptography | no | n/a |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent model-corruption by degenerate params (e.g. `c_deg = 0` V2G silently re-enabling co-charge economics) | Tampering | Constructor guards + mandatory post-solve certificates that refuse (`:error`) by default |
| Numerical-results laundering (reusing peer tolerances) | Repudiation | Measured-tolerance provenance documented in-file per certificate |
| Supply chain | — | No new packages this phase; Manifest pinned |

## Sources

### Primary (HIGH confidence)
- This repo's source, read this session: `src/devices/{AbstractDevice,PVBattery,Thermostatic,Deferrable,FourQuadBESS,Aggregator}.jl`;
  `src/models/{welfare_solve,complementarity_4q,exactness}.jl`; `src/admm/{DsoOpt,admm_state,ReactiveMode,AgrOpt}.jl`;
  `src/experiments/{materialize,Scenario,run}.jl`; `src/TSODSO.jl`; `src/pricing/dlmp.jl`;
  `src/settlement/feasibility.jl`; `test/{fixtures_two_bus,fixtures_four_quad_bess,runner_support,runtests}.jl`;
  `test/test_admm_reactive.jl`, `test/test_pvbattery.jl` listing
- `.planning/phases/43-.../43-CONTEXT.md` (locked decisions); `.planning/ROADMAP.md` Phase 43;
  `.planning/REQUIREMENTS.md` DEV-06..10; `.planning/config.json`
- `.planning/research/FEATURES.md` rows 65-71, 97, 108-112, 141-142, 161-163 (research pre-answers)

### Secondary (MEDIUM confidence)
- Prior-phase research (gate-then-golden, `:slow` budgets, pitfalls): `40-RESEARCH.md` (POP-04
  measured-band design), `41-RESEARCH.md` (A5 script-artifact rule), `42-RESEARCH.md` (Pitfalls
  1-8: Symbol trap, formatter, equality-assert)
- Kircher, "Thermal modeling of buildings" (Purdue ME 597 DER notes),
  kevinjkircher.com/wp-content/uploads/2025/02/der-buildings-2.pdf — 2R2C ODEs + exact ZOH
  discretization [VERIFIED via web this session: form matches]

### Tertiary (LOW confidence)
- Exact bibliographic details for Bacher & Madsen 2011 / Reynders et al. 2014 / ISO 13790 5R1C
  (canonical names from FEATURES.md; verify before thesis bibliography) — flagged A7

## Metadata

**Confidence breakdown:**
- Device anatomy / plug-in points: HIGH — every file/line cited was read this session
- Reactive-consensus path & trait seams: HIGH — all 5 probe sites located and quoted; the
  FixedCapacitor classification asymmetry is flagged for the equivalence test (A8)
- 2R2C math: HIGH for the form (repo templates + literature-verified ODE), MEDIUM for
  bibliographic precision
- EV formulation: HIGH (all idioms in-repo); certificate tolerance VALUES: deliberately
  unmeasured until the fixtures exist (gate-then-golden)
- Pitfalls: HIGH — 42-RESEARCH transfer + repo-verified failure histories

**Research date:** 2026-10-26
**Valid until:** 2026-11-25 (stable domain; repo-local — re-verify only if the device/admm files
change under this phase's own work)
