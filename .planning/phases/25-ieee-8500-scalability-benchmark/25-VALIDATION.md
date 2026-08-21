---
phase: 25
slug: ieee-8500-scalability-benchmark
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-20
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `25-RESEARCH.md` § Validation Architecture, with D-17's post-research revision applied
> (heavy runs are committed-artifact, not live-at-docs-build).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + `TestItems`/`TestItemRunner` (repo-established) |
| **Config file** | none dedicated — repo-wide `test/runtests.jl` + `@testitem` convention |
| **Quick run command** | `julia --project=. test/test_ieee8500.jl` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | quick ~seconds–low minutes (small density point only); full suite existing baseline |

> **TRAP — do not use `TestItemRunner` in a plan `<verify>` block.** Under `--project=.` the
> `julia -e '@run_package_tests'` idiom fails (recorded project lesson + v2.x milestone-audit debt).
> Every `<verify>` command must be a **direct `Test.jl` script**, as the quick command above is.

---

## Sampling Rate

- **After every task commit:** `julia --project=. test/test_ieee8500.jl` (fixture construction +
  invariants + the corrected-transformer-pu assertions)
- **After every plan wave:** full `test/` suite for this phase's new files. Density-sweep-scale runs
  belong to the harness / `docs` job, **never** the fast `test` job.
- **Before `/gsd:verify-work`:** full suite green AND the `docs` job green (page renders from committed
  results plus its cheap live slice, per revised D-17)
