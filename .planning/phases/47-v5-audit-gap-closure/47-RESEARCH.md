# Phase 47: v5.0 Audit Gap Closure - Research

**Researched:** 2026-11-06
**Domain:** Certificate routing and loud input guards on the settlement / flexibility-market seams (Julia + JuMP, in-repo code only)
**Confidence:** HIGH (every claim below was read in code at HEAD 113d4d4 or measured with a Julia 1.12.5 probe this session)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

## Implementation Decisions (user-approved 2026-11-06)

### B1: V2G EV certificate, "Fix: run EV certificate"

**The defect:**
- `src/settlement/price_taker.jl:125-128` and `src/coordination/flex_clear.jl:442-445` compute
  `has_battery` with the shape predicate `p_ch ∧ p_dch ∧ ¬q`. A V2G `ElectricVehicle` matches it.
- `assert_battery_complementarity!` (`src/models/welfare_solve.jl:425-450`) selects devices by the
  `storage_kind` trait via `_stash_entry_has_kind`, so it skips EVs.
- The result is `battery_certificate = :ok` even though nothing ran. `assert_ev_complementarity!`
  (`src/models/complementarity_ev.jl`) is never called on these paths.

**The fix:**
- Both `has_battery` predicates must select through the same trait routing
  (`_stash_entry_has_kind(..., :battery, ...)`) that the check itself uses.
- When the population contains V2G EVs, both paths run the EV co-charge certificate and record it as
  its **own status**, for example `ev_certificate` / `ev_message` with values
  `:not_checked | :ok | :refused`. It follows the same report semantics as `battery_certificate`:
  try/catch on `CertificateError`, never rethrow, never loosen τ.
  - A V1G-only EV population has no `p_dch`, so it reports `:not_checked` for EV co-charge.
- **The EV τ** must be an existing, measured constant chosen by the same rule these paths already use
  to choose `τ_batt`. The research step decides which of the two existing values applies on a standalone
  price-taker or stage-2 solve: `TAU_EV` (centralized, 2e-7) or `TAU_EV_ADMM` (3.6e-3, ADMM final
  consolidation only). **Do not pick a new value.**
- **Where the status flows:** `clear_flex_market` must carry the new status into its `physics` record,
  as `battery_certificate` does.
  - The research step checks whether the price-taker and flex records feed any CSV writer
    (`compare_tariffs` rows, `results/settlement_comparison/*.csv`).
  - Committed CSVs must stay byte-identical. Either the new status does not reach the CSV schema, or it
    reaches it only additively and no committed CSV is regenerated. The research step recommends which.
- **Tests:** a V2G EV fixture on each path, including a negative-price fixture that forces co-charge
  (the Phase 43 pattern in `test/test_electricvehicle.jl`). The test shows the EV certificate
  reporting `:refused` (or `:ok` where truly clean) and the battery certificate never claiming `:ok`
  for an EV-only population.

### B2: actors × flex market / tariff comparison, "Record scope + guard"
- **Scope decision (recorded):** settling profit-seeking aggregator actors (`ProfitObjective` wedge,
  `Portfolio` slots, Phase 44) through `clear_flex_market` or `compare_tariffs` is **future work**.
  Phase 45 met SETL-07/08 with ledger actors = DSO / aggregators / wholesale.
  - Record the decision in REQUIREMENTS.md: a note on the SETL-07/08 traceability rows, plus a
    future-requirements entry.
  - Record it in the docs limitations section of `docs/literate/flex_market.jl` and in the audit.
- **Guard:** both functions must refuse actor inputs with an `ArgumentError` whose message names the scope
  decision.
  - The research step must first find every channel through which an actor can reach them: keyword
    arguments, population/aggregator objects carrying a non-welfare objective or portfolio,
    behaviour-wrapped devices, shared-bus aggregators. Guard only the channels that exist.
  - If the only channel is a keyword the functions do not accept today, so it already fails with a
    `MethodError`, the planner decides between two options:
    - add an explicit `actors = nothing` keyword that throws an `ArgumentError` when it is not `nothing`;
    - document the `MethodError` as the refusal, matching the Phase 44 item-8 precedent.
    The decision is recorded either way.
  - **Behaviour wrappers** (`apply_behaviour`, ACTOR-04) are device-level. The research step decides whether
    they are an actor channel for this guard. If wrapped devices already work correctly through these paths,
    they are not refused.

### W2 + W3: device guards, "Add W2+W3 guards"
- **W2:** `compare_tariffs` currently refuses unsupported Phase-43 devices only in the fit leg, after
  the dadp, flat and tou legs have solved (`src/settlement/comparison.jl` around 609-816).
  - Move the existing `_reject_unsupported_flex_devices` check, or an equivalent, into the
    boundary-guard block so the refusal happens **before any solve**.
  - The supported-device set and the error type stay the same; only the timing changes.
- **W3:** flex stage 2 already refuses `FixedCapacitor`, because stage 2 fixes reactive draw at
  `−Pdc·tanφ` (`src/coordination/flex_clear.jl:157-170`).
  - Refuse devices with a reactive decision, `has_reactive_decision == true`
    (`SmartInverterPV`, `FourQuadBESS`), the same way, using the trait rather than a type list.
  - The research step confirms that no committed flex-market result uses such devices; this is expected
    because those results use the default population. If one does, stop and report.
- Each guard gets a test.

### Backlog (no code this phase)
- Integration-check items W1, W4, W5, W6, W7, W8 and W9, plus the two unresolved `@ref` warnings in
  the docs build, become one backlog todo file under `.planning/todos/pending/`.

### Claude's Discretion
- The plan split. Expected: one plan for B1, one for the guards (B2/W2/W3), and one closure plan for
  docs, requirements, the audit update and the backlog todo. Merge them if they are small.
- The names of the new status fields, as long as they mirror `battery_certificate`.

