# Phase 47: v5.0 Audit Gap Closure - Pattern Map

**Mapped:** 2026-11-06
**Files analyzed:** 12 (5 src, 5 test, 1 docs, 1 planning)
**Analogs found:** 12 / 12. Every new pattern is a sibling of code that already exists in the same file.

Read with the Post-Research Corrections in `47-CONTEXT.md`, which override earlier text:
- W3 predicate is `has_reactive_decision(d) && !is_flexible_load(d)`.
- EV τ is `TAU_EV_ADMM`.
- B2 uses an untyped `actors = nothing` keyword.
- The `SettlementInput` actor channel is documented, not guarded.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/settlement/price_taker.jl` (new `_storage_certificates` helper + `ev_*` fields + `τ_ev` kw) | service (certificate report) | request-response (solve → status record) | same file `:119-141` (battery block) + `src/admm/admm_state.jl:162-168` (τ pairing) + `src/models/complementarity_ev.jl:110-136` (EV selection) | exact |
| `src/coordination/flex_clear.jl` `_deliver` (call shared helper, `τ_ev` kw, new fields) | service | request-response | same file `:442-460` (duplicate battery block) | exact |
| `src/coordination/flex_clear.jl` `_dispatch_record` (+ `ev_certificate`, `ev_message`, `n_ev_*`) | utility (record fold) | transform | same file `:493-504` | exact |
| `src/coordination/flex_clear.jl` new `_refuse_reactive_decision` + 2 call sites | guard | request-response (pre-solve) | same file `:157-170` `_refuse_fixed_capacitor`; calls at `:201`, `:672` | exact |
| `src/coordination/flex_settle.jl` `clear_flex_market` (`actors = nothing` kw guard, docstring limitation) | controller (public entry) | request-response | `src/settlement/comparison.jl:399-405` (`welfare_optimizer` keyword refusal), `:408-413` (`houses` refusal); entry guards `flex_settle.jl:318-328` | role-match |
| `src/settlement/comparison.jl` `compare_tariffs` (`actors` kw guard, W2 per-agg call, W3 call) | controller | request-response | same file boundary block `:356-436` (signature `:338-355`); `src/pricing/fit.jl:81-97` | exact |
| `test/test_settlement.jl` (new price-taker V2G items) | test | — | `test/test_settlement.jl:666-691` (`:not_checked` pin) + `test/test_electricvehicle.jl:404-470` (fixture) | exact |
| `test/test_flex_market.jl` (`_deliver` key pin edit; EV-on-clear items; W3 guard asserts) | test | — | same file `:907-945`, `:745-768`, `:1160-1172`, `:1416-1467` | exact |
| `test/test_flex_market_fence.jl` (B2 `actors`, W2 before-any-solve, W3 in comparison) | test | — | same file `:273-430` (`counting()` / `refused(g)` / `cases` loop) | exact |
| `test/test_electricvehicle.jl` | test (fixture source, read-only) | — | `:404-470` | source of fixture |
| `docs/literate/flex_market.jl` §12 limitations | docs | — | same file `:665-686` bullet list; `:130-139` reactive paragraph | exact |
| `.planning/REQUIREMENTS.md` (SETL-07/08 note + future entry) | config/planning | — | same file `:80-89` (Future), `:138-139` and `:117` (annotated traceability rows) | exact |

## Pattern Assignments

### `src/settlement/price_taker.jl` (service, request-response): B1

**Analog (the block to replace with the shared helper):** `src/settlement/price_taker.jl:119-141`
```julia
    has_battery = any(
        haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q) for
        varlist in values(ctx.agg_device_vars) for v in varlist
    )
    battery_certificate = :not_checked
    battery_message = ""
    if has_battery
        battery_certificate = :ok
        try
            assert_battery_complementarity!(ctx; τ = τ_batt, T = T, on_violation = :error)
        catch err
            err isa CertificateError || rethrow()
            battery_certificate = :refused
            battery_message = err.msg
        end
    end

    return (; net, utility, battery_certificate, battery_message)