- **Max feedback latency:** 120 s for the quick command

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 25-01-01 | 01 | 1 | SCALE-01 | T-25-01 | Vendored source checksums match the committed provenance record; commit SHA pinned (not `master`) | unit | `sha256sum scripts/data/ieee8500/*` vs `25-DATA-PROVENANCE.md` | ❌ W0 | ⬜ pending |
| 25-01-02 | 01 | 1 | SCALE-01 | T-25-03 | Parallel-edge dedupe asserts identical then keeps one — never averages | unit | (exercised via Task 3's `--verify`) | ❌ W0 | ⬜ pending |
| 25-01-03 | 01 | 1 | SCALE-01 | T-25-02 | `--verify` pinned sanity check catches a wrong transformer reduction before commit | unit | `julia scripts/reduce_ieee8500_impedances.jl --verify` | ❌ W0 | ⬜ pending |
| 25-02-01 | 02 | 1 | SCALE-04 | T-25-05 | SCS UUID/version human-verified against the live registry before any [weakdeps] entry | manual | human checkpoint (registry pages) | ❌ W0 | ⬜ pending |
| 25-02-02 | 02 | 1 | SCALE-04 | T-25-05 | SCS reachable only via `alternative_optimizer`/`SCSChoice`, never a hard dependency | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 25-02-03 | 02 | 1 | SCALE-04 | T-25-06 | `solve_admm`'s wall-clock budget reports `:budget_exceeded` honestly instead of hanging | unit | `julia --project=. test/test_admm_timeout.jl` | ❌ W0 | ⬜ pending |
| 25-03-01 | 03 | 2 | SCALE-02 | T-25-07 | Multi-voltage-base per-unit ingestion at S_base=0.5 MVA; Feeder construction invariants pass at scale | unit | `julia --project=. -e '...ieee8500_modified()...'` | ❌ W0 | ⬜ pending |
| 25-03-02 | 03 | 2 | SCALE-01 | — | N/A | unit | `julia --project=. -e '...ieee8500_mv_modified()...'` | ❌ W0 | ⬜ pending |
| 25-03-03 | 03 | 2 | SCALE-02 | T-25-07 | Tripwire verdict explicit; corrected transformer pu values pinned, band never silently widened | unit | `julia --project=. test/test_ieee8500.jl` | ❌ W0 | ⬜ pending |
| 25-04-01 | 04 | 3 | SCALE-03 | — | N/A | unit | `grep` structural checks on FixedCapacitor.jl | ❌ W0 | ⬜ pending |
| 25-04-02 | 04 | 3 | SCALE-01 | T-25-09 | Real per-load kW drives population magnitude, never a tuned scalar; capacitor buses never add a second :Rq writer | unit | `julia --project=. -e '...build_population(...)...'` | ❌ W0 | ⬜ pending |
| 25-04-03 | 04 | 3 | SCALE-03 | T-25-10 | DEV-05 sole-`:Rq`-writer invariant preserved; IEEE-13/123 population byte-identical | unit | `julia --project=. test/test_ieee8500.jl` | ❌ W0 | ⬜ pending |
| 25-05-01 | 05 | 4 | SCALE-05 | T-25-12 | Per-fixture noise floor measured fresh, never reused from IEEE-13/123 (fast smoke on ieee13 gates the task; the full 5-rung ladder on ieee8500-mv/ieee8500 is the reported deliverable, not the automated verify) | unit | `julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee13 --tolerances 1e-6,1e-8` | ❌ W0 | ⬜ pending |
| 25-05-02 | 05 | 4 | SCALE-04 | T-25-11 | Harness cannot hang unbounded (D-18 timeout enforced); every point reported, none dropped | integration | `julia scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick` | ❌ W0 | ⬜ pending |
| 25-05-03 | 05 | 4 | SCALE-04 | — | N/A | integration | `julia --project=. test/test_benchmark_ieee8500.jl` | ❌ W0 | ⬜ pending |
| 25-06-01 | 06 | 5 | SCALE-05 | T-25-11 | Headline 4,873-bus point present and its outcome stated honestly, whatever it is | manual + integration | committed CSV + human-read SUMMARY | ❌ W0 | ⬜ pending |
| 25-06-02 | 06 | 5 | SCALE-05 | T-25-13/T-25-14 | Live slice bounded, never threatens the shared docs-job budget; headline outcome stated in page prose | docs | `julia --project=docs docs/make.jl` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs match the real plans (25-01 through 25-06) created by /gsd:plan-phase 25.*

---

## Wave 0 Requirements

- [ ] `scripts/reduce_ieee8500_impedances.jl` — with `--verify` self-check AND the
      **assert-identical-then-dedupe** step for the 3 confirmed parallel-edge collisions + 4 regulator
      banks (without it `assert_radial` throws)
- [ ] `src/data/ieee8500.jl` + generated `src/data/ieee8500_impedances.jl` — the two fixture builders
      (full MV+LV headline, MV-only control)
- [ ] `test/test_ieee8500.jl` — construction/invariant tests covering SCALE-01/02/03, including an
      explicit assertion on the **corrected** transformer per-unit values at `S_base = 0.5 MVA`
      (CT5 → r=3.00 / x=2.72 pu) so a regression to the placeholder formula fails loudly
- [ ] `ext/TSODSOSCSExt.jl` — new extension; its test must be gated on SCS being installed
- [ ] `scripts/benchmark_ieee8500.jl` — the harness, with a `--quick` mode affordable in CI, separate
      from the full density sweep
- [ ] Framework install: **none new** — existing `Test` + TestItems/TestItemRunner suffices

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The measured scaling curve is *scientifically* honest (non-convergent and timed-out points reported, not omitted) | SCALE-04 | Requires human judgement about reporting completeness; no assertion can prove an omission did not happen | Read the committed results table and the literate page side by side; confirm every attempted point appears with a status, including `budget exceeded` and non-convergent rows |
| The `IMPEDANCE_PU_MAX` verdict is *honest* rather than accommodated | SCALE-02 | The requirement is about reasoning, not a value | Confirm `S_base = 0.5 MVA` clears the band with no change to `src/units/PerUnit.jl` constants, and that the docstring states the 1 MVA non-comparability |
| Exactness tolerances are newly derived, not inherited | SCALE-05 | Anti-certificate-laundering is a provenance property | Confirm the committed `atol`/`rtol` trace to a measured noise floor on THIS fixture, with the tolerance ladder recorded |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] No `TestItemRunner` in any `<verify>` block (direct `Test.jl` only)
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
