# Phase 25: IEEE-8500 Scale Benchmark - Research

**Researched:** 2026-08-20
**Domain:** Real-utility-scale OpenDSS feeder ingestion (3-winding center-tap transformer reduction,
phase-tagged positive-sequence collapse), Clarabel/SCS conic-solver benchmarking at ~4,900 branches,
SOCP-exactness noise-floor calibration.
**Confidence:** MEDIUM-HIGH overall — HIGH on the transformer reduction (verified against OpenDSS's
own source code), HIGH on Clarabel/solver mechanics (Context7/official docs), MEDIUM on the exact
phase-collapse edge cases (verified against the real vendored files, but not exhaustively for every
one of 2,526 records), LOW-MEDIUM on model-build performance at true 4,873-bus scale (reasoned from
code inspection, not yet measured).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Deferred Ideas (OUT OF SCOPE)

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
</user_constraints>

## Summary

The phase's five priority questions all have concrete, mostly well-grounded answers. The single most
important correction this research surfaces: **D-05's transformer per-unit arithmetic in CONTEXT.md
used an incomplete reduction formula** (`%Rs[1]+%Rs[2]` and bare `Xhl`) that omits the second
secondary half-winding entirely. Verified directly against OpenDSS's own `Transformer.pas` source
(the actual engine that produced this test case), the physically- and numerically-correct balanced
reduction is `R_total = %Rs[1]+%Rs[2]+%Rs[3]` and `X_total = 0.5·(Xhl+Xht+Xlt)`. Recomputed, the CT5
transformer (8 of 1,177 units, the smallest) moves from "82% of `IMPEDANCE_PU_MAX=5.0`, comfortably
cleared" to **r=6.0 pu / x=5.44 pu — over the limit on both axes**. This directly changes D-05's
"tripwire cleared honestly" conclusion and needs to be re-decided before the plan locks S_base.

Second: the cone-gap noise-floor calibration (spike 002's prescribed method) maps cleanly onto
Clarabel's real, documented settings surface (`tol_gap_abs/rel`, `tol_feas`, `tol_infeas_abs/rel`,
and — importantly — `equilibrate_min_scaling`/`equilibrate_max_scaling`, which cap Clarabel's
automatic conditioning fix at an 8-order-of-magnitude window, uncomfortably close to this fixture's
measured ~9-order impedance spread). Clarabel also exposes a native `time_limit` solver setting with
a standard `MOI.TIME_LIMIT` termination status, which directly implements D-18's per-point timeout
for a single Clarabel call with zero risk of the fragile async-task-cancellation pattern — but
`solve_admm`'s outer ADMM loop has no built-in wall-clock exit today, so bounding a *whole* ADMM
point needs either a small additive `time_limit_s` kwarg on `solve_admm` or an external
iteration-budget estimate from a one-iteration timing probe.

Third: the positive-sequence collapse of the phase-tagged MV network is mostly a direct transfer of
`scripts/reduce_ieee123_impedances.jl`'s method, but the real vendored files contain a concrete,
verified pitfall the IEEE-123 script never had to handle: **three locations produce genuine parallel
edges after phase-suffix stripping** (`Q16642`/`Q16642_CAP`, `Q16483`/`Q16483_CAP`,
`L2823592`/`L2823592_CAP` — three single-phase "cap connector" jumper lines each, one per phase, all
between the same two collapsed bus names) plus the four regulator transformer banks (each three
single-phase units between the same collapsed bus pair). The reduction script must detect and
deduplicate these (assert all copies identical, keep one) or the `edges == N-1` radial invariant
breaks at construction.

Fourth: SCS.jl's weakdep/extension wiring is a direct, low-risk copy of the existing
`TSODSOGurobiExt.jl`/`TSODSOMosekExt.jl` pattern, with one naming wrinkle: SCS is open-source, not
commercial, so routing it through `commercial_optimizer`/`GurobiChoice`/`MosekChoice` is a semantic
mismatch that the planner should resolve with a new, non-"commercial" dispatch name.

Fifth: the codebase's own scale mechanisms (`assert_radial`'s BFS, the DSO-OPT transit-node
relaxation, the vectorized `@constraint` comprehensions) are all linear in `N`/`B`/`T` by inspection —
no accidental quadratic blowup was found. The more concrete scale risk is **the docs CI job's
30-minute budget** (`.github/workflows/CI.yml`), which the existing `socp_applicability.jl` literate
page already exceeds on a much smaller substrate (~16 min on IEEE-123-scale) and works around by
loading pre-computed results instead of solving live — directly relevant to D-17/D-18's grid sizing.

**Primary recommendation:** fix the transformer reduction formula before finalizing D-05's tripwire
math; build the reduction script's edge-collapse step with an explicit "assert-identical-then-dedupe"
guard for phase-tag collisions; calibrate the noise floor using Clarabel's real settings names; bound
D-18's per-point timeout via Clarabel's native `time_limit` for single solves plus a small additive
`time_limit_s` on `solve_admm` for the ADMM loop; and size the docs page's density-sweep grid against
the docs job's real ~30-minute budget, not an assumed-unlimited one.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OpenDSS text parsing → committed impedance table | Data ingestion (`scripts/`) | — | Zero-dependency, text-in/Julia-source-out, mirrors `reduce_ieee123_impedances.jl`; never a runtime dependency |
| Per-unit conversion (MV/LV multi-base) | Data ingestion (`src/data/*.jl`, at `Feeder` construction time) | `src/units/PerUnit.jl` (the conversion primitives) | `Feeder`/`Branch` store per-unit only (DATA-01); conversion happens ONCE, never inside a model builder |
| Radial-topology + magnitude validation | `Feeder` inner constructor (`src/data/Feeder.jl`) | `src/data/topology.jl`, `src/units/PerUnit.jl` | Construction-time invariant; cannot be bypassed |
| Fixed-Q capacitor injection | Device layer (`src/devices/`) | `Aggregator` roll-up (`:Rq` seam) | Reuses the existing optional `q_inject` contract (MESH-04/D-09); zero core-model change |
| SOCP relaxation + exactness certification | Model/formulation layer (`src/models/`) | — | `assert_socp_exact!` is the existing, reusable gate; only its `atol`/`rtol` are re-derived per fixture |
| ADMM/DADP decomposition | `src/admm/` | — | Existing `solve_admm`/`build_dso_opt`/`build_agr_opt`; NOT modified except possibly a minimal wall-clock kwarg |
| Solver selection (Clarabel/SCS/HiGHS) | `src/solver/factory.jl` | `ext/TSODSOSCSExt.jl` (new) | Single seam; no model ever names a solver (INFRA-02) |
| Benchmark measurement + goldens | `scripts/` (harness) + `test/` (goldens) | `src/experiments/store.jl` (DrWatson) | Measuring is not a framework capability (D-14); stays out of `src/` |
| Live-executed scaling narrative | `docs/literate/` + `docs/make.jl` | CI (`.github/workflows/CI.yml`, `docs` job, 30 min) | Bounded by the SAME CI budget every other literate page shares |

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCALE-01 | Committed IEEE-8500 balanced-load-case fixture, dependency-free reduction script, `--verify` mode, provenance header, stated real bus count (IN-02) | Reduction-script pattern transfer (Architecture Patterns §1-3); parallel-edge/self-loop pitfalls (Common Pitfalls §1); real fetched file formats confirmed |
| SCALE-02 | Multi-voltage-base per-unit ingestion, `S_base` as load-bearing decision, `IMPEDANCE_PU_MAX` cleared honestly or re-scoped | Transformer reduction correction (Common Pitfalls §2, Code Examples §1) — directly changes D-05's arithmetic; MV/LV `V_base` consistency requirement (Common Pitfalls §3) |
| SCALE-03 | Non-modeled devices (capacitors, regulators, transformer core losses) handled by stated assumption | `q_inject` seam reuse for capacitors (Architecture Patterns §4); transformer no-load-loss/magnetizing-branch omission (Common Pitfalls §2, "what's approximated away") |
| SCALE-04 | Measured scaling numbers, Clarabel-vs-SCS crossover, SCS weakdep wiring | SCS.jl extension pattern (Architecture Patterns §5); Clarabel/SCS tolerance-name asymmetry (Common Pitfalls §5); scale/model-dimension estimates (Common Pitfalls §6-7) |
| SCALE-05 | New exactness gate at scale, live-executed literate page | Noise-floor calibration ladder using real Clarabel settings (Code Examples §2); docs-CI-budget constraint on D-17/D-18 (Common Pitfalls §8) |

