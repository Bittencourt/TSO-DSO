# Phase 19: 4Q-BESS + Live Reactive Dual-Ascent - Context

**Gathered:** 2026-08-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Two deliverables, both flag-gated so the default path stays byte-identical (roadmap success
criterion 4):

1. **`FourQuadBESS` device** (MESH-04): a battery with sign-free active and reactive decision
   variables inside an inverter apparent-power cone `p² + q² ≤ S²max`, flowing
   device → Aggregator → `:Rq` residual, with the no-binaries complementarity property
   re-derived for the 4Q case AND hard-checked post-solve — never silently inherited from
   `PVBattery`.
2. **Live reactive μ-dual-ascent** (MESH-05): the v2.1 one-shot certified reactive-dual
   scaffolding (`reactive_consensus`/`qag_dso`) promoted to a live, converging μ-ascent step on
   `:balance_q` inside `solve_admm`, converging on a fixture with a `FourQuadBESS` present,
   cross-validated against the centralized solve, under its own two-block convergence/stopping
   treatment (NOT the single-block Boyd rule as-is).

Out of scope: meshed topology/formulation/certificate (Phase 23, MESH-01/02/03), the combined
literate rung page (Phase 23, MESH-06), any Volt-VAR droop controller (explicit anti-feature).

</domain>

<decisions>
## Implementation Decisions

### 4Q-BESS device semantics
- **D-01:** `FourQuadBESS` is a **standalone battery + 4Q inverter** — no PV field. PV-owning
  prosumers keep using `PVBattery` alongside it. Keeps the new-device pattern (the one Phase 23
  references) clean of PV-curtailment/cone interactions.
- **D-02:** **Grid charging, capped**: net active power is sign-free (the battery may import),
  but with an explicit charge-rate cap separate from discharge — asymmetric bounds
  (`Pch_max` ≠ `Pdch_max` permitted). Assumption A6 (charge-from-PV-only) is documented as
  `PVBattery`-specific, deliberately not inherited.
- **D-03:** **q is free inside the cone** — no cost/utility term on reactive power in the device
  objective. Its "price" is purely the reactive nodal dual μ (cleanest transactive story).
  Consequence the planner must honor: when μ ≈ 0, q can be non-unique/degenerate — the
  cross-validation compares **welfare and prices, not q trajectories**.