```
- **`:not_checked` rule.** The check runs only when the population holds the device class, and selection uses the check's own predicate. Do not test whether the stash is empty. The rationale is in the comment at `:119-125`; that comment contains "review WR-03", a planning-ID hit, and may be removed safely.
- **Signature to extend** (`:83-88`): add `τ_ev::Real = TAU_EV_ADMM` next to `τ_batt::Real = 1e-3`.
- **Docstring to extend** (`:60-77`): the `battery_certificate` / `battery_message` bullets show the wording to mirror for `ev_certificate` / `ev_message`.
- **Header comment** (`:27-34`): add one EV sentence in the same "report semantics / never loosen τ" register. Do not write "Pitfall N".
- `price_taker_dispatches` (`:150-160`) forwards `kwargs...`, so it needs no change. Its docstring says "`kwargs` forward (`T`, `τ_batt`)"; add `τ_ev`.

**Trait selection to copy:** `src/devices/CapabilityTraits.jl:61-72`
```julia
function _stash_entry_has_kind(types::Union{Nothing, Vector{DataType}}, v, i::Int,
                               kind::Symbol, legacy_shape::Function)
    if types !== nothing && length(types) >= i
        return storage_kind(types[i]) === kind
    end
    return legacy_shape(v)
end
```

**EV selection, mirrored exactly for `has_v2g`:** `src/models/complementarity_ev.jl:110-115`
```julia
    for (bus, varlist) in ctx.agg_device_vars
        types = get(ctx.agg_device_types, bus, nothing)
        for (i, v) in enumerate(varlist)
            _stash_entry_has_kind(types, v, i, :ev, _ -> false) || continue
            haskey(v, :p_dch) || continue          # V1G: no discharge leg, compliant by build
```
- The certificate throws `CertificateError(msg; kind = :ev)`, and the message starts `"EV complementarity violated at bus …"` (`:128-135`). Tests match on the substring `"EV complementarity"`.
- Do **not** use the `Float64` return value as a presence signal; decide presence with `has_v2g`. The research covers this in answer 2.

**τ pairing (the rule that picks `TAU_EV_ADMM`):** `src/admm/admm_state.jl:162-168` (repeated at `:198-204`)
```julia
            check_battery = true,
            battery_on_violation = _batt_on_violation(st),
            τ_batt = 1e-3,
            check_ev = true,
            τ_ev = TAU_EV_ADMM,
```
Constants: `TAU_EV = 2e-7` at `complementarity_ev.jl:74` and `TAU_EV_ADMM = 3.6e-3` at `:82`. Reference them by name only and never write the numeric literal.

**Other EV call site (for contrast; do not copy its τ):** `src/models/welfare_solve.jl:326`. The call is `assert_ev_complementarity!(ctx; T = T, on_violation = on_violation)` on the centralized path, which uses the default `TAU_EV`.

**Helper shape:** use RESEARCH "Pattern 1" (`_storage_certificates` + `_report(f, present)`). The `try` sits inside a function body, which is safe for `@testitem` scoping. Define the helper in `price_taker.jl`, which is included before `flex_clear.jl`.

---

### `src/coordination/flex_clear.jl` `_deliver` (service, request-response): B1

**Analog (the duplicated block to delete and replace with a call to the shared helper):** `flex_clear.jl:442-460`
```julia
    # Battery complementarity as a recorded status (the price-taker report semantics).
    has_battery = any(
        haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q) for
        varlist in values(ctx.agg_device_vars) for v in varlist
    )
    ...
    return (; net, utility, battery_certificate, battery_message, shortfall)