</phase_requirements>

## Standard Stack

### Core (already dependencies — no change)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Clarabel.jl | 0.11.1 (repo-pinned) | Primary SOCP solver | Already the project default; settings confirmed via official Clarabel docs this session |
| HiGHS.jl / Ipopt.jl | repo-pinned | LP/MILP / NLP fallback, unaffected by this phase | No change |
| JuMP.jl / MOI | 1.30.x / 1.51.x | Modeling layer | No change |
| DrWatson.jl | repo-pinned | Result storage for benchmark harness output | Existing `tagsave` pattern (`src/experiments/store.jl`) |

### New (this phase)
| Library | Version | Purpose | Provenance |
|---------|---------|---------|------------|
| `SCS` (Julia, registry name `SCS`) | 2.6.4 (General registry, confirmed current) | Alternative first-order conic solver for the D-20/D-21 crossover + DADP-drift diagnostic | [ASSUMED] — see Package Legitimacy Audit below; slopcheck has no Julia-ecosystem support, so this cannot reach `[VERIFIED]` this session despite corroboration from the official `jump-dev/SCS.jl` README and the Julia General registry `Versions.toml` |

**Installation** (weakdep only — never a hard runtime dependency):
```toml
# Project.toml
[weakdeps]
SCS = "c946c3f1-2d62-5474-9fac-a2c854d76d31"   # verify this UUID against the live General registry at implementation time

[extensions]
TSODSOSCSExt = "SCS"
```

**Version verification:** confirmed via `raw.githubusercontent.com/JuliaRegistries/General/master/S/SCS/Versions.toml`
(fetched this session): latest listed version is `2.6.4`, matching CLAUDE.md's pinned recommendation.
Re-run this check at implementation time — the registry moves.

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `SCS` | Julia General | mature (SCS.jl has shipped since ~2017; v2.6.4 is an incremental release) | not applicable (Julia General has no download counters) | `github.com/jump-dev/SCS.jl` (confirmed via WebFetch of its README) | **not available — slopcheck has no Julia/General-registry ecosystem support** (`--ecosystem` only accepts pypi/npm/crates.io/go/rubygems/maven/packagist) | **[ASSUMED] — gate behind `checkpoint:human-verify` before `Pkg.add`** |

**Packages removed due to slopcheck `[SLOP]` verdict:** none (slopcheck could not run against this ecosystem).
**Packages flagged as suspicious `[SUS]`:** none evaluated (same reason).

Per the graceful-degradation protocol: since slopcheck cannot verify Julia General-registry packages,
`SCS` is tagged `[ASSUMED]` even though it is corroborated by the official `jump-dev/SCS.jl` GitHub
README and the live General registry `Versions.toml`. The planner should insert a
`checkpoint:human-verify` task immediately before the `Pkg.add("SCS")` / `[weakdeps]` step, where the
human confirms the UUID and version against `https://github.com/JuliaRegistries/General/blob/master/S/SCS/Package.toml`
at execution time.

## Architecture Patterns

### System Architecture Diagram

```
 OpenDSS source (GitHub, dss-extensions/electricdss-tst, pinned commit SHA)
        │  (vendor: fetch, sha256-pin — SCALE-01)
        ▼
 scripts/data/ieee8500/*.dss  (vendored text, never re-derived)
        │
        ▼
 scripts/reduce_ieee8500_impedances.jl   (zero deps: Base + PCRE regex)
   ├─ parse Lines.dss / LineCodes2.DSS      → Fortescue-reduce per-phase Ω/km, DEDUPE phase-collapsed
   │                                           parallel edges (assert-identical-then-keep-one)
   ├─ parse LoadXfmrCodes.dss                → 3-winding star decomposition (Xhl/Xht/Xlt → X1,X2,X3),
   │                                           balanced-series reduction (ΣR, X1+X2+X3)
   ├─ parse Regulators.dss / Transformers.dss → near-ideal low-Z treatment (Assumption A2), same dedupe
   └─ parse Triplex_Lines.DSS / Loads.dss    → LV topology + real per-load kW (D-03)
        │  emits committed Julia source (Ω/pu-ready, NOT yet pu)
        ▼
 src/data/ieee8500_impedances.jl  (GENERATED, committed)
        │
        ▼
 src/data/ieee8500.jl  (fixture builder: ieee8500_modified() / ieee8500_mv_modified())
   ├─ Ω → pu ONCE via to_pu_impedance (PerUnitBase per voltage level, D-09)
   ├─ Feeder(buses, branches, root)  ← assert_radial + assert_magnitudes run HERE
   └─ registers into build_feeder(sym) (src/experiments/materialize.jl)
        │
        ▼
 src/experiments/materialize.jl
   ├─ build_population(:default, feeder, :ieee8500, profiles, seed)
   │    NEW per-bus real-kW path (D-03) — cannot reuse the scalar `load_scale` pattern as-is
   └─ q-only capacitor Aggregator at the 4 promoted cap buses (D-12)
        │
        ▼
 scripts/benchmark_ieee8500.jl  (harness — density sweep × {Clarabel, SCS} × {centralized, ADMM})
   ├─ centralized: solve_welfare(...) + assert_socp_exact!(ctx; atol/rtol from noise-floor calibration)
   ├─ ADMM: solve_admm(...) [+ possible new time_limit_s kwarg for D-18]
   └─ metrics: time_ns() split (assembly vs solve), iter count, termination_status, peak memory
        │
        ├──► test/ (D-16 deterministic goldens: iter counts, dims, termination status — NOT wall time)
        └──► docs/literate/ieee8500_scaling.jl (D-17 live-executed page, D-18 per-point timeout)
```

