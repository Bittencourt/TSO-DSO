---
phase: 25-ieee-8500-scalability-benchmark
verified: 2026-08-22T03:19:43Z
status: gaps_found
score: 7/9 must-haves verified
overrides_applied: 0
gaps:
  - truth: "The Clarabel-vs-SCS crossover point is identified rather than assumed (SCALE-04)"
    status: failed
    reason: "SCS.jl was never installed in any environment used to run the benchmark. Every row in results/ieee8500_benchmark/density_sweep_full.csv reads scs_status = scs_unavailable / not_requested / skipped_oom, at EVERY fixture and EVERY density, not only at IEEE-8500 scale. The alternative_optimizer(SCSChoice(), pc) dispatch (ext/TSODSOSCSExt.jl) is structurally wired and unit-testable, but was never exercised with a real SCS solve, so no crossover was ever observed. This is a controllable gap (installing an open-source Julia weakdep), not an environmental wall like the OOM kills below, and the requirement text is unconditional: 'identified rather than assumed.'"
    artifacts:
      - path: "results/ieee8500_benchmark/density_sweep_full.csv"
        issue: "scs_status column is scs_unavailable/not_requested/skipped_oom on all 17 rows"
      - path: "ext/TSODSOSCSExt.jl"
        issue: "Correctly wired but never actually loaded/exercised in the measurement environment"
    missing:
      - "Pkg.add(\"SCS\") in the benchmark environment, then a re-run of at least the small ieee13/ieee123 rows plus one ieee8500-mv row through run_scs_comparison to produce a real, non-'unavailable' crossover measurement"
  - truth: "Solve time, ADMM iteration count, and SOCP exactness are measured on the committed headline fixture at ~40x scale (SCALE-04/SCALE-05)"
    status: failed
    reason: "The actual headline fixture (ieee8500_modified(), 4,875 buses/4,874 branches -- the true ~40x point the roadmap goal names) never produced a single successful measurement. All 4 attempted/considered densities are OOM_KILLED or not_attempted in density_sweep_full.csv; the fixture never reached solve_welfare's convergence check, solve_admm's iteration loop, or the PF-04 exactness gate. Every number obtained for solve time / ADMM iterations / exact_verdict in the sweep comes from the SEPARATE ieee8500-mv MV-only control fixture (2,521 buses, roughly 20x IEEE-123, not 40x), and even there only at the two lowest densities (0.1, 0.25); ADMM never converges cleanly at any IEEE-8500-scale point (4 iters then ERROR or budget_exceeded)."
    artifacts:
      - path: "results/ieee8500_benchmark/density_sweep_full.csv"
        issue: "Every 'ieee8500' (headline, full MV+LV) row is OOM_KILLED or not_attempted; no termination_status, admm_iters, or exact_verdict value exists for the headline fixture at any density"
    missing:
      - "A converged or at-least-attempted-and-cleanly-classified headline-fixture point, OR an explicit, human-ratified decision that OOM-bounded non-measurement at 40x scale is an acceptable final answer for this phase (see human_verification below -- this is largely an external memory-wall constraint, and is reported honestly, which is why it is scored differently from the SCS gap above)"
deferred:
  - truth: "solve_admm's hardcoded final-consolidation assert_socp_exact! throws on a converged IEEE-8500 point even after the D-13 connector fix (deferred-items.md item 3)"
    addressed_in: "Future milestone (SCALE-STRETCH, listed under REQUIREMENTS.md Future Requirements, not in the current v3.0 phase list)"
    evidence: "REQUIREMENTS.md: 'SCALE-STRETCH: Performance engineering driven by the Phase 25 measurements ... Deliberately deferred: Phase 25 measures and characterizes the wall; optimizing it is separate work and must not be entangled with the benchmark that justifies it.'"
  - truth: "A genuinely converged, memory-feasible IEEE-8500 headline point is reachable without architectural memory-footprint work (deferred-items.md item 4)"
    addressed_in: "Future milestone (SCALE-STRETCH)"
    evidence: "Same SCALE-STRETCH carve-out as above; Phase 25 is the last phase of the v3.0 milestone (no Phase 26 exists in ROADMAP.md to receive this work within-milestone)"
