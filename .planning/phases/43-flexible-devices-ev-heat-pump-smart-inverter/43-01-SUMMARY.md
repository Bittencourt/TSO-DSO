---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
plan: 01
subsystem: device-capability-traits
tags: [traits, refactor, devices, admm, certificates, equivalence-gate]
requires:
  - "pre-existing probe sites (DsoOpt.jl _any_flexible_reactive + OFF/CERTIFIED guard, admm_state.jl _react_outputs/_default_reactive_consensus, welfare_solve.jl battery certificate)"
  - "Aggregator.jl:240 device-vars stash"
provides:
  - "has_reactive_decision(d::AbstractDevice)::Bool trait (default = is_flexible_load; @compat public)"
  - "storage_kind trait, type-canonical + instance forwarding (:battery/:four_quadrant/:none; @compat public)"
  - "ModelContext.agg_device_types::Dict{Int,Vector{DataType}} (lockstep device-type provenance)"
  - "_agg_has_reactive_decision / _stash_entry_has_kind shared helpers"
  - "test/test_device_traits.jl classification-equivalence gate"
affects:
  - "43-02 ElectricVehicle (vars can never false-match battery/4Q/consensus classification)"
  - "43-03 HeatPump (is_flexible_load ⇒ has_reactive_decision true by default)"
  - "43-04 SmartInverterPV (sets has_reactive_decision = true)"
  - "AgrOpt battery/4Q check kwargs (unchanged selection semantics via paired types)"
tech-stack:
  added: []
  patterns:
    - "capability trait: docstring + one-line default on AbstractDevice, typed overrides in CapabilityTraits.jl (golden-untouched device files)"
    - "type-paired stash: DataType appended in lockstep with vars; pairing overrides shape, legacy shape fallback for unprovenanced entries"
key-files:
  created:
    - src/devices/CapabilityTraits.jl
    - test/test_device_traits.jl
  modified:
    - src/devices/AbstractDevice.jl
    - src/core/ModelContext.jl
    - src/devices/Aggregator.jl
    - src/admm/DsoOpt.jl
    - src/admm/admm_state.jl
    - src/models/welfare_solve.jl
    - src/TSODSO.jl
decisions:
  - "storage_kind implemented type-canonical (::Type{<:AbstractDevice} defaults, ::Type{<:PVBattery}/::Type{<:FourQuadBESS} overrides) with instance reads forwarding — the DataType stash reads the trait directly and each class has exactly ONE override point"
  - "Aggregator type push placed inside the per-device loop beside push!(device_vars, res.vars) (the vars append! at :240 is post-loop; lockstep per-iteration placement is what guarantees index pairing)"
  - "Pairing rule: paired type decides when provenance exists (length ≥ i); absent/short type lists fall back to the legacy shape predicate per entry — hand-built certificate fixtures unchanged"
metrics:
  duration: "38 min"
  completed: "2026-10-27T01:01Z"
  tasks: 3
  files: 9
---

# Phase 43 Plan 01: Capability-Trait Refactor (Wave 1 correctness gate) Summary

**One-liner:** Device classification moved from isa/shape sniffing to dispatched capability
traits (`has_reactive_decision`, `storage_kind`) with a lockstep device-type stash
(`agg_device_types`), proven behavior-identical on every existing device and fixture by a new
equivalence test suite (56/56), with the full fast suite green (33244 pass) and the canary
bit-exact (iters = 56, welfare = -4823.66604824162).

## What Was Built

- **Traits on the device hierarchy** (`src/devices/AbstractDevice.jl`):
  `has_reactive_decision(d::AbstractDevice)::Bool = is_flexible_load(d)` — the old probe's
  flexible-load half made explicit — and the `storage_kind` trait (`:none` default,
  `:battery` PVBattery, `:four_quadrant` FourQuadBESS, `:ev` reserved for 43-02), type-canonical
  with instance forwarding so the `DataType` stash reads it directly. Docstrings name the
  historical probe each replaces and the EV-safety motivation.
- **Typed overrides for existing devices** (`src/devices/CapabilityTraits.jl`, NEW): one line per
  override, header citing the golden-untouched policy (zero diffs on
  PVBattery/Thermostatic/FourQuadBESS/FixedCapacitor/Deferrable/Interruptible/Scenario) and the
  `is_flexible_load` precedent; plus `_stash_entry_has_kind`, the pairing selector with legacy
  shape fallback.
- **Device-type provenance** (`src/core/ModelContext.jl` + `src/devices/Aggregator.jl`):
  `agg_device_types::Dict{Int,Vector{DataType}}`, empty by default; `Aggregator.contribute!`
  pushes `typeof(d)` in the SAME per-device loop iteration as the vars push (same bus key), so
  index `i` of a bus's type list is the owner of vars entry `i`. Behaviorally inert.