### Pattern 1: Star-equivalent decomposition of a 3-winding transformer (VERIFIED against OpenDSS source)

**What:** OpenDSS's `Transformer.pas` (`CalcY_Terminal`, lines ~1805-1825 of the vendored
`tshort/OpenDSS` mirror) builds the transformer's `ZB` loop-impedance matrix using, for a 3-winding
unit, diagonal terms `ZB[i,i] = (R1+R_{i+1}) + j·XSC[i]` (where `XSC = [Xhl, Xht, Xlt]`) and
off-diagonal terms `ZB[i,j] = 0.5·(ZB[i,i]+ZB[j,j] - (R_{i+1}+R_{j+1}) - j·Xlt)`. Substituting
concrete values proves the off-diagonal collapses EXACTLY to `R1 + j·X1` where
`X1 = 0.5·(Xhl+Xht−Xlt)` — i.e. this matrix construction **is** the classical star (Y) equivalent
circuit (branches `Z1=R1+jX1`, `Z2=R2+jX2`, `Z3=R3+jX3` meeting at an internal star point), derived
from the three pairwise short-circuit tests `Xhl=X1+X2`, `Xht=X1+X3`, `Xlt=X2+X3`.

**When to use:** any OpenDSS 3-winding `XfmrCode` (here: all 9 `CT*` service-transformer codes,
`phases=1 windings=3`).

**The balanced-load reduction (physically derived, this session — tag `[ASSUMED]`, not lifted from a
published formula):** the two secondary half-windings (`X2`, `X3`) are wired in series through the
physical center-tap node (`X....1.0` / `X....0.2`, confirmed in the vendored `LoadXfmrCodes.dss`
comment: "secondary windings are consistently connected 1.0 and 0.2… to get the polarity correct").
`Loads.dss`'s own comment confirms the kW is split EQUALLY between the two 120 V legs with the SAME
`pf`. Under that symmetric loading, a phasor KCL argument (each leg's load current, referenced to the
SAME global neutral, is the negative of the other's — `I_leg1 = −I_leg2`) shows the transformer's own
center-tap node carries **zero net current**, so the full load current flows through BOTH `Z2` and
`Z3` in series (never splitting off at the tap). The correct single-branch reduction is therefore:

```
R_total%  = %Rs[1] + %Rs[2] + %Rs[3]                      # R is NOT star-decomposed — confirmed
                                                            # directly from source: ZB uses bare
                                                            # Rs[i]+Rs[j] sums, no transform needed
X_total%  = X1 + X2 + X3 = 0.5·(Xhl + Xht + Xlt)           # star-decomposed, then re-summed
          = Xhl + 0.5·Xlt     (when Xhl == Xht, true for every CT* code here)
```

For the CT5 code (`%Rs=[0.6,1.2,1.2]`, `Xhl=Xht=2.04`, `Xlt=1.36`):
`R_total = 0.6+1.2+1.2 = 3.0%`, `X_total = 0.5·(2.04+2.04+1.36) = 2.72%`.

**Correction to CONTEXT.md D-05:** D-05's placeholder formula (`%Rs[1]+%Rs[2]` and bare `Xhl`) gives
`R=1.8%`, `X=2.04%` — under-counting by omitting the second secondary half-winding's resistance
entirely and omitting the star-transform correction on X. Converting BOTH to the 1 MVA system base
(`Z_pu = Z%/100 · S_base_system/kVA_xfmr_own`, kVA_xfmr_own = 5 for CT5):

| | D-05's formula (incomplete) | Corrected formula |
|---|---|---|
| r (pu) | 1.8%×200 = 3.60 | **3.0%×200 = 6.00** |
| x (pu) | 2.04%×200 = 4.08 | **2.72%×200 = 5.44** |
| vs `IMPEDANCE_PU_MAX=5.0` | 72-82% of limit — "cleared" | **20-9% OVER the limit on both axes** |

This is the single highest-priority correction from this research: **re-run D-05's tripwire check with
the corrected formula before locking `S_base`.** Under the phase's own "characterize the wall, don't
tune it away" ethos (D-06), tripping on CT5 (8 of 1,177 units, the smallest/most numerous-adjacent
size) may itself be the honest finding SCALE-02's success criterion asks for — or it may justify a
consciously-documented re-scope (e.g. widening the tripwire band specifically with reasoning, never
silently). Either way, this must be a stated decision, not an artifact of an under-counted formula.

**What is approximated away:** the magnetizing/no-load branch (`%imag=0.5`, `%noloadloss=.2` — a
SHUNT admittance OpenDSS adds "to the 2nd winding, assuming it is closest to the core", per the same
source function). This framework has no shunt/magnetizing-branch modeling capability (the same gap
D-10/D-11 already document for capacitors) — so transformer core losses are silently dropped unless
explicitly stated. Recommend folding this into the SCALE-03 "stated assumption, not silence" list
alongside capacitors/regulators.

**Recommended verification:** since this derivation is reasoned (not lifted from a citable published
formula), give the reduction script's `--verify` mode a pinned sanity check analogous to
`reduce_ieee123_impedances.jl`'s `LINECODE1_R1_EXPECTED` — e.g. assert CT5 reduces to
`R_total=3.0%, X_total=2.72%` (or whatever the final chosen formula gives) within tight tolerance, so
any future edit to the formula is caught loudly.

### Pattern 2: MV/LV per-unit base consistency (must be a matched pair, not independently chosen)

**What:** `Z_base = V_LL²/S_3φ` is algebraically IDENTICAL to `V_LN²/S_1φ` for a balanced system —
so the "line-to-line vs line-to-neutral" convention for `V_base` does not matter in isolation, but
**the ratio `V_base_MV / V_base_LV` must equal the real transformer turns ratio** (~60:1 here,
`7.2kV/0.12kV = 60.0` or `12.47kV/0.208kV = 59.95`, both consistent). Mixing conventions —
e.g. `V_base_MV=12.47` paired with `V_base_LV=0.12` (ratio 104, not ~60) — silently introduces a
`(104/60)² ≈ 3.0×` per-unit impedance error at every MV/LV boundary, because the transformer's own
`%Z` figures convert to the system base using ONLY the kVA ratio (their voltage dependence cancels
via the turns ratio) — but only if the chosen `V_base` pair itself respects that same turns ratio.

**Recommendation:** `V_base_MV = 12.47 kV`, `V_base_LV = 0.208 kV` — both match `Master.dss`'s own
`Set voltagebases=[115, 12.47, 0.48, 0.208]` list, both match `ieee123.jl`'s established precedent of
using the feeder's OpenDSS-nominal voltage directly, and the ratio (59.95) is within 0.1% of the
transformer's real 60:1 ratio (negligible). CONTEXT.md D-09 lists "0.208/0.12 kV LV" as if either
were interchangeable; they are NOT interchangeable with each other in isolation — pick 0.208 kV to
pair consistently with the 12.47 kV MV choice.

### Pattern 3: Reduction-script transfer from IEEE-123 — what carries over unchanged, what does not