human_verification:
  - test: "Decide whether OOM-bounded non-measurement of the true 4,875-bus headline fixture (at every density) is an acceptable final answer for SCALE-04/05, or whether the phase should be re-run on a machine with materially more free RAM (the kills occurred at anon-rss 6.8-9.75 GiB on a shared 15 GiB machine with ~9 GiB of contemporaneous unrelated swap pressure, so the true memory requirement is unknown, only lower-bounded)"
    expected: "A recorded decision either accepting the honest non-measurement as this phase's final answer for the headline point, or a follow-up plan to re-measure on a dedicated/larger machine"
    why_human: "This is a resource/scope trade-off (buy time on a bigger machine vs. accept a documented negative result) that only the researcher can make; it is not resolvable by inspecting code"
---

# Phase 25: IEEE-8500 Scalability Benchmark Verification Report

**Phase Goal:** A researcher can load a real-utility-scale feeder -- the public IEEE-8500
balanced load case, full MV primary plus LV secondary -- as a committed, provenance-tracked
fixture, and get honest measured answers about whether the operational pipeline holds ~40x above
the largest fixture shipped to date: solve time, ADMM iteration count, memory, the
Clarabel-vs-SCS crossover, and whether SOCP exactness survives.

**Verified:** 2026-08-22T03:19:43Z
**Status:** gaps_found
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A committed, provenance-tracked IEEE-8500 fixture (full MV+LV) exists, ingested from vendored OpenDSS source by a dependency-free script | VERIFIED | `ieee8500_modified()` = 4,875 buses / 4,874 branches (clean tree); `ieee8500_mv_modified()` = 2,521/2,520; `scripts/reduce_ieee8500_impedances.jl` has zero `using`/`import`; `25-DATA-PROVENANCE.md` pins a real 40-hex commit SHA and documents the one intentional data-shaping deviation (busbar-tie connector) transparently |
| 2 | Multi-voltage-base per-unit ingestion is correct and explicit, tripwires cleared honestly (SCALE-02) | VERIFIED | `IMPEDANCE_PU_MAX`/`SMAX_PU_MAX` in `src/units/PerUnit.jl` untouched since commit `f155d2a` (pre-Phase-25); `S_base=0.5 MVA` decision and the ~9-order pu spread documented in `src/data/ieee8500.jl` and `test/test_ieee8500.jl` |
| 3 | Non-modeled devices (capacitors, regulators, switches) are handled by stated assumption, never silence (SCALE-03) | VERIFIED | `src/devices/FixedCapacitor.jl` is a real, wired, zero-JuMP-variable device consumed by `materialize.jl`'s `build_population` for both `:ieee8500`/`:ieee8500_mv`; D-11 (CapControl out of scope) and D-13 (near-ideal regulator/switch treatment) documented in-code with rationale, not silently omitted; `IEEE8500_REGULATOR_EDGES` = 43 entries |
| 4 | The benchmark harness reports every attempted point honestly, including timeouts/non-convergence, never silently (SCALE-04) | VERIFIED | `results/ieee8500_benchmark/density_sweep_full.csv` has 17 rows including 6 manually-recorded `OOM_KILLED` rows (each with `journalctl -k` PID/anon-rss provenance) and 2 explicit `not_attempted` rows with stated rationale -- no point silently dropped (T-25-11 addressed) |
| 5 | A fresh, per-fixture SOCP-exactness noise floor is measured before any exactness claim at 8500 scale, never IEEE-13/123 tolerances reused (SCALE-05, anti-certificate-laundering) | VERIFIED | `IEEE8500_MV_EXACT_ATOL = 0.0011460285861373265`, `IEEE8500_EXACT_ATOL = 0.004969145122458496`, both independently measured via `--calibrate-noise-floor` and re-measured after the connector fix in plan 25-07; no tolerance was widened to manufacture an "exact" verdict (T-25-12 addressed -- see `25-DATA-PROVENANCE.md`'s deviation section) |
| 6 | Where exactness/convergence fails, the failure is characterized (conditioning vs. size vs. formulation), not tuned away or merely reported as an outcome (SCALE-05) | VERIFIED | `docs/literate/ieee8500_scaling.jl`'s "Synthesis" section explicitly triangulates size (bus/branch count vs. OOM), a separate conditioning wall (the ~1e-3 noise floor vs. the project's 1e-6 default), and explicitly states formulation (Clarabel vs. SCS) is UNTESTED, not ruled out -- a genuine characterization, not hand-waving |
| 7 | A live-executed literate page documents the fixture, assumptions, and measured scaling curve (SCALE-05) | VERIFIED | `docs/literate/ieee8500_scaling.jl` (266 lines) solves a real live point (`ieee8500-mv`, density=0.1, Clarabel, 90s budget) at doc-build time and reads the committed full sweep via a Base-only CSV parser; wired into `docs/make.jl` (lines 43, 87); no CSV/DataFrames dependency added to `docs/Project.toml` |
| 8 | Solve time, ADMM iteration count, and SOCP exactness are measured on the committed headline fixture at ~40x scale, against IEEE-13/123 baselines (SCALE-04/05) | FAILED | Every row for the true headline fixture (`ieee8500`, 4,875 buses) is `OOM_KILLED` or `not_attempted` at every density including the smallest (0.1, tried twice). Zero successful termination_status/admm_iters/exact_verdict values exist for this fixture. Real numbers exist only for the separate `ieee8500-mv` (2,521-bus, ~20x) control fixture, at its two lowest densities, and even there ADMM never reaches a clean converged consolidation (4 iters then `ERROR:ErrorException` or `budget_exceeded`) |
| 9 | The Clarabel-vs-SCS crossover point is identified by measurement rather than assumed (SCALE-04) | FAILED | SCS.jl was never installed in the measurement environment at any point across plans 25-02, 25-05, or 25-06. `scs_status` reads `scs_unavailable`/`not_requested`/`skipped_oom` on all 17 sweep rows, including the cheap IEEE-13/123 rows where installing/running SCS would have cost almost nothing. The dispatch code (`ext/TSODSOSCSExt.jl`) is real and correctly wired, but the crossover itself was never observed |

