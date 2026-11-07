# Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter) - Context

**Gathered:** 2026-10-26
**Status:** Ready for planning

<domain>
## Phase Boundary

A researcher can add EVs, heat pumps and smart-inverter PV as convex, binary-free devices, each
validated against the centralized solve before ADMM use. Deliverables: a device-capability trait
refactor landing FIRST (existing fixtures keep their resolved reactive mode; goldens unchanged);
an EV device with seeded arrival/departure sessions and a soft departure energy target (V1G),
extendable to V2G with a strictly positive degradation cost and a certificate that reports any
simultaneous charge/discharge (including on a negative-price fixture); a heat-pump device with a
2R2C building thermal model, exogenous COP(T_out) profile and a comfort band under a consistent
terminal-temperature rule; smart-inverter PV supplying optimal reactive power within an apparent-
power cone, with SOCP exactness re-measured in the high-PV regime and a Volt-VAR droop curve
evaluated only post hoc as a comparator; and a per-device-class centralized-vs-ADMM validation
gate. Requirements: DEV-06, DEV-07, DEV-08, DEV-09, DEV-10.

v5.0 policies bind this phase: **golden policy** (default path byte-identical — existing device
files and fixtures untouched behaviourally, canary never re-pinned) and **honesty policy**
(certificates report, never loosen; a reported co-charge on the negative-price fixture is the
certificate working, not a defect). Binary-free is a HARD project rule (REQUIREMENTS Out-of-Scope:
"Binary EV / compressor on-off logic — Project rule: convex device models, no binaries").

</domain>

<decisions>
## Implementation Decisions

**Mode:** Auto-accepted recommended answers (autonomous run, user pre-authorization)