### Deferred Ideas (OUT OF SCOPE)
- Actor-aware flex market and tariff comparison: wedge lines and flex payments in one ledger, residual 0.
- Reactive (q) dispatch in flex stage 2.
- Integration-check items W1, W4–W9: backlog todo.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-07 | V2G EVs with positive degradation cost; a certificate reports any simultaneous charge/discharge (including a negative-price fixture) | B1 answers 1–3 below: the trait-routed `has_battery`, the `ev_certificate`/`ev_message` status using `TAU_EV_ADMM`, the negative-price fixture measured at a ratio of 0.66 on `price_taker_dispatch` (183× τ) |
| SETL-07 | DSO flexibility market producing the same settlement record as price-based coordination | B1 on `clear_flex_market` (physics `baseline`/`delivered` records); W3 reactive-decision refusal; B2 `actors` refusal plus the documented SettlementInput limitation |
| SETL-08 | Comparison table across FIT, TOU, flat, DADP and flex | W2 up-front refusal in `compare_tariffs`; B2 `actors` refusal; CSV schema unchanged (answer 3) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Julia + JuMP; no named solver inside a model (`select_optimizer(QP())` stays the pattern in `price_taker_dispatch` / `_deliver`).
- Correctness and traceability over speed; every modelling assumption is documented. The W3 and B2 refusals need docstring and docs text.
- Reproducibility: pinned environment. The digest fences assert only on Julia 1.12.5, which is the active `release` channel here (verified: `julia --version` = 1.12.5).
- Extensibility via traits, not type lists. This is the reason W3 uses traits, and it is also where the W3 STOP below comes from.
- GSD workflow: edits only inside a GSD command.
- Memory and project conventions that apply here:
  - The `@testitem` soft-scope trap: no `try x = …` and no outer-variable reassignment inside a top-level `for`. Wrap such code in a function.
  - Never re-pin goldens.
  - Tolerances are measured, never picked.
  - New src/test/docs text adds no planning-ID hits. The baseline is 355, verified this session with `python3 .github/scripts/check_planning_ids.py`. The guard also flags the phrase "byte-identical" (rule `byteid`), `ROADMAP`, `REQUIREMENTS.md`, `Pitfall N`, `WR-NN`, `DEV-NN` and `phase NN`. Use "unchanged" or "bit-for-bit" in code comments.

## Summary

All four audit items are small, local edits. Two findings change what the CONTEXT literally says, and the planner must handle them first.

**STOP on W3 (literal predicate).** `has_reactive_decision` is **true for every flexible load**, not just `SmartInverterPV` and `FourQuadBESS`. Its default is `has_reactive_decision(d) = is_flexible_load(d)` (`src/devices/AbstractDevice.jl:109`). Measured trait table this session:
- true: `Interruptible`, `Thermostatic`, `Deferrable`, `HeatPump`, `FourQuadBESS`, `SmartInverterPV`;
- false: `PVBattery`, `FixedCapacitor`, `ElectricVehicle`, `FlexBidDevice`.

A refusal keyed on `has_reactive_decision == true` would therefore refuse every flex-market test fixture (Interruptible/Thermostatic/Deferrable). It would also refuse the populations behind every committed `flex_*` row of `results/settlement_comparison/tariff_comparison.csv`: the IEEE-13 and IEEE-123 default houses are `[Thermostatic, Deferrable, PVBattery]` (`materialize.jl` `_default_house`, line 259).

Stage 2 *deliberately* drops the flexible-load `p·tanφ` draw. This is documented in `flex_clear.jl:17-25` and `docs/literate/flex_market.jl:130-139`, so those devices are supported, not silently mishandled. The predicate that selects exactly the CONTEXT's intended set {`SmartInverterPV`, `FourQuadBESS`}, still by trait, is:

`has_reactive_decision(d) && !is_flexible_load(d)`

It holds for exactly those two types, and is false for every flexible load, for `FailAtCall` and for the wrappers. No committed result or existing test uses `SmartInverterPV` or `FourQuadBESS` with the flex market, so the refined guard changes no committed output. **The user or planner must confirm the refined predicate before execution.**

**B2 has one silent channel the CONTEXT did not list.** `clear_flex_market` takes `input::SettlementInput`. Measured: an input from `solve_welfare(...; actors = [Portfolio(...; objective = ProfitObjective(0.5))])` → `settlement_input(ctx)` is accepted. It clears with `status = "ok"`, residual 0.0 and no actor ledger lines, and its `source` is `:centralized`, the same as a welfare run. Detecting it would need a provenance field on the pinned `SettlementInput` type, which is out of scope. Every other channel already fails loudly:
- the `actors` keyword gives a `MethodError` on both functions;
- a `Vector{Portfolio}` passed as `aggs` gives a `MethodError`;
- shared buses give an `ArgumentError` on both;
- `Aggregator` has no objective field.

ROADMAP success criterion 2 says "refuse ... with an `ArgumentError`", so an explicit `actors = nothing` keyword is warranted. The input channel is documented as a limitation.

**Primary recommendation:**
- **B1:** one shared internal helper, used by both `price_taker_dispatch` and `_deliver`. It does trait-routed battery selection plus a trait-routed V2G EV certificate at `TAU_EV_ADMM`, and returns `ev_certificate`/`ev_message`. The EV counts are added to `_dispatch_record` additively. Nothing reaches any DataFrame or CSV.
- **W2:** `_reject_unsupported_flex_devices` runs per aggregator in the `compare_tariffs` boundary block.
- **W3:** a sibling of `_refuse_fixed_capacitor` with the refined predicate, called at its three call sites.
- **B2:** an `actors = nothing` keyword on both functions that throws an `ArgumentError` naming the scope decision.

## Architectural Responsibility Map

The "tiers" in this repo are module seams, not web tiers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Certificate selection by device class | `src/devices/CapabilityTraits.jl` (`storage_kind`, `_stash_entry_has_kind`) | `src/core/ModelContext.jl` (type-paired stash) | Classification is a property of the type, never of variable names |
| Certificate math (battery, EV) | `src/models/welfare_solve.jl`, `src/models/complementarity_ev.jl` | — | Consumed, never modified (golden policy) |
| Certificate status recording (report semantics) | `src/settlement/price_taker.jl` (new shared helper) | `src/coordination/flex_clear.jl` (`_deliver`, `_dispatch_record`) | The two price-taker-shaped solves share one report routine, so the defect cannot re-diverge |
| Input refusals before any solve | `src/settlement/comparison.jl` boundary block; `src/coordination/flex_clear.jl` / `flex_settle.jl` guards | `src/pricing/fit.jl` (`_reject_unsupported_flex_devices`, reused) | Guards live at the public entry points |
| Persistence (CSV) | `scripts/tariff_comparison.jl` | — | `compare_tariffs` does no IO; it builds columns explicitly by name |

## Standard Stack

No new libraries. Everything uses the existing in-repo API.

| Component | Location | Purpose |
|-----------|----------|---------|
| `_stash_entry_has_kind(types, v, i, kind, legacy_shape)` | `src/devices/CapabilityTraits.jl:61-72` | Trait-routed stash selection with a legacy-shape fallback for hand-built contexts |
| `assert_battery_complementarity!(ctx; τ, T, on_violation)` | `src/models/welfare_solve.jl:413-466` | Battery certificate; selection at 436-444 |
| `assert_ev_complementarity!(ctx; τ = TAU_EV, T = _require_T(ctx), on_violation = :error, report = false) -> Float64` | `src/models/complementarity_ev.jl:96-143` | EV certificate; throws `CertificateError(msg; kind = :ev)` |
| `TAU_EV = 2e-7`, `TAU_EV_ADMM = 3.6e-3` | `src/models/complementarity_ev.jl:74, 82` | Existing measured constants |
| `_reject_unsupported_flex_devices(devices, caller)` | `src/pricing/fit.jl:81-97` | Refuses `ElectricVehicle, HeatPump, SmartInverterPV, PartialCompliance, OptOut, Rebound` |
| `_refuse_fixed_capacitor(aggs, who)` | `src/coordination/flex_clear.jl:157-170` | Template for the W3 sibling |
| `has_reactive_decision`, `is_flexible_load` | `src/devices/AbstractDevice.jl:84,109`; `CapabilityTraits.jl:23,41-46`; `SmartInverterPV.jl:89` | W3 predicate |