**Score:** 7/9 truths verified

### Deferred Items

Items not yet met but explicitly out of the current milestone's scope per REQUIREMENTS.md's own
`SCALE-STRETCH` carve-out (there is no Phase 26 in the v3.0 roadmap to receive this work
within-milestone).

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | `solve_admm`'s hardcoded `assert_socp_exact!(atol=1e-6)` still throws on a converged, consolidated IEEE-8500 point even after the D-13 connector fix (deferred-items.md item 3, open) | Future milestone (SCALE-STRETCH) | REQUIREMENTS.md: "SCALE-STRETCH: Performance engineering driven by the Phase 25 measurements ... Deliberately deferred: Phase 25 measures and characterizes the wall; optimizing it is separate work" |
| 2 | Reaching a memory-feasible, converged headline point requires architectural memory-footprint work (deferred-items.md item 4, open) | Future milestone (SCALE-STRETCH) | Same SCALE-STRETCH carve-out; Phase 25 is the final phase of the v3.0 milestone |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/reduce_ieee8500_impedances.jl` | Dependency-free OpenDSS -> table reduction, `--verify` mode | VERIFIED | Zero `using`/`import`; contains `reshape_near_zero_mv_edges!` (plan 25-07 fix) with documented threshold + assert-exactly-1 guard |
| `src/data/ieee8500_impedances.jl` | Generated committed impedance/load/capacitor tables | VERIFIED | Contains `IEEE8500_XFMR_EDGES`, `IEEE8500_MV_BRANCH_RX_OHMS`, `IEEE8500_CAPACITOR_KVAR`, `IEEE8500_LOAD_KW`, `IEEE8500_REGULATOR_EDGES` (43 entries) |
| `src/data/ieee8500.jl` | `ieee8500_modified()` + `ieee8500_mv_modified()` fixtures | VERIFIED | Both construct valid `Feeder`s; orchestrator-confirmed bus/branch counts, clean trees |
| `src/devices/FixedCapacitor.jl` | q-only fixed-injection device | VERIFIED | Real `contribute!` method, no JuMP variables, exported, consumed by `materialize.jl` |
| `src/experiments/materialize.jl` | IEEE-8500 population wiring (real per-load kW, capacitor buses) | VERIFIED | `build_population` branches on `feeder_sym in (:ieee8500, :ieee8500_mv)`, real per-bus kW lookup, capacitor `Aggregator`s appended, SX->X->MV walk for the MV-only control path with an explicit consistency assertion |
| `ext/TSODSOSCSExt.jl` | SCS weakdep extension, `alternative_optimizer(SCSChoice(), pc)` | ORPHANED (untested) | Code is structurally correct and wired to `Project.toml`'s `[weakdeps]`/`[extensions]`, but SCS.jl was never installed/loaded in any measurement session -- the dispatch has never actually been exercised end-to-end |
| `src/admm/solve_admm.jl` | `time_limit_s` kwarg, `:budget_exceeded` exit path | VERIFIED | Confirmed by `test/test_admm_timeout.jl` (part of the passing suite) and exercised live in the sweep (`ieee8500-mv` density=0.25 shows `budget_exceeded`) |
| `src/models/exactness.jl` | `socp_relaxation_gap(ctx)`, non-throwing sibling of `assert_socp_exact!` | VERIFIED | Used by both the noise-floor calibration mode and the literate page's live section |
| `scripts/benchmark_ieee8500.jl` | Fixture-parametrized density-sweep harness | VERIFIED | Drives all 17 committed rows; `--quick` mode backs the D-16 goldens |
| `test/test_benchmark_ieee8500.jl` | D-16 deterministic goldens (never wall time) | VERIFIED (design confirmed) | Deliberately a plain `Test.jl` script (not `@testitem`) per `25-05-PLAN.md`'s documented TestItemRunner-under-`--project=.` trap; orchestrator-confirmed 10/10 passing; not part of the TestItemRunner suite by design, correctly documented, not a silent gap |
| `results/ieee8500_benchmark/density_sweep_full.csv` | Full cross-fixture sweep, every attempted point present | VERIFIED (as an honesty artifact) but see truth #8 | 17 rows; duplicate `ieee8500` density=0.1 rows are a documented, intentional retry (see next section), not a silent drop |
| `docs/literate/ieee8500_scaling.jl` | Live-executed page + committed curve + characterization | VERIFIED | 266 lines; live section solves a real point; synthesis section characterizes the wall by size/conditioning/formulation |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `scripts/reduce_ieee8500_impedances.jl` | `src/data/ieee8500_impedances.jl` | `emit_output` writing committed const tables | WIRED | Table constants present and consumed downstream |
| `FixedCapacitor.contribute!` | `Aggregator.contribute!` | `hasproperty(res, :q_inject)` roll-up | WIRED | Confirmed in `materialize.jl`; DEV-05 sole-`:Rq`-writer invariant preserved per `test/test_ieee8500.jl` regression tests |
| `materialize.jl build_population` | `IEEE8500_LOAD_KW` | per-bus `Dict{Int,Float64}` real-kW path | WIRED | Direct lookup for `:ieee8500`; SX->X->MV walk with explicit `ArgumentError` guard for `:ieee8500_mv` |
| `ext/TSODSOSCSExt.jl` | `src/solver/factory.jl` seam | `alternative_optimizer(::SCSChoice, pc)` | WIRED but UNEXERCISED | Method exists and dispatches correctly by code inspection; never actually invoked with SCS loaded in any session that produced committed results |
| `docs/make.jl` | `docs/literate/ieee8500_scaling.jl` | literate-source tuple + page-title map | WIRED | Lines 43 and 87 of `docs/make.jl` |
| `docs/literate/ieee8500_scaling.jl` | `results/ieee8500_benchmark/density_sweep_full.csv` | Base-only `read_sweep_csv` | WIRED | Verified by reading the file directly; correctly `limit`-splits around the free-text `error_msg` column |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `docs/literate/ieee8500_scaling.jl` (precomputed section) | `sweep_rows` | `read_sweep_csv(results/ieee8500_benchmark/density_sweep_full.csv)` | Yes -- real measured/OOM rows, not static/empty | FLOWING |
| `docs/literate/ieee8500_scaling.jl` (live section) | `ctx`, `live_gap`, `live_elapsed_s` | `solve_welfare(feeder, ConvexBranchFlow(), live_aggs; ...)` | Yes -- a genuine live solve at doc-build time | FLOWING |
| `materialize.jl build_population(:ieee8500)` | `kw_pu_dict` | `IEEE8500_LOAD_KW` (generated from real vendored `Loads.dss` kW) | Yes | FLOWING |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|-----------------|-------------|--------|----------|
| SCALE-01 | 25-01, 25-03, 25-04 | Committed IEEE-8500 fixture, dependency-free ingestion, real bus count stated | SATISFIED | Fixture exists, provenance pinned, real per-load kW population wired |
| SCALE-02 | 25-03 | Multi-voltage-base per-unit ingestion, tripwires cleared honestly | SATISFIED | `PerUnit.jl` constants untouched; S_base decision documented |
| SCALE-03 | 25-04 | Non-modeled devices handled by stated assumption | SATISFIED | `FixedCapacitor` real and wired; D-11/D-13 documented. Note: `.planning/REQUIREMENTS.md`'s own checklist and traceability table still show SCALE-03 as unchecked/"Pending" despite this code-level evidence of completion -- a bookkeeping gap, not a code gap (see Anti-Patterns / Gaps Summary) |
| SCALE-04 | 25-02, 25-05, 25-06 | Benchmark deliverable: solve time/ADMM iters/memory measured, Clarabel-vs-SCS crossover identified, non-convergence reported honestly | BLOCKED (partial) | Non-convergence/OOM honestly reported (satisfied); solve time/ADMM iters measured only on the MV-only control fixture at low density, never the true headline fixture (unsatisfied); Clarabel-vs-SCS crossover never measured anywhere (unsatisfied). REQUIREMENTS.md itself marks this "Pending," consistent with this finding |
| SCALE-05 | 25-05, 25-06, 25-07 | SOCP exactness re-certified at scale with a fresh gate; failure characterized; literate page | BLOCKED (partial) | Fresh, non-inherited noise floor genuinely measured and characterized (satisfied); literate page live-executes and synthesizes honestly (satisfied); but exactness was only actually evaluated at the MV-only control fixture's smallest density, never at the true headline fixture (OOM before the gate could ever run) -- "re-certified at scale" is true only for the ~20x control point, not the ~40x headline point. REQUIREMENTS.md marks this "Pending," consistent with this finding |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/REQUIREMENTS.md` | 145, 149, 154, 225-227 | SCALE-03/04/05 checkboxes unchecked and traceability table marks them "Pending" | INFO | Bookkeeping only lags for SCALE-03 (code evidence shows it complete); for SCALE-04/05 it accurately reflects the partial completion this report independently found. Recommend updating REQUIREMENTS.md to reflect SCALE-03 as complete and SCALE-04/05 as explicitly partial (not silently left "Pending" without a note) once the gaps above are resolved or formally accepted |