| Element | IEEE-123 script | IEEE-8500 | Change needed |
|---|---|---|---|
| Terminal parsing | Integer terminal numbers (`149`, `9r`) | Alphanumeric names with optional `.N` phase suffix (`M1009763.2`, `L3085398`) | `parse_terminal` must strip a trailing `\.\d+$` suffix, not parse a leading integer |
| Linecode lookup | `LineCode=<int>`, single `IEEELineCodes.DSS` shared across 4 feeders (12 of 29 relevant) | `Linecode=<name>` (lowercased in source, e.g. `1PH-x4_ACSRx4_ACSR`), `LineCodes2.DSS` has 69 codes, all referenced by this feeder alone (redirect chain confirms `LineCodes2.DSS`, NOT `LineCodes.dss`) | Regex keys on name, not int; no "is this code even used by MY feeder" filter needed here (single-feeder file) |
| Matrix reduction | `fortescue_reduce` handles n=1,2,3 uniformly (n=1 short-circuits to `mat[1,1]`) | Same matrix shapes appear (1x1 for the ~50 single-phase codes, e.g. `1ph-x4_acsrx4_acsr Rmatrix=[1.67466]`) | **No change** — the existing function transfers directly |
| Parallel/duplicate edges after collapse | None observed (each `(p,c)` edge tuple unique in `IEEE123_EDGES`) | **3 confirmed locations** (`Q16642`↔`Q16642_CAP`, `Q16483`↔`Q16483_CAP`, `L2823592`↔`L2823592_CAP`, each with 3 identical single-phase "CAP_xA/B/C" jumper records, r1=x1=1.0 Ω/km × 0.001 km each) + the 4 regulator transformer banks (`VREG2/3/4`, `FEEDER_REG` — 3 single-phase units each, same collapsed bus pair) | **New step required**: after building the (from,to) edge dict, detect keys hit by >1 raw record; assert all copies have IDENTICAL impedance (throw loudly if not — never silently average or arbitrarily pick); keep exactly one |
| Self-loops after collapse | N/A | **Verified NONE** in `Lines.dss` (checked all 2,526 records programmatically this session: zero cases where `bus1`'s base name equals `bus2`'s base name) | No handling needed, but the reduction script should still assert this (throw if found) rather than assume it |
| Switch/near-zero-Z segments | `IEEE123_SWITCH_EDGES` (5 segments, explicit list) | `switch=y` lines exist (e.g. `2002200004868472_sw bus1=D5563942-4_INT bus2=Q16483 switch=y R1=1`) plus the 4 regulator banks + substation transformer + source reactor | Same Assumption-A2 treatment (D-13); needs its own explicit edge list analogous to `IEEE123_SWITCH_EDGES` |
| Direct r1/x1 (no linecode/matrix) | None | `HVMV_Sub_connector` (`r1=0.001 x1=0.01`, the 6.4e-9 pu stub D-06 references) and the 6 `CAP_*` jumpers specify `r1=`/`x1=` DIRECTLY, no `Linecode=`/matrix lookup at all | Reduction script needs a SECOND regex path for lines with inline `r1=`/`x1=` (skip the linecode lookup for these) |

### Pattern 4: q-only fixed-injection capacitor device (minimal `AbstractDevice`)

**What:** The `AbstractDevice` contract (`src/devices/AbstractDevice.jl`) requires
`contribute!(d, ctx; T) -> (; vars, p_inject, q_inject, utility)`. `FourQuadBESS`
(`src/devices/FourQuadBESS.jl:259-360`) is the only existing implementor of the OPTIONAL `q_inject`
widened contract (MESH-04/D-09). A fixed-Q capacitor device needs NO JuMP variables, NO constraints,
and NO utility term — it is a pure constant injection:

```julia
# Source: pattern derived from src/devices/AbstractDevice.jl + FourQuadBESS.jl contract (this session)
struct FixedCapacitor <: AbstractDevice
    bus::Int
    q_nom_pu::Float64     # nameplate reactive injection, per-unit, always-on (D-11)
end

function contribute!(d::FixedCapacitor, ctx::ModelContext; T::Int)
    q_const = fill(AffExpr(d.q_nom_pu), T)     # constant AffExpr, no variables
    p_inject = fill(AffExpr(0.0), T)           # no active injection
    utility = zero(QuadExpr)                   # not a decision, nothing to optimize
    return (; vars = NamedTuple(), p_inject, q_inject = q_const, utility)
end
```

Because `q_inject` is summed additively by `Aggregator` (DEV-05 sole-writer invariant preserved,
D-12), this adds ZERO new JuMP variables to the model per capacitor bus — the entire device is a
constant folded into the existing `:Rq` residual sum. Confirms D-10's "nearly free" framing.

### Pattern 5: SCS weakdep extension (mirrors `TSODSOGurobiExt.jl`/`TSODSOMosekExt.jl`, with a naming caveat)

**What:** The existing pattern (`ext/TSODSOGurobiExt.jl`, `ext/TSODSOMosekExt.jl`) adds a method to
`commercial_optimizer(choice_marker, pc::ProblemClass)`, gated by `[weakdeps]`+`[extensions]` in
`Project.toml`, dispatched via a singleton marker type (`GurobiChoice`, `MosekChoice`) declared in
`src/solver/ProblemClass.jl`. **SCS is open-source, not commercial** — routing it through
`commercial_optimizer`/a `*Choice` marker is a semantic mismatch (the docstring and error message
both say "commercial solvers are opt-in… never a hard dependency", which is TRUE of SCS's
weakdep-ness but not of its licensing).

**Recommendation:** introduce a PARALLEL, differently-named dispatch function (e.g.
`alternative_optimizer(choice, pc::ProblemClass)`, or whatever name the planner's discretion settles
on — this is explicitly Claude's-discretion naming per CONTEXT.md) with its own marker type
(`SCSChoice`), fallback-errors in `factory.jl` exactly like `commercial_optimizer`'s fallback, and a
concrete method added ONLY by `ext/TSODSOSCSExt.jl`:

```julia
# Source: pattern mirrors ext/TSODSOGurobiExt.jl exactly, this session
module TSODSOSCSExt

using TSODSO, SCS, JuMP

TSODSO.alternative_optimizer(::TSODSO.SCSChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(SCS.Optimizer, "verbose" => 0)

end # module TSODSOSCSExt
```

**SCS settings relevant to D-21's DADP-drift diagnostic** (confirmed via WebFetch/WebSearch of the
official `cvxgrp/scs` docs and `jump-dev/SCS.jl` README):
- Option names are `eps_abs`/`eps_rel` (NOT `tol_gap_abs`/`tol_gap_rel` — different vocabulary from
  Clarabel), default `1e-4` each — **two orders of magnitude looser than Clarabel's factory default
  `1e-8`**. Expect visibly noisier SCS duals purely from this default gap; D-21's diagnostic should
  report the `eps_abs`/`eps_rel` actually used alongside the drift numbers, or the comparison
  conflates "different algorithm" with "different requested accuracy."
- `max_iters` (default `1e5`), `normalize`/`scale`/`adaptive_scale` (default `scale=0.1`,
  `adaptive_scale=true`) control SCS's own internal equilibration — a second, independent scaling
  mechanism from Clarabel's, worth noting if the two solvers diverge differently as impedance
  conditioning worsens.