```
- **Signature** (`:401-408`): add `τ_ev::Real = TAU_EV_ADMM` after `τ_batt::Real = 1e-3`.
- **Docstring** (`:395-396`): "the battery complementarity certificate is reported (`:ok`, `:refused` or `:not_checked`), never thrown". Extend it to cover the EV certificate.
- **New return order:** `(; net, utility, battery_certificate, battery_message, ev_certificate, ev_message, shortfall)`. This keeps the price-taker fields as a prefix.
- `_shortfall_diagnostic` (`:475-490`) reads only `.shortfall`, so it needs no change.

### `src/coordination/flex_clear.jl` `_dispatch_record` (transform): B1

**Analog:** `flex_clear.jl:493-504`
```julia
function _dispatch_record(ds)
    certs = Symbol[d.battery_certificate for d in ds]
    return (;
        net = Vector{Float64}[d.net for d in ds],
        utility = Float64[d.utility for d in ds],
        battery_certificate = certs,
        battery_message = String[d.battery_message for d in ds],
        n_battery_ok = count(==(:ok), certs),
        n_battery_refused = count(==(:refused), certs),
        n_battery_not_checked = count(==(:not_checked), certs),
    )
end
```
Append, after the existing seven fields:
- `ev_certificate`;
- `ev_message`;
- `n_ev_ok`, `n_ev_refused`, `n_ev_not_checked`, using the same `count(==(…))` idiom.

Consumers read fields by name: `comparison.jl:1100, 1238-1240, 1297` and `test_flex_market.jl:1007-1011`. `physics.baseline` and `physics.delivered` are built here; the baseline call is at `:685` (`baseline = _dispatch_record(stage1)`). That is how `clear_flex_market.physics` carries the status (B1 "status flows" requirement). No `physics` top-level key changes.

---

### `src/coordination/flex_clear.jl` `_refuse_reactive_decision` (guard, pre-solve): W3

**Analog:** `flex_clear.jl:155-170`
```julia
# Internal: refuse a population with a constant reactive injection the pseudo-device cannot
# carry. Runs before any solve.
function _refuse_fixed_capacitor(aggs, who::AbstractString)
    for (k, a) in enumerate(aggs)
        for d in a.devices
            d isa FixedCapacitor && throw(
                ArgumentError(
                    "$who: aggregator[$k] (bus $(a.bus)) holds a FixedCapacitor; its constant " *
                    "reactive injection is not represented by the stage-2 bid pseudo-device " *
                    "(the flex product is active power only).",
                ),
            )
        end
    end
    return nothing
end
```
- **Sibling:** replace `d isa FixedCapacitor` with `has_reactive_decision(d) && !is_flexible_load(d)`, and name the device type with `nameof(typeof(d))`. The full text is in RESEARCH "W3 sibling guard".
- **Call sites:** call it immediately after each `_refuse_fixed_capacitor` call:
  - `flex_clear.jl:201` (`_stage2_aggregators`);
  - `flex_clear.jl:672` (`_flex_physics`, before stage 1);
  - `comparison.jl:435` (inside the `flex_markets !== nothing` block).
- **Docstrings:** extend the `_stage2_aggregators` docstring (`:179`, "…or a `FixedCapacitor` in the population") and the `_flex_physics` docstring (`:629`). Also extend the `compare_tariffs` docstring tail (`comparison.jl:332-333`).
- Leave the FixedCapacitor message unchanged. `test_flex_market_fence.jl:418` matches on `"FixedCapacitor"`.

---

### `src/coordination/flex_settle.jl` `clear_flex_market` (public entry): B2 + docstring limitation

**Current entry guards** (`flex_settle.jl:305-328`):
```julia
function clear_flex_market(
    feeder::AbstractFeeder, pf::AbstractPowerFlow, aggs::AbstractVector{<:Aggregator},
    input::SettlementInput, fm::FlexMarket;
    T::Int, λ₀, bins::Union{Nothing, Vector{Vector{Int}}} = nothing,
    optimizer = nothing, τ_batt::Real = 1e-3,
)
    input.T == T || throw(
        ArgumentError("clear_flex_market: input.T = $(input.T) does not match T = $T."),
    )