**Installation:** none.

## Package Legitimacy Audit

Not applicable. This phase installs no external packages: in-repo code only, with `Project.toml`/`Manifest.toml` untouched.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Answers to the research questions

### 1. B1, routing: the exact edit (`file:line`)

**Current shape predicates:**

`src/settlement/price_taker.jl:126-129`:
```julia
has_battery = any(
    haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q) for
    varlist in values(ctx.agg_device_vars) for v in varlist
)
```
`src/coordination/flex_clear.jl:443-446` holds the identical expression.

**Replacement, the same selection as `welfare_solve.jl:436-444`:**
```julia
_batt_shape(v) = haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q)
has_battery = any(
    _stash_entry_has_kind(get(ctx.agg_device_types, bus, nothing), v, i, :battery, _batt_shape)
    for (bus, varlist) in ctx.agg_device_vars for (i, v) in enumerate(varlist)
)
```

**`ctx.agg_device_types` is populated on both paths. [VERIFIED: code + probe]**
- Both `price_taker_dispatch` (`price_taker.jl:104`) and `_deliver` (`flex_clear.jl:424`) call `contribute!(agg::Aggregator, ctx; T)`.
- `Aggregator.contribute!` pushes `typeof(d)` into `ctx.agg_device_types[agg.bus]` in the same per-device loop (`src/devices/Aggregator.jl`, the `push!(get!(ctx.agg_device_types, ...), typeof(d))` line inside `for d in agg.devices`). It appends the vars in the same order after the loop.
- Probe: on the price-taker build, `ctx.agg_device_types == Dict(2 => [ElectricVehicle{Float64}])`. A 15-device mixed aggregator gave `length(vars) == length(types) == 15`.

**The change gives the same result for every existing population. [VERIFIED: probe 2026-11-06]**
- The probe compared the shape predicate with the trait predicate for every stash entry of one aggregator holding Interruptible, Thermostatic, Deferrable, PVBattery, FixedCapacitor, FourQuadBESS, V1G EV, V2G EV, HeatPump, SmartInverterPV, `PartialCompliance{PVBattery}`, `Rebound{PartialCompliance{PVBattery}}`, `OptOut{PVBattery}`, and `PartialCompliance{EV}` in both V2G and V1G form.
- The predicates agree on every entry **except the V2G EV and the wrapped V2G EV**.
  - shape=true, trait=false: these are the B1 cases;
  - PVBattery and its wrappers: shape=true, trait=true;
  - OptOut: vars `(;)`, both false;
  - FourQuadBESS: has `:q`, both false.

So `battery_certificate` and the `batt_*` counts are unchanged for every EV-free population. No committed CSV population has an EV.

**B1 confirmed live today. [VERIFIED: probe]**
- `price_taker_dispatch(Aggregator(2, 0.9, [V2G EV], zeros(24)), fill(-50.0, 24)).battery_certificate == :ok`, although its raw EV ratio is 0.66.
- A compliant `clear_flex_market` (Interruptible + V2G EV, swing λ₀, two-bus) gives `status = "ok"` with `physics.baseline.battery_certificate == [:ok]` and `physics.delivered.battery_certificate == [:ok]`. The population has no battery.

### 2. B1, the EV certificate

**Signature:** `assert_ev_complementarity!(ctx::ModelContext; τ::Real = TAU_EV, T::Int = _require_T(ctx), on_violation::Symbol = :error, report::Bool = false) -> Float64` (`complementarity_ev.jl:96-102`).
- It selects `_stash_entry_has_kind(types, v, i, :ev, _ -> false) && haskey(v, :p_dch)` (lines 112-115). There is no legacy-shape fallback, so a stash without provenance never selects an EV.
- It throws `CertificateError(msg; kind = :ev)` with a message starting `"EV complementarity violated at bus …"` (lines 128-135).

**τ: use `TAU_EV_ADMM` (3.6e-3).** The rule these paths use for `τ_batt`:
- Both paths hard-code `τ_batt = 1e-3`, labelled "the ADMM-consolidation discipline" (`price_taker.jl:33, 73, 83`; `flex_clear.jl:407, 640`; `flex_settle.jl:315`; `comparison.jl:346`).
- That 1e-3 is exactly the ADMM final-consolidation battery τ. At the same call site the code pairs it with `τ_ev = TAU_EV_ADMM` (`src/admm/admm_state.jl:166-168` and `202-204`).
- The rationale is the same: an IPM on a QP co-activates the optimal face, so the QP-tight value under-tolerances (`AgrOpt.jl:244-256`). The standalone/centralized pair is `(τ_batt = 1e-6 | problem-class τ, TAU_EV)`, which these paths explicitly did **not** adopt.
- So the same rule maps to `TAU_EV_ADMM`. [VERIFIED: code]

**Measurement supports it.** Price-taker builds, raw ratio `max p_ch·p_dch/Pmax²` [VERIFIED: probe, Julia 1.12.5]:

| Regime (penalty-free price-taker QP, T = 24) | Max ratio | > TAU_EV (2e-7) | > TAU_EV_ADMM (3.6e-3) |
|---|---|---|---|
| 75 compliant solves: test EV and 24 seeded `_flex_ev` (house 1:24, scale 0.02) converted to V2G, each at swing / flat 4 / TOU prices | 1.2003e-3 (flex EV h=4, swing) | **19 of 75** | 0 of 75 |
| The compliant clear's stage-1 flat baseline (p ≈ 2.655; Interruptible + V2G test EV) | 2.56e-3 | yes | no (0.71·τ) |
| Negative-price fixture on `price_taker_dispatch` (Pmax = 5, η = 0.9, c_deg = 0.01, price −50) | 0.66 | yes (3.3e6×) | yes (183×) |

- `TAU_EV` would refuse a quarter of the compliant price-taker solves. That would be certificate noise, not co-charge.
- `TAU_EV_ADMM` refuses none of them, and still flags the negative-price co-charge by a factor of 183.
- Margin caveat: the flat-baseline clear sits at 0.71·τ (degenerate flat price, the same effect the battery shows on flat baselines; see `docs/literate/flex_market.jl` "Refused baseline battery certificates"). If it ever flips to `:refused`, that is an honest outcome. Never retune it.