- Set via `optimizer_with_attributes(SCS.Optimizer, "max_iters" => N, "eps_abs" => x, ...)` — same
  JuMP idiom as the rest of the factory.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-point solver wall-clock cap (single Clarabel/SCS solve) | An `@async`/`Task`-based external killer wrapping the solve | Clarabel's native `time_limit` setting (seconds), checked via `termination_status(model) == MOI.TIME_LIMIT` and `has_values(model)` for a partial iterate | Task-based cancellation of a blocking FFI/tight-loop solver call is fragile and can leave the solver's internal state corrupted; `time_limit` is a first-class, standard MOI-reported solver feature |
| Peak-memory measurement | Adding BenchmarkTools.jl or another profiling dependency | `Base.gc_live_bytes()` / `Sys.maxrss()` sampled at the monotonic-clock checkpoints already used by `src/planning/benders.jl`/`trace.jl`'s `time_ns()` idiom | BenchmarkTools is explicitly NOT a project dependency (CLAUDE.md); the existing timing idiom already has the right shape to extend with a memory sample at each checkpoint |
| Noise-floor "is this exact" classification | A bespoke ad-hoc tolerance guess per fixture | The existing `assert_socp_exact!(ctx; rtol, atol)` gate, re-parametrized per fixture (never reused across fixtures — the anti-certificate-laundering rule already established at Phase 20/23) | The gate's math (WR-01 combined `atol+rtol·magnitude`) is already correct; only the NUMBERS need re-deriving at this scale, via the spike-002-prescribed tolerance-ladder re-solve |
| 3-winding transformer reduction | A generic N-winding matrix-inversion utility inside `src/` | The closed-form star-decomposition (Pattern 1 above), computed once in the reduction script and emitted as a plain Ω or %Z pair | This fixture has exactly ONE transformer topology (9 XfmrCodes, all `windings=3`); a general N-winding solver is unneeded machinery for a one-shot text-to-table reduction |

**Key insight:** every "don't hand-roll" here is really "don't build new machinery — the project
already has the right tool, just needs it re-parametrized or re-scaled for this fixture." That is
consistent with the phase's stated purpose (measure/characterize, not build new capability).

## Common Pitfalls

### Pitfall 1: Parallel edges after phase-suffix stripping break the radial invariant
**What goes wrong:** `assert_radial` requires `edges == buses - 1`; naively keeping all raw
phase-tagged `New Line`/`New Transformer` records after stripping `.N` suffixes yields 3 identical
parallel edges at 3 capacitor-connector locations and 3 at each of 4 regulator banks — the
`Feeder`/`MeshedFeeder` constructor will throw (correctly) the moment this is attempted, but only
AFTER the reduction script has already emitted a wrong table.
**Why it happens:** the source data models a genuinely 3-phase segment as 3 separate single-phase
records (common OpenDSS style for feeders assembled from per-phase construction data).
**How to avoid:** in the reduction script, build the (from,to)→[records] multimap FIRST; for any key
with >1 record, assert all have identical `r`/`x` (within a tight tolerance) and throw loudly if not;
then collapse to exactly one edge.
**Warning signs:** `--verify` mode reporting an edge count that doesn't match `2N_expected - (dupes)`;
`assert_radial`'s `B == N-1` check failing with `B` slightly larger than expected.

### Pitfall 2: Incomplete 3-winding transformer reduction silently under-counts impedance
**What goes wrong:** using only 2 of the 3 windings (`%Rs[1]+%Rs[2]`, bare `Xhl`) under-counts both R
and X, which can *silently* make a tripwire APPEAR cleared when the physically-correct value trips it
(exactly what happened to D-05's CT5 calculation — see Architecture Patterns §1).
**Why it happens:** `%Rs[1]+%Rs[2]` and `Xhl` look plausible in isolation (they ARE the correct
"primary + one secondary leg" values) but miss that the balanced center-tap load path runs through
BOTH secondary legs in series.
**How to avoid:** use `R_total=ΣRs[1:3]`, `X_total=0.5·(Xhl+Xht+Xlt)`; verify with a pinned sanity
check in `--verify` mode.
**Warning signs:** any tripwire check that reports "comfortably cleared" for the SMALLEST unit of a
transformer population where larger units clear by a wider margin should be double-checked — an
under-counted formula systematically understates risk most for the units where the pu impedance is
already largest (smallest kVA).

### Pitfall 3: Mixing MV/LV voltage-base conventions introduces a silent ~3x per-unit error
**What goes wrong:** pairing `V_base_MV=12.47kV` (L-L convention) with `V_base_LV=0.12kV` (L-N
convention) — or any other mismatched pair — changes the effective MV/LV base ratio from the real
~60:1 transformer turns ratio, introducing a `(ratio_error)²` per-unit impedance error exactly at
every MV/LV transformer boundary (silent, because both individual base choices "look" reasonable).
**Why it happens:** the source data itself is ambiguous — `LoadXfmrCodes.dss` rates windings at 7.2kV
primary / 0.12kV secondary; `Loads.dss`/`Master.dss` uses 0.208kV as the LV voltagebase entry for
OpenDSS's own internal bookkeeping (an artifact of OpenDSS's generic multi-phase per-unit-voltage
machinery, not a real "line-to-line" LV voltage — this is genuinely single-phase 120/240V).
**How to avoid:** pick ONE consistent (L-L-equivalent) pair — `12.47`/`0.208` — matching
`Master.dss`'s own `voltagebases=` list and `ieee123.jl`'s established precedent (Architecture
Patterns §2).
**Warning signs:** `IMPEDANCE_PU_MAX` tripwire results that seem implausibly far from a hand-check;
DADP magnitudes across the MV/LV boundary that don't match the transformer's real ~60:1 turns-ratio
scaling.

### Pitfall 4: `_default_house`/`build_population`'s scalar `load_scale` pattern cannot express D-03's real per-bus kW
**What goes wrong:** `build_population` (`src/experiments/materialize.jl:247-296`) currently applies
ONE scalar `load_scale` (`_IEEE13_LOAD_SCALE`/`_IEEE123_LOAD_SCALE`) uniformly to every house in the
population. D-03 requires each of the 1,177 load buses to use its OWN real per-load kW from
`Loads.dss` (which ranges roughly 2-10 kW per record, heterogeneous) — a single scalar cannot express
this.
**Why it happens:** the existing scale constants were tuned placeholders (D-03 explicitly departs
from this precedent); the function signature was never designed for a heterogeneous per-bus
magnitude.
**How to avoid:** either (a) add a new `build_population` branch keyed on `feeder_sym === :ieee8500`
that threads a `Dict{Int,Float64}` (bus → real kW, parsed once from the reduction script's emitted
table or a parallel `Loads.dss`-derived table) into `_default_house` in place of the scalar
`load_scale`, or (b) add a new, explicit `_default_house`-like function that takes a per-bus
magnitude directly. Either is a genuinely new code path, not a parameter tweak to the existing one.
**Warning signs:** any implementation that tries to "average" the real kW into a single scalar has
silently reverted to the D-03-rejected tuned-constant precedent.