```
- Add an untyped `actors = nothing` keyword, and make the throw the **first** statement, before `input.T == T`.
- The message prefix `"clear_flex_market:"` matches the existing test convention `startswith(e.msg, "clear_flex_market:")` at `test_flex_market.jl:1452`.
- **Docstring:** the `Throws ArgumentError…` paragraph is at `:298-303`. Add the `actors` refusal there. Add one sentence near the "Reactive power" paragraph (`:283-285`): an input from an actor-objective run is not detected and its wedges are not carried.
- Leave the `_flex_physics` call (`:329-339`) unchanged. `τ_ev` is not threaded through here (assumption A5).

**Keyword-refusal analog (the closest in-repo `X !== nothing → ArgumentError`):** `src/settlement/comparison.jl:399-405`
```julia
    (engine === :admm && welfare_optimizer !== nothing) && throw(
        ArgumentError(
            "compare_tariffs: welfare_optimizer conditions the centralized SOCP solves (the " *
            "DADP solve under engine = :centralized and each flexibility-market redispatch); " *
            "solve_admm takes no optimizer (use agr_optimizer for ADMM conditioning).",
        ),
    )
```
Also see `comparison.jl:408-413`: `houses === nothing || throw(ArgumentError("compare_tariffs: houses cannot be combined with flex_market — … is not modelled; pass one or the other."))`. It has the same scope-naming shape, "not modelled; pass …".
- **Do not copy:** the typed `actors::Union{Nothing, AbstractVector{Portfolio}} = nothing` at `src/models/welfare_solve.jl:139`. A typed keyword turns a wrong argument type back into a `MethodError`.

---

### `src/settlement/comparison.jl` `compare_tariffs` (public entry): B2 + W2 + W3

**Analog: the boundary-guard block in the same file, `:356-436`.** Signature at `:338-355`; block opener at `:356`:
```julia
    # ---- boundary guards (T-41-19) — BEFORE any solving ---------------------------------
```
- **B2:** add `actors = nothing` to the keyword list (`:343-355`). Throw as the first statement after the block opener, before the `engine in (...)` check at `:357`.
- **W2:** insert the per-aggregator loop after the shared-bus check (`:368-373`) and before `flex_markets = _flex_market_list(flex_market)` (`:406`). The surrounding guard idiom is:
```julia
    length(unique(a.bus for a in aggs)) == length(aggs) || throw(
        ArgumentError(
            "compare_tariffs: aggregators share buses — the ledger requires exactly one aggregator per bus.",
        ),
    )