**`τ_ev` exposure.** Add `τ_ev::Real = TAU_EV_ADMM` as a keyword on `price_taker_dispatch` and `_deliver`, mirroring `τ_batt`. `price_taker_dispatches`/`household_dispatches` forward `kwargs...`. Do not thread it through `clear_flex_market`/`compare_tariffs`/`_flex_physics`: no caller needs it, and it keeps the public surface unchanged. This is planner discretion; the value is fixed either way.

**The negative-price fixture yields a measurable co-charge on both paths. [VERIFIED: probe]**
- **Price-taker:** `Aggregator(2, 0.9, AbstractDevice[ev_neg], zeros(24))` at `fill(-50.0, 24)`, where `ev_neg = ElectricVehicle(2, 0.9, 1.0, 5.0, 0.0, 40.0, 20.0, 20.0, 10.0, 1.0, 4.0, 9.0, 1, 24; v2g = true, c_deg = 0.01)` (`test_electricvehicle.jl:414-431`). Ratio 0.66, so the test asserts `ev_certificate === :refused`, `battery_certificate === :not_checked`, and `occursin("EV complementarity", ev_message)`.
- **`clear_flex_market`:** λ₀ must be positive (guard), so drive stage 1 with a hand-built `SettlementInput`:
  ```julia
  SettlementInput((prices = fill(-50.0, 1, T), bus_nets = Dict(2 => fill(-1.0, T)),
      bus_utilities = Dict(2 => 0.0), p_import = fill(1.0, T), λ₀ = fill(4.0, T),
      buses = [2], T = T, source = :centralized))
  ```
  `flat_prices` of that input is −50 everywhere.
  - Probe: on the two-bus feeder (`Branch(1, 2, 1e-3, 1e-3, 10.0)`, λ₀ = 4), the clear returns `status = "inexact_redispatch"`, with `physics.baseline` populated and today `[:ok]`.
  - The stage-1 record exists on every non-throwing status. Assert `res.physics.baseline.ev_certificate == [:refused]` and `battery_certificate == [:not_checked]`, and do **not** pin `res.status`.
- **Delivery path:** call `TSODSO._deliver(agg_neg, fill(-50.0, T), zeros(T); T, weight = 500.0)` directly and expect `ev_certificate === :refused`. The same QP plus the tracking term; not separately probed. Expected from the identical stage-1 build: [ASSUMED], low risk.

**How `:not_checked` is decided.** Mirror the certificate's own selection:
```julia
has_v2g = any(
    _stash_entry_has_kind(get(ctx.agg_device_types, bus, nothing), v, i, :ev, _ -> false) &&
    haskey(v, :p_dch)
    for (bus, varlist) in ctx.agg_device_vars for (i, v) in enumerate(varlist)
)
```
- V1G vars are `(; p_ch, soc, soc0)` (`ElectricVehicle.jl:402`), so `has_v2g == false` and the status is `:not_checked`.
- EV-free populations give `:not_checked`.
- Wrapped V2G (`PartialCompliance{ElectricVehicle}`) forwards the inner vars and `storage_kind` (`CapabilityTraits.jl:47`), so it is checked (probe: `ev_v2g = true`).
- Do not use the certificate's `0.0` return value as the "not present" signal, because a present-and-perfectly-clean V2G EV can also return ≈0.

### 3. B1, where the records flow, and the fence-safe design

**Record consumers. [VERIFIED: grep test/ scripts/ docs/literate/]**
- `price_taker_dispatch` record `(; net, utility, battery_certificate, battery_message)` is read by:
  - `compare_tariffs` (`comparison.jl:513-521` house solve; `698-711` flat/tou certs);
  - `_flex_physics` stage 1 (`flex_clear.jl:679`) → `_dispatch_record`;
  - `docs/literate/settlement_equity.jl:85-89` (prints `pt.battery_certificate`);
  - tests by field name (`test_settlement.jl:619-690`).
- No test pins its key set.
- `_deliver` record `(; net, utility, battery_certificate, battery_message, shortfall)`. Its **key set is pinned** at `test/test_flex_market.jl:939-940`.
- `_dispatch_record` (`flex_clear.jl:493-504`) is read by field name only (`comparison.jl:1100, 1238-1240, 1297`; `test_flex_market.jl:1007-1011`). Its key set is not pinned.
- `physics` top-level keys are pinned (`test_flex_market.jl:1024-1052`, asserted 1063 and 1147). So are the `clear_flex_market` record keys (`1226-1246`, asserted 1261). **Neither changes** if the EV fields live inside `baseline`/`delivered`.

**The CSV path never sees the records.**
- `compare_tariffs` builds every summary column explicitly (`_summary_row`, `comparison.jl:141-205`: 37 columns, pinned at `test_flex_market_fence.jl:36-74,153-154`).
- The flex extras are `FLEX_EXTRA_COLUMNS` (`comparison.jl:945-980`, pinned at `test_flex_market.jl:1628`). Only `batt_ok/batt_refused/batt_not_checked` and `baseline_batt_refused` are read from the certificate vectors.
- Committed CSVs with certificate columns: `results/settlement_comparison/tariff_comparison.csv` (cols 16-18, 73) and `results/thesis_case_a_magnitude/lens_summary.csv` (cols 12-14). Their populations have no EV.

**Digests.** The only digest that touches these paths is `test_flex_market_fence.jl`. It folds DataFrame column names and cells (`df_digest`, 120-127) and ledger transfers (`ledger_digest`, 130-142), and never a record NamedTuple. `ActorFenceDigest` folds `solve_admm`/`solve_welfare` outputs only. **No digest changes** when fields are added to the records. Baseline measured this session: the fence file's fast set passes 86/86 in 162 s, with digests `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`, equal to the pin.

**Recommendation: the EV status does not reach the CSV schema.** After W2, `compare_tariffs` refuses every EV population before any solve, so an EV column there would be constant and uninformative. It would also force a re-pin of the 37-column list and `FLEX_EXTRA_COLUMNS`.

Concretely:
- `price_taker_dispatch` returns `(; net, utility, battery_certificate, battery_message, ev_certificate, ev_message)`: the existing four fields first, two new fields appended.
- `_deliver` returns `(; net, utility, battery_certificate, battery_message, ev_certificate, ev_message, shortfall)`. **Update the pin at `test_flex_market.jl:939-940`** to this tuple. This is a field-set schema assertion, not a golden digest; record it as a deliberate additive change. An extra `@test c.d1.ev_certificate === :not_checked` belongs beside it, because the tight fixture is an Interruptible.
  - Alternative: keep `shortfall` second-to-last and append the EV fields after it. Either order requires the pin edit, so prefer price-taker-prefix order.
- `_dispatch_record` gains `ev_certificate::Vector{Symbol}`, `ev_message::Vector{String}`, `n_ev_ok`, `n_ev_refused`, `n_ev_not_checked`, appended after the existing seven fields. `physics.baseline`/`physics.delivered` therefore carry them, and `clear_flex_market` exposes them through `physics`.
- No change to `comparison.jl` column builders, and no regeneration of any CSV.