### Pitfall 5: SCS and Clarabel tolerance vocabularies do not share option names
**What goes wrong:** copy-pasting Clarabel's `tol_gap_abs`/`tol_gap_rel` into an SCS
`optimizer_with_attributes` call is a silent no-op (SCS ignores unrecognized keys or errors,
depending on version) — SCS's real names are `eps_abs`/`eps_rel`.
**Why it happens:** the two solvers use genuinely different internal algorithms (Clarabel: IPM with
a duality-gap stopping criterion; SCS: first-order ADMM with a primal/dual-residual stopping
criterion) and never shared an option-naming convention.
**How to avoid:** keep the two solvers' attribute vocabularies in clearly separate, explicitly
labeled blocks in the benchmark harness; never assume symmetry.
**Warning signs:** an SCS run that appears to converge at the SAME nominal tolerance number as
Clarabel but with wildly different actual accuracy — the numbers are not directly comparable across
solvers even when the option NAMES coincidentally overlap.

### Pitfall 6: `solve_admm` has no wall-clock exit — D-18's per-point timeout needs a design decision
**What goes wrong:** `solve_admm` (`src/admm/solve_admm.jl:185`) loops internally up to `maxiter`
(default 200) with no time-based early exit. At unknown-scale wall time per iteration, a fixed
`maxiter` does not bound WALL TIME the way D-18 needs.
**Why it happens:** the function was designed before any run took long enough to need a wall-clock
guard; iteration count was always the natural knob.
**How to avoid:** two options, both legitimate: (a) add a minimal, additive `time_limit_s::Union{Nothing,Real}=nothing`
kwarg to `solve_admm` that checks `time_ns()` at the top of each iteration and breaks with a
`:budget_exceeded` status field in the return (mirrors the project's own established monotonic-clock
idiom, `src/planning/benders.jl`); or (b) avoid touching `src/admm/` at all — probe a single
iteration's wall time on the actual fixture first, then compute and pass a conservative `maxiter`
that fits the budget, accepting this bounds ITERATIONS not wall-clock exactly. Option (a) is more
precise and honest to D-18's actual intent; option (b) keeps the phase's `src/admm/`-untouched
framing exactly as CONTEXT.md's Integration Points section lists it. This is a genuine open decision
for the planner, not resolved by this research.
**Warning signs:** a benchmark point that appears to "hang" the docs build — this is exactly the
failure D-18 exists to prevent, so whichever option is chosen, test it against a deliberately
slow/non-convergent point BEFORE relying on it in the live docs build.

### Pitfall 7: The docs job's 30-minute CI budget is a real, already-tight constraint
**What goes wrong:** `.github/workflows/CI.yml`'s `docs` job has `timeout-minutes: 30`, and the
EXISTING `socp_applicability.jl` literate page already documents that ITS OWN substrate B (a
122-branch feeder) takes ~16 minutes and "exceeds this job's whole CI timeout" — which is why THAT
page loads pre-computed results from `results/socp_applicability/` instead of solving live. D-17
chooses full live execution for the NEW 8500-scale page anyway; D-18's per-point timeout is the ONLY
guard against blowing the same budget, but the grid size matters just as much as the per-point cap.
**Why it happens:** the 30-minute budget is shared across ALL ~20 literate pages in the docs build,
not dedicated to this one page; whatever headroom exists is whatever the other 19 pages don't
consume.
**How to avoid:** before finalizing the density-sweep grid (D-1: e.g. 10/25/50/100%) crossed with 2
fixtures (MV-only, MV+LV) crossed with 2 solvers (Clarabel, SCS) — up to 16 points — compute
`grid_size × per_point_timeout` and compare against the REMAINING docs-job budget (30 min minus
whatever the other pages already consume; measure this empirically, e.g. via CI logs, before
assuming headroom). If the arithmetic doesn't fit, either (a) bump `timeout-minutes` on the `docs`
job (simple, low-risk, but changes shared CI infra — flag for the user), or (b) shrink the grid, or
(c) move the most expensive points (headline MV+LV at 100% density, both solvers) to a
`results/`-loaded pattern like `socp_applicability.jl` already does, with the SMALLER points solved
genuinely live.
**Warning signs:** any planning that treats "fully live-executed" (D-17) as unconstrained; D-18 alone
does not guarantee the TOTAL page fits the job budget, only that no SINGLE point hangs it.

## Runtime State Inventory

Not applicable — this phase is greenfield ingestion (new fixture, new script, new extension), not a
rename/refactor/migration.

## Code Examples

### Clarabel per-point wall-clock timeout (D-18, single centralized solve)
```julia
# Source: Clarabel official docs (oxfordcontrol/ClarabelDocs, fetched via ctx7 this session) +
# MOI standard termination-status semantics
model = Model(select_optimizer(SOCP(); time_limit = per_point_budget_s))
optimize!(model)
if termination_status(model) == MOI.TIME_LIMIT
    # record a "budget exceeded" row (D-18) — has_values(model) tells you whether a
    # suboptimal-but-usable iterate exists to report alongside the timeout
    status = :budget_exceeded
    partial = has_values(model) ? value.(...) : nothing
else
    status = termination_status(model)
end
```

### Noise-floor calibration ladder (spike 002's prescribed method, real Clarabel option names)
```julia
# Source: Clarabel official settings docs (fetched via ctx7 this session)
# Re-solve a KNOWN-benign point (interior, non-congested) across a tightening tolerance ladder;
# the point where the cone residual STOPS improving is the fixture's own noise floor.
ladder = [1e-6, 1e-7, 1e-8, 1e-9, 1e-10]   # tol_gap_abs = tol_gap_rel, swept together
residuals = Float64[]
for tol in ladder
    m = Model(select_optimizer(SOCP(); tol_gap_abs = tol, tol_gap_rel = tol))
    # ... build the SAME benign point on the SAME fixture ...
    optimize!(m)
    push!(residuals, measured_cone_residual(m))   # |l·v - (P²+Q²)| on the SAME branch/time
end
# floor = the residual value where tightening `tol` further no longer reduces the measured
# residual (the solver has hit ITS OWN numerical floor, not the requested tolerance) —
# feed this floor into assert_socp_exact!'s atol for THIS fixture (never reuse IEEE-13/123's).
```