No debt markers (`TBD`/`FIXME`/`XXX`) were found in any phase-25-modified file that were not either (a) part of a documented data-shaping decision's prose ("MODELING PLACEHOLDER" referring to the vendored source's own placeholder length value) or (b) an unrelated format-string literal (`XXXX` inside a `Printf`-style comment). No blocker-level debt markers found.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Fixture construction produces the documented bus/branch counts | (orchestrator pre-verified) `ieee8500_modified()` / `ieee8500_mv_modified()` | 4,875/4,874 and 2,521/2,520, both clean trees | PASS |
| Full project test suite is green modulo pre-existing, phase-25-unrelated failures | (orchestrator pre-verified) `Pkg.test()` | 29,760 passed; 3 errors + 1 failure confirmed reproducing at pre-phase baseline `6ffa252`; 2 further failures are local Aqua/CairoMakie drift, not phase-25 | PASS (no phase-25 regression) |
| `test/test_benchmark_ieee8500.jl`'s D-16 goldens | `julia --project=. test/test_benchmark_ieee8500.jl` | (orchestrator pre-verified) 10/10 pass | SKIP (re-run in this verification session timed out at 100s without concluding either way; not re-attempted given the orchestrator's direct prior confirmation and the deterministic, non-wall-time nature of the goldens) |
| `docs/make.jl` builds with the new page and no new CSV/DataFrames dependency | `grep CSV\|DataFrames docs/make.jl docs/Project.toml` | No matches | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes are declared by or relevant to this phase. SKIPPED (no probes).