- **Probe-site rewiring, ONE predicate / three consumers** (`src/admm/DsoOpt.jl`):
  `_agg_has_reactive_decision(agg) = hasproperty(agg,:devices) && any(has_reactive_decision,
  agg.devices)` is used by `_any_flexible_reactive` (feeding `build_dso_opt`'s kwarg default and
  `admm_state.jl`'s `_default_reactive_consensus`, which needed no edit) AND the inline
  OFF/CERTIFIED guard copy at the former DsoOpt.jl:326; the guard message names the trait;
  `normalize_reactive_mode` and the normalized-mode comparison untouched.
- **Certificate publish selection trait-routed** (`src/admm/admm_state.jl` `_react_outputs`,
  `src/models/welfare_solve.jl` battery certificate): paired-type `storage_kind` decides when
  provenance exists; absent/short type lists fall back to the legacy var-shape sniffs
  (`haskey(:p_ch)/:p_dch/(!):q`) so hand-built certificate contexts classify exactly as before.
  The `τ·scale²` relative test, `on_violation` validation and `CertificateError(; kind =
  :battery)` are byte-for-byte unchanged. `complementarity_4q.jl` untouched per plan.
- **Wiring** (`src/TSODSO.jl`): `include("devices/CapabilityTraits.jl")` between
  FixedCapacitor.jl and Aggregator.jl; `has_reactive_decision, storage_kind` added to the
  `@compat public` capability block (not exported, `is_flexible_load` precedent).
- **Equivalence test suite** (`test/test_device_traits.jl`, 5 items, 56 tests): per-type truth
  table (explicit assertions, FixedCapacitor A8 named), reactive-default resolution on existing
  fixture populations (LIVE via `mu_q !== nothing` + `reactive_consensus_mode`, OFF via
  `mu_q === nothing`, no explicit kwarg), stash pairing on two real `solve_welfare` runs
  (plain + 4Q fixtures; per-bus lengths, positional `<:` pairing, `storage_kind` off paired
  types), legacy shape fallback (deliberately co-activating battery-shaped hand-built stash
  still throws without provenance; pairing overrides shape when present), and the OFF/CERTIFIED
  guard intact (ArgumentError on explicit OFF, message names the trait, `:live` Symbol still
  rejected).

## TDD Gate Compliance

- RED: `test(43-01): add failing classification-equivalence test suite (RED)` (1546869) —
  suite ran, exit 1: 30 errors (`UndefVarError` on the absent traits), 2 failures (guard
  message, pairing asserts). Natural RED as planned.
- GREEN: `feat(43-01): capability traits + type-paired stash, probe sites rewired (GREEN)`
  (18740ca) — 56/56 green.
- Task 3's gate ran on the GREEN tree (no file changes to commit) and is folded into the GREEN
  commit per the plan's own allowance.

## Verification Evidence

- `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_device_traits.jl julia --project=. -e 'import
  Pkg; Pkg.test()'` → **56/56 pass, exit 0** (after failing 1m22.9s/exit 1 in RED).
- Full fast suite `TSODSO_TEST_SET=fast ... Pkg.test()` → **33244 pass / 6 broken (the
  pre-existing expected_broken.txt records) / 33250 total, exit 0, 15m48s**.
- **Equivalence proof** (by test, not comment): (a) per-type truth table —
  `has_reactive_decision(d) == (d isa FourQuadBESS || is_flexible_load(d))` for all six existing
  device classes, `storage_kind` per class; (b) existing fixtures keep their resolved reactive
  mode — TwoBusFixtures Thermostatic population defaults LIVE (`reactive_consensus_mode ===
  LIVE`, `mu_q !== nothing`), PVBattery-only population defaults OFF (`mu_q === nothing`), both
  solved WITHOUT the explicit kwarg; (c) `_default_reactive_consensus` direct reads agree
  (LIVE/OFF).
- **Canary bit-exact**: `iters = 56`, `welfare = -4823.66604824162` (canary item's own loud
  report in the suite log; pinned assertions pass) — never re-pinned.
- **Golden audit**: `git diff --name-only | grep
  'PVBattery|Thermostatic|FourQuadBESS|FixedCapacitor|Deferrable|Interruptible|Scenario'` → no
  matches (zero diffs on all seven golden files).
- **Soft-scope audit**: `grep -c "soft scope is ambiguous"` over the full-suite log → **0**.
- JuliaFormatter (repo-pinned v2 style, 92-col via `.JuliaFormatter.toml`) run over exactly the
  nine touched files; no golden file touched by formatting.

## Deviations from Plan

**1. [Plan-internal inconsistency] Truth-table `storage_kind` for FourQuadBESS**
- **Found during:** Task 1
- **Issue:** The Task 1 truth-table bullet says `storage_kind(d) === (:battery if d isa
  PVBattery else :none)`, but locked Design decision 2 and the Task 2 action unambiguously
  assign `:four_quadrant` to FourQuadBESS (the `_react_outputs` paired publish selection
  depends on it; `:none` would silently break every LIVE reactive crossval).
- **Fix:** Truth table asserts the design-decision values: PVBattery `:battery`, FourQuadBESS
  `:four_quadrant`, all others `:none`.
- **Files:** test/test_device_traits.jl

**2. [Rule 3 — blocking detail] Fixture-module naming in the reactive-default item**
- **Found during:** Task 1
- **Issue:** The plan's Task 1 says "build the SmallRadialFixtures aggregator set" —
  `SmallRadialFixtures` defines a feeder + profiles only and has no aggregator builder; the
  required probe-true/probe-false populations are `TwoBusFixtures.build_two_bus_aggregators`
  (Thermostatic members ⇒ LIVE) and `build_two_bus_aggregators_no_flex` (PVBattery-only ⇒ OFF).
- **Fix:** Used the TwoBusFixtures builders (the identical populations the plan describes);
  noted in the test file.
- **Files:** test/test_device_traits.jl

**3. [Plan-letter vs intent] Aggregator lockstep push placement**
- **Found during:** Task 2
- **Issue:** The plan's Task 2 action says `push!(get!(ctx.agg_device_types, ...),
  typeof(d))` "immediately beside the Aggregator.jl:240 vars append" — but the vars append at
  :240 is a post-loop `append!` of the whole `device_vars` vector, where a single `push!`
  would store one type per aggregator (breaking pairing).
- **Fix:** Placed the `push!` INSIDE the per-device loop, beside `push!(device_vars, res.vars)`
  — the "same loop iteration, same bus key" lockstep Design decision 3 mandates; index pairing
  proven by the stash-pairing test item.
- **Files:** src/devices/Aggregator.jl

**4. [Rule 1 — bug in new test code] Pairing asserts used `isa` on DataType values; fallback
item pushed a union-all into `Vector{DataType}`**
- **Found during:** Task 2 (GREEN run)
- **Issue:** (a) `types2[1] isa TSODSO.Thermostatic` is always false for a stash entry — the
  stash stores type objects, so `typeof(Thermostatic{Float64}) <: Thermostatic` needs `<:`;
  (b) `FourQuadBESS` (union-all) is not a `DataType` and fails the typed-vector convert.
- **Fix:** `<:` comparisons in the pairing item; fallback item pairs via
  `typeof(bess_instance)` — exactly what Aggregator stores. (Src code was verified correct by
  the same run: type-level `storage_kind` asserts passed.)
- **Files:** test/test_device_traits.jl (fix committed within the GREEN commit)

**5. [Design-mechanics refinement] `storage_kind` dispatch shape**
- **Found during:** Task 2
- **Issue:** Design decision 2 spelled the overrides as instance methods
  (`storage_kind(::PVBattery)`), but the stash stores `DataType`s — instance-only dispatch
  would force the certificates to reconstruct instances (impossible) or duplicate the override.
- **Fix:** Type-canonical generic (`::Type{<:AbstractDevice}` default; `::Type{<:PVBattery}` /
  `::Type{<:FourQuadBESS}` overrides in CapabilityTraits.jl) with instance reads forwarding
  (`storage_kind(d) = storage_kind(typeof(d))`) — one override point per class, instance and
  type reads both public, values and override location exactly per design decision 2. Truth
  table asserts BOTH forms.
- **Files:** src/devices/AbstractDevice.jl, src/devices/CapabilityTraits.jl

## Threat Model Mitigations (from plan)

- **T-43-01-1** (probe-site tampering): mitigated — classification-equivalence test gates every
  rewired site; defaults derive from `is_flexible_load` so drift is caught per-type.
- **T-43-01-2** (battery-selection tampering): mitigated — trait-routed selection with the
  legacy fallback documented in-code and test-verified both ways (fallback selects when
  unprovenanced; pairing overrides shape when provenance exists).
- **T-43-01-3** (fallback repudiation): mitigated — fallback rationale documented at all three
  call sites (`CapabilityTraits.jl` helper + welfare_solve.jl + admm_state.jl); production
  pairing asserted by the stash-pairing item on real solves.
- **T-43-01-SC** (package legitimacy): zero new packages — by construction.

## Known Stubs

None — no placeholder/TODO/stub patterns introduced; every new code path is live and tested.

## Self-Check: PASSED

- [x] `src/devices/CapabilityTraits.jl` exists (new)
- [x] `test/test_device_traits.jl` exists (new, 5 items / 56 tests)
- [x] All 7 modified files present with committed diffs (18740ca)
- [x] Commits verified in git log: 1546869 (RED), 18740ca (GREEN)
- [x] Full fast suite exit 0 (33244/6/33250)
- [x] Canary bit-exact in suite log
- [x] Zero golden-file diffs; zero soft-scope warnings