### Deduplicating phase-collapsed parallel edges (new reduction-script step)
```julia
# Source: pattern this session, generalizing scripts/reduce_ieee123_impedances.jl's approach to a
# real pitfall that fixture never had (see Common Pitfalls §1)
by_pair = Dict{Tuple{String,String}, Vector{LineRecord}}()
for r in records
    key = r.bus1_base < r.bus2_base ? (r.bus1_base, r.bus2_base) : (r.bus2_base, r.bus1_base)
    push!(get!(by_pair, key, LineRecord[]), r)
end
for (key, recs) in by_pair
    length(recs) == 1 && continue
    r_ref, x_ref = recs[1].r_ohm, recs[1].x_ohm
    all(rec -> isapprox(rec.r_ohm, r_ref; rtol=1e-6) && isapprox(rec.x_ohm, x_ref; rtol=1e-6), recs) ||
        throw(ArgumentError("edge $key collapses $(length(recs)) non-identical phase-tagged " *
                             "records — cannot safely dedupe, inspect source data"))
    # keep exactly one (recs[1]) — all copies verified identical
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| IEEE-123-scale fixtures only (largest shipped) | IEEE-8500-scale (~4,873 buses, ~40x) | This phase | First real-utility-scale test of the ADMM/DADP pipeline and the SOCP-exactness gate |
| Single-solver (Clarabel-only) benchmarking | Clarabel-vs-SCS crossover measurement | This phase (D-20/D-21) | First systematic evidence for the project's "never certify on SCS" policy, converting an assertion into measured drift data |
| Fixed exactness tolerances reused across fixtures | Per-fixture noise-floor calibration (spike-002 method) | Already established at Phase 20/23 for other fixtures; this phase applies it at a new scale | Prevents the exact "48% flagged inexact by noise alone" failure spike 002 found |

**Deprecated/outdated:** none — this phase does not deprecate anything; it extends existing patterns
to a new scale.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Balanced-load center-tap reduction (`R_total=ΣRs`, `X_total=0.5(Xhl+Xht+Xlt)`) is the physically-correct series-path reduction under the documented equal-split loading | Architecture Patterns §1 | If wrong, D-05's whole tripwire re-analysis (and possibly S_base itself) needs redoing again; recommend the `--verify` pinned sanity check AND, if feasible, a one-time cross-check against a real OpenDSS/opendssdirect power-flow solve on a single transformer in isolation |
| A2 | `V_base_MV=12.47kV`/`V_base_LV=0.208kV` is the right consistent pair (vs. `7.2`/`0.12`) | Architecture Patterns §2 | Either consistent pair is mathematically equivalent; the risk is only in MIXING them — flagged clearly either way |
| A3 | `SCS` (Julia General registry, `jump-dev/SCS.jl`) is the correct, non-hallucinated package — corroborated by registry + official README, but NOT slopcheck-verified (no Julia ecosystem support) | Package Legitimacy Audit, Standard Stack | Low risk (well-known, long-established package) but per protocol must stay `[ASSUMED]` and gated behind human verification before install |
| A4 | Neither `assert_radial`'s BFS nor the DSO-OPT transit-node relaxation nor the vectorized `@constraint` comprehensions are accidentally quadratic at ~4,873 buses | Common Pitfalls (implicit — see Summary) | Based on code reading (all loops are O(N)/O(N+B)/O(N·T)), not an actual measured run at true scale; if wrong, this shows up immediately as a benchmark finding (which is exactly what SCALE-04 wants measured, so low downstream risk even if the code-reading assessment is imprecise) |
| A5 | The `alternative_optimizer`/`SCSChoice` naming split (vs. reusing `commercial_optimizer`) is the right architectural call | Architecture Patterns §5 | Naming is explicitly Claude's-discretion per CONTEXT.md; if the planner instead reuses `commercial_optimizer` for SCS, the ONLY cost is a misleading name/docstring, no functional risk |

## Open Questions

1. **D-18's per-point timeout mechanism for the whole-ADMM-loop case (Pitfall 6)**
   - What we know: Clarabel's native `time_limit` cleanly bounds any SINGLE solve; `solve_admm` has
     no wall-clock exit of its own.
   - What's unclear: whether the planner should add a minimal `time_limit_s` kwarg to
     `src/admm/solve_admm.jl` (more precise, touches `src/admm/`) or bound it externally via an
     iteration-count probe (less precise, stays out of `src/admm/` per CONTEXT.md's stated
     integration points).
   - Recommendation: this is a genuine plan-time decision; either is defensible. If chosen, the
     `src/admm/` change should be as small and additive as the existing `time_ns()` idiom already
     models elsewhere in the codebase.

2. **Whether the docs-job's real remaining CI budget (Pitfall 7) actually fits D-17's chosen grid**
   - What we know: the job's total budget is 30 minutes; one existing page alone would consume more
     than that if run live at a comparable scale (hence why it doesn't).
   - What's unclear: how much of the 30 minutes the OTHER ~20 existing pages already consume today —
     this needs an empirical measurement (e.g., time the current `docs` CI job end-to-end) before the
     grid size / per-point timeout can be chosen with confidence.
   - Recommendation: the planner should include an early task that measures current docs-build wall
     time, THEN sizes D-18's per-point cap and D-1's grid against the real remaining headroom.

3. **Whether a real OpenDSS/opendssdirect cross-check of the transformer reduction (A1) is worth the
   dependency cost**
   - What we know: A1's derivation is grounded in reading OpenDSS's own source code (`Transformer.pas`),
     which is strong evidence, but it is still a derivation, not a citation of a published formula.
   - What's unclear: whether the project's "dependency-free reduction script" constraint (SCALE-01)
     permits even a ONE-TIME, out-of-band cross-check (e.g. a local `pip install opendssdirect.py` run
     manually, never committed as a project dependency) to validate A1 numerically before locking it.
   - Recommendation: if time permits, do this cross-check informally (not as a `Project.toml`/`scripts/`
     dependency) purely to build confidence in A1; if not, ship with the `--verify` pinned-sanity-value
     idiom as the safety net, consistent with how `reduce_ieee123_impedances.jl` handles the same
     class of risk.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `curl`/network access to `raw.githubusercontent.com` | Vendoring the OpenDSS source files (SCALE-01) | ✓ (confirmed this session — all listed files fetched successfully) | — | — |
| `ctx7` CLI (Context7 fallback) | Library-doc lookups during this research | ✓ | — | WebSearch/WebFetch (also used) |
| `slopcheck` | Package Legitimacy Gate | ✓ installed, but **no Julia/General-registry ecosystem support** | — | Manual `checkpoint:human-verify` gate on the SCS install (see Package Legitimacy Audit) |
| Julia General registry access | Confirming SCS.jl's current version | ✓ (fetched `Versions.toml` directly) | latest listed: 2.6.4 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** slopcheck's Julia-ecosystem gap (fallback: human verification gate, already applied above).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems`/`TestItemRunner` (repo-established) |
| Config file | none dedicated — repo-wide `test/runtests.jl` + `@testitem` convention |
| Quick run command | `julia --project=. test/test_ieee8500.jl` (plain `Test.jl` script — per the existing GSD-plan lesson that `<verify>` blocks must use direct `Test.jl`, not `TestItemRunner`, under `--project=.`) |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCALE-01 | Reduction script emits a valid, radial, provenance-headed fixture; `--verify` mode passes | unit | `julia scripts/reduce_ieee8500_impedances.jl --verify` | ❌ Wave 0 |
| SCALE-01 | `Feeder` construction succeeds (radial + magnitude invariants) for both fixtures | unit | `julia --project=. test/test_ieee8500.jl` | ❌ Wave 0 |
| SCALE-02 | Multi-voltage-base conversion produces the corrected transformer pu values; `IMPEDANCE_PU_MAX` verdict is explicit (cleared or consciously re-scoped) | unit | same file, dedicated `@testitem`/`@test` block | ❌ Wave 0 |
| SCALE-03 | Capacitor `q_inject` device sums correctly into `:Rq`; regulator near-ideal treatment matches Assumption A2 | unit | same file | ❌ Wave 0 |
| SCALE-04 | Benchmark harness produces deterministic dims/iter-count/status goldens (D-16) | integration | `julia scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick` (small density point only) | ❌ Wave 0 |
| SCALE-04 | SCS extension loads and solves via `alternative_optimizer`/`SCSChoice` | unit | `julia --project=. -e 'import SCS; using TSODSO; ...'` | ❌ Wave 0 (needs SCS installed — gated behind the human-verify checkpoint) |
| SCALE-05 | Per-fixture noise-floor calibration produces a defensible `atol`/`rtol` pair; `assert_socp_exact!` re-certifies at scale | unit + docs | `test/test_exactness.jl`-style unit test + the live-executed literate page | ❌ Wave 0 (unit); page is inherently docs-CI-gated |