### 4. B2: actor channels

| Channel | `compare_tariffs` today | `clear_flex_market` today | Evidence |
|---|---|---|---|
| `actors = [Portfolio(...)]` keyword | `MethodError` (unsupported keyword) | `MethodError` | probe |
| `Vector{Portfolio}` passed as `aggs` | `MethodError` (dispatch on `AbstractVector{<:Aggregator}`) | `MethodError` (same signature) | probe; `flex_settle.jl:308` |
| `Aggregator` carrying an objective | impossible: `Aggregator` fields are `bus, φ, devices, Pdc`; objectives live only on `Portfolio` (`src/actors/Portfolio.jl:15-31`) | impossible | code |
| Shared-bus (multi-site) aggregators | `ArgumentError` "aggregators share buses …" (`comparison.jl:369-374`) | `ArgumentError` via `agg_buses == input.buses` (`flex_settle.jl:321-327`): duplicated buses never equal the unique `input.buses` | code |
| `input::SettlementInput` from an actor run (`solve_welfare`/`solve_admm` with `actors`) | n/a (runs its own DADP solve without actors) | **SILENT**: clears `ok`, residual 0.0, no actor lines, `input.source == :centralized` | probe (`ProfitObjective(0.5)`, two-bus) |
| Behaviour wrappers (`apply_behaviour`) | `ArgumentError` from the fit leg after the DADP/flat/tou solves (W2 moves it up front) | **work**: `PartialCompliance` (with storage), `OptOut`, `Rebound` populations all clear `status = "ok"`, residual 0.0 | probe |

**Recommendation.**
1. **Add an explicit `actors = nothing` keyword** (untyped) to `compare_tariffs` and `clear_flex_market`. If it is not `nothing`, throw an `ArgumentError` as the first statement, before any other guard or solve. The message must:
   - name the function;
   - say that settling profit-seeking aggregator actors (`Portfolio` / `ProfitObjective`) through the flexibility market or the tariff comparison is not supported;
   - say that this is a recorded scope decision (future work: wedge lines and flex payments in one ledger).

   This is warranted because ROADMAP success criterion 2 requires an `ArgumentError`, which a `MethodError` does not satisfy. It also turns an opaque error into one that names the scope decision.
   - Keep it untyped: a `Union{Nothing, AbstractVector{Portfolio}}` annotation would turn a wrong type back into a `MethodError`.
   - The default `nothing` is a no-op, so the default paths are unchanged.
   - No test pins the keyword list: `test_settlement.jl:1043-1090` checks values only.
2. **SettlementInput channel: document, do not guard.** It cannot be detected. `SettlementInput` is a `const` typed NamedTuple with 8 fixed fields (`run_inputs.jl:36-48`), and an actor run produces the same `source` symbol. A provenance field would change the type for every caller and the actor ledger metadata, which breaks this phase's "additive" constraint.
   - Put one sentence in the `clear_flex_market` docstring: an input from an actor-objective run is not detected; its wedges are not carried; this is out of scope.
   - Put the same sentence in `docs/literate/flex_market.jl` §12 "Assumptions and limitations" (line 665ff).
   - Add one backlog line: a provenance flag on `SettlementInput`.
3. **Shared buses:** both already refuse with an `ArgumentError`. Leave the messages unchanged; no new text is needed.
4. **Behaviour wrappers are not an actor channel.**
   - They are device-level. Traits forward through them (`CapabilityTraits.jl:41-49`), and they satisfy the `contribute!` contract.
   - They clear correctly through `clear_flex_market`; the probe above shows residual 0.0. The B1 trait routing also fixes their certificates: a wrapped V2G EV is routed to the EV certificate.
   - Do not refuse them in `clear_flex_market`. `compare_tariffs` keeps refusing them, unchanged, because of the FIT leg's existing device set (W2 only changes the timing).
   - Optional: a positive regression test that a `PartialCompliance` population clears `ok` with residual 0.0 documents the decision.

### 5. W2: exact locations

- The guard function: `src/pricing/fit.jl:81-97`, called at `fit.jl:121` inside `_fit_pv_and_flex` with caller `"fit_baseline (FIT-OPT)"`.
- In `compare_tariffs` the refusal fires inside the fit leg (`comparison.jl:793-816`, `fit_baseline(...)` at 801). It is an `ArgumentError`, so it is not caught by the solver-outcome `catch` at 811-818 and propagates. That happens **after** the DADP solve (`comparison.jl:439-479`) and the flat/tou price-taker solves (`696-791`).
  - Probe: with a counting `welfare_optimizer`, an EV population and a `PartialCompliance` population were each refused after `n_welfare_solves = 1`.
- The boundary-guard block runs from `comparison.jl:356` (`# ---- boundary guards … BEFORE any solving`) through `436`.
- **Insertion:** after the shared-bus check (`369-374`) and before `flex_markets = _flex_market_list(flex_market)` (`406`):
  ```julia
  for a in aggs
      _reject_unsupported_flex_devices(a.devices, "compare_tariffs (the fit leg runs fit_baseline / FIT-OPT)")
  end
  ```
  The supported set and the error type are the same. Keep `fit.jl:121` as is: it stays reachable from direct `fit_baseline` calls.
- **No output change for supported populations. [VERIFIED: code]**
  - The function is pure. It has no RNG, no model and no mutation, and returns `nothing` unless a device is in `Union{ElectricVehicle, HeatPump, SmartInverterPV, PartialCompliance, OptOut, Rebound}`.
  - Every committed or fenced population (PVBattery / Thermostatic / Deferrable / Interruptible / FixedCapacitor / FourQuadBESS) passes. The fit leg's own check still passes afterwards.
  - The fence items "comparison keywords default unchanged" and "default fence (digests)" confirm it.
- **Message:** include the substring `compare_tariffs`, matching the existing guard-test convention `occursin("compare_tariffs", msg)` at `test_flex_market_fence.jl:411`.
- **Edge case:** `houses` are not checked today either, and the fit leg reads only `aggs`. Keep the check on `aggs` so this is purely a timing change.

### 6. W3: the refusal

- The existing refusal is `_refuse_fixed_capacitor(aggs, who)` (`flex_clear.jl:157-170`). It is called at:
  - `_stage2_aggregators` (`flex_clear.jl:201`);
  - `_flex_physics` (`flex_clear.jl:672`, before stage 1);
  - `compare_tariffs` inside the `flex_market` block (`comparison.jl:435`).
- **STOP on the literal predicate.** The CONTEXT's `has_reactive_decision == true` selects every flexible load (trait table in the Summary). It would refuse:
  - the default IEEE-13/123 houses `[Thermostatic, Deferrable, PVBattery]`, which are the populations of every committed `flex_*` row in `tariff_comparison.csv`;
  - the Interruptible/Thermostatic/Deferrable fixtures of all 18 items in `test_flex_market.jl` and the flex cases in `test_flex_market_fence.jl`;
  - `FailAtCall`, which overrides `is_flexible_load` (`test_flex_market.jl:249-259`).

  Those devices are supported by design: stage 2 drops their `p·tanφ` draw, as `flex_clear.jl:17-25` documents.