### Human Verification Required

### 1. Accept or reject OOM-bounded non-measurement of the headline fixture

**Test:** Review `results/ieee8500_benchmark/density_sweep_full.csv`'s `ieee8500` rows and
`docs/literate/ieee8500_scaling.jl`'s "headline point, stated plainly" section.
**Expected:** A recorded decision: either (a) accept that the true 4,875-bus headline fixture's
solve time / ADMM iterations / exactness could not be measured on the available 15 GiB shared
machine and that this negative, honestly-reported result is this phase's final answer for those
three dimensions at 40x scale, or (b) commission a follow-up measurement on a machine with
materially more free RAM before considering SCALE-04/05 closed.
**Why human:** This is a resource/scope trade-off, not a code-correctness question.

### 2. Decide on the SCS crossover gap

**Test:** Review `ext/TSODSOSCSExt.jl` and the `scs_status` column of
`results/ieee8500_benchmark/density_sweep_full.csv`.
**Expected:** A decision to either (a) install SCS.jl and re-run at least the cheap IEEE-13/123
points plus one IEEE-8500-mv point to produce a real crossover measurement before closing
SCALE-04, or (b) formally accept the crossover as unmeasured for this milestone via an explicit
override/decision recorded in this VERIFICATION.md's frontmatter or REQUIREMENTS.md.
**Why human:** Whether "identified rather than assumed" can be waived is a scope decision, not a
code-correctness question -- though note this is unlike the OOM wall in that it is trivially
actionable (`Pkg.add("SCS")`) rather than environmentally blocked.