- **D-04:** Internal structure keeps the **`p_ch`/`p_dch` ≥ 0 split with net injection
  `p = p_dch − p_ch`** entering the cone — the only convex way to model round-trip efficiency
  η < 1 in the SOC recursion (mirrors `PVBattery`'s eq. 3.6 pattern). This makes the
  complementarity question genuinely live (see below).

### Complementarity guarantee (MESH-04's second clause)
- **D-05:** **Both routes**: re-derive the conditions under which `p_ch·p_dch = 0` holds at the
  optimum for the 4Q grid-charging case (the App. C argument does NOT transfer — grid charging +
  negative nodal prices can make simultaneous charge/discharge, i.e. deliberate energy burning
  through η² < 1, genuinely optimal), document the derivation beside the code, AND run the hard
  post-solve numeric check on every solve regardless.
- **D-06:** **Throw by default, kwarg to report**: the check throws on violation, with a
  documented kwarg (mirroring `assert_socp_exact!`'s `rtol_exact` diagnostic-neutralization
  pattern) letting research runs observe violations without modifying `src/`.
- **D-07:** The check is a **new named, exported certificate function** — a peer of
  `assert_socp_exact!`/`assert_ac_exact!` — with its **own tolerance** in the WR-01 scale-free
  idiom (`atol + rtol·magnitude`), calibrated against the solver noise floor. Never a reused
  tolerance (v3.0 standing bar). Reusable by Phase 23.
- **D-08:** If the derivation shows violations are genuinely possible in-scope (e.g.
  negative-price regimes): **honest finding + documented boundary** — characterize the violating
  regime as a first-class finding, let the certificate throw there. No constructor parameter
  restrictions beyond what the derivation justifies.

### Aggregator contract widening
- **D-09:** Devices hand reactive power to the Aggregator via an **optional `q_inject` field** in
  the aggregatable-device return contract: `(; vars, p_inject, q_inject, utility)`, where a
  device that omits `q_inject` contributes zero reactive. **Existing devices stay untouched**
  (absent = zero). This is the "widened Aggregator contract" pattern Phase 23 references.
- **D-10:** `:Rq` composition is **purely additive on top of untouched code**:
  `:Rq = −Pdc·tanφ + Σ device q_inject`. The existing inelastic power-factor term is not
  refactored, so byte-identity with no 4Q device present falls out structurally.
- **D-11:** **μ and device q are first-class result outputs, peers of λ**: reactive
  price-per-bus-per-hour and 4Q device q trajectories land in the same results/DataFrame surface
  the active DADPs use today. The live reactive price is this phase's headline product.

### Live μ-ascent config & validation
- **D-12:** **Promote `reactive_consensus` to a 3-state mode** (e.g. `:off | :certified | :live`)
  with `Bool` still accepted for back-compat (`false → :off`, `true → :certified`). One knob for
  three points on one axis; no invalid two-Bool combinations to police. Default remains off /
  byte-identical; existing v2.1 tests must pass unmodified via the back-compat mapping.
- **D-13:** **Small radial fixture is the primary CI-gated evidence** for μ-ascent convergence +
  cross-validation (with a `FourQuadBESS` present); IEEE-13 runs as supporting evidence under the
  existing bounded-retry quarantine (quick task 260726-vn2 pattern). STATE.md warns new outer
  loops amplify the known Clarabel IEEE-13 flakiness — do not gate CI on it.
- **D-14:** **Acceptance gate = welfare + λ + μ agreement** vs the centralized solve, each with
  its own newly-measured tolerance (measurement-before-golden). μ matching IS the deliverable —
  welfare-only would let a wrong price pass. If the fixture shows genuine μ degeneracy, document
  the honest boundary rather than force a match.
- **D-15:** **Docs this phase: rich docstrings + the 4Q complementarity derivation note beside
  the code** (house style). The literate executed rung page is Phase 23's MESH-06 as the roadmap
  scopes it — no standalone page now.

### Claude's Discretion
- Exact two-block convergence/stopping treatment math (which residuals, update rule for μ,
  whether the reactive block gets its own ρ) — research question; roadmap only forbids using the
  single-block Boyd rule as-is.
- μ initialization / warm-start (e.g. from the `:certified` one-shot read) — implementation
  choice.
- Utility parametrization of the 4Q battery's charge/discharge preference (whether App. C's
  λ-triple shape is reused with new derivation, or a different concave form) — must serve the
  D-05 derivation.
- Naming of the new device struct, certificate function, and mode symbols.
- Whether AGR-OPT's per-node subproblem becoming conic (SOCP) when a 4Q device is present needs
  any solver-path adjustment (Clarabel handles both).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v3.0 research (phase-level pitfalls + standing bars)
- `.planning/research/SUMMARY.md` — v3.0 research synthesis; MESH-axis split rationale and the
  phase-19-first sequencing.
- `.planning/research/PITFALLS.md` — "certificate laundering" standing bar (every new
  mathematical regime gets its OWN certificate/tolerance), gate-then-golden ordering,
  measurement-before-golden.

### Source theory
- `.planning/research/THEORY-thesis.md` — thesis equation map (battery eqs. 3.6–3.9, App. C
  no-binary argument pp. 166-168 that D-05 re-derives for 4Q).

### Code seams this phase touches (read before planning)
- `src/devices/PVBattery.jl` — the existing battery: SOC recursion pattern, App. C argument and
  its strict-λ constructor guard, the aggregatable-device return contract this phase widens.