- **Refined trait predicate (recommended):**
  ```julia
  _stage2_reactive_decision(d) = has_reactive_decision(d) && !is_flexible_load(d)
  ```
  - Measured true for exactly `FourQuadBESS` and `SmartInverterPV`.
  - False for every flexible load, `PVBattery`, `FixedCapacitor` (refused separately), `ElectricVehicle`, `FlexBidDevice` and all wrappers. Wrappers cannot wrap 4Q/SIPV anyway (`Behavioural.jl:41`).
  - Meaning: "the device has its own reactive decision variable, not the decision-coupled power-factor draw stage 2 already drops".
  - Implement it as a sibling `_refuse_reactive_decision(aggs, who)`, called right after `_refuse_fixed_capacitor` at the same three sites. Leave the FixedCapacitor message unchanged: `test_flex_market_fence.jl:418` asserts `occursin("FixedCapacitor", …)`.
  - The new message names the device type and says that its reactive decision is not represented by the stage-2 bid pseudo-device, which holds reactive at `−Pdc·tanφ`.
- **Committed results and existing tests do not use 4Q/SIPV with the flex market. [VERIFIED: grep + code]**
  - `grep FourQuadBESS|SmartInverterPV|flex_devices` over `test/test_flex_market*.jl`, `test/test_settlement.jl` and `docs/literate/flex_market.jl` finds nothing.
  - `scripts/tariff_comparison.jl` builds `build_population(:default, …)` without `flex_devices`, plus `house(...)` = `[therm, defer, batt]` (around line 955).
  - `FourQuadBESS` is only constructed in `src/experiments/mpc_loop.jl:1115`, an MPC window, not a flex path.
  - Under the refined predicate: **no STOP**. Under the literal predicate: **STOP** (see above).
- **Ordering in `compare_tariffs`.** After W2, `SmartInverterPV` is already refused up front by `_reject_unsupported_flex_devices`, so in `compare_tariffs` the W3 guard only adds `FourQuadBESS` (+ flex_market). `clear_flex_market` and `_flex_physics` have no W2 guard, so W3 covers both types there.

### 7. Validation Architecture: see the section below.

## Architecture Patterns

### Data flow
```
price vector ──► price_taker_dispatch / _deliver
                  │ Model(select_optimizer(QP())) → contribute!(agg) → [types,vars stash]
                  │ solve (assert_solved!, dual=false)
                  └► _storage_certificates(ctx; T, τ_batt, τ_ev)      ◄── NEW shared helper
                        ├─ trait :battery selection → assert_battery_complementarity!  → battery_certificate/message
                        └─ trait :ev ∧ p_dch       → assert_ev_complementarity!(τ=TAU_EV_ADMM) → ev_certificate/message
                  ▼
   record (net, utility, battery_*, ev_*[, shortfall])
        ├─► compare_tariffs: reads battery_certificate only → batt_* columns (EV fields never reach a DataFrame)
        └─► _flex_physics: _dispatch_record → physics.baseline / physics.delivered (+ n_ev_*) → clear_flex_market.physics

public entry ──► guards (before any solve)
   compare_tariffs: actors≠nothing → ArgumentError ; per-agg _reject_unsupported_flex_devices (W2) ; [flex_market] FixedCapacitor + reactive-decision (W3)
   clear_flex_market: actors≠nothing → ArgumentError ; (via _flex_physics) FixedCapacitor + reactive-decision (W3)
```

### Pattern 1: one shared report routine (prevents the B1 divergence recurring)
**What:** Move the battery block out of `price_taker.jl:119-141` and `flex_clear.jl:442-458` into one internal function in `price_taker.jl`, which is included before `flex_clear.jl` (`TSODSO.jl:312, 317`). `_deliver` calls it.

**Example:**
```julia
# price_taker.jl (internal). Report semantics: try/catch CertificateError, never rethrow it, never loosen τ.
function _storage_certificates(ctx::ModelContext; T::Int, τ_batt::Real, τ_ev::Real)
    batt_shape(v) = haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q)
    sel(kind, legacy) = any(
        _stash_entry_has_kind(get(ctx.agg_device_types, bus, nothing), v, i, kind, legacy) &&
        (kind !== :ev || haskey(v, :p_dch))
        for (bus, varlist) in ctx.agg_device_vars for (i, v) in enumerate(varlist)
    )
    battery_certificate, battery_message = _report(sel(:battery, batt_shape)) do
        assert_battery_complementarity!(ctx; τ = τ_batt, T = T, on_violation = :error)
    end
    ev_certificate, ev_message = _report(sel(:ev, _ -> false)) do
        assert_ev_complementarity!(ctx; τ = τ_ev, T = T, on_violation = :error)
    end
    return (; battery_certificate, battery_message, ev_certificate, ev_message)
end
function _report(f, present::Bool)
    present || return (:not_checked, "")
    try
        f()
        return (:ok, "")
    catch err
        err isa CertificateError || rethrow()
        return (:refused, err.msg)
    end
end
```
The `try` lives inside a function, so it is safe for both source and `@testitem` scoping. The names are illustrative; planner discretion.

### Anti-patterns to avoid
- **Shape sniffing for selection:** this is exactly the B1 bug. Always use `_stash_entry_has_kind` with the paired types.
- **Using `TAU_EV` on price-taker solves:** it would refuse 19 of 75 compliant solves (measured).
- **Adding EV columns to `compare_tariffs`:** it breaks the 37-column pin and the `FLEX_EXTRA_COLUMNS` pin for zero information, because EVs are refused there after W2.
- **`has_reactive_decision` alone as the W3 predicate:** it refuses every flexible load (STOP).
- **A typed `actors::Union{Nothing,…}` keyword:** a wrong type would give a `MethodError` again.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Which stash entry is a battery or EV | `haskey(v, :p_ch) && …` | `_stash_entry_has_kind` (`CapabilityTraits.jl:61`) | Pairing overrides shape; hand-built contexts keep the legacy fallback |
| EV co-charge test | a new ratio loop | `assert_ev_complementarity!` | Measured τ provenance, Pmax-over-horizon handling, message text |
| Unsupported-device list for W2 | a new type list | `_reject_unsupported_flex_devices` | The CONTEXT locks "same set, same error type" |
| Proving "before any solve" in tests | timing or log scraping | the counting `welfare_optimizer` factory (`test_flex_market_fence.jl:281-288, 329-333`) or the `FailAtCall` contribute counter (`test_flex_market.jl:249-266`, `fail_at = 0`) | Existing, deterministic patterns |

## Common Pitfalls