```
- **W2 callee, unchanged:** `src/pricing/fit.jl:81-97`
```julia
function _reject_unsupported_flex_devices(devices, caller::AbstractString)
    bad = unique(nameof(typeof(d)) for d in devices if d isa Union{
            ElectricVehicle,HeatPump,SmartInverterPV,PartialCompliance,OptOut,Rebound})
    isempty(bad) || throw(ArgumentError(
            "$caller does not support the phase-43 flexible devices / phase-44 behavioural wrappers " * ...
```
  - Pass a `caller` string that contains `compare_tariffs`. The fence tests assert `occursin("compare_tariffs", msg)` (`test_flex_market_fence.jl:411`).
  - Keep `fit.jl:121` unchanged.
- **W3:** at `:435`, add `_refuse_reactive_decision(aggs, "compare_tariffs")` immediately after `_refuse_fixed_capacitor(aggs, "compare_tariffs")`.
- **Docstring:** the guard list is at `:325-333` ("With `flex_market`, these throw `ArgumentError` before any solve: …"). Add the reactive-decision refusal there. Add the `actors` refusal and the up-front device refusal to the general docstring.
- **No column changes:** `_summary_row` (`:141-205`) and `FLEX_EXTRA_COLUMNS` (`:945-980`) stay untouched. The `batt_*` columns read `battery_certificate` at `:682` and `:781`, and that stays as is.

---

### `test/test_settlement.jl` (new price-taker items): B1

**Analog:** `test/test_settlement.jl:666-691`, the thermostatic `:not_checked` pin:
```julia
@testitem "price-taker: thermostatic-only aggregator reports :not_checked (WR-03 pin)" tags =
    [:settlement] begin
    using TSODSO
    ...
    res = price_taker_dispatch(agg, fill(30.0, T))
    @test res.battery_certificate == :not_checked
    @test res.battery_message == ""
end
```
- Also see the item at `:637-664`, which shows the "both outcomes valid" assertion style: `@test res.battery_certificate in (:ok, :refused)`.
- New item titles must not contain planning IDs. The existing title contains "WR-03"; do not copy that.

**Fixture source:** `test/test_electricvehicle.jl:404-470`. The positional V2G constructor is at `:413-430`:
```julia
    T = 24
    Pmax, η = 5.0, 0.9
    ev = TSODSO.ElectricVehicle(2, η, 1.0, Pmax, 0.0, 40.0, 20.0, 20.0, 10.0, 1.0, 4.0, 9.0, 1, 24;
                                v2g = true, c_deg = 0.01)
    ...
    price = fill(-50.0, T)
```
- That item builds a hand-made stash: `ctx.agg_device_types[2] = DataType[typeof(ev)]` at `:436-438`.
- The new tests go through `price_taker_dispatch(Aggregator(2, 0.9, AbstractDevice[ev], zeros(24)), fill(-50.0, 24))`. `Aggregator.contribute!` builds the paired stash itself.
- Assert:
  - `ev_certificate === :refused` (measured ratio 0.66);
  - `battery_certificate === :not_checked`;
  - `occursin("EV complementarity", ev_message)`.
- **V1G `:not_checked` fixture:** `test_electricvehicle.jl:472-504`, the same constructor without `v2g` and with window `1, 4`.
- **Clean `:ok` pin:** use the swing price with the test EV, never a flat baseline (RESEARCH Pitfall D).

---

### `test/test_flex_market.jl`: B1 pin edit, EV on clear, W3 guards

**`_deliver` key-set pin to edit additively:** `test/test_flex_market.jl:938-941`
```julia
        # the delivery result speaks the price-taker vocabulary
        @test keys(c.d1) ==
              (:net, :utility, :battery_certificate, :battery_message, :shortfall)
        @test c.d1.battery_certificate === :not_checked
```
- Change the tuple to `(:net, :utility, :battery_certificate, :battery_message, :ev_certificate, :ev_message, :shortfall)`.
- Add `@test c.d1.ev_certificate === :not_checked` (the tight fixture is an Interruptible).
- This is a schema assertion, not a golden.

**Physics-record certificate assertions (style for `n_ev_*`):** `:1005-1011`
```julia
        @test r.ph.delivered.battery_certificate[1] in (:ok, :refused, :not_checked)
        @test r.ph.baseline.battery_certificate[1] in (:ok, :refused, :not_checked)
        @test r.ph.delivered.n_battery_ok +
              r.ph.delivered.n_battery_refused +
              r.ph.delivered.n_battery_not_checked == 1
```
On the negative-price hand-built `SettlementInput` clear, assert only `res.physics.baseline.*`. Do not pin `res.status`; the measured status is `inexact_redispatch` (Pitfall C). The `SettlementInput` literal is in RESEARCH answer 2. Use `merge(input, (; …))` as at `:1428-1435` if starting from an existing input.

**Error capture helper:** `FlexMarketFixtures.caught` at `:387-395`, used as `M.caught(() -> …)`. It is soft-scope safe.

**FixedCapacitor guard tests (copy for W3 with `FourQuadBESS` / `SmartInverterPV`):**
- `_stage2_aggregators`: `:749-760`
```julia
    cap = Aggregator(2, 0.95,
        AbstractDevice[Interruptible(2, 0.0, 2.0, 6.0, 1.0), FixedCapacitor(2, 0.1)], f.Pdc)
    @test_throws ArgumentError TSODSO._stage2_aggregators([cap], [f.base], [fb]; T = M.T_INT)
```
- `_flex_physics` via `phys`: `:1165-1171` (`@test_throws ArgumentError phys([cap], f.π0)`).
- `clear_flex_market` entry guards and message-prefix asserts: `:1415-1453` (`e_ord`, `startswith(e_ord.msg, "clear_flex_market:")`). Use these for the B2 `actors` test on `clear_flex_market`.

**Before-any-solve proof on the clear: the `FailAtCall` counting dry run.**
- Defined at `:244-268`; `failing_agg(f, 0)` never fails and counts calls.
- Usage at `:1106-1119`: `agg, dev = M.failing_agg(f, fail_at)`, then `dev.calls[]`.
- For B2, assert `dev.calls[] == 0` after the refused call.
- `FailAtCall` overrides `is_flexible_load` (`:259`), so the W3 predicate is false for it. The research confirms this.

**Optional wrapper regression (B2 decision doc).** Use the `M.market_clear(f, input, FlexMarket())` shape at `:1405`, with a `PartialCompliance`-wrapped population. Assert `status == "ok"` and `ledger_residual(...) == 0.0`.

---

### `test/test_flex_market_fence.jl`: B2 / W2 / W3 on `compare_tariffs`

**Analog:** the item "flex market: welfare_optimizer contract and guards", `:273-430`.
- Counting factory (`:281-288`):
```julia
    function counting()
        n = Ref(0)
        factory = function ()
            n[] += 1
            return JuMP.MOI.instantiate(TSODSO.select_optimizer(TSODSO.SOCP()))
        end
        return (; n, factory)
    end
```
- `refused(g)` helper (`:329-333`) and the cases loop (`:407-412`):
```julia
    for (label, g) in cases
        rr = refused(g)
        @test rr.e isa ArgumentError
        @test rr.n == 0
        rr.e isa ArgumentError && @test occursin("compare_tariffs", rr.e.msg)
    end
```
- Reason-specific asserts (`:413-418`), e.g. `e_cap isa ArgumentError && occursin("FixedCapacitor", e_cap.msg)`.
  - W2: add EV, HeatPump, SmartInverterPV and wrapper cases **without** `flex_market`. Today these refuse after one welfare solve; after W2 they must show `n == 0`.
  - W3: add a `FourQuadBESS` case **with** `flex_market`.
  - B2: add `actors = [Portfolio(...)]`.
- Build aggregators like `cap` at `:334-339`: an `Interruptible` plus the device under test. Either add new items or extend this one; keep `try` inside functions (Pitfall F).

**Keyword-default equality style (B2: explicit `actors = nothing` equals the default):** `:303-307`, `r1.summary.welfare[1] == r0.summary.welfare[1]`. Also see the item "comparison keywords default unchanged" at `:244`.

**Existing W2-callee unit tests (no change, for reference):** `test/test_behaviour.jl:335-349` and `test/test_flex_population.jl:268, 284`.

---

### `docs/literate/flex_market.jl` §12 (docs)

**Analog:** `docs/literate/flex_market.jl:665-686`, a bold-lead bullet list:
```julia
# - **Refused baseline battery certificates.** The flat-price baseline that offers are measured
#   from is not battery-exact on either IEEE feeder; the refusals are counted, not repaired
#   (section 8).
...
# - **Inelastic reactive power in stage 2** (section 1).
```
Add bullets in the same form:
- **Actors not settled here.** This is the scope decision. Mention the `actors` refusal and the undetected `SettlementInput`-from-actor-run limitation.
- **Devices with their own reactive decision refused in stage 2.** Name `SmartInverterPV` and `FourQuadBESS`. Cross-reference section 1.
- Optionally, an EV-certificate sentence next to the refused-battery-certificates bullet.

The section 1 reactive paragraph (`:130-139`) ends with the FixedCapacitor refusal sentence. Extend that sentence for W3.

Planning-ID guard: do not write "phase 47", "REQUIREMENTS.md", "byte-identical", or `DEV-`/`WR-` IDs.

---

### `.planning/REQUIREMENTS.md` (planning)

**Future-requirements format** (`:80-89`):
```markdown
## Future Requirements

Deferred; tracked but not in this roadmap.

- **ACTOR-F1**: Tariff-menu (strategic) aggregator choosing its tariff by outer enumeration, labelled a lower bound.
...
- **SETL-F1**: Aggregate-flexibility polytope bids; equity compensation mechanisms.
```
Add the next free ID, e.g. `**SETL-F2**`: actor-aware flexibility market and tariff comparison, meaning wedge lines and flex payments in one ledger with residual 0. A `SettlementInput` provenance flag can go there or in the backlog.

**Annotated traceability-row format** (`:138-139`, and the longer annotation precedent at `:117` POP-04):
```markdown
| SETL-07 | Phase 45 | Complete (plans 45-01..45-07; results/settlement_comparison/tariff_comparison.csv) |
| SETL-08 | Phase 45 | Complete (plans 45-01..45-07; results/settlement_comparison/tariff_comparison.csv) |
```
Append inside the status cell, for example: `; scope: ledger actors = DSO / aggregators / wholesale; profit-seeking actors refused (Phase 47 guard), see SETL-F2`. `.planning/` is outside the planning-ID guard's scan.

## Shared Patterns

### Certificate report semantics (B1)
**Source:** `src/settlement/price_taker.jl:126-139`.
**Apply to:** `price_taker_dispatch` and `_deliver`, through one helper.
1. The status is `:not_checked` unless trait-routed selection finds the device class.
2. If the class is present, call the check with `on_violation = :error`.
3. `catch err; err isa CertificateError || rethrow()`, then record `:refused` + `err.msg`.
4. Never loosen τ.

### Trait routing, not shape sniffing
**Source:** `src/devices/CapabilityTraits.jl:61-72`, with the pairing `get(ctx.agg_device_types, bus, nothing)` + `enumerate(varlist)` (`complementarity_ev.jl:110-112`).
**Apply to:**
- `has_battery`, with legacy shape `p_ch ∧ p_dch ∧ ¬q`;
- `has_v2g`, with legacy `_ -> false` plus `haskey(v, :p_dch)`.

### Loud pre-solve `ArgumentError` guards
**Source:** `src/coordination/flex_clear.jl:157-170`; `src/settlement/comparison.jl:356-436`.
**Apply to:** W2, W3 and B2.
- The message starts with the function name (`"compare_tariffs: …"`, `"clear_flex_market: …"`, `"$who: …"`).
- It names the unsupported combination and gives the reason.
- The guard runs before any `Model(...)` is built.

### Before-any-solve test proof
**Source:**
- `counting()` / `refused(g)` at `test/test_flex_market_fence.jl:281-288, 329-333` (for `compare_tariffs`);
- `FailAtCall` `fail_at = 0` at `test/test_flex_market.jl:244-268` (for `clear_flex_market` / `_flex_physics`).

**Apply to:** every new guard test. Assert `n == 0` / `dev.calls[] == 0` together with `isa ArgumentError` and a message substring.

### `@testitem` soft scope
**Source:** `M.caught` at `test/test_flex_market.jl:387-395`, and the `check(seed)` function wrappers (e.g. `:913-926`).
**Apply to:** every new test with `try` or a loop-carried variable.

## No Analog Found

None. Every pattern is in-file or a direct sibling.

| File | Role | Data Flow | Reason |
|---|---|---|---|
| (none) | | | |

## Metadata

**Analog search scope:**
- `src/settlement/`, `src/coordination/`, `src/models/{welfare_solve,complementarity_ev}.jl`, `src/admm/admm_state.jl`, `src/devices/CapabilityTraits.jl`, `src/pricing/fit.jl`;
- `test/test_{settlement,flex_market,flex_market_fence,electricvehicle,behaviour,flex_population}.jl`;
- `docs/literate/flex_market.jl`;
- `.planning/REQUIREMENTS.md`.

**Files scanned:** 15
**Pattern extraction date:** 2026-11-06 (HEAD 9e9b709)
