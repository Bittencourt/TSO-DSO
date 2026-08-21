# Phase 25: IEEE-8500 Scale Benchmark - Context

**Gathered:** 2026-08-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Ingest the public IEEE-8500 **balanced load case** OpenDSS feeder (full MV primary + LV secondary)
as a committed, provenance-tracked fixture built by a dependency-free reduction script, then measure
whether the operational ADMM/DADP pipeline holds ~40x above IEEE-123 — the largest fixture shipped
to date. Deliverables: the fixture(s), a fixture-parametrized benchmark harness, a re-certified
exactness gate at this scale, and a live-executed literate page carrying the measured scaling curve.
Requirements: SCALE-01..05.

**Depends on**: nothing in v3.0. Structurally independent of Phase 24 (this phase touches
`src/data/`, `scripts/`, `ext/`, `test/`, `docs/`; Phase 24 touches only `src/planning/`). Consumes
the shipped v1.0 operational core and the IEEE-13/IEEE-123 fixtures as the baselines it scales
*against*.

**Explicitly NOT this phase:** performance *engineering* (deferred as SCALE-STRETCH — this phase
measures and characterizes the wall, optimizing it is separate work), the high-PV DLMP case study at
8500 scale (a pricing story, not a scaling one), and any unbalanced three-phase use of the source
data (standing project scope is balanced positive-sequence; the feeder's own balanced master is used).

**Where the wall is expected:** not raw bus count but **impedance conditioning**. Measured from the
source data, the fixture spans ~9 orders of magnitude in per-unit impedance — 6.4e-9 pu (the 0.001 km
`HVMV_Sub_connector` at `r1=0.001`) up to ~4.08 pu (a CT5 service transformer). `S_base` shifts that
distribution uniformly and therefore **cannot** change the spread; the spread is structural.

</domain>

<decisions>
## Implementation Decisions

### Fixture Set & Population (SCALE-01, SCALE-04)
- **D-01:** The benchmark output is a **curve, not a point** — a **density sweep** over the fraction
  of load buses populated (e.g. 10/25/50/100%), with full density as the top point. This is the only
  way to separate network-size cost from AGR-OPT fan-out cost, which is the attribution SCALE-04/05
  demands.
- **D-02:** An **MV-only control fixture** is included alongside the headline fixture: ~2,519 MV
  buses with each load aggregated onto the MV node it hangs from. Cheap (the reduction script parses
  both levels anyway) and the only way to attribute cost/conditioning specifically to the LV rungs.
  So **two committed fixtures** land: full MV+LV (headline) and MV-only (control). NOT scope
  narrowing — full MV+LV remains the headline.
- **D-03:** Load magnitudes come from the **real per-load kW in `Loads.dss`** (pf 0.97), used as the
  per-bus magnitude and shaped by the existing seeded profile machinery. This deliberately does NOT
  follow the `_IEEE13_LOAD_SCALE` / `_IEEE123_LOAD_SCALE` tuned-constant precedent
  (`src/experiments/materialize.jl:121-129`) — real magnitudes are available, so no magic constant is
  invented.
- **D-04:** The **3-device house stays fixed** (Thermostatic + Deferrable + PVBattery, as
  `_default_house` builds today). Comparability with the IEEE-13/123 runs beats another axis, and a
  device-count axis on top of a density sweep is combinatorial.

### Per-Unit Ingestion & Magnitudes (SCALE-02)
- **D-05:** **`S_base` = 1 MVA**, matching IEEE-13/123. Verified against source data: worst case is a
  CT5 unit at r=3.60 / x=4.08 pu — inside `IMPEDANCE_PU_MAX = 5.0` at 82% of the limit, and only
  **8 of 1,177** service transformers are CT5 (modal are CT15 x382 at 41% and CT25 x486 at 25%).
  10 MVA would trip the band 8x; 0.1 MVA is comfortable at 8% but breaks cross-fixture pu
  comparability and inflates every `smax` 10x (head branch 27.5 -> 275 pu, blowing
  `SMAX_PU_MAX = 100`). **The tripwire is cleared honestly — not widened.**
- **D-06:** **Every branch is kept.** The ~9-order impedance spread is REPORTED as a measured
  property of the fixture, not engineered away. A degenerate-stub-merged variant is a **data-driven
  follow-up** only if the measurement shows conditioning is the wall — mitigation up front would
  pre-empt the finding the phase exists to produce.
- **D-07:** **Per-voltage-level bands.** MV keeps the 0.9-1.1 IEEE-123 convention; LV service points
  get the **0.88 floor that `Loads.dss` itself declares** (`Vminpu=.88`). A uniform MV band applied at
  1,177 LV buses fed through real service-transformer impedance risks manufacturing infeasibility that
  would kill the benchmark before it measures anything.
- **D-08:** **Head-only thermal limit** — 27.5 MVA substation rating (from `Transformers.dss`) on the
  head branch, `SMAX_NO_LIMIT` on the interior, exactly the IEEE-123 precedent. Real per-segment
  ampacity from linecode `normamps` is rejected for this phase: thousands of potentially binding
  thermal constraints would be a congestion study wearing a benchmark's clothes.
- **D-09:** Multi-voltage-base ingestion needs **no core struct change** — `Feeder`/`Branch` store
  per-unit only, so ingestion picks the right `PerUnitBase` per voltage level (12.47 kV MV,
  0.208/0.12 kV LV) and converts ONCE at ingestion via `to_pu_impedance`, never inside the reduction
  script (the IEEE-123 rule).

### Capacitor Banks & Non-Modeled Devices (SCALE-03)
- **D-10:** The 4 capacitor banks (3x300 + 3x400 + 900 kvar = **3.9 MVAr**) are modeled as a
  **fixed-Q, q-only device via the existing `q_inject` seam** — Phase 19's MESH-04/D-09 optional
  device reactive injection, which `Aggregator` already sums into `:Rq`. **No core model change**;
  no new shunt support is added (that would be scope creep into the device model). Chosen over
  omission because it is nearly free and keeps 3.9 MVAr of real voltage support on a feeder whose LV
  floor is 0.88.
- **D-11:** **CapControl switching is out of scope** — banks are always-on at nameplate, one
  documented assumption. This follows the standing project stance from the OVR axis ("no literal
  IEEE-1547 Volt-VAR droop controller — the SOCP subsumes it"): a switched-capacitor control law is a
  decentralized heuristic controller and has no place in an optimization-first framework.
- **D-12:** All 4 cap buses (`R20185`, `R42247`, `R42246`, `R18242`) are MV terminals verified to
  carry **no load**, so they would be transit/zero-injection nodes. They are **promoted to load buses
  with zero inelastic demand** (`Pdc = 0`), each hosting a q-only Aggregator. This preserves the
  DEV-05 invariant that **the Aggregator is the SOLE `:Rp`/`:Rq` writer** — load-bearing architecture
  that must not be bent for 4 buses. Extending the transit-node relaxation to inject constant q is
  REJECTED for adding a second `:Rq` writer.
- **D-13:** Regulators and switch segments keep the existing IEEE-123 near-ideal low-impedance
  treatment (Assumption A2, `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` analog). Tap changing is not
  modeled.

### Benchmark Harness, CI & Evidence (SCALE-04, SCALE-05)
- **D-14:** The harness is a **fixture-parametrized script in `scripts/`**, taking a fixture symbol
  and running across `ieee13` / `ieee123` / `ieee8500-mv` / `ieee8500` so the output is a cross-fixture
  curve. Follows the `socp_applicability_sweep.jl` / `repro_stability_check.jl` precedent. NOT an
  exported `src/` module — measuring is not a framework capability, and every `src/` addition carries
  the full test/Aqua/JET burden.
- **D-15:** **CI carries perf-regression goldens** — USER CHOICE, overriding the recommended
  smoke-test-only option. To keep them non-flaky (D-16) they pin **deterministic quantities only**.
- **D-16:** Goldens pin **ADMM iteration counts, model dimensions (variable/constraint counts), and
  solver termination status** — all machine-independent, so a regression is a real regression. **Wall
  time is recorded in the results table but NOT asserted.** Chosen over wall-time bands because bands
  loose enough not to flake on shared runners are also loose enough to miss real regressions, and the
  milestone already carries quarantined-flaky-test debt.
- **D-17:** The literate page is **fully live-executed at docs build** — USER CHOICE, overriding the
  recommended committed-artifact route. Bounded by D-18 rather than by reducing the grid.
- **D-18:** Every sweep point is attempted live with a **per-point wall-clock timeout**; a point
  exceeding the documented cap records a **"budget exceeded" row** instead of hanging the build. This
  keeps the page genuinely fully live-executed AND bounds the docs build — and a timeout row is itself
  an honest scaling finding, not a failure. **Open risk stated plainly:** total docs-build time is
  unknown up front because runtime at this scale is exactly what the phase measures; D-18 is the guard
  that makes an unbounded choice safe.
- **D-19:** Metrics recorded per point: wall time **split into JuMP model assembly vs solver time**,
  ADMM iteration count, peak memory, solver termination status, the per-fixture cone-gap noise floor,
  and the exactness verdict. The build/solve split is what attributes cost to assembly vs solver — the
  phase's central attribution question. Termination status is explicit because **Clarabel
  NUMERICAL_ERROR is known standing debt** (see the v2.x milestone audits).

### Solver Comparison (SCALE-04)
- **D-20:** **SCS is NOT currently a dependency** (verified in `Project.toml`), so it arrives as a
  **weakdep + `ext/TSODSOSCSExt.jl`**, following the existing `ext/TSODSOGurobiExt.jl` /
  `TSODSOMosekExt.jl` precedent and routing through the existing `select_optimizer` factory. This
  preserves the milestone's zero-new-**hard**-runtime-package property and keeps SCS removable. A hard
  `[deps]` entry is REJECTED.
- **D-21:** The comparison includes a **measured DADP-drift diagnostic** — how far SCS's DADPs and
  cone residuals drift from Clarabel's, alongside wall time and convergence. Cheap once both solvers
  run, and it converts the project's standing "never certify prices or exactness on SCS" policy from
  an assertion into evidence. Scoped as a **diagnostic column, not a price-quality study.**

### Claude's Discretion
- **ADMM iteration cap and non-convergence policy** at 1,177 aggregators. Bounded by the standing
  carry-forward that an honest non-convergence result IS a valid deliverable (Phase 23 D-10) and by
  D-18's timeout; the specific cap is Claude's.
- **The cone-gap noise-floor calibration ladder** — how the per-feeder floor is measured at ~4,900
  branches (the spike-002 method: re-solve a benign point across a tolerance ladder) and how the
  calibrated floor feeds `assert_socp_exact!`'s `atol`/`rtol`, including whether the floor is committed
  as fixture metadata.
- **The density-sweep grid points** (10/25/50/100% is illustrative, not locked) and the per-point
  timeout value in D-18.
- **All module/struct/function/kwarg/fixture-symbol names**, including the reduction script name, the
  generated impedance-table filename, and the q-only capacitor device type name.
- Whether the MV-only control fixture is a separate committed builder or a documented reduction mode
  of the same builder.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/ROADMAP.md` § "Phase 25: IEEE-8500 Scale Benchmark" — goal, dependencies, the 5 success
  criteria, and the SCALE-STRETCH deferral note.
- `.planning/REQUIREMENTS.md` § "IEEE-8500 Scale Benchmark (`SCALE`)" — SCALE-01..05 verbatim.
- `.planning/STATE.md` § "Roadmap Evolution" — the scoping already done at phase-add time. **Do not
  re-derive the source-data fetch or the record counts.**

### Source data provenance (SCALE-01)
- `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` — verified raw URL base,
  fetch date, sha256s, per-file record counts, and the `LoadXfmrCodes.dss` vs `LoadXfmrs.dss` redirect
  subtlety (the balanced master's secondaries ARE connected; do not conclude otherwise).

### Ingestion pattern to follow (SCALE-01, SCALE-02)
- `scripts/reduce_ieee123_impedances.jl` — **the pattern to copy**: zero `using` statements, Base +
  PCRE regex only so `Project.toml [deps]` is untouched; topology read as plain text and never
  re-derived; pinned sanity value; `--verify` self-check mode; emits a committed generated Julia table.
- `src/data/ieee123.jl` — fixture shape, the DATA PROVENANCE / transcription-note header convention,
  the IN-02 naming caveat ("123-node" is lineage, not a bus count — same caveat applies to
  "8500-node"), the load/transit split via `ieee123_load_nodes`, and the Ω→pu-once-at-ingestion rule.
- `src/data/ieee123_impedances.jl` — the generated-table format the reduction script emits.
- `src/data/Feeder.jl` — `Bus`/`Branch`/`Feeder`; validation is a construction invariant
  (`assert_radial` + `assert_magnitudes` in the inner constructor), structs are immutable and store
  **per-unit only** (this is why D-09 needs no core change).
- `src/units/PerUnit.jl` — `to_pu_impedance`, `PerUnitBase`, and the tripwire constants:
  `IMPEDANCE_PU_MAX = 5.0` (:58), `SMAX_PU_MAX = 100.0` (:59), `SMAX_NO_LIMIT = 99.0` (:73),
  `VOLTAGE_PU_MIN/MAX` (:56-57).

### Exactness gate & the noise-floor prerequisite (SCALE-05)
- `.planning/spikes/MANIFEST.md` — **load-bearing.** Spike 002's method defect: `assert_socp_exact!`'s
  default `atol = 1e-6` sits AT Clarabel's cone-residual noise floor on a 122-branch feeder, flagging
  48% of points inexact by noise alone. Per-feeder noise-floor calibration is therefore a HARD
  PREREQUISITE before any exactness claim at ~4,900 branches. Also: scale-free WR-01
  `atol + rtol·magnitude` classification only (never a bare absolute threshold); never generalize a
  boundary finding from one substrate; report fixture-relative axes as fixture-relative.
- `src/models/exactness.jl:23` — `assert_socp_exact!(ctx; rtol=1e-4, atol=1e-6)`, the gate whose
  tolerances must be re-derived at this scale, never reused.
- `.planning/notes/socp-validity-envelope.md` — retained design decisions behind the validity-envelope
  work.

### Population, devices & the reactive seam (SCALE-03, SCALE-04)
- `src/experiments/materialize.jl` — `build_feeder(sym)` fixture registry (:35), the per-fixture
  load/pv/dev scale constants (:121-129) that D-03 deliberately departs from, `_load_buses` (:181),
  `_default_house` (:200), `build_population` (:263).
- `src/devices/AbstractDevice.jl` — the device contract, including the OPTIONAL `q_inject` reactive
  seam (:69-75) that D-10 reuses.
- `src/devices/Aggregator.jl` — the DEV-05 sole-`:Rp`/`:Rq`-writer invariant (:118-130) that D-12
  preserves; `Σ_d q_inject_d[t]` roll-up (:186).
- `src/devices/FourQuadBESS.jl` — today's only `q_inject` implementor; the reference shape for the
  q-only capacitor device.

### Solver factory & extension pattern (SCALE-04, D-20)
- `ext/TSODSOGurobiExt.jl`, `ext/TSODSOMosekExt.jl` — the weakdep extension precedent for
  `ext/TSODSOSCSExt.jl`.
- `Project.toml` — confirms SCS absent from `[deps]`; `[weakdeps]` is where it lands.
- `src/solver/` — the `select_optimizer` factory / `ProblemClass` dispatch every solver must route
  through; no model may name a solver.

### Timing & results precedent (SCALE-04)
- `src/planning/benders.jl:204-269` and `src/planning/trace.jl:77` — the established **monotonic
  `time_ns`** timing idiom (deliberately immune to NTP steps). Note BenchmarkTools is NOT a dependency
  and is not required.
- `src/experiments/run.jl:53,91` — the `elapsed` / `@elapsed` convention.
- `src/experiments/store.jl` — DrWatson result storage (`tagsave` stamps git commit + Manifest).

### Prior-phase patterns that constrain this phase
- `.planning/phases/23-meshed-networks/23-CONTEXT.md` — D-01 (new type alongside, existing paths
  byte-untouched), D-08 (tolerances measured at the fixture's own scale, NEVER reused — the Phase-19
  CR-01 lesson), D-09 (CI regression proving existing behavior unchanged), D-10 (honest-gap outcome IS
  a valid deliverable).
- `.planning/phases/22-stochastic-pv-demand-uncertainty/22-CONTEXT.md` — D-11 (measurement-before-golden,
  locked), D-12 (small CI fixture; heavy demonstrations quarantined or in the literate page, not CI).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/reduce_ieee123_impedances.jl` — the whole dependency-free OpenDSS-parse → Fortescue-reduce
  → emit-committed-table machinery, including `parse_lower_triangular`, `fortescue_reduce`, and the
  phase-suffix-stripping `parse_terminal`. The 8500 linecodes are the same Ohm-matrix form
  (`LineCodes2.DSS`, `Units=km`), so the reduction method transfers directly.
- The optional `q_inject` device seam (`src/devices/AbstractDevice.jl:69-75`) — makes D-10's capacitor
  device nearly free. Built by Phase 19 for 4Q-BESS; this is its second consumer.
- Monotonic `time_ns` timing idiom (`src/planning/benders.jl`, `src/planning/trace.jl`) — no
  BenchmarkTools dependency needed for D-19's metrics.
- DrWatson `tagsave` result storage (`src/experiments/store.jl`) for the recorded results table.
- The DSO-OPT transit-node (zero-injection) relaxation — essential here: with 2,519 MV terminals and
  only 1,177 load buses, **the great majority of MV buses are transit nodes**, a far higher ratio than
  IEEE-123's ~37/123.

### Established Patterns
- **Per-unit only inside `Feeder`; SI→pu converted ONCE at ingestion** — the reason multi-voltage-base
  works without a core change (D-09).
- **Validation as a construction invariant** — `assert_radial` + `assert_magnitudes` run in the inner
  constructor, so an invalid feeder cannot exist. At ~4,873 buses these run on every fixture build;
  `assert_radial` must scale (tree check on ~4.9k nodes/edges).
- **Fixture symbol registry** — `build_feeder(sym)` dispatch is the single seam new fixtures plug into.
- **Certificates get NEW tolerances measured at their own scale** — never reused (the standing
  anti-certificate-laundering rule).
- **Solver never named inside a model** — everything through the `select_optimizer` factory.

### Integration Points
- `src/data/` — two new fixture builders (full MV+LV, MV-only control) + one generated impedance table,
  wired into the `src/TSODSO.jl` include graph after `ieee123.jl`.
- `src/experiments/materialize.jl` — `build_feeder` registry entries, `_load_buses` branch for the new
  fixtures, and the D-03 real-kW population path.
- `ext/TSODSOSCSExt.jl` + `Project.toml [weakdeps]` — new solver extension.
- `scripts/` — reduction script + benchmark harness.
- `docs/literate/` — the live-executed scaling page.
- `test/` — fixture invariant tests + D-16 deterministic goldens.

### Risks Surfaced During Scouting
- **~9 orders of per-unit impedance spread** (6.4e-9 → 4.08 pu) — the suspected conditioning wall, and
  NOT fixable by `S_base` (which shifts uniformly). This is the phase's central technical risk.
- **Docs-build runtime is unbounded a priori** (D-17), guarded only by D-18's per-point timeout.
- **`assert_radial` at ~4.9k buses** — previously exercised at 123; worth confirming it is not
  accidentally quadratic.
- **Clarabel NUMERICAL_ERROR** is pre-existing standing debt and a plausible failure mode at this
  scale; D-19 records termination status explicitly so it shows up as data rather than a mystery.

</code_context>

<specifics>
## Specific Ideas

- The fixture is built from the feeder's **own balanced load case** (`Master.dss`), not a
  balanced reduction of the unbalanced case — this is why the phase is compatible with the standing
  balanced-positive-sequence scope. `Master-unbal.dss` + `UnbalancedLoads.DSS` are out of scope.
- Expected post-collapse size: **2,519 MV terminals + 1,177 `X*` + 1,177 `SX*` ≈ 4,873 buses**. State
  the measured count in the fixture docstring; carry the IN-02 caveat that "8500-node" counts
  per-phase nodes, not buses.
- Source-data topology chain to preserve: MV `L*` → center-tap service transformer → `X*` LV → triplex
  → `SX*` load bus.
- Service-transformer population is 9 XfmrCode sizes: CT15 x382, CT25 x486, CT37 x117, CT10 x112,
  CT50 x48, CT75 x20, CT5 x8, CT250 x3, CT100 x1 — all at `Xhl=2.04%`, `%Rs=[0.6 1.2 1.2]`.
- The 3-winding center-tap transformer must be reduced to a **single equivalent series impedance** for
  the balanced positive-sequence single-phase equivalent; state the reduction explicitly (the
  `%Rs[1] + %Rs[2]` series treatment used for the D-05 numbers is a starting point, not a locked
  derivation — research should confirm it).
- `Master.dss` redirects `LineCodes2.DSS`, **not** `LineCodes.dss`. Using the wrong one silently
  yields wrong impedances.
- Still to fetch when vendoring: `Triplex_Linecodes.dss` (required for the LV rung) and optionally
  `Buscoords.dss` for figures.
- `25-DATA-PROVENANCE.md` pins the `master` git ref, not a commit SHA — **pin a commit SHA when
  vendoring.**

</specifics>

<deferred>
## Deferred Ideas

- **SCALE-STRETCH — performance engineering** (`direct_model` on hot subproblems, sparse-aware model
  assembly, parallel per-node AGR-OPT solves, impedance rescaling/preconditioning). Already recorded
  in ROADMAP.md and REQUIREMENTS.md. This phase measures and characterizes the wall; optimizing it must
  not be entangled with the benchmark that justifies it.
- **High-PV DLMP case study at 8500 scale** — the pricing/physics story (DLMP spatial spread,
  congestion structure on a realistic feeder). A natural follow-on; explicitly not this phase.
- **Degenerate-stub-merged fixture variant** — only if the measurement shows conditioning is the wall
  (D-06). Data-driven follow-up, not planned up front.
- **Device-count axis** on top of the density sweep (D-04) — a 2-D cost surface. Cheap to add later
  once the 1-D curve exists.
- **Real per-segment ampacity limits** from linecode `normamps` (D-08) — would turn the fixture into a
  congestion study; belongs to a pricing/congestion phase, not a scaling one.
- **CapControl switched-capacitor behavior** and regulator tap changing (D-11, D-13) — decentralized
  control laws, against the standing optimization-first stance.
- **Unbalanced three-phase use of the 8500 source data** — permanently out of standing project scope,
  though the source files support it.
- **Unpackaged spikes** — `.planning/spikes/MANIFEST.md` exists with no findings skill. Running
  `/gsd:spike --wrap-up` would make spike 002's noise-floor lesson available as a discoverable skill
  rather than a manual read. Housekeeping, not phase work.

</deferred>

---

*Phase: 25-IEEE-8500 Scale Benchmark*
*Context gathered: 2026-08-20*