### Pitfall A: the literal W3 predicate refuses the default population
**What goes wrong:** every committed flex leg, and 18 flex test items, start throwing `ArgumentError`.
**Avoid:** use `has_reactive_decision(d) && !is_flexible_load(d)`, confirmed with the user.
**Warning sign:** `test_flex_market.jl` "physics pipeline statuses and fields" fails at the guard.

### Pitfall B: `_deliver` key-set pin
**What goes wrong:** `test_flex_market.jl:939-940` fails after the EV fields are added.
**Avoid:** update the pin in the same plan and state it as an additive schema change. Never touch a digest.

### Pitfall C: pinning `res.status` on the negative-price flex fixture
**What goes wrong:** stage 2 on −50 baselines measured `inexact_redispatch`, a solver outcome that can move.
**Avoid:** assert only `physics.baseline.*`, which is computed before stage 2 and is present on every status.

### Pitfall D: asserting `:ok` on the compliant flat-baseline clear
**What goes wrong:** the measured ratio 2.56e-3 is 0.71·τ, a degenerate flat price. Asserting `:ok` there is a fragile test.
**Avoid:**
- For a clean `:ok` pin, use the price-taker at the swing price with the test EV (ratio < 2.2e-4, ≥ 16× margin).
- On the clear, assert `ev_certificate[1] in (:ok, :refused)`, `battery_certificate == [:not_checked]` and that the counts sum to 1.

### Pitfall E: planning-ID hits in new text
**Avoid:**
- Do not write "byte-identical" (it is flagged), `SETL-07`-style IDs with flagged prefixes (`DEV-`, `WR-`), "phase 47", "REQUIREMENTS.md" or "Pitfall N" in src/test/docs.
- Run `python3 .github/scripts/check_planning_ids.py` and require ≤ 355 hits. None of the touched files has allowlist entries, so removing an old hit (for example `price_taker.jl:125` "review WR-03") is safe and creates no stale allowlist entry.

### Pitfall F: `@testitem` soft scope
**Avoid:** put negative-path `try`/`catch` and counters inside functions. The fence file's `refused(g)` / `counting()` helpers are the model.

## Code Examples

### W3 sibling guard
```julia
# flex_clear.jl, next to _refuse_fixed_capacitor (same contract: runs before any solve).
function _refuse_reactive_decision(aggs, who::AbstractString)
    for (k, a) in enumerate(aggs), d in a.devices
        (has_reactive_decision(d) && !is_flexible_load(d)) && throw(
            ArgumentError(
                "$who: aggregator[$k] (bus $(a.bus)) holds a $(nameof(typeof(d))), which has its own " *
                "reactive decision; the stage-2 bid pseudo-device holds reactive power at the " *
                "inelastic −Pdc·tanφ (the flex product is active power only).",
            ),
        )
    end
    return nothing
end
```

### B2 keyword guard (first statement of each function)
```julia
actors === nothing || throw(ArgumentError(
    "compare_tariffs: actors are not supported. Settling profit-seeking aggregator actors " *
    "(Portfolio / ProfitObjective) through the tariff comparison or the flexibility market is " *
    "a recorded scope decision (future work); pass actors = nothing."))
```

### Negative-price test core (price-taker)
```julia
ev = TSODSO.ElectricVehicle(2, 0.9, 1.0, 5.0, 0.0, 40.0, 20.0, 20.0, 10.0, 1.0, 4.0, 9.0, 1, 24;
                            v2g = true, c_deg = 0.01)
r = price_taker_dispatch(Aggregator(2, 0.9, AbstractDevice[ev], zeros(24)), fill(-50.0, 24))
@test r.battery_certificate === :not_checked     # today :ok (the B1 defect)
@test r.ev_certificate === :refused              # measured ratio 0.66 ≫ TAU_EV_ADMM
@test occursin("EV complementarity", r.ev_message)
```

## State of the Art

| Old approach | Current approach | When changed | Impact |
|---|---|---|---|
| Shape-sniffed certificate selection | Trait-routed `storage_kind` over the type-paired stash | v5.0 device refactor | These two `has_battery` sites were missed; this phase completes the migration |

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | The refined W3 predicate `has_reactive_decision && !is_flexible_load` is what the user meant by "SmartInverterPV, FourQuadBESS" | Answer 6 | If the user wants the literal trait, every committed flex leg is refused. **Must confirm** |
| A2 | `_deliver` at a negative price reproduces the `:refused` EV status (not separately probed) | Answer 2 | Low: same build plus the L1 term; the test would reveal it immediately |
| A3 | Documenting the undetectable SettlementInput actor channel, rather than guarding it, is acceptable under "guard only the channels that exist" | Answer 4 | Medium: if the user wants a hard guard, `SettlementInput` needs a provenance field, which is outside the phase's additive scope |
| A4 | Updating the `_deliver` key-set pin (`test_flex_market.jl:939-940`) is not "re-pinning a golden" | Answer 3 | Low: it is a schema assertion, not a digest. Flag it in the plan |
| A5 | `τ_ev` is exposed only on `price_taker_dispatch` / `_deliver`, not threaded through `clear_flex_market` / `compare_tariffs` | Answer 2 | Low: an API-surface choice only; the value is fixed |

## Open Questions

1. **The W3 predicate (blocking).**
   - Known: the literal trait selects every flexible load; the refined trait selects exactly {4Q, SIPV}.
   - Recommendation: the planner adopts the refined predicate and records it as a confirmation item, with a `checkpoint:human-verify` before the W3 task, or asks in the plan-check.
2. **The SettlementInput actor channel.**
   - Known: it is silent today and cannot be detected without a type change.
   - Recommendation: document it in the docstring, docs §12 and the audit, and add one line to the backlog todo (a SettlementInput provenance flag).
3. **Should `_shortfall_diagnostic`'s 10w re-delivery also expose EV status?** It only reads `.shortfall` (`flex_clear.jl:479`). Recommendation: no change. It now runs the EV check but ignores it, which costs nothing.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all code/tests | ✓ | 1.12.5 (`release` channel; 1.12.7 is also installed, but the fence digests assert only on 1.12.5) | — |
| Project env (`--project=.`) | probes/tests | ✓ | instantiated (probes ran) | — |
| Python 3 | planning-ID guard | ✓ | system | — |

No missing dependencies.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test stdlib + TestItemRunner 1.1.5 (`@testitem`, `@testmodule`), runner `test/runtests.jl` with `TSODSO_TEST_SET` / `TSODSO_TEST_FILES` |
| Config file | `test/runtests.jl`, `test/runner_support.jl`, `test/expected_broken.txt` |
| Quick run command | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'`, then `git checkout -- test/Project.toml test/Manifest.toml` |
| Full suite command | Not used in this phase (forbidden for research; the phase gate uses the file set below) |