### EV Device Model (V1G / V2G, DEV-06/07)
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
  rejected as the default (infeasibility risk; the research line is "soft via quadratic shortfall
  penalty ... keeps feasibility and matches the quadratic-utility style").
- V2G: discharge enabled with a STRICTLY POSITIVE linear degradation cost `c_deg·p_dch[t]`
  (research: "linear or quadratic throughput cost on discharge"; linear keeps the App. C
  λ-structure interpretable). Its no-binary justification is the App. C argument EXTENDED by
  `c_deg` (discharge only when paid ≥ marginal cost), and because η² < 1 co-charge is known to be
  attainable at zero/negative prices (the repo's own App. C η<1 finding), a DEDICATED
  `assert_ev_complementarity!`-style post-solve certificate (scale-free `p_ch·p_dch < τ·Pmax²`
  form, same `:error`/`:warn` convention) is MANDATORY, exercised on a negative-price fixture where
  co-charge would appear without the degradation cost. V2G is opt-in (a constructor field/kwarg);
  the V1G default path stays the smaller model.

### Heat Pump (DEV-08)
- New dedicated `HeatPump{T} <: AbstractDevice` struct in `src/devices/HeatPump.jl` with a 2R2C
  two-state building thermal model (indoor-air `Tin` + envelope-mass `Tem` states, coupled linear
  recursion with the ambient profile) — `Thermostatic` is NOT modified (byte-identical golden
  policy; the research line "extends existing thermostatic device (3.2) to two coupled states" is
  realized as a new device following the `Thermostatic` template). Reviewers will not accept a
  1-state model as a building thermal model (research FEATURES row 68).
- COP is an EXOGENOUS per-step parameter vector `COP::Vector{T}` (validated `length ≥ T` at
  `contribute!` time, exactly like `Thermostatic`'s `Tout`), so heat `Q = COP[t]·p` stays LINEAR
  and the model convex. No endogenous temperature-dependent (Carnot) expression. No JuMP
  `Parameter` seam in this phase (mirror `Tout`, not `Ppv_param`) — the MPC re-target seam is only
  added if a windowed use actually needs it (avoid over-building).
- Comfort band is a HARD band on the indoor-air state plus the concave-quadratic comfort utility
  (the `Thermostatic` eq. 3.3 + 3.11 pattern, curvature `b > 0` guard). Consistent
  terminal-temperature rule: BOTH states are `T+1` long, the recursion unconditionally covers
  `t = 1:T` closing on `state[T+1]` with the band applying at `T+1` (the PVBattery whole-horizon
  closure rule), plus an optional `terminal` kwarg mirroring `PVBattery`'s `soc_terminal`
  (`nothing` default / `Real` / `:cyclic` against the initial-condition Parameter) so a run can pin
  or cyclicize the terminal state explicitly.
- The heat pump is a flexible LOAD: `is_flexible_load(::HeatPump) = true`, so it inherits the
  eq. 3.23 power-factor reactive draw through the existing `Aggregator` roll-up (with the
  per-device `φ` override convention); electric draw `p ∈ [0, Pmax]` in the heating convention
  (`+COP·p` heat gain, constructor-guarded signs).

### Smart-Inverter PV (DEV-09)
- New dedicated `SmartInverterPV{T} <: AbstractDevice` struct in `src/devices/SmartInverterPV.jl`
  (the `FourQuadBESS` precedent — the 4Q capability shipped as a SEPARATE device rather than
  widening `PVBattery`): a PV generator with curtailable `pv_used` (the `PVBattery` curtailment
  pattern) and an optimal-Q reactive decision `q[t]`. `PVBattery` itself is NOT widened — its
  tests/goldens stay structurally untouched, and households without batteries still get
  smart-inverter PV (a `PVBattery` kwarg would force a battery). Battery+inverter co-location via
  a combined device is a noted non-goal for this phase.
- Apparent-power cone: ONE ANONYMOUS per-t `SecondOrderCone` constraint
  `[S_inv, pv_used[t], q[t]] in SecondOrderCone()` — the `FourQuadBESS.jl:385` idiom verbatim
  (anonymous; never a named container, per the object-dictionary collision discipline).
  `S_inv > 0` constructor guard.
- Q carries NO device utility term (zero-cost optimal Q, the `FourQuadBESS` convention: "no cost
  or utility term on reactive power anywhere"); welfare sees Q only through the network, and it is
  priced only by the certified reactive DLMP (`extract_reactive_dlmp`, untouched). Thesis A3
  (DER active-only) is LIFTED for this device by routing its `q_inject` through the EXISTING
  reactive-consensus path (`qag_dso` pin / LIVE dual ascent) — never bypassing it.
- SOCP exactness re-measured in the high-PV regime: a fixture at high `pv_scale` (the EXACT-04 /
  pv-boom regime) with and without optimal Q, measured through the standard gates
  (`assert_socp_exact!`/hybrid ratios) — "refused with certificate" is a valid measured outcome.
  Volt-VAR droop: POST-HOC comparator ONLY — evaluated on the fixed dispatch via the Phase-27/41
  physics-only idiom (`ACPowerFlow(; limits = false)` + reported diagnostics) in the validation
  artifacts/literate page; NEVER a convex constraint (piecewise-linear droop with deadband is not
  convex); the droop-as-control-loop remains DEV-F1 (future).

### Capability Trait Refactor, Validation & Registration (DEV-10)
- The refactor lands FIRST (success criterion 1): small trait functions on `AbstractDevice.jl` —
  (a) a reactive-capability trait (e.g. `has_reactive_decision(d)::Bool`, default `false`) replacing
  the hard-coded `dv isa FourQuadBESS || is_flexible_load(dv)` probes in `DsoOpt.jl` /
  `admm_state.jl`'s `_default_reactive_consensus`, and (b) a storage-classification trait so the
  battery-complementarity predicate's var-shape sniffing (`haskey(v, :p_ch) && haskey(v, :p_dch) &&
  !haskey(v, :q)`) becomes trait-driven and the EV/V2G certificate reuses the same machinery.
  Defaults are set so EVERY existing device classifies exactly as today — a test proves the
  equivalence (existing fixtures keep their resolved reactive mode; `:default` goldens unchanged).
- Per-device-class validation BEFORE ADMM use: one test file per new device
  (`test_electricvehicle.jl`, `test_heatpump.jl`, `test_smartinverterpv.jl` — the
  `test_pvbattery.jl`/`test_device.jl` convention), each with a small fixture (two-bus/IEEE-13
  scale) cross-validating the centralized `solve_welfare` optimum against the ADMM result
  (agreement bands MEASURED then pinned — gate-then-golden; `:slow`-tagged where heavy). A device
  class is used under ADMM only after its centralized match passes.
- Registration/naming: new files in `src/devices/` each declaring their own exports (project
  convention); include ordering after `PVBattery`/`FourQuadBESS` in `TSODSO.jl`. EV session
  sampling (arrival/departure/energy) is seeded via the established hash idiom
  (`hash((seed, :ev, bus, house_index))`-style, the `_case_a_house_seed` pattern) with truncated-
  normal arrival/departure + lognormal energy draws whose parameters are DOCUMENTED as
  low-confidence calibration (research row 66 cites ACN-Data/NHTS as the check-later source).
- Population entry: new devices reach experiments through population-construction opt-ins
  (`build_population`-level selector branch/kwarg, the `:case_a_784` additive-branch pattern) — the
  `Scenario` schema is NOT touched in this phase (Scenario.jl is schema-fragile and golden-hash-
  bearing; the Phase-21/22 coordinated-schema lesson). `:default` and `:case_a_784` stay
  byte-identical.

### the agent's Discretion
- Exact trait function names/signatures, the soft-target penalty's exact quadratic-vs-affine form,
  session-distribution parameter values (documented, low-confidence), fixture sizes, test/CSV
  naming, and whether the smart-inverter exactness re-measurement lands as a test or a literate
  artifact are at the agent's discretion within the decisions above.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/devices/AbstractDevice.jl` — the AGGREGATABLE-device contract: `contribute!(dev, ctx; T)`
  builds vars/constraints on `ctx.model`, writes NOTHING to residuals/objective, RETURNS
  `(; vars, p_inject, [q_inject], utility)`; `is_flexible_load` trait (default `false`) — the seam
  the capability refactor extends.
- `src/devices/PVBattery.jl` — the storage template: App. C no-binary λ-triple with STRICT
  ordering constructor guard, T+1-length state closing the whole horizon, `soc_terminal`
  (`nothing`/`Real`/`:cyclic`) kwarg, anonymous JuMP `Parameter` seams (`soc0`, `Ppv_param`),
  curtailment `pv_used`.
- `src/devices/FourQuadBESS.jl` — the reactive-device template: sign-free `q`, anonymous per-t
  `[Smax, p_net[t], q[t]] in SecondOrderCone()`, `q_inject` in the return, NO utility on q — the
  smart-inverter's direct pattern.
- `src/devices/Thermostatic.jl` — the thermal template: linear state recursion with ambient
  profile `Tout::Vector` (validated at contribute! time), hard comfort band, concave-quadratic
  comfort utility, per-device `φ` override — the heat pump's direct pattern.
- `src/devices/Aggregator.jl` — sole `:Rp`/`:Rq` writer; `hasproperty(res, :q_inject)` guard;
  `is_flexible_load` power-factor accumulation; `ctx.agg_device_vars` stash keyed by bus (feeds
  the complementarity certificates). New devices need NO aggregator changes.
- Certificates: `assert_battery_complementarity!` (`src/models/welfare_solve.jl`, scale-free
  `τ·Pmax²` relative test, `on_violation = :error/:warn`, mandatory in `solve_welfare`) and
  `assert_4q_complementarity!` (`src/models/complementarity_4q.jl`) — the EV certificate's
  machinery; AgrOpt runs `check_battery` off mid-loop / on final (`src/admm/AgrOpt.jl`).
- The refactor targets: `src/admm/DsoOpt.jl`'s reactive probe
  (`dv isa FourQuadBESS || is_flexible_load(dv)`, lines ~173/326) and
  `src/admm/admm_state.jl:409` `_default_reactive_consensus` — the classification that must stay
  resolved-identical for existing fixtures.
- `_case_a_house` / `_case_a_house_seed` (`src/experiments/materialize.jl`) — per-house device
  construction + hash-seeded sampling precedents; `build_population` selector dispatch — the
  additive opt-in point for flex-device populations.
- Research pre-answers: `.planning/research/FEATURES.md` rows 65–71, 97, 108–112, 141–142 (EV =
  availability-windowed battery-deriv; V2G needs positive degradation cost + post-hoc
  complementarity — the repo's own App. C η<1 co-charge finding is the cited risk; HP 2R2C with
  fixed COP keeps Q linear; Volt-VAR = the FourQuadBESS cone pattern; droop is post-hoc ONLY).
- Test precedents: `test_pvbattery.jl`, `test_device.jl`, `test_admm.jl` (centralized-vs-ADMM
  cross-validation), `fixtures_two_bus.jl`, the `:slow` tag split + `expected_broken.txt` guard.

### Established Patterns
- Fail-loud `ArgumentError` constructor guards (never `@assert`); promotion outer constructors.
- ANONYMOUS JuMP construction (containers, Parameters, cones) — never named object-dictionary
  entries; multi-instance composition in one shared model depends on it.
- Byte-identical default path: new devices/types/kwargs are opt-in; `:default` population and
  existing device files behaviourally untouched; canary (`iters = 56`,
  `welfare = -4823.66604824162`) never re-pinned.
- Each new mathematical regime gets its OWN certificate/gate — never a reused tolerance (v3.0
  standing anti-"certificate-laundering" bar); gate-then-golden / measurement-before-golden for
  any pinned numeric band.
- Honesty policy: reported co-charge / refused exactness are first-class measured outcomes.
- JuliaFormatter (pinned 2.10.2, 92-col); tests via `julia --project=. -e 'import Pkg; Pkg.test()'`
  only.

### Integration Points
- `Aggregator.contribute!` roll-up (3.21–3.23) + `ctx.agg_device_vars` — where every new device
  lands without aggregator changes; `:Rq` reactive path (reactive consensus LIVE/CERTIFIED) for
  the smart-inverter's `q_inject`.
- `src/admm/AgrOpt.jl` (reuses `contribute!` verbatim; battery check kwargs) and
  `src/admm/DsoOpt.jl` (reactive probe → trait) — the ADMM integration seams.
- `assert_battery_complementarity!` / `assert_4q_complementarity!` / the new EV certificate —
  `welfare_solve` + AgrOpt post-solve hooks.
- `build_population` selector dispatch + household map — population-level opt-in; `Scenario`
  schema deliberately untouched.
- `extract_reactive_dlmp` (certified μ) — smart-inverter Q pricing; `ACPowerFlow(; limits=false)`
  physics idiom — the post-hoc droop comparator.
- `results/` + `docs/literate/` artifact pattern; REQUIREMENTS.md traceability DEV-06..10.

</code_context>

<specifics>
## Specific Ideas

- The research digest pre-answers the device math and constraints (FEATURES.md rows 65–71,
  108–112, 141–142): EV = battery/deferrable with an availability window; V2G's binary-free caveat
  is the repo's OWN App. C η<1 finding (co-charge attainable at zero/negative prices) — hence the
  strictly positive degradation cost plus a dedicated post-hoc certificate, with the negative-price
  fixture as its exercise. Heat pump = 2-state (2R2C) thermal model with COP fixed exogenous so
  `Q = COP[t]·p` stays linear; smart-inverter Volt-VAR = the FourQuadBESS apparent-power-cone
  pattern attached to PV, routed through the reactive-consensus path (never bypassing A3's lift).
- Binary-free is non-negotiable (REQUIREMENTS Out-of-Scope row): charging windows enter as bounds,
  comfort/shortfall as soft convex penalties or bands — never big-M, never semicontinuous.
- Success criterion 1 ordering is binding: the capability trait refactor lands FIRST and a test
  proves existing fixtures keep their resolved reactive mode (`_default_reactive_consensus`
  classification unchanged) before any new device lands.
- Droop is a fixed-point simulation, not a convex constraint — post-hoc comparator only (DEV-F1
  defers the control loop); optimal Q is the convex model of record.

</specifics>

<deferred>
## Deferred Ideas

- Volt-VAR droop as an outer fixed-point control loop — DEV-F1 (future requirement, out of this
  phase's scope by DEV-09's own wording).
- Reactive-power REMUNERATION of smart inverters at the certified reactive DL μ in the settlement
  ledger — a Phase-45 settlement concern (research row 92); this phase prices Q via the existing
  certified path only.
- Battery + smart-inverter co-location in ONE device struct (a combined PV+battery+Q model) —
  noted as a possible follow-up composition; this phase ships SmartInverterPV standalone.
- EV session recalibration against ACN-Data/NHTS empirical data — parameters documented as
  low-confidence; empirical refit is its own future task.
- Binary EV on/off, minimum charge power, compressor cycling — permanently out of scope (project
  convex-only rule).
- Aggregator-actor (ACTOR) coupling of the new devices — Phase 44 scope.

</deferred>
