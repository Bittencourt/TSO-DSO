# Phase 47: v5.0 Audit Gap Closure - Context

**Gathered:** 2026-11-06
**Status:** Ready for planning
**Source:** `.planning/v5.0-MILESTONE-AUDIT.md` (items B1, B2, W2, W3); the user decided all three questions on 2026-11-06.

<domain>
## Phase Boundary

This phase closes the gaps the v5.0 audit found. It makes two kinds of fix and no new features:

- **Honest certificates** on `price_taker_dispatch` and `clear_flex_market`.
- **Loud refusals** wherever the milestone did not wire a combination.

Out of scope:
- actor support in the flexibility market or tariff comparison (a recorded scope decision, see B2);
- reactive-power support in flex stage 2;
- the other integration-check items W1, W4–W9. These go to backlog todos.

The phase is additive. These stay byte-identical:
- every default path;
- the goldens and digest fences;
- the knife-edge canary (56 iterations / −4823.66604824162);
- every committed results CSV.

No tolerance, τ, ε or hybrid floor changes.

</domain>

<decisions>
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

</decisions>

<code_context>
## Existing Code Insights
- The trait routing: `_stash_entry_has_kind` (`src/devices/CapabilityTraits.jl`) and `storage_kind`.
  Production paths pair `ctx.agg_device_types` with `ctx.agg_device_vars`.
- The EV certificate is `src/models/complementarity_ev.jl`. It is routed by `storage_kind === :ev` and
  wired into `welfare_solve.jl` and `AgrOpt.jl`/`admm_state.jl` (`check_ev`).
- Phase 43 EV tests: `test/test_electricvehicle.jl` has the V2G negative-price co-charge fixture.
- Flex market: `src/coordination/flex_clear.jl` (stage 1/2, the FixedCapacitor refusal) and
  `src/coordination/flex_settle.jl` (`clear_flex_market`, the physics record).
  Its tests are `test/test_flex_market.jl` and `test/test_flex_market_fence.jl`.
- Price taker: `src/settlement/price_taker.jl`; tariff comparison: `src/settlement/comparison.jl`.
  Their tests are `test/test_price_taker*.jl` and `test/test_settlement_*`/`test_compare_tariffs*`;
  the research step resolves the exact file names.

## Established Patterns
- **Honesty policy:** certificates report and never throw in harness/report paths. A refusal is a
  status, and a check that did not run is `:not_checked`, never `:ok` (Phase 45 review WR-03 set this
  exact rule for `has_battery`).
- **Guards** are `ArgumentError`s with a message naming the unsupported combination and why. Each guard
  is tested.
- **Tolerances** are measured, never picked. Goldens are never re-pinned.
- **Planning-ID guard:** new src/test/scripts/docs text adds no planning-ID hits (baseline 355).

</code_context>

<deferred>
## Deferred Ideas
- Actor-aware flex market and tariff comparison: wedge lines and flex payments in one ledger, residual 0.
- Reactive (q) dispatch in flex stage 2.
- Integration-check items W1, W4–W9: backlog todo.
</deferred>

## Post-Research Corrections (2026-11-06)

`47-RESEARCH.md` measured the following. These points supersede the decisions above where they differ. The
user's intent is unchanged: refuse SmartInverterPV and FourQuadBESS in stage 2, and make certificates honest.

- **W3 predicate.** The `has_reactive_decision` trait defaults to `is_flexible_load(d)`, so it is true for
  every flexible load: Interruptible, Thermostatic, Deferrable and HeatPump. The literal trait would
  therefore refuse the default IEEE-13/123 houses and every committed `flex_*` row. Stage 2 drops the
  flexible-load q on purpose.
  - **Decision:** refuse on `has_reactive_decision(d) && !is_flexible_load(d)`. This is still trait-based,
    and it selects exactly SmartInverterPV and FourQuadBESS. Neither appears in any committed result or
    flex test, so there is no STOP.
- **EV τ.** These paths take `τ_batt = 1e-3` from the ADMM final consolidation, and that call site pairs it
  with `TAU_EV_ADMM`. Use `TAU_EV_ADMM`, which is 3.6e-3 and already measured.
  - On 75 compliant price-taker solves the worst ratio was 1.2e-3, so it refused none of them;
    `TAU_EV` would have falsely refused 19.
  - The negative-price fixture gives 0.66, which is 183× the tolerance, so the test asserts `:refused`.
  - Do **not** pin `:ok` on a flat-baseline flex clear, where the ratio is 0.71 of the tolerance.
- **CSV and digest impact:** none. The one test to update is the `_deliver` field-list assertion in
  `test/test_flex_market.jl` around line 939. It is an additive schema check, not a golden.
- **B2 guard:**
  - Add an explicit `actors = nothing` keyword to `compare_tariffs` and `clear_flex_market` that throws an
    `ArgumentError` naming the scope decision. This meets ROADMAP success criterion 2.
  - A `SettlementInput` built from an actor run cannot be told apart from a normal one without changing
    that type, which is out of scope. **Document it as a limitation; do not guard it.**
  - Behaviour wrappers are not an actor channel: they clear `ok` with residual 0.0, so they are not refused.
- **W2:** `_reject_unsupported_flex_devices` is at `src/pricing/fit.jl:81-97`. Call it per aggregator in the
  `comparison.jl` boundary-guard block, between the shared-bus check and `_flex_market_list`.