Measured: `test_flex_market_fence.jl` fast set took **162 s wall**, 86/86 pass, with the digests matching the pin on 1.12.5. Every run carries roughly 2 minutes of load and compile overhead, so batch files with comma-separated `TSODSO_TEST_FILES=a.jl,b.jl`.

### Phase Requirements → Test Map
| Req / item | Behavior | Test type | File (new item unless noted) | Exists? |
|---|---|---|---|---|
| DEV-07 / B1 | price-taker negative-price V2G → `ev_certificate :refused`, battery `:not_checked` | unit | `test/test_settlement.jl` "price-taker: V2G EV certificate …" | ❌ new |
| DEV-07 / B1 | price-taker compliant V2G (swing, test EV) → `:ok`; V1G-only → `:not_checked`; EV-free unchanged; `PVBattery` + V2G → both run independently; wrapped V2G routed to EV | unit | `test/test_settlement.jl` | ❌ new |
| SETL-07 / B1 | `clear_flex_market` with negative hand-built `SettlementInput` → `physics.baseline.ev_certificate == [:refused]`, battery `[:not_checked]`, `n_ev_refused == 1` (no status pin) | integration | `test/test_flex_market.jl` | ❌ new |
| SETL-07 / B1 | `_deliver` at −50 → `:refused`; compliant clear (Interruptible + V2G, swing λ₀) → `status "ok"`, battery `[:not_checked]`, EV in `(:ok, :refused)` | integration | `test/test_flex_market.jl` | ❌ new |
| SETL-07 / B1 | `_deliver` key-set pin updated additively | schema | `test/test_flex_market.jl:939-940` | ✅ edit |
| SETL-07,08 / B2 | `compare_tariffs(...; actors = [Portfolio])` and `clear_flex_market(...; actors = …)` → `ArgumentError` naming the scope, before any solve (counting factory `n == 0` / `FailAtCall` calls 0); explicit `actors = nothing` equals the default | guard | `test/test_flex_market_fence.jl` | ❌ new |
| SETL-07 / B2 (decision doc) | a behaviour-wrapped population clears `ok`, residual 0.0 (wrappers are not refused) | regression | `test/test_flex_market.jl` (optional) | ❌ new |
| SETL-08 / W2 | `compare_tariffs` with EV / HeatPump / SmartInverterPV / wrapper → `ArgumentError` with counting `welfare_optimizer` `n == 0`, message contains `compare_tariffs` + device name | guard | `test/test_flex_market_fence.jl` (extend "welfare_optimizer contract and guards" or a new item) | ❌ new |
| SETL-07 / W3 | `FourQuadBESS` and `SmartInverterPV` refused by `_stage2_aggregators`, `_flex_physics`, `clear_flex_market`, `compare_tariffs(flex_market)` before any solve; Interruptible/Thermostatic/Deferrable/HeatPump **not** refused | guard | `test/test_flex_market.jl` + `test/test_flex_market_fence.jl` | ❌ new |
| Fences | default digests, 37 columns, keyword-default equality, knife-edge canary, committed-CSV invariants | fence | `test_flex_market_fence.jl`, `test_admm_knifeedge_canary.jl`, `test_actor_default_fence.jl`, `test_flex_market_ieee.jl` (fast item "committed comparison CSV rows") | ✅ |

### Sampling Rate
- **Per task commit:** the touched file's fast set:
  - B1: `TSODSO_TEST_FILES=test_settlement.jl,test_flex_market.jl`;
  - guards: `TSODSO_TEST_FILES=test_flex_market_fence.jl,test_flex_market.jl`.
- **Per plan:** `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_settlement.jl,test_flex_market.jl,test_flex_market_fence.jl,test_electricvehicle.jl,test_behaviour.jl`.
- **Phase gate:**
  - the per-plan set plus `test_admm_knifeedge_canary.jl,test_actor_default_fence.jl,test_flex_market_ieee.jl,test_exports.jl,test_device_traits.jl`;
  - `git diff --exit-code -- results/` (committed CSVs unchanged);
  - `git diff --exit-code -- src/admm src/models` (consumed, never modified);
  - `python3 .github/scripts/check_planning_ids.py` ≤ 355;
  - `git checkout -- test/Project.toml test/Manifest.toml` after every run.
- One Julia process at a time, no background runs, nothing IEEE-8500.

### Wave 0 Gaps
None. The framework, fixtures (`FlexMarketFixtures`, `FlexFenceFixtures`, `TwoBusFixtures`) and the before-any-solve harnesses already exist. New items only.

## Security Domain

This is a research library with no network or auth surface. Only input validation applies.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Loud `ArgumentError` guards before any solve (W2, W3, B2). Report-not-throw certificate statuses (B1) |
| V6 Cryptography | no | — |

| Threat pattern | STRIDE | Mitigation |
|---|---|---|
| Silent misreport (a certificate claims a check that never ran) | Repudiation / integrity of results | Trait-routed `has_*` predicates; `:not_checked` when nothing is selected |
| Unsupported combination silently mishandled (q dropped, actors ignored) | Tampering (result integrity) | W3 / B2 guards; documented SettlementInput limitation |

## Sources

### Primary (HIGH confidence; code read at 113d4d4 and Julia 1.12.5 probes, 2026-11-06)
- `src/settlement/price_taker.jl`, `src/coordination/flex_clear.jl`, `src/coordination/flex_settle.jl`, `src/settlement/comparison.jl`, `src/models/welfare_solve.jl`, `src/models/complementarity_ev.jl`, `src/devices/{CapabilityTraits,AbstractDevice,Aggregator,Behavioural,ElectricVehicle,SmartInverterPV}.jl`, `src/actors/{Portfolio,actor_objective}.jl`, `src/settlement/run_inputs.jl`, `src/pricing/fit.jl`, `src/admm/{admm_state,AgrOpt}.jl`, `src/experiments/materialize.jl`, `scripts/tariff_comparison.jl`
- Tests: `test/test_flex_market.jl`, `test/test_flex_market_fence.jl`, `test/test_settlement.jl`, `test/test_electricvehicle.jl`
- Probes (scratchpad, not committed):
  - trait table;
  - B1 reproduction on both paths;
  - 75-solve τ regime measurement;
  - shape-vs-trait equivalence over 15 device and wrapper entries;
  - actor-input silent channel;
  - wrapper clears;
  - W2 refusal timing;
  - fence fast-set baseline run.

### Secondary / Tertiary
- None (no web sources were needed; the phase is internal).

## Metadata

**Confidence breakdown:**
- B1 routing, τ choice and record flow: HIGH (code plus measurement).
- B2 channels: HIGH (probe of every channel); the recommendation for the input channel is a judgment call (A3).
- W2: HIGH.
- W3: HIGH on the facts. The predicate choice needs user confirmation (A1).

**Research date:** 2026-11-06
**Valid until:** 2026-12-06 (internal code; invalidated by any edit to the traits, certificates or flex seams)
