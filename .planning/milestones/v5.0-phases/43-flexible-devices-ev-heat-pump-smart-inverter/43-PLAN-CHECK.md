# Phase 43 Plan Check — Goal-Backward Verification

**Checked:** 2026-10-26
**Plans:** 43-01..43-05 (15 tasks)
**Verdict:** **APPROVED** (0 blockers, 1 warning, 3 info)

---

## Verdict

**APPROVED** — the five plans, executed in their declared wave order, will achieve the phase
goal: a researcher can add EVs, heat pumps and smart-inverter PV as convex, binary-free
devices, each validated against the centralized solve before ADMM use. No revision required.

---

## 1. Requirement & Success-Criterion Coverage

| Requirement | Plans (frontmatter) | Producing tasks | Status |
|-------------|---------------------|-----------------|--------|
| DEV-06 (EV V1G, windows-as-bounds, soft target, seeded sessions) | 43-02, 43-05 | 43-02 T1–T3 (device, certificate, gate); 43-05 T1–T2 (hash-seeded per-house sessions, opt-in) | COVERED |
| DEV-07 (V2G c_deg > 0 + certificate, negative-price fixture) | 43-02 | T1 (RED incl. certificate-fires item), T2 (complementarity_ev.jl), T3 (V2G crossval) | COVERED |
| DEV-08 (2R2C, exogenous COP, comfort band, terminal rule) | 43-03 | T1–T3 | COVERED |
| DEV-09 (apparent-power cone, optimal Q, exactness re-measured high-PV, droop post-hoc) | 43-04, 43-05 | 43-04 T1–T3; 43-05 T3 (script + CSV + droop comparator + literate) | COVERED |
| DEV-10 (trait refactor changes no behaviour; centralized-before-ADMM gate) | 43-01, 43-02, 43-03, 43-04 | 43-01 T1–T3; per-device Task 3 crossval gates | COVERED |

All five ROADMAP success criteria map to producing tasks. The DEV-06 "seeded sessions" half
correctly spans 43-02 (device) + 43-05 (seeding); both claim DEV-06. No PROJECT.md requirement
relevant to this phase is dropped; DEV-F1 (droop control loop) is correctly absent (deferred).

**Gate-then-golden ordering (DEV-10b) is enforced structurally:** each device plan's Task 3
lands the centralized-vs-ADMM crossval gate in the same plan that creates the device, and
43-05's population-level ADMM end-to-end item (`depends_on: ["43-04"]`, transitively after all
three gates) explicitly notes "the devices are ADMM-certified by 43-02..43-04 gates." No ADMM
use of any new device class precedes its gate.

## 2. Correctness-Gate Ordering (trait refactor FIRST)

- 43-01 is wave 1, `depends_on: []`; 43-02 `depends_on: ["43-01"]`. The EV cannot land before
  the storage trait.
- The trap is real and correctly neutralized: `welfare_solve.jl:366`
  (`haskey(v,:p_ch) && haskey(v,:p_dch) && !haskey(v,:q)`) would match a V2G EV's vars.
  43-01 rewires the predicate to `storage_kind` routing over a type-paired stash
  (`agg_device_types` appended in lockstep at the `Aggregator.jl:240` site — verified);
  43-02 adds `storage_kind(::ElectricVehicle) = :ev` and its Task 1 asserts the battery
  certificate does NOT throw on the negative-price EV ctx while the EV certificate DOES fire.
- 43-01's classification-equivalence test covers the exact probe sites verified in code:
  `DsoOpt.jl:173` (`_any_flexible_reactive`), `DsoOpt.jl:326` (guard inline copy),
  `admm_state.jl:409` (`_default_reactive_consensus`), `admm_state.jl:439` (`_react_outputs`).
- The `has_reactive_decision = is_flexible_load` default + `FourQuadBESS` override reproduces
  the old probe on every existing type, including the A8 asymmetry — confirmed in code:
  `FixedCapacitor.jl` carries a constant `AffExpr` `q_inject` yet is probe-false today; the
  default keeps it false. Truth-table test pins it per-type (named assertion for FixedCapacitor).
- Guard-message update in 43-01 is safe: all existing `@test_throws ArgumentError build_dso_opt`
  assertions are type-only; none match message text.

## 3. Dependency / Wave Validity