### Sampling Rate
- **Per task commit:** the quick, single-small-point harness run + the fixture-construction unit test.
- **Per wave merge:** full `test/` suite for this phase's new files (fast — density-sweep-scale runs
  belong in the docs page/CI `docs` job, NOT in the fast `test` job).
- **Phase gate:** the `docs` job's live-executed page green (bounded by D-18) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `scripts/reduce_ieee8500_impedances.jl` — does not exist yet; needs the `--verify` self-check
  and the dedupe-parallel-edges step (Pitfall 1)
- [ ] `src/data/ieee8500.jl` + `src/data/ieee8500_impedances.jl` (generated) — fixture builders
- [ ] `test/test_ieee8500.jl` — construction/invariant tests, covering SCALE-01/02/03
- [ ] `ext/TSODSOSCSExt.jl` — new extension, needs a test gated behind SCS being installed
- [ ] `scripts/benchmark_ieee8500.jl` — the harness itself; needs at least a "quick" mode for
  CI-affordable smoke testing separate from the full density sweep
- [ ] Framework install: none new for `test/` (existing TestItems/TestItemRunner suffices)

## Security Domain

Not applicable in the conventional sense — this is a research optimization framework with no network
service, authentication, or user-facing input surface. The one relevant control-adjacent concern:

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Fetching third-party OpenDSS source files over the network at vendoring time | Tampering (supply-chain: a compromised or altered upstream file) | Pin a commit SHA (not `master` — 25-DATA-PROVENANCE.md already flags this), verify sha256 against the pinned value at fetch time, mirroring the existing provenance-header convention |
| Installing a new weakdep (`SCS`) | Tampering (dependency-confusion/typosquat) | Package Legitimacy Audit above — human-verify checkpoint before install, since slopcheck cannot cover the Julia ecosystem |

No ASVS categories apply (no auth/session/access-control/input-validation-from-untrusted-users
surface exists in this codebase).

## Sources

### Primary (HIGH confidence)
- `Transformer.pas` (`tshort/OpenDSS`, `Source/PDElements/Transformer.pas`, fetched directly this
  session via `raw.githubusercontent.com`) — the `CalcY_Terminal` function's `ZB` matrix construction,
  used to VERIFY the star-decomposition formulas in Architecture Patterns §1.
- Vendored IEEE-8500 OpenDSS source files (`Master.dss`, `LoadXfmrCodes.dss`, `Lines.dss`,
  `LineCodes2.DSS`, `Loads.dss`, `Triplex_Lines.DSS`, `Regulators.dss`, `Transformers.dss`,
  `Capacitors.dss`), fetched this session from
  `raw.githubusercontent.com/dss-extensions/electricdss-tst/master/Version8/Distrib/IEEETestCases/8500-Node/`
  — used for the phase-collapse pitfall analysis (parallel edges, self-loop check, terminal formats).
- Clarabel official docs (`oxfordcontrol/clarabeldocs`, fetched via `ctx7`) — settings names
  (`tol_gap_abs/rel`, `tol_feas`, `tol_infeas_abs/rel`, `time_limit`, `equilibrate_*`), JuMP wiring
  (`set_optimizer_attribute`, `Clarabel.Settings`).
- `raw.githubusercontent.com/JuliaRegistries/General/master/S/SCS/Versions.toml` (fetched this
  session) — confirms `SCS` v2.6.4 is the current General-registry version.
- Existing repo source read directly: `src/data/Feeder.jl`, `src/data/topology.jl`,
  `src/units/PerUnit.jl`, `src/models/exactness.jl`, `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`,
  `src/solver/factory.jl`, `src/solver/ProblemClass.jl`, `src/devices/AbstractDevice.jl`,
  `src/devices/FourQuadBESS.jl`, `src/experiments/materialize.jl`, `scripts/reduce_ieee123_impedances.jl`,
  `docs/make.jl`, `.github/workflows/CI.yml`, `.planning/spikes/MANIFEST.md`.

### Secondary (MEDIUM confidence)
- `jump-dev/SCS.jl` README (fetched via WebFetch) — `SCS.Optimizer`, `optimizer_with_attributes`
  usage.
- WebSearch results cross-referencing `cvxgrp/scs` official docs for `eps_abs`/`eps_rel`/`max_iters`
  option names (multiple corroborating sources: SCS Python docs, JuMP-dev Convex.jl solver page).

### Tertiary (LOW confidence)
- The single WebFetch of `opendss.epri.com/ModelingSingle-phaseCenter-tappe.html` explicitly stated
  it did NOT contain the balanced-equivalent formula and offered an unsubstantiated "combine in
  parallel" aside — this was EXPLICITLY DISREGARDED in favor of the source-code-verified derivation
  (Architecture Patterns §1), since it contradicted the KCL-grounded, source-verified analysis.

## Metadata

**Confidence breakdown:**
- Transformer reduction (Pattern 1 / Pitfall 2): HIGH — verified against OpenDSS's own engine source
  code, cross-checked with a from-scratch KCL derivation that agrees exactly.
- Phase-collapse / parallel-edge pitfall: HIGH for the 3 confirmed locations (found by directly
  processing all 2,526 real `Lines.dss` records this session) — MEDIUM for completeness (the
  Regulators.dss/Transformers.dss collision cases were identified by inspection, not by running the
  same exhaustive dedup script against them).
- Clarabel/SCS solver mechanics: HIGH — official docs, cross-referenced.
- Scale/performance code-reading (assert_radial, DsoOpt): MEDIUM — sound by inspection, not measured
  at true 4,873-bus scale (that measurement IS the phase's own deliverable).
- SCS package legitimacy: MEDIUM (registry+README corroborated) but formally `[ASSUMED]` per the
  slopcheck-unavailable degradation rule.

**Research date:** 2026-08-20
**Valid until:** 30 days for the code-pattern findings (repo state can drift); the OpenDSS source-data
findings (Pattern 1, Pitfall 1) are stable indefinitely (public, versioned upstream data) modulo the
commit-SHA-pinning caveat already in 25-DATA-PROVENANCE.md.