### Gaps Summary

Six of six plans (25-01 through 25-06) plus the authorized gap-closure task 25-07 are merged, and
the vast majority of this phase's engineering is genuinely substantive: the fixture is real and
provenance-tracked, per-unit ingestion is correct, the capacitor/regulator assumption handling is
real wired code (not a stub), the benchmark harness honestly reports every attempted point
including six OOM kills and two deliberately-skipped points, the SOCP-exactness noise floor was
freshly measured (never certificate-laundered from IEEE-13/123), and the literate page performs a
genuinely rigorous, honest synthesis of the wall it hit. This is a phase that clearly tried hard to
be honest about its own limits, and largely succeeded at that.

However, two of the roadmap goal's five explicitly named deliverables are not actually
delivered, and REQUIREMENTS.md's own bookkeeping (SCALE-04/05 still "Pending") agrees:

1. **The Clarabel-vs-SCS crossover was never measured, at any scale.** This is squarely within
   the phase's control (an open-source Julia package install) and is not excused by the shared
   machine's memory pressure. The requirement text is unconditional ("identified rather than
   assumed").
2. **The true ~40x headline fixture (4,875 buses) never produced a single successful
   measurement** of solve time, ADMM iteration count, or SOCP exactness -- every attempt at every
   density was OOM-killed or skipped. The numbers that DO exist for "IEEE-8500 scale" all come
   from the separate, smaller MV-only control fixture (~20x, not ~40x). This is honestly reported
   and well-characterized, but it means the goal's core promise -- an answer at the actual
   headline scale -- was not delivered, only a well-documented account of why it wasn't.

Both gaps are structured in this report's frontmatter for `/gsd:plan-phase --gaps` should the
researcher want a closure plan (e.g., install SCS and re-measure the cheap points; attempt the
headline fixture on a larger machine). Items 3 and 4 from `deferred-items.md` (the tolerance-gap
and memory-footprint architectural work) are correctly out of this phase's scope per
REQUIREMENTS.md's own `SCALE-STRETCH` carve-out and are not counted as gaps here.

---

_Verified: 2026-08-22T03:19:43Z_
_Verifier: Claude (gsd-verifier)_