Chain `[] → [43-01] → [43-02] → [43-03] → [43-04]`; waves 1–5 = index + 1; acyclic; no forward
references; fully sequential so no same-wave file conflicts. The cross-plan include-order
contract is consistent: FixedCapacitor → ElectricVehicle (43-02) → HeatPump (43-03) →
SmartInverterPV (43-04) → CapabilityTraits → Aggregator; 43-02 explicitly places the
ElectricVehicle include before CapabilityTraits.jl "which references the type."

## 4. Locked-Decision Fidelity (CONTEXT.md)

| Locked decision | Where delivered | Verified |
|---|---|---|
| No big-M, no binaries anywhere | 43-02/03/04 zero-binary invariants (counted vars + `is_binary`/`is_integer` == 0); windows as zero-upper bounds (`Deferrable.jl:227` idiom verified) | ✓ |
| Thermostatic golden-untouched | 43-03 is a NEW file; 43-01 T3 + 43-03 diff audits; 43-01 T3 audits all 7 golden files | ✓ |
| Scenario schema untouched | 43-05: no-op-default kwarg, `SCENARIO_VALID_POPULATIONS` structural guard, Scenario.jl untouched | ✓ |
| Zero-binary invariants | all three device plans | ✓ |
| Measured-then-pinned tolerances | τ_ev measured (43-02 T2 provenance table); crossval bands pinned at observed maxima (43-02/03/04 T3); "never invented constants" explicit; verdicts only via standard gates (43-05) | ✓ |
| Exogenous COP | 43-03: `COP::Vector`, length ≥ T at contribute!, no Parameter seam | ✓ |
| Terminal kwarg both states | 43-03 joint `Union{Nothing,Real,Symbol}` kwarg (A3), both states T+1 | ✓ |
| SOC cone idiom | 43-04: anonymous per-t `[S_inv, pv_used[t], q[t]] in SecondOrderCone()` — `FourQuadBESS.jl:385` verified in code | ✓ |
| Canary never re-pinned; droop post-hoc only; V1G smaller model; per-house seeding | 43-01/05; 43-04/05; 43-02 (OQ1 adopted); 43-05 (`hash((s_pop,:ev,bus,house_index))`, verified idiom at `materialize.jl:403-404`) | ✓ |

**Scope-reduction scan (7b): clean.** No "v1/stub/simplified/future-enhancement" language.
V1G-without-`p_dch` is research OQ1's recommendation under pre-authorized autonomy (CONTEXT
itself prefers "the smaller model"); exactness-as-script is OQ3, explicitly within CONTEXT
discretion. No deferred idea is implemented (droop is comparator-only; no settlement
remuneration; no combined device; no recalibration — constants documented low-confidence per
the locked decision; no ACTOR coupling).

## 5. Task Atomicity / Verifiability

- 15/15 tasks have files + action + verify + done; all verify blocks are `<automated>`.
- TDD RED→GREEN in every plan, matching the 42-01 precedent. RED verify commands preserve exit
  semantics (`... ; test $? -ne 0`); GREEN/gate commands assert success; 43-05 T3's chain
  (script run → CSV non-empty → CI index → make.jl registration → fast suite) is runnable.
- `TSODSO_TEST_FILES` / `TSODSO_TEST_SET` are real hooks (`test/runner_support.jl:8-37`
  verified), including the dead-file guard that makes the RED runs meaningful.
- files_modified paths are realistic (all anchor files verified to exist; new files land at
  convention-conforming paths). No golden file appears in any plan's file set.
- One coherent-tolerance note: bands pin at observed maxima and structural identities stay
  exact — no equality assertions on solver floats (Pitfall 9 respected).

## 6. Research-Trap Coverage

| Trap | Delivered by |
|---|---|
| Symbol subtraction (`:gap_1e-10`) | 43-05 interfaces block bans Symbol-with-exponent literals; String keys for CSV/Dict rungs |
| Stash-holds-NamedTuples → type-paired stash | 43-01 design decision 3+4 (`agg_device_types::Dict{Int,Vector{DataType}}`, lockstep append, documented legacy fallback for unprovenanced hand-built contexts, stash-pairing test) |
| FixedCapacitor asymmetry | 43-01 truth + named test assertion (A8 confirmed real in `FixedCapacitor.jl:73-75`) |
| Forward-Euler 2R2C stability | 43-03 constructor guards `α_ie+α_ia ≤ 1`, `α_me+α_ma ≤ 1` with physics-reason ArgumentErrors (Pitfall 12) |

Also covered: anonymity/two-instance items (Pitfall 3), `let`-wrapped soft-scope discipline
(Pitfall 10), `expected_broken.txt`/scripts-index/`docs/make.jl` both-sites registration
(Pitfall 5), JuliaFormatter 2.10.2 + no `|`-leading docstrings (Pitfall 13).