- `src/devices/Aggregator.jl` — sole `:Rp`/`:Rq` writer; the `−Pdc·tanφ` inelastic reactive term
  D-10 keeps untouched; the roll-up point for the new `q_inject`.
- `src/devices/AbstractDevice.jl` — device contract documentation to update for `q_inject`.
- `src/admm/solve_admm.jl` — `reactive_consensus::Bool` kwarg (D-12 promotes to 3-state), the
  ADMM outer loop the μ-ascent step lands in, `assert_no_slack` certification of `:balance_q`.
- `src/admm/DsoOpt.jl` — `qag_dso[j,t]` coupling variable + `:qag_pin` equality (the v2.1
  one-shot scaffolding the live ascent unpins), `:balance_q` registration.
- `src/admm/AgrOpt.jl` — per-node aggregator subproblem that gains the 4Q device + μ price term.
- `src/admm/residuals.jl` — `:Rq` residual plumbing.
- `src/models/exactness.jl` — `assert_socp_exact!` (the certificate pattern D-07's new gate is a
  peer of; do NOT reuse its tolerance).

### Measurement hygiene (binding on tolerance design)
- `.planning/spikes/MANIFEST.md` — solver-noise-floor calibration requirements (WR-01 scale-free
  idiom scales with magnitude, NOT solver accuracy; calibrate per feeder before classifying).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PVBattery.jl`'s SOC recursion + split-variable pattern (eq. 3.6): the 4Q device reuses the
  convex η-modeling shape, minus the PV coupling.
- v2.1 `reactive_consensus` scaffolding (`qag_dso` coupling variable, `:qag_pin` equality,
  `:balance_q` dual certification in the final consolidation solve): the live ascent replaces the
  pin with a genuine consensus/ascent update rather than building new plumbing.
- Bounded-retry quarantine pattern for flaky IEEE-13 ADMM tests (quick task 260726-vn2).
- `assert_socp_exact!` / `assert_ac_oracle` certificate idiom (throw-by-default, kwarg
  neutralization) as the shape template for the new complementarity certificate.

### Established Patterns
- Aggregator-as-sole-`:Rp`/`:Rq`-writer (LOCKED since v1.0): devices return terms, never write
  residuals — the 4Q device must follow this via the widened return contract.
- Byte-identical default paths when new flags are off (v3.0 standing bar; roadmap success
  criterion 4) — D-09/D-10's absent-means-zero + additive composition are designed to make this
  structurally trivial.
- Throw-never-@assert convention for guards; strict constructor validation with loud
  ArgumentErrors (see `PVBattery`'s inner constructor).
- Test invocation: `julia --project=. -e 'import Pkg; Pkg.test()'` — never
  `--project=test` + `@run_package_tests` (documented misdiagnosis hazard).

### Integration Points
- Device → `Aggregator.contribute!` roll-up (new `q_inject` enters here).
- `solve_admm` kwarg surface + outer loop (3-state mode, μ-ascent step, two-block stopping).
- `DsoOpt` `ctx.meta[:qag_dso]` handle (unpinned in `:live` mode).
- Results/pricing surface where λ DADPs are exported today (μ + q join it, D-11).

</code_context>

<specifics>
## Specific Ideas

- The complementarity derivation should explicitly address the negative-price regime: with grid
  charging and η² < 1, simultaneous charge/discharge is energy-burning, which flips from
  strictly-dominated to potentially-optimal exactly when the effective nodal price is negative —
  the user chose to characterize this honestly (D-08) rather than exclude it by construction.
- Cross-validation semantics under q-degeneracy: compare welfare and prices, never q
  trajectories (D-03) — a q-trajectory golden would be pinning a non-unique quantity.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Meshed formulation, angle-recoverability
certificate, and the combined literate page are already scoped to Phase 23; overvoltage
restriction to Phase 20.)

</deferred>

---

*Phase: 19-4Q-BESS + Live Reactive Dual-Ascent*
*Context gathered: 2026-08-07*