## Dimension Summary

| Dimension | Result |
|---|---|
| 1 Requirement coverage | PASS |
| 2 Task completeness | PASS |
| 3 Dependency correctness | PASS |
| 4 Key links planned | PASS (all wiring tasks present; anchor sites verified in code) |
| 5 Scope sanity | PASS (3 tasks/plan; files 9/7/3/3/8 — see info #3) |
| 6 must_haves derivation | PASS (researcher-observable truths, artifacts, key_links) |
| 7 Context compliance | PASS (no contradictions, no deferred scope, 100% decision coverage) |
| 7b Scope reduction | PASS (none) |
| 7c Architectural tier | PASS (certificates in models, traits on device hierarchy, seeding in experiments, measurement in artifacts — matches Responsibility Map) |
| 8 Nyquist | PASS on substance — see warning #1 (8e letter) |
| 9 Cross-plan data contracts | PASS (type-paired stash produced by 43-01, consumed by 43-02; exclusive storage_kind values) |
| 10 AGENTS.md | SKIPPED (no AGENTS.md) |
| 11 Research resolution | PASS in substance — see info #2 |
| 12 Pattern compliance | PASS (every PATTERNS.md file maps to its analog reference in the owning plan; shared patterns embedded) |

## Issues

### Warnings (1)

**W-1 [nyquist_8e] No `43-VALIDATION.md` while `workflow.nyquist_validation: true`.**
- The full validation architecture (test framework, requirements→test map with automated
  commands, sampling rate, Wave-0 gaps) is present in `43-RESEARCH.md §Validation Architecture`,
  and checks 8a–8d pass against it (15/15 automated verify; no watch modes/E2E; every wave 3/3;
  all Wave-0 gaps closed by named tasks: 43-01 T1, 43-02 T1, 43-03 T1, 43-04 T1, 43-05 T3).
- Phase 42 shipped under the same config with the identical structure
  (`42-RESEARCH.md:599`, no `42-VALIDATION.md`), so this is the project's living convention;
  the prescribed remedy ("re-run --research to regenerate") would reproduce the same artifact
  set. Recorded as a convention-drift warning, not a revision requirement.

### Info (3)

**I-1 [research_resolution]** `43-RESEARCH.md §Open Questions` lacks the `(RESOLVED)` suffix,
but all three OQs are resolved by adoption, verifiable in the plans: OQ1 → 43-02 design
decision 1 (V1G omits `p_dch`); OQ2 → 43-03 joint terminal kwarg; OQ3 → 43-05 T3
(script + committed CSV + literate).

**I-2 [task_completeness]** 43-02 T1's negative-price certificate item needs
`ctx.agg_device_vars` populated, which only an aggregator-bearing solve (or a hand-populated
stash à la `test_welfare_solve.jl`) provides — a no-feeder standalone context leaves the stash
empty and the certificate silent. The RED→GREEN loop will force the right route; executor
should use the feeder path.

**I-3 [scope_sanity]** 43-01 touches 9 files — above the 5–8 target but one coherent refactor
(one predicate, three consumers, stash plumbing, its test). No split warranted.

### Blockers (0)

None.

## Codebase Spot-Checks (all claims verified this session)

`DsoOpt.jl:170-176,326`; `admm_state.jl:409,439`; `welfare_solve.jl:285,352-388 (predicate :366)`;
`PVBattery.jl:280,315,326-330`; `Deferrable.jl:144,212,227`; `FourQuadBESS.jl:169,385,406`;
`FixedCapacitor.jl:73-75` (A8 asymmetry real); `AbstractDevice.jl:84`; `ModelContext.jl:63,73`;
`Aggregator.jl:203,216,240`; `materialize.jl:24,403-404,546`; `TSODSO.jl:118-129,336-337`;
`runner_support.jl:8-37` (TEST_SET/TEST_FILES); `AgrOpt.jl:199-200,234-243,325-338`;
`fixtures_four_quad_bess.jl:40-49` (SEED_2BUS convention); `fixtures_ieee13.jl`
(high_pv_feeder/build_high_pv_aggregators); `upsert_sweep_rows` (`benchmark_ieee8500.jl:810`);
`check_scripts_index.py`; `docs/make.jl` registration sites (:19, :92); `ACPowerFlow(; limits=false)`
idiom; type-only guard-message assertions in tests.
